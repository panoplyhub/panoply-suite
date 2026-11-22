-- Panoply Suite location notes: a short plain line under a guide step saying where the NPC or object
-- is ("Inside the Lion's Pride Inn, upstairs", "Inside Stormwind Keep, throne room").
-- Facts come from, in order: our curated table (Data/LocationNotes.lua), the generated facts in
-- PanoplySuite_QuestData (inn rest areas, innkeepers, guard points of interest; VMaNGOS-derived data) and
-- entrances learned in game. Words are composed here from the phrase table below, so they can be
-- translated. When the facts are uncertain the note is left out - no guessing.
local ADDON, Panoply = ...
local L = {}
Panoply.Locations = L
local C = Panoply.Compat

L.ENTRANCE_YARDS = 8     -- close enough to the doorway: the arrow switches to the NPC itself
L.LEARN_YARDS = 80       -- learn an entrance only while heading for a target this close

-- Phrase table: English default; add a table per GetLocale() code to translate.
L.PHRASES = {
  enUS = {
    inside = "Inside %s",
    near = "Near %s",
    part = "%s, %s",              -- note, room or floor
    upstairs = "upstairs",
    downstairs = "downstairs",
    entrance = "Entrance to %s",
    entranceAny = "Entrance",
  },
}
function L.Phrase(key)
  local loc = (_G.GetLocale and _G.GetLocale()) or "enUS"
  local t = L.PHRASES[loc]
  return (t and t[key]) or L.PHRASES.enUS[key]
end

local function curated(kind, id)
  local T = Panoply.LocationNotesCurated
  local t = T and (kind == "object" and T.objects or T.npcs)
  local e = t and t[id]
  if type(e) ~= "table" or (e.kind ~= "inside" and e.kind ~= "near") then return nil end
  return { indoor = e.kind == "inside", near = e.kind == "near", name = e.name, room = e.room, floor = e.floor,
           entrance = e.entrance, forever = e.forever, curated = true }
end

function L:LearnedStore()
  local db = Panoply.db
  if type(db) ~= "table" then return nil end
  local key = (Panoply.QuestData and Panoply.QuestData.forever) and "learnedEntrancesForever" or "learnedEntrances"
  db[key] = db[key] or {}
  return db[key]
end

-- Facts for one NPC / object: { indoor, near, name, room, floor, entrance, curated } or nil.
-- map: where the step sends you (re-drawn Forever zones only trust entries checked on Forever).
function L:Fact(kind, id, map)
  if type(id) ~= "number" then return nil end
  local QD = Panoply.QuestData
  local f = curated(kind, id)
  if not f then
    local g = QD and QD.LocationFact and QD:LocationFact(kind, id)
    if g then f = { indoor = g.indoor, near = g.near, name = g.name, floor = g.floor, entrance = g.entrance } end
  end
  if not f then return nil end
  if QD and QD.RedrawnZone and QD:RedrawnZone(map) and not f.forever then return nil end
  if not f.entrance then
    local s = self:LearnedStore()
    local e = s and s[kind .. ":" .. id]
    if type(e) == "table" and e.map then f.entrance = { map = e.map, x = e.x, y = e.y, learned = true } end
  end
  return f
end

-- Text for facts, or nil when there is nothing certain to say.
function L.Compose(f)
  if type(f) ~= "table" or type(f.name) ~= "string" or f.name == "" then return nil end
  local P = L.Phrase
  if f.near then return P("near"):format(f.name) end
  if not f.indoor then return nil end
  local s = P("inside"):format(f.name)
  if type(f.room) == "string" and f.room ~= "" then s = P("part"):format(s, f.room) end
  if f.floor == 1 then s = P("part"):format(s, P("upstairs"))
  elseif f.floor == -1 then s = P("part"):format(s, P("downstairs")) end
  return s
end

-- The NPC / object a step is about: talk steps name it; "do" steps only when the quest has a
-- single creature or object target.
function L.StepTarget(step)
  if type(step) ~= "table" then return nil end
  if step.kind == "talk" then
    if step.npc then return "npc", step.npc end
    if step.obj then return "object", step.obj end
  elseif step.kind == "do" and step.questID and Panoply.QuestData then
    local q = Panoply.QuestData:GetQuest(step.questID)
    local o = q and q.objectives
    if type(o) ~= "table" then return nil end
    local found, kind, id = 0, nil, nil
    for _, c in ipairs(o.creatures or {}) do found = found + 1 kind, id = "npc", c[1] end
    for _, kc in ipairs(o.killCredit or {}) do found = found + 1 kind, id = "npc", kc[2] or (type(kc[1]) == "table" and kc[1][1]) end
    for _, ob in ipairs(o.objects or {}) do found = found + 1 kind, id = "object", ob[1] end
    if found == 1 and type(id) == "number" then return kind, id end
  end
  return nil
end

function L:ForStep(step)
  local kind, id = L.StepTarget(step)
  if not kind then return nil end
  return self:Fact(kind, id, step.mapID), kind, id
end

function L:NoteForStep(step)
  if type(step) ~= "table" then return nil end
  if step.locNote ~= nil then return step.locNote or nil end   -- precomputed / test value
  local f = self:ForStep(step)
  return L.Compose(f)
end

-- Entrance-first arrow: while the target is indoors with a known entrance and you are outside and
-- not yet at the doorway, return the entrance. Reaching it (or being indoors) points at the NPC.
function L:EntranceFor(step, m, x, y)
  if not step or not m then return nil end
  local f = self:ForStep(step)
  local e = f and f.indoor and f.entrance
  if not e or e.map ~= m then return nil end
  if C.Indoors() then return nil end
  if step.entranceReached then return nil end
  local pm, px, py = C.GetPlayerPos()
  local Nav = Panoply.Nav
  if pm and Nav and Nav.Distance then
    local d = Nav.Distance(pm, px, py, e.map, e.x, e.y)
    if d and d <= L.ENTRANCE_YARDS then step.entranceReached = true return nil end
  end
  local label = f.name and L.Phrase("entrance"):format(f.name) or L.Phrase("entranceAny")
  return e.map, e.x, e.y, label
end

-- Learning: the last outdoor spot before you step inside, near an indoor target without an
-- entrance, is remembered as that target's entrance (per client: Era and Forever kept apart).
function L:Sample()
  local E = Panoply.Engine
  local step = E and E.Current and E:Current()
  local pm, px, py = C.GetPlayerPos()
  if not step or not pm then return end
  local indoors = C.Indoors()
  if not indoors then self.lastOutdoor = { map = pm, x = px, y = py } end
  if indoors and self.wasOutdoors and self.lastOutdoor then
    local f, kind, id = self:ForStep(step)
    if f and f.indoor and not f.entrance and step.mapID == self.lastOutdoor.map and Panoply.Nav and Panoply.Nav.Distance then
      local d = Panoply.Nav.Distance(pm, px, py, step.mapID, step.x, step.y)
      if d and d <= L.LEARN_YARDS then
        local s = self:LearnedStore()
        local o = self.lastOutdoor
        if s then s[kind .. ":" .. id] = { map = o.map, x = math.floor(o.x * 10000 + 0.5) / 10000,
                                           y = math.floor(o.y * 10000 + 0.5) / 10000, t = (_G.time and _G.time()) or 0 } end
      end
    end
  end
  self.wasOutdoors = not indoors
end
Panoply:On("ZONE_CHANGED_INDOORS", function() L:Sample() end)
