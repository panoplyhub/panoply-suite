-- Hearth Hall (Modules/Alts, SPEC 20.2): every character you have played with Panoply Suite, in one
-- window, across the whole account. This file is the data: what is saved for each character, when
-- it is saved, and the questions the window asks of it (lists, totals, "which character has X").
--
-- Saved data (account-wide, PanoplySuiteDB.alts, format v1):
--   alts = { v = 1, realms = { [realm] = { [name] = record } } }
--   record = { name, realm, faction, race, raceFile, class, classFile, level, xp, xpMax, rested,
--              resting, money, zone, sub, t (last seen, time()), played = { total, level, at },
--              profs = { prim = { {name, rank, max}... }, sec = { ... } },
--              guide = { i, n, title, goal }, mail = { t, n, total, money, items = { [itemID] = n },
--              expires (0.9.5: when the first letter runs out), cod (0.9.5: letters to pay for) } }
--   NEW fields in 0.9.5 phase 4I (docs/specs/page-redesigns-02-muster.md; nothing above is renamed):
--     gear = { [inventory slot id] = item link }  what the character wore (the gear engine's saved-character source reads it)
--     plan = { key, from, name, topTree }  the talent plan it follows (the gear engine weighs a saved character with it)
--     ilvl (average item level of what it wore), hearth (its hearthstone's place), spec (the talent tree with the most points)
--     recipes = { [profession] = { recipe name, ... } }  the recipes its profession windows showed ("who can craft")
--     cds = { { name, prof, ready (time()), kind = "camp" | "legacy" | "prof" } }  cooldowns, as when it was last played
--     camp = { favor, rep, repValue, repMax }  WoW Forever: Merchant's Favor and the trade camp's standing
--     wellRested  WoW Forever: its Well Rested Legacy perk rank (raises the rested estimate)
--     lockouts = { { name, reset (time()), diff } }  its raid and dungeon lockouts
--     mail.letters = { { from, subject, money, cod, expires (time()), items = { itemID, ... } } }  one entry per letter
--     mail.ahSold, mail.ahExpired  letters from the auction house: sales paid out, items that did not sell
--   NEW key PanoplySuiteDB.musterGold = { v = 1, chars = { [realm] = { [name] = { { day, copper }, ... } } } }: one gold point per
--     character a day (the last of the day wins), written at login and logout, kept 35 days (the 30-day chart and the 7-day change).
-- Only the character being played is ever written, and only its own record. Bags and bank are not
-- copied: they stay in the Inventory store (Modules/Bags/Store.lua, PanoplySuiteDB.inventory) and are
-- read from it, so there is one version of the item counting. A character that has an Inventory
-- record but no Hearth Hall record yet (saved by an older Panoply Suite) still shows in the list.
--
-- Reads game APIs only (never moves, buys or uses anything).
local ADDON, Panoply = ...
local C = Panoply.Compat

local Alts = Panoply.Modules:Register({
  key = "alts", label = "Muster", icon = "Partner",
  desc = "All your characters in one window: level, rested, gold, professions, where they are, and what is in their bags, bank and mail. Search any item across them.",
  defaults = { hallSort = "level", hallPlayed = true, hallMail = true, hallRestGuess = true, hallMailDays = 3 },
  options = {
    { type = "check", key = "hallPlayed", label = "Ask the game for my played time at login",
      tip = "Once per login. The game's own \"Total time played\" chat lines are hidden for that one answer. /played still works as usual." },
    { type = "check", key = "hallMail", label = "Remember what is in my mailbox when I open it",
      tip = "Only the letters, items and gold you can already see at the mailbox, saved so your other characters can find them." },
    { type = "check", key = "hallRestGuess", label = "Estimate rested XP for characters that are offline",
      tip = "Shown with a ~. Based on the usual rule: 5% of a level per 8 hours in an inn or a city, a quarter of that elsewhere." },
    { type = "slider", key = "hallMailDays", label = "Warn about mail this many days before it runs out", min = 1, max = 7, step = 1, fmt = "%d",
      tip = "Muster's mail alert and the red days on its Mail tab." },
  },
})
Panoply.Alts = Alts
Alts.VERSION = 1
Alts.errors = {}
Alts.SORTS = { "level", "name", "gold", "played", "seen" }
Alts.SORT_LABELS = { level = "Level", name = "Name", gold = "Gold", played = "Played", seen = "Last seen" }
Alts.MAX_LETTERS = 50         -- letters remembered per mailbox (one row each on the Mail tab)
Alts.MAX_RECIPES = 400        -- recipe names remembered per profession
Alts.MAX_CDS = 20
Alts.GOLD_DAYS = 35           -- days of gold points kept per character
Alts.SLOW = 60                -- seconds between the slower readings (cooldowns, camp, lockouts) while playing
Alts.WELL_RESTED = 1225478    -- the Legacy perk (Modules/Legacy/Data.lua): +4% rested rate and cap a rank
Alts.DEDICATED_STUDY = 1225469
Alts.MAX_MAIL_ITEMS = 600     -- distinct items remembered per mailbox
Alts.MAX_PROFS = 12
Alts.MAX_MONEY = 100000000000  -- copper: 10 million gold, far past any cap

-------------------------------------------------------------------------------
-- Small helpers (pure; the tests call them directly)
-------------------------------------------------------------------------------
function Alts.Now() return _G.time and time() or 0 end

-- cut a string to n bytes without leaving half of a multi-byte character at the end
local function cut(s, n)
  if type(s) ~= "string" then return nil end
  s = s:gsub("%c", " ")
  if #s <= n then return s end
  local i = n
  while i > 0 do
    local b = s:byte(i + 1)
    if b and b >= 0x80 and b < 0xC0 then i = i - 1 else break end
  end
  return s:sub(1, i)
end
Alts.Cut = cut

-- a whole number inside [lo, hi], or nil when the game gave something else
local function num(v, lo, hi)
  v = C.Readable(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  v = math.floor(v + 0.5)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end
Alts.Num = num

local function section(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    Alts.errors[name] = tostring(err)
    Panoply:Debug("hearth hall:", name, err)
  else
    Alts.errors[name] = nil
  end
  return ok
end

-- copper -> "12,840g" (silver or copper when under 1 gold)
local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
Alts.Commas = commas
function Alts.MoneyShort(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper < 0 then copper = 0 end
  local g = math.floor(copper / 10000)
  if g > 0 then return commas(g) .. "g" end
  local s = math.floor(copper / 100)
  if s > 0 then return s .. "s" end
  return copper .. "c"
end
function Alts.MoneyFull(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper < 0 then copper = 0 end
  local g, s, k = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = commas(g) .. "g" end
  if s > 0 or g > 0 then out[#out + 1] = s .. "s" end
  out[#out + 1] = k .. "c"
  return table.concat(out, " ")
end

-- seconds -> "6d 2h", "14h 20m", "35m"
function Alts.Duration(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
  if d > 0 then return ("%dd %dh"):format(d, h) end
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return ("%dm"):format(m)
end

-- last seen: "just now", "5 min ago", "2 h ago", "3 d ago", "2 w ago", "4 mo ago"
function Alts.Ago(t, now)
  if not t or t <= 0 then return "not seen yet" end
  local s = (now or Alts.Now()) - t
  if s < 90 then return "just now" end
  if s < 90 * 60 then return ("%d min ago"):format(math.floor(s / 60 + 0.5)) end
  if s < 36 * 3600 then return ("%d h ago"):format(math.floor(s / 3600 + 0.5)) end
  if s < 14 * 86400 then return ("%d d ago"):format(math.floor(s / 86400 + 0.5)) end
  if s < 60 * 86400 then return ("%d w ago"):format(math.floor(s / (7 * 86400) + 0.5)) end
  return ("%d mo ago"):format(math.floor(s / (30 * 86400) + 0.5))
end

-- the game's own class colours (RAID_CLASS_COLORS) when present, else these standard values
local CLASS_FALLBACK = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
  DRUID = { 1, 0.49, 0.04 }, MONK = { 0, 1, 0.6 }, DEMONHUNTER = { 0.64, 0.19, 0.79 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
  EVOKER = { 0.2, 0.58, 0.5 },
}
function Alts.ClassColor(classFile)
  local t = _G.RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
  if t and t.r then return { t.r, t.g, t.b } end
  return CLASS_FALLBACK[classFile or ""] or { 0.9, 0.89, 0.87 }
end
function Alts.ColorCode(c)
  return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
function Alts.FactionColor(f)
  if f == "Horde" then return { 0.88, 0.39, 0.35 } end
  if f == "Alliance" then return { 0.42, 0.65, 0.94 } end
  return { 0.6, 0.65, 0.7 }
end

-- Rested XP as a share of the level bar. offline guess (SPEC 20.2): 5% of a level per 8 hours when
-- the character logged out in an inn or a city, a quarter of that anywhere else, never past 150%.
-- Returns percent (or nil when the character has no XP bar) and whether it was estimated.
-- 0.9.5 phase 4I: on WoW Forever the Well Rested Legacy perk (rec.wellRested, read from the game when it shows it) raises both the
-- rate and the cap by 4% a rank (Modules/Legacy/Data.lua). UNVERIFIED on the live client: the rates are the long-standing rule.
Alts.REST_CAP = 150
Alts.WELL_RESTED_STEP = 0.04
function Alts.RestBoost(rec)
  local r = type(rec) == "table" and tonumber(rec.wellRested) or 0
  if not C.IsForever() or r <= 0 then return 1 end
  return 1 + Alts.WELL_RESTED_STEP * math.min(5, math.floor(r))
end
function Alts.RestCap(rec) return Alts.REST_CAP * Alts.RestBoost(rec) end
function Alts.RestedPercent(rec, now, guess)
  if type(rec) ~= "table" or not rec.xpMax or rec.xpMax <= 0 then return nil end
  local pct = (rec.rested or 0) / rec.xpMax * 100
  local guessed = false
  local boost = Alts.RestBoost(rec)
  if guess and rec.t and now and now > rec.t then
    local hours = (now - rec.t) / 3600
    local gain = hours * (rec.resting and (5 / 8) or (5 / 32)) * boost
    -- 0.9.5 phase 17 (spec 02: rested shows an estimate marked ~): away more than a minute is an estimate, however small the gain
    -- (it waited for a 1% gain: 1.6 hours in an inn, 6.4 outside, shown without the ~ until then)
    if hours * 60 >= 1 then pct, guessed = pct + gain, true end
  end
  return math.max(0, math.min(Alts.REST_CAP * boost, pct)), guessed
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------
-- create: only a save makes the saved table. A read (the roster, search, "who can craft" for the gear engine on the Class page) before
-- anything was saved gets an empty table that is not kept, so reading never adds a saved key (0.9.5 phase 17).
function Alts:Data(create)
  local db = Panoply.db
  if not db then return nil end
  local a = db.alts
  if type(a) ~= "table" then
    if not create then return { v = Alts.VERSION, realms = {} } end
    a = { v = Alts.VERSION, realms = {} } db.alts = a
  end
  if type(a.realms) ~= "table" then a.realms = {} end
  if a.v == nil then a.v = Alts.VERSION end
  return a
end

-- A save made by a NEWER Panoply Suite (downgrade): read what we understand, never write.
function Alts:ReadOnly()
  local a = Panoply.db and Panoply.db.alts
  return type(a) == "table" and type(a.v) == "number" and a.v > Alts.VERSION
end

function Alts:Rec(realm, name, create)
  local a = self:Data(create)
  if not a or type(realm) ~= "string" or type(name) ~= "string" then return nil end
  local r = a.realms[realm]
  if type(r) ~= "table" then
    if not create then return nil end
    r = {} a.realms[realm] = r
  end
  local rec = r[name]
  if type(rec) ~= "table" then
    if not create then return nil end
    rec = {} r[name] = rec
  end
  return rec
end

function Alts:Me()
  local p = C.PlayerInfo()
  if not (p.name and p.realm) or p.name == "" or p.realm == "" then return nil end
  return p.realm, p.name, p
end

function Alts:MineRec(create)
  local realm, name = self:Me()
  if not realm then return nil end
  return self:Rec(realm, name, create), realm, name
end

-------------------------------------------------------------------------------
-- Saving the character being played
-------------------------------------------------------------------------------
local function setIf(rec, key, v) if v ~= nil then rec[key] = v end end

-- first: the first save of this login; final: the save at logout (both also log a gold point)
function Alts:Collect(first, final)
  if not self.active or self:ReadOnly() then return false end
  local realm, name, p = self:Me()
  if not realm then return false end
  local rec = self:Rec(realm, name, true)
  if not rec then return false end
  rec.v = Alts.VERSION
  rec.name, rec.realm = cut(name, 40), cut(realm, 60)
  section("identity", function()
    setIf(rec, "faction", cut(p.faction, 12))
    setIf(rec, "race", cut(p.race, 40)); setIf(rec, "raceFile", cut(p.raceFile, 40))
    setIf(rec, "class", cut(p.class, 40)); setIf(rec, "classFile", cut(p.classFile, 40))
  end)
  section("progress", function()
    -- only what the game shows now: a level or XP number it hides (WoW Forever) leaves the last good one in the record
    local level, xp, xpMax, rested = C.XPKnown()
    setIf(rec, "level", num(level, 1, 200))
    setIf(rec, "xp", num(xp, 0, 1e9)); setIf(rec, "xpMax", num(xpMax, 0, 1e9)); setIf(rec, "rested", num(rested, 0, 1e9))
    local resting = _G.IsResting and C.Readable(IsResting())
    if resting ~= nil then rec.resting = resting and true or false end
    -- at the level cap there is no XP bar: nothing to rest
    local cap = _G.GetMaxPlayerLevel and num(select(2, pcall(GetMaxPlayerLevel))) or num(_G.MAX_PLAYER_LEVEL)
    if cap and rec.level and rec.level >= cap then rec.xpMax, rec.rested = 0, 0 end
  end)
  section("gold", function() setIf(rec, "money", num(C.MoneyKnown(), 0, Alts.MAX_MONEY)) end)   -- hidden: the last good amount stays
  section("where", function()
    local z, s = C.ZoneText()
    if type(z) == "string" and z ~= "" then rec.zone, rec.sub = cut(z, 60), cut(s or "", 60) end
  end)
  section("professions", function()
    local PD, pd = Panoply.ProfDetect, Panoply.ProfData
    if not (PD and pd and PD.Scan and pd.ORDER) then return end
    local known = PD:Scan()
    local prim, sec = {}, {}
    for _, pname in ipairs(pd.ORDER) do
      local k = known[pname]
      if k and #prim + #sec < Alts.MAX_PROFS then
        local e = { cut(pname, 40), num(k.rank, 0, 1000) or 0, num(k.max, 0, 1000) or 0 }
        if pd.SECONDARY and pd.SECONDARY[pname] then sec[#sec + 1] = e else prim[#prim + 1] = e end
      end
    end
    rec.profs = { prim = prim, sec = sec }
  end)
  section("guide", function()
    local E = Panoply.Engine
    if Panoply:PlayAlong() or not (E and E.steps and #E.steps > 0) then rec.guide = nil return end
    local idx = num(E.index, 1, #E.steps) or 1
    local step = E.steps[idx]
    local goal = Panoply.Planner and Panoply.Planner.lastStats and num(Panoply.Planner.lastStats.goalLevel, 1, 200)
    rec.guide = { i = idx, n = #E.steps, title = cut(type(step) == "table" and type(step.title) == "string" and step.title or "", 90), goal = goal }
  end)
  -- the slower readings (gear, recipes, spellbook, cooldowns, lockouts): once a minute while playing, and always at logout. 0.9.5 phase
  -- 17: gear and recipes moved here from every save (a save runs every few seconds while XP, gold or the zone change)
  local t = Alts.Now()
  if final or not self.slowAt or t - self.slowAt >= Alts.SLOW then
    self.slowAt = t
    section("gear", function() Alts:ReadGear(rec) end)
    section("recipes", function() Alts:ReadRecipes(rec) end)
    section("hearth", function() local h = C.BindLocation() if type(h) == "string" and h ~= "" then rec.hearth = cut(h, 60) end end)
    section("spec", function() local sp = Alts.ReadSpec() if sp then rec.spec = cut(sp, 40) end end)
    section("cooldowns", function() Alts:ReadCooldowns(rec) end)
    section("camp", function() Alts:ReadCamp(rec) end)
    section("lockouts", function() Alts:ReadLockouts(rec) end)
  end
  rec.t = t
  if first or final then section("goldlog", function() Alts:LogGold(realm, name, rec.money) end) end
  Panoply:Fire("ALTS_CHANGED", realm, name)
  return true
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4I: the readings Muster's detail tabs need (each a NEW field of the record; see the top of the file)
-------------------------------------------------------------------------------
Alts.GEAR_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
Alts.ILVL_SKIP = { [4] = true, [19] = true }        -- shirt and tabard do not count toward the average item level
function Alts:ReadGear(rec)
  local f = _G.GetInventoryItemLink
  if type(f) ~= "function" then return end
  local gear, sum, n = {}, 0, 0
  for _, sid in ipairs(Alts.GEAR_SLOTS) do
    local ok, link = pcall(f, "player", sid)
    link = ok and C.Readable(link)
    if type(link) == "string" and link:find("item:", 1, true) then
      gear[sid] = cut(link, 300)
      if not Alts.ILVL_SKIP[sid] then
        local i = C.ItemInfo(link)
        local lv = i and num(i.ilvl, 0, 1000)
        if lv and lv > 0 then sum, n = sum + lv, n + 1 end
      end
    end
  end
  rec.gear = gear
  rec.ilvl = n > 0 and math.floor(sum / n + 0.5) or rec.ilvl
  -- the plan it follows, as the gear engine weighs a saved character (Modules/Gear/Gear.lua savedContext: { key, from, name, topTree })
  local ST = Panoply.SpecTrainer
  if ST and ST.Tracked then
    local ok, plan = pcall(ST.Tracked, ST)
    if ok and type(plan) == "table" and plan.key then
      local top
      if type(plan.points) == "table" and ST.RanksAt and rec.classFile then
        local ok2, _, spent = pcall(ST.RanksAt, ST, rec.classFile, plan.points)
        if ok2 and type(spent) == "table" then
          local best = 0
          for i, k in ipairs(spent) do if (tonumber(k) or 0) > best then best, top = k, i end end
        end
      end
      rec.plan = { key = cut(tostring(plan.key), 80), from = type(plan.from) == "string" and cut(plan.from, 20) or nil,
        name = type(plan.name) == "string" and cut(plan.name, 80) or nil, topTree = top }
    end
  end
end

-- the recipes the profession windows showed this character (Engine/Professions.lua keeps them per character), copied so the other
-- characters can ask "who can craft"
function Alts:ReadRecipes(rec)
  local k = Panoply.cdb and Panoply.cdb.knownRecipes
  if type(k) ~= "table" then return end
  local out, any = {}, false
  for prof, list in pairs(k) do
    if type(prof) == "string" and type(list) == "table" then
      local names = {}
      for nm, v in pairs(list) do if v and type(nm) == "string" and #names < Alts.MAX_RECIPES then names[#names + 1] = cut(nm, 80) end end
      table.sort(names)
      if #names > 0 then out[cut(prof, 40)] = names any = true end
    end
  end
  if any then rec.recipes = out end
end

-- the talent tree with the most points ("Beast Mastery"); nil when no points are spent or the game does not say
function Alts.ReadSpec()
  local f, nf = _G.GetTalentTabInfo, _G.GetNumTalentTabs
  if type(f) ~= "function" then return nil end
  local okN, tabs = pcall(nf or function() return 3 end)
  tabs = okN and num(tabs, 0, 5) or 3
  local best, bestN = nil, 0
  for i = 1, tabs do
    local r = { pcall(f, i) }
    if r[1] then
      -- Classic answers name, icon, points spent; newer clients id, name, description, icon, points spent, ...
      local name, pts = r[2], r[4]
      if type(r[2]) == "number" and type(r[3]) == "string" then name, pts = r[3], r[6] end
      pts = num(pts, 0, 100) or 0
      name = C.Readable(name)
      if type(name) == "string" and pts > bestN then best, bestN = name, pts end
    end
  end
  return best
end

local function readyAt(cd)
  if type(cd) ~= "number" then return nil end
  return math.floor(Alts.Now() + math.max(0, cd) + 0.5)
end
-- cooldowns the game says this character has: camp objects (WoW Forever), Dedicated Study (Legacy), profession recipes with a cooldown
function Alts:ReadCooldowns(rec)
  local PC, PD, PR = Panoply.ProfCamp, Panoply.ProfData, Panoply.Professions
  if not (PC and PC.Cooldown) then return end
  local out, seen = {}, {}
  local function add(name, prof, kind, cd)
    local r = readyAt(cd)
    if not r or #out >= Alts.MAX_CDS then return end
    local key = (prof or "") .. "\1" .. r          -- transmutes share one cooldown: list it once
    if kind == "prof" and seen[key] then return end
    seen[key] = true
    out[#out + 1] = { name = cut(name, 60), prof = prof and cut(prof, 40), ready = r, kind = kind }
  end
  local profs = {}
  for _, q in ipairs(rec.profs and rec.profs.prim or {}) do profs[#profs + 1] = { q[1], q[2] } end
  for _, q in ipairs(rec.profs and rec.profs.sec or {}) do profs[#profs + 1] = { q[1], q[2] } end
  local PF = Panoply.ProfForever
  if C.IsForever() and PF and PF.CampOf and PC.Snapshot then
    local snap = PC:Snapshot()
    for _, pr in ipairs(profs) do
      for _, o in ipairs(PF.CampOf(pr[1]) or {}) do
        local state, cd = PC:ObjectState(o, pr[2], snap)
        if state == "known" then add(o.name, pr[1], "camp", cd) end
      end
    end
  end
  local L = Panoply.Legacy
  if L and L.Here and L:Here() and L.Actual then
    local ok, actual = pcall(L.Actual, L)
    if ok and type(actual) == "table" and (tonumber(actual[Alts.DEDICATED_STUDY]) or 0) > 0 then
      add("Dedicated Study", nil, "legacy", PC:Cooldown("Dedicated Study"))
    end
  end
  if type(PD) == "table" and PR and PR.KnowsRecipe then
    for _, pr in ipairs(profs) do
      local d = PD[pr[1]]
      for _, r in ipairs(type(d) == "table" and d.recipes or {}) do
        if r.cooldown and PR:KnowsRecipe(pr[1], r) then add(r.name, pr[1], "prof", PC:Cooldown(r.name)) end
      end
    end
  end
  rec.cds = out
end

-- WoW Forever: Merchant's Favor and the trade camp's standing, as the Professions page reads them; the Well Rested perk rank
function Alts:ReadCamp(rec)
  if not C.IsForever() then return end
  local PC = Panoply.ProfCamp
  if PC and PC.Snapshot then
    local snap = PC:Snapshot()
    local fav = snap.favor
    if type(fav) == "table" then fav = fav.quantity or fav.amount or fav.count end
    local rep = snap.rep
    rec.camp = { favor = num(fav, 0, 1e9), rep = type(rep) == "table" and cut(rep.standing, 30) or nil,
      repValue = type(rep) == "table" and num(rep.value, 0, 1e9) or nil, repMax = type(rep) == "table" and num(rep.max, 0, 1e9) or nil }
  end
  local L = Panoply.Legacy
  if L and L.Here and L:Here() and L.Actual then
    local ok, actual = pcall(L.Actual, L)
    if ok and type(actual) == "table" then rec.wellRested = num(actual[Alts.WELL_RESTED], 0, 5) or 0 end
  end
end

-- raid and dungeon lockouts (GetSavedInstanceInfo): the ones that are still locked
function Alts:ReadLockouts(rec)
  local nf, f = _G.GetNumSavedInstances, _G.GetSavedInstanceInfo
  if type(nf) ~= "function" or type(f) ~= "function" then return end
  local ok, n = pcall(nf)
  n = ok and num(n, 0, 100) or 0
  local out = {}
  for i = 1, n do
    local okI, name, _, reset, diff, locked = pcall(f, i)
    reset = okI and num(reset, 0, 1e8)
    if okI and type(C.Readable(name)) == "string" and reset and reset > 0 and C.Readable(locked) ~= false then
      out[#out + 1] = { name = cut(C.Readable(name), 60), reset = math.floor(Alts.Now() + reset), diff = num(diff, 0, 100) }
    end
  end
  rec.lockouts = out
end

-------------------------------------------------------------------------------
-- Gold over time (NEW key PanoplySuiteDB.musterGold): one point a character a day
-------------------------------------------------------------------------------
Alts.DAY = 86400
function Alts.Day(t) return math.floor((t or Alts.Now()) / Alts.DAY) end
function Alts:GoldLog(create)
  local db = Panoply.db
  if not db then return nil end
  local g = db.musterGold
  if type(g) ~= "table" or type(g.chars) ~= "table" then
    if not create then return nil end
    g = { v = 1, chars = {} } db.musterGold = g
  end
  return g
end
function Alts:LogGold(realm, name, copper)
  copper = num(copper, 0, Alts.MAX_MONEY)
  if not copper or self:ReadOnly() then return false end
  local g = self:GoldLog(true)
  g.chars[realm] = type(g.chars[realm]) == "table" and g.chars[realm] or {}
  local list = type(g.chars[realm][name]) == "table" and g.chars[realm][name] or {}
  g.chars[realm][name] = list
  local d = Alts.Day()
  local last = list[#list]
  if type(last) == "table" and last[1] == d then last[2] = copper else list[#list + 1] = { d, copper } end
  while #list > 0 and (type(list[1]) ~= "table" or (tonumber(list[1][1]) or 0) < d - Alts.GOLD_DAYS) do table.remove(list, 1) end
  return true
end
-- a character's gold at the end of day d: its last point on or before d; before its first point, that first point (nothing is known
-- about earlier days, so the line is drawn flat rather than rising from nothing)
local function goldOn(list, d)
  local v, first
  for _, pt in ipairs(list) do
    if type(pt) == "table" and tonumber(pt[1]) then
      first = first or tonumber(pt[2])
      if pt[1] <= d then v = tonumber(pt[2]) end
    end
  end
  return v or first
end
-- The chart: days (oldest first, `days` of them ending today) and, per character, its gold on each day (today: its saved gold now).
-- A character with no points yet (saved before 0.9.5, or never logged in since) is drawn flat at its saved gold.
-- Returns { days = { d, ... }, series = { { realm, name, classFile, values = { ... } } }, totals = { ... } }
function Alts:GoldSeries(days)
  days = days or 30
  local today = Alts.Day()
  local out = { days = {}, series = {}, totals = {} }
  for i = days - 1, 0, -1 do out.days[#out.days + 1] = today - i end
  local g = self:GoldLog(false)
  for _, e in ipairs(self:List()) do
    local list = g and type(g.chars[e.realm]) == "table" and g.chars[e.realm][e.name]
    local s = { realm = e.realm, name = e.name, classFile = e.classFile, values = {} }
    for i, d in ipairs(out.days) do
      local v
      if type(list) == "table" and #list > 0 then v = goldOn(list, d) else v = e.money end
      if d == today then v = e.money end
      s.values[i] = v or 0
      out.totals[i] = (out.totals[i] or 0) + (v or 0)
    end
    out.series[#out.series + 1] = s
  end
  table.sort(out.series, function(a, b) return (a.values[#a.values] or 0) > (b.values[#b.values] or 0) end)
  return out
end
-- the account's gold now and its change over the last `n` days (nil until some character has a point at least that old)
function Alts:GoldChange(n)
  n = n or 7
  local s = self:GoldSeries(n + 1)
  local first, last = s.totals[1] or 0, s.totals[#s.totals] or 0
  local g = self:GoldLog(false)
  local any = false
  for _, chars in pairs(g and g.chars or {}) do
    for _, list in pairs(type(chars) == "table" and chars or {}) do
      if type(list) == "table" and type(list[1]) == "table" and (tonumber(list[1][1]) or 1e12) <= s.days[1] then any = true end
    end
  end
  return last, any and (last - first) or nil
end

-- Coalesce bursts of events (XP ticks, gold, zoning) into one save a few seconds later.
Alts.DELAY = 5
function Alts:Touch()
  if not self.active or self.pending then return end
  self.pending = true
  C.After(Alts.DELAY, function()
    Alts.pending = false
    if Alts.active then Alts:Collect() end
  end)
end

-------------------------------------------------------------------------------
-- Played time. RequestTimePlayed makes the game print two chat lines; for the one request
-- Hearth Hall makes per login those lines are hidden (the chat windows stop listening for the
-- answer, then listen again as soon as it arrives, or after 8 s if it never does).
-------------------------------------------------------------------------------
function Alts:MuteTimePlayed(on)
  if on then
    if self.muted then return end
    self.muted = {}
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
      local cf = _G["ChatFrame" .. i]
      if cf and cf.UnregisterEvent and cf.IsEventRegistered and cf:IsEventRegistered("TIME_PLAYED_MSG") then
        self.muted[#self.muted + 1] = cf
        pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG")
      end
    end
  elseif self.muted then
    for _, cf in ipairs(self.muted) do pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
    self.muted = nil
  end
end

function Alts:RequestPlayed()
  if not self.active or self.askedPlayed or Panoply.db.hallPlayed == false then return false end
  local f = _G.RequestTimePlayed
  if type(f) ~= "function" then return false end
  self.askedPlayed = true
  self:MuteTimePlayed(true)
  local ok = pcall(f)
  if not ok then self:MuteTimePlayed(false) return false end
  C.After(8, function() Alts:MuteTimePlayed(false) end)
  return true
end

function Alts:OnPlayed(total, levelTime)
  self:MuteTimePlayed(false)
  if not self.active or self:ReadOnly() then return end
  local rec = self:MineRec(true)
  if not rec then return end
  local t = num(total, 0)
  if not t then return end
  rec.played = { total = t, level = num(levelTime, 0) or 0, at = Alts.Now() }
  Panoply:Fire("ALTS_CHANGED")
end

-- played time as shown: the saved total, plus the time since it was reported for the character
-- being played (it keeps counting while you are online)
function Alts.PlayedNow(entry, now)
  local pl = entry and entry.rec and entry.rec.played
  if type(pl) ~= "table" or not pl.total then return nil end
  if entry.me and pl.at and now and now > pl.at then return pl.total + (now - pl.at) end
  return pl.total
end

-------------------------------------------------------------------------------
-- Mail: the mailbox only answers while it is open
-------------------------------------------------------------------------------
function Alts:ReadMail()
  if not (self.active and self.mailOpen) or Panoply.db.hallMail == false or self:ReadOnly() then return false end
  local n, total
  do
    local f = _G.GetInboxNumItems
    if type(f) ~= "function" then return false end
    local ok, a, b = pcall(f)
    if not ok then return false end
    n, total = tonumber(C.Readable(a)), tonumber(C.Readable(b))
  end
  if not n then return false end
  local rec = self:MineRec(true)
  if not rec then return false end
  -- the items: one version of the reading (Engine/ProfGuide.lua ScanMail fills Panoply.cdb.mailItems)
  local G = Panoply.ProfGuide
  if G and G.ScanMail then pcall(G.ScanMail, G) end
  local items, count = {}, 0
  for id, c in pairs((Panoply.cdb and Panoply.cdb.mailItems) or {}) do
    id, c = tonumber(id), num(c, 1, 1000000)
    if id and c and count < Alts.MAX_MAIL_ITEMS then items[id] = c count = count + 1 end
  end
  -- the gold waiting in letters; 0.9.5 (NEW fields, phase 4A3 alerts): when the first letter runs out (the game's days left) and how
  -- many letters are cash on delivery
  local money, soonest, cod = 0, nil, 0
  local letters, ahSold, ahExpired = {}, 0, 0
  local t = Alts.Now()
  local hf = _G.GetInboxHeaderInfo
  if type(hf) == "function" then
    for i = 1, n do
      local ok, _, _, from, subject, m, c, days, hasItem = pcall(hf, i)
      m = ok and num(m, 0, Alts.MAX_MONEY)
      if m then money = money + m end
      local codAmount = ok and num(c, 0, Alts.MAX_MONEY) or 0
      if codAmount > 0 then cod = cod + 1 end
      local d = ok and tonumber(C.Readable(days))   -- a fraction of a day matters here: not rounded
      if d and (d ~= d or d < 0 or d > 31) then d = nil end
      if d and (not soonest or d < soonest) then soonest = d end
      -- 0.9.5 phase 4I (NEW fields): one row a letter for the Mail tab, and the auction house's letters for the alerts
      if ok then
        subject = C.Readable(subject)
        local ah = Alts.AuctionMail(subject)
        if ah == "sold" then ahSold = ahSold + 1 elseif ah == "expired" then ahExpired = ahExpired + 1 end
        if #letters < Alts.MAX_LETTERS then
          local ids = {}
          if (num(hasItem, 0, 16) or 0) > 0 then ids = Alts.LetterItems(i) end
          letters[#letters + 1] = { from = cut(C.Readable(from), 40), subject = cut(subject, 90), money = m or 0, cod = codAmount,
            expires = d and math.floor(t + d * 86400) or nil, items = ids, ah = ah }
        end
      end
    end
  end
  rec.mail = { t = t, n = n, total = num(total, 0) or n, money = money, items = items,
    expires = soonest and math.floor(t + soonest * 86400) or nil, cod = cod, letters = letters, ahSold = ahSold, ahExpired = ahExpired }
  Panoply:Fire("ALTS_CHANGED")
  return true
end

-- The game's own mail subjects for the auction house (its global strings, never typed English): "sold", "expired" or nil.
-- A client that lacks a string matches nothing.
Alts.AH_SUBJECTS = { sold = { "AUCTION_SOLD_MAIL_SUBJECT" }, expired = { "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT" } }
local function subjectPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
  p = p:gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+")
  return "^" .. p .. "$"
end
function Alts.AuctionMail(subject)
  if type(subject) ~= "string" then return nil end
  for kind, names in pairs(Alts.AH_SUBJECTS) do
    for _, g in ipairs(names) do
      local pat = subjectPattern(rawget(_G, g))
      if pat and subject:find(pat) then return kind end
    end
  end
  return nil
end
-- the item ids attached to one letter (at most 16)
function Alts.LetterItems(i)
  local out = {}
  local lf, gf = _G.GetInboxItemLink, _G.GetInboxItem
  for a = 1, (_G.ATTACHMENTS_MAX_RECEIVE or 16) do
    local id
    if type(lf) == "function" then
      local ok, link = pcall(lf, i, a)
      id = ok and C.ItemIDFromLink(C.Readable(link))
    end
    if not id and type(gf) == "function" then
      local ok, name, itemID = pcall(gf, i, a)
      if ok and type(C.Readable(itemID)) == "number" then id = C.Readable(itemID) end
    end
    if id then out[#out + 1] = id end
  end
  return out
end

function Alts:TouchMail()
  if not self.active or self.mailPending then return end
  self.mailPending = true
  C.After(0.5, function()
    Alts.mailPending = false
    Alts:ReadMail()
  end)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "PLAYER_MONEY",
                      "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "SKILL_LINES_CHANGED" }) do
  Alts:On(ev, function() Alts:Touch() end)
end
for _, ev in ipairs({ "PROF_UPDATED", "PROFS_DETECTED", "STEP_CHANGED", "PLAN_ADOPTED", "LEVEL_CHANGED", "STEPS_CHANGED" }) do
  Alts:Listen(ev, function() Alts:Touch() end)
end
Alts:On("TIME_PLAYED_MSG", function(_, total, levelTime) Alts:OnPlayed(total, levelTime) end)
Alts:On("MAIL_SHOW", function() Alts.mailOpen = true Alts:TouchMail() end)
Alts:On("MAIL_INBOX_UPDATE", function() if Alts.mailOpen then Alts:TouchMail() end end)
Alts:On("MAIL_CLOSED", function() Alts.mailOpen = false end)
-- the last word before the game saves its files: no timers run at logout, so save now
Alts:On("PLAYER_LOGOUT", function() Alts:Collect(false, true) end)

function Alts.Enable(self)
  self.pending, self.mailPending = false, false
  -- professions and the route are detected a moment after the modules start: first save then
  C.After(3, function() if Alts.active then Alts:Collect(true) end end)
  C.After(10, function() Alts:RequestPlayed() end)
end
function Alts.Disable(self)
  self:MuteTimePlayed(false)
  if self.Hide then self:Hide() end
end

-------------------------------------------------------------------------------
-- Questions for the window
-------------------------------------------------------------------------------
-- Every character as { realm, name, rec, me, stub, level, money, t, classFile, faction }.
-- stub = known only from saved bags (before Hearth Hall existed): level and the rest are unknown.
function Alts:List()
  local out, seen = {}, {}
  local meRealm, meName = self:Me()
  local a = self:Data()
  local function key(realm, name) return realm .. "\1" .. name end
  if a then
    for realm, chars in pairs(a.realms) do
      if type(chars) == "table" then
        for name, rec in pairs(chars) do
          if type(rec) == "table" and type(name) == "string" and type(realm) == "string" then
            out[#out + 1] = { realm = realm, name = name, rec = rec, me = (realm == meRealm and name == meName),
              level = tonumber(rec.level), money = tonumber(rec.money) or 0, t = tonumber(rec.t) or 0,
              classFile = rec.classFile, faction = rec.faction }
            seen[key(realm, name)] = true
          end
        end
      end
    end
  end
  for realm, chars in pairs((Panoply.db and Panoply.db.inventory) or {}) do
    if type(chars) == "table" then
      for name, c in pairs(chars) do
        if type(c) == "table" and type(name) == "string" and not seen[key(realm, name)] then
          local rec = { name = name, realm = realm, classFile = c.class, faction = c.faction, money = c.money, t = c.t }
          out[#out + 1] = { realm = realm, name = name, rec = rec, stub = true, me = (realm == meRealm and name == meName),
            level = nil, money = tonumber(c.money) or 0, t = tonumber(c.t) or 0, classFile = c.class, faction = c.faction }
        end
      end
    end
  end
  return out
end

local SORTERS = {
  level = function(a, b)
    if (a.level or -1) ~= (b.level or -1) then return (a.level or -1) > (b.level or -1) end
    return a.name < b.name
  end,
  name = function(a, b) return a.name:lower() < b.name:lower() end,
  gold = function(a, b)
    if a.money ~= b.money then return a.money > b.money end
    return a.name < b.name
  end,
  played = function(a, b)
    local pa = type(a.rec and a.rec.played) == "table" and tonumber(a.rec.played.total) or -1
    local pb = type(b.rec and b.rec.played) == "table" and tonumber(b.rec.played.total) or -1
    if pa ~= pb then return pa > pb end
    return a.name < b.name
  end,
  seen = function(a, b)
    -- the one being played counts as newest
    local ta, tb = a.me and math.huge or a.t, b.me and math.huge or b.t
    if ta ~= tb then return ta > tb end
    return a.name < b.name
  end,
}

-- Realms (yours first, then A to Z), each with its characters in the chosen order and its gold.
-- Returns groups, account gold, character count.
function Alts:Groups(sortKey)
  local sorter = SORTERS[sortKey or (Panoply.db and Panoply.db.hallSort) or "level"] or SORTERS.level
  local meRealm = self:Me()
  local by, order = {}, {}
  local total, count = 0, 0
  for _, e in ipairs(self:List()) do
    local g = by[e.realm]
    if not g then g = { realm = e.realm, chars = {}, gold = 0 } by[e.realm] = g order[#order + 1] = g end
    g.chars[#g.chars + 1] = e
    g.gold = g.gold + e.money
    total, count = total + e.money, count + 1
  end
  table.sort(order, function(a, b)
    if (a.realm == meRealm) ~= (b.realm == meRealm) then return a.realm == meRealm end
    return a.realm:lower() < b.realm:lower()
  end)
  for _, g in ipairs(order) do table.sort(g.chars, sorter) end
  return order, total, count
end

function Alts:Find(realm, name)
  for _, e in ipairs(self:List()) do if e.realm == realm and e.name == name then return e end end
  return nil
end

-- Forget one character: Panoply Suite's saved record of it (this record and the saved bags and bank),
-- nothing in the game. The character being played cannot be forgotten (it would come straight back).
function Alts:Forget(realm, name)
  local meRealm, meName = self:Me()
  if realm == meRealm and name == meName then return false, "You are playing this character." end
  if self:ReadOnly() then return false, "These records were saved by a newer Panoply Suite." end
  local a = self:Data()
  local gone = false
  if a and type(a.realms[realm]) == "table" and a.realms[realm][name] ~= nil then
    a.realms[realm][name] = nil
    if next(a.realms[realm]) == nil then a.realms[realm] = nil end
    gone = true
  end
  local inv = Panoply.db and Panoply.db.inventory
  if inv and type(inv[realm]) == "table" and inv[realm][name] ~= nil then
    inv[realm][name] = nil
    if next(inv[realm]) == nil then inv[realm] = nil end
    if Panoply.Inventory then Panoply.Inventory.cache = nil end
    gone = true
  end
  if gone then Panoply:Fire("ALTS_CHANGED") Panoply:Fire("INVENTORY_CHANGED", "forget") end
  return gone
end

-------------------------------------------------------------------------------
-- What is in bags, bank and mail
-------------------------------------------------------------------------------
-- Names for items the game has not cached yet: the link saved with the item in a bag slot.
local linkNames
local function buildLinkNames()
  linkNames = {}
  for _, chars in pairs((Panoply.db and Panoply.db.inventory) or {}) do
    for _, c in pairs(chars) do
      for _, where in ipairs({ "bags", "bank" }) do
        for _, cont in pairs(type(c) == "table" and c[where] or {}) do
          for slot, it in pairs(type(cont) == "table" and cont or {}) do
            if type(slot) == "number" and type(it) == "table" and type(it[4]) == "string" and not linkNames[it[1]] then
              local nm = it[4]:match("|h%[(.-)%]|h")
              if nm then linkNames[it[1]] = nm end
            end
          end
        end
      end
    end
  end
end
Panoply:Listen("INVENTORY_CHANGED", function() linkNames = nil end)

-- name and quality of an item: the game, else the saved link, else Panoply Suite's own item names
function Alts:ItemName(id)
  local i = C.ItemInfo(id)
  if i and i.name then return i.name, i.quality end
  if not linkNames then buildLinkNames() end
  if linkNames[id] then return linkNames[id], nil end
  local pd = Panoply.ProfData
  local nm = pd and pd.ItemName and pd.ItemName(id)
  if type(nm) == "string" and nm ~= "" and nm ~= tostring(id) then return nm, nil end
  return nil, nil
end

-- { { itemID, count, name, quality } } for one character and one place ("bags", "bank", "mail")
function Alts:Contents(entry, where)
  local out = {}
  if where == "mail" then
    local m = entry.rec and entry.rec.mail
    for id, n in pairs(m and m.items or {}) do out[#out + 1] = { itemID = id, count = n } end
  elseif Panoply.Inventory and Panoply.db and Panoply.db.inventory and Panoply.db.inventory[entry.realm] then
    for id, by in pairs(Panoply.Inventory:Counts(entry.realm)) do
      local c = by[entry.name]
      if c and (c[where] or 0) > 0 then out[#out + 1] = { itemID = id, count = c[where] } end
    end
  end
  for _, it in ipairs(out) do it.name, it.quality = self:ItemName(it.itemID) end
  table.sort(out, function(a, b)
    if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
    local an, bn = (a.name or ("~" .. a.itemID)):lower(), (b.name or ("~" .. b.itemID)):lower()
    if an ~= bn then return an < bn end
    return a.itemID < b.itemID
  end)
  return out
end

-- slots used and total in what was saved of a character's bags or bank, and when
function Alts:SlotUse(entry, where)
  local c = Panoply.db and Panoply.db.inventory and Panoply.db.inventory[entry.realm] and Panoply.db.inventory[entry.realm][entry.name]
  if type(c) ~= "table" or type(c[where]) ~= "table" then return nil end
  local used, size = 0, 0
  for _, cont in pairs(c[where]) do
    if type(cont) == "table" then
      size = size + (tonumber(cont.size) or 0)
      for slot, it in pairs(cont) do if type(slot) == "number" and type(it) == "table" then used = used + 1 end end
    end
  end
  local t = (where == "bank") and c.bankSeen or c.t
  if size == 0 then return nil, nil, t end
  return used, size, t
end

-- The saved containers of one character as bag grids (the Hearth Hall page draws them like the game's
-- own bags). where = "bags" | "bank" | "mail". Returns a list of
--   { id, name, size, used, slots = { [i] = { itemID, count, quality, link, name } } }
-- and the time they were saved. Only what was saved: an empty slot stays empty, an item the game has
-- not cached has no name. Mail has no slot positions (only { [itemID] = count } is saved), so it is the
-- items packed 16 to a box, in the order Alts:Contents gives them.
Alts.MAIL_BOX = 16
function Alts:Grid(entry, where)
  local out = {}
  if where == "mail" then
    local items = self:Contents(entry, "mail")
    local per, n = self.MAIL_BOX, #items
    local box = 0
    for start = 1, math.max(1, n), per do
      box = box + 1
      local c = { id = box, name = box == 1 and "Mailbox" or ("Mailbox " .. box), size = per, used = 0, slots = {} }
      for i = 1, per do
        local it = items[start + i - 1]
        if it then c.slots[i] = { itemID = it.itemID, count = it.count, quality = it.quality, name = it.name } c.used = c.used + 1 end
      end
      if c.used > 0 then out[#out + 1] = c end
    end
    local m = entry.rec and entry.rec.mail
    return out, m and m.t
  end
  local c = Panoply.db and Panoply.db.inventory and Panoply.db.inventory[entry.realm] and Panoply.db.inventory[entry.realm][entry.name]
  if type(c) ~= "table" or type(c[where]) ~= "table" then return out end
  local ids = {}
  for id, cont in pairs(c[where]) do if type(cont) == "table" and type(id) == "number" then ids[#ids + 1] = id end end
  table.sort(ids)
  local n = 0
  for _, id in ipairs(ids) do
    local cont = c[where][id]
    local size = tonumber(cont.size) or 0
    if size > 0 then
      n = n + 1
      local name
      if where == "bags" then name = id == 0 and "Backpack" or ("Bag " .. id)
      else name = id == -1 and "Bank" or ("Bank bag " .. (id - 4)) end
      local g = { id = id, name = name, size = size, used = 0, slots = {}, family = tonumber(cont.family) }
      for slot = 1, size do
        local it = cont[slot]
        if type(it) == "table" and it[1] then
          local nm, q = self:ItemName(it[1])
          g.slots[slot] = { itemID = it[1], count = tonumber(it[2]) or 1, quality = tonumber(it[3]) or q, link = it[4], name = nm }
          g.used = g.used + 1
        end
      end
      out[#out + 1] = g
    end
  end
  local _, _, t = self:SlotUse(entry, where)
  return out, t
end

-- does this saved slot match what was typed? (a name part, an item id or "item:123")
function Alts.SlotMatches(slot, text)
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #text < 2 or not slot then return false end
  local wantId = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if wantId and slot.itemID == wantId then return true end
  return slot.name and slot.name:lower():find(text, 1, true) and true or false
end

-------------------------------------------------------------------------------
-- "Which character has it?"  Bags and bank come from the Inventory store (its Counts, one version
-- of the counting); mail is Hearth Hall's own.
-------------------------------------------------------------------------------
Alts.SEARCH_MIN, Alts.SEARCH_MAX = 2, 25

function Alts:Search(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #text < Alts.SEARCH_MIN then return nil end
  local want = text:lower()
  local wantId = tonumber(want:match("item:(%d+)")) or tonumber(want)
  local per = {}      -- itemID -> { [realm .. 1 .. name] = { realm, name, bags, bank, mail } }
  local function add(id, realm, name, where, n)
    if not n or n <= 0 then return end
    local byId = per[id]
    if not byId then byId = {} per[id] = byId end
    local k = realm .. "\1" .. name
    local p = byId[k]
    if not p then p = { realm = realm, name = name, bags = 0, bank = 0, mail = 0, worn = 0, listed = 0 } byId[k] = p end
    p[where] = p[where] + n
  end
  local Store = Panoply.Inventory
  if Store and Panoply.db and Panoply.db.inventory then
    for realm in pairs(Panoply.db.inventory) do
      for id, by in pairs(Store:Counts(realm)) do
        for name, c in pairs(by) do add(id, realm, name, "bags", c.bags) add(id, realm, name, "bank", c.bank) end
      end
    end
  end
  local a = self:Data()
  for realm, chars in pairs(a and a.realms or {}) do
    for name, rec in pairs(type(chars) == "table" and chars or {}) do
      local m = type(rec) == "table" and rec.mail
      if m and type(m.items) == "table" then for id, n in pairs(m.items) do add(tonumber(id), realm, name, "mail", n) end end
      -- 0.9.5 phase 4I: what it wears, and what it has listed on the auction house
      if type(rec) == "table" and type(rec.gear) == "table" then
        for _, link in pairs(rec.gear) do local id = C.ItemIDFromLink(link) if id then add(id, realm, name, "worn", 1) end end
      end
      if type(rec) == "table" then
        for _, l in ipairs(self:Listings({ realm = realm, name = name })) do if l.id and l.id > 0 then add(l.id, realm, name, "listed", l.stack or 1) end end
      end
    end
  end
  local results = {}
  -- 0.9.5 phase 17: the characters looked up once per search (Find built the whole list again for every match)
  local chars = {}
  for _, e in ipairs(self:List()) do chars[e.realm .. "\1" .. e.name] = e end
  for id, byId in pairs(per) do
    local nm, q = self:ItemName(id)
    local hit = (wantId and id == wantId) or (nm and nm:lower():find(want, 1, true))
    if hit then
      local parts, total = {}, 0
      for _, p in pairs(byId) do
        p.total = p.bags + p.bank + p.mail + p.worn + p.listed
        total = total + p.total
        local e = chars[p.realm .. "\1" .. p.name]
        p.classFile, p.faction = e and e.classFile, e and e.faction
        parts[#parts + 1] = p
      end
      table.sort(parts, function(x, y)
        if x.total ~= y.total then return x.total > y.total end
        return x.name < y.name
      end)
      results[#results + 1] = { itemID = id, name = nm or ("item " .. id), quality = q, total = total, parts = parts }
    end
  end
  table.sort(results, function(x, y)
    if x.total ~= y.total then return x.total > y.total end
    return x.name:lower() < y.name:lower()
  end)
  local more = math.max(0, #results - Alts.SEARCH_MAX)
  for i = #results, Alts.SEARCH_MAX + 1, -1 do results[i] = nil end
  return results, more
end

-- "bags 20, bank 10, mail 4": the places that have any
function Alts.PartText(p)
  local t = {}
  if p.bags and p.bags > 0 then t[#t + 1] = "bags " .. p.bags end
  if p.bank and p.bank > 0 then t[#t + 1] = "bank " .. p.bank end
  if p.mail and p.mail > 0 then t[#t + 1] = "mail " .. p.mail end
  if p.worn and p.worn > 0 then t[#t + 1] = "worn " .. p.worn end
  if p.listed and p.listed > 0 then t[#t + 1] = "auctions " .. p.listed end
  return table.concat(t, ", ")
end
-- spec 02 2.3: "12 bank, 3 mail" (the number first), for the search rows
function Alts.WhereText(p)
  local t = {}
  for _, k in ipairs({ "bags", "bank", "mail", "worn", "listed" }) do
    if (p[k] or 0) > 0 then t[#t + 1] = p[k] .. " " .. (k == "listed" and "auctions" or k) end
  end
  return table.concat(t, ", ")
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4I: the auction house (Modules/Auctions/Record.lua, the history the Auctions page shows) and "who can craft"
-------------------------------------------------------------------------------
-- the Auctions record of a character: its realm group's key, or its realm's own (the record keys a character by its realm group)
function Alts:AuctionRec(entry)
  local Auc = Panoply.Auctions
  local R = Auc and Auc.Record
  if not (R and R.Chars and entry and entry.name) then return nil end
  local ok, all = pcall(R.Chars)
  if not ok or type(all) ~= "table" then return nil end
  local meRealm = self:Me()
  local keys = { entry.realm, ((entry.realm or ""):gsub("%s", "")) }
  if entry.realm == meRealm and Panoply.Prices and Panoply.Prices.RealmGroup then
    local okG, g = pcall(Panoply.Prices.RealmGroup)
    if okG and g then table.insert(keys, 1, g) end
  end
  -- a realm connected to the one being played: the record's own key for it (Record.lua R.RealmKey)
  if R.RealmKey then
    local okK, k = pcall(R.RealmKey, entry.realm)
    if okK and type(k) == "string" then table.insert(keys, 1, k) end
  end
  for _, k in ipairs(keys) do
    local c = type(all[k]) == "table" and all[k][entry.name]
    if type(c) == "table" then return c, k end
  end
  -- a realm group named after another realm of the group (the group's key is the first of its realm names, Prices.RealmGroup): the one
  -- record of that name. 0.9.5 phase 17: never a record that is another character's: a key after this realm's name cannot be its group,
  -- and a key that is a realm where Muster knows a character of the same name is that character's
  local function nrm(s) return (tostring(s or ""):gsub("[%s%-']", "")) end   -- as Prices.Norm
  local own = nrm(entry.realm)
  local taken = {}     -- the realms (as record keys) where Muster has another character of this name
  for realm, chars in pairs(self:Data().realms) do
    if realm ~= entry.realm and type(chars) == "table" and type(chars[entry.name]) == "table" then taken[nrm(realm)] = true end
  end
  local found, fk
  for k, chars in pairs(all) do
    if type(k) == "string" and k < own and not taken[k] and type(chars) == "table" and type(chars[entry.name]) == "table" then
      if found then return nil end
      found, fk = chars[entry.name], k
    end
  end
  return found, fk
end
-- what a character still has listed: { { id, name, stack, buyout, bid, t, ends (time()) } }, soonest to end first. A listing whose time
-- ran out is left out (it is in the mail or sold).
function Alts:Listings(entry)
  local c = self:AuctionRec(entry)
  local R = Panoply.Auctions and Panoply.Auctions.Record
  local out = {}
  if not (c and R and R.Decode and type(c.listed) == "table") then return out end
  local t = Alts.Now()
  for _, row in ipairs(c.listed) do
    local okD, r = pcall(R.Decode, "listed", row)
    if okD and type(r) == "table" then
      r.ends = (r.t or 0) + (r.hours or 0) * 3600
      if r.hours == 0 or r.ends > t then out[#out + 1] = r end
    end
  end
  table.sort(out, function(a, b) return (a.ends or 0) < (b.ends or 0) end)
  return out
end

-- Who can craft: the recipes (Panoply Suite's profession data) whose name or product matches the text, and the characters whose
-- profession windows showed that recipe. { { recipe, profession, makes (item id), who = { { realm, name, classFile } } } }
Alts.CRAFT_MAX = 8
function Alts:WhoCanCraft(text)
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #text < Alts.SEARCH_MIN then return {} end
  local PD = Panoply.ProfData
  if type(PD) ~= "table" then return {} end
  -- the characters that know each recipe name, by profession
  local knows = {}
  for _, e in ipairs(self:List()) do
    local rc = e.rec and e.rec.recipes
    for prof, names in pairs(type(rc) == "table" and rc or {}) do
      if type(names) == "table" then
        knows[prof] = knows[prof] or {}
        for _, nm in ipairs(names) do
          knows[prof][nm] = knows[prof][nm] or {}
          table.insert(knows[prof][nm], { realm = e.realm, name = e.name, classFile = e.classFile })
        end
      end
    end
  end
  local out = {}
  local profs = {}
  for prof in pairs(knows) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local d = PD[prof]
    for _, r in ipairs(type(d) == "table" and d.recipes or {}) do
      local who = r.name and knows[prof][r.name]
      if who then
        local hit = r.name:lower():find(text, 1, true)
        if not hit and r.makes then
          local nm = self:ItemName(r.makes)
          hit = nm and nm:lower():find(text, 1, true)
        end
        if hit and #out < Alts.CRAFT_MAX then out[#out + 1] = { recipe = r.name, profession = prof, makes = r.makes, who = who } end
      end
    end
  end
  return out
end
-- the gear engine's "who can craft" (Modules/Gear/Sources.lua asks with a profession and its recipe record): the names
function Alts.CraftersOf(prof, recipe)
  if type(recipe) ~= "table" or not recipe.name then return nil end
  local out = {}
  for _, e in ipairs(Alts:List()) do
    local names = e.rec and type(e.rec.recipes) == "table" and e.rec.recipes[prof]
    if type(names) == "table" then
      for _, nm in ipairs(names) do if nm == recipe.name then out[#out + 1] = e.name break end end
    end
  end
  return #out > 0 and out or nil
end
if Panoply.GearSources then Panoply.GearSources.whoCanCraft = Alts.CraftersOf end

-- one result as a sentence: "You have 14 Linen Cloth: Mirabel (bank 10, mail 4), Aldric (bags 20)".
-- A character on another realm than the one you are on gets its realm after the name.
-- color = true paints each name in its class colour (|cff...|r).
function Alts:ResultText(r, color)
  local meRealm = self:Me()
  local bits = {}
  for _, p in ipairs(r.parts) do
    local nm = p.name .. ((meRealm and p.realm ~= meRealm) and (" - " .. p.realm) or "")
    if color then nm = Alts.ColorCode(Alts.ClassColor(p.classFile)) .. nm .. "|r" end
    bits[#bits + 1] = nm .. " (" .. Alts.PartText(p) .. ")"
  end
  return ("You have %d %s: %s"):format(r.total, r.name, table.concat(bits, ", "))
end
