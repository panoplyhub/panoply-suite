-- Panoply Suite "no guide for this area yet" (0.7.4.1, a Skyborne on Zephras Isle was sent to Dun Morogh).
-- Own code.
--
-- Panoply Suite only has quest data for the classic world. Where a player stands on a map that data does not cover (a Forever
-- zone such as Zephras Isle, or any map the data has no zone rectangle for), a route can only lead somewhere else, so the
-- guide does NOT plan there: no route, no guide arrow, no trail, no "go to <other zone>" steps. In its place:
--   * one line at the top of the quest tracker (and the same words in the guide window) saying so,
--   * "Record mode": saves every quest taken or handed in here, with the NPCs' places, the objectives and the turn-ins
--     (Engine/QuestRecorder.lua; PanoplySuiteDB.questRecords; tools/import_forever_recordings.py), ON by default here,
--   * "Turn guide off here": the player's own switch for this zone, remembered per character.
-- When the player reaches a zone the data covers, the guide comes back by itself (a fresh plan from where they stand).
--
-- How an area is judged (NG:Evaluate):
--   zone  the player's map, or one of its parents (up to four), has a zone rectangle in the quest data (DB.rects, the
--         classic world) and is not one of Forever's new zones (QD:NewZone). Otherwise there is no data: "zone".
--   off   the player turned the guide off in this zone (Panoply.cdb.noGuide.off[key]): "off".
--   Nothing is judged (guide stays as it is) when the map is unknown (loading screen, inside an instance), when the quest
--   data is not loaded, or when the data carries no zone rectangles at all (so a missing table can never switch the guide off).
-- Saved per character in PanoplySuiteCharDB.noGuide = { off = { [zoneKey] = true }, rec = { [zoneKey] = true | false } }.
-- zoneKey is "m<uiMap>" of the zone-level map (the map that has the data, or the new zone's first map, or the map itself).
local ADDON, Panoply = ...
local C = Panoply.Compat
local NG = {}
Panoply.NoGuide = NG

NG.LINE = "No guide for this area yet - recording your quests."
NG.LINE_NOREC = "No guide for this area yet - not recording."
NG.LINE_OFF = "Guide is off in this zone."
NG.LINE_OFF_REC = "Guide is off in this zone - recording your quests."
NG.REC_LABEL = "Record mode"
NG.OFF_LABEL = "Turn guide off here"
NG.MAX_PARENTS = 4

local function qd() return Panoply.QuestData end

local function store(create)
  local cdb = Panoply.cdb
  if not cdb then return nil end
  if type(cdb.noGuide) ~= "table" then
    if not create then return nil end
    cdb.noGuide = {}
  end
  local s = cdb.noGuide
  if type(s.off) ~= "table" then if not create then return s end s.off = {} end
  if type(s.rec) ~= "table" then if not create then return s end s.rec = {} end
  return s
end

local function mapInfo(map)
  local f = C.G and C.G("C_Map.GetMapInfo")
  if not f then return nil end
  local ok, info = pcall(f, map)
  return ok and type(info) == "table" and info or nil
end
local function parentOf(map)
  local info = mapInfo(map)
  local p = info and tonumber(C.Readable(info.parentMapID)) or nil
  if p and p > 0 then return p end
  return nil
end

-- Cosmic, world and continent maps (the client's UIMapType 0, 1, 2) have no zone rectangle, and a boat, a zeppelin, a swim off a coast or a
-- flight shows one of them. They say nothing about the guide: the last judgement stays. Fallback ids for a client that gives no map type.
NG.WORLD_MAPS = { [946] = true, [947] = true, [1414] = true, [1415] = true, [1463] = true, [1464] = true }
local function continentLike(map, rects)
  local info = mapInfo(map)
  local t = info and tonumber(C.Readable(info.mapType)) or nil
  if t then return t <= 2 end
  if NG.WORLD_MAPS[map] then return true end
  for _, r in pairs(rects) do if type(r) == "table" and r[7] == map then return true end end   -- the parent of the data's zones
  return false
end

-- The judgement for a map: reason ("zone" | nil), the zone key and a display name; or "hold" (cannot judge this map). `zoneName` is a fallback.
-- Cached per map and zone text.
function NG:Judge(map, zoneName)
  local QD = qd()
  if not (QD and QD.Available and QD:Available()) then return nil end
  local own = QD.own
  local rects = own and own.rects
  if type(rects) ~= "table" or next(rects) == nil then return nil end   -- cannot tell: never switch the guide off on a guess
  map = tonumber(map)
  if not map then return nil end
  local ck = map .. "|" .. tostring(zoneName or "")
  local c = self.jcache and self.jcache[ck]
  if c and c.qd == own then return c[1], c[2], c[3] end
  local function done(a, b, d)
    self.jcache = self.jcache or {}
    self.jcache[ck] = { a, b, d, qd = own }
    return a, b, d
  end
  -- the data's own zones first (the common case)
  if rects[map] then return done(nil, "m" .. map, (type(rects[map]) == "table" and rects[map][6]) or zoneName) end
  -- Classic Era has no Forever-only map (Mount Hyjal, Zephras Isle...): the client cannot be on one, so such a map is left as it always was
  if not QD.forever then
    local FR = Panoply.QuestRecorder
    if FR and FR.NewZone and FR:NewZone(map) then return done(nil) end
  end
  local nz = QD.NewZone and QD:NewZone(map, zoneName)
  if nz and nz.pvp then return done(nil) end   -- a battleground map: Panoply Suite has never planned there; unchanged
  if nz then
    local um = nz.uiMaps and nz.uiMaps[1] or map
    return done("zone", "m" .. um, nz.name)
  end
  if continentLike(map, rects) then return "hold" end   -- (not cached: the map type may arrive later)
  local m = map
  for _ = 1, self.MAX_PARENTS do
    local p = parentOf(m)
    if not p then break end
    if rects[p] then return done(nil, "m" .. p, (type(rects[p]) == "table" and rects[p][6]) or zoneName) end
    m = p
  end
  local name = zoneName
  if (not name or name == "") and C.MapName then name = C.MapName(map) end
  return done("zone", "m" .. map, (name and name ~= "") and name or "this area")
end

-- What the current place says: "hold" (cannot judge: keep the last answer), false (the guide applies) or an area { reason, key, name }.
function NG:Candidate()
  local S = Panoply.State
  local pos = S and S.pos
  if not (pos and pos.map) then return "hold" end        -- unknown map (loading screen, instance)
  if C.OnTaxi and C.OnTaxi() then return "hold" end       -- on a flight the map is the continent's
  local reason, key, name = self:Judge(pos.map, S.zone)
  if reason == "hold" then return "hold" end
  if not key then return false end
  -- 0.8.0: a written leveling guide covers this area for this character (Engine/Guides.lua: the Skyborne start on Zephras Isle)
  if reason == "zone" and Panoply.Guides and Panoply.Guides:CoversArea(key) then return false end
  if not reason then
    local s = store(false)
    if s and s.off and s.off[key] then reason = "off" end
  end
  if not reason then return false end
  return { reason = reason, key = key, name = name }
end

function NG:Area() return self.area end
-- Cheap and pure: the committed answer (Update changes it). Play-along mode owns the screen, so it is never "no guide" there.
function NG:Active()
  if Panoply.PlayAlong and Panoply:PlayAlong() then return false end
  return self.area ~= nil
end

-- A change must last this many seconds before it counts, so a border, a bay or a ferry cannot flap the guide.
NG.HYSTERESIS_S = 3

-- Record mode for the area: the player's saved choice, else on where there is no data and off where the player only turned the guide off.
-- /panoply recorded off (the account-wide switch) is the master: Record mode never changes it.
function NG:RecorderOff() return Panoply.db ~= nil and Panoply.db.questRecorder == false end
function NG:Recording()
  local a = self.area
  if not a then return false end
  if self:RecorderOff() then return false end
  local s = store(false)
  local v = s and s.rec and s.rec[a.key]
  if v ~= nil then return v and true or false end
  return a.reason == "zone"
end

function NG:GuideOff()
  local a = self.area
  local s = store(false)
  return a ~= nil and s ~= nil and s.off and s.off[a.key] == true
end

function NG:SetRecording(on)
  local a = self.area
  if not a then return false end
  local s = store(true)
  s.rec[a.key] = on and true or false
  if on and self:RecorderOff() then
    Panoply:Print("The quest recorder is switched off for the whole add-on (/panoply recorded off). Type /panoply recorded on to let Record mode save quests.")
  end
  if on then self:HookRecorder() local FR = Panoply.QuestRecorder if FR and FR.Queue then FR:Queue() end end
  Panoply:Fire("NOGUIDE_CHANGED")
  return true
end

-- The player's own switch. In a zone without data the guide is off anyway; the switch is then only remembered (the guide stays off
-- there when data for it arrives later). In a zone with data it turns the guide off for that zone.
function NG:SetGuideOff(on)
  local a = self.area
  if not a then return false end
  local s = store(true)
  if on then s.off[a.key] = true else s.off[a.key] = nil end
  self:Update(true)
  Panoply:Fire("NOGUIDE_CHANGED")
  return true
end

function NG:HookRecorder()
  local FR = Panoply.QuestRecorder
  if FR and FR.Hook then FR:Hook() end
end

NG.LINE_RECOFF = "No guide for this area yet - recording is off everywhere (/panoply recorded on)."
NG.LINE_OFF_RECOFF = "Guide is off in this zone - recording is off everywhere (/panoply recorded on)."
NG.LINE_PLAN = "There is no guide for this area yet, so there is no route to build. The guide comes back by itself in the first zone it has quests for."

-- What the tracker line and the guide window say.
function NG:Text()
  local a = self.area
  if not a then return nil end
  local rec = self:Recording()
  if a.reason == "zone" then return rec and NG.LINE or (self:RecorderOff() and NG.LINE_RECOFF or NG.LINE_NOREC) end
  return rec and NG.LINE_OFF_REC or (self:RecorderOff() and NG.LINE_OFF_RECOFF or NG.LINE_OFF)
end

-- Entering: stop the guide (nothing routes, nothing points). The saved route stays saved.
function NG:Clear()
  if Panoply:GuideUnavailable() then return end   -- 0.9.7: there is no route to stop, and the card already says the guide is not available
  if Panoply.Hub and Panoply.Hub:Holds() then return end   -- Hub phase 1: a plan sent from Panoply Hub is followed here too
  local P, E = Panoply.Planner, Panoply.Engine
  if P then
    if P.job then P.job = nil if P.driver then P.driver:Hide() end end
    P.actions, P.hash, P.planSet = {}, nil, {}
  end
  if E then
    E.detour, E.travel = nil, nil
    E:SetSteps({}, "No guide here")
  end
  if Panoply.Route and Panoply.Route.Stop then pcall(Panoply.Route.Stop, Panoply.Route) end
  if Panoply.Arrow and Panoply.Arrow.Retarget then pcall(Panoply.Arrow.Retarget, Panoply.Arrow) end
end

-- Leaving for a zone with data. Nothing synchronous and nothing that offers to drop quests: the saved route comes back when there is one
-- (the ordinary re-plan check then decides whether it still fits), else an automatic, sliced, out-of-combat plan (Panoply:ResumeReplan).
function NG:Resume()
  if Panoply:GuideUnavailable() then return end   -- 0.9.7 (Nov 18 2026): no guide engine, and no old route in its place to bring back
  if not (Panoply.cdb and Panoply.cdb.setupDone and Panoply.QuestData:Available()) or (Panoply.PlayAlong and Panoply:PlayAlong()) then return end
  if Panoply.Hub and Panoply.Hub:Holds() then return end   -- Hub phase 1: the Panoply Hub plan is still the route; nothing to bring back
  -- (Nov 11 2026: with the planner off, only a follower on a Panoply Hub plan the leader shared waits for it again; a written guide comes
  -- back below, the leader's when the two of you are in step, Engine/Sync.lua)
  local Y = Panoply.Sync
  if Y and Y.IsFollower and Y:IsFollower() and (Panoply.Guides.PlannerOn() or Y:HoldsSharedRoute()) then
    -- the party leader's route is asked for again (CheckRoute, at the partner's next state)
    for who, st in pairs(Panoply.Sync.partners or {}) do
      st.badHash = nil
      if Panoply.Sync.CheckRoute then pcall(Panoply.Sync.CheckRoute, Panoply.Sync, who, st) end
    end
    return
  end
  local saved = Panoply.cdb.plan
  -- (Nov 11 2026: a saved planner route is not a route any more; only a Hub plan the leader shared comes back this way)
  local actionsOK = Panoply.Planner:BuildsLevelingRoute() or (saved and saved.sharedKind == "hub")
  if actionsOK and saved and saved.actions and #saved.actions > 0 and (saved.flavor or "forever") == C.Flavor() then
    Panoply.Engine.index = Panoply.cdb.stepIndex or 1
    Panoply.Planner:Adopt(saved.actions, saved.title or "Saved plan", "saved", true)
    Panoply:CheckReplan("zone")
    return
  end
  Panoply:ResumeReplan("left the no-guide area")
end

local function commit(self, cand)
  local was = self.area
  self.area, self.pend = cand or nil, nil
  self.init = true
  if cand then
    if not was then self:Clear() end   -- entering; moving between two no-guide zones needs nothing more
    if self:Recording() then self:HookRecorder() local FR = Panoply.QuestRecorder if FR and FR.Queue then FR:Queue() end end
  elseif was then
    local ok, err = pcall(self.Resume, self)
    if not ok then Panoply:Debug("no-guide resume", err) end
  end
  if (cand or was) then   -- (the first judgement of a guided character changes nothing for a partner)
    if Panoply.Sync and Panoply.Sync.SendState then pcall(Panoply.Sync.SendState, Panoply.Sync) end   -- a partner learns that this side shares no route (or does again)
    Panoply:Fire("NOGUIDE_CHANGED")
  end
end

-- Judge the place now. The first judgement (login) and the player's own switch count at once; any other change only after it has held
-- for NG.HYSTERESIS_S seconds. Returns whether the area is a no-guide area.
function NG:Update(force)
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return false end   -- PanoplyGuide's guides decide (WoW Forever)
  local cand = self:Candidate()
  if cand == "hold" then self.pend = nil return self:Active() end
  local cur = self.area
  local sig = cand and (cand.key .. ":" .. cand.reason) or "-"
  local csig = cur and (cur.key .. ":" .. cur.reason) or "-"
  if sig == csig and self.init then
    self.pend = nil
    if cur then cur.name = cand.name or cur.name end
    return self:Active()
  end
  local now = C.GetTime() or 0
  if force or not self.init then commit(self, cand) return self:Active() end
  if not self.pend or self.pend.sig ~= sig then self.pend = { sig = sig, t = now } end
  if now - self.pend.t >= NG.HYSTERESIS_S then commit(self, cand) end
  return self:Active()
end

-- Hub phase 1: while a plan sent from Panoply Hub is the route (Engine/Hub.lua), the guide runs here as anywhere: the player
-- sent that plan for this character on purpose. NG:Active (the area itself, and with it Record mode) is unchanged.
function Panoply:NoGuideHere()
  -- WoW Forever with PanoplyGuide's engine: PanoplyGuide knows where its guides reach; ours is not the judge there
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return false end
  return Panoply.NoGuide ~= nil and Panoply.NoGuide:Active() and not (Panoply.Hub ~= nil and Panoply.Hub:Holds())
end

-- /panoply noguide [status | record on|off | off | on]
function NG:Slash(args)
  local sub = (args[2] or ""):lower()
  local lines
  self:Update()
  if sub == "record" then
    local v = (args[3] or ""):lower()
    if not self.area then lines = { "This area has a guide, so record mode is not in use here." }
    elseif v == "on" or v == "off" then
      self:SetRecording(v == "on")
      lines = { "Record mode is " .. v .. " in " .. tostring(self.area.name) .. "." }
    else lines = { "Usage: /panoply noguide record on | off" } end
  elseif sub == "off" or sub == "on" then
    local a = self.area
    if sub == "off" and not a then
      local S = Panoply.State
      local _, key, name = self:Judge(S.pos and S.pos.map, S.zone)
      if not key then lines = { "Panoply Suite cannot tell which zone you are in right now." }
      else
        local s = store(true)
        s.off[key] = true
        self:Update(true)
        Panoply:Fire("NOGUIDE_CHANGED")
        lines = { "Guide is off in " .. tostring(name) .. ". /panoply noguide on brings it back." }
      end
    elseif sub == "on" and a and self:GuideOff() then
      self:SetGuideOff(false)
      lines = { "Guide is back on in this zone." .. (self.area and " (There is no guide data for it yet.)" or "") }
    else
      lines = { sub == "off" and "The guide is already off here." or "The guide is not switched off in this zone." }
    end
  else
    local a = self.area
    if a then lines = { self:Text(), (a.name or "") .. ": record mode " .. (self:Recording() and "on" or "off") .. ", guide switched off here: " .. (self:GuideOff() and "yes" or "no") .. "." }
    else lines = { "This area has a guide. /panoply noguide off turns the guide off in this zone." } end
  end
  for _, l in ipairs(lines) do Panoply:Print(l) end
  return lines
end
