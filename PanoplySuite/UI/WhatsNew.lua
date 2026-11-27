-- Panoply Suite, Step 2 item B: the "What's new" note (docs/step2/ABC-SPEC.md B-09).
-- After an update, once, a small window says what changed in plain words, and each line has a button that opens the page it is about.
-- "Got it" closes it; Help > What's new shows it again. The version the account has seen is saved (PanoplySuiteDB.whatsNewSeen); a
-- brand-new account starts on the current version already seen, so it is told nothing about changes it never had.
--
-- (0.7.4.1 is a short note: no guide yet in new areas, and the talent planner. 0.8.0: the rename to Panoply Suite, the written leveling guides and the GPL licence: four lines.)
-- WHOEVER MAKES A RELEASE adds a note to WN.NOTES for Panoply.version (the version it describes): one short line per changed part, at most
-- WN.MAX (8) lines, each { the sentence, the page it is about, the button's words, gear = true to open that page's gear, windowSize =
-- true for the line that says what the Window size was }. The 0.7.4 note's order (8 lines, the most a note may have): setup (A), Home
-- page (B), settings shape (B), Class & Spec (C), map look (D), the map and the zone connections (E, one line), auction record (F), and
-- last the one-time "Window size starts again at 100%". A player is shown the lines of every note newer than the version this account
-- last saw, up to the version it runs now, so a line is told once and never again. A showing holds at most WN.MAX lines across those
-- notes, newest first; when they are more, the Window size line is never the one dropped (WN:Lines).
-- tests/ease_tests.lua fails when Panoply.version has no note of its own, when a note has more than WN.MAX lines, and when a line names a page
-- this build does not have. A release with nothing to tell adds a note with no lines.
-- 0.9.5 phase 4L (docs/specs/page-redesigns-06-help.md section 7): the title shows the installed version (read from the TOC); a version
-- selector at the top lists the versions, current first; the lines are grouped by page, each group with the page's icon and its current
-- name; a line gets a "Show me" button only when it points at a page or a spot on it (general = true: no button). Show me goes through
-- the window's back and forward history (UI/History.lua), like any jump from one page to another.
local ADDON, Panoply = ...
local Skin, C = Panoply.Skin, Panoply.Compat
local WN = {}
Panoply.WhatsNew = WN
local SP, TH = Skin.SP, Skin.TextHeight

WN.NOTES = {
  { version = "0.7.3.6", lines = {} },       -- released: nothing to add
  { version = "0.9.9.6", lines = {} },       -- Nov 26 2026: Hub remembers your auction house, shows only your factions' prices and the items' own icons; installers say /panoply; nothing to add (any text is approved first)
  -- Nov 25 2026: Hub prices by faction; guide engine renamed; /ps dropped. The line is our approved text ("Use that line")
  { version = "0.9.9.5", lines = {
    { "/ps is gone: type /panoply to open Panoply Suite (another guide add-on uses /ps).", "home", "Show me", general = true },
  } },
  { version = "0.9.9.4", lines = {} },       -- Nov 23 2026: WoW Forever talent trees from Blizzard's data; public builds in every place; profession icons; nothing to add (any text is approved first)
  { version = "0.9.9.3", lines = {} },       -- Nov 22 2026: Hub: carried-over Horde house removed; old 0.9.9.1 pick no longer used; nothing to add (any text is approved first)
  { version = "0.9.9.2", lines = {} },       -- Nov 22 2026: your auction house is found automatically; nothing to add (any text is approved first)
  { version = "0.9.9.1", lines = {} },       -- Nov 21 2026: PanoplyGuide 0.4.2.1 (walking arrow fixed, guide fixes); nothing to add (any text is approved first)
  { version = "0.9.9", lines = {} },         -- Nov 21 2026: PanoplyGuide 0.4.2 (the guide engine); nothing to add (any text is approved first)
  { version = "0.9.8", lines = {} },         -- Nov 21 2026: some game data was taken out; nothing to add (we approves any text first)
  -- 0.9.7 (Nov 18 2026, WoW Forever only): Classic out of the product, the levelling styles replaced by one Group quests setting,
  -- partner levelling with the class-quest hold, the guide picker. Shown from the build whose version is 0.9.7 (a note newer than
  -- the build is never shown). Each line stays only if its part is in the build; we approves new text before it ships.
  { version = "0.9.7", lines = {
    { "Panoply Suite is now for WoW Forever only.", "home", "Show me", general = true },
    { "Levelling styles are gone. One Group quests setting decides: Ask me each time, Always include them, or Leave them out.", "guide", "Show me", gear = true },
    { "Level together: see each other's progress, wait for each other at turn-ins, and sync to the same step. The guide holds while one of you does a class quest.", "partner", "Show me" },
    { "Pick your guide on the Guide page, or let Panoply Suite pick for you. Your progress is kept.", "guide", "Show me" },
  } },
  -- a hotfix (ticket PS-0011 again, the first quest giver after setup), and Nov 18 2026 (easier report access): how to report
  { version = "0.9.6.2", lines = {
    { "Found a problem or have an idea? Right-click the guide, or Ctrl-click the minimap button and pick Report a problem / Feedback. Or type /panoply report or /panoply idea.", "help", "Show me" },
  } },
  { version = "0.9.6.1", lines = {} },       -- a hotfix (ticket PS-0011, quest givers and the automatic accept): nothing to add
  -- 0.9.6 (phases A-I and J-P). The wording was a placeholder until 0.9.7 (lane M2 wrote these lines; we approves new text before it
  -- ships). The loot line names where the drops come from: a community copy of Classic's 1.12 loot tables, never the game's own.
  { version = "0.9.6", lines = {
    { "Point at the minimap button to see what each click does. You can switch Panoply Suite off there, on Home, or on the welcome page.", "home", "Show me" },
    { "A new character gets a short welcome page before setup.", "home", "Show me", general = true },
    { "Go to finds towns, inns and landmarks by name, as well as NPCs and quests.", "map", "Show me" },
    { "Dungeon and raid maps show what each boss can drop, with its chance, from a community copy of Classic's 1.12 loot tables. Click a boss to open its treasure room.", "map", "Show me" },
    { "A new character's guide starts on its own.", "guide", "Show me" },
    { "The Professions page opens even before you have a profession, with a picker to choose your first ones. You can craft on the page.", "professions", "Show me" },
    { "Profession trainers, vendors and auctioneers are the ones of your own side.", "professions", "Show me" },
  } },
  -- 0.9.5 (spec 06 section 7): the version that ships specs 01 to 06: the renames, the merged Class page, back and forward, the nav
  -- sections and alerts, and the new Help. Written in phase 4L; we approves new text before it ships.
  { version = "0.9.5", lines = {
    { "New page names: Muster (was Hearth Hall) and Field Kit (was Miscellaneous).", "hall", "Show me" },
    { "The Class page is one page now: your plan, talents, spells to buy, how to play, gear and your pet.", "class", "Show me" },
    { "Back and forward: the arrows at the top of the window, or your mouse's fourth and fifth buttons, go back through the pages you opened.", "home", "Show me", general = true },
    { "The page list has four sections: Play, Character, Account and Setup.", "home", "Show me", general = true },
    { "A dot beside a page means something there needs you. Home lists them all under Needs you.", "home", "Show me" },
    { "Help is new: search it, read tips for every page, find any command, and report a problem in one place.", "help", "Show me" },
    { "Setup asks how much you have played, so the Class page is written for you.", "class", "Show me", general = true },
  } },
  -- 0.9.2 (Nov 13 2026): the guides on PanoplyGuide 0.3.7.2 and guide fixes. No new text was written for it (new text needs our OK
  -- first), so the note has no lines and shows nothing
  { version = "0.9.2", lines = {} },
  -- 0.9.3 (Nov 14 2026): the next list after 0.9.2 (talent sync, menus, saved map spots, bag window, window sizes) and PanoplyGuide's
  -- engine on WoW Forever. No new text was written for it (new text needs our OK first), so the note has no lines and shows nothing
  { version = "0.9.3", lines = {} },
  -- 0.9.4 (Nov 14 2026): the next list after 0.9.3 (profession data, hunter pets, class pages, shield logo, About, menu icons). No new text was
  -- written for it (new text needs our OK first), so the note has no lines and shows nothing
  { version = "0.9.4", lines = {} },
  { version = "0.9.1", lines = {
    -- the planner off (PanoplyGuide's written guides are the only route), the guide's place kept across login, Level together in step
    { "The planner is turned off. The written leveling guide is now the only route.", "guide", "Open Guide" },
    { "The guide keeps its place when you log out and back in.", "guide", "Open Guide" , general = true },
    { "Level together follows the party leader's route while the two of you are in step, and keeps its own route when you are not.", "partner", "Open Level together" },
    -- long lists the same way everywhere
    { "Every scroll bar can be dragged.", "guide", "Open Guide" , general = true },
    { "Long lists are closed sections, with a search box, a Jump to list, and Expand all / Collapse all.", "class", "Open Class" , general = true },
    -- the hunter's pet as the Pet tab of the Hunter Class Guide (no third menu level; 11 Nov 2026: "Should be in the class page")
    { "The hunter's pet is the Pet tab of the Hunter Class Guide. Families, Planner, To tame and Training points are closed sections in it.", "class", "Open the Pet tab", classTopic = { "HUNTER", "pet" } },
    { "To tame is grouped by zone.", "class", "Open the Pet tab", classTopic = { "HUNTER", "pet" } },
    -- Nov 12 2026: the minimap crest's clicks
    { "Minimap crest: left-click shows or hides the guide, right-click opens Panoply Suite, Ctrl-click opens the quick switches.", "help", "Open Help" },
  } },
  { version = "0.9.0", lines = {
    { "The map's Go to search now finds places by what they are and where they are, in any word order: try goldshire inn.", "map", "Open Map" },
    -- Nov 11 2026 ("turn planner off."): the planner no longer fills in, and the Leveling route row is gone, so these two lines say so
    { "The written leveling guides are now the route on both games. Missing a quest? Type /panoply report.", "guide", "Open Guide" },
    { "A fresh character, including an Undead start, now gets the written guide for its own race.", "guide", "Open Guide" },
    { "Walk into a dungeon and the guide lists the bosses and your quests for it. Your leveling route is waiting when you leave.", "guide", "Open Guide" },
    { "The planner is off. Where the written guide has no step for you, the guide window says so.", "guide", "Open Guide" },
  } },
  { version = "0.8.3", lines = {} },       -- a layout fix (the profession window's Report button): nothing to add
  { version = "0.8.4", lines = {} },       -- What's New copy was not written for this release: nothing to tell yet
  { version = "0.8.2", lines = {
    -- AddOns.txt migration (installer) and the new-Forever-zone guide fixes (Engine/Guides.lua)
    { "The installer now turns Panoply Suite on where Hearthpath was on, so the guide window and minimap button come back after the rename.", "help", "Open Help" , general = true },
    { "In a new Forever start such as Zephras Isle, the written guide no longer shows a coming-soon note or a leftover arrow to another zone.", "guide", "Open Guide" },
  } },
  { version = "0.8.1", lines = {
    -- the profession window beside the game's own (Modules/ProfWindow)
    { "Professions: no red bar, both windows work. Make all works, a box makes exactly N, side tabs switch professions, and the guide has a Professions button.", "professions", "Open Professions" },
    -- bags: unequip, split, whose bags (a list), special bags marked (Modules/Bags)
    { "Bags: take a bag off, split a stack, pick whose bags you see from a list, and tell special bags (quiver, herb, soul and more) apart.", "hall", "Open Muster" },
    -- pickup from where the character is (Engine/Guides.lua)
    { "/ps replan picks the written guide up where this character is, never back at the start zone.", "guide", "Open Guide" },
  } },
  { version = "0.8.0", lines = {
    -- the rename: Hearthpath is now Panoply Suite (Core/Migrate.lua copies the old saved data across once)
    { "Hearthpath is now called Panoply Suite. Type /panoply to open it, or /ps for short (/ps noguide, /ps help).", "home", "Open Home" },
    { "Your settings and recorded guides came across on their own. Nothing was wiped.", "help", "Open Help" , general = true },
    -- the written leveling guides (Engine/Guides.lua, Data/Guides/: converted from PanoplyGuide's own guides)
    { "WoW Forever: written leveling guides from every race's start to 60. A Skyborne gets the Zephras Isle guide by itself; /ps route guides follows them all the way.", "guide", "Open Guide" },
    -- the licence (LICENSE, NOTICE.md)
    { "Panoply Suite is now free software under the GNU GPL version 3. Credits are in NOTICE.md.", "help", "Open Help" , general = true },
  } },
  { version = "0.7.4.1", lines = {
    -- no guide yet in new areas (Engine/NoGuide.lua)
    { "Where there is no guide yet, such as a new race's own start area, Panoply Suite says so and records your steps instead of sending you to another race's start.", "guide", "Open Guide" },
    -- the redesigned talent planner (Modules/SpecTrainer/Planner.lua)
    { "The talent planner is redesigned: it shows your talent trees with their icons, and you plan point by point.", "class", "Open Class" },
  } },
  { version = "0.7.4", lines = {
    -- A: setup
    { "New characters start with a short setup of four questions. Help can run it again whenever you like.", "help", "Open Help" },
    -- B: menu ease
    { "A new Home page shows what needs you now, in one place.", "home", "Open Home" },
    { "Every page's settings show the few that most players change first. The rest are under More settings, and Profiles can copy them to your other characters.", "guide", "Open settings", gear = true },
    -- C: Class & Spec
    { "Class & Spec is a page of its own: pick a class plan, and see which spells to buy at each trainer visit and what they cost.", "class", "Open Class" },
    -- D: the Look of the map
    { "Everything on the maps can be changed: size, opacity, spacing, style and colour, on the world map and the minimap, with a live preview.", "map", "Open Map settings", gear = true },
    -- E: the Map module (a toolbar on the world map, a map of every dungeon and raid) and the zone connections, in ONE line
    { "The world map has a toolbar to jump to any zone and a map of every dungeon and raid, and it shows where zones join: exits, boats, zeppelins, the tram, portals, flight points.", "map", "Open Map settings", gear = true },
    -- F: the auction record
    { "Auctions are remembered: look through the last scan from anywhere, and see what you listed, bought and sold. At most 8 MB.", "auctions", "Open Auctions" },
    -- the one-time line, always last
    { "Window size starts again at 100% for everyone. Small, Normal and Large are at the top of every page.", "guide", "Open Guide", windowSize = true },
  } },
}

local MAX = 8
WN.MAX = MAX         -- the most lines one showing holds (and one note may have)

-- dotted versions compared number by number: "0.7.4" is newer than "0.7.3.6"
function WN.Cmp(a, b)
  local function parts(v) local t = {} for n in tostring(v or "0"):gmatch("%d+") do t[#t + 1] = tonumber(n) end return t end
  local x, y = parts(a), parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p < q and -1 or 1 end
  end
  return 0
end

function WN:NoteFor(version)
  for _, n in ipairs(self.NOTES) do if n.version == version then return n end end
end

-- The installed version, from the add-on's TOC ("## Version"), the number the game shows in its AddOns list; Panoply.version when the game
-- does not say (the two are the same in a release: tests/ease_tests.lua checks).
function WN.InstalledVersion()
  local get = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
  if type(get) == "function" then
    local ok, v = pcall(get, ADDON or "PanoplySuite", "Version")
    if ok and type(v) == "string" and v:match("^%d") then return v end
  end
  return tostring(Panoply.version)
end

-- The versions the selector lists: the installed one first, then every older note that has lines, newest first.
function WN:Versions()
  local cur = WN.InstalledVersion()
  local out, seen = { cur }, { [cur] = true }
  local list = {}
  for _, n in ipairs(self.NOTES) do
    if #n.lines > 0 and self.Cmp(n.version, cur) <= 0 and not seen[n.version] then seen[n.version] = true list[#list + 1] = n.version end
  end
  table.sort(list, function(a, b) return self.Cmp(a, b) > 0 end)
  for _, v in ipairs(list) do out[#out + 1] = v end
  return out
end

-- The notes to show: every one newer than what this account saw, up to this version (newest first); force = Help's button: the
-- newest note that has lines.
function WN:Pending(force)
  local list = {}
  if force then
    -- the newest note with lines that this build has reached (never a note for a version still to come)
    local cur = WN.InstalledVersion()
    for _, n in ipairs(self.NOTES) do
      if #n.lines > 0 and self.Cmp(n.version, cur) <= 0 and (not list[1] or self.Cmp(n.version, list[1].version) > 0) then list[1] = n end
    end
    return list
  end
  local db = Panoply.db or {}
  local seen = db.whatsNewSeen or db.lastVersion or "0"
  for _, n in ipairs(self.NOTES) do
    if self.Cmp(n.version, seen) > 0 and self.Cmp(n.version, Panoply.version) <= 0 and #n.lines > 0 then list[#list + 1] = n end
  end
  table.sort(list, function(a, b) return self.Cmp(a.version, b.version) > 0 end)
  return list
end

function WN:Lines(force)
  local all, sizeLines = {}, 0
  for _, n in ipairs(self:Pending(force)) do
    for _, l in ipairs(n.lines) do
      local text = l[1]
      if l.windowSize and Panoply.windowSizeWas and math.abs(Panoply.windowSizeWas - 1) > 0.001 then
        text = text .. (" It was %d%%."):format(math.floor(Panoply.windowSizeWas * 100 + 0.5))
      end
      all[#all + 1] = { text = text, page = l[2], button = l[3], gear = l.gear, windowSize = l.windowSize, classTopic = l.classTopic,
        general = l.general, version = n.version }
      if l.windowSize then sizeLines = sizeLines + 1 end
    end
  end
  if #all <= MAX then return all end
  -- more than a showing holds (an account that skipped versions): the lines are kept newest first, but the one-time Window size line is
  -- kept whatever else goes, because it is the one that says why the player's window changed. Order stays as it was.
  local reserve = math.min(sizeLines, MAX)
  local room = MAX - reserve
  local out, taken, kept = {}, 0, 0
  for _, e in ipairs(all) do
    if e.windowSize then
      if kept < reserve then kept = kept + 1 out[#out + 1] = e end
    elseif taken < room then taken = taken + 1 out[#out + 1] = e end
  end
  return out
end

-- the page (or its gear) a line is about; classTopic = { class, topic }: that tab of a Class Guide page (0.9.1, the Hunter's Pet)
function WN.Go(line)
  local Menu = Panoply.Menu
  local CP = Panoply.ClassPages
  if line.classTopic and line.page == "class" and CP and CP.Open then CP:Open(line.classTopic[1], line.classTopic[2]) return end
  if line.gear then Menu:OpenGear(line.page) else Menu:Open(line.page) end
end

WN.SHOW_ME = "Show me"
WN.FOOT = "You can read this again in Help."

-- the lines of a showing grouped by page, in the order each page first comes: { { page, label, icon, lines = { ... } }, ... }
function WN.Groups(lines)
  local Cat = Panoply.Catalog
  local out, by = {}, {}
  for _, l in ipairs(lines or {}) do
    local key = l.page or "help"
    local g = by[key]
    if not g then
      local pg = Cat and Cat:Page(key)
      g = { page = key, label = (pg and pg.label) or key, icon = pg and pg.icon, lines = {} }
      by[key] = g
      out[#out + 1] = g
    end
    g.lines[#g.lines + 1] = l
  end
  -- the one-time Window size line stays the last one shown (its page's group goes last, and it last in it)
  for i, g in ipairs(out) do
    local k
    for j, l in ipairs(g.lines) do if l.windowSize then k = j end end
    if k then
      local l = table.remove(g.lines, k)
      g.lines[#g.lines + 1] = l
      table.remove(out, i)
      out[#out + 1] = g
      break
    end
  end
  return out
end

function WN:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteWhatsNew", 560, 400, "What's new in Panoply Suite", "")
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f.cards, f.groups = {}, {}
  -- the version selector (spec 06 section 7): the installed version first, then the older notes
  f.pick = Panoply.Kit.Dropdown(f, { width = 200, label = "Version ", tip = "Version", tipBody = "Read what changed in another version.",
    items = function()
      local it = {}
      for i, v in ipairs(WN:Versions()) do it[#it + 1] = { value = v, text = v .. (i == 1 and " (installed)" or "") } end
      return it
    end,
    get = function() return WN.lastSnap and WN.lastSnap.version end,
    set = function(v) WN:Display(WN:SnapshotOf(v)) end })
  -- the lines sit in a scrolling area: a note of 8 lines at large text is taller than a small screen, and the window never is
  f.list = Skin.ScrollArea(f)
  for i = 1, MAX do
    local c = Skin.Card(f.list.content)
    c.panoplyGapOK = true
    c.text = Skin.Ink(c, 13)
    c.btn = Skin.Button(c, WN.SHOW_ME, 100, 28, function() local l = c.line WN:Close() if l then WN.Go(l) end end, WN.SHOW_ME, nil)
    c:Hide()
    f.cards[i] = c
    local g = CreateFrame("Frame", nil, f.list.content)
    g.panoplyGapOK = true
    g.icon = g:CreateTexture(nil, "ARTWORK"); g.icon:SetSize(18, 18)
    g.name = Skin.Name(g, 14, Skin.colors.heading)
    g:SetSize(10, 22)
    g:Hide()
    f.groups[i] = g
  end
  f.empty = Skin.Ink(f.list.content, 13, Skin.colors.inkSoft)
  f.empty:SetText("Nothing new to tell in this version.")
  f.foot = Skin.Ink(f, 11, Skin.colors.inkSoft)
  f.foot:SetText(WN.FOOT)
  f.ok = Skin.Button(f, "Got it", 100, 30, function() WN:Close() end, "Got it", "Close this note. It does not come back until the next update.")
  f.ok.panoplyAccent = true
  self.frame = f
  -- Nov 2026: resizable in both directions, the size remembered. Until the player drags it the window is as tall as its
  -- lines (as before); after that it keeps the height they chose and the lines scroll.
  Skin.Resizable(f, { key = "whatsNew", minW = WN.MIN_W, minH = WN.MIN_H, onSize = function() if WN.lastSnap then WN:Layout(WN.lastSnap) end end })
  return f
end

WN.MIN_W, WN.MIN_H = 420, 260
function WN:Layout(snap)
  local f = self.frame
  self.lastSnap = snap
  local lines = snap.lines
  local W = math.max(WN.MIN_W, f:GetWidth() or 560)
  local pad = 20
  local inner = W - 2 * pad
  local list = f.list
  -- the title: the installed version, from the TOC; the subtitle: the version being read
  f.panoplyTitle:SetText(("What's new in %s"):format(WN.InstalledVersion()))
  f.panoplySubtitle:SetText(("Version %s"):format(snap.version))
  local top = (f.panoplyHeaderBottom or 50) + SP.s
  f.pick:Fit(160, math.min(260, inner))
  f.pick:ClearAllPoints(); f.pick:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
  top = top + (f.pick:GetHeight() or 26) + SP.m
  -- the foot: what it says and Got it (measured first: the lines get what is left of the screen)
  local okw = Skin.FitButton(f.ok, 90, inner)
  local fw = inner - okw - SP.m - 8
  f.foot:SetWidth(fw)
  local footH = math.max(f.ok:GetHeight(), TH(f.foot, fw))
  local groups = WN.Groups(lines)
  -- the groups and their cards at a width w; returns the height of all of them
  local function lay(w)
    local y = 0
    local ci = 0
    for gi, g in ipairs(f.groups) do
      local gr = groups[gi]
      if not gr then g:Hide() else
        g:Show()
        -- the page's own icon, the one its header and the left list show (own = true: the same in both icon styles)
        if gr.icon then Skin.SetIcon(g.icon, gr.icon, { size = 18, own = true }) g.icon:Show() else g.icon:Hide() end
        g.name:SetText(gr.label)
        g.icon:ClearAllPoints(); g.icon:SetPoint("LEFT", g, "LEFT", 0, 0)
        g.name:ClearAllPoints(); g.name:SetPoint("LEFT", g, "LEFT", 18 + SP.s, 0); g.name:SetWidth(w - 18 - SP.s)
        local gh = math.max(20, TH(g.name, w - 18 - SP.s))
        g:SetSize(w, gh)
        g:ClearAllPoints(); g:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
        y = y + gh + SP.xs
        for _, l in ipairs(gr.lines) do
          ci = ci + 1
          local c = f.cards[ci]
          if c then
            c.line = l
            c.text:SetText(l.text)
            -- Show me only where the line points at a page or a spot on it (spec 06 section 7)
            local btn = not l.general
            local bw = 0
            if btn then
              c.btn:Show()
              c.btn.label:SetText(WN.SHOW_ME)
              c.btn.tip, c.btn.tipBody = WN.SHOW_ME, l.gear and ("Opens the %s page's settings."):format(gr.label) or ("Opens the %s page."):format(gr.label)
              bw = Skin.FitButton(c.btn, 90, math.floor(w * 0.34))
            else c.btn:Hide() end
            local tw = w - 2 * 14 - (btn and (bw + SP.m) or 0)
            c.text:SetWidth(tw)
            local th = TH(c.text, tw)
            local h = math.max(12 + th + 12, btn and (c.btn:GetHeight() + 20) or 0)
            c:SetSize(w, h)
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -y)
            c.text:ClearAllPoints(); c.text:SetPoint("LEFT", c, "LEFT", 14, 0)
            c.btn:ClearAllPoints(); c.btn:SetPoint("RIGHT", c, "RIGHT", -14, 0)
            c:Show()
            y = y + h + SP.s
          end
        end
        y = y + SP.xs
      end
    end
    for i = ci + 1, #f.cards do f.cards[i]:Hide() f.cards[i].line = nil end
    if #lines == 0 then
      f.empty:Show()
      f.empty:ClearAllPoints(); f.empty:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, 0); f.empty:SetWidth(w)
      y = TH(f.empty, w) + SP.m
    else f.empty:Hide() end
    return y
  end
  local h = lay(inner)
  -- the window always fits the screen: when the lines are taller than what is left, they scroll (and are narrower by the bar)
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local cap = screenH - 40 - top - (SP.m + footH + pad)
  local viewH = h
  -- a height the player chose (the grip): the lines get what that leaves, and scroll when it is less than they need
  local userH
  if f.panoplySizing then userH = f:GetHeight() elseif f.panoplyUserSize then local _, uh = f:panoplyUserSize() userH = uh end
  if userH then cap = math.min(cap, math.max(WN.MIN_H, userH) - top - (SP.m + footH + pad)) end
  if h > cap then
    viewH = math.max(96, cap)
    h = lay(inner - 12)
  elseif userH then
    viewH = math.max(96, cap)
  end
  list:ClearAllPoints(); list:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top); list:SetSize(inner, viewH)
  list.content:SetWidth(list:ContentWidth(h))
  list:SetContentHeight(h)
  if list.SetVerticalScroll then list:SetVerticalScroll(0) end
  list:UpdateBar()
  local y = top + viewH + SP.m
  f.foot:ClearAllPoints(); f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
  f.ok:ClearAllPoints(); f.ok:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad - 8, -y)      -- 8: clear of the resize grip
  y = y + footH + pad
  if not f.panoplySizing then f:SetHeight(y) end
  -- a little above the middle, never past the top or bottom of the screen (a window already on screen stays where the player put it)
  if not f:IsShown() then
    local up = math.max(0, math.min(40, (screenH - y) / 2 - 10))
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, up)
  end
end

-- One version's own note, for the selector: { lines, version }
function WN:SnapshotOf(version)
  local n = self:NoteFor(version)
  local lines = {}
  for _, l in ipairs(n and n.lines or {}) do
    lines[#lines + 1] = { text = l[1], page = l[2], button = l[3], gear = l.gear, windowSize = l.windowSize, classTopic = l.classTopic,
      general = l.general, version = version }
  end
  return { lines = lines, version = version }
end

-- What a showing is about, worked out when it is asked for (marking the version seen must not empty it before it is drawn)
function WN:Snapshot(force)
  local note = self:Pending(force)[1]
  return { lines = self:Lines(force), version = note and note.version or Panoply.version }
end

-- force = true: Help's button (shows the newest note again, whatever the account has seen)
function WN:Show(force)
  local snap = self:Snapshot(force)
  if not force then
    if not Panoply.db then return false end
    -- this version is now seen, whether or not there was anything to tell
    Panoply.db.whatsNewSeen = Panoply.version
    if #snap.lines == 0 then return false end
    -- one window at a time: the tour is on screen, the note follows it
    local T = Panoply.Tour
    if T and T.active then self.queued = snap return false end
  end
  self:Display(snap)
  return true
end

function WN:Display(snap)
  local f = self:Create()
  self:Layout(snap)
  f:Show()
end

function WN:Close()
  if self.frame then self.frame:Hide() end
  -- the tour that was waiting for this window starts now
  local T = Panoply.Tour
  if T and T.queuedAuto then T.queuedAuto = nil C.After(0.5, function() T.AutoStart() end) end
end

-- the tour was on screen when the note was due: now it is the note's turn
Panoply:Listen("TOUR_DONE", function()
  local snap = WN.queued
  if snap then WN.queued = nil C.After(0.5, function() if not (WN.frame and WN.frame:IsShown()) then WN:Display(snap) end end) end
end)

-- After login (Panoply:AfterLogin): an updated account is told once. While the thank-you or the setup is on screen it waits for them to
-- close; combat is handled by the caller.
function WN:AfterLogin()
  local db = Panoply.db
  -- what this account had seen when it logged in is kept (an account from before this note has seen up to the version it last ran):
  -- Bootstrap writes the running version into lastVersion right after this, and a note that waits for the thank-you needs the old one
  if db and not db.whatsNewSeen then db.whatsNewSeen = db.lastVersion or "0" end
  if not db or #self:Lines(false) == 0 then
    if db and db.whatsNewSeen ~= Panoply.version then db.whatsNewSeen = Panoply.version end
    return false
  end
  local Z = Panoply.Wizard
  if Z and Z.frame and Z.frame:IsShown() then
    self.waiting = true
    if not self.hooked and Z.frame.HookScript then
      self.hooked = true
      Z.frame:HookScript("OnHide", function()
        if WN.waiting then WN.waiting = nil C.After(0.5, function() WN:Show() end) end
      end)
    end
    return false
  end
  return self:Show()
end
