-- Map module, MAP FAVORITES (0.9.5 phase 4G, queue item 1): the places a player marks for themselves, with a type, a note and an icon,
-- shown as pins on the world map and the minimap and listed in the Favorites window (FavWindow.lua), opened from the map's Places menu.
--   * Kept in a NEW saved variable of its own, PanoplySuiteFavoritesDB (per account, shared by every character): { version = 1, nextId,
--     list = { { id, name, type, prof, note, icon, map, x, y, by, at, from } }, hide = { [type] = true }, migrated = { spots, chars } }.
--     No other saved variable is renamed or changed. Each favorite remembers who saved it (by = "Name-Realm"), so a character can show
--     only its own (Panoply.cdb.mapFavOnlyMine, per character).
--   * Migration, once, without deleting anything: the starred Saved spots (PanoplySuiteSpotsDB, account) and this character's Go to
--     Favourites (Panoply.cdb.placesFav) that have a position are COPIED in. Both old lists keep their data and their own sections, as we
--     decided on 2026-11-14 (favorites stay separate); each copy says where it came from (from = "spot:<id>" or "goto").
--   * Types: Vendor, Trainer (with a profession), Rare / hidden monster, Hidden spot, Treasure, Herb / ore node, Quest giver, Flight
--     master, Inn, Repair, Mailbox, Custom. The icon defaults from the type (a trainer of a profession gets that profession's icon) and
--     the player can pick any other. Every icon is a texture that ships with the game, named by its path; no art is shipped or copied.
--   * Share: one favorite or a set as a text line (PSF1:...:<check number>), read back with every field checked, the same way the custom
--     rotations share. A bad or changed line is refused in plain words and nothing is added.
-- No automatic movement: this file saves places and draws icons. A click points the arrow (or plans the trip); the player walks.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local floor, max, min, sqrt, abs = math.floor, math.max, math.min, math.sqrt, math.abs

local F = {}
M.Favorites = F
F.MAX = 500                 -- favorites on one account
F.NAME_MAX = 60             -- letters in a name
F.NOTE_MAX = 200            -- letters in a note
F.IMPORT_MAX = 200          -- favorites in one shared line
F.TEXT_MAX = 60000          -- the longest shared line read
F.PREFIX = "PSF1:"
F.WM_PX = 18                -- a world map pin at Size 100%
F.MM_PX = 14                -- a minimap pin at Size 100%
F.MM_CAP = 12               -- the closest this many on the minimap
F.MM_TICK = 0.5
F.SIZE_MIN, F.SIZE_MAX = 0.5, 2
local function size(key) local v = tonumber(Panoply.db and Panoply.db[key]) or 1 return math.max(F.SIZE_MIN, math.min(F.SIZE_MAX, v)) end
F.Size = size
F.rev = 0
F.shown, F.mmShown = 0, 0

Panoply.defaults.account.mapFavWM = true        -- pins on the world map
Panoply.defaults.account.mapFavMM = true        -- pins on the minimap
Panoply.defaults.account.mapFavLabels = false   -- the name under each pin on the world map
Panoply.defaults.account.mapFavWMSize = 1        -- how big the pins are on the world map (50% to 200%)
Panoply.defaults.account.mapFavMMSize = 1        -- and on the minimap
Panoply.defaults.char.mapFavOnlyMine = false    -- this character shows only the favorites it saved

local I = "Interface\\Icons\\"
local TR = "Interface\\Minimap\\Tracking\\"
-- the types, in the order the menus list them. icon: the default; the trainer's comes from its profession.
F.TYPES = {
  { key = "vendor", label = "Vendor", icon = I .. "INV_Misc_Bag_10" },
  { key = "trainer", label = "Trainer", icon = TR .. "Profession" },
  { key = "rare", label = "Rare / hidden monster", icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
  { key = "hidden", label = "Hidden spot", icon = I .. "INV_Misc_Spyglass_02" },
  { key = "treasure", label = "Treasure", icon = I .. "INV_Box_02" },
  { key = "node", label = "Herb / ore node", icon = I .. "INV_Ore_Copper_01" },
  { key = "quest", label = "Quest giver", icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
  { key = "flight", label = "Flight master", icon = I .. "Ability_Mount_Gryphon_01" },
  { key = "inn", label = "Inn", icon = TR .. "Innkeeper" },
  { key = "repair", label = "Repair", icon = TR .. "Repair" },
  { key = "mail", label = "Mailbox", icon = TR .. "Mailbox" },
  { key = "custom", label = "Custom", icon = I .. "INV_Misc_Map_01" },
}
F.TYPE = {}
for _, t in ipairs(F.TYPES) do F.TYPE[t.key] = t end
-- a trainer's profession, and its icon (the game's own profession icons; "Class" is a class trainer)
F.PROFS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring",
  "Cooking", "First Aid", "Fishing", "Class" }
F.PROF_ICON = {
  Alchemy = I .. "Trade_Alchemy", Blacksmithing = I .. "Trade_BlackSmithing", Enchanting = I .. "Trade_Engraving",
  Engineering = I .. "Trade_Engineering", Herbalism = I .. "Trade_Herbalism", Leatherworking = I .. "INV_Misc_ArmorKit_17",
  Mining = I .. "Trade_Mining", Skinning = I .. "INV_Misc_Pelt_Wolf_01", Tailoring = I .. "Trade_Tailoring", Cooking = I .. "INV_Misc_Food_15",
  ["First Aid"] = I .. "Spell_Holy_SealOfSacrifice", Fishing = I .. "Trade_Fishing", Class = TR .. "Class",
}
for _, p in ipairs(F.PROFS) do F.PROF_ICON[p:lower()] = F.PROF_ICON[p] end

-------------------------------------------------------------------------------
-- The saved list
-------------------------------------------------------------------------------
function F:DB()
  local db = _G.PanoplySuiteFavoritesDB
  -- the same table as last time, already tidied and migrated for this character: no walk over the list (the minimap asks twice a second)
  if db ~= nil and db == self.dbSeen and self.migrationDone then return db end
  if type(db) ~= "table" then db = {} _G.PanoplySuiteFavoritesDB = db end
  if type(db.list) ~= "table" then db.list = {} end
  if type(db.hide) ~= "table" then db.hide = {} end
  if type(db.migrated) ~= "table" then db.migrated = {} end
  if type(db.migrated.chars) ~= "table" then db.migrated.chars = {} end
  db.version = tonumber(db.version) or 1
  db.nextId = tonumber(db.nextId) or 1
  for _, f in ipairs(db.list) do
    if type(f) == "table" and type(f.id) == "number" and f.id >= db.nextId then db.nextId = f.id + 1 end
  end
  if not self.migrating then self:Migrate(db) end
  self.dbSeen = db
  self.migrationDone = Panoply.cdb ~= nil and F.Me() ~= nil      -- (one character a session: a new character is a new login)
  return db
end

local function whole(f)
  return type(f) == "table" and type(f.id) == "number" and type(f.name) == "string" and type(f.map) == "number"
    and type(f.x) == "number" and type(f.y) == "number" and f.x >= 0 and f.x <= 1 and f.y >= 0 and f.y <= 1
end
F.Whole = whole

-- "Name-Realm" of this character
function F.Me()
  local who = C.PlayerInfo() or {}
  return who.name and (who.name .. (who.realm and ("-" .. who.realm) or "")) or nil
end

-- a name or note as it is kept: no colour codes or links, single spaces, cut to its length. Returns the text and whether it was cut.
-- (a cut never leaves half of a letter of a non-English client: the bytes of an unfinished UTF-8 letter at the end go too)
local function utf8Whole(text)
  local tail = text:match("[\192-\247][\128-\191]*$")
  if not tail then return text end
  local lead = tail:byte(1)
  local want = lead >= 240 and 4 or (lead >= 224 and 3 or 2)
  if #tail < want then return text:sub(1, #text - #tail) end
  return text
end
function F.Clean(text, limit)
  text = tostring(text or ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local cut = false
  if limit and #text > limit then text = utf8Whole(text:sub(1, limit)):gsub("%s+$", "") cut = true end
  return text, cut
end

-- an icon as it is kept: a game texture path ("Interface\..."), or a number (a game file the icon picker offered). Anything else: nil.
function F.CleanIcon(icon)
  if type(icon) == "number" then return (icon > 0 and icon == floor(icon) and icon < 100000000) and icon or nil end
  if type(icon) ~= "string" then return nil end
  icon = icon:gsub("/", "\\")
  if #icon > 120 or not icon:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee]\\[%w_\\%-]+$") then return nil end
  return icon
end

local function round4(v) return floor(v * 10000 + 0.5) / 10000 end
local function typeKey(t) return F.TYPE[t or ""] and t or "custom" end
local function profName(p)
  if type(p) ~= "string" then return nil end
  for _, n in ipairs(F.PROFS) do if n:lower() == p:lower() then return n end end
  return nil
end

function F:TypeLabel(f)
  local t = F.TYPE[typeKey(f and f.type)]
  if t.key == "trainer" and f.prof then return f.prof == "Class" and "Class trainer" or (f.prof .. " trainer") end
  return t.label
end
function F.DefaultIcon(t, prof)
  t = typeKey(t)
  if t == "trainer" and prof and F.PROF_ICON[prof] then return F.PROF_ICON[prof] end
  if t == "flight" then
    local who = C.PlayerInfo() or {}
    if who.faction == "Horde" then return I .. "Ability_Mount_Wyvern_01" end
  end
  return F.TYPE[t].icon
end
function F:IconOf(f) return (f and f.icon) or F.DefaultIcon(f and f.type, f and f.prof) end

function F:Get(id)
  for _, f in ipairs(self:DB().list) do if whole(f) and f.id == id then return f end end
  return nil
end

function F:Count()
  local n = 0
  for _, f in ipairs(self:DB().list) do if whole(f) then n = n + 1 end end
  return n
end

local function changed()
  F.rev = F.rev + 1
  Panoply:Fire("FAVORITES_CHANGED")
end

-- "Elwynn Forest 45.2, 61.8"
function F:Where(f)
  return ("%s %.1f, %.1f"):format(C.MapName(f.map) or ("Map " .. tostring(f.map)), f.x * 100, f.y * 100)
end

-- the fields of a new or changed favorite, checked. t = { name, type, prof, note, icon, map, x, y } (x and y: 0..1 or 0..100).
-- Returns a clean table, or nil and a plain reason.
function F:Check(t)
  if type(t) ~= "table" then return nil, "Nothing to save." end
  local map, x, y = tonumber(t.map), tonumber(t.x), tonumber(t.y)
  if not map or not C.MapName(map) then return nil, "Panoply Suite does not know that zone." end
  if not (x and y) then return nil, "X and Y must be numbers, like 45.2 and 61.8." end
  if x > 1 or y > 1 then x, y = x / 100, y / 100 end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "X and Y must be between 0 and 100." end
  local name, cut = F.Clean(t.name, F.NAME_MAX)
  if name == "" then return nil, "Give the favorite a name." end
  if cut then return nil, ("A name can be %d letters long at most."):format(F.NAME_MAX) end
  local note, cutN = F.Clean(t.note, F.NOTE_MAX)
  if cutN then return nil, ("A note can be %d letters long at most."):format(F.NOTE_MAX) end
  local ty = typeKey(t.type)
  local icon = nil
  if t.icon ~= nil and t.icon ~= "" then
    icon = F.CleanIcon(t.icon)
    if not icon then return nil, "That icon is not one of the game's textures." end
  end
  return { name = name, type = ty, prof = ty == "trainer" and profName(t.prof) or nil, note = note ~= "" and note or nil,
    icon = icon, map = map, x = round4(x), y = round4(y) }
end

local function sameSpot(a, map, x, y, name)
  return a.map == map and abs(a.x - x) < 0.002 and abs(a.y - y) < 0.002 and a.name:lower() == name:lower()
end

-- Save a favorite. Returns it, or nil and a plain reason (a second save of the same place and name returns the one there is).
function F:Add(t, opts)
  local v, why = self:Check(t)
  if not v then return nil, why end
  local db = self:DB()
  for _, f in ipairs(db.list) do
    if whole(f) and sameSpot(f, v.map, v.x, v.y, v.name) then return f, "That favorite is already saved." end
  end
  if self:Count() >= F.MAX then return nil, ("You have %d favorites, the most Panoply Suite keeps. Delete one first."):format(F.MAX) end
  v.id = db.nextId
  v.by = (opts and opts.by) or F.Me()
  v.at = (opts and opts.at) or (_G.time and time()) or nil
  v.from = opts and opts.from or nil
  db.nextId = db.nextId + 1
  db.list[#db.list + 1] = v
  if not (opts and opts.quiet) then changed() end
  return v
end

-- Change a favorite: any of its fields (name, type, profession, note, icon, place). The id and who saved it stay.
function F:Update(id, t)
  local f = self:Get(id)
  if not f then return nil, "That favorite is not saved any more." end
  local merged = {}
  for _, k in ipairs({ "name", "type", "prof", "note", "icon", "map", "x", "y" }) do
    if t[k] ~= nil then merged[k] = t[k] else merged[k] = f[k] end
  end
  if t.icon == false then merged.icon = nil end     -- false: back to the type's own icon
  if t.note == false then merged.note = nil end
  if t.prof == false then merged.prof = nil end     -- false: any profession
  local v, why = self:Check(merged)
  if not v then return nil, why end
  for k, val in pairs(v) do f[k] = val end
  if v.icon == nil then f.icon = nil end
  if v.note == nil then f.note = nil end
  if v.prof == nil then f.prof = nil end
  changed()
  return f
end

function F:Move(id, map, x, y) return self:Update(id, { map = map, x = x, y = y }) end
function F:Rename(id, name) return self:Update(id, { name = name }) end

function F:Remove(id)
  local list = self:DB().list
  for i, f in ipairs(list) do
    if type(f) == "table" and f.id == id then table.remove(list, i) changed() return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Show and hide: by type (for the account) and "only mine" (for this character)
-------------------------------------------------------------------------------
function F:TypeShown(t) return not self:DB().hide[typeKey(t)] end
function F:SetTypeShown(t, on)
  local db = self:DB()
  db.hide[typeKey(t)] = (not on) and true or nil
  changed()
end
function F:OnlyMine() return Panoply.cdb ~= nil and Panoply.cdb.mapFavOnlyMine == true end
function F:SetOnlyMine(on)
  if not Panoply.cdb then return end
  Panoply.cdb.mapFavOnlyMine = on and true or false
  changed()
end
-- is this favorite shown (on the maps and in the list's "shown" view)?
-- me: this character's "Name-Realm" when the caller already has it (a redraw asks once, not once a favorite)
function F:Visible(f, me)
  if not whole(f) or not self:TypeShown(f.type) then return false end
  if self:OnlyMine() then
    me = me or F.Me()
    if me and f.by ~= me then return false end
  end
  return true
end
-- a copy of a starred Saved spot that the player has not changed, standing on that spot while Saved spots are drawn: the spot's own star
-- is its pin (one pin, not two on top of each other). Once the copy gets its own type, icon or place it has its own pin.
function F:Doubled(f)
  local id = type(f.from) == "string" and tonumber(f.from:match("^spot:(%d+)$"))
  if not id or f.type ~= "custom" or f.icon or not (Panoply.db and Panoply.db.mapSpots ~= false) then return false end
  local sp = M.Spots and M.Spots.Get and M.Spots:Get(id)
  return sp ~= nil and sp.map == f.map and abs(sp.x - f.x) < 0.002 and abs(sp.y - f.y) < 0.002
end

-- yards from the character to a favorite in the same zone; nil when it is in another zone or the zone has no size
function F:Distance(f)
  local m, px, py = C.GetPlayerPos()
  if not (m and px and f and f.map == m) then return nil end
  local w, h = C.MapSize(m)
  if not w then return nil end
  local dx, dy = (f.x - px) * w, (f.y - py) * h
  return sqrt(dx * dx + dy * dy)
end
function F:DistanceText(f)
  local d = self:Distance(f)
  if d then return ("%d yards"):format(floor(d + 0.5)) end
  return "in " .. (C.MapName(f.map) or "another zone")
end

-- The list. opts = { zone = map id or nil (all zones), sort = "name" | "distance", shown = true (only those the maps show) }
function F:List(opts)
  opts = opts or {}
  local out = {}
  for _, f in ipairs(self:DB().list) do
    if whole(f) and (not opts.zone or f.map == opts.zone) and (not opts.shown or self:Visible(f)) then out[#out + 1] = f end
  end
  if opts.sort == "distance" then
    local d = {}
    for _, f in ipairs(out) do d[f] = self:Distance(f) end
    table.sort(out, function(a, b)
      local x, y = d[a], d[b]
      if x and y and x ~= y then return x < y end
      if (x ~= nil) ~= (y ~= nil) then return x ~= nil end
      if a.map ~= b.map then return (C.MapName(a.map) or "") < (C.MapName(b.map) or "") end
      return a.name:lower() < b.name:lower()
    end)
  else
    table.sort(out, function(a, b)
      local an, bn = a.name:lower(), b.name:lower()
      if an ~= bn then return an < bn end
      return a.id < b.id
    end)
  end
  return out
end

-------------------------------------------------------------------------------
-- Going there
-------------------------------------------------------------------------------
local function dest(f) return { kind = "favorite", name = f.name, sub = "Favorite - " .. F:Where(f), map = f.map, x = f.x, y = f.y } end
-- the trip there (the Go to window's route engine), else the arrow
function F:Go(id)
  local f = self:Get(id)
  if not f then return false end
  local N = M.Navigate
  if N and N.Go then return N:Go(dest(f)) end
  return M:PointAt(f.map, f.x, f.y, f.name)
end
-- open the world map on it and ring the spot
function F:Show(id)
  local f = self:Get(id)
  if not f then return false end
  local N = M.Navigate
  if N and N.ShowOnMap then return N:ShowOnMap(dest(f)) end
  return false
end

-------------------------------------------------------------------------------
-- Where a new favorite starts: the character's own position, or the target (a vendor, a trainer, a rare)
-------------------------------------------------------------------------------
function F:Here()
  local m, x, y = C.GetPlayerPos()
  if not (m and x and y) then return nil, "Panoply Suite can't tell where you are here (inside a dungeon, or the map has no position)." end
  local sub = (_G.GetSubZoneText and GetSubZoneText()) or ""
  if type(sub) ~= "string" or sub == "" then sub = C.MapName(m) or "" end
  return { map = m, x = x, y = y, name = sub, type = "custom" }
end

-- a place kind of the map's Places (Map.lua M.PLACE_TYPES) as a favorite's type
local PLACE_TYPE = { placeTrainClass = "trainer", placeTrainProf = "trainer", placeTrainPet = "trainer", placeTrainDemon = "trainer",
  placeTrainPortal = "trainer", placeTrainWeapon = "trainer", placeTrainRiding = "trainer", placeMail = "mail", placeInn = "inn",
  placeRepair = "repair", placeVTrade = "vendor", placeVProf = "vendor", placeVReagent = "vendor", placeVAmmo = "vendor", placeVFood = "vendor",
  placeVPoison = "vendor", placeRare = "rare", flight = "flight", placeAuction = "vendor", placeBank = "custom", placeStable = "custom",
  placeGuild = "custom", placeAnvil = "custom", placeForge = "custom", placeCamp = "custom" }
F.PLACE_TYPE = PLACE_TYPE
-- the profession a trainer's title names ("Blacksmithing Trainer", "Master Alchemist")
local PROF_WORDS = { alchem = "Alchemy", blacksmith = "Blacksmithing", enchant = "Enchanting", engineer = "Engineering", herbal = "Herbalism",
  leatherwork = "Leatherworking", miner = "Mining", mining = "Mining", skinn = "Skinning", tailor = "Tailoring", cook = "Cooking", chef = "Cooking",
  ["first aid"] = "First Aid", fish = "Fishing" }
function F.ProfOfTitle(sub)
  sub = tostring(sub or ""):lower()
  for w, p in pairs(PROF_WORDS) do if sub:find(w, 1, true) then return p end end
  return nil
end

-- the type of a Go to favourite (Navigate.lua keeps its kind, its title and, for a kind of place, its place type): Places' kind first, then
-- the Go to kind, then the words of its title. Returns the type and, for a trainer, its profession.
local SUB_WORDS = { { "trainer", "trainer" }, { "innkeeper", "inn" }, { "flight master", "flight" }, { "gryphon master", "flight" },
  { "wind rider master", "flight" }, { "hippogryph master", "flight" }, { "bat handler", "flight" }, { "mailbox", "mail" }, { "repair", "repair" },
  { "armorer", "repair" }, { "supplies", "vendor" }, { "vendor", "vendor" }, { "merchant", "vendor" }, { "goods", "vendor" }, { "reagents", "vendor" } }
function F.TypeOfPlace(d)
  local ty = PLACE_TYPE[d.type or ""]
  if not ty and d.kind == "flight" then ty = "flight" end
  local sub = tostring(d.sub or ""):lower()
  if not ty then for _, w in ipairs(SUB_WORDS) do if sub:find(w[1], 1, true) then ty = w[2] break end end end
  ty = ty or "custom"
  local prof
  if ty == "trainer" then prof = (d.type == "placeTrainClass") and "Class" or F.ProfOfTitle(d.sub) end
  return ty, prof
end

-- the character's target as a new favorite: its name and title, its kind, and where the map data has it in this zone (the nearest
-- spot of an NPC of that name), else where the character stands. Returns a table for the form, or nil and why.
function F:FromTarget()
  local exists = C.pc(_G.UnitExists, "target")
  if not exists then return nil, "Target a vendor, a trainer or a creature first." end
  local isPlayer = C.pc(_G.UnitIsPlayer, "target")
  if isPlayer then return nil, "That is a player. Target a vendor, a trainer or a creature." end
  local name = C.pc(_G.UnitName, "target")
  if not (type(name) == "string" and name ~= "") then return nil, "The game did not say who your target is." end
  local here, why = self:Here()
  if not here then return nil, why end
  local out = { name = name, type = "custom", map = here.map, x = here.x, y = here.y, fromData = false }
  local P = M.Places
  local best, bd
  if P and P.Index then
    local okI, idx = pcall(P.Index)
    for _, e in ipairs(okI and idx and idx.byMap and idx.byMap[here.map] or {}) do
      if e.name == name then
        local d = (e.x - here.x) ^ 2 + (e.y - here.y) ^ 2
        if not bd or d < bd then best, bd = e, d end
      end
    end
  end
  if best then
    out.x, out.y, out.fromData = best.x, best.y, true
    out.type = PLACE_TYPE[best.type] or "custom"
    if out.type == "trainer" then out.prof = best.type == "placeTrainClass" and "Class" or F.ProfOfTitle(best.sub) end
    if best.sub and best.sub ~= "" then out.name = F.Clean(name .. ", " .. best.sub, F.NAME_MAX) end
  end
  local class = C.pc(_G.UnitClassification, "target")
  if class == "rare" or class == "rareelite" then out.type = "rare" end
  return out
end

-------------------------------------------------------------------------------
-- Migration: the old favourites are COPIED in once; nothing is deleted
-------------------------------------------------------------------------------
function F:Migrate(db)
  self.migrating = true
  local ok, err = pcall(function()
    local n = 0
    if not db.migrated.spots then
      local sdb = _G.PanoplySuiteSpotsDB
      for _, sp in ipairs(type(sdb) == "table" and type(sdb.spots) == "table" and sdb.spots or {}) do
        if type(sp) == "table" and sp.fav and type(sp.id) == "number" and type(sp.name) == "string" then
          local v = self:Add({ name = sp.name, type = "custom", map = sp.map, x = sp.x, y = sp.y },
            { by = sp.by, at = sp.at, from = "spot:" .. sp.id, quiet = true })
          if v then n = n + 1 end
        end
      end
      db.migrated.spots = true      -- marked only once every starred spot was copied (an error halfway: tried again next time)
    end
    local me = F.Me()
    if me and Panoply.cdb and not db.migrated.chars[me] then
      for _, d in ipairs(type(Panoply.cdb.placesFav) == "table" and Panoply.cdb.placesFav or {}) do
        if type(d) == "table" and not d.spot and type(d.name) == "string" and d.map and d.x and d.y then
          local ty, prof = F.TypeOfPlace(d)
          local v = self:Add({ name = d.name, type = ty, prof = prof, map = d.map, x = d.x, y = d.y }, { by = me, from = "goto", quiet = true })
          if v then n = n + 1 end
        end
      end
      db.migrated.chars[me] = true
    end
    if n > 0 then F.migratedNow = (F.migratedNow or 0) + n changed() end
  end)
  self.migrating = false
  if not ok then Panoply:Debug("favorites migration", err) end
end

-------------------------------------------------------------------------------
-- Share: a text line of one favorite or a set, and reading one back
-------------------------------------------------------------------------------
local function enc(s)
  return (tostring(s):gsub("[^A-Za-z0-9]", function(ch) if ch == " " then return "+" end return ("%%%02X"):format(ch:byte()) end))
end
local function dec(s)
  return (s:gsub("%+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function check(body)
  local a, b = 1, 0
  for i = 1, #body do a = (a + body:byte(i)) % 65521 b = (b + a) % 65521 end
  return ("%04X%04X"):format(b, a)
end
F.Checksum = check

-- ids: one id, or a list of ids. Returns the line, or nil and why.
function F:Export(ids)
  if type(ids) == "number" then ids = { ids } end
  local parts = {}
  for _, id in ipairs(ids or {}) do
    local f = self:Get(id)
    if f then
      local icon = f.icon and (type(f.icon) == "number" and ("#" .. f.icon) or f.icon) or ""
      parts[#parts + 1] = table.concat({ enc(f.name), f.type, enc(f.prof or ""), enc(f.note or ""), enc(icon), tostring(f.map),
        tostring(floor(f.x * 10000 + 0.5)), tostring(floor(f.y * 10000 + 0.5)) }, ",")
    end
  end
  if #parts == 0 then return nil, "There is no favorite to share." end
  if #parts > F.IMPORT_MAX then return nil, ("A shared line holds %d favorites at most."):format(F.IMPORT_MAX) end
  local body = table.concat(parts, "~")
  local line = F.PREFIX .. body .. ":" .. check(body)
  if #line > F.TEXT_MAX then return nil, "That is too many favorites, or notes too long, for one line. Share fewer (This zone, or one type)." end
  return line, #parts
end

local function bad(msg) return nil, msg end
-- Reads a shared line. Returns a list of favorites (checked, not saved), or nil and a plain reason. Changes nothing.
function F:Read(text)
  if type(text) ~= "string" then return bad("Paste a shared favorites line first.") end
  if #text > F.TEXT_MAX * 2 then return bad("That text is far too long to be shared favorites.") end
  text = text:gsub("%s+", "")
  if text == "" then return bad("Paste a shared favorites line first.") end
  if #text > F.TEXT_MAX then return bad("That text is too long to be shared favorites.") end
  if text:sub(1, #F.PREFIX) ~= F.PREFIX then return bad("That is not a shared favorites line: it should begin with " .. F.PREFIX) end
  local body, sum = text:match("^PSF1:([^:]*):(%x%x%x%x%x%x%x%x)$")
  if not body then return bad("That text is not complete: a shared favorites line ends with a check number after a colon.") end
  if body == "" then return bad("That line holds no favorite.") end
  if not body:match("^[A-Za-z0-9+%%~,]*$") then return bad("That text has characters a shared favorites line never has.") end
  if check(body) ~= sum:upper() then return bad("The check number does not match: the text was changed or cut short when it was copied.") end
  local out = {}
  for part in (body .. "~"):gmatch("(.-)~") do
    local fl = {}
    for field in (part .. ","):gmatch("(.-),") do fl[#fl + 1] = field end
    if #fl ~= 8 then return bad("A favorite in that line is not in the shape a shared favorite has.") end
    if not F.TYPE[fl[2]] then return bad("A favorite in that line has a type Panoply Suite does not know.") end
    local map, xi, yi = fl[6]:match("^%d+$") and tonumber(fl[6]), fl[7]:match("^%d+$") and tonumber(fl[7]), fl[8]:match("^%d+$") and tonumber(fl[8])
    if not (map and xi and yi) or #fl[6] > 7 or xi > 10000 or yi > 10000 then return bad("A favorite in that line has a damaged place.") end
    local rawIcon = dec(fl[5])
    local icon
    if rawIcon ~= "" then
      local n = rawIcon:match("^#(%d+)$")
      icon = F.CleanIcon(n and tonumber(n) or rawIcon)
      if not icon then return bad("A favorite in that line has an icon that is not one of the game's textures.") end
    end
    local name, cut = F.Clean(dec(fl[1]), F.NAME_MAX)
    local note, cutN = F.Clean(dec(fl[4]), F.NOTE_MAX)
    if name == "" then return bad("A favorite in that line has no name.") end
    if cut then return bad(("A name in that line is longer than %d letters."):format(F.NAME_MAX)) end
    if cutN then return bad(("A note in that line is longer than %d letters."):format(F.NOTE_MAX)) end
    out[#out + 1] = { name = name, type = fl[2], prof = profName(dec(fl[3])), note = note ~= "" and note or nil, icon = icon,
      map = map, x = xi / 10000, y = yi / 10000 }
    if #out > F.IMPORT_MAX then return bad(("A shared line holds %d favorites at most, and that one has more."):format(F.IMPORT_MAX)) end
  end
  return out
end

-- Adds every favorite of a shared line. Returns added, skipped (already saved), unknown zones; or nil and why (nothing is added).
function F:Import(text)
  local list, why = self:Read(text)
  if not list then return nil, why end
  local room = F.MAX - self:Count()
  local fresh = {}
  local db = self:DB()
  local skipped, unknown = 0, 0
  for _, t in ipairs(list) do
    if not C.MapName(t.map) then unknown = unknown + 1
    else
      local dup = false
      for _, f in ipairs(db.list) do if whole(f) and sameSpot(f, t.map, round4(t.x), round4(t.y), t.name) then dup = true break end end
      -- the same favorite twice in one line is one favorite
      for _, f in ipairs(fresh) do if sameSpot({ map = f.map, x = round4(f.x), y = round4(f.y), name = f.name }, t.map, round4(t.x), round4(t.y), t.name) then dup = true break end end
      if dup then skipped = skipped + 1 else fresh[#fresh + 1] = t end
    end
  end
  if #fresh > room then return nil, ("That line has %d new favorites and there is room for %d. Delete some first."):format(#fresh, max(0, room)) end
  local added = 0
  for _, t in ipairs(fresh) do
    if self:Add(t, { from = "import", quiet = true }) then added = added + 1 end
  end
  if added > 0 then changed() end
  return added, skipped, unknown
end

-------------------------------------------------------------------------------
-- The pins: a layer on the world map's canvas, and the closest few on the minimap
-------------------------------------------------------------------------------
local function setIcon(tex, f)
  local icon = F:IconOf(f)
  -- a file this game says it does not have would draw as a green square: the game's question mark instead
  if type(icon) == "string" and C.FileExists(icon) == false then icon = I .. "INV_Misc_QuestionMark" end
  tex:SetTexture(icon)
  if tex.SetTexCoord then
    if type(icon) == "string" and icon:find("^Interface\\Icons\\") then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
  end
end
F.SetIcon = setIcon

function F:Tip(owner, f, onMap)
  local GT = _G.GameTooltip
  if not (f and GT) then return end
  GT:SetOwner(owner, "ANCHOR_RIGHT")
  GT:SetText(f.name, 1, 0.82, 0.25)
  GT:AddLine(self:TypeLabel(f), 0.9, 0.9, 0.9)
  if f.note then GT:AddLine(f.note, 0.9, 0.9, 0.9, true) end
  GT:AddLine(self:DistanceText(f), 0.7, 0.7, 0.7)
  if onMap then
    GT:AddLine("Click: show me the way", 0.5, 0.85, 1)
    GT:AddLine("Right-click: edit, share or delete", 0.5, 0.85, 1)
  end
  GT:Show()
end

function F:PinMenu(owner, f)
  if not (f and Skin.Menu) then return end
  local FW = M.FavWindow
  return Skin.Menu(owner, {
    { text = "Show me the way", tip = "Plans the trip there; the arrow follows it.", func = function() F:Go(f.id) end },
    { text = "Edit...", tip = "Change its name, type, note, icon or place.", func = function() if FW then FW:OpenForm({ edit = f.id }) end end },
    { text = "Share...", tip = "A text line of this favorite to copy and paste to a friend.", func = function() if FW then FW:Share({ f.id }) end end },
    { text = "All favorites", tip = "The Favorites window: every favorite, by zone, by name or by distance.", func = function() if FW then FW:Open() end end },
    { text = "Delete this favorite...", tip = "Asks first, then takes it off your favorites. This cannot be undone.",
      func = function() if FW then FW:ConfirmDelete(owner, f) else F:Remove(f.id) end end },
  }, { width = 210 })
end

function F:NewPin(parent, minimap)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true
  p.panoplyMinimap = minimap and true or nil
  p:SetSize(F.WM_PX, F.WM_PX)
  local back = p:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(Skin.TEX.CircleMask)
  back:SetPoint("TOPLEFT", p, "TOPLEFT", -2, 2); back:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 2, -2)
  local k = Skin.colors.trailInk or { 0.04, 0.05, 0.07 }
  back:SetVertexColor(k[1], k[2], k[3], 0.92)
  p.back = back
  p.tex = p:CreateTexture(nil, "OVERLAY")
  p.tex:SetAllPoints(p)
  p:SetScript("OnEnter", function(self) F:Tip(self, self.fav, not self.panoplyMinimap) end)
  p:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  if minimap then
    -- the minimap's own clicks stay the minimap's; the pin still shows its tooltip under the pointer
    p:EnableMouse(false)
    if p.SetMouseMotionEnabled then p:SetMouseMotionEnabled(true) end
    if p.SetMouseClickEnabled then p:SetMouseClickEnabled(false) end
  else
    p.label = Skin.Text(p, 10, Skin.colors.text)
    p.label:SetPoint("TOP", p, "BOTTOM", 0, -2)
    if p.label.SetWordWrap then p.label:SetWordWrap(false) end
    p.label.panoplyLayoutSkip = true
    if p.RegisterForClicks then p:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    p:SetScript("OnClick", function(self, button)
      local f = self.fav
      if not f then return end
      if button == "RightButton" then F:PinMenu(self, f) else F:Go(f.id) end
    end)
  end
  return p
end

function F:StylePin(p, f, where, px)
  p.fav = f
  p:SetSize(px, px)
  setIcon(p.tex, f)
  p:SetAlpha(1)
  if p.label then
    if Panoply.db and Panoply.db.mapFavLabels then
      p.label:SetText(f.name)
      p.label:SetWidth(math.ceil(Skin.TextWidth(p.label)) + 4)
      p.label:Show()
    else p.label:Hide() end
  end
end

function F:Layer()
  local canvas = C.WorldMapCanvas()
  if not canvas then return nil end
  if not self.layer then
    self.layer = CreateFrame("Frame", nil, canvas)
    self.layer:SetAllPoints(canvas)
    self.layer.panoplyLayoutSkip = true
  end
  if self.layer:GetParent() ~= canvas and self.layer.SetParent then self.layer:SetParent(canvas) self.layer:SetAllPoints(canvas) end
  return self.layer, canvas
end

-- the favorites of one zone map that are shown
function F:Collect(map)
  local out = {}
  if not map then return out end
  local me = F.Me()
  for _, f in ipairs(self:List()) do if f.map == map and self:Visible(f, me) and not self:Doubled(f) then out[#out + 1] = f end end
  return out
end

function F:Refresh()
  self.pins = self.pins or {}
  self:HookMap()
  local used = 0
  local wm, map = C.WorldMap(), C.WorldMapID()
  if M.active and Panoply.db and Panoply.db.mapFavWM ~= false and wm and wm.IsShown and wm:IsShown() and map then
    local list = self:Collect(map)
    local layer, canvas = nil, nil
    if #list > 0 then layer, canvas = self:Layer() end
    if layer then
      local lvl = M:IconLevel()
      if layer.SetFrameLevel and layer:GetFrameLevel() ~= lvl then layer:SetFrameLevel(lvl) end
      if C.FloorMapAlpha then C.FloorMapAlpha(layer) C.HookMapAlpha() end
      local markLevel = M:MarkLevel(layer:GetFrameLevel())
      local W, H = canvas:GetWidth() or 1002, canvas:GetHeight() or 668
      local Tr = Panoply.Trail
      local cs = Tr and Tr.CanvasScale and Tr:CanvasScale(canvas) or 1
      local px = F.WM_PX * size("mapFavWMSize") / max(0.2, cs)
      for _, f in ipairs(list) do
        used = used + 1
        local p = self.pins[used]
        if not p then p = self:NewPin(layer) self.pins[used] = p end
        self:StylePin(p, f, "wm", px)
        p:ClearAllPoints()
        p:SetPoint("CENTER", layer, "TOPLEFT", f.x * W, -f.y * H)
        if p.SetFrameLevel then p:SetFrameLevel(markLevel + 1) end
        p:Show()
      end
    end
  end
  for i = used + 1, #self.pins do self.pins[i]:Hide() self.pins[i].fav = nil end
  self.shown = used
  self:MinimapRefresh()
  return used
end

function F:MinimapRefresh()
  self.mmPins = self.mmPins or {}
  local used = 0
  local mm = _G.Minimap
  local m, px, py = C.GetPlayerPos()
  if M.active and Panoply.db and Panoply.db.mapFavMM ~= false and mm and mm:IsShown() and m then
    local w, h = C.MapSize(m)
    if w then
      local radius = C.MinimapRadius()
      local half = (mm:GetWidth() or 140) / 2
      local rot = C.MinimapRotates()
      local fa = rot and (C.Facing() or 0) or 0
      local cf, sf = math.cos(fa), math.sin(fa)
      local mmPx = F.MM_PX * size("mapFavMMSize")
      local cand = {}
      local me = F.Me()
      for _, f in ipairs(self:DB().list) do
        if f.map == m and self:Visible(f, me) and not self:Doubled(f) then
          local dx, dy = (f.x - px) * w, (f.y - py) * h
          local north = -dy
          local sx, sy = dx * cf + north * sf, -dx * sf + north * cf
          local d = sqrt(sx * sx + sy * sy)
          if d <= radius then cand[#cand + 1] = { f = f, sx = sx, sy = sy, d = d } end
        end
      end
      table.sort(cand, function(a, b) return a.d < b.d end)
      for k = 1, min(#cand, F.MM_CAP) do
        local c = cand[k]
        local ox, oy = c.sx / radius * (half - 6), c.sy / radius * (half - 6)
        local ca = Panoply.MinimapCentreAlpha and Panoply.MinimapCentreAlpha(ox, oy) or 1
        if ca > 0 then
          used = used + 1
          local p = self.mmPins[used]
          if not p then p = self:NewPin(mm, true) self.mmPins[used] = p end
          self:StylePin(p, c.f, "mm", mmPx)
          p:SetAlpha(ca)
          p:ClearAllPoints()
          p:SetPoint("CENTER", mm, "CENTER", ox, oy)
          p:Show()
        end
      end
    end
  end
  for i = used + 1, #self.mmPins do self.mmPins[i]:Hide() self.mmPins[i].fav = nil end
  self.mmShown = used
  return used
end

function F:Enable()
  if not self.driver then
    local d = CreateFrame("Frame", nil, _G.Minimap or UIParent)
    d.elapsed = 0
    d:SetScript("OnUpdate", function(frame, dt)
      frame.elapsed = frame.elapsed + (dt or 0)
      if frame.elapsed < F.MM_TICK then return end
      frame.elapsed = 0
      F:MinimapRefresh()
    end)
    self.driver = d
  end
  self.driver:Show()
end

function F:Disable()
  if self.driver then self.driver:Hide() end
  for _, p in ipairs(self.pins or {}) do p:Hide() end
  for _, p in ipairs(self.mmPins or {}) do p:Hide() end
  self.shown, self.mmShown = 0, 0
  local FW = M.FavWindow
  if FW and FW.Hide then FW:Hide() end
end

-- Alt-right-click on the world map: a new favorite at the place under the pointer (a plain right-click is the game's own zoom out,
-- Shift-right-click saves a spot, Ctrl-right-click sets a waypoint). Read when the button goes down, the form opens when it comes up.
function F:OnMapDown(button)
  self.press = nil
  if not (M.active and button == "RightButton" and _G.IsAltKeyDown and IsAltKeyDown()) then return end
  local m = C.WorldMapID()
  local x, y = C.WorldMapCursor()
  if m and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then self.press = { map = m, x = x, y = y } end
end
function F:OnMapUp(button)
  local p = self.press
  self.press = nil
  if not (p and button == "RightButton") then return end
  local FW = M.FavWindow
  return FW and FW:OpenForm({ map = p.map, x = p.x, y = p.y }) or nil
end
function F:HookMap()
  if self.hooked then return end
  local wm = C.WorldMap()
  local sc = wm and wm.ScrollContainer
  if not (sc and sc.HookScript) then return end
  self.hooked = true
  sc:HookScript("OnMouseDown", function(_, button) F:OnMapDown(button) end)
  sc:HookScript("OnMouseUp", function(_, button) F:OnMapUp(button) end)
end


-------------------------------------------------------------------------------
-- Settings and changes
-------------------------------------------------------------------------------
F.KEYS = { "mapFavWM", "mapFavMM", "mapFavLabels", "mapFavWMSize", "mapFavMMSize" }
local function redraw() if M.active then F:Refresh() end end
for _, k in ipairs(F.KEYS) do Panoply.optionHooks[k] = redraw end
-- Saved spots shown or hidden changes which favorites draw their own pin (F:Doubled): the spots' own hook runs, then this one
local spotsHook = Panoply.optionHooks.mapSpots
Panoply.optionHooks.mapSpots = function(...) if spotsHook then spotsHook(...) end redraw() end
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys(F.KEYS) end

M.options[#M.options + 1] = { type = "check", key = "mapFavWM", label = "Favorites on the world map",
  tip = "Your map favorites as their icons on the world map. Alt-right-click the map to add one; the Places menu on the map lists them." }
M.options[#M.options + 1] = { type = "check", key = "mapFavMM", label = "Favorites on the minimap",
  tip = "The closest of your favorites on the minimap. Hover one for its name, note and distance." }
M.options[#M.options + 1] = { type = "check", key = "mapFavLabels", label = "Names under favorites on the world map",
  tip = "Each favorite's name under its icon on the world map. Off: the name shows when you hover the icon." }
M.options[#M.options + 1] = { type = "slider", key = "mapFavWMSize", label = "Size on the world map", min = F.SIZE_MIN, max = F.SIZE_MAX, step = 0.05,
  tip = "How big your favorites' icons are on the world map. 100% is the standard size." }
M.options[#M.options + 1] = { type = "slider", key = "mapFavMMSize", label = "Size on the minimap", min = F.SIZE_MIN, max = F.SIZE_MAX, step = 0.05,
  tip = "How big your favorites' icons are on the minimap. 100% is the standard size." }

Panoply:Listen("FAVORITES_CHANGED", function()
  if M.active then F:Refresh() end
  local FW = M.FavWindow
  if FW and FW.Changed then FW:Changed() end
end)

-------------------------------------------------------------------------------
-- /panoply fav
-------------------------------------------------------------------------------
F.USAGE = "Usage: /panoply fav  (the Favorites window)   /panoply fav here   /panoply fav target   /panoply fav import"
function F:Slash(rest)
  rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if not Panoply.Modules:IsOn("map") then Panoply:Print("Map favorites are part of the Map page, which is switched off.") return false end
  local FW = M.FavWindow
  if not FW then return false end
  if rest == "" or rest == "list" then FW:Open() return true end
  if rest == "here" then FW:OpenForm({ here = true }) return true end
  if rest == "target" then FW:OpenForm({ target = true }) return true end
  if rest == "import" then FW:OpenImport() return true end
  Panoply:Print(F.USAGE)
  return false
end
