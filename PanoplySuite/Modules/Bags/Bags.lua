-- Bags module (SPEC 19.3): one combined bag window (B key and bag buttons open it), a combined
-- bank window at the banker, search, sort, a bag-slot bar, gold, and offline viewing of your
-- other characters on the realm. Quality glow and badges come from the Glow module.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local Store = Panoply.Inventory
local Bags = Panoply.Modules:Register({
  key = "bags", label = "Bags", icon = "Bags",
  desc = "All your bags in one window, a combined bank, search, sort and your other characters' items.",
  defaults = { bagColumns = 10, bankColumns = 14, bagTooltipCounts = true, bagHidden = {}, bagReplaceDefault = true, bagDragDrop = true },
})
Panoply.Bags = Bags
Bags.SLOT, Bags.GAP, Bags.PAD = 37, 4, 14
Bags.HEAD, Bags.TOOL, Bags.FOOT = 58, 34, 40
Bags.BUY = 30           -- 0.9.5 phase 16: the bank's "Buy a bag slot" / "Buy a bank tab" row
Bags.windows = {}

local QUAL_WORDS = { poor = 0, junk = 0, grey = 0, gray = 0, common = 1, white = 1, uncommon = 2, green = 2,
                     rare = 3, blue = 3, epic = 4, purple = 4, legendary = 5, orange = 5 }

-------------------------------------------------------------------------------
-- Data: live bags of this character, or the saved copy of any character.
-------------------------------------------------------------------------------
function Bags:IsMe(name) local _, me = Store:Me() return name == nil or name == me end

-- Returns list of { bag, slot, itemID, count, quality, link, quest, junk } (empty slots too).
function Bags:Slots(kind, name)
  local out = {}
  local ids = kind == "bank" and C.BankIDs() or C.BagIDs()
  local hidden = (Panoply.db.bagHidden or {})
  local live = self:IsMe(name) and (kind == "bags" or Store.atBank)
  local saved = not live and Store:Char(name)[kind == "bank" and "bank" or "bags"] or nil
  for _, bag in ipairs(ids) do
    if not hidden[kind .. bag] then
      local size = live and C.NumSlots(bag) or (saved and saved[bag] and saved[bag].size or 0)
      local family = live and C.BagFamily(bag) or (saved and saved[bag] and saved[bag].family) or 0
      for slot = 1, size do
        local e = { bag = bag, slot = slot, family = (family ~= 0) and family or nil }
        if live then
          local i = C.SlotInfo(bag, slot)
          if i and i.itemID then
            e.itemID, e.count, e.quality, e.link, e.locked = i.itemID, i.count, i.quality, i.link, i.locked
            e.quest, e.questID, e.questStart = C.SlotQuest(bag, slot)
            e.icon = i.icon
          end
        else
          local it = saved[bag][slot]
          if it then e.itemID, e.count, e.quality, e.link = it[1], it[2], it[3], it[4] end
        end
        if e.itemID then
          local ii = C.ItemInfo(e.link or e.itemID)
          e.quality = e.quality or (ii and ii.quality)
          e.name = ii and ii.name
          -- safety rule: the slot picture is always the game's own icon for this item (container
          -- info, then the item's icon by ID); the game's "?" (134400) until it is known
          -- (0.9.7 hotfix: the game's own "?" is not a picture; Bags:Fill paints the slot again when the game sends the item)
          if Panoply.Icons.IsUnknown(e.icon) then e.icon = C.ItemIcon(e.link or e.itemID) end
          -- junk only from the game's own quality 0 (and a vendor price)
          e.junk = e.quality == 0 and ii and (ii.sellPrice or 0) > 0
          -- quest-class items are only used for search and sorting; the quest MARK needs the API
          e.questClass = ii and ii.classID == 12 or false
        end
        out[#out + 1] = e
      end
    end
  end
  return out, live
end

function Bags.Matches(e, text)
  if not text or text == "" then return true end
  if not e.itemID then return false end
  text = text:lower()
  if QUAL_WORDS[text] then return e.quality == QUAL_WORDS[text] end
  if text == "quest" then return (e.quest or e.questClass) and true or false end
  return (e.name or ""):lower():find(text, 1, true) ~= nil
end

-------------------------------------------------------------------------------
-- 0.8.1: specialty bags (a bag family), shown apart in the combined window: each family's slots get its own tint and the bag bar
-- names it. Family bits as the game reports them (C.BagFamily).
-------------------------------------------------------------------------------
Bags.FAMILIES = {
  { bit = 1, name = "Quiver", color = { 0.80, 0.62, 0.30 } }, { bit = 2, name = "Ammo pouch", color = { 0.80, 0.62, 0.30 } },
  { bit = 4, name = "Soul bag", color = { 0.62, 0.42, 0.85 } }, { bit = 8, name = "Leatherworking bag", color = { 0.72, 0.52, 0.36 } },
  { bit = 32, name = "Herb bag", color = { 0.38, 0.78, 0.42 } }, { bit = 64, name = "Enchanting bag", color = { 0.45, 0.62, 0.95 } },
  { bit = 128, name = "Engineering bag", color = { 0.90, 0.72, 0.30 } }, { bit = 256, name = "Keyring", color = { 0.75, 0.75, 0.75 } },
  { bit = 512, name = "Gem bag", color = { 0.90, 0.45, 0.70 } }, { bit = 1024, name = "Mining bag", color = { 0.62, 0.66, 0.72 } },
}
local function hasBit(v, b) return v and b and (v % (b * 2)) >= b end
function Bags.Family(family)
  if not family or family == 0 then return nil end
  for _, f in ipairs(Bags.FAMILIES) do if hasBit(family, f.bit) then return f end end
  return { bit = family, name = "Special bag", color = { 0.70, 0.70, 0.70 } }
end

-- 0.8.1 ("cannot unequip a bag"): take an equipped bag off, as the game's own bag bar does. The backpack cannot come off,
-- a bag must be empty (the game's rule), and it goes into a free slot of another ordinary bag (a bag never goes into a quiver,
-- a herb bag or the like). Our own buttons call the game's PickupBagFromSlot / PickupContainerItem: never in combat, never while
-- a spell waits for its target. Returns true, or false and the reason the player is told.
function Bags:Unequip(bag)
  if not bag or bag == 0 then return false, "The backpack cannot be taken off." end
  if C.InCombat() then return false, "Bags cannot be changed in combat." end
  if C.BankBagIndex(bag) and not Store.atBank then return false, "Visit a banker to change your bank bags." end
  if not C.BagInvSlot(bag) then return false, "This slot holds no bag that can be taken off." end
  local size = C.NumSlots(bag)
  if size == 0 then return false, "There is no bag in this slot." end
  for slot = 1, size do local i = C.SlotInfo(bag, slot) if i and i.itemID then return false, "Empty this bag first: the game only lets an empty bag be taken off." end end
  local ids = C.BagIDs()
  for _, other in ipairs(ids) do
    if other ~= bag and C.BagFamily(other) == 0 then
      for slot = 1, C.NumSlots(other) do
        local i = C.SlotInfo(other, slot)
        if not (i and i.itemID) then
          if not C.PickupBag(bag) then return false, "The game did not let the bag be picked up." end
          C.PickupSlot(other, slot)
          self:RefreshSoon()
          return true
        end
      end
    end
  end
  return false, "There is no free slot in your other bags to put it in."
end

-- 0.8.1 ("cannot split stacks"): the client's split modifier (Shift) on a stack opens the game's own split box; the split is
-- the game's SplitContainerItem (C.SplitSlot), so charges, locks and counts stay the client's. The game's container template
-- opens the box itself when it knows the stack (Bags:Fill gives it the count it reads, button.count); this opens it for the plain
-- buttons and whenever the template did not.
function Bags.SplitOwner(b)
  if not b.SplitStack then b.SplitStack = function(owner, n) local e = owner.entry if e then C.SplitSlot(e.bag, e.slot, n) end end end
  return b
end
function Bags:OpenSplit(b)
  local e = b and b.entry
  if not (e and e.itemID and (e.count or 1) > 1 and b.panoplyLive) or e.locked or C.CursorHasItem() then return false end
  local SSF = _G.StackSplitFrame
  if SSF and SSF.IsShown and SSF:IsShown() then return true end
  Bags.SplitOwner(b)
  if SSF and SSF.OpenStackSplitFrame then return (pcall(SSF.OpenStackSplitFrame, SSF, e.count, b, "BOTTOMRIGHT", "TOPRIGHT")) end
  if _G.OpenStackSplitFrame then return (pcall(_G.OpenStackSplitFrame, e.count, b, "BOTTOMRIGHT", "TOPRIGHT")) end
  return false
end

-- 0.8.1: whose bags (a list of the characters this account's bags know, the one you play marked)
function Bags:CharacterMenu(kind)
  local w = self:Create(kind)
  local _, me = Store:Me()
  local cur = w.viewing or me
  local items = {}
  for _, n in ipairs(Store:Characters()) do
    local name = n
    items[#items + 1] = { text = name .. (name == me and "  (you)" or ""), checked = (name == cur),
      func = function() Bags:ViewCharacter(kind, name) end }
  end
  if #items == 0 then items[1] = { text = me or "You", checked = true, func = function() end } end
  return items
end
function Bags:ViewCharacter(kind, name)
  local w = self:Create(kind)
  local _, me = Store:Me()
  w.viewing = (name ~= me) and name or nil
  self:Refresh(kind)
end

-------------------------------------------------------------------------------
-- Item buttons. Live slots use the game's container button template (so click, drag, use and
-- tooltips behave exactly like the default bags); offline slots are plain look-only buttons.
-------------------------------------------------------------------------------
local nButtons = 0
-- 0.6.0 (taint fix, a tester: "blocked from an action only available to the Blizzard UI" when she
-- clicked the item to enchant after Make): a live button belongs to ONE bag and ONE slot for
-- its whole life. Its parent frame carries the bag (SetID) and the button the slot (SetID); both
-- are kept by the game itself, so the template's own secure click reads clean values. Panoply Suite
-- never writes bagID, never calls SetBagID, never re-parents a button to another bag.
function Bags:NewButton(parent, live, bag, slot)
  local b
  if live and not C.InCombat() then
    nButtons = nButtons + 1
    for _, kind in ipairs({ "ItemButton", "Button" }) do
      local ok, nb = pcall(CreateFrame, kind, "PanoplySuiteBagItem" .. nButtons, parent, "ContainerFrameItemButtonTemplate")
      if ok and nb then b = nb break end
    end
    if b then b.panoplyTemplate = true end
  end
  b = b or CreateFrame("Button", nil, parent)
  b.panoplyOwn, b.panoplyLive = true, live
  if slot and b.SetID then b:SetID(slot) end
  b.panoplyBag, b.panoplySlot = bag, slot
  if b.panoplyTemplate then Bags.Scrub(b) end
  Bags.Lift(b)
  local S = Bags.SLOT
  b:SetSize(S, S)
  if b.SetNormalTexture then pcall(b.SetNormalTexture, b, "") end
  -- skin v3 slot: inset slate with a slot-coloured hairline (Skin.colors.slotBottom / slotLine)
  local bg, bgLine = Skin.Box(b, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine, layer = "BACKGROUND", lineLayer = "BACKGROUND" })
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  -- 0.5.3: the real item icon keeps its art but gets rounded corners to sit in the rounded slot
  Skin.Mask(icon, Skin.TEX.RoundMaskSmall, b)
  local count = Skin.Text(b, 12, Skin.colors.text); count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  if count.SetJustifyH then count:SetJustifyH("RIGHT") end
  local dim = b:CreateTexture(nil, "OVERLAY"); dim:SetAllPoints(b); Skin.Round(dim, 6, Skin.TEX.RFill); dim:SetVertexColor(0, 0, 0, 0.72); dim:Hide()
  -- hover: a flat cerulean wash (no additive glow)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); Skin.Round(hl, Skin.RADIUS.row, Skin.TEX.RFill)
  hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], 0.18)
  b.panoplyIcon, b.panoplyCount, b.panoplyDim, b.panoplyBG, b.panoplyLine = icon, count, dim, bg, bgLine
  local function onClick(self, button)
    if C.AltDown() and button == "LeftButton" and self.entry and self.entry.itemID and Panoply.Merchant then
      Panoply.Merchant:ToggleProtect(self.entry.link or self.entry.itemID)
      Bags:Refresh()
      return
    end
    -- 0.8.1: the split modifier on a stack: the game's split box (the template opens it itself when it can)
    if button == "LeftButton" and self.panoplyLive and self.entry and C.SplitModifier() and (self.entry.count or 1) > 1 and not C.AltDown() then
      Bags:OpenSplit(self)
      return
    end
    -- plain fallback buttons (made in combat, replaced by real ones after it) cannot be the
    -- target of a spell: only the game's own buttons may do that
    if not self.panoplyTemplate and self.panoplyLive and C.SpellTargeting() then Bags:TargetHint() return end
    if not self.panoplyTemplate and self.panoplyLive and button == "RightButton" and self.entry and C.MerchantShown() then
      C.UseSlot(self.entry.bag, self.entry.slot)
    end
    -- 0.5.9: click to pick up / click to drop on the plain fallback buttons too (the game's
    -- template does this itself)
    if not self.panoplyTemplate and self.panoplyLive and button == "LeftButton" and self.entry and not C.AltDown() then
      C.PickupSlot(self.entry.bag, self.entry.slot)
    end
  end
  if b.panoplyTemplate and b.HookScript then b:HookScript("OnClick", onClick) else b:SetScript("OnClick", onClick) end
  Bags:SetupDrag(b)
  if not b.panoplyTemplate then
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnEnter", function(self)
      local e, GT = self.entry, _G.GameTooltip
      if not (e and e.itemID and GT) then return end
      GT:SetOwner(self, "ANCHOR_RIGHT")
      if self.panoplyLive and GT.SetBagItem then GT:SetBagItem(e.bag, e.slot) elseif e.link and GT.SetHyperlink then GT:SetHyperlink(e.link) end
      if Panoply.Merchant and Panoply.Merchant:Protected(e.itemID) then GT:AddLine("Never sold (Alt-click to change)", 0.5, 0.85, 1) end
      GT:Show()
    end)
    b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  end
  return b
end

function Bags:TargetHint()
  if self.hinted then return end
  self.hinted = true
  Panoply:Print("This bag slot was drawn during combat and can't take a spell. Close and reopen your bags, then click the item again.")
end

-------------------------------------------------------------------------------
-- Drag and drop. Press, hold, drag an item and let go on another slot, a bag in the bar, the
-- bank, the character window or an action bar.
-- 0.5.9.1 (tester: "drag is not live" in 0.5.9): 0.5.9 relied on the template's own drag
-- scripts, but every ITEM_LOCK_CHANGED (fired the moment an item is picked up) redrew the window
-- 0.1 s later by hiding, re-parenting and re-showing every slot button - including the one the
-- mouse was dragging from. That ends the drag in the client, so the release reached no slot and
-- the item stayed on the cursor. Now:
--   * 0.6.0: template buttons keep ALL of the game's own handlers (OnClick, OnDragStart,
--     OnReceiveDrag): they are secure, so a drag or click while a spell waits for its target
--     (enchanting) is the game's own action. 0.5.9.1 replaced the drag handlers with ours, and
--     ours picked items up from add-on code: the game blocks that while a spell is targeting.
--     We only add post-hooks (HookScript) that note when a drag starts and ends. Each button
--     belongs to one bag and slot for good, so the game's code always acts on the slot shown.
--     Plain fallback buttons (made in combat) have our own handlers, which do nothing while a
--     spell is targeting.
--   * a redraw never hides or re-parents a button that is in use, and redraws wait while a drag
--     is in progress (until the drop, OnDragStop, or the cursor is empty).
--   * nothing protected is changed in combat; it is caught up on PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
local function protectedNow(b) return C.InCombat() and b.IsProtected and b:IsProtected() and true or false end
Bags.ProtectedNow = protectedNow

-- Forever launch (a tester, Nov 4 2026: the bag could not be used at all): Forever's
-- ContainerFrameItemButtonTemplate is declared frameLevel="10" (Era's has no level), so a slot made
-- from it sat at level 10 under our window (level 30): drawn behind the window's background and not
-- clickable, while the window was sized for every slot. A slot is kept one level above its parent
-- (the bag frame inside the window). Never in combat: then it waits for the next redraw.
function Bags.Lift(b)
  local p = b.GetParent and b:GetParent()
  if not (p and p.GetFrameLevel and b.GetFrameLevel and b.SetFrameLevel) then return false end
  local want = p:GetFrameLevel() + 1
  if b:GetFrameLevel() >= want then return true end
  if protectedNow(b) then Bags.layoutPending = true return false end
  b:SetFrameLevel(want)
  return true
end
function Bags:DragBegin() self.dragging = true end
function Bags:DragEnd()
  if not self.dragging then return end
  self.dragging = nil
  self:RefreshSoon()
end
local function dragStart(self)
  if not (Panoply.db.bagDragDrop and self.panoplyLive and self.entry) then return end
  C.PickupSlot(self.entry.bag, self.entry.slot)
  if C.CursorHasItem() then Bags:DragBegin() end
end
local function receiveDrag(self)
  if not (self.panoplyLive and self.entry) then return end
  if C.CursorHasItem() then C.PickupSlot(self.entry.bag, self.entry.slot) end
  Bags:DragEnd()
end
local function dragStop() Bags:DragEnd() end
Bags.DragStart, Bags.ReceiveDrag = dragStart, receiveDrag
local function hookDragStart() if C.CursorHasItem() then Bags:DragBegin() end end
Bags.HookDragStart = hookDragStart
function Bags:SetupDrag(b)
  if not b.panoplyLive then return end
  if protectedNow(b) then self.dragPending = true return end
  if b.RegisterForDrag then
    if Panoply.db.bagDragDrop then b:RegisterForDrag("LeftButton") else b:RegisterForDrag() end
  end
  b.panoplyDragOn = Panoply.db.bagDragDrop and true or false
  if not b.panoplyDragScripts then
    b.panoplyDragScripts = true
    if b.panoplyTemplate and b.HookScript then
      b:HookScript("OnDragStart", hookDragStart)
      b:HookScript("OnReceiveDrag", dragStop)
      b:HookScript("OnDragStop", dragStop)
    else
      b:SetScript("OnDragStart", dragStart)
      b:SetScript("OnReceiveDrag", receiveDrag)
      b:SetScript("OnDragStop", dragStop)
    end
  end
end
function Bags:ApplyDrag()
  if C.InCombat() then self.dragPending = true return false end
  self.dragPending = nil
  for _, w in pairs(self.windows) do
    for _, b in ipairs(w.pool and w.pool.L or {}) do self:SetupDrag(b) end
  end
  return true
end
-- A drop on a bag in the bag bar puts the item into that bag (the backpack, a bag, the bank).
function Bags:DropOnBag(bag)
  if not C.CursorHasItem() then self:DragEnd() return false end
  local ok = C.PutInBag(bag)
  self:DragEnd()
  return ok
end

-- The game's container button template carries its own overlays that Blizzard's bag code hides
-- on every update. Our window does not run that code, so we hide them ourselves, every update.
-- (0.5.1 bug: BattlepayItemTexture, the shop "new item" highlight, is visible by default in the
-- Classic template, so every slot - empty ones too - showed a glow in the real client.)
Bags.TEMPLATE_PARTS = { "BattlepayItemTexture", "NewItemTexture", "flash", "IconBorder", "IconOverlay", "IconOverlay2",
  "JunkIcon", "UpgradeIcon", "searchOverlay", "ExtendedSlot", "ExtendedOverlay", "ExtendedOverlay2", "BagStaticTop",
  "BagStaticBottom", "ItemContextOverlay", "BagIndicator", "subicon" }
function Bags.Scrub(b)
  for _, k in ipairs(Bags.TEMPLATE_PARTS) do
    local t = b[k]
    if type(t) == "table" and t.Hide then pcall(t.Hide, t) end
  end
  for _, k in ipairs({ "newitemglowAnim", "flashAnim" }) do
    local a = b[k]
    if type(a) == "table" and a.Stop then pcall(a.Stop, a) end
  end
  local name = b.GetName and b:GetName()
  local q = name and _G[name .. "IconQuestTexture"]
  if q and q.Hide then pcall(q.Hide, q) end
  if b.GetNormalTexture then
    local n = C.pc(b.GetNormalTexture, b)
    if n and n.SetAlpha then pcall(n.SetAlpha, n, 0) end
  end
end

-- The bag and slot the game's template code reads: the slot is the button's ID, the bag is the
-- parent frame's ID (Classic Era reads self:GetParent():GetID(); the modern mixin's GetBagID
-- falls back to the parent's ID when no bagID was set - and Panoply Suite never sets one: a value
-- written by an add-on is "tainted" and the game's click would then be blocked). Buttons are
-- made for one bag and slot (Bags:NewButton), so this only re-checks; never in combat.
function Bags.SetSlotIDs(b, e)
  if protectedNow(b) then
    if b.panoplyBag ~= e.bag or b.panoplySlot ~= e.slot then Bags.layoutPending = true end
    return false
  end
  local p = b.GetParent and b:GetParent()
  if p and p.panoplyBagParent and p.GetID and p:GetID() ~= e.bag and p.SetID then p:SetID(e.bag) end
  if b.SetID and (not b.GetID or b:GetID() ~= e.slot) then b:SetID(e.slot) end
  b.panoplyBag, b.panoplySlot = e.bag, e.slot
  return true
end

function Bags:Fill(b, e, text)
  b.entry = e
  if b.panoplyTemplate then Bags.Scrub(b) end
  -- 0.8.1: the stack size the game's split code reads from the button (its own bag code sets it; ours is not run)
  -- (never in combat: then the game's own click code stays untouched by add-on writes)
  if b.panoplyLive and not C.InCombat() then b.count = e.count or 0 end
  -- 0.8.1: a specialty bag's slots wear its family's tint
  local fam = Bags.Family(e.family)
  b.panoplyFamily = fam and fam.name or nil
  b.panoplyTint = fam and fam.color or Skin.colors.slotLine
  if b.panoplyBG and b.panoplyBG.SetVertexColor then
    if fam then b.panoplyBG:SetVertexColor(fam.color[1] * 0.45, fam.color[2] * 0.45, fam.color[3] * 0.45, 1)
    else local c = Skin.colors.slotBottom if c then b.panoplyBG:SetVertexColor(c[1], c[2], c[3], 1) end end
  end
  if b.panoplyLine and b.panoplyLine.SetVertexColor then
    if fam then b.panoplyLine:SetVertexColor(fam.color[1], fam.color[2], fam.color[3], 1)
    else local c = Skin.colors.slotLine if c then b.panoplyLine:SetVertexColor(c[1], c[2], c[3], 1) end end
  end
  if b.panoplyIcon.SetDesaturated then b.panoplyIcon:SetDesaturated(e.locked and true or false) end
  Bags.SetSlotIDs(b, e)
  Bags.Lift(b)
  if e.itemID then
    Panoply.Icons:Apply(b.panoplyIcon, e.link or e.itemID, e.icon); b.panoplyIcon:Show()
    b.panoplyCount:SetText((e.count or 1) > 1 and tostring(e.count) or "")
  else
    Panoply.Icons:Release(b.panoplyIcon)
    b.panoplyIcon:Hide(); b.panoplyCount:SetText("")
  end
  local match = Bags.Matches(e, text)
  b.matched = match
  -- while searching, only matching items keep their glow and badges; the rest are dimmed
  if Panoply.Glow then
    -- 0.8.4: this character's own live items are also offered to Upgrade Hints (never another character's saved bags)
    if match then Panoply.Glow:Apply(b, e.itemID and e.quality or nil, { quest = e.quest, questStart = e.questStart, junk = e.junk,
      item = b.panoplyLive and e.itemID and (e.link or e.itemID) or nil })
    else Panoply.Glow:Apply(b, nil) end
  end
  if match or not text or text == "" then b.panoplyDim:Hide() else b.panoplyDim:Show() end
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function bagParent(w, bag, live)
  w.bagFrames = w.bagFrames or {}
  local key = (live and "L" or "V") .. bag
  local p = w.bagFrames[key]
  if not p then
    p = CreateFrame("Frame", nil, w.grid)
    p:SetAllPoints(w.grid)
    if p.SetID then p:SetID(bag) end
    p.panoplyBagParent, p.panoplyBag = true, bag
    w.bagFrames[key] = p
  end
  return p
end

function Bags:Create(kind)
  if self.windows[kind] then return self.windows[kind] end
  local name = kind == "bank" and "PanoplySuiteBank" or "PanoplySuiteBags"
-- 0.9.5 phase 4J (spec 02 section 1, theme pass): its own header icon (the bag or the bank, not the shared shield)
  local w = Skin.Window(name, 440, 400, kind == "bank" and "Bank" or "Bags", "", "MEDIUM", kind == "bank" and "Bank" or "Bags")
  w.kind = kind
  -- Nov 2026: a resize grip. A bag window is a grid of slots, so its width is "how many slots in a row" (the Bag columns /
  -- Bank columns setting, which is what is remembered) and its height follows the slots: when the grip is let go the window
  -- takes the nearest whole number of columns. Not in combat (the slots are the game's own protected buttons).
  Skin.Resizable(w, { combat = false, minW = 380, minH = 160, onSize = function(wd, _, done) if done then Bags:ColumnsFromWidth(kind, wd) end end })
  -- sit above the guide window when they overlap, and come forward when clicked
  if w.SetToplevel then w:SetToplevel(true) end
  if w.SetFrameLevel then w:SetFrameLevel(30) end
  Panoply.Windows:OwnPlace(w)      -- 0.9.5: the bag windows keep their corners; opened from a page they still come in front of it
  w.pool = { L = {}, V = {} }
  if kind == "bags" then w:ClearAllPoints(); w:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
  else w:ClearAllPoints(); w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -110) end
  local P = Bags.PAD
  -- Toolbar: whose bags, search, sort, bag bar, bank
  -- 0.8.1: a list of characters (was: click through the names)
  local who
  who = Skin.Button(w, "", 120, 24, function() Skin.Menu(who, Bags:CharacterMenu(kind), { width = 200 }) end, "Whose items",
    "Pick a character from the list to look through their bags. Your other characters' items are what they had when you last logged them out.")
  who:SetPoint("TOPLEFT", w, "TOPLEFT", P, -Bags.HEAD)
  w.who = who
  local box = CreateFrame("EditBox", name .. "Search", w)
  box:SetHeight(24); box:SetAutoFocus(false)
  if box.SetFontObject and _G.ChatFontNormal then box:SetFontObject(ChatFontNormal) end
  if box.SetTextInsets then box:SetTextInsets(26, 8, 0, 0) end
  Skin.Box(box, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  local mag = box:CreateTexture(nil, "ARTWORK"); Skin.SetGlyph(mag, "Search"); mag:SetSize(14, 14); mag:SetPoint("LEFT", box, "LEFT", 7, 0)
  local hint = Skin.Text(box, 12, Skin.colors.dim); hint:SetPoint("LEFT", box, "LEFT", 26, 0); hint:SetText("Search")
  box:SetScript("OnTextChanged", function(self) local t = self:GetText() or "" if t == "" then hint:Show() else hint:Hide() end w.search = t; Bags:Refresh(kind) end)
  box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetPoint("LEFT", who, "RIGHT", 8, 0)
  w.searchBox = box
  w.sortBtn = Skin.IconButton(w, "", 24, function() Bags:Sort(kind) end, "Sort", "Tidy these bags: same kinds of items together, best first.")
  w.sortBtn:SetIcon("Sort")
  w.barBtn = Skin.IconButton(w, "", 24, function() w.showBar = not w.showBar; Bags:Refresh(kind) end, "Bag slots", "Show your bags so you can hide one from this window or swap a bag.")
  w.barBtn:SetIcon("Bags")
  w.barBtn:SetPoint("TOPRIGHT", w, "TOPRIGHT", -P, -Bags.HEAD)
  w.sortBtn:SetPoint("RIGHT", w.barBtn, "LEFT", -6, 0)
  if kind == "bags" then
    w.bankBtn = Skin.IconButton(w, "", 24, function() Bags:Toggle("bank") end, "Bank", "Open your bank as it was the last time you visited a banker (live when you are at one).")
    w.bankBtn:SetIcon("Bank")
    w.bankBtn:SetPoint("RIGHT", w.sortBtn, "LEFT", -6, 0)
    box:SetPoint("RIGHT", w.bankBtn, "LEFT", -8, 0)
  else
    box:SetPoint("RIGHT", w.sortBtn, "LEFT", -8, 0)
  end
  w.grid = CreateFrame("Frame", nil, w)
  w.grid:SetPoint("TOPLEFT", w, "TOPLEFT", P, -(Bags.HEAD + Bags.TOOL))
  -- Footer: gold, free slots, bag bar
  w.money = Skin.Text(w, 13, Panoply.Kit.Color("text.primary")); w.money:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -(P + 12), 14)   -- clear of the resize grip in the corner
  if w.money.SetJustifyH then w.money:SetJustifyH("RIGHT") end
  w.free = Skin.Text(w, 12, Panoply.Kit.Color("text.muted")); w.free:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", P, 14)
  w.bar = CreateFrame("Frame", nil, w); w.bar:SetHeight(30)
  w.barButtons = {}
  local ids = kind == "bank" and C.BankIDs() or C.BagIDs()
  for i, bag in ipairs(ids) do
    local bb = Skin.IconButton(w.bar, "", 28, function()
        if C.CursorHasItem() then Bags:DropOnBag(bag) return end   -- 0.5.9: holding an item: put it in this bag
        Bags:ToggleBag(kind, bag)
      end, "Bag " .. (i - (kind == "bank" and 1 or 0)),
      "Shown: click to hide its slots in the window. Drop an item here to put it in this bag.")
    bb.panoplyName = "Bag " .. (i - (kind == "bank" and 1 or 0))
    bb:SetScript("OnReceiveDrag", function() Bags:DropOnBag(bag) end)
    -- 0.8.1: right-click takes the bag off; dragging it picks it up, as the game's own bag bar does (not the backpack, not the bank)
    -- 0.9.5 phase 16: the bank's bag slots too, as the game's bank window does (only at a banker; Bags:Unequip says so)
    if (kind == "bags" and bag ~= 0) or (kind == "bank" and C.BankBagIndex(bag)) then
      if bb.RegisterForClicks then bb:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
      if bb.RegisterForDrag then bb:RegisterForDrag("LeftButton") end
      bb:SetScript("OnDragStart", function()
        if kind == "bank" and not Store.atBank then return end
        if not C.InCombat() and C.PickupBag(bag) then Bags:DragBegin() end
      end)
      local hook = bb.HookScript and "HookScript" or nil
      local function onUp(_, btn)
        if btn ~= "RightButton" then return end
        local ok, why = Bags:Unequip(bag)
        if not ok and why then Panoply:Print(why) end
      end
      if hook then bb:HookScript("OnMouseUp", onUp) else bb:SetScript("OnMouseUp", onUp) end
    end
    bb:SetPoint("LEFT", w.bar, "LEFT", (i - 1) * 32, 0)
    bb.bag = bag
    w.barButtons[#w.barButtons + 1] = bb
  end
  -- 0.9.5 phase 16 ("bank bag can't buy bag slots"): the game's bank window has a Purchase button with the next slot's price;
  -- ours is this row, shown at a banker while a bank bag slot is left to buy. The click opens the game's own confirm box.
  if kind == "bank" then
    w.buy = CreateFrame("Frame", nil, w); w.buy:SetHeight(Bags.BUY)
    w.buy.btn = Skin.Button(w.buy, "Buy a bag slot", 140, 26, function() Bags:BuyBankSlot() end, "Buy a bag slot",
      "Buys the next bank bag slot, as the game's own bank window does. The game asks you to confirm the price first.")
    Skin.FitButton(w.buy.btn, 120, 220)
    w.buy.btn:SetPoint("LEFT", w.buy, "LEFT", 0, 0)
    w.buy.cost = Skin.Text(w.buy, 12, Panoply.Kit.Color("text.primary"))
    w.buy.cost:SetPoint("LEFT", w.buy.btn, "RIGHT", 10, 0)
    w.buy:Hide()
  end
  -- 0.6.1 safety net: every bag hidden -> say so in the empty grid, with one click to show them all
  w.allHidden = CreateFrame("Frame", nil, w.grid)
  w.allHidden:SetPoint("TOPLEFT", w.grid, "TOPLEFT", 0, 0)
  w.allHidden:SetSize(360, Bags.SLOT)
  w.allHidden.text = Skin.Text(w.allHidden, 12, Panoply.Kit.Color("text.muted"))
  w.allHidden.text:SetPoint("LEFT", w.allHidden, "LEFT", 2, 0)
  w.allHidden.text:SetText(kind == "bank" and "All bank bags are hidden." or "All bags are hidden.")
  w.allHidden.show = Skin.Button(w.allHidden, "Show all", 92, 26, function() Bags:ShowAllBags(kind) end,
    "Show all", "Show the slots of every bag in this window again.")
  w.allHidden.show:SetPoint("LEFT", w.allHidden.text, "RIGHT", 10, 0)
  w.allHidden:Hide()
  w:SetScript("OnHide", function() if kind == "bank" and Store.atBank then local B = _G.C_Bank local f = (B and B.CloseBankFrame) or _G.CloseBankFrame if f then pcall(f) end end end)
  self.windows[kind] = w
  return w
end

function Bags:ToggleBag(kind, bag)
  Panoply.db.bagHidden = Panoply.db.bagHidden or {}
  local k = kind .. bag
  Panoply.db.bagHidden[k] = not Panoply.db.bagHidden[k] or nil
  self:Refresh(kind)
end

-- 0.6.1: clear every hidden bag of this window (the "Show all" button)
function Bags:ShowAllBags(kind)
  local h = Panoply.db.bagHidden
  if h then for k in pairs(h) do if k:sub(1, #kind) == kind and tonumber(k:sub(#kind + 1)) then h[k] = nil end end end
  self:Refresh(kind)
end

function Bags:AllHidden(kind)
  local h = Panoply.db.bagHidden or {}
  local ids = kind == "bank" and C.BankIDs() or C.BagIDs()
  if #ids == 0 then return false end
  for _, bag in ipairs(ids) do if not h[kind .. bag] then return false end end
  return true
end

-- the number of columns a window of this width holds (within the setting's own range), set and drawn at once
Bags.COLS = { bags = { "bagColumns", 6, 16 }, bank = { "bankColumns", 8, 20 } }
function Bags:ColumnsFromWidth(kind, width)
  local c = Bags.COLS[kind]
  if not (c and Panoply.db) then return nil end
  local cols = math.floor(((width or 0) - 2 * Bags.PAD + Bags.GAP) / (Bags.SLOT + Bags.GAP) + 0.5)
  cols = math.max(c[2], math.min(c[3], cols))
  if Panoply.db[c[1]] ~= cols then Panoply:SetOption(c[1], cols) else self:Refresh(kind) end
  return cols
end

function Bags:NextCharacter(kind)
  local w = self:Create(kind)
  local list = Store:Characters()
  local cur = w.viewing or (select(2, Store:Me()))
  local idx = 1
  for i, n in ipairs(list) do if n == cur then idx = i end end
  w.viewing = list[idx % #list + 1]
  self:Refresh(kind)
end

function Bags:Refresh(kind)
  if not kind then for k in pairs(self.windows) do self:Refresh(k) end return end
  local w = self.windows[kind]
  if not w or not w:IsShown() then return end
  local _, me = Store:Me()
  local name = w.viewing or me
  local entries, live = self:Slots(kind, name)
  w.live = live
  local cols = kind == "bank" and (Panoply.db.bankColumns or 14) or (Panoply.db.bagColumns or 10)
  local S, Gp, P = Bags.SLOT, Bags.GAP, Bags.PAD
  local mode = live and "L" or "V"
  local pool = w.pool[mode]
  w.slots = w.slots or { L = {}, V = {} }
  -- 0.5.9.1: buttons that stay in use are never hidden here (hiding the button a drag started
  -- from ends the drag); only the unused ones are hidden, and only what changed is touched.
  -- 0.6.0: one button per bag slot, made once and never moved to another bag (see NewButton).
  local function hideUnused(list, keep)
    for _, b in ipairs(list) do if not (keep and keep[b]) and b:IsShown() and not protectedNow(b) then b:Hide() end end
  end
  hideUnused(live and w.pool.V or w.pool.L)
  local inUse = {}
  local free, used = 0, 0
  local n = 0
  for i, e in ipairs(entries) do
    n = i
    local byBag = w.slots[mode][e.bag]
    if not byBag then byBag = {} w.slots[mode][e.bag] = byBag end
    local b = byBag[e.slot]
    local parent = bagParent(w, e.bag, live)
    -- a plain button drawn during combat is swapped for the game's real one afterwards
    if b and live and not b.panoplyTemplate and not C.InCombat() and not (Bags.dragging and C.CursorHasItem()) then
      b:Hide(); b.entry = nil
      for k, x in ipairs(pool) do if x == b then table.remove(pool, k) break end end
      b = nil
    end
    if not b then
      b = self:NewButton(parent, live, e.bag, e.slot)
      byBag[e.slot] = b
      pool[#pool + 1] = b
    end
    inUse[b] = true
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = col * (S + Gp), -row * (S + Gp)
    if not protectedNow(b) then
      if b.panoplyX ~= x or b.panoplyY ~= y or b.panoplyGrid ~= w.grid then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", w.grid, "TOPLEFT", x, y)
        b.panoplyX, b.panoplyY, b.panoplyGrid = x, y, w.grid
      end
    elseif b.panoplyX ~= x or b.panoplyY ~= y then
      self.layoutPending = true
    end
    self:Fill(b, e, w.search)
    if not b:IsShown() and not protectedNow(b) then b:Show() end
    if e.itemID then used = used + 1 else free = free + 1 end
  end
  hideUnused(pool, inUse)
  local rows = math.max(1, math.ceil(n / cols))
  local gridW, gridH = cols * S + (cols - 1) * Gp, rows * S + (rows - 1) * Gp
  w.grid:SetSize(gridW, gridH)
  local buy = kind == "bank" and self:BankBuyState(live) or nil
  local h = Bags.HEAD + Bags.TOOL + gridH + 12 + (w.showBar and 36 or 0) + (buy and Bags.BUY + 4 or 0) + Bags.FOOT
  local winW = math.max(380, gridW + P * 2)
  w:SetSize(winW, h)
  if w.buy then
    if buy then
      w.buy:ClearAllPoints()
      w.buy:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", P, Bags.FOOT + (w.showBar and 36 or 0))
      w.buy:SetWidth(winW - 2 * P)
      local noun = buy.mode == "tab" and "Tab" or "Slot"
      local text = (buy.total and ("%s %d of %d"):format(noun, buy.bought + 1, buy.total) or ("%s %d"):format(noun, buy.bought + 1))
        .. (buy.cost and (": " .. Panoply.Kit.Coins(buy.cost)) or "")   -- 4J: coin icons
      w.buy.btn.label:SetText(buy.mode == "tab" and "Buy a bank tab" or "Buy a bag slot")
      w.buy.btn.tip = buy.mode == "tab" and "Buy a bank tab" or "Buy a bag slot"
      Skin.FitButton(w.buy.btn, 120, 220)
      w.buy.cost:SetText(text)
      w.buy.cost:SetWidth(math.max(40, winW - 2 * P - w.buy.btn:GetWidth() - 10))
      if w.buy.cost.SetJustifyH then w.buy.cost:SetJustifyH("LEFT") end
      w.buy.btn:SetEnabledLook(buy.afford)
      local what = buy.mode == "tab" and "bank tab" or "bank bag slot"
      w.buy.btn.tipBody = buy.afford and ("Buys the next " .. what .. ", as the game's own bank window does. The game asks you to confirm the price first.")
        or ("You do not have enough money for the next " .. what .. " yet.")
      w.buy:Show()
    else
      w.buy:Hide()
    end
  end
  w.bar:ClearAllPoints()
  if w.showBar then
    w.bar:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", P, Bags.FOOT)
    w.bar:SetWidth(#w.barButtons * 32); w.bar:Show()
    for _, bb in ipairs(w.barButtons) do
      local hidden = Panoply.db.bagHidden and Panoply.db.bagHidden[kind .. bb.bag]
      bb:SetIcon("Bags")
      -- the real bag's own icon where the game tells us (Blizzard item icons are fine to show)
      local CC = _G.C_Container
      local inv = bb.bag > 0 and (CC and CC.ContainerIDToInventoryID and C.pc(CC.ContainerIDToInventoryID, bb.bag) or C.pc(_G.ContainerIDToInventoryID, bb.bag))
      local tex = inv and C.pc(_G.GetInventoryItemTexture, "player", inv)
      if tex and bb.icon then
        if Skin.live then Skin.live[bb.icon] = nil end  -- the bag's own icon: an icon-style switch must not repaint it
        bb.icon:SetTexture(tex)
      end
      -- 0.6.1: a hidden bag is dimmed and slashed but stays clickable (SetEnabledLook(false) ignored clicks)
      -- 0.9.5 phase 16: a bank bag slot not bought yet is dimmed too, and says so (the game's own bank shows it locked)
      local idx = kind == "bank" and C.BankBagIndex(bb.bag) or nil
      local locked = live and idx and buy ~= nil and buy.mode == "slot" and idx > buy.bought
      bb:SetDimmed(hidden or locked)
      local fam = Bags.Family(live and C.BagFamily(bb.bag) or nil)
      bb.tip = bb.panoplyName .. (fam and (" - " .. fam.name) or "") .. (locked and " (not bought yet)" or (hidden and " (hidden)" or ""))
      if locked then
        bb.tipBody = "This bank bag slot is not bought yet. Use Buy a bag slot below to buy the next one."
      else
        bb.tipBody = (hidden and "Hidden: click to show its slots in the window. Drop an item here to put it in this bag."
          or "Shown: click to hide its slots in the window. Drop an item here to put it in this bag.")
          .. (((kind == "bags" and bb.bag ~= 0) or idx) and " Right-click or drag to take the bag off (it must be empty)." or "")
      end
    end
  else
    w.bar:Hide()
  end
  if self:AllHidden(kind) then w.allHidden:Show() else w.allHidden:Hide() end
  local c = Store:Char(name)
  local money = live and C.Money() or (c.money or 0)
  w.money:SetText(Panoply.Kit.Coins(money))   -- 4J: coin icons
  w.free:SetText(("%d of %d slots free"):format(free, free + used))
  local title = (kind == "bank" and "%s's bank" or "%s's bags"):format(name)
  w.panoplyTitle:SetText(title)
  local state = live and "Live" or ((kind == "bank" and c.bankSeen == nil) and "Not seen yet: visit a banker once"
    or ("Saved copy" .. (name ~= me and (" of " .. name) or "")))
  w.panoplySubtitle:SetText(state)
  w.who.label:SetText(name .. (name == me and "" or "  (saved)") .. "  v")
  w.sortBtn:SetEnabledLook(live)
  w.entries = entries
  Panoply:Fire("BAGS_REFRESHED", kind)
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 16: buying bank space, bag slots on Classic and bank tabs on Forever (2026-11-15, Forever parity)
-------------------------------------------------------------------------------
-- What the buy row shows: nil when there is nothing to buy here (not at a banker, a saved copy, everything bought, or a client without
-- the API); else C.BankBuyInfo() (mode "slot" on Classic, "tab" on Forever) with afford worked out.
function Bags:BankBuyState(live)
  if not (live and Store.atBank) then return nil end
  local info = C.BankBuyInfo()
  if not info or info.full then return nil end
  if info.afford == nil then
    local money = C.MoneyKnown and C.MoneyKnown() or nil
    info.afford = not (info.cost and money and money < info.cost)
  end
  return info
end

-- The confirm box when the game has none of its own (the game's own is used whenever it exists). Yes is the player's click.
local function ownBuyDialog()
  local D = _G.StaticPopupDialogs
  if not D then return nil end
  if not D.PANOPLYSUITE_BUY_BANK then
    D.PANOPLYSUITE_BUY_BANK = { text = "%s", button1 = _G.YES or "Yes", button2 = _G.NO or "No", timeout = 0, whileDead = false,
      hideOnEscape = true, OnAccept = function(_, data)
        if data and data.mode == "tab" then
          local B = _G.C_Bank
          if B and B.PurchaseBankTab then B.PurchaseBankTab(data.bankType) end
        elseif _G.PurchaseSlot then
          PurchaseSlot()
        end
      end }
  end
  return "PANOPLYSUITE_BUY_BANK"
end

-- The player's click on Buy a bag slot (Classic) / Buy a bank tab (Forever). Nothing is bought here: this opens the game's own
-- confirm box (CONFIRM_BUY_BANK_SLOT, whose Yes calls PurchaseSlot; CONFIRM_BUY_BANK_TAB, whose Yes calls C_Bank.PurchaseBankTab), so
-- the purchase is always the player's own click on Yes. Never from an event, a timer or combat. Returns true when the box was asked for.
function Bags:BuyBankSlot()
  if not Store.atBank then Panoply:Print("Visit a banker to buy more bank space.") return false end
  if C.InCombat() then Panoply:Print("Not during a fight.") return false end
  local info = self:BankBuyState(true)
  if not info then
    local any = C.BankBuyInfo()
    Panoply:Print(any and any.full and "Your bank has every slot bought already." or "The game offers nothing to buy at this bank right now.")
    return false
  end
  local what = info.mode == "tab" and "bank tab" or "bank bag slot"
  if not info.afford then
    Panoply:Print("Not enough money for the next " .. what .. (info.cost and (" (" .. C.FormatMoney(info.cost) .. ")") or "") .. ".")
    return false
  end
  local show, D = _G.StaticPopup_Show, _G.StaticPopupDialogs
  if not show then return false end
  if info.mode == "slot" and D and D.CONFIRM_BUY_BANK_SLOT then
    -- the game's own box shows the price its bank window worked out; that window is open (hidden) while we are at the banker
    local bf = _G.BankFrame
    if bf and info.cost and rawget(bf, "nextSlotCost") == nil then bf.nextSlotCost = info.cost end
    show("CONFIRM_BUY_BANK_SLOT")
    return true
  end
  if info.mode == "tab" and D and D.CONFIRM_BUY_BANK_TAB then
    show("CONFIRM_BUY_BANK_TAB", nil, nil, { bankType = info.bankType })
    return true
  end
  local which = ownBuyDialog()
  if not which then return false end
  show(which, ("Buy %s %d for %s?"):format(what, info.bought + 1, info.cost and C.FormatMoney(info.cost) or "the game's price"), nil,
    { mode = info.mode, bankType = info.bankType })
  return true
end

function Bags:Open(kind)
  kind = kind or "bags"
  if not self.active then return end
  local w = self:Create(kind)
  w:Show()
  self:Refresh(kind)
end
function Bags:Close(kind) local w = self.windows[kind or "bags"] if w then w:Hide() end end
function Bags:Toggle(kind)
  kind = kind or "bags"
  local w = self.windows[kind]
  if w and w:IsShown() then w:Hide() else self:Open(kind) end
end

-------------------------------------------------------------------------------
-- Sorting: the game's own sort where the client has one (Forever); on Era our own sorter.
-- 0.7.2 ("sort bag needs to work WAY faster"): the old sorter made one swap, waited 0.15 s,
-- re-read every slot and made the next one: about 11 s for a full, messy set of bags on a fast
-- connection, and when the server took longer than 0.15 s to answer it reached for an item the
-- server still held and stopped half done (measured with tests/v072_bagsort_tests.lua's server stub
-- before the change; the numbers are in PROGRESS-build.md). Now each round plans the whole layout once and makes every swap it safely
-- can at once (each slot used once per round, never a slot the game shows as locked, never two
-- stacks of the same item, which the game would merge instead of swap), then waits only until the
-- server has released those slots and plans the next round. A round puts at least half of the
-- misplaced items in place, so a full set of bags takes a handful of server round trips.
-- Every move is an ordinary bag pick-up (PickupContainerItem), which add-ons may do out of combat.
-------------------------------------------------------------------------------
Bags.SORT_POLL = 0.03     -- s between looks at the slots while the server answers
Bags.SORT_WAIT = 4        -- s: give up when the server holds a slot this long
Bags.SORT_ROUNDS = 60     -- safety stop
Bags.SORT_BATCH = 40      -- swaps sent in one round at most
Bags.SORT_REFUSED = 5     -- rounds in a row where the game refused a pick-up: then stop
local ORDER = { [12] = 1, [0] = 2, [7] = 3, [5] = 4, [9] = 5, [4] = 6, [2] = 7, [1] = 8, [11] = 9, [6] = 10, [15] = 11 }
local EMPTY = "~"
function Bags.SortKey(e)
  if not e.itemID then return EMPTY end
  local ii = e.ii or C.ItemInfo(e.link or e.itemID) or {}   -- SortPlan already read it (one lookup per item a round)
  local group = (e.quest or e.questClass) and 0 or (e.quality == 0 and 99 or (ORDER[ii.classID or 15] or 50))
  return ("%02d%d%04d%s%05d"):format(group, 9 - (e.quality or 1), 9999 - (ii.ilvl or 0), (e.name or ii.name or ""):lower(), 99999 - (e.count or 1))
end

function Bags:Sort(kind)
  local w = self.windows[kind or "bags"]
  if w and not w.live then Panoply:Print("Only your own bags can be sorted, live.") return false end
  if C.InCombat() then Panoply:Print("Sorting waits until you leave combat.") return false end
  if kind == "bank" then if C.SortBank() then return true end
  elseif C.CanSortBags() then if C.SortBags() then return true end end
  return self:StartSorter(kind or "bags")
end

function Bags:SortPlan(kind)
  local ids = kind == "bank" and C.BankIDs() or C.BagIDs()
  local pos = {}
  for _, bag in ipairs(ids) do
    local _, family = C.pc(_G.C_Container and C_Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots, bag)
    if (family or 0) == 0 then
      for slot = 1, C.NumSlots(bag) do
        local i = C.SlotInfo(bag, slot)
        local e = { bag = bag, slot = slot }
        if i and i.itemID then e.itemID, e.count, e.quality, e.link, e.locked = i.itemID, i.count, i.quality, i.link, i.locked; e.quest = C.SlotQuest(bag, slot)
          local ii = C.ItemInfo(e.link or e.itemID); e.ii = ii; e.name = ii and ii.name; e.questClass = ii and ii.classID == 12 or false
          e.stack = ii and ii.stack end   -- nil while the game hasn't loaded the item yet
        pos[#pos + 1] = e
      end
    end
  end
  return pos
end

-- Dropping a stack on another stack of the same item merges them (the game does not swap). An item
-- the game hasn't loaded yet (no stack size) counts as stackable, to be safe.
local function merges(a, b) return a.itemID and a.itemID == b.itemID and (a.stack == nil or a.stack > 1) end

local function sortKeys(pos)
  local key, want = {}, {}
  for i, e in ipairs(pos) do key[i] = Bags.SortKey(e); want[i] = key[i] end
  table.sort(want)
  return key, want
end

function Bags:IsSorted(kind)
  local key, want = sortKeys(self:SortPlan(kind))
  for i = 1, #key do if key[i] ~= want[i] then return false end end
  return true
end

-- The swaps of one round: a list of { from, to }, empty while the server still holds slots; nil
-- when the bags are sorted; false when they can't be finished (only moves that would merge two
-- stacks of one item are left and no slot is free).
function Bags:SortRound(kind)
  local pos = self:SortPlan(kind)
  local key, want = sortKeys(pos)
  local busy, moves, todo, held = {}, {}, false, false
  for i, e in ipairs(pos) do
    if e.locked then busy[i], held = true, true end
    if key[i] ~= want[i] then todo = true end
  end
  if not todo then return nil end
  if held then return moves end   -- the server is still answering the last round
  -- a misplaced slot takes the item it wants from another misplaced slot; best one that wants
  -- what this slot holds (one swap puts both in place)
  for i = 1, #pos do
    if #moves >= Bags.SORT_BATCH then break end
    if key[i] ~= want[i] and not busy[i] and want[i] ~= EMPTY then
      local pick, alt
      for j = 1, #pos do
        if j ~= i and not busy[j] and key[j] == want[i] and key[j] ~= want[j] and not merges(pos[j], pos[i]) then
          if want[j] == key[i] then pick = j break end
          alt = alt or j
        end
      end
      pick = pick or alt
      if pick then
        moves[#moves + 1] = { pos[pick], pos[i] }
        busy[i], busy[pick] = true, true
      end
    end
  end
  if #moves == 0 then
    -- only merging moves are left: park those stacks in free slots first (from the end of the
    -- bags; one stack per free slot), the next round can then swap freely
    local k = #pos
    for i = 1, #pos do
      if #moves >= Bags.SORT_BATCH then break end
      if key[i] ~= want[i] and pos[i].itemID then
        while k > 0 and (pos[k].itemID or busy[k] or k == i) do k = k - 1 end
        if k == 0 then break end
        moves[#moves + 1] = { pos[i], pos[k] }
        busy[k] = true
        k = k - 1
      end
    end
    if #moves == 0 then return false end
  end
  return moves
end

-- The first swap of the next round, or nil when there is none right now (sorted, can't be
-- finished, or the server still holds slots). To ask "sorted?" use Bags:IsSorted.
function Bags:NextSwap(kind)
  local m = self:SortRound(kind)
  if m and m[1] then return m[1][1], m[1][2] end
  return nil
end

function Bags:StartSorter(kind)
  if self.sorting then return false end
  local s = { kind = kind, swaps = 0, rounds = 0, waited = 0, refused = 0 }
  self.sorting = s
  local function stop(sorted, why)
    if Bags.sorting ~= s then return end
    Bags.sorting = nil
    Bags:Refresh(kind)
    if sorted then Panoply:Fire("BAGS_SORTED", kind)
    elseif why then Panoply:Print("Sorting stopped: " .. why) end
  end
  local function round()
    if Bags.sorting ~= s then return end
    if C.InCombat() then return stop(false, "you are in combat. Sort again after the fight.") end
    if C.SpellTargeting() then return stop(false, "a spell is waiting for its target.") end
    if C.CursorHasItem() then return stop(false, "you picked up an item.") end
    if kind == "bank" and not Store.atBank then return stop(false, "the bank closed.") end
    if s.rounds >= Bags.SORT_ROUNDS then return stop(false, "it took too many steps. Sort again to finish.") end
    local moves = Bags:SortRound(kind)
    if moves == nil then return stop(true) end
    if moves == false then return stop(false, "your bags are full, so a few stacks of the same item stay in their order. Free a slot and sort again.") end
    if #moves == 0 then
      s.waited = s.waited + Bags.SORT_POLL
      if s.waited > Bags.SORT_WAIT then return stop(false, "an item stayed locked (in a trade or mail?). Sort again later.") end
      C.After(Bags.SORT_POLL, round)
      return
    end
    s.rounds, s.waited = s.rounds + 1, 0
    local refused = false
    for _, m in ipairs(moves) do
      C.PickupSlot(m[1].bag, m[1].slot); C.PickupSlot(m[2].bag, m[2].slot)
      s.swaps = s.swaps + 1
      -- a pick-up the game refused (busy) leaves an item on the cursor: put it back and send the
      -- rest of this round's swaps next round
      if C.CursorHasItem() then
        if _G.ClearCursor then pcall(ClearCursor) end
        if C.CursorHasItem() then return stop(false, "an item stayed on the cursor.") end
        refused = true
        break
      end
    end
    s.refused = refused and s.refused + 1 or 0
    if s.refused >= Bags.SORT_REFUSED then return stop(false, "the game kept refusing the moves. Sort again in a moment.") end
    C.After(Bags.SORT_POLL, round)
  end
  round()
  return true
end

-------------------------------------------------------------------------------
-- Opening with the B key and bag buttons
-------------------------------------------------------------------------------
-- 0.6.0 (taint fix): Panoply Suite no longer replaces the game's bag functions (ToggleAllBags,
-- OpenAllBags, ToggleBackpack, ...). Replacing them made every piece of the game's own code that
-- calls them - the vendor, the bank, the mailbox, Esc, the B key, the bag bar - carry on as
-- "add-on code", and what it left behind (the vendor's state, read by every bag and character
-- slot click) made the game block the next protected click: clicking the item an enchant
-- should go on. Now the game's functions run untouched; a post-hook (hooksecurefunc, which
-- cannot taint) opens or closes our window to match, and the game's own bag frames are kept
-- out of sight by parking them on a hidden frame (never hidden or closed from our code).
Bags.HOOKS = { ToggleAllBags = "toggle", ToggleBackpack = "toggle", ToggleBag = "toggle",
  OpenAllBags = "open", OpenBackpack = "open", OpenBag = "open",
  CloseAllBags = "close", CloseBackpack = "close", CloseBag = "close" }
local burst
-- One key press or click can run several of these (ToggleBackpack calls ToggleBag; ToggleAllBags
-- opens or closes each bag): the first one in the same moment decides, and if a toggle ended
-- with our window unchanged (it was closed with its own X while the game's stayed open) it is
-- toggled once more right after, so B always does what you expect.
function Bags:FollowGame(how)
  if not (self.took and self.active) then return end
  local w = self.windows.bags
  local now = C.Now and C.Now() or (_G.GetTime and GetTime()) or 0
  if burst and burst.t == now then
    if how == "toggle" then burst.toggle = true end
    return
  end
  local mine = { t = now, before = (w and w:IsShown()) and true or false, toggle = how == "toggle" }
  burst = mine
  if how == "toggle" then self:Toggle("bags") elseif how == "open" then self:Open("bags") else self:Close("bags") end
  C.After(0, function()
    if burst ~= mine then return end
    burst = nil
    local w2 = Bags.windows.bags
    local shown = (w2 and w2:IsShown()) and true or false
    if mine.toggle and shown == mine.before and Bags.took and Bags.active then Bags:Toggle("bags") end
  end)
end
-- Nov 2026 ("equipping a bag from inventory must not close the bag window, so a player can equip 4 bags in a row"). When a bag
-- goes into or out of a bag slot the game closes that one bag's own frame (CloseBag for that bag). Our window is all the bags in one,
-- so one bag closing is not "close the window": a CloseBag on its own closes ours only when it is not part of a bag-slot change and
-- the game then has no bag left open. CloseAllBags and CloseBackpack (Esc, the B key, the vendor leaving) still close it at once;
-- they run CloseBag inside, and are heard right after it.
Bags.SWAP_SECS = 0.5
function Bags:MarkSwap() self.swapAt = (C.Now and C.Now()) or (_G.GetTime and GetTime()) or 0 end
function Bags:SwapJustNow()
  local now = (C.Now and C.Now()) or (_G.GetTime and GetTime()) or 0
  return self.swapAt ~= nil and (now - self.swapAt) <= Bags.SWAP_SECS
end
function Bags.AnyGameBagOpen()
  if type(_G.IsBagOpen) ~= "function" then return false end
  for _, bag in ipairs(C.BagIDs()) do
    local ok, open = pcall(_G.IsBagOpen, bag)
    if ok and open then return true end
  end
  return false
end
function Bags:FollowBagClose()
  if not (self.took and self.active) then return end
  local w = self.windows.bags
  if not (w and w:IsShown()) then return end
  self.closeAsk = (self.closeAsk or 0) + 1
  local ask = self.closeAsk
  C.After(0, function()
    if ask ~= Bags.closeAsk then return end                -- several in one moment: the last one decides
    local w2 = Bags.windows.bags
    if not (w2 and w2:IsShown() and Bags.took and Bags.active) then return end
    if Bags:SwapJustNow() or Bags.AnyGameBagOpen() then return end
    Bags:Close("bags")
  end)
end
for _, ev in ipairs({ "BAG_CLOSED", "BAG_CONTAINER_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
  Panoply:On(ev, function() Bags:MarkSwap() end)
end

function Bags:HookGame()
  if self.hooked then return end
  self.hooked = {}
  for fn, how in pairs(Bags.HOOKS) do
    local follow
    if fn == "CloseBag" then follow = function() Bags:FollowBagClose() end
    else follow = function() Bags:FollowGame(how) end end
    if type(_G[fn]) == "function" and C.Hook(_G, fn, follow) then self.hooked[fn] = how end
  end
end
-- The game's own bag frames, parked on a hidden frame while ours replace them (out of combat).
function Bags.GameBagFrames()
  local out = {}
  for i = 1, _G.NUM_CONTAINER_FRAMES or 13 do local f = _G["ContainerFrame" .. i] if f then out[#out + 1] = f end end
  if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
  return out
end
local parked = {}
function Bags:ParkGameBags(on)
  if C.InCombat() then self.parkPending = on and "park" or "unpark" return false end
  self.parkPending = nil
  if on and not self.hider then
    self.hider = CreateFrame("Frame", "PanoplySuiteHiddenBagParent", UIParent)
    self.hider:Hide()
  end
  for _, f in ipairs(Bags.GameBagFrames()) do
    if f.SetParent and f.GetParent and not (f.IsProtected and f:IsProtected() and C.InCombat()) then
      if on and f:GetParent() ~= self.hider then parked[f] = f:GetParent() or UIParent; f:SetParent(self.hider)
      elseif not on and parked[f] then f:SetParent(parked[f]); parked[f] = nil end
    end
  end
  return true
end
function Bags:TakeOver()
  if not Panoply.db.bagReplaceDefault or self.took then return end
  self.took = true
  self:HookGame()
  self:ParkGameBags(true)
end
function Bags:GiveBack()
  if not self.took then return end
  self.took = false
  self:ParkGameBags(false)
end

local bankHidden
local function hideDefaultBank()
  local bf = _G.BankFrame
  if not bf or not Bags.active then return end
  bankHidden = true
  if bf.SetAlpha then bf:SetAlpha(0) end
  if bf.EnableMouse then bf:EnableMouse(false) end
  if bf.ClearAllPoints then bf:ClearAllPoints(); bf:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -2000, -2000) end
end
local function restoreDefaultBank()
  local bf = _G.BankFrame
  if not bf or not bankHidden then return end
  bankHidden = false
  if bf.SetAlpha then bf:SetAlpha(1) end
  if bf.EnableMouse then bf:EnableMouse(true) end
  if bf.ClearAllPoints then bf:ClearAllPoints(); bf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

function Bags:Enable()
  Store:HookTooltip()
  self:TakeOver()
  Store:SaveBags()
end
function Bags:Disable()
  self:GiveBack()
  restoreDefaultBank()
  for _, w in pairs(self.windows) do w:Hide() end
end

Bags:Listen("BANK_OPENED", function() hideDefaultBank(); Bags:Open("bank"); Bags:Open("bags") end)
Bags:Listen("BANK_CLOSED", function() restoreDefaultBank(); Bags:Close("bank"); Bags:Refresh() end)
Bags:Listen("INVENTORY_CHANGED", function() Bags:Refresh() end)
Bags:Listen("NEVER_SELL_CHANGED", function() Bags:Refresh() end)
Panoply:Listen("GLOW_CHANGED", function() if Bags.active then Bags:Refresh() end end)
-- Item locks (picked up / being moved) and late item data (quality, icon, name arriving after the
-- first read) refresh the open windows; bursts are coalesced into one redraw.
function Bags:RefreshSoon()
  if not self.active or self.soon then return end
  self.soon = true
  C.After(0.1, function()
    Bags.soon = false
    if not Bags.active then return end
    -- 0.5.9.1: never redraw under a drag in progress; check again shortly (a drag ends with the
    -- drop, OnDragStop, or when the cursor is empty)
    if Bags.dragging then
      if C.CursorHasItem() then Bags:RefreshSoon() return end
      Bags.dragging = nil
    end
    Bags:Refresh()
  end)
end
Panoply:On("ITEM_LOCK_CHANGED", function() Bags:RefreshSoon() end)
Panoply:On("GET_ITEM_INFO_RECEIVED", function() Bags:RefreshSoon() end)
Panoply:On("BAG_UPDATE_DELAYED", function() Bags:RefreshSoon() end)
-- 0.9.5 phase 16: a bank bag slot bought (PLAYERBANKBAGSLOTS_CHANGED, Classic) or a bank tab (BANK_TABS_CHANGED, Forever), and the bag
-- slot flags; each is skipped on a client that has no such event. The buy row, the price and the bag bar are drawn again.
for _, ev in ipairs({ "PLAYERBANKBAGSLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "BAG_SLOT_FLAGS_UPDATED", "BANK_BAG_SLOT_FLAGS_UPDATED" }) do
  Panoply:On(ev, function() if Store.atBank and Store:Enabled() then Store:Touch() end Bags:RefreshSoon() end)
end
Bags:On("PLAYER_REGEN_ENABLED", function()
  if Bags.dragPending then Bags:ApplyDrag() end
  if Bags.parkPending then Bags:ParkGameBags(Bags.parkPending == "park") end
  Bags.layoutPending = nil
  Bags:Refresh()
end)

Bags.options = {
  { type = "check", key = "bagReplaceDefault", label = "Open these instead of the game's bags", tip = "The B key and bag buttons open Panoply Suite's combined window. Takes effect after /reload when changed." },
  { type = "check", key = "bagDragDrop", label = "Drag and drop items in bags",
    tip = "Press and hold an item, drag it and let go on another slot, bag, the bank, your character or an action bar. Clicking to pick up and clicking to put down works either way.",
    onChange = function() Bags:ApplyDrag() end },
  { type = "check", key = "bagTooltipCounts", label = "Item counts in tooltips", tip = "Shows how many of an item each of your characters has, for example \"Alice: 12 in bags, 40 in bank\"." },
  { type = "slider", key = "bagColumns", label = "Bag columns", min = 6, max = 16, step = 1, fmt = "%d", tip = "How many slots per row in the bag window." },
  { type = "slider", key = "bankColumns", label = "Bank columns", min = 8, max = 20, step = 1, fmt = "%d", tip = "How many slots per row in the bank window." },
}
Panoply.optionHooks.bagColumns = function() Bags:Refresh() end
Panoply.optionHooks.bankColumns = function() Bags:Refresh() end
