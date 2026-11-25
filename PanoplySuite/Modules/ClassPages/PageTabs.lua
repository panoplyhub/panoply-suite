-- Panoply Suite 0.9.5 phase 4H: the Class page's Talents, Spells and Gear tabs (docs/specs/page-redesigns-03-class.md sections 4, 5, 7).
-- The frame and the other tabs are Page.lua; Pet is Modules/HunterPet/PetTab.lua.
--
--   Talents   the talent planner (Modules/SpecTrainer/Planner.lua), drawn inside the tab: Next point, the three trees (left-click adds the
--             plan's next rank, right-click takes the last one back), the goal of each tree, Level by level. Edits are kept at once.
--   Spells    a timeline instead of 20+ closed rows: Now and Next visit open, each later trainer level one compact row with its spells'
--             icons ("Level 18 · 60s"), a click opens its names and costs. Skipped ranks are greyed and struck through, with the reason
--             in the tooltip. "Level 15 to 60: 94g 30s" in the header; the nearest class trainer (and pet trainer) at the top.
--   Gear      the slot grid (UI/SlotGrid.lua) on the left, the ranked next upgrades across every slot on the right; a click on a slot
--             lists only that slot. "Weighed for Beast Mastery leveling" (the plan's name opens Talents). One gear engine for the suite
--             (Panoply.Gear): this tab's slice is everything up to five levels ahead.
-- Nothing here buys, equips, spends or casts: buttons change what the page shows or add a waypoint through Go to.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local U = CP.UI

local function ST() return Panoply.SpecTrainer end
local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end
local function stOn() return ST() ~= nil and Panoply.Modules:IsOn("spectrainer") end
local OFF = "Talents & spells is switched off, so this tab is empty. Turn it on with the switch at the top right. Your plan is kept."

-- icon slots of the page (spec 03 section 11); every fallback is the game's own file, drawn only when the game says it has it
local I = "Interface\\Icons\\"
Kit.RegisterIcon("icon.badge.new", { glyph = "Star" })
Kit.RegisterIcon("icon.ui.copy", { game = { I .. "INV_Misc_Note_01", I .. "INV_Scroll_03" } })
Kit.RegisterIcon("icon.trainer", { icon = "Train" })
Kit.RegisterIcon("icon.stable", { game = { I .. "Ability_Hunter_BeastTaming", I .. "Ability_Hunter_BeastCall" } })

local function offMessage(holder, w)
  if not holder.offText then holder.offText = select(2, U.Text(holder, 0, 0, w, 13, "text.muted", OFF, true)) end
  holder.offText:SetWidth(w)
  local h = ceil(TH(holder.offText, w))
  holder.offText:SetHeight(h)
  holder.offText:Show()
  return h + SP.s
end

-------------------------------------------------------------------------------
-- Talents
-------------------------------------------------------------------------------
CP.TALENTS_MIN_H = 440      -- the Wide band's least height (a smaller window scrolls the tab)
CP.TABS.talents = {
  Sig = function(v) return stOn() and "on" or "off" end,
  Draw = function(p, holder, w, viewH, v)
    local s = ST()
    if not stOn() then
      if s and s.planner then s.planner:Hide() end
      return offMessage(holder, w)
    end
    if holder.offText then holder.offText:Hide() end
    -- (0.9.9.4: neither the game's tree nor a static one for this class: one plain line)
    if not s:Trees() then
      if s.planner then s.planner:Hide() end
      if not holder.noTree then holder.noTree = select(2, U.Text(holder, 0, 0, w, 13, "text.muted", s.NO_TREE_LINE, true)) end
      holder.noTree:SetWidth(w)
      local th = ceil(TH(holder.noTree, w))
      holder.noTree:SetHeight(th)
      holder.noTree:Show()
      return th + SP.s
    end
    if holder.noTree then holder.noTree:Hide() end
    local host = s:PlannerHost(holder)
    host:ClearAllPoints(); host:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    s.plannerBand = v.band
    local wide = v.band == "wide"
    local h = wide and max(viewH, CP.TALENTS_MIN_H) or 2400
    host:SetSize(w, h)
    host:Show()
    -- (the real talents are read when the tab is first drawn and when the game says they changed, never on a plain refresh)
    if not holder.readLive then holder.readLive = true s.plannerLive = nil end
    local used = s:LayoutPlanner() or h
    if not wide then h = used host:SetHeight(h) end
    -- fills the view in the Wide band (the Level by level list scrolls inside); the tab scrolls only when the window is too short
    return h, wide and h <= viewH
  end,
}

-------------------------------------------------------------------------------
-- Builds (0.9.9.4)
-------------------------------------------------------------------------------
-- Every suggested build of the class by spec, on the shared build card (Modules/SpecTrainer/BuildCard.lua): Follow this build, Show on
-- tree, In use on the one followed. Filter chips: the spec, and the kind (a level by level order, or a level-60 layout only). A spec no
-- build fits says "No suggested build for this spec yet". Plan by hand at the end. CP.buildFilter is kept for the play session.
CP.buildFilter = {}
Kit.OnReset("class", function() CP.buildFilter = {} end)
CP.BUILDS_HELP = "The talent builds of public guide sites (Maxroll, Wowhead, Method, Icy Veins), read through TimeSaver's free talent calculator. A build shows only when every talent it names is in your talent tree and it keeps the game's rules. A level-60 layout has no level by level order. The web address of each build is in its tooltip."
CP.BUILDS_KINDS = { { nil, "Any kind" }, { "order", "Leveling order" }, { "layout", "Level-60 layout" } }
function CP:SetBuildFilter(key, value)
  self.buildFilter[key] = value
  Menu:RefreshCurrent()
end
CP.TABS.builds = {
  Sig = function(v, w)
    if not stOn() then return "off" end
    local s = ST()
    local f = CP.buildFilter
    return table.concat({ tostring(f.spec), tostring(f.kind), tostring(s:PlanValue()), tostring(s.previewKey),
      tostring(s.trees and s.trees[v.class]), #s:ReadyMade(v.class), v.band }, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if holder.drawn then return holder.panoplyH end
    holder.drawn = true
    if not stOn() then holder.panoplyH = offMessage(holder, w) return holder.panoplyH end
    local s = ST()
    local f = CP.buildFilter
    local y = 0
    local hdr = Kit.SectionHeader(holder, { title = "Talent builds", help = CP.BUILDS_HELP })
    y = y - hdr:Layout(0, y, w) - SP.s
    -- the chips: the spec, then the kind
    local all = s:BuildsBySpec(v.class)
    p.buildChips = {}
    local specChips = {}
    local function chip(label, active, fn, tip)
      local b = Skin.Tab(holder, label, 90, fn, label, tip)
      b.panoplyPicker = true
      b:SetActive(active)
      p.buildChips[#p.buildChips + 1] = b
      return b
    end
    specChips[1] = chip("All specs", f.spec == nil, function() CP:SetBuildFilter("spec", nil) end, "Builds for every spec.")
    for _, g in ipairs(all) do
      local b = chip(("%s %d"):format(g.name, #g.builds), f.spec == g.spec, function() CP:SetBuildFilter("spec", g.spec) end, "Only " .. g.name .. " builds.")
      b.panoplySpec = g.spec
      specChips[#specChips + 1] = b
    end
    y = y - Skin.FlowButtons(holder, specChips, 0, y, w, SP.s, 70) - SP.s
    local kindChips = {}
    for _, k in ipairs(CP.BUILDS_KINDS) do
      local b = chip(k[2], f.kind == k[1], function() CP:SetBuildFilter("kind", k[1]) end,
        k[1] == "layout" and "Builds the guide gives only as their level-60 layout: no level by level order." or
        k[1] == "order" and "Builds with a level by level order from level 10." or "Both kinds.")
      b.panoplyKind = k[1] or "any"
      kindChips[#kindChips + 1] = b
    end
    y = y - Skin.FlowButtons(holder, kindChips, 0, y, w, SP.s, 70) - SP.m
    -- (0.9.9.4: no tree for this class at all: one plain line, then Plan by hand)
    if not s:Trees(v.class) then
      y = y - U.Text(holder, 0, y, w, 12, "text.muted", s.NO_TREE_LINE, true) - SP.m
    end
    -- the cards, by spec
    local groups, total = s:BuildsBySpec(v.class, f)
    local cols = (v.band == "wide" and w >= 2 * s.CARD.minW + SP.m) and 2 or 1
    local cw = floor((w - (cols - 1) * SP.m) / cols)
    p.buildCards, p.buildGroups = {}, {}
    local function follow(facts) s:FollowBuild(facts.key) Menu:RefreshCurrent() end
    local function show(facts) s:ShowOnTree(facts.key) end
    for _, g in ipairs(groups) do
      local th = U.Text(holder, 0, y, w, 13, "gold.title", #g.builds > 0 and ("%s \194\183 %d %s"):format(g.name, #g.builds, plural(#g.builds, "build")) or g.name, false, true)
      y = y - th - SP.s
      p.buildGroups[#p.buildGroups + 1] = g
      if #g.builds == 0 then
        local c = s:BuildCard(holder, { mode = "line" })
        local filtered = f.kind ~= nil and #((all[g.spec] or {}).builds or {}) > 0
        c:Set(filtered and { none = true, specName = g.name, title = "No build of this kind for " .. g.name,
          sub = "Pick Any kind to see its other builds." } or { none = true, specName = g.name })
        local h = c:Fit(w)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
        y = y - h - SP.m
      else
        local i = 1
        while i <= #g.builds do
          local rowH, row = 0, {}
          for k = 0, cols - 1 do
            local facts = g.builds[i + k]
            if facts then
              local c = s:BuildCard(holder, { mode = "full", onFollow = follow, onShow = show })
              c:Set(facts)
              rowH = max(rowH, c:Fit(cw))
              row[#row + 1] = c
              p.buildCards[#p.buildCards + 1] = c
            end
          end
          for k, c in ipairs(row) do
            c:SetHeight(rowH)
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", (k - 1) * (cw + SP.m), y)
          end
          y = y - rowH - SP.m
          i = i + cols
        end
      end
    end
    -- Plan by hand
    local own = s:BuildCard(holder, { mode = "line", actions = { "byhand" }, onByHand = function() s:NewEmptyPlan() CP:GoTab("talents") end })
    own:Set({ byHand = true })
    local oh = own:Fit(w)
    own:ClearAllPoints(); own:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
    p.buildByHand = own
    y = y - oh - SP.m
    -- where they come from, and how many the tree in use leaves out
    local dropped = s.droppedBuilds and s.droppedBuilds[v.class] or {}
    local words = "Builds from public guides, read through TimeSaver. Each card's tooltip has its web address."
    if #dropped > 0 then
      words = words .. (" %d %s from the guides %s not fit your talent tree and %s left out."):format(#dropped, plural(#dropped, "build"),
        #dropped == 1 and "does" or "do", #dropped == 1 and "is" or "are")
    end
    y = y - U.Text(holder, 0, y, w, 11, "text.muted", words, true) - SP.s
    p.buildsTotal = total
    holder.panoplyH = -y
    return holder.panoplyH
  end,
}

-------------------------------------------------------------------------------
-- Spells
-------------------------------------------------------------------------------
CP.SPELL_ICON = 18
CP.spellFilter = ""

-- the words of a row: "Serpent Sting Rank 2" and what it costs
local function rowName(r) return r.name .. ((r.rank and r.rank ~= "") and (" " .. r.rank) or "") end
local function matches(r)
  local f = (CP.spellFilter or ""):lower()
  return f == "" or rowName(r):lower():find(f, 1, true) ~= nil
end

-- The tab's data: { sp, total, head, trainers = { class = text, pet = text|nil, words = { blocks } } }
function CP:SpellsData()
  local s = ST()
  local sp = s:SpellPlan()
  local d = { sp = sp }
  d.head = ("Level %d to %d: %s"):format(sp.from, sp.to, s.Money(sp.buy.cost))
  d.words = self:TrainerBlocks(self:PlayerClass(), self:Experience(), C.IsForever())
  -- (the nearest trainer is found with the travel router: asked again at most every 30 seconds, not at every redraw)
  local now = C.GetTime and C.GetTime() or 0
  local tc = self.trainerCache
  if not tc or now - tc.at > 30 or now < tc.at then
    local ok, t = pcall(s.NearestTrainer, s)
    tc = { at = now, t = ok and t or nil }
    self.trainerCache = tc
  end
  d.trainer = tc.t
  d.pet = self:PlayerClass() == "HUNTER" and Panoply.HunterPet and Panoply.HunterPet.KnowsPetTrainers and Panoply.HunterPet:KnowsPetTrainers() or false
  return d
end

-- a strike-through line over a font string (skipped ranks)
local function strike(parent, fs, w)
  local t = parent:CreateTexture(nil, "OVERLAY")
  Skin.Solid(t, Kit.Color("text.muted"), 0.9)
  t:SetHeight(1)
  t:SetPoint("LEFT", fs, "LEFT", 0, 0)
  t:SetWidth(max(4, min(w, ceil(TW(fs)) + 2)))
  t.panoplyStrike = true
  return t
end

-- one spell, open: icon, name and rank, cost; a skipped one greyed and struck, the reason in its tooltip
local function spellRow(holder, x, y, w, r, list)
  local ic = U.Icon(holder, x, y, CP.SPELL_ICON, r.icon or 134400, r.kind == "skip")
  local cost
  if r.kind ~= "skip" then
    local _cw, _ch
    _cw, _ch, cost = U.Word(holder, 0, y - 1, 12, "text.primary", ST().Money(r.cost), 120)
    cost:ClearAllPoints(); cost:SetPoint("TOPRIGHT", holder, "TOPLEFT", x + w, y - 1)
    if cost.SetJustifyH then cost:SetJustifyH("RIGHT") end
  end
  local nx = x + CP.SPELL_ICON + SP.s
  local room = w - (nx - x) - 80
  local token = r.kind == "skip" and "text.muted" or "text.primary"
  local nh, fs = U.Text(holder, nx, y - 1, room, 12, token, rowName(r) .. (r.kind == "opt" and "  (optional)" or ""), false)
  local st
  if r.kind == "skip" then st = strike(holder, fs, room) end
  -- the tooltip: the reason a rank is skipped or optional
  if r.why and r.why ~= "" then
    local hot = CreateFrame("Frame", nil, holder)
    hot.panoplyGapOK = true
    hot:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
    hot:SetSize(w - 70, max(CP.SPELL_ICON, nh))
    if hot.EnableMouse then hot:EnableMouse(true) end
    Skin.Tooltip(hot, rowName(r), (r.kind == "skip" and "Skipped: " or "Optional: ") .. r.why)
    hot:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
    hot:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    hot.panoplyWhy = r.why
  end
  list[#list + 1] = { row = r, icon = ic, name = fs, strike = st, cost = cost }
  return max(CP.SPELL_ICON, nh) + SP.xs
end

-- an open visit (Now, Next visit, or a later level that was clicked open)
local function openVisit(holder, x, y, w, title, v, list, extra)
  local y0 = y
  local th = U.Text(holder, x, y, w - 160, 13, "gold.title", title, false, true)
  local s = ST()
  local summary = v.buy.n > 0 and ("%d %s, %s"):format(v.buy.n, plural(v.buy.n, "spell"), s.Money(v.buy.cost)) or "nothing to buy"
  local _sw, _sh, sfs = U.Word(holder, 0, y, 12, "text.muted", summary, 160)
  sfs:ClearAllPoints(); sfs:SetPoint("TOPRIGHT", holder, "TOPLEFT", x + w, y)
  y = y - th - SP.s
  local shown = 0
  for _, r in ipairs(v.rows) do
    if matches(r) then y = y - spellRow(holder, x, y, w, r, list) shown = shown + 1 end
  end
  if shown == 0 then y = y - U.Text(holder, x, y, w, 12, "text.muted", #v.rows == 0 and "Nothing here." or "No spell here matches the search.", true) - SP.xs end
  if extra then y = y - extra(y) end
  return y0 - y + SP.m
end

CP.TABS.spells = {
  Sig = function(v, w)
    if not stOn() then return "off" end
    local d = CP:SpellsData()
    v.spells = d
    local t = { d.head, tostring(d.trainer and d.trainer.name), tostring(d.pet), CP.spellFilter or "", tostring(d.sp.level) }   -- not the gold: the tab never shows it, and a new copy was built on every coin
    for _, vis in ipairs(d.sp.visits) do
      t[#t + 1] = (vis.now and "N" or "V") .. vis.level .. (Kit.GetOpen("class", "spells/level" .. vis.level, false) and "o" or "c")
      for _, r in ipairs(vis.rows) do t[#t + 1] = r.kind .. r.name .. (r.rank or "") .. r.cost end
    end
    return table.concat(t, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if not stOn() then return offMessage(holder, w) end
    if holder.drawn then return holder.panoplyH end
    holder.drawn = true
    local s = ST()
    local d = v.spells or CP:SpellsData()
    local sp = d.sp
    local list = {}
    p.spellRows, p.laterRows = list, {}
    local y = 0
    -- the header: the running total, and what the list follows
    local hdr = Kit.SectionHeader(holder, { title = d.head, help = s:PlanIntro(sp) .. "\n\nPrices are what the trainer charges; until you visit one they come from Panoply Suite's own table. Skipped and optional spells are not counted." })
    y = y - hdr:Layout(0, y, w) - SP.s
    p.spellsHead = hdr
    if not sp.table then
      local h = U.Text(holder, 0, y, w, 12, "text.muted", "Panoply Suite Quest Data is not installed, so there is no spell plan. The trainer panel still lists what the trainer teaches.", true)
      holder.panoplyH = -y + h + SP.s
      return holder.panoplyH
    end
    -- the trainers: the nearest class trainer, and the pet trainer for a Hunter, with buttons that point the way
    do
      local x = 0
      local name = d.trainer and d.trainer.name and ("Class trainer: %s"):format(d.trainer.name) or "Class trainer: the nearest one your map knows"
      local go = U.IconButton(holder, "Arrow", nil, 20, function() s:PointToTrainer() end, "Point me to my trainer",
        "Adds the nearest class trainer to your waypoints; the arrow follows it.")
      go:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
      p.trainerGo = go
      x = x + 20 + SP.s
      local tipWords = {}
      for _, b in ipairs(d.words) do tipWords[#tipWords + 1] = (b.tag and (b.tag .. ": ") or "") .. b.text end
      local _link, lw = U.Link(holder, x, y - 2, name, max(60, floor(w * 0.55)), function() s:PointToTrainer() end, "Trainers",
        #tipWords > 0 and table.concat(tipWords, "\n\n") or "Any trainer of your class teaches the same spells.")
      x = x + lw + SP.l
      if d.pet then
        local pg = U.IconButton(holder, "Arrow", nil, 20, function() Panoply.HunterPet:GoToPetTrainer() end, "Point me to a pet trainer",
          "Adds the nearest pet trainer your map knows to your waypoints.")
        pg:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
        U.Link(holder, x + 20 + SP.s, y - 2, "Pet trainer", 120, function() Panoply.HunterPet:GoToPetTrainer() end, "Pet trainer",
          "Pet trainers teach your pet Growl, resistances and more.")
        p.petTrainerGo = pg
      end
      y = y - 22 - SP.s
    end
    -- the search
    local box = Skin.Input(holder, min(260, w), 24, "Search spells")
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
    box:SetText(CP.spellFilter or "")
    if box.placeholder then if (CP.spellFilter or "") ~= "" then box.placeholder:Hide() else box.placeholder:Show() end end
    box:SetScript("OnEnterPressed", function(b) CP.spellFilter = b:GetText() or "" if b.ClearFocus then b:ClearFocus() end Menu:RefreshCurrent() end)
    box:SetScript("OnEscapePressed", function(b) CP.spellFilter = "" b:SetText("") if b.ClearFocus then b:ClearFocus() end Menu:RefreshCurrent() end)
    p.spellSearch = box
    y = y - 24 - SP.m
    -- Now
    local nowV = sp.now
    local function pointMe(yy)
      local b = Skin.Button(holder, "Point me to my trainer", 160, 24, function() s:PointToTrainer() end, "Point me to my trainer",
        "Adds the nearest class trainer to your waypoints; the arrow follows it.")
      Skin.FitButton(b, 140, 220)
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, yy)
      p.pointMe = b
      return b:GetHeight() + SP.xs
    end
    if nowV and nowV.buy.n > 0 then
      y = y - openVisit(holder, 0, y, w, "Now", nowV, list, pointMe)
    else
      local h = U.Text(holder, 0, y, w, 13, "gold.title", "Now", false, true)
      y = y - h - SP.xs
      y = y - U.Text(holder, 0, y, w, 12, "text.muted", "Nothing to buy now.", true) - SP.m
    end
    -- Next visit
    if sp.next then
      y = y - openVisit(holder, 0, y, w, ("Next visit: level %d"):format(sp.next.level), sp.next, list)
    end
    -- Later levels: one compact row each, with the spell icons inline; a click opens it
    local later = {}
    for _, vis in ipairs(sp.visits) do if not vis.now and vis ~= sp.next then later[#later + 1] = vis end end
    if #later > 0 then
      local h = U.Text(holder, 0, y, w, 13, "gold.title", "Later levels", false, true)
      y = y - h - SP.s
      for _, vis in ipairs(later) do
        local id = "spells/level" .. vis.level
        -- (a search opens every level that has a spell it found, so the names show)
        local open = Kit.GetOpen("class", id, false) or (CP.spellFilter or "") ~= ""
        local any = false
        for _, r in ipairs(vis.rows) do if matches(r) then any = true break end end
        if any or (CP.spellFilter or "") == "" then
          local rowB = CreateFrame("Button", nil, holder)
          rowB.panoplyGapOK = true
          rowB:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
          local label = ("Level %d \194\183 %s"):format(vis.level, vis.buy.n > 0 and s.Money(vis.buy.cost) or "nothing to buy")
          local lw, lh = U.Word(rowB, 0, -2, 12, "text.primary", label, 150, true)
          local ix = max(110, lw + SP.m)
          local icons = {}
          local perRow = max(1, floor((w - ix) / (CP.SPELL_ICON + 3)))
          local n = 0
          for _, r in ipairs(vis.rows) do
            if matches(r) then
              local col, line = n % perRow, floor(n / perRow)
              local t = U.Icon(rowB, ix + col * (CP.SPELL_ICON + 3), -line * (CP.SPELL_ICON + 3), CP.SPELL_ICON, r.icon or 134400, r.kind == "skip")
              t.panoplySkip = r.kind == "skip" or nil
              icons[#icons + 1] = t
              n = n + 1
            end
          end
          local lines = max(1, ceil(n / perRow))
          local rh = max(lh + 4, lines * (CP.SPELL_ICON + 3))
          rowB:SetSize(w, rh)
          local names = {}
          for _, r in ipairs(vis.rows) do names[#names + 1] = rowName(r) .. (r.kind == "skip" and " (skipped)" or "") end
          Skin.Tooltip(rowB, ("Level %d"):format(vis.level), table.concat(names, "\n") .. "\n\nClick to " .. (open and "close" or "show names and costs") .. ".")
          rowB:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
          rowB:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
          rowB:SetScript("OnClick", function() Kit.SetOpen("class", id, not open) Menu:RefreshCurrent() end)
          p.laterRows[#p.laterRows + 1] = { visit = vis, button = rowB, icons = icons, open = open }
          y = y - rh - SP.xs
          if open then
            for _, r in ipairs(vis.rows) do
              if matches(r) then y = y - spellRow(holder, 22, y, w - 22, r, list) end
            end
            y = y - SP.s
          end
        end
      end
    end
    holder.panoplyH = -y + SP.s
    return holder.panoplyH
  end,
}

-------------------------------------------------------------------------------
-- Gear
-------------------------------------------------------------------------------
CP.GEAR_ROWS = 12           -- the ranked list's rows across every slot (a selected slot lists all of its own)
CP.gearSlot = nil

-- the grid of the Gear tab: the gear engine's best per slot for this character, up to five levels ahead (At Your Level's model, the
-- Class page's slice: Panoply.ClassGear:Filter)
function CP:GearGrid()
  local AL = Panoply.AtLevel
  if not (AL and AL.Grid and Panoply.Gear) then return nil end
  local ctx = Panoply.Gear:GetContext()
  local CG = Panoply.ClassGear
  local filter = CG and CG.Filter and CG:Filter(ctx) or { maxLevel = (ctx and ctx.level or 1) + 5, includeLocked = true }
  return AL:Grid(nil, nil, { filter = filter })
end

-- the ranked next upgrades: every slot's candidates that beat what is worn, best first (one slot when key is given)
function CP:GearList(g, key)
  local out = {}
  for _, c in ipairs(g and g.cells or {}) do
    if not key or c.key == key then
      for _, cand in ipairs(c.list) do out[#out + 1] = { cell = c, cand = cand } end
    end
  end
  table.sort(out, function(a, b)
    if (a.cand.locked and true or false) ~= (b.cand.locked and true or false) then return not a.cand.locked end
    if (a.cand.delta or 0) ~= (b.cand.delta or 0) then return (a.cand.delta or 0) > (b.cand.delta or 0) end
    return (a.cand.name or "") < (b.cand.name or "")
  end)
  if not key then while #out > CP.GEAR_ROWS do table.remove(out) end end
  return out
end

function CP:SelectGearSlot(key)
  if CP.gearSlot == key then CP.gearSlot = nil else CP.gearSlot = key end
  if Panoply.History then Panoply.History:Note("slot") end
  Menu:RefreshCurrent()
end
Kit.OnReset("class", function() CP.gearSlot = nil end)

CP.GEAR_HELP = "What you wear, scored with your plan's stat weights, and the best upgrade for each slot from quests, dungeons, vendors, the auction house and crafting, up to five levels ahead. The same gear engine ranks At your level, Muster and the auction house. Scores are a guide: items with an effect are scored on their plain stats."

CP.TABS.gear = {
  Sig = function(v, w)
    local g = CP:GearGrid()
    v.grid = g
    if not g then return "none" end
    local t = { tostring(CP.gearSlot), tostring(g.weighedFor), tostring(g.noWeights), tostring(g.working), v.band }
    for _, c in ipairs(g.cells) do
      local up = c.now or c.soon
      t[#t + 1] = table.concat({ c.key, tostring(c.state), tostring(c.worn and (c.worn.link or c.worn.id)), up and tostring(up.itemID) or "", up and tostring(up.delta) or "", #c.list }, ":")
    end
    return table.concat(t, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if holder.drawn then return holder.panoplyH end
    holder.drawn = true
    local g = v.grid
    local y = 0
    local hdr = Kit.SectionHeader(holder, { title = "Gear", help = CP.GEAR_HELP })
    y = y - hdr:Layout(0, y, w) - SP.s
    if not g then
      local h = U.Text(holder, 0, y, w, 12, "text.muted", "The gear engine is not in this build.", true)
      holder.panoplyH = -y + h + SP.s
      return holder.panoplyH
    end
    -- "Weighed for Beast Mastery leveling": the plan's name opens Talents
    if g.weighedFor then
      local link = U.Link(holder, 0, y, g.weighedFor, w, function() CP:GoTab("talents") end, g.weighedFor, "Opens the Talents tab: the plan these weights come from.")
      p.weighedLink = link
      y = y - (link:GetHeight() or 14) - SP.s
    end
    -- 0.9.9.4: the build the weights come from, on the shared build card (its tooltip has the web address)
    p.gearBuildCard = nil
    local build = stOn() and ST():FollowedBuild() or nil
    if build and build.source == "public" then
      local card = ST():BuildCard(holder, { mode = "line", actions = { "change" } })
      card:Set(ST():BuildFacts(build))
      local ch = card:Fit(min(w, 640))
      card:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
      p.gearBuildCard = card
      y = y - ch - SP.m
    end
    if g.noWeights or not g.best then
      local h = U.Text(holder, 0, y, w, 12, "text.muted", "There are no stat weights for this class and plan yet, so nothing is ranked.", true)
      holder.panoplyH = -y + h + SP.s
      return holder.panoplyH
    end
    local wide = v.band == "wide"
    local gap = SP.l + SP.s
    local gw = wide and floor((w - gap) * 0.45) or w
    local lx = wide and (gw + gap) or 0
    local lw = wide and (w - gap - gw) or w
    -- the grid
    local cells = {}
    for _, c in ipairs(g.cells) do cells[#cells + 1] = Panoply.AtLevel.CellView(c, g.mine) end
    local grid = Kit.SlotGrid(holder, { onSelect = function(key) CP:SelectGearSlot(key) end, accent = Kit.ClassColor(v.class) })
    grid:Set(cells)
    grid:Select(CP.gearSlot)
    local cols = v.band == "narrow" and 2 or (wide and Kit.SlotGridColumns(gw, 3) or Kit.SlotGridColumns(gw, 4))
    local gh = grid:Layout(0, y, gw, cols)
    p.gearGrid, p.gearCells = grid, cells
    local ly = wide and y or (y - gh - SP.l)
    -- the ranked list
    local key = CP.gearSlot
    local rows = CP:GearList(g, key)
    local title = key and ("%s: %d %s"):format(((g.best and g.best[key] and g.best[key].label) or key), #rows, plural(#rows, "upgrade")) or "Next upgrades"
    local th = U.Text(holder, lx, ly, lw - (key and 26 or 0), 13, "gold.title", title, false, true)
    if key then
      local close = Skin.IconButton(holder, "Close", 18, function() CP:SelectGearSlot(key) end, "Every slot", "Lists the upgrades for every slot again.")
      close:SetPoint("TOPLEFT", holder, "TOPLEFT", lx + lw - 18, ly)
      p.gearClose = close
    end
    ly = ly - th - SP.s
    p.gearRows = {}
    if #rows == 0 then
      ly = ly - U.Text(holder, lx, ly, lw, 12, "text.muted", key and "Nothing up to five levels ahead beats what you wear here." or "Nothing up to five levels ahead beats what you wear.", true) - SP.s
    end
    for _, it in ipairs(rows) do
      local c = it.cand
      local ic = U.ItemIcon(holder, lx, ly, 20, c.link or c.itemID, c.locked)
      local chip = Kit.StatusChip(holder, c.locked and "soon" or "now", c.locked and (c.lockReason or "Later") or Panoply.Gear.DeltaText(c.delta))
      local nx = lx + 20 + SP.s
      local room = max(40, lx + lw - nx - chip:GetWidth() - SP.s)
      local nw, nh, nfs = U.Word(holder, nx, ly - 2, 12, "text.primary", Panoply.AtLevel.ItemName(c), room, true)
      chip:SetPoint("TOPLEFT", holder, "TOPLEFT", nx + nw + SP.s, ly - 2)
      local line = ("%s \194\183 %s \194\183 Level %d"):format(it.cell.label or it.cell.key, Panoply.Gear.SourceText(c.source), c.requiredLevel or 0)
      local sh = U.Text(holder, nx, ly - max(20, nh + 4), max(40, lx + lw - nx), 11, "text.muted", line, true)
      p.gearRows[#p.gearRows + 1] = { cand = c, cell = it.cell, icon = ic, name = nfs, chip = chip }
      ly = ly - max(20, nh + 4) - sh - SP.s
    end
    local bottom = min(y - gh, ly)
    holder.panoplyH = -bottom + SP.s
    return holder.panoplyH
  end,
}

-- the gear engine finished a long list, or the game named items: the Gear tab (and the Overview's gear row) follow it
Panoply:Listen("GEAR_CHANGED", function(ctxKey, what)
  if (what == "done" or (what == "changed" and (ctxKey == nil or ctxKey == "player"))) and Menu.current == "class" and Menu.frame and Menu.frame:IsShown()
    and (CP.topic == "gear" or CP.topic == "overview") and not C.InCombat() then
    Menu:RefreshCurrent()
  end
end)
