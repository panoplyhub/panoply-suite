-- Map module, FIND ANYTHING (0.8.4): more things the Go to window's search can find, beside the places it already lists (Navigate.lua):
--   * quests, by name: where the quest starts;
--   * creatures, by name: the nearest place one stands (service NPCs and rare creatures are places already and are not listed twice);
--   * items, by name: the nearest place it drops, is found or is sold;
--   * dungeon and raid bosses, by name: the door of their dungeon;
--   * the kinds of gathering spot ("Treasure chest", "Herb", "Ore vein", "Fishing pool"): the nearest one known in your zone.
-- Every one of them comes from Panoply Suite's own tables (QuestData's quest, NPC and item records, the instance atlas, the Gathering
-- module); nothing is typed in here. A thing with no known position is not listed: a result can always be shown on the map.
--
-- How it meets the places: N:Search asks F:Search. The places are ranked by Navigate (N.RankHits); from three letters on, the names
-- here are matched (starts with the text, a word starts with it, the text is inside) and merged in by the same order, each kind with
-- its own standing (F.PROM, under towns, dungeons, zones and the "nearest" entries). When the text names a kind of place ("inn",
-- "paladin trainer", "mailbox") the places come first and the rest after them; otherwise neither the places nor the rest can fill
-- the list alone (F.KEEP_EACH). Only the few results that will be shown are worked out fully (their position looked up), so typing
-- stays quick with some thirteen thousand names.
-- 0.9.6: a text that names a town or zone ("goldshire") lists that town's places before the quests that only mention it (classOf in
-- F:Search); the towns, inns and landmarks themselves are places of Navigate (Maps/Landmarks.lua).
-- "Show on the map" (the row's right-click menu) opens the world map on the place's zone and rings the spot (F:Mark).
-- No automatic movement (hub rule 2 of CLAUDE.md): this file lists and marks; the arrow shows the way and the player walks.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local Nav = Panoply.Nav
local max = math.max

local F = {}
M.Find = F
F.MIN_CHARS = 3                 -- shorter text finds places only
F.SCAN_CAP = 40                 -- at most this many candidates are looked up for one search
F.MARK_PX = 30
-- how well known a kind is among names that match the same way (Navigate's N.PROMINENCE: city 100 ... type 60, flight 50, npc 30)
F.PROM = { boss = 45, gather = 44, quest = 26, creature = 22, item = 18 }
F.KINDS = { "boss", "gather", "quest", "creature", "item" }

local function mapName(id)
  local n = C.MapName and C.MapName(id)
  return (n and n ~= "") and n or nil
end

-- the name of a record: the text before the first "|" of the data add-on's raw line, or the decoded record's name
local function recordName(raw, get, id)
  local r = type(raw) == "table" and raw[id]
  if type(r) == "string" then
    local n = r:match("^([^|]*)")
    return n ~= "" and n or nil
  end
  if type(get) == "function" then
    local ok, rec = pcall(get, id)
    if ok and type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then return rec.name end
  end
  return nil
end

-------------------------------------------------------------------------------
-- The names: one list for each kind, built once from the tables in use ({ names = normalised, shown = as written, ids })
-------------------------------------------------------------------------------
function F:Sources()
  local QD = Panoply.QuestData
  local own = QD and QD.own
  local P = M.Places
  local idx = P and P.Index() or nil
  if self.sources and self.sourcesOf == own and self.sourcesIdx == idx then return self.sources end
  local N = M.Navigate
  local src = {}
  for _, k in ipairs(F.KINDS) do src[k] = { names = {}, shown = {}, ids = {} } end
  local function put(kind, name, id)
    local n = N.Normalise(name)
    if n == "" then return end
    local s = src[kind]
    local i = #s.names + 1
    s.names[i], s.shown[i], s.ids[i] = n, name, id
  end
  if own then
    -- quests (hidden ones are never routed and never listed)
    for id in QD:EachQuestId() do
      if not (QD.hidden and QD.hidden[id]) then
        local name = recordName(own.Q, own.Quest, id)
        if name then put("quest", name, id) end
      end
    end
    -- creatures that are not places already (0.9.6: nor the other side's innkeepers, bankers and trainers: not a place for you)
    local placed = {}
    for _, list in pairs(idx and idx.byType or {}) do
      for _, e in ipairs(list) do if e.id then placed[e.id] = true end end
    end
    for id in pairs(idx and idx.otherSide or {}) do placed[id] = true end
    local okN, ids = pcall(own.NpcIds or function() return {} end)
    for _, id in ipairs(okN and type(ids) == "table" and ids or {}) do
      if type(id) == "number" and not placed[id] then
        local name = recordName(own.N, own.Npc, id)
        if name then put("creature", name, id) end
      end
    end
    -- items
    if type(own.I) == "table" then
      for id in pairs(own.I) do
        if type(id) == "number" then
          local name = recordName(own.I, own.Item, id)
          if name then put("item", name, id) end
        end
      end
    end
  end
  -- bosses: the instance atlas (each boss once; its id is "instance index:boss index")
  local d = M.Data and M.Data()
  for i, inst in ipairs(d and d.instances or {}) do
    for j, b in ipairs(type(inst.bosses) == "table" and inst.bosses or {}) do
      if type(b) == "table" and type(b[1]) == "string" then put("boss", b[1], i * 1000 + j) end
    end
  end
  -- the kinds of gathering spot
  local G = Panoply.Gathering
  if G and G.TYPES then
    for i, t in ipairs(G.TYPES) do put("gather", F.GATHER_NAME[t] or t, i) end
  end
  self.sources, self.sourcesOf, self.sourcesIdx = src, own, idx
  return src
end

F.GATHER_NAME = { herb = "Herb", ore = "Ore vein", fish = "Fishing pool", chest = "Treasure chest" }

-- candidates for a normalised text: { { kind, id, name, class, prom } ... }, best first, at most F.SCAN_CAP
function F:Hits(q)
  local hits = {}
  if q == "" then return hits end
  local sp = " " .. q
  local n = #q
  for _, kind in ipairs(F.KINDS) do
    local s = self:Sources()[kind]
    local prom = F.PROM[kind] or 0
    for i, name in ipairs(s.names) do
      local class
      if name:sub(1, n) == q then class = 0
      elseif name:find(sp, 1, true) then class = 1
      elseif name:find(q, 1, true) then class = 2 end
      if class then hits[#hits + 1] = { kind = kind, id = s.ids[i], name = s.shown[i], class = class, prom = prom } end
    end
  end
  table.sort(hits, F.Before)
  for i = #hits, F.SCAN_CAP + 1, -1 do hits[i] = nil end
  return hits
end

-- the order of N.Rank: how the name matches, then the better-known kind, then the shorter name, then the name
function F.Before(a, b)
  if a.class ~= b.class then return a.class < b.class end
  if a.prom ~= b.prom then return a.prom > b.prom end
  local la, lb = #a.name, #b.name
  if la ~= lb then return la < lb end
  if a.name ~= b.name then return a.name < b.name end
  if (a.seq or 0) ~= (b.seq or 0) then return (a.seq or 0) < (b.seq or 0) end
  return tostring(a.id or "") < tostring(b.id or "")
end

-------------------------------------------------------------------------------
-- From a candidate to a destination ({ kind, name, sub, map, x, y }), or nil when it has no known position
-------------------------------------------------------------------------------
-- the spot of a list nearest to the player (by distance when both are on one continent), else the first
local function nearest(spots)
  local pm, px, py = C.GetPlayerPos()
  local best, bestD
  for _, s in ipairs(spots or {}) do
    if s.map and s.x and s.y then
      local d = pm and Nav and Nav.Distance(pm, px, py, s.map, s.x, s.y)
      if d and (not bestD or d < bestD) then best, bestD = s, d end
    end
  end
  if best then return best end
  for _, s in ipairs(spots or {}) do if s.map and s.x and s.y then return s end end
  return nil
end
F.NearestSpot = nearest

local function zoneOf(s) return mapName(s.map) or "an unnamed zone" end

-- is this quest open to the player's race? (a quest of the other side is not listed)
local function questForMe(q)
  local QD = Panoply.QuestData
  local races = tonumber(q.races) or 0
  if races == 0 then return true end
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  local mask = info.raceID and QD.RaceMask and QD:RaceMask(info.raceID) or 0
  if mask <= 0 then return true end                       -- a race the data does not know: nothing is hidden from it
  return races % (mask * 2) >= mask
end

F.MAKE = {}
function F.MAKE.quest(h)
  local QD = Panoply.QuestData
  local q = QD:GetQuest(h.id)
  if not q or not questForMe(q) then return nil end
  local s = nearest(QD:GiverSpots(q))
  if not s then return nil end
  return { kind = "quest", name = q.name, sub = ("Quest, level %d - %s"):format(q.level or 0, zoneOf(s)), map = s.map, x = s.x, y = s.y }
end
function F.MAKE.creature(h)
  local QD = Panoply.QuestData
  local s = nearest(QD:NpcSpots(h.id))
  if not s then return nil end
  local lo, hi = QD:NpcLevel(h.id)
  local level = M.Extras and M.Extras.LevelText(lo, hi)
  return { kind = "creature", name = h.name, sub = ("Creature%s - %s"):format(level and (", " .. level:lower()) or "", zoneOf(s)), map = s.map, x = s.x, y = s.y }
end
function F.MAKE.item(h)
  local QD = Panoply.QuestData
  local s = nearest(QD:ItemSpots(h.id))
  if not s then return nil end
  return { kind = "item", name = h.name, sub = ("Item, %s - %s"):format(s.vendor and "sold" or "found", zoneOf(s)), map = s.map, x = s.x, y = s.y }
end
function F.MAKE.boss(h)
  local d = M.Data and M.Data()
  local inst = d and d.instances and d.instances[math.floor(h.id / 1000)]
  if not inst then return nil end
  for _, door in ipairs(inst.doors or {}) do
    if door[7] == 0 and door[4] and door[5] and door[6] then
      return { kind = "boss", name = h.name, sub = ("Boss - %s"):format(inst.name),
        map = door[4], x = door[5], y = door[6] }
    end
  end
  return nil
end
function F.MAKE.gather(h)
  local G = Panoply.Gathering
  local t = G and G.TYPES and G.TYPES[h.id]
  if not (t and G.active and G.Nearest) then return nil end
  local pm, px, py = C.GetPlayerPos()
  if not pm then return nil end
  local n = G:Nearest(t, { map = pm, x = px, y = py }, pm)
  if not n then return nil end
  return { kind = "gather", name = h.name, sub = ("Nearest known - %s"):format(mapName(pm) or "your zone"),
    map = pm, x = n[3], y = n[4] }
end

function F:Make(h)
  local fn = F.MAKE[h.kind]
  if not fn then return nil end
  local ok, d = pcall(fn, h)
  if not ok then Panoply:Debug("find", h.kind, h.id, d) return nil end
  return d
end

-------------------------------------------------------------------------------
-- The search: the places, and from three letters on everything else, in one order
-------------------------------------------------------------------------------
F.KEEP_OTHERS = 2               -- when the text names a kind of place: this many rows stay for quests and the rest, after the places
F.KEEP_EACH = 3                 -- otherwise: at least this many places and this many of the rest, when there are that many

function F:Search(dests, query, limit)
  local N = M.Navigate
  limit = limit or N.MAX_RESULTS
  local hits, info = N.RankHits(dests, query, limit)
  local q = info.q
  local places, out, seen = {}, {}, {}
  for i, h in ipairs(hits) do
    local d = h.d
    places[i] = { dest = d, place = true, name = d.name, class = h.class, prom = h.prom, seq = i }
    seen[tostring(d.kind) .. "|" .. tostring(d.name) .. "|" .. tostring(d.map) .. "|" .. tostring(d.type)] = true
  end
  if #q < F.MIN_CHARS then
    for i, h in ipairs(places) do out[i] = h.dest end
    return out
  end
  -- the rest: quests, creatures, items, bosses, gathering spots; only as many as could be shown are worked out
  local others = {}
  local np = #places
  for _, h in ipairs(self:Hits(q)) do
    if #others >= limit then break end
    local d = self:Make(h)
    if d then
      local key = tostring(d.kind) .. "|" .. tostring(d.name) .. "|" .. tostring(d.map) .. "|" .. tostring(d.type)
      if not seen[key] then
        seen[key] = true
        h.dest, h.seq = d, np + #others + 1
        others[#others + 1] = h
      end
    end
  end
  if info.typed then
    -- the text names a kind of place ("inn", "paladin trainer", "mailbox"): the places first, then the rest
    local keep = math.min(#others, F.KEEP_OTHERS, math.floor(limit / 4))   -- a short list (the first hit alone) is places only
    local n = math.min(np, limit - keep)
    for i = 1, n do out[#out + 1] = places[i].dest end
    for i = 1, math.min(#others, limit - n) do out[#out + 1] = others[i].dest end
    return out
  end
  -- one order for all of them (each list keeps its own order); neither the places nor the rest can fill the list alone.
  -- 0.9.6: when the text names a town or zone ("goldshire"), the places in it (found by where they are) rank as names with a word
  -- starting with the text, and so before a quest that only has the town in its name ("Report to Goldshire")
  local function classOf(h) return (h.place and info.where and h.class >= 3) and 1 or h.class end
  local all = {}
  local ip, io = 1, 1
  while places[ip] or others[io] do
    local a, b = places[ip], others[io]
    local place
    if not b then place = true
    elseif not a then place = false
    elseif classOf(a) ~= b.class then place = classOf(a) < b.class
    elseif a.prom ~= b.prom then place = a.prom > b.prom
    else place = not F.Before(b, a) end
    if place then all[#all + 1] = a ip = ip + 1 else all[#all + 1] = b io = io + 1 end
  end
  local needO = math.min(F.KEEP_EACH, #others, math.floor(limit / 2))
  local needP = math.min(F.KEEP_EACH, np, limit - needO)
  local gotP, gotO = 0, 0
  for _, h in ipairs(all) do
    if #out >= limit then break end
    local owed = h.place and max(0, needO - gotO) or max(0, needP - gotP)
    if limit - #out > owed then
      out[#out + 1] = h.dest
      if h.place then gotP = gotP + 1 else gotO = gotO + 1 end
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- "Show on the map": a ring round the spot on the world map, until the map is closed or another place is shown
-------------------------------------------------------------------------------
function F:Mark(r)
  self.mark = (type(r) == "table" and r.map and r.x and r.y) and { map = r.map, x = r.x, y = r.y, label = r.label } or nil
  if not self.hideHooked then
    local wm = C.WorldMap()
    if wm and wm.HookScript then
      self.hideHooked = true
      wm:HookScript("OnHide", function() F.mark = nil if F.ring then F.ring:Hide() end end)
    end
  end
  return self:Refresh("mark")
end

function F:Refresh(why)
  local r = self.mark
  local wm, map = C.WorldMap(), C.WorldMapID()
  local canvas = C.WorldMapCanvas()
  if not (M.active and r and canvas and wm and wm.IsShown and wm:IsShown() and map == r.map) then
    if self.ring then self.ring:Hide() end
    return false
  end
  local f = self.ring
  if not f then
    f = CreateFrame("Frame", nil, canvas)
    f.panoplyLayoutSkip = true
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints(f)
    f.tex:SetTexture(Skin.TEX.GatherRing)
    local a = Skin.colors.accent
    f.tex:SetVertexColor(a[1], a[2], a[3], 1)
    self.ring = f
  end
  if f:GetParent() ~= canvas and f.SetParent then f:SetParent(canvas) end
  local W, H = canvas:GetWidth() or 1002, canvas:GetHeight() or 668
  local Tr = Panoply.Trail
  local cs = Tr and Tr.CanvasScale and Tr:CanvasScale(canvas) or 1
  local px = F.MARK_PX / max(0.2, cs)
  f:SetSize(px, px)
  f:ClearAllPoints()
  f:SetPoint("CENTER", canvas, "TOPLEFT", r.x * W, -r.y * H)
  if f.SetFrameLevel then f:SetFrameLevel(M:MarkLevel(M:IconLevel())) end
  f:Show()
  return true
end

function F:Disable()
  self.mark = nil
  if self.ring then self.ring:Hide() end
end
