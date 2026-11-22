-- Panoply Suite: written leveling guides (0.8.0). Own code, GPL-3.0-only (see ../LICENSE).
--
-- The guide text it follows is Polestar's own WoW Forever leveling route (GPL-3.0-only, https://github.com/fitzforge/polestar),
-- converted by tools/convert_polestar_guides.py into Data/Guides/*.lua. None of Polestar's add-on code, arrow, navigation or
-- frames is used: these steps run on Panoply Suite's own step engine (Engine/Steps.lua), arrow and guide window.
--
-- Which route a character follows (Panoply.cdb.routeSource, per character; /panoply route):
--   "auto"    (the default; Nov 10 2026) the written guides ARE the leveling route on WoW Forever and on Classic
--             Era: the character's race start, then its faction's route, guide after guide, each picked up from the character's own
--             quest progress. Where the player stands in a new Forever zone none of their guides goes to, it is "No guide for this
--             area yet" (Engine/NoGuide.lua); where no written guide has a step for them at all (every guide of their route done or
--             out-levelled; a race with no written route) it is "No guide step here" (G:NoStep).
--   "guides"  the same written route, held everywhere (new Forever zones too).
--   "planner" Nov 11 2026 ("turn planner off. use polestar."): gone. There is no planner route and no planner fallback
--             (Engine/Planner.lua P:BuildsLevelingRoute). A character who has routeSource = "planner" saved from before follows the
--             written guides like everyone else; the saved value is left as it is and means nothing. /panoply route planner changes
--             nothing. (Only the suite's older tests of the planner turn the planner back on, and with it these three old meanings.)
-- Where the route is kept (Nov 11 2026, "the guide should not reset after every login."): Panoply.cdb.plan.at is the guide's own step
-- number (guide.steps) of the step the engine stands on, kept up to date as the player moves on. At login, at a reload and when a side
-- trip or a no-guide area gives the route back (G:Start with keepIndex) the same guide comes back at that step, never a guide earlier in
-- the chain, with its steps still built from the character's own quest log and handed-in quests.
-- Level together (Engine/Sync.lua S:SharedGuide): the partner who follows, when in step with the party leader, takes the leader's written
-- guide at the leader's step; out of step, their own.
-- Classic Era follows the same converted guides in the classic zones. What is WoW Forever's alone never reaches an Era character: the
-- Skyborne starts (Zephras Isle) are never picked there, and a quest that is not in Era's own quest data (the quests Forever added to
-- the classic zones) is left out of the steps and of the "is this guide finished" count, so no step waits for a quest Era does not have.
--
-- What a guide step becomes: one Panoply Suite step with one goal per guide goal (accept, turnin, complete, quest objectives,
-- collect, goto, flight path, fly, hearth, sethome, level, enter, buy), an "only" race/class/faction condition decided once for
-- the character (a goal or step for another race or class is left out), and a "when" predicate checked live (a step whose
-- predicate fails is hidden, so the engine passes it, as Polestar's own guides intend). Goals the engine cannot see done
-- (train, vendor, note, use, abandon, destroy, task, nearest targets) are shown and never hold the step, except a task, which
-- waits for the player's tick. G.unsupported counts what the data carries that is not acted on.
local ADDON, Panoply = ...
local C, U = Panoply.Compat, Panoply.Util
local G = { fns = {}, guides = {}, index = nil, unsupported = {} }
Panoply.Guides = G

G.MODES = { auto = true, guides = true, planner = true }
G.SKYBORNE_IDS = { [95] = true, [96] = true }
G.GOTO_RADIUS = 8          -- yards: Polestar's own default for a goto
G.MAX_STEPS = 400          -- a guide is at most this many steps (the longest converted guide is far below)

-- the data files call these (Data/Guides/Index.lua, Alliance.lua, Horde.lua)
function Panoply.GuideDataAdd(fn) if type(fn) == "function" then G.fns[#G.fns + 1] = fn end end
function Panoply.GuideDataIndex(t) if type(t) == "table" then G.index = t end end

-- Build the guide tables once, when first needed (a client that never asks keeps them as unrun functions).
function G:Load()
  if self.loaded then return end
  self.loaded = true
  for _, fn in ipairs(self.fns) do
    local ok, g = pcall(fn)
    if ok and type(g) == "table" and type(g.id) == "string" then self.guides[g.id] = g
    else Panoply:Debug("guide data", tostring(g)) end
  end
  self.fns = {}
end

function G:HasData() return self.index ~= nil and (#self.fns > 0 or next(self.guides) ~= nil) end
-- WoW Forever, and (Nov 10 2026) Classic Era. Era needs its own quest data loaded: that is how a WoW Forever-only quest is told apart
-- (G.NotHere), and without it such a quest would hold a step for good.
function G:Available()
  if not self:HasData() then return false end
  if C.IsForever() then return true end
  if C.Flavor() ~= "era" then return false end
  local QD = Panoply.QuestData
  return QD ~= nil and QD.Available ~= nil and QD:Available() and true or false
end

-- Classic Era only: is this quest one that Era does not have (a quest WoW Forever added)? Era's own quest data (PanoplySuite_QuestData,
-- the Vanilla tables) lists every Era quest, so a guide quest that is not in it is Forever's. Never true on WoW Forever.
function G.NotHere(q)
  if not q or C.IsForever() then return false end
  local QD = Panoply.QuestData
  if not (QD and QD.Available and QD:Available()) then return false end
  return QD:GetQuest(q) == nil
end
-- Classic Era only: an item the Era client itself does not have (asked of the game; kept when the game cannot say)
local function itemNotHere(id)
  if not id or C.IsForever() then return false end
  local f = C.G("C_Item.DoesItemExistByID")
  if not f then return false end
  local ok, v = pcall(f, id)
  if not ok then return false end
  v = C.Readable(v)
  return v == false
end
-- Classic Era only: a creature or object Era's own data does not list (someone WoW Forever added to a classic zone)
local function entityNotHere(kind, id)
  if not id or C.IsForever() then return false end
  local QD = Panoply.QuestData
  if not (QD and QD.Available and QD:Available()) then return false end
  if kind == "npc" then return QD:NpcName(id) == nil end
  if kind == "object" then return QD:ObjectName(id) == nil end
  return false
end
-- Is this guide one this game has? WoW Forever: all of them. Classic Era: not a Skyborne start, and not a guide whose own zone is on no
-- Era map (Zephras Isle).
function G:InThisGame(guide)
  if not guide then return false end
  if C.IsForever() then return true end
  if type(guide.id) == "string" and guide.id:find("/skyborne/", 1, true) then return false end
  local QD = Panoply.QuestData
  local rects = QD and QD.own and QD.own.rects
  if type(rects) ~= "table" or next(rects) == nil then return true end
  local any, known = false, false
  for m in pairs(self:PrimaryMaps(guide)) do any = true if rects[m] then known = true end end
  return known or not any
end

-- Nov 11 2026: does the old planner still plan leveling routes? Never in the add-on (Engine/Planner.lua); only the suite's older tests.
local function plannerOn()
  local P = Panoply.Planner
  return P ~= nil and P.BuildsLevelingRoute ~= nil and P:BuildsLevelingRoute() and true or false
end
G.PlannerOn = plannerOn
function G:Mode()
  local m = Panoply.cdb and Panoply.cdb.routeSource
  if m == "planner" and not plannerOn() then return "auto" end   -- an old saved planner choice is harmless: the written guides
  return G.MODES[m] and m or "auto"
end
function G:SetMode(m)
  if not G.MODES[m] then return false end
  if m == "planner" and not plannerOn() then return false end   -- the planner is off: nothing changes
  if Panoply.cdb then Panoply.cdb.routeSource = (m ~= "auto") and m or nil end
  if Panoply.NoGuide then Panoply.NoGuide.jcache = nil end
  return true
end

-------------------------------------------------------------------------------
-- Who the character is, and which guides are theirs
-------------------------------------------------------------------------------
local function isSkyborne(info)
  return (info.raceID and G.SKYBORNE_IDS[info.raceID]) or (type(info.raceFile) == "string" and info.raceFile:find("Skyborne", 1, true) ~= nil)
end
function G:Who()
  local info = C.PlayerInfo()
  return { race = isSkyborne(info) and "Skyborne" or info.raceFile, faction = info.faction, class = info.classFile }
end
function G:ChainKey(who)
  who = who or self:Who()
  if not (who.faction and who.race) then return nil end
  return who.faction .. ":" .. who.race
end
function G:Chain(who)
  local key = self:ChainKey(who)
  return key and self.index and self.index.chains and self.index.chains[key] or nil, key
end
function G:Guide(id) self:Load() return self.guides[id] end

-- `only` conditions: races OR, classes OR (a "!" class leaves that class out), factions OR; the groups AND
function G.Applies(cond, who)
  if not cond then return true end
  if cond.races then
    local ok
    for _, r in ipairs(cond.races) do if r == who.race then ok = true end end
    if not ok then return false end
  end
  if cond.classes then
    local ok
    for _, c in ipairs(cond.classes) do if c == who.class then ok = true end end
    if not ok then return false end
  end
  if cond.notClasses then
    for _, c in ipairs(cond.notClasses) do if c == who.class then return false end end
  end
  if cond.factions then
    local ok
    for _, f in ipairs(cond.factions) do if f == who.faction then ok = true end end
    if not ok then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- `when` predicates, checked on the live state (Polestar's guide format, "Conditions checked during play")
-------------------------------------------------------------------------------
function G.Money(text)
  if not text then return nil end
  if text:match("^%d+$") then return tonumber(text) end
  local total, any = 0, false
  for n, unit in text:gmatch("(%d+)([gsc])") do
    any = true
    total = total + tonumber(n) * ((unit == "g" and 10000) or (unit == "s" and 100) or 1)
  end
  return any and total or nil
end
local function cmp(a, op, b)
  if op == "<" then return a < b elseif op == "<=" then return a <= b elseif op == ">" then return a > b elseif op == ">=" then return a >= b end
  return nil
end
local function levelValue(s)
  local lvl = s.level or 1
  local max = (s.xpMax and s.xpMax > 0) and s.xpMax or nil
  return lvl + ((max and s.xp) and math.min(s.xp / max, 0.999) or 0)
end
local function ids(text)
  local out = {}
  for n in (text or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return out
end
-- true / false, or nil for a predicate this engine cannot read (counted in G.unsupported; the step is then shown)
function G.When(pred, s)
  local p = (pred or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local neg = false
  if p:sub(1, 1) == "!" then neg, p = true, p:sub(2) end
  local function out(v) if v == nil then return nil end if neg then return not v end return v end
  local op, n = p:match("^level%s*([<>]=?)%s*([%d%.]+)$")
  if op then return cmp(levelValue(s), op, tonumber(n)) end   -- `level` takes no "!"
  local mop, amount = p:match("^money%s*([<>]=?)%s*(%S+)$")
  if mop then local m = G.Money(amount) return m and cmp(C.Money and C.Money() or 0, mop, m) or nil end
  local word, rest = p:match("^(%a+)%s*(.*)$")
  if not word then return nil end
  word = word:lower()
  rest = rest:gsub('^"(.*)"$', "%1")
  if word == "onquest" then
    for _, q in ipairs(ids(rest)) do if s.log[q] then return out(true) end end
    return out(false)
  elseif word == "complete" then
    local q = tonumber(rest:match("%d+"))
    local e = q and s.log[q]
    return out(e and e.isComplete and true or false)
  elseif word == "turnedin" then
    local q = tonumber(rest:match("%d+"))
    return out(q and s.completed[q] == true or false)
  elseif word == "available" then
    local q = tonumber(rest:match("%d+"))
    if not q then return nil end
    if s.log[q] or s.completed[q] then return out(false) end
    local QD = Panoply.QuestData
    local rec = QD and QD.Available and QD:Available() and QD:GetQuest(q)
    if rec and (rec.reqLevel or 0) > (s.level or 1) then return out(false) end
    return out(true)
  elseif word == "has" then
    local item, count = rest:match("^(%d+)%s*x?(%d*)")
    if not item then return nil end
    return out(C.ItemCount(tonumber(item)) >= (tonumber(count) or 1))
  elseif word == "skill" then
    local name, rank = rest:match('^"?(.-)"?%s+(%d+)$')
    if not name then return nil end
    local have = (s.skills and (s.skills[name] or s.skills["One-Handed " .. name])) or 0
    return out(have >= tonumber(rank))
  elseif word == "group" then
    -- 0.9.7: the converted guide has no question card; it answers from the Group quests setting: "Always include them" shows
    -- group steps, the other two leave them out (Engine/Difficulty.lua)
    local Dif = Panoply.Difficulty
    return out(Dif ~= nil and Dif.GroupQuests ~= nil and Dif.GroupQuests() == "do")
  elseif word == "dungeon" then
    return out(false)   -- Polestar's own default: every dungeon run is off until the player picks it
  elseif word == "zone" then
    return out(s.zone == rest or s.subzone == rest)
  elseif word == "subzone" then
    return out(s.subzone == rest)
  elseif word == "bound" then
    return out(C.BindLocation and C.BindLocation() == rest or false)
  elseif word == "knows" then
    local sp = tonumber(rest:match("%d+"))
    return sp and C.KnowsSpell and out(C.KnowsSpell(sp) and true or false) or nil
  end
  return nil
end
function G:StepApplies(step, s)
  if not step.when then return true end
  for _, p in ipairs(step.when) do
    local v = G.When(p, s)
    if v == false then return false end
    if v == nil then self.unsupported["when " .. p] = (self.unsupported["when " .. p] or 0) + 1 end
  end
  return true
end

-------------------------------------------------------------------------------
-- Guide step -> engine step
-------------------------------------------------------------------------------
local function quoted(name) return "\226\128\156" .. name .. "\226\128\157" end
-- Our own quest data first, then a title the game already knows: the quest log (Panoply.State.log) or the client's own title lookup
-- (Compat C.QuestTitle). "quest 12345" only when nothing knows the name (a quest newer than our data and not yet seen by the client).
local function questNameKnown(id)
  local QD = Panoply.QuestData
  local q = id and QD and QD.Available and QD:Available() and QD:GetQuest(id)
  if q and q.name then return q.name end
  local S = Panoply.State
  local entry = id and S and S.log and S.log[id]
  if entry and type(entry.title) == "string" and entry.title ~= "" then return entry.title end
  local t = id and C.QuestTitle and C.QuestTitle(id)
  if t then return t end
  -- Quest titles from a table in PanoplySuite_QuestData for a quest our data does not name; none ships in this release: nil
  local F = id and QD and QD.own and QD.own.Facts
  local fn = F and F.QuestName and F.QuestName(id)
  if type(fn) == "string" and fn ~= "" then return fn end
  return nil
end
local function questName(id, fallback)
  return questNameKnown(id) or fallback or ("quest " .. tostring(id))
end
G.QuestNameKnown = questNameKnown
local function entityName(kind, id, fallback)
  local QD = Panoply.QuestData
  if not (id and QD and QD.Available and QD:Available()) then return fallback end
  local n = (kind == "npc" and QD:NpcName(id)) or (kind == "object" and QD:ObjectName(id)) or (kind == "item" and QD:ItemName(id))
  return n or fallback
end

-- Nov 11 zone audit: a goal text for an item our data does not name, from the client's own name for it (C.ItemInfo reads it through
-- C.Readable). The function answers nil until the client knows the item; it holds the id, so nothing new goes into the saved plan.
local function itemRetext(id, make)
  return function()
    local info = C.ItemInfo and C.ItemInfo(id)
    local n = info and info.name
    if type(n) == "string" and n ~= "" then return make(n) end
    return nil
  end
end

-- a map id for a zone name the converter resolved; the player's own map when it is one of them
local function mapFor(guide, zone, s)
  local list = zone and guide.zones and guide.zones[zone]
  if not list then
    local m = zone and zone:match("^map (%d+)$")
    return m and tonumber(m) or nil
  end
  if s.pos and s.pos.map then for _, m in ipairs(list) do if m == s.pos.map then return m end end end
  return list[1]
end
-- a typed coordinate in Polestar's map frame ("era" by default) as a spot on this client's map
-- Classic Era: a coordinate typed in WoW Forever's own map frame ("live") is not used: Forever re-drew some maps, and Era's data
-- cannot say which. The caller then takes the place from Era's own quest data, as for a goal with no typed coordinate.
local function spot(guide, g, s)
  if not g.x then return nil end
  if (g.frame or guide.coords or "era") ~= "era" and not C.IsForever() then return nil end
  local map = g.map or mapFor(guide, g.zone, s)
  if not map then return nil end
  local x, y = g.x, g.y
  local QD = Panoply.QuestData
  local own = QD and QD.own
  if (g.frame or guide.coords or "era") == "era" and QD and QD.forever and own and own.foreverRects and own.rects and own.foreverRects[map] and own.rects[map] and own.Reproject then
    local nx, ny = own.Reproject(map, x, y, own.foreverRects)
    if nx then x, y = nx, ny end
  end
  return { map = map, x = x, y = y }
end
local function nearestSpot(spots, ref)
  local best, bd
  for _, p in ipairs(spots or {}) do
    local d = (ref and ref.map == p.map) and ((p.x - ref.x) ^ 2 + (p.y - ref.y) ^ 2) or (ref and 9 or 0)
    if not bd or d < bd then best, bd = p, d end
  end
  return best
end
-- Pick-up and hand-in spots from a table in PanoplySuite_QuestData (x and y in percent of the zone map) for a quest our data cannot
-- place. Only spots for the player's side or both sides. No such table ships in this release: nil.
local function factSpots(kind, q)
  local QD = Panoply.QuestData
  local F = q and QD and QD.own and QD.own.Facts
  local pts = F and F.QuestPoints and F.QuestPoints(q)
  local list = pts and pts[kind]
  if not list then return nil end
  local side, out = QD:PlayerSide(), {}
  for _, p in ipairs(list) do
    if p.map > 0 and (p.side == nil or p.side == "B" or p.side == side) then
      out[#out + 1] = { map = p.map, x = p.x / 100, y = p.y / 100 }
    end
  end
  return out[1] and out or nil
end
G.FactSpots = factSpots

-- where a quest's giver / ender / objectives are, from Panoply Suite's own quest data (pick-up and hand-in: else a pick-up table when the data add-on carries one)
local function questSpot(kind, q, g, ref)
  local QD = Panoply.QuestData
  if not (QD and QD.Available and QD:Available()) then return nil end
  local placed = kind == "accept" or kind == "turnin"
  if g.npc then
    local p = nearestSpot(QD:NpcSpots(g.npc), ref)
    if p or not placed then return p end
  elseif g.object then
    local p = nearestSpot(QD:ObjectSpots(g.object), ref)
    if p or not placed then return p end
  end
  local rec = q and QD:GetQuest(q)
  if placed then
    local p = rec and nearestSpot(kind == "accept" and QD:GiverSpots(rec) or QD:FinisherSpots(rec), ref)
    return p or nearestSpot(factSpots(kind, q), ref)
  end
  if not rec then return nil end
  local areas = QD:ObjectiveAreas(rec)
  local a = areas[g.obj or 1] or areas[1]
  return a and nearestSpot(a.spots, ref) or nil
end

-- One guide goal -> one engine goal (or nil when it is for someone else / never shown). A second result of true says the goal was
-- left out because this game does not have what it is about (Classic Era: a quest, item, creature or object that is WoW Forever's).
function G:Goal(guide, g, who, s, ref)
  if g.only and not G.Applies(g.only, who) then return nil end
  local v = g.v
  local out
  local q = g.id
  if (v == "accept" or v == "turnin" or v == "complete" or v == "abandon") and G.NotHere(q) then return nil, true end
  if g.quest and G.NotHere(g.quest) then return nil, true end
  if (v == "collect" or v == "buy") and not g.quest and itemNotHere(g.id or g.item) then return nil, true end
  if (v == "talk" or v == "kill") and not g.quest and entityNotHere("npc", g.id) then return nil, true end
  if v == "interact" and not g.quest and entityNotHere("object", g.id) then return nil, true end
  if v == "accept" or v == "turnin" or v == "complete" then
    local name = g.text or questName(q)
    local verb = (v == "accept" and "Accept ") or (v == "turnin" and "Hand in ") or "Finish "
    out = { type = v, questID = q, text = verb .. quoted(name) }
    if v == "accept" and g.lvl then out.text = out.text .. " (from level " .. g.lvl .. ")" end
    -- Nov 13 2026: "direct" = the quest is taken and handed in in the same talk (Distracting Jarven): never in the log before its
    -- hand-in, so the arrow points at it all the same (Engine/Steps.lua Engine:Target)
    for _, w in ipairs(g.words or {}) do if w == "direct" then out.direct = true end end
    -- After 0.8.2: the name was not known when the step was built ("quest 92840"): StepText asks again when it shows the goal
    if not g.text and q and not questNameKnown(q) then
      local suffix = (v == "accept" and g.lvl) and (" (from level " .. g.lvl .. ")") or ""
      out.retext = function(n) return verb .. quoted(n) .. suffix end
      -- Nov 13 2026 (Polestar 0.3.7.2 Teldrassil, quest 98403, named nowhere we can read): until the game names it, the line names
      -- the person the guide's own note gives ("Tallonkai Swiftroot: ..." or "Tallonkai Swiftroot, upstairs"), not a number
      local note = type(g.note) == "string" and g.note or ""
      local who, sep = note:match("^([^:,;%(]+)([:,;%(]?)")
      who = who and who:gsub("%s+$", "")
      -- a person, not a place: followed by ":" or "," in the note, or two or more capitalised words ("Upstairs", "Below ground" are not)
      local words, caps = 0, true
      for w in (who or ""):gmatch("%S+") do words = words + 1 if not w:match("^[%u\"']") then caps = false end end
      if who and who ~= "" and #who <= 40 and who:match("^%u") and caps and (sep ~= "" or words >= 2) then
        out.text = verb .. who .. "'s quest" .. suffix
      end
    end
    local p = spot(guide, g, s) or questSpot(v, q, g, ref)
    if p then out.mapID, out.x, out.y = p.map, p.x, p.y end
  elseif v == "kill" or v == "talk" or v == "interact" or (v == "collect" and g.quest) or (v == "use" and g.quest) then
    local kind = (v == "kill" or v == "talk") and "npc" or (v == "interact" and "object") or "item"
    local name = g.text or entityName(kind, (kind == "item" and (g.id or g.item)) or g.id, nil)
    local verb = (v == "kill" and "Kill ") or (v == "talk" and "Talk to ") or (v == "interact" and "Use ") or (v == "collect" and "Collect ") or "Use "
    -- no name anywhere (guide goal, our data): say which quest the target belongs to rather than a bare "the target"
    local what = name or ("the " .. (kind == "npc" and "target" or kind) .. (g.quest and (" for " .. quoted(questName(g.quest))) or ""))
    out = { text = verb .. what }
    if g.quest then
      out.type, out.questID = "objective", g.quest
      -- Nov 12 2026 (Felix's Box, Chest and Bucket of Bolts): Polestar often names the item or creature and not the objective's
      -- number. Such a goal is judged by its own item or creature (Engine/Steps.lua Goals.eval.objective), never by objective 1,
      -- which made every unnumbered part of a quest tick on the first objective alone.
      if g.obj then out.objIndex = g.obj
      else
        local id = g.id or g.item
        if kind == "item" then out.itemID, out.count = id, g.count
        elseif kind == "npc" then out.npcID = id
        else out.objectID = id end
        out.partName = name
      end
      if v == "use" then out.optional = true end
    elseif v == "talk" or v == "interact" then out.type = "talk"
    else out.type, out.optional = "confirm", true end
    -- where: Polestar's own spot first; else, for a numbered goal, that objective's area in our data; for an unnumbered one, the
    -- spots of its own item or creature (never objective 1's area, which is another part of the quest)
    local QD = Panoply.QuestData
    local own = not g.obj and g.quest and QD:Available() and (g.id or g.item)
      and ((kind == "item" and QD:ItemSpots(g.id or g.item)) or (kind == "npc" and QD:NpcSpots(g.id)) or (kind == "object" and QD:ObjectSpots(g.id))) or nil
    local p = spot(guide, g, s) or (g.quest and g.obj and questSpot("objective", g.quest, g, ref)) or (own and nearestSpot(own, ref))
      or (kind == "npc" and g.id and nearestSpot(QD:Available() and QD:NpcSpots(g.id) or {}, ref))
    if p then out.mapID, out.x, out.y = p.map, p.x, p.y end
    if not name and g.quest and not questNameKnown(g.quest) then
      out.retext = function(n) return verb .. "the " .. (kind == "npc" and "target" or kind) .. " for " .. quoted(n) end
      out.retextQuest = g.quest
    end
    -- Nov 11 zone audit: an item our data does not name (a quest-given totem, an item WoW Forever added) is named by the client once
    -- it knows it (in the bags, or cached): StepText asks again when it shows the goal. Polestar's collect / use id is always an item.
    if not name and kind == "item" and (g.id or g.item) then out.itemRetext = itemRetext(g.id or g.item, function(n) return verb .. n end) end
  elseif v == "collect" or v == "buy" then
    local id = g.id or g.item
    local known = g.text or entityName("item", id, nil)
    local name = known or "the item"
    local prefix = ((v == "buy") and "Buy " or "Collect ") .. (g.count and g.count > 1 and (g.count .. " x ") or "")
    local suffix = g.nearest and " (nearest vendor)" or ""
    out = { type = (v == "buy") and "buy" or "collect", itemID = id, count = g.count or 1, text = prefix .. name .. suffix }
    if not id then out.type, out.optional = "confirm", true end
    if not known and id then out.itemRetext = itemRetext(id, function(n) return prefix .. n .. suffix end) end
  elseif v == "goto" or v == "explore" then
    local p = spot(guide, g, s)
    if not p then self.unsupported["goto without a map"] = (self.unsupported["goto without a map"] or 0) + 1 return nil end
    out = { type = "goto", mapID = p.map, x = p.x, y = p.y, radius = g.radius or G.GOTO_RADIUS, text = "Go to " .. (g.text or g.zone or "the marked spot") }
  elseif v == "getfp" then
    out = { type = "guideFlight", node = g.text, text = "Learn the flight path at " .. (g.text or "the flight master") }
    local p = g.npc and questSpot("npc", nil, g, ref)
    if p then out.mapID, out.x, out.y = p.map, p.x, p.y end
  elseif v == "fly" then
    out = { type = "fly", zone = g.text, text = "Fly to " .. (g.text or "the next town") }
  elseif v == "hearth" then
    out = { type = "hearth", zone = g.text, text = "Use your Hearthstone to " .. (g.text or "your inn") }
  elseif v == "enter" then
    out = { type = "hearth", zone = g.text, text = "Go into " .. (g.text or "the area") }
    local p = spot(guide, g, s)
    if p then out.mapID, out.x, out.y = p.map, p.x, p.y end
  elseif v == "sethome" then
    if g.nearest or not g.text then out = { type = "confirm", optional = true, text = "Make the nearest inn your home" }
    else out = { type = "sethome", inn = g.text, text = "Make " .. g.text .. " your home (talk to the innkeeper)" } end
    local p = g.npc and questSpot("npc", nil, g, ref)
    if p then out.mapID, out.x, out.y = p.map, p.x, p.y end
  elseif v == "level" then
    local whole, frac = tostring(g.level or g.id or ""):match("^(%d+)%.?(%d*)$")
    local lvl = tonumber(whole or g.id)
    if not lvl then return nil end
    local xp = 0
    if frac and frac ~= "" and Panoply.Planner and Panoply.Planner.XPToLevel then xp = math.floor(Panoply.Planner.XPToLevel(lvl) * tonumber("0." .. frac)) end
    out = { type = "level", level = lvl, xp = xp, text = "Reach level " .. lvl .. (xp > 0 and (" (" .. math.floor(tonumber("0." .. frac) * 100 + 0.5) .. "%)") or "") }
  elseif v == "die" then
    return nil   -- a deathskip: Polestar's "Use deathskips" is off by default, and then the goal does not apply
  elseif v == "task" then
    out = { type = "confirm", optional = g.optional, text = g.text or "Do this, then tick it" }
  elseif v == "note" then
    out = { type = "confirm", optional = true, text = g.text or "" }
  elseif v == "train" then
    out = { type = "confirm", optional = true, text = g.trainClass and "Train your new spells at your class trainer" or ("Train " .. table.concat(g.words or {}, " ")) }
  elseif v == "vendor" then
    out = { type = "confirm", optional = true, text = "Sell your junk and repair at a vendor" }
  elseif v == "abandon" then
    out = { type = "confirm", optional = true, text = "Abandon " .. quoted(questName(q, g.text)) }
  elseif v == "destroy" then
    out = { type = "confirm", optional = true, text = "Destroy " .. (g.text or entityName("item", g.id, "the item")) }
  else
    -- money, wait, cast, skill, learn, craft, rep, achieve: shown, never holding the step
    self.unsupported["goal " .. tostring(v)] = (self.unsupported["goal " .. tostring(v)] or 0) + 1
    out = { type = "confirm", optional = true, text = (g.text or v) }
  end
  if g.optional then out.optional = true end
  if g.group then
    out.text = out.text .. " (group advised)"
    local f = out.itemRetext
    if f then out.itemRetext = function() local t = f() return t and (t .. " (group advised)") or nil end end
  end
  if g.note and g.note ~= "" then out.note = g.note end
  return out
end

-- the flight path goal: Polestar names the flight point ("Stormwind, Elwynn") or its part before the comma ("Stormwind")
Panoply.Goals.eval.guideFlight = function(g)
  local known = Panoply.cdb and Panoply.cdb.knownTaxi
  if not (known and g.node) then return Panoply.Goals.TODO end
  if known[g.node] then return Panoply.Goals.DONE end
  local pre = g.node .. ","
  for name in pairs(known) do if type(name) == "string" and name:sub(1, #pre) == pre then return Panoply.Goals.DONE end end
  return Panoply.Goals.TODO
end

-- goal types that are only a pointer or a note (what is left of a step whose quest this game does not have)
G.POINTERS = { ["goto"] = true, confirm = true, talk = true }
-- The engine steps of one guide, for this character
function G:Steps(guide, who, s, pickup)
  local steps, ref = {}, s.pos
  local carry = nil   -- the goals of an `along` step, listed with the next step (never a stop of their own)
  for i, st in ipairs(guide.steps) do
    if #steps >= G.MAX_STEPS then break end
    if G.Applies(st.only, who) then
      local goals, gone = {}, 0
      for _, g in ipairs(st.goals) do
        local eg, notHere = self:Goal(guide, g, who, s, ref)
        if eg then goals[#goals + 1] = eg elseif notHere then gone = gone + 1 end
      end
      -- Classic Era: a step that lost a goal because Era does not have its quest (or item, or creature), and that keeps nothing the
      -- engine could see done but pointers and notes, goes as a whole: walking to the spot of a quest that is not there is no step
      if gone > 0 then
        local keeps = false
        for _, eg in ipairs(goals) do if not G.POINTERS[eg.type] and not eg.optional then keeps = true end end
        if not keeps then goals = {} end
      end
      -- a goto beside other goals only points the way (the quest goals decide the step), as for the planner's talk steps
      local others = 0
      for _, eg in ipairs(goals) do if eg.type ~= "goto" then others = others + 1 end end
      if others > 0 then for _, eg in ipairs(goals) do if eg.type == "goto" then eg.hint = true end end end
      if st.along then
        carry = carry or {}
        for _, eg in ipairs(goals) do eg.optional = true carry[#carry + 1] = eg end
      elseif #goals > 0 then
        if carry then for _, eg in ipairs(carry) do goals[#goals + 1] = eg end carry = nil end
        local work = false
        for _, eg in ipairs(goals) do if eg.type ~= "accept" and eg.type ~= "turnin" and eg.type ~= "goto" and not eg.optional then work = true end end
        local step = { kind = work and "do" or "talk", title = st.title or guide.title, why = st.tip, goals = goals, guideID = guide.id, guideStep = i,
                       zone = st.zone or guide.zone, fromGuide = true }
        for _, eg in ipairs(goals) do if eg.mapID then step.mapID, step.x, step.y = eg.mapID, eg.x, eg.y ref = { map = eg.mapID, x = eg.x, y = eg.y } break end end
        -- Nov 13 2026 (play-through, Tauren: "Fizsprocket's Notes" starts from an item looted in the mine; the guide's pick-up is optional
        -- and its Finish was not, so the step could never end without the item): a quest whose pick-up in this step is optional has its
        -- other goals in the step wait for it (hidden until the quest is in the log or handed in; Engine/Steps.lua Goals.Status)
        local optional = {}
        for _, eg in ipairs(goals) do if eg.type == "accept" and eg.optional and eg.questID then optional[eg.questID] = true end end
        for _, eg in ipairs(goals) do
          if eg.questID and optional[eg.questID] and (eg.type == "complete" or eg.type == "objective") then eg.needsLog = true end
        end
        if st.when then
          local when = st
          local function applies(state) return G:StepApplies(when, state) end
          for _, eg in ipairs(goals) do eg.onlyIf = applies end
        end
        local acc, tin = {}, {}
        for _, eg in ipairs(goals) do
          if eg.type == "accept" then acc[#acc + 1] = questName(eg.questID) elseif eg.type == "turnin" then tin[#tin + 1] = questName(eg.questID) end
        end
        step.accepts, step.turnins = acc, tin
        steps[#steps + 1] = step
      end
    end
  end
  if pickup then steps = G.PickUp(steps, s) end
  return steps
end

-- 0.8.1 pickup: the steps from where THIS character is. A quest goal already done for them (handed in; an accept whose quest is in
-- the log or handed in) is left out; a step whose quest goals were all done goes with its pointers and notes; and every step before
-- the first one that still has quest work is left out, so step 1 and the arrow are the next real work (never the start of the zone).
local QUEST_GOALS = { accept = true, turnin = true, complete = true, objective = true }
-- Nov 13 2026: a quest whose pick-up the route moved past untaken (too hard then, or skipped; Engine/Steps.lua Engine:NoteNotTaken) and
-- that is still not in the log or handed in. It never brings the player back to its pick-up, and never keeps a guide "unfinished":
-- the Tauren at the end of Mulgore was sent back from Thunder Bluff to Bloodhoof Village (step 16), round and round.
local function passedUntaken(q, s)
  local nt = Panoply.cdb and Panoply.cdb.notTaken
  return (nt and q and nt[q] and not s.log[q] and not s.completed[q]) and true or false
end
G.PassedUntaken = passedUntaken
local function goalDone(g, s)
  local q = g.questID
  if not q then return false end
  if s.completed[q] then return true end
  if passedUntaken(q, s) then return true end
  if g.type == "accept" then return s.log[q] ~= nil end
  if g.type == "complete" then local e = s.log[q] return e and e.isComplete and true or false end
  return false
end
function G.PickUp(steps, s)
  local out, started = {}, false
  for _, st in ipairs(steps) do
    local had, kept = 0, {}
    for _, g in ipairs(st.goals) do
      if QUEST_GOALS[g.type] and g.questID then
        had = had + 1
        if not goalDone(g, s) then kept[#kept + 1] = g end
      else
        kept[#kept + 1] = g
      end
    end
    local open = 0
    for _, g in ipairs(kept) do if QUEST_GOALS[g.type] and g.questID then open = open + 1 end end
    if had > 0 and open == 0 then
      -- every quest goal of this step is done: the step goes
    elseif not started and open == 0 then
      -- a pointer, note or errand before the first real work (it belongs to the part already done)
    else
      started = true
      st.goals = kept
      out[#out + 1] = st
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- Which guide now, and handing it to the engine
-------------------------------------------------------------------------------
-- how far this character got in a guide: its quests for them that are in the log or handed in
-- skip (optional): quest ids not to count (Nov 13 2026: quests the guide being judged also has; see G:Pick)
function G:Progress(guide, who, s, skip)
  local n, seen = 0, {}
  if skip then for q in pairs(skip) do seen[q] = true end end
  for _, st in ipairs(guide.steps) do
    if G.Applies(st.only, who) then
      for _, g in ipairs(st.goals) do
        if g.v == "accept" and g.id and not seen[g.id] and (not g.only or G.Applies(g.only, who)) and (s.completed[g.id] or s.log[g.id]) and not G.NotHere(g.id) then
          seen[g.id] = true
          n = n + 1
        end
      end
    end
  end
  return n
end
G.MOVED_ON = 2   -- quests started in a later guide that say the character has moved on past an earlier one
-- a guide is done for this character once every quest it accepts or hands in (for them) is handed in (Classic Era: every such quest
-- that Era has; G.NotHere)
function G:Unfinished(guide, who, s)
  for _, st in ipairs(guide.steps) do
    if G.Applies(st.only, who) then
      for _, g in ipairs(st.goals) do
        -- Nov 13 2026 (play-through, Orc at the end of Durotar): a pick-up whose quest is in the log is done here, as for the steps
        -- (G.PickUp). Quests a guide only hands out and the next guide hands in (Crossroads Conscription) kept Durotar "unfinished"
        -- while it had no step left, so the character got no step at all instead of The Barrens.
        if (g.v == "accept" or g.v == "turnin") and g.id and (not g.only or G.Applies(g.only, who)) and not s.completed[g.id] and not G.NotHere(g.id)
          and not passedUntaken(g.id, s) and not (g.v == "accept" and s.log[g.id]) then return true end
      end
    end
  end
  return false
end
-- does the area at `map` lack the planner's quest data (Engine/NoGuide.lua's judgement)? Era never asks.
local function plannerBlind(map, zoneName)
  local NG = Panoply.NoGuide
  if not (NG and NG.Judge and map) then return false end
  local saved = G.judging
  G.judging = true
  local ok, reason = pcall(NG.Judge, NG, map, zoneName)
  G.judging = saved
  return ok and reason == "zone"
end
function G:CoversBlind(guide, s)
  for name, list in pairs(guide.zones or {}) do
    if name == guide.zone then for _, m in ipairs(list) do if plannerBlind(m, name) then return true end end end
  end
  return false
end
-- 0.8.1: a guide's own (primary) zone: the maps the data lists under guide.zone, as a set. NOT guide.zones as a whole: that table also
-- lists the maps the guide travels out to (Skyborne: Alterac, Stormwind, Elwynn, Westfall besides Zephras Isle's 2521 and 2665).
function G:PrimaryMaps(guide)
  local set = {}
  local list = guide and guide.zone and guide.zones and guide.zones[guide.zone]
  for _, m in ipairs(list or {}) do set[m] = true end
  return set
end
-- is the player standing in this guide's primary zone (a primary map, or the zone's name when the map is unknown)?
function G:InPrimaryZone(guide)
  local S = Panoply.State
  if not (guide and guide.zone and S) then return false end
  local pos = S.pos
  if pos and pos.map and self:PrimaryMaps(guide)[pos.map] then return true end
  return S.zone ~= nil and S.zone == guide.zone
end
-- Is this guide the character's own race start (Data/Guides/Index.lua `starts`: the first guide of their chain)?
function G:IsRaceStart(guide, who)
  local key = self:ChainKey(who)
  local starts = self.index and self.index.starts
  return guide ~= nil and key ~= nil and starts ~= nil and starts[key] == guide.id
end
-- 0.8.1: the player is in this guide's primary zone AND that zone is a new Forever zone (Engine/QuestData.lua NewZone: no planner data
-- there), or (after 0.8.4) the guide is the character's own race start. Until Nov 10 2026 this, with CoversBlind, was what "auto" asked
-- before it took a guide; G:Pick no longer does (the written guides are the route wherever they cover), and both stay as plain
-- questions about a guide and where the player stands.
function G:StartsHere(guide, who)
  if not self:InPrimaryZone(guide) then return false end
  if self:IsRaceStart(guide, who) then return true end
  local QD, S = Panoply.QuestData, Panoply.State
  local z = QD and QD.NewZone and QD:NewZone(S.pos and S.pos.map, guide.zone)
  return z ~= nil and z ~= false and not z.pvp
end
-- Is the player standing somewhere "auto" leaves to the planner: a new Forever zone, or a place the planner has no data for, that no
-- guide of this character's route goes to (its own zone or a zone it travels through)? A classic zone is never such a place; inside an
-- instance there is no position to judge, so the route stays what it was.
function G:ChainCovers(chain, map, zoneName)
  for _, id in ipairs(chain or {}) do
    local g = self.guides[id]
    if g and self:InThisGame(g) then
      if zoneName and zoneName ~= "" and (g.zone == zoneName or (g.zones and g.zones[zoneName])) then return true end
      if map then for _, list in pairs(g.zones or {}) do for _, m in ipairs(list) do if m == map then return true end end end end
    end
  end
  return false
end
function G:Uncovered(chain, s)
  local map = s.pos and s.pos.map
  local QD = Panoply.QuestData
  local z = QD and QD.NewZone and QD:NewZone(map, s.zone)
  local new = (z ~= nil and z ~= false) or (map ~= nil and plannerBlind(map, s.zone))
  if not new then return false end
  return not self:ChainCovers(chain, map, s.zone)
end
-- The guide this character should be on now: the first guide of their chain (race start, then the faction's route to 60) that this
-- game has, that they have not outlevelled, that still has a quest for them, and that they have not moved on from (0.8.1: a later guide
-- of the chain they can already do, with G.MOVED_ON or more of its quests taken or handed in, means they left this one behind). So a
-- level 25 character lands on the guide for 25, never back at the race start, and a finished guide hands on to the next, through 60.
-- "auto" (the default) and "guides" both follow this; "auto" alone gives way to the planner where the player stands in a place none of
-- their guides goes to (G:Uncovered). nil = no written guide covers this character now (the planner plans).
function G:Pick(s, who)
  if not self:Available() then return nil end
  local mode = self:Mode()
  if mode == "planner" then return nil end
  who = who or self:Who()
  if not C.IsForever() and who.race == "Skyborne" then return nil end   -- no Skyborne on Classic Era
  local chain = self:Chain(who)
  if not chain then return nil end
  self:Load()
  if mode == "auto" and self:Uncovered(chain, s) then return nil end
  local level = s.level or 1
  -- Nov 13 2026 (Polestar 0.3.7.2, Alliance 30-40: Stranglethorn Vale, Desolace, Stranglethorn Vale again): quests a later guide
  -- shares with this guide or any guide before it (a second visit to the same zone) are no sign of having moved on; only quests of
  -- its own count. Before, the first Stranglethorn visit's quests made the second visit "taken", and Desolace between them was skipped.
  local function questsUpTo(i)
    local set = {}
    for k = 1, i do
      local g = self.guides[chain[k]]
      for _, st in ipairs(g and g.steps or {}) do for _, gl in ipairs(st.goals or {}) do
        if (gl.v == "accept" or gl.v == "turnin") and gl.id then set[gl.id] = true end
      end end
    end
    return set
  end
  local function movedOn(i)
    local before
    for j = i + 1, #chain do
      local later = self.guides[chain[j]]
      if later and self:InThisGame(later) and (later.levels[1] or 1) <= level then
        before = before or questsUpTo(i)
        if self:Progress(later, who, s, before) >= G.MOVED_ON then return true end
      end
    end
    return false
  end
  for i, id in ipairs(chain) do
    local g = self.guides[id]
    if g and self:InThisGame(g) and level <= (g.levels[2] or 60) and self:Unfinished(g, who, s) and not movedOn(i) then return g end
  end
  return nil
end
-- Would the written guide take this character now? (Planner and Bootstrap ask before they plan.)
function G:UseHere()
  if Panoply:GuideUnavailable() then return false end   -- 0.9.7 (Nov 18 2026): the converted guides are no backup in the add-on
  if G.judging or not self:Available() or self:Mode() == "planner" or Panoply:PlayAlong() then return false end
  local Y = Panoply.Sync
  if plannerOn() then
    -- 0.8.1 (the suite's older planner tests): following a partner, the party leader plans; no pickup of our own over the leader's route
    if Y and Y.IsFollower and Y:IsFollower() then return false end
  else
    -- Nov 11 2026: following a partner, in step with the party leader, on a route the leader shared that is not a written guide (a
    -- Panoply Hub plan): no written guide of our own over it. In step with a leader on a written guide, Start takes that guide; out of
    -- step, our own written guide as when playing alone.
    if Y and Y.HoldsSharedRoute and Y:HoldsSharedRoute() then return false end
    if Y and Y.SharedGuide and Y:SharedGuide() then return true end
  end
  local S = Panoply.State
  if not S then return false end
  if not S.level then S:RefreshPlayer() end
  return self:Pick(S) ~= nil
end
-- Is this map one the written guide covers for this character (so Engine/NoGuide.lua must not say "No guide here")?
function G:CoversArea(key)
  if Panoply:GuideUnavailable() then return false end   -- 0.9.7
  if G.judging or not self:Available() or self:Mode() == "planner" then return false end
  local S = Panoply.State
  local g = S and self:Pick(S)
  if not g then return false end
  for _, list in pairs(g.zones or {}) do for _, m in ipairs(list) do if key == ("m" .. m) then return true end end end
  -- a guide of the route that came before goes here too (a Skyborne who has just finished Zephras Isle and still stands on it: the
  -- next guide leads them off the isle, so the isle is not "No guide for this area yet")
  local n = tonumber(type(key) == "string" and key:match("^m(%d+)$"))
  return n ~= nil and self:ChainCovers(self:Chain(), n, nil)
end

-- The written guide this character was on when the route was last saved (Panoply.cdb.plan, this game), or nil.
function G:SavedGuide()
  local saved = Panoply.cdb and Panoply.cdb.plan
  if not (saved and saved.source == "guides" and type(saved.guide) == "string") then return nil end
  if (saved.flavor or "forever") ~= C.Flavor() then return nil end
  return self:Guide(saved.guide), saved
end
local function chainIndex(chain, id) for i, x in ipairs(chain or {}) do if x == id then return i end end return nil end
-- The engine step to stand on in `steps` for the guide's own step number `at`: the first step at or after it (pickup may have left the
-- very step out because its quests are done). nil = every step left is before it.
function G.IndexAt(steps, at)
  if not at then return nil end
  for i, st in ipairs(steps) do if (st.guideStep or 0) >= at then return i end end
  return nil
end

-- Put the guide's steps in the engine. Returns true, info; or nil when no written guide applies (the caller goes on: "No guide step
-- here" since Nov 11 2026, Engine/Planner.lua).
-- keepIndex (login, a reload, the route coming back after a side trip or a no-guide area): the place is kept. The guide is the one saved
-- unless the picker has moved on to a later guide of the chain (finished, out-levelled, moved on); never an earlier one, which is what a
-- character whose handed-in quests the game has not sent yet, or who skipped a quest, would otherwise get. The engine stands on the
-- saved guide step (Panoply.cdb.plan.at), or the first one after it that still has work. The steps themselves still come from the
-- character's own quest log and handed-in quests (pickup), so nothing done is offered again.
-- Level together (Sync:SharedGuide): in step with the party leader on a written guide, this is the leader's guide, at the leader's step.
G.KEEP_REASONS = { login = true, ["left the no-guide area"] = true }   -- the route coming back by itself keeps its place
function G:Start(reason, keepIndex)
  if Panoply:PlayAlong() then return nil end
  if Panoply:GuideUnavailable() then return nil end   -- 0.9.7 (Nov 18 2026): the converted guides are no backup in the add-on
  keepIndex = keepIndex or G.KEEP_REASONS[reason or ""] or false
  local S = Panoply.State
  S:RefreshAll()
  local who = self:Who()
  local guide = self:Pick(S, who)
  local Y = Panoply.Sync
  local shared = not plannerOn() and Y and Y.SharedGuide and Y:SharedGuide() or nil
  local sharedGuide = shared and self:Guide(shared.guide)
  if sharedGuide and not self:InThisGame(sharedGuide) then shared, sharedGuide = nil, nil end
  local at
  if sharedGuide then
    guide, at = sharedGuide, shared.at
  elseif keepIndex then
    local kept, saved = self:SavedGuide()
    if kept and self:InThisGame(kept) and (S.level or 1) <= (kept.levels[2] or 60) and self:Unfinished(kept, who, S) then
      local chain = self:Chain(who)
      local ki, pi = chainIndex(chain, kept.id), guide and chainIndex(chain, guide.id)
      -- the saved guide, unless the picker is on a later guide of this chain (a guide of another chain, a test's or an old one, is kept)
      if not guide or not ki or not pi or pi <= ki then guide = kept end
      if guide == kept then at = saved.at end
    end
  end
  if not guide then return nil end
  local steps = self:Steps(guide, who, S, true)   -- 0.8.1: from where this character is
  local title = ("%s (%d-%d)"):format(guide.title or guide.id, guide.levels[1], guide.levels[2])
  local P = Panoply.Planner
  -- 0.8.1: a planner job still being built (sliced, Planner:ReplanAsync) must not adopt its plan over the guide when it finishes
  if P.job then P.job = nil if P.driver then P.driver:Hide() end end
  P.actions, P.hash, P.planSet, P.lastStats = {}, nil, {}, nil
  local index = G.IndexAt(steps, at) or 1
  if Panoply.cdb then
    Panoply.cdb.plan = { guide = guide.id, chain = self:ChainKey(who), title = title, source = "guides", flavor = C.Flavor(),
                    at = steps[index] and steps[index].guideStep or nil,
                    shared = sharedGuide and shared.leader or nil }
  end
  -- the steps are rebuilt from this character's own progress every time (pickup), so a saved engine step number would point into a
  -- different list: the place is the guide's own step number (plan.at), found again in the new list
  Panoply.Engine.index = index
  Panoply.Engine:SetSteps(steps, title, true)
  if Panoply.cdb then Panoply.cdb.stepIndex = Panoply.Engine.index end
  self:NotePlace()
  self.current = guide.id
  Panoply:Fire("PLAN_ADOPTED", "guides")
  Panoply:Debug("guide", guide.id, "steps", #steps, "at", tostring(at), reason or "")
  return true, { guide = guide.id, steps = #steps, title = title, shared = sharedGuide and shared.leader or nil }
end

-- Keep Panoply.cdb.plan.at on the guide step the engine stands on (every step change, and after Start).
function G:NotePlace()
  local saved, E = Panoply.cdb and Panoply.cdb.plan, Panoply.Engine
  if not (saved and saved.source == "guides" and E) then return end
  local st = E.steps and E.steps[E.index]
  if st and st.fromGuide and st.guideID == saved.guide and st.guideStep then saved.at = st.guideStep end
end
Panoply:Listen("STEP_CHANGED", function() G:NotePlace() end)

-- Nov 11 2026 ("turn planner off. use polestar. when a user reports an issue on a missing quest then we incorporate it."): no
-- written guide has a step for this character here (every guide of their route is done or out-levelled; a race with no written route).
-- There is no planner to fill in: the guide window says so, and how to tell us about a missing quest. The saved route is left as it
-- is. Returns false and the line (Core/Bootstrap.lua AfterReplan prints it when the player asked).
G.NOSTEP_TITLE = "No guide step here"
G.NOSTEP_LINE = "The leveling guide has no step for this character here. If a quest is missing from it, type /panoply report and say which quest; missing quests are added to the guide."
function G:NoStep(reason)
  local P, E = Panoply.Planner, Panoply.Engine
  if P then
    if P.job then P.job = nil if P.driver then P.driver:Hide() end end
    P.actions, P.hash, P.planSet, P.lastStats = {}, nil, {}, nil
  end
  E.detour, E.travel = nil, nil
  E:SetSteps({}, G.NOSTEP_TITLE)
  self.current = nil
  Panoply:Debug("no guide step", reason or "")
  return false, G.NOSTEP_LINE
end
function G:NoStepShown()
  local E = Panoply.Engine
  return E ~= nil and #E.steps == 0 and E.title == G.NOSTEP_TITLE
end

-- What /panoply route prints. Nov 11 2026: the written guides are the only leveling route; there is no planner choice.
G.MODE_WORDS = {
  auto = "the written leveling guides for your race and faction, picked up from where this character is",
  guides = "the written leveling guides for your race and faction, kept in new zones they do not go to as well",
  planner = "Panoply Suite's planner only. This is the fallback: the written leveling guides are off for this character",   -- (the suite's older planner tests only)
}
G.PLANNER_OFF_LINE = "The planner is off: the written leveling guides are the only leveling route."
function G:Status()
  if not self:HasData() then return "The written leveling guides are not loaded." end
  -- 0.9.7 (Nov 18 2026): /panoply route on a character whose guide comes from the guide engine, or has no guide at all
  local PS = Panoply.PolestarEngine
  if PS and PS.on == true then return "Route: the leveling guide for this character, picked up from where this character is." end
  if Panoply:GuideUnavailable() then return Panoply.GUIDE_UNAVAILABLE_LINE end
  if not self:Available() then return "The written leveling guides are for WoW Forever." end
  local mode = self:Mode()
  local chain, key = self:Chain()
  local line = "Route: " .. G.MODE_WORDS[mode] .. "."
  if mode == "auto" then line = line .. " (This is the default.)" end
  local saved = Panoply.cdb and Panoply.cdb.plan
  local now = saved and saved.source == "guides" and saved.guide and self:Guide(saved.guide)
  local planner = mode == "planner"
  local none = planner and ", so the planner plans." or ". If a quest is missing, /panoply report tells us."
  if now and not planner then line = line .. " Now: " .. (now.title or now.id) .. "."
  elseif chain and not planner and Panoply.State and not self:Pick(Panoply.State) then line = line .. " No written guide has a step for this character here right now" .. none end
  if not chain then line = line .. " There is no written guide for " .. tostring(key) .. none end
  if mode ~= "auto" then line = line .. " /panoply route auto goes back to the default." end
  return line
end
