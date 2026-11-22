-- Merchant module (SPEC 19.2): auto-repair and auto-sell junk at vendors, with a short chat
-- summary, a never-sell list (Alt-click an item) and an optional "sell soulbound gear I can't use".
local ADDON, Panoply = ...
local C = Panoply.Compat
local Mer = Panoply.Modules:Register({
  key = "merchant", label = "Merchant", icon = "Vendor",
  desc = "Repairs your gear and sells grey items when you talk to a vendor, then says what it did.",
  defaults = { autoRepair = true, guildRepair = false, autoSellJunk = true, sellUnusable = false, neverSell = {} },
})
Panoply.Merchant = Mer
Mer.SELL_DELAY = 0.2   -- seconds between sells (the server drops very fast item use)

-- Armour / weapon subclasses each class can ever use (Classic rules). Anything else that is
-- soulbound, white or green, and not usable is "unusable gear".
local ARMOR = { cloth = 1, leather = 2, mail = 3, plate = 4, shield = 6, libram = 7, idol = 8, totem = 9 }
local CAN = {
  WARRIOR = { a = { 1, 2, 3, 4, 6 }, w = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
  PALADIN = { a = { 1, 2, 3, 4, 6, 7 }, w = { 0, 1, 4, 5, 6, 7, 8 } },
  HUNTER = { a = { 1, 2, 3 }, w = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
  ROGUE = { a = { 1, 2 }, w = { 2, 3, 4, 7, 13, 15, 16, 18 } },
  PRIEST = { a = { 1 }, w = { 4, 10, 15, 19 } },
  SHAMAN = { a = { 1, 2, 3, 6, 9 }, w = { 0, 1, 4, 5, 10, 13, 15 } },
  MAGE = { a = { 1 }, w = { 7, 10, 15, 19 } },
  WARLOCK = { a = { 1 }, w = { 7, 10, 15, 19 } },
  DRUID = { a = { 1, 2, 8 }, w = { 4, 5, 6, 10, 13, 15 } },
}
Mer.CAN, Mer.ARMOR = CAN, ARMOR
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

function Mer.Unusable(ii, classFile)
  if not ii or not classFile or not CAN[classFile] then return false end
  local cls, sub = ii.classID, ii.subclassID
  if cls == 4 then
    if sub == 0 or ii.equipLoc == "INVTYPE_CLOAK" then return false end   -- rings, necks, trinkets, cloaks
    return not has(CAN[classFile].a, sub)
  elseif cls == 2 then
    if sub == 20 or sub == 14 then return false end                       -- fishing poles, misc
    return not has(CAN[classFile].w, sub)
  end
  return false
end

function Mer:Protected(id) return Panoply.db and Panoply.db.neverSell and Panoply.db.neverSell[id] and true or false end
function Mer:ToggleProtect(item)
  local id = C.ItemIDFromLink(item)
  if not id or not Panoply.db then return nil end
  Panoply.db.neverSell = Panoply.db.neverSell or {}
  local on = not Panoply.db.neverSell[id]
  Panoply.db.neverSell[id] = on or nil
  local ii = C.ItemInfo(id)
  local name = ii and (ii.link or ii.name) or ("item " .. id)
  Panoply:Print(on and ("Will never sell " .. name .. ". Alt-click it again to allow selling.") or ("May sell " .. name .. " again."))
  Panoply:Fire("NEVER_SELL_CHANGED", id, on)
  return on
end

-- Should this bag slot be sold? Returns ok, value, reason.
function Mer:ShouldSell(info)
  if not info or not info.itemID or info.locked then return false end
  if self:Protected(info.itemID) then return false, 0, "protected" end
  local ii = C.ItemInfo(info.link or info.itemID)
  local price = ii and ii.sellPrice or 0
  if info.noValue or price <= 0 then return false, 0, "no value" end
  local q = info.quality or (ii and ii.quality)
  local value = price * (info.count or 1)
  if q == 0 then return true, value, "junk" end
  if Panoply.db.sellUnusable and (q == 1 or q == 2) and info.bound then
    local classFile = (C.PlayerInfo() or {}).classFile
    if Mer.Unusable(ii, classFile) then return true, value, "unusable" end
  end
  return false, 0
end

function Mer:SellList()
  local out = {}
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, C.NumSlots(bag) do
      local info = C.SlotInfo(bag, slot)
      local ok, value, why = self:ShouldSell(info)
      if ok then out[#out + 1] = { bag = bag, slot = slot, itemID = info.itemID, value = value, why = why } end
    end
  end
  return out
end

-- Selling stops when the vendor closes, the buyback tab is open or combat starts.
function Mer:CanSellNow()
  return C.MerchantShown() and not C.MerchantBuybackTab() and not C.InCombat()
end

function Mer:Repair(s)
  if not Panoply.db.autoRepair or not C.CanRepair() then return end
  local cost, need = C.RepairCost()
  if not need or cost <= 0 then return end
  if Panoply.db.guildRepair and C.CanGuildRepair() then
    if C.RepairAll(true) then s.repaired, s.guild = cost, true return end
  end
  if C.Money() < cost then
    Panoply:Print(("Not enough gold to repair (%s needed)."):format(C.FormatMoney(cost)))
    return
  end
  if C.RepairAll(false) then s.repaired = cost end
end

function Mer:Summary(s)
  local parts = {}
  if (s.items or 0) > 0 then
    parts[#parts + 1] = ("sold %d item%s for %s"):format(s.items, s.items == 1 and "" or "s", C.FormatMoney(s.earned))
  end
  if (s.repaired or 0) > 0 then
    parts[#parts + 1] = ("repaired for %s%s"):format(C.FormatMoney(s.repaired), s.guild and " (guild bank)" or "")
  end
  -- (0.9.5 phase 4F: a visit with nothing to do is remembered too, for Field Kit's "Last visit"; nothing is printed for it)
  if #parts == 0 then self.lastSummary = "Nothing to repair or sell." return nil end
  local msg = parts[1]:gsub("^%l", string.upper) .. (parts[2] and (", " .. parts[2]) or "") .. "."
  if s.stopped then msg = msg .. " Stopped early: " .. s.stopped .. "." end
  Panoply:Print(msg)
  self.lastSummary = msg
  return msg
end

function Mer:Pump()
  local s = self.session
  if not s or s.done then return end
  if not self.active or not self:CanSellNow() then
    s.stopped = not self.active and "module off" or C.InCombat() and "combat" or "vendor closed"
    s.done = true
    self:Summary(s)
    return
  end
  -- 0.6.0 (taint fix): while a spell waits for its target (an enchant, a stone) or something is
  -- on the cursor, selling would be "use the spell on this item" / a drop, which only the
  -- player's own click may do. Wait and try again; give up quietly after a while.
  if C.SpellTargeting() or C.CursorHasItem() then
    s.waits = (s.waits or 0) + 1
    if s.waits > 120 then s.stopped = "a spell or item was waiting on the cursor"; s.done = true; s.queue = {}; self:Summary(s) return end
    C.After(0.5, function() Mer:Pump() end)
    return
  end
  local job = table.remove(s.queue, 1)
  if not job then s.done = true; self:Summary(s) return end
  local info = C.SlotInfo(job.bag, job.slot)
  if info and info.itemID == job.itemID and self:ShouldSell(info) then
    if C.UseSlot(job.bag, job.slot) then s.items = s.items + 1; s.earned = s.earned + job.value end
  end
  C.After(self.SELL_DELAY, function() Mer:Pump() end)
end

function Mer:OnShow()
  if self.session and not self.session.done then self.session.done = true end
  local s = { items = 0, earned = 0, repaired = 0, queue = {} }
  self.session = s
  self:Repair(s)
  if Panoply.db.autoSellJunk and self:CanSellNow() then
    s.queue = self:SellList()
  end
  if #s.queue == 0 then s.done = true; self:Summary(s) return end
  self:Pump()
end

function Mer:SellNow()
  if not C.MerchantShown() then Panoply:Print("Talk to a vendor first.") return end
  local s = { items = 0, earned = 0, repaired = 0, queue = self:SellList() }
  self.session = s
  if #s.queue == 0 then s.done = true Panoply:Print("Nothing to sell.") return end
  self:Pump()
end

Mer:On("MERCHANT_SHOW", function() C.After(0.1, function() if Mer.active then Mer:OnShow() end end) end)
Mer:On("MERCHANT_CLOSED", function() if Mer.session and not Mer.session.done then Mer.session.queue = {} end end)

-- Alt-click in the game's own bags toggles "never sell" too (our bag window does it itself).
local hooked = false
function Mer:Enable()
  if hooked then return end
  hooked = true
  local function onClick(btn, button)
    if not (Mer.active and C.AltDown() and button == "LeftButton") then return end
    local bag = btn.GetBagID and C.pc(btn.GetBagID, btn) or (btn.GetParent and btn:GetParent() and btn:GetParent().GetID and btn:GetParent():GetID())
    local slot = btn.GetID and btn:GetID()
    local info = bag and slot and C.SlotInfo(bag, slot)
    if info and info.itemID then Mer:ToggleProtect(info.link or info.itemID) end
  end
  C.Hook("ContainerFrameItemButton_OnModifiedClick", onClick)
  if _G.ContainerFrameItemButtonMixin then C.Hook(ContainerFrameItemButtonMixin, "OnModifiedClick", onClick) end
end
function Mer:Disable()
  if self.session then self.session.queue = {} end
end

Mer.options = {
  { type = "check", key = "autoRepair", label = "Repair at vendors", tip = "Repairs all your gear when you talk to a vendor who can repair." },
  { type = "check", key = "guildRepair", label = "Use guild bank for repairs", tip = "Pay repairs from the guild bank when your guild allows it. Only shown where the game supports guild repairs.", only = function() return C.HasGuildRepair() end },
  { type = "check", key = "autoSellJunk", label = "Sell grey items", tip = "Sells every grey (junk) item when you talk to a vendor. Alt-click an item in your bags to protect it." },
  { type = "check", key = "sellUnusable", label = "Also sell soulbound gear I can't use", tip = "White and green soulbound armour or weapons your class can never use. Off by default." },
}
