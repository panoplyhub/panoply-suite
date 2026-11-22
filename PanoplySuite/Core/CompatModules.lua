-- Panoply Suite Compat, part 2 (0.5.0 modules): add-ons, bags and bank, items, money, merchant,
-- tooltips, world map, minimap, spells and trade skill details. Same rule as Compat.lua: every
-- API is found by existence checks at call time, never by version numbers, and every call is
-- wrapped so a missing or changed API means "unknown", not an error.
local ADDON, Panoply = ...
local C = Panoply.Compat
local G, R = C.G, C.Readable

local function pass(ok, ...) if not ok then return nil end return ... end
local function pc(f, ...) if not f then return nil end return pass(pcall(f, ...)) end
C.pc = pc

-------------------------------------------------------------------------------
-- Add-ons
-------------------------------------------------------------------------------
-- 0.6.1: shift-click link into the chat box. ChatFrameUtil.InsertLink is the current name on
-- Forever 1.60.1 and Era 1.15.9; ChatEdit_InsertLink is only a deprecated alias on Forever.
function C.InsertChatLink(link)
  if type(link) ~= "string" then return false end
  local f = G("ChatFrameUtil.InsertLink") or _G.ChatEdit_InsertLink
  if not f then return false end
  local ok, r = pcall(f, link)
  return ok and r and true or false
end

function C.IsAddOnLoaded(name)
  local f = G("C_AddOns.IsAddOnLoaded") or _G.IsAddOnLoaded
  if not f or not name then return false end
  local ok, a, b = pcall(f, name)
  if not ok then return false end
  -- C_AddOns returns (loadedOrLoading, loaded); the old global returns one value.
  return (b ~= nil and b or a) and true or false
end

-------------------------------------------------------------------------------
-- Keys / money
-------------------------------------------------------------------------------
function C.AltDown() return _G.IsAltKeyDown and IsAltKeyDown() and true or false end
function C.CtrlDown() return _G.IsControlKeyDown and IsControlKeyDown() and true or false end
-- After 0.8.4: the money the game shows right now, nil while it is hidden (a secret value on WoW Forever) or cannot be asked.
-- Code that SAVES the amount uses this one, so a hidden value never replaces a saved good one with 0. C.Money() always answers a
-- number: the last amount this session could read, 0 only when it never could.
function C.MoneyKnown()
  local m = R(pc(_G.GetMoney))
  if type(m) ~= "number" then return nil end
  C.lastMoney = m
  return m
end
function C.Money() return C.MoneyKnown() or C.lastMoney or 0 end

function C.FormatMoney(c)
  c = math.floor(math.abs(c or 0))
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%dg %ds %dc"):format(g, s, k) end
  if s > 0 then return ("%ds %dc"):format(s, k) end
  return ("%dc"):format(k)
end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------
function C.ItemIDFromLink(link)
  if type(link) == "number" then return link end
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)")) or tonumber(link)
end

-- { name, link, quality, ilvl, minLevel, type, subtype, stack, equipLoc, icon, sellPrice, classID, subclassID, bindType, setID }
function C.ItemInfo(item)
  local f = G("C_Item.GetItemInfo") or _G.GetItemInfo
  if not f or not item then return nil end
  local r = { pcall(f, item) }
  if not r[1] or not r[2] then return nil end
  return { name = R(r[2]), link = R(r[3]), quality = R(r[4]), ilvl = R(r[5]), minLevel = R(r[6]), type = R(r[7]),
           subtype = R(r[8]), stack = R(r[9]), equipLoc = R(r[10]), icon = R(r[11]), sellPrice = R(r[12]),
           classID = R(r[13]), subclassID = R(r[14]), bindType = R(r[15]), setID = R(r[17]) }
end

-------------------------------------------------------------------------------
-- 0.9.7 in-game hotfix (WoW Forever: red "?" icons on plain items). The ONE place that finds an item's or a spell's picture.
-- Two things went wrong before. (1) Each screen asked the game once, when it drew: an item the game had not loaded yet got the "?"
-- and most screens never looked again. (2) The game can answer with its OWN "?" picture (file 134400) for an item it has not loaded
-- (UNVERIFIED in the real client, the reading that fits what we saw); that is a real value, so it was taken as the item's picture
-- and kept. Here the game's "?" counts as "not known yet", every call the client has is tried, the item is asked for, and a
-- picture drawn through Icons:Apply is painted again when the game sends the item (GET_ITEM_INFO_RECEIVED, ITEM_DATA_LOAD_RESULT).
-- The "?" stays only when every call still fails after the game has answered.
--   Icons:Item(item)              the picture of an item (an id or a link), or nil while the game does not know it
--   Icons:Spell(spell)            the picture of a spell (an id or a name), or nil
--   Icons:Apply(tex, item, known, waiting)
--                                 puts the item's picture on tex (a texture, or anything with SetTexture): `known` (a picture the
--                                 caller already has, the bag slot's for one) when it is a real one, else Icons:Item; otherwise the
--                                 "?" (or `waiting`, a picture the caller would sooner show meanwhile) and a repaint when the item
--                                 arrives. Returns true and the picture, or false.
--   Icons:ApplySpell(tex, spell, fallback)   the spell's picture, else fallback, else the "?"
--   Icons:Release(tex)            tex shows something else now: a late answer must not paint over it
-- Only calls that exist are used (each is looked up by name when it is needed); nothing is added to the game's own tables.
-------------------------------------------------------------------------------
local Icons = { waiting = {}, asked = {}, bound = setmetatable({}, { __mode = "k" }), shown = setmetatable({}, { __mode = "k" }) }
Panoply.Icons = Icons
Icons.UNKNOWN = 134400                       -- the game's question mark (INV_Misc_QuestionMark)
Icons.UNKNOWN_FILE = "inv_misc_questionmark"

-- is this "no picture"? nil, 0, an empty path, or the game's own question mark (by file id or by path)
function Icons.IsUnknown(v)
  v = R(v)
  if type(v) == "number" then return v <= 0 or v == Icons.UNKNOWN end
  if type(v) == "string" then return v == "" or v:lower():find(Icons.UNKNOWN_FILE, 1, true) ~= nil end
  return true
end
local function known(v) v = R(v) if Icons.IsUnknown(v) then return nil end return v end

-- ask the game to load an item (a local request). Once per item until the game answers.
function Icons:Ask(id)
  if not id or self.asked[id] then return false end
  self.asked[id] = true
  local f = G("C_Item.RequestLoadItemDataByID")
  if f then pcall(f, id) end
  return true
end

function Icons:Item(item, noAsk)
  if item == nil then return nil end
  local id = C.ItemIDFromLink(item)
  local v
  -- 1. the item's static facts (they need no loading where the client has the call): the 5th answer is the picture
  local inst = G("C_Item.GetItemInfoInstant") or _G.GetItemInfoInstant
  if inst then local ok, _, _, _, _, icon = pcall(inst, item) v = ok and known(icon) or nil end
  -- 2. the picture by item id
  if not v then v = known(pc(G("C_Item.GetItemIconByID") or _G.GetItemIcon, id or item)) end
  -- 3. the item's full information (only once the game has loaded it): the 10th answer
  if not v then
    local info = G("C_Item.GetItemInfo") or _G.GetItemInfo
    if info then local r = { pcall(info, item) } v = r[1] and known(r[11]) or nil end
  end
  if not v and id and not noAsk then self:Ask(id) end
  return v
end

function Icons:Spell(spell)
  if spell == nil then return nil end
  local v = known(pc(G("C_Spell.GetSpellTexture"), spell))
  if not v then v = known(pc(_G.GetSpellTexture, spell)) end
  if not v then
    local f = G("C_Spell.GetSpellInfo")
    local t = f and pc(f, spell)
    if type(t) == "table" then v = known(t.iconID or t.originalIconID) end
  end
  if not v and _G.GetSpellInfo then local ok, _, _, icon = pcall(_G.GetSpellInfo, spell) v = ok and known(icon) or nil end
  return v
end

function Icons:Release(tex)
  local id = tex and self.bound[tex]
  if not id then return end
  self.bound[tex], self.shown[tex] = nil, nil
  local w = self.waiting[id]
  if w then w[tex] = nil end
end

function Icons:Apply(tex, item, have, waiting)
  if not (tex and tex.SetTexture) then return false end
  self:Release(tex)
  local icon = known(have) or self:Item(item)
  if icon then tex:SetTexture(icon) return true, icon end
  tex:SetTexture(known(waiting) or Icons.UNKNOWN)
  local id = C.ItemIDFromLink(item)
  if id then
    self.bound[tex] = id
    -- what the texture shows while it waits, as the game reports it: a late answer paints only a texture that still shows this
    self.shown[tex] = tex.GetTexture and pc(tex.GetTexture, tex) or nil
    local w = self.waiting[id]
    if not w then w = setmetatable({}, { __mode = "k" }) self.waiting[id] = w end
    w[tex] = true
  end
  return false
end

function Icons:ApplySpell(tex, spell, fallback)
  if not (tex and tex.SetTexture) then return false end
  self:Release(tex)
  local icon = self:Spell(spell)
  tex:SetTexture(icon or known(fallback) or Icons.UNKNOWN)
  return icon ~= nil, icon
end

-- the game sent an item (or said it has none, ok == false): the pictures that waited for it are painted. Nothing is asked again
-- from here, so an item the game never has cannot loop.
function Icons:Arrived(id, ok)
  id = tonumber(R(id))
  if not id then return 0 end
  self.asked[id] = nil
  local w = self.waiting[id]
  if not w then return 0 end
  self.waiting[id] = nil
  local icon = (R(ok) ~= false) and self:Item(id, true) or nil
  local n = 0
  for tex in pairs(w) do
    if self.bound[tex] == id then
      -- (a pooled texture that was given another picture since, by code that does not come through here, is left alone)
      local was, cur = self.shown[tex], tex.GetTexture and pc(tex.GetTexture, tex)
      self.bound[tex], self.shown[tex] = nil, nil
      if icon and (cur == nil or cur == was) then tex:SetTexture(icon) n = n + 1 end
    end
  end
  return n
end
Panoply:On("GET_ITEM_INFO_RECEIVED", function(_, id, ok) Icons:Arrived(id, ok) end)
Panoply:On("ITEM_DATA_LOAD_RESULT", function(_, id, ok) Icons:Arrived(id, ok) end)

function C.ItemIcon(item) return Icons:Item(item) end
function C.SpellIcon(spell) return Icons:Spell(spell) end

-- Item quality colours (the game's own table when present, else the standard values).
C.QUALITY = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}
-- The game's own colour first (C_Item.GetItemQualityColor, then GetItemQualityColor, then
-- ITEM_QUALITY_COLORS), so borders match item names and tooltips exactly.
function C.QualityColor(q)
  if q == nil then return C.QUALITY[1] end
  local f = G("C_Item.GetItemQualityColor") or _G.GetItemQualityColor
  local r, g, b = pc(f, q)
  r, g, b = R(r), R(g), R(b)
  if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
  local t = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
  if t and t.r then return { t.r, t.g, t.b } end
  return C.QUALITY[q] or C.QUALITY[1]
end
-- Container quality as a real value: the legacy API answers -1 (and C_Container nil) while the
-- item is not cached yet.
local function quality(v) v = R(v) if type(v) ~= "number" or v < 0 then return nil end return v end

-------------------------------------------------------------------------------
-- Bags and bank. Container IDs: bags 0..NUM_BAG_SLOTS (+ the reagent bag where it exists),
-- bank -1 plus the bank bags after the last carried bag.
-------------------------------------------------------------------------------
function C.BagIDs()
  local out = {}
  for b = 0, (_G.NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
  if (_G.NUM_REAGENTBAG_SLOTS or 0) > 0 then out[#out + 1] = (_G.NUM_BAG_SLOTS or 4) + 1 end
  return out
end
function C.BankIDs()
  local out = { _G.BANK_CONTAINER or -1 }
  local first = (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) + 1
  for i = 0, (_G.NUM_BANKBAGSLOTS or 6) - 1 do out[#out + 1] = first + i end
  return out
end

-- 0.9.5 phase 16 ("bank bag can't buy bag slots", Forever parity). What the game's own bank window offers to buy, read the way
-- this client offers it. The two clients differ (tests/clientapi): Classic Era buys bank BAG SLOTS (GetNumBankSlots, GetBankSlotCost,
-- PurchaseSlot, PLAYERBANKBAGSLOTS_CHANGED); WoW Forever 1.60.1 has none of those and buys bank TABS instead (C_Bank,
-- Enum.BankType.Character, BANK_TABS_CHANGED). Returns nil when neither exists, else
--   { mode = "slot" | "tab", bought, total, full, cost (nil when unknown), afford (nil when unknown), bankType (tabs only) }
function C.BankBuyInfo()
  local f = _G.GetNumBankSlots
  if f then
    local ok, n, full = pcall(f)
    n = ok and R(n) or nil
    if type(n) == "number" then
      local total = _G.NUM_BANKBAGSLOTS or 6
      full = (R(full) and true or false) or n >= total
      local cost
      if not full and _G.GetBankSlotCost then
        cost = R(pc(_G.GetBankSlotCost, n))
        if type(cost) ~= "number" or cost < 0 then cost = nil end
      end
      return { mode = "slot", bought = n, total = total, full = full, cost = cost }
    end
  end
  local B = _G.C_Bank
  local E = _G.Enum and _G.Enum.BankType
  local bt = E and E.Character
  if B and bt ~= nil and B.PurchaseBankTab and B.FetchNumPurchasedBankTabs then
    local n = R(pc(B.FetchNumPurchasedBankTabs, bt))
    if type(n) ~= "number" then return nil end
    local total = R(B.FetchMaxNumBankTabs and pc(B.FetchMaxNumBankTabs, bt))
    if type(total) ~= "number" then total = nil end
    local full = R(B.HasMaxBankTabs and pc(B.HasMaxBankTabs, bt))
    if full == nil then full = total ~= nil and n >= total end
    full = full and true or false
    local cost, afford
    if not full and B.FetchNextPurchasableBankTabData then
      local d = pc(B.FetchNextPurchasableBankTabData, bt)
      if type(d) == "table" then
        cost = R(d.tabCost)
        if type(cost) ~= "number" or cost < 0 then cost = nil end
        afford = R(d.canAfford)
      end
    end
    -- the game says when a tab cannot be bought right now (CanPurchaseBankTab); nothing to offer then
    if not full and B.CanPurchaseBankTab and R(pc(B.CanPurchaseBankTab, bt)) == false and afford ~= false then return nil end
    return { mode = "tab", bought = n, total = total, full = full, cost = cost, afford = afford, bankType = bt }
  end
  return nil
end
-- A bank bag container ID (C.BankIDs, after the main bank) -> its place 1..NUM_BANKBAGSLOTS; nil for the main bank, any other bag, and
-- on a client whose bank has tabs in place of bag slots (a tab is not a bag that can be taken off).
function C.BankBagIndex(bag)
  if not _G.GetNumBankSlots then return nil end
  local first = (_G.NUM_BAG_SLOTS or 4) + (_G.NUM_REAGENTBAG_SLOTS or 0) + 1
  local i = type(bag) == "number" and bag - first + 1 or nil
  if i and i >= 1 and i <= (_G.NUM_BANKBAGSLOTS or 6) then return i end
  return nil
end

function C.NumSlots(bag)
  local f = G("C_Container.GetContainerNumSlots") or _G.GetContainerNumSlots
  return R(pc(f, bag)) or 0
end

-- { itemID, count, quality, link, icon, bound, locked, noValue } or nil for an empty slot.
function C.SlotInfo(bag, slot)
  local f = G("C_Container.GetContainerItemInfo")
  if f then
    local t = pc(f, bag, slot)
    if type(t) ~= "table" then return nil end
    return { itemID = R(t.itemID), count = R(t.stackCount) or 1, quality = quality(t.quality), link = R(t.hyperlink),
             icon = R(t.iconFileID), bound = R(t.isBound), locked = R(t.isLocked), noValue = R(t.hasNoValue) }
  end
  f = _G.GetContainerItemInfo
  if not f then return nil end
  local r = { pcall(f, bag, slot) }
  if not r[1] or not r[2] then return nil end
  local link = R(r[8])
  return { itemID = R(r[11]) or C.ItemIDFromLink(link), count = R(r[3]) or 1, quality = quality(r[5]), link = link,
           icon = R(r[2]), locked = R(r[4]), noValue = R(r[10]) }
end

-- 0.5.4 safety rule: an item is a quest item ONLY when the game's own quest-info API says so.
-- Returns isQuest, questID, startsQuest (questID present and not yet active - the game's "bang").
-- No API in this client -> false (we never guess from item class or our own data).
function C.SlotQuest(bag, slot)
  local f = G("C_Container.GetContainerItemQuestInfo") or _G.GetContainerItemQuestInfo
  if not f then return false end
  local r = { pcall(f, bag, slot) }
  if not r[1] then return false end
  local isQuest, questID, active
  if type(r[2]) == "table" then isQuest, questID, active = R(r[2].isQuestItem), R(r[2].questID), R(r[2].isActive)
  else isQuest, questID, active = R(r[2]), R(r[3]), R(r[4]) end
  if questID == 0 then questID = nil end
  local q = (isQuest or questID) and true or false
  return q, questID, (q and questID ~= nil and not active) and true or false
end

-- 0.6.0: never while a spell waits for its target (see C.SpellTargeting): then this call would
-- be the protected "use the spell on this item" action and the game blocks the add-on.
function C.UseSlot(bag, slot)
  local f = G("C_Container.UseContainerItem") or _G.UseContainerItem
  if not f or C.SpellTargeting() then return false end
  return (pcall(f, bag, slot))
end
function C.PickupSlot(bag, slot)
  local f = G("C_Container.PickupContainerItem") or _G.PickupContainerItem
  if not f or C.SpellTargeting() then return false end
  return (pcall(f, bag, slot))
end
-- 0.8.1: the bag slot (inventory slot) a container sits in, or nil (the backpack and the bank's main slots have none)
function C.BagInvSlot(bag)
  if not bag or bag <= 0 then return nil end
  local CC = _G.C_Container
  local inv = CC and CC.ContainerIDToInventoryID and C.pc(CC.ContainerIDToInventoryID, bag) or C.pc(_G.ContainerIDToInventoryID, bag)
  return R(inv)
end
-- 0.8.1: pick an equipped bag up onto the cursor (the game's own call, as its bag bar does); never while a spell targets
function C.PickupBag(bag)
  local inv = C.BagInvSlot(bag)
  local f = _G.PickupBagFromSlot or (_G.C_Container and _G.C_Container.PickupBagFromSlot)
  if not (inv and f) or C.SpellTargeting() then return false end
  return (pcall(f, inv))
end
-- 0.8.1: free slots and the bag family (0 = a normal bag; a bit set = quiver 1, ammo pouch 2, soul bag 4, leatherworking 8,
-- herb 32, enchanting 64, engineering 128, keyring 256, gems 512, mining 1024), as the game reports them
function C.BagFree(bag)
  local f = G("C_Container.GetContainerNumFreeSlots") or _G.GetContainerNumFreeSlots
  if not f then return nil, nil end
  local ok, free, family = pcall(f, bag)
  if not ok then return nil, nil end
  return R(free), R(family)
end
function C.BagFamily(bag)
  if bag == 0 or bag == (_G.BANK_CONTAINER or -1) then return 0 end
  local _, family = C.BagFree(bag)
  return family or 0
end
-- 0.8.1: split a stack through the game's own call (the client keeps the count, charges and locks)
function C.SplitSlot(bag, slot, count)
  local f = G("C_Container.SplitContainerItem") or _G.SplitContainerItem
  if not f or C.SpellTargeting() or not (count and count > 0) then return false end
  return (pcall(f, bag, slot, count))
end
-- the client's own "split stack" modifier (Shift by default; players can change it)
function C.SplitModifier()
  if _G.IsModifiedClick then local ok, v = pcall(IsModifiedClick, "SPLITSTACK") if ok then return v and true or false end end
  return C.ShiftDown()
end
-- 0.5.9: put the item on the cursor into a bag (0 = backpack, 1-4 bags, -1 bank, 5-10 bank bags).
function C.PutInBag(bag)
  if bag == 0 and _G.PutItemInBackpack then return (pcall(PutItemInBackpack)) end
  if bag and bag > 0 then
    local CC = _G.C_Container
    local inv = CC and CC.ContainerIDToInventoryID and C.pc(CC.ContainerIDToInventoryID, bag) or C.pc(_G.ContainerIDToInventoryID, bag)
    if inv and _G.PutItemInBag then return (pcall(PutItemInBag, inv)) end
  end
  -- no bag slot to drop on (the bank's main slots): first free slot of that bag
  for slot = 1, C.NumSlots(bag) or 0 do
    local i = C.SlotInfo(bag, slot)
    if not (i and i.itemID) then return C.PickupSlot(bag, slot) end
  end
  return false
end
function C.CursorHasItem() return _G.CursorHasItem and CursorHasItem() and true or false end
-- 0.6.0: a spell (an enchant, a sharpening stone, ...) is waiting for the player to click its
-- target. While it is, picking up or using a bag item IS the targeting action, which only the
-- game's own click may do: Panoply Suite code never touches bag items then.
function C.SpellTargeting()
  local f = _G.SpellIsTargeting
  if not f then return false end
  local ok, v = pcall(f)
  return ok and v and true or false
end

-- The game's own sort where it exists (Forever). Era has none: the Bags module sorts itself.
function C.CanSortBags() return G("C_Container.SortBags") ~= nil end
function C.SortBags() local f = G("C_Container.SortBags") if not f then return false end return (pcall(f)) end
function C.SortBank() local f = G("C_Container.SortBankBags") if not f then return false end return (pcall(f)) end

-------------------------------------------------------------------------------
-- Merchant
-------------------------------------------------------------------------------
function C.MerchantShown() local m = _G.MerchantFrame return m and m.IsShown and m:IsShown() and true or false end
-- Buyback tab or a merchant without a sell list: do not sell anything.
function C.MerchantBuybackTab()
  local m = _G.MerchantFrame
  return m and m.selectedTab == 2 or false
end
function C.CanRepair() return pc(_G.CanMerchantRepair) and true or false end
function C.RepairCost()
  local cost, need = pc(_G.GetRepairAllCost)
  return R(cost) or 0, need and true or false
end
-- Guild-bank repairs: only where the API exists (Forever); off by default in settings.
function C.HasGuildRepair() return _G.CanGuildBankRepair ~= nil end
function C.CanGuildRepair()
  if not _G.CanGuildBankRepair or not (_G.IsInGuild and IsInGuild()) then return false end
  return pc(CanGuildBankRepair) and true or false
end
function C.RepairAll(guild) if not _G.RepairAllItems then return false end return (pcall(RepairAllItems, guild and true or false)) end

-------------------------------------------------------------------------------
-- Tooltips: one hook for item tooltips on both clients.
-------------------------------------------------------------------------------
function C.HookItemTooltip(fn)
  local TDP = _G.TooltipDataProcessor
  local itemType = G("Enum.TooltipDataType.Item")
  if TDP and TDP.AddTooltipPostCall and itemType ~= nil then
    pcall(TDP.AddTooltipPostCall, itemType, function(tt, data)
      local id = data and (R(data.id) or (data.hyperlink and C.ItemIDFromLink(data.hyperlink)))
      if id then pcall(fn, tt, id) end
    end)
    return "TooltipDataProcessor"
  end
  local GT = _G.GameTooltip
  if GT and GT.HookScript then
    local function onItem(tt)
      local _, link = pc(tt.GetItem, tt)
      local id = C.ItemIDFromLink(link)
      if id then pcall(fn, tt, id) end
    end
    pcall(GT.HookScript, GT, "OnTooltipSetItem", onItem)
    if _G.ItemRefTooltip and ItemRefTooltip.HookScript then pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", onItem) end
    return "OnTooltipSetItem"
  end
  return nil
end

function C.Hook(tbl, name, fn)
  if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
  if not _G.hooksecurefunc or type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
  return (pcall(hooksecurefunc, tbl, name, fn))
end

-------------------------------------------------------------------------------
-- World map and minimap
-------------------------------------------------------------------------------
function C.WorldMap() return _G.WorldMapFrame end
function C.WorldMapCanvas()
  local w = _G.WorldMapFrame
  local sc = w and w.ScrollContainer
  return sc and (sc.Child or (sc.GetCanvas and pc(sc.GetCanvas, sc))) or nil
end
function C.WorldMapID()
  local w = _G.WorldMapFrame
  if not (w and w.GetMapID) then return nil end
  return R(pc(w.GetMapID, w))
end
-- 0.6.1 world-map fix. Blizzard's map canvas (Blizzard_MapCanvas, Era 1.15.9 and Forever 1.60.1)
-- gives its pins ABSOLUTE frame levels from a pin frame-level manager that starts at 2000; the
-- explored-area art is one full-canvas pin at PIN_FRAME_LEVEL_MAP_EXPLORATION (about 2001). A layer
-- at "canvas level + 20" is therefore drawn UNDER the explored map art and cannot be seen. This
-- returns a level read from the map's own manager (read only, nothing is added or changed there):
--   "trail" 0.6.2: an explicit HIGH pin level (the super-tracked quest's): above the map art, fog,
--           highlights, towns, flight points, vignettes and quest blobs; under the group members
--           and the player arrow;
--   "pins"  our own pins, just above the trail (bonus objective level), still under the player;
--   "card"  above every pin.
-- Each list is tried in order; a type the client does not know answers the default level (2000,
-- under the art) and is skipped, so an older or different map falls back to a lower known level.
C.MAP_LEVEL_TYPES = {
  trail = { "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "PIN_FRAME_LEVEL_ACTIVE_QUEST", "PIN_FRAME_LEVEL_DIG_SITE", "PIN_FRAME_LEVEL_AREA_POI" },
  pins = { "PIN_FRAME_LEVEL_BONUS_OBJECTIVE", "PIN_FRAME_LEVEL_VEHICLE_BELOW_GROUP_MEMBER", "PIN_FRAME_LEVEL_ENCOUNTER", "PIN_FRAME_LEVEL_AREA_POI" },
}
-- 0.6.2: a floor under the world map's fade. The small Era map fades with the worldMapOpacity
-- setting, and other add-ons can fade WorldMapFrame further;
-- our trail and pins follow the map's alpha down to MAP_ALPHA_FLOOR and stop there, so they never
-- vanish while the map is still on screen. Only our own layers change (SetIgnoreParentAlpha on a frame
-- we created, never on a Blizzard frame).
C.MAP_ALPHA_FLOOR = 0.9
C.mapAlphaLayers = {}
function C.FloorMapAlpha(f)
  if not (f and f.SetAlpha) then return nil end
  C.mapAlphaLayers[f] = true
  local parent = f.GetParent and f:GetParent()
  local pa = 1
  if parent and parent.GetEffectiveAlpha then
    local ok, v = pcall(parent.GetEffectiveAlpha, parent)
    if ok and type(v) == "number" then pa = v end
  end
  local floor = C.MAP_ALPHA_FLOOR
  if pa < floor and f.SetIgnoreParentAlpha then
    pc(f.SetIgnoreParentAlpha, f, true)
    pc(f.SetAlpha, f, math.max(floor, pa))
    f.panoplyFloored = true
  elseif f.panoplyFloored then
    if f.SetIgnoreParentAlpha then pc(f.SetIgnoreParentAlpha, f, false) end
    pc(f.SetAlpha, f, 1)
    f.panoplyFloored = nil
  end
  return pa
end
function C.FloorAllMapAlpha() for f in pairs(C.mapAlphaLayers) do C.FloorMapAlpha(f) end end
-- re-apply when something fades the map (hooks only: Blizzard's code runs untouched)
function C.HookMapAlpha()
  if C.mapAlphaHooked then return end
  local wm = C.WorldMap()
  if not wm then return end
  C.mapAlphaHooked = true
  C.Hook(wm, "SetAlpha", C.FloorAllMapAlpha)
  if wm.ScrollContainer then C.Hook(wm.ScrollContainer, "SetAlpha", C.FloorAllMapAlpha) end
end

C.MAP_LEVEL_ART = { "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_FOG_OF_WAR", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" }
C.MAP_LEVEL_FALLBACK = 2600   -- no manager (an unknown map frame): still above where Blizzard puts map art
function C.WorldMapLevel(kind)
  local w = _G.WorldMapFrame
  local mgr = w and w.GetPinFrameLevelsManager and pc(w.GetPinFrameLevelsManager, w)
  local lvl
  if type(mgr) == "table" and mgr.GetValidFrameLevel then
    local art = 0
    for _, t in ipairs(C.MAP_LEVEL_ART) do
      local v = tonumber(R(pc(mgr.GetFrameLevelStart or mgr.GetValidFrameLevel, mgr, t)))
      if v and v > art then art = v end
    end
    local top = tonumber(R(pc(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_TOPMOST")))
    if kind == "card" then
      lvl = top and top + 20
    else
      for _, t in ipairs(C.MAP_LEVEL_TYPES[kind] or C.MAP_LEVEL_TYPES.pins) do
        local v = tonumber(R(pc(mgr.GetValidFrameLevel, mgr, t)))
        -- an unknown type answers the default level (2000), which is UNDER the art: skip it
        if v and v > art then lvl = v break end
      end
      lvl = lvl or (top and top + 1) or (art > 0 and art + 1) or nil
    end
  end
  if not lvl then
    local c = C.WorldMapCanvas()
    local base = c and c.GetFrameLevel and tonumber(R(pc(c.GetFrameLevel, c))) or 1
    lvl = math.max(base + 20, C.MAP_LEVEL_FALLBACK + (kind == "card" and 400 or kind == "pins" and 100 or 0))
  end
  -- our pins always sit above our trail, whatever the client's list answered
  if kind == "pins" then lvl = math.max(lvl, C.WorldMapLevel("trail") + 1) end
  return math.max(1, math.min(9800, lvl))
end
-- Put a frame at one of those levels (cheap; called on every redraw because another add-on can add
-- pin levels and shift Blizzard's numbers while the game runs).
function C.LiftOnWorldMap(f, kind)
  if not (f and f.SetFrameLevel) then return nil end
  local lvl = C.WorldMapLevel(kind)
  if not (f.GetFrameLevel and f:GetFrameLevel() == lvl) then pc(f.SetFrameLevel, f, lvl) end
  return lvl
end
function C.WorldMapCursor()
  local sc = _G.WorldMapFrame and WorldMapFrame.ScrollContainer
  if not (sc and sc.GetNormalizedCursorPosition) then return nil end
  local x, y = pc(sc.GetNormalizedCursorPosition, sc)
  return R(x), R(y)
end
function C.MinimapZoom() local m = _G.Minimap return m and m.GetZoom and R(pc(m.GetZoom, m)) or 0 end
-- 0.6.1: Forever hides the rotation setting during encounters (a secret value): read it through
-- Readable first, so a secret means "not rotating" instead of an error on compare.
function C.MinimapRotates()
  if not _G.GetCVar then return false end
  local v = R(pc(GetCVar, "rotateMinimap"))
  return v == "1" or v == 1 or v == true
end
function C.Indoors() return _G.IsIndoors and pc(IsIndoors) and true or false end
-- Minimap view diameter in yards by zoom level (same numbers on both clients).
C.MINIMAP_YARDS = { outdoor = { 466.67, 400, 333.33, 266.67, 200, 133.33 }, indoor = { 300, 240, 180, 120, 80, 50 } }
function C.MinimapRadius()
  local t = C.Indoors() and C.MINIMAP_YARDS.indoor or C.MINIMAP_YARDS.outdoor
  return (t[(C.MinimapZoom() or 0) + 1] or t[1]) / 2
end

-- 0.6.0: which of the game's gathering trackers is on (Find Minerals / Find Herbs).
-- Returns { ore = bool, herb = bool }, or nil when the client gives no way to read it.
-- Tried in order: C_Minimap.GetNumTrackingTypes + C_Minimap.GetTrackingInfo (table or multiple
-- returns), the global GetNumTrackingTypes + GetTrackingInfo, then GetTrackingTexture (Era's
-- single active tracker). Matched by spell ID, then icon file ID or path, then English name.
C.TRACK_SPELLS = { [2580] = "ore", [8388] = "ore", [2383] = "herb", [8387] = "herb" }
C.TRACK_ICONS = { [136025] = "ore", [133939] = "herb" }
C.TRACK_ICON_NAMES = { spell_nature_earthquake = "ore", inv_misc_flower_02 = "herb" }
C.TRACK_NAMES = { ["Find Minerals"] = "ore", ["Find Herbs"] = "herb" }
local function trackKind(name, tex, spellID)
  spellID, tex, name = R(spellID), R(tex), R(name)
  if spellID and C.TRACK_SPELLS[spellID] then return C.TRACK_SPELLS[spellID] end
  if type(tex) == "number" and C.TRACK_ICONS[tex] then return C.TRACK_ICONS[tex] end
  if type(tex) == "string" then
    local base = tex:lower():gsub("\\", "/"):match("([^/]+)$") or ""
    base = base:gsub("%.blp$", "")
    if C.TRACK_ICON_NAMES[base] then return C.TRACK_ICON_NAMES[base] end
  end
  if type(name) == "string" and C.TRACK_NAMES[name] then return C.TRACK_NAMES[name] end
  return nil
end
C.TrackKind = trackKind
function C.GatherTracking()
  local num = G("C_Minimap.GetNumTrackingTypes") or _G.GetNumTrackingTypes
  local info = (G("C_Minimap.GetNumTrackingTypes") and G("C_Minimap.GetTrackingInfo")) or _G.GetTrackingInfo
  local n = num and info and pc(num)
  if type(n) == "number" then
    local out = { ore = false, herb = false }
    for i = 1, n do
      local ok, a, tex, active, _, _, spellID = pcall(info, i)
      if ok then
        local name = a
        if type(a) == "table" then name, tex, active, spellID = a.name, a.texture, a.active, a.spellID end
        local k = trackKind(name, tex, spellID)
        if k and R(active) then out[k] = true end
      end
    end
    return out
  end
  if _G.GetTrackingTexture then
    local ok, tex = pcall(GetTrackingTexture)
    if not ok then return nil end
    local k = trackKind(nil, tex, nil)
    return { ore = k == "ore", herb = k == "herb" }
  end
  return nil
end

-------------------------------------------------------------------------------
-- 0.6.0: current skill and maximum for the profession window. Reads the open trade skill
-- (GetTradeSkillLine), the craft window (GetCraftDisplaySkillLine, Enchanting on Era) or, when
-- neither is open, the skill list (GetSkillLineInfo). Returns { name, rank, max, mod, src } or nil.
-- mod = a temporary bonus (racial, item or buff) when the client gives one, else 0.
-------------------------------------------------------------------------------
local function num(v) v = R(v) return type(v) == "number" and v or tonumber(v) end
local function skillRec(name, rank, max, mod, src)
  rank, max = num(rank), num(max)
  if not (rank and max and max > 0) then return nil end
  return { name = R(name), rank = rank, max = max, mod = num(mod) or 0, src = src }
end
function C.ProfSkillLine(prof, craft)
  local function try(fn, src)
    if not fn then return nil end
    local ok, n, rank, max, mod = pcall(fn)
    if not ok or not n or n == "" or n == "UNKNOWN" then return nil end
    if prof and R(n) ~= prof then return nil end
    return skillRec(n, rank, max, mod, src)
  end
  -- WoW Forever's profession frame (C_TradeSkillUI)
  local base = not craft and G("C_TradeSkillUI.GetBaseProfessionInfo")
  if base then
    local ok, t = pcall(base)
    if ok and type(t) == "table" and t.professionName and (not prof or R(t.professionName) == prof) then
      local r = skillRec(t.professionName, t.skillLevel, t.maxSkillLevel, t.skillModifier, "C_TradeSkillUI")
      if r then return r end
    end
  end
  local order = craft and { { _G.GetCraftDisplaySkillLine, "craft" }, { _G.GetTradeSkillLine, "trade" } }
    or { { _G.GetTradeSkillLine, "trade" }, { _G.GetCraftDisplaySkillLine, "craft" } }
  for _, o in ipairs(order) do local r = try(o[1], o[2]) if r then return r end end
  -- 0.6.1: Forever 1.60.1 has no GetNumSkillLines/GetSkillLineInfo globals, only C_SkillInfo
  -- (SkillLineAttributes table: name, isHeader, rank, tempPoints, modifier, maxRank)
  local cn, ci = G("C_SkillInfo.GetNumSkillLines"), G("C_SkillInfo.GetSkillLineInfo")
  if prof and cn and ci then
    local okN, n = pcall(cn)
    for i = 1, (okN and tonumber(R(n))) or 0 do
      local ok, t = pcall(ci, i)
      if ok and type(t) == "table" and not R(t.isHeader) and R(t.name) == prof then
        local r = skillRec(R(t.name), R(t.rank), R(t.maxRank), (num(R(t.tempPoints)) or 0) + (num(R(t.modifier)) or 0), "skills")
        if r then return r end
      end
    end
  end
  if prof and _G.GetNumSkillLines and _G.GetSkillLineInfo then
    local okN, n = pcall(GetNumSkillLines)
    for i = 1, (okN and tonumber(n)) or 0 do
      local ok, name, header, _, rank, temp, mod, max = pcall(GetSkillLineInfo, i)
      if ok and not header and R(name) == prof then
        return skillRec(name, rank, max, (num(temp) or 0) + (num(mod) or 0), "skills")
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Spells and loot
-------------------------------------------------------------------------------
function C.SpellName(id)
  local f = G("C_Spell.GetSpellInfo")
  if f then local t = pc(f, id) if type(t) == "table" then return R(t.name) end end
  if _G.GetSpellInfo then return R(pc(GetSpellInfo, id)) end
  return nil
end
function C.IsFishingLoot() return _G.IsFishingLoot and pc(IsFishingLoot) and true or false end
function C.TooltipTitle()
  local l = _G.GameTooltipTextLeft1
  return l and l.GetText and R(pc(l.GetText, l)) or nil
end

-------------------------------------------------------------------------------
-- Trade skill details (for the profession window module)
-- Returns a list of { index, recipeID, name, difficulty, numAvailable, itemID, link, icon,
-- reagents = { { itemID, name, need, have, icon } } }, plus the window kind.
-------------------------------------------------------------------------------
local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local function craftDetails()
  local out = {}
  local cat
  for i = 1, pc(GetNumCrafts) or 0 do
    local name, _, kind, avail = pc(GetCraftInfo, i)
    if name and kind == "header" then cat = name end   -- 0.6.0: the game's own category rows, when it has them
    if name and kind ~= "header" then
      local row = { index = i, name = name, difficulty = kind, numAvailable = avail or 0, reagents = {}, craft = true, category = cat }
      row.icon = pc(_G.GetCraftIcon, i)
      row.link = pc(_G.GetCraftItemLink, i)   -- 0.5.9.2: kept for the tooltip (an enchant/spell link)
      for j = 1, pc(_G.GetCraftNumReagents, i) or 0 do
        local rn, rt, need, have = pc(_G.GetCraftReagentInfo, i, j)
        local rl = pc(_G.GetCraftReagentItemLink, i, j)
        row.reagents[#row.reagents + 1] = { itemID = C.ItemIDFromLink(rl), link = rl, name = rn, icon = rt, need = need or 1, have = have }
      end
      out[#out + 1] = row
    end
  end
  return out, "Craft"
end
-- 0.7.1 (Tailoring "All" missed Trade Goods): the Era game only lists what its own window shows.
-- A header it has collapsed (its "All" collapse button, or a group closed by hand) still lists
-- as a row but its recipes do not, and its own subclass / slot dropdowns, search text and
-- "Have materials" box leave rows out too. Everything Panoply Suite derived from that list ("All",
-- the counts, the tabs) was missing those recipes; picking "Trade Goods" in the game's dropdown
-- reopened the group, so they "came back" only there. Before reading, open the whole book:
-- expand collapsed headers (last first, so the indexes still to visit do not move) and clear
-- a game filter only when the game says one is set. C functions only (no Blizzard Lua: taint),
-- each feature-detected and pcall'd. Once the list is whole the next read changes nothing, so
-- the TRADE_SKILL_UPDATE this causes cannot loop. keepFilters: the game's own window is in view
-- (the "Blizzard" button), so its dropdowns / search / "Have materials" stay the player's; only
-- the collapsed groups are opened.
local function wholeTradeList(keepFilters)
  local changed = false
  local function f(n) local v = _G[n] return type(v) == "function" and v or nil end
  if keepFilters then
  elseif f("GetTradeSkillSubClassFilter") and f("SetTradeSkillSubClassFilter") and pc(GetTradeSkillSubClassFilter, 0) == false then
    pc(SetTradeSkillSubClassFilter, 0, 1, 1); changed = true
  end
  if keepFilters then
  elseif f("GetTradeSkillInvSlotFilter") and f("SetTradeSkillInvSlotFilter") and pc(GetTradeSkillInvSlotFilter, 0) == false then
    pc(SetTradeSkillInvSlotFilter, 0, 1, 1); changed = true
  end
  if not keepFilters and f("GetTradeSkillItemNameFilter") and f("SetTradeSkillItemNameFilter") then
    local t = pc(GetTradeSkillItemNameFilter)
    if type(t) == "string" and t ~= "" then pc(SetTradeSkillItemNameFilter, ""); changed = true end
  end
  local cb = _G.TradeSkillFrameAvailableFilterCheckButton
  if not keepFilters and f("TradeSkillOnlyShowMakeable") and cb and cb.GetChecked and pc(cb.GetChecked, cb) then
    pc(TradeSkillOnlyShowMakeable, false)
    if cb.SetChecked then pc(cb.SetChecked, cb, false) end
    changed = true
  end
  if f("ExpandTradeSkillSubClass") and f("GetNumTradeSkills") and f("GetTradeSkillInfo") then
    for i = pc(GetNumTradeSkills) or 0, 1, -1 do
      local name, kind, _, expanded = pc(GetTradeSkillInfo, i)
      if name and kind == "header" and expanded == false then pc(ExpandTradeSkillSubClass, i); changed = true end
    end
  end
  return changed
end
local function wholeCraftList(keepFilters)
  local changed = false
  local cb = _G.CraftFrameAvailableFilterCheckButton
  if not keepFilters and type(_G.CraftOnlyShowMakeable) == "function" and cb and cb.GetChecked and pc(cb.GetChecked, cb) then
    pc(CraftOnlyShowMakeable, false)
    if cb.SetChecked then pc(cb.SetChecked, cb, false) end
    changed = true
  end
  if type(_G.ExpandCraftSkillLine) == "function" then
    for i = pc(GetNumCrafts) or 0, 1, -1 do
      local name, _, kind, _, expanded = pc(GetCraftInfo, i)
      if name and kind == "header" and expanded == false then pc(ExpandCraftSkillLine, i); changed = true end
    end
  end
  return changed
end
C.WholeTradeList, C.WholeCraftList = wholeTradeList, wholeCraftList
-- Forever (and Midnight) can hide GetRecipeInfo().numAvailable as a secret value;
-- Readable() then returns nil and we used to treat that as 0. Make then forced the
-- count to 1 even when the player typed a higher number (the qty box still showed,
-- because canRepeat was true). GetCraftableCount is the dedicated readable count.
local function craftableMax(recipeID, infoAvailable, rowAvailable)
  local n = tonumber(R(infoAvailable)) or tonumber(rowAvailable)
  if (not n or n < 1) and recipeID then
    local gcc = G("C_TradeSkillUI.GetCraftableCount")
    if gcc then
      local c = tonumber(R(pc(gcc, recipeID)))
      if c ~= nil then return math.max(0, math.floor(c)) end
    end
  end
  return n or 0
end
-- preferCraft (0.5.9): the enchanting window (CRAFT_SHOW) is the open one, read it first.
function C.TradeSkillDetails(preferCraft, keepFilters)
  if preferCraft and _G.GetNumCrafts and _G.GetCraftInfo and (pc(GetNumCrafts) or 0) > 0 then wholeCraftList(keepFilters) return craftDetails() end
  local out = {}
  local ids, info, schem = G("C_TradeSkillUI.GetAllRecipeIDs"), G("C_TradeSkillUI.GetRecipeInfo"), G("C_TradeSkillUI.GetRecipeSchematic")
  local catInfo = G("C_TradeSkillUI.GetCategoryInfo")
  if ids and info then
    local list = pc(ids)
    if type(list) == "table" and #list > 0 then
      for i, rid in ipairs(list) do
        local r = pc(info, rid)
        if type(r) == "table" and r.learned ~= false then
          local row = { index = i, recipeID = rid, name = R(r.name), difficulty = DIFF[R(r.relativeDifficulty)] or R(r.difficulty),
                        numAvailable = craftableMax(rid, r.numAvailable), icon = R(r.icon), reagents = {},
                        noRepeat = (R(r.isEnchantingRecipe) or R(r.isSalvageRecipe)) and true or nil }
          -- 0.6.0: the recipe's category (the game's own list headers: Armor, Weapons, Materials ...)
          local cid = R(r.categoryID)
          if cid and catInfo then
            local ci = pc(catInfo, cid)
            row.category = type(ci) == "table" and R(ci.name) or nil
          end
          local s = schem and pc(schem, rid, false)
          if type(s) == "table" then
            row.itemID = R(s.outputItemID)
            -- 0.9.7 in-game hotfix (WoW Forever: every material of a recipe shown twice). The game's list of material slots was
            -- taken as it came. Now a material is listed ONCE per recipe however many slots name it (the larger count is kept: no
            -- recipe in our own WoW Forever recipe facts needs one material in two slots), and a slot the game marks as not a plain
            -- material (optional, finishing: Enum.CraftingReagentType, where the client has it) or as not required is left out.
            -- UNVERIFIED in the real client: which of the two WoW Forever sends.
            local basic = G("Enum.CraftingReagentType.Basic")
            local byItem = {}
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
              local rg = type(slot) == "table" and slot.reagents and slot.reagents[1]
              local id = rg and R(rg.itemID)
              local kind = type(slot) == "table" and R(slot.reagentType)
              local plain = (basic == nil or kind == nil or kind == basic) and R(slot.required) ~= false
              if id and plain then
                local need = tonumber(R(slot.quantityRequired)) or 1
                local e = byItem[id]
                if e then e.need = math.max(e.need, need)
                else
                  e = { itemID = id, need = need }
                  byItem[id] = e
                  row.reagents[#row.reagents + 1] = e
                end
              end
            end
          end
          out[#out + 1] = row
        end
      end
      return out, "C_TradeSkillUI"
    end
  end
  if _G.GetNumTradeSkills and _G.GetTradeSkillInfo and (pc(GetNumTradeSkills) or 0) > 0 then
    wholeTradeList(keepFilters)
    local cat
    for i = 1, pc(GetNumTradeSkills) or 0 do
      local name, kind, avail = pc(GetTradeSkillInfo, i)
      if name and kind == "header" then cat = name end   -- 0.6.0: header rows (Armor, Weapons, Materials ...) = categories
      if name and kind ~= "header" and kind ~= "subheader" then
        local row = { index = i, name = name, difficulty = kind, numAvailable = avail or 0, reagents = {}, category = cat }
        row.link = pc(_G.GetTradeSkillItemLink, i); row.itemID = C.ItemIDFromLink(row.link)
        row.icon = pc(_G.GetTradeSkillIcon, i)
        for j = 1, pc(_G.GetTradeSkillNumReagents, i) or 0 do
          local rn, rt, need, have = pc(_G.GetTradeSkillReagentInfo, i, j)
          local rl = pc(_G.GetTradeSkillReagentItemLink, i, j)
          row.reagents[#row.reagents + 1] = { itemID = C.ItemIDFromLink(rl), link = rl, name = rn, icon = rt, need = need or 1, have = have }
        end
        out[#out + 1] = row
      end
    end
    return out, "TradeSkill"
  end
  if _G.GetNumCrafts and _G.GetCraftInfo and (pc(GetNumCrafts) or 0) > 0 then wholeCraftList(keepFilters) return craftDetails() end
  return out, nil
end

-- Select a recipe in the game's own window and make it.
function C.SelectRecipe(row, kind)
  if kind == "C_TradeSkillUI" then
    local f = G("C_TradeSkillUI.OpenRecipe") or G("C_TradeSkillUI.SetRecipeItemNameFilter")
    if G("C_TradeSkillUI.OpenRecipe") then return (pcall(C_TradeSkillUI.OpenRecipe, row.recipeID)) end
    return false
  -- 0.6.0 (taint fix): only the game's C functions. Calling Blizzard's own Lua
  -- (CraftFrame_SetSelection / TradeSkillFrame_SetSelection) from add-on code wrote add-on
  -- ("tainted") values into the game's profession window state.
  elseif kind == "Craft" then
    if _G.SelectCraft then return (pcall(SelectCraft, row.index)) end
  else
    if _G.SelectTradeSkill then return (pcall(SelectTradeSkill, row.index)) end
  end
  return false
end
-- 0.8.1: the game's list can move under us (a group opened or closed, a skill-up, a new recipe), so a
-- row's index is only a hint: find the recipe by name in the game's own list again before using it.
local function liveIndex(row, kind)
  if kind == "Craft" and _G.GetCraftInfo then
    if pc(_G.GetCraftInfo, row.index) == row.name then return row.index end
    for i = 1, pc(_G.GetNumCrafts) or 0 do if pc(_G.GetCraftInfo, i) == row.name then return i end end
  elseif kind == "TradeSkill" and _G.GetTradeSkillInfo then
    if pc(_G.GetTradeSkillInfo, row.index) == row.name then return row.index end
    for i = 1, pc(_G.GetNumTradeSkills) or 0 do if pc(_G.GetTradeSkillInfo, i) == row.name then return i end end
  end
  return row.index
end
C.LiveRecipeIndex = liveIndex
-- 0.8.1 ("Make All does not work", "no way to make a certain number"): can this recipe be made more than once
-- in one go, and how many do the materials allow right now? Returns { canRepeat, max, why }.
--   Craft (Era enchanting): DoCraft(index) takes no count, one enchant per click, and each one asks for its own
--   item: not repeatable. TradeSkill: DoTradeSkill(index, count); the count the game itself shows (numAvailable)
--   is read live, and a recipe with a cooldown (transmutes, Mooncloth) makes one per cooldown. C_TradeSkillUI
--   (Forever): CraftRecipe(id, count); enchanting and salvage recipes are one at a time.
function C.RecipeRepeat(row, kind)
  if not row then return { canRepeat = false, max = 0, why = "no recipe" } end
  if kind == "Craft" or row.craft then
    return { canRepeat = false, max = 1, why = "The game makes enchants one at a time." }
  end
  if kind == "C_TradeSkillUI" then
    local info = G("C_TradeSkillUI.GetRecipeInfo")
    local r = info and row.recipeID and pc(info, row.recipeID)
    if type(r) ~= "table" then return { canRepeat = not row.noRepeat, max = craftableMax(row.recipeID, nil, row.numAvailable), why = row.noRepeat and "One at a time." or nil } end
    local max = craftableMax(row.recipeID, r.numAvailable, row.numAvailable)
    if R(r.isEnchantingRecipe) or R(r.isSalvageRecipe) or row.noRepeat then return { canRepeat = false, max = math.min(1, max), why = "The game makes this one at a time." } end
    if (tonumber(R(r.cooldown)) or 0) > 0 then return { canRepeat = false, max = math.min(1, max), why = "On cooldown." } end
    return { canRepeat = true, max = max }
  end
  local idx = liveIndex(row, kind)
  local _, _, avail = pc(_G.GetTradeSkillInfo or function() end, idx)
  local max = tonumber(avail) or tonumber(row.numAvailable) or 0
  if type(_G.GetTradeSkillCooldown) == "function" and pc(_G.GetTradeSkillCooldown, idx) then
    return { canRepeat = false, max = math.min(1, max), why = "This recipe has a cooldown: one per cooldown." }
  end
  return { canRepeat = true, max = max }
end
-- Returns true, or false and why (0.7.3.1: the caller tells the player; it used to fail without a word).
-- 0.8.1: the recipe is found again by name; the count is held to what the materials allow (and to 1 where the game
-- cannot repeat); enchanting (DoCraft) has no count at all.
-- 0.8.2: when the live count is hidden (max is 0) but the recipe can repeat, keep the caller's number instead of
-- forcing 1. That is what made the qty box look like it worked while Make still crafted one.
function C.MakeRecipe(row, kind, n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local rep = C.RecipeRepeat(row, kind)
  if not rep.canRepeat then n = 1 elseif rep.max >= 1 then n = math.min(n, rep.max) end
  local f, a, b
  if kind == "C_TradeSkillUI" then f, a, b = G("C_TradeSkillUI.CraftRecipe"), row.recipeID, n
  elseif kind == "Craft" then f, a = _G.DoCraft, liveIndex(row, kind)
  else f, a, b = _G.DoTradeSkill, liveIndex(row, kind), n end
  if type(f) ~= "function" then return false, "this game has no " .. (kind == "Craft" and "DoCraft" or kind == "C_TradeSkillUI" and "CraftRecipe" or "DoTradeSkill") end
  if a == nil then return false, "no recipe index" end
  -- the game's own enchanting window selects the recipe (SelectCraft) and then makes the selected one
  -- (DoCraft(GetCraftSelectionIndex())): do the same, with the game's C functions only (no Blizzard Lua)
  if kind == "Craft" and type(_G.SelectCraft) == "function" then pcall(_G.SelectCraft, a) end
  local ok, err
  if b ~= nil then ok, err = pcall(f, a, b) else ok, err = pcall(f, a) end
  if not ok then return false, tostring(err) end
  return true, nil, n
end
-- 0.5.9: end the open profession session (Craft = the enchanting window in Era).
function C.CloseProfession(kind)
  if kind == "Craft" and _G.CloseCraft then return (pcall(CloseCraft)) end
  local f = G("C_TradeSkillUI.CloseTradeSkill") or _G.CloseTradeSkill
  if f then return (pcall(f)) end
  if _G.CloseCraft then return (pcall(CloseCraft)) end
  return false
end
function C.TradeSkillFrame()
  for _, n in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[n]
    if f and f.IsShown and f:IsShown() then return f, n end
  end
  return nil
end

-- Resize bounds: SetResizeBounds (newer clients) or SetMinResize/SetMaxResize (older).
function C.SetResizeBounds(f, minW, minH, maxW, maxH)
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, minW, minH, maxW, maxH) return "bounds" end
  if f.SetMinResize then pcall(f.SetMinResize, f, minW, minH) end
  if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
  return "minmax"
end

-------------------------------------------------------------------------------
-- 0.5.7: dropping quests and destroying their quest items (Replan clean-up). Feature-detected;
-- only ever called from a Confirm click, out of combat.
-------------------------------------------------------------------------------
-- Abandon one quest. Forever: C_QuestLog.SetSelectedQuest/SetAbandonQuest/AbandonQuest;
-- Era: SelectQuestLogEntry(index) + SetAbandonQuest + AbandonQuest.
function C.AbandonQuest(questID)
  if not questID or C.InCombat() then return false end
  local sel, setA, ab = G("C_QuestLog.SetSelectedQuest"), G("C_QuestLog.SetAbandonQuest"), G("C_QuestLog.AbandonQuest")
  if sel and setA and ab then
    return pcall(sel, questID) and pcall(setA) and pcall(ab) and true or false
  end
  local idx = C.LogIndexForQuest(questID)
  if idx and _G.SelectQuestLogEntry and _G.SetAbandonQuest and _G.AbandonQuest then
    return pcall(SelectQuestLogEntry, idx) and pcall(SetAbandonQuest) and pcall(AbandonQuest) and true or false
  end
  return false
end

function C.CanDeleteItems()
  return _G.DeleteCursorItem ~= nil and (G("C_Container.PickupContainerItem") or _G.PickupContainerItem) ~= nil
end

-- Pick up the item in (bag, slot) and destroy it. Checks the slot still holds itemID first,
-- and that it really went (the client may refuse); anything left on the cursor is put back.
function C.DeleteSlot(bag, slot, itemID)
  if C.InCombat() or not C.CanDeleteItems() then return false end
  local s = C.SlotInfo(bag, slot)
  if not s or s.itemID ~= itemID then return false end
  if C.CursorHasItem() and _G.ClearCursor then pcall(ClearCursor) end
  if C.CursorHasItem() then return false end
  C.PickupSlot(bag, slot)
  if not C.CursorHasItem() then return false end
  local ok = pcall(DeleteCursorItem)
  if C.CursorHasItem() then if _G.ClearCursor then pcall(ClearCursor) end return false end
  local after = C.SlotInfo(bag, slot)
  return ok and not (after and after.itemID == itemID) or false
end

-------------------------------------------------------------------------------
-- 0.5.7: death and the corpse run.
-------------------------------------------------------------------------------
function C.IsGhost()
  local f = _G.UnitIsGhost
  return f and pc(f, "player") and true or false
end
function C.IsDead()
  local f = _G.UnitIsDeadOrGhost or _G.UnitIsDead
  return f and pc(f, "player") and true or false
end

-- Where the corpse is: map, x, y (0-1). Tries each map in `maps` (player's map first, then the
-- map we died on, then their parents). Forever/modern: C_DeathInfo.GetCorpseMapPosition(mapID);
-- Era: the legacy GetCorpseMapPosition(), which answers for the world map's current map.
function C.CorpsePos(maps)
  local f = G("C_DeathInfo.GetCorpseMapPosition")
  if f then
    local seen = {}
    for _, m in ipairs(maps or {}) do
      local cur, guard = m, 0
      while cur and cur > 0 and not seen[cur] and guard < 6 do
        seen[cur] = true
        local v = pc(f, cur)
        local x, y
        if type(v) == "table" then
          if v.GetXY then x, y = v:GetXY() else x, y = v.x, v.y end
        end
        x, y = R(x), R(y)
        if x and y and (x > 0 or y > 0) then return cur, x, y end
        local info = pc(G("C_Map.GetMapInfo"), cur)
        cur = type(info) == "table" and R(info.parentMapID) or nil
        guard = guard + 1
      end
    end
    return nil
  end
  local legacy = _G.GetCorpseMapPosition
  if legacy then
    local ok, x, y = pcall(legacy)
    x, y = R(x), R(y)
    if ok and x and y and (x > 0 or y > 0) then
      local wm = C.WorldMap()
      local m = (wm and wm:IsShown() and C.WorldMapID()) or (maps and maps[1])
      return m, x, y
    end
  end
  return nil
end
