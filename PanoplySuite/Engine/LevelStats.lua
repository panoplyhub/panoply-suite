-- Panoply Suite level times (2 Nov 2026: "a real-game measuring tool ... records my actual time per level and
-- per zone ... so /panoply levelstats compares real vs simulated"). Own code.
--
-- Recorded quietly for the character you are playing, in PanoplySuiteCharDB.levelStats (plain numbers, no
-- internet, no chat messages, no protected calls). Per level:
--   t     seconds of play that counted at that level (see "what counts" below)
--   skip  seconds that did not count (idle or AFK for longer than the cap)
--   q     quests handed in
--   k     kills that gave experience
--   z     seconds per zone, { [zone name] = seconds }, at most MAX_ZONES zones per level; the rest go to zo
--   zo    seconds in zones beyond that cap
--   pre   seconds played at this level before Panoply Suite started watching (from /played, see OnPlayed)
--   part  true: Panoply Suite started watching in the middle of this level
--   open  true: the end of this level was not seen (you logged in at a higher level)
--
-- What counts: the game clock while you are logged in, once a second (Travel's ticker is not used; this runs in
-- every questing mode). A tick counts only while you are playing: moving, fighting, gaining experience or handing
-- in a quest. After IDLE_S (5 minutes, the same rule as the experience pace, Pace:IsActive) of none of those, or
-- while flagged AFK, the time goes to "skip" instead. So one idle stretch counts at most 5 minutes. One tick
-- counts at most MAX_GAP_S (a loading screen or a frozen client is not counted past a minute).
-- /played: the game's own level time is read only when something else asks for it (you typing /played, or Hearth
-- Hall's one muted request per login). It is never requested here, so it never prints to chat. It is used for
-- one thing: a level that Panoply Suite started watching half way gets "pre", the time /played says came before.
--
-- The simulator's figures are a small table shipped with the add-on (Data/LevelStatsSim.lua, made by
-- tools/make_levelstats_sim.py from tests/routesim, minutes per level).
local ADDON, Panoply = ...
local C = Panoply.Compat
local LS = {}
Panoply.LevelStats = LS
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

LS.SCHEMA = 1
LS.MAX_GAP_S = 60       -- one tick counts at most this long
LS.MAX_LEVEL = 80       -- records above this level are not kept (the game's cap is 60)
LS.MAX_ZONES = 12       -- zones kept per level
LS.ZONE_CHARS = 40
LS.BAND = 5             -- /panoply levelstats compares bands of 5 levels
LS.NEARLY = 0.05        -- within 5% of the simulator is "about the same"
LS.RECENT = 15          -- /panoply levelstats levels shows this many levels
LS.TOP_ZONES = 12       -- /panoply levelstats zones shows this many zones

local function num(v)
  v = tonumber(v)
  if v and v == v and v > -1e12 and v < 1e12 then return v end
  return 0
end

local function enabled() return Panoply.cdb ~= nil and not (Panoply.db and Panoply.db.levelStats == false) end

local function store()
  local c = Panoply.cdb
  if not c then return nil end
  local s = c.levelStats
  if type(s) ~= "table" then s = {} c.levelStats = s end
  s.v = LS.SCHEMA
  if type(s.levels) ~= "table" then s.levels = {} end
  return s
end
LS.Store = store

local function cutName(z)
  z = tostring(z)
  if #z <= LS.ZONE_CHARS then return z end
  z = z:sub(1, LS.ZONE_CHARS)
  local i = #z
  while i > 0 and z:byte(i) >= 128 and z:byte(i) < 192 do i = i - 1 end   -- never cut a character in half
  if i > 0 and z:byte(i) >= 192 then z = z:sub(1, i - 1) end
  return z
end

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------
-- Make `lvl` the level being recorded. A level reached while Panoply Suite was watching (the one before it was the
-- level we recorded) starts clean; anything else (first login with Panoply Suite, a login at a higher level)
-- ends the old record as "open" and starts the new one as "part".
function LS:Enter(lvl, xp)
  local s = store()
  lvl = floor(num(lvl))
  if not s or lvl < 1 or lvl > self.MAX_LEVEL then return nil end
  local lv = s.levels[lvl]
  if s.cur == lvl and type(lv) == "table" then self.seen = lvl return lv end
  local clean = self.seen ~= nil and self.seen == s.cur and lvl == s.cur + 1
  local old = s.cur and s.levels[s.cur]
  if type(old) == "table" and not clean and s.cur ~= lvl then old.open = true end
  if type(lv) ~= "table" then
    lv = { t = 0, skip = 0, q = 0, k = 0, z = {}, zo = 0 }
    local brandNew = s.cur == nil and lvl == 1 and num(xp) == 0
    if not clean and not brandNew then lv.part = true end
    s.levels[lvl] = lv
  end
  s.cur = lvl
  self.seen = lvl
  return lv
end

local function addZone(lv, zone, secs)
  local z = lv.z
  if type(z) ~= "table" then z = {} lv.z = z end
  if z[zone] ~= nil then z[zone] = num(z[zone]) + secs return end
  local n = 0
  for _ in pairs(z) do n = n + 1 end
  if n < LS.MAX_ZONES then z[zone] = secs else lv.zo = num(lv.zo) + secs end
end

-- Once a second (Core/Bootstrap.lua Panoply:Tick).
function LS:Tick()
  if not enabled() then self.lastT, self.act, self.carry, self.seen = nil, nil, nil, nil return end
  local s = store()
  local now = C.GetTime()
  local last = self.lastT
  self.lastT = now
  local dt = last and (now - last) or 0
  if dt < 0 then dt = 0 end
  if dt > self.MAX_GAP_S then dt = self.MAX_GAP_S end
  if not self.act then self.act = { lastActive = now } end   -- logging in counts as playing
  local lvl, xp = C.XP()
  lvl = floor(num(lvl))
  if s.cur and lvl < s.cur then lvl = s.cur end              -- the game's level can lag a level-up by a moment
  local poke = self.poke or (C.InCombat and C.InCombat()) or false
  self.poke = false
  if self.lastXP and (xp ~= self.lastXP or lvl ~= self.lastLvl) then poke = true end
  self.lastXP, self.lastLvl = xp, lvl
  local active = Panoply.Pace:IsActive(self.act, poke, now)
  local lv = self:Enter(lvl, xp)
  self.carry = (self.carry or 0) + dt
  local whole = floor(self.carry)
  self.carry = self.carry - whole
  if not lv or whole <= 0 then return end
  if active then
    lv.t = num(lv.t) + whole
    local z = C.ZoneText()
    if type(z) ~= "string" or z == "" then z = self.zone or "Unknown" end
    z = cutName(z)
    self.zone = z
    addZone(lv, z, whole)
  else
    lv.skip = num(lv.skip) + whole
  end
end

local function currentRec()
  if not enabled() then return nil end
  local s = store()
  local lv = s and s.cur and s.levels[s.cur]
  if type(lv) == "table" then return lv end
  return nil
end

-- A quest handed in / a kill that gave experience (events below).
function LS:Quest()
  local lv = currentRec()
  if lv then lv.q = num(lv.q) + 1 self.poke = true end
end
function LS:Kill()
  local lv = currentRec()
  if lv then lv.k = num(lv.k) + 1 self.poke = true end
end

-- "X dies, you gain N experience." in this client's language, as a pattern (nil when the game has no such text).
function LS.KillPattern()
  local g = _G.COMBATLOG_XPGAIN_FIRSTPERSON
  if type(g) ~= "string" or g == "" then return nil end
  local p = g:gsub("%%%d?%$?s", "\2"):gsub("%%%d?%$?d", "\3")   -- %s, %d (and %1$s, %2$d)
  p = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")                  -- the rest is literal text
  p = p:gsub("\2", ".+"):gsub("\3", "%%d+")
  return "^" .. p
end

function LS:OnXPMessage(msg)
  msg = C.Readable(msg)
  if type(msg) ~= "string" then return end
  self.killPat = self.killPat or LS.KillPattern()
  if self.killPat and msg:find(self.killPat) then self:Kill() end
end

-- The game's /played answer (total, seconds at this level), whoever asked for it.
function LS:OnPlayed(total, levelTime)
  if not enabled() then return end
  local lt = C.Readable(levelTime)
  lt = type(lt) == "number" and lt or nil
  local lv = currentRec()
  if not (lt and lt >= 0 and lt < 1e9 and lv and lv.part and lv.pre == nil) then return end
  lv.pre = max(0, floor(lt - (num(lv.t) + num(lv.skip)) + 0.5))
end

function LS:Register()
  Panoply:On("PLAYER_LEVEL_UP", function(_, newLevel)
    if not enabled() then return end
    local n = tonumber(C.Readable(newLevel))
    if n then LS:Enter(n) end
  end)
  Panoply:On("QUEST_TURNED_IN", function() LS:Quest() end)
  Panoply:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg) LS:OnXPMessage(msg) end)
  Panoply:On("TIME_PLAYED_MSG", function(_, total, levelTime) LS:OnPlayed(total, levelTime) end)
end

-- "Forget my level times".
function LS:Reset()
  if Panoply.cdb then Panoply.cdb.levelStats = nil end
  self.seen, self.lastT, self.act, self.carry, self.zone, self.lastXP, self.lastLvl, self.poke = nil, nil, nil, nil, nil, nil, nil, nil
  store()
end

-------------------------------------------------------------------------------
-- Comparing with the simulator
-------------------------------------------------------------------------------
-- The simulator's minutes per level for this client ({ [level] = minutes }), or nil.
function LS.SimTable()
  local D = Panoply.LevelStatsSim
  if type(D) ~= "table" then return nil end
  local key = (C.Flavor and C.Flavor() == "forever") and "forever" or "era"
  return D[key], key
end

-- "3 h 05 min", "42 min", "under 1 min".
function LS.Time(sec)
  local m = floor(num(sec) / 60 + 0.5)
  if m < 1 then return "under 1 min" end
  if m < 60 then return m .. " min" end
  return ("%d h %02d min"):format(floor(m / 60), m % 60)
end
local T = LS.Time

-- A level counts for the comparison when it was seen from its start to its end, or its start is known from /played.
local function complete(lv, lvl, cur)
  return type(lv) == "table" and not lv.open and lvl < cur and (not lv.part or lv.pre ~= nil)
end
local function realSecs(lv) return num(lv.t) + num(lv.pre) end

-- Everything the slash command and the report need, from the saved record.
--   levels[lvl] = { real = seconds, sim = seconds or nil, q =, k =, done = bool }
--   bands = { { lo =, hi =, n = levels compared, real =, sim = } } (only bands with at least one compared level)
--   total = { n =, real =, sim = }
function LS:Analyse()
  local s = store()
  local out = { levels = {}, bands = {}, total = { n = 0, real = 0, sim = 0 }, missing = {}, skipped = 0 }
  if not s then return out end
  local sim, key = LS.SimTable()
  out.flavor, out.sim = key, sim
  out.cur = s.cur
  local cur = s.cur or 0
  local first, last
  for lvl, lv in pairs(s.levels) do
    if type(lvl) == "number" and type(lv) == "table" then
      local done = complete(lv, lvl, cur)
      local simMin = sim and tonumber(sim[lvl]) or nil
      out.levels[lvl] = { real = realSecs(lv), sim = simMin and simMin * 60 or nil, q = num(lv.q), k = num(lv.k), done = done,
                          part = lv.part and lv.pre == nil or false, open = lv.open or false, now = lvl == cur }
      out.skipped = out.skipped + num(lv.skip)
      if done then first = min(first or lvl, lvl) last = max(last or lvl, lvl) end
    end
  end
  out.first, out.last = first, last
  local bands = {}
  for lvl, e in pairs(out.levels) do
    if e.done and e.sim then
      local b = floor((lvl - 1) / self.BAND)
      local x = bands[b]
      if not x then x = { lo = b * self.BAND + 1, hi = (b + 1) * self.BAND, n = 0, real = 0, sim = 0 } bands[b] = x end
      x.n, x.real, x.sim = x.n + 1, x.real + e.real, x.sim + e.sim
      out.total.n, out.total.real, out.total.sim = out.total.n + 1, out.total.real + e.real, out.total.sim + e.sim
    end
  end
  local keys = {}
  for b in pairs(bands) do keys[#keys + 1] = b end
  table.sort(keys)
  for _, b in ipairs(keys) do out.bands[#out.bands + 1] = bands[b] end
  -- levels below the current one with no usable record (played before Panoply Suite watched, or the end was missed)
  for lvl = 1, cur - 1 do
    local e = out.levels[lvl]
    if not (e and e.done) then out.missing[#out.missing + 1] = lvl end
  end
  return out
end

-- "18 min faster" / "26 min slower" / "about the same", and the same as a percentage.
local function diffText(real, sim)
  if not sim or sim <= 0 then return nil end
  local d = real - sim
  if abs(d) < sim * LS.NEARLY then return "about the same" end
  return ("%s %s, %d%%"):format(T(abs(d)), d < 0 and "faster" or "slower", floor(abs(d) / sim * 100 + 0.5))
end

local function range(list)
  -- {1,2,3,7,8} -> "1-3, 7-8"
  local parts, i = {}, 1
  while i <= #list do
    local j = i
    while list[j + 1] == list[j] + 1 do j = j + 1 end
    parts[#parts + 1] = (i == j) and tostring(list[i]) or (list[i] .. "-" .. list[j])
    i = j + 1
  end
  return table.concat(parts, ", ")
end

local function title(a)
  local label = a.flavor == "forever" and "WoW Forever" or "WoW Classic"
  local D = Panoply.LevelStatsSim or {}
  return ("Your level times against the simulator (%s, %s):"):format(label, D.model or "simulator")
end

-- /panoply levelstats: the bands.
function LS:SummaryLines()
  local a = self:Analyse()
  local out = {}
  if not store() then return { "Level times: not ready yet." } end
  if not a.sim then return { "Level times: this game has no simulator table to compare with." } end
  local anyLevel = next(a.levels) ~= nil
  if not enabled() then out[#out + 1] = "Level times are switched off (/panoply levelstats on turns them back on)." end
  if not anyLevel then
    out[#out + 1] = "No level times yet. Panoply Suite is watching: play on, then try /panoply levelstats again."
    return out
  end
  out[#out + 1] = title(a)
  local faster, slower, worst, worstD = 0, 0, nil, 0
  for _, b in ipairs(a.bands) do
    local part = b.n < (b.hi - b.lo + 1) and (" (%d of %d levels)"):format(b.n, b.hi - b.lo + 1) or ""
    out[#out + 1] = ("Levels %d-%d%s: you %s, simulator %s (%s)"):format(b.lo, b.hi, part, T(b.real), T(b.sim), diffText(b.real, b.sim) or "")
    local d = (b.real - b.sim) / max(1, b.sim)
    if abs(d) >= LS.NEARLY then
      if d < 0 then faster = faster + 1 else slower = slower + 1 end
    end
    if d > worstD then worstD, worst = d, b end
  end
  local cur = a.cur and a.levels[a.cur]
  if cur then
    local simPart = cur.sim and ("; simulator %s for the whole level"):format(T(cur.sim)) or ""
    out[#out + 1] = ("Level %d (now): %s so far, %d quest%s, %d kill%s%s"):format(a.cur, T(cur.real), cur.q, cur.q == 1 and "" or "s",
      cur.k, cur.k == 1 and "" or "s", simPart)
  end
  if a.skipped >= 600 then out[#out + 1] = ("Not counted (idle or away): %s."):format(T(a.skipped)) end
  if a.total.n > 0 then
    out[#out + 1] = ("Total, %d level%s compared: you %s, simulator %s (%s)"):format(a.total.n, a.total.n == 1 and "" or "s",
      T(a.total.real), T(a.total.sim), diffText(a.total.real, a.total.sim) or "")
    local nb = #a.bands
    local line = ("Faster than the simulator in %d of %d band%s"):format(faster, nb, nb == 1 and "" or "s")
    if worst and worstD >= LS.NEARLY then line = line .. ("; slowest against it: levels %d-%d"):format(worst.lo, worst.hi) end
    out[#out + 1] = line .. "."
  else
    out[#out + 1] = "No finished level to compare yet."
  end
  if #a.missing > 0 then
    out[#out + 1] = ("Not compared: level%s %s (played before Panoply Suite was watching, or not seen to the end)."):format(#a.missing == 1 and "" or "s", range(a.missing))
  end
  return out
end

-- /panoply levelstats levels: the latest levels one by one.
function LS:LevelLines()
  local a = self:Analyse()
  local out = {}
  if not store() then return { "Level times: not ready yet." } end
  local list = {}
  for lvl in pairs(a.levels) do list[#list + 1] = lvl end
  table.sort(list)
  if #list == 0 then return { "No level times yet." } end
  out[#out + 1] = title(a)
  local from = max(1, #list - self.RECENT + 1)
  if from > 1 then out[#out + 1] = ("(the latest %d of %d levels; /panoply levelstats shows the bands)"):format(self.RECENT, #list) end
  for i = from, #list do
    local lvl = list[i]
    local e = a.levels[lvl]
    local what
    if e.now then what = "now"
    elseif e.done then what = diffText(e.real, e.sim) or "no simulator figure"
    elseif e.open then what = "not seen to the end"
    else what = "started before Panoply Suite was watching" end
    local simPart = e.sim and (", simulator %s"):format(T(e.sim)) or ""
    out[#out + 1] = ("Level %d: you %s%s (%s), %d quest%s, %d kill%s"):format(lvl, T(e.real), simPart, what, e.q, e.q == 1 and "" or "s",
      e.k, e.k == 1 and "" or "s")
  end
  return out
end

-- /panoply levelstats zones: where the time went, all levels together.
function LS:ZoneLines()
  local s = store()
  if not s then return { "Level times: not ready yet." } end
  local zones, other = {}, 0
  for lvl, lv in pairs(s.levels) do
    if type(lvl) == "number" and type(lv) == "table" then
      other = other + num(lv.zo)
      if type(lv.z) == "table" then
        for name, secs in pairs(lv.z) do
          local z = zones[name]
          if not z then z = { name = tostring(name), secs = 0, lo = lvl, hi = lvl } zones[name] = z end
          z.secs, z.lo, z.hi = z.secs + num(secs), min(z.lo, lvl), max(z.hi, lvl)
        end
      end
    end
  end
  local list = {}
  for _, z in pairs(zones) do list[#list + 1] = z end
  if #list == 0 then return { "No zone times yet. Panoply Suite is watching: play on, then try /panoply levelstats zones again." } end
  table.sort(list, function(a, b) if a.secs ~= b.secs then return a.secs > b.secs end return a.name < b.name end)
  local out = { "Where your time went, by zone (all levels recorded):" }
  for i = 1, min(#list, self.TOP_ZONES) do
    local z = list[i]
    out[#out + 1] = ("%s: %s (level%s %s)"):format(z.name, T(z.secs), z.lo == z.hi and "" or "s", z.lo == z.hi and tostring(z.lo) or (z.lo .. "-" .. z.hi))
  end
  if #list > self.TOP_ZONES or other > 0 then
    local rest = other
    for i = self.TOP_ZONES + 1, #list do rest = rest + list[i].secs end
    out[#out + 1] = ("%d other zone%s: %s"):format(max(0, #list - self.TOP_ZONES), #list - self.TOP_ZONES == 1 and "" or "s", T(rest))
  end
  return out
end

-- A small, plain summary for problem reports (Core/Reports.lua): whole minutes, bands only, no names.
function LS:ReportSummary()
  local s = store()
  if not s or next(s.levels) == nil then return nil end
  local a = self:Analyse()
  local D = Panoply.LevelStatsSim or {}
  local out = { recording = enabled(), simulator = D.model, flavor = a.flavor, level = a.cur }
  local bands = {}
  for _, b in ipairs(a.bands) do
    bands[#bands + 1] = ("%d-%d: %d min (simulator %d), %d level%s"):format(b.lo, b.hi, floor(b.real / 60 + 0.5), floor(b.sim / 60 + 0.5), b.n, b.n == 1 and "" or "s")
  end
  if #bands > 0 then out.bands = bands end
  if a.total.n > 0 then out.total = ("%d levels: %d min (simulator %d)"):format(a.total.n, floor(a.total.real / 60 + 0.5), floor(a.total.sim / 60 + 0.5)) end
  local cur = a.cur and a.levels[a.cur]
  if cur then out.now = ("level %d: %d min, %d quests, %d kills"):format(a.cur, floor(cur.real / 60 + 0.5), cur.q, cur.k) end
  if #a.missing > 0 then out.notRecorded = range(a.missing) end
  return out
end

-- /panoply levelstats [levels | zones | on | off | reset]
function LS:Slash(args)
  local sub = (args[2] or ""):lower()
  local lines
  if sub == "levels" or sub == "level" then lines = self:LevelLines()
  elseif sub == "zones" or sub == "zone" then lines = self:ZoneLines()
  elseif sub == "on" or sub == "off" then
    Panoply:SetOption("levelStats", sub == "on")
    lines = { sub == "on" and "Level times are recorded again." or "Level times are no longer recorded (what is saved stays; /panoply levelstats reset deletes it)." }
  elseif sub == "reset" then
    self:Reset()
    lines = { "Your level times are forgotten; Panoply Suite starts counting again from here." }
  elseif sub == "" or sub == "bands" or sub == "summary" then lines = self:SummaryLines()
  else lines = { "Usage: /panoply levelstats | levels | zones | on | off | reset" } end
  for _, l in ipairs(lines) do Panoply:Print(l) end
  return lines
end
