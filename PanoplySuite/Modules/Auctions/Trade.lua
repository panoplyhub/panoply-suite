-- Auctions: trading layer (0.7.3, extended in 0.7.4). Searching, shopping lists, posting, cancelling, buying,
-- undercut checks.
-- Blizzard add-on policy, kept in code (not just in the docs):
--   * every request to the auction house server (a search, an own-auctions refresh, a post, a cancel, a
--     purchase) goes through Auc:Request, which refuses anything that is not inside a player click and allows
--     ONE request per click. There is no loop, no timer and no event handler that sends one.
--   * a search or a refresh waits for the client's permission first (CanSendAuctionQuery on Era,
--     C_AuctionHouse.IsThrottledMessageSystemReady on Forever).
--   * one post = one request. 0.7.4: "Stacks" may be more than 1 on Era, exactly like the game's own Create
--     Auction button (one PostAuction call with numStacks); it is 1 unless the player types more. One cancel =
--     one auction. No "cancel all". "Post all worthwhile" is one post per click (Sell.lua).
--   * 0.7.4: buying is two clicks. The first only selects (Era) or asks the game for a quote (Forever,
--     StartCommoditiesPurchase); the second re-checks the auction and sends ONE purchase.
-- Two API shapes, chosen at run time (feature-detected, never by version number):
--   "classic": QueryAuctionItems / GetAuctionItemInfo("list"|"owner") / PostAuction / CancelAuction
--   "modern":  C_AuctionHouse.SendBrowseQuery / GetBrowseResults / PostItem, PostCommodity /
--              QueryOwnedAuctions, GetOwnedAuctions / CancelAuction
-- UNVERIFIED in a real client: every call below was written from the public API documentation and
-- run against the offline stub; the Forever (modern) shapes and the Era sell slot have not been
-- tried in the game. See the report.
local ADDON, Panoply = ...
local C = Panoply.Compat
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T = {}
Auc.Trade = T

-- 0.7.4: we asked for "1 copper under" as the undercut; auctionWorth = the profit per post that makes the verdict
-- "Post it" (default 5 silver); auctionHideUnder = the Vendor tab hides deals whose profit is smaller.
for k, v in pairs({ auctionLists = {}, auctionRecent = {}, auctionUndercut = "1c", auctionSellHours = 24, auctionWorth = "5s", auctionHideUnder = "10c" }) do
  if Panoply.defaults.account[k] == nil then Panoply.defaults.account[k] = v end
end
T.TIMEOUT = 10             -- seconds before a request with no answer is forgotten (nothing is re-sent)
T.MAX_LISTS, T.MAX_TERMS, T.MAX_RECENT, T.MAX_TERM = 20, 100, 10, 60
T.HOURS = { 12, 24, 48 }    -- the three lengths as saved (auctionSellHours); both clients take them as 1 / 2 / 3
-- 0.7.3.1 (our "this addon has been disabled" popup on Era): the game's own Era auction window posts with
-- PostAuction(startPrice, buyoutPrice, duration 1-3, stackSize, numStacks) and prices the deposit with
-- GetAuctionDeposit(duration, startPrice, buyoutPrice, stackSize, numStacks) (Blizzard_AuctionUI, classic_era,
-- 1.15.9). 0.7.3 called StartAuction / CalculateAuctionDeposit with minutes (720 / 1440 / 2880), never checked.
T.DUR = { [12] = 1, [24] = 2, [48] = 3 }
T.DUR_TEXT = { [12] = "AUCTION_DURATION_ONE", [24] = "AUCTION_DURATION_TWO", [48] = "AUCTION_DURATION_THREE" }
T.DUR_PLAIN = { [12] = "Short", [24] = "Medium", [48] = "Long" }
-- The name of a length as the player's game says it: the Era game's own labels (its auction window's three
-- buttons), else "12h" / "24h" / "48h" on the modern auction house.
function T.DurLabel(hours)
  hours = T.DUR[hours] and hours or 24
  if T.Kind() == "classic" then
    local s = _G[T.DUR_TEXT[hours]]
    return (type(s) == "string" and s ~= "") and s or T.DUR_PLAIN[hours]
  end
  return hours .. "h"
end
T.UNDERCUTS = { { "1c", "1 copper" }, { "10c", "10 copper" }, { "1s", "1 silver" }, { "1%", "1 percent" }, { "2%", "2 percent" }, { "5%", "5 percent" } }
Auc.options[#Auc.options + 1] = { type = "choice", key = "auctionUndercut", label = "Undercut by", values = T.UNDERCUTS,
  tip = "When you sell, Panoply Suite suggests this much under the lowest price somebody else asks. You can change the price before you post." }
T.WORTHS = { { "1s", "1 silver" }, { "5s", "5 silver" }, { "10s", "10 silver" }, { "50s", "50 silver" }, { "1g", "1 gold" } }
Auc.options[#Auc.options + 1] = { type = "choice", key = "auctionWorth", label = "Worth posting from", values = T.WORTHS,
  tip = "On the Sell tab an item says \"Post it\" when posting it earns at least this much more than its cost (the cost to make it, or what a vendor pays). Under it, the item says \"Keep it\"." }
T.HIDES = { { "1c", "1 copper" }, { "10c", "10 copper" }, { "50c", "50 copper" }, { "1s", "1 silver" }, { "10s", "10 silver" } }
Auc.options[#Auc.options + 1] = { type = "choice", key = "auctionHideUnder", label = "Vendor tab: hide deals under", values = T.HIDES,
  tip = "The Vendor tab lists auctions that cost less than a vendor pays. Deals whose profit is smaller than this are left out of the list and the total. You can also type any amount on the tab itself." }
-- 0.7.4: the old default was "1%", saved in every account that ever opened the auction house. The two cannot be told
-- apart from a choice made on purpose, so the saved "1%" moves to the new default (1 copper) once; any other value
-- stays. UNVERIFIED how many accounts chose "1%" deliberately (the setting is new in 0.7.3).
function T.Migrate()
  if not Panoply.db or Panoply.db.auctionUndercutV2 then return end
  Panoply.db.auctionUndercutV2 = true
  if Panoply.db.auctionUndercut == "1%" then Panoply.db.auctionUndercut = "1c" end
end
Panoply:On("PLAYER_LOGIN", function() T.Migrate() end)

local function now() return P.Now() end

-- Which API shape this client has: "classic", "modern" or nil.
function T.Kind()
  local CAH = _G.C_AuctionHouse
  if _G.QueryAuctionItems and _G.GetAuctionItemInfo then return "classic" end
  if type(CAH) == "table" and CAH.SendBrowseQuery and CAH.GetBrowseResults then return "modern" end
  return nil
end
function T.Open() local f = Auc.Frame() return f ~= nil and (not f.IsShown or f:IsShown()) end

-------------------------------------------------------------------------------
-- Money text: "1g 20s 5c", "12g", "5s", "7c". A bare number is refused on purpose (is it gold or copper?).
-------------------------------------------------------------------------------
function T.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  local s = text:lower():gsub("%s+", "")
  if s == "" then return nil end
  local total, used = 0, 0
  local rest = s
  for num, unit in s:gmatch("(%d*%.?%d+)([gsc])") do
    local v = tonumber(num)
    if not v then return nil end
    if unit ~= "g" and num:find("%.") then return nil end
    total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    used = used + #num + 1
  end
  if used == 0 or used ~= #rest then return nil end
  return math.floor(total + 0.5)
end
-- "1g 20s 5c": only the parts that are not zero ("50s", never "50s 0c"); the parser reads it back.
function T.MoneyText(c)
  c = math.floor((c or 0) + 0.5)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
  return table.concat(out, " ")
end

-------------------------------------------------------------------------------
-- Suggested price: undercut the lowest price someone else asks.
-------------------------------------------------------------------------------
function T.ParseUndercut(v)
  v = tostring(v or "1c")
  local n, u = v:match("^(%d+)([cs%%])$")
  n = tonumber(n)
  if not n then return "percent", 1 end
  if u == "%" then return "percent", n end
  return "fixed", n * (u == "s" and 100 or 1)
end
-- lowest other-seller unit price -> the price to ask (at least 1 copper, never above the lowest)
function T.Undercut(lowest, setting)
  if not lowest or lowest <= 0 then return nil end
  local mode, v = T.ParseUndercut(setting or (Panoply.db and Panoply.db.auctionUndercut))
  local cut = mode == "percent" and math.max(1, math.floor(lowest * v / 100)) or v
  return math.max(1, lowest - cut)
end
-- rows: search results (each { unit, mine }). Returns price, basis ("competition" | "scan" | "history"), the
-- reference price, and a label. With no competition the price service's market price is asked as it is.
function T.Suggest(id, rows)
  local lowest
  for _, r in ipairs(rows or {}) do
    if r.unit and r.unit > 0 and not r.mine and (not lowest or r.unit < lowest) then lowest = r.unit end
  end
  if lowest then return T.Undercut(lowest), "competition", lowest end
  local m, rec = P.Market(id)
  if m then return m, "scan", m, rec.label end
  return nil
end
-- "Protection against posting too low": below the vendor price, or below half the usual price.
function T.TooLow(id, unit)
  local ii = id and C.ItemInfo(id)
  local vendor = ii and ii.sellPrice or 0
  if vendor > 0 and unit < vendor then return ("below the vendor price (%s)"):format(T.MoneyText(vendor)), "vendor" end
  local h = id and P.History(id)
  if h and h.hist and #h.hist > 0 then
    local sum = 0
    for _, d in ipairs(h.hist) do sum = sum + d[2] end
    local avg = sum / #h.hist
    if avg > 0 and unit < avg * 0.5 then return ("less than half the usual price (%s)"):format(T.MoneyText(math.floor(avg + 0.5))), "usual" end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Shopping lists (account wide, Panoply.db.auctionLists) and recent searches
-------------------------------------------------------------------------------
local function clean(s) return (tostring(s or ""):gsub("[%c^]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, T.MAX_TERM)) end
function T.Lists() Panoply.db.auctionLists = Panoply.db.auctionLists or {} return Panoply.db.auctionLists end
function T.NewList(name)
  local L = T.Lists()
  name = clean(name)
  if name == "" then return nil end
  for _, l in ipairs(L) do if l.name:lower() == name:lower() then return l end end
  if #L >= T.MAX_LISTS then return nil end
  local l = { name = name, terms = {} }
  L[#L + 1] = l
  return l
end
function T.DeleteList(l)
  local L = T.Lists()
  for i, x in ipairs(L) do if x == l then table.remove(L, i) return true end end
  return false
end
function T.AddTerm(l, term)
  term = clean(term)
  if not l or term == "" or #l.terms >= T.MAX_TERMS then return false end
  for _, t in ipairs(l.terms) do if t:lower() == term:lower() then return false end end
  l.terms[#l.terms + 1] = term
  return true
end
function T.RemoveTerm(l, i) if l and l.terms[i] then table.remove(l.terms, i) return true end return false end
function T.Recent() Panoply.db.auctionRecent = Panoply.db.auctionRecent or {} return Panoply.db.auctionRecent end
function T.AddRecent(term)
  term = clean(term)
  if term == "" then return end
  local R = T.Recent()
  for i = #R, 1, -1 do if R[i]:lower() == term:lower() then table.remove(R, i) end end
  table.insert(R, 1, term)
  while #R > T.MAX_RECENT do table.remove(R) end
end
-- Our own text format: "Panoply Suite list^Name^term^term".
function T.Export(l)
  if not l then return "" end
  return "Panoply Suite list^" .. l.name .. "^" .. table.concat(l.terms, "^")
end
function T.Import(text)
  if type(text) ~= "string" then return nil, "nothing to read" end
  local parts = {}
  for p in (text:gsub("[\r\n]+", "")):gmatch("[^^]+") do parts[#parts + 1] = p end
  -- a list shared from before the rename starts "Hearthpath list": still read
  if (parts[1] ~= "Panoply Suite list" and parts[1] ~= "Hearthpath list") or not parts[2] then return nil, "this is not a Panoply Suite list" end
  local l = T.NewList(parts[2])
  if not l then return nil, "too many lists (" .. T.MAX_LISTS .. ")" end
  local n = 0
  for i = 3, #parts do if T.AddTerm(l, parts[i]) then n = n + 1 end end
  return l, n
end

-------------------------------------------------------------------------------
-- Clicks: run fn as the player's click. Auc:Request allows one server request inside it.
-------------------------------------------------------------------------------
function T.Click(fn, ...)
  local prev = Auc.click
  Auc.click = { used = false }
  local ok, a, b = pcall(fn, ...)
  Auc.click = prev
  if not ok then Panoply:Debug("auctions: click", a) return false, "error" end
  return a, b
end

-- May the client take another query now?
function T.CanSend()
  local k = T.Kind()
  if k == "classic" then return Auc:CanQuery() end
  local CAH = _G.C_AuctionHouse
  if k == "modern" and CAH and CAH.IsThrottledMessageSystemReady then
    local ok, ready = pcall(CAH.IsThrottledMessageSystemReady)
    return not ok or ready ~= false
  end
  return k ~= nil
end

function T:Busy() return self.pending ~= nil end
local function startPending(kind, extra)
  T.token = (T.token or 0) + 1
  local p = extra or {}
  p.kind, p.t, p.token = kind, now(), T.token
  T.pending = p
  local token = T.token
  -- forgetting a request that never got an answer is the only thing a timer does; it sends nothing
  C.After(T.TIMEOUT, function()
    if T.pending and T.pending.token == token then
      T.pending = nil
      Panoply:Fire("AUCTION_TRADE_STATE", "timeout", kind)
    end
  end)
  Panoply:Fire("AUCTION_TRADE_STATE", "asking", kind)
end
local function done(kind)
  if T.pending and T.pending.kind == kind then T.pending = nil end
  Panoply:Fire("AUCTION_TRADE_STATE", "done", kind)
end

-------------------------------------------------------------------------------
-- Search (shopping lists, selling's competition, undercut checks): one request per call
-------------------------------------------------------------------------------
-- term: item name; exact: the whole name must match. Must be called inside T.Click.
function T:Search(term, exact, purpose)
  term = clean(term)
  if term == "" then return false, "empty" end
  if Auc.scan then return false, "a scan is running" end
  if self.pending then return false, "busy" end
  local k = T.Kind()
  if not k then return false, "no auction house API" end
  if not T.CanSend() then return false, "server busy" end
  local sent
  if k == "classic" then
    sent = Auc:Request("search", _G.QueryAuctionItems, term, nil, nil, 0, false, nil, false, exact and true or false, nil)
  else
    sent = Auc:Request("search", _G.C_AuctionHouse.SendBrowseQuery, { searchString = term, sorts = {}, filters = {} })
  end
  if not sent then return false, "refused" end
  self.buy = nil                                   -- a new search puts away a purchase that was waiting for its second click
  startPending("search", { term = term, exact = exact, purpose = purpose or "shop", page = 0 })
  T.AddRecent(term)
  return true
end
-- the next page of the same search (classic only). replace = true (the Buy tab): the page replaces the list, so
-- every row shown is on the page the game holds now (a purchase goes by the row's position on that page).
function T:SearchMore(replace)
  local r = self.results
  if not r or r.kind ~= "classic" or not r.more or self.pending or Auc.scan then return false, "no more" end
  if not T.CanSend() then return false, "server busy" end
  local sent = Auc:Request("search", _G.QueryAuctionItems, r.term, nil, nil, r.page + 1, false, nil, false, r.exact and true or false, nil)
  if not sent then return false, "refused" end
  self.buy = nil
  startPending("search", { term = r.term, exact = r.exact, purpose = r.purpose, page = r.page + 1, append = not replace })
  return true
end

local function playerName() return C.pc(_G.UnitName, "player") end
local function itemName(id, link, name)
  if name and name ~= "" then return name end
  local ii = (link and C.ItemInfo(link)) or (id and C.ItemInfo(id))
  return ii and ii.name or (id and ("item " .. id)) or "?"
end

-- classic: read the "list" page that just arrived
local function readClassicList()
  local n, total = C.pc(_G.GetNumAuctionItems, "list")
  n, total = n or 0, total or 0
  local me, rows = playerName(), {}
  for i = 1, n do
    local r = { C.pc(_G.GetAuctionItemInfo, "list", i) }
    local id = r[17]
    if id then
      local count = (r[3] and r[3] > 0) and r[3] or 1
      local buyout = r[10] or 0
      local link = C.pc(_G.GetAuctionItemLink, "list", i)
      if buyout > 0 then
        rows[#rows + 1] = { id = id, link = link, key = P.ItemKey(id, link), name = itemName(id, link, r[1]), icon = r[2], quality = r[4],
          count = count, buyout = buyout, unit = buyout / count, owner = r[14], mine = (r[14] ~= nil and r[14] == me),
          left = _G.GetAuctionItemTimeLeft and C.pc(_G.GetAuctionItemTimeLeft, "list", i) or nil, index = i, page = T.pending and T.pending.page or 0 }
      end
    end
  end
  return rows, n, total
end
-- modern: the browse results (one row per item: lowest price and how many are for sale)
local function readBrowse()
  local CAH = _G.C_AuctionHouse
  local list = CAH and CAH.GetBrowseResults and C.pc(CAH.GetBrowseResults) or {}
  local rows = {}
  for _, b in ipairs(list) do
    local k = b.itemKey
    if k and k.itemID and b.minPrice and b.minPrice > 0 then
      local key = (k.itemSuffix and k.itemSuffix ~= 0) and (k.itemID .. ":" .. k.itemSuffix) or k.itemID
      rows[#rows + 1] = { id = k.itemID, key = key, name = itemName(k.itemID), count = b.totalQuantity or 1, buyout = b.minPrice, unit = b.minPrice,
        mine = b.containsOwnerItem and true or false, browse = true, itemKey = k }
    end
  end
  return rows, #list, #list
end

local function finishSearch(rows, n, total)
  local p = T.pending
  if not p or p.kind ~= "search" then return end
  table.sort(rows, function(a, b) if a.unit ~= b.unit then return a.unit < b.unit end return (a.count or 0) > (b.count or 0) end)
  local res = { kind = T.Kind(), term = p.term, exact = p.exact, purpose = p.purpose, page = p.page or 0, rows = rows, total = total, t = now(), gen = Auc.listGen }
  if p.append and T.results and T.results.term == p.term then
    local all = {}
    for _, r in ipairs(T.results.rows) do all[#all + 1] = r end
    for _, r in ipairs(rows) do all[#all + 1] = r end
    table.sort(all, function(a, b) return a.unit < b.unit end)
    res.rows = all
  end
  for _, r in ipairs(res.rows) do if r.gen == nil then r.gen = res.gen end end    -- 0.7.4: a purchase is only valid within this list
  res.more = res.kind == "classic" and ((res.page + 1) * Auc.PAGE < (total or 0))
  local low
  for _, r in ipairs(res.rows) do if not r.mine and (not low or r.unit < low) then low = r.unit end end
  res.lowest = low
  T.results = res
  done("search")
  Panoply:Fire("AUCTION_TRADE_SEARCH", res)
end
function T:OnList()
  if not self.pending or self.pending.kind ~= "search" or T.Kind() ~= "classic" then return end
  local rows, n, total = readClassicList()
  finishSearch(rows, n, total)
end
function T:OnBrowse()
  if not self.pending or self.pending.kind ~= "search" or T.Kind() ~= "modern" then return end
  local rows, n, total = readBrowse()
  finishSearch(rows, n, total)
end

-------------------------------------------------------------------------------
-- My auctions (cancelling tab): refresh = one request; the list is also read whenever the game sends it
-------------------------------------------------------------------------------
function T:RefreshOwned()
  if self.pending then return false, "busy" end
  if Auc.scan then return false, "a scan is running" end
  local k = T.Kind()
  local sent
  if k == "classic" then
    if not _G.GetOwnerAuctionItems then return false, "not available" end
    sent = Auc:Request("owned", _G.GetOwnerAuctionItems)
  elseif k == "modern" and _G.C_AuctionHouse.QueryOwnedAuctions then
    if not T.CanSend() then return false, "server busy" end
    sent = Auc:Request("owned", _G.C_AuctionHouse.QueryOwnedAuctions, {})
  else return false, "not available" end
  if not sent then return false, "refused" end
  startPending("owned")
  return true
end
local function readOwnedClassic()
  local n = C.pc(_G.GetNumAuctionItems, "owner") or 0
  local rows = {}
  for i = 1, n do
    local r = { C.pc(_G.GetAuctionItemInfo, "owner", i) }
    local id = r[17]
    if id and r[16] ~= 1 then                          -- 1 = already sold
      local count = (r[3] and r[3] > 0) and r[3] or 1
      local link = C.pc(_G.GetAuctionItemLink, "owner", i)
      local buyout = r[10] or 0
      rows[#rows + 1] = { index = i, id = id, link = link, key = P.ItemKey(id, link), name = itemName(id, link, r[1]), icon = r[2], quality = r[4],
        count = count, buyout = buyout, bid = r[11] or 0, unit = buyout > 0 and buyout / count or nil,
        left = _G.GetAuctionItemTimeLeft and C.pc(_G.GetAuctionItemTimeLeft, "owner", i) or nil }
    end
  end
  return rows
end
local function readOwnedModern()
  local CAH = _G.C_AuctionHouse
  local list = CAH and CAH.GetOwnedAuctions and C.pc(CAH.GetOwnedAuctions) or {}
  local rows = {}
  for _, a in ipairs(list) do
    local k = a.itemKey
    local id = k and k.itemID
    if id and a.auctionID and (a.status == nil or a.status == 0) then   -- 0 = active (Enum.AuctionStatus.Active)
      local qty = a.quantity or 1
      local buyout = a.buyoutAmount or 0
      -- a commodity auction reports its UNIT price, an item auction the whole price (UNVERIFIED)
      local info = CAH.GetItemKeyInfo and C.pc(CAH.GetItemKeyInfo, k)
      local unit = buyout > 0 and ((info and info.isCommodity) and buyout or buyout / qty) or nil
      rows[#rows + 1] = { auctionID = a.auctionID, id = id, link = a.itemLink, key = id, name = itemName(id, a.itemLink), count = qty,
        buyout = unit and unit * qty or 0, unit = unit, left = a.timeLeftSeconds or a.timeLeft }
    end
  end
  return rows
end
function T:OnOwned()
  local k = T.Kind()
  if not k then return end
  local old = self.owned
  local rows = k == "classic" and readOwnedClassic() or readOwnedModern()
  -- keep what was already learned about each auction (undercut checks) when the same one is still there
  for _, r in ipairs(rows) do
    for _, o in ipairs(old and old.rows or {}) do
      if o.check and o.id == r.id and o.buyout == r.buyout and o.count == r.count then r.check = o.check break end
    end
  end
  self.owned = { rows = rows, t = now() }
  done("owned")
  Panoply:Fire("AUCTION_TRADE_OWNED", self.owned)
end

-- The undercut check of one of my auctions, from a search result for its item: the lowest unit price
-- somebody else asks. state: "lowest" (mine is the cheapest), "undercut" (someone is cheaper), "alone".
function T.Judge(row, results)
  local low
  for _, r in ipairs(results.rows or {}) do
    if not r.mine and r.id == row.id and (not low or r.unit < low) then low = r.unit end
  end
  if not row.unit then return { state = "bid", t = now() } end
  if not low then return { state = "alone", t = now() } end
  if low < row.unit then return { state = "undercut", lowest = low, by = row.unit - low, t = now() } end
  return { state = "lowest", lowest = low, t = now() }
end
-- the next of my auctions that has no check yet (the "Check next" button searches this one)
function T:NextToCheck()
  for _, r in ipairs(self.owned and self.owned.rows or {}) do
    if not r.check and r.unit then return r end
  end
  return nil
end
-- Must be inside T.Click. One search for the next unchecked auction's item (exact name).
function T:CheckNext()
  local r = self:NextToCheck()
  if not r then return false, "all checked" end
  local ok, why = self:Search(r.name, true, "check")
  if ok then self.pending.checkFor = r end
  return ok, why
end
-- a "check" search finished: judge every unchecked auction of that item at once (same data)
local function applyChecks(res)
  if res.purpose ~= "check" or not T.owned then return end
  for _, r in ipairs(T.owned.rows) do
    if not r.check and r.unit and (r.name == res.term or itemName(r.id) == res.term) then r.check = T.Judge(r, res) end
  end
  Panoply:Fire("AUCTION_TRADE_OWNED", T.owned)
end

-- Cancel ONE auction. Must be inside T.Click. The row is checked against the game's list first: when
-- the list moved (another auction sold or expired) nothing is cancelled and the list must be refreshed.
function T:Cancel(row)
  if not row then return false, "no auction" end
  local k = T.Kind()
  if k == "classic" then
    local r = { C.pc(_G.GetAuctionItemInfo, "owner", row.index or 0) }
    if r[17] ~= row.id or (r[10] or 0) ~= row.buyout then return false, "stale" end
    if not Auc:Request("cancel", _G.CancelAuction, row.index) then return false, "refused" end
  elseif k == "modern" then
    local CAH = _G.C_AuctionHouse
    if CAH.CanCancelAuction and C.pc(CAH.CanCancelAuction, row.auctionID) == false then return false, "cannot cancel" end
    if not Auc:Request("cancel", CAH.CancelAuction, row.auctionID) then return false, "refused" end
  else return false, "no auction house API" end
  row.cancelled = true
  Panoply:Fire("AUCTION_TRADE_CANCELLED", row)           -- 0.7.4 (item F): the record writes it to "did not sell"
  Panoply:Fire("AUCTION_TRADE_OWNED", self.owned)
  return true
end

-------------------------------------------------------------------------------
-- Posting (selling tab)
-------------------------------------------------------------------------------
-- Bag items worth listing: not soulbound, not locked, with a game-known name. { bag, slot, id, link, name, count, icon, quality }
function T.BagItems()
  local out, seen = {}, {}
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, C.NumSlots(bag) do
      local s = C.SlotInfo(bag, slot)
      if s and s.itemID and not s.bound and not s.locked then
        local ii = C.ItemInfo(s.itemID)
        local key = s.itemID
        if ii and ii.name then
          local e = seen[key]
          if e then e.total = e.total + s.count
          else
            e = { bag = bag, slot = slot, id = s.itemID, link = s.link, name = ii.name, count = s.count, total = s.count, icon = s.icon or ii.icon,
                  quality = s.quality or ii.quality, stack = ii.stack or 1 }
            seen[key] = e
            out[#out + 1] = e
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Put the item in the sell slot (classic) / remember its bag position (modern). No server request.
function T:Load(item)
  local k = T.Kind()
  if not k or not item then return false end
  if k == "classic" then
    if not (_G.ClickAuctionSellItemButton and _G.GetAuctionSellItemInfo) then return false end
    if _G.ClearCursor then C.pc(_G.ClearCursor) end
    if C.pc(_G.GetAuctionSellItemInfo) then          -- something is in the slot: take it back first
      C.pc(_G.ClickAuctionSellItemButton)
      if _G.ClearCursor then C.pc(_G.ClearCursor) end
    end
    C.PickupSlot(item.bag, item.slot)
    C.pc(_G.ClickAuctionSellItemButton)
    local name = C.pc(_G.GetAuctionSellItemInfo)
    if not name then
      if _G.ClearCursor then C.pc(_G.ClearCursor) end
      return false
    end
  end
  self.sale = { item = item, bag = item.bag, slot = item.slot }
  return true
end
function T:Unload()
  if T.Kind() == "classic" and self.sale and _G.GetAuctionSellItemInfo and C.pc(_G.GetAuctionSellItemInfo) then
    C.pc(_G.ClickAuctionSellItemButton)
    if _G.ClearCursor then C.pc(_G.ClearCursor) end
  end
  self.sale = nil
end
-- deposit for the post of the loaded item: `stacks` auctions (default 1) of `stack` items at `unit` copper each
-- (nil when the client cannot say)
function T:Deposit(hours, stack, unit, stacks)
  local k, s = T.Kind(), self.sale
  if not s then return nil end
  local dur = T.DUR[hours] or 2
  if k == "classic" and _G.GetAuctionDeposit then
    stack, unit = math.floor(tonumber(stack) or 0), math.floor(tonumber(unit) or 0)
    if stack < 1 or unit < 1 then return nil end
    stacks = math.max(1, math.floor(tonumber(stacks) or 1))
    local d = C.pc(_G.GetAuctionDeposit, dur, unit * stack, unit * stack, stack, stacks)
    return type(d) == "number" and d or nil
  elseif k == "modern" then
    local CAH = _G.C_AuctionHouse
    local loc = s.loc or (_G.ItemLocation and ItemLocation:CreateFromBagAndSlot(s.bag, s.slot))
    local d = CAH.CalculateItemDeposit and loc and C.pc(CAH.CalculateItemDeposit, loc, dur, stack or 1)
    return type(d) == "number" and d or nil
  end
  return nil
end

-- Post the loaded item: `stacks` auctions (default 1; Era only, one request like the game's own Create Auction
-- button) of `stack` items at `unit` copper each. Must be inside T.Click.
-- Era: when the game holds the post back for the player to confirm (PostAuction answers false and fires
-- AUCTION_HOUSE_POST_WARNING), nothing is posted and the answer is "confirm"; the next Post click sends the
-- same auction again with confirm = true, as the game's own window does.
function T:Post(stack, unit, hours, confirm, stacks)
  local s, k = self.sale, T.Kind()
  if not s or not k then return false, "nothing loaded" end
  if self.pending then return false, "busy" end
  stack = math.floor(tonumber(stack) or 0)
  unit = math.floor(tonumber(unit) or 0)
  stacks = math.floor(tonumber(stacks) or 1)
  if stack < 1 or unit < 1 or stacks < 1 then return false, "bad price or stack" end
  if k ~= "classic" then stacks = 1 end              -- the modern auction house posts one quantity (UNVERIFIED shape)
  hours = T.DUR[hours] and hours or 24
  local total = unit * stack
  local dur = T.DUR[hours]
  local sent
  if k == "classic" then
    if not _G.PostAuction then return false, "not available" end
    if not C.pc(_G.GetAuctionSellItemInfo) then return false, "the sell slot is empty" end
    local posted
    sent, posted = Auc:Request("post", _G.PostAuction, total, total, dur, stack, stacks, confirm and true or false)
    if sent and not posted then return false, "confirm" end
  else
    local CAH = _G.C_AuctionHouse
    local loc = s.loc or (_G.ItemLocation and ItemLocation:CreateFromBagAndSlot(s.bag, s.slot))
    if not loc then return false, "not available" end
    local status = CAH.GetItemCommodityStatus and C.pc(CAH.GetItemCommodityStatus, loc)
    if status == 2 and CAH.PostCommodity then sent = Auc:Request("post", CAH.PostCommodity, loc, dur, stack, unit)
    elseif CAH.PostItem then sent = Auc:Request("post", CAH.PostItem, loc, dur, 1, total, total)
    else return false, "not available" end
  end
  if not sent then return false, "refused" end
  P.RecordPost({ id = s.item.id, link = s.item.link, name = s.item.name, count = stack * stacks, unit = unit, hours = hours })
  Panoply:Fire("AUCTION_TRADE_POSTED", s.item, stack, unit, hours, stacks)
  return true
end

-------------------------------------------------------------------------------
-- Buying (0.7.4: the Buy tab and the Vendor tab). Two clicks, one purchase.
--   Era:     click 1 (BuyClick) sends nothing: it selects the row. Click 2 (ConfirmBuy) re-checks that the auction
--            at that position in the game's list is still the same item, count and buyout, and only then sends
--            ONE PlaceAuctionBid("list", index, buyout). A row that moved, sold or changed price sends nothing.
--   Forever: click 1 sends ONE quote request (StartCommoditiesPurchase); the game answers with COMMODITY_PRICE_UPDATED;
--            click 2 checks the quote against the limit the tab set and sends ONE ConfirmCommoditiesPurchase.
-- A row is { id, count, buyout, unit, index (Era), gen (Era: Auc.listGen when it was read), limitFor = fn(qty) -> the most
-- the whole purchase may cost (Forever) }.
-- UNVERIFIED in a real client: PlaceAuctionBid from our own button without the game's buyout dialog (Era), every
-- Forever call and event named here.
-------------------------------------------------------------------------------
-- The one purchase waiting for its second click: { row, state = "armed" | "asking" | "quoted", qty, quote = { unit, total }, token }
function T:BuyClick(row, qty)
  local k = T.Kind()
  if not k or not row then return false, "no auction house API" end
  if self.pending or Auc.scan then return false, "busy" end
  if k == "classic" then
    if not row.index or not _G.PlaceAuctionBid then return false, "not available" end
    self.buy = { row = row, state = "armed", t = now() }
    Panoply:Fire("AUCTION_TRADE_BUY", "armed", row)
    return true, "armed"
  end
  local CAH = _G.C_AuctionHouse
  if not (CAH and CAH.StartCommoditiesPurchase and CAH.ConfirmCommoditiesPurchase) then return false, "not available" end
  qty = math.floor(tonumber(qty) or row.count or 1)
  if qty < 1 then return false, "bad quantity" end
  if not T.CanSend() then return false, "server busy" end
  local sent = Auc:Request("quote", CAH.StartCommoditiesPurchase, row.id, qty)
  if not sent then return false, "refused" end
  T.buyToken = (T.buyToken or 0) + 1
  local token = T.buyToken
  self.buy = { row = row, state = "asking", qty = qty, t = now(), token = token }
  C.After(T.TIMEOUT, function()
    if T.buy and T.buy.token == token and T.buy.state == "asking" then
      T.buy = nil
      Panoply:Fire("AUCTION_TRADE_BUY", "timeout", row)
    end
  end)
  Panoply:Fire("AUCTION_TRADE_BUY", "asking", row)
  return true, "asking"
end
-- Era: is the auction at the row's position still the same one? Returns true, or false and why.
function T.Recheck(row)
  if row.gen and row.gen ~= Auc.listGen then return false, "stale" end
  local r = { C.pc(_G.GetAuctionItemInfo, "list", row.index or 0) }
  local count = (r[3] and r[3] > 0) and r[3] or 1
  if r[17] ~= row.id or count ~= row.count or (r[10] or 0) ~= row.buyout then return false, "stale" end
  if r[14] ~= nil and r[14] == playerName() then return false, "yours" end
  return true
end
-- Must be inside T.Click.
function T:ConfirmBuy(row)
  local b, k = self.buy, T.Kind()
  if not b or b.row ~= row or not k then return false, "not armed" end
  if self.pending or Auc.scan then return false, "busy" end
  if k == "classic" then
    local ok, why = T.Recheck(row)
    if not ok then self.buy = nil Panoply:Fire("AUCTION_TRADE_BUY", "stale", row) return false, why end
    if not Auc:Request("buy", _G.PlaceAuctionBid, "list", row.index, row.buyout) then return false, "refused" end
  else
    local CAH = _G.C_AuctionHouse
    if b.state ~= "quoted" then return false, b.state == "asking" and "busy" or "not armed" end
    local limit = row.limitFor and row.limitFor(b.qty) or nil
    if limit and b.quote.total > limit then self.buy = nil Panoply:Fire("AUCTION_TRADE_BUY", "stale", row) return false, "stale" end
    if not Auc:Request("buy", CAH.ConfirmCommoditiesPurchase, row.id, b.qty) then return false, "refused" end
  end
  -- 0.7.4 (item F): what was paid, for the record (Forever: the quote the player confirmed)
  if k ~= "classic" and b.quote then row.paid, row.paidQty = b.quote.total, b.qty end
  self.buy = nil
  row.bought = true
  Panoply:Fire("AUCTION_TRADE_BUY", "bought", row)
  return true
end
function T:CancelBuy() if self.buy then self.buy = nil Panoply:Fire("AUCTION_TRADE_BUY", "cancelled") end end
-- the game's answer to a quote request (Forever)
Auc:On("COMMODITY_PRICE_UPDATED", function(_, unit, total)
  local b = T.buy
  if not b or b.state ~= "asking" then return end
  b.state, b.quote = "quoted", { unit = tonumber(unit) or 0, total = tonumber(total) or 0 }
  Panoply:Fire("AUCTION_TRADE_BUY", "quoted", b.row)
end)
Auc:On("COMMODITY_PRICE_UNAVAILABLE", function()
  local b = T.buy
  if not b or b.state ~= "asking" then return end
  T.buy = nil
  Panoply:Fire("AUCTION_TRADE_BUY", "unavailable", b.row)
end)

-------------------------------------------------------------------------------
-- Events (answers only: nothing here sends a request)
-------------------------------------------------------------------------------
Auc:On("AUCTION_ITEM_LIST_UPDATE", function() T:OnList() end)
Auc:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() T:OnBrowse() end)
Auc:On("AUCTION_OWNED_LIST_UPDATE", function() T:OnOwned() end)
Auc:On("OWNED_AUCTIONS_UPDATED", function() T:OnOwned() end)
Panoply:Listen("AUCTION_TRADE_SEARCH", function(res) applyChecks(res) end)
Auc:On("AUCTION_HOUSE_CLOSED", function() T.pending, T.results, T.owned, T.sale, T.buy = nil, nil, nil, nil, nil end)
