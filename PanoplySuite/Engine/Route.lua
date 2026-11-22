-- Panoply Suite Route (0.6.0, SPEC section 21.4): the router core. Own code.
-- Finds the quickest way to a target with A* over a time-weighted graph built from
-- PanoplySuite_RouteData (flight paths, ships, zeppelins, the Deeprun Tram, innkeepers):
--   * walk edges between any two points on one continent: straight when nothing is in the way, else along
--     the road graph (M3, Engine/Roads.lua plugs into Route.RoadHook);
--   * flights, only between flight paths this character knows and only for the player's faction;
--   * transports, costed as the average wait (half the departure interval) plus the ride;
--   * a virtual hearthstone edge from the start to the bind spot, only when the cooldown is up.
-- The search runs as a coroutine with a per-frame budget (Route.BUDGET_MS, 2 ms), results are cached
-- (LRU, 32 entries) and the route is re-planned on the triggers in SPEC 21.4.
-- Advice only: nothing here takes a flight, uses an item or boards anything.
local ADDON, Panoply = ...
local Route = {}
Panoply.Route = Route
local C = Panoply.Compat
local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min

Route.RUN_SPEED = 7.0         -- yd/s on foot (Nav.RUN_SPEED)
Route.TAXI_SPEED = 32.0       -- yd/s, to be replaced by measured flight times (M6)
Route.TAXI_BOARD = 10         -- s: talk to the flight master and take off
Route.HEARTH_CAST = 10        -- s
Route.HEARTH_LOAD = 20        -- s of loading screen
Route.HEARTH_ITEM = 6948
Route.BUDGET_MS = 2.0         -- hard cap per frame slice (SPEC 21.8)
Route.SLICE_MS = 0.75         -- target for the longest slice; checks run often enough to stay well under the cap
Route.YIELD_MS = 0.6          -- yield once a slice has run this long: leaves room for the last uninterrupted step
Route.CACHE_SIZE = 32
Route.OFF_TRAIL_YD = 60
Route.OFF_TRAIL_SECONDS = 5
-- 0.7.3.1 bend: the road graph is our own and coarse (a few points a road), so the real road can run
-- tens of yards beside its line, and within OFF_TRAIL_YD nothing re-plans. The minimap trail and the
-- arrow therefore bend through the player: walk points near the player move by the player's offset from
-- the line, fully up to NUDGE_FULL_YD off it and fading to none at OFF_TRAIL_YD; fully for NUDGE_FLAT_YD
-- along the line either way (wider than the minimap at its widest zoom, so the visible trail runs along
-- the road you are on) and fading to none at NUDGE_REACH_YD; and to none over the last NUDGE_END_YD to
-- either end of the walk, so the start and the destination never move.
Route.NUDGE_FULL_YD = 55
Route.NUDGE_FLAT_YD = 240
Route.NUDGE_REACH_YD = 440
Route.NUDGE_END_YD = 60
Route.SHORT_WALK_S = 5         -- 0.7.2 (M3): a walk this short (as shown, rounded) before a flight or boat is not a leg of its own
Route.OVER_TARGET_YD = 250     -- 0.7.2 (M3): a flight that passes this close to the target "passes over" it
Route.BACK_WALK_YD = 300       -- ...and is worth saying only when the walk back is longer than this
-- M3 hook: function(cont, ax, ay, bx, by, speed, amap, bmap) -> seconds (maps: M5 road layers). nil = straight line. Engine/Roads.lua sets it.
-- Called inside the search coroutine without pcall (Lua 5.1 cannot yield across pcall); an error ends
-- the job (Route:Resume reports it) instead of hiding a bad answer.
Route.RoadHook = nil

local clock = _G.debugprofilestop
  or (_G.GetTimePreciseSec and function() return _G.GetTimePreciseSec() * 1000 end)
  or (os and os.clock and function() return os.clock() * 1000 end)
  or function() return 0 end
Route.clock = clock

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------
-- WoW Forever with Polestar's engine (Engine/PolestarEngine.lua): the route is Polestar's, so our route data is not read and
-- (it is load-on-demand) never loaded; our own router does not plan.
local function polestar() local PE = Panoply.PolestarEngine return PE ~= nil and PE:Active() end
Route.Polestar = polestar

function Route:Data()
  if polestar() then return nil end
  local RD = rawget(_G, "PanoplySuiteRouteData")
  if not (RD and RD.flavor) and not self.loadTried then
    self.loadTried = true
    local load = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if load then pcall(load, "PanoplySuite_RouteData") end
    RD = rawget(_G, "PanoplySuiteRouteData")
  end
  if RD and RD.flavor then return RD end
  return nil
end

function Route:Available() return self:Data() ~= nil end

-- uiMap (0..1) -> continent, world x, world y (Blizzard axes: x north, y west).
function Route:ToWorld(map, x, y)
  local RD = self:Data()
  local r = RD and RD.rects[map]
  if r then return r[1], r[4] - y * (r[4] - r[2]), r[5] - x * (r[5] - r[3]) end
  if C.WorldPos then
    local c, wx, wy = C.WorldPos(map, x, y)
    if c then return c, wx, wy end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Player state that changes the graph
-------------------------------------------------------------------------------
local function opt(key) local db = Panoply.db return not (db and db[key] == false) end

function Route:Faction()
  local f = C.PlayerInfo().faction
  return (f == "Horde") and "H" or "A"
end

function Route:Known(name)
  local k = Panoply.cdb and Panoply.cdb.knownTaxi
  return k and name and k[name] and true or false
end

function Route:GroundSpeed()
  local s = Panoply.cdb and tonumber(Panoply.cdb.routeSpeed)
  return (s and s > self.RUN_SPEED) and s or self.RUN_SPEED
end

-- Learn the ground speed (mounted speed when the player rides): GetUnitSpeed's run speed.
function Route:LearnSpeed()
  local f = _G.GetUnitSpeed
  if not (f and Panoply.cdb) then return end
  local ok, _, run = pcall(f, "player")
  -- 0.8.2: Forever hands this back as a secret number while the game restricts addons; comparing it raised
  -- "attempt to compare local 'run'". Readable() turns a secret into nil (and is a no-op on Era).
  run = ok and tonumber(C.Readable(run))
  if run and run > self.RUN_SPEED and run < 20 and (not Panoply.cdb.routeSpeed or run > Panoply.cdb.routeSpeed) and not C.OnTaxi() then
    Panoply.cdb.routeSpeed = run
  end
end

-- Seconds until the hearthstone is ready (0 = ready), or nil when the player has none.
function Route:HearthCooldown()
  if (C.ItemCount and C.ItemCount(self.HEARTH_ITEM) or 0) <= 0 then return nil end
  local f = (_G.C_Container and _G.C_Container.GetItemCooldown) or _G.GetItemCooldown
  if not f then return 0 end
  local ok, start, dur = pcall(f, self.HEARTH_ITEM)
  if not ok then return 0 end
  start, dur = tonumber(C.Readable(start)) or 0, tonumber(C.Readable(dur)) or 0   -- cooldowns can be secret on Forever
  if start <= 0 or dur <= 0 then return 0 end
  return max(0, start + dur - C.GetTime())
end

-- Innkeeper the hearthstone is bound to: { name, cont, wx, wy, map, x, y } or nil.
function Route:BindSpot()
  local RD = self:Data()
  if not RD then return nil end
  local bind = C.BindLocation and C.BindLocation()
  local learned = Panoply.cdb and Panoply.cdb.bindSpot
  if learned and learned.name == bind and learned.cont then
    return { name = bind, cont = learned.cont, wx = learned.wx, wy = learned.wy, map = learned.map, x = learned.x, y = learned.y }
  end
  local id = bind and RD.bind[bind]
  local i = id and RD.inns[id]
  if not i then return nil end
  return { name = bind, npc = id, npcName = i[1], cont = i[2], wx = i[3], wy = i[4], map = i[5], x = i[6], y = i[7] }
end

-------------------------------------------------------------------------------
-- Graph (static part: rebuilt when the faction, known flights or settings change)
-------------------------------------------------------------------------------
Route.epoch = 0
function Route:Bump(reason) self.epoch = self.epoch + 1 self.graph = nil self.lastBump = reason end

local function d2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end

function Route:Graph(tick)
  tick = tick or function() end
  local RD = self:Data()
  if not RD then return nil end
  local fac = self:Faction()
  local sig = table.concat({ self.epoch, fac, tostring(opt("routeFlights")), tostring(opt("routeTransports")) }, "|")
  if self.graph and self.graph.sig == sig then return self.graph end
  local V, adj, ground = {}, {}, {}
  local function add(v)
    V[#V + 1] = v
    adj[#V] = {}
    if v.ground then
      local g = ground[v.cont]
      if not g then g = {} ground[v.cont] = g end
      g[#g + 1] = #V
    end
    return #V
  end
  local hsp = self.TAXI_SPEED
  if opt("routeFlights") then
    local gIdx, aIdx = {}, {}
    for id, n in pairs(RD.nodes) do
      if (n[2] == "N" or n[2] == fac) and self:Known(n[1]) then
        gIdx[id] = add({ kind = "fp", ground = true, cont = n[3], wx = n[4], wy = n[5], map = n[6], x = n[7], y = n[8],
                         name = n[1], npc = n[9], npcName = n[10], node = id })
        aIdx[id] = add({ kind = "air", cont = n[3], wx = n[4], wy = n[5], name = n[1], node = id })
        local a = adj[gIdx[id]]
        a[#a + 1] = { aIdx[id], self.TAXI_BOARD, "board" }
        local b = adj[aIdx[id]]
        b[#b + 1] = { gIdx[id], 0, "land" }
      end
      tick()
    end
    for _, l in ipairs(RD.legs) do
      local a, b = aIdx[l[2]], aIdx[l[3]]
      if a and b then
        local e = adj[a]
        e[#e + 1] = { b, l[4] / self.TAXI_SPEED, "fly", l }
      end
      tick()
    end
  end
  if opt("routeTransports") then
    for _, t in ipairs(RD.transports) do
      if t[4] == "N" or t[4] == fac then
        local idx = {}
        for i, s in ipairs(t[6]) do
          idx[i] = add({ kind = "dock", ground = true, cont = s[2], wx = s[3], wy = s[4], map = s[5], x = s[6], y = s[7], name = s[1], transport = t })
        end
        local wait = t[5] / 2
        for _, r in ipairs(t[7]) do
          local a, b = idx[r[1]], idx[r[2]]
          local e = adj[a]
          e[#e + 1] = { b, wait + r[3], t[3], { t = t, wait = wait, upTo = t[5], ride = r[3] } }
          if V[a].cont == V[b].cont and r[3] > 0 then hsp = max(hsp, d2(V[a].wx, V[a].wy, V[b].wx, V[b].wy) / r[3]) end
        end
      end
      tick()
    end
  end
  self.graph = { sig = sig, V = V, adj = adj, ground = ground, hspeed = max(hsp, self:GroundSpeed()), n = #V }
  return self.graph
end

-------------------------------------------------------------------------------
-- A* (binary heap) as a coroutine
-------------------------------------------------------------------------------
local function push(h, f, v)
  local n = #h + 1
  h[n] = { f, v }
  while n > 1 do
    local p = floor(n / 2)
    if h[p][1] <= h[n][1] then break end
    h[p], h[n] = h[n], h[p]
    n = p
  end
end
local function pop(h)
  local top = h[1]
  local n = #h
  h[1] = h[n]
  h[n] = nil
  n = n - 1
  local i = 1
  while true do
    local l, r, s = 2 * i, 2 * i + 1, i
    if l <= n and h[l][1] < h[s][1] then s = l end
    if r <= n and h[r][1] < h[s][1] then s = r end
    if s == i then break end
    h[i], h[s] = h[s], h[i]
    i = s
  end
  return top
end
Route._heap = { push = push, pop = pop }

function Route:WalkSeconds(cont, ax, ay, bx, by, speed, amap, bmap)
  if self.RoadHook and opt("routeRoads") then
    local s = self.RoadHook(cont, ax, ay, bx, by, speed, amap, bmap)
    if s then return s end
  end
  return d2(ax, ay, bx, by) / speed
end

-- The search body. graph: static graph; S, T: {cont, wx, wy, ...}; ctx: { hearth = spot|nil, speed }.
-- Yields (from inside) whenever the slice ran longer than Route.YIELD_MS (aiming at Route.SLICE_MS for the longest one).
function Route:Search(G, S, T, ctx, tick)
  local V, adj, ground = G.V, G.adj, G.ground
  local nS, nT = G.n + 1, G.n + 2
  local VV = setmetatable({ [nS] = S, [nT] = T }, { __index = V })
  local speed = ctx.speed
  local hs = max(G.hspeed, speed)   -- a fast pace (factor < 1) must not make the estimate overshoot
  local function h(i)
    local v = VV[i]
    if v.cont ~= T.cont then return 0 end
    return d2(v.wx, v.wy, T.wx, T.wy) / hs
  end
  local g, prev, closed, heap = { [nS] = 0 }, {}, {}, {}
  -- the bind spot is a vertex of its own, reached only by the hearth edge from the start
  local nH
  if ctx.hearth then
    nH = G.n + 3
    VV[nH] = { kind = "inn", ground = true, cont = ctx.hearth.cont, wx = ctx.hearth.wx, wy = ctx.hearth.wy, map = ctx.hearth.map,
               x = ctx.hearth.x, y = ctx.hearth.y, name = ctx.hearth.name, npcName = ctx.hearth.npcName }
  end
  push(heap, h(nS), nS)
  local stats = { expanded = 0, relaxed = 0 }
  local function relax(u, v, cost, kind, info)
    stats.relaxed = stats.relaxed + 1
    local ng = g[u] + cost
    if not closed[v] and (not g[v] or ng < g[v] - 1e-9) then
      g[v] = ng
      prev[v] = { u, kind, info, cost }
      push(heap, ng + h(v), v)
    end
    if kind == "walk" or stats.relaxed % 16 == 0 then tick() end   -- a walk edge can cost a road search
  end
  while #heap > 0 do
    local top = pop(heap)
    local u = top[2]
    if not closed[u] then
      closed[u] = true
      stats.expanded = stats.expanded + 1
      if u == nT then break end
      local vu = VV[u]
      -- walk edges (ground vertices, the start, the bind spot)
      if vu.ground or u == nS then
        local list = ground[vu.cont]
        if list then
          for k = 1, #list do
            local v = list[k]
            if v ~= u then relax(u, v, self:WalkSeconds(vu.cont, vu.wx, vu.wy, V[v].wx, V[v].wy, speed, vu.map, V[v].map), "walk") end
          end
        end
        if vu.cont == T.cont then
          local w = self:WalkSeconds(vu.cont, vu.wx, vu.wy, T.wx, T.wy, speed, vu.map, T.map)
          if u == nS then stats.walk = w end      -- walking all the way: Travel compares against it
          relax(u, nT, w, "walk")
        end
      end
      if u == nS and nH then relax(u, nH, ctx.hearthCost, "hearth") end
      local a = adj[u]
      if a then for k = 1, #a do local e = a[k] relax(u, e[1], e[2], e[3], e[4]) end end
      tick()
    end
  end
  if not g[nT] then return nil, stats end
  -- rebuild the raw edge list
  local raw, v = {}, nT
  while v ~= nS do
    local p = prev[v]
    table.insert(raw, 1, { from = VV[p[1]], to = VV[v], kind = p[2], info = p[3], cost = p[4] })
    v = p[1]
  end
  return { total = g[nT], raw = raw, walk = stats.walk }, stats
end

-- Merge raw edges into legs the guide can show: walk, fly (board + chained flights + land), ship/
-- zeppelin/tram, hearth.
function Route:Legs(raw)
  local legs, i = {}, 1
  while i <= #raw do
    local e = raw[i]
    if e.kind == "board" then
      local leg = { kind = "fly", from = e.from, seconds = e.cost, via = {}, yards = 0, paths = {} }
      i = i + 1
      while raw[i] and raw[i].kind == "fly" do
        leg.seconds = leg.seconds + raw[i].cost
        leg.yards = leg.yards + raw[i].info[4]
        leg.paths[#leg.paths + 1] = raw[i].info      -- RD.legs rows: the trail draws their flight shapes
        leg.via[#leg.via + 1] = raw[i].to.name
        leg.to = raw[i].to
        i = i + 1
      end
      if raw[i] and raw[i].kind == "land" then leg.to = raw[i].to i = i + 1 end
      table.remove(leg.via)
      -- a flight you have taken before: show its measured time (M5 pace; the choice still uses the estimate)
      local P = Panoply.Pace
      local m = P and leg.to and P:FlightTime(leg.from.name, leg.to.name)
      if m then leg.estimate = leg.seconds leg.seconds = self.TAXI_BOARD + m leg.measured = true end
      legs[#legs + 1] = leg
    elseif e.kind == "walk" and e.cost < 0.5 then
      i = i + 1                      -- standing still (start on top of a node)
    else
      local leg = { kind = e.kind, from = e.from, to = e.to, seconds = e.cost }
      if e.kind == "walk" then
        leg.yards = d2(e.from.wx, e.from.wy, e.to.wx, e.to.wy)
        local R = Panoply.Roads
        if R and self.RoadHook == R.Hook and opt("routeRoads") and e.from.cont == e.to.cont and R:Available() then
          local p = R:Path(e.from.cont, e.from.wx, e.from.wy, e.to.wx, e.to.wy, e.from.map, e.to.map)
          leg.yards, leg.points, leg.how, leg.kinds, leg.roadIds, leg.through = p.yards, p.points, p.how, p.kinds, p.ids, p.through
          if p.how == "road" then leg.via = p.names end
        end
      end
      if e.info and e.info.t then leg.wait, leg.upTo, leg.ride, leg.name = e.info.wait, e.info.upTo, e.info.ride, e.info.t[2] end
      if e.info and e.info.t then leg.word = e.info.t[8] end   -- 0.8.4: what it is called when not the kind's own word (a skycutter)
      legs[#legs + 1] = leg
      i = i + 1
    end
  end
  return self:TidyLegs(legs, raw[#raw] and raw[#raw].to)
end

-- 0.7.2 (M3): the card, the trail and the steps all read these legs, so they stay one to one.
--   * a few steps to the flight master or the dock are folded into the ride ("Take the flight at Booty Bay",
--     never "Walk 1 s"); the ride's start stays at the flight master.
--   * a flight whose path passes over the target, followed by a long walk back, says so.
function Route:TidyLegs(legs, target)
  for i = #legs - 1, 1, -1 do
    local l, nx = legs[i], legs[i + 1]
    if l.kind == "walk" and nx.kind ~= "walk" and floor((l.seconds or 0) + 0.5) <= self.SHORT_WALK_S then
      nx.boardWalk = l.seconds
      nx.seconds = nx.seconds + (l.seconds or 0)
      table.remove(legs, i)
    end
  end
  local last, prev = legs[#legs], legs[#legs - 1]
  if last and prev and last.kind == "walk" and prev.kind ~= "walk" and floor((last.seconds or 0) + 0.5) <= self.SHORT_WALK_S then
    prev.landWalk = last.seconds
    prev.seconds = prev.seconds + (last.seconds or 0)
    legs[#legs] = nil
  end
  local RD = self:Data()
  for i = 1, #legs - 1 do
    local l, nx = legs[i], legs[i + 1]
    if l.kind == "fly" and nx.kind == "walk" and i + 1 == #legs and target and target.wx and (nx.yards or 0) > self.BACK_WALK_YD then
      local best
      for _, row in ipairs(l.paths or {}) do
        local pts = RD and RD.Trail and row[5] and RD.Trail(row)
        for k = 1, (pts and #pts or 1) - 1 do
          local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
          local dx, dy = bx - ax, by - ay
          local L = dx * dx + dy * dy
          local t = L > 0 and max(0, min(1, ((target.wx - ax) * dx + (target.wy - ay) * dy) / L)) or 0
          local d = d2(ax + t * dx, ay + t * dy, target.wx, target.wy)
          if not best or d < best then best = d end
        end
      end
      if best and best <= self.OVER_TARGET_YD then l.overTarget = true nx.backFrom = l.to end
    end
  end
  return legs
end

-------------------------------------------------------------------------------
-- Queries: cache, jobs, synchronous run
-------------------------------------------------------------------------------
Route.cache, Route.cacheOrder = {}, {}

local function spot(self, s)
  if s.cont and s.wx then return s end
  local c, wx, wy = self:ToWorld(s.map, s.x, s.y)
  if not c then return nil end
  return { cont = c, wx = wx, wy = wy, map = s.map, x = s.x, y = s.y, name = s.name }
end

function Route:Context()
  -- your own pace (M5): walking times are scaled by the learned travel factor (bounded 0.7 to 1.6)
  local pace = Panoply.Pace and Panoply.Pace:TravelFactor() or 1
  local ctx = { speed = self:GroundSpeed() / pace, pace = pace }
  if opt("routeHearth") and not self.noHearth then   -- 0.7.2: noHearth while the planner models it itself
    local cd = self:HearthCooldown()
    if cd and cd <= 0 then
      ctx.hearth = self:BindSpot()
      ctx.hearthCost = self.HEARTH_CAST + self.HEARTH_LOAD
    end
  end
  return ctx
end

function Route:Key(S, T, ctx)
  return table.concat({ self.epoch, self:Faction(), floor(S.wx / 25), floor(S.wy / 25), S.cont, floor(T.wx / 5), floor(T.wy / 5), T.cont,
    ctx.hearth and (ctx.hearth.name or "?") or "-", floor(ctx.speed * 10), tostring(opt("routeFlights")), tostring(opt("routeTransports")),
    tostring(opt("routeHearth")), tostring(opt("routeRoads")) }, ":")
end

function Route:CacheGet(key)
  local r = self.cache[key]
  if r then
    for i, k in ipairs(self.cacheOrder) do if k == key then table.remove(self.cacheOrder, i) break end end
    self.cacheOrder[#self.cacheOrder + 1] = key
  end
  return r
end

function Route:CachePut(key, r)
  if not self.cache[key] then
    self.cacheOrder[#self.cacheOrder + 1] = key
    while #self.cacheOrder > self.CACHE_SIZE do
      local old = table.remove(self.cacheOrder, 1)
      self.cache[old] = nil
    end
  end
  self.cache[key] = r
end

function Route:ClearCache() self.cache, self.cacheOrder = {}, {} end

-- Make a job: { co, from, to, key, slices = {}, result }. Run it with Route:Resume(job).
function Route:NewJob(from, to)
  local S, T = spot(self, from), spot(self, to)
  if not (S and T and self:Data()) then return nil, "no route data or unknown map" end
  S.name = S.name or "your position"
  -- 0.9.4 (review K1): the destination's own name, else its label, else nothing: the route box then says "Your route" (a made-up
  -- "the target" used to become "Route to the target")
  T.name = T.name or to.label
  local ctx = self:Context()
  local key = self:Key(S, T, ctx)
  local job = { from = S, to = T, key = key, slices = {}, ctx = ctx }
  local hit = self:CacheGet(key)
  if hit then job.result, job.done, job.cached = hit, true, true return job end
  job.co = coroutine.create(function()
    local t0 = clock()
    local function tick()
      if clock() - job.sliceStart >= self.YIELD_MS then coroutine.yield() end
    end
    job.sliceStart = t0
    if Panoply.Roads then Panoply.Roads.tick = tick end
    local G = self:Graph(tick)
    tick()
    local r, stats = self:Search(G, S, T, ctx, tick)
    job.stats = stats
    if r then
      r.legs = self:Legs(r.raw)
      r.raw = nil
      for _, l in ipairs(r.legs) do if l.measured then r.total = r.total + (l.seconds - l.estimate) end end
      r.paceFactor = ctx.pace
      r.from, r.to = S, T
    end
    if Panoply.Roads then Panoply.Roads.tick = nil end
    return r
  end)
  return job
end

-- One slice. Returns true when the job is finished.
function Route:Resume(job)
  if job.done then return true end
  job.sliceStart = clock()
  local ok, r = coroutine.resume(job.co)
  job.slices[#job.slices + 1] = clock() - job.sliceStart
  if not ok then
    job.done, job.err = true, r
    if Panoply.Roads then Panoply.Roads.tick = nil end
    Panoply:Debug("route", r)
    return true
  end
  if coroutine.status(job.co) == "dead" then
    job.done, job.result = true, r or false
    if r then self:CachePut(job.key, r) end
    return true
  end
  return false
end

-- Synchronous: runs every slice now (tests, /panoply route). Returns result, job.
function Route:FindNow(from, to)
  local job, err = self:NewJob(from, to)
  if not job then return nil, err end
  while not self:Resume(job) do end
  return job.result or nil, job
end

-- Asynchronous: one slice per frame through the driver frame; cb(result, job) when done.
Route.queue = {}
function Route:Request(from, to, cb)
  if Panoply:PlayAlong() then if cb then cb(nil) end return nil end   -- 0.7.1: the planner does not run
  -- 0.7.4.1: no route out of an area without a guide. 0.8.4: except to the spot the player picked by hand, and to nothing else.
  if Panoply:NoGuideHere() and not self:HandPickedSpot(to) then if cb then cb(nil) end return nil end
  local job = self:NewJob(from, to)
  if not job then if cb then cb(nil) end return nil end
  job.cb = cb
  if job.done then if cb then cb(job.result, job) end return job end
  self.queue[#self.queue + 1] = job
  self:Driver():Show()
  return job
end

function Route:Driver()
  if self.driver then return self.driver end
  local f = CreateFrame("Frame")
  f:Hide()
  f:SetScript("OnUpdate", function(fr, elapsed) Route:OnUpdate(elapsed) end)
  self.driver = f
  return f
end

-- 0.6.0: background work shares the frame. The router has priority: other sliced jobs (quest
-- icon index) skip any frame while a route is being planned, so two slices never stack.
function Route:Busy()
  return #self.queue > 0 or (self.lastSliceAt ~= nil and self.lastSliceAt == (C.GetTime and C.GetTime() or 0))
end

function Route:OnUpdate(elapsed)
  local job = self.queue[1]
  if job then
    self.lastSliceAt = C.GetTime and C.GetTime() or 0
    if self:Resume(job) then
      table.remove(self.queue, 1)
      if job.cb then pcall(job.cb, job.result, job) end
    end
  end
  self.offClock = (self.offClock or 0) + (elapsed or 0)
  if self.offClock >= 1 then self.offClock = 0 self:Tick(1) end
  if #self.queue == 0 and not self.current and not self.waitPos then self.driver:Hide() end
end

-------------------------------------------------------------------------------
-- Re-plan triggers (SPEC 21.4)
-------------------------------------------------------------------------------
-- 0.8.4 (Go to): in an area without a guide the engine still plans, but only to a spot the player picked by hand: a Go to
-- destination or stop, a waypoint set this session (/way, a map click, a quest pin) or the hand-picked arrow spot. The guide's own
-- target never counts there, so a Skyborne on Zephras Isle is still never sent off the island toward another zone's guide (0.7.4.1).
-- A waypoint left over from an earlier session does not count either (the arrow may still point at it; nothing is planned to it).
function Route:HandPicked()
  local A, W = Panoply.Arrow, Panoply.Waypoints
  if not (A and A.HandTarget) then return nil end
  local m, x, y, label = A:HandTarget()
  if not m then return nil end
  local man = A.manual
  if man and man.m == m and man.x == x and man.y == y then return m, x, y, label end
  local wp = W and W.active and W:Current()
  if wp and wp.m == m and wp.x == x and wp.y == y and ((W.fresh and W.fresh[wp]) or wp.go) then return m, x, y, label end
  return nil
end

-- Is this spot the hand-picked one? (Route:Request's guard in an area without a guide.)
function Route:HandPickedSpot(t)
  local m, x, y = self:HandPicked()
  return (m and t and t.map == m and math.abs((t.x or -1) - x) < 1e-4 and math.abs((t.y or -1) - y) < 1e-4) and true or false
end

-- The spot of a trip the player picked by hand (map, x, y, label), or nil when the route is the guide's own: any waypoint or
-- hand-picked arrow spot the arrow follows, and in an area without a guide only the ones Route:HandPicked allows.
function Route:HandTrip()
  if Panoply:PlayAlong() then return nil end
  if Panoply:NoGuideHere() then return self:HandPicked() end
  local A = Panoply.Arrow
  if not (A and A.HandTarget) then return nil end
  return A:HandTarget()
end

function Route:Enabled()
  if polestar() then return opt("routeEnabled") and not Panoply:PlayAlong() end
  if not (opt("routeEnabled") and self:Available()) or Panoply:PlayAlong() then return false end
  if Panoply:NoGuideHere() then return self:HandPicked() ~= nil end
  return true
end

-- 0.7.1: playing along: drop everything at once (queued jobs, the shown route, the driver frame).
-- One ROUTE_UPDATED clears the trail, the route card and the trip strip; then nothing runs.
function Route:Stop()
  self.gen = (self.gen or 0) + 1
  self.queue = {}
  self.working, self.waitPos, self.pending = nil, nil, nil
  if self.driver then self.driver:Hide() end
  if self.current then self.current = nil Panoply:Fire("ROUTE_UPDATED", "play along") end
end

-- What the route should lead to right now: the guide's own target, or a spot picked by hand
-- (waypoint, clicked quest icon, Professions arrow button) which wins, like on the arrow.
function Route:WantedTarget()
  if not (Panoply.Engine and Panoply.Engine.Target) then return nil end
  -- 0.8.4: in an area without a guide only a hand-picked spot is a target (Route:HandPicked), never the guide's
  if Panoply:NoGuideHere() then return self:HandPicked() end
  -- the guide's own target: a travel step ("Fly to X") is made from this route, so it must not feed back
  local m, x, y, label = (Panoply.Engine.GuideTarget or Panoply.Engine.Target)(Panoply.Engine)
  local A = Panoply.Arrow
  if A and A.HandTarget then
    local hm, hx, hy, hl = A:HandTarget()
    if hm then m, x, y, label = hm, hx, hy, hl end
  end
  return m, x, y, label
end

-- 0.6.1 stale-trip fix: does this route still lead to what the guide wants now? A route is only
-- shown (trip strip, ETA under the arrow, trail) while it ends at the current target.
local function sameSpot(t, m, x, y)
  return t and m and t.map == m and math.abs((t.x or -1) - (x or -2)) < 1e-4 and math.abs((t.y or -1) - (y or -2)) < 1e-4
end
Route.VALID_YD = 10
function Route:Valid(r)
  r = r or self.current
  if r and r.ps then return polestar() end   -- Polestar's route is for Polestar's own target, always
  local t = r and (r.target or r.to)
  if not (t and t.map) then return false end
  local m, x, y = self:WantedTarget()
  if not m then return false end
  if sameSpot(t, m, x, y) then return true end
  local c1, ax, ay = self:ToWorld(t.map, t.x, t.y)
  local c2, bx, by = self:ToWorld(m, x, y)
  return (c1 and c1 == c2 and d2(ax, ay, bx, by) <= self.VALID_YD) and true or false
end

-- Drop the shown route at once (plan swap, step change, zone change, teleport): the strip says
-- "Working out route..." until the new one is ready, never the old plan's numbers. Any job still
-- running for the old target is ignored when it finishes (the generation no longer matches).
function Route:Invalidate(reason)
  if Panoply:PlayAlong() then return end
  if polestar() then return end
  self.gen = (self.gen or 0) + 1
  local had = self.current ~= nil
  self.current = nil
  -- a replan follows right away; until it is done the strip shows "Working out route..."
  self.working = (self:Enabled()) and { pending = reason } or nil
  if had then Panoply:Fire("ROUTE_UPDATED", reason) end
end

function Route:Replan(reason)
  if Panoply:PlayAlong() then return end   -- 0.7.1: no route planning, no route events
  self.lastReason = reason
  if polestar() then Panoply.PolestarEngine:SyncRoute(reason) return end   -- Polestar plans; we take its route over
  if not (Panoply.Engine and Panoply.Engine.Target) then return end
  if C.InCombat and C.InCombat() then
    self.pending = reason
    -- 0.8.4 (mid-trip change in a fight): nothing is planned in combat, but a route to a stop that is no longer the next one is
    -- dropped at once, so the travel step, the trip strip and the arrow never show the old trip until the fight ends
    if self.current and not self:Valid(self.current) then
      self.gen = (self.gen or 0) + 1
      self.current = nil
      Panoply:Fire("ROUTE_UPDATED", reason)
    end
    return
  end
  local m, x, y, label = self:WantedTarget()
  local pm, px, py = C.GetPlayerPos()
  -- 0.6.0 arrow fix: no position yet (a loading screen, or the moment right after a zone change): try again on
  -- the next once-a-second tick instead of waiting for the next step change.
  self.waitPos = (m and not pm and self:Enabled()) and reason or nil
  if self.waitPos then self:Driver():Show() end
  if not (m and pm) or not self:Enabled() then
    self.gen = (self.gen or 0) + 1
    self.working = nil
    if self.current then self.current = nil Panoply:Fire("ROUTE_UPDATED", reason) end
    return
  end
  self.replans = (self.replans or 0) + 1
  self.gen = (self.gen or 0) + 1
  local gen, target = self.gen, { map = m, x = x, y = y }
  -- the old route no longer fits once the target moved: drop it now rather than show it meanwhile
  if self.current and not sameSpot(self.current.target, m, x, y) then self.current = nil Panoply:Fire("ROUTE_UPDATED", reason) end
  self.working = target
  -- jobs still queued for an older plan or target would only delay this one: drop them
  for i = #self.queue, 1, -1 do
    local q = self.queue[i]
    if q.gen and q.gen < gen then table.remove(self.queue, i) self.discarded = (self.discarded or 0) + 1 end
  end
  local job = self:Request({ map = pm, x = px, y = py }, { map = m, x = x, y = y, label = label }, function(r)
    -- 0.6.1: a job that finishes after the plan, the step or the target changed is thrown away
    if gen ~= self.gen then self.discarded = (self.discarded or 0) + 1 return end
    local wm, wx, wy = self:WantedTarget()
    if not sameSpot(target, wm, wx, wy) then self.discarded = (self.discarded or 0) + 1 self:Replan("target moved") return end
    self.working = nil
    if r then r.target = target end
    self.current = r or nil
    self.offFor = 0
    Panoply:Fire("ROUTE_UPDATED", reason)
  end)
  if job and not job.done then job.gen = gen end
end

-- 0.6.1: the time under the arrow. The route's total when it fits, but never more than a plain
-- walk could explain for a short hop (same continent, under 150 yd straight): then the walk time.
Route.SANITY_YD = 150
function Route:StraightWalk()
  local m, x, y = self:WantedTarget()
  local pm, px, py = C.GetPlayerPos()
  if not (m and pm) then return nil end
  local c1, ax, ay = self:ToWorld(pm, px, py)
  local c2, bx, by = self:ToWorld(m, x, y)
  if not (c1 and c1 == c2) then return nil end
  local d = sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
  return d, d / max(1, self:GroundSpeed())
end
function Route:StepETA()
  local r = self.current
  if not (r and r.total and self:Valid(r)) then return nil end
  if r.ps then return r.total end   -- Polestar's plan is timed by Polestar
  local d, walk = self:StraightWalk()
  if d and d < self.SANITY_YD and r.total > walk * 3 + 20 then
    self.sanityFixes = (self.sanityFixes or 0) + 1
    return walk, true
  end
  return r.total
end

-- Known flight paths or bind/hearth state changed: drop the static graph and cached routes.
function Route:Changed(reason)
  if Panoply:PlayAlong() then return end
  self:Bump(reason)
  self:ClearCache()
  self:Replan(reason)
end

function Route:KnownSignature()
  local k, n = Panoply.cdb and Panoply.cdb.knownTaxi or {}, 0
  for _ in pairs(k) do n = n + 1 end
  return n
end

-- Distance (yd) from a world point to the current route's ground polyline on that continent, and the
-- nearest point on it (wx, wy); the trail's off-trail cue points there.
function Route:OffTrail(cont, wx, wy)
  local r = self.current
  if not r then return nil end
  local best, nx, ny
  for _, l in ipairs(r.legs) do
    if l.kind == "walk" and l.from.cont == cont and l.to.cont == cont then
      local pts = l.points or { { l.from.wx, l.from.wy }, { l.to.wx, l.to.wy } }
      for k = 1, #pts - 1 do
        local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
        local dx, dy = bx - ax, by - ay
        local L = dx * dx + dy * dy
        local t = L > 0 and max(0, min(1, ((wx - ax) * dx + (wy - ay) * dy) / L)) or 0
        local qx, qy = ax + t * dx, ay + t * dy
        local d = d2(wx, wy, qx, qy)
        if not best or d < best then best, nx, ny = d, qx, qy end
      end
    end
  end
  return best, nx, ny
end

-- 0.7.3.1 bend weight (0..1) for the walk point s yd along a walk len yd long, when the player stands
-- d yd off the walk and nearest to it at s0 yd along (see NUDGE_FULL_YD above).
function Route.NudgeWeight(d, s, s0, len)
  local full, off = Route.NUDGE_FULL_YD, Route.OFF_TRAIL_YD
  local g = d <= full and 1 or (off - d) / (off - full)
  if g <= 0 then return 0 end
  local flat, reach = Route.NUDGE_FLAT_YD, Route.NUDGE_REACH_YD
  local h = min(1, (reach - math.abs(s - s0)) / (reach - flat))
  if h <= 0 then return 0 end
  local e = min(1, s / Route.NUDGE_END_YD, (len - s) / Route.NUDGE_END_YD)
  if e <= 0 then return 0 end
  return g * h * e
end

-- Called once a second: learn speed, watch the bind/hearth state and the off-trail timer.
function Route:Tick(dt)
  if Panoply:PlayAlong() then return end
  if polestar() then return end
  self:LearnSpeed()
  if self.waitPos and C.GetPlayerPos() then local r = self.waitPos self.waitPos = nil self:Replan(r) end
  local bind = C.BindLocation and C.BindLocation()
  if bind ~= self.lastBind then
    local first = self.lastBind == nil
    self.lastBind = bind
    if not first then self:Changed("bind") return end
  end
  local cd = self:HearthCooldown()
  local ready = cd ~= nil and cd <= 0
  if ready ~= self.lastReady then
    local first = self.lastReady == nil
    self.lastReady = ready
    if not first then self:ClearCache() self:Replan("hearth cooldown") return end
  end
  if not self.current or C.OnTaxi() or (C.InInstance and C.InInstance()) then self.offFor = 0 return end
  local pm, px, py = C.GetPlayerPos()
  if not pm then return end
  local c, wx, wy = self:ToWorld(pm, px, py)
  local d = c and self:OffTrail(c, wx, wy)
  if d and d > self.OFF_TRAIL_YD then
    self.offFor = (self.offFor or 0) + (dt or 1)
    if self.offFor >= self.OFF_TRAIL_SECONDS then self.offFor = 0 self:Replan("off trail") end
  else
    self.offFor = 0
  end
end

local ROUTE_KEYS = { routeEnabled = true, routeFlights = true, routeHearth = true, routeTransports = true, routeRoads = true,
                     routeLearnFP = true, routeSteps = true, paceLearn = true }

function Route:Register()
  Panoply:Listen("STEP_CHANGED", function(i, reason)
    -- a travel step appearing or going away does not move the guide's target (Travel replans itself after a trip)
    if reason == "travel" or reason == "travel done" then return end
    Route:Invalidate("step")
    Route:Replan("step")
  end)
  -- 0.6.1 stale-trip fix: a new plan (Replan, plan switch, partner plan, inserted steps) changes the
  -- step list without a STEP_CHANGED when the index stays at 1; the old route was kept and shown.
  Panoply:Listen("STEPS_CHANGED", function() Route:Invalidate("plan") Route:Replan("plan") end)
  Panoply:Listen("OPTION_CHANGED", function(key) if ROUTE_KEYS[key] then Route:Changed("settings") end end)
  -- 0.8.4: walking into (or out of) an area without a guide drops the route (NoGuide:Clear); a hand-picked trip is planned again
  -- from there, and the guide's own route stays off (Route:Enabled)
  Panoply:Listen("NOGUIDE_CHANGED", function() Route:Replan("no guide area") end)
  Panoply:On("TAXIMAP_OPENED", function()
    -- Automation records the known flight paths on the same event; compare after it ran
    local n = Route:KnownSignature()
    if n ~= Route.knownCount then Route.knownCount = n Route:Changed("new flight path") end
  end)
  Panoply:On("UI_INFO_MESSAGE", function()
    local n = Route:KnownSignature()
    if n ~= Route.knownCount then Route.knownCount = n Route:Changed("new flight path") end
  end)
  Panoply:On("ZONE_CHANGED_NEW_AREA", function() Route:Invalidate("zone") Route:Replan("zone") end)
  -- a loading screen (hearthstone, portal, instance, boat between continents): the start moved
  Panoply:On("PLAYER_ENTERING_WORLD", function(login, reload)
    if login or reload then return end
    Route:Invalidate("teleport") Route:Replan("teleport")
  end)
  Panoply:On("BAG_UPDATE_COOLDOWN", function() Route:Tick(0) end)
  Panoply:On("PLAYER_REGEN_ENABLED", function() if Route.pending then local r = Route.pending Route.pending = nil Route:Replan(r) end end)
  -- binding at an innkeeper: remember where the player stood (exact bind spot, own data)
  local function bound()
    local pm, px, py = C.GetPlayerPos()
    local name = C.BindLocation and C.BindLocation()
    if pm and name and Panoply.cdb then
      local c, wx, wy = Route:ToWorld(pm, px, py)
      if c then Panoply.cdb.bindSpot = { name = name, cont = c, wx = wx, wy = wy, map = pm, x = px, y = py } end
    end
    Route.lastBind = name
    Route:Changed("bind")
  end
  Panoply:On("HEARTHSTONE_BOUND", bound)
  self.knownCount = self:KnownSignature()
end

-------------------------------------------------------------------------------
-- Plain words
-------------------------------------------------------------------------------
local function dur(s)
  s = floor(s + 0.5)
  if s < 60 then return s .. " s" end
  local m = floor(s / 60)
  if m < 60 then return (s % 60 == 0) and (m .. " min") or (m .. " min " .. (s % 60) .. " s") end
  return floor(m / 60) .. " h " .. (m % 60) .. " min"
end
Route.Duration = dur

local function yd(n)
  n = floor(n + 0.5)
  if n >= 1000 then return ("%d,%03d yd"):format(floor(n / 1000), n % 1000) end
  return n .. " yd"
end

local function place(v)
  local n = v and v.name
  if type(n) ~= "string" or not n:find("%S") then n = "the next stop" end   -- 0.9.4: never "?"
  return (n:gsub(",.*$", ""):gsub(" %(.*%)$", ""))
end
local STOP = { tram = "the Deeprun Tram entrance in %s", ship = "the ship dock at %s", zeppelin = "the zeppelin tower at %s",
               portal = "the portal in %s", skycutter = "the skycutter dock at %s" }

function Route:Describe(r)
  if not r then return { "No route found." } end
  local out = { ("%s to %s: about %s."):format(place(r.from), place(r.to), dur(r.total)) }
  for i, l in ipairs(r.legs) do
    local s
    if l.kind == "walk" then
      local where = (l.to.kind == "fp" and ("the flight master%s in %s"):format(l.to.npcName ~= "" and (" " .. l.to.npcName) or "", place(l.to)))
        or (l.to.kind == "dock" and (STOP[l.to.transport[8] or l.to.transport[3]] or "%s"):format(place(l.to)))
        or place(l.to)
      local road = ""
      if l.how == "road" and l.via then
        local names, skip = {}, { [place(l.to)] = true, [place(l.from)] = true }
        for _, t in ipairs(l.through or {}) do skip[t] = true end
        local all = {}
        for _, n in ipairs(l.via) do if not skip[n] then all[#all + 1] = n end end
        -- at most three names, spread over the walk (first, middle, last)
        if #all <= 3 then names = all else names = { all[1], all[floor((#all + 1) / 2)], all[#all] } end
        road = (l.kinds and l.kinds.road == nil and l.kinds.trail) and " along the trail" or " along the road"
        if #names == 1 then road = road .. " via " .. names[1]
        elseif #names > 1 then road = road .. " via " .. table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names] end
        -- named tunnels are always said, so players know where the way goes underground
        local seenT = {}
        for _, t in ipairs(l.through or {}) do
          if not seenT[t] then seenT[t] = true road = road .. (#names > 0 and ", " or " ") .. "through " .. t end
        end
      end
      s = ("Walk%s to %s%s (%s, %s)."):format(i == 1 and "" or " on", where, road, yd(l.yards), dur(l.seconds))
    elseif l.kind == "fly" then
      s = ("Fly from %s to %s (%s, about %s). Talk to the flight master and pick %s yourself.%s"):format(place(l.from), place(l.to),
        yd(l.yards), dur(l.seconds), place(l.to), (#l.via > 0 and (" The flight passes " .. table.concat(l.via, ", ", 1) .. ".") or "")
        .. (l.overTarget and " The flight passes over the target; you cannot get off on the way, so you walk back." or ""))
      s = s:gsub("^Fly from (.-) to", "Take the flight at %1 to")
    elseif l.kind == "hearth" then
      s = ("Use your hearthstone to %s (about %s with the loading screen)."):format(l.to.name or "your inn", dur(l.seconds))
    elseif l.kind == "portal" then
      s = ("Step through the portal in %s to %s (about %s)."):format(place(l.from), place(l.to), dur(l.seconds))
    else
      local what = (l.kind == "tram") and "the Deeprun Tram" or ("the " .. (l.word or l.kind))
      s = ("Take %s from %s to %s: wait about %s (up to %s), ride %s%s."):format(what, place(l.from), place(l.to), dur(l.wait), dur(l.upTo),
        dur(l.ride), l.kind == "tram" and " with the loading screens" or "")
    end
    out[#out + 1] = i .. ". " .. s
  end
  return out
end
