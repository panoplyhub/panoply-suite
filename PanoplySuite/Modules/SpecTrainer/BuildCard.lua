-- Panoply Suite 0.9.9.4: the build card. ONE card, used everywhere a talent build is shown (Nov 22 2026: "this is also part of the
-- setup and also part of the new user setup. dont put the blinders on and ignore the rest of our addon and all the other places this is
-- needed."): the setup's talent step, the Class page's first-run card, Settings > Talents and trainer, the Class page's Builds tab and
-- its Talents tab, the Pet tab, the Gear tab, the Trainer Helper and the Legacy page. The words that name a build in a sentence (Home,
-- the level-up card, the next-talent card) come from here too (ST:BuildWords).
--
--   The facts (ST:BuildFacts)   spec, kind ("Leveling, level 10-60" or "Level-60 layout": a build the guide gives only as its level-60
--                               layout has no order, and none is invented), source ("From Icy Veins, via TimeSaver"), the point split
--                               ("31 Survival, 20 Marksmanship"), three key talents (the deepest ones the build takes), the build's own
--                               short summary when the data has one, its web address, and "In use" when this character follows it.
--   The card (ST:BuildCard)     mode "full": name, In use, kind and source, three talent icons and the split, the summary, and the
--                               buttons Follow this build and Show on tree. mode "pick": the same card in setup (a click anywhere picks
--                               it; Chosen instead of In use). mode "line": one compact card (a talent icon, name, kind and source, the
--                               mark, and the buttons a place asks for). Two more kinds of card in the same shape: "No suggested build for
--                               this spec yet" (a spec with no public build that fits the tree in use) and "Plan by hand".
-- The web address is in the card's tooltip. Show on tree shows the build on the Talents tab without following it (ST:ShowOnTree).
-- Nothing here spends a point, buys a spell or changes a talent.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local Skin, Kit = Panoply.Skin, Panoply.Kit
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

ST.BUILD_WORDS = {
  none = "No suggested build for this spec yet",
  noneSub = "Plan your own: click talents in the order you want them.",
  byHand = "Plan by hand",
  byHandSub = "An empty plan of your own: click talents in the order you want them.",
  follow = "Follow this build", show = "Show on tree", inUse = "In use", chosen = "Chosen", showing = "Not followed",
  leveling = "Leveling, level %s", layout = "Level-60 layout", level60 = "Level 60",
  layoutTip = "The guide gives this build only as its level-60 layout, so there is no level by level order. Spend the points in any order the game allows.",
  -- (0.9.9.4 review: a build some of whose points Panoply named, the data's `inferred`, says so)
  inferredTip = "A few points were filled in by Panoply where the guide's page did not name them.",
}
local WORDS = ST.BUILD_WORDS

-------------------------------------------------------------------------------
-- The facts
-------------------------------------------------------------------------------
-- "TimeSaver (from Icy Veins)" -> "Icy Veins", "TimeSaver"; any other source line -> it, nil
function ST:BuildGuide(sourceLine)
  if type(sourceLine) ~= "string" or sourceLine == "" then return nil, nil end
  local via, guide = sourceLine:match("^(.-) %(from (.-)%)$")
  if guide then return guide, via end
  return sourceLine, nil
end

-- "From Icy Veins, via TimeSaver" (a public build), "Panoply Suite's own plan" (Classic Era's basic set), "Your own plan"
function ST:BuildSourceText(p)
  if type(p) ~= "table" then return nil end
  if p.source == "public" then
    local guide, via = self:BuildGuide(p.sourceLine)
    if guide and via then return ("From %s, via %s"):format(guide, via) end
    return guide and ("From " .. guide) or "From a public guide"
  end
  if p.source == "basic" then return "Panoply Suite's own plan" end
  if p.source == "own" then return "Your own plan" end
  return "From " .. tostring(p.source)
end

-- the spec a build is for: its own, else the tree it puts the most points in
function ST:BuildSpec(p)
  if type(p) ~= "table" then return nil end
  if p.spec then return p.spec end
  local _, spent = self:RanksAt(p.class, p.points or {})
  local main, best = nil, 0
  for i, n in ipairs(spent or {}) do if n > best then main, best = i, n end end
  return main
end

-- "Leveling, level 10-60" (a build with its order), "Leveling, level 40-60" (a build whose guide says so in its name), "Level-60 layout"
function ST:BuildKind(p)
  if type(p) ~= "table" then return nil end
  if self:NoOrder(p) then return WORDS.layout end
  if p.at60 then return WORDS.level60 end
  local a, b = tostring(p.name or ""):match("(%d+)%-(%d+)%s*$")
  return WORDS.leveling:format(a and (a .. "-" .. b) or ((self.FIRST_LEVEL or 10) .. "-" .. (self.LAST_LEVEL or 60)))
end

-- up to three talents that say what a build is: the deepest ones it takes (a one-point talent first on a row: those are the abilities)
function ST:BuildKeyTalents(p, n)
  n = n or 3
  local T = type(p) == "table" and self:Trees(p.class) or nil
  if not T then return {} end
  local ranks = self:RanksAt(p.class, p.points or {})
  local list = {}
  for id, r in pairs(ranks) do
    local tal = T.byId[id]
    if tal and r > 0 then list[#list + 1] = { tal = tal, rank = r } end
  end
  table.sort(list, function(a, b)
    if a.tal.tier ~= b.tal.tier then return a.tal.tier > b.tal.tier end
    local a1, b1 = a.tal.ranks == 1, b.tal.ranks == 1
    if a1 ~= b1 then return a1 end
    if a.tal.tab ~= b.tal.tab then return a.tal.tab < b.tal.tab end
    return tostring(a.tal.id) < tostring(b.tal.id)
  end)
  local out = {}
  for i = 1, min(n, #list) do
    local e = list[i]
    out[i] = { name = e.tal.name, rank = e.rank, max = e.tal.ranks, icon = self:TalentIcon(e.tal, p.class), tal = e.tal }
  end
  return out
end

-- the build (a ready-made plan) this character follows, or nil: the plan itself, or the ready-made plan an untouched copy stands for
function ST:FollowedBuild(slot)
  local t = self:Tracked(slot)
  if not t then return nil end
  if t.source ~= "own" then return t end
  if self:IsMirror(t) then return self:Find(t.from, t.class) end
  return nil
end

-- Everything a card shows about a ready-made plan p (any source), as plain values (the tests read these):
-- { key, name, class, spec, specName, kind, noOrder, source, guide, via, split, keys = { { name, rank, max, icon } }, summary, url,
--   inUse, previewing, default, public, inferred }
function ST:BuildFacts(p)
  if type(p) ~= "table" then return nil end
  local T = self:Trees(p.class)
  local spec = self:BuildSpec(p)
  local guide, via = self:BuildGuide(p.sourceLine)
  local followed = self:FollowedBuild()
  return {
    key = p.key, name = p.name or p.key, class = p.class, spec = spec, specName = spec and T and T.tabs[spec] and T.tabs[spec].name or nil,
    kind = self:BuildKind(p), noOrder = self:NoOrder(p) or nil, source = self:BuildSourceText(p), guide = guide, via = via,
    split = self:TreeSummary(p.class, p.points or {}), keys = self:BuildKeyTalents(p, 3),
    -- (a short summary only when the build's data has one of its own; a "Source: ..." line is not a summary)
    summary = (type(p.blurb) == "string" and p.blurb ~= "") and p.blurb or nil,
    url = p.link, public = p.source == "public" or nil, default = p.default or nil, inferred = p.inferred and true or nil,
    -- (the guides whose build for this spec is folded into this one: "One per spec, extra only if different")
    alsoFrom = (type(p.alsoFrom) == "table" and #p.alsoFrom > 0) and p.alsoFrom or nil,
    inUse = followed ~= nil and followed.key == p.key or nil,
    previewing = self.previewKey ~= nil and self.previewKey == p.key or nil,
  }
end

-- The builds of a class by spec, in the tree's order, for the setup and the Builds tab. Every spec is listed, with an empty list when no
-- build fits it. filter: { spec = 1..3, kind = "order" | "layout" } (either may be nil).
-- Returns { { spec, name, builds = { facts... } } }, and the number of builds before the filter.
function ST:BuildsBySpec(classFile, filter)
  classFile = classFile or self:ClassFile()
  filter = filter or {}
  local T = self:Trees(classFile)
  if not T then return {}, 0 end
  local out, total = {}, 0
  for i, tab in ipairs(T.tabs) do out[i] = { spec = i, name = tab.name, builds = {} } end
  for _, p in ipairs(self:ReadyMade(classFile)) do
    local f = self:BuildFacts(p)
    total = total + 1
    local keep = (not filter.spec or f.spec == filter.spec)
      and (not filter.kind or (filter.kind == "layout") == (f.noOrder == true))
    if keep and f.spec and out[f.spec] then table.insert(out[f.spec].builds, f) end
  end
  if filter.spec then out = { out[filter.spec] } end
  return out, total
end

-- The words that name the followed build in a sentence: "your Survival leveling build (Icy Veins)", "your plan \"My Hunter\"", or nil
-- with no plan. (Home's talent line, the level-up card, the next-talent card, the Trainer Helper, the Gear tab.)
function ST:BuildWords(slot)
  local b = self:FollowedBuild(slot)
  if b then
    if b.source == "public" then
      local guide = self:BuildGuide(b.sourceLine)
      return ("your %s build (%s)"):format(b.name or b.key, guide or "a public guide"), b
    end
    return ("your %s plan"):format(b.name or b.key), b
  end
  local t = self:Tracked(slot)
  if t then return ("your plan \"%s\""):format(t.name or t.key), nil end
  return nil, nil
end

-------------------------------------------------------------------------------
-- Show on tree: a build on the Talents tab, not followed
-------------------------------------------------------------------------------
-- The Talents tab shows the build (its tree, its order or its layout) and says it is not followed; Follow this build follows it, Back to
-- my plan ends it. A click on a talent while it shows makes a plan of your own from it (as an edit of any ready-made build does).
function ST:ShowOnTree(key)
  local p = self:Find(key)
  if not (p and p.class == self:ClassFile()) then return nil end
  if self:FollowedBuild() and self:FollowedBuild().key == key then self.previewKey = nil
  else self.previewKey = key end
  self.edit, self.undo = nil, nil
  self:OpenPlanner()
  return p
end
function ST:PreviewPlan()
  local k = self.previewKey
  if not k then return nil end
  local p = self:Find(k)
  if p and p.class == self:ClassFile() and p.source ~= "own" then return p end
  self.previewKey = nil
  return nil
end
function ST:EndPreview()
  if not self.previewKey then return false end
  self.previewKey, self.edit = nil, nil
  return true
end
-- Follow this build (anywhere): followed at once, the preview (if it was this build) ends
function ST:FollowBuild(key)
  local p = self:ChoosePlan(key)
  self.previewKey = nil
  return p
end

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------
ST.CARD = { pad = 12, icon = 24, lineIcon = 28, gap = 6, minW = 220 }
local CARD = ST.CARD

local function tint(t, c, a) if t and c then t:SetVertexColor(c[1], c[2], c[3], a or 1) end end
local function setText(fs, words, w)
  fs:SetText(words or "")
  fs:SetWidth(max(10, w))
  local h = ceil(TH(fs, max(10, w)))
  fs:SetHeight(h)
  return h
end
local function place(obj, parent, x, y) obj:ClearAllPoints(); obj:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end

-- an icon tile with its own tooltip (the talent's name and the build's rank in it)
local function iconTile(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.panoplyGapOK = true
  if f.EnableMouse then f:EnableMouse(true) end
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  Skin.Round(f.bg, 4, Skin.TEX.RFill)
  tint(f.bg, Skin.colors.slotLine)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  if f.icon.SetTexCoord then f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  Skin.Tooltip(f, "", nil)
  f:SetScript("OnEnter", function(self) if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
  f:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  return f
end

-- ST:BuildCard(parent, opts)
--   opts.mode      "full" | "pick" | "line"
--   opts.onFollow(facts), opts.onShow(facts), opts.onByHand(), opts.onPick(card) (pick mode: a click anywhere on the card)
--   opts.actions   line mode: { "follow" | "show" | "change" | "back" | "byhand" ... } the buttons it shows ("change" opens the Builds tab)
-- card:Set(facts | { none = true, specName } | { byHand = true }, o)  o.selected (pick), o.mark (words for the chip)
-- card:Fit(width) lays it out for that width and returns its height (the card's own frames only; nothing outside it moves).
function ST:BuildCard(parent, opts)
  opts = opts or {}
  local mode = opts.mode or "full"
  local c
  if mode == "pick" then
    -- the setup's cards are buttons: a click anywhere picks the build (as the old plan cards did)
    c = Skin.Button(parent, "", 200, 60, function(self) if opts.onPick then opts.onPick(self) end end)
    c.label:SetText("")
    c.tipAnchor = Panoply.Wizard and Panoply.Wizard.TipBeside or nil
  else
    c = CreateFrame("Button", nil, parent)
    c:SetSize(200, 60)
    c.panoplyBox = true
    c.fill = c:CreateTexture(nil, "BACKGROUND")
    c.fill:SetAllPoints(c)
    Skin.Round(c.fill, Skin.RADIUS.card, Skin.TEX.RFill)
    tint(c.fill, Kit.Color("surface.1"))
    Skin.Tooltip(c, "", nil)
    c:SetScript("OnEnter", function(self) if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
    c:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  end
  c.panoplyKit, c.panoplyGapOK, c.panoplyBuildCard = "BuildCard", true, mode
  c.mode = mode
  c.stripe = c:CreateTexture(nil, "BORDER")
  c.stripe:SetWidth(2)
  c.stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -Skin.RADIUS.card)
  c.stripe:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, Skin.RADIUS.card)
  c.stripe:Hide()
  c.title = Skin.Name(c, mode == "line" and 13 or 14, Skin.colors.text)
  c.sub = Skin.Ink(c, 11, Skin.colors.inkSoft)
  c.split = Skin.Ink(c, 12, Skin.colors.ink)
  c.summary = Skin.Ink(c, 12, Skin.colors.inkSoft)
  for _, fs in ipairs({ c.title, c.sub, c.split, c.summary }) do
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
  end
  c.chip = Kit.StatusChip(c, "state.good", WORDS.inUse)
  c.chip:Hide()
  c.icons = {}
  for i = 1, (mode == "line" and 1 or 3) do c.icons[i] = iconTile(c, mode == "line" and CARD.lineIcon or CARD.icon) end
  local function follow() if opts.onFollow and c.facts then opts.onFollow(c.facts, c) end end
  local function show() if opts.onShow and c.facts then opts.onShow(c.facts, c) end end
  c.btn = {
    follow = Skin.Button(c, WORDS.follow, 120, 24, follow, WORDS.follow, "Your talent hints, the spells to buy and the gear weights follow this build."),
    show = Skin.Button(c, WORDS.show, 100, 24, show, WORDS.show, "Shows this build on the Talents tab without following it."),
    change = Skin.Button(c, "Change build", 100, 24, function() if opts.onChange then opts.onChange(c.facts, c) else ST:OpenBuilds() end end,
      "Change build", "Opens the Class page's Builds tab: every suggested build for your class."),
    pick = Skin.Button(c, "Pick a build", 100, 24, function() if opts.onChange then opts.onChange(c.facts, c) else ST:OpenBuilds() end end,
      "Pick a build", "Opens the Class page's Builds tab: every suggested build for your class."),
    back = Skin.Button(c, "Back to my plan", 110, 24, function() if opts.onBack then opts.onBack(c.facts, c) end end,
      "Back to my plan", "Stops showing this build. Nothing was changed."),
    byhand = Skin.Button(c, WORDS.byHand, 100, 24, function() if opts.onByHand then opts.onByHand(c) end end,
      WORDS.byHand, "Starts an empty plan of your own on the Talents tab."),
  }
  c.order = { "follow", "show", "change", "pick", "back", "byhand" }
  for _, k in ipairs(c.order) do c.btn[k]:Hide() end

  -- what the card shows
  function c:Set(f, o)
    o = o or {}
    self.facts = f
    self.kind = (f and f.none) and "none" or (f and f.byHand) and "byhand" or "build"
    self.pickKey = o.pickKey or (f and f.key) or nil
    self.selected = o.selected and true or nil
    local mark = o.mark
    local title, sub
    if self.kind == "none" then
      title = f.title or WORDS.none
      sub = f.sub or ((f.withSpec and f.specName and (f.specName .. " \194\183 ") or "") .. WORDS.noneSub)
      self.tip, self.tipBody = f.title or WORDS.none, "No public guide's build fits this spec's talent tree in this game yet. Plan your own: click talents on the Talents tab in the order you want them."
    elseif self.kind == "byhand" then
      title, sub = f.title or WORDS.byHand, f.sub or WORDS.byHandSub
      self.tip, self.tipBody = f.title or WORDS.byHand, f.tip or "Starts an empty plan of your own: click talents on the Talents tab in the order you want them."
    else
      title = f.name
      sub = (f.kind or "") .. ((f.source and f.source ~= "") and (" \194\183 " .. f.source) or "")
      if not mark then
        if mode == "pick" then mark = self.selected and WORDS.chosen or nil
        elseif f.previewing then mark = WORDS.showing
        elseif f.inUse then mark = WORDS.inUse end
      end
      local body = {}
      body[#body + 1] = (f.specName and (f.specName .. ". ") or "") .. (f.kind or "") .. ". " .. (f.source or "") .. "."
      if f.split then body[#body + 1] = "Talents: " .. f.split .. "." end
      if f.noOrder then body[#body + 1] = WORDS.layoutTip end
      if f.inferred then body[#body + 1] = WORDS.inferredTip end
      if f.alsoFrom then
        body[#body + 1] = ("A similar build for this spec is in %s's guide; it is not listed apart."):format(table.concat(f.alsoFrom, "'s and "))
      end
      if f.url then body[#body + 1] = f.url end
      self.tip, self.tipBody = f.name, table.concat(body, "\n")
    end
    self.title:SetText(title or "")
    self.sub:SetText(sub or "")
    self.split:SetText((self.kind == "build" and mode ~= "line") and (f.split or "") or "")
    self.summary:SetText((self.kind == "build" and mode ~= "line") and (f.summary or "") or "")
    self.markText = mark
    if mark then self.chip:Set(mark == WORDS.showing and "state.warn" or "state.good", mark) self.chip:Show() else self.chip:Hide() end
    -- the icons: the key talents (a build), none for the other two kinds
    for i, t in ipairs(self.icons) do
      local k = self.kind == "build" and f.keys and f.keys[i] or nil
      if k then
        t.icon:SetTexture(k.icon)
        t.tip, t.tipBody = k.name, ("%d of %d in this build."):format(k.rank, k.max)
        t.panoplyTalent = k.name
        t:Show()
      else t:Hide() t.panoplyTalent = nil end
    end
    -- the buttons this card shows
    self.want = {}
    if mode == "line" then
      for _, k in ipairs(o.actions or opts.actions or {}) do
        local ok = (k == "follow" and self.kind == "build" and not (f and f.inUse)) or (k == "show" and self.kind == "build")
          or (k == "change") or (k == "pick") or (k == "back") or (k == "byhand" and self.kind ~= "build")
        if ok then self.want[#self.want + 1] = k end
      end
    elseif self.kind == "build" then
      if not (f.inUse and mode ~= "pick") then self.want[#self.want + 1] = "follow" end
      if opts.onShow then self.want[#self.want + 1] = "show" end
    elseif opts.onByHand and mode ~= "pick" then
      self.want[#self.want + 1] = "byhand"
    end
    for _, k in ipairs(self.order) do self.btn[k]:Hide() end
    for _, k in ipairs(self.want) do self.btn[k]:Show() end
    self:Look()
    return self
  end

  -- selected / in use: an accent stripe (pick mode: the selected outline of a setup card)
  function c:Look()
    local on = self.selected or (self.facts and (self.facts.inUse or self.facts.previewing))
    if mode == "pick" then
      if self.Paint then self:Paint(self.selected and "sel" or "up") end
      local t = self.selected and Skin.colors.heading or Skin.colors.text
      self.title:SetTextColor(t[1], t[2], t[3], 1)
    end
    if on and self.kind == "build" then
      tint(self.stripe, Kit.Color((self.facts and self.facts.previewing) and "state.warn" or "state.good"))
      self.stripe:Show()
    else self.stripe:Hide() end
    if self.kind == "none" then
      local m = Skin.colors.inkSoft
      self.title:SetTextColor(m[1], m[2], m[3], 1)
    end
  end
  function c:SetSelected(on)
    self.selected = on and true or nil
    if self.facts then self:Set(self.facts, { selected = self.selected, pickKey = self.pickKey }) end
  end

  -- the layout
  function c:Fit(width)
    width = max(CARD.minW, floor(width))
    self:SetWidth(width)
    local pad = mode == "pick" and (CARD.pad - 2) or CARD.pad
    local x0, inner = pad + 2, width - 2 * pad - 2
    local y = -pad
    local lineMode = mode == "line"
    local iconW = 0
    if lineMode and self.icons[1]:IsShown() then
      iconW = CARD.lineIcon + SP.m
      place(self.icons[1], self, x0, y)
    end
    -- the buttons first in line mode (at the right when the card is wide enough, else under the words)
    local btns = {}
    for _, k in ipairs(self.want) do btns[#btns + 1] = self.btn[k] end
    local btnW, btnH = 0, 0
    for _, b in ipairs(btns) do
      local bw, bh = Skin.FitButton(b, 70, max(70, inner))
      btnW, btnH = btnW + bw + SP.s, max(btnH, bh)
    end
    local rightBtns = lineMode and #btns > 0 and (inner - iconW - btnW) >= 200
    local textX = x0 + iconW
    local textW = inner - iconW - (rightBtns and btnW or 0)
    -- the title row: the title, then the mark at its right (0.9.9.4: no "Recommended" pill, our decision)
    local cw, ch = 0, 0
    if self.chip:IsShown() then cw, ch = self.chip:Set(self.chip.kind, self.markText) end
    local marks = cw > 0 and (cw + SP.s) or 0
    local tw = max(60, min(ceil(TW(self.title)) + 8, textW - marks))
    local th = setText(self.title, self.title:GetText(), tw)
    place(self.title, self, textX, y)
    local mx = textX + tw + SP.s
    local rowH = th
    if cw > 0 then
      -- (when the title takes the whole row, the mark goes on a row of its own under it)
      if mx + cw > textX + textW + 1 then
        y = y - rowH - 2
        place(self.chip, self, textX, y)
        rowH = ch
      else
        place(self.chip, self, mx, y - max(0, floor((th - ch) / 2)))
        rowH = max(rowH, ch)
      end
    end
    y = y - rowH - (mode == "pick" and 1 or 3)
    -- kind and source
    if (self.sub:GetText() or "") ~= "" then
      local sh = setText(self.sub, self.sub:GetText(), textW)
      place(self.sub, self, textX, y); self.sub:Show()
      y = y - sh
    else self.sub:Hide() end
    if lineMode then
      y = min(y, -pad - (iconW > 0 and CARD.lineIcon or 0))
      if rightBtns then
        local bx = x0 + inner - btnW + SP.s
        local by = -pad
        for _, b in ipairs(btns) do place(b, self, bx, by) bx = bx + b:GetWidth() + SP.s end
        y = min(y, by - btnH)
      elseif #btns > 0 then
        y = y - SP.s
        local bh = Skin.FlowButtons(self, btns, textX, y, inner - iconW, SP.s, 70)
        y = y - bh
      end
      self.split:Hide(); self.summary:Hide()
    else
      -- the key talents and the point split
      local shown = 0
      for _, t in ipairs(self.icons) do if t:IsShown() then shown = shown + 1 end end
      -- (the buttons go at the right of the icons and the split when they fit there with the split at least 160 wide, on two lines
      -- at most: a shorter card)
      local inRow = false
      if #btns > 0 and (self.summary:GetText() or "") == "" then
        local splitW = min(ceil(TW(self.split)) + 8, 160)
        inRow = shown * (CARD.icon + 4) + SP.s + splitW + SP.m + btnW <= inner
      end
      self.buttonsInRow = inRow or nil
      if shown > 0 or (self.split:GetText() or "") ~= "" then
        y = y - (mode == "pick" and 3 or CARD.gap)
        local rowH = max(shown > 0 and CARD.icon or 0, inRow and btnH or 0)
        local iy = y - floor((rowH - CARD.icon) / 2)
        local ix = x0
        for _, t in ipairs(self.icons) do if t:IsShown() then place(t, self, ix, iy) ix = ix + CARD.icon + 4 end end
        local sx = shown > 0 and (ix + SP.s - 4) or x0
        local sw = x0 + inner - sx - (inRow and (btnW + SP.s) or 0)
        local sh = 0
        if (self.split:GetText() or "") ~= "" then
          sh = setText(self.split, self.split:GetText(), sw)
          place(self.split, self, sx, y - max(0, floor((rowH - sh) / 2)))
          self.split:Show()
        else self.split:Hide() end
        if inRow then
          local bx = x0 + inner - btnW + SP.s
          for _, b in ipairs(btns) do place(b, self, bx, y - floor((rowH - b:GetHeight()) / 2)) bx = bx + b:GetWidth() + SP.s end
        end
        y = y - max(rowH, sh)
      else self.split:Hide() end
      if (self.summary:GetText() or "") ~= "" then
        y = y - CARD.gap
        local mh = setText(self.summary, self.summary:GetText(), inner)
        place(self.summary, self, x0, y); self.summary:Show()
        y = y - mh
      else self.summary:Hide() end
      if #btns > 0 and not inRow then
        y = y - SP.s - 2
        local bh = Skin.FlowButtons(self, btns, x0, y, inner, SP.s, 70)
        y = y - bh
      end
    end
    local h = ceil(-y + pad)
    self:SetHeight(h)
    self.panoplyH = h
    return h
  end
  return c
end

-- a spec's heading over its cards (setup, Builds tab): the spec's name, and how many builds it has
function ST:SpecHeading(parent, name, n)
  local fs = Skin.Name(parent, 13, Skin.colors.heading)
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(n and n > 0 and ("%s \194\183 %d %s"):format(name, n, n == 1 and "build" or "builds") or name)
  return fs
end

-- the Class page's Builds tab (Modules/ClassPages/PageTabs.lua); without the Class page, its Talents
function ST:OpenBuilds()
  local CP = Panoply.ClassPages
  if CP and CP.Open then return CP:Open(nil, "builds") end
  return self:OpenPlanner()
end

-- The card above the Talents tab's trees: what the tree shows and where it comes from. Returns facts and Set's options, or nil.
--   a build shown with Show on tree     the build, "Showing, not followed", Follow this build and Back to my plan
--   a followed build                    the build, In use, Change build
--   your edited copy of a build         the build's facts under your plan's name, "Your copy", Change build
--   a plan of your own                  its name, "Your own plan", Change build
--   nothing followed (builds exist)     "No build followed yet", Pick a build
function ST:TalentsCard()
  local pv = self:PreviewPlan()
  if pv then return self:BuildFacts(pv), { actions = { "follow", "back" } } end
  local fb = self:FollowedBuild()
  if fb then return self:BuildFacts(fb), { actions = { "change" } } end
  local t = self:Tracked()
  if t then
    local o = t.from and self:Find(t.from, t.class)
    if o and o.source ~= "own" then
      local f = self:BuildFacts(o)
      f.name, f.split, f.keys = t.name or t.key, self:TreeSummary(t.class, t.points or {}), self:BuildKeyTalents(t, 3)
      f.inUse = true
      return f, { actions = { "change" }, mark = "Your copy" }
    end
    return { byHand = true, title = t.name or t.key, sub = "Your own plan: " .. self:TreeSummary(t.class, t.points or {}) .. "." }, { actions = { "change" } }
  end
  if #self:ReadyMade() > 0 then
    return { none = true, title = "No build followed yet", sub = "Pick one on the Builds tab, or click talents to plan by hand." }, { actions = { "pick" } }
  end
  return nil
end
