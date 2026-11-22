-- Auctions: Shopping tab (0.7.3). Shopping lists of item names and searches in the auction house.
-- One click = one search (Blizzard policy; see Trade.lua). "Search next" walks the list one term per
-- click instead of firing every search at once. Lists are saved account wide (Panoply.db.auctionLists;
-- at most 20 lists of 100 terms), plus the last 10 searches. Share a list as text (Export / Import).
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T = Auc.Trade
local Panel = Auc.Panel
local S = { best = {} }
Auc.Shopping = S
S.LEFT_W, S.RIGHT_W = 232, 366
S.WHY = {
  busy = "A search is still on its way.", ["server busy"] = "The auction house says wait a moment, then click again.",
  ["a scan is running"] = "Stop the scan first (the X next to the progress bar).", refused = "That click was not allowed to send a request.",
  empty = "Type an item name first.", ["no auction house API"] = "This client has no auction house to search.",
}
local function say(text, bad) Panel:Say(text, bad) end
local function money(c) return T.MoneyText(c) end

-- the list being shown: a saved list, or the recent searches (index 0)
function S.Lists() local L = T.Lists() if #L == 0 then T.NewList("Default") end return L end
function S.Current()
  local L = S.Lists()
  if S.index == 0 then return { name = "Recent searches", terms = T.Recent(), recent = true } end
  S.index = math.min(math.max(S.index or 1, 1), #L)
  return L[S.index]
end

-- One search for `term`, from the player's click.
function S.Search(term)
  local ok, why = T.Click(function() return T:Search(term, true, "shop") end)
  if ok then say(("Asking the auction house for %s..."):format(term)) else say(S.WHY[why] or tostring(why), true) end
  Panel:Refresh()
  return ok
end
-- The next term after the one searched last (one search per click).
function S.SearchNext()
  local cur = S.Current()
  if #cur.terms == 0 then say("Add an item name to this list first.", true) return false end
  local i = ((S.cursor or 0) % #cur.terms) + 1
  S.cursor = i
  return S.Search(cur.terms[i])
end

-- The materials of the recipe picked in the profession window, as a shopping list "Recipe: <name>" (made
-- again each time). No request: the names are searched one click at a time like any other list.
function S.FromRecipe()
  local PW = Panoply.ProfWindow
  local row = PW and PW.SelectedRow and PW:SelectedRow()
  if not row or #(row.reagents or {}) == 0 then say("Pick a recipe in the profession window first.", true) return false end
  local l = T.NewList(("Recipe: %s"):format(row.name))
  if not l then say("No more lists (the limit is " .. T.MAX_LISTS .. ").", true) return false end
  l.terms = {}
  for _, rg in ipairs(row.reagents) do
    local ii = rg.itemID and C.ItemInfo(rg.itemID)
    local n = rg.name or (ii and ii.name)
    if n then T.AddTerm(l, n) end
  end
  for i, x in ipairs(S.Lists()) do if x == l then S.index = i end end
  S.cursor = 0
  say(("The materials of %s are in the list \"%s\". Click a name to search for it."):format(row.name, l.name))
  Panel:Refresh()
  return true
end

local function build(body)
  local ui = {}
  S.ui = ui
  local LW = S.LEFT_W
  ui.pick = Skin.Button(body, "", 116, 24, function(b)
    local items = {}
    for i, l in ipairs(S.Lists()) do items[#items + 1] = { text = l.name, checked = (S.index or 1) == i, func = function() S.index = i S.cursor = 0 Panel:Refresh() end } end
    items[#items + 1] = { text = "Recent searches", checked = S.index == 0, func = function() S.index = 0 S.cursor = 0 Panel:Refresh() end }
    Skin.Menu(b, items)
  end, "Pick a list", "Your shopping lists, and your recent searches.")
  ui.pick:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  ui.new = Skin.Button(body, "New", 46, 24, function()
    local name = ui.add:GetText()
    if not name or name:gsub("%s", "") == "" then name = "List " .. (#S.Lists() + 1) end
    local l = T.NewList(name)
    if l then
      for i, x in ipairs(S.Lists()) do if x == l then S.index = i end end
      Panel.SetBox(ui.add, "")
      say(("List \"%s\" made. Type item names below and click Add."):format(l.name))
    else say("No more lists (the limit is " .. T.MAX_LISTS .. ").", true) end
    Panel:Refresh()
  end, "New list", "Makes a list. Type its name in the box below first, or leave the box empty.")
  ui.new:SetPoint("LEFT", ui.pick, "RIGHT", 4, 0)
  -- 0.9.5 phase 4J (spec 02 section 1, theme pass): Delete is in a ⋯ menu and asks first (it was a button that deleted at once)
  local function deleteList(cur)
    if cur.recent then return end
    T.DeleteList(cur)
    S.index = 1; S.cursor = 0
    say(("List \"%s\" deleted."):format(cur.name))
    Panel:Refresh()
  end
  ui.del = Panoply.Kit.More(body, function()
    local cur = S.Current()
    if cur.recent then
      return { { text = Skin.Code(Skin.colors.dim) .. "Delete this list|r", tip = "Recent searches is not a list of yours: it cannot be deleted." } }
    end
    -- (the question is one menu heading: a long list name is cut so it stays inside the menu)
    local nm = tostring(cur.name or "")
    if #nm > 18 then nm = nm:sub(1, 16):gsub("[\192-\255][\128-\191]*$", "") .. "..." end   -- (never half a letter)
    return { { text = "Delete this list", tip = "Asks first, then deletes the list shown (not the items in your bags).",
      func = function() Panoply.Kit.Ask(ui.del, ("Delete the list \"%s\"?"):format(nm), "Yes, delete it", function() deleteList(cur) end, "Keep it") end } }
  end, "Delete the list shown (asks first).", 24)
  ui.del:SetPoint("LEFT", ui.new, "RIGHT", 4, 0)

  ui.terms = Panel.List(body, LW, 168, 24, function(parent)
    local r = Panel.Row(parent)
    r.name = Panel.Cell(r, 6, 114)
    r.price = Panel.Cell(r, 124, 78, "RIGHT", 11)
    r.x = Skin.Button(r, "x", 18, 18, function(self)
      local cur = S.Current()
      if not cur.recent then T.RemoveTerm(cur, self:GetParent().index) Panel:Refresh() end
    end, "Remove", "Takes this item name off the list.")
    r.x:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r:SetScript("OnClick", function(self) S.Search(self.item) end)
    Skin.Tooltip(r, "Search", "One click asks the auction house for this item once.")
    return r
  end)
  ui.terms.sf:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -30)

  ui.add = Panel.Box(body, 168, 24, "Item name")
  ui.add:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -204)
  ui.addBtn = Skin.Button(body, "Add", 56, 24, function()
    local cur = S.Current()
    if cur.recent then say("Recent searches fill themselves. Pick a list to add names.", true) return end
    if T.AddTerm(cur, ui.add:GetText()) then Panel.SetBox(ui.add, "") else say("Not added: empty, already in the list, or the list is full.", true) end
    Panel:Refresh()
  end, "Add to list", "Adds the item name in the box to the list shown.")
  ui.addBtn:SetPoint("LEFT", ui.add, "RIGHT", 6, 0)
  ui.addBtn.panoplyDefault = true

  ui.next = Skin.Button(body, "Search next", 100, 24, function() S.SearchNext() end, "Search the next item",
    "Searches the next item name in the list, one search per click.")
  ui.next:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -236)
  ui.export = Skin.Button(body, "Export", 62, 24, function()
    local cur = S.Current()
    Panel.SetBox(ui.share, T.Export(cur))
    if ui.share.HighlightText then ui.share:HighlightText() end
    say("The list is in the box below: copy it (Ctrl+C) to share it.")
  end, "Export list", "Puts the list as text in the box below so you can copy it.")
  ui.export:SetPoint("LEFT", ui.next, "RIGHT", 4, 0)
  ui.import = Skin.Button(body, "Import", 62, 24, function()
    local l, n = T.Import(ui.share:GetText())
    if l then
      for i, x in ipairs(S.Lists()) do if x == l then S.index = i end end
      say(("Imported \"%s\": %d item names."):format(l.name, n))
    else say(S.WHY[n] or tostring(n), true) end
    Panel:Refresh()
  end, "Import list", "Reads a list that was exported from Panoply Suite (paste it in the box below first).")
  ui.import:SetPoint("LEFT", ui.export, "RIGHT", 4, 0)
  ui.share = Panel.Box(body, LW, 24, "Paste a list here")
  ui.share:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -268)
  ui.recipe = Skin.Button(body, "Materials of the open recipe", LW, 24, function() S.FromRecipe() end, "Materials of the open recipe",
    "Makes a list of the materials of the recipe picked in the Panoply Suite profession window, ready to search.")
  ui.recipe:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -298)

  local x = LW + 12
  ui.head = Skin.Heading(body, 14, "Results")
  ui.head:SetPoint("TOPLEFT", body, "TOPLEFT", x, 0)
  ui.head:SetWidth(S.RIGHT_W)
  ui.head.cellW = S.RIGHT_W
  ui.info = Panel.Note(body, S.RIGHT_W, 11)
  ui.info:SetPoint("TOPLEFT", body, "TOPLEFT", x, -22)
  if ui.info.SetWordWrap then ui.info:SetWordWrap(false) end
  ui.colHead = {}
  for i, c in ipairs({ { "Item", 6, 104, "LEFT" }, { "Qty", 114, 34, "RIGHT" }, { "Each", 152, 98, "RIGHT" }, { "Total", 254, 98, "RIGHT" } }) do
    local fs = Skin.Label(body, 11)
    fs:SetPoint("TOPLEFT", body, "TOPLEFT", x + c[2], -44)
    fs:SetWidth(c[3]); if fs.SetJustifyH then fs:SetJustifyH(c[4]) end
    fs:SetText(c[1])
    ui.colHead[i] = fs
  end
  ui.results = Panel.List(body, S.RIGHT_W, 214, 22, function(parent)
    local r = Panel.Row(parent)
    r.name = Panel.Cell(r, 6, 104)
    r.qty = Panel.Cell(r, 114, 34, "RIGHT")
    r.each = Panel.Cell(r, 152, 98, "RIGHT")
    r.total = Panel.Cell(r, 254, 98, "RIGHT")
    return r
  end)
  ui.results.sf:SetPoint("TOPLEFT", body, "TOPLEFT", x, -62)
  ui.more = Skin.Button(body, "More results", 110, 24, function()
    local ok, why = T.Click(function() return T:SearchMore() end)
    if ok then say("Asking for the next page...") else say(S.WHY[why] or tostring(why), true) end
    Panel:Refresh()
  end, "More results", "Asks for the next page of this search (one request per click).")
  ui.more:SetPoint("TOPLEFT", body, "TOPLEFT", x, -284)
  ui.hint = Panel.Note(body, S.RIGHT_W - 120, 11)
  ui.hint:SetPoint("LEFT", ui.more, "RIGHT", 8, 0)
  if ui.hint.SetWordWrap then ui.hint:SetWordWrap(false) end
end

local function refresh(body)
  local ui = S.ui
  if not ui then return end
  local cur = S.Current()
  Skin.Ellipsize(ui.pick.label, cur.name, 100)
  ui.del:SetEnabledLook(true)   -- 4J: its ⋯ menu says why Recent searches can't be deleted
  ui.addBtn:SetEnabledLook(not cur.recent)
  local busy = T:Busy()
  local last = T.results
  if last and last.purpose == "shop" then S.best[last.term:lower()] = { unit = last.lowest, t = last.t } end
  ui.next:SetEnabledLook(not busy and #cur.terms > 0)
  ui.terms:Set(cur.terms, function(r, term, i)
    r.index = i
    Panel.Put(r.name, term)
    local b = S.best[term:lower()]
    Panel.Put(r.price, b and b.unit and money(math.floor(b.unit)) or "")
    if cur.recent then r.x:Hide() else r.x:Show() end
  end)
  local res = T.results
  if res and res.purpose == "shop" then
    S.best[res.term:lower()] = { unit = res.lowest, t = res.t }      -- the price beside each searched name
    Panel.Put(ui.head, res.term)
    local rows = res.rows
    local low = res.lowest
    local ref = P.Market(rows[1] and rows[1].id)
    ui.info:SetText(low and ("Lowest %s each of %d listed%s%s"):format(money(math.floor(low)), #rows, res.more and " on this page" or "",
      ref and ("  -  your last scan: " .. money(ref)) or "") or "Nothing for sale (or only bid-only auctions).")
    ui.results:Set(rows, function(r, it)
      Panel.Put(r.name, it.name .. (it.mine and " (yours)" or ""))
      Panel.Put(r.qty, tostring(it.count))
      Panel.Put(r.each, money(math.floor(it.unit)))
      Panel.Put(r.total, it.browse and "" or money(it.buyout))
    end)
    ui.more:SetEnabledLook(res.more and not busy and true or false)
    ui.hint:SetText(res.more and "More auctions exist than shown." or "")
  else
    Panel.Put(ui.head, "Results")
    ui.info:SetText(busy and "Waiting for the auction house..." or "Click an item name to search for it.")
    ui.results:Set({}, function() end)
    ui.more:SetEnabledLook(false)
    ui.hint:SetText("")
  end
end

Panel:AddTab("shopping", "Shopping", "Shopping lists and searches. One click, one search.", build, refresh)
