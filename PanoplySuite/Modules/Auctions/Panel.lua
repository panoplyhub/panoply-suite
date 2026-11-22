-- Auctions: the Auction window (0.7.3; called the Trade window until 0.9.5, when "Trade" became "Auction window" everywhere: in WoW
-- "Trade" is the player-to-player trade window). ONE window for the auction house features that are
-- not scanning and not in the three Panoply Suite tabs of the game's window (Host.lua; 0.7.4): Shopping (lists and
-- searches), Cancelling and History. It opens from the
-- "Auction window" button next to Scan on the auction house window (Auctions.lua) and the Auctions page, and closes with the auction house. It never
-- touches the game's own auction house frames. Each tab lives in its own file and registers itself with
-- Panel:AddTab(key, label, build, refresh). Look: skin v3 (Skin.Window, Skin.Tab, Skin.Button).
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local Panel = { tabs = {}, order = {} }
Auc.Panel = Panel
Panel.W, Panel.H = 640, 470

function Panel:AddTab(key, label, tip, build, refresh)
  self.tabs[key] = { key = key, label = label, tip = tip, build = build, refresh = refresh }
  self.order[#self.order + 1] = key
end

-- A message under the tabs (status of the last click, server busy ...).
function Panel:Say(text, bad)
  local f = self.frame
  if not f then return end
  f.status:SetText(text or "")
  local c = bad and Skin.colors.warn or Skin.colors.inkSoft
  if c then f.status:SetTextColor(c[1], c[2], c[3], 1) end
end

-- A scrolling list with a pool of rows. makeRow(parent) builds one row once; fill(row, item, i) shows an item.
function Panel.List(parent, w, h, rowH, makeRow)
  local L = { rows = {}, rowH = rowH, w = w }
  local sf = Skin.ScrollArea(parent)
  sf:SetSize(w, h)
  L.sf = sf
  function L:Set(items, fill)
    for i, it in ipairs(items) do
      local r = self.rows[i]
      if not r then r = makeRow(sf.content) self.rows[i] = r end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", sf.content, "TOPLEFT", 0, -(i - 1) * rowH)
      r:SetSize(w - 12, rowH)
      r.item = it
      fill(r, it, i)
      r:Show()
    end
    for i = #items + 1, #self.rows do self.rows[i]:Hide() end
    sf:SetContentHeight(#items * rowH)
    self.count = #items
  end
  return L
end
-- one text cell in a row: fixed width, one line, cut with "..." when longer
function Panel.Cell(row, x, w, justify, size)
  local fs = Skin.Text(row, size or 12)
  fs:SetPoint("LEFT", row, "LEFT", x, 0)
  fs:SetWidth(w)
  if fs.SetJustifyH then fs:SetJustifyH(justify or "LEFT") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs.cellW = w
  return fs
end
function Panel.Put(fs, text) Skin.Ellipsize(fs, text or "", fs.cellW) end
-- a row that highlights under the mouse
function Panel.Row(parent)
  local r = CreateFrame("Button", nil, parent)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(r)
  Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
  r.hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight); r.hl:Hide()
  r:SetScript("OnEnter", function(self) self.hl:Show() end)
  r:SetScript("OnLeave", function(self) if not self.selected then self.hl:Hide() end end)
  function r:SetSelected(on) self.selected = on if on then self.hl:Show() else self.hl:Hide() end end
  return r
end
-- An input box whose placeholder hides while there is text (also after SetText from code). onChange(box, byUser).
function Panel.Box(parent, w, h, placeholder, onChange)
  local box = Skin.Input(parent, w, h, placeholder)
  box:SetScript("OnTextChanged", function(self, user)
    if self.placeholder then if (self:GetText() or "") == "" then self.placeholder:Show() else self.placeholder:Hide() end end
    if onChange then onChange(self, user) end
  end)
  return box
end
function Panel.SetBox(box, text)
  box:SetText(text or "")
  if box.placeholder then if (text or "") == "" then box.placeholder:Show() else box.placeholder:Hide() end end
end
function Panel.Note(parent, w, size)
  local fs = Skin.Text(parent, size or 11, Skin.colors.inkSoft)
  fs:SetWidth(w)
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  return fs
end

function Panel:Build()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteAuctionPanel", Panel.W, Panel.H, "Auction window", "Shopping lists, cancelling and price history", "HIGH", "Collect")   -- 4J: its own header icon
  self.frame = f
  local top = (f.panoplyHeaderBottom or 50) + 8
  local x = 14
  f.tabButtons = {}
  for _, key in ipairs(self.order) do
    local t = self.tabs[key]
    local b = Panoply.Kit.TextTab(f, t.label, 120, function() Panel:Select(key) end, t.label, t.tip)   -- 4J: underlined tabs
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -top)
    x = x + 126
    f.tabButtons[key] = b
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(top + 38))
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 40)
    body:Hide()
    t.body = body
    if t.build then t.build(body, Panel) end
  end
  f.status = Skin.Text(f, 11, Panoply.Kit.Color("text.muted"))
  f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
  f.status:SetWidth(Panel.W - 36 - 12)          -- 12: clear of the resize grip
  if f.status.SetJustifyH then f.status:SetJustifyH("LEFT") end
  if f.status.SetWordWrap then f.status:SetWordWrap(false) end
  f:HookScript("OnShow", function() Panel:Refresh() end)   -- a hook: the open animation and Window size's fit check on open stay
  -- Nov 2026: the window resizes in both directions and remembers its size; each tab's body is tied to both corners and is
  -- drawn again for the new room
  Skin.Resizable(f, { key = "auctionPanel", minW = Panel.W, minH = Panel.H, onSize = function(w)
    f.status:SetWidth(w - 36 - 12)
    if f:IsShown() then Panel:Refresh() end
  end })
  return f
end

function Panel:Select(key)
  if not self.frame or not self.tabs[key] then return end
  self.current = key
  for k, t in pairs(self.tabs) do
    local on = k == key
    self.frame.tabButtons[k]:SetActive(on)
    if t.body then if on then t.body:Show() else t.body:Hide() end end
  end
  self:Say("")
  self:Refresh()
end
function Panel:Refresh()
  local t = self.current and self.tabs[self.current]
  if t and t.refresh and self.frame and self.frame:IsShown() then t.refresh(t.body, Panel) end
end

function Panel:Show()
  local f = self:Build()
  f:Show()
  self:Select(self.current or self.order[1])
end
function Panel:Hide() if self.frame then self.frame:Hide() end end
function Panel:Toggle() if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end end

-- The data under a tab changed (a search came back, the owned list arrived ...)
for _, ev in ipairs({ "AUCTION_TRADE_SEARCH", "AUCTION_TRADE_OWNED", "AUCTION_TRADE_STATE", "AUCTION_TRADE_POSTED", "AUCTION_SCAN_DONE" }) do
  Panoply:Listen(ev, function() Panel:Refresh() end)
end
Panoply:On("AUCTION_HOUSE_CLOSED", function() Panel:Hide() end)
