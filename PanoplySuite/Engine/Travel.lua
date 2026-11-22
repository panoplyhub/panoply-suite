-- Panoply Suite Travel steps (0.6.0 M5, SPEC section 21.5): "Fly to X", "Take the boat to Y", "Hearth to Z".
-- Own code. When the fastest way to the guide's next target uses a flight, a boat, a zeppelin, the tram, a
-- portal or the hearthstone, and that saves real time, a short travel step is shown before the levelling
-- step. The plan itself is not changed: the step lives beside it (Engine.travel) and goes away when you
-- board, arrive, skip it, or the route changes. It only advises: it never opens or picks a flight for you.
-- Optional: "Remind me to learn new flight paths" adds a stop at a flight master the route walks past.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Travel = {}
Panoply.Travel = Travel
local floor, max, sqrt = math.floor, math.max, math.sqrt

Travel.MIN_SAVE_S = 30        -- a travel step must save at least this much...
Travel.MIN_SAVE_FRAC = 0.10   -- ...and this share of the walking time
Travel.LEARN_NEAR_YD = 80     -- a flight master this close to the walk is "on the way"
Travel.ARRIVE_YD = 40
Travel.FP_RADIUS = 8          -- yd: standing at the flight master
Travel.DOCK_RADIUS = 15

local function opt(key, default)
  local db = Panoply.db
  if not db or db[key] == nil then return default end
  return db[key] ~= false
end

-- a stop's name without its zone. 0.9.4: never "?" (the route box read "Route to ?"): a stop with no name is "the next stop"
local function place(v)
  local n = v and v.name
  if type(n) ~= "string" or not n:find("%S") then n = "the next stop" end
  return (n:gsub(",.*$", ""):gsub(" %(.*%)$", ""))
end
Travel.Place = place

local function dur(s) return Panoply.Route.Duration(s) end

local VEHICLE = { ship = "boat", zeppelin = "zeppelin", tram = "tram", portal = "portal" }
local STOP = { ship = "the ship dock at %s", zeppelin = "the zeppelin tower at %s", tram = "the Deeprun Tram in %s", portal = "the portal in %s",
               skycutter = "the skycutter dock at %s" }
-- 0.8.4: what a ride is called: the transport's own word when the route data gives one (a skycutter), else the kind's
local function vehicle(leg) return leg.word or VEHICLE[leg.kind] or leg.kind end
local function stop(leg) return STOP[leg.word or leg.kind] or "%s" end

-- The first leg that is not walking, and its index.
function Travel:FirstTransit(r)
  for i, l in ipairs(r and r.legs or {}) do
    if l.kind ~= "walk" then return l, i end
  end
  return nil
end

-- Does the route save enough over walking to be worth a step? (Walking is impossible across continents.)
function Travel:Worth(r)
  if not r or not r.total then return false end
  if not r.walk then return true end
  return r.walk - r.total >= max(self.MIN_SAVE_S, self.MIN_SAVE_FRAC * r.walk)
end

-- Seconds of the trip from the transit leg on (what the "why" line compares).
local function onwards(r, i)
  local s = 0
  for k = i, #r.legs do s = s + (r.legs[k].seconds or 0) end
  return s
end

local function why(leg, r, i)
  local walk = r.walk
  local onW = walk and (" against %s on foot"):format(dur(walk)) or ""
  local k = leg.kind
  if k == "fly" then
    local air = leg.seconds - (Panoply.Route.TAXI_BOARD or 0)
    if not walk then return ("Flying is the quickest way there: about %s in the air."):format(dur(air)) end
    return ("Flying is faster: about %s in the air%s.%s"):format(dur(air), onW,
      leg.overTarget and " The flight passes over the target; you cannot get off on the way, so you walk back." or "")
  elseif k == "hearth" then
    return ("Your hearthstone is faster: about %s with the loading screen%s."):format(dur(leg.seconds), onW)
  elseif k == "portal" then
    return ("The portal is faster: about %s%s."):format(dur(onwards(r, i)), onW)
  else
    local what = "the " .. vehicle(leg)
    if not walk then
      return ("%s is the way across: wait about %s (up to %s), ride about %s."):format(what:gsub("^t", "T"), dur(leg.wait or 0),
        dur(leg.upTo or 0), dur(leg.ride or 0))
    end
    return ("%s is faster: about %s with the wait%s."):format(what:gsub("^t", "T"), dur(onwards(r, i)), onW)
  end
end

-- Build the step for one transit leg. Goals: a goto to where you board (the arrow and trail lead there) and a
-- plain confirm ("I've done it"). No "fly" goal: those are for the old auto-fly option, which this never uses.
function Travel:BuildStep(leg, r, i, idx)
  local k, from, to = leg.kind, leg.from, leg.to
  local step = { isTravel = true, kind = k, leg = leg, trip = r, guideIndex = idx, goals = {} }
  step.key = ("%s:%s>%s:%d"):format(k, place(from), place(to), idx)
  step.why = why(leg, r, i)
  local g = step.goals
  if k == "fly" then
    step.title = ("Take the flight at %s to %s"):format(place(from), place(to))
    local who = (from.npcName and from.npcName ~= "") and ("Talk to %s (flight master)"):format(from.npcName)
      or ("Talk to the flight master in %s"):format(place(from))
    g[1] = { type = "goto", mapID = from.map, x = from.x, y = from.y, radius = self.FP_RADIUS, text = who }
    g[2] = { type = "confirm", text = ("Choose %s on the flight map"):format(place(to)) }
  elseif k == "hearth" then
    step.title = "Hearth to " .. place(to)
    g[1] = { type = "confirm", text = ("Use your hearthstone (it takes you to %s)"):format(to.name or "your inn") }
  else
    step.title = ("Take the %s to %s"):format(vehicle(leg), place(to))
    g[1] = { type = "goto", mapID = from.map, x = from.x, y = from.y, radius = self.DOCK_RADIUS,
             text = "Go to " .. stop(leg):format(place(from)) }
    local ride = k == "portal" and ("Step through the portal to %s"):format(place(to))
      or k == "tram" and ("Ride the tram to %s"):format(place(to))
      or ("Board the %s to %s (it comes about every %s)"):format(vehicle(leg), place(to), dur(leg.upTo or 0))
    g[2] = { type = "confirm", text = ride }
  end
  return step
end

-- A flight master you have not met, on (or right beside) the route's first walk: { name, map, x, y, npcName }.
function Travel:LearnStop(r)
  if not opt("routeLearnFP", true) or not opt("routeFlights", true) then return nil end
  local RD = Panoply.Route:Data()
  local leg = r and r.legs and r.legs[1]
  if not (RD and leg and leg.kind == "walk" and leg.from.cont == leg.to.cont) then return nil end
  local pts = leg.points or { { leg.from.wx, leg.from.wy }, { leg.to.wx, leg.to.wy } }
  local fac = Panoply.Route:Faction()
  local best, bd
  for id, n in pairs(RD.nodes) do
    if n[3] == leg.from.cont and (n[2] == "N" or n[2] == fac) and not Panoply.Route:Known(n[1]) and n[6] then
      for k = 1, #pts - 1 do
        local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
        local dx, dy = bx - ax, by - ay
        local L = dx * dx + dy * dy
        local t = L > 0 and math.max(0, math.min(1, ((n[4] - ax) * dx + (n[5] - ay) * dy) / L)) or 0
        local qx, qy = ax + t * dx - n[4], ay + t * dy - n[5]
        local d = sqrt(qx * qx + qy * qy)
        if d <= self.LEARN_NEAR_YD and (not bd or d < bd) then best, bd = n, d end
      end
    end
  end
  if not best then return nil end
  return { name = best[1], map = best[6], x = best[7], y = best[8], npcName = best[10] }
end

function Travel:BuildLearnStep(n, r, idx)
  local step = { isTravel = true, kind = "learn", trip = r, guideIndex = idx }
  step.key = ("learn:%s:%d"):format(n.name, idx)
  step.title = "Learn the flight path at " .. place(n)
  step.why = "It is on your way, and it will make later trips faster."
  local who = (n.npcName and n.npcName ~= "") and ("Talk to %s (flight master)"):format(n.npcName) or "Talk to the flight master"
  step.goals = {
    { type = "goto", mapID = n.map, x = n.x, y = n.y, radius = self.FP_RADIUS, text = who },
    { type = "fpath", node = n.name, text = "Learn the flight path" },
  }
  return step
end

Travel.dismissed = {}

-- What the guide should show now (called whenever the route changes).
function Travel:Evaluate(reason)
  local E = Panoply.Engine
  if not E then return end
  if Panoply:PlayAlong() then self:Show(nil) return end   -- 0.7.1: no travel steps without the guide
  -- WoW Forever with Polestar's engine: its travel step comes from Polestar's own plan (PolestarEngine:SyncTravel)
  if Panoply.PolestarEngine and Panoply.PolestarEngine:Active() then return end
  local idx = E.index
  local want
  if opt("routeSteps", true) and not E.detour and E.steps[idx] and not C.OnTaxi() and Panoply.Route then
    local r = Panoply.Route.current
    -- 0.6.1: never build a "Fly to" step from a route that ends somewhere else (an old plan's)
    if r and Panoply.Route.Valid and not Panoply.Route:Valid(r) then r = nil end
    if r then
      local n = self:LearnStop(r)
      if n then
        local s = self:BuildLearnStep(n, r, idx)
        if not self.dismissed[s.key] then want = s end
      end
      if not want then
        local leg, i = self:FirstTransit(r)
        if leg and self:Worth(r) then
          local s = self:BuildStep(leg, r, i, idx)
          if not self.dismissed[s.key] then want = s end
        end
      end
    end
  end
  self:Show(want)
end

function Travel:Show(step)
  local E = Panoply.Engine
  local old = E.travel
  if old and step and old.key == step.key then
    -- same step, newer route: keep the object (and its goal states), refresh the times
    old.trip, old.leg, old.why = step.trip, step.leg or old.leg, step.why
    Panoply:Fire("STEP_UPDATED")
    return
  end
  if not old and not step then return end
  E.travel = step
  if step then step.startedAt = C.GetTime() end
  Panoply:Fire("STEP_CHANGED", E.index, step and "travel" or "travel done")
end

-- "Skip" or "I've done it": hide this travel step until the guide moves to another step.
function Travel:Dismiss(why)
  local E = Panoply.Engine
  local s = E and E.travel
  if not s then return end
  if s.ps then Panoply.PolestarEngine:SkipLeg() return end   -- Polestar's leg: Polestar leaves it out or moves on
  self.dismissed[s.key] = true
  self:Show(nil)
end

-- Once a second: goal states, and boarding / arriving.
function Travel:Tick(dt)
  if Panoply.Pace then
    Panoply.Pace:TickTrip(dt)
    Panoply.Pace:TickXP(dt)
  end
  local taxi = C.OnTaxi()
  if self.wasTaxi and not taxi then
    if Panoply.Pace then Panoply.Pace:FlightEnded() end
    if Panoply.Route then Panoply.Route:Replan("landed") end
  end
  self.wasTaxi = taxi
  local E = Panoply.Engine
  local s = E and E.travel
  if not s then return end
  if s.ps then return end   -- Polestar's travel step: Polestar sees the boarding and the arrival itself
  if s.guideIndex ~= E.index or E.detour then self:Show(nil) return end
  local State = Panoply.State
  for _, g in ipairs(s.goals) do g.status = Panoply.Goals.Status(g, State) end
  if self:Finished(s, taxi) then
    self.dismissed[s.key] = true
    self:Show(nil)
    if Panoply.Route then Panoply.Route:Replan("travel done") end
  else
    E:Updated()   -- 0.9.5 phase 4A4: once a second, so only when the travel step's goals or what the window shows changed
  end
end

function Travel:Finished(s, taxi)
  local k = s.kind
  if k == "learn" then return s.goals[2].status == Panoply.Goals.DONE end
  if k == "fly" then
    if taxi then
      if Panoply.Pace then Panoply.Pace:FlightStarted(s.leg) end
      return true
    end
    return false
  end
  local pm, px, py = C.GetPlayerPos()
  local c, wx, wy
  if pm then c, wx, wy = Panoply.Route:ToWorld(pm, px, py) end
  local to, from = s.leg.to, s.leg.from
  if not c then s.away = true return false end         -- inside the tram or a loading screen
  if c ~= from.cont and c == to.cont then return true end
  local dx, dy = wx - to.wx, wy - to.wy
  if c == to.cont and dx * dx + dy * dy <= self.ARRIVE_YD * self.ARRIVE_YD then return true end
  if s.away and c == to.cont and k == "tram" then return true end
  return false
end

-- 0.8.4 (Go to): the turn-by-turn words of a route, one entry per leg, for a trip the player picked by hand (Modules/Map/Navigate.lua
-- lists them in the Go to window and says the next one in chat). The same words as the travel steps above, so a trip reads the same
-- with or without a levelling guide: { { text = "Take the boat to Theramore", detail = "Wait about 2 min 45 s ...", kind, seconds } }.
local function yards(n)
  n = floor((n or 0) + 0.5)
  if n >= 1000 then return ("%d,%03d yd"):format(floor(n / 1000), n % 1000) end
  return n .. " yd"
end
function Travel:Advice(r)
  local out = {}
  for i, leg in ipairs(r and r.legs or {}) do
    local k, from, to = leg.kind, leg.from, leg.to
    local text, detail
    if k == "walk" then
      local where = (to.kind == "fp" and (((to.npcName and to.npcName ~= "") and (to.npcName .. ", the flight master in %s") or "the flight master in %s"):format(place(to))))
        or (to.kind == "dock" and (STOP[to.transport[8] or to.transport[3]] or "%s"):format(place(to)))
        or place(to)
      text = (i == 1 and "Go to " or "Go on to ") .. where
      local road = ""
      if leg.how == "road" then
        road = (leg.kinds and leg.kinds.road == nil and leg.kinds.trail) and "Along the trail" or "Along the road"
        local via = {}
        for _, n in ipairs(leg.via or {}) do if n ~= place(to) and n ~= place(from) and #via < 3 then via[#via + 1] = n end end
        if #via > 0 then road = road .. " via " .. table.concat(via, ", ") end
        road = road .. ". "
      end
      detail = ("%s%s, about %s."):format(road, yards(leg.yards), dur(leg.seconds or 0))
    elseif k == "fly" then
      text = ("Take the flight at %s to %s"):format(place(from), place(to))
      detail = ("Talk to the flight master and choose %s. About %s%s."):format(place(to), dur(leg.seconds or 0),
        leg.overTarget and "; it passes over where you are going, so you walk back" or "")
    elseif k == "hearth" then
      text = "Hearth to " .. place(to)
      detail = ("Use your hearthstone. About %s with the loading screen."):format(dur(leg.seconds or 0))
    elseif k == "portal" then
      text = ("Step through the portal to %s"):format(place(to))
      detail = ("At %s. About %s."):format(stop(leg):format(place(from)), dur(leg.seconds or 0))
    elseif k == "tram" then
      text = ("Ride the tram to %s"):format(place(to))
      detail = ("Wait about %s (up to %s), ride about %s."):format(dur(leg.wait or 0), dur(leg.upTo or 0), dur(leg.ride or 0))
    else
      text = ("Take the %s to %s"):format(vehicle(leg), place(to))
      detail = ("Board at %s. Wait about %s (up to %s), ride about %s."):format(stop(leg):format(place(from)), dur(leg.wait or 0),
        dur(leg.upTo or 0), dur(leg.ride or 0))
    end
    out[#out + 1] = { text = text, detail = detail, kind = k, seconds = leg.seconds or 0 }
  end
  return out
end

-- Trip time of the current step (seconds) and the route; nil when no route.
function Travel:TripTotal()
  local r = Panoply.Route and Panoply.Route.current
  if r and Panoply.Route.Valid and not Panoply.Route:Valid(r) then r = nil end
  return r and r.total or nil, r
end

function Travel:Register()
  Panoply:Listen("ROUTE_UPDATED", function(reason) Travel:Evaluate(reason) end)
  Panoply:Listen("STEP_CHANGED", function(i, reason)
    if reason ~= "travel" and reason ~= "travel done" then
      Travel.dismissed = {}
      local E = Panoply.Engine
      if E.travel and E.travel.guideIndex ~= E.index then E.travel = nil end
    end
  end)
  -- when the route is replanned for a new step, the walk of its first leg is timed (your pace)
  Panoply:Listen("ROUTE_UPDATED", function(reason)
    if Panoply.Pace and Panoply.Route.current and not C.OnTaxi() then Panoply.Pace:StartTrip(Panoply.Route.current, reason) end
  end)
end
