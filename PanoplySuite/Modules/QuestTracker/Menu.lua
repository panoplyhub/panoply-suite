-- Quest tracker (SPEC 23.2): the small v3 right-click menu (quest actions, tracker options).
local ADDON, Panoply = ...
local C, QT = Panoply.Compat, Panoply.QuestTracker
local M = { rows = {} }
QT.Menu = M
M.WIDTH = 210

function M:Build()
  if self.frame then return self.frame end
  -- Nov 2026: a click elsewhere, Esc and the tracker closing all close it through the shared pop-up manager (Skin.Popups);
  -- the old full-screen click catcher (it swallowed the click it closed on) is gone.
  local f = CreateFrame("Frame", "PanoplySuiteTrackerMenu", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetWidth(self.WIDTH)
  f.panoplyBox = true
  f:EnableMouse(true)
  QT.Box(f, "S", QT.Color("panel"), 0.98, QT.Color("trim"), 1)
  local title = QT.NewText(f, "head", 13, QT.Color("heading"))
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
  title:SetWidth(self.WIDTH - 24)
  self.title = title
  f:Hide()
  Panoply.Skin.Popups:Adopt(f)
  self.frame = f
  return f
end

function M:Row(i)
  local r = self.rows[i]
  if r then return r end
  local f = self.frame
  r = CreateFrame("Button", nil, f)
  r:RegisterForClicks("LeftButtonUp")
  local hl = r:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(r); hl:SetTexture("Interface\\Buttons\\WHITE8X8")
  local a = QT.Color("accent")
  hl:SetVertexColor(a[1], a[2], a[3], 0.14)
  hl:Hide()
  r.hl = hl
  r.check = r:CreateTexture(nil, "ARTWORK")
  r.check:SetSize(8, 8)
  r.check:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -8)
  r.check:SetTexture("Interface\\Buttons\\WHITE8X8")
  r.check:SetVertexColor(a[1], a[2], a[3], 1)
  r.text = QT.NewText(r, "body", 12, QT.Color("text"))
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 20, -4)
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    local GT = _G.GameTooltip
    if GT and self.item and self.item.tip then
      GT:SetOwner(self, "ANCHOR_RIGHT"); GT:SetText(self.item.label, 0.91, 0.81, 0.58, 1, true)
      GT:AddLine(self.item.tip, 0.9, 0.9, 0.87, true); GT:Show()
    end
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnClick", function(self)
    local it = self.item
    M:Close()
    if it and it.func then it.func() end
  end)
  self.rows[i] = r
  return r
end

function M:Open(owner, title, items)
  local f = self:Build()
  local S = Panoply.Skin
  self.title:SetText(title or "")
  local y = 8
  local th = math.ceil(S.TextHeight(self.title, self.WIDTH - 24))
  self.title:SetHeight(th)
  y = y + th + 4
  local inner = self.WIDTH - 12
  for i, it in ipairs(items) do
    local r = self:Row(i)
    r.item = it
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -y)
    r:SetWidth(inner)
    r.text:SetWidth(inner - 26)
    r.text:SetText(it.label)
    local c = it.warn and QT.Color("warn") or QT.Color("text")
    r.text:SetTextColor(c[1], c[2], c[3], 1)
    local h = math.ceil(S.TextHeight(r.text, inner - 26))
    r.text:SetHeight(h)
    r:SetHeight(h + 8)
    r.panoplyTip = it.label
    if it.checked then r.check:Show() else r.check:Hide() end
    r:Show()
    y = y + h + 8
  end
  for i = #items + 1, #self.rows do self.rows[i]:Hide() self.rows[i].item = nil end
  f:SetHeight(y + 8)
  f:ClearAllPoints()
  local left = owner and owner.GetLeft and owner:GetLeft()
  if left and left < self.WIDTH + 10 then f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
  elseif owner then f:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
  else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
  if f:IsShown() then f:Hide() end      -- open for another row: closed there first
  f.panoplyOwner = owner
  f:Show()
  self.items = items
  return f
end

function M:Close()
  if self.frame then self.frame:Hide() end
end
function M:IsOpen() return self.frame and self.frame:IsShown() or false end
-- Click the menu row with this label (tests and keyboard use).
function M:Choose(label)
  for _, r in ipairs(self.rows) do
    if r:IsShown() and r.item and r.item.label == label then r:GetScript("OnClick")(r, "LeftButton") return true end
  end
  return false
end
