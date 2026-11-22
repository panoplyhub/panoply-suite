-- Panoply Suite: Forever Legacy, the model (0.8.4; rebuilt for 0.9.5 phase 4C, docs/specs/page-redesigns-v1.md section 3).
-- What the account has done (the 65 challenges as rows), this character's perk plan, its spent points, and the account rewards.
-- The page is Modules/Legacy/Page.lua; the facts are Modules/Legacy/Data.lua.
--
-- Nothing in this file spends a Legacy point, opens a perk or clicks anything in the game's Legacy window. It reads what the game
-- shows about each character, keeps the player's own ticks and plan, and can show the game's own Legacy window on a click, out of
-- combat (L:OpenGame).
--
-- How a row knows it is done. Each group of rows has a mode:
--   auto     Panoply reads it itself: levels, tradeskill skill, reputation, boss kills, quests and map exploration of each character
--            are cached when that character plays (below) and merged into the account (Hardcore characters left out). The mode is
--            auto only while the reading works in this game right now, and the probe (/panoply probe) did not record it as missing
--            or secret.
--   manual   the game does not tell: the row has a box to tick (PvP ranks without UnitPVPRank, Field of Honor weeks, a battleground
--            whose faction name is not known, a dungeon only WoW Forever has).
-- A live source (L:SetSource) can say more: see "A live source" below.
--
-- Saved data (PanoplySuiteDB.foreverLegacy; v = 1; 0.8.4's keys are kept and still read, nothing is renamed):
--   earned = { [category] = n }   0.8.4: the player's own count of a category (the old - 1 / + 1). Still read: a category counts at
--                                  least that many, so nothing counted before is lost.
--   done = { [id] = true }         ticked by hand: 0.8.4's named challenges, and since 0.9.5 a manual row's id ("pvp.foh.4")
--   cosmetics = { [key] = true }   0.8.4: rewards marked collected by hand. Still read: an owned mark the collections cannot check.
--   chars = { [realm] = { [name] = record } }, the record:
--     spent = { [tree] = n }, want = { [perk id] = true }, classFile, t      0.8.4 (kept; `spent` is still read until a plan is marked
--                                                                            spent; `want` is kept, not shown)
--     NEW in 0.9.5: plan = { [perk id] = rank }, planSpent = true (this plan is what the character spent in the game),
--       cache = { at, level, classFile, hc (Hardcore), profs = { [name] = skill }, pvprank, reps = { [faction] = standing },
--                 kills = { [instance key] = { [boss] = time } }, explore = 0..100, valth = steps done }
--   NEW in 0.9.5: seen = { [row id] = true } (completions already announced), seenReward = { [key] = true }, rewardIds = { [key] = id }
--     (the ids the game's collections gave for the rewards, found by name)
--
-- A live source, set with L:SetSource(src). Every function is optional:
--   src.Challenges()  -> named challenges (0.8.4 shape, Data.lua)     src.Points() -> the account's Legacy points
--   src.Spent()       -> { [tree] = n } for this character            src.Ranks()  -> { [perk id] = rank } for this character
--   src.Cosmetics()   -> { { key, owned } }  ownership of the rewards
local ADDON, Panoply = ...
local L = Panoply.Legacy
local C = Panoply.Compat
local G = C.G
local floor, max, min = math.floor, math.max, math.min

local function whole(n) n = tonumber(n) or 0 return max(0, floor(n + 0.5)) end
local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end
L.plural = plural
local function readable(v) return C.Readable and C.Readable(v) or v end
local function changed(what) Panoply:Fire("LEGACY_CHANGED", what) end

-------------------------------------------------------------------------------
-- The saved data
-------------------------------------------------------------------------------
function L:Store()
  local db = Panoply.db
  if not db then return nil end
  local s = db.foreverLegacy
  if type(s) ~= "table" then s = {} db.foreverLegacy = s end
  s.v = s.v or 1
  for _, k in ipairs({ "earned", "done", "cosmetics", "chars" }) do if type(s[k]) ~= "table" then s[k] = {} end end
  return s
end
-- the saved table only when it is there and whole (reading never makes one)
function L:Peek()
  local s = Panoply.db and Panoply.db.foreverLegacy
  if type(s) ~= "table" then return nil end
  for _, k in ipairs({ "earned", "done", "cosmetics", "chars" }) do if type(s[k]) ~= "table" then return nil end end
  return s
end

function L:Me()
  local ok, info = pcall(C.PlayerInfo)
  if not ok or type(info) ~= "table" then return nil end
  return info.realm, info.name, info
end

local BLANK = { spent = {}, want = {}, plan = {} }
-- This character's record. create = make it when it is not there yet (only a change does that; looking never writes).
function L:Char(create)
  local s = create and self:Store() or self:Peek()
  local realm, name, info = self:Me()
  if not (s and type(realm) == "string" and type(name) == "string") then return BLANK end
  local r = s.chars[realm]
  local c = type(r) == "table" and r[name] or nil
  if type(c) ~= "table" then
    if not create then return BLANK end
    if type(r) ~= "table" then r = {} s.chars[realm] = r end
    c = {}
    r[name] = c
  end
  if create then
    if type(c.spent) ~= "table" then c.spent = {} end
    if type(c.want) ~= "table" then c.want = {} end
    if type(c.plan) ~= "table" then c.plan = {} end
    c.classFile = info.classFile or c.classFile
    c.t = _G.time and time() or c.t
  end
  return c
end

function L:SetSource(src)
  self.source = type(src) == "table" and src or nil
  changed("source")
end
local function fromSource(self, fn)
  local src = self.source
  if src and type(src[fn]) == "function" then
    local ok, v = pcall(src[fn])
    if ok then return v end
    Panoply:Debug("legacy source", fn, v)
  end
  return nil
end

-------------------------------------------------------------------------------
-- Modes: what this game lets Panoply read right now
-------------------------------------------------------------------------------
-- the probe's answer for a check, when it ran on this game build: "missing" | "secret" | ... | nil
function L:ProbeSays(id)
  local P = Panoply.Probe
  if not (P and P.Record) then return nil end
  local ok, rec = pcall(P.Record, P, false)
  local r = ok and type(rec) == "table" and type(rec.results) == "table" and rec.results[id]
  return type(r) == "table" and r.status or nil
end
local function probeBlocks(self, id)
  local st = id and self:ProbeSays(id)
  return st == "missing" or st == "secret"
end

L.PROBE_GATES = { tradeskills = "skills.lines", explore = "explore.map", pvprank = "explore.pvprank" }
-- the readings, each true when it works in this game now
L.READERS = {
  classes = function() local lv = C.XPKnown() return type(lv) == "number" end,
  tradeskills = function() return Panoply.ProfDetect ~= nil and type(Panoply.ProfDetect.Scan) == "function" end,
  pvprank = function() return G("UnitPVPRank") ~= nil end,
  reps = function() return G("C_Reputation.GetFactionDataByIndex") ~= nil or G("GetFactionInfo") ~= nil end,
  kills = function() return not (Panoply.skippedEvents and Panoply.skippedEvents.BOSS_KILL) end,
  explore = function() return G("C_MapExplorationInfo.GetExploredMapTextures") ~= nil and L:AreaTable() ~= nil end,
  valthalak = function() return G("C_QuestLog.IsQuestFlaggedCompleted") ~= nil or G("IsQuestFlaggedCompleted") ~= nil end,
}
function L:Mode(group)
  if self.modeMemo and self.modeMemo[group] then return self.modeMemo[group] end
  local f = self.READERS[group]
  if not f then return "manual" end
  if probeBlocks(self, self.PROBE_GATES[group]) then return "manual" end
  local ok, yes = pcall(f)
  local m = (ok and yes) and "auto" or "manual"
  if self.modeMemo then self.modeMemo[group] = m end
  return m
end

-------------------------------------------------------------------------------
-- The cache: what each character shows, saved when it plays (WoW Forever only)
-------------------------------------------------------------------------------
-- the explorable areas of every zone of this game (instance atlas extras)
function L:AreaTable()
  local qd = rawget(_G, "PanoplySuiteQuestData")
  local ex = qd and qd.MapExtras
  local a = type(ex) == "table" and type(ex.areas) == "table" and ex.areas[C.IsForever() and "forever" or "era"] or nil
  return type(a) == "table" and a or nil
end

-- percent of the world's areas this character has explored, or nil when the game does not say
function L:ReadExplore()
  local areas = self:AreaTable()
  local f = G("C_MapExplorationInfo.GetExploredMapTextures")
  if not (areas and f) then return nil end
  local total, seen = 0, 0
  for uiMap, list in pairs(areas) do
    local n = type(list) == "table" and #list or 0
    if n > 0 then
      total = total + n
      local ok, tex = pcall(f, uiMap)
      if ok and type(tex) == "table" and readable(tex) then seen = seen + min(n, #tex) end
    end
  end
  if total == 0 then return nil end
  return floor(seen * 1000 / total + 0.5) / 10
end

-- standing by faction name, for the battleground factions only
function L:ReadReps()
  local want = {}
  for _, e in ipairs(self.PVP_EXALTED) do for _, n in ipairs(e.factions) do want[n] = true end end
  local out = {}
  local n = 0
  if G("C_Reputation.GetNumFactions") and G("C_Reputation.GetFactionDataByIndex") then
    local ok, cnt = pcall(G("C_Reputation.GetNumFactions"))
    for i = 1, min(ok and tonumber(readable(cnt)) or 0, 300) do
      local ok2, d = pcall(G("C_Reputation.GetFactionDataByIndex"), i)
      if ok2 and type(d) == "table" and want[d.name] and tonumber(readable(d.reaction)) then
        out[d.name] = { s = tonumber(d.reaction), v = (tonumber(readable(d.currentStanding)) or 0) - (tonumber(readable(d.currentReactionThreshold)) or 0),
          m = (tonumber(readable(d.nextReactionThreshold)) or 0) - (tonumber(readable(d.currentReactionThreshold)) or 0) }
        n = n + 1
      end
    end
  elseif G("GetNumFactions") and G("GetFactionInfo") then
    local ok, cnt = pcall(G("GetNumFactions"))
    for i = 1, min(ok and tonumber(readable(cnt)) or 0, 300) do
      local ok2, fname, _, sid, lo, hi, v = pcall(G("GetFactionInfo"), i)
      if ok2 and want[fname] and tonumber(readable(sid)) then
        out[fname] = { s = tonumber(sid), v = (tonumber(readable(v)) or 0) - (tonumber(readable(lo)) or 0), m = (tonumber(readable(hi)) or 0) - (tonumber(readable(lo)) or 0) }
        n = n + 1
      end
    end
  else
    return nil
  end
  return out
end

function L:ReadValthalak()
  if self:Mode("valthalak") ~= "auto" then return nil end
  local n = 0
  for _, step in ipairs(self.VALTHALAK.steps) do
    local any = false
    for _, id in ipairs(step) do if C.IsQuestCompleted(id) then any = true break end end
    if not any then break end
    n = n + 1
  end
  return n
end

-- Save what this character shows now into its record (only on WoW Forever, only the character being played)
function L:Collect()
  if not self:Here() or not Panoply.db then return false end
  local c = self:Char(true)
  if c == BLANK then return false end
  local k = type(c.cache) == "table" and c.cache or {}
  c.cache = k
  local _, _, info = self:Me()
  k.classFile = info and info.classFile or k.classFile
  -- A reading only ever raises what is saved: a challenge, once reached, stays reached. (The skill list is empty for a moment while
  -- the game loads, a collapsed header hides factions, a PvP rank decays every week: none of that may take a point away.)
  local function higher(a, b) a, b = tonumber(a), tonumber(b) if a and b then return max(a, b) end return a or b end
  local lv = C.XPKnown()
  if type(lv) == "number" then k.level = higher(k.level, lv) end
  local okHc, hc = pcall(C.IsHardcore)
  k.hc = (okHc and hc) and true or nil
  if self:Mode("tradeskills") == "auto" then
    local ok, known, _, _, total = pcall(Panoply.ProfDetect.Scan, Panoply.ProfDetect)
    if ok and type(known) == "table" and (tonumber(total) or 0) > 0 then
      local p = type(k.profs) == "table" and k.profs or {}
      for name, e in pairs(known) do if type(e) == "table" and tonumber(e.rank) then p[name] = higher(p[name], whole(e.rank)) end end
      k.profs = p
    end
  end
  local rk = G("UnitPVPRank")
  if rk then
    local ok, r = pcall(rk, "player")
    r = ok and tonumber(readable(r)) or nil
    -- UnitPVPRank counts from 5 for rank 1 in the classic client (0 = no rank); the highest rank reached is kept
    if r then k.pvprank = higher(k.pvprank, r >= 5 and (r - 4) or 0) end
  end
  local reps = self:ReadReps()
  if reps then
    local kept = type(k.reps) == "table" and k.reps or {}
    for name, e in pairs(reps) do
      local old = kept[name]
      local was = type(old) == "table" and tonumber(old.s) or tonumber(old)
      if not was or e.s >= was then kept[name] = e end
    end
    k.reps = kept
  end
  local ex = self:ReadExplore()
  if ex then k.explore = higher(k.explore, ex) end
  local vs = self:ReadValthalak()
  if vs then k.valth = higher(k.valth, vs) end
  k.at = _G.time and time() or k.at
  -- the reward ids the collections gave this session (found while drawing; written here, where saving belongs)
  if self.foundIds and next(self.foundIds) then
    local s = self:Store()
    s.rewardIds = type(s.rewardIds) == "table" and s.rewardIds or {}
    for key, id in pairs(self.foundIds) do s.rewardIds[key] = id end
  end
  self:Announce()
  changed("cache")
  return true
end

-- a boss died: kept under the instance's map id ("#36") and its name, so dungeons (atlas ids) and raids (by name) both find it
function L:NoteKill(bossName)
  if not self:Here() or type(bossName) ~= "string" or bossName == "" then return false end
  local f = G("GetInstanceInfo")
  if not f then return false end
  local ok, iname, itype, _, _, _, _, _, iid = pcall(f)
  if not ok or (itype ~= "party" and itype ~= "raid") then return false end
  local c = self:Char(true)
  if c == BLANK then return false end
  c.cache = type(c.cache) == "table" and c.cache or {}
  local kills = type(c.cache.kills) == "table" and c.cache.kills or {}
  c.cache.kills = kills
  local t = _G.time and time() or 0
  for _, key in ipairs({ iid and ("#" .. tostring(iid)) or nil, type(iname) == "string" and iname or nil }) do
    if key then
      kills[key] = type(kills[key]) == "table" and kills[key] or {}
      kills[key][bossName] = t
    end
  end
  self:Announce()
  changed("kills")
  return true
end

-------------------------------------------------------------------------------
-- The account: every character's record, merged (Hardcore characters left out of the shared total)
-------------------------------------------------------------------------------
-- { { realm, name, classFile, level, profs, reps, kills, explore, valth, pvprank, hc, fromMuster } }
function L:Chars()
  local out, by = {}, {}
  local s = self:Peek()
  for realm, list in pairs(s and s.chars or {}) do
    if type(realm) == "string" and type(list) == "table" then
      for name, c in pairs(list) do
        if type(name) == "string" and type(c) == "table" then
          local k = type(c.cache) == "table" and c.cache or {}
          local e = { realm = realm, name = name, classFile = k.classFile or c.classFile, level = tonumber(k.level), profs = type(k.profs) == "table" and k.profs or {},
            reps = type(k.reps) == "table" and k.reps or {}, kills = type(k.kills) == "table" and k.kills or {}, explore = tonumber(k.explore),
            valth = tonumber(k.valth), pvprank = tonumber(k.pvprank), hc = k.hc and true or false }
          out[#out + 1] = e
          by[realm .. "\1" .. name] = e
        end
      end
    end
  end
  -- Hardcore realms: Muster keeps no Hardcore mark, so a character Legacy has only from Muster takes its realm's (a realm where every
  -- character Legacy has seen is Hardcore is a Hardcore realm)
  local hcRealm = {}
  for _, e in ipairs(out) do
    if e.hc then if hcRealm[e.realm] == nil then hcRealm[e.realm] = true end else hcRealm[e.realm] = false end
  end
  -- characters Muster saved (its own table, read only) fill in what Legacy has not seen yet: class, level, professions
  local alts = Panoply.db and Panoply.db.alts
  for realm, list in pairs(type(alts) == "table" and type(alts.realms) == "table" and alts.realms or {}) do
    if type(realm) == "string" and type(list) == "table" then
      for name, r in pairs(list) do
        if type(name) == "string" and type(r) == "table" then
          local e = by[realm .. "\1" .. name]
          if not e then
            e = { realm = realm, name = name, profs = {}, reps = {}, kills = {}, hc = hcRealm[realm] == true, fromMuster = true }
            out[#out + 1] = e
            by[realm .. "\1" .. name] = e
          end
          e.classFile = e.classFile or r.classFile
          if not e.level then e.level = tonumber(r.level) end
          if next(e.profs) == nil and type(r.profs) == "table" then
            for _, part in ipairs({ r.profs.prim, r.profs.sec }) do
              for _, pr in ipairs(type(part) == "table" and part or {}) do
                if type(pr) == "table" and type(pr[1]) == "string" then e.profs[pr[1]] = whole(pr[2]) end
              end
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.realm ~= b.realm then return a.realm < b.realm end return a.name < b.name end)
  return out
end
-- the characters that count for the account (not Hardcore)
function L:Counting()
  local out = {}
  for _, e in ipairs(self:Chars()) do if not e.hc then out[#out + 1] = e end end
  return out
end
function L:IsMe(e)
  local realm, name = self:Me()
  return e and e.realm == realm and e.name == name
end
-- this character's entry (cache or Muster), or a blank one
function L:MeEntry()
  for _, e in ipairs(self:Chars()) do if self:IsMe(e) then return e end end
  local realm, name, info = self:Me()
  local profs = {}
  if Panoply.ProfDetect and Panoply.ProfDetect.Scan then
    local ok, known = pcall(Panoply.ProfDetect.Scan, Panoply.ProfDetect)
    for n, e in pairs(ok and type(known) == "table" and known or {}) do if type(e) == "table" and tonumber(e.rank) then profs[n] = whole(e.rank) end end
  end
  local okHc, hc = pcall(C.IsHardcore)
  return { realm = realm, name = name, classFile = info and info.classFile, level = C.XPKnown(), profs = profs, reps = {}, kills = {}, hc = (okHc and hc) and true or false }
end

-------------------------------------------------------------------------------
-- The rows: the 65 challenges
-------------------------------------------------------------------------------
-- the date of a { y, m, d } table, as a time() value (noon, so a time zone never moves the day)
local function dateOf(t) return _G.time and time({ year = t[1], month = t[2], day = t[3], hour = 12 }) or 0 end
L.dateOf = dateOf
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function L.DateText(t) return ("%s %d"):format(MONTHS[t[2]] or "?", t[3]) end
function L:Now() return (_G.time and time()) or 0 end

-- the first day a Field of Honor week can be earned
function L:FieldWeekStart(week)
  local w1 = self.FIELD_OF_HONOR.week1
  local t = dateOf(w1) + (week - 1) * 7 * 86400
  local d = _G.date and date("*t", t)
  return t, d and { d.year, d.month, d.day } or w1
end

function L:BuildRows()
  if self.ROWS then return self.ROWS end
  local rows, byId = {}, {}
  local function add(r) rows[#rows + 1] = r byId[r.id] = r end
  for _, cls in ipairs(self.CLASS_ORDER) do
    for _, lv in ipairs(self.CLASS_LEVELS) do
      add({ id = ("class.%s.%d"):format(cls, lv), cat = "classes", group = "classes", class = cls, level = lv, label = ("%s %d"):format(self.CLASS_NAMES[cls], lv) })
    end
  end
  for _, prof in ipairs(self.TRADESKILLS) do
    for _, at in ipairs(self.TRADESKILL_LEVELS) do
      add({ id = ("trade.%s.%d"):format(prof, at), cat = "tradeskills", group = "tradeskills", prof = prof, skill = at, label = ("%s %d"):format(prof, at) })
    end
  end
  for _, rk in ipairs(self.PVP_RANKS) do add({ id = "pvp.rank." .. rk, cat = "pvp", group = "pvprank", rank = rk, label = "Rank " .. rk }) end
  for _, e in ipairs(self.PVP_EXALTED) do add({ id = "pvp.ex." .. e.key, cat = "pvp", group = #e.factions > 0 and "reps" or "none", ex = e, label = "Exalted: " .. e.name }) end
  for _, wk in ipairs(self.FIELD_OF_HONOR.weeks) do add({ id = "pvp.foh." .. wk, cat = "pvp", group = "none", week = wk, label = "Field of Honor: " .. wk .. " weeks" }) end
  for _, t in ipairs(self.SPELUNKER) do add({ id = "dng." .. t.key, cat = "dungeons", group = "kills", tier = t, label = t.name }) end
  for _, r in ipairs(self.RAIDS) do add({ id = "raid." .. r.key, cat = "raids", group = "kills", raid = r, label = r.name }) end
  add({ id = "adv.explore", cat = "adventure", group = "explore", label = self.EXPLORE.name })
  add({ id = "adv.valthalak", cat = "adventure", group = "valthalak", label = self.VALTHALAK.name })
  self.ROWS, self.ROW_BY_ID = rows, byId
  return rows
end
function L:Row(id) self:BuildRows() return self.ROW_BY_ID[id] end
function L:RowsOf(cat)
  local out = {}
  for _, r in ipairs(self:BuildRows()) do if r.cat == cat then out[#out + 1] = r end end
  return out
end

-- the atlas instances by name
function L:Atlas()
  local qd = rawget(_G, "PanoplySuiteQuestData")
  local d = qd and qd.MapData
  if type(d) ~= "table" then return nil end
  if self.atlasFor ~= d then
    local by = {}
    for _, inst in ipairs(d.instances or {}) do if type(inst) == "table" and inst.name then by[inst.name] = inst end end
    self.atlasBy, self.atlasFor = by, d
  end
  return self.atlasBy
end
-- the final bosses of a dungeon: the last boss of each wing in the atlas, in its order. nil when the atlas does not have it.
function L:FinalBosses(dungeonName)
  local by = self:Atlas()
  local inst = by and by[dungeonName]
  if not inst then return nil, nil end
  self.finalMemo = (self.finalMemoFor == by) and self.finalMemo or {}
  self.finalMemoFor = by
  if self.finalMemo[dungeonName] then return self.finalMemo[dungeonName], inst end
  local last, order = {}, {}
  for _, b in ipairs(inst.bosses or {}) do
    if type(b) == "table" and type(b[1]) == "string" then
      local wing = b[5] or ""
      if last[wing] == nil then order[#order + 1] = wing end
      last[wing] = b[1]
    end
  end
  local out = {}
  for _, w in ipairs(order) do out[#out + 1] = { boss = last[w], wing = w ~= "" and w or nil } end
  self.finalMemo[dungeonName] = out
  return out, inst
end
-- who killed a boss in an instance: the first counting character's name, or nil
local function killedBy(chars, keys, boss)
  for _, e in ipairs(chars) do
    for _, key in ipairs(keys) do
      local k = e.kills[key]
      if type(k) == "table" and k[boss] then return e end
    end
  end
  return nil
end

-- one dungeon of a Spelunker band: { name, bosses = { { boss, wing, by } }, done, manual, checked, inst, note }
function L:DungeonState(tier, name, chars)
  chars = chars or self:Counting()
  local s = self:Peek()
  local list, inst = self:FinalBosses(name)
  local out = { name = name, note = tier.notes and tier.notes[name], inst = inst }
  local id = "dng." .. tier.key .. "." .. name
  out.id = id
  if not list or self:Mode("kills") ~= "auto" then
    out.manual = true
    out.checked = s ~= nil and s.done[id] == true
    out.done = out.checked
    out.bosses = {}
    return out
  end
  local keys = { "#" .. tostring(inst.id), inst.name }
  local all = true
  out.bosses = {}
  for _, b in ipairs(list) do
    local by = killedBy(chars, keys, b.boss)
    out.bosses[#out.bosses + 1] = { boss = b.boss, wing = b.wing, by = by and by.name or nil }
    if not by then all = false end
  end
  out.done = all
  return out
end

-- the state of a row: { state = "done" | "progress" | "todo" | "locked", by (character name), have (number), need, text (inline),
-- manual (it has a box to tick), checked, until (the date it opens, { y, m, d }), parts (dungeons of a Spelunker band) }
function L:RowState(r, chars)
  chars = chars or self:Counting()
  local s = self:Peek()
  local out = { row = r }
  local function tick()
    out.manual = true
    out.checked = s ~= nil and s.done[r.id] == true
    out.state = out.checked and "done" or "todo"
    return out
  end
  if r.group == "classes" then
    if self:Mode("classes") ~= "auto" then return tick() end
    local best
    for _, e in ipairs(chars) do if e.classFile == r.class and e.level and (not best or e.level > best.level) then best = e end end
    out.need = r.level
    if best and best.level >= r.level then out.state, out.by, out.have = "done", best.name, best.level
    elseif best then out.state, out.have, out.by = "progress", best.level, best.name
    else out.state = "todo" end
    return out
  elseif r.group == "tradeskills" then
    if self:Mode("tradeskills") ~= "auto" then return tick() end
    local best, bv
    for _, e in ipairs(chars) do
      local v = e.profs[r.prof]
      if v and (not bv or v > bv) then best, bv = e, v end
    end
    out.need = r.skill
    if bv and bv >= r.skill then out.state, out.by, out.have = "done", best.name, bv
    elseif bv then out.state, out.have, out.by = "progress", bv, best.name
    else out.state = "todo" end
    -- this character's own skill, shown inline
    local me = self.meMemo or self:MeEntry()
    out.mine = me.profs and me.profs[r.prof] or nil
    return out
  elseif r.group == "pvprank" then
    if self:Mode("pvprank") ~= "auto" then return tick() end
    local best
    for _, e in ipairs(chars) do if e.pvprank and (not best or e.pvprank > best.pvprank) then best = e end end
    out.need = r.rank
    if best and best.pvprank >= r.rank then out.state, out.by, out.have = "done", best.name, best.pvprank
    elseif best and best.pvprank > 0 then out.state, out.have = "progress", best.pvprank
    else out.state = "todo" end
    return out
  elseif r.group == "reps" then
    if self:Mode("reps") ~= "auto" then return tick() end
    local best, bs
    for _, e in ipairs(chars) do
      for _, fname in ipairs(r.ex.factions) do
        local st = e.reps[fname]
        local sid = type(st) == "table" and tonumber(st.s) or tonumber(st)
        if sid and (not bs or sid > bs) then best, bs = e, sid end
      end
    end
    if bs and bs >= self.EXALTED_STANDING then out.state, out.by = "done", best.name
    elseif bs and bs >= 5 then out.state, out.have, out.by = "progress", bs, best.name
    else out.state = "todo" end
    return out
  elseif r.week then
    local t, d = self:FieldWeekStart(r.week)
    out["until"] = d
    if self:Now() < t then out.state = "locked" return out end
    return tick()
  elseif r.tier then
    local done, total = 0, 0
    out.parts = {}
    for _, name in ipairs(r.tier.dungeons) do
      local d = self:DungeonState(r.tier, name, chars)
      out.parts[#out.parts + 1] = d
      total = total + 1
      if d.done then done = done + 1 end
    end
    out.have, out.need = done, total
    out.state = (total > 0 and done == total) and "done" or (done > 0 and "progress" or "todo")
    return out
  elseif r.raid then
    out["until"] = r.raid.opens
    if self:Now() < dateOf(r.raid.opens) then out.state = "locked" return out end
    if self:Mode("kills") ~= "auto" then return tick() end
    -- distinct bosses killed in that raid by the counting characters (one character's kills; the best one)
    local best, bn = nil, 0
    for _, e in ipairs(chars) do
      local k = e.kills[r.raid.instance]
      local n = 0
      for _ in pairs(type(k) == "table" and k or {}) do n = n + 1 end
      if n > bn then best, bn = e, n end
    end
    out.have, out.need = bn, r.raid.bosses
    if bn >= r.raid.bosses then out.state, out.by = "done", best.name
    elseif bn > 0 then out.state, out.by = "progress", best.name
    else out.state = "todo" end
    return out
  elseif r.group == "explore" then
    if self:Mode("explore") ~= "auto" then return tick() end
    local best
    for _, e in ipairs(chars) do if e.explore and (not best or e.explore > best.explore) then best = e end end
    out.need = 100
    if best and best.explore >= 100 then out.state, out.by, out.have = "done", best.name, 100
    elseif best then out.state, out.have, out.by = "progress", best.explore, best.name
    else out.state = "todo" end
    return out
  elseif r.group == "valthalak" then
    if self:Mode("valthalak") ~= "auto" then return tick() end
    local best
    for _, e in ipairs(chars) do if e.valth and (not best or e.valth > best.valth) then best = e end end
    local n = #self.VALTHALAK.steps
    out.need = n
    if best and best.valth >= n then out.state, out.by, out.have = "done", best.name, n
    elseif best and best.valth > 0 then out.state, out.have, out.by = "progress", best.valth, best.name
    else out.state = "todo" end
    return out
  end
  return tick()
end

-- 0.9.5 phase 17 (spec 02 2.3, Muster's Overview): the challenges one character has earned by itself, worked out from that character
-- alone. Rows ticked by hand and rows not open yet belong to the account, not a character, so they are left out. Returns the rows, in
-- the page's order (empty when Legacy does not know the character).
function L:EarnedBy(realm, name)
  local entry
  for _, e in ipairs(self:Chars()) do if e.realm == realm and e.name == name then entry = e end end
  local out = {}
  if not entry then return out end
  self.modeMemo, self.meMemo = {}, self:MeEntry()
  local ok, err = pcall(function()
    for _, r in ipairs(self:BuildRows()) do
      local st = self:RowState(r, { entry })
      if st.state == "done" and not st.manual then out[#out + 1] = r end
    end
  end)
  self.modeMemo, self.meMemo = nil, nil
  if not ok then error(err, 0) end
  return out
end

-- a manual row (or a manual dungeon of a Spelunker band), ticked by hand
function L:CanTickRow(id)
  local r = self:Row(id)
  if r then local st = self:RowState(r) return st.manual == true end
  local key, name = tostring(id):match("^dng%.(%w+)%.(.+)$")
  if key then
    for _, t in ipairs(self.SPELUNKER) do
      if t.key == key then local d = self:DungeonState(t, name) return d.manual == true end
    end
  end
  return false
end
function L:SetTicked(id, on)
  if not self:CanTickRow(id) then return false end
  local s = self:Store()
  s.done[id] = on and true or nil
  changed("challenges")
  return true
end

-- every row's state, once: { [row id] = state }
function L:States()
  local chars = self:Counting()
  local out = {}
  self.modeMemo, self.meMemo = {}, self:MeEntry()
  local ok, err = pcall(function() for _, r in ipairs(self:BuildRows()) do out[r.id] = self:RowState(r, chars) end end)
  self.modeMemo, self.meMemo = nil, nil
  if not ok then error(err, 0) end
  return out
end

-------------------------------------------------------------------------------
-- Categories, totals and points
-------------------------------------------------------------------------------
function L:Category(key)
  for _, c in ipairs(self.CATEGORIES) do if c.key == key then return c end end
  return nil
end
function L:Challenges()
  local v = fromSource(self, "Challenges")
  return type(v) == "table" and v or self.CHALLENGES
end
function L:IsDone(ch)
  if type(ch) ~= "table" then return false end
  if ch.done ~= nil then return ch.done and true or false end
  local s = self:Peek()
  return s ~= nil and ch.id ~= nil and s.done[ch.id] == true
end

-- One category: { key, name, total, done, rowsDone, counted (0.8.4's own count) }
function L:CategoryInfo(key, states)
  local cat = self:Category(key)
  if not cat then return nil end
  states = states or self:States()
  local n = 0
  for _, r in ipairs(self:RowsOf(key)) do if states[r.id] and states[r.id].state == "done" then n = n + 1 end end
  local s = self:Peek()
  local counted = min(cat.count, whole(s and s.earned[key]))
  return { key = key, name = cat.name, total = cat.count, rowsDone = n, counted = counted, done = min(cat.count, max(n, counted)) }
end
function L:Categories(states)
  states = states or self:States()
  local out = {}
  for _, c in ipairs(self.CATEGORIES) do out[#out + 1] = self:CategoryInfo(c.key, states) end
  return out
end
-- 0.8.4's count for a category (no button sets it any more; kept so a saved count can still be read and tested)
function L:SetEarned(key, n)
  local cat = self:Category(key)
  if not cat then return false end
  local s = self:Store()
  n = min(cat.count, whole(n))
  if (s.earned[key] or 0) == n then return false end
  s.earned[key] = n > 0 and n or nil
  changed("challenges")
  return true
end

function L:Total()
  local n = 0
  for _, c in ipairs(self.CATEGORIES) do n = n + c.count end
  return n
end
function L:Done(states)
  local n = 0
  for _, c in ipairs(self:Categories(states)) do n = n + c.done end
  return n
end
-- The account's Legacy points: what the game says when a source knows, else one for each challenge done
function L:Points(states)
  local v = fromSource(self, "Points")
  if tonumber(v) then return whole(v), true end
  return self:Done(states) * self.POINTS_PER_CHALLENGE, false
end

-------------------------------------------------------------------------------
-- Completions announced (a toast and a shine; never twice)
-------------------------------------------------------------------------------
function L:Announce()
  local s = self:Peek()
  if not s then return end
  local states = self:States()
  local first = s.seen == nil
  s.seen = type(s.seen) == "table" and s.seen or {}
  s.seenReward = type(s.seenReward) == "table" and s.seenReward or {}
  local points = self:Points(states)
  local total = self:Total()
  self.fresh = self.fresh or {}
  for _, r in ipairs(self:BuildRows()) do
    local st = states[r.id]
    if st and st.state == "done" and not st.manual and not s.seen[r.id] then
      s.seen[r.id] = true
      if not first then
        self.fresh[r.id] = true
        Panoply.Kit.Toast(("Legacy: %s - %d/%d"):format(r.label, points, total), { title = "Legacy" })
      end
    end
  end
  for _, rw in ipairs(self.COSMETICS) do
    if points >= rw.points and not s.seenReward[rw.key] then
      s.seenReward[rw.key] = true
      if not first then
        self.fresh["reward." .. rw.key] = true
        Panoply.Kit.Toast(("Legacy reward: %s at %d points"):format(rw.name, rw.points), { title = "Legacy" })
      end
    end
  end
end
-- the page draws a shine on a cell that completed since it last looked
function L:TakeFresh(id)
  if self.fresh and self.fresh[id] then self.fresh[id] = nil return true end
  return false
end

-------------------------------------------------------------------------------
-- The account rewards
-------------------------------------------------------------------------------
L.REWARD_CACHE = 30   -- seconds a collection answer is kept
L.REWARD_MISS = 600   -- seconds a "not found" is kept (the toy box search walks every toy)
-- find a reward in the game's collections by name: owned (true / false / nil = cannot tell), icon, id
function L:FindReward(rw)
  local now = (_G.GetTime and GetTime()) or 0
  self.rewardCache = self.rewardCache or {}
  local c = self.rewardCache[rw.key]
  if c and now - c.at < self.REWARD_CACHE then return c.owned, c.icon, c.id end
  local owned, icon, id
  local s = self:Peek()
  local known = s and type(s.rewardIds) == "table" and s.rewardIds[rw.key] or nil
  if rw.find == "toy" then
    local has, info = G("PlayerHasToy"), G("C_ToyBox.GetToyInfo")
    if known and has then
      local ok, o = pcall(has, known)
      if ok then owned = readable(o) and true or false end
      if info then local ok2, _, _, ic = pcall(info, known) if ok2 then icon = ic end end
      id = known
    elseif has and G("C_ToyBox.GetNumToys") and G("C_ToyBox.GetToyFromIndex") and info then
      local ok, n = pcall(G("C_ToyBox.GetNumToys"))
      for i = 1, min(ok and tonumber(readable(n)) or 0, 3000) do
        local ok2, itemID = pcall(G("C_ToyBox.GetToyFromIndex"), i)
        if ok2 and type(itemID) == "number" and itemID > 0 then
          local ok3, _, name, ic = pcall(info, itemID)
          if ok3 and type(name) == "string" and name:lower() == rw.name:lower() then
            local ok4, o = pcall(has, itemID)
            if ok4 then owned = readable(o) and true or false end
            icon, id = ic, itemID
            break
          end
        end
      end
    end
  elseif rw.find == "pet" then
    local f = G("C_PetJournal.FindPetIDByName")
    if f then
      local ok, species, guid = pcall(f, rw.name)
      if ok and species then
        owned, id = guid ~= nil, species
        local inf = G("C_PetJournal.GetPetInfoBySpeciesID")
        if inf then local ok2, _, ic = pcall(inf, species) if ok2 then icon = ic end end
      end
    end
  elseif rw.find == "mount" then
    local ids, inf = G("C_MountJournal.GetMountIDs"), G("C_MountJournal.GetMountInfoByID")
    if ids and inf then
      local a = rw.name:lower()
      local b = a:gsub("^reins of the ", "")
      local list = known and { known } or select(2, pcall(ids))
      for _, mid in ipairs(type(list) == "table" and list or {}) do
        local res = { pcall(inf, mid) }
        local name = res[2]
        if res[1] and type(name) == "string" and (name:lower() == a or name:lower() == b) then
          owned, icon, id = readable(res[12]) and true or false, res[4], mid
          break
        end
      end
    end
  elseif rw.find == "item" then
    local f = G("C_Item.GetItemInfo") or G("GetItemInfo")
    if f then
      local ok, name, link, _, _, _, _, _, _, _, ic = pcall(f, known or rw.name)
      if ok and name then
        icon = ic
        id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or known
        local cnt = G("C_Item.GetItemCount") or G("GetItemCount")
        if cnt and id then local ok2, nn = pcall(cnt, id, true) if ok2 and tonumber(readable(nn)) then owned = tonumber(nn) > 0 or nil end end
      end
    end
  end
  -- a source may know better; then the player's own 0.8.4 mark
  local srcList = fromSource(self, "Cosmetics")
  for _, e in ipairs(type(srcList) == "table" and srcList or {}) do
    if type(e) == "table" and e.key == rw.key and e.owned ~= nil then owned = e.owned and true or false end
  end
  if owned == nil and s and s.cosmetics[rw.key] == true then owned = true end
  -- an id the game gave is kept, so the next session asks for it directly
  if id and id ~= known then self.foundIds = self.foundIds or {} self.foundIds[rw.key] = id end
  -- a reward not found is asked again only after REWARD_MISS (the toy box search is long); a found one after REWARD_CACHE
  self.rewardCache[rw.key] = { at = now + (id and 0 or (self.REWARD_MISS - self.REWARD_CACHE)), owned = owned, icon = icon, id = id }
  return owned, icon, id
end

-- the reward track: { { key, kind, name, points, reached, owned, icon, next } } in threshold order
function L:Rewards(points)
  points = points or (self:Points())
  local out, nextSet = {}, false
  for _, rw in ipairs(self.COSMETICS) do
    local owned, icon, id = self:FindReward(rw)
    local e = { key = rw.key, kind = rw.kind, name = rw.name, points = rw.points, reached = points >= rw.points, owned = owned, icon = icon, id = id,
      fallback = rw.fallback, unverified = rw.unverified }
    if not e.reached and not nextSet then e.next, nextSet = true, true end
    out[#out + 1] = e
  end
  return out
end
-- 0.8.4's name for the rewards (kept for anything that still asks)
function L:Cosmetics() return self:Rewards() end

-------------------------------------------------------------------------------
-- The perk plan (this character)
-------------------------------------------------------------------------------
function L:Tree(key)
  for _, t in ipairs(self.TREES) do if t.key == key then return t end end
  return nil
end
function L:Perk(id)
  for _, p in ipairs(self.PERKS) do if p.id == id then return p end end
  return nil
end
-- the perks of the launch trees (or of one tree), by tier then column
function L:Perks(tree)
  local out = {}
  for _, p in ipairs(self.PERKS) do if p.tree and (not tree or p.tree == tree) then out[#out + 1] = p end end
  local order = {}
  for i, t in ipairs(self.TREES) do order[t.key] = i end
  table.sort(out, function(a, b)
    if a.tree ~= b.tree then return (order[a.tree] or 9) < (order[b.tree] or 9) end
    if a.gate ~= b.gate then return a.gate < b.gate end
    return a.col < b.col
  end)
  return out
end
-- the name and the words of a perk: the game's own when this client gives them, else the shipped ones
function L:PerkName(p)
  local f = G("C_Spell.GetSpellName")
  if f and p.id then
    local ok, n = pcall(f, p.id)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return p.name or ""
end
function L:PerkText(p) return p.text or "" end
-- what rank r of a perk gives, in our words (never the client's tooltip: several show stale single values)
function L:RankText(p, r)
  local per = p.per
  if type(per) ~= "table" then return "" end
  if per.text then return per.text end
  local v
  if per.list then v = per.list[r] else v = (per.step or 0) * r end
  if v == nil then return "" end
  return (per.fmt or "%d"):format(v)
end
function L:PerkIcon(p)
  local t = p.id and Panoply.Icons:Spell(p.id)   -- 0.9.7 hotfix: the one shared lookup (Core/CompatModules.lua)
  if t then return t end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- 0.9.5 phase 4G (spec 01 section 8): the perks that change the Professions page's Camp tab and Next card (Field Guide, Reagent Economy,
-- Dedicated Study), when this character has them in the game or in its plan: { { perk, name, rank, state = "owned" | "planned", text } }
function L:CampPerks()
  local out = {}
  if not self:Here() then return out end
  local plan, actual = self:Plan(), self:Actual()
  for _, p in ipairs(self.PERKS or {}) do
    if p.affects == "camp" then
      local own = actual and whole(actual[p.id]) or 0
      local planned = whole(plan[p.id])
      local r = own > 0 and own or planned
      if r > 0 then
        out[#out + 1] = { perk = p, name = self:PerkName(p), rank = r, max = p.ranks or 1, state = own > 0 and "owned" or "planned", text = self:RankText(p, r) }
      end
    end
  end
  return out
end
-- one line for a perk: "Field Guide (planned, 2 of 3): 17% shorter camp cooldown"
function L.CampPerkLine(e)
  local how = e.state == "owned" and "you have it" or "planned"
  local rk = (e.max or 1) > 1 and (", %d of %d"):format(e.rank, e.max) or ""
  return ("%s (%s%s): %s"):format(e.name, how, rk, e.text ~= "" and e.text or "changes your camp")
end

function L:Plan()
  local c = self:Char()
  return type(c.plan) == "table" and c.plan or {}
end
function L:PlanRank(id, plan) plan = plan or self:Plan() return whole(plan[id]) end
function L:PlanTotal(plan)
  plan = plan or self:Plan()
  local n = 0
  for _, p in ipairs(self:Perks()) do n = n + self:PlanRank(p.id, plan) end
  return n
end
-- points in a tree on perks below a gate (the tiers above a row), or in the whole tree
function L:TreePoints(tree, plan, belowGate)
  plan = plan or self:Plan()
  local n = 0
  for _, p in ipairs(self:Perks(tree)) do
    if not belowGate or p.gate < belowGate then n = n + self:PlanRank(p.id, plan) end
  end
  return n
end
-- Is a plan one the game would allow? Every rank within its perk, the 16-point cap, every gate (enough points in the tiers above),
-- every prerequisite full. Returns ok, and the first reason it is not.
function L:Validate(plan)
  local total = 0
  for id, r in pairs(plan) do
    local p = self:Perk(id)
    r = whole(r)
    if r > 0 then
      if not (p and p.tree) then return false, "That perk is not in a tree." end
      if r > p.ranks then return false, ("%s has %d %s."):format(p.name, p.ranks, plural(p.ranks, "rank")) end
      total = total + r
    end
  end
  if total > self.CAP then return false, ("A character has %d points."):format(self.CAP) end
  for _, p in ipairs(self:Perks()) do
    if self:PlanRank(p.id, plan) > 0 then
      if p.gate > 0 and self:TreePoints(p.tree, plan, p.gate) < p.gate then
        return false, ("%s needs %d points in %s first."):format(p.name, p.gate, self:Tree(p.tree).name)
      end
      if p.prereq then
        local q = self:Perk(p.prereq)
        if q and self:PlanRank(q.id, plan) < q.ranks then return false, ("%s needs %s at full rank first."):format(p.name, q.name) end
      end
    end
  end
  return true
end
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
-- can one rank be added (removed)? ok, reason
function L:CanAdd(id)
  local p = self:Perk(id)
  if not (p and p.tree) then return false, "Not a perk of the trees." end
  local plan = copy(self:Plan())
  if self:PlanRank(id, plan) >= p.ranks then return false, "Already at full rank." end
  plan[id] = self:PlanRank(id, plan) + 1
  return self:Validate(plan)
end
function L:CanRemove(id)
  local plan = copy(self:Plan())
  local r = self:PlanRank(id, plan)
  if r <= 0 then return false, "No rank planned." end
  plan[id] = r > 1 and (r - 1) or nil
  return self:Validate(plan)
end
local function setPlan(self, plan)
  local c = self:Char(true)
  if c == BLANK then return false end
  c.plan = plan
  changed("plan")
  return true
end
function L:AddRank(id)
  if not self:CanAdd(id) then return false end
  local plan = copy(self:Plan())
  plan[id] = self:PlanRank(id, plan) + 1
  return setPlan(self, plan)
end
function L:RemoveRank(id)
  if not self:CanRemove(id) then return false end
  local plan = copy(self:Plan())
  local r = self:PlanRank(id, plan)
  plan[id] = r > 1 and (r - 1) or nil
  return setPlan(self, plan)
end
function L:ClearPlan()
  if next(self:Plan()) == nil then return false end
  return setPlan(self, {})
end
function L:Preset(key)
  for _, p in ipairs(self.PRESETS) do if p.key == key then return p end end
  return nil
end
-- a preset fills the plan (on a click). Only a valid build is ever written.
function L:ApplyPreset(key)
  local pre = self:Preset(key)
  if not pre or not self:Validate(pre.ranks) then return false end
  return setPlan(self, copy(pre.ranks))
end
function L:PresetOn(key)
  local pre = self:Preset(key)
  if not pre then return false end
  local plan = self:Plan()
  for _, p in ipairs(self:Perks()) do if self:PlanRank(p.id, plan) ~= whole(pre.ranks[p.id]) then return false end end
  return true
end
-- a tier row of a tree is open when the plan has enough points in the tiers above it
function L:TierOpen(tree, gate, plan) return gate <= 0 or self:TreePoints(tree, plan, gate) >= gate end

-- the ranks the game says this character has (a source), or nil
function L:Actual()
  local v = fromSource(self, "Ranks")
  return type(v) == "table" and v or nil
end

-------------------------------------------------------------------------------
-- Spent points and the meter
-------------------------------------------------------------------------------
function L:SpentLive()
  local t = fromSource(self, "Spent")
  if type(t) == "table" then return t end
  local a = self:Actual()
  if a then
    local out = {}
    for id, r in pairs(a) do
      local p = self:Perk(id)
      if p and p.tree then out[p.tree] = (out[p.tree] or 0) + whole(r) end
    end
    return out
  end
  return nil
end
-- points spent on this character: the game's (a source), else the plan when it is marked as spent, else 0.8.4's own numbers
function L:SpentTotal()
  local live = self:SpentLive()
  local c = self:Char()
  local n = 0
  if live then
    for _, t in ipairs(self.TREES) do n = n + whole(live[t.key]) end
    return n, "live"
  end
  if c.planSpent then return self:PlanTotal(), "plan" end
  for _, t in ipairs(self.TREES) do n = n + whole(c.spent and c.spent[t.key]) end
  return n, n > 0 and "recorded" or "none"
end
function L:Spent(tree)
  local live = self:SpentLive()
  if live then return whole(live[tree]) end
  local c = self:Char()
  if c.planSpent then return self:TreePoints(tree) end
  return whole(c.spent and c.spent[tree])
end
-- the plan is what this character spent in the game (the tick on the Perk plan tab, when the game does not say)
function L:PlanSpent() return self:Char().planSpent == true end
function L:SetPlanSpent(on)
  if self:SpentLive() then return false end
  local c = self:Char(true)
  if c == BLANK then return false end
  c.planSpent = on and true or nil
  changed("plan")
  return true
end

-- The meter: { cap, spent, left (under the cap), points (the account's), live, short (spent more than the account has),
-- unspent (points this character could spend and has not) }
function L:Meter(states)
  local spent, how = self:SpentTotal()
  local points, live = self:Points(states)
  local can = min(points, self.CAP)
  return { cap = self.CAP, spent = spent, left = max(0, self.CAP - spent), points = points, live = live, short = spent > points,
    unspent = max(0, can - spent), how = how }
end

-------------------------------------------------------------------------------
-- Next points: the nearest points this character can earn
-------------------------------------------------------------------------------
-- { { id, label, dist (text), left (share still to go, 0..1), link = { kind, ... }, locked, until, parts } } nearest first, locked last
function L:NextPoints(states)
  states = states or self:States()
  local me = self:MeEntry()
  local out, locked = {}, {}
  -- a Hardcore character's progress does not count for the account's points: nothing here is earnable by it
  local earnable = not me.hc
  local function share(cur, target, prev) local span = max(1, target - (prev or 0)) return max(0, min(1, (target - cur) / span)) end
  -- the class: the next level of this character's class not done yet
  if earnable and me.classFile and me.level then
    local prev = 1
    for _, lv in ipairs(self.CLASS_LEVELS) do
      local r = self:Row(("class.%s.%d"):format(me.classFile, lv))
      local st = r and states[r.id]
      if st and st.state ~= "done" and not st.manual then
        local togo = max(0, lv - me.level)
        out[#out + 1] = { id = r.id, label = r.label, dist = ("%d %s to go"):format(togo, plural(togo, "level")),
          left = share(me.level, lv, prev), link = { kind = "guide" }, cat = "classes" }
        break
      end
      prev = lv
    end
  end
  -- tradeskills: the next mark of each crafting tradeskill this character has
  for _, prof in ipairs(self.TRADESKILLS) do
    local cur = me.profs and me.profs[prof]
    if earnable and cur then
      local prev = 0
      for _, at in ipairs(self.TRADESKILL_LEVELS) do
        local r = self:Row(("trade.%s.%d"):format(prof, at))
        local st = r and states[r.id]
        if st and st.state ~= "done" and not st.manual then
          out[#out + 1] = { id = r.id, label = r.label, dist = ("%d skill to go"):format(max(0, at - cur)), left = share(cur, at, prev),
            link = { kind = "professions", prof = prof }, cat = "tradeskills" }
          break
        end
        prev = at
      end
    end
  end
  -- Spelunker: a band this character is in, with the dungeons left
  for _, t in ipairs(self.SPELUNKER) do
    local r = self:Row("dng." .. t.key)
    local st = r and states[r.id]
    if earnable and st and st.state ~= "done" and (me.level or 0) >= t.from then
      local left, parts = 0, {}
      for _, d in ipairs(st.parts or {}) do if not d.done then left = left + 1 parts[#parts + 1] = d end end
      out[#out + 1] = { id = r.id, label = r.label, dist = ("%d %s left"):format(left, plural(left, "dungeon")), left = left / max(1, #(st.parts or {})),
        link = { kind = "dungeons" }, parts = parts, cat = "dungeons" }
    end
  end
  -- exploration and the questline, when they are read
  local ex = states["adv.explore"]
  if earnable and ex and ex.state == "progress" then
    out[#out + 1] = { id = "adv.explore", label = self.EXPLORE.name, dist = ("%.1f%% explored"):format(ex.have or 0), left = (100 - (ex.have or 0)) / 100, cat = "adventure" }
  end
  local vq = states["adv.valthalak"]
  if earnable and vq and vq.state ~= "done" and not vq.manual and (me.level or 0) >= 58 then
    local n = #self.VALTHALAK.steps
    out[#out + 1] = { id = "adv.valthalak", label = self.VALTHALAK.name, dist = ("step %d of %d"):format(min(n, (vq.have or 0) + 1), n),
      left = (n - (vq.have or 0)) / n, cat = "adventure" }
  end
  table.sort(out, function(a, b) if a.left ~= b.left then return a.left < b.left end return a.label < b.label end)
  -- what is locked, with its date, at the bottom
  for _, r in ipairs(self:BuildRows()) do
    local st = states[r.id]
    if st and st.state == "locked" then
      locked[#locked + 1] = { id = r.id, label = r.label, dist = "Opens " .. self.DateText(st["until"]), locked = true, ["until"] = st["until"], cat = r.cat }
    end
  end
  for _, e in ipairs(locked) do out[#out + 1] = e end
  return out
end

-------------------------------------------------------------------------------
-- Doors
-------------------------------------------------------------------------------
L.TABS = { { "next", "Next points" }, { "challenges", "Challenges" }, { "plan", "Perk plan" } }
L.OLD_TABS = { perks = "plan", cosmetics = "challenges" }   -- 0.8.4's tabs, for links and saved state that still name them
L.tab = "next"

function L:Here() return C.IsForever() end
function L.ValidTab(k) for _, t in ipairs(L.TABS) do if t[1] == k then return true end end return L.OLD_TABS[k] ~= nil end

-- Open the Legacy page (other pages link here). tab: "next", "challenges" or "plan" (0.8.4's "perks" and "cosmetics" still work).
-- On Classic Era there is no Legacy system, so there is no L.Open at all there (it is taken away at the end of this file): a
-- page that links here "if present" tests `Panoply.Legacy and Panoply.Legacy.Open` and shows no link on Era.
function L:Open(tab)
  if not self:Here() then return false end
  tab = self.OLD_TABS[tab] or tab
  for _, t in ipairs(self.TABS) do if t[1] == tab then self.tab = tab end end
  return Panoply.Menu:Open("legacy")
end

-- The game's own Legacy window, where points are really spent. Only on a click, never in combat.
function L:CanOpenGame() return type(_G.ToggleLegacySystemUI) == "function" end
function L:OpenGame()
  if not self:CanOpenGame() then Panoply:Print("This game client has no Legacy window to open.") return false end
  if C.InCombat() then Panoply:Print("Open the Legacy window after the fight.") return false end
  local ok, err = pcall(_G.ToggleLegacySystemUI)
  if not ok then Panoply:Debug("legacy window", err) Panoply:Print("The game would not open its Legacy window.") return false end
  return true
end

-------------------------------------------------------------------------------
-- When the cache is saved (WoW Forever only): a moment after login, and after the things it reads change
-------------------------------------------------------------------------------
L.COLLECT_DELAY = 3
function L:Soon()
  if self.pending or not self:Here() then return end
  self.pending = true
  C.After(self.COLLECT_DELAY, function() L.pending = nil L:Collect() end)
end
if L:Here() then
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA",
    "MAP_EXPLORATION_UPDATED" }) do
    Panoply:On(ev, function() L:Soon() end)
  end
  Panoply:On("BOSS_KILL", function(_, _, name) L:NoteKill(name) end)
end

if not L:Here() then L.Open = nil end
