-- Auctions: the Panoply Suite Sell tab (0.7.4; replaces the old Selling tab of the Trade window).
-- docs/auctions/AUCTIONS-REDESIGN-SPEC.md sections 3, 4, 6, 7.
--   left   the sell list: every sellable bag item (not soulbound), best profit per post first, items with no price last,
--          a Post button on each row, and "Post all worthwhile".
--   right  the item card of the picked item: icon and name, what the scan says, the verdict (Verdict.lua), the numbers of
--          one post (price, the house's cut, cost, profit, deposit), the price / stacks / stack size / length boxes,
--          "Check price now" (one search) and Post. With nothing picked: a summary of the verdicts.
-- Blizzard policy (Auc:Request, Trade.lua): picking, typing and re-sorting send nothing. Post sends ONE post per click
-- (Stacks above 1 is still one PostAuction call, like the game's own Create Auction button; default 1).
-- "Post all worthwhile" posts ONE auction per click, the first Post it row, and never a Keep it, Vendor it or Scan first
-- row. After a post the next one waits until the game has updated the bags (BAG_UPDATE_DELAYED, or a few seconds).
-- A post the game holds back for confirmation (Era, AUCTION_HOUSE_POST_WARNING) is not sent or recorded; the control then
-- reads "Confirm post" and the next click sends the same post confirmed.
-- A Vendor it row, or a price under half the 30-day average, needs a second click ("Post anyway").
-- UNVERIFIED in a real client: filling the sell slot from a row click and quoting the deposit in the same click (Era),
-- the Forever shapes (one Quantity, PostCommodity / PostItem), which bag items the recipe data knows as crafted.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T, V, Host = Auc.Trade, Auc.Verdict, Auc.Host
local S = { hours = 24, entries = {} }
Auc.Sell = S
S.LIST_W = 288
S.ROW_H = 42
S.WAIT = 6                    -- seconds before a post stops waiting for the bags (nothing is sent by this)
S.WHY = {
  busy = "A request is still on its way.", refused = "That click could not send the post.", stale = "The sell slot changed.",
  load = "The auction house would not take that item (soulbound, or not allowed here).",
  ["bad price or stack"] = "Check the price, the stack size and the stacks.",
  ["the sell slot is empty"] = "The sell slot is empty. Pick the item again.", ["not available"] = "This client cannot post that item here.",
  ["nothing loaded"] = "Pick the item again.",
}
local function money(c) return T.MoneyText(math.floor((c or 0) + 0.5)) end
-- the most one post can hold: one stack on Era (the game's own rule), any quantity you have on Forever (commodities)
local function maxStack(it)
  if T.Kind() == "modern" then return it.total end
  return math.min(it.total, math.max(1, it.stack))
end
-- a name short enough for a one-line message
local function short(name, n) name = tostring(name or "") if #name > (n or 22) then return name:sub(1, (n or 22) - 3) .. "..." end return name end
-- big money without the small coins ("4666g" for 4666g 66s 46c): list rows only, the card shows every coin
local function rough(c)
  c = math.floor((c or 0) + 0.5)
  local a = math.abs(c)
  if a >= 100000000 then return T.MoneyText(c < 0 and -(a - a % 10000) or (a - a % 10000)) end
  if a >= 10000000 then return T.MoneyText(c < 0 and -(a - a % 100) or (a - a % 100)) end
  return T.MoneyText(c)
end
local function say(text, bad) if S.ui then S.Say(text, bad) end end
local function setBox(box, text) Auc.Panel.SetBox(box, text) end
local function tint(fs, name)
  local c = Skin.colors[name] or Skin.colors.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
end
-- A button that looks quiet but still takes the click (a Vendor it row, a post with no price yet): its click explains or asks
-- again. (Skin's SetDimmed draws a slash across an icon: that is for toggles, not for this.)
local function quiet(b, on)
  if b.disabled then return end
  tint(b.label, on and "dim" or "text")
  b.bg:SetAlpha(on and 0.7 or 1)
end

-------------------------------------------------------------------------------
-- What is known about one bag item (no frames, no requests)
-------------------------------------------------------------------------------
-- The price facts: lowest price each, how many are for sale, when it was seen, the price to suggest.
function S.Info(it)
  local info = { id = it.id }
  local res = T.results
  local rows = res and res.purpose == "sell" and res.term == it.name and res.rows or nil
  local rec
  if rows then                                    -- a "Check price now" answer: the freshest word there is
    local low, n = nil, 0
    for _, r in ipairs(rows) do
      if not r.mine then
        n = n + (r.count or 1)
        if r.unit and (not low or r.unit < low) then low = r.unit end
      end
    end
    info.lowest, info.forSale, info.seenAt, info.age, info.checked = low, n, res.t, math.max(0, P.Now() - (res.t or P.Now())), true
    if low then info.suggest = T.Undercut(low) end
  end
  local _, r = P.Market(it.id, it.link)
  rec = r
  info.rec = rec
  if rec then
    info.source = rec.source
    if not info.checked then
      info.age = rec.age
      if rec.source == "scan" and not rec.listed then      -- nobody had it for sale at the last full scan
        info.seenAt, info.lastSeen = rec.lastSeenAt, rec.lastSeen
        info.suggest = rec.lastSeen
      else
        info.lowest, info.forSale, info.seenAt = rec.price, rec.qty, rec.at
        info.suggest = T.Undercut(rec.price)
      end
    elseif not info.suggest then
      info.suggest = rec.lastSeen or rec.price        -- nobody else sells it now: the last price seen, as it is
    end
  end
  return info
end

-- One sell-list entry. over = { price, stack, stacks } to use the numbers typed in the boxes.
function S.Entry(it, over)
  over = over or {}
  local info = S.Info(it)
  local ce = P.CostEach(it.id)
  local stack = over.stack or math.min(it.stack > 0 and it.stack or 1, it.total)
  local price = over.price or info.suggest
  local e = { item = it, id = it.id, name = it.name, icon = it.icon, quality = it.quality, have = it.total, info = info, ce = ce,
    stack = stack, stacks = over.stacks or 1, price = price, hours = S.hours }
  e.v = V.Compute({ price = price, stack = stack, vendor = ce.vendor, cost = ce.cost, cut = P.AHCut(), worth = V.Worth() })
  e.crafted = ce.kind == "crafted"
  return e
end

-- What the number boxes say right now (nil for a box that is empty or not a number).
function S.Typed()
  local ui = S.ui
  if not ui then return {} end
  local function num(box)
    local n = tonumber(box:GetText() or "")
    return (n and n >= 1 and n == math.floor(n)) and n or nil
  end
  local text = ui.price:GetText() or ""
  return { price = T.ParseMoney(text), priceText = text, stack = num(ui.stack), stacks = num(ui.stacks) }
end

function S.Items() return T.BagItems() end

-- Rebuild the entries from the bags. keepOrder: leave the rows where they are (while a number is being typed).
function S.Build(keepOrder)
  local items = S.Items()
  local typed = S.Typed()
  local list = {}
  for _, it in ipairs(items) do
    local over
    if S.sel == it.id then over = { price = typed.price, stack = typed.stack, stacks = typed.stacks } end
    list[#list + 1] = S.Entry(it, over)
  end
  if keepOrder and #S.entries == #list then
    local pos = {}
    for i, e in ipairs(S.entries) do pos[e.id] = i end
    table.sort(list, function(a, b) return (pos[a.id] or 1e9) < (pos[b.id] or 1e9) end)
  else
    table.sort(list, V.Before)
  end
  S.entries = list
  return list
end
function S.Selected() for _, e in ipairs(S.entries) do if e.id == S.sel then return e end end end

-- The rows with the verdict Post it (the ones "Post all worthwhile" may post), in list order.
function S.Worthwhile(skipDone)
  local out = {}
  for _, e in ipairs(S.entries) do
    if e.v.verdict == V.POST and not (skipDone and S.round and S.round[e.id]) then out[#out + 1] = e end
  end
  return out
end

-------------------------------------------------------------------------------
-- Picking an item, posting
-------------------------------------------------------------------------------
-- Put the item in the game's sell slot (a local action, no request) so the game can quote the deposit.
function S.EnsureLoaded(it)
  if not it then return false end
  if T.sale and T.sale.item and T.sale.item.id == it.id then return true end
  return T:Load(it)
end

function S.Pick(e)
  if not e then return end
  if S.sel == e.id then return end
  if not T:Load(e.item) then
    say(S.WHY.load, true)
    return
  end
  S.sel, S.armed, S.held, S.priceTouched = e.id, nil, nil, false
  S.hours = (Panoply.db and T.DUR[Panoply.db.auctionSellHours] and Panoply.db.auctionSellHours) or 24
  local ui = S.ui
  local ne = S.Entry(e.item)
  setBox(ui.stack, tostring(ne.stack))
  setBox(ui.stacks, "1")
  setBox(ui.price, ne.info.suggest and T.MoneyText(ne.info.suggest) or "")
  say("")
  S.Refresh()
end

local function sigOf(e) return ("%s:%d:%d:%d:%d"):format(tostring(e.id), e.price or 0, e.stack, e.stacks, e.hours) end

-- Post what an entry says: ONE click, ONE request. how = "card" | "row" | "all".
-- Returns true when the post went out.
function S.Post(e, how)
  if not e then return false end
  local it = e.item
  if how == "card" then
    local t = S.Typed()
    if not t.price or t.price < 1 then say("Type the price like 1g 20s 5c (g, s and c, not a bare number).", true) return false end
    if not t.stack or t.stack > maxStack(it) then
      say(("%s must be a whole number from 1 to %d."):format(T.Kind() == "modern" and "Quantity" or "Stack size", maxStack(it)), true)
      return false
    end
    if not t.stacks or t.stacks * t.stack > it.total or (T.Kind() == "modern" and t.stacks > 1) then
      local most = T.Kind() == "modern" and 1 or math.floor(it.total / t.stack)
      say(("You have %d: at most %d stack%s of %d."):format(it.total, most, most == 1 and "" or "s", t.stack), true)
      return false
    end
  end
  if not e.price or e.price < 1 then say("No price on file. Scan, or pick it and type a price.", true) return false end
  local sig = sigOf(e)
  local risky
  if e.v.verdict == V.VENDOR then risky = "A vendor pays as much."
  else
    local why, kind = T.TooLow(it.id, e.price)
    if why then risky = kind == "vendor" and "Under the vendor price." or "Under half the usual price." end
  end
  if risky and S.armed ~= sig and S.held ~= sig then
    S.armed = sig
    say(risky .. " Click again to post anyway.", true)
    S.Refresh(true)
    return false
  end
  local confirm = S.held == sig
  local ok, why = T.Click(function()
    if not S.EnsureLoaded(it) then return false, "load" end
    return T:Post(e.stack, e.price, e.hours, confirm, e.stacks)
  end)
  S.armed = nil
  if not ok then
    if why == "confirm" then
      S.held = sig
      say("The game wants you to confirm this post. Click Confirm post.", true)
    else
      S.held = nil
      say(S.WHY[why] or tostring(why), true)
    end
    S.Refresh(true)
    return false
  end
  S.held = nil
  say(("Posted %d x %s at %s each (%s)%s."):format(e.stack * e.stacks, short(e.name, 22), money(e.price), T.DurLabel(e.hours),
    e.stacks > 1 and (", %d stacks"):format(e.stacks) or ""))
  Panoply:SetOption("auctionSellHours", e.hours)
  -- the game empties the sell slot and changes the bags a moment later; the next post waits for that
  T.sale = nil
  S.waiting = (S.waiting or 0) + 1
  local token = S.waiting
  C.After(S.WAIT, function() if S.waiting == token then S.waiting = nil S.Refresh(true) end end)
  S.Refresh(true)
  return true
end

-- "Post all worthwhile": the first Post it row not yet posted in this round. ONE auction per click.
function S.PostNext()
  local list = S.Worthwhile(true)
  if #list == 0 then S.round = nil list = S.Worthwhile(false) end
  local e = list[1]
  if not e then say("Nothing here is worth posting right now.", true) return false end
  S.round = S.round or {}
  local ok = S.Post(e, "all")
  if ok then S.round[e.id] = true S.Refresh(true) end
  return ok
end

-- One search for the picked item (Check price now): who else sells it and for how much.
function S.Lookup()
  local e = S.Selected()
  if not e then say("Pick an item from the list first.", true) return end
  local ok, why = T.Click(function() return T:Search(e.name, true, "sell") end)
  if ok then say("Asking the auction house about " .. short(e.name, 22) .. "...") else say(Auc.Shopping.WHY[why] or tostring(why), true) end
  S.Refresh(true)
end

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------
function S.Say(text, bad)
  local ui = S.ui
  if not ui then return end
  if (text or "") == "" then text = "One click posts one. Click again for the next one." bad = false end
  ui.note:SetText(text)
  tint(ui.note, bad and "warn" or "inkSoft")
end

local function build(body, W, H)
  local ui = {}
  S.ui = ui
  local PAD, TOP, LW = 10, 6, S.LIST_W
  local CW = W - 2 * PAD - LW - 10
  local HC = H - 2 * TOP                     -- the height of both cards
  ui.W, ui.H, ui.CW = W, H, CW
  local U = Host
  -- left: the sell list
  local left = Skin.Card(body)
  left:SetSize(LW, HC); left:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -TOP)
  ui.left = left
  ui.listHead = U.Text(left, 10, -8, LW - 84, 10, "inkSoft", "label")
  ui.listHead:SetText("SELL LIST: BEST PROFIT FIRST")
  ui.count = U.Text(left, LW - 76, -8, 66, 10, "inkSoft", "label", "RIGHT")
  local listH = HC - 28 - 28 - 4 - 34 - 6
  ui.list = Auc.Panel.List(left, LW - 12, listH, S.ROW_H, function(parent)
    local r = Auc.Panel.Row(parent)
    r.slot = U.ItemSlot(r, 30)
    r.slot:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name = U.Text(r, 40, -2, 166, 12, "text", "semi")
    r.verdict = U.Text(r, 40, -21, 58, 10, "text", "label")
    r.count = U.Text(r, 98, -21, 30, 10, "inkSoft")
    r.profit = U.Text(r, 128, -21, 80, 10, "text", "semi", "RIGHT")
    r.post = Skin.Button(r, "Post", 50, 26, function(self) S.RowPost(self:GetParent()) end, "Post", "Posts this item at the price and stack shown. One click, one auction.")
    r.post:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r:SetScript("OnClick", function(self) S.Pick(self.entry) end)
    return r
  end)
  ui.list.sf:SetPoint("TOPLEFT", left, "TOPLEFT", 4, -28)
  ui.postAll = Skin.Button(left, "Post all worthwhile", LW - 20, 28, function() S.PostNext() end, "Post all worthwhile",
    "Posts the first item that says Post it, then the next, one auction per click. It never posts Keep it, Vendor it or Scan first items.")
  ui.postAll:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 10, 42)
  ui.postAll.panoplyDefault = true
  ui.note = U.Text(left, 10, 0, LW - 20, 10, "inkSoft")
  if ui.note.SetWordWrap then ui.note:SetWordWrap(true) end
  ui.note:SetHeight(34)
  ui.note:ClearAllPoints(); ui.note:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 10, 6)

  -- right: the card (picked item) and the summary (nothing picked)
  local x0 = PAD + LW + 10
  local right = Skin.Card(body)
  right:SetSize(CW, HC); right:SetPoint("TOPLEFT", body, "TOPLEFT", x0, -TOP)
  ui.right = right
  local function R(x, y, w, size, color, role, justify) return U.Text(right, x, y, w, size, color, role, justify) end

  -- summary (nothing picked)
  local sm = {}
  ui.summary = sm
  sm.head = Skin.Heading(right, 15, "Pick an item on the left")
  sm.head:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -10); sm.head:SetWidth(CW - 24)
  if sm.head.SetWordWrap then sm.head:SetWordWrap(false) end
  sm.sub = R(12, -36, CW - 24, 11, "inkSoft")
  sm.rows = {}
  for i, v in ipairs({ V.POST, V.KEEP, V.VENDOR, V.SCAN }) do
    local y = -60 - (i - 1) * 28
    local row = { v = v }
    row.bg = right:CreateTexture(nil, "BACKGROUND")
    Skin.Round(row.bg, Skin.RADIUS.row, Skin.TEX.RFill)
    row.bg:SetPoint("TOPLEFT", right, "TOPLEFT", 10, y); row.bg:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT", -10, y - 24)
    row.bg:SetVertexColor(Skin.colors.panel[1], Skin.colors.panel[2], Skin.colors.panel[3], 0.9)
    row.word = R(18, y - 3, 90, 12, V.COLOR[v], "semi")
    row.word:SetText(V.NAME[v])
    row.n = R(110, y - 3, 66, 12, "text", nil, "RIGHT")
    row.text = R(186, y - 3, CW - 186 - 16, 11, "inkSoft")
    sm.rows[i] = row
  end
  local hy = -60 - 4 * 28 - 4
  sm.how = R(12, hy, CW - 24, 10, "inkSoft", "label")
  sm.how:SetText("HOW THE VERDICT IS WORKED OUT")
  sm.rules = {}
  for i = 1, 5 do sm.rules[i] = R(12, hy - 18 - (i - 1) * 20, CW - 24, 11, "inkSoft") end

  -- the card (picked item). Every y is measured at 1.3x text (the layout checker), top to bottom; the whole card is 318 high
  -- at the smallest area the panels are drawn for (330).
  local cd = {}
  ui.card = cd
  cd.slot = U.ItemSlot(right, 44)
  cd.slot:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -8)
  local gridW, labW = 196, 94
  local textW = CW - 10 - 62 - gridW - 10
  cd.name = Skin.Heading(right, 14)
  cd.name:SetPoint("TOPLEFT", right, "TOPLEFT", 62, -6); cd.name:SetWidth(textW)
  if cd.name.SetWordWrap then cd.name:SetWordWrap(false) end
  cd.name.cellW = textW
  cd.stackLine = R(62, -28, textW, 11, "text"); cd.stackLine.cellW = textW
  cd.costLine = R(62, -47, textW, 10, "inkSoft")
  cd.costLine:SetHeight(35)
  if cd.costLine.SetWordWrap then cd.costLine:SetWordWrap(true) end
  -- what the scan says: four label / value lines at the right of the header
  local gx = CW - 10 - gridW
  cd.gl, cd.gv = {}, {}
  for i = 1, 4 do
    cd.gl[i] = R(gx, -8 - (i - 1) * 19, labW, 10, "inkSoft", "label")
    cd.gv[i] = R(gx + labW, -6 - (i - 1) * 19, gridW - labW, 11, "text", "semi", "RIGHT")
    cd.gv[i].cellW = gridW - labW
  end
  cd.gl[1]:SetText("LOWEST EACH"); cd.gl[2]:SetText("FOR SALE"); cd.gl[3]:SetText("LAST SCAN"); cd.gl[4]:SetText("VENDOR EACH")
  -- the verdict strip: a flat tinted fill and a thin line, re-tinted per verdict (no glow)
  cd.strip = CreateFrame("Frame", nil, right)
  cd.strip:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -85); cd.strip:SetSize(CW - 20, 42)
  cd.stripBg, cd.stripLine = Skin.Box(cd.strip, "S", { fill = Skin.colors.inkSoft, fillA = 0.14, line = Skin.colors.inkSoft, lineA = 0.55 })
  cd.verdict = U.Text(cd.strip, 10, -9, 112, 15, "done", "head")
  cd.sentence = U.Text(cd.strip, 128, -2, CW - 20 - 128 - 8, 11, "text")
  if cd.sentence.SetWordWrap then cd.sentence:SetWordWrap(true) end
  cd.sentence:SetHeight(38)
  -- the numbers of one post (left) and the profit (right)
  local ty = -130
  local pw = 132                           -- the profit block's width, at the right
  local px = CW - 10 - pw
  local lw = 108                           -- label column
  local colW = math.floor((px - 8 - 10 - lw - 4) / 2)
  local c1 = 10 + lw + colW                -- right edges of the Each and Stack columns
  local c2 = c1 + 4 + colW
  cd.th1 = R(c1 - colW, ty, colW, 10, "inkSoft", "label", "RIGHT"); cd.th1:SetText("EACH")
  cd.th2 = R(c2 - colW, ty, colW, 10, "inkSoft", "label", "RIGHT")
  cd.rowL, cd.rowE, cd.rowS = {}, {}, {}
  for i = 1, 3 do
    local yy = ty - 17 - (i - 1) * 19
    cd.rowL[i] = R(10, yy, lw, 11, "text")
    cd.rowE[i] = R(c1 - colW, yy, colW, 11, "text", nil, "RIGHT"); cd.rowE[i].cellW = colW
    cd.rowS[i] = R(c2 - colW, yy, colW, 11, "text", nil, "RIGHT"); cd.rowS[i].cellW = colW
  end
  cd.pLabel = R(px, ty, pw, 10, "inkSoft", "label")
  cd.pBig = R(px, ty - 16, pw, 15, "done", "semi"); cd.pBig.cellW = pw
  cd.pEach = R(px, ty - 43, pw, 11, "done"); cd.pEach.cellW = pw
  cd.dep = R(px, ty - 62, pw, 10, "inkSoft"); cd.dep.cellW = pw
  cd.dep2 = R(px, ty - 79, pw, 10, "inkSoft"); cd.dep2.cellW = pw
  local rule = right:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(Skin.colors.hairline[1], Skin.colors.hairline[2], Skin.colors.hairline[3], 1)
  rule:SetPoint("TOPLEFT", right, "TOPLEFT", px - 6, ty); rule:SetSize(1, 96)
  cd.rule = rule
  -- inputs
  local iy = ty - 100
  cd.priceL = R(10, iy - 3, 80, 11, "inkSoft"); cd.priceL:SetText("Price each")
  ui.price = Auc.Panel.Box(right, 126, 22, "1g 20s 5c", function(self, user)
    if user then S.priceTouched = true S.Refresh(true) end
  end)
  ui.price:SetPoint("TOPLEFT", right, "TOPLEFT", 92, iy)
  cd.suggest = Skin.Button(right, "Suggested", 84, 22, function() S.Suggested() end, "Suggested price",
    "Puts the suggested price back in the box: a bit under the lowest price somebody else asks.")
  cd.suggest:SetPoint("LEFT", ui.price, "RIGHT", 6, 0)
  ui.stacks = Auc.Panel.Box(right, 52, 22, "1", function(self, user) if user then S.Refresh(true) end end)
  ui.stacks:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, iy)
  cd.stacksL = R(0, 0, 56, 11, "inkSoft", nil, "RIGHT")
  cd.stacksL:ClearAllPoints(); cd.stacksL:SetPoint("RIGHT", ui.stacks, "LEFT", -6, 0)
  cd.stacksL:SetText("Stacks")
  local iy2 = iy - 25
  cd.stackL = R(10, iy2 - 3, 80, 11, "inkSoft"); cd.stackL:SetText("Stack size")
  ui.stack = Auc.Panel.Box(right, 52, 22, "1", function(self, user) if user then S.Refresh(true) end end)
  ui.stack:SetPoint("TOPLEFT", right, "TOPLEFT", 92, iy2)
  cd.max = Skin.Button(right, "Max", 44, 22, function() S.Max() end, "Biggest stack", "The most one auction can hold (the stack size of this item, or what your bags have).")
  cd.max:SetPoint("LEFT", ui.stack, "RIGHT", 6, 0)
  ui.dur = {}
  local dw = 72
  for i = #T.HOURS, 1, -1 do
    local h = T.HOURS[i]
    local label = T.DurLabel(h)
    local b = Skin.Button(right, label, dw, 22, function() S.hours = h Panoply:SetOption("auctionSellHours", h) S.Refresh(true) end, label,
      "How long the auction runs. A longer auction costs a bigger deposit.")
    b:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10 - (#T.HOURS - i) * (dw + 4), iy2)
    ui.dur[h] = b
  end
  -- actions
  local ay = iy2 - 26
  ui.lookup = Skin.Button(right, "Check price now", 128, 26, function() S.Lookup() end, "Check price now",
    "Asks the auction house who sells this item right now (one search per click).")
  ui.lookup:SetPoint("TOPLEFT", right, "TOPLEFT", 10, ay)
  ui.post = Skin.Button(right, "Post", 214, 30, function() S.Post(S.Selected(), "card") end, "Post",
    "Posts the stacks above at this price. One click sends one post. Nothing is posted by itself. The deposit is held by the auction house and comes back when the item sells.")
  ui.post:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, ay)
  ui.post.panoplyDefault = true
  S.Say("")
end

function S.RowPost(row)
  local e = row and row.entry
  if not e then return end
  if e.v.verdict == V.SCAN then
    say("No price on file. Scan, or pick it and click Check price now.", true)
    return
  end
  S.Post(e, "row")
end

function S.Suggested()
  local e = S.Selected()
  if not e then return end
  S.priceTouched = false
  setBox(S.ui.price, e.info.suggest and T.MoneyText(e.info.suggest) or "")
  S.Refresh(true)
end
function S.Max()
  local e = S.Selected()
  if not e then return end
  setBox(S.ui.stack, tostring(maxStack(e.item)))
  S.Refresh(true)
end

-------------------------------------------------------------------------------
-- Drawing (reads the entries; sends nothing)
-------------------------------------------------------------------------------
local function paintStrip(cd, v)
  local name = V.COLOR[v] or "inkSoft"
  local c = Skin.colors[name]
  cd.stripBg:SetVertexColor(c[1], c[2], c[3], 0.14)
  cd.stripLine:SetVertexColor(c[1], c[2], c[3], 0.55)
  tint(cd.verdict, name)
end

local function fillRow(r, e)
  r.entry = e
  r.slot:Set(e.icon, e.quality, (e.item and e.item.link) or e.id)
  Auc.Panel.Put(r.name, e.name)
  local v = e.v
  r.verdict:SetText(V.NAME[v.verdict]); tint(r.verdict, V.COLOR[v.verdict])
  r.count:SetText("x" .. e.have)
  if v.profit then r.profit:SetText((v.profit < 0 and "-" or "+") .. rough(math.abs(v.profit))); tint(r.profit, v.profit >= 0 and "done" or "loss")
  else r.profit:SetText("no price"); tint(r.profit, "inkSoft") end
  r:SetSelected(S.sel == e.id)
  local sig = sigOf(e)
  local busy = T:Busy() or S.waiting
  r.post.label:SetText(S.held == sig and "Confirm" or (S.armed == sig and "Sure?" or "Post"))
  r.post:SetEnabledLook(not busy)
  if not busy then quiet(r.post, v.verdict == V.VENDOR or v.verdict == V.SCAN) end
end

local function refreshSummary(sm, entries)
  local n, sum = {}, {}
  for _, e in ipairs(entries) do
    local k = e.v.verdict
    n[k] = (n[k] or 0) + 1
    if k == V.POST then sum[k] = (sum[k] or 0) + e.v.profit
    elseif k == V.VENDOR then sum[k] = (sum[k] or 0) + e.v.vendorStack end
  end
  local text = {
    post = ("%s if they all sell"):format("+" .. rough(sum.post or 0)),
    keep = "hold for a better price",
    vendor = ("%s from a vendor"):format(rough(sum.vendor or 0)),
    scan = "scan to get a price",
  }
  for _, row in ipairs(sm.rows) do
    local c = n[row.v] or 0
    row.n:SetText(("%d item%s"):format(c, c == 1 and "" or "s"))
    row.text:SetText(text[row.v])
  end
  local worth = money(V.Worth())
  sm.rules[1]:SetText(("Post it: the profit after the cut is at least %s."):format(worth))
  sm.rules[2]:SetText("Vendor it: a vendor pays as much as the cut leaves you.")
  sm.rules[3]:SetText(("Keep it: posting earns under %s, or loses money."):format(worth))
  sm.rules[4]:SetText("Cost: the cost to make it, or what a vendor pays.")
  sm.rules[5]:SetText("Deposit: returned when the item sells.")
end

local function sourcePhrase(info)
  local s = info.source
  if s == "companion" then return "FROM FILE" elseif s == "region" then return "US AVERAGE" end
  return "LAST SCAN"
end

local function refreshCard(cd, e)
  local ui = S.ui
  local it, v, info, ce = e.item, e.v, e.info, e.ce
  cd.slot:Set(e.icon, e.quality, (e.item and e.item.link) or e.id)
  Host.FitName(cd.name, e.name, cd.name.cellW, 14)
  local modern = T.Kind() == "modern"
  Host.Fit(cd.stackLine, (modern and "Selling %d - you have %d" or "Stack of %d - you have %d"):format(e.stack, it.total), cd.stackLine.cellW, 11, "text")
  if ce.kind == "crafted" then
    cd.costLine:SetText(("Crafted (%s): your cost is its materials"):format(ce.prof or "profession"))
  elseif ce.partial then
    cd.costLine:SetText("Some materials have no price: using the vendor price")
  else
    cd.costLine:SetText("Not crafted: your cost is the vendor price")
  end
  -- what the scan says
  cd.gl[3]:SetText(sourcePhrase(info))
  local function gv(i, text, color) Host.Fit(cd.gv[i], text, cd.gv[i].cellW, 11, color or "text", "semi") end
  gv(1, info.lowest and money(info.lowest) or (info.checked or info.lastSeen) and "none listed now" or "none on file")
  gv(2, info.forSale and tostring(info.forSale) or "-")
  if info.seenAt and info.age then
    local old = info.age > P.OLD
    gv(3, V.Ago(info.age) .. (old and " (old)" or ""), old and "warn" or "done")
  elseif info.rec then
    gv(3, "age unknown", "warn")
  else
    gv(3, "never", "warn")
  end
  gv(4, ce.vendor > 0 and money(ce.vendor) or "-")
  -- the verdict strip
  cd.verdict:SetText(V.NAME[v.verdict])
  paintStrip(cd, v.verdict)
  local sig = sigOf(e)
  Host.FitPara(cd.sentence, V.Sentence(v, e.crafted and ce.kind == "crafted", V.Worth()), 36, 11, "text")
  -- the numbers
  local cutPct = math.floor(P.AHCut() * 100 + 0.5)
  cd.th2:SetText(("STACK OF %d"):format(e.stack))
  cd.rowL[1]:SetText("You ask")
  cd.rowL[2]:SetText(("House cut (%d%%)"):format(cutPct))
  cd.rowL[3]:SetText(ce.kind == "crafted" and "Cost to make" or "Vendor price")
  if v.price then
    local cutEach = v.price - math.floor(v.price * (1 - v.cutRate) + 0.5)
    local E = { money(v.price), "-" .. money(cutEach), "-" .. money(math.floor(v.costEach + 0.5)) }
    local St = { money(v.sale), "-" .. money(v.cutAmount), "-" .. money(v.cost) }
    for i = 1, 3 do
      Host.Fit(cd.rowE[i], E[i], cd.rowE[i].cellW, 11, "text")
      Host.Fit(cd.rowS[i], St[i], cd.rowS[i].cellW, 11, "text")
    end
  else
    for i = 1, 3 do cd.rowE[i]:SetText("-"); cd.rowS[i]:SetText("-") end
  end
  -- profit block
  local dep
  if not S.waiting and not (T.sale and T.sale.item and T.sale.item.id == it.id) then S.EnsureLoaded(it) end   -- local: no request
  if T.sale and T.sale.item and T.sale.item.id == it.id then
    local t = S.Typed()
    if t.price and t.stack then dep = T:Deposit(e.hours, t.stack, t.price, t.stacks or 1) end
  end
  if v.profit then
    local good = v.profit >= 0
    cd.pLabel:SetText(good and "PROFIT" or "LOSS")
    cd.pBig:SetText(V.Signed(v.profit)); tint(cd.pBig, good and "done" or "loss")
    local each = (e.stacks > 1 and not modern) and ("%s each, x%d"):format(V.Signed(v.profitEach), e.stacks) or (V.Signed(v.profitEach) .. " each")
    Host.Fit(cd.pEach, each, cd.pEach.cellW, 11, v.profitEach >= 0 and "done" or "loss")
  else
    cd.pLabel:SetText("PROFIT"); cd.pBig:SetText("-"); tint(cd.pBig, "inkSoft"); cd.pEach:SetText("")
  end
  if dep then
    local over = v.profit and v.profit > 0 and dep > v.profit
    Host.Fit(cd.dep, ("Deposit %s"):format(money(dep)), cd.dep.cellW, 10, over and "warn" or "inkSoft")
    if over then cd.dep2:SetText("more than the profit"); tint(cd.dep2, "warn") else cd.dep2:SetText("back when it sells"); tint(cd.dep2, "inkSoft") end
  else
    cd.dep:SetText("Deposit -"); tint(cd.dep, "inkSoft")
    cd.dep2:SetText("")
  end
  Host.Fit(cd.pBig, cd.pBig:GetText(), cd.pBig.cellW, 15, v.profit and (v.profit >= 0 and "done" or "loss") or "inkSoft", "semi")
  -- boxes and buttons
  cd.stackL:SetText(modern and "Quantity" or "Stack size")
  if modern then cd.stacksL:Hide() ui.stacks:Hide() else cd.stacksL:Show() ui.stacks:Show() end
  for h, b in pairs(ui.dur) do b:SetSelected(h == S.hours) end
  local busy = T:Busy() or S.waiting
  ui.lookup:SetEnabledLook(not busy)
  ui.post:SetEnabledLook(not busy)
  local label
  if S.held == sig then label = "Confirm post"
  elseif S.armed == sig then label = "Post anyway"
  elseif not S.Typed().price then label = "Type a price first"
  elseif modern then label = ("Post %d"):format(e.stack)
  elseif e.stacks > 1 then label = ("Post %d stacks of %d"):format(e.stacks, e.stack)
  else label = ("Post 1 stack of %d"):format(e.stack) end
  ui.post.label:SetText(label)
  if not busy then quiet(ui.post, label == "Type a price first") end
  if S.armed == sig and v.verdict == V.VENDOR then tint(ui.post.label, "loss") end
end

function S.Refresh(keepOrder)
  local ui = S.ui
  if not ui then return end
  local entries = S.Build(keepOrder)
  local sel = S.Selected()
  if S.sel and not sel then                       -- the item left the bags (all posted or moved)
    S.sel, S.armed, S.held = nil, nil, nil
    T:Unload()
  end
  ui.count:SetText(("%d item%s"):format(#entries, #entries == 1 and "" or "s"))
  ui.list:Set(entries, fillRow)
  -- Post all worthwhile
  local all = S.Worthwhile(false)
  local left = #S.Worthwhile(true)
  if S.round and left == 0 then S.round = nil left = #all end
  local busy = T:Busy() or S.waiting
  local top = S.Worthwhile(true)[1]
  local label
  if top and S.held == sigOf(top) then label = "Confirm post"
  elseif S.round and next(S.round) then label = ("Post next (%d left)"):format(left)
  else label = ("Post all worthwhile (%d)"):format(#all) end
  ui.postAll.label:SetText(label)
  ui.postAll:SetEnabledLook(not busy and #all > 0)
  -- right side
  if sel then
    ui.summary.head:Hide(); ui.summary.sub:Hide(); ui.summary.how:Hide()
    for _, r in ipairs(ui.summary.rows) do r.bg:Hide(); r.word:Hide(); r.n:Hide(); r.text:Hide() end
    for _, r in ipairs(ui.summary.rules) do r:Hide() end
    S.ShowCard(true)
    refreshCard(ui.card, sel)
  else
    S.ShowCard(false)
    local sm = ui.summary
    sm.head:Show(); sm.sub:Show(); sm.how:Show()
    sm.head:SetText(#entries > 0 and "Pick an item on the left" or "Nothing to sell in your bags")
    sm.sub:SetText(#entries > 0 and "Or post everything worth posting, one click at a time." or "Soulbound items are not listed.")
    for _, r in ipairs(sm.rows) do r.bg:Show(); r.word:Show(); r.n:Show(); r.text:Show() end
    for _, r in ipairs(sm.rules) do r:Show() end
    refreshSummary(sm, entries)
    ui.post:SetEnabledLook(false)
  end
end

-- show / hide every control of the card (the boxes, buttons and texts that belong to a picked item)
function S.ShowCard(on)
  local ui = S.ui
  local cd = ui.card
  local frames = { ui.price, ui.stacks, ui.stack, ui.lookup, ui.post, cd.suggest, cd.max, cd.slot, cd.strip }
  for _, b in pairs(ui.dur) do frames[#frames + 1] = b end
  for _, f in ipairs(frames) do if on then f:Show() else f:Hide() end end
  local texts = { cd.name, cd.stackLine, cd.costLine, cd.th1, cd.th2, cd.pLabel, cd.pBig, cd.pEach, cd.dep, cd.dep2, cd.priceL, cd.stacksL, cd.stackL, cd.rule }
  for _, t in ipairs(cd.gl) do texts[#texts + 1] = t end
  for _, t in ipairs(cd.gv) do texts[#texts + 1] = t end
  for _, t in ipairs(cd.rowL) do texts[#texts + 1] = t end
  for _, t in ipairs(cd.rowE) do texts[#texts + 1] = t end
  for _, t in ipairs(cd.rowS) do texts[#texts + 1] = t end
  for _, t in ipairs(texts) do if on then t:Show() else t:Hide() end end
end

local function refresh() S.Refresh(false) end
Host:AddPanel("sell", "Panoply Suite Sell", "Post items from your bags: a price, a verdict and the profit.", build, refresh)
Host.panels.sell.say = function(text, bad) S.Say(text, bad) end

-- the game updated the bags: the waiting post is over; the list is worked out again
Panoply:On("BAG_UPDATE_DELAYED", function()
  S.waiting = nil
  if not (Host.shell and Host.shell:IsShown() and Host.current == "sell") then return end
  S.Refresh(false)
  local now = S.Selected()
  if now then S.EnsureLoaded(now.item) end
end)
Panoply:On("AUCTION_HOUSE_CLOSED", function() S.sel, S.armed, S.held, S.round, S.waiting = nil, nil, nil, nil, nil end)
Panoply:Listen("AUCTION_SCAN_DONE", function() S.round = nil end)
