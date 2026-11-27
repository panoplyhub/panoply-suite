-- Map module, GO TO: type a place, get suggestions as you type, and the arrow takes you there. Feels like a map app's search; looks like
-- Panoply Suite (the same slate window, buttons and words as the rest). Free in the base add-on; no Hub needed.
--
--   * Search: every town and zone, every dungeon and raid, each kind of place (the nearest one to you: "Auction house", "Innkeeper"...), every
--     flight master, and every trainer, service and vendor NPC in the data. Ranked by N.Rank: a name that STARTS with what you typed comes
--     before one that merely has a word starting with it, before one that only contains it; within each, the better-known kind first (towns,
--     then dungeons and raids, then zones, then the nearest-of-a-kind entries, then flight masters, then single NPCs); then the shorter name.
--     So "st" gives Stormwind City first and Stratholme second.
--   * Going: the route engine does the walking, riding, boats, zeppelins and known flights. A destination becomes the FIRST waypoint (the one
--     the arrow follows, Waypoints module) and every waypoint you had stays behind it as a later stop. Nothing is cleared or lost.
--   * Stops: add stops before or during a trip, move them up and down, remove them. The stops ARE the waypoint list (one list, so the
--     Waypoints window, /way and this window always agree).
--   * Favourites and Recents: places you saved and the last ones you went to. Home: one place you chose, or, until you choose one, the inn
--     your hearthstone is bound to (when the route data knows it). All of these are saved with the character (Panoply.cdb: placesFav,
--     placesHome, placesRecent) and are never touched by a settings reset.
--   * 0.8.4: WoW Forever's new zones, the named areas inside them and its new dungeons are destinations too (PanoplySuite_RouteData's
--     RD.places, from the client's own tables). A new dungeon has no charted door yet: it leads to the area that carries its name and
--     says so. A trip you picked here is planned by the route engine even where there is no written guide (Engine/Route.lua
--     HandPicked), and its turn-by-turn words ("Take the boat to...", "Take the flight at...") head this window's list and are said
--     in chat as each part of the trip comes up (N:Trip, N:Announce; the words are Engine/Travel.lua's).
--   * 0.8.4: a search may be several words, and a place is found by its name, its kind and where it is, in any order: "goldshire inn",
--     "paladin trainer goldshire", "flight master stormwind", "mailbox elwynn". Every word must be the start of a word of the place's
--     name or title, of its kind (M.PLACE_TYPES: dest, alias, label) or of its zone or town. The town is the named point of the route
--     data the place stands at (N:Towns: inn and bind names, named road points, flight point names, Forever's named areas); no
--     coordinate is typed in here. Mailboxes, anvils, forges and camp sites have no name of their own: they are listed once for each
--     town or zone ("Mailbox - Goldshire, Elwynn Forest"). When the text names a kind of place, the places come first, the nearest
--     first (Find.lua). Class trainers: the class the text names, else your own class unless "Show all classes" is on.
--   * 0.9.6 (Nov 16 2026: "Why can I not find the Goldshire Inn? Many spots are like this."): towns are destinations of their own
--     ("Goldshire - Town in Elwynn Forest"), and so are inns by their own names ("Lion's Pride Inn") and the named places a city guard
--     points to ("Stormwind Bank", "The Great Forge", "Deeprun Tram"). They come from PanoplySuite_QuestData/Maps/Landmarks.lua
--     (tools/build_landmarks.py: the client's own AreaPOI town labels, and VMaNGOS's guard points of interest and inn rest areas). The
--     towns are also the "where" words of every place, so a search by town works when the route data is not loaded (WoW Forever with
--     PanoplyGuide's guide: Route:Data() is nil there on purpose, and before this every place lost its town). A text that names a town or
--     zone lists that town's places before the quests that merely mention it (Find.lua).
-- No automatic movement (hub rule 2 of CLAUDE.md): this file moves nothing, targets nothing, casts nothing. It adds waypoints; the arrow
-- shows the way and the player walks.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local Nav = Panoply.Nav
local floor, max, min = math.floor, math.max, math.min

local N = {}
M.Navigate = N
N.MAX_RESULTS = 8
N.MAX_RECENT = 8
N.MAX_FAV = 50
-- how well known a kind of place is: higher comes first among names that match the same way
N.PROMINENCE = { city = 100, saved = 90, instance = 80, town = 75, zone = 70, area = 65, type = 60, flight = 50, npc = 30, place = 30,
  landmark = 28, town_kindText = 20 }   -- saved: the player's own spots (Spots.lua); town, landmark: 0.9.6 (Maps/Landmarks.lua)
-- the second line of a landmark's row, by its kind in the data ("Inn - Goldshire, Elwynn Forest")
N.LANDMARK_LABEL = { placeInn = "Inn", placeBank = "Bank", placeAuction = "Auction house", placeMail = "Mailbox", flight = "Flight master",
  travel = "Tram and zeppelin", trainer = "Trainers", landmark = "Landmark" }
N.TOWN_YARDS = 250              -- a place this close to a named point of the route data is "in" that town
-- words that say nothing in a search ("the inn in goldshire", "nearest mailbox")
N.STOP = { ["in"] = true, at = true, the = true, of = true, near = true, nearest = true, closest = true, to = true, a = true, an = true }
-- words of a kind's name that do not name the kind on their own ("house" of "Auction house", "master" of "Flight master")
N.TYPE_GENERIC = { ["and"] = true, house = true, houses = true, master = true, masters = true, creature = true, creatures = true, site = true,
  sites = true, goods = true, fire = true, spawn = true, supplies = true, box = true, path = true }
N.FLIGHT_WORDS = "Flight master flight flightmaster flight path taxi"
-- among the places found only by where they are ("goldshire"), what a traveller looks for first; the other kinds follow in one group
N.WHERE_ORDER = { placeInn = 1, flight = 2, placeMail = 3, placeBank = 4, placeAuction = 5, placeTrainClass = 6, placeRepair = 7 }
N.WHERE_LAST = 20
N.WHERE_KINDS = { city = true, town = true, zone = true, area = true }   -- the kinds of destination a text can name as "where"

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- lower case, letters and digits and single spaces only ("Rut'theran Village" -> "rut theran village")
function N.Normalise(s)
  s = tostring(s or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " ")
  return trim(s)
end

-- 0: the name starts with the text; 1: a word of the name starts with it; 2: the text is somewhere inside; nil: no match
function N.MatchClass(name, q)
  local n = N.Normalise(name)
  if q == "" or n == "" then return nil end
  if n:sub(1, #q) == q then return 0 end
  if n:find(" " .. q, 1, true) then return 1 end
  if n:find(q, 1, true) then return 2 end
  return nil
end

-- every word a kind of place is called by: word -> { place key = true } (M.PLACE_TYPES' dest, alias and label, and the flight masters)
function N.TypeWords()
  if N.typeWords then return N.typeWords end
  local words = {}
  local function eat(text, key)
    for w in N.Normalise(text):gmatch("%S+") do
      if not N.TYPE_GENERIC[w] and not N.STOP[w] then
        words[w] = words[w] or {}
        words[w][key] = true
      end
    end
  end
  for _, t in ipairs(M.PLACE_TYPES or {}) do
    eat(t.dest, t.key) eat(t.alias, t.key) eat(t.label, t.key)
  end
  eat(N.FLIGHT_WORDS, "flight")
  N.typeWords = words
  return words
end

-- the words a place of a kind is found by ("Innkeeper inn Innkeepers")
function N.TypeText(key)
  if key == "flight" then return N.FLIGHT_WORDS end
  local t = M.PLACE_BY_KEY and M.PLACE_BY_KEY[key]
  if not t then return "" end
  return t.dest .. " " .. (t.alias or "") .. " " .. (t.label or "")
end

-- What was typed, taken apart: { q = normalised text, tokens = its words without the filler ones, typed = it names a kind of place,
-- typeTok = { the words of it that do = true }, types = { place key = true }, classes = { class word = true } or nil when no class
-- is named }
function N.Query(query)
  local q = N.Normalise(query)
  local info = { q = q, tokens = {}, types = {}, typeTok = {} }
  local all = {}
  for w in q:gmatch("%S+") do all[#all + 1] = w end
  for _, w in ipairs(all) do if not N.STOP[w] then info.tokens[#info.tokens + 1] = w end end
  if #info.tokens == 0 then info.tokens = all end
  local tw = N.TypeWords()
  local P = M.Places
  local classWords = P and P.ClassWords and P.ClassWords() or {}
  for _, t in ipairs(info.tokens) do
    local n = #t
    for word, keys in pairs(tw) do
      if word == t or (n >= 3 and word:sub(1, n) == t) then
        info.typed = true
        info.typeTok[t] = true
        for k in pairs(keys) do info.types[k] = true end
      end
    end
    if n >= 3 then
      for _, cw in ipairs(classWords) do
        for w in cw:gmatch("%S+") do
          if w:sub(1, n) == t then
            info.classes = info.classes or {}
            info.classes[cw] = true
          end
        end
      end
    end
  end
  -- 0.9.6: every word of the text names a kind of place ("anvil", "mailbox")
  info.onlyKind = info.typed and #info.tokens > 0 or nil
  for _, t in ipairs(info.tokens) do if not info.typeTok[t] then info.onlyKind = nil end end
  return info
end

-- the words a destination is found by: what it is (its names, keys, and its kind, tw) and where it is (ww), as two lists
local function wordsOf(d)
  if d.wl then return d.wl, d.wwl end
  local function list(texts)
    local out, seen = {}, {}
    for i = 1, 6 do
      local text = texts[i]
      if text then
        for w in N.Normalise(text):gmatch("%S+") do
          if not seen[w] then seen[w] = true out[#out + 1] = w end
        end
      end
    end
    return out
  end
  local keys = d.keys or { d.name }
  d.wl = list({ keys[1], keys[2], keys[3], keys[4], d.tw })
  d.wwl = list({ d.ww })
  return d.wl, d.wwl
end

local function startsAny(words, t)
  local n = #t
  for _, w in ipairs(words) do
    if w:sub(1, n) == t then return true end
  end
  return false
end

-- a class trainer is listed when it is of a class the text names; with no class named, when it is the player's own (or "Show all
-- classes" is on); and always when the text is its own name
function N.ClassOK(d, info)
  if not d.classWord then return true end
  -- its own name: any match for a person; for a guard's landmark (0.9.6) the name has to start with the text, since "Ironforge
  -- Rogue Trainer" holds the word "trainer" itself
  local own = N.MatchClass(d.name, info.q)
  if own and (d.kind ~= "landmark" or own == 0) then return true end
  if info.classes then return info.classes[d.classWord] == true end
  if Panoply.db and Panoply.db.placeClassAll then return true end
  local P = M.Places
  if not (P and P.IsMyClass) then return true end
  return P.IsMyClass({ type = "placeTrainClass", classWord = d.classWord })
end

-- How a destination matches: 0, 1, 2 as N.MatchClass for the whole text against one of its names. Else word by word: every word
-- typed must start a word of what it is or of where it is ("goldshire inn"): 3 when a word says what it is, 4 when the words only say
-- where ("goldshire": everything in Goldshire). When the text names a kind of place, one of those words must be of this place's own
-- name or kind: a smith in a town with "Inn" in a street's name is not an inn. nil: no match.
function N.Match(d, info)
  if not N.ClassOK(d, info) then return nil end
  local q = info.q
  local best
  local keys = d.keys or { d.name }
  for i = 1, 4 do
    local key = keys[i]
    if key then
      local c = N.MatchClass(key, q)
      if c and (not best or c < best) then best = c end
    end
  end
  -- 0.9.6: a text that names a kind of place ("inn") is not found in the middle of a word ("Skinning Trainer"): only a name that
  -- starts with it, or has a word that does, or the word by word match below
  if best == 2 and info.typed then best = nil end
  if best then return best end
  if #info.tokens == 0 then return nil end
  local what, where = wordsOf(d)
  local nWhat, kindNamed = 0, false
  for _, t in ipairs(info.tokens) do
    if startsAny(what, t) then
      nWhat = nWhat + 1
      if info.typeTok[t] then kindNamed = true end
    elseif not startsAny(where, t) then
      return nil
    end
  end
  if info.typed and not kindNamed then return nil end
  return nWhat > 0 and 3 or 4
end

-- yards from the player to a destination (a far number when it is on another continent or has no spot)
local function yardsTo(d)
  if not (d.map and d.x and d.y) then return math.huge end
  local pm, px, py = C.GetPlayerPos()
  local dist = pm and Nav and Nav.Distance(pm, px, py, d.map, d.x, d.y)
  return dist or math.huge
end

-- dests: { { name, kind, keys = { more words that match }, prom = optional override } ... }; the best `limit` for the text, best first,
-- as { d, class, prom, seq } records. When the text names a kind of place, the nearer of two equal places comes first.
function N.RankHits(dests, query, limit)
  local info = type(query) == "table" and query or N.Query(query)
  local hits = {}
  if info.q == "" then return hits, info end
  for i, d in ipairs(dests) do
    local class = N.Match(d, info)
    -- the player's own saved spot (Spots.lua) is never crowded out by the data's places: found by a word of its name, it ranks with
    -- the names that start with the text (found only by its zone, it stays with the other places of that zone)
    if class and d.kind == "saved" and class < 4 then class = 0 end
    -- 0.9.6: the text names a town, a zone or an area by the start of its name ("goldshire"): Find.lua lists the places in it before
    -- the quests that merely mention it
    if class == 0 and N.WHERE_KINDS[d.kind] then info.where = true end
    -- 0.9.6: a text made only of a kind's words ("anvil", "camp") asks for that kind: a town whose name starts the same way
    -- (Anvilmar, Camp Narache) comes after the places of the kind
    local prom = d.prom or N.PROMINENCE[d.kind] or 0
    if class and info.onlyKind and d.kind == "town" then prom = N.PROMINENCE.town_kindText end
    if class then
      hits[#hits + 1] = { d = d, class = class, prom = prom, seq = i,
        dist = info.typed and yardsTo(d) or 0,
        ord = class == 4 and (d.kind == "saved" and 0 or N.WHERE_ORDER[d.ptype or ""] or N.WHERE_LAST) or 0 }   -- your own spots lead a zone's places
    end
  end
  table.sort(hits, function(a, b)
    if a.class ~= b.class then return a.class < b.class end
    if a.ord ~= b.ord then return a.ord < b.ord end
    if a.prom ~= b.prom then return a.prom > b.prom end
    if a.dist ~= b.dist then return a.dist < b.dist end
    local la, lb = #a.d.name, #b.d.name
    if la ~= lb then return la < lb end
    if a.d.name ~= b.d.name then return a.d.name < b.d.name end
    return a.seq < b.seq
  end)
  for i = #hits, (limit or N.MAX_RESULTS) + 1, -1 do hits[i] = nil end
  return hits, info
end

function N.Rank(dests, query, limit)
  local out = {}
  for i, h in ipairs(N.RankHits(dests, query, limit)) do out[i] = h.d end
  return out
end

-------------------------------------------------------------------------------
-- Every place you can go to
-------------------------------------------------------------------------------
local function mapName(id)
  local n = C.MapName and C.MapName(id)
  return (n and n ~= "") and n or nil
end

-- town and zone maps (the continents are not destinations: a whole continent is no place to walk to)
function N:ZoneIds()
  local d = M.Data()
  local out, seen = {}, {}
  for _, list in pairs(d and d.zones or {}) do
    for _, id in ipairs(list) do if not seen[id] then seen[id] = true out[#out + 1] = id end end
  end
  if #out == 0 then for id = 1411, 1458 do out[#out + 1] = id end end
  table.sort(out)
  return out
end

-- 0.8.4: the route data's named places (WoW Forever: new zones, the battleground, areas inside the new zones, new dungeons); nil on Era
function N:RoutePlaces()
  local R = Panoply.Route
  local RD = R and R.Data and R:Data()
  return RD and RD.places or nil
end

-- The named points of the route data, by map: { [uiMap] = { { name, wx, wy } ... } } (world yards). They are the inns' bind names, the
-- named points of the road graph, the flight points' towns and WoW Forever's named areas: all of them data Panoply Suite already
-- routes with. A name that is a whole zone's is left out (the zone is searched by the map's own name).
function N:Towns()
  local R = Panoply.Route
  local RD = R and R.Data and R:Data()
  local L = self:Landmarks()
  if self.towns and self.townsOf == RD and self.townsL == L then return self.towns end
  local byMap = {}
  self.towns, self.townsOf, self.townsL = byMap, RD, L
  local zoneNames = {}
  for _, id in ipairs(self:ZoneIds()) do
    local n = mapName(id)
    if n then zoneNames[N.Normalise(n)] = true end
  end
  -- 0.9.6: the game's own town labels (Maps/Landmarks.lua), kept on their map (x, y); they do not need the route data
  for _, t in ipairs(L.towns) do
    if not zoneNames[N.Normalise(t.name)] then
      local l = byMap[t.map] or {}
      byMap[t.map] = l
      l[#l + 1] = { name = t.name, x = t.x, y = t.y }
    end
  end
  if type(RD) ~= "table" then return byMap end
  local function put(name, map, wx, wy)
    if type(name) ~= "string" or name == "" or type(map) ~= "number" or type(wx) ~= "number" or type(wy) ~= "number" then return end
    if zoneNames[N.Normalise(name)] then return end
    -- a point named by what it is ("the Barrens road", "the Orgrimmar inn", "the dry lake") is not a town: a name's words are capitalised
    for w in name:gmatch("%S+") do
      if w:match("^%l") and not N.STOP[w] and w ~= "and" then return end
    end
    local l = byMap[map] or {}
    byMap[map] = l
    l[#l + 1] = { name = name:sub(1, 1):upper() .. name:sub(2), wx = wx, wy = wy }
  end
  for name, id in pairs(type(RD.bind) == "table" and RD.bind or {}) do
    local i = type(RD.inns) == "table" and RD.inns[id]
    if type(i) == "table" then put(name, i[5], i[3], i[4]) end
  end
  for _, c in pairs(type(RD.roads) == "table" and RD.roads or {}) do
    local nodes = type(c) == "table" and c.nodes
    if type(nodes) == "table" then
      for i = 1, #nodes - 3, 4 do
        local label, id = nodes[i + 2], nodes[i + 3]
        if type(label) == "string" and type(id) == "string" then put(label, tonumber(id:match("^(%d+):")), nodes[i], nodes[i + 1]) end
      end
    end
  end
  for _, n in pairs(type(RD.nodes) == "table" and RD.nodes or {}) do
    if type(n) == "table" and type(n[1]) == "string" and type(n[6]) == "number" and type(n[9]) == "number" and n[9] > 0 then
      put(n[1]:match("^([^,]+)"), n[6], n[4], n[5])
    end
  end
  for _, p in ipairs(type(RD.places) == "table" and RD.places or {}) do
    if p[2] == "area" and R.ToWorld then
      local _, wx, wy = R:ToWorld(p[3], p[4], p[5])
      put(p[1], p[3], wx, wy)
    end
  end
  return byMap
end

-- the town a spot is in: the nearest named point within N.TOWN_YARDS on its map, and every name that close; nil when there is none
function N:TownOf(map, x, y)
  local list = self:Towns()[map]
  if not list then return nil end
  local R = Panoply.Route
  local wx, wy
  if R and R.ToWorld then
    local _
    _, wx, wy = R:ToWorld(map, x, y)
  end
  -- a town of the town labels is on this map (x, y): yards from the map's own size, so no world frame is needed
  local mw, mh
  if C.MapSize then mw, mh = C.MapSize(map) end
  local best, bestD, names, seen = nil, nil, {}, {}
  local lim = N.TOWN_YARDS * N.TOWN_YARDS
  for _, t in ipairs(list) do
    local dx, dy
    if t.x and mw and mh then dx, dy = (t.x - x) * mw, (t.y - y) * mh
    elseif t.wx and wx then dx, dy = t.wx - wx, t.wy - wy end
    local d2 = dx and (dx * dx + dy * dy) or math.huge
    if d2 <= lim then
      if not bestD or d2 < bestD or (d2 == bestD and t.name < best) then best, bestD = t.name, d2 end
      if not seen[t.name] then seen[t.name] = true names[#names + 1] = t.name end
    end
  end
  if not best then return nil end
  table.sort(names)
  return best, table.concat(names, " ")
end

-- the flight point's own name for a flight master ("Sentinel Hill, Westfall"), by the NPC
function N:FlightName(npc)
  if not self.flightNames then
    local R = Panoply.Route
    local RD = R and R.Data and R:Data()
    local t = {}
    for _, n in pairs(type(RD) == "table" and type(RD.nodes) == "table" and RD.nodes or {}) do
      if type(n) == "table" and type(n[1]) == "string" and type(n[9]) == "number" then t[n[9]] = n[1] end
    end
    self.flightNames, self.flightNamesOf = t, RD
  end
  return self.flightNames[npc]
end

-- 0.9.6: the names a town or landmark is found by from its first letter: as written, without the apostrophes ("lions pride" finds
-- Lion's Pride Inn) and without a leading "The" ("crossroads" finds The Crossroads before a quest that starts with the word)
function N.NameKeys(name)
  local keys = { name }
  local bare = name:gsub("'", "")
  if bare ~= name then keys[#keys + 1] = bare end
  local short = name:match("^[Tt]he%s+(.+)$")
  if short then keys[#keys + 1] = short end
  return keys
end

-- 0.9.6: the towns, WoW Forever's named spots and the landmarks of PanoplySuite_QuestData/Maps/Landmarks.lua, decoded once:
-- { towns = { { name, map, x, y } }, spots = { ... }, marks = { { name, kind, map, x, y } } }. The towns and spots are the
-- client's own tables of this game (Classic or WoW Forever); a landmark is a 1.12 server spot, re-expressed on this client's zone map
-- like every NPC spot (QuestData's SpotsFrom: on WoW Forever, "not checked" in a re-drawn zone). Landmarks of the other side (its
-- guards point to them, its innkeeper keeps the inn) are left out. Empty lists without the data file.
function N:Landmarks()
  local QD = Panoply.QuestData
  local own = (QD and QD.own) or rawget(_G, "PanoplySuiteQuestData")
  local raw = type(own) == "table" and type(own.Landmarks) == "table" and own.Landmarks or nil
  local side = QD and QD.PlayerSide and QD:PlayerSide() or "A"
  local flavor = C.Flavor and C.Flavor() == "forever" and "forever" or "era"
  local key = tostring(raw) .. side .. flavor
  if self.landmarks and self.landmarksKey == key then return self.landmarks end
  local out = { towns = {}, spots = {}, marks = {} }
  self.landmarks, self.landmarksKey = out, key
  if not raw then return out end
  local X = M.Extras
  local function rows(list, into)
    for _, r in ipairs(type(list) == "table" and list or {}) do
      local f = X and X.Split(tostring(r)) or {}
      local map, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
      if f[1] and f[1] ~= "" and map and x and y then into[#into + 1] = { name = f[1], map = map, x = x, y = y } end
    end
  end
  rows(type(raw.towns) == "table" and raw.towns[flavor], out.towns)
  rows(type(raw.spots) == "table" and raw.spots[flavor], out.spots)
  for _, r in ipairs(type(raw.landmarks) == "table" and raw.landmarks or {}) do
    local f = X and X.Split(tostring(r)) or {}
    local map, packed = tostring(f[4] or ""):match("^(%d+):(%x+)$")
    if f[1] and f[1] ~= "" and map and tostring(f[3] or ""):find(side, 1, true) and QD and QD.SpotsFrom then
      for _, sp in ipairs(QD.SpotsFrom(QD, { [tonumber(map)] = X.Points(packed) })) do
        out.marks[#out.marks + 1] = { name = f[1], kind = f[2], map = sp.map, x = sp.x, y = sp.y }
      end
    end
  end
  return out
end

function N:Destinations()
  local P = M.Places
  local idx = P and P.Index() or { byType = {}, count = 0 }
  local places = self:RoutePlaces()
  local Sp = M.Spots
  local key = tostring(idx) .. ":" .. idx.count .. ":" .. tostring(places) .. ":" .. tostring(self:Towns()) .. ":" .. tostring(Sp and Sp.rev or 0)
    .. ":" .. tostring(self:Landmarks())
  if self.dests and self.destsKey == key then return self.dests end
  local out = {}
  local function add(d) d.nk = d.nk or {} out[#out + 1] = d end
  -- towns and zones: the middle of the map (a zone has no one place to walk to)
  local Z = Panoply.ZoneLevels
  for _, id in ipairs(self:ZoneIds()) do
    local name = mapName(id)
    if name then
      local city = Z and Z.IsCity and Z.IsCity(id) and true or false
      add({ kind = city and "city" or "zone", name = name, sub = city and "Town" or "Zone", map = id, x = 0.5, y = 0.5 })
    end
  end
  -- dungeons and raids: their outdoor door
  local d = M.Data()
  for _, inst in ipairs(d and d.instances or {}) do
    for _, door in ipairs(inst.doors or {}) do
      if door[7] == 0 and door[4] and door[5] and door[6] then
        add({ kind = "instance", name = inst.name, sub = (inst.kind == "raid" and "Raid" or "Dungeon") .. " entrance", map = door[4], x = door[5], y = door[6] })
        break
      end
    end
  end
  -- 0.8.4: the places the route data names. A zone the list above already has (by map) is not added twice.
  local have = {}
  for _, e in ipairs(out) do if e.map and e.kind ~= "instance" then have[e.map] = true end end
  for _, p in ipairs(places or {}) do
    local name, kind, map, x, y, where = p[1], p[2], p[3], p[4], p[5], p[6]
    if kind == "zone" or kind == "battleground" then
      if not have[map] then
        have[map] = true
        add({ kind = "zone", name = mapName(map) or name, sub = kind == "zone" and "Zone" or "Battleground", map = map, x = x, y = y,
              pvp = kind == "battleground" or nil })
      end
    elseif kind == "area" then
      add({ kind = "area", name = name, sub = "Area in " .. where, map = map, x = x, y = y })
    elseif kind == "dungeon" then
      local known = map and map > 0
      add({ kind = "instance", name = name, sub = "Dungeon - entrance not charted yet", map = known and map or nil, x = known and x or nil,
            y = known and y or nil, uncharted = true, where = known and where or nil })
    end
  end
  -- 0.9.6: the towns (the game's own town labels), once each: not a zone or town already listed by that name on that map
  local named = {}
  for _, e in ipairs(out) do if e.map then named[N.Normalise(e.name) .. ":" .. e.map] = true end end
  for _, t in ipairs(self:Landmarks().towns) do
    local nk = N.Normalise(t.name) .. ":" .. t.map
    if not named[nk] then
      named[nk] = true
      local zone = mapName(t.map)
      add({ kind = "town", name = t.name, sub = zone and ("Town in " .. zone) or "Town", map = t.map, x = t.x, y = t.y, keys = N.NameKeys(t.name),
        ww = zone })
    end
  end
  -- 0.9.6: inns by their own names, the named places a guard points to, WoW Forever's named spots; each with its kind and where it is
  local function landmark(e, kind)
    local zone = mapName(e.map)
    local town, near = self:TownOf(e.map, e.x, e.y)
    if town and zone and (" " .. N.Normalise(zone) .. " "):find(" " .. N.Normalise(town) .. " ", 1, true) then town = nil end
    if town and N.Normalise(town) == N.Normalise(e.name) then town = nil end   -- "The Great Forge - The Great Forge" says it twice
    local shown = (town and zone) and (town .. ", " .. zone) or town or zone
    local isPlace = M.PLACE_BY_KEY and M.PLACE_BY_KEY[kind] or kind == "flight"
    -- a class's trainers ("Undercity Mage Trainers") follow the class rule of the class trainers (N.ClassOK)
    local classWord
    if kind == "trainer" and P and P.ClassWords then
      local n = " " .. N.Normalise(e.name) .. " "
      for _, cw in ipairs(P.ClassWords()) do if n:find(" " .. cw .. " ", 1, true) then classWord = cw break end end
    end
    add({ kind = "landmark", name = e.name, sub = (N.LANDMARK_LABEL[kind] or "Landmark") .. (shown and (" - " .. shown) or ""),
      map = e.map, x = e.x, y = e.y, keys = N.NameKeys(e.name), tw = isPlace and N.TypeText(kind) or (N.LANDMARK_LABEL[kind] or ""),
      ww = (zone or "") .. " " .. (near or ""), ptype = isPlace and kind or nil, classWord = classWord })
  end
  local L = self:Landmarks()
  for _, e in ipairs(L.marks) do landmark(e, e.kind) end
  for _, e in ipairs(L.spots) do
    if not named[N.Normalise(e.name) .. ":" .. e.map] then landmark(e, "landmark") end
  end
  -- each kind of place: the nearest one to you
  if P then
    for _, t in ipairs(M.PLACE_TYPES) do
      if P.Count(t.key) > 0 then
        add({ kind = "type", name = t.dest, sub = "Nearest to you", type = t.key, keys = { t.dest, t.alias } })
      end
    end
    if P.Count("flight") > 0 then add({ kind = "type", name = "Flight master", sub = "Nearest to you", type = "flight", keys = { "Flight master", "flight" } }) end
    -- every one of them by name, with its kind and where it stands (zone and town) as more words to find it by
    local seen = {}
    local function whereOf(e)
      local zone = mapName(e.map)
      local town, near = self:TownOf(e.map, e.x, e.y)
      -- "Stormwind, Stormwind City" says the same thing twice
      if town and zone and (" " .. N.Normalise(zone) .. " "):find(" " .. N.Normalise(town) .. " ", 1, true) then town = nil end
      local shown = (town and zone) and (town .. ", " .. zone) or town or zone
      return shown, (zone or "") .. " " .. (near or ""), town
    end
    local kinds = {}
    for k in pairs(idx.byType) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, k in ipairs(kinds) do
      for _, e in ipairs(idx.byType[k]) do
        if e.station then
          -- a mailbox, an anvil, a forge or a camp site has no name of its own: one entry for each town, and one for the rest of each zone
          local shown, words, town = whereOf(e)
          local gk = "station:" .. e.type .. ":" .. e.map .. ":" .. (town or "")
          local g = seen[gk]
          if not g then
            g = { kind = "place", name = e.name, sub = shown or P.TypeLabel(e.type), map = e.map, x = e.x, y = e.y, keys = { e.name, e.sub },
              tw = N.TypeText(e.type), ww = words, spots = {}, ptype = e.type }
            seen[gk] = g
            add(g)
          end
          g.spots[#g.spots + 1] = { map = e.map, x = e.x, y = e.y }
        else
          local sk = e.type .. ":" .. tostring(e.id) .. ":" .. e.map
          if not seen[sk] then
            seen[sk] = true
            local shown, words = whereOf(e)
            local flight = e.type == "flight"
            local class = e.type == "placeTrainClass" and e.classWord or nil
            local what = (class and type(e.sub) == "string" and e.sub ~= "") and e.sub or P.TypeLabel(e.type)   -- "Paladin Trainer", not "Class trainer"
            add({ kind = flight and "flight" or "npc", name = e.name, sub = what .. (shown and (" - " .. shown) or ""),
              map = e.map, x = e.x, y = e.y, keys = { e.name, e.sub },
              tw = N.TypeText(e.type) .. (class and (" " .. class .. " trainer") or ""),
              ww = words .. (flight and (" " .. (self:FlightName(e.id) or "")) or ""), classWord = class, ptype = e.type })
          end
        end
      end
    end
  end
  -- Nov 2026: the player's own saved spots, found next to the places of the data (Spots.lua)
  if Sp and Sp.Dests then for _, sd in ipairs(Sp:Dests()) do add(sd) end end
  self.dests, self.destsKey = out, key
  return out
end

-- the best matches for the text typed so far; Find.lua (0.8.4) adds quests, items, creatures and bosses to the places
function N:Search(query, limit)
  local F = M.Find
  if F and F.Search then return F:Search(self:Destinations(), query, limit) end
  return N.Rank(self:Destinations(), query, limit)
end

-------------------------------------------------------------------------------
-- From a destination to a spot on a map
-------------------------------------------------------------------------------
-- the closest place of a kind: by distance when both you and it are on one continent, else the first the data lists
function N:Nearest(typeKey)
  local P = M.Places
  local list = P and P.Index().byType[typeKey]
  if not list or #list == 0 then return nil end
  local pm, px, py = C.GetPlayerPos()
  local best, bestD
  for _, e in ipairs(list) do
    local ok = true
    if typeKey == "placeTrainClass" and not (Panoply.db and Panoply.db.placeClassAll) then ok = P.IsMyClass(e) end   -- "the nearest class trainer" is yours
    if ok then
      local dist = pm and Nav and Nav.Distance(pm, px, py, e.map, e.x, e.y)
      if dist and (not bestD or dist < bestD) then best, bestD = e, dist end
      if not best and not pm then best = e end
    end
  end
  if not best then
    for _, e in ipairs(list) do
      if typeKey ~= "placeTrainClass" or (Panoply.db and Panoply.db.placeClassAll) or P.IsMyClass(e) then best = e break end
    end
  end
  return best
end

-- { map, x, y, label } for a destination, or nil and why not
function N:Resolve(d)
  if type(d) ~= "table" then return nil, "no place" end
  if d.pvp then return nil, "it is a battleground, not a place you can walk to" end
  if d.uncharted then
    if not (d.map and d.x and d.y) then return nil, "its entrance is not charted yet" end
    return { map = d.map, x = d.x, y = d.y, label = d.name,
             note = ("The entrance to %s is not charted yet. This takes you to %s."):format(d.name, d.where or "its zone") }
  end
  if d.type then
    local e = self:Nearest(d.type)
    if not e then return nil, "none known" end
    return { map = e.map, x = e.x, y = e.y, label = e.name }
  end
  if type(d.spots) == "table" and d.spots[1] then
    -- several of them in one town or zone (two mailboxes): the one nearest to you
    local pm, px, py = C.GetPlayerPos()
    local best, bestD
    for _, s in ipairs(d.spots) do
      local dist = pm and Nav and Nav.Distance(pm, px, py, s.map, s.x, s.y)
      if dist and (not bestD or dist < bestD) then best, bestD = s, dist end
    end
    best = best or d.spots[1]
    return { map = best.map, x = best.x, y = best.y, label = d.name }
  end
  if d.map and d.x and d.y then return { map = d.map, x = d.x, y = d.y, label = d.name } end
  return nil, "no position"
end

-------------------------------------------------------------------------------
-- Saved with the character: favourites, Home, recents
-------------------------------------------------------------------------------
local function store() return Panoply.cdb end

local function snapshot(d)
  return { kind = d.kind, name = d.name, sub = d.sub, map = d.map, x = d.x, y = d.y, type = d.type, pvp = d.pvp, uncharted = d.uncharted, where = d.where,
           spot = d.spot }
end

local function same(a, b)
  if a.spot or b.spot then return a.spot == b.spot end       -- a saved spot is itself, whatever it is called now
  if a.type or b.type then return a.type == b.type end
  return a.name == b.name and a.map == b.map and math.abs((a.x or 0) - (b.x or 0)) < 0.0005 and math.abs((a.y or 0) - (b.y or 0)) < 0.0005
end

function N:Favs() local s = store() if not s then return {} end s.placesFav = s.placesFav or {} return s.placesFav end
function N:Recents() local s = store() if not s then return {} end s.placesRecent = s.placesRecent or {} return s.placesRecent end

function N:FavIndex(d)
  for i, f in ipairs(self:Favs()) do if same(f, d) then return i end end
  return nil
end
-- a saved spot's star is kept with the spot (for every character); every other favourite is this character's own list
local function spotOf(d)
  local Sp = M.Spots
  return type(d) == "table" and d.spot and Sp and Sp:Get(d.spot) or nil
end
function N:IsFav(d)
  if type(d) == "table" and d.spot then local sp = spotOf(d) return sp ~= nil and sp.fav == true end
  return self:FavIndex(d) ~= nil
end
function N:AddFav(d)
  if type(d) == "table" and d.spot then return M.Spots and M.Spots:SetFav(d.spot, true) or false end
  local list = self:Favs()
  if not store() or self:IsFav(d) or #list >= N.MAX_FAV then return false end
  list[#list + 1] = snapshot(d)
  return true
end
function N:RemoveFav(d)
  if type(d) == "table" and d.spot then return M.Spots and M.Spots:SetFav(d.spot, false) or false end
  local i = self:FavIndex(d)
  if not i then return false end
  table.remove(self:Favs(), i)
  return true
end
function N:ToggleFav(d)
  if self:IsFav(d) then return self:RemoveFav(d) end
  return self:AddFav(d)
end

function N:Remember(d)
  local list = self:Recents()
  if not store() then return end
  for i = #list, 1, -1 do if same(list[i], d) then table.remove(list, i) end end
  table.insert(list, 1, snapshot(d))
  while #list > N.MAX_RECENT do table.remove(list) end
end

function N:SetHome(d)
  local s = store()
  if not s or type(d) ~= "table" then return false end
  s.placesHome = snapshot(d)
  return true
end
function N:ClearHome() local s = store() if s then s.placesHome = nil end end

-- the Home destination, and whether it is the automatic one: the place you chose, else the inn your hearthstone is bound to
function N:Home()
  local s = store()
  local h = s and s.placesHome
  if type(h) == "table" and h.map then return h, false end
  local R = Panoply.Route
  local bind = R and R.BindSpot and R:BindSpot()
  if bind and bind.map and bind.x and bind.y then
    return { kind = "home", name = bind.npcName or bind.name, sub = "Hearth inn - " .. tostring(bind.name), map = bind.map, x = bind.x, y = bind.y }, true
  end
  return nil
end

-------------------------------------------------------------------------------
-- Going and stops (the waypoint list)
-------------------------------------------------------------------------------
function N:Stops()
  local W = Panoply.Waypoints
  return W and W:List() or {}
end

local function waypointsOn() return Panoply.Waypoints ~= nil and Panoply.Modules:IsOn("waypoints") end

local function retarget()
  if Panoply.Arrow and Panoply.Arrow.Retarget and not Panoply:PlayAlong() then Panoply.Arrow:Retarget() end
end

-- put a spot in the list: first = the next stop (the arrow follows it), else at the end
-- src (0.9.5 phase 4K): the Map page's group the stop goes in (Waypoints.lua W.GROUPS); none = a stop of the trip
function N:Place(r, first, src)
  if waypointsOn() then
    local W = Panoply.Waypoints
    src = src or "trip"
    local wp = W:Add(r.map, r.x, r.y, r.label, true, src)
    if not wp then return false end
    -- 0.8.4: a Go to stop: the route engine plans to it even in an area without a guide, also after a reload (Route:HandPicked).
    -- 0.9.5 phase 4K: only a stop of the trip; a pin another page drops (pet tames, a dungeon door, a death, a profession spot) is a
    -- waypoint, and becomes a trip stop only through "Add to trip" (Waypoints.lua W:AddToTrip)
    if src == "trip" then wp.go = true end
    local n = #W:List()
    if first and n > 1 then W:Move(n, 1) end
    retarget()
    return true
  end
  -- the Waypoints module is off: one destination, straight to the arrow
  if not first then Panoply:Print("Switch on Waypoints (in Settings) to chain stops.") return false end
  return M:PointAt(r.map, r.x, r.y, r.label, src)
end

function N:Go(d, src)
  local r, why = self:Resolve(d)
  if not r then Panoply:Print(("Can't go to %s: %s."):format(tostring(d and d.name or "that place"), why or "no position")) return false end
  if not self:Place(r, true, src) then return false end
  self:Remember(d)
  Panoply:Print(("Going to %s."):format(r.label or "that place"))
  if r.note then Panoply:Print(r.note) end
  if self.frame and self.frame:IsShown() then self:Update() end
  return true
end

function N:AddStop(d, src)
  local r, why = self:Resolve(d)
  if not r then Panoply:Print(("Can't add %s: %s."):format(tostring(d and d.name or "that place"), why or "no position")) return false end
  if not self:Place(r, false, src) then return false end
  self:Remember(d)
  if r.note then Panoply:Print(r.note) end
  if self.frame and self.frame:IsShown() then self:Update() end
  return true
end

-- open the world map on the place's zone and ring the spot (Find.lua draws the ring); nothing is set, nothing moves
function N:ShowOnMap(d)
  local r, why = self:Resolve(d)
  if not r then Panoply:Print(("Can't show %s: %s."):format(tostring(d and d.name or "that place"), why or "no position")) return false end
  if C.InCombat() then Panoply:Print("The map can't be changed in combat.") return false end
  local open = C.G("C_Map.OpenWorldMap")
  local wm = C.WorldMap()
  if open then M.pc(open, r.map) elseif wm and wm.Show then wm:Show() end
  if wm and wm.SetMapID then wm:SetMapID(r.map) end
  if M.Find and M.Find.Mark then M.Find:Mark(r) end
  return true
end

function N:GoHome()
  local h = self:Home()
  if not h then Panoply:Print("No Home yet: right-click a place and choose Set as Home.") return false end
  return self:Go(h)
end

function N:MoveStop(i, dir)
  local W = Panoply.Waypoints
  if not W then return false end
  local ok = W:Move(i, i + dir)
  if ok then retarget() end
  return ok
end
function N:RemoveStop(i)
  local W = Panoply.Waypoints
  if not W then return false end
  local ok = W:Remove(i)
  if ok then retarget() end
  return ok
end

-------------------------------------------------------------------------------
-- 0.8.4: the trip you picked, turn by turn
-------------------------------------------------------------------------------
N.TRIP_WORKING = "Working out the way..."
N.TRIP_STRAIGHT = "No route worked out for this one: the arrow points straight at it."

-- The trip to the stop the arrow follows, when the player picked it by hand: { label, total = seconds, steps = { { text, detail } ... } },
-- { label, working = true } while the route engine is still planning, { label } when there is no route (the arrow points straight
-- there); nil when nothing is hand-picked. The steps are the route engine's own legs in Engine/Travel.lua's words.
function N:Trip()
  local R, T = Panoply.Route, Panoply.Travel
  if not (R and R.HandTrip and T and T.Advice) then return nil end
  local m, x, y, label = R:HandTrip()
  if not m then return nil end
  local trip = { label = label or (mapName(m) or "your stop"), map = m, x = x, y = y }
  local r = R.current
  if r and R.Valid and not R:Valid(r) then r = nil end
  if r and r.legs and #r.legs > 0 then
    trip.total = (R.StepETA and R:StepETA()) or r.total
    trip.steps = T:Advice(r)
    trip.ride = false
    for _, l in ipairs(r.legs) do if l.kind ~= "walk" then trip.ride = true end end
  elseif R.working or (R.queue and R.queue[1]) or R.waitPos then
    trip.working = true
  end
  return trip
end

-- Says the next part of a hand-picked trip in chat, once: the whole trip when it is first worked out ("Trip to Theramore: about 9 min.
-- First: go to the ship dock at Menethil Harbor."), then each new part as the one before it is done ("Next: take the boat to
-- Theramore."). A plain walk with nothing to board is not announced (Go already said "Going to ..."). Uses the travel steps' own
-- switch (Travel steps in the Guide settings: routeSteps). Returns the line it said, or nil.
function N:Announce()
  if Panoply.db and Panoply.db.routeSteps == false then return nil end
  local trip = self:Trip()
  if not (trip and trip.steps and trip.steps[1]) then
    if not trip then self.said = nil end
    return nil
  end
  local spot = trip.map .. ":" .. trip.x .. ":" .. trip.y
  local said = self.said
  local same = said and said.spot == spot
  if not same and not trip.ride then return nil end
  local first = trip.steps[1].text
  if same and said.text == first then return nil end
  local lower = first:sub(1, 1):lower() .. first:sub(2)
  local line
  if same then
    line = ("Next: %s."):format(lower)
  else
    line = ("Trip to %s: about %s. First: %s."):format(trip.label, Panoply.Route.Duration(trip.total or 0), lower)
  end
  self.said = { spot = spot, text = first }
  Panoply:Print(line)
  return line
end

-------------------------------------------------------------------------------
-- What the window lists: rows of { head } | { dest, role } | { note } | { step = { text, detail } }
-------------------------------------------------------------------------------
function N:Model(query)
  local rows = {}
  query = trim(query)
  if query ~= "" then
    for _, d in ipairs(self:Search(query)) do rows[#rows + 1] = { dest = d } end
    if #rows == 0 then
      rows[1] = { note = "Nothing matches \"" .. query .. "\"." }
      -- Nov 2026: a place that is missing can be reported, or saved as a spot of your own
      if Panoply.ReportWindow then rows[#rows + 1] = { action = "report", text = "Report a missing place", query = query,
        tip = "Tell us which place is missing. The report window opens with what you typed filled in." } end
      if M.Spots then rows[#rows + 1] = { action = "save", text = "Save a spot of my own", query = query,
        tip = "Save a place yourself: where you stand, or a zone, X and Y you type." } end
    end
    return rows
  end
  -- 0.8.4: the trip in hand comes first, turn by turn
  local trip = self:Trip()
  if trip then
    rows[#rows + 1] = { head = "YOUR TRIP" }
    if trip.steps then
      rows[#rows + 1] = { step = { text = "To " .. trip.label, detail = ("About %s in all."):format(Panoply.Route.Duration(trip.total or 0)) } }
      for i, s in ipairs(trip.steps) do rows[#rows + 1] = { step = { text = i .. ". " .. s.text, detail = s.detail } } end
    else
      rows[#rows + 1] = { step = { text = "To " .. trip.label, detail = trip.working and N.TRIP_WORKING or N.TRIP_STRAIGHT } }
    end
  end
  local home, auto = self:Home()
  if home then
    rows[#rows + 1] = { head = "HOME" }
    rows[#rows + 1] = { dest = home, role = "home", auto = auto }
  end
  -- favourites: the starred saved spots first (kept for every character), then this character's own favourite places
  local Sp = M.Spots
  local saved = Sp and Sp:Dests() or {}
  local favs = self:Favs()
  local starred, plain = {}, {}
  for _, d in ipairs(saved) do if self:IsFav(d) then starred[#starred + 1] = d else plain[#plain + 1] = d end end
  if #favs + #starred > 0 then
    rows[#rows + 1] = { head = "FAVOURITES" }
    for _, d in ipairs(starred) do rows[#rows + 1] = { dest = d, role = "fav" } end
    for _, f in ipairs(favs) do if not f.spot then rows[#rows + 1] = { dest = f, role = "fav" } end end
  end
  if #plain > 0 then
    rows[#rows + 1] = { head = "SAVED SPOTS" }
    for _, d in ipairs(plain) do rows[#rows + 1] = { dest = d, role = "saved" } end
  end
  local recents = self:Recents()
  local shownRecent = {}
  for _, r in ipairs(recents) do if not r.spot or (Sp and Sp:Get(r.spot)) then shownRecent[#shownRecent + 1] = r end end   -- a removed spot is not offered
  if #shownRecent > 0 then
    rows[#rows + 1] = { head = "RECENT" }
    for _, r in ipairs(shownRecent) do rows[#rows + 1] = { dest = r, role = "recent" } end
  end
  if #rows == 0 then rows[1] = { note = "Type a town, a dungeon, a trainer, the auction house or a flight master." } end
  return rows
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
N.W, N.RES_H, N.STOP_H, N.ROW_H = 420, 196, 128, 44
N.BTN_Y = 28                 -- the bottom buttons sit this far up: clear of the resize grip in the corner

local function distanceText(map, x, y)
  local pm, px, py = C.GetPlayerPos()
  local d = pm and Nav and Nav.Distance(pm, px, py, map, x, y)
  return d and Panoply.StepText and Panoply.StepText.Distance(d) or nil
end

local function newRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(N.ROW_H)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(r)
  local a = Skin.colors.accent
  r.hl:SetColorTexture(a[1], a[2], a[3], 0.14); r.hl:Hide()
  r.name = Skin.Text(r, 12)
  r.sub = Skin.Text(r, 11, Skin.colors.inkSoft)
  r.head = Skin.Label(r, 10, Skin.colors.gold)
  r.note = Skin.Text(r, 12, Skin.colors.inkSoft)
  for _, fs in ipairs({ r.name, r.sub, r.head, r.note }) do if fs.SetWordWrap then fs:SetWordWrap(false) end if fs.SetJustifyH then fs:SetJustifyH("LEFT") end end
  r.add = Skin.IconButton(r, "+", 22, function(self) local row = self:GetParent() if row.dest then N:AddStop(row.dest) end end,
    "Add as a stop", "Add this place to the end of your stops. The arrow keeps going to the first stop.")
  r.fav = Skin.Button(r, "Save", 48, 22, function(self)
    local row = self:GetParent()
    if row.dest then N:ToggleFav(row.dest) N:Update() end
  end, "Favourite", "Save this place, or take it off your favourites.")
  -- a saved spot has a star in place of the Save button (Spots.lua): gold when it is a favourite
  r.star = Skin.IconButton(r, "StarEmpty", 22, function(self)
    local row = self:GetParent()
    if row.dest then N:ToggleFav(row.dest) N:Update() end
  end, "Favorite", "Star this saved spot, or take the star off. Starred spots come first.")
  r.star:Hide()
  -- a row that is one button ("Report a missing place")
  r.act = Skin.Button(r, "", 160, 24, function(self) N:RowAction(self:GetParent()) end, "", "")
  r.act:Hide()
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r:SetScript("OnEnter", function(self) if self.dest then self.hl:Show() end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() end)
  r:SetScript("OnClick", function(self, button)
    if not self.dest then return end
    if button == "RightButton" then N:RowMenu(self) else N:Go(self.dest) end
  end)
  return r
end

-- the buttons under "Nothing matches": report the missing place, or save a spot of your own
function N:RowAction(row)
  local m = row and row.action
  if not m then return end
  if m.action == "report" and Panoply.ReportWindow then
    local pm, px, py = C.GetPlayerPos()
    local where = pm and (" I am in %s at %.1f, %.1f."):format(C.MapName(pm) or ("map " .. pm), (px or 0) * 100, (py or 0) * 100) or ""
    return Panoply.ReportWindow:Open({ general = true, note = ("Missing place: I searched Go to for \"%s\" and it is not there.%s"):format(m.query or "", where) })
  elseif m.action == "save" and M.Spots then
    return M.Spots:OpenForm({ here = true, name = m.query })
  end
end

function N:RowMenu(row)
  local d = row.dest
  if not (d and Skin.Menu) then return end
  local items = {
    { text = "Go there", func = function() N:Go(d) end },
    { text = "Add as a stop", func = function() N:AddStop(d) end },
    { text = d.spot and (N:IsFav(d) and "Remove the star" or "Star as a favourite") or (N:IsFav(d) and "Remove from favourites" or "Save as a favourite"),
      func = function() N:ToggleFav(d) N:Update() end },
    { text = "Set as Home", func = function() if N:SetHome(d) then N:Update() end end },
    { text = "Show on the map", func = function() N:ShowOnMap(d) end },
  }
  if row.role == "home" and not row.auto then items[#items + 1] = { text = "Clear Home", func = function() N:ClearHome() N:Update() end } end
  if d.spot and M.Spots then
    items[#items + 1] = { text = "Rename...", func = function() M.Spots:OpenForm({ edit = d.spot }) end }
    items[#items + 1] = { text = "Remove this spot", tip = "Takes this spot off your saved list. This cannot be undone.", func = function() M.Spots:Remove(d.spot) end }
  end
  Skin.Menu(row, items, { width = 190 })
end

function N:Create()
  if self.frame then return self.frame end
  local W = self.W
  local f = Skin.Window("PanoplySuiteGoTo", W, 494 + N.BTN_Y - 14, "Go to", "Type a place; the arrow takes you there", nil, "Travel")   -- 4J: its own header icon
  self.frame = f
  local inner = W - 32
  f.input = Skin.Input(f, inner, 26, N.PLACEHOLDER)
  f.input:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -62)
  f.input:SetScript("OnTextChanged", function(box)
    if box.placeholder then if (box:GetText() or "") == "" then box.placeholder:Show() else box.placeholder:Hide() end end
    N:Update()
  end)
  f.input:SetScript("OnEnterPressed", function(box)
    local first
    for _, r in ipairs(N.model or {}) do if r.dest then first = r.dest break end end
    if first then N:Go(first) box:ClearFocus() end
  end)
  f.res = Skin.ScrollArea(f)
  f.res:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -96)
  f.res:SetSize(inner, self.RES_H)
  f.resRows = {}
  f.stopHead = Skin.Label(f, 10, Skin.colors.gold)
  f.stopHead:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + self.RES_H + 10))
  f.stopHead:SetText("STOPS")
  f.stops = Skin.ScrollArea(f)
  f.stops:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + self.RES_H + 10 + 16))
  f.stops:SetSize(inner, self.STOP_H)
  f.stopRows = {}
  f.stopNote = Skin.Text(f, 12, Skin.colors.inkSoft)
  f.stopNote:SetPoint("TOPLEFT", f.stops, "TOPLEFT", 2, -4)
  f.stopNote:SetWidth(inner - 4)
  f.stopNote:SetText("No stops. Search a place and choose it, or press + to add it as a stop.")
  f.home = Skin.Button(f, "Go home", 100, 24, function() N:GoHome() end, "Go home", "Go to your Home: the place you chose, or the inn your hearthstone is bound to.")
  f.home:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, N.BTN_Y)
  -- 0.9.5 phase 4J (spec 02 section 1, theme pass): Clear stops is in the ⋯ menu and asks first (it was a button that cleared at once)
  f.clear = Panoply.Kit.More(f, function()
    return { { text = "Clear stops", tip = "Asks first, then removes every stop. The arrow has nowhere to go until you pick a place.",
      func = function() Panoply.Kit.Ask(f.clear, "Remove every stop?", "Yes, clear them",
        function() if Panoply.Waypoints then Panoply.Waypoints:Clear() retarget() N:Update() end end, "Keep them") end } }
  end, "Clear stops (asks first).", 24)
  f.clear:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, N.BTN_Y)
  -- Nov 2026: save a spot of your own (Spots.lua): where you stand, or a zone, X and Y you type
  f.saveSpot = Skin.Button(f, "Save a spot", 100, 24, function() if M.Spots then M.Spots:OpenForm({ here = true }) end end, "Save a spot",
    "Save a place of your own: where you stand now, or a zone, X and Y you type. Shift-right-click the world map saves the place you clicked.")
  f.saveSpot:SetPoint("BOTTOM", f, "BOTTOM", 0, N.BTN_Y)
  -- Nov 2026: the window resizes in both directions and remembers its size: the search results take the height it gains or
  -- loses (they scroll), the stops keep theirs, the buttons stay on the bottom edge
  Skin.Resizable(f, { key = "goto", minW = N.MIN_W, minH = N.MIN_H, onSize = function(w, h) N:Resized(w, h) end })
  f:HookScript("OnShow", function() N:Update() end)
  if not self.listening then
    self.listening = true
    Panoply:Listen("WAYPOINTS_CHANGED", function() if N.frame and N.frame:IsShown() then N:Update() end end)
  end
  return f
end

N.MIN_W, N.MIN_H = 360, 400
N.PLACEHOLDER, N.PLACEHOLDER_SHORT = "Search: a town, a trainer, the auction house...", "Search a place"
function N:Resized(w, h)
  local f = self.frame
  if not f then return end
  local inner = w - 32
  local resH = math.max(60, h - 96 - 10 - 16 - self.STOP_H - 38 - N.BTN_Y)       -- what is left between the search box and the stops
  f.input:SetWidth(inner)
  -- the words in the empty search box get shorter on a narrow window
  if f.input.placeholder then
    f.input.placeholder:SetText(N.PLACEHOLDER)
    if Skin.TextWidth(f.input.placeholder) > inner - 32 then f.input.placeholder:SetText(N.PLACEHOLDER_SHORT) end
  end
  f.res:SetSize(inner, resH)
  f.stopHead:ClearAllPoints(); f.stopHead:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + resH + 10))
  f.stops:ClearAllPoints(); f.stops:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + resH + 10 + 16))
  f.stops:SetSize(inner, self.STOP_H)
  f.stopNote:SetWidth(inner - 4)
  -- three buttons on the bottom edge: on a narrow window the middle one moves up onto a row of its own
  local bw = (f.home:GetWidth() or 100) + (f.saveSpot:GetWidth() or 100) + (f.clear:GetWidth() or 100) + 2 * Skin.SP.m
  f.saveSpot:ClearAllPoints()
  if bw <= inner then f.saveSpot:SetPoint("BOTTOM", f, "BOTTOM", 0, N.BTN_Y)
  else
    f.saveSpot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, N.BTN_Y + 24 + Skin.SP.s)
    resH = math.max(60, resH - 24 - Skin.SP.s)
    f.res:SetSize(inner, resH)
    f.stopHead:ClearAllPoints(); f.stopHead:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + resH + 10))
    f.stops:ClearAllPoints(); f.stops:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(96 + resH + 10 + 16))
  end
  if f.res.UpdateBar then f.res:UpdateBar() end
  if f.stops.UpdateBar then f.stops:UpdateBar() end
  if f:IsShown() then self:Update() end
end

function N:DrawResults()
  local f = self.frame
  local area = f.res
  local rows = self.model
  local content = area.content
  local width = area:ContentWidth(#rows * self.ROW_H)
  local y = 0
  local btnW = 22 + 4 + 48 + 6
  for i, m in ipairs(rows) do
    local r = f.resRows[i]
    if not r then r = newRow(content) f.resRows[i] = r end
    r.dest, r.role, r.auto, r.action = m.dest, m.role, m.auto, m.action and m or nil
    r.name:Hide(); r.sub:Hide(); r.head:Hide(); r.note:Hide(); r.add:Hide(); r.fav:Hide(); r.hl:Hide(); r.star:Hide(); r.act:Hide()
    -- a place row is two single lines (cut with an ellipsis); a trip step's words wrap instead, so an instruction is never cut short
    for _, fs in ipairs({ r.name, r.sub }) do if fs.SetWordWrap then fs:SetWordWrap(m.step ~= nil) end end
    local h = self.ROW_H
    if m.step then
      local textW = width - 12
      r.name:SetText(m.step.text); r.name:SetWidth(textW)
      r.sub:SetText(m.step.detail or ""); r.sub:SetWidth(textW)
      local nameH = Skin.TextHeight(r.name, textW)
      local subH = (m.step.detail and m.step.detail ~= "") and Skin.TextHeight(r.sub, textW) or 0
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -4); r.name:Show()
      r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -(4 + nameH + 2))
      if subH > 0 then r.sub:Show() end
      h = 4 + nameH + 2 + subH + 6
    elseif m.action then
      h = 30
      r.act.label:SetText(m.text); r.act.tip, r.act.tipBody = m.text, m.tip
      Skin.FitButton(r.act, 120, width - 8)
      r.act:ClearAllPoints(); r.act:SetPoint("LEFT", r, "LEFT", 4, 0); r.act:Show()
    elseif m.head then
      h = 20
      r.head:SetText(m.head); r.head:ClearAllPoints(); r.head:SetPoint("LEFT", r, "LEFT", 4, -2); r.head:Show()
    elseif m.note then
      h = 28
      Skin.Ellipsize(r.note, m.note, width - 8)
      r.note:ClearAllPoints(); r.note:SetPoint("LEFT", r, "LEFT", 4, 0); r.note:Show()
    else
      local d = m.dest
      local textW = width - btnW - 10
      Skin.Ellipsize(r.name, d.name or "?", textW)
      r.name:SetWidth(textW)
      local sub = d.sub or ""
      if m.role == "home" and m.auto then sub = d.sub end
      local dist = d.map and d.x and distanceText(d.map, d.x, d.y)
      if dist then sub = sub .. ((sub ~= "") and "  -  " or "") .. dist end
      Skin.Ellipsize(r.sub, sub, textW)
      r.sub:SetWidth(textW)
      -- two lines: the name, then the kind and the distance under it (measured, so they never touch at any text size)
      local nameH = Skin.TextHeight(r.name, textW)
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -4); r.name:Show()
      r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -(4 + nameH + 2)); r.sub:Show()
      r.add:ClearAllPoints(); r.add:SetPoint("RIGHT", r, "RIGHT", -(48 + 4 + 4), 0); r.add:Show()
      if d.spot then
        -- a saved spot: its star (gold = a favourite), where the Save button sits for other places
        local on = N:IsFav(d)
        r.star:SetIcon(on and "Star" or "StarEmpty", 14)
        local sc = on and Skin.colors.goldBright or Skin.colors.inkSoft
        if r.star.icon and r.star.icon.SetVertexColor then r.star.icon:SetVertexColor(sc[1], sc[2], sc[3], 1) end
        r.star.panoplyStarOn = on
        r.star:ClearAllPoints(); r.star:SetPoint("RIGHT", r, "RIGHT", -(4 + 13), 0); r.star:Show()
      else
        r.fav.label:SetText(N:IsFav(d) and "Saved" or "Save")
        r.fav:ClearAllPoints(); r.fav:SetPoint("RIGHT", r, "RIGHT", -4, 0); r.fav:Show()
      end
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r:SetSize(width, h)
    r:Show()
    y = y + h
  end
  for i = #rows + 1, #f.resRows do f.resRows[i]:Hide() f.resRows[i].dest = nil end
  area:SetContentHeight(y)
  content:SetWidth(area:ContentWidth(y))
end

function N:DrawStops()
  local f = self.frame
  local list = self:Stops()
  local area = f.stops
  local content = area.content
  local rh = 26
  local width = area:ContentWidth(#list * rh)
  local y = 0
  for i, wp in ipairs(list) do
    local r = f.stopRows[i]
    if not r then
      r = CreateFrame("Frame", nil, content)
      r:SetHeight(rh)
      r.text = Skin.Text(r, 12)
      if r.text.SetWordWrap then r.text:SetWordWrap(false) end
      r.up = Skin.Button(r, "Up", 34, 22, function(self) N:MoveStop(self:GetParent().index, -1) end, "Move up", "Do this stop sooner. The first stop is the one the arrow follows.")
      r.down = Skin.Button(r, "Down", 44, 22, function(self) N:MoveStop(self:GetParent().index, 1) end, "Move down", "Do this stop later.")
      r.del = Skin.IconButton(r, "x", 22, function(self) N:RemoveStop(self:GetParent().index) end, "Remove", "Remove this stop.")
      f.stopRows[i] = r
    end
    r.index = i
    local label = wp.note and wp.note ~= "" and wp.note or (C.MapName(wp.m) or ("Map " .. tostring(wp.m)))
    local dist = distanceText(wp.m, wp.x, wp.y)
    local btns = 34 + 44 + 22 + 4 * 3
    Skin.Ellipsize(r.text, ("%s%d. %s%s"):format(i == 1 and (Skin.Code(Skin.colors.accent) .. ">|r ") or "", i, label, dist and ("  (" .. dist .. ")") or ""), width - btns - 8)
    r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.del:ClearAllPoints(); r.del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.down:ClearAllPoints(); r.down:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.up:ClearAllPoints(); r.up:SetPoint("RIGHT", r.down, "LEFT", -4, 0)
    r.up:SetEnabledLook(i > 1)
    r.down:SetEnabledLook(i < #list)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r:SetSize(width, rh)
    r:Show()
    y = y + rh
  end
  for i = #list + 1, #f.stopRows do f.stopRows[i]:Hide() end
  if #list == 0 then f.stopNote:Show() else f.stopNote:Hide() end
  area:SetContentHeight(y)
  content:SetWidth(area:ContentWidth(y))
  f.clear:SetEnabledLook(#list > 0)
end

function N:Update()
  local f = self.frame
  if not f then return end
  self.model = self:Model(f.input:GetText() or "")
  self:DrawResults()
  self:DrawStops()
  local home, auto = self:Home()
  f.home:SetEnabledLook(home ~= nil)
  f.home.label:SetText("Go home")
end

function N:Toggle()
  local f = self:Create()
  if f:IsShown() then f:Hide() return end
  f:Show()
  self:Update()
  if f.input.SetFocus then f.input:SetFocus() end
end

function N:Hide() if self.frame then self.frame:Hide() end end

-- 0.8.4: every new or changed route of a hand-picked trip: say its next part in chat, and keep the open window's list in step
Panoply:Listen("ROUTE_UPDATED", function()
  N:Announce()
  if N.frame and N.frame:IsShown() then N:Update() end
end)
