-- Panoply Suite Pace (0.6.0 M5, SPEC section 21.6): your own pace, learned while you play. Own code.
--   * Travel pace: how your real walking times compare with the router's estimates. Learned from walks that
--     ended where the route said (no combat, no AFK, no detours); bounded to PACE_MIN..PACE_MAX so one odd
--     trip cannot throw the times off. The router divides its ground speed by this factor.
--   * Flight times: the real time of each flight you take (from take-off to landing), kept per route.
--   * Experience pace: experience per hour of active play, smoothed (half-life 45 min), with rested bonus
--     experience and AFK time left out. Until 20 minutes are learned the plan's own estimate is used.
-- Everything is reset with "Forget my pace" (Guide > Trip times, or /panoply pace reset).
-- Advice only: nothing here moves the character.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Pace = {}
Panoply.Pace = Pace
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

Pace.PACE_MIN, Pace.PACE_MAX = 0.7, 1.6   -- travel factor bounds (1 = the router's estimate)
Pace.SAMPLE_MIN, Pace.SAMPLE_MAX = 0.4, 3.0  -- a trip outside this ratio is thrown away (lost, waited, ported)
Pace.WEIGHT = 0.25                          -- weight of one new trip
Pace.MIN_TRIP_S = 30                        -- shorter walks are too noisy to learn from
Pace.ARRIVE_YD = 30
Pace.FLIGHT_MIN, Pace.FLIGHT_MAX = 0.6, 1.8 -- a measured flight is kept only within this ratio of the estimate
Pace.XP_HALF_LIFE = 45 * 60                 -- s of active play
Pace.XP_WARMUP = 20 * 60                    -- s of active play before your own pace is used
Pace.XP_WINDOW = 5 * 60                     -- one sample per 5 min of active play
Pace.IDLE_S = 5 * 60                        -- no movement and no experience for this long: not counted

local function store()
  local c = Panoply.cdb
  if not c then return nil end
  if type(c.pace) ~= "table" then c.pace = {} end
  local p = c.pace
  p.travel = tonumber(p.travel) or 1
  p.travelN = tonumber(p.travelN) or 0
  p.xphActive = tonumber(p.xphActive) or 0
  if type(p.flights) ~= "table" then p.flights = {} end
  return p
end
Pace.Store = store

local function clamp(v, a, b) return max(a, min(b, v)) end

-------------------------------------------------------------------------------
-- Travel factor
-------------------------------------------------------------------------------
function Pace:Learning() return not (Panoply.db and Panoply.db.paceLearn == false) end

-- Factor applied to walking times (1 = as estimated; 1.2 = you take 20% longer).
function Pace:TravelFactor()
  local p = store()
  if not p or not self:Learning() then return 1 end
  return clamp(p.travel, self.PACE_MIN, self.PACE_MAX)
end

-- One finished walk: predicted seconds at factor 1 and the real seconds. Returns the new factor or nil.
function Pace:AddTrip(predicted, actual)
  local p = store()
  if not p or not predicted or not actual or predicted < self.MIN_TRIP_S then return nil end
  local r = actual / predicted
  if r < self.SAMPLE_MIN or r > self.SAMPLE_MAX then return nil end
  r = clamp(r, self.PACE_MIN, self.PACE_MAX)
  local w = p.travelN == 0 and 0.5 or self.WEIGHT
  p.travel = clamp(p.travel + (r - p.travel) * w, self.PACE_MIN, self.PACE_MAX)
  p.travelN = p.travelN + 1
  Panoply:Fire("PACE_CHANGED", "travel")
  return p.travel
end

-- The walk being timed: the route's first walk (to the flight master, the dock or the target).
function Pace:StartTrip(r, reason)
  if not r or not r.legs or not self:Learning() then self.trip = nil return end
  local leg = r.legs[1]
  if not leg or leg.kind ~= "walk" or not leg.seconds then self.trip = nil return end
  -- same destination (a zone change, a refreshed route): keep timing the walk already under way
  local t = self.trip
  if t and reason ~= "off trail" and t.cont == leg.to.cont and math.abs(t.to.wx - leg.to.wx) < 5 and math.abs(t.to.wy - leg.to.wy) < 5 then return end
  self.trip = nil
  local f = (r.paceFactor or 1)
  self.trip = { t0 = C.GetTime(), predicted = leg.seconds / f, to = leg.to, cont = leg.to.cont, lost = 0 }
end

-- Once a second (Travel:Tick): finish or spoil the trip.
function Pace:TickTrip(dt)
  local t = self.trip
  if not t then return end
  if C.OnTaxi() or (C.InCombat and C.InCombat()) or (C.IsDead and C.IsDead()) or self:Away() then
    t.spoiled = true
  end
  local pm, px, py = C.GetPlayerPos()
  if not pm or not Panoply.Route then return end
  local c, wx, wy = Panoply.Route:ToWorld(pm, px, py)
  if not c or c ~= t.cont then t.spoiled = true return end
  local dx, dy = wx - t.to.wx, wy - t.to.wy
  if dx * dx + dy * dy <= self.ARRIVE_YD * self.ARRIVE_YD then
    local actual = C.GetTime() - t.t0
    self.trip = nil
    if not t.spoiled then self:AddTrip(t.predicted, actual) end
  elseif C.GetTime() - t.t0 > t.predicted * self.SAMPLE_MAX + 60 then
    self.trip = nil
  end
end

function Pace:Away()
  local f = _G.UnitIsAFK
  return f and f("player") and true or false
end

-------------------------------------------------------------------------------
-- Flight times
-------------------------------------------------------------------------------
-- Measured seconds of a flight a -> b (taxi node names), or nil.
function Pace:FlightTime(a, b)
  local p = store()
  local s = p and a and b and p.flights[a .. ">" .. b]
  return s and tonumber(s) or nil
end

function Pace:NoteFlight(a, b, seconds, estimate)
  local p = store()
  if not (p and a and b and seconds) then return end
  if estimate and estimate > 0 then
    local r = seconds / estimate
    if r < self.FLIGHT_MIN or r > self.FLIGHT_MAX then return end
  end
  local k = a .. ">" .. b
  local old = tonumber(p.flights[k])
  p.flights[k] = old and floor((old * 0.5 + seconds * 0.5) + 0.5) or floor(seconds + 0.5)
  Panoply:Fire("PACE_CHANGED", "flight")
end

-- Called by Travel when a flight starts / ends (from the route's fly leg).
function Pace:FlightStarted(leg)
  if not leg then return end
  self.flight = { t0 = C.GetTime(), from = leg.from and leg.from.name, to = leg.to and leg.to.name, estimate = leg.seconds }
end
function Pace:FlightEnded()
  local f = self.flight
  self.flight = nil
  if not f then return end
  local s = C.GetTime() - f.t0
  local est = f.estimate and (f.estimate - (Panoply.Route and Panoply.Route.TAXI_BOARD or 0)) or nil
  self:NoteFlight(f.from, f.to, s, est)
end

-------------------------------------------------------------------------------
-- Experience pace
-------------------------------------------------------------------------------
function Pace:XPState() local lvl, xp, mx, rested = C.XP() return lvl, xp, mx, rested end

-- Is the player playing right now? One rule for everything that times play (this file's experience pace and
-- Engine/LevelStats.lua): moving, gaining experience or `poke` (fighting...) keeps the clock running; after
-- IDLE_S seconds of none of those, or while flagged AFK, it stops until the player does something again.
-- `a` is the table that remembers the last position and the last sign of activity (Pace itself, or the
-- caller's own), so two callers never disturb each other.
function Pace:IsActive(a, poke, now)
  local pm, px, py = C.GetPlayerPos()
  local moved = pm and a.lastPos and (pm ~= a.lastPos[1] or abs(px - a.lastPos[2]) + abs(py - a.lastPos[3]) > 1e-5)
  a.lastPos = pm and { pm, px, py } or nil
  if poke or moved then a.lastActive = now end
  if self:Away() or not a.lastActive or now - a.lastActive > self.IDLE_S then return false end
  return true
end

-- Once a second: count active time and experience gained (without rested bonus).
function Pace:TickXP(dt)
  local p = store()
  if not p then return end
  dt = dt or 1
  local lvl, xp, mx, rested = self:XPState()
  local last = self.lastXP
  self.lastXP = { lvl = lvl, xp = xp, mx = mx, rested = rested }
  local now = C.GetTime()
  local gained = 0
  if last then
    if lvl == last.lvl then gained = xp - last.xp
    elseif lvl == last.lvl + 1 then gained = (last.mx - last.xp) + xp end
    if gained < 0 then gained = 0 end
    -- rested experience doubles kill experience: what the rested pool lost was bonus, not pace
    local used = (last.rested or 0) - (rested or 0)
    if used > 0 then gained = max(0, gained - used) end
  end
  if not self:IsActive(self, gained > 0, now) then return end
  self.win = self.win or { xp = 0, t = 0 }
  self.win.xp, self.win.t = self.win.xp + gained, self.win.t + dt
  if self.win.t >= self.XP_WINDOW then
    self:AddXPWindow(self.win.xp, self.win.t)
    self.win = { xp = 0, t = 0 }
  end
end

function Pace:AddXPWindow(xp, seconds)
  local p = store()
  if not p or seconds <= 0 then return end
  local rate = xp / seconds * 3600
  local a = 1 - 0.5 ^ (seconds / self.XP_HALF_LIFE)
  p.xph = p.xph and (p.xph + (rate - p.xph) * a) or rate
  p.xphActive = p.xphActive + seconds
  Panoply:Fire("PACE_CHANGED", "xp")
end

-- The plan's own estimate (experience per hour), from the planner's last run.
function Pace:PlanXPH()
  local P, st = Panoply.Planner, Panoply.Planner and Panoply.Planner.lastStats
  if not (P and st and st.seconds and st.seconds > 0 and P.XPToLevel) then return nil end
  local xp, lvl = 0, st.startLevel or 1
  local endLevel = st.endLevel or lvl
  local _, curXP = self:XPState()
  for l = lvl, endLevel - 1 do xp = xp + P.XPToLevel(l) end
  xp = xp + (st.endXP or 0) - (st.startXP or curXP or 0)
  if xp <= 0 then return nil end
  return xp / st.seconds * 3600
end

-- 7400 -> "7,400" (whole numbers with a thousands comma, as the rest of the text).
function Pace.Number(n)
  local s = tostring(floor((n or 0) + 0.5))
  local k
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

-- Experience per hour to use, and where it came from ("pace" or "plan").
function Pace:XPH()
  local p = store()
  local want = not (Panoply.db and Panoply.db.paceSource == "plan")
  if want and p and p.xph and p.xphActive >= self.XP_WARMUP and p.xph > 0 then return p.xph, "pace" end
  local plan = self:PlanXPH()
  if plan then return plan, "plan" end
  if p and p.xph and p.xph > 0 and p.xphActive >= self.XP_WINDOW then return p.xph, "pace" end
  return nil
end

-- Seconds to reach level `target` (default: the next level), or nil.
function Pace:TimeToLevel(target)
  local rate = self:XPH()
  if not rate or rate <= 0 then return nil end
  local lvl, xp, mx = self:XPState()
  target = target or (lvl + 1)
  if target <= lvl then return 0 end
  local need = (mx or 0) - (xp or 0)
  local P = Panoply.Planner
  for l = lvl + 1, target - 1 do need = need + ((P and P.XPToLevel) and P.XPToLevel(l) or mx) end
  return need / rate * 3600
end

-- The level line: "Level 25 in about 47 min at your pace · plan end (level 30) in about 6 h 10 min".
-- short = true (0.9.5 phase 4K): only "Level 16 in about 1 h 22 min at your pace", without the plan-end part (the guide window's and the
-- Guide page's trip line)
function Pace:LevelLine(short)
  local D = Panoply.Route and Panoply.Route.Duration
  if not D then return nil end
  local lvl = self:XPState()
  local t = self:TimeToLevel()
  if not t then return nil end
  local _, src = self:XPH()
  local s = ("Level %d in about %s %s"):format(lvl + 1, D(t), src == "pace" and "at your pace" or "(plan estimate)")
  local st = Panoply.Planner and Panoply.Planner.lastStats
  local goal = st and st.goalLevel
  if not short and goal and goal > lvl + 1 then
    local te = self:TimeToLevel(goal)
    if te then s = s .. (" · plan end (level %d) in about %s"):format(goal, D(te)) end
  end
  return s
end

-- 0.8.4, the XP horizon: where your experience bar will be after `minutes` of play (HORIZON_MIN when not given) at the
-- pace XPH() gives. Returns { frac = 0..1 along this level's bar, now = where the bar is now, levelUp = true when the
-- next level comes first (frac is 1 then), level, minutes, source = "pace" | "plan" }, or nil when there is no pace yet
-- or nothing left to gain. Advice only: UI/Misc.lua draws it as a small mark on the experience bar.
Pace.HORIZON_MIN = 30
function Pace:Horizon(minutes)
  minutes = tonumber(minutes) or self.HORIZON_MIN
  local rate, src = self:XPH()
  if not rate or rate <= 0 or minutes <= 0 then return nil end
  local lvl, xp, mx = self:XPState()
  if not mx or mx <= 0 or not xp then return nil end
  local reach = xp + rate * minutes / 60
  local up = reach >= mx
  return { frac = up and 1 or clamp(reach / mx, 0, 1), now = clamp(xp / mx, 0, 1), levelUp = up, level = lvl, minutes = minutes, source = src }
end

-- "In 30 min: 72% of level 24 at your pace" / "In 30 min: level 25 (plan estimate)"
function Pace:HorizonLine(minutes)
  local h = self:Horizon(minutes)
  if not h then return nil end
  local how = h.source == "pace" and "at your pace" or "(plan estimate)"
  if h.levelUp then return ("In %d min: level %d %s"):format(h.minutes, h.level + 1, how), h end
  return ("In %d min: %d%% of level %d %s"):format(h.minutes, floor(h.frac * 100), h.level, how), h
end

-- "Forget my pace".
function Pace:Reset()
  if Panoply.cdb then Panoply.cdb.pace = nil end
  self.trip, self.flight, self.win, self.lastXP = nil, nil, nil, nil
  store()
  Panoply:Fire("PACE_CHANGED", "reset")
  if Panoply.Route and Panoply.Route.Changed then Panoply.Route:Changed("pace reset") end
end

-- Plain-words summary for the calibration readout and /panoply pace.
function Pace:Summary()
  local p = store() or { travel = 1, travelN = 0, xphActive = 0, flights = {} }
  local out = {}
  local f = self:TravelFactor()
  if p.travelN == 0 then out[#out + 1] = "Travel pace: not learned yet (times use the standard estimate)."
  else
    local pct = floor((f - 1) * 100 + 0.5)
    out[#out + 1] = ("Travel pace: %s, from %d walk%s."):format(pct == 0 and "as estimated" or pct > 0 and ("%d%% slower than the estimate"):format(pct)
      or ("%d%% faster than the estimate"):format(-pct), p.travelN, p.travelN == 1 and "" or "s")
  end
  local n = 0
  for _ in pairs(p.flights) do n = n + 1 end
  out[#out + 1] = n == 0 and "Flight times: none measured yet." or ("Flight times: %d flight%s measured."):format(n, n == 1 and "" or "s")
  local rate, src = self:XPH()
  if rate then
    out[#out + 1] = ("Experience: about %s per hour (%s)."):format(Pace.Number(rate), src == "pace" and "your pace" or "the plan's estimate")
  else
    out[#out + 1] = "Experience: not enough play yet to tell."
  end
  return out
end
