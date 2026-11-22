-- Panoply Suite reports (SPEC-REPORTS.md): the report store, Panoply Suite's own Lua error capture and the
-- breadcrumb of recent internal events. Original code for Panoply Suite. No third-party code.
--
-- Loads right after Core/Init.lua so errors in the files after it are caught too.
-- Everything lives in ONE account-wide saved variable, PanoplySuiteReportsDB:
--   { schema, installId, nextSeq, settings = { send, includeName, chatNotice, captureErrors },
--     reports = { <report>, ... }  (newest last, at most MAX_REPORTS)
--     errors  = { [sig] = <error>, ... } (at most MAX_ERRORS signatures),
--     queuedNotice = true  (0.9.4: a "Report queued" notice is owed; removed once shown) }
-- 0.9.4 adds these keys on a report (Core/Reports.lua): credit (text the player typed in "Credit me as", at most 40 characters,
-- absent when empty) and, once the companion app has recorded a ticket (PanoplySuite_Plans/Tickets.lua): ticket ("PS-0042"),
-- ticketN, ticketStatus, fixedIn, toldReceived, toldFixed. kind is "step", "general" or "feedback".
-- The game never sends anything. Panoply Hub (PanoplyHub/) reads the saved file when it runs and sends the
-- confirmed reports that are waiting, unless settings.send is off. With World of Warcraft closed it writes
-- sent = true (and sentAt) back on the reports it sent, through its write journal; nothing else is changed.
--
-- Privacy (SPEC-REPORTS 3): never chat, whispers, the account name, BattleTag, email, or another
-- add-on's data. 0.9.4: neither a saved REPORT nor an error record ever carries the character's name, realm, race or class. The old
-- settings.includeName key stays in the saved data untouched and is never read (no switch for it exists any more); what older
-- versions saved is scrubbed once per character (R:ScrubStored, marker db.scrubbed094).
local ADDON, Panoply = ...
Panoply = Panoply or {}

local R = Panoply.Reports or {}
Panoply.Reports = R

R.SCHEMA = 1
R.MAX_REPORTS = 50
R.MAX_ERRORS = 100
R.MAX_BYTES = 256 * 1024        -- rough size of everything kept (reports + errors)
R.MAX_NOTE = 500
R.MAX_CRUMBS = 30
R.MAX_MSG = 400
R.MAX_STACK_LINES = 12
R.MAX_LINE = 160
-- 0.9.5 phase 4A4: send is the sharing setting (Core/Sharing.lua) and its standard is OFF (06b section 2); Reset puts it back to off
R.SETTINGS = { send = false, includeName = false, chatNotice = true, captureErrors = true }

R.crumbs = {}                    -- this session's breadcrumb (strings, newest last)
R.pending = {}                   -- errors seen before the saved variables were loaded
R.session = { errors = 0, noticed = false, start = nil }

local function now() return (_G.time and _G.time()) or os.time() end
local function clock() return (_G.GetTime and _G.GetTime()) or 0 end

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
-- 32-bit string hash (no bit library in Lua 5.1): 8 hex digits.
function R.Hash(s)
  local h = 5381
  s = tostring(s or "")
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return ("%08x"):format(h)
end

-- The character's own name and realm (to scrub them out of free text): the name, the realm as the game spells it, the realm
-- without spaces or punctuation (the "normalized" form), each once.
function R.Identity()
  local out, seen = {}, {}
  local function put(v)
    if type(v) ~= "string" then return end
    if _G.issecretvalue and _G.issecretvalue(v) then return end
    if #v < 2 or seen[v:lower()] then return end
    seen[v:lower()] = true
    out[#out + 1] = v
  end
  local function add(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if not ok then return end
    put(a)
    put(b)
    if type(a) == "string" and not (_G.issecretvalue and _G.issecretvalue(a)) then put((a:gsub("[%s%p]", ""))) end
  end
  add(_G.UnitName, "player")
  add(_G.GetRealmName)
  add(_G.GetNormalizedRealmName)
  return out
end

local function cut(s, n)
  s = tostring(s or "")
  if #s > n then return s:sub(1, n - 3) .. "..." end
  return s
end
R.Cut = cut

-- Remove anything personal from free text Panoply Suite did not write itself (error messages, stack
-- lines, the player's note): emails, BattleTags, other add-ons' names in paths, and the character
-- name and realm (whole words only). keepName = true skips ONLY the name and realm step; the one caller that passes it is
-- R:ScrubAll for Panoply Suite's own data titles (0.9.4 review K4), never free text, an error or a note.
function R:Scrub(s, keepName)
  s = tostring(s or "")
  s = s:gsub("[%w%._%%%+%-]+@[%w%.%-]+%.%a%a+", "<email>")
  s = s:gsub("[%a\128-\255][%w\128-\255]*#%d%d%d%d+", "<battletag>")
  -- paths: keep Panoply Suite's own files, hide every other add-on's folder name
  s = s:gsub("[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]([^\\/:%]\"]+)", function(dir)
    if dir:find("^PanoplySuite") then return "AddOns/" .. dir end
    return "AddOns/<other add-on>"
  end)
  -- a full disk path before the game folder (C:\Games\World of Warcraft\_classic_era_\...) never leaves
  s = s:gsub("%a:[\\/][^:\n]-[\\/](AddOns/)", "%1")
  s = s:gsub("/Users/[^/\n]+/[^:\n]-/(AddOns/)", "%1")
  if not keepName then
    for _, w in ipairs(R.Identity()) do
      -- whole words only ("we" must not turn "Edit" into "<character>it"), in any capitalisation ("zorvandel", "ZORVANDEL")
      local pat = w:gsub("%p", "%%%0"):gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
      s = s:gsub("%f[%w\128-\255]" .. pat .. "%f[^%w\128-\255]", "<character>")
    end
  end
  return s
end

-------------------------------------------------------------------------------
-- The saved variable
-------------------------------------------------------------------------------
local function newInstallId()
  local t = {}
  for i = 1, 12 do t[i] = ("%x"):format(math.random(0, 15)) end
  return "i" .. table.concat(t)
end

function R:InitDB()
  local db = _G.PanoplySuiteReportsDB
  if type(db) ~= "table" then db = {} _G.PanoplySuiteReportsDB = db end
  db.schema = R.SCHEMA
  if type(db.installId) ~= "string" or not db.installId:find("^i%x+$") then db.installId = newInstallId() end
  db.nextSeq = tonumber(db.nextSeq) or 1
  if type(db.settings) ~= "table" then db.settings = {} end
  for k, v in pairs(R.SETTINGS) do if db.settings[k] == nil then db.settings[k] = v end end
  if type(db.reports) ~= "table" then db.reports = {} end
  if type(db.errors) ~= "table" then db.errors = {} end
  self.db = db
  -- 0.9.5 phase 4A4: the one sharing setting (Core/Sharing.lua): settings.share, OFF to start; settings.send follows it
  if Panoply.Sharing then Panoply.Sharing:Migrate(db) end
  self:ScrubStored()
  self:MarkFixed()
  -- errors seen while the add-on was still loading
  local pend = self.pending
  self.pending = {}
  for _, p in ipairs(pend) do self:StoreError(p) end
  self:Enforce()
  return db
end

-- 0.9.4 (review B1): what 0.9.3 and earlier saved may hold the character's name and realm (the old account-wide "Include my
-- character name and realm" setting kept them in noted error records and in the player block and text of reports). Scrub it once
-- per character, in place: only VALUES change; no key is renamed or removed, quest recordings and Skyborne records are not in this
-- table. The marker is db.scrubbed094 = { [hash of this character's name and realm] = true } (a hash, never the name): another
-- character of the same account that logs in later still gets its own pass. Reports Panoply Hub has marked sent are left as they
-- are (they have already left); every other report loses player.name, realm, race and class (the companion app drops them too,
-- the second lock) and has its free text scrubbed.
local function scrubList(R, list)
  if type(list) ~= "table" then return end
  for i, v in ipairs(list) do if type(v) == "string" then list[i] = R:Scrub(v, false) end end
end
function R:ScrubStored()
  local db = self.db
  if not db then return false end
  local ids = R.Identity()
  if #ids == 0 then return false end   -- the game does not know the character yet: try again at login
  local parts = {}
  for i, v in ipairs(ids) do parts[i] = v:lower() end
  local mark = R.Hash(table.concat(parts, "|"))
  if type(db.scrubbed094) ~= "table" then db.scrubbed094 = {} end
  if db.scrubbed094[mark] then return false end
  for _, e in pairs(db.errors) do
    if type(e) == "table" then
      if type(e.msg) == "string" then e.msg = R:Scrub(e.msg, false) end
      if type(e.where) == "string" then e.where = R:Scrub(e.where, false) end
      scrubList(R, e.stack)
      scrubList(R, e.crumbs)
    end
  end
  for _, r in ipairs(db.reports) do
    if type(r) == "table" and r.sent ~= true then
      if type(r.player) == "table" then
        r.player.name, r.player.realm, r.player.race, r.player.class = nil, nil, nil, nil
      end
      if type(r.note) == "string" then r.note = R:Scrub(r.note, false) end
      if type(r.where) == "table" then
        for _, k in ipairs({ "zone", "subzone" }) do
          if type(r.where[k]) == "string" then r.where[k] = R:Scrub(r.where[k], false) end
        end
      end
      scrubList(R, r.breadcrumb)
      if type(r.errors) == "table" then
        for _, e in ipairs(r.errors) do if type(e) == "table" and type(e.msg) == "string" then e.msg = R:Scrub(e.msg, false) end end
      end
    end
  end
  db.scrubbed094[mark] = true
  return true
end

function R:Setting(key)
  local s = self.db and self.db.settings
  if s and s[key] ~= nil then return s[key] end
  return R.SETTINGS[key]
end
function R:SetSetting(key, value)
  if not self.db then return end
  -- 0.9.5 phase 4A4: "send" is the sharing setting now (Core/Sharing.lua keeps settings.share and settings.send together)
  if key == "send" and Panoply.Sharing then Panoply.Sharing:Set(value) return end
  local old = self.db.settings[key]
  self.db.settings[key] = value
  if old ~= value and Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "setting") end
end

-- Rough size in bytes of a saved value (what it adds to PanoplySuiteReportsDB.lua).
function R.Size(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "string" then return #v + 4 end
  if t ~= "table" then return 8 end
  if depth > 8 then return 0 end
  local n = 4
  for k, x in pairs(v) do n = n + R.Size(k, depth + 1) + R.Size(x, depth + 1) + 4 end
  return n
end

-- Keep the caps: newest MAX_REPORTS reports, MAX_ERRORS error signatures (the ones seen most
-- recently win), and MAX_BYTES in all (oldest reports go first, then the oldest errors).
function R:Enforce()
  local db = self.db
  if not db then return end
  while #db.reports > R.MAX_REPORTS do table.remove(db.reports, 1) end
  if type(db.localReports) == "table" then while #db.localReports > R.MAX_REPORTS do table.remove(db.localReports, 1) end end
  local list = {}
  for sig, e in pairs(db.errors) do
    if type(e) == "table" then list[#list + 1] = e else db.errors[sig] = nil end
  end
  table.sort(list, function(a, b)
    if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
    return tostring(a.sig) < tostring(b.sig)
  end)
  for i = R.MAX_ERRORS + 1, #list do db.errors[list[i].sig] = nil list[i] = nil end
  local total = 0
  for _, r in ipairs(db.reports) do total = total + (r.bytes or R.Size(r)) end
  local errBytes = {}
  for i, e in ipairs(list) do errBytes[i] = R.Size(e) total = total + errBytes[i] end
  while total > R.MAX_BYTES and #db.reports > 0 do
    local r = table.remove(db.reports, 1)
    total = total - (r.bytes or R.Size(r))
  end
  local i = #list
  while total > R.MAX_BYTES and i >= 1 do
    db.errors[list[i].sig] = nil
    total = total - errBytes[i]
    i = i - 1
  end
  self.bytes = total
end

function R:NextId(prefix)
  local db = self.db
  local seq = db and db.nextSeq or 1
  if db then db.nextSeq = seq + 1 end
  return ("%s-%s-%d-%d"):format(prefix or "r", db and db.installId or "i0", now(), seq)
end

-- Reports and error signatures kept (Panoply Hub keeps its own list of what it sent, too).
function R:Counts()
  local db = self.db
  if not db then return 0, 0 end
  local e = 0
  for _ in pairs(db.errors) do e = e + 1 end
  return #db.reports, e
end

-- Reports Panoply Hub has marked sent, reports still waiting for it, and reports the report server refused for good
-- (Hub marks those refused = true; they are never sent again).
function R:SendCounts()
  local db = self.db
  if not db then return 0, 0, 0 end
  local sent, waiting, refused = 0, 0, 0
  for _, r in ipairs(db.reports) do
    if r.sent == true then sent = sent + 1 elseif r.refused == true then refused = refused + 1 else waiting = waiting + 1 end
  end
  return sent, waiting, refused
end

-- 0.9.5 phase 4L (spec 06 section 6): Noted problems' Clear: every noted problem goes; saved reports stay.
function R:ClearErrors()
  if not self.db then return end
  self.db.errors = {}
  if Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "clearErrors") end
end

function R:ClearAll()
  if not self.db then return end
  self.db.reports = {}
  self.db.errors = {}
  if Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "clear") end
end

-------------------------------------------------------------------------------
-- Breadcrumb: Panoply Suite's own internal events (never chat or other add-ons). Numbers and
-- true/false are kept; text only when it is one of Panoply Suite's own short keys (OPTION_CHANGED
-- "autoFly", STEP_CHANGED "manual"), never names.
-------------------------------------------------------------------------------
R.CRUMB_TEXT_ARGS = { OPTION_CHANGED = true, STEP_CHANGED = true, ROUTE_UPDATED = true, PLAN_ADOPTED = true,
                      GUIDE_CHANGED = true, REPORTS_CHANGED = true, MODULE_TOGGLED = true }
R.CRUMB_GAME_EVENTS = { PLAYER_LEVEL_UP = true, QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true,
                        PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true, TAXIMAP_OPENED = true,
                        PLAYER_CONTROL_LOST = true, PLAYER_CONTROL_GAINED = true, PLAYER_DEAD = true,
                        PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, ADDON_ACTION_BLOCKED = true,
                        ADDON_ACTION_FORBIDDEN = true }
local function crumbArg(event, v, textOK)
  local t = type(v)
  if t == "number" then return (v == math.floor(v)) and tostring(v) or ("%.2f"):format(v) end
  if t == "boolean" then return tostring(v) end
  if t == "string" and textOK and #v <= 24 and v:find("^[%w_%.:%-]+$") then return v end
  return nil
end
function R:Crumb(event, ...)
  if type(event) ~= "string" then return end
  local textOK = R.CRUMB_TEXT_ARGS[event]
  local parts = { event }
  for i = 1, math.min(select("#", ...), 3) do
    local a = crumbArg(event, (select(i, ...)), textOK)
    if a then parts[#parts + 1] = a end
  end
  local body = table.concat(parts, " ")
  local list = self.crumbs
  local last = list[#list]
  if last and last.body == body then last.n = last.n + 1 last.at = clock() return end
  list[#list + 1] = { body = body, n = 1, at = clock() }
  while #list > R.MAX_CRUMBS do table.remove(list, 1) end
end
-- The breadcrumb as text lines: "+12.3s STEP_CHANGED 5 manual (x3)", seconds since the session began.
function R:Breadcrumb()
  local out = {}
  local t0 = self.session.start or 0
  for _, c in ipairs(self.crumbs) do
    out[#out + 1] = ("+%.1fs %s%s"):format(math.max(0, (c.at or 0) - t0), c.body, c.n > 1 and (" (x" .. c.n .. ")") or "")
  end
  return out
end

-------------------------------------------------------------------------------
-- Error capture
-------------------------------------------------------------------------------
-- "AddOns/PanoplySuite..." (the game) or "addon/PanoplySuite..." (the offline test copy)
local OURS = "[Aa]dd[Oo]ns?[\\/](PanoplySuite[^\\/:]*)"
local ANY_ADDON = "[Aa]dd[Oo]ns?[\\/]([^\\/:%]\"]+)[\\/]"

-- Is this error Panoply Suite's? The file named in the message decides; a message without an add-on
-- file (an error inside the game's own code) is ours when the first add-on frame on the stack is.
function R.IsOurs(msg, stack)
  msg = tostring(msg or "")
  local dir = msg:match(ANY_ADDON)
  if dir then return dir:find("^PanoplySuite") ~= nil end
  for line in tostring(stack or ""):gmatch("[^\n]+") do
    local d = line:match(ANY_ADDON)
    if d then return d:find("^PanoplySuite") ~= nil end
  end
  return false
end

-- Trimmed stack: at most MAX_STACK_LINES lines, each cut to MAX_LINE, scrubbed (keepName is false in every real call).
function R:TrimStack(stack, keepName)
  local out = {}
  for line in tostring(stack or ""):gmatch("[^\n]+") do
    line = line:gsub("^%s+", "")
    if line ~= "" and not line:find("ErrorCapture%.lua") then
      out[#out + 1] = cut(self:Scrub(line, keepName), R.MAX_LINE)
      if #out >= R.MAX_STACK_LINES then break end
    end
  end
  return out
end

-- The message as the signature sees it: addresses and numbers become "#" so "table: 0x1234abcd",
-- "got 17 items" and "got 18 items" stay one problem. The line number after a file name is kept
-- (that is where the problem is), and so is the first stack line in the signature.
function R.Normalize(msg)
  msg = tostring(msg or ""):gsub("0x%x+", "#")
  return (msg:gsub("()(%d+%.?%d*)", function(at, num)
    if msg:sub(math.max(1, at - 5), at - 1) == ".lua:" then return num end
    return "#"
  end))
end
local normalize = R.Normalize

-- Record one problem. kind: "lua" (the game's error handler), "caught" (an error Panoply Suite caught
-- itself and logged), "blocked" / "forbidden" (ADDON_ACTION_BLOCKED / _FORBIDDEN).
function R:NoteError(kind, msg, stack, where)
  if self.db and not self:Setting("captureErrors") then return nil end
  -- 0.9.4 (review B1): the character name and realm are ALWAYS removed from an error record (message, stack lines, where, crumbs),
  -- whatever the old account-wide settings.includeName says: the consent notice promises it and the companion app uploads these
  -- records on its own. That saved key is kept in the data and is never read.
  local clean = cut(self:Scrub(msg, false), R.MAX_MSG)
  local crumbs = {}
  for i, line in ipairs(self:Breadcrumb()) do crumbs[i] = self:Scrub(line, false) end
  local rec = { kind = kind or "lua", msg = clean, stack = self:TrimStack(stack, false),
                where = where and cut(self:Scrub(where, false), 60) or nil, at = now(), crumbs = crumbs }
  rec.sig = R.Hash((kind or "lua") .. "|" .. normalize(clean) .. "|" .. tostring(rec.stack[1] or ""))
  self.session.errors = self.session.errors + 1
  if not self.db then
    if #self.pending < 50 then self.pending[#self.pending + 1] = rec end
  else
    self:StoreError(rec)
  end
  self:Notice()
  return rec.sig
end

function R:StoreError(rec)
  local db = self.db
  local e = db.errors[rec.sig]
  if e then
    e.count = (e.count or 1) + 1
    e.last = rec.at
    e.version = Panoply.version
    e.fixedIn = self:FixedIn(e)   -- 0.9.5: seen again in a version with the fix: it is not fixed after all
  else
    local C = Panoply.Compat
    local v, b
    if C and C.BuildInfo then v, b = C.BuildInfo() end
    e = { sig = rec.sig, kind = rec.kind, msg = rec.msg, stack = rec.stack, where = rec.where, count = 1, first = rec.at,
          last = rec.at, crumbs = rec.crumbs, version = Panoply.version, game = v and (tostring(v) .. " (" .. tostring(b) .. ")") or nil,
          flavor = C and C.Flavor and C.Flavor() or nil, sent = false }
    db.errors[rec.sig] = e
    self:Enforce()
  end
  if Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "error") end
  return e
end

-- 0.9.5 phase 4A4 (spec 06 section 0.2): problems a later version fixed. A noted problem whose message matches and that was last seen
-- in a version before the fix gets fixedIn (a NEW key on the record; nothing else changes), so Noted problems can say it is fixed
-- instead of showing an old count as if it were still happening. Seen again in a fixed version, it is a new problem and loses the mark.
--   bb7adf08 (and the same error under the old Hearthpath folder: 22794f78, b37b3d2e, 63e15326): WoW Forever handed GetUnitSpeed's run
--   speed back as a secret number while add-ons were restricted, and Route:LearnSpeed compared it, once per bag-cooldown event (about once
--   a second). Fixed in 0.8.3: C.Readable turns a secret into nil before the compare (Engine/Route.lua, test "bugs06:").
R.KNOWN_FIXES = {
  { match = "Engine[\\/]Route%.lua:%d+: attempt to compare local 'run' %(a secret", fixedIn = "0.8.3" },
}
local function older(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y end
  end
  return false
end
R.VersionOlder = older
function R:FixedIn(e)
  if type(e) ~= "table" or type(e.msg) ~= "string" then return nil end
  for _, f in ipairs(R.KNOWN_FIXES) do
    if e.msg:find(f.match) and older(e.version or "0", f.fixedIn) then return f.fixedIn end
  end
  return nil
end
function R:MarkFixed()
  local n = 0
  for _, e in pairs(self.db and self.db.errors or {}) do
    if type(e) == "table" then
      local v = self:FixedIn(e)
      if v and e.fixedIn ~= v then e.fixedIn = v n = n + 1
      elseif not v and e.fixedIn then e.fixedIn = nil end
    end
  end
  return n
end

-- One quiet chat line per session (setting, on by default); never a popup.
R.NOTICE = "Panoply Suite hit a problem; it's been noted. Help > gear > Reports and privacy shows what is kept."
function R:Notice()
  if self.session.noticed then return end
  if self.db and not self:Setting("chatNotice") then return end
  if not self.db then self.session.wantNotice = true return end
  self.session.noticed = true
  local function say() if Panoply.Print then Panoply:Print(R.NOTICE) end end
  local C = Panoply.Compat
  -- not from inside the error handler: the next frame
  if C and C.After then C.After(0, say) else say() end
end

-- The game's error handler, chained: Panoply Suite records its own errors and then always passes
-- every error on to whatever handler was there before (the game's, or another error add-on's).
-- It never swallows an error and never errors itself.
local busy = false
function R.OnLuaError(msg, ...)
  if not busy then
    busy = true
    pcall(function()
      local stack = _G.debugstack and _G.debugstack(4, 24, 0) or ""
      if R.IsOurs(msg, stack) then R:NoteError("lua", msg, stack) end
    end)
    busy = false
  end
end
function R:InstallHandler()
  local get, set = _G.geterrorhandler, _G.seterrorhandler
  if type(get) ~= "function" or type(set) ~= "function" or self.handler then return false end
  local prev = get()
  local function handler(msg, ...)
    R.OnLuaError(msg, ...)
    if prev and prev ~= handler then return prev(msg, ...) end
  end
  self.handler, self.prevHandler = handler, prev
  set(handler)
  return true
end

-- Errors Panoply Suite catches itself (pcall around every event handler, callback and login step) end
-- up in Panoply:Debug with the message. Pick out the ones that carry a Lua error location in our files.
function R:WatchDebug()
  if self.debugWrapped or type(Panoply.Debug) ~= "function" then return end
  self.debugWrapped = true
  local debug0 = Panoply.Debug
  function Panoply:Debug(...)
    local r = debug0(self, ...)
    if not busy then
      busy = true
      local n, args = select("#", ...), { ... }
      pcall(function()
        local where
        for i = 1, n do
          local v = args[i]
          if type(v) == "string" and v:find(OURS .. "[^:]*:%d+:") then
            R:NoteError("caught", v, _G.debugstack and _G.debugstack(3, 12, 0) or "", where)
            break
          elseif i <= 2 and type(v) == "string" then where = (where and (where .. " ") or "") .. v end
        end
      end)
      busy = false
    end
    return r
  end
end

-- Breadcrumbs from Panoply Suite's own callbacks and a few game events.
function R:WatchEvents()
  if self.fireWrapped then return end
  self.fireWrapped = true
  local fire, dispatch = Panoply.Fire, Panoply.Dispatch
  if type(fire) == "function" then
    function Panoply:Fire(name, ...)
      if name ~= "REPORTS_CHANGED" then pcall(R.Crumb, R, name, ...) end
      return fire(self, name, ...)
    end
  end
  if type(dispatch) == "function" then
    function Panoply:Dispatch(event, ...)
      if R.CRUMB_GAME_EVENTS[event] then pcall(R.Crumb, R, event, ...) end
      return dispatch(self, event, ...)
    end
  end
end

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN name the add-on the game blamed. Only Panoply Suite's.
function R.OnBlocked(event, addon, func)
  if type(addon) ~= "string" or not addon:find("^PanoplySuite") then return end
  local kind = event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked"
  local stack = _G.debugstack and _G.debugstack(3, 12, 0) or ""
  R:NoteError(kind, ("%s tried to call %s"):format(addon, tostring(func or "?")), stack)
end

-------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------
R.session.start = clock()
R:InstallHandler()
R:WatchDebug()
R:WatchEvents()
if Panoply.On then
  Panoply:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON and name ~= "PanoplySuite" then return end
    if R.db and R.db == _G.PanoplySuiteReportsDB then return end
    R:InitDB()
    if R.session.wantNotice then R.session.wantNotice = nil R:Notice() end
  end)
  Panoply:On("ADDON_ACTION_BLOCKED", R.OnBlocked)
  Panoply:On("ADDON_ACTION_FORBIDDEN", R.OnBlocked)
end
