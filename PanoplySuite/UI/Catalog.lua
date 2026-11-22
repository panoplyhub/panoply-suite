-- Panoply Suite one-window menu: the catalogue. Which pages the window has, which sections each page's
-- gear has, and which rows each section holds (docs/menus/MENUS-SPEC-v2.md and SETTINGS-MAP.md part A).
-- Every setting has exactly one home here. Keys never change: a row only says which saved key it edits.
-- The rows themselves (label, tip, limits) are looked up by key from the places that already define
-- them (UI/Settings.lua, the module option lists, UI/SettingsTravel.lua, UI/SettingsReports.lua,
-- Spec & Trainer); a catalogue row may carry a plainer label. Also here: the All settings search index,
-- the order of the pages, and Panoply:SettingsPath(key) ("Guide > Arrow") for every tip and chat line.
local ADDON, Panoply = ...
local C = Panoply.Compat
local SUI = Panoply.SettingsUI
local Cat = {}
Panoply.Catalog = Cat

-------------------------------------------------------------------------------
-- Looking rows up by key
-------------------------------------------------------------------------------
function Cat:Registry()
  if self.reg then return self.reg end
  local reg = {}
  local function add(r) if r.key and not reg[r.key] then reg[r.key] = r end end
  for _, it in ipairs(SUI.items) do
    local need = it.needs
    add({ type = "check", key = it[1], label = it[2], tip = it[3], only = need and function() return Panoply.Compat.Features()[need] end or nil })
  end
  for key, c in pairs(SUI.choices) do
    local vals = {}
    for _, v in ipairs(c.values) do vals[#vals + 1] = { v, c.names[v] or v } end
    reg[key] = { type = "segmented", key = key, label = c.label, tip = c.tip, values = vals, get = c.get, set = c.set, default = Cat.CHOICE_DEFAULTS[key] }
  end
  for _, r in ipairs(SUI.partyRows) do add(r) end
  for _, r in ipairs(SUI.guideRows) do add(r) end
  for _, r in ipairs(SUI.travelRows or {}) do add(r) end
  for _, d in ipairs(Panoply.Modules.list) do for _, r in ipairs(d.options or {}) do add(r) end end
  -- Step 2 D: the rows of everything drawn on a map come from one place (Panoply.Look.Rows), whichever module draws it
  for _, t in ipairs(Panoply.Look.THINGS) do for _, r in ipairs(Panoply.Look.Rows(t.id)) do add(r) end end
  local ST = Panoply.SpecTrainer
  for _, r in ipairs(ST and ST.SETTINGS_ROWS or {}) do add(r) end
  -- the reports switches live in PanoplySuiteReportsDB: their standard is the reports module's own
  for _, r in ipairs(Panoply.SettingsReports and Panoply.SettingsReports.rows or {}) do
    local d = r.key and Panoply.Reports and Panoply.Reports.SETTINGS and Panoply.Reports.SETTINGS[r.key]
    if d ~= nil then
      local row = {}
      for k, v in pairs(r) do row[k] = v end
      row.default = d
      add(row)
    else add(r) end
  end
  self.reg = reg
  return reg
end

-- the standard of the choices that are not plain Panoply.db values (their own get / set)
Cat.CHOICE_DEFAULTS = { iconStyle = "panoply", profGuide = "interleave", profStrategy = "cheapest", profSpec = "", groupQuests = "ask", routeSource = "auto", guideSource = "leveling", guideWindowSize = "auto" }

-- A row spec is a key ("autoAccept"), { "autoAccept", "A plainer label", tip = "..." } or a whole row
-- ({ type = "button", ... }). Returns the row to build, or nil when the key has no row in this build.
-- The one plain line shown when the mouse rests on a setting (Step 2 B): the line written for it in UI/CatalogHelp.lua, else its
-- own tip when that is already one short line. Longer tips stay as the search words.
Cat.HELP_MAX = 110
function Cat.HelpFor(key, tip)
  local h = key and Cat.HELP and Cat.HELP[key]
  if h then return h end
  if type(tip) == "string" and tip ~= "" and #tip <= Cat.HELP_MAX then return tip end
  return nil
end

function Cat:Row(spec)
  if type(spec) == "string" then spec = { spec } end
  if spec.type then
    if spec.help == nil then spec.help = Cat.HelpFor(spec.key or spec.id, spec.tip) end
    return spec
  end
  local base = self:Registry()[spec[1]]
  if not base then return nil end
  local row = {}
  for k, v in pairs(base) do row[k] = v end
  if spec[2] then row.label = spec[2] end
  for k, v in pairs(spec) do if type(k) == "string" then row[k] = v end end
  row.key = spec[1]
  if row.help == nil then row.help = Cat.HelpFor(row.key, row.tip) end
  return row
end

-------------------------------------------------------------------------------
-- Actions the gear rows run
-------------------------------------------------------------------------------
local function call(obj, name, ...) local o = Panoply[obj] if o and o[name] then return o[name](o, ...) end end

local function partnerRow(parent, x, y, width, ink)
  local Skin = Panoply.Skin
  local SP = Skin.SP
  local inner = width - 40
  local label = Skin.Text(parent, 12, Skin.colors.text); label:SetText("Who your partner is")
  label:SetWidth(inner); label:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  y = y - Skin.TextHeight(label, inner) - SP.xs
  local eb = Skin.Input(parent, 200, 24, "Partner's name")
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  local function use() Panoply:SetPartner(eb:GetText()) end
  eb:SetScript("OnEnterPressed", function() use(); eb:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function() use() end)
  eb:SetScript("OnTextChanged", function(b) if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end end)
  local set = Skin.Button(parent, "Use this name", 110, 24, use, "Use this name",
    "Sync only with this player. Leave the box empty to sync with anyone in your group who runs Panoply Suite.")
  local any = Skin.Button(parent, "Anyone in my group", 140, 24, function() eb:SetText(""); Panoply:SetPartner("") end, "Anyone in my group",
    "Sync with whoever in your group runs Panoply Suite.")
  local bh = Skin.FlowButtons(parent, { set, any }, x + 2 + 206, y, inner - 206, SP.s, 90)
  y = y - math.max(24, bh) - SP.s
  local cur = Skin.Ink(parent, 11, Skin.colors.inkSoft); cur:SetWidth(inner)
  cur:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  local w = eb
  function w:Refresh()
    if not self:HasFocus() then self:SetText(Panoply.db.syncPartner or "") end
    local c = Panoply.db.syncPartner or ""
    cur:SetText(c ~= "" and ("Syncing with " .. c) or "Syncing with anyone in your group")
    cur:SetHeight(Skin.TextHeight(cur, inner))
  end
  w:Refresh()
  y = y - Skin.TextHeight(cur, inner) - SP.m
  w.panoplyKey = "syncPartner"
  return w, y
end

local function overridesRow(parent, x, y, width)
  local Skin = Panoply.Skin
  local bw = math.min(300, width - 40)
  local b = Skin.Button(parent, "", bw, 24, function() SUI:OpenOverrides() end, "Professions to plan",
    "Panoply Suite reads your professions from your skills by itself. Click to change it by hand: plan a profession you have not learned yet, or hide one.")
  function b:Refresh() self.label:SetText("Professions to plan: " .. SUI.FoundText()) Skin.FitButton(self, 160, bw) end
  b:Refresh()
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  return b, y - b:GetHeight() - Skin.SP.s
end

-- A button that asks first: the row shows the question and Yes / Keep (inside the gear, no popup).
local function confirmRow(label, tip, ask, doit)
  return { type = "custom", id = "action:" .. label, label = label, tip = tip, build = function(parent, x, y, width)
    local Skin = Panoply.Skin
    local SP = Skin.SP
    local inner = width - 40
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
    box:SetWidth(inner)
    local go = Skin.Button(box, label, 160, 24, nil, label, tip)
    local q = Skin.Ink(box, 11, Skin.colors.warn); q:SetWidth(inner); q:SetText(ask)
    local yes = Skin.Button(box, "Yes, do it", 100, 24, function() doit() box.asking = nil; box:Refresh() end, "Yes", "Do it now.")
    yes.panoplyDanger = true; yes:Paint("up")
    local no = Skin.Button(box, "Keep things", 100, 24, function() box.asking = nil; box:Refresh() end, "Keep things", "Do nothing.")
    go:SetScript("OnClick", function() box.asking = true; box:Refresh() end)
    function box:Refresh()
      local h
      if self.asking then
        go:Hide(); q:Show(); yes:Show(); no:Show()
        q:ClearAllPoints(); q:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        local qh = Skin.TextHeight(q, inner)
        h = qh + SP.s + Skin.FlowButtons(box, { yes, no }, 0, -(qh + SP.s), inner, SP.s, 80)
      else
        q:Hide(); yes:Hide(); no:Hide(); go:Show()
        Skin.FitButton(go, 120, inner)
        go:ClearAllPoints(); go:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        h = go:GetHeight()
      end
      box:SetHeight(h)
    end
    box:Refresh()
    return box, y - box:GetHeight() - SP.m
  end }
end

local function readout(id, fn) return { type = "readout", id = id, text = fn } end
-- 0.8.4: pages added by another file (UI/Misc.lua) build their rows with the same helpers
Cat.ConfirmRow, Cat.Readout = confirmRow, readout


local function btn(id, label, tip, fn) return { type = "button", id = id, label = label, tip = tip, func = fn } end

-- Step 2 E: the Map module's settings (toolbar, follow my zone, dimmer, icons) are rows of the Map page like any other; a row of a module
-- that is off or not in this build is simply not listed (the Look of the map leaves its Info icons and Connections out the same way)
local function mapOn() return Panoply.Modules ~= nil and Panoply.Modules.byKey.map ~= nil and Panoply.Modules:Wanted("map") end
local function mapRow(key, label, extra)
  local spec = { key, label, only = mapOn }
  for k, v in pairs(extra or {}) do spec[k] = v end
  return spec
end

-------------------------------------------------------------------------------
-- Everyday words, so a search finds a setting by what it does as well as by its name
-------------------------------------------------------------------------------
Cat.WORDS = {
  windowAlpha = "opacity transparent transparency see-through seethrough background",
  windowFadeAlpha = "opacity transparent transparency see-through faded",
  arrowAlpha = "opacity transparent transparency see-through",
  trackerBgAlpha = "opacity transparent transparency see-through",
  autoSellJunk = "junk gray grey trash vendor sell",
  sellNow = "junk gray grey trash vendor sell",
  sellUnusable = "junk gray grey trash vendor bind soulbound",
  autoRepair = "gold armor armour broken vendor",
  partyShare = "sync duo partner together party friend share progress",
  syncWaitForPartner = "sync duo partner together party friend",
  syncPartner = "sync duo partner together party friend name",
  wayMapClick = "way waypoint",
  waySlash = "way waypoint command",
  wayList = "way waypoint",
  iconStyle = "look style picture",
  minimapButton = "shield crest button hide show",
  kitToasts = "toast banner popup notice message completed complete done legacy challenge",
  tooltipAuction = "price gold",
  tooltipVendor = "price gold sell",
  priceSource = "price blizzard companion",
  profAuctionCost = "price gold craft",
  autoFly = "flight flightpath taxi",
  routeFlights = "flight flightpath taxi",
  routeLearnFP = "flight flightpath taxi",
  routeHearth = "hearth hearthstone inn",
  stepsShown = "how many lines window",
  windowScale = "big small bigger smaller scale size windows menu large normal",
  arrowScale = "big small bigger smaller scale size arrow large normal",
  homeNext = "home next step line",
  homeNeeds = "home talent point spells trainer line",
  homeGold = "home gold money line",
  homeBags = "home bags full slots line",
  homeAuction = "home auction scan line",
  auctionForgetScan = "delete clear remove saved scan space size megabytes",
  auctionForgetHistory = "delete clear remove bought sold listed history record space size megabytes",
  hideInCombat = "fight fade",
  hideArrowInCombat = "fight fade",
  trackerLocked = "move drag lock",
  windowLocked = "move drag lock",
  arrowLocked = "move drag lock",
  autoAccept = "quest giver automatic",
  autoTurnIn = "quest hand in automatic complete",
  groupQuests = "elite dungeon instance group party ask include leave skip",
  questRecorder = "forever record save new zone skyborne",
  guideSource = "forever guide source leveling added polestar switch",
  partyQuestChat = "forever party chat announce tell say group objectives quest progress ready hand in loot",
  questRecorderNotice = "forever record save new zone skyborne chat",
  profiles = "save load switch character account share",
  bagReplaceDefault = "backpack b key",
  bagColumns = "wide width slots",
  bankColumns = "wide width slots",
  glowStrength = "border glow quality colour color",
  glowPoor = "border grey gray",
  gatherShare = "partner herbs ore",
  captureErrors = "lua error bug",
  send = "privacy upload send automatic sharing share hub",
  paceLearn = "speed time minutes",
  paceSource = "speed time minutes",
  tripShown = "minutes how long",
  paceShown = "minutes how long next level",
  hallPlayed = "time played played",
  hallMail = "mailbox letters",
  hallRestGuess = "rested xp",
  hallSort = "order sort characters alts",
  trainerReserve = "gold keep money",
  mapBar = "toolbar bar strip zone menu jump level range coordinates layers dungeons",
  mapCoords = "coordinates position cursor where numbers",
  mapFollow = "follow zone travel automatic switch change",
  mapDim = "dark darker dimmer dim opacity transparent wash brightness",
  mapScale = "big small bigger smaller scale size window larger",
  mapEntrances = "dungeon raid instance door entrance entrances info icons",
  mapFavWM = "favorites favourites favorite my places pins world map custom marks",
  mapFavMM = "favorites favourites favorite my places pins minimap",
  mapFavLabels = "favorites favourites names labels world map",
  mapFavWMSize = "favorites favourites size icon big small world map",
  mapFavMMSize = "favorites favourites size icon big small minimap",
  mapGraves = "graveyard graveyards spirit healer corpse info icons",
  mapFog = "fog unexplored explore exploration discover undiscovered areas hidden map",
  mapFogStrength = "fog unexplored strength opacity solid faint",
  placeRare = "rare rares rare spawn elite silver dragon sightings last seen",
  rareAlert = "rare rares alert notice warn nearby near sighting",
  placeCamp = "camp camps campfire camp fire cooking fire cook bonfire brazier",
  mapExits = "zone exit exits border next zone arrow level range connections",
  mapBoats = "boat boats ship ships dock ferry connections",
  mapZeppelins = "zeppelin zeppelins blimp airship tower connections",
  mapTram = "tram trams deeprun subway stormwind ironforge connections",
  mapPortals = "portal portals darnassus rutheran teldrassil connections",
  mapFlight = "flight path paths flightpath taxi gryphon wind rider known connections",
  mapFlightUnseen = "flight path paths flightpath taxi not learned unknown unseen connections",
}

-- 0.7.3.7: the size and opacity rows of everything drawn on a map are found by what they do and by the thing's name
-- (words come with the rows: Panoply.Look.Rows). Step 2 D: so are the spacing, style and colour rows.
for _, t in ipairs(Panoply.Look.THINGS) do
  for _, r in ipairs(Panoply.Look.Rows(t.id)) do Cat.WORDS[r.key] = r.words end
end

-------------------------------------------------------------------------------
-- The pages, in the order Panoply Suite ships them (our own order is saved in PanoplySuiteDB.menu)
-------------------------------------------------------------------------------
local function R(...) return { ... } end

-- Step 2 D: the rows of the Map page's "Look of the map": every control of every thing drawn on a map, on each map it is drawn on
-- (Panoply.Look.CONTROLS says which). They are drawn by the panel at the front of the Map gear (UI/LookPanel.lua), not as a list under More,
-- but they are rows of the catalogue like any other: the All settings box finds them, Reset this page and Undo reach them, a profile holds
-- them. The things of a module show only while that module is in this build and switched on (the trail has none: it is part of the guide).
-- Item E adds "Info icons" and "Connections" to Panoply.Look.THINGS; their rows join this list by themselves.
local LOOK_LABEL = { size = "Size", alpha = "Opacity", spacing = "Spacing", style = "Style", colour = "Colour", names = "Names" }
function Cat.LookRows()
  local rows = {}
  for _, t in ipairs(Panoply.Look.THINGS) do
    local id = t.id
    local only = function() return Panoply.Look.Here(id) end
    for _, m in ipairs(t.maps) do
      for _, what in ipairs(Panoply.Look.CONTROLS[id][m] or {}) do
        rows[#rows + 1] = { Panoply.Look.Key(id, m, what), LOOK_LABEL[what], only = only }
      end
    end
  end
  return rows
end

-- A thing added later (Panoply.Look.AddThing) gets its rows into the Map page's Look of the map, and the registry of rows is built again
function Cat.RefreshLook()
  local map = Cat.map
  for _, sec in ipairs(map and map.sections or {}) do if sec.key == "look" then sec.rows = Cat.LookRows() end end
  Cat.reg = nil
  for _, t in ipairs(Panoply.Look.THINGS) do
    for _, r in ipairs(Panoply.Look.Rows(t.id)) do Cat.WORDS[r.key] = r.words end
  end
  -- a thing added after the gear was loaded (the Map module's Info icons and Connections) shows the real screen while its controls are hovered
  if Panoply.PageSettings and Panoply.PageSettings.PREVIEW then for _, k in ipairs(Panoply.Look.AllKeys()) do Panoply.PageSettings.PREVIEW[k] = true end end
end
Panoply.Look.OnAdd = function() Cat.RefreshLook() end

-- Step 2 B. Every page may carry:
--   help   one plain line shown when the mouse rests on the page in the left list
--   noSize no Small / Normal / Large in its header (Profiles and Help: nothing there resizes)
--   front  what the gear shows first: { exact = { sizes }, common = { the 5 or 6 settings most players change } }. Each is a
--          row spec like the sections' (a key, or { key, "a plainer label" }); the rest of the page's settings are the collapsible
--          sections under them (0.9.5: every section is listed, closed), and the All settings box finds all of them. A front row
--          lives in its section of the catalogue as before (one home); the gear just shows it first.
--   shown  when the page is useful (Cat:Useful): the left list shows the page only then; the search and the doors still reach it
--   minWidth (0.9.5) the least width of the page's own area it can be laid out for. A page rebuilt for the Narrow band says a small
--          number and the window can then be dragged narrower while it shows (Menu:MinWidthFor); a page that does not say keeps 628.
--   nav    (0.9.5 phase 4A3) the section of the left list the page sits in: "play", "character", "account" or "setup" (Cat.NAV_SECTIONS).
--          The player can move a page to another section in Edit pages (PanoplySuiteDB.menu.sections, Menu:SectionOf).
--   oldNames (0.9.5) the names the page had before (search words only: "hearth hall" still finds Muster; never shown).
-- The order inside each section is our (spec 05 section 1): Play: Home, Guide, Map, At your level, Level together. Character: Class
-- (Class & Spec merged into it in 0.9.5 phase 4H), Professions, Legacy. Account: Muster, Auctions. Setup: Field Kit, Unit frames, Profiles, Help.
Cat.NAV_SECTIONS = {
  { key = "play", label = "Play" },
  { key = "character", label = "Character" },
  { key = "account", label = "Account" },
  { key = "setup", label = "Setup" },
}
Cat.PAGES = {
  { key = "home", nav = "play", label = "Home", icon = "MenuHome", body = "Home",
    text = "What needs you now, in one place.",
    help = "What needs you now: your next step, what needs you, and a tile for each page. Each opens its page.",
    -- 0.9.5 phase 4K (spec 05 section 3.2): which tiles show is still set here; homeBags and homeAuction keep their keys (the Bags and
    -- Prices tiles now), homeLegacy and homeUpgrade are new. This session's tile is Field Kit's switch (homeSession).
    sections = {
      { key = "lines", title = "What Home shows", rows = { R("homeNext", "Show my next step"), R("homeNeeds", "Show what needs me"),
          R("homeGold", "Gold tile"), R("homeBags", "Bags tile"), R("homeAuction", "Prices tile"),
          R("homeLegacy", "Legacy tile"), R("homeUpgrade", "Next upgrade tile") } },
    },
    front = { common = { "homeNext", "homeNeeds", "homeGold", "homeBags", "homeAuction" } } },

  { key = "guide", nav = "play", label = "Guide", icon = "Leveling", body = "Guide",
    text = "Your next step, and the route to your goal.",
    help = "Your next step and the route to your goal.",
    -- 0.9.5 phase 4K: the page has a Narrow band of its own now (spec 05 section 4.5): one column, the next 3 steps
    minWidth = 440,
    front = { exact = { { "arrowScale", "Arrow" } },
      common = { "groupQuests", "autoExtendPlan", "arrowShown", "windowLocked", "hideInCombat", "toasts" } },
    sections = {
      -- 0.9.7 (Nov 18 2026): the levelling styles are gone; Group quests has their row (its words are UI/Settings.lua's)
      { key = "mode", title = "Group quests", rows = { R("groupQuests", "Group quests") } },
      -- Nov 11 2026 ("turn planner off. use polestar."): the written guides are the only leveling route, so the Leveling route row
      -- (Written guides / Planner (fallback)) and Fix the route by itself (the planner re-planning by itself) are off this page. Their
      -- saved keys (routeSource, autoReplan) are kept as they are and change nothing.
      { key = "route", title = "Your route", rows = {
          R("autoExtendPlan", "Keep planning"),
          R("guideRouteSteps", "Steps in the route list"),
          R("dropOnReplan", "Offer to drop unused quests after Replan") } },
      -- Nov 2026 (step 7): on WoW Forever the guide is Polestar's; this is the switch between its leveling guide and an added guide
      { key = "source", title = "Guide source (WoW Forever)", exists = function() return Panoply.PolestarEngine ~= nil and Panoply.PolestarEngine:Present() end, rows = {
          R("guideSource", "Guide source"),
          readout("info:polestar", function() return Panoply.PolestarEngine:Status() .. "\n" .. Panoply.PolestarEngine:Credits() end) } },
      -- 0.9.4 (step 21): the party chat lines of the guide engine (WoW Forever): off unless turned on here (Engine/PolestarVoice.lua)
      { key = "partychat", title = "Party chat", exists = function() return Panoply.PolestarEngine ~= nil and Panoply.PolestarEngine:Present() end, rows = {
          R("partyQuestChat", "Tell my party about my quest progress") } },
      { key = "fastest", title = "Fastest way there", rows = {
          R("routeFlights", "Flight paths you know"), R("autoFly", "Pick the flight for me"), R("routeHearth", "Your hearthstone"),
          R("routeTransports", "Boats, trams and zeppelins"), R("routeRoads", "Roads and passes"),
          R("routeSteps", "Travel steps in the guide"), R("routeLearnFP", "Remind me to learn flight paths") } },
      { key = "trail", title = "Trail",
        text = "How the trail looks on each map (size, spacing, opacity, style, colour): Map page > Look of the map.",
        rows = { R("trailWorldMap", "On the world map"), R("trailMinimap", "On the minimap"), R("trailAnimate", "Let the dots drift") } },
      -- 0.9.7: "Time to level from" is hidden: the time to your next level comes from your own pace, and the plan's estimate it
      -- offered is not there with the guide engine. The row keeps its home (Reset this page still puts it back to your own pace).
      { key = "trips", title = "Trip times",
        rows = { R("tripShown", "Trip time under the guide window"), R("paceShown", "Time to your next level"),
          { "paceSource", "Time to level from", only = function() return false end }, R("paceLearn", "Learn my pace") },
        advanced = { readout("info:measured", function() return table.concat(Panoply.Calib:Lines(), "\n") end),
          btn("action:paceForget", "Forget my pace", "Starts learning your pace again from now.", function() SUI.ForgetPace() end) } },
      { key = "givers", title = "At quest givers", rows = {
          R("autoAccept", "Accept route quests for me"), R("autoTurnIn", "Hand in finished quests for me"),
          R("autoSelectSingleReward", "Take the only reward"), R("autoSkipTrivial", "Leave grey quests alone") } },
      { key = "window", title = "Guide window",
        text = "The small step window you play with.",
        rows = { R("stepsShown", "Steps shown"), R("guideWindowSize", "Window layout"), R("windowLocked", "Lock the guide window"),
          R("hideInCombat", "Hide the guide window in combat"), R("toasts", "Step done banner"), R("soundOnStep", "Sound when a step is done"),
          btn("action:toggleGuide", "Show or hide the guide window", "Shows the guide window when it is hidden, and hides it when it is shown.", function() call("UI", "Toggle") end),
          btn("action:resetWindowSize", "Standard window width and height", "Back to the standard width and height.", function() call("UI", "ResetSize") end) },
        advanced = { R("windowAlpha", "How solid the window background is"), R("windowFade", "Fade when the mouse is away"),
          R("windowFadeAlpha", "How faded") } },
      { key = "arrow", title = "Arrow",
        rows = { R("arrowShown", "Show the arrow"), R("arrowScale", "Arrow size"), R("arrowLocked", "Lock the arrow"), R("hideArrowInCombat", "Hide the arrow in combat"),
          R("corpseArrow", "Corpse arrow when you die"), R("blizzWaypoint", "Game's map pin as well"),
          btn("action:arrowResetPos", "Move the arrow back to the top", "Puts the arrow back at the top of the screen.", function() call("Arrow", "ResetPosition") end) },
        advanced = { R("arrowAlpha", "How solid the arrow is") } },
      { key = "tracker", title = "Quest tracker", module = "questTracker",
        rows = { R("trackerAutoTrack", "Track new quests"), R("trackerItems", "Quest item buttons"), R("trackerParty", "Party progress in the tracker"),
          R("trackerSort", "Sort quests by"), R("trackerShowAll", "Show untracked quests too"), R("trackerHideBlizzard", "Hide the game's quest tracker"),
          R("trackerLocked", "Lock position and size"),
          btn("action:trackerUnhide", "Unhide all hidden quests", "Quests you hid from the map and plan come back.", function() Panoply.QuestTracker:UnhideAll() end) },
        advanced = { R("trackerFontSize", "Text size"), R("trackerOutline", "Outline the text"), R("trackerBgAlpha", "How solid the background is"),
          R("trackerHideBG", "Hide in battlegrounds"), R("trackerHideDungeon", "Hide in dungeons and raids"),
          btn("action:trackerResetPos", "Move the tracker back", "Back to the default spot.", function() Panoply.QuestTracker:ResetPosition() end) } },
      { key = "together", title = "Level together", rows = {
          { type = "custom", id = "syncPartner", label = "Who your partner is", build = partnerRow },
          -- 0.9.7: the Level together switch is partyShare (UI/Settings.lua SUI.partyRows); "Share one route" went with the old sync
          R("partyShare", "Level together"), R("syncWaitForPartner", "Wait for my partner"),
          btn("action:openPartner", "Open the partner view", "Where your partner is, and Sync now.", function() Panoply.Menu:Open("partner") end) } },
    } },

  { key = "map", nav = "play", label = "Map", icon = "Map", body = "Map",
    text = "Go to, what the map shows, your trip, waypoints and saved spots.",
    help = "The map's toolbar, zone connections, quest icons, gathering spots, waypoints, and how everything on the maps looks.",
    -- Step 2 D: the gear opens with the Look of the map (size, opacity, spacing, style and colour of everything drawn on the world map and
    -- the minimap, with a live preview) and spans the page; the on / off rows of the icons and spots are under More settings
    gearWide = true,
    front = { panel = "look" },
    sections = {
      -- Step 2 E: the Map module (UI/../Modules/Map). Its own On / Off switch is the head of this section (the Map page is four modules' page,
      -- so the page header has no switch of its own: the Look of the map and the quest icons would still be there with it off).
      { key = "maptools", title = "Map tools", module = "map",
        text = "The toolbar on the world map, follow my zone, the dimmer and the map window.",
        rows = { mapRow("mapBar", "Show the map toolbar"), mapRow("mapCoords", "Show coordinates"), mapRow("mapFollow", "Follow my zone"),
          mapRow("mapDim", "Dim the map"), mapRow("mapScale", "Map window size"),
          btn("action:mapReset", "Reset map position and size", "Puts the map window back where the game puts it and turns the dimmer off.",
            function() if Panoply.Map and Panoply.Map.Window then Panoply.Map.Window:Reset() end end),
          btn("action:mapInstances", "Open the dungeon and raid maps", "A map of every dungeon and raid: facts, floor plan and numbered bosses.",
            function() if Panoply.Map and Panoply.Map.Instances then Panoply.Map.Instances:Toggle() end end) } },
      { key = "mapconn", title = "Connections", exists = function() return Panoply.Modules.byKey.map ~= nil end,
        text = "Where the zones join: exits, boats, zeppelins, the tram, portals and flight points. How they look: Look of the map > Connections.",
        rows = { mapRow("mapExits", "Zone exits"), mapRow("mapBoats", "Boats"), mapRow("mapZeppelins", "Zeppelins"), mapRow("mapTram", "Trams"),
          mapRow("mapPortals", "Portals"), mapRow("mapFlight", "Flight points you know"), mapRow("mapFlightUnseen", "Flight points not seen yet") } },
      { key = "mapinfo", title = "Info icons", exists = function() return Panoply.Modules.byKey.map ~= nil end,
        text = "Dungeon and raid entrances and graveyards. How they look: Look of the map > Info icons.",
        rows = { mapRow("mapEntrances", "Dungeon and raid entrances"), mapRow("mapGraves", "Graveyards"),
          mapRow("mapFog", "Mark unexplored areas"), mapRow("mapFogStrength", "Fog strength") } },
      { key = "mapplaces", title = "Places", exists = function() return Panoply.Modules.byKey.map ~= nil end,
        text = "Trainers, services, vendors and crafting stations on the zone maps and the minimap. The same switches are in the Places menu on the map. How they look: Look of the map > Places.",
        rows = { mapRow("placeTrainClass", "Class trainers"), mapRow("placeClassAll", "Show all classes"),
          mapRow("placeTrainProf", "Profession trainers"), mapRow("placeTrainPet", "Pet trainers"), mapRow("placeTrainDemon", "Demon trainers"),
          mapRow("placeTrainPortal", "Portal trainers"), mapRow("placeTrainWeapon", "Weapon masters"), mapRow("placeTrainRiding", "Riding trainers"),
          mapRow("placeMail", "Mailboxes"), mapRow("placeInn", "Innkeepers"), mapRow("placeAuction", "Auction houses"), mapRow("placeBank", "Bankers"),
          mapRow("placeGuild", "Guild masters"), mapRow("placeStable", "Stable masters"), mapRow("placeRepair", "Repair vendors"),
          mapRow("placeVTrade", "Trade goods"), mapRow("placeVProf", "Profession supplies"), mapRow("placeVReagent", "Reagents"),
          mapRow("placeVAmmo", "Ammunition"), mapRow("placeVFood", "Food and drink"), mapRow("placeVPoison", "Poisons"),
          mapRow("placeAnvil", "Anvils"), mapRow("placeForge", "Forges"),
          mapRow("placeRare", "Rare creatures"), mapRow("rareAlert", "Tell me when a rare creature is near"), mapRow("placeCamp", "Camp sites"),
          -- 0.9.5 phase 4K (spec 05b 1.4): the kinds other pages feed, shown only where they mean something (Map.lua M.KindOK)
          mapRow("placeBeastTame", "Beasts to tame", { only = function() return mapOn() and Panoply.Map.KindOK("placeBeastTame") end }),
          mapRow("placeBlueprint", "Blueprint sources", { only = function() return mapOn() and Panoply.Map.KindOK("placeBlueprint") end }),
          mapRow("placeTradeCamp", "Trade camps", { only = function() return mapOn() and Panoply.Map.KindOK("placeTradeCamp") end }),
          mapRow("placeDeath", "Where I died"), mapRow("placeMinimap", "Places on the minimap"),
          btn("action:goTo", "Open Go to", "Search for a place, save favourites, set a Home and chain stops.",
            function() if Panoply.Map and Panoply.Map.Navigate then Panoply.Map.Navigate:Toggle() end end) } },
      -- 0.9.5 phase 4G (queue item 1): the player's own map favorites (Modules/Map/Favorites.lua): where they show, their names and their
      -- size on each map; which types show and Only mine are in the Favorites window itself. (Their size is here, not in the Look of the
      -- map: a tenth thing there would not fit the gear's view at 1.3x text.)
      { key = "mapfavs", title = "Map favorites", exists = function() return Panoply.Modules.byKey.map ~= nil end,
        text = "Your own places, with a type, a note and an icon, for every character.",
        rows = { mapRow("mapFavWM", "Favorites on the world map"), mapRow("mapFavMM", "Favorites on the minimap"),
          mapRow("mapFavLabels", "Names under favorites on the world map"), mapRow("mapFavWMSize", "Size on the world map"),
          mapRow("mapFavMMSize", "Size on the minimap"),
          btn("action:mapFavorites", "Open Map favorites", "Every favorite: this zone or all, by name or distance, which types show.",
            function() if Panoply.Map and Panoply.Map.FavWindow then Panoply.Map.FavWindow:Open() end end) } },
      { key = "icons", title = "Quest icons", module = "questpins", rows = {
          R("qpWorldMap", "On the world map"), R("qpMinimap", "On the minimap"), R("qpObjectives", "Objectives too"), R("qpLowLevel", "Low-level quests"),
          R("qpLevelsAbove", "Quests above your level"), R("qpRepeatable", "Repeatable quests"), R("qpGroup", "Group quests") } },
      { key = "tips", title = "Quest tooltips", module = "questpins", rows = {
          R("qpTooltips", "Quest info in tooltips"), R("qpDropStart", "Items that start a quest"), R("qpParty", "Party progress in tooltips") } },
      { key = "gathering", title = "Gathering spots", module = "gathering",
        rows = { { type = "typechecks", id = "gatherShow" }, R("gatherWorldMap", "On the world map"), R("gatherMinimap", "On the minimap"),
          R("gatherSkillFilter", "Only spots you have the skill for"), R("gatherShare", "Share finds with your partner") },
        advanced = { R("gatherDatabase", "Known spawn spots"), R("gatherEdgeFade", "Faded icons at the minimap edge"),
          R("gatherMinimapYards", "Minimap distance"), R("gatherFadeNear", "Fade spots when close"), R("gatherFadeYards", "Fade distance") } },
      { key = "waypoints", title = "Waypoints", module = "waypoints", rows = {
          R("wayMapClick", "Ctrl-right-click the map to set one"), R("waySlash", "The /way command"),
          btn("action:wayList", "Open the waypoint list", "Your waypoints, and the arrow follows them.", function() Panoply.Waypoints:Toggle() end) } },
      -- 0.7.3.7 ("Fix every size slider"): each thing drawn on a map has its own World map and Minimap controls (nothing shares a
      -- slider). Step 2 D: "Look of the map" holds them all (and the Hollow rings switch, now the Icon / Ring style of the gathering spots
      -- on the minimap). A thing of a module that is off or not in this build is left out.
      { key = "look", title = "Look of the map", dynamic = true, panel = true,
        text = "How each thing looks on the world map and on the minimap. 100% is how it always looked.",
        rows = Cat.LookRows() },
    } },

  -- 0.8.4: the class pages (Modules/ClassPages). 0.9.5 phase 4H (docs/specs/page-redesigns-03-class.md): Class & Spec ("Talents & spells")
  -- and the Class Guide are ONE page, "Class": its header holds the plan and "Written for", its tabs are Overview, Talents, Spells,
  -- How to play, Gear and Pet. The old names are search words; the old page key "classspec" opens this page (Menu.ALIAS). Its gear
  -- holds what Class & Spec's held (talents and the trainer); its On switch is Talents & spells (the text tabs work with it off).
  { key = "class", nav = "character", oldNames = "class guide class & spec class and spec talents & spells talents spells talent planner spells to buy trainer pet macros rotation how to play gear",
    label = "Class", icon = "MenuClass", body = "ClassPages", module = "spectrainer",
    text = "Your plan, talents, spells to buy, how to play, gear and pet.",
    help = "Your class on one page: the plan in the header drives the talents, the spells to buy, the gear weights and the advice.",
    front = { common = { "specNextCard", "trainerPanel", "trainerLearnNext", "trainerToast", "trainerMountFund", "trainerReserve" } },
    sections = {
      { key = "spec", title = "Talents and trainer", module = "spectrainer",
        rows = { { type = "custom", id = "specTracked", label = "Plan I follow", build = function(p, x, y, w) return Panoply.SpecTrainer.PlanRow(p, x, y, w) end },
          { type = "custom", id = "action:specPlanner", label = "Open the Talents tab", build = function(p, x, y, w) return Panoply.SpecTrainer.PlannerRow(p, x, y, w) end },
          R("specNextCard", "Next talent when you level up"), R("specOutline", "Outline it in the talent window"),
          R("trainerPanel", "Trainer Helper beside the trainer"), R("trainerLearnNext", "\"Learn next\" button"), R("trainerShowSkip", "Show the Skip group"),
          R("trainerProfPanel", "Recipes at profession trainers"), R("trainerToast", "Tell me when new spells are waiting"),
          R("trainerArrowOffer", "Offer to point the arrow to my trainer"), { "trainerMenuLine", "Trainer visits in my route",
            tip = "When spells or a profession rank wait for you, the Guide page's route has a step for the trainer." },
          R("trainerMoneyWarn", "Warn me when I will be short"), R("trainerMountFund", "Save for riding at level 40") },
        advanced = { R("trainerReserve", "Gold to keep untouched"),
          readout("info:specSource", function() return Panoply.SpecTrainer:SettingsSourceText() end) } },
    } },

  -- 0.9.1 (11 Nov 2026: "why a diff page for hunters? Should be in the class page"): the hunter's pet has no page of its own in
  -- this list. It is the Pet tab of the Hunter's Class Guide (Modules/ClassPages, Modules/HunterPet/Panel.lua), one tab on that
  -- page's one row, with Families, Planner, To tame and Training points as closed sections inside it.

  -- 0.8.4: At your level (Modules/AtLevel): the dungeons in range, the upgrades by slot, the class quest and the trainer, for the
  -- level you are now. Nothing to set, so no gear. 0.9.5 phase 4D: rebuilt for the Narrow band, so the window may go narrower.
  { key = "atlevel", nav = "play", label = "At your level", icon = "MenuAtLevel", body = "AtLevel",
    minWidth = 420,
    text = "Dungeons, gear and class quests for the level you are now.",
    help = "What you can do at your level: dungeons in range, the best upgrade for each slot, and your class quest and trainer.",
    sections = {} },

  -- 0.9.5 phase 4I (spec 02): its own icon, and the old name and the plain words still find it. Drawn for the Narrow band too.
  { key = "hall", nav = "account", oldNames = "hearth hall alts characters", label = "Muster", icon = "MenuMuster", body = "Hall", module = "alts",
    minWidth = 420,
    text = "Your characters, with their gold, bags, bank, mail and gear.",
    help = "All your characters with their gold, bags, bank, mail, gear and professions, and your bag windows.",
    front = { common = { "bagReplaceDefault", "bagTooltipCounts", "glowStrength", "hallMail" } },
    sections = {
      { key = "hall", title = "Muster", rows = { R("hallPlayed", "Ask the game for my played time at login"),
          R("hallMail", "Remember what is in my mailbox when I open it"), R("hallRestGuess", "Estimate rested XP for characters that are offline"),
          R("hallMailDays", "Warn about mail this many days before it runs out") } },
      -- moved here from the Bags page, which the one-window menu does not have (Nov 3): same keys, same module switches
      { key = "bags", title = "Bag window", module = "bags", rows = { R("bagReplaceDefault", "Open these instead of the game's bags"), R("bagDragDrop", "Drag and drop items"),
          R("bagTooltipCounts", "Item counts in tooltips"),
          btn("action:openBags", "Open my bags", "All your bags in one window (the B key does the same).", function() if Panoply.Bags then Panoply.Bags:Toggle("bags") end end) },
        advanced = { R("bagColumns", "Bag columns"), R("bankColumns", "Bank columns") } },
      { key = "borders", title = "Item quality borders", module = "glow", rows = {
          R("glowStrength", "Border strength"), R("glowPoor", "Grey items too"), R("glowDefaultFrames", "In the game's own windows too"),
          R("glowBadges", "Quest ! and junk coin badges") } },
      -- 0.9.5 phase 4F (spec 01 5.3): repair and selling moved to Field Kit's "At the vendor" (UI/Misc.lua), with the same saved keys;
      -- Muster keeps one link to them
      { key = "vendorlink", title = "At the vendor", exists = function() return Panoply.Modules.byKey.merchant ~= nil end, rows = {
          btn("action:vendorSettings", "Vendor settings: Field Kit", "Repair, selling grey items and restock are on the Field Kit page. Opens them; Back returns here.",
            function() Panoply.Menu:OpenGear("misc", "vendor") end) } },
    },
    controls = { { key = "hallSort", label = "Sort characters by", tip = "Level, name, gold, played or last seen. The Sort button on this page changes it." } } },

  -- 0.9.5 phase 4E: the page shows the data itself (Prices, Upgrades, History; Modules/Auctions/View.lua) and is drawn for the Narrow
  -- band too, so the window may go narrower. "trade window" still finds it (it was called that until 0.9.5).
  { key = "auctions", nav = "account", oldNames = "trade window trade", label = "Auctions", icon = "MenuAuctions", body = "Auctions", module = "auctions",
    minWidth = 420,
    text = "Prices from your last scan, gear upgrades on the auction house, and your auction history.",
    help = "Prices from your last scan, gear upgrades on the auction house, and what you bought and sold.",
    front = { common = { "auctionAutoScan", "auctionPassive", "auctionUndercut", "tooltipVendor", "tooltipAuction", "priceSource" } },
    sections = {
      { key = "scanning", title = "Scanning", rows = { R("auctionAutoScan", "Tell me when a full scan is ready"), R("auctionPassive", "Remember prices while I browse"),
          R("auctionSlowScan", "Slower scan: one page per click") },
        advanced = { btn("action:auctionForget", "Forget old prices", "Removes prices older than 30 days now (this also happens by itself).",
          function() for _, r in ipairs(Panoply.Auctions.options or {}) do if r.label == "Forget old prices" and r.func then r.func() end end end) } },
      { key = "selling", title = "Selling", rows = { R("auctionUndercut", "Undercut by") } },
      { key = "prices", title = "Prices", rows = { R("tooltipVendor", "Vendor price in tooltips"), R("tooltipAuction", "Auction price in tooltips"),
          R("priceSource", "Prices come from"),
          R("profAuctionCost", "Material costs in the profession window") } },
      -- Step 2 F: what Panoply Suite keeps of the auction house, how much room it takes, and the two Forget buttons (Modules/Auctions/Record.lua,
      -- loaded after this file: the rows are built when the gear opens)
      { key = "record", title = "Saved auctions",
        text = "The last scan, and what you listed, bought and sold, are kept on this computer only, at most 8 MB. Over 8 MB, old scans and prices older than 14 days go first, and your own history only for characters not played for 90 days. If it is still over, nothing more is deleted: the size below says so, and the Forget buttons free space.",
        rows = { readout("info:auctionSaved", function() return Panoply.Auctions and Panoply.Auctions.Record and Panoply.Auctions.Record.MeterText() or "" end),
          { type = "custom", id = "action:auctionForgetScan", label = "Forget the saved scan",
            tip = "Deletes the saved scan of every realm from this computer. The prices Panoply Suite keeps are not touched.",
            build = function(p, x, y, w, ink) return Panoply.Auctions.Record.ForgetScanRow().build(p, x, y, w, ink) end },
          { type = "custom", id = "action:auctionForgetHistory", label = "Forget my auction history",
            tip = "Deletes what Panoply Suite recorded of what you listed, bought and sold: this character, or all of them.",
            build = function(p, x, y, w, ink) return Panoply.Auctions.Record.ForgetHistoryRow().build(p, x, y, w, ink) end } } },
    } },

  { key = "professions", nav = "character", label = "Professions", icon = "Professions", body = "Professions", module = "profwindow",
    text = "Your professions: next step, shopping list and plans.",
    help = "Your professions: next step, shopping list and plans.",
    -- 0.9.6 phase K (Nov 17 2026: "yes, always show professions with a starter guide"): always in the left list, on Classic and
    -- WoW Forever, whatever the character has learned. With nothing learned the page is a starter guide (UI/ProfPage.lua).
    -- 0.9.5 phase 4B: rebuilt for the Narrow band (one column under 560), so the window may go narrower while it shows
    minWidth = 420,
    front = { common = { "profGuide", "profStrategy", "profTracker", "profOverride", "profBlizzardToo", "profWindowLocked" } },
    sections = {
      { key = "mine", title = "Your professions", rows = {
          { type = "custom", id = "profOverride", label = "Professions to plan", build = overridesRow },
          R("profGuide", "Guide shows"), R("profStrategy", "Recipe plans"), R("profSpec", "Blacksmithing specialty"), R("profTracker", "Profession tracker") } },
      { key = "window", title = "Profession window", exists = function() return Panoply.Modules.byKey.profwindow ~= nil end, rows = {
          R("profBlizzardToo", "Game's profession window as well"), R("profWindowLocked", "Lock the window"),
          btn("action:profResetPos", "Move the window back", "Back to the default spot: beside the character screen and other open game panels.",
            function() Panoply.ProfWindow:ResetPosition() end) } },
    } },

  -- 0.8.4: Forever Legacy (Modules/Legacy): the account's challenges, this character's 16 perk points and the account rewards.
  -- WoW Forever only: Classic Era has no Legacy system, so the page does not exist there.
  { key = "legacy", nav = "character", oldNames = "forever legacy", label = "Legacy", icon = "MenuLegacy", body = "Legacy", exists = function() return C.IsForever() end,
    -- 0.9.5 phase 4C: rebuilt for the Narrow band (the strip in two lines, the tabs as a dropdown), so the window may go narrower
    minWidth = 420,
    text = "Legacy challenges, your perk points and the account rewards.",
    help = "Count your Legacy challenges, plan this character's 16 perk points, and see the account rewards.",
    sections = {} },

  { key = "frames", nav = "setup", label = "Unit frames", icon = "MenuFrames", body = "Frames", module = "frames",
    text = "Player, target, party and pet frames.", help = "Player, target, party and pet frames.", sections = {} },

  -- Level together: its own page (it was a view of the Guide); in the list only while you are in a group. Its settings live in the
  -- Guide's "Level together" section; its gear shows them first.
  { key = "partner", nav = "play", label = "Level together", icon = "MenuTogether", body = "Partner", shown = "group",
    text = "Who leads, where your partner is, and Sync now.",
    help = "Who you level with, where they are, and Sync now.",
    front = { common = { "syncPartner", "partyShare", "syncWaitForPartner" } },
    sections = {} },

  -- 0.9.5 (spec 1.5): the size of every Panoply Suite window is one setting for the whole suite, so it is no longer a slider in
  -- every page's settings: its one home is here (a profile holds it), and the Small / Normal / Large choice in each page's header
  -- still sets it. (Phase 4F puts the slider on the row of the profile in use.)
  -- 0.9.5 phase 4F: the page is drawn for the Narrow band too (spec 01 6.3), so the window may go narrower while it shows
  { key = "profiles", nav = "setup", label = "Profiles", icon = "Modules", body = "Profiles", noSize = true, minWidth = 420,
    text = "Save your settings under a name. Each character picks the profile it uses.",
    help = "Save your settings under a name, and give them to your other characters.",
    front = { exact = { { "windowScale", "All Panoply Suite windows" } } },
    sections = {
      { key = "size", title = "Window size", rows = { R("windowScale", "All Panoply Suite windows") } },
    } },

  { key = "help", nav = "setup", label = "Help", icon = "Help", body = "Help", noSize = true,
    text = "Get started, tips for every page, commands and problems.",
    -- 0.9.5 phase 4L (spec 06 section 2): the ? says what Help's gear holds, so no body line has to
    help = "Search help, tips for every page, commands and problems. Gear: icons, minimap button, reports, Reset.",
    front = { common = { "iconStyle", "minimapButton", "send", "captureErrors" } },
    sections = {
      { key = "look", title = "Look", rows = { R("iconStyle", "Icons"), R("minimapButton", "Minimap button"),
          R("kitToasts", "Banner when something is completed") } },
      { key = "reports", title = "Reports and privacy", rows = {
          R("send", Panoply.Sharing.SETTING), R("captureErrors", "Note Panoply Suite errors"),
          R("chatNotice", "Tell me once per session in chat"),
          -- Nov 18 2026 (easier report access): the report window from the Settings too
          btn("action:reportOpen", "Report a problem / Feedback", "Opens the report window: tell us what is wrong, or share an idea.",
            function() Panoply.ReportWindow:Open({ general = true }) end),
          btn("action:reportsClear", "Clear saved reports", "Removes every saved report and noted problem from this computer.", function() Panoply.Reports:ClearAll() Panoply:Print("Saved reports and noted problems were cleared from this computer.") end) },
        advanced = { readout("info:reports", function() return table.concat(Panoply.SettingsReports:Lines(), "\n") end) } },
      { key = "recorder", title = "Quest recorder (WoW Forever)", exists = function() return C.IsForever() end, rows = {
          R("questRecorder", "Save quests in new zones as I play"), R("questRecorderNotice", "Tell me once per session in chat"),
          readout("info:recorded", function() return Panoply.QuestRecorder and table.concat(Panoply.QuestRecorder:Lines(), "\n") or "" end) } },
      { key = "reset", title = "Reset", rows = {
          confirmRow("Reset all settings", "Puts every setting on every page back to Panoply Suite's standard. Your route, saved characters and prices are kept.",
            "This puts every setting on every page back to Panoply Suite's standard. Your route, your saved characters and your prices are kept.",
            function() Cat:ResetAll() end) } },
    } },
}

-- A page with a view of its own that is not in the left list (none today: Level together became a page of its own in Step 2 B).
Cat.VIEWS = {}

for _, p in ipairs(Cat.PAGES) do Cat[p.key] = p end

-------------------------------------------------------------------------------
-- What exists in this build
-------------------------------------------------------------------------------
function Cat.IsHunter()
  local ok, p = pcall(C.PlayerInfo)
  return ok and type(p) == "table" and p.classFile == "HUNTER"
end

local function moduleHere(key) return key ~= nil and Panoply.Modules and Panoply.Modules.byKey[key] ~= nil end

function Cat:SectionExists(sec)
  if sec.module and not moduleHere(sec.module) then return false end
  if sec.exists and not sec.exists() then return false end
  return true
end

function Cat:Sections(page)
  local out = {}
  for _, s in ipairs(page.sections or {}) do if self:SectionExists(s) then out[#out + 1] = s end end
  return out
end

function Cat:PageExists(page)
  if page.hunterOnly then return self.IsHunter() end
  if page.exists and not page.exists() then return false end   -- 0.8.4: a page of one game only (Forever Legacy)
  if page.module and not moduleHere(page.module) then
    if page.moduleOptional then return #self:Sections(page) > 0 end
    return false
  end
  if page.key == "frames" and not (Panoply.Menu and Panoply.Menu.defs and Panoply.Menu.defs.Frames) then return false end
  return true
end

-- The pages the window can show, in the order Panoply Suite ships them
function Cat:Existing()
  local out = {}
  for _, p in ipairs(self.PAGES) do if self:PageExists(p) then out[#out + 1] = p end end
  return out
end

-- Step 2 B: a page is in the left list only when it is useful: Level together while in a group. Every other page is always there
-- (0.9.6 phase K: Professions too, also before anything is learned; it no longer comes and goes). A page that is not useful yet is
-- still reached by the search, the slash commands and the pages' own links; it is only left out of the list.
function Cat:Useful(page)
  local k = page.shown
  if not k then return true end
  if k == "hunter" then return self.IsHunter() end
  if k == "group" then return Panoply.Compat.InGroup() and true or false end
  return true
end

-- the pages that come and go (a small dot in the left list); Professions is no longer one of them (it has no "shown" rule)
function Cat:Comes(page) return page.shown ~= nil end

function Cat:Page(key) return self[key] and self[key].sections and self[key] or self.VIEWS[key] end

-------------------------------------------------------------------------------
-- Rows of a section, built into real row tables (rows with no key in this build are dropped)
-------------------------------------------------------------------------------
-- the specs of a section: everyday rows, or the Advanced ones (never the other list by mistake)
local function specs(sec, advanced)
  if advanced then return sec.advanced or {} end
  return sec.rows or {}
end
Cat.Specs = specs

-- skipFront = the page: leave out the rows its gear shows first (the gear's More settings holds the rest)
-- all = true: the rows whether or not they are drawn now (a module that is off hides its rows): what Reset this page and Undo reach
function Cat:SectionRows(sec, advanced, skipFront, all)
  local out = {}
  local front = skipFront and self:FrontKeys(skipFront)
  for _, spec in ipairs(specs(sec, advanced)) do
    local row = self:Row(spec)
    -- a row this build never draws (a guild bank repair on Era, a map pin where the game has none) is not listed either
    if row and (all or not row.only or row.only()) and not (front and front[Cat.RowId(row)]) then out[#out + 1] = row end
  end
  return out
end

-------------------------------------------------------------------------------
-- The front of a gear (Step 2 B): the exact sizes, then the 5 or 6 common settings
-------------------------------------------------------------------------------
local function specKeyOf(spec)
  if type(spec) == "string" then return spec end
  if spec.type then return spec.key or spec.id end
  return spec[1]
end

-- the catalogue's own spec of a setting, wherever its section is
function Cat:FindSpec(key)
  for _, page in ipairs(self.PAGES) do
    for _, sec in ipairs(page.sections or {}) do
      for _, adv in ipairs({ false, true }) do
        for _, spec in ipairs(specs(sec, adv)) do
          if specKeyOf(spec) == key then return spec, sec, page, adv end
        end
      end
    end
  end
  return nil
end

-- the rows of the front: which = "exact" or "common". A front entry is a key or { key, "a plainer label" }; its row comes from the
-- section that owns the setting. A row this build does not draw is left out.
function Cat:FrontRows(page, which)
  local out = {}
  for _, entry in ipairs(page.front and page.front[which] or {}) do
    local key = specKeyOf(entry)
    local spec, sec = self:FindSpec(key)
    if spec and (not sec or self:SectionExists(sec)) then
      local row
      local label = (type(entry) == "table" and entry[2]) or (type(spec) == "table" and spec[2]) or nil
      if type(spec) == "table" and spec.type then
        row = {}
        for k, v in pairs(spec) do row[k] = v end
        if type(entry) == "table" and entry[2] then row.label = entry[2] end
        row.help = nil
        row = self:Row(row)
      else
        local over = { key }
        if label then over[2] = label end
        for _, src in ipairs({ spec, entry }) do
          if type(src) == "table" then for k, v in pairs(src) do if type(k) == "string" then over[k] = v end end end
        end
        row = self:Row(over)
      end
      if row and (not row.only or row.only()) then out[#out + 1] = row end
    end
  end
  return out
end

function Cat:FrontKeys(page)
  local keys = {}
  for _, which in ipairs({ "exact", "common" }) do
    for _, entry in ipairs(page.front and page.front[which] or {}) do keys[specKeyOf(entry)] = true end
  end
  -- Step 2 D: the rows of the page's panel section (the Look of the map) are in the front, drawn by the panel
  for _, sec in ipairs(page.sections or {}) do
    if sec.panel then for _, spec in ipairs(specs(sec, false)) do keys[specKeyOf(spec)] = true end end
  end
  return keys
end

-- how many settings sit under More settings: every setting of the page's sections that is not in the front (headings, small
-- headings and read-outs are not settings)
function Cat:MoreCount(page)
  local n = 0
  for _, sec in ipairs(self:Sections(page)) do
    for _, adv in ipairs({ false, true }) do
      for _, row in ipairs(self:SectionRows(sec, adv, page)) do
        if row.type ~= "heading" and row.type ~= "subheading" and row.type ~= "readout" then n = n + 1 end
      end
    end
  end
  return n
end

-- Every row that has a key, with where it lives: { page, section, row, advanced }
function Cat:AllRows()
  local out = {}
  for _, page in ipairs(self.PAGES) do
    for _, sec in ipairs(page.sections or {}) do
      for _, adv in ipairs({ false, true }) do
        for _, spec in ipairs(specs(sec, adv)) do
          local row = self:Row(spec)
          if row and row.type ~= "heading" and row.type ~= "subheading" then out[#out + 1] = { page = page, section = sec, row = row, advanced = adv } end
        end
      end
    end
  end
  return out
end

local function rowId(row) return row.key or row.id end
Cat.RowId = rowId

-- Current value of a row as plain words: On, Off, 70%, the chosen option, "" for an action.
function Cat:State(row)
  if row.type == "check" then
    local v
    if row.get then v = row.get() elseif row.key then v = Panoply.db and Panoply.db[row.key] end
    return v and "On" or "Off"
  elseif row.type == "slider" then
    local v = row.get and row.get() or (Panoply.db and Panoply.db[row.key])
    if type(v) ~= "number" then return "" end
    if row.fmt then return row.fmt:format(v) end
    return ("%d%%"):format(math.floor(v * 100 + 0.5))
  elseif row.type == "segmented" or row.type == "choice" then
    local v = row.get and row.get() or (Panoply.db and Panoply.db[row.key])
    for _, o in ipairs(row.values or {}) do if o[1] == v then return o[2] end end
    return tostring(v or "")
  elseif row.type == "button" then return "Button"
  end
  return ""
end

-------------------------------------------------------------------------------
-- Where is a setting? ("Guide > Arrow")
-------------------------------------------------------------------------------
local function specKey(spec)
  if type(spec) == "string" then return spec end
  if spec.type then return spec.key or spec.id end
  return spec[1]
end

-- Looks at the catalogue's own specs (no row is built), so it is safe to ask at load time.
function Cat:Find(key)
  if type(key) == "string" and key:find("^gatherShow:") then key = "gatherShow" end
  for _, page in ipairs(self.PAGES) do
    for _, sec in ipairs(page.sections or {}) do
      for _, adv in ipairs({ false, true }) do
        for _, spec in ipairs(specs(sec, adv)) do
          if specKey(spec) == key then return { page = page, section = sec, advanced = adv, key = key } end
        end
      end
    end
  end
  for _, page in ipairs(self.PAGES) do
    if page.key == key then return { page = page } end
    for _, c in ipairs(page.controls or {}) do if c.key == key then return { page = page, control = c } end end
    for _, sec in ipairs(page.sections or {}) do
      if sec.module and key == "module:" .. sec.module then return { page = page, section = sec } end
    end
    if page.module and key == "module:" .. page.module then return { page = page } end
  end
  return nil
end

function Cat:Path(key)
  local e = self:Find(key)
  if not e then return "Help" end
  if e.control or not e.section then return e.page.label end
  return e.page.label .. " > " .. e.section.title
end
function Panoply:SettingsPath(key) return Cat:Path(key) end

-------------------------------------------------------------------------------
-- Opening a setting (the window, its gear, the row)
-------------------------------------------------------------------------------
function Cat:Open(key)
  local e = self:Find(key)
  if not e then Panoply.Menu:Open() return end
  if e.control or not e.section then Panoply.Menu:Open(e.page.key) return end
  Panoply.Menu:OpenGear(e.page.key, e.section.key, key, e.advanced)
end

-------------------------------------------------------------------------------
-- Reset: a page's own settings back to Panoply Suite's standard (never another page's, never switches)
-------------------------------------------------------------------------------
local function defaultFor(key)
  local d = Panoply.defaults and Panoply.defaults.account and Panoply.defaults.account[key]
  if type(d) == "table" then return nil end
  return d
end

-- What Reset puts back: { key, default, set } for every setting row of the page that has a standard, wherever it is
-- saved (Panoply.db, the per-character file, the reports file); "gatherShow" stands for the four type checks.
function Cat:ResetItems(page, withShared)
  local items, seen = {}, {}
  local function add(row)
    -- a size shared by every window (the exact slider on a page that is not the Guide) is not this page's to reset
    if row.shared and not withShared then return end
    if row.type == "typechecks" then
      if not seen.gatherShow then seen.gatherShow = true items[#items + 1] = { key = "gatherShow" } end
    elseif row.key and (row.type == "check" or row.type == "slider" or row.type == "segmented" or row.type == "choice") and not seen[row.key] then
      local d = row.default
      if d == nil and not row.get then d = defaultFor(row.key) end
      if d ~= nil then seen[row.key] = true items[#items + 1] = { key = row.key, default = d, set = row.set, get = row.get } end
    end
  end
  -- every row of the page, whether its module is on or off: the settings are there and keep their values while the module is off, so
  -- Reset this page (and Undo) must reach them (a row hidden because its module is off is not a row that is reset less)
  for _, sec in ipairs(page.sections or {}) do
    if self:SectionExists(sec) then
      for _, adv in ipairs({ false, true }) do
        for _, row in ipairs(self:SectionRows(sec, adv, nil, true)) do add(row) end
      end
    end
  end
  -- the front of the gear: a page whose settings live in another page's section (Level together) is reset through it
  for _, which in ipairs({ "exact", "common" }) do
    for _, row in ipairs(self:FrontRows(page, which)) do add(row) end
  end
  return items
end

-- What the page's settings are right now (Undo my changes in the gear puts them back): { { item, value } }. The sizes shared by
-- every window are in it, because a size picked while the gear is open is a change to undo.
local function dcopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = dcopy(x) end
  return o
end
local function dsame(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not dsame(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function currentOf(it)
  if it.key == "gatherShow" then return dcopy(Panoply.db and Panoply.db.gatherShow) end
  if it.get then return dcopy(it.get()) end
  return dcopy(Panoply.db and Panoply.db[it.key])
end
function Cat:Snapshot(page)
  local snap = { page = page, list = {} }
  for _, it in ipairs(self:ResetItems(page, true)) do snap.list[#snap.list + 1] = { item = it, value = currentOf(it) } end
  return snap
end
function Cat:SnapshotChanged(snap)
  for _, e in ipairs(snap.list) do if not dsame(currentOf(e.item), e.value) then return true end end
  return false
end
function Cat:Restore(snap)
  local n = 0
  for _, e in ipairs(snap.list) do
    local it, want = e.item, e.value
    if not dsame(currentOf(it), want) then
      n = n + 1
      if it.key == "gatherShow" then
        if Panoply.Gathering then for _, t in ipairs(Panoply.Gathering.TYPES) do Panoply.Gathering:SetShown(t, type(want) ~= "table" or want[t] ~= false) end end
      elseif it.set then it.set(dcopy(want))
      else Panoply:SetOption(it.key, dcopy(want)) end
    end
  end
  return n
end

function Cat:PageKeys(page)
  local keys = {}
  for _, it in ipairs(self:ResetItems(page)) do keys[#keys + 1] = it.key end
  return keys
end

function Cat:ResetPage(page)
  local n = 0
  for _, it in ipairs(self:ResetItems(page)) do
    if it.key == "gatherShow" then
      if Panoply.Gathering then for _, t in ipairs(Panoply.Gathering.TYPES) do Panoply.Gathering:SetShown(t, true) end n = n + 1 end
    elseif it.set then it.set(it.default); n = n + 1
    else Panoply:SetOption(it.key, it.default); n = n + 1 end
  end
  -- Step 20 (0.9.4): the page's remembered tab and open sections go too (UI/Kit.lua); they are not settings, so n does not count them
  if Panoply.Kit and page and page.key then Panoply.Kit.ResetState(page.key) end
  return n
end

function Cat:ResetAll()
  local n = 0
  for _, page in ipairs(self.PAGES) do n = n + self:ResetPage(page) end
  Panoply:Print(("Panoply Suite settings are back to the standard (%d settings)."):format(n))
  return n
end

-------------------------------------------------------------------------------
-- The search ("All settings"): by name, by what it says, by everyday words; pages and actions too
-------------------------------------------------------------------------------
Cat.ACTIONS = {
  { id = "action:tour", label = "Take the tour", words = "help learn how", page = "help", run = function() Panoply.Tour:Start() end },
  { id = "action:setup", label = "Run setup again", words = "wizard help", page = "help", run = function() Panoply.Wizard:Start() end },
  { id = "action:report", label = "Report a problem", words = "bug wrong help", page = "help", run = function() Panoply.ReportWindow:Open() end },
  { id = "action:whatsnew", label = "What's new", words = "update changes new version help", page = "help", run = function() Panoply.WhatsNew:Show(true) end },
  { id = "action:selftest", label = "Check for problems", words = "self test help", page = "help", run = function() Panoply.SelfTest:Run() end },
}

function Cat:Index()
  local out = {}
  for _, page in ipairs(self:Existing()) do
    out[#out + 1] = { kind = "page", page = page, label = page.label, words = (page.text or "") .. (page.oldNames and (" " .. page.oldNames) or ""), key = "page:" .. page.key }
    for _, c in ipairs(page.controls or {}) do
      out[#out + 1] = { kind = "control", page = page, label = c.label, tip = c.tip, words = Cat.WORDS[c.key], key = c.key }
    end
    for _, sec in ipairs(self:Sections(page)) do
      for _, adv in ipairs({ false, true }) do
        for _, row in ipairs(self:SectionRows(sec, adv)) do
          if row.type == "typechecks" and Panoply.Gathering then
            -- the four type checks are four settings: Herbs, Ore veins, Fishing pools, Treasure chests
            local G = Panoply.Gathering
            for _, t in ipairs(G.TYPES) do
              local one = { type = "check", key = "gatherShow:" .. t, label = G.LABEL[t], get = function() return Panoply.db.gatherShow and Panoply.db.gatherShow[t] end }
              out[#out + 1] = { kind = "setting", page = page, section = sec, row = one, advanced = adv, label = G.LABEL[t],
                tip = "Show " .. G.LABEL[t]:lower() .. " on your maps.", words = "gathering herbs ore fish chest", key = one.key }
            end
          elseif row.type ~= "heading" and row.type ~= "subheading" and row.type ~= "readout" then
            local id = rowId(row)
            out[#out + 1] = { kind = "setting", page = page, section = sec, row = row, advanced = adv, label = row.searchLabel or row.label or id,
              tip = row.tip, words = Cat.WORDS[id] or Cat.WORDS[(id or ""):gsub("^action:", "")], key = id }
          end
        end
      end
    end
  end
  for _, a in ipairs(self.ACTIONS) do
    out[#out + 1] = { kind = "action", page = self.help, label = a.label, words = a.words, key = a.id, run = a.run }
  end
  return out
end

local function lower(s) return (s or ""):lower() end

-- results best first; each { entry, score, label }. Every word typed must be found somewhere.
function Cat:Search(text, max)
  local q = lower(text):gsub("^%s+", ""):gsub("%s+$", "")
  if #q < 2 then return {} end
  local toks = {}
  for w in q:gmatch("%S+") do toks[#toks + 1] = w end
  local out = {}
  for i, e in ipairs(self:Index()) do
    local label, words, tip = lower(e.label), lower(e.words), lower(e.tip)
    local sec, page = lower(e.section and e.section.title), lower(e.page and e.page.label)
    local score, ok = 0, true
    for _, t in ipairs(toks) do
      local s = 0
      if label:find(t, 1, true) then
        s = 10
        if label:find("^" .. t:gsub("%p", "%%%0")) or label:find("[%s%p]" .. t:gsub("%p", "%%%0")) then s = 14 end
      end
      if s < 7 and words:find(t, 1, true) then s = 7 end
      if s < 4 and (sec:find(t, 1, true) or page:find(t, 1, true)) then s = 4 end
      if s < 2 and tip:find(t, 1, true) then s = 2 end
      if s == 0 then ok = false break end
      score = score + s
    end
    if ok then
      if e.kind == "page" then score = score + 1 end
      out[#out + 1] = { entry = e, score = score - #label * 0.01, order = i }
    end
  end
  table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.order < b.order end)
  max = max or 12
  for i = #out, max + 1, -1 do out[i] = nil end
  return out
end
