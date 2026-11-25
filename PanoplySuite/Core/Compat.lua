-- Panoply Suite Compat: the ONLY file that talks to Blizzard APIs directly.
-- Rule: pick each API path by existence checks at call time, never by version numbers.
-- Every read that could be a Midnight-era "secret value" goes through Readable().
-- Launch-day patches should only need edits in this file.
local ADDON, Panoply = ...
local C = {}
Panoply.Compat = C

C.missing = {}   -- [name] = true once a wrapper found no usable API
C.errors = {}    -- [name] = last error

-- Resolve a dotted global path at call time ("C_QuestLog.GetInfo").
-- (Nov 14 2026, 0.9.4 step 22: plain find and sub, so a lookup makes no iterator closure: the minimap asks for the player's position
-- ten times a second and the two lookups in it were 176 bytes of garbage a call; the substrings are the same strings every time)
local sfind, ssub = string.find, string.sub
local function G(path)
  local v, i = _G, 1
  while true do
    if type(v) ~= "table" then return nil end
    local j = sfind(path, ".", i, true)
    if not j then return v[ssub(path, i)] end
    v = v[ssub(path, i, j - 1)]
    i = j + 1
  end
end
C.G = G

local function missing(name)
  if not C.missing[name] then
    C.missing[name] = true
    if Panoply.Debug then Panoply:Debug("missing API for", name) end
  end
end

-- Secret values (Midnight addon disarmament) cannot be compared/used; treat as unknown.
function C.Readable(v)
  local isSecret = _G.issecretvalue
  if isSecret then   -- Era has no secret values: this whole check is skipped there
    local ok, secret = pcall(isSecret, v)
    if not ok or secret then return nil end
  end
  return v
end
local R = C.Readable

-- pcall a global function by path; returns ok, results...
local function call(name, path, ...)
  local f = G(path)
  if type(f) ~= "function" then return false end
  local res = { n = 0 }
  local function pack(...) res.n = select("#", ...) for i = 1, res.n do res[i] = (select(i, ...)) end end
  pack(pcall(f, ...))
  if not res[1] then C.errors[name] = res[2]; Panoply:Debug("API error", name, res[2]); return false end
  return true, unpack(res, 2, res.n)
end
C.Call = call

-------------------------------------------------------------------------------
-- Client / flavor
-------------------------------------------------------------------------------
function C.BuildInfo()
  local ok, version, build, date, toc = call("BuildInfo", "GetBuildInfo")
  if not ok then return nil end
  return version, build, date, toc
end

-- Which game is this? "forever" (WoW Forever, Mainline-family 1.60.x), "era" (Classic Era 1.15.x),
-- "mainline" (Midnight, unsupported) or "unknown". Used for DATA choices and labels only; API paths
-- are still picked by existence checks.
function C.Flavor()
  if C.flavorOverride then return C.flavorOverride end
  local pid = _G.WOW_PROJECT_ID
  local camelot, classic, mainline = _G.WOW_PROJECT_CAMELOT, _G.WOW_PROJECT_CLASSIC, _G.WOW_PROJECT_MAINLINE
  if pid and camelot and pid == camelot then return "forever" end
  if pid and classic and pid == classic then return "era" end
  local _, _, _, toc = C.BuildInfo()
  toc = tonumber(toc)
  if toc and toc >= 16000 and toc < 20000 then return "forever" end
  if toc and toc >= 11000 and toc < 12000 then return "era" end
  if pid and mainline and pid == mainline then return "mainline" end
  return "unknown"
end
function C.IsEra() return C.Flavor() == "era" end
function C.IsForever() return C.Flavor() == "forever" end

C.FLAVOR_LABEL = { forever = "WoW Forever", era = "WoW Classic", mainline = "WoW (Midnight, not supported)", unknown = "unknown game" }
function C.FlavorLabel() return C.FLAVOR_LABEL[C.Flavor()] or C.Flavor() end

-- Feature detection, computed once per session (tests may reset with C.features = nil).
-- restrictions = Midnight "addon disarmament" rules (secret values, no addon messages in instances).
function C.Features()
  if C.features then return C.features end
  local f = {}
  f.flavor = C.Flavor()
  f.secrets = _G.issecretvalue ~= nil
  f.restrictions = f.secrets or f.flavor == "forever"
  f.questLog = (G("C_QuestLog.GetInfo") and "C_QuestLog") or (_G.GetQuestLogTitle and "legacy") or "missing"
  f.objectives = (G("C_QuestLog.GetQuestObjectives") and "C_QuestLog") or (_G.GetQuestLogLeaderBoard and "legacy") or "missing"
  f.map = (G("C_Map.GetBestMapForUnit") and "C_Map") or "missing"
  f.blizzWaypoint = (G("C_Map.SetUserWaypoint") and G("UiMapPoint.CreateFromCoordinates")) and true or false
  f.tradeSkill = (G("C_TradeSkillUI.GetAllRecipeIDs") and "C_TradeSkillUI") or (_G.GetTradeSkillInfo and "legacy") or "missing"
  f.craft = _G.GetCraftInfo and true or false   -- Era Enchanting uses the separate Craft window
  f.gossip = (G("C_GossipInfo.GetAvailableQuests") and "C_GossipInfo") or "missing"
  f.taxi = (G("C_TaxiMap.GetAllTaxiNodes") and "C_TaxiMap") or (_G.NumTaxiNodes and "legacy") or "missing"
  f.addonMessages = (G("C_ChatInfo.SendAddonMessage") and "C_ChatInfo") or (_G.SendAddonMessage and "legacy") or "missing"
  C.features = f
  return f
end

function C.GetTime()
  local f = _G.GetTime
  return f and f() or os.time()
end

function C.After(sec, fn)
  local after = G("C_Timer.After")
  if after then after(sec, fn) return true end
  missing("C_Timer.After")
  fn()  -- no timers on this client: run now rather than never
  return false
end

function C.NewTicker(sec, fn)
  local nt = G("C_Timer.NewTicker")
  if nt then return nt(sec, fn) end
  missing("C_Timer.NewTicker")
  -- Fallback: OnUpdate driven ticker
  local f = CreateFrame("Frame")
  local acc = 0
  f:SetScript("OnUpdate", function(_, e) acc = acc + e if acc >= sec then acc = 0 fn() end end)
  return { Cancel = function() f:SetScript("OnUpdate", nil) end }
end

function C.InCombat()
  local f = _G.InCombatLockdown
  return f and f() and true or false
end

function C.ShiftDown()
  local f = _G.IsShiftKeyDown
  return f and f() and true or false
end

-------------------------------------------------------------------------------
-- Player
-------------------------------------------------------------------------------
function C.PlayerInfo()
  local info = {}
  if _G.UnitName then info.name = R(UnitName("player")) end
  if _G.GetRealmName then info.realm = R(GetRealmName()) end
  if _G.UnitRace then local n, file, id = UnitRace("player"); info.race, info.raceFile, info.raceID = R(n), R(file), R(id) end
  if _G.UnitClass then local n, file, id = UnitClass("player"); info.class, info.classFile, info.classID = R(n), R(file), R(id) end
  if _G.UnitFactionGroup then info.faction = R(UnitFactionGroup("player")) end
  return info
end

-- After 0.8.4 (Boneless on WoW Forever: his Hearth Hall record fell to level 1 with no gold): the game can hide the level and the
-- XP numbers (secret values). C.XPKnown() answers only what the game shows right now: level, xp, xpMax, rested, each nil while it is
-- hidden (rested is 0 when there simply is none). Code that SAVES these uses it, so a hidden value never replaces a saved good one.
-- C.XP() still always answers numbers, for everything that only needs one now: the level is the last one this session could read
-- (1 only when it never could), the XP numbers are 0 while hidden.
local function shown(v) if v ~= nil and R(v) == nil then return nil, true end return v, false end
function C.XPKnown()
  local level = _G.UnitLevel and R(UnitLevel("player")) or nil
  if type(level) ~= "number" or level < 1 then level = nil end
  if level then C.lastLevel = level end
  local xp = _G.UnitXP and R(UnitXP("player")) or nil
  local xpMax = _G.UnitXPMax and R(UnitXPMax("player")) or nil
  local rested, hidden
  if _G.GetXPExhaustion then rested, hidden = shown(GetXPExhaustion()) end
  if not hidden then rested = rested or 0 end
  return level, xp, xpMax, rested
end
function C.XP()
  local level, xp, xpMax, rested = C.XPKnown()
  return level or C.lastLevel or 1, xp or 0, xpMax or 0, rested or 0
end

function C.ZoneText()
  local z = _G.GetRealZoneText or _G.GetZoneText
  local s = _G.GetSubZoneText
  return z and R(z()) or "", s and R(s()) or ""
end

function C.BindLocation()
  local f = _G.GetBindLocation
  if not f then missing("BindLocation") return nil end
  return R(f())
end

function C.InInstance()
  local f = _G.IsInInstance
  if not f then return false end
  local inInst, kind = f()
  return R(inInst) and true or false, R(kind)
end

-- The instance the player is in, by the game's own account: name, kind ("party", "raid", ...), the instance's map number.
-- Any part the game does not give (or gives as a secret value) is nil.
function C.InstanceInfo()
  local f = _G.GetInstanceInfo
  if not f then return nil end
  local ok, name, kind, _, _, _, _, _, id = pcall(f)
  if not ok then return nil end
  name, kind, id = R(name), R(kind), R(id)
  return type(name) == "string" and name ~= "" and name or nil, type(kind) == "string" and kind or nil, type(id) == "number" and id or nil
end

-- An area's name as the game knows it (quests are filed under an area number), or nil.
function C.AreaName(areaID)
  local f = G("C_Map.GetAreaInfo")
  if not (f and type(areaID) == "number") then return nil end
  local ok, name = pcall(f, areaID)
  name = ok and R(name) or nil
  return type(name) == "string" and name ~= "" and name or nil
end

-------------------------------------------------------------------------------
-- Deaths of creatures near the player (the dungeon helper, Engine/Dungeon.lua, ticks a boss off with them).
-- Read-only: nothing is targeted, cast or sent. Each signal is used only where the client offers it:
--   log        the combat log's "died" lines (Classic Era; WoW Forever has no combat log reader for add-ons)
--   xp         the "<name> dies, you gain experience" chat line
--   unit       a dead creature the player has targeted or is pointing at (also checked when a fight ends and at looting)
--   encounter  ENCOUNTER_END / BOSS_KILL, which the game sends in raids and may not send in 5-player dungeons
-------------------------------------------------------------------------------
C.DEATH_EVENTS = { "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "LOOT_OPENED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_END", "BOSS_KILL" }
C.DEATH_LOG_EVENTS = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

-- A dead creature in this unit slot: name, GUID. Nil for a player, a living unit, or no unit.
function C.DeadUnit(unit)
  local exists, dead, isPlayer, uname = _G.UnitExists, _G.UnitIsDead, _G.UnitIsPlayer, _G.UnitName
  if not (exists and dead and uname) then return nil end
  local ok, there = pcall(exists, unit)
  if not (ok and R(there)) then return nil end
  local okD, d = pcall(dead, unit)
  if not (okD and R(d)) then return nil end
  if isPlayer then local okP, p = pcall(isPlayer, unit) if not okP or R(p) then return nil end end
  local okN, name = pcall(uname, unit)
  name = okN and R(name) or nil
  if type(name) ~= "string" or name == "" then return nil end
  local guid
  if _G.UnitGUID then local okG, g = pcall(_G.UnitGUID, unit) guid = okG and R(g) or nil end
  return name, type(guid) == "string" and guid or nil
end

-- The creature named in a "<name> dies, you gain <n> experience." chat line, or nil.
function C.DeathFromXPLine(msg)
  msg = R(msg)
  if type(msg) ~= "string" then return nil end
  local fmt = _G.COMBATLOG_XPGAIN_FIRSTPERSON
  local tail = " dies, you gain "
  if type(fmt) == "string" then
    local a = fmt:find("%s", 1, true)
    if a == 1 then
      local rest = fmt:sub(3)
      local b = rest:find("%", 1, true)
      local t = b and rest:sub(1, b - 1) or rest
      if t ~= "" then tail = t end
    end
  end
  local at = msg:find(tail, 1, true)
  if not at or at < 2 then return nil end
  return msg:sub(1, at - 1)
end

local deathFrame, deathFn
local function onDeathEvent(_, event, ...)
  local fn = deathFn
  if not fn then return end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local info = _G.CombatLogGetCurrentEventInfo
    if not info then return end
    local ok, _, sub, _, _, _, _, _, guid, name = pcall(info)
    if not ok then return end
    sub = R(sub)
    if not (sub and C.DEATH_LOG_EVENTS[sub]) then return end
    name, guid = R(name), R(guid)
    if type(name) == "string" or type(guid) == "string" then fn(type(name) == "string" and name or nil, type(guid) == "string" and guid or nil, "log") end
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local name = C.DeathFromXPLine((...))
    if name then fn(name, nil, "xp") end
  elseif event == "ENCOUNTER_END" then
    local _, name, _, _, success = ...
    name, success = R(name), R(success)
    if type(name) == "string" and (success == 1 or success == true) then fn(name, nil, "encounter") end
  elseif event == "BOSS_KILL" then
    local _, name = ...
    name = R(name)
    if type(name) == "string" then fn(name, nil, "encounter") end
  else
    for _, unit in ipairs({ "target", "mouseover" }) do
      local name, guid = C.DeadUnit(unit)
      if name then fn(name, guid, "unit") end
    end
  end
end

-- Start (fn) or stop (nil) watching. fn(name, guid, source); name or guid may be nil. Returns the events being watched.
function C.WatchDeaths(fn)
  deathFn = fn
  if not deathFrame then
    if not fn then return {} end
    deathFrame = CreateFrame("Frame")
    deathFrame:SetScript("OnEvent", function(self, event, ...)
      local ok, err = pcall(onDeathEvent, self, event, ...)
      if not ok and Panoply.Debug then Panoply:Debug("death watch", event, err) end
    end)
    C.deathFrame = deathFrame
  end
  local on = {}
  local EU = _G.C_EventUtils
  for _, ev in ipairs(C.DEATH_EVENTS) do
    if fn then
      local valid = true
      if EU and EU.IsEventValid then
        local okV, v = pcall(EU.IsEventValid, ev)
        if okV and v == false then valid = false end
      end
      if valid and pcall(deathFrame.RegisterEvent, deathFrame, ev) then on[#on + 1] = ev end
    else
      pcall(deathFrame.UnregisterEvent, deathFrame, ev)
    end
  end
  return on
end

function C.InGroup()
  local f = _G.IsInGroup
  return f and f() and true or false
end

function C.GroupChannel()
  if _G.IsInRaid and IsInRaid() then return "RAID" end
  if C.InGroup() then return "PARTY" end
  return nil
end

function C.GroupMembers()
  local names = {}
  local n = _G.GetNumGroupMembers and tonumber(R(GetNumGroupMembers())) or 0   -- a secret count is "nobody we can name"
  local unitPrefix = (_G.IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local u = unitPrefix .. i
    if _G.UnitExists and UnitExists(u) and not (_G.UnitIsUnit and UnitIsUnit(u, "player")) then
      local name, realm = UnitName(u)
      name = R(name)
      if name then names[#names + 1] = (realm and realm ~= "") and (name .. "-" .. realm) or name end
    end
  end
  return names
end

-- Who holds the party / raid crown: name (realm added when the game gives one) and whether it is you.
-- nil when not grouped or when the client cannot say (0.7.3.2: the partner route leader is the crown holder,
-- Engine/Sync.lua falls back to name order when this returns nil).
function C.GroupLeader()
  local f = _G.UnitIsGroupLeader or _G.UnitIsPartyLeader
  if not f or not C.InGroup() then return nil end
  local function holds(u)
    local ok, v = pcall(f, u)
    return ok and R(v) and true or false
  end
  if holds("player") then return (C.PlayerInfo() or {}).name, true end
  local n = _G.GetNumGroupMembers and tonumber(R(GetNumGroupMembers())) or 0   -- a secret count is "nobody we can name"
  local unitPrefix = (_G.IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local u = unitPrefix .. i
    if _G.UnitExists and UnitExists(u) and holds(u) then
      local name, realm = UnitName(u)
      name = R(name)
      if name then return (realm and realm ~= "") and (name .. "-" .. realm) or name, false end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Rules (Forever rulesets / hardcore)
-------------------------------------------------------------------------------
function C.Ruleset()
  local hc = G("C_GameRules.IsHardcoreActive")   -- Era hardcore realms
  if C.IsEra() then
    if hc then local ok, on = pcall(hc) if ok and on then return "hardcore" end end
    return "era"
  end
  local isActive = G("C_GameRules.IsGameRuleActive")
  local enum = G("Enum.GameRule")
  if not (isActive and enum) then missing("Ruleset") return "unknown" end
  local active = {}
  for k, v in pairs(enum) do
    if type(k) == "string" and k:find("Ruleset") then
      local ok, on = pcall(isActive, v)
      if ok and R(on) then active[#active + 1] = k end
    end
  end
  table.sort(active)
  return #active > 0 and table.concat(active, ",") or "normal"
end

function C.IsHardcore()
  local r = C.Ruleset()
  return type(r) == "string" and r:lower():find("hardcore") ~= nil
end

-------------------------------------------------------------------------------
-- Quests
-------------------------------------------------------------------------------
function C.IsQuestCompleted(id)
  local f = G("C_QuestLog.IsQuestFlaggedCompleted") or _G.IsQuestFlaggedCompleted
  if not f then missing("IsQuestCompleted") return false end
  local ok, v = pcall(f, id)
  return ok and R(v) and true or false
end

function C.GetAllCompleted()
  local set = {}
  local f = G("C_QuestLog.GetAllCompletedQuestIDs")
  if f then
    local ok, list = pcall(f)
    if ok and type(list) == "table" then
      for _, id in ipairs(list) do set[id] = true end
      return set, "C_QuestLog"
    end
  end
  local g = _G.GetQuestsCompleted
  if g then
    local t = {}
    local ok = pcall(g, t)
    if ok then for id in pairs(t) do set[id] = true end return set, "GetQuestsCompleted" end
  end
  missing("GetAllCompleted")
  return set, nil
end

-- Returns list of { questID, title, level, isComplete (ready for turn-in), failed }
function C.IterQuestLog()
  local list = {}
  local num = G("C_QuestLog.GetNumQuestLogEntries")
  local info = G("C_QuestLog.GetInfo")
  if num and info then
    local n = num()
    for i = 1, n or 0 do
      local ok, q = pcall(info, i)
      if ok and type(q) == "table" and not q.isHeader and q.questID and q.questID ~= 0 and not q.isHidden then
        local done = C.IsReadyForTurnIn(q.questID)
        list[#list + 1] = { questID = q.questID, title = q.title, level = q.level, isComplete = done, logIndex = i,
                            suggestedGroup = tonumber(q.suggestedGroup) or 0 }
      end
    end
    return list
  end
  local num2, title = _G.GetNumQuestLogEntries, _G.GetQuestLogTitle
  if num2 and title then
    local n = num2()
    for i = 1, n or 0 do
      local t, level, group, isHeader, _, isComplete, _, questID = title(i)
      if t and not isHeader and questID and questID ~= 0 then
        local ready = (isComplete == 1)
        if isComplete == nil and _G.GetNumQuestLeaderBoards then
          local okN, nb = pcall(GetNumQuestLeaderBoards, i)
          if okN and nb == 0 then ready = true end   -- "talk to" quests have no objectives
        end
        list[#list + 1] = { questID = questID, title = t, level = level, isComplete = ready, failed = (isComplete == -1), logIndex = i,
                            suggestedGroup = tonumber(group) or 0 }
      end
    end
    return list
  end
  missing("IterQuestLog")
  return list
end

-- Quest tag of a quest in the log ("dungeon" | "raid" | "group" | "elite" | "pvp" | nil).
-- Forever: C_QuestLog.GetQuestTagInfo(id) -> { tagID }; Era: GetQuestTagInfo(id) -> tagID, tagName.
C.QUEST_TAG = { [1] = "group", [41] = "pvp", [62] = "raid", [81] = "dungeon", [85] = "dungeon", [88] = "raid", [89] = "raid" }
function C.QuestTag(questID)
  local id
  local modern = G("C_QuestLog.GetQuestTagInfo")
  if modern then
    local ok, t = pcall(modern, questID)
    if ok and type(t) == "table" then id = t.tagID; if t.isElite and not id then return "elite" end end
  end
  if not id and _G.GetQuestTagInfo then
    local ok, t = pcall(GetQuestTagInfo, questID)
    if ok then id = tonumber(C.Readable(t)) end
  end
  return id and C.QUEST_TAG[id] or nil
end

function C.IsReadyForTurnIn(questID)
  local f = G("C_QuestLog.ReadyForTurnIn")
  if f then local ok, v = pcall(f, questID) if ok then return R(v) and true or false end end
  local g = G("C_QuestLog.IsComplete")
  if g then local ok, v = pcall(g, questID) if ok then return R(v) and true or false end end
  if _G.GetQuestLogTitle then
    for _, q in ipairs(C.IterQuestLog()) do if q.questID == questID then return q.isComplete end end
  end
  return false
end

function C.LogIndexForQuest(questID)
  local f = _G.GetQuestLogIndexByID or G("C_QuestLog.GetLogIndexForQuestID")
  if f then local ok, i = pcall(f, questID) if ok and i and i > 0 then return i end end
  for _, q in ipairs(C.IterQuestLog()) do if q.questID == questID then return q.logIndex end end
  return nil
end

-- A quest's title as the client knows it (Forever: C_QuestLog.GetTitleForQuestID; it answers nil until the title is cached).
-- Nil when the client has nothing: callers keep their own fallback.
function C.QuestTitle(questID)
  local f = G("C_QuestLog.GetTitleForQuestID")
  if not (f and questID) then return nil end
  local ok, t = pcall(f, questID)
  t = ok and R(t) or nil
  if type(t) == "string" and t ~= "" then return t end
  return nil
end

-- After 0.8.2: where the game itself points for a quest in the log: its next waypoint (the objective area, or the
-- turn-in once the quest is complete). Returns mapID, x, y (0..1) or nil. Only clients that have
-- C_QuestLog.GetNextWaypoint answer (Forever); Classic Era has none, so it is nil there. Also used by log-driven mode
-- (Engine/Planner.lua LogDrivenSteps). Nov 13 2026: a second, looser copy of this function further down (no map id or number
-- checks) replaced this one at load; it was removed.
function C.QuestWaypoint(questID)
  local f = G("C_QuestLog.GetNextWaypoint")
  if not (f and questID) then return nil end
  local ok, map, x, y = pcall(f, questID)
  if not ok then return nil end
  map, x, y = R(map), R(x), R(y)
  if type(map) == "number" and type(x) == "number" and type(y) == "number" and map > 0 then return map, x, y end
  return nil
end

-- Returns list of { text, type, finished, numFulfilled, numRequired }
function C.GetObjectives(questID)
  local f = G("C_QuestLog.GetQuestObjectives")
  if f then
    local ok, objs = pcall(f, questID)
    if ok and type(objs) == "table" then
      local out = {}
      for i, o in ipairs(objs) do
        out[i] = { text = R(o.text), type = R(o.type), finished = R(o.finished) and true or false,
                   numFulfilled = R(o.numFulfilled) or 0, numRequired = R(o.numRequired) or 0 }
      end
      return out
    end
  end
  -- Classic Era: leaderboard API by quest log index. Text looks like "Kobold Vermin slain: 3/10".
  if _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
    local idx = C.LogIndexForQuest(questID)
    if not idx then return {} end
    local out = {}
    local okN, n = pcall(GetNumQuestLeaderBoards, idx)
    for j = 1, (okN and n or 0) do
      local ok, text, kind, finished = pcall(GetQuestLogLeaderBoard, j, idx)
      if ok then text, finished = R(text), R(finished) end   -- a secret string cannot be matched
      if ok and type(text) == "string" then
        local have, need = text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(have), tonumber(need)
        out[#out + 1] = { text = text, type = kind, finished = finished and true or false,
                          numFulfilled = have or (finished and 1 or 0), numRequired = need or 1 }
      end
    end
    return out
  end
  missing("GetObjectives")
  return {}
end

function C.InLogSet()
  local set = {}
  for _, q in ipairs(C.IterQuestLog()) do set[q.questID] = q end
  return set
end

function C.TrivialRange(level)
  local f = G("C_QuestLog.GetTrivialRange")
  if f then
    local ok, v = pcall(f)
    v = ok and R(v)
    if type(v) == "number" and v >= 0 and v < 30 then return v end
  end
  local g = _G.GetQuestGreenRange
  if g then local ok, v = pcall(g) if ok and type(R(v)) == "number" then return v end end
  -- Fallback approximation (green range widens with level). [INFERENCE]
  level = level or 1
  if level < 10 then return 5 elseif level < 20 then return 6 elseif level < 40 then return 7
  elseif level < 50 then return 8 end
  return 9
end

function C.KnowsSpell(spellID)
  local f = G("C_SpellBook.IsSpellKnown") or _G.IsPlayerSpell or _G.IsSpellKnown
  if not f then return nil end
  local ok, v = pcall(f, spellID)
  return ok and R(v) and true or false
end

-------------------------------------------------------------------------------
-- WoW Forever's class talents (0.9.9.4 hotfix): Blizzard's trait tree (C_ClassTalents and C_Traits). Classic Era's GetTalentInfo,
-- GetNumTalents, GetNumTalentTabs and UnitCharacterPoints are not in that game and are never called there (Modules/SpecTrainer).
-- Reading only: no function here spends, refunds, stages or commits a point. Each returns nil when the game does not answer.
-------------------------------------------------------------------------------
local function call(path, ...)
  local f = G(path)
  if type(f) ~= "function" then missing(path) return nil end
  local ok, a, b = pcall(f, ...)
  if not ok then C.errors[path] = a return nil end
  return a, b
end

-- the config the game's talent window shows: the active spec group's combat config (C_SpecializationInfo), else
-- C_ClassTalents.GetActiveConfigID (the frame starts from that one and goes past it when it is nil). Returns the config and how it was
-- found ("group" | "active").
function C.TalentConfig()
  if G("C_SpecializationInfo.GetActiveSpecGroup") and G("C_SpecializationInfo.GetCombatConfigIDForSpecGroup") then
    local group = tonumber(R(call("C_SpecializationInfo.GetActiveSpecGroup")))
    local id = group and R(call("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", group))
    if type(id) == "number" then return id, "group" end
  end
  local id = R(call("C_ClassTalents.GetActiveConfigID"))
  if type(id) == "number" then return id, "active" end
  return nil
end

-- the node ids of a trait tree, or nil
function C.TalentTreeNodes(tree)
  local list = call("C_Traits.GetTreeNodes", tree)
  return type(list) == "table" and list or nil
end

-- one node of the config: { id, rank (learned), current (learned plus shown but not applied), max, entry }, or nil when the game has
-- no such node (it answers ID 0, or nothing)
function C.TalentNode(config, nodeID)
  local info = call("C_Traits.GetNodeInfo", config, nodeID)
  if type(info) ~= "table" then return nil end
  local id = tonumber(R(info.ID))
  if not id or id == 0 then return nil end
  local rank = tonumber(R(info.activeRank)) or 0
  local entry = type(info.activeEntry) == "table" and tonumber(R(info.activeEntry.entryID)) or nil
  if not entry and type(info.entryIDs) == "table" then entry = tonumber(R(info.entryIDs[1])) end
  -- (0.9.9.4: where the node is drawn, its arrows out and whether it is shown: the game's own tree, ST:LiveTree. Its gates are the static
  -- tree's, Blizzard's tables: the game's own conditions are not read)
  local edges = {}
  for _, e in ipairs(type(info.visibleEdges) == "table" and info.visibleEdges or {}) do
    local t = type(e) == "table" and tonumber(R(e.targetNode)) or nil
    if t then edges[#edges + 1] = t end
  end
  local visible = R(info.isVisible)
  return { id = id, rank = rank, current = tonumber(R(info.currentRank)) or rank, max = tonumber(R(info.maxRanks)) or 0, entry = entry,
           posX = tonumber(R(info.posX)), posY = tonumber(R(info.posY)), edges = edges, visible = visible ~= false }
end

-- the trait tree a config shows (its first tree), or nil
function C.TalentConfigTree(config)
  local info = call("C_Traits.GetConfigInfo", config)
  local ids = type(info) == "table" and info.treeIDs
  return type(ids) == "table" and tonumber(R(ids[1])) or nil
end

-- an entry's spell id and its name in the game's language (the definition's own name when it has one)
function C.TalentEntrySpell(config, entryID)
  if not entryID then return nil end
  local e = call("C_Traits.GetEntryInfo", config, entryID)
  local defID = type(e) == "table" and tonumber(R(e.definitionID)) or nil
  local d = defID and call("C_Traits.GetDefinitionInfo", defID)
  if type(d) ~= "table" then return nil end
  local spell = tonumber(R(d.spellID))
  local name = R(d.overrideName)
  if type(name) ~= "string" or name == "" then name = spell and C.SpellName(spell) or nil end
  return spell, name
end

-- the unspent points on the tree (the tree's currency); nil when the game cannot say
function C.TalentUnspent(config, tree)
  local list = call("C_Traits.GetTreeCurrencyInfo", config, tree, false)
  if type(list) ~= "table" or not list[1] then return nil end
  local n
  for _, c in ipairs(list) do
    local qn = type(c) == "table" and tonumber(R(c.quantity)) or nil
    if qn then n = (n or 0) + qn end
  end
  return n
end

-- a spell's name and icon in this game
function C.SpellName(spell)
  local n = R(call(G("C_Spell.GetSpellName") and "C_Spell.GetSpellName" or "GetSpellInfo", spell))
  return type(n) == "string" and n ~= "" and n or nil
end
function C.SpellIcon(spell)
  local ic = R(call(G("C_Spell.GetSpellTexture") and "C_Spell.GetSpellTexture" or "GetSpellTexture", spell))
  return (type(ic) == "number" or type(ic) == "string") and ic or nil
end

function C.IsEliteQuest(questID)
  local f = G("C_QuestLog.IsEliteQuest")
  if not f then return false end
  local ok, v = pcall(f, questID)
  return ok and R(v) and true or false
end

-------------------------------------------------------------------------------
-- Quest NPC interaction (automation)
-------------------------------------------------------------------------------
function C.GossipAvailable()
  local out = {}
  local f = G("C_GossipInfo.GetAvailableQuests")
  if f then
    local ok, list = pcall(f)
    if ok and type(list) == "table" then
      for i, q in ipairs(list) do
        out[#out + 1] = { questID = q.questID, title = q.title, isTrivial = q.isTrivial,
                          repeatable = q.repeatable, index = i }
      end
    end
    return out
  end
  missing("GossipAvailable")
  return out
end

function C.GossipActive()
  local out = {}
  local f = G("C_GossipInfo.GetActiveQuests")
  if f then
    local ok, list = pcall(f)
    if ok and type(list) == "table" then
      for i, q in ipairs(list) do
        out[#out + 1] = { questID = q.questID, title = q.title, isComplete = q.isComplete, index = i }
      end
    end
    return out
  end
  missing("GossipActive")
  return out
end

-- Mainline takes a questID; older builds took an index. Try questID first.
function C.GossipSelectAvailable(q)
  local f = G("C_GossipInfo.SelectAvailableQuest")
  if not f then missing("GossipSelectAvailable") return false end
  return (pcall(f, q.questID or q.index))
end
function C.GossipSelectActive(q)
  local f = G("C_GossipInfo.SelectActiveQuest")
  if not f then missing("GossipSelectActive") return false end
  return (pcall(f, q.questID or q.index))
end

-- QUEST_GREETING (non-gossip quest givers)
function C.GreetingActive()
  local out = {}
  local n = _G.GetNumActiveQuests and GetNumActiveQuests() or 0
  for i = 1, n do
    local title, isComplete = nil, nil
    if _G.GetActiveTitle then title, isComplete = GetActiveTitle(i) end
    local qid = _G.GetActiveQuestID and GetActiveQuestID(i) or nil
    out[#out + 1] = { index = i, title = title, isComplete = isComplete, questID = qid }
  end
  return out
end
function C.GreetingAvailable()
  local out = {}
  local n = _G.GetNumAvailableQuests and GetNumAvailableQuests() or 0
  for i = 1, n do
    local isTrivial, _, isRepeatable, _, questID
    if _G.GetAvailableQuestInfo then isTrivial, _, isRepeatable, _, questID = GetAvailableQuestInfo(i) end
    out[#out + 1] = { index = i, title = _G.GetAvailableTitle and GetAvailableTitle(i), isTrivial = isTrivial, repeatable = isRepeatable, questID = questID }
  end
  return out
end
function C.GreetingSelectActive(i) if _G.SelectActiveQuest then SelectActiveQuest(i) return true end return false end
function C.GreetingSelectAvailable(i) if _G.SelectAvailableQuest then SelectAvailableQuest(i) return true end return false end

function C.DialogQuestID()
  local f = _G.GetQuestID
  return f and R(f()) or nil
end
function C.AcceptQuest() if _G.AcceptQuest then AcceptQuest() return true end missing("AcceptQuest") return false end
-- 0.9.6.1 (PS-0011): what the game's own Accept button reads before it answers a quest window (WoW Forever's quest window; a
-- client without one of these answers false). QuestGetAutoAccept: the game gave the quest as the window opened, and the window
-- is only acknowledged (AcknowledgeAutoAcceptQuest), never accepted again. QuestIsFromAreaTrigger: a quest offered by walking
-- into a place (the game shows its own pop-up). QuestFlagsPVP: taking it turns PvP on, and the game asks the player first.
local function flag(name)
  local f = _G[name]
  if type(f) ~= "function" then return false end
  local ok, v = pcall(f)
  return ok and R(v) and true or false
end
function C.DialogTitle()
  local f = _G.GetTitleText
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f)
  v = ok and R(v) or nil
  return type(v) == "string" and v ~= "" and v or nil
end
function C.QuestAutoAccepted() return flag("QuestGetAutoAccept") end
function C.QuestFromAreaTrigger() return flag("QuestIsFromAreaTrigger") end
function C.QuestNeedsPvPConfirm() return flag("QuestFlagsPVP") end
function C.AcknowledgeAutoAccept()
  if type(_G.AcknowledgeAutoAcceptQuest) == "function" then AcknowledgeAutoAcceptQuest() return true end
  missing("AcknowledgeAutoAcceptQuest")
  return false
end
function C.IsQuestCompletable() return _G.IsQuestCompletable and IsQuestCompletable() and true or false end
function C.CompleteQuest() if _G.CompleteQuest then CompleteQuest() return true end missing("CompleteQuest") return false end
function C.NumQuestChoices() return _G.GetNumQuestChoices and GetNumQuestChoices() or 0 end
function C.GetQuestReward(choice) if _G.GetQuestReward then GetQuestReward(choice) return true end missing("GetQuestReward") return false end

-------------------------------------------------------------------------------
-- Map & position
-------------------------------------------------------------------------------
function C.GetPlayerPos()
  local best = G("C_Map.GetBestMapForUnit")
  local pos = G("C_Map.GetPlayerMapPosition")
  if not (best and pos) then missing("GetPlayerPos") return nil end
  local ok, mapID = pcall(best, "player")
  mapID = ok and R(mapID)
  if not mapID then return nil end
  local ok2, p = pcall(pos, mapID, "player")
  if not ok2 or not p then return nil end   -- nil inside instances
  local x, y
  if p.GetXY then x, y = p:GetXY() else x, y = p.x, p.y end
  x, y = R(x), R(y)
  if not x or not y or (x == 0 and y == 0) then return nil end
  return mapID, x, y
end

-- Known approximate map sizes in yards (fallback only; live client values preferred).
C.fallbackMapSize = {
  [1429] = { 3470.8, 2314.6 }, [1426] = { 4925.0, 3283.3 }, [1438] = { 5091.7, 3393.8 },
  [1439] = { 6550.0, 4366.7 }, [1436] = { 3500.0, 2333.3 }, [1432] = { 2758.3, 1839.6 },
  [1453] = { 1737.5, 1158.3 }, [1455] = { 790.6, 527.6 },  [1457] = { 1058.3, 705.7 },
  [1433] = { 2170.8, 1447.9 }, [1431] = { 2700.0, 1800.0 }, [1437] = { 4135.4, 2756.3 },
}

-- 0.6.0 (zone-change arrow fix): C_Map.GetMapWorldSize is a retail / Forever API; the Classic Era
-- 1.15 client does not have it. Before, every zone outside the 12-entry fallback table (Arathi,
-- Hillsbrad and everything past the low-level zones) had no size, so the arrow lost its direction
-- and fell back to "Head to <zone>" even inside the target's zone. Now the size is measured from
-- C_Map.GetWorldPosFromMapPos (every client has it), then the route data's map rects, then the table.
C.mapSizeCache = {}
local function measuredSize(mapID)
  local c0, ax, ay = C.WorldPos(mapID, 0, 0)
  local c1, bx, by = C.WorldPos(mapID, 1, 0)
  local c2, dx, dy = C.WorldPos(mapID, 0, 1)
  if not (c0 and c1 and c2 and ax and bx and dx and ay and by and dy) then return nil end
  local w = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
  local h = math.sqrt((dx - ax) ^ 2 + (dy - ay) ^ 2)
  if w > 1 and h > 1 then return w, h end
  return nil
end
local function routeDataSize(mapID)
  local RD = rawget(_G, "PanoplySuiteRouteData")
  local r = RD and RD.rects and RD.rects[mapID]
  if not r then return nil end
  local w, h = math.abs(r[5] - r[3]), math.abs(r[4] - r[2])
  if w > 1 and h > 1 then return w, h end
  return nil
end
function C.MapSize(mapID)
  if not mapID then return nil end
  local f = G("C_Map.GetMapWorldSize")
  if f then
    local ok, w, h = pcall(f, mapID)
    if ok and R(w) and R(h) and w > 0 and h > 0 then return w, h end
  end
  local hit = C.mapSizeCache[mapID]
  if hit then return hit[1], hit[2] end
  local w, h = measuredSize(mapID)
  if not w then w, h = routeDataSize(mapID) end
  if not w then
    local fb = C.fallbackMapSize[mapID]
    if fb then w, h = fb[1], fb[2] end
  end
  if not w then return nil end
  C.mapSizeCache[mapID] = { w, h }
  return w, h
end

-- World position of a map point. Returns continentID, wx, wy (axes as the client defines them).
function C.WorldPos(mapID, x, y)
  local f = G("C_Map.GetWorldPosFromMapPos")
  local mk = _G.CreateVector2D
  if not (f and mk) then missing("WorldPos") return nil end
  local ok, cont, vec = pcall(f, mapID, mk(x, y))
  if not ok or not vec then return nil end
  local wx, wy
  if vec.GetXY then wx, wy = vec:GetXY() else wx, wy = vec.x, vec.y end
  return R(cont), R(wx), R(wy)
end

function C.MapName(mapID)
  local f = G("C_Map.GetMapInfo")
  if not f or not mapID then return nil end
  local ok, info = pcall(f, mapID)
  local name = ok and info and R(info.name) or nil
  return (type(name) == "string" and name ~= "") and name or nil
end

-- 0.6.1: the kind of a map (Enum.UIMapType: 0 cosmic, 1 world, 2 continent, 3 zone, 4 dungeon...).
function C.MapType(mapID)
  local f = G("C_Map.GetMapInfo")
  if not f or not mapID then return nil end
  local ok, info = pcall(f, mapID)
  local t = ok and info and R(info.mapType) or nil
  return tonumber(t)
end
C.MAP_TYPE_CONTINENT = 2

function C.Facing()
  local f = _G.GetPlayerFacing
  if not f then missing("Facing") return nil end
  local ok, v = pcall(f)
  return ok and R(v) or nil
end

function C.OnTaxi()
  local f = _G.UnitOnTaxi
  return f and R(f("player")) and true or false
end

function C.SetBlizzWaypoint(mapID, x, y)
  local set = G("C_Map.SetUserWaypoint")
  local mk = G("UiMapPoint.CreateFromCoordinates")
  if not (set and mk) then missing("SetBlizzWaypoint") return false end
  local can = G("C_Map.CanSetUserWaypointOnMap")
  if can then local ok, v = pcall(can, mapID) if ok and not v then return false end end
  local ok = pcall(set, mk(mapID, x, y))
  if not ok then return false end
  local st = G("C_SuperTrack.SetSuperTrackedUserWaypoint")
  if st then pcall(st, true) end
  return true
end

function C.ClearBlizzWaypoint()
  local f = G("C_Map.ClearUserWaypoint")
  if f then pcall(f) end
end

-------------------------------------------------------------------------------
-- Taxi
-------------------------------------------------------------------------------
-- Returns list of { name, slotIndex, nodeID, state = "current"|"reachable"|"none" }
function C.TaxiNodes()
  local out = {}
  local all = G("C_TaxiMap.GetAllTaxiNodes")
  local mapIDf = _G.GetTaxiMapID
  if all and mapIDf then
    local ok, nodes = pcall(all, mapIDf())
    if ok and type(nodes) == "table" then
      local E = G("Enum.FlightPathState") or {}
      for _, n in ipairs(nodes) do
        local st = "none"
        if n.state == E.Current then st = "current" elseif n.state == E.Reachable then st = "reachable" end
        out[#out + 1] = { name = n.name, slotIndex = n.slotIndex, nodeID = n.nodeID, state = st }
      end
      return out
    end
  end
  if _G.NumTaxiNodes and _G.TaxiNodeName then
    for i = 1, NumTaxiNodes() do
      local t = _G.TaxiNodeGetType and TaxiNodeGetType(i) or "NONE"
      out[#out + 1] = { name = TaxiNodeName(i), slotIndex = i, state = (t == "CURRENT" and "current") or (t == "REACHABLE" and "reachable") or "none" }
    end
    return out
  end
  missing("TaxiNodes")
  return out
end

function C.TakeTaxi(slotIndex)
  local f = _G.TakeTaxiNode
  if not f then missing("TakeTaxi") return false end
  return (pcall(f, slotIndex))
end

-------------------------------------------------------------------------------
-- Items / skills / trade skills
-------------------------------------------------------------------------------
function C.ItemCount(itemID, includeBank)
  local f = G("C_Item.GetItemCount") or _G.GetItemCount
  if not f then missing("ItemCount") return 0 end
  local ok, n = pcall(f, itemID, includeBank)
  return ok and R(n) or 0
end

local function normSkill(a, ...)
  if type(a) == "table" then
    return { name = a.skillName or a.name, rank = a.skillRank or a.rank or a.currentLevel, max = a.skillMaxRank or a.maxRank or a.maxLevel,
             isHeader = a.isHeader, skillLineID = a.skillLineID or a.skillLine or a.skillID or a.id }
  end
  -- Classic tuple: name, isHeader, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank
  local isHeader, _, rank, _, _, max = ...
  return { name = a, isHeader = isHeader, rank = rank, max = max }
end

-- Returns list of { name, rank, max, skillLineID }
function C.GetSkills()
  local out = {}
  local n1, i1 = G("C_SkillInfo.GetNumSkillLines"), G("C_SkillInfo.GetSkillLineInfo")
  if n1 and i1 then
    local okN, n = pcall(n1)
    if okN and type(n) == "number" then
      for i = 1, n do
        local ok, a, b, c, d, e, f2, g = pcall(i1, i)
        if ok and a then
          local s = normSkill(a, b, c, d, e, f2, g)
          if s.name and not s.isHeader then out[#out + 1] = s end
        end
      end
      if #out > 0 or not _G.GetProfessions then return out, "C_SkillInfo" end
    end
  end
  if _G.GetNumSkillLines and _G.GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local s = normSkill(GetSkillLineInfo(i))
      if s.name and not s.isHeader then out[#out + 1] = s end
    end
    if #out > 0 or not _G.GetProfessions then return out, "GetSkillLineInfo" end
  end
  if _G.GetProfessions and _G.GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 6 do
      local idx = list[i]
      if idx then
        local name, _, rank, max, _, _, skillLine = GetProfessionInfo(idx)
        out[#out + 1] = { name = name, rank = rank, max = max, skillLineID = skillLine }
      end
    end
    return out, "GetProfessions"
  end
  missing("GetSkills")
  return out, nil
end

local difficultyNames = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

-- Reads the currently open profession window. Returns nil if none open.
-- { name, rank, max, recipes = { {name, difficulty} } }
function C.ReadOpenTradeSkill()
  local ids = G("C_TradeSkillUI.GetAllRecipeIDs")
  local info = G("C_TradeSkillUI.GetRecipeInfo")
  if ids and info then
    local ok, list = pcall(ids)
    if ok and type(list) == "table" and #list > 0 then
      local res = { recipes = {} }
      local base = G("C_TradeSkillUI.GetBaseProfessionInfo") or G("C_TradeSkillUI.GetChildProfessionInfo")
      if base then
        local okb, p = pcall(base)
        if okb and type(p) == "table" then
          res.name = p.professionName or p.parentProfessionName
          res.rank, res.max = p.skillLevel, p.maxSkillLevel
        end
      end
      for _, rid in ipairs(list) do
        local ok2, r = pcall(info, rid)
        if ok2 and type(r) == "table" and r.learned ~= false then
          local d = r.relativeDifficulty ~= nil and difficultyNames[r.relativeDifficulty] or r.difficulty
          res.recipes[#res.recipes + 1] = { name = r.name, difficulty = d, recipeID = rid }
        end
      end
      return res, "C_TradeSkillUI"
    end
  end
  if _G.GetNumTradeSkills and _G.GetTradeSkillInfo then
    local n = GetNumTradeSkills() or 0
    if n > 0 then
      local res = { recipes = {} }
      if _G.GetTradeSkillLine then res.name, res.rank, res.max = GetTradeSkillLine() end
      for i = 1, n do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
          res.recipes[#res.recipes + 1] = { name = name, difficulty = kind }
        end
      end
      return res, "GetTradeSkillInfo"
    end
  end
  -- Classic Era Enchanting (and Beast Training) use the Craft window.
  if _G.GetNumCrafts and _G.GetCraftInfo then
    local okN, n = pcall(GetNumCrafts)
    if okN and n and n > 0 then
      local res = { recipes = {} }
      if _G.GetCraftDisplaySkillLine then res.name, res.rank, res.max = GetCraftDisplaySkillLine() end
      for i = 1, n do
        local name, _, kind = GetCraftInfo(i)
        if name and kind ~= "header" then res.recipes[#res.recipes + 1] = { name = name, difficulty = kind } end
      end
      if res.name then return res, "GetCraftInfo" end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Addon messages
-------------------------------------------------------------------------------
function C.RegisterPrefix(prefix)
  local f = G("C_ChatInfo.RegisterAddonMessagePrefix") or _G.RegisterAddonMessagePrefix
  if not f then missing("RegisterPrefix") return false end
  local ok, res = pcall(f, prefix)
  return ok and res ~= false
end

-- Returns ok(boolean), reason ("ok"|"lockdown"|"throttled"|"error"|code)
function C.Send(prefix, msg, channel, target)
  local f = G("C_ChatInfo.SendAddonMessage") or _G.SendAddonMessage
  if not f then missing("Send") return false, "missing" end
  local ok, res = pcall(f, prefix, msg, channel, target)
  if not ok then return false, "error" end
  if res == nil or res == true or res == 0 then return true, "ok" end
  if res == false then return false, "error" end
  local E = G("Enum.SendAddonMessageResult") or {}
  if res == (E.AddOnMessageLockdown or 11) then return false, "lockdown" end
  if E.AddonMessageThrottle and res == E.AddonMessageThrottle then return false, "throttled" end
  return false, tostring(res)
end

-------------------------------------------------------------------------------
-- Inventory of wrappers for /panoply selftest. Each probe returns status, detail.
-------------------------------------------------------------------------------
C.probes = {
  { "BuildInfo", function() local v, b, _, toc = C.BuildInfo() if not v then return "MISSING" end return "PASS", ("%s build %s Interface %s"):format(v, tostring(b), tostring(toc)) end },
  { "Game", function() local f = C.Flavor() return (f == "forever" or f == "era") and "PASS" or "WARN", C.FlavorLabel() .. " (WOW_PROJECT_ID=" .. tostring(_G.WOW_PROJECT_ID) .. ")" end },
  { "Secrets API", function()
      if _G.issecretvalue then return "PASS", "issecretvalue present (Midnight rules on)" end
      if C.IsEra() then return "PASS", "not used on Classic (no Midnight rules)" end
      return "WARN", "no issecretvalue" end },
  { "PlayerInfo", function() local p = C.PlayerInfo() if not p.race then return "MISSING" end return "PASS", ("%s %s %s (raceID %s)"):format(tostring(p.faction), tostring(p.race), tostring(p.class), tostring(p.raceID)) end },
  { "GroupLeader", function() if not (_G.UnitIsGroupLeader or _G.UnitIsPartyLeader) then return "WARN", "no party-leader query: partner route leader falls back to name order" end
      local name, me = C.GroupLeader() return "PASS", name and (me and "you hold the party crown" or (name .. " holds the party crown")) or "no group, or no leader reported" end },
  { "XP", function() local l, x, m = C.XP() return "PASS", ("level %d, %d/%d xp"):format(l, x, m) end },
  { "IsQuestCompleted", function() if not (G("C_QuestLog.IsQuestFlaggedCompleted") or _G.IsQuestFlaggedCompleted) then return "MISSING" end C.IsQuestCompleted(1) return "PASS" end },
  { "GetAllCompleted", function() local s, how = C.GetAllCompleted() if not how then return "MISSING" end return "PASS", ("%d completed via %s"):format(Panoply.Util.Count(s), how) end },
  { "IterQuestLog", function() if not (G("C_QuestLog.GetInfo") or _G.GetQuestLogTitle) then return "MISSING" end return "PASS", #C.IterQuestLog() .. " quests in log" end },
  { "GetObjectives", function() local how = C.Features().objectives if how == "missing" then return "MISSING" end return "PASS", how end },
  { "TrivialRange", function() return (G("C_QuestLog.GetTrivialRange") or _G.GetQuestGreenRange or C.IsEra()) and "PASS" or "WARN", "range " .. C.TrivialRange(C.XP()) end },
  { "PlayerPos", function() if not G("C_Map.GetBestMapForUnit") then return "MISSING" end local m, x, y = C.GetPlayerPos() if not m then return "WARN", "no position (instance?)" end return "PASS", ("map %d %.1f,%.1f"):format(m, x * 100, y * 100) end },
  { "MapSize", function() local m = C.GetPlayerPos() if not m then return "SKIP" end local w, h = C.MapSize(m) if not w then return "MISSING" end return G("C_Map.GetMapWorldSize") and "PASS" or "WARN", ("%.0f x %.0f yd"):format(w, h) end },
  { "WorldPos", function() local m, x, y = C.GetPlayerPos() if not m then return "SKIP" end local c = C.WorldPos(m, x, y) return c and "PASS" or "MISSING", c and ("continent " .. tostring(c)) or nil end },
  { "Facing", function() local f = C.Facing() if f == nil then return _G.GetPlayerFacing and "WARN" or "MISSING", "facing unreadable (secret/instance?)" end return "PASS" end },
  { "UserWaypoint", function()
      if C.Features().blizzWaypoint then return "PASS", G("C_SuperTrack.SetSuperTrackedUserWaypoint") and "supertrack ok" or "no C_SuperTrack" end
      if C.IsEra() then return "PASS", "not on Classic: Panoply Suite arrow only" end
      return "MISSING" end },
  { "Skills", function() local s, how = C.GetSkills() if not how then return "MISSING" end return "PASS", ("%d skill lines via %s"):format(#s, how) end },
  { "TradeSkillUI", function() if G("C_TradeSkillUI.GetAllRecipeIDs") then return "PASS", "C_TradeSkillUI (open a profession to read recipes)" end if _G.GetTradeSkillInfo then return "PASS", "classic trade skill API" .. (_G.GetCraftInfo and " + craft window" or "") end return "MISSING" end },
  { "Taxi", function() if G("C_TaxiMap.GetAllTaxiNodes") or _G.NumTaxiNodes then return "PASS", "open a flight master to read nodes" end return "MISSING" end },
  { "Gossip", function() local how = C.Features().gossip return how ~= "missing" and "PASS" or "MISSING", how end },
  { "QuestDialog", function() return (_G.AcceptQuest and _G.CompleteQuest and _G.GetQuestReward) and "PASS" or "MISSING" end },
  { "AddonMessages", function()
      if C.Features().addonMessages == "missing" then return "MISSING" end
      local inst = C.InInstance()
      if not C.Features().restrictions then return "PASS", "no Midnight limits: sync also works in dungeons" end
      return "PASS", inst and "in instance: sync paused (Midnight rules)" or "ok (pauses in dungeons)" end },
  { "Timers", function() return G("C_Timer.After") and "PASS" or "MISSING" end },
  { "Ruleset", function() local r = C.Ruleset() return r ~= "unknown" and "PASS" or "WARN", r end },
}

-- Does a built-in client file exist? true/false when the game can tell us, nil when it can't
-- (then the caller just uses it; a missing texture shows nothing, never an error).
function C.FileExists(path)
  local f = _G.GetFileIDFromPath
  if not f then return nil end
  local ok, id = pcall(f, path)
  if not ok then return nil end
  return id ~= nil and id ~= 0
end

-- Names of online friends (C_FriendList in both clients; older global API as a fallback).
function C.FriendNames()
  local out = {}
  local FL = _G.C_FriendList
  if FL and FL.GetNumFriends and FL.GetFriendInfoByIndex then
    local ok, n = pcall(FL.GetNumFriends)
    for i = 1, (ok and n or 0) do
      local ok2, info = pcall(FL.GetFriendInfoByIndex, i)
      if ok2 and info and info.name and info.connected ~= false then out[#out + 1] = R(info.name) end
    end
  elseif _G.GetNumFriends and _G.GetFriendInfo then
    for i = 1, GetNumFriends() or 0 do
      local name, _, _, _, connected = GetFriendInfo(i)
      if name and connected then out[#out + 1] = name end
    end
  end
  return out
end
