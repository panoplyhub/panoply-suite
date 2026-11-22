-- Auctions: the Panoply Suite Buy tab (0.7.4). docs/auctions/AUCTIONS-REDESIGN-SPEC.md section 5.
-- A search box, one search per click, and the answer listed cheapest first by price per item: seller, time left, price
-- each, stack, total buyout, how far from the usual (30-day) price, and a Buy button.
--   Era: the game returns pages of 50; the list shows the page Panoply Suite has loaded now, sorted by price each, with
--     "Page 1 of 3" and Next page (one more search). A purchase goes by the row's position on that page, so only the page
--     the game holds can be bought; a new search or another page puts the old rows away.
--   Buying is two clicks. Buy selects the row (Forever: asks the game for a quote). Confirm buy re-checks the auction and
--     sends ONE purchase (Trade.lua T:BuyClick / T:ConfirmBuy). A moved, sold or re-priced auction sends nothing.
--   Forever: the rows are the game's browse rows (one per item: the lowest price each and how many are for sale). Only
--     commodities (stackable goods) can be bought here, by quantity (UNVERIFIED shape); other items are bought in the
--     game's own Buy tab.
-- Nothing here sends a request without a click (Auc:Request).
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T, V, Host = Auc.Trade, Auc.Verdict, Auc.Host
local B = { exact = true, qty = 1 }
Auc.Buy = B
B.ROW_H = 30
B.LEFT = { [1] = "Short", [2] = "Medium", [3] = "Long", [4] = "Very long" }
B.USUAL_PCT = 3          -- a price this many percent under / over the 30-day average is called out
B.WHY = {
  stale = "That auction has changed. Search again.", yours = "That is your own auction.", ["not armed"] = "Click Buy first.",
  busy = "A request is still on its way.", refused = "That click could not send the purchase.",
  ["not available"] = "This client cannot buy that here.", ["server busy"] = "The auction house says wait a moment, then click again.",
  ["bad quantity"] = "Type a whole number for the quantity.", ["no auction house API"] = "This client has no auction house to buy from.",
}
local function money(c) return T.MoneyText(math.floor((c or 0) + 0.5)) end
local function tint(fs, name) local c = Skin.colors[name] or Skin.colors.text fs:SetTextColor(c[1], c[2], c[3], 1) end

function B.Say(text, bad)
  local ui = B.ui
  if not ui then return end
  if (text or "") == "" then text = "Buy, then Confirm buy: two clicks, one purchase. Only buyout prices are listed." bad = false end
  ui.note:SetText(text)
  tint(ui.note, bad and "warn" or "inkSoft")
end

-- The rows to show: this search's rows with a buyout, cheapest price each first, bought ones gone.
function B.Rows()
  local res = T.results
  if not res or res.purpose ~= "buy" then return nil end
  local rows = {}
  for _, r in ipairs(res.rows or {}) do
    if not r.bought and r.unit then rows[#rows + 1] = r end
  end
  table.sort(rows, function(a, b)
    if a.unit ~= b.unit then return a.unit < b.unit end
    return (a.count or 0) > (b.count or 0)
  end)
  return rows, res
end

-- "-12%" green, "+12%" red, "about usual", "-" when there is no 30-day average. Returns text, colour name.
function B.VsUsual(row)
  local rec = P.FromScan(row.key or row.id)
  local avg = rec and rec.avg
  if not avg or avg <= 0 or not row.unit then return "-", "inkSoft" end
  local pct = math.floor((row.unit - avg) / avg * 100 + (row.unit >= avg and 0.5 or -0.5))
  if pct <= -B.USUAL_PCT then return ("%d%%"):format(pct), "done" end
  if pct >= B.USUAL_PCT then return ("+%d%%"):format(pct), "loss" end
  return "about usual", "inkSoft"
end

function B.Search()
  local ui = B.ui
  local term = ui.search:GetText() or ""
  if term:gsub("%s", "") == "" then B.Say("Type an item name first.", true) return end
  local ok, why = T.Click(function() return T:Search(term, B.exact, "buy") end)
  if ok then B.Say("Asking the auction house for " .. term .. "...") else B.Say(Auc.Shopping.WHY[why] or tostring(why), true) end
  B.Refresh()
end
function B.Next()
  local ok, why = T.Click(function() return T:SearchMore(true) end)
  if ok then B.Say("Asking for the next page...") else B.Say(Auc.Shopping.WHY[why] or tostring(why), true) end
  B.Refresh()
end

-- The quantity box (Forever): a whole number, at least 1.
function B.Qty()
  local n = tonumber(B.ui and B.ui.qty:GetText() or "")
  return (n and n >= 1 and n == math.floor(n)) and n or nil
end

-- The Buy / Confirm buy click of one row.
function B.RowClick(row)
  if not row then return end
  if row.mine then B.Say(B.WHY.yours, true) return end
  local modern = T.Kind() == "modern"
  local cur = T.buy
  local confirming = cur and cur.row == row and (cur.state == "armed" or cur.state == "quoted")
  if modern then
    local CAH = _G.C_AuctionHouse
    local info = CAH and CAH.GetItemKeyInfo and row.itemKey and C.pc(CAH.GetItemKeyInfo, row.itemKey)
    if info and info.isCommodity == false then B.Say("This item is bought in the game's own Buy tab.", true) return end
  end
  local ok, why
  if confirming then
    ok, why = T.Click(function() return T:ConfirmBuy(row) end)
    if ok then
      local q = (cur and cur.qty) or row.count
      B.Say(("Bought %s x %s."):format(tostring(q), row.name or "item"))
    else B.Say(B.WHY[why] or tostring(why), true) end
  else
    local qty = modern and B.Qty() or nil
    if modern and not qty then B.Say(B.WHY["bad quantity"], true) return end
    if modern then
      local q = qty
      row.limitFor = function() return math.floor(row.unit * q) end   -- never more than the price shown, per item
    end
    ok, why = T.Click(function() return T:BuyClick(row, qty) end)
    if ok then
      B.Say(modern and "Asking the game for a price..." or "Check the total, then click Confirm buy.")
    else B.Say(B.WHY[why] or Auc.Shopping.WHY[why] or tostring(why), true) end
  end
  B.Refresh()
end

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------
-- columns are laid out from the right edge: x and width of each, for a row IW - 12 wide (the first column takes what is left)
local function columns(rowW)
  local c, x = {}, rowW - 2
  x = x - 100; c.buy = { x, 100 }
  x = x - 4 - 92; c.vs = { x, 92 }
  x = x - 4 - 112; c.total = { x, 112 }
  x = x - 4 - 44; c.stack = { x, 44 }
  x = x - 4 - 104; c.each = { x, 104 }
  x = x - 4 - 78; c.left = { x, 78 }
  c.who = { 34, x - 4 - 34 }
  return c
end
local COL
local function build(body, W, H)
  local ui = {}
  B.ui = ui
  local U = Host
  local PAD = 10
  local card = Skin.Card(body)
  card:SetSize(W - 2 * PAD, H - 2 * PAD); card:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -PAD)
  ui.card = card
  local IW = W - 2 * PAD - 20
  COL = columns(IW - 12)
  -- search row
  ui.search = Auc.Panel.Box(card, 280, 28, "Item name")
  ui.search:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
  ui.go = Skin.Button(card, "Search", 84, 28, function() B.Search() end, "Search", "Asks the auction house for this item. One search per click.")
  ui.go:SetPoint("LEFT", ui.search, "RIGHT", 6, 0)
  ui.go.panoplyDefault = true
  ui.exact = Skin.Check(card, "Exact name", { get = function() return B.exact end, set = function(v) B.exact = v and true or false end }, nil,
    "On: only items named exactly like this. Off: every item whose name contains it.")
  ui.exact:SetPoint("LEFT", ui.go, "RIGHT", 12, 0)
  ui.qtyL = U.Text(card, 0, 0, 70, 11, "inkSoft", nil, "RIGHT")
  ui.qtyL:ClearAllPoints(); ui.qtyL:SetPoint("TOPLEFT", card, "TOPLEFT", 560, -17)
  ui.qtyL:SetText("Quantity")
  ui.qty = Auc.Panel.Box(card, 52, 28, "1")
  ui.qty:SetPoint("LEFT", ui.qtyL, "RIGHT", 6, 0)
  Auc.Panel.SetBox(ui.qty, "1")
  ui.next = Skin.Button(card, "Next page", 96, 28, function() B.Next() end, "Next page", "Asks for the next page of this search. One search per click.")
  ui.next:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
  ui.page = U.Text(card, 0, 0, 110, 11, "inkSoft", nil, "RIGHT")
  ui.page:ClearAllPoints(); ui.page:SetPoint("RIGHT", ui.next, "LEFT", -8, 0)
  -- the item found
  local fy = -46
  ui.found = CreateFrame("Frame", nil, card)
  ui.found:SetPoint("TOPLEFT", card, "TOPLEFT", 10, fy); ui.found:SetSize(IW, 54)
  ui.found.bg, ui.found.rim = Skin.Box(ui.found, "S", { fill = Skin.colors.panel, fillA = 0.9, line = Skin.colors.hairline })
  ui.found.slot = U.ItemSlot(ui.found, 40)
  ui.found.slot:SetPoint("TOPLEFT", ui.found, "TOPLEFT", 8, -7)
  ui.found.name = Skin.Heading(ui.found, 14)
  local figX = IW - 6 - 3 * 116              -- the three figures sit at the right edge
  ui.found.name:SetPoint("TOPLEFT", ui.found, "TOPLEFT", 56, -4); ui.found.name:SetWidth(figX - 64)
  if ui.found.name.SetWordWrap then ui.found.name:SetWordWrap(false) end
  ui.found.name.cellW = figX - 64
  ui.found.sub = U.Text(ui.found, 56, -29, figX - 64, 10, "inkSoft")
  ui.found.fl, ui.found.fv = {}, {}
  for i, label in ipairs({ "CHEAPEST EACH", "USUAL (30 DAYS)", "VENDOR PAYS" }) do
    local x = figX + (i - 1) * 116
    ui.found.fl[i] = U.Text(ui.found, x, -6, 112, 10, "inkSoft", "label")
    ui.found.fl[i]:SetText(label)
    ui.found.fv[i] = U.Text(ui.found, x, -24, 112, 13, "text", "semi")
    ui.found.fv[i].cellW = 112
  end
  -- column headers
  local hy = fy - 54 - 6
  ui.heads = {}
  local heads = { who = "SELLER", left = "TIME LEFT", each = "PRICE EACH v", stack = "STACK", total = "TOTAL BUYOUT", vs = "VS USUAL" }
  for k, text in pairs(heads) do
    local c = COL[k]
    local fs = U.Text(card, 10 + c[1], hy, c[2], 10, k == "each" and "highlight" or "inkSoft", "label", k == "who" and "LEFT" or "RIGHT")
    fs:SetText(text)
    ui.heads[k] = fs
  end
  -- list
  local ly = hy - 20
  local listH = H - 2 * PAD - (-ly) - 30
  ui.list = Auc.Panel.List(card, IW, listH, B.ROW_H, function(parent)
    local r = Auc.Panel.Row(parent)
    r.slot = U.ItemSlot(r, 26)
    r.slot:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.seller = U.Text(r, COL.who[1], -4, COL.who[2], 12, "text", "semi")
    r.left = U.Text(r, COL.left[1], -5, COL.left[2], 11, "inkSoft", nil, "RIGHT")
    r.each = U.Text(r, COL.each[1], -4, COL.each[2], 12, "text", "semi", "RIGHT")
    r.stack = U.Text(r, COL.stack[1], -4, COL.stack[2], 12, "text", nil, "RIGHT")
    r.total = U.Text(r, COL.total[1], -4, COL.total[2], 12, "text", nil, "RIGHT")
    r.vs = U.Text(r, COL.vs[1], -5, COL.vs[2], 11, "inkSoft", nil, "RIGHT")
    r.buy = Skin.Button(r, "Buy", COL.buy[2], 24, function(self) B.RowClick(self:GetParent().item) end, "Buy",
      "Buy: select this auction. Confirm buy: re-check it and buy it. Two clicks, one purchase.")
    r.buy:SetPoint("LEFT", r, "LEFT", COL.buy[1], 0)
    return r
  end)
  ui.list.sf:SetPoint("TOPLEFT", card, "TOPLEFT", 10, ly)
  ui.empty = U.Text(card, 20, ly - 20, IW - 20, 12, "inkSoft")
  if ui.empty.SetWordWrap then ui.empty:SetWordWrap(true) end
  ui.empty:SetHeight(40)
  ui.note = U.Text(card, 10, 0, IW, 10, "inkSoft")
  ui.note:ClearAllPoints(); ui.note:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 8)
  B.Say("")
end

-- one item in the results: the seller is the first column; with several different items it is the item's name instead
local function fillRow(r, e)
  r.item = e
  r.slot:Set(e.icon, e.quality, e.link or e.id)
  local modern = e.browse
  local who = e.mine and "You" or (e.owner or (modern and "Lowest price" or "Another seller"))
  Auc.Panel.Put(r.seller, B.multi and (e.name or ("item " .. tostring(e.id))) or who)
  r.left:SetText(e.left and B.LEFT[e.left] or "-")
  r.each:SetText(money(e.unit))
  r.stack:SetText(tostring(e.count or 1))
  local cur = T.buy
  local mine = cur and cur.row == e
  local total = e.unit * (e.count or 1)
  if mine and cur.quote then total = cur.quote.total end
  r.total:SetText(money(total))
  local vs, color = B.VsUsual(e)
  r.vs:SetText(vs); tint(r.vs, color)
  tint(r.each, "text")
  r.buy.label:SetText((mine and cur.state == "asking") and "Asking..." or (mine and (cur.state == "armed" or cur.state == "quoted")) and "Confirm buy" or "Buy")
  r.buy:SetSelected(mine and (cur.state == "armed" or cur.state == "quoted") or false)
  r.buy:SetEnabledLook(not (T:Busy() or (mine and cur.state == "asking")) and not e.mine)
  r:SetSelected(mine and true or false)
end

function B.Refresh()
  local ui = B.ui
  if not ui then return end
  local modern = T.Kind() == "modern"
  local rows, res = B.Rows()
  if modern then ui.qty:Show() ui.qtyL:Show() else ui.qty:Hide() ui.qtyL:Hide() end
  local list = rows or {}
  B.multi = false
  for _, r in ipairs(list) do if r.id ~= list[1].id then B.multi = true end end
  ui.heads.who:SetText(B.multi and "ITEM" or (modern and "WHO" or "SELLER"))
  -- the cheapest row's price is the green one
  ui.list:Set(list, fillRow)
  if list[1] then
    for _, r in ipairs(ui.list.rows) do
      if r:IsShown() and r.item == list[1] and not list[1].mine then tint(r.each, "done") end
    end
  end
  -- page and next
  if res and res.kind == "classic" then
    local pages = math.max(1, math.ceil((res.total or 0) / Auc.PAGE))
    ui.page:SetText(("Page %d of %d"):format((res.page or 0) + 1, pages))
    ui.next:Show(); ui.page:Show()
    ui.next:SetEnabledLook(res.more and not T:Busy() and true or false)
  else
    ui.next:Hide(); ui.page:Hide()
  end
  ui.go:SetEnabledLook(not T:Busy())
  -- the item found
  local f = ui.found
  if res and list[1] then
    local e = list[1]
    f:Show()
    f.slot:Set(e.icon, e.quality, e.link or e.id)
    Host.FitName(f.name, e.name or "?", f.name.cellW, 14)
    local low
    for _, r in ipairs(list) do if not r.mine and (not low or r.unit < low) then low = r.unit end end
    local n = res.total or #list
    f.sub:SetText(("%d auction%s for sale, searched %s"):format(n, n == 1 and "" or "s", V.Ago(math.max(0, P.Now() - (res.t or P.Now())))))
    local rec = P.FromScan(e.key or e.id)
    local ii = C.ItemInfo(e.id)
    Host.Fit(f.fv[1], low and money(low) or "-", 112, 13, "done", "semi")
    Host.Fit(f.fv[2], rec and rec.avg and money(rec.avg) or "-", 112, 13, "text", "semi")
    Host.Fit(f.fv[3], ii and ii.sellPrice and ii.sellPrice > 0 and money(ii.sellPrice) or "-", 112, 13, "text", "semi")
  else
    f:Hide()
  end
  -- empty states
  if not res then
    ui.empty:SetText("Type an item name and click Search. One search per click; nothing is searched or bought by itself.")
    ui.empty:Show()
  elseif #list == 0 then
    ui.empty:SetText(res.exact and "No auctions with a buyout price for that exact name. Try again without Exact name." or "No auctions with a buyout price for that name.")
    ui.empty:Show()
  else
    ui.empty:Hide()
  end
end

Host:AddPanel("buy", "Panoply Suite Buy", "Search the auction house, cheapest price per item first, and buy in two clicks.", build, function() B.Refresh() end)
Host.panels.buy.say = function(text, bad) B.Say(text, bad) end
