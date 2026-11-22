-- Panoply Suite: runs the bundled Polestar guide engine from inside Panoply Suite's own folders (WoW Forever only).
-- Original code for Panoply Suite (GPL-3.0-only). It loads Polestar's files; it copies none of Polestar's code.
--
-- Why (0.9.5, 2026-11-15: "i dont want polestar out there like that"): Polestar's release is 27 add-on folders, which
-- the game's AddOns list showed as 27 rows. tools/update_polestar_engine.py now puts those folders inside PanoplySuite/
-- (PanoplySuite/Polestar/<folder>/) and, for the nine languages, PanoplySuite_Languages/ (load on demand). Each Lua file
-- of Polestar's is wrapped, on its first and last line only, in PanoplySuiteBundle.File(folder, path, function(...) ... end);
-- the tool's --check proves the rest of every file is Polestar's release. Each wrapped function gets the environment
-- below (B.env): its C_AddOns and CreateFrame are this file's, every other name is the game's own (reads and writes go to
-- _G), so nothing in Polestar's files changes and no local is added (Lua allows 200; UI/GuideFrame.lua has them all).
--
-- What this file does so Polestar runs as it did in its own folders:
--   * each Polestar folder keeps its own name and private table (the file's "..."), as the game gave them;
--   * its files run when the game would have run them: Polestar's main folder as Panoply Suite loads (it loaded just
--     before Panoply Suite, and still does: the bundle's lines come first in the TOC); the folders that were not load on
--     demand (Polestar_Guides, Polestar_Recorder) right after Polestar's own ADDON_LOADED, in the order the game used;
--     the load-on-demand ones when Polestar asks for them (C_AddOns.LoadAddOn), the language add-on loaded first for a
--     language folder;
--   * ADDON_LOADED("<that folder>") is handed to the frames Polestar's files made, at those moments, after the saved data
--     is in (Panoply Suite's ADDON_LOADED, which comes after PanoplySuite's saved variables, Polestar's among them);
--   * Polestar's own questions about add-ons (C_AddOns, the copy its files see) are answered for its folders from
--     their TOC fields (PanoplySuite/Polestar/Pieces.lua); every other add-on is the game's answer;
--   * its pictures, fonts and sounds are found in their new folder (Dir);
--   * Polestar's saved data: PanoplySuite's WoW Forever TOCs list PolestarDB, PolestarCharDB and the Recorder's two, so
--     the game saves them with Panoply Suite's. A player who had the earlier bundle has them in the old Polestar files;
--     the stand-in add-on in the old "Polestar" folder (no code, the two names in its TOC) keeps those loading, and the
--     first time a character logs in its tables are taken from there when Panoply Suite has none yet (Takeover). Nothing
--     here edits the old files; the game writes them back at log out because the stand-in lists the names (same tables).
--     The Recorder's two tables had no stand-in: an old WTF/.../Polestar_Recorder.lua stays on disk, not loaded.
-- Not on Classic Era (Polestar is for WoW Forever; its TOCs never loaded there), and not when the player has a Polestar
-- of their own loaded (a full one in the "Polestar" folder): then that one runs, as before, and these files do nothing.
local B = {}
PanoplySuiteBundle = B

local type, pairs, ipairs, select, tostring, xpcall, setfenv, unpack = type, pairs, ipairs, select, tostring, xpcall, setfenv, unpack
local G = _G
local realAddOns = G.C_AddOns
local realCreateFrame = G.CreateFrame

B.ADDON = "PanoplySuite"
B.STANDIN = "Polestar"                  -- the old folder name the game files Polestar's saved data under (the stand-in)
B.STANDIN_FIELD = "X-Panoply-StandIn"
B.SAVED = { "PolestarDB", "PolestarCharDB", "PolestarRecorderDB", "PolestarRecorderCharDB" }

local folders, order = {}, {}           -- name -> folder record (Pieces.lua); the game's load order
local loaded, running = {}, {}          -- folder -> true once its files ran and its ADDON_LOADED went out; while running
local frames = {}                       -- every frame Polestar's files made, in order (ADDON_LOADED goes to these)
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

-- Why it stays off: "era" (not WoW Forever), "own" (the player's own Polestar is loaded), or nil (on).
local function offReason()
  local toc = G.GetBuildInfo and select(4, G.GetBuildInfo())
  if type(toc) ~= "number" or toc < 16000 or toc >= 20000 then return "era" end
  if rawget(G, "Polestar") ~= nil then return "own" end
  return nil
end
B.off = offReason()

-- Polestar's saved tables as they stand while PanoplySuite's files load: the stand-in's (the old files), or the player's
-- own Polestar's, both loaded before Panoply Suite. PanoplySuite's own saved variables arrive after its files.
local early = {}
for _, n in ipairs(B.SAVED) do early[n] = rawget(G, n) end

-------------------------------------------------------------------------------
-- The folders (PanoplySuite/Polestar/Pieces.lua, written by tools/update_polestar_engine.py)
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

-- Where a Polestar folder's files are now, for "Interface\\AddOns\\" .. Dir(name) .. "\\Media\\...". Any other name as it is.
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

-- Called by every wrapped file of Polestar's as it loads.
function B.File(name, path, fn)
  if B.off then return end
  setfenv(fn, B.env)
  local f = folders[name]
  if not f then
    errorHandler()("Panoply Suite: " .. tostring(name) .. "/" .. tostring(path) .. " is not in Pieces.lua (run tools/update_polestar_engine.py)")
    return
  end
  if f.mode == "now" then run(f, fn) else f.chunks[#f.chunks + 1] = fn end
end

-- ADDON_LOADED(name) to the frames Polestar's files made, as the game sends it to every frame registered for it.
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

-- Polestar's C_AddOns.LoadAddOn for one of its folders: the files run now, then its ADDON_LOADED. -> loaded, reason
function B.Load(name)
  local f = folders[name]
  if not f then return realLoad(name) end
  if B.off then return false, "DISABLED" end
  if loaded[name] or running[name] then return true end
  for _, dep in ipairs(f.deps) do
    local d = folders[dep]
    -- a folder that needs Polestar loads while Polestar's own files run too (its language folder does), as in the game
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
  if meta(f, "X-Polestar-Locale") then
    for _, o in ipairs(order) do
      if o ~= f and o.addon == f.addon and not loaded[o.name] and meta(o, "X-Polestar-Locale") then o.chunks, o.dropped = {}, true end
    end
  end
  fireLoaded(name)
  return true
end

-------------------------------------------------------------------------------
-- The saved data
-------------------------------------------------------------------------------
-- Is the "Polestar" add-on there the stand-in (no code, only the saved-data names)?
local function standIn()
  local get = realAddOns and realAddOns.GetAddOnMetadata
  if not get then return false end
  local ok, v = pcall(get, B.STANDIN, B.STANDIN_FIELD)
  return ok and v ~= nil and tostring(v) ~= ""
end

-- The first login of each character after the update: its Polestar tables are still only in the old files (loaded by
-- the stand-in before Panoply Suite); Panoply Suite has none of its own yet, so it takes those. A table Panoply Suite
-- already has is never replaced. -> the names taken
function B.Takeover()
  local took = {}
  if not (standIn() and realLoaded(B.STANDIN)) then return took end
  for _, n in ipairs(B.SAVED) do
    if rawget(G, n) == nil and type(early[n]) == "table" then
      G[n] = early[n]
      took[#took + 1] = n
    end
  end
  B.tookOver = took
  return took
end

-------------------------------------------------------------------------------
-- Old folders of the earlier bundle left next to Panoply Suite (a zip unpacked over an older install)
-------------------------------------------------------------------------------
function B.Leftovers()
  local out = {}
  local info = realAddOns and realAddOns.GetAddOnInfo
  if not info then return out end
  for _, f in ipairs(order) do
    if f.name ~= B.STANDIN then
      local ok, n, _, _, _, reason = pcall(info, f.name)
      if ok and n and reason ~= "MISSING" then out[#out + 1] = f.name end
    end
  end
  return out
end

local function turnOffLeftovers(list)
  local off = realAddOns and realAddOns.DisableAddOn
  if not off then return end
  for _, n in ipairs(list) do pcall(off, n) end
end

-------------------------------------------------------------------------------
-- Start: Panoply Suite's ADDON_LOADED (its saved variables are in)
-------------------------------------------------------------------------------
function B.OnStart(fn)
  if started then safely(fn) else afterStart[#afterStart + 1] = fn end
end

-- 0.9.6.1 hotfix (Nov 17 2026): Polestar's install check (Core/Data.lua CheckInstall, at login) counts Polestar_Codex as
-- required, and the release we bundle (Pieces.lua) has no Polestar_Codex or Polestar_QuestDB, so every complete install was told
-- it was "mixed or incomplete". A required folder the bundled release does not have is not missing from this install: it is
-- left out of the check's missing list. Every folder the release has, and every stale version, is still reported.
local function fitInstallCheck(core)
  local D = core and type(core.ns) == "table" and core.ns.Data
  local check = type(D) == "table" and D.CheckInstall
  if type(check) ~= "function" then return end
  D.CheckInstall = function(...)
    -- 0.9.9.1: Polestar 0.4.2.1's check returns a fourth value (how many Polestar_Nav_R folders of 0.4.2 are still in the AddOns
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
  if B.off == "own" then
    -- the player's own Polestar loaded before us with its own saved tables; PanoplySuite's copy of the names must not
    -- replace them (the game just loaded PanoplySuite's saved variables over the globals)
    for _, n in ipairs(B.SAVED) do if early[n] ~= nil then G[n] = early[n] end end
  end
  if not B.off then
    B.ShareMixins()
    B.Takeover()
    B.leftovers = B.Leftovers()
    if #B.leftovers > 0 then turnOffLeftovers(B.leftovers) end
    local core
    for _, f in ipairs(order) do if f.mode == "now" then core = f end end
    if core then
      loaded[core.name] = true
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
-- What Polestar's files see as C_AddOns and CreateFrame
-------------------------------------------------------------------------------
function B.CreateFrame(...)
  local fr = realCreateFrame(...)
  if fr then frames[#frames + 1] = fr end
  return fr
end


-- The list Polestar sees: the game's add-ons (but a leftover old folder of the same name as one of ours), then its 27
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

-- The environment of Polestar's files: C_AddOns and CreateFrame are the two above; every other name is read from _G
-- (two table lookups, no function call) and every global the files set goes into _G, as before.
local own = setmetatable({ C_AddOns = B.C_AddOns, CreateFrame = B.CreateFrame }, { __index = G })
B.env = setmetatable({}, { __index = own, __newindex = G })

-- 0.9.6 phase I: the game builds what some of its functions return (C_Map.GetPlayerMapPosition's and GetWorldPosFromMapPos's
-- Vector2D, a colour, an item location) from a mixin it looks up BY NAME in the calling code's own environment, read raw: the
-- lookup does not follow __index. In the environment above every global is reached through __index, so in Polestar's files
-- those functions failed with "unable to find mixin or metatable (Vector2DMixin)" (our WoW Forever error log, Nov 16-17 2026,
-- 19 times at Polestar's Core/Compat.lua:826 and :880). One of them was the login's guide pick: a fresh character got no guide
-- ("No guide here yet"). So the game's mixins are put in the environment itself, the same tables (read only: Polestar's files
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
-- Polestar is up before any of Panoply Suite's own handlers, whatever order the game sends the event to frames in.
-------------------------------------------------------------------------------
local ev = realCreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" then
    if name == B.ADDON then B.Start() end
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    local l = B.leftovers
    if l and #l > 0 and G.DEFAULT_CHAT_FRAME then
      G.DEFAULT_CHAT_FRAME:AddMessage(("|cff0093b2Panoply Suite|r: %d old guide engine folders from an earlier version are still in Interface/AddOns (%s). Panoply Suite carries them inside its own folder now, so they are turned off. Close the game and delete them."):format(#l, table.concat(l, ", ")))
    end
  end
end)
B.eventFrame = ev
