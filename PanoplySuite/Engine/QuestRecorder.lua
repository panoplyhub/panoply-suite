-- Panoply Suite quest recorder for WoW Forever (3 Nov 2026: "quietly save quest id, name, level, giver/turn-in NPC
-- and position, objectives and where they were done ... /panoply recorded shows what was captured"). Own code.
--
-- WoW Forever has quests the 1.12 data does not know: the new zones (Mount Hyjal, Riverglades, Zephras Isle, the
-- Darkspear Islands, Shen'dralas) and the Skyborne races. The only source for them is the game client itself while
-- somebody plays. This module only READS what the client reports, on the game's own quest events. It never accepts,
-- targets, casts or moves anything, and add-ons cannot go online: nothing leaves the computer. The file is written
-- by the game into SavedVariables (PanoplySuiteDB.questRecords, account-wide, so every character on one PC merges);
-- tools/import_forever_recordings.py turns the saved files into Panoply Suite's quest data for review.
--
-- It records a quest when ANY of these is true (the reason is saved as "why"):
--   race   the player is Skyborne (race id 95 or 96, or a race name with "Skyborne"),
--   zone   the quest was taken, handed in or worked on in a new Forever zone (a map, a map inside one, or the zone name),
--   data   the quest id is in the Forever-only list of PanoplySuite_QuestData (Data/ForeverZones.lua, when it exists),
--   new    PanoplySuite_QuestData is loaded and does not know the quest id at all (a Forever-only quest).
-- Anything else (an old-zone quest played by a normal race) is never recorded. On Classic Era nothing registers.
--
-- Where the zone and race facts come from (FR:Data): PanoplySuite_QuestData's Forever overlay (overlay.forever.newZones,
-- .races) and, when the file exists, DB.foreverZones from Data/ForeverZones.lua:
--   DB.foreverZones = { zones  = { [areaId] = { name =, uiMaps = { uiMapId, ... }, minLevel =, maxLevel = } },
--                       quests = { [questId] = <anything> },   -- Forever-only quest ids (a list of ids works too)
--                       races  = { [raceId] = <anything> } }
-- A shape that differs from this is ignored (never an error); the built-in fallback below always applies:
-- the five AreaTable ids of the new zones and races 95 and 96 (Blizzard client tables, build 1.60.1.70755).
--
-- What is saved, per quest id, in PanoplySuiteDB.questRecords = { v, quests = { [questId] = record } }:
--   nm title   lv quest level   plv lowest player level seen accepting it (an upper bound of the required level)
--   z zone name where it was taken   why reason (above)   b client build "1.60.1.70755"   t0 / t1 first / last time (unix)
--   n times accepted   td times handed in   by { "raceId/CLASS/Faction" = true }   (who recorded it)
--   gv { {id, nm, k "npc"|"object", m uiMap, x, y (percent 0..100), n} }   quest givers; at most MAX_NPCS spots
--   en { ... same ... }   turn-in NPCs (the spot is where the PLAYER stood, within talking range of the NPC)
--   ob { { tx text without the count, ty type, nd needed count, at { ["uiMap:x:y"] = times } } }
--      at = where the player stood each time the objective's count went up, on a 0.5 percent grid, at most MAX_CELLS
--   pre { [questId] = times }   quests handed in during the 10 minutes before this one was accepted (prerequisite hints)
--   preNpc true   the most recent one was handed in at this quest's giver (a quest-line step)
-- Size caps: MAX_QUESTS quests, MAX_CELLS objective spots per objective, MAX_CELLS_TOTAL in all; when the store is
-- full new quests are not added (one chat line says so) and nothing already saved is dropped.
local ADDON, Panoply = ...
local C = Panoply.Compat
local FR = {}
Panoply.QuestRecorder = FR
local floor, abs, min, max = math.floor, math.abs, math.min, math.max

FR.SCHEMA = 1
FR.MAX_QUESTS = 1500
FR.MAX_OBJ = 12             -- objectives kept per quest
FR.MAX_CELLS = 24           -- objective spots per objective
FR.MAX_CELLS_TOTAL = 30000  -- objective spots in the whole store
FR.MAX_NPCS = 3             -- giver spots (and turn-in spots) per quest
FR.MAX_WHO = 8              -- recorders (race/class/faction) per quest
FR.MAX_PRE = 8              -- prerequisite hints per quest
FR.CELL = 0.5               -- objective spots are rounded to this many percent of the map
FR.NPC_MERGE = 0.3          -- two NPC spots closer than this (percent of the map, both axes) are one
FR.PENDING_S = 300          -- a quest window's NPC counts for this long
FR.PRE_WINDOW_S = 600       -- a hand-in this recent is a prerequisite hint
FR.SCAN_DELAY_S = 0.5       -- quest log changes are looked at once per half second
FR.CONFIRM_S = 30           -- /panoply recorded clear needs a second command within this time
FR.TITLE_CHARS = 80
FR.TEXT_CHARS = 120
FR.RECENT = 5               -- /panoply recorded lists this many newest quests
FR.TOP_ZONES = 8            -- /panoply recorded lists this many zones

-- Blizzard client tables (AreaTable.csv, build 1.60.1.70755): the zones Forever added to the classic world.
FR.FALLBACK_AREAS = { [616] = "Mount Hyjal", [16591] = "Riverglades", [16593] = "Zephras Isle", [16606] = "Darkspear Islands",
                      [16651] = "Shen'dralas" }
-- ChrRaces.csv: High Order Skyborne (Alliance) and Windshaper Skyborne (Horde).
FR.FALLBACK_RACES = { [95] = true, [96] = true }

local function num(v)
  v = tonumber(v)
  if v and v == v and v > -1e12 and v < 1e12 then return v end
  return 0
end

local function cut(s, n)
  s = tostring(s)
  if #s <= n then return s end
  s = s:sub(1, n)
  local i = #s
  while i > 0 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end   -- never cut a character in half
  if i > 0 and s:byte(i) >= 192 then s = s:sub(1, i - 1) end
  return s
end

local function str(v, n)
  v = C.Readable(v)
  if type(v) ~= "string" or v == "" then return nil end
  return cut(v, n)
end

local function nowUnix()
  local f = _G.time
  return f and floor(num(f())) or 0
end

local function safe(tag, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    FR.errors = (FR.errors or 0) + 1
    FR.lastError = tag .. ": " .. tostring(err)
    Panoply:Debug("quest recorder", tag, err)
  end
  return ok
end

-- Forever only, and the player did not switch it off. Era never records.
-- 0.7.4.1: in an area without a guide (Engine/NoGuide.lua) "Record mode" is the switch, on either client.
local function noGuideRecording()
  local NG = Panoply.NoGuide
  return NG ~= nil and NG:Active() and NG:Recording()
end
local function enabled()
  if Panoply.db == nil then return false end
  local NG = Panoply.NoGuide
  if NG and NG:Active() then return NG:Recording() end   -- the area's own switch decides here (NG:Recording also honours /panoply recorded off)
  return Panoply.db.questRecorder ~= false and C.Flavor() == "forever"
end

-------------------------------------------------------------------------------
-- What counts as a new zone, a Forever-only quest, a Skyborne race
-------------------------------------------------------------------------------
-- { maps = { [uiMapId] = name }, names = { [lowercase zone name] = name }, quests = set or nil, races = set, source = text }
function FR:Data()
  local DB = Panoply.QuestData and Panoply.QuestData.own
  if type(DB) ~= "table" then DB = nil end
  local fz = DB and DB.foreverZones
  local ov = DB and DB.overlay and DB.overlay.forever
  local oz, orc = ov and ov.newZones, ov and ov.races
  local c = self.dataCache
  if c and c.fz == fz and c.oz == oz and c.orc == orc then return c end
  local d = { fz = fz, oz = oz, orc = orc, maps = {}, names = {}, areas = {}, races = {}, source = "built-in", nZones = 0, nQuests = 0 }
  for id, name in pairs(self.FALLBACK_AREAS) do d.areas[id] = name d.names[name:lower()] = name end
  for id in pairs(self.FALLBACK_RACES) do d.races[id] = true end
  local function zoneName(m, name)
    if type(name) == "string" and name ~= "" then d.names[name:lower()] = name end
    d.maps[m] = (type(name) == "string" and name ~= "") and name or d.maps[m] or true
  end
  pcall(function()
    if type(oz) == "table" then for m, name in pairs(oz) do if type(m) == "number" then zoneName(m, name) end end end
    if type(orc) == "table" then for id in pairs(orc) do if type(id) == "number" then d.races[id] = true end end end
    if type(fz) == "table" then
      local used = false
      if type(fz.zones) == "table" then
        for area, z in pairs(fz.zones) do
          if type(area) == "number" and type(z) == "table" then
            used = true
            d.areas[area] = z.name or d.areas[area]
            if type(z.name) == "string" then d.names[z.name:lower()] = z.name end
            local list = type(z.uiMaps) == "table" and z.uiMaps or type(z.uiMapIds) == "table" and z.uiMapIds or {}
            for _, m in ipairs(list) do if type(m) == "number" then zoneName(m, z.name) end end
            if type(z.uiMap) == "number" then zoneName(z.uiMap, z.name) end
          end
        end
      end
      if type(fz.quests) == "table" then
        d.quests = {}
        for k, v in pairs(fz.quests) do
          local id = type(k) == "number" and k or (type(v) == "number" and v) or nil
          if id then d.quests[id] = true used = true end
        end
      end
      if type(fz.races) == "table" then
        for k, v in pairs(fz.races) do
          local id = type(k) == "number" and k or (type(v) == "number" and v) or nil
          if id then d.races[id] = true used = true end
        end
      end
      if used then d.source = "ForeverZones.lua" end
    end
  end)
  for _ in pairs(d.areas) do d.nZones = d.nZones + 1 end
  if d.quests then for _ in pairs(d.quests) do d.nQuests = d.nQuests + 1 end end
  self.dataCache = d
  return d
end

function FR:IsSkyborne(info)
  info = info or C.PlayerInfo()
  if not info then return false end
  local id = tonumber(info.raceID)
  if id and self:Data().races[id] then return true end
  local name = info.race
  return type(name) == "string" and name:find("Skyborne", 1, true) ~= nil
end

-- The new zone a map belongs to (the map itself or up to four parents), or nil; the zone name is the fallback.
function FR:NewZone(map)
  local d = self:Data()
  local m = tonumber(map)
  for _ = 1, 5 do
    if not m or m == 0 then break end
    local hit = d.maps[m]
    if hit then return type(hit) == "string" and hit or "new zone" end
    local f = C.G("C_Map.GetMapInfo")
    if not f then break end
    local ok, info = pcall(f, m)
    local parent = ok and type(info) == "table" and C.Readable(info.parentMapID) or nil
    m = tonumber(parent)
  end
  local z = C.ZoneText()
  if type(z) == "string" and z ~= "" and d.names[z:lower()] then return d.names[z:lower()] end
  return nil
end

-- Why this quest is recorded, or nil when it is not (see the top of the file). `noZone`: leave the player's place
-- out (a quest found in the log was not necessarily taken here).
function FR:Reason(qid, map, noZone)
  if self:IsSkyborne() then return "race" end
  if not noZone and self:NewZone(map) then return "zone" end
  local d = self:Data()
  if d.quests and d.quests[qid] then return "data" end
  local QD = Panoply.QuestData
  if QD and QD.Available and QD:Available() and QD.GetQuest and not QD:GetQuest(qid) then return "new" end
  -- 0.7.4.1: where Panoply Suite has no guide and Record mode is on, every other quest is saved too (an old-zone quest taken there, say)
  if not noZone and noGuideRecording() then return "noguide" end   -- (a quest found in the log was not necessarily taken here)
  return nil
end

-------------------------------------------------------------------------------
-- The store
-------------------------------------------------------------------------------
local function store(create)
  local db = Panoply.db
  if not db then return nil end
  local s = db.questRecords
  if type(s) ~= "table" then
    if not create then return nil end
    s = {}
    db.questRecords = s
  end
  if type(s.quests) ~= "table" then s.quests = {} end
  s.v = FR.SCHEMA
  if FR.counted ~= s then   -- once per session (and after a clear): count what the save file holds
    local nq, nc = 0, 0
    for _, r in pairs(s.quests) do
      nq = nq + 1
      if type(r) == "table" and type(r.ob) == "table" then
        for _, o in pairs(r.ob) do
          if type(o) == "table" and type(o.at) == "table" then for _ in pairs(o.at) do nc = nc + 1 end end
        end
      end
    end
    FR.nQuests, FR.nCells, FR.counted = nq, nc, s
  end
  return s
end
FR.Store = store

local function pct(v) return floor(num(v) * 10000 + 0.5) / 100 end

local function here()
  local m, x, y = C.GetPlayerPos()
  if not m then return nil end
  return m, pct(x), pct(y)
end

local function cellKey(m, x, y)
  local c = FR.CELL
  local cx, cy = floor(x / c + 0.5) * c, floor(y / c + 0.5) * c
  return ("%d:%.1f:%.1f"):format(m, cx, cy)
end

-- "Kobold Vermin slain: 3/10" -> "Kobold Vermin slain";  "3/10 Kobolds" -> "Kobolds"
local function objectiveName(text)
  text = str(text, FR.TEXT_CHARS)
  if not text then return nil end
  local a = text:match("^(.-):?%s*%d+%s*/%s*%d+%s*$")
  if a and a ~= "" then return a end
  local b = text:match("^%d+%s*/%s*%d+%s+(.+)$")
  if b and b ~= "" then return b end
  return text
end

local function whoKey(info)
  return ("%s/%s/%s"):format(tostring(info.raceID or "?"), tostring(info.classFile or "?"), tostring(info.faction or "?"))
end

local function buildText()
  local v, b = C.BuildInfo()
  if v and b then return tostring(v) .. "." .. tostring(b) end
  return v and tostring(v) or nil
end

-- The quest's log entry (title, level), or nil.
local function logEntry(qid)
  for _, q in ipairs(C.IterQuestLog()) do if q.questID == qid then return q end end
  return nil
end

function FR:Notice()
  if not self.noticePending then return end
  if C.InCombat() then return end
  self.noticePending = nil
  if Panoply.db and Panoply.db.questRecorderNotice ~= false then
    if C.Flavor() == "forever" then
      Panoply:Print("Quest recorder on: new Forever quests are saved on this computer only. /panoply recorded shows them; add notice off to silence this.")
    else
      Panoply:Print("Quest recorder on: Panoply Suite has no guide for this area, so the quests you take here are saved on this computer only. /panoply recorded shows them; /panoply recorded notice off silences this.")
    end
  end
end

-- Title and level from the quest log entry (no time stamp change: this runs on every scan until both are known).
function FR.Fill(r, entry)
  if not entry then return end
  local t = str(entry.title, FR.TITLE_CHARS)
  if t then r.nm = t end
  local l = tonumber(C.Readable(entry.level))
  if l and l > 0 then r.lv = l end
end

-- The record for a quest id, made when it is new (nil when the store is full). `entry` is the log entry or nil.
function FR:Touch(qid, reason, entry)
  local s = store(true)
  if not s then return nil end
  local r = s.quests[qid]
  if type(r) ~= "table" then
    if self.nQuests >= self.MAX_QUESTS then
      if not self.fullTold then
        self.fullTold = true
        Panoply:Print(("The quest recorder is full (%d quests). Run the import tool on your saved file, then /panoply recorded clear."):format(self.MAX_QUESTS))
      end
      return nil
    end
    r = { t0 = nowUnix(), n = 0, td = 0, why = reason }
    s.quests[qid] = r
    self.nQuests = self.nQuests + 1
  end
  r.t1 = nowUnix()
  r.b = buildText() or r.b
  FR.Fill(r, entry)
  if not self.noticed then self.noticed, self.noticePending = true, true end
  return r
end

local function addNpc(r, field, npc, m, x, y)
  if not (npc and m and x and y) then return end
  local list = r[field]
  if type(list) ~= "table" then list = {} r[field] = list end
  for _, e in ipairs(list) do
    if type(e) == "table" and e.id == npc.id and e.nm == npc.nm and e.m == m and abs(num(e.x) - x) <= FR.NPC_MERGE and abs(num(e.y) - y) <= FR.NPC_MERGE then
      e.n = num(e.n) + 1
      return
    end
  end
  if #list >= FR.MAX_NPCS then return end
  list[#list + 1] = { id = npc.id, nm = npc.nm, k = npc.kind, m = m, x = x, y = y, n = 1 }
end

local function addWho(r)
  local info = C.PlayerInfo() or {}
  if type(r.by) ~= "table" then r.by = {} end
  local key = whoKey(info)
  if r.by[key] then return end
  local n = 0
  for _ in pairs(r.by) do n = n + 1 end
  if n < FR.MAX_WHO then r.by[key] = true end
end

-- One more spot where the player stood while objective `o` (a record's objective) went up.
local function addCell(o, m, x, y)
  if type(o.at) ~= "table" then o.at = {} end
  local k = cellKey(m, x, y)
  if o.at[k] then o.at[k] = num(o.at[k]) + 1 return end
  local n = 0
  for _ in pairs(o.at) do n = n + 1 end
  if n >= FR.MAX_CELLS or FR.nCells >= FR.MAX_CELLS_TOTAL then return end
  o.at[k] = 1
  FR.nCells = FR.nCells + 1
end

-- What this character's hand-ins say about the order: the quests handed in shortly before, newest first.
function FR:AddPre(r, giverNpc)
  local list = self.turns
  if not list or #list == 0 then return end
  local now = C.GetTime()
  local first, taken = true, 0
  for i = #list, 1, -1 do
    local e = list[i]
    if now - e.t <= self.PRE_WINDOW_S then
      taken = taken + 1
      if type(r.pre) ~= "table" then r.pre = {} end
      local n = 0
      for _ in pairs(r.pre) do n = n + 1 end
      if r.pre[e.id] or n < self.MAX_PRE then r.pre[e.id] = num(r.pre[e.id]) + 1 end
      if first and giverNpc and giverNpc.id and e.npc == giverNpc.id then r.preNpc = true end
      first = false
      if taken >= 3 then break end
    end
  end
end

-------------------------------------------------------------------------------
-- Objectives
-------------------------------------------------------------------------------
-- Compare the quest's objective counts with the last look; a count that went up saves where the player stands.
function FR:Observe(r, qid)
  local objs = C.GetObjectives(qid)
  if type(objs) ~= "table" then return end
  local last = self.last[qid]
  if not last then last = {} self.last[qid] = last end
  local m, x, y = here()
  local changed = false
  for i, o in ipairs(objs) do
    if i > self.MAX_OBJ then break end
    if type(r.ob) ~= "table" then r.ob = {} end
    local ro = r.ob[i]
    if type(ro) ~= "table" then
      ro = {}
      r.ob[i] = ro
    end
    ro.tx = ro.tx or objectiveName(o.text)
    local ty = str(o.type, 20)
    ro.ty = ro.ty or ty
    ro.nd = max(num(ro.nd), num(o.numRequired))
    local have = num(o.numFulfilled)
    local prev = last[i]
    if prev ~= nil and have > prev and m then addCell(ro, m, x, y) changed = true end
    last[i] = have
  end
  if changed then r.t1 = nowUnix() end
end

-- Look at the quest log: quests already recorded get their objectives checked; a quest in the log that qualifies and
-- has no record yet (accepted before the recorder was on, or from another source) is added without a giver.
function FR:Scan(adopt)
  if not enabled() then return end
  local s = store(false)
  local log = C.IterQuestLog()
  local inLog = {}
  for _, q in ipairs(log) do
    local qid = q.questID
    inLog[qid] = true
    local r = s and s.quests[qid]
    if not (type(r) == "table") and adopt and not self.rejected[qid] then
      local why = self:Reason(qid, nil, true)
      if why then
        r = self:Touch(qid, why, q)
        if r then r.adopted = true end
        s = store(false)
      else
        self.rejected[qid] = true
      end
    end
    if type(r) == "table" then
      if r.nm == nil or r.lv == nil then FR.Fill(r, q) end
      safe("observe", self.Observe, self, r, qid)
    end
  end
  for qid in pairs(self.last) do if not inLog[qid] then self.last[qid] = nil end end
end

-- Quest log changes come in bursts: one scan half a second after the first.
function FR:Queue()
  if self.scanPending then return end
  self.scanPending = true
  C.After(self.SCAN_DELAY_S, function()
    self.scanPending = nil
    safe("scan", function() self:Scan(not C.InCombat()) self:Notice() end)
  end)
end

-------------------------------------------------------------------------------
-- NPC at the open quest window
-------------------------------------------------------------------------------
local function guidKind(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id), "npc" end
  if kind == "GameObject" then return tonumber(id), "object" end
  return nil
end

-- { id =, nm =, kind = } of the NPC (or object) whose quest window is open, or nil (a quest started by an item or shared by a player).
local function windowNpc()
  local guid
  if type(_G.UnitGUID) == "function" then
    local ok, g = pcall(_G.UnitGUID, "npc")
    if ok then guid = C.Readable(g) end
  end
  if type(guid) == "string" and guid:find("^Player") then return nil end
  local id, kind = guidKind(guid)
  local name
  if type(_G.UnitName) == "function" then
    local ok, n = pcall(_G.UnitName, "npc")
    if ok then name = str(n, 60) end
  end
  if not id and not name then return nil end
  return { id = id, kind = kind, nm = name }
end

local function dialogQuest()
  if type(_G.GetQuestID) ~= "function" then return nil end
  local ok, id = pcall(_G.GetQuestID)
  id = ok and tonumber(C.Readable(id)) or nil
  if id and id > 0 then return id end
  return nil
end

local function dialogTitle()
  if type(_G.GetTitleText) ~= "function" then return nil end
  local ok, t = pcall(_G.GetTitleText)
  return ok and str(t, FR.TITLE_CHARS) or nil
end

-- A quest window opened: remember who offered it and where we stand (QUEST_DETAIL).
function FR:OnDetail()
  if not enabled() then return end
  local qid = dialogQuest()
  if not qid then return end
  local m, x, y = here()
  self.give[qid] = { npc = windowNpc(), m = m, x = x, y = y, title = dialogTitle(), zone = str((C.ZoneText()), 40), t = C.GetTime() }
end

-- The "hand in" window opened (QUEST_PROGRESS, QUEST_COMPLETE): remember the NPC; flush objective counts first.
function FR:OnFinish(flush)
  if not enabled() then return end
  local qid = dialogQuest()
  if not qid then return end
  local m, x, y = here()
  self.fin[qid] = { npc = windowNpc(), m = m, x = x, y = y, t = C.GetTime() }
  if flush then self:Scan(false) end
end

local function fresh(p) return p and C.GetTime() - p.t <= FR.PENDING_S end

-- QUEST_ACCEPTED carries (questID) on Forever and (questLogIndex, questID) on Era; Era never gets here.
function FR:OnAccepted(a, b)
  if not enabled() then return end
  local qid = tonumber(C.Readable(b or a))
  if not qid or qid <= 0 then return end
  local p = self.give[qid]
  self.give[qid] = nil
  if not fresh(p) then p = nil end
  local s = store(false)
  local existing = s and s.quests[qid]
  local m = p and p.m or here()
  local why = (type(existing) == "table" and existing.why) or self:Reason(qid, m)
  if not why then self.rejected[qid] = true return end
  self.rejected[qid] = nil
  local entry = logEntry(qid) or (p and p.title and { title = p.title }) or nil
  local r = self:Touch(qid, why, entry)
  if not r then return end
  if not r.nm and p and p.title then r.nm = p.title end
  if not r.z then r.z = (p and p.zone) or str((C.ZoneText()), 40) or C.MapName(m) end
  r.n = num(r.n) + 1
  local pl = tonumber(C.Readable(_G.UnitLevel and _G.UnitLevel("player")))
  if pl and pl > 0 then r.plv = r.plv and min(r.plv, pl) or pl end
  addWho(r)
  if p and p.npc then addNpc(r, "gv", p.npc, p.m, p.x, p.y) end
  self:AddPre(r, p and p.npc)
  self:Observe(r, qid)
  self:Queue()
end

-- QUEST_TURNED_IN (questID, xp, money): the quest is done; the NPC is the one whose window was open.
function FR:OnTurnedIn(a)
  if not enabled() then return end
  local qid = tonumber(C.Readable(a))
  if not qid or qid <= 0 then return end
  local e = self.fin[qid]
  self.fin[qid] = nil
  if not fresh(e) then e = nil end
  local m, x, y
  if e then m, x, y = e.m, e.x, e.y else m, x, y = here() end
  local s = store(false)
  local r = s and s.quests[qid]
  local why = (type(r) == "table" and r.why) or self:Reason(qid, m)
  if why then
    r = self:Touch(qid, why, nil)
    if r then
      if not r.z then r.z = str((C.ZoneText()), 40) or C.MapName(m) end
      r.td = num(r.td) + 1
      addWho(r)
      if e and e.npc then addNpc(r, "en", e.npc, m, x, y) end
      self:Queue()
    end
  end
  -- every hand-in is remembered for a while: it may be the lead-in of the next quest
  self.turns = self.turns or {}
  self.turns[#self.turns + 1] = { id = qid, t = C.GetTime(), npc = e and e.npc and e.npc.id or nil }
  while #self.turns > 6 do table.remove(self.turns, 1) end
  self.last[qid] = nil
end

-------------------------------------------------------------------------------
-- Registering
-------------------------------------------------------------------------------
function FR:Register()
  self.registered = false
  self.give, self.fin, self.last, self.rejected = {}, {}, {}, {}
  if C.Flavor() ~= "forever" then return end   -- Classic Era: no events until an area without a guide asks (FR:Hook)
  self:Hook()
end

-- 0.7.4.1: register the quest events once. Forever does it at login; Classic Era only when Record mode is on in an area without a guide.
function FR:Hook()
  if self.registered then return end
  self.registered = true
  self.give, self.fin, self.last, self.rejected = self.give or {}, self.fin or {}, self.last or {}, self.rejected or {}
  Panoply:On("QUEST_DETAIL", function() safe("detail", FR.OnDetail, FR) end)
  Panoply:On("QUEST_PROGRESS", function() safe("progress", FR.OnFinish, FR, false) end)
  Panoply:On("QUEST_COMPLETE", function() safe("complete", FR.OnFinish, FR, true) end)
  Panoply:On("QUEST_ACCEPTED", function(_, a, b) safe("accepted", FR.OnAccepted, FR, a, b) end)
  Panoply:On("QUEST_TURNED_IN", function(_, a) safe("turnedin", FR.OnTurnedIn, FR, a) end)
  Panoply:On("QUEST_REMOVED", function(_, a) local id = tonumber(C.Readable(a)) if id then FR.last[id] = nil end end)
  Panoply:On("QUEST_LOG_UPDATE", function() if enabled() then FR:Queue() end end)
  Panoply:On("QUEST_WATCH_UPDATE", function() if enabled() then FR:Queue() end end)
  Panoply:On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
    unit = C.Readable(unit)
    if enabled() and (unit == nil or unit == "player") then FR:Queue() end
  end)
  Panoply:On("PLAYER_REGEN_ENABLED", function() safe("notice", FR.Notice, FR) end)
  Panoply:On("PLAYER_ENTERING_WORLD", function()   -- the log is there a few seconds after a login or a reload
    if enabled() then C.After(5, function() safe("login scan", function() FR:Scan(true) FR:Notice() end) end) end
  end)
end

-------------------------------------------------------------------------------
-- What was captured
-------------------------------------------------------------------------------
local function eachRecord(fn)
  local s = store(false)
  if not s then return end
  for id, r in pairs(s.quests) do
    if type(id) == "number" and type(r) == "table" then fn(id, r) end
  end
end

local function cellsOf(r)
  local n = 0
  if type(r.ob) == "table" then
    for _, o in pairs(r.ob) do
      if type(o) == "table" and type(o.at) == "table" then for _ in pairs(o.at) do n = n + 1 end end
    end
  end
  return n
end

-- { quests =, givers = (quests with a giver), turnins =, spots = objective spots, zones = { { name, quests, givers, turnins, spots } }, newest = { {id, rec} } }
function FR:Stats()
  local out = { quests = 0, givers = 0, turnins = 0, spots = 0, zones = {}, newest = {} }
  local byZone, all = {}, {}
  eachRecord(function(id, r)
    local hasG = type(r.gv) == "table" and #r.gv > 0
    local hasE = type(r.en) == "table" and #r.en > 0
    local sp = cellsOf(r)
    out.quests = out.quests + 1
    if hasG then out.givers = out.givers + 1 end
    if hasE then out.turnins = out.turnins + 1 end
    out.spots = out.spots + sp
    local zn = type(r.z) == "string" and r.z ~= "" and r.z or "Unknown zone"
    local z = byZone[zn]
    if not z then z = { name = zn, quests = 0, givers = 0, turnins = 0, spots = 0 } byZone[zn] = z out.zones[#out.zones + 1] = z end
    z.quests = z.quests + 1
    if hasG then z.givers = z.givers + 1 end
    if hasE then z.turnins = z.turnins + 1 end
    z.spots = z.spots + sp
    all[#all + 1] = { id = id, rec = r }
  end)
  table.sort(out.zones, function(a, b) if a.quests ~= b.quests then return a.quests > b.quests end return a.name < b.name end)
  table.sort(all, function(a, b)
    local ta, tb = num(a.rec.t1), num(b.rec.t1)
    if ta ~= tb then return ta > tb end
    return a.id > b.id
  end)
  for i = 1, min(#all, self.RECENT) do out.newest[i] = all[i] end
  return out
end

local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function stamp(t)
  t = num(t)
  local f = _G.date
  if t <= 0 or not f then return "unknown time" end
  local ok, s = pcall(f, "%d %b %H:%M", t)
  return ok and s or "unknown time"
end

-- The lines /panoply recorded prints.
function FR:Lines()
  if C.Flavor() ~= "forever" and not self.registered then
    return { "The quest recorder is only for WoW Forever; anywhere else it records only in an area Panoply Suite has no guide for (Record mode)." }
  end
  local out = {}
  local d = self:Data()
  local st = self:Stats()
  local state = (Panoply.db and Panoply.db.questRecorder == false) and " It is switched off (/panoply recorded on)." or ""
  if st.quests == 0 then
    out[1] = "Quest recorder: nothing saved yet. It saves quests in the new Forever zones, for the Skyborne, and quests new to Panoply Suite." .. state
    out[2] = ("Zone list: %s (%s). Everything stays on this computer."):format(d.source, plural(d.nZones, "zone"))
    return out
  end
  out[#out + 1] = ("Quest recorder: %s saved (limit %d)%s"):format(plural(st.quests, "quest"), self.MAX_QUESTS, state == "" and "." or ("." .. state))
  out[#out + 1] = ("Captured: %s with a giver, %s with a turn-in, %s where objectives were done."):format(
    plural(st.givers, "quest"), plural(st.turnins, "quest"), plural(st.spots, "spot"))
  out[#out + 1] = "By zone:"
  for i = 1, min(#st.zones, self.TOP_ZONES) do
    local z = st.zones[i]
    out[#out + 1] = ("  %s: %s, %s, %s, %s"):format(z.name, plural(z.quests, "quest"), plural(z.givers, "giver"), plural(z.turnins, "turn-in"),
      plural(z.spots, "objective spot"))
  end
  if #st.zones > self.TOP_ZONES then out[#out + 1] = ("  and %d more zones"):format(#st.zones - self.TOP_ZONES) end
  out[#out + 1] = ("Newest %d:"):format(#st.newest)
  for _, e in ipairs(st.newest) do
    local r = e.rec
    out[#out + 1] = ("  %d %s (level %s), %s"):format(e.id, tostring(r.nm or "unnamed quest"), r.lv and tostring(r.lv) or "?", stamp(r.t1))
  end
  out[#out + 1] = ("Zone list: %s (%s). Saved on this computer only. /panoply recorded clear deletes it all."):format(d.source, plural(d.nZones, "zone"))
  return out
end

-- Counts only (no names, no positions) for problem reports (Core/Reports.lua).
function FR:ReportSummary()
  if C.Flavor() ~= "forever" then return nil end
  local st = self:Stats()
  if st.quests == 0 then return nil end
  return { recording = enabled(), quests = st.quests, zones = #st.zones, withGiver = st.givers, withTurnIn = st.turnins, spots = st.spots,
           zoneList = self:Data().source }
end

-- Forget everything (the second /panoply recorded clear).
function FR:Clear()
  local n = 0
  local s = store(false)
  if s then for _ in pairs(s.quests) do n = n + 1 end end
  if Panoply.db then Panoply.db.questRecords = nil end
  self.counted, self.nQuests, self.nCells = nil, 0, 0
  self.last, self.rejected, self.give, self.fin, self.turns = {}, {}, {}, {}, nil
  self.fullTold = nil
  -- quests still in the log are not picked up again at once (a /reload or a login does that, without givers)
  local okLog, log = pcall(C.IterQuestLog)
  if okLog and type(log) == "table" then for _, q in ipairs(log) do self.rejected[q.questID] = true end end
  return n
end

-- /panoply recorded | clear | on | off | notice on | notice off
function FR:Slash(args)
  local sub = (args[2] or ""):lower()
  local lines
  if sub ~= "clear" then self.confirmUntil = nil end
  if C.Flavor() ~= "forever" and not self.registered then
    lines = self:Lines()
  elseif sub == "clear" then
    local s = store(false)
    local n = 0
    if s then for _ in pairs(s.quests) do n = n + 1 end end
    if n == 0 then
      lines = { "Nothing is recorded, so there is nothing to clear." }
    elseif self.confirmUntil and C.GetTime() <= self.confirmUntil then
      self.confirmUntil = nil
      lines = { ("Deleted %s from the quest recorder."):format(plural(self:Clear(), "recorded quest")) }
    else
      self.confirmUntil = C.GetTime() + self.CONFIRM_S
      lines = { ("This deletes all %s. Type /panoply recorded clear again within %d seconds to confirm."):format(plural(n, "recorded quest"), self.CONFIRM_S) }
    end
  elseif sub == "on" or sub == "off" then
    Panoply:SetOption("questRecorder", sub == "on")
    lines = { sub == "on" and "The quest recorder is on." or "The quest recorder is off (what is saved stays; /panoply recorded clear deletes it)." }
  elseif sub == "notice" then
    local v = (args[3] or ""):lower()
    if v == "on" or v == "off" then
      Panoply:SetOption("questRecorderNotice", v == "on")
      lines = { v == "on" and "The recorder tells you once per session when it starts saving." or "The recorder is silent when it starts saving." }
    else
      lines = { "Usage: /panoply recorded notice on | off" }
    end
  elseif sub == "" or sub == "list" or sub == "status" then
    lines = self:Lines()
  else
    lines = { "Usage: /panoply recorded | clear | on | off | notice on | notice off" }
  end
  for _, l in ipairs(lines) do Panoply:Print(l) end
  return lines
end
