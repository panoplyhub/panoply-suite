-- Panoply Suite zone level ranges (Step 2 item E, our decisions 9 and 26; docs/step2/ZONE-LEVELS-CHECK.md is the sheet to check them against the game).
--
-- The game's own client table has a level range column for every map, but it is 0 for all 54 Era rows, and ranges worked out from the
-- creatures inside a zone box are useless (the boxes overlap their neighbours). So the ranges are written here by hand, and a range is
-- SHOWN only after somebody has seen it in the game and set `checked` to true in its row. Until then the row's range is only a proposal:
-- no zone exit, no toolbar chip and no tooltip says it. A city shows "City" instead of a range (that is a fact, not a level).
--
-- Classic Era and WoW Forever each have their OWN range for a zone ("will be different probably for classic vs. forever"), each with its
-- own checked flag, and a client reads only its own: on Era the Forever numbers are never looked at, and on Forever the Era ones are not.
-- A zone only one client has (Forever's new zones) has only that client's slot, so the other client has no row for it at all.
--
-- One row per map:
--   [uiMap] = { "name", era = { lowest, highest, checked }, forever = { lowest, highest, checked } }
--   [uiMap] = { "name", "city" }                      a city, on both clients
-- A slot with no range yet is { nil, nil, false }. To mark a range as checked, change its last word from false to true; a range that turned
-- out different in the game: change its two numbers in the same edit. tools/zone_levels_apply.py does both from the sheet, for both clients.
local ADDON, Panoply = ...
local Z = {}
Panoply.ZoneLevels = Z

Z.ROWS = {
  -- Kalimdor
  [1440] = { "Ashenvale", era = { 18, 30, false }, forever = { nil, nil, false } },
  [1447] = { "Azshara", era = { 45, 55, false }, forever = { nil, nil, false } },
  [1439] = { "Darkshore", era = { 10, 20, false }, forever = { nil, nil, false } },
  [1457] = { "Darnassus", "city" },
  [1443] = { "Desolace", era = { 30, 40, false }, forever = { nil, nil, false } },
  [1411] = { "Durotar", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1445] = { "Dustwallow Marsh", era = { 35, 45, false }, forever = { nil, nil, false } },
  [1448] = { "Felwood", era = { 48, 55, false }, forever = { nil, nil, false } },
  [1444] = { "Feralas", era = { 40, 50, false }, forever = { nil, nil, false } },
  [1450] = { "Moonglade", era = { 55, 60, false }, forever = { nil, nil, false } },
  [1412] = { "Mulgore", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1454] = { "Orgrimmar", "city" },
  [1451] = { "Silithus", era = { 55, 60, false }, forever = { nil, nil, false } },
  [1442] = { "Stonetalon Mountains", era = { 15, 27, false }, forever = { nil, nil, false } },
  [1446] = { "Tanaris", era = { 40, 50, false }, forever = { nil, nil, false } },
  [1438] = { "Teldrassil", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1413] = { "The Barrens", era = { 10, 25, false }, forever = { nil, nil, false } },
  [1441] = { "Thousand Needles", era = { 25, 35, false }, forever = { nil, nil, false } },
  [1456] = { "Thunder Bluff", "city" },
  [1449] = { "Un'Goro Crater", era = { 48, 55, false }, forever = { nil, nil, false } },
  [1452] = { "Winterspring", era = { 55, 60, false }, forever = { nil, nil, false } },
  -- Eastern Kingdoms
  [1416] = { "Alterac Mountains", era = { 30, 40, false }, forever = { nil, nil, false } },
  [1417] = { "Arathi Highlands", era = { 30, 40, false }, forever = { nil, nil, false } },
  [1418] = { "Badlands", era = { 35, 45, false }, forever = { nil, nil, false } },
  [1419] = { "Blasted Lands", era = { 45, 55, false }, forever = { nil, nil, false } },
  [1428] = { "Burning Steppes", era = { 50, 58, false }, forever = { nil, nil, false } },
  [1430] = { "Deadwind Pass", era = { 55, 60, false }, forever = { nil, nil, false } },
  [1426] = { "Dun Morogh", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1431] = { "Duskwood", era = { 18, 30, false }, forever = { nil, nil, false } },
  [1423] = { "Eastern Plaguelands", era = { 53, 60, false }, forever = { nil, nil, false } },
  [1429] = { "Elwynn Forest", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1424] = { "Hillsbrad Foothills", era = { 20, 30, false }, forever = { nil, nil, false } },
  [1455] = { "Ironforge", "city" },
  [1432] = { "Loch Modan", era = { 10, 20, false }, forever = { nil, nil, false } },
  [1433] = { "Redridge Mountains", era = { 15, 25, false }, forever = { nil, nil, false } },
  [1427] = { "Searing Gorge", era = { 43, 50, false }, forever = { nil, nil, false } },
  [1421] = { "Silverpine Forest", era = { 10, 20, false }, forever = { nil, nil, false } },
  [1453] = { "Stormwind City", "city" },
  [1434] = { "Stranglethorn Vale", era = { 30, 45, false }, forever = { nil, nil, false } },
  [1435] = { "Swamp of Sorrows", era = { 35, 45, false }, forever = { nil, nil, false } },
  [1425] = { "The Hinterlands", era = { 40, 50, false }, forever = { nil, nil, false } },
  [1420] = { "Tirisfal Glades", era = { 1, 10, false }, forever = { nil, nil, false } },
  [1458] = { "Undercity", "city" },
  [1422] = { "Western Plaguelands", era = { 51, 58, false }, forever = { nil, nil, false } },
  [1436] = { "Westfall", era = { 10, 20, false }, forever = { nil, nil, false } },
  [1437] = { "Wetlands", era = { 20, 30, false }, forever = { nil, nil, false } },
  -- Forever only: zones Classic Era does not have (map ids from Data/ForeverZones.lua of PanoplySuite_QuestData; their ranges stay blank until
  -- somebody supplies them: that table carries no level range for them)
  [2482] = { "Mount Hyjal", forever = { nil, nil, false } },
  [2548] = { "Riverglades", forever = { nil, nil, false } },
  [2521] = { "Zephras Isle", forever = { nil, nil, false } },
  [2524] = { "Darkspear Islands", forever = { nil, nil, false } },   -- the client table calls this map a battleground (pvp); no zone exit leads to it
  [2652] = { "Shen'dralas", forever = { nil, nil, false } },
}

-- Zephras Isle has two maps in Panoply Suite's data (one area, two UiMaps: Data/ForeverZones.lua of PanoplySuite_QuestData); the second one has no row
-- of its own and reads the first one's.
Z.SAME = { [2665] = 2521 }

-- The client in use: "era" or "forever" (anything else, an unsupported game, has no ranges at all).
function Z.Client()
  local C = Panoply.Compat
  return C and C.Flavor and C.Flavor() or nil
end

-- the row of a map for a client (default: the client in use), or nil when the client has no such zone: { name, low, high, checked, city }.
-- A city is a row of both clients. `checked` is true only for a slot somebody checked that holds a whole range.
function Z.Row(map, client)
  local r = Z.ROWS[Z.SAME[map] or map]
  if type(r) ~= "table" then return nil end
  if r[2] == "city" then return { name = r[1], city = true } end
  client = client or Z.Client()
  local slot = (client == "era" or client == "forever") and r[client] or nil
  if type(slot) ~= "table" then return nil end
  return { name = r[1], low = slot[1], high = slot[2], checked = slot[3] == true and slot[1] ~= nil and slot[2] ~= nil }
end

-- the checked range of a map: low, high; nil when the map has no row on this client, is a city, or its range has not been checked yet
function Z.Range(map, client)
  local r = Z.Row(map, client)
  if r and r.checked and r.low and r.high then return r.low, r.high end
  return nil
end

function Z.IsCity(map, client)
  local r = Z.Row(map, client)
  return r ~= nil and r.city == true
end

-- the words for a map's range: "10 to 20", "City", or nil (an unchecked range, or no row on this client, says nothing)
function Z.Words(map, client)
  if Z.IsCity(map, client) then return "City" end
  local lo, hi = Z.Range(map, client)
  if lo then return lo == hi and tostring(lo) or (lo .. " to " .. hi) end
  return nil
end

-- where a player of this level stands against a zone: "below" (the zone is below you), "in" (your level is in its range), "above" (the zone
-- is above you), or nil when the zone has no checked range here (a city, or a range nobody has checked)
function Z.Standing(map, level, client)
  local lo, hi = Z.Range(map, client)
  level = tonumber(level)
  if not (lo and level) then return nil end
  if level > hi then return "below" end
  if level < lo then return "above" end
  return "in"
end

-- the maps whose range for a client nobody has checked yet (for the sheet and the tests): list of uiMap ids, sorted; cities and the zones
-- the client does not have are not in it
function Z.Unchecked(client)
  client = client or Z.Client()
  local out = {}
  for m, r in pairs(Z.ROWS) do
    if type(r) == "table" and r[2] ~= "city" and type(r[client]) == "table" and r[client][3] ~= true then out[#out + 1] = m end
  end
  table.sort(out)
  return out
end
