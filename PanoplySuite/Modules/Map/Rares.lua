-- Map module, RARE SIGHTINGS (0.8.4): remembers when and where you last saw each rare creature, shows it in the rare's tooltip on the maps
-- (the rare creatures are a kind of place: Map.lua M.PLACE_TYPES "placeRare", Extras.lua lists them from the data), and can tell you when
-- one is near. The alert is OFF unless the player turns it on.
--
--   * A rare is noticed when the game shows it to you: you target it, your mouse passes over it, or its nameplate appears. A creature
--     counts when the game calls it rare (or rare elite), or when the data lists it as one. Nothing is scanned, targeted or searched for:
--     this file only reads what the game has just shown (hub rule 2 of CLAUDE.md), so there is no automation of any kind here.
--   * A sighting is saved for the whole account (Panoply.db.rareSightings; on WoW Forever Panoply.db.rareSightingsForever, because a spot on a
--     re-drawn zone map is not the same spot on Classic Era's): { t = when, map, x, y = where YOU stood, n = how many times, name, lvl,
--     elite }. It is the player's own record, not a setting: no profile holds it and no settings reset clears it.
--   * /panoply rares lists the rares of the zone you are in with when you last saw each.
local ADDON, Panoply = ...
local C, M = Panoply.Compat, Panoply.Map
local floor = math.floor

local R = {}
M.Rares = R
R.CLASS = { rare = true, rareelite = true }   -- what UnitClassification calls a rare
R.SAME_VISIT = 60          -- seconds: seeing it again this soon is the same sighting (the count does not go up)
R.ALERT_AGAIN = 300        -- seconds before the same rare is announced again
R.alerted = {}

Panoply.defaults.account.rareAlert = false       -- "Tell me when a rare creature is near": off unless the player turns it on

local function now() return (_G.time and _G.time()) or 0 end

-- the saved sightings of this client (made on first use)
function R:Store()
  local db = Panoply.db
  if type(db) ~= "table" then return nil end
  local key = C.IsForever() and "rareSightingsForever" or "rareSightings"
  if type(db[key]) ~= "table" then db[key] = {} end
  return db[key]
end

function R:Sighting(id)
  local s = self:Store()
  local e = s and s[id]
  return type(e) == "table" and e or nil
end

-- "just now", "5 minutes ago", "3 hours ago", "2 days ago"
function R.Ago(seconds)
  seconds = tonumber(seconds) or 0
  if seconds < 120 then return "just now" end
  if seconds < 7200 then return ("%d minutes ago"):format(floor(seconds / 60)) end
  if seconds < 172800 then return ("%d hours ago"):format(floor(seconds / 3600)) end
  return ("%d days ago"):format(floor(seconds / 86400))
end

-- the tooltip line of a rare: when it was last seen
function R:SeenText(id)
  local e = self:Sighting(id)
  if not (e and e.t) then return "You have not seen it yet." end
  local n = tonumber(e.n) or 1
  return ("Last seen %s%s."):format(R.Ago(now() - e.t), n > 1 and (" (seen %d times)"):format(n) or "")
end

-- one fact about a unit, or nil when the game will not say (no such function, an error, a secret value)
local function fact(fn, unit)
  local f = _G[fn]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, unit)
  if not ok then return nil end
  return C.Readable(v)
end

-- Is this unit a rare creature? Returns id, name, level, elite, dead; nil when it is not one or the game will not say what it is.
function R:Identify(unit)
  if type(unit) ~= "string" or fact("UnitExists", unit) == false then return nil end
  if fact("UnitPlayerControlled", unit) then return nil end          -- a hunter's tamed rare is a pet now
  local QD = Panoply.QuestData
  local id, kind
  if QD and QD.NpcIdFromGUID then id, kind = QD.NpcIdFromGUID(fact("UnitGUID", unit)) end
  if not id or kind ~= "npc" then return nil end
  local known = M.Extras and M.Extras:Rare(id)
  local class = fact("UnitClassification", unit)
  if not (known or R.CLASS[class]) then return nil end
  local name = fact("UnitName", unit)
  if type(name) ~= "string" or name == "" then name = known and known.name or nil end
  local level = tonumber(fact("UnitLevel", unit))
  if level and level <= 0 then level = nil end
  local elite = class == "rareelite" or (class == nil and known and known.elite) or false
  return id, name, level, elite, fact("UnitIsDead", unit) and true or false
end

-- write one sighting down; returns the record and whether it is a new visit
function R:Saw(id, name, level, elite)
  local store = self:Store()
  if not (store and type(id) == "number") then return nil end
  local t = now()
  local e = type(store[id]) == "table" and store[id] or {}
  local fresh = not e.t or t - e.t > R.SAME_VISIT
  local hadSpot = e.map ~= nil
  if fresh then e.n = (tonumber(e.n) or 0) + 1 end
  e.t = t
  local map, x, y = C.GetPlayerPos()
  if map and x and y then e.map, e.x, e.y = map, floor(x * 10000 + 0.5) / 10000, floor(y * 10000 + 0.5) / 10000 end
  if type(name) == "string" and name ~= "" then e.name = name end
  if level then e.lvl = level end
  e.elite = elite and true or nil
  store[id] = e
  -- a rare the data does not hold gets its mark where it was seen: the list of places is made again
  local known = M.Extras and M.Extras:Rare(id)
  if not known and e.map and (fresh or not hadSpot) and M.Places then
    M.Places.index = nil
    if M.active then M.Places:Refresh("rare") end
  end
  Panoply:Fire("RARE_SEEN", id, e, fresh)
  return e, fresh
end

function R:Alert(id, e)
  if not (Panoply.db and Panoply.db.rareAlert) then return false end
  local t = C.GetTime()
  if self.alerted[id] and t - self.alerted[id] < R.ALERT_AGAIN then return false end
  self.alerted[id] = t
  local name = e.name or "A rare creature"
  local what = (e.elite and "Rare elite" or "Rare") .. (e.lvl and (", level " .. e.lvl) or "")
  Panoply:Print(("Rare creature near you: %s (%s)."):format(name, what:lower()))
  if Panoply.Toast and Panoply.Toast.Show then Panoply.Toast:Show("Rare creature near you", name .. "\n" .. what) end
  return true
end

-- the game has just shown this unit: if it is a rare, remember it (and say so when the alert is on and it is alive)
function R:Check(unit)
  local id, name, level, elite, dead = self:Identify(unit)
  if not id then return nil end
  local e = self:Saw(id, name, level, elite)
  if e and not dead then self:Alert(id, e) end
  return id
end

M:On("PLAYER_TARGET_CHANGED", function() R:Check("target") end)
M:On("UPDATE_MOUSEOVER_UNIT", function() R:Check("mouseover") end)
M:On("NAME_PLATE_UNIT_ADDED", function(_, unit) R:Check(unit) end)

-------------------------------------------------------------------------------
-- The rares of a zone, for /panoply rares
-------------------------------------------------------------------------------
-- { { id, name, level = "Level 10", elite, seen = the sighting or nil } ... } by level, then name
function R:ZoneList(map)
  local out, have = {}, {}
  local P = M.Places
  for _, e in ipairs(P and map and P.Index().byMap[map] or {}) do
    if e.type == "placeRare" and e.id and not have[e.id] then
      have[e.id] = true
      local known = M.Extras and M.Extras:Rare(e.id)
      out[#out + 1] = { id = e.id, name = e.name, level = e.level, elite = e.sub == "Rare elite", seen = self:Sighting(e.id),
        sort = known and known.min or (self:Sighting(e.id) or {}).lvl or 0 }
    end
  end
  table.sort(out, function(a, b)
    if a.sort ~= b.sort then return a.sort < b.sort end
    return a.name < b.name
  end)
  return out
end

-- the lines /panoply rares prints
function R:Lines(map)
  map = map or C.GetPlayerPos()
  local zone = map and C.MapName(map)
  if not map then return { "Rare creatures: your zone is not known here (inside a dungeon, perhaps)." } end
  local list = self:ZoneList(map)
  if #list == 0 then return { ("No rare creatures are known in %s."):format(zone or "this zone") } end
  local lines = { ("Rare creatures of %s (%d):"):format(zone or "this zone", #list) }
  for _, r in ipairs(list) do
    local seen = r.seen and r.seen.t and ("last seen " .. R.Ago(now() - r.seen.t)) or "not seen yet"
    lines[#lines + 1] = ("  %s%s%s: %s"):format(r.name, r.level and (", " .. r.level:lower()) or "", r.elite and ", elite" or "", seen)
  end
  lines[#lines + 1] = Panoply.db and Panoply.db.rareAlert and "The nearby alert is on." or "The nearby alert is off. Turn it on in the Map page's settings (Places)."
  return lines
end

function R:Print(map) for _, l in ipairs(self:Lines(map)) do Panoply:Print(l) end end

M.options[#M.options + 1] = { type = "check", key = "rareAlert", label = "Tell me when a rare creature is near", parent = "placeRare", indent = true,
  tip = "A short notice and a chat line when the game shows you a rare creature: you target it, your mouse passes over it, or its nameplate appears. Off unless you turn it on. Nothing is targeted or searched for you." }
M.KEYS[#M.KEYS + 1] = "rareAlert"
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "rareAlert" }) end
