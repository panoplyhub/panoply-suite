-- Auctions: the one view of the saved auction data (0.9.5 phase 4E, docs/specs/page-redesigns-v1.md section 7). The Auctions page of
-- the main window and the pop-out window (Browser.lua) both draw this view; they share what is chosen in it (the tab, the search, the
-- category, the open item, the History filters), so the pop-out shows the same tabs as the page.
--
--   The strip (pinned)  the scan freshness chip (green under a day, amber 1 to 3 days, red over 3 days), "160,990 auctions · 9,842
--                       items", the storage meter (its tooltip has the 8 MB cap), Open Auction window (only at the auction house), and
--                       once: "View only here. Buying and posting happen in the Auction window."
--   Tabs (pinned)       Prices · Upgrades · History (Narrow: a dropdown), and on the page the pop-out button at the right of the bar.
--   Prices              one row per item: icon, name in its quality colour, listings, quantity, lowest each, market each, the trend
--                       against the scan before. A click opens the item: a 14-point sparkline of its lowest price and, for an item on
--                       a shopping list, its kept auctions. Search and the game's categories. A column with nothing in it is hidden.
--   Upgrades            the shared slot grid (UI/SlotGrid.lua) with the gear engine's best auction house piece for each slot and its
--                       price; a click lists that slot's candidates. "Only what I can afford" counts the gold of every character of
--                       this realm and faction (Hearth Hall). The header names the plan: "Beast Mastery Hunter, level 15".
--   History             Bought · Sold · Didn't sell as stat cells (counts and coins; the auction house cut in Sold's tooltip), the
--                       character and period menus, the table. With nothing recorded the whole tab is one line.
--   Bands (7.4)         Wide: every column; the Upgrades grid beside the slot's candidates. Medium: Prices hides the trend; the grid
--                       above the candidates. Narrow: Prices shows name, lowest and market (the rest on the open row); the stat cells
--                       stack.
-- VIEW ONLY: nothing here buys, posts or cancels, asks the auction house for anything or calls anything protected.
-- The gear engine's auction source (Panoply.GearSources.auctionData) reads the saved scan here, whether or not anything is open.
local ADDON, Panoply = ...
local C, Skin, Kit = Panoply.Compat, Panoply.Skin, Panoply.Kit
local P = Panoply.Prices
local Auc = Panoply.Auctions
local R = Auc.Record
local Host, Panel = Auc.Host, Auc.Panel
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local V = { infoCache = {}, views = {} }
Auc.View = V
V.ROW_H = 26
V.WHEEL = 3
V.GRIP = 22                   -- room under the scrolling part for a window's resize grip
V.FRESH, V.STALE = 86400, 3 * 86400     -- the freshness chip: green under a day, amber up to 3 days, red after
V.PERIODS = { { 7, "Last 7 days" }, { 30, "Last 30 days" }, { 0, "All kept" } }
V.GEAR_CLASS = { [2] = true, [4] = true }   -- the game's item classes: weapon, armor
V.MAX_CANDIDATES = 12         -- candidates listed for the chosen slot
-- what is chosen in the view (shared by the page and the pop-out)
V.state = { tab = "prices", query = "", sort = { key = "name", asc = true }, histKind = "sold", period = 30 }

-- the page's accent (spec 1.1 names none for Auctions): steel blue. Its icon slots (icon.ui.popout, icon.trend.up / down,
-- icon.coin.gold) are the kit's own (UI/KitParts.lua).
Kit.TOKENS["accent.auctions"] = Kit.TOKENS["accent.auctions"] or "accentSteel"

local function money(c) return P.Money(c) end
local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end
local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

-------------------------------------------------------------------------------
-- Words (also read by the tests and the previews)
-------------------------------------------------------------------------------
V.WORDS = {
  viewOnly = "View only here. Buying and posting happen in the Auction window.",
  noScan = "No scan yet. Open the auction house and click Scan: tooltips, this page and the gear pages then have prices.",
  noMatch = "No item in the scan matches.",
  histEmpty = "Nothing yet. Panoply records what you buy, sell and post from now on, for each character.",
  openTip = "Opens Panoply's Auction window beside the auction house: shopping lists, cancelling and history, one click per request.",
  openAway = "Only at the auction house. Talk to an auctioneer first.",
  freshTip = "Scan at the auction house",
  popTip = "Opens these tabs in their own window, to keep beside the game.",
}
V.HELP = {
  prices = "One row per item of the last scan: how many listings, how many items in all, the lowest buyout for one, and the market price (the middle of all the listed items' prices, counted by quantity). The arrow compares the lowest price with the scan before. Click a row for its lowest price on each of the last 14 days it was scanned.",
  upgrades = "The best piece for each slot on the auction house, ranked by the gear engine for your plan's stat weights, up to your level. The price is the lowest buyout in the last scan.",
  history = "What your characters bought, sold and listed that did not sell, kept on this computer from the time Panoply saw it happen.",
}

-- The freshness of a scan: "good" | "warn" | "bad" and its words
function V.Freshness(t, now)
  now = now or P.Now()
  if not t or t <= 0 then return "state.idle", "No scan yet" end
  local age = max(0, now - t)
  local tok = age < V.FRESH and "state.good" or (age <= V.STALE and "state.warn" or "state.bad")
  return tok, ("Scanned %s"):format(R.Ago(age))
end

-------------------------------------------------------------------------------
-- Items (names, icons and categories come from the game's own item information)
-------------------------------------------------------------------------------
function V.LinkOf(key)
  local id, suffix = tostring(key):match("^(%d+):?(%-?%d*)$")
  if not id then return nil end
  if suffix and suffix ~= "" then return ("item:%s:0:0:0:0:0:%s"):format(id, suffix) end
  return "item:" .. id
end
function V.ItemInfo(key)
  local c = V.infoCache[key]
  if c and not c.pending then return c end
  local id = P.KeyID(key)
  local ii = id and C.ItemInfo(id)
  if ii and ii.name then
    c = { name = ii.name, lname = ii.name:lower(), icon = ii.icon or C.ItemIcon(id), quality = ii.quality, class = ii.classID, id = id }
  else
    local nm = "Item " .. tostring(id or key)
    c = { name = nm, lname = nm:lower(), pending = true, id = id }
  end
  V.infoCache[key] = c
  return c
end
local function className(classID)
  local f = (_G.C_Item and C_Item.GetItemClassInfo) or _G.GetItemClassInfo
  local n = classID and C.pc(f, classID)
  return type(n) == "string" and n ~= "" and n or nil
end
V.CLASS_ORDER = { 2, 4, 1, 0, 7, 6, 11, 9, 5, 12, 15, 3, 8, 13, 10, 14, 16, 17, 18 }

-------------------------------------------------------------------------------
-- The scan being looked at
-------------------------------------------------------------------------------
-- the key: chosen (the pop-out opened for another realm or faction), else the latest scan of this realm
function V:Key() return self.state.snapKey or R.LatestKey() end
function V:Snap() return R.Snap(self:Key()) end

-- The scan's items decoded once per scan: { items = { R.Item + info }, byKey, cats, trend (any item has an earlier point),
-- pending = { [key] = true } }
function V:Load()
  local snap = self:Snap()
  local c = self.cache
  if c and c.snap == snap and c.t == (snap and snap.t) then
    -- 0.9.7 in-game hotfix: items the game named while this page was closed were never filled in (the answer is only listened for
    -- while the page shows), so their rows kept "Item 123" and the "?". They are looked at again here, at most every V.INFO_EVERY s.
    local now = C.GetTime()
    if next(c.pending) and (not c.pendingAt or now - c.pendingAt >= V.INFO_EVERY) then
      c.pendingAt = now
      if self:ResolvePending() then c = nil end
    end
    if c then return c end
  end
  c = { snap = snap, t = snap and snap.t, items = {}, byKey = {}, pending = {}, classes = {} }
  self.cache = c
  if not snap then return c end
  for _, it in ipairs(R.Items(snap)) do
    it.info = V.ItemInfo(it.key)
    if it.info.pending then c.pending[it.key] = true end
    local cls = it.info.class or it.class
    it.cls = cls
    if cls then c.classes[cls] = true end
    local prev = it.trend[1]
    if prev then
      c.trend = true
      local a, b = it.low or it.market, (prev[2] > 0 and prev[2]) or (prev[3] > 0 and prev[3]) or nil
      if a and b then it.change = (a - b) / b end
    end
    if it.low then c.anyLow = true end
    if it.market then c.anyMarket = true end
    c.items[#c.items + 1] = it
    c.byKey[it.key] = it
  end
  local cats = {}
  for _, id in ipairs(V.CLASS_ORDER) do
    if c.classes[id] then cats[#cats + 1] = { id = id, name = className(id) or ("Category " .. id) } end
  end
  local rest = {}
  for id in pairs(c.classes) do
    local listed = false
    for _, e in ipairs(cats) do if e.id == id then listed = true end end
    if not listed then rest[#rest + 1] = id end
  end
  table.sort(rest)
  for _, id in ipairs(rest) do cats[#cats + 1] = { id = id, name = className(id) or ("Category " .. id) } end
  c.cats = cats
  c.sorted = nil
  return c
end
function V:Forget() self.cache = nil self.infoCache = {} end

-- sorting the Prices rows
V.SORTS = {
  name = { "Item name", "A to Z", "Z to A", true },
  listings = { "Listings", "few first", "most first", false },
  qty = { "Quantity", "few first", "most first", false },
  low = { "Lowest each", "low first", "high first", true },
  market = { "Market each", "low first", "high first", true },
  trend = { "Trend", "falling first", "rising first", true },
}
local function byName(a, b)
  if a.info.lname ~= b.info.lname then return a.info.lname < b.info.lname end
  return tostring(a.key) < tostring(b.key)
end
local function numberCmp(field, asc)
  return function(a, b)
    local x, y = a[field], b[field]
    if x == nil or y == nil then
      if x == nil and y == nil then return byName(a, b) end
      return y == nil
    end
    if x ~= y then if asc then return x < y end return x > y end
    return byName(a, b)
  end
end
function V:Compare()
  local s = self.state.sort
  local f = s.key == "trend" and "change" or s.key
  if s.key == "name" then
    if s.asc then return byName end
    return function(a, b) return byName(b, a) end
  end
  return numberCmp(f, s.asc)
end
function V:SetSort(key, asc)
  local s = self.state.sort
  if asc == nil then
    if s.key == key then asc = not s.asc else asc = V.SORTS[key] and V.SORTS[key][4] end
  end
  self.state.sort = { key = key, asc = asc and true or false }
  if self.cache then self.cache.sorted = nil end
  self:Top()
  self:RefreshAll()
end

-- the rows of the Prices list: the items that match, sorted, with the open item's own rows under it
function V:PriceRows()
  local c = self:Load()
  if not c.sorted then
    table.sort(c.items, self:Compare())
    c.sorted = true
  end
  local q = (self.state.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cat = self.state.cat
  local out, n = {}, 0
  for _, it in ipairs(c.items) do
    if (not cat or it.cls == cat) and (q == "" or it.info.lname:find(q, 1, true)) then
      n = n + 1
      out[#out + 1] = it
      if self.state.open == it.key then
        out[#out + 1] = { detail = "spark", item = it }
        for _, l in ipairs(R.Listings(c.snap, it.key) or {}) do out[#out + 1] = { detail = "listing", item = it, l = l } end
      end
    end
  end
  return out, n
end

-------------------------------------------------------------------------------
-- The gear engine's auction source: the saved scan's weapons and armour with a buyout, once each, at their lowest price
-------------------------------------------------------------------------------
-- which saved scan the gear engine reads: this character's own realm and faction (or the neutral house that is open), else the
-- newest scan of this realm
function V.FeedKey()
  local own = P.Key()
  if R.Snap(own) then return own end
  return R.LatestKey()
end
function V.Feed()
  local snap = R.Snap(V.FeedKey())
  local f = V.feed
  if f and f.snap == snap and f.t == (snap and snap.t) and not V.feedDirty then return f.data end
  V.feedDirty = nil
  if not snap then V.feed = { snap = nil } return nil end
  local items, pending = {}, 0
  -- 0.9.6: the items whose kind the game has not said yet, by item id -> their scan keys. Only an answer for one of these makes the
  -- summary grow (V.FeedArrived); an item the game never names stays here and costs nothing.
  local waiting = {}
  local keys = {}
  for key in pairs(snap.rows or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    local it = R.Item(snap, key)
    if it and it.low then
      local cls = it.class
      if not cls then
        local id = P.KeyID(key)
        local ii = C.ItemInfo(id)
        cls = ii and ii.classID
        if not cls and id then
          pending = pending + 1
          waiting[id] = waiting[id] or {}
          waiting[id][#waiting[id] + 1] = key
        end
      end
      if cls and V.GEAR_CLASS[cls] then
        items[#items + 1] = { ref = V.LinkOf(key), price = it.low, market = it.market, key = key }
      end
    end
  end
  local data = { items = items, age = max(0, P.Now() - (tonumber(snap.t) or 0)), pending = pending, waiting = waiting }
  V.feed = { snap = snap, t = snap.t, data = data }
  return data
end
Panoply.GearSources.auctionData = function() return V.Feed() end

-- the gold of every character of this realm and faction (Hearth Hall's record; the money carried now for this one)
function V.AccountGold()
  local A = Panoply.Alts
  local mine = C.Money() or 0
  if not (A and A.List and A.Me) then return mine, 1 end
  local ok, list = pcall(A.List, A)
  if not ok or type(list) ~= "table" then return mine, 1 end
  local realm = A:Me()
  local faction = C.pc(_G.UnitFactionGroup, "player")
  local total, n = mine, 1
  for _, ch in ipairs(list) do
    if not ch.me and ch.realm == realm and (not faction or not ch.faction or ch.faction == faction) then
      total, n = total + (ch.money or 0), n + 1
    end
  end
  return total, n
end
function V:AffordOnly() return Panoply.db ~= nil and Panoply.db.auctionUpgradesAfford == true end

-- The Upgrades tab as data: { state = "noscan" | "noclass" | "working" | "ok", head, weighedFor, cells (the grid's), list (the chosen
-- slot's candidates), found (slots with an upgrade), progress, gold }
function V:UpgradeData()
  local d = { cells = {} }
  local snap = self:Snap()
  if not snap then d.state = "noscan" return d end
  -- the engine ranks the scan of this character's own auction house; another realm's or faction's scan has no upgrades for it
  if self:Key() ~= V.FeedKey() then d.state = "otherscan" return d end
  local G = Panoply.Gear
  local ctx = G and G.GetContext and G:GetContext()
  if not (ctx and ctx.stats) then d.state = "noclass" return d end
  local me = C.PlayerInfo and C.PlayerInfo() or {}
  local plan = (ctx.planName or ""):gsub("%s*%(default%)$", "")
  local cls = me.className or (ctx.class and ctx.class:sub(1, 1) .. ctx.class:sub(2):lower()) or "character"
  d.head = plan ~= "" and ("%s %s, level %d"):format(plan, cls, ctx.level or me.level or 1) or ("%s, level %d"):format(cls, ctx.level or 1)
  d.weighedFor = ctx.weighedFor
  local filter = { sources = { auction = true }, maxLevel = ctx.level }
  if self:AffordOnly() then
    d.gold = V.AccountGold()
    filter.maxPrice = d.gold
  end
  local best = G:BestPerSlot(ctx, filter)
  d.best = best
  if not best then d.state = "noclass" return d end
  d.working, d.progress = best.working and true or false, best.progress or 0
  local AL = Panoply.AtLevel
  local order = (AL and AL.PAPER) or { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "mainhand", "offhand", "ranged" }
  local seen, found = {}, 0
  for _, key in ipairs(order) do
    local b = best[key]
    local slot = G.SLOTS and G.SLOTS[key]
    local cell = { key = key, label = (b and b.label) or (slot and slot.label) or key, list = {} }
    if b then
      cell.worn, cell.empty = b.worn, b.empty or nil
      for _, c in ipairs(b.candidates or {}) do
        if c.upgrade and not c.locked and c.itemID and not seen[c.itemID] then
          seen[c.itemID] = true
          cell.list[#cell.list + 1] = c
        end
      end
    end
    cell.now = cell.list[1]
    cell.state = cell.now and "up" or "none"
    if cell.now then found = found + 1 end
    d.cells[#d.cells + 1] = cell
  end
  d.found = found
  d.state = "ok"
  return d
end

-- one cell of the grid as the slot grid draws it
local function itemIcon(c)
  if not c then return nil end
  local id = c.itemID or c.id
  return c.icon or (id and C.ItemIcon and C.ItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- the item a cell's picture belongs to (the slot grid paints it again when the game sends the item: UI/SlotGrid.lua)
local function itemRef(c) return c and (c.link or c.itemID or c.id) or nil end
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
function V.ItemName(it) return ("|cff%s%s|r"):format(QUALITY[it.quality or 1] or QUALITY[1], it.name or "?") end
function V.CellView(cell)
  local v = { key = cell.key, label = cell.label, state = cell.state }
  if cell.worn then v.icon, v.quality, v.item = itemIcon(cell.worn), cell.worn.quality, itemRef(cell.worn) end
  local up = cell.now
  if up then
    v.over = { icon = itemIcon(up), quality = up.quality, name = up.name, item = itemRef(up) }
    v.value = ("%s · %s"):format(Panoply.Gear.DeltaText(up.delta), money(up.price or 0))
  else v.value = "No upgrade" end
  local lines = {}
  if cell.worn then lines[#lines + 1] = ("Worn: %s"):format(V.ItemName(cell.worn)) else lines[#lines + 1] = "Worn: nothing" end
  if up then lines[#lines + 1] = ("Best on the auction house: %s %s, %s"):format(V.ItemName(up), Panoply.Gear.DeltaText(up.delta), money(up.price or 0))
  else lines[#lines + 1] = "Nothing on the auction house beats it." end
  lines[#lines + 1] = "Click for every candidate."
  v.tip, v.tipBody = cell.label, table.concat(lines, "\n")
  return v
end

-------------------------------------------------------------------------------
-- History data
-------------------------------------------------------------------------------
function V:RealmKey() return R.RealmOfSnapKey(self:Key()) end
local function sinceOf(period)
  if not period or period <= 0 then return nil end
  return P.Now() - period * 86400
end
V.HIST = {
  bought = { title = "Bought", amount = "YOU PAID", who = "SELLER" },
  sold = { title = "Sold", amount = "YOU GOT", who = "BUYER" },
  unsold = { title = "Didn't sell", amount = "LISTED AT", who = "OUTCOME" },
}
V.HIST_ORDER = { "bought", "sold", "unsold" }
function V:HistoryData()
  local realm = self:RealmKey()
  local st = self.state
  if st.char and not R.CharRec(realm, st.char, false) then st.char = nil end
  local since = sinceOf(st.period)
  local T = R.Totals(realm, st.char, since)
  local any = T.bought.n + T.sold.n + T.unsold.n + (T.listed or 0)
  local all = R.Totals(realm, nil, nil)
  local ever = all.bought.n + all.sold.n + all.unsold.n + (all.listed or 0)
  return { realm = realm, since = since, totals = T, any = any > 0, ever = ever > 0, rows = R.History(st.histKind, realm, st.char, since) }
end

-------------------------------------------------------------------------------
-- A list that draws only the rows you can see, with a bar on its right
-------------------------------------------------------------------------------
function V.NewList(parent, rowH, makeRow)
  local L = { rows = {}, rowH = rowH, offset = 0, total = 0, visible = 0, makeRow = makeRow }
  local box = CreateFrame("Frame", nil, parent)
  box.panoplyGapOK = true
  L.box = box
  local bar = Skin.ScrollBar(box, {
    get = function() return L.offset end,
    max = function() return L:MaxOffset() end,
    set = function(v) L.offset = clamp(floor(v + 0.5), 0, L:MaxOffset()) L:Update() end,
    ratio = function() return L.total > 0 and L.visible / L.total or 1 end,
    step = 1,
    page = function() return max(1, L.visible - 1) end,
    length = function() return L.h or 0 end,
  })
  bar:Hide()
  L.bar = bar
  function L:MaxOffset() return max(0, self.total - self.visible) end
  function L:Update()
    self.offset = clamp(self.offset, 0, self:MaxOffset())
    for i = 1, self.visible do
      local r = self.rows[i]
      local item = self.data and self.data[self.offset + i]
      if item then self.fill(r, item, self.offset + i) r:Show() else r:Hide() end
    end
    for i = self.visible + 1, #self.rows do self.rows[i]:Hide() end
    if self.total > self.visible and self.visible > 0 then bar:Update() else bar:Hide() end
  end
  function L:Scroll(rows) self.offset = clamp(self.offset + rows, 0, self:MaxOffset()) self:Update() end
  function L:ScrollTo(offset) self.offset = offset self:Update() end
  function L:Size(w, h)
    self.w, self.h = w, h
    box:SetSize(w, h)
    bar:ClearAllPoints(); bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0); bar:SetHeight(h)
    self.visible = max(0, floor(h / self.rowH))
    for i = 1, self.visible do
      local r = self.rows[i]
      if not r then r = makeRow(box) self.rows[i] = r end
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(i - 1) * self.rowH)
      r:SetSize(w - 14, self.rowH)
    end
  end
  function L:Set(data, fill)
    self.data, self.fill, self.total = data, fill, #data
    self:Update()
  end
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(_, delta) L:Scroll(-(delta or 0) * V.WHEEL) end)
  return L
end

-------------------------------------------------------------------------------
-- A view: what one host (the page's body, the pop-out window) shows. New(host, { kind = "page" | "popout" })
-------------------------------------------------------------------------------
local View = {}
View.__index = View

function V.New(host, opts)
  opts = opts or {}
  local v = setmetatable({ host = host, kind = opts.kind or "page" }, View)
  v:Build()
  V.views[#V.views + 1] = v
  return v
end

-- a word at (x, y) of parent, one line, cut to w: returns its width and height and the font string
local function word(parent, fs, x, y, size, token, words, w, name)
  fs = fs or (name and Skin.Name(parent, size, Kit.Color(token)) or Skin.Ink(parent, size, Kit.Color(token)))
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  setColor(fs, Kit.Color(token))
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(max(10, w))
  fs:SetText(words or "")
  if TW(fs) > w then Skin.Ellipsize(fs, words or "", max(10, w)) end
  local tw = min(w, ceil(TW(fs)) + 2)
  fs:SetWidth(max(10, tw))
  local th = ceil(TH(fs, max(10, tw)))
  fs:SetHeight(th)
  fs:Show()
  return tw, th, fs
end
local function para(parent, fs, x, y, size, token, words, w)
  fs = fs or Skin.Ink(parent, size, Kit.Color(token))
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  setColor(fs, Kit.Color(token))
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(max(10, w))
  fs:SetText(words or "")
  local h = ceil(TH(fs, max(10, w)))
  fs:SetHeight(h)
  fs:Show()
  return h, fs
end
local function menuButton(parent, w, tip, body, onClick)
  local b = Skin.Button(parent, tip, w, 26, onClick, tip, body)
  b:SetIcon("Sort", 12)
  b.panoplyFixedH = 26
  return b
end

function View:Build()
  local host = self.host
  local st = V.state
  -- 1. the strip
  local strip = Kit.Surface(host, 1)
  self.strip = strip
  strip.chip = Kit.StatusChip(strip, "state.idle", "No scan yet")
  strip.chip:EnableMouse(true)
  Skin.Tooltip(strip.chip, V.WORDS.freshTip, nil)
  strip.chip:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
  strip.chip:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  strip.count = Skin.Ink(strip, 12, Kit.Color("text.primary"))
  strip.meter = Kit.ProgressBar(strip, { h = 6, accent = "auctions" })
  strip.meter:EnableMouse(true)
  Skin.Tooltip(strip.meter, "Saved on this computer", "")
  strip.meter:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
  strip.meter:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  strip.open = Skin.Button(strip, "Open Auction window", 170, 26, function() V.OpenAuctionWindow() end, "Open Auction window", V.WORDS.openTip)
  if strip.open.SetIcon then strip.open:SetIcon("Auctions", 14) end
  strip.note = Skin.Ink(strip, 11, Kit.Color("text.muted"))
  -- 2. the tabs
  local items = {
    { key = "prices", label = "Prices", tip = "Prices", tipBody = V.HELP.prices },
    { key = "upgrades", label = "Upgrades", tip = "Upgrades", tipBody = V.HELP.upgrades },
    { key = "history", label = "History", tip = "History", tipBody = V.HELP.history },
  }
  self.tabs = Kit.Tabs(host, { page = self.kind == "page" and "auctions" or nil, items = items, default = "prices", style = "underline",
    get = function() return V.state.tab end,
    onSelect = function(k) V:SetTab(k) end, redraw = function() end })
  if self.kind == "page" then
    local pb = CreateFrame("Button", nil, host)
    pb:SetSize(22, 22)
    pb.panoplyKit = "IconButton"
    local t = pb:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(pb)
    pb.icon = t
    pb.panoplyIconHow = Kit.Icon(t, "icon.ui.popout", { size = 22 })
    Skin.Tooltip(pb, "Pop out", V.WORDS.popTip)
    pb:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
    pb:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    pb:SetScript("OnClick", function() if Auc.Browser then Auc.Browser:Open() end end)
    self.popBtn = pb
  end
  -- 3. the tabs' bodies
  self:BuildPrices()
  self:BuildUpgrades()
  self:BuildHistory()
  self.msg = Skin.Ink(host, 13, Kit.Color("text.muted"))
  self.msg:Hide()
end

-- Prices ---------------------------------------------------------------------------------
V.COLS = {
  { key = "name", title = "ITEM", align = "LEFT" },
  { key = "listings", title = "LISTINGS", w = 64, align = "RIGHT" },
  { key = "qty", title = "QUANTITY", w = 72, align = "RIGHT" },
  { key = "low", title = "LOWEST EACH", short = "LOWEST", w = 104, align = "RIGHT" },
  { key = "market", title = "MARKET EACH", short = "MARKET", w = 104, align = "RIGHT" },
  { key = "trend", title = "TREND", w = 64, align = "RIGHT" },
}
function View:BuildPrices()
  local g = CreateFrame("Frame", nil, self.host)
  g.panoplyGapOK = true
  self.prices = g
  g.box = Panel.Box(g, 220, 26, "Search item names", function(box)
    V.state.query = box:GetText() or ""
    V.stamp = (V.stamp or 0) + 1
    local stamp = V.stamp
    C.After(0.2, function() if V.stamp == stamp then V:Top() V:RefreshAll() end end)
  end)
  g.cat = menuButton(g, 170, "All categories", "Narrow the list to one kind of item. It works together with the search.", function(b) self:CategoryMenu(b) end)
  g.help = Kit.HelpIcon(g, "Prices", V.HELP.prices)
  g.hdr = {}
  for i, col in ipairs(V.COLS) do
    local h = CreateFrame("Button", nil, g)
    h.label = Skin.Label(h, 10, Kit.Color("text.muted"))
    if h.label.SetWordWrap then h.label:SetWordWrap(false) end
    h.label:SetText(col.title)
    if h.label.SetJustifyH then h.label:SetJustifyH(col.align) end
    h.label:SetPoint("LEFT", h, "LEFT", 0, 0); h.label:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.bar = h:CreateTexture(nil, "ARTWORK")
    h.bar:SetHeight(2)
    Skin.Solid(h.bar, Kit.Color("gold.title"), 1)
    h.bar:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0); h.bar:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.col = col
    h:SetScript("OnClick", function() V:SetSort(col.key) end)
    Skin.Tooltip(h, "Sort by " .. V.SORTS[col.key][1]:lower(), "Click again to turn the order round.")
    h:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
    h:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    g.hdr[i] = h
  end
  g.list = V.NewList(g, V.ROW_H, function(parent)
    local r = Panel.Row(parent)
    r.slot = Host.ItemSlot(r, 22)
    r.name = Panel.Cell(r, 0, 100, "LEFT", 12)
    r.cells = {}
    for i = 2, #V.COLS do r.cells[i] = Panel.Cell(r, 0, 50, V.COLS[i].align, 12) end
    r.arrow = r:CreateTexture(nil, "ARTWORK")
    r.arrow:SetSize(10, 10)
    r.arrow:Hide()
    -- the open item's sparkline: dots joined by lines (where the client draws lines)
    r.spark = CreateFrame("Frame", nil, r)
    r.spark.panoplyGapOK = true
    r.spark.dots, r.spark.lines = {}, {}
    r.spark:Hide()
    r.sparkText = Panel.Cell(r, 0, 100, "LEFT", 11)
    r:HookScript("OnEnter", function(row) V.Tip(row) end)
    r:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(row) if row.itemKey and not row.detail then V:ToggleOpen(row.itemKey) end end)
    return r
  end)
  g.empty = Skin.Ink(g, 13, Kit.Color("text.muted"))
  g:Hide()
end

function View:CategoryMenu(owner)
  local c = V:Load()
  local items = { { text = "All categories", checked = function() return V.state.cat == nil end, func = function() V.state.cat = nil V:Top() V:RefreshAll() end } }
  for _, e in ipairs(c.cats or {}) do
    items[#items + 1] = { text = e.name, checked = function() return V.state.cat == e.id end, func = function() V.state.cat = e.id V:Top() V:RefreshAll() end }
  end
  Skin.Menu(owner, items, { width = 220 })
end

-- Upgrades -------------------------------------------------------------------------------
function View:BuildUpgrades()
  local g = CreateFrame("Frame", nil, self.host)
  g.panoplyGapOK = true
  self.upgrades = g
  g.area = Skin.ScrollArea(g)
  g.content = CreateFrame("Frame", nil, g.area.content)
  g.content.panoplyGapOK = true
  g.content:SetPoint("TOPLEFT", g.area.content, "TOPLEFT", 0, 0)
  local h = g.content
  g.head = Skin.Name(h, 15, Kit.Color("text.primary"))
  g.weighed = CreateFrame("Button", nil, h)
  g.weighed.panoplyGapOK = true
  g.weighed.fs = Skin.Ink(g.weighed, 11, Kit.Color("text.muted"))
  g.weighed.fs:SetPoint("TOPLEFT", g.weighed, "TOPLEFT", 0, 0)
  Skin.Tooltip(g.weighed, "Weights", "Opens the plan these weights come from.")
  g.weighed:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
  g.weighed:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  g.weighed:SetScript("OnClick", function() if Panoply.Gear and Panoply.Gear.OpenPlan then Panoply.Gear:OpenPlan() end end)
  g.help = Kit.HelpIcon(h, "Upgrades", V.HELP.upgrades)
  g.afford = Skin.Check(h, "Only what I can afford", {
    get = function() return V:AffordOnly() end,
    set = function(v) Panoply:SetOption("auctionUpgradesAfford", v and true or false) end,
  }, function() V:RefreshAll() end, "Leaves out the upgrades that cost more than the gold of your characters on this realm and faction (Muster's count).")
  g.gold = Skin.Ink(h, 11, Kit.Color("text.muted"))
  g.bar = Kit.ProgressBar(h, { h = 7, accent = "auctions" })
  g.barText = Skin.Ink(h, 11, Kit.Color("text.muted"))
  g.grid = Kit.SlotGrid(h, { onSelect = function(key) V:SelectSlot(key) end, accent = "auctions" })
  g.listTitle = Skin.Name(h, 13, Kit.Color("gold.title"))
  g.rows = {}
  g.none = Skin.Ink(h, 12, Kit.Color("text.muted"))
  g:Hide()
end

-- History --------------------------------------------------------------------------------
function View:BuildHistory()
  local g = CreateFrame("Frame", nil, self.host)
  g.panoplyGapOK = true
  self.history = g
  g.charBtn = menuButton(g, 220, "All characters on this realm", "Whose auctions to show: every character of this realm, or one.", function(b) self:CharacterMenu(b) end)
  g.periodBtn = menuButton(g, 150, "Last 30 days", "How far back to look. Panoply keeps the newest rows of each kind for each character.", function(b) self:PeriodMenu(b) end)
  g.help = Kit.HelpIcon(g, "History", V.HELP.history)
  g.cells = {}
  for _, kind in ipairs(V.HIST_ORDER) do
    local t = CreateFrame("Button", nil, g)
    t.panoplyGapOK, t.panoplyBox = true, true
    -- the cell's card is a texture of the cell itself (surface.1, no border), so its words sit on it
    local fill = t:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(t)
    Skin.Round(fill, Skin.RADIUS.card, Skin.TEX.RFill)
    t.fill = fill
    function t:SetLevel(l) local c = Kit.Color("surface." .. l) self.fill:SetVertexColor(c[1], c[2], c[3], 1) end
    t.bg = t
    t.lab = Skin.Ink(t, 11, Kit.Color("text.muted"))
    t.big = Skin.Name(t, 15, Kit.Color("text.primary"))
    t.sub = Skin.Ink(t, 12, Kit.Color("text.primary"))
    t.coin = t:CreateTexture(nil, "ARTWORK")
    t.coin:SetSize(14, 14)
    Kit.Icon(t.coin, "icon.coin.gold", { size = 14 })
    t.line = t:CreateTexture(nil, "ARTWORK")
    t.line:SetHeight(2)
    Skin.Solid(t.line, Kit.Color("gold.title"), 1)
    for _, fs in ipairs({ t.lab, t.big, t.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
    t.kind = kind
    Skin.Tooltip(t, V.HIST[kind].title, "")
    t:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
    t:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    t:SetScript("OnClick", function() V.state.histKind = kind V:Top() V:RefreshAll() end)
    g.cells[kind] = t
  end
  g.hdr = {}
  for i = 1, 6 do
    local fs = Skin.Label(g, 10, Kit.Color("text.muted"))
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    g.hdr[i] = fs
  end
  g.list = V.NewList(g, V.ROW_H, function(parent)
    local r = Panel.Row(parent)
    r.slot = Host.ItemSlot(r, 22)
    r.name = Panel.Cell(r, 0, 100, "LEFT", 12)
    r.cells = {}
    for i = 1, 6 do r.cells[i] = Panel.Cell(r, 0, 50, "LEFT", 12) end
    r:HookScript("OnEnter", function(row) V.Tip(row) end)
    r:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    return r
  end)
  g.empty = Skin.Ink(g, 13, Kit.Color("text.muted"))
  g:Hide()
end

function View:CharacterMenu(owner)
  local items = { { text = "All characters on this realm", checked = function() return V.state.char == nil end, func = function() V.state.char = nil V:Top() V:RefreshAll() end } }
  for _, name in ipairs(R.CharNames(V:RealmKey())) do
    items[#items + 1] = { text = name, checked = function() return V.state.char == name end, func = function() V.state.char = name V:Top() V:RefreshAll() end }
  end
  Skin.Menu(owner, items, { width = 250 })
end
function View:PeriodMenu(owner)
  local items = {}
  for _, p in ipairs(V.PERIODS) do
    items[#items + 1] = { text = p[2], checked = function() return V.state.period == p[1] end, func = function() V.state.period = p[1] V:Top() V:RefreshAll() end }
  end
  Skin.Menu(owner, items, { width = 190 })
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
-- Draw the view in W x H of its host. band: "wide" | "medium" | "narrow" (the host works it out from its width and the Size setting)
function View:Render(W, H, band)
  self.W, self.H, self.band = W, H, band or Kit.Band(W)
  band = self.band
  local y = -self:DrawStrip(W, band)
  y = y - SP.m
  -- the tabs, and the pop-out button at the right end of their bar (Narrow: a dropdown)
  local tab = self.tabs:Current()
  V.state.tab = tab
  local tabsW = self.popBtn and (W - 22 - SP.s) or W
  local th = self.tabs:Layout(0, y, tabsW, band == "narrow" and "dropdown" or nil)
  if self.popBtn then
    self.popBtn:ClearAllPoints(); self.popBtn:SetPoint("TOPLEFT", self.host, "TOPLEFT", W - 22, y - max(0, floor((th - 22) / 2)))
    self.popBtn:Show()
  end
  y = y - th - SP.s
  local bodyH = max(40, H + y - V.GRIP)
  self.prices:Hide(); self.upgrades:Hide(); self.history:Hide()
  if tab == "upgrades" then self:DrawUpgrades(0, y, W, bodyH, band)
  elseif tab == "history" then self:DrawHistory(0, y, W, bodyH, band)
  else self:DrawPrices(0, y, W, bodyH, band) end
end

-- "Nov 15, 14:05"
local function dateText(t)
  if not (_G.date and t and t > 0) then return "?" end
  return date("%b ", t) .. tostring(tonumber(date("%d", t))) .. date(", %H:%M", t)
end
V.DateText = dateText

-- The strip. Returns its height.
function View:DrawStrip(W, band)
  local s = self.strip
  local pad = SP.m
  local inner = W - 2 * pad
  local snap = V:Snap()
  local now = P.Now()
  local t = (snap and tonumber(snap.t)) or R.ScanTime(V:Key()) or 0
  local tok, words = V.Freshness(t, now)
  s.chip:Set(tok, words)
  s.chip.tip, s.chip.tipBody = V.WORDS.freshTip, t > 0 and (dateText(t) .. ", " .. R.Ago(now - t) .. ".") or nil
  -- Open Auction window at the right of line 1
  local at = V.AtAuctionHouse()
  s.open:SetEnabledLook(at)
  s.open.tipBody = at and V.WORDS.openTip or V.WORDS.openAway
  -- beside the chip when it fits on one line there, else on a line of its own under the chip (a narrow pop-out)
  local bw = Skin.FitButton(s.open, 150, inner)
  local below = s.chip:GetWidth() + SP.m + bw > inner
  local ch = s.chip:GetHeight()
  local x = pad
  local lineH = max(26, ceil(ch), below and 0 or ceil(s.open:GetHeight() or 26))
  s.chip:ClearAllPoints(); s.chip:SetPoint("TOPLEFT", s, "TOPLEFT", x, -pad - max(0, floor((lineH - ch) / 2)))
  s.open:ClearAllPoints()
  if below then
    s.open:SetPoint("TOPLEFT", s, "TOPLEFT", pad, -pad - lineH - SP.xs)
    lineH = lineH + SP.xs + ceil(s.open:GetHeight() or 26)
    bw = -SP.m                      -- nothing at the right of line 1
  else
    s.open:SetPoint("TOPRIGHT", s, "TOPRIGHT", -pad, -pad)
  end
  x = x + s.chip:GetWidth() + SP.m
  local count = snap and ("%s auctions · %s items"):format(R.Commas(snap.n or 0), R.Commas(snap.items or 0)) or nil
  local meterW = 60
  if not V.bytes then V.bytes = R.Bytes() end         -- measured again when the saved data changes
  local bytes = V.bytes
  local room = W - pad - bw - SP.m - x
  local need = 0
  if count then s.count:SetText(count) need = ceil(TW(s.count)) + 2 + SP.m + meterW end
  local y2 = -pad - lineH - SP.xs
  local cx, cy, cw, second
  if need <= room and not below then cx, cy, cw = x, -pad - max(0, floor((lineH - 16) / 2)), room - meterW - SP.m
  else cx, cy, cw, second = pad, y2, inner - meterW - SP.m, true end
  local tw, th = 0, 16
  if count then tw, th = word(s, s.count, cx, cy, 12, "text.primary", count, cw) else s.count:Hide() end
  s.meter:ClearAllPoints(); s.meter:SetPoint("TOPLEFT", s, "TOPLEFT", cx + tw + (count and SP.m or 0), cy - max(0, floor((th - 6) / 2)))
  if second then y2 = y2 - max(th, 8) - SP.xs end
  s.meter:SetBarWidth(meterW)
  s.meter:SetProgress(min(1, bytes / R.BUDGET))
  s.meter.tip, s.meter.tipBody = "Saved on this computer", R.MeterText(bytes)
  s.meter:Show()
  -- the one View only line
  local nh = para(s, s.note, pad, y2, 11, "text.muted", V.WORDS.viewOnly, inner)
  local h = -y2 + nh + pad
  s:ClearAllPoints(); s:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, 0)
  s:SetSize(W, h)
  s:Show()
  return h
end

-- which columns show in this band (and have something in them in this scan)
function View:Columns(band, c)
  local show = { name = true, listings = band ~= "narrow", qty = band ~= "narrow", low = c.anyLow, market = c.anyMarket,
    trend = band == "wide" and c.trend }
  -- Narrow: name, lowest and market only; a scan without buyouts still shows the listings and quantity
  if band == "narrow" and not c.anyLow and not c.anyMarket then show.listings, show.qty = true, true end
  return show
end

function View:DrawPrices(x0, y0, W, H, band)
  local g = self.prices
  g:ClearAllPoints(); g:SetPoint("TOPLEFT", self.host, "TOPLEFT", x0, y0)
  g:SetSize(W, H)
  g:Show()
  local c = V:Load()
  if not c.snap then
    g.box:Hide(); g.cat:Hide(); g.help:Hide()
    for _, h in ipairs(g.hdr) do h:Hide() end
    g.list.box:Hide()
    para(g, g.empty, 0, 0, 13, "text.muted", V.WORDS.noScan, W)
    return
  end
  -- the search and the category
  local cname = "All categories"
  for _, e in ipairs(c.cats or {}) do if e.id == V.state.cat then cname = e.name end end
  g.cat.label:SetText(cname)
  local helpW = 16 + SP.s
  local boxW = band == "narrow" and max(140, W - 150 - SP.m - helpW) or 220
  g.box:SetWidth(boxW)
  g.box:ClearAllPoints(); g.box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
  if (g.box:GetText() or "") ~= (V.state.query or "") then Panel.SetBox(g.box, V.state.query) end
  g.box:Show()
  local catW = Skin.FitButton(g.cat, 130, max(130, min(220, W - boxW - SP.m - helpW)))
  g.cat:ClearAllPoints(); g.cat:SetPoint("TOPLEFT", g, "TOPLEFT", boxW + SP.m, 0)
  g.cat:Show()
  g.help:ClearAllPoints(); g.help:SetPoint("TOPRIGHT", g, "TOPRIGHT", -2, -5)
  g.help:Show()
  local y = 26 + SP.m
  -- the columns
  local show = self:Columns(band, c)
  local cols = {}
  for i, col in ipairs(V.COLS) do if show[col.key] then cols[#cols + 1] = { i = i, col = col } end end
  local gap = SP.m
  local fixed = 0
  for _, e in ipairs(cols) do fixed = fixed + (e.col.w or 0) end
  local nameW = W - 14 - fixed - (#cols - 1) * gap - 4
  if band == "narrow" then
    -- narrow money columns
    for _, e in ipairs(cols) do if e.col.w then e.w = 88 end end
    fixed = 0
    for _, e in ipairs(cols) do fixed = fixed + (e.w or e.col.w or 0) end
    nameW = W - 14 - fixed - (#cols - 1) * gap - 4
  end
  local colX, colW, x = {}, {}, 4
  for _, e in ipairs(cols) do
    local w = e.col.w and (e.w or e.col.w) or nameW
    colX[e.col.key], colW[e.col.key] = x, w
    x = x + w + gap
  end
  self.colX, self.colW = colX, colW
  local hh = 0
  for i, h in ipairs(g.hdr) do
    local key = V.COLS[i].key
    if colX[key] then
      local hx = colX[key] + (key == "name" and 22 + SP.s or 0)
      local hw = colW[key] - (key == "name" and 22 + SP.s or 0)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", g, "TOPLEFT", hx, -y)
      h:SetSize(hw, 16)
      local title = (band == "narrow" and V.COLS[i].short) or V.COLS[i].title
      h.label:SetText(title)
      if TW(h.label) > hw then Skin.Ellipsize(h.label, title, hw) end
      local on = V.state.sort.key == key
      if on then h.bar:Show() else h.bar:Hide() end
      setColor(h.label, Kit.Color(on and "text.primary" or "text.muted"))
      h:Show()
      hh = max(hh, 16)
    else h:Hide() end
  end
  y = y + hh + SP.xs
  local rows, n = V:PriceRows()
  g.list.box:ClearAllPoints(); g.list.box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y)
  g.list:Size(W, max(0, H - y))
  g.list.box:Show()
  -- an item just opened: the list moves so that it and its own rows are in view
  if V.reveal and V.reveal == V.state.open then
    local at, last
    for i, d in ipairs(rows) do
      if d.key == V.reveal and not d.detail then at = i end
      if d.detail and d.item.key == V.reveal then last = i end
    end
    if at then
      local vis = g.list.visible
      local off = g.list.offset
      if at <= off then off = at - 1
      elseif (last or at) > off + vis then off = min(at - 1, (last or at) - vis) end
      g.list.offset = max(0, off)
    end
  end
  for _, r in ipairs(g.list.rows) do self:PlaceRow(r) end
  local view = self
  g.list:Set(rows, function(r, d) view:FillPriceRow(r, d) end)
  if n == 0 then
    para(g, g.empty, 0, -(y + SP.m), 13, "text.muted", V.WORDS.noMatch, W)
  else g.empty:Hide() end
end

function View:PlaceRow(r)
  local colX, colW = self.colX, self.colW
  r.slot:ClearAllPoints(); r.slot:SetPoint("LEFT", r, "LEFT", colX.name, 0)
  local nx = colX.name + 22 + SP.s
  r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r, "LEFT", nx, 0)
  r.name:SetWidth(colW.name - 22 - SP.s); r.name.cellW = colW.name - 22 - SP.s
  r.nameW = colW.name - 22 - SP.s
  r.fullW = max(r.nameW, floor((self.prices.list.w or 400) - 14 - nx - 4))     -- a kept auction's line takes the whole row
  for i = 2, #V.COLS do
    local key = V.COLS[i].key
    local fs = r.cells[i]
    if colX[key] then
      local w = colW[key] - (key == "trend" and 12 or 0)
      fs:ClearAllPoints(); fs:SetPoint("LEFT", r, "LEFT", colX[key] + (key == "trend" and 12 or 0), 0)
      fs:SetWidth(w); fs.cellW = w
      fs.panoplyCol = true
    else fs.panoplyCol = false fs:Hide() end
  end
  if colX.trend then
    r.arrow:ClearAllPoints(); r.arrow:SetPoint("LEFT", r, "LEFT", colX.trend, 0)
  end
  r.spark:ClearAllPoints(); r.spark:SetPoint("LEFT", r, "LEFT", nx, 0)
  r.spark:SetSize(140, V.ROW_H - 8)
  r.sparkText:ClearAllPoints(); r.sparkText:SetPoint("LEFT", r, "LEFT", nx + 140 + SP.m, 0)
  local sw = max(20, (r:GetWidth() or 400) - (nx + 140 + SP.m) - 4)
  r.sparkText:SetWidth(sw); r.sparkText.cellW = sw
end

local function changeText(ch)
  if not ch then return "" end
  local pct = floor(math.abs(ch) * 100 + 0.5)
  if pct == 0 then return "same" end
  return (ch > 0 and "+" or "-") .. pct .. "%"
end
V.ChangeText = changeText

function View:FillPriceRow(r, d)
  r.detail = d.detail
  r.itemKey = d.detail and d.item.key or d.key
  local it = d.detail and d.item or d
  r.link, r.nameText, r.tipText = V.LinkOf(it.key), it.info.name, nil
  r:SetSelected(not d.detail and V.state.open == it.key)
  if d.detail then
    r.slot:Hide()
    r.arrow:Hide()
    for i = 2, #V.COLS do r.cells[i]:Hide() end
    if d.detail == "spark" then
      r.name:Hide()
      self:DrawSpark(r, it)
      r.spark:Show()
      local pts = #it.trend + 1
      local words = ("Lowest over the last %d %s"):format(pts, plural(pts, "scan"))
      if self.band == "narrow" then words = ("%s · %d listings, %s items"):format(words, it.listings, R.Commas(it.qty)) end
      -- the explanation is the row's tooltip, not more words on the row
      r.link = nil
      r.tipText = R.Listings(V:Load().snap, it.key) and (words .. ". Its single auctions are listed below.")
        or (words .. ". Single auctions are kept only for items on a shopping list.")
      Host.Fit(r.sparkText, "", r.sparkText.cellW, 11, "inkSoft")
      Panel.Put(r.sparkText, words)
      setColor(r.sparkText, Kit.Color("text.muted"))
      r.sparkText:Show()
    else
      r.spark:Hide()
      r.sparkText:Hide()
      local l = d.l
      local parts = { ("%d × %s each"):format(l.stack, l.each and money(l.each) or "bid only") }
      if l.buyout > 0 then parts[#parts + 1] = "buyout " .. money(l.buyout) end
      if l.seller then parts[#parts + 1] = l.seller end
      if l.left and l.left > 0 then parts[#parts + 1] = R.BandText(l.left) end
      r.name:Show()
      r.name:SetWidth(r.fullW); r.name.cellW = r.fullW
      Panel.Put(r.name, "    " .. table.concat(parts, " · "))
      setColor(r.name, Kit.Color("text.muted"))
    end
    return
  end
  r.spark:Hide()
  r.sparkText:Hide()
  r.slot:Show()
  r.slot:Set(it.info.icon, it.info.quality, it.info.id and (V.LinkOf(it.key) or it.info.id))
  r.name:Show()
  r.name:SetWidth(r.nameW); r.name.cellW = r.nameW
  Panel.Put(r.name, it.info.name)
  setColor(r.name, (it.info.quality and it.info.quality >= 1) and C.QualityColor(it.info.quality) or Skin.colors.text)
  local vals = {
    listings = R.Commas(it.listings), qty = R.Commas(it.qty),
    low = it.low and money(it.low) or "bid only", market = it.market and money(it.market) or "",
  }
  for i = 2, #V.COLS do
    local key = V.COLS[i].key
    local fs = r.cells[i]
    if fs.panoplyCol then
      if key == "trend" then
        Panel.Put(fs, changeText(it.change))
        local tok = not it.change and "text.muted" or (it.change > 0.005 and "state.bad" or (it.change < -0.005 and "state.good" or "text.muted"))
        setColor(fs, Kit.Color(tok))
      else
        Host.Fit(fs, vals[key], fs.cellW, 12, key == "low" and "done" or "text")
      end
      fs:Show()
    end
  end
  if self.colX.trend and it.change and math.abs(it.change) > 0.005 then
    Kit.Icon(r.arrow, it.change > 0 and "icon.trend.up" or "icon.trend.down", { size = 10 })
    r.arrow:Show()
  else r.arrow:Hide() end
end

-- the sparkline of an item: its lowest price at each point, oldest at the left (the market price where there is no lowest)
function View:DrawSpark(r, it)
  local sp = r.spark
  local pts = {}
  for i = #it.trend, 1, -1 do
    local e = it.trend[i]
    pts[#pts + 1] = { ago = e[1], v = (e[2] > 0 and e[2]) or (e[3] > 0 and e[3]) or nil }
  end
  pts[#pts + 1] = { ago = 0, v = it.low or it.market }
  local lo, hi = math.huge, 0
  for _, p in ipairs(pts) do if p.v then lo, hi = min(lo, p.v), max(hi, p.v) end end
  local w, h = 140, V.ROW_H - 8
  local span = R.TREND - 1
  local accent = Kit.Accent("auctions")
  local coords = {}
  for i, p in ipairs(pts) do
    local dot = sp.dots[i]
    if not dot then dot = sp:CreateTexture(nil, "ARTWORK") dot:SetSize(3, 3) sp.dots[i] = dot end
    if p.v then
      local x = floor((span - min(span, p.ago)) / span * (w - 3))
      local yv = hi > lo and floor((p.v - lo) / (hi - lo) * (h - 3)) or floor((h - 3) / 2)
      dot:ClearAllPoints(); dot:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", x, yv)
      Skin.Solid(dot, accent, 1)
      dot:Show()
      coords[#coords + 1] = { x + 1, yv + 1 }
    else dot:Hide() end
  end
  for i = #pts + 1, #sp.dots do sp.dots[i]:Hide() end
  for i = 1, #sp.lines do sp.lines[i]:Hide() end
  if sp.CreateLine then
    for i = 2, #coords do
      local ln = sp.lines[i - 1]
      if not ln then ln = sp:CreateLine(nil, "ARTWORK") sp.lines[i - 1] = ln end
      if ln.SetThickness then ln:SetThickness(1) end
      if ln.SetColorTexture then ln:SetColorTexture(accent[1], accent[2], accent[3], 0.8) end
      ln:SetStartPoint("BOTTOMLEFT", sp, coords[i - 1][1], coords[i - 1][2])
      ln:SetEndPoint("BOTTOMLEFT", sp, coords[i][1], coords[i][2])
      ln:Show()
    end
  end
  sp.panoplyPoints = #coords
end

function View:DrawUpgrades(x0, y0, W, H, band)
  local g = self.upgrades
  g:ClearAllPoints(); g:SetPoint("TOPLEFT", self.host, "TOPLEFT", x0, y0)
  g:SetSize(W, H)
  g:Show()
  g.area:ClearAllPoints(); g.area:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
  g.area:SetSize(W, H)
  g.area:Show()
  local h = g.content
  local cw = W - 14
  local d = V:UpgradeData()
  self.upData = d
  for _, r in ipairs(g.rows) do for _, part in pairs(r) do if type(part) == "table" and part.Hide then part:Hide() end end end
  g.listTitle:Hide(); g.none:Hide(); g.bar:Hide(); g.barText:Hide(); g.grid:Hide(); g.afford:Hide(); g.gold:Hide()
  g.head:Hide(); g.weighed:Hide(); g.help:Hide()
  if d.state ~= "ok" then
    local words = d.state == "noscan" and V.WORDS.noScan
      or (d.state == "otherscan" and "Upgrades come from the scan of your own realm and faction. This window shows another one; close it and open Auctions again for yours.")
      or "Panoply cannot read your class's stat weights yet. Open this tab again in a moment."
    local nh = para(h, g.none, 0, 0, 13, "text.muted", words, cw)
    h:SetSize(cw, nh)
    g.area:SetContentHeight(nh + SP.s)
    return
  end
  local y = 0
  local hw = 16 + SP.s
  local _, th = word(h, g.head, 0, y, 15, "text.primary", d.head, cw - hw, true)
  g.help:ClearAllPoints(); g.help:SetPoint("TOPLEFT", h, "TOPLEFT", cw - 16, y - 1)
  g.help:Show()
  y = y - th - SP.xs
  if d.weighedFor then
    local ww, wh = word(g.weighed, g.weighed.fs, 0, 0, 11, "text.muted", d.weighedFor, cw)
    g.weighed:SetSize(ww, wh)
    g.weighed:ClearAllPoints(); g.weighed:SetPoint("TOPLEFT", h, "TOPLEFT", 0, y)
    g.weighed:Show()
    y = y - wh - SP.xs
  end
  -- Only what I can afford, and the gold it counts
  g.afford:ClearAllPoints(); g.afford:SetPoint("TOPLEFT", h, "TOPLEFT", 0, y - 2)
  g.afford:Show()
  if g.afford.Refresh then g.afford:Refresh() end
  local aw = 18 + 9 + ceil(TW(g.afford.label)) + 2          -- the box and its label
  if d.gold then
    local gw = cw - aw - SP.m
    if gw >= 80 then word(h, g.gold, aw + SP.m, y - 4, 11, "text.muted", ("Your characters here have %s"):format(money(d.gold)), gw) end
  end
  y = y - 22 - SP.s
  -- working: a progress bar (never "Looking through the scan...")
  if d.working then
    local bw = min(240, cw)
    g.bar:ClearAllPoints(); g.bar:SetPoint("TOPLEFT", h, "TOPLEFT", 0, y - 4)
    g.bar:SetBarWidth(bw)
    g.bar:SetProgress(d.progress or 0)
    g.bar:Show()
    word(h, g.barText, bw + SP.m, y, 11, "text.muted", ("%d%%"):format(floor((d.progress or 0) * 100)), 60)
    y = y - 16 - SP.s
  end
  -- the grid, and the chosen slot's candidates beside it (Wide) or under it
  local cells = {}
  for _, cell in ipairs(d.cells) do cells[#cells + 1] = V.CellView(cell) end
  g.grid:Set(cells)
  if V.state.slot then
    local ok = false
    for _, cell in ipairs(d.cells) do if cell.key == V.state.slot then ok = true end end
    if not ok then V.state.slot = nil end
  end
  g.grid:Select(V.state.slot)
  local gridW, listX, listY, listW = cw, 0, nil, cw
  if band == "wide" then
    gridW = floor((cw - SP.l) * 0.6)
    listX, listW = gridW + SP.l, cw - gridW - SP.l
  end
  local cols = band == "narrow" and 2 or (band == "medium" and 4 or Kit.SlotGridColumns(gridW, 4))
  local gh = g.grid:Layout(0, y, gridW, cols)
  local bottom
  if band == "wide" then
    listY = y
    local lh = self:DrawCandidates(h, listX, listY, listW, d)
    bottom = y - max(gh, lh)
  else
    listY = y - gh - SP.l
    local lh = self:DrawCandidates(h, listX, listY, listW, d)
    bottom = listY - lh
  end
  local ch = -bottom + SP.s
  h:SetSize(cw, ch)
  g.area:SetContentHeight(ch)
  if g.area.UpdateBar then g.area:UpdateBar() end
end

-- the chosen slot's candidates (none chosen: the slots with an upgrade, best first). Returns the height.
function View:DrawCandidates(h, x0, y0, w, d)
  local g = self.upgrades
  local cell
  for _, c in ipairs(d.cells) do if c.key == V.state.slot then cell = c end end
  local list, title
  if cell then
    list = cell.list
    title = #list == 0 and cell.label or ("%s: %d %s"):format(cell.label, #list, plural(#list, "candidate"))
  else
    list = {}
    for _, c in ipairs(d.cells) do if c.now then list[#list + 1] = c.now end end
    table.sort(list, function(a, b) return (a.delta or 0) > (b.delta or 0) end)
    title = d.found == 0 and "No upgrades on the auction house" or ("Upgrades for %d %s"):format(d.found, plural(d.found, "slot"))
  end
  local y = y0
  local _, th = word(h, g.listTitle, x0, y, 13, "gold.title", title, w, true)
  y = y - th - SP.s
  if #list == 0 then
    local words = cell and "Nothing on the auction house beats what you wear here." or
      (self.upData and V:AffordOnly() and "Nothing you can afford beats what you wear. Untick Only what I can afford to see the rest." or "Nothing on the auction house beats what you wear.")
    local nh = para(h, g.none, x0, y, 12, "text.muted", words, w)
    return -(y - nh - y0)
  end
  for i = 1, min(#list, V.MAX_CANDIDATES) do
    local c = list[i]
    local r = g.rows[i]
    if not r then
      r = {}
      r.btn = Panel.Row(h)
      r.btn.panoplyGapOK = true
      r.icon = Host.ItemSlot(r.btn, 22)
      r.icon:SetPoint("LEFT", r.btn, "LEFT", 2, 0)
      r.name = Panel.Cell(r.btn, 28, 100, "LEFT", 12)
      r.gain = Panel.Cell(r.btn, 0, 60, "RIGHT", 11)
      r.price = Panel.Cell(r.btn, 0, 90, "RIGHT", 12)
      r.btn:HookScript("OnEnter", function(row) V.Tip(row) end)
      r.btn:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      g.rows[i] = r
    end
    local b = r.btn
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", h, "TOPLEFT", x0, y)
    b:SetSize(w, V.ROW_H)
    local priceW, gainW = 96, 56
    r.price:ClearAllPoints(); r.price:SetPoint("RIGHT", b, "RIGHT", -4, 0); r.price:SetWidth(priceW); r.price.cellW = priceW
    r.gain:ClearAllPoints(); r.gain:SetPoint("RIGHT", b, "RIGHT", -4 - priceW - SP.s, 0); r.gain:SetWidth(gainW); r.gain.cellW = gainW
    local nw = max(30, w - 28 - priceW - gainW - 2 * SP.s - 8)
    r.name:SetWidth(nw); r.name.cellW = nw
    r.icon:Set(c.icon, c.quality, c.link or c.itemID or c.id)
    Panel.Put(r.name, c.name or "?")
    setColor(r.name, (c.quality and c.quality >= 1) and C.QualityColor(c.quality) or Skin.colors.text)
    Host.Fit(r.gain, Panoply.Gear.DeltaText(c.delta), gainW, 11, "done")
    Host.Fit(r.price, money(c.price or 0), priceW, 12, "text")
    local key = c.source and c.source.key or c.itemID
    b.link, b.nameText = c.link or V.LinkOf(key), c.name
    b:SetScript("OnClick", function() V:ShowItem(c.name) end)
    for _, part in pairs(r) do if type(part) == "table" and part.Show then part:Show() end end
    y = y - V.ROW_H
  end
  if #list > V.MAX_CANDIDATES then
    local nh = para(h, g.none, x0, y - SP.xs, 11, "text.muted", ("And %d more."):format(#list - V.MAX_CANDIDATES), w)
    y = y - nh - SP.xs
  end
  return -(y - y0)
end

function View:DrawHistory(x0, y0, W, H, band)
  local g = self.history
  g:ClearAllPoints(); g:SetPoint("TOPLEFT", self.host, "TOPLEFT", x0, y0)
  g:SetSize(W, H)
  g:Show()
  local st = V.state
  local d = V:HistoryData()
  if not d.ever then
    -- nothing recorded at all: the whole tab is one line
    g.charBtn:Hide(); g.periodBtn:Hide(); g.help:Hide(); g.list.box:Hide()
    for _, t in pairs(g.cells) do t:Hide() end
    for _, fs in ipairs(g.hdr) do fs:Hide() end
    para(g, g.empty, 0, 0, 13, "text.muted", V.WORDS.histEmpty, W)
    return
  end
  -- the menus
  g.charBtn.label:SetText(st.char or "All characters on this realm")
  local pl = "All kept"
  for _, e in ipairs(V.PERIODS) do if e[1] == st.period then pl = e[2] end end
  g.periodBtn.label:SetText(pl)
  local avail = W - 16 - 2 * SP.m
  local cbw = Skin.FitButton(g.charBtn, 160, max(160, floor(avail * 0.6)))
  Skin.FitButton(g.periodBtn, 120, max(120, avail - cbw))
  g.charBtn:ClearAllPoints(); g.charBtn:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
  g.periodBtn:ClearAllPoints(); g.periodBtn:SetPoint("LEFT", g.charBtn, "RIGHT", SP.m, 0)
  g.charBtn:Show(); g.periodBtn:Show()
  g.help:ClearAllPoints(); g.help:SetPoint("TOPRIGHT", g, "TOPRIGHT", -2, -5)
  g.help:Show()
  local y = 26 + SP.m
  -- the three stat cells: side by side, or stacked (Narrow)
  local T = d.totals
  local words = {
    bought = { "Bought", ("%d"):format(T.bought.n), money(T.bought.paid) },
    sold = { "Sold", ("%d"):format(T.sold.n), money(T.sold.got) },
    unsold = { "Didn't sell", ("%d"):format(T.unsold.n), ("%d expired, %d cancelled"):format(T.unsold.expired, T.unsold.cancelled) },
  }
  local tips = {
    bought = ("%d %s, %s paid in all."):format(T.bought.n, plural(T.bought.n, "purchase"), money(T.bought.paid)),
    sold = ("%d %s for %s. The auction house's cut: %s. You received %s.%s"):format(T.sold.n, plural(T.sold.n, "sale"), money(T.sold.price),
      money(max(0, T.sold.price - T.sold.got)), money(T.sold.got),
      T.sold.waiting > 0 and (" %d more %s waiting for the mail that says what you received."):format(T.sold.waiting, T.sold.waiting == 1 and "is" or "are") or ""),
    unsold = ("%d did not sell: %d expired, %d cancelled. Deposits paid on them: %s.%s"):format(T.unsold.n, T.unsold.expired, T.unsold.cancelled,
      money(T.unsold.deposit), (T.listed or 0) > 0 and (" %d still listed."):format(T.listed) or ""),
  }
  local stack = band == "narrow"
  local cellW = stack and W - 14 or floor((W - 14 - 2 * SP.m) / 3)
  local cellH = 0
  for _, k in ipairs(V.HIST_ORDER) do
    local t = g.cells[k]
    local iw = cellW - 2 * SP.m
    t.lab:SetText(words[k][1]); t.big:SetText(words[k][2]); t.sub:SetText(words[k][3])
    for _, fs in ipairs({ t.lab, t.big, t.sub }) do fs:SetWidth(iw) end
    Skin.Ellipsize(t.sub, words[k][3], iw - (k ~= "unsold" and 18 or 0))
    local hh = SP.s + ceil(TH(t.lab, iw)) + 2 + ceil(TH(t.big, iw)) + 2 + ceil(TH(t.sub, iw)) + SP.s + 2
    if stack then hh = SP.s + max(ceil(TH(t.big, iw)), ceil(TH(t.sub, iw))) + SP.s + 2 end
    cellH = max(cellH, hh)
    t.tip, t.tipBody = V.HIST[k].title, tips[k]
  end
  for i, k in ipairs(V.HIST_ORDER) do
    local t = g.cells[k]
    t:SetSize(cellW, cellH)
    t:ClearAllPoints()
    if stack then t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -(y + (i - 1) * (cellH + SP.s)))
    else t:SetPoint("TOPLEFT", g, "TOPLEFT", (i - 1) * (cellW + SP.m), -y) end
    local iw = cellW - 2 * SP.m
    if stack then
      local lw = floor(iw * 0.4)
      t.lab:SetWidth(lw); t.big:SetWidth(40)
      t.lab:ClearAllPoints(); t.lab:SetPoint("LEFT", t, "LEFT", SP.m, 0)
      t.big:ClearAllPoints(); t.big:SetPoint("LEFT", t, "LEFT", SP.m + lw, 0)
      local sw = iw - lw - 40 - SP.s - 18
      t.sub:SetWidth(max(20, sw))
      Skin.Ellipsize(t.sub, words[k][3], max(20, sw))
      t.sub:ClearAllPoints(); t.sub:SetPoint("LEFT", t, "LEFT", SP.m + lw + 40 + SP.s + (k ~= "unsold" and 18 or 0), 0)
      t.coin:ClearAllPoints(); t.coin:SetPoint("LEFT", t, "LEFT", SP.m + lw + 40 + SP.s, 0)
    else
      local ty = SP.s
      t.lab:ClearAllPoints(); t.lab:SetPoint("TOPLEFT", t, "TOPLEFT", SP.m, -ty); ty = ty + ceil(TH(t.lab, iw)) + 2
      t.big:ClearAllPoints(); t.big:SetPoint("TOPLEFT", t, "TOPLEFT", SP.m, -ty); ty = ty + ceil(TH(t.big, iw)) + 2
      t.coin:ClearAllPoints(); t.coin:SetPoint("TOPLEFT", t, "TOPLEFT", SP.m, -ty)
      local off = k ~= "unsold" and 18 or 0
      t.sub:SetWidth(iw - off)
      Skin.Ellipsize(t.sub, words[k][3], iw - off)
      t.sub:ClearAllPoints(); t.sub:SetPoint("TOPLEFT", t, "TOPLEFT", SP.m + off, -ty)
    end
    if k ~= "unsold" then t.coin:Show() else t.coin:Hide() end
    t.line:ClearAllPoints(); t.line:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", SP.m, 1); t.line:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -SP.m, 1)
    if st.histKind == k then t.line:Show() t.bg:SetLevel(2) else t.line:Hide() t.bg:SetLevel(1) end
    t:Show()
  end
  y = y + (stack and (3 * cellH + 2 * SP.s) or cellH) + SP.m
  -- the table
  local kind = st.histKind
  local HD = V.HIST[kind]
  local rows = d.rows
  local anyWho = false
  for _, r in ipairs(rows) do if (kind == "unsold") or (r.who and r.who ~= "") then anyWho = true end end
  local cols
  if band == "narrow" then
    cols = { { "DATE", 96, "LEFT" }, { "ITEM" }, { HD.amount, 116, "RIGHT" } }
  elseif kind == "unsold" then
    cols = { { "DATE", 120, "LEFT" }, { "ITEM" }, { "STACK", 50, "RIGHT" }, { HD.amount, 128, "RIGHT" }, { HD.who, 96, "LEFT" }, { "DEPOSIT", 96, "RIGHT" } }
  else
    cols = { { "DATE", 120, "LEFT" }, { "ITEM" }, { "STACK", 50, "RIGHT" }, { HD.amount, 128, "RIGHT" }, anyWho and { HD.who, 96, "LEFT" } or false, { "CHARACTER", 96, "LEFT" } }
  end
  local list = {}
  for _, c in ipairs(cols) do if c then list[#list + 1] = c end end
  cols = list
  local gap = SP.m
  local fixed = 0
  for _, c in ipairs(cols) do fixed = fixed + (c[2] or 0) end
  local itemW = W - 14 - fixed - (#cols - 1) * gap - 4
  local colX, colW, x = {}, {}, 4
  for i, c in ipairs(cols) do colW[i] = c[2] or itemW colX[i] = x x = x + colW[i] + gap end
  for i, fs in ipairs(g.hdr) do
    local c = cols[i]
    if c then
      local hx, hw = colX[i], colW[i]
      if not c[2] then hx, hw = hx + 22 + SP.s, hw - 22 - SP.s end
      fs:SetText(c[1]); fs:SetWidth(hw)
      if fs.SetJustifyH then fs:SetJustifyH(c[3] or "LEFT") end
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", g, "TOPLEFT", hx, -y)
      fs:Show()
    else fs:Hide() end
  end
  y = y + 16 + SP.xs
  g.list.box:ClearAllPoints(); g.list.box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y)
  g.list:Size(W, max(0, H - y))
  g.list.box:Show()
  local itemCol
  for i, c in ipairs(cols) do if not c[2] then itemCol = i end end
  for _, r in ipairs(g.list.rows) do
    r.slot:ClearAllPoints(); r.slot:SetPoint("LEFT", r, "LEFT", colX[itemCol], 0)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r, "LEFT", colX[itemCol] + 22 + SP.s, 0)
    r.name:SetWidth(colW[itemCol] - 22 - SP.s); r.name.cellW = colW[itemCol] - 22 - SP.s
    for i = 1, 6 do
      local cell = r.cells[i]
      if cols[i] and i ~= itemCol then
        cell:ClearAllPoints(); cell:SetPoint("LEFT", r, "LEFT", colX[i], 0)
        cell:SetWidth(colW[i]); cell.cellW = colW[i]
        if cell.SetJustifyH then cell:SetJustifyH(cols[i][3] or "LEFT") end
        cell.panoplyCol = cols[i][1]
      else cell.panoplyCol = nil cell:Hide() end
    end
  end
  local howWord = { e = "Expired", c = "Cancelled" }
  g.list:Set(rows, function(r, e)
    local id = e.id ~= 0 and e.id or nil
    local info = id and V.ItemInfo(id)
    local nm = (info and not info.pending and info.name) or e.name or (id and ("Item " .. id)) or "Item"
    r.link, r.nameText = id and V.LinkOf(id) or nil, nm
    r.slot:Set(info and info.icon, info and info.quality, id)
    Panel.Put(r.name, nm)
    setColor(r.name, (info and info.quality and info.quality >= 1) and C.QualityColor(info.quality) or Skin.colors.text)
    for i = 1, 6 do
      local cell, col = r.cells[i], r.cells[i].panoplyCol
      if col then
        local text, color = "", "text"
        if col == "DATE" then text, color = V.DateText(e.t), "inkSoft"
        elseif col == "STACK" then text = tostring(e.stack)
        elseif col == HD.amount then
          if kind == "sold" then text, color = e.got > 0 and money(e.got) or "waiting for mail", e.got > 0 and "done" or "inkSoft"
          elseif kind == "bought" then text, color = e.paid > 0 and money(e.paid) or "?", e.paid > 0 and "text" or "inkSoft"
          else text, color = e.price > 0 and money(e.price) or "?", e.price > 0 and "text" or "inkSoft" end
        elseif col == HD.who then
          if kind == "unsold" then text, color = howWord[e.how] or "Expired", e.how == "c" and "warn" or "text" else text = e.who or "" end
        elseif col == "DEPOSIT" then text, color = e.deposit > 0 and money(e.deposit) or "", "inkSoft"
        elseif col == "CHARACTER" then text = e.char or "" end
        Host.Fit(cell, text, cell.cellW, 12, color)
        cell:Show()
      end
    end
  end)
  if #rows == 0 then
    para(g, g.empty, 0, -(y + SP.m), 13, "text.muted", ("No %s in this period."):format(kind == "sold" and "sales" or (kind == "bought" and "purchases" or "unsold auctions")), W)
  else g.empty:Hide() end
end

-------------------------------------------------------------------------------
-- What the player does
-------------------------------------------------------------------------------
function V.Tip(row)
  local GT = _G.GameTooltip
  if GT and row.tipText then
    GT:SetOwner(row, "ANCHOR_RIGHT")
    GT:SetText(row.tipText, 0.9, 0.9, 0.88, 1, true)
    GT:Show()
    return
  end
  if not (GT and row.link) then return end
  GT:SetOwner(row, "ANCHOR_RIGHT")
  local ok = GT.SetHyperlink and pcall(GT.SetHyperlink, GT, row.link)
  if not ok then GT:SetText(row.nameText or "", 0.95, 0.84, 0.55, 1, true) end
  GT:Show()
end

-- a new search, category or order starts at the top of the lists again
function V:Top()
  for _, v in ipairs(self.views) do
    if v.prices and v.prices.list then v.prices.list.offset = 0 end
    if v.history and v.history.list then v.history.list.offset = 0 end
  end
end

function V:Note(what) if Panoply.History and Panoply.History.Note then Panoply.History:Note(what) end end

function V:SetTab(tab, from)
  if self.state.tab == tab then return end
  self.state.tab = tab
  self:RefreshAll()
end
function V:ToggleOpen(key)
  self.state.open = (self.state.open ~= key) and key or nil
  self.reveal = self.state.open
  self:Note("item")
  self:RefreshAll()
end
function V:SelectSlot(key)
  self.state.slot = (self.state.slot ~= key) and key or nil
  self:Note("slot")
  self:RefreshAll()
end
-- an upgrade's row: the Prices tab, searched for that item
function V:ShowItem(name)
  self.state.tab = "prices"
  self.state.query = name or ""
  self.state.cat = nil
  self:Top()
  self:Note("item")
  self:RefreshAll()
end

-- 0.9.5 phase 4G (spec 01 section 8): another page's link to one item on the Prices tab (the Professions Shopping tab): the Auctions page
-- opens (a step of history, with the return chip) searched for that item and with its row open when the scan has it
function V:OpenItem(name, key)
  local st = self.state
  st.tab, st.query, st.cat = "prices", name or "", nil
  -- the scan the Professions page read its price from (this realm and faction's), not one the page had chosen before
  local feed = V.FeedKey()
  local want = (feed ~= R.LatestKey()) and feed or nil
  if st.snapKey ~= want then st.snapKey = want self:Forget() end
  local snap = R.Snap(self:Key())
  st.open = key and snap and R.Item(snap, key) and key or nil
  self.reveal = st.open
  self:Top()
  if Panoply.Menu and Panoply.Menu.Open then Panoply.Menu:Open("auctions") end
  self:RefreshAll()
  return true
end
-- the price the Professions page reads for an item: the lowest buyout and the market price in this realm and faction's scan, and the
-- scan's age in seconds; nil when the scan does not have it
function V.PriceOf(key)
  local snap = R.Snap(V.FeedKey())
  local it = snap and R.Item(snap, key)
  if not it then return nil end
  return { low = it.low, market = it.market, age = max(0, P.Now() - (tonumber(snap.t) or 0)), listings = it.listings }
end
-- "Scanned 3 hours ago" for this realm and faction's scan, or nil with none
function V.ScanAge()
  local snap = R.Snap(V.FeedKey())
  if not (snap and tonumber(snap.t) and tonumber(snap.t) > 0) then return nil end
  return max(0, P.Now() - tonumber(snap.t))
end

-- is the player at an open auction house window?
function V.AtAuctionHouse()
  local f = Auc.Frame and Auc.Frame()
  return f ~= nil and (not f.IsShown or f:IsShown()) and true or false
end
function V.OpenAuctionWindow()
  if V.AtAuctionHouse() and Auc.Panel then Auc.Panel:Show() return true end
  Panoply:Print(V.WORDS.openAway)
  return false
end

-- every view that is showing draws itself again
function V:RefreshAll()
  local M = Panoply.Menu
  if M and M.frame and M.frame:IsShown() and M.current == "auctions" and M.RefreshCurrent then M:RefreshCurrent() end
  if Auc.Browser and Auc.Browser.Refresh then Auc.Browser:Refresh() end
  self.reveal = nil
end
function V:Visible()
  local M = Panoply.Menu
  local page = M and M.frame and M.frame:IsShown() and M.current == "auctions"
  local pop = Auc.Browser and Auc.Browser.frame and Auc.Browser.frame:IsShown()
  return (page or pop) and true or false
end

-- the page's own state for back and forward: the open item, the chosen slot, the search, the History filters
if Panoply.History then Panoply.History:State("auctions", {
  get = function() local s = V.state return { open = s.open, slot = s.slot, query = s.query, cat = s.cat, kind = s.histKind, char = s.char, period = s.period } end,
  set = function(s)
    if type(s) ~= "table" then return end
    local st = V.state
    st.open, st.slot, st.query, st.cat = s.open, s.slot, s.query or "", s.cat
    st.histKind, st.char, st.period = s.kind or st.histKind, s.char, s.period or st.period
  end,
  key = function(s) return type(s) == "table" and table.concat({ tostring(s.open), tostring(s.slot), tostring(s.query), tostring(s.cat), tostring(s.kind), tostring(s.char), tostring(s.period) }, "|") or tostring(s) end,
}) end
Kit.TabVar("auctions", { get = function() return V.state.tab end, set = function(k) V.state.tab = k end, default = "prices",
  valid = function(k) return k == "prices" or k == "upgrades" or k == "history" end })

-------------------------------------------------------------------------------
-- When something changes
-------------------------------------------------------------------------------
for _, ev in ipairs({ "AUCTION_RECORD_CHANGED", "AUCTION_SCAN_DONE" }) do
  Panoply:Listen(ev, function(kind)
    V.bytes = nil
    if ev == "AUCTION_SCAN_DONE" or kind == "scan" or kind == nil or kind == "trim" then
      V.cache, V.feed = nil, nil
      if Panoply.Gear and Panoply.Gear.SourceChanged then Panoply.Gear:SourceChanged("auction") end
    end
    if V:Visible() then V:RefreshAll() end
  end)
end
-- the gear engine finished (or changed) a result: the Upgrades tab shows it. Its progress while it works is shown at most a few
-- times a second (0.9.6: before, every slice of the engine's work drew the whole tab again).
V.PROGRESS_EVERY = 0.25
Panoply:Listen("GEAR_CHANGED", function(_, what)
  if not (V:Visible() and V.state.tab == "upgrades") then return end
  if what ~= "progress" then V:RefreshAll() return end
  if V.progressWait then return end
  V.progressWait = true
  C.After(V.PROGRESS_EVERY, function()
    V.progressWait = nil
    if V:Visible() and V.state.tab == "upgrades" then V:RefreshAll() end
  end)
end)
Panoply:On("PLAYER_MONEY", function() if V:Visible() and V.state.tab == "upgrades" and V:AffordOnly() then V:RefreshAll() end end)
-- an item the game did not know yet is now known: its name, icon and class are filled in (at most every two seconds)
V.INFO_EVERY = 2
function V:ResolvePending()
  local c = self.cache
  local changed = false
  for key in pairs(c and c.pending or {}) do
    local inf = self.infoCache[key]
    local ii = inf and inf.id and C.ItemInfo(inf.id)
    if ii and ii.name then
      inf.name, inf.lname, inf.icon, inf.quality, inf.class, inf.pending = ii.name, ii.name:lower(), ii.icon or C.ItemIcon(inf.id), ii.quality, ii.classID, nil
      c.pending[key] = nil
      changed = true
    end
  end
  return changed
end
-- 0.9.6: the items of the scan the game has named since the summary was made: the weapons and armour among them are added to the
-- summary and handed to the gear engine as new rows (it fills them in; nothing is worked out again from the start). Returns how
-- many rows were added.
function V.FeedArrived()
  local f = V.feed
  local data = f and f.data
  local arrived = V.feedArrived
  V.feedArrived = nil
  if not (data and arrived and f.snap) then return 0 end
  local rows = {}
  for id in pairs(arrived) do
    local keys = data.waiting and data.waiting[id]
    local ii = keys and C.ItemInfo(id)
    if keys and ii and ii.classID then
      data.waiting[id] = nil
      data.pending = max(0, (data.pending or 0) - #keys)
      if V.GEAR_CLASS[ii.classID] then
        for _, key in ipairs(keys) do
          local it = R.Item(f.snap, key)
          if it and it.low then
            local row = { ref = V.LinkOf(key), price = it.low, market = it.market, key = key }
            data.items[#data.items + 1] = row
            rows[#rows + 1] = { ref = row.ref, price = row.price, source = Panoply.GearSources.AuctionRecord(row, data.age) }
          end
        end
      end
    end
  end
  local G = Panoply.Gear
  if #rows > 0 and G and G.AddCandidates then G:AddCandidates("auction", rows) end
  return #rows
end
Panoply:On("GET_ITEM_INFO_RECEIVED", function(_, id, success)
  -- the engine's auction source left out items the game had not named: an answer for one of them is collected, and they are added
  -- together (at most every 2 s). An answer for anything else, or a "no such item", changes nothing.
  id = tonumber(id)
  local waiting = V.feed and V.feed.data and V.feed.data.waiting
  if id and waiting and waiting[id] then
    if success == false then
      V.feed.data.pending = max(0, (V.feed.data.pending or 0) - #waiting[id])
      waiting[id] = nil
    else
      V.feedArrived = V.feedArrived or {}
      V.feedArrived[id] = true
      if not V.feedWait then
        V.feedWait = true
        C.After(V.INFO_EVERY, function()
          V.feedWait = nil
          V.FeedArrived()
        end)
      end
    end
  end
  if not (V:Visible() and V.cache and next(V.cache.pending or {})) or V.infoWait then return end
  V.infoWait = true
  C.After(V.INFO_EVERY, function()
    V.infoWait = nil
    if not V:Visible() then return end
    if V:ResolvePending() then
      V.cache = nil                 -- decoded again: the names, the sort, the categories and the category menu follow
      V:RefreshAll()
    end
  end)
end)
