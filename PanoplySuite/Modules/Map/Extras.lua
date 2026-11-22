-- Map module, MAP EXTRAS (0.8.4): the places the NPC table does not hold. Mailboxes, anvils, forges and camp sites (cooking fires) are game
-- objects; guild masters and rare creatures are creatures the service flags do not find. All of them are read from
-- PanoplySuite_QuestData/Maps/Extras.lua (tools/build_mapextras.py: the same world database as every other spot in Panoply Suite, GPL-2.0-or-later) and
-- handed to Places.lua as more kinds of place, so they get the same switches (the Places menu on the map and the Map page), the same Look
-- (size, opacity, colour, on the world map and the minimap) and the same "nearest one" in the Go to window as trainers and innkeepers.
--
-- NOTHING here is a coordinate somebody typed in: every spot is a row of the data file, re-expressed on the client's own zone rectangle
-- by the same code as the NPC spots (QuestData's SpotsFrom: on WoW Forever a spot in a re-drawn zone is marked "not checked"). Without the
-- data file every one of these kinds stays empty.
--
-- A rare creature the data does not hold (WoW Forever's new ones) appears once the player has seen it: at the place it was seen from
-- (Rares.lua keeps the sightings), and the tooltip says so.
-- Information only (hub rule 2 of CLAUDE.md): this file draws nothing and moves nothing; it lists places.
local ADDON, Panoply = ...
local C, M = Panoply.Compat, Panoply.Map

local X = {}
M.Extras = X

-- the object kinds of the data file, in the order they are added: { data key, place key, the name a pin and a waypoint carry, its second line }
X.OBJECTS = {
  { "mail", "placeMail", "Mailbox" },
  { "anvil", "placeAnvil", "Anvil" },
  { "forge", "placeForge", "Forge" },
  { "camp", "placeCamp", "Camp site", "Cooking fire" },
}
X.CAMP_HELP = "A fire you can cook at: no need to light your own."
X.SIGHTING_HELP = "Marked where you saw it: the data has no spot for it."

-- the data add-on's table, or nil
function X.Data()
  local QD = Panoply.QuestData
  local own = (QD and QD.own) or rawget(_G, "PanoplySuiteQuestData")
  local d = type(own) == "table" and own.MapExtras
  return type(d) == "table" and d or nil
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do if type(k) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys
end

-- "xxxyyy..." (3 + 3 hex digits a point, 0..4095) -> { { x, y } ... } in percent, the shape QuestData's spawn lists have
function X.Points(packed)
  local out = {}
  if type(packed) ~= "string" then return out end
  for i = 1, #packed - 5, 6 do
    local x, y = tonumber(packed:sub(i, i + 2), 16), tonumber(packed:sub(i + 3, i + 5), 16)
    if x and y then out[#out + 1] = { x / 40.95, y / 40.95 } end
  end
  return out
end

-- spawn lists by map -> spots { map, x, y (0..1), unverified } on this client's rectangles, maps in order
local function spots(byMap)
  local QD = Panoply.QuestData
  local out = {}
  if not (QD and QD.SpotsFrom and type(byMap) == "table") then return out end
  for _, map in ipairs(sortedKeys(byMap)) do
    for _, s in ipairs(QD.SpotsFrom(QD, { [map] = byMap[map] })) do out[#out + 1] = s end
  end
  return out
end

local function split(s)
  local out, pos = {}, 1
  while true do
    local a = s:find("|", pos, true)
    if not a then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, a - 1)
    pos = a + 1
  end
end
X.Split = split

-- "<uiMap>:<xxxyyy...>;..." -> spots
local function spawnSpots(field)
  local byMap = {}
  for seg in tostring(field or ""):gmatch("[^;]+") do
    local map, packed = seg:match("^(%d+):(%x+)$")
    if map then byMap[tonumber(map)] = X.Points(packed) end
  end
  return spots(byMap)
end

-- "Level 10" or "Level 10 to 12" (nil when the data has no level)
function X.LevelText(lo, hi)
  lo, hi = tonumber(lo) or 0, tonumber(hi) or 0
  if lo <= 0 and hi <= 0 then return nil end
  if hi <= lo then return "Level " .. lo end
  return ("Level %d to %d"):format(lo, hi)
end

-------------------------------------------------------------------------------
-- Rare creatures of the data: { [npcId] = { id, name, min, max, elite, spots } }, decoded once
-------------------------------------------------------------------------------
function X:Rares()
  local d = X.Data()
  if self.rares and self.raresOf == d then return self.rares end
  local out = {}
  self.rares, self.raresOf = out, d
  for id, raw in pairs(d and type(d.rares) == "table" and d.rares or {}) do
    if type(id) == "number" and type(raw) == "string" then
      local f = split(raw)
      if f[1] and f[1] ~= "" then
        out[id] = { id = id, name = f[1], min = tonumber(f[2]) or 0, max = tonumber(f[3]) or 0, elite = f[4] == "1", spots = spawnSpots(f[5]) }
      end
    end
  end
  return out
end

function X:Rare(id) return self:Rares()[id] end

-- the spots of one object kind ("mail", "anvil", "forge", "camp"); mailboxes are the player's side's and the ones both sides use
function X:ObjectSpots(kind)
  local d = X.Data()
  local objects = d and type(d.objects) == "table" and d.objects or nil
  local t = objects and objects[kind]
  if type(t) ~= "table" then return {} end
  local out = {}
  local function addMaps(maps)
    if type(maps) ~= "table" then return end
    local byMap = {}
    for map, packed in pairs(maps) do if type(map) == "number" then byMap[map] = X.Points(packed) end end
    for _, s in ipairs(spots(byMap)) do out[#out + 1] = s end
  end
  if kind == "mail" then
    local QD = Panoply.QuestData
    local side = QD and QD.PlayerSide and QD:PlayerSide() or "A"
    addMaps(t[side])
    addMaps(t.AH)
  else
    addMaps(t)
  end
  return out
end

-------------------------------------------------------------------------------
-- More kinds of place for Places.lua (P.Index calls this once, with a function that files one entry)
-------------------------------------------------------------------------------
function X:AddPlaces(add)
  local d = X.Data()
  local n = 0
  if d then
    for _, o in ipairs(X.OBJECTS) do
      for _, s in ipairs(self:ObjectSpots(o[1])) do
        add({ type = o[2], name = o[3], sub = o[4], map = s.map, x = s.x, y = s.y, unverified = s.unverified, station = true })
        n = n + 1
      end
    end
    local QD = Panoply.QuestData
    local side = QD and QD.PlayerSide and QD:PlayerSide() or "A"
    local guild = type(d.guild) == "table" and d.guild or {}
    for _, id in ipairs(sortedKeys(guild)) do
      local f = split(tostring(guild[id]))
      if f[1] and f[1] ~= "" and tostring(f[2] or ""):find(side, 1, true) then
        for _, s in ipairs(spawnSpots(f[3])) do
          add({ type = "placeGuild", id = id, name = f[1], sub = "Guild Master", map = s.map, x = s.x, y = s.y, unverified = s.unverified })
          n = n + 1
        end
      end
    end
  end
  local rares = self:Rares()
  for _, id in ipairs(sortedKeys(rares)) do
    local r = rares[id]
    for _, s in ipairs(r.spots) do
      add({ type = "placeRare", id = id, name = r.name, sub = r.elite and "Rare elite" or "Rare", level = X.LevelText(r.min, r.max),
        map = s.map, x = s.x, y = s.y, unverified = s.unverified })
      n = n + 1
    end
  end
  -- a rare the data does not hold, seen by the player: where it was seen from
  local R = M.Rares
  local seen = R and R.Store and R:Store() or {}
  for _, id in ipairs(sortedKeys(seen)) do
    local e = seen[id]
    if not rares[id] and type(e) == "table" and type(e.map) == "number" and type(e.x) == "number" and type(e.y) == "number" then
      add({ type = "placeRare", id = id, name = type(e.name) == "string" and e.name or "Rare creature", sub = e.elite and "Rare elite" or "Rare",
        level = X.LevelText(e.lvl, e.lvl), map = e.map, x = e.x, y = e.y, sighting = true })
      n = n + 1
    end
  end
  return n
end

-- the extra lines of a place's tooltip (Places.lua tipOf)
function X:TipLines(e)
  local out = {}
  if type(e) ~= "table" then return out end
  if e.type == "placeRare" then
    if e.level then out[#out + 1] = e.level end
    local R = M.Rares
    if R and R.SeenText and e.id then out[#out + 1] = R:SeenText(e.id) end
    if e.sighting then out[#out + 1] = X.SIGHTING_HELP end
  elseif e.type == "placeCamp" then
    out[#out + 1] = X.CAMP_HELP
  end
  return out
end
