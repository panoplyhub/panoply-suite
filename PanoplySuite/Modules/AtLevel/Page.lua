-- Panoply Suite: the "At your level" page of the one-window menu (the facts and rules are Modules/AtLevel/AtLevel.lua). 0.8.4;
-- rebuilt in 0.9.5 phase 4D (docs/specs/page-redesigns-v1.md section 4) with the shared visual system (UI/KitParts.lua) and the
-- shared slot grid (UI/SlotGrid.lua): no bordered boxes, gold only on titles, explanations in ? tooltips, no empty-state cards.
--
--   The top strip (pinned)   line 1: the class crest, "Level 15 Hunter", the XP bar to the next level with the rested part shaded,
--                            the percent; the doors (Guide, Class gear, all dungeon maps) as icon buttons at the right.
--                            line 2: chips, each one a click: Trainer ("2 spells · 24s" opens the spell plan; the arrow points to
--                            the trainer; grey "Next: level 16, ..." when nothing can be bought now), Class quest (only when one is
--                            open or opens within the window), Window ("Showing level 15 to 18" with a stepper up to +5).
--   Dungeons                 one row a dungeon in the window, the best fit first: instance icon, name, a badge when the way in is in
--                            the other side's land, Now / At 17, Point me there and Map right after the name; the level range drawn
--                            against your level in the quest colours; the door's zone and place; "3 upgrades for you" (marks those
--                            cells of the grid) and, on WoW Forever, "Counts toward Novice Spelunker (2/6)" (opens Legacy).
--   Upgrades by slot         the slot grid: the worn item in each slot, the best upgrade over its corner with "+14" or "At 17", the
--                            quality as the border. A click opens the slot's list: every candidate, best first, with its source,
--                            its level and Point me there. The headline counts exactly the cells in full colour.
--   Bands                    Wide: Dungeons (~45%) beside the grid (~55%). Medium: one column, Dungeons first, the grid 4 wide.
--                            Narrow: the grid 2 wide, the range bar becomes a "15-20" chip, the strip's chips wrap.
-- Only the part under the strip scrolls. Nothing here buys, equips, routes or casts: every button opens a page or sets a waypoint
-- through Go to.
local ADDON, Panoply = ...
local AL = Panoply.AtLevel
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Page = {}
AL.PageFrame = Page
Page.GRIP = 22           -- room left under the scrolling part for the window's resize grip and corner
Page.ROW_ICON = 22       -- a dungeon row's instance icon
Page.RANGE_W = 120       -- the level range bar
Page.BTN = 20            -- Point me there and Map

local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end

-- an item's name in the game's colour for its quality
function AL.ItemName(it)
  return ("|cff%s%s|r"):format(AL.QUALITY_COLOR[it.quality or 1] or AL.QUALITY_COLOR[1], it.name or "?")
end

-------------------------------------------------------------------------------
-- Icon slots (spec section 9)
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
-- the page's own menu icon (the left list's): no other page shares it
Kit.RegisterIcon("icon.page.atyourlevel", { icon = "MenuAtLevel", own = true })
Kit.RegisterIcon("icon.instance.dungeon", Kit.ICONS["icon.instance.dungeon"] or { game = { I .. "INV_Misc_Key_14", I .. "INV_Misc_Key_03" } })
Kit.RegisterIcon("icon.instance.raid", Kit.ICONS["icon.instance.raid"] or { game = { I .. "INV_Misc_Head_Dragon_01", I .. "INV_Misc_Key_14" } })
Kit.RegisterIcon("icon.faction.alliance", { game = { I .. "INV_BannerPVP_02", I .. "INV_Misc_QuestionMark" } })
Kit.RegisterIcon("icon.faction.horde", { game = { I .. "INV_BannerPVP_01", I .. "INV_Misc_QuestionMark" } })
-- (icon.trainer and icon.quest.class are not registered: the strip's chips are words, with no picture)
Kit.RegisterIcon("icon.ui.classgear", { game = { I .. "INV_Chest_Chain_05", I .. "INV_Chest_Cloth_17" } })
-- the class crests: the game's class circle texture, cut to each class
local CREST = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CREST_CUT = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
for cls in pairs(CREST_CUT) do
  if not Kit.ICONS["icon.class." .. cls:lower()] then Kit.RegisterIcon("icon.class." .. cls:lower(), { game = { CREST }, raw = true }) end
end

-------------------------------------------------------------------------------
-- The words (also read by the tests and the previews)
-------------------------------------------------------------------------------
AL.HELP = {
  dungeons = "The dungeons and raids of your level and of the next few levels, the best fit first. The bar is the level of their monsters, coloured the way quests are, with a mark at your level.",
  gear = "The best piece for each slot from the quests, dungeons, vendors and crafts of these levels, ranked by the gear engine for your plan's stat weights. A piece that needs a higher level shows its level. Raid drops are not listed here. Items with an effect are scored on their plain stats.",
  window = "How far ahead this page looks. Widen it to see what opens a little later.",
}

-- the door of a row, in words: "Westfall 38.0, 77.5", or for a dungeon only WoW Forever has, its zone and that the way in is not
-- charted ("Source unknown" when even the zone is not known)
function AL:WhereText(r)
  if r.forever then
    local z = r.inst.zoneName
    return z and (z .. ", entrance not charted yet") or "Entrance: source unknown"
  end
  local where = self:Door(r.inst)
  return where or "No entrance in the atlas"
end

-- the level range in words: "15-20" (a raid: "Level 60")
function AL.RangeText(r)
  if r.kind == "raid" then return ("Level %d"):format(AL.LAST_LEVEL) end
  if r.lo == r.hi then return tostring(r.lo) end
  return ("%d-%d"):format(r.lo, r.hi)
end

-- Everything the page shows, as data (no frames). d = { level, own, class, className, window, top, xp = { cur, max, rested, pct } | nil,
-- trainer = AL:TrainerChip() | nil, quest = AL:ClassQuestChip() | nil, dungeons = { rows, now, soon, head, note }, grid = AL:Grid(),
-- gear = { head, weighedFor, note } }
function AL:PageData()
  local me = self:Player()
  local level, own = self:Level()
  local class = me.class
  local window = self:Window()
  local d = { level = level, own = own, class = class, className = me.className or "character", window = window,
    top = min(AL.LAST_LEVEL, level + window) }
  if own and level < AL.LAST_LEVEL then
    local _, xp, xpMax, rested = C.XPKnown()
    if type(xp) == "number" and type(xpMax) == "number" and xpMax > 0 then
      d.xp = { cur = xp, max = xpMax, rested = type(rested) == "number" and rested or 0, pct = floor(xp / xpMax * 100) }
    end
  end
  d.trainer = own and self:TrainerChip() or nil
  d.quest = self:ClassQuestChip(level, class)
  d.grid = self:Grid(level, class)
  -- dungeons
  local list = self:Dungeons(level)
  local spel = self:Spelunker()
  local faction = C.PlayerInfo and (C.PlayerInfo() or {}).faction or nil
  local dn = { rows = {}, now = 0, soon = 0 }
  local mapOn = Panoply.Map ~= nil and Panoply.Map.Instances ~= nil and Panoply.Modules ~= nil and Panoply.Modules:IsOn("map")
  for _, r in ipairs(list) do
    if r.when == "now" then dn.now = dn.now + 1 else dn.soon = dn.soon + 1 end
    local row = { name = r.name, id = r.id, inst = r.inst, kind = r.kind, when = r.when, from = r.from, lo = r.lo, hi = r.hi, forever = r.forever,
      estimated = r.inst.estimated }
    row.chip = r.when == "now" and "Now" or ("At %d"):format(r.from)
    row.range = AL.RangeText(r)
    row.where = self:WhereText(r)
    row.canGo = self:Door(r.inst) ~= nil
    row.canMap = mapOn and not r.forever
    if r.side and faction and r.side ~= faction then row.side = r.side end
    row.upgrades = AL.DungeonUpgrades(d.grid, r.id)
    local s = spel[r.name]
    if s then row.spelunker = s end
    row.blueprints = self:Blueprints(r.name)
    dn.rows[#dn.rows + 1] = row
  end
  if dn.now > 0 and dn.soon > 0 then dn.head = ("%d now, %d soon"):format(dn.now, dn.soon)
  elseif dn.now > 0 then dn.head = ("%d now"):format(dn.now)
  elseif dn.soon > 0 then dn.head = ("%d soon"):format(dn.soon)
  else dn.head = "None in range" end
  if #list == 0 then
    -- the next one to open, as one line (not a card)
    local best, bestFrom
    for _, inst in ipairs((self:Instances())) do
      if inst.kind ~= "raid" then
        local from = max(inst.enter or 0, (inst.mobs[1] or 1) - 3)
        if from > level and (not bestFrom or from < bestFrom) then best, bestFrom = inst, from end
      end
    end
    if best then dn.note = ("The next one is %s, from about level %d."):format(best.name, bestFrom)
    elseif not self:MapData() then dn.note = "The dungeon list needs Panoply Suite Quest Data; it is not loaded."
    else dn.note = "Nothing opens in the next few levels." end
  end
  d.dungeons = dn
  -- the gear headline: exactly the cells in full colour, and the locked ones
  local g = d.grid
  local gear = { weighedFor = g.weighedFor }
  if g.noWeights or not g.best then gear.head = "No gear weights for this class yet"
  elseif g.working then gear.head = "Looking through the gear for these levels"
  elseif g.now == 0 and g.later == 0 then gear.head = own and "Nothing beats what you wear" or "No gear listed for this level"
  else
    gear.head = g.now > 0 and ("Upgrades for %d %s"):format(g.now, plural(g.now, "slot")) or "No upgrade to wear yet"
    if g.later > 0 then gear.head = gear.head .. (", %d at a higher level"):format(g.later) end
  end
  if g.wornPending then gear.note = "The game has not said yet what you wear in every slot." end
  d.gear = gear
  return d
end

-- one cell of the grid as the slot grid draws it
-- (an item the game has not sent its picture for yet shows the game's question mark until it does)
local function itemIcon(it)
  if not it then return nil end
  return C.ItemIcon(it.link or it.id or it.itemID) or Skin.UNKNOWN_ITEM
end
local function itemRef(it) return it and (it.link or it.id or it.itemID) or nil end
function AL.CellView(cell, mine)
  local up = cell.now or cell.soon
  local v = { key = cell.key, label = cell.label, state = cell.state }
  -- (0.9.7 hotfix: item = the id or link, so the slot grid paints the picture again when the game sends the item)
  if cell.worn then v.icon, v.quality, v.item = itemIcon(cell.worn), cell.worn.quality, itemRef(cell.worn) end
  if up then v.over = { icon = itemIcon(up), quality = up.quality, name = up.name, item = itemRef(up) } end
  if cell.pairOf then v.value = "Pair"
  elseif cell.state == "up" then v.value = Panoply.Gear.DeltaText(cell.now.delta)
  elseif cell.state == "locked" then v.value = cell.at and ("At %d"):format(cell.at) or "Needs training"
  else v.value = "No upgrade" end
  local lines = {}
  if cell.worn then lines[#lines + 1] = ("Worn: %s"):format(AL.ItemName(cell.worn))
  elseif mine then lines[#lines + 1] = "Worn: nothing" end
  if cell.pairOf then
    lines[#lines + 1] = ("Best now: %s, with %s in the main hand, in place of your two-hand weapon: one swap, %s together."):format(AL.ItemName(cell.now),
      AL.ItemName(cell.pairOf), Panoply.Gear.DeltaText(cell.pairOf.delta))
  elseif cell.now then lines[#lines + 1] = ("Best now: %s %s, %s"):format(AL.ItemName(cell.now), Panoply.Gear.DeltaText(cell.now.delta), Panoply.Gear.SourceText(cell.now.source)) end
  if cell.soon then lines[#lines + 1] = ("%s: %s %s, %s"):format(cell.soon.lockReason or (cell.at and ("At level " .. cell.at)) or "Later", AL.ItemName(cell.soon),
    Panoply.Gear.DeltaText(cell.soon.delta), Panoply.Gear.SourceText(cell.soon.source)) end
  if not up then lines[#lines + 1] = "Nothing in these levels beats it." end
  lines[#lines + 1] = "Click for every candidate."
  v.tip, v.tipBody = cell.label, table.concat(lines, "\n")
  return v
end

-------------------------------------------------------------------------------
-- Small parts
-------------------------------------------------------------------------------
-- one line (or a wrapped block) of text at (x, y) of parent, w wide: returns its height and the font string
local function text(parent, x, y, w, size, token, words, wrap, name)
  local fs = name and Skin.Name(parent, size or 12, Kit.Color(token or "text.primary")) or Skin.Ink(parent, size or 12, Kit.Color(token or "text.muted"))
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(max(10, w))
  if wrap then
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(words or "")
  else
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    Skin.Ellipsize(fs, words or "", max(10, w))
  end
  local h = ceil(TH(fs, max(10, w)))
  fs:SetHeight(h)
  return h, fs
end
-- a text that is exactly as wide as its words (at most maxW): returns its width, height, font string
local function word(parent, x, y, size, token, words, maxW, name)
  local h, fs = text(parent, x, y, maxW or 400, size, token, words, false, name)
  local w = min(maxW or 400, ceil(TW(fs)) + 2)
  fs:SetWidth(w)
  return w, h, fs
end
-- a chip that is a button: StatusChip words and colour, a tooltip, a click
local function chipButton(parent, kind, words, onClick, tip, body)
  local b = CreateFrame("Button", nil, parent)
  b.panoplyKit, b.panoplyGapOK = "ChipButton", true
  local chip = Kit.StatusChip(b, kind, words)
  local w, h = chip:Set(kind, words)
  chip:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b:SetSize(w, h)
  b.chip = chip
  Skin.Tooltip(b, tip or words, body)
  b:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
  return b
end
-- an icon button: a glyph of the skin or an icon slot
local function iconButton(parent, glyph, slot, size, onClick, tip, body)
  local b = Skin.IconButton(parent, "", size or Page.BTN, onClick, tip, body)
  b:SetIcon(glyph or "Map", floor((size or Page.BTN) * 0.7))
  if slot then
    b.panoplyKitIcon = slot
    -- (the Guide's picture follows the icon style here: the game's own in WoW icons, not the left list's drawing)
    if slot == "icon.guide" then Skin.SetIcon(b.icon, "Leveling", { size = floor((size or Page.BTN) * 0.7) })
    elseif not glyph then Kit.Icon(b.icon, slot, { size = floor((size or Page.BTN) * 0.7) }) end
  end
  return b
end
local function crest(tex, cls)
  tex:SetTexture(CREST)
  local t = type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[cls] or CREST_CUT[cls]
  if t and tex.SetTexCoord then tex:SetTexCoord(t[1], t[2], t[3], t[4]) end
  tex.panoplySlot = "icon.class." .. tostring(cls):lower()
end

-------------------------------------------------------------------------------
-- The page's state (history): the expanded slot, the dungeon whose upgrades are marked, the window, where it is scrolled
-------------------------------------------------------------------------------
-- The open slot is the page's remembered state (Kit page state, "slot.<key>"), so the header's Reset view closes it; Reset view
-- also lets go of the marked dungeon and narrows the window again.
AL.slot = AL.slot        -- the slot whose list is open (nil: none)
AL.mark = AL.mark        -- the dungeon whose upgrades are marked on the grid (nil: none)
local function savedSlot()
  for _, k in ipairs(AL.PAPER) do if Kit.GetOpen("atlevel", "slot." .. k, false) then return k end end
  return nil
end
local function setSlot(key)
  for _, k in ipairs(AL.PAPER) do if k ~= key then Kit.ForgetOpen("atlevel", "slot." .. k) end end
  if key then Kit.SetOpen("atlevel", "slot." .. key, true) end
  AL.slot = savedSlot()
end
Kit.OnReset("atlevel", function() AL.slot, AL.mark = nil, nil AL:SetWindow(AL.AHEAD) end)
if Panoply.History then Panoply.History:State("atlevel", {
  get = function() return { slot = AL.slot, mark = AL.mark, window = AL:Window(), level = AL.viewLevel, scroll = Page.area and Page.area:GetVerticalScroll() or 0 } end,
  set = function(s)
    if type(s) ~= "table" then return end
    setSlot(s.slot)
    AL.mark, AL.viewLevel = s.mark, s.level
    AL:SetWindow(s.window)
    Page.pendingScroll = s.scroll or 0
  end,
  key = function(s) return type(s) == "table" and (tostring(s.slot) .. "|" .. tostring(s.mark) .. "|" .. tostring(s.window) .. "|" .. tostring(s.level)) or tostring(s) end,
}) end

function AL:SelectSlot(key)
  setSlot(savedSlot() ~= key and key or nil)
  if Panoply.History then Panoply.History:Note("slot") end
  Menu:RefreshCurrent()
end
function AL:MarkDungeon(id)
  if self.mark == id then self.mark = nil else self.mark = id end
  Page.focusGrid = self.mark ~= nil
  if Panoply.History then Panoply.History:Note("mark") end
  Menu:RefreshCurrent()
end
function AL:StepWindow(delta)
  self:SetWindow(self:Window() + delta)
  if Panoply.History then Panoply.History:Note("window") end
  Menu:RefreshCurrent()
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
Menu:RegisterTab("AtLevel", function(p)
  p.msg = Skin.Ink(p, 13, Kit.Color("text.muted"))
  p.area = Skin.ScrollArea(p)
  Page.area = p.area
  p.panoplyArea = nil
end, function(p) Page:Render(p) end)

-- what is drawn: when it is the same as last time, nothing is drawn again. (0.9.6: the experience a kill or a quest gives is not part
-- of it: the bar takes it in place, Page:UpdateXP. Before, every kill drew the whole page again on new frames, and frames are
-- never freed, so the menu grew slower through an evening.)
local function signature(p, d, W, H, band)
  local t = { W, H, band, tostring(AL.slot), tostring(AL.mark), d.level, tostring(d.own), d.window, tostring(Panoply.ClassPages ~= nil), tostring(Skin.Style()) }
  if d.xp then t[#t + 1] = "xp" end
  t[#t + 1] = d.trainer and d.trainer.text or "-"
  if d.quest then t[#t + 1] = table.concat({ d.quest.q.id, d.quest.now, d.quest.soon, tostring(d.quest.q.inLog) }, ":") end
  for _, r in ipairs(d.dungeons.rows) do
    t[#t + 1] = table.concat({ tostring(r.id), r.chip, r.upgrades, tostring(r.canGo), tostring(r.canMap), tostring(r.side),
      r.spelunker and (r.spelunker.done .. "/" .. r.spelunker.total) or "", #(r.blueprints or {}) > 0 and r.blueprints[1].name or "" }, ":")
  end
  t[#t + 1] = tostring(d.dungeons.note)
  t[#t + 1] = d.gear.head .. tostring(d.gear.note) .. tostring(d.gear.weighedFor)
  for _, c in ipairs(d.grid.cells) do
    local up = c.now or c.soon
    t[#t + 1] = table.concat({ c.key, c.state, tostring(c.worn and (c.worn.link or c.worn.id)), up and tostring(up.itemID) or "", up and tostring(up.delta) or "", #c.list }, ":")
  end
  return table.concat(t, "|")
end

function Page:Render(p)
  local me = AL:Player()
  local W, H = p.width or 600, p.height or 400
  local function message(words)
    p.sig = nil
    if p.fixed then p.fixed:Hide() end
    if p.content then p.content:Hide() end
    p.area:Hide()
    p.data = nil
    p.msg:ClearAllPoints(); p.msg:SetPoint("TOPLEFT", p, "TOPLEFT", 4, 0); p.msg:SetWidth(W - 8)
    p.msg:SetText(words)
    p.msg:SetHeight(TH(p.msg, W - 8))
    p.msg:Show()
  end
  if not Panoply.GearRules.classes[me.class or ""] then return message("Panoply Suite cannot read your class yet. Open this page again in a moment.") end
  if not AL:Available() then return message("This page needs Panoply Suite Quest Data, and it is not loaded. Turn it on in the game's AddOns list.") end
  p.msg:Hide()
  AL.slot = savedSlot()
  local band = Kit.Band(W)
  local d = AL:PageData()
  -- a marked dungeon or an open slot that is no longer on the page is let go
  if AL.mark and AL.DungeonUpgrades(d.grid, AL.mark) == 0 then AL.mark = nil end
  local sig = signature(p, d, W, H, band)
  p.data = d
  if p.sig == sig then self:UpdateXP(p, d) return end
  p.sig = sig
  self:Draw(p, d, W, H, band)
end

function Page:Draw(p, d, W, H, band)
  p.band = band
  if p.fixed then p.fixed:Hide() end
  if p.content then p.content:Hide() end
  p.rows, p.links, p.buttons = {}, {}, {}
  local fixed = CreateFrame("Frame", nil, p)
  fixed:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); fixed:SetSize(W, H)
  fixed.panoplyGapOK = true
  p.fixed = fixed
  -- 1. the top strip (pinned)
  local y = -self:DrawStrip(p, fixed, W, band, d) - SP.m
  -- 2. the rest: the only part that scrolls
  local area = p.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
  area:SetSize(W, max(1, H + y - Page.GRIP))
  area:Show()
  local content = CreateFrame("Frame", nil, area.content)
  content:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
  content.panoplyGapOK = true
  p.content = content
  local cw = W - 14
  local ch, gridY
  if band == "wide" then
    local gap = SP.l + SP.s
    local lw = floor((cw - gap) * 0.45)
    local rw = cw - gap - lw
    local lh = self:DrawDungeons(p, content, 0, 0, lw, band, d)
    local rh = self:DrawGear(p, content, lw + gap, 0, rw, band, d)
    ch, gridY = max(lh, rh), 0
  else
    local lh = self:DrawDungeons(p, content, 0, 0, cw, band, d)
    gridY = -(lh + SP.l)
    local rh = self:DrawGear(p, content, 0, gridY, cw, band, d)
    ch = lh + SP.l + rh
  end
  content:SetSize(cw, max(1, ch))
  area:SetContentHeight(ch + SP.s)
  local s
  if Page.focusGrid then s = -gridY
  elseif Page.pendingScroll then s = Page.pendingScroll end
  Page.focusGrid, Page.pendingScroll = nil, nil
  if s and area.SetVerticalScroll then area:SetVerticalScroll(max(0, min(area:MaxScroll(), s))) end
  if area.UpdateBar then area:UpdateBar() end
end

-------------------------------------------------------------------------------
-- The top strip
-------------------------------------------------------------------------------
-- the experience bar, its rested part, its percent and its tooltip, on the frames already drawn (no new frame)
function Page:UpdateXP(p, d)
  local card = p.strip
  local bar = card and card.xpBar
  if not (bar and d.xp) then return end
  local bw = bar.panoplyBarW or bar:GetWidth()
  bar:SetValue(d.xp.cur, d.xp.max)
  local rest = min(d.xp.rested, d.xp.max - d.xp.cur)
  local r = bar.rested
  if r then
    if rest > 0 then
      local fx = floor(bw * d.xp.cur / d.xp.max)
      local rw = max(2, floor(bw * rest / d.xp.max))
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", bar, "TOPLEFT", fx, 0); r:SetSize(max(1, min(rw, bw - fx)), 8)
      r:Show()
    else
      r:Hide()
    end
  end
  Skin.Tooltip(bar, ("Level %d: %d of %d XP"):format(d.level, d.xp.cur, d.xp.max), rest > 0 and ("Rested: %d XP more at double speed (the shaded part)."):format(d.xp.rested) or "Not rested.")
  if card.pct then card.pct:SetText(("%d%%"):format(d.xp.pct)) end
end
function Page:DrawStrip(p, fixed, W, band, d)
  local card = Kit.Surface(fixed, 1)
  card:SetPoint("TOPLEFT", fixed, "TOPLEFT", 0, 0)
  p.strip = card
  local pad = SP.m
  local inner = W - 2 * pad
  -- the doors at the right of line 1: Back to my level (when looking at another level), Guide, Class gear, all dungeon maps
  local doors = {}
  if not d.own then
    local back = Skin.Button(card, "Back to my level", 130, 24, function() AL.viewLevel = nil if Panoply.History then Panoply.History:Note("level") end Menu:RefreshCurrent() end,
      "Back to my level", "Show the page for the level you are now.")
    Skin.FitButton(back, 110, 160)
    p.mineBtn = back
    doors[#doors + 1] = back
  else p.mineBtn = nil end
  p.guideBtn = iconButton(card, nil, "icon.guide", 24, function() Menu:Open("guide") end, "Open the Guide", "Your next step and the route to your goal.")
  doors[#doors + 1] = p.guideBtn
  if Panoply.ClassPages ~= nil and type(Panoply.ClassPages.Open) == "function" then
    p.gearBtn = iconButton(card, nil, "icon.ui.classgear", 24, function() AL:OpenClassGear() end, "Class gear", "What your class looks for in gear, on its class page.")
    doors[#doors + 1] = p.gearBtn
  else p.gearBtn = nil end
  if Panoply.Map ~= nil and Panoply.Map.Instances ~= nil and Panoply.Modules ~= nil and Panoply.Modules:IsOn("map") then
    p.mapsBtn = iconButton(card, "Map", "icon.ui.map", 24, function() AL:OpenDungeonMap(nil) end, "All dungeon maps", "Every dungeon and raid: facts, floor plan and numbered bosses.")
    doors[#doors + 1] = p.mapsBtn
  else p.mapsBtn = nil end
  local dw = 0
  for i, b in ipairs(doors) do dw = dw + b:GetWidth() + (i > 1 and SP.s or 0) end
  local x = W - pad
  for i = #doors, 1, -1 do
    local b = doors[i]
    x = x - b:GetWidth()
    b:SetPoint("TOPLEFT", card, "TOPLEFT", x, -pad)
    x = x - SP.s
  end
  -- line 1: the crest, who and what level, the XP bar and its percent
  local crestTex = card:CreateTexture(nil, "ARTWORK")
  crestTex:SetSize(24, 24)
  crestTex:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -pad)
  crest(crestTex, d.class)
  card.crest = crestTex
  local lx = pad + 24 + SP.s
  local room = inner - 24 - SP.s - dw - SP.m
  local title = d.own and ("Level %d %s"):format(d.level, d.className) or ("Looking at level %d %s"):format(d.level, d.className)
  local tw, th, tfs = word(card, lx, -pad - 3, 14, "text.primary", title, max(60, room), true)
  card.title = tfs
  local after = lx + tw + SP.m
  local barRoom = pad + inner - dw - SP.m - after
  card.xpBar = nil
  if d.xp and barRoom >= 80 then
    local pct = ("%d%%"):format(d.xp.pct)
    local pw = 40
    local bw = barRoom - pw - SP.s
    local bar = Kit.ProgressBar(card, { h = 8, accent = Kit.ClassColor(d.class) })
    bar:SetPoint("TOPLEFT", card, "TOPLEFT", after, -pad - 8)
    bar:SetBarWidth(bw)
    bar.panoplyBarW = bw
    -- the rested part, shaded after the fill (to the end of the bar at most); made once, shown when there is rest
    local r = bar:CreateTexture(nil, "ARTWORK", nil, -1)
    Skin.Solid(r, Kit.ClassColor(d.class), 0.35)
    bar.rested = r
    if bar.EnableMouse then bar:EnableMouse(true) end
    bar:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
    bar:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    card.xpBar = bar
    local _, _, pfs = word(card, after + bw + SP.s, -pad - 4, 12, "text.primary", pct, pw)
    card.pct = pfs
    self:UpdateXP(p, d)
  end
  local y = -pad - max(24, th + 6) - SP.s
  -- line 2: the chips
  local chips = {}
  if d.trainer then
    local t = d.trainer
    local b = chipButton(card, t.now and "state.good" or "state.idle", t.text,
      function() if Panoply.SpecTrainer and Panoply.SpecTrainer.OpenClassSpec then Panoply.SpecTrainer:OpenClassSpec("spells") end end,
      "Class trainer", t.now and "What to buy now, on the spell plan." or "Nothing to buy now: this is your next visit. Opens the spell plan.")
    p.trainerChip = b
    chips[#chips + 1] = { b }
    local arrow = iconButton(card, "Arrow", "icon.ui.arrow", 20, function() AL:GoToTrainer() end, "Point me to my trainer",
      "Adds your nearest class trainer to your waypoints; the arrow follows it.")
    p.trainBtn = arrow
    chips[#chips][2] = arrow
  else p.trainerChip, p.trainBtn = nil, nil end
  if d.quest then
    local q = d.quest.q
    local words = q.when == "now" and ("Class quest: %s"):format(q.name) or ("Class quest at %d: %s"):format(q.reqLevel, q.name)
    local more = (d.quest.now + d.quest.soon) - 1
    local canGo = not q.inLog and AL:CanGoToSource({ kind = "quest", id = q.id, name = q.name })
    local body = ("Level %d.%s%s"):format(q.level, q.inLog and " In your quest log: click for the Guide." or (canGo and " Click to point the arrow at whoever gives it." or " Click for the Guide."),
      more > 0 and (" And %d more %s for your class in this window."):format(more, plural(more, "quest")) or "")
    local b = chipButton(card, q.when == "now" and "state.warn" or "state.idle", words, function()
      if canGo then AL:GoToSource({ kind = "quest", id = q.id, name = q.name }) else Menu:Open("guide") end
    end, q.name, body)
    p.questChip = b
    chips[#chips + 1] = { b }
  else p.questChip = nil end
  -- the window and its stepper
  local wwords = ("Showing level %d to %d"):format(d.level, d.top)
  local wb = chipButton(card, "state.idle", wwords, nil, "Window", AL.HELP.window)
  p.windowChip = wb
  local minus = Skin.Button(card, "-", 22, 20, function() AL:StepWindow(-1) end, "Look fewer levels ahead", "Back to " .. AL.AHEAD .. " levels at the least.")
  local plus = Skin.Button(card, "+", 22, 20, function() AL:StepWindow(1) end, "Look further ahead", "Up to " .. AL.WINDOW_MAX .. " levels ahead.")
  minus:SetEnabledLook(d.window > AL.AHEAD)
  plus:SetEnabledLook(d.window < AL.WINDOW_MAX and d.top < AL.LAST_LEVEL)
  p.windowMinus, p.windowPlus = minus, plus
  chips[#chips + 1] = { wb, minus, plus }
  -- flow them, wrapping to a new line when one does not fit
  local cx, rowH = pad, 0
  local lines = 1
  for _, group in ipairs(chips) do
    local gw = 0
    for i, b in ipairs(group) do gw = gw + b:GetWidth() + (i > 1 and SP.xs or 0) end
    if cx > pad and cx + gw > pad + inner then
      y = y - rowH - SP.s
      cx, rowH, lines = pad, 0, lines + 1
    end
    for i, b in ipairs(group) do
      if i > 1 then cx = cx + SP.xs end
      local bh = b:GetHeight()
      b:SetPoint("TOPLEFT", card, "TOPLEFT", cx, y - floor((22 - bh) / 2))
      cx = cx + b:GetWidth()
      rowH = max(rowH, 22)
    end
    cx = cx + SP.m
  end
  p.chipLines = lines
  local h = -y + rowH + pad
  card:SetSize(W, h)
  return h
end

-------------------------------------------------------------------------------
-- Dungeons
-------------------------------------------------------------------------------
local function header(p, holder, x, y, w, title, help, count)
  local h = Kit.SectionHeader(holder, { title = title, help = help })
  local hh = h:Layout(x, y, w)
  if count then
    local cw, _, cfs = word(holder, 0, y + 1, 12, "text.primary", count, max(40, floor(w * 0.6)))
    cfs:ClearAllPoints(); cfs:SetPoint("TOPLEFT", holder, "TOPLEFT", x + w - (help and (16 + SP.s) or 0) - cw, y + 1)
    if cfs.SetJustifyH then cfs:SetJustifyH("RIGHT") end
    h.title:SetWidth(max(40, min(ceil(TW(h.title)) + 2, w - cw - 40)))
    h.count = cfs
  end
  return y - hh - SP.s, h
end

-- the level range against your level: a track, the range in its quest colour, a mark at your level
local function rangeBar(holder, x, y, w, r, level)
  local f = CreateFrame("Frame", nil, holder)
  f:SetSize(w, 6)
  f:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
  f.panoplyGapOK, f.panoplyKit = true, "RangeBar"
  local lo, hi = r.kind == "raid" and AL.LAST_LEVEL or r.lo, r.kind == "raid" and AL.LAST_LEVEL or r.hi
  local a, b = min(lo, level) - 3, max(hi, level) + 3
  local span = max(1, b - a)
  local track = f:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(f)
  Skin.Round(track, 3, Skin.TEX.RFill)
  track:SetVertexColor(Skin.colors.slotBottom[1], Skin.colors.slotBottom[2], Skin.colors.slotBottom[3], 1)
  local key, col = Panoply.Difficulty.Color(floor((lo + hi) / 2 + 0.5), level)
  local seg = f:CreateTexture(nil, "ARTWORK")
  local sx = floor(w * (lo - a) / span)
  local sw = max(4, floor(w * (hi - lo) / span))
  seg:SetPoint("TOPLEFT", f, "TOPLEFT", sx, 0); seg:SetSize(min(sw, w - sx), 6)
  Skin.Round(seg, 3, Skin.TEX.RFill)
  seg:SetVertexColor(col[1], col[2], col[3], 1)
  local mark = f:CreateTexture(nil, "OVERLAY")
  mark:SetSize(2, 10)
  mark:SetPoint("CENTER", f, "LEFT", floor(w * (level - a) / span), 0)
  Skin.Solid(mark, Kit.Color("text.primary"), 1)
  f.key, f.seg, f.mark = key, seg, mark
  return f
end

function Page:DrawDungeons(p, holder, x0, y0, w, band, d)
  local dn = d.dungeons
  local y = header(p, holder, x0, y0, w, "Dungeons", AL.HELP.dungeons, dn.head)
  if dn.note then
    local h = text(holder, x0 + 4, y, w - 8, 12, "text.muted", dn.note, true)
    return -(y - h - SP.m) + y0
  end
  local narrow = band == "narrow"
  for _, r in ipairs(dn.rows) do
    local row = { data = r }
    -- line 1: icon, name, the side badge, Now / At 17, Point me there and Map
    local ic = holder:CreateTexture(nil, "ARTWORK")
    ic:SetSize(Page.ROW_ICON, Page.ROW_ICON)
    ic:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, y)
    row.iconHow = Kit.Icon(ic, r.kind == "raid" and "icon.instance.raid" or "icon.instance.dungeon", { size = Page.ROW_ICON })
    row.icon = ic
    local nx = x0 + Page.ROW_ICON + SP.s
    -- what follows the name on its line, so the name knows its room
    local chip = Kit.StatusChip(holder, r.when == "now" and "now" or "soon", r.chip)
    local chipW = chip:GetWidth()
    local btnW = (r.canGo and (Page.BTN + SP.xs) or 0) + (r.canMap and (Page.BTN + SP.xs) or 0)
    local sideW = r.side and (14 + SP.xs) or 0
    local nameRoom = max(40, x0 + w - nx - SP.s - sideW - chipW - SP.s - btnW)
    local nw, nh, nfs = word(holder, nx, y - 3, 13, "text.primary", r.name, nameRoom, true)
    row.name, row.nameX, row.nameW = nfs, nx, nw
    local cx = nx + nw + SP.s
    if r.side then
      local s = holder:CreateTexture(nil, "ARTWORK")
      s:SetSize(14, 14)
      s:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y - 4)
      row.sideHow = Kit.Icon(s, r.side == "Horde" and "icon.faction.horde" or "icon.faction.alliance", { size = 14 })
      local tipF = CreateFrame("Frame", nil, holder)
      tipF:SetAllPoints(s)
      Skin.Tooltip(tipF, ("In %s land"):format(r.side), ("The way in lies in %s land."):format(r.side))
      if tipF.EnableMouse then tipF:EnableMouse(true) end
      tipF:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
      tipF:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      row.side = s
      cx = cx + 14 + SP.xs
    end
    chip:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y - 4)
    row.chip = chip
    cx = cx + chipW + SP.s
    row.buttons = {}
    if r.canGo then
      local b = iconButton(holder, "Arrow", "icon.ui.arrow", Page.BTN, function() AL:GoToDoor(r.inst) end, "Point me there",
        "Adds the door of " .. r.name .. " to your waypoints; the arrow follows it.")
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y - 2)
      row.goX = cx
      cx = cx + Page.BTN + SP.xs
      row.buttons[#row.buttons + 1] = b
      row.goBtn = b
    end
    if r.canMap then
      local b = iconButton(holder, "Map", "icon.ui.map", Page.BTN, function() AL:OpenDungeonMap(r.inst) end, "Map of " .. r.name, "The floor plan with its bosses.")
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y - 2)
      row.buttons[#row.buttons + 1] = b
      row.mapBtn = b
    end
    local ly = y - max(Page.ROW_ICON, nh + 6) - 2
    -- line 2: the range (a bar against your level; Narrow: a chip) and the door
    local wx = nx
    if narrow then
      local rc = Kit.StatusChip(holder, "state.idle", r.range)
      rc:SetPoint("TOPLEFT", holder, "TOPLEFT", nx, ly)
      row.rangeChip = rc
      wx = nx + rc:GetWidth() + SP.s
    else
      local bar = rangeBar(holder, nx, ly - 4, Page.RANGE_W, r, d.level)
      row.range = bar
      local rw = word(holder, nx + Page.RANGE_W + SP.s, ly - 1, 11, "text.primary", r.range, 70)
      wx = nx + Page.RANGE_W + SP.s + rw + SP.m
    end
    local whereText = r.where .. (r.estimated and " (level range not confirmed)" or "")
    local wh, wfs = text(holder, wx, ly - 1, max(40, x0 + w - wx), 11, "text.muted", whereText)
    row.where = wfs
    ly = ly - max(16, wh) - SP.xs
    -- line 3: the badges
    local bx = nx
    local bh = 0
    if r.upgrades > 0 then
      local words = ("%d %s for you"):format(r.upgrades, plural(r.upgrades, "upgrade"))
      local b = chipButton(holder, AL.mark == r.id and "state.warn" or "state.good", words, function() AL:MarkDungeon(r.id) end, words,
        AL.mark == r.id and "Click again to stop marking them." or "Marks the slots of the grid that this dungeon has an upgrade for.")
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, ly)
      bx = bx + b:GetWidth() + SP.s
      bh = b:GetHeight()
      row.upgradeBadge = b
      p.links[#p.links + 1] = b
    end
    if r.spelunker then
      local s = r.spelunker
      local words = ("Counts toward %s (%d/%d)"):format(s.name, s.done, s.total)
      local avail = x0 + w - bx
      local probe = Kit.StatusChip(holder, "state.idle", words)
      if probe:GetWidth() > avail and bx > nx then
        ly, bx = ly - bh - SP.xs, nx
      end
      probe:Hide()
      local b = chipButton(holder, s.this and "done" or "state.idle", words, function() AL:OpenSpelunker(s.key) end, s.name,
        (s.this and "This dungeon's final bosses are done. " or "") .. "Opens Legacy, Challenges, at this band.")
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, ly)
      bh = max(bh, b:GetHeight())
      row.spelunkerBadge = b
      p.links[#p.links + 1] = b
      bx = bx + b:GetWidth() + SP.s
    end
    -- 0.9.5 phase 4G (spec 01 section 8): a camp Blueprint this dungeon drops for one of your professions; a click opens its Camp tab
    row.blueprintBadges = {}
    for _, bp in ipairs(r.blueprints or {}) do
      local words = "Blueprint: " .. bp.name
      local probe = Kit.StatusChip(holder, "state.warn", words)
      if probe:GetWidth() > x0 + w - bx and bx > nx then
        ly, bx, bh = ly - bh - SP.xs, nx, 0
      end
      probe:Hide()
      local b = chipButton(holder, "state.warn", words, function() AL:OpenCamp(bp.prof) end, words,
        ("%s drops the %s Blueprint for %s (unverified community notes). Opens Professions, %s, Camp."):format(bp.boss or "A boss here", bp.name, bp.prof, bp.prof))
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, ly)
      bx = bx + b:GetWidth() + SP.s
      bh = max(bh, b:GetHeight())
      row.blueprintBadges[#row.blueprintBadges + 1] = b
      p.links[#p.links + 1] = b
    end
    if bh > 0 then ly = ly - bh - SP.xs end
    y = ly - SP.m
    p.rows[#p.rows + 1] = row
  end
  return -(y - y0)
end

-------------------------------------------------------------------------------
-- Upgrades by slot
-------------------------------------------------------------------------------
function Page:DrawGear(p, holder, x0, y0, w, band, d)
  local g = d.grid
  p.gearX, p.gearY, p.gearW = x0, y0, w
  local y, h = header(p, holder, x0, y0, w, "Upgrades by slot", AL.HELP.gear .. (g.weighedFor and ("\n\n" .. g.weighedFor .. ".") or ""), nil)
  p.gearHeader = h
  local hh, hfs = text(holder, x0, y, w, 15, "text.primary", d.gear.head, true, true)
  p.gearHead = hfs
  y = y - hh - SP.xs
  if g.weighedFor then
    -- the engine's header line, the same on every page; it opens the plan it reads
    local b = CreateFrame("Button", nil, holder)
    b.panoplyGapOK = true
    local lw, lh, lfs = word(b, 0, 0, 11, "text.muted", g.weighedFor, w)
    b:SetSize(lw, lh)
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, y)
    Skin.Tooltip(b, g.weighedFor, "Opens the plan these weights come from.")
    b:SetScript("OnEnter", function(self) local c = Kit.Color("text.primary") lfs:SetTextColor(c[1], c[2], c[3], 1) if self.panoplyShowTip then self.panoplyShowTip() end end)
    b:SetScript("OnLeave", function() local c = Kit.Color("text.muted") lfs:SetTextColor(c[1], c[2], c[3], 1) if _G.GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() Panoply.Gear:OpenPlan() end)
    p.weighedLink = b
    y = y - lh - SP.xs
  end
  if d.gear.note then
    local nh = text(holder, x0, y, w, 11, "text.muted", d.gear.note, true)
    y = y - nh - SP.xs
  end
  y = y - SP.s
  if g.noWeights or not g.best then return -(y - y0) end
  -- the grid
  local cells = {}
  local marked = AL.mark and g.byDungeon[AL.mark] or nil
  for _, c in ipairs(g.cells) do
    local v = AL.CellView(c, g.mine)
    if marked and marked[c.key] then v.mark = true end
    cells[#cells + 1] = v
  end
  local grid = Kit.SlotGrid(holder, { onSelect = function(key) AL:SelectSlot(key) end, accent = Kit.ClassColor(d.class) })
  grid:Set(cells)
  grid:Select(AL.slot)
  local cols = band == "narrow" and 2 or (band == "medium" and 4 or Kit.SlotGridColumns(w, 5))
  local gh = grid:Layout(x0, y, w, cols)
  p.grid, p.gridCells = grid, cells
  y = y - gh - SP.m
  -- the open slot: every candidate, best first
  local open
  for _, c in ipairs(g.cells) do if c.key == AL.slot then open = c end end
  p.slotList = nil
  if open then y = y - self:DrawSlotList(p, holder, x0, y, w, open) end
  return -(y - y0)
end

function Page:DrawSlotList(p, holder, x0, y0, w, cell)
  local y = y0
  local n = #cell.list
  local title = n == 0 and cell.label or ("%s: %d %s"):format(cell.label, n, plural(n, "candidate"))
  local hh = text(holder, x0, y, w - 30, 13, "gold.title", title, false, true)
  local close = Skin.IconButton(holder, "Close", 18, function() AL:SelectSlot(cell.key) end, "Close", "Close this list.")
  close:SetPoint("TOPLEFT", holder, "TOPLEFT", x0 + w - 18, y)
  p.slotClose = close
  y = y - max(hh, 18) - SP.s
  local list = { key = cell.key, rows = {} }
  p.slotList = list
  if n == 0 then
    local h = text(holder, x0, y, w, 12, "text.muted", cell.worn and "Nothing in these levels beats what you wear." or "Nothing in these levels for this slot.", true)
    return -(y - h - SP.m - y0)
  end
  for _, c in ipairs(cell.list) do
    local r = { cand = c }
    local ic = holder:CreateTexture(nil, "ARTWORK")
    ic:SetSize(20, 20)
    ic:SetPoint("TOPLEFT", holder, "TOPLEFT", x0, y)
    Panoply.Icons:Apply(ic, itemRef(c))
    if ic.SetTexCoord then ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    r.icon = ic
    local nx = x0 + 20 + SP.s
    local chip = Kit.StatusChip(holder, c.locked and "soon" or "now", c.locked and (c.lockReason or "Later") or Panoply.Gear.DeltaText(c.delta))
    local canGo = AL:CanGoToSource(c.source)
    local room = max(40, x0 + w - nx - chip:GetWidth() - SP.s - (canGo and (Page.BTN + SP.s) or 0))
    local nw, nh, nfs = word(holder, nx, y - 2, 12, "text.primary", AL.ItemName(c), room, true)
    r.name = nfs
    local cx = nx + nw + SP.s
    chip:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y - 2)
    r.chip = chip
    cx = cx + chip:GetWidth() + SP.s
    if canGo then
      local b = iconButton(holder, "Arrow", "icon.ui.arrow", Page.BTN, function() AL:GoToSource(c.source) end, "Point me there",
        "Adds " .. (c.source.kind == "quest" and "whoever gives the quest" or "the dungeon's door") .. " to your waypoints; the arrow follows it.")
      b:SetPoint("TOPLEFT", holder, "TOPLEFT", cx, y)
      r.goBtn = b
    end
    local line = Panoply.Gear.SourceText(c.source)
    local more = #(c.secondarySources or {})
    if more > 0 then line = line .. (", and %d more %s"):format(more, plural(more, "place")) end
    line = line .. (" · Level %d"):format(c.requiredLevel or 0)
    if c.pairedWith then line = line .. (" · with %s"):format(c.pairedWith.name or "an off-hand item") end
    if c.hasEffect then line = line .. " · has an effect that is not scored" end
    local sh, sfs = text(holder, nx, y - max(20, nh + 4), max(40, x0 + w - nx), 11, "text.muted", line, true)
    r.sub = sfs
    y = y - max(20, nh + 4) - sh - SP.s
    list.rows[#list.rows + 1] = r
  end
  return -(y - y0) + SP.xs
end

-------------------------------------------------------------------------------
-- The page follows the gear engine
-------------------------------------------------------------------------------
-- a long gear list the engine has just finished looking through, or items the game has just named: the page shows them
Panoply:Listen("GEAR_CHANGED", function(ctxKey, what)
  if (what == "done" or (what == "changed" and (ctxKey == nil or ctxKey == "player"))) and Menu.current == "atlevel" and Menu.frame and Menu.frame:IsShown() then
    Menu:RefreshCurrent()
  end
end)
