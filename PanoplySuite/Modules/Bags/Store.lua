-- Inventory store (SPEC 19.3): what every character on this account carries and keeps in the
-- bank, saved per realm and character, for offline viewing, tooltip counts and the profession
-- window's "can make from bags + bank". Only reads bag APIs; never moves anything.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Store = { dirty = {}, cache = nil }
Panoply.Inventory = Store

function Store:Enabled()
  local M = Panoply.Modules
  return M and (M:IsOn("bags") or M:IsOn("profwindow") or M:IsOn("alts")) or false
end

function Store:Me()
  local p = C.PlayerInfo()
  return p.realm or "Realm", p.name or "Me", p
end

function Store:Realm(realm)
  if not Panoply.db then return {} end
  Panoply.db.inventory = Panoply.db.inventory or {}
  realm = realm or (self:Me())
  Panoply.db.inventory[realm] = Panoply.db.inventory[realm] or {}
  return Panoply.db.inventory[realm]
end

function Store:Char(name, realm)
  local r = self:Realm(realm)
  local _, me, p = self:Me()
  name = name or me
  if not r[name] then r[name] = { bags = {}, bank = {} } end
  local c = r[name]
  if name == me then c.class, c.faction = p.classFile, p.faction end
  return c
end

-- Characters on a realm, yours first, then by name.
function Store:Characters(realm)
  local _, me = self:Me()
  local out = {}
  for n in pairs(self:Realm(realm)) do out[#out + 1] = n end
  table.sort(out, function(a, b) if (a == me) ~= (b == me) then return a == me end return a < b end)
  return out
end

local function readContainer(bag)
  local t = { size = C.NumSlots(bag) }
  local fam = C.BagFamily and C.BagFamily(bag) or 0   -- 0.8.1: a specialty bag (quiver, herb, soul...) is shown apart
  if fam and fam ~= 0 then t.family = fam end
  for slot = 1, t.size do
    local i = C.SlotInfo(bag, slot)
    if i and i.itemID then t[slot] = { i.itemID, i.count or 1, i.quality, i.link } end
  end
  return t
end
Store.ReadContainer = readContainer

-- 0.9.5 phase 4A4 (spec 06 section 0.3): what the bags hold, as one string. BAG_UPDATE also comes for cooldowns, durability and the
-- like; the bags are saved again then, but INVENTORY_CHANGED (Muster, the bag window, the profession window, Home) only goes out when
-- an item, a count, a bag or the gold really changed.
function Store.BagSig(c)
  local out = { tostring(c.money) }
  local ids = {}
  for bag in pairs(c.bags or {}) do ids[#ids + 1] = bag end
  table.sort(ids)
  for _, bag in ipairs(ids) do
    local t = c.bags[bag]
    out[#out + 1] = "|" .. tostring(bag) .. ":" .. tostring(t.size) .. ":" .. tostring(t.family)
    for slot = 1, t.size or 0 do
      local it = t[slot]
      if it then out[#out + 1] = slot .. "=" .. tostring(it[1]) .. "x" .. tostring(it[2]) .. ":" .. tostring(it[4]) end
    end
  end
  return table.concat(out, ",")
end

function Store:SaveBags()
  if not self:Enabled() then return end
  local c = self:Char()
  c.bags = {}
  for _, bag in ipairs(C.BagIDs()) do c.bags[bag] = readContainer(bag) end
  local money = C.MoneyKnown()   -- hidden (WoW Forever): the last good amount stays
  if money then c.money = money end
  c.t = time and time() or 0
  self.cache = nil
  local sig = Store.BagSig(c)
  if sig == self.lastBagSig then Panoply.quieted.INVENTORY_CHANGED = (Panoply.quieted.INVENTORY_CHANGED or 0) + 1 return end
  self.lastBagSig = sig
  Panoply.bagRev = (Panoply.bagRev or 0) + 1   -- what the step and profession signatures read (Engine/Steps.lua)
  Panoply:Fire("INVENTORY_CHANGED", "bags")
end

function Store:SaveBank()
  if not self:Enabled() or not self.atBank then return end
  local c = self:Char()
  c.bank = {}
  for _, bag in ipairs(C.BankIDs()) do c.bank[bag] = readContainer(bag) end
  c.bankSeen = time and time() or 0
  self.cache = nil
  Panoply:Fire("INVENTORY_CHANGED", "bank")
end

-- Coalesce bursts of BAG_UPDATE into one read.
function Store:Touch()
  if self.pending then return end
  self.pending = true
  C.After(0.3, function()
    Store.pending = false
    Store:SaveBags()
    if Store.atBank then Store:SaveBank() end
  end)
end

-- counts[itemID][charName] = { bags, bank }
function Store:Counts(realm)
  if self.cache and self.cacheRealm == (realm or "") then return self.cache end
  local out = {}
  for name, c in pairs(self:Realm(realm)) do
    for _, where in ipairs({ "bags", "bank" }) do
      for _, cont in pairs(c[where] or {}) do
        for slot, it in pairs(cont) do
          if type(slot) == "number" and type(it) == "table" then
            local id = it[1]
            out[id] = out[id] or {}
            out[id][name] = out[id][name] or { bags = 0, bank = 0 }
            out[id][name][where] = out[id][name][where] + (it[2] or 1)
          end
        end
      end
    end
  end
  self.cache, self.cacheRealm = out, realm or ""
  return out
end

-- How many of an item this character has in bags + bank (live bags, saved bank).
function Store:Have(itemID, name)
  local c = self:Counts()[itemID]
  local _, me = self:Me()
  local mine = c and c[name or me]
  local live = C.ItemCount(itemID, false)
  local bags = (name == nil or name == me) and live or (mine and mine.bags or 0)
  return bags + (mine and mine.bank or 0), bags, mine and mine.bank or 0
end

function Store:TooltipLines(itemID)
  local counts = self:Counts()[itemID]
  if not counts then return {} end
  local lines, total, n = {}, 0, 0
  for _, name in ipairs(self:Characters()) do
    local cn = counts[name]
    if cn and (cn.bags + cn.bank) > 0 then
      local parts = {}
      if cn.bags > 0 then parts[#parts + 1] = cn.bags .. " in bags" end
      if cn.bank > 0 then parts[#parts + 1] = cn.bank .. " in bank" end
      lines[#lines + 1] = { name = name, text = name .. ": " .. table.concat(parts, ", "), class = self:Char(name).class }
      total, n = total + cn.bags + cn.bank, n + 1
    end
  end
  if n > 1 then lines[#lines + 1] = { text = "Total: " .. total, total = true } end
  return lines
end

local tooltipHooked
function Store:HookTooltip()
  if tooltipHooked then return end
  tooltipHooked = C.HookItemTooltip(function(tt, id)
    if not (Panoply.Modules:IsOn("bags") and Panoply.db.bagTooltipCounts) then return end
    for _, l in ipairs(Store:TooltipLines(id)) do
      local cc = l.class and _G.RAID_CLASS_COLORS and RAID_CLASS_COLORS[l.class]
      if cc then tt:AddLine(l.text, cc.r, cc.g, cc.b) else tt:AddLine(l.text, 0.95, 0.82, 0.45) end
    end
    if tt.Show then tt:Show() end
  end) or "none"
end

Panoply:On("BAG_UPDATE", function() if Store:Enabled() then Store:Touch() end end)
Panoply:On("BAG_UPDATE_DELAYED", function() if Store:Enabled() then Store:Touch() end end)
Panoply:On("PLAYER_MONEY", function()
  if not Store:Enabled() then return end
  local money = C.MoneyKnown()   -- hidden (WoW Forever): the last good amount stays
  local c = Store:Char()
  if not money or money == c.money then return end   -- 0.9.5 phase 4A4: only a real change of gold is told
  c.money = money
  Store.lastBagSig = nil
  Panoply:Fire("INVENTORY_CHANGED", "money")
end)
Panoply:On("BANKFRAME_OPENED", function() Store.atBank = true if Store:Enabled() then Store:SaveBank() end Panoply:Fire("BANK_OPENED") end)
Panoply:On("BANKFRAME_CLOSED", function() if Store:Enabled() then Store:SaveBank() end Store.atBank = false Panoply:Fire("BANK_CLOSED") end)
Panoply:On("PLAYERBANKSLOTS_CHANGED", function() if Store:Enabled() and Store.atBank then Store:Touch() end end)
