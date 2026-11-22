-- Panoply Suite, the hunter's pet (Nov 2026): the tame recorder's own saved log. Hunters only (it is fed by Recorder.lua, which starts
-- for hunters only; any other class never calls it and nothing is created).
-- What it writes down, from what the game itself reports at the time: when the hunter tames a beast, and when the pet that is out shows an
-- ability rank it did not have a moment ago. Per entry: the beast's name, its creature id when the unit GUID gives one, its level, its
-- family, the zone and map the hunter stood in, the ability ranks in the pet's spellbook (and their spell ids), the game's client and
-- version, and the date.
-- Saved in a variable of its own, PanoplySuitePetLogDB (per account, new in this version): { version = 1, on = nil | true | false,
-- tames = { entry, ... } oldest first }. Capped at L.CAP entries: the oldest go first. Nothing existing is renamed, moved or deleted: the
-- older record of tames (PanoplySuiteDB.hunterPetBeasts, PanoplySuiteCharDB.hunterPet.log) is still written by Recorder.lua exactly as
-- before and still drives the planner; this log is a second, fuller copy with the game's own facts, for the add-on's research.
-- The switch (Pet tab, To tame) is on until the player turns it off: the older recorder has always recorded tames without a switch, and this
-- one only reads and writes down, on this computer, never sends anything.
-- It only watches. It never tames, targets, casts, calls, stables or trains anything, and touches no protected frame.
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = Panoply.HunterPet

local L = { CAP = 200, SHOW = 5, SPELL_IDS_MAX = 40 }
P.PetLog = L

-- the saved log. Reading never makes it (a writer asks for it); a log that exists but is not shaped as expected is made whole in
-- place (its own keys only).
function L:DB(create)
  local db = _G.PanoplySuitePetLogDB
  if type(db) ~= "table" then
    if not create then return nil end
    db = {}
    _G.PanoplySuitePetLogDB = db
  end
  db.version = tonumber(db.version) or 1
  if type(db.tames) ~= "table" then db.tames = {} end
  return db
end

function L:IsOn()
  local db = _G.PanoplySuitePetLogDB
  return not (type(db) == "table" and db.on == false)
end

function L:SetOn(on)
  local db = self:DB(true)
  on = on and true or false
  if db.on == on then return false end
  db.on = on
  P:Changed("petlog")
  return true
end

-- oldest entries go first once the log is over its cap
function L:Trim()
  local db = _G.PanoplySuitePetLogDB
  if type(db) ~= "table" or type(db.tames) ~= "table" then return 0 end
  local gone = 0
  while #db.tames > L.CAP do table.remove(db.tames, 1) gone = gone + 1 end
  return gone
end

-- the facts every entry carries: when, which game, where
local function stamp(e, m, x, y)
  e.t = (_G.time and _G.time()) or 0
  local date = _G.date and _G.date("%Y-%m-%d %H:%M")
  e.date = type(date) == "string" and date or nil
  local version, build, _, toc = C.BuildInfo()
  e.game = { client = P.Client(), version = version, build = build, toc = toc }
  local zone, sub = C.ZoneText()
  e.zone = (type(zone) == "string" and zone ~= "") and zone or nil
  e.sub = (type(sub) == "string" and sub ~= "") and sub or nil
  if not m then m, x, y = C.GetPlayerPos() end
  if m then
    e.map = m
    if type(x) == "number" and type(y) == "number" then e.x, e.y = math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000 end
  end
  return e
end

local function copyRanks(ranks)
  local out = {}
  for k, v in pairs(ranks or {}) do if type(k) == "string" and type(v) == "number" then out[k] = v end end
  return out
end

local function idsOf(spells)
  local out = {}
  for _, s in ipairs(spells or {}) do
    if type(s.id) == "number" and #out < L.SPELL_IDS_MAX then out[#out + 1] = s.id end
  end
  return out
end

-- the creature id a unit GUID names (nil when there is none, or it cannot be read)
local function creatureId(guid)
  local QD = Panoply.QuestData
  local id = QD and QD.NpcIdFromGUID and QD.NpcIdFromGUID(guid)
  return type(id) == "number" and id or nil
end

-- A tame, seen by Recorder:Scan: pet = the new pet, target = what the hunter had targeted a moment before (name, level, family, guid,
-- where), ranks = { ability = rank } in its spellbook, fresh = the recorder's note of this tame. The spellbook may fill a moment after
-- the pet appears, so while the tame is fresh the same entry is brought up to date instead of a second one being written.
function L:OnTame(pet, target, ranks, spells, fresh)
  if not (self:IsOn() and type(pet) == "table" and type(fresh) == "table") then return nil end
  local e = fresh.logEntry
  if not e then
    local db = self:DB(true)
    e = { kind = "tame", name = pet.name, level = (target and target.level) or pet.level, petLevel = pet.level,
      family = pet.familyName or (target and target.family), id = creatureId(target and target.guid) }
    stamp(e, target and target.m, target and target.x, target and target.y)
    db.tames[#db.tames + 1] = e
    self:Trim()
    fresh.logEntry = e
  end
  e.ranks = copyRanks(ranks)
  e.spellIds = idsOf(spells)
  P:Changed("petlog")
  return e
end

-- The pet that is out shows ranks it did not have at the last look (same pet: a new pet is a tame, handled above). was, now = { ability = rank }.
function L:OnRanks(pet, was, now, spells)
  if not (self:IsOn() and type(pet) == "table" and type(now) == "table") then return nil end
  local gained, any = {}, false
  for key, rank in pairs(now) do
    if type(rank) == "number" and rank > ((type(was) == "table" and was[key]) or 0) then gained[key] = rank any = true end
  end
  if not any then return nil end
  local db = self:DB(true)
  local e = { kind = "rank", name = pet.name, level = pet.level, family = pet.familyName, gained = gained, ranks = copyRanks(now), spellIds = idsOf(spells) }
  stamp(e)
  db.tames[#db.tames + 1] = e
  self:Trim()
  P:Changed("petlog")
  return e
end

-- the recorded tames, newest first (kind = "tame"); n at most
function L:Recent(n)
  local db = _G.PanoplySuitePetLogDB
  local out = {}
  if type(db) ~= "table" or type(db.tames) ~= "table" then return out end
  for i = #db.tames, 1, -1 do
    local e = db.tames[i]
    if type(e) == "table" and e.kind == "tame" then
      out[#out + 1] = e
      if n and #out >= n then break end
    end
  end
  return out
end

-- how many entries of each kind are in the log: tames, ranks
function L:Counts()
  local db = _G.PanoplySuitePetLogDB
  local tames, ranks = 0, 0
  if type(db) == "table" and type(db.tames) == "table" then
    for _, e in ipairs(db.tames) do
      if type(e) == "table" then
        if e.kind == "tame" then tames = tames + 1 elseif e.kind == "rank" then ranks = ranks + 1 end
      end
    end
  end
  return tames, ranks
end

-- "Wood Lurker, level 17 Spider, Duskwood, 14 Nov 2026: Bite 3."
function L.Words(e)
  local bits = { tostring(e.name or "A beast") }
  local lf = {}
  if e.level then lf[#lf + 1] = "level " .. e.level end
  if e.family then lf[#lf + 1] = e.family end
  if #lf > 0 then bits[1] = bits[1] .. ", " .. table.concat(lf, " ") end
  if e.zone then bits[#bits + 1] = e.zone end
  if e.date then bits[#bits + 1] = P.DateWords(tostring(e.date):match("^(%d%d%d%d%-%d%d%-%d%d)") or e.date) end
  local keys = {}
  for k, v in pairs(e.ranks or {}) do if type(v) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  local ranks = {}
  for _, k in ipairs(keys) do ranks[#ranks + 1] = ("%s %d"):format(k, e.ranks[k]) end
  return table.concat(bits, ", ") .. (#ranks > 0 and (": " .. table.concat(ranks, ", ") .. ".") or ": no ability a hunter can learn.")
end
