-- Panoply Suite one-window menu: the gear, the settings panel every page shares. 0.9.5 (docs/specs/page-redesigns-v1.md 1.5) gives
-- it one shape for every page, top to bottom:
--   * the page's name and a button with the profile name (it opens Profiles);
--   * EXACT SIZES: the sliders of this page (when it has any of its own);
--   * COMMON SETTINGS: the 5 or 6 settings most players change (page.front in UI/Catalog.lua);
--   * MORE SETTINGS: every other section of the page as a list of collapsible sections, all there and all closed when the panel
--     opens (a section that is its own feature has its own On / Off switch; rare rows sit behind "Advanced (n)"). A click on a
--     section's header opens it under its header; several can be open at once. A jump from the All settings box or a link opens
--     the section it names and outlines the row. There is no "More settings (n more)" row any more;
--   * at the bottom: "Reset this page" (this page only), "Undo my changes" (once something changed) and "Done".
-- Where it sits follows the page's band (UI/KitParts.lua, Kit.Band): on a Wide page it is a drawer about 420 wide at the right and the
-- page stays visible beside it, laid out again for the room that is left; on a Medium or Narrow page it takes the whole page area
-- (Back, the return chip, Done or the X get out of it). A page whose settings need the width (the Map's Look of the map: page.gearWide)
-- always takes the whole page area.
-- A page's panel holds only that page's settings: a setting lives on exactly one page (the size of every window is on Profiles).
-- While the mouse is on a setting that changes something on the screen (a size, the arrow, a window) the menu window fades to a faint
-- outline, so the real screen shows; it comes back when the mouse leaves. Changes apply at once; there is no Save button.
-- The rows come from UI/Catalog.lua and are drawn by SettingsUI:BuildRows.
local ADDON, Panoply = ...
local Skin, Cat, SUI = Panoply.Skin, Panoply.Catalog, Panoply.SettingsUI
local Gear = { holders = {}, frames = {}, open = false }
Panoply.PageSettings = Gear
local SP = Skin.SP

-- the settings that change something you can see on the screen behind the menu: the mouse resting on one fades the window
Gear.PREVIEW = {}
for _, k in ipairs({ "windowScale", "arrowScale", "arrowAlpha", "arrowShown", "windowAlpha", "windowFade", "windowFadeAlpha", "stepsShown",
  "trackerFontSize", "trackerBgAlpha", "trackerOutline", "trackerHideBlizzard", "bagColumns", "bankColumns", "iconStyle", "minimapButton",
  "trailMinimap", "qpMinimap", "gatherMinimap", "gatherMinimapYards", "gatherFadeNear", "gatherFadeYards", "gatherRings",
  "gatherEdgeFade", "gatherDatabase", "glowStrength", "glowPoor", "glowBadges" }) do Gear.PREVIEW[k] = true end
for _, k in ipairs(Panoply.Look.AllKeys()) do Gear.PREVIEW[k] = true end
-- Step 2 D: a page's gear may open with a panel of its own at the front (the Map page's Look of the map, UI/LookPanel.lua): page.front.panel
-- names it, Gear.PANELS[name].Build(parent, width, y, page) builds it and returns { height, Widget(key), Reveal(key), Refresh(), All() }.
-- A page whose gear needs the room (the Map page: two columns beside a list) says page.gearWide and gets the width of the page.
Gear.PANELS = {}
Gear.held = {}      -- the sliders whose knob is held right now
Gear.FADE = 0.2     -- how much of the menu window is left while it shows the real screen
Gear.DRAWER_W = 420 -- the drawer beside a Wide page
Gear.SEC_PAD = 8    -- a section's rows sit this far inside its card

local function history() return Panoply.History end

function Gear:Create()
  if self.sheet then return self.sheet end
  local Menu = Panoply.Menu
  local f = CreateFrame("Frame", nil, Menu.area)
  Skin.Panel(f, 1, nil, "M", true)
  f.panoplyGapOK = true
  -- the gear stays whole while the window behind it fades (Gear:Preview)
  if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
  f.title = Skin.Heading(f, 16)
  f.close = Skin.IconButton(f, "x", 24, function() Gear:Close() end, "Close", Cat.UI_HELP.close)
  f.profile = Skin.Button(f, "Profile", 140, 28, function() Gear:OpenProfiles() end, "Profile", Cat.UI_HELP.profile)
  f.scroll = Skin.ScrollArea(f)
  f.rule = f:CreateTexture(nil, "ARTWORK"); Skin.Solid(f.rule, Skin.colors.hairline, 1); f.rule:SetHeight(1)
  f.reset = Skin.Button(f, "Reset this page", 150, 28, function() Gear:AskReset() end, "Reset this page", Cat.UI_HELP.reset)
  f.undo = Skin.Button(f, "Undo my changes", 150, 28, function() Gear:Undo() end, "Undo my changes", Cat.UI_HELP.undo)
  f.done = Skin.Button(f, "Done", 90, 28, function() Gear:Close() end, "Done", Cat.UI_HELP.done)
  f.ask = Skin.Text(f, 11, Skin.colors.warn)
  f.yes = Skin.Button(f, "Yes, reset them", 140, 28, function() Gear:DoReset() end, "Yes, reset", "Put them back to standard now.")
  f.yes.panoplyDanger = true; f.yes:Paint("up")
  f.no = Skin.Button(f, "Keep them", 100, 28, function() Gear:AskReset(false) end, "Keep them", "Do nothing.")
  f:Hide()
  self.sheet = f
  Panoply:Listen("OPTION_CHANGED", function(key)
    -- a module's own switch changes which blocks a "dynamic" section lists: build it again (the Look of the map follows it in Refresh)
    if type(key) == "string" and key:find("^module:") then Gear:DropDynamic() end
    if Gear.open and not Panoply.Menu.batching then Gear:RefreshRows() end
  end)
  Panoply:Listen("MODULE_CHANGED", function() Gear:DropDynamic() if Gear.open then Gear:RefreshRows() end end)
  Panoply:Listen("REPORTS_CHANGED", function() if Gear.open then Gear:RefreshRows() end end)
  Panoply:Listen("PACE_CHANGED", function() if Gear.open then Gear:RefreshRows() end end)
  Panoply:Listen("PROFILES_CHANGED", function() if Gear.open then Gear:LayoutHead() end end)
  return f
end

-------------------------------------------------------------------------------
-- Rows: built once into a frame, with the live preview hooked in
-------------------------------------------------------------------------------
local function previewHook(w)
  if not (w.panoplyKey and Gear.PREVIEW[w.panoplyKey] and w.HookScript) then return end
  w:HookScript("OnEnter", function() Gear:Preview(true) end)
  w:HookScript("OnLeave", function() if not w.panoplyHeld then Gear:Preview(false) end end)
  if w.panoplyRow and w.panoplyRow.type == "slider" then
    -- a knob being dragged keeps the window faded even when the mouse leaves the track
    w:HookScript("OnMouseDown", function() w.panoplyHeld = true Gear.held[w] = true Gear:Preview(true) end)
    w:HookScript("OnMouseUp", function() w.panoplyHeld = nil Gear.held[w] = nil if not (w.IsMouseOver and w:IsMouseOver()) then Gear:Preview(false) end end)
  end
end

Gear.PreviewHook = previewHook

local function build(parent, rows, y, W)
  local made
  made, y = SUI:BuildRows(parent, rows, 0, y, W, true)
  for _, w in ipairs(made) do
    if w.panoplyReadout then w.panoplyBuilt = w.panoplyHeight end
    previewHook(w)
    -- a row that draws itself (a button that turns into a question with its answers) may change height when it is refreshed: the
    -- section it is in is measured again, so its card always holds it
    if w.panoplyRow and w.panoplyRow.type == "custom" and type(w.Refresh) == "function" and w.GetHeight then
      local refresh = w.Refresh
      w.panoplyBuiltH = w:GetHeight()
      w.Refresh = function(self, ...)
        local was = self:GetHeight()
        local r = refresh(self, ...)
        if math.abs((self:GetHeight() or 0) - (was or 0)) > 0.5 then Gear:Reflow() end
        return r
      end
    end
  end
  return made, y
end

local function measure(h)
  local y = h.baseH
  -- rows that grew since they were built (a question under a button, a read-out with more lines): the section is as tall as they need
  local grown = 0
  for _, w in ipairs(h.made or {}) do
    if w.panoplyBuiltH and w.GetHeight then grown = grown + math.max(0, (w:GetHeight() or 0) - w.panoplyBuiltH)
    elseif w.panoplyReadout then grown = grown + math.max(0, (w.panoplyHeight or 0) - (w.panoplyBuilt or 0)) end
  end
  y = y + grown
  if h.advBtn then
    y = y + SP.s + 28
    if h.advOpen then
      local delta = 0
      for _, w in ipairs(h.advMade or {}) do if w.panoplyReadout then delta = delta + (w.panoplyHeight or 0) - (w.panoplyBuilt or 0) end end
      y = y + SP.s + h.advH + delta
    end
  end
  return y + SP.m
end

-- the sections of the page's panel: the ones that still hold something once the front rows are taken out
function Gear:MoreSections(page)
  local out = {}
  for _, s in ipairs(Cat:Sections(page)) do
    if s.module or #Cat:SectionRows(s, false, page) + #Cat:SectionRows(s, true, page) > 0 then out[#out + 1] = s end
  end
  return out
end

-- how many settings a section holds here (headings and read-outs are not settings)
function Gear:SectionCount(page, sec)
  local n = 0
  for _, adv in ipairs({ false, true }) do
    for _, row in ipairs(Cat:SectionRows(sec, adv, page)) do
      if row.type ~= "heading" and row.type ~= "subheading" and row.type ~= "readout" then n = n + 1 end
    end
  end
  return n
end

-- what the closed header of a section says at its right: a feature of its own says On or Off first, then how many settings
function Gear:SectionSummary(page, sec)
  local n = self:SectionCount(page, sec)
  local count = ("%d setting%s"):format(n, n == 1 and "" or "s")
  if sec.module and Panoply.Modules.byKey[sec.module] then
    local status = Panoply.Modules:Status(sec.module)
    return tostring(status) .. ", " .. count
  end
  return count
end

-- the rows of one section, built once into a frame under the section's card. A section that is a feature of its own starts with
-- its On / Off switch.
function Gear:Holder(page, sec)
  local key = page.key .. ":" .. sec.key
  local h = self.holders[key]
  if h then return h end
  local fr = self.P
  local sc = fr and fr.secBy[sec.key]
  local parent = sc and sc.card or (fr and fr.body) or self.sheet.scroll.content
  h = CreateFrame("Frame", nil, parent)
  local W = self.rowsW - 2 * Gear.SEC_PAD
  h:SetWidth(W)
  h.sec, h.page, h.panoplyW = sec, page, self.rowsW
  local y = -2
  if sec.module then
    local d = Panoply.Modules.byKey[sec.module]
    h.switch = Skin.Switch(h, function()
      Panoply.Modules:Set(sec.module, not Panoply.Modules:Wanted(sec.module))
      Gear:RefreshRows()
    end, sec.title, "Turns " .. sec.title:lower() .. " on or off.")
    h.status = Skin.Text(h, 11, Skin.colors.inkSoft)
    h.moduleDef = d
  end
  h.layoutHead = function()
    if not h.switch then return 0 end
    h.status:Hide()
    h.switch:SetState(Panoply.Modules:Wanted(sec.module), Panoply.Modules:Status(sec.module), W - 8)
    h.switch:ClearAllPoints(); h.switch:SetPoint("TOPLEFT", h, "TOPLEFT", 4, -2)
    h.switch:Show()
    return 24
  end
  local hh = h.layoutHead()
  if hh > 0 then y = y - hh - SP.s end
  h.made, y = build(h, Cat:SectionRows(sec, false, page), y, W)
  h.baseH = -y
  local adv = Cat:SectionRows(sec, true, page)
  if #adv > 0 then
    local ay = y - SP.s
    local b = Skin.Button(h, "", 150, 28, function() Gear:ToggleAdvanced(h) end, "Advanced", "Settings you rarely need. They are found by the search box too.")
    b.label:SetText("Advanced (" .. #adv .. ")")
    Skin.FitButton(b, 130, W - 12)
    b:SetPoint("TOPLEFT", h, "TOPLEFT", 4, ay)
    h.advBtn = b
    local ah = CreateFrame("Frame", nil, h)
    ah:SetPoint("TOPLEFT", h, "TOPLEFT", 0, ay - 28 - SP.s)
    ah:SetWidth(W)
    h.advHolder = ah
    local advEnd
    h.advMade, advEnd = build(ah, adv, -2, W)
    h.advH = -advEnd
    h.advOffsetY = -(ay - 28 - SP.s)
    ah:SetHeight(h.advH)
    ah:Hide()
    h.advOpen = false
  end
  h.Measure = measure
  h:SetHeight(measure(h))
  h:Hide()
  self.holders[key] = h
  if sc then
    if sc.holder and sc.holder ~= h then sc.holder:Hide() end
    sc.holder = h
  end
  return h
end

-- Sections whose rows depend on which modules are on (sec.dynamic) are built again the next time they are shown; one that is
-- open is rebuilt at once.
function Gear:DropDynamic()
  local again
  for k, h in pairs(self.holders) do
    if h.sec and h.sec.dynamic then
      h:Hide()
      self.holders[k] = nil
      if self.cur == h then self.cur = nil end
      if self.P and self.P.open[h.sec.key] and h.page == self.P.page then again = h.sec.key end
    end
  end
  if again and self.open and self.page then
    local keep = self.sheet.scroll.GetVerticalScroll and self.sheet.scroll:GetVerticalScroll() or 0
    self.cur = self:Holder(self.page, self.P.secBy[again].sec)
    self:RefreshRows()
    self:LayoutContent()
    local sc = self.sheet.scroll
    if sc.SetVerticalScroll then sc:SetVerticalScroll(math.min(keep, sc:MaxScroll())) sc:UpdateBar() end
  end
end

function Gear:ToggleAdvanced(h, open)
  if open == nil then open = not h.advOpen end
  h.advOpen = open
  if h.advHolder then if open then h.advHolder:Show() else h.advHolder:Hide() end end
  h:SetHeight(measure(h))
  if self.P and self.P.open[h.sec.key] and h.page == self.P.page then self:LayoutContent() self.sheet.scroll:UpdateBar() end
end

-------------------------------------------------------------------------------
-- The front, and the sections that follow it, of one page (built once per page and width)
-------------------------------------------------------------------------------
local function heading(parent, text)
  local l = Skin.Label(parent, 10, Skin.colors.inkSoft)
  l:SetText(text)
  return l
end

function Gear:Frame(page)
  local fr = self.frames[page.key]
  if fr and math.abs((fr.width or 0) - self.rowsW) < 1 then return fr end
  if fr then
    fr.body:Hide()
    self.frames[page.key] = nil
    -- its sections' rows were built under its cards: they are built again for the new one
    for k, h in pairs(self.holders) do
      if h.page == page then h:Hide() self.holders[k] = nil if self.cur == h then self.cur = nil end end
    end
  end
  local f = self.sheet
  local W = self.rowsW
  fr = { page = page, width = W, open = {}, order = {}, secs = {}, secBy = {}, moreOpen = false }
  -- one frame holds the front and the sections: the scroll area has a single page in it, as it always had
  local body = CreateFrame("Frame", nil, f.scroll.content)
  body:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 0, 0)
  body:SetWidth(W)
  body:Hide()
  fr.body = body
  local front = CreateFrame("Frame", nil, body)
  front:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  front:SetWidth(W)
  fr.front = front
  local y = -2
  fr.exactMade, fr.commonMade = {}, {}
  local exact = Cat:FrontRows(page, "exact")
  if #exact > 0 then
    local l = heading(front, "EXACT SIZES"); l:SetWidth(W - 12); l:SetPoint("TOPLEFT", front, "TOPLEFT", 4, y)
    y = y - Skin.TextHeight(l) - SP.s
    fr.exactMade, y = build(front, exact, y, W)
  end
  local common = Cat:FrontRows(page, "common")
  if #common > 0 then
    local l = heading(front, "COMMON SETTINGS"); l:SetWidth(W - 12); l:SetPoint("TOPLEFT", front, "TOPLEFT", 4, y)
    y = y - Skin.TextHeight(l) - SP.s
    fr.commonMade, y = build(front, common, y, W)
  end
  -- Step 2 D: the page's own panel (Map: the Look of the map)
  local PB = page.front and page.front.panel and Gear.PANELS[page.front.panel]
  if PB then
    fr.panel = PB.Build(front, W, y, page)
    fr.panelH = fr.panel.height
    y = y - fr.panelH
    fr.panel.onResize = function() Gear:RelayFront(fr) end
  end
  fr.hasFront = #exact + #common > 0 or fr.panel ~= nil
  fr.moreSecs = self:MoreSections(page)
  fr.moreCount = Cat:MoreCount(page)
  if fr.hasFront then y = y - SP.s end
  fr.frontH = fr.hasFront and -y or 0
  front:SetHeight(math.max(1, fr.frontH))
  front:Hide()
  -- the sections: a card each (surface.1, no border), with the kit's chevron header; the rows are built when a section first opens
  if #fr.moreSecs > 0 and fr.hasFront then fr.secLabel = heading(body, "MORE SETTINGS") end
  local K = Panoply.Kit
  for i, sec in ipairs(fr.moreSecs) do
    local card = K.Surface(body, 1)
    local s = { sec = sec, card = card }
    s.strip = K.Strip(card, { Toggle = function() Gear:ToggleSection(sec.key) end })
    s.strip.panoplyGearSection = sec.key
    fr.secs[i], fr.secBy[sec.key] = s, s
  end
  self.frames[page.key] = fr
  return fr
end

-- The page's panel changed height (another thing of the Look of the map has more rows): the front grows or shrinks with it
function Gear:RelayFront(fr)
  if not (fr and fr.panel) then return end
  local delta = fr.panel.height - (fr.panelH or 0)
  if math.abs(delta) < 0.5 then return end
  fr.panelH = fr.panel.height
  fr.frontH = fr.frontH + delta
  fr.front:SetHeight(fr.frontH)
  if self.open and self.P == fr then
    self:LayoutContent()
    self.sheet.scroll:UpdateBar()
  end
end

-- a row changed height by itself: the sections are measured and placed again (not while they are being laid out already)
function Gear:Reflow()
  if not (self.open and self.P and self.sheet) or self.laying then return end
  self:LayoutContent()
  self.sheet.scroll:UpdateBar()
end

-- the sections under the front: each a header, and under an open one its rows
function Gear:LayoutContent()
  local fr = self.P
  if not fr then return end
  self.laying = true
  local sc = self.sheet.scroll
  local K = Panoply.Kit
  local W = self.rowsW
  local y = fr.frontH
  if fr.secLabel then
    fr.secLabel:SetWidth(W - 12)
    fr.secLabel:ClearAllPoints(); fr.secLabel:SetPoint("TOPLEFT", fr.body, "TOPLEFT", 4, -y)
    y = y + Skin.TextHeight(fr.secLabel) + SP.s
  elseif #fr.secs > 0 then
    y = y + 2
  end
  for _, s in ipairs(fr.secs) do
    local sec = s.sec
    local open = fr.open[sec.key] and true or false
    s.card:ClearAllPoints(); s.card:SetPoint("TOPLEFT", fr.body, "TOPLEFT", 0, -y)
    s.card:SetWidth(W)
    local hh = K.LayoutStrip(s.strip, W, sec.title, self:SectionSummary(fr.page, sec), open, 0, 0)
    -- the section's explanation is its header's tooltip, never a paragraph in the panel
    s.strip.tipBody = (sec.text and (sec.text .. " ") or "") .. (open and "Click to close this section." or "Click to open this section.")
    local ch = hh
    if open then
      local h = self:Holder(fr.page, sec)
      if s.holder and s.holder ~= h then s.holder:Hide() end
      s.holder = h
      if h.layoutHead then h.layoutHead() end
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", s.card, "TOPLEFT", Gear.SEC_PAD, -(hh + 2))
      local mh = measure(h)
      h:SetHeight(mh)
      h:Show()
      h.panoplyY = y + hh + 2          -- its top inside the panel's content (Gear:JumpRow)
      ch = hh + 2 + mh
    elseif s.holder then
      s.holder:Hide()
    end
    s.card:SetHeight(ch)
    s.card:Show()
    s.y, s.h = y, ch
    y = y + ch + SP.xs
  end
  fr.moreOpen = next(fr.open) ~= nil
  fr.body:SetHeight(math.max(1, y))
  sc:SetContentHeight(y)
  self.laying = nil
end

-- the section's holder that was opened last and is still open, or nil
local function lastOpen(self, fr)
  for i = #fr.order, 1, -1 do
    local k = fr.order[i]
    if fr.open[k] and fr.secBy[k] then return self:Holder(fr.page, fr.secBy[k].sec) end
  end
  return nil
end
local function forget(list, key)
  for i = #list, 1, -1 do if list[i] == key then table.remove(list, i) end end
end

-- Open or close one section (a click on its header). Other sections stay as they are.
function Gear:ToggleSection(key, open)
  local fr = self.P
  local s = fr and fr.secBy[key]
  if not s then return false end
  if open == nil then open = not fr.open[key] end
  forget(fr.order, key)
  if open then
    fr.open[key] = true
    fr.order[#fr.order + 1] = key
    self.cur = self:Holder(fr.page, s.sec)
  else
    fr.open[key] = nil
    self.cur = lastOpen(self, fr)
  end
  self:RefreshRows()
  self:LayoutContent()
  self.sheet.scroll:UpdateBar()
  self:LayoutFooter()
  local H = history()
  if H then H:Touch() end
  return true
end

-- Open every section (true) or close them all (false); nil flips between "none open" and "the first one open". Kept for the code
-- and the scenes written when the sections sat under one "More settings" row.
function Gear:ToggleMore(open)
  local fr = self.P
  if not fr or #fr.moreSecs == 0 then return end
  if open == nil then open = not fr.moreOpen end
  if open then
    if not fr.moreOpen then self:Select(fr.moreSecs[1].key) end
  else
    for _, s in ipairs(fr.secs) do fr.open[s.sec.key] = nil end
    fr.order = {}
    self.cur = nil
    self:RefreshRows()
    self:LayoutContent()
    self.sheet.scroll:UpdateBar()
    self:LayoutFooter()
  end
end

-------------------------------------------------------------------------------
-- Open, close, sections
-------------------------------------------------------------------------------
-- Where the panel sits for this page at the window's size now: a drawer beside a Wide page, else the whole page area.
function Gear:Layout(page)
  local Menu = Panoply.Menu
  local f = self.sheet
  page = page or self.page
  local W = Menu.bodyW
  -- a drawer when the page is Wide and what is left beside the drawer is still as wide as the page can be laid out for
  -- (page.minWidth, UI/Catalog.lua; a page that does not say lays out for Menu.DRAWER_PAGE_MIN or more)
  local left = W - Gear.DRAWER_W - SP.m
  local drawer = Panoply.Kit.Band(W) == "wide" and not page.gearWide and left >= Menu:PageMinWidth(Menu.pageDef or page, true)
  local sw = drawer and math.min(Gear.DRAWER_W, W) or W
  self.drawer = drawer
  self.rowsW = sw - 32 - 12
  local top = (Menu.headerH or 58) + SP.s
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", Menu.area, "TOPRIGHT", 0, -top)
  local sh = Menu.areaH - top - 2
  f:SetSize(sw, sh)
  f.sw = sw
  f.title:SetText(page.label .. " settings")
  f.close:ClearAllPoints(); f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
  self:LayoutHead()
  -- a section built for another width is rebuilt on its next use
  for k, h in pairs(self.holders) do
    if math.abs((h.panoplyW or 0) - self.rowsW) > 1 then h:Hide() self.holders[k] = nil if self.cur == h then self.cur = nil end end
  end
end

-- the page beside the drawer (Wide), or hidden under the panel (Medium and Narrow)
function Gear:ApplyMode()
  local Menu = Panoply.Menu
  if self.drawer then
    Menu:SetDrawer(self.sheet.sw + SP.m)
    Menu:ShowHost(true)
  else
    Menu:SetDrawer(nil)
    Menu:ShowHost(false)
  end
end

-- the name of the profile the character being played uses
function Gear:ProfileName()
  local P = Panoply.Profiles
  if not P then return nil end
  local mr, mn = P:Me()
  if not mr then return nil end
  return P:Of(mr, mn)
end

-- When the settings cover their page (a Medium or Narrow page), a chip at the head names the page under them and goes back to it:
-- the same as Back. Not beside a Wide page (the page is in view), and not when the settings were reached by a jump from another
-- page (the page header's return chip is the way back then). Returns its width, 0 when it is not shown.
function Gear:LayoutBack()
  local f = self.sheet
  local H = history()
  local Menu = Panoply.Menu
  local show = H and self.open and not self.drawer and Menu.pageDef and not H:Jumped()
  if not show then
    if f.back then f.back:Hide() end
    return 0
  end
  if not f.back then f.back = H.MakeChip(f, function() Gear:Back() end) end
  local w = H.FitChip(f.back, Menu.pageDef.label or "the page", "Closes the settings and shows the page again. The Back arrow at the top does the same.", 150)
  f.back:ClearAllPoints(); f.back:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
  f.back:Show()
  return w
end

-- the chip at the head: one step back when that step is this page without its settings, else the settings just close
function Gear:Back()
  local H = history()
  local prev = H and H:BackTo()
  local cur = H and H.list[H.index]
  if prev and cur and cur.gear and not prev.gear and prev.page == cur.page then return H:Back() end
  self:Close()
end

function Gear:LayoutHead()
  local f = self.sheet
  if not (f and self.page) then return end
  local sw = f.sw or f:GetWidth()
  local name = self:ProfileName()
  local bw = 0
  local cw = self:LayoutBack()
  local left = 16 + (cw > 0 and (cw + SP.s) or 0)
  if name then
    f.profile.label:SetText("Profile: " .. name)
    bw = Skin.FitButton(f.profile, 110, math.floor(sw * 0.45))
    f.profile:ClearAllPoints(); f.profile:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(12 + 24 + SP.s), -12)
    f.profile:Show()
  else f.profile:Hide() end
  local tw = sw - left - 12 - 24 - SP.s - (bw > 0 and (bw + SP.m) or 0)
  -- 0.9.5 phase 4F: on a narrow panel (a page drawn for the Narrow band) the title would be squeezed beside the Profile button into
  -- several lines: the button goes on a line of its own under the title instead
  local below = false
  if bw > 0 then
    f.title:SetWidth(2000)
    local natural = math.ceil(Skin.TextWidth(f.title)) + 2
    if tw < math.min(natural, 160) then below, tw = true, sw - left - 12 - 24 - SP.s end
  end
  f.title:SetWidth(tw); f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -12)
  local th = Skin.TextHeight(f.title, tw)
  local y
  if below then
    f.profile:ClearAllPoints(); f.profile:SetPoint("TOPLEFT", f, "TOPLEFT", left, -(12 + math.max(th, 24) + SP.s))
    y = 12 + math.max(th, 24) + SP.s + f.profile:GetHeight() + SP.m
  else
    y = 12 + math.max(th, bw > 0 and f.profile:GetHeight() or 0, 24) + SP.m
  end
  f.rowsTop = y
  f.rowsX = 16
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", f.rowsX, -f.rowsTop)
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 62)
  f.scroll:SetSize(self.rowsW + 12, (f:GetHeight() or 0) - f.rowsTop - 62)
  f.scroll.content:SetWidth(self.rowsW)
  f.rule:ClearAllPoints(); f.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 54); f.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 54)
end

function Gear:OpenProfiles()
  Panoply.Menu:Select("profiles")
end

-- sectionKey / rowKey: where a search result or a link points. A row of the front needs no section; any other row opens its
-- section. Every section starts closed.
function Gear:Open(page, sectionKey, rowKey, advanced)
  local Menu = Panoply.Menu
  if Menu:HostLocked() then
    -- the page showing carries secure buttons and it is a fight: the settings open in its place when it ends
    Panoply.Kit.Defer("menu/gear", function() Gear:Open(page, sectionKey, rowKey, advanced) end)
    Panoply:Print("The settings open when combat ends.")
    return
  end
  local H = history()
  if H then H:Begin() end
  local f = self:Create()
  if Menu.editing then Menu:EndEdit() end
  Menu:CloseResults()
  self.page = page
  self.open = true
  self.asking = false
  self:Layout(page)
  self:ApplyMode()
  f:Show()
  if Menu.header and Menu.header.gear then Menu.header.gear:SetSelected(true) end
  -- the page's front and sections, built for this width
  for _, fr in pairs(self.frames) do if fr.body then fr.body:Hide() end end
  for _, h in pairs(self.holders) do h:Hide() end
  self.cur = nil
  local fr = self:Frame(page)
  self.P = fr
  fr.body:Show()
  if fr.hasFront then fr.front:Show() else fr.front:Hide() end
  fr.open, fr.order, fr.moreOpen = {}, {}, false
  self.snapshot = Cat:Snapshot(page)
  local inFront = rowKey and self:FindFront(rowKey)
  if (sectionKey or rowKey) and not inFront and #fr.moreSecs > 0 then
    local sec = fr.moreSecs[1]
    for _, s in ipairs(fr.moreSecs) do if s.key == sectionKey then sec = s end end
    self:Select(sec.key, rowKey, advanced)
  else
    self:RefreshRows()
    self:LayoutContent()
    self.sheet.scroll:UpdateBar()
    if self.sheet.scroll.SetVerticalScroll then self.sheet.scroll:SetVerticalScroll(0) end
    self:LayoutFooter()
    if inFront then self:JumpRow(rowKey) end
  end
  -- the page beside a drawer is laid out again for the room that is left
  if self.drawer then Menu:RefreshCurrent() end
  if H then H:End("gear") end
end

function Gear:Close(silent)
  if not self.open then return end
  local H = history()
  if H then H:Begin() end
  self.open = false
  self:ClearPreview()
  self.sheet:Hide()
  local Menu = Panoply.Menu
  if Menu.header and Menu.header.gear then Menu.header.gear:SetSelected(false) end
  Menu:SetDrawer(nil)
  if not (Menu.results and Menu.results:IsShown()) and not Menu.editing then
    if not Menu:ShowHost(true) then
      Panoply.Kit.Defer("menu/host", function() Menu:ShowHost(true) end)
      Panoply:Print("The page comes back when combat ends.")
    end
  end
  if not silent then Menu:RefreshCurrent() end
  if H then H:End("gear") end
end

-- The window was resized (or the page's band changed) while the panel is open: it takes its new place and width, with the same
-- sections open and the same place in the list.
function Gear:Relayout()
  if not (self.open and self.page and self.sheet) then return end
  local was = self.P
  local sc = self.sheet.scroll
  local keep = sc.GetVerticalScroll and sc:GetVerticalScroll() or 0
  self:Layout(self.page)
  self:ApplyMode()
  for _, fr in pairs(self.frames) do if fr.body then fr.body:Hide() end end
  local fr = self:Frame(self.page)
  self.P = fr
  if was and fr ~= was then
    for k, v in pairs(was.open) do fr.open[k] = v end
    for i, k in ipairs(was.order) do fr.order[i] = k end
  end
  fr.body:Show()
  if fr.hasFront then fr.front:Show() else fr.front:Hide() end
  self.cur = lastOpen(self, fr)
  self:RefreshRows()
  self:LayoutContent()
  if sc.SetVerticalScroll then sc:SetVerticalScroll(math.min(keep, sc:MaxScroll())) end
  sc:UpdateBar()
  self:LayoutFooter()
end

-- Show one section (it opens if it was closed; the others stay as they are), at the row a search or a link named
function Gear:Select(secKey, rowKey, advanced)
  local f = self.sheet
  local fr = self.P
  if not fr then return end
  local sec
  for _, s in ipairs(fr.moreSecs) do if s.key == secKey then sec = s end end
  sec = sec or fr.moreSecs[1]
  if not sec then
    self.cur = nil
    self:LayoutContent()
    self:LayoutFooter()
    return
  end
  forget(fr.order, sec.key)
  fr.open[sec.key] = true
  fr.order[#fr.order + 1] = sec.key
  local h = self:Holder(self.page, sec)
  self.cur = h
  if rowKey and advanced and h.advBtn and not h.advOpen then
    h.advOpen = true
    if h.advHolder then h.advHolder:Show() end
    h:SetHeight(measure(h))
  end
  self:RefreshRows()
  self:LayoutContent()
  -- the section's header at the top of the view (a row a search named is scrolled to by JumpRow)
  local s = fr.secBy[sec.key]
  if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(math.max(0, math.min(f.scroll:MaxScroll(), (s and s.y or 0) - SP.xs))) end
  f.scroll:UpdateBar()
  self:LayoutFooter()
  if rowKey then self:JumpRow(rowKey) end
  local H = history()
  if H then H:Touch() end
end

-- the row a search result named: scrolled into view and outlined for a moment
function Gear:FindFront(key)
  local fr = self.P
  if not fr then return nil end
  for _, list in ipairs({ fr.exactMade or {}, fr.commonMade or {} }) do
    for _, w in ipairs(list) do if w.panoplyKey == key then return w end end
  end
  if fr.panel then return fr.panel:Widget(key) end
end

function Gear:FindRow(h, key)
  for _, w in ipairs(h.made or {}) do if w.panoplyKey == key then return w, 0 end end
  for _, w in ipairs(h.advMade or {}) do if w.panoplyKey == key then return w, h.advOffsetY or 0 end end
end

-- the sections that are open, the one opened last first
function Gear:OpenHolders()
  local fr = self.P
  local out = {}
  if not fr then return out end
  if self.cur then out[1] = self.cur end
  for _, s in ipairs(fr.secs) do
    if fr.open[s.sec.key] and s.holder and s.holder ~= self.cur then out[#out + 1] = s.holder end
  end
  return out
end

-- the keys of the sections that are open, in the order of the list (what History keeps of the panel)
function Gear:OpenSections()
  local fr = self.P
  local out = {}
  if not (fr and self.open) then return out end
  for _, s in ipairs(fr.secs) do if fr.open[s.sec.key] then out[#out + 1] = s.sec.key end end
  return out
end

-- the widget of a setting wherever it is in the open gear: the front, or a section that is open
function Gear:Widget(key)
  local w = self:FindFront(key)
  if w then return w end
  for _, h in ipairs(self:OpenHolders()) do
    w = self:FindRow(h, key)
    if w then return w, h end
  end
  return nil
end

function Gear:JumpRow(key)
  local sc = self.sheet.scroll
  local fr = self.P
  if fr and fr.panel then fr.panel:Reveal(key) end      -- the panel shows the thing the setting belongs to
  local w, base = self:FindFront(key), 0
  if not w then
    local h, off
    for _, oh in ipairs(self:OpenHolders()) do
      w, off = self:FindRow(oh, key)
      if w then h = oh break end
    end
    if not w then return end
    if off ~= 0 and not h.advOpen then self:ToggleAdvanced(h, true) end
    base = (h.panoplyY or fr.frontH) + off
  end
  local want = math.max(0, math.min(sc:MaxScroll(), (w.panoplyRowY or 0) + base - 30))
  if sc.SetVerticalScroll then sc:SetVerticalScroll(want) end
  sc:UpdateBar()
  self:Flash(w)
end

function Gear:Flash(w)
  local f = self.flash
  if not f then
    f = CreateFrame("Frame", nil, self.sheet)
    Skin.Border(f, true)
    f.panoplyLayoutSkip = true
    f:EnableMouse(false)
    self.flash = f
  end
  f:SetParent(w:GetParent())
  f:ClearAllPoints()
  local extra = (w.panoplyRow and (w.panoplyRow.type == "slider" or w.panoplyRow.type == "segmented" or w.panoplyRow.type == "choice")) and 24 or 4
  f:SetPoint("TOPLEFT", w, "TOPLEFT", -6, extra)
  local right = w.label and w.label.GetObjectType and w.label or w
  f:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 6, -4)
  f:Show()
  self.flashStamp = (self.flashStamp or 0) + 1
  local stamp = self.flashStamp
  Panoply.Compat.After(2.5, function() if Gear.flashStamp == stamp and Gear.flash then Gear.flash:Hide() end end)
end

-------------------------------------------------------------------------------
-- Live preview: the menu window fades while the mouse is on a setting that changes the screen behind it
-------------------------------------------------------------------------------
-- The window was hidden (or the gear closed) while a knob was held or the window was fading: nothing may stay held, and the menu
-- window is whole again at once (a fade still running is cancelled, or it would finish on the next frame and leave it faint).
function Gear:ClearPreview()
  for w in pairs(self.held) do w.panoplyHeld = nil end
  self.held = {}
  self.previewing = false
  local Menu = Panoply.Menu
  local f = Menu.frame
  Menu.preview = false
  if f then
    if Skin.tweens then Skin.tweens[f] = nil end
    f:SetAlpha(1)
  end
end

function Gear:Preview(on)
  local Menu = Panoply.Menu
  on = on and true or false
  if self.previewing == on then return end
  self.previewing = on
  if Menu.Preview then Menu:Preview(on) end
end

-------------------------------------------------------------------------------
-- Refresh, footer, reset, undo
-------------------------------------------------------------------------------
function Gear:RefreshRows()
  if not self.open then return end
  local fr = self.P
  if fr then
    for _, list in ipairs({ fr.exactMade or {}, fr.commonMade or {} }) do
      for _, w in ipairs(list) do if w.Refresh then w:Refresh() end end
    end
    if fr.panel then fr.panel:Refresh() end
  end
  local any = false
  for _, h in ipairs(self:OpenHolders()) do
    any = true
    if h.layoutHead then h.layoutHead() end
    for _, list in ipairs({ h.made or {}, h.advMade or {} }) do
      for _, w in ipairs(list) do if w.Refresh then w:Refresh() end end
    end
    h:SetHeight(measure(h))
  end
  -- the headers say On / Off and how many settings: they follow a switch at once
  if fr and (any or #fr.secs > 0) and self.sheet:IsShown() and fr.body:IsShown() then self:LayoutContent() end
  self:LayoutFooter()
end

function Gear:AskReset(on)
  if on == nil then on = true end
  self.asking = on
  self:LayoutFooter()
end

function Gear:DoReset()
  local n = Cat:ResetPage(self.page)
  self.asking = false
  Panoply:Print(("%s settings are back to the standard (%d settings)."):format(self.page.label, n))
  self:RefreshRows()
end

-- Undo my changes: every setting of this page goes back to what it was when the gear was opened (the sizes included)
function Gear:Undo()
  if not self.snapshot then return 0 end
  local n = Cat:Restore(self.snapshot)
  Panoply:Print(("%s settings are back as they were when you opened them (%d settings)."):format(self.page.label, n))
  self:RefreshRows()
  return n
end

function Gear:Changed()
  return self.snapshot ~= nil and Cat:SnapshotChanged(self.snapshot)
end

function Gear:LayoutFooter()
  local f = self.sheet
  if not (f and self.page) then return end
  local sw = f:GetWidth()
  local n = #Cat:PageKeys(self.page)
  f.reset:Hide(); f.done:Hide(); f.ask:Hide(); f.yes:Hide(); f.no:Hide(); f.undo:Hide()
  local base = 12
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", f.rowsX or 16, -(f.rowsTop or 60))
  if self.asking and n > 0 then
    local w = sw - 28
    f.ask:SetText(("Put %d setting%s of %s back to Panoply Suite's standard? Nothing on other pages changes, and the on / off switches stay."):format(n, n == 1 and "" or "s", self.page.label))
    f.ask:SetWidth(w); f.ask:ClearAllPoints(); f.ask:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, base + 28 + SP.xs)
    f.ask:Show()
    f.yes:ClearAllPoints(); f.yes:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, base)
    f.no:ClearAllPoints(); f.no:SetPoint("LEFT", f.yes, "RIGHT", SP.s, 0)
    f.yes:Show(); f.no:Show()
    local bottom = 62 + Skin.TextHeight(f.ask, w) + SP.xs
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, bottom)
    f.scroll:SetSize(self.rowsW + 12, f:GetHeight() - (f.rowsTop or 60) - bottom)
  else
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 62)
    f.scroll:SetSize(self.rowsW + 12, f:GetHeight() - (f.rowsTop or 60) - 62)
    f.done:ClearAllPoints(); f.done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, base); f.done:Show()
    local x, room = 14, sw - 14 - 90 - 14 - SP.m
    if n > 0 then
      f.reset.label:SetText("Reset this page")
      local rw = Skin.FitButton(f.reset, 130, room)
      f.reset:ClearAllPoints(); f.reset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, base); f.reset:Show()
      x = x + rw + SP.s
      room = room - rw - SP.s
    end
    if self:Changed() then
      local uw = Skin.FitButton(f.undo, 130, math.max(100, room))
      f.undo:ClearAllPoints(); f.undo:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, base); f.undo:Show()
    end
  end
  f.scroll:UpdateBar()
end
