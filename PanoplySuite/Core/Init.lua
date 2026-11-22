-- Panoply Suite: namespace, event bus, saved variables, logging.
-- Original code for Panoply Suite (personal addon). No third-party code.
local ADDON, Panoply = ...
Panoply = Panoply or {}

Panoply.name    = "Panoply Suite"
Panoply.version = "0.9.8"
Panoply.prefix  = "HPATH1"          -- addon message prefix (<=16 chars)
Panoply.debugLog = {}

-------------------------------------------------------------------------------
-- Printing / debug
-------------------------------------------------------------------------------
local CHAT_TAG = "|cff0093b2Panoply Suite|r: "

function Panoply:Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local msg = CHAT_TAG .. table.concat(parts, " ")
  local cf = _G.DEFAULT_CHAT_FRAME
  if cf and cf.AddMessage then cf:AddMessage(msg) elseif print then print(msg) end
end

function Panoply:Debug(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  local log = self.debugLog
  log[#log + 1] = line
  if #log > 400 then table.remove(log, 1) end
  if self.db and self.db.debug then self:Print("|cff888888" .. line .. "|r") end
end

-------------------------------------------------------------------------------
-- Internal callbacks (module to module)
-------------------------------------------------------------------------------
Panoply.callbacks = {}
function Panoply:Listen(name, fn)
  local list = self.callbacks[name]
  if not list then list = {}; self.callbacks[name] = list end
  list[#list + 1] = fn
end
function Panoply:Fire(name, ...)
  -- 0.9.5 phase 4A4: a plain Fire of a message that FireChanged guards (or of one that makes it stale) lets the next FireChanged through
  local sigs = self.lastSig
  if sigs[name] ~= nil and self.firingChanged ~= name then sigs[name] = nil end
  local stale = Panoply.SIG_RESETS[name]
  if stale then for _, n in ipairs(stale) do sigs[n] = nil end end
  local list = self.callbacks[name]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then self:Debug("callback error", name, err) end
  end
end

-- 0.9.5 phase 4A4 (spec 06 section 0.3, event churn): the one-second ticker checks the step, the travel step and the profession step, and
-- each check used to say STEP_UPDATED / PROF_UPDATED every time (the guide window, the tracker, the menu and the character record all
-- redrew or saved once a second, twice for a profession step). FireChanged sends the message only when sig, a plain string of everything
-- its listeners show, differs from the last one sent; Panoply.quieted counts the ones it held back (for /panoply probe and the tests).
Panoply.lastSig, Panoply.quieted = {}, {}
-- a message that makes another one's last signature meaningless (a new step, a new step list, a guide switch)
Panoply.SIG_RESETS = { STEP_CHANGED = { "STEP_UPDATED" }, STEPS_CHANGED = { "STEP_UPDATED" }, GUIDE_SWITCHED = { "STEP_UPDATED", "PROF_UPDATED" },
                  OPTION_CHANGED = { "STEP_UPDATED", "PROF_UPDATED" }, PROFS_DETECTED = { "PROF_UPDATED" } }
function Panoply:FireChanged(name, sig, ...)
  if sig ~= nil and self.lastSig[name] == sig then
    self.quieted[name] = (self.quieted[name] or 0) + 1
    return false
  end
  self.firingChanged = name
  local ok, err = pcall(self.Fire, self, name, ...)
  self.firingChanged = nil
  self.lastSig[name] = sig
  if not ok then self:Debug("callback error", name, err) end
  return true
end

-- The plain fields of a table (strings, numbers, booleans) as one string, in key order; tables and functions inside are left out.
-- out (optional) is a list the parts are added to.
function Panoply.Flat(t, out)
  out = out or {}
  if type(t) ~= "table" then out[#out + 1] = tostring(t) return out end
  local ks = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then ks[#ks + 1] = k end
  end
  table.sort(ks, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  for _, k in ipairs(ks) do out[#out + 1] = tostring(k) .. "=" .. tostring(t[k]) end
  return out
end

-------------------------------------------------------------------------------
-- Game event bus
-------------------------------------------------------------------------------
Panoply.events = {}
local eventFrame = CreateFrame("Frame", "PanoplySuiteEventFrame")
Panoply.eventFrame = eventFrame

function Panoply:On(event, fn)
  local list = self.events[event]
  if not list then
    list = {}
    self.events[event] = list
    -- Some events may not exist on a given client; registering an unknown event errors.
    -- 0.6.1: ask the client first (C_EventUtils.IsEventValid, on Forever and Era) so an
    -- Era-only event is skipped quietly on Forever; pcall stays as the safety net.
    local EU = _G.C_EventUtils
    local valid = true
    if EU and EU.IsEventValid then
      local okV, v = pcall(EU.IsEventValid, event)
      if okV and v == false then valid = false end
    end
    local ok = valid and pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then self:Debug("event not available:", event) end
    self.skippedEvents = self.skippedEvents or {}
    if not ok then self.skippedEvents[event] = true end
  end
  list[#list + 1] = fn
end

function Panoply:Dispatch(event, ...)
  local list = self.events[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then self:Debug("handler error", event, err) end
  end
end

eventFrame:SetScript("OnEvent", function(_, event, ...) Panoply:Dispatch(event, ...) end)

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------
Panoply.defaults = {
  account = {
    debug = false,
    autoAccept = true,       -- ON by default
    autoTurnIn = true,       -- ON by default
    autoFly = false,         -- 0.6.0 (SPEC 21.12): OFF by default; the player picks the destination
    routeEnabled = true,     -- 0.6.0 route planner (SPEC 21.9; all on by default)
    routeFlights = true,     -- use flight paths I know
    routeHearth = true,      -- use my hearthstone
    routeTransports = true,  -- use boats, trams and zeppelins
    routeRoads = true,       -- follow roads and passes (M3; straight lines until then)
    trailWorldMap = true,    -- 0.6.0 M4: the dotted trail on the world map (with the route card)
    trailMinimap = true,     -- the dotted trail on the minimap
    trailAnimate = true,     -- let the minimap dots drift slowly along the route
    -- 0.7.3.7: trail dots have their own size and opacity on each map (Panoply.Look); 100% / 100% is how they always looked
    trailWmSize = 1, trailWmAlpha = 1, trailMmSize = 1, trailMmAlpha = 1,
    routeSteps = true,       -- 0.6.0 M5: "Fly to X" / "Take the boat to Y" steps when they save time
    routeLearnFP = true,     -- remind me to learn flight paths the route walks past
    tripShown = true,        -- trip time under the guide window
    paceShown = true,        -- "Level 25 in about 47 min" line
    paceSource = "pace",     -- time to level from: "pace" (my own pace) or "plan" (the plan's estimate)
    paceLearn = true,        -- learn my travel pace from real trips (bounded 0.7 to 1.6)
    levelStats = true,       -- 0.7.4: record my time per level and zone (/panoply levelstats; Engine/LevelStats.lua)
    questRecorder = true,    -- 0.7.5: WoW Forever only: save new-zone / Skyborne quests as I play (/panoply recorded; Engine/QuestRecorder.lua)
    questRecorderNotice = true, -- ...and say so once per session
    partyQuestChat = false,  -- 0.9.4 (step 21): tell my party about my quest progress in chat (WoW Forever, the guide engine's line); OFF unless turned on
    roadRecords = {},        -- 0.6.0 M6: /panoply record: walked positions only (for turning into road points later)
    autoOnlyPlanQuests = false,
    autoSkipTrivial = true,
    autoSelectSingleReward = true,
    syncEnabled = true,
    syncWaitForPartner = true, syncAdoptPartnerPlan = true,
    -- 0.9.7 (Nov 18 2026; two NEW keys): the levelling styles are gone. The old key levellingStyle has no default any more: it
    -- stays in a saved file exactly as it was and is never read again (it is turned into groupQuests once, in InitDB below).
    groupQuests = "ask",     -- "ask" | "do" | "skip": Ask me each time / Always include them / Leave them out (Engine/Difficulty.lua)
    partyShare = true,       -- level together: share guide progress with my party and show theirs (Engine/PolestarParty.lua); off = nothing sent or shown
    autoExtendPlan = true,   -- when a plan runs out, plan the next few levels automatically
    autoReplan = true,       -- 0.7: re-plan when the plan no longer fits (abandon, level, moved, not offered)
    dropOnReplan = true,     -- 0.5.7: after Replan, offer to drop quests the new route doesn't use (asks first)
    syncPartner = "",        -- optional name; empty = any group member running Panoply Suite
    arrowShown = true,
    blizzWaypoint = true,
    windowLocked = false,
    minimapButton = true,    -- the shield button on the minimap
    iconStyle = "panoply", -- skin v3: "panoply" = our J icons (default; "hearthpath" before 0.9.5, still read), "wow" = the game's own icons
    showCrest = false,       -- RETIRED (Nov 2026: the shield is the one logo). Kept only so an old saved value still reads; nothing uses it.
    minimapAngle = 215,      -- degrees around the minimap
    toasts = true,           -- "Done! Next: ..." banner
    kitToasts = true,        -- 0.9.5 (a NEW key): the banner for something that completed by itself (Panoply.Kit.Toast, UI/KitParts.lua)
    -- 0.9.5 phase 4A3 (NEW keys): one on / off switch per kind of alert (Core/Alerts.lua, UI/AlertSources.lua), in the settings of
    -- the page that publishes it; off hides that kind on Home, in the nav dots and in Muster's chip at once
    alertTalentPoints = true, alertSpellsToBuy = true, alertLegacyPoints = true, alertBagsFull = true, alertMailExpiring = true,
    alertMailCOD = true, alertRestedFull = true, alertAuctionScan = true, alertTrainNow = true, alertStepGroup = true,
    alertAuctionMail = true, alertCooldownReady = true,   -- 0.9.5 phase 4I: Muster's two new kinds (NEW keys)
    windowScale = 1.0,       -- Window size: every Panoply Suite window of its own (Small / Normal / Large on a page set it to 80 / 100 / 130%)
    arrowScale = 1.0,        -- Step 2 B: how big the arrow is (Guide gear; the Guide's Small / Normal / Large set it too)
    windowAlpha = 0.95,
    stepsShown = 3,          -- guide window: current step + upcoming (1-5)
    windowFade = false,      -- fade the guide window when the mouse is not over it
    windowFadeAlpha = 0.35,
    hideInCombat = true,     -- 0.5.6: fade the guide window + profession tracker out in combat (ON)
    hideArrowInCombat = false, -- 0.5.7: its own setting, "Hide arrow in combat" (OFF: the arrow stays)
    corpseArrow = true,      -- 0.5.7: a separate skull arrow to your corpse while you are a ghost
    arrowLocked = false,     -- locked arrow: no dragging, clicks pass through
    arrowAlpha = 1.0,
    modules = {},            -- Settings > Modules on/off (nil = module default)
    soundOnStep = true,
    plannerHorizon = 3,      -- levels ahead
    plannerLogSize = 20,
    prices = {},             -- user-entered reagent prices (copper), by item name
    tradeObservations = {},  -- live recipe difficulty reads (professions corrections)
    profGuide = "interleave", -- profession steps: "interleave" (when close by), "only", "off" (tracker only)
    profStrategy = "cheapest", -- or "fastest"
    profTracker = false,     -- floating profession-step tracker next to the guide. 0.9.5 phase 4L (spec 06a 2.6): off in the standard settings,
                             -- so "Start fresh" opens no window the other setup choices don't (an account that has it on keeps it)
    profPlanFrom = "current", -- Professions tab: plan from your current skill or "scratch"
    questingMode = "guide",  -- no longer a choice: the levelling guide is always on (any saved value is set back to "guide" at load)
    questingAsked = false,   -- 0.7.1: saved name kept; the one-time note it belonged to is gone (0.9.7 hotfix)
    thanksSeen = false,      -- Step 2 A: the one-page thank-you (UI/Wizard.lua) was shown on this account; never again
    suiteOffAt = nil,        -- 0.9.6 item 4: when Panoply Suite was turned off (UI/Minimap.lua); the next login says it is back on and clears it
    setupLast = nil,         -- Step 2 A: what the last character that finished setup chose = "my usual" for the next one (UI/Wizard.lua)
    menu = { order = {}, hidden = {}, last = "guide", noted = false },  -- one-window menu: the player's page order, hidden pages, last page, the one-time note shown
    -- Step 2 B: which lines the Home page shows (Home's gear); each opens its page in one click
    homeNext = true, homeNeeds = true, homeGold = true, homeBags = true, homeAuction = true,
    whatsNewSeen = nil,      -- Step 2 B: the version whose "What's new" note this account has seen (UI/WhatsNew.lua)
  },
  char = {
    plan = nil,              -- serialized action list
    stepIndex = 1,
    knownTaxi = {},
    routeSpeed = nil,        -- 0.6.0: learned ground speed (mounted), yd/s
    bindSpot = nil,          -- 0.6.0: where this character last bound the hearthstone
    pace = nil,              -- 0.6.0 M5: learned pace { travel, travelN, xph, xphActive, flights } (Pace.lua)
    levelStats = nil,        -- 0.7.4: my real time per level and zone { v, cur, levels = { [level] = {...} } } (LevelStats.lua)
    window = nil,            -- position
    profession = nil,        -- last profession plan request
    setupDone = false,       -- first-run wizard finished
    welcomeSeen = false,     -- 0.9.6 item 5: this character was shown the splash and the welcome page before its setup (UI/Wizard.lua)
    welcomeShown = false,    -- 0.9.6 phase H: the welcome page was really on screen (or its Set up clicked); what the first run reads now
    professions = { primary = {}, secondary = {}, mode = "current", override = {} }, -- detected automatically (ProfDetect)
    profTrack = nil,         -- profession the guide follows (default: first crafting profession)
    profSpec = {},           -- e.g. { Blacksmithing = "Armorsmith" }
    knownRecipes = {},       -- recipes seen in your profession window or learned
    profMade = {},           -- items you created (craft step counters)
    profSegment = nil,
    mailItems = {},          -- items waiting in your mailbox (seen when it was open)
    windowSize = nil,        -- { w, h } guide window size (resize grip)
    waypoints = {},          -- /way queue (Waypoints module)
    classExperience = nil,   -- 0.8.4: how much the player has played, 1 to 4, picked on the class page (Modules/ClassPages)
    sectionState = {},       -- 0.9.0: which sections of a long list are open, { ["<page>/<tab>"] = { [section] = true } } (UI/Sections.lua);
                             -- a section that is not here is closed, so every section starts closed
    notTaken = {},           -- Nov 13 2026: quests whose pick-up the guide moved past untaken (too hard then, or skipped): { [questID] = true };
                             -- their later Finish / Collect / Kill / Hand in goals stay hidden until the quest is in the log (Engine/Steps.lua)
  },
}

local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      applyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end
Panoply.ApplyDefaults = applyDefaults

function Panoply:InitDB()
  -- 0.5.6: an account that already had saved settings is an update, not a fresh install
  -- (a table holding only the bridge's stopgap mark, Core/Migrate.lua, is not saved settings)
  self.existingAccount = false
  if type(_G.PanoplySuiteDB) == "table" then
    for k in pairs(_G.PanoplySuiteDB) do if k ~= "legacyPending" then self.existingAccount = true break end end
  end
  _G.PanoplySuiteDB = _G.PanoplySuiteDB or {}
  _G.PanoplySuiteCharDB = _G.PanoplySuiteCharDB or {}
  local groupQuestsUnset = _G.PanoplySuiteDB.groupQuests == nil   -- (asked before the defaults fill it in; the 0.9.7 step below reads it)
  self.db = applyDefaults(_G.PanoplySuiteDB, self.defaults.account)
  self.cdb = applyDefaults(_G.PanoplySuiteCharDB, self.defaults.char)
  self.db.questingMode = "guide"   -- the questing mode is gone; whatever an older version saved is set back
  if self.Prices and self.Prices.CleanSource then self.Prices.CleanSource(self.db) end
  -- settings of removed features: dead saved keys are cleared (tooltipYield; the qpHide* and qpQ*Noted keys of the removed
  -- quest-icon switches; a retired map-mode key is left in the saved file untouched, as no pattern that avoids its name is safe)
  for _, k in ipairs({ "tooltipYield" }) do self.db[k] = nil end
  for k in pairs(self.db) do
    if type(k) == "string" and (k:find("^qpHide") or k:find("^qpQ.*Noted$")) then self.db[k] = nil end
  end
  -- one-window menu: a brand-new account never had the old menus, so the one-time note is not for it
  if not self.existingAccount then self.db.menu.noted = true end
  -- one-off settings migrations
  -- 0.5.6: "Hide in combat" is now on by default (it was off, so saved "off" was only the old default)
  if not self.db.migrated056 then self.db.migrated056 = true self.db.hideInCombat = true end
  -- 0.5.7: "Hide in combat" became two separate settings. The saved hideInCombat value is the
  -- window setting only. The arrow stays visible unless it was really being hidden in 0.5.6
  -- (both the main option and "Also hide the arrow" were on), since that was the player's choice.
  if not self.db.migrated057 then
    self.db.migrated057 = true
    if not (self.db.hideInCombat and self.db.hideArrowInCombat) then self.db.hideArrowInCombat = false end
  end
  -- 0.6.0: Auto fly is off by default (SPEC 21.12). Accounts from 0.5.x saved the old default (on);
  -- turn it off once, but only if the player never changed it (autoFlyTouched is recorded from 0.6.0
  -- on, and a saved "off" can only be the player's own choice). Otherwise their choice stays.
  if not self.db.migrated060 then
    self.db.migrated060 = true
    if self.existingAccount and self.db.autoFly == true and not self.db.autoFlyTouched then
      self.db.autoFly = false
      self.db.autoFlyNotice = true
    end
  end
  -- 0.6.1: smaller minimap icons ("icons on minimap are too large and cover too much of the
  -- map"). The old minimap quest icon default (1.15) is saved in every 0.5.10+ account; a saved
  -- 1.15 can only be that default, so it moves to the new 1.0 once. Any other value was the
  -- player's own choice and stays.
  if not self.db.migrated061 then
    self.db.migrated061 = true
    if self.existingAccount and self.db.qpScaleMinimap == 1.15 then self.db.qpScaleMinimap = 1 end
  end
  -- 0.6.2: the route trail is drawn at full opacity by default (0.6.1's 0.85 helped it vanish into
  -- the map art). A saved 0.85 can only be the old default (the slider steps by 0.05 from 0.3, so a
  -- player who moved it and came back is indistinguishable, and full is the readable choice); it
  -- moves to 1 once. Any other value was the player's own choice and stays.
  if not self.db.migrated062 then
    self.db.migrated062 = true
    if self.existingAccount and self.db.trailAlpha == 0.85 then self.db.trailAlpha = 1 end
  end
  -- 0.7.3: "Include elite quests" and "Include dungeon quests" became one Levelling style. The old
  -- saved values map to a style once (dungeons on = Ultimate, elite on = Fastest, both off = Safe & steady)
  -- and the two old keys are removed. (0.9.7: only an account that still has one of the two old keys gets a
  -- style written; a new account has none to write, and the 0.9.7 step below starts it on "Ask me each time".)
  if not self.db.migratedLevellingStyle then
    self.db.migratedLevellingStyle = true
    if self.db.includeElite ~= nil or self.db.includeDungeons ~= nil then
      -- what the two switches of before 0.7.3 meant, as the style of that time (the 0.9.7 step below maps it on to Group quests)
      self.db.levellingStyle = self.db.includeDungeons and "ultimate" or self.db.includeElite and "fastest" or "steady"
      self.db.includeElite, self.db.includeDungeons = nil, nil
    end
  end
  -- 0.9.7 (Nov 18 2026): the levelling styles became one "Group quests" setting. The saved style maps to it ONCE, and only
  -- when groupQuests was never set: Safe & steady -> Ask me each time, Safe -> Leave them out, Fastest and Ultimate -> Always
  -- include them (Engine/Difficulty.lua). levellingStyle itself is not renamed, removed or changed; nothing reads it after this.
  -- The saved copy of every profile gets the same step, so a profile saved before the update cannot put the standard
  -- "Ask me each time" over what its style meant.
  if not self.db.migratedGroupQuests then
    self.db.migratedGroupQuests = true
    local D = Panoply.Difficulty
    if groupQuestsUnset then self.db.groupQuests = D.GroupQuestsFromStyle(self.db.levellingStyle) end
    local list = type(self.db.profiles) == "table" and self.db.profiles.list
    if type(list) == "table" then
      for _, rec in pairs(list) do
        local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
        if type(set) == "table" and set.groupQuests == nil and set.levellingStyle ~= nil then
          set.groupQuests = D.GroupQuestsFromStyle(set.levellingStyle)
        end
      end
    end
  end
  -- 0.7.3.7 ("Fix every size slider"): every thing drawn on a map has its own size and opacity on each map, and the
  -- stacked sliders (quest icon scales, minimap icon size, trail size and opacity, gathering icon size) are gone. What the
  -- old ones added up to becomes the new values once, so nothing changes size or opacity on screen; the saved copies of
  -- the profiles are converted too, so a profile saved before the update cannot undo this or bring the old keys back.
  if not self.db.migratedLook then
    self.db.migratedLook = true
    Panoply.Look.Migrate(self.db)
  end
  -- Step 2 B (our decision 18): Window size starts back at 100% for everyone on this update, because Small / Normal / Large
  -- (80 / 100 / 130%) now sit on every page. The saved copy of every profile is changed too, so a profile saved before the
  -- update cannot bring the old size back. The What's new note says so (UI/WhatsNew.lua).
  if not self.db.migratedSizePresets then
    self.db.migratedSizePresets = true
    self.windowSizeWas = self.existingAccount and type(self.db.windowScale) == "number" and self.db.windowScale or nil
    self.db.windowScale = 1.0
    local list = type(self.db.profiles) == "table" and self.db.profiles.list
    if type(list) == "table" then
      for _, rec in pairs(list) do
        local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
        if type(set) == "table" then set.windowScale = nil end
      end
    end
  end
  -- Step 2 E: the Map module's "Icon size" became a Size for the info icons and one for the connections (Look of the map); a chosen size carries over once
  if not self.db.migratedMapIcons then
    self.db.migratedMapIcons = true
    Panoply.Look.MigrateMapIcons(self.db, Panoply.Map and Panoply.Map.ProfileKeys and Panoply.Map.ProfileKeys())
  end
  -- a new install has nothing to be told about: it starts on this version's note already seen
  if not self.existingAccount and self.db.whatsNewSeen == nil then self.db.whatsNewSeen = Panoply.version end
  if self.Glow and self.Glow.Migrate then self.Glow:Migrate() end
end

-------------------------------------------------------------------------------
-- 0.6.1: minimap icons (quest icons and gathering pins share the centre fade)
-------------------------------------------------------------------------------
Panoply.MM_CENTER_PX = 15      -- pins this close to the minimap centre (the player arrow) fade out
Panoply.MM_CENTER_GONE = 6     -- and are gone this close
-- Alpha for a pin dx, dy pixels from the minimap centre: 1 from MM_CENTER_PX out, 0 at
-- MM_CENTER_GONE or closer, smooth in between, so nothing is ever drawn over the player arrow.
function Panoply.MinimapCentreAlpha(dx, dy)
  local d = math.sqrt((dx or 0) ^ 2 + (dy or 0) ^ 2)
  local far, near = Panoply.MM_CENTER_PX, Panoply.MM_CENTER_GONE
  if d >= far then return 1 end
  if d <= near then return 0 end
  local t = (d - near) / (far - near)
  return t * t * (3 - 2 * t)
end

-------------------------------------------------------------------------------
-- 0.7.3.7: size and opacity of everything Panoply Suite draws on a map ("Fix every size slider").
-- Every thing has its own pair for the world map and, where it is drawn there, for the minimap: nothing shares a
-- slider and nothing multiplies another one. Size is a share of the standard size (100% = how it looked before),
-- opacity a share of full. Drawing code asks Look.Size / Look.Alpha; the menu rows come from Look.Rows.
-------------------------------------------------------------------------------
local Look = {}
Panoply.Look = Look
Look.SIZE_MIN, Look.SIZE_MAX, Look.ALPHA_MIN, Look.ALPHA_MAX, Look.STEP = 0.25, 3, 0.1, 1, 0.05
Look.WINDOW_MIN, Look.WINDOW_MAX = 0.4, 2
Look.ARROW_MIN, Look.ARROW_MAX = 0.5, 2
-- Step 2 B: the three size choices on every page (our decision 1): Small 80%, Normal 100%, Large 130%
Look.PRESETS = { { id = "small", name = "Small", factor = 0.8 }, { id = "normal", name = "Normal", factor = 1 }, { id = "large", name = "Large", factor = 1.3 } }
-- id, saved-key prefix, name in the menu, what it is in the player's own words (for the search), maps it is drawn on
Look.THINGS = {
  { id = "trail", prefix = "trail", name = "Trail dots", words = "trail dots ants route path walking", maps = { "wm", "mm" } },
  { id = "giver", prefix = "qpGiver", name = "Quest givers (!)", words = "quest giver givers exclamation icons", maps = { "wm", "mm" } },
  { id = "turnin", prefix = "qpTurnin", name = "Hand-ins (?)", words = "quest hand in hand-in turn in turn-in question icons", maps = { "wm", "mm" } },
  { id = "objective", prefix = "qpObjective", name = "Objectives", words = "quest objective objectives targets markers dots", maps = { "wm", "mm" } },
  { id = "gather", prefix = "gather", name = "Gathering spots", words = "gathering herbs ore veins fishing chests nodes spots", maps = { "wm", "mm" } },
  { id = "way", prefix = "way", name = "Waypoints", words = "waypoint waypoints way pin", maps = { "wm" } },
}
Look.MAPS = {
  wm = { suffix = "Wm", name = "World map", on = "on the world map", words = "world map worldmap" },
  mm = { suffix = "Mm", name = "Minimap", on = "on the minimap", words = "minimap mini map" },
}
Look.BY_ID = {}
for _, t in ipairs(Look.THINGS) do Look.BY_ID[t.id] = t end

function Look.Key(thing, map, what)
  local t = Look.BY_ID[thing]
  return t.prefix .. Look.MAPS[map].suffix .. (what == "alpha" and "Alpha" or "Size")
end
-- every saved key of the sizes and opacities, in menu order
function Look.Keys()
  local out = {}
  for _, t in ipairs(Look.THINGS) do
    for _, m in ipairs(t.maps) do
      out[#out + 1] = Look.Key(t.id, m, "size")
      out[#out + 1] = Look.Key(t.id, m, "alpha")
    end
  end
  return out
end
-- the standard value of every one of them: 100%
function Look.Defaults()
  local out = {}
  for _, k in ipairs(Look.Keys()) do out[k] = 1 end
  return out
end

local function number(v, default)
  v = tonumber(v)
  if v == nil or v ~= v then return default end
  return v
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
Look.Clamp = clamp
-- Share of the standard size (0.25 to 3) / of full opacity (0.1 to 1) saved for a thing on a map. A missing, junk or
-- out-of-range saved value is read as 100% / the nearest end.
function Look.Size(thing, map) return clamp(number(Panoply.db and Panoply.db[Look.Key(thing, map, "size")], 1), Look.SIZE_MIN, Look.SIZE_MAX) end
function Look.Alpha(thing, map) return clamp(number(Panoply.db and Panoply.db[Look.Key(thing, map, "alpha")], 1), Look.ALPHA_MIN, Look.ALPHA_MAX) end
-- "Window size": every Panoply Suite window of its own (40% to 200%)
function Look.WindowScale() return clamp(number(Panoply.db and Panoply.db.windowScale, 1), Look.WINDOW_MIN, Look.WINDOW_MAX) end
-- the arrow's own size (Guide gear), 50% to 200%
function Look.ArrowScale() return clamp(number(Panoply.db and Panoply.db.arrowScale, 1), Look.ARROW_MIN, Look.ARROW_MAX) end

-- The menu rows of one thing: a slider for each size and opacity it has. The label spells out what and where (the
-- catalogue shows "Size" / "Opacity" under a "World map" / "Minimap" line); the search finds a row by it.
function Look.Rows(thing)
  local t = Look.BY_ID[thing]
  local rows = {}
  for _, m in ipairs(t.maps) do
    local mp = Look.MAPS[m]
    for _, what in ipairs({ "size", "alpha" }) do
      local size = what == "size"
      local label = ("%s: %s %s"):format(t.name, size and "size" or "opacity", mp.on)
      rows[#rows + 1] = { type = "slider", key = Look.Key(thing, m, what), label = label, searchLabel = label, default = 1,
        min = size and Look.SIZE_MIN or Look.ALPHA_MIN, max = size and Look.SIZE_MAX or Look.ALPHA_MAX, step = Look.STEP,
        tip = size and ("How big %s are %s. 100%% is the standard size."):format(t.name:lower(), mp.on)
          or ("How solid %s look %s. Lower is more see-through."):format(t.name:lower(), mp.on),
        words = t.words .. " " .. mp.words .. (size and " size big bigger small smaller scale" or " opacity transparent transparency see-through seethrough faded fade solid") }
    end
  end
  return rows
end

-- The values the stacked sliders of 0.7.3.6 and before added up to, as the new keys. `t` is a table of saved settings (the
-- account's, or the settings of a profile); a key that is missing there means its old standard. Clamped as the old readers
-- clamped, then to the new ranges.
Look.OLD_KEYS = { "qpScaleWorld", "qpScaleMinimap", "qpScaleGiver", "qpScaleTurnin", "qpScaleObjective", "mmIconScale", "trailScale", "trailAlpha" }
local OLD_STANDARD = { qpScaleWorld = 1.15, qpScaleMinimap = 1, qpScaleGiver = 1, qpScaleTurnin = 1, qpScaleObjective = 1, mmIconScale = 1, trailScale = 1, trailAlpha = 1 }
local OLD_RANGE = { qpScaleWorld = { 0.6, 2 }, qpScaleMinimap = { 0.6, 2 }, qpScaleGiver = { 0.6, 2 }, qpScaleTurnin = { 0.6, 2 }, qpScaleObjective = { 0.6, 2 },
  mmIconScale = { 0.7, 1.3 }, trailScale = { 0.6, 2 }, trailAlpha = { 0.2, 1 } }
Look.OLD_WORLD_STANDARD = 1.15      -- the world map quest icons were drawn at 1.15 x 20 px = 23 px: that is 100% now
Look.OLD_GATHER_PX = 14             -- gatherIconSize's standard: 14 px on the world map, 8 px on the minimap
function Look.FromOld(t, gatherPx)
  local function old(k)
    local r = OLD_RANGE[k]
    return clamp(number(t[k], OLD_STANDARD[k]), r[1], r[2])
  end
  local mm = old("mmIconScale")
  local world, mini = old("qpScaleWorld") / Look.OLD_WORLD_STANDARD, old("qpScaleMinimap")
  local out = {}
  for key, kind in pairs({ qpGiver = "qpScaleGiver", qpTurnin = "qpScaleTurnin", qpObjective = "qpScaleObjective" }) do
    out[key .. "WmSize"] = world * old(kind)
    out[key .. "MmSize"] = mini * old(kind) * mm
  end
  local g = number(gatherPx, Look.OLD_GATHER_PX) / Look.OLD_GATHER_PX
  out.gatherWmSize, out.gatherMmSize = g, g * mm
  out.trailWmSize, out.trailMmSize = old("trailScale"), old("trailScale")
  out.trailWmAlpha, out.trailMmAlpha = old("trailAlpha"), old("trailAlpha")
  for k, v in pairs(out) do
    out[k] = k:find("Alpha$") and clamp(v, Look.ALPHA_MIN, Look.ALPHA_MAX) or clamp(v, Look.SIZE_MIN, Look.SIZE_MAX)
  end
  return out
end
-- Writes the new keys into `t` and takes the old ones out of it.
local function convert(t, gatherPx)
  for k, v in pairs(Look.FromOld(t, gatherPx)) do t[k] = v end
  for _, k in ipairs(Look.OLD_KEYS) do t[k] = nil end
end
-- The account's settings and the saved copy of every profile (PanoplySuiteDB.profiles.list[name].settings.set).
function Look.Migrate(db)
  local gatherPx = number(db.gatherIconSize, Look.OLD_GATHER_PX)
  convert(db, gatherPx)
  db.gatherIconSize = nil
  local list = type(db.profiles) == "table" and db.profiles.list
  if type(list) == "table" then
    for _, rec in pairs(list) do
      local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
      if type(set) == "table" then convert(set, gatherPx) end
    end
  end
end

-- The guide-off questing mode is gone: Panoply Suite's levelling guide is never switched off by a mode. The guide parts still ask
-- this one function, and it always answers no.
function Panoply:PlayAlong()
  return false
end

-- 0.9.7 (Nov 18 2026): WoW Forever only, and ONE levelling guide engine. When that engine cannot run (it did not load, or a
-- part the guide needs is missing), nothing takes its place: the old planner and the converted guides do not run in the add-on.
-- The guide card and one chat line say "guide not available"; every other page keeps working. Every part that used to fall
-- through to the old route asks Panoply:GuideUnavailable() first.
Panoply.GUIDE_UNAVAILABLE_TITLE = "Guide not available"
Panoply.GUIDE_UNAVAILABLE_LINE = "The leveling guide is not available right now. Everything else in Panoply Suite works as usual."
-- The old planner and the converted guides still run for the suite's older tests, which are tests of that code (tests/run.lua turns
-- the planner back on for them, Engine/Planner.lua P.levelingOff). No saved value, setting or command reaches this in the add-on.
function Panoply:OldRouteForTests()
  local P = self.Planner
  return P ~= nil and P.BuildsLevelingRoute ~= nil and P:BuildsLevelingRoute() and true or false
end
function Panoply:GuideUnavailable()
  if self:PlayAlong() then return false end                    -- playing along: the guide is off by the player's own choice
  local PS = self.PolestarEngine
  if PS ~= nil and PS.on == true then return false end         -- the guide engine runs
  return not self:OldRouteForTests()
end
-- Empty the guide and say so on the card (Engine/StepText.lua WhatNow reads GuideUnavailable). say = also one line in chat.
function Panoply:ShowGuideUnavailable(say)
  local E, P = self.Engine, self.Planner
  if P then
    if P.job then P.job = nil if P.driver then P.driver:Hide() end end
    P.actions, P.hash, P.planSet, P.lastStats = {}, nil, {}, nil
  end
  if E then
    E.detour, E.travel = nil, nil
    if #E.steps > 0 or E.title ~= self.GUIDE_UNAVAILABLE_TITLE then E:SetSteps({}, self.GUIDE_UNAVAILABLE_TITLE) end
  end
  if say then self:Print(self.GUIDE_UNAVAILABLE_LINE) end
  return false, self.GUIDE_UNAVAILABLE_LINE
end

-- One place to change a setting, so side effects (re-plan, arrow, minimap) always happen.
Panoply.optionHooks = {}
function Panoply:SetOption(key, value)
  if not self.db then return end
  local old = self.db[key]
  self.db[key] = value
  if key == "autoFly" then self.db.autoFlyTouched = true end
  -- profGuide is also mirrored per character (activeGuide), so re-apply it even when the
  -- account-wide value did not change
  if old ~= value or (key == "profGuide" and self.cdb and self.cdb.activeGuide
      and self.ProfGuide and self.ProfGuide.GUIDE_TO_MODE[self.cdb.activeGuide] ~= value) then
    local hook = self.optionHooks[key]
    if hook then local ok, err = pcall(hook, value, old) if not ok then self:Debug("option hook", key, err) end end
    self:Fire("OPTION_CHANGED", key, value)
  end
end

-- 0.9.5 (phase 8, queue item 8): the one global handle is Panoply (Bindings.xml and /dump use it). PanoplySuite is the name it had
-- before; it stays for one release as a deprecated alias, so a macro or another add-on that used it keeps working. Remove it in 0.9.6.
-- (The code's own name was HP until 0.9.5, but that was only ever each file's local name for this table, never a global.)
_G.Panoply = Panoply
_G.PanoplySuite = Panoply
