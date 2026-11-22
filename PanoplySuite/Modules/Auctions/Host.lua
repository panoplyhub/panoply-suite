-- Auctions: the tab host (0.7.4, docs/auctions/AUCTIONS-REDESIGN-SPEC.md section 2). Adds three tabs to the game's
-- auction window: Panoply Suite Sell, Panoply Suite Buy and Panoply Suite Vendor. A panel registers itself with
-- Host:AddPanel(key, label, tip, build, refresh); Sell.lua, Buy.lua and Vendor.lua are the three.
--   Classic Era (AuctionFrame): our tabs follow the game's own (Browse, Bids, Auctions), which are not touched or
--     reordered. Clicking ours hides the game's panels (Hide on plain frames, nothing protected) and shows our panel in
--     the same inside area; clicking one of the game's tabs hides ours. Nothing is sent to the auction house by a tab.
--   Too small, or no tab strip to follow (Forever's AuctionHouseFrame, whose own tab system is not known well enough
--     to add to): the same three tabs open ONE Panoply Suite window beside the game's, with the same panels in it. The three
--     buttons sit in the game's own bottom tab row, flush after its right-most tab (modernTab finds it and touches nothing);
--     when no such tab is found they form one strip touching the window's bottom edge, 14 px in from the left.
-- UNVERIFIED in a real client: the Era window's inside size (the design assumes about 800 x 350 inside a window of
-- about 832 x 447; the numbers are from memory, not measured), that AuctionFrameTab<n> / AuctionFrameBrowse /
-- AuctionFrameBid / AuctionFrameAuctions are the names the 1.15.x window uses, and everything about
-- AuctionHouseFrame (the fallback does not touch its tabs).
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local Auc = Panoply.Auctions
local Host = { panels = {}, order = {}, tabs = {} }
Auc.Host = Host
Host.MIN_W, Host.MIN_H = 760, 330      -- the smallest inside area the panels are drawn for
Host.MAX_W, Host.MAX_H = 800, 350
Host.INSET = { l = 16, t = 70, r = 16, b = 38 }   -- inside the Era window: left, top, right, bottom (UNVERIFIED)
Host.GAME_PANELS = { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions" }

-------------------------------------------------------------------------------
-- Small drawing helpers shared by the three panels
-------------------------------------------------------------------------------
local function colorOf(c) if type(c) == "string" then return Skin.colors[c] or Skin.colors.text end return c or Skin.colors.text end
-- One line of text at (x, y) under parent's TOPLEFT, `w` wide, cut with "..." when longer (Panel.Put). colour: a Skin.colors name.
function Host.Text(parent, x, y, w, size, color, role, justify)
  local fs = Skin.Text(parent, size, colorOf(color), nil, role)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  if fs.SetJustifyH then fs:SetJustifyH(justify or "LEFT") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs.cellW = w
  return fs
end
-- A text whose size steps down (to 9) until it fits maxW: money must never be cut short with "...".
function Host.Fit(fs, text, maxW, size, color, role)
  fs:SetText(text or "")
  local c = colorOf(color)
  for px = size, 9, -1 do
    Skin.Font(fs, px, c, nil, role)
    if not maxW or Skin.TextWidth(fs) <= maxW then break end
  end
end
-- A wrapped text whose size steps down (to 9) until it fits maxH (the height of its box).
function Host.FitPara(fs, text, maxH, size, color, role)
  fs:SetText(text or "")
  local c = colorOf(color)
  for px = size, 9, -1 do
    Skin.Font(fs, px, c, nil, role)
    if (fs:GetStringHeight() or 0) <= maxH then break end
  end
end
-- A heading (the item's name): one line; the size steps down to 11, and only then is it cut with "...".
function Host.FitName(fs, text, maxW, size)
  fs:SetText(text or "")
  for px = size, 11, -1 do
    Skin.Font(fs, px, Skin.colors.heading, nil, "head")
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1.5) end
    if not maxW or Skin.TextWidth(fs) <= maxW then return end
  end
  Skin.Ellipsize(fs, text or "", maxW)
end
-- The item's own game icon in a small rounded slot; the border carries the quality (uncommon and better). Never a stand-in
-- picture (SPEC 19.10): an unknown item shows the game's question mark.
function Host.ItemSlot(parent, size)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(size, size)
  s.bg, s.rim = Skin.Box(s, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetPoint("TOPLEFT", s, "TOPLEFT", 4, -4); s.icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -4, 4)
  -- item (0.9.7 hotfix): the item's id or link. With it the picture comes from the shared helper (Core/CompatModules.lua Icons):
  -- the game's own "?" is not taken as a picture, and the slot is painted again when the game sends the item.
  function s:Set(icon, quality, item)
    if item then Panoply.Icons:Apply(self.icon, item, icon)
    else Panoply.Icons:Release(self.icon) self.icon:SetTexture(icon or 134400) end
    local c = (quality and quality >= 2) and C.QualityColor(quality) or Skin.colors.slotLine
    self.rim:SetVertexColor(c[1], c[2], c[3], 1)
  end
  return s
end

function Host:AddPanel(key, label, tip, build, refresh)
  self.panels[key] = { key = key, label = label, tip = tip, build = build, refresh = refresh }
  self.order[#self.order + 1] = key
end

-- A message from the panel on screen (what the last click did, why it did nothing).
function Host:Say(text, bad)
  local p = self.current and self.panels[self.current]
  if p and p.say then p.say(text or "", bad) end
end

local function gameTabs()
  local out = {}
  for i = 1, 20 do
    local t = _G["AuctionFrameTab" .. i]
    if not t then break end
    out[#out + 1] = t
  end
  return out
end

-- Forever's AuctionHouseFrame: the game's own bottom tabs, found without touching them, so ours can sit in the same row. Looked
-- for in two places, neither verified in a real client: the frame's own Tabs list, and the tab names the modern window is believed
-- to use. Only a shown tab counts. Returns the right-most one, or nil.
Host.MODERN_TAB_NAMES = { "AuctionHouseFrameBuyTab", "AuctionHouseFrameSellTab", "AuctionHouseFrameAuctionsTab",
  "AuctionHouseFrameTab1", "AuctionHouseFrameTab2", "AuctionHouseFrameTab3", "AuctionHouseFrameTab4" }
local function modernTab(ah)
  local found = {}
  local function add(t)
    if type(t) == "table" and t.GetRight and t.IsShown and C.pc(t.IsShown, t) then found[#found + 1] = t end
  end
  if type(ah.Tabs) == "table" then for _, t in ipairs(ah.Tabs) do add(t) end end
  for _, n in ipairs(Host.MODERN_TAB_NAMES) do add(_G[n]) end
  local best, right
  for _, t in ipairs(found) do
    local r = C.pc(t.GetRight, t)
    if not best or (r and (not right or r > right)) then best, right = t, r end
  end
  return best
end

-- Decide once how the panels are shown: "embedded" in the game's own window, or in "window" mode.
function Host:Setup()
  if self.ready then return self.ready end
  local ah = Auc.Frame()
  if not ah then return nil end
  self.ah = ah
  local era = _G.AuctionFrame ~= nil and ah == _G.AuctionFrame
  local gt = era and gameTabs() or {}
  local w, h = ah:GetWidth() or 0, ah:GetHeight() or 0
  local I = Host.INSET
  self.gameTabs = gt
  self.followTab = (not era) and modernTab(ah) or nil      -- Forever: the game's right-most bottom tab, to sit beside (never touched)
  if era and #gt > 0 and w >= Host.MIN_W + I.l + I.r and h >= Host.MIN_H + I.t + I.b then
    self.mode = "embedded"
    self.W = math.min(Host.MAX_W, w - I.l - I.r)
    self.H = math.min(Host.MAX_H, h - I.t - I.b)
  else
    self.mode = "window"
    self.W, self.H = Host.MAX_W, Host.MAX_H
    self.why = era and (#gt == 0 and "the game's tab strip was not found" or "the auction window is too small for the tabs")
      or "this client's auction house keeps its own tabs"
  end
  self:BuildTabs(gt)
  self.ready = self.mode
  return self.ready
end

-- Our three tab buttons, hung where the game's own tabs are (after the last one), drawn in skin v3.
function Host:BuildTabs(gt)
  local ah = self.ah
  local last = gt[#gt]
  for i, key in ipairs(self.order) do
    local p = self.panels[key]
    local b = Skin.Tab(ah, p.label, 140, function() Host:Select(key) end, p.label, p.tip)
    -- a small hearthstone dot before the words (a flat brass dot: no glow)
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetSize(6, 6)
    Skin.Round(dot, 3, Skin.TEX.RFill)
    dot:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], 1)
    dot:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 7, 0)
    b:SetWidth(math.max(124, b:NeedWidth() + 18))
    if i == 1 then
      if last then b:SetPoint("TOPLEFT", last, "TOPRIGHT", 10, 0)
      elseif self.followTab then b:SetPoint("TOPLEFT", self.followTab, "TOPRIGHT", 4, 0)    -- Forever: the game's own tab row, flush after its last tab
      else b:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 14, 0) end                              -- no tab row known: one strip, touching the window's bottom edge
    else
      b:SetPoint("LEFT", self.tabs[self.order[i - 1]], "RIGHT", 4, 0)
    end
    self.tabs[key] = b
  end
  -- the game's own tab being clicked puts ours away
  for _, t in ipairs(gt) do
    if t.HookScript then t:HookScript("OnClick", function() Host:Deselect() end) end
  end
  if _G.hooksecurefunc and _G.AuctionFrameTab_OnClick and not self.hooked then
    self.hooked = true
    pcall(_G.hooksecurefunc, "AuctionFrameTab_OnClick", function() Host:Deselect() end)
  end
end

-- The shell the panels live in: the inside area of the game's window, or our own window.
function Host:BuildShell()
  if self.shell then return self.shell end
  local W, H = self.W, self.H
  local shell
  if self.mode == "embedded" then
    local I = Host.INSET
    shell = CreateFrame("Frame", "PanoplySuiteAuctionArea", self.ah)
    shell:SetSize(W, H)
    shell:SetPoint("TOPLEFT", self.ah, "TOPLEFT", I.l, -I.t)
    if shell.SetFrameLevel and self.ah.GetFrameLevel then shell:SetFrameLevel((C.pc(self.ah.GetFrameLevel, self.ah) or 1) + 20) end
    shell:EnableMouse(true)           -- the game's panels under it never see these clicks
    local fill, line = Skin.Box(shell, "L", { fill = Skin.colors.panel, fillA = 1, line = Skin.colors.trim })
    shell.panoplyBg = fill
    self.body = shell
    shell:Hide()
  else
    local sub = self.why and ("Opened here because " .. self.why .. ".") or "Sell, buy and find vendor deals"
    shell = Skin.Window("PanoplySuiteAuctionHost", W + 28, H + 112, "Panoply Suite auctions", sub, "HIGH", "Vendor")   -- 4J: its own header icon
    Panoply.Windows:Leave(shell)       -- it sits beside the game's auction window: Window size leaves it at its own size
    Panoply.Windows:OwnPlace(shell)    -- 0.9.5: and it is not moved beside the main window either
    local top = (shell.panoplyHeaderBottom or 50) + 8
    local x = 14
    shell.tabButtons = {}
    for _, key in ipairs(self.order) do
      local p = self.panels[key]
      local b = Panoply.Kit.TextTab(shell, p.label, 132, function() Host:Select(key) end, p.label, p.tip)   -- 4J: underlined tabs
      b:SetWidth(math.max(120, b:NeedWidth() + 14))
      b:SetPoint("TOPLEFT", shell, "TOPLEFT", x, -top)
      x = x + b:GetWidth() + 6
      shell.tabButtons[key] = b
    end
    local body = CreateFrame("Frame", nil, shell)
    body:SetSize(W, H)
    body:SetPoint("TOPLEFT", shell, "TOPLEFT", 14, -(top + 38))
    self.body = body
    -- beside the game's window when there is room, else the middle of the screen (Skin.Window starts there)
    local ah, ui = self.ah, _G.UIParent
    if ah and ah.GetRight and ui and ui.GetWidth then
      local right = ah:GetRight()
      if right and right + 8 + W + 28 <= ui:GetWidth() then
        shell:ClearAllPoints()
        shell:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, 0)
      end
    end
  end
  self.shell = shell
  for _, key in ipairs(self.order) do
    local p = self.panels[key]
    local body = CreateFrame("Frame", nil, self.body)
    body:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, 0)
    body:SetSize(W, H)
    body:Hide()
    p.body = body
    if p.build then p.build(body, W, H, Host) end
  end
  return shell
end

-- Show one of our panels. Sends nothing to the auction house.
function Host:Select(key)
  if not self:Setup() or not self.panels[key] then return end
  local shell = self:BuildShell()
  self.current = key
  if self.mode == "embedded" then
    for _, n in ipairs(Host.GAME_PANELS) do
      local f = _G[n]
      if f and f.Hide then pcall(f.Hide, f) end
    end
    for _, t in ipairs(self.gameTabs) do
      if _G.PanelTemplates_DeselectTab then pcall(_G.PanelTemplates_DeselectTab, t) end
    end
  end
  shell:Show()
  for k, p in pairs(self.panels) do
    if p.body then if k == key then p.body:Show() else p.body:Hide() end end
    if self.tabs[k] then self.tabs[k]:SetActive(k == key) end
    if shell.tabButtons and shell.tabButtons[k] then shell.tabButtons[k]:SetActive(k == key) end
  end
  self:Say("")
  self:Refresh()
end

-- The module was switched off (Settings > Modules): no tabs, no panels. Switching it on shows the tabs again.
function Host:SetEnabled(on)
  for _, b in pairs(self.tabs) do if on then b:Show() else b:Hide() end end
  if not on and self.shell then self.shell:Hide() self.current = nil end
end

-- Put our panels away (the game's tab was clicked, or the auction house closed).
function Host:Deselect()
  if not self.shell then return end
  if self.mode == "embedded" then
    self.shell:Hide()
    self.current = nil
    for _, b in pairs(self.tabs) do b:SetActive(false) end
  end
end

function Host:Refresh()
  local p = self.current and self.panels[self.current]
  if p and p.refresh and self.shell and self.shell:IsShown() then p.refresh(p.body, Host) end
end

-- The data under a panel changed (an answer came back, a post went out, a scan finished ...).
for _, ev in ipairs({ "AUCTION_TRADE_SEARCH", "AUCTION_TRADE_STATE", "AUCTION_TRADE_POSTED", "AUCTION_TRADE_BUY", "AUCTION_SCAN_DONE" }) do
  Panoply:Listen(ev, function() Host:Refresh() end)
end
Panoply:On("AUCTION_HOUSE_CLOSED", function()
  Host:Deselect()
  if Host.shell and Host.mode == "window" then Host.shell:Hide() end
  Host.current = nil
end)
Panoply:On("AUCTION_HOUSE_SHOW", function() if Host.mode == "embedded" then Host:Deselect() end end)
