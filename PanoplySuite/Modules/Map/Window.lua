-- Map module, the game's map window: follow my zone, dim the map, move / size / reset.
-- Everything is a plain method call on the window (SetScale, SetAlpha, SetPoint, SetMapID) made from
-- our own code, never inside a game function, never in combat, and each only when the player has
-- changed the matching setting (the defaults leave the game's window exactly as the game draws it).
local ADDON, Panoply = ...
local C, M, Skin = Panoply.Compat, Panoply.Map, Panoply.Skin
local pcallv = M.pc

local Wn = {}
M.Window = Wn

function Wn:Mode()
  local wm = C.WorldMap()
  local maxed = wm and wm.IsMaximized and pcallv(wm.IsMaximized, wm)
  return maxed and "max" or "win"
end

local function readPoints(f)
  local out = {}
  local n = f.GetNumPoints and pcallv(f.GetNumPoints, f) or 1
  for i = 1, math.min(n or 1, 6) do
    local p, rel, rp, x, y = pcallv(f.GetPoint, f, i)
    if p then
      local relName = rel and rel.GetName and rel:GetName() or nil
      out[#out + 1] = { p, relName or "UIParent", rp, x or 0, y or 0 }
    end
  end
  return out
end

local function setPoints(f, list)
  if not (f.ClearAllPoints and f.SetPoint and list and #list > 0) then return false end
  f:ClearAllPoints()
  for _, p in ipairs(list) do
    local rel = _G[p[2]] or _G.UIParent
    f:SetPoint(p[1], rel, p[3], p[4], p[5])
  end
  return true
end

-------------------------------------------------------------------------------
-- Size, dimmer, position
-------------------------------------------------------------------------------
function Wn:ApplyScale()
  local wm = C.WorldMap()
  if not (wm and wm.SetScale) then return end
  local s = M.Num("mapScale", M.SCALE_MIN, M.SCALE_MAX, 1)
  if M:Wants("scale") and math.abs(s - 1) > 0.001 then
    M:Later("mapScale", function()
      if wm.GetScale and math.abs((wm:GetScale() or 1) - s) < 0.0005 then return end
      wm:SetScale(s)
      Wn.scaled = true
    end)
  elseif self.scaled then
    M:Later("mapScale", function() wm:SetScale(1) Wn.scaled = nil end)
  end
end

-- The dimmer: one flat dark wash over the map's own picture (above the explored art, under every pin
-- of ours and the route). The game's window and its opacity are not touched, so the trail and the pins
-- keep full strength however dark the map is.
function Wn:ApplyDim()
  local canvas = C.WorldMapCanvas()
  local wm = C.WorldMap()
  local v = M.Num("mapDim", 0, M.DIM_MAX, 0)
  if not (canvas and wm and wm.IsShown and wm:IsShown() and M.active and v > 0.001) then
    if self.wash then self.wash:Hide() end
    self.dimShown = 0
    return
  end
  if not self.wash then
    self.wash = CreateFrame("Frame", nil, canvas)
    self.wash:SetAllPoints(canvas)
    self.wash.panoplyLayoutSkip = true
    self.wash.tex = self.wash:CreateTexture(nil, "BACKGROUND")
    self.wash.tex:SetAllPoints(self.wash)
    self.wash.tex:SetTexture(Skin and Skin.WHITE or "Interface\\Buttons\\WHITE8X8")
  end
  if self.wash:GetParent() ~= canvas and self.wash.SetParent then self.wash:SetParent(canvas) self.wash:SetAllPoints(canvas) end
  local lvl = M:ArtLevel() + 1
  if self.wash:GetFrameLevel() ~= lvl then self.wash:SetFrameLevel(lvl) end
  self.wash.tex:SetVertexColor(0, 0, 0, v)
  self.wash:Show()
  self.dimShown = v
end

function Wn:ApplyPosition()
  local wm = C.WorldMap()
  if not wm then return end
  local mode = self:Mode()
  local saved = Panoply.db and Panoply.db.mapPos and Panoply.db.mapPos[mode]
  if M:Wants("move") and type(saved) == "table" and #saved > 0 then
    M:Later("mapPos", function()
      Wn.default = Wn.default or {}
      if not Wn.default[mode] then Wn.default[mode] = readPoints(wm) end
      if setPoints(wm, saved) then Wn.moved = true end
    end)
  end
end

function Wn:Apply(why)
  if not C.WorldMap() then return end
  self:ApplyScale()
  self:ApplyDim()
  self:ApplyPosition()
end

-------------------------------------------------------------------------------
-- Move with the grip in the toolbar (one drag, saved per window mode)
-------------------------------------------------------------------------------
function Wn:CanMove()
  return M:Wants("move") and not C.InCombat() and C.WorldMap() ~= nil
end

function Wn:StartMove()
  local wm = C.WorldMap()
  if not (self:CanMove() and wm.StartMoving and wm.SetMovable) then return false end
  local mode = self:Mode()
  self.default = self.default or {}
  if not self.default[mode] then self.default[mode] = readPoints(wm) end
  wm:SetMovable(true)
  if wm.SetClampedToScreen then wm:SetClampedToScreen(true) end
  wm:StartMoving()
  self.moving = true
  return true
end

function Wn:StopMove()
  local wm = C.WorldMap()
  if not (self.moving and wm) then return false end
  self.moving = nil
  if wm.StopMovingOrSizing then wm:StopMovingOrSizing() end
  local pts = readPoints(wm)
  if #pts > 0 and Panoply.db then
    Panoply.db.mapPos = Panoply.db.mapPos or {}
    Panoply.db.mapPos[self:Mode()] = pts
    self.moved = true
  end
  return true
end

function Wn:OnHide()
  if self.wash then self.wash:Hide() end
  if self.moving then self:StopMove() end
end

-- Put the window back: our saved position and size go, the dimmer goes off; the game's own layout comes back.
function Wn:Reset()
  local wm = C.WorldMap()
  if self.moving then self:StopMove() end
  if Panoply.db then Panoply.db.mapPos = {} end
  Panoply:SetOption("mapScale", 1)
  Panoply:SetOption("mapDim", 0)
  if not wm then return end
  M:Later("mapReset", function()
    local mode = Wn:Mode()
    local def = Wn.default and Wn.default[mode]
    if def then setPoints(wm, def) end
    if Wn.default then Wn.default[mode] = nil end
    Wn.moved = nil
    if wm.SetScale then wm:SetScale(1) end
    Wn.scaled = nil
  end)
  Panoply:Print("Map position and size are back to the game's own, and the dimmer is off.")
end

-------------------------------------------------------------------------------
-- Follow my zone
-------------------------------------------------------------------------------
-- The map follows the player into a new zone only if it was showing the zone the player was in;
-- looking at another zone on purpose is left alone.
function Wn:Follow()
  local was = M.lastPlayerMap
  local now = M:PlayerMap()
  M.lastPlayerMap = now
  if not (M:Wants("follow") and Panoply.db and Panoply.db.mapFollow and M:Shown() and now and was and now ~= was) then return false end
  local wm = C.WorldMap()
  if not (wm and wm.SetMapID) or C.WorldMapID() ~= was or C.InCombat() then return false end
  wm:SetMapID(now)
  return true
end

function Wn:Enable() M.lastPlayerMap = M:PlayerMap() end

function Wn:Disable()
  local wm = C.WorldMap()
  if self.wash then self.wash:Hide() end
  if self.moving then self:StopMove() end
  if not wm then return end
  M:Later("mapOff", function()
    if Wn.scaled and wm.SetScale then wm:SetScale(1) Wn.scaled = nil end
    local def = Wn.default and Wn.default[Wn:Mode()]
    if Wn.moved and def then setPoints(wm, def) Wn.moved = nil end
  end)
end
