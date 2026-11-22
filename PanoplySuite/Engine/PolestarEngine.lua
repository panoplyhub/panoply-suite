-- Panoply Suite: the Polestar engine adapter (WoW Forever only). Own code; it calls Polestar, it does not copy it.
--
-- On WoW Forever the leveling guide, the walking routes, the arrow's target and the travel plan come from Polestar
-- (bundled inside this folder since 0.9.5, its content unchanged except what Polestar/PANOPLY-CHANGES.md lists: Polestar/<its folders>, run by Core/Bundle.lua; GPL-3.0, see
-- NOTICE.md). Polestar keeps running as it is; this file only
--   * keeps Polestar's own windows, arrow, map drawings and buttons hidden, through Polestar's own switch (Polestar.SetHidden,
--     its "Hiding Polestar" contract: the engine, the navigation and the quest automation run on while nothing of it shows);
--   * reads the step Polestar is on (Polestar.Engine.GetStepView) and hands it to Panoply's guide window as one of our steps;
--   * reads where Polestar's arrow would point (Polestar.Nav.Sample) for our arrow;
--   * reads Polestar's travel plan and walking line (Polestar.Nav.GetRoute / GetRouteGeometry) as one of our routes, so our
--     map trail, trip strip and travel steps draw it;
--   * passes Back, Skip, "I've done it" and the guide's questions (next zone, group quest, a quest that left the log) on.
-- 0.9.7 (Nov 18 2026): Panoply Suite is for WoW Forever only, and this is its one levelling guide engine. When Polestar is
-- not loaded, or lacks a part this file calls, nothing takes its place: the guide card says "Guide not available"
-- (Core/Init.lua Panoply:GuideUnavailable) and the old planner and converted guides do not run.
local ADDON, Panoply = ...
local C = Panoply.Compat
local PS = {}
Panoply.PolestarEngine = PS
local floor, sqrt, pi = math.floor, math.sqrt, math.pi

PS.TESTED = "0.4.2.1"           -- the Polestar release this adapter was written and tested against (tools/update_polestar_engine.py)
PS.OWNER = "PanoplySuite"        -- our name for Polestar.Nav.API (a spot picked by hand in Panoply is routed by Polestar too)
PS.LEVELING_PACK = "guides"      -- Polestar's own guide pack
PS.ADDED_PACK = "panoply"        -- the pack id a guide added from outside registers under (a Polestar guide pack; none ships yet)
PS.SOURCES = { "leveling", "added" }
PS.SOURCE_NAMES = { leveling = "Leveling guide", added = "Added guide" }
PS.UPCOMING = 4                  -- the steps listed under "Up next"
PS.SCAN = 40                     -- how far ahead "Up next" looks for steps this character has
PS.NO_ADDED = "No added guide is on this computer yet. The leveling guide stays on."

-- What the adapter needs from Polestar. A release that lacks one of these is not driven: the guide is "not available" then
-- (0.9.7: nothing runs in its place), and /panoply polestar says which part is missing.
local NEEDS = {
  { "SetHidden" }, { "Hidden" }, { "On" }, { "Get" }, { "Set" },
  { "Engine", "GetGuide" }, { "Engine", "GetStepIndex" }, { "Engine", "GetLiveStep" }, { "Engine", "GetStepView" },
  { "Engine", "StepNumber" }, { "Engine", "StepTotal" }, { "Engine", "Next" }, { "Engine", "Prev" }, { "Engine", "Skip" },
  { "Engine", "ToggleGoal" }, { "Engine", "GetWaypoint" },
  { "Nav", "GetTarget" }, { "Nav", "Sample" }, { "Nav", "GetRoute" }, { "Nav", "LiveCoords" },
  { "Compat", "MapToWorld" },
}

local function P() return rawget(_G, "Polestar") end
PS.P = P

-- nil when Polestar has everything the adapter calls, else the name of the first part that is missing
function PS:Missing()
  local p = P()
  if type(p) ~= "table" then return "Polestar is not loaded" end
  for _, path in ipairs(NEEDS) do
    local v = p
    for _, k in ipairs(path) do v = type(v) == "table" and v[k] or nil end
    if type(v) ~= "function" then return "Polestar." .. table.concat(path, ".") end
  end
  return nil
end

function PS:Present()
  return C.Flavor() == "forever" and self:Missing() == nil
end

-- Panoply's guide is drawn from Polestar: on WoW Forever, Polestar loaded and started
function PS:Active()
  return self.on == true
end

-- True when the guide engine cannot run on WoW Forever and nothing takes its place: the windows then say "Guide not available"
-- (Core/Init.lua Panoply:GuideUnavailable is the one rule; UI/MainFrame.lua asks here).
function PS:Unavailable()
  return C.Flavor() == "forever" and Panoply:GuideUnavailable() and true or false
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f = pcall(fn, ...)
  if not ok then Panoply:Debug("polestar call", a) return nil end
  return a, b, c, d, e, f
end

-------------------------------------------------------------------------------
-- Polestar's own windows stay hidden, and the settings of its that clash with ours follow ours
-------------------------------------------------------------------------------
-- Polestar's settings the adapter sets (through Polestar.Set, as its own options window would). The value each had before is kept
-- in PanoplySuiteDB.polestarKept, so PS:Unmanage puts every one back exactly.
local NILVAL = "\0nil"
function PS:Manage(path, value)
  local p = P()
  if not (p and Panoply.db) then return end
  local now = call(p.Get, path)
  if now == value then return end
  Panoply.db.polestarKept = Panoply.db.polestarKept or {}
  local kept = Panoply.db.polestarKept
  if kept[path] == nil then
    local own = p.DB and call(p.DB)
    local node = own and own.settings
    for key in path:gmatch("[^.]+") do node = type(node) == "table" and node[key] or nil end
    kept[path] = node == nil and NILVAL or node
  end
  call(p.Set, path, value)
end

function PS:Unmanage()
  -- the engine's guild times go back with its settings (Engine/PolestarParty.lua holds them while Panoply runs it)
  local PP = Panoply.PolestarParty
  if PP and PP.Unpin then PP:Unpin() end
  local p = P()
  local kept = Panoply.db and Panoply.db.polestarKept
  if not (p and kept) then return 0 end
  local n = 0
  for path, v in pairs(kept) do
    local old = v
    if old == NILVAL then old = call(p.GetDefault, path) end
    call(p.Set, path, old)
    n = n + 1
  end
  Panoply.db.polestarKept = nil
  return n
end

-- Nov 14 2026 (0.9.4 fix round 17-22, review B2): Polestar's own helpers that ACT for the player (they keep running while its windows
-- are hidden) are switched off at every login, so the one that acts is Panoply's, with Panoply's switches, never-sell list and Shift key:
--   behavior.autoAccept, behavior.autoTurnin   Panoply: Engine/Automation.lua (quest accept and hand-in)
--   qol.sellJunk, qol.autoRepair, qol.repairGuild   Panoply: Modules/Merchant (Sell grey items, Repair for me, guild bank), never-sell list
--   qol.buyGoals                               buys what a step needs with the player's gold (Panoply has no such thing: its Restock buys only
--                                              the list the player made, and is off until turned on); it spends gold, so it is off
--   qol.fastLoot                               Panoply: Modules/Merchant/Restock.lua (Faster auto loot, off until turned on)
-- logs/094/fix-round-17-22.md lists every other Polestar automation, its default and who governs it.
PS.AUTOMATION_OFF = { "behavior.autoAccept", "behavior.autoTurnin", "qol.sellJunk", "qol.autoRepair", "qol.repairGuild", "qol.buyGoals", "qol.fastLoot" }

-- Polestar has the settings table and its Get / Set: enough to switch an automation off, whether or not the rest of what the adapter
-- drives is there (a Polestar release that lacks another function still must not sell, repair or tell the party on its own)
function PS:CanSet()
  local p = P()
  return C.Flavor() == "forever" and type(p) == "table" and type(p.Get) == "function" and type(p.Set) == "function" and Panoply.db ~= nil
end

function PS:ApplyAutomation()
  if not self:CanSet() then return false end
  for _, path in ipairs(self.AUTOMATION_OFF) do self:Manage(path, false) end
  -- Nov 14 2026 (0.9.4 step 21): what is told to the party about quest progress is Panoply Suite's own setting, off unless turned on
  -- (Engine/PolestarVoice.lua); Polestar has it on
  if Panoply.PolestarVoice then Panoply.PolestarVoice:ApplyParty() end
  return true
end

function PS:ApplySettings()
  -- its minimap button, its floating button (off by default; a player who came from Polestar may have it on) and its button in the
  -- game menu are ways to show Polestar's own windows
  self:Manage("maps.minimapButton", false)
  self:Manage("ui.launcher", false)
  self:Manage("ui.gameMenuButton", false)
  -- one automatic quest accept and hand-in, one seller, one repairer: Panoply's own stays the one that acts
  self:ApplyAutomation()
  self:ApplyGroupQuests()
end

-- 0.9.7 (Nov 18 2026): "Group quests" (PanoplySuiteDB.groupQuests: "ask" | "do" | "skip", Engine/Difficulty.lua) is Polestar's
-- own behavior.groupQuests, set through PS:Manage at login and whenever our setting changes, so the value the player had in
-- Polestar is kept and PS:Unmanage puts it back. Polestar itself keeps each answer the player gave for one quest
-- (Engine.AnswerGroup, per character) and asks its setting only for a quest never answered, so an answered quest keeps its answer.
PS.GROUP_QUESTS_PATH = "behavior.groupQuests"
function PS:ApplyGroupQuests()
  if not self:CanSet() then return false end
  local D = Panoply.Difficulty
  self:Manage(self.GROUP_QUESTS_PATH, D.GroupQuests())
  return true
end

function PS:Hide()
  local p = P()
  if not p then return end
  if p.SetHideKeepsArrow and p.HideKeepsArrow and call(p.HideKeepsArrow) then call(p.SetHideKeepsArrow, false) end
  if not call(p.Hidden) then call(p.SetHidden, true) end
end

-------------------------------------------------------------------------------
-- Start (once per login) and Polestar's messages
-------------------------------------------------------------------------------
PS.MESSAGES = { "GUIDE_CHANGED", "STEP_CHANGED", "STEP_UPDATED", "WAYPOINT_CHANGED", "GUIDE_END", "GUIDE_CONTINUED", "GUIDE_COMPLETED",
                "GUIDES_REGISTERED", "ROUTE_CHOICE", "ROUTE_CHOSEN", "PLAYER_SKIPPED_STEP", "TABS_CHANGED" }
PS.ROUTE_MESSAGES = { "ROUTE_CHANGED", "ROUTE_ADVANCED", "NAV_ROUTE_GEOMETRY" }

function PS:OnLogin()
  self.on = false
  if not self:Present() then
    if C.Flavor() == "forever" and P() then
      Panoply:Debug("polestar adapter off:", self:Missing())
      -- the adapter is not driving this Polestar, but Polestar still runs: its sell, repair, loot and party helpers are switched off
      -- all the same (Backlog 6 of the 17-22 review: the party chat lock must not depend on the adapter starting)
      self:ApplyAutomation()
    end
    return false
  end
  local p = P()
  if Panoply.PolestarVoice and Panoply.PolestarVoice.installedFor ~= p then Panoply.PolestarVoice:Install() end   -- what Polestar says, in Panoply's voice
  if self.listening ~= p then
    self.listening = p
    for _, msg in ipairs(self.MESSAGES) do
      p.On(msg, function() if PS.on then PS:Changed(msg) end end)
    end
    for _, msg in ipairs(self.ROUTE_MESSAGES) do
      p.On(msg, function() if PS.on then PS:SyncRoute(msg) end end)
    end
    -- anything that shows Polestar again (its slash command, a key binding) is undone: its own windows stay hidden
    p.On("POLESTAR_HIDDEN", function(hidden)
      if PS.on and not hidden and not PS.hiding then
        PS.hiding = true
        PS:Hide()
        PS.hiding = nil
        if not PS.saidHidden then
          PS.saidHidden = true
          -- Nov 14 2026 (step 21): never the engine's name; the one chat line says what the player sees
          Panoply:Print("The guide's other windows stay hidden: Panoply Suite shows its guide, arrow and route in its own windows.")
        end
      end
    end)
  end
  self.on = true
  self:Hide()
  self:ApplySettings()
  self.version = type(p.version) == "string" and p.version or "?"
  if self.version ~= self.TESTED then Panoply:Debug("polestar", self.version, "differs from the tested", self.TESTED) end
  return true
end

-- A Polestar message: the mirror is rebuilt once, a moment later (Polestar fires several in a row)
function PS:Changed(why)
  if why == "STEP_CHANGED" or why == "GUIDE_CHANGED" or why == "TABS_CHANGED" then self.stale = true end
  if self.queued then return end
  self.queued = true
  C.After(0, function()
    PS.queued = nil
    if PS:Active() then PS:Sync(why) end
  end)
end

-------------------------------------------------------------------------------
-- Polestar's step as one of our steps
-------------------------------------------------------------------------------
local STATUS = { done = "done", active = "todo", pending = "todo", skipped = "hidden", na = "hidden" }
-- our goal types are used for the step's icon and for the quest line only; the state always comes from Polestar (g.ps)
local TYPE = { accept = "accept", turnin = "turnin", complete = "complete", kill = "kill", collect = "item", ["goto"] = "goto",
               talk = "talk", interact = "talk", use = "talk", sethome = "hearth", hearth = "hearth", getfp = "fly", fly = "fly",
               enter = "goto", explore = "goto", train = "train", learn = "train", skill = "train", buy = "buy", vendor = "vendor",
               level = "level", craft = "craft" }

-- map and 0..1 position on the game's own map of a Polestar point ({ map, x, y, f }: percent, in its own frame)
local function livePoint(p, point)
  if type(point) ~= "table" or not point.map then return nil end
  local m, x, y = call(p.Nav.LiveCoords, point)
  if not (m and type(x) == "number" and type(y) == "number") then return nil end
  return m, x / 100, y / 100
end
PS.LivePoint = function(point) local p = P() if p then return livePoint(p, point) end end

-- Nov 14 2026 (step 21): the guide's own words reach the player through the voice: the few guide notes that name the engine
-- ("Follow the Polestar guide ...", "Polestar cannot read your rank yet") are said as the guide speaks (PolestarVoice.GuideText)
local function gt(s)
  local V = Panoply.PolestarVoice
  if V and type(s) == "string" then return V.GuideText(s) end
  return s
end

local function goalText(gv)
  local t = type(gv.text) == "string" and gt(gv.text) or ""
  local pr = gv.progress
  if type(pr) == "table" and type(pr.cur) == "number" and type(pr.max) == "number" and pr.max > 1 and (pr.kind or "count") == "count" then
    local have = ("%d/%d"):format(pr.cur, pr.max)
    if not t:find(have, 1, true) then t = t .. " (" .. have .. ")" end
  end
  return t
end

function PS:BuildStep(view, full)
  local p = P()
  local step = { ps = true, fromGuide = true, psIndex = view.index, goals = {}, title = gt(view.title) }
  local notes, confirm = {}, nil
  for _, gv in ipairs(view.goals or {}) do
    if gv.t == "note" then
      local nt = gt(gv.text)
      if full and STATUS[gv.status] ~= "hidden" and type(nt) == "string" and nt ~= "" then notes[#notes + 1] = nt end
    elseif not gv.folded then
      local g = { ps = true, psIndex = gv.index, type = TYPE[gv.t] or "confirm", text = goalText(gv), status = STATUS[gv.status] or "todo",
                  questID = type(gv.quest) == "number" and gv.quest or nil, optional = gv.optional or gv.side or nil,
                  hint = gt(gv.header) or nil, psManual = gv.manual or nil }
      if g.type == "kill" then step.kind = step.kind or "kill" end
      if full then
        g.mapID, g.x, g.y = livePoint(p, gv)
        if g.status == "todo" and gv.manual and not confirm then confirm = gv.index end
        if type(gv.noticeText) == "string" and g.status ~= "hidden" then notes[#notes + 1] = gt(gv.noticeText) end
        if type(gv.purposeText) == "string" then notes[#notes + 1] = gt(gv.purposeText) end
      end
      step.goals[#step.goals + 1] = g
    end
  end
  if not step.title or step.title == "" then
    for _, g in ipairs(step.goals) do if g.status ~= "hidden" and g.text ~= "" then step.title = g.text break end end
  end
  step.title = step.title or "Next step"
  if full then
    if type(view.note) == "string" and view.note ~= "" then table.insert(notes, 1, gt(view.note)) end
    if type(view.why) == "string" and view.why ~= "" then notes[#notes + 1] = gt(view.why) end
    step.why = table.concat(notes, " ")
    step.psConfirm = confirm
    step.psCurrent = view.current
  end
  return step
end

-- "Step 12 of 80" as the player counts the steps (Polestar leaves out the ones this character does not have)
-- 0.9.5 phase 4K: the two numbers alone (nil, nil when Polestar cannot say); Panoply.StepText.Number builds "Step 12 of 80 · Westfall" from them
function PS:Num(index)
  local p = P()
  if not (p and p.Engine and index) then return nil, nil end
  local n, total = call(p.Engine.StepNumber, index), call(p.Engine.StepTotal)
  if type(n) ~= "number" or type(total) ~= "number" then return nil, nil end
  return n, total
end

function PS:NumText(index, live)
  local p = P()
  local n, total = call(p.Engine.StepNumber, index), call(p.Engine.StepTotal)
  local s = (type(n) == "number" and type(total) == "number") and ("Step %d of %d"):format(n, total) or "Step"
  if live and index ~= live then s = s .. ", not your current step" end
  return s
end

function PS:Upcoming(index)
  local p = P()
  local out = {}
  local count = call(p.Engine.GetStepCount) or 0
  for i = index + 1, math.min(count, index + self.SCAN) do
    if #out >= self.UPCOMING then break end
    local v = call(p.Engine.GetStepView, i)
    if v and v.status ~= "na" and v.status ~= "done" and not v.along and not v.skipped then
      local open = false
      for _, gv in ipairs(v.goals or {}) do if gv.status ~= "na" and gv.t ~= "note" then open = true break end end
      if open then out[#out + 1] = self:BuildStep(v, false) end
    end
  end
  return out
end

-- Rebuild our copy of Polestar's step. Fires our own STEP_CHANGED / STEP_UPDATED / STEPS_CHANGED so every window follows.
function PS:Sync(why)
  if not self:Active() then return false end
  local p, E = P(), Panoply.Engine
  local guide = call(p.Engine.GetGuide)
  local index = guide and call(p.Engine.GetStepIndex) or nil
  local live = guide and call(p.Engine.GetLiveStep) or nil
  local view = index and call(p.Engine.GetStepView, index) or nil
  local key = guide and ((guide.id or "?") .. ":" .. tostring(index)) or "none"
  local changed = key ~= self.key
  local oldLive, oldGuide = self.live, self.guideID
  self.key, self.live, self.guideID = key, live, guide and guide.id or nil
  self.guideTitle = guide and guide.title or nil
  self.guideZone = guide and type(guide.zoneName) == "string" and guide.zoneName or nil   -- 0.9.5 phase 4K: the chapter's name ("Westfall")
  if not view then
    -- no guide, or the guide has no step left for this character
    if #E.steps > 0 or changed or E.travel then
      E.steps, E.index, E.title, E.waiting, E.travel = {}, 1, self.guideTitle or "No guide", nil, nil
      self.upcoming = nil
      Panoply:Fire("STEPS_CHANGED")
      if oldGuide and oldGuide == self.guideID and oldLive and not live then Panoply:Fire("PLAN_FINISHED") end
    else
      E:Updated()   -- 0.9.5 phase 4A4: Sync runs from the one-second check; quiet while nothing changed
    end
    return true
  end
  local step = self:BuildStep(view, true)
  step.guideID = guide.id
  step.numText = self:NumText(index, live)
  step.psLooking = (live and index ~= live) or nil
  step.mapID, step.x, step.y = self:Target()
  if changed or self.stale or not self.upcoming then
    self.upcoming = self:Upcoming(index)
    self.stale = nil
  end
  local steps = { step }
  for _, s in ipairs(self.upcoming) do steps[#steps + 1] = s end
  E.steps, E.index, E.title, E.waiting = steps, 1, guide.title or "Guide", nil
  if Panoply.cdb then Panoply.cdb.stepIndex = 1 end
  if changed then
    -- the step before this one was finished in play (not looked away from): the same word our own engine gives
    if oldGuide == self.guideID and oldLive and live and live > oldLive and index == live then Panoply:Fire("STEP_DONE", oldLive) end
    E.travel = nil
    Panoply:Fire("STEPS_CHANGED")
    Panoply:Fire("STEP_CHANGED", 1, "polestar")
  else
    E:Updated()
  end
  self:SyncTravel()
  return true
end

-- Called where our own engine checks its step (events and the one-second tick)
function PS:Check()
  if not self:Active() then return false end
  local now = C.GetTime() or 0
  if self.lastSync and now - self.lastSync < 0.45 and not self.stale then return true end
  self.lastSync = now
  self:Sync("check")
  self:SyncRoute("check")
  return true
end

-- The guide's own target (never a spot picked by hand): map, x, y (0..1), label
function PS:Target()
  if not self:Active() then return nil end
  local p = P()
  local wp = call(p.Engine.GetWaypoint)
  if type(wp) ~= "table" then return nil end
  local m, x, y = livePoint(p, wp)
  if not m then return nil end
  return m, x, y, type(wp.label) == "string" and wp.label or nil
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
function PS:Back()
  local p = P()
  call(p.Engine.Prev)
  self.stale = true
  self:Sync("back")
end

-- Skip: on the step you are on, skip it for good (Polestar remembers); while looking at an earlier step, one step forward
function PS:Skip()
  local p = P()
  local index, live = call(p.Engine.GetStepIndex), call(p.Engine.GetLiveStep)
  if index and live and index ~= live then call(p.Engine.Next) else call(p.Engine.Skip) end
  self.stale = true
  self:Sync("skip")
end

function PS:CanBack()
  local p = P()
  local index = call(p.Engine.GetStepIndex)
  if not index then return false end
  local n = call(p.Engine.StepNumber, index)
  return type(n) == "number" and n > 1
end

-- "I've done it": tick the goal the game cannot check by itself (else the goal the arrow is on).
-- 0.9.5 phase 4K: `goal` (optional) names the one goal to tick; a Done tick on a step further down the route passes it (PS.ManualGoal),
-- so it never falls back to that step's first open goal (an accept or a kill the player has not done would be saved as done)
function PS:Confirm(step, goal)
  local p = P()
  if not (step and step.ps and step.psIndex) then return false end
  goal = goal or step.psConfirm or step.psCurrent
  if not goal then
    for _, g in ipairs(step.goals) do if g.status == "todo" and not g.optional then goal = g.psIndex break end end
  end
  if not goal then return false end
  local ok = call(p.Engine.ToggleGoal, step.psIndex, goal)
  self.stale = true
  self:Sync("confirm")
  return ok and true or false
end

-- The first goal of a step that only a manual tick can finish and that is still open (its Polestar goal index), or nil
function PS.ManualGoal(step)
  if not (step and step.ps) then return nil end
  for _, g in ipairs(step.goals or {}) do
    if g.psManual and g.status == "todo" and g.psIndex then return g.psIndex end
  end
  return nil
end

-- "Replan": Polestar plans by itself; this asks it for a guide when it has none, and works the way there out again
function PS:Replan(reason)
  if not self:Active() then return false end
  local p = P()
  if not call(p.Engine.GetGuide) and p.Engine.StartGuide then call(p.Engine.StartGuide) end
  if p.Nav.travel and p.Nav.travel.Replan then call(p.Nav.travel.Replan) end
  self.stale = true
  self:Sync("replan")
  self:SyncRoute("replan")
  if reason == "menu" or reason == "settings" or reason == "slash" or reason == "button" then
    local step = Panoply.Engine.steps[1]
    if step then Panoply:Print(("Your guide: %s, %s. The way there was worked out again."):format(tostring(Panoply.Engine.title), step.numText or "one step"))
    else Panoply:Print(self:IdleText()) end
  end
  return true
end

-- 0.9.6 phase I: no guide open for this character: Polestar's own pick (Engine.StartGuide, what its login does with "pick a guide for
-- me" on, its default) opens the guide for its level and place. At login, after Polestar's own login pick: in the bundle that pick
-- failed until 0.9.6 (Core/Bundle.lua B.ShareMixins), and a character it failed for had no guide at all ("No guide here yet"). A
-- player who turned Polestar's pick off keeps it off. -> true when a guide is open
function PS:EnsureGuide(why)
  if not self:Active() then return false end
  local p = P()
  local E = p.Engine
  if call(E.GetGuide) then return true end
  if call(p.Get, "behavior.autoSelectGuide") == false or not E.StartGuide then return false end
  call(E.StartGuide)
  local ok = call(E.GetGuide) ~= nil
  if ok then self.stale = true Panoply:Debug("guide started for this character:", why) end
  return ok
end

-- 0.9.6 phase I ("if more than one route/zone choice really exists, offer the player that choice"): the guide open for this
-- character is one option of a route choice that two or more routes really fit, the character has not chosen yet, and is at the
-- start of it (its first level or the next one, as Polestar's own login offer). Polestar asks that in its own window, which stays
-- hidden; Panoply's guide window asks it instead (PS:Question). -> the choice's from-guide id, or nil
function PS:StartOffer()
  if not self:Active() then return nil end
  local p = P()
  local E = p.Engine
  local guide = call(E.GetGuide)
  if not (guide and E.RouteChoiceFor and E.GetRouteChoice) then return nil end
  local from = call(E.RouteChoiceFor, guide.id)
  local choice = from and call(E.GetRouteChoice, from)
  if type(choice) ~= "table" or type(choice.options) ~= "table" or #choice.options < 2 or choice.chosen ~= nil then return nil end
  local info = p.Compat and p.Compat.GetPlayerInfo and call(p.Compat.GetPlayerInfo)
  local level = (type(info) == "table" and info.level) or (Panoply.State and Panoply.State.level) or 1
  if (tonumber(level) or 1) > (tonumber(guide.minLevel) or 1) + 1 then return nil end
  return from, choice
end

-------------------------------------------------------------------------------
-- When there is no step: what the guide window says, and the guide's questions
-------------------------------------------------------------------------------
function PS:IdleText()
  local p = P()
  local guide = call(p.Engine.GetGuide)
  if not guide then
    return "No guide for this character here yet", "The leveling guide has nothing for this character's level and place right now. It starts by itself when it does."
  end
  return ("You finished %s"):format(tostring(gt(guide.title) or "this guide")), "There is no step left in this guide for this character."
end

-- A route choice as a question with two answers (the recommended route, then the other or a menu of the others). kind "next": the
-- guide is finished ("Where next?"); "start" (0.9.6 phase I): the character stands at the start of one of the routes (PS:StartOffer).
-- (0.9.7: the copy lane's final words for the "start" title and lead line)
PS.START_TITLE = "Choose your route"
PS.START_BODY = "More than one route starts here. Pick one to follow."
function PS:ChoiceQuestion(from, choice, kind, guide, after)
  local E = P().Engine
  local rec, others = nil, {}
  for _, o in ipairs(choice.options) do
    if o.recommended and not rec then rec = o else others[#others + 1] = o end
  end
  rec = rec or table.remove(others, 1)
  local function label(o)
    local lv = (o.minLevel and o.maxLevel) and (" (levels %d to %d)"):format(o.minLevel, o.maxLevel) or ""
    return tostring(o.zoneName or o.title or "the next zone") .. lv
  end
  local list = { "Recommended: " .. label(rec) .. "." }
  for _, o in ipairs(others) do list[#list + 1] = "Or: " .. label(o) .. "." end
  local out
  if kind == "start" then
    -- the route choice at the start of a guide (0.9.6 phase I)
    out = { kicker = "Your guide asks", title = PS.START_TITLE, body = PS.START_BODY .. " " .. table.concat(list, " ") }
  else
    out = { kicker = "Your guide asks", title = "Where next?",
      body = ("You finished %s. "):format(tostring(choice.fromTitle or guide.title or "this guide")) .. table.concat(list, " ") }
  end
  out.a = { label = "Go to " .. tostring(rec.zoneName or rec.title or "the next zone"), tip = "Takes the recommended zone.",
            fn = function() call(E.ChooseRoute, from, rec.id) after() end }
  if #others > 0 then
    local o = others[1]
    out.b = { label = #others == 1 and ("Go to " .. tostring(o.zoneName or o.title or "the other zone")) or "Another zone",
      tip = #others == 1 and "Takes the other zone." or "Shows the other zones to pick from.",
      fn = function(anchor)
        if #others == 1 then call(E.ChooseRoute, from, o.id) after() return end
        local items = {}
        for _, x in ipairs(others) do
          items[#items + 1] = { text = label(x), func = function() call(E.ChooseRoute, from, x.id) after() end }
        end
        return Panoply.Skin.Menu(anchor, items)
      end }
  end
  return out
end

-- A question the guide waits on, in plain words, with at most two answers: { kicker, title, body, a = { label, tip, fn }, b = {...} }
function PS:Question()
  if not self:Active() then return nil end
  local p = P()
  local E = p.Engine
  local guide = call(E.GetGuide)
  if not guide then return nil end
  local function after() PS.stale = true PS:Sync("answer") end
  local q, title = call(E.LostQuestion)
  if q then
    local name = Panoply.Planner.Quoted(title or "A quest")
    return { kicker = "Your guide asks", title = name .. " left your quest log",
      body = "The guide had already passed where you pick it up. Go back for it, or leave it out together with the quests that follow from it?",
      a = { label = "Go back for it", tip = "The guide leads you back to where the quest is picked up.", fn = function() call(E.AnswerLost, q, "back") after() end },
      b = { label = "Leave it out", tip = "The guide skips this quest and the quests that need it.", fn = function() call(E.AnswerLost, q, "skip") after() end } }
  end
  q, title = call(E.GroupQuestion)
  if q then
    local name = Panoply.Planner.Quoted(title or "A quest")
    return { kicker = "Your guide asks", title = "Group quest: " .. name,
      body = "This quest is meant for a group. Do it with a group, or leave it out of your guide?",
      a = { label = "Leave it out", tip = "The guide goes on without this quest.", fn = function() call(E.AnswerGroup, q, "skip") after() end },
      b = { label = "I'll do it", tip = "The guide keeps this quest and its steps.", fn = function() call(E.AnswerGroup, q, "do") after() end } }
  end
  -- 0.9.6 phase I: a route choice at the start of the guide (PS:StartOffer), asked over the first step
  local startFrom, startChoice = self:StartOffer()
  if startFrom then return self:ChoiceQuestion(startFrom, startChoice, "start", guide, after) end
  if call(E.GetLiveStep) then return nil end
  -- the guide is finished: the next zone, when there is a choice or a next guide
  local from = call(E.PendingRouteChoice)
  local choice = from and call(E.GetRouteChoice, from)
  if type(choice) == "table" and type(choice.options) == "table" and #choice.options > 0 then
    return self:ChoiceQuestion(from, choice, "next", guide, after)
  end
  local nextId = E.NextGuide and call(E.NextGuide, guide.id)
  local nextGuide = nextId and p.Guides and call(p.Guides.Get, nextId)
  if nextGuide then
    return { kicker = "Guide finished", title = ("You finished %s"):format(tostring(guide.title or "this guide")),
      body = ("Next: %s."):format(tostring(nextGuide.title or "the next guide")),
      a = { label = "Start the next guide", tip = "Opens the next guide where this one ends.", fn = function() call(E.StartNext, guide.id) after() end } }
  end
  return nil
end

-------------------------------------------------------------------------------
-- The arrow: where Polestar's own arrow would point
-------------------------------------------------------------------------------
-- state, yards, angle (0 = straight ahead, counter-clockwise, 0..2pi; nil when the game gives no facing), other-zone name
-- 0.9.9 (Nov 21 2026: "Polestar's wording"): what Polestar's own arrow says in the states it added in 0.4.x for a walk it cannot
-- guide, taken from Polestar's own text table (its words, in the player's language where Polestar has them; the key is the English).
-- 0.9.9.1 (Polestar 0.4.2.1): the "unsafe" state is gone (the other faction's towns are walked round, with "Hostile town" under the step),
-- and the underwater state's words are now Polestar's "Under water nearby: swim down to it"; each state here was checked against
-- Polestar/Nav/Nav.lua (what Nav.Sample returns) and Nav/Arrow.lua (what it shows) of 0.4.2.1.
-- 0.9.9.1 (review): Polestar's arrow has words in two more states, "water-depth" (the yards below you, a number in the words) and
-- "arrived-underwater"; they are mapped the same way. What Polestar's arrow DOES in each state (Nav/Arrow.lua setMode / Update): routing shows
-- the arrow straight at the target with the words; unmapped, submerged and water-depth show the words and no arrow; arrived-underwater shows
-- its arrival look (no arrow) with the words. PS.STATE_ARROW lists the one state that keeps the arrow.
PS.STATE_TEXT = { routing = "Finding a walking route", unmapped = "The last steps here aren't mapped",
                  submerged = "Under water nearby: swim down to it", ["water-depth"] = "%d yd below you: swim down",
                  ["arrived-underwater"] = "Arrived underwater" }
PS.STATE_ARROW = { routing = true }
function PS:StateText(st, yards)
  local key = self.STATE_TEXT[st]
  if not key then return nil end
  local p = P()
  local L = type(p) == "table" and p.L or nil
  local ok, text = pcall(function() return L and L[key] end)
  text = ok and type(text) == "string" and text ~= "" and text or key
  if text:find("%%d") then
    -- a text with the yards in it (Polestar rounds the distance: floor(dist + .5)); no number, no words
    if type(yards) ~= "number" then return nil end
    local f, out = pcall(string.format, text, math.floor(yards + 0.5))
    return f and out or nil
  end
  return text
end

function PS:Sample()
  local p = P()
  local st, dist, angle = call(p.Nav.Sample)
  if type(angle) == "number" then
    while angle < 0 do angle = angle + 2 * pi end
    while angle >= 2 * pi do angle = angle - 2 * pi end
  else angle = nil end
  local zone
  if st == "far" then zone = p.Nav.GetTargetZoneName and call(p.Nav.GetTargetZoneName) or nil end
  return st, type(dist) == "number" and dist or nil, angle, zone
end

-- A spot picked by hand in Panoply (a waypoint, Go to, a saved spot, a quest icon): Polestar routes to it; nil lets it go again
function PS:SetHandTarget(m, x, y, label)
  local p = P()
  local api = p and p.Nav and p.Nav.API
  if not (self:Active() and api and api.Navigate and api.Cancel) then return false end
  local key = m and (m .. ":" .. x .. ":" .. y) or nil
  if key == self.handKey then return true end
  self.handKey = key
  if key then call(api.Navigate, self.OWNER, m, x, y, type(label) == "string" and label or nil)
  else call(api.Cancel, self.OWNER) end
  self:SyncRoute("hand")
  return true
end

-------------------------------------------------------------------------------
-- Polestar's travel plan and walking line as one of our routes (Panoply.Route.current): the trail, the trip strip and the
-- arrow's trip time read it as they read our own router's
-------------------------------------------------------------------------------
local KIND = { walk = "walk", fly = "fly", flight = "fly", boat = "ship", zeppelin = "zeppelin", tram = "tram", portal = "portal",
               hearth = "hearth", teleport = "portal", lift = "walk" }
local DOCK = { ship = true, zeppelin = true, tram = true }

local function spot(pt, fallback)
  if type(pt) ~= "table" then return fallback end
  return { cont = pt.c, wx = pt.wx, wy = pt.wy, name = pt.name or pt.short or (fallback and fallback.name) or nil }
end

local function length(pts)
  local d = 0
  for i = 1, #pts - 1 do d = d + sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2) end
  return d
end

function PS:BuildRoute()
  local p = P()
  local t = call(p.Nav.GetTarget)
  if type(t) ~= "table" then return nil end
  local geom = p.Nav.GetRouteGeometry and call(p.Nav.GetRouteGeometry)
  local glegs = type(geom) == "table" and geom.legs or nil
  if type(glegs) ~= "table" or #glegs == 0 then return nil end
  local plegs, ci = call(p.Nav.GetRoute)
  local travel = p.Nav.travel
  local active = type(plegs) == "table" and ci and travel and travel.Active and call(travel.Active)
  local speed = (Panoply.Route and Panoply.Route.GroundSpeed and Panoply.Route:GroundSpeed()) or 7
  local tm, tx, ty = livePoint(p, t)
  local r = { ps = true, legs = {}, total = 0 }
  -- Nov 14 2026 (0.9.4, the route box read "Route to ?"): the route's end carries the destination's name, which is Polestar's own
  -- label of its target (a Go to place or a hand-picked spot passes its name through SetHandTarget; a guide step has its own). It is
  -- nil when Polestar gives none: the route box then says "Your route" and nothing is made up.
  local name = type(t.label) == "string" and t.label:find("%S") and t.label or nil
  if tm then r.to = { map = tm, x = tx, y = ty, name = name } r.target = r.to end
  local label = name or "your target"
  for k, gl in ipairs(glegs) do
    local pl = active and plegs[ci + k - 1] or nil
    local kind = KIND[(pl and pl.kind) or gl.kind] or "walk"
    local pts, cont = {}, nil
    for _, q in ipairs(gl.pts or {}) do
      if cont == nil then cont = q[1] end
      if q[1] == cont then pts[#pts + 1] = { q[2], q[3] } end
    end
    if #pts >= 1 then
      local first, last = pts[1], pts[#pts]
      local from = spot(pl and pl.from, { cont = cont, wx = first[1], wy = first[2], name = "where you are" })
      local to = spot(pl and pl.to, { cont = cont, wx = last[1], wy = last[2], name = label })
      if not to.name then to.name = label end
      if not from.name then from.name = "where you are" end
      local yards = length(pts)
      local leg = { ps = true, kind = kind, from = from, to = to, points = pts, yards = yards,
                    seconds = (pl and type(pl.seconds) == "number" and pl.seconds) or yards / speed,
                    label = pl and type(pl.label) == "string" and pl.label or nil }
      r.legs[#r.legs + 1] = leg
      r.total = r.total + leg.seconds
    end
  end
  if #r.legs == 0 then return nil end
  r.from = r.legs[1].from          -- the trip panel's "From ..." line reads it
  -- a walk that ends where a flight or a ride starts is a walk "to the flight master" / "to the dock" in the trip strip
  for i = 1, #r.legs - 1 do
    local l, nx = r.legs[i], r.legs[i + 1]
    if l.kind == "walk" then
      if nx.kind == "fly" then l.to.kind = "fp"
      elseif DOCK[nx.kind] then l.to.kind = "dock" l.to.transport = { nil, nil, nx.kind } end
    end
  end
  return r
end

function PS:RouteSig()
  local p = P()
  local t = call(p.Nav.GetTarget)
  local travel = p.Nav.travel
  local _, ci = call(p.Nav.GetRoute)
  local walk = p.Nav.walk
  return table.concat({ tostring(t), tostring(t and t.map), tostring(t and t.x), tostring(t and t.y),
    tostring(travel and travel.version), tostring(ci), tostring(walk and walk.version) }, "|")
end

function PS:SyncRoute(why)
  if not self:Active() then return false end
  local R = Panoply.Route
  if not R then return false end
  local sig = self:RouteSig()
  local geometry = why == "NAV_ROUTE_GEOMETRY" or why == "ROUTE_CHANGED" or why == "ROUTE_ADVANCED" or why == "replan" or why == "hand"
  if sig == self.routeSig and not geometry and (R.current ~= nil) == (self.hadRoute == true) then return true end
  self.routeSig = sig
  local r = nil
  if Panoply.db and Panoply.db.routeEnabled ~= false then r = self:BuildRoute() end
  self.hadRoute = r ~= nil
  R.working = nil
  if r or R.current then
    R.current = r
    Panoply:Fire("ROUTE_UPDATED", "polestar")
  end
  self:SyncTravel()
  return true
end

-- The leg of Polestar's plan that is not a walk (a flight, a boat, the tram, a portal, the hearthstone) as our travel step, in
-- front of the guide's step, in Polestar's own words for it
function PS:SyncTravel()
  local p, E, T = P(), Panoply.Engine, Panoply.Travel
  if not (self:Active() and T and T.Show) then return end
  local travel = p.Nav.travel
  local want
  if Panoply.db and Panoply.db.routeSteps ~= false and travel and travel.Active and call(travel.Active) and E.steps[1] and not E.detour and not C.OnTaxi() then
    local leg = call(travel.CurrentLeg)
    if type(leg) == "table" and leg.kind and leg.kind ~= "walk" and type(leg.label) == "string" then
      local kind = KIND[leg.kind] or "walk"
      local full = travel.CurrentLabel and call(travel.CurrentLabel) or leg.label
      local title, caption = tostring(full):match("^([^\n]*)\n?(.*)$")
      local secs = type(leg.seconds) == "number" and leg.seconds or nil
      local why = (caption and caption ~= "") and caption or ""
      if secs and secs >= 1 then why = (why ~= "" and (why .. " ") or "") .. ("About %s."):format(Panoply.Route.Duration(secs)) end
      want = { ps = true, isTravel = true, kind = kind, guideIndex = 1, key = "ps:" .. tostring(leg.kind) .. ":" .. title,
               title = title, why = why, psConfirm = 1,
               goals = { { ps = true, psIndex = 1, type = "confirm", text = title, status = "todo" } } }
    end
  end
  T:Show(want)
end

-- "Skip" or "I've done it" on a travel step: Polestar leaves that leg out (or moves on to the next one)
function PS:SkipLeg()
  local p = P()
  local travel = p and p.Nav.travel
  if travel and travel.SkipLeg then call(travel.SkipLeg) end
  self:SyncRoute("replan")
end

-------------------------------------------------------------------------------
-- Guide source: the leveling guide, or a guide added from outside (a Polestar guide pack with the id PS.ADDED_PACK)
-------------------------------------------------------------------------------
function PS:PackOf(id)
  local p = P()
  local g = id and p and p.Guides and call(p.Guides.Get, id)
  return type(g) == "table" and g.pack or nil
end

-- Every guide of the added pack that Polestar has registered: { { id, title }, ... }
function PS:AddedGuides()
  local p = P()
  local out = {}
  if not (self:Present() and p.Guides and p.Guides.List) then return out end
  for _, h in ipairs(call(p.Guides.List) or {}) do
    if type(h) == "table" and h.pack == self.ADDED_PACK then out[#out + 1] = { id = h.id, title = h.title or h.id } end
  end
  return out
end

function PS:Source()
  local p = P()
  local guide = self:Active() and call(p.Engine.GetGuide) or nil
  if guide and guide.pack == self.ADDED_PACK then return "added" end
  return "leveling"
end

-- Switch the guide Polestar follows. Each guide keeps its own place (Polestar's tabs), so switching back resumes where it was.
function PS:SetSource(src)
  if not self:Active() then return false, "The guide source switch is for WoW Forever." end
  local p = P()
  local E = p.Engine
  local cur = call(E.GetGuide)
  if src == "added" then
    local list = self:AddedGuides()
    if #list == 0 then return false, self.NO_ADDED end
    if cur and cur.pack ~= self.ADDED_PACK and Panoply.cdb then Panoply.cdb.psLevelingGuide = cur.id end
    local want = list[1].id
    for _, g in ipairs(list) do if Panoply.cdb and Panoply.cdb.psAddedGuide == g.id then want = g.id end end
    if not call(E.OpenTab, want, true) and (call(E.GetGuide) or {}).id ~= want then return false, "That guide could not be opened." end
    if Panoply.cdb then Panoply.cdb.psAddedGuide = want end
  elseif src == "leveling" then
    if cur and cur.pack == self.ADDED_PACK and Panoply.cdb then Panoply.cdb.psAddedGuide = cur.id end
    local want = Panoply.cdb and Panoply.cdb.psLevelingGuide
    if not (want and p.Guides and call(p.Guides.Get, want) and self:PackOf(want) ~= self.ADDED_PACK) then
      want = p.Guides and p.Guides.Suggest and call(p.Guides.Suggest) or nil
    end
    if not want then return false, "The leveling guide has nothing for this character right now." end
    call(E.OpenTab, want, true)
  else
    return false, "Unknown guide source."
  end
  self.stale = true
  self:Sync("source")
  self:SyncRoute("replan")
  Panoply:Fire("OPTION_CHANGED", "guideSource", self:Source())
  return true
end

-------------------------------------------------------------------------------
-- Credits, for the Guide source section of the settings and /panoply polestar (the full notices are in NOTICE.md and in each
-- Polestar folder's own LICENSE, CREDITS.md and LICENSE-DATA.txt)
function PS:Credits()
  local v = (self:Present() and type(P().version) == "string") and P().version or self.TESTED
  return ("Guide, guide engine and travel planner: Polestar %s by the Polestar authors (GPL-3.0). "
    .. "Walking router: Polestar Nav, started from Shortest Path Forever by Cillian Berragan (GPL-3.0 or later). "
    .. "Walking maps and the walks in the guides: Leffe's navigation maps. Polestar is bundled as a modified version: Panoply Suite changed two of its files (PANOPLY-CHANGES.md lists them); the notices are in NOTICE.md."):format(v)
end

-- Is this quest one the guide wants picked up now? (Engine/Automation.lua's "only quests in my route" switches)
function PS:WantsQuest(questID)
  local p = P()
  if not (self:Active() and questID and p.Engine.WantsQuest) then return false end
  return call(p.Engine.WantsQuest, "accept", questID) and true or false
end

-------------------------------------------------------------------------------
-- Status (for /panoply polestar and the self-test)
-------------------------------------------------------------------------------
-- Nov 14 2026 (step 21): never the engine's name in what the player reads (the credit line below is the one place: About, NOTICE.md
-- and this credit say whose it is). /panoply polestar is the unadvertised engine-and-credits command (not in /panoply help).
function PS:Status()
  if C.Flavor() ~= "forever" then return "The guide is for WoW Forever. " .. Panoply.GUIDE_UNAVAILABLE_LINE end
  local miss = self:Missing()
  if miss then
    local what = miss == "Polestar is not loaded" and "it is not loaded" or (miss:gsub("^Polestar%.", "") .. " is missing")
    return "The guide is not in use (" .. what .. "). " .. Panoply.GUIDE_UNAVAILABLE_LINE
  end
  if not self.on then return ("The guide (version %s) is loaded and starts when you log in."):format(tostring(P().version)) end
  local guide = call(P().Engine.GetGuide)
  return ("Guide, walking routes and travel plan: Panoply Suite's guide engine %s (GPL-3.0), drawn in Panoply Suite's windows. Guide source: %s%s."):format(
    tostring(self.version), self.SOURCE_NAMES[self:Source()], guide and (" (" .. tostring(gt(guide.title)) .. ")") or "")
end

-- our switches that Polestar follows, and the mode switch
Panoply:Listen("OPTION_CHANGED", function(key)
  if not PS.on then return end
  if key == "groupQuests" then
    PS:ApplyGroupQuests()
    PS.stale = true
    if PS:Active() then PS:Sync("group quests") end
  elseif key == "routeEnabled" or key == "routeSteps" then
    PS.routeSig = nil
    PS:SyncRoute("replan")
  end
end)
