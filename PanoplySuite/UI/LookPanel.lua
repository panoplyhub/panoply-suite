-- Panoply Suite, Step 2 item D: the Look of the map, the front of the Map page's gear (docs/step2/DEF-SPEC.md section D, mockups/step2/D-01 to D-05).
-- Three parts, side by side (the Map gear is as wide as the page: our decision 15):
--   1. a list of the things drawn on a map (Trail, Quest givers, Hand-ins, Objectives, Gathering, Waypoints; Info icons and Connections
--      join with item E): one is lit, a click lights another;
--   2. two columns, World map and Minimap, with the controls of that one thing on that one map: a slider has its name and its value on
--      one line, the bar under it and a small tick where 100% (how it always looked) is; Style is a row of joined buttons; Colour is a row
--      of round swatches with the chosen one ringed and its name at the right of the line. Nothing is shared between the two maps and
--      nothing is multiplied by anything else;
--   3. a live preview under the list: a true-size piece of the world map (108 x 64) and of the minimap (a 56 px circle) with the thing
--      drawn on them as set. It is drawn by the same code the maps use (Panoply.Look.Draw[thing], registered by the Trail, Quest icons,
--      Gathering and Waypoints code), from the same saved numbers, and redrawn while a slider is dragged.
-- Fit (item E, eight things): at 1.3x text on a 1024 x 668 screen the front of the gear is about 298 px high and does not scroll. The list is
-- 8 x 21 px and the preview card is as tall as its text needs. tests/look_tests.lua and tests/connections_tests.lua measure this.
-- The rows are rows of the catalogue (Map > Look of the map: UI/Catalog.lua), so the All settings box finds every control, Reset this page and
-- Undo reach them and a profile holds them; the panel only draws them. Everything here is Panoply Suite's own drawing: no glow.
local ADDON, Panoply = ...
local Skin, Cat, Look, Gear = Panoply.Skin, Panoply.Catalog, Panoply.Look, Panoply.PageSettings
local SP = Skin.SP
local LP = {}
Panoply.LookPanel = LP

LP.LIST_W = 184          -- the list of things (and the live preview under it)
LP.GAP = 14              -- between the list and the columns, and between the two columns
LP.ROW_H = 18            -- one thing in the list (nine things since Places: the list and the preview must fit the gear's view at 1.3x text)
LP.ROW_PITCH = 19
LP.WM_W, LP.WM_H, LP.MM_D = 108, 64, 56     -- the live preview's true-size pieces of the world map and the minimap
LP.SWATCH, LP.SWATCH_PITCH = 24, 28
LP.GROUND = { 0.36, 0.30, 0.19 }            -- the preview's map ground: a plain earth tone (the marks have dark outlines)

-- one plain line each, for the tooltip of a thing in the list (the one-line help of Step 2 B)
LP.THING_HELP = {
  trail = "How your route looks on the maps: dots, dashes or a line, their size and colour.",
  giver = "The ! where a quest can be picked up.",
  turnin = "The ? where a finished quest is handed in.",
  objective = "The markers where a quest's monsters, items and places are.",
  gather = "The herbs, ore veins, fishing pools and chests you found.",
  way = "Your waypoints on the world map.",
  info = "The dungeon and raid doors and the graveyards on the world map.",
  conn = "Zone exits, boats, zeppelins, the tram, portals and flight points on the world map.",
}
local COLUMN = { wm = "WORLD MAP", mm = "MINIMAP" }
local LABEL = { size = "Size", alpha = "Opacity", spacing = "Spacing", style = "Style", colour = "Colour", names = "Names" }
local READ = { size = Look.Size, alpha = Look.Alpha, spacing = Look.Spacing }

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function lineHeight(fs) return Skin.TextHeight(fs, 1000) end

-------------------------------------------------------------------------------
-- A row's first line: its name at the left, its value at the right
-------------------------------------------------------------------------------
local function nameLine(parent, x, y, w, name)
  local n = Skin.Text(parent, 12, Skin.colors.text)
  n:SetText(name)
  if n.SetWordWrap then n:SetWordWrap(false) end
  local v = Skin.Name(parent, 12, Skin.colors.heading)
  if v.SetJustifyH then v:SetJustifyH("RIGHT") end
  if v.SetWordWrap then v:SetWordWrap(false) end
  n:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  v:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y)
  local L = { name = n, value = v, w = w }
  function L.Set(text)
    v:SetText(text)
    local vw = math.ceil(Skin.TextWidth(v)) + 2
    v:SetWidth(vw)
    n:SetWidth(math.max(20, w - vw - SP.s))
  end
  L.Set("")
  L.h = math.max(lineHeight(n), lineHeight(v))
  return L
end

-- a control that is not in use now (Spacing while the Style is a Line) is greyed, and says so; it still works, and its value is kept
local function dim(w, off)
  local a = off and 0.45 or 1
  w:SetAlpha(a)
  w.panoplyDim = off and true or nil
  if w.panoplyLine then w.panoplyLine.name:SetAlpha(a) w.panoplyLine.value:SetAlpha(a) end
end

-- the controls of a row hover like the settings of every gear: the menu fades so the real screen shows while the mouse is on one
local function previewHook(w) if Gear.PreviewHook then Gear.PreviewHook(w) end end

-------------------------------------------------------------------------------
-- Slider
-------------------------------------------------------------------------------
local function slider(parent, x, y, w, row)
  local info = row.look
  local key = row.key
  local read = READ[info.what]
  local L = nameLine(parent, x, y, w, row.label)
  local s = Skin.Slider(parent, row.label, row.min, row.max, row.step,
    function() return read(info.thing, info.map) end,
    function(v) Panoply:SetOption(key, v) end, row.help or row.tip, nil)
  s:SetWidth(w)
  s:ClearAllPoints(); s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - L.h - 2)
  -- Skin's own "Name: value" label is not used here (the name and the value are the two ends of the line above); it stays, hidden,
  -- where the name is, so the row can be outlined
  s.label:ClearAllPoints(); s.label:SetPoint("TOPLEFT", L.name, "TOPLEFT", 0, 0); s.label:SetWidth(w); s.label:Hide()
  s.panoplyLine, s.nameText, s.valueText = L, L.name, L.value
  -- the tick where 100% is
  local tick = s:CreateTexture(nil, "OVERLAY")
  Skin.Solid(tick, Skin.colors.slotLine, 1)
  tick:SetSize(2, 5)
  tick.panoplyLayoutSkip = true
  local frac = (row.default - row.min) / math.max(0.0001, row.max - row.min)
  tick:SetPoint("TOP", s, "BOTTOMLEFT", math.floor(frac * w + 0.5), -1)
  s.tick = tick
  local function showValue(v)
    if s.panoplyOff and s.panoplyOff() then L.Set("not used") else L.Set(pct(v)) end
  end
  s:HookScript("OnValueChanged", function(_, v) showValue(math.floor(v / row.step + 0.5) * row.step) end)
  local base = s.Refresh
  function s:Refresh()
    base(self)
    showValue(read(info.thing, info.map))
    dim(self, self.panoplyOff and self.panoplyOff())
  end
  if info.what == "spacing" then s.panoplyOff = function() return Look.Style(info.thing, info.map) == "line" end end
  s.panoplyKey, s.panoplyRow = key, row
  s:Refresh()
  previewHook(s)
  s.panoplyHeight = L.h + 2 + 16 + 3
  return s, s.panoplyHeight
end

-------------------------------------------------------------------------------
-- Style: joined buttons
-------------------------------------------------------------------------------
local function choice(parent, x, y, w, row)
  local info = row.look
  local key = row.key
  local L = nameLine(parent, x, y, w, row.label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - L.h - 2)
  f:SetWidth(w)
  f.buttons = {}
  for _, v in ipairs(row.values) do
    local b = Skin.Button(f, v[2], 60, 24, function() Panoply:SetOption(key, v[1]) end, row.label, row.help or row.tip)
    b.value = v[1]
    b.panoplyKey, b.panoplyRow = key, row
    previewHook(b)
    f.buttons[#f.buttons + 1] = b
  end
  local bh = Skin.FlowButtons(f, f.buttons, 0, 0, w, 2, 48)
  f:SetHeight(bh)
  f.panoplyLine, f.panoplyKey, f.panoplyRow = L, key, row
  function f:Refresh()
    local cur
    if info.what == "names" then cur = Look.Names(info.thing, info.map)
    elseif info.thing == "gather" then cur = Look.Style("gather", "mm") == "ring" else cur = Look.Style(info.thing, info.map) end
    local name = ""
    for _, b in ipairs(self.buttons) do
      local on = b.value == cur
      b:SetSelected(on)
      local c = on and Skin.colors.heading or Skin.colors.text
      b.label:SetTextColor(c[1], c[2], c[3], 1)
      if on then for _, v in ipairs(row.values) do if v[1] == b.value then name = v[2] end end end
    end
    L.Set(name)
  end
  f:Refresh()
  f.panoplyHeight = L.h + 2 + bh
  return f, f.panoplyHeight
end

-------------------------------------------------------------------------------
-- Colour: round swatches
-------------------------------------------------------------------------------
-- the quest pin a swatch shows for "Panoply Suite" and the game's own icon for "Blizzard default"
local PIN_KIND = { giver = "give", turnin = "turnin", objective = "obj" }
local QUARTERS = { { "trailWalk", 0, 0 }, { "trailShip", 0.5, 0 }, { "trailTram", 0, 0.5 }, { "trailFly", 0.5, 0.5 } }   -- By type: four of the trail's colours

local function paintSwatch(b, thing, e)
  local rgb = Look.EntryRGB(e)
  local inner = LP.SWATCH - 6
  if rgb then
    b.disc:SetTexture(Skin.TEX.CircleMask)
    b.disc:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
    b.disc:Show()
  elseif e.id == "type" then
    b.disc:Hide()
    b.quarters = b.quarters or {}
    for i, q in ipairs(QUARTERS) do
      local t = b.quarters[i]
      if not t then
        t = b:CreateTexture(nil, "ARTWORK")
        t:SetTexture(Skin.TEX.CircleMask)
        t:SetSize(inner / 2, inner / 2)
        t:SetTexCoord(q[2], q[2] + 0.5, q[3], q[3] + 0.5)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", 3 + (q[2] > 0 and inner / 2 or 0), -(3 + (q[3] > 0 and inner / 2 or 0)))
        b.quarters[i] = t
      end
      local c = Skin.colors[q[1]]
      t:SetVertexColor(c[1], c[2], c[3], 1)
    end
  else
    -- art: Panoply Suite's own pin, the waypoint pin, or the game's own quest icon
    b.disc:Hide()
    local path
    local QP = Panoply.QuestPins
    if e.id == "panoply" and QP then path = QP.TEX[PIN_KIND[thing] or "give"]
    elseif e.id == "blizzard" and QP then path = QP:GameArt(PIN_KIND[thing] or "give")
    elseif e.id == "standard" then path = Skin.TEX.PinTrail end
    b.art = b.art or b:CreateTexture(nil, "ARTWORK")
    b.art:SetSize(inner, inner)
    b.art:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.art:SetTexture(path)
    b.art:Show()
  end
end

local function swatches(parent, x, y, w, row)
  local info = row.look
  local key = row.key
  local thing = info.thing
  local L = nameLine(parent, x, y, w, row.label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - L.h - 2)
  f:SetSize(w, LP.SWATCH)
  f.buttons, f.pool = {}, {}
  f.panoplyLine, f.panoplyKey, f.panoplyRow = L, key, row
  -- the choices offered in this client (Blizzard default is left out where the game has no such icon); built again when that changes
  function f:Build()
    local offered = Look.Offered(thing)
    local sig = {}
    for _, e in ipairs(offered) do sig[#sig + 1] = e.id end
    sig = table.concat(sig, ",")
    if sig == self.sig then return end
    self.sig = sig
    for _, b in ipairs(self.pool) do b:Hide() end
    self.buttons = {}
    for i, e in ipairs(offered) do
      local b = self.pool[i]
      if not b then
        b = CreateFrame("Button", nil, self)
        b:SetSize(LP.SWATCH, LP.SWATCH)
        -- a ring (brass when chosen), a dark pad inside it, and the colour or the art on the pad
        b.ring = b:CreateTexture(nil, "BACKGROUND"); b.ring:SetTexture(Skin.TEX.CircleMask); b.ring:SetAllPoints(b)
        b.pad = b:CreateTexture(nil, "BORDER"); b.pad:SetTexture(Skin.TEX.CircleMask)
        b.pad:SetSize(LP.SWATCH - 4, LP.SWATCH - 4); b.pad:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.disc = b:CreateTexture(nil, "ARTWORK"); b.disc:SetTexture(Skin.TEX.CircleMask)
        b.disc:SetSize(LP.SWATCH - 6, LP.SWATCH - 6); b.disc:SetPoint("CENTER", b, "CENTER", 0, 0)
        self.pool[i] = b
      end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * LP.SWATCH_PITCH, 0)
      b.value, b.panoplyKey, b.panoplyRow, b.entry = e.id, key, row, e
      if b.art then b.art:Hide() end
      if b.quarters then for _, t in ipairs(b.quarters) do t:Hide() end end
      paintSwatch(b, thing, e)
      if b.quarters and e.id == "type" then for _, t in ipairs(b.quarters) do t:Show() end end
      Skin.Tooltip(b, e.name, row.help or row.tip)
      b:SetScript("OnEnter", function() if b.panoplyShowTip then b.panoplyShowTip() end Gear:Preview(true) end)
      b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end Gear:Preview(false) end)
      b:SetScript("OnClick", function() Panoply:SetOption(key, e.id) end)
      b:Show()
      self.buttons[#self.buttons + 1] = b
    end
  end
  function f:Refresh()
    self:Build()
    local cur = Look.Colour(thing, info.map)
    local name = ""
    for _, b in ipairs(self.buttons) do
      local on = b.value == cur
      b.selected = on and true or nil
      local c = on and Skin.colors.heading or Skin.colors.slotLine
      b.ring:SetVertexColor(c[1], c[2], c[3], 1)
      local p = Skin.colors.panel
      b.pad:SetVertexColor(p[1], p[2], p[3], 1)
      if on then name = b.entry.name end
    end
    L.Set(name)
  end
  f:Refresh()
  f.panoplyHeight = L.h + 2 + LP.SWATCH
  return f, f.panoplyHeight
end

local BUILD = { slider = slider, segmented = function(parent, x, y, w, row) if row.swatches then return swatches(parent, x, y, w, row) end return choice(parent, x, y, w, row) end }

-------------------------------------------------------------------------------
-- The live preview: a card under the list with a true-size piece of each map
-------------------------------------------------------------------------------
local function previewCard(parent, x, y)
  local card = Skin.Card(parent)
  card:SetSize(LP.LIST_W, 100)
  card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local title = Skin.Label(card, 10, Skin.colors.gold)
  title:SetText("LIVE PREVIEW")
  title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -6)
  title:SetWidth(LP.LIST_W - 20)
  local top = 6 + lineHeight(title) + 3
  local C = { frame = card, title = title, layers = {} }
  -- the world map: a rounded piece of ground
  local wm = CreateFrame("Frame", nil, card)
  wm:SetSize(LP.WM_W, LP.WM_H)
  wm:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -top)
  Skin.Box(wm, "S", { fill = LP.GROUND, fillA = 1, line = Skin.colors.hairline })
  if wm.SetClipsChildren then wm:SetClipsChildren(true) end
  wm.panoplyLayoutSkip = true
  -- the minimap: a round piece of ground in a brass ring
  local mm = CreateFrame("Frame", nil, card)
  mm:SetSize(LP.MM_D, LP.MM_D)
  mm:SetPoint("TOPLEFT", card, "TOPLEFT", 8 + LP.WM_W + 6, -top - (LP.WM_H - LP.MM_D) / 2)
  local ring = mm:CreateTexture(nil, "BACKGROUND", nil, -1)
  ring:SetTexture(Skin.TEX.CircleMask); ring:SetVertexColor(Skin.colors.goldDark[1], Skin.colors.goldDark[2], Skin.colors.goldDark[3], 1)
  ring:SetPoint("TOPLEFT", mm, "TOPLEFT", -2, 2); ring:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 2, -2)
  local ground = mm:CreateTexture(nil, "BACKGROUND")
  ground:SetTexture(Skin.TEX.CircleMask); ground:SetVertexColor(LP.GROUND[1], LP.GROUND[2], LP.GROUND[3], 1); ground:SetAllPoints(mm)
  if mm.SetClipsChildren then mm:SetClipsChildren(true) end
  mm.panoplyLayoutSkip = true
  -- "Not drawn" in the round piece of a thing that is not on the minimap
  local none = Skin.Text(mm, 10.5, Skin.colors.inkSoft)        -- a child of the round piece, so it is drawn over the ground
  none:SetText("Not drawn")
  none:SetWidth(LP.MM_D - 8)
  if none.SetJustifyH then none:SetJustifyH("CENTER") end
  none:SetPoint("CENTER", mm, "CENTER", 0, 0)
  none:Hide()
  local capY = top + LP.WM_H + 3
  local c1 = Skin.Text(card, 11, Skin.colors.inkSoft); c1:SetText("World map"); c1:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -capY); c1:SetWidth(LP.WM_W)
  local c2 = Skin.Text(card, 11, Skin.colors.inkSoft); c2:SetText("Minimap")
  c2:SetWidth(LP.MM_D + 6); if c2.SetJustifyH then c2:SetJustifyH("CENTER") end
  c2:SetPoint("TOPLEFT", card, "TOPLEFT", 8 + LP.WM_W + 6 - 3, -capY)
  C.wm, C.mm, C.none, C.c1, C.c2 = wm, mm, none, c1, c2
  -- as tall as its text needs (the captions are the last thing in it)
  C.height = math.ceil(capY + math.max(lineHeight(c1), lineHeight(c2)) + 6)
  card:SetHeight(C.height)
  return C
end

-- one layer of marks for one thing on one map (made once; the thing's drawer fills it)
local function layerFor(C, thing, map)
  local k = thing .. ":" .. map
  local l = C.layers[k]
  if not l then
    local patch = map == "wm" and C.wm or C.mm
    l = CreateFrame("Frame", nil, patch)
    l:SetAllPoints(patch)
    l:SetSize(map == "wm" and LP.WM_W or LP.MM_D, map == "wm" and LP.WM_H or LP.MM_D)
    l.panoplyLayoutSkip = true
    C.layers[k] = l
  end
  return l
end

-------------------------------------------------------------------------------
-- The panel
-------------------------------------------------------------------------------
local Panel = {}
Panel.__index = Panel

-- the things the list shows: the ones whose module is in this build and switched on
function Panel:Visible()
  local out = {}
  for _, t in ipairs(Look.THINGS) do if Look.Here(t.id) then out[#out + 1] = t.id end end
  return out
end

function Panel:LayoutList()
  local vis = self:Visible()
  local shown = {}
  for i, id in ipairs(vis) do
    shown[id] = true
    local b = self.buttons[id]
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", self.left, "TOPLEFT", 0, -(i - 1) * LP.ROW_PITCH)
    b:Show()
    b:SetSelected(id == self.cur)
    local c = (id == self.cur and Skin.colors.heading) or Skin.colors.text
    b.label:SetTextColor(c[1], c[2], c[3], 1)
  end
  for id, b in pairs(self.buttons) do if not shown[id] then b:Hide() end end
  self.listH = #vis * LP.ROW_PITCH
  self.preview.frame:ClearAllPoints()
  self.preview.frame:SetPoint("TOPLEFT", self.left, "TOPLEFT", 0, -(self.listH + SP.s))
  self.visible = vis
end

-- the controls of one thing: both columns, built the first time the thing is shown
function Panel:Thing(id)
  local T = self.things[id]
  if T then return T end
  T = { id = id, made = {}, byKey = {} }
  self.things[id] = T
  local holder = CreateFrame("Frame", nil, self.right)
  holder:SetWidth(self.rightW)
  holder:Hide()
  T.holder = holder
  local def = Look.BY_ID[id]
  local tallest = 0
  for i, m in ipairs({ "wm", "mm" }) do
    local x = (i - 1) * (self.colW + LP.GAP)
    local head = Skin.Label(holder, 10, Skin.colors.gold)
    head:SetText(COLUMN[m])
    head:SetWidth(self.colW)
    head:SetPoint("TOPLEFT", holder, "TOPLEFT", x, 0)
    local hh = lineHeight(head)
    local rule = holder:CreateTexture(nil, "ARTWORK")
    Skin.Solid(rule, Skin.colors.hairline, 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -(hh + 3)); rule:SetPoint("TOPRIGHT", holder, "TOPLEFT", x + self.colW, -(hh + 3))
    rule.panoplyLayoutSkip = true
    local y = -(hh + 3 + SP.xs)
    local controls = Look.CONTROLS[id][m]
    if controls then
      for _, what in ipairs(controls) do
        local row = Cat:Row({ Look.Key(id, m, what), LABEL[what] })
        if row then
          local w, h = BUILD[row.type](holder, x, y, self.colW, row)
          w.panoplyRowY = self.top - y - 4        -- from the top of the front, so a search result can scroll to it
          T.made[#T.made + 1] = w
          T.byKey[row.key] = w
          y = y - h - 2
        end
      end
    else
      -- the thing is not drawn on this map: the column says so instead of showing controls that do nothing
      local note = Skin.Card(holder)
      note:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
      local txt = Skin.Ink(note, 12, Skin.colors.inkSoft)
      txt:SetText(("Panoply Suite does not draw %s on the %s."):format(Look.SHORT[id]:lower(), m == "mm" and "minimap" or "world map"))
      txt:SetWidth(self.colW - 24)
      txt:SetPoint("TOPLEFT", note, "TOPLEFT", 12, -10)
      local th = Skin.TextHeight(txt, self.colW - 24)
      note:SetSize(self.colW, th + 20)
      T.note = note
      y = y - th - 20
    end
    tallest = math.max(tallest, -y)
  end
  T.height = tallest
  holder:SetHeight(tallest)
  return T
end

function Panel:Select(id)
  local vis = self:Visible()
  local ok = false
  for _, v in ipairs(vis) do if v == id then ok = true end end
  if not ok then id = vis[1] end
  if not id then return end
  self.cur = id
  LP.last = id
  for tid, T in pairs(self.things) do T.holder:Hide() end
  local T = self:Thing(id)
  T.holder:Show()
  self:Refresh()
end

-- the More settings button's place at the foot of the columns, and the thing's columns
function Panel:Note()
  local b = self.moreBtn
  if b then b:SetWidth(self.rightW) b:ClearAllPoints() b:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", self.rightX, 0) end
  local T = self.things[self.cur]
  if T then
    T.holder:ClearAllPoints(); T.holder:SetPoint("TOPLEFT", self.right, "TOPLEFT", 0, 0)
    T.holder:SetAlpha(1)
  end
end

function Panel:DrawPreview()
  local id = self.cur
  local C = self.preview
  local def = id and Look.BY_ID[id]
  if not def then return end
  for k, l in pairs(C.layers) do l:Hide() end
  local draw = Look.Draw[id]
  for _, m in ipairs({ "wm", "mm" }) do
    local drawn = Look.CONTROLS[id][m] ~= nil
    if m == "mm" then if drawn then C.none:Hide() else C.none:Show() end end
    if drawn and draw then
      local layer = layerFor(C, id, m)
      layer:Show()
      draw(layer, m)
    end
  end
end

-- the panel's height: the list and the preview at the left, the columns and the foot (the More settings button) at the right
function Panel:Relayout()
  local T = self.things[self.cur]
  self.rightMax = math.max(self.rightMax or 0, T and T.height or 0)
  local foot = self.moreBtn and self.moreBtn:GetHeight() or 0
  local right = self.rightMax + (foot > 0 and (SP.s + foot) or 0)
  local left = self.listH + SP.s + self.preview.height
  local h = math.ceil(math.max(left, right))
  if math.abs(h - (self.height or 0)) > 0.5 then
    self.height = h
    self.frame:SetHeight(h)
    if self.onResize then self.onResize() end
  end
end

function Panel:Refresh()
  self:LayoutList()
  if not (self.cur and self.buttons[self.cur] and self.buttons[self.cur]:IsShown()) then
    local first = self.visible[1]
    if first and first ~= self.cur then self:Select(first) return end
  end
  local T = self:Thing(self.cur)
  for _, w in ipairs(T.made) do if w.Refresh then w:Refresh() end end
  self:Note()
  self:DrawPreview()
  self:Relayout()
end

-- the widget of a setting of the Look of the map (built when asked for; not shown unless its thing is)
function Panel:Widget(key)
  local info = Look.KeyInfo(key)
  if not (info and Look.Here(info.thing)) then return nil end
  return self:Thing(info.thing).byKey[key]
end

-- show the thing a setting belongs to (a search result, a link)
function Panel:Reveal(key)
  local info = Look.KeyInfo(key)
  if info and Look.Here(info.thing) and info.thing ~= self.cur then self:Select(info.thing) end
end

-- every widget of every thing the list shows (built if need be): for the tests and the layout checks
function Panel:All()
  local out = {}
  for _, id in ipairs(self:Visible()) do
    for _, w in ipairs(self:Thing(id).made) do out[#out + 1] = w end
  end
  return out
end

-- The More settings button sits at the foot of the right side, under the columns
function Panel:PlaceMore(b)
  self.moreBtn = b
  Skin.FitButton(b, self.rightW, self.rightW)
  b:SetWidth(self.rightW)
  self:Note()
  self:Relayout()
end

function LP.Build(parent, W, y, page)
  local P = setmetatable({ W = W, things = {}, buttons = {}, top = -y }, Panel)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
  f:SetSize(W, 100)
  P.frame = f
  -- the list at the left
  local left = CreateFrame("Frame", nil, f)
  left:SetPoint("TOPLEFT", f, "TOPLEFT", 4, 0)
  left:SetSize(LP.LIST_W, 100)
  P.left = left
  for _, t in ipairs(Look.THINGS) do
    local id = t.id
    local b = Skin.Button(left, Look.SHORT[id] or t.name, LP.LIST_W, LP.ROW_H, function() P:Select(id) end, Look.SHORT[id] or t.name,
      LP.THING_HELP[id] or ("How " .. t.name:lower() .. " look on the maps."))
    b:SetWidth(LP.LIST_W)
    b.label:ClearAllPoints(); b.label:SetPoint("LEFT", b, "LEFT", 12, 0)
    if b.label.SetJustifyH then b.label:SetJustifyH("LEFT") end
    b.label:SetWidth(LP.LIST_W - 20)
    b.panoplyThing = id
    P.buttons[id] = b
  end
  P.preview = previewCard(left, 0, 0)
  -- the columns at the right
  P.rightX = 4 + LP.LIST_W + LP.GAP
  P.rightW = W - P.rightX - 4
  P.colW = math.floor((P.rightW - LP.GAP) / 2)
  local right = CreateFrame("Frame", nil, f)
  right:SetPoint("TOPLEFT", f, "TOPLEFT", P.rightX, 0)
  right:SetSize(P.rightW, 100)
  P.right = right
  P.listH = 0
  P:LayoutList()
  -- the trail is the busiest thing: build it first, and the panel is as tall as it needs from the start whichever thing opens first
  if Look.Here("trail") then P.rightMax = P:Thing("trail").height end
  local first = P.visible[1]
  local want = LP.last
  local ok = false
  for _, v in ipairs(P.visible) do if v == want then ok = true end end
  P:Select(ok and want or first)
  return P
end

Gear.PANELS.look = LP

-- a profile holds the new keys (the sizes and opacities were already in its list)
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys(Look.ExtraKeys()) end
