-- Map module: Panoply Suite's world map improvements and instance maps, in one place.
--   Window.lua     follow my zone, dim the map, move / size / reset (the game's own map window)
--   Bar.lua        the toolbar on the map: zone jump menu, level range, coordinates, Layers menu, Dungeons
--   Icons.lua      info icons (dungeon and raid entrances, graveyards) and connections (zone exits, boats, zeppelins, the tram,
--                  portals, flight points known and not seen yet)
--   Instances.lua  the instance map window: every dungeon and raid, facts, floor plan, numbered bosses
-- Written from plain public feature descriptions (MATCH-LIST.md: map add-on and instance-map add-on
-- sections) and the game's own data. No code, art or data of any other add-on was read or used.
--
-- Rules this module keeps (SPEC 19.3 taint notes, CLAUDE.md hard rules 2, 3, 7):
--   * It never replaces a game function. The game's world map is only followed with hooksecurefunc /
--     HookScript, and our own frames are children of it (the same way Trail and Quest icons draw).
--   * Nothing here touches the game's map window in combat; changes wait for PLAYER_REGEN_ENABLED.
--   * Everything it draws sits UNDER the route trail and the quest pins (C.WorldMapLevel), so the
--     route stays the clearest thing on the map. The guide parts (trail, route card, quest icons) have
--     their own switches; this module has no guide parts and keeps working when they are off.
local ADDON, Panoply = ...
local C = Panoply.Compat

local M = Panoply.Modules:Register({
  key = "map", label = "Map", icon = "Map",
  desc = "Zone jump menu, coordinates, entrances, flight points and boats on the world map, and a map of every dungeon and raid.",
  defaults = {
    mapBar = true,               -- the toolbar on the world map
    mapCoords = true,            -- your and the cursor's coordinates (in the toolbar)
    mapFollow = true,            -- switch the map to the zone you travel into
    mapDim = 0,                  -- dim the map art under our icons and the route (0 = off, up to 0.6)
    mapScale = 1,                -- 1 = leave the game's own map size alone
    -- Info icons (how big, how solid and what colour: Map page > Look of the map > Info icons)
    mapEntrances = true,         -- dungeon and raid entrances
    mapGraves = false,           -- graveyards (spirit healers)
    -- Connections (Step 2 item E; how big, how solid, names and colour: Look of the map > Connections)
    mapExits = true,             -- an arrow chip where a road leaves the zone, with the next zone's name and level range
    mapBoats = true,             -- boats
    mapZeppelins = true,         -- zeppelins
    mapTram = true,              -- the Deeprun Tram
    mapPortals = true,           -- portals (Rut'theran Village and Darnassus)
    mapFlight = true,            -- flight points you know
    mapFlightUnseen = true,      -- flight points not seen at a flight master yet (dimmed, with a "?")
    mapPos = {},                 -- where the player dragged the map window to ("max" / "win" = { point, relPoint, x, y })
    mapInstFilter = "all",       -- instance window: all, dungeon, raid, level
  },
})
Panoply.Map = M

-- Places (Places.lua draws them, Navigate.lua finds them): every kind of place is ONE setting, and that setting is what both the Places
-- menu on the map toolbar (Bar.lua) and the Map page's Places section (UI/Catalog.lua) read and write, so the two cannot disagree. How big,
-- how solid and what colour they are is the Look of the map's "Places" (below). `dest` is how the Go to window names the nearest one,
-- `icon` the game's own tracking icon drawn for it (Interface\Minimap\Tracking\<icon>: UNVERIFIED in a real client), `alias` extra words
-- the search matches. Trainers and services are on, vendors and stations off (cities get too busy). Outdoors (0.8.4): rare creatures on,
-- camp sites off (a zone has dozens of fires).
M.PLACE_GROUPS = {
  { id = "trainers", head = "TRAINERS" }, { id = "services", head = "SERVICES" },
  { id = "vendors", head = "VENDORS" }, { id = "stations", head = "STATIONS" },
  { id = "outdoors", head = "OUTDOORS" },      -- 0.8.4 map extras: rare creatures and camp sites (Extras.lua)
  { id = "yours", head = "FROM YOUR PAGES" },  -- 0.9.5 phase 4K (spec 05b 1.4): places other pages of Panoply Suite know (Places.lua P.DYNAMIC)
}
M.PLACE_TYPES = {
  { key = "placeTrainClass", group = "trainers", label = "Class trainers", default = true, icon = "Class", dest = "Class trainer",
    tip = "Where your class trainer stands. Turn on \"Show all classes\" to see every class's trainer." },
  { key = "placeTrainProf", group = "trainers", label = "Profession trainers", default = true, icon = "Profession", dest = "Profession trainer",
    tip = "Trainers for every profession, including Cooking, Fishing and First Aid." },
  { key = "placeTrainPet", group = "trainers", label = "Pet trainers", default = true, icon = "Class", dest = "Pet trainer",
    tip = "Hunter pet trainers." },
  { key = "placeTrainDemon", group = "trainers", label = "Demon trainers", default = true, icon = "Class", dest = "Demon trainer",
    tip = "Warlock demon trainers." },
  { key = "placeTrainPortal", group = "trainers", label = "Portal trainers", default = true, icon = "Class", dest = "Portal trainer",
    tip = "Mage trainers who teach the city portal spells. Not the portals between places: those are under Connections." },
  { key = "placeTrainWeapon", group = "trainers", label = "Weapon masters", default = true, icon = "Class", dest = "Weapon master", alias = "weapon trainer",
    tip = "Where you learn weapon skills." },
  { key = "placeTrainRiding", group = "trainers", label = "Riding trainers", default = true, icon = "Class", dest = "Riding trainer",
    tip = "Where you learn to ride and buy your mount's skill." },
  { key = "placeMail", group = "services", label = "Mailboxes", default = true, icon = "Mailbox", dest = "Mailbox", alias = "mail",
    tip = "Mailboxes your side can use." },
  { key = "placeInn", group = "services", label = "Innkeepers", default = true, icon = "Innkeeper", dest = "Innkeeper", alias = "inn tavern",
    tip = "Innkeepers: where you set your hearthstone and rest." },
  { key = "placeAuction", group = "services", label = "Auction houses", default = true, icon = "Auctioneer", dest = "Auction house", alias = "ah auctioneer",
    tip = "Auctioneers." },
  { key = "placeBank", group = "services", label = "Bankers", default = true, icon = "Banker", dest = "Bank", alias = "banker",
    tip = "Bankers." },
  { key = "placeGuild", group = "services", label = "Guild masters", default = true, icon = "Class", dest = "Guild master",
    tip = "Guild masters: where you start a guild." },
  { key = "placeStable", group = "services", label = "Stable masters", default = true, icon = "StableMaster", dest = "Stable master", alias = "stables",
    tip = "Stable masters." },
  { key = "placeRepair", group = "services", label = "Repair vendors", default = true, icon = "Repair", dest = "Repair vendor", alias = "repair armorer blacksmith",
    tip = "Vendors who repair your gear." },
  { key = "placeVTrade", group = "vendors", label = "Trade goods", default = false, icon = "Reagents", dest = "Trade goods vendor",
    tip = "Vendors of trade goods." },
  { key = "placeVProf", group = "vendors", label = "Profession supplies", default = false, icon = "Profession", dest = "Profession supplies",
    tip = "Vendors of profession supplies, such as Alchemy or Tailoring supplies." },
  { key = "placeVReagent", group = "vendors", label = "Reagents", default = false, icon = "Reagents", dest = "Reagent vendor",
    tip = "Reagent vendors." },
  { key = "placeVAmmo", group = "vendors", label = "Ammunition", default = false, icon = "Ammunition", dest = "Ammunition vendor",
    tip = "Vendors of arrows and bullets (found by their title)." },
  { key = "placeVFood", group = "vendors", label = "Food and drink", default = false, icon = "Food", dest = "Food and drink vendor",
    tip = "Vendors of food and drink (found by their title)." },
  { key = "placeVPoison", group = "vendors", label = "Poisons", default = false, icon = "Poisons", dest = "Poison vendor",
    tip = "Poison vendors." },
  { key = "placeAnvil", group = "stations", label = "Anvils", default = false, icon = "Repair", dest = "Anvil",
    tip = "Anvils, for Blacksmithing and Engineering." },
  { key = "placeForge", group = "stations", label = "Forges", default = false, icon = "Repair", dest = "Forge",
    tip = "Forges, for smelting ore and for Blacksmithing." },
  -- 0.8.4 map extras (Extras.lua, Rares.lua). `tex` is a whole texture path of the game's own (UNVERIFIED in a real client, like `icon`).
  { key = "placeRare", group = "outdoors", label = "Rare creatures", default = true, icon = "Class", dest = "Rare creature", alias = "rares rare spawn",
    tex = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    tip = "Where each rare creature of the zone can appear. Hover one for its level and when you last saw it." },
  { key = "placeCamp", group = "outdoors", label = "Camp sites", default = false, icon = "Food", dest = "Camp site", alias = "campfire camp fire cooking fire cook",
    tex = "Interface\\Icons\\Spell_Fire_Fire",
    tip = "Camp sites: fires you can cook at, so you need not light your own. Fires that stand together are one camp." },
  -- 0.9.5 phase 4K (spec 05b 1.4): four kinds fed by other pages, not by the world database's NPC table (Places.lua P.DYNAMIC says
  -- where each one's places come from). `only` hides a kind where it means nothing (a kind that is hidden draws nothing, is not in the
  -- Places menu and not on the Map page). `slot` is the icon slot (UI/KitParts.lua); `tex` the picture when the slot resolves to nothing.
  { key = "placeBeastTame", group = "yours", label = "Beasts to tame", default = true, dest = "Beast to tame", alias = "tame pet beast hunter",
    slot = "icon.layer.beasts", tex = "Interface\\Icons\\Ability_Hunter_BeastTaming", only = function() return M.IsHunter() end, owner = "class",
    tip = "The beasts your pet plan still needs (the To tame list of the Class page's Pet tab), at the place nearest you." },
  { key = "placeBlueprint", group = "yours", label = "Blueprint sources", default = true, dest = "Blueprint source", alias = "blueprint camp boss drop",
    slot = "icon.layer.blueprints", tex = "Interface\\Icons\\INV_Scroll_03", only = function() return C.IsForever() end, owner = "professions",
    tip = "The dungeons whose bosses drop camp Blueprints, at the dungeon's door. Hover one for which Blueprints and which bosses." },
  { key = "placeTradeCamp", group = "yours", label = "Trade camps", default = true, dest = "Trade camp", alias = "trade camp favor writ crate commerce supply",
    slot = "icon.layer.tradecamps", tex = "Interface\\Icons\\INV_Misc_Coin_01", only = function() return C.IsForever() end, owner = "professions",
    tip = "The Azeroth Commerce Authority and Durotar Supply and Logistics camps." },
  { key = "placeDeath", group = "yours", label = "Where I died", default = false, dest = "Where I died", alias = "death died corpse",
    slot = "icon.layer.deaths", tex = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", owner = "misc",
    tip = "Where this character died, from the Field Kit's death log (the newest 20). Your corpse arrow after a death is separate and stays as it is." },
}
-- the player is a Hunter (the Beasts to tame kind is theirs only)
function M.IsHunter()
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  return type(info.classFile) == "string" and info.classFile:upper() == "HUNTER"
end
-- a kind of place that means something on this character and this game (Places menu, Map page, drawing)
function M.KindOK(t)
  if type(t) == "string" then t = M.PLACE_BY_KEY and M.PLACE_BY_KEY[t] end
  if not t then return false end
  if t.only then local ok, v = pcall(t.only) return ok and v and true or false end
  return true
end
-- the icon slots of the fed kinds (spec 05 section 7, icon.layer.*): Panoply's theme has no drawing for them, so each is the game's own
-- picture (the kind's `tex`), listed by Kit.IconReport like every other slot
if Panoply.Kit and Panoply.Kit.RegisterIcon then
  for _, t in ipairs(M.PLACE_TYPES) do
    if t.slot and t.tex and not (Panoply.Kit.ICONS and Panoply.Kit.ICONS[t.slot]) then Panoply.Kit.RegisterIcon(t.slot, { game = { t.tex } }) end
  end
end
M.PLACE_BY_KEY = {}
for _, t in ipairs(M.PLACE_TYPES) do
  M.PLACE_BY_KEY[t.key] = t
  Panoply.defaults.account[t.key] = t.default
end
-- the class trainers: your own class's only, or every class's
Panoply.defaults.account.placeClassAll = false
-- 0.9.5 phase 4K (spec 05b 1.3 Display): the places on the minimap, all kinds together (new key; on, as before)
Panoply.defaults.account.placeMinimap = true
M.PLACE_KEYS = {}
for _, t in ipairs(M.PLACE_TYPES) do M.PLACE_KEYS[#M.PLACE_KEYS + 1] = t.key end
M.PLACE_KEYS[#M.PLACE_KEYS + 1] = "placeClassAll"
M.PLACE_KEYS[#M.PLACE_KEYS + 1] = "placeMinimap"

M.DIM_MAX, M.SCALE_MIN, M.SCALE_MAX = 0.6, 0.6, 1.4

-------------------------------------------------------------------------------
-- Small safe helpers
-------------------------------------------------------------------------------
local function pcallv(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if r[1] then return unpack(r, 2) end
  return nil
end
M.pc = pcallv

local function opt(key)
  local v = Panoply.db and Panoply.db[key]
  return v
end
function M.Opt(key) return opt(key) end

-- clamp a saved number to a range (a bad saved value gives the default)
function M.Num(key, lo, hi, def)
  local v = tonumber(opt(key))
  if not v or v ~= v then v = def end
  return math.max(lo, math.min(hi, v))
end

-- Run now, or when combat ends (one slot per key, newest wins).
M.pending = {}
function M:Later(key, fn)
  if C.InCombat() then self.pending[key] = fn return false end
  fn()
  return true
end
function M:RunPending()
  local list = self.pending
  self.pending = {}
  for _, fn in pairs(list) do local ok, err = pcall(fn) if not ok then Panoply:Debug("map pending", err) end end
end

-- Is this feature on right now?
function M:Wants(feature)
  if not self.active then return false end
  return true
end

-------------------------------------------------------------------------------
-- The game's map window
-------------------------------------------------------------------------------
function M:Shown()
  local wm = C.WorldMap()
  return wm and wm.IsShown and wm:IsShown() and true or false
end

-- the world position of the player's zone, if any (nil inside instances)
function M:PlayerMap()
  local m = C.GetPlayerPos()
  return m
end

-- the highest of the game's own map-art levels (explored art, fog, highlights); anything of ours above
-- this is drawn over the picture
function M:ArtLevel()
  local wm = C.WorldMap()
  local mgr = wm and wm.GetPinFrameLevelsManager and pcallv(wm.GetPinFrameLevelsManager, wm)
  local art = 0
  if type(mgr) == "table" and mgr.GetValidFrameLevel then
    for _, t in ipairs(C.MAP_LEVEL_ART) do
      local v = tonumber(C.Readable(pcallv(mgr.GetValidFrameLevel, mgr, t)))
      if v and v > art then art = v end
    end
  end
  if art == 0 then art = C.MAP_LEVEL_FALLBACK - 1 end
  return art
end

-- frame level for our icon layer: above the map art and the dimmer, below the route trail and the quest pins
function M:IconLevel()
  local trail = C.WorldMapLevel("trail")
  local lvl = math.max(self:ArtLevel() + 2, trail - 3)
  if lvl >= trail then lvl = math.max(1, trail - 1) end
  return lvl
end

-- frame level of every mark (and so, one above it, of the words and the chip that hang from it): ONE level for all of them, two under the
-- trail, so a mark and its words are strictly under the route trail and the quest pins above it however many marks there are (the first
-- build gave each mark its own level, up to twenty above the layer, which put marks over the trail and the quest icons: an exit chip took the
-- click where the trail leaves a zone). The layer itself is one level under, the hover lines on it.
function M:MarkLevel(layerLevel)
  local trail = C.WorldMapLevel("trail")
  return math.max(layerLevel or 1, trail - 2)
end

-- The one hand-off from a map icon or the instance window to the arrow: a waypoint (the Waypoints
-- module), or the arrow itself; the route plans to it either way. Nothing else happens.
-- src (0.9.5 phase 4K): the Map page's waypoint group (Waypoints.lua W.GROUPS); none = Mine
function M:PointAt(map, x, y, label, src)
  local Way = Panoply.Waypoints
  local done = false
  if Way and Panoply.Modules:IsOn("waypoints") and Way.Add then
    Way:Add(map, x, y, label, nil, src or "mine")
    done = true
  elseif Panoply.Arrow and not Panoply:PlayAlong() then
    Panoply.Arrow:PointAt(map, x, y, label)
    done = true
  end
  if done and Panoply.Arrow and Panoply.Arrow.Retarget and not Panoply:PlayAlong() then Panoply.Arrow:Retarget() end
  self.lastPoint = done and { map = map, x = x, y = y, label = label } or nil
  return done
end

-------------------------------------------------------------------------------
-- One refresh for everything that follows the map window
-------------------------------------------------------------------------------
function M:Changed(why)
  if not self.active then return end
  if self.Window then self.Window:Apply(why) end
  if self.Bar then self.Bar:Refresh(why) end
  if self.Icons then self.Icons:Refresh(why) end
  if self.Places then self.Places:Refresh(why) end
  if self.Spots then self.Spots:Refresh(why) end
  if self.Favorites then self.Favorites:Refresh(why) end
  if self.Fog then self.Fog:Refresh(why) end
  if self.Find then self.Find:Refresh(why) end
end

function M:HookMap()
  if self.hooked then return end
  local wm = C.WorldMap()
  if not wm then return end
  self.hooked = true
  if wm.HookScript then
    wm:HookScript("OnShow", function() M:OnShow() end)
    wm:HookScript("OnHide", function() M:OnHide() end)
  end
  for _, name in ipairs({ "OnMapChanged", "Maximize", "Minimize", "SynchronizeDisplayState" }) do
    C.Hook(wm, name, function() M:Changed(name) end)
  end
end

function M:OnShow()
  if not self.active then return end
  self.shownAt = C.GetTime()
  self.lastPlayerMap = self:PlayerMap()
  self:Changed("show")
  -- the game lays the window out in the same breath; apply ours again one tick later
  C.After(0, function() if M.active and M:Shown() then M:Changed("show2") end end)
end

function M:OnHide()
  if self.Bar then self.Bar:Hide() end
  if self.Window then self.Window:OnHide() end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
M:On("ZONE_CHANGED_NEW_AREA", function()
  if M.Window then M.Window:Follow() end
  if M.Icons then M.Icons:Refresh("zone") end
  if M.Instances then M.Instances:OnZone(true) end   -- dungeon helper: a second look at which instance this is
end)
M:On("PLAYER_ENTERING_WORLD", function()
  if M.Window then M.Window:Follow() end
  if M.Instances then M.Instances:OnZone() end
  M:Changed("world")
end)
M:On("PLAYER_REGEN_ENABLED", function() M:RunPending() end)

function M:Enable()
  self:HookMap()
  if self.Window then self.Window:Enable() end
  if self.Instances then self.Instances:Enable() end
  if self.Places then self.Places:Enable() end
  if self.Favorites then self.Favorites:Enable() end
  self:Changed("enable")
end

function M:Disable()
  if self.Window then self.Window:Disable() end
  if self.Bar then self.Bar:Hide() end
  if self.Icons then self.Icons:Disable() end
  if self.Places then self.Places:Disable() end
  if self.Spots then self.Spots:Disable() end
  if self.Favorites then self.Favorites:Disable() end
  if self.Fog then self.Fog:Disable() end
  if self.Find then self.Find:Disable() end
  if self.Navigate then self.Navigate:Hide() end
  if self.Instances then self.Instances:Disable() end
end

-- Info icons and Connections (Step 2 item E) are two things of the Look of the map (Map page, Core/Look.lua): how big, how solid and what
-- colour they are on the world map, and for Connections whether their names show all the time or only on hover. The minimap does not draw
-- them (our decision 10), so each has a World map column only. The preview in the gear is drawn by Icons.lua from the same numbers.
Panoply.Look.AddThing({ id = "info", prefix = "info", name = "Info icons", short = "Info icons", module = "map", maps = { "wm" },
  words = "info icons dungeon raid entrances door instance spirit healer graveyard graveyards",
  controls = { wm = { "size", "alpha", "colour" } },
  group = { first = { { id = "kind", name = "By kind" } }, palette = Panoply.Look.SIX, default = "kind" } })
Panoply.Look.AddThing({ id = "conn", prefix = "conn", name = "Connections", short = "Connections", module = "map", maps = { "wm" },
  words = "connections zone exit exits border boat boats zeppelin zeppelins tram portal portals flight flights flight point path",
  controls = { wm = { "size", "alpha", "names", "colour" } },
  group = { first = { { id = "kind", name = "By kind" } }, palette = Panoply.Look.SIX, default = "kind" } })

-- Places (Step 3 map slice): the places on the world map and the minimap are one more thing of the Look of the map, with a World map and a
-- Minimap column: size, opacity and colour like the other custom icons. By kind keeps the game's own icon of each place.
Panoply.Look.AddThing({ id = "place", prefix = "place", name = "Places", short = "Places", module = "map", maps = { "wm", "mm" },
  words = "places trainers trainer services vendors stations innkeeper inn banker bank auction house mailbox stable repair anvil forge weapon master riding pet demon portal",
  controls = { wm = { "size", "alpha", "colour" }, mm = { "size", "alpha", "colour" } },
  group = { first = { { id = "kind", name = "By kind" } }, palette = Panoply.Look.SIX, default = "kind" } })

-- Settings that change what is on the map redraw it.
-- the settings the minimap's "Connections" quick switch turns on and off together
M.CONNECTION_KEYS = { "mapExits", "mapBoats", "mapZeppelins", "mapTram", "mapPortals", "mapFlight", "mapFlightUnseen" }
M.KEYS = { "mapBar", "mapCoords", "mapFollow", "mapDim", "mapScale", "mapEntrances", "mapGraves", "mapExits", "mapBoats", "mapZeppelins",
  "mapTram", "mapPortals", "mapFlight", "mapFlightUnseen" }
-- "mapSpots" (Saved spots on the map, Spots.lua) is not one of these: it is the Layers menu's own switch, not part of a profile
for _, k in ipairs(M.PLACE_KEYS) do M.KEYS[#M.KEYS + 1] = k end
local function redraw(k) return function() if M.active then M:Changed("option") end end end
for _, k in ipairs(M.KEYS) do Panoply.optionHooks[k] = redraw(k) end
for _, k in ipairs(Panoply.Look.AllKeys()) do
  local info = Panoply.Look.KeyInfo(k)
  if info and (info.thing == "info" or info.thing == "conn" or info.thing == "place") then Panoply.optionHooks[k] = redraw(k) end
end
-- every key a profile holds for the Map module: its settings and the controls of its two things in the Look of the map
function M.ProfileKeys()
  local out = {}
  for _, k in ipairs(M.KEYS) do out[#out + 1] = k end
  for _, k in ipairs(Panoply.Look.AllKeys()) do
    local info = Panoply.Look.KeyInfo(k)
    if info and (info.thing == "info" or info.thing == "conn" or info.thing == "place") then out[#out + 1] = k end
  end
  return out
end
-- a profile holds the Map module's settings (the Look keys of the two things are added by Panoply.Look.AddThing; the dragged window places
-- are not part of a layout, like the arrow's place)
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys(M.KEYS) end

-- Status for the settings page and /panoply map.
function M:Report()
  return {
    active = self.active,
    bar = self.Bar and self.Bar.frame and self.Bar.frame:IsShown() or false,
    icons = self.Icons and self.Icons.shown or 0,
  }
end

-- The settings. The rows are found by key (the Map page's gear, UI/Catalog.lua, and the All settings box); the labels here are the ones
-- the Layers menu on the map shows too. The sizes, opacities, colours and names of the info icons and the connections are rows of the
-- Look of the map (Panoply.Look.Rows), added below.
M.options = {
  { type = "check", key = "mapBar", label = "Show the map toolbar", tip = "A strip along the bottom of the world map: the zone menu, the zone's level range, your coordinates and the cursor's, the Layers menu and the Dungeons button." },
  { type = "check", key = "mapCoords", label = "Show coordinates", tip = "Your position and the cursor's, in the toolbar.", parent = "mapBar", indent = true },
  { type = "check", key = "mapFollow", label = "Follow my zone", tip = "While the map is open, it follows you when you cross into a new zone. It stays where it is if you were looking at another zone." },
  { type = "slider", key = "mapDim", label = "Dim the map", min = 0, max = M.DIM_MAX, step = 0.05, tip = "A flat dark wash over the map's own picture, under every icon and the route, so they read better. 0% is off. The route trail and your pins are not dimmed." },
  { type = "slider", key = "mapScale", label = "Map window size", min = M.SCALE_MIN, max = M.SCALE_MAX, step = 0.05, tip = "100% leaves the game's own size alone. Drag the grip at the left end of the toolbar to move the map." },
  { type = "check", key = "mapEntrances", label = "Dungeon and raid entrances", tip = "Hover for the dungeon's level range and size. Click to point the arrow at the door; right-click to open its map." },
  { type = "check", key = "mapGraves", label = "Graveyards", tip = "Where the spirit healers stand." },
  { type = "check", key = "mapExits", label = "Zone exits", tip = "On a zone map, an arrow where a road leaves the zone, with the next zone's name and its level range." },
  { type = "check", key = "mapBoats", label = "Boats", tip = "A dock icon at both ends of every boat, with where it goes." },
  { type = "check", key = "mapZeppelins", label = "Zeppelins", tip = "A tower icon at both ends of every zeppelin, with where it goes." },
  { type = "check", key = "mapTram", label = "Trams", tip = "The Deeprun Tram's two ends, in Stormwind and Ironforge." },
  { type = "check", key = "mapPortals", label = "Portals", tip = "The portals between Rut'theran Village and Darnassus, at both ends." },
  { type = "check", key = "mapFlight", label = "Flight points you know", tip = "The flight masters whose flight path Panoply Suite has seen on your list. Hover one to see its flights." },
  { type = "check", key = "mapFlightUnseen", label = "Flight points not seen yet", tip = "The other flight masters, dimmed with a question mark. Panoply Suite only learns a flight path when you open a flight master's map." },
}
M.options[#M.options + 1] = { type = "check", key = "mapSpots", label = "Saved spots",
  tip = "The places you saved yourself, as stars on the world map. Shift-right-click the map to save one; the Go to window lists them." }
-- the Places: one switch for each kind of place (the Places menu on the toolbar writes these same keys), then the class trainers' own switch
for _, t in ipairs(M.PLACE_TYPES) do
  M.options[#M.options + 1] = { type = "check", key = t.key, label = t.label, tip = t.tip }
end
M.options[#M.options + 1] = { type = "check", key = "placeClassAll", label = "Show all classes", parent = "placeTrainClass", indent = true,
  tip = "Class trainers of every class. Off: only your own class's trainers." }
M.options[#M.options + 1] = { type = "check", key = "placeMinimap", label = "Places on the minimap",
  tip = "The places that are switched on, on the minimap too. Off: on the world map only." }
for _, id in ipairs({ "info", "conn", "place" }) do for _, r in ipairs(Panoply.Look.Rows(id)) do M.options[#M.options + 1] = r end end
