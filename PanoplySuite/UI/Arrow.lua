-- Panoply Suite waypoint arrow (own art Media/Arrow.tga, tinted, with Media/ArrowTrim.tga). Hidden in instances.
-- 0.5.0: lock (no drag, clicks go through), own opacity, right-click menu, waypoint queue
-- (Waypoints module) between a hand-picked spot and the guide step, hide in combat.
local ADDON, Panoply = ...
local Arrow = {}
Panoply.Arrow = Arrow
local Skin, C, Nav = Panoply.Skin, Panoply.Compat, Panoply.Nav

local NEAR_YARDS = 40
local HERE_YARDS = 10

function Arrow:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteArrow", UIParent)
  self.frame = f
  f:SetSize(64, 84)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function() if not (Panoply.db and Panoply.db.arrowLocked) then f:StartMoving() end end)
  f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then Arrow:OpenMenu() end end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint(1)
    if Panoply.cdb then Panoply.cdb.arrowPos = { p = p, rp = rp, x = x, y = y, s = f:GetScale() or 1 } end
  end)
  -- Step 2 B: the arrow has its own size (Guide gear, and Small / Normal / Large on the Guide page)
  f:SetScale(Panoply.Look.ArrowScale())
  self:ApplySavedPlace()
  -- 0.6.0 (SPEC 21.12): no soft glow behind the arrow any more; shape and behaviour unchanged.
  -- 0.6.0 arrow fix: the redrawn arrow (smooth 256 px body, brass trim), same size and place
  local tex = Skin.NavArrow(f, "ARTWORK", 56)
  tex:SetPoint("TOP", f, "TOP", 0, 0)
  self.tex = tex
  -- distance "pill" under the arrow
  local pill = CreateFrame("Frame", nil, f)
  pill:SetSize(84, 20); pill:SetPoint("TOP", tex, "BOTTOM", 0, -2)
  local pbg = Skin.Box(pill, "S", { fill = Skin.colors.card, fillA = 0.85, line = Skin.colors.hairline })
  self.pill = pill
  self.dist = Skin.Name(pill, 11, Skin.colors.heading)
  self.dist:SetPoint("CENTER", pill, "CENTER", 0, 0)
  if self.dist.SetJustifyH then self.dist:SetJustifyH("CENTER") end
  self.elapsed = 0
  f:SetScript("OnUpdate", function(_, dt) Arrow:OnUpdate(dt) end)
  f:Hide()
  self:ApplyLock()
  self:ApplyAlpha()
  Panoply:Listen("STEP_CHANGED", function() Arrow.manual = nil; Arrow:Retarget() end)
  Panoply:Listen("WAYPOINTS_CHANGED", function() Arrow:Retarget() end)
  Panoply:Listen("STEPS_CHANGED", function() Arrow:Retarget() end)
  Panoply:Listen("STEP_UPDATED", function() Arrow:Retarget() end)
  return f
end

local function setRotation(tex, a)
  if tex.trim and tex.trim ~= tex then setRotation(tex.trim, a) end
  if tex.SetRotation then tex:SetRotation(a) return end
  -- Fallback: rotate tex coords around the centre.
  local s, c = math.sin(a), math.cos(a)
  local function p(x, y) return 0.5 + (x * c - y * s), 0.5 + (x * s + y * c) end
  local ulx, uly = p(-0.5, -0.5); local llx, lly = p(-0.5, 0.5)
  local urx, ury = p(0.5, -0.5); local lrx, lry = p(0.5, 0.5)
  tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end
Arrow.SetRotation = setRotation

-- Point at a spot picked by hand (the arrow buttons on the Professions tab). Cleared when you get
-- there or the guide moves to another step.
function Arrow:PointAt(m, x, y, label)
  if not m then self.manual = nil else self.manual = { m = m, x = x, y = y, label = label } end
  self.target = nil
  self:Create()
  self:Retarget()
  self:Refresh()
end

-- Locked: no dragging and the mouse goes straight through (unlock in Settings or /panoply arrow unlock).
function Arrow:ApplyLock()
  local f = self.frame
  if not f then return end
  local locked = Panoply.db and Panoply.db.arrowLocked
  f:EnableMouse(not locked)
  if f.SetMovable then f:SetMovable(not locked) end
  self.locked = locked and true or false
end
function Arrow:ApplyAlpha()
  if self.combatFaded then return end
  if self.frame then self.frame:SetAlpha(Panoply.db and Panoply.db.arrowAlpha or 1) end
end
-- 0.5.7: the arrow is its own frame (parented to UIParent, not the guide window) with its own
-- setting, "Hide arrow in combat" (off by default), separate from "Hide guide window in combat".
-- When on it fades (alpha only, never Show/Hide) and comes back at its own opacity afterwards.
-- When off it stays shown and keeps updating through the fight.
function Arrow:OnCombat(inCombat)
  local f = self.frame
  self.combatHidden = nil
  if not f then return end
  local fade = inCombat and Panoply.db and Panoply.db.hideArrowInCombat
  if fade then
    self.combatFaded = true
    Panoply.Skin.FadeTo(f, 0, 0.3)
    if f.EnableMouse then f:EnableMouse(false) end
  elseif self.combatFaded then
    self.combatFaded = nil
    Panoply.Skin.FadeTo(f, Panoply.db and Panoply.db.arrowAlpha or 1, 0.3)
    self:ApplyLock()
  end
end
function Arrow:ResetPosition()
  if Panoply.cdb then Panoply.cdb.arrowPos = nil end
  if self.frame then self.frame:ClearAllPoints(); self.frame:SetPoint("TOP", UIParent, "TOP", 0, -140 / (self.frame:GetScale() or 1)) end
end
-- 0.7.3.6 (profiles): where the saved place says, or the standard place. The saved offsets are in the scale the arrow had when
-- they were saved (s; an older save had no s and was made at 100%), so the same spot on screen is the offsets times s / now.
function Arrow:ApplySavedPlace()
  local f = self.frame
  if not f then return end
  local ap = Panoply.cdb and Panoply.cdb.arrowPos
  local now = f:GetScale() or 1
  f:ClearAllPoints()
  if ap and ap.p then
    local k = (ap.s or 1) / now
    f:SetPoint(ap.p, UIParent, ap.rp or ap.p, (ap.x or 0) * k, (ap.y or 0) * k)
  else f:SetPoint("TOP", UIParent, "TOP", 0, -140 / now) end
end
-- The arrow's size changed (Arrow size in the gear, or Small / Normal / Large): the corner it hangs from stays where it was
-- on screen, and a saved place is saved again in the new scale.
function Arrow:ApplyScale()
  local f = self.frame
  if not f then return false end
  local s = Panoply.Look.ArrowScale()
  local old = f:GetScale() or 1
  if math.abs(old - s) < 0.0001 then return false end
  if f.GetNumPoints and f:GetNumPoints() == 1 and f.GetPoint then
    local p, rel, rp, x, y = f:GetPoint(1)
    f:SetScale(s)
    f:ClearAllPoints()
    f:SetPoint(p, rel or UIParent, rp or p, (x or 0) * old / s, (y or 0) * old / s)
    local ap = Panoply.cdb and Panoply.cdb.arrowPos
    if ap and ap.p then Panoply.cdb.arrowPos = { p = p, rp = rp or p, x = (x or 0) * old / s, y = (y or 0) * old / s, s = s } end
  else f:SetScale(s) end
  return true
end
Panoply.optionHooks = Panoply.optionHooks or {}
Panoply.optionHooks.arrowScale = function() if Arrow.ApplyScale then Arrow:ApplyScale() end end

-- The right-click menu is a tiny quick menu (one window has every setting): lock, clear the target,
-- hide, reset the position, and "All settings..." which opens this page's gear.
function Arrow:OpenMenu()
  local items = {
    { text = "Lock arrow", checked = Panoply.db.arrowLocked, tip = "Stops dragging and lets clicks go through. Unlock it in " .. Panoply:SettingsPath("arrowLocked") .. " or with /panoply arrow unlock.",
      func = function() Panoply:SetOption("arrowLocked", true) Panoply:Print("Arrow locked. Unlock it in " .. Panoply:SettingsPath("arrowLocked") .. " or with /panoply arrow unlock.") end },
    { text = "Clear this target", tip = "Forget a hand-picked spot or the current waypoint.", func = function()
      if self.manual then self.manual = nil elseif Panoply.Waypoints and Panoply.Waypoints.active then Panoply.Waypoints:RemoveCurrent() end
      self:Retarget() end },
    { text = "Hide the arrow", func = function() Panoply:SetOption("arrowShown", false) end },
    { text = "Reset position", func = function() self:ResetPosition() end },
    { text = "All settings...", tip = "Opens the Guide's settings, on the Arrow.", func = function() Panoply.Menu:OpenGear("guide", "arrow") end },
  }
  return Skin.Menu(self.frame, items)
end

-- A spot picked by hand: the hand-picked arrow spot (Professions buttons, quest icons with the
-- Waypoints module off) over the waypoint queue (/panoply way, map clicks, quest icons). Nil = the guide
-- step. Reached spots are dropped here. The route planner plans to this too (Route:Replan), so the
-- arrow's across-zone aim (RouteAim) works for a clicked quest icon exactly as for a guide step.
-- 0.8.1: a waypoint left over from an earlier session that has nothing to do with the written guide being followed is ignored (kept in
-- the list, never followed): the guide card said "In Arathi Highlands" on Zephras Isle for a Refuge Pointe waypoint nobody remembered.
-- Foreign = not on the step's map (or one of its goals') and not in the guide's own zone (PrimaryMaps; never the guide's whole `zones`
-- table, which lists the travel-out maps too). A waypoint set this session (Waypoints:Add) is the player's own and is always followed.
-- 0.8.2: the guide is the one the LEVELLING step belongs to when a travel or profession step is in front of it (Engine:Current is
-- not a guide step then, and the check used to fail open); the guide is loaded on demand (G:Guide), not assumed to be in G.guides;
-- a step with no map (mapID nil) never matches a waypoint's map.
function Arrow:ForeignWaypoint(wp)
  local W, G, E = Panoply.Waypoints, Panoply.Guides, Panoply.Engine
  if not (wp and wp.m and G and E) then return false end
  if W and W.fresh and W.fresh[wp] then return false end
  local cur = E:Current()
  local lvl = E.LevelStep and E:LevelStep()
  local step = (cur and cur.guideID and cur) or (lvl and lvl.guideID and lvl) or nil
  local guide = step and G:Guide(step.guideID)
  if not guide then return false end
  for _, s in ipairs({ cur or step, step }) do
    if s.mapID and wp.m == s.mapID then return false end
    for _, g in ipairs(s.goals or {}) do if g.mapID and g.mapID == wp.m then return false end end
  end
  return not G:PrimaryMaps(guide)[wp.m]
end

function Arrow:HandTarget()
  local m, x, y, label
  local W = Panoply.Waypoints
  local wp = W and W.active and W:Current()
  if wp and self:ForeignWaypoint(wp) then wp = nil end
  if wp then
    local pm, px, py = C.GetPlayerPos()
    local d = pm and Nav.Distance(pm, px, py, wp.m, wp.x, wp.y)
    if d and d <= HERE_YARDS then W:Reached(wp) wp = W:Current() end
    if wp then m, x, y, label = wp.m, wp.x, wp.y, wp.note or "Waypoint" end
  end
  local man = self.manual
  if man then
    local pm, px, py = C.GetPlayerPos()
    local d = pm and Nav.Distance(pm, px, py, man.m, man.x, man.y)
    if d and d <= HERE_YARDS then self.manual = nil
    else m, x, y, label = man.m, man.x, man.y, man.label end
  end
  return m, x, y, label
end

function Arrow:Retarget()
  local m, x, y, label = Panoply.Engine:Target()
  -- Waypoints (/panoply way, map Ctrl-right-click, quest icons) come before the guide step.
  local hm, hx, hy, hl = self:HandTarget()
  if hm then m, x, y, label = hm, hx, hy, hl end
  -- WoW Forever with PanoplyGuide's engine: a spot picked by hand is routed by PanoplyGuide too (and let go when it is reached or cleared)
  local PE = Panoply.PanoplyGuideEngine
  -- Nov 14 2026 (website claim check S2): a profession step shown in front of PanoplyGuide's step (modes Mixed and Professions only) is
  -- routed the same way, as long as it is the step in front and no spot was picked by hand (that wins, as on Classic Era); when the
  -- detour ends, nil lets PanoplyGuide go back to its own target. Before this the arrow kept pointing at PanoplyGuide's target.
  if PE and PE:Active() then
    local pm_, px_, py_, pl_ = hm, hx, hy, hl
    local E = Panoply.Engine
    if not pm_ and E.detour and not E.dungeon then pm_, px_, py_, pl_ = E:Target(E.detour) end
    PE:SetHandTarget(pm_, px_, py_, pl_)
  end
  -- the route follows a hand-picked spot; when it is reached or cleared, back to the guide's target
  local hand = hm and (hm .. ":" .. hx .. ":" .. hy) or nil
  if hand ~= self.handKey then
    self.handKey = hand
    local R = Panoply.Route
    if R and R.Replan then R:Replan(hand and "waypoint" or "waypoint done") end
  end
  -- Nov 12 2026 (a player report, Northshire Abbey): the arrow moves on inside a step (one hand-in done, the next one), but the trail was only
  -- planned again on a step, plan or zone change, so it kept leading to the old place. When the trail no longer ends where the
  -- route should go now, plan it again at once. (Route:Valid compares with the guide's own target, so a flight or boat trip, where
  -- the arrow points at the flight master and the trail at the destination, is left alone.)
  local R = Panoply.Route
  if R and R.current and R.Valid and not R.working and not R:Valid(R.current) then R:Replan("target moved") end
  local same = self.target and m and self.target.m == m and self.target.x == x and self.target.y == y
  if same then return end
  self.target = m and { m = m, x = x, y = y, label = label } or nil
  -- Nov 13 2026 (play-through, Skyborne): the arrow had pointed nowhere (the quest's pick-up has no map spot) and, once the quest is
  -- taken, points at its objective inside the same step; with no trail at all there was nothing for the check above to compare, so no
  -- trail was planned. A new target with no trail plans one (only here, when the target changes, so it never repeats every frame).
  if m and R and R.Replan and not R.working and not R.current then R:Replan("target appeared") end
  if Panoply.db and Panoply.db.blizzWaypoint then
    if m then C.SetBlizzWaypoint(m, x, y) else C.ClearBlizzWaypoint() end
  end
  self:Update()
end

function Arrow:ShouldShow()
  if not (Panoply.db and Panoply.db.arrowShown) or not self.target then return false end
  if self.combatHidden then return false end
  if self.pausedForCorpse then return false end   -- 0.5.7: the corpse arrow is up (UI/CorpseArrow.lua)
  if C.InInstance() then return false end
  return true
end

Arrow.FINDING = "Finding route..."
Arrow.LOOKAHEAD_YD = 45     -- across zones: aim this far ahead along the route's walk (roads, bridges, passes)

-- 0.6.0 arrow fix: the route's next real waypoint for this target, in world coordinates (continent, x, y, name):
-- the boarding point of a flight, boat or zeppelin, or a point a little way ahead on the walk (the road
-- through the pass, the bridge, the zone border). Nil when the route is for another target, you are
-- far off it (a re-plan is on its way) or on another continent from it.
function Arrow:RouteAim(pm, px, py, t)
  local R = Panoply.Route
  local r = R and R.current
  if not (r and r.legs and r.legs[1] and r.to and t) then return nil end
  if r.to.map ~= t.m or math.abs((r.to.x or -9) - t.x) > 1e-4 or math.abs((r.to.y or -9) - t.y) > 1e-4 then return nil end
  local c, wx, wy = R:ToWorld(pm, px, py)
  if not c then return nil end
  local leg = r.legs[1]
  if leg.kind ~= "walk" then
    local f = leg.from
    if f and f.cont == c and f.wx then return c, f.wx, f.wy, f.name end
    return nil
  end
  if not (leg.from and leg.to and leg.from.cont == c and leg.to.cont == c) then return nil end
  local pts = leg.points or { { leg.from.wx, leg.from.wy }, { leg.to.wx, leg.to.wy } }
  local best, bk, qx, qy
  for k = 1, #pts - 1 do
    local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
    local dx, dy = bx - ax, by - ay
    local L = dx * dx + dy * dy
    local u = L > 0 and math.max(0, math.min(1, ((wx - ax) * dx + (wy - ay) * dy) / L)) or 0
    local cx, cy = ax + u * dx, ay + u * dy
    local d = math.sqrt((wx - cx) ^ 2 + (wy - cy) ^ 2)
    if not best or d < best then best, bk, qx, qy = d, k, cx, cy end
  end
  if not best or best > 2 * (R.OFF_TRAIL_YD or 60) then return nil end
  -- 0.7.3.1: the aim point bends towards the player like the minimap trail (Route.NudgeWeight), so the
  -- arrow follows the road you are on when our road line runs beside it
  local s0, len = 0, 0
  for k = 1, #pts - 1 do
    local L = math.sqrt((pts[k + 1][1] - pts[k][1]) ^ 2 + (pts[k + 1][2] - pts[k][2]) ^ 2)
    if k < bk then s0 = s0 + L elseif k == bk then s0 = s0 + math.sqrt((qx - pts[k][1]) ^ 2 + (qy - pts[k][2]) ^ 2) end
    len = len + L
  end
  local function bent(ax, ay, s)
    local w = R.NudgeWeight and R.NudgeWeight(best, s, s0, len) or 0
    return c, ax + w * (wx - qx), ay + w * (wy - qy), leg.to.name
  end
  local need = self.LOOKAHEAD_YD
  local sx, sy = qx, qy
  for k = bk, #pts - 1 do
    local ex, ey = pts[k + 1][1], pts[k + 1][2]
    local L = math.sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2)
    if L >= need and L > 0 then return bent(sx + (ex - sx) * need / L, sy + (ey - sy) * need / L, s0 + self.LOOKAHEAD_YD) end
    need = need - L
    sx, sy = ex, ey
  end
  return c, leg.to.wx, leg.to.wy, leg.to.name
end

function Arrow:Update()
  local f = self.frame
  if not f then return end
  self.last = { target = self.target }
  if self:ShouldShow() then f:Show() else f:Hide() end
  local t = self.target
  if not t and self.dist then self.dist:SetText("") end   -- 0.8.2: no target, no leftover "Head to <zone>" on the pill
  if not t or C.InInstance() then self.last.target = nil if Panoply.UI and Panoply.UI.UpdateArrow then pcall(Panoply.UI.UpdateArrow, Panoply.UI) end return end
  local PE = Panoply.PanoplyGuideEngine
  if PE and PE:Active() then return self:UpdatePanoplyGuide(t) end
  local m, px, py = C.GetPlayerPos()
  if not m then
    -- 0.6.0 arrow fix: a loading screen or the moment after a zone change: a calm text, no arrow, no glow
    self.tex:Hide(); self.dist:SetText(Arrow.FINDING); self.last.target = nil; self.last.finding = true
    if Panoply.UI and Panoply.UI.UpdateArrow then pcall(Panoply.UI.UpdateArrow, Panoply.UI) end
    return
  end
  local bearing, d = Nav.Bearing(m, px, py, t.m, t.x, t.y)
  -- 0.6.0 arrow fix: in another zone (or on another continent) follow the route's next real waypoint
  local aimB, aimD, via
  if m ~= t.m or not bearing then
    local c, ax, ay, name = self:RouteAim(m, px, py, t)
    if c then aimB, aimD = Nav.BearingToWorld(m, px, py, c, ax, ay) via = name end
  end
  if not bearing and not aimB then
    self.tex:Hide()
    local zone = C.MapName(t.m) or "another zone"
    self.last.otherZone = zone
    local R = Panoply.Route
    local busy = R and R.Enabled and R:Enabled() and ((R.queue and R.queue[1]) or R.waitPos)
    self.dist:SetText(busy and Arrow.FINDING or ("Head to " .. zone))
    self.last.finding = busy and true or nil
    if Panoply.UI and Panoply.UI.UpdateArrow then pcall(Panoply.UI.UpdateArrow, Panoply.UI) end
    return
  end
  local facing = C.Facing()
  local col = Skin.colors.arrowFar
  if bearing then
    if d <= HERE_YARDS then col = Skin.colors.arrowHere elseif d <= NEAR_YARDS then col = Skin.colors.arrowNear end
  end
  self.tex:SetVertexColor(col[1], col[2], col[3], 1)
  local dir = aimB or bearing
  local shown = bearing and d or aimD
  if facing then
    setRotation(self.tex, Nav.ArrowAngle(dir, facing))
    self.tex:Show()
  else
    self.tex:Hide()
  end
  self.dist:SetText(Panoply.StepText.Distance(shown))
  self.last.yards, self.last.color = shown, col
  self.last.via = aimB and via or nil
  self.last.angle = facing and Nav.ArrowAngle(dir, facing) or nil
  if Panoply.UI and Panoply.UI.UpdateArrow then pcall(Panoply.UI.UpdateArrow, Panoply.UI) end
end

-- WoW Forever with PanoplyGuide's engine: the direction and the distance are the ones PanoplyGuide's own (hidden) arrow would show:
-- along its walking route, to the flight master or the dock of its travel plan, or straight at the target.
Arrow.SEE_GUIDE = "See the guide"
function Arrow:UpdatePanoplyGuide(t)
  local st, yards, angle, zone = Panoply.PanoplyGuideEngine:Sample()
  local function done() if Panoply.UI and Panoply.UI.UpdateArrow then pcall(Panoply.UI.UpdateArrow, Panoply.UI) end end
  if st == "nopos" then
    self.tex:Hide(); self.dist:SetText(Arrow.FINDING); self.last.target = nil; self.last.finding = true
    return done()
  end
  if st == "far" then
    zone = zone or C.MapName(t.m) or "another zone"
    self.tex:Hide(); self.dist:SetText("Head to " .. zone); self.last.otherZone = zone
    return done()
  end
  local words = Panoply.PanoplyGuideEngine:StateText(st, yards)
  if words then
    -- 0.9.9: a walk PanoplyGuide cannot guide says so in PanoplyGuide's own words, on the distance line. 0.9.9.1: as PanoplyGuide's own arrow does
    -- per state: while the walking route is being found ("routing") the arrow points straight at the target (when there is a bearing) with
    -- the words; in every other worded state (unmapped, submerged, water-depth, arrived-underwater) the words and no arrow
    self.dist:SetText(words); self.last.stateText = words; self.last.yards = nil
    if Panoply.PanoplyGuideEngine.STATE_ARROW[st] and angle then
      local col = Skin.colors.arrowFar
      self.tex:SetVertexColor(col[1], col[2], col[3], 1)
      setRotation(self.tex, angle) self.tex:Show()
      self.last.color, self.last.angle = col, angle
    else
      self.tex:Hide(); self.last.target = nil
    end
    return done()
  end
  self.last.stateText = nil
  if st == "instruction" and not (yards and angle) then
    -- a flight, a boat, a portal or the hearthstone with nothing to walk to: the guide window says what to do
    self.tex:Hide(); self.dist:SetText(Arrow.SEE_GUIDE); self.last.target = nil
    return done()
  end
  if not (st == "travel" or st == "arrived" or st == "search" or st == "instruction") or not yards then
    self.tex:Hide(); self.dist:SetText(""); self.last.target = nil
    return done()
  end
  local col = Skin.colors.arrowFar
  if st == "arrived" or yards <= HERE_YARDS then col = Skin.colors.arrowHere elseif yards <= NEAR_YARDS then col = Skin.colors.arrowNear end
  self.tex:SetVertexColor(col[1], col[2], col[3], 1)
  if angle then setRotation(self.tex, angle) self.tex:Show() else self.tex:Hide() end
  self.dist:SetText(Panoply.StepText.Distance(yards))
  self.last.yards, self.last.color, self.last.angle = yards, col, angle
  return done()
end

function Arrow:OnUpdate(dt)
  self.elapsed = self.elapsed + (dt or 0)
  if self.elapsed < 0.05 then return end
  self.elapsed = 0
  self.updates = (self.updates or 0) + 1
  -- waypoints are cleared on arrival even while the guide step stays the same
  if Panoply.Waypoints and Panoply.Waypoints.active and Panoply.Waypoints:Current() then self:Retarget() end
  self:Update()
end

function Arrow:Refresh()
  self:Create()
  if self:ShouldShow() then self.frame:Show() else self.frame:Hide() end
  self:Update()
end

-- 0.6.0 arrow fix: re-resolve the target on every zone change (and after a loading screen) right away; the
-- 0.05 s update then reads the new position, so the arrow is right again within a second.
local function zoneChanged()
  if not Arrow.frame then return end
  Arrow:Retarget()
  Arrow:Update()
end
Panoply:On("ZONE_CHANGED_NEW_AREA", zoneChanged)
Panoply:On("ZONE_CHANGED", zoneChanged)
Panoply:On("PLAYER_ENTERING_WORLD", zoneChanged)

Panoply.optionHooks.arrowLocked = function() Arrow:ApplyLock() end
Panoply.optionHooks.arrowAlpha = function() Arrow:ApplyAlpha() end
Panoply.optionHooks.hideArrowInCombat = function() Arrow:OnCombat(Panoply.UI and Panoply.UI.inCombat) end
