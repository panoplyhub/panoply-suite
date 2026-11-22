-- Panoply Suite Nav: distances and bearings between map points (own math).
local ADDON, Panoply = ...
local Nav = {}
Panoply.Nav = Nav
local C = Panoply.Compat
local atan2, sqrt, pi = math.atan2, math.sqrt, math.pi

Nav.RUN_SPEED = 7.0          -- yards per second on foot
Nav.CROSS_ZONE_SECONDS = 300 -- unknown path between two zones on one continent
Nav.CROSS_CONTINENT_SECONDS = 2400 -- boat/zeppelin plus the walk either side

local function sameMapVector(mapID, px, py, tx, ty)
  local w, h = C.MapSize(mapID)
  if not w then return nil end
  local east = (tx - px) * w
  local south = (ty - py) * h
  return east, south
end

-- Project world point (cx,wx,wy) into a map's 0..1 coordinates using the map's own frame.
local function projectToMap(mapID, wx, wy)
  local c0, ax, ay = C.WorldPos(mapID, 0, 0)
  local c1, bx, by = C.WorldPos(mapID, 1, 0)
  local c2, dx, dy = C.WorldPos(mapID, 0, 1)
  if not (c0 and c1 and c2 and ax and bx and dx) then return nil end
  local ux, uy = bx - ax, by - ay
  local vx, vy = dx - ax, dy - ay
  local det = ux * vy - uy * vx
  if det == 0 then return nil end
  local rx, ry = wx - ax, wy - ay
  local u = (rx * vy - ry * vx) / det
  local v = (ux * ry - uy * rx) / det
  return u, v, c0
end
Nav.ProjectToMap = projectToMap

-- World position (continent, x north, y west, in yards) of a map point from the route data's map
-- rects (PanoplySuite_RouteData), for when the client cannot answer.
local function rectWorld(map, x, y)
  local R = Panoply.Route
  local RD = R and R.Data and R:Data() or rawget(_G, "PanoplySuiteRouteData")
  local r = RD and RD.rects and RD.rects[map]
  if not r then return nil end
  return r[1], r[4] - y * (r[4] - r[2]), r[5] - x * (r[5] - r[3])
end

-- Both points in one world frame: the client's first, else the route data's (never mixed).
local function worldPair(pmap, px, py, tmap, tx, ty)
  local pc, pwx, pwy = C.WorldPos(pmap, px, py)
  local tc, twx, twy = C.WorldPos(tmap, tx, ty)
  if pc and tc and pwx and twx then return pc, pwx, pwy, tc, twx, twy end
  pc, pwx, pwy = rectWorld(pmap, px, py)
  tc, twx, twy = rectWorld(tmap, tx, ty)
  if pc and tc then return pc, pwx, pwy, tc, twx, twy end
  return nil
end
Nav.WorldPair = worldPair

-- Returns east, south offsets in yards from player point to target point.
-- 0.6.0 arrow fix: across maps the offset is the plain difference of the two world positions (yards, Blizzard
-- axes x north / y west), so it no longer needs the player's map size; on one map it uses the map
-- size and falls back to the world frame when the size is unknown.
function Nav.Offset(pmap, px, py, tmap, tx, ty)
  if not (pmap and tmap and px and py and tx and ty) then return nil end
  if pmap == tmap then
    local e, s = sameMapVector(pmap, px, py, tx, ty)
    if e then return e, s end
  end
  local pc, pwx, pwy, tc, twx, twy = worldPair(pmap, px, py, tmap, tx, ty)
  if not pc or pc ~= tc then return nil end
  return -(twy - pwy), -(twx - pwx)
end

-- Bearing and distance from a map point to a world point (route legs are in world coordinates,
-- from Panoply.Route:ToWorld). Nil when the player is on another continent or the map is unknown.
function Nav.BearingToWorld(pmap, px, py, cont, wx, wy)
  local R = Panoply.Route
  if not (R and R.ToWorld and pmap) then return nil end
  local c, ax, ay = R:ToWorld(pmap, px, py)
  if not c or c ~= cont then return nil end
  local north, west = wx - ax, wy - ay
  local a = atan2(west, north)
  if a < 0 then a = a + 2 * pi end
  return a, sqrt(north * north + west * west)
end

function Nav.Distance(pmap, px, py, tmap, tx, ty)
  local e, s = Nav.Offset(pmap, px, py, tmap, tx, ty)
  if not e then return nil end
  return sqrt(e * e + s * s)
end

-- Bearing in WoW facing convention: 0 = north, increasing counter-clockwise (pi/2 = west).
function Nav.Bearing(pmap, px, py, tmap, tx, ty)
  local e, s = Nav.Offset(pmap, px, py, tmap, tx, ty)
  if not e then return nil end
  local north, west = -s, -e
  local a = atan2(west, north)
  if a < 0 then a = a + 2 * pi end
  return a, sqrt(e * e + s * s)
end

-- Angle to rotate an "up" arrow texture so it points at the target.
function Nav.ArrowAngle(bearing, facing)
  if not bearing or not facing then return nil end
  local a = bearing - facing
  while a < 0 do a = a + 2 * pi end
  while a >= 2 * pi do a = a - 2 * pi end
  return a
end

-- Planner travel estimate (seconds) between two spots {map,x,y}.
function Nav.TravelSeconds(a, b)
  if not a or not b then return Nav.CROSS_ZONE_SECONDS end
  local d = Nav.Distance(a.map, a.x, a.y, b.map, b.x, b.y)
  if d then return d / Nav.RUN_SPEED end
  local QD = Panoply.QuestData
  local ca, cb = QD.continentOf[a.map], QD.continentOf[b.map]
  if ca and cb and ca ~= cb then return Nav.CROSS_CONTINENT_SECONDS end
  return Nav.CROSS_ZONE_SECONDS
end
