-- Panoply Suite one-window menu: the left list of pages (open a page, Edit pages: drag, hide, reset),
-- and "All settings", the one search box that finds any setting and jumps to it.
local ADDON, Panoply = ...
local Menu = Panoply.Menu
local Skin, Cat = Panoply.Skin, Panoply.Catalog
local SP = Skin.SP

local ROW_W, ROW_H, ROW_GAP = 188, 34, 4
-- 0.8.4: the list grew (Class Guide, At your level, Miscellaneous, Forever Legacy) past what the window holds at the full row height.
-- When the rows would run under the buttons at the bottom, they get shorter (never under MIN_ROW_H) and closer; the window stays its size.
local MIN_ROW_H, MIN_ROW_GAP = 26, 2

-------------------------------------------------------------------------------
-- The left list
-------------------------------------------------------------------------------
local function makeRow(list, page)
  local row = Skin.Tab(list, page.label, ROW_W, function() Menu:RowClick(page.key) end, page.label, page.help or page.text, page.icon, true)
  row:SetHeight(ROW_H)
  row.page = page
  row.label:ClearAllPoints(); row.label:SetPoint("LEFT", row, "LEFT", 36, 0)
  if row.label.SetJustifyH then row.label:SetJustifyH("LEFT") end
  if row.icon then row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", row, "LEFT", 10, 0) end
  row.tag = Skin.Text(row, 10, Skin.colors.dim)
  row.tag:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  if row.tag.SetJustifyH then row.tag:SetJustifyH("RIGHT") end
  if row.tag.SetWordWrap then row.tag:SetWordWrap(false) end
  -- 0.9.5 phase 4A3 (spec 05 section 2): a small dot while the page has something that needs you (an "act" alert of the shared
  -- registry, Core/Alerts.lua). It used to mark the pages that come and go; those are simply in the list while they are useful.
  row.dot = row:CreateTexture(nil, "OVERLAY")
  row.dot:SetTexture(Skin.TEX.CircleMask); row.dot:SetSize(8, 8)
  row.dot:SetVertexColor(Skin.colors.warn[1], Skin.colors.warn[2], Skin.colors.warn[3], 1)
  row.dot:SetPoint("RIGHT", row, "RIGHT", -14, 0)
  row.dot:Hide()
  row.grip = Skin.Grip(row)
  row.grip:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.eye = Skin.IconButton(row, "Eye", 22, function() Menu:SetHidden(page.key, not Menu:IsHidden(page.key)) end,
    "Hide or show this page", "A hidden page waits under Hidden. Search and /panoply still reach it.")
  row.eye:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnDragStart", function() if Menu.editing then Menu:StartDrag(page.key) end end)
  row:SetScript("OnDragStop", function() Menu:StopDrag() end)
  return row
end

function Menu:BuildList(list)
  self.rows = {}
  -- 0.9.5 phase 4A3: the rows and the section labels sit in a scroll area above the buttons. They get shorter first (down to
  -- MIN_ROW_H); when even that does not fit (the smallest window, many pages, large text) the list scrolls, like a page does.
  local sc = Skin.ScrollArea(list)
  sc:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  sc:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 28 + SP.s)
  self.listScroll = sc
  local holder = sc.content
  holder:SetWidth(ROW_W)
  self.listHolder = holder
  for _, page in ipairs(Cat.PAGES) do self.rows[page.key] = makeRow(holder, page) end
  local edge = list:CreateTexture(nil, "ARTWORK")
  Skin.Solid(edge, Skin.colors.hairline, 1)
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT", list, "TOPRIGHT", 5, 0); edge:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 5, 0)
  self.hiddenLabel = Skin.Label(holder, 9, Skin.colors.inkSoft); self.hiddenLabel:SetText("HIDDEN")
  -- 0.9.5 phase 4A3: the section labels (spec 05 section 1), in the same muted small capitals as HIDDEN
  self.secLabels = {}
  for _, sec in ipairs(Cat.NAV_SECTIONS) do
    local l = Skin.Label(holder, 9, Skin.colors.inkSoft)
    l:SetText(sec.label:upper())
    self.secLabels[sec.key] = l
  end
  self.dropLine = holder:CreateTexture(nil, "OVERLAY")
  Skin.Solid(self.dropLine, Skin.colors.accent, 1)
  self.dropLine:SetHeight(3); self.dropLine:SetWidth(ROW_W - 12); self.dropLine:Hide()
  self.editBtn = Skin.Button(list, "Edit pages", ROW_W, 28, function() Menu:BeginEdit() end, "Edit pages", Cat.UI_HELP.editPages)
  self.resetBtn = Skin.Button(list, "Reset order", ROW_W, 28, function() Menu:ResetOrder() end, "Reset order",
    "Back to the order Panoply Suite ships the pages in, with none hidden.")
  self.doneBtn = Skin.Button(list, "Done", ROW_W, 28, function() Menu:EndEdit() end, "Done", "Leave Edit pages.")
  self.doneBtn.panoplyAccent = true
  self.listButtons = { self.editBtn, self.resetBtn, self.doneBtn }
  -- 0.9.5 r095: the buttons sit above the list's rows (scroll area, its content, the row: three levels down), so a row scrolled
  -- under them (the smallest window) never takes their click
  if list.GetFrameLevel then
    for _, b in ipairs(self.listButtons) do if b.SetFrameLevel then b:SetFrameLevel(list:GetFrameLevel() + 8) end end
  end
end

-- the small word at the right of a row: Soon, or Off while the page's feature is off
function Menu:Tag(page)
  if page.soon then return "Soon" end
  local on = self:SwitchState(page)
  if on == false then return "Off" end
  return ""
end

-- the height of a row and the gap under it for this many rows: the full size when they fit above the buttons, else as tall as fits
-- (extra = what the HIDDEN label takes in Edit pages; buttonsH = the buttons at the bottom of the list)
function Menu:ListPitch(nRows, extra, buttonsH)
  local avail = (self.H - (self.hb or 50) - 18) - 2 - (extra or 0) - (buttonsH or 0) - SP.s
  if nRows < 1 or nRows * (ROW_H + ROW_GAP) - ROW_GAP <= avail then return ROW_H, ROW_GAP end
  local h = math.floor((avail + MIN_ROW_GAP) / nRows) - MIN_ROW_GAP
  return math.max(MIN_ROW_H, math.min(ROW_H, h)), MIN_ROW_GAP
end

-- the height a section label takes in the list, with the gap above it (none above the first)
function Menu:SectionLabelH(first)
  local l = self.secLabels and select(2, next(self.secLabels))
  local h = l and Skin.TextHeight(l) or 11
  return (first and 0 or SP.s) + h + SP.xs
end

function Menu:LayoutList()
  local list = self.list
  if not list then return end
  local frame = list
  list = self.listHolder or list
  for _, row in pairs(self.rows) do row:Hide() end
  self.hiddenLabel:Hide(); self.dropLine:Hide()
  for _, l in pairs(self.secLabels or {}) do l:Hide() end
  local editing = self.editing
  local vis = self:PageList(false)
  local hid = {}
  if editing then
    for _, p in ipairs(self:PageList(true)) do if self:IsHidden(p.key) and not p.soon then hid[#hid + 1] = p end end
  end
  -- the sections that show a label: those with a page in the list; in Edit pages all four, so a page can be dragged into an empty one
  local bySec, secs = {}, {}
  for _, p in ipairs(vis) do
    local k = self:SectionOf(p.key)
    if not bySec[k] then bySec[k] = {} end
    table.insert(bySec[k], p)
  end
  for _, sec in ipairs(Cat.NAV_SECTIONS) do
    if editing or bySec[sec.key] then secs[#secs + 1] = sec end
  end
  local labelsH = 0
  for i = 1, #secs do labelsH = labelsH + self:SectionLabelH(i == 1) end
  local labelH = #hid > 0 and (SP.xs + Skin.TextHeight(self.hiddenLabel) + SP.s) or 0
  local rowH, rowGap = self:ListPitch(#vis + #hid, labelH + labelsH, editing and (28 + SP.s + 28) or 28)
  self.rowH, self.rowGap = rowH, rowGap
  local A = Panoply.Alerts
  local y = -2
  -- where a dragged page can land: one slot per row of the list (not the hidden ones) and, in Edit pages, one per section label
  self.slots = {}
  local function place(page, hidden)
    local row = self.rows[page.key]
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
    row:SetWidth(ROW_W)
    row:SetHeight(rowH)
    row.panoplyY = y
    row.panoplyHidden = hidden
    -- a row: icon + name, a tag at the right; in Edit pages a grip and an eye
    local tag = editing and (page.soon and "Soon" or "") or self:Tag(page)
    row.tag:SetText(tag)
    local tw = tag ~= "" and (math.ceil(Skin.TextWidth(row.tag)) + 4) or 0
    row.tag:SetWidth(math.max(1, tw))
    local left = editing and 46 or 36
    row.label:ClearAllPoints(); row.label:SetPoint("LEFT", row, "LEFT", left, 0)
    if row.icon then row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", row, "LEFT", editing and 22 or 10, 0) end
    local dot = not editing and tw == 0 and A ~= nil and A:PageHasAct(page.key)
    local right = (editing and not page.soon) and 34 or (tw > 0 and tw + 14 or (dot and 26 or 8))
    local lw = ROW_W - left - right
    row.label:SetWidth(lw)
    Skin.Ellipsize(row.label, page.label, lw)
    if editing then row.grip:Show() else row.grip:Hide() end
    if editing and not page.soon then row.eye:Show() row.eye:SetDimmed(hidden and true or false) else row.eye:Hide() end
    if tw > 0 then row.tag:Show() else row.tag:Hide() end
    if dot then row.dot:Show() else row.dot:Hide() end
    row:SetActive(not editing and Menu.current and (Menu.pageDef and (Menu.pageDef.parent or Menu.pageDef.key) == page.key) or (editing and self.picked == page.key) or false)
    row:Show()
    if not hidden then self.slots[#self.slots + 1] = { y = y, h = rowH, key = page.key, section = self:SectionOf(page.key) } end
    y = y - rowH - rowGap
  end
  for i, sec in ipairs(secs) do
    local l = self.secLabels[sec.key]
    if i > 1 then y = y - SP.s end
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
    l:Show()
    local lh = Skin.TextHeight(l)
    if editing then self.slots[#self.slots + 1] = { y = y, h = lh, section = sec.key, label = true } end
    y = y - lh - SP.xs
    for _, page in ipairs(bySec[sec.key] or {}) do place(page, false) end
  end
  if #hid > 0 then
    y = y - SP.xs
    self.hiddenLabel:ClearAllPoints(); self.hiddenLabel:SetPoint("TOPLEFT", list, "TOPLEFT", 6, y)
    self.hiddenLabel:Show()
    y = y - Skin.TextHeight(self.hiddenLabel) - SP.s
    for _, p in ipairs(hid) do place(p, true) end
  end
  self.listBottom = y
  -- buttons at the bottom, under the scroll area
  self.editBtn:Hide(); self.resetBtn:Hide(); self.doneBtn:Hide()
  local buttonsH
  if editing then
    self.doneBtn:ClearAllPoints(); self.doneBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); self.doneBtn:Show()
    self.resetBtn:ClearAllPoints(); self.resetBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 28 + SP.s); self.resetBtn:Show()
    buttonsH = 28 + SP.s + 28
  else
    self.editBtn:ClearAllPoints(); self.editBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); self.editBtn:Show()
    buttonsH = 28
  end
  local sc = self.listScroll
  if sc then
    sc:ClearAllPoints()
    sc:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    sc:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, buttonsH + SP.s)
    -- the size as well as the two corners (as the page area does): what the list's room is, from the window's height
    sc:SetSize(self.LIST_W, math.max(10, (self.H - (self.hb or 50) - 18) - buttonsH - SP.s))
    sc:SetContentHeight(math.max(0, -y - rowGap))   -- the gap after the last row is not content
  end
end

function Menu:RefreshList() self:LayoutList() end

function Menu:RowClick(key)
  if self.editing then
    self.picked = key
    self:LayoutList()
    if self.frame.EnableKeyboard then self.frame:EnableKeyboard(true) end
    return
  end
  -- 0.9.5: a click on the list is a plain move for the history (no return chip on the page it opens)
  if Panoply.History then Panoply.History:Via("nav") end
  self:Select(key)
end

-------------------------------------------------------------------------------
-- Edit pages
-------------------------------------------------------------------------------
function Menu:BuildEditCard()
  if self.editCard then return self.editCard end
  local c = Skin.Card(self.area)
  c:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, 0); c:SetPoint("TOPRIGHT", self.host, "TOPRIGHT", 0, 0)
  c.head = Skin.Heading(c, 17, "Arrange your pages")
  c.lines = {}
  for _, t in ipairs({
    "Drag a page up or down. Put the ones you use most at the top.",
    "Or click a page, then press Alt + Up or Alt + Down to move it.",
    "The eye hides a page. Hidden pages wait under Hidden, and the eye brings them back.",
    "Reset order puts the pages back the way Panoply Suite ships them.",
  }) do c.lines[#c.lines + 1] = Skin.Ink(c, 13) c.lines[#c.lines]:SetText(t) end
  c.note = Skin.Ink(c, 12, Skin.colors.inkSoft)
  c.note:SetText("Your order is remembered for every character on this account. A hidden page is not gone: the All settings box and /panoply still reach it.")
  function c:Layout()
    local w = Menu.hostW - 40
    local y = -16
    self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 20, y); self.head:SetWidth(w)
    y = y - Skin.TextHeight(self.head, w) - SP.m
    for _, l in ipairs(self.lines) do
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", self, "TOPLEFT", 20, y); l:SetWidth(w)
      y = y - Skin.TextHeight(l, w) - SP.m
    end
    y = y - SP.m
    self.note:ClearAllPoints(); self.note:SetPoint("TOPLEFT", self, "TOPLEFT", 20, y); self.note:SetWidth(w)
    y = y - Skin.TextHeight(self.note, w) - SP.l
    self:SetHeight(-y)
  end
  c:Hide()
  self.editCard = c
  return c
end

function Menu:BeginEdit()
  if self.editing then return end
  self:Create()
  if self:HostLocked() then
    -- the page showing carries secure buttons and it is a fight: it cannot be put away, so Edit pages starts when the fight ends
    Panoply.Kit.Defer("menu/edit", function() Menu:BeginEdit() end)
    Panoply:Print("Edit pages starts when combat ends.")
    return
  end
  if not self.pageDef then self:Select() end
  if Panoply.PageSettings and Panoply.PageSettings.open then Panoply.PageSettings:Close(true) end
  self:CloseResults(true)
  self.editing = true
  self.picked = self.picked or (self.pageDef and (self.pageDef.parent or self.pageDef.key))
  for n, p in pairs(self.pages) do p:Hide() if p.panoplyArea then p.panoplyArea:Hide() end end
  local c = self:BuildEditCard()
  c:Layout(); c:Show()
  self:LayoutList()
  if not self.keyHooked then
    self.keyHooked = true
    self.frame:SetScript("OnKeyDown", function(f, key)
      if Menu.editing and Menu.picked and (key == "UP" or key == "DOWN") and _G.IsAltKeyDown and IsAltKeyDown() then
        if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
        Menu:MovePage(Menu.picked, key == "UP" and -1 or 1)
      elseif f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
    end)
  end
  if self.frame.EnableKeyboard then self.frame:EnableKeyboard(true) end
end

function Menu:EndEdit()
  if not self.editing then return end
  self.editing = false
  self.picked = nil
  self:StopDrag()
  if self.editCard then self.editCard:Hide() end
  if self.frame.EnableKeyboard then self.frame:EnableKeyboard(false) end
  if self.pageDef then self:ShowBody(self.pageDef.body) end
  self:LayoutList()
  self:RefreshCurrent()
end

-- dragging: the row follows nothing visible; a brass line shows where it will land
function Menu:StartDrag(key)
  if not (_G.GetCursorPosition and self.editing) then return end
  self.dragKey = key
  self.picked = key
  self.frame:SetScript("OnUpdate", function() Menu:DragStep() end)
end

-- 0.9.5: the slot under the pointer (a row, or a section label in Edit pages; Menu:LayoutList records them), the nearest by its middle
function Menu:DragIndex()
  local list = self.list
  local _, cy = GetCursorPosition()
  local scale = (list.GetEffectiveScale and list:GetEffectiveScale()) or 1
  local top = list.GetTop and list:GetTop()
  if not (cy and top) or not self.slots or #self.slots == 0 then return nil end
  local sc = self.listScroll
  local off = (sc and sc.GetVerticalScroll and sc:GetVerticalScroll()) or 0
  local rel = -(top + off - cy / scale)      -- the pointer in the rows' own y (0 at their top, negative below), the scroll counted
  local best, bestD
  for i, sl in ipairs(self.slots) do
    local d = math.abs((sl.y - sl.h / 2) - rel)
    if not bestD or d < bestD then best, bestD = i, d end
  end
  return best
end

function Menu:DragStep()
  local idx = self:DragIndex()
  if not idx then return end
  self.dragTo = idx
  local sl = self.slots[idx]
  -- the line: above the row it lands on, or under the label of the section it goes to the top of
  local y = sl.label and (sl.y - sl.h - 1) or (sl.y + 2)
  self.dropLine:ClearAllPoints(); self.dropLine:SetPoint("TOPLEFT", self.listHolder or self.list, "TOPLEFT", 6, y); self.dropLine:Show()
end

function Menu:StopDrag()
  if not self.dragKey then return end
  local key, to = self.dragKey, self.dragTo
  self.dragKey, self.dragTo = nil, nil
  self.frame:SetScript("OnUpdate", nil)
  self.dropLine:Hide()
  local sl = to and self.slots and self.slots[to]
  if sl then
    if sl.label then
      -- onto a section's label: the top of that section
      self:SetSection(key, sl.section)
      local order = self:FullOrder()
      for i, k in ipairs(order) do if k == key then table.remove(order, i) break end end
      local pos
      for i, k in ipairs(order) do if not pos and self:SectionOf(k) == sl.section then pos = i end end
      if not pos then
        -- an empty section: after the pages of the sections before it
        local si = self:SectionIndex(sl.section)
        pos = 1
        for i, k in ipairs(order) do if self:SectionIndex(self:SectionOf(k)) < si then pos = i + 1 end end
      end
      table.insert(order, pos, key)
      self:Saved().order = order
    elseif sl.key ~= key then
      -- onto a page: its place, in its section
      self:SetSection(key, sl.section)
      local order = self:FullOrder()
      local at, mine
      for i, k in ipairs(order) do if k == sl.key then at = i elseif k == key then mine = i end end
      -- above the row it lands on: coming from above, the row moves up one place once the page is taken out
      if at and mine and mine < at then at = at - 1 end
      if at then self:MovePage(key, 0, at) end
    end
  end
  self:LayoutList()
end

-------------------------------------------------------------------------------
-- All settings: the search box and its results
-------------------------------------------------------------------------------
local RES_MAX, RES_ROW = 9, 44

function Menu:BuildSearch(box)
  box:SetScript("OnTextChanged", function(b)
    local t = b:GetText() or ""
    if b.placeholder then if t == "" then b.placeholder:Show() else b.placeholder:Hide() end end
    Menu:ShowResults(t)
  end)
  box:SetScript("OnEnterPressed", function(b) Menu:ActivateResult(Menu.sel or 1) end)
  box:SetScript("OnEscapePressed", function(b)
    if (b:GetText() or "") ~= "" then Menu:SetBoxText("") end
    b:ClearFocus()
    Menu:CloseResults()
  end)
  box:SetScript("OnArrowPressed", function(b, key)
    if not (Menu.shown and #Menu.shown > 0) then return end
    local n = #Menu.shown
    Menu.sel = math.max(1, math.min(n, (Menu.sel or 1) + (key == "DOWN" and 1 or -1)))
    Menu:PaintResults()
  end)
end

local function mark(label, toks)
  local low = label:lower()
  local spans = {}
  for _, t in ipairs(toks) do
    local a, b = low:find(t, 1, true)
    if a then spans[#spans + 1] = { a, b } end
  end
  table.sort(spans, function(x, y) return x[1] < y[1] end)
  local out, pos = {}, 1
  for _, s in ipairs(spans) do
    if s[1] >= pos then
      out[#out + 1] = label:sub(pos, s[1] - 1)
      out[#out + 1] = Skin.Code(Skin.colors.highlight) .. label:sub(s[1], s[2]) .. "|r"
      pos = s[2] + 1
    end
  end
  out[#out + 1] = label:sub(pos)
  return table.concat(out)
end

function Menu:BuildResults()
  if self.results then return self.results end
  local f = Skin.Card(self.area)
  f:SetPoint("TOPLEFT", self.area, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", self.area, "TOPRIGHT", 0, 0)
  f:SetFrameStrata("DIALOG")
  f.head = Skin.Text(f, 12, Skin.colors.text)
  f.hint = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.foot = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.rows = {}
  f:Hide()
  self.results = f
  return f
end

local function resultRow(f, i)
  local r = f.rows[i]
  if r then return r end
  local b = Skin.Button(f, "", 100, RES_ROW, function() Menu:ActivateResult(i) end)
  b.label:Hide()
  b.path = Skin.Label(b, 9, Skin.colors.accent)
  b.name = Skin.Text(b, 13, Skin.colors.text)
  b.state = Skin.Name(b, 12, Skin.colors.done)
  b.chev = Skin.Name(b, 14, Skin.colors.goldBright); b.chev:SetText(">")
  for _, fs in ipairs({ b.path, b.name, b.state, b.chev }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  f.rows[i] = b
  return b
end

function Menu:ShowResults(text)
  text = tostring(text or "")
  if #text:gsub("%s", "") < 2 then self:CloseResults() return end
  if self:HostLocked() then
    -- the page showing carries secure buttons and it is a fight: the results take its place when it ends
    Panoply.Kit.Defer("menu/results", function() Menu:ShowResults(text) end)
    Panoply:Print("The search results open when combat ends.")
    return
  end
  if Panoply.PageSettings and Panoply.PageSettings.open then Panoply.PageSettings:Close(true) end
  if self.editing then self:EndEdit() end
  local f = self:BuildResults()
  local hits = Cat:Search(text, RES_MAX)
  self.shown, self.sel = hits, 1
  self.query = text
  self.toks = {}
  for w in text:lower():gmatch("%S+") do self.toks[#self.toks + 1] = w end
  local W = self.bodyW
  local pages, seen = 0, {}
  for _, h in ipairs(hits) do local k = h.entry.page and h.entry.page.key if k and not seen[k] then seen[k] = true pages = pages + 1 end end
  local y = -12
  f.panoplyCut = nil
  local head = #hits == 0 and ('Nothing found for "%s"'):format(text)
    or ('%d result%s for "%s", on %d page%s'):format(#hits, #hits == 1 and "" or "s", text, pages, pages == 1 and "" or "s")
  f.head:SetText(head)
  f.hint:SetText(#hits > 0 and "Enter opens the first one" or "")
  local hw = math.ceil(Skin.TextWidth(f.hint)) + 2
  f.hint:SetWidth(math.max(1, hw)); f.hint:ClearAllPoints(); f.hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y)
  local headW = W - 28 - hw - SP.m
  f.head:SetWidth(headW); f.head:ClearAllPoints(); f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
  y = y - math.max(Skin.TextHeight(f.head, headW), Skin.TextHeight(f.hint, hw)) - SP.s
  for _, r in ipairs(f.rows) do r:Hide() end
  for i, h in ipairs(hits) do
    local e = h.entry
    local b = resultRow(f, i)
    b.entry = e
    local path
    if e.kind == "setting" then path = e.page.label:upper() .. "  >  " .. e.section.title:upper() .. (e.advanced and "  >  ADVANCED" or "")
    elseif e.kind == "control" then path = e.page.label:upper() .. "  >  THIS PAGE"
    elseif e.kind == "page" then path = "PAGE"
    else path = "ACTION" end
    local state = e.kind == "setting" and Cat:State(e.row) or (e.kind == "page" and "Open" or (e.kind == "action" and "Run" or ""))
    b.state:SetText(state)
    local sw = math.ceil(Skin.TextWidth(b.state)) + 2
    local cw = 14
    local lw = W - 28 - sw - cw - 3 * SP.m
    b.path:SetText(path); b.path:SetWidth(lw)
    Skin.Ellipsize(b.path, path, lw)
    b.name:SetWidth(lw)
    Skin.Ellipsize(b.name, mark(e.label, self.toks), lw)
    b.state:SetWidth(sw); b.chev:SetWidth(cw)
    local ph, nh = Skin.TextHeight(b.path, lw), Skin.TextHeight(b.name, lw)
    local rh = math.max(RES_ROW, 6 + ph + 2 + nh + 6)
    b:SetSize(W - 20, rh)
    b.path:ClearAllPoints(); b.path:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -6)
    b.name:ClearAllPoints(); b.name:SetPoint("TOPLEFT", b.path, "BOTTOMLEFT", 0, -2)
    b.chev:ClearAllPoints(); b.chev:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    b.state:ClearAllPoints(); b.state:SetPoint("RIGHT", b.chev, "LEFT", -SP.m, 0)
    b.state:SetTextColor((state == "On" and Skin.colors.done or state == "Off" and Skin.colors.dim or Skin.colors.text)[1],
      (state == "On" and Skin.colors.done or state == "Off" and Skin.colors.dim or Skin.colors.text)[2],
      (state == "On" and Skin.colors.done or state == "Off" and Skin.colors.dim or Skin.colors.text)[3], 1)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y)
    b:Show()
    y = y - rh - 2
    -- the panel stays inside the window: rows that would not fit are left for a longer word
    if -y > self.areaH - 70 then
      b:Hide()
      y = y + rh + 2
      f.panoplyCut = (f.panoplyCut or 0) + 1
      break
    end
  end
  f.foot:SetText(#hits > 0 and "Click a result: its page opens, the gear opens, and the setting is outlined."
    or 'Try a word like "arrow", "junk", "opacity" or "partner".')
  f.foot:SetWidth(W - 28); f.foot:ClearAllPoints(); f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - SP.xs)
  y = y - SP.xs - Skin.TextHeight(f.foot, W - 28) - SP.m
  f:SetHeight(-y)
  f:Show()
  self:ShowHost(false)
  self.header:Hide()
  self:PaintResults()
end

function Menu:PaintResults()
  local f = self.results
  if not f then return end
  for i, r in ipairs(f.rows) do if r:IsShown() then r:SetSelected(i == self.sel) end end
end

function Menu:CloseResults()
  if self.results then self.results:Hide() end
  self.shown, self.sel = nil, nil
  if self.header then self.header:Show() end
  if self.host and not (Panoply.PageSettings and Panoply.PageSettings.open) and not self.editing then
    if not self:ShowHost(true) then
      Panoply.Kit.Defer("menu/host", function() Menu:ShowHost(true) end)
      Panoply:Print("The page comes back when combat ends.")
    end
  end
end

function Menu:ActivateResult(i)
  local hit = self.shown and self.shown[i]
  if not hit then return end
  local e = hit.entry
  self:SetBoxText("")
  if self.box.ClearFocus then self.box:ClearFocus() end
  self:CloseResults()
  if e.kind == "setting" then
    self:OpenGear(e.page.key, e.section.key, Cat.RowId(e.row), e.advanced)
  elseif e.kind == "action" then
    if e.run then e.run() end
  else
    self:Select(e.page.key)
  end
end

-------------------------------------------------------------------------------
-- The one-time note for an account that had the old Settings, Modules and Guide menus
-------------------------------------------------------------------------------
Menu.NOTE_TEXT = "Panoply Suite has one window now. Type a word in All settings to find any setting."

function Menu:ShowNote()
  local s = self:Saved()
  if s.noted then return false end
  s.noted = true
  local f = self.note
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteMenuNote", UIParent)
    f:SetSize(430, 110)
    f:SetPoint("TOP", UIParent, "TOP", 0, -190)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Skin.Panel(f, 1, nil, "M")
    f.head = Skin.Heading(f, 15, "One window")
    f.body = Skin.Text(f, 12)
    f.body:SetText(Menu.NOTE_TEXT)
    f.show = Skin.Button(f, "Show me", 110, 26, function() f:Hide() Menu:Search("") end, "Show me", "Opens Panoply Suite with the All settings box ready.")
    f.ok = Skin.Button(f, "Got it", 90, 26, function() f:Hide() end, "Got it", "Close this note. It does not come back.")
    f.buttons = { f.show, f.ok }
    function f:Layout()
      local w = self:GetWidth() - 36
      local y = -16
      self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 18, y); self.head:SetWidth(w)
      y = y - Skin.TextHeight(self.head, w) - SP.xs
      self.body:ClearAllPoints(); self.body:SetPoint("TOPLEFT", self, "TOPLEFT", 18, y); self.body:SetWidth(w)
      y = y - Skin.TextHeight(self.body, w) - SP.m
      local bh = Skin.FlowButtons(self, self.buttons, 18, y, w, SP.s, 80)
      y = y - bh - SP.l
      self:SetHeight(-y)
    end
    f:Hide()
    self.note = f
  end
  f:Layout()
  f:Show()
  return true
end

-- an account that already had settings (an update, not a first install) gets the note once
Panoply:On("PLAYER_LOGIN", function()
  Panoply.Compat.After(12, function()
    if Panoply.db and Panoply.existingAccount and not Panoply.Menu:Saved().noted then Panoply.Menu:ShowNote() end
  end)
end)
