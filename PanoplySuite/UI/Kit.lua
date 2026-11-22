-- Panoply Suite 0.9.4 step 20 ("One consistent menu system across the whole main window"): ONE set of UI pieces that every
-- page of the main window uses, so a player learns them once. Panoply.Kit, built on Skin's own primitives (nothing here draws a texture
-- or a font that Skin does not already draw):
--
--   Kit.PageHeader(area, opts)       the header of every page: icon, title, one line of help, and the right-hand controls slot
--                                    (the gear, the switch, an extra readout, extra controls a page registers, Small / Normal / Large)
--   Kit.Section(parent, page, id, o) a collapsible group: a card whose header has a chevron, a title and a summary slot; the body is a
--                                    frame the page puts its members in. Open or closed is remembered (Kit.State)
--   Kit.Tabs(parent, opts)           the tabs of a page that has more than one view: a row across the top (the standard: 0.9.1,
--                                    "no third menu level, only the left list plus ONE row of top tabs") or a vertical rail
--                                    (orientation = "side"); icons in both icon styles; the last tab is remembered
--   Kit.Dropdown(parent, opts)       a button that shows the choice and opens Skin.Menu under it (Skin.Popups closes it: click
--                                    outside, Esc, its button going away with its page)
--   Kit.List(parent, opts)           pooled rows: one height, hover, selection, an optional icon and a value at the right; scrolls
--                                    when it is given a height to stay within
--   Kit.TYPE / Kit.SPACE / Kit.SECTION ...   the spacing and type sizes
--
-- Memory: PanoplySuiteDB.pageState (a NEW account key, made the first time something is remembered; never a default, never in a
-- profile): { [page key] = { tab = "bank", open = { [section id] = true | false } } }. A section or tab that is not there takes the
-- page's own default. "Reset this page" (Catalog:ResetPage) clears the page's entry.
--
-- Combat (Step 20 fix round, review B1): nothing here creates, shows, hides, moves or sizes a protected frame, and the game forbids add-on
-- code those calls on a protected frame and on every frame ABOVE a protected one (a secure button makes its parents protected). So every
-- piece asks, before it changes what is drawn in a fight, whether the frame it would move holds protected frames:
--   Kit.Protected(frame)   frame:IsProtected() (true for a secure button and for a parent of one), else a look through its children
--   Kit.Holds(page, fn)    a page whose content (a holder frame) carries secure buttons says so once; fn() gives the frame or a list
--   Kit.PageLocked(page)   in combat and the page holds protected frames
-- A Section, a Tabs row, a Dropdown pick and a Skin.Sections list on a locked page (or a Section with opts.guard / its own protected
-- card) change nothing at once: the change waits for PLAYER_REGEN_ENABLED, a plain line in chat says so, and a second click before then
-- takes the first back. Laying a locked section out in a fight draws nothing again (it keeps its last place and height).
local ADDON, Panoply = ...
local Skin = Panoply.Skin
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Kit = { used = {}, resetHooks = {}, deferred = { order = {}, fn = {} } }
Panoply.Kit = Kit

-------------------------------------------------------------------------------
-- Measurements (read off the class guide, the profession page and Skin.Sections, which the kit must not change)
-------------------------------------------------------------------------------
Kit.SPACE = { xs = SP.xs, s = SP.s, m = SP.m, l = SP.l, xl = SP.xl, pad = 12 }
Kit.PAD = 12                                   -- inside a card
-- a section header: the same numbers as UI/Sections.lua (chevron at 11, text at 30, 8 above and below the text, summary at the right)
Kit.SECTION = { pad = 8, chevronX = 11, chevron = 12, textX = 30, right = 10, titleSize = 13, summarySize = 11, gap = 2, bottom = 10 }
-- the page header: UI/Menu.lua's, moved here
Kit.HEADER = { icon = 34, textX = 52, minH = 48, titleSize = 19, helpSize = 12, gear = 32, switchY = 17, rowH = 28 }
Kit.TAB = { h = 30, gap = SP.xs, minW = 80, railH = 32, railW = 168 }
Kit.ROW_H = 28                                 -- a list row, one line
Kit.TYPE = { title = 19, help = 12, label = 10, section = 13, summary = 11, body = 12, row = 12, rowSub = 11, rowBig = 15, rowBigSub = 12 }

local function inCombat() return Panoply.Compat and Panoply.Compat.InCombat and Panoply.Compat.InCombat() end
Kit.InCombat = inCombat

-- true when f, or a frame under it, is protected. The game answers for the parents of a secure button by itself (IsProtected is true for
-- them); the look through the children is for a client or a frame where it does not. At most SCAN frames are looked at.
Kit.SCAN = 600
local function scan(f, left)
  if not f.GetChildren then return false, left end
  local kids = { f:GetChildren() }
  for _, k in ipairs(kids) do
    left = left - 1
    if left <= 0 then return false, 0 end
    if k.IsProtected and k:IsProtected() then return true, left end
    local hit
    hit, left = scan(k, left)
    if hit then return true, left end
  end
  return false, left
end
function Kit.Protected(f)
  if type(f) ~= "table" then return false end
  if f.IsProtected and f:IsProtected() then return true end
  return (scan(f, Kit.SCAN))
end
-- pages that say their content holds protected frames: page key -> function giving a frame, or a list of frames
Kit.holds = {}
function Kit.Holds(page, fn) Kit.holds[page] = fn end
-- true when the frames a page declared hold protected ones, in combat or not
function Kit.PageHolds(page)
  local fn = page and Kit.holds[page]
  if not fn then return false end
  local f = fn()
  if type(f) ~= "table" then return false end
  if f.IsProtected or f.GetChildren then return Kit.Protected(f) end
  for _, x in ipairs(f) do if Kit.Protected(x) then return true end end
  return false
end
function Kit.PageLocked(page) return inCombat() and Kit.PageHolds(page) and true or false end
-- one plain line for a change that waits
local function waitLine(what, will)
  Panoply:Print(("%s %s when combat ends."):format(what, will))
end

local function mark(page, piece)
  if not page then return end
  Kit.used[page] = Kit.used[page] or {}
  Kit.used[page][piece] = (Kit.used[page][piece] or 0) + 1
end
Kit.Mark = mark

-------------------------------------------------------------------------------
-- What is remembered (PanoplySuiteDB.pageState)
-------------------------------------------------------------------------------
local session = {}      -- before the saved data is loaded (and in a test that has none)
local function root(create)
  local db = Panoply.db
  if not db then return session end
  local r = db.pageState
  if type(r) ~= "table" then
    if not create then return nil end
    r = {}
    db.pageState = r
  end
  return r
end
local function entry(page, create)
  local r = root(create)
  if not r then return nil end
  local s = r[page]
  if type(s) ~= "table" then
    if not create then return nil end
    s = {}
    r[page] = s
  end
  return s
end

-- the tab last used on a page, or nil (never saved, or not one the page has: saved data from another build)
function Kit.GetTab(page, valid)
  local s = entry(page, false)
  local t = s and s.tab
  if type(t) ~= "string" then return nil end
  if valid and not valid(t) then return nil end
  return t
end
function Kit.SetTab(page, tab)
  if type(tab) ~= "string" then return end
  local s = entry(page, false)
  if s and s.tab == tab then return end
  s = entry(page, true)
  s.tab = tab
end
-- a section's saved state: true (open), false (closed) or the page's default
function Kit.GetOpen(page, id, default)
  local s = entry(page, false)
  local o
  if s and type(s.open) == "table" then o = s.open[id] end
  if type(o) ~= "boolean" then return default end
  return o
end
function Kit.SetOpen(page, id, open)
  local s = entry(page, true)
  if type(s.open) ~= "table" then s.open = {} end
  s.open[id] = open and true or false
end
-- 0.9.5 phase 4D: forget a section's saved state (it shows its default again; a page with nothing left remembered has nothing to reset)
function Kit.ForgetOpen(page, id)
  local s = entry(page, false)
  if not (s and type(s.open) == "table") then return end
  s.open[id] = nil
  if next(s.open) == nil then s.open = nil end
end
-- true when the page has something remembered (a tab, or any section's open or closed)
function Kit.HasState(page)
  local r = root(false)
  local s = r and r[page]
  if type(s) ~= "table" then return false end
  if type(s.tab) == "string" then return true end
  if type(s.open) == "table" and next(s.open) ~= nil then return true end
  return false
end
-- Reset this page: forget the page's tab and sections (every page with no key); the pages' own hooks put their working copies back
function Kit.OnReset(page, fn)
  Kit.resetHooks[page] = Kit.resetHooks[page] or {}
  table.insert(Kit.resetHooks[page], fn)
end
function Kit.ResetState(page)
  -- in a fight, a page whose content carries protected frames (Kit.Holds) is put back when the fight ends
  if inCombat() then
    local locked = false
    if page then locked = Kit.PageHolds(page) else for k in pairs(Kit.holds) do if Kit.PageHolds(k) then locked = true end end end
    if locked then
      Kit.Defer("kit/reset/" .. tostring(page), function() Kit.ResetState(page) end)
      Panoply:Print("The page goes back as it first opens when combat ends.")
      return 0
    end
  end
  local r = root(false)
  local n = 0
  if r then
    if page then
      if r[page] ~= nil then r[page] = nil n = 1 end
    else
      for k in pairs(r) do r[k] = nil n = n + 1 end
    end
  end
  for k, list in pairs(Kit.resetHooks) do
    if not page or k == page then
      for _, fn in ipairs(list) do
        local ok, err = pcall(fn)
        if not ok then Panoply:Debug("kit reset hook", k, err) end
      end
    end
  end
  Kit.ResetShown(page)
  Kit.Redraw(page)
  return n
end
-- A page that keeps the tab it shows in a variable of its own (older code and the doors that open a page on a tab write it) tells the
-- kit how to read and write it, at load. At login the saved tab goes back into it (nothing could have asked for another tab by then);
-- from then on the variable is the truth and the kit keeps the saved tab the same (Tabs:Current); Reset this page puts the default back.
-- spec = { get = fn, set = fn(tab), default = tab, valid = fn(tab) -> bool }
Kit.vars = {}
function Kit.TabVar(page, spec)
  Kit.vars[page] = spec
  Kit.OnReset(page, function() spec.set(spec.default) end)
end
Panoply:On("PLAYER_LOGIN", function()
  for page, spec in pairs(Kit.vars) do
    local saved = Kit.GetTab(page, spec.valid)
    if saved then spec.set(saved) end
  end
end)

-- sections and tabs already drawn show their default again
function Kit.ResetShown(page)
  for _, o in ipairs(Kit.live or {}) do
    if (not page or o.page == page) and o.Apply then o:Apply() end
  end
end
Kit.live = {}

-- the page's own redraw after a section or tab changed (the window's page that is showing)
function Kit.Redraw(page)
  local M = Panoply.Menu
  if M and M.frame and M.frame:IsShown() and (page == nil or M.current == page) then M:RefreshCurrent() end
end

-- a change that waits for the end of a fight
-- (kept in the order asked; a second ask under the same key replaces the first and keeps its place)
function Kit.Defer(key, fn)
  local d = Kit.deferred
  if d.fn[key] == nil then d.order[#d.order + 1] = key end
  d.fn[key] = fn
end
Kit.dirty = {}          -- pages that laid out in a fight without moving a protected frame: drawn again when it ends
function Kit.MarkDirty(page) Kit.dirty[page or "*"] = true end
Panoply:On("PLAYER_REGEN_ENABLED", function()
  local list, dirty = Kit.deferred, Kit.dirty
  Kit.deferred, Kit.dirty = { order = {}, fn = {} }, {}
  for _, key in ipairs(list.order) do
    local ok, err = pcall(list.fn[key])
    if not ok then Panoply:Debug("kit deferred", key, err) end
  end
  for page in pairs(dirty) do Kit.Redraw(page ~= "*" and page or nil) end
end)

-------------------------------------------------------------------------------
-- The header of a section (shared with the cards of Menu.NewCard): chevron, title, summary
-------------------------------------------------------------------------------
local function setChevron(t, open)
  if Skin.Sections and Skin.Sections.SetChevron then Skin.Sections.SetChevron(t, open) end
end

local function newStrip(parent, owner)
  local b = CreateFrame("Button", nil, parent)
  local hl = b:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(b)
  Skin.Round(hl, Skin.RADIUS.row, Skin.TEX.RFill)
  hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight)
  hl:Hide()
  local chev = b:CreateTexture(nil, "ARTWORK")
  chev:SetSize(Kit.SECTION.chevron, Kit.SECTION.chevron)
  local g = Skin.colors.gold
  chev:SetVertexColor(g[1], g[2], g[3], 1)
  local title = Skin.Text(b, Kit.SECTION.titleSize, Skin.colors.text, nil, "semi")
  local sum = Skin.Text(b, Kit.SECTION.summarySize, Skin.colors.inkSoft)
  b.title, b.summary, b.chevron, b.hl = title, sum, chev, hl
  Skin.Tooltip(b, "", nil)
  b:SetScript("OnEnter", function(self) hl:Show() if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() owner:Toggle() end)
  b.panoplyKit = "SectionHeader"
  return b
end

-- lays the header out in width w from the top left of its card; returns its height. Same arithmetic as Skin.Sections' header.
local function layoutStrip(b, w, title, summary, open, x, y, indent)
  local S = Kit.SECTION
  local card = b:GetParent()
  indent = indent or 0
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", card, "TOPLEFT", x or 0, y or 0)
  setChevron(b.chevron, open)
  local tc = open and Skin.colors.heading or Skin.colors.text
  local titleFS, sum = b.title, b.summary
  titleFS:SetText(title or "")
  titleFS:SetTextColor(tc[1], tc[2], tc[3], 1)
  sum:SetText(summary or "")
  local tx, pad = S.textX + indent, S.pad
  local tw = w - tx - S.right
  local titleW, sumW = ceil(TW(titleFS)) + 2, ceil(TW(sum)) + 2
  local h
  titleFS:ClearAllPoints(); sum:ClearAllPoints()
  if (summary or "") == "" then
    titleFS:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    titleFS:SetWidth(tw)
    h = ceil(TH(titleFS, tw)); titleFS:SetHeight(h)
    sum:Hide()
  elseif titleW + SP.m + sumW <= tw then
    -- one line: the name on the left, the summary on the right
    titleFS:SetWidth(titleW)
    local th = ceil(TH(titleFS, titleW)); titleFS:SetHeight(th)
    titleFS:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    if sum.SetJustifyH then sum:SetJustifyH("RIGHT") end
    sum:SetWidth(sumW)
    local sh = ceil(TH(sum, sumW)); sum:SetHeight(sh)
    sum:SetPoint("TOPRIGHT", b, "TOPRIGHT", -S.right, -pad - max(0, floor((th - sh) / 2)))
    sum:Show()
    h = max(th, sh)
  else
    -- two lines: the name, then the summary under it
    titleFS:SetWidth(tw)
    local th = ceil(TH(titleFS, tw)); titleFS:SetHeight(th)
    titleFS:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad)
    if sum.SetJustifyH then sum:SetJustifyH("LEFT") end
    sum:SetWidth(tw)
    local sh = ceil(TH(sum, tw)); sum:SetHeight(sh)
    sum:SetPoint("TOPLEFT", b, "TOPLEFT", tx, -pad - th - 2)
    sum:Show()
    h = th + 2 + sh
  end
  local hh = h + 2 * pad
  b:SetSize(w, hh)
  b.chevron:ClearAllPoints()
  b.chevron:SetPoint("TOPLEFT", b, "TOPLEFT", S.chevronX, -pad - max(0, floor((min(h, 18) - S.chevron) / 2)))
  b.tip = title
  b.tipBody = open and "Click to close this section." or "Click to open this section."
  b.panoplyOpen = open
  return hh
end

-- 0.9.5: the strip by itself, for a piece that brings its own card (the settings panel's sections, UI/Gear.lua): Kit.Strip(card, owner)
-- makes it (owner:Toggle() is what a click does) and Kit.LayoutStrip(strip, w, title, summary, open, x, y) lays it out and returns its height
Kit.Strip, Kit.LayoutStrip = newStrip, layoutStrip

-- Skin.Sections' header (Kit.SectionList): a card holding the same chevron strip a Kit.Section has, drawn in width w at (x, y) of parent.
-- toggle() is what a click does. Returns the card, the strip and the strip's height.
function Kit.ListHeader(parent, id, title, summary, open, x, y, w, toggle)
  local card = Skin.Card(parent)
  card.panoplyGapOK = true
  card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  card:SetSize(w, 30)
  local b = newStrip(card, { Toggle = toggle })
  local hh = layoutStrip(b, w, title, summary, open, 0, 0)
  b.panoplySection = id
  return card, b, hh
end

-- a list of collapsible groups with the search bar, Expand all and Jump to (UI/Sections.lua is the code; opts.page binds it to a page)
function Kit.SectionList(opts) return Skin.Sections.New(opts) end

-------------------------------------------------------------------------------
-- Section: a collapsible group (a card: the header, and under it the body when open)
-------------------------------------------------------------------------------
local Section = {}
Section.__index = Section
Kit.SectionClass = Section

-- opts.title, opts.summary (text, or a function giving it), opts.open (the default; true when not said), opts.guard (a function
-- that says the body holds protected frames), opts.caps (the title is drawn in capitals: the class guide's), opts.onChange(section, open) (what to do after a change; the default redraws the
-- page that is showing)
function Kit.Section(parent, page, id, opts)
  opts = opts or {}
  local card = Skin.Card(parent)
  card.panoplyGapOK = true
  local s = setmetatable({ page = page, id = id, opts = opts, card = card, title = opts.title or "", summary = opts.summary }, Section)
  s.body = CreateFrame("Frame", nil, card)
  s.body.panoplyGapOK = true
  s.body:SetSize(10, 1)
  s.strip = newStrip(card, s)
  s.strip.panoplyKitOwner = s
  card.panoplyKitSection = s
  mark(page, "Section")
  Kit.live[#Kit.live + 1] = s
  return s
end

function Section:IsOpen()
  return Kit.GetOpen(self.page, self.id, self.opts.open ~= false)
end

function Section:SetTitle(t) self.title = t or "" end
function Section:SetSummary(t) self.summary = t end

local function summaryText(s)
  local t = s.summary
  if type(t) == "function" then
    local ok, v = pcall(t)
    t = ok and v or ""
  end
  return t
end

-- true while a change to this section's frames would be a protected call: in combat, and the body or the card holds protected frames
-- (found by IsProtected, see Kit.Protected), or the section says so (opts.guard: a function), or its page does (Kit.Holds: changing
-- this section moves the page's protected content)
function Section:Locked()
  if not inCombat() then return false end
  local o = self.opts
  if o.guard and o.guard() then return true end
  if Kit.PageHolds(self.page) then return true end
  return Kit.Protected(self.card)
end

-- body shown or hidden to match the saved state (only when it changed; locked in a fight: left alone, drawn again when it ends)
function Section:Apply()
  local open = self:IsOpen()
  if self.shown == open then return open end
  if self:Locked() then Kit.MarkDirty(self.page) return self.shown == true end
  self.shown = open
  if open then self.body:Show() else self.body:Hide() end
  return open
end

-- the card's header at width w (the card is placed by the caller); returns the header's height and whether the body is open
function Section:Head(w)
  if self.hh and self:Locked() then
    -- a fight, and the card holds protected frames (or moving it would move some): it keeps its last place, size and look
    Kit.MarkDirty(self.page)
    return self.hh, self.shown == true
  end
  local open = self:Apply()
  if self.shown == nil then open = self:IsOpen() end
  self.w = w
  self.card:SetWidth(w)
  -- 0.9.5 phase 4L: opts.icon(texture) draws an icon in the header, after the chevron and before the title (Help's Tips by page)
  local indent = 0
  if self.opts.icon then
    local t = self.strip.icon
    if not t then t = self.strip:CreateTexture(nil, "ARTWORK") t:SetSize(18, 18) self.strip.icon = t end
    local ok, err = pcall(self.opts.icon, t)
    if not ok then Panoply:Debug("section icon", self.id, err) end
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.strip, "TOPLEFT", Kit.SECTION.textX, -Kit.SECTION.pad + 1)
    t:Show()
    indent = 18 + SP.s
  end
  local hh = layoutStrip(self.strip, w, self.opts.caps and self.title:upper() or self.title, summaryText(self), open, 0, 0, indent)
  self.hh = hh
  self.body:ClearAllPoints()
  self.body:SetPoint("TOPLEFT", self.card, "TOPLEFT", 0, -(hh + Kit.SECTION.gap))
  self.body:SetWidth(w)
  self.card:Show()
  return hh, open
end

-- the card at (x, y) of anchor, then its header
function Section:Begin(anchor, x, y, w)
  if self.hh and self:Locked() then
    Kit.MarkDirty(self.page)
    return self.hh, self.shown == true
  end
  self.card:ClearAllPoints()
  self.card:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
  return self:Head(w)
end

-- the content is contentH tall (what the page laid out in the body); returns the whole card's height
function Section:Done(contentH)
  if self.cardH and self:Locked() then Kit.MarkDirty(self.page) return self.cardH end
  local open = self.shown
  if open == nil then open = self:IsOpen() end
  local h = self.hh or 0
  if open then
    contentH = max(0, ceil(contentH or 0))
    self.body:SetHeight(max(1, contentH))
    h = h + Kit.SECTION.gap + contentH + Kit.SECTION.bottom
  end
  self.card:SetHeight(h)
  self.cardH = h
  return h
end

function Section:Hide() if self.card:IsShown() and not self:Locked() then self.card:Hide() end end

-- the player clicked the header: opened or closed, remembered. In a fight, when that would move protected frames, it waits (a second
-- click before then takes the first back); returns false for a change that waits
function Section:Toggle()
  local now = self:IsOpen()
  if self.pendingWant ~= nil then now = self.pendingWant end
  local want = not now
  if self:Locked() then
    self.pendingWant = want
    local back = (want == self:IsOpen())
    Kit.Defer(self.page .. "/" .. self.id, function()
      self.pendingWant = nil
      if self:IsOpen() ~= want then self:SetOpen(want) end
    end)
    local name = "The " .. (self.title ~= "" and self.title or "page") .. " section"
    if back then Panoply:Print(name .. " stays as it is.") else waitLine(name, want and "opens" or "closes") end
    return false
  end
  self:SetOpen(want)
  return true
end

function Section:SetOpen(open)
  Kit.SetOpen(self.page, self.id, open)
  self:Apply()
  if self.opts.onChange then self.opts.onChange(self, open) else Kit.Redraw(self.page) end
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
local Tabs = {}
Tabs.__index = Tabs
Kit.TabsClass = Tabs

-- opts.page: the page key (the last tab is remembered under it); opts.items: { { key, label, short, tip, tipBody, icon, own } };
-- opts.orientation: "top" (a row, the standard) or "side" (a rail); opts.default: the tab that shows first; opts.get(): a page's
-- own working copy of the tab, when it has one (it wins while it names a tab of this page); opts.onSelect(key)
-- opts.style: "underline" for underlined text tabs (0.9.5, the redesigned pages); the boxed tabs when not said
function Kit.Tabs(parent, opts)
  opts = opts or {}
  local t = setmetatable({ page = opts.page, opts = opts, parent = parent, buttons = {}, byKey = {}, items = opts.items or {},
    orientation = opts.orientation == "side" and "side" or "top" }, Tabs)
  for i, it in ipairs(t.items) do
    local key = it.key
    -- 0.9.5 (spec 1.2): opts.style = "underline" draws the tabs as underlined text (Kit.TextTab, UI/KitParts.lua), not boxed buttons
    local make = (opts.style == "underline" and Kit.TextTab) or Skin.Tab
    local b = make(parent, it.label, 100, function() t:Select(key) end, it.tip or it.label, it.tipBody, it.icon, it.own)
    b.panoplyTab, b.panoplyFullLabel, b.panoplyShortLabel = key, it.label, it.short
    b.panoplyTabIndex = i
    -- a tab never takes the keyboard or the mouse wheel: the page keeps both
    t.buttons[i] = b
    t.byKey[key] = b
  end
  mark(opts.page, "Tabs")
  Kit.live[#Kit.live + 1] = t
  return t
end

function Tabs:Has(key) return self.byKey[key] ~= nil end

-- the tab that shows: the page's working copy, else the saved one, else the default, else the first
function Tabs:Current()
  local o = self.opts
  local first = self.items[1] and self.items[1].key
  local dflt = (o.default and self.byKey[o.default]) and o.default or first
  local v
  if o.get then
    local g = o.get()
    if g and self.byKey[g] then v = g end
  end
  if not v and self.page then v = Kit.GetTab(self.page, function(k) return self.byKey[k] ~= nil end) end
  v = v or dflt
  -- the page's own copy is the truth while it has one: what is saved follows it (a tab nobody changed is not saved)
  if self.page and o.get then
    local saved = Kit.GetTab(self.page)
    if saved ~= v and (saved ~= nil or v ~= dflt) then Kit.SetTab(self.page, v) end
  end
  return v
end

function Tabs:Apply() end

-- true while changing the tab would redraw protected frames (see Section:Locked)
function Tabs:Locked()
  if not inCombat() then return false end
  if self.opts.guard and self.opts.guard() then return true end
  return Kit.PageHolds(self.page)
end

function Tabs:Select(key, quiet)
  if not self.byKey[key] then return false end
  if not quiet and self:Locked() then
    -- a fight, and the page's content carries protected frames: the tab changes when it ends (a later click replaces this one)
    self.pendingKey = key
    Kit.Defer((self.page or "tabs") .. "/tab", function()
      local k = self.pendingKey
      self.pendingKey = nil
      if k and k ~= self:Current() then self:Select(k) end
    end)
    local label = self.byKey[key].panoplyFullLabel or key
    if key == self:Current() then Panoply:Print(("The %s tab stays as it is."):format(label)) else waitLine(("The %s tab"):format(label), "opens") end
    return false
  end
  -- 0.9.5 (spec 1.4): switching tabs is a step of the window's history (not when a page or the history itself sets it quietly)
  local H = (not quiet) and Panoply.History or nil
  if H then H:Begin() end
  if self.opts.onSelect then self.opts.onSelect(key) end
  if self.page then Kit.SetTab(self.page, key) end
  if not quiet then
    if self.opts.redraw then self.opts.redraw(key) else Kit.Redraw(self.page) end
  end
  if H then H:End("tab") end
  return true
end

-- one step along the tabs (a page's own key handling may ask for it; the tabs bind no key themselves)
function Tabs:Step(dir)
  local cur = self:Current()
  local n = #self.items
  for i, it in ipairs(self.items) do
    if it.key == cur and n > 0 then
      local nxt = self.items[((i - 1 + (dir or 1)) % n) + 1]
      return self:Select(nxt.key)
    end
  end
  return false
end

function Tabs:SetLabel(key, text)
  local b = self.byKey[key]
  if not b then return end
  b.panoplyFullLabel = text
  b.label:SetText(text)
end

function Tabs:SetShown(key, on)
  local b = self.byKey[key]
  if not b then return end
  b.panoplyHidden = not on or nil
end

function Tabs:HideAll() for _, b in ipairs(self.buttons) do b:Hide() end end

-- Lays the tabs out from (x, y) of the parent and marks the current one. Top: a row in width w (Skin.TabRow: the short names, then
-- shortened ones, never a second row); returns the row's height. Side: a rail w wide, one tab under another; returns the rail's
-- width and its height.
function Tabs:Layout(x, y, w, mode)
  -- 0.9.5 (spec 1.3): on a narrow page the tabs become one dropdown (mode = "dropdown"); returns the dropdown's height
  if mode == "dropdown" then return self:LayoutDropdown(x, y, w) end
  if self.dd then self.dd:Hide() end
  local cur = self:Current()
  local shown = {}
  for _, b in ipairs(self.buttons) do
    if b.panoplyHidden then b:Hide() else
      b:Show()
      b:SetActive(b.panoplyTab == cur)
      shown[#shown + 1] = b
    end
  end
  if self.orientation == "side" then
    local yy = 0
    for _, b in ipairs(shown) do
      b:SetSize(w, Kit.TAB.railH)
      b.label:SetWidth(w - 2 * SP.m - (b.icon and 22 or 0))
      Skin.Ellipsize(b.label, b.panoplyFullLabel, w - 2 * SP.m - (b.icon and 22 or 0))
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y - yy)
      yy = yy + Kit.TAB.railH + Kit.TAB.gap
    end
    return w, max(0, yy - Kit.TAB.gap)
  end
  for _, b in ipairs(shown) do b:SetHeight(Kit.TAB.h) end
  return Skin.TabRow(self.parent, shown, x, y, w, Kit.TAB.gap, self.opts.minW or Kit.TAB.minW)
end

-- The tabs as one dropdown (a narrow page): the same choices, the same memory, the same combat rule (Tabs:Select).
function Tabs:LayoutDropdown(x, y, w)
  self:HideAll()
  if not self.dd then
    self.dd = Kit.Dropdown(self.parent, { page = self.page, width = 200, tip = "Show", tipBody = "Pick what this page shows.",
      items = function()
        local out = {}
        for _, it in ipairs(self.items) do
          local b = self.byKey[it.key]
          if b and not b.panoplyHidden then out[#out + 1] = { text = b.panoplyFullLabel or it.label, value = it.key, tip = it.tipBody } end
        end
        return out
      end,
      get = function() return self:Current() end,
      set = function(k) self:Select(k) end })
    self.dd.panoplyTabsDropdown = true
  end
  local dd = self.dd
  dd:ClearAllPoints(); dd:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  dd:Fit(min(140, w), w)
  dd:Show()
  return dd:GetHeight() or 26
end

-------------------------------------------------------------------------------
-- Dropdown
-------------------------------------------------------------------------------
-- opts.items: a list, or a function giving it, of { text, value, tip }; opts.get() the value that shows; opts.set(value);
-- opts.label: words before the choice ("Sort: "); opts.width; opts.tip / opts.tipBody; opts.page (for the tests' list)
function Kit.Dropdown(parent, opts)
  opts = opts or {}
  local b = Skin.Button(parent, "", opts.width or 160, opts.height or 26, nil, opts.tip, opts.tipBody)
  b.panoplyKit = "Dropdown"
  b.panoplyDropdown = opts
  local chev = b:CreateTexture(nil, "ARTWORK")
  chev:SetSize(Kit.SECTION.chevron, Kit.SECTION.chevron)
  chev:SetPoint("RIGHT", b, "RIGHT", -10, 0)
  local gc = Skin.colors.gold
  chev:SetVertexColor(gc[1], gc[2], gc[3], 1)
  setChevron(chev, true)
  b.chevron = chev
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
  if b.label.SetJustifyH then b.label:SetJustifyH("LEFT") end
  local function list()
    local it = opts.items
    if type(it) == "function" then it = it() end
    return it or {}
  end
  function b:Items() return list() end
  function b:Current()
    local v = opts.get and opts.get()
    for _, it in ipairs(list()) do if it.value == v then return it end end
    return nil
  end
  function b:Refresh()
    local it = self:Current()
    local text = (opts.label or "") .. (it and it.text or (opts.empty or ""))
    local room = max(20, (self:GetWidth() or 160) - 10 - 10 - Kit.SECTION.chevron - SP.s)
    self.label:SetWidth(room)
    Skin.Ellipsize(self.label, text, room)
    self.panoplyText = text
  end
  -- the width that shows the longest choice whole, never more than max
  function b:Fit(minW, maxW)
    local widest = 0
    local probe = self.label
    for _, it in ipairs(list()) do
      probe:SetText((opts.label or "") .. (it.text or ""))
      widest = max(widest, ceil(TW(probe)))
    end
    local w = max(minW or 90, min(maxW or 260, widest + 10 + 10 + Kit.SECTION.chevron + SP.s))
    self:SetWidth(w)
    self:Refresh()
    return w
  end
  b.panoplyFit = function(self, minW, maxW) return self:Fit(minW, maxW) end
  function b:Open()
    local cur = opts.get and opts.get()
    local items = {}
    for i, it in ipairs(list()) do
      items[i] = { text = it.text, tip = it.tip, checked = (it.value == cur),
        func = function()
          local function pick()
            if opts.set then opts.set(it.value) end
            b:Refresh()
            if opts.onChange then opts.onChange(it.value) end
          end
          -- a fight, and the page's content carries protected frames (or the dropdown says so): the choice is made when it ends
          if inCombat() and ((opts.guard and opts.guard()) or Kit.PageHolds(opts.page)) then
            Kit.Defer((opts.page or "dropdown") .. "/dd/" .. tostring(b), pick)
            waitLine(("The choice '%s'"):format(it.text or "?"), "is made")
            return
          end
          pick()
        end }
    end
    return Skin.Menu(self, items, { width = max(opts.menuWidth or 0, self:GetWidth() or 160) })
  end
  function b:IsOpen() return Skin.menu and Skin.menu:IsShown() and Skin.menu.panoplyOwner == self and true or false end
  function b:Close() if self:IsOpen() then Skin.Popups:Close(Skin.menu) end end
  b:SetScript("OnClick", function(self) if not self.disabled then self:Open() end end)
  b:SetScript("OnHide", function(self) self:Close() end)
  b:Refresh()
  mark(opts.page, "Dropdown")
  return b
end

-------------------------------------------------------------------------------
-- List: pooled rows
-------------------------------------------------------------------------------
local List = {}
List.__index = List

-- opts.rowH (the least row height; Kit.ROW_H), opts.big (the larger type of a Home line), opts.icon (an icon column), opts.iconSize,
-- opts.onClick(item, index), opts.maxH (the most height it takes; more scrolls), opts.page.
-- items: { { id, title, sub, right, icon, own, selected, tip, tipBody, color, go, mark } } (set with List:Set, drawn by List:Layout)
function Kit.List(parent, opts)
  opts = opts or {}
  local l = setmetatable({ opts = opts, parent = parent, rows = {}, items = {}, selected = nil }, List)
  l.frame = CreateFrame("Frame", nil, parent)
  l.frame.panoplyGapOK = true
  l.frame:SetSize(10, 1)
  l.frame.panoplyKit = "List"
  if opts.maxH then
    l.area = Skin.ScrollArea(l.frame)
    l.area:SetPoint("TOPLEFT", l.frame, "TOPLEFT", 0, 0)
    l.host = l.area.content
  else
    l.host = l.frame
  end
  mark(opts.page, "List")
  return l
end

function List:Set(items)
  self.items = items or {}
  if self.selected then
    local found
    for _, it in ipairs(self.items) do if it.id == self.selected then found = true end end
    if not found then self.selected = nil end
  end
end

function List:Select(id)
  self.selected = id
  for _, r in ipairs(self.rows) do if r:IsShown() then self:Paint(r) end end
end
function List:Selected() return self.selected end

function List:Paint(r)
  local it = r.item
  local sel = it and ((it.selected == true) or (self.selected ~= nil and it.id == self.selected))
  r.panoplySelected = sel and true or false
  if sel then r.sel:Show() else r.sel:Hide() end
  local c = it and it.color or (sel and Skin.colors.heading or Skin.colors.ink)
  r.title:SetTextColor(c[1], c[2], c[3], 1)
end

function List:Row(i)
  local r = self.rows[i]
  if r then return r end
  local o, big = self.opts, self.opts.big
  r = CreateFrame("Button", nil, self.host)
  r.panoplyGapOK = true
  r.panoplyKit = "ListRow"
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(r)
  Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
  r.hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight); r.hl:Hide()
  r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(r)
  Skin.Solid(r.sel, Skin.colors.highlight, 0.18); r.sel:Hide()
  r.bar = r:CreateTexture(nil, "OVERLAY"); Skin.Solid(r.bar, Skin.colors.warn, 1); r.bar:SetWidth(3); r.bar:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.title = big and Skin.Name(r, Kit.TYPE.rowBig, Skin.colors.text) or Skin.Ink(r, Kit.TYPE.row)
  r.sub = Skin.Ink(r, big and Kit.TYPE.rowBigSub or Kit.TYPE.rowSub, Skin.colors.inkSoft)
  r.right = big and Skin.Name(r, 13, Skin.colors.goldBright) or Skin.Ink(r, Kit.TYPE.rowSub, Skin.colors.inkSoft)
  if r.right.SetJustifyH then r.right:SetJustifyH("RIGHT") end
  if r.right.SetWordWrap then r.right:SetWordWrap(false) end
  r.chev = Skin.Name(r, 15, Skin.colors.goldBright); r.chev:SetText(">")
  if r.chev.SetWordWrap then r.chev:SetWordWrap(false) end
  Skin.Tooltip(r, "", nil)
  local list = self
  r:SetScript("OnEnter", function(self) self.hl:Show() if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnClick", function(self)
    local it = self.item
    if not it or it.disabled then return end
    if list.opts.selectable then list:Select(it.id) end
    if it.onClick then it.onClick(it, self.panoplyIndex) elseif list.opts.onClick then list.opts.onClick(it, self.panoplyIndex) end
  end)
  self.rows[i] = r
  return r
end

-- the rows at (x, y) of the parent, width w; returns the list's height
function List:Layout(x, y, w)
  local o = self.opts
  local big = o.big
  local pad = big and 14 or 8
  local iconS = o.iconSize or (big and 30 or 16)
  local minH = o.rowH or (big and 56 or Kit.ROW_H)
  local f = self.frame
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, y)
  f:SetWidth(w)
  local innerW = w
  if o.maxH then
    -- rows are laid out for the width the bar leaves, then the view is cut to maxH
    innerW = w - 12
  end
  local rowY = 0
  for i, it in ipairs(self.items) do
    local r = self:Row(i)
    r.item, r.panoplyIndex = it, i
    r.tip, r.tipBody = it.tip or "", it.tipBody
    local hasIcon = it.icon ~= nil or o.icon
    local tx = pad + ((hasIcon and iconS + SP.m) or 0)
    local goW = it.go and (14 + SP.s) or 0
    r.right:SetText(it.right or "")
    local rw = (it.right and it.right ~= "") and min(ceil(TW(r.right)) + 2, floor(innerW * 0.4)) or 0
    r.right:SetWidth(max(1, rw))
    local tw = innerW - tx - pad - goW - (rw > 0 and (rw + SP.m) or 0)
    tw = max(40, tw)
    r.title:SetText(it.title or ""); r.title:SetWidth(tw)
    local th = TH(r.title, tw); r.title:SetHeight(th)
    r.sub:SetText(it.sub or ""); r.sub:SetWidth(tw)
    local sh = (it.sub and it.sub ~= "") and TH(r.sub, tw) or 0
    r.sub:SetHeight(max(1, sh))
    local h = ceil(max(minH, (big and 10 or 6) + th + (sh > 0 and (2 + sh) or 0) + (big and 10 or 6)))
    r:SetSize(innerW, h)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", self.host, "TOPLEFT", 0, -rowY)
    r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", r, "TOPLEFT", tx, -(big and 10 or 6))
    r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
    if hasIcon and it.icon then
      r.icon:SetSize(iconS, iconS)
      Skin.SetIcon(r.icon, it.icon, { size = iconS, own = it.own and true or nil })
      r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", r, "LEFT", pad, 0)
      r.icon:Show()
    else r.icon:Hide() end
    r.chev:ClearAllPoints(); r.bar:ClearAllPoints()
    if it.go then
      r.chev:SetWidth(14); r.chev:SetPoint("RIGHT", r, "RIGHT", -pad, 0); r.chev:Show()
    else r.chev:Hide() end
    r.right:ClearAllPoints()
    if rw > 0 then
      r.right:SetPoint("RIGHT", r, "RIGHT", -(pad + goW), 0)
      r.right:Show()
    else r.right:Hide() end
    if it.mark then
      r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -6); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 6); r.bar:Show()
    else r.bar:Hide() end
    r:Show()
    -- a row used again for another item shows no hover left from the one before (a row hidden under the mouse never heard it leave)
    if not (r.IsMouseOver and r:IsMouseOver()) then r.hl:Hide() end
    self:Paint(r)
    rowY = rowY + h + (o.gap or SP.xs)
  end
  for i = #self.items + 1, #self.rows do
    local r = self.rows[i]
    r:Hide()
    r.hl:Hide()
    r.item = nil
  end
  local content = max(0, rowY - ((#self.items > 0) and (o.gap or SP.xs) or 0))
  local h = content
  if o.maxH and content > o.maxH then
    h = o.maxH
    self.area:Show()
    self.area:SetSize(w, h)
    self.area.content:SetWidth(innerW)
    self.area:SetContentHeight(content)
  elseif o.maxH then
    self.area:Show()
    self.area:SetSize(w, max(1, content))
    self.area.content:SetWidth(w)
    self.area:SetContentHeight(content)
    -- no bar needed: rows take the whole width
    for i = 1, #self.items do self.rows[i]:SetWidth(w) end
  end
  f:SetHeight(max(1, h))
  self.contentH, self.height = content, h
  return h
end

function List:Hide() self.frame:Hide() end
function List:Show() self.frame:Show() end

-------------------------------------------------------------------------------
-- PageHeader: the header of every page (icon, title, one line of help, the right-hand controls)
-------------------------------------------------------------------------------
-- opts: onGear(), gearTip, onSwitch(), switchTip, sizes = { { id, name, tip, tipBody }... }, onSize(id), sizeLabelTip,
--   onReset(), resetTip (Reset view: the one button every page has, to show the page as it first opens)
-- h:Layout(spec, W) with spec = { icon, label, text, hasGear, switch = { on, word } | nil, extra = { label, value } | nil,
--   size = { current = id } | nil, controls = { frames } | nil, reset = { can = bool } | nil }; returns the header's height
--   spec.chip (0.9.5): the return chip of a page reached by a jump (UI/History.lua), a button with panoplyControlW
function Kit.PageHeader(area, opts)
  opts = opts or {}
  local H = Kit.HEADER
  local h = CreateFrame("Frame", nil, area)
  h:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  h:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
  h:SetHeight(58)
  h.panoplyKit = "PageHeader"
  h.panoplyMadeBy = Kit.PageHeader
  h.icon = h:CreateTexture(nil, "ARTWORK"); h.icon:SetSize(H.icon, H.icon)
  h.icon:SetPoint("TOPLEFT", h, "TOPLEFT", 6, -6)
  h.name = Skin.Heading(h, H.titleSize)
  h.text = Skin.Text(h, H.helpSize, Skin.colors.inkSoft)
  h.extraLabel = Skin.Label(h, 9, Skin.colors.inkSoft)
  h.extraValue = Skin.Name(h, 14, Skin.colors.heading)
  -- each is one line, as wide as its words: never wrapped over the other
  for _, fs in ipairs({ h.extraLabel, h.extraValue }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  h.switch = Skin.Switch(h, opts.onSwitch, "On or off", opts.switchTip)
  h.gear = Skin.IconButton(h, "Settings", H.gear, opts.onGear, "Settings", opts.gearTip)
  -- Reset view (step 20: one way to reset a page's remembered tab and sections, the same on every page, gear or no gear)
  h.reset = Skin.Button(h, "Reset view", 84, H.rowH, opts.onReset, "Reset view", opts.resetTip)
  h.reset.panoplyKit = "ResetView"
  -- Small / Normal / Large (UI/Presets.lua): on every page except Profiles and Help
  h.sizeLabel = Skin.Text(h, 12, Skin.colors.inkSoft); h.sizeLabel:SetText("Size")
  h.sizeBtns = {}
  for _, pr in ipairs(opts.sizes or {}) do
    local b = Skin.Button(h, pr.name, 64, H.rowH, function() if opts.onSize then opts.onSize(pr.id) end end, pr.name .. " size", pr.tipBody)
    b.panoplyPreset = pr.id
    h.sizeBtns[#h.sizeBtns + 1] = b
  end
  h.sizeLabel.tip, h.sizeLabel.tipBody = "Size", opts.sizeLabelTip
  h.rule = h:CreateTexture(nil, "ARTWORK")
  Skin.Solid(h.rule, Skin.colors.hairline, 1)
  h.rule:SetHeight(1)
  h.rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0); h.rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
  h.slot = {}          -- the extra controls a page registered, shown while that page is
  function h:Layout(spec, W)
    local TWf, THf = Skin.TextWidth, Skin.TextHeight
    -- 0.9.5 phase 4H: a page may be headed by a game texture cut to one part (the Class page's class crest); the next page's own icon
    -- gets the whole texture back
    if self.panoplyCrest and not spec.crest then
      if self.icon.SetTexCoord then self.icon:SetTexCoord(0, 1, 0, 1) end
      self.panoplyCrest = nil
    end
    Skin.SetIcon(self.icon, spec.icon, { size = H.icon, own = true })
    if spec.crest and spec.crest.tex then
      Skin.live[self.icon] = nil
      self.icon:SetTexture(spec.crest.tex)
      local c = spec.crest.cut
      if c and self.icon.SetTexCoord then self.icon:SetTexCoord(c[1], c[2], c[3], c[4]) end
      self.icon:Show()
      self.panoplyCrest = spec.crest.tex
    end
    self.name:SetText(spec.label)
    self.text:SetText(spec.text or "")
    -- right side, from the edge: the gear, the switch, the page's own extra (account gold), the page's extra controls, the Size choice
    local x = W - 4
    self.gear:ClearAllPoints()
    if spec.hasGear then self.gear:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -8); self.gear:Show(); x = x - H.gear - SP.m else self.gear:Hide() end
    if spec.switch then
      self.switch:SetState(spec.switch.on, spec.switch.word, 250)
      self.switch:ClearAllPoints(); self.switch:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(W - x) - 0, -H.switchY)
      self.switch:Show()
      x = x - self.switch:GetWidth() - SP.l
    else self.switch:Hide() end
    if spec.extra and spec.extra.label then
      self.extraLabel:SetText(spec.extra.label); self.extraValue:SetText(spec.extra.value)
      local ew = max(ceil(TWf(self.extraLabel)), ceil(TWf(self.extraValue))) + 8
      for _, o in ipairs({ self.extraLabel, self.extraValue }) do o:SetWidth(ew) if o.SetJustifyH then o:SetJustifyH("RIGHT") end end
      self.extraLabel:ClearAllPoints(); self.extraLabel:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(W - x), -8)
      self.extraValue:ClearAllPoints(); self.extraValue:SetPoint("TOPRIGHT", self.extraLabel, "BOTTOMRIGHT", 0, -2)
      self.extraLabel:Show(); self.extraValue:Show()
      x = x - ew - SP.l
    else self.extraLabel:Hide(); self.extraValue:Hide() end
    -- the page's extra controls (a registered frame each; its width is its own)
    for _, c in ipairs(self.slot) do c:Hide() end
    self.slot = {}
    for _, c in ipairs(spec.controls or {}) do
      local cw = c.panoplyControlW or c:GetWidth() or 90
      c:ClearAllPoints(); c:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(W - x), -8)
      c:Show()
      self.slot[#self.slot + 1] = c
      x = x - cw - SP.m
    end
    -- Size: Small, Normal, Large (not on Profiles and Help). Its width is read first: where Reset view goes depends on it.
    local sizeBelow, sg
    local shown = spec.size ~= nil and #self.sizeBtns > 0
    if shown then
      self.sizeLabel:SetWidth(ceil(TWf(self.sizeLabel)) + 2)
      sg = ceil(TWf(self.sizeLabel)) + 2 + SP.s
      for _, b in ipairs(self.sizeBtns) do sg = sg + Skin.FitButton(b, 56, 120) + 2 end
      sg = sg - 2
    end
    -- the title keeps at least 230 px: when it would not, the Size choice goes on its own line under the title
    local function sizeFits(xx) return (xx - sg - SP.l) - H.textX - 6 >= 230 end
    -- Reset view: the tab and the sections of this page as they first open (greyed while the page is already so). It sits in the top row
    -- with the other controls. If it alone would push the Size choice below the title (a narrow window or big text: the whole header
    -- then grows by a row, and the settings sheet under it loses that height), it sits on the second line under the Size choice instead
    -- (0.9.4 integration: the Map gear's front no longer fitted at 1.3x text on 1024 x 668)
    local resetBelow
    if spec.reset then
      local rw = Skin.FitButton(self.reset, 76, 130)
      -- dimmed while there is nothing to reset, and still clickable (it says the page is already as it opens); the words are dimmed, not
      -- struck through as Skin's SetDimmed draws a toggle that is off
      local dim = not spec.reset.can
      self.reset.dimmed = dim
      local c = dim and Skin.colors.dim or Skin.colors.text
      self.reset.label:SetTextColor(c[1], c[2], c[3], 1)
      self.reset.bg:SetAlpha(dim and 0.7 or 1)
      self.reset:Show()
      self.reset:ClearAllPoints()
      if shown and sizeFits(x) and not sizeFits(x - rw - SP.m) then
        resetBelow = true
      else
        self.reset:SetPoint("TOPRIGHT", self, "TOPRIGHT", -(W - x), -10)
        x = x - rw - SP.m
      end
    else self.reset:Hide() end
    -- Size sits at the top right when the title still has room; otherwise on its own line under the title, so nothing is squeezed at large
    -- text sizes.
    if shown then
      sizeBelow = not sizeFits(x)
      local cur = spec.size.current
      for _, b in ipairs(self.sizeBtns) do
        b:SetSelected(b.panoplyPreset == cur)
        local c = b.panoplyPreset == cur and Skin.colors.heading or Skin.colors.text
        b.label:SetTextColor(c[1], c[2], c[3], 1)
      end
      if not sizeBelow then x = x - sg - SP.l end
    end
    local tw = max(120, x - H.textX - 6)
    self.name:ClearAllPoints(); self.name:SetPoint("TOPLEFT", self, "TOPLEFT", H.textX, -6); self.name:SetWidth(tw)
    local nh = THf(self.name, tw)
    self.text:ClearAllPoints(); self.text:SetPoint("TOPLEFT", self, "TOPLEFT", H.textX, -6 - nh - 2); self.text:SetWidth(tw)
    local th = THf(self.text, tw)
    local total = max(H.minH, 6 + nh + 2 + th + 8)
    -- 0.9.5 (spec 1.4): the return chip of a page reached by a jump ("< Field Kit"): beside the title when the title's line has
    -- the room, else on a line of its own under the help line (the header grows by that line)
    if self.chipShown and self.chipShown ~= spec.chip then self.chipShown:Hide() end
    self.chipShown = spec.chip
    if spec.chip then
      local c = spec.chip
      local cw, chh = c.panoplyControlW or c:GetWidth() or 90, c:GetHeight() or 24
      local nameW = ceil(TWf(self.name)) + 2
      c:ClearAllPoints()
      if nameW + SP.m + cw <= tw and nh <= chh + 6 then
        self.name:SetWidth(nameW)
        c:SetPoint("TOPLEFT", self, "TOPLEFT", H.textX + nameW + SP.m, -6 - floor((nh - chh) / 2))
        self.chipBelow = false
      else
        local cy = 6 + nh + 2 + th + SP.xs
        c:SetPoint("TOPLEFT", self, "TOPLEFT", H.textX, -cy)
        total = max(total, cy + chh + SP.s)
        self.chipBelow = true
      end
      c:Show()
    end
    if shown then
      -- the group's left edge: from the right end of the space the title leaves
      local gx, y
      if sizeBelow then gx, y = W - 4 - sg, -(total - 2); total = total + 28 + SP.s
      else gx, y = x + SP.l, -10 end
      self.sizeLabel:ClearAllPoints(); self.sizeLabel:SetPoint("TOPLEFT", self, "TOPLEFT", gx, y - 6)
      self.sizeLabel:Show()
      local bx = gx + ceil(TWf(self.sizeLabel)) + 2 + SP.s
      for _, b in ipairs(self.sizeBtns) do
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", self, "TOPLEFT", bx, y); b:Show()
        bx = bx + b:GetWidth() + 2
      end
    else
      self.sizeLabel:Hide()
      for _, b in ipairs(self.sizeBtns) do b:Hide() end
    end
    if resetBelow then
      -- under everything that stands in the top row on the right (gear, switch, Size, the account's gold), at the right edge
      local bottom = 10 + H.rowH
      if spec.hasGear then bottom = max(bottom, 8 + H.gear) end
      if spec.switch then bottom = max(bottom, H.switchY + (self.switch:GetHeight() or 24)) end
      if spec.extra and spec.extra.label then bottom = max(bottom, 8 + (self.extraLabel:GetHeight() or 12) + 2 + (self.extraValue:GetHeight() or 18)) end
      local ry = bottom + 4
      self.reset:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -ry)
      total = max(total, ry + H.rowH + 2)
    end
    self:SetHeight(total)
    return total
  end
  Kit.lastHeader = h
  return h
end
