-- Panoply Suite session summary (0.8.4): what this play session has brought so far. Own code.
--   * Experience gained and experience per hour of the session (rested bonus included: it is what the player really got).
--   * Gold: what the character has now against what it had when the session started (can be less).
--   * Dungeon runs: each time the character walks into a dungeon or raid alive (a corpse run back in is the same run).
--   * Deaths this session (the full list is Engine/DeathLog.lua).
-- A /reload is the same session: the numbers are kept in PanoplySuiteCharDB.session at logout and picked up again when the
-- character is back within RESUME_S seconds. Reads only: nothing here moves, targets or casts.
-- Shown by UI/Misc.lua: one line on Home, one strip on the Guide page, and the XP horizon mark (Engine/Pace.lua).
-- 0.9.5 phase 4F: the experience gained over the session, one point a minute at most (Session:Curve), for Field Kit's chart. A
-- /reload keeps it in a NEW per-character key, PanoplySuiteCharDB.sessionCurve, read and cleared at the next login like the session.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Session = {}
Panoply.Session = Session
local floor, max = math.floor, math.max

Session.RESUME_S = 5 * 60     -- a logout shorter than this (a /reload, a quick relog) carries the session on
Session.MIN_RATE_S = 60       -- no "per hour" before a minute has gone by
Session.CURVE_STEP_S = 60     -- the chart keeps one point per minute (a later gain in the same minute moves that point)
Session.CURVE_MAX = 240       -- points kept (older ones are thinned to every other one)

Panoply.defaults.account.sessionStrip = true   -- the strip on the Guide page
Panoply.defaults.account.homeSession = true    -- the line on Home

local function wall() return (_G.time and _G.time()) or os.time() end

local function fresh()
  local lvl, xp, mx = C.XP()
  return { start = wall(), xp = 0, levels = 0, money0 = C.Money(), runs = 0, deaths = 0, last = { lvl = lvl, xp = xp, mx = mx }, curve = {} }
end

-- The session being counted (made on first use, so a test or a late caller never finds none).
function Session:Data()
  if not self.data then self.data = fresh() end
  return self.data
end

-- At login: carry on the saved session when the character was away only a moment, else start a new one.
function Session:Start()
  local saved = Panoply.cdb and Panoply.cdb.session
  local now = wall()
  if type(saved) == "table" and type(saved.at) == "number" and now - saved.at >= 0 and now - saved.at <= self.RESUME_S
      and type(saved.start) == "number" then
    local d = fresh()
    d.start = saved.start
    d.xp, d.levels = tonumber(saved.xp) or 0, tonumber(saved.levels) or 0
    d.runs, d.deaths = tonumber(saved.runs) or 0, tonumber(saved.deaths) or 0
    d.money0 = tonumber(saved.money0) or d.money0
    d.inside = saved.inside
    local curve = Panoply.cdb and Panoply.cdb.sessionCurve
    if type(curve) == "table" then
      for _, pt in ipairs(curve) do
        if type(pt) == "table" and type(pt[1]) == "number" and type(pt[2]) == "number" then d.curve[#d.curve + 1] = { pt[1], pt[2] } end
      end
    end
    self.data = d
  else
    self.data = fresh()
  end
  if Panoply.cdb then Panoply.cdb.session, Panoply.cdb.sessionCurve = nil, nil end
  self:CheckInstance()
  Panoply:Fire("SESSION_CHANGED", "start")
  return self.data
end

-- At logout: what a /reload needs to carry on.
function Session:Save()
  local d = self.data
  if not (d and Panoply.cdb) then return end
  Panoply.cdb.session = { at = wall(), start = d.start, xp = d.xp, levels = d.levels, runs = d.runs, deaths = d.deaths,
    money0 = d.money0, inside = d.inside }
  if d.curve and #d.curve > 0 then
    local out = {}
    for i, pt in ipairs(d.curve) do out[i] = { pt[1], pt[2] } end
    Panoply.cdb.sessionCurve = out
  end
end

-- a point of the chart: experience gained so far, at seconds since the start (one point a minute)
function Session:NotePoint()
  local d = self:Data()
  d.curve = d.curve or {}
  local t = math.max(0, wall() - d.start)
  local last = d.curve[#d.curve]
  if last and t - last[1] < self.CURVE_STEP_S and #d.curve > 1 then last[2] = d.xp
  else d.curve[#d.curve + 1] = { t, d.xp } end
  if #d.curve > self.CURVE_MAX then
    local kept = {}
    for i, pt in ipairs(d.curve) do if i % 2 == 1 or i == #d.curve then kept[#kept + 1] = pt end end
    d.curve = kept
  end
end

-- The chart: { { t = seconds since the start, xp = gained by then } }, from 0 at the start, and the session's length now.
function Session:Curve()
  local d = self:Data()
  local seconds = math.max(0, wall() - d.start)
  local out = { { t = 0, xp = 0 } }
  for _, pt in ipairs(d.curve or {}) do
    if pt[1] > out[#out].t then out[#out + 1] = { t = pt[1], xp = pt[2] } else out[#out].xp = pt[2] end
  end
  return out, seconds
end

function Session:Reset()
  self.data = fresh()
  self:CheckInstance(true)
  Panoply:Fire("SESSION_CHANGED", "reset")
end

-- Experience: the difference since the last look. A new level is "the rest of the old level plus what is in the new one";
-- the bar going back to a smaller number with the same level is the same thing (the level number can lag behind the bar).
function Session:NoteXP()
  local d = self:Data()
  local lvl, xp, mx = C.XP()
  local last = d.last
  d.last = { lvl = lvl, xp = xp, mx = mx }
  if not last then return 0 end
  local gained = 0
  if lvl == last.lvl and xp >= last.xp then gained = xp - last.xp
  elseif lvl == last.lvl + 1 then
    gained = max(0, (last.mx or 0) - (last.xp or 0)) + xp
    d.levels = d.levels + 1
  elseif lvl == last.lvl and xp < last.xp then
    -- the bar rolled over and the level number has not caught up: the level-up is counted now, and the level is remembered as
    -- already gained so that the number catching up is not a second level-up
    gained = max(0, (last.mx or 0) - (last.xp or 0)) + xp
    d.levels = d.levels + 1
    d.last.lvl = lvl + 1
  elseif lvl > last.lvl + 1 then
    d.levels = d.levels + (lvl - last.lvl)
  end
  if gained > 0 then d.xp = d.xp + gained self:NotePoint() Panoply:Fire("SESSION_CHANGED", "xp") end
  return gained
end

-- Dungeon runs: walking in is a new run; coming back in after dying inside (the corpse run: the game may already have the
-- character alive again at the door), or as a ghost, is the same one.
function Session:CheckInstance(quiet)
  local d = self:Data()
  local inside, kind = C.InInstance()
  local dungeon = inside and (kind == "party" or kind == "raid")
  if dungeon and not d.inside then
    d.inside = true
    local back = d.diedInside or (C.IsDead and C.IsDead())
    d.diedInside = nil
    if not quiet and not back then d.runs = d.runs + 1 Panoply:Fire("SESSION_CHANGED", "run") end
  elseif not dungeon and d.inside then
    d.inside = nil
  end
  return d.runs
end

function Session:NoteDeath()
  local d = self:Data()
  d.deaths = d.deaths + 1
  Panoply:Fire("SESSION_CHANGED", "death")
end

-- The numbers: { seconds, xp, xph (nil in the first minute), gold (copper, may be negative), runs, deaths, levels }
function Session:Stats()
  local d = self:Data()
  local seconds = max(0, wall() - d.start)
  local out = { seconds = seconds, xp = d.xp, gold = C.Money() - (d.money0 or 0), runs = d.runs, deaths = d.deaths, levels = d.levels }
  if seconds >= self.MIN_RATE_S then out.xph = d.xp / seconds * 3600 end
  return out
end

-- "+3g 20s", "-45s 10c", "no change"
function Session.GoldText(copper)
  copper = floor((copper or 0) + 0.5)
  if copper == 0 then return "no change" end
  return (copper > 0 and "+" or "-") .. C.FormatMoney(copper)
end

-- "12 min", "1 h 05 min"
function Session.TimeText(seconds)
  local m = floor((seconds or 0) / 60)
  if m < 60 then return ("%d min"):format(m) end
  return ("%d h %02d min"):format(floor(m / 60), m % 60)
end

local function number(n) return Panoply.Pace and Panoply.Pace.Number and Panoply.Pace.Number(n) or tostring(floor((n or 0) + 0.5)) end

-- The parts of the strip, in order: experience per hour, gold, dungeon runs (deaths only when there were any).
function Session:Parts()
  local s = self:Stats()
  local parts = {}
  if s.xph then parts[#parts + 1] = ("%s XP per hour"):format(number(s.xph))
  else parts[#parts + 1] = ("%s XP so far"):format(number(s.xp)) end
  parts[#parts + 1] = "Gold: " .. Session.GoldText(s.gold)
  parts[#parts + 1] = s.runs == 1 and "1 dungeon run" or ("%d dungeon runs"):format(s.runs)
  if s.deaths > 0 then parts[#parts + 1] = s.deaths == 1 and "1 death" or ("%d deaths"):format(s.deaths) end
  return parts, s
end

-- One line: "This session (42 min): 7,400 XP per hour, Gold: +3g 20s 0c, 1 dungeon run"
function Session:Line()
  local parts, s = self:Parts()
  return ("This session (%s): %s"):format(Session.TimeText(s.seconds), table.concat(parts, ", ")), s
end

Panoply:On("PLAYER_LOGIN", function() Session:Start() end)
Panoply:On("PLAYER_LOGOUT", function() Session:Save() end)
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }) do Panoply:On(ev, function() Session:NoteXP() end) end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do Panoply:On(ev, function() Session:CheckInstance() end) end
Panoply:On("PLAYER_MONEY", function() Panoply:Fire("SESSION_CHANGED", "gold") end)
-- a death inside a dungeon: the walk back in is part of the same run (whether or not the death log is on)
Panoply:On("PLAYER_DEAD", function() local d = Session:Data() if d.inside then d.diedInside = true end end)
