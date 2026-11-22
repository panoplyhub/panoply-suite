-- Panoply Suite 0.9.5, phase 4D: the slot grid (docs/specs/page-redesigns-v1.md 4.3), a shared component of the visual system
-- (UI/KitParts.lua). At Your Level builds it first; Auctions (Upgrades), Muster (Gear) and the Class page's Gear tab reuse it.
-- It draws what it is given and ranks nothing: the pages hand it the gear engine's answer (Panoply.Gear) as cells.
--
--   local g = Kit.SlotGrid(parent, { onSelect = function(key, cell) end })
--   g:Set(cells)         cells in paper-doll order, each:
--                          key          the engine's slot key ("head", "finger", "mainhand", ...)
--                          label        "Head"
--                          icon         the worn item's picture (a path or a file id); nil with empty = true: the empty-slot picture
--                                       (icon slot icon.slot.<key>)
--                          item         (0.9.7 hotfix) the worn item's id or link: with it the picture comes through Panoply.Icons
--                                       (Core/CompatModules.lua), so the game's "?" is painted over when the game sends the item.
--                                       over.item is the same for the upgrade's small picture.
--                          quality      the worn item's quality (the icon's border colour when there is no upgrade)
--                          state        "up" (an upgrade to wear now: full colour), "locked" (only for a later level: lock badge),
--                                       "none" (nothing better: desaturated)
--                          over         { icon, quality } the best upgrade, drawn over the worn item's corner
--                          value        the cell's second line: "+14", "At 17" (empty for "none")
--                          tip, tipBody the tooltip (worn against the upgrade)
--                          mark         true: drawn with the page's accent stripe (opts.accent) (a page points at these cells, "3 upgrades for you")
--   g:Select(key)        the expanded cell (drawn on surface.2); nil = none
--   g:Layout(x, y, w, cols) places the tiles cols wide at (x, y) of the parent, w wide; returns the height (again at any width)
--   g:Hide()             hides every tile (a page that draws its grid again elsewhere)
--
-- Item quality is the icon's border colour (the game's own colours). No glow, no card borders: a tile is the icon and two lines of
-- text, with a surface only under the hovered, selected or marked one.
local ADDON, Panoply = ...
local Skin, Kit, C = Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TW = Skin.SP, Skin.TextWidth
local floor, max, min = math.floor, math.max, math.min

Kit.SLOT_TILE = { icon = 36, h = 42, gap = 8, minW = 140 }

-- the paper doll's empty-slot pictures (the game's own), one icon slot each
local PD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
Kit.SLOT_ART = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Chest", chest = "Chest", wrist = "Wrists", hands = "Hands",
  waist = "Waist", legs = "Legs", feet = "Feet", finger = "Finger", trinket = "Trinket", mainhand = "MainHand", offhand = "SecondaryHand",
  ranged = "Ranged" }
for key, art in pairs(Kit.SLOT_ART) do
  Kit.RegisterIcon("icon.slot." .. key, { game = { PD .. art, "Interface\\Icons\\INV_Misc_QuestionMark" }, raw = true })
end

-- the colour of an item quality ({ r, g, b }): the game's own table when it has one
function Kit.QualityColor(q)
  q = tonumber(q) or 1
  local t = _G.ITEM_QUALITY_COLORS
  local c = type(t) == "table" and t[q]
  if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
  return C.QUALITY[q] or C.QUALITY[1]
end

-- how many tiles fit across w (at least 1)
function Kit.SlotGridColumns(w, most)
  local T = Kit.SLOT_TILE
  local n = floor((w + T.gap) / (T.minW + T.gap))
  return max(1, min(most or 8, n))
end

local function tile(grid)
  local parent = grid.parent
  local T = Kit.SLOT_TILE
  local t = CreateFrame("Button", nil, parent)
  t:SetHeight(T.h)
  t.panoplyKit, t.panoplyGapOK = "SlotTile", true
  -- the hovered, selected or marked tile's surface: textures of the tile itself (not a card of its own over its words), and the
  -- accent stripe down its left edge when it is marked
  local bg = t:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(t)
  Skin.Round(bg, Skin.RADIUS.card, Skin.TEX.RFill)
  bg:Hide()
  t.bg = bg
  local stripe = t:CreateTexture(nil, "BORDER")
  stripe:SetWidth(2)
  stripe:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -Skin.RADIUS.card)
  stripe:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, Skin.RADIUS.card)
  Skin.Solid(stripe, grid.accent, 1)
  stripe:Hide()
  t.stripe = stripe
  local cell = Kit.IconCell(t, { size = T.icon })
  cell:SetPoint("TOPLEFT", t, "TOPLEFT", 3, -3)
  -- the tile answers the mouse, not the icon inside it
  if cell.EnableMouse then cell:EnableMouse(false) end
  t.cell = cell
  local over = cell:CreateTexture(nil, "OVERLAY", nil, 6)
  over:SetSize(18, 18)
  over:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 4, 4)
  if over.SetTexCoord then over:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  over:Hide()
  t.over = over
  -- the upgrade's quality as a 1 px edge round its small picture
  t.overEdge = {}
  for i = 1, 4 do
    local e = cell:CreateTexture(nil, "OVERLAY", nil, 5)
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    e:Hide()
    t.overEdge[i] = e
  end
  local e = t.overEdge
  e[1]:SetPoint("BOTTOMLEFT", over, "TOPLEFT", -1, 0); e[1]:SetPoint("BOTTOMRIGHT", over, "TOPRIGHT", 1, 0)
  e[2]:SetPoint("TOPLEFT", over, "BOTTOMLEFT", -1, 0); e[2]:SetPoint("TOPRIGHT", over, "BOTTOMRIGHT", 1, 0)
  e[3]:SetPoint("TOPRIGHT", over, "TOPLEFT", 0, 0); e[3]:SetPoint("BOTTOMRIGHT", over, "BOTTOMLEFT", 0, 0)
  e[4]:SetPoint("TOPLEFT", over, "TOPRIGHT", 0, 0); e[4]:SetPoint("BOTTOMLEFT", over, "BOTTOMRIGHT", 0, 0)
  t.label = Skin.Ink(t, 11, Kit.Color("text.muted"))
  t.value = Skin.Name(t, 12, Kit.Color("text.primary"))
  for _, fs in ipairs({ t.label, t.value }) do
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  end
  Skin.Tooltip(t, "", nil)
  local function paint()
    local on = t.hover or t.selected or t.marked
    if on then
      local c = Kit.Color((t.selected or t.hover) and "surface.2" or "surface.1")
      bg:SetVertexColor(c[1], c[2], c[3], 1)
      bg:Show()
    else bg:Hide() end
    if t.marked then stripe:Show() else stripe:Hide() end
  end
  t.Paint = paint
  t:SetScript("OnEnter", function(self) self.hover = true paint() if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
  t:SetScript("OnLeave", function(self) self.hover = false paint() if _G.GameTooltip then GameTooltip:Hide() end end)
  t:SetScript("OnClick", function(self) if grid.onSelect and self.data then grid.onSelect(self.data.key, self.data) end end)
  return t
end

local function fill(t, d)
  t.data = d
  local cell = t.cell
  local state = d.state == "up" and "progress" or (d.state == "locked" and "locked" or "todo")
  cell:SetState(state, { progress = 1 })
  local I = Panoply.Icons
  if d.item then I:Apply(cell, d.item, d.icon) cell.panoplySlot = nil
  elseif d.icon then I:Release(cell) cell:SetTexture(d.icon) cell.panoplySlot = nil
  else I:Release(cell) cell:SetSlot("icon.slot." .. tostring(d.key)) end
  -- the border: the upgrade's quality on a cell with one, else what is worn
  local q = (d.over and d.state ~= "none") and d.over.quality or d.quality
  if q and (d.icon or d.item or d.over) then cell:SetRing(1, Kit.QualityColor(q)) else cell:SetRing(0) end
  cell.panoplyQuality = q
  if d.over and (d.over.icon or d.over.item) and d.state ~= "none" then
    if d.over.item then I:Apply(t.over, d.over.item, d.over.icon) else I:Release(t.over) t.over:SetTexture(d.over.icon) end
    if t.over.SetDesaturated then t.over:SetDesaturated(d.state == "locked") end
    t.over:Show()
    local qc = Kit.QualityColor(d.over.quality)
    for _, e in ipairs(t.overEdge) do Skin.Solid(e, qc, 1) e:Show() end
  else
    t.over:Hide()
    for _, e in ipairs(t.overEdge) do e:Hide() end
  end
  t.panoplyOverIcon = t.over:IsShown() and (d.over.icon or I.UNKNOWN) or nil
  -- (the whole words are kept: Layout shortens them to the width it has, every time from the whole words)
  t.label.panoplyFull, t.value.panoplyFull = d.label or "", d.value or ""
  t.label:SetText(t.label.panoplyFull)
  t.value:SetText(t.value.panoplyFull)
  local tok = d.state == "up" and "state.good" or (d.state == "locked" and "text.primary" or "text.muted")
  local c = Kit.Color(tok)
  t.value:SetTextColor(c[1], c[2], c[3], 1)
  t.tip, t.tipBody = d.tip or d.label, d.tipBody
  t.marked = d.mark and true or false
  t:Paint()
end

function Kit.SlotGrid(parent, opts)
  opts = opts or {}
  -- opts.accent: the page's accent (spec 1.1), the stripe down a marked tile
  local g = { parent = parent, onSelect = opts.onSelect, tiles = {}, cells = {}, panoplyKit = "SlotGrid", accent = Kit.Accent(opts.accent or "professions") }
  function g:Hide() for _, t in ipairs(self.tiles) do t:Hide() end end
  function g:Set(cells)
    self.cells = cells or {}
    for i, d in ipairs(self.cells) do
      local t = self.tiles[i] or tile(self)
      self.tiles[i] = t
      fill(t, d)
      t.selected = (self.selected ~= nil and d.key == self.selected)
      t:Paint()
    end
    for i = #self.cells + 1, #self.tiles do self.tiles[i]:Hide() end
  end
  function g:Select(key)
    self.selected = key
    for i, t in ipairs(self.tiles) do
      if i <= #self.cells then t.selected = key ~= nil and t.data.key == key t:Paint() end
    end
  end
  function g:Tile(key)
    for i, t in ipairs(self.tiles) do if i <= #self.cells and t.data.key == key then return t end end
  end
  function g:Layout(x, y, w, cols)
    local T = Kit.SLOT_TILE
    cols = max(1, cols or Kit.SlotGridColumns(w))
    local tw = floor((w - (cols - 1) * T.gap) / cols)
    local tx = T.icon + 3 + 4 + SP.s       -- (clear of the upgrade's small picture over the icon's corner)
    local textW = max(10, tw - tx - 2)
    local rows = 0
    for i, t in ipairs(self.tiles) do
      if i <= #self.cells then
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        rows = row + 1
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x + col * (tw + T.gap), y - row * (T.h + T.gap))
        t:SetWidth(tw)
        t.label:ClearAllPoints(); t.label:SetPoint("TOPLEFT", t, "TOPLEFT", tx, -5)
        t.value:ClearAllPoints(); t.value:SetPoint("TOPLEFT", t, "TOPLEFT", tx, -21)
        for _, fs in ipairs({ t.label, t.value }) do
          fs:SetWidth(textW)
          local s = fs.panoplyFull or fs:GetText() or ""
          fs:SetText(s)
          if TW(fs) > textW then Skin.Ellipsize(fs, s, textW) end
          fs:SetHeight(15)
        end
        t:Show()
      end
    end
    self.cols, self.tileW = cols, tw
    return rows > 0 and (rows * T.h + (rows - 1) * T.gap) or 0
  end
  return g
end
