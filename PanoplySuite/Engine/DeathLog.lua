-- Panoply Suite death log (0.8.4): where, when and at what level this character died. Own code.
-- Each death is one small record in PanoplySuiteCharDB.deathLog (a new key; nothing else is touched):
--   { t = time, level =, zone =, sub =, map = (zone map id), x =, y = (0..1 on that map; none inside a dungeon),
--     inst = true inside a dungeon or raid, hc = true on a Hardcore realm (kept for later; nothing reads it yet) }
-- The newest MAX records are kept. Reads only: nothing here moves, targets or casts, and nothing is sent anywhere.
-- Where it shows: the Miscellaneous page (UI/Misc.lua), /panoply deaths, and the session summary counts today's.
local ADDON, Panoply = ...
local C = Panoply.Compat
local DL = {}
Panoply.DeathLog = DL

DL.MAX = 100          -- records kept (the oldest go first)
DL.REPEAT_S = 10      -- the game can say "dead" twice for one death: a second one this soon is the same death

Panoply.defaults.account.deathLog = true

local function wall() return (_G.time and _G.time()) or os.time() end

function DL:Store()
  local c = Panoply.cdb
  if not c then return nil end
  if type(c.deathLog) ~= "table" then c.deathLog = { v = 1, list = {} } end
  if type(c.deathLog.list) ~= "table" then c.deathLog.list = {} end
  return c.deathLog
end

function DL:On() return not (Panoply.db and Panoply.db.deathLog == false) end

-- Note a death now. Returns the record, or nil when it is off, a repeat, or a hunter playing dead.
function DL:Record()
  if not self:On() then return nil end
  local s = self:Store()
  if not s then return nil end
  local fd = _G.UnitIsFeignDeath
  if type(fd) == "function" then
    local ok, v = pcall(fd, "player")
    if ok and C.Readable(v) then return nil end
  end
  -- a ghost cannot die: the game saying "dead" again for one (at a login as a ghost) is not a new death
  if C.IsGhost and C.IsGhost() then return nil end
  local now = wall()
  local last = s.list[#s.list]
  if last and type(last.t) == "number" and now - last.t >= 0 and now - last.t < self.REPEAT_S then return nil end
  local level = C.XP()
  local zone, sub = C.ZoneText()
  local rec = { t = now, level = level, zone = zone ~= "" and zone or nil, sub = (sub ~= "" and sub ~= zone) and sub or nil }
  local inside = C.InInstance()
  if inside then rec.inst = true end
  local m, x, y = C.GetPlayerPos()
  if m and x and y then rec.map, rec.x, rec.y = m, math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000 end
  if C.IsHardcore and C.IsHardcore() then rec.hc = true end
  s.list[#s.list + 1] = rec
  while #s.list > self.MAX do table.remove(s.list, 1) end
  if Panoply.Session then Panoply.Session:NoteDeath() end
  Panoply:Fire("DEATH_LOGGED", rec)
  return rec
end

-- The records, newest first (a copy of the list; the records themselves are the saved ones).
function DL:List()
  local s = self:Store()
  local out = {}
  if not s then return out end
  for i = #s.list, 1, -1 do out[#out + 1] = s.list[i] end
  return out
end

function DL:Count() local s = self:Store() return s and #s.list or 0 end

function DL:Clear()
  local s = self:Store()
  if not s then return 0 end
  local n = #s.list
  s.list = {}
  Panoply:Fire("DEATH_LOGGED", nil)
  return n
end

-- "just now", "35 minutes ago", "3 days ago" (Home's own words when Home is loaded)
function DL.Ago(t, now)
  now = now or wall()
  if Panoply.Home and Panoply.Home.Ago then return Panoply.Home.Ago(t, now) end
  local s = now - (t or 0)
  if s < 90 then return "just now" end
  if s < 90 * 60 then return ("%d minutes ago"):format(math.floor(s / 60 + 0.5)) end
  if s < 36 * 3600 then local h = math.floor(s / 3600 + 0.5) return ("%d hour%s ago"):format(h, h == 1 and "" or "s") end
  local d = math.floor(s / 86400 + 0.5)
  return ("%d day%s ago"):format(d, d == 1 and "" or "s")
end

-- "Level 23, Duskwood (Raven Hill) 18.4, 56.2, 2 hours ago"
function DL.Text(rec, now)
  local where = rec.zone or "an unknown place"
  if rec.sub then where = where .. " (" .. rec.sub .. ")" end
  if rec.x and rec.y then where = where .. (" %.1f, %.1f"):format(rec.x * 100, rec.y * 100)
  elseif rec.inst then where = where .. ", inside" end
  return ("Level %d, %s, %s"):format(rec.level or 1, where, DL.Ago(rec.t, now))
end

-- The newest `n` deaths as lines (for the Miscellaneous page and /panoply deaths).
function DL:Lines(n)
  local out = {}
  local now = wall()
  for i, rec in ipairs(self:List()) do
    if n and i > n then break end
    out[#out + 1] = DL.Text(rec, now)
  end
  return out
end

-- "No deaths recorded.", "1 death recorded", "12 deaths recorded"
function DL:Headline()
  local n = self:Count()
  if n == 0 then return self:On() and "No deaths recorded" or "The death log is off" end
  return n == 1 and "1 death recorded" or ("%d deaths recorded"):format(n)
end

-- /panoply deaths [clear | on | off]
function DL:Slash(args)
  local sub = (args and args[2] or ""):lower()
  if sub == "clear" or sub == "reset" then
    local n = self:Clear()
    Panoply:Print(("The death log is empty now (%d removed)."):format(n))
  elseif sub == "on" or sub == "off" then
    Panoply:SetOption("deathLog", sub == "on")
    Panoply:Print(sub == "on" and "Deaths are recorded again." or "Deaths are no longer recorded. The ones already in the log stay.")
  else
    Panoply:Print(self:Headline() .. (self:Count() > 0 and ":" or "."))
    for _, l in ipairs(self:Lines(10)) do Panoply:Print(l) end
    if self:Count() > 10 then Panoply:Print(("...and %d older."):format(self:Count() - 10)) end
  end
end

Panoply:On("PLAYER_DEAD", function() DL:Record() end)
