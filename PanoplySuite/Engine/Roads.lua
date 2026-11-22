-- Panoply Suite Roads (0.6.0 M3, SPEC section 21.3): walk legs that follow roads. Own code.
-- Reads RD.roads from PanoplySuite_RouteData (our own hand-authored road graph, tools/roadgraph/):
-- named road points, road links (road, trail, bridge, pass, tunnel, swim, elevator, zone line) and
-- no-go areas (lakes, cliffs, mountain walls).
--   * A straight walk is allowed only when it crosses no no-go area.
--   * Otherwise (or when it is shorter) the walk snaps on to one of the nearest road points, follows
--     the road graph and snaps off at a road point near the target ("snap-on / snap-off").
--   * With no road in reach and the straight line blocked, the straight line is used with a penalty,
--     so the router prefers any other way but still answers.
--   * 0.6.0 M5 layers: a zone that lies under another one (Undercity) keeps its road points and walls on
--     its own layer. A walk that starts or ends there snaps only to that layer's points and bumps only into
--     its walls; a walk between the layers has no straight line (it goes by the lifts).
-- Plugs into Route.RoadHook (cost) and Route:Legs (path, yards, place names, polyline).
-- Advice only: nothing here moves the character.
local ADDON, Panoply = ...
local Roads = {}
Panoply.Roads = Roads
local Route = Panoply.Route
local sqrt, floor, max, min, huge = math.sqrt, math.floor, math.max, math.min, math.huge

Roads.SNAP_YD = 700           -- look this far for a road point to step onto / off
Roads.SNAP_K = 3              -- try this many road points per end
Roads.CELL = 500              -- grid cell (yd) for road points and no-go areas
Roads.BLOCKED_FACTOR = 4.0    -- straight line through a no-go area with no road round it (0.6.0: was 2.5; a strait
                              -- or a wall with no way through must lose to the ferry or the long way round)
Roads.FIELD_CACHE = 24        -- road distance fields kept (one per start point)
Roads.KINDS = { "road", "trail", "bridge", "pass", "tunnel", "swim", "elevator", "zone" }
Roads.tick = nil              -- set by the router while a search runs (yields inside long loops)

local function d2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function key(cx, cy) return (cx + 2000) * 4096 + (cy + 2000) end

-------------------------------------------------------------------------------
-- Load: per continent arrays, adjacency, grids
-------------------------------------------------------------------------------
function Roads:Data()
  local RD = Route:Data()
  local src = RD and RD.roads
  if not src then self.C, self.src = nil, nil return nil end
  if self.src == src then return self.C end
  local CELL = self.CELL
  local tick = self.tick        -- inside a router job: building the grids can yield between steps
  local C = {}
  local LAYER = {}
  for _, d in pairs(src) do for _, m in ipairs(d.layers or {}) do LAYER[m] = true end end
  self.LAYER = LAYER
  local function layerOf(sid)
    local m = sid and tonumber(sid:match("^(%d+):"))
    return (m and LAYER[m]) and m or nil
  end
  for cont, d in pairs(src) do
    local X, Y, label, id, adj, grid, lay = {}, {}, {}, {}, {}, {}, {}
    local nd = d.nodes
    local n = floor(#nd / 4)
    for i = 1, n do
      local b = (i - 1) * 4
      X[i], Y[i], label[i], id[i] = nd[b + 1], nd[b + 2], nd[b + 3] or nil, nd[b + 4]
      lay[i] = layerOf(id[i])
      adj[i] = {}
      local k = key(floor(X[i] / CELL), floor(Y[i] / CELL))
      local g = grid[k]
      if not g then g = {} grid[k] = g end
      g[#g + 1] = i
      if tick and i % 32 == 0 then tick() end
    end
    local L = d.links
    for j = 1, #L - 2, 3 do
      local a, b, kind = L[j], L[j + 1], L[j + 2]
      local len = d2(X[a], Y[a], X[b], Y[b])
      local A, B = adj[a], adj[b]
      A[#A + 1] = b A[#A + 1] = len A[#A + 1] = kind
      B[#B + 1] = a B[#B + 1] = len B[#B + 1] = kind
      if tick and j % 96 == 1 then tick() end
    end
    -- no-go polygons: { id, xs = {}, ys = {}, minx, miny, maxx, maxy }, bucketed by grid cell
    local polys, pgrid = {}, {}
    for _, p in ipairs(d.nogo or {}) do
      local P = { id = p[1], xs = {}, ys = {}, layer = layerOf(p[1]) }
      local minx, miny, maxx, maxy = huge, huge, -huge, -huge
      for j = 2, #p - 1, 2 do
        local x, y = p[j], p[j + 1]
        P.xs[#P.xs + 1], P.ys[#P.ys + 1] = x, y
        minx, miny, maxx, maxy = min(minx, x), min(miny, y), max(maxx, x), max(maxy, y)
      end
      P.minx, P.miny, P.maxx, P.maxy = minx, miny, maxx, maxy
      polys[#polys + 1] = P
      for cx = floor(minx / CELL), floor(maxx / CELL) do
        for cy = floor(miny / CELL), floor(maxy / CELL) do
          local k = key(cx, cy)
          local g = pgrid[k]
          if not g then g = {} pgrid[k] = g end
          g[#g + 1] = P
        end
      end
      if tick then tick() end
    end
    C[cont] = { n = n, X = X, Y = Y, label = label, id = id, adj = adj, grid = grid, polys = polys, pgrid = pgrid,
                layer = lay, fields = {}, fieldOrder = {}, snaps = {}, snapsL = {} }
  end
  self.C, self.src = C, src
  return C
end

function Roads:Available() return self:Data() ~= nil end

-- The road layer of a map: its own uiMap for a zone under another one (Undercity), nil on the surface.
function Roads:Layer(map)
  local L = map and self.LAYER
  return (L and L[map]) and map or nil
end

-- Road point index by its id ("1433:bridge_s"), for tests and the debug command.
function Roads:Find(cont, id)
  local c = self:Data() and self.C[cont]
  if not c then return nil end
  for i = 1, c.n do if c.id[i] == id then return i end end
  return nil
end

-------------------------------------------------------------------------------
-- Geometry
-------------------------------------------------------------------------------
local function inside(P, x, y)
  if x < P.minx or x > P.maxx or y < P.miny or y > P.maxy then return false end
  local xs, ys, c = P.xs, P.ys, false
  local n = #xs
  local j = n
  for i = 1, n do
    local xi, yi, xj, yj = xs[i], ys[i], xs[j], ys[j]
    if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then c = not c end
    j = i
  end
  return c
end
Roads._inside = inside

local function orient(ax, ay, bx, by, cx, cy)
  local v = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
  if v > 1e-9 then return 1 elseif v < -1e-9 then return -1 end
  return 0
end

local function crosses(P, ax, ay, bx, by)
  if max(ax, bx) < P.minx or min(ax, bx) > P.maxx or max(ay, by) < P.miny or min(ay, by) > P.maxy then return false end
  local xs, ys = P.xs, P.ys
  local n = #xs
  local j = n
  for i = 1, n do
    local o1, o2 = orient(ax, ay, bx, by, xs[j], ys[j]), orient(ax, ay, bx, by, xs[i], ys[i])
    if o1 ~= o2 and o1 ~= 0 and o2 ~= 0 then
      local o3, o4 = orient(xs[j], ys[j], xs[i], ys[i], ax, ay), orient(xs[j], ys[j], xs[i], ys[i], bx, by)
      if o3 ~= o4 and o3 ~= 0 and o4 ~= 0 then return true end
    end
    j = i
  end
  return inside(P, (ax + bx) / 2, (ay + by) / 2)
end

local stamp = 0
-- True when the straight walk a -> b crosses no no-go area. An area that contains either end does not
-- count (the player may stand in a lake; the way out is free). Only areas on the walk's own layer count.
function Roads:Clear(c, ax, ay, bx, by, lay)
  local CELL = self.CELL
  local pgrid = c.pgrid
  stamp = stamp + 1
  local L = d2(ax, ay, bx, by)
  local steps = max(1, floor(L / (CELL * 0.5)))
  local lastk
  for s = 0, steps do
    local t = s / steps
    local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local k = key(cx, cy)
    if k ~= lastk then
      lastk = k
      -- the cell and its neighbours (a segment can clip a corner between two samples)
      for dx = -1, 1 do
        for dy = -1, 1 do
          local g = pgrid[key(cx + dx, cy + dy)]
          if g then
            for i = 1, #g do
              local P = g[i]
              if P.stamp ~= stamp then
                P.stamp = stamp
                if P.layer == lay and crosses(P, ax, ay, bx, by) and not inside(P, ax, ay) and not inside(P, bx, by) then return false, P.id end
              end
            end
          end
        end
      end
    end
  end
  return true
end

-- Up to SNAP_K road points within SNAP_YD of a point that can be walked to in a straight line:
-- flat list { node, yards, node, yards, ... } (nearest first). Cached per point. Only points on the
-- given layer (nil: the surface).
function Roads:Snap(c, x, y, lay)
  local fx, fy = floor(x), floor(y)
  local cache = c.snaps
  if lay then cache = c.snapsL[lay] if not cache then cache = {} c.snapsL[lay] = cache end end
  local row = cache[fx]
  local hit = row and row[fy]
  if hit then return hit end
  local CELL, R = self.CELL, self.SNAP_YD
  local cx, cy = floor(x / CELL), floor(y / CELL)
  local span = floor(R / CELL) + 1
  local cand = {}
  for dx = -span, span do
    for dy = -span, span do
      local g = c.grid[key(cx + dx, cy + dy)]
      if g then
        for i = 1, #g do
          local n = g[i]
          if c.layer[n] == lay then
            local d = d2(x, y, c.X[n], c.Y[n])
            if d <= R then cand[#cand + 1] = { n, d } end
          end
        end
      end
    end
  end
  table.sort(cand, function(a, b) return a[2] < b[2] end)
  local out = {}
  local tick = self.tick
  for i = 1, #cand do
    local n, d = cand[i][1], cand[i][2]
    if tick and i % 4 == 0 then tick() end
    if self:Clear(c, x, y, c.X[n], c.Y[n], lay) then
      out[#out + 1] = n out[#out + 1] = d
      if #out >= self.SNAP_K * 2 then break end
    end
  end
  if not row then row = {} cache[fx] = row c.nsnaps = (c.nsnaps or 0) + 1 end
  if c.nsnaps > 600 then
    c.nsnaps = 1
    if lay then c.snapsL = { [lay] = { [fx] = row } } c.snaps = {} else c.snaps = { [fx] = row } c.snapsL = {} end
  end
  row[fy] = out
  return out
end

-------------------------------------------------------------------------------
-- Road distance field from one start point (Dijkstra over the continent's road graph)
-------------------------------------------------------------------------------
local hpush, hpop = Route._heap.push, Route._heap.pop

function Roads:Field(c, x, y, lay)
  local last = c.lastField
  if last and last.x == x and last.y == y and last.lay == lay then return last end
  local fx, fy = floor(x), floor(y)
  local fk = fx * 65536 + fy + (lay or 0) * 2 ^ 34
  local f = c.fields[fk]
  if not f then
    f = { x = x, y = y, lay = lay, dist = {}, prev = {} }
    local dist, prev, heap, done = f.dist, f.prev, {}, {}
    local snap = self:Snap(c, x, y, lay)
    for i = 1, #snap - 1, 2 do
      local n, d = snap[i], snap[i + 1]
      if not dist[n] or d < dist[n] then dist[n] = d prev[n] = 0 hpush(heap, d, n) end
    end
    local adj, tick, pops = c.adj, self.tick, 0
    while #heap > 0 do
      local top = hpop(heap)
      local u, du = top[2], top[1]
      if not done[u] then
        done[u] = true
        local a = adj[u]
        for j = 1, #a - 2, 3 do
          local v, nd = a[j], du + a[j + 1]
          if not dist[v] or nd < dist[v] - 1e-9 then dist[v] = nd prev[v] = u hpush(heap, nd, v) end
        end
        pops = pops + 1
        if tick and pops % 32 == 0 then tick() end
      end
    end
    c.fields[fk] = f
    local order = c.fieldOrder
    order[#order + 1] = fk
    while #order > self.FIELD_CACHE do c.fields[table.remove(order, 1)] = nil end
  else
    f.x, f.y = x, y
  end
  c.lastField = f
  return f
end

-- Walk distance a -> b in yards and how: "direct", "road" (with the exit node) or "blocked".
-- la, lb: the layers of the two ends (Roads:Layer(map)); a walk between layers has no straight line.
-- noDirect (0.7): the two ends are in different zones; only the roads count (through a zone line).
function Roads:Distance(cont, ax, ay, bx, by, la, lb, noDirect)
  local C = self:Data()
  local c = C and C[cont]
  local d = d2(ax, ay, bx, by)
  if not c then return d, "direct" end
  local best, how, exit = huge, nil, nil
  local clear = la == lb and self:Clear(c, ax, ay, bx, by, la)
  -- 0.7 (SPEC 21.3 "off-graph legs are kept short"): a straight walk off the roads only for short
  -- hops. Longer walks follow the road graph; a straight line is the fallback only when no road
  -- reaches both ends (a data gap, counted in Roads.gaps for the route checks).
  if clear and not noDirect and d <= self.MAX_DIRECT_YD then best, how = d, "direct" end
  if c.n > 0 then
    local f = self:Field(c, ax, ay, la)
    local dist = f.dist
    local snap = self:Snap(c, bx, by, lb)
    for i = 1, #snap - 1, 2 do
      local n = snap[i]
      local dn = dist[n]
      if dn and dn + snap[i + 1] < best then best, how, exit = dn + snap[i + 1], "road", n end
    end
  end
  -- a road graph too thin to be useful here (city streets, a long way round): when the road walk is
  -- more than DETOUR_MAX times the clear straight line, the straight line is the honest answer
  if how == "road" and clear and not noDirect and best > d * self.DETOUR_MAX then
    self.gaps = (self.gaps or 0) + 1
    return d, "direct"
  end
  if not how and clear then
    self.gaps = (self.gaps or 0) + 1
    return d * (noDirect and self.UNKNOWN_CROSS_FACTOR or 1), "direct"   -- no road near either end
  end
  if not how then return d * self.BLOCKED_FACTOR, "blocked" end
  return best, how, exit
end

-- Route.RoadHook: seconds for a walk. amap, bmap: the maps of the two ends (for the layer).
-- 0.7 route fix: a walk from one zone into another follows the road graph through a zone line. The
-- straight line between two zones crossed mountain ranges that have no hand-drawn no-go area (Coldridge
-- Valley -> Goldshire came out as a 7 minute walk over the Dun Morogh mountains).
Roads.ZONE_LINES_ONLY = true
Roads.MAX_DIRECT_YD = 300         -- longest straight walk off the roads when a road route exists
Roads.UNKNOWN_CROSS_FACTOR = 1.6  -- no road near either end: straight line, but clearly worse than a road
Roads.DETOUR_MAX = 2.0            -- a clear straight line beats a road walk more than twice as long

-- True when a walk between these two maps must use a zone line (see ZONE_LINES_ONLY).
function Roads.CrossZone(amap, bmap)
  return Roads.ZONE_LINES_ONLY and amap and bmap and amap ~= bmap or false
end

function Roads.Hook(cont, ax, ay, bx, by, speed, amap, bmap)
  if not Roads:Data() then return nil end
  local yd = Roads:Distance(cont, ax, ay, bx, by, Roads:Layer(amap), Roads:Layer(bmap), Roads.CrossZone(amap, bmap))
  return yd / speed
end

-- The full walk: { yards, how, points = {{x, y}, ...}, nodes = {i, ...}, names = {...}, kinds = {kind=true},
-- through = {named tunnels, in walking order} }.
function Roads:Path(cont, ax, ay, bx, by, amap, bmap)
  local la, lb = self:Layer(amap), self:Layer(bmap)
  local yd, how, exit = self:Distance(cont, ax, ay, bx, by, la, lb, Roads.CrossZone(amap, bmap))
  local out = { yards = yd, how = how, points = { { ax, ay } }, nodes = {}, names = {}, kinds = {}, ids = {}, through = {} }
  if how == "road" then
    local c = self.C[cont]
    local f = self:Field(c, ax, ay, la)
    local chain, n = {}, exit
    while n and n ~= 0 do
      table.insert(chain, 1, n)
      local p = f.prev[n]
      if p and p ~= 0 then
        local a = c.adj[n]
        for j = 1, #a - 2, 3 do
          if a[j] == p then
            local kind = self.KINDS[a[j + 2]] or "road"
            out.kinds[kind] = true
            -- a named tunnel ("Timbermaw Hold", "Blackrock Mountain") is said as "through ..." in the step text
            if kind == "tunnel" then
              local nm = c.label[n] or c.label[p]
              if nm then table.insert(out.through, 1, nm) end
            end
            break
          end
        end
      end
      n = p
    end
    local seen = {}
    for _, i in ipairs(chain) do
      out.nodes[#out.nodes + 1] = i
      out.ids[#out.ids + 1] = c.id[i]
      out.points[#out.points + 1] = { c.X[i], c.Y[i] }
      local l = c.label[i]
      if l and not seen[l] then seen[l] = true out.names[#out.names + 1] = l end
    end
  end
  out.points[#out.points + 1] = { bx, by }
  return out
end

-- Drop cached fields (new data or settings).
function Roads:Reset()
  self.src, self.C = nil, nil
end

Route.RoadHook = Roads.Hook
