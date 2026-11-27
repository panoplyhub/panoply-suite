-- Panoply Suite: runs the bundled guide engine from inside Panoply Suite's own folders (WoW Forever only).
-- Original code for Panoply Suite (GPL-3.0-only). It loads the guide engine's files; it copies none of their code.
-- Whose the guide engine is, its licence and Panoply Suite's changes to it: NOTICE.md and GuideEngine/PANOPLY-CHANGES.md.
--
-- Why (0.9.5): the guide engine's release is many add-on folders, which the game's AddOns list showed as that many rows.
-- Panoply Suite's bundling tool puts those folders inside PanoplySuite/ (PanoplySuite/GuideEngine/<folder>/) and, for the
-- nine languages, PanoplySuite_Languages/ (load on demand). Each Lua file of the engine is wrapped, on its first and
-- last line only, in PanoplySuiteBundle.File(folder, path, function(...) ... end). Each wrapped function gets the
-- environment below (B.env): its C_AddOns and CreateFrame are this file's, every other name is the game's own (reads
-- and writes go to _G), so no local is added (Lua allows 200; UI/GuideFrame.lua has them all).
--
-- 0.9.9.5 (Nov 25 2026): every name of the engine's own (folders, files, globals, frames, slash commands, saved
-- data, hidden-message prefixes, text) is Panoply's now ("PanoplyGuide..."), so nothing a player or another add-on can
-- see carries the engine's old name, and the engine's own add-on can be installed next to Panoply Suite: the two share
-- no folder, no saved-data name and no global. There is no stand-in folder any more.
--
-- What this file does so the engine runs as it did in its own folders:
--   * each engine folder keeps a name and a private table of its own (the file's "..."), as the game gave them;
--   * its files run when the game would have run them: the main folder as Panoply Suite loads (the engine's lines come
--     first in the TOC); the folders that were not load on demand right after the main folder's own ADDON_LOADED, in
--     the order the game used; the load-on-demand ones when the engine asks for them (C_AddOns.LoadAddOn), the
--     language add-on loaded first for a language folder;
--   * ADDON_LOADED("<that folder>") is handed to the frames the engine's files made, at those moments, after the saved
--     data is in (Panoply Suite's ADDON_LOADED, which comes after PanoplySuite's saved variables, the engine's among them);
--   * the engine's own questions about add-ons (C_AddOns, the copy its files see) are answered for its folders from
--     their TOC fields (PanoplySuite/GuideEngine/Pieces.lua); every other add-on is the game's answer;
--   * its pictures, fonts and sounds are found in their new folder (Dir);
--   * its saved data: PanoplySuite's TOCs list PanoplyGuideDB, PanoplyGuideCharDB and the Recorder's two, so the game
--     saves them with Panoply Suite's (WTF/.../SavedVariables/PanoplySuite.lua). A player coming from 0.9.5 to 0.9.9.4
--     has them in those same files under the old names: the game still reads them in (it runs the whole saved file), and
--     Migrate below moves each table to its new name once, the first time each character logs in. The old names are not
--     in the TOC any more, so the game writes only the new ones back.
-- Not on Classic Era (the engine is for WoW Forever; its TOCs never loaded there).
local B = {}
PanoplySuiteBundle = B

local type, pairs, ipairs, select, tostring, xpcall, setfenv, unpack = type, pairs, ipairs, select, tostring, xpcall, setfenv, unpack
local G = _G
local realAddOns = G.C_AddOns
local realCreateFrame = G.CreateFrame

B.ADDON = "PanoplySuite"
B.SAVED = { "PanoplyGuideDB", "PanoplyGuideCharDB", "PanoplyGuideRecorderDB", "PanoplyGuideRecorderCharDB" }
-- The names the same four tables were saved under by Panoply Suite 0.9.5 to 0.9.9.4, in the same order, and the three
-- spellings of the engine's old name with what each is now (for the names kept INSIDE the saved tables). These lines
-- are the only place the old name is spelled in Panoply Suite's code; they can go once every player has moved over.
B.SAVED_OLD = { "PolestarDB", "PolestarCharDB", "PolestarRecorderDB", "PolestarRecorderCharDB" }   -- OLD-SAVED-NAMES
B.WORDS_OLD = { { "Polestar", "PanoplyGuide" }, { "polestar", "panoplyguide" }, { "POLESTAR", "PANOPLYGUIDE" } }   -- OLD-SAVED-NAMES
-- Panoply Suite's own saved tables whose top-level keys carried the old name (settings such as the two "quiet" switches)
B.OWN_SAVED = { "PanoplySuiteDB", "PanoplySuiteCharDB" }

local folders, order = {}, {}           -- name -> folder record (Pieces.lua); the game's load order
local loaded, running = {}, {}          -- folder -> true once its files ran and its ADDON_LOADED went out; while running
local frames = {}                       -- every frame the engine's files made, in order (ADDON_LOADED goes to these)
local started = false
local afterStart = {}

local function errorHandler()
  local h = G.geterrorhandler and G.geterrorhandler()
  return type(h) == "function" and h or function(e) if G.print then G.print(tostring(e)) end end
end

-- xpcall with arguments (Lua 5.1's xpcall passes none): an error goes to the game's error handler, as an error in an
-- add-on's file does, and loading goes on.
local function safely(fn, ...)
  local n, args = select("#", ...), { ... }
  return xpcall(function() return fn(unpack(args, 1, n)) end, errorHandler())
end

-- Why it stays off: "era" (not WoW Forever), or nil (on). (Until 0.9.9.4 it also stayed off beside the engine's own add-on;
-- since 0.9.9.5 the two share no name, so both run.)
local function offReason()
  local toc = G.GetBuildInfo and select(4, G.GetBuildInfo())
  if type(toc) ~= "number" or toc < 16000 or toc >= 20000 then return "era" end
  return nil
end
B.off = offReason()

-- The globals of the OLD names as they stand while PanoplySuite's files load, before PanoplySuite's saved variables
-- arrive: nil, or another add-on's own tables (the engine's own add-on, when the player has it and it loaded first).
-- Whatever stands there then is not ours and is put back untouched by Migrate.
local early = {}
for i, n in ipairs(B.SAVED_OLD) do early[i] = rawget(G, n) end
-- The globals of the NEW names as they stand when the last of PanoplySuite's files has run (Core/Bootstrap.lua calls
-- B.Snapshot), just before the game reads the saved variables in. A table there then was made by the engine's own files as
-- they loaded (a setting read at load time makes an empty one: PanoplyGuide/Core/Init.lua DB()), not read from the saved
-- file. Review fix (0.9.9.5): without this, the account table of a player coming from 0.9.9.4 was never moved, because the
-- engine had already made an empty one under the new name, and the game then saved the empty one.
local made = {}
function B.Snapshot()
  for i, n in ipairs(B.SAVED) do made[i] = rawget(G, n) end
end

-------------------------------------------------------------------------------
-- The folders (PanoplySuite/GuideEngine/Pieces.lua, written by Panoply Suite's bundling tool)
-------------------------------------------------------------------------------
function B.Define(def)
  B.release = def.release
  for _, f in ipairs(def.folders or {}) do
    f.ns = {}                 -- its own private table, as the game gives each add-on one
    f.chunks = {}
    f.lmeta = {}
    for k, v in pairs(f.meta or {}) do f.lmeta[k:lower()] = v end
    f.deps = {}
    for dep in ((f.meta and f.meta.Dependencies) or ""):gmatch("[^,%s]+") do f.deps[#f.deps + 1] = dep end
    f.optdeps = {}
    for dep in ((f.meta and f.meta.OptionalDeps) or ""):gmatch("[^,%s]+") do f.optdeps[#f.optdeps + 1] = dep end
    folders[f.name] = f
    order[#order + 1] = f
  end
end

function B.Folder(name) return folders[name] end
function B.Folders() return order end
function B.IsLoaded(name) return loaded[name] == true end

-- Where a engine folder's files are now, for "Interface\\AddOns\\" .. Dir(name) .. "\\Media\\...". Any other name as it is.
function B.Dir(name)
  local f = folders[name]
  return f and f.dir or name
end

-- A folder's TOC field (the game reads field names in any case).
local function meta(f, field)
  if type(field) ~= "string" then return nil end
  local v = f.meta[field]
  if v == nil then v = f.lmeta[field:lower()] end
  return v
end

-------------------------------------------------------------------------------
-- Running the files
-------------------------------------------------------------------------------
local function run(f, fn)
  running[f.name] = true
  safely(fn, f.name, f.ns)
  running[f.name] = nil
end

-- Called by every wrapped file of the engine's as it loads.
function B.File(name, path, fn)
  if B.off then return end
  setfenv(fn, B.env)
  local f = folders[name]
  if not f then
    errorHandler()("Panoply Suite: " .. tostring(name) .. "/" .. tostring(path) .. " is not in Pieces.lua (the bundle is out of date)")
    return
  end
  if f.mode == "now" then run(f, fn) else f.chunks[#f.chunks + 1] = fn end
end

-- ADDON_LOADED(name) to the frames the engine's files made, as the game sends it to every frame registered for it.
local function fireLoaded(name)
  for i = 1, #frames do
    local fr = frames[i]
    local registered = fr.IsEventRegistered and fr:IsEventRegistered("ADDON_LOADED")
    local h = registered and fr.GetScript and fr:GetScript("OnEvent")
    if h then safely(h, fr, "ADDON_LOADED", name) end
  end
end
B.FireLoaded = fireLoaded

local function realLoaded(name)
  if not (realAddOns and realAddOns.IsAddOnLoaded) then return false end
  local a, b = realAddOns.IsAddOnLoaded(name)
  if b == nil then b = a end
  return b and true or false
end

local function realLoad(name)
  local load = (realAddOns and realAddOns.LoadAddOn) or G.LoadAddOn
  if not load then return false, "MISSING" end
  return load(name)
end

-- The engine's files register short command words next to their long one. The short words are also the words of the
-- engine's own add-on when a player has it installed beside Panoply Suite, and the game gives a word two add-ons both
-- register to either of them. So only the words that start with B.COMMAND_WORD stay registered (0.9.9.5).
B.COMMANDS = { "PANOPLYGUIDE", "PANOPLYGUIDEREC" }
B.COMMAND_WORD = "/panoplyguide"
function B.OwnCommands()
  for _, cmd in ipairs(B.COMMANDS) do
    local keep, i = {}, 1
    while type(rawget(G, "SLASH_" .. cmd .. i)) == "string" do
      local word = G["SLASH_" .. cmd .. i]
      if word:sub(1, #B.COMMAND_WORD) == B.COMMAND_WORD then keep[#keep + 1] = word end
      G["SLASH_" .. cmd .. i] = nil
      i = i + 1
    end
    for j = 1, #keep do G["SLASH_" .. cmd .. j] = keep[j] end
  end
end

-- the engine's C_AddOns.LoadAddOn for one of its folders: the files run now, then its ADDON_LOADED. -> loaded, reason
function B.Load(name)
  local f = folders[name]
  if not f then return realLoad(name) end
  if B.off then return false, "DISABLED" end
  if loaded[name] or running[name] then return true end
  for _, dep in ipairs(f.deps) do
    local d = folders[dep]
    -- a folder that needs the engine loads while the engine's own files run too (its language folder does), as in the game
    if d and not (loaded[dep] or running[dep] or d.mode == "now") then
      if not B.Load(dep) then return false, "DEP_MISSING" end
    elseif not d and not realLoaded(dep) then
      local ok = realLoad(dep)
      if not ok then return false, "DEP_MISSING" end
    end
  end
  if f.addon ~= B.ADDON and not realLoaded(f.addon) then
    local ok, why = realLoad(f.addon)
    if not ok then return false, why or "MISSING" end
  end
  if f.dropped then return false, "DEMAND_LOADED" end
  if #f.chunks < (f.files or 0) then return false, "CORRUPT" end
  running[name] = true
  local chunks = f.chunks
  f.chunks = {}                         -- run once; the files' code is not kept twice
  for i = 1, #chunks do safely(chunks[i], f.name, f.ns) end
  running[name] = nil
  loaded[name] = true
  -- a client plays in one language: once its folder ran, the other language folders' code (parsed with it, never run)
  -- is let go, so a German client does not keep eight more languages in memory
  if meta(f, "X-PanoplyGuide-Locale") then
    for _, o in ipairs(order) do
      if o ~= f and o.addon == f.addon and not loaded[o.name] and meta(o, "X-PanoplyGuide-Locale") then o.chunks, o.dropped = {}, true end
    end
  end
  B.OwnCommands()
  fireLoaded(name)
  return true
end

-------------------------------------------------------------------------------
-- The saved data: moving it from the old names (0.9.5 to 0.9.9.4) to the new ones, once
-------------------------------------------------------------------------------
local function newWord(str)
  for _, w in ipairs(B.WORDS_OLD) do
    if str:find(w[1], 1, true) then str = str:gsub(w[1], w[2]) end
  end
  return str
end

-- The same table with every text in it (keys and values, at any depth) carrying the new name where it carried the old
-- one: the engine keeps folder names, guide pack names and its own setting names inside its saved data, and its code
-- now asks for them by their new names. Done in place; a table reached twice is done once.
local function renameInside(t, seen)
  seen = seen or {}
  if seen[t] then return t end
  seen[t] = true
  local moves
  for k, v in pairs(t) do
    if type(v) == "table" then
      renameInside(v, seen)
    elseif type(v) == "string" then
      local nv = newWord(v)
      if nv ~= v then t[k] = nv end
    end
    if type(k) == "string" then
      local nk = newWord(k)
      if nk ~= k then moves = moves or {}; moves[#moves + 1] = { k, nk } end
    end
  end
  if moves then
    for _, m in ipairs(moves) do
      local v = rawget(t, m[1])
      rawset(t, m[1], nil)
      if rawget(t, m[2]) == nil then rawset(t, m[2], v) end   -- a value already saved under the new name wins
    end
  end
  return t
end
B.RenameInside = renameInside

-- Called at Start (PanoplySuite's saved variables are in). For each of the four tables: when the game has just read a
-- table in under the old name from PanoplySuite's own saved file (the global changed since this file loaded), it is
-- ours. It becomes the table of the new name when there is none yet, or only the empty one the engine made for itself while
-- its files loaded (B.Snapshot; a table already saved under the new name is never replaced), and the old global goes back to what it was before (nil, or another add-on's own table: never touched).
-- Panoply Suite's own tables get their top-level keys renamed the same way. -> the new names that were filled
function B.Migrate()
  local took = {}
  for i, old in ipairs(B.SAVED_OLD) do
    local new = B.SAVED[i]
    local mine = rawget(G, old)
    if mine ~= early[i] then
      G[old] = early[i]
      local cur = rawget(G, new)
      if type(mine) == "table" and (cur == nil or (made[i] ~= nil and cur == made[i])) then
        G[new] = renameInside(mine)
        took[#took + 1] = new
      end
    end
  end
  for _, name in ipairs(B.OWN_SAVED) do
    local t = rawget(G, name)
    if type(t) == "table" then
      local moves
      for k in pairs(t) do
        if type(k) == "string" and newWord(k) ~= k then moves = moves or {}; moves[#moves + 1] = k end
      end
      for _, k in ipairs(moves or {}) do
        local nk, v = newWord(k), t[k]
        t[k] = nil
        if t[nk] == nil then t[nk] = v end
      end
    end
  end
  B.migrated = took
  return took
end

-------------------------------------------------------------------------------
-- Start: Panoply Suite's ADDON_LOADED (its saved variables are in)
-------------------------------------------------------------------------------
function B.OnStart(fn)
  if started then safely(fn) else afterStart[#afterStart + 1] = fn end
end

-- 0.9.6.1 hotfix (Nov 17 2026): the engine's install check (Core/Data.lua CheckInstall, at login) counts its Codex folder as
-- required, and the release we bundle (Pieces.lua) has no Codex or QuestDB folder, so every complete install was told
-- it was "mixed or incomplete". A required folder the bundled release does not have is not missing from this install: it is
-- left out of the check's missing list. Every folder the release has, and every stale version, is still reported.
local function fitInstallCheck(core)
  local D = core and type(core.ns) == "table" and core.ns.Data
  local check = type(D) == "table" and D.CheckInstall
  if type(check) ~= "function" then return end
  D.CheckInstall = function(...)
    -- 0.9.9.1: the engine's 0.4.2.1 check returns a fourth value (how many Nav_R folders of 0.4.2 are still in the AddOns
    -- list, which its login code compares with 0); the wrapper hands every value on, not just the first three
    local missing, stale, retired, regions = check(...)
    if type(missing) ~= "table" then return missing, stale, retired, regions end
    local kept = {}
    for _, name in ipairs(missing) do
      if folders[name] then kept[#kept + 1] = name end
    end
    return kept, stale, retired, regions
  end
end

function B.Start()
  if started then return end
  started = true
  -- on every game: the old globals are handed back and the saved tables moved, whether or not the engine runs here
  B.Migrate()
  if not B.off then
    B.ShareMixins()
    local core
    for _, f in ipairs(order) do if f.mode == "now" then core = f end end
    if core then
      loaded[core.name] = true
      B.OwnCommands()
      fireLoaded(core.name)
      fitInstallCheck(core)
    end
    for _, f in ipairs(order) do
      if f.mode == "start" then B.Load(f.name) end
    end
  end
  local list = afterStart
  afterStart = {}
  for i = 1, #list do safely(list[i]) end
end

-------------------------------------------------------------------------------
-- What the engine's files see as C_AddOns and CreateFrame
-------------------------------------------------------------------------------
function B.CreateFrame(...)
  local fr = realCreateFrame(...)
  if fr then frames[#frames + 1] = fr end
  return fr
end


-- The list the engine sees: the game's add-ons (but a leftover old folder of the same name as one of ours), then its 27
local list
local function buildList()
  list = {}
  local n = (realAddOns and realAddOns.GetNumAddOns and realAddOns.GetNumAddOns()) or 0
  local info = realAddOns and realAddOns.GetAddOnInfo
  for i = 1, n do
    local name = info and info(i)
    if not (type(name) == "string" and folders[name]) then list[#list + 1] = i end
  end
  for _, f in ipairs(order) do list[#list + 1] = f.name end
  return list
end

local function info(f)
  local lod = meta(f, "LoadOnDemand") == "1"
  local reason = (lod and not loaded[f.name]) and "DEMAND_LOADED" or nil
  return f.name, meta(f, "Title") or f.name, meta(f, "Notes") or "", true, reason, "INSECURE", false
end

local V = {}
function V.LoadAddOn(name) return B.Load(name) end
function V.IsAddOnLoaded(name)
  local f = folders[name]
  if not f then
    if realAddOns and realAddOns.IsAddOnLoaded then return realAddOns.IsAddOnLoaded(name) end
    return false, false
  end
  if loaded[name] then return true, true end
  if running[name] then return true, false end
  return false, false
end
function V.GetAddOnMetadata(name, field)
  local f = folders[name]
  if f then return meta(f, field) end
  if type(name) == "number" then
    local l = list or buildList()
    local e = l[name]
    if type(e) == "string" then return meta(folders[e], field) end
    name = e
  end
  local get = realAddOns and realAddOns.GetAddOnMetadata
  if get and name ~= nil then return get(name, field) end
  return nil
end
function V.GetNumAddOns() return #buildList() end
function V.GetAddOnInfo(which)
  if type(which) == "number" then
    local l = list or buildList()
    local e = l[which]
    if type(e) == "string" then return info(folders[e]) end
    which = e
    if which == nil then return nil end
  elseif folders[which] then
    return info(folders[which])
  end
  return realAddOns.GetAddOnInfo(which)
end
function V.DoesAddOnExist(name)
  if folders[name] then return true end
  if realAddOns and realAddOns.DoesAddOnExist then return realAddOns.DoesAddOnExist(name) end
  local ok, n, _, _, _, reason = pcall(V.GetAddOnInfo, name)
  return ok and n ~= nil and reason ~= "MISSING"
end
function V.GetAddOnEnableState(a, b)
  if folders[a] or folders[b] then return 2 end
  if realAddOns and realAddOns.GetAddOnEnableState then return realAddOns.GetAddOnEnableState(a, b) end
  return 0
end
function V.EnableAddOn(name, ...)
  if folders[name] then return end   -- always on: they are part of Panoply Suite now
  if realAddOns and realAddOns.EnableAddOn then return realAddOns.EnableAddOn(name, ...) end
end
function V.DisableAddOn(name, ...)
  if folders[name] then return end
  if realAddOns and realAddOns.DisableAddOn then return realAddOns.DisableAddOn(name, ...) end
end
function V.IsAddOnLoadOnDemand(name)
  local f = folders[name]
  if f then return meta(f, "LoadOnDemand") == "1" end
  if realAddOns and realAddOns.IsAddOnLoadOnDemand then return realAddOns.IsAddOnLoadOnDemand(name) end
  return false
end
function V.IsAddOnLoadable(name, ...)
  if folders[name] then return true end
  if realAddOns and realAddOns.IsAddOnLoadable then return realAddOns.IsAddOnLoadable(name, ...) end
  return false
end
function V.GetAddOnDependencies(name)
  local f = folders[name]
  if f then return unpack(f.deps) end
  if realAddOns and realAddOns.GetAddOnDependencies then return realAddOns.GetAddOnDependencies(name) end
end
function V.GetAddOnOptionalDependencies(name)
  local f = folders[name]
  if f then return unpack(f.optdeps) end
  if realAddOns and realAddOns.GetAddOnOptionalDependencies then return realAddOns.GetAddOnOptionalDependencies(name) end
end
-- anything else is the game's own
B.C_AddOns = setmetatable(V, { __index = function(_, k) return realAddOns and realAddOns[k] end })

-- The environment of the engine's files: C_AddOns and CreateFrame are the two above; every other name is read from _G
-- (two table lookups, no function call) and every global the files set goes into _G, as before.
local own = setmetatable({ C_AddOns = B.C_AddOns, CreateFrame = B.CreateFrame }, { __index = G })
B.env = setmetatable({}, { __index = own, __newindex = G })

-- 0.9.6 phase I: the game builds what some of its functions return (C_Map.GetPlayerMapPosition's and GetWorldPosFromMapPos's
-- Vector2D, a colour, an item location) from a mixin it looks up BY NAME in the calling code's own environment, read raw: the
-- lookup does not follow __index. In the environment above every global is reached through __index, so in the engine's files
-- those functions failed with "unable to find mixin or metatable (Vector2DMixin)" (our WoW Forever error log, Nov 16-17 2026,
-- 19 times at the engine's Core/Compat.lua:826 and :880). One of them was the login's guide pick: a fresh character got no guide
-- ("No guide here yet"). So the game's mixins are put in the environment itself, the same tables (read only: the engine's files
-- assign no global named ...Mixin), once now (the game's own are all defined before any add-on loads) and again at Start for a
-- game add-on loaded in between.
function B.ShareMixins()
  local n = 0
  for k, v in pairs(G) do
    if type(k) == "string" and type(v) == "table" and k:sub(-5) == "Mixin" and rawget(B.env, k) == nil then
      rawset(B.env, k, v)
      n = n + 1
    end
  end
  return n
end
B.ShareMixins()

-------------------------------------------------------------------------------
-- Panoply Suite's ADDON_LOADED. Core/Migrate.lua's handler (the first one Panoply Suite registers) calls Start too, so
-- the engine is up before any of Panoply Suite's own handlers, whatever order the game sends the event to frames in.
-------------------------------------------------------------------------------
local ev = realCreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == B.ADDON then B.Start() end
end)
B.eventFrame = ev
