-- Panoply Suite 0.9.5 phase 4H: the Class page (docs/specs/page-redesigns-03-class.md, 03a and 05a). Class & Spec and the Class Guide
-- are one page; this file is its frame: the header, the plan and "Written for" controls, the tabs, reading another class, and the
-- Overview and How to play tabs. Talents, Spells and Gear are Page*.lua beside this file; Pet is Modules/HunterPet/PetTab.lua.
--
--   Window header   the class crest and the class's name ("Hunter"); under it "Talon · level 15 · Beast Mastery" (Menu.headerTitle).
--   Pinned strip    [Spec 1 | Spec 2] (WoW Forever, level 40 and up, second spec bought)  Plan: Beast Mastery leveling ▾  ...  (New plan,
--                   Duplicate, Rename, Delete)   Written for: New to the game ▾   ... (Read about another class; Reset this page).
--                   The plan drives the talent tree, the spells list, the gear weights and the rotation text, and is chosen nowhere else.
--                   "Saved as your own copy. Undo" under it after a ready-made plan was edited (Modules/SpecTrainer/PlanModel.lua).
--                   Reading another class: "Reading: Mage. Back to my Hunter", and only Overview and How to play show.
--   Tabs            Overview · Talents · Spells · How to play · Gear · Pet (Pet for a class with a pet system Panoply Suite has data for).
--                   Narrow: one dropdown. Only the part under the tabs scrolls (Talents fills it and scrolls inside).
--   Overview        first run on a character (setup skipped or never run, an answer missing): a two-question card (how much have you
--                   played; pick a plan). Then: Now (up to five rows, each one action with a link to its tab) and About your class.
--   How to play     a section index on the left (a dropdown at the top below the Wide band): Leveling, What to press (with the next
--                   ability display and your own rotations), the class's spells, Macros, Group play. Text is chosen by Written for.
--
-- Combat: the next ability display's card is made only out of combat, as before (Sequencer.lua); a tab never creates a frame in a fight.
-- Nothing here casts, buys, spends or changes a talent: buttons change what the page shows, the plan, or add a waypoint.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Page = { GRIP = 22, BTN = 20, NOW_MAX = 5, INDEX_W = 190 }
CP.Page = Page
CP.PANEL_MIN_H = 200
CP.TABS = {}           -- tab key -> { Draw = function(p, holder, w, viewH, v) return height, fill end, Sig = function(v, w) return "..." end }

local function ST() return Panoply.SpecTrainer end
local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end

-------------------------------------------------------------------------------
-- Small measured pieces, shared by the Class page's tab files (CP.UI)
-------------------------------------------------------------------------------
local U = {}
CP.UI = U
local PAD = 12

-- one line (or a wrapped block) of text at (x, y) of parent, w wide: returns its height and the font string
function U.Text(parent, x, y, w, size, token, words, wrap, name)
  local fs = name and Skin.Name(parent, size or 12, Kit.Color(token or "text.primary")) or Skin.Ink(parent, size or 12, Kit.Color(token or "text.muted"))
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  w = max(10, w)
  fs:SetWidth(w)
  if wrap then
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(words or "")
  else
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    Skin.Ellipsize(fs, words or "", w)
  end
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  return h, fs
end
-- a text exactly as wide as its words (at most maxW): width, height, font string
function U.Word(parent, x, y, size, token, words, maxW, name)
  local h, fs = U.Text(parent, x, y, maxW or 400, size, token, words, false, name)
  local w = min(maxW or 400, ceil(TW(fs)) + 2)
  fs:SetWidth(w)
  return w, h, fs
end
-- an icon button with a skin glyph or an icon slot
function U.IconButton(parent, glyph, slot, size, onClick, tip, body)
  size = size or Page.BTN
  local b = Skin.IconButton(parent, "", size, onClick, tip, body)
  b:SetIcon(glyph or "Map", floor(size * 0.7))
  if slot and not glyph then
    b.panoplyKitIcon = slot
    Kit.Icon(b.icon, slot, { size = floor(size * 0.7) })
  end
  return b
end
-- a link: words that are a button (muted, brighter under the mouse)
function U.Link(parent, x, y, words, maxW, onClick, tip, body, size)
  local b = CreateFrame("Button", nil, parent)
  b.panoplyGapOK = true
  local w, h, fs = U.Word(b, 0, 0, size or 11, "text.muted", words, maxW)
  b:SetSize(w, h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  Skin.Tooltip(b, tip or words, body)
  b:SetScript("OnEnter", function(self) local c = Kit.Color("text.primary") fs:SetTextColor(c[1], c[2], c[3], 1) if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() local c = Kit.Color("text.muted") fs:SetTextColor(c[1], c[2], c[3], 1) if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() if onClick then onClick() end end)
  b.fs = fs
  return b, w, h
end
-- a small square icon texture
function U.Icon(parent, x, y, size, tex, desat)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetTexture(tex or 134400)
  if t.SetTexCoord then t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  if desat and t.SetDesaturated then t:SetDesaturated(true) t.panoplyDesat = true end
  return t
end

-- an ITEM's picture (an id or a link): Panoply.Icons finds it and paints it again when the game sends the item, so a
-- late-loading item is not left as the game's "?" (0.9.7 icons)
function U.ItemIcon(parent, x, y, size, item, desat)
  local t = U.Icon(parent, x, y, size, nil, desat)
  Panoply.Icons:Apply(t, item)
  return t
end

-- the class crests: the game's class circle texture, cut to each class (the same cut as At Your Level's strip)
CP.CREST = "Interface\\TargetingFrame\\UI-Classes-Circles"
CP.CREST_CUT = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
function CP:CrestCut(cls)
  local t = type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[cls] or nil
  if type(t) == "table" and type(t[1]) == "number" then return t end
  return self.CREST_CUT[cls or ""]
end

-- a card that is filled from the top (the write-ups): with a heading it is a Kit.Section and c is its body; Done() returns its height
function U.OpenCard(holder, w, label, closed, sectionId)
  local c, sec
  if label and label ~= "" then
    sec = Kit.Section(holder, "class", sectionId or ((holder.topicKey or "") .. "/" .. label), { title = label, caps = true, open = not closed })
    c = sec.body
    c:SetWidth(w)
    c.sec = sec
    c.y = -SP.xs
  else
    c = Skin.Card(holder)
    c.panoplyGapOK = true
    c:SetWidth(w)
    c.y = -10
  end
  c.inner = w - 2 * PAD
  function c:Para(text, color, size)
    local fs = Skin.Ink(self, size or 12, color or Skin.colors.ink)
    fs:SetWidth(self.inner); fs:SetText(text or "")
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, self.y)
    local h = TH(fs, self.inner); fs:SetHeight(h)
    self.y = self.y - h - SP.s
    return fs
  end
  function c:Big(text)
    local fs = Skin.Name(self, 14, Skin.colors.heading)
    fs:SetWidth(self.inner); fs:SetText(text or "")
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, self.y)
    local h = TH(fs, self.inner); fs:SetHeight(h)
    self.y = self.y - h - SP.s
  end
  function c:Buttons(list)
    local bh = Skin.FlowButtons(self, list, PAD, self.y, self.inner, SP.s, 90)
    self.y = self.y - bh - SP.s
  end
  -- a "WoW Forever" note as a small badge before the words (spec 03 section 6: a badge, not coloured inline text)
  function c:Tagged(tag, text)
    local chip = Kit.StatusChip(self, "state.idle", tag)
    local cw, ch = chip:Set("state.idle", tag)
    chip:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, self.y)
    chip.panoplyGameTag = tag
    local x = PAD + cw + SP.s
    local fs = Skin.Ink(self, 12, Skin.colors.ink)
    local tw = max(40, self.inner - cw - SP.s)
    fs:SetWidth(tw); fs:SetText(text or "")
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, self.y - 1)
    local h = TH(fs, tw); fs:SetHeight(h)
    self.y = self.y - max(h + 1, ch) - SP.s
    return fs, chip
  end
  function c:Done()
    if self.sec then
      self.contentH = max(0, ceil(-self.y - SP.s))
      return self.contentH
    end
    local h = ceil(-self.y + 10 - SP.s)
    self:SetHeight(h)
    return h
  end
  return c
end

-- puts the cards of a holder one under another; returns the height of them all (sections at the height their open state gives)
function U.PlaceCards(holder, w)
  local sig = { w }
  for _, e in ipairs(holder.entries or {}) do if e.sec then sig[#sig + 1] = e.sec:IsOpen() and "o" or "c" end end
  sig = table.concat(sig, ",")
  if holder.placeSig == sig and holder.panoplyH then return holder.panoplyH end
  holder.placeSig = sig
  local y = 0
  for _, e in ipairs(holder.entries or {}) do
    if e.sec then
      e.sec:Begin(holder, 0, y, w)
      y = y - e.sec:Done(e.contentH) - SP.m
    else
      e:ClearAllPoints(); e:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
      y = y - e:GetHeight() - SP.m
    end
  end
  holder.panoplyH = -y
  return -y
end

-- a macro inside a card: its name and how long it is, the text in a box with a copy button, and what it does (255-character counter kept)
function U.Macro(c, b)
  local n = #b.body
  local count = Skin.Text(c, 11, Skin.colors.inkSoft)
  count:SetText(("%d of %d characters"):format(n, CP.MACRO_MAX))
  if count.SetJustifyH then count:SetJustifyH("RIGHT") end
  local cw = ceil(TW(count)) + 4
  local name = Skin.Name(c, 12, Skin.colors.heading)
  local copyW = 22
  local nw = c.inner - cw - SP.m - copyW - SP.s
  name:SetWidth(nw); name:SetText(b.name)
  name:ClearAllPoints(); name:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local nh = TH(name, nw); name:SetHeight(nh)
  count:SetWidth(cw); count:SetHeight(TH(count, cw))
  count:ClearAllPoints(); count:SetPoint("TOPRIGHT", c, "TOPLEFT", PAD + c.inner - copyW - SP.s, c.y)
  local box = CreateFrame("Frame", nil, c)
  box.panoplyGapOK = true
  -- the copy button: the macro's text in a box to select and copy (Ctrl+C); the game has no clipboard call for add-ons
  local copy = U.IconButton(c, nil, "icon.ui.copy", copyW, function() CP:ShowMacroText(box, b) end, "Copy",
    "Shows the macro's text selected, ready to copy with Ctrl+C. Then type /macro, make a new macro and paste it in.")
  copy:SetPoint("TOPRIGHT", c, "TOPLEFT", PAD + c.inner, c.y + 2)
  box.panoplyCopy = copy
  c.y = min(c.y - nh, c.y - TH(count, cw)) - SP.xs
  Skin.Box(box, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine })
  box:ClearAllPoints(); box:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local tw = c.inner - 2 * SP.m
  local body = Skin.Ink(box, 12, Skin.colors.text)
  body:SetWidth(tw); body:SetText(b.body)
  body:ClearAllPoints(); body:SetPoint("TOPLEFT", box, "TOPLEFT", SP.m, -SP.s)
  local th = TH(body, tw); body:SetHeight(th)
  local bh = ceil(th + 2 * SP.s)
  box:SetSize(c.inner, bh)
  box.panoplyMacro, box.panoplyBody = b, body
  c.y = c.y - bh - SP.xs
  if b.note and b.note ~= "" then c:Para(b.note, Skin.colors.inkSoft, 11) end
  c.y = c.y - SP.xs
  return box
end

-- the macro's text in a box the player can copy from (one shared edit box laid over the macro's own box)
function CP:ShowMacroText(box, b)
  local eb = self.copyBox
  if not eb then
    eb = Skin.Input(box, 200, 24, "")
    if eb.icon then eb.icon:Hide() end
    if eb.SetMultiLine then eb:SetMultiLine(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
    eb:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    self.copyBox = eb
  end
  if eb.SetParent then eb:SetParent(box) end
  eb:ClearAllPoints(); eb:SetAllPoints(box)
  eb:SetText(b.body)
  eb:Show()
  if eb.SetFocus then eb:SetFocus() end
  if eb.HighlightText then eb:HighlightText() end
  self.copyShown = b
  return eb
end

-------------------------------------------------------------------------------
-- The words of the header (the tests and the previews read these too)
-------------------------------------------------------------------------------
-- "Talon · level 15 · Beast Mastery": the character, its level and the tree of the plan (else of its talents); another class: what it is
function CP:WhoLine()
  local cls = self:ViewClass()
  if cls ~= self:PlayerClass() then return ("Reading about the %s. Back to your own class from the strip below."):format(self.CLASS_NAME[cls] or cls) end
  local info = C.PlayerInfo() or {}
  local level = C.XP() or 1
  local parts = { info.name or "You", ("level %d"):format(level) }
  local s = ST()
  if s and s.Trees then
    local tree
    local t = s:Tracked()
    if t and s.RanksAt then
      local ok, _, spent = pcall(s.RanksAt, s, t.class, t.points)
      if ok and spent then
        local best, bi = 0, nil
        for i, n in ipairs(spent) do if n > best then best, bi = n, i end end
        local T = bi and s:Trees(t.class)
        tree = T and T.tabs[bi] and T.tabs[bi].name
      end
    end
    if not tree and s.MainTree then tree = (s:MainTree()) end
    if tree then parts[#parts + 1] = tree end
  end
  return table.concat(parts, " \194\183 ")
end

Menu.headerTitle.class = function()
  local cls = CP:ViewClass()
  local cut = CP:CrestCut(cls)
  return { label = CP.CLASS_NAME[cls] or "Class", text = CP:WhoLine(), crest = cut and { tex = CP.CREST, cut = cut } or nil }
end

-- the plan dropdown's tooltip: what the plan drives, and (WoW Forever, under level 40) where the second spec comes from
function CP:PlanTip()
  local body = "The plan drives the talent tree, the spells to buy, the gear weights and the rotation text. Edits save as you make them; editing a ready-made plan keeps your own copy."
  local s = ST()
  if C.IsForever() and s and (s:Player().level or 1) < s.DUAL_SPEC_LEVEL then body = body .. "\n\nA second spec can be bought from your trainer at 40." end
  return body
end

-------------------------------------------------------------------------------
-- Menus of the strip
-------------------------------------------------------------------------------
function CP:PlanMenuItems()
  local s = ST()
  local p = s:ActivePlan()
  local own = s:IsOwnPlan(p)
  return {
    { text = "New plan", tip = "An empty plan of your own. Click talents on the Talents tab in the order you want them.",
      func = function() s:NewEmptyPlan() CP:SetTopic("talents") Menu:RefreshCurrent() end },
    { text = "Duplicate", tip = "A copy of this plan, to change without touching this one.", func = function() s:DuplicatePlan() Menu:RefreshCurrent() end },
    { text = "Rename", tip = own and "Give this plan another name." or "A ready-made plan keeps its name. Edit it, or Duplicate it, to make your own.",
      disabled = not own, func = function() if own then CP.renaming = p.key Menu:RefreshCurrent() end end },
    { text = "Delete", tip = own and "Deletes this plan of yours. It asks first." or "A ready-made plan cannot be deleted.", disabled = not own,
      func = function() if own then CP:ConfirmDelete(CP.planMoreBtn, p) end end },
  }
end
function CP:OpenPlanMenu(owner)
  local items = {}
  for _, it in ipairs(self:PlanMenuItems()) do
    if it.disabled then items[#items + 1] = { text = it.text, tip = it.tip, disabled = true, func = function() end }
    else items[#items + 1] = it end
  end
  return Skin.Menu(owner, items, { width = 170 })
end

-- The plan dropdown's list, CP.PLAN_PAGE plans a page; "More plans..." turns the page. A choice made in a fight on a page that holds protected
-- frames waits for the fight to end, as every Kit.Dropdown's does.
CP.PLAN_PAGE = 12
function CP:OpenPlanList(owner, page)
  local s = ST()
  -- 0.9.9.4: the builds grouped by spec, each with its kind and source on a second line, then Plan by hand and your own plans
  local all = s:PlanMenuItems()
  local per = self.PLAN_PAGE
  local pages = math.max(1, math.ceil(#all / per))
  page = ((math.max(1, page or 1) - 1) % pages) + 1
  local cur = s:PlanValue()
  local items = {}
  local lastGroup
  for i = (page - 1) * per + 1, math.min(#all, page * per) do
    local it = all[i]
    if it.group and it.group ~= lastGroup then
      if lastGroup then items[#items + 1] = { divider = true } end
      items[#items + 1] = { header = it.group }
      lastGroup = it.group
    end
    items[#items + 1] = { text = it.text, sub = it.sub, tip = it.tip, checked = it.value == cur, func = function()
      local function pick()
        if it.value == s.BY_HAND then s:NewEmptyPlan() else s:ChoosePlan(it.value) end
        if owner.Refresh then owner:Refresh() end Menu:RefreshCurrent()
      end
      if Kit.InCombat() and Kit.PageHolds("class") then
        Kit.Defer("class/dd/plan", pick)
        Panoply:Print(("The choice '%s' is made when combat ends."):format(it.text or "?"))
        return
      end
      pick()
    end }
  end
  if pages > 1 then
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = ("More plans... (%d of %d)"):format(page, pages), tip = "Shows the next plans.", func = function() CP:OpenPlanList(owner, page + 1) end }
  end
  return Skin.Menu(owner, items, { width = math.max(owner:GetWidth() or 220, 220) })
end

-- Delete asks first; the plan that is followed asks which to follow instead
function CP:ConfirmDelete(owner, p)
  local s = ST()
  local items = { { header = ("Delete %s?"):format(p.name or "this plan") } }
  local choices = s:SwitchChoices(p.key)
  local followed = s:Tracked() and s:Tracked().key == p.key
  if followed and #choices > 0 then
    items[#items + 1] = { header = "Then follow:" }
    for _, it in ipairs(choices) do
      items[#items + 1] = { text = it.text, tip = "Deletes your plan and follows this one.", func = function()
        s:DeleteOwnPlan(p.key, it.value) Menu:RefreshCurrent() end }
    end
  else
    items[#items + 1] = { text = "Yes, delete it", tip = "This cannot be undone.", func = function() s:DeleteOwnPlan(p.key) Menu:RefreshCurrent() end }
  end
  items[#items + 1] = { text = "Cancel", tip = "Keeps it.", func = function() end }
  return Skin.Menu(owner, items, { width = 240 })
end

-- the page's ...: Read about another class (then the nine classes), Back to my class, Reset this page
function CP:PageMenuItems()
  local own = self:PlayerClass()
  local items = { { header = "Read about another class" } }
  for _, k in ipairs(self.CLASSES) do
    if k ~= own then
      items[#items + 1] = { text = self.CLASS_NAME[k], checked = self:ViewClass() == k, tip = "Its Overview and How to play, to read. Talents, Spells, Gear and Pet are for your own character.",
        func = function() CP:ReadClass(k) end }
    end
  end
  items[#items + 1] = { divider = true }
  if own and self:ViewClass() ~= own then
    items[#items + 1] = { text = "Back to my " .. (self.CLASS_NAME[own] or "class"), tip = "Shows your own class again.", func = function() CP:ReadClass(own) end }
  end
  items[#items + 1] = { text = "Reset this page", tip = "The tab, the sections and the How to play section as the page first opens. Your plan and your answers are kept.",
    func = function() CP:ResetPage() end }
  return items
end
function CP:OpenPageMenu(owner) return Skin.Menu(owner, self:PageMenuItems(), { width = 200 }) end

function CP:ReadClass(k)
  if not self:SetClass(k) then return false end
  if Panoply.History then Panoply.History:Note("class") end
  self.topic = self:ViewTopic(k)
  Menu:RefreshCurrent()
  return true
end

function CP:ResetPage()
  if Kit.ResetState then Kit.ResetState("class") end
  self.topic, self.howto, self.renaming = "overview", nil, nil
  self.viewClass = self:PlayerClass() or self.viewClass
  Menu:RefreshCurrent()
end
Kit.OnReset("class", function() CP.howto, CP.renaming = nil, nil end)

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
-- the page's last tab is remembered (PanoplySuiteDB.pageState.class.tab) and put back at login; CP.topic is the page's own copy
Kit.TabVar("class", { get = function() return CP.topic end, set = function(k) CP.topic = k end, default = "overview",
  valid = function(k) return CP.TOPIC[k] ~= nil end })

Menu:RegisterTab("ClassPages", function(p)
  local s = ST()
  p.msg = Skin.Ink(p, 13, Kit.Color("text.muted"))
  p.area = Skin.ScrollArea(p)
  p.panoplyArea = nil          -- (the window sizes a page's panoplyArea to the whole page; this page places its own scrolling part under the strip)
  p.renameMsg = Skin.Ink(p, 11, Kit.Color("state.warn"))
  -- the strip's controls, made once
  p.specTabs = {}
  for i = 1, 2 do
    local b = Skin.Tab(p, "Spec " .. i, 70, function() if s then s:SetViewSpec(i) end Menu:RefreshCurrent() end, "Spec " .. i,
      "Each spec has its own plan. This shows spec " .. i .. "'s; you switch specs in the game's own talent window.")
    b.panoplyPicker, b.panoplySpec = true, i
    p.specTabs[i] = b
  end
  if s then
    p.planDD = Kit.Dropdown(p, { page = "class", label = "Plan: ", width = 240, height = 28, tip = "Plan", tipBody = CP:PlanTip(),
      empty = "pick one", items = function() return s:PlanItems() end, get = function() return s:PlanValue() end,
      set = function(k) s:ChoosePlan(k) end, onChange = function() Menu:RefreshCurrent() end })
    -- a long list of plans is shown a page at a time (a menu never grows past the screen; the old planner did the same)
    p.planDD.Open = function(self) return CP:OpenPlanList(self, 1) end
    p.planMore = Skin.Button(p, "...", 34, 28, function(b) CP:OpenPlanMenu(b) end, "Plan", "New plan, Duplicate, Rename or Delete.")
    p.planMore.panoplyFixedW = true
    CP.planMoreBtn = p.planMore
    -- Rename: a box in the strip, in place of the plan
    p.renameBox = Skin.Input(p, 200, 26, "Plan name")
    if p.renameBox.icon then p.renameBox.icon:Hide() end
    if p.renameBox.SetTextInsets then p.renameBox:SetTextInsets(8, 6, 0, 0) end
    local function doRename()
      local name, why = s:RenamePlan(CP.renaming, p.renameBox:GetText())
      if name then CP.renaming, CP.renameWhy = nil, nil else CP.renameWhy = why end
      Menu:RefreshCurrent()
    end
    p.renameBox:SetScript("OnEnterPressed", doRename)
    p.renameBox:SetScript("OnEscapePressed", function() CP.renaming, CP.renameWhy = nil, nil Menu:RefreshCurrent() end)
    p.renameOK = Skin.Button(p, "Rename", 80, 26, doRename, "Rename", "Keeps the new name.")
    p.renameCancel = Skin.Button(p, "Cancel", 70, 26, function() CP.renaming, CP.renameWhy = nil, nil Menu:RefreshCurrent() end, "Cancel", "Keeps the old name.")
    p.renameBox:Hide(); p.renameOK:Hide(); p.renameCancel:Hide()
    -- "Saved as your own copy. Undo"
    p.undoText = Skin.Ink(p, 12, Kit.Color("text.primary"))
    p.undoBtn = Skin.Button(p, "Undo", 60, 22, function() s:Undo() Menu:RefreshCurrent() end, "Undo", "Removes your copy and goes back to the plan you followed before.")
  end
  local levels = {}
  for i, label in ipairs(CP.LEVELS) do levels[i] = { text = label, value = i, tip = CP.LEVEL_TIP[i] } end
  p.writtenDD = Kit.Dropdown(p, { page = "class", label = "Written for: ", width = 260, height = 28, tip = "Written for",
    tipBody = "How the text on this page is written and which parts start open. Nothing is ever hidden by it.",
    items = levels, get = function() return CP:Experience() end, set = function(n) CP:SetExperience(n) end,
    onChange = function() Menu:RefreshCurrent() end })
  p.pageMore = Skin.Button(p, "...", 34, 28, function(b) CP:OpenPageMenu(b) end, "More", "Read about another class, or reset this page.")
  p.pageMore.panoplyFixedW = true
  -- reading another class
  p.banner = Skin.Ink(p, 12, Kit.Color("text.primary"))
  p.mineBtn = Skin.Button(p, "Back to my class", 140, 24, function() CP:ReadClass(CP:PlayerClass()) end, "Back to my class", "Shows your own class again.")
  p.ownOnly = Skin.Ink(p, 11, Kit.Color("text.muted"))
  -- the tabs: ONE row (a dropdown on a narrow page)
  local items = {}
  for _, t in ipairs(CP.TOPICS) do items[#items + 1] = { key = t.key, label = t.label, short = t.short, tip = t.label, tipBody = t.tip } end
  p.kitTabs = Kit.Tabs(p, { page = "class", items = items, default = "overview", minW = 60, style = "underline",
    get = function() return CP.topic end, onSelect = function(k) CP:SetTopic(k) end })
  p.topicTabs = p.kitTabs.byKey
  for key, b in pairs(p.topicTabs) do b.panoplyTopic = key end
  p.built = {}
  CP.pageFrame = p
end, function(p) Page:Render(p) end)

-- what the page shows: { class, own, forever, level, topic, band, howto, seqState }
function Page:View(p)
  local cls = CP:ViewClass()
  CP.topic = CP:ViewTopic(cls)
  return { class = cls, topic = CP.topic, level = CP:Experience(), forever = C.IsForever() and true or false,
    own = cls == CP:PlayerClass(), band = Kit.Band(p.width or 600), howto = CP:HowtoSection() }
end

function Page:Message(p, words)
  for _, h in pairs(p.built or {}) do if h then h:Hide() end end
  p.area:Hide()
  self:HideStrip(p)
  p.msg:ClearAllPoints(); p.msg:SetPoint("TOPLEFT", p, "TOPLEFT", 4, 0); p.msg:SetWidth((p.width or 600) - 8)
  p.msg:SetText(words)
  p.msg:SetHeight(TH(p.msg, (p.width or 600) - 8))
  p.msg:Show()
end

function Page:HideStrip(p)
  for _, o in ipairs({ p.planDD, p.planMore, p.writtenDD, p.pageMore, p.banner, p.mineBtn, p.ownOnly, p.undoText, p.undoBtn,
    p.renameBox, p.renameOK, p.renameCancel, p.specTabs[1], p.specTabs[2] }) do if o then o:Hide() end end
  p.kitTabs:HideAll()
  if p.kitTabs.dd then p.kitTabs.dd:Hide() end
end

-- places a row of frames from x at y, each at its own width; wraps to a new line when the next does not fit; returns the height
local function flow(p, list, y, W)
  local x, lineH, top = 2, 0, y
  for _, f in ipairs(list) do
    local w = f:GetWidth() or 60
    if x > 2 and x + w > W then x = 2 y = y - lineH - SP.s lineH = 0 end
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", p, "TOPLEFT", x, y); f:Show()
    x = x + w + (f.panoplyGapAfter or SP.s)
    lineH = max(lineH, f:GetHeight() or 26)
  end
  return top - y + lineH
end

function Page:Render(p)
  local W, H = p.width or 600, p.height or 400
  local s = ST()
  if not CP:PlayerClass() then return self:Message(p, "Panoply Suite cannot read your class yet. Open this page again in a moment.") end
  p.msg:Hide()
  local v = self:View(p)
  p.view = v
  self:HideStrip(p)
  local y = 0
  -- 1. the strip: the plan and Written for (the plan only on your own class, and only with Talents & spells on)
  local stOn = s and Panoply.Modules:IsOn("spectrainer")
  local row1, row2 = {}, {}
  if v.own and stOn then
    if s:DualSpec() then
      local slot = s:PlanSlot()
      for i, b in ipairs(p.specTabs) do b:SetActive(i == slot) Skin.FitButton(b, 64, 90) row1[#row1 + 1] = b end
      p.specTabs[2].panoplyGapAfter = SP.m
    end
    if CP.renaming and s:CDB().specPlans[CP.renaming] then
      local box = p.renameBox
      if box.panoplyFor ~= CP.renaming then
        box.panoplyFor = CP.renaming
        box:SetText(s:CDB().specPlans[CP.renaming].name or "")
        if box.SetFocus then box:SetFocus() end
        if box.HighlightText then box:HighlightText() end
      end
      box:SetWidth(min(260, max(140, W - 200)))
      Skin.FitButton(p.renameOK, 70, 110); Skin.FitButton(p.renameCancel, 60, 100)
      row1[#row1 + 1] = box; row1[#row1 + 1] = p.renameOK; row1[#row1 + 1] = p.renameCancel
    else
      CP.renaming = nil
      p.renameBox.panoplyFor = nil
      p.planDD.tipBody = CP:PlanTip()
      p.planDD:Fit(180, min(320, W - 60))
      row1[#row1 + 1] = p.planDD; row1[#row1 + 1] = p.planMore
    end
    p.planMore.panoplyGapAfter = SP.l
  end
  p.writtenDD:Fit(200, min(320, W - 60))
  row2[#row2 + 1] = p.writtenDD; row2[#row2 + 1] = p.pageMore
  -- Wide and Medium: one line when it fits; Narrow: Plan on the first line, Written for on the second (spec 03 section 9)
  local all = {}
  for _, f in ipairs(row1) do all[#all + 1] = f end
  for _, f in ipairs(row2) do all[#all + 1] = f end
  local need = 0
  for _, f in ipairs(all) do need = need + (f:GetWidth() or 60) + (f.panoplyGapAfter or SP.s) end
  if v.band ~= "narrow" and need <= W then
    y = y - flow(p, all, y, W) - SP.s
  else
    if #row1 > 0 then y = y - flow(p, row1, y, W) - SP.s end
    y = y - flow(p, row2, y, W) - SP.s
  end
  if CP.renameWhy and CP.renaming then
    local m = p.renameMsg
    m:SetText(CP.renameWhy); m:SetWidth(W - 8); m:SetHeight(TH(m, W - 8))
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", p, "TOPLEFT", 4, y); m:Show()
    y = y - TH(m, W - 8) - SP.xs
  else p.renameMsg:Hide() end
  -- 2. "Saved as your own copy. Undo"
  if v.own and s and s.undo then
    p.undoText:SetText(s.UNDO_TEXT .. " " .. ("\"%s\" is your plan now."):format(s.undo.name or ""))
    local uw = min(ceil(TW(p.undoText)) + 4, W - 80)
    p.undoText:SetWidth(uw); p.undoText:SetHeight(TH(p.undoText, uw))
    p.undoText:ClearAllPoints(); p.undoText:SetPoint("TOPLEFT", p, "TOPLEFT", 4, y - 3); p.undoText:Show()
    Skin.FitButton(p.undoBtn, 56, 90)
    p.undoBtn:ClearAllPoints(); p.undoBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 4 + uw + SP.s, y); p.undoBtn:Show()
    y = y - max(TH(p.undoText, uw) + 3, p.undoBtn:GetHeight()) - SP.s
  end
  -- 3. reading another class: the banner, and only the text tabs
  local own = CP:PlayerClass()
  if not v.own then
    p.banner:SetText(("Reading: %s."):format(CP.CLASS_NAME[v.class] or v.class))
    local bw = ceil(TW(p.banner)) + 4
    p.banner:SetWidth(bw); p.banner:SetHeight(TH(p.banner, bw))
    p.banner:ClearAllPoints(); p.banner:SetPoint("TOPLEFT", p, "TOPLEFT", 4, y - 4); p.banner:Show()
    p.mineBtn.label:SetText("Back to my " .. (CP.CLASS_NAME[own] or "class"))
    Skin.FitButton(p.mineBtn, 120, 220)
    p.mineBtn:ClearAllPoints(); p.mineBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 4 + bw + SP.m, y); p.mineBtn:Show()
    y = y - max(TH(p.banner, bw) + 4, p.mineBtn:GetHeight()) - SP.s
  end
  -- 4. the tabs
  for _, t in ipairs(CP.TOPICS) do p.kitTabs:SetShown(t.key, CP:HasTopic(t, v.class)) end
  local tabH = p.kitTabs:Layout(2, y, W, v.band == "narrow" and "dropdown" or nil)
  y = y - tabH - SP.s
  if not v.own then
    p.ownOnly:SetText("Talents, Spells, Gear and Pet: these show for your own character.")
    p.ownOnly:SetWidth(W - 8); p.ownOnly:SetHeight(TH(p.ownOnly, W - 8))
    p.ownOnly:ClearAllPoints(); p.ownOnly:SetPoint("TOPLEFT", p, "TOPLEFT", 4, y); p.ownOnly:Show()
    y = y - TH(p.ownOnly, W - 8) - SP.s
  end
  y = y - SP.xs
  -- 5. the body: the only part that scrolls
  local area = p.area
  local viewH = max(60, floor(H + y - self.GRIP))
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
  area:SetSize(W, viewH)
  area:Show()
  local cw = W - 14
  local tab = CP.TABS[v.topic] or CP.TABS.overview
  -- the content of a tab is built once for what it shows and kept (the game never frees a frame); only the tab showing is shown
  local function sigOf() return v.topic .. "|" .. v.class .. "|" .. cw .. "|" .. (tab.Sig and tab.Sig(v, cw, viewH, p) or "") end
  local sig = sigOf()
  -- in a fight a tab that holds the next ability display's card and was never drawn for this view is drawn without that card (no such
  -- frame is created in combat: Sequencer.lua); the card is drawn when the fight ends (CP.Seq.dirty)
  if not p.built[sig] and C.InCombat() and tab.CombatWait and tab.CombatWait(v) then
    v.forceWait = true
    CP.Seq.dirty, CP.dirty = true, true
    sig = sigOf()
  end
  -- spec 03 section 1.8: the outgoing tab's frames are hidden before the new one shows
  for k, h in pairs(p.built) do if k ~= sig and h then h:Hide() end end
  local holder = p.built[sig]
  if not holder then
    holder = CreateFrame("Frame", nil, area.content)
    holder.panoplyGapOK = true
    holder:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
    holder:SetWidth(cw)
    holder.topicKey = v.topic
    holder.page = p
    p.built[sig] = holder
    holder.panoplyH = nil
    holder.drawn = false
  end
  p.panoplyContent = holder
  holder:Show()
  local ch, fill = tab.Draw(p, holder, cw, viewH, v)
  ch = ch or 0
  if holder.panoplyLastH ~= ch then holder.panoplyLastH = ch holder:SetHeight(max(1, ch)) end
  if area.content.panoplyLastW ~= cw or area.content.panoplyLastH ~= ch then
    area.content.panoplyLastW, area.content.panoplyLastH = cw, ch
    area.content:SetSize(cw, max(1, ch))
  end
  area:SetContentHeight(fill and min(ch, viewH) or (ch + SP.s))
  if fill and area.SetVerticalScroll then area:SetVerticalScroll(0) end
  if area.UpdateBar then area:UpdateBar() end
  p.contentH = ch
end

-- the page follows the fight ending (a tab waiting to be drawn), the plan, talents and level
local function refreshIfShown()
  if Menu.current == "class" and Menu.frame and Menu.frame:IsShown() then Menu:RefreshCurrent() end
end
Panoply:On("PLAYER_REGEN_ENABLED", function() if CP.dirty then CP.dirty = nil refreshIfShown() end end)
Panoply:Listen("SPEC_PLAN_CHANGED", function() if not C.InCombat() then refreshIfShown() end end)
Panoply:On("PLAYER_LEVEL_UP", function() if not C.InCombat() then C.After(0.2, refreshIfShown) end end)

-------------------------------------------------------------------------------
-- Overview
-------------------------------------------------------------------------------
-- The Now list (spec 03 section 3.2): up to five rows, each one action with the tab that handles it. Only rows that apply.
-- A row: { key, icon, icons = { textures }, title, sub, tab, go = { fn, tip, body } }
function CP:NowRows()
  local out = {}
  local s = ST()
  local stOn = s and Panoply.Modules:IsOn("spectrainer")
  local level = C.XP() or 1
  local cls = self:PlayerClass()
  -- next talent point
  if stOn then
    local plan = s:Tracked() or s:ActivePlan()
    local ok, n = pcall(s.Next, s, plan)
    if ok and n and n.tal then
      local due = math.max(n.level or level, level)
      local when = (s:UnspentPoints() or 0) > 0 and "now" or ("at level %d"):format(due)
      out[#out + 1] = { key = "talent", icon = s:HeldIcon(n.tal, cls), title = ("%s %d/%d"):format(n.tal.name, n.rank, n.tal.ranks),
        sub = "Next talent point, " .. when .. ((s.BuildWords and s:BuildWords()) and (", from " .. s:BuildWords()) or ""), tab = "talents" }
    end
    -- the trainer
    local okP, sp = pcall(s.SpellPlan, s)
    if okP and sp and sp.table then
      local nowV = sp.now and sp.now.buy.n > 0 and sp.now or nil
      if nowV or sp.next then
        local icons = {}
        for _, r in ipairs((nowV or sp.next).rows) do if r.kind == "buy" and #icons < 5 then icons[#icons + 1] = r.icon or 134400 end end
        local title = nowV and ("%d %s to buy now \194\183 %s"):format(nowV.buy.n, plural(nowV.buy.n, "spell"), s.Money(nowV.buy.cost)) or "Nothing to buy now"
        local sub = sp.next and ("Next visit: level %d, %d %s, %s"):format(sp.next.level, sp.next.buy.n, plural(sp.next.buy.n, "spell"), s.Money(sp.next.buy.cost)) or "Nothing left after this visit."
        out[#out + 1] = { key = "trainer", icons = icons, title = title, sub = sub, tab = "spells",
          go = { fn = function() s:PointToTrainer() end, tip = "Point me to my trainer", body = "Adds the nearest class trainer to your waypoints; the arrow follows it." } }
      end
    end
  end
  -- the pet: the next useful tame
  local P = Panoply.HunterPet
  if P and cls == "HUNTER" and P.Main and P.ToTame then
    local fam = P:Main() or P:View()
    local ok, tt = pcall(P.ToTame, P, fam)
    local e = ok and tt and tt.list and tt.list[1]
    if e and e.t and e.teaches and e.teaches[1] then
      local a = e.teaches[1]
      local at = (e.t.lo or 1) > level and (" at %d"):format(e.t.lo) or ""
      out[#out + 1] = { key = "pet", icon = P.FamilyIcon and P:FamilyIcon(fam) or nil,
        title = ("Tame a %s%s for %s %d"):format(e.n, at, a.key, a.rank), sub = e.t.z and ("In %s"):format(e.t.z) or "Where: not known yet", tab = "pet" }
    end
  end
  -- gear: the slots with an upgrade now, and the top two items
  local G = Panoply.Gear
  if G and CP.GearGrid then
    local ok, g = pcall(CP.GearGrid, CP)
    if ok and g and g.now and g.now > 0 then
      local best = {}
      for _, c in ipairs(g.cells) do if c.now then best[#best + 1] = c.now end end
      table.sort(best, function(a, b) return (a.delta or 0) > (b.delta or 0) end)
      local icons = {}
      for i = 1, min(2, #best) do icons[i] = { item = best[i].link or best[i].itemID } end
      out[#out + 1] = { key = "gear", icons = icons, title = ("Upgrades for %d %s"):format(g.now, plural(g.now, "slot")),
        sub = best[1] and ("Best: %s"):format(best[1].name or "?") or nil, tab = "gear" }
    end
  end
  -- the class quest: only when one is open or opens within 3 levels
  local AL = Panoply.AtLevel
  if AL and AL.ClassQuestChip and AL.Available and AL:Available() then
    local ok, q = pcall(AL.ClassQuestChip, AL, level, cls)
    if ok and type(q) == "table" and q.q and (q.q.when == "now" or (q.q.reqLevel or 99) <= level + 3) then
      local sub = q.q.when == "now" and (q.q.inLog and "In your quest log." or "Open now.") or ("Opens at level %d."):format(q.q.reqLevel or level)
      out[#out + 1] = { key = "quest", title = ("Class quest: %s"):format(q.q.name or "your class quest"), sub = sub,
        go = { fn = function() if AL.Open then AL:Open() end end, tip = "At your level", body = "Opens At your level, where the class quest and who gives it are." } }
    end
  end
  while #out > Page.NOW_MAX do table.remove(out) end
  return out
end

-- one row of the Now list; returns its height
local function nowRow(p, holder, y, w, r)
  local x = 0
  local ICON = 28
  if r.icon then U.Icon(holder, x, y, ICON, r.icon) x = x + ICON + SP.s
  elseif r.icons and #r.icons > 0 then
    for i, t in ipairs(r.icons) do
      if type(t) == "table" then U.ItemIcon(holder, x + (i - 1) * (18 + 2), y + 0, 18, t.item)
      else U.Icon(holder, x + (i - 1) * (18 + 2), y + 0, 18, t) end
    end
    x = x + #r.icons * 20 + SP.s
  end
  local right = 0
  local link
  if r.tab then
    local t = CP.TOPIC[r.tab]
    link = Skin.Button(holder, (t and t.label or r.tab) .. " >", 80, 22, function() CP:GoTab(r.tab) end, t and t.label or r.tab, "Opens the " .. (t and t.label or r.tab) .. " tab.")
    Skin.FitButton(link, 60, 140)
    right = link:GetWidth()
    link:SetPoint("TOPRIGHT", holder, "TOPLEFT", w, y)
  end
  local go
  if r.go then
    go = U.IconButton(holder, "Arrow", nil, Page.BTN, r.go.fn, r.go.tip, r.go.body)
    go:SetPoint("TOPRIGHT", holder, "TOPLEFT", w - right - (right > 0 and SP.s or 0), y)
    right = right + Page.BTN + SP.s
  end
  local tw = max(60, w - x - right - SP.s)
  local th = U.Text(holder, x, y, tw, 13, "text.primary", r.title, true, true)
  local sh = 0
  if r.sub and r.sub ~= "" then sh = U.Text(holder, x, y - th - 2, tw, 11, "text.muted", r.sub, true) end
  p.nowRows[#p.nowRows + 1] = { row = r, link = link, go = go }
  return max(ICON, th + (sh > 0 and (sh + 2) or 0), 22)
end

-- a tab by its key, as one step of the window's history (the Now list's links, the Guide's links)
function CP:GoTab(key, section)
  local H = Panoply.History
  if H then H:Begin() end
  self:SetTopic(key)
  if section then self:SetHowtoSection(section) end
  if H then H:End("tab") end
  if Menu.current == "class" then Menu:RefreshCurrent() else self:Open(nil, key) end
end

-- the first-run card: how much have you played, and pick a plan (only what setup did not answer)
function CP:FirstRunWanted()
  local A = Panoply.Answers
  if not (A and A.ClassCardWanted) then return false end
  if Panoply.cdb and Panoply.cdb.classCardDone then return false end
  if A:SetupState() ~= "done" and A:Get("experience") ~= nil and (A:Get("plan") ~= nil or not Panoply.Modules:IsOn("spectrainer")) then
    -- both questions answered (here or anywhere): the card is gone for good
    self:FirstRunDone()
    return false
  end
  return A:ClassCardWanted()
end
function CP:FirstRunDone()
  if Panoply.cdb then Panoply.cdb.classCardDone = true end      -- a NEW key: the card disappears for good once both are answered
end

local function firstRun(p, holder, w)
  local y = 0
  local h = U.Text(holder, 0, y, w, 15, "gold.title", "Two questions, then this page is yours", true, true)
  y = y - h - SP.s
  y = y - U.Text(holder, 0, y, w, 12, "text.muted", "Both stay changeable at the top of this page.", true) - SP.m
  -- 1
  local A = Panoply.Answers
  local answeredExp = A and A:Get("experience") ~= nil
  y = y - U.Text(holder, 0, y, w, 13, "text.primary", "1. How much have you played?", true, true) - SP.s
  local btns = {}
  for i, label in ipairs(CP.LEVELS) do
    local b = Skin.Tab(holder, label, 120, function() CP:SetExperience(i) Menu:RefreshCurrent() end, label, CP.LEVEL_TIP[i])
    b.panoplyPicker = true
    b:SetActive(answeredExp and CP:Experience() == i)
    btns[#btns + 1] = b
  end
  local bh = Skin.FlowButtons(holder, btns, 0, y, w, SP.s, 100)
  y = y - bh - SP.m
  p.firstExp = btns
  -- 2
  local s = ST()
  local answeredPlan = s and s:Tracked() ~= nil
  -- 0.9.9.4 (the builds are part of the new user setup too): the same question and the same build cards as setup's talent step
  y = y - U.Text(holder, 0, y, w, 13, "text.primary", "2. How do you want to level?", true, true) - SP.s
  p.firstPlans = {}
  if s and Panoply.Modules:IsOn("spectrainer") then
    local cur = s:PlanValue()
    local function pickCard(facts, key, o)
      local c = s:BuildCard(holder, { mode = "pick", onPick = function()
          if key == "own" then s:NewEmptyPlan() else s:FollowBuild(key) end
          Menu:RefreshCurrent()
        end, onFollow = function() s:FollowBuild(key) Menu:RefreshCurrent() end, onShow = facts.key and function() s:ShowOnTree(key) end or nil })
      c.tipAnchor = nil
      c:Set(facts, { pickKey = key, selected = answeredPlan and cur == key })
      local ch = c:Fit(w)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
      y = y - ch - SP.s
      p.firstPlans[#p.firstPlans + 1] = c
      return c
    end
    for _, g in ipairs(s:BuildsBySpec()) do
      local hh = U.Text(holder, 0, y, w, 12, "gold.title", g.name, false, true)
      y = y - hh - SP.xs
      if #g.builds == 0 then
        local c = s:BuildCard(holder, { mode = "line" })
        c:Set({ none = true, specName = g.name })
        local ch = c:Fit(w)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
        y = y - ch - SP.s
      end
      for _, f in ipairs(g.builds) do pickCard(f, f.key) end
    end
    pickCard({ byHand = true }, "own")
  else
    y = y - U.Text(holder, 0, y, w, 12, "text.muted", "Talents & spells is switched off, so there is no plan to pick. Turn it on with the switch at the top.", true) - SP.s
    answeredPlan = true
  end
  if answeredExp and answeredPlan then CP:FirstRunDone() end
  return -y
end

CP.TABS.overview = {
  Sig = function(v, w)
    local parts = { v.level, tostring(v.own), tostring(CP:FirstRunWanted()) }
    if v.own then for _, r in ipairs(CP:NowRows()) do parts[#parts + 1] = r.key .. ":" .. (r.title or "") .. ":" .. (r.sub or "") end end
    local s = ST()
    if s then parts[#parts + 1] = tostring(s:PlanValue()) .. tostring(CP:Experience()) end
    return table.concat(parts, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if not holder.drawn then
      holder.drawn = true
      p.nowRows = {}
      local top = CreateFrame("Frame", nil, holder)
      top.panoplyGapOK = true
      top:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
      local y = 0
      if v.own and CP:FirstRunWanted() then
        y = -firstRun(p, top, w) - SP.l
        holder.firstRun = true
      else
        holder.firstRun = false
        if v.own then
          local rows = CP:NowRows()
          local hh = U.Text(top, 0, y, w, 13, "gold.title", "Now", false, true)
          y = y - hh - SP.s
          if #rows == 0 then y = y - U.Text(top, 0, y, w, 12, "text.muted", "Nothing needs you right now.", true) - SP.m end
          for _, r in ipairs(rows) do y = y - nowRow(p, top, y, w, r) - SP.m end
          y = y - SP.s
        end
      end
      top:SetSize(w, max(1, -y))
      holder.topH = -y
      holder.nowRows = p.nowRows
      -- About your class, under the top part: open for New to the game, closed for the other three (the player's choice is kept after)
      local sub = CreateFrame("Frame", nil, holder)
      sub.panoplyGapOK = true
      sub:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -holder.topH)
      sub:SetWidth(w)
      sub.topicKey = "overview"
      -- reading another class: the block is about that class, not yours
      local aboutT = v.own and "About your class" or ("About the %s"):format(CP.CLASS_NAME[v.class] or v.class)
      local c = U.OpenCard(sub, w, aboutT, v.level ~= 1, "overview/about")
      for _, b in ipairs(CP:Blocks(v.class, "overview", v.level, v.forever)) do
        if b.kind == "h" then
          local fs = Skin.Name(c, 12, Skin.colors.heading)
          fs:SetWidth(c.inner); fs:SetText(b.text)
          fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
          local h = TH(fs, c.inner); fs:SetHeight(h); c.y = c.y - h - SP.xs
        elseif b.kind == "p" then
          if b.tag then c:Tagged(b.tag, b.text) else c:Para(b.text) end
        end
      end
      c:Done()
      sub.entries = { c }
      holder.sub, holder.about = sub, c
    end
    p.nowRows = holder.nowRows
    p.firstRun = holder.firstRun
    local ch = U.PlaceCards(holder.sub, w)
    holder.sub:SetHeight(max(1, ch))
    return holder.topH + ch
  end,
}

-------------------------------------------------------------------------------
-- How to play
-------------------------------------------------------------------------------
-- the blocks of a How to play section, without what moved to another tab: the talent notes (the Talents tab's tooltips) and the
-- Trainers part (the Spells tab's trainer line)
function CP:HowtoBlocks(classFile, key, level, forever)
  local h = self.HOWTO_BY[key]
  if not h then return {} end
  local out, skip = {}, false
  for _, b in ipairs(self:Blocks(classFile, h.topic, level, forever)) do
    if b.kind == "h" then skip = (key == "shots") and (b.text == "Trainers" or b.text == "Talent points") end
    local moved = key == "shots" and b.kind == "p" and b.text:find("^New in the trees:")
    if not skip and not moved then out[#out + 1] = b end
  end
  return out
end

-- the words of the Trainers part of the class's write-up (the Spells tab shows them)
function CP:TrainerBlocks(classFile, level, forever)
  local out, on = {}, false
  for _, b in ipairs(self:Blocks(classFile, "spells", level, forever)) do
    if b.kind == "h" then on = b.text == "Trainers"
    elseif on and b.kind == "p" then out[#out + 1] = b end
  end
  return out
end

local function drawSection(p, holder, x, w, v, key)
  local cards = CreateFrame("Frame", nil, holder)
  cards.panoplyGapOK = true
  cards:SetPoint("TOPLEFT", holder, "TOPLEFT", x, 0)
  cards:SetWidth(w)
  cards.topicKey = "howto/" .. key
  cards.entries = {}
  local card
  local function close() if card then card:Done() cards.entries[#cards.entries + 1] = card card = nil end end
  local function open(label, closed) close() card = U.OpenCard(cards, w, label, closed) return card end
  holder.macros = {}
  for _, b in ipairs(CP:HowtoBlocks(v.class, key, v.level, v.forever)) do
    if b.kind == "h" then open(b.text, v.level >= 3)
    elseif b.kind == "p" then
      card = card or open(nil)
      if b.tag then card:Tagged(b.tag, b.text) else card:Para(b.text) end
    elseif b.kind == "m" then
      card = card or open(nil)
      holder.macros[#holder.macros + 1] = U.Macro(card, b)
    end
  end
  close()
  -- What to press: the next ability display under the words, then your own rotations (spec 03a section 4)
  if key == "press" and CP.Seq and (v.seqState == "on" or v.seqState == "off") then
    -- (the tab's holder is the sequencer's and the editor's: it is what shows and hides with the tab, and where they keep their parts)
    local sc = open(CP.Seq.TITLE)
    CP.Seq:Fill(sc, holder, v)
    close()
    if v.own and v.seqState == "on" and CP.Editor then
      local ec = open(CP.Editor.TITLE, true)
      CP.Editor:Fill(ec, holder, v)
      close()
    end
  end
  return cards
end

CP.TABS.howto = {
  -- the next ability display's card is never made in a fight (Sequencer.lua): What to press first drawn in a fight has its words and no card
  CombatWait = function(v) return v.howto == "press" and (v.seqState == "on" or v.seqState == "off") end,
  Sig = function(v, w)
    local seq = "-"
    if v.howto == "press" and CP.Seq then
      v.seqState = v.forceWait and "wait" or CP.Seq:ViewState()
      seq = v.seqState .. tostring(CP.Editor and CP.Editor.mode or "") .. tostring(CP.Seq.advDrawn or false)
    end
    return table.concat({ v.howto, v.level, tostring(v.forever), tostring(v.own), v.band, seq }, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if v.howto == "press" and CP.Seq and not v.seqState then v.seqState = CP.Seq:ViewState() end
    if not holder.drawn then
      holder.drawn = true
      local key = v.howto
      local indexW = v.band == "wide" and Page.INDEX_W or 0
      local x = 0
      holder.index = {}
      if indexW > 0 then
        -- the section index, on the left (it stays in view: the page scrolls only when a section is longer than the view)
        local yy = 0
        for _, h in ipairs(CP.HOWTO) do
          local label = CP:HowtoLabel(h.key, v.class)
          local b = Kit.TextTab(holder, label, indexW - SP.m, function() CP:SetHowtoSection(h.key) if Panoply.History then Panoply.History:Note("howto") end Menu:RefreshCurrent() end,
            label, "Shows this part of How to play.")
          b:SetActive(h.key == key)
          b:SetWidth(indexW - SP.m)
          -- the index reads from the left, each name whole when it fits, else shortened with its full name in the tooltip
          local lw = indexW - SP.m - 2 * SP.s
          b.label:ClearAllPoints(); b.label:SetPoint("LEFT", b, "LEFT", SP.s, 1)
          if b.label.SetJustifyH then b.label:SetJustifyH("LEFT") end
          b.label:SetWidth(lw)
          Skin.Ellipsize(b.label, label, lw)
          b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, yy)
          b.panoplyHowto = h.key
          holder.index[#holder.index + 1] = b
          yy = yy - (b:GetHeight() or 26) - SP.xs
        end
        holder.indexH = -yy
        x = indexW
      else
        -- Medium and Narrow: the index is a dropdown at the top
        local items = {}
        for _, h in ipairs(CP.HOWTO) do items[#items + 1] = { text = CP:HowtoLabel(h.key, v.class), value = h.key } end
        local dd = Kit.Dropdown(holder, { page = "class", label = "Section: ", width = 260, height = 26, tip = "How to play", tipBody = "Pick the part to read.",
          items = items, get = function() return CP:HowtoSection() end,
          set = function(k) CP:SetHowtoSection(k) if Panoply.History then Panoply.History:Note("howto") end end, onChange = function() Menu:RefreshCurrent() end })
        dd:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        dd:Fit(200, min(320, w))
        holder.indexDD = dd
        holder.topH = (dd:GetHeight() or 26) + SP.m
      end
      -- the section's title and its ? (What to press: the Beta line and what this client shares in combat)
      local tx = x
      local tw = w - x
      local ty = -(holder.topH or 0)
      local label = CP:HowtoLabel(key, v.class)
      local hdr = Kit.SectionHeader(holder, { title = label, help = key == "press" and CP.Seq and CP.Seq:HelpText() or nil })
      hdr:Layout(tx, ty, tw)
      holder.header = hdr
      holder.cardsY = ty - (hdr:GetHeight() or 22) - SP.s
      local cards = drawSection(p, holder, tx, tw, v, key)
      cards:ClearAllPoints(); cards:SetPoint("TOPLEFT", holder, "TOPLEFT", tx, holder.cardsY)
      holder.cards, holder.cardsW = cards, tw
      holder.entries = cards.entries      -- (the section's cards, as the sequencer's tests and the editor read them)
    end
    local ch = U.PlaceCards(holder.cards, holder.cardsW)
    -- (sized only when it changed: in a fight the frames that hold the next ability display's card are not moved or sized)
    if holder.cards.panoplyLastH ~= ch then holder.cards.panoplyLastH = ch holder.cards:SetHeight(max(1, ch)) end
    return max(-holder.cardsY + ch, holder.indexH or 0)
  end,
}

-- the page's state for Back / Forward: the How to play section (the tab is the history's own)
if Panoply.History and Panoply.History.State then
  Panoply.History:State("class", { get = function() return { howto = CP.howto, class = CP.viewClass } end,
    set = function(st) if type(st) == "table" then CP.howto = st.howto CP.viewClass = st.class or CP.viewClass end end,
    key = function(st) return tostring(st and st.howto) .. ":" .. tostring(st and st.class) end })
end
