-- Panoply Suite road recorder (0.6.0 M6, SPEC section 21.13): /panoply record. Own code.
-- Saves where you walk, so real roads can be captured in game and turned into road points later
-- (tools/roadgraph/import_record.py). It only reads your position: no movement, no clicks, no automation.
-- Each recording: { name, flavor, char, started, stopped, points = { { map, x, y, t, seg }, ... } }
-- in PanoplySuiteDB.roadRecords (account-wide SavedVariables, written when you log out or /reload).
-- Map x/y are 0..100 with two decimals; t is seconds since the start; seg goes up after a pause (a flight,
-- a loading screen, an instance, death), so pieces that were not walked are never joined.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Rec = {}
Panoply.Recorder = Rec
local floor, sqrt = math.floor, math.sqrt

Rec.EVERY_S = 2          -- look at your position every 2 s...
Rec.MIN_YD = 10          -- ...and keep it when you moved at least 10 yd
Rec.MAX_POINTS = 20000   -- per recording (about 55 hours of walking at one point per 10 yd)
Rec.MAX_RECORDS = 50

local function list()
  local db = Panoply.db
  if not db then return nil end
  if type(db.roadRecords) ~= "table" then db.roadRecords = {} end
  return db.roadRecords
end

local function stamp()
  local f = _G.date
  return f and f("%Y-%m-%d %H:%M") or tostring(floor(C.GetTime()))
end

function Rec:Active() return self.rec ~= nil end

function Rec:Start(name)
  local L = list()
  if not L then return nil, "not ready" end
  if self.rec then return nil, "already recording" end
  while #L >= self.MAX_RECORDS do table.remove(L, 1) end
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  local rec = { name = (name and name ~= "") and name or ("Recording " .. (#L + 1)), flavor = C.Flavor(), char = info.name,
                started = stamp(), points = {} }
  L[#L + 1] = rec
  self.rec, self.t0, self.seg, self.clock, self.last = rec, C.GetTime(), 1, 0, nil
  self:Sample(true)
  Panoply:Fire("RECORDER_CHANGED", true)
  return rec
end

function Rec:Stop()
  local rec = self.rec
  if not rec then return nil end
  self:Sample(true)
  rec.stopped = stamp()
  self.rec, self.last = nil, nil
  Panoply:Fire("RECORDER_CHANGED", false)
  return rec
end

-- Paused while flying, in an instance, dead, or when the map position is unknown (loading screens).
function Rec:Paused()
  if C.OnTaxi() then return true end
  if C.InInstance and C.InInstance() then return true end
  if C.IsDead and C.IsDead() then return true end
  return false
end

function Rec:Sample(force)
  local rec = self.rec
  if not rec then return end
  local pm, px, py = C.GetPlayerPos()
  if not pm or self:Paused() then
    if self.last then self.seg = self.seg + 1 self.last = nil end
    return
  end
  local Route = Panoply.Route
  local c, wx, wy
  if Route then c, wx, wy = Route:ToWorld(pm, px, py) end
  local last = self.last
  if last and not force then
    if c and last.c == c and last.wx then
      local dx, dy = wx - last.wx, wy - last.wy
      if sqrt(dx * dx + dy * dy) < self.MIN_YD then return end
    elseif last.map == pm and math.abs(last.x - px) + math.abs(last.y - py) < 0.002 then
      return
    end
  end
  if #rec.points >= self.MAX_POINTS then
    Panoply:Print("The road recording is full; it has been stopped and saved. Start a new one with /panoply record.")
    self:Stop()
    return
  end
  if last and c and last.c and last.c ~= c then self.seg = self.seg + 1 end
  local p = { pm, floor(px * 10000 + 0.5) / 100, floor(py * 10000 + 0.5) / 100, floor(C.GetTime() - self.t0 + 0.5), self.seg }
  rec.points[#rec.points + 1] = p
  self.last = { map = pm, x = px, y = py, c = c, wx = wx, wy = wy }
end

function Rec:Tick(dt)
  if not self.rec then return end
  self.clock = (self.clock or 0) + (dt or 1)
  if self.clock >= self.EVERY_S then self.clock = 0 self:Sample() end
end

function Rec:Summary()
  local L = list() or {}
  local out = {}
  if self.rec then
    out[#out + 1] = ("Recording \"%s\": %d point%s so far."):format(self.rec.name, #self.rec.points, #self.rec.points == 1 and "" or "s")
  end
  out[#out + 1] = (#L == 0) and "No road recordings saved." or ("%d road recording%s saved:"):format(#L, #L == 1 and "" or "s")
  for i, r in ipairs(L) do
    out[#out + 1] = ("  %d. %s (%s, %d points, %s)"):format(i, r.name, r.flavor or "?", #(r.points or {}), r.started or "?")
  end
  return out
end

function Rec:Clear()
  local L = list()
  if not L then return 0 end
  local n = #L
  for i = n, 1, -1 do if L[i] ~= self.rec then table.remove(L, i) end end
  return n - #L
end

-- /panoply record [name] | stop | list | clear
function Rec:Slash(args)
  local sub = (args[2] or ""):lower()
  if sub == "stop" or sub == "off" then
    local r = self:Stop()
    if r then Panoply:Print(("Road recording \"%s\" saved: %d points. It is written to your SavedVariables when you log out or /reload."):format(r.name, #r.points))
    else Panoply:Print("Not recording. Start with /panoply record [name].") end
  elseif sub == "list" or sub == "status" then
    for _, l in ipairs(self:Summary()) do Panoply:Print(l) end
  elseif sub == "clear" then
    Panoply:Print(("%d road recording(s) deleted."):format(self:Clear()))
  elseif self.rec then
    Panoply:Print(("Already recording \"%s\" (%d points). /panoply record stop to save it."):format(self.rec.name, #self.rec.points))
  else
    local name = table.concat(args, " ", 2)
    if (args[2] or ""):lower() == "start" then name = table.concat(args, " ", 3) end
    local r, err = self:Start(name)
    if r then Panoply:Print(("Recording your path as \"%s\". Walk the road, then /panoply record stop. Only your position is saved."):format(r.name))
    else Panoply:Print("Could not start recording: " .. tostring(err)) end
  end
end

function Rec:Register()
  Panoply:On("PLAYER_LOGOUT", function() if Rec.rec then Rec:Sample(true) Rec.rec.stopped = stamp() .. " (logout)" end end)
end
