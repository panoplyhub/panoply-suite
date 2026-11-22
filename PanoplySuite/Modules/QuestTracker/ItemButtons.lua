-- Quest tracker (SPEC 23.4): quest item buttons. Secure action buttons (type "item"); one click
-- is one use, by the game's own template. Panoply Suite only ever sets WHICH item a button uses,
-- and only out of combat: in combat nothing secure is created, moved, shown, hidden or changed.
-- Changes wait for PLAYER_REGEN_ENABLED; meanwhile the row's own (plain) item slot shows a dimmed
-- look-alike. No automation: nothing is used without the player's own click or key press.
local ADDON, Panoply = ...
local C, QT = Panoply.Compat, Panoply.QuestTracker
local I = { pool = {}, created = 0 }
QT.Items = I
I.NEAREST = "HearthpathQuestItemNearest"
I.TICK = 3
_G["BINDING_NAME_CLICK " .. I.NEAREST .. ":LeftButton"] = "Use nearest quest item"

local function opt(k) return Panoply.db and Panoply.db[k] end

-------------------------------------------------------------------------------
-- Which item belongs to which quest (plain reads; safe any time)
-------------------------------------------------------------------------------
local function questRecord(id)
  local QD = Panoply.QuestData
  if not QD or not QD.GetQuest then return nil end
  local ok, q = pcall(QD.GetQuest, QD, id)
  return ok and q or nil
end

-- Sets e.item = { id, icon, count } on every entry that has a usable quest item.
function I:Assign(entries)
  local on = opt("trackerItems") ~= false
  local bagByQuest, bagByItem = {}, {}
  if on then
    for _, b in ipairs(C.BagQuestItems()) do
      bagByItem[b.itemID] = bagByItem[b.itemID] or b
      if b.questID and not bagByQuest[b.questID] and C.ItemUsable(b.itemID) then bagByQuest[b.questID] = b end
    end
  end
  self.any = false
  for _, e in ipairs(entries) do
    e.item = nil
    if on then
      local id, icon = C.QuestSpecialItem(e.logIndex)
      if not id then
        local b = bagByQuest[e.questID]
        if b then id, icon = b.itemID, b.icon end
      end
      if not id then
        local q = questRecord(e.questID)
        if q then
          local cands = { q.sourceItem }
          for _, it in ipairs((q.objectives and q.objectives.items) or {}) do cands[#cands + 1] = it[1] end
          for _, cid in ipairs(cands) do
            if cid and cid ~= 0 and bagByItem[cid] and C.ItemUsable(cid) then id, icon = cid, bagByItem[cid].icon break end
          end
        end
      end
      if id then
        e.item = { id = id, icon = icon or C.ItemIcon(id), count = C.ItemCount(id) or 0 }
        self.any = true
      end
    end
  end
  self:Ticker()
end

-------------------------------------------------------------------------------
-- Secure buttons
-------------------------------------------------------------------------------
local function setItem(b, itemID)
  -- the only secure attributes Panoply Suite ever sets; out of combat only (callers check)
  if b.itemID == itemID then return end
  b:SetAttribute("type", itemID and "item" or nil)
  b:SetAttribute("item", itemID and ("item:" .. itemID) or nil)
  b.itemID = itemID
end
I.SetItem = setItem

function I:NewButton()
  self.created = self.created + 1
  local b = CreateFrame("Button", "PanoplySuiteQuestItem" .. self.created, UIParent, "SecureActionButtonTemplate")
  b:SetSize(QT.ITEM, QT.ITEM)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetFrameStrata("MEDIUM")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.icon = icon
  local rim = b:CreateTexture(nil, "OVERLAY")
  rim:SetAllPoints(b)
  Panoply.Skin.Round(rim, 6, QT.MEDIA .. "PanelSLine")
  local t = QT.Color("trim")
  rim:SetVertexColor(t[1], t[2], t[3], 1)
  local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  cd:SetAllPoints(icon)
  b.cooldown = cd
  local count = QT.NewText(b, "semi", 10, QT.Color("text"))
  count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  count:SetJustifyH("RIGHT")
  count:SetWordWrap(false)
  b.count = count
  b:SetScript("OnEnter", function(self)
    local GT = _G.GameTooltip
    if not GT or not self.itemID then return end
    GT:SetOwner(self, "ANCHOR_LEFT")
    if GT.SetHyperlink then pcall(GT.SetHyperlink, GT, "item:" .. self.itemID) end
    GT:AddLine("Click to use", 0.36, 0.74, 0.82)
    GT:Show()
  end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b.panoplyTip = "Quest item"
  b:Hide()
  return b
end

function I:Button(i)
  if not self.pool[i] then self.pool[i] = self:NewButton() end
  return self.pool[i]
end

function I:AnyShown()
  for _, b in ipairs(self.pool) do if b:IsShown() then return true end end
  return false
end

-- Where a row's slot is on the screen, if it is fully inside the visible part of the list.
local function slotPlace(slot)
  local f, sf = QT.frame, QT.scroll
  if not (f and f:IsShown() and sf and sf:IsShown() and slot:IsShown()) then return nil end
  local row = slot:GetParent()
  if row and row.IsShown and not row:IsShown() then return nil end
  local l, t, b = slot:GetLeft(), slot:GetTop(), slot:GetBottom()
  local st, sb = sf:GetTop(), sf:GetBottom()
  if not (l and t and b and st and sb) then return nil, "unknown" end
  if t > st + 1 or b < sb - 1 then return nil end
  local ratio = (slot:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return l * ratio, t * ratio
end

local function resetSlot(slot)
  slot.covered, slot.placeholder = nil, nil
  slot.icon:Hide()
  if slot.icon.SetDesaturated then slot.icon:SetDesaturated(false) end
  slot:EnableMouse(false)
end

-- Out of combat: put one secure button over each visible item slot; hide and clear the rest.
function I:Place()
  if C.InCombat() then self.pending = true self:Placeholders() return false end
  self.pending = nil
  local n, retry = 0, false
  for _, r in ipairs(QT.shownRows or {}) do
    local slot = r.slot
    if slot and slot.hasItem and slot.itemID and r.e and r.e.item then
      local x, y = slotPlace(slot)
      if y == "unknown" then retry = true end
      if x then
        n = n + 1
        local b = self:Button(n)
        setItem(b, slot.itemID)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        b:SetFrameLevel((QT.frame:GetFrameLevel() or 1) + 20)
        b.slot, b.e = slot, r.e
        b:Show()
        resetSlot(slot)
        slot.covered = b
      else
        resetSlot(slot)
      end
    elseif slot then resetSlot(slot) end
  end
  for i = n + 1, #self.pool do
    local b = self.pool[i]
    b:Hide()
    setItem(b, nil)
    b.slot, b.e = nil, nil
  end
  self.shown = n
  if retry and not self.retrying then
    -- the client has not laid the rows out yet (first frame): try once more shortly
    self.retrying = true
    C.After(0.1, function() I.retrying = false I:Place() end)
  end
  self:Visuals()
  self:UpdateNearest()
  return true
end

-- In combat: a dimmed plain look-alike in every slot no secure button covers with the right item.
function I:Placeholders()
  for _, r in ipairs(QT.shownRows or {}) do
    local slot = r.slot
    if slot and slot.hasItem and r.e and r.e.item then
      local b = slot.covered
      if not (b and b.itemID == slot.itemID and b.slot == slot) then
        Panoply.Icons:Apply(slot.icon, r.e.item.id, r.e.item.icon)
        if slot.icon.SetDesaturated then slot.icon:SetDesaturated(true) end
        slot.icon:SetAlpha(0.6)
        slot.icon:Show()
        slot:EnableMouse(true)
        slot.placeholder = true
        QT.Tip(slot, "Quest item", "Ready after combat: item buttons can only change outside combat.")
      end
    end
  end
end

-- Count and cooldown (plain visuals; fine in combat).
function I:Visuals()
  for _, b in ipairs(self.pool) do
    if b:IsShown() and b.itemID then
      local e = b.e
      Panoply.Icons:Apply(b.icon, b.itemID, e and e.item and e.item.icon)
      local c = C.ItemCount(b.itemID) or 0
      b.count:SetText(c > 1 and tostring(c) or "")
      b.icon:SetAlpha(c > 0 and 1 or 0.4)
      local s, d = C.ItemCooldown(b.itemID)
      if b.cooldown.SetCooldown then
        if d and d > 0 then b.cooldown:SetCooldown(s, d) b.cooldownShown = { s, d }
        else b.cooldown:SetCooldown(0, 0) b.cooldownShown = nil end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- "Use nearest quest item" key binding (the player sets the key in Key Bindings)
-------------------------------------------------------------------------------
function I:NearestButton()
  if self.nearest then return self.nearest end
  local b = CreateFrame("Button", self.NEAREST, UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetSize(1, 1)
  b:Hide()
  self.nearest = b
  return b
end

function I:PickNearest()
  local best, bd
  local pm, px, py = C.GetPlayerPos()
  local pos = pm and { pm, px, py } or nil
  for _, e in ipairs(QT.entries or {}) do
    if e.item and not e.hidden and (C.ItemCount(e.item.id) or 0) > 0 then
      local _, d = QT:Nearest(e.questID, e.isComplete, pos)
      if not best or (d and (not bd or d < bd)) then best, bd = e, d end
    end
  end
  return best
end

function I:UpdateNearest()
  if C.InCombat() then return false end
  local want = QT:IsOn() and opt("trackerItems") ~= false and self:PickNearest() or nil
  local id = want and want.item.id or nil
  if id or self.nearest then setItem(self:NearestButton(), id) end
  self.nearestQuest = want and want.questID or nil
  return true
end

-- 3 s refresh only while a quest item exists (nearest item for the key; distance order).
function I:Ticker()
  if not self.any or self.ticking then return end
  self.ticking = true
  local function tick()
    if not (I.any and QT:IsOn()) then I.ticking = false return end
    if not C.InCombat() then
      I:UpdateNearest()
      if Panoply.db and Panoply.db.trackerSort == "distance" then QT:Refresh("distance") end
    end
    C.After(I.TICK, tick)
  end
  C.After(self.TICK, tick)
end

QT:On("BAG_UPDATE_COOLDOWN", function() I:Visuals() end)
QT:On("SPELL_UPDATE_COOLDOWN", function() I:Visuals() end)
QT:On("BAG_UPDATE", function() I:Visuals() end)
QT:On("PLAYER_REGEN_DISABLED", function() I:Placeholders() end)
