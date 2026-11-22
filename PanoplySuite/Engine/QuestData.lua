-- Panoply Suite QuestData: adapter over Panoply Suite's own quest database, read at RUNTIME.
-- The one source is PanoplySuite_QuestData: Panoply Suite's own data add-on (global
-- PanoplySuiteQuestData), generated from the VMaNGOS world database by tools/build_questdata.py and
-- shipped under the GPL-3.0 with the rest of the suite. 0.6.0: no other add-on's quest database is read any more.
-- This file itself contains no server data; it is Panoply Suite's own code.
local ADDON, Panoply = ...
local QD = { cache = {}, npcCache = {}, objCache = {}, itemSpotCache = {} }
Panoply.QuestData = QD
local U = Panoply.Util

QD.source = nil         -- "PanoplySuite_QuestData" | nil
QD.status = "not initialized"

-- Own small fallback for Alliance-relevant classic AreaIDs -> UiMapIDs (Forever keeps Classic UiMapIDs).
QD.fallbackAreaToMap = {
  [1] = 1426, [12] = 1429, [38] = 1432, [40] = 1436, [44] = 1433, [10] = 1431, [11] = 1437,
  [141] = 1438, [148] = 1439, [1519] = 1453, [1537] = 1455, [1657] = 1457, [331] = 1440,
  [267] = 1424, [45] = 1417, [33] = 1434, [3] = 1418, [51] = 1427, [46] = 1428, [8] = 1435,
  [47] = 1425, [4] = 1419, [400] = 1441, [405] = 1443, [406] = 1442, [357] = 1444, [15] = 1445,
  [440] = 1446, [490] = 1449, [361] = 1448, [16] = 1447, [618] = 1452, [1377] = 1451,
  [28] = 1422, [139] = 1423, [41] = 1430, [36] = 1416,
}

-- Own fallback list of Classic instance AreaIDs (dungeons, raids, battlegrounds), used only when
-- the data add-on gives no instance table. Game facts, not copied data.
QD.fallbackInstanceAreas = {
  1581, 717, 718, 209, 719, 721, 491, 722, 796, 1337, 1176, 2100, 1477, 1584, 1583, 2557, 2017, 2057,
  2437, 2717, 2159, 2677, 1977, 3429, 3428, 3456, 2597, 3277, 3358,
}

-- Continent of a UiMapID (for travel penalties). EK = 1415, Kalimdor = 1414.
QD.continentOf = {}
for _, m in ipairs({ 1426, 1429, 1432, 1436, 1433, 1431, 1437, 1453, 1455, 1424, 1417, 1434, 1418, 1427, 1428, 1435, 1425, 1419, 1422, 1423, 1430, 1416, 1420, 1421 }) do QD.continentOf[m] = 1415 end
for _, m in ipairs({ 1438, 1439, 1457, 1440, 1441, 1443, 1442, 1444, 1445, 1446, 1449, 1448, 1447, 1452, 1451, 1411, 1412, 1413, 1450, 1454, 1456 }) do QD.continentOf[m] = 1414 end

-------------------------------------------------------------------------------
-- Provider binding
-------------------------------------------------------------------------------
local getQ, getN, getO, getI   -- function(id, key)

function QD:Init(force)
  if self.source and not force then return true end
  self.cache, self.npcCache, self.objCache, self.itemSpotCache, self.dropperCache = {}, {}, {}, {}, {}
  self.own, self.flavorWarning = nil, nil
  self.trainerCache, self.groupCache = nil, nil
  if self:InitOwn() then return true end
  self.source = nil
  self.status = "Panoply Suite Quest Data not found. Turn on the Panoply Suite Quest Data add-on to get the leveling route. Manual steps still work."
  return false
end

-- PanoplySuite_QuestData. Records come back already in the field shapes used below.
QD.OWN_API = 1
function QD:InitOwn()
  local DB = rawget(_G, "PanoplySuiteQuestData")
  if type(DB) ~= "table" or type(DB.Quest) ~= "function" or (tonumber(DB.apiVersion) or 0) < QD.OWN_API then return false end
  local function field(get) return function(id, k) local r = get(id) if r then return r[k] end return nil end end
  getQ, getN, getO, getI = field(DB.Quest), field(DB.Npc), field(DB.Object), field(DB.Item)
  self.own = DB
  self.source = "PanoplySuite_QuestData"
  self.dbFlavor = "Era"
  self.forever = Panoply.Compat.IsForever()
  self.fingerprint = "HQD/" .. tostring(DB.version or "?") .. (self.forever and "+forever" or "")
  self.status = ("PanoplySuite_QuestData %s (%s)%s"):format(tostring(DB.version or "?"), tostring(DB.source or "VMaNGOS"),
    self.forever and ", WoW Forever overlay; spots in re-drawn zones unverified" or "")
  self:LoadSupport()
  return true
end

function QD:Available() return self.source ~= nil end

function QD:LoadSupport()
  self.areaToMap = {}
  for k, v in pairs(self.fallbackAreaToMap) do self.areaToMap[k] = v end
  self.xp = nil
  self.hidden = {}
  self.instanceAreas, self.instanceSource = {}, "built-in list"
  self.groupCache = {}
  if self.own then self:LoadOwnSupport() end
  if not next(self.instanceAreas) then
    for _, a in ipairs(self.fallbackInstanceAreas) do self.instanceAreas[a] = true end
  end
end

-- Zone tables from PanoplySuite_QuestData: area -> uiMap, instance areas, hidden quests, continents.
function QD:LoadOwnSupport()
  local DB = self.own
  for k, v in pairs(DB.areaToMap or {}) do self.areaToMap[k] = v end
  for _, a in ipairs(DB.instanceAreas or {}) do self.instanceAreas[a] = true end
  self.instanceSource = "PanoplySuite_QuestData"
  for _, q in ipairs(DB.hidden or {}) do self.hidden[q] = true end
  local function continent(rects, m)
    for _ = 1, 6 do
      local r = rects[m] or DB.rects[m]
      if not r then return nil end
      local parent = r[7]
      if parent == 1414 or parent == 1415 then return parent end
      m = parent
    end
  end
  local rects = self.forever and DB.foreverRects or {}
  for _, set in ipairs({ DB.rects or {}, rects }) do
    for m in pairs(set) do
      local c = continent(rects, m)
      if c and not QD.continentOf[m] then QD.continentOf[m] = c end
    end
  end
  self.overlay = self.forever and DB.overlay and DB.overlay.forever or nil
  self:ListenLearning()
end

function QD:IsInstanceArea(area) return self.instanceAreas and self.instanceAreas[area] == true end

function QD:UiMapForArea(areaID)
  local m = self.areaToMap and self.areaToMap[areaID]
  if m and m ~= 0 then return m end
  return nil
end

-------------------------------------------------------------------------------
-- Masks
-------------------------------------------------------------------------------
function QD:RaceMask(raceID)
  local bits = self.own and self.own.raceBits
  if bits and raceID and bits[raceID] then return 2 ^ bits[raceID] end
  if raceID and raceID >= 1 and raceID <= 11 then return 2 ^ (raceID - 1) end
  -- 0.7.4.1: a race this data does not know (or none) gets mask 0: no race bit matches, so it takes only the quests open to every
  -- race. It used to get nil, which the planner read as "no race filter" and handed it every race's starting quests.
  return 0
end

-- 0.7.4.1 (our e): each race's own starting valley. The data gives these valleys' quests to every race (race mask 0: the 1.12 server gated them
-- by area), so the planner has to know whose valley it is or it sends a Human to Coldridge Valley for its "all race" quests. Area ids are the
-- quests' zone (the starting sub-zone, public game facts), values are race ids: 1 Human, 2 Orc, 3 Dwarf, 4 Night Elf, 5 Undead, 6 Tauren, 7 Gnome,
-- 8 Troll. A race that is not listed (the Forever Skyborne, a race this data does not know) has no valley in the classic world: it is never
-- sent into any of them. Checked against the data by the "noguide: start areas" test (each valley's quests sit in its own area).
QD.START_AREAS = {
  [9] = { 1 },          -- Northshire Valley
  [132] = { 3, 7 },     -- Coldridge Valley
  [188] = { 4 },        -- Shadowglen
  [154] = { 5 },        -- Deathknell
  [220] = { 6 },        -- Red Cloud Mesa (Camp Narache)
  [363] = { 2, 8 },     -- Valley of Trials
}
-- true when `zone` (a quest's zone) is a racial starting valley that this race does not start in
function QD:ForeignStart(zone, raceID)
  local r = QD.START_AREAS[zone]
  if not r then return false end
  for _, id in ipairs(r) do if id == raceID then return false end end
  return true
end

function QD:ClassMask(classID, classFile)
  if classID and classID >= 1 then return 2 ^ (classID - 1) end
  return nil
end

-------------------------------------------------------------------------------
-- Normalized records
-------------------------------------------------------------------------------
local function num(v) if type(v) == "number" then return v end return 0 end
local function tbl(v) if type(v) == "table" then return v end return nil end

function QD:AllQuestIds()
  if not self.source then return {} end
  if self.own then return self.own.QuestIds() end
  return {}
end
-- Every quest id, unsorted, without building the sorted list first (the quest icon index walks
-- this in sub-millisecond slices). Returns an iterator: for id in QD:EachQuestId() do ... end
function QD:EachQuestId()
  local raw = self.source and self.own and type(self.own.Q) == "table" and self.own.Q
  if raw then
    local k
    return function()
      repeat k = next(raw, k) until k == nil or type(k) == "number"
      return k
    end
  end
  local ids, i = self:AllQuestIds(), 0
  return function() i = i + 1 return ids[i] end
end

-- Raw record fields can come in odd shapes (sparse lists, a number where a
-- list is expected, missing text). Everything below turns raw fields into one fixed shape so the
-- rest of Panoply Suite never has to guess:
--   id lists      -> { number, ... }
--   objectives    -> { { id, count|nil, text|nil }, ... }          (creatures/objects/items/spells/rep)
--   killCredit    -> { { {npcId, ...}, rootNpcId|nil, text|nil }, ... }
-- Lists are read with pairs() over numeric keys in order, so holes (nil entries) are skipped.
local function numKeys(t)
  local keys = {}
  for k in pairs(t) do if type(k) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys
end
local function idList(v)
  if type(v) == "number" then return { v } end
  if type(v) ~= "table" then return {} end
  local out = {}
  for _, k in ipairs(numKeys(v)) do
    local x = v[k]
    if type(x) == "number" then out[#out + 1] = x
    elseif type(x) == "table" then for _, y in ipairs(idList(x)) do out[#out + 1] = y end end
  end
  return out
end
QD.IdList = idList
local function str(v) if type(v) == "string" and v ~= "" then return v end return nil end

local function objEntry(e)
  if type(e) == "number" then return { e } end
  if type(e) ~= "table" or type(e[1]) ~= "number" then return nil end
  local count, text = nil, nil
  for _, k in ipairs(numKeys(e)) do
    if k > 1 then
      local x = e[k]
      if type(x) == "number" and not count then count = x
      elseif type(x) == "string" and not text then text = x end
    end
  end
  return { e[1], count, text }
end
local function objList(v)
  if type(v) ~= "table" then return nil end
  local out = {}
  -- a single entry given directly ({ id, "text" }) instead of a list of entries
  if type(v[1]) == "number" then local e = objEntry(v) return e and { e } or nil end
  for _, k in ipairs(numKeys(v)) do local e = objEntry(v[k]) if e then out[#out + 1] = e end end
  return #out > 0 and out or nil
end

-- One kill-credit objective. Seen shapes: { {npcIds}, rootNpcId, "text" }, { {npcIds}, rootNpcId, nil, n },
-- { npcId, rootNpcId } and { {npcIds} }.
local function killCreditEntry(e)
  if type(e) == "number" then return { { e }, e, nil } end
  if type(e) ~= "table" then return nil end
  local npcs = idList(e[1])
  local root = type(e[2]) == "number" and e[2] or nil
  if type(e[2]) == "table" then -- a list where a root id was expected
    for _, x in ipairs(idList(e[2])) do npcs[#npcs + 1] = x end
  end
  local text = str(e[3])
  if not root and npcs[1] then root = npcs[1] end
  if #npcs == 0 and root then npcs = { root } end
  if #npcs == 0 then return nil end
  return { npcs, root, text }
end
local function killCreditList(v)
  if type(v) ~= "table" then return nil end
  local out = {}
  -- a single objective given directly: { {ids}, root, ... } or { id, root }
  if (type(v[1]) == "table" and type(v[1][1]) == "number") or type(v[1]) == "number" then
    local e = killCreditEntry(v)
    return e and { e } or nil
  end
  for _, k in ipairs(numKeys(v)) do local e = killCreditEntry(v[k]) if e then out[#out + 1] = e end end
  return #out > 0 and out or nil
end
local function strList(v)
  if type(v) == "string" then return { v } end
  if type(v) ~= "table" then return nil end
  local out = {}
  for _, k in ipairs(numKeys(v)) do if type(v[k]) == "string" then out[#out + 1] = v[k] end end
  return #out > 0 and out or nil
end
local function optIds(v) local l = idList(v) return #l > 0 and l or nil end
local function trigger(v)
  if type(v) ~= "table" then return nil end
  local spawns = type(v[2]) == "table" and v[2] or nil
  if not spawns and not str(v[1]) then return nil end
  return { str(v[1]) or "Explore the marked area", spawns }
end
local function pair(v) -- { id, value } (required skill / reputation)
  if type(v) ~= "table" then return nil end
  if type(v[1]) == "number" then return { v[1], type(v[2]) == "number" and v[2] or 0 } end
  if type(v[1]) == "table" then return pair(v[1]) end
  return nil
end

QD.Normalize = {
  IdList = idList, Objectives = objList, KillCredit = killCreditList, Strings = strList, Trigger = trigger,
}

local function buildQuest(self, id, name)
  local sb = tbl(getQ(id, "startedBy")) or {}
  local fb = tbl(getQ(id, "finishedBy")) or {}
  local ob = tbl(getQ(id, "objectives")) or {}
  local q = {
    id = id, name = name,
    reqLevel = num(getQ(id, "requiredLevel")), level = num(getQ(id, "questLevel")),
    races = num(getQ(id, "requiredRaces")), classes = num(getQ(id, "requiredClasses")),
    starts = { npc = idList(sb[1]), obj = idList(sb[2]), item = idList(sb[3]) },
    ends = { npc = idList(fb[1]), obj = idList(fb[2]) },
    objectives = { creatures = objList(ob[1]), objects = objList(ob[2]), items = objList(ob[3]), rep = objList(ob[4]),
                   killCredit = killCreditList(ob[5]), spells = objList(ob[6]) },
    objectivesText = strList(getQ(id, "objectivesText")),
    trigger = trigger(getQ(id, "triggerEnd")),
    preGroup = optIds(getQ(id, "preQuestGroup")), preSingle = optIds(getQ(id, "preQuestSingle")),
    exclusiveTo = optIds(getQ(id, "exclusiveTo")),
    zone = num(getQ(id, "zoneOrSort")),
    reqSkill = pair(getQ(id, "requiredSkill")),
    reqMaxLevel = num(getQ(id, "requiredMaxLevel")),
    nextInChain = num(getQ(id, "nextQuestInChain")),
    specialFlags = num(getQ(id, "specialFlags")),
    parentQuest = num(getQ(id, "parentQuest")),
    reqSpell = num(getQ(id, "requiredSpell")),
    breadcrumbFor = num(getQ(id, "breadcrumbForQuestId")),
    reqMinRep = pair(getQ(id, "requiredMinRep")),
    sourceItem = num(getQ(id, "sourceItemId")),
    questFlags = num(getQ(id, "questFlags")),
  }
  q.questType = num(getQ(id, "questType"))
  q.suggestedPlayers = num(getQ(id, "suggestedPlayers"))
  if q.level <= 0 then q.level = math.max(q.reqLevel, 1) end
  local xpRow = self.xp and self.xp[id]
  q.xp = (type(xpRow) == "table" and type(xpRow[2]) == "number" and xpRow[2]) or (type(xpRow) == "number" and xpRow) or nil
  if not q.xp then local x = getQ(id, "xp") if type(x) == "number" and x > 0 then q.xp = x end end
  -- WoW Forever: quests open to every classic race of a side also admit that side's Skyborne race.
  -- (Assumption, documented in PanoplySuite_QuestData/Forever.lua.)
  local sm = self.overlay and self.overlay.sideMasks
  if sm and q.races ~= 0 then
    for _, v in pairs(sm) do
      if q.races == v.classic then q.races = q.races + v.extra end
    end
  end
  return q
end

QD.badQuests = {}
function QD:GetQuest(id)
  if type(id) ~= "number" then return nil end
  local c = self.cache[id]
  if c ~= nil then return c or nil end
  if not self.source then return nil end
  local okN, name = pcall(getQ, id, "name")
  if not okN then self.badQuests[id] = tostring(name); Panoply:Debug("skipped quest", id, name); self.cache[id] = false return nil end
  -- Forever title-only facts are not routable DB.Q records; keep their unknown metadata empty.
  if type(name) ~= "string" and self.overlay and self.overlay.questTitles then
    name = self.overlay.questTitles[id]
  end
  if type(name) ~= "string" then self.cache[id] = false return nil end
  local ok, q = pcall(buildQuest, self, id, name)
  if not ok then
    -- one odd record must never break planning: skip it and note why
    self.badQuests[id] = tostring(q)
    Panoply:Debug("skipped quest", id, name, q)
    self.cache[id] = false
    return nil
  end
  self.cache[id] = q
  return q
end

local function safeName(get, id)
  if type(id) ~= "number" or not get then return nil end
  local ok, v = pcall(get, id, "name")
  return ok and str(v) or nil
end
function QD:NpcName(id) return self.source and safeName(getN, id) or nil end
function QD:ObjectName(id) return self.source and safeName(getO, id) or nil end
function QD:ItemName(id) return self.source and safeName(getI, id) or nil end
-- Side letter of the player ("A" or "H"); Alliance when unknown (Panoply Suite's original audience).
function QD:PlayerSide()
  local f = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
  if f == "Horde" then return "H" end
  return "A"
end
function QD:NpcFriendly(id)
  local f = self.source and getN(id, "friendlyToFaction")
  if f == nil then return nil end
  if self.own and f == "" then return false end   -- hostile to both sides
  return type(f) == "string" and f:find(self:PlayerSide(), 1, true) ~= nil
end
function QD:NpcLevel(id) return num(getN(id, "minLevel")), num(getN(id, "maxLevel")) end

-- Own data: spawn keys are uiMapIDs already (negative keys = inside an instance map, no spot).
-- On WoW Forever, points in re-drawn zones are re-expressed on the Forever map rectangle and marked
-- unverified: the world position is the 1.12 server's, not confirmed on Forever.
local function ownSpot(self, map, px, py)
  local x, y = px / 100, py / 100
  local fr = self.forever and self.own.foreverRects
  if fr and fr[map] and self.own.rects[map] then
    local nx, ny = self.own.Reproject(map, x, y, fr)
    if nx then return { map = map, x = nx, y = ny, unverified = true } end
    return { map = map, x = x, y = y, unverified = true }
  end
  return { map = map, x = x, y = y }
end
local function spotsFrom(self, spawns)
  local out = {}
  if type(spawns) ~= "table" then return out end
  for area, list in pairs(spawns) do
    local map = (type(area) == "number" and area > 0) and area or nil   -- own data: keyed by UiMapID
    if map and type(list) == "table" then
      for _, p in ipairs(list) do
        if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" and p[1] >= 0 and p[2] >= 0 then
          out[#out + 1] = ownSpot(self, map, p[1], p[2])
        end
      end
    end
  end
  return out
end
QD.SpotsFrom = spotsFrom

-------------------------------------------------------------------------------
-- Learned and overlay positions (own data only). When the player talks to an NPC (gossip, quest,
-- vendor, trainer, flight master, bank) Panoply Suite stores where that NPC stood. On WoW Forever a
-- learned spot replaces the 1.12 spots on the same map; on Era it is used only for NPCs the database
-- has no spot for. Corrections shipped in PanoplySuite_QuestData/Forever.lua (overlay) count as learned.
-------------------------------------------------------------------------------
QD.LEARN_EVENTS = { "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING",
                    "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED" }

-- Location facts for notes under a step (PanoplySuite_QuestData only; the fallbacks have none).
function QD:LocationFact(kind, id)
  local DB = self.own
  if not DB or type(DB.Location) ~= "function" or type(id) ~= "number" then return nil end
  local ok, f = pcall(DB.Location, kind, id)
  return ok and f or nil
end
-- WoW Forever re-drew some zones; positions (and notes) there are not trusted until checked.
function QD:RedrawnZone(map)
  if not self.forever or not map then return nil end
  local F = self.own and self.own.overlay and self.own.overlay.forever
  return F and F.redrawnZones and F.redrawnZones[map] or nil
end

-- forever-data: WoW Forever's new zones (Mount Hyjal, Riverglades, Zephras Isle, Darkspear Islands, Shen'dralas), from Blizzard's own
-- client tables (Data/ForeverZones.lua, Forever TOCs only). The record for a UiMap id, or by zone name when the map is unknown
-- (inside an instance the map id is nil, or a sub-map the table does not list: the zone name still answers). Era, or no data file: always nil.
-- The tables carry no level range, so rec.minLevel / rec.maxLevel are nil; rec.exploreMin / exploreMax are a hint only.
function QD:NewZone(map, zoneName)
  if not self.forever then return nil end
  local Z = self.own and self.own.foreverZones
  if type(Z) ~= "table" or type(Z.byUiMap) ~= "table" then return nil end
  if map and Z.byUiMap[map] then return Z.byUiMap[map] end
  local m = type(zoneName) == "string" and zoneName ~= "" and Z.byName and Z.byName[zoneName]
  return m and Z.byUiMap[m] or nil
end

-- Levels the client tables give for a new zone's map: minLevel, maxLevel (nil: not in the tables), exploreMin, exploreMax (hint).
function QD:NewZoneLevels(map)
  local z = self:NewZone(map)
  if not z then return nil end
  return z.minLevel, z.maxLevel, z.exploreMin, z.exploreMax
end

function QD:LearnedStore()
  local db = Panoply.db
  if type(db) ~= "table" then return nil end
  local key = self.forever and "learnedNpcsForever" or "learnedNpcs"
  db[key] = db[key] or {}
  return db[key]
end

-- Creature id from a unit GUID ("Creature-0-<server>-<instance>-<zone>-<npcId>-<spawn>").
function QD.NpcIdFromGUID(guid)
  if Panoply.Compat and Panoply.Compat.Readable then guid = Panoply.Compat.Readable(guid) end   -- a secret GUID cannot be parsed
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id), "npc" end
  if kind == "GameObject" then return tonumber(id), "object" end
  return nil
end

-- Quests the database does not know (Forever-only quests): remember who gives / takes them.
QD.QUEST_START_EVENTS = { QUEST_DETAIL = "start" }
QD.QUEST_END_EVENTS = { QUEST_PROGRESS = "finish", QUEST_COMPLETE = "finish" }
function QD:LearnQuestRelation(event, npc)
  local role = QD.QUEST_START_EVENTS[event] or QD.QUEST_END_EVENTS[event]
  if not role or not _G.GetQuestID then return nil end
  local ok, qid = pcall(_G.GetQuestID)
  qid = ok and tonumber(qid)
  if not qid or qid <= 0 or self.own.Quest(qid) then return nil end
  local db = Panoply.db
  if type(db) ~= "table" then return nil end
  db.learnedQuests = db.learnedQuests or {}
  local e = db.learnedQuests[qid] or {}
  local okT, title = pcall(_G.GetTitleText or function() return nil end)
  if okT and type(title) == "string" and title ~= "" then e.title = title end
  e[role] = npc
  e.flavor = Panoply.Compat.Flavor()
  db.learnedQuests[qid] = e
  return qid
end

function QD:LearnFromUnit(unit, event)
  if not self.own then return nil end
  local guid = _G.UnitGUID and _G.UnitGUID(unit or "npc")
  local id, kind = QD.NpcIdFromGUID(guid)
  if not id or kind ~= "npc" then return nil end
  local map, x, y = Panoply.Compat.GetPlayerPos()
  if not map then return nil end
  local store = self:LearnedStore()
  if not store then return nil end
  local e = store[id]
  if e and e.map == map and math.abs(e.x - x) < 0.01 and math.abs(e.y - y) < 0.01 then
    e.n = (e.n or 1) + 1
  else
    store[id] = { map = map, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000,
                  t = (_G.time and _G.time()) or 0, n = 1 }
  end
  self.npcCache[id] = nil
  self.itemSpotCache = {}
  if event then self:LearnQuestRelation(event, id) end
  return id
end

function QD:ListenLearning()
  if self.learningOn then return end
  self.learningOn = true
  for _, ev in ipairs(QD.LEARN_EVENTS) do
    Panoply:On(ev, function(event) if QD.own then QD:LearnFromUnit("npc", event) end end)
  end
end

-- Spot list after overlay corrections and learned positions.
function QD:CorrectSpots(id, spots)
  local fixes = {}
  local ov = self.overlay and self.overlay.npcs and self.overlay.npcs[id]
  if type(ov) == "table" then
    for map, list in pairs(ov) do
      for _, p in ipairs(list) do fixes[#fixes + 1] = { map = map, x = p[1] / 100, y = p[2] / 100, verified = true } end
    end
  end
  local store = self:LearnedStore()
  local l = store and store[id]
  if type(l) == "table" and l.map then fixes[#fixes + 1] = { map = l.map, x = l.x, y = l.y, learned = true } end
  if #fixes == 0 then return spots end
  if not self.forever and #spots > 0 then return spots end
  local out = {}
  for _, f in ipairs(fixes) do out[#out + 1] = f end
  -- A fix replaces every database spot on its map: spots far from it are wrong on this client,
  -- spots close to it are the same place.
  local fixed = {}
  for _, f in ipairs(fixes) do fixed[f.map] = true end
  for _, s in ipairs(spots) do if not fixed[s.map] then out[#out + 1] = s end end
  return out
end

function QD:NpcSpots(id)
  if type(id) ~= "number" then return {} end
  local c = self.npcCache[id]
  if c then return c end
  if not self.source then return {} end
  local s = spotsFrom(self, getN(id, "spawns"))
  if #s == 0 and not self.own then
    local wp = spotsFrom(self, getN(id, "waypoints"))
    if wp[1] then s = { wp[1] } end
  end
  if self.own then s = self:CorrectSpots(id, s) end
  self.npcCache[id] = s
  return s
end

function QD:ObjectSpots(id)
  if type(id) ~= "number" then return {} end
  local c = self.objCache[id]
  if c then return c end
  if not self.source then return {} end
  local s = spotsFrom(self, getO(id, "spawns"))
  self.objCache[id] = s
  return s
end

-- Where an item comes from (drops from NPCs/objects). Bounded to keep it cheap.
function QD:ItemSpots(id)
  if type(id) ~= "number" then return {} end
  local c = self.itemSpotCache[id]
  if c then return c end
  local out = {}
  if self.source then
    local n = 0
    for _, npc in ipairs(idList(getI(id, "npcDrops"))) do
      for _, s in ipairs(self:NpcSpots(npc)) do out[#out + 1] = s end
      n = n + 1 if n >= 8 then break end
    end
    n = 0
    for _, obj in ipairs(idList(getI(id, "objectDrops"))) do
      for _, s in ipairs(self:ObjectSpots(obj)) do out[#out + 1] = s end
      n = n + 1 if n >= 4 then break end
    end
    if #out == 0 and self.own then   -- sold, not dropped
      n = 0
      for _, npc in ipairs(idList(getI(id, "vendors"))) do
        if self:NpcFriendly(npc) ~= false then
          for _, s in ipairs(self:NpcSpots(npc)) do s = U.Copy(s); s.vendor = npc; out[#out + 1] = s end
          n = n + 1 if n >= 4 then break end
        end
      end
    end
  end
  self.itemSpotCache[id] = out
  return out
end

-- Who drops an item: lists of NPC and object IDs (used by the quest tooltips on mobs). Cached.
QD.dropperCache = {}
-- 0.7: planner facts the converter used to leave out (PanoplySuite_QuestData/Data/Fixes.lua):
-- pre (seen in game), cond (quest gates), drop (quest item drop chances in percent).
function QD:Fixes() return self.own and self.own.fixes or nil end

function QD:ItemDroppers(id)
  if type(id) ~= "number" or not self.source then return {}, {} end
  local c = self.dropperCache[id]
  if c then return c[1], c[2] end
  local npcs, objs = idList(getI(id, "npcDrops")), idList(getI(id, "objectDrops"))
  self.dropperCache[id] = { npcs, objs }
  return npcs, objs
end

function QD:GiverSpots(q)
  local out = {}
  for _, npc in ipairs(q.starts.npc) do
    for _, s in ipairs(self:NpcSpots(npc)) do s = U.Copy(s); s.npc = npc; out[#out + 1] = s end
  end
  for _, obj in ipairs(q.starts.obj) do
    for _, s in ipairs(self:ObjectSpots(obj)) do s = U.Copy(s); s.obj = obj; out[#out + 1] = s end
  end
  return out
end

function QD:FinisherSpots(q)
  local out = {}
  for _, npc in ipairs(q.ends.npc) do
    for _, s in ipairs(self:NpcSpots(npc)) do s = U.Copy(s); s.npc = npc; out[#out + 1] = s end
  end
  for _, obj in ipairs(q.ends.obj) do
    for _, s in ipairs(self:ObjectSpots(obj)) do s = U.Copy(s); s.obj = obj; out[#out + 1] = s end
  end
  return out
end

-- Objective areas: list of { kind="kill"|"object"|"item"|"event", id, spots = {...} }
function QD:ObjectiveAreas(q)
  local out = {}
  local o = q.objectives
  for _, c in ipairs(o.creatures or {}) do out[#out + 1] = { kind = "kill", id = c[1], spots = self:NpcSpots(c[1]) } end
  for _, kc in ipairs(o.killCredit or {}) do
    local spots = {}
    for _, npc in ipairs(kc[1]) do for _, s in ipairs(self:NpcSpots(npc)) do spots[#spots + 1] = s end end
    out[#out + 1] = { kind = "kill", id = kc[2], spots = spots }
  end
  for _, ob in ipairs(o.objects or {}) do out[#out + 1] = { kind = "object", id = ob[1], spots = self:ObjectSpots(ob[1]) } end
  for _, it in ipairs(o.items or {}) do out[#out + 1] = { kind = "item", id = it[1], spots = self:ItemSpots(it[1]) } end
  if q.trigger and type(q.trigger[2]) == "table" then
    out[#out + 1] = { kind = "event", text = q.trigger[1], spots = spotsFrom(self, q.trigger[2]) }
  end
  return out
end

-- After 0.8.4: items a quest needs in your bags BEFORE its objective can be done (Data/Fixes.lua `need`; Marla's Last Wish: Samuel's
-- Remains before Marla's Grave). Not part of ObjectiveAreas: the game lists no objective line for them, so the objective indexes
-- stay the game's own. Returns { { item, count, name, npcs = {...}, spots = {...} }, ... } (empty for nearly every quest).
function QD:QuestNeeds(q)
  local F = self:Fixes()
  local list = q and F and F.need and F.need[q.id]
  local out = {}
  if type(list) ~= "table" then return out end
  for _, n in ipairs(list) do
    if type(n) == "table" and type(n[1]) == "number" then
      local npcs = idList(n[4])
      local spots = {}
      for _, npc in ipairs(npcs) do for _, s in ipairs(self:NpcSpots(npc)) do spots[#spots + 1] = s end end
      out[#out + 1] = { item = n[1], count = (type(n[2]) == "number" and n[2] > 0) and n[2] or 1, name = str(n[3]), npcs = npcs, spots = spots }
    end
  end
  return out
end

-- Gathering nodes by name -> count of spawns per UiMapID (e.g. "Copper Vein").
function QD:NodeSpawnsByMap(nodeName)
  local res = {}
  local own = self.own
  if own then
    -- gathering table first (same server spawns, already per map), then the object records
    local gd = own.GatherData or Panoply.GatherData
    if type(gd) == "table" and type(gd.maps) == "table" then
      for m, names in pairs(gd.maps) do
        local pts = names[nodeName]
        if type(pts) == "string" and #pts >= 6 then res[m] = (res[m] or 0) + math.floor(#pts / 6) end
      end
      if next(res) then return res end
    end
    for _, id in ipairs(own.ObjectIdsByName(nodeName)) do
      for _, s in ipairs(self:ObjectSpots(id)) do res[s.map] = (res[s.map] or 0) + 1 end
    end
    return res
  end
  return res
end

-------------------------------------------------------------------------------
-- Dungeon / raid / elite-group classification (own rules over the quest record fields)
-------------------------------------------------------------------------------
QD.QUEST_FLAG_RAID = 64          -- questFlags bit for raid quests
QD.ELITE_RANKS = { [1] = true, [2] = true, [3] = true }   -- elite, rare elite, boss
-- QuestInfo / quest_template.Type: 1 group (elite), 41 PvP, 62 raid, 81 dungeon. Only the own data
-- carries it; a record without it leaves questType nil.
QD.QUEST_TYPE_WHY = { [1] = "elite", [62] = "raid", [81] = "dungeon" }

-- Spawn summary for an NPC/object: total spawn areas, how many are instance areas.
local function spawnAreas(self, spawns)
  local all, inst = 0, 0
  if type(spawns) == "table" then
    for area, list in pairs(spawns) do
      if type(list) == "table" and #list > 0 then
        all = all + 1
        if self.own then
          if type(area) == "number" and area < 0 then inst = inst + 1 end   -- -mapId: inside an instance
        elseif self:IsInstanceArea(area) then inst = inst + 1 end
      end
    end
  end
  return all, inst
end
-- true when every known spawn is inside an instance
function QD:NpcOnlyInInstance(id)
  local all, inst = spawnAreas(self, getN(id, "spawns"))
  return all > 0 and inst == all
end
function QD:ObjectOnlyInInstance(id)
  local all, inst = spawnAreas(self, getO(id, "spawns"))
  return all > 0 and inst == all
end
function QD:NpcElite(id) return QD.ELITE_RANKS[num(getN(id, "rank"))] == true end

-- Sources of an item: only-instance? only-elite? (all droppers / containers must qualify)
function QD:ItemSourceInfo(itemID)
  if type(itemID) ~= "number" then return false, false end
  local drops = idList(getI(itemID, "npcDrops"))
  local objs = idList(getI(itemID, "objectDrops"))
  if #drops + #objs == 0 then return false, false end
  if self.own and #idList(getI(itemID, "vendors")) > 0 then return false, false end   -- also sold outside
  local onlyInst, onlyElite = true, #objs == 0
  for i, npc in ipairs(drops) do
    if i > 30 then break end
    if not self:NpcOnlyInInstance(npc) then onlyInst = false end
    if not self:NpcElite(npc) then onlyElite = false end
  end
  for i, o in ipairs(objs) do
    if i > 30 then break end
    if not self:ObjectOnlyInInstance(o) then onlyInst = false end
  end
  return onlyInst, onlyElite
end

-- Why a quest is a dungeon/raid/elite-group quest, or nil. Cached per quest.
function QD:GroupContentReason(q)
  self.groupCache = self.groupCache or {}
  local c = self.groupCache[q.id]
  if c ~= nil then return c or nil end
  local why
  if q.zone > 0 and self:IsInstanceArea(q.zone) then why = "dungeon"
  elseif q.questFlags > 0 and math.floor(q.questFlags / QD.QUEST_FLAG_RAID) % 2 == 1 then why = "raid"
  elseif QD.QUEST_TYPE_WHY[q.questType or 0] then why = QD.QUEST_TYPE_WHY[q.questType]
  else
    local o = q.objectives
    for _, cr in ipairs(o.creatures or {}) do
      if self:NpcOnlyInInstance(cr[1]) then why = "dungeon" break end
      if self:NpcElite(cr[1]) then why = "elite" break end
    end
    if not why then
      for _, kc in ipairs(o.killCredit or {}) do
        local list = kc[1]
        local inst, elite = #list > 0, #list > 0
        for _, npc in ipairs(list) do
          if not self:NpcOnlyInInstance(npc) then inst = false end
          if not self:NpcElite(npc) then elite = false end
        end
        if inst then why = "dungeon" break end
        if elite then why = "elite" break end
      end
    end
    if not why then
      for _, ob in ipairs(o.objects or {}) do if self:ObjectOnlyInInstance(ob[1]) then why = "dungeon" break end end
    end
    if not why then
      for _, it in ipairs(o.items or {}) do
        local inst, elite = self:ItemSourceInfo(it[1])
        if inst then why = "dungeon" break end
        if elite then why = "elite" break end
      end
    end
    if not why and q.trigger and type(q.trigger[2]) == "table" then
      local all, inst = 0, 0
      for area in pairs(q.trigger[2]) do all = all + 1 if self:IsInstanceArea(area) then inst = inst + 1 end end
      if all > 0 and inst == all then why = "dungeon" end
    end
    if not why then
      -- giver or finisher only reachable inside an instance
      local function onlyInside(list, fn) for _, id in ipairs(list) do if not fn(self, id) then return false end end return true end
      if (#q.starts.npc + #q.starts.obj > 0) and onlyInside(q.starts.npc, QD.NpcOnlyInInstance) and onlyInside(q.starts.obj, QD.ObjectOnlyInInstance) then why = "dungeon" end
      if (#q.ends.npc + #q.ends.obj > 0) and onlyInside(q.ends.npc, QD.NpcOnlyInInstance) and onlyInside(q.ends.obj, QD.ObjectOnlyInInstance) then why = "dungeon" end
    end
  end
  self.groupCache[q.id] = why or false
  return why
end

-- A quest with nothing to do but talk/deliver (pure lead-in).
function QD:IsLeadIn(q)
  local o = q.objectives
  local function empty(t) return not t or #t == 0 end
  if q.breadcrumbFor ~= 0 then return true end
  return empty(o.creatures) and empty(o.objects) and empty(o.items) and empty(o.killCredit) and not (q.trigger and q.trigger[2])
end

-- Profession trainers friendly to Alliance, found by NPC title (e.g. "Tailoring Trainer").
function QD:FindTrainers(professionName)
  self.trainerCache = self.trainerCache or {}
  if self.trainerCache[professionName] then return self.trainerCache[professionName] end
  local out = {}
  local allIds = self.own and self.own.NpcIds
  if allIds then
    local needle = professionName:lower()
    local function check(id)
      local sub = getN(id, "subName")
      if type(sub) == "string" then
        local l = sub:lower()
        if l:find(needle, 1, true) and l:find("trainer", 1, true) and self:NpcFriendly(id) then
          local spots = self:NpcSpots(id)
          if spots[1] then out[#out + 1] = { npc = id, name = self:NpcName(id) or sub, title = sub, spot = spots[1] } end
        end
      end
    end
    local okIds, ids = pcall(allIds)
    for _, id in ipairs(okIds and type(ids) == "table" and ids or {}) do
      if type(id) == "number" then
        local ok, err = pcall(check, id)
        if not ok then Panoply:Debug("skipped npc", id, err) end
      end
    end
  end
  self.trainerCache[professionName] = out
  return out
end
