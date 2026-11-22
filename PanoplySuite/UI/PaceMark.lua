-- Panoply Suite 0.8.4: the XP horizon mark. A small brass mark on the experience bar at the spot your pace takes you
-- to in the next 30 minutes (Engine/Pace.lua, Pace:Horizon). It is drawn in two places, both optional and both switched
-- by one setting (Miscellaneous > This session > "Mark where my pace takes me on the XP bar"):
--   * on the level bar of the Guide page (our own bar; placed by the Guide page's layout through Menu.levelingBlocks);
--   * on the game's own experience bar at the bottom of the screen, when this client has one we can find and it is on
--     screen. That one is a frame of our own laid over the bar: nothing of the game's bar is changed, hooked or replaced.
-- No mark is drawn when there is no pace learned yet (the plan's estimate is not used for it), at the level cap, or when the next level comes before the 30 minutes are
-- up (then the mark sits at the end of the bar). A flat line, no glow, no animation. Reads only.
local ADDON, Panoply = ...
local Menu, Skin, C = Panoply.Menu, Panoply.Skin, Panoply.Compat
local PM = {}
Panoply.PaceMark = PM

PM.WIDTH = 2                 -- the mark, in UI units
PM.OVERHANG = 2              -- how far it stands out above and below our own bar
PM.GAME_BARS = { "MainMenuExpBar" }   -- the game's experience bar, by client (Classic Era); a client without one gets no mark there

Panoply.defaults.account.paceMark = true

function PM:On() return not (Panoply.db and Panoply.db.paceMark == false) end

-- Where the mark goes: the horizon (Pace:Horizon), or nil when there is none to draw.
function PM:Horizon()
  if not self:On() then return nil end
  local P = Panoply.Pace
  if not (P and P.Horizon) then return nil end
  local ok, h = pcall(P.Horizon, P)
  if not ok or type(h) ~= "table" then return nil end
  -- the mark is drawn from the pace learned from your own play, never from the plan's estimate
  if h.source ~= "pace" or h.frac <= (h.now or 0) then return nil end
  return h
end

local function paint(tex)
  local c = Skin.colors.goldBright or Skin.colors.gold or Skin.colors.text
  Skin.Solid(tex, c, 1)
end

-------------------------------------------------------------------------------
-- The Guide page's level bar
-------------------------------------------------------------------------------
local block = {}
function block.build(p)
  local bar = p.nextCard and p.nextCard.levelBar
  if not bar then return end
  local tick = bar:CreateTexture(nil, "OVERLAY")
  paint(tick)
  tick:SetSize(PM.WIDTH, (bar:GetHeight() or 8) + 2 * PM.OVERHANG)
  tick:Hide()
  p.paceTick = tick
end
function block.refresh(p)
  if not p.paceTick then return end
  p.paceHorizon = (not Panoply:PlayAlong()) and PM:Horizon() or nil
  if not p.paceHorizon then p.paceTick:Hide() end
end
-- the bar has its width by now (the page laid its cards out first); the block takes no room of its own
function block.layout(p, y, W)
  local tick, h = p.paceTick, p.paceHorizon
  if not tick then return y end
  local bar = p.nextCard.levelBar
  local w = bar.panoplyWidth or (bar.GetWidth and bar:GetWidth()) or 0
  if not h or w <= 4 then tick:Hide() return y end
  local x = math.max(1, math.min(w - 1 - PM.WIDTH, math.floor((w - 2) * h.frac + 0.5)))
  tick:ClearAllPoints(); tick:SetPoint("TOPLEFT", bar, "TOPLEFT", x, PM.OVERHANG)
  tick:Show()
  return y
end
if Menu and Menu.levelingBlocks then table.insert(Menu.levelingBlocks, block) end
PM.block = block

-------------------------------------------------------------------------------
-- The game's own experience bar
-------------------------------------------------------------------------------
local function usable(f) return type(f) == "table" and f.GetWidth ~= nil and f.IsVisible ~= nil end

function PM.GameBar()
  for _, name in ipairs(PM.GAME_BARS) do
    local f = C.G(name)
    if usable(f) then return f, name end
  end
  return nil
end

function PM:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuitePaceMark", _G.UIParent)
  f:SetSize(PM.WIDTH, 10)
  if f.SetFrameStrata then f:SetFrameStrata("MEDIUM") end
  if f.EnableMouse then f:EnableMouse(false) end
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetAllPoints(f)
  paint(f.tex)
  f:Hide()
  self.frame = f
  return f
end

-- Place or hide the mark on the game's bar. Returns true when it is shown.
function PM:Refresh()
  local h = self:Horizon()
  local bar = h and PM.GameBar()
  local shown = false
  if bar then
    local okV, vis = pcall(bar.IsVisible, bar)
    local okW, w = pcall(bar.GetWidth, bar)
    local okH, bh = pcall(bar.GetHeight, bar)
    w, bh = okW and C.Readable(w), okH and C.Readable(bh)
    if okV and vis and type(w) == "number" and w > 4 then
      local f = self:Build()
      local x = math.max(0, math.min(w - PM.WIDTH, math.floor(w * h.frac + 0.5)))
      local ok = pcall(function()
        -- over the bar's own art, whatever layer the game draws that on
        if bar.GetFrameStrata and f.SetFrameStrata then f:SetFrameStrata(bar:GetFrameStrata()) end
        if bar.GetFrameLevel and f.SetFrameLevel then f:SetFrameLevel((bar:GetFrameLevel() or 0) + 5) end
        f:SetSize(PM.WIDTH, type(bh) == "number" and bh > 0 and bh or 10)
        f:ClearAllPoints()
        f:SetPoint("LEFT", bar, "LEFT", x, 0)
      end)
      if ok then f:Show() shown = true end
    end
  end
  if not shown and self.frame then self.frame:Hide() end
  self.shown = shown
  return shown
end

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION" }) do
  Panoply:On(ev, function() PM:Refresh() end)
end
Panoply:Listen("PACE_CHANGED", function() PM:Refresh() end)
Panoply:Listen("PLAN_ADOPTED", function() PM:Refresh() end)
Panoply:Listen("OPTION_CHANGED", function(key)
  if key == "paceMark" or key == "paceSource" or key == "paceLearn" then PM:Refresh() end
end)
