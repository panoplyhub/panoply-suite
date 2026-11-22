-- Panoply Suite 0.9.0: long lists, the same way on every page (11 Nov 2026: "make it collapsible but they ALL start out as
-- collapsed, NOT opened"). Three shared pieces, so a player learns them once:
--   Skin.Sections.New(opts)   a list of collapsible sections. Several can be open at once. Every section starts closed; a closed
--                             header shows a short summary ("Ranks 1-8, 6 beasts teach it"). One level only: a section's body is a
--                             flat list, never another set of sections. What is open is kept per character in
--                             PanoplySuiteCharDB.sectionState[<page/tab>][<section>] = true (a missing value is closed).
--   Skin.FindBar(parent, S)   the bar pinned under a long tab's tabs: a search box that filters live by section and item names
--                             (items inside closed sections too) and opens the sections that match, "N of M", a clear X,
--                             "No matches for 'x'", Expand all / Collapse all, and Jump to.
--   Jump to                   a small pop-out of the section names built from plain Frames and Buttons (no UIDropDownMenu, which
--                             taints the game's own menus on Classic). A click opens that section and scrolls to it.
-- Plus Skin.KeepScroll / Skin.RecallScroll: where each tab was scrolled, for this play session, so a tab switch and back lands
-- where the player was.
-- Searching never changes what is saved: the sections a search opens close again when it is cleared, back to the saved state.
--
-- Step 20 (0.9.4): this is the kit's list of groups (Panoply.Kit.SectionList is this same piece). Its headers are drawn by UI/Kit.lua
-- (Kit.ListHeader: the one chevron header every page's section has) and, given opts.page, what is open is remembered where every
-- page's is: PanoplySuiteDB.pageState[page].open[<prefix><section>] (a value from the older per-character sectionState is read as
-- the default until the player changes it; Reset this page clears both). In combat, on a page whose content carries protected frames
-- (Kit.Holds), a click on a header, Expand all and Jump to wait for the end of the fight with a plain line (Kit.Defer).
local ADDON, Panoply = ...
local Skin = Panoply.Skin
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Sections = { LONG = 12 }
Skin.Sections = Sections

-- a tab with more items than this gets the bar and the sections ("more than about 10 to 15 items")
function Sections.IsLong(n) return (n or 0) > Sections.LONG end

local function lower(s) return tostring(s or ""):lower() end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-------------------------------------------------------------------------------
-- The saved open / closed state (per character, new key, nothing renamed)
-------------------------------------------------------------------------------
local session = {}   -- before the saved data is loaded (and in a test that has none) the state lives here
function Sections.Store(key)
  local root
  if Panoply.cdb then
    if type(Panoply.cdb.sectionState) ~= "table" then Panoply.cdb.sectionState = {} end
    root = Panoply.cdb.sectionState
  else
    root = session
  end
  if type(root[key]) ~= "table" then root[key] = {} end
  return root[key]
end

-------------------------------------------------------------------------------
-- The controller
-------------------------------------------------------------------------------
local S = {}
S.__index = S

-- opts.key: where the older per-character state was saved ("hunterpet/planner"); opts.page: the page key the state is remembered
-- under now (PanoplySuiteDB.pageState) and opts.prefix the start of each section's id there (default key .. "/"); opts.onChange(why, id):
-- the page lays itself out again; opts.guard: a function that says a change would move protected frames (besides Kit.Holds);
-- opts.noun: what an item is, for the search box ("Search beasts and zones" comes from opts.placeholder).
function Sections.New(opts)
  opts = opts or {}
  local o = setmetatable({ key = opts.key or "list", onChange = opts.onChange, placeholder = opts.placeholder, opts = opts,
    page = opts.page, prefix = opts.prefix or ((opts.key or "list") .. "/"), pending = {},
    list = {}, byId = {}, query = "", force = {}, version = 0, headers = {}, cards = {}, headerY = {} }, S)
  local K = Panoply.Kit
  if o.page and K then
    K.OnReset(o.page, function() local st = Sections.Store(o.key) for k in pairs(st) do st[k] = nil end o.pending = {} end)
    K.Mark(o.page, "SectionList")
  end
  return o
end

-- list: { { id, title, summary, items = { "searchable text of one item", ... }, body = function(card, x, y, w, match) -> y } }
-- match is nil when every item shows, else a set { [itemIndex] = true } of the items the search matched. Setting the list does not
-- count as a change (the page builds it while it lays itself out).
function S:SetList(list)
  self.list, self.byId = list or {}, {}
  for _, s in ipairs(self.list) do
    s.titleL = lower(s.title)
    s.itemsL = {}
    for i, t in ipairs(s.items or {}) do s.itemsL[i] = lower(t) end
    self.byId[s.id] = s
  end
end

function S:changed(why, id)
  self.version = self.version + 1
  if why == "query" then self.resetScroll = true end      -- a new search shows its results from the top
  if self.onChange then self.onChange(why, id) end
end

-- true once after the search changed: the page puts its list back at the top
function S:TakeReset()
  local r = self.resetScroll
  self.resetScroll = nil
  return r and true or false
end

function S:Filtering() return self.query ~= "" end

-- how many of a section's items the search matches, and which (nil = all of them)
function S:Match(s)
  local n = #(s.itemsL or {})
  if not self:Filtering() then return n, nil end
  local q = lower(self.query)
  if s.titleL:find(q, 1, true) then return max(n, 1), nil end
  local set, c = {}, 0
  for i, t in ipairs(s.itemsL) do
    if t:find(q, 1, true) then set[i] = true c = c + 1 end
  end
  return c, c > 0 and set or false
end

function S:Shown(s)
  s = type(s) == "table" and s or self.byId[s]
  if not s then return false end
  if not self:Filtering() then return true end
  return (self:Match(s)) > 0
end

function S:Saved(id)
  local legacy = Sections.Store(self.key)[id] == true
  if self.page and Panoply.Kit then return Panoply.Kit.GetOpen(self.page, self.prefix .. id, legacy) end
  return legacy
end

-- in a fight, on a page whose content carries protected frames: changes wait (see the head of this file)
function S:Locked()
  local K = Panoply.Kit
  if not (K and self.page and K.InCombat()) then return false end
  if self.opts.guard and self.opts.guard() then return true end
  return K.PageHolds(self.page)
end
-- queues fn for the end of the fight under what; the line says it plainly
function S:Wait(what, fn, line)
  Panoply.Kit.Defer(self.page .. "/" .. self.key .. "/" .. what, fn)
  Panoply:Print(line)
end

function S:IsOpen(id)
  local s = self.byId[id]
  if not s then return false end
  if self:Filtering() then
    if self.force[id] ~= nil then return self.force[id] end
    return self:Shown(s)                           -- a search opens the sections it matches
  end
  return self:Saved(id)
end

function S:SetOpen(id, open, quiet)
  if not quiet and self:Locked() then
    local sec = self.byId[id]
    local name = "The " .. ((sec and sec.title ~= "" and sec.title) or "list") .. " section"
    self.pending[id] = open and true or false
    self:Wait("open:" .. id, function() self.pending[id] = nil self:SetOpen(id, open) end,
      (open == self:IsOpen(id)) and (name .. " stays as it is.") or (name .. (open and " opens" or " closes") .. " when combat ends."))
    return
  end
  if self:Filtering() then
    self.force[id] = open and true or false        -- for this search only; what is saved stays as it was
  elseif self.page and Panoply.Kit then
    Panoply.Kit.SetOpen(self.page, self.prefix .. id, open)
  else
    Sections.Store(self.key)[id] = open and true or nil
  end
  if not quiet then self:changed("toggle", id) end
end

function S:Toggle(id)
  local now = self:IsOpen(id)
  if self.pending[id] ~= nil then now = self.pending[id] end
  self:SetOpen(id, not now)
end

function S:AllOpen()
  local any = false
  for _, s in ipairs(self.list) do
    if self:Shown(s) then
      any = true
      if not self:IsOpen(s.id) then return false end
    end
  end
  return any
end

function S:SetAll(open)
  if self:Locked() then
    self:Wait("all", function() self:SetAll(open) end, "The list " .. (open and "opens" or "closes") .. " when combat ends.")
    return
  end
  for _, s in ipairs(self.list) do
    if self:Shown(s) then self:SetOpen(s.id, open, true) end
  end
  self:changed(open and "expand" or "collapse")
end

function S:SetQuery(q)
  q = trim(q)
  if q == self.query then return end
  self.query = q
  self.force = {}
  self:changed("query")
end

-- items matched and items in all (both the whole list when there is no search)
function S:Counts()
  local n, m = 0, 0
  for _, s in ipairs(self.list) do
    local all = #(s.itemsL or {})
    m = m + all
    if self:Filtering() then n = n + (self:Match(s)) else n = n + all end
  end
  return n, m
end

-- open a section and ask the page to scroll to it; a search that hides it is cleared first
function S:JumpTo(id)
  local s = self.byId[id]
  if not s then return false end
  if self:Locked() then
    self:Wait("jump", function() self:JumpTo(id) end, "The list goes to " .. (s.title ~= "" and s.title or "that section") .. " when combat ends.")
    return true
  end
  if self:Filtering() and not self:Shown(s) then self.query = "" self.force = {} end
  self:SetOpen(id, true, true)
  self.pendingJump = id
  self:changed("jump", id)
  return true
end

-- the header's y (from the top of the frame the sections were drawn into) of the section a Jump to asked for, once
function S:TakeJump()
  local id = self.pendingJump
  self.pendingJump = nil
  return id and self.headerY[id], id
end

-------------------------------------------------------------------------------
-- Drawing the sections
-------------------------------------------------------------------------------
-- the chevron: the scroll arrow's drawing, pointing right (closed; its own file) or down (open; the up one flipped)
Skin.TEX.ScrollArrowRight = Skin.MEDIA .. "ScrollArrowRight"
local function setChevron(t, open)
  if open then
    t:SetTexture(Skin.TEX.ScrollArrow)
    t:SetTexCoord(0, 1, 1, 0)
  else
    t:SetTexture(Skin.TEX.ScrollArrowRight)
    t:SetTexCoord(0, 1, 0, 1)
  end
end
Sections.SetChevron = setChevron

-- (The code under the "if" is the header of 0.9.0 to 0.9.3, kept only as the measuring reference of tests/pages_tests.lua: it draws when
-- Kit.ListHeader is switched off, which nothing does in the add-on.)
local function header(S, parent, s, x, y, w)
  if Panoply.Kit and Panoply.Kit.ListHeader then
    local open = S:IsOpen(s.id)
    local card, b, hh = Panoply.Kit.ListHeader(parent, s.id, s.title, s.summary, open, x, y, w, function() S:Toggle(s.id) end)
    card.header = b
    return card, b, hh
  end
  local card = Skin.Card(parent)
  card.panoplyGapOK = true
  card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  card:SetSize(w, 30)
  local open = S:IsOpen(s.id)
  local b = CreateFrame("Button", nil, card)
  b:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(b)
  Skin.Round(hl, Skin.RADIUS.row, Skin.TEX.RFill)
  hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight)
  hl:Hide()
  local chev = b:CreateTexture(nil, "ARTWORK")
  chev:SetSize(12, 12)
  local g = Skin.colors.gold
  chev:SetVertexColor(g[1], g[2], g[3], 1)
  setChevron(chev, open)
  local tx, pad = 30, 8
  local tw = w - tx - 10
  local title = Skin.Text(b, 13, open and Skin.colors.heading or Skin.colors.text, nil, "semi")
  title:SetText(s.title or "")
  local sum = Skin.Text(b, 11, Skin.colors.inkSoft)
  sum:SetText(s.summary or "")
  local titleW, sumW = ceil(TW(title)) + 2, ceil(TW(sum)) + 2
  local h
  title:ClearAllPoints(); sum:ClearAllPoints()
  if (s.summary or "") == "" then
    title:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    title:SetWidth(tw)
    h = ceil(TH(title, tw)); title:SetHeight(h)
    sum:Hide()
  elseif titleW + SP.m + sumW <= tw then
    -- one line: the name on the left, the summary on the right
    title:SetWidth(titleW)
    local th = ceil(TH(title, titleW)); title:SetHeight(th)
    title:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    if sum.SetJustifyH then sum:SetJustifyH("RIGHT") end
    sum:SetWidth(sumW)
    local sh = ceil(TH(sum, sumW)); sum:SetHeight(sh)
    sum:SetPoint("TOPRIGHT", b, "TOPRIGHT", -10, -pad - max(0, floor((th - sh) / 2)))
    h = max(th, sh)
  else
    -- two lines: the name, then the summary under it
    title:SetWidth(tw)
    local th = ceil(TH(title, tw)); title:SetHeight(th)
    title:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    sum:SetWidth(tw)
    local sh = ceil(TH(sum, tw)); sum:SetHeight(sh)
    sum:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad - th - 2)
    h = th + 2 + sh
  end
  local hh = h + 2 * pad
  b:SetSize(w, hh)
  chev:SetPoint("TOPLEFT", b, "TOPLEFT", 11, -pad - max(0, floor((min(h, 18) - 12) / 2)))
  b.title, b.summary, b.chevron, b.hl = title, sum, chev, hl
  b.panoplySection, b.panoplyOpen = s.id, open
  Skin.Tooltip(b, s.title, open and "Click to close this section." or "Click to open this section.")
  b:SetScript("OnEnter", function(self) hl:Show() if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() S:Toggle(s.id) end)
  card.header = b
  return card, b, hh
end

-- draws every section that shows into parent from (x, y), each a card: the header, and under it the body when open.
-- Returns the y below the last one. With a search that matches nothing: "No matches for 'x'".
function S:Render(parent, x, y, w)
  self.headers, self.cards, self.headerY, self.empty = {}, {}, {}, nil
  local any = false
  for _, s in ipairs(self.list) do
    if self:Shown(s) then
      any = true
      local card, b, hh = header(self, parent, s, x, y, w)
      self.headers[s.id], self.cards[s.id], self.headerY[s.id] = b, card, y
      local ch = hh
      if self:IsOpen(s.id) and s.body then
        local _, match = self:Match(s)
        local yy = s.body(card, 12, -hh - 2, w - 24, match or nil)
        ch = ceil(-yy + 10)
      end
      card:SetHeight(ch)
      y = y - ch - SP.s
    end
  end
  if not any and self:Filtering() then
    local fs = Skin.Text(parent, 12, Skin.colors.inkSoft)
    fs:SetText(("No matches for '%s'"):format(self.query))
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 4)
    fs:SetWidth(w - 8)
    local h = ceil(TH(fs, w - 8))
    fs:SetHeight(h)
    self.empty = fs
    y = y - 4 - h - SP.s
  end
  return y
end

-------------------------------------------------------------------------------
-- Jump to: a pop-out of the section names (plain Frames and Buttons)
-------------------------------------------------------------------------------
local Jump = {}
Sections.Jump = Jump
Jump.ROW_H, Jump.MAX_H, Jump.W = 22, 320, 230

function Jump:Frame()
  local f = self.frame
  if f then return f end
  f = CreateFrame("Frame", "PanoplySuiteJumpList", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  Skin.Panel(f, 1, nil, "M")
  f:EnableMouse(true)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f.head = Skin.Label(f, 10, Skin.colors.inkSoft)
  f.head:SetText("JUMP TO")
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  f.area = Skin.ScrollArea(f)
  f.rows = {}
  f:Hide()
  Skin.Popups:Adopt(f, { close = function() Jump:Hide() end })
  self.frame = f
  return f
end

function Jump:Hide() if self.frame then self.frame:Hide() self.frame.owner = nil end end

-- show the names of S's sections under owner (a second click on the same owner closes it)
function Jump:Toggle(owner, S)
  local f = self:Frame()
  if Skin.Popups:Reopening(f, owner) then return nil end
  if f:IsShown() and f.owner == owner then self:Hide() return nil end
  if f:IsShown() then f:Hide() end       -- open for another button: closed there first
  return self:Show(owner, S)
end

function Jump:Show(owner, S)
  local f = self:Frame()
  f.owner, f.S = owner, S
  local w = self.W
  local headH = ceil(TH(f.head, w - 24)) + SP.xs
  f.head:SetWidth(w - 24); f.head:SetHeight(headH - SP.xs)
  local c = f.area.content
  for _, r in ipairs(f.rows) do r:Hide() end
  local y, rw = 0, w - 24 - 12
  for i, s in ipairs(S.list) do
    local r = f.rows[i]
    if not r then
      r = CreateFrame("Button", nil, c)
      r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(r); Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
      r.hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight); r.hl:Hide()
      r.text = Skin.Text(r, 12)
      r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -4)
      if r.text.SetWordWrap then r.text:SetWordWrap(false) end
      r:SetScript("OnEnter", function(self) self.hl:Show() end)
      r:SetScript("OnLeave", function(self) self.hl:Hide() end)
      r:SetScript("OnClick", function(self)
        local SS, id = f.S, self.panoplySection
        Jump:Hide()
        if SS then SS:JumpTo(id) end
      end)
      f.rows[i] = r
    end
    r.panoplySection = s.id
    local fs = r.text
    fs:SetWidth(rw - 12)
    Skin.Ellipsize(fs, s.title or "", rw - 12)
    local th = ceil(TH(fs, rw - 12))
    fs:SetHeight(th)
    local rh = max(self.ROW_H, th + 8)
    r:SetSize(rw, rh)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    local dim = S:Filtering() and not S:Shown(s)
    local col = dim and Skin.colors.dim or Skin.colors.text
    fs:SetTextColor(col[1], col[2], col[3], 1)
    r:Show()
    y = y - rh
  end
  local listH = -y
  local viewH = min(listH, self.MAX_H)
  f:SetSize(w, headH + viewH + 10 + 10)
  f.area:ClearAllPoints()
  f.area:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10 - headH)
  f.area:SetSize(w - 24, viewH)
  f.area.content:SetWidth(w - 24)
  f.area:SetContentHeight(listH)
  f.area:ScrollTo(0)
  f:ClearAllPoints()
  -- under the owner, right edges together (the button sits at the right of the bar); above it when there is no room below
  local flipY
  local ui = _G.UIParent
  if owner and owner.GetBottom then
    local ob = owner:GetBottom()
    local es = ((owner.GetEffectiveScale and owner:GetEffectiveScale()) or 1) / ((ui and ui.GetEffectiveScale and ui:GetEffectiveScale()) or 1)
    if ob and ob * es - 4 - f:GetHeight() < 0 then flipY = true end
  end
  if owner then
    f:SetPoint(flipY and "BOTTOMRIGHT" or "TOPRIGHT", owner, flipY and "TOPRIGHT" or "BOTTOMRIGHT", 0, flipY and 4 or -4)
  else
    f:SetPoint("CENTER", UIParent, "CENTER")
  end
  f:Show()
  return f
end

-------------------------------------------------------------------------------
-- The bar under the tabs
-------------------------------------------------------------------------------
Sections.BAR_H = 26

-- builds the bar for S into parent; bar:Layout(w) places its parts in width w and returns its height; bar:Sync() brings the
-- count, the clear X, the Expand / Collapse label and the box's text up to date (the page calls it after each change).
function Skin.FindBar(parent, S, opts)
  opts = opts or {}
  local bar = CreateFrame("Frame", nil, parent)
  bar.S = S
  bar:SetHeight(Sections.BAR_H)
  local box = Skin.Input(bar, 200, 24, opts.placeholder or S.placeholder or "Search")
  bar.search = box
  box:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t == "" then self.placeholder:Show() else self.placeholder:Hide() end
    if not bar.syncing then S:SetQuery(t) end
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  Skin.Tooltip(box, opts.placeholder or S.placeholder or "Search", "Type to show only what matches. The sections that match open by themselves.")
  box:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  box:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  -- the clear X and "N of M" sit inside the box's right end while a search is on (the typed text stops before them)
  bar.clear = Skin.IconButton(box, "x", 18, function() bar:Clear() end, "Clear the search", "Shows the whole list again, as you left it.")
  bar.count = Skin.Text(box, 11, Skin.colors.inkSoft)
  if bar.count.SetWordWrap then bar.count:SetWordWrap(false) end
  if bar.count.SetJustifyH then bar.count:SetJustifyH("RIGHT") end
  bar.toggle = Skin.Button(bar, "Expand all", 96, 24, function() S:SetAll(not S:AllOpen()) end, "Expand all / Collapse all",
    "Opens every section, or closes them all again.")
  bar.jump = Skin.Button(bar, "Jump to", 80, 24, function(b) Jump:Toggle(b, S) end, "Jump to",
    "Every section by name: click one to open it and go straight to it.")
  bar:SetScript("OnHide", function() if Jump.frame and Jump.frame.owner == bar.jump then Jump:Hide() end end)

  function bar:Clear()
    self.syncing = true
    box:SetText("")
    box.placeholder:Show()
    self.syncing = nil
    if box.ClearFocus then box:ClearFocus() end
    S:SetQuery("")
  end

  -- the count's size: the widest "N of M" this list can show, so the box does not jump about while typing (measured with that
  -- text in it, never while it is empty)
  local function countSize()
    local _, m = S:Counts()
    local was = bar.count:GetText()
    bar.count:SetText(("%d of %d"):format(m, m))
    local w = ceil(TW(bar.count)) + 4
    local h = ceil(TH(bar.count, w))
    bar.count:SetText(was or "")
    return w, h
  end

  function bar:Sync()
    self.syncing = true
    if (box:GetText() or "") ~= S.query then box:SetText(S.query) end
    if S.query == "" then box.placeholder:Show() else box.placeholder:Hide() end
    self.syncing = nil
    if S:Filtering() then
      local n, m = S:Counts()
      self.count:SetText(("%d of %d"):format(n, m)); self.count:Show()
      self.clear:Show()
      if box.SetTextInsets then box:SetTextInsets(24, 4 + 18 + SP.xs + (self.countW or 0) + SP.xs, 0, 0) end
    else
      self.count:SetText(""); self.count:Hide()
      self.clear:Hide()
      if box.SetTextInsets then box:SetTextInsets(24, 6, 0, 0) end
    end
    self.toggle.label:SetText(S:AllOpen() and "Collapse all" or "Expand all")
  end

  function bar:Layout(w)
    self:SetWidth(w)
    -- Expand all / Collapse all keeps one width (the longer label) so the bar does not shift when it changes
    local lab = self.toggle.label
    lab:SetText("Collapse all"); local tw1 = TW(lab)
    lab:SetText("Expand all"); local tw2 = TW(lab)
    local tgW = ceil(max(tw1, tw2)) + 2 * SP.m
    local jw = Skin.FitButton(self.jump, 70)
    local h = Sections.BAR_H
    self.toggle:SetSize(tgW, 24)
    self.jump:SetHeight(24)
    self.jump:ClearAllPoints(); self.jump:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -1)
    self.toggle:ClearAllPoints(); self.toggle:SetPoint("TOPRIGHT", self.jump, "TOPLEFT", -SP.s, 0)
    local cw, ch = countSize()
    self.countW = cw
    self.count:SetWidth(cw)
    self.count:SetHeight(ch)
    local boxW = max(120, w - jw - tgW - 2 * SP.s)
    box:SetSize(boxW, 24)
    -- the hint in the box ends inside it (shortened with "..." when the box is narrow; its tooltip has it whole)
    local hint = opts.placeholder or S.placeholder or "Search"
    box.placeholder:SetWidth(boxW - 30)
    Skin.Ellipsize(box.placeholder, hint, boxW - 30)
    if box.placeholder.SetWordWrap then box.placeholder:SetWordWrap(false) end
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -1)
    self.clear:ClearAllPoints(); self.clear:SetPoint("RIGHT", box, "RIGHT", -3, 0)
    self.count:ClearAllPoints(); self.count:SetPoint("RIGHT", box, "RIGHT", -(3 + 18 + SP.xs), 0)
    self:SetHeight(h)
    self:Sync()
    return h
  end
  return bar
end

-------------------------------------------------------------------------------
-- Where each tab was scrolled (this play session)
-------------------------------------------------------------------------------
Skin.scrollMemo = Skin.scrollMemo or {}
function Skin.KeepScroll(key, area)
  if key and area and area.GetVerticalScroll then Skin.scrollMemo[key] = area:GetVerticalScroll() or 0 end
end
function Skin.RecallScroll(key, area)
  if not (key and area) then return 0 end
  local v = Skin.scrollMemo[key] or 0
  if area.ScrollTo then return area:ScrollTo(v) end
  if area.SetVerticalScroll then area:SetVerticalScroll(min(v, area.MaxScroll and area:MaxScroll() or v)) end
  return v
end

-------------------------------------------------------------------------------
-- A row of tabs that never wraps (one row of 2 to 5 short tabs, no second row, no overflow arrows, no "More" menu)
-------------------------------------------------------------------------------
-- list: the tab buttons (Skin.Button or Skin.Tab), placed left to right from (x, y) under parent's top left. Each is as wide as its
-- label; when they do not all fit in maxW, the tabs that have a short name (b.panoplyShortLabel, e.g. "Spells" for "Spells & Talents")
-- use it; when they still do not fit, each gets the same share and its label is shortened to fit (its tooltip keeps the whole
-- name). A caller that changes a label sets b.panoplyFullLabel to the whole text. Returns the row's height; b.panoplyShort is true on a tab
-- that shows its short name.
function Skin.TabRow(parent, list, x, y, maxW, gap, minW)
  gap = gap or SP.s
  local shown = {}
  for _, b in ipairs(list) do if b:IsShown() then shown[#shown + 1] = b end end
  local n = #shown
  if n == 0 then return 0 end
  local need, total, h = {}, 0, 0
  local function measure(short)
    total = (n - 1) * gap
    for i, b in ipairs(shown) do
      b.panoplyShort = short and b.panoplyShortLabel ~= nil or false
      b.label:SetText(b.panoplyShort and b.panoplyShortLabel or b.panoplyFullLabel)
      need[i] = math.max(minW or 60, ceil(TW(b.label) + 2 * SP.m + ((b.icon and b.icon.IsShown and b.icon:IsShown()) and 24 or 0)))
      total = total + need[i]
    end
  end
  for _, b in ipairs(shown) do
    b.panoplyFullLabel = b.panoplyFullLabel or b.label:GetText()
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    h = math.max(h, b:GetHeight() or 24)
  end
  measure(false)
  if total > maxW then measure(true) end
  if total > maxW then
    local each = floor((maxW - (n - 1) * gap) / n)
    for i, b in ipairs(shown) do
      need[i] = each
      Skin.Ellipsize(b.label, b.panoplyShort and b.panoplyShortLabel or b.panoplyFullLabel, each - 2 * SP.s)
    end
  end
  local cx = x
  for i, b in ipairs(shown) do
    b:SetWidth(need[i])
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y)
    cx = cx + need[i] + gap
  end
  return h
end
