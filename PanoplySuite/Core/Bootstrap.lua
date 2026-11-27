-- Panoply Suite bootstrap: wires saved variables, data, UI, events and the 1s safety ticker.
local ADDON, Panoply = ...
local C = Panoply.Compat

function Panoply:Replan(reason, planHere)
  -- WoW Forever with PanoplyGuide's engine (Engine/PanoplyGuideEngine.lua): PanoplyGuide plans; our planner is not asked
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return Panoply.PanoplyGuideEngine:Replan(reason) end
  -- 0.9.7 (Nov 18 2026): the guide engine cannot run: nothing takes its place (no old planner, no converted guide). The guide
  -- card says "Guide not available"; a re-plan the player asked for says it in chat too (Core/Init.lua GuideUnavailable).
  if Panoply:GuideUnavailable() then
    return Panoply:ShowGuideUnavailable(reason == "menu" or reason == "settings" or reason == "slash" or reason == "button")
  end
  -- 0.7.4.1: an area without a guide: nothing to plan (Engine/NoGuide.lua)
  -- 0.8.1: unless a written guide takes this character (Engine/Guides.lua); the no-guide judgement may still be the one of the place they
  -- came from (it only changes after it has held for a few seconds), and Planner:Replan below is what starts the written guide
  if Panoply:NoGuideHere() and not (Panoply.Guides and Panoply.Guides:UseHere()) then
    if reason == "menu" or reason == "settings" or reason == "slash" or reason == "button" then Panoply:Print(Panoply.NoGuide.LINE_PLAN or "There is no guide for this area yet.") end
    return false
  end
  -- 0.7.3.2: following a partner's route, a re-plan is a request to the party leader (who re-plans for both of
  -- you and shares it). Re-planning here would give you a route of your own that the leader's then replaces.
  -- (planHere: the leader did not answer, so plan here after all; see Sync:GiveUpAsk)
  if not planHere and Panoply.Sync and Panoply.Sync.AskReplan and Panoply.Sync:AskReplan(reason) then return false end
  local oldHash, oldSet = Panoply.Planner.hash, Panoply.Planner.planSet
  local ok, info = Panoply.Planner:Replan(reason)
  return Panoply:AfterReplan(ok, info, reason, oldHash, oldSet)
end

-- What follows a new plan (shared by the button, the slash command and the automatic re-plan).
-- auto = an automatic re-plan (Bootstrap CheckReplan). 0.7.2.1 (an automatic re-plan asked only one
-- partner to drop quests): an automatic re-plan never offers to drop quests. With zone batching
-- a new plan often leaves quests of other zones for later levels, and keeping them costs nothing; in a
-- party only the planning partner re-plans, so only that partner was asked. A re-plan you start yourself still asks.
function Panoply:AfterReplan(ok, info, reason, oldHash, oldSet, auto)
  if ok then
    -- a written guide (Engine/Guides.lua) has a title and steps, no planner estimate
    if type(info) == "table" and info.guide then Panoply:Print(("Your route: %s, %d steps from where you are."):format(tostring(info.title or "the written guide"), #Panoply.Engine.steps))
    else Panoply:Print(("New plan: %d steps, about %d min to reach level %d."):format(#Panoply.Engine.steps, math.floor((info.seconds or 0) / 60), info.endLevel or 0)) end
    -- 0.5.8: say which quests in the log were put off by the difficulty guard
    local later = {}
    for i, d in ipairs(Panoply.Planner.deferred or {}) do
      if i <= 4 then later[#later + 1] = Panoply.Difficulty.Tag(d.level, d.title) .. " (level " .. d.need .. ")" end
    end
    if #later > 0 then
      Panoply:Print("Kept for later, too hard right now: " .. table.concat(later, ", ") .. (#Panoply.Planner.deferred > 4 and (" and %d more"):format(#Panoply.Planner.deferred - 4) or "") .. ".")
    end
    -- 0.5.7: offer to drop the quests the new route doesn't use (asks first, see Engine/DropQuests.lua)
    if Panoply.DropQuests and not auto then
      local okD, err = pcall(Panoply.DropQuests.Offer, Panoply.DropQuests, reason, oldHash, oldSet)
      if not okD then Panoply:Debug("drop offer", err) end
    end
  elseif Panoply.Guides and info == Panoply.Guides.NOSTEP_LINE then
    -- Nov 11 2026: no written guide has a step here, and there is no planner to fill in (Engine/Guides.lua NoStep)
    if reason == "menu" or reason == "settings" or reason == "slash" or reason == "button" then Panoply:Print(info) end
  else
    Panoply:Print("Following your quest log only: " .. tostring(info))
  end
  return ok
end

-- When the plan runs out, plan the next stretch automatically. In a synced pair only the route leader
-- (the party leader; see Sync:LeaderOf) re-plans; the other adopts that plan through sync.
local extendedFor
Panoply:Listen("PLAN_FINISHED", function()
  local steps = Panoply.Engine.steps
  -- Hub phase 1: a plan sent from Panoply Hub ran out (Engine/Hub.lua). A side trip puts the leveling place back, so there is
  -- no next stretch to plan here; a finished replan is followed by the ordinary next stretch below.
  if Panoply.Hub and Panoply.Hub:OnPlanFinished() then return end
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return end   -- PanoplyGuide goes on to its next guide itself (the guide window asks)
  if Panoply:GuideUnavailable() then return end   -- 0.9.7: no guide engine, and nothing in its place to plan on
  if not Panoply.db or not Panoply.db.autoExtendPlan or extendedFor == steps or Panoply:PlayAlong() or Panoply:NoGuideHere() then return end
  if not Panoply.QuestData:Available() then return end
  -- (the partner who follows: the party leader plans; since Nov 11 2026 only while they hold a route the leader shared, such as a
  -- Panoply Hub plan: a written guide of their own goes on to its next guide here as for anyone)
  if Panoply.Sync:IsFollower() and (Panoply.Guides.PlannerOn() or Panoply.Sync:HoldsSharedRoute()) then return end
  extendedFor = steps
  C.After(1, function()
    if Panoply.Engine.steps == steps then Panoply:Replan("plan finished") end
  end)
end)

function Panoply:ResetPlan()
  Panoply.cdb.plan = nil; Panoply.cdb.stepIndex = 1
  Panoply.Planner.actions, Panoply.Planner.hash, Panoply.Planner.planSet, Panoply.Planner.lastStats = {}, nil, {}, nil
  Panoply.Engine:SetSteps({}, "No plan")
  Panoply:Print("Route cleared. Click Build my route (or Replan now) for a new one.")
end

-- Settings that need more than a saved value.
-- (0.9.7: the levelling style and its "Re-planning..." line are gone. Group quests is handed to the guide engine by
-- Engine/PanoplyGuideEngine.lua when it changes; nothing is planned again.)
Panoply.optionHooks.arrowShown = function() Panoply.Arrow:Refresh() end
Panoply.optionHooks.blizzWaypoint = function(v) if not v then C.ClearBlizzWaypoint() end Panoply.Arrow.target = nil Panoply.Arrow:Retarget() end
Panoply.optionHooks.minimapButton = function() if Panoply.Minimap then Panoply.Minimap:Refresh() end end
-- windowScale: UI/Skin.lua (Panoply.Windows) scales every window of its own
Panoply.optionHooks.syncEnabled = function(v) Panoply:Fire("SYNC_STATUS") if v then Panoply.Sync:SendHello() end end
Panoply.optionHooks.syncPartner = function() Panoply:Fire("SYNC_STATUS") end

local function restoreOrPlan()
  -- 0.7.4.1: logging in inside an area without a guide: no steps, no planning; the saved route stays saved
  -- (0.8.1: judged first, acted on after the written guide has had its say, so a leftover planner plan can never be adopted in a zone the written guide covers)
  local noGuide = Panoply.NoGuide and Panoply.NoGuide:Update()
  -- Hub phase 1: the plans Panoply Hub sent are read here, once per login, and a plan of its that is the route comes back before
  -- anything else decides the route (Engine/Hub.lua). A failure there never stops the ordinary restore.
  local hubOK, hubRoute = true, false
  if Panoply.Hub then hubOK, hubRoute = pcall(Panoply.Hub.AtRestore, Panoply.Hub) end
  if not hubOK then Panoply:Debug("hub restore", hubRoute) hubRoute = false end
  if hubRoute then return end
  -- WoW Forever with PanoplyGuide's engine: its guide is the route; nothing of ours is restored or planned (the saved plan stays saved)
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then
    Panoply.Engine.detour, Panoply.Engine.travel = nil, nil
    Panoply.PanoplyGuideEngine.key = nil
    -- 0.9.6 phase I: a character with no guide open gets one now (PanoplyGuide's own login pick failed in the bundle until 0.9.6)
    Panoply.PanoplyGuideEngine:EnsureGuide("login")
    Panoply.PanoplyGuideEngine:Sync("login")
    Panoply.PanoplyGuideEngine:SyncRoute("replan")
    return
  end
  -- 0.9.7 (Nov 18 2026): the guide engine cannot run. Nothing below runs in the add-on: no converted guide, no saved planner
  -- route, no planner. The saved route (PanoplySuiteCharDB.plan) stays in the file untouched; the guide card and one chat line
  -- say the guide is not available. (Below is the old route, which only the suite's older tests of it still reach.)
  if Panoply:GuideUnavailable() then
    Panoply:ShowGuideUnavailable(not Panoply.saidGuideUnavailable)
    Panoply.saidGuideUnavailable = true
    return
  end
  -- 0.8.0: a written leveling guide takes this character now (Engine/Guides.lua): its steps, at the saved step
  -- After 0.8.4: not on a first run (the setup wizard builds the route when you click Start guiding, as for the planner below),
  -- unless this character already follows a written guide. Every fresh character in its race's starting zone now takes the written
  -- guide (Guides:StartsHere), so without this the route was there before the wizard was done.
  -- Nov 10 2026: route "auto" follows the written guides everywhere they cover, on both games. A character who was on a planner
  -- route under the old default is taken over here, at this login: the written guide for their level, with its steps built from their
  -- own quest log and handed-in quests (Guides:Start), never from the start of the zone. Their saved planner plan is replaced by the
  -- guide's in the same saved key (plan); nothing else of theirs is touched. A character who chose /panoply route planner is left alone.
  -- 0.9.6 phase I (Nov 17 2026: "for a new character in a starting zone the guide auto-plans and starts with no manual step"): on a
  -- first run too. The splash, welcome and setup show over a guide that is already running; finishing or skipping setup plans again
  -- with the answers (UI/Wizard.lua Finish), from the same quest log, so nothing done meanwhile is lost.
  local saved0 = Panoply.cdb.plan
  if Panoply.Guides and Panoply.Guides:UseHere() then
    local okG, infoG = Panoply.Guides:Start("login", true)
    if okG then
      if saved0 and saved0.source ~= "guides" and type(saved0.actions) == "table" and #saved0.actions > 0 and (saved0.flavor or "forever") == C.Flavor() then
        -- (Nov 11 2026: the planner is off, so the old "/panoply route planner brings the planner back" is gone from this line)
        Panoply:Print(("Your leveling route is now the written guide for your race and faction, picked up from where this character is: %s. Nothing you have done is lost.")
          :format(tostring(infoG and infoG.title or "the written guide")))
      end
      return
    end
  end
  if noGuide then
    Panoply.Engine.detour, Panoply.Engine.travel = nil, nil
    Panoply.Engine.steps, Panoply.Engine.title, Panoply.Engine.waiting = {}, "No guide here", nil
    return
  end
  local saved = Panoply.cdb.plan
  -- A plan saved by the other game (e.g. a copied WTF folder) has the wrong coordinates: drop it.
  if saved and (saved.flavor or "forever") ~= C.Flavor() then
    Panoply:Debug("dropping plan saved on", saved.flavor or "forever")
    Panoply.cdb.plan, Panoply.cdb.stepIndex, saved = nil, nil, nil
  end
  -- Nov 11 2026 ("turn planner off."): a saved action list is the route again only when it is not a planner leveling route: a
  -- Panoply Hub plan a party leader shared (Engine/Sync.lua marks it). An old planner route stays saved, untouched, and is not used:
  -- the written guide or "No guide step here" (Planner:Replan below) is the route.
  if saved and saved.actions and #saved.actions > 0 and (Panoply.Planner:BuildsLevelingRoute() or saved.sharedKind == "hub") then
    Panoply.Engine.index = Panoply.cdb.stepIndex or 1
    Panoply.Planner:Adopt(saved.actions, saved.title or "Saved plan", "saved", true)
    if saved.sharedKind and Panoply.cdb.plan then Panoply.cdb.plan.sharedKind, Panoply.cdb.plan.sharedBy = saved.sharedKind, saved.sharedBy end
    return
  end
  if not Panoply.cdb.setupDone then
    -- First run: the setup wizard builds the route when you click Start guiding.
    Panoply.Engine:SetSteps({}, "No plan")
    return
  end
  if Panoply.QuestData:Available() then Panoply.Planner:Replan("first login")
  else Panoply.Engine:SetSteps(Panoply.Planner:LogDrivenSteps(), "Your quest log") end
end
Panoply.RestoreOrPlan = restoreOrPlan

local dataTries = 0
local function initData()
  local QD = Panoply.QuestData
  QD:Init(true)
  if QD:Available() and #QD:AllQuestIds() == 0 and dataTries < 10 then
    -- the quest data may still be loading right after login; try again shortly.
    dataTries = dataTries + 1
    QD.source = nil
    C.After(3, initData)
    return
  end
  if not QD:Available() then Panoply:Print(QD.status) end
  restoreOrPlan()
  Panoply.ProfGuide:Refresh("login")
end

-- 0.5.6: every login step runs on its own (pcall). One part failing (a module, the guide
-- window, the minimap button) can never stop the setup wizard, the tour or the ticker.
Panoply.loginErrors = {}
local function step(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    Panoply.loginErrors[#Panoply.loginErrors + 1] = { name = name, err = tostring(err) }
    Panoply:Debug("login step failed:", name, err)
  end
  return ok
end
Panoply.LoginStep = step

-- After the UI is ready: a character to set up -> the short splash, the welcome page, then setup (0.9.6 item 5; UI/Wizard.lua);
-- updated -> thank-you (Close) or welcome card; no plan -> chat hint.
function Panoply:AfterLogin()
  if Panoply.loginDone then return end
  if C.InCombat and C.InCombat() then Panoply.loginPending = true return end
  Panoply.loginDone = true
  local db, cdb = Panoply.db or {}, Panoply.cdb or {}
  local wizard = false
  -- 0.9.6 item 4: turned off from the minimap button, the welcome page or Home, and now back on (UI/Minimap.lua)
  if Panoply.Minimap and Panoply.Minimap.NoteBackOn then step("back on", Panoply.Minimap.NoteBackOn, Panoply.Minimap) end
  -- Step 2 item A: a character that has not finished setup gets the short steps; 0.9.6 item 5: the first time, they open with the
  -- splash and the welcome page (PanoplySuiteCharDB.welcomeSeen); an account that never saw the thank-you sees it once
  if (not cdb.setupDone or not db.thanksSeen) and not (Panoply.Wizard.frame and Panoply.Wizard.frame:IsShown()) then
    wizard = step("setup wizard", Panoply.Wizard.AutoStart, Panoply.Wizard)
  end
  -- account-wide: the first login after updating to this version
  if db.seenWelcome ~= Panoply.WELCOME_VERSION then
    local updated = db.lastVersion ~= nil or Panoply.existingAccount
    db.seenWelcome = Panoply.WELCOME_VERSION
    if updated and not wizard and Panoply.Toast and Panoply.Toast.ShowWelcome then step("welcome", Panoply.Toast.ShowWelcome, Panoply.Toast) end
  end
  -- Step 2 B: what changed in this update, once per account (UI/WhatsNew.lua); it waits for the thank-you or the setup to close
  if Panoply.WhatsNew then step("whats new", Panoply.WhatsNew.AfterLogin, Panoply.WhatsNew) end
  -- 0.9.5 phase 4L: an update from before the new window owes each character the tour offer once (UI/Tour.lua)
  if Panoply.Tour and Panoply.Tour.NoteLogin then step("tour offer", Panoply.Tour.NoteLogin, Panoply.Tour) end
  db.lastVersion = Panoply.version
  if db.autoFlyNotice then
    db.autoFlyNotice = nil
    Panoply:Print("Auto fly is now off by default: open the flight map and pick the destination yourself. You can turn it back on in " .. Panoply:SettingsPath("autoFly") .. ".")
  end
  -- (0.9.7: not when the guide is not available: setup cannot start a guide then, and the line above already said so)
  if (not Panoply.Engine.steps or #Panoply.Engine.steps == 0) and not Panoply:PlayAlong() and not Panoply:GuideUnavailable() then
    Panoply:Print("type /panoply setup to get started")
  end
  if #Panoply.loginErrors > 0 then
    local names = {}
    for _, e in ipairs(Panoply.loginErrors) do names[#names + 1] = e.name end
    Panoply:Print("part of Panoply Suite could not start (" .. table.concat(names, ", ") .. "). Everything else works; /panoply selftest has details.")
  end
end
Panoply.WELCOME_VERSION = "0.5.6"
Panoply.LOGIN_DELAY = 2

function Panoply:OnLogin()
  Panoply.loginErrors = {}
  Panoply.loginDone, Panoply.loginPending = nil, nil
  step("addon messages", C.RegisterPrefix, Panoply.prefix)
  -- 0.7.3.6: this character's profile (its settings, module switches, page order and window places) is applied
  -- before any window exists; the very first time, what it is set to becomes Default and nothing changes
  if Panoply.Profiles then step("profiles", Panoply.Profiles.OnLogin, Panoply.Profiles) end
  step("character info", Panoply.State.RefreshAll, Panoply.State)
  step("guide window", Panoply.UI.Create, Panoply.UI)
  step("arrow", Panoply.Arrow.Create, Panoply.Arrow)
  step("toast", Panoply.Toast.Create, Panoply.Toast)
  step("minimap button", Panoply.Minimap.Create, Panoply.Minimap)
  step("settings page", Panoply.SettingsUI.RegisterBlizzard, Panoply.SettingsUI)
  step("automation", Panoply.Automation.Register, Panoply.Automation)
  -- WoW Forever: PanoplyGuide's engine, when it is loaded (hides PanoplyGuide's own windows; our windows draw its guide and route)
  if Panoply.PanoplyGuideEngine then step("panoplyguide engine", Panoply.PanoplyGuideEngine.OnLogin, Panoply.PanoplyGuideEngine) end
  -- Suite modules (merchant, bags, glow, gathering, profession window, waypoints)
  step("modules", Panoply.Modules.ApplyAll, Panoply.Modules, true)
  if Panoply.ProfTracker then step("profession tracker", Panoply.ProfTracker.Create, Panoply.ProfTracker) end
  step("profession detect", Panoply.ProfDetect.Detect, Panoply.ProfDetect, "login")
  step("quest data", initData)
  step("show guide", function()
    if Panoply:PlayAlong() then if Panoply.UI.frame then Panoply.UI.frame:Hide() end   -- 0.7.1: the saved shown/hidden choice is kept
    elseif Panoply.cdb.hidden then Panoply.UI:Hide() else Panoply.UI:Show() end
  end)
  step("arrow refresh", Panoply.Arrow.Refresh, Panoply.Arrow)
  Panoply.ticker = C.NewTicker(1, function() Panoply:Tick() end)
  Panoply.Sync.loginAt = C.GetTime()   -- 0.7.3.2: a saved partner is waited for a few seconds (Sync:ClearToAdvance)
  C.After(5, function() step("sync hello", Panoply.Sync.SendHello, Panoply.Sync) end)
  -- 0.5.6: the wizard (and the welcome card) wait a moment for the game's UI to settle
  C.After(Panoply.LOGIN_DELAY, function() Panoply:AfterLogin() end)
  Panoply:Debug("logged in", C.Flavor())
  if C.Flavor() ~= "forever" then
    Panoply:Print("This game (" .. C.FlavorLabel() .. ") isn't supported. Panoply Suite is made for WoW Forever.")
  end
end
Panoply:On("PLAYER_REGEN_ENABLED", function() if Panoply.loginPending then Panoply.loginPending = nil Panoply:AfterLogin() end end)

function Panoply:Tick()
  Panoply.State:RefreshPlayer()
  if Panoply.NoGuide then Panoply.NoGuide:Update() end   -- 0.7.4.1
  Panoply.ProfGuide:Tick()
  Panoply.Engine:Check()
  if Panoply.Travel and not Panoply:PlayAlong() then Panoply.Travel:Tick(1) end
  if Panoply.Recorder then Panoply.Recorder:Tick(1) end
  Panoply.Sync:Tick()
  if Panoply.Locations then Panoply.Locations:Sample() end
  Panoply.Arrow:Retarget()
  if Panoply.Arrow.frame and not Panoply.Arrow.frame:IsShown() then Panoply.Arrow:Update() end
  -- 0.7.4: level and zone times for /panoply levelstats (every questing mode; last, so it can never hold up the guide)
  if Panoply.LevelStats then Panoply.LevelStats:Tick() end
end

local logPending = false
local function onLogChanged()
  if logPending then return end
  logPending = true
  C.After(0.3, function()
    logPending = false
    Panoply.State:RefreshLog()
    Panoply.Engine:Check()
    Panoply.UI:Refresh()
  end)
end

Panoply:On("ADDON_LOADED", function(_, name)
  if name == ADDON then Panoply:InitDB() end
end)
Panoply:On("PLAYER_LOGIN", function() Panoply:OnLogin() end)
Panoply:On("QUEST_TURNED_IN", function(_, questID)
  if questID then Panoply.State.completed[questID] = true end
  onLogChanged()
end)
-- Launch-day guard: if quest IDs in the game don't exist in the quest database, say so once.
Panoply:On("QUEST_ACCEPTED", function(_, a, b)
  local id = tonumber(b or a)
  local QD = Panoply.QuestData
  if not id or not QD:Available() or QD:GetQuest(id) then return end
  Panoply.State.unknownQuests = (Panoply.State.unknownQuests or 0) + 1
  Panoply:Debug("quest not in database", id)
  if Panoply.State.unknownQuests == 3 then
    Panoply:Print("Heads up: 3 quests you picked up are not in the quest database (DB mismatch). Update Panoply Suite (and its Panoply Suite Quest Data); until then follow your quest log and use the Done button.")
  end
end)
for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do Panoply:On(ev, onLogChanged) end
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE" }) do
  Panoply:On(ev, function(_, newLevel)
    if ev == "PLAYER_LEVEL_UP" and tonumber(newLevel) then Panoply.State.pendingLevel = tonumber(newLevel) end
    Panoply.State:RefreshPlayer()
    if ev == "PLAYER_LEVEL_UP" then Panoply:ReviewDeferred("level up") end
    Panoply.Engine:Check(); Panoply.UI:Refresh(); Panoply.Sync:SendState()
    -- 0.5.8: quest difficulty colours depend on your level
    if ev == "PLAYER_LEVEL_UP" then Panoply:Fire("LEVEL_CHANGED") end
  end)
end

-- 0.5.8: quests the difficulty guard put off come back once they are safe (your level-up, or
-- your partner's when they are the lower one). Solo or plan leader: re-plan so they rejoin the
-- route; the partner who follows gets that plan through sync.
function Panoply:ReviewDeferred(reason)
  if not Panoply.db or not Panoply.Engine.ReviewDeferred or Panoply:PlayAlong() then return {} end
  local back = Panoply.Engine:ReviewDeferred()
  if #back == 0 then return back end
  local names = {}
  for i, id in ipairs(back) do
    local q = Panoply.QuestData:GetQuest(id)
    local lvl = Panoply.Difficulty.QuestLevel(id, q) or 1
    names[i] = Panoply.Difficulty.Tag(lvl, (q and q.name) or (Panoply.State.log[id] and Panoply.State.log[id].title) or "a quest")
  end
  Panoply:Print("Back on your route: " .. table.concat(names, ", ") .. ".")
  -- (0.7.3.2: this used to read `leader, isMe = A and f()`, which drops isMe, so a leader never re-planned here)
  -- (Hub phase 1: not over a plan sent from Panoply Hub; its too-hard steps come back by themselves, the engine hides them only for now)
  if not Panoply.Sync:IsFollower() and not (Panoply.Hub and Panoply.Hub:Holds()) then Panoply:Replan(reason or "level up") end
  Panoply:Fire("DEFERRED_BACK", back)
  return back
end
for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_GAINED" }) do
  Panoply:On(ev, function() if not Panoply.db then return end Panoply.State:RefreshPlayer(); if Panoply.NoGuide then Panoply.NoGuide:Update() end; Panoply.Engine:Check(); Panoply.Arrow:Refresh() end)
end
-- 0.7 re-planning (ROUTE-FIX-PLAN.md "Re-planning"): after a quest leaves the log, a level-up, a
-- zone change, a hearth/flight/death (entering world) or a quest giver that does not offer the
-- planned quest, ask the planner whether the plan still fits; re-plan when it does not.
-- Throttled: at most one check per 1.5 s, at most one automatic re-plan per 20 s, never in combat.
local replanPending, lastAutoReplan = false, -1000
-- 0.7.2.1 ("replan constantly does different things and doesn't sync very well across the party"):
-- with a partner sharing one route, every automatic re-plan by the planning partner sends both of you a
-- new route, so in a party they come at most once every PARTY_REPLAN_GAP seconds (solo: 20 s).
Panoply.PARTY_REPLAN_GAP = 120
function Panoply:CheckReplan(event)
  if not Panoply.db or Panoply.db.autoReplan == false then return end
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return end   -- PanoplyGuide re-plans by itself
  if Panoply:GuideUnavailable() then return end   -- 0.9.7: no guide engine, and nothing in its place to re-plan
  if Panoply.Hub and Panoply.Hub:Holds() then return end   -- Hub phase 1: a plan sent from Panoply Hub is followed as it was sent, never re-planned by itself
  if Panoply:NoGuideHere() then return end   -- 0.7.4.1: no guide for this area
  if Panoply.PlayAlong and Panoply:PlayAlong() then return end   -- 0.7.1 base: playing along, no route to fix
  if not Panoply.QuestData:Available() or not Panoply.Planner.actions or #Panoply.Planner.actions == 0 then return end
  if replanPending then return end
  replanPending = true
  C.After(1.5, function()
    replanPending = false
    if Panoply.PlayAlong and Panoply:PlayAlong() then return end
    if C.InCombat and C.InCombat() then Panoply.replanAfterCombat = event return end
    local partner = Panoply.Sync.ActivePartner and Panoply.Sync:ActivePartner()
    if Panoply.Sync:IsFollower() then return end  -- the partner (the party leader) plans
    Panoply.State:RefreshAll()
    local ok, why = pcall(Panoply.Planner.CheckReplan, Panoply.Planner, event)
    if not ok then Panoply:Debug("replan check", why) return end
    -- Nov 10 2026: the route is the planner's (it filled in where no written guide covered this character) and a written guide covers
    -- them again: the same automatic re-plan, which hands the route back to the written guide (Planner:ReplanAsync asks Guides first)
    if not why and Panoply.Guides and Panoply.Guides:UseHere() then why = "the written guide covers you here" end
    local now = C.GetTime() or 0
    local shared = partner and Panoply.Sync:Shares()
    if why and now - lastAutoReplan >= (shared and Panoply.PARTY_REPLAN_GAP or 20) then
      lastAutoReplan = now
      -- 0.7.2 (M2): built a few ms per frame (never in combat), adopted when done
      local oldHash, oldSet = Panoply.Planner.hash, Panoply.Planner.planSet
      Panoply.replanNotice = { why = why, at = now, pending = true }
      Panoply.Planner:ReplanAsync(why, function(ok, info)
        if Panoply.PlayAlong and Panoply:PlayAlong() then return end
        Panoply.replanNotice = { why = why, at = C.GetTime() or 0, ok = ok }
        if ok then Panoply:Print("Route updated (" .. why .. ").") end
        Panoply:AfterReplan(ok, info, why, oldHash, oldSet, true)
        -- 0.7.2: say it on screen too (the toast banner; off with the toasts setting)
        if ok and Panoply.Toast then
          local first = Panoply.Engine:Current()
          local nxt = first and Panoply.StepText and Panoply.StepText.Headline(first)
          pcall(Panoply.Toast.Show, Panoply.Toast, "Route updated", "Because " .. why .. "." .. (nxt and ("\nNext: " .. nxt) or ""))
        end
        Panoply:Fire("REPLAN_DONE", why, ok)
      end)
    end
  end)
end
-- 0.7.4.1: leaving an area without a guide (Engine/NoGuide.lua) for one with data, with no saved route to go back to: the same automatic
-- re-plan as above (sliced, never in combat, at most once per 20 s, never offers to drop quests, the leader plans for a pair).
function Panoply:ResumeReplan(reason)
  if Panoply:PlayAlong() or Panoply:NoGuideHere() or not Panoply.QuestData:Available() then return end
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return end
  if Panoply:GuideUnavailable() then return end   -- 0.9.7: no guide engine, and nothing in its place
  if Panoply.Hub and Panoply.Hub:Holds() then return end   -- Hub phase 1: a Panoply Hub plan holds the route
  if Panoply.Planner.job then return end
  if Panoply.Sync:IsFollower() and (Panoply.Guides.PlannerOn() or Panoply.Sync:HoldsSharedRoute()) then return end   -- the party leader's route
  if C.InCombat and C.InCombat() then Panoply.resumeAfterCombat = reason return end
  local now = C.GetTime() or 0
  local wait = 20 - (now - lastAutoReplan)
  if wait > 0 then
    if not Panoply.resumePending then
      Panoply.resumePending = true
      C.After(wait, function() Panoply.resumePending = nil Panoply:ResumeReplan(reason) end)
    end
    return
  end
  lastAutoReplan = now
  Panoply.State:RefreshAll()
  local oldHash, oldSet = Panoply.Planner.hash, Panoply.Planner.planSet
  Panoply.replanNotice = { why = reason, at = now, pending = true }
  Panoply.Planner:ReplanAsync(reason, function(ok, info)
    if Panoply:PlayAlong() then return end
    Panoply.replanNotice = { why = reason, at = C.GetTime() or 0, ok = ok }
    if ok then Panoply:Print("Route updated (" .. reason .. ").") end
    Panoply:AfterReplan(ok, info, reason, oldHash, oldSet, true)
    Panoply:Fire("REPLAN_DONE", reason, ok)
  end)
end

-- 0.7.3.2: the follower pressed Replan: the party leader re-plans for both of you (not limited by PARTY_REPLAN_GAP,
-- because a player asked; Sync:OnReplanRequest already de-duplicates). Never offers to drop quests.
-- Returns ok, why: ok = a new route is being built (or already is) and goes to the partner when ready.
function Panoply:PartnerReplan(who)
  if Panoply:PlayAlong() then return false, "playalong" end
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return false, "panoplyguide" end
  if Panoply:GuideUnavailable() then return false, "noguide" end   -- 0.9.7: no guide engine, and no planner in its place
  if Panoply:NoGuideHere() then return false, "noguide" end   -- 0.7.4.1
  if Panoply.Planner.job then return true end   -- one is already running; its result is shared the same way
  if not Panoply.QuestData:Available() then return false, "nodata" end
  lastAutoReplan = C.GetTime() or 0
  local oldHash, oldSet = Panoply.Planner.hash, Panoply.Planner.planSet
  Panoply:Print((who or "Your partner") .. " asked for a new route. Re-planning for both of you...")
  Panoply.Planner:ReplanAsync("partner asked", function(ok, info)
    if Panoply.PlayAlong and Panoply:PlayAlong() then return end
    Panoply:AfterReplan(ok, info, "partner asked", oldHash, oldSet, true)
    if not ok and Panoply.Sync then Panoply.Sync:Queue("K", { ok = 0, why = "failed" }) end   -- tell the follower to stop waiting
    Panoply:Fire("REPLAN_DONE", "partner asked", ok)
  end)
  return true
end
Panoply:On("PLAYER_REGEN_ENABLED", function()
  if Panoply.replanAfterCombat then local ev = Panoply.replanAfterCombat Panoply.replanAfterCombat = nil Panoply:CheckReplan(ev) end
  if Panoply.resumeAfterCombat then local r = Panoply.resumeAfterCombat Panoply.resumeAfterCombat = nil Panoply:ResumeReplan(r) end
end)
Panoply:On("QUEST_REMOVED", function() Panoply:CheckReplan("removed") end)
Panoply:On("PLAYER_LEVEL_UP", function() Panoply:CheckReplan("levelup") end)
Panoply:On("ZONE_CHANGED_NEW_AREA", function() Panoply:CheckReplan("zone") end)
Panoply:On("PLAYER_ENTERING_WORLD", function() if Panoply.loginDone then Panoply:CheckReplan("moved") end end)

-- A quest giver who should offer the plan's next quest and does not (a missing lead-in, a level the
-- data got wrong): remember it so the planner skips it for now, then re-plan.
local function checkOffered(list)
  local P = Panoply.Planner
  if Panoply:GuideUnavailable() then return end   -- 0.9.7
  if not Panoply.db or Panoply.db.autoReplan == false or not P.actions or #P.actions == 0 then return end
  local ctx = P:GameContext()
  local a = ctx and ctx.plan[ctx.index]
  if not a or a.t ~= "a" or not a.n then return end
  local npc = Panoply.QuestData.NpcIdFromGUID(_G.UnitGUID and _G.UnitGUID("npc"))
  if npc ~= a.n then return end
  for _, q in ipairs(list) do if q.questID == a.q then return end end
  if Panoply.State.log[a.q] then return end
  P:NoteNotOffered(a.q, Panoply.State.level)
  Panoply:CheckReplan("notoffered")
end
Panoply:On("GOSSIP_SHOW", function() pcall(checkOffered, C.GossipAvailable()) end)
Panoply:On("QUEST_GREETING", function() pcall(checkOffered, C.GreetingAvailable()) end)

Panoply:On("HEARTHSTONE_BOUND", function() Panoply.State.bind = C.BindLocation(); Panoply.Engine:Check() end)
Panoply:On("SKILL_LINES_CHANGED", function() Panoply.State:RefreshSkills(); Panoply.Engine:Check() end)
Panoply.ProfGuide:Register()
if Panoply.Route then Panoply.Route:Register() end
if Panoply.Trail then Panoply.Trail:Register() end
if Panoply.Travel then Panoply.Travel:Register() end
if Panoply.Recorder then Panoply.Recorder:Register() end
if Panoply.LevelStats then Panoply.LevelStats:Register() end
if Panoply.QuestRecorder then Panoply.QuestRecorder:Register() end
if Panoply.Trip then Panoply.Trip:Register() end
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  Panoply:On(ev, function() pcall(Panoply.Professions.ObserveOpenWindow, Panoply.Professions) end)
end
Panoply:On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender) Panoply.Sync:OnMessage(prefix, msg, channel, sender) end)
-- 0.7.3.2: the party leader decides whose route is shared, so a change of leader means a fresh hello (and a repair if the routes differ)
local function rosterChanged()
  if not Panoply.db then return end
  Panoply.Sync:PruneLeft()   -- 0.7.3.2: a partner who left the group is forgotten at once
  if Panoply.helloPending then return end
  Panoply.helloPending = true
  C.After(2, function() Panoply.helloPending = nil; Panoply.Sync:SendHello(); Panoply.UI:Refresh() end)
end
Panoply:On("GROUP_ROSTER_UPDATE", rosterChanged)
Panoply:On("PARTY_LEADER_CHANGED", rosterChanged)
Panoply:Listen("STEP_CHANGED", function() if Panoply.db then Panoply.Sync:SendState() end end)

-- Key bindings (Bindings.xml)
_G.BINDING_HEADER_HEARTHPATH = "Panoply Suite"
-- the last file of PanoplySuite's TOCs: the guide engine's tables as they stand before the game reads the saved variables in
-- (Core/Bundle.lua B.Snapshot, so its saved data from before 0.9.9.5 is moved over the empty tables the engine made)
if _G.PanoplySuiteBundle and _G.PanoplySuiteBundle.Snapshot then _G.PanoplySuiteBundle.Snapshot() end
_G.BINDING_NAME_HEARTHPATH_TOGGLE = "Show/hide guide"
_G.BINDING_NAME_HEARTHPATH_NEXT = "Next step"
_G.BINDING_NAME_HEARTHPATH_PREV = "Previous step"
_G.BINDING_NAME_HEARTHPATH_REPLAN = "Re-plan route"
