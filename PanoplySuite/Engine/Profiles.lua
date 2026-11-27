-- Panoply Suite profiles (SPEC section 29). A profile is a name plus a snapshot of SETTINGS. Each character uses
-- one profile; a character that has never picked uses "Default".
--
-- How it works: the live settings stay where the add-on always read them (PanoplySuiteDB, plus the window
-- positions in PanoplySuiteCharDB), so no other code changed. A profile is a saved copy of the covered ones
-- (P.ACCOUNT_KEYS, the module switches, the page order, the window places; SPEC 29.1). The copy of the
-- profile a character uses is refreshed when it logs out, before it switches profile and before a copy of
-- that profile is made; it is applied at login (before any window exists) and at once when the character
-- switches. WINDOW PLACES are different: they stay with each character. A login never applies places and a
-- logout never saves them; they follow a profile only when a character switches (the places it leaves are
-- saved into the profile it leaves, the new profile's places are applied) or copies a profile (the same SetOption / module switch the gear uses, so nothing needs a /reload). Per-character data
-- (quest progress, plan and step, Hearth Hall items, recordings, level times, partner, auction data) is never
-- in a snapshot.
--
-- Saved (account-wide) in PanoplySuiteDB.profiles, created on first use and never written by anything else:
--   { v = 1,
--     list = { [name] = { made = <time>, from = <name copied from, or nil>, settings = <snapshot, or nil = never saved> } },
--     use  = { [realm .. "\1" .. character] = <profile name> } }   -- no entry = "Default"
--   snapshot = { v = 1, t = <time>, set = { [key] = value }, modules = { [module] = bool }, menu = { order, hidden },
--                pos = { [key] = value } }   -- a key that is missing means Panoply Suite's standard value
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = {}
Panoply.Profiles = P

P.VERSION = 1
P.DEFAULT = "Default"
P.MAX_NAME = 24
P.MAX_PROFILES = 24

local function now() return _G.time and time() or 0 end
local function lower(s) return (s or ""):lower() end

function P.Key(realm, name) return tostring(realm) .. "\1" .. tostring(name) end

-- The saved table, made on first use; "Default" always exists.
function P:Data()
  local db = Panoply.db
  if not db then return nil end
  local d = db.profiles
  if type(d) ~= "table" then d = {} db.profiles = d end
  if d.v == nil then d.v = P.VERSION end
  if type(d.list) ~= "table" then d.list = {} end
  if type(d.use) ~= "table" then d.use = {} end
  if type(d.list[P.DEFAULT]) ~= "table" then d.list[P.DEFAULT] = { made = now() } end
  return d
end

-- Names, "Default" first and the rest A to Z.
function P:Names()
  local d = self:Data()
  local out = {}
  if not d then return out end
  for name in pairs(d.list) do if name ~= P.DEFAULT then out[#out + 1] = name end end
  table.sort(out, function(a, b)
    local la, lb = lower(a), lower(b)
    if la ~= lb then return la < lb end
    return a < b
  end)
  table.insert(out, 1, P.DEFAULT)
  return out
end

function P:Exists(name)
  local d = self:Data()
  return d ~= nil and type(name) == "string" and type(d.list[name]) == "table"
end

function P:Count() return #self:Names() end

-- A name the player typed, made safe: trimmed, spaces folded, control characters out. Returns the name or nil, why.
function P.Clean(text)
  local s = tostring(text or "")
  -- no "|": the game reads |c...|r, |H...|h and |T...|t in any text, so a name must not carry them
  s = s:gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil, "Type a name first." end
  -- letters, not bytes: an accented letter is two or three bytes
  local letters = select(2, s:gsub("[^\128-\191]", ""))
  if letters > P.MAX_NAME then return nil, ("Names can be at most %d letters."):format(P.MAX_NAME) end
  return s
end

-- Can this be the name of a profile (other than `except`, which may keep its own name)?
function P:Valid(text, except)
  local s, why = P.Clean(text)
  if not s then return nil, why end
  for _, n in ipairs(self:Names()) do
    if lower(n) == lower(s) and n ~= except then return nil, ("There is already a profile called %s."):format(n) end
  end
  return s
end

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deepcopy(x) end
  return o
end

function P:New(text)
  local d = self:Data()
  if not d then return nil, "Panoply Suite is still loading." end
  if self:Count() >= P.MAX_PROFILES then return nil, ("You can have at most %d profiles."):format(P.MAX_PROFILES) end
  local name, why = self:Valid(text)
  if not name then return nil, why end
  d.list[name] = { made = now() }
  Panoply:Fire("PROFILES_CHANGED", "new", name)
  return name
end

-- A new profile that starts as a copy of another one's saved settings.
function P:Copy(from, text)
  local d = self:Data()
  if not (d and self:Exists(from)) then return nil, "That profile is gone." end
  -- copying the profile this character uses copies what it is set to right now
  local mr, mn = self:Me()
  if mr and self:Of(mr, mn) == from then self:SaveCurrent(true) end
  local name, why = self:New(text)
  if not name then return nil, why end
  d.list[name].from = from
  d.list[name].settings = deepcopy(d.list[from].settings)
  return name
end

function P:Rename(old, text)
  local d = self:Data()
  if not (d and self:Exists(old)) then return nil, "That profile is gone." end
  if old == P.DEFAULT then return nil, "Default keeps its name." end
  local name, why = self:Valid(text, old)
  if not name then return nil, why end
  if name == old then return name end
  d.list[name], d.list[old] = d.list[old], nil
  for k, v in pairs(d.use) do if v == old then d.use[k] = name end end
  for _, rec in pairs(d.list) do if rec.from == old then rec.from = name end end
  -- "my usual" in the setup (UI/Wizard.lua) names a profile: it follows the rename
  local last = Panoply.db.setupLast
  if type(last) == "table" and last.profile == old then last.profile = name end
  Panoply:Fire("PROFILES_CHANGED", "rename", name, old)
  return name
end

-- Deleting hands its characters to `moveTo` (0.9.5 phase 4F: the player picks it in the question; Default when none is given).
-- Returns how many characters were moved. When the character being played used it, the new profile's settings are applied to it
-- now (what it was set to is deleted with it).
function P:Delete(name, moveTo)
  local d = self:Data()
  if not (d and self:Exists(name)) then return nil, "That profile is gone." end
  if name == P.DEFAULT then return nil, "Default cannot be deleted." end
  moveTo = moveTo or P.DEFAULT
  if moveTo == name then return nil, "Pick another profile for its characters." end
  if not self:Exists(moveTo) then return nil, "That profile is gone." end
  local mr, mn = self:Me()
  local mine = mr and self:Of(mr, mn) == name
  local moved = 0
  for k, v in pairs(d.use) do
    if v == name then d.use[k] = moveTo ~= P.DEFAULT and moveTo or nil moved = moved + 1 end
  end
  for _, rec in pairs(d.list) do if rec.from == name then rec.from = nil end end
  -- as for its characters: "my usual" follows them
  local last = Panoply.db.setupLast
  if type(last) == "table" and last.profile == name then last.profile = moveTo end
  d.list[name] = nil
  if mine and self.loggedIn then self:Apply(moveTo, "live") end
  Panoply:Fire("PROFILES_CHANGED", "delete", name)
  return moved
end

-- Back to Panoply Suite's standard settings: what the profile holds becomes the standard (an empty snapshot).
-- When the character being played uses it, the standard settings are applied to it now.
function P:ResetToDefaults(name)
  local d = self:Data()
  if not (d and self:Exists(name)) then return nil, "That profile is gone." end
  d.list[name].settings = self:Standard()
  local mr, mn = self:Me()
  if mr and self:Of(mr, mn) == name and self.loggedIn then self:Apply(name, "live") end
  Panoply:Fire("PROFILES_CHANGED", "reset", name)
  return true
end

-------------------------------------------------------------------------------
-- Which character uses which
-------------------------------------------------------------------------------
-- The profile a character uses ("Default" when it never picked one, or when its profile is gone).
function P:Of(realm, name)
  local d = self:Data()
  if not d then return P.DEFAULT end
  local p = d.use[P.Key(realm, name)]
  if p and type(d.list[p]) == "table" then return p end
  return P.DEFAULT
end

function P:Use(realm, name, profile)
  local d = self:Data()
  if not (d and realm and name) then return false end
  if not self:Exists(profile) then return false end
  local was = self:Of(realm, name)
  d.use[P.Key(realm, name)] = profile ~= P.DEFAULT and profile or nil
  if was ~= profile then Panoply:Fire("PROFILES_CHANGED", "use", profile, realm, name) end
  return true
end

-- (Step 2 B-08's "Copy settings to my other characters", P:CopyTo, is gone in 0.9.5 phase 4F: spec 01 section 6 replaces it with a
-- profile dropdown on each character row of the Profiles page, which calls P:Use, and Duplicate for a copy of a profile.)

-- The character being played: realm, name (nil until the game says who it is).
function P:Me()
  local ok, info = pcall(C.PlayerInfo)
  if not (ok and type(info) == "table") then return nil end
  if type(info.name) ~= "string" or info.name == "" or type(info.realm) ~= "string" or info.realm == "" then return nil end
  return info.realm, info.name, info
end

-- Every character Panoply Suite knows (Hearth Hall's saved ones, and the one being played), name order.
-- { realm, name, me, classFile, level }
function P:Characters()
  local out, seen = {}, {}
  local mr, mn, mi = self:Me()
  local Alts = Panoply.Alts
  if Alts and Alts.List then
    local ok, list = pcall(Alts.List, Alts)
    if ok and type(list) == "table" then
      for _, e in ipairs(list) do
        local k = P.Key(e.realm, e.name)
        if not seen[k] then
          seen[k] = true
          out[#out + 1] = { realm = e.realm, name = e.name, me = (e.realm == mr and e.name == mn), classFile = e.classFile, level = e.level }
        end
      end
    end
  end
  if mr and not seen[P.Key(mr, mn)] then
    out[#out + 1] = { realm = mr, name = mn, me = true, classFile = mi and mi.classFile, level = mi and mi.level }
  end
  table.sort(out, function(a, b)
    if a.me ~= b.me then return a.me end
    if lower(a.name) ~= lower(b.name) then return lower(a.name) < lower(b.name) end
    return a.realm < b.realm
  end)
  return out
end

-- The characters that use a profile.
function P:UsedBy(profile)
  local out = {}
  for _, c in ipairs(self:Characters()) do
    if self:Of(c.realm, c.name) == profile then out[#out + 1] = c end
  end
  return out
end

-------------------------------------------------------------------------------
-- What a profile covers (SPEC 29.1)
-------------------------------------------------------------------------------
-- PanoplySuiteDB keys: every setting that has a row in a page's gear, except the ones named in P.NOT_COVERED, plus
-- the settings that have no row (the extras at the end). Sorted. tests/profiles_tests.lua compares this list with
-- the catalogue so a setting added later cannot be forgotten.
P.ACCOUNT_KEYS = {
  "arrowAlpha", "arrowLocked", "arrowScale", "arrowShown", "auctionAutoScan", "auctionPassive", "auctionSlowScan", "auctionUndercut",
  "autoAccept", "autoExtendPlan", "autoFly", "autoRepair", "autoReplan", "autoSelectSingleReward", "autoSellJunk",
  "autoSkipTrivial", "autoTurnIn", "bagColumns", "bagDragDrop", "bagReplaceDefault", "bagTooltipCounts", "bankColumns",
  "blizzWaypoint", "corpseArrow", "dropOnReplan", "gatherDatabase", "gatherEdgeFade", "gatherFadeNear", "gatherFadeYards",
  "gatherMinimap", "gatherMinimapYards", "gatherMmAlpha", "gatherMmSize", "gatherRings", "gatherShare", "gatherSkillFilter",
  "gatherWmAlpha", "gatherWmSize", "gatherWorldMap",
  "glowBadges", "glowDefaultFrames", "glowPoor", "glowStrength", "groupQuests", "guideWindowSize", "guildRepair", "hallMail", "hallMailDays", "hallPlayed", "hallRestGuess",
  "hideArrowInCombat", "hideInCombat", "homeAuction", "homeBags", "homeGold", "homeNeeds", "homeNext", "iconStyle", "minimapButton", "paceLearn",
  "paceShown", "paceSource", "priceSource", "profAuctionCost", "profBlizzardToo", "profStrategy", "profTracker",
  "profWindowLocked", "questRecorder", "questRecorderNotice", "routeFlights",
  "routeHearth", "routeLearnFP", "routeRoads", "routeSteps", "routeTransports", "sellUnusable", "showCrest", "soundOnStep",
  "specNextCard", "specOutline", "stepsShown", "syncAdoptPartnerPlan", "syncEnabled", "syncWaitForPartner", "toasts",
  "tooltipAuction", "tooltipVendor", "trackerAutoTrack", "trackerBgAlpha", "trackerFontSize",
  "trackerHideBG", "trackerHideBlizzard", "trackerHideDungeon", "trackerItems", "trackerLocked", "trackerOutline",
  "trackerParty", "trackerShowAll", "trackerSort", "trailAnimate", "trailMinimap",
  "trailMmAlpha", "trailMmSize", "trailWmAlpha", "trailWmSize", "trailWorldMap", "trainerArrowOffer", "trainerLearnNext", "trainerMenuLine", "trainerMoneyWarn", "trainerMountFund",
  "trainerPanel", "trainerProfPanel", "trainerReserve", "trainerShowSkip", "trainerToast", "tripShown", "wayMapClick",
  "waySlash", "wayWmAlpha", "wayWmSize", "windowAlpha", "windowFade", "windowFadeAlpha", "windowLocked", "windowScale",
  -- settings with no row in a gear (a command, a control on a page, or a built-in limit)
  "autoOnlyPlanQuests", "hallSort", "levelStats", "minimapAngle", "plannerHorizon", "plannerLogSize",
  -- a table of its own (the four gathering types shown)
  "gatherShow",
}
-- A module that owns settings registers their keys here from its own file (QuestPins does for its qp* keys), so
-- this file never has to name what only that module may name. Keys are kept sorted and listed once.
function P:AddKeys(list)
  local have = {}
  for _, k in ipairs(P.ACCOUNT_KEYS) do have[k] = true end
  for _, k in ipairs(list) do
    if not have[k] then P.ACCOUNT_KEYS[#P.ACCOUNT_KEYS + 1] = k have[k] = true end
  end
end

-- 0.9.7 (Nov 18 2026): settings that are gone. They are not captured, applied or read any more, but a value a saved copy of a
-- profile already holds is carried along untouched (P:SaveCurrent), as the account's own saved value is (Core/Init.lua).
P.RETIRED_KEYS = { "levellingStyle" }

-- 0.9.7: settings a profile carried once and must not any more (partyShare: what you share with other players is the account's
-- own choice, Engine/PanoplyGuideParty.lua names it in P.NOT_COVERED). Not captured or applied; a value a saved copy of a profile
-- already holds is ignored and carried along untouched (P:SaveCurrent), never deleted from the save.
P.DROPPED_KEYS = { "partyShare" }

-- Gear rows that are NOT in a profile, and why.
P.NOT_COVERED = {
  send = "Reports and privacy are saved in PanoplySuiteReportsDB and stay the same for the whole account",
  captureErrors = "Reports and privacy (same file)",
  chatNotice = "Reports and privacy (same file)",
  profGuide = "kept per character (each guide keeps its own step)",
  profSpec = "the Blacksmithing specialty is a fact about one character",
  syncPartner = "who your partner is belongs to the character, not to a layout",
  routeSource = "which leveling route a character follows is that character's own choice (saved per character, as /panoply route saves it); a profile must never put another character on the planner",
  guideSource = "WoW Forever: which guide a character follows (the leveling guide or an added one) is that character's own place in the guide engine's saved data, not a setting of ours",
}
-- PanoplySuiteCharDB: where this character put its windows, and how big (applied by P:PlaceWindows).
P.PLACE_KEYS = { "window", "windowSize", "arrowPos", "trackerPos", "trackerHeight", "trackerWidth", "profWindowPos" }   -- trackerWidth: Nov 2026

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
P.DeepCopy, P.Same = copy, same

local function standardValue(key) return copy(Panoply.defaults and Panoply.defaults.account and Panoply.defaults.account[key]) end

-- A snapshot of what the live settings are right now.
function P:Capture()
  local db, cdb = Panoply.db, Panoply.cdb
  local snap = { v = 1, t = now(), set = {}, modules = {}, menu = { order = {}, hidden = {} }, pos = {} }
  if not db then return snap end
  for _, k in ipairs(P.ACCOUNT_KEYS) do
    if db[k] ~= nil then snap.set[k] = copy(db[k]) end
  end
  snap.modules = copy(type(db.modules) == "table" and db.modules or {})
  local m = type(db.menu) == "table" and db.menu or {}
  snap.menu = { order = copy(type(m.order) == "table" and m.order or {}), hidden = copy(type(m.hidden) == "table" and m.hidden or {}),
    sections = copy(type(m.sections) == "table" and m.sections or {}) }   -- 0.9.5: the pages moved to another section of the list
  for _, k in ipairs(P.PLACE_KEYS) do
    if cdb and cdb[k] ~= nil then snap.pos[k] = copy(cdb[k]) end
  end
  return snap
end

-- Panoply Suite's standard settings: an empty snapshot (a missing key means the standard value).
function P:Standard() return { v = 1, t = now(), set = {}, modules = {}, menu = { order = {}, hidden = {} }, pos = {} } end

-- Refresh the saved copy of the profile the character being played uses. The window places are kept as the profile
-- had them unless withPlaces (a switch away from it, or a copy of it): a logout or a change in a gear never writes
-- this character's places into a profile other characters share.
function P:SaveCurrent(withPlaces)
  local d = self:Data()
  local mr, mn = self:Me()
  if not (d and mr and self.loggedIn) then return false end
  local rec = d.list[self:Of(mr, mn)]
  if not rec then return false end
  local old = rec.settings
  local snap = self:Capture()
  if not withPlaces and type(old) == "table" and type(old.pos) == "table" then snap.pos = copy(old.pos) end
  if type(old) == "table" and type(old.set) == "table" then
    for _, k in ipairs(P.RETIRED_KEYS) do if old.set[k] ~= nil and snap.set[k] == nil then snap.set[k] = copy(old.set[k]) end end
    for _, k in ipairs(P.DROPPED_KEYS) do if old.set[k] ~= nil then snap.set[k] = copy(old.set[k]) end end
  end
  rec.settings = snap
  return true
end

-- Where the windows go (live): each one that exists is placed again from PanoplySuiteCharDB. In combat it waits.
function P:PlaceWindows()
  local C = Panoply.Compat
  if C.InCombat and C.InCombat() then self.placePending = true return false end
  self.placePending = nil
  local function try(name, fn, ...) if fn then local ok, err = pcall(fn, ...) if not ok then Panoply:Debug("profile place", name, err) end end end
  if Panoply.UI and Panoply.UI.ApplySavedPlace then try("guide window", Panoply.UI.ApplySavedPlace, Panoply.UI) end
  if Panoply.Arrow and Panoply.Arrow.ApplySavedPlace then try("arrow", Panoply.Arrow.ApplySavedPlace, Panoply.Arrow) end
  if Panoply.ProfTracker and Panoply.ProfTracker.ApplySavedPlace then try("profession tracker", Panoply.ProfTracker.ApplySavedPlace, Panoply.ProfTracker) end
  local QT = Panoply.QuestTracker
  if QT and QT.frame then try("quest tracker", QT.ApplyPosition, QT) try("quest tracker size", QT.Layout, QT) end
  local PW = Panoply.ProfWindow
  if PW and PW.frame and PW.frame:IsShown() and PW.Anchor then try("profession window", PW.Anchor, PW) end
  if Panoply.Minimap and Panoply.Minimap.Position then try("minimap button", Panoply.Minimap.Position, Panoply.Minimap) end
  return true
end
Panoply:On("PLAYER_REGEN_ENABLED", function() if P.placePending then P:PlaceWindows() end end)

-- Apply a profile's settings. mode "login": plain writes before any window exists. mode "live": the same calls the
-- gear makes (the row's own set, else Panoply:SetOption), module switches through Panoply.Modules, windows placed again.
-- Window places are applied only in live mode (a switch, Delete or Reset); a login never touches them.
-- Returns how many settings changed.
function P:Apply(name, mode, opts)
  local d = self:Data()
  local db, cdb = Panoply.db, Panoply.cdb
  if not (d and db) then return 0 end
  local rec = d.list[name] or d.list[P.DEFAULT]
  local snap = rec and rec.settings or self:Standard()
  if type(snap) ~= "table" or type(snap.set) ~= "table" then snap = self:Standard() end
  opts = opts or {}
  local live = mode == "live"
  local changed = 0
  -- SetOption and the icon style hook mark "the player chose this" (autoFlyTouched, iconStyleTouched), which the one-time
  -- migrations read; applying a profile is not that choice, so the flags are put back exactly as they were
  local touched = { autoFlyTouched = db.autoFlyTouched, iconStyleTouched = db.iconStyleTouched }
  local Cat = live and Panoply.Catalog
  local reg = Cat and Cat.Registry and Cat:Registry() or {}
  for _, k in ipairs(P.ACCOUNT_KEYS) do
    local want = snap.set[k]
    if want == nil then want = standardValue(k) end
    if not same(db[k], want) then
      changed = changed + 1
      if k == "gatherShow" then
        if live and Panoply.Gathering and Panoply.Gathering.SetShown and Panoply.Gathering.TYPES then
          for _, t in ipairs(Panoply.Gathering.TYPES) do Panoply.Gathering:SetShown(t, type(want) ~= "table" or want[t] ~= false) end
        else db[k] = copy(want) end
      elseif live then
        local row = reg[k]
        if row and row.set then
          local ok, err = pcall(row.set, copy(want))
          if not ok then Panoply:Debug("profile apply", k, err) Panoply:SetOption(k, copy(want)) end
        else Panoply:SetOption(k, copy(want)) end
        if not same(db[k], want) then db[k] = copy(want) end
      else db[k] = copy(want) end
    end
  end
  -- module switches (the On / Off of each page's feature)
  local want = type(snap.modules) == "table" and snap.modules or {}
  db.modules = type(db.modules) == "table" and db.modules or {}
  local seen = {}
  for k in pairs(db.modules) do seen[k] = true end
  for k in pairs(want) do seen[k] = true end
  for k in pairs(seen) do
    if db.modules[k] ~= want[k] then
      changed = changed + 1
      local M = Panoply.Modules
      if live and M and M.byKey and M.byKey[k] then
        if want[k] == nil then
          db.modules[k] = nil
          M:Apply(M.byKey[k])
          Panoply:Fire("OPTION_CHANGED", "module:" .. k, M:Wanted(k))
        else M:Set(k, want[k]) end
      else db.modules[k] = want[k] end
    end
  end
  -- the order of the pages and the hidden ones (not the page last used, not the one-time note)
  db.menu = type(db.menu) == "table" and db.menu or {}
  local m = type(snap.menu) == "table" and snap.menu or {}
  local order, hidden = copy(type(m.order) == "table" and m.order or {}), copy(type(m.hidden) == "table" and m.hidden or {})
  local sections = copy(type(m.sections) == "table" and m.sections or {})
  if not (same(db.menu.order or {}, order) and same(db.menu.hidden or {}, hidden) and same(db.menu.sections or {}, sections)) then
    changed = changed + 1
    db.menu.order, db.menu.hidden, db.menu.sections = order, hidden, sections
    if live and Panoply.Menu and Panoply.Menu.frame and Panoply.Menu.LayoutList then Panoply.Menu:LayoutList() end
  end
  -- where the windows are
  if cdb and live then
    local pos = type(snap.pos) == "table" and snap.pos or {}
    local moved
    for _, k in ipairs(P.PLACE_KEYS) do
      if not same(cdb[k], pos[k]) then cdb[k] = copy(pos[k]) moved = true end
    end
    if moved then changed = changed + 1 end
    self:PlaceWindows()
  end
  db.autoFlyTouched, db.iconStyleTouched = touched.autoFlyTouched, touched.iconStyleTouched
  if Panoply.Prices and Panoply.Prices.CleanSource then Panoply.Prices.CleanSource(db) end   -- an old profile cannot bring back a source that is gone
  if live then Panoply:Fire("PROFILE_APPLIED", name) end
  return changed
end

-- Switch the character being played to another profile now: what it is set to is saved into the profile it
-- leaves, then the new profile's settings are applied. Returns true, how many settings changed.
function P:Switch(profile)
  local mr, mn = self:Me()
  if not (mr and self:Exists(profile)) then return false end
  local was = self:Of(mr, mn)
  if was == profile then return true, 0 end
  self:SaveCurrent(true)
  self:Use(mr, mn, profile)
  return true, self:Apply(profile, "live")
end

-- Login (before any window exists): the first time ever, what the character is set to IS Default, so nothing
-- changes; after that its profile's settings are applied. Window places are never applied at login: each character
-- keeps its own (an existing account looks exactly the same after updating, and characters on one profile do not
-- move each other's windows).
function P:OnLogin()
  local d = self:Data()
  local mr, mn = self:Me()
  if not (d and mr and Panoply.db and Panoply.cdb) then return false end
  local use = self:Of(mr, mn)
  local rec = d.list[use]
  if rec.settings == nil and use == P.DEFAULT then
    rec.settings = self:Capture()
  else
    self:Apply(use, "login")
  end
  self.loggedIn = true
  return true
end
Panoply:On("PLAYER_LOGOUT", function() P:SaveCurrent() end)
-- A change made in the gear is also kept soon after (two seconds, once per burst), so the saved copy is never far behind
-- the live settings even if a logout never gets to run it.
local pendingSave
local function later()
  if pendingSave then return end
  pendingSave = true
  C.After(2, function() pendingSave = nil P:SaveCurrent() end)
end
Panoply:Listen("OPTION_CHANGED", later)
Panoply:Listen("MODULE_CHANGED", later)
