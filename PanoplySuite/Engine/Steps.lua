-- Panoply Suite Steps: live game state snapshot + step/goal model + auto-advancing engine.
local ADDON, Panoply = ...
local C, U = Panoply.Compat, Panoply.Util

-------------------------------------------------------------------------------
-- State snapshot (everything goal checks need; refreshed by events)
-------------------------------------------------------------------------------
local State = { completed = {}, log = {}, skills = {}, skillMax = {}, objectives = {} }
Panoply.State = State

function State:RefreshCompleted()
  self.completed = C.GetAllCompleted()
end

function State:RefreshLog()
  local log = {}
  for _, q in ipairs(C.IterQuestLog()) do log[q.questID] = q end
  self.log = log
  self.objectives = {}
end

function State:RefreshSkills()
  local skills, maxes = {}, {}
  local PD = Panoply.ProfData
  for _, s in ipairs(C.GetSkills()) do
    local line = s.skillLineID or (PD and PD.SKILL_LINES and PD.SKILL_LINES[s.name])
    if s.name then skills[s.name] = s.rank or 0; maxes[s.name] = s.max or 0 end
    if line then skills[line] = s.rank or 0; maxes[line] = s.max or 0 end
  end
  self.skills, self.skillMax = skills, maxes
end

function State:RefreshPlayer()
  self.level, self.xp, self.xpMax = C.XP()
  -- PLAYER_LEVEL_UP carries the new level before UnitLevel("player") catches up
  if self.pendingLevel then
    if self.pendingLevel > (self.level or 1) then self.level = self.pendingLevel else self.pendingLevel = nil end
  end
  self.zone, self.subzone = C.ZoneText()
  self.onTaxi = C.OnTaxi()
  local m, x, y = C.GetPlayerPos()
  self.pos = m and { map = m, x = x, y = y } or nil
end

function State:RefreshAll()
  self:RefreshCompleted(); self:RefreshLog(); self:RefreshSkills(); self:RefreshPlayer()
  self.bind = C.BindLocation()
end

function State:Objectives(questID)
  local o = self.objectives[questID]
  if not o then o = C.GetObjectives(questID); self.objectives[questID] = o end
  return o
end

function State:IsCompleted(q) return self.completed[q] == true end
function State:InLog(q) return self.log[q] ~= nil end

-------------------------------------------------------------------------------
-- Goals
-------------------------------------------------------------------------------
local Goals = {}
Panoply.Goals = Goals
Goals.DEFAULT_RADIUS = 10   -- yards

local DONE, TODO, HIDDEN = "done", "todo", "hidden"
Goals.DONE, Goals.TODO, Goals.HIDDEN = DONE, TODO, HIDDEN

-- How many of an item a quest asks for, from our own quest data (nil when it does not say)
function Goals.ItemsNeeded(questID, itemID)
  local QD = Panoply.QuestData
  local rec = QD and QD.Available and QD:Available() and QD:GetQuest(questID)
  local items = rec and rec.objectives and rec.objectives.items
  for _, it in ipairs(items or {}) do if it[1] == itemID and (it[2] or 0) > 0 then return it[2] end end
  return nil
end

-- The game's objective line for this quest that names this part ("Felix's Chest: 0/1", "Frostmane Troll Whelp slain: 3/10")
function Goals.ObjectiveNamed(s, questID, name)
  if type(name) ~= "string" or name == "" then return nil end
  for _, o in ipairs(s:Objectives(questID)) do
    if type(o.text) == "string" and o.text:find(name, 1, true) then return o end
  end
  return nil
end

Goals.eval = {
  accept = function(g, s) return (s:InLog(g.questID) or s:IsCompleted(g.questID)) and DONE or TODO end,
  turnin = function(g, s) return (s:IsCompleted(g.questID) and not s:InLog(g.questID)) and DONE or TODO end,
  complete = function(g, s)
    if s:IsCompleted(g.questID) then return DONE end
    local q = s.log[g.questID]
    if q and q.isComplete then return DONE end
    return TODO
  end,
  objective = function(g, s)
    if s:IsCompleted(g.questID) then return DONE end
    if not s:InLog(g.questID) then return TODO end
    -- After 0.8.2: a quest the game calls complete has every objective done. Forever-only quests often list no objective at
    -- the guide's index (or none at all), which left the kill pin on the step after the kills were finished.
    local e = s.log[g.questID]
    if e and e.isComplete then return DONE end
    if g.objIndex then
      local o = s:Objectives(g.questID)[g.objIndex]
      if o and (o.finished or (o.numRequired > 0 and o.numFulfilled >= o.numRequired)) then return DONE end
      return TODO
    end
    -- Nov 12 2026: a goal Polestar names by its item or creature (no objective number) is done when THAT part is: the item in the
    -- bags, as many as the quest asks for, or the game's own objective line that names it finished. Never objective 1's state.
    if g.itemID and C.ItemCount(g.itemID) >= (g.count or Goals.ItemsNeeded(g.questID, g.itemID) or 1) then return DONE end
    local o = Goals.ObjectiveNamed(s, g.questID, g.partName)
    if not o then   -- a quest with one objective line: that line is this part, whatever it is called
      local all = s:Objectives(g.questID)
      if #all == 1 then o = all[1] end
    end
    if o and (o.finished or (o.numRequired > 0 and o.numFulfilled >= o.numRequired)) then return DONE end
    return TODO
  end,
  ["goto"] = function(g, s)
    -- Nov 13 2026 (play-through, Undead: Gordo's road): a spot once reached stays reached. It counted only while the player stood on
    -- it, so with several spots in a row (a road to walk) the arrow swung back to the first one as soon as the player walked on.
    if g.reached then return DONE end
    if s.onTaxi or not s.pos or not g.mapID then return TODO end
    local d = Panoply.Nav.Distance(s.pos.map, s.pos.x, s.pos.y, g.mapID, g.x, g.y)
    if d and d <= (g.radius or Goals.DEFAULT_RADIUS) then g.reached = true return DONE end
    return TODO
  end,
  collect = function(g, s) return (C.ItemCount(g.itemID, g.bank) >= (g.count or 1)) and DONE or TODO end,
  level = function(g, s)
    local lvl = s.level or 1
    if lvl > g.level then return DONE end
    if lvl == g.level and (g.xp or 0) <= (s.xp or 0) then return DONE end
    return TODO
  end,
  skill = function(g, s)
    local r = s.skills[g.skillLine] or s.skills[g.skillName] or 0
    return r >= (g.skill or 1) and DONE or TODO
  end,
  learn = function(g, s)
    if g.spellID then local k = C.KnowsSpell(g.spellID) if k then return DONE end end
    if g.skillLine or g.skillName then
      local r = s.skills[g.skillLine] or s.skills[g.skillName]
      if r and r > 0 and not g.spellID then return DONE end
    end
    return g.confirmed and DONE or TODO
  end,
  fpath = function(g, s) return (Panoply.cdb and Panoply.cdb.knownTaxi[g.node]) and DONE or TODO end,
  fly = function(g, s)
    if s.onTaxi then return TODO end
    if g.zone and (s.zone == g.zone or s.subzone == g.zone) then return DONE end
    return g.confirmed and DONE or TODO
  end,
  hearth = function(g, s) return (g.zone and (s.zone == g.zone or s.subzone == g.zone)) and DONE or TODO end,
  sethome = function(g, s) return (s.bind and s.bind == g.inn) and DONE or TODO end,
  confirm = function(g) return g.confirmed and DONE or TODO end,
  talk = function(g) return g.confirmed and DONE or TODO end,
  -- a dungeon boss (Engine/Dungeon.lua): done once the run has it ticked (a death seen, a quest that needed it, or the player's own tick)
  boss = function(g) return (Panoply.Dungeon and Panoply.Dungeon:BossDone(g.boss)) and DONE or TODO end,
}
Goals.eval.kill = Goals.eval.objective
Goals.eval.buy = Goals.eval.collect

-- 0.5.8: goals about a quest that is too hard right now (red, or an elite above level + 2;
-- the lower partner's level in partner mode) are deferred: hidden until a level-up makes them safe.
Goals.DEFERRABLE = { accept = true, complete = true, objective = true, kill = true, turnin = true }

-- Nov 13 2026 ("the guide never asks to finish a quest it didn't have you pick up"): the quest work that follows a pick-up the
-- guide moved past untaken (Engine:NoteNotTaken). Hidden until the quest is in the log; once it is (or is handed in), forgotten.
local AFTER_PICKUP = { complete = true, objective = true, turnin = true }
local function notTaken(g, s)
  local nt = Panoply.cdb and Panoply.cdb.notTaken
  local q = g.questID
  if not (nt and q and AFTER_PICKUP[g.type] and nt[q]) then return false end
  if s:InLog(q) or s:IsCompleted(q) then nt[q] = nil return false end
  return true
end
Goals.NotTaken = notTaken

function Goals.Status(g, s)
  -- WoW Forever with Polestar's engine (Engine/PolestarEngine.lua): the goal is Polestar's, and so is its state
  if g.ps then return g.status or TODO end
  if g.onlyIf and not g.onlyIf(s) then return HIDDEN end
  if notTaken(g, s) then return HIDDEN end
  -- Nov 13 2026: work for a quest the step only may start (its pick-up is optional: an item that starts it may not drop) waits for it
  if g.needsLog and g.questID and not s:InLog(g.questID) and not s:IsCompleted(g.questID) then return HIDDEN end
  local f = Goals.eval[g.type]
  if not f then return TODO end
  local ok, st = pcall(f, g, s)
  if not ok then Panoply:Debug("goal eval error", g.type, st) return TODO end
  g.deferred = nil
  if st ~= DONE and g.questID and Goals.DEFERRABLE[g.type] and Panoply.Difficulty and not g.forceRoute then
    local okD, info = pcall(Panoply.Difficulty.Defer, g.questID)
    if okD and info then g.deferred = info return HIDDEN end
  end
  return st
end

-- A step is complete when all required goals are done. Hint goals (e.g. "goto" next to an
-- accept) never block. A step made only of hints/hidden goals needs its hints.
function Goals.StepComplete(step, s)
  local required, hints, deferred = 0, 0, 0
  local allHintsDone, requiredOpen = true, false
  -- Every goal is evaluated (not just up to the first open one): hint goals such as gathering
  -- routes move the arrow even while the main goal is still to do.
  for _, g in ipairs(step.goals) do
    local st = Goals.Status(g, s)
    g.status = st
    if g.deferred then deferred = deferred + 1 end
    if st ~= HIDDEN then
      if g.hint or g.optional then
        hints = hints + 1
        if st ~= DONE then allHintsDone = false end
      else
        required = required + 1
        if st ~= DONE then requiredOpen = true end
      end
    end
  end
  -- Nov 13 2026: "Go to" pointers written before a goal that is already done were the way to it, and are passed (Undead: once Gordo's
  -- quest is taken, the arrow goes on to the Gloom Weed, not along the rest of his road). The guide's own order is kept.
  local lastDone = 0
  for i, g in ipairs(step.goals) do if g.status == DONE and not g.hint and not g.optional then lastDone = i end end
  for i = 1, lastDone - 1 do
    local g = step.goals[i]
    if g.hint and g.type == "goto" and g.status == TODO then g.status, g.reached = DONE, true end
  end
  step.deferred = nil
  if requiredOpen then return false end
  -- 0.5.8: nothing left to do here but quests that are too hard now: the step is put off
  if required == 0 and deferred > 0 then step.deferred = true return false, true end
  if required == 0 then
    if hints == 0 then return true end  -- everything hidden
    return allHintsDone
  end
  return true
end

-------------------------------------------------------------------------------
-- Engine
-------------------------------------------------------------------------------
local Engine = { steps = {}, index = 1, title = "No plan" }
Panoply.Engine = Engine

function Engine:SetSteps(steps, title, keepIndex)
  self.steps = steps or {}
  self.title = title or "Plan"
  if not keepIndex then self.index = 1 end
  if self.index > #self.steps then self.index = math.max(#self.steps, 1) end
  self.waiting = nil
  self.travel = nil
  self:FastForward()
  Panoply:Fire("STEPS_CHANGED")
end

-- 0.6.0 M5: a travel step ("Fly to X", "Take the boat to Y") comes before the levelling step when the
-- fastest way there uses it (Panoply.Travel decides; it never changes the plan itself).
-- Dungeon helper: inside a dungeon the run's own step (Engine/Dungeon.lua) is in front of everything; the levelling route stays
-- in self.steps at self.index, untouched, and is the step again the moment the player leaves or the dungeon steps are done.
function Engine:Current() return self.dungeon or self.detour or self.travel or self.steps[self.index] end
function Engine:LevelStep() return self.steps[self.index] end

-- A profession step shown in place of the levelling step (ProfGuide decides when).
function Engine:SetDetour(step)
  if Panoply:PlayAlong() or Panoply:NoGuideHere() then step = nil end   -- 0.7.1: no guide, so no profession step in it either (0.7.4.1: nor in an area without one)
  local old = self.detour
  self.detour = step
  if (old and old.key) ~= (step and step.key) then Panoply:Fire("STEP_CHANGED", self.index, "detour")
  elseif step then self:Updated() end
end

-- 0.9.5 phase 4A4 (spec 06 section 0.3): everything the STEP_UPDATED listeners show (the guide window, the arrow, the profession tracker),
-- as one string: the step in front and the levelling step with their goals' states, the next few steps, where the player is, the level
-- and XP, and the quest log, skills, completed quests and bags (each a table read again, or a counter, when the game says they changed).
-- The arrow's distance is not in it: the arrow draws that itself several times a second.
-- Panoply.bagRev goes up when the bags really changed (Modules/Bags/Store.lua compares what they hold); with the bag store off (no bags,
-- profession window or Muster module), on each finished burst of bag events instead
Panoply.bagRev = 0
Panoply:On("BAG_UPDATE_DELAYED", function() if not (Panoply.Inventory and Panoply.Inventory:Enabled()) then Panoply.bagRev = Panoply.bagRev + 1 end end)
local function stepParts(st, out)
  if type(st) ~= "table" then out[#out + 1] = "-" return end
  Panoply.Flat(st, out)
  for _, g in ipairs(type(st.goals) == "table" and st.goals or {}) do
    out[#out + 1] = "|g"
    Panoply.Flat(g, out)
    if g.itemID then out[#out + 1] = "n=" .. tostring(C.ItemCount(g.itemID, g.bank)) end
  end
end
function Engine:UpdateSig()
  local S = State
  local out = { tostring(self.index), tostring(#self.steps), tostring(self.waiting), tostring(S.level), tostring(S.xp), tostring(S.xpMax),
                tostring(S.zone), tostring(S.subzone), tostring(S.onTaxi), tostring(S.log), tostring(S.skills), tostring(S.completed),
                tostring(S.bind), tostring(Panoply.bagRev) }
  for _, st in ipairs({ self.dungeon or false, self.detour or false, self.travel or false, self.steps[self.index] or false }) do
    out[#out + 1] = "|s"
    stepParts(st or nil, out)
  end
  for i = self.index + 1, math.min(#self.steps, self.index + 4) do
    out[#out + 1] = "|u"
    Panoply.Flat(self.steps[i], out)
  end
  return table.concat(out, ";")
end
-- The step in front may have changed: tell the windows, unless nothing they show did.
function Engine:Updated()
  local ok, sig = pcall(self.UpdateSig, self)
  if not ok then Panoply:Debug("step signature", sig) sig = nil end
  return Panoply:FireChanged("STEP_UPDATED", sig)
end

-- Target point for arrow: first unfinished goal with coordinates, else step coordinates.
function Engine:Target(step)
  if not step and Panoply:PlayAlong() then return nil end   -- 0.7.1: no guide target; waypoints still work
  step = step or self:Current()
  -- Polestar's step (or its travel step): the guide's target is where Polestar's own waypoint is
  if step and step.ps then return Panoply.PolestarEngine:Target() end
  if step and self.detour == step then Goals.StepComplete(step, State) end
  if not step then return nil end
  if step.isDungeon then return nil end   -- nothing inside an instance has a spot the arrow could point at (no player position there)
  local stale = false   -- a goal that supplied the step's own coordinates is already done
  local anyShown = false   -- Nov 13 2026: a step none of whose goals is for this character has no point of its own either
  for _, g in ipairs(step.goals) do
    if g.status ~= HIDDEN then anyShown = true end
    -- Nov 13 2026 (play-through, Skyborne: "Accept The Fate of Zephras" has no map spot, so the arrow went on to Talaanis, the quest's
    -- objective, before the quest was taken): work for a quest that is not in the log cannot count yet, so the arrow never points at
    -- it. The pick-up comes first; when it has no spot either, the step says so (StepText.NoSpotNote).
    local notYet = AFTER_PICKUP[g.type] and g.questID and not g.direct and not State:InLog(g.questID) and not State:IsCompleted(g.questID)
    if notYet then
      -- nothing to point at for this goal; and when it is the goal the step's own point was taken from, that point is not one either
      -- (Nov 13 2026, Polestar 0.3.7.2 Skyborne "The Al'Aketh camp": the step's point was the item of a quest still to be taken)
      if g.mapID and g.mapID == step.mapID and g.x == step.x and g.y == step.y then stale = true end
    elseif g.mapID and g.status ~= DONE and g.status ~= HIDDEN then
      -- indoor target, you outside: the building's entrance first when we know it
      local L = Panoply.Locations
      if L then
        local em, ex, ey, el = L:EntranceFor(step, g.mapID, g.x, g.y)
        if em then return em, ex, ey, el end
      end
      return g.mapID, g.x, g.y, g.text
    elseif not g.mapID and g.questID and g.status ~= DONE and g.status ~= HIDDEN and not g.hint then
      -- After 0.8.2: an unfinished quest goal our data cannot place (a Forever quest, a turn-in with no known
      -- spot) asks the game where it points. Only a quest in the log has a waypoint; a turn-in only once complete.
      local e = State.log[g.questID]
      if e and (g.type ~= "turnin" or e.isComplete) then
        local wm, wx, wy = C.QuestWaypoint(g.questID)
        if wm then return wm, wx, wy, g.text end
      end
    elseif g.mapID and g.status == DONE and g.mapID == step.mapID and g.x == step.x and g.y == step.y then
      stale = true
    end
  end
  -- The step's own point is its first goal's. Once that goal is done it is a stale pin (the kill spot of a
  -- finished quest), never a place to send the player for the hand-ins that follow.
  -- (Nov 13 2026, Polestar 0.3.7.2 Teldrassil ends on a "Fishers only" step: a character without Fishing was pointed 3800 yd away at
  -- Gubber Blump while the window said "Plan complete!")
  if step.mapID and not stale and anyShown then return step.mapID, step.x, step.y, step.title end
  return nil
end

-- The guide's own target (the profession detour or the levelling step), never a travel step:
-- the route is planned to this, and the travel step is made from that route.
function Engine:GuideTarget()
  if self.dungeon then return nil end   -- inside a dungeon the route waits; no trip is planned from in there
  local step = self.detour or self.steps[self.index]
  if not step then return nil end
  return self:Target(step)
end

function Engine:Goto(i, reason)
  if i < 1 then i = 1 end
  if i > #self.steps then i = #self.steps end
  if i == self.index then return end
  self.index = i
  self.waiting = nil
  self.travel = nil
  if Panoply.cdb then Panoply.cdb.stepIndex = i end
  Panoply:Fire("STEP_CHANGED", i, reason)
end

function Engine:Next()
  if self.dungeon and Panoply.Dungeon then Panoply.Dungeon:Skip() return end
  if self.travel and not self.detour and Panoply.Travel then Panoply.Travel:Dismiss("skip") return end
  if self.detour and Panoply.ProfGuide then Panoply.ProfGuide:Snooze(self.detour) return end
  local cur = self.steps[self.index]
  if cur and cur.ps then Panoply.PolestarEngine:Skip() return end   -- Polestar's step: Polestar skips it (and remembers)
  self:NoteNotTaken(self.steps[self.index])
  self:Goto(self.index + 1, "manual")
end
function Engine:Prev()
  if self.dungeon and Panoply.Dungeon then Panoply.Dungeon:Back() return end
  if self.detour then return end
  local cur = self.steps[self.index]
  if cur and cur.ps then Panoply.PolestarEngine:Back() return end
  self:Goto(self.index - 1, "manual")
end

function Engine:IsComplete(i)
  local step = self.steps[i]
  return step and Goals.StepComplete(step, State) or false
end

-- 0.5.8: complete, or put off because its quests are too hard right now (then also remembered).
function Engine:Passable(i)
  local step = self.steps[i]
  if not step then return false end
  local done, deferred = Goals.StepComplete(step, State)
  if deferred then self:NoteDeferred(step) end
  return done or deferred or false, deferred
end

-- Nov 13 2026: the player moves on from a step (it was done, put off as too hard, or skipped) while one of its pick-ups was never
-- taken (not in the log, not handed in): that quest is remembered for this character, so the guide never asks later to finish it,
-- get its items or kills, or hand it in (Goals.Status). Called only when the route moves on in play (Check, Next, FastForward), never
-- when a route is set or restored at login, so a quest log the game has not sent yet cannot mark anything.
function Engine:NoteNotTaken(step)
  local nt = Panoply.cdb and Panoply.cdb.notTaken
  if not (nt and step and step.goals) then return end
  for _, g in ipairs(step.goals) do
    local q = g.questID
    if g.type == "accept" and q and not State:InLog(q) and not State:IsCompleted(q) then nt[q] = true end
  end
end

-- Deferred quests: { [questID] = { name =, info = } }. Kept until a level-up makes them safe.
Engine.deferred = {}
function Engine:NoteDeferred(step)
  for _, g in ipairs(step.goals or {}) do
    if g.deferred and g.questID and not self.deferred[g.questID] then
      local q = Panoply.QuestData and Panoply.QuestData:GetQuest(g.questID)
      local e = State.log[g.questID]
      local name = (q and q.name) or (e and e.title) or "a quest"
      self.deferred[g.questID] = { name = name, info = g.deferred }
      if Panoply.Difficulty and Panoply.Print then Panoply:Print(Panoply.Difficulty.Explain(g.questID, name, g.deferred)) end
      Panoply:Fire("QUEST_DEFERRED", g.questID)
    end
  end
end

-- Called on level-up (yours or your partner's): quests that are safe now come back.
-- Returns the list of quest ids that came back.
function Engine:ReviewDeferred()
  local back, seen = {}, {}
  local function review(id)
    if seen[id] then return end
    seen[id] = true
    if State.completed[id] then self.deferred[id] = nil return end
    local okD, info = pcall(Panoply.Difficulty.Defer, id)
    if okD and not info then back[#back + 1] = id; self.deferred[id] = nil end
  end
  for id in pairs(self.deferred) do review(id) end
  -- quests the planner itself had to leave for later (in your log, too hard for the whole stretch)
  for _, d in ipairs((Panoply.Planner and Panoply.Planner.deferred) or {}) do if State.log[d.questID] then review(d.questID) end end
  table.sort(back)
  return back
end

-- Skip over already-completed steps (load / re-plan / after turning things in).
function Engine:FastForward()
  local n = 0
  while self.index < #self.steps and self:Passable(self.index) and n < 500 do
    self:NoteNotTaken(self.steps[self.index])
    self.index = self.index + 1
    n = n + 1
  end
  if n > 0 then
    self.travel = nil
    if Panoply.cdb then Panoply.cdb.stepIndex = self.index end
    Panoply:Fire("STEP_CHANGED", self.index, "fastforward")
  end
  return n
end

-- Called by events and a 1s safety ticker.
function Engine:Check()
  if Panoply:PlayAlong() then return end   -- 0.7.1: no guide steps to check
  -- Dungeon helper: while the run's steps are up, the levelling route (and a profession step) waits where it is
  if Panoply.Dungeon and Panoply.Dungeon:Tick() then return end
  local d = self.detour
  if d then
    if Goals.StepComplete(d, State) then
      self.detour = nil
      if Panoply.db and Panoply.db.soundOnStep and _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
        pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
      end
      if Panoply.ProfGuide then Panoply.ProfGuide:Refresh("done") end
      Panoply:Fire("STEP_DONE", "prof", d)
    else
      self:Updated()
    end
  end
  -- While the profession guide is active the route waits where it is; switching back resumes
  -- there (and catches up with anything already finished).
  if d and Panoply.ProfGuide and Panoply.ProfGuide:Active() == "professions" then return end
  -- WoW Forever with Polestar's engine: Polestar decides what is done and moves the guide on; we only take its step over again
  local PE = Panoply.PolestarEngine
  if PE and PE:Active() then PE:Check() return end
  local step = self.steps[self.index]
  if not step then return end
  local complete, deferred = Goals.StepComplete(step, State)
  if deferred then
    -- 0.5.8: too hard right now: move on quietly (no "step done" toast); it comes back on level-up
    self:NoteDeferred(step)
    self.waiting = nil
    if self.index < #self.steps then self:NoteNotTaken(step); self:Goto(self.index + 1, "deferred"); self:FastForward()
    else self:Updated() end
    return
  end
  if not complete then
    self.waiting = nil
    if not d then self:Updated() end
    return
  end
  Panoply:Fire("STEP_DONE", self.index)
  if self.index >= #self.steps then Panoply:Fire("PLAN_FINISHED") return end
  -- Sync gate (wait for partner on the same step)
  if Panoply.Sync and not Panoply.Sync:ClearToAdvance(self.index) then
    if not self.waiting then self.waiting = true; Panoply:Fire("STEP_UPDATED") end
    return
  end
  self.waiting = nil
  if Panoply.db and Panoply.db.soundOnStep and _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
    pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
  end
  self:NoteNotTaken(step)
  self:Goto(self.index + 1, "auto")
  self:FastForward()
end

-- Mark a confirm/talk goal on the current step as done (button click).
function Engine:ConfirmCurrent()
  local step = self:Current()
  if not step then return end
  if step.isDungeon and Panoply.Dungeon then Panoply.Dungeon:Confirm(step) return end
  if step.isProf and Panoply.ProfGuide then Panoply.ProfGuide:Confirm(step) return end
  if step.isTravel and Panoply.Travel then Panoply.Travel:Dismiss("done") return end
  if step.ps then Panoply.PolestarEngine:Confirm(step) return end
  for _, g in ipairs(step.goals) do
    if g.type == "confirm" or g.type == "talk" or g.type == "learn" or g.type == "fly" then g.confirmed = true end
  end
  self:Check()
end

-- Insert extra steps (e.g. profession steps) right after the current step.
function Engine:InsertSteps(list)
  local at = math.min(self.index + 1, #self.steps + 1)
  for i, s in ipairs(list) do table.insert(self.steps, at + i - 1, s) end
  Panoply:Fire("STEPS_CHANGED")
end
