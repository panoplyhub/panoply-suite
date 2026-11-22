-- Muster (was Hearth Hall), a page of the one Panoply Suite window. 0.9.5 phase 4I rebuilt it from docs/specs/page-redesigns-02-muster.md
-- with the shared visual system (UI/KitParts.lua): no bordered boxes, gold only on titles, explanations in ? tooltips, one-line empty
-- states, the destructive action in a ⋯ menu that asks first, money with coin icons.
--
--   Account strip (pinned)  account gold with the 7-day change (a click opens the 30-day gold chart, stacked by character), the
--                           characters, total played and free bag slots, the Alerts chip with its count (a click lists them, each
--                           opening the character and tab it is about), the ? tooltip (Core/Sharing.lua's Muster line), and the
--                           search box "Find an item on any character" with the Sort dropdown.
--   Roster (Wide, ~260 px)  grouped by realm and faction: class crest, name in its class colour, level, zone, gold, a thin rested bar
--                           (estimated, "~"), alert dot, "Playing" on the character being played, ⋯ (Forget, Set profile).
--                           Medium: an icon rail (crest, level, alert dot; the name in the tooltip). Narrow: a character dropdown in
--                           the strip.
--   Character detail        name, race, class and spec, level with the XP bar and the estimated rested part, where it is, its hearth,
--                           last seen, played; tabs Overview · Bags · Bank · Mail · Gear · Professions · Auctions (· Lockouts when it
--                           has some, on WoW Forever from Dec 9, 2026). Narrow: the tabs are a dropdown.
--   Search                  replaces the detail while a query is typed: one row an item with where every copy is, then "Who can
--                           craft". Back returns to the character. In Bags and Bank the slots that do not match are dimmed.
-- The data is Alts.lua's, the Inventory store's and the Auctions record's (only what was saved: nothing is invented); this file draws it.
-- Nothing here moves, buys, uses or casts anything.
local ADDON, Panoply = ...
local C, Skin, Kit = Panoply.Compat, Panoply.Skin, Panoply.Kit
local Alts = Panoply.Alts
local Menu = Panoply.Menu
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local H = { containers = {}, tab = "overview", search = "", view = "char" }
Alts.Hall = H

H.ROSTER_W, H.RAIL_W = 260, 56
H.ROW_H, H.RAIL_H, H.GROUP_H = 42, 46, 24
H.SLOT, H.SLOT_GAP, H.COLS = 26, 3, 4
H.MAX_RESULTS = 12
H.CHART_DAYS, H.CHART_H, H.CHART_SERIES = 30, 120, 8
H.GRIP = 22
-- WoW Forever's raids open on Dec 9, 2026 (00:00 UTC): the Lockouts tab stays hidden there before then (spec 02 2.3)
H.LOCKOUTS_FROM = 1796774400

Kit.TOKENS["accent.muster"] = Kit.TOKENS["accent.muster"] or "accentMoss"

-------------------------------------------------------------------------------
-- Icon slots (spec 02 section 4)
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
Kit.RegisterIcon("icon.page.muster", { icon = "MenuMuster", own = true })
Kit.RegisterIcon("icon.alert", { game = { "Interface\\GossipFrame\\AvailableQuestIcon", I .. "INV_Misc_QuestionMark" }, raw = true })
Kit.RegisterIcon("icon.mail", { game = { I .. "INV_Letter_15", I .. "INV_Letter_01" } })
Kit.RegisterIcon("icon.bank", { game = { I .. "INV_Misc_Bag_10_Blue", I .. "INV_Misc_Bag_10" } })
Kit.RegisterIcon("icon.bags", { game = { I .. "INV_Misc_Bag_08", I .. "INV_Misc_Bag_07" } })
if not Kit.ICONS["icon.faction.alliance"] then Kit.RegisterIcon("icon.faction.alliance", { game = { I .. "INV_BannerPVP_02", I .. "INV_Misc_QuestionMark" } }) end
if not Kit.ICONS["icon.faction.horde"] then Kit.RegisterIcon("icon.faction.horde", { game = { I .. "INV_BannerPVP_01", I .. "INV_Misc_QuestionMark" } }) end

local CREST = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CREST_CUT = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
for cls in pairs(CREST_CUT) do
  if not Kit.ICONS["icon.class." .. cls:lower()] then Kit.RegisterIcon("icon.class." .. cls:lower(), { game = { CREST }, raw = true }) end
end
local function crest(tex, cls)
  local t = type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[cls or ""] or CREST_CUT[cls or ""]
  if t then
    tex:SetTexture(CREST)
    if tex.SetTexCoord then tex:SetTexCoord(t[1], t[2], t[3], t[4]) end
  else
    tex:SetTexture(I .. "INV_Misc_QuestionMark")
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
  end
  tex.panoplySlot = "icon.class." .. tostring(cls or "unknown"):lower()
end

-------------------------------------------------------------------------------
-- Words (also read by the tests and the previews)
-------------------------------------------------------------------------------
H.TABS = { { "overview", "Overview" }, { "bags", "Bags" }, { "bank", "Bank" }, { "mail", "Mail" }, { "gear", "Gear" },
  { "professions", "Professions" }, { "auctions", "Auctions" }, { "lockouts", "Lockouts" } }
H.TAB_TIPS = {
  overview = "Professions, cooldowns, item level and this character's alerts.",
  bags = "What this character carried in its bags the last time it was played.",
  bank = "What was in its bank the last time it visited a banker.",
  mail = "Its mailbox, as it was the last time it was open.",
  gear = "What it wore. For the character you are playing, the upgrades from At your level.",
  professions = "Skill, rank and the recipes known, saved when it opens each profession window.",
  auctions = "What it still has listed on the auction house, and what did not sell.",
  lockouts = "Raids and dungeons it is saved to, and when they reset.",
}
H.WORDS = {
  search = "Find an item on any character",
  noMatch = "Nothing found on any of your characters.",
  noMail = "No mail.",
  mailRanOut = "Ran out",
  mailNotSeen = "Mailbox not opened yet with Muster on.",
  noAuctions = "Nothing listed.",
  noLockouts = "No lockouts.",
  stub = "Only its saved bags are known. Log in with it once and Muster fills in the rest.",
  meSoon = "Muster saves this character a few seconds after login.",
  noGear = "Not saved yet: log in with it once.",
  bagsOff = "Bags and bank are only saved while the Bags module is on.",
  off = "Muster is off. Turn it on with the switch at the top of this page.",
  noAlerts = "Nothing needs you.",
  noLegacy = "No Legacy challenges earned by this character yet.",
}
H.LEGACY_NAMES = 4      -- the Overview names this many of a character's Legacy challenges, then "and N more"
local FAMILY = { [1] = "Quiver", [2] = "Ammo pouch", [4] = "Soul bag", [8] = "Leatherworking bag", [16] = "Inscription bag",
  [32] = "Herb bag", [64] = "Enchanting bag", [128] = "Engineering bag", [256] = "Keyring", [512] = "Gem bag", [1024] = "Mining bag" }
function H.FamilyName(fam)
  fam = tonumber(fam) or 0
  if fam == 0 then return nil end
  local bit = 1
  while bit <= 1024 do
    if fam % (bit * 2) >= bit and FAMILY[bit] then return FAMILY[bit] end
    bit = bit * 2
  end
  return "Special bag"
end
local RANKS = { { 75, "Apprentice" }, { 150, "Journeyman" }, { 225, "Expert" }, { 300, "Artisan" } }
function H.RankName(maxSkill)
  maxSkill = tonumber(maxSkill) or 0
  for _, r in ipairs(RANKS) do if maxSkill <= r[1] then return r[2] end end
  return "Artisan"
end

local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end
local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

-- copper with the game's coin icons. short: gold only (rounded down) over 1 gold
local COIN = { g = "Interface\\MoneyFrame\\UI-GoldIcon", s = "Interface\\MoneyFrame\\UI-SilverIcon", c = "Interface\\MoneyFrame\\UI-CopperIcon" }
function H.Coins(copper, short)
  copper = floor(math.abs(tonumber(copper) or 0) + 0.5)
  local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  local out = {}
  local function add(v, k) out[#out + 1] = (k == "g" and Alts.Commas(v) or tostring(v)) .. "|T" .. COIN[k] .. ":0:0:2:0|t" end
  if short and g > 0 then add(g, "g") return table.concat(out, " ") end
  if g > 0 then add(g, "g") end
  if s > 0 or (g > 0 and c > 0) then add(s, "s") end
  if c > 0 or #out == 0 then add(c, "c") end
  return table.concat(out, " ")
end
-- "+1,204g" in green, "-12g" in red (coins), for the account strip
function H.ChangeText(delta)
  if not delta or delta == 0 then return nil end
  local col = delta > 0 and Kit.Color("state.good") or Kit.Color("state.bad")
  return Skin.Code(col) .. (delta > 0 and "+" or "-") .. H.Coins(math.abs(delta), true) .. "|r"
end

function H:Key(e) return e and (e.realm .. "\1" .. e.name) end
local function charKey(e) return Panoply.Alerts and Panoply.Alerts.CharKey(e.realm, e.name) end

-------------------------------------------------------------------------------
-- A canvas: pooled pieces on one frame, all hidden at the start of each layout and taken again in drawing order
-------------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas
local function canvas(frame) return setmetatable({ frame = frame, pools = {} }, Canvas) end
function Canvas:Begin()
  for _, pl in pairs(self.pools) do for i = 1, pl.n do pl[i]:Hide() if pl[i].hl then pl[i].hl:Hide() end end pl.n = 0 end
end
function Canvas:Get(kind, make)
  local pl = self.pools[kind]
  if not pl then pl = { n = 0 } self.pools[kind] = pl end
  pl.n = pl.n + 1
  local o = pl[pl.n]
  if not o then o = make(self.frame) pl[pl.n] = o end
  if o.ClearAllPoints then o:ClearAllPoints() end
  o:Show()
  return o
end
-- one line (or wrapped words) at (x, y), w wide: its height and the font string
function Canvas:Text(x, y, w, size, color, words, opts)
  opts = opts or {}
  local kind = (opts.name and "N" or "I") .. size
  local fs = self:Get(kind, function(f)
    local s = opts.name and Skin.Name(f, size, Kit.Color("text.primary")) or Skin.Ink(f, size, Kit.Color("text.muted"))
    if s.SetJustifyH then s:SetJustifyH("LEFT") end
    return s
  end)
  setColor(fs, type(color) == "table" and color or Kit.Color(color or "text.muted"))
  if fs.SetJustifyH then fs:SetJustifyH(opts.right and "RIGHT" or "LEFT") end
  fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  w = max(10, w)
  fs:SetWidth(w)
  if opts.wrap then
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(words or "")
  else
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    Skin.Ellipsize(fs, words or "", w)
  end
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  if opts.fit then fs:SetWidth(min(w, ceil(TW(fs)) + 2)) end
  return h, fs
end
-- a text exactly as wide as its words (at most maxW): width, height, font string
function Canvas:Word(x, y, size, color, words, maxW, opts)
  opts = opts or {}
  opts.fit = true
  local h, fs = self:Text(x, y, maxW or 400, size, color, words, opts)
  return min(maxW or 400, ceil(TW(fs)) + 2), h, fs
end
-- the width words would take, without drawing them (one hidden font string per size)
function Canvas:Measure(size, color, words, maxW, opts)
  local name = opts and opts.name
  self.meas = self.meas or {}
  local k = (name and "N" or "I") .. size
  local fs = self.meas[k]
  if not fs then
    fs = name and Skin.Name(self.frame, size, Kit.Color("text.primary")) or Skin.Ink(self.frame, size, Kit.Color("text.muted"))
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetWidth(2000)
    fs:Hide()
    fs.panoplyLayoutSkip = true
    self.meas[k] = fs
  end
  fs:SetText(words or "")
  return min(maxW or 400, ceil(TW(fs)) + 2)
end
function Canvas:Tex(x, y, w, h, layer)
  local t = self:Get("T" .. (layer or "ARTWORK"), function(f) return f:CreateTexture(nil, layer or "ARTWORK") end)
  t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  t:SetSize(w, h)
  t:SetAlpha(1)
  if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
  if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 1) end
  return t
end
-- a clickable area with a tooltip (rows, chips)
local function hotSpot(f)
  local b = CreateFrame("Button", nil, f)
  -- a clear click area over words that are laid out (and checked) on their own: the layout checker leaves it out
  b.panoplyGapOK, b.panoplyLayoutSkip = true, true
  -- the suite's hover look (a soft rounded accent tint), drawn on the canvas BEHIND the words: a texture on this button would sit
  -- over every word the canvas draws for the row (0.9.5 blanked the name, level, gold and zone of a hovered row)
  b.hl = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.hl:SetAllPoints(b)
  Skin.Round(b.hl, Skin.RADIUS.row, Skin.TEX.RFill)
  b.hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight)
  b.hl.panoplyLayoutSkip = true
  b.hl:Hide()
  b:SetScript("OnHide", function(self) self.hl:Hide() end)
  b:SetScript("OnEnter", function(self)
    if self.panoplyHover then self.hl:Show() end
    local GT = _G.GameTooltip
    if not GT then return end
    if self.link then
      GT:SetOwner(self, "ANCHOR_RIGHT")
      local ok = GT.SetHyperlink and pcall(GT.SetHyperlink, GT, self.link)
      if ok then GT:Show() return end
    end
    if self.tip then
      GT:SetOwner(self, "ANCHOR_RIGHT")
      GT:SetText(self.tip, 0.95, 0.84, 0.55, 1, true)
      if self.tipBody then GT:AddLine(self.tipBody, 0.9, 0.9, 0.88, true) end
      GT:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self, btn) if self.panoplyOnClick then self.panoplyOnClick(self, btn) end end)
  return b
end
function Canvas:Hot(x, y, w, h, onClick, tip, body, hover)
  local b = self:Get("hot", hotSpot)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  b:SetSize(max(1, w), max(1, h))
  b.panoplyOnClick, b.tip, b.tipBody, b.link, b.panoplyHover = onClick, tip, body, nil, hover
  b.hl:Hide()
  b:EnableMouse(onClick ~= nil or tip ~= nil)
  return b
end
function Canvas:Button(x, y, label, onClick, tip, body, minW, maxW, h)
  local b = self:Get("btn" .. (h or 24), function(f)
    local bb = Skin.Button(f, "", 80, h or 24, function(self, btn) if self.panoplyOnClick then self.panoplyOnClick(self, btn) end end)
    bb.panoplyGapOK = true
    return bb
  end)
  b.label:SetText(label or "")
  Skin.FitButton(b, minW or 60, maxW or 240)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  b.panoplyOnClick, b.tip, b.tipBody = onClick, tip or label, body
  b:SetEnabledLook(true)
  return b, b:GetWidth(), b:GetHeight()
end
function Canvas:More(x, y, size, items, tip)
  local b = self:Get("more" .. size, function(f)
    local bb = Skin.IconButton(f, "Settings", size, function(self) if self.panoplyItems then Skin.Menu(self, self.panoplyItems(), { width = 210 }) end end, "More", "")
    bb.panoplyKitIcon = "icon.ui.more"
    bb.panoplyGapOK = true
    return bb
  end)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  b.panoplyItems, b.tip, b.tipBody = items, "More", tip
  return b
end
function Canvas:Bar(x, y, w, h, accent, value, maxV)
  local bar = self:Get("bar" .. h, function(f) return Kit.ProgressBar(f, { h = h, accent = accent }) end)
  bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  if bar.SetAccent then bar:SetAccent(accent) end
  bar:SetBarWidth(max(4, w))
  if maxV and maxV > 0 then bar:SetValue(min(value or 0, maxV), maxV) else bar:SetProgress(value or 0) end
  return bar
end
function Canvas:Chip(x, y, kind, words)
  local chip = self:Get("chip", function(f) return Kit.StatusChip(f, kind, words) end)
  local w, h = chip:Set(kind, words)
  chip:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  return chip, w, h
end
function Canvas:Help(x, y, title, body)
  local b = self:Get("help", function(f) local hh = Kit.HelpIcon(f, title, body, 16) hh.panoplyGapOK = true return hh end)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y)
  b.tip, b.tipBody = title, body
  return b
end

-- a bag slot (the game's item icon, its quality border, the stack count)
local function newSlot(parent)
  local s = CreateFrame("Button", nil, parent)
  s:SetSize(H.SLOT, H.SLOT)
  s.panoplyLayoutSkip = true
  s.rim = s:CreateTexture(nil, "BACKGROUND"); s.rim:SetAllPoints(s)
  Skin.Round(s.rim, 3, Skin.TEX.RFill)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2); s.icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
  s.count = Skin.Name(s, 9, Skin.colors.text)
  s.count:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
  if s.count.SetJustifyH then s.count:SetJustifyH("RIGHT") end
  s:SetScript("OnEnter", function(self)
    local GT = _G.GameTooltip
    if not (GT and self.item) then return end
    GT:SetOwner(self, "ANCHOR_RIGHT")
    local ok = self.item.link and GT.SetHyperlink and pcall(GT.SetHyperlink, GT, self.item.link)
    if not ok then GT:SetText(self.item.name or ("Item " .. self.item.itemID), 0.95, 0.84, 0.55, 1, true) end
    GT:Show()
  end)
  s:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  return s
end
local function newContainer(parent)
  local c = CreateFrame("Frame", nil, parent)
  c.panoplyGapOK = true
  c.name = Skin.Label(c, 9, Skin.colors.inkSoft)
  c.used = Skin.Text(c, 10, Skin.colors.dim)
  c.kind = Skin.Text(c, 10, Skin.colors.dim)
  for _, fs in ipairs({ c.name, c.used, c.kind }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  c.slots = {}
  return c
end

-------------------------------------------------------------------------------
-- The page's state: who is chosen, the tab, the view (char | results | alerts | chart), the search; Back and Forward (History)
-------------------------------------------------------------------------------
Panoply.Kit.TabVar("hall", { get = function() return H.tab end, set = function(k) H.tab = k end, default = "overview",
  valid = function(k) return H.TAB_TIPS[k] ~= nil end })
Kit.OnReset("hall", function() H.view, H.confirm = "char", nil H:ClearSearch() end)
if Panoply.History then Panoply.History:State("hall", {
  get = function() return { sel = H.sel and { realm = H.sel.realm, name = H.sel.name } or nil, tab = H.tab, view = H.view, search = H.search } end,
  set = function(s)
    if type(s) ~= "table" then return end
    H.sel, H.tab, H.view, H.confirm = s.sel, s.tab or H.tab, s.view or "char", nil
    H.search = s.search or ""
    if H.box then H.box:SetText(H.search) if H.box.placeholder then if H.search == "" then H.box.placeholder:Show() else H.box.placeholder:Hide() end end end
  end,
  key = function(s) return type(s) == "table" and (tostring(s.sel and (s.sel.realm .. "/" .. s.sel.name)) .. "|" .. tostring(s.tab) .. "|" .. tostring(s.view) .. "|" .. tostring(s.search)) or tostring(s) end,
}) end
local function note(why) if Panoply.History then Panoply.History:Note(why) end end

function H:Select(realm, name, tab)
  self.sel = { realm = realm, name = name }
  self.confirm = nil
  if tab and self.TAB_TIPS[tab] then self.tab = tab end
  self.view = "char"
  note("character")
  self:Refresh()
end
function H:SetTab(tab)
  if not self.TAB_TIPS[tab] then return end
  self.tab = tab
  if self.page and self.page.tabs then self.page.tabs:Select(tab, true) end
  note("tab")
  self:Refresh()
end
function H:SetView(v)
  if self.view == v then v = "char" end
  self.view = v
  self.confirm = nil
  note("view")
  self:Refresh()
end

function H:SetSearch(text, now)
  text = tostring(text or "")
  if text == self.search then return end
  self.search = text
  local stamp = (self.stamp or 0) + 1
  self.stamp = stamp
  local function go()
    if #self.search >= Alts.SEARCH_MIN then self.view = "results" elseif self.view == "results" then self.view = "char" end
    note("search")
    self:Refresh()
  end
  if now or text == "" then go() return end
  C.After(0.2, function() if H.stamp == stamp then go() end end)
end
function H:ClearSearch()
  self.search = ""
  self.stamp = (self.stamp or 0) + 1
  if self.view == "results" then self.view = "char" end
  if self.box then self.box:SetText("") if self.box.placeholder then self.box.placeholder:Show() end end
end
function H:BackToCharacter()
  self:ClearSearch()
  self.view = "char"
  note("back")
  self:Refresh()
end

function H:CycleSort()
  local cur = Panoply.db.hallSort or "level"
  local nxt = Alts.SORTS[1]
  for i, k in ipairs(Alts.SORTS) do if k == cur then nxt = Alts.SORTS[i % #Alts.SORTS + 1] end end
  Panoply:SetOption("hallSort", nxt)
  self:Refresh()
end

-- Forget (from the ⋯ menu): first a question on the page that lists what is deleted
function H:AskForget(e)
  if not e then return end
  self.sel = { realm = e.realm, name = e.name }
  self.view, self.confirm = "char", self:Key(e)
  self:Refresh()
end
-- what forgetting deletes, in words
function H:ForgetList(e)
  -- 0.9.5 phase 17: a character known only from its saved bags (e.stub) has no record of its level, gold or professions to forget
  local bits = {}
  if not e.stub then bits[1] = "its level, gold, professions and where it was" end
  local used = Alts:SlotUse(e, "bags")
  if used then bits[#bits + 1] = ("its saved bags (%d %s)"):format(used, plural(used, "item")) end
  local bused = Alts:SlotUse(e, "bank")
  if bused then bits[#bits + 1] = ("its saved bank (%d %s)"):format(bused, plural(bused, "item")) end
  local m = e.rec and e.rec.mail
  if m then bits[#bits + 1] = ("its saved mail (%d %s)"):format(m.n or 0, plural(m.n or 0, "letter")) end
  if type(e.rec and e.rec.recipes) == "table" then bits[#bits + 1] = "its saved recipes" end
  local g = Alts:GoldLog(false)
  if g and type(g.chars[e.realm]) == "table" and g.chars[e.realm][e.name] then bits[#bits + 1] = "its gold history" end
  return bits
end
function H:DoForget()
  local e = self.cur
  if not e then return end
  local ok, why = Alts:Forget(e.realm, e.name)
  self.confirm = nil
  if ok then
    local g = Alts:GoldLog(false)
    if g and type(g.chars[e.realm]) == "table" then
      g.chars[e.realm][e.name] = nil
      if next(g.chars[e.realm]) == nil then g.chars[e.realm] = nil end
    end
    Panoply:Print(("Muster forgot %s. Nothing in the game changed."):format(e.name))
    self.sel = nil
  elseif why then Panoply:Print(why) end
  self:Refresh()
end
-- the ⋯ menu of a character
function H:MenuItems(e)
  local items = {}
  if Panoply.Menu and Menu.pages and Panoply.Catalog and Panoply.Catalog.profiles then
    items[#items + 1] = { text = "Set profile", tip = "Choose the settings profile this character uses, on the Profiles page.",
      func = function() note("profiles") Menu:Open("profiles") end }
  end
  items[#items + 1] = { divider = true }
  if e.me then
    items[#items + 1] = { text = Skin.Code(Skin.colors.dim) .. "Forget this character|r", tip = "You are playing this character right now, so it cannot be forgotten.",
      func = function() Panoply:Print("You are playing this character, so Muster cannot forget it. Log in with another one first.") end }
  else
    items[#items + 1] = { text = Skin.Code(Skin.colors.loss) .. "Forget this character|r",
      tip = "Delete what Panoply Suite saved about it. Asks first; nothing in the game changes.", func = function() H:AskForget(e) end }
  end
  return items
end

-------------------------------------------------------------------------------
-- The page body (built once): the strip's controls and the scroll areas
-------------------------------------------------------------------------------
Menu:RegisterTab("Hall", function(p)
  p.strip = Kit.Surface(p, 1)
  p.strip.panoplyGapOK = true
  p.scv = canvas(p.strip)
  p.box = Skin.Input(p.strip, 300, 26, H.WORDS.search)
  p.box:SetScript("OnTextChanged", function(b)
    local t = b:GetText() or ""
    if b.placeholder then if t == "" then b.placeholder:Show() else b.placeholder:Hide() end end
    H:SetSearch(t)
  end)
  p.box:SetScript("OnEnterPressed", function(b) b:ClearFocus() H:SetSearch(b:GetText() or "", true) end)
  p.box:SetScript("OnEscapePressed", function(b)
    if (b:GetText() or "") ~= "" then b:SetText("") H:SetSearch("", true) end
    b:ClearFocus()
  end)
  H.box = p.box
  p.sortBtn = Kit.Dropdown(p.strip, { page = "hall", width = 140, label = "Sort: ", tip = "Sort",
    tipBody = "How the characters are ordered: level, name, gold, played or last seen.",
    items = function()
      local out = {}
      for _, k in ipairs(Alts.SORTS) do out[#out + 1] = { text = Alts.SORT_LABELS[k], value = k } end
      return out
    end,
    get = function() local k = Panoply.db.hallSort or "level" if not Alts.SORT_LABELS[k] then k = "level" end return k end,
    set = function(v) Panoply:SetOption("hallSort", v) end,
    onChange = function() H:Refresh() end })
  H.sortBtn = p.sortBtn
  -- Narrow: the roster is this dropdown
  p.charDD = Kit.Dropdown(p.strip, { page = "hall", width = 200, tip = "Character", tipBody = "Pick whose bags, bank, mail and gear you see.",
    items = function()
      local out = {}
      for _, e in ipairs(H.flat or {}) do out[#out + 1] = { text = e.name .. (e.level and (" (" .. e.level .. ")") or ""), value = H:Key(e) } end
      return out
    end,
    get = function() return H.cur and H:Key(H.cur) end,
    set = function(v) for _, e in ipairs(H.flat or {}) do if H:Key(e) == v then H:Select(e.realm, e.name) end end end })
  p.roster = Skin.ScrollArea(p)
  p.rcv = canvas(p.roster.content)
  p.detail = Skin.ScrollArea(p)
  p.dcv = canvas(p.detail.content)
  local items = {}
  for _, t in ipairs(H.TABS) do items[#items + 1] = { key = t[1], label = t[2], tip = t[2], tipBody = H.TAB_TIPS[t[1]] } end
  p.tabs = Kit.Tabs(p.detail.content, { page = "hall", items = items, default = "overview", style = "underline", minW = 48,
    get = function() return H.tab end, onSelect = function(k) H.tab = k H.confirm = nil note("tab") H:Refresh() end })
  p.grid = Kit.SlotGrid(p.detail.content, { accent = "muster", onSelect = function(key) H:GearClick(key) end })
  p.off = Skin.Ink(p, 13, Kit.Color("state.warn"))
  H.page = p
end, function(p) H:Refresh() end)

-------------------------------------------------------------------------------
-- Refresh: the data, then the drawing
-------------------------------------------------------------------------------
function H:Refresh()
  local p = self.page
  if not p then return end
  local f = Menu.frame
  if not (f and f:IsShown() and Menu.current == "hall") then return end
  self.nRefresh = (self.nRefresh or 0) + 1
  self.gridCache = {}   -- the saved containers are read once per refresh
  local sortKey = Panoply.db.hallSort or "level"
  if not Alts.SORT_LABELS[sortKey] then sortKey = "level" end
  local groups, total, count = Alts:Groups(sortKey)
  local flat, meE = {}, nil
  for _, g in ipairs(groups) do for _, e in ipairs(g.chars) do flat[#flat + 1] = e if e.me then meE = e end end end
  local cur
  if self.sel then for _, e in ipairs(flat) do if e.realm == self.sel.realm and e.name == self.sel.name then cur = e end end end
  cur = cur or meE or flat[1]
  self.cur, self.flat, self.groups, self.total, self.count = cur, flat, groups, total, count
  self.sel = cur and { realm = cur.realm, name = cur.name } or nil
  if self.confirm and not (cur and self.confirm == self:Key(cur)) then self.confirm = nil end
  Menu:LayoutHeader()
  local ok, err = pcall(self.Draw, self, p)
  if not ok then Panoply:Debug("muster draw", err) end
  Panoply:Fire("ALTS_SHOWN")
end

-- the alerts of every character (Core/Alerts.lua, from UI/AlertSources.lua's Muster source and the others)
function H:Alerts(e)
  local A = Panoply.Alerts
  if not A then return {} end
  local ok, list = pcall(A.List, A, e and { characterKey = charKey(e) } or nil)
  if not ok or type(list) ~= "table" then return {} end
  if e then return list end
  local out = {}
  for _, a in ipairs(list) do if a.page == "hall" or a.characterKey then out[#out + 1] = a end end
  return out
end

-- one character's saved containers for one place, read once per refresh
function H:GridOf(e, where)
  self.gridCache = self.gridCache or {}
  local k = self:Key(e) .. "\2" .. where
  local g = self.gridCache[k]
  if not g then g = { Alts:Grid(e, where) } self.gridCache[k] = g end
  return g[1], g[2]
end

function H:FreeSlots()
  local free = 0
  for _, e in ipairs(self.flat or {}) do
    local used, size = Alts:SlotUse(e, "bags")
    if used and size then free = free + max(0, size - used) end
  end
  return free
end
function H:TotalPlayed(now)
  local t = 0
  for _, e in ipairs(self.flat or {}) do t = t + (Alts.PlayedNow(e, now) or 0) end
  return t
end

function H:LockoutsShown(e)
  local l = e and e.rec and e.rec.lockouts
  if type(l) ~= "table" or #l == 0 then return false end
  local now = Alts.Now()
  if C.IsForever() and now < H.LOCKOUTS_FROM then return false end
  -- 0.9.5 phase 17 (spec 02 2.3: hidden for a character with no lockouts): only a lockout that has not reset yet counts
  for _, x in ipairs(l) do if type(x) == "table" and (tonumber(x.reset) or 0) > now then return true end end
  return false
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
function H:Draw(p)
  local W, Hh = p.width or 600, p.height or 400
  local band = Kit.Band(W)
  p.band = band
  if not (Panoply.Modules and Panoply.Modules:IsOn("alts")) then
    p.strip:Hide(); p.roster:Hide(); p.detail:Hide()
    p.off:SetText(H.WORDS.off)
    p.off:ClearAllPoints(); p.off:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -12); p.off:SetWidth(W - 12)
    p.off:SetHeight(TH(p.off, W - 12))
    p.off:Show()
    return
  end
  p.off:Hide()
  local sh = self:DrawStrip(p, W, band)
  local top = sh + SP.m
  local areaH = max(40, Hh - top - H.GRIP)
  local rw = band == "wide" and H.ROSTER_W or (band == "medium" and H.RAIL_W or 0)
  if rw > 0 then
    p.roster:ClearAllPoints(); p.roster:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -top)
    p.roster:SetSize(rw, areaH)
    p.roster:Show()
    local h = self:DrawRoster(p, rw, band)
    p.roster.content:SetSize(rw - 10, max(1, h))
    p.roster:SetContentHeight(h)
    if p.roster.UpdateBar then p.roster:UpdateBar() end
  else
    p.rcv:Begin()
    p.roster:Hide()
  end
  local gap = rw > 0 and SP.l or 0
  local dw = W - rw - gap
  p.detail:ClearAllPoints(); p.detail:SetPoint("TOPLEFT", p, "TOPLEFT", rw + gap, -top)
  p.detail:SetSize(dw, areaH)
  p.detail:Show()
  local inner = dw - 14
  local h = self:DrawDetail(p, inner, band)
  p.detail.content:SetSize(inner, max(1, h))
  p.detail:SetContentHeight(h + SP.s)
  if self.scrollTop then
    self.scrollTop = nil
    if p.detail.SetVerticalScroll then p.detail:SetVerticalScroll(0) end
  end
  if p.detail.UpdateBar then p.detail:UpdateBar() end
end

-- The account strip: gold and its change, counts, the Alerts chip, ?, then the search row
function H:DrawStrip(p, W, band)
  local s, cv = p.strip, p.scv
  cv:Begin()
  s:ClearAllPoints(); s:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  local pad = SP.m
  local inner = W - 2 * pad
  local now = Alts.Now()
  local gold, change = Alts:GoldChange(7)
  -- the right end of line 1: ? and the Alerts chip
  local x = W - pad - 16
  local Sh = Panoply.Sharing
  self.helpBody = Sh and Sh.MusterTip and Sh:MusterTip() or nil
  p.helpBtn = cv:Help(x, -pad - 2, "Muster", self.helpBody)
  local alerts = self:Alerts(nil)
  self.alertCount = #alerts
  local words = #alerts > 0 and ("Alerts " .. #alerts) or "Alerts"
  local chip, cw, ch = cv:Chip(0, 0, #alerts > 0 and "state.warn" or "state.idle", words)
  x = x - SP.s - cw
  chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", s, "TOPLEFT", x, -pad - 1)
  p.alertsChip = cv:Hot(x, -pad - 1, cw, ch, function() H:SetView("alerts") end, "Alerts",
    #alerts > 0 and "What needs you on your characters. Click to list them." or H.WORDS.noAlerts)
  p.alertsChip.chip = chip
  local rightW = W - pad - x
  -- the left of line 1: gold (a click opens the chart), then the counts
  local gw, gh, gfs = cv:Word(pad, -pad - 2, 14, "text.primary", H.Coins(gold, true), inner - rightW - SP.m, { name = true })
  local lx = pad + gw + SP.s
  local delta = H.ChangeText(change)
  local dwid = 0
  if delta then
    local w2 = cv:Word(lx, -pad - 4, 12, "text.primary", delta .. " " .. Skin.Code(Kit.Color("text.muted")) .. "7 days|r", max(40, inner - rightW - gw - SP.m))
    dwid = w2 + SP.s
  end
  p.goldBtn = cv:Hot(pad, -pad, gw + dwid + SP.s, max(gh, 18) + 4, function() H:SetView("chart") end, "Account gold",
    "Every character's gold together. Click for the last 30 days, character by character.", true)
  p.goldText = gfs
  local cx = lx + dwid
  local played = self:TotalPlayed(now)
  local bits = { ("%d %s"):format(self.count or 0, plural(self.count or 0, "character")) }
  if played > 0 then bits[#bits + 1] = Alts.Duration(played) .. " played" end
  local free = self:FreeSlots()
  bits[#bits + 1] = ("%d free bag %s"):format(free, plural(free, "slot"))
  local room = (x - SP.m) - cx
  local y1h = max(gh, 18)
  if room >= 120 then
    local _, _, cfs = cv:Word(cx, -pad - 4, 11, "text.muted", table.concat(bits, " · "), room)
    p.countText = cfs
  else
    local hh, cfs = cv:Text(pad, -pad - y1h - SP.xs, inner, 11, "text.muted", table.concat(bits, " · "))
    p.countText = cfs
    y1h = y1h + SP.xs + hh
  end
  -- line 2: the search box, Sort, and on Narrow the character dropdown
  local y2 = -pad - y1h - SP.s
  local ddW = 0
  p.charDD:Hide()
  if band == "narrow" then
    p.charDD:Fit(120, min(200, floor(inner * 0.45)))
    p.charDD:ClearAllPoints(); p.charDD:SetPoint("TOPLEFT", s, "TOPLEFT", pad, y2)
    p.charDD:Refresh()
    p.charDD:Show()
    ddW = p.charDD:GetWidth() + SP.s
  end
  p.sortBtn:Fit(110, 170)
  local sw = p.sortBtn:GetWidth()
  local boxRoom = inner - ddW - sw - SP.s
  local y2b = y2
  if boxRoom < 150 then
    -- too narrow for both on one row: the box gets its own row
    p.sortBtn:ClearAllPoints(); p.sortBtn:SetPoint("TOPLEFT", s, "TOPLEFT", pad + ddW, y2)
    y2b = y2 - 26 - SP.s
    boxRoom = inner
    p.box:ClearAllPoints(); p.box:SetPoint("TOPLEFT", s, "TOPLEFT", pad, y2b)
  else
    p.box:ClearAllPoints(); p.box:SetPoint("TOPLEFT", s, "TOPLEFT", pad + ddW, y2)
    p.sortBtn:ClearAllPoints(); p.sortBtn:SetPoint("TOPLEFT", s, "TOPLEFT", pad + ddW + min(320, boxRoom) + SP.s, y2)
  end
  local bw = min(320, boxRoom)
  p.box:SetWidth(floor(bw))
  p.box.placeholder:SetText(H.WORDS.search)
  if TW(p.box.placeholder) + 24 > bw then p.box.placeholder:SetText("Find an item") end
  p.sortBtn:Show(); p.box:Show()
  local hgt = -y2b + 26 + pad
  s:SetSize(W, hgt)
  s:Show()
  return hgt
end

-- Roster (Wide) or rail (Medium)
function H:DrawRoster(p, w, band)
  local cv = p.rcv
  cv:Begin()
  self.rows = {}
  local now, guess = Alts.Now(), Panoply.db.hallRestGuess ~= false
  local y = 0
  local inner = w - 10
  for _, g in ipairs(self.groups or {}) do
    -- realm and faction: one header each
    local byFaction, order = {}, {}
    for _, e in ipairs(g.chars) do
      local f = e.faction or "?"
      if not byFaction[f] then byFaction[f] = {} order[#order + 1] = f end
      table.insert(byFaction[f], e)
    end
    local myFaction = (C.PlayerInfo() or {}).faction
    table.sort(order, function(a, b)
      if (a == myFaction) ~= (b == myFaction) then return a == myFaction end
      return a < b
    end)
    for _, fac in ipairs(order) do
      local list = byFaction[fac]
      if band == "wide" then
        local slot = fac == "Horde" and "icon.faction.horde" or (fac == "Alliance" and "icon.faction.alliance" or nil)
        local tx = 4
        if slot then
          local t = cv:Tex(4, -y - 4, 14, 14)
          Kit.Icon(t, slot, { size = 14 })
          tx = 4 + 14 + SP.s
        end
        local gold = 0
        for _, e in ipairs(list) do gold = gold + e.money end
        local gwid = cv:Measure(11, "text.muted", H.Coins(gold, true), 100)
        local _, _, gfs = cv:Word(inner - gwid, -y - 5, 11, "text.muted", H.Coins(gold, true), 100)
        cv:Text(tx, -y - 4, inner - tx - gwid - SP.s, 12, "text.primary", g.realm, { name = true })
        y = y + H.GROUP_H
        for _, e in ipairs(list) do y = y + self:DrawRow(cv, e, y, inner, now, guess) end
      else
        for _, e in ipairs(list) do y = y + self:DrawRail(cv, e, y, inner, now, guess) end
      end
      y = y + SP.xs
    end
  end
  return y + SP.s
end

function H:RestOf(e, now, guess)
  if e.stub then return nil, false end
  return Alts.RestedPercent(e.rec, now, guess and not e.me)
end

-- the suite's selected-row look (Kit.List): a light gold wash under the row's words, so name, level, gold and zone stay readable
local function selectedLook(t)
  Skin.Solid(t, Skin.colors.highlight, 0.18)
  t.panoplyRowSelected = true
end

function H:DrawRow(cv, e, y, w, now, guess)
  local sel = self.cur and self:Key(self.cur) == self:Key(e)
  local row = cv:Hot(0, -y, w, H.ROW_H - 2, function(_, btn) H:Select(e.realm, e.name) end, e.name, nil, true)
  row.entry = e
  self.rows[#self.rows + 1] = row
  local bg
  if sel then
    bg = cv:Tex(0, -y, w, H.ROW_H - 2, "BACKGROUND")
    selectedLook(bg)
    row.panoplySelected = true
  end
  local cc = Alts.ClassColor(e.classFile)
  local ct = cv:Tex(6, -y - 4, 20, 20)
  crest(ct, e.classFile)
  local x = 32
  local moreX = w - 20
  local more = cv:More(moreX, -y - 2, 18, function() return H:MenuItems(e) end, "Forget this character, Set profile.")
  row.more = more
  local gold = H.Coins(e.money, true)
  local gw = cv:Measure(11, "text.primary", gold, 110)
  local _, gh = cv:Word(moreX - SP.xs - gw, -y - 5, 11, "text.primary", gold, 110)
  local alerts = self:Alerts(e)
  local dotW = 0
  if #alerts > 0 then
    local d = cv:Tex(moreX - SP.xs - gw - SP.s - 8, -y - 7, 8, 8)
    Kit.Icon(d, "icon.alert", { size = 8 })
    d.panoplyAlertDot = true
    row.dot = d
    dotW = 8 + SP.s
  end
  local lv = e.level and tostring(e.level) or "?"
  local nameRoom = moreX - SP.xs - gw - SP.s - dotW - x
  local lvw = cv:Measure(11, "text.muted", lv, 40)
  local nw, nh, nfs = cv:Word(x, -y - 3, 13, cc, e.name, max(20, nameRoom - lvw - SP.s), { name = true })
  row.nameText = nfs
  local _, lh = cv:Word(x + nw + SP.xs, -y - 5, 11, "text.muted", lv, 40)
  -- line 2 (under everything on line 1, at any text size): zone, or "Playing"
  local l2 = max(3 + nh, 5 + gh, 5 + lh) + 2
  local zx = x
  local zoneRoom = w - 4 - x
  local chipH = 0
  if e.me then
    local chip, cw2, ch2 = cv:Chip(0, 0, "state.good", "Playing")
    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", cv.frame, "TOPLEFT", w - 4 - cw2, -y - l2)
    row.playing = chip
    zoneRoom = zoneRoom - cw2 - SP.s
    chipH = ch2 or 0
  end
  local zone = e.stub and "Saved bags only" or ((e.rec.zone and e.rec.zone ~= "") and e.rec.zone or "Unknown place")
  local zh = cv:Text(zx, -y - l2, zoneRoom, 11, "text.muted", zone)
  local rh = max(H.ROW_H, l2 + max(zh, chipH) + 9)
  row:SetHeight(rh - 2)
  if bg then bg:SetHeight(rh - 2) end
  -- the rested bar
  local pct, guessed = self:RestOf(e, now, guess)
  local bar = cv:Bar(x, -y - rh + 6, w - 4 - x, 3, cc, (pct or 0) / Alts.RestCap(e.rec), nil)
  bar:SetAlpha(guessed and 0.6 or 1)
  local restWords = (pct and pct >= 1) and ("Rested " .. (guessed and "~" or "") .. floor(pct + 0.5) .. "%") or "Not rested"
  row.rest, row.restGuessed = restWords, guessed
  local bits = {}
  if e.level then bits[#bits + 1] = "Level " .. e.level end
  local rec = e.rec or {}
  if rec.race or rec.class then bits[#bits + 1] = ((rec.race or "") .. " " .. (rec.class or "")):gsub("^%s+", "") end
  bits[#bits + 1] = e.realm
  row.tipBody = table.concat(bits, ", ") .. ". " .. restWords .. (guessed and " (estimated)." or ".")
  return rh
end

function H:DrawRail(cv, e, y, w, now, guess)
  local rh = H.RAIL_H
  local sel = self.cur and self:Key(self.cur) == self:Key(e)
  local row = cv:Hot(0, -y, w, rh - 2, function() H:Select(e.realm, e.name) end, e.name, nil, true)
  row.entry = e
  self.rows[#self.rows + 1] = row
  if sel then
    selectedLook(cv:Tex(0, -y, w, rh - 2, "BACKGROUND"))
    row.panoplySelected = true
  end
  local ct = cv:Tex(floor((w - 26) / 2), -y - 3, 26, 26)
  crest(ct, e.classFile)
  local lv = e.level and tostring(e.level) or "?"
  local lw = cv:Measure(10, "text.primary", lv, w)
  cv:Word(floor((w - lw) / 2), -y - 31, 10, e.me and Kit.Color("state.good") or "text.primary", lv, w, { name = true })
  local alerts = self:Alerts(e)
  if #alerts > 0 then
    local d = cv:Tex(w - 10, -y - 2, 8, 8)
    Kit.Icon(d, "icon.alert", { size = 8 })
    d.panoplyAlertDot = true
    row.dot = d
  end
  local pct, guessed = self:RestOf(e, now, guess)
  local restWords = (pct and pct >= 1) and ("Rested " .. (guessed and "~" or "") .. floor(pct + 0.5) .. "%") or "Not rested"
  row.rest = restWords
  row.tipBody = ("Level %s%s. %s%s"):format(lv, e.me and ", playing now" or "", restWords, #alerts > 0 and (". " .. #alerts .. " " .. plural(#alerts, "alert")) or "")
  return rh
end

-------------------------------------------------------------------------------
-- The detail pane: a character, the search results, the alerts or the gold chart
-------------------------------------------------------------------------------
function H:DrawDetail(p, w, band)
  local cv = p.dcv
  cv:Begin()
  p.tabs:HideAll()
  if p.tabs.dd then p.tabs.dd:Hide() end
  p.grid:Hide()
  for _, c in ipairs(self.containers) do c:Hide() end
  for _, k in ipairs({ "askText", "yesBtn", "noBtn", "emptyText", "noneText", "foundHead", "craftHead", "backBtn", "restText", "whereText",
    "legacyBtn", "historyBtn", "detailName", "detailMore" }) do p[k] = nil end
  p.resultRows, p.craftRows, p.alertRows, p.letterRows, p.listingRows, p.profRows = {}, {}, {}, {}, {}, {}
  if self.view == "results" and #self.search >= Alts.SEARCH_MIN then return self:DrawResults(p, cv, w, band) end
  if self.view == "alerts" then return self:DrawAlertList(p, cv, w) end
  if self.view == "chart" then return self:DrawChart(p, cv, w) end
  self.view = "char"
  local e = self.cur
  if not e then
    local h = cv:Text(2, -SP.s, w - 4, 12, "text.muted", "No characters yet. Muster saves each one a few seconds after it logs in.", { wrap = true })
    return h + SP.l
  end
  local y = self:DrawCharHead(p, cv, e, w, band)
  if self.confirm == self:Key(e) then y = y + self:DrawConfirm(p, cv, e, y, w) end
  -- the tabs (Lockouts only with lockouts to show)
  p.tabs:SetShown("lockouts", self:LockoutsShown(e))
  if self.tab == "lockouts" and not self:LockoutsShown(e) then self.tab = "overview" end
  if p.tabs:Current() ~= self.tab then p.tabs:Select(self.tab, true) end
  local th = p.tabs:Layout(2, -y, w - 4, band == "narrow" and "dropdown" or nil)
  y = y + max(th, 24) + SP.m
  local tab = self.tab
  local h
  if tab == "overview" then h = self:DrawOverview(p, cv, e, y, w)
  elseif tab == "bags" or tab == "bank" then h = self:DrawBags(p, cv, e, y, w, tab)
  elseif tab == "mail" then h = self:DrawMail(p, cv, e, y, w)
  elseif tab == "gear" then h = self:DrawGear(p, cv, e, y, w, band)
  elseif tab == "professions" then h = self:DrawProfs(p, cv, e, y, w)
  elseif tab == "auctions" then h = self:DrawAuctions(p, cv, e, y, w)
  elseif tab == "lockouts" then h = self:DrawLockouts(p, cv, e, y, w) end
  return y + (h or 0) + SP.l
end

-- one line that says the tab has nothing (spec: empty states are one line)
local function emptyLine(cv, y, w, words)
  local h = cv:Text(4, -y, w - 8, 12, "text.muted", words)
  return h + SP.m
end

function H:DrawCharHead(p, cv, e, w, band)
  local rec = e.rec or {}
  local now = Alts.Now()
  local y = SP.xs
  local ct = cv:Tex(2, -y, 28, 28)
  crest(ct, e.classFile)
  local x = 2 + 28 + SP.m
  local more = cv:More(w - 22, -y, 20, function() return H:MenuItems(e) end, "Forget this character, Set profile.")
  p.detailMore = more
  local room = w - 22 - SP.s - x
  local nw, nh, nfs = cv:Word(x, -y, 16, Alts.ClassColor(e.classFile), e.name, room, { name = true })
  p.detailName = nfs
  if e.me then
    local chip, cw = cv:Chip(0, 0, "state.good", "Playing")
    chip:ClearAllPoints()
    if nw + SP.s + cw <= room then chip:SetPoint("TOPLEFT", cv.frame, "TOPLEFT", x + nw + SP.s, -y - 2) else chip:Hide() end
  end
  y = y + nh + 2
  local who = {}
  if e.level then who[#who + 1] = "Level " .. e.level end
  local rc = ((rec.race or "") .. " " .. (rec.class or "")):gsub("^%s+", ""):gsub("%s+$", "")
  if rc ~= "" then who[#who + 1] = rc end
  local line = table.concat(who, " ")
  if rec.spec then line = line .. " · " .. rec.spec end
  if e.realm ~= (Alts:Me()) then line = line .. " · " .. e.realm end
  local h1 = cv:Text(x, -y, room, 12, "text.muted", line ~= "" and line or e.realm)
  y = max(y + h1, SP.xs + 28) + SP.s
  if e.stub then
    local h = cv:Text(2, -y, w - 4, 12, "state.warn", e.me and H.WORDS.meSoon or H.WORDS.stub, { wrap = true })
    return y + h + SP.m
  end
  -- the XP bar, the rested part shaded (estimated for a character that is offline)
  local guess = Panoply.db.hallRestGuess ~= false
  local pct, guessed = self:RestOf(e, now, guess)
  if rec.xpMax and rec.xpMax > 0 then
    local bw = min(320, w - 4 - 120)
    local bar = cv:Bar(2, -y - 2, bw, 8, Alts.ClassColor(e.classFile), rec.xp or 0, rec.xpMax)
    local rest = pct and floor(rec.xpMax * pct / 100) or 0
    local restShown = min(rest, rec.xpMax - (rec.xp or 0))
    if restShown > 0 then
      local fx = floor(bw * (rec.xp or 0) / rec.xpMax)
      local r = cv:Tex(2 + fx, -y - 2, max(2, min(bw - fx, floor(bw * restShown / rec.xpMax))), 8)
      Skin.Solid(r, Alts.ClassColor(e.classFile), guessed and 0.22 or 0.35)
    end
    local words = (pct and pct >= 1) and ((guessed and "~" or "") .. floor(pct + 0.5) .. "% rested") or "Not rested"
    local _, _, rfs = cv:Word(2 + bw + SP.s, -y, 11, "text.muted", words, w - bw - 8)
    p.restText = rfs
    bar.tip = ("Level %d: %d of %d XP"):format(e.level or 0, rec.xp or 0, rec.xpMax)
    y = y + 12 + SP.s
  elseif e.level then
    p.restText = nil
  end
  local bits = {}
  local where = rec.zone and rec.zone ~= "" and (rec.zone .. ((rec.sub and rec.sub ~= "" and rec.sub ~= rec.zone) and (", " .. rec.sub) or "")) or nil
  if where then bits[#bits + 1] = where end
  if rec.hearth then bits[#bits + 1] = "Hearth: " .. rec.hearth end
  bits[#bits + 1] = e.me and "Playing now" or ("Last seen " .. Alts.Ago(e.t, now))
  local played = Alts.PlayedNow(e, now)
  if played then bits[#bits + 1] = "Played " .. Alts.Duration(played) end
  local h2, wfs = cv:Text(2, -y, w - 4, 11, "text.muted", table.concat(bits, " · "), { wrap = true })
  p.whereText = wfs
  return y + h2 + SP.m
end

function H:DrawConfirm(p, cv, e, y, w)
  local bits = self:ForgetList(e)
  local words = ("Forget %s? Panoply Suite deletes %s. Nothing in the game changes, and it comes back the next time you log in with it."):format(e.name,
    table.concat(bits, ", "))
  local h, fs = cv:Text(4, -y, w - 8, 12, "state.warn", words, { wrap = true })
  p.askText = fs
  local by = y + h + SP.s
  local yes, yw, yh = cv:Button(4, -by, "Yes, forget it", function() H:DoForget() end, "Yes, forget it", "Delete Panoply Suite's saved record of this character.", 110, 160)
  yes.panoplyDanger = true
  yes:Paint("up")
  local no = cv:Button(4 + yw + SP.s, -by, "Keep it", function() H.confirm = nil H:Refresh() end, "Keep it", "Do nothing.", 80, 120)
  p.yesBtn, p.noBtn = yes, no
  return h + SP.s + (yh or 24) + SP.m
end

-- Overview: professions, cooldowns, camp, Legacy, item level, this character's alerts
function H:DrawOverview(p, cv, e, y0, w)
  local rec = e.rec or {}
  local y = y0
  local now = Alts.Now()
  local function head(words)
    local h = cv:Text(2, -y, w - 4, 12, "text.primary", words, { name = true })
    y = y + h + SP.xs
  end
  -- professions as small skill bars
  local profs = {}
  for _, q in ipairs(rec.profs and rec.profs.prim or {}) do profs[#profs + 1] = q end
  for _, q in ipairs(rec.profs and rec.profs.sec or {}) do profs[#profs + 1] = q end
  p.profRows = {}
  if #profs > 0 then
    head("Professions")
    local lw = min(150, floor(w * 0.35))
    for _, q in ipairs(profs) do
      local nm, rk, mx = q[1] or "?", q[2] or 0, q[3] or 0
      local th = cv:Text(4, -y, lw, 11, "text.primary", nm)
      local nums = ("%d / %d"):format(rk, mx)
      local nw = cv:Measure(11, "text.muted", nums, 90)
      local bw = max(30, w - 8 - lw - SP.s - nw - SP.s)
      cv:Bar(4 + lw + SP.s, -y - 4, bw, 6, Kit.Accent("professions"), rk, mx > 0 and mx or 1)
      cv:Word(w - 4 - nw, -y, 11, "text.muted", nums, 90)
      local open = e.me and Panoply.ProfUI and Panoply.ProfUI.Show and Panoply.Catalog and Panoply.Catalog.professions
      local hot = cv:Hot(2, -y, w - 4, 16, open and function() note("professions") Panoply.ProfUI:Show(nm) end or nil,
        nm, open and ("%s %d of %d. Click for the Professions page."):format(nm, rk, mx) or ("%s %d of %d."):format(nm, rk, mx), open and true or nil)
      hot.profName = nm
      hot:SetHeight(max(16, th))
      p.profRows[#p.profRows + 1] = hot
      y = y + max(16, th) + 2
    end
    y = y + SP.s
  end
  -- cooldowns with the time left (as when it was last played)
  local cds = type(rec.cds) == "table" and rec.cds or {}
  if #cds > 0 then
    head("Cooldowns")
    for _, cd in ipairs(cds) do
      local left = (tonumber(cd.ready) or 0) - now
      local when = left <= 0 and "Ready" or ("Ready in " .. Alts.Duration(left))
      local ww = cv:Measure(11, left <= 0 and Kit.Color("state.good") or "text.muted", when, 140)
      local th = cv:Text(4, -y, w - 8 - ww - SP.s, 11, "text.primary", (cd.name or "?") .. (cd.prof and (" (" .. cd.prof .. ")") or ""))
      cv:Word(w - 4 - ww, -y, 11, left <= 0 and Kit.Color("state.good") or "text.muted", when, 140)
      y = y + max(15, th) + 1
    end
    y = y + SP.s
  end
  -- WoW Forever: trade camp and Legacy
  if C.IsForever() then
    local camp = type(rec.camp) == "table" and rec.camp
    if camp and (camp.favor or camp.rep) then
      head("Trade camp")
      local bits = {}
      if camp.favor then bits[#bits + 1] = ("Merchant's Favor %d"):format(camp.favor) end
      if camp.rep then bits[#bits + 1] = camp.rep .. ((camp.repMax and camp.repMax > 0) and (" %d / %d"):format(camp.repValue or 0, camp.repMax) or "") end
      local h = cv:Text(4, -y, w - 8, 11, "text.muted", table.concat(bits, " · "))
      y = y + h + SP.m
    end
    local L = Panoply.Legacy
    if L and L.Open then
      -- 0.9.5 phase 17 (spec 02 2.3): the Legacy challenges this character earned by itself (Legacy.lua L:EarnedBy)
      local earned = {}
      if L.EarnedBy then
        local okE, rows = pcall(L.EarnedBy, L, e.realm, e.name)
        if okE and type(rows) == "table" then earned = rows end
      end
      head("Legacy")
      local names = {}
      for i = 1, min(#earned, H.LEGACY_NAMES) do names[i] = earned[i].label end
      local line = #earned == 0 and H.WORDS.noLegacy
        or (("%d %s earned: "):format(#earned, plural(#earned, "challenge")) .. table.concat(names, ", ") .. (#earned > H.LEGACY_NAMES and (", and " .. (#earned - H.LEGACY_NAMES) .. " more") or ""))
      local lh = cv:Text(4, -y, w - 8, 11, "text.muted", line)
      p.legacyLine = line
      y = y + lh + SP.s
      local b, bw, bh = cv:Button(4, -y, "Legacy challenges", function() note("legacy") L:Open("challenges") end, "Legacy challenges",
        "The account's Legacy challenges, on the Legacy page.", 120, w - 8)
      p.legacyBtn = b
      y = y + bh + SP.m
    end
  end
  -- item level of what it wears
  if rec.ilvl then
    local h = cv:Text(4, -y, w - 8, 11, "text.muted", ("Item level %d (the average of what it wore)"):format(rec.ilvl))
    y = y + h + SP.m
  end
  -- this character's alerts, each a link
  local alerts = self:Alerts(e)
  p.alertRows = {}
  if #alerts > 0 then
    head("Alerts")
    y = y + self:AlertRows(p, cv, alerts, y, w, false)
  end
  if y == y0 then y = y + emptyLine(cv, y, w, "Nothing saved yet for this character.") end
  return y - y0
end

-- rows of alerts: each opens the character and tab it is about (Core/Alerts.lua's opener)
function H:AlertRows(p, cv, alerts, y0, w, withName)
  local y = y0
  p.alertRows = p.alertRows or {}
  for _, a in ipairs(alerts) do
    local d = cv:Tex(4, -y - 4, 8, 8)
    Kit.Icon(d, "icon.alert", { size = 8 })
    local h = cv:Text(4 + 8 + SP.s, -y, w - 12 - 8 - SP.s, 11, a.severity == "act" and "text.primary" or "text.muted", a.text or "?")
    local hot = cv:Hot(2, -y, w - 4, max(15, h), function()
      note("alert")
      if Panoply.Alerts and Panoply.Alerts.Open then Panoply.Alerts:Open(a) end
    end, a.text, a.detail, true)
    hot.alert = a
    p.alertRows[#p.alertRows + 1] = hot
    y = y + max(15, h) + 2
  end
  return y - y0 + SP.s
end

-- one container as a block: its name and type, free slots, the slots as squares (dimmed when they do not match a search)
function H:FillContainer(c, g, w, want)
  local S, G, cols = self.SLOT, self.SLOT_GAP, self.COLS
  local x0 = 4
  local fam = H.FamilyName(g.family)
  c.name:SetWidth(w - 2 * x0)
  Skin.Ellipsize(c.name, g.name:upper(), w - 2 * x0)
  c.name:ClearAllPoints(); c.name:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -2)
  c.used:SetWidth(w - 2 * x0)
  Skin.Ellipsize(c.used, ("%d free"):format(max(0, g.size - g.used)), w - 2 * x0)
  c.used:ClearAllPoints(); c.used:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -2 - TH(c.name, 9999) - 1)
  local y = 2 + TH(c.name, 9999) + 1 + TH(c.used, 9999)
  -- the bag's type (a quiver, a herb bag...) on a line of its own
  if fam then
    c.kind:SetWidth(w - 2 * x0)
    Skin.Ellipsize(c.kind, fam, w - 2 * x0)
    c.kind:ClearAllPoints(); c.kind:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y - 1)
    c.kind:Show()
    y = y + 1 + TH(c.kind, 9999)
  else c.kind:SetText("") c.kind:Hide() end
  y = y + SP.xs
  local rows = ceil(g.size / cols)
  local hits = 0
  for i = 1, max(g.size, #c.slots) do
    local s = c.slots[i]
    if i > g.size then if s then s:Hide() end
    else
      if not s then s = newSlot(c) c.slots[i] = s end
      local r, k = floor((i - 1) / cols), (i - 1) % cols
      s:ClearAllPoints(); s:SetPoint("TOPLEFT", c, "TOPLEFT", x0 + k * (S + G), -(y + r * (S + G)))
      local it = g.slots[i]
      s.item = it
      if it then
        Panoply.Icons:Apply(s.icon, it.itemID)   -- the game's own icon, or its "?"; never a guess
        s.icon:Show()
        if (it.count or 1) > 1 then s.count:SetText(tostring(it.count)) s.count:Show() else s.count:SetText("") s.count:Hide() end
        local q = it.quality or 1
        local col = (q >= 2 and C.QualityColor(q)) or Skin.colors.slotLine
        local match = want and Alts.SlotMatches(it, want)
        if match then hits = hits + 1; col = Skin.colors.highlight end
        s.rim:SetVertexColor(col[1], col[2], col[3], 1)
        s.panoplyMatch = match and true or nil
        local dim = want and not match
        s.icon:SetAlpha(dim and 0.25 or 1); s.rim:SetAlpha(dim and 0.35 or 1); s.count:SetAlpha(dim and 0.35 or 1)
        s:EnableMouse(true)
      else
        s.icon:Hide(); s.count:Hide()
        s.rim:SetVertexColor(Skin.colors.slotBottom[1], Skin.colors.slotBottom[2], Skin.colors.slotBottom[3], 1)
        s.rim:SetAlpha(want and 0.4 or 1)
        s.panoplyMatch = nil
        s:EnableMouse(false)
      end
      s:Show()
    end
  end
  y = y + rows * (S + G) + SP.xs
  c:SetHeight(y)
  c.hits = hits
  return y
end

function H:DrawBags(p, cv, e, y0, w, where)
  local y = y0
  local grids, stamp = self:GridOf(e, where)
  local want = (#self.search >= Alts.SEARCH_MIN) and self.search or nil
  if stamp and not (e.me and where == "bags") then
    local h = cv:Text(4, -y, w - 8, 11, "text.muted", "As of " .. Alts.Ago(stamp, Alts.Now()))
    y = y + h + SP.s
  end
  if want then
    local h = cv:Text(4, -y, w - 8, 11, "state.warn", ("Showing what matches \"%s\"."):format(want))
    y = y + h + SP.s
  end
  if #grids == 0 then
    local msg
    if where == "bank" then msg = stamp and "Nothing in the bank." or "Not saved yet: visit a banker with it once."
    else msg = stamp and "Nothing in the bags." or "Not saved yet: open its bags once." end
    if not (Panoply.Inventory and Panoply.Inventory:Enabled()) then msg = H.WORDS.bagsOff end
    p.emptyText = select(2, cv:Text(4, -y, w - 8, 12, "text.muted", msg))
    return y - y0 + 16 + SP.m
  end
  p.emptyText = nil
  local cwid = self.COLS * (self.SLOT + self.SLOT_GAP) - self.SLOT_GAP + 8
  local perRow = max(1, floor((w + SP.m) / (cwid + SP.m)))
  local rowTop, rowH, col = y, 0, 0
  for i, g in ipairs(grids) do
    local c = self.containers[i]
    if not c then c = newContainer(p.detail.content) self.containers[i] = c end
    c:SetWidth(cwid)
    local h = self:FillContainer(c, g, cwid, want)
    if col >= perRow then rowTop = rowTop + rowH + SP.m; rowH, col = 0, 0 end
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", p.detail.content, "TOPLEFT", 2 + col * (cwid + SP.m), -rowTop)
    c:Show()
    rowH = max(rowH, h)
    col = col + 1
  end
  return rowTop + rowH + SP.m - y0
end

-- Mail: one row a letter (sender, subject, attachments, money, COD, days left); a save from before 0.9.5 has only the items
function H:DrawMail(p, cv, e, y0, w)
  local m = e.rec and e.rec.mail
  local y = y0
  p.letterRows = {}
  if not m then return emptyLine(cv, y, w, H.WORDS.mailNotSeen) end
  local now = Alts.Now()
  local h0 = cv:Text(4, -y, w - 8, 11, "text.muted", "As of " .. Alts.Ago(m.t, now) .. ((m.money or 0) > 0 and (" · Gold waiting: " .. H.Coins(m.money)) or ""))
  y = y + h0 + SP.s
  local letters = type(m.letters) == "table" and m.letters or nil
  if letters then
    if #letters == 0 then return y - y0 + emptyLine(cv, y, w, H.WORDS.noMail) end
    local warnDays = Panoply.Alerts and Panoply.Alerts.MailDays and Panoply.Alerts.MailDays() or 3
    for _, l in ipairs(letters) do
      local rowY = y
      local icon = cv:Tex(4, -y, 20, 20)
      local first = type(l.items) == "table" and l.items[1]
      if first then Panoply.Icons:Apply(icon, first) else Panoply.Icons:Release(icon) Kit.Icon(icon, "icon.mail", { size = 20 }) end
      local x = 4 + 20 + SP.s
      -- the right end: days left, COD, money
      local rx = w - 4
      local days = l.expires and (l.expires - now) / 86400 or nil
      if days then
        -- 0.9.5 phase 17: a letter whose time is up (an alt not played for days) went back or was deleted: muted, not "< 1 day" in red
        local gone = days <= 0
        local dw = gone and H.WORDS.mailRanOut or days < 1 and "< 1 day" or (floor(days) .. " " .. plural(floor(days), "day"))
        local col = (not gone and days < warnDays) and Kit.Color("state.bad") or Kit.Color("text.muted")
        local ww = cv:Measure(11, col, dw, 80)
        rx = rx - ww
        cv:Word(rx, -y - 1, 11, col, dw, 80)
        rx = rx - SP.s
      end
      if (l.cod or 0) > 0 then
        local chip, cw = cv:Chip(0, 0, "state.bad", "COD " .. H.Coins(l.cod, true))
        rx = rx - cw
        chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", cv.frame, "TOPLEFT", rx, -y)
        rx = rx - SP.s
      end
      if (l.money or 0) > 0 then
        local mw = cv:Measure(11, "text.primary", H.Coins(l.money, true), 120)
        rx = rx - mw
        cv:Word(rx, -y - 1, 11, "text.primary", H.Coins(l.money, true), 120)
        rx = rx - SP.s
      end
      local h1 = cv:Text(x, -y, rx - x, 12, "text.primary", l.from or "?", { name = true })
      local h2 = cv:Text(x, -y - h1, w - 4 - x, 11, "text.muted", l.subject or "")
      y = y + max(20, h1 + h2)
      -- attachments as icons
      local items = type(l.items) == "table" and l.items or {}
      if #items > 1 then
        y = y + 2
        local per = max(1, floor((w - x) / 18))
        for i, id in ipairs(items) do
          local r, k = floor((i - 1) / per), (i - 1) % per
          local t = cv:Tex(x + k * 18, -y - r * 18, 16, 16)
          Panoply.Icons:Apply(t, id)
        end
        y = y + ceil(#items / per) * 18
      end
      local hot = cv:Hot(2, -rowY, w - 4, y - rowY, nil, l.subject or "Letter", ("From %s."):format(l.from or "?"))
      hot.letter = l
      p.letterRows[#p.letterRows + 1] = hot
      y = y + SP.s
    end
    if (m.total or 0) > (m.n or 0) then
      local h = cv:Text(4, -y, w - 8, 11, "text.muted", ("Only %d of %d letters were showing."):format(m.n or 0, m.total))
      y = y + h + SP.s
    end
    return y - y0
  end
  -- before 0.9.5: the items only, packed in a box
  local grids = self:GridOf(e, "mail")
  if #grids == 0 then return y - y0 + emptyLine(cv, y, w, H.WORDS.noMail) end
  return y - y0 + self:DrawBagsFrom(p, grids, y, w)
end
function H:DrawBagsFrom(p, grids, y0, w)
  local want = (#self.search >= Alts.SEARCH_MIN) and self.search or nil
  local cwid = self.COLS * (self.SLOT + self.SLOT_GAP) - self.SLOT_GAP + 8
  local perRow = max(1, floor((w + SP.m) / (cwid + SP.m)))
  local rowTop, rowH, col = y0, 0, 0
  for i, g in ipairs(grids) do
    local c = self.containers[i]
    if not c then c = newContainer(p.detail.content) self.containers[i] = c end
    c:SetWidth(cwid)
    local h = self:FillContainer(c, g, cwid, want)
    if col >= perRow then rowTop = rowTop + rowH + SP.m; rowH, col = 0, 0 end
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", p.detail.content, "TOPLEFT", 2 + col * (cwid + SP.m), -rowTop)
    c:Show()
    rowH = max(rowH, h)
    col = col + 1
  end
  return rowTop + rowH + SP.m - y0
end

-- Gear: the paper doll with the At your level slot component (UI/SlotGrid.lua). For the character being played: the one gear
-- engine's answer through At your level (the same cells, so the same best item on both pages); a click opens that slot there.
function H:GearCells(e)
  local AL = Panoply.AtLevel
  if e.me and AL and AL.Grid and AL.Available and AL:Available() and Panoply.GearRules and Panoply.GearRules.classes[e.classFile or ""] then
    local ok, grid = pcall(AL.Grid, AL, nil, nil)
    if ok and type(grid) == "table" then
      local cells = {}
      for _, cell in ipairs(grid.cells) do
        local v = AL.CellView(cell, true)
        if cell.worn and cell.worn.ilvl and v.state ~= "up" then v.value = ("ilvl %d"):format(cell.worn.ilvl) end
        cells[#cells + 1] = v
      end
      return cells, grid, true
    end
  end
  local gear = e.rec and type(e.rec.gear) == "table" and e.rec.gear
  if not gear then return nil end
  local G, AL2 = Panoply.Gear, Panoply.AtLevel
  local paper = AL2 and AL2.PAPER or { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket", "mainhand", "offhand", "ranged" }
  local cells = {}
  for _, key in ipairs(paper) do
    local slot = G and G.SLOTS and G.SLOTS[key]
    local ids = slot and slot.ids or {}
    local links = {}
    for _, sid in ipairs(ids) do if gear[sid] then links[#links + 1] = gear[sid] end end
    local v = { key = key, label = slot and slot.label or key, state = "none" }
    if links[1] then
      local i = C.ItemInfo(links[1])
      v.icon = C.ItemIcon(links[1]) or Skin.UNKNOWN_ITEM
      v.item = links[1]          -- the slot grid paints the picture again when the game sends the item (UI/SlotGrid.lua)
      v.quality = i and i.quality
      v.value = (i and i.ilvl) and ("ilvl %d"):format(i.ilvl) or "Worn"
      local lines = {}
      for _, l in ipairs(links) do
        local ii = C.ItemInfo(l)
        lines[#lines + 1] = ii and ii.name and (("|cff%s%s|r"):format(Panoply.AtLevel and Panoply.AtLevel.QUALITY_COLOR and Panoply.AtLevel.QUALITY_COLOR[ii.quality or 1] or "ffffff", ii.name)
          .. (ii.ilvl and (" (item level %d)"):format(ii.ilvl) or "")) or (l:match("|h%[(.-)%]|h") or "An item the game has not shown yet")
      end
      v.tip, v.tipBody = v.label, table.concat(lines, "\n")
    else
      v.value = "Empty"
      v.tip, v.tipBody = v.label, "Nothing worn here."
    end
    cells[#cells + 1] = v
  end
  return cells, nil, false
end
function H:GearClick(key)
  local e = self.cur
  if not (e and e.me) then return end
  local AL = Panoply.AtLevel
  if not (AL and AL.SelectSlot) then return end
  note("atlevel")
  Menu:Open("atlevel")
  AL:SelectSlot(key)
end
function H:DrawGear(p, cv, e, y0, w, band)
  local y = y0
  local cells, grid, mine = self:GearCells(e)
  if not cells then return emptyLine(cv, y, w, e.me and "The game has not said yet what you wear." or H.WORDS.noGear) end
  local rec = e.rec or {}
  local bits = {}
  if rec.ilvl then bits[#bits + 1] = ("Item level %d"):format(rec.ilvl) end
  if mine and grid then
    if grid.now and grid.now > 0 then bits[#bits + 1] = ("Upgrades for %d %s on At your level: click a slot"):format(grid.now, plural(grid.now, "slot")) end
    if grid.weighedFor then bits[#bits + 1] = "Weighed for " .. grid.weighedFor end
  end
  if #bits > 0 then
    local h = cv:Text(4, -y, w - 8, 11, "text.muted", table.concat(bits, " · "), { wrap = true })
    y = y + h + SP.s
  end
  p.grid:Set(cells)
  local cols = Kit.SlotGridColumns(w - 4)
  local gh = p.grid:Layout(2, -y, w - 4, cols)
  self.gearCells = cells
  return y + gh + SP.m - y0
end

function H:DrawProfs(p, cv, e, y0, w)
  local rec = e.rec or {}
  local y = y0
  local profs = {}
  for _, q in ipairs(rec.profs and rec.profs.prim or {}) do profs[#profs + 1] = q end
  for _, q in ipairs(rec.profs and rec.profs.sec or {}) do profs[#profs + 1] = q end
  if #profs == 0 then return emptyLine(cv, y, w, "No professions.") end
  local recipes = type(rec.recipes) == "table" and rec.recipes or {}
  for _, q in ipairs(profs) do
    local nm, rk, mx = q[1] or "?", q[2] or 0, q[3] or 0
    local nw, nh = cv:Word(4, -y, 13, "text.primary", nm, floor(w * 0.5), { name = true })
    local _, rh = cv:Word(4 + nw + SP.s, -y - 2, 11, "text.muted", H.RankName(mx), 120)
    local nums = ("%d / %d"):format(rk, mx)
    local numW = cv:Measure(11, "text.muted", nums, 90)
    local _, mh = cv:Word(w - 4 - numW, -y - 2, 11, "text.muted", nums, 90)
    y = y + max(nh, rh + 2, mh + 2) + 2
    cv:Bar(4, -y, w - 8, 6, Kit.Accent("professions"), rk, mx > 0 and mx or 1)
    y = y + 6 + SP.xs
    local list = recipes[nm]
    local words = type(list) == "table" and ("%d %s known"):format(#list, plural(#list, "recipe"))
      or "Recipes not saved yet: open the profession window once with it."
    local h = cv:Text(4, -y, w - 8, 11, "text.muted", words)
    y = y + h + SP.m
  end
  return y - y0
end

-- Auctions: what it still has listed (the Auctions history, spec 01 7.3), and what did not sell, waiting in the mail
function H:DrawAuctions(p, cv, e, y0, w)
  local y = y0
  local list = Alts:Listings(e)
  local now = Alts.Now()
  p.listingRows = {}
  local hist = Panoply.Auctions and Panoply.Auctions.View and Panoply.Catalog and Panoply.Catalog.auctions
  if hist then
    local b, bw, bh = cv:Button(4, -y, "Auction history", function() H:OpenAuctionHistory(e) end, "Auction history",
      ("What %s bought, sold and listed, on the Auctions page."):format(e.name), 110, w - 8)
    p.historyBtn = b
    y = y + bh + SP.m
  end
  if #list == 0 then y = y + emptyLine(cv, y, w, H.WORDS.noAuctions)
  else
    for _, l in ipairs(list) do
      local icon = cv:Tex(4, -y, 18, 18)
      Panoply.Icons:Apply(icon, l.id)
      local left = (l.ends or 0) - now
      local when = (l.hours or 0) == 0 and "" or (left > 0 and (Alts.Duration(left) .. " left") or "Ended")
      local ww = when ~= "" and cv:Measure(11, "text.muted", when, 110) or 0
      local price = (l.buyout or 0) > 0 and H.Coins(l.buyout, true) or ((l.bid or 0) > 0 and ("bid " .. H.Coins(l.bid, true)) or "")
      local pw = price ~= "" and cv:Measure(11, "text.primary", price, 130) or 0
      local rx = w - 4
      if ww > 0 then rx = rx - ww cv:Word(rx, -y, 11, "text.muted", when, 110) rx = rx - SP.s end
      if pw > 0 then rx = rx - pw cv:Word(rx, -y, 11, "text.primary", price, 130) rx = rx - SP.s end
      local nm = l.name or (Alts:ItemName(l.id)) or ("Item " .. tostring(l.id))
      cv:Text(4 + 18 + SP.s, -y, rx - (4 + 18 + SP.s), 12, "text.primary", nm .. (((l.stack or 1) > 1) and (" x" .. l.stack) or ""))
      local hot = cv:Hot(2, -y, w - 4, 18, nil, nm, ("Listed %s."):format(Alts.Ago(l.t, now)))
      hot.listing = l
      p.listingRows[#p.listingRows + 1] = hot
      y = y + 18 + 2
    end
    y = y + SP.s
  end
  -- did not sell: the auction house's letters waiting in the mail (as of the last mailbox visit)
  local m = e.rec and e.rec.mail
  local back = {}
  for _, l in ipairs(m and type(m.letters) == "table" and m.letters or {}) do
    if l.ah == "expired" then for _, id in ipairs(l.items or {}) do back[#back + 1] = id end end
  end
  if #back > 0 then
    local h = cv:Text(2, -y, w - 4, 12, "text.primary", "Did not sell, waiting in the mail", { name = true })
    y = y + h + SP.xs
    for _, id in ipairs(back) do
      local icon = cv:Tex(4, -y, 16, 16)
      Panoply.Icons:Apply(icon, id)
      cv:Text(4 + 16 + SP.s, -y, w - 8 - 16 - SP.s, 11, "text.primary", (Alts:ItemName(id)) or ("Item " .. id))
      y = y + 18
    end
    y = y + SP.s
  end
  return y - y0
end
function H:OpenAuctionHistory(e)
  local V = Panoply.Auctions and Panoply.Auctions.View
  if not V then return end
  note("auctions")
  V.state.tab = "history"
  V.state.char = e and e.name or nil
  Menu:Open("auctions")
  if V.RefreshAll then pcall(V.RefreshAll, V) end
end

function H:DrawLockouts(p, cv, e, y0, w)
  local y = y0
  local now = Alts.Now()
  local list = e.rec and type(e.rec.lockouts) == "table" and e.rec.lockouts or {}
  local any = false
  for _, l in ipairs(list) do
    local left = (l.reset or 0) - now
    if left > 0 then
      any = true
      local when = "Resets in " .. Alts.Duration(left)
      local ww = cv:Measure(11, "text.muted", when, 140)
      local th = cv:Text(4, -y, w - 8 - ww - SP.s, 12, "text.primary", l.name or "?")
      cv:Word(w - 4 - ww, -y - 1, 11, "text.muted", when, 140)
      y = y + max(17, th) + 1
    end
  end
  if not any then return emptyLine(cv, y, w, H.WORDS.noLockouts) end
  return y - y0 + SP.s
end

-- Search results (spec 02 2.3): one row an item, where every copy is, then "Who can craft"
function H:DrawResults(p, cv, w, band)
  local y = SP.xs
  local cur = self.cur
  local back, bw, bh = cv:Button(2, -y, cur and ("Back to " .. cur.name) or "Back", function() H:BackToCharacter() end, "Back",
    "Clear the search and show the character again.", 90, w - 4)
  p.backBtn = back
  y = y + bh + SP.m
  local want = self.search
  local found, more = Alts:Search(want)
  found = found or {}
  local hh, headFs = cv:Text(2, -y, w - 4, 13, "text.primary", ("Looking for \"%s\""):format(want), { name = true })
  p.foundHead = headFs
  y = y + hh + SP.s
  p.resultRows = {}
  if #found == 0 then
    local h, fs = cv:Text(4, -y, w - 8, 12, "text.muted", H.WORDS.noMatch)
    p.noneText = fs
    y = y + h + SP.m
  else
    p.noneText = nil
    local meRealm = Alts:Me()
    for i, r in ipairs(found) do
      if i > H.MAX_RESULTS then break end
      local rowY = y
      local icon = cv:Tex(4, -y, 20, 20)
      Panoply.Icons:Apply(icon, r.itemID)
      local x = 4 + 20 + SP.s
      local tw = cv:Measure(12, "text.primary", tostring(r.total), 60)
      cv:Word(w - 4 - tw, -y, 12, "text.primary", tostring(r.total), 60)
      local qc = (r.quality and r.quality >= 0 and Panoply.AtLevel and Panoply.AtLevel.QUALITY_COLOR and Panoply.AtLevel.QUALITY_COLOR[r.quality]) or nil
      local nm = qc and ("|cff%s%s|r"):format(qc, r.name) or r.name
      local h1 = cv:Text(x, -y, w - 4 - tw - SP.s - x, 12, "text.primary", nm, { name = true })
      local parts = {}
      for _, pp in ipairs(r.parts) do
        local who = pp.name .. ((meRealm and pp.realm ~= meRealm) and (" - " .. pp.realm) or "")
        parts[#parts + 1] = Alts.ColorCode(Alts.ClassColor(pp.classFile)) .. who .. "|r — " .. Alts.WhereText(pp)
      end
      local h2 = cv:Text(x, -y - h1, w - 4 - x, 11, "text.muted", table.concat(parts, " · "), { wrap = true })
      y = y + max(20, h1 + h2)
      -- a click on the row shows the first character that has it, on the tab where it is, with the search still dimming the rest
      local first = r.parts[1]
      local tab = first and ((first.bags > 0 and "bags") or (first.bank > 0 and "bank") or (first.mail > 0 and "mail") or (first.worn > 0 and "gear") or "auctions")
      local hot = cv:Hot(2, -rowY, w - 4, y - rowY, function()
        if first then H.sel = { realm = first.realm, name = first.name } H.tab = tab H.view = "char" note("result") H:Refresh() end
      end, r.name, Alts:ResultText(r, false) .. ".", true)
      hot.result = r
      p.resultRows[#p.resultRows + 1] = hot
      y = y + SP.s
    end
    local extra = max(more or 0, #found - H.MAX_RESULTS)
    if extra > 0 then
      local h = cv:Text(4, -y, w - 8, 11, "text.muted", ("And %d more. Type more of the name to narrow it down."):format(extra))
      y = y + h + SP.s
    end
  end
  -- Who can craft
  local crafts = Alts:WhoCanCraft(want)
  p.craftRows = {}
  if #crafts > 0 then
    y = y + SP.s
    local h, cfs = cv:Text(2, -y, w - 4, 13, "text.primary", "Who can craft", { name = true })
    p.craftHead = cfs
    y = y + h + SP.s
    for _, c in ipairs(crafts) do
      local names = {}
      for _, wh in ipairs(c.who) do names[#names + 1] = Alts.ColorCode(Alts.ClassColor(wh.classFile)) .. wh.name .. "|r" end
      local icon = cv:Tex(4, -y, 16, 16)
      if c.makes then Panoply.Icons:Apply(icon, c.makes) else Panoply.Icons:Release(icon) Kit.Icon(icon, "icon.page.muster", { size = 16 }) end
      local h3, fs = cv:Text(4 + 16 + SP.s, -y, w - 8 - 16 - SP.s, 11, "text.primary", ("%s (%s): %s"):format(c.recipe, c.profession, table.concat(names, ", ")), { wrap = true })
      p.craftRows[#p.craftRows + 1] = fs
      y = y + max(16, h3) + 2
    end
  else p.craftHead = nil end
  return y + SP.m
end

-- The alerts list (the strip's chip): every character's, each opening the character and tab it is about
function H:DrawAlertList(p, cv, w)
  local y = SP.xs
  local back, _, bh = cv:Button(2, -y, self.cur and ("Back to " .. self.cur.name) or "Back", function() H:SetView("char") end, "Back", "Show the character again.", 90, w - 4)
  p.backBtn = back
  y = y + bh + SP.m
  local h = cv:Text(2, -y, w - 4, 13, "text.primary", "Alerts", { name = true })
  y = y + h + SP.s
  local alerts = self:Alerts(nil)
  p.alertRows = {}
  if #alerts == 0 then return y + emptyLine(cv, y, w, H.WORDS.noAlerts) end
  return y + self:AlertRows(p, cv, alerts, y, w, true) + SP.m
end

-- The 30-day gold chart, stacked by character (the biggest H.CHART_SERIES each a colour; the rest together)
function H:DrawChart(p, cv, w)
  local y = SP.xs
  local back, _, bh = cv:Button(2, -y, self.cur and ("Back to " .. self.cur.name) or "Back", function() H:SetView("char") end, "Back", "Show the character again.", 90, w - 4)
  p.backBtn = back
  y = y + bh + SP.m
  local h = cv:Text(2, -y, w - 4, 13, "text.primary", "Gold, last 30 days", { name = true })
  y = y + h + SP.s
  local s = Alts:GoldSeries(H.CHART_DAYS)
  self.chart = s
  local top = 0
  for _, v in ipairs(s.totals) do if v > top then top = v end end
  local _, change = Alts:GoldChange(7)
  local bits = { "Now " .. H.Coins(s.totals[#s.totals] or 0, true) }
  local ct = H.ChangeText(change)
  if ct then bits[#bits + 1] = ct .. " in 7 days" end
  local h2 = cv:Text(2, -y, w - 4, 11, "text.muted", table.concat(bits, " · "))
  y = y + h2 + SP.s
  local cw, chh = w - 8, H.CHART_H
  local n = #s.days
  local bw = max(2, floor((cw - (n - 1) * 2) / n))
  local base = y + chh
  local series = {}
  for i, ser in ipairs(s.series) do if i <= H.CHART_SERIES then series[#series + 1] = ser end end
  local rest = { name = "Others", values = {} }
  for i = H.CHART_SERIES + 1, #s.series do
    for d = 1, n do rest.values[d] = (rest.values[d] or 0) + (s.series[i].values[d] or 0) end
  end
  if #s.series > H.CHART_SERIES then series[#series + 1] = rest end
  local axis = cv:Tex(4, -base, cw, 1)
  Skin.Solid(axis, Kit.Color("rule"), 0.5)
  for d = 1, n do
    local acc = 0
    local x = 4 + (d - 1) * (bw + 2)
    for _, ser in ipairs(series) do
      local v = ser.values[d] or 0
      if v > 0 and top > 0 then
        local hpx = max(1, floor(chh * v / top))
        local bottom = floor(chh * acc / top)
        local t = cv:Tex(x, -(base - bottom - hpx), bw, hpx)
        local col = ser.classFile and Alts.ClassColor(ser.classFile) or Kit.Color("text.muted")
        Skin.Solid(t, col, 0.9)
        acc = acc + v
      end
    end
    local hot = cv:Hot(x, -y, bw + 2, chh, nil, date and date("%b %d", s.days[d] * 86400) or ("Day " .. d),
      "All characters: " .. H.Coins(s.totals[d] or 0, true))
  end
  y = base + SP.xs
  local lw = cv:Measure(10, "text.muted", "Today", 80)
  cv:Word(4, -y, 10, "text.muted", "30 days ago", 120)
  local _, th = cv:Word(4 + cw - lw, -y, 10, "text.muted", "Today", 80)
  y = y + max(14, th) + SP.m
  -- the legend: one line a character, its colour, its gold now
  for _, ser in ipairs(series) do
    local sw = cv:Tex(4, -y - 3, 8, 8)
    Skin.Solid(sw, ser.classFile and Alts.ClassColor(ser.classFile) or Kit.Color("text.muted"), 0.9)
    local gw = cv:Measure(11, "text.primary", H.Coins(ser.values[n] or 0, true), 120)
    cv:Word(w - 4 - gw, -y, 11, "text.primary", H.Coins(ser.values[n] or 0, true), 120)
    local th = cv:Text(4 + 8 + SP.s, -y, w - 8 - 8 - SP.s - gw - SP.s, 11, "text.primary", ser.name .. (ser.realm and ser.realm ~= (Alts:Me()) and (" - " .. ser.realm) or ""))
    y = y + max(15, th) + 1
  end
  return y + SP.m
end

-------------------------------------------------------------------------------
-- Opening and closing (the page of the one window)
-------------------------------------------------------------------------------
function Alts:Open(realm, name, tab)
  if not self.active then
    Panoply:Print("Muster is off. Turn it on with the switch at the top of its page (Muster).")
    Menu:Open("hall")
    return false
  end
  self:Collect()          -- this character is up to date the moment the page opens
  if realm and name then H.sel = { realm = realm, name = name } H.view = "char" H.confirm = nil end
  if tab and H.TAB_TIPS[tab] then H.tab = tab end
  Menu:Open("hall")
  H:Refresh()
  return true
end
function Alts:Hide() end
function Alts:Toggle()
  if Menu.frame and Menu.frame:IsShown() and Menu.current == "hall" then Menu:Hide() else self:Open() end
end

-- looting fires INVENTORY_CHANGED every third of a second: redraw once a moment, only while it is open
function H:RefreshSoon()
  if not (Menu.frame and Menu.frame:IsShown() and Menu.current == "hall") or self.soon then return end
  self.soon = true
  C.After(0.3, function() H.soon = false H:Refresh() end)
end
Panoply:Listen("ALTS_CHANGED", function() if Alts.active then H:RefreshSoon() end end)
Panoply:Listen("INVENTORY_CHANGED", function() if Alts.active then H:RefreshSoon() end end)
Panoply:Listen("OPTION_CHANGED", function(key)
  if key == "hallRestGuess" or key == "hallSort" or key == "hallMailDays" then H:Refresh() end
end)

-- /hearthhall opens it, /hearthhall linen opens it already searching ("/panoply muster ..." is the same)
function Alts:Slash(arg)
  arg = tostring(arg or ""):match("^%s*(.-)%s*$")
  if not self.active then Panoply:Print("Muster is off. Turn it on with the switch at the top of its page (Muster).") Menu:Open("hall") return end
  if arg ~= "" then
    self:Open()
    if H.box then H.box:SetText(arg) if H.box.placeholder then H.box.placeholder:Hide() end end
    H:SetSearch(arg, true)
  else
    self:Toggle()
  end
end
_G.SLASH_HEARTHPATHHALL1 = "/hearthhall"
if _G.SlashCmdList then _G.SlashCmdList.HEARTHPATHHALL = function(msg) Alts:Slash(msg) end end

-- the Help page lists the command: registered with the others in Core/Slash.lua (key "muster", module "alts"; 0.9.5 phase 4A4)
