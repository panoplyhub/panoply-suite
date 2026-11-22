-- Auctions module (SPEC 19.8): Panoply Suite's own auction house scanner.
-- A rounded "Scan" button with a progress bar sits on the auction house window.
-- 0.6.1 (Blizzard add-on policy): every request to the auction house server comes from one
-- click by the player, one request per click. Nothing is ever asked for from a timer or an event.
--   Classic Era: "Scan" asks for everything at once (QueryAuctionItems getAll) when the server
--   allows it (about once per 15 minutes; a countdown shows otherwise). Otherwise the scan goes
--   page by page: "Scan" asks for page 1, then "Next page" asks for the next one, one page per
--   click, with "Page 3 of 12" above the bar.
--   Forever (modern API): "Scan" asks for C_AuctionHouse.ReplicateItems when allowed. 0.9.5 (item 14): during the
--   15-minute wait there is no slow fallback any more (it was a browse plus up to 200 "Load more" clicks, about 15
--   minutes of clicking); the countdown and the age of the last scan show, and the click opens the shopping list, where
--   each item is one quick search. A client with browse queries only still scans by browse, one batch per click.
-- Reading the answers (local data, no server request) runs on a time budget per frame (Auc.FRAME_MS), so the game
-- does not freeze. 0.9.5: auctions whose item the game has not loaded yet are read again as the game's item events
-- arrive (no fixed three retries), prices are saved first and the saved scan and vendor deals are worked out after
-- them, an empty or much shorter answer than the last full scan is "server busy" (not saved, the wait does not
-- restart), and the bar counts auctions read out of the total and ends with the time taken.
-- The X stops a scan and keeps what was already read. Normal browsing
-- records prices too. Data goes to PanoplySuiteAuctionDB per realm + faction (Panoply.Prices).
-- 0.7.3: "Auction window" (called "Trade" until 0.9.5) opens the Panoply Suite auctions window (Panel.lua; tabs in Shopping.lua, Cancelling.lua, History.lua;
-- the requests in Trade.lua). 0.7.4: Sell, Buy and Vendor are three tabs of the game's own window (Host.lua). The same rule holds there: one click, one
-- request. Setting "Slower scan" makes every scan page by page.
-- 0.7.4: the scan also keeps, for the Vendor tab, the auctions whose buyout is below what a vendor pays for the same
-- items (Auc.deals; at most Auc.MAX_DEALS, the biggest profits, replaced by every scan, kept in memory only: an
-- auction's position in the game's list is meaningless after a reload). The saved price data is unchanged.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Skin = Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Modules:Register({
  key = "auctions", label = "Auctions", icon = "Auctions",
  desc = "Scans the auction house so item tooltips can show what things sell for on your realm.",
  defaults = { auctionAutoScan = false, auctionPassive = true, auctionSlowScan = false },
})
Panoply.Auctions = Auc
Auc.FRAME_MS = 10          -- milliseconds of reading per frame (0.9.5; was a fixed 400 auctions per frame)
Auc.CLOCK_EVERY = 25       -- auctions read between two looks at the clock
Auc.ROWS_NOCLOCK = 400     -- auctions per frame on a client without debugprofilestop
Auc.GETALL_COOLDOWN = 15 * 60
Auc.PAGE = 50              -- NUM_AUCTION_ITEMS_PER_PAGE on Classic
Auc.LOAD_POLL = 1          -- seconds: auctions still waiting for their item are looked at again this often, events or not
Auc.LOAD_IDLE = 6          -- seconds with no waiting auction becoming readable: the rest are given up
Auc.LOAD_MAX = 60          -- seconds of waiting for items in all
Auc.ANSWER_WAIT = 120      -- seconds a full scan waits for the server's answer before it says the server is busy
Auc.BUSY_SHARE = 0.5       -- a full scan under half of the last full scan's auctions is a busy server's answer...
Auc.BUSY_MIN = 1000        -- ...when the last full scan had at least this many
Auc.POST_SYNC = 5000       -- auctions: a scan this small has its saved scan and deals worked out at once
Auc.MAX_DEALS = 100        -- below-vendor auctions kept from one scan (the Vendor tab)
Auc.listGen = 0            -- counts the requests that replace the game's auction list (a purchase by position is only valid within one)

Auc.options = {
  -- the saved key stays auctionAutoScan (0.5.3); since 0.6.1 it only reminds, it never scans
  { type = "check", key = "auctionAutoScan", label = "Tell me when a full scan is ready", tip = "When you open the auction house and a full scan is allowed (about once every 15 minutes), Panoply Suite says so. It never scans by itself: every request is one click on Scan or Next page." },
  { type = "check", key = "auctionPassive", label = "Remember prices while I browse", tip = "Pages you look at in the auction house update the prices too." },
  -- 0.9.7 (WoW Forever only): WoW Forever always scans in one go (Auc:Start), so the row is not drawn there; the saved key stays
  { type = "check", key = "auctionSlowScan", label = "Slower scan: one page per click", tip = "Scan page by page even when a full scan is allowed. Slower, but gentler on a connection that drops.",
    only = function() return not C.IsForever() end },
  { type = "button", label = "Forget old prices", tip = "Removes prices older than 30 days now (this also happens by itself).", func = function() local n = P.Prune() Panoply:Print(("Removed %d old prices."):format(n)) end },
}

local function now() return P.Now() end

-- Which API this client has.
function Auc.API()
  local CAH = _G.C_AuctionHouse
  if _G.QueryAuctionItems and _G.GetAuctionItemInfo then return "classic" end
  if type(CAH) == "table" and CAH.ReplicateItems and CAH.GetNumReplicateItems then return "replicate" end
  if type(CAH) == "table" and CAH.SendBrowseQuery then return "browse" end
  return nil
end
function Auc.Frame() return _G.AuctionFrame or _G.AuctionHouseFrame end

-- Seconds until a full scan is allowed again (0 = now). Uses the server's answer when it has one.
function Auc:FullScanWait()
  local r = P.Realm()
  local left = math.max(0, Auc.GETALL_COOLDOWN - (now() - (r.lastGetAll or 0)))
  if Auc.API() == "classic" and _G.CanSendAuctionQuery then
    local ok, can, canAll = pcall(CanSendAuctionQuery, "list")
    if ok then
      if canAll then return 0 end
      return left > 0 and left or 60   -- the server says no but we don't know how long: say about a minute
    end
  end
  return left
end
function Auc.FormatWait(s)
  s = math.max(0, math.floor(s))
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-------------------------------------------------------------------------------
-- Scan state
-------------------------------------------------------------------------------
-- self.scan = { kind = "full"|"paged"|"replicate"|"browse", page, total, read, seen = { [key] = { min, qty } }, retry = {} }
function Auc:Busy() return self.scan ~= nil end

local function add(seen, key, unit, qty)
  if not key or not unit or unit <= 0 then return end
  local s = seen[key]
  if not s then seen[key] = { unit, qty or 1 } return end
  if unit < s[1] then s[1] = unit end
  s[2] = s[2] + (qty or 1)
end
Auc.Add = add

-- 0.7.4: what a vendor pays for this item (copper each), cached for the length of one scan; nil when the game does not
-- know the item yet or the item cannot be sold to a vendor.
local function vendorPrice(scan, itemID)
  local v = scan.vendor[itemID]
  if v == nil then
    local ii = C.ItemInfo(itemID)
    v = (ii and ii.sellPrice and ii.sellPrice > 0) and ii.sellPrice or false
    scan.vendor[itemID] = v
  end
  return v or nil
end
-- A listed auction (buyout above 0) of `count` items: kept for the Vendor tab when its buyout is below the vendor value.
local function noteDeal(scan, info, link, index, count, buyout, itemID)
  local v = vendorPrice(scan, itemID)
  if not v or buyout >= v * count then return end
  local owner = info[14]
  if owner ~= nil and owner == C.pc(_G.UnitName, "player") then return end      -- your own auctions cannot be bought
  local list = scan.deals
  list[#list + 1] = { id = itemID, key = P.ItemKey(itemID, link), link = link, name = info[1], icon = info[2], quality = info[4], count = count,
    buyout = buyout, unit = buyout / count, vendor = v, profit = v * count - buyout, index = index, gen = Auc.listGen, owner = owner }
  if #list > Auc.MAX_DEALS * 4 then
    table.sort(list, function(a, b) return a.profit > b.profit end)
    for i = #list, Auc.MAX_DEALS + 1, -1 do list[i] = nil end
    scan.dealsCut = true
  end
end

-- one auction from the classic list / replicate list. Returns false when its item info is not cached.
-- scan + index (optional): also keep it for the Vendor tab when it is below the vendor price.
local function readOne(seen, info, link, scan, index)
  local count, buyout, itemID, hasAll = info[3], info[10], info[17], info[18]
  if hasAll == false or not itemID then return false end
  count = (count and count > 0) and count or 1
  -- 0.7.4 (item F): the saved scan keeps every auction: stack, buyout, bid (the current bid, else the starting bid), seller, time left
  if scan and scan.rec then
    local bid = (type(info[11]) == "number" and info[11] > 0) and info[11] or info[8]
    scan.rec:Add(P.ItemKey(itemID, link), count, buyout, bid, info[14], Auc.Record.Band(scan.timeFn and index and scan.timeFn(index), scan.zeroBased))
  end
  if not buyout or buyout <= 0 then return true end           -- bid-only: not in the price data
  add(seen, P.ItemKey(itemID, link), buyout / count, count)
  if scan and scan.deals then noteDeal(scan, info, link, index, count, buyout, itemID) end
  return true
end
Auc.ReadOne = readOne

-- the time left of one auction of the game's list (1 Short .. 4 Very long)
local function classicTime(i) return _G.GetAuctionItemTimeLeft and C.pc(_G.GetAuctionItemTimeLeft, "list", i) or nil end

local function classicInfo(i)
  local r = { C.pc(_G.GetAuctionItemInfo, "list", i) }
  if r[1] == nil and r[17] == nil then return nil end
  return r, C.pc(_G.GetAuctionItemLink, "list", i)
end
local function replicateInfo(i)
  local CAH = _G.C_AuctionHouse
  local r = { C.pc(CAH.GetReplicateItemInfo, i) }
  if r[1] == nil and r[17] == nil then return nil end
  return r, CAH.GetReplicateItemLink and C.pc(CAH.GetReplicateItemLink, i)
end

function Auc:Progress(read, total, text)
  local ui = self.ui
  if not ui then return end
  ui.bar:Show()
  ui.bar:SetProgress(total > 0 and read / total or 0, text or ("%s of %s auctions"):format(Auc.Commas(read), Auc.Commas(total)))
end

-- 12345 -> "12,345"
function Auc.Commas(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""):gsub("^%-,", "-"))
end
-- seconds -> "0:41" (minutes:seconds)
function Auc.Duration(sec) return Auc.FormatWait(math.max(0, sec or 0)) end
-- how long ago, short enough for the strip: "just now", "6 min ago", "3 h ago", "2 days ago"
function Auc.ShortAgo(sec)
  sec = math.max(0, math.floor(sec or 0))
  if sec < 60 then return "just now" end
  if sec < 3600 then return math.floor(sec / 60) .. " min ago" end
  if sec < 48 * 3600 then return math.floor(sec / 3600) .. " h ago" end
  return math.floor(sec / 86400) .. " days ago"
end

-- Milliseconds, for the reading budget. Tests may replace it.
function Auc.Clock()
  local f = _G.debugprofilestop
  if f then local ok, v = pcall(f) if ok and type(v) == "number" then return v end end
  return nil
end

-- the auction house asks the game for an item it has not loaded yet (once per item and scan; a local request, not an
-- auction house request)
local function wantItem(scan, itemID)
  if not itemID or scan.asked[itemID] then return end
  scan.asked[itemID] = true
  local f = C.G and C.G("C_Item.RequestLoadItemDataByID")
  if f then pcall(f, itemID) end
end

-- 0.9.5 (item 14): one auction of a scan. Its price goes into scan.seen at once; what the saved scan and the Vendor tab
-- need is kept in scan.rows and worked out after the prices are saved (postStep, from Commit). Returns false (and the item,
-- when the game gave it) while the game has not loaded the auction's item: it is read again later (Auc:WaitItems).
function Auc:ReadRow(scan, getter, i)
  local info, link = getter(i)
  if not info then return false end
  local count, buyout, itemID, hasAll = info[3], info[10], info[17], info[18]
  if hasAll == false or not itemID then wantItem(scan, itemID) return false, itemID end
  count = (count and count > 0) and count or 1
  local key = P.ItemKey(itemID, link)
  local rows = scan.rows
  local n = rows.n + 1
  rows.n = n
  rows.key[n], rows.cnt[n], rows.bo[n], rows.idx[n], rows.gen[n] = key, count, buyout or 0, i, Auc.listGen
  -- 0.7.4 (item F): the saved scan keeps every auction: stack, buyout, bid (the current bid, else the starting bid), seller, time left
  rows.bid[n] = (type(info[11]) == "number" and info[11] > 0) and info[11] or info[8]
  rows.own[n] = info[14]
  rows.band[n] = Auc.Record and Auc.Record.Band(scan.timeFn and scan.timeFn(i), scan.zeroBased) or 0
  if buyout and buyout > 0 then
    rows.link[n] = link
    add(scan.seen, key, buyout / count, count)
  end
  return true
end

-- Read indexes first..last (or the list `only`) on the time budget, one frame after another; then done(waiting, ids), with the
-- indexes whose item the game has not loaded yet and their items (ids[j] for waiting[j], nil when the game gave none).
function Auc:ReadPass(first, last, only, getter, done, quiet)
  local scan = self.scan
  local pos, stop = only and 1 or first, only and #only or last
  local waiting, ids = {}, {}
  local function step()
    if self.scan ~= scan or scan.cancelled then return end
    local t0, k = Auc.Clock(), 0
    while pos <= stop do
      local i = only and only[pos] or pos
      pos = pos + 1
      local ok, id = self:ReadRow(scan, getter, i)
      if ok then scan.ok = scan.ok + 1 else local w = #waiting + 1 waiting[w], ids[w] = i, id end
      if not only then scan.read = scan.read + 1 end
      k = k + 1
      if t0 then
        if k % Auc.CLOCK_EVERY == 0 then local t1 = Auc.Clock() if t1 and t1 - t0 >= Auc.FRAME_MS then break end end
      elseif k >= Auc.ROWS_NOCLOCK then break end
    end
    if not quiet and not only then self:Progress(scan.read, scan.total) end
    if pos <= stop then C.After(0, step) else done(waiting, ids) end
  end
  step()
end

-- Auctions whose item is not loaded yet: when the game says an item arrived (GET_ITEM_INFO_RECEIVED, ITEM_DATA_LOAD_RESULT) the
-- auctions of that item are read again on the next frame; every Auc.LOAD_POLL seconds all that still wait are looked at again
-- (an item the game names no event for, a row with no item yet). The wait ends when none is left, nothing became readable for
-- Auc.LOAD_IDLE seconds, or after Auc.LOAD_MAX seconds; those still waiting then are counted (scan.unread).
function Auc:WaitItems(waiting, ids, getter, done, quiet)
  local scan = self.scan
  if #waiting == 0 then scan.loading = nil return done() end
  local t0 = C.GetTime()
  local L = { pending = {}, left = #waiting, byItem = {}, arrived = {}, since = t0, last = t0 }
  for j, i in ipairs(waiting) do
    L.pending[i] = true
    local id = ids and ids[j]
    if id then local b = L.byItem[id] if not b then b = {} L.byItem[id] = b end b[#b + 1] = i end
  end
  scan.loading = L
  local function words()
    if not quiet then self:Progress(scan.ok, scan.ok + L.left, ("Waiting for items: %s left"):format(Auc.Commas(L.left))) end
  end
  local again
  local function finish()
    scan.loading = nil
    scan.unread = (scan.unread or 0) + L.left
    done()
  end
  local function arm()
    if L.timer then return end
    L.timer = true
    C.After(Auc.LOAD_POLL, function() L.timer = nil L.all = true again() end)
  end
  again = function()
    if self.scan ~= scan or scan.cancelled or scan.loading ~= L or L.busy then return end
    L.kick = nil
    local list = {}
    if L.all then
      L.all, L.arrived = nil, {}
      for i in pairs(L.pending) do list[#list + 1] = i end
      table.sort(list)
    else
      for id in pairs(L.arrived) do
        for _, i in ipairs(L.byItem[id] or {}) do if L.pending[i] then list[#list + 1] = i end end
      end
      L.arrived = {}
    end
    if #list == 0 then arm() return end
    L.busy = true
    self:ReadPass(nil, nil, list, getter, function(still)
      L.busy = false
      local wait = {}
      for _, i in ipairs(still) do wait[i] = true end
      local gained = false
      for _, i in ipairs(list) do if not wait[i] and L.pending[i] then L.pending[i] = nil L.left = L.left - 1 gained = true end end
      local t = C.GetTime()
      if gained then L.last = t end
      if L.left == 0 or t - L.last >= Auc.LOAD_IDLE or t - L.since >= Auc.LOAD_MAX then return finish() end
      words()
      if next(L.arrived) and not L.kick then L.kick = true C.After(0, again) end
      arm()
    end, true)
  end
  -- an item arrived: its auctions are read on the next frame (many items arrive together)
  L.onItem = function(id)
    if id ~= nil and L.byItem[id] then L.arrived[id] = true elseif id == nil then L.all = true else return end
    if L.kick or L.busy then return end
    L.kick = true
    C.After(0, again)
  end
  words()
  arm()
end
function Auc:OnItemLoaded(id)
  local L = self.scan and self.scan.loading
  if L and L.onItem then L.onItem(tonumber(id)) end
end

-- 0.7.4: what a vendor pays for this item (copper each), cached for the length of one scan; nil when the game does not
-- know the item or the item cannot be sold to a vendor. 0.9.5: asked after the prices are saved, when the items are loaded.
local function vendorAt(cache, itemID)
  local v = cache[itemID]
  if v == nil then
    local ii = C.ItemInfo(itemID)
    v = (ii and ii.sellPrice and ii.sellPrice > 0) and ii.sellPrice or false
    cache[itemID] = v
  end
  return v or nil
end

-- 0.9.5 (item 14): after the prices are saved, the rest of the scan: every auction into the saved scan (Record.lua) and the
-- auctions below the vendor price into the Vendor tab's list. Small scans do it at once; big ones on the time budget.
local function postStep(job, budget)
  local scan, rows = job.scan, job.scan.rows
  local rec, me = scan.rec, job.me
  local t0, k = Auc.Clock(), 0
  while job.i < rows.n do
    job.i = job.i + 1
    local n = job.i
    local key, cnt, bo = rows.key[n], rows.cnt[n], rows.bo[n]
    if rec then rec:Add(key, cnt, bo, rows.bid[n], rows.own[n], rows.band[n]) end
    if bo > 0 and scan.deals then
      local id = P.KeyID(key)
      local v = id and vendorAt(scan.vendor, id)
      local owner = rows.own[n]
      if v and bo < v * cnt and not (owner ~= nil and owner == me) then      -- your own auctions cannot be bought
        local ii = C.ItemInfo(id)
        local list = scan.deals
        list[#list + 1] = { id = id, key = key, link = rows.link[n], name = ii and ii.name, icon = ii and ii.icon, quality = ii and ii.quality, count = cnt,
          buyout = bo, unit = bo / cnt, vendor = v, profit = v * cnt - bo, index = rows.idx[n], gen = rows.gen[n], owner = owner }
        if #list > Auc.MAX_DEALS * 4 then
          table.sort(list, function(a, b) return a.profit > b.profit end)
          for j = #list, Auc.MAX_DEALS + 1, -1 do list[j] = nil end
          scan.dealsCut = true
        end
      end
    end
    k = k + 1
    if budget then
      if t0 then
        if k % Auc.CLOCK_EVERY == 0 then local t1 = Auc.Clock() if t1 and t1 - t0 >= Auc.FRAME_MS then return false end end
      elseif k >= Auc.ROWS_NOCLOCK then return false end
    end
  end
  return true
end

function Auc:FinishPost(job)
  if self.post ~= job then return end
  self.post = nil
  local scan, full, t, n = job.scan, job.full, job.t, job.n
  -- 0.7.4 (item F): the scan itself is saved too (Record.lua): a partial one never replaces a full one younger than 24 hours
  if scan.rec and Auc.Record then
    local saved, why = Auc.Record.FinishScan(scan, full, t)
    if why == "kept" then
      local old = Auc.Record.Snap()
      Panoply:Print(("Your saved scan is still the full one from %s: a partial scan never replaces a full scan younger than a day."):format(Auc.Record.Ago(t - (old and old.t or t))))
    end
  end
  if scan.deals then
    table.sort(scan.deals, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return (a.index or 0) < (b.index or 0) end)
    local cut = scan.dealsCut or #scan.deals > Auc.MAX_DEALS
    for i = #scan.deals, Auc.MAX_DEALS + 1, -1 do scan.deals[i] = nil end
    for _, d in ipairs(scan.deals) do d.t = t end
    self.deals = { t = t, rows = scan.deals, kind = scan.kind, items = n, full = full and true or false, capped = cut, gen = Auc.listGen }
  end
  scan.rows = nil
  if self.ui then
    self.ui.bar:SetProgress(1, job.label)
    C.After(4, function() if self.ui and not self.scan and not self.post then self.ui.bar:Hide() end end)
    self:UpdateButton()
  end
  Panoply:Fire("AUCTION_SCAN_DONE", n, full)
end
-- Finish the work after a scan now (a new scan is starting, or the module is switched off).
function Auc:FlushPost()
  local job = self.post
  if not job then return end
  postStep(job, false)
  self:FinishPost(job)
end

function Auc:Commit(full, label)
  local scan = self.scan
  if not scan then return 0 end
  local r = P.Realm()
  local t = now()
  local n = 0
  -- the prices first: whatever happens after this, they are saved
  for key, s in pairs(scan.seen) do P.Record(key, s[1], s[2], t, r) n = n + 1 end
  if full then
    r.lastScan = t
    -- 0.9.5: how many auctions the last full scan had (a much shorter answer later is a busy server's: Auc:ServerBusy)
    if (scan.kind == "replicate" or scan.kind == "full") and (scan.total or 0) > 0 then r.lastFullCount = scan.total end
  end
  local secs = t - (scan.started or t)
  if not label then
    label = ("Done: %s items in %s"):format(Auc.Commas(n), Auc.Duration(secs))
    if full and (scan.kind == "replicate" or scan.kind == "full") then
      local miss = scan.unread or 0
      Panoply:Print(("Auction scan done: %s items from %s auctions in %s."):format(Auc.Commas(n), Auc.Commas(scan.total or 0), Auc.Duration(secs))
        .. (miss == 1 and " 1 auction was skipped: the game had not loaded its item." or miss > 1 and (" %s auctions were skipped: the game had not loaded their items."):format(Auc.Commas(miss)) or ""))
    end
  end
  scan.secs = secs
  self.scan = nil
  self.lastCount = n
  local job = { scan = scan, full = full, t = t, n = n, label = label, i = 0, me = C.pc(_G.UnitName, "player") }
  if self.post then self:FlushPost() end
  self.post = job
  scan.rows = scan.rows or { n = 0 }
  if scan.rows.n <= Auc.POST_SYNC then
    postStep(job, false)
    self:FinishPost(job)
  else
    if self.ui then self.ui.bar:SetProgress(1, ("Saving the scan: %s items"):format(Auc.Commas(n))) self:UpdateButton() end
    local function step()
      if self.post ~= job then return end
      local ok, done = pcall(postStep, job, true)
      if not ok then Panoply:Debug("auctions: after the scan", done) done = true end
      if done then self:FinishPost(job) else C.After(0, step) end
    end
    C.After(0, step)
  end
  return n
end

-- Throw the scan away (nothing read yet, or the module was switched off).
function Auc:Cancel(text)
  if not self.scan then return end
  self.scan.cancelled = true
  self.scan = nil
  if self.ui then self.ui.bar:SetProgress(0, text or "Cancelled") self:UpdateButton() end
  Panoply:Fire("AUCTION_SCAN_DONE", 0, false)
end

-- 0.9.5 (item 14): the server answered a full scan with nothing, with far fewer auctions than the last full scan, or not at
-- all. That is a busy server, not the auction house: nothing is saved and the 15-minute wait does not start (the time of
-- the last full request goes back to what it was). The same short answer twice in a row is believed (the house did shrink).
function Auc:ServerBusy(scan, n, last)
  if self.scan ~= scan then return end
  P.Realm().lastGetAll = scan.prevGetAll or 0
  self.lastShort = n
  self:Cancel("Server busy: try again shortly")
  local why = n == 0 and "no auctions" or ("%s auctions (the last full scan had %s)"):format(Auc.Commas(n), Auc.Commas(last))
  Panoply:Print(("The auction house sent %s. The server is busy: click Scan again in a minute. Nothing was saved, and the 15-minute wait did not start."):format(why))
end
local function looksBusy(self, n)
  local last = tonumber(P.Realm().lastFullCount) or 0
  if n <= 0 then return true, last end
  if last >= Auc.BUSY_MIN and n < last * Auc.BUSY_SHARE then
    local prev = self.lastShort
    if prev and math.abs(prev - n) <= n * 0.1 then return false, last end
    return true, last
  end
  return false, last
end

-- 0.6.1: the X (and closing the auction house) stops a scan but keeps the pages already read,
-- so a page-by-page scan that stops half way still updates those prices.
function Auc:Stop()
  local scan = self.scan
  if not scan then return 0 end
  if next(scan.seen) == nil then self:Cancel() return 0 end
  scan.cancelled = true
  local n = 0
  for _ in pairs(scan.seen) do n = n + 1 end
  return self:Commit(false, ("Stopped: saved %s items"):format(Auc.Commas(n)))
end

-------------------------------------------------------------------------------
-- Requests to the server: only from the player's click, one per click
-------------------------------------------------------------------------------
-- Auc:OnButton runs inside the button's OnClick and marks that one click as unused. The first
-- request uses it up; anything else (a timer, an event, a second request in the same click)
-- is refused here, so a bug can never turn into an automatic scan.
function Auc:Request(what, fn, ...)
  if not self.click or self.click.used then
    Panoply:Debug("auctions: refused a request without a click:", what)
    self.refused = (self.refused or 0) + 1
    return false
  end
  if type(fn) ~= "function" then return false end
  self.click.used = what
  -- a request that replaces the game's auction list makes every earlier position in it meaningless
  if what == "search" or what == "getAll" or what == "replicate" or what == "browse" or what == "more" or tostring(what):find("^page ") then
    Auc.listGen = Auc.listGen + 1
  end
  -- 0.7.3.1: the call's own first answer comes back too (Era PostAuction answers false when the game holds
  -- the post for the player to confirm)
  local ok, res = pcall(fn, ...)
  if not ok then Panoply:Debug("auctions: request failed", what, res) res = nil end
  self.requests = (self.requests or 0) + 1
  return ok, res
end

-- Can the server take a normal (one page) query right now? Classic only; modern always yes.
function Auc:CanQuery()
  if Auc.API() ~= "classic" or not _G.CanSendAuctionQuery then return true end
  local ok, can = pcall(CanSendAuctionQuery, "list")   -- the game's own browse button asks with "list"
  return (ok and can) and true or false
end

-------------------------------------------------------------------------------
-- Starting scans (from the Scan click)
-------------------------------------------------------------------------------
function Auc:Start(force)
  if self.scan then return false, "busy" end
  local api = Auc.API()
  if not api then return false, "no auction house API" end
  if not self.click or self.click.used then return false, "needs a click" end
  if self.Trade and self.Trade.pending then return false, "busy" end      -- a search is waiting for its answer
  local wait = self:FullScanWait()
  -- 0.9.5 (item 14): Forever scans in one go or not at all. During the wait nothing is asked for (the old browse plus up to
  -- 200 "Load more" clicks took about 15 minutes): the click opens the shopping list instead (Auc:OnButton)
  if api == "replicate" and wait > 0 then return false, "wait" end
  if Panoply.db and Panoply.db.auctionSlowScan and api == "classic" then force = force or "paged" end
  if self.post then self:FlushPost() end
  local r = P.Realm()
  self.scan = { seen = {}, rows = { n = 0, key = {}, cnt = {}, bo = {}, bid = {}, own = {}, band = {}, idx = {}, link = {}, gen = {} },
    asked = {}, read = 0, ok = 0, total = 0, page = -1, pages = nil, started = now(), state = "asking", deals = {}, vendor = {}, prevGetAll = r.lastGetAll }
  local scan = self.scan
  local sent
  if api == "classic" then
    if wait <= 0 and force ~= "paged" then
      scan.kind = "full"
      sent = self:Request("getAll", _G.QueryAuctionItems, "", nil, nil, 0, false, nil, true, false, nil)
      if sent then r.lastGetAll = now() end
    else
      scan.kind = "paged"
      sent = self:QueryPage(0)
    end
  elseif api == "replicate" then
    scan.kind = "replicate"
    sent = self:Request("replicate", _G.C_AuctionHouse.ReplicateItems)
    if sent then r.lastGetAll = now() end
  else
    scan.kind = "browse"
    scan.waiting = true
    sent = self:Request("browse", _G.C_AuctionHouse.SendBrowseQuery, { searchString = "", sorts = {}, filters = {} })
  end
  if not sent then
    self.scan = nil
    self:UpdateButton()
    return false, "server busy"
  end
  if Auc.Record then scan.rec = Auc.Record.NewSnap(scan.kind) end
  self:Progress(0, 1, scan.kind == "paged" and "Page 1: asking the auction house..." or "Asking the auction house...")
  self:UpdateButton()
  -- a full scan that gets no answer at all: the server is busy (a local timer; it never asks the server for anything)
  if scan.kind == "full" or scan.kind == "replicate" then
    C.After(Auc.ANSWER_WAIT, function()
      if self.scan == scan and scan.state == "asking" then self:ServerBusy(scan, 0, tonumber(P.Realm().lastFullCount) or 0) end
    end)
  end
  return true, scan.kind
end

-- Paged scan: ask for one page (0-based). Only from a click; refused while the server is busy.
function Auc:QueryPage(page)
  local scan = self.scan
  if not scan or scan.cancelled then return false end
  if not self:CanQuery() then return false end
  local sent = self:Request("page " .. (page + 1), _G.QueryAuctionItems, "", nil, nil, page, false, nil, false, false, nil)
  if sent then scan.page, scan.waiting, scan.state = page, true, "asking" end
  return sent
end

-- The "Next page" / "Load more" click.
function Auc:Next()
  local scan = self.scan
  if not scan or scan.state ~= "ready" then return false end
  if scan.kind == "paged" then
    if not self:CanQuery() then
      if self.ui then self.ui.wait:SetText("Server busy: click again in a moment") end
      return false
    end
    local ok = self:QueryPage(scan.page + 1)
    if ok then self:Progress(scan.page, scan.pages or 1, ("Page %d of %d: asking..."):format(scan.page + 1, scan.pages or 1)) end
    self:UpdateButton()
    return ok
  elseif scan.kind == "browse" then
    local CAH = _G.C_AuctionHouse
    scan.more = (scan.more or 0) + 1
    scan.waiting, scan.state = true, "asking"
    local ok = self:Request("more", CAH and CAH.RequestMoreBrowseResults)
    if not ok then scan.waiting, scan.state = false, "ready" end
    self:UpdateButton()
    return ok
  end
  return false
end

-------------------------------------------------------------------------------
-- Answers from the server (events): read them, never ask again from here
-------------------------------------------------------------------------------
function Auc:OnListUpdate()
  local scan = self.scan
  if not scan then return self:Passive() end
  if scan.kind == "full" then
    if scan.reading then return end
    scan.reading, scan.state = true, "reading"
    scan.timeFn = classicTime
    local batch = C.pc(_G.GetNumAuctionItems, "list") or 0
    local busy, last = looksBusy(self, batch)
    if busy then return self:ServerBusy(scan, batch, last) end
    self.lastShort = nil
    scan.total = batch
    self:UpdateButton()
    self:ReadPass(1, batch, nil, classicInfo, function(waiting, ids)
      self:WaitItems(waiting, ids, classicInfo, function() self:Commit(true) end)
    end)
  elseif scan.kind == "paged" and scan.waiting then
    scan.waiting, scan.state = false, "reading"
    scan.timeFn = classicTime
    local batch, total = C.pc(_G.GetNumAuctionItems, "list")
    batch, total = batch or 0, total or 0
    scan.pages = math.max(1, math.ceil(total / Auc.PAGE))
    scan.total = total
    self:UpdateButton()
    -- each page waits for its items before the next click, since the next page reuses indexes 1..50
    scan.read = 0
    self:ReadPass(1, batch, nil, classicInfo, function(waiting, ids)
      self:WaitItems(waiting, ids, classicInfo, function()
        scan.pagesRead = (scan.pagesRead or 0) + 1
        local label = ("Page %d of %d"):format(scan.page + 1, scan.pages)
        if scan.page + 1 < scan.pages then
          -- wait for the player's next click; nothing is asked for from here
          scan.state = "ready"
          self:Progress(scan.page + 1, scan.pages, label)
          self:UpdateButton()
        else
          self:Progress(1, 1, label)
          self:Commit(true)
        end
      end, true)
    end, true)
  end
end

function Auc:OnReplicate()
  local scan = self.scan
  if not scan or scan.kind ~= "replicate" or scan.reading then return end
  scan.reading, scan.state = true, "reading"
  local CAH = _G.C_AuctionHouse
  -- the time left of a replicate row, when the client has it (the band is counted from 0 there: UNVERIFIED)
  if CAH.GetReplicateItemTimeLeft then scan.timeFn, scan.zeroBased = function(i) return C.pc(CAH.GetReplicateItemTimeLeft, i) end, true end
  local n = C.pc(CAH.GetNumReplicateItems) or 0
  -- 0.9.5 (item 14): an empty or much too short answer is a busy server's (not saved, the wait does not restart)
  local busy, last = looksBusy(self, n)
  if busy then return self:ServerBusy(scan, n, last) end
  self.lastShort = nil
  scan.total = n
  self:UpdateButton()
  -- replicate indexes start at 0
  self:ReadPass(0, n - 1, nil, replicateInfo, function(waiting, ids)
    self:WaitItems(waiting, ids, replicateInfo, function() self:Commit(true) end)
  end)
end

local function browseRecord(seen, results, scan)
  for _, r in ipairs(results or {}) do
    local k = r.itemKey
    if k and k.itemID and r.minPrice and r.minPrice > 0 then
      local key = (k.itemSuffix and k.itemSuffix ~= 0) and (k.itemID .. ":" .. k.itemSuffix) or k.itemID
      add(seen, key, r.minPrice, r.totalQuantity or 1)
      -- the saved scan of a browse: one row for each item, its lowest price and how many are listed (the game gives no list of
      -- auctions here, so the scan's summary of the item has no market price: Record.lua)
      if scan and scan.rec then
        local q = math.max(1, math.floor(tonumber(r.totalQuantity) or 1))
        scan.rec:Add(key, q, r.minPrice * q, 0, nil, 0)
      end
      -- the Vendor tab: the cheapest unit of this item is below what a vendor pays (bought by quantity: UNVERIFIED shape)
      local v = scan and scan.deals and vendorPrice(scan, k.itemID)
      if v and r.minPrice < v then
        local ii = C.ItemInfo(k.itemID)
        scan.deals[#scan.deals + 1] = { id = k.itemID, key = key, name = ii and ii.name or nil, icon = ii and ii.icon, quality = ii and ii.quality, count = 1,
          buyout = r.minPrice, unit = r.minPrice, vendor = v, profit = v - r.minPrice, browse = true, gen = Auc.listGen }
      end
    end
  end
end
Auc.BrowseRecord = browseRecord

function Auc:OnBrowse()
  local CAH = _G.C_AuctionHouse
  local scan = self.scan
  local results = CAH and CAH.GetBrowseResults and C.pc(CAH.GetBrowseResults) or {}
  if not scan or scan.kind ~= "browse" then
    if Panoply.db and Panoply.db.auctionPassive ~= false then
      local seen = {}
      browseRecord(seen, results)
      for key, s in pairs(seen) do P.Record(key, s[1], s[2]) end
    end
    return
  end
  scan.seen, scan.deals = {}, {}
  if Auc.Record then scan.rec = Auc.Record.NewSnap("browse") end      -- the list holds every batch so far: read it again whole
  browseRecord(scan.seen, results, scan)
  scan.read, scan.total = #results, #results
  scan.waiting = false
  local full = CAH.HasFullBrowseResults and C.pc(CAH.HasFullBrowseResults)
  if full or not CAH.RequestMoreBrowseResults then
    scan.partialBrowse = not full                                     -- stopped before the game said the list was complete
    self:Commit(true)
  else
    -- more results exist: the player clicks "Load more" for the next batch
    scan.state = "ready"
    self:Progress(scan.read, math.max(scan.read, 1), ("Loaded %d items"):format(scan.read))
    self:UpdateButton()
  end
end

-- Normal browsing on Classic: remember what is on the page being looked at.
function Auc:Passive()
  if not Panoply.db or Panoply.db.auctionPassive == false or Auc.API() ~= "classic" then return 0 end
  local batch = C.pc(_G.GetNumAuctionItems, "list") or 0
  if batch <= 0 or batch > Auc.PAGE * 2 then return 0 end   -- a huge list is someone else's full scan
  local seen = {}
  for i = 1, batch do local info, link = classicInfo(i) if info then readOne(seen, info, link) end end
  local n = 0
  for key, s in pairs(seen) do P.Record(key, s[1], s[2]) n = n + 1 end
  return n
end

-- Neutral auction houses (Booty Bay, Gadgetzan, Everlook): the auctioneer has no faction.
-- Unverified in the real client; only used while the auction house is open.
function Auc:DetectNeutral()
  P.ahFaction = nil
  if _G.UnitExists and C.pc(_G.UnitExists, "npc") then
    local f = C.pc(_G.UnitFactionGroup, "npc")
    if f == nil or f == "Neutral" then P.ahFaction = "Neutral" end
  end
end

-------------------------------------------------------------------------------
-- UI on the auction house window
-------------------------------------------------------------------------------
-- 0.9.5 (item 13): Scan and Auction window are real tabs hung from the TOP edge of the game's auction window, drawn like
-- Panoply's bottom tabs (Host.lua) and outside the window, so nothing of the game's (Filter, Search, the close X) sits on
-- them or over them. In 0.9.4 they were slim buttons inside the window's header, where Forever's own header drew over them
-- (2026-11-15: "only a faint outline"). Right to left: Scan, Auction window, then a status plate with the countdown or
-- "Asking...", and while a scan runs its progress bar and stop button.
-- When the window sits so high that the tabs would leave the screen, the strip hangs down from the same edge instead, inside the
-- window's header (its right end holds only the close X, which the strip stays clear of).
-- UNVERIFIED in a real client: the game windows' exact top edge (the strip touches GetTop of AuctionFrame / AuctionHouseFrame).
Auc.BUTTON_W = 104          -- the Scan tab's smallest width
Auc.TAB_H = 30              -- the bottom tabs' height (Skin.Tab)
Auc.STRIP_RIGHT = 40        -- the strip's right end, in from the window's right edge: clear of the close X
Auc.BAR_W = 212             -- room for "160,990 of 160,990 auctions" and "Server busy: try again shortly" above it at 1.3x text
Auc.SCAN_LABELS = { "Scan", "Next page", "Load more", "Shopping" }
Auc.SCAN_TIP = "Each click asks the auction house once. A full scan is allowed about once every 15 minutes; otherwise click Scan for page 1, then Next page for each page after it."
Auc.SCAN_TIP_FOREVER = "Each click asks the auction house once. A full scan is allowed about once every 15 minutes and is read in about a minute; while you wait, this opens your shopping list for quick searches."
function Auc.ScanTip() return Auc.API() == "replicate" and Auc.SCAN_TIP_FOREVER or Auc.SCAN_TIP end

-- One tab of the strip: Skin.Tab with the bottom tabs' brass dot, plus a pressed look and a resting (disabled) look.
local function topTab(parent, label, onClick, tip, tipBody)
  local t = Skin.Tab(parent, label, 110, nil, tip, tipBody)
  local dot = t:CreateTexture(nil, "OVERLAY")
  dot:SetSize(6, 6)
  Skin.Round(dot, 3, Skin.TEX.RFill)
  dot:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], 1)
  dot:SetPoint("LEFT", t, "LEFT", 12, 0)
  t.dot = dot
  local function seat(dy) t.label:ClearAllPoints(); t.label:SetPoint("CENTER", t, "CENTER", 7, dy) end
  seat(0)
  local paint = t.Paint
  function t:Paint()
    paint(self)
    if self.pressed then
      local f = Skin.colors.tabFillSel
      self.bg:SetVertexColor(f[1], f[2], f[3], 1)
    end
    if self.disabled then
      local c = Skin.colors.dim
      self.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    self.dot:SetAlpha(self.disabled and 0.4 or 1)
  end
  function t:SetEnabledLook(on)
    self.disabled = not on
    if self.disabled then self.pressed = nil seat(0) end
    self:Paint()
  end
  function t:NeedWidth() return math.ceil(Skin.TextWidth(self.label) + 2 * Skin.SP.l + 18) end
  -- the tooltip still shows on a resting tab (it says why); the tab itself does not light up
  t:SetScript("OnEnter", function(self) self.hover = not self.disabled self:Paint() if self.panoplyShowTip then self.panoplyShowTip() end end)
  t:SetScript("OnLeave", function(self) self.hover = false self.pressed = nil seat(0) self:Paint() if _G.GameTooltip then GameTooltip:Hide() end end)
  t:SetScript("OnMouseDown", function(self) if self.disabled then return end self.pressed = true seat(-1) self:Paint() end)
  t:SetScript("OnMouseUp", function(self) self.pressed = nil seat(0) self:Paint() end)
  t:SetScript("OnClick", function(self, button) if not self.disabled and onClick then onClick(self, button) end end)
  t:Paint()
  return t
end
Auc.TopTab = topTab

function Auc:BuildUI()
  local host = Auc.Frame()
  if not host or self.ui then return self.ui end
  local ui = CreateFrame("Frame", "PanoplySuiteAuctionScan", host)
  ui:SetSize(410, Auc.TAB_H)
  if ui.SetFrameLevel and host.GetFrameLevel then ui:SetFrameLevel((C.pc(host.GetFrameLevel, host) or 1) + 50) end
  local b = topTab(ui, "Scan", function() Auc:OnButton() end, "Scan the auction house", Auc.SCAN_TIP)
  b:SetPoint("BOTTOMRIGHT", ui, "BOTTOMRIGHT", 0, 0)
  -- 0.7.3: this opens the Auction window (shopping, cancelling, history; 0.7.4: selling moved to the Sell tab). 0.9.5: called
  -- "Auction window", not "Trade" (in WoW, Trade is the player-to-player window). Its tab is lit while that window is open.
  local tb = topTab(ui, "Auction window", function() if Auc.Panel then Auc.Panel:Toggle() end Auc:UpdateButton() end, "Auction window",
    "Shopping lists, cancelling undercut auctions and price history. Selling, buying and vendor deals are the three Panoply Suite tabs of this window. Every search, post, cancel and purchase is one click.")
  tb:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -4, 0)
  -- the status plate: the countdown or "Asking...", and while a scan runs the stop button and progress bar
  local plate = CreateFrame("Frame", nil, ui)
  plate:SetSize(140, Auc.TAB_H)
  plate.panoplyBox = true
  plate.bg, plate.rim = Skin.Box(plate, "S", { fill = Skin.colors.tabFillIdle, fillA = 1, line = Skin.colors.hairline })
  plate:SetPoint("BOTTOMRIGHT", tb, "BOTTOMLEFT", -4, 0)
  local wait = Skin.Text(plate, 10, Skin.colors.tabIdle or Skin.colors.text)
  if wait.SetWordWrap then wait:SetWordWrap(false) end
  -- 0.6.0: a thin bar low in the plate, its label above it (never on the fill)
  local bar = Skin.Bar(plate, 6)
  bar:SetWidth(Auc.BAR_W); bar.panoplyWidth = Auc.BAR_W
  bar:Hide()
  local x = Skin.Button(plate, "", 18, 18, function() Auc:Stop() end, "Stop the scan", "Keeps the prices already read.")
  if x.SetIcon then x:SetIcon("Close", 11) end
  x:Hide()
  ui.button, ui.bar, ui.cancel, ui.wait, ui.trade, ui.plate = b, bar, x, wait, tb, plate
  -- whatever changes the plate's contents lays the strip out again (the hint is also set straight from Next)
  local set = wait.SetText
  function wait:SetText(text) set(self, text) Auc:LayoutStrip() end
  for _, f in ipairs({ bar, x }) do
    if f.HookScript then
      f:HookScript("OnShow", function() Auc:LayoutStrip() end)
      f:HookScript("OnHide", function() Auc:LayoutStrip() end)
    end
  end
  self.ui = ui
  self:PlaceUI()
  self:UpdateButton()
  return ui
end

-- Above the window's top edge when the screen has room for the tabs there, else just inside that edge.
function Auc:PlaceUI()
  local ui, host = self.ui, Auc.Frame()
  if not ui or not host then return end
  local top = host.GetTop and C.pc(host.GetTop, host)
  local par = _G.UIParent
  local room = par and par.GetTop and C.pc(par.GetTop, par)
  local hs = host.GetEffectiveScale and C.pc(host.GetEffectiveScale, host) or 1
  local ps = par and par.GetEffectiveScale and C.pc(par.GetEffectiveScale, par) or 1
  local above = not (top and room) or (top + Auc.TAB_H) * hs <= room * ps + 0.5
  ui:ClearAllPoints()
  if above then
    ui:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", -Auc.STRIP_RIGHT, 0)
  else
    ui:SetPoint("TOPRIGHT", host, "TOPRIGHT", -Auc.STRIP_RIGHT, 0)      -- hung down from the same edge, over the header's empty right end
  end
  ui.above = above
end

-- Widths from the words at the player's text size: the Scan tab fits its longest label, so it never jumps while it changes.
function Auc:LayoutStrip()
  local ui = self.ui
  if not ui or not ui.plate then return end
  local b, tb, plate, bar, x, wait = ui.button, ui.trade, ui.plate, ui.bar, ui.cancel, ui.wait
  local cur, sw = b.label:GetText(), Auc.BUTTON_W
  for _, l in ipairs(Auc.SCAN_LABELS) do b.label:SetText(l) sw = math.max(sw, b:NeedWidth()) end
  b.label:SetText(cur)
  b:SetWidth(sw)
  tb:SetWidth(math.max(124, tb:NeedWidth()))
  local hasText = (wait:GetText() or "") ~= ""
  local barOn, xOn = bar:IsShown(), x:IsShown()
  local off = 10                       -- laid out right to left, from the plate's right edge
  wait:ClearAllPoints()
  if hasText then
    wait:SetPoint("RIGHT", plate, "RIGHT", -off, 0)
    off = off + math.ceil(Skin.TextWidth(wait)) + 2 + 12
  end
  bar:ClearAllPoints()
  if barOn then
    bar:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -off, 3)      -- low, so its label above it stays inside the plate
    off = off + Auc.BAR_W + 8
  end
  x:ClearAllPoints()
  if xOn then
    x:SetPoint("RIGHT", plate, "RIGHT", -off, 0)
    off = off + 18 + 8
  end
  local w = off                        -- the last gap is the left padding
  plate:SetWidth(w)
  -- inside the window's header (no room above it) the plate shows only while a scan runs, so it covers the header's title only
  -- then; the countdown is also in the Scan tab's tooltip
  if (hasText and ui.above ~= false) or barOn or xOn then plate:Show() else plate:Hide() end
  ui:SetWidth(sw + 4 + tb:GetWidth() + 4 + w)
end

-- The button's click: exactly one server request at most (Start, Next page or Load more).
function Auc:OnButton()
  self.click = { used = false }
  local ok, err = pcall(function()
    local scan = self.scan
    if not scan then
      local ok, why = self:Start()
      if not ok and why == "wait" then self:QuickSearch() end
    elseif scan.state == "ready" then self:Next() end
    -- asking / reading: the button is greyed out and does nothing
  end)
  self.click = nil
  if not ok then Panoply:Debug("auctions: click", err) end
end

-- 0.9.5 (item 14): Forever during the 15-minute wait: the Auction window opens on the shopping list, where each item on the
-- list is one quick search (one click, one request: Shopping.lua). Nothing is asked for from here.
function Auc:QuickSearch()
  local Panel = Auc.Panel
  if not Panel then return false end
  Panel:Show()
  if Panel.Select then Panel:Select("shopping") end
  self:UpdateButton()
  return true
end
-- Forever's wait, in words: "Full scan in 9:00 · last 6 min ago" (the strip) and a sentence for the tooltip
function Auc:WaitWords(w)
  local last = tonumber(P.Realm().lastScan) or 0
  local ago = last > 0 and Auc.ShortAgo(now() - last) or nil
  local short = "Full scan in " .. Auc.FormatWait(w) .. (ago and (" · last " .. ago) or "")
  local long = ("A full scan is allowed again in %s. %s Meanwhile this opens your shopping list: each item on it is one quick search.")
    :format(Auc.FormatWait(w), ago and ("Your last full scan was " .. (Auc.Record and Auc.Record.Ago(now() - last) or ago) .. ".") or "There is no full scan on this realm yet.")
  return short, long
end

function Auc:UpdateButton()
  local ui = self.ui
  if not ui then return end
  local b, scan = ui.button, self.scan
  local label, enabled, hint
  local waitTip
  if not scan then
    local w = self:FullScanWait()
    label, enabled = "Scan", true
    hint = w > 0 and ("Full scan in " .. Auc.FormatWait(w))
      or (Panoply.db and Panoply.db.auctionAutoScan and "Full scan ready: click Scan" or "Full scan ready")
    if w > 0 and Auc.API() == "replicate" then
      label = "Shopping"
      hint, waitTip = self:WaitWords(w)
    end
    ui.cancel:Hide()
  else
    ui.cancel:Show()
    if scan.state == "ready" then
      label = scan.kind == "browse" and "Load more" or "Next page"
      enabled = scan.kind ~= "paged" or self:CanQuery()
      if scan.kind == "paged" then
        hint = enabled and ("Click for page %d"):format(scan.page + 2) or "Server busy: a moment..."
      else
        hint = "One batch per click"
      end
    else
      label = scan.kind == "paged" and "Next page" or (scan.kind == "browse" and "Load more" or "Scan")
      enabled = false
      hint = scan.state == "asking" and "Asking..." or "Reading..."
    end
  end
  b.label:SetText(label)
  if b.SetEnabledLook then b:SetEnabledLook(enabled) end
  ui.wait:SetText(hint)
  b.tipBody = waitTip and (hint .. "\n\n" .. waitTip) or ((hint and hint ~= "") and (hint .. "\n\n" .. Auc.ScanTip()) or Auc.ScanTip())
  -- the Auction window tab is lit while that window is open (its own close button included)
  local pf = Auc.Panel and Auc.Panel.frame
  if pf and not pf.panoplyAucTab and pf.HookScript then
    pf.panoplyAucTab = true
    pf:HookScript("OnShow", function() Auc:UpdateButton() end)
    pf:HookScript("OnHide", function() Auc:UpdateButton() end)
  end
  ui.trade:SetActive(pf and pf:IsShown() and true or false)
  self:LayoutStrip()
end

function Auc:OnShow()
  self:DetectNeutral()
  self:BuildUI()
  if self.ui then self:PlaceUI() self.ui:Show() self:UpdateButton() end
  if self.Host and self.Host:Setup() then self.Host:SetEnabled(true) end      -- 0.7.4: the three Panoply Suite tabs
  if not self.ticker then
    -- only refreshes the button text (countdown, "server busy"); it never sends anything
    self.ticker = C.NewTicker(1, function() if Auc.ui and Auc.ui:IsShown() and (not Auc.scan or Auc.scan.state == "ready") then Auc:UpdateButton() end end)
  end
  -- 0.6.1: the old "scan automatically" option now only points at the button
  if Panoply.db and Panoply.db.auctionAutoScan and not self.scan and self:FullScanWait() <= 0 then
    Panoply:Print("A full auction scan is ready: click Scan on the auction house window.")
  end
end

function Auc:OnClose()
  self.open = false
  if self.scan then self:Stop() end
  if self.ticker and self.ticker.Cancel then self.ticker:Cancel() end
  self.ticker = nil
  P.ahFaction = nil
end

Auc:On("AUCTION_HOUSE_SHOW", function() Auc.open = true Auc:OnShow() end)
Auc:On("AUCTION_HOUSE_CLOSED", function() Auc:OnClose() end)
Auc:On("AUCTION_ITEM_LIST_UPDATE", function() Auc:OnListUpdate() end)
Auc:On("REPLICATE_ITEM_LIST_UPDATE", function() Auc:OnReplicate() end)
Auc:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() Auc:OnBrowse() end)
Auc:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() Auc:OnBrowse() end)
-- 0.9.5 (item 14): an item the game loaded: a scan waiting for it reads its auctions again (Panoply:On, so Record.lua's own
-- GET_ITEM_INFO_RECEIVED handler stays as it is)
Panoply:On("GET_ITEM_INFO_RECEIVED", function(_, id) Auc:OnItemLoaded(id) end)
Panoply:On("ITEM_DATA_LOAD_RESULT", function(_, id) Auc:OnItemLoaded(id) end)

function Auc:Enable() end
function Auc:Disable()
  if self.scan then self:Cancel() end
  if self.post then self:FlushPost() end
  if self.ui then self.ui:Hide() end
  if self.Panel then self.Panel:Hide() end
  if self.Host then self.Host:SetEnabled(false) end
  if self.Trade then self.Trade.pending = nil end
end
