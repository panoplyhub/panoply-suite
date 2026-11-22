-- Auctions: History tab (0.7.3). The 30 days of prices Panoply Suite keeps for every scanned item (one
-- bar per day: the lowest buyout that day) and "Your history": what you posted, from this window.
-- Reads Panoply.Prices only; nothing here talks to the auction house.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local Panel = Auc.Panel
local H = {}
Auc.History = H
H.LIST_W, H.ROWS = 232, 60          -- at most 60 items listed at once
H.CHART_W, H.CHART_H = 360, 84

local function money(c) return Panoply.Auctions.Trade and Panoply.Auctions.Trade.MoneyText(c) or C.FormatMoney(c) end
local function day(d) return (_G.date and date("%b %d", d * P.DAY)) or tostring(d) end

-- names of the items this realm has prices for, cached per realm (item info can arrive later)
function H.Names()
  local k = P.Key()
  if H.cacheKey ~= k then H.cacheKey, H.names = k, {} end
  return H.names
end
-- Items to list: the ones whose name contains `text`; with no text, the ones you posted, then the
-- most recently seen. Returns { { key, name, price, at } ... } (at most H.ROWS).
function H.Find(text)
  text = (text or ""):lower()
  local names, out = H.Names(), {}
  local r = P.DB().realms[P.Key()]
  local mine = {}
  for _, m in ipairs(P.Mine()) do mine[m.id] = true end
  for _, key in ipairs(P.Known()) do
    local n = names[key]
    if not n or n:find("^item %d+$") then n = P.KeyName(key) names[key] = n end
    if text == "" or n:lower():find(text, 1, true) then
      local e = P.Decode(r.items[key])
      if e and e.cur then out[#out + 1] = { key = key, name = n, price = e.cur, at = e.t or 0, mine = mine[P.KeyID(key)] } end
    end
  end
  table.sort(out, function(a, b)
    if text == "" then
      if (a.mine and true or false) ~= (b.mine and true or false) then return a.mine and true or false end
      if a.at ~= b.at then return a.at > b.at end
    elseif a.name ~= b.name then return a.name < b.name end
    return tostring(a.key) < tostring(b.key)
  end)
  while #out > H.ROWS do table.remove(out) end
  return out
end
-- numbers behind the chart: { days = { {day, min, qty} }, low, high, avg, now, at }
function H.Stats(key)
  local e = P.History(key)
  if not e then return nil end
  local low, high, sum = nil, 0, 0
  for _, d in ipairs(e.hist) do
    low = (not low or d[2] < low) and d[2] or low
    high = math.max(high, d[2]); sum = sum + d[2]
  end
  return { days = e.hist, low = low, high = high, avg = #e.hist > 0 and math.floor(sum / #e.hist + 0.5) or nil, now = e.cur, at = e.t, qty = e.q }
end
-- your postings of one item, newest first (at most `n`)
function H.Posts(key, n)
  local id, out = P.KeyID(key), {}
  local m = P.Mine()
  for i = #m, 1, -1 do
    if m[i].id == id then out[#out + 1] = m[i] if #out >= (n or 6) then break end end
  end
  return out
end

local function build(body)
  local ui = {}
  H.ui = ui
  ui.search = Panel.Box(body, H.LIST_W, 24, "Find a scanned item", function(self)
    H.query = self:GetText() or ""
    Panel:Refresh()
  end)
  ui.search:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  ui.list = Panel.List(body, H.LIST_W, 292, 22, function(parent)
    local r = Panel.Row(parent)
    r.name = Panel.Cell(r, 6, 146)
    r.price = Panel.Cell(r, 154, 70, "RIGHT")
    r:SetScript("OnClick", function(self) H.key = self.item.key Panel:Refresh() end)
    return r
  end)
  ui.list.sf:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -30)
  local x = H.LIST_W + 14
  ui.title = Skin.Heading(body, 15, "")
  ui.title:SetPoint("TOPLEFT", body, "TOPLEFT", x, 0)
  ui.title:SetWidth(H.CHART_W)
  ui.title.cellW = H.CHART_W
  ui.now = Panel.Note(body, H.CHART_W, 12)
  ui.now:SetPoint("TOPLEFT", body, "TOPLEFT", x, -24)
  ui.stats = Panel.Note(body, H.CHART_W, 12)
  ui.stats:SetPoint("TOPLEFT", body, "TOPLEFT", x, -44)
  ui.chart = CreateFrame("Frame", nil, body)
  ui.chart:SetSize(H.CHART_W, H.CHART_H)
  ui.chart:SetPoint("TOPLEFT", body, "TOPLEFT", x, -88)
  ui.base = ui.chart:CreateTexture(nil, "BORDER")
  ui.base:SetPoint("BOTTOMLEFT", ui.chart, "BOTTOMLEFT", 0, 0); ui.base:SetPoint("BOTTOMRIGHT", ui.chart, "BOTTOMRIGHT", 0, 0); ui.base:SetHeight(1)
  Skin.Solid(ui.base, Skin.colors.hairline, 1)
  ui.bars = {}
  ui.first = Panel.Note(body, 150, 11); ui.first:SetPoint("TOPLEFT", ui.chart, "BOTTOMLEFT", 0, -4)
  ui.last = Panel.Note(body, 150, 11); ui.last:SetPoint("TOPRIGHT", ui.chart, "BOTTOMRIGHT", 0, -4)
  if ui.last.SetJustifyH then ui.last:SetJustifyH("RIGHT") end
  ui.mineHead = Skin.Label(body, 12)
  ui.mineHead:SetPoint("TOPLEFT", body, "TOPLEFT", x, -214)
  ui.mineHead:SetText("Your history")
  ui.mine = Panel.Note(body, H.CHART_W, 11)
  ui.mine:SetPoint("TOPLEFT", ui.mineHead, "BOTTOMLEFT", 0, -4)
end

local function drawChart(ui, st)
  local n = #st.days
  local w = math.floor(H.CHART_W / 30)
  for i = 1, math.max(n, #ui.bars) do
    local b = ui.bars[i]
    if not b then
      b = ui.chart:CreateTexture(nil, "ARTWORK")
      Skin.Solid(b, Skin.colors.accent, 0.9)
      ui.bars[i] = b
    end
    local d = st.days[i]
    if d then
      local h = math.max(2, math.floor((H.CHART_H - 4) * d[2] / math.max(1, st.high)))
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", ui.chart, "BOTTOMLEFT", (30 - n + i - 1) * w + 1, 1)
      b:SetSize(w - 2, h)
      b:Show()
    else b:Hide() end
  end
end

local function refresh(body)
  local ui = H.ui
  if not ui then return end
  ui.list:Set(H.Find(H.query), function(r, it)
    Panel.Put(r.name, it.name)
    Panel.Put(r.price, money(it.price))
    r:SetSelected(it.key == H.key)
  end)
  local st = H.key and H.Stats(H.key)
  if not st then
    Panel.Put(ui.title, H.key and P.KeyName(H.key) or "Price history")
    ui.now:SetText(H.key and "No prices kept for this item on this realm." or "Pick an item on the left.")
    ui.stats:SetText("Scan the auction house to fill this in. Panoply Suite keeps up to " .. P.HISTORY_DAYS .. " days per item (at least " .. Panoply.Auctions.Record.STALE_HISTORY_DAYS .. " when its saved data is over the limit).")
    drawChart(ui, { days = {}, high = 1 })
    ui.first:SetText(""); ui.last:SetText(""); ui.mine:SetText("")
    return
  end
  Panel.Put(ui.title, P.KeyName(H.key))
  ui.now:SetText(("Now %s each, seen %s"):format(money(st.now), P.Age(P.Now() - (st.at or 0))))
  ui.stats:SetText(("Low %s  -  average %s  -  high %s"):format(money(st.low or 0), money(st.avg or 0), money(st.high)))
  drawChart(ui, st)
  local d1, dn = st.days[1], st.days[#st.days]
  ui.first:SetText(d1 and day(d1[1]) or "")
  ui.last:SetText(dn and day(dn[1]) or "")
  local lines = {}
  for _, m in ipairs(H.Posts(H.key, 5)) do
    lines[#lines + 1] = ("%s: %d x %s each, %s"):format((_G.date and date("%b %d", m.t)) or "?", m.count or 1, money(m.unit or 0), Auc.Trade.DurLabel(m.hours or 24))
  end
  ui.mine:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing posted from Panoply Suite yet.")
end

Panel:AddTab("history", "History", "Up to the last " .. P.HISTORY_DAYS .. " days of prices Panoply Suite saw for an item, and what you posted.", build, refresh)
