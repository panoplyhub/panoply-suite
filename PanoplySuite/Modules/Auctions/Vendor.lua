-- Auctions: the Panoply Suite Vendor tab (0.7.4). docs/auctions/AUCTIONS-REDESIGN-SPEC.md section 5a.
-- After a scan: every live auction whose BUYOUT is below what a vendor pays for the same items, so the player can buy it
-- and sell it to a vendor at a profit. Profit = vendor price x count - buyout (a vendor sale has no auction house cut).
-- Auctions with only a bid are never listed (a bid can be outbid); items the game gives no vendor price for are never listed.
-- The list is what the last scan kept (Auctions.lua, Auc.deals: replaced by every scan, in memory only, capped).
-- Nothing here scans or buys by itself: the game window's own Scan button fills the list. Buying is two clicks, one purchase
-- per click: Buy selects the row, Confirm buy re-checks that the auction at that position is still the same item, count and
-- buyout, and only then sends ONE purchase (Trade.lua T:BuyClick / T:ConfirmBuy). A bought row leaves the list; the list is
-- never refilled without a scan.
-- "Hide deals under" (default 10 copper, setting auctionHideUnder) keeps tiny profits out of the list and the total.
-- UNVERIFIED in a real client: that a position in the game's list stays valid between the scan and the purchase (the re-check
-- refuses when it does not), the Forever commodity quote flow, and that the scan can read every auction's owner and buyout.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T, V, Host = Auc.Trade, Auc.Verdict, Auc.Host
local D = {}
Auc.Vendor = D
D.ROW_H = 30
D.MAIL = "Bought items arrive by mail: buy, then the mailbox, then any vendor."
D.WHY = {
  stale = "That auction has changed. Scan again.", yours = "That is your own auction.", ["not armed"] = "Click Buy first.",
  busy = "A request is still on its way.", refused = "That click could not send the purchase.",
  ["not available"] = "This client cannot buy that here.", ["server busy"] = "The auction house says wait a moment, then click again.",
  ["no auction house API"] = "This client has no auction house to buy from.",
}
local function money(c) return T.MoneyText(math.floor((c or 0) + 0.5)) end
local function tint(fs, name) local c = Skin.colors[name] or Skin.colors.text fs:SetTextColor(c[1], c[2], c[3], 1) end

-- Deals under this profit (copper) are hidden.
function D.HideUnder()
  local c = T.ParseMoney(Panoply.db and Panoply.db.auctionHideUnder or "10c")
  return c or 10
end

-- The rows to show, best profit first, the hidden count, the total profit of the rows shown, and the scan record.
function D.Rows()
  local deals = Auc.deals
  if not deals then return nil, 0, 0, nil end
  local hide, rows, hidden, total = D.HideUnder(), {}, 0, 0
  for _, d in ipairs(deals.rows) do
    if not d.bought then
      if d.profit >= hide then rows[#rows + 1] = d total = total + d.profit else hidden = hidden + 1 end
    end
  end
  table.sort(rows, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return (a.index or 0) < (b.index or 0) end)
  return rows, hidden, total, deals
end

function D.Say(text, bad)
  local ui = D.ui
  if not ui then return end
  if (text or "") == "" then text = "One click, one auction: Buy, then Confirm buy." bad = false end
  ui.note:SetText(text)
  tint(ui.note, bad and "warn" or "inkSoft")
end

function D.RowClick(d)
  if not d then return end
  local modern = T.Kind() == "modern"
  local cur = T.buy
  local confirming = cur and cur.row == d and (cur.state == "armed" or cur.state == "quoted")
  local ok, why
  if confirming then
    ok, why = T.Click(function() return T:ConfirmBuy(d) end)
    if ok then
      local qty = (cur and cur.qty) or d.count
      local paid = (cur and cur.quote and cur.quote.total) or d.buyout
      D.Say(("Bought %d x %s for %s. Collect it from the mailbox, then sell it to any vendor for %s."):format(qty, d.name or "item", money(paid), money(d.vendor * qty)))
    else
      D.Say(D.WHY[why] or tostring(why), true)
      if why == "stale" then d.stale = true end
    end
  else
    if modern then
      d.limitFor = function(qty) return d.vendor * qty - 1 end         -- the game's price must still be under the vendor value
    end
    ok, why = T.Click(function() return T:BuyClick(d, modern and d.count or nil) end)
    if ok then D.Say(modern and "Asking the game for a price..." or "Check the profit, then click Confirm buy.")
    else D.Say(D.WHY[why] or Auc.Shopping.WHY[why] or tostring(why), true) end
  end
  D.Refresh()
end

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------
-- columns are laid out from the right edge: x and width of each, for a row IW - 12 wide (the item name takes what is left)
local function columns(rowW)
  local c, x = {}, rowW - 2
  x = x - 98; c.buy = { x, 98 }
  x = x - 4 - 96; c.profit = { x, 96 }
  x = x - 4 - 84; c.age = { x, 84 }
  x = x - 4 - 100; c.vendor = { x, 100 }
  x = x - 4 - 96; c.buyout = { x, 96 }
  x = x - 4 - 56; c.count = { x, 56 }
  c.name = { 34, x - 4 - 34 }
  return c
end
local COL
local function build(body, W, H)
  local ui = {}
  D.ui = ui
  local U = Host
  local PAD = 10
  local card = Skin.Card(body)
  card:SetSize(W - 2 * PAD, H - 2 * PAD); card:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -PAD)
  ui.card = card
  local IW = W - 2 * PAD - 20
  COL = columns(IW - 12)
  ui.title = Skin.Heading(card, 15, "Auctions below the vendor price")
  ui.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10); ui.title:SetWidth(IW - 220)
  if ui.title.SetWordWrap then ui.title:SetWordWrap(false) end
  ui.lastL = U.Text(card, 0, 0, 80, 11, "inkSoft", nil, "RIGHT")
  ui.lastL:ClearAllPoints(); ui.lastL:SetPoint("TOPRIGHT", card, "TOPRIGHT", -150, -13)
  ui.lastL:SetText("Last scan")
  ui.last = U.Text(card, 0, 0, 140, 11, "done", "semi", "RIGHT")
  ui.last:ClearAllPoints(); ui.last:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -13)
  ui.sum = U.Text(card, 12, -36, IW - 4, 11, "inkSoft")
  -- the mail notice: always shown (our instruction), not only the first time
  ui.mail = CreateFrame("Frame", nil, card)
  ui.mail:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -58); ui.mail:SetSize(IW, 26)
  ui.mail.bg, ui.mail.rim = Skin.Box(ui.mail, "S", { fill = Skin.colors.accent, fillA = 0.14, line = Skin.colors.accent, lineA = 0.55 })
  ui.mail.text = U.Text(ui.mail, 10, -4, IW - 20, 11, "text")
  ui.mail.text:SetText(D.MAIL)
  -- headers
  local hy = -92
  local heads = { name = "ITEM", count = "COUNT", buyout = "BUYOUT", vendor = "VENDOR PAYS", age = "PRICE AGE", profit = "PROFIT v" }
  for k, text in pairs(heads) do
    local c = COL[k]
    local fs = U.Text(card, 10 + c[1], hy, c[2], 10, k == "profit" and "highlight" or "inkSoft", "label", k == "name" and "LEFT" or "RIGHT")
    fs:SetText(text)
  end
  local ly = hy - 20
  local listH = H - 2 * PAD - (-ly) - 40
  ui.list = Auc.Panel.List(card, IW, listH, D.ROW_H, function(parent)
    local r = Auc.Panel.Row(parent)
    r.slot = U.ItemSlot(r, 24)
    r.slot:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name = U.Text(r, COL.name[1], -5, COL.name[2], 12, "text", "semi")
    r.count = U.Text(r, COL.count[1], -5, COL.count[2], 12, "text", nil, "RIGHT")
    r.buyout = U.Text(r, COL.buyout[1], -5, COL.buyout[2], 12, "text", nil, "RIGHT")
    r.vendor = U.Text(r, COL.vendor[1], -5, COL.vendor[2], 12, "text", nil, "RIGHT")
    r.age = U.Text(r, COL.age[1], -5, COL.age[2], 11, "inkSoft", nil, "RIGHT")
    r.profit = U.Text(r, COL.profit[1], -5, COL.profit[2], 12, "done", "semi", "RIGHT")
    r.buy = Skin.Button(r, "Buy", COL.buy[2], 24, function(self) D.RowClick(self:GetParent().item) end, "Buy",
      "Buy: select this auction. Confirm buy: re-check it and buy it. Two clicks, one purchase.")
    r.buy:SetPoint("LEFT", r, "LEFT", COL.buy[1], 0)
    return r
  end)
  ui.list.sf:SetPoint("TOPLEFT", card, "TOPLEFT", 10, ly)
  -- empty states
  ui.emptyHead = Skin.Heading(card, 14, "")
  ui.emptyHead:SetPoint("TOPLEFT", card, "TOPLEFT", 20, ly - 14); ui.emptyHead:SetWidth(IW - 20)
  if ui.emptyHead.SetWordWrap then ui.emptyHead:SetWordWrap(false) end
  ui.emptyText = U.Text(card, 20, ly - 44, IW - 40, 12, "inkSoft")
  if ui.emptyText.SetWordWrap then ui.emptyText:SetWordWrap(true) end
  ui.emptyText:SetHeight(60)
  -- the footer: Hide deals under
  ui.hideL = U.Text(card, 0, 0, 120, 11, "inkSoft")
  ui.hideL:ClearAllPoints(); ui.hideL:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 14)
  ui.hideL:SetText("Hide deals under")
  ui.hide = Auc.Panel.Box(card, 84, 26, "10c", function(self, user) if user then D.SetHide(self:GetText()) end end)
  ui.hide:SetPoint("LEFT", ui.hideL, "RIGHT", 8, 0)
  Auc.Panel.SetBox(ui.hide, T.MoneyText(D.HideUnder()))
  ui.hidden = U.Text(card, 0, 0, 190, 11, "inkSoft")
  ui.hidden:ClearAllPoints(); ui.hidden:SetPoint("LEFT", ui.hide, "RIGHT", 10, 0)
  ui.note = U.Text(card, 0, 0, 262, 10, "inkSoft", nil, "RIGHT")
  ui.note:ClearAllPoints(); ui.note:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 16)
  if ui.note.SetWordWrap then ui.note:SetWordWrap(true) end
  ui.note:SetHeight(32)
  D.Say("")
end

-- The box accepts the money form ("10c", "1s"); anything else leaves the setting as it was.
function D.SetHide(text)
  local c = T.ParseMoney(text or "")
  if not c then D.Say("Type an amount like 10c or 1s.", true) return end
  Panoply:SetOption("auctionHideUnder", T.MoneyText(c))
  D.Say("")
  D.Refresh()
end

-- 0.9.6.2 launch fix (Nov 18 2026, screenshot new-26): most rows read "item 2072" with a red ? for good. A deal keeps the name
-- and icon the game had when the scan read it, and an item the game had not loaded then was never asked for again. Now a row with
-- no name or icon asks the game for the item (Classic and WoW Forever: C.ItemInfo, then C_Item.RequestLoadItemDataByID where the
-- client has it), and the list is drawn again when the game sends it (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT, below).
-- "item <id>" shows only until then. Same pattern as ProfWindow.lua's PW.waiting.
D.waiting = {}
-- 0.9.7 in-game hotfix: a picture that is the game's own "?" is not a picture (Panoply.Icons, Core/CompatModules.lua), and the
-- picture no longer waits for the item's full information: the game can give it by item id at once.
function D.Resolve(d)
  local I = Panoply.Icons
  if I.IsUnknown(d.icon) then d.icon = nil end
  if d.name and d.icon then return true end
  local ii = C.ItemInfo(d.id)
  if ii then
    d.name, d.quality = d.name or ii.name, d.quality or ii.quality
  end
  d.icon = d.icon or I:Item(d.link or d.id)
  if d.name and d.icon then return true end
  if d.id and not D.waiting[d.id] then
    D.waiting[d.id] = true
    I:Ask(d.id)          -- once per item until the game answers (the shared helper keeps count, so no screen asks twice)
  end
  return false
end
function D.OnItemInfo(id, ok)
  id = tonumber(id)
  if not (id and D.waiting[id]) then return end
  D.waiting[id] = nil
  if ok == false then return end   -- "no such item" for now: the row keeps its placeholder, and asks again when it is drawn again
  D.Refresh()
end
Panoply:On("GET_ITEM_INFO_RECEIVED", function(_, id, ok) D.OnItemInfo(id, ok) end)
Panoply:On("ITEM_DATA_LOAD_RESULT", function(_, id, ok) D.OnItemInfo(id, ok) end)

local function fillRow(r, d)
  r.item = d
  D.Resolve(d)
  r.slot:Set(d.icon, d.quality, d.link or d.id)
  Auc.Panel.Put(r.name, d.name or ("item " .. tostring(d.id)))
  r.count:SetText("x" .. d.count)
  local cur = T.buy
  local mine = cur and cur.row == d
  local paid = d.buyout
  if mine and cur.quote then paid = cur.quote.total end
  local profit = d.vendor * d.count - paid
  if mine and cur.quote then r.buyout:SetText(money(paid)) else r.buyout:SetText(money(d.buyout)) end
  r.vendor:SetText(money(d.vendor * d.count))
  local age = math.max(0, P.Now() - (d.t or P.Now()))
  r.age:SetText(V.Ago(age, true)); tint(r.age, age > P.OLD and "warn" or "inkSoft")
  r.profit:SetText(V.Signed(profit)); tint(r.profit, profit > 0 and "done" or "loss")
  local armed = mine and (cur.state == "armed" or cur.state == "quoted")
  r.buy.label:SetText((mine and cur.state == "asking") and "Asking..." or armed and "Confirm buy" or "Buy")
  r.buy:SetSelected(armed and true or false)
  r.buy:SetEnabledLook(not (T:Busy() or (mine and cur.state == "asking")))
  r:SetSelected(armed and true or false)
end

function D.Refresh()
  local ui = D.ui
  if not ui then return end
  local rows, hidden, total, deals = D.Rows()
  local list = rows or {}
  ui.list:Set(list, fillRow)
  -- last scan
  if deals then
    local age = math.max(0, P.Now() - deals.t)
    ui.last:SetText(V.Ago(age) .. (age > P.OLD and " (old)" or ""))
    tint(ui.last, age > P.OLD and "warn" or (age < P.DAY and "done" or "text"))
  else
    ui.last:SetText("never"); tint(ui.last, "warn")
  end
  -- the line above the list
  if #list > 0 then
    ui.sum:SetText(("%d auction%s you can buy and sell to a vendor. Profit if you buy them all: %s"):format(#list, #list == 1 and "" or "s", V.Signed(total)))
    ui.emptyHead:Hide(); ui.emptyText:Hide()
  else
    ui.sum:SetText("")
    ui.emptyHead:Show(); ui.emptyText:Show()
    if not deals then
      ui.emptyHead:SetText("Scan first")
      ui.emptyText:SetText("Panoply Suite needs a scan to know what is for sale. Click the Scan button on the auction window. Nothing is scanned or bought by itself.")
    else
      ui.emptyHead:SetText("No deals in the last scan")
      ui.emptyText:SetText(("No auction is listed for less than a vendor pays (deals under %s are hidden). Scan again later: prices change all day."):format(money(D.HideUnder())))
    end
  end
  ui.hidden:SetText(hidden > 0 and ("%d smaller deal%s %s hidden"):format(hidden, hidden == 1 and "" or "s", hidden == 1 and "is" or "are") or "")
  local typed = ui.hide:GetText() or ""
  local focused = ui.hide.HasFocus and ui.hide:HasFocus()
  if T.ParseMoney(typed) ~= D.HideUnder() and not focused then Auc.Panel.SetBox(ui.hide, T.MoneyText(D.HideUnder())) end
end

Host:AddPanel("vendor", "Panoply Suite Vendor", "Auctions listed for less than a vendor pays: buy them and sell them to a vendor for a profit.", build, function() D.Refresh() end)
Host.panels.vendor.say = function(text, bad) D.Say(text, bad) end
