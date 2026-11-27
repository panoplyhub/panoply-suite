-- Panoply Suite slash commands: /panoply (/ps, its short form from 0.8.0, was dropped in 0.9.9.5; the old /hp and /hearthpath still work, unadvertised)
local ADDON, Panoply = ...
local C, U = Panoply.Compat, Panoply.Util

-- 0.9.5 phase 4A4 (spec 06 section 2.3): every command registers its usage line and what it does in the command registry
-- (Panoply.Help:Command, Core/HelpRegistry.lua). chat is the line /panoply help prints (unchanged from 0.9.4); the commands with page fields
-- are also on the Help page's list, grouped, with their other names. order keeps /panoply help in this order, before the modules' lines.
local Help = Panoply.Help
local CMDS = {
  { key = "open", usage = "/panoply", desc = "Open Panoply Suite (every page, and every setting behind its gear).", group = "open",
    chat = "/panoply - open Panoply Suite (the Guide, Muster (your characters and bags), professions, Profiles and every setting behind each page's gear)" },
  { key = "settings", usage = "/panoply settings arrow", desc = "Open Panoply Suite with the All settings box ready, and the word typed in it.", group = "open",
    chat = "/panoply settings [word] - open Panoply Suite with the All settings box ready; a word types it in (/panoply settings arrow)" },
  { key = "guide", usage = "/panoply guide", desc = "Show or hide the guide window.", group = "guide",
    chat = "/panoply guide - show or hide the guide window" },
  { key = "guidewhich", page = false, chat = "/panoply guide leveling | professions [name] | both - which guide the step window follows" },
  { key = "route", page = false, chat = "/panoply route - say which leveling route this character follows: the written leveling guides for your race and faction, from where this character is;  route guides - keep the written guide in new zones it does not go to as well;  route auto - back to the default" },
  { key = "switch", usage = "/panoply switch", desc = "Flip the guide between levelling and your profession.", group = "guide",
    chat = "/panoply switch - flip between the levelling and the profession guide" },
  { key = "setup", usage = "/panoply setup", desc = "Run the quick setup again.", group = "help",
    chat = "/panoply setup - run the quick setup again" },
  { key = "tour", usage = "/panoply tour", desc = "Take the tour again.", group = "help",
    chat = "/panoply tour - the short tour of everything Panoply Suite does (also on the Help page)" },
  { key = "replan", usage = "/panoply replan", desc = "Plan a fresh route from where you are.", group = "guide",
    chat = "/panoply replan - pick the written guide up again from where this character is (never back at the start zone)" },
  { key = "next", usage = "/panoply next   /panoply prev", desc = "Move one step forward or back.", group = "guide",
    chat = "/panoply next | prev - move one step" },
  { key = "prof", page = false, chat = "/panoply prof <profession> [scratch] [target] - print a profession plan" },
  { key = "proftrack", page = false, chat = "/panoply prof track <profession> - the profession your guide follows" },
  { key = "profmode", page = false, chat = "/panoply prof mode interleave | only | off - mix profession steps with levelling, professions only, or tracker only" },
  { key = "profhow", page = false, chat = "/panoply prof fastest | cheapest - how the plan picks recipes" },
  { key = "profnow", page = false, chat = "/panoply prof now | later - show the profession step now, or hide it for 15 minutes" },
  { key = "proftracker", page = false, chat = "/panoply prof tracker - show or hide the profession tracker" },
  { key = "price", page = false, chat = "/panoply price \"Item Name\" <copper> - set your own Auction House price" },
  { key = "sync", page = false, chat = "/panoply sync - show partner status" },
  { key = "source", page = false, chat = "/panoply source leveling | added - WoW Forever: which guide to follow" },   -- Nov 14 2026 (step 21): /panoply panoplyguide (engine and credits) still works but is not advertised
  { key = "arrow", usage = "/panoply arrow lock", desc = "Lock the arrow in place (/panoply arrow unlock, /panoply arrow reset).", group = "guide",
    chat = "/panoply arrow - toggle the arrow;  /panoply arrow lock | unlock | reset" },
  { key = "way", group = "waypoints", module = "waypoints",
    chat = "/panoply way 45.2 61.8 [zone] [note] - set a waypoint (also /way);  /panoply way list | clear",
    usage = "/way 45.2 61.8",
    aliases = { "/panoply way" },
    desc = "Set a waypoint; the arrow takes you there. /way list shows them, /way clear removes them." },
  { key = "spot", page = false, chat = "/panoply spot - save the place you stand at as a spot of your own;  spot <name>;  spot <zone> <x> <y> <name>;  spot list" },
  { key = "fav", page = false, chat = "/panoply fav - your map favorites;  fav here - add where you stand;  fav target - add your target;  fav import - add a shared line" },
  { key = "bags", usage = "/panoply bags   /panoply bank", desc = "Open your bags, or your saved bank from anywhere.", group = "items", module = "bags",
    chat = "/panoply bags | bank - open your bags or your (saved) bank" },
  { key = "muster", usage = "/panoply muster", desc = "Open Muster: all your characters, their gold, professions, bags, bank and mail. Add an item's name to find it.", group = "open", module = "alts", aliases = { "/panoply hall", "/hearthhall" },
    chat = "/panoply muster [item] - open Muster (all your characters; also /panoply hall and /hearthhall); with an item's name it finds it on any character" },
  { key = "junk", usage = "/panoply junk", desc = "Sell grey items now (at a vendor).", group = "items", module = "merchant",
    chat = "/panoply junk - sell junk now (at a vendor)" },
  { key = "modules", page = false, chat = "/panoply modules - list the suite's modules and whether they are on" },
  { key = "minimap", page = false, chat = "/panoply minimap - show or hide the minimap button" },
  { key = "scale", page = false, chat = "/panoply scale 0.9 - size of every Panoply Suite window (0.4 to 2)" },
  { key = "selftest", usage = "/panoply selftest", desc = "Check that Panoply Suite works on this game version; the result is printed in chat.", group = "help",
    chat = "/panoply selftest - check the addon works on this game" },
  { key = "probe", page = false, chat = "/panoply probe - ask this game what it shares with add-ons and save the answers (for building Panoply Suite);  probe show - what was found;  probe clear - forget it" },
  { key = "mapdebug", page = false, chat = "/panoply mapdebug - with the world map open: save what the route trail drew (for a bug report), print a summary and lay our road points over the map;  /panoply mapdebug roads - toggle only the road points;  /panoply mapdebug off - remove them" },
  { key = "rares", page = false, chat = "/panoply rares - the rare creatures of the zone you are in, and when you last saw each" },
  { key = "trip", page = false, chat = "/panoply trip - show or hide the trip details (legs and times)" },
  { key = "pace", page = false, chat = "/panoply pace - what Panoply Suite has learned about your pace;  /panoply pace reset - forget it" },
  { key = "calib", page = false, chat = "/panoply calib - the travel measurements (speed, pace, minimap, hearthstone, recorder)" },
  { key = "record", page = false, chat = "/panoply record [name] | stop | list | clear - save your walked path so a road can be added later (position only)" },
  { key = "levelstats", page = false, chat = "/panoply levelstats - your real time per level against the simulator;  levelstats levels | zones | on | off | reset" },
  { key = "noguide", page = false, chat = "/panoply noguide - the 'no guide for this area yet' state;  noguide record on | off;  noguide off | on (turn the guide off or on in this zone)" },
  { key = "recorded", page = false, chat = "/panoply recorded - WoW Forever: the quests the recorder saved for new zones and the Skyborne;  recorded clear | on | off | notice off" },
  { key = "debug", page = false, chat = "/panoply debug apis | on | off | log" },
  { key = "report", usage = "/panoply report", desc = "Report a problem with the current step (/panoply report general for anything else, /panoply report feedback for an idea).", group = "help",
    chat = "/panoply report [general] - report a problem with the current step, or anything else" },   -- [reports] merge: SPEC-REPORTS
  { key = "reset", page = false, chat = "/panoply reset - forget this character's route" },
  { key = "import", page = false, chat = "/panoply import - where bringing across your old Hearthpath settings stands" },
  -- not in the 0.9.4 chat list: Help page rows only
  { key = "class", usage = "/panoply class [talents | spells | play | gear | pet]", desc = "Open the Class page: your plan, talents, spells to buy, how to play, gear and pet.", group = "open", chat = false },
  { key = "talents", usage = "/panoply talents", desc = "Open the Class page on Talents.", group = "open", chat = false },
  { key = "spells", usage = "/panoply spells", desc = "Open the Class page on Spells: what to buy at each trainer visit.", group = "open", chat = false },
  { key = "help", usage = "/panoply help", desc = "Every command, printed in chat.", group = "help", chat = false },
}
for i, c in ipairs(CMDS) do c.order = 100 + i Help:Command(c) end

-- Split into words; "double quoted text" stays one argument.
local function parseArgs(msg)
  local args = {}
  local rest = msg or ""
  while true do
    rest = rest:gsub("^%s+", "")
    if rest == "" then break end
    local q, after = rest:match('^"([^"]*)"(.*)$')
    if q then args[#args + 1] = q; rest = after
    else
      local w, after2 = rest:match("^(%S+)(.*)$")
      args[#args + 1] = w; rest = after2
    end
  end
  return args
end
Panoply.ParseSlashArgs = parseArgs

function Panoply:Slash(msg)
  local args = parseArgs(msg)
  local cmd = (args[1] or ""):lower()
  if cmd == "" or cmd == "menu" then Panoply.Menu:Toggle()
  elseif cmd == "guide" and args[2] then
    local G = Panoply.ProfGuide
    local which = args[2]:lower()
    if which == "leveling" or which == "levelling" or which == "level" then which = "leveling"
    elseif which == "professions" or which == "profession" or which == "prof" then which = "professions"
    elseif which == "both" or which == "mixed" then which = "both"
    else Panoply:Print("Usage: /panoply guide leveling | professions [name] | both") return end
    local prof
    if args[3] then
      local want = table.concat(args, " ", 3):lower()
      for _, n in ipairs(Panoply.ProfData.ORDER) do if n:lower() == want then prof = n end end
      if not prof then Panoply:Print("Unknown profession: " .. table.concat(args, " ", 3)) return end
    end
    G:SetActive(which, prof)
    Panoply.UI:Show()
    Panoply:Print("Guide: " .. G.GUIDE_LABELS[which] .. ((which ~= "leveling" and G:Tracked()) and (" (" .. G:Tracked() .. ")") or ""))
  elseif cmd == "switch" then
    local G = Panoply.ProfGuide
    local now = G:Switch()
    Panoply.UI:Show()
    Panoply:Print("Guide: " .. G.GUIDE_LABELS[now] .. ((now ~= "leveling" and G:Tracked()) and (" (" .. G:Tracked() .. ")") or ""))
  elseif cmd == "guide" or cmd == "show" or cmd == "toggle" then Panoply.UI:Toggle()
  elseif cmd == "spot" or cmd == "spots" then
    -- Nov 2026: saved map spots (Modules/Map/Spots.lua)
    local Sp = Panoply.Map and Panoply.Map.Spots
    if not Sp then Panoply:Print("Saved spots are not in this build.") return end
    local rest = (msg or ""):gsub("^%s*%S+%s*", "")
    if cmd == "spots" and rest == "" then rest = "list" end
    Sp:Slash(rest)
  elseif cmd == "fav" or cmd == "favs" or cmd == "favorites" or cmd == "favourites" then
    -- 0.9.5 phase 4G: map favorites (Modules/Map/Favorites.lua)
    local Fv = Panoply.Map and Panoply.Map.Favorites
    if not Fv then Panoply:Print("Map favorites are not in this build.") return end
    Fv:Slash((msg or ""):gsub("^%s*%S+%s*", ""))
  elseif cmd == "engine" then
    Panoply:Print(Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Status() or "Not in this build.")
    if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Present() then Panoply:Print(Panoply.PanoplyGuideEngine:Credits()) end
  elseif cmd == "source" then
    -- Nov 2026 (step 7): the guide source switch (Engine/PanoplyGuideEngine.lua), WoW Forever
    local PE = Panoply.PanoplyGuideEngine
    local v = (args[2] or ""):lower()
    if not (PE and PE:Active()) then Panoply:Print(PE and PE:Status() or "Not in this build.")
    elseif v == "leveling" or v == "levelling" or v == "added" then
      local ok, why = PE:SetSource(v == "added" and "added" or "leveling")
      Panoply:Print(ok and ("Guide source: " .. PE.SOURCE_NAMES[PE:Source()] .. " (" .. tostring(Panoply.Engine.title) .. ").") or why)
    else
      Panoply:Print("Guide source: " .. PE.SOURCE_NAMES[PE:Source()] .. ". Use /panoply source leveling or /panoply source added.")
    end
  elseif cmd == "hide" then Panoply.UI:Hide()
  elseif cmd == "setup" or cmd == "wizard" then Panoply.Wizard:Start()
  elseif cmd == "tour" or cmd == "howto" or cmd == "intro" then Panoply.Tour:Start()
  elseif cmd == "style" then
    -- 0.9.7 (Nov 18 2026): the levelling styles are gone; the old command changes nothing and says where the new setting is
    Panoply:Print(Panoply.StepText.StyleGone())
  elseif cmd == "minimap" then Panoply:SetOption("minimapButton", Panoply.db.minimapButton == false); Panoply:Print("Minimap button " .. (Panoply.db.minimapButton and "shown" or "hidden"))
  elseif cmd == "help" then for _, l in ipairs(Help:ChatLines()) do Panoply:Print(l) end
  elseif cmd == "replan" then Panoply:Replan("slash")
  elseif cmd == "next" then Panoply.Engine:Next()
  elseif cmd == "prev" then Panoply.Engine:Prev()
  elseif cmd == "selftest" or cmd == "test" then Panoply.SelfTest:Run()
  elseif cmd == "probe" then
    -- 0.9.5: what this game shares with add-ons, saved for the pages built on it (Core/Probe.lua)
    Panoply.Probe:Slash(table.concat(args, " ", 2))
  elseif cmd == "mapdebug" then if Panoply.Trail then Panoply.Trail:MapDebugCommand(args[2]) end
  elseif cmd == "rares" and Panoply.Map and Panoply.Map.Rares then Panoply.Map.Rares:Print()
  elseif cmd == "options" or cmd == "settings" or cmd == "config" then Panoply.Menu:Search(table.concat(args, " ", 2))
  elseif cmd == "arrow" then
    local sub = (args[2] or ""):lower()
    if sub == "lock" or sub == "unlock" then
      Panoply:SetOption("arrowLocked", sub == "lock")
      Panoply:Print(sub == "lock" and "Arrow locked: it can't be dragged and clicks go through it." or "Arrow unlocked: drag it where you like.")
    elseif sub == "reset" then
      if Panoply.Arrow.frame then Panoply.Arrow.frame:ClearAllPoints(); Panoply.Arrow.frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
      Panoply:Print("Arrow moved back to the top of the screen.")
    else
      Panoply:SetOption("arrowShown", not Panoply.db.arrowShown); Panoply:Print("Arrow " .. (Panoply.db.arrowShown and "on" or "off"))
    end
  elseif cmd == "way" or cmd == "waypoint" then
    local W = Panoply.Waypoints
    if not (W and W.active) then Panoply:Print("Waypoints are off (switch them on in " .. Panoply:SettingsPath("waySlash") .. ").") return end
    W:Slash(msg:match("^%s*%S+%s*(.*)$") or "")
  elseif cmd == "muster" or cmd == "hall" or cmd == "alts" then
    if Panoply.Alts then Panoply.Alts:Slash(msg:match("^%s*%S+%s*(.*)$") or "") end
  elseif cmd == "bags" or cmd == "bank" then
    local B = Panoply.Bags
    if not (B and B.active) then Panoply:Print("Panoply Suite bags are off (the switch is in the gear of the Muster page, under Bag window).") return end
    B:Toggle(cmd)
  elseif cmd == "junk" or cmd == "sell" then
    local M = Panoply.Merchant
    if not (M and M.active) then Panoply:Print("The vendor helper is off (switch it on in " .. Panoply:SettingsPath("autoSellJunk") .. ").") return end
    M:SellNow()
  elseif cmd == "modules" or cmd == "module" then
    local M = Panoply.Modules
    local key, v = (args[2] or ""):lower(), (args[3] or ""):lower()
    if M:Get(key) and (v == "on" or v == "off") then M:Set(key, v == "on") end
    for _, d in ipairs(M.list) do Panoply:Print(("%s (%s): %s"):format(d.label, d.key, M:Status(d.key))) end
    if key == "" then Panoply:Print("Turn one on or off: /panoply modules bags off") end
  elseif cmd == "scale" then
    local v = tonumber(args[2])
    local lo, hi = Panoply.Look.WINDOW_MIN, Panoply.Look.WINDOW_MAX
    if v and v >= lo and v <= hi then
      Panoply:SetOption("windowScale", v)
      Panoply:Print(("Window size %d%% (the same as %s)."):format(math.floor(v * 100 + 0.5), Panoply:SettingsPath("windowScale")))
    else Panoply:Print(("Usage: /panoply scale %.1f-%.0f (now %.2f). 1 is the standard size; this changes every Panoply Suite window."):format(lo, hi, Panoply.Look.WindowScale())) end
  elseif cmd == "sync" then
    Panoply:Print(Panoply.Sync:StatusText())
    Panoply.Sync:SendHello()
  elseif cmd == "prof" or cmd == "profession" then
    local G = Panoply.ProfGuide
    local sub = (args[2] or ""):lower()
    local function profName(s)
      for _, n in ipairs(Panoply.ProfData.ORDER) do if n:lower() == (s or ""):lower() then return n end end
      return nil
    end
    if sub == "mode" then
      local m = (args[3] or ""):lower()
      if not G.MODE_LABELS[m] then Panoply:Print("Profession mode: " .. G:Mode() .. ". Use interleave, only or off.") return end
      Panoply:SetOption("profGuide", m); Panoply:Print("Profession steps: " .. G.MODE_LABELS[m]) return
    elseif sub == "fastest" or sub == "cheapest" then
      if Panoply.ProfPlans then Panoply.ProfPlans:SetAllStrategy(sub) else Panoply:SetOption("profStrategy", sub) end
      Panoply:Print("Profession plans now pick the " .. sub .. " recipes.") return
    elseif sub == "track" then
      local n = profName(table.concat(args, " ", 3))
      if not n then Panoply:Print("Usage: /panoply prof track Blacksmithing") return end
      G:SetTracked(n); Panoply:Print("Your guide now follows " .. n .. ".") return
    elseif sub == "now" then G:Force(); Panoply.UI:Show() return
    elseif sub == "later" then G:Snooze(G:First()); Panoply:Print("Profession step hidden for 15 minutes.") return
    elseif sub == "tracker" then Panoply:SetOption("profTracker", Panoply.db.profTracker == false); return
    end
    local mode, target = "current", 300
    local nameParts = {}
    for i = 2, #args do
      local w = args[i]
      if w:lower() == "scratch" then mode = "scratch"
      elseif tonumber(w) then target = tonumber(w)
      else nameParts[#nameParts + 1] = w end
    end
    local name = table.concat(nameParts, " ")
    if name == "" then Panoply.Menu:Open("professions") return end
    name = profName(name) or name
    -- 0.9.5 phase 4B: the profession's own plan choice (Engine/ProfPlans.lua)
    local plan, err = Panoply.Professions:PlanForPlayer(name, mode, target, { strategy = Panoply.ProfPlans and Panoply.ProfPlans:Strategy(name) or nil })
    if not plan then Panoply:Print(err) return end
    for _, l in ipairs(Panoply.Professions:Describe(plan)) do Panoply:Print(l) end
  elseif cmd == "price" then
    local item, copper = args[2], tonumber(args[3])
    if not item or not copper then Panoply:Print('Usage: /panoply price "Linen Cloth" 15  (copper; 100 = 1 silver)') return end
    local id = tonumber(item) or Panoply.ProfData.ItemID(item)
    Panoply.db.prices[item] = copper
    if id then Panoply.db.prices[id] = copper end
    if Panoply.ProfGuide then Panoply.ProfGuide:Invalidate() end
    Panoply:Print((id and Panoply.ProfData.ItemName(id) or item) .. " = " .. U.FormatMoney(copper))
  elseif cmd == "debug" then
    local sub = (args[2] or ""):lower()
    if sub == "on" then Panoply.db.debug = true; Panoply:Print("debug on")
    elseif sub == "off" then Panoply.db.debug = false; Panoply:Print("debug off")
    elseif sub == "log" then for _, l in ipairs(Panoply.debugLog) do Panoply:Print(l) end
    else
      local v, b, _, toc = C.BuildInfo()
      Panoply:Print(("Client %s build %s Interface %s, flavor %s"):format(tostring(v), tostring(b), tostring(toc), C.Flavor()))
      local m = U.Keys(C.missing); table.sort(m)
      Panoply:Print("Missing APIs: " .. (#m > 0 and table.concat(m, ", ") or "none"))
      for k, e in pairs(C.errors) do Panoply:Print("Error in " .. k .. ": " .. tostring(e)) end
      Panoply:Print("Quest data: " .. tostring(Panoply.QuestData.status))
    end
  elseif cmd == "trip" then
    if Panoply.Trip then Panoply.Trip:TogglePanel() end
  elseif cmd == "pace" then
    if (args[2] or ""):lower() == "reset" then Panoply.Pace:Reset() Panoply:Print("Your pace is forgotten; times use the standard estimate again.")
    else for _, l in ipairs(Panoply.Pace:Summary()) do Panoply:Print(l) end end
  elseif cmd == "calib" or cmd == "calibration" then
    for _, l in ipairs(Panoply.Calib:Lines()) do Panoply:Print(l) end
  elseif cmd == "record" or cmd == "rec" then
    Panoply.Recorder:Slash(args)
  elseif cmd == "levelstats" or cmd == "leveltimes" then
    Panoply.LevelStats:Slash(args)
  elseif cmd == "route" and Panoply.Guides then
    local G = Panoply.Guides
    local m = (args[2] or ""):lower()
    if m == "" then Panoply:Print(G:Status()) return end
    -- Nov 11 2026 ("turn planner off."): /panoply route planner changes nothing
    if m == "planner" and not G.PlannerOn() then Panoply:Print(G.PLANNER_OFF_LINE .. " " .. G:Status()) return end
    if not G:SetMode(m) then Panoply:Print(G.PlannerOn() and "Usage: /panoply route auto | guides | planner" or "Usage: /panoply route auto | guides") return end
    Panoply:Print(G:Status())
    if Panoply.NoGuide then Panoply.NoGuide:Update(true) end
    Panoply:Replan("route " .. m)
  elseif cmd == "noguide" and Panoply.NoGuide then
    Panoply.NoGuide:Slash(args)
  elseif cmd == "recorded" or cmd == "questrecorder" then
    Panoply.QuestRecorder:Slash(args)
  elseif cmd == "import" then
    -- where the copy of the old Hearthpath saved data stands (Core/Migrate.lua); it runs only at load
    for _, l in ipairs(Panoply.Migrate:Report()) do Panoply:Print(l) end
    local res = Panoply.Migrate.result
    if res and #res.problems > 0 then for _, p in ipairs(res.problems) do Panoply:Print(p) end Panoply:Print("Fix that, then type /reload to try again.") end
  elseif cmd == "reset" then
    Panoply:ResetPlan()
  elseif cmd == "class" and Panoply.Catalog and Panoply.Catalog.class then
    -- 0.9.5 phase 4A4 (spec 06 section 2.3): the Class page by its new name. Phase 4H: "/panoply class talents" (spells, play, gear,
    -- pet, or an older name: rotation, macros, plan) opens that tab
    local tab = args[2] and table.concat(args, " ", 2):lower() or nil
    if Panoply.ClassPages and Panoply.ClassPages.Open then Panoply.ClassPages:Open(nil, tab) else Panoply.Menu:Open("class") end
  elseif (cmd == "talents" or cmd == "spells" or cmd == "pet") and Panoply.ClassPages and Panoply.ClassPages.Open then
    Panoply.ClassPages:Open(nil, cmd)
  else
    for _, l in ipairs(Help:ChatLines()) do Panoply:Print(l) end
  end
end

-- /panoply is the command. /ps (its short form from 0.8.0) was dropped in 0.9.9.5 ("Drop /ps from Panoply"): it is the
-- original guide engine add-on's own command, and the two can be installed together. The numbers run 1, 2, 3 with no gap (the game stops at the
-- first missing one). /hp and /hearthpath (the
-- old names) keep working and are not shown anywhere. The id stays HEARTHPATH: it is internal, and changing it would gain nothing.
_G.SLASH_HEARTHPATH1 = "/panoply"
_G.SLASH_HEARTHPATH2 = "/hp"
_G.SLASH_HEARTHPATH3 = "/hearthpath"
if _G.SlashCmdList then _G.SlashCmdList.HEARTHPATH = function(msg) Panoply:Slash(msg or "") end end
