-- Map module, UNEXPLORED FOG (0.8.4): on a zone map, a soft blue-grey patch over every named area you have not explored yet, with a small
-- "?" in its middle that tells you the area's name. OPT-IN: off by default (setting mapFog); how strong the fog is has its own slider.
--
-- What it is, and what it is not:
--   * The game draws an area's own art on the zone map once you have explored it, and says which areas those are
--     (C_MapExplorationInfo.GetExploredMapTextures). The client's tables list EVERY named area of the map and where its art sits
--     (PanoplySuite_QuestData/Maps/Extras.lua, areas: from UiMapXMapArt, WorldMapOverlay and AreaTable, by tools/build_mapextras.py).
--     The areas of the table that the game has not drawn are the ones you have not explored: those get the fog.
--   * It does NOT reveal the hidden art of an unexplored area. That needs the table of the art's file ids, which is not in the data
--     (docs/map/MAP-REDO-SPEC.md, "Reveal"). The fog marks WHERE something is left to discover and what it is called.
--   * When the game will not say what is explored (no such function on this client, or an error), nothing is drawn: the fog never guesses.
-- Rules (Map.lua): our own frames on the map's canvas, never a game function replaced; the fog sits just over the map's own art and under
-- every icon, the route trail and the quest pins. The patch itself takes no clicks (the map under it works as before); only the small "?"
-- does: hover for the name, click to point the arrow at the middle of the area (a waypoint, like every other map icon: nothing moves).
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local max, min = math.max, math.min

local F = {}
M.Fog = F
F.ART_W, F.ART_H = 1002, 668           -- the art canvas of a Classic zone map, when the game does not give the size
F.STRENGTH_MIN, F.STRENGTH_MAX, F.STRENGTH_DEFAULT = 0.2, 0.8, 0.45
F.COLOUR = { 0.36, 0.44, 0.56 }        -- flat blue-grey (skin v3: no glow, no grain)
F.CHIP_PX = 16
F.shown = 0

Panoply.defaults.account.mapFog = false                          -- opt-in
Panoply.defaults.account.mapFogStrength = F.STRENGTH_DEFAULT

local function flavor() return C.IsForever() and "forever" or "era" end

local function isContinent(map)
  local Tr = Panoply.Trail
  return Tr and Tr.IsContinentMap and Tr:IsContinentMap(map) or false
end

-- every named area of a zone map, from the data: { { x, y, w, h, left, right, top, bottom, area, name } ... } in art pixels
function F:Areas(map)
  local X = M.Extras
  local d = X and X.Data()
  self.cache = (self.cacheOf == d) and self.cache or {}
  self.cacheOf = d
  local key = flavor() .. ":" .. tostring(map)
  if self.cache[key] then return self.cache[key] end
  local out = {}
  local rows = d and type(d.areas) == "table" and type(d.areas[flavor()]) == "table" and d.areas[flavor()][map]
  for _, raw in ipairs(type(rows) == "table" and rows or {}) do
    local f = X.Split(tostring(raw))
    local a = { x = tonumber(f[1]), y = tonumber(f[2]), w = tonumber(f[3]), h = tonumber(f[4]), left = tonumber(f[5]), right = tonumber(f[6]),
      top = tonumber(f[7]), bottom = tonumber(f[8]), area = tonumber(f[9]), name = f[10] }
    if a.x and a.y and a.w and a.h and a.left and a.right and a.top and a.bottom and a.right > a.left and a.bottom > a.top
      and type(a.name) == "string" and a.name ~= "" then
      out[#out + 1] = a
    end
  end
  self.cache[key] = out
  return out
end

-- what the game has drawn as explored on a map: a set of "x:y:w:h", or nil when the game will not say
function F:Explored(map)
  local get = C.G("C_MapExplorationInfo.GetExploredMapTextures")
  if type(get) ~= "function" or not map then return nil end
  local ok, list = pcall(get, map)
  if not ok then return nil end
  local set = {}
  if type(list) ~= "table" then return set end          -- nothing explored on this map yet
  for _, t in ipairs(list) do
    if type(t) == "table" then
      local x, y, w, h = C.Readable(t.offsetX), C.Readable(t.offsetY), C.Readable(t.textureWidth), C.Readable(t.textureHeight)
      if not (x and y and w and h) then return nil end   -- a value the game keeps to itself: we do not know, so we draw nothing
      set[x .. ":" .. y .. ":" .. w .. ":" .. h] = true
    end
  end
  return set
end

-- the areas of a map the player has not explored: a list of areas, or nil (and why) when that cannot be known
function F:Unexplored(map)
  if not map or isContinent(map) then return nil, "not a zone map" end
  local areas = self:Areas(map)
  if #areas == 0 then return nil, "no area list for this map" end
  local explored = self:Explored(map)
  if not explored then return nil, "the game does not say what is explored" end
  local out = {}
  for _, a in ipairs(areas) do
    if not explored[a.x .. ":" .. a.y .. ":" .. a.w .. ":" .. a.h] then out[#out + 1] = a end
  end
  return out
end

function F:Strength()
  return M.Num("mapFogStrength", F.STRENGTH_MIN, F.STRENGTH_MAX, F.STRENGTH_DEFAULT)
end

-- the size of the map's art in its own pixels (the area rectangles of the data are in these)
function F:ArtSize(map)
  local get = C.G("C_Map.GetMapArtLayers")
  local layers = get and map and M.pc(get, map)
  local l = type(layers) == "table" and layers[1]
  local w, h = l and tonumber(C.Readable(l.layerWidth)), l and tonumber(C.Readable(l.layerHeight))
  if w and h and w > 0 and h > 0 then return w, h end
  return F.ART_W, F.ART_H
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
local function tipOf(chip)
  local a, GT = chip.area, _G.GameTooltip
  if not (a and GT) then return end
  GT:SetOwner(chip, "ANCHOR_RIGHT")
  GT:SetText(a.name, 1, 0.82, 0.25)
  GT:AddLine("Not explored yet", 0.9, 0.9, 0.9)
  GT:AddLine("Click: point the arrow here", 0.5, 0.85, 1)
  GT:Show()
end

function F:Layer()
  local canvas = C.WorldMapCanvas()
  if not canvas then return nil end
  if not self.layer then
    self.layer = CreateFrame("Frame", nil, canvas)
    self.layer:SetAllPoints(canvas)
    self.layer.panoplyLayoutSkip = true
    self.patches, self.chips = {}, {}
  end
  if self.layer:GetParent() ~= canvas and self.layer.SetParent then self.layer:SetParent(canvas) self.layer:SetAllPoints(canvas) end
  return self.layer, canvas
end

function F:NewChip(parent)
  local b = CreateFrame("Button", nil, parent)
  b.panoplyLayoutSkip = true                    -- placed at the area's map position; two small areas may sit side by side
  b:SetSize(F.CHIP_PX, F.CHIP_PX)
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(Skin.TEX.CircleMask)
  back:SetAllPoints(b)
  local k = Skin.colors.trailInk or { 0.04, 0.05, 0.07 }
  back:SetVertexColor(k[1], k[2], k[3], 0.85)
  b.back = back
  b.mark = Skin.Text(b, 11, Skin.colors.inkSoft)
  b.mark.panoplyLayoutSkip = true
  b.mark:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.mark:SetText("?")
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b:SetScript("OnEnter", tipOf)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self)
    local a = self.area
    if a and self.map then M:PointAt(self.map, a.cx, a.cy, a.name) end
  end)
  return b
end

function F:Refresh(why)
  local used = 0
  local wm, map = C.WorldMap(), C.WorldMapID()
  self.why = nil
  if M.active and Panoply.db and Panoply.db.mapFog and wm and wm.IsShown and wm:IsShown() and map then
    local list, whyNot = self:Unexplored(map)
    self.why = whyNot
    local layer, canvas = self:Layer()
    if list and layer then
      local art = M:ArtLevel() + 1                               -- just over the map's own art
      local top = M:IconLevel()
      if art > top then art = top end
      if layer.SetFrameLevel and layer:GetFrameLevel() ~= art then layer:SetFrameLevel(art) end
      local W, H = canvas:GetWidth() or F.ART_W, canvas:GetHeight() or F.ART_H
      local aw, ah = self:ArtSize(map)
      local sx, sy = W / aw, H / ah
      local Tr = Panoply.Trail
      local cs = Tr and Tr.CanvasScale and Tr:CanvasScale(canvas) or 1
      local chipPx = F.CHIP_PX / max(0.2, cs)
      local strength = self:Strength()
      local c = F.COLOUR
      local chipLevel = M:MarkLevel(top)
      for _, a in ipairs(list) do
        used = used + 1
        local t = self.patches[used]
        if not t then
          t = layer:CreateTexture(nil, "ARTWORK")
          t:SetTexture(Skin.TEX.CircleMask)                      -- a flat soft-cornered patch (an ellipse), no glow
          self.patches[used] = t
        end
        local l, r, tp, b = max(0, a.left), min(aw, a.right), max(0, a.top), min(ah, a.bottom)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", layer, "TOPLEFT", l * sx, -tp * sy)
        t:SetSize(max(4, (r - l) * sx), max(4, (b - tp) * sy))
        t:SetVertexColor(c[1], c[2], c[3], strength)
        t:Show()
        a.cx, a.cy = ((l + r) / 2) / aw, ((tp + b) / 2) / ah
        local chip = self.chips[used]
        if not chip then chip = self:NewChip(layer) self.chips[used] = chip end
        chip.area, chip.map = a, map
        chip:SetSize(chipPx, chipPx)
        chip:ClearAllPoints()
        chip:SetPoint("CENTER", layer, "TOPLEFT", a.cx * W, -a.cy * H)
        if chip.SetFrameLevel then chip:SetFrameLevel(chipLevel) end
        chip:Show()
      end
    end
  end
  for i = used + 1, #(self.patches or {}) do self.patches[i]:Hide() self.chips[i]:Hide() end
  self.shown = used
  return used
end

function F:Disable()
  for i = 1, #(self.patches or {}) do self.patches[i]:Hide() self.chips[i]:Hide() end
  self.shown = 0
end

-- exploring a new area redraws the fog (the game says so with this event, where the client has it)
M:On("MAP_EXPLORATION_UPDATED", function() if Panoply.db and Panoply.db.mapFog then F:Refresh("explored") end end)

M.options[#M.options + 1] = { type = "check", key = "mapFog", label = "Mark unexplored areas",
  tip = "On a zone map, a soft blue-grey patch over every named area you have not explored yet. Hover the \"?\" in its middle for the area's name; click it to point the arrow there. It does not reveal the area's hidden map art. Off unless you turn it on." }
M.options[#M.options + 1] = { type = "slider", key = "mapFogStrength", label = "Fog strength", min = F.STRENGTH_MIN, max = F.STRENGTH_MAX, step = 0.05,
  parent = "mapFog", tip = "How solid the patches over the unexplored areas are." }
for _, k in ipairs({ "mapFog", "mapFogStrength" }) do
  M.KEYS[#M.KEYS + 1] = k
  Panoply.optionHooks[k] = function() if M.active then M:Changed("option") end end
end
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "mapFog", "mapFogStrength" }) end
-- one more tick in the Layers menu on the map, with the info icons (Bar.lua B.LAYERS)
if M.Bar and M.Bar.LAYERS and M.Bar.LAYERS[2] then
  local rows = M.Bar.LAYERS[2].rows
  rows[#rows + 1] = { "mapFog", "Unexplored areas" }
end
