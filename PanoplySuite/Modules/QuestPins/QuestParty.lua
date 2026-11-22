-- Party quest progress (SPEC 22.6), part of the Quest icons module. Rides on the existing
-- Panoply Suite sync channel (Engine/Sync.lua: prefix HPATH1, PARTY channel, chunking at 255 bytes,
-- throttled queue). Message kind "Q" = a compact summary of the sender's quest log.
-- Information only: nothing is done for anyone.
-- 0.9.7 (partner leveling): with the guide engine's party sync on (Engine/PolestarParty.lua), the party's progress is the engine's:
-- the same quest IDs and counts, already sent to the party by the engine, so nothing of ours is sent a second time. Who has a
-- quest, the counts and the lines below then read from it (P:Engine). "Share with my party" off (PanoplySuiteDB.partyShare)
-- switches this off too: nothing sent, nothing shown.
local ADDON, Panoply = ...
local C = Panoply.Compat
local QP = Panoply.QuestPins
local P = { members = {}, version = 0, THROTTLE = 2, MAX_QUESTS = 40, MAX_LEN = 1600, VERSION = 1 }
Panoply.QuestParty = P
P.stats = { sent = 0, throttled = 0, same = 0, received = 0, malformed = 0, stranger = 0 }

local function shortName(n) return n and (n:match("^([^%-]+)") or n) or n end

-------------------------------------------------------------------------------
-- Encoding: "<questID>:<ready 0|1>[:<have>/<need>,<have>/<need>...]" joined by ";"
-------------------------------------------------------------------------------
function P.Encode(list)
  local parts = {}
  for i, e in ipairs(list) do
    if i > P.MAX_QUESTS then break end
    local s = e.id .. ":" .. (e.ready and 1 or 0)
    if not e.ready and e.obj and #e.obj > 0 then
      local o = {}
      for j, ob in ipairs(e.obj) do
        if j > 8 then break end
        o[j] = math.max(0, math.min(999, math.floor(ob[1] or 0))) .. "/" .. math.max(0, math.min(999, math.floor(ob[2] or 0)))
      end
      s = s .. ":" .. table.concat(o, ",")
    end
    parts[#parts + 1] = s
  end
  return table.concat(parts, ";")
end

-- Strict: anything unexpected makes the whole message invalid (returns nil).
function P.Decode(s)
  if type(s) ~= "string" or #s > P.MAX_LEN or s:find("[^%d:;,/]") then return nil end
  local out, n = {}, 0
  if s == "" then return out end
  for part in (s .. ";"):gmatch("([^;]*);") do
    local id, ready, rest = part:match("^(%d+):([01])(.*)$")
    if not id then return nil end
    id = tonumber(id)
    if id < 1 or id > 9999999 or out[id] then return nil end
    local e = { ready = ready == "1", obj = {} }
    if rest ~= "" then
      local body = rest:match("^:(.+)$")
      if not body then return nil end
      for ob in (body .. ","):gmatch("([^,]*),") do
        local h, need = ob:match("^(%d+)/(%d+)$")
        if not h then return nil end
        h, need = tonumber(h), tonumber(need)
        if h > 999 or need > 999 then return nil end
        e.obj[#e.obj + 1] = { h, need }
        if #e.obj > 8 then return nil end
      end
    end
    out[id] = e
    n = n + 1
    if n > P.MAX_QUESTS then return nil end
  end
  return out
end

-- My quest log as a list for Encode (sorted, so an unchanged log gives the same string).
function P:Summary()
  local list = {}
  for id, e in pairs(Panoply.State.log or {}) do
    local obj = {}
    if not e.isComplete then
      for j, o in ipairs(Panoply.State:Objectives(id) or {}) do
        local need = tonumber(o.numRequired) or 0
        if need == 0 then need = 1 end
        obj[j] = { o.finished and need or (tonumber(o.numFulfilled) or 0), need }
      end
    end
    list[#list + 1] = { id = id, ready = e.isComplete and true or false, obj = obj }
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return P.Encode(list)
end

-------------------------------------------------------------------------------
-- Sending: on quest log changes, at most every THROTTLE seconds, only when changed; forced
-- (full) when the group changes.
-------------------------------------------------------------------------------
function P:On()
  return Panoply.db and Panoply.db.qpParty ~= false and Panoply.db.partyShare ~= false and QP.active and true or false
end

-- 0.9.7: the engine's party members when its party sync is the one running, else nil (our own messages are then the source).
function P:Engine()
  local PP = Panoply.PolestarParty
  if not (PP and PP.Enabled and PP:Enabled()) then return nil end
  return PP:Members()
end
-- the engine's party progress changed (Engine/PolestarParty.lua hears its message)
function P:EngineChanged()
  self.version = self.version + 1
  Panoply:Fire("QUEST_PARTY_CHANGED")
end

function P:Send(force)
  if not self:On() then return false, "off" end
  if self:Engine() then return false, "engine" end   -- 0.9.7: the engine already tells the party
  if not C.InGroup() then return false, "solo" end
  local s = self:Summary()
  if not force and s == self.lastSent then self.stats.same = self.stats.same + 1 return false, "same" end
  local now = C.GetTime()
  if self.lastTime and now - self.lastTime < self.THROTTLE then
    self.forcePending = self.forcePending or force
    self.stats.throttled = self.stats.throttled + 1
    if not self.pending then
      self.pending = true
      C.After(self.THROTTLE - (now - self.lastTime) + 0.05, function()
        self.pending = nil
        local f = self.forcePending
        self.forcePending = nil
        self:Send(f)
      end)
    end
    return false, "throttled"
  end
  if not (Panoply.Sync and Panoply.Sync:Queue("Q", { v = self.VERSION, s = s })) then return false, "sync off" end
  self.lastTime, self.lastSent = now, s
  self.stats.sent = self.stats.sent + 1
  return true
end

-------------------------------------------------------------------------------
-- Receiving: only from people in your party right now; malformed messages are dropped.
-------------------------------------------------------------------------------
function P:Present()
  local set = {}
  for _, n in ipairs(C.GroupMembers()) do set[shortName(n)] = true end
  return set
end

function P:OnData(who, p)
  who = shortName(who)
  if not who then return false end
  if not self:Present()[who] then self.stats.stranger = self.stats.stranger + 1 return false end
  local data = type(p) == "table" and tonumber(p.v) == self.VERSION and P.Decode(p.s)
  if not data then self.stats.malformed = self.stats.malformed + 1 return false end
  self.members[who] = { quests = data, seen = C.GetTime() }
  self.stats.received = self.stats.received + 1
  self.version = self.version + 1
  Panoply:Fire("QUEST_PARTY_CHANGED", who)   -- 0.7.1: the tracker listened for this, nothing sent it
  return true
end

-- Forget people who left; a full send to whoever joined.
function P:RosterChanged()
  local present = self:Present()
  local changed = false
  for name in pairs(self.members) do if not present[name] then self.members[name] = nil changed = true end end
  if changed then self.version = self.version + 1 Panoply:Fire("QUEST_PARTY_CHANGED") end
  if C.InGroup() then self:Send(true) else self.lastSent = nil end
end

-- 0.7.1: who in your party has a quest, structured: { { name, has, ready, obj = { {n, of}, ... } } },
-- sorted by name; only people in your party right now who sent their progress.
function P:Who(qid)
  local out = {}
  if not self:On() then return out end
  local engine = self:Engine()
  if engine then
    -- 0.9.7: a member's quest as the engine keeps it: its counts in the quest log's order ({} for a quest without counts)
    for _, m in ipairs(engine) do
      local counts = type(m.quests) == "table" and m.quests[qid] or nil
      local obj, ready = {}, false
      if type(counts) == "table" then
        ready = #counts > 0
        for j, c in ipairs(counts) do
          obj[j] = { tonumber(c[1]) or 0, tonumber(c[2]) or 0 }
          if obj[j][1] < obj[j][2] then ready = false end
        end
      end
      out[#out + 1] = { name = m.name, has = counts ~= nil, ready = ready, obj = obj }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end
  local present = self:Present()
  for name, m in pairs(self.members) do
    if present[name] then
      local e = m.quests[qid]
      out[#out + 1] = { name = name, has = e ~= nil, ready = e and e.ready or false, obj = e and e.obj or {} }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- How many party members have the quest (and how many sent their progress at all).
function P:HaveCount(qid)
  local n, of = 0, 0
  for _, w in ipairs(self:Who(qid)) do of = of + 1 if w.has then n = n + 1 end end
  return n, of
end

-- Lines for a quest: { { "Alice: 3/10", r, g, b, kind } }. objIdx = one objective, nil = all.
-- kind (0.7.1): "missing" (doesn't have it), "ready" or "progress", so a list can dim the first.
function P:Lines(qid, objIdx)
  local out = {}
  for _, w in ipairs(self:Who(qid)) do
    local name, e = w.name, w
    if not e.has then local c = Panoply.Skin.RGB("qpTipDim") out[#out + 1] = { name .. ": doesn't have it", c[1], c[2], c[3], "missing" }
    elseif e.ready then local c = Panoply.Skin.RGB("qpTipReady") out[#out + 1] = { name .. ": done", c[1], c[2], c[3], "ready" }
    else
      local t = {}
      if objIdx and e.obj[objIdx] then t[1] = e.obj[objIdx][1] .. "/" .. e.obj[objIdx][2]
      else for j, o in ipairs(e.obj) do t[j] = o[1] .. "/" .. o[2] end end
      local allDone = objIdx and e.obj[objIdx] and e.obj[objIdx][1] >= e.obj[objIdx][2]
      local c = Panoply.Skin.RGB(allDone and "qpTipReady" or "qpTipText") out[#out + 1] = { name .. ": " .. (#t > 0 and table.concat(t, ", ") or "on it"), c[1], c[2], c[3], "progress" }
    end
  end
  return out
end

if Panoply.Sync then
  Panoply.Sync.openKinds = Panoply.Sync.openKinds or {}
  Panoply.Sync.openKinds.Q = true   -- every party member's progress, not only the sync partner's
  Panoply.Sync.handlers.Q = function(who, p) if P:On() then P:OnData(who, p) end end
end
-- P:On() decides (the setting and Quest icons on).
Panoply:On("QUEST_LOG_UPDATE", function() if P:On() then C.After(0.4, function() P:Send(false) end) end end)
Panoply:On("GROUP_ROSTER_UPDATE", function() if P:On() then C.After(1, function() P:RosterChanged() end) end end)
