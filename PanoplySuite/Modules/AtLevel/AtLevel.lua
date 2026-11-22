-- Panoply Suite 0.8.4: "At your level". One place for what a character of this level can do now: the dungeons in range, the gear it
-- can wear now and soon (one slot grid since 0.9.5), and the class quests and trainer visits still open. It is not a second
-- leveling guide: it lists, the Guide routes.
-- This file is the facts and the rules (no windows): the page is Modules/AtLevel/Page.lua.
--
-- Data: PanoplySuiteQuestData.LootData (PanoplySuite_QuestData/Loot/Loot.lua, built by tools/build_lootdata.py from the VMaNGOS world
-- database) and PanoplySuiteQuestData.MapData (the instance atlas of the Map module). Both are the classic 1.12 world, which WoW Forever
-- runs too; the dungeons only Forever has are named in LootData.forever.gaps and have no loot here (nothing is guessed); 0.9.5 lists
-- them by level from Data/ForeverDungeons.lua (community data, marked unverified). What
-- Forever changes goes in LootData.forever.items / bosses / quests (same record formats): on Forever those win, Era never reads them.
--
-- Read-only API for the other pages (Class Gear, Map / Instances, the Level-up Card):
--   Panoply.AtLevel:Open(level)                 open the page (level: look at another level; nil = your own)
--   Panoply.AtLevel:Available()                 true when the loot tables are installed
--   Panoply.AtLevel:Item(itemID)                one item of the tables: { id, name, quality, slot, slotName, typeName, reqLevel, ilvl, stats, ... }
--   Panoply.AtLevel:InstanceLoot(instanceID)    { { boss = name, items = { { item = <Item>, chance = percent }, ... } }, ... } in clearing order
--   Panoply.AtLevel:QuestLoot(questID)          { choice = { <Item>, ... }, fixed = { <Item>, ... } } or nil
--   Panoply.AtLevel:Dungeons(level)             the dungeons and raids in range: { { inst, when = "now" | "soon", from, lo, hi, side }, ... }
--   Panoply.AtLevel:LootFor(level, class)       gear this class can wear at this level or within the window's levels, with where it comes from
--   Panoply.AtLevel:Upgrades(level, class)      the best piece for each slot, as the gear engine ranks it (Panoply.Gear:BestPerSlot with this
--                                          page's slice: the window's levels ahead, every source but raids). Nothing is ranked here.
--   Panoply.AtLevel:Grid(level, class)          0.9.5: the slot grid, one cell a slot in paper-doll order, from the same engine answer
--   Panoply.AtLevel:Window() / SetWindow(n)     how many levels ahead the page looks (3, widened to 5 by the top strip's stepper)
--   Panoply.AtLevel:Instances()                 every dungeon and raid: the atlas, plus on WoW Forever the ones only Forever has
--   Panoply.AtLevel:ClassQuests(level, class)   the class quests open now or within the window
-- class is a class file name ("HUNTER"); nil = your own. Every list is a fresh table the caller may keep or reorder; the rows in it
-- are shared (LootFor's answer is kept for a moment, AL.KEEP seconds, so a page that asks three times pays once): do not change a row.
local ADDON, Panoply = ...
local C = Panoply.Compat
local AL = {}
Panoply.AtLevel = AL

AL.AHEAD = 3          -- "soon" = within this many levels (the window the page opens with)
AL.WINDOW_MAX = 5     -- 0.9.5: the top strip's stepper widens the window up to this many levels ahead
AL.BELOW = 4          -- a quest this many levels under you is still worth its reward
AL.LAST_LEVEL = 60
AL.KEEP = 2           -- seconds LootFor's last answers are kept (quests handed in and levels gained show after that)

local floor = math.floor

-- How many levels ahead the page looks ("Showing level 15 -> 18"): AHEAD to WINDOW_MAX, for this session only
function AL:Window()
  local w = floor(tonumber(self.window) or AL.AHEAD)
  return math.max(AL.AHEAD, math.min(AL.WINDOW_MAX, w))
end
function AL:SetWindow(n)
  local before = self:Window()
  self.window = math.max(AL.AHEAD, math.min(AL.WINDOW_MAX, floor(tonumber(n) or AL.AHEAD)))
  if self.window ~= before then self:Forget() end
  return self.window
end

-------------------------------------------------------------------------------
-- The data
-------------------------------------------------------------------------------
local function questData() return rawget(_G, "PanoplySuiteQuestData") end
function AL:Loot() local qd = questData() return qd and type(qd.LootData) == "table" and qd.LootData or nil end
function AL:MapData() local qd = questData() return qd and type(qd.MapData) == "table" and qd.MapData or nil end
function AL:Available() return self:Loot() ~= nil end

-- One table of the loot data ("items", "bosses", "quests") and, on WoW Forever, the table of Forever's own records that go before it
local function tables(self, name)
  local loot = self:Loot()
  if not loot then return nil, nil end
  local over = C.IsForever() and type(loot.forever) == "table" and type(loot.forever[name]) == "table" and loot.forever[name] or nil
  return type(loot[name]) == "table" and loot[name] or nil, over
end
local function record(self, name, key)
  local base, over = tables(self, name)
  local v = over and over[key]
  if v == nil and base then v = base[key] end
  return v
end

-- The game's inventory type number -> the slot it goes in: { key, name, the character's slot numbers }
AL.SLOTS = {
  [1] = { "head", "Head", { 1 } }, [2] = { "neck", "Neck", { 2 } }, [3] = { "shoulder", "Shoulder", { 3 } },
  [5] = { "chest", "Chest", { 5 } }, [20] = { "chest", "Chest", { 5 } }, [6] = { "waist", "Waist", { 6 } },
  [7] = { "legs", "Legs", { 7 } }, [8] = { "feet", "Feet", { 8 } }, [9] = { "wrist", "Wrist", { 9 } },
  [10] = { "hands", "Hands", { 10 } }, [11] = { "finger", "Finger", { 11, 12 } }, [12] = { "trinket", "Trinket", { 13, 14 } },
  [16] = { "back", "Back", { 15 } },
  [13] = { "weapon", "One-hand", { 16 } }, [21] = { "weapon", "Main hand", { 16 } }, [17] = { "weapon", "Two-hand", { 16 } },
  [14] = { "offhand", "Shield", { 17 } }, [22] = { "offhand", "Off hand", { 17 } }, [23] = { "offhand", "Held in off hand", { 17 } },
  [15] = { "ranged", "Ranged", { 18 } }, [25] = { "ranged", "Thrown", { 18 } }, [26] = { "ranged", "Ranged", { 18 } },
  [28] = { "ranged", "Relic", { 18 } },
}
-- the order the slots are listed in
AL.SLOT_ORDER = { "weapon", "offhand", "ranged", "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket" }

-- "class.subclass" of an item -> what it is called
AL.TYPES = {
  ["4.0"] = "", ["4.1"] = "Cloth", ["4.2"] = "Leather", ["4.3"] = "Mail", ["4.4"] = "Plate", ["4.6"] = "Shield",
  ["4.7"] = "Libram", ["4.8"] = "Idol", ["4.9"] = "Totem",
  ["2.0"] = "Axe", ["2.1"] = "Two-hand axe", ["2.2"] = "Bow", ["2.3"] = "Gun", ["2.4"] = "Mace", ["2.5"] = "Two-hand mace",
  ["2.6"] = "Polearm", ["2.7"] = "Sword", ["2.8"] = "Two-hand sword", ["2.10"] = "Staff", ["2.13"] = "Fist weapon",
  ["2.14"] = "", ["2.15"] = "Dagger", ["2.16"] = "Thrown", ["2.18"] = "Crossbow", ["2.19"] = "Wand", ["2.20"] = "Fishing pole",
}

-- What each class can use is the gear engine's rule table (Data/GearRules.lua), not a second copy here.
local function rulesOf(class) return Panoply.GearRules.classes[class or ""] end
-- an item of the loot tables as the engine's rules read it (no level of its own: this page asks about the kind of item)
local function asGear(it)
  local c, sub = tostring(it.kind or ""):match("^(%d+)%.(%d+)$")
  return { slot = it.invType, class = tonumber(c), sub = tonumber(sub), req = 0, mask = (it.classMask or 0) ~= 0 and it.classMask or nil }
end
-- body armour from light to heavy: a class is shown its heaviest kind (and, once it has a second heavy kind, that one too)
AL.ARMOUR = { "4.1", "4.2", "4.3", "4.4" }
AL.BODY = { head = true, shoulder = true, chest = true, wrist = true, hands = true, waist = true, legs = true, feet = true }
AL.CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
AL.CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
  MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
AL.QUALITY = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
-- the game's item quality colours (white, green, blue, purple, orange)
AL.QUALITY_COLOR = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

local function hasBit(mask, bitValue) return floor(mask / bitValue) % 2 == 1 end

local function split(s, sep)
  local out, pos = {}, 1
  while true do
    local a = s:find(sep, pos, true)
    if not a then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, a - 1)
    pos = a + 1
  end
end

-- One item of the tables, decoded once. nil when the tables do not have it.
AL.items = setmetatable({}, { __mode = "v" })
function AL:Item(id)
  local it = self.items[id]
  if it then return it end
  local raw = record(self, "items", id)
  if type(raw) ~= "string" then return nil end
  local f = split(raw, "|")
  local inv = tonumber(f[3]) or 0
  local slot = AL.SLOTS[inv]
  local stats = {}
  for k, v in (f[8] or ""):gmatch("(%a+):([%d%.]+)") do stats[k] = tonumber(v) end
  it = { id = id, name = f[1], quality = tonumber(f[2]) or 1, invType = inv, kind = f[4] or "",
    slot = slot and slot[1] or nil, slotName = slot and slot[2] or nil, wornIn = slot and slot[3] or nil,
    typeName = AL.TYPES[f[4] or ""] or "", reqLevel = tonumber(f[5]) or 0, ilvl = tonumber(f[6]) or 0,
    classMask = tonumber(f[7]) or 0, stats = stats, random = f[9] == "r" }
  self.items[id] = it
  return it
end

-- Can this class use the item at this level? (the class restriction written on the item, then the kind of armour or weapon)
function AL:CanUse(it, class, level)
  if not (it and it.slot and rulesOf(class)) then return false end
  return (Panoply.GearScore.CanUse(class, asGear(it), level or AL.LAST_LEVEL))
end

-- Is it the kind of body armour this class wants at this level? (a Warrior is not shown cloth trousers)
function AL:Fits(it, class, level)
  if not self:CanUse(it, class, level) then return false end
  if not AL.BODY[it.slot] or it.kind == "4.0" then return true end
  local can, best, bestFrom = rulesOf(class).armor, nil, nil
  for i = #AL.ARMOUR, 1, -1 do
    local from = can[i]
    if from and level >= from then best, bestFrom = i, from break end
  end
  if not best then return false end
  if it.kind == AL.ARMOUR[best] then return true end
  -- the kind worn before the heaviest one was learned (mail on a level 42 Warrior) still counts
  return bestFrom > 1 and it.kind == AL.ARMOUR[best - 1]
end

-------------------------------------------------------------------------------
-- Who is looking
-------------------------------------------------------------------------------
function AL:Player()
  local info = C.PlayerInfo() or {}
  local level = C.XP()
  return { level = tonumber(level) or 1, class = info.classFile, classID = info.classID, raceID = info.raceID, name = info.name,
    className = AL.CLASS_NAME[info.classFile or ""] or info.class }
end

-- the level the page looks at: the one asked for with Open(level), else your own
function AL:Level()
  local own = self:Player().level
  local v = tonumber(self.viewLevel)
  if v and v >= 1 and v <= AL.LAST_LEVEL and v ~= own then return floor(v), false end
  return own, true
end

function AL:Done(questID)
  local S = Panoply.State
  if S and type(S.completed) == "table" and S.completed[questID] then return true end
  return C.IsQuestCompleted(questID)
end

-------------------------------------------------------------------------------
-- Dungeons in range
-------------------------------------------------------------------------------
-- Every dungeon and raid the pages list: the instance atlas in its order (by the level of its monsters) and, on WoW Forever, the
-- dungeons only Forever has (Data/ForeverDungeons.lua, community data: inst.forever, inst.unverified). Those carry no doors and no
-- loot; an entry level from PanoplySuite_QuestData, when it carries one, wins over the data file's (none ships in this release). Returns the list and a table by id.
local function factsEntry(name)
  local qd = questData()
  local F = qd and qd.Facts
  if not (F and type(F.Dungeon) == "function") then return nil end
  local ok, d = pcall(F.Dungeon, name)
  return ok and type(d) == "table" and tonumber(d.minLevel) or nil
end
function AL:Instances()
  local d = self:MapData()
  local forever = C.IsForever() and true or false
  if self.instList and self.instFor == d and self.instForever == forever and self.instData == Panoply.ForeverDungeons then return self.instList, self.instById end
  local list, by, named = {}, {}, {}
  for _, inst in ipairs(d and d.instances or {}) do by[inst.id] = inst named[inst.name] = true end
  local placed = {}
  for _, id in ipairs(d and d.order or {}) do if by[id] and not placed[id] then placed[id] = true list[#list + 1] = by[id] end end
  for _, inst in ipairs(d and d.instances or {}) do if not placed[inst.id] then placed[inst.id] = true list[#list + 1] = inst end end
  local FD = Panoply.ForeverDungeons
  if forever and d and FD and type(FD.list) == "table" then
    for _, f in ipairs(FD.list) do
      if type(f) == "table" and f.name and not named[f.name] and type(f.mobs) == "table" then
        local enter = factsEntry(f.name) or f.enter or f.mobs[1]
        local lo, hi = f.mobs[1], f.mobs[2]
        -- the game's entry level moves the whole range with it when it is higher
        if enter > lo then hi, lo = hi + (enter - lo), enter end
        local inst = { id = "forever:" .. f.name, name = f.name, kind = "dungeon", size = 5, enter = enter, mobs = { lo, hi }, forever = true,
          unverified = FD.unverified and true or nil, estimated = f.estimated and true or nil, zoneName = f.zone, side = f.side }
        list[#list + 1] = inst
        by[inst.id] = inst
      end
    end
  end
  self.instList, self.instById, self.instFor, self.instForever, self.instData = list, by, d, forever, FD
  return list, by
end

-- "now": you can get in and the monsters are near your level. "soon": that is true within the window (Window() levels ahead).
-- The second value is the level it opens at.
function AL:DungeonState(inst, level)
  if type(inst) ~= "table" or type(inst.mobs) ~= "table" then return nil end
  local lo, hi = inst.mobs[1] or 1, inst.mobs[2] or 1
  local from, to
  if inst.kind == "raid" then from, to = AL.LAST_LEVEL, AL.LAST_LEVEL
  else from, to = math.max(inst.enter or 0, lo - 3), hi + 3 end
  if level >= from and level <= to then return "now", from end
  if level < from and level + self:Window() >= from then return "soon", from end
  return nil
end

-- The capitals and their doorsteps whose dungeon lies in one side's land: a badge for the other side (Data/ForeverDungeons.lua
-- gives Forever's own as `side`)
AL.SIDE_LAND = { ["Ragefire Chasm"] = "Horde", ["The Stockade"] = "Alliance" }
function AL:LandOf(inst) return inst and (inst.side or AL.SIDE_LAND[inst.name]) or nil end

-- How far the level is from the dungeon's monsters (0 inside their range): the page lists the best fit first
local function misfit(inst, level)
  local lo, hi = inst.mobs[1] or 1, inst.mobs[2] or 1
  if level < lo then return lo - level end
  if level > hi then return level - hi end
  return 0
end

-- { { inst, id, name, kind, when = "now" | "soon", from (the level it opens at), lo, hi, forever, side }, ... }: what you can do
-- now first (the best fit for your level first, dungeons before raids), then what opens within the window (soonest first)
function AL:Dungeons(level)
  level = level or self:Level()
  local list = self:Instances()
  local out = {}
  for i, inst in ipairs(list) do
    local when, from = self:DungeonState(inst, level)
    if when then
      out[#out + 1] = { inst = inst, id = inst.id, name = inst.name, kind = inst.kind, when = when, from = from, lo = inst.mobs[1], hi = inst.mobs[2],
        forever = inst.forever, side = self:LandOf(inst), pos = i }
    end
  end
  table.sort(out, function(a, b)
    if a.when ~= b.when then return a.when == "now" end
    if a.kind ~= b.kind then return a.kind ~= "raid" end
    if a.when == "now" then
      local fa, fb = misfit(a.inst, level), misfit(b.inst, level)
      if fa ~= fb then return fa < fb end
    elseif a.from ~= b.from then return a.from < b.from end
    return a.pos < b.pos
  end)
  return out
end

-- "Westfall 38.0, 77.5" for the first way in; nil when the atlas has no door
function AL:Door(inst)
  local d = inst and inst.doors and inst.doors[1]
  if not d then return nil end
  local zone = C.MapName(d[4]) or "outside"
  local where = ("%s %.1f, %.1f"):format(zone, d[5] * 100, d[6] * 100)
  if d[7] and d[7] > 0 then
    local data = self:MapData()
    local outer
    for _, i in ipairs(data and data.instances or {}) do if i.id == d[7] then outer = i end end
    where = ("inside %s (%s)"):format(outer and outer.name or "another dungeon", where)
  end
  return where, { kind = "instance", name = inst.name, sub = (inst.kind == "raid" and "Raid" or "Dungeon") .. " entrance", map = d[4], x = d[5], y = d[6] }
end

-- Point the arrow at the door: through Go to (Modules/Map/Navigate.lua), which is the waypoint list and the arrow that already exist
function AL:GoToDoor(inst)
  local _, dest = self:Door(inst)
  if not dest then return false end
  local M = Panoply.Map
  -- 0.9.5 phase 4K (spec 05 section 6): the door goes in the Map page's Dungeons group
  if M and M.Navigate and M.Navigate.Go then return M.Navigate:Go(dest, "dungeon") and true or false end
  if M and M.PointAt then return M:PointAt(dest.map, dest.x, dest.y, inst.name .. " (door)", "dungeon") and true or false end
  return false
end

function AL:OpenDungeonMap(inst)
  local M = Panoply.Map
  if not (M and M.Instances and M.Instances.Open and Panoply.Modules and Panoply.Modules:IsOn("map")) then return false end
  M.Instances:Open(inst and inst.id or nil)
  return true
end

-------------------------------------------------------------------------------
-- Loot of a boss, an instance, a quest
-------------------------------------------------------------------------------
function AL:InstanceLoot(id)
  local rows = record(self, "bosses", id)
  local out = {}
  for _, r in ipairs(rows or {}) do
    local items = {}
    for iid, ch in tostring(r[2] or ""):gmatch("(%d+):(%d+)") do
      local it = self:Item(tonumber(iid))
      if it then items[#items + 1] = { item = it, chance = tonumber(ch) } end
    end
    out[#out + 1] = { boss = r[1], items = items }
  end
  return out
end

function AL:QuestLoot(questID)
  local raw = record(self, "quests", questID)
  if type(raw) ~= "string" then return nil end
  local a, b = raw:match("^([^;]*);(.*)$")
  local function list(s)
    local t = {}
    for iid in (s or ""):gmatch("%d+") do local it = self:Item(tonumber(iid)) if it then t[#t + 1] = it end end
    return t
  end
  return { choice = list(a), fixed = list(b) }
end

-- Is the quest for the player's side? The data has no side on a quest: it is the side of who gives it (or, for a quest an item or an
-- object starts, of who takes it back). A quest with nobody to ask is let through.
function AL:QuestSide(q)
  local QD = Panoply.QuestData
  for _, list in ipairs({ q.starts and q.starts.npc or {}, q.ends and q.ends.npc or {} }) do
    if #list > 0 then
      for _, npc in ipairs(list) do if QD:NpcFriendly(npc) then return true end end
      return false
    end
  end
  return true
end

-- Is the quest one this character can take? Returns "now", "soon" (opens within AHEAD levels) or nil, and the quest.
-- Left out: the other side's quests, repeatable ones, and the ones that ask for a profession, a reputation or a spell (the page
-- cannot tell whether you have those).
function AL:QuestState(questID, level, class, raceID)
  local QD = Panoply.QuestData
  if not (QD and QD.GetQuest) then return nil end
  local own = questData()
  if own and own.IsHidden and own.IsHidden(questID) then return nil end
  local q = QD:GetQuest(questID)
  if not q then return nil end
  if (q.specialFlags or 0) % 2 == 1 or q.reqSkill or q.reqMinRep or (q.reqSpell or 0) ~= 0 or (q.parentQuest or 0) ~= 0 then return nil end
  if not self:QuestSide(q) then return nil end
  local cid = AL.CLASS_ID[class or ""]
  if q.classes ~= 0 and not (cid and hasBit(q.classes, 2 ^ (cid - 1))) then return nil end
  if q.races ~= 0 and raceID then
    local rm = QD:RaceMask(raceID)
    if not (rm and rm > 0 and hasBit(q.races, rm)) then return nil end
  end
  if (q.reqMaxLevel or 0) > 0 and level > q.reqMaxLevel then return nil end
  if q.reqLevel > level + self:Window() then return nil end
  return q.reqLevel <= level and "now" or "soon", q
end

-------------------------------------------------------------------------------
-- Gear for a level and a class
-------------------------------------------------------------------------------
-- Every piece of gear the class can wear at this level, or will within AHEAD levels, that comes from a dungeon in range or from a
-- quest of these levels. Each row: the item's fields, when ("now" | "soon"), and sources =
-- { { kind = "boss", instance = id, instanceName, boss, chance } | { kind = "quest", quest = id, name, level }, ... }.
-- opts.raceID / opts.done(questID): whose quests count (your own when the class is yours); opts.all = true leaves out nothing for
-- being the wrong kind of armour.
function AL:LootFor(level, class, opts)
  opts = opts or {}
  local me = self:Player()
  level = tonumber(level) or self:Level()
  class = class or me.class
  local out, by = {}, {}
  if not (self:Available() and rulesOf(class)) then return out end
  local mine = class == me.class
  local raceID = opts.raceID or (mine and me.raceID) or nil
  -- the same question asked again within a moment gets the same rows (never when the caller brings its own "done")
  local key = not opts.done and table.concat({ level, class, tostring(raceID), opts.all and "all" or "fit", self:Window() }, "|") or nil
  local now = C.GetTime()
  local kept = key and self.kept and self.kept[key]
  if kept and now - kept.at >= 0 and now - kept.at < AL.KEEP and kept.loot == self:Loot() then
    for i, r in ipairs(kept.rows) do out[i] = r end
    return out
  end
  local done = opts.done or (mine and function(q) return AL:Done(q) end) or function() return false end
  local function add(it, when, src)
    -- an item for a later level is "soon" at best; one for a level past the window is left out
    if it.reqLevel > level + self:Window() then return end
    local useAt = math.max(level, it.reqLevel)
    if not (opts.all and self:CanUse(it, class, useAt) or self:Fits(it, class, useAt)) then return end
    if it.reqLevel > level then when = "soon" end
    local row = by[it.id]
    if not row then
      row = { sources = {}, when = when }
      for k, v in pairs(it) do row[k] = v end
      by[it.id] = row
      out[#out + 1] = row
    elseif when == "now" then row.when = "now" end
    row.sources[#row.sources + 1] = src
  end
  for _, d in ipairs(self:Dungeons(level)) do
    for _, b in ipairs(self:InstanceLoot(d.id)) do
      for _, e in ipairs(b.items) do
        add(e.item, d.when, { kind = "boss", instance = d.id, instanceName = d.name, boss = b.boss, chance = e.chance })
      end
    end
  end
  local base, over = tables(self, "quests")
  local seenQuest = {}
  for _, set in ipairs({ over or {}, base or {} }) do
    for qid in pairs(set) do
      if not seenQuest[qid] then
        seenQuest[qid] = true
        local when, q = self:QuestState(qid, level, class, raceID)
        if when and q.level >= level - AL.BELOW and q.level <= level + self:Window() + 2 and not done(qid) then
          local r = self:QuestLoot(qid)
          for _, list in ipairs(r and { r.choice, r.fixed } or {}) do
            for _, it in ipairs(list) do add(it, when, { kind = "quest", quest = qid, name = q.name, level = q.level }) end
          end
        end
      end
    end
  end
  local order = {}
  for i, k in ipairs(AL.SLOT_ORDER) do order[k] = i end
  for _, row in ipairs(out) do
    table.sort(row.sources, function(a, b)
      if a.kind ~= b.kind then return a.kind == "quest" end           -- a sure reward before a drop
      if a.kind == "boss" then return (a.chance or 0) > (b.chance or 0) end
      return (a.quest or 0) < (b.quest or 0)
    end)
  end
  table.sort(out, function(a, b)
    -- a list by slot, in a steady order; which piece is better is the gear engine's to say, not this list's
    if a.slot ~= b.slot then return (order[a.slot] or 99) < (order[b.slot] or 99) end
    if a.reqLevel ~= b.reqLevel then return a.reqLevel > b.reqLevel end
    return a.id < b.id
  end)
  if key then
    self.kept = self.kept or {}
    local rows = {}
    for i, r in ipairs(out) do rows[i] = r end
    self.kept[key] = { at = now, rows = rows, loot = self:Loot() }
  end
  return out
end
-- forget what LootFor kept (a quest was handed in, a level gained)
function AL:Forget() self.kept = nil end

-- "Edwin VanCleef, The Deadmines (20%)" or "Quest: The Defias Brotherhood"
function AL.SourceText(src)
  if not src then return "" end
  if src.kind == "quest" then return ("Quest: %s"):format(src.name or "?") end
  return ("%s, %s (%d%%)"):format(src.boss or "?", src.instanceName or "?", src.chance or 0)
end

-- "Rare one-hand sword" / "Mail legs"
function AL.KindText(it)
  if it.typeName == nil and it.class then
    -- an item as the gear engine reads it: the same words from its numbers
    local inv = AL.SLOTS[it.slot or 0]
    it = { typeName = AL.TYPES[it.class .. "." .. tostring(it.sub)] or "", slotName = inv and inv[2] or "", slot = inv and inv[1] or nil, invType = it.slot }
  end
  local t = it.typeName or ""
  local slot = it.slotName or ""
  local what
  if it.slot == "weapon" or it.slot == "ranged" then
    what = t ~= "" and t or slot
    if it.invType == 13 and t ~= "" then what = "One-hand " .. t:lower() end
  elseif t ~= "" and t ~= slot then what = t .. " " .. slot:lower()
  else what = slot end
  return what
end

-------------------------------------------------------------------------------
-- What would be better than what you wear: the gear engine's answer
-------------------------------------------------------------------------------
-- The slots in this page's order -> the engine's slot keys
AL.GEAR_SLOT = { weapon = "mainhand", offhand = "offhand", ranged = "ranged", head = "head", neck = "neck", shoulder = "shoulder", back = "back",
  chest = "chest", wrist = "wrist", hands = "hands", waist = "waist", legs = "legs", feet = "feet", finger = "finger", trinket = "trinket" }

-- Who the gear is ranked for: your own character with what it wears, or (another level, another class) that class at that
-- level with nothing worn. Returns the engine's ctx and whether it is your own character as it is now.
function AL:GearContext(level, class, opts)
  local me = self:Player()
  level = tonumber(level) or self:Level()
  class = class or me.class
  if class == me.class and level == me.level then return Panoply.Gear:GetContext(), true end
  opts = opts or {}
  return Panoply.Gear:GetContext({ class = class, level = level, raceID = opts.raceID or (class == me.class and me.raceID) or nil, done = opts.done }), false
end

-- This page's slice of the engine (docs/specs/page-redesigns-04-gear-engine.md section 6): what can be worn up to the window's
-- levels from now (AHEAD unless the top strip widened it, or `window`), from every source but raids, with the pieces for later kept
-- and marked ("At level 17").
function AL:GearFilter(level, window)
  return { maxLevel = level + (tonumber(window) or self:Window()), includeLocked = true,
    sources = { quest = true, dungeon = true, vendor = true, auction = true, crafted = true, favor = true } }
end

-- For each slot: { slot, slotName, now = the best candidate that can be worn now and beats what is worn (nil: nothing does),
-- soon = the best one for a later level when it beats `now`, worn = the item it would replace, empty = a place is free }.
-- now and soon are the engine's candidates (itemID, name, quality, score, delta, source, lockReason, ...). The second value
-- is the engine's whole result (working = true while a long list is still being looked through).
function AL:Upgrades(level, class, opts)
  level = tonumber(level) or self:Level()
  local ctx = self:GearContext(level, class, opts)
  local out = {}
  if not ctx then return out, nil end
  local best = Panoply.Gear:BestPerSlot(ctx, self:GearFilter(level))
  for _, k in ipairs(AL.SLOT_ORDER) do
    local b = best and best[AL.GEAR_SLOT[k]]
    local e = { slot = k, slotName = b and b.label or nil }
    if b then
      e.worn, e.wornScore, e.empty = b.worn, b.wornScore, b.empty or nil
      for _, c in ipairs(b.candidates) do
        if c.upgrade then
          if not c.locked then e.now = e.now or c
          elseif not e.soon and (not e.now or (c.delta or 0) > (e.now.delta or 0)) then e.soon = c end
        end
      end
    end
    out[#out + 1] = e
  end
  return out, best
end

-- The slot grid (spec 01, 4.3): one cell per equipment slot in paper-doll order, from the gear engine's BestPerSlot for this page's
-- slice. Rings and trinkets are one cell each (the engine weighs a candidate against the weaker of the two worn).
AL.PAPER = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "mainhand", "offhand", "ranged" }

-- Returns { cells = { cell, ... }, now = slots with an upgrade to wear now, later = slots whose only upgrade waits for a higher
-- level, byDungeon = { [instance id] = { [slot key] = the item shown there } } (the slots whose shown upgrade drops there),
-- weighedFor, noWeights, working, wornPending, mine, best (the engine's whole result) }. A cell: { key, label, worn (the item worn
-- there, the weaker one of a pair), empty, list = the upgrade candidates, best first, now (the best one to wear now), soon (the best
-- one for later when it beats `now`), state = "up" | "locked" | "none", at (the level a "locked" cell waits for; nil when it waits
-- for weapon training: skill = "Axes"), pairOf (the off-hand cell: the main hand's one-hand weapon it goes with, one swap for a
-- worn two-hander) }. An item is listed once on the grid: in the first slot of the paper doll it ranks in (a one-hand weapon in
-- the main hand before the off hand).
function AL:Grid(level, class, opts)
  level = tonumber(level) or self:Level()
  local ctx, mine = self:GearContext(level, class, opts)
  local out = { cells = {}, now = 0, later = 0, byDungeon = {}, mine = mine }
  -- (0.9.5 phase 4H: opts.filter is another page's slice of the same engine: the Class page's Gear tab, up to five levels ahead)
  local best = ctx and Panoply.Gear:BestPerSlot(ctx, (opts and opts.filter) or self:GearFilter(level)) or nil
  out.best = best
  if best then out.weighedFor, out.noWeights, out.working = best.weighedFor, best.noWeights, best.working and true or false end
  out.wornPending = (mine and ctx and ctx.wornPending) and true or nil
  local seen, byKey = {}, {}
  for _, key in ipairs(AL.PAPER) do
    local b = best and best[key]
    local slot = Panoply.Gear.SLOTS[key]
    local cell = { key = key, label = (b and b.label) or (slot and slot.label) or key, list = {} }
    if b then
      cell.worn, cell.wornScore, cell.empty = b.worn, b.wornScore, b.empty or nil
      for _, c in ipairs(b.candidates or {}) do
        if c.upgrade and c.itemID and not seen[c.itemID] then
          seen[c.itemID] = true
          cell.list[#cell.list + 1] = c
        end
      end
    end
    for _, c in ipairs(cell.list) do
      if not c.locked then cell.now = cell.now or c
      elseif not cell.soon and (not cell.now or (c.delta or 0) > (cell.now.delta or 0)) then cell.soon = c end
    end
    byKey[key] = cell
    out.cells[#out.cells + 1] = cell
  end
  -- a worn two-hander: the main hand's best is a one-hand weapon weighed with an off-hand item, so the off hand shows that same
  -- item (one swap, not two upgrades with two gains of their own)
  local mh, oh = byKey.mainhand, byKey.offhand
  local partner = mh and mh.now and mh.now.pairedWith
  if partner and oh then
    for _, c in ipairs(oh.list) do
      if c.itemID == (partner.id or partner.itemID) and not c.locked then oh.now, oh.pairOf = c, mh.now end
    end
  end
  for _, cell in ipairs(out.cells) do
    if cell.now then cell.state = "up" out.now = out.now + 1
    elseif cell.soon then
      local lock = cell.soon.lock or {}
      cell.state = "locked"
      if lock.skill then cell.skill = lock.skill
      else cell.at = lock.level or cell.soon.requiredLevel out.later = out.later + 1 end
    else cell.state = "none" end
    -- the dungeon or raid the shown upgrade drops in (its main source and the others)
    local shown = cell.now or cell.soon
    for i = 0, shown and #(shown.secondarySources or {}) or -1 do
      local src = i == 0 and shown.source or shown.secondarySources[i]
      if type(src) == "table" and (src.kind == "dungeon" or src.kind == "raid") and src.instance then
        local t = out.byDungeon[src.instance]
        if not t then t = {} out.byDungeon[src.instance] = t end
        t[cell.key] = shown.itemID
      end
    end
  end
  return out
end

-- how many slots of the grid show an upgrade from this dungeon or raid (the cells "N upgrades for you" marks)
function AL.DungeonUpgrades(grid, id)
  local n = 0
  for _ in pairs(grid and grid.byDungeon[id] or {}) do n = n + 1 end
  return n
end

-------------------------------------------------------------------------------
-- Class quests and the class trainer
-------------------------------------------------------------------------------
-- The quests only this class gets that are open now or within AHEAD levels, not done, with the quests before them done:
-- { { id, name, level, reqLevel, when = "now" | "soon", inLog = true | nil, rewards = { <Item>, ... } }, ... }, newest first.
-- A name is listed once: several trainers hand out the same errand, and it is one quest to the player.
function AL:ClassQuests(level, class, opts)
  opts = opts or {}
  local me = self:Player()
  level = tonumber(level) or self:Level()
  class = class or me.class
  local loot = self:Loot()
  local out = {}
  local ids = loot and loot.classQuests and loot.classQuests[class or ""]
  if type(ids) ~= "string" then return out end
  local mine = class == me.class
  local raceID = opts.raceID or (mine and me.raceID) or nil
  local done = opts.done or (mine and function(q) return AL:Done(q) end) or function() return false end
  local log = mine and Panoply.State and type(Panoply.State.log) == "table" and Panoply.State.log or {}
  for sid in ids:gmatch("%d+") do
    local id = tonumber(sid)
    local when, q = self:QuestState(id, level, class, raceID)
    if when and not done(id) then
      local open = true
      for _, x in ipairs(q.exclusiveTo or {}) do if done(x) then open = false end end
      if open and q.preGroup then for _, p in ipairs(q.preGroup) do if not done(p) then open = false end end end
      if open and q.preSingle then
        local any = false
        for _, p in ipairs(q.preSingle) do if done(p) then any = true end end
        if not any then open = false end
      end
      -- a quest that only sends you to the next one is over once the next one is done
      if open and (q.breadcrumbFor or 0) ~= 0 and done(q.breadcrumbFor) then open = false end
      if open and (q.nextInChain or 0) ~= 0 and done(q.nextInChain) then open = false end
      if open then
        local r = self:QuestLoot(id)
        local rewards = {}
        for _, list in ipairs(r and { r.choice, r.fixed } or {}) do for _, it in ipairs(list) do rewards[#rewards + 1] = it end end
        out[#out + 1] = { id = id, name = q.name, level = q.level, reqLevel = q.reqLevel, when = when, inLog = log[id] and true or nil, rewards = rewards }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.when ~= b.when then return a.when == "now" end
    if a.reqLevel ~= b.reqLevel then
      if a.when == "now" then return a.reqLevel > b.reqLevel end
      return a.reqLevel < b.reqLevel
    end
    return a.id < b.id
  end)
  local seen, uniq = {}, {}
  for _, q in ipairs(out) do
    local first = seen[q.name]
    if not first then seen[q.name] = q uniq[#uniq + 1] = q
    elseif q.inLog then first.inLog = true end
  end
  return uniq
end

-- The top strip's trainer chip, from the same spell plan Class & Spec shows: { now = true, n, cost, text = "2 spells · 24s" } when
-- something can be bought now, { next = level, n, cost, text = "Next: level 16, 3 spells, 54s" } when the next visit is later, or
-- nil (that page is off, or nothing is left to buy). A plan that cannot be worked out is logged and gives no chip.
function AL:TrainerChip()
  local ST = Panoply.SpecTrainer
  if not (ST and ST.SpellPlan and ST.Money and Panoply.Modules and Panoply.Modules:IsOn("spectrainer") and ST:ClassFile()) then return nil end
  local ok, sp = pcall(ST.SpellPlan, ST)
  if not ok then Panoply:Debug("At your level: the spell plan failed:", sp) return nil end
  if type(sp) ~= "table" or not sp.table then return nil end
  local function spells(n) return ("%d %s"):format(n, n == 1 and "spell" or "spells") end
  if sp.now and sp.now.buy.n > 0 then
    return { now = true, n = sp.now.buy.n, cost = sp.now.buy.cost, text = ("%s · %s"):format(spells(sp.now.buy.n), ST.Money(sp.now.buy.cost)) }
  end
  if sp.next then
    return { next = sp.next.level, n = sp.next.buy.n, cost = sp.next.buy.cost,
      text = ("Next: level %d, %s, %s"):format(sp.next.level, spells(sp.next.buy.n), ST.Money(sp.next.buy.cost)) }
  end
  return nil
end

-- The class quest chip: shown only when a class quest is open now or opens within the window. { q = the first one, now = how
-- many are open now, soon = how many open later in the window } or nil.
function AL:ClassQuestChip(level, class)
  local list = self:ClassQuests(level, class)
  if #list == 0 then return nil end
  local now = 0
  for _, q in ipairs(list) do if q.when == "now" then now = now + 1 end end
  return { q = list[1], now = now, soon = #list - now, list = list }
end

-- WoW Forever: the Legacy Spelunker band each dungeon counts toward, and how far that band is: { [dungeon name] = { key, name,
-- done, total, this = this dungeon is done } }. Empty on Classic Era and when the Legacy page is not in this build.
function AL:Spelunker()
  local L = Panoply.Legacy
  local out = {}
  if not (L and L.Open and L.SPELUNKER and L.Row and L.RowState and L.Counting) then return out end
  local chars = L:Counting()
  for _, t in ipairs(L.SPELUNKER) do
    local r = L:Row("dng." .. t.key)
    local st = r and L:RowState(r, chars)
    if st and type(st.parts) == "table" then
      local done = 0
      for _, d in ipairs(st.parts) do if d.done then done = done + 1 end end
      for _, d in ipairs(st.parts) do
        out[d.name] = { key = t.key, name = t.name, done = done, total = #st.parts, this = d.done and true or false }
      end
    end
  end
  return out
end

function AL:GoToTrainer()
  local N = Panoply.Map and Panoply.Map.Navigate
  if not (N and N.Go) then return false end
  return N:Go({ kind = "type", name = "Class trainer", sub = "Nearest to you", type = "placeTrainClass" }) and true or false
end

-- Point me there for a candidate's source: a dungeon or raid drop goes to its door, a quest to whoever gives it (the nearest of
-- them), through Go to (Modules/Map/Navigate.lua). Returns true when the arrow has somewhere to go.
function AL:CanGoToSource(src)
  if type(src) ~= "table" then return false end
  if src.kind == "dungeon" or src.kind == "raid" then
    local _, by = self:Instances()
    return by[src.instance] ~= nil and self:Door(by[src.instance]) ~= nil
  end
  if src.kind == "quest" then
    local QD = Panoply.QuestData
    local q = QD and QD.GetQuest and src.id and QD:GetQuest(src.id)
    -- (a record without its givers has no one to point at)
    if not (q and type(q.starts) == "table" and type(q.starts.npc) == "table" and type(q.starts.obj) == "table" and QD.GiverSpots) then return false end
    return #QD:GiverSpots(q) > 0
  end
  return false
end
function AL:GoToSource(src)
  if not self:CanGoToSource(src) then return false end
  if src.kind == "dungeon" or src.kind == "raid" then
    local _, by = self:Instances()
    return self:GoToDoor(by[src.instance])
  end
  local N = Panoply.Map and Panoply.Map.Navigate
  if not (N and N.Go) then return false end
  local QD = Panoply.QuestData
  return N:Go({ kind = "quest", name = src.name or "the quest giver", spots = QD:GiverSpots(QD:GetQuest(src.id)) }) and true or false
end

-- The Legacy page, Challenges, with this Spelunker band open and scrolled to (WoW Forever only)
function AL:OpenSpelunker(key)
  local L = Panoply.Legacy
  if not (L and L.Open) then return false end
  if key and type(L.open) == "table" then L.open[key] = true end
  -- 0.9.5 phase 4G (spec 01 section 8): the page opens at the Dungeons section, on this band
  L.focus = { section = "dungeons", tier = key }
  return L:Open("challenges") and true or false
end

-- 0.9.5 phase 4G (spec 01 section 8): the camp Blueprints a dungeon drops for one of this character's professions that it does not
-- have yet (WoW Forever; the drop sources are the unverified notes of Data/ProfForever.lua). { { prof, name, boss } } in the
-- professions' order; empty on Classic Era, for a profession not learned, or once the object is known.
local function instKey(n) return tostring(n or ""):lower():gsub("^the ", "") end
function AL:Blueprints(dungeonName)
  local out = {}
  local PF, PC, PR = Panoply.ProfForever, Panoply.ProfCamp, Panoply.Professions
  if not (C.IsForever() and PF and PR and PR.CurrentSkill and dungeonName) then return out end
  local want = instKey(dungeonName)
  local snap
  local profs = {}
  for prof in pairs(PF.CAMP or {}) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local rank = PR:CurrentSkill(prof)
    if rank then
      local list = {}
      for _, o in ipairs(PF.CAMP[prof]) do list[#list + 1] = o end
      if prof == "Cooking" then
        for _, t in ipairs(PF.CAMPFIRE or {}) do
          if t.blueprint then list[#list + 1] = { name = t.tier .. " campfire", source = t.source, blueprint = true, skill = t.skill, campfire = true } end
        end
      end
      for _, o in ipairs(list) do
        if o.blueprint and o.source and instKey(o.source.instance) == want then
          -- a campfire tier cannot be read from the game yet, so its Blueprint is always offered
          local state = "missing"
          if PC and PC.ObjectState and not o.campfire then
            snap = snap or (PC.Snapshot and PC:Snapshot()) or { spells = {}, items = {} }
            state = PC:ObjectState(o, rank, snap) or "missing"
          end
          if state ~= "known" then out[#out + 1] = { prof = prof, name = o.name, boss = o.source.boss } end
        end
      end
    end
  end
  return out
end

-- the Professions page on that profession's Camp tab
function AL:OpenCamp(prof)
  local PUI = Panoply.ProfUI
  if not (PUI and PUI.Show) then return false end
  PUI.page = "Camp"
  PUI:Show(prof)
  return true
end

-------------------------------------------------------------------------------
-- Doors
-------------------------------------------------------------------------------
-- Open the page. level: look at another level (1 to 60); nil or your own level = your own.
function AL:Open(level)
  self.viewLevel = tonumber(level)
  if Panoply.Menu and Panoply.Menu.Open then return Panoply.Menu:Open("atlevel") end
end

-- Class Gear, when the class pages are in this build
function AL:OpenClassGear()
  local CP = Panoply.ClassPages
  if CP and type(CP.Open) == "function" then CP:Open(self:Player().class, "Gear") return true end
  return false
end
