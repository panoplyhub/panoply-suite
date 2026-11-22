-- Panoply Suite: the Legacy page (WoW Forever only). 0.8.4; rebuilt in 0.9.5 phase 4C (docs/specs/page-redesigns-v1.md section 3)
-- with the shared visual system (UI/KitParts.lua): surfaces with no borders, gold only on titles, explanations in ? tooltips,
-- icon cells, pips, a progress bar with the reward marks, talent nodes, underlined text tabs.
--
--   The top strip (pinned)   the account's points on a bar to 65 with the four rewards at their marks (owned = full colour with a
--                            check; the next one has a ring), and this character: "X of 16 spent", "N unspent", and Legacy (N),
--                            which opens the game's own Legacy window
--   Next points (default)    the nearest points this character can earn, nearest first, each with a link; locked ones last
--   Challenges               all 65 in six groups: Classes (9 x 3 class crests), Tradeskills (6 x 3, with this character's skill),
--                            PvP (rank pips, exalted, Field of Honor weeks), Dungeons (Spelunker bands that open to their dungeons),
--                            Raids (locked until their date), Adventure (exploration %, the questline's step)
--   Perk plan                the three trees as talent nodes with tier rows at 0 / 5 / 10 and prerequisite arrows. A click adds a
--                            planned rank, a right-click takes one away; the planner never lets an invalid build be made.
--   Bands                    Wide: trees side by side, Challenges in two columns. Medium: one tree at a time (a three-way switch),
--                            Challenges in one column. Narrow: the strip in two lines, the tabs as a dropdown, the class grid icons only.
-- Only the tab content scrolls. Nothing on this page spends a point or buys anything; one button opens the game's own window.
local ADDON, Panoply = ...
local L = Panoply.Legacy
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local plural = L.plural

local Page = {}
L.PageFrame = Page
Page.GRIP = 22           -- room left under the scrolling part for the window's resize grip and corner
Page.RIGHT_W = 236       -- the "This character" part of the strip (Wide and Medium)
Page.NODE, Page.NODE_GAP, Page.TIER_GAP = 36, 14, 22
Page.CELL = 28           -- a class or tradeskill cell
Page.ROW_CELL = 20       -- the state mark at the start of a row

-------------------------------------------------------------------------------
-- The words (also read by the tests)
-------------------------------------------------------------------------------
L.GAME_WINDOW_TIP = "Shows the game's own Legacy window. Panoply never spends a point: you do that there."
L.NEVER_SPENDS = "Panoply never spends a point."
L.HELP = {
  strip = "Every challenge done is one Legacy point for the whole account (Hardcore characters count apart). The rewards unlock at their marks on the bar. Each character spends its own points, up to 16.",
  next = "The points this character is closest to, nearest first, measured by the share still to go. Locked ones are at the bottom with the date they open.",
  classes = "One point for each class at level 25, 45 and 60, on any character of this account. Panoply reads each character's level when you play it.",
  tradeskills = "One point for each crafting tradeskill at 150, 225 and 300, on any character. The number beside a tradeskill is this character's own skill.",
  pvp = "Ranks reached, exalted with each battleground's faction, and weeks of Field of Honor. A week can first be earned from the date shown.",
  dungeons = "Spelunker: the final boss of every dungeon of a level band. Click a band to see its dungeons and which bosses are done.",
  raids = "Every boss of a raid. Raids open on their date.",
  adventure = "Explore the whole world map on one character, and finish the Lord Valthalak questline.",
  plan = "Plan this character's 16 points. Click a perk to add a rank, right-click to take one away. A tier opens with 5 and 10 points in the tiers of that tree above it, and an arrow means the perk above must be at full rank first.",
}
-- the words a row shows at its right
function L:StateText(st)
  if st.manual then return st.checked and "Done (ticked)" or "Tick when done" end
  if st.state == "locked" then return "Locked until " .. L.DateText(st["until"]) end
  if st.state == "done" then return st.by and ("Done · " .. st.by) or "Done" end
  if st.state == "progress" then
    if st.have and st.need then return ("%s of %s"):format(tostring(st.have), tostring(st.need)) end
    return "In progress"
  end
  return "Not yet"
end

-------------------------------------------------------------------------------
-- Icon slots (spec section 9): what each resolves to is in Kit.IconReport
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
-- No shield drawing is in the theme yet: the page's own menu icon (the hourglass of the left list) stands for it, so the header no
-- longer shares a picture with another page.
Kit.RegisterIcon("icon.legacy.shield", { icon = "MenuLegacy", own = true })
Kit.RegisterIcon("icon.instance.dungeon", { game = { I .. "INV_Misc_Key_14", I .. "INV_Misc_Key_03" } })
Kit.RegisterIcon("icon.instance.raid", { game = { I .. "INV_Misc_Head_Dragon_01", I .. "INV_Misc_Key_14" } })
for _, rw in ipairs(L.COSMETICS) do Kit.RegisterIcon("icon.reward." .. rw.key, { game = { I .. rw.fallback, I .. "INV_Misc_QuestionMark" } }) end
Kit.RegisterIcon("icon.pvp.rank", { game = { I .. "INV_BannerPVP_02", I .. "INV_Misc_QuestionMark" } })
Kit.RegisterIcon("icon.adventure.explore", { game = { I .. "INV_Misc_Map_01" } })
Kit.RegisterIcon("icon.adventure.quest", { game = { I .. "INV_Misc_Book_09", I .. "INV_Misc_Note_01" } })
-- the class crests: the game's class circle texture, cut to each class (the standard cut when the game does not give its own table)
local CREST = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CREST_CUT = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
for _, cls in ipairs(L.CLASS_ORDER) do Kit.RegisterIcon("icon.class." .. cls:lower(), { game = { CREST }, raw = true }) end
local function crest(cell, cls)
  cell:SetTexture(CREST)
  local t = type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[cls] or CREST_CUT[cls]
  if t and cell.icon.SetTexCoord then cell.icon:SetTexCoord(t[1], t[2], t[3], t[4]) end
  cell.panoplySlot = "icon.class." .. cls:lower()
end

-------------------------------------------------------------------------------
-- Small parts
-------------------------------------------------------------------------------
local function tint(fs, token) local c = Kit.Color(token) fs:SetTextColor(c[1], c[2], c[3], 1) end
-- one line (or a wrapped block) of text at (x, y) of parent, w wide: returns its height
local function text(parent, x, y, w, size, token, words, wrap)
  local fs = Skin.Ink(parent, size or 12, Kit.Color(token or "text.muted"))
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
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
local function rightText(parent, xRight, y, size, token, words, maxW)
  local fs = Skin.Ink(parent, size or 11, Kit.Color(token or "text.muted"))
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetJustifyH then fs:SetJustifyH("RIGHT") end
  fs:SetText(words or "")
  local w = min(maxW or 999, ceil(TW(fs)) + 2)
  fs:SetWidth(w)
  if maxW and TW(fs) > maxW then Skin.Ellipsize(fs, words or "", maxW) end
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xRight - w, y)
  return w, h, fs
end
local function cellState(st) return (st.manual and (st.checked and "done" or "todo")) or st.state end
local function rowTip(r, st)
  local lines = {}
  if st.manual then lines[#lines + 1] = "The game does not tell Panoply about this one. Tick it when you have done it."
  elseif st.state == "done" then lines[#lines + 1] = st.by and ("Done by " .. st.by .. (st.have and r.cat == "classes" and (", level " .. st.have) or "") .. ".") or "Done."
  elseif st.state == "progress" then lines[#lines + 1] = ("%s of %s%s."):format(tostring(st.have), tostring(st.need), st.by and (", " .. st.by) or "")
  elseif st.state == "locked" then lines[#lines + 1] = "Opens " .. L.DateText(st["until"]) .. "."
  else lines[#lines + 1] = "Not done on any character yet." end
  return table.concat(lines, " ")
end

-- a row: a state mark (or a box to tick), the name, and the state at the right. opts: x, y, w, label, st, slot | texture, accent,
-- onClick (the name links somewhere), linkTip, right (words instead of the state's). Returns the height.
local function stateRow(p, holder, o)
  local st, r = o.st, o.st.row
  local x, y, w = o.x, o.y, o.w
  local h = 20
  local rw, rh = rightText(holder, x + w, y + 1, 11, st.state == "done" and "text.primary" or "text.muted", o.right or L:StateText(st), floor(w * 0.45))
  local nameX = x + Page.ROW_CELL + SP.s
  local nameW = max(40, w - (nameX - x) - rw - SP.s)
  if st.manual and r then
    -- the box ticks this row (or one dungeon of a band) by hand
    local id = o.tickId or r.id
    local chk = Skin.Check(holder, o.label, { get = function() return o.st.checked == true end, set = function(v) L:SetTicked(id, v) end }, nil, rowTip(r, st), true)
    chk:SetPoint("TOPLEFT", holder, "TOPLEFT", x + 1, y)
    local _, lh = chk:FitLabel(nameW + Page.ROW_CELL - 18)
    chk.panoplyRow = id
    p.ticks[#p.ticks + 1] = chk
    h = max(h, lh)
  else
    local cell = Kit.IconCell(holder, { size = Page.ROW_CELL, accent = o.accent })
    if o.slot then cell:SetSlot(o.slot) elseif o.texture then cell:SetTexture(o.texture) end
    cell:SetState(st.state, { progress = (st.have and st.need and st.need > 0) and (st.have / st.need) or 0, tip = o.label, tipBody = rowTip(r or {}, st) })
    cell:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
    cell.panoplyRow = r and r.id
    if r and L:TakeFresh(r.id) then cell:Shine() end
    p.cells[#p.cells + 1] = cell
    local lh, fs = text(holder, nameX, y + 2, nameW, 12, o.onClick and "text.primary" or "text.primary", o.label)
    if o.onClick then
      local b = CreateFrame("Button", nil, holder)
      b:SetAllPoints(fs)
      b.panoplyLayoutSkip = true
      Skin.Tooltip(b, o.label, o.linkTip)
      b:SetScript("OnEnter", function(s) if s.panoplyShowTip then s.panoplyShowTip() end end)
      b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      b:SetScript("OnClick", o.onClick)
      fs.panoplyLink = true
    end
    h = max(h, lh + 2)
  end
  return max(h, rh) + SP.xs
end

-- a map button (a dungeon on Panoply's dungeon map; else the world map)
local function mapButton(parent, inst)
  local b = Skin.IconButton(parent, "", 20, function() L:ShowDungeon(inst) end, "Show on the map", "Opens this dungeon on the map.")
  b:SetIcon("Map", 14)
  b.panoplyKitIcon = "icon.ui.map"
  b.panoplyInstance = inst and inst.id
  return b
end
function L:ShowDungeon(inst)
  local M = Panoply.Map
  if inst and M and M.Instances and M.Instances.Open and Panoply.Modules and Panoply.Modules:IsOn("map") then M.Instances:Open(inst.id) return true end
  if Panoply.Menu then Panoply.Menu:Open("map") end
  return false
end
function L:OpenProfession(name)
  local PUI = Panoply.ProfUI
  if PUI and PUI.Show then PUI:Show(name) return true end
  Panoply.Menu:Open("professions")
  return false
end

-- a section: its header (gold title, rule, ?) with the count at the right. Returns the y under the header.
local function header(p, holder, x, y, w, title, help, count)
  local h = Kit.SectionHeader(holder, { title = title, help = help })
  local hh = h:Layout(x, y, w)
  if count then
    local cw = rightText(holder, x + w - (help and (16 + SP.s) or 0), y + 1, 12, "text.primary", count)
    h.title:SetWidth(min(ceil(TW(h.title)) + 2, w - cw - 40))
  end
  p.headers[#p.headers + 1] = h
  return y - hh - SP.s
end

-------------------------------------------------------------------------------
-- The page's state (history) and its tabs
-------------------------------------------------------------------------------
L.tree = L.tree or "professions"     -- the tree shown in Medium and Narrow
L.open = L.open or {}                 -- the Spelunker bands opened to their dungeons
if Panoply.History then Panoply.History:State("legacy", {
  get = function() return { tree = L.tree, scroll = Page.area and Page.area:GetVerticalScroll() or 0 } end,
  set = function(s) if type(s) == "table" then L.tree = s.tree or L.tree Page.pendingScroll = s.scroll or 0 end end,
  key = function(s) return type(s) == "table" and tostring(s.tree) or tostring(s) end,
}) end

local TAB_TIP = {
  next = "The nearest points this character can earn.",
  challenges = "All 65 challenges, and who has done them.",
  plan = "Plan this character's 16 perk points.",
}
Panoply.Kit.TabVar("legacy", { get = function() return L.tab end, set = function(k) L.tab = L.OLD_TABS[k] or k end, default = "next", valid = L.ValidTab })

Menu:RegisterTab("Legacy", function(p)
  local items = {}
  for _, t in ipairs(L.TABS) do items[#items + 1] = { key = t[1], label = t[2], tip = t[2], tipBody = TAB_TIP[t[1]] } end
  p.kitTabs = Kit.Tabs(p, { page = "legacy", items = items, default = "next", style = "underline",
    get = function() return L.OLD_TABS[L.tab] or L.tab end, onSelect = function(k) L.tab = k Page.pendingTop = true end })
  p.tabs = p.kitTabs.buttons
  p.area = Skin.ScrollArea(p)
  Page.area = p.area
  p.panoplyArea = nil
end, function(p) Page:Render(p) end)

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
-- what is drawn: when it is the same as last time, nothing is drawn again
local function signature(W, H, band, tab, states, meter, rewards)
  local t = { W, H, band, tab, L.tree, tostring(L.focus and L.focus.profession), tostring(L.focus and L.focus.tier) }
  for k, v in pairs(L.open) do if v then t[#t + 1] = "o" .. k end end
  for _, r in ipairs(L:BuildRows()) do
    local st = states[r.id]
    t[#t + 1] = table.concat({ st.state, tostring(st.by), tostring(st.have), tostring(st.checked), tostring(st.mine) }, ":")
    for _, d in ipairs(st.parts or {}) do
      t[#t + 1] = tostring(d.done) .. tostring(d.checked)
      for _, b in ipairs(d.bosses) do t[#t + 1] = tostring(b.by) end
    end
  end
  t[#t + 1] = table.concat({ meter.spent, meter.points, meter.unspent, tostring(L:PlanSpent()), tostring(L:CanOpenGame()) }, ":")
  for _, rw in ipairs(rewards) do t[#t + 1] = tostring(rw.owned) .. tostring(rw.icon) end
  local plan = L:Plan()
  for _, pk in ipairs(L:Perks()) do t[#t + 1] = tostring(plan[pk.id] or 0) end
  local a = L:Actual()
  if a then for id, r in pairs(a) do t[#t + 1] = tostring(id) .. "=" .. tostring(r) end end
  return table.concat(t, "|")
end

function Page:Render(p)
  local W, H = p.width or 600, p.height or 400
  local band = Kit.Band(W)
  local states = L:States()
  local meter = L:Meter(states)
  local rewards = L:Rewards(meter.points)
  local tab = p.kitTabs:Current()
  tab = L.OLD_TABS[tab] or tab
  L.tab = tab
  local sig = signature(W, H, band, tab, states, meter, rewards)
  if p.sig == sig then return end
  p.sig = sig
  self:Draw(p, W, H, band, tab, states, meter, rewards)
end

function Page:Draw(p, W, H, band, tab, states, meter, rewards)
  p.band = band
  if p.fixed then p.fixed:Hide() end
  if p.content then p.content:Hide() end
  p.cells, p.ticks, p.headers, p.nodes, p.arrows, p.links = {}, {}, {}, {}, {}, {}
  local fixed = CreateFrame("Frame", nil, p)
  fixed:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); fixed:SetSize(W, H)
  fixed.panoplyGapOK = true
  p.fixed = fixed
  -- 1. the top strip
  local y = -self:DrawStrip(p, fixed, W, band, meter, rewards) - SP.m
  -- 2. the tabs (Narrow: a dropdown)
  local th = p.kitTabs:Layout(0, y, W, band == "narrow" and "dropdown" or nil)
  y = y - th - SP.s
  -- 3. Medium and Narrow, Perk plan: the three-way tree switch (pinned)
  if tab == "plan" and band ~= "wide" then
    y = y - self:DrawTreeSwitch(p, fixed, 0, y, W) - SP.s
  end
  -- 4. the tab content: the only part that scrolls
  local area = p.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
  area:SetSize(W, max(1, H + y - Page.GRIP))
  area:Show()
  local content = CreateFrame("Frame", nil, area.content)
  content:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
  content.panoplyGapOK = true
  p.content = content
  local cw = W - 14
  local ch
  if tab == "challenges" then ch = self:DrawChallenges(p, content, cw, band, states)
  elseif tab == "plan" then ch = self:DrawPlan(p, content, cw, band, meter)
  else ch = self:DrawNext(p, content, cw, band, states) end
  content:SetSize(cw, max(1, ch))
  area:SetContentHeight(ch + SP.s)
  local s
  if Page.focusY then s, Page.focusY = Page.focusY, nil
  elseif Page.pendingTop then s = 0
  elseif Page.pendingScroll then s = Page.pendingScroll end
  Page.pendingTop, Page.pendingScroll = nil, nil
  if s and area.SetVerticalScroll then area:SetVerticalScroll(max(0, min(area:MaxScroll(), s))) end
  if area.UpdateBar then area:UpdateBar() end
end

-- The strip: the reward track and this character. Returns its height.
function Page:DrawStrip(p, fixed, W, band, meter, rewards)
  local card = Kit.Surface(fixed, 1)
  card:SetPoint("TOPLEFT", fixed, "TOPLEFT", 0, 0)
  p.strip = card
  local pad = SP.m
  local narrow = band == "narrow"
  local RW = narrow and 0 or Page.RIGHT_W
  local LW = W - 2 * pad - (narrow and 0 or (RW + SP.l))
  -- the account: points and the bar to 65 with the reward marks (the page's own icon, icon.legacy.shield, is in the window's header)
  local help = Kit.HelpIcon(card, "Legacy", L.HELP.strip)
  local total = L:Total()
  local lh, lfs = text(card, pad, -pad - 1, LW - 16 - SP.s, 13, "text.primary",
    ("Account: %d of %d points"):format(meter.points, total))
  card.pointsText = lfs
  help:SetPoint("TOPLEFT", card, "TOPLEFT", pad + LW - 16, -pad)
  local y = -pad - max(16, lh) - SP.s
  local bar = Kit.ProgressBar(card, { h = 8, accent = "legacy.professions" })
  bar:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y - 2)
  bar:SetBarWidth(LW)
  bar:SetValue(meter.points, total)
  local ticks = {}
  for _, rw in ipairs(rewards) do
    ticks[#ticks + 1] = { value = rw.points, reached = rw.reached, key = rw.key, tip = ("%s at %d points"):format(rw.name, rw.points),
      tipBody = ("%s. %s"):format(rw.kind, rw.owned and "Collected." or (rw.reached and "Unlocked." or ("%d more points."):format(rw.points - meter.points))) }
  end
  bar:SetTicks(ticks)
  card.bar = bar
  y = y - 8 - 6
  card.rewardCells = {}
  if not narrow then
    -- the rewards under their marks
    local s = 26
    for _, rw in ipairs(rewards) do
      local cell = Kit.IconCell(card, { size = s, accent = "legacy.professions" })
      if rw.icon then cell:SetTexture(rw.icon) else cell:SetSlot("icon.reward." .. rw.key) end
      local state = rw.owned and "done" or (rw.reached and "done" or (rw.next and "progress" or "todo"))
      if rw.reached and rw.owned == false then state = "progress" end
      cell:SetState(state, { progress = rw.next and 1 or (state == "progress" and 1 or 0), tip = rw.name,
        tipBody = ("%s · %d points. %s%s"):format(rw.kind, rw.points,
          rw.owned and "Collected." or (rw.reached and "Unlocked: collect it in the game." or ("%d more points."):format(max(0, rw.points - meter.points))),
          rw.unverified and " (Community data, not yet confirmed in the game.)" or "") })
      local cx = floor(LW * rw.points / total) - floor(s / 2)
      cx = max(0, min(LW - s, cx))
      cell:SetPoint("TOPLEFT", card, "TOPLEFT", pad + cx, y)
      cell.panoplyReward = rw.key
      if L:TakeFresh("reward." .. rw.key) then Kit.Pulse(cell) end
      card.rewardCells[#card.rewardCells + 1] = cell
    end
    y = y - s - 2
  end
  local leftH = -y
  -- this character
  local spentLine = ("%d of %d spent"):format(meter.spent, meter.cap)
  local btnLabel = meter.unspent > 0 and ("Legacy (%d)"):format(meter.unspent) or "Legacy"
  local btn = Skin.Button(card, btnLabel, 100, 24, function() L:OpenGame() end, "Open the game's Legacy window", L.GAME_WINDOW_TIP)
  Skin.FitButton(btn, 80, 140)
  btn:SetEnabledLook(L:CanOpenGame())
  card.gameBtn = btn
  local chip
  if meter.unspent > 0 then
    chip = Kit.StatusChip(card, "state.warn", ("%d unspent"):format(meter.unspent))
    card.unspentChip = chip
  end
  local rightH
  if narrow then
    -- line 2: spent, the unspent chip, the button at the right
    local bw = btn:GetWidth()
    btn:SetPoint("TOPLEFT", card, "TOPLEFT", W - pad - bw, y)
    local cwid = chip and chip:GetWidth() or 0
    local room = max(60, W - 2 * pad - bw - cwid - 2 * SP.s)
    local sh, sfs = text(card, pad, y - 4, room, 12, "text.primary", "This character: " .. spentLine)
    local sw = min(ceil(TW(sfs)) + 2, room)
    sfs:SetWidth(sw)
    card.spentText = sfs
    if chip then chip:SetPoint("TOPLEFT", card, "TOPLEFT", pad + sw + SP.s, y - 3) end
    leftH = -y + max(24, sh + 4)
    rightH = 0
  else
    local x0 = W - pad - RW
    local h1 = text(card, x0, -pad, RW, 11, "text.muted", "THIS CHARACTER")
    local h2, sfs = text(card, x0, -pad - h1 - 2, RW, 13, "text.primary", spentLine)
    card.spentText = sfs
    local yy = -pad - h1 - 2 - h2 - SP.s
    btn:SetPoint("TOPLEFT", card, "TOPLEFT", x0, yy)
    if chip then chip:SetPoint("TOPLEFT", card, "TOPLEFT", x0 + btn:GetWidth() + SP.s, yy - 3) end
    rightH = -yy + 24
  end
  local h = max(leftH, rightH) + pad
  card:SetSize(W, h)
  return h
end

-------------------------------------------------------------------------------
-- Next points
-------------------------------------------------------------------------------
function Page:DrawNext(p, content, W, band, states)
  local y = header(p, content, 0, 0, W, "Nearest first", L.HELP.next)
  local list = L:NextPoints(states)
  if #list == 0 or L:MeEntry().hc then
    local words = L:MeEntry().hc and "Hardcore characters earn Legacy apart from the account, so nothing here counts for this character."
      or "Nothing left that this character can earn now."
    local h = text(content, 4, y, W - 8, 12, "text.muted", words, true)
    return -y + h + SP.m
  end
  local catAccent = { classes = "legacy.adventure", tradeskills = "legacy.professions", dungeons = "legacy.resourcefulness", adventure = "legacy.adventure", raids = "legacy.resourcefulness", pvp = "legacy.resourcefulness" }
  for _, e in ipairs(list) do
    local r = L:Row(e.id)
    local st = states[e.id]
    local slot, texture
    if e.cat == "classes" and r then texture = nil
    elseif e.cat == "tradeskills" and r then texture = Panoply.ProfUI and Panoply.ProfUI.IconFor(r.prof)
    elseif e.cat == "dungeons" then slot = "icon.instance.dungeon"
    elseif e.cat == "raids" then slot = "icon.instance.raid"
    elseif e.id == "adv.explore" then slot = "icon.adventure.explore"
    elseif e.id == "adv.valthalak" then slot = "icon.adventure.quest"
    else slot = "icon.pvp.rank" end
    local onClick, linkTip
    if e.link and e.link.kind == "professions" then
      onClick = function() L:OpenProfession(e.link.prof) end
      linkTip = "Opens the Professions page on " .. e.link.prof .. "."
    elseif e.link and e.link.kind == "guide" then
      onClick = function() Panoply.Menu:Open("guide") end
      linkTip = "Opens the Guide."
    end
    local rowSt = st or { state = "locked", ["until"] = e["until"] }
    local x = 4
    local rowY = y
    local h = stateRow(p, content, { x = x, y = y, w = W - 8, label = e.label, st = rowSt, texture = texture, slot = slot, accent = catAccent[e.cat],
      right = e.dist, onClick = onClick, linkTip = linkTip })
    if e.cat == "classes" and r then
      local cell = p.cells[#p.cells]
      if cell then crest(cell, r.class) end
    end
    if e.locked then
      -- locked: muted
      local cell = p.cells[#p.cells]
      if cell then cell:SetAlpha(0.6) end
    end
    if onClick then p.links[#p.links + 1] = { id = e.id, fn = onClick, y = rowY } end
    y = y - h
    -- a Spelunker band: the dungeons left, each with its map button
    for _, d in ipairs(e.parts or {}) do
      local bx = x + Page.ROW_CELL + SP.s
      local mb = mapButton(content, d.inst)
      mb:SetPoint("TOPLEFT", content, "TOPLEFT", W - 4 - 20, y)
      if not d.inst then mb:Hide() mb.panoplyFlowSkip = true end
      p.links[#p.links + 1] = { id = e.id .. ":" .. d.name, map = mb }
      local missing = {}
      for _, b in ipairs(d.bosses) do if not b.by then missing[#missing + 1] = b.boss end end
      local words = d.name .. (#missing > 0 and (": " .. table.concat(missing, ", ")) or "")
      local dh = text(content, bx, y - 2, W - 8 - (bx - x) - 20 - SP.s, 11, "text.muted", words)
      y = y - max(20, dh + 2) - SP.xs
    end
  end
  return -y + SP.m
end

-------------------------------------------------------------------------------
-- Challenges
-------------------------------------------------------------------------------
-- a grid section: rows of cells (Classes: 9 x 3; Tradeskills: 6 x 3). Returns the height.
local function gridSection(p, holder, W, band, key, rows, labels, states, opts)
  local y = header(p, holder, 0, 0, W, opts.title, L.HELP[key], opts.count)
  local s = Page.CELL
  local iconsOnly = band == "narrow" and key == "classes"
  local labelW = iconsOnly and 0 or min(floor(W * 0.5), max(90, W - 3 * (s + SP.m) - 8))
  -- the column heads (25 / 45 / 60)
  local x0 = 4 + labelW + (iconsOnly and 0 or SP.s)
  local headH = 0
  for i, lv in ipairs(opts.levels) do
    local fs = Skin.Ink(holder, 10, Kit.Color("text.muted"))
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetText(tostring(lv)); fs:SetWidth(s + 8)
    local fh = ceil(TH(fs, s + 8))
    fs:SetHeight(fh)
    headH = max(headH, fh)
    fs:SetPoint("TOPLEFT", holder, "TOPLEFT", x0 + (i - 1) * (s + SP.m) - 4, y)
  end
  y = y - headH - SP.xs
  for gi, group in ipairs(rows) do
    local rowY = y
    if not iconsOnly then
      local lab = labels[gi]
      local _, fs = text(holder, 4, y - floor((s - 14) / 2), labelW, 12, lab.token or "text.primary", lab.text)
      if lab.color then fs:SetTextColor(lab.color[1], lab.color[2], lab.color[3], 1) end
      if lab.onClick then
        local b = CreateFrame("Button", nil, holder)
        b:SetAllPoints(fs)
        b.panoplyLayoutSkip = true
        Skin.Tooltip(b, lab.text, lab.linkTip)
        b:SetScript("OnEnter", function(sf) if sf.panoplyShowTip then sf.panoplyShowTip() end end)
        b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("OnClick", lab.onClick)
        p.links[#p.links + 1] = { id = lab.id, fn = lab.onClick }
      end
    end
    for i, r in ipairs(group) do
      local st = states[r.id]
      local cell = Kit.IconCell(holder, { size = s, accent = opts.accent and opts.accent(r) or "legacy.professions",
        onClick = st.manual and function() L:SetTicked(r.id, not st.checked) end or nil })
      opts.icon(cell, r)
      local body = rowTip(r, st)
      if st.mine then body = body .. (" This character: %d."):format(st.mine) end
      cell:SetState(cellState(st), { progress = (st.have and st.need and st.need > 0) and (st.have / st.need) or 0, tip = r.label, tipBody = body })
      cell:SetPoint("TOPLEFT", holder, "TOPLEFT", x0 + (i - 1) * (s + SP.m), y)
      cell.panoplyRow = r.id
      if L:TakeFresh(r.id) then cell:Shine() end
      if L.focus and L.focus.section == key and L.focus.profession == r.prof and L.focus.skill == r.skill then
        cell:Shine()
        Page.focusRow = { id = r.id, y = rowY }
      end
      p.cells[#p.cells + 1] = cell
    end
    y = y - s - SP.s
  end
  return -y
end

local function classSection(p, holder, W, band, states, info)
  local rows, labels = {}, {}
  for _, cls in ipairs(L.CLASS_ORDER) do
    local g = {}
    for _, lv in ipairs(L.CLASS_LEVELS) do g[#g + 1] = L:Row(("class.%s.%d"):format(cls, lv)) end
    rows[#rows + 1] = g
    labels[#labels + 1] = { text = L.CLASS_NAMES[cls], color = Kit.ClassColor(cls) }
  end
  return gridSection(p, holder, W, band, "classes", rows, labels, states, { title = "Classes", count = ("%d of %d"):format(info.done, info.total),
    levels = L.CLASS_LEVELS, icon = function(cell, r) crest(cell, r.class) end, accent = function(r) return "class." .. r.class end })
end

local function tradeSection(p, holder, W, band, states, info)
  local rows, labels = {}, {}
  local me = L:MeEntry()
  for _, prof in ipairs(L.TRADESKILLS) do
    local g = {}
    for _, at in ipairs(L.TRADESKILL_LEVELS) do g[#g + 1] = L:Row(("trade.%s.%d"):format(prof, at)) end
    rows[#rows + 1] = g
    local mine = me.profs and me.profs[prof]
    labels[#labels + 1] = { id = "trade." .. prof, text = mine and ("%s · %d"):format(prof, mine) or prof, onClick = function() L:OpenProfession(prof) end,
      linkTip = "Opens the Professions page on " .. prof .. "." }
  end
  return gridSection(p, holder, W, band, "tradeskills", rows, labels, states, { title = "Tradeskills", count = ("%d of %d"):format(info.done, info.total),
    levels = L.TRADESKILL_LEVELS, icon = function(cell, r) cell:SetTexture(Panoply.ProfUI and Panoply.ProfUI.IconFor(r.prof) or (I .. "INV_Misc_QuestionMark")) end })
end

local function pvpSection(p, holder, W, band, states, info)
  local y = header(p, holder, 0, 0, W, "PvP", L.HELP.pvp, ("%d of %d"):format(info.done, info.total))
  -- the ranks: pips against the rank reached (a box each when the game does not tell the rank)
  local ranks = L:RowsOf("pvp")
  local rankRows = {}
  for _, r in ipairs(ranks) do if r.rank then rankRows[#rankRows + 1] = r end end
  if L:Mode("pvprank") == "auto" then
    local done, best = 0, 0
    for _, r in ipairs(rankRows) do local st = states[r.id] if st.state == "done" then done = done + 1 end best = max(best, st.have or 0) end
    local _, lfs = text(holder, 4, y - 2, 60, 12, "text.primary", "Ranks")
    local pips = Kit.Pips(holder, { accent = "legacy.resourcefulness", size = 10, gap = 6 })
    local pw = pips:Set(done, #rankRows)
    pips:SetPoint("TOPLEFT", holder, "TOPLEFT", 4 + 60 + SP.s, y - 4)
    local marks = {}
    for _, r in ipairs(rankRows) do marks[#marks + 1] = tostring(r.rank) end
    text(holder, 4 + 60 + SP.s + pw + SP.m, y - 2, max(40, W - 80 - pw - SP.m), 11, "text.muted",
      ("%s · now rank %d"):format(table.concat(marks, " / "), best))
    pips.panoplyKitPips = true
    p.rankPips = pips
    y = y - 22
  else
    for _, r in ipairs(rankRows) do y = y - stateRow(p, holder, { x = 4, y = y, w = W - 8, label = r.label, st = states[r.id], slot = "icon.pvp.rank" }) end
  end
  for _, r in ipairs(ranks) do
    if r.ex then
      local st = states[r.id]
      y = y - stateRow(p, holder, { x = 4, y = y, w = W - 8, label = r.label, st = st, slot = "icon.pvp.rank", accent = "legacy.resourcefulness" })
      if r.ex.note and st.manual then
        p.ticks[#p.ticks].tipBody = r.ex.note
      end
    end
  end
  for _, r in ipairs(ranks) do
    if r.week then
      local st = states[r.id]
      local _, d = L:FieldWeekStart(r.week)
      local words = st.state == "locked" and ("From " .. L.DateText(d)) or nil
      y = y - stateRow(p, holder, { x = 4, y = y, w = W - 8, label = r.label, st = st, slot = "icon.pvp.rank",
        accent = "legacy.resourcefulness", right = words })
    end
  end
  return -y
end

local function dungeonSection(p, holder, W, band, states, info)
  local y = header(p, holder, 0, 0, W, "Dungeons", L.HELP.dungeons, ("%d of %d"):format(info.done, info.total))
  for _, r in ipairs(L:RowsOf("dungeons")) do
    local st = states[r.id]
    local open = L.open[r.tier.key] and true or false
    local label = ("%s (levels %d to %d)"):format(r.label, r.tier.from, r.tier.to)
    local rowY = y
    -- 0.9.5 phase 4G: reached from At Your Level's Spelunker badge: the page scrolls to this band
    if L.focus and L.focus.section == "dungeons" and L.focus.tier == r.tier.key then Page.focusRow = { id = r.id, y = rowY } end
    y = y - stateRow(p, holder, { x = 4, y = y, w = W - 8, label = (open and "- " or "+ ") .. label, st = st, slot = "icon.instance.dungeon", accent = "legacy.resourcefulness",
      onClick = function() L.open[r.tier.key] = not L.open[r.tier.key] p.sig = nil Menu:RefreshCurrent() end,
      linkTip = open and "Click to close the list." or "Click to see its dungeons and their final bosses." })
    p.links[#p.links + 1] = { id = r.id, toggle = true, y = rowY }
    if open then
      for _, d in ipairs(st.parts or {}) do
        local bx = 4 + Page.ROW_CELL + SP.s
        local bw = W - 8 - (bx - 4) - 20 - SP.s
        local dy = y
        if d.manual then
          y = y - stateRow(p, holder, { x = bx, y = y, w = bw, label = d.name, st = { row = r, manual = true, checked = d.checked, state = d.checked and "done" or "todo" },
            tickId = d.id })
          if d.note then p.ticks[#p.ticks].tipBody = d.note .. " The game does not tell Panoply about this one: tick it when you have done it." end
        else
          local dh = text(holder, bx, y - 2, bw, 12, d.done and "text.primary" or "text.muted", d.name .. (d.done and " · done" or ""))
          y = y - dh - 4
          for _, b in ipairs(d.bosses) do
            local words = ("%s%s · %s"):format(b.boss, b.wing and (" (" .. b.wing .. ")") or "", b.by and ("killed by " .. b.by) or "not yet")
            local bh = text(holder, bx + SP.l, y, bw - SP.l, 11, b.by and "text.primary" or "text.muted", words)
            y = y - bh - 2
          end
          if d.note then local nh = text(holder, bx + SP.l, y, bw - SP.l, 11, "text.muted", d.note, true) y = y - nh - 2 end
        end
        local mb = mapButton(holder, d.inst)
        mb:SetPoint("TOPLEFT", holder, "TOPLEFT", W - 4 - 20, dy)
        if not d.inst then mb:Hide() end
        p.links[#p.links + 1] = { id = d.id, map = mb }
        y = y - SP.xs
      end
    end
  end
  return -y
end

local function listSection(p, holder, W, band, states, info, cat, title, slotFor)
  local y = header(p, holder, 0, 0, W, title, L.HELP[cat], ("%d of %d"):format(info.done, info.total))
  for _, r in ipairs(L:RowsOf(cat)) do
    local st = states[r.id]
    local right
    if r.id == "adv.explore" and st.have then right = st.state == "done" and nil or ("%.1f%%"):format(st.have) end
    if r.id == "adv.valthalak" and not st.manual then right = st.state == "done" and nil or ("step %d of %d"):format(st.have or 0, #L.VALTHALAK.steps) end
    if r.raid and st.state ~= "locked" and not st.manual then right = ("%d of %d bosses"):format(st.have or 0, r.raid.bosses) end
    y = y - stateRow(p, holder, { x = 4, y = y, w = W - 8, label = r.raid and ("%s (%d %s)"):format(r.label, r.raid.bosses, plural(r.raid.bosses, "boss", "bosses")) or r.label,
      st = st, slot = slotFor(r), accent = cat == "raids" and "legacy.resourcefulness" or "legacy.adventure", right = right })
  end
  return -y
end

function Page:DrawChallenges(p, content, W, band, states)
  local cats = {}
  for _, c in ipairs(L:Categories(states)) do cats[c.key] = c end
  local cols = band == "wide" and 2 or 1
  local gap = SP.l
  local colW = floor((W - (cols - 1) * gap) / cols)
  local builders = {
    { "classes", function(h) return classSection(p, h, colW, band, states, cats.classes) end },
    { "tradeskills", function(h) return tradeSection(p, h, colW, band, states, cats.tradeskills) end },
    { "pvp", function(h) return pvpSection(p, h, colW, band, states, cats.pvp) end },
    { "dungeons", function(h) return dungeonSection(p, h, colW, band, states, cats.dungeons) end },
    { "raids", function(h) return listSection(p, h, colW, band, states, cats.raids, "raids", "Raids", function() return "icon.instance.raid" end) end },
    { "adventure", function(h) return listSection(p, h, colW, band, states, cats.adventure, "adventure", "Adventure",
      function(r) return r.id == "adv.explore" and "icon.adventure.explore" or "icon.adventure.quest" end) end },
  }
  local colY = {}
  for i = 1, cols do colY[i] = 0 end
  p.sections = {}
  Page.focusRow = nil
  for _, b in ipairs(builders) do
    -- the shorter column takes the next section
    local ci = 1
    for i = 2, cols do if colY[i] < colY[ci] then ci = i end end
    local holder = CreateFrame("Frame", nil, content)
    holder.panoplyGapOK = true
    holder:SetPoint("TOPLEFT", content, "TOPLEFT", (ci - 1) * (colW + gap), -colY[ci])
    local h = b[2](holder)
    holder:SetSize(colW, max(1, h))
    holder.panoplySection = b[1]
    p.sections[b[1]] = holder
    if Page.focusRow and not Page.focusY and L.focus and L.focus.section == b[1] then Page.focusY = max(0, colY[ci] + (-Page.focusRow.y) - 40) end
    colY[ci] = colY[ci] + h + SP.l
  end
  if L.focus then L.focus = nil end
  local hmax = 0
  for i = 1, cols do hmax = max(hmax, colY[i]) end
  return hmax
end

-------------------------------------------------------------------------------
-- Perk plan
-------------------------------------------------------------------------------
function Page:DrawTreeSwitch(p, fixed, x, y, W)
  local bw = floor((W - 2 * SP.s) / 3)
  p.treeBtns = {}
  for i, t in ipairs(L.TREES) do
    local b = Skin.Button(fixed, t.name, bw, 24, function()
      if L.tree ~= t.key then L.tree = t.key p.sig = nil Menu:RefreshCurrent() if Panoply.History then Panoply.History:Note("tree") end end
    end, t.name, "Show the " .. t.name .. " tree.")
    b:SetPoint("TOPLEFT", fixed, "TOPLEFT", x + (i - 1) * (bw + SP.s), y)
    b:SetSelected(L.tree == t.key)
    b.panoplyTree = t.key
    if TW(b.label) > bw - 8 then Skin.Ellipsize(b.label, t.name, bw - 8) end
    p.treeBtns[#p.treeBtns + 1] = b
  end
  return 24
end

-- one tree: header, then a card (the tree's accent stripe down its left) holding the tier rows of talent nodes, the arrows and the empty
-- future slots. Returns the height.
local function drawTree(p, holder, tree, W, actual)
  local plan = L:Plan()
  local pts = L:TreePoints(tree.key, plan)
  local accent = "legacy." .. tree.key
  local top = header(p, holder, 0, 0, W, tree.name, nil, ("%d %s"):format(pts, plural(pts, "point")))
  local card = Kit.Surface(holder, 1)
  card:SetAccent(accent)
  card:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, top)
  card.panoplyTree = tree.key
  local y = 0
  local s, g = Page.NODE, Page.NODE_GAP
  local gridW = L.TREE_COLS * s + (L.TREE_COLS - 1) * g
  local labelW = 26
  local x0 = max(labelW + SP.s, floor((W - gridW - labelW) / 2) + labelW)
  local byId, taken = {}, {}
  for ti, gate in ipairs(L.TIERS) do
    local rowY = y - (ti - 1) * (s + Page.TIER_GAP) - SP.s
    local open = L:TierOpen(tree.key, gate, plan)
    local lab = Skin.Ink(card, 10, Kit.Color("text.muted"))
    lab:SetText(tostring(gate)); lab:SetWidth(labelW); lab:SetHeight(ceil(TH(lab)))
    if lab.SetJustifyH then lab:SetJustifyH("RIGHT") end
    lab:SetPoint("TOPLEFT", card, "TOPLEFT", x0 - labelW - SP.s, rowY - floor((s - 12) / 2))
    Skin.Tooltip(lab, "Tier " .. ti, ("Opens with %d points in %s in the tiers above."):format(gate, tree.name))
    for _, pk in ipairs(L:Perks(tree.key)) do
      if pk.gate == gate then
        local node = Kit.TalentNode(card, { size = s, onClick = function(_, button)
          if button == "RightButton" then L:RemoveRank(pk.id) else L:AddRank(pk.id) end
        end })
        local r = L:PlanRank(pk.id, plan)
        local canAdd, why = L:CanAdd(pk.id)
        local lines = {}
        for i = 1, pk.ranks do lines[#lines + 1] = ("%sRank %d: %s"):format(i == r and "> " or "", i, L:RankText(pk, i)) end
        if pk.prereq then local q = L:Perk(pk.prereq) if q then lines[#lines + 1] = "Needs " .. q.name .. " at full rank." end end
        if gate > 0 then lines[#lines + 1] = ("Needs %d points in %s in the tiers above."):format(gate, tree.name) end
        if actual then lines[#lines + 1] = ("In the game: %d of %d."):format(tonumber(actual[pk.id]) or 0, pk.ranks) end
        if pk.affects == "camp" then lines[#lines + 1] = "Changes what the Professions page's Camp tab and Next card show." end
        if not canAdd and r < pk.ranks and why then lines[#lines + 1] = why end
        lines[#lines + 1] = "Click: one rank more. Right-click: one rank less."
        node:Set({ icon = L:PerkIcon(pk), rank = r, max = pk.ranks, available = canAdd or r > 0, locked = not open and r == 0,
          tip = ("%s  %d/%d"):format(L:PerkName(pk), r, pk.ranks), tipBody = table.concat(lines, "\n") })
        if actual and (tonumber(actual[pk.id]) or 0) ~= r then
          local wc = Kit.Color("state.warn")
          node.rim:SetVertexColor(wc[1], wc[2], wc[3], 1)
          node.panoplyDiffers = true
        end
        node:SetPoint("TOPLEFT", card, "TOPLEFT", x0 + (pk.col - 1) * (s + g), rowY)
        node.panoplyPerk = pk.id
        byId[pk.id] = node
        taken[ti .. ":" .. pk.col] = true
        p.nodes[#p.nodes + 1] = node
      end
    end
  end
  -- the empty future slots: the free cells of the last tier first, then the tier above
  local placed = 0
  for ti = #L.TIERS, 1, -1 do
    for col = 1, L.TREE_COLS do
      if placed < L.FUTURE_SLOTS and not taken[ti .. ":" .. col] then
        -- never in the path of an arrow
        local blocked = false
        for _, pk in ipairs(L:Perks(tree.key)) do
          if pk.prereq and pk.col == col then
            local q = L:Perk(pk.prereq)
            local tq, tp
            for i, gt in ipairs(L.TIERS) do if gt == q.gate then tq = i end if gt == pk.gate then tp = i end end
            if tq and tp and ti > tq and ti < tp then blocked = true end
          end
        end
        if not blocked then
          local rowY = y - (ti - 1) * (s + Page.TIER_GAP) - SP.s
          local node = Kit.TalentNode(card, { size = s })
          node:Set({ icon = "Interface\\Icons\\INV_Misc_QuestionMark", rank = 0, max = 1, locked = true, tip = "A future perk",
            tipBody = "Blizzard plans more perks for this tree." })
          node.rankText:SetText("")
          node.plate:Hide()
          node:SetPoint("TOPLEFT", card, "TOPLEFT", x0 + (col - 1) * (s + g), rowY)
          node.panoplyFuture = true
          p.nodes[#p.nodes + 1] = node
          taken[ti .. ":" .. col] = true
          placed = placed + 1
        end
      end
    end
  end
  -- the arrows
  for _, pk in ipairs(L:Perks(tree.key)) do
    if pk.prereq and byId[pk.id] and byId[pk.prereq] then
      local q = L:Perk(pk.prereq)
      local a = Kit.TalentArrow(card, byId[pk.prereq], byId[pk.id])
      a:Layout(false)
      a:SetMet(L:PlanRank(q.id, plan) >= q.ranks)
      a.panoplyFrom, a.panoplyTo = q.id, pk.id
      p.arrows[#p.arrows + 1] = a
    end
  end
  local gridH = #L.TIERS * s + (#L.TIERS - 1) * Page.TIER_GAP + 2 * SP.s
  card:SetSize(W, gridH)
  return -(top - gridH) + SP.s
end


function Page:DrawPlan(p, content, W, band, meter)
  local y = header(p, content, 0, 0, W, "Perk plan", L.HELP.plan, ("%d of %d planned"):format(L:PlanTotal(), L.CAP))
  -- presets and clear
  local btns = {}
  for _, pre in ipairs(L.PRESETS) do
    local b = Skin.Button(content, pre.name, 120, 26, function() L:ApplyPreset(pre.key) end, "Preset: " .. pre.name, pre.tip .. " Fills the plan; nothing is spent.")
    b:SetSelected(L:PresetOn(pre.key))
    b.panoplyPreset = pre.key
    btns[#btns + 1] = b
  end
  local clear = Skin.Button(content, "Clear plan", 110, 26, function() L:ClearPlan() end, "Clear plan", "Takes every planned rank away.")
  clear:SetEnabledLook(L:PlanTotal() > 0)
  btns[#btns + 1] = clear
  p.presetBtns = btns
  y = y - Skin.FlowButtons(content, btns, 4, y, W - 8, SP.s, 90) - SP.s
  -- the reset note and the promise
  local h1 = text(content, 4, y, W - 8, 11, "text.muted", L.RESET_NOTE, true)
  y = y - h1 - 2
  local h2 = text(content, 4, y, W - 8, 11, "text.muted", L.NEVER_SPENDS, true)
  y = y - h2 - SP.s
  -- when the game does not say what is spent: one box, "this plan is what I spent"
  if not L:SpentLive() then
    local chk = Skin.Check(content, "I have spent this plan in the game", { get = function() return L:PlanSpent() end, set = function(v) L:SetPlanSpent(v) end }, nil,
      "The game does not tell Panoply what this character spent. Tick this when your points in the game match this plan: the top strip then counts them.", true)
    chk:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
    local _, ch = chk:FitLabel(W - 40)
    p.spentCheck = chk
    p.ticks[#p.ticks + 1] = chk
    y = y - max(18, ch) - SP.m
  end
  local actual = L:Actual()
  if band == "wide" then
    local gap = SP.l
    local tw = floor((W - 2 * gap) / 3)
    local hmax = 0
    for i, t in ipairs(L.TREES) do
      local holder = CreateFrame("Frame", nil, content)
      holder.panoplyGapOK = true
      holder:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (tw + gap), y)
      local h = drawTree(p, holder, t, tw, actual)
      holder:SetSize(tw, max(1, h))
      hmax = max(hmax, h)
    end
    y = y - hmax
  else
    local t = L:Tree(L.tree) or L.TREES[1]
    local holder = CreateFrame("Frame", nil, content)
    holder.panoplyGapOK = true
    holder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    local h = drawTree(p, holder, t, W, actual)
    holder:SetSize(W, max(1, h))
    y = y - h
  end
  return -y + SP.m
end

-------------------------------------------------------------------------------
-- The page follows the model
-------------------------------------------------------------------------------
Panoply:Listen("LEGACY_CHANGED", function()
  if Menu.frame and Menu.frame:IsShown() and Menu.current == "legacy" then Menu:RefreshCurrent() end
end)
-- the header's own readout: how far the account is
Menu.headerExtra.legacy = function() return "POINTS", ("%d of %d"):format((L:Points()), L:Total()) end
