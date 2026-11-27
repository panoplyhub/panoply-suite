-- Panoply Suite: the Help page. 0.9.5 phase 4L rebuilds it to docs/specs/page-redesigns-06-help.md section 2 (with 06a and 06b):
--   Search help (tips, commands and settings together), then four sections: Get started, Tips by page, Commands and Problems.
--   Wide: the four sections are an index on the left (about 220 px) and the chosen one on the right. Medium and Narrow: the index is a
--   drop-down under the search box.
-- Tips come from the help registry (Core/HelpRegistry.lua: each page registers its own, and a page's "?" text and subtitle are read
-- from the Catalog), the commands from the slash-command registry. Nothing about pages or commands is written out here.
-- Its gear holds the look of Panoply Suite, reports and privacy and Reset (UI/Catalog.lua). Laid out from measured text (scroll page).
local ADDON, Panoply = ...
local Menu, Skin, Kit = Panoply.Menu, Panoply.Skin, Panoply.Kit
local Help = Panoply.Help or {}   -- 0.9.5 phase 4A4: the registries live on the same table (Core/HelpRegistry.lua)
Panoply.Help = Help
local SP = Skin.SP
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-------------------------------------------------------------------------------
-- Icon slots (spec 06 section 9). The theme's drawing first; the game's icon only where the theme has none.
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
Kit.RegisterIcon("icon.help.setup", { icon = "Settings" })                      -- the theme's cog
Kit.RegisterIcon("icon.help.tour", { icon = "Tour" })                           -- the theme's map drawing (no signpost in the theme)
Kit.RegisterIcon("icon.help.new", { game = { I .. "INV_Misc_Note_02", I .. "INV_Misc_Note_01" } })   -- gap: no star in the theme
Kit.RegisterIcon("icon.help.check", { mark = "Check" })
Kit.RegisterIcon("icon.help.report", { icon = "Flag" })
Kit.RegisterIcon("icon.help.noted", { game = { I .. "INV_Misc_Note_01", I .. "INV_Scroll_03" } })    -- gap: no list drawing in the theme
Kit.RegisterIcon("icon.help.sharing", { glyph = "Lock" })
Kit.RegisterIcon("icon.help.everywhere", { icon = "Logo" })                     -- the Panoply crest

-- the four sections, in order (spec 06 section 2)
Help.SECTIONS = {
  { key = "start", label = "Get started" },
  { key = "tips", label = "Tips by page" },
  { key = "commands", label = "Commands" },
  { key = "problems", label = "Problems" },
}
Help.INDEX_W = 220
Help.SEARCH_HINT = "Search help"

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------
local NUM = { "One", "Two", "Three", "Four", "Five", "Six" }

-- The commands list, made from the command registry (Help:Command, Core/HelpRegistry.lua; each command registers itself beside its
-- handler, in Core/Slash.lua and the modules). Each row keeps the shape { command, what it does (with its other names), module };
-- a row with no command shows its note in the command's place.
function Help.Commands()
  local out = {}
  for _, r in ipairs(Help:CommandList()) do
    local also = Help.AliasText(r)
    local desc = r.desc
    if also then desc = desc .. " (" .. also .. ")" end
    if r.usage then out[#out + 1] = { r.usage, desc, r.module, row = r }
    elseif r.note then out[#out + 1] = { r.note, "", r.module, row = r } end
  end
  return out
end

-- Every tip that applies, as { title, body } (from the help registry).
function Help.Tips()
  return Help:AllTips()
end

-- The installed version, read from the add-on's TOC (the same number Panoply.version carries; What's new uses the same).
function Help.Version()
  local WN = Panoply.WhatsNew
  if WN and WN.InstalledVersion then return WN.InstalledVersion() end
  return tostring(Panoply.version)
end

-- Get started (spec 06 section 2.1): three rows, each an icon, a title, one muted line and one button.
function Help.Rows()
  local n = Panoply.Wizard and #Panoply.Wizard:Steps() or 4
  local v = Help.Version():match("^(%d+%.%d+%.%d+)") or Help.Version()
  return {
    { key = "setup", icon = "icon.help.setup", title = "Run setup", button = "Run setup",
      desc = ("%s short questions. Nothing changes until you press Start guiding."):format(NUM[n] or tostring(n)),
      tip = "Run setup", body = "Asks the setup questions again for the character you are playing. Nothing changes until you press Start guiding.",
      run = function() Panoply.Wizard:Start() end },
    { key = "tour", icon = "icon.help.tour", title = "Take the tour", button = "Start the tour",
      desc = "A short walk through the window.",
      tip = "Take the tour", body = Panoply.Catalog.UI_HELP.tour, run = function() Panoply.Tour:Start() end },
    { key = "whatsnew", icon = "icon.help.new", title = "What's new", button = "Show what's new",
      desc = ("What changed in version %s."):format(v),
      tip = "What's new", body = Panoply.Catalog.UI_HELP.whatsNew, run = function() Panoply.WhatsNew:Show(true) end },
  }
end

-- How many noted problems were last seen in the past 7 days, and how many there are in all.
function Help.NotedCounts(at)
  local R = Panoply.Reports
  local now = at or ((_G.time and _G.time()) or os.time())
  local week, all = 0, 0
  for _, e in pairs(R and R.db and R.db.errors or {}) do
    if type(e) == "table" then
      all = all + 1
      if (tonumber(e.last) or 0) >= now - 7 * 86400 then week = week + 1 end
    end
  end
  return week, all
end

-- "3 problems noted this week" (spec 06 section 2.4); "No problems noted this week" when none.
function Help.NotedLine(at)
  local week, all = Help.NotedCounts(at)
  if week == 0 then
    if all == 0 then return "No problems noted." end
    return ("No problems noted this week (%d older)."):format(all)
  end
  return ("%d problem%s noted this week"):format(week, week == 1 and "" or "s")
end

-- The things Panoply Suite does for you, with each one's state and the page that owns its switch (spec 06 section 2.2).
function Help.Automation()
  local db = Panoply.db or {}
  local list = {
    { key = "autoAccept", label = "Accept quests", page = "guide", on = db.autoAccept ~= false },
    { key = "autoTurnIn", label = "Turn in quests", page = "guide", on = db.autoTurnIn ~= false },
    { key = "autoFly", label = "Take flight paths", page = "guide", on = db.autoFly == true },
  }
  if Panoply.Modules and Panoply.Modules:IsOn("merchant") then
    local M = Panoply.Merchant
    local mdb = M and M.db or db
    list[#list + 1] = { key = "autoRepair", label = "Repair your gear", page = "misc", on = mdb.autoRepair ~= false }
    list[#list + 1] = { key = "autoSellJunk", label = "Sell grey items", page = "misc", on = mdb.autoSellJunk ~= false }
  end
  for _, a in ipairs(list) do
    local pg = Panoply.Catalog and Panoply.Catalog[a.page]
    a.pageLabel = (type(pg) == "table" and pg.label) or (a.page == "misc" and "Field Kit" or "Guide")
  end
  return list
end

-- Nov 2026: the About block, at the end of Get started: the version (from the TOC, never typed), the licence, where the source
-- code is, and where the full credits are (0.9.9.5: the credits themselves are in NOTICE.md and on the listing, not here). A game window cannot open a web link, so the address is a
-- selectable box (the same read-only copy pattern as UI/ReportCopy.lua): select it, press Ctrl+C (Cmd+C on a Mac).
Help.SOURCE_URL = "github.com/panoplyhub/panoply-suite"
function Help.About()
  return {
    title = "About Panoply Suite",
    version = "Version " .. Help.Version(),
    lines = {
      "Panoply Suite is free and open source, under the GNU GPL v3.",
      "Its source code is at the address below. Select it and press Ctrl+C (Cmd+C on a Mac) to copy it.",
      "Every credit and licence is written out in NOTICE.md, in the Panoply Suite add-on folder.",
    },
    addressAfter = 2,            -- the address box sits under this line
    address = Help.SOURCE_URL,
  }
end

-- all of the About text as one string (the tests read it)
function Help.AboutText()
  local a = Help.About()
  return table.concat({ a.title, a.version, table.concat(a.lines, "\n"), a.address }, "\n")
end

-------------------------------------------------------------------------------
-- Search help: tips, commands and settings together (spec 06 section 2)
-------------------------------------------------------------------------------
local function lower(s) return tostring(s or ""):lower() end
local function plain(s) return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
local function hasAll(hay, words)
  hay = lower(hay)
  for _, w in ipairs(words) do if not hay:find(w, 1, true) then return false end end
  return true
end

-- { { kind = "tip" | "command" | "setting" | "page" | "action", label, where, ... }, ... } (at most max of each kind)
function Help:Search(text, maxEach)
  maxEach = maxEach or 6
  local words = {}
  for w in lower(text):gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return {} end
  local out = {}
  local n = 0
  for _, e in ipairs(self:Entries()) do
    for _, t in ipairs(e.tips) do
      if n < maxEach and hasAll(plain(t[1]) .. " " .. plain(t[2]) .. " " .. (e.label or ""), words) then
        n = n + 1
        out[#out + 1] = { kind = "tip", label = plain(t[1]), body = plain(t[2]), where = e.label, page = e.key }
      end
    end
  end
  n = 0
  for _, c in ipairs(self:CommandList()) do
    local text2 = table.concat({ c.usage or "", c.desc or "", table.concat(c.aliases or {}, " "), c.note or "" }, " ")
    if n < maxEach and hasAll(text2, words) then
      n = n + 1
      out[#out + 1] = { kind = "command", label = c.usage or c.note, body = c.desc, row = c }
    end
  end
  local Cat = Panoply.Catalog
  if Cat and Cat.Search then
    local ok, hits = pcall(Cat.Search, Cat, text, maxEach)
    for _, h in ipairs(ok and hits or {}) do
      local e = h.entry
      local where
      if e.kind == "setting" then where = e.page.label .. " > " .. e.section.title
      elseif e.kind == "control" then where = e.page.label
      elseif e.kind == "page" then where = "Page" else where = "Action" end
      out[#out + 1] = { kind = e.kind == "setting" and "setting" or e.kind, label = plain(e.label), where = where, entry = e }
    end
  end
  return out
end

-- Open one search result: a setting opens the same way the top All settings box does; a command goes into the chat box; a tip opens its
-- page's row in Tips by page.
function Help:OpenResult(r, p)
  if not r then return end
  if r.kind == "command" then return Help.PasteCommand(r.row) end
  if r.kind == "tip" then
    if p then
      p.query = ""
      if p.search then p.search:SetText("") end
      Help.SetSection("tips")
      Kit.SetOpen("help", "tip:" .. tostring(r.page), true)
      Menu:RefreshCurrent()
    end
    return
  end
  local e = r.entry
  if not e then return end
  if e.kind == "setting" then
    Menu:OpenGear(e.page.key, e.section.key, Panoply.Catalog.RowId(e.row), e.advanced)
  elseif e.kind == "action" then
    if e.run then e.run() end
  elseif e.page then
    Menu:Select(e.page.key)
  end
end

-------------------------------------------------------------------------------
-- Which section shows (kept for the session, like a page's tab)
-------------------------------------------------------------------------------
-- The index is the kit's tabs (a rail on a Wide page, one dropdown on Medium and Narrow): the choice is remembered, goes into the
-- window's back and forward history, and Reset view puts it back, the same as every page's tabs.
function Help.Section()
  if Help.tabs then return Help.tabs:Current() end
  local cur = Kit.GetTab("help", function(t) for _, s in ipairs(Help.SECTIONS) do if s.key == t then return true end end return false end)
  return cur or "start"
end
function Help.SetSection(key)
  if Help.tabs then return Help.tabs:Select(key) end
  Kit.SetTab("help", key)
  if Menu.current == "help" and Menu.frame and Menu.frame:IsShown() then Menu:RefreshCurrent() end
end

-- "Check for problems" (spec 06 section 2.4): the result inline, not a pop-up. { ok = true } or { issues = { { text, fix } } }
function Help.CheckProblems()
  local T = Panoply.SelfTest
  if not T then return { issues = { { text = "The self-test is not loaded." } } } end
  local res = T:Run(true)
  local issues = {}
  for _, r in ipairs(res and res.results or {}) do
    -- (a WARN is normal in places, such as no position inside a dungeon: only a failure or a missing part is a problem)
    if r.status == "FAIL" or r.status == "MISSING" then
      issues[#issues + 1] = { text = ("Problem: %s%s"):format(r.name, r.detail and (" (" .. tostring(r.detail) .. ")") or ""),
        status = r.status, name = r.name, detail = r.detail }
    end
  end
  Help.lastCheck = { ok = #issues == 0, issues = issues, counts = res and res.counts }
  return Help.lastCheck
end

-------------------------------------------------------------------------------
-- Building blocks
-------------------------------------------------------------------------------
local TH, TW = Skin.TextHeight, Skin.TextWidth

local function iconTex(parent, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size or 20, size or 20)
  return t
end

-- a reusable pool of objects made by make(i)
local function pool(list, i, make)
  local o = list[i]
  if not o then o = make(i) list[i] = o end
  return o
end

local function place(fs, parent, x, y, w)
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); fs:SetWidth(w)
  local h = TH(fs, w); fs:SetHeight(h)
  return h
end

-- a row card: icon, title, one muted line, a button on the right (Get started and Problems)
local function rowCard(parent, def)
  local c = Skin.Card(parent)
  c.panoplyGapOK = true
  c.key = def.key
  c.icon = iconTex(c, 20)
  c.panoplyIconHow = Kit.Icon(c.icon, def.icon, { size = 20 })
  c.title = Skin.Name(c, 14, Skin.colors.text); c.title:SetText(def.title or "")
  c.desc = Skin.Ink(c, 12, Skin.colors.inkSoft); c.desc:SetText(def.desc or "")
  if def.button then c.button = Skin.Button(c, def.button, 120, 30, def.run, def.tip, def.body) end
  -- lays the card out at width w; extra(c, x, y, tw) may add lines under the muted one and returns their height
  function c:Fit(w, extra)
    local pad = 14
    local bw = 0
    if self.button and self.button:IsShown() then bw = Skin.FitButton(self.button, 110, floor(w * 0.4)) end
    if self.side and self.side:IsShown() then bw = max(bw, self.side:GetWidth() or 0) end
    local x0 = pad + 20 + SP.m
    local tw = w - x0 - pad - (bw > 0 and (bw + SP.m) or 0)
    self.icon:ClearAllPoints(); self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -12)
    local y = -12
    y = y - place(self.title, self, x0, y, tw)
    if (self.desc:GetText() or "") ~= "" then
      self.desc:Show()
      y = y - SP.xs - place(self.desc, self, x0, y - SP.xs, tw)
    else self.desc:Hide() end
    if extra then y = y - extra(self, x0, y, tw) end
    local bh = self.button and self.button:IsShown() and self.button:GetHeight() or 0
    local h = max(-y + 12, bh + 24)
    self:SetSize(w, h)
    if self.button and self.button:IsShown() then
      self.button:ClearAllPoints(); self.button:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, -max(12, (min(h, 12 + 24 + bh) - bh) / 2))
    end
    if self.side and self.side:IsShown() then
      self.side:ClearAllPoints(); self.side:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, -12)
    end
    return h
  end
  return c
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
Menu:RegisterTab("Help", function(p)
  p.query = ""
  -- Search help, full width under the header
  local box = Skin.Input(p, 300, 28, Help.SEARCH_HINT)
  box:SetScript("OnTextChanged", function(self, user)
    if self.placeholder then if (self:GetText() or "") == "" then self.placeholder:Show() else self.placeholder:Hide() end end
    if user then
      p.query = self:GetText() or ""
      Menu:RefreshCurrent()
    end
  end)
  box:SetScript("OnEscapePressed", function(self) self:SetText("") p.query = "" self:ClearFocus() Menu:RefreshCurrent() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() if p.results and p.results[1] then Help:OpenResult(p.results[1], p) end end)
  p.search = box
  -- the index: the kit's tabs, a rail on the left (Wide) or one dropdown under the search box (Medium and Narrow)
  local items = {}
  for _, s in ipairs(Help.SECTIONS) do items[#items + 1] = { key = s.key, label = s.label, tipBody = ("Shows %s."):format(s.label) } end
  p.tabs = Kit.Tabs(p, { page = "help", orientation = "side", items = items, default = "start" })
  Help.tabs = p.tabs
  p.index = p.tabs.buttons
  -- each section has its own frame
  p.secs = {}
  for _, s in ipairs(Help.SECTIONS) do
    local f = CreateFrame("Frame", nil, p)
    f.panoplyGapOK = true
    f:SetSize(10, 10)
    p.secs[s.key] = f
  end
  p.resultsFrame = CreateFrame("Frame", nil, p); p.resultsFrame.panoplyGapOK = true; p.resultsFrame:SetSize(10, 10)
  p.resultHead = Skin.Ink(p.resultsFrame, 12, Skin.colors.inkSoft)
  p.resultRows = {}

  -- GET STARTED
  local st = p.secs.start
  p.rows, p.buttons = {}, {}
  for i, r in ipairs(Help.Rows()) do
    local c = rowCard(st, r)
    p.rows[i] = c
    p.buttons[#p.buttons + 1] = c.button
  end
  local ab = CreateFrame("Frame", nil, st)
  ab.panoplyGapOK = true
  ab.title = Skin.Name(ab, 15, Skin.colors.heading)
  ab.version = Skin.Ink(ab, 12, Skin.colors.goldBright)
  ab.lines = {}
  for i = 1, #Help.About().lines do ab.lines[i] = Skin.Ink(ab, 12, Skin.colors.inkSoft) end
  local abox = Skin.Input(ab, 300, 28, "")
  abox.panoplyLayoutSkip = true      -- selectable text, not laid out by us
  if abox.icon then abox.icon:Hide() end
  if abox.placeholder then abox.placeholder:Hide() end
  if abox.SetTextInsets then abox:SetTextInsets(10, 8, 0, 0) end
  -- read-only: what is typed is put back; clicking into it selects the whole address, ready for Ctrl+C
  abox:SetScript("OnTextChanged", function(self, user)
    if user and self:GetText() ~= Help.SOURCE_URL then self:SetText(Help.SOURCE_URL) end
  end)
  abox:HookScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
  ab.box = abox
  p.about = ab

  -- TIPS BY PAGE
  -- COMMANDS
  p.cmdHeads, p.cmdRows = {}, {}
  -- PROBLEMS
  local pr = p.secs.problems
  p.check = rowCard(pr, { key = "check", icon = "icon.help.check", title = "Check for problems", button = "Check",
    desc = "Panoply Suite checks itself and shows what, if anything, is wrong.", tip = "Check for problems",
    body = "Checks that Panoply Suite works on this game version. The result shows here.",
    run = function() Help.CheckProblems() Menu:RefreshCurrent() end })
  p.checkLines = {}
  p.report = rowCard(pr, { key = "report", icon = "icon.help.report", title = "Report a problem", button = "Report",
    desc = "Tell us about a bug, a wrong step or an idea.", tip = "Report a problem", body = "The Report a problem window opens.",
    run = function() Panoply.ReportWindow:Open({ general = true }) end })
  p.noted = rowCard(pr, { key = "noted", icon = "icon.help.noted", title = "Noted problems", button = "Noted problems",
    desc = "", tip = "Noted problems", body = "Panoply Suite's own errors, as a readable list.",
    run = function() Panoply.ReportWindow:OpenProblems() end })
  p.sharing = rowCard(pr, { key = "sharing", icon = "icon.help.sharing", title = "Sharing", desc = "" })
  p.shareSwitch = Skin.Switch(p.sharing, function()
    Panoply.Sharing:Set(not Panoply.Sharing:On())
    Menu:RefreshCurrent()
  end, Panoply.Sharing.SETTING, "Turns this setting on or off. The line beside it says where reports go now.")
  p.sharing.side = p.shareSwitch
  p.shareLabel = Skin.Ink(p.sharing, 12, Skin.colors.text)
  p.buttons[#p.buttons + 1] = p.check.button
  p.buttons[#p.buttons + 1] = p.report.button
  p.buttons[#p.buttons + 1] = p.noted.button

  -- the tips' rows: one kit section per page (its icon, name and subtitle in the header; closed at first), Everywhere first
  p.tipSecs = {}
  p.tipSec = function(e)
    local r = p.tipSecs[e.key]
    if r then return r end
    local sec = Kit.Section(p.secs.tips, "help", "tip:" .. e.key, { title = e.label, open = false,
      icon = function(t)
        if r.entryKey == Help.EVERYWHERE then r.panoplyIconHow = Kit.Icon(t, "icon.help.everywhere", { size = 18 })
        elseif r.iconName then Skin.SetIcon(t, r.iconName, { size = 18, own = true }) end
      end })
    r = { sec = sec, tips = {}, auto = {}, entryKey = e.key }
    local body = sec.body
    r.open = Skin.Button(body, "Open page", 110, 26, function(self) if self.pageKey then Menu:Select(self.pageKey) end end, "Open page", "Opens this page.")
    -- Everywhere's "Things it does for you" (spec 06 section 2.2): a heading, then one line per automatic action
    r.autoHead = Skin.Name(body, 13, Skin.colors.heading)
    r.autoHead:SetText("Things it does for you")
    r.autoHead:Hide()
    p.tipSecs[e.key] = r
    return r
  end
  p.cmdRow = function(i)
    return pool(p.cmdRows, i, function()
      local b = Skin.Button(p.secs.commands, "", 100, 30, function(self) if self.row then Help.PasteCommand(self.row) end end, nil, nil)
      b.label:SetText("")
      b.cmd = Skin.Text(b, 12, Skin.colors.goldBright)
      b.desc = Skin.Ink(b, 12)
      b.also = Skin.Ink(b, 11, Skin.colors.inkSoft)
      return b
    end)
  end
  p.cmdHead = function(i) return pool(p.cmdHeads, i, function() return Skin.Label(p.secs.commands, 11, Skin.colors.accent) end) end
  p.resultRow = function(i)
    return pool(p.resultRows, i, function()
      local b = Skin.Button(p.resultsFrame, "", 100, 40, function(self) Help:OpenResult(self.result, p) end, nil, nil)
      b.label:SetText("")
      b.path = Skin.Label(b, 9, Skin.colors.accent)
      b.name = Skin.Text(b, 13, Skin.colors.text)
      return b
    end)
  end

  ---------------------------------------------------------------------------
  function p:Layout()
    local W = self.width - 4
    local band = Kit.Band(self.width)
    local y = 0
    -- search, full width
    self.search:ClearAllPoints(); self.search:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -y); self.search:SetSize(W, 28)
    y = y + 28 + SP.m
    local cur = Help.Section()
    local x0, cw
    if band == "wide" then
      local _, ih = self.tabs:Layout(2, -y, Help.INDEX_W)
      x0 = 2 + Help.INDEX_W + SP.l
      cw = W - Help.INDEX_W - SP.l
      self.indexBottom = y + ih
    else
      local dh = self.tabs:Layout(2, -y, min(260, W), "dropdown")
      y = y + dh + SP.m
      x0, cw = 2, W
      self.indexBottom = y
    end
    self.pick = self.tabs.dd
    local searching = #((self.query or ""):gsub("%s", "")) >= 2
    local h = 0
    for k, f in pairs(self.secs) do if k ~= cur or searching then f:Hide() end end
    if searching then
      self.resultsFrame:Show()
      self.resultsFrame:ClearAllPoints(); self.resultsFrame:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y); self.resultsFrame:SetWidth(cw)
      h = self:LayoutResults(cw)
      self.resultsFrame:SetHeight(max(1, h))
    else
      self.resultsFrame:Hide()
      local f = self.secs[cur]
      f:Show()
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y); f:SetWidth(cw)
      local fn = self["Layout_" .. cur]
      h = fn and fn(self, f, cw) or 0
      f:SetHeight(max(1, h))
    end
    return max(y + h, self.indexBottom or 0) + SP.s
  end

  function p:Layout_start(f, w)
    local y = 0
    for _, c in ipairs(self.rows) do
      local h = c:Fit(w)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      y = y + h + SP.s
    end
    -- About
    y = y + SP.m
    local ab = self.about
    ab:ClearAllPoints(); ab:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y); ab:SetSize(w, 10)
    local ay = 0
    local function put(fs, gap)
      ay = ay - place(fs, ab, 0, ay, w) - gap
    end
    put(ab.title, SP.s)
    put(ab.version, SP.m)
    local about = Help.About()
    for i, l in ipairs(ab.lines) do
      put(l, (i == about.addressAfter) and SP.s or SP.m)
      if i == about.addressAfter then
        ab.box:ClearAllPoints(); ab.box:SetPoint("TOPLEFT", ab, "TOPLEFT", 0, ay)
        ab.box:SetSize(min(w, 300), 28)
        ay = ay - 28 - SP.m
      end
    end
    ab:SetHeight(max(1, -ay))
    return y - ay
  end

  function p:Layout_tips(f, w)
    local y = 0
    local hx = Kit.SECTION.textX
    for _, e in ipairs(self.entries or {}) do
      local r = self.tipSecs[e.key]
      if r then
        local sec = r.sec
        local _, open = sec:Begin(f, 0, -y, w)
        local ry = 0
        if open then
          local body = sec.body
          local tw = w - hx - 14
          ry = SP.xs
          for _, t in ipairs(r.tips) do
            if t.a:IsShown() then
              ry = ry + place(t.a, body, hx, -ry, tw) + 2
              ry = ry + place(t.b, body, hx, -ry, tw) + SP.s
            end
          end
          if r.autoHead:IsShown() then ry = ry + place(r.autoHead, body, hx, -ry, tw) + SP.xs end
          for _, a in ipairs(r.auto) do
            if a.text:IsShown() then
              local bw = Skin.FitButton(a.link, 80, floor(tw * 0.35))
              local lw = tw - bw - SP.m
              local lh = place(a.text, body, hx, -ry, lw)
              a.link:ClearAllPoints(); a.link:SetPoint("TOPLEFT", body, "TOPLEFT", hx + lw + SP.m, -ry + 2)
              ry = ry + max(lh, a.link:GetHeight()) + SP.xs
            end
          end
          if r.open:IsShown() then
            Skin.FitButton(r.open, 100, tw)
            r.open:ClearAllPoints(); r.open:SetPoint("TOPLEFT", body, "TOPLEFT", hx, -ry)
            ry = ry + r.open:GetHeight() + SP.s
          end
        end
        y = y + sec:Done(ry) + SP.s
      end
    end
    return y
  end

  function p:Layout_commands(f, w)
    local y = 0
    local list = self.cmdList or {}
    local hi, ri = 0, 0
    local cmdW = 0
    for i = 1, #list do
      local b = self.cmdRows[i]
      if b and b.cmd:IsShown() then cmdW = max(cmdW, ceil(TW(b.cmd)) + 4) end
    end
    cmdW = min(cmdW, floor(w * 0.42))
    for _, item in ipairs(self.cmdLayout or {}) do
      if item.head then
        hi = hi + 1
        local hfs = self.cmdHeads[hi]
        if y > 0 then y = y + SP.s end
        y = y + place(hfs, f, 2, -y, w) + SP.xs
      else
        ri = ri + 1
        local b = self.cmdRows[ri]
        local dw = w - cmdW - 3 * SP.m
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y); b:SetWidth(w)
        local ch = place(b.cmd, b, SP.m, -6, cmdW)
        local dh = place(b.desc, b, SP.m + cmdW + SP.m, -6, dw)
        if (b.also:GetText() or "") ~= "" then b.also:Show() dh = dh + 2 + place(b.also, b, SP.m + cmdW + SP.m, -6 - dh - 2, dw) else b.also:Hide() end
        local h = max(ch, dh) + 12
        b:SetHeight(h)
        y = y + h + 2
      end
    end
    return y
  end

  function p:Layout_problems(f, w)
    local y = 0
    local function card(c, extra)
      local h = c:Fit(w, extra)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      y = y + h + SP.s
    end
    card(self.check, function(c, x, cy, tw)
      local hgt = 0
      for _, l in ipairs(self.checkLines) do
        if l.fs:IsShown() then
          local lw = tw - (l.fix:IsShown() and (Skin.FitButton(l.fix, 70, floor(tw * 0.4)) + SP.m) or 0)
          local lh = place(l.fs, c, x, cy - SP.s - hgt, lw)
          if l.fix:IsShown() then l.fix:ClearAllPoints(); l.fix:SetPoint("TOPLEFT", c, "TOPLEFT", x + lw + SP.m, cy - SP.s - hgt + 2) lh = max(lh, l.fix:GetHeight()) end
          hgt = hgt + lh + SP.xs
        end
      end
      return hgt > 0 and (hgt + SP.s) or 0
    end)
    card(self.report)
    card(self.noted)
    -- Sharing: the state line, then the setting with its switch
    card(self.sharing, function(c, x, cy, tw)
      local sw = self.shareSwitch
      local lh = place(self.shareLabel, c, x, cy - SP.s, tw - 46 - 54 - 40)
      sw:ClearAllPoints(); sw:SetPoint("TOPLEFT", c, "TOPLEFT", x + tw - 46 - 54 - 24, cy - SP.s)
      return max(lh, 24) + SP.s
    end)
    return y
  end

  function p:LayoutResults(w)
    local y = 0
    y = y + place(self.resultHead, self.resultsFrame, 2, 0, w) + SP.s
    for i, b in ipairs(self.resultRows) do
      local r = self.results and self.results[i]
      if not r then b:Hide() else
        b:Show()
        local lw = w - 20
        local ph = place(b.path, b, 10, -6, lw)
        local nh = place(b.name, b, 10, -6 - ph - 2, lw)
        local h = max(36, 6 + ph + 2 + nh + 6)
        b:SetSize(w, h)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", self.resultsFrame, "TOPLEFT", 0, -y)
        y = y + h + 2
      end
    end
    return y
  end
end, function(p)
  -- Get started
  for i, r in ipairs(Help.Rows()) do
    local c = p.rows[i]
    c.title:SetText(r.title)
    c.desc:SetText(r.desc)
    c.button.tipBody = r.body
  end
  local about = Help.About()
  p.about.title:SetText(about.title)
  p.about.version:SetText(about.version)
  for i, l in ipairs(about.lines) do p.about.lines[i]:SetText(l) end
  p.about.box:SetText(about.address)
  -- Tips by page (from the help registry, Everywhere first, in nav order)
  p.entries = Help:Entries()
  local present = {}
  for _, e in ipairs(p.entries) do
    present[e.key] = true
    local r = p.tipSec(e)
    r.iconName = e.icon
    r.sec:SetTitle(e.label)
    r.sec:SetSummary(e.subtitle or "")
    local body = r.sec.body
    local tips = e.tips or {}
    for k = 1, max(#tips, #r.tips) do
      local t = r.tips[k]
      if not t then
        t = { a = Skin.Name(body, 13, Skin.colors.heading), b = Skin.Ink(body, 12) }
        r.tips[k] = t
      end
      local tip = tips[k]
      if tip then t.a:SetText(tip[1]) t.b:SetText(tip[2]) t.a:Show() t.b:Show() else t.a:SetText("") t.b:SetText("") t.a:Hide() t.b:Hide() end
    end
    -- Everywhere: the things it does for you, each with its state and the page that owns its switch
    local auto = e.key == Help.EVERYWHERE and Help.Automation() or {}
    for k = 1, max(#auto, #r.auto) do
      local a = r.auto[k]
      if not a then
        a = { text = Skin.Ink(body, 12) }
        a.link = Skin.Button(body, "", 80, 24, function(self) if self.pageKey then Menu:OpenGear(self.pageKey) end end, nil, nil)
        r.auto[k] = a
      end
      local it = auto[k]
      if it then
        a.text:SetText(("%s: %s"):format(it.label, it.on and "On" or "Off"))
        a.link.label:SetText(it.pageLabel)
        a.link.pageKey = it.page
        a.link.tip, a.link.tipBody = it.pageLabel, ("Its switch is in the %s page's settings."):format(it.pageLabel)
        a.text:Show() a.link:Show()
      else a.text:SetText("") a.text:Hide() a.link:Hide() end
    end
    if #auto > 0 then r.autoHead:Show() else r.autoHead:Hide() end
    if e.key == Help.EVERYWHERE then r.open:Hide() r.open.pageKey = nil else r.open:Show() r.open.pageKey = e.key end
  end
  for key, r in pairs(p.tipSecs) do if not present[key] then r.sec:Hide() end end
  -- Commands, grouped
  local list = Help:CommandList()
  p.cmdList = list
  p.cmdLayout = {}
  local hi, ri = 0, 0
  local lastGroup
  for _, c in ipairs(list) do
    if c.group ~= lastGroup and c.key ~= "help" then
      lastGroup = c.group
      hi = hi + 1
      local g = Help.GROUPS[Help.GROUP[c.group] or #Help.GROUPS]
      local hfs = p.cmdHead(hi)
      hfs:SetText(g.label:upper())
      hfs:Show()
      p.cmdLayout[#p.cmdLayout + 1] = { head = true }
    end
    ri = ri + 1
    local b = p.cmdRow(ri)
    b.row = c.usage and c or nil
    b.cmd:SetText(c.usage or c.note or "")
    if c.usage then b.cmd:SetTextColor(Skin.colors.goldBright[1], Skin.colors.goldBright[2], Skin.colors.goldBright[3], 1)
    else b.cmd:SetTextColor(Skin.colors.inkSoft[1], Skin.colors.inkSoft[2], Skin.colors.inkSoft[3], 1) end
    b.desc:SetText(c.usage and c.desc or "")
    b.also:SetText(Help.AliasText(c) or "")
    b.tip = c.usage and c.usage or nil
    b.tipBody = c.usage and "Click to put it in the chat box, ready to send." or nil
    b:SetEnabledLook(c.usage ~= nil)
    b.cmd:Show() b:Show()
    p.cmdLayout[#p.cmdLayout + 1] = { row = ri }
  end
  for i = hi + 1, #p.cmdHeads do p.cmdHeads[i]:Hide() end
  for i = ri + 1, #p.cmdRows do p.cmdRows[i]:Hide() p.cmdRows[i].cmd:Hide() end
  -- Problems
  local chk = Help.lastCheck
  local lines = {}
  if chk then
    if chk.ok then lines[1] = { text = "No problems found." }
    else for _, is in ipairs(chk.issues) do lines[#lines + 1] = is end end
  end
  for k = 1, max(#lines, #p.checkLines) do
    local l = p.checkLines[k]
    if not l then
      l = { fs = Skin.Ink(p.check, 12) }
      l.fix = Skin.Button(p.check, "Report it", 90, 24, function(self) Panoply.ReportWindow:Open({ general = true, note = self.note }) end, "Report it",
        "Opens Report a problem with this line already in the note.")
      p.checkLines[k] = l
    end
    local it = lines[k]
    if it then
      l.fs:SetText(it.text)
      local col = it.status and Skin.colors.warn or Skin.colors.done
      if col then l.fs:SetTextColor(col[1], col[2], col[3], 1) end
      l.fs:Show()
      if it.status then l.fix.note = it.text l.fix:Show() else l.fix:Hide() end
    else l.fs:SetText("") l.fs:Hide() l.fix:Hide() end
  end
  p.noted.desc:SetText(Help.NotedLine())
  p.sharing.desc:SetText(Panoply.Sharing:Line())
  p.shareLabel:SetText(Panoply.Sharing.SETTING)
  p.shareSwitch:SetState(Panoply.Sharing:On())
  -- search results
  local q = p.query or ""
  if #(q:gsub("%s", "")) >= 2 then
    p.results = Help:Search(q, 6)
    p.resultHead:SetText(#p.results == 0 and ('Nothing in Help for "%s"'):format(q) or ('%d result%s for "%s"'):format(#p.results, #p.results == 1 and "" or "s", q))
    for i, r in ipairs(p.results) do
      local b = p.resultRow(i)
      b.result = r
      local kind = ({ tip = "TIP", command = "COMMAND", setting = "SETTING", page = "PAGE", action = "ACTION", control = "THIS PAGE" })[r.kind] or r.kind:upper()
      b.path:SetText(kind .. (r.where and ("  >  " .. r.where:upper()) or ""))
      b.name:SetText(r.label or "")
      b.tip = r.label
      b.tipBody = r.kind == "command" and "Click to put it in the chat box." or (r.kind == "setting" and "Opens the setting, the same way the All settings box does." or r.body)
    end
    for i = #p.results + 1, #p.resultRows do p.resultRows[i].result = nil end
  else
    p.results = nil
  end
end, { scroll = true })

-- the Help page shows the sharing state and the noted count: drawn again when either changes
Panoply:Listen("REPORTS_CHANGED", function()
  if Menu.current == "help" and Menu.frame and Menu.frame:IsShown() then Menu:RefreshCurrent() end
end)
