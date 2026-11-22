-- Prices (SPEC 19.7): THE price service (0.7.3). Tooltips, the profession window and the profession
-- planner all ask this file; there is no other price lookup in Panoply Suite.
-- Sources, all optional and feature-detected:
--   yours       prices you typed with /panoply price (Panoply.db.prices); they win for crafting costs
--   scan        Panoply Suite's own auction scans (PanoplySuiteAuctionDB, per realm + faction)
--   companion   the companion add-on Hearthpath_Data (HearthpathPrices, made outside the game)
--   Blizzard    0.9.5, WoW Forever: free auction prices from Blizzard's game data API that Panoply Hub writes into
--               PanoplySuite_Plans/Prices.lua (PanoplySuiteHubPrices). Read only, never copied into saved data, and
--               nothing older than 30 days is used (Blizzard's terms).
-- Auto picks the newest of scan / Blizzard / companion file (realm + faction), then the region average
-- ("US avg"), then just the vendor price.
-- P.Unit(id) = one item's price; P.CraftCost / P.CraftLine = a recipe's materials and profit;
-- P.History(key) = the 30 days kept per item; P.Mine() = your own recent postings (capped).
-- Saved data (PanoplySuiteAuctionDB, per "Realm-Faction"): items[key] = "cur,t,q;day,min,qty;..." with at
-- most P.HISTORY_DAYS (30) days per item, at most P.MAX_ITEMS (8000) items per realm, and
-- mine = at most P.MAX_MINE (200) postings.
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = {}
Panoply.Prices = P
P.OLD = 3 * 86400          -- data older than this is marked "old"
P.HISTORY_DAYS = 30
P.MAX_ITEMS = 8000         -- items kept per realm + faction (the least recently seen go first)
P.MAX_MINE = 200           -- your own postings kept per realm + faction
P.DAY = 86400

for k, v in pairs({ tooltipVendor = true, tooltipAuction = true, priceSource = "auto" }) do Panoply.defaults.account[k] = v end

local function now() return (_G.time and time()) or 0 end
P.Now = now

-------------------------------------------------------------------------------
-- Realm + faction key. Characters on the same realm (or connected realms) and faction share data.
-------------------------------------------------------------------------------
local function norm(s) return s and (tostring(s):gsub("[%s%-']", "")) or nil end
P.Norm = norm
function P.RealmName()
  local n = C.pc(_G.GetNormalizedRealmName)
  if not n or n == "" then n = norm(C.pc(_G.GetRealmName)) end
  return n or "Unknown"
end
-- Connected realms: all share one key, the alphabetically first normalised name of the group.
function P.RealmGroup()
  local me = P.RealmName()
  local list = _G.GetAutoCompleteRealms and { C.pc(_G.GetAutoCompleteRealms) } or {}
  if type(list[1]) == "table" then list = list[1] end
  local best = me
  for _, r in ipairs(list) do
    local n = norm(r)
    if n and n ~= "" and n < best then best = n end
  end
  return best
end
function P.Faction()
  if P.ahFaction then return P.ahFaction end   -- a neutral auction house while it is open
  local f = C.pc(_G.UnitFactionGroup, "player")
  return f or "Neutral"
end
function P.Key(faction) return P.RealmGroup() .. "-" .. (faction or P.Faction()) end

-------------------------------------------------------------------------------
-- Own price DB. Compact per-item string: "cur,t,q;day,min,n;day,min,n..."
--   cur = latest min buyout per unit (copper), t = when, q = quantity seen at that time,
--   history = one entry per day (min unit buyout that day, most units seen that day).
-------------------------------------------------------------------------------
function P.DB()
  local db = _G.PanoplySuiteAuctionDB
  if type(db) ~= "table" then db = { v = 1, realms = {} } _G.PanoplySuiteAuctionDB = db end
  db.realms = db.realms or {}
  db.v = db.v or 1
  return db
end
function P.Realm(key)
  local db = P.DB()
  key = key or P.Key()
  local r = db.realms[key]
  if not r then r = { items = {}, lastScan = 0, lastGetAll = 0 } db.realms[key] = r end
  r.items = r.items or {}
  return r
end
function P.Decode(s)
  if type(s) ~= "string" then return nil end
  local e = { hist = {} }
  local first = true
  for part in s:gmatch("[^;]+") do
    local a, b, c = part:match("^(%-?%d*),(%-?%d*),(%-?%d*)$")
    if first then e.cur, e.t, e.q = tonumber(a), tonumber(b), tonumber(c) first = false
    elseif a then e.hist[#e.hist + 1] = { tonumber(a), tonumber(b), tonumber(c) } end
  end
  return e
end
function P.Encode(e)
  local out = { ("%d,%d,%d"):format(e.cur or 0, e.t or 0, e.q or 0) }
  table.sort(e.hist, function(x, y) return x[1] < y[1] end)
  for _, h in ipairs(e.hist) do out[#out + 1] = ("%d,%d,%d"):format(h[1], h[2], h[3] or 0) end
  return table.concat(out, ";")
end
local function prune(e, today)
  local keep = {}
  for _, h in ipairs(e.hist) do if h[1] > today - P.HISTORY_DAYS then keep[#keep + 1] = h end end
  e.hist = keep
end
-- Record one item's min unit buyout and quantity at time t (default now).
function P.Record(key, unit, qty, t, realm)
  if not key or not unit or unit <= 0 then return end
  t = t or now()
  local r = realm or P.Realm()
  local e = P.Decode(r.items[key]) or { hist = {} }
  e.cur, e.t, e.q = math.floor(unit + 0.5), t, qty or 1
  local day = math.floor(t / P.DAY)
  local h = e.hist[#e.hist]
  for _, x in ipairs(e.hist) do if x[1] == day then h = x end end
  if h and h[1] == day then
    h[2] = math.min(h[2], e.cur); h[3] = math.max(h[3] or 0, qty or 1)
  else
    e.hist[#e.hist + 1] = { day, e.cur, qty or 1 }
  end
  prune(e, day)
  r.items[key] = P.Encode(e)
end
-- Drop history older than 30 days, items not seen for that long, and (when a realm holds more than
-- P.MAX_ITEMS items) the least recently seen ones. Returns how many items were removed.
function P.Prune(t)
  local today = math.floor((t or now()) / P.DAY)
  local n = 0
  for _, r in pairs(P.DB().realms) do
    local seenAt = {}
    for k, s in pairs(r.items or {}) do
      local e = P.Decode(s)
      if e then
        prune(e, today)
        if #e.hist == 0 and (e.t or 0) < (today - P.HISTORY_DAYS) * P.DAY then r.items[k] = nil n = n + 1
        else r.items[k] = P.Encode(e) seenAt[#seenAt + 1] = { k, e.t or 0 } end
      end
    end
    if #seenAt > P.MAX_ITEMS then
      table.sort(seenAt, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return tostring(a[1]) < tostring(b[1]) end)
      for i = P.MAX_ITEMS + 1, #seenAt do r.items[seenAt[i][1]] = nil n = n + 1 end
    end
    if type(r.mine) == "table" then while #r.mine > P.MAX_MINE do table.remove(r.mine, 1) end end
  end
  return n
end
-- Our own scan for an item: price, age, and whether it was in the latest full scan.
function P.FromScan(key)
  local r = P.DB().realms[P.Key()]
  local e = r and P.Decode(r.items[key])
  if not e or not e.cur then return nil end
  local t = now()
  local res = { source = "scan", label = "scan", price = e.cur, at = e.t, age = t - (e.t or 0), qty = e.q }
  res.listed = (e.t or 0) >= (r.lastScan or 0)
  local hi, sum, n = 0, 0, 0
  for _, h in ipairs(e.hist) do
    if h[1] > math.floor(t / P.DAY) - P.HISTORY_DAYS then hi = math.max(hi, h[2]) sum = sum + h[2] n = n + 1 end
  end
  res.high = hi > 0 and hi or nil
  res.avg = n > 0 and math.floor(sum / n + 0.5) or nil
  res.lastSeen, res.lastSeenAt = e.cur, e.t
  -- 0.9.5 (spec 7.2): the saved scan's summary of the item: its market price and the scan's age
  local Rec = Panoply.Auctions and Panoply.Auctions.Record
  if Rec and Rec.Snap and Rec.Item then
    local ok, snap = pcall(Rec.Snap, P.Key())
    local it = ok and snap and Rec.Item(snap, key)
    if it then
      res.market, res.scanAt, res.scanAge = it.market, snap.t, t - (tonumber(snap.t) or t)
      res.listings, res.scanQty = it.listings, it.qty
    end
  end
  return res
end

-------------------------------------------------------------------------------
-- Companion file Hearthpath_Data: HearthpathPrices
--   realms[realm][faction] = { updated, items = { [id] = { market, minBuyout, historical[, recent] } } }
--   region = { updated, items = { [id] = { market, historical, avgSalePrice } } }
-- Copper; minBuyout 0 = none listed; historical 0 = unknown (Era files); recent may be missing.
-------------------------------------------------------------------------------
local function pos(v) v = tonumber(v) return (v and v > 0) and v or nil end
-- The prices file keeps its old name (Hearthpath_Data / HearthpathPrices: the helper writes it on players'
-- computers). A later helper may write PanoplySuite_Data / PanoplySuitePrices instead: that one is read
-- first when it is there, the old one otherwise.
function P.CompanionFile()
  local new = _G.PanoplySuitePrices
  if type(new) == "table" then return new end
  local old = _G.HearthpathPrices
  if type(old) == "table" then return old end
  return nil
end
function P.CompanionRealm()
  local HPP = P.CompanionFile()
  if type(HPP) ~= "table" or type(HPP.realms) ~= "table" then return nil end
  local tries = { C.pc(_G.GetRealmName), C.pc(_G.GetNormalizedRealmName) }
  for _, n in ipairs(tries) do if n and HPP.realms[n] then return HPP.realms[n] end end
  local want = {}
  for _, n in ipairs(tries) do if n then want[norm(n):lower()] = true end end
  for k, v in pairs(HPP.realms) do if want[norm(k):lower()] then return v end end
  return nil
end
function P.FromCompanion(id)
  local realm = P.CompanionRealm()
  local fac = realm and realm[P.Faction()]
  local t = fac and fac.items and fac.items[id]
  if type(t) ~= "table" then return nil end
  local market, minBuyout, hist = pos(t[1]), pos(t[2]), pos(t[3])
  local recent = pos(t[4]) or minBuyout
  local price = minBuyout or market
  if not price then return nil end
  local file = P.CompanionFile() or {}
  local at = tonumber(fac.updated or file.generated) or 0
  return { source = "companion", label = "Companion file", price = price, listed = minBuyout ~= nil, market = market,
           historical = hist, recent = recent, minBuyout = minBuyout, at = at, age = now() - at }
end
function P.FromRegion(id)
  local HPP = P.CompanionFile()
  local reg = type(HPP) == "table" and HPP.region
  local t = reg and reg.items and reg.items[id]
  if type(t) ~= "table" then return nil end
  local market, hist, sale = pos(t[1]), pos(t[2]), pos(t[3])
  local price = market or sale or hist
  if not price then return nil end
  local at = tonumber(reg.updated) or 0
  return { source = "region", label = "US avg", price = price, market = market, historical = hist, avgSale = sale,
           at = at, age = now() - at, listed = true, region = true }
end

-------------------------------------------------------------------------------
-- 0.9.5: WoW Forever auction prices from Blizzard's game data API (PanoplySuite_Plans/Prices.lua, written by Panoply
-- Hub outside the game; PanoplyHub/SAVEDVARS-CONTRACT.md "Auction prices"). Read as untrusted data:
--   PanoplySuiteHubPrices = { format = 1, realms = { [realm] = { Alliance = id, Horde = id, Neutral = id, All = id } },
--     commodities = id?, houses = { [id] = { faction, updated, items = { [itemID] = { lowest, market, qty } } } } }
-------------------------------------------------------------------------------
P.HUB_KEEP = 30 * 86400    -- Blizzard's terms: a price older than this is never used
-- the exact credit and disclaimer of the price feed (.lane/CONTRACT-V2.md; PanoplyHub/core/include/hp/prices.hpp)
P.HUB_CREDIT = "Market data via the Blizzard Developer API."
P.HUB_DISCLAIMER = "Panoply Suite and Panoply Hub are not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks or registered trademarks of Blizzard Entertainment, Inc., in the U.S. and/or other countries."
-- the same, short enough for a tooltip at 1.3x text on a 1024x668 screen (and naming no Panoply Hub there)
P.HUB_TIP_CREDIT = P.HUB_CREDIT
P.HUB_TIP_DISCLAIMER = "Not affiliated with or endorsed by Blizzard Entertainment."
function P.HubFile()
  local f = _G.PanoplySuiteHubPrices
  if type(f) ~= "table" or f.format ~= 1 or type(f.houses) ~= "table" or type(f.realms) ~= "table" then return nil end
  return f
end
local function hubHouse(f, id)
  local h = type(id) == "string" and f.houses[id]
  if type(h) ~= "table" or type(h.items) ~= "table" then return nil end
  local at = tonumber(h.updated)
  if not at or now() - at > P.HUB_KEEP then return nil end
  return h, at
end
-- The houses for this character: its realm's house for its faction (the neutral house while one is open), the realm's
-- one list when it has no faction houses, then the region-wide commodities.
-- this character's realm in the file's realms map: the entry, and the name it is listed under
local function hubRealm(f)
  local tries = { C.pc(_G.GetRealmName), C.pc(_G.GetNormalizedRealmName) }
  for _, n in ipairs(tries) do if n and type(f.realms[n]) == "table" then return f.realms[n], n end end
  local want = {}
  for _, n in ipairs(tries) do if n then want[norm(n):lower()] = true end end
  for k, v in pairs(f.realms) do if type(k) == "string" and type(v) == "table" and want[norm(k):lower()] then return v, k end end
  return nil
end
function P.HubHouses()
  local f = P.HubFile()
  if not f then return {} end
  local entry = hubRealm(f)
  local out = {}
  if entry then
    local h, at = hubHouse(f, entry[P.Faction()])
    if not h then h, at = hubHouse(f, entry.All) end
    if h then out[#out + 1] = { h, at } end
  end
  local c, cat = hubHouse(f, f.commodities)
  if c then out[#out + 1] = { c, cat } end
  return out
end
-- 0.9.9.2: has Panoply Hub found this character's auction house? Panoply Hub works it out from the scans saved in the game (Record.lua,
-- house[...]) and lists the house in the realms map; a house it only guessed (the busiest of the faction) is named in the file's
-- `guessed` table and does not count. Returns the line for the Auctions page and whether the house was found.
P.HOUSE_FOUND = "Your auction house: %s, %s"
P.HOUSE_FOUND_ONE = "Your auction house: %s"
-- three honest states: matched; a scan of this realm + faction is saved but Hub has not matched it yet; no scan yet
P.HOUSE_NOT_FOUND = "Open the auction house once so Panoply Hub can find your house."
P.HOUSE_NOT_FOUND_SHORT = "Open the auction house once to find your house."   -- a narrow window, where the line above would be cut off
P.HOUSE_SCANNED = "Scan saved. Panoply Hub will match your auction house."
P.HOUSE_SCANNED_SHORT = "Scan saved. Hub will match your house."
-- returns the line, whether the house was found, the shorter line for a narrow window, and the state ("matched", "scanned", "none")
function P.HubHouseLine()
  local f = P.HubFile()
  local realm, name
  if f then realm, name = hubRealm(f) end
  if realm then
    local faction = P.Faction()
    local id = realm[faction]
    local shownFaction = faction
    if not id then id, shownFaction = realm.All, nil end
    local guessed = type(f.guessed) == "table" and type(f.guessed[name]) == "table" and f.guessed[name][shownFaction or "All"]
    if id and not guessed and hubHouse(f, id) then
      local shown = C.pc(_G.GetRealmName) or P.RealmName()
      local line = shownFaction and P.HOUSE_FOUND:format(shownFaction, shown) or P.HOUSE_FOUND_ONE:format(shown)
      return line, true, line, "matched"
    end
  end
  local db = _G.PanoplySuiteAuctionDB
  if type(db) == "table" and type(db.house) == "table" and type(db.house[P.Key()]) == "table" then
    return P.HOUSE_SCANNED, false, P.HOUSE_SCANNED_SHORT, "scanned"
  end
  return P.HOUSE_NOT_FOUND, false, P.HOUSE_NOT_FOUND_SHORT, "none"
end
function P.FromHub(id)
  if type(id) ~= "number" then id = tonumber(id) end
  if not id then return nil end
  for _, hh in ipairs(P.HubHouses()) do
    local t = hh[1].items[id]
    if type(t) == "table" then
      local lowest, market, qty = pos(t[1]), pos(t[2]), pos(t[3])
      local price = lowest or market
      if price then
        local at = hh[2]
        return { source = "hub", label = "Blizzard", price = price, listed = true, market = market, qty = qty,
                 at = at, age = math.max(0, now() - at) }
      end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Choosing a price
-------------------------------------------------------------------------------
P.SOURCES = { { "auto", "Auto (newest)" }, { "scan", "Panoply Suite scan" }, { "hub", "Blizzard prices (WoW Forever)" }, { "companion", "Companion file" } }
-- a saved source this version does not offer is set back to "auto" in the saved table (load, and Profiles:Apply)
function P.CleanSource(db)
  if type(db) ~= "table" then return end
  for _, src in ipairs(P.SOURCES) do if src[1] == db.priceSource then return end end
  db.priceSource = "auto"
end
function P.ItemKey(id, link)
  if type(link) == "string" then
    local s = link:match("item:([%-%d:]+)")
    if s then
      local f = {}
      for x in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = x end
      local suffix = tonumber(f[7] or "")
      if suffix and suffix ~= 0 then return (tonumber(f[1]) or id) .. ":" .. suffix end
    end
  end
  return id
end
-- Returns the chosen price record (or nil) and the list of all candidates.
function P.Lookup(id, link, mode)
  mode = mode or (Panoply.db and Panoply.db.priceSource) or "auto"
  local known = false
  for _, src in ipairs(P.SOURCES) do if src[1] == mode then known = true end end
  if not known then mode = "auto" end   -- a saved source this version does not offer
  local key = P.ItemKey(id, link)
  local scan = P.FromScan(key)
  if not scan and key ~= id then scan = P.FromScan(id) end
  local cands = {}
  local comp = (mode == "auto" or mode == "companion") and P.FromCompanion(id) or nil
  local hub = (mode == "auto" or mode == "hub") and P.FromHub(id) or nil
  if mode == "scan" then return scan, { scan }
  elseif mode == "hub" then return hub, { hub }
  elseif mode == "companion" then return comp or P.FromRegion(id), { comp } end
  if scan then cands[#cands + 1] = scan end
  if hub then cands[#cands + 1] = hub end
  if comp then cands[#cands + 1] = comp end
  -- newest wins; a record with unknown age loses to any dated one
  table.sort(cands, function(a, b)
    local x, y = a.age or math.huge, b.age or math.huge
    if x ~= y then return x < y end
    return (a.source == "scan") and b.source ~= "scan"
  end)
  local best = cands[1]
  -- an own record of an item that was NOT in the latest scan still wins for "last seen", but if
  -- another source has it listed and is newer, that one is shown (already handled by age)
  if not best then best = P.FromRegion(id) end
  return best, cands, scan
end


-------------------------------------------------------------------------------
-- The one price service (0.7.3). Everything that needs "what does this cost" asks here:
--   item tooltips (P:AddLines), the profession window (P.CraftLine), the profession planner
--   (PD.Price calls P.Yours / P.Market), the shopping, selling and cancelling tabs.
-------------------------------------------------------------------------------
-- A price you typed with /panoply price. 0 or less counts as "not set".
function P.Yours(id, name)
  local t = Panoply.db and Panoply.db.prices
  if type(t) ~= "table" then return nil end
  local v = id and pos(t[id])
  if v then return v end
  if not name and id then local ii = C.ItemInfo(id) name = ii and ii.name end
  return name and pos(t[name]) or nil
end
-- The market price (own scan, Blizzard prices, companion file, region average), copper per item, and the
-- record it came from. Never your typed prices.
function P.Market(id, link)
  local best = P.Lookup(id, link)
  if best and best.price then return best.price, best end
  return nil
end
-- One item: your price first, else the market. Returns copper, "you" | "auction", a label for the
-- source ("your prices", "scan", "Blizzard", "Companion file", "US avg"). market == false: yours only.
function P.Unit(id, link, name, market)
  local y = P.Yours(id, name)
  if y then return y, "you", "your prices" end
  if market == false then return nil end
  local c, rec = P.Market(id, link)
  if c then return c, "auction", rec.label end
  return nil
end

-- Material cost of a recipe row ({ reagents = { { itemID, name, need } } }): total copper, a source
-- label, and whether every reagent had a price. nil when nothing is known. market == false: only the
-- prices you typed (the "Use auction prices" setting off).
function P.CraftCost(row, market)
  local total, known, labels, n = 0, true, {}, 0
  for _, rg in ipairs(row and row.reagents or {}) do
    local c, _, label = P.Unit(rg.itemID, rg.link, rg.name, market)
    if c then
      total = total + c * (rg.need or 1)
      if not labels[label] then labels[label] = true n = n + 1 labels[#labels + 1] = label end
    else known = false end
  end
  if n == 0 then return nil end
  return total, (n == 1 and labels[1] or "mixed prices"), known
end

-- The Auction House keeps 5% of a sale (15% at the neutral houses in Booty Bay, Gadgetzan and Everlook).
function P.AHCut() return P.ahFaction == "Neutral" and 0.15 or 0.05 end
-- Profit of selling `count` of the crafted item at its unit price, after the cut, minus the cost.
-- Returns profit (may be negative), the sale price, or nil when the crafted item has no known price.
function P.Profit(itemID, link, count, cost)
  if not itemID or not cost then return nil end
  local unit = P.Unit(itemID, link)
  if not unit then return nil end
  count = (count and count > 0) and count or 1
  local sale = unit * count
  return math.floor(sale * (1 - P.AHCut()) + 0.5) - cost, sale
end
-- The text the profession window shows under a recipe: "Materials: ... (source)" and a Profit line.
-- (row.numMade = how many one craft makes, default 1.) nil when no price is known.
function P.CraftLine(row, market)
  local cost, src, known = P.CraftCost(row, market)
  if not cost then return nil end
  local out = ("Materials: %s%s (%s)"):format(C.FormatMoney(cost), known and "" or "+", src)
  if known and market ~= false and row.itemID then
    local profit, sale = P.Profit(row.itemID, row.itemLink, row.numMade, cost)
    if profit then
      out = out .. ("\n%s: %s (sells for %s, after the %d%% auction house cut)"):format(profit >= 0 and "Profit" or "Loss",
        C.FormatMoney(math.abs(profit)), C.FormatMoney(sale), math.floor(P.AHCut() * 100 + 0.5))
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- 0.7.4 (auctions redesign): the cost of one bag item, for the Sell tab's verdict and profit.
--   crafted item (Panoply Suite's recipe data says a recipe makes it): the cost to make = the materials priced by
--   P.CraftCost (the same numbers the profession window shows), divided by how many one craft makes; with
--   several recipes the cheapest one whose materials ALL have a price is used.
--   any other item: the vendor price (the sure money you give up by not vendoring).
--   a crafted item with a material that has no price anywhere: the vendor price, and `partial` says so.
-- UNVERIFIED: which bag items the recipe data covers (it is Classic 1.12 data).
-------------------------------------------------------------------------------
-- itemID -> { { prof = "Tailoring", row = { itemID, numMade, reagents = { { itemID, name, need } } } } }
local function craftedIndex()
  if P.crafted then return P.crafted end
  local idx = {}
  local PD = Panoply.ProfData
  if PD then
    for _, prof in ipairs(PD.ORDER or {}) do
      local def = PD[prof]
      for _, r in ipairs(type(def) == "table" and def.recipes or {}) do
        if r.makes and type(r.reagents) == "table" then
          local rg = {}
          for id, need in pairs(r.reagents) do rg[#rg + 1] = { itemID = id, name = PD.ItemName and PD.ItemName(id) or nil, need = need } end
          table.sort(rg, function(a, b) return a.itemID < b.itemID end)
          if #rg > 0 then
            idx[r.makes] = idx[r.makes] or {}
            table.insert(idx[r.makes], { prof = prof, row = { itemID = r.makes, numMade = (r.count and r.count > 0) and r.count or 1, reagents = rg } })
          end
        end
      end
    end
  end
  P.crafted = idx
  return idx
end
function P.ResetCrafted() P.crafted = nil end
-- Returns { cost = copper each (may be fractional), kind = "crafted" | "vendor", prof, vendor, partial }.
-- cost is nil only when the item has no vendor price either (it is then worth 0 to a vendor).
function P.CostEach(id)
  local ii = id and C.ItemInfo(id)
  local vendor = (ii and ii.sellPrice) or 0
  local out = { kind = "vendor", cost = vendor, vendor = vendor }
  local best
  for _, e in ipairs(craftedIndex()[id] or {}) do
    local total, _, known = P.CraftCost(e.row)
    if total and known then
      local each = total / e.row.numMade
      if not best or each < best.each then best = { each = each, prof = e.prof, src = select(2, P.CraftCost(e.row)) } end
    else
      out.partial, out.prof = true, e.prof       -- a recipe exists, but a material has no price: its cost is not used
    end
  end
  if best then out.kind, out.cost, out.prof, out.partial, out.src = "crafted", best.each, best.prof, nil, best.src end
  return out
end

-- Price history of one item key on this realm: { cur, t, q, hist = { { day, min, qty } ... } } with the
-- days oldest first, or nil. At most P.HISTORY_DAYS days are kept.
function P.History(key)
  local r = P.DB().realms[P.Key()]
  local e = r and P.Decode(r.items[key])
  if not e or not e.cur then return nil end
  table.sort(e.hist, function(a, b) return a[1] < b[1] end)
  return e
end
-- Every item key this realm has a price for.
function P.Known()
  local r = P.DB().realms[P.Key()]
  local out = {}
  for k in pairs(r and r.items or {}) do out[#out + 1] = k end
  return out
end
function P.KeyID(key) return tonumber((tostring(key):match("^(%d+)"))) end
function P.KeyName(key)
  local id = P.KeyID(key)
  local ii = id and C.ItemInfo(id)
  return ii and ii.name or (id and ("item " .. id) or tostring(key))
end

-- Your own recent postings on this realm + faction ("Your History"), newest last, capped.
function P.Mine()
  local r = P.Realm()
  r.mine = r.mine or {}
  return r.mine
end
function P.RecordPost(e)
  local m = P.Mine()
  e.t = e.t or now()
  m[#m + 1] = e
  while #m > P.MAX_MINE do table.remove(m, 1) end
end

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
local ICON = { g = "Interface\\MoneyFrame\\UI-GoldIcon", s = "Interface\\MoneyFrame\\UI-SilverIcon", c = "Interface\\MoneyFrame\\UI-CopperIcon" }
function P.Money(c)
  c = math.floor((c or 0) + 0.5)
  -- 0.6.1: C_CurrencyInfo.GetCoinTextureString on Forever and Era 1.15.9; the old global as fallback
  local CI = _G.C_CurrencyInfo
  local f = (CI and CI.GetCoinTextureString) or _G.GetCoinTextureString
  if f then
    local ok, s = pcall(f, c)
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  local function add(v, k) out[#out + 1] = v .. "|T" .. ICON[k] .. ":0:0:2:0|t" end
  if g > 0 then add(g, "g") end
  if s > 0 or (g > 0 and cc > 0) then add(s, "s") end
  if cc > 0 or #out == 0 then add(cc, "c") end
  return table.concat(out, " ")
end
function P.Age(sec)
  if not sec then return "age unknown" end
  if sec < 3600 then return ("%dm ago"):format(math.max(1, math.floor(sec / 60))) end
  if sec < 86400 then return ("%dh ago"):format(math.floor(sec / 3600)) end
  local d = math.floor(sec / 86400)
  return d == 1 and "1 day ago" or ("%d days ago"):format(d)
end
function P.Date(t) return (_G.date and t and t > 0) and date("%b %d", t) or "?" end
-- how old a price is, for the line beside it: "12 minutes old", "5 hours old", "7 days old" (spec 7.2: every tooltip price shows its age)
function P.Old(sec)
  if not sec then return "age unknown" end
  sec = math.max(0, sec)
  if sec < 3600 then local m = math.max(1, math.floor(sec / 60)) return m == 1 and "1 minute old" or ("%d minutes old"):format(m) end
  if sec < 86400 then local h = math.floor(sec / 3600) return h == 1 and "1 hour old" or ("%d hours old"):format(h) end
  local d = math.floor(sec / 86400)
  return d == 1 and "1 day old" or ("%d days old"):format(d)
end

-- Stack count of the item under the tooltip, from its owner (bag slots, loot, merchant...).
function P.CountFor(tt)
  local o = tt and tt.GetOwner and C.pc(tt.GetOwner, tt)
  if type(o) ~= "table" then return 1 end
  local n = (o.entry and o.entry.count) or o.count or o.panoplyStack
  if not n and o.GetID and o.GetParent then
    local par = o:GetParent()
    local bag, slot = par and par.GetID and C.pc(par.GetID, par), C.pc(o.GetID, o)
    if bag and slot and C.SlotInfo then local si = C.SlotInfo(bag, slot) n = si and si.count end
  end
  n = tonumber(n)
  return (n and n > 1) and n or 1
end

local GREY, ORANGE = "|cff8f99a6", "|cffe8a04a"
local function line(tt, left, right)
  if tt.AddDoubleLine then tt:AddDoubleLine(left, right, 0.85, 0.80, 0.62, 1, 1, 1) else tt:AddLine(left .. "  " .. right) end
end
-- The tooltip lines. Returns the number of lines added.
function P:AddLines(tt, id, link, count)
  if not Panoply.db then return 0 end
  count = count or 1
  local added = 0
  local shift = C.ShiftDown()
  if Panoply.db.tooltipVendor ~= false then
    local ii = C.ItemInfo(id)
    local sell = ii and ii.sellPrice
    local blizz = tt.shownMoneyFrames and tt.shownMoneyFrames > 0
    if sell and sell > 0 and not blizz then
      line(tt, count > 1 and ("Vendor (x%d)"):format(count) or "Vendor", P.Money(sell * count))
      added = added + 1
    end
  end
  if Panoply.db.tooltipAuction ~= false then
    local best, _, scan = P.Lookup(id, link)
    if best then
      local old = best.age and best.age > P.OLD
      local tag = GREY .. best.label .. ", " .. P.Age(best.age) ..
        (old and (" " .. ORANGE .. "old|r") or "") .. "|r"
      if best.source == "scan" and not best.listed then
        line(tt, "Last seen " .. GREY .. P.Date(best.lastSeenAt) .. ", " .. P.Old(best.age) .. "|r", P.Money(best.lastSeen))
        added = added + 1
        if best.high then line(tt, "Highest recent " .. GREY .. "(30 days)|r", P.Money(best.high)) added = added + 1 end
      else
        local head = best.region and "US avg" or "Auction"
        if count > 1 and not shift then
          line(tt, head .. " " .. tag, P.Money(best.price) .. GREY .. " ea|r  " .. P.Money(best.price * count))
        else
          line(tt, head .. " " .. tag, P.Money(best.price))
        end
        added = added + 1
        -- the saved scan's market price of the item, with the scan's age ("Market · 7 days old   2s 40c")
        if best.source == "scan" and best.market and best.market > 0 then
          local mold = best.scanAge and best.scanAge > P.OLD
          line(tt, "Market " .. GREY .. "· " .. P.Old(best.scanAge) .. (mold and (" " .. ORANGE .. "old|r") or "") .. "|r", P.Money(best.market))
          added = added + 1
        end
      end
      if shift then
        if count > 1 then line(tt, ("  Stack of %d"):format(count), P.Money(best.price * count)) added = added + 1 end
        local s = scan or (best.source == "scan" and best)
        local ageW = GREY .. ", " .. (best.age and P.Old(best.age) or "age unknown") .. "|r"
        if s and s.avg then line(tt, "  30-day average", P.Money(s.avg)) added = added + 1 end
        if s and s.high and s.listed then line(tt, "  Highest recent " .. GREY .. "(30 days)|r", P.Money(s.high)) added = added + 1 end
        if best.market and best.market ~= best.price and best.source ~= "scan" then line(tt, "  Market (" .. best.label .. ")" .. ageW, P.Money(best.market)) added = added + 1 end
        if best.historical then line(tt, "  Historical" .. ageW, P.Money(best.historical)) added = added + 1 end
      end
      -- Blizzard's prices always carry their credit and disclaimer (Blizzard's API terms)
      if best.source == "hub" and tt.AddLine then
        tt:AddLine(GREY .. P.HUB_TIP_CREDIT .. "|r", 1, 1, 1, true)
        tt:AddLine(GREY .. P.HUB_TIP_DISCLAIMER .. "|r", 1, 1, 1, true)
        added = added + 2
      end
    end
  end
  -- a price you typed with /panoply price: its own line, so the market line above stays honest
  if Panoply.db.tooltipAuction ~= false then
    local mine = P.Yours(id)
    if mine then
      line(tt, count > 1 and ("Your price (x%d)"):format(count) or "Your price", P.Money(mine * count))
      added = added + 1
    end
  end
  if added > 0 and tt.Show then tt:Show() end
  return added
end

function P:Hook()
  if self.hooked then return end
  self.hooked = C.HookItemTooltip(function(tt, id)
    local link
    if tt.GetItem then local _, l = C.pc(tt.GetItem, tt) link = l end
    P:AddLines(tt, id, link, P.CountFor(tt))
  end) or false
end
Panoply:On("PLAYER_LOGIN", function() P:Hook() C.After(5, function() P.Prune() end) end)

-- Settings rows: Auctions > Prices.
if Panoply.Bags and Panoply.Bags.options then
  local o = Panoply.Bags.options
  o[#o + 1] = { type = "heading", label = "Tooltips" }
  o[#o + 1] = { type = "check", key = "tooltipVendor", label = "Show vendor price", tip = "What a vendor pays for the item, times the stack you point at." }
  o[#o + 1] = { type = "check", key = "tooltipAuction", label = "Show auction price", tip = "The lowest buyout per item, the stack total and how old the price is. Hold Shift for more." }
  o[#o + 1] = { type = "choice", key = "priceSource", label = "Price source", values = P.SOURCES,
    tip = "Auto uses the newest of your own scan, Blizzard's free WoW Forever prices (fetched about once an hour by Panoply Hub, never older than 30 days), and the companion file; then the US average; then just the vendor price. A price you set with /panoply price always has its own line and is used for crafting costs." }
end
