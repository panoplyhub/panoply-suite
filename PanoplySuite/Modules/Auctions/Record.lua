-- Auctions: the record (Step 2 item F, docs/step2/DEF-SPEC.md section F, decisions 12, 13 and 14 in docs/step2/DECISIONS.md).
-- What Panoply Suite keeps about the auction house, on this computer only, as it happens:
--   * the LAST SCAN of each realm + faction, as ONE SUMMARY PER ITEM (0.9.5 phase 4E, docs/specs/page-redesigns-v1.md 7.2): the
--     lowest buyout each, the market price (the median of the each-prices, weighted by quantity), the total quantity, the number of
--     listings, and a short trend (the lowest and market prices of up to 13 earlier scan days within 14 days). Every item of the scan
--     is kept: there is no cap on items or auctions any more. The single auctions are kept only for items on a shopping list
--     (at most R.WATCH_ITEMS items, the R.WATCH_ROWS cheapest auctions of each);
--   * for each character: what it listed, bought and sold, and what did not sell (expired or cancelled).
-- Saved data, inside PanoplySuiteAuctionDB (account wide: any character can look at any record, decision 14):
--   agg[realm-faction] = { v = 1, t, kind, full, n (auctions read), items (how many items), pages, of, summary, migrated,
--                          rows = { [itemKey] = "low,market,qty,listings,class;ago,low,market;..." },
--                          watch = { [itemKey] = "stack,buyout,bid,seller,left;..." }, sellers = { "name", ... } }
--       itemKey as Prices.ItemKey; low / market 0 = no buyout in the scan; class = the game's item class (-1 = not known when it was
--       saved); "ago" = whole days before this scan (1 to 13), one point a day, the newest scan of a day standing for it.
--   snaps[realm-faction]  the OLD per-auction scans (0.7.4 to 0.9.4). Read once into agg (R.Migrate) and kept, untouched, until a new
--                         scan of the same realm + faction replaces it (as 0.9.4 itself would have); nothing new is written there.
--   rec[realmGroup][character] = { f = faction, seen = time, mail = { "subject|minute" ... },
--                                  listed / sold / bought / unsold = { "csv row", ... } }
-- Rows are text, not tables: a Lua table per item costs several times more in the saved file and in memory.
-- Caps (decision 12): one scan per realm + faction, at most 3 realm-factions; 300 sold + 200 bought + 300 did not sell + 100
-- still-listed rows per character, 20 characters; 8 MB in all for everything Panoply Suite saves for the auction house (the price
-- history of Prices.lua counts too). Over 8 MB only data that can be made again or is
-- stale goes, in this order: scans not refreshed for 14 days, other realm-factions' scans (never your own faction's, never the auction house
-- you are at), characters not played for 90 days, price history older than 14 days (oldest realm first, never below a realm's last 14 days,
-- never a realm wholesale). Still over: nothing else is deleted; the size meter says so and the two Forget buttons free space.
-- Rule 13: a partial scan (stopped, or a browse, which saves only the lowest price of each item) never replaces a full scan younger
-- than 24 hours.
-- Reads game events and data only. It never asks the auction house for anything and never calls a protected function.
-- UNVERIFIED in a real client (only the game can show): the text of the sold / won chat lines and of the mail subjects (this
-- file matches the game's own global strings, never typed English, and does nothing for a string the client lacks), what
-- GetInboxInvoiceInfo returns without the mail being opened, the seller name and the time left of every auction in a full scan on
-- Era 1.15 and on Forever, GetReplicateItemTimeLeft's values, and the hook points of the game's own post, cancel and buy.
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = Panoply.Prices
local Auc = Panoply.Auctions
local R = {}
Auc.Record = R

R.MB = 1048576
R.BUDGET = 8 * R.MB                 -- bytes of saved auction data in all
R.MAX_SELLERS, R.MAX_SNAPS = 3000, 3      -- sellers named in the kept auctions; realm-factions with a saved scan
R.TREND = 14                        -- trend points of an item at most (this scan and 13 earlier days), none older than 14 days
R.WATCH_ITEMS, R.WATCH_ROWS = 200, 50     -- items whose single auctions are kept (on a shopping list), and auctions each
R.CAPS = { sold = 300, bought = 200, unsold = 300, listed = 100 }
R.MAX_CHARS = 20
R.MAX_MAIL = 80                     -- mails remembered per character so one is never counted twice
R.FULL_KEEP = 24 * 3600             -- a partial scan never replaces a full one younger than this
R.STALE_SNAP = 14 * 86400           -- over the budget: scans older than this go first
R.STALE_HISTORY_DAYS = 14           -- price history older than this (a realm keeps its last 14 days)
R.STALE_CHAR = 90 * 86400           -- characters not played for this long
R.errors = {}

local function now() return P.Now() end
local function floor(v) return math.floor(v + 0.0000001) end

-------------------------------------------------------------------------------
-- Where things are saved
-------------------------------------------------------------------------------
-- the saved scans (one summary per item, 0.9.5); the old per-auction scans of the same save are read into them once
function R.Snaps()
  local db = P.DB()
  if type(db.agg) ~= "table" then db.agg = {} end
  if R.migratedDB ~= db then R.migratedDB = db R.Migrate(db) end
  return db.agg
end
-- the migration runs at login (behind the loading screen), not in whatever first asks, such as an item tooltip
Panoply:On("PLAYER_LOGIN", function() local ok, err = pcall(R.Snaps) if not ok then R.errors.migrate = tostring(err) end end)
-- the old per-auction scans (0.7.4 to 0.9.4), or nil
function R.OldSnaps() local s = P.DB().snaps return type(s) == "table" and s or nil end
function R.Chars()
  local db = P.DB()
  if type(db.rec) ~= "table" then db.rec = {} end
  return db.rec
end
function R.Snap(key) return R.Snaps()[key or P.Key()] end

-- The key of the scan to look at when nobody chose one. P.Key() follows the auction house you are standing at (a neutral house has
-- its own key only while it is open), so a Neutral scan saved at Booty Bay would be unreachable once the window closed. This is the
-- most recently taken scan of this realm: this character's own key wins a tie, then the newest. Falls back to P.Key() with no scan.
function R.LatestKey()
  local own = P.Key()
  local snaps = R.Snaps()
  local realm = P.RealmGroup()
  local best, bt = nil, -1
  for k, s in pairs(snaps) do
    if type(k) == "string" and type(s) == "table" and type(s.rows) == "table" and k:match("^(.*)%-[^%-]*$") == realm then
      local t = tonumber(s.t) or 0
      if t > bt or (t == bt and k == own) then best, bt = k, t end
    end
  end
  return best or own
end

-- The key of a realm for the record: connected realms share one (the alphabetically first), like the prices do.
function R.RealmKey(realm)
  local n = P.Norm(realm)
  if not n or n == "" or n == P.RealmName() then return P.RealmGroup() end
  local list = _G.GetAutoCompleteRealms and { C.pc(_G.GetAutoCompleteRealms) } or {}
  if type(list[1]) == "table" then list = list[1] end
  for _, r in ipairs(list) do if P.Norm(r) == n then return P.RealmGroup() end end
  return n
end
-- the key of the scan of a realm + faction (nil realm: this character's)
function R.SnapKey(realm, faction)
  if not realm or realm == "" then return P.Key() end
  return R.RealmKey(realm) .. "-" .. ((faction and faction ~= "") and faction or P.Faction())
end
local function realmOfKey(key) return tostring(key or ""):match("^(.*)%-[^%-]*$") or tostring(key or "") end
function R.RealmOfSnapKey(key) return realmOfKey(key) end
function R.FactionOfSnapKey(key) return tostring(key or ""):match("%-([^%-]*)$") or "" end

-- when the saved scan of a realm + faction was taken (0 = none). Home and the Auctions page show this one number, so they agree
-- with the browser. A save from before the record has only the time of the last full scan.
function R.ScanTime(key)
  local s = R.Snap(key)
  if s and tonumber(s.t) then return s.t end
  local r = P.DB().realms[key or P.Key()]
  return r and tonumber(r.lastScan) or 0
end

-------------------------------------------------------------------------------
-- Words and numbers
-------------------------------------------------------------------------------
function R.Commas(n)
  local s = tostring(floor(tonumber(n) or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
-- seconds -> "12 minutes ago", "3 hours ago", "4 days ago"
function R.Ago(sec)
  if not sec or sec < 0 then sec = 0 end
  if sec < 90 then return "just now" end
  local m = floor(sec / 60 + 0.5)
  if sec < 90 * 60 then return m .. (m == 1 and " minute ago" or " minutes ago") end
  local h = floor(sec / 3600 + 0.5)
  if sec < 36 * 3600 then return h .. (h == 1 and " hour ago" or " hours ago") end
  local d = floor(sec / 86400 + 0.5)
  return d .. (d == 1 and " day ago" or " days ago")
end
function R.MBText(bytes)
  local mb = (bytes or 0) / R.MB
  if mb < 0.05 then return "under 0.1 MB" end
  return ("about %.1f MB"):format(mb)
end

-------------------------------------------------------------------------------
-- The size of what is saved. Lua cannot read a file's size, so this adds up what the game's writer produces for the same data:
-- one line for each entry, a tab for each level of nesting, ["key"] = value, a comma, and " -- [n]" after an array entry.
-- (tests/auctions_record_tests.lua checks it against a writer of that format on the real data.)
-------------------------------------------------------------------------------
local function qlen(s)
  local n = #s + 2
  if s:find('[\\"%c]') then
    local _, a = s:gsub('[\\"]', "")
    local _, b = s:gsub("%c", "")
    n = n + a + b * 3
  end
  return n
end
local function keyLen(k)
  if type(k) == "number" then return #tostring(k) + 5 end              -- [123] =
  return qlen(tostring(k)) + 5                                          -- ["name"] =
end
local sizeOf
-- the bytes of one value (a table counts its braces and everything inside), no key, no comma
local function valueLen(v, depth)
  local t = type(v)
  if t == "string" then return qlen(v) end
  if t == "number" then return #tostring(v) end
  if t == "boolean" then return v and 4 or 5 end
  if t == "table" then return sizeOf(v, depth) end
  return 3
end
-- The price history and the scans are tables of plain strings (digits, commas, semicolons: nothing to escape), by far the largest part
-- of what is saved: each is measured by its length alone, which is about ten times faster than looking inside every string.
local function itemsSize(items, depth)
  local n = 3 + (depth - 1)
  local arr = #items                                   -- numbers 1 to arr in a row are written as an array: one byte more each
  for k, v in pairs(items) do
    local kl
    if type(k) == "number" and k >= 0 and k < 1000000 and k % 1 == 0 then
      kl = k < 10 and 6 or k < 100 and 7 or k < 1000 and 8 or k < 10000 and 9 or k < 100000 and 10 or 11
      if k >= 1 and k <= arr then n = n + 1 end
    else kl = keyLen(k) end
    n = n + depth + 2 + kl + (type(v) == "string" and #v + 2 or valueLen(v, depth + 1))
  end
  return n
end
-- a table whose entries sit `depth` tabs in: "{\n" + entries + tabs and "}"
sizeOf = function(tbl, depth)
  local n = 3 + (depth - 1)                      -- "{" "\n" and the closing tabs + "}"
  local arr = #tbl
  for k, v in pairs(tbl) do
    local isArr = type(k) == "number" and k >= 1 and k <= arr and k == math.floor(k)
    local vlen
    if k == "items" and depth == 3 and type(v) == "table" then vlen = itemsSize(v, depth + 1) else vlen = valueLen(v, depth + 1) end
    local line = depth + vlen + 2                                -- the tabs, the value, ",\n"
    if isArr then line = line + 5 + #tostring(k) + 1 else line = line + keyLen(k) end   -- " -- [" n "]"  |  the key
    n = n + line
  end
  return n
end
R.SizeOf = sizeOf
R.TableSize = function(tbl) return sizeOf(tbl, 1) end
-- one realm's price data inside the saved file, as an entry of `realms`
function R.RealmBytes(key, r) return 2 + keyLen(key) + valueLen(r, 3) + 2 end

local snapSize = setmetatable({}, { __mode = "k" })      -- a stored scan never changes: measured once
local function snapBytes(s)
  local b = snapSize[s]
  if not b then b = sizeOf(s, 3) snapSize[s] = b end
  return b
end

-- { total, prices, scans, history, perScan = { [key] = bytes } } of PanoplySuiteAuctionDB, in bytes. Measures everything once.
function R.Sizes()
  local db = P.DB()
  local out = { prices = 0, scans = 0, history = 0, other = 0, perScan = {} }
  -- each top-level entry: one tab, its key, the value, ",\n"
  for k, v in pairs(db) do
    if k == "realms" then out.prices = out.prices + 1 + keyLen(k) + valueLen(v, 2) + 2
    elseif (k == "agg" or k == "snaps") and type(v) == "table" then
      -- the scans (agg) and the old per-auction scans still waiting to be replaced (snaps): perScan is both of a key
      local n = 4                                                      -- "{\n" and the closing tab + "}"
      for key, s in pairs(v) do
        local b = type(s) == "table" and snapBytes(s) or valueLen(s, 3)
        out.perScan[key] = (out.perScan[key] or 0) + 2 + keyLen(key) + b + 2
        n = n + 2 + keyLen(key) + b + 2                                -- two tabs, the key, the scan, ",\n"
      end
      out.scans = out.scans + 1 + keyLen(k) + n + 2
    elseif k == "rec" then out.history = out.history + 1 + keyLen(k) + valueLen(v, 2) + 2
    else out.other = out.other + 1 + keyLen(k) + valueLen(v, 2) + 2 end
  end
  out.total = out.prices + out.scans + out.history + out.other + #"PanoplySuiteAuctionDB = {\n}\n"
  return out
end
function R.Bytes() return R.Sizes().total end
-- "Saved on this computer: about 0.6 MB of 8 MB" (the gear and the Auctions page); over the limit it says so and what frees space.
-- The window's footer is short: no "of 8 MB" (F-01).
function R.MeterText(bytes)
  bytes = bytes or R.Bytes()
  local mb = floor(R.BUDGET / R.MB)
  if bytes > R.BUDGET then
    return ("Saved on this computer: %s: over the %d MB limit. Nothing was deleted to make room; the Forget buttons in the Auctions settings free space."):format(R.MBText(bytes), mb)
  end
  return ("Saved on this computer: %s of %d MB"):format(R.MBText(bytes), mb)
end
function R.MeterShort(bytes)
  bytes = bytes or R.Bytes()
  if bytes > R.BUDGET then return ("Saved on this computer: %s, over the %d MB limit"):format(R.MBText(bytes), floor(R.BUDGET / R.MB)) end
  return ("Saved on this computer: %s"):format(R.MBText(bytes))
end

-------------------------------------------------------------------------------
-- Scan rows: "stack,buyout,bid,seller,left;" for each auction, grouped by item
--   seller = a number in the scan's seller list (0 = the game did not give one), left = 1 Short .. 4 Very long (0 = not given),
--   bid = the current bid, or the starting bid when nobody bid, buyout 0 = bid only.
-------------------------------------------------------------------------------
-- The time left of an auction as 1 Short, 2 Medium, 3 Long, 4 Very long (0 = the game did not say). The Era list answers 1 to 4; a
-- client that counts the bands from 0 (zeroBased) or answers in seconds is turned into the same four steps.
function R.Band(v, zeroBased)
  v = tonumber(C.Readable(v))
  if not v then return 0 end
  if v > 4 then
    if v <= 1800 then return 1 elseif v <= 7200 then return 2 elseif v <= 43200 then return 3 end
    return 4
  end
  if zeroBased then v = v + 1 end
  if v >= 1 and v <= 4 then return floor(v) end
  return 0
end
-- the words for the four steps: the game's own where it gives short ones (AUCTION_TIME_LEFT1 .. 4), else these
R.BAND_WORDS = { "Short", "Medium", "Long", "Very long" }
function R.BandText(b)
  if not b or b < 1 or b > 4 then return "" end
  local g = _G["AUCTION_TIME_LEFT" .. b]
  if type(g) == "string" and g ~= "" and #g <= 12 and not g:find("%(") then return g end
  return R.BAND_WORDS[b]
end

local Snap = {}
Snap.__index = Snap
function R.NewSnap(kind)
  return setmetatable({ kind = kind, items = {}, n = 0, seen = {}, sellers = {}, nSellers = 0 }, Snap)
end
local function whole(v) v = tonumber(v) or 0 if v ~= v or v < 0 or v == math.huge then return 0 end return floor(v) end

function Snap:Add(itemKey, stack, buyout, bid, owner, left)
  if itemKey == nil then return end
  local idx = 0
  owner = C.Readable(owner)
  if type(owner) == "string" and owner ~= "" then
    idx = self.seen[owner]
    if not idx then
      if self.nSellers < R.MAX_SELLERS then
        self.nSellers = self.nSellers + 1
        idx = self.nSellers
        self.seen[owner] = idx
        self.sellers[idx] = owner
      else idx = 0 end
    end
  end
  local list = self.items[itemKey]
  if not list then list = {} self.items[itemKey] = list end
  list[#list + 1] = ("%d,%d,%d,%d,%d"):format(math.max(1, whole(stack)), whole(buyout), whole(bid), idx, whole(left))
  self.n = self.n + 1
end

-- the price of one item in a row (huge when the row has no buyout)
local function eachOf(row)
  local st, bo = row:match("^(%d+),(%d+),")
  st, bo = tonumber(st), tonumber(bo)
  if not st or not bo or bo == 0 then return math.huge end
  return bo / st
end

-- The market price of an item: the median of its each-prices weighted by quantity (pairs = { each, qty, each, qty, ... }, sorted by
-- each here). The each-price at which half of all the listed items (counted one by one) are reached.
function R.Market(pairs_)
  local list = {}
  for i = 1, #pairs_, 2 do list[#list + 1] = { pairs_[i], pairs_[i + 1] } end
  if #list == 0 then return 0 end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local half, cum = total / 2, 0
  for _, e in ipairs(list) do
    cum = cum + e[2]
    if cum >= half then return e[1] end
  end
  return list[#list][1]
end

-- An item summary as a string, and back. head = { low, market, qty, listings, class } in decimal; trend = { { ago, low, market }, ... },
-- each point written in base 36 to keep the saved file small ("1,ekc,ezo"), its market left empty when it equals its lowest ("1,ekc,").
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = floor(tonumber(n) or 0)
  if n <= 0 then return "0" end
  local out = ""
  while n > 0 do
    local d = n % 36
    out = B36:sub(d + 1, d + 1) .. out
    n = floor(n / 36)
  end
  return out
end
R.B36 = b36
local function encodeItem(low, market, qty, listings, class, trend)
  local out = { ("%d,%d,%d,%d,%d"):format(low, market, qty, listings, class) }
  for _, e in ipairs(trend or {}) do
    out[#out + 1] = b36(e[1]) .. "," .. b36(e[2]) .. "," .. (e[3] == e[2] and "" or b36(e[3]))
  end
  return table.concat(out, ";")
end
R.EncodeItem = encodeItem
function R.DecodeItem(str)
  if type(str) ~= "string" then return nil end
  local low, market, qty, listings, class, rest = str:match("^(%d+),(%d+),(%d+),(%d+),(%-?%d+);?(.*)$")
  if not low then return nil end
  local it = { low = tonumber(low), market = tonumber(market), qty = tonumber(qty), listings = tonumber(listings), class = tonumber(class), trend = {} }
  for ago, l, m in rest:gmatch("([%w]+),([%w]+),([%w]*)") do
    local lv = tonumber(l, 36)
    it.trend[#it.trend + 1] = { tonumber(ago, 36), lv, m == "" and lv or tonumber(m, 36) }
  end
  return it
end

-- The trend of an item: this scan's point and the earlier ones of the scan this one replaces (prev: that scan's item string,
-- shift: days between the two scans). One point a day; at most R.TREND points; none older than R.TREND days.
local function mergeTrend(prevStr, shift)
  if not prevStr or not shift or shift < 0 then return {} end
  local old = R.DecodeItem(prevStr)
  if not old then return {} end
  local out = {}
  if shift >= 1 and shift < R.TREND and (old.low > 0 or old.market > 0) then out[#out + 1] = { shift, old.low, old.market } end
  for _, e in ipairs(old.trend) do
    local ago = e[1] + shift
    if ago >= 1 and ago < R.TREND and #out < R.TREND - 1 then
      if not (out[#out] and out[#out][1] == ago) then out[#out + 1] = { ago, e[2], e[3] } end
    end
  end
  return out
end
R.MergeTrend = mergeTrend

-- The items whose single auctions are kept: the exact item names on the Auctions shopping lists (lower case). nil when there is none.
function R.WatchNames()
  local lists = Panoply.db and Panoply.db.auctionLists
  if type(lists) ~= "table" then return nil end
  local names, any = {}, false
  for _, l in ipairs(lists) do
    for _, term in ipairs(type(l) == "table" and type(l.terms) == "table" and l.terms or {}) do
      if type(term) == "string" and term ~= "" then names[term:lower()] = true any = true end
    end
  end
  return any and names or nil
end

-- The finished scan (strings, ready to save): one summary per item. full: every page was read. extra: { pages, of, summary, watch }
-- prev: the saved scan of the same realm + faction (its points become this one's trend)
function Snap:Build(t, full, extra, prev)
  extra = extra or {}
  local day = floor((t or 0) / 86400)
  local prevRows, shift = nil, nil
  if type(prev) == "table" and type(prev.rows) == "table" and tonumber(prev.t) then
    prevRows, shift = prev.rows, day - floor(prev.t / 86400)
  end
  local watch = extra.watch
  if watch == nil then watch = R.WatchNames() end
  local rows, kept, sellers, seen, nSellers, watched = {}, {}, {}, {}, 0, 0
  local count = 0
  for key, list in pairs(self.items) do
    if #list > 0 then
      local low, qty, pairs_ = nil, 0, {}
      for _, row in ipairs(list) do
        local st, bo = row:match("^(%d+),(%d+),")
        st, bo = tonumber(st) or 1, tonumber(bo) or 0
        qty = qty + st
        if bo > 0 then
          local each = bo / st
          if not low or each < low then low = each end
          pairs_[#pairs_ + 1] = each
          pairs_[#pairs_ + 1] = st
        end
      end
      -- a browse (summary) gives only the lowest price of each item: no market price can be worked out from it
      local market = extra.summary and 0 or R.Market(pairs_)
      local id = P.KeyID(key)
      local ii = id and C.ItemInfo(id)
      local class = (ii and tonumber(ii.classID)) or -1
      local trend = prevRows and mergeTrend(prevRows[key], shift) or nil
      rows[key] = encodeItem(low and floor(low + 0.5) or 0, floor(market + 0.5), qty, #list, class, trend)
      count = count + 1
      -- the single auctions of an item on a shopping list: the cheapest first, their sellers numbered again
      local name = watch and not extra.summary and ii and ii.name
      if name and watch[name:lower()] and watched < R.WATCH_ITEMS then
        watched = watched + 1
        local tmp = {}
        for i, row in ipairs(list) do tmp[i] = { eachOf(row), row } end
        table.sort(tmp, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
        local out = {}
        for i = 1, math.min(#tmp, R.WATCH_ROWS) do
          local st, bo, bid, sel, left = tmp[i][2]:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
          local owner = self.sellers[tonumber(sel) or 0]
          local idx = 0
          if owner then
            idx = seen[owner]
            if not idx then nSellers = nSellers + 1 idx = nSellers seen[owner] = idx sellers[idx] = owner end
          end
          out[#out + 1] = ("%s,%s,%s,%d,%s;"):format(st, bo, bid, idx, left)
        end
        kept[key] = table.concat(out)
      end
    end
  end
  return { v = 1, t = t, kind = self.kind, full = full and true or false, n = self.n, items = count,
    pages = extra.pages, of = extra.of, summary = extra.summary or nil, rows = rows,
    watch = next(kept) and kept or nil, sellers = nSellers > 0 and sellers or nil }
end

-- One item of a scan as numbers: { key, low, market, qty, listings, class, trend = { { ago, low, market } ... } }; low / market are
-- nil when the scan had no buyout of it.
function R.Item(snap, key)
  local it = type(snap) == "table" and type(snap.rows) == "table" and R.DecodeItem(snap.rows[key]) or nil
  if not it then return nil end
  it.key = key
  if it.low == 0 then it.low = nil end
  if it.market == 0 then it.market = nil end
  if it.class < 0 then it.class = nil end
  return it
end
-- Every item of a scan, as R.Item
function R.Items(snap)
  local out = {}
  if type(snap) ~= "table" or type(snap.rows) ~= "table" then return out end
  for key in pairs(snap.rows) do
    local it = R.Item(snap, key)
    if it then out[#out + 1] = it end
  end
  return out
end
-- The kept single auctions of an item (only items on a shopping list have them), cheapest first:
-- { { stack, buyout, bid, seller (name or nil), left, each } ... }, or nil
function R.Listings(snap, key)
  local s = type(snap) == "table" and type(snap.watch) == "table" and snap.watch[key]
  if type(s) ~= "string" then return nil end
  local sellers, out = snap.sellers or {}, {}
  for stack, buyout, bid, sel, left in s:gmatch("(%d+),(%d+),(%d+),(%d+),(%d+);") do
    stack, buyout = tonumber(stack), tonumber(buyout)
    out[#out + 1] = { stack = stack, buyout = buyout, bid = tonumber(bid), seller = sellers[tonumber(sel)], left = tonumber(left),
      each = buyout > 0 and buyout / stack or nil }
  end
  return out
end

-- The rows of an OLD per-auction scan (0.7.4 to 0.9.4) as an array of { key, stack, buyout, bid, seller (name or nil), left, each }.
-- Only the migration reads these.
function R.RawRows(snap)
  local rows, n = {}, 0
  if type(snap) ~= "table" then return rows end
  local sellers = snap.sellers or {}
  for key, s in pairs(snap.items or {}) do
    if type(s) == "string" then
      for stack, buyout, bid, sel, left in s:gmatch("(%d+),(%d+),(%d+),(%d+),(%d+);") do
        stack, buyout = tonumber(stack), tonumber(buyout)
        n = n + 1
        rows[n] = { key = key, stack = stack, buyout = buyout, bid = tonumber(bid), seller = sellers[tonumber(sel)], left = tonumber(left),
          each = buyout > 0 and buyout / stack or nil }
      end
    end
  end
  return rows
end

-- 0.9.5: the old per-auction scans of this save are read into item summaries, once. The old scan stays as it is until a new scan of
-- its realm + faction replaces it. A scan that cannot be read is left alone (and not summarised). Returns how many were read.
function R.Migrate(db)
  db = db or P.DB()
  if type(db.snaps) ~= "table" then return 0 end
  if type(db.agg) ~= "table" then db.agg = {} end
  local n = 0
  for k, old in pairs(db.snaps) do
    if type(k) == "string" and type(old) == "table" and type(old.items) == "table" and db.agg[k] == nil then
      local ok, agg = pcall(function()
        local sn = R.NewSnap(old.kind)
        for _, r in ipairs(R.RawRows(old)) do sn:Add(r.key, r.stack, r.buyout, r.bid, r.seller, r.left) end
        local a = sn:Build(tonumber(old.t) or 0, old.full, { pages = old.pages, of = old.of, summary = old.summary })
        a.n = tonumber(old.n) or a.n            -- the auctions that scan read (it saved at most 40,000 of them)
        a.migrated = true
        return a
      end)
      if ok and type(agg) == "table" and agg.items > 0 then db.agg[k] = agg n = n + 1
      elseif not ok then R.errors.migrate = tostring(agg) Panoply:Debug("auction record: migrate", agg) end
    end
  end
  return n
end

-- Rule 13: store a scan. Returns true when it was saved, or false and why ("kept": a full scan younger than 24 hours stays).
-- The old per-auction scan of the same realm + faction (0.9.4) goes now: this scan replaces it.
function R.Store(snap, key)
  key = key or P.Key()
  local snaps = R.Snaps()
  local old = snaps[key]
  if old and not snap.full and old.full and (snap.t - (old.t or 0)) < R.FULL_KEEP then return false, "kept", old end
  snaps[key] = snap
  local raw = R.OldSnaps()
  if raw then raw[key] = nil end
  R.TrimScans(key)
  Panoply:Fire("AUCTION_RECORD_CHANGED", "scan", key)
  return true
end
-- at most three realm-factions: the one scanned longest ago goes
function R.TrimScans(keep)
  R.Repair()
  local snaps = R.Snaps()
  local list = {}
  for k, s in pairs(snaps) do list[#list + 1] = k end
  if #list <= R.MAX_SNAPS then return 0 end
  table.sort(list, function(a, b) local x, y = snaps[a].t or 0, snaps[b].t or 0 if x ~= y then return x < y end return tostring(a) < tostring(b) end)
  local dropped = 0
  local raw = R.OldSnaps()
  for _, k in ipairs(list) do
    if #list - dropped <= R.MAX_SNAPS then break end
    if k ~= keep then snaps[k] = nil if raw then raw[k] = nil end dropped = dropped + 1 end
  end
  return dropped
end

-- Called when a scan finishes (Auctions.lua Commit). Never raises: the prices are already saved and must stay saved.
function R.FinishScan(scan, full, t)
  if not scan or not scan.rec then return nil end
  local ok, res, why = pcall(function()
    -- a browse saves only the lowest price of each item: it is never a full scan, whatever the game says about its list (decision 13)
    local key = P.Key()
    local snap = scan.rec:Build(t, full and scan.kind ~= "browse", { pages = scan.pagesRead, of = scan.pages, summary = scan.kind == "browse" }, R.Snap(key))
    if snap.items == 0 then return false, "empty" end
    local saved, w = R.Store(snap, key)
    R.SafeEnforce(true)
    return saved, w
  end)
  if not ok then R.errors.scan = tostring(res) Panoply:Debug("auction record: scan", res) return nil end
  return res, why
end

-------------------------------------------------------------------------------
-- Characters and their rows
-------------------------------------------------------------------------------
-- A row is one line of text. Numbers come first, text last. In the text fields a comma, a semicolon, a bar, a percent sign and control
-- characters are written as %xx and read back as they were, so a name is never changed. `nh` is a hash of the whole item name: a sale
-- is matched to its listing by it when the game does not give the item (not loaded yet at the mailbox).
R.KINDS = {
  listed = { "t", "id", "stack", "buyout", "bid", "hours", "deposit", "nh", "name" },
  sold = { "t", "id", "stack", "price", "got", "who", "src", "nh", "name" },
  bought = { "t", "id", "stack", "paid", "who", "src", "nh", "name" },
  unsold = { "t", "id", "stack", "price", "how", "deposit", "nh", "name" },
}
local TEXT = { who = true, src = true, how = true, name = true, nh = true }
local function esc1(ch) return ("%%%02x"):format(ch:byte()) end
local function txt(s) return (tostring(s or ""):sub(1, 120):gsub("[%%,;|%c]", esc1)) end
local function untxt(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
function R.Encode(kind, row)
  local out = {}
  for i, f in ipairs(R.KINDS[kind]) do
    local v = row[f]
    out[i] = TEXT[f] and txt(v) or tostring(whole(v))
  end
  return table.concat(out, ",")
end
function R.Decode(kind, s)
  local row, i = {}, 0
  local fields = R.KINDS[kind]
  for part in (tostring(s) .. ","):gmatch("([^,]*),") do
    i = i + 1
    local f = fields[i]
    if not f then break end
    if TEXT[f] then row[f] = part ~= "" and untxt(part) or nil else row[f] = tonumber(part) or 0 end
  end
  return row
end
-- a hash of a whole item name (colours and brackets off, capitals ignored): 8 hex digits, "" for no name
function R.NameHash(name)
  if type(name) ~= "string" or name == "" then return "" end
  local s = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*%[", ""):gsub("%]%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if s == "" then return "" end
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967291 end
  return ("%08x"):format(h)
end

function R.TrimChars(keepRealm, keepName)
  local all = R.Chars()
  local list, n = {}, 0
  for rk, chars in pairs(all) do
    for name, c in pairs(chars) do n = n + 1 list[#list + 1] = { rk, name, type(c) == "table" and c.seen or 0 } end
  end
  if n <= R.MAX_CHARS then return 0 end
  table.sort(list, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end return a[1] .. a[2] < b[1] .. b[2] end)
  local dropped = 0
  for _, e in ipairs(list) do
    if n - dropped <= R.MAX_CHARS then break end
    if not (e[1] == keepRealm and e[2] == keepName) then
      all[e[1]][e[2]] = nil
      if next(all[e[1]]) == nil then all[e[1]] = nil end
      dropped = dropped + 1
    end
  end
  return dropped
end

function R.CharRec(realmKey, name, create)
  local all = R.Chars()
  local r = all[realmKey]
  if type(r) ~= "table" then
    if not create then return nil end
    r = {} all[realmKey] = r
  end
  local c = r[name]
  if type(c) ~= "table" then
    if not create then return nil end
    c = { seen = now(), listed = {}, sold = {}, bought = {}, unsold = {} }
    r[name] = c
    R.TrimChars(realmKey, name)
  end
  for _, k in ipairs({ "listed", "sold", "bought", "unsold" }) do if type(c[k]) ~= "table" then c[k] = {} end end
  return c
end
-- the character being played (made on first use): the record, the realm key, the name
function R.Me()
  local p = C.PlayerInfo()
  if type(p.name) ~= "string" or p.name == "" then return nil end
  local rk = P.RealmGroup()
  local c = R.CharRec(rk, p.name, true)
  c.seen = now()
  if type(p.faction) == "string" then c.f = p.faction end
  return c, rk, p.name
end

local function push(c, kind, row)
  local list = c[kind]
  list[#list + 1] = R.Encode(kind, row)
  while #list > R.CAPS[kind] do table.remove(list, 1) end
end
-- A damaged save (a value of the wrong kind where a scan or a character should be) is put right, never raised at the player:
-- what cannot be read is dropped.
function R.Repair()
  local db = P.DB()
  if db.agg ~= nil and type(db.agg) ~= "table" then db.agg = {} end
  for k, s in pairs(db.agg or {}) do
    if type(k) ~= "string" or type(s) ~= "table" or type(s.rows) ~= "table" then db.agg[k] = nil
    else
      if s.watch ~= nil and type(s.watch) ~= "table" then s.watch = nil end
      if s.sellers ~= nil and type(s.sellers) ~= "table" then s.sellers = nil end
      if tonumber(s.t) == nil then s.t = 0 end
    end
  end
  if db.snaps ~= nil and type(db.snaps) ~= "table" then db.snaps = {} end
  for k, s in pairs(db.snaps or {}) do
    if type(k) ~= "string" or type(s) ~= "table" or type(s.items) ~= "table" then db.snaps[k] = nil
    else
      if type(s.sellers) ~= "table" then s.sellers = {} end
      if tonumber(s.t) == nil then s.t = 0 end
    end
  end
  if db.rec ~= nil and type(db.rec) ~= "table" then db.rec = {} end
  for rk, chars in pairs(db.rec or {}) do
    if type(rk) ~= "string" or type(chars) ~= "table" then db.rec[rk] = nil
    else
      for name, c in pairs(chars) do
        if type(name) ~= "string" or type(c) ~= "table" then chars[name] = nil
        else
          for _, kind in ipairs({ "listed", "sold", "bought", "unsold" }) do if type(c[kind]) ~= "table" then c[kind] = {} end end
          if type(c.mail) ~= "table" then c.mail = nil end
          c.seen = tonumber(c.seen) or 0
        end
      end
    end
  end
end
-- apply every cap to what is saved (a save from another version, or hand-edited)
function R.Normalize()
  R.Repair()
  R.TrimScans()
  R.TrimChars()
  for _, chars in pairs(R.Chars()) do
    for _, c in pairs(chars) do
      if type(c) == "table" then
        for kind, cap in pairs(R.CAPS) do
          if type(c[kind]) == "table" then while #c[kind] > cap do table.remove(c[kind], 1) end end
        end
        if type(c.mail) == "table" then while #c.mail > R.MAX_MAIL do table.remove(c.mail, 1) end end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Items by name
-------------------------------------------------------------------------------
local function idFromLink(s) return tonumber(tostring(s or ""):match("item:(%d+)")) end
local function nameFromText(s)
  s = tostring(s or "")
  local n = s:match("|h%[(.-)%]|h") or s:match("^%[(.-)%]$") or s
  return (n:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
function R.ItemName(id, fallback)
  if id and id ~= 0 then
    local ii = C.ItemInfo(id)
    if ii and ii.name then return ii.name end
  end
  return fallback
end
-- Is the game's item (an id, a name, or both) the item of this row? By id when both have one; else by the whole name, through the hash
-- the row kept (the game need not know the item: it may not be loaded yet).
local function sameItem(row, id, name)
  if id and id ~= 0 and row.id and row.id ~= 0 then return row.id == id end
  if (not name or name == "") and id and id ~= 0 then name = R.ItemName(id) end
  local h = R.NameHash(name)
  if h == "" then return false end
  if row.nh and row.nh ~= "" then return row.nh == h end
  local mine = R.ItemName(row.id, row.name)
  return mine ~= nil and R.NameHash(mine) == h
end
-- the name hash for a row about this item: from the name the game gave, else from what the game knows of the id, else the listing's
local function hashFor(id, name, L)
  local h = R.NameHash(name)
  if h == "" and id and id ~= 0 then h = R.NameHash(R.ItemName(id)) end
  if h == "" and L then h = L.nh or "" end
  return h
end

-- The listing a sale, an expiry or a cancel closes: of the same item, preferring the same stack and the same price (so five stacks
-- that end one after another close five different listings); the oldest when nothing tells them apart. It leaves "still listed".
local function takeListed(c, id, name, stack, price)
  local best, bi, bscore
  for i, s in ipairs(c.listed) do
    local row = R.Decode("listed", s)
    if sameItem(row, id, name) then
      local score = ((stack and row.stack == stack) and 2 or 0) + ((price and price > 0 and row.buyout == price) and 1 or 0)
      if not bscore or score > bscore then best, bi, bscore = row, i, score end
    end
  end
  if not best then return nil end
  table.remove(c.listed, bi)
  return best
end

-------------------------------------------------------------------------------
-- What happened (each writes to the character being played)
-------------------------------------------------------------------------------
local function changed(kind) Panoply:Fire("AUCTION_RECORD_CHANGED", kind) end

-- you posted an auction. info = { id, name, stack, buyout, bid, hours, deposit, t, count (how many of these auctions) }
function R.NoteListed(info)
  local c = R.Me()
  if not c or not info or not info.id then return false end
  local nh = hashFor(info.id, info.name)
  for _ = 1, math.max(1, math.min(R.CAPS.listed, floor(info.count or 1))) do
    push(c, "listed", { t = info.t or now(), id = info.id, stack = info.stack or 1, buyout = info.buyout, bid = info.bid or info.buyout,
      hours = info.hours or 24, deposit = info.deposit, nh = nh })
  end
  changed("listed")
  return true
end

-- the game said one of your auctions sold (a chat line). id or name tells which item.
function R.NoteSoldMessage(id, name, t)
  local c = R.Me()
  if not c then return false end
  local L = takeListed(c, id, name)
  local rid = (id and id ~= 0 and id) or (L and L.id) or 0
  push(c, "sold", { t = t or now(), id = rid, stack = L and L.stack or 1, price = L and L.buyout or 0, got = 0, src = "c",
    nh = hashFor(rid, name, L), name = rid ~= 0 and "" or name })
  changed("sold")
  return true
end
-- the mail of a sale. a = { id, name, buyer, price, cut, money, t }
function R.NoteSoldMail(a)
  local c = R.Me()
  if not c then return false end
  local got = (a.price and a.price > 0) and math.max(0, a.price - (a.cut or 0)) or 0
  -- the chat line of the same sale made the row already: it gets the buyer, the price and what you received (the one with the same price first)
  local hit
  for pass = 1, 2 do
    for i, s in ipairs(c.sold) do
      local row = R.Decode("sold", s)
      if row.src == "c" and sameItem(row, a.id, a.name) and (a.t - row.t) < 35 * 86400 and (pass == 2 or (a.price and a.price > 0 and row.price == a.price)) then
        hit = { i, row } break
      end
    end
    if hit then break end
  end
  if hit then
    local row = hit[2]
    if a.price and a.price > 0 then row.price, row.got = a.price, got end
    if (a.price or 0) == 0 and (a.money or 0) > 0 then row.got = a.money end
    row.who, row.src = a.buyer, "m"
    if (row.nh or "") == "" then row.nh = hashFor(row.id, a.name) end
    c.sold[hit[1]] = R.Encode("sold", row)
    changed("sold")
    return true
  end
  -- a sale made while you were away: no chat line, only the mail; it closes one listing (the one of that price)
  local L = takeListed(c, a.id, a.name, nil, a.price)
  local price = (a.price and a.price > 0) and a.price or (L and L.buyout) or 0
  if got == 0 and (a.money or 0) > 0 then got = math.max(0, a.money - (L and L.deposit or 0)) end
  local id = (a.id and a.id ~= 0 and a.id) or (L and L.id) or 0
  push(c, "sold", { t = a.t, id = id, stack = L and L.stack or 1, price = price, got = got, who = a.buyer, src = "m",
    nh = hashFor(id, a.name, L), name = id ~= 0 and "" or a.name })
  changed("sold")
  return true
end

-- you sent a purchase (the player's click): kept until the game says it went through, and forgotten after three minutes without that
-- word, so a buyout that failed is never matched by a later "You won" for the same item
R.pending = {}
R.PENDING_SECONDS = 180
function R.ExpirePending()
  local t = C.GetTime()
  for i = #R.pending, 1, -1 do if t - (R.pending[i].at or 0) > R.PENDING_SECONDS then table.remove(R.pending, i) end end
end
function R.NoteBuyClick(info)
  if not info or not (info.id or info.name) then return false end
  R.ExpirePending()
  info.t, info.at = now(), C.GetTime()
  R.pending[#R.pending + 1] = info
  while #R.pending > 10 do table.remove(R.pending, 1) end
  C.After(R.PENDING_SECONDS + 1, function() R.ExpirePending() end)
  -- a client without the game's "you won" line cannot confirm: the mail will (and records it once)
  if not R.Matcher("ERR_AUCTION_WON_S") then return R.CommitBuy(table.remove(R.pending)) end
  return true
end
function R.CommitBuy(b)
  if not b then return false end
  local c = R.Me()
  if not c then return false end
  push(c, "bought", { t = b.t or now(), id = b.id or 0, stack = b.stack or 1, paid = b.paid or 0, who = b.seller, src = "c",
    nh = hashFor(b.id, b.name), name = (b.id and b.id ~= 0) and "" or b.name })
  changed("bought")
  return true
end
-- "You won an auction for X": the oldest waiting purchase of that item is now recorded
function R.NoteWon(id, name)
  R.ExpirePending()
  for i, b in ipairs(R.pending) do
    if sameItem({ id = b.id or 0, name = b.name, nh = R.NameHash(b.name or (b.id and R.ItemName(b.id))) }, id, name) then
      table.remove(R.pending, i)
      return R.CommitBuy(b)
    end
  end
  return false
end
-- the mail of a purchase. a = { id, name, stack, seller, paid, t }
function R.NoteBoughtMail(a)
  local c = R.Me()
  if not c then return false end
  R.ExpirePending()
  for i, s in ipairs(c.bought) do
    local row = R.Decode("bought", s)
    if row.src == "c" and sameItem(row, a.id, a.name) and (a.t - row.t) < 35 * 86400 then
      if (a.paid or 0) > 0 then row.paid = a.paid end
      if a.seller then row.who = a.seller end
      row.src = "m"
      if (row.nh or "") == "" then row.nh = hashFor(row.id, a.name) end
      c.bought[i] = R.Encode("bought", row)
      changed("bought")
      return true
    end
  end
  for i, b in ipairs(R.pending) do
    if sameItem({ id = b.id or 0, name = b.name, nh = R.NameHash(b.name or (b.id and R.ItemName(b.id))) }, a.id, a.name) then table.remove(R.pending, i) break end
  end
  push(c, "bought", { t = a.t, id = a.id or 0, stack = a.stack or 1, paid = a.paid or 0, who = a.seller, src = "m",
    nh = hashFor(a.id, a.name), name = (a.id and a.id ~= 0) and "" or a.name })
  changed("bought")
  return true
end

-- an auction ended without a sale. how = "e" expired, "c" cancelled. info = { id, name, stack, t }. It closes ONE listing.
function R.NoteUnsold(how, info)
  local c = R.Me()
  if not c or not info then return false end
  local L = takeListed(c, info.id, info.name, info.stack)
  local id = (info.id and info.id ~= 0 and info.id) or (L and L.id) or 0
  push(c, "unsold", { t = info.t or now(), id = id, stack = info.stack or (L and L.stack) or 1, price = (L and L.buyout) or info.price or 0, how = how,
    deposit = (L and L.deposit) or info.deposit or 0, nh = hashFor(id, info.name, L), name = id ~= 0 and "" or info.name })
  changed("unsold")
  return true
end

-- Rows with no item id (a sale or an expiry the game told only by name) get their id when the game has the item: GET_ITEM_INFO_RECEIVED
-- brings the ids that just arrived. No new row is made from it.
function R.ResolveWaiting(ids)
  local waiting = {}
  for _, chars in pairs(R.Chars()) do
    for _, c in pairs(chars) do
      if type(c) == "table" then
        for kind in pairs(R.KINDS) do
          for i, s in ipairs(c[kind] or {}) do
            if type(s) == "string" and s:find("^%d+,0,") then waiting[#waiting + 1] = { c, kind, i, R.Decode(kind, s) } end
          end
        end
      end
    end
  end
  if #waiting == 0 then return 0 end
  local byHash = {}
  for id in pairs(ids or {}) do
    local h = R.NameHash(R.ItemName(id))
    if h ~= "" then byHash[h] = id end
  end
  local n = 0
  for _, w in ipairs(waiting) do
    local row = w[4]
    local h = (row.nh and row.nh ~= "") and row.nh or R.NameHash(row.name)
    local id = byHash[h]
    if not id and row.name then
      local ii = C.ItemInfo(row.name)                       -- the game knows an item by its name once it has it
      id = ii and ii.link and C.ItemIDFromLink(ii.link) or nil
    end
    if id then
      row.id, row.nh, row.name = id, h, nil
      w[1][w[2]][w[3]] = R.Encode(w[2], row)
      n = n + 1
    end
  end
  if n > 0 then Panoply:Fire("AUCTION_RECORD_CHANGED", "items") end
  return n
end
R.infoIds = {}
function R.OnItemInfo(id)
  if type(id) ~= "number" then return end
  R.infoIds[id] = true
  if R.infoWait then return end
  R.infoWait = true
  C.After(1, function()
    R.infoWait = nil
    local ids = R.infoIds
    R.infoIds = {}
    local ok, err = pcall(R.ResolveWaiting, ids)
    if not ok then R.errors.resolve = tostring(err) end
  end)
end

-------------------------------------------------------------------------------
-- What the browser asks
-------------------------------------------------------------------------------
-- the characters with a record on this realm, by name
function R.CharNames(realmKey)
  local out = {}
  for name, c in pairs(R.Chars()[realmKey] or {}) do if type(c) == "table" then out[#out + 1] = name end end
  table.sort(out)
  return out
end
-- the rows of one kind, newest first: { t, id, stack, ..., char }. charName nil: every character on the realm. since: a time.
function R.History(kind, realmKey, charName, since)
  local out = {}
  for name, c in pairs(R.Chars()[realmKey] or {}) do
    if type(c) == "table" and (not charName or charName == name) then
      for _, s in ipairs(c[kind] or {}) do
        local row = R.Decode(kind, s)
        if not since or row.t >= since then row.char = name out[#out + 1] = row end
      end
    end
  end
  table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return (a.char or "") < (b.char or "") end)
  return out
end
-- { bought = { n, paid }, sold = { n, price, got, waiting }, unsold = { n, expired, cancelled, deposit }, listed = n }
function R.Totals(realmKey, charName, since)
  local T = { bought = { n = 0, paid = 0 }, sold = { n = 0, price = 0, got = 0, waiting = 0 }, unsold = { n = 0, expired = 0, cancelled = 0, deposit = 0 }, listed = 0 }
  for _, r in ipairs(R.History("bought", realmKey, charName, since)) do T.bought.n = T.bought.n + 1 T.bought.paid = T.bought.paid + r.paid end
  for _, r in ipairs(R.History("sold", realmKey, charName, since)) do
    T.sold.n = T.sold.n + 1
    T.sold.price = T.sold.price + r.price
    if r.got > 0 then T.sold.got = T.sold.got + r.got else T.sold.waiting = T.sold.waiting + 1 end
  end
  for _, r in ipairs(R.History("unsold", realmKey, charName, since)) do
    T.unsold.n = T.unsold.n + 1
    if r.how == "c" then T.unsold.cancelled = T.unsold.cancelled + 1 else T.unsold.expired = T.unsold.expired + 1 end
    T.unsold.deposit = T.unsold.deposit + r.deposit
  end
  for name, c in pairs(R.Chars()[realmKey] or {}) do
    if type(c) == "table" and (not charName or charName == name) then T.listed = T.listed + #(c.listed or {}) end
  end
  return T
end

-------------------------------------------------------------------------------
-- Forgetting
-------------------------------------------------------------------------------
-- every saved scan; returns how many
function R.ForgetScans()
  local n = 0
  local seen = {}
  for k in pairs(R.Snaps()) do seen[k] = true n = n + 1 end
  for k in pairs(R.OldSnaps() or {}) do if not seen[k] then n = n + 1 end end
  P.DB().agg = {}
  if P.DB().snaps ~= nil then P.DB().snaps = {} end
  Panoply:Fire("AUCTION_RECORD_CHANGED", "scan")
  return n
end
-- this character's rows, or every character's
function R.ForgetHistory(all)
  local n = 0
  if all then
    for _, chars in pairs(R.Chars()) do for _ in pairs(chars) do n = n + 1 end end
    P.DB().rec = {}
  else
    local p = C.PlayerInfo()
    local rk = P.RealmGroup()
    local chars = R.Chars()[rk]
    if chars and p.name and chars[p.name] then
      chars[p.name] = nil n = 1
      if next(chars) == nil then R.Chars()[rk] = nil end
    end
  end
  Panoply:Fire("AUCTION_RECORD_CHANGED", "history")
  return n
end

-------------------------------------------------------------------------------
-- The budget (decision 12): 8 MB of saved auction data in all. Over it, only what can be made again or is stale goes.
-------------------------------------------------------------------------------
-- The order, and nothing else is ever deleted:
--   a  scans not refreshed for 14 days (oldest first)
--   b  the scans of other realm-factions (oldest first); never your own faction's on this realm, never the auction house you are at
--      (a neutral one has its own key), so scanning at Booty Bay does not cost a Horde player the Horde scan
--   c  characters not played for 90 days (oldest first); a character played within 90 days is never touched
--   d  price history older than 14 days, one realm-faction at a time, the oldest first, never below a realm's newest 14 days and never
--      a realm wholesale; the history is cut in small steps over several frames (a login or a scan never stalls)
-- Still over after d: nothing more is deleted. R.over is true, the size meter says it is over and that the two Forget buttons free space.
function R.Protected()
  local own = P.Key(C.pc(_G.UnitFactionGroup, "player") or "Neutral")
  return { [own] = true, [P.Key()] = true }
end

-- the price history of one item as the string "cur,t,q;day,min,qty;...": the days up to `cutoff` (a day number) are cut; nil when
-- nothing of the item is left that is newer than the cutoff
local DAY = 86400
local function cutItem(s, cutoff)
  local head, rest = s:match("^([^;]*);?(.*)$")
  if rest == "" then                                    -- no days at all: it stays unless the item itself is that old
    local t = tonumber(head:match("^%-?%d*,(%-?%d*)")) or 0
    if t < (cutoff + 1) * DAY then return nil end
    return s
  end
  -- the days run oldest first: skip the ones up to the cutoff, keep the rest as it stands
  local from, cut = 1, false
  for d, nextPos in rest:gmatch("(%-?%d+),[^;]*;?()") do
    if tonumber(d) > cutoff then break end
    from, cut = nextPos, true
  end
  if not cut then return s end
  local kept = rest:sub(from)
  if kept == "" then
    local t = tonumber(head:match("^%-?%d*,(%-?%d*)")) or 0
    if t < (cutoff + 1) * DAY then return nil end
    return head
  end
  return head .. ";" .. kept
end
R.CutItem = cutItem

-- when a realm's newest data is from: its last full scan, else its newest item
local function realmRef(r)
  local ref = tonumber(r.lastScan) or 0
  if ref > 0 then return ref end
  for _, s in pairs(r.items) do
    local t = type(s) == "string" and tonumber(s:match("^%-?%d*,(%-?%d*)")) or 0
    if t > ref then ref = t end
  end
  return ref
end

R.CHUNK = 50                       -- price items cut in one step (about 5 ms)
-- One step of the history cut: at most R.CHUNK items. Returns true when the whole job is finished.
function R.TrimStep()
  local job = R.job
  if not job then return true end
  if not job.realm then
    job.i = job.i + 1
    local e = job.list[job.i]
    if not e or job.total <= R.BUDGET then return true end
    local r = P.DB().realms[e[1]]
    if type(r) ~= "table" or type(r.items) ~= "table" then return false end
    local keys = {}
    for k in pairs(r.items) do keys[#keys + 1] = k end
    job.realm, job.key, job.keys, job.pos = r, e[1], keys, 1
    job.cutoff = math.floor(realmRef(r) / DAY) - R.STALE_HISTORY_DAYS
    job.before = R.RealmBytes(e[1], r)
    return false
  end
  local r, items = job.realm, job.realm.items
  local last = math.min(#job.keys, job.pos + R.CHUNK - 1)
  for i = job.pos, last do
    local k = job.keys[i]
    local v = items[k]
    if type(v) == "string" then
      local new = cutItem(v, job.cutoff)
      if new ~= v then items[k] = new end
    end
  end
  job.pos = last + 1
  if job.pos > #job.keys then
    local after = R.RealmBytes(job.key, r)
    job.total = job.total - (job.before - after)
    if job.before > after then job.dropped[#job.dropped + 1] = "price history older than " .. R.STALE_HISTORY_DAYS .. " days of " .. job.key end
    job.realm = nil
  end
  return false
end
local function finishJob()
  local job = R.job
  R.job = nil
  R.over = job.total > R.BUDGET
  R.size = job.total
  if R.over then Panoply:Debug("auction record: over the budget") end
  if #job.dropped > 0 then
    R.lastDropped = job.dropped
    Panoply:Fire("AUCTION_RECORD_CHANGED", "trim")
    Panoply:Print(("Panoply Suite let go of old auction data to stay near %d MB: %s."):format(floor(R.BUDGET / R.MB), table.concat(job.dropped, ", ")))
  end
end
R.FinishJob = finishJob
local function runJob(sync)
  if sync then
    while R.job and not R.TrimStep() do end
    if R.job then finishJob() end
    return
  end
  local function step()
    if not R.job then return end
    local ok, done = pcall(R.TrimStep)
    if not ok then R.errors.trim = tostring(done) finishJob() return end
    if done then finishJob() else C.After(0, step) end
  end
  C.After(0, step)
end

-- Returns what was dropped, as words (the history cut finishes later when async). async: spread the history cut over frames.
function R.Enforce(async)
  if R.job then if async then return {} end runJob(true) end
  R.Normalize()
  local dropped = {}
  local sizes = R.Sizes()                                    -- everything is measured once
  local total = sizes.total
  R.size = total
  if total <= R.BUDGET then R.over = false return dropped end
  local t = now()
  local snaps = R.Snaps()
  local protected = R.Protected()
  -- a, b: scans
  local raw = R.OldSnaps()
  local function scanEntry(k) return sizes.perScan[k] or 0 end
  local function dropScans(list)
    for _, k in ipairs(list) do
      if total <= R.BUDGET then return end
      total = total - scanEntry(k)
      snaps[k] = nil
      if raw then raw[k] = nil end
      dropped[#dropped + 1] = "the scan of " .. k
    end
  end
  local function byAge(keys) table.sort(keys, function(a, b) local x, y = snaps[a].t or 0, snaps[b].t or 0 if x ~= y then return x < y end return tostring(a) < tostring(b) end) return keys end
  local stale, others = {}, {}
  for k, sn in pairs(snaps) do
    if t - (sn.t or 0) > R.STALE_SNAP then stale[#stale + 1] = k end
  end
  dropScans(byAge(stale))
  -- an old per-auction scan that could not be read into a summary is shown nowhere: it goes first of all that is left
  for k in pairs(raw or {}) do
    if snaps[k] == nil and total > R.BUDGET then
      total = total - scanEntry(k)
      raw[k] = nil
      dropped[#dropped + 1] = "the unreadable old scan of " .. tostring(k)
    end
  end
  for k in pairs(snaps) do if not protected[k] then others[#others + 1] = k end end
  dropScans(byAge(others))
  -- c: characters not played for 90 days
  if total > R.BUDGET then
    local list = {}
    local me, mk = C.PlayerInfo().name, P.RealmGroup()
    for rk, cs in pairs(R.Chars()) do
      for name, c in pairs(cs) do
        if t - (c.seen or 0) > R.STALE_CHAR and not (rk == mk and name == me) then list[#list + 1] = { rk, name, c.seen or 0 } end
      end
    end
    table.sort(list, function(a, b) return a[3] < b[3] end)
    for _, e in ipairs(list) do
      if total <= R.BUDGET then break end
      local c = R.Chars()[e[1]][e[2]]
      total = total - (3 + keyLen(e[2]) + sizeOf(c, 4) + 2)
      R.Chars()[e[1]][e[2]] = nil
      if next(R.Chars()[e[1]]) == nil then R.Chars()[e[1]] = nil end
      dropped[#dropped + 1] = "the record of " .. e[2]
    end
  end
  -- d: price history, oldest realm first, in steps
  if total > R.BUDGET then
    local list = {}
    for k, r in pairs(P.DB().realms) do
      if type(r) == "table" and type(r.items) == "table" then list[#list + 1] = { k, tonumber(r.lastScan) or 0 } end
    end
    -- the oldest data first; of two equally old, the one that is not yours comes first
    table.sort(list, function(a, b)
      if a[2] ~= b[2] then return a[2] < b[2] end
      local x, y = protected[a[1]] and 1 or 0, protected[b[1]] and 1 or 0
      if x ~= y then return x < y end
      return tostring(a[1]) < tostring(b[1])
    end)
    R.job = { list = list, i = 0, total = total, dropped = dropped }
    runJob(not async)
    return dropped
  end
  R.size, R.over = total, false
  if #dropped > 0 then
    R.lastDropped = dropped
    Panoply:Fire("AUCTION_RECORD_CHANGED", "trim")
    Panoply:Print(("Panoply Suite let go of old auction data to stay near %d MB: %s."):format(floor(R.BUDGET / R.MB), table.concat(dropped, ", ")))
  end
  return dropped
end
-- Enforce that never raises (login, logout and the end of a scan must not show the player a Lua error)
function R.SafeEnforce(async)
  local ok, res = pcall(R.Enforce, async)
  if not ok then R.errors.enforce = tostring(res) Panoply:Debug("auction record: enforce", res) return {} end
  return res
end

-------------------------------------------------------------------------------
-- The game's own words: chat lines and mail subjects come from the client's global strings, never from English typed here
-------------------------------------------------------------------------------
-- "Auction successful: %s" -> a function(text) returning what stands for %s (nil when the text is not that line). nil without the string.
local function esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
function R.PatternOf(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, i, caps = { "^" }, 1, 0
  while i <= #fmt do
    local s, e, kind = fmt:find("%%%d*%$?([sd])", i)
    if not s then out[#out + 1] = esc((fmt:sub(i):gsub("%%%%", "%%"))) break end
    if s > i then out[#out + 1] = esc((fmt:sub(i, s - 1):gsub("%%%%", "%%"))) end
    out[#out + 1] = kind == "d" and "(%d+)" or "(.+)"
    caps = caps + 1
    i = e + 1
  end
  if caps == 0 then return nil end
  out[#out + 1] = "$"
  return table.concat(out)
end
R.matchCache = {}
function R.Matcher(const)
  local fmt = _G[const]
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local c = R.matchCache[const]
  if not c or c.fmt ~= fmt then
    local pat = R.PatternOf(fmt)
    c = { fmt = fmt, pat = pat }
    R.matchCache[const] = c
  end
  if not c.pat then return nil end
  return function(text)
    if type(text) ~= "string" then return nil end
    return text:match(c.pat)
  end
end

R.CHAT = { { "ERR_AUCTION_SOLD_S", "sold" }, { "ERR_AUCTION_WON_S", "won" } }
R.MAIL = { { "AUCTION_SOLD_MAIL_SUBJECT", "sold" }, { "AUCTION_WON_MAIL_SUBJECT", "won" }, { "AUCTION_EXPIRED_MAIL_SUBJECT", "expired" } }

-- one line the game printed. The same line can arrive twice, as a chat line and as an info message: the second channel's copy of a
-- line that just came in on the first is ignored. The same line on the same channel again is a second event (two sales of one item).
function R.OnMessage(text, channel)
  text = C.Readable(text)
  if type(text) ~= "string" or text == "" then return false end
  local t = C.GetTime()
  if R.lastMsg == text and channel ~= R.lastChannel and t - (R.lastMsgAt or 0) < 2 then return false end
  for _, e in ipairs(R.CHAT) do
    local m = R.Matcher(e[1])
    local what = m and m(text)
    if what then
      R.lastMsg, R.lastMsgAt, R.lastChannel = text, t, channel
      local id, name = idFromLink(what), nameFromText(what)
      if e[2] == "sold" then return R.NoteSoldMessage(id, name) end
      return R.NoteWon(id, name)
    end
  end
  return false
end

-- Mail ------------------------------------------------------------------------
-- Every mail is counted once, and only once, however many look alike (three "Auction successful: Linen Cloth" are three sales; five
-- stacks that expire together are five). A mail is known by everything the mailbox shows of it: subject, sender, money, what is attached
-- and how many, the invoice (who, price, deposit, cut) and the minute it expires. What was counted is remembered for each character as
-- "hash|minute|how many of that look were counted"; a mailbox that shows N mails of one look and has counted M of them makes N - M new
-- rows, so taking a mail away or reopening the box adds nothing, and a new mail of the same look still counts.
local function hash16(str)
  local a, b = 5381, 52711
  for i = 1, #str do
    local ch = str:byte(i)
    a = (a * 33 + ch) % 4294967291
    b = (b * 131 + ch + 7) % 4294967279
  end
  return ("%08x%08x"):format(a, b)
end
local function mailCounted(c, fp, minute)
  for i, e in ipairs(c.mail or {}) do
    local h, m, n = tostring(e):match("^(%x+)|(%d+)|(%d+)$")
    if h == fp and math.abs((tonumber(m) or 0) - minute) <= 10 then return i, tonumber(n) or 0 end
  end
  return nil, 0
end
local function mailRemember(c, idx, fp, minute, n)
  c.mail = c.mail or {}
  local e = fp .. "|" .. minute .. "|" .. n
  if idx then c.mail[idx] = e else c.mail[#c.mail + 1] = e end
end
local function mailForget(c)
  if type(c.mail) ~= "table" then return end
  local nowMin = floor(now() / 60)
  for i = #c.mail, 1, -1 do
    local m = tonumber(tostring(c.mail[i]):match("|(%d+)|%d+$")) or 0
    if m < nowMin - 10 then table.remove(c.mail, i) end
  end
  while #c.mail > R.MAX_MAIL do table.remove(c.mail, 1) end
end
function R.MailKind(subject)
  for _, e in ipairs(R.MAIL) do
    local m = R.Matcher(e[1])
    local what = m and m(subject)
    if what then return e[2], nameFromText(what) end
  end
  return nil
end
local function invoice(i)
  local r = { C.pc(_G.GetInboxInvoiceInfo, i) }
  if type(C.Readable(r[1])) ~= "string" then return nil end
  return { type = r[1], name = r[2], other = type(r[3]) == "string" and r[3] or nil, bid = tonumber(r[4]) or 0, buyout = tonumber(r[5]) or 0,
    deposit = tonumber(r[6]) or 0, cut = tonumber(r[7]) or 0 }
end
local function attached(i)
  local r = { C.pc(_G.GetInboxItem, i, 1) }
  return tonumber(r[2]), tonumber(r[4]), type(r[1]) == "string" and r[1] or nil      -- item id, count, name
end

-- One mail of a kind that is new: the row it makes
local function processMail(g)
  local inv = g.inv
  if g.kind == "sold" then
    local price = inv and ((inv.bid > 0 and inv.bid) or inv.buyout) or nil
    R.NoteSoldMail({ name = g.nm, buyer = inv and inv.other, price = price, cut = inv and inv.cut, money = g.money, t = g.sent })
  elseif g.kind == "won" then
    R.NoteBoughtMail({ id = g.id, name = g.nm, stack = g.count or 1, seller = inv and inv.other, paid = inv and ((inv.bid > 0 and inv.bid) or inv.buyout) or 0, t = g.sent })
  elseif g.kind == "expired" then
    R.NoteUnsold("e", { id = g.id, name = g.nm, stack = g.count, t = g.sent })
  end
end

-- Look through the mailbox for the mails of sales, wins and expired auctions. Safe to run again: a mail counts once.
function R.ScanMail()
  local n = C.pc(_G.GetInboxNumItems) or 0
  if type(n) ~= "number" or n < 1 then return 0 end
  local c = R.Me()
  if not c then return 0 end
  local t = now()
  local groups = {}
  for i = 1, n do
    local h = { C.pc(_G.GetInboxHeaderInfo, i) }
    local subject = C.Readable(h[4])
    if type(subject) == "string" then
      local kind, nm = R.MailKind(subject)
      if kind then
        local days = tonumber(h[7]) or 30
        local expiry = t + floor(days * 86400)
        local minute = floor(expiry / 60)
        local inv = invoice(i)
        local id, count, aname = attached(i)
        local money = tonumber(h[5]) or 0
        local fp = hash16(table.concat({ subject, tostring(h[3]), money, tostring(tonumber(h[6]) or 0), tostring(id), tostring(count), tostring(aname),
          inv and (inv.type .. "\1" .. tostring(inv.other) .. "\1" .. inv.bid .. "\1" .. inv.buyout .. "\1" .. inv.deposit .. "\1" .. inv.cut) or "-" }, "\2"))
        local g
        for _, x in ipairs(groups) do if x.fp == fp and math.abs(x.minute - minute) <= 10 then g = x break end end
        if g then g.n = g.n + 1
        else
          -- the mail was sent about 30 days before it expires (UNVERIFIED); never in the future
          groups[#groups + 1] = { fp = fp, minute = minute, n = 1, kind = kind, nm = nm, inv = inv, id = id, count = count, money = money,
            sent = math.min(t, math.max(t - 35 * 86400, expiry - 30 * 86400)) }
        end
      end
    end
  end
  local did = 0
  mailForget(c)
  for _, g in ipairs(groups) do
    local idx, seen = mailCounted(c, g.fp, g.minute)
    local fresh = g.n - seen
    if fresh > 0 then
      mailRemember(c, idx, g.fp, g.minute, g.n)
      for _ = 1, fresh do
        local ok, err = pcall(processMail, g)
        if ok then did = did + 1 else R.errors.mail = tostring(err) Panoply:Debug("auction record: mail", err) end
      end
    end
  end
  return did
end

-------------------------------------------------------------------------------
-- Your own posts, cancels and purchases
-------------------------------------------------------------------------------
-- Panoply Suite's own tabs say what they did through events (Trade.lua); the game's own auction window is watched by hooks (below).
-- A hook does nothing during a Panoply Suite click (Auc.click is set): Trade.lua records those once, with what it knows.
local function hours(duration) return ({ [1] = 12, [2] = 24, [3] = 48 })[duration] or 24 end

Auc:Listen("AUCTION_TRADE_POSTED", function(item, stack, unit, hrs, stacks)
  if not item then return end
  local total = (stack or 1) * (unit or 0)
  local deposit
  local T = Auc.Trade
  if T and T.Deposit then
    local d = T:Deposit(hrs, stack, unit, stacks)
    if type(d) == "number" then deposit = floor(d / math.max(1, stacks or 1)) end
  end
  R.NoteListed({ id = item.id, name = item.name, stack = stack, buyout = total, bid = total, hours = hrs, deposit = deposit, count = stacks })
end)
Auc:Listen("AUCTION_TRADE_CANCELLED", function(row)
  if not row then return end
  R.NoteUnsold("c", { id = row.id, name = row.name, stack = row.count })
end)
Auc:Listen("AUCTION_TRADE_BUY", function(what, row)
  if what ~= "bought" or not row then return end
  -- Era: the auction's buyout; Forever: the quote the player confirmed (Trade.lua keeps it in row.paid)
  R.NoteBuyClick({ id = row.id, name = row.name, stack = row.paidQty or row.count, paid = row.paid or row.buyout, seller = row.owner })
end)

-- the game's own window ----------------------------------------------------------
-- the item in the sell slot, remembered while it is there (the game empties the slot when the post goes through)
R.sellSlot = nil
function R.ReadSellSlot()
  local r = { C.pc(_G.GetAuctionSellItemInfo) }
  local id = tonumber(r[10])
  if id then R.sellSlot = { id = id, name = r[1], count = tonumber(r[3]) or 1 } else R.sellSlot = nil end
  return R.sellSlot
end

local function onGamePost(start, buyout, duration, stack, numStacks)
  if Auc.click then return end
  local slot = R.ReadSellSlot() or R.lastSlot
  if not slot then Panoply:Debug("auction record: a post in the game's window with nothing known in the sell slot") return end
  numStacks = math.max(1, floor(tonumber(numStacks) or 1))
  local deposit
  if _G.GetAuctionDeposit then
    local d = C.pc(_G.GetAuctionDeposit, duration, start, buyout, stack, numStacks)
    if type(d) == "number" then deposit = floor(d / numStacks) end
  end
  R.NoteListed({ id = slot.id, name = slot.name, stack = tonumber(stack) or slot.count or 1, buyout = tonumber(buyout) or tonumber(start), bid = tonumber(start),
    hours = hours(duration), deposit = deposit, count = numStacks })
end
local function onGameCancel(index)
  if Auc.click then return end
  local r = { C.pc(_G.GetAuctionItemInfo, "owner", index) }
  if not tonumber(r[17]) then return end
  R.NoteUnsold("c", { id = tonumber(r[17]), name = r[1], stack = tonumber(r[3]) or 1 })
end
local function onGameBid(kind, index, amount)
  if Auc.click or kind ~= "list" then return end
  local r = { C.pc(_G.GetAuctionItemInfo, "list", index) }
  local buyout, id = tonumber(r[10]) or 0, tonumber(r[17])
  if id and buyout > 0 and (tonumber(amount) or 0) >= buyout then
    R.NoteBuyClick({ id = id, name = r[1], stack = tonumber(r[3]) or 1, paid = buyout, seller = r[14] })
  end
end
-- Forever: the item location says which item is being posted
local function itemOf(loc)
  local id = _G.C_Item and C_Item.GetItemID and C.pc(C_Item.GetItemID, loc)
  if tonumber(id) then
    local ii = C.ItemInfo(id)
    return tonumber(id), ii and ii.name
  end
end
local function onModernPostItem(loc, duration, qty, bid, buyout)
  if Auc.click then return end
  local id, name = itemOf(loc)
  if not id then Panoply:Debug("auction record: a post in the game's window, item not known") return end
  R.NoteListed({ id = id, name = name, stack = 1, buyout = buyout, bid = bid, hours = hours(duration), count = 1 })
end
local function onModernPostCommodity(loc, duration, qty, unit)
  if Auc.click then return end
  local id, name = itemOf(loc)
  if not id then Panoply:Debug("auction record: a post in the game's window, item not known") return end
  R.NoteListed({ id = id, name = name, stack = qty or 1, buyout = (tonumber(unit) or 0) * (tonumber(qty) or 1), bid = (tonumber(unit) or 0) * (tonumber(qty) or 1),
    hours = hours(duration), count = 1 })
end
local function onModernCancel(auctionID)
  if Auc.click then return end
  local CAH = _G.C_AuctionHouse
  local list = CAH and CAH.GetOwnedAuctions and C.pc(CAH.GetOwnedAuctions) or {}
  for _, a in ipairs(list) do
    if a.auctionID == auctionID and a.itemKey and a.itemKey.itemID then
      R.NoteUnsold("c", { id = a.itemKey.itemID, stack = a.quantity or 1 })
      return
    end
  end
end
-- the last quote the game gave for a commodity purchase (the game's own window and Panoply Suite's both ask for one first)
Auc:On("COMMODITY_PRICE_UPDATED", function(_, unit, total) R.quote = { unit = tonumber(unit), total = tonumber(total), t = now() } end)
local function onModernBuy(id, qty)
  if Auc.click then return end
  local q = R.quote
  local ii = C.ItemInfo(id)
  R.NoteBuyClick({ id = tonumber(id), name = ii and ii.name, stack = tonumber(qty) or 1, paid = q and q.total or 0 })
end

local function hookOnce(tbl, name, fn)
  local f = type(tbl) == "table" and tbl[name]
  if type(f) ~= "function" then return false end
  R.hooked = R.hooked or setmetatable({}, { __mode = "k" })
  if R.hooked[f] then return true end
  local ok = pcall(hooksecurefunc, tbl, name, function(...)
    local ok2, err = pcall(fn, ...)
    if not ok2 then R.errors.hook = tostring(err) Panoply:Debug("auction record: hook", name, err) end
  end)
  if ok then R.hooked[tbl[name]] = true R.hooked[f] = true end
  return ok
end
-- Run when the auction house opens (the game's own functions exist then). Post hooks: nothing is replaced, nothing is called.
function R.Hook()
  if not _G.hooksecurefunc then return false end
  hookOnce(_G, "PostAuction", onGamePost)
  hookOnce(_G, "CancelAuction", onGameCancel)
  hookOnce(_G, "PlaceAuctionBid", onGameBid)
  local CAH = _G.C_AuctionHouse
  if type(CAH) == "table" then
    hookOnce(CAH, "PostItem", onModernPostItem)
    hookOnce(CAH, "PostCommodity", onModernPostCommodity)
    hookOnce(CAH, "CancelAuction", onModernCancel)
    hookOnce(CAH, "ConfirmCommoditiesPurchase", onModernBuy)
  end
  return true
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
-- Every event is asked for only where the client has it (a client that does not know an event can raise an error when it is registered,
-- and the launch-day self-test lists the events a client lacks). R.EVENTS is what this file listens to; the tests check it on both clients.
R.EVENTS = { "AUCTION_HOUSE_SHOW", "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "MAIL_INBOX_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "GET_ITEM_INFO_RECEIVED",
  "COMMODITY_PRICE_UPDATED", "PLAYER_LOGIN", "PLAYER_LOGOUT" }
local function clientHas(ev)
  local EU = _G.C_EventUtils
  if EU and EU.IsEventValid then
    local ok, v = pcall(EU.IsEventValid, ev)
    if ok and v == false then return false end
  end
  return true
end
Auc:On("AUCTION_HOUSE_SHOW", function() R.Hook() R.ReadSellSlot() end)
-- NEW_AUCTION_UPDATE (the Classic sell slot changed) exists on Era only. It keeps the item of the slot, which the game empties when a post
-- goes through, for the PostAuction hook. Forever has no such event and needs none: its post hooks (PostItem, PostCommodity) are given the
-- item's location, so the post is recorded from the hook itself, which reads the item from that location.
if clientHas("NEW_AUCTION_UPDATE") then
  R.EVENTS[#R.EVENTS + 1] = "NEW_AUCTION_UPDATE"
  Auc:On("NEW_AUCTION_UPDATE", function()
    local s = R.ReadSellSlot()
    if s then R.lastSlot = s end               -- kept after the slot empties, for the post that follows
  end)
end
Auc:On("CHAT_MSG_SYSTEM", function(_, text) R.OnMessage(text, "chat") end)
Auc:On("UI_INFO_MESSAGE", function(_, _, text) R.OnMessage(text, "info") end)
Auc:On("MAIL_INBOX_UPDATE", function() if R.mailOpen then R.ScanMail() end end)
Auc:On("MAIL_SHOW", function() R.mailOpen = true end)
Auc:On("MAIL_CLOSED", function() R.mailOpen = false end)
Panoply:On("PLAYER_LOGIN", function() C.After(8, function() R.SafeEnforce(true) end) end)
Auc:On("GET_ITEM_INFO_RECEIVED", function(_, id) R.OnItemInfo(id) end)
-- the last chance before the game writes the saved files
Panoply:On("PLAYER_LOGOUT", function() local ok, err = pcall(R.Enforce, false) if not ok then R.errors.logout = tostring(err) end end)

-------------------------------------------------------------------------------
-- The gear's two Forget buttons (Auctions > More settings > Saved auctions): each asks first, inside the gear
-------------------------------------------------------------------------------
-- choices = { { label, fn(), tip } ... }; the question is shown with the choices and a "Keep it" button.
local function askRow(id, label, tip, ask, choices)
  return { type = "custom", id = id, label = label, tip = tip, build = function(parent, x, y, width)
    local Skin = Panoply.Skin
    local SP = Skin.SP
    local inner = width - 40
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
    box:SetWidth(inner)
    local go = Skin.Button(box, label, 190, 24, nil, label, tip)
    local q = Skin.Ink(box, 11, Skin.colors.warn)
    q:SetWidth(inner)
    local btns = {}
    for i, ch in ipairs(choices) do
      local b = Skin.Button(box, ch[1], 120, 24, function()
        ch[2]()
        box.asking = nil
        box:Refresh()
        if Panoply.PageSettings and Panoply.PageSettings.open then Panoply.PageSettings:RefreshRows() end
      end, ch[1], ch[3])
      b.panoplyDanger = true
      b:Paint("up")
      btns[i] = b
    end
    local keep = Skin.Button(box, "Keep it", 90, 24, function() box.asking = nil box:Refresh() end, "Keep it", "Do nothing.")
    btns[#btns + 1] = keep
    go:SetScript("OnClick", function() box.asking = true box:Refresh() end)
    function box:Refresh()
      local h
      if self.asking then
        go:Hide() q:Show()
        q:SetText(type(ask) == "function" and ask() or ask)
        for _, b in ipairs(btns) do b:Show() end
        q:ClearAllPoints() q:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        local qh = Skin.TextHeight(q, inner)
        h = qh + SP.s + Skin.FlowButtons(box, btns, 0, -(qh + SP.s), inner, SP.s, 80)
      else
        q:Hide()
        for _, b in ipairs(btns) do b:Hide() end
        go:Show()
        Skin.FitButton(go, 120, inner)
        go:ClearAllPoints() go:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        h = go:GetHeight()
      end
      box:SetHeight(h)
    end
    box:Refresh()
    return box, y - box:GetHeight() - SP.m
  end }
end
function R.ForgetScanRow()
  return askRow("action:auctionForgetScan", "Forget the saved scan", "Deletes the saved scan of every realm from this computer. The prices Panoply Suite keeps are not touched.",
    function()
      local n = 0
      for _ in pairs(R.Snaps()) do n = n + 1 end
      return n == 0 and "There is no saved scan." or ("Forget %d saved scan%s? You can scan again at any auction house."):format(n, n == 1 and "" or "s")
    end,
    { { "Yes, forget it", function() R.ForgetScans() end, "Delete every saved scan." } })
end
function R.ForgetHistoryRow()
  return askRow("action:auctionForgetHistory", "Forget my auction history", "Deletes what Panoply Suite recorded of what you listed, bought and sold: this character, or all of them.",
    "Forget what you listed, bought and sold: this character, or every character?",
    { { "This character", function() R.ForgetHistory(false) end, "Delete this character's auction history." },
      { "All characters", function() R.ForgetHistory(true) end, "Delete the auction history of every character." } })
end
function R.SizeReadout() return R.MeterText() end
