-- Panoply Suite, the hunter's pet (0.8.4; the Pet tab of the Hunter Class Guide): the recorder. Hunters only; other classes register nothing.
-- It only reads and writes down. It never tames, abandons, calls, feeds, trains or targets anything.
--   * The pet that is out: its family, level and the ranks in its spellbook (so the planner can say "on your pet"), kept per family.
--   * A tame: the beast the hunter had targeted becomes the pet. The beast, its level, where the hunter stood and the ranks it knew
--     are kept for the account; a beast the list said knows a rank and did not is no longer offered for that rank.
--   * Learning: when the game says "You have learned a new ..." for a pet ability, that rank is ticked. On Classic Era the Beast
--     Training window lists every rank the hunter can teach, and opening it ticks them all.
-- Every game call is guarded (C.Call): a function a client does not have, or one that answers in a shape this file does not know,
-- reads as "nothing", never as an error. The names differ by client (Era: HasPetSpells, GetPetTrainingPoints, the Craft window;
-- WoW Forever: C_SpellBook, C_PetInfo); which one answers is found by asking, not by the client's version.
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = Panoply.HunterPet
local D = Panoply.HunterPetData

local R = { TAME_WINDOW = 90, FRESH_FOR = 30, SCAN_DELAY = 0.3 }
P.Recorder = R

local function readable(v) return C.Readable and C.Readable(v) or v end

-- the results of a guarded game call (nothing when the function is missing or errors)
local function ask(path, ...)
  local res = { C.Call(path, path, ...) }
  if not res[1] then return nil end
  return unpack(res, 2, 8)
end

local function now() return C.GetTime() end

-------------------------------------------------------------------------------
-- Reading the game
-------------------------------------------------------------------------------
-- the pet that is out: { name, family (ours, nil when the game's name is not one we know), familyName, level, guid }
function R.ReadPet()
  if not ask("UnitExists", "pet") then return nil end
  local name = readable(ask("UnitName", "pet"))
  if type(name) ~= "string" or name == "" then return nil end
  local famName = readable(ask("UnitCreatureFamily", "pet"))
  local level = readable(ask("UnitLevel", "pet"))
  local guid = readable(ask("UnitGUID", "pet"))
  return { name = name, familyName = type(famName) == "string" and famName or nil, family = P:FamilyKey(famName),
    level = type(level) == "number" and level or nil, guid = type(guid) == "string" and guid or nil }
end

-- the pet's spellbook: { { name, rankText, id } }, and whether a spellbook was read at all
function R.ReadPetSpells()
  local out = {}
  -- WoW Forever: C_SpellBook with the pet spell bank
  local n = ask("C_SpellBook.HasPetSpells")
  if type(n) == "number" and n > 0 then
    local bank = C.G("Enum.SpellBookSpellBank.Pet") or 1
    for i = 1, n do
      local name, sub = ask("C_SpellBook.GetSpellBookItemName", i, bank)
      local info = ask("C_SpellBook.GetSpellBookItemInfo", i, bank)
      local id
      if type(info) == "table" then
        id = info.spellID or info.actionID
        name = name or info.name
        sub = sub or info.subName
      end
      name = readable(name)
      if type(name) == "string" then out[#out + 1] = { name = name, rankText = readable(sub), id = readable(id) } end
    end
    return out, true
  end
  -- Classic Era: the old spellbook calls with "pet"
  n = ask("HasPetSpells")
  if type(n) == "number" and n > 0 then
    for i = 1, n do
      local name, sub = ask("GetSpellBookItemName", i, "pet")
      local _, id = ask("GetSpellBookItemInfo", i, "pet")
      name = readable(name)
      if type(name) == "string" then out[#out + 1] = { name = name, rankText = readable(sub), id = readable(id) } end
    end
    return out, true
  end
  return out, false
end

-- the pet's training points as the game counts them: total, spent (nil when the game does not say, or not as two numbers)
function R.ReadTrainingPoints()
  for _, path in ipairs({ "GetPetTrainingPoints", "C_PetInfo.GetPetTrainingPoints" }) do
    local total, spent = ask(path)
    total, spent = readable(total), readable(spent)
    if type(total) == "number" and type(spent) == "number" then return total, spent end
  end
  return nil
end

-- the highest rank of each of our abilities in a spell list: { ability = rank }
function R.RanksIn(spells)
  local ranks = {}
  for _, s in ipairs(spells) do
    local key, rank = P:ResolveSpell(s.id, s.name, s.rankText)
    if key and rank > (ranks[key] or 0) then ranks[key] = rank end
  end
  return ranks
end

-------------------------------------------------------------------------------
-- The pet that is out, and a tame
-------------------------------------------------------------------------------
local function sameRanks(a, b)
  for k, v in pairs(a or {}) do if (b or {})[k] ~= v then return false end end
  for k, v in pairs(b or {}) do if (a or {})[k] ~= v then return false end end
  return true
end

-- remember the beast the hunter is looking at (a tame is "the thing I had targeted is now my pet"). A player, or anything a player
-- controls (the hunter's own pet, someone else's), is not a beast to tame.
function R:OnTarget()
  if not ask("UnitExists", "target") then return end
  if ask("UnitIsPlayer", "target") or ask("UnitPlayerControlled", "target") or ask("UnitIsUnit", "target", "pet") then return end
  local guid = readable(ask("UnitGUID", "target"))
  if type(guid) == "string" and guid:find("^Pet%-") then return end
  local name = readable(ask("UnitName", "target"))
  if type(name) ~= "string" or name == "" then return end
  local level = readable(ask("UnitLevel", "target"))
  local m, x, y = C.GetPlayerPos()
  local family = readable(ask("UnitCreatureFamily", "target"))
  self.lastTarget = { name = name, level = type(level) == "number" and level > 0 and level or nil, m = m, x = x, y = y, t = now(),
    guid = guid, family = type(family) == "string" and family or nil }
end

-- what a tame of a beast showed: keep the beast, the ranks it knew, and strike it from the ranks the list said it knows and it did not
function R:RecordBeast(name, target, ranks, level)
  local beasts = P:Beasts(true)
  local b = beasts[name]
  if type(b) ~= "table" then b = {} beasts[name] = b end
  if target and target.m and target.x and target.y then
    b.m, b.x, b.y = target.m, math.floor(target.x * 10000 + 0.5) / 10000, math.floor(target.y * 10000 + 0.5) / 10000
  end
  b.lvl = (target and target.level) or level or b.lvl
  b.knows = {}
  for key, rank in pairs(ranks) do
    local def = P:Data().abilities[key]
    if def and def.kind == "wild" then b.knows[key] = rank end
  end
  b.miss = {}
  -- this client's teacher records, filed under this client's own ability names
  for key, byRank in pairs(P:TeacherTable()) do
    for rank, list in pairs(byRank) do
      for _, t in ipairs(list) do
        if t.n == name and (ranks[key] or 0) ~= rank then b.miss[P.NeedKey(key, rank)] = true end
      end
    end
  end
  return b
end

-- read the pet and its spellbook; note a new pet, a tame, and what changed
function R:Scan()
  self.queued = nil
  local pet = R.ReadPet()
  local was = P.pet
  if not pet then
    if was then P.pet = nil self.fresh = nil P:Changed("pet") end
    return nil
  end
  local spells, read = R.ReadPetSpells()
  local ranks = R.RanksIn(spells)
  local total, spent = R.ReadTrainingPoints()
  local isNew = not was or (pet.guid and was.guid and pet.guid ~= was.guid) or was.name ~= pet.name or was.family ~= pet.family
  -- the same pet shows a rank it did not have at the last look: written to the pet log (PetLog.lua). Not while a tame is fresh: the
  -- pet's spellbook may still be filling, and the tame's own entry is brought up to date instead.
  local tameFresh = self.fresh and self.fresh.name == pet.name and now() - self.fresh.t <= R.FRESH_FOR
  -- Only when the last look really read the spellbook too: a look that could not read it (still empty just after UNIT_PET or login)
  -- has no ranks to compare with, and every ability would show as newly gained.
  if read and was and was.read and not isNew and not tameFresh and P.PetLog then P.PetLog:OnRanks(pet, was.ranks, ranks, spells) end
  pet.ranks, pet.points, pet.spent, pet.read = ranks, total, spent, read and true or false
  P.pet = pet
  -- a tame: a new pet with the name (and, when both are known, the level) of the beast that was targeted a moment ago
  local lt = self.lastTarget
  if isNew and lt and lt.name == pet.name and now() - lt.t <= R.TAME_WINDOW and (not lt.level or not pet.level or lt.level == pet.level) then
    self.fresh = { name = pet.name, target = lt, t = now() }
    self.lastTarget = nil
    local s, ok = P:Store(true)
    if ok then
      table.insert(s.log, 1, { t = (_G.time and _G.time()) or 0, n = pet.name, lvl = lt.level or pet.level, m = lt.m })
      while #s.log > P.LOG_CAP do table.remove(s.log) end
    end
  end
  local fresh = self.fresh
  if fresh and (fresh.name ~= pet.name or now() - fresh.t > R.FRESH_FOR) then fresh = nil self.fresh = nil end
  if fresh and read then
    R:RecordBeast(pet.name, fresh.target, ranks, pet.level)
    if P.PetLog then P.PetLog:OnTame(pet, fresh.target, ranks, spells, fresh) end
    if not fresh.said then
      fresh.said = true
      local knows = {}
      for key, rank in pairs(P:Beasts()[pet.name].knows) do knows[#knows + 1] = { key = key, rank = rank } end
      table.sort(knows, function(a, b) return a.key < b.key end)
      if #knows > 0 then
        Panoply:Print(("%s knows %s. Fight with it until the game says you learned each one; then you can teach them to another pet."):format(pet.name, P.RanksText(knows)))
      else
        Panoply:Print(("%s knows no ability a hunter can learn from it."):format(pet.name))
      end
    end
  end
  -- the last pet of each family is kept, so the planner can say what is on it while another pet is out
  local changed = isNew or not sameRanks(was and was.ranks, ranks) or (was and (was.level ~= pet.level or was.points ~= total or was.spent ~= spent))
  if pet.family and read then
    local s, ok = P:Store(true)
    if ok then
      local snap = s.pets[pet.family]
      if type(snap) ~= "table" or snap.name ~= pet.name or snap.level ~= pet.level or not sameRanks(snap.ranks, ranks) then
        s.pets[pet.family] = { name = pet.name, level = pet.level, ranks = ranks }
        changed = true
      end
    end
  end
  if changed or fresh then P:Changed("pet") end
  return pet
end

-- several events arrive together when a pet appears: one read a moment later
function R:Queue()
  if self.queued then return end
  self.queued = true
  C.After(R.SCAN_DELAY, function() if R.queued then R:Scan() end end)
end

-------------------------------------------------------------------------------
-- Learning a rank
-------------------------------------------------------------------------------
-- "You have learned a new spell: %s." as a pattern that captures the name
local function patternOf(fmt)
  if type(fmt) ~= "string" or not fmt:find("%s", 1, true) then return nil end
  local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end
R.LEARN_GLOBALS = { "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_PASSIVE_S" }
R.LEARN_ENGLISH = { "You have learned a new spell: %s.", "You have learned a new ability: %s." }

-- the pet ability and rank a system message says the hunter learned (rank nil when the message does not carry one). The game may
-- name the spell in plain words ("Bite (Rank 3)") or as a spell link ("|cff71d5ff|Hspell:17263|h[Bite]|h|r"): a link's spell id
-- says the rank by itself.
function R.ParseLearn(msg)
  msg = readable(msg)
  if type(msg) ~= "string" then return nil end
  local linkId = tonumber(msg:match("|Hspell:(%d+)[^|]*|h"))
  -- the message in plain words: colour codes and link wrappers taken off
  msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[(.-)%]|h", "%1")
  local formats = {}
  for _, g in ipairs(R.LEARN_GLOBALS) do if type(_G[g]) == "string" then formats[#formats + 1] = _G[g] end end
  for _, f in ipairs(R.LEARN_ENGLISH) do formats[#formats + 1] = f end
  for _, f in ipairs(formats) do
    local pat = patternOf(f)
    local what = pat and msg:match(pat)
    if what then
      if linkId then
        local key, rank = P:ResolveLearned(linkId)
        if key then return key, rank end
      end
      local name, rank = what:match("^(.-)%s*%(%D*(%d+)%)$")
      name = name or what
      if P:Data().abilities[name] then return name, tonumber(rank) end
    end
  end
  return nil
end

function R:OnSystemMessage(msg)
  local key, rank = R.ParseLearn(msg)
  if not key then return end
  -- a message without a rank: the rank is the one the pet that is out knows (the beast just tamed), or the only rank there is
  if not rank then
    local def = P:Data().abilities[key]
    rank = (P.pet and P.pet.ranks and P.pet.ranks[key]) or (#def.ranks == 1 and def.ranks[1].r) or nil
  end
  if not (rank and P:RankDef(key, rank)) then Panoply:Debug("hunter pet: learned", key, "but the rank is not known") return end
  if P:SetLearned(key, rank, true) then
    Panoply:Print(("Learned %s rank %d: you can now teach it to a pet that can use it."):format(key, rank))
  end
  return key, rank
end

-- Classic Era: the Beast Training window (the Craft window) lists every rank the hunter can teach
function R:OnCraft()
  local title = readable(ask("GetCraftName"))
  local want = (C.SpellName and C.SpellName(5149)) or "Beast Training"
  if type(title) ~= "string" or (title ~= want and title ~= "Beast Training") then return 0 end
  local n = ask("GetNumCrafts")
  if type(n) ~= "number" then return 0 end
  local ticked = 0
  for i = 1, n do
    local name, sub, kind = ask("GetCraftInfo", i)
    if kind ~= "header" then
      local key, rank = P:ResolveSpell(nil, readable(name), readable(sub))
      if key and P:SetLearned(key, rank, true, true) then ticked = ticked + 1 end
    end
  end
  if ticked > 0 then P:Changed("learned") end
  return ticked
end

-------------------------------------------------------------------------------
-- Start (hunters only)
-------------------------------------------------------------------------------
function R:Start()
  if self.started or not P.IsHunter() then return false end
  self.started = true
  Panoply:On("UNIT_PET", function(_, unit) if unit == nil or unit == "player" then R:Queue() end end)
  for _, ev in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "UNIT_PET_TRAINING_POINTS", "UNIT_PET_EXPERIENCE", "SPELLS_CHANGED" }) do
    Panoply:On(ev, function() R:Queue() end)
  end
  Panoply:On("PLAYER_TARGET_CHANGED", function() R:OnTarget() end)
  Panoply:On("CHAT_MSG_SYSTEM", function(_, msg) R:OnSystemMessage(msg) end)
  Panoply:On("CRAFT_SHOW", function() R:OnCraft() end)
  Panoply:On("CRAFT_UPDATE", function() R:OnCraft() end)
  R:Queue()
  return true
end

Panoply:On("PLAYER_LOGIN", function() R:Start() end)
