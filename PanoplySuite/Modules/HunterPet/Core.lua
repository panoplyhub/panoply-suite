-- Panoply Suite, the hunter's pet (0.8.4; the Pet tab of the Hunter Class Guide): the planner behind the panel.
--   * Families: what each pet family eats and which abilities it can learn (Modules/HunterPet/Data.lua, per client).
--   * A plan per family: the rank wanted of each ability. The main pet family's plan is the one the page opens on; plans for
--     other families are saved beside it.
--   * What is still to learn: for each wanted rank the hunter has not learned and the pet does not know, the wild beasts that
--     know it (their level, their zone, whether this hunter can tame them yet), or "bought from a pet trainer".
--   * The to-tame list: as few beasts as cover the missing ranks, in level order, each with a map marker on request.
--   * Training points: what the wanted ranks cost against the points a pet of a level and loyalty has.
-- This file moves nothing, targets nothing, tames nothing and trains nothing (hub rule 2 of CLAUDE.md): it reads, counts and adds
-- waypoints the player asked for. Map markers go through the Waypoints list (Modules/Map/Navigate.lua, Modules/Waypoints); there is
-- no second movement system here. A marker's position is never made up: it is where Panoply Suite's own NPC data puts the beast, or
-- where the player met it.
-- Saved (new keys, nothing renamed): PanoplySuiteCharDB.hunterPet = { v, main, view, plans, learned, pets, log } with the character,
-- and PanoplySuiteDB.hunterPetBeasts = { era = {...}, forever = {...} } (beasts this account has met or tamed) with the account.
local ADDON, Panoply = ...
local C = Panoply.Compat
local D = Panoply.HunterPetData

local P = { rev = 0, panels = {} }
Panoply.HunterPet = P

P.MAX_LEVEL = 60
P.MAX_LOYALTY = 6
P.LOG_CAP = 40
P.TEACHERS_SHOWN = 2      -- beasts listed under a missing rank in Planner (To tame has them all)

local floor, max, min = math.floor, math.max, math.min

-------------------------------------------------------------------------------
-- The client's facts
-------------------------------------------------------------------------------
function P.Client() return (C.IsEra and C.IsEra()) and "era" or "forever" end
function P:Data() return D.clients[P.Client()] end

function P.IsHunter()
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  return info.classFile == "HUNTER"
end

function P.HunterLevel()
  local level = C.XP and C.XP() or 1
  return type(level) == "number" and level or 1
end

-- the families this client has, by name
function P:Families() return self:Data().families end

function P:IsFamily(fam)
  for _, f in ipairs(self:Families()) do if f == fam then return true end end
  return false
end

-- the family's name as this client calls it (Classic Era's Owl is WoW Forever's Bird of Prey)
function P:FamilyName(fam)
  local rec = D.families[fam]
  if rec and rec.eraName and P.Client() == "era" then return rec.eraName end
  return fam
end

-- our family for the name the game gives a pet (English names; nil when it is not one of ours)
function P:FamilyKey(gameName)
  if type(gameName) ~= "string" or gameName == "" then return nil end
  local q = gameName:lower()
  for _, fam in ipairs(self:Families()) do
    local rec = D.families[fam]
    if fam:lower() == q or (rec and rec.eraName and rec.eraName:lower() == q) then return fam end
  end
  return nil
end

function P:Diet(fam)
  local rec = D.families[fam]
  return rec and rec.diet or {}
end

-- "meat and fish" / "fish, bread, fungus and fruit" / "anything: meat, fish, ..."
function P:DietText(fam)
  local diet = self:Diet(fam)
  local n = #diet
  if n == 0 then return "" end
  local words = {}
  for i, f in ipairs(diet) do words[i] = f:lower() end
  local list = n == 1 and words[1] or (table.concat(words, ", ", 1, n - 1) .. " and " .. words[n])
  if n == #D.FOODS then return "anything: " .. list end
  return list
end

-- The abilities a family can learn on this client, in the order the page shows them: the ones learned by taming first (the lowest
-- pet level first), then the ones bought from a pet trainer (Growl first). An entry: { key, def, kind, first, max, ranks }, where
-- ranks are the ranks this family can use (a family may start above rank 1).
function P:Abilities(fam)
  local client = P.Client()
  self.abilityCache = self.abilityCache or {}
  local ck = client .. "|" .. tostring(fam)
  if self.abilityCache[ck] then return self.abilityCache[ck] end
  local out = {}
  for key, def in pairs(self:Data().abilities) do
    local can = def.users == "all"
    if not can then for _, u in ipairs(def.users) do if u == fam then can = true break end end end
    if can and self:IsFamily(fam) then
      local first = def.first and def.first[fam] or 1
      local ranks = {}
      for _, r in ipairs(def.ranks) do if r.r >= first then ranks[#ranks + 1] = r end end
      if #ranks > 0 then
        out[#out + 1] = { key = key, def = def, kind = def.kind, first = ranks[1].r, max = ranks[#ranks].r, ranks = ranks }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return a.kind == "wild" end
    if a.kind == "trainer" and (a.key == "Growl") ~= (b.key == "Growl") then return a.key == "Growl" end
    local la, lb = a.ranks[1].lvl or 0, b.ranks[1].lvl or 0
    if a.kind == "wild" and la ~= lb then return la < lb end
    return a.key < b.key
  end)
  self.abilityCache[ck] = out
  return out
end

function P:Ability(fam, key)
  for _, a in ipairs(self:Abilities(fam)) do if a.key == key then return a end end
  return nil
end

-- the rank record of an ability on this client (any family)
function P:RankDef(key, rank)
  local def = self:Data().abilities[key]
  for _, r in ipairs(def and def.ranks or {}) do if r.r == rank then return r end end
  return nil
end

-- this client's spell ids: the pet's own spells, and the hunter's Beast Training ("teach") spells
function P:SpellIndex()
  if not self.spellIndex or self.spellIndexClient ~= P.Client() then
    self.spellIndex, self.teachIndex, self.spellIndexClient = {}, {}, P.Client()
    for key, def in pairs(self:Data().abilities) do
      for _, r in ipairs(def.ranks) do
        if r.pet then self.spellIndex[r.pet] = { key, r.r } end
        if r.teach then self.teachIndex[r.teach] = { key, r.r } end
      end
    end
  end
  return self.spellIndex, self.teachIndex
end

-- { ability, rank } for a spell id the game names when the hunter learns a rank (the Beast Training spell, or the pet's own)
function P:ResolveLearned(id)
  local pet, teach = self:SpellIndex()
  local hit = type(id) == "number" and (teach[id] or pet[id])
  if hit then return hit[1], hit[2] end
  return nil
end

-- { ability, rank } for a pet's own spell id, or for its name and rank text ("Rank 3") from the pet's spellbook
function P:ResolveSpell(id, name, rankText)
  local hit = type(id) == "number" and self:SpellIndex()[id]
  if hit then return hit[1], hit[2] end
  local def = type(name) == "string" and self:Data().abilities[name]
  if not def then return nil end
  local n = tonumber(type(rankText) == "string" and rankText:match("%d+") or rankText)
  if not n and #def.ranks == 1 then n = def.ranks[1].r end
  if n and self:RankDef(name, n) then return name, n end
  return nil
end

-------------------------------------------------------------------------------
-- Saved with the character and the account
-------------------------------------------------------------------------------
local BLANK = { plans = {}, learned = {}, pets = {}, log = {} }

-- the character's saved table; reading never makes it (create: a writer asks for it). Second result: it can be written to.
function P:Store(create)
  local cdb = Panoply.cdb
  if type(cdb) ~= "table" then return BLANK, false end
  local s = cdb.hunterPet
  if type(s) ~= "table" then
    if not create then return BLANK, false end
    s = {}
    cdb.hunterPet = s
  end
  s.v = s.v or 1
  for _, k in ipairs({ "plans", "learned", "pets", "log" }) do if type(s[k]) ~= "table" then s[k] = {} end end
  return s, true
end

-- beasts this account has met or tamed, on this client: [name] = { m, x, y, lvl, n = tames, knows = { ability = rank }, miss = { "Bite:3" = true } }
function P:Beasts(create)
  local db = Panoply.db
  if type(db) ~= "table" then return {}, false end
  local client = P.Client()
  if type(db.hunterPetBeasts) ~= "table" or type(db.hunterPetBeasts[client]) ~= "table" then
    if not create then return {} end
    if type(db.hunterPetBeasts) ~= "table" then db.hunterPetBeasts = {} end
    db.hunterPetBeasts[client] = {}
  end
  return db.hunterPetBeasts[client], true
end

function P:Changed(why)
  self.rev = self.rev + 1
  Panoply:Fire("HUNTERPET_CHANGED", why)
end

-- the main pet family (the player's choice; until there is one, the family of the pet that is out)
function P:Main()
  local s = self:Store()
  if s.main and self:IsFamily(s.main) then return s.main end
  if self.pet and self.pet.family then return self.pet.family end
  return nil
end
function P:SetMain(fam)
  if not self:IsFamily(fam) then return false end
  local s, ok = self:Store(true)
  if not ok then return false end
  s.main = fam
  self:Plan(fam, true)
  self:Changed("main")
  return true
end

-- the family the page shows: the last one looked at, else the main family, else the first in the list
function P:View()
  local s = self:Store()
  if s.view and self:IsFamily(s.view) then return s.view end
  return self:Main() or self:Families()[1]
end
function P:SetView(fam)
  if not self:IsFamily(fam) then return false end
  local s, ok = self:Store(true)
  if not ok then return false end
  s.view = fam
  self:Changed("view")
  return true
end

-- the saved plan of a family: { want = { ability = rank (0 = leave it out) }, pick = { "Bite:3" = beast }, level, loyalty }
function P:Plan(fam, create)
  local s, ok = self:Store(create)
  local p = s.plans[fam]
  if type(p) ~= "table" then
    if not (create and ok and self:IsFamily(fam)) then return nil end
    p = {}
    s.plans[fam] = p
  end
  if type(p.want) ~= "table" then p.want = {} end
  if type(p.pick) ~= "table" then p.pick = {} end
  return p
end
function P:HasPlan(fam) return self:Plan(fam) ~= nil end
function P:SavePlan(fam)
  if not self:Plan(fam, true) then return false end
  self:Changed("plan")
  return true
end
function P:RemovePlan(fam)
  local s = self:Store()
  if not s.plans[fam] then return false end
  s.plans[fam] = nil
  if s.main == fam then s.main = nil end
  self:Changed("plan")
  return true
end
-- the families with a saved plan: the main one first, then by name
function P:SavedPlans()
  local s = self:Store()
  local out = {}
  for fam in pairs(s.plans) do if self:IsFamily(fam) then out[#out + 1] = fam end end
  local main = s.main
  table.sort(out, function(a, b) if (a == main) ~= (b == main) then return a == main end return a < b end)
  return out
end

-- The rank wanted of an ability: the plan's. Until the plan says, an ability learned by taming is wanted at the highest rank the
-- family can use, and so is Growl (it costs no points); the other ranks a pet trainer sells cost training points a pet cannot
-- pay for all at once, so they start left out and the player adds the ones they want on the Training points tab.
function P:Want(fam, key)
  local a = self:Ability(fam, key)
  if not a then return 0 end
  local p = self:Plan(fam)
  local w = p and p.want[key]
  if type(w) ~= "number" then return (a.kind == "wild" or key == "Growl") and a.max or 0 end
  if w <= 0 then return 0 end
  return max(a.first, min(a.max, floor(w)))
end
-- set it (0 = leave the ability out); a rank below the family's first one is "out". Saves the plan.
function P:SetWant(fam, key, rank)
  local a = self:Ability(fam, key)
  local p = a and self:Plan(fam, true)
  if not p then return false end
  rank = floor(tonumber(rank) or 0)
  if rank < a.first then rank = 0 end
  p.want[key] = min(a.max, rank)
  self:Changed("want")
  return true
end

-- has this hunter learned the rank (so it can be taught to a pet)? Ranks every hunter starts with count.
function P:Learned(key, rank)
  local s = self:Store()
  if s.learned[key] and s.learned[key][rank] then return true end
  local r = self:RankDef(key, rank)
  return r and r.auto and true or false
end
function P:SetLearned(key, rank, on, quiet)
  local s, ok = self:Store(true)
  if not (ok and self:RankDef(key, rank)) then return false end
  local was = s.learned[key] and s.learned[key][rank] and true or false
  if was == (on and true or false) then return false end
  s.learned[key] = s.learned[key] or {}
  s.learned[key][rank] = on and true or nil
  if next(s.learned[key]) == nil then s.learned[key] = nil end
  if not quiet then self:Changed("learned") end
  return true
end

-- the ranks a pet of this family has: the pet that is out when it is of this family, else the last pet of the family that was seen
function P:PetOf(fam)
  if self.pet and self.pet.family == fam then return self.pet, true end
  local s = self:Store()
  local snap = s.pets[fam]
  if type(snap) == "table" then return snap, false end
  return nil, false
end
function P:PetRank(fam, key)
  local pet = self:PetOf(fam)
  local r = pet and type(pet.ranks) == "table" and pet.ranks[key]
  return type(r) == "number" and r or 0
end

-- "pet" (the pet knows it), "learned" (the hunter can teach it) or "missing"
function P:RankState(fam, key, rank)
  if self:PetRank(fam, key) >= rank then return "pet" end
  if self:Learned(key, rank) then return "learned" end
  return "missing"
end

-------------------------------------------------------------------------------
-- Teachers
-------------------------------------------------------------------------------
local function needKey(key, rank) return key .. ":" .. rank end
P.NeedKey = needKey

-- This client's teacher records: [ability (this client's own name)][rank] = { record }. D.teachersBy when a data file provides it;
-- otherwise Data.lua's research ledger list (the records carry no src: the ledger is their source, and a Forever-only beast is left
-- out on Classic Era).
function P:TeacherTable()
  local by = D.teachersBy and D.teachersBy[P.Client()]
  if by then return by end
  local era = P.Client() == "era"
  local out = {}
  for ability, byRank in pairs(D.teachers) do
    local key = ability
    if era then for eraName, foreverName in pairs(D.ERA_ALIAS) do if foreverName == ability then key = eraName end end end
    out[key] = {}
    for rank, list in pairs(byRank) do
      out[key][rank] = {}
      for _, t in ipairs(list) do if not (era and t.f) then table.insert(out[key][rank], t) end end
    end
  end
  return out
end

-- The wild beasts that know a rank, on this client: the list's (without the ones this account tamed and found not to know it), then
-- the ones this account's own tames found. A copy per call: { n, lo, hi, z, area, inst, rare, elite, own, fam, src, led, page, read,
-- id, ids, nomatch, alt } (src: "ledger"; alt: both sides' facts where two sources differ).
function P:Teachers(key, rank)
  local list = self:TeacherTable()[key]
  local beasts = self:Beasts()
  local nk = needKey(key, rank)
  local out, seen = {}, {}
  for _, t in ipairs(list and list[rank] or {}) do
    local b = beasts[t.n]
    local missed = b and type(b.miss) == "table" and b.miss[nk]
    if not missed and not seen[t.n] then
      seen[t.n] = true
      out[#out + 1] = { n = t.n, lo = t.lo, hi = t.hi, z = t.z, area = t.area, inst = t.inst, rare = t.rare, elite = t.elite,
        fam = t.fam, src = t.src or "ledger", led = t.led, page = t.page, read = t.read, id = t.id, ids = t.ids, nomatch = t.nomatch, alt = t.alt }
    end
  end
  local own = {}
  for name, b in pairs(beasts) do
    if not seen[name] and type(b) == "table" and type(b.knows) == "table" and b.knows[key] == rank then own[#own + 1] = name end
  end
  table.sort(own)
  for _, name in ipairs(own) do
    local b = beasts[name]
    local zone = b.m and C.MapName and C.MapName(b.m) or nil
    out[#out + 1] = { n = name, lo = b.lvl or 0, hi = b.lvl or 0, z = zone or "", own = true }
  end
  return out
end

-- "level 16-17, Silverpine Forest (Tirisfal entrance)" (capital: "Level ..." to start a sentence)
function P:WhereText(t, capital)
  local word = capital and "Level " or "level "
  local lv = (t.lo and t.lo > 0) and ((t.lo == t.hi or not t.hi) and (word .. t.lo) or (word .. t.lo .. "-" .. t.hi)) or nil
  local zone = (t.z and t.z ~= "") and (t.z .. (t.area and (" (" .. t.area .. ")") or "")) or nil
  if lv and zone then return lv .. ", " .. zone end
  return lv or zone or ""
end

-- can this hunter tame it now, and the sentence that says so (a hunter cannot tame a beast above their own level)
function P:TameText(t, level)
  level = level or P.HunterLevel()
  local can = (t.lo or 0) <= level
  local parts = { can and "You can tame it now." or ("Too high for you yet: you can tame it from level %d."):format(t.lo) }
  if t.inst == "dungeon" then parts[#parts + 1] = "It lives inside a dungeon."
  elseif t.inst == "raid" then parts[#parts + 1] = "It lives inside a raid." end
  if t.rare then parts[#parts + 1] = "A rare beast, so it is not always there." end
  if t.elite then parts[#parts + 1] = "It is an elite." end
  if t.own then parts[#parts + 1] = "From your own tames." end
  return table.concat(parts, " "), can
end

-- "2026-11-14" as "14 Nov 2026" (the text unchanged when it is not a date)
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function P.DateWords(iso)
  local y, m, d = tostring(iso or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y or not MONTHS[tonumber(m)] then return tostring(iso or "") end
  return ("%d %s %s"):format(tonumber(d), MONTHS[tonumber(m)], y)
end

-- where one beast's facts come from, in plain words: "Source: Panoply Suite's research ledger, 9 Nov 2026." or "Source: your own tame."
function P:SourceText(t)
  if t.own then return "Source: your own tame." end
  local led = (D.SOURCES or {}).ledger or {}
  return ("Source: Panoply Suite's research ledger, %s."):format(P.DateWords(led.read or "2026-11-09"))
end

-------------------------------------------------------------------------------
-- What is still to learn
-------------------------------------------------------------------------------
-- The ranks of one ability the plan still needs: from the best rank the hunter's level can already use (lower ranks are no use any
-- more) up to the wanted rank, each one neither on the pet nor learned.
function P:NeededRanks(fam, a, level)
  local want = self:Want(fam, a.key)
  if want <= 0 then return {} end
  level = level or P.HunterLevel()
  local from = a.first
  for _, r in ipairs(a.ranks) do if r.r <= want and (r.lvl or 0) <= level then from = r.r end end
  local out = {}
  for _, r in ipairs(a.ranks) do
    if r.r >= from and r.r <= want and self:RankState(fam, a.key, r.r) == "missing" then out[#out + 1] = r end
  end
  return out
end

-- Everything the family's plan still needs: wild = { { key, rank, def (the rank record), teachers } }, trainer = { { key, rank, def } }
function P:Missing(fam)
  local out = { wild = {}, trainer = {} }
  local level = P.HunterLevel()
  for _, a in ipairs(self:Abilities(fam)) do
    for _, r in ipairs(self:NeededRanks(fam, a, level)) do
      if a.kind == "trainer" then
        out.trainer[#out.trainer + 1] = { key = a.key, rank = r.r, def = r }
      else
        out.wild[#out.wild + 1] = { key = a.key, rank = r.r, def = r, teachers = self:Teachers(a.key, r.r) }
      end
    end
  end
  return out
end

-- "Bite rank 3, Claw rank 2"
function P.RanksText(list)
  local t = {}
  for _, n in ipairs(list) do t[#t + 1] = ("%s rank %d"):format(n.key, n.rank) end
  return table.concat(t, ", ")
end

-- The to-tame list of a family's plan: as few beasts as cover the missing ranks (a beast the player picked for a rank keeps it), in
-- level order. Returns list = { { n, t = the beast's record, teaches = { { key, rank } }, others = n more beasts for its first
-- rank } }, unknown = ranks no beast is known for, trainer = ranks bought from a pet trainer.
function P:ToTame(fam)
  local missing = self:Missing(fam)
  local plan = self:Plan(fam)
  local level = P.HunterLevel()
  local needs, unknown = {}, {}
  for _, n in ipairs(missing.wild) do
    if #n.teachers == 0 then
      unknown[#unknown + 1] = n
    else
      local cands = n.teachers
      local pick = plan and plan.pick[needKey(n.key, n.rank)]
      if pick then
        for _, t in ipairs(n.teachers) do if t.n == pick then cands = { t } break end end
      end
      needs[#needs + 1] = { key = n.key, rank = n.rank, cands = cands, all = n.teachers }
    end
  end
  local list = {}
  local left = #needs
  while left > 0 do
    -- how many of the ranks still open each beast covers
    local score, rec, order = {}, {}, {}
    for _, n in ipairs(needs) do
      if not n.done then
        for _, t in ipairs(n.cands) do
          if not score[t.n] then score[t.n] = 0 rec[t.n] = t order[#order + 1] = t.n end
          score[t.n] = score[t.n] + 1
        end
      end
    end
    local function better(a, b)
      if score[a] ~= score[b] then return score[a] > score[b] end
      local ta, tb = rec[a], rec[b]
      if (ta.inst ~= nil) ~= (tb.inst ~= nil) then return ta.inst == nil end
      if (ta.rare or false) ~= (tb.rare or false) then return not ta.rare end
      local ca, cb = (ta.lo or 0) <= level, (tb.lo or 0) <= level
      if ca ~= cb then return ca end
      if (ta.lo or 0) ~= (tb.lo or 0) then return (ta.lo or 0) < (tb.lo or 0) end
      return a < b
    end
    local best
    for _, name in ipairs(order) do if not best or better(name, best) then best = name end end
    local entry = { n = best, t = rec[best], teaches = {}, others = 0 }
    for _, n in ipairs(needs) do
      if not n.done then
        for _, t in ipairs(n.cands) do
          if t.n == best then
            n.done = true
            left = left - 1
            if #entry.teaches == 0 then entry.others = #n.all - 1 entry.first = n end
            entry.teaches[#entry.teaches + 1] = { key = n.key, rank = n.rank }
            break
          end
        end
      end
    end
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b)
    if (a.t.lo or 0) ~= (b.t.lo or 0) then return (a.t.lo or 0) < (b.t.lo or 0) end
    if (a.t.hi or 0) ~= (b.t.hi or 0) then return (a.t.hi or 0) < (b.t.hi or 0) end
    return a.n < b.n
  end)
  return { list = list, unknown = unknown, trainer = missing.trainer }
end

-- "Other beast": the next beast that knows the entry's first rank takes its place in the list (the choice is kept with the plan)
function P:NextChoice(fam, entry)
  local n = entry and entry.first
  local plan = n and #n.all > 1 and self:Plan(fam, true)
  if not plan then return false end
  local at = 1
  for i, t in ipairs(n.all) do if t.n == entry.n then at = i break end end
  plan.pick[needKey(n.key, n.rank)] = n.all[at % #n.all + 1].n
  self:Changed("pick")
  return true
end

-- "Learned it": tick the ranks a beast of the list teaches
function P:MarkLearned(entry)
  local any = false
  for _, n in ipairs(entry and entry.teaches or {}) do
    if self:SetLearned(n.key, n.rank, true, true) then any = true end
  end
  if any then self:Changed("learned") end
  return any
end

-------------------------------------------------------------------------------
-- Map markers (the Waypoints list; a position is our NPC data's or the player's own, never made up)
-------------------------------------------------------------------------------
-- the NPC ids that carry a name in Panoply Suite Quest Data (built once per data table, on first use)
function P:NpcIds(name)
  local QD = Panoply.QuestData
  local own = QD and QD.own
  if not (own and type(own.NpcIds) == "function" and type(own.Npc) == "function") then return {} end
  if self.npcIndexOwn ~= own then
    self.npcIndexOwn, self.npcIndex = own, {}
    local ok, ids = pcall(own.NpcIds)
    for _, id in ipairs(ok and type(ids) == "table" and ids or {}) do
      local okr, rec = pcall(own.Npc, id)
      if okr and type(rec) == "table" and type(rec.name) == "string" then
        local t = self.npcIndex[rec.name]
        if not t then t = {} self.npcIndex[rec.name] = t end
        t[#t + 1] = id
      end
    end
  end
  return self.npcIndex[name] or {}
end

-- where a beast can be found: where this account met it first, then the NPC data's places for its name
function P:Spots(name)
  local out = {}
  local b = self:Beasts()[name]
  if type(b) == "table" and b.m and b.x and b.y then out[#out + 1] = { map = b.m, x = b.x, y = b.y, own = true } end
  local QD = Panoply.QuestData
  for _, id in ipairs(self:NpcIds(name)) do
    local ok, spots = pcall(QD.NpcSpots, QD, id)
    for _, s in ipairs(ok and type(spots) == "table" and spots or {}) do
      if s.map and s.x and s.y then out[#out + 1] = { map = s.map, x = s.x, y = s.y } end
    end
  end
  return out
end

-- the spot nearest the player (the first one when the distance cannot be told)
function P:NearestSpot(name)
  local spots = self:Spots(name)
  if #spots == 0 then return nil end
  local pm, px, py = C.GetPlayerPos()
  local Nav = Panoply.Nav
  local best, bestD
  for _, s in ipairs(spots) do
    local d = pm and Nav and Nav.Distance and Nav.Distance(pm, px, py, s.map, s.x, s.y)
    if d and (not bestD or d < bestD) then best, bestD = s, d end
  end
  return best or spots[1], #spots
end

function P.MarkerLabel(entry)
  local teaches = entry.teaches and #entry.teaches > 0 and P.RanksText(entry.teaches) or nil
  return "Tame " .. entry.n .. (teaches and (": " .. teaches) or "")
end

-- put a spot in the waypoint list (first = the one the arrow follows); false and why when it cannot be done
function P:Place(spot, label, first)
  local Way = Panoply.Waypoints
  for _, wp in ipairs(Way and Way.List and Way:List() or {}) do
    if wp.m == spot.map and wp.note == label and math.abs(wp.x - spot.x) < 0.0005 and math.abs(wp.y - spot.y) < 0.0005 then return true, "already" end
  end
  local N = Panoply.Map and Panoply.Map.Navigate
  if N and N.Place then
    if N:Place({ map = spot.map, x = spot.x, y = spot.y, label = label }, first, "pet") then return true end   -- 0.9.5 4K: Map page group Pet tames
    return false, "off"
  end
  if Way and Way.active and Way.Add then
    local wp = Way:Add(spot.map, spot.x, spot.y, label, true, "pet")
    if not wp then return false, "off" end
    if first and #Way:List() > 1 then Way:Move(#Way:List(), 1) end
    return true
  end
  return false, "off"
end

-- "Map marker" on a beast of the list
function P:Mark(entry, first)
  local spot = self:NearestSpot(entry.n)
  if not spot then return false, "nowhere" end
  local ok, why = self:Place(spot, P.MarkerLabel(entry), first ~= false)
  if ok and why ~= "already" then Panoply:Print(("Map marker set: %s, %s."):format(entry.n, C.MapName(spot.map) or "on your map")) end
  if not ok then Panoply:Print("Switch on Waypoints (Map page, gear) to set map markers.") end
  return ok, why
end

-- "Mark where I stand": the player has found the beast; the place is kept for this account, and "Map marker" leads back to it
-- (no waypoint is added now: the player is standing on it)
function P:MarkHere(entry)
  local m, x, y = C.GetPlayerPos()
  if not m then Panoply:Print("Panoply Suite cannot tell where you are here, so no map marker was set.") return false, "nowhere" end
  local beasts, kept = self:Beasts(true)
  if not kept then return false, "nowhere" end
  local b = beasts[entry.n]
  if type(b) ~= "table" then b = {} beasts[entry.n] = b end
  b.m, b.x, b.y = m, floor(x * 10000 + 0.5) / 10000, floor(y * 10000 + 0.5) / 10000
  Panoply:Print(("Kept this place for %s. Its Map marker button brings you back here."):format(entry.n))
  self:Changed("spot")
  return true
end

-- "Mark them all": every beast of the list that has a known place, in the list's order at the front of the waypoint list.
-- With the Waypoints list switched off there is only the arrow: it is pointed at the first beast that has a place, and the player is told.
function P:MarkAll(fam)
  local tame = self:ToTame(fam)
  local n = 0
  if not (Panoply.Waypoints and Panoply.Modules and Panoply.Modules:IsOn("waypoints")) then
    for _, e in ipairs(tame.list) do
      local spot = self:NearestSpot(e.n)
      if spot and self:Place(spot, P.MarkerLabel(e), true) then
        Panoply:Print(("The arrow points at %s. Switch on Waypoints (Map page, gear) to mark the whole list."):format(e.n))
        return 1
      end
    end
    Panoply:Print("No map marker: none of these beasts has a known place yet.")
    return 0
  end
  for i = #tame.list, 1, -1 do
    local e = tame.list[i]
    local spot = self:NearestSpot(e.n)
    if spot then
      local ok, why = self:Place(spot, P.MarkerLabel(e), true)
      if not ok then Panoply:Print("Switch on Waypoints (Map page, gear) to set map markers.") return 0 end
      if why ~= "already" then n = n + 1 end
    end
  end
  Panoply:Print(n == 0 and "No new map markers: none of these beasts has a known place yet." or ("%d map marker%s set, in the list's order."):format(n, n == 1 and "" or "s"))
  return n
end

-- the nearest pet trainer the map already knows (Places on the map), through Go to
function P:GoToPetTrainer()
  local N = Panoply.Map and Panoply.Map.Navigate
  if not (N and N.Go) then Panoply:Print("The Map feature is not in this build, so there is no pet trainer to point at.") return false end
  return N:Go({ kind = "type", name = "Pet trainer", type = "placeTrainPet" })
end
function P:KnowsPetTrainers()
  local Places = Panoply.Map and Panoply.Map.Places
  local ok, n = pcall(function() return Places and Places.Count and Places.Count("placeTrainPet") or 0 end)
  return ok and type(n) == "number" and n > 0
end

-------------------------------------------------------------------------------
-- Training points
-------------------------------------------------------------------------------
-- The points a pet has to spend: its level times (its loyalty level - 1). The game's own number is shown beside it when the pet is out.
function P.Points(level, loyalty)
  return max(0, floor(level or 0)) * max(0, floor(loyalty or 1) - 1)
end

function P:PlanLevel(fam)
  local p = self:Plan(fam)
  local v = p and tonumber(p.level)
  return v and max(1, min(P.MAX_LEVEL, floor(v))) or P.MAX_LEVEL
end
function P:PlanLoyalty(fam)
  local p = self:Plan(fam)
  local v = p and tonumber(p.loyalty)
  return v and max(1, min(P.MAX_LOYALTY, floor(v))) or P.MAX_LOYALTY
end
function P:SetPlanLevel(fam, level)
  local p = self:Plan(fam, true)
  if not p then return false end
  p.level = max(1, min(P.MAX_LEVEL, floor(tonumber(level) or P.MAX_LEVEL)))
  self:Changed("budget")
  return true
end
function P:SetPlanLoyalty(fam, loyalty)
  local p = self:Plan(fam, true)
  if not p then return false end
  p.loyalty = max(1, min(P.MAX_LOYALTY, floor(tonumber(loyalty) or P.MAX_LOYALTY)))
  self:Changed("budget")
  return true
end

-- the highest rank of an ability a pet of this level can use (0: none yet)
function P.MaxRankAt(a, level)
  local best = 0
  for _, r in ipairs(a.ranks) do if (r.lvl or 0) <= level then best = r.r end end
  return best
end

-- What the plan costs at its pet level: rows = { { a, rank (the wanted rank the level allows; 0 = out), tp (nil: cost not known),
-- capped (the plan wants a higher rank than the level allows) } }, spent, budget, left, unknown (ranks with no known cost)
function P:Budget(fam)
  local level, loyalty = self:PlanLevel(fam), self:PlanLoyalty(fam)
  local out = { rows = {}, level = level, loyalty = loyalty, budget = P.Points(level, loyalty), spent = 0, unknown = 0 }
  for _, a in ipairs(self:Abilities(fam)) do
    local want = self:Want(fam, a.key)
    local rank = min(want, P.MaxRankAt(a, level))
    if rank < a.first then rank = 0 end
    local r = rank > 0 and self:RankDef(a.key, rank) or nil
    local tp = r and r.tp or nil
    if r and tp == nil then out.unknown = out.unknown + 1 end
    out.spent = out.spent + (tp or 0)
    out.rows[#out.rows + 1] = { a = a, rank = rank, tp = tp, capped = want > rank }
  end
  out.left = out.budget - out.spent
  return out
end

-- one step up or down for an ability in the builder (down from the family's first rank is "out")
function P:StepWant(fam, key, delta)
  local a = self:Ability(fam, key)
  if not a then return false end
  local cur = min(self:Want(fam, key), P.MaxRankAt(a, self:PlanLevel(fam)))
  if cur < a.first then cur = 0 end
  local nxt
  if delta > 0 then
    nxt = cur == 0 and a.first or cur + 1
    if nxt > P.MaxRankAt(a, self:PlanLevel(fam)) then return false end
  else
    if cur == 0 then return false end
    nxt = cur - 1
    if nxt < a.first then nxt = 0 end
  end
  return self:SetWant(fam, key, nxt)
end

-------------------------------------------------------------------------------
-- WoW Forever pet talents: the hook
-------------------------------------------------------------------------------
-- The WoW Forever API list has C_PetInfo.GetPetTalentTree; nothing in the repo says what it returns or whether hunter pets have a
-- talent tree there, so the builder plans classic training points. When the game does hand a tree over, the Training points tab
-- says so, and a later build draws it by setting P.TalentBuilder = function(parent, tree, x, y, w) ... return y below end.
function P:PetTalentTree()
  local ok, tree = C.Call("PetTalentTree", "C_PetInfo.GetPetTalentTree")
  if ok and type(tree) == "table" and next(tree) ~= nil then return tree end
  return nil
end
P.TalentBuilder = nil
