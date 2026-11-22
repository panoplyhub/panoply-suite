-- Panoply Suite: brings the old Hearthpath saved data across, once, and only when the copy checks out.
-- Original code for Panoply Suite. No third-party code.
--
-- Why this is needed: the game loads saved data by the add-on folder's name. Panoply Suite's folder is
-- "PanoplySuite", so the game never hands it the old WTF/.../SavedVariables/Hearthpath.lua files. The
-- installer therefore puts a tiny stand-in add-on in the old "Hearthpath" folder: no game code at all,
-- only the four old saved-data names in its TOC, so the game keeps loading the old account files and every
-- character's file. Panoply Suite lists it under OptionalDeps, so the stand-in loads first and its data
-- is already there when Panoply Suite's ADDON_LOADED arrives (this handler is the first one registered).
--
-- What it does, per table (account: HearthpathDB, HearthpathAuctionDB, HearthpathReportsDB; character:
-- HearthpathCharDB), into PanoplySuiteDB, PanoplySuiteAuctionDB, PanoplySuiteReportsDB, PanoplySuiteCharDB:
--   * already marked done (legacyImport in the new table): nothing, ever again (no quest is copied twice)
--   * old one missing: nothing to copy; no mark. If the stand-in exists but is turned off, that is a
--     problem and is said on screen (the old data could not load), nothing is marked
--   * old one empty: nothing to copy; no mark (an empty copy is never a finished one)
--   * old one not a table, or with a loop / odd key or value in it: a problem, said on screen, nothing changed
--   * otherwise: a deep copy (new tables throughout, nothing shared with the old ones). An existing
--     Panoply table is never replaced: only what it does not have yet is added from the old one, and what
--     it already has stays. The result is checked against the old data (every old value is there, equal,
--     and in its own table); only then is the mark written. A failed check puts the new table back as
--     it was and says so.
-- The old tables are only ever read. The game writes them back to Hearthpath.lua at log out (same data;
-- the file's date changes), so going back to the old add-on finds them exactly as they were.
local ADDON, Panoply = ...

local M = { V = 1, STANDIN = "Hearthpath", STANDIN_FIELD = "X-Panoply-StandIn" }
Panoply.Migrate = M

M.TABLES = {
  { old = "HearthpathDB",        new = "PanoplySuiteDB",        scope = "account", what = "settings, routes and quest records" },
  { old = "HearthpathAuctionDB", new = "PanoplySuiteAuctionDB", scope = "account", what = "auction history" },
  { old = "HearthpathReportsDB", new = "PanoplySuiteReportsDB", scope = "account", what = "problem reports" },
  { old = "HearthpathCharDB",    new = "PanoplySuiteCharDB",    scope = "char",    what = "this character's settings and windows" },
}

-------------------------------------------------------------------------------
-- Plain table helpers (saved data holds only strings, numbers, booleans and tables)
-------------------------------------------------------------------------------
local KEY_OK = { string = true, number = true, boolean = true }
local VAL_OK = { string = true, number = true, boolean = true, table = true }

-- nil when t is plain saved data; otherwise a short reason ("a loop", "a function value", ...)
function M.Check(t)
  local open = {}
  local function walk(x, depth)
    if open[x] then return "a table inside itself" end
    if depth > 200 then return "tables nested too deep" end
    open[x] = true
    for k, v in pairs(x) do
      if not KEY_OK[type(k)] then return "a " .. type(k) .. " key" end
      if type(k) == "number" and k ~= k then return "a NaN key" end
      if not VAL_OK[type(v)] then return "a " .. type(v) .. " value" end
      if type(v) == "table" then local bad = walk(v, depth + 1) if bad then return bad end end
    end
    open[x] = nil
    return nil
  end
  return walk(t, 0)
end

local function deepCopy(x)
  if type(x) ~= "table" then return x end
  local out = {}
  for k, v in pairs(x) do out[k] = deepCopy(v) end
  return out
end
M.DeepCopy = deepCopy

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
M.DeepEqual = deepEqual

-- Stable written-out form (keys sorted by type, then value), for exact before/after comparisons.
local TYPE_ORDER = { boolean = 1, number = 2, string = 3 }
local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return TYPE_ORDER[ta] < TYPE_ORDER[tb] end
  if ta == "boolean" then return (not a) and b end
  return a < b
end
local function lit(v)
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t == "number" then
    if v == math.floor(v) and v > -2^53 and v < 2^53 then return ("%d"):format(v) end
    return ("%.17g"):format(v)
  end
  return tostring(v)
end
function M.Serialize(x)
  if type(x) ~= "table" then return lit(x) end
  local keys = {}
  for k in pairs(x) do keys[#keys + 1] = k end
  table.sort(keys, keyLess)
  local parts = {}
  for i, k in ipairs(keys) do parts[i] = "[" .. lit(k) .. "]=" .. M.Serialize(x[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- A list: keys exactly 1..n (n > 0). Lists (reports, saved roads, waypoints, the menu order) are merged by
-- their entries, never by position: the winner's entries stay as they are, in order, and the other side's
-- entries that the winner does not have are added after them. An entry is the same entry when it has the
-- same id (a table with an id field), otherwise when it is equal written out.
local function isList(t)
  if type(t) ~= "table" then return false end
  local n = #t
  if n == 0 then return false end
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c == n
end
M.IsList = isList
local function entryKey(e)
  if type(e) == "table" and (type(e.id) == "string" or type(e.id) == "number") then return "id:" .. tostring(e.id) end
  return "v:" .. M.Serialize(e)
end
-- the merged list as it must come out: win's entries, then lose's entries win does not have (each once)
local function mergedList(win, lose)
  local out, seen = {}, {}
  for i = 1, #win do out[i] = win[i] seen[entryKey(win[i])] = true end
  for i = 1, #lose do
    local k = entryKey(lose[i])
    if not seen[k] then seen[k] = true out[#out + 1] = lose[i] end
  end
  return out
end

-- Adds to dst everything of src that dst does not have yet (deep copies); never changes what dst has.
local function fillMissing(dst, src)
  for k, v in pairs(src) do
    local d = dst[k]
    if d == nil then
      dst[k] = deepCopy(v)
    elseif isList(d) and isList(v) then
      local seen = {}
      for i = 1, #d do seen[entryKey(d[i])] = true end
      for i = 1, #v do
        local ek = entryKey(v[i])
        if not seen[ek] then seen[ek] = true d[#d + 1] = deepCopy(v[i]) end
      end
    elseif type(d) == "table" and type(v) == "table" then
      fillMissing(d, v)
    end
  end
end

local function tablesOf(x, set)
  set = set or {}
  if type(x) == "table" and not set[x] then
    set[x] = true
    for _, v in pairs(x) do tablesOf(v, set) end
  end
  return set
end

-- The check after the copy: new must be exactly "win, with what only lose has added". win = what the new
-- table held before (nil when it did not exist: then new must equal lose exactly), lose = the other side.
-- Lists come out as mergedList(win, lose). No table of new may be one of win's or lose's.
function M.Verify(lose, new, win)
  if type(new) ~= "table" then return false, "the new table is missing" end
  local others = tablesOf(lose)
  if win then tablesOf(win, others) end
  for t in pairs(tablesOf(new)) do if others[t] then return false, "a table is shared with the old data" end end
  local function walk(o, n, b, path)
    if type(n) ~= "table" then return false, path .. " lost" end
    for k, ov in pairs(o) do
      local nv, bv = n[k], b and b[k]
      local here = path .. "." .. tostring(k)
      if bv ~= nil then
        if isList(ov) and isList(bv) then
          if not deepEqual(nv, mergedList(bv, ov)) then return false, here .. " (a list) not merged right" end
        elseif type(ov) == "table" and type(bv) == "table" then
          local ok, why = walk(ov, nv, bv, here)
          if not ok then return false, why end
        elseif not deepEqual(nv, bv) then
          return false, here .. " changed"
        end
      elseif not deepEqual(nv, ov) then
        return false, here .. " not copied"
      end
    end
    if b then for k, bv in pairs(b) do if o[k] == nil and not deepEqual(n[k], bv) then return false, path .. "." .. tostring(k) .. " changed" end end end
    for k in pairs(n) do
      if o[k] == nil and not (b and b[k] ~= nil) and not (path == "" and k == "legacyImport") then return false, path .. "." .. tostring(k) .. " came from nowhere" end
    end
    return true
  end
  local ok, why = walk(lose, new, win, "")
  if not ok then return false, why end
  if not win then
    local copy = {}
    for k, v in pairs(new) do if k ~= "legacyImport" then copy[k] = v end end
    if M.Serialize(copy) ~= M.Serialize(lose) then return false, "the copy does not match the old data" end
  end
  return true
end

-- The check for a legacyPending table: the old data wins, and what that stopgap session added (what the old
-- data does not have, and list entries it does not have) is kept: the same check with the roles swapped.
function M.VerifyOldWins(old, new, before)
  return M.Verify(before or {}, new, old)
end

-------------------------------------------------------------------------------
-- The stand-in add-on
-------------------------------------------------------------------------------
-- "loaded" (the stand-in ran, its data is here), "full" (an old full Hearthpath ran instead of the
-- stand-in), "off" (the folder is there but the game did not load it), "missing" (no Hearthpath folder)
function M.StandIn()
  local C = Panoply.Compat
  local name = M.STANDIN
  local loaded = C and C.IsAddOnLoaded and C.IsAddOnLoaded(name)
  local meta = (C and C.G and C.G("C_AddOns.GetAddOnMetadata")) or _G.GetAddOnMetadata
  local isStandIn
  if meta then
    local ok, v = pcall(meta, name, M.STANDIN_FIELD)
    isStandIn = ok and v ~= nil and tostring(v) ~= ""
  end
  if loaded then return isStandIn and "loaded" or "full" end
  local info = (C and C.G and C.G("C_AddOns.GetAddOnInfo")) or _G.GetAddOnInfo
  if info then
    local ok, n, _, _, _, reason = pcall(info, name)
    if ok and n and reason ~= "MISSING" then return "off" end
  end
  return "missing"
end

-------------------------------------------------------------------------------
-- The copy
-------------------------------------------------------------------------------
-- One table. Returns a status word and, for a problem, the reason:
--   done-before | copied | merged | none | empty | not-loaded (problem) | malformed (problem) | failed (problem)
function M.One(t, standIn)
  local old, new = _G[t.old], _G[t.new]
  if type(new) == "table" and type(new.legacyImport) == "table" and new.legacyImport.v then return "done-before" end
  if old == nil then
    if standIn == "off" then return "not-loaded", "the Hearthpath (old saved data) add-on is turned off" end
    return "none"
  end
  if type(old) ~= "table" then return "malformed", "the old " .. t.old .. " is a " .. type(old) .. ", not a table" end
  local bad = M.Check(old)
  if bad then return "malformed", "the old " .. t.old .. " holds " .. bad end
  if next(old) == nil then return "empty" end
  if new ~= nil and type(new) ~= "table" then return "malformed", t.new .. " is a " .. type(new) .. ", not a table" end
  if new ~= nil then
    local badNew = M.Check(new)
    if badNew then return "malformed", t.new .. " holds " .. badNew end
  end
  -- A table made while the old data could not load (legacyPending) was only a stand-in for it: the old
  -- values win there, and what that session added (keys the old data does not have) is kept.
  local pending = type(new) == "table" and new.legacyPending == true
  local before = new ~= nil and deepCopy(new) or nil
  if pending then before.legacyPending = nil end
  local target, ok, err, why
  if pending then
    target = deepCopy(old)
    ok, err = pcall(fillMissing, target, before)
    if ok then ok, why = M.VerifyOldWins(old, target, before) end
  else
    target = before and deepCopy(before) or {}
    ok, err = pcall(fillMissing, target, old)
    if ok then ok, why = M.Verify(old, target, before) end
  end
  if not ok then
    -- nothing was changed: the copy was made on the side and is dropped
    return "failed", "the copy of " .. t.old .. " did not check out (" .. tostring(why or err) .. ")"
  end
  local merged = before ~= nil and next(before) ~= nil
  target.legacyImport = { v = M.V, from = t.old, at = (_G.time and _G.time()) or 0, merged = merged or nil }
  _G[t.new] = target
  return merged and "merged" or "copied"
end

local PROBLEM = { ["not-loaded"] = true, malformed = true, failed = true }

-- Runs once per session, at Panoply Suite's ADDON_LOADED (never later: other code holds the tables by
-- then; /panoply import only reports, and a /reload tries again). Returns the result
-- { standIn, tables = { [oldName] = { status, why } }, problems = { text } }.
function M.Stopgap(t) if _G[t.new] == nil then _G[t.new] = { legacyPending = true } end end

function M:Run()
  if self.result then return self.result end
  local standIn = M.StandIn()
  local res = { standIn = standIn, tables = {}, problems = {} }
  for _, t in ipairs(M.TABLES) do
    local status, why = M.One(t, standIn)
    res.tables[t.old] = { status = status, why = why }
    if PROBLEM[status] then
      res.problems[#res.problems + 1] = ("Your old Hearthpath %s could not be brought across: %s."):format(t.what, why)
    end
    -- Nothing came across and Panoply Suite has no table of its own yet (the old data could not load, or
    -- there is none, or no stand-in at all: Panoply Suite put in by hand): this session's new table starts
    -- as a stopgap, so old data that loads later wins over the defaults this session writes into it. A new
    -- table that already exists is never marked. (A brand-new player only carries the mark: it is not a
    -- setting, Init.lua ignores it, and it goes away the day old data is brought across.)
    if status ~= "copied" and status ~= "merged" and status ~= "done-before" then M.Stopgap(t) end
  end
  if standIn == "full" then
    res.problems[#res.problems + 1] = "An old copy of Hearthpath is running next to Panoply Suite. Please run the Panoply Suite installer again, or turn the old Hearthpath off in the AddOns list."
  end
  self.result = res
  return res
end

-- Said on screen after log in (the chat window exists then): one line the time the old data came across;
-- the problems (if any) every time until they are fixed; nothing otherwise.
function M:Notice()
  local res = self.result
  if not res or self.noticed then return end
  self.noticed = true
  local came = false
  for _, r in pairs(res.tables) do if r.status == "copied" or r.status == "merged" then came = true end end
  if came and #res.problems == 0 then
    Panoply:Print("Hearthpath is now called Panoply Suite. Your settings, routes and records came across. Type /panoply to open it.")
  end
  if #res.problems == 0 then return end
  for _, p in ipairs(res.problems) do Panoply:Print(p) end
  Panoply:Print("Your old data was not changed and is safe. Fix the above, then type /reload to try again (/panoply import shows where things stand).")
end

-- One line per table, for /panoply import.
function M:Report()
  local res = self.result
  -- the copy only ever runs at load (later, other code already holds the tables): never from here
  if not res then return { "Bringing across your old Hearthpath settings did not run this session. Type /reload to try again." } end
  local SAY = {
    ["done-before"] = "brought across earlier", copied = "brought across now", merged = "added to what Panoply Suite already had",
    none = "nothing old to bring", empty = "the old one was empty", ["not-loaded"] = "could not load", malformed = "damaged, left alone",
    failed = "did not check out, left alone",
  }
  local out = {}
  for _, t in ipairs(M.TABLES) do
    local r = res.tables[t.old]
    out[#out + 1] = ("%s: %s"):format((t.what:gsub("^%l", string.upper)), SAY[r and r.status] or "?")
  end
  return out
end

if Panoply.On then
  -- an error inside the copy must never be silent (the event bus only logs handler errors to Debug):
  -- it is said on screen, nothing is marked, and every new table still missing starts as a stopgap
  Panoply:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON or M.result then return end
    -- 0.9.5: the bundled guide engine (WoW Forever) starts first, as it did when it loaded before Panoply Suite in folders
    -- of its own (Core/Bundle.lua; it starts only once, and it is not there on Classic Era)
    local bundle = rawget(_G, "PanoplySuiteBundle")
    if bundle and bundle.Start then
      local bok, berr = pcall(bundle.Start)
      if not bok then Panoply:Debug("bundle start: " .. tostring(berr)) end
    end
    local ok, err = pcall(M.Run, M)
    if not ok then
      M.result = { standIn = "?", tables = {}, problems = { "Bringing across your old Hearthpath settings stopped with an error (" .. tostring(err) .. ")." } }
      for _, t in ipairs(M.TABLES) do M.result.tables[t.old] = { status = "failed", why = tostring(err) } M.Stopgap(t) end
    end
  end)
  Panoply:On("PLAYER_LOGIN", function() M:Notice() end)
end
