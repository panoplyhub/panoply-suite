-- Merchant module, 0.8.4: restock and fast loot. Both are OFF until the player turns them on (Miscellaneous page gear).
--
-- RESTOCK. The player keeps a short list of things to carry and how many of each (PanoplySuiteCharDB.restock, a new key:
-- { [itemID] = count }). At a vendor that sells one of them, Panoply Suite buys what is missing, up to that number and never
-- over it, and says what it bought. It buys only with gold (never an item that costs tokens or honour), only what the
-- character can pay for, never in combat, and not while Shift is held. How the list is filled:
--   * Alt-click an item in the vendor's window: keep one full stack of it; Alt-click it again to take it off the list;
--   * /panoply restock 40 [item link]: keep 40; /panoply restock 0 [item link]: take it off; /panoply restock: the list.
-- Buying is the game's own "buy from this vendor" call, the same one a click on the item makes; nothing here casts,
-- targets or moves, and nothing happens away from an open vendor window.
--
-- FAST LOOT. With the game's own auto loot on, a corpse's items are picked up the moment the loot window has them,
-- instead of one by one as the window draws. It only asks for the slots the game was about to loot anyway; with auto loot
-- off (or its key held to switch it off) or with a master looter, the game's own window is left alone, and a slot the game
-- has locked (someone else's roll) is never asked for.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Mer = Panoply.Merchant
local Re = {}
Panoply.Restock = Re
Mer.Restock = Re

Re.BUY_DELAY = 0.2     -- seconds between purchases (the server drops very fast buying, like very fast selling)
Re.MAX_BUYS = 40       -- purchases in one visit, whatever the list says
Re.MAX_COUNT = 2000    -- the most of one item the list may ask for
Re.REPORT_DELAY = 0.5  -- after the last purchase, before the bags are counted for the chat line
Re.LOOT_GAP = 0.3      -- a loot window is emptied at most once this often

Panoply.defaults.account.restock = false
Panoply.defaults.account.fastLoot = false

local function first(path, ...)
  local ok, a, b, c, d, e, f, g, h = C.Call(path, path, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h
end
local function R(v) return C.Readable(v) end

-------------------------------------------------------------------------------
-- The list
-------------------------------------------------------------------------------
function Re:List()
  local c = Panoply.cdb
  if not c then return {} end
  if type(c.restock) ~= "table" then c.restock = {} end
  return c.restock
end

function Re:On() return Mer.active and Panoply.db ~= nil and Panoply.db.restock == true end

-- Keep `count` of an item (a link or an id); 0 or less takes it off the list. Returns the count now kept, or nil.
function Re:Set(item, count)
  local id = C.ItemIDFromLink(item)
  if not id or not Panoply.cdb then return nil end
  count = math.floor(tonumber(count) or 0)
  local list = self:List()
  if count <= 0 then list[id] = nil count = 0 else list[id] = math.min(count, self.MAX_COUNT) count = list[id] end
  Panoply:Fire("RESTOCK_CHANGED", id, count)
  return count
end

local function itemName(id)
  local ii = C.ItemInfo(id)
  return ii and (ii.link or ii.name) or ("item " .. id)
end

-- The list as rows { id, name, want, have }, by name.
function Re:Rows()
  local out = {}
  for id, want in pairs(self:List()) do
    local ii = C.ItemInfo(id)
    out[#out + 1] = { id = id, name = ii and ii.name or ("item " .. id), want = want, have = C.ItemCount(id) or 0 }
  end
  table.sort(out, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
  return out
end

-- What the gear and the Miscellaneous page say about the list.
function Re:Lines()
  local rows = self:Rows()
  if #rows == 0 then
    return { "Nothing on the list yet. At a vendor, Alt-click an item to keep one stack of it, or type /panoply restock 40 and Shift-click the item." }
  end
  local out = {}
  for _, r in ipairs(rows) do out[#out + 1] = ("%s: keep %d (you carry %d)"):format(r.name, r.want, r.have) end
  return out
end

function Re:Summary()
  local n = 0
  for _ in pairs(self:List()) do n = n + 1 end
  if not (Panoply.db and Panoply.db.restock) then return n == 0 and "Restock is off" or ("Restock is off (%d on the list)"):format(n) end
  if n == 0 then return "Restock is on, the list is empty" end
  return n == 1 and "Restock: 1 item on the list" or ("Restock: %d items on the list"):format(n)
end

-------------------------------------------------------------------------------
-- What the open vendor sells
-------------------------------------------------------------------------------
-- { index, id, price (copper for one purchase), per (items in one purchase), stock (nil = no limit), maxStack, tokens }
function Re.MerchantItems()
  local out = {}
  local n = tonumber(R(first("GetMerchantNumItems"))) or 0
  local info = C.G("C_MerchantFrame.GetItemInfo")
  for i = 1, n do
    local price, per, stock, buyable, tokens
    if type(info) == "function" then
      local ok, t = pcall(info, i)
      if ok and type(t) == "table" then
        price, per, stock, buyable, tokens = R(t.price), R(t.stackCount), R(t.numAvailable), R(t.isPurchasable), R(t.hasExtendedCost)
      end
    end
    if price == nil then
      local _, _, p, q, avail, can, _, ext = first("GetMerchantItemInfo", i)
      price, per, stock, buyable, tokens = R(p), R(q), R(avail), R(can), R(ext)
    end
    local id = C.ItemIDFromLink(R(first("GetMerchantItemLink", i))) or tonumber(R(first("GetMerchantItemID", i)))
    if id and type(price) == "number" and buyable ~= false then
      stock = tonumber(stock)
      out[#out + 1] = { index = i, id = id, price = price, per = math.max(1, tonumber(per) or 1),
        stock = (stock and stock >= 0) and stock or nil, maxStack = tonumber(R(first("GetMerchantItemMaxStack", i))) or 1,
        tokens = tokens and true or false }
    end
  end
  return out
end

-- The purchases a visit would make: { { index, id, quantity (the number handed to the game's buy call; nil for a bundle),
-- items, cost } }. An item sold one at a time is bought in calls of up to its largest stack; an item sold in bundles (200
-- arrows) is bought a bundle at a time, with the game's plain "buy this" call and no number (what a right-click on it
-- does), and only whole bundles that do not go over the number asked for.
function Re:Plan(money)
  local list = self:List()
  local jobs, left = {}, money or C.Money()
  for _, m in ipairs(Re.MerchantItems()) do
    local want = list[m.id]
    if want and not m.tokens and m.price >= 0 then
      local need = want - (C.ItemCount(m.id) or 0)
      local stock = m.stock
      while need > 0 and #jobs < self.MAX_BUYS do
        local quantity, items, cost
        if m.per > 1 then
          -- a bundle is all or nothing
          if need < m.per or (stock and stock < 1) or m.price > left then break end
          quantity, items, cost = nil, m.per, m.price
          if stock then stock = stock - 1 end
        else
          items = math.min(need, math.max(1, m.maxStack), stock or need)
          -- not enough gold for the whole call: as many as the gold allows
          if m.price > 0 then items = math.min(items, math.floor(left / m.price)) end
          if items < 1 then break end
          quantity, cost = items, m.price * items
          if stock then stock = stock - items end
        end
        jobs[#jobs + 1] = { index = m.index, id = m.id, quantity = quantity, items = items, cost = cost, each = m.price / m.per }
        left = left - cost
        need = need - items
      end
    end
  end
  return jobs
end

function Re:CanBuyNow()
  return C.MerchantShown() and not C.InCombat() and not C.ShiftDown()
end

-- What a visit really brought: counted from the bags (a purchase the game refused, with full bags for one, is not in it).
function Re:Report(s)
  if not s or s.reported then return nil end
  s.reported = true
  local parts, spent, bought = {}, 0, 0
  for id, had in pairs(s.before) do
    local n = (C.ItemCount(id) or 0) - had
    if n > 0 then
      parts[#parts + 1] = ("%d %s"):format(n, itemName(id))
      spent = spent + n * (s.each[id] or 0)
      bought = bought + n
    end
  end
  s.bought, s.spent = bought, math.floor(spent + 0.5)
  if bought == 0 then return nil end
  table.sort(parts)
  local msg = ("Restocked %s for %s."):format(table.concat(parts, ", "), C.FormatMoney(s.spent))
  if s.stopped then msg = msg .. " Stopped early: " .. s.stopped .. "." end
  Panoply:Print(msg)
  self.lastSummary = msg
  return msg
end

function Re:Pump()
  local s = self.session
  if not s or s.done then return end
  if not self:On() or not self:CanBuyNow() then
    s.stopped = C.InCombat() and "combat" or (not C.MerchantShown()) and "vendor closed" or nil
    s.done = true
    self:Report(s)
    return
  end
  local job = table.remove(s.queue, 1)
  if not job then
    -- a moment for the last purchase to reach the bags, then say what came of it
    s.done = true
    C.After(self.REPORT_DELAY, function() Re:Report(s) end)
    return
  end
  if job.cost <= C.Money() then
    local buy = C.G("BuyMerchantItem")
    if type(buy) == "function" then
      if job.quantity then pcall(buy, job.index, job.quantity) else pcall(buy, job.index) end
    end
  end
  C.After(self.BUY_DELAY, function() Re:Pump() end)
end

-- At a vendor: buy what the list is short of. Returns how many purchases were queued.
function Re:OnShow()
  if self.session and not self.session.done then self.session.done = true end
  if not self:On() or not self:CanBuyNow() then return 0 end
  local s = { queue = self:Plan(), bought = 0, spent = 0, before = {}, each = {} }
  self.session = s
  local n = #s.queue
  if n == 0 then s.done = true return 0 end
  for _, job in ipairs(s.queue) do
    if s.before[job.id] == nil then s.before[job.id] = C.ItemCount(job.id) or 0 end
    s.each[job.id] = job.each
  end
  self:Pump()
  return n
end

Mer:On("MERCHANT_SHOW", function() C.After(0.3, function() if Mer.active then Re:OnShow() end end) end)
Mer:On("MERCHANT_CLOSED", function() if Re.session and not Re.session.done then Re.session.queue = {} end end)

-- Alt-click an item in the vendor's window: on the list (one full stack) or off it. An after-hook on the game's own
-- click handler; it never replaces it.
local hooked = false
function Re:Hook()
  if hooked then return end
  hooked = C.Hook("MerchantItemButton_OnModifiedClick", function(btn)
    -- the buy-back tab shows other items on the same buttons: nothing is listed from there
    if not (Re:On() and C.AltDown()) or C.MerchantBuybackTab() then return end
    local index = btn and btn.GetID and btn:GetID()
    local link = index and R(first("GetMerchantItemLink", index))
    local id = C.ItemIDFromLink(link)
    if not id then return end
    if Re:List()[id] then
      Re:Set(id, 0)
      Panoply:Print(("%s is off your restock list."):format(link))
    else
      local ii = C.ItemInfo(link)
      local n = Re:Set(id, math.max(1, tonumber(ii and ii.stack) or 1))
      Panoply:Print(("Restock keeps %d %s. Alt-click it again to stop, or type /panoply restock and a number to change it."):format(n, link))
    end
  end) and true or false
end
Panoply:Listen("MODULE_CHANGED", function(key, on) if key == "merchant" and on then Re:Hook() end end)
Panoply:On("PLAYER_LOGIN", function() if Mer.active then Re:Hook() end end)

-- /panoply restock            the list
-- /panoply restock on | off   the switch
-- /panoply restock 40 <item>  keep 40 of it (0 takes it off); <item> is a link (Shift-click it) or an item number
function Re:Slash(msg)
  local rest = (msg or ""):gsub("^%s*%S+%s*", "", 1)
  local word = rest:match("^(%S+)") or ""
  if word:lower() == "on" or word:lower() == "off" then
    Panoply:SetOption("restock", word:lower() == "on")
    Panoply:Print(word:lower() == "on" and "Restock is on: at a vendor, Panoply Suite buys what your list is short of." or "Restock is off.")
    return
  end
  local count, item = rest:match("^(%d+)%s+(.+)$")
  if count then
    local id = C.ItemIDFromLink(item)
    if not id then Panoply:Print("Usage: /panoply restock 40 and then Shift-click the item, so its link follows the number.") return end
    local n = self:Set(id, tonumber(count))
    Panoply:Print(n > 0 and ("Restock keeps %d %s."):format(n, itemName(id)) or ("%s is off your restock list."):format(itemName(id)))
    if n > 0 and not (Panoply.db and Panoply.db.restock) then Panoply:Print("Restock itself is off. Turn it on with /panoply restock on, or in " .. Panoply:SettingsPath("restock") .. ".") end
    return
  end
  Panoply:Print(self:Summary() .. ".")
  for _, l in ipairs(self:Lines()) do Panoply:Print(l) end
end

-------------------------------------------------------------------------------
-- Fast loot
-------------------------------------------------------------------------------
local Loot = {}
Panoply.FastLoot = Loot

-- Is the game about to auto loot this window? (the auto loot setting, turned around while its key is held)
function Loot.AutoLootNow()
  local on = false
  local get = C.G("C_CVar.GetCVarBool") or C.G("GetCVarBool")
  if type(get) == "function" then local ok, v = pcall(get, "autoLootDefault") on = ok and R(v) and true or false end
  local mod = C.G("IsModifiedClick")
  if type(mod) == "function" then
    local ok, held = pcall(mod, "AUTOLOOTTOGGLE")
    if ok and R(held) then on = not on end
  end
  return on
end

function Loot.MasterLoot()
  local f = C.G("C_PartyInfo.GetLootMethod") or C.G("GetLootMethod")
  if type(f) ~= "function" then return false end
  local ok, method = pcall(f)
  method = ok and R(method)
  return method == "master" or method == 2
end

-- Pick up everything in the open loot window now. Returns how many slots were asked for.
function Loot:Take()
  if not (Panoply.db and Panoply.db.fastLoot == true) then return 0 end
  if not Loot.AutoLootNow() or Loot.MasterLoot() then return 0 end
  local now = C.GetTime()
  if self.last and now - self.last >= 0 and now - self.last < Re.LOOT_GAP then return 0 end
  self.last = now
  local take = C.G("LootSlot")
  local n = tonumber(R(first("GetNumLootItems"))) or 0
  if type(take) ~= "function" or n <= 0 then return 0 end
  local info = C.G("GetLootSlotInfo")
  local done = 0
  for slot = n, 1, -1 do
    local locked = false
    if type(info) == "function" then
      local ok, _, _, _, _, _, isLocked = pcall(info, slot)
      locked = ok and R(isLocked) and true or false
    end
    if not locked and pcall(take, slot) then done = done + 1 end
  end
  return done
end

Panoply:On("LOOT_READY", function() Loot:Take() end)
