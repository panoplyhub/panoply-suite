-- Panoply Suite, Step 2 item D: the Look of the map (docs/step2/DEF-SPEC.md section D, mockups/step2/D-01 to D-05).
-- Core/Init.lua holds the first half of Panoply.Look (the Size and Opacity of everything drawn on a map, per map). This file adds the rest of
-- what a player can change about a thing on a map: the Spacing of the trail's walking pieces, its Style (dots, dashes, line) and a
-- Colour for every thing, plus the one table that says which controls each thing has on each map. The Map page's gear (UI/LookPanel.lua),
-- the menu rows (Panoply.Look.Rows, found by the All settings box) and the drawing code (UI/Trail.lua, the Quest icons, Gathering and
-- Waypoints modules) all read this one table, so a control cannot exist in one place and be missing in another.
--
-- Every thing keeps its own World map and Minimap controls: nothing is shared and nothing is multiplied.
-- 100% / the standard choice is how it always looked.
--
-- To add a thing (Step 2 item E adds "Info icons" and "Connections" with the Map module): call Panoply.Look.AddThing(def) (below) with its saved-key
-- prefix, name, words, maps, the module that draws it, its controls on each map and its colour choices; then give its module's option list
-- Panoply.Look.Rows(id) like the other modules do, and register the code that draws a small sample of it in Panoply.Look.Draw[id] (the live preview
-- calls it). The Map page's list, columns, search and Reset follow by themselves, and AddThing puts every key of the new thing into the
-- standard settings, the profiles and the hover-to-see-the-screen list. A thing whose module is not in the build is left out.
local ADDON, Panoply = ...
local Look = Panoply.Look

Look.SPACING_MIN, Look.SPACING_MAX = 0.5, 3

local function number(v, default)
  v = tonumber(v)
  if v == nil or v ~= v then return default end
  return v
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Register a thing drawn on a map. def = { id, prefix (saved keys: <prefix>WmSize ...), name, words (for the search), maps = { "wm" } or
-- { "wm", "mm" }, short (its name in the list), module (the module that draws it; nil: part of the guide),
-- controls = { wm = { "size", ... }, mm = { ... } } (a map with no entry is not drawn on), group = { first = { { id, name } ... }, palette, default } }.
-- Look.OnAdd (the catalogue) is told, so the Map page's rows include it.
function Look.AddThing(def)
  local t = { id = def.id, prefix = def.prefix, name = def.name, words = def.words, maps = def.maps }
  Look.THINGS[#Look.THINGS + 1] = t
  Look.BY_ID[t.id] = t
  Look.SHORT[t.id] = def.short or def.name
  Look.MODULE[t.id] = def.module
  Look.CONTROLS[t.id] = def.controls
  Look.GROUP[t.id] = def.group
  Look.Forget()
  -- every key of the new thing has its standard, so Reset, a new account and a profile all know it (the sizes and opacities of the
  -- first six things are listed in Core/Init.lua and in their modules)
  for _, m in ipairs(t.maps) do
    for _, what in ipairs(def.controls[m] or {}) do
      local k = Look.Key(t.id, m, what)
      if Panoply.defaults.account[k] == nil then Panoply.defaults.account[k] = Look.Default(t.id, m, what) end
    end
  end
  for k, v in pairs(Look.ExtraDefaults()) do if Panoply.defaults.account[k] == nil then Panoply.defaults.account[k] = v end end
  -- a profile holds every key of the thing (Engine/Profiles.lua keeps one list; a thing added after it was loaded is added to it here)
  if Panoply.Profiles and Panoply.Profiles.AddKeys then
    local keys = {}
    for _, m in ipairs(t.maps) do
      for _, what in ipairs(def.controls[m] or {}) do keys[#keys + 1] = Look.Key(t.id, m, what) end
    end
    Panoply.Profiles:AddKeys(keys)
  end
  if Look.OnAdd then Look.OnAdd(t.id) end
end

-- the name of a thing in the list at the left of the Look of the map
Look.SHORT = { trail = "Trail", giver = "Quest givers", turnin = "Hand-ins", objective = "Objectives", gather = "Gathering", way = "Waypoints" }

-- the module that draws a thing (nil: part of the guide itself). A thing shows only while its module is in this build and switched on.
Look.MODULE = { giver = "questpins", turnin = "questpins", objective = "questpins", gather = "gathering", way = "waypoints" }
function Look.Here(thing)
  local m = Look.MODULE[thing]
  if not m then return true end
  return Panoply.Modules ~= nil and Panoply.Modules.byKey[m] ~= nil and Panoply.Modules:Wanted(m)
end

-- Which controls a thing has on each map, in the order the panel draws them.
--   size     how big (25% to 300%)                     alpha    how solid (10% to 100%)
--   spacing  the gap between the walking dots/dashes   style    dots / dashes / line, or Icon / Ring
--   colour   one of the thing's colours (see GROUP)
--   names    the words beside the marks: always, or only while the mouse is on one (item E: Connections)
-- A thing with no entry for a map is not drawn there (the panel says so).
Look.CONTROLS = {
  trail = { wm = { "size", "spacing", "alpha", "style", "colour" }, mm = { "size", "spacing", "alpha", "style", "colour" } },
  giver = { wm = { "size", "alpha", "colour" }, mm = { "size", "alpha", "colour" } },
  turnin = { wm = { "size", "alpha", "colour" }, mm = { "size", "alpha", "colour" } },
  objective = { wm = { "size", "alpha", "colour" }, mm = { "size", "alpha", "colour" } },
  gather = { wm = { "size", "alpha", "colour" }, mm = { "size", "alpha", "style", "colour" } },
  way = { wm = { "size", "alpha", "colour" } },
}

-- The saved key of a control. The sizes and opacities keep the keys they have had since 0.7.3.7; the Icon / Ring style of the
-- gathering spots on the minimap is the "Hollow rings on the minimap" switch of 0.6.0, moved here (same key, same saved value).
local SUFFIX = { size = "Size", alpha = "Alpha", spacing = "Spacing", style = "Style", colour = "Colour", names = "Names" }
local KEY_OVERRIDE = { ["gather.mm.style"] = "gatherRings" }
function Look.Key(thing, map, what)
  local ov = KEY_OVERRIDE[thing .. "." .. map .. "." .. what]
  if ov then return ov end
  local t = Look.BY_ID[thing]
  return t.prefix .. Look.MAPS[map].suffix .. (SUFFIX[what] or "Size")
end

-- every saved key of every control, in menu order (Look.Keys, in Core/Init.lua, is the sizes and opacities only: they are all numbers
-- and all start at 1)
function Look.AllKeys()
  local out = {}
  for _, t in ipairs(Look.THINGS) do
    for _, m in ipairs(t.maps) do
      for _, what in ipairs(Look.CONTROLS[t.id][m] or {}) do out[#out + 1] = Look.Key(t.id, m, what) end
    end
  end
  return out
end

-- key -> { thing, map, what }
local keyInfo
local entries = {}
-- what is remembered about the things is thrown away (a thing was added)
function Look.Forget() keyInfo = nil entries = {} end
function Look.KeyInfo(key)
  if not keyInfo then
    keyInfo = {}
    for _, t in ipairs(Look.THINGS) do
      for _, m in ipairs(t.maps) do
        for _, what in ipairs(Look.CONTROLS[t.id][m] or {}) do keyInfo[Look.Key(t.id, m, what)] = { thing = t.id, map = m, what = what } end
      end
    end
  end
  return keyInfo[key]
end

-------------------------------------------------------------------------------
-- Colours
-------------------------------------------------------------------------------
-- Six colours for the trail, the gathering spots and the waypoints (the trail's own bright colours), and five for the quest icons
-- (the pin's light parts take the colour, its dark outline stays). A skin token is read when the colour is used, so a re-skin follows.
local SIX = {
  { id = "cyan", name = "Cyan", token = "trailWalk" }, { id = "yellow", name = "Yellow", token = "trailShip" },
  { id = "orange", name = "Orange", token = "trailZeppelin" }, { id = "green", name = "Green", token = "trailTram" },
  { id = "pink", name = "Pink", token = "trailFly" }, { id = "white", name = "White", token = "trailOff" },
}
local FIVE = {
  { id = "gold", name = "Gold", rgb = { 255 / 255, 209 / 255, 77 / 255 } }, { id = "red", name = "Red", token = "loss" },
  { id = "green", name = "Green", token = "done" }, { id = "violet", name = "Violet", rgb = { 180 / 255, 140 / 255, 255 / 255 } },
  { id = "white", name = "White", token = "trailOff" },
}
Look.SIX, Look.FIVE = SIX, FIVE
-- Step 2 item E: the Map module's old "Icon size" slider (mapIconScale, 70% to 150%) is gone; the info icons and the connections each have a Size
-- in the Look of the map. A size somebody chose carries over once, to both, unless they already have one of their own; the saved copy of every
-- profile is converted the same way, so a profile saved earlier cannot bring the old key back.
-- And the keys the Map module brought (`keys`: its settings and the controls of its two things): a profile saved before has none of them, and
-- logging in applies the character's profile (Engine/Profiles.lua: a key a profile lacks is put back to its standard), which would undo this
-- migration and every Map setting already chosen. So the live value of each of those keys, after the migration, is written into every saved
-- profile that lacks it (the same way the per-map sizes migration protected its own keys).
function Look.MigrateMapIcons(db, keys)
  local function convert(t)
    local s = tonumber(t.mapIconScale)
    if s and s == s and math.abs(s - 1) > 0.001 then
      s = clamp(s, Look.SIZE_MIN, Look.SIZE_MAX)
      if t.infoWmSize == nil or t.infoWmSize == 1 then t.infoWmSize = s end
      if t.connWmSize == nil or t.connWmSize == 1 then t.connWmSize = s end
    end
    t.mapIconScale = nil
  end
  convert(db)
  local list = type(db.profiles) == "table" and db.profiles.list
  if type(list) == "table" then
    for _, rec in pairs(list) do
      local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
      if type(set) == "table" then convert(set) end
    end
    if type(keys) == "table" then
      local function copyv(v) if type(v) ~= "table" then return v end local o = {} for k2, x in pairs(v) do o[k2] = copyv(x) end return o end
      for _, rec in pairs(list) do
        local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
        if type(set) == "table" then
          for _, k in ipairs(keys) do if set[k] == nil and db[k] ~= nil then set[k] = copyv(db[k]) end end
        end
      end
    end
  end
end

-- what the first swatches of a thing mean, which colours follow, and the choice that is how it always looked
Look.GROUP = {
  trail = { first = { { id = "type", name = "By travel type" } }, palette = SIX, default = "type" },
  gather = { first = { { id = "type", name = "By type" } }, palette = SIX, default = "type" },
  way = { first = { { id = "standard", name = "Standard" } }, palette = SIX, default = "standard" },
}
for _, q in ipairs({ "giver", "turnin", "objective" }) do
  Look.GROUP[q] = { first = { { id = "blizzard", name = "Blizzard default" }, { id = "panoply", name = "Panoply Suite" } }, palette = FIVE, default = "panoply" }
end

-- Is a choice offered in this client? The module that owns a choice registers the test (the quest icons say whether the game has
-- its own quest icon textures: UNVERIFIED in the real client, so a client without them simply has no "Blizzard default" swatch).
Look.AVAIL = {}
function Look.Available(thing, id)
  local f = Look.AVAIL[id]
  return f == nil or f(thing) and true or false
end

-- every choice of a thing's colour row, in the order of the swatches: { id, name, rgb | token }
function Look.Entries(thing)
  local list = entries[thing]
  if not list then
    local g = Look.GROUP[thing]
    list = {}
    for _, e in ipairs(g.first) do list[#list + 1] = e end
    for _, e in ipairs(g.palette) do list[#list + 1] = e end
    entries[thing] = list
  end
  return list
end
-- the choices the player is offered right now (a choice this client cannot draw is left out)
function Look.Offered(thing)
  local out = {}
  for _, e in ipairs(Look.Entries(thing)) do if Look.Available(thing, e.id) then out[#out + 1] = e end end
  return out
end
local function rgbOf(e)
  if e.rgb then return e.rgb end
  local c = e.token and Panoply.Skin and Panoply.Skin.colors[e.token]
  return c
end
-- { r, g, b } of a choice that is a colour; nil for the choices that are art (By type, Standard, Blizzard default, Panoply Suite)
function Look.EntryRGB(entry) return entry.id and (entry.rgb or entry.token) and rgbOf(entry) or nil end

-------------------------------------------------------------------------------
-- Reading what is saved: a missing, junk or out-of-range value is read as the standard one
-------------------------------------------------------------------------------
function Look.Default(thing, map, what)
  if what == "size" or what == "alpha" or what == "spacing" then return 1 end
  if what == "names" then return "always" end
  if what == "style" then if thing == "gather" then return true end return "dots" end
  if what == "colour" then return Look.GROUP[thing].default end
end

-- the gap between the walking dots or dashes of the trail, 50% to 300% of the standard gap
function Look.Spacing(thing, map)
  return clamp(number(Panoply.db and Panoply.db[Look.Key(thing, map, "spacing")], 1), Look.SPACING_MIN, Look.SPACING_MAX)
end

-- "dots" | "dashes" | "line" for the trail's walking part; "ring" | "icon" for the gathering spots on the minimap
function Look.Style(thing, map)
  local v = Panoply.db and Panoply.db[Look.Key(thing, map, "style")]
  if thing == "gather" then return v ~= false and "ring" or "icon" end
  if v == "dashes" or v == "line" then return v end
  return "dots"
end

-- "always" | "hover": are the words beside the marks of a thing shown all the time, or only while the mouse is on one (Connections)
function Look.Names(thing, map)
  local v = Panoply.db and Panoply.db[Look.Key(thing, map, "names")]
  if v == "hover" then return "hover" end
  return "always"
end

-- the id of the colour choice (one of Look.Entries(thing)), the standard one when the saved one is junk or not offered here
function Look.Colour(thing, map)
  local v = Panoply.db and Panoply.db[Look.Key(thing, map, "colour")]
  if v == "hearthpath" then v = "panoply" end   -- the Panoply Suite swatch's id before 0.9.5 (Skin.PanoplyValues rewrites it at login)
  for _, e in ipairs(Look.Entries(thing)) do
    if e.id == v then
      if Look.Available(thing, v) then return v end
      break
    end
  end
  return Look.GROUP[thing].default
end

-- { r, g, b } when the thing is drawn in one colour on this map, nil when it is drawn as it always was (or with art: Blizzard default)
function Look.RGB(thing, map)
  local id = Look.Colour(thing, map)
  for _, e in ipairs(Look.Entries(thing)) do
    if e.id == id then return Look.EntryRGB(e) end
  end
  return nil
end

-- Put a colour on a texture: the art goes grey and takes the colour (its dark outline stays dark), or, with no colour, the texture is
-- given back as it was. Only a texture this was used on is ever reset, so a game icon that is grey on purpose is left alone.
function Look.Tint(tex, rgb)
  if not tex then return end
  if rgb then
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    if tex.SetVertexColor then tex:SetVertexColor(rgb[1], rgb[2], rgb[3], 1) end
    tex.panoplyLookTint = true
  elseif tex.panoplyLookTint then
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
    tex.panoplyLookTint = nil
  end
end

-------------------------------------------------------------------------------
-- The menu rows of one thing: a row for each control it has on each map. The label spells out what and where (the panel shows
-- "Size" / "Spacing" ... under a "World map" / "Minimap" heading); the All settings box finds a row by it and by the words.
-------------------------------------------------------------------------------
local WHAT_WORD = { size = "size", alpha = "opacity", spacing = "spacing", style = "style", colour = "colour", names = "names" }
local WHAT_WORDS = {
  size = " size big bigger small smaller scale",
  alpha = " opacity transparent transparency see-through seethrough faded fade solid",
  spacing = " spacing space gap apart distance dense closer further wider",
  style = " style dots dashes dashed line solid ring rings icon icons hollow look",
  colour = " colour color tint hue blizzard default panoply hearthpath swatch paint",
  names = " names words labels text always hover show hide",
}
-- one short line each (the one-line help is built from these: UI/Catalog.lua keeps a tip of 110 letters or fewer)
local function tipFor(thing, t, map, mp, what)
  local lower = t.name:lower()
  local on = mp.on
  if what == "size" then return ("How big %s are %s. 100%% is the standard size."):format(lower, on)
  elseif what == "alpha" then return ("How solid %s look %s. Lower is more see-through."):format(lower, on)
  elseif what == "spacing" then return ("How far apart the walking dots and dashes are %s. 100%% is the usual gap."):format(on)
  elseif what == "style" then
    if thing == "gather" then return "Spots on the minimap as icons, or as hollow rings that let the game's tracking dot show." end
    return ("How the walking part of the trail is drawn %s. Flights and boats keep their shapes."):format(on)
  elseif what == "names" then
    return ("The words beside %s %s: always there, or only while the mouse is on one."):format(lower, on)
  elseif what == "colour" then
    local g = Look.GROUP[thing]
    if thing == "trail" then return ("Colour of the trail %s: by travel type, or one colour for all of it."):format(on) end
    if thing == "objective" then return ("Colour of objectives %s: Panoply Suite's pin, or one colour."):format(on) end   -- no game texture is known to fit
    if g.first[1].id == "blizzard" then return ("Colour of %s %s: the game's own icon, Panoply Suite's pin, or one colour."):format(lower, on) end
    return ("Colour of %s %s: %s, or one colour."):format(lower, on, g.first[1].name:lower())
  end
end

local function stylesFor(thing)
  if thing == "gather" then return { { false, "Icon" }, { true, "Ring" } } end
  return { { "dots", "Dots" }, { "dashes", "Dashes" }, { "line", "Line" } }
end
local function colourValues(thing)
  local out = {}
  for _, e in ipairs(Look.Entries(thing)) do out[#out + 1] = { e.id, e.name } end
  return out
end

local function row(thing, t, m, what)
  local mp = Look.MAPS[m]
  local label = ("%s: %s %s"):format(t.name, WHAT_WORD[what], mp.on)
  local r = { key = Look.Key(thing, m, what), label = label, searchLabel = label, default = Look.Default(thing, m, what), look = { thing = thing, map = m, what = what },
    tip = tipFor(thing, t, m, mp, what), words = t.words .. " " .. mp.words .. WHAT_WORDS[what] }
  if what == "size" or what == "alpha" or what == "spacing" then
    r.type = "slider"
    local size = what == "size"
    r.min = size and Look.SIZE_MIN or (what == "alpha" and Look.ALPHA_MIN or Look.SPACING_MIN)
    r.max = size and Look.SIZE_MAX or (what == "alpha" and Look.ALPHA_MAX or Look.SPACING_MAX)
    r.step = Look.STEP
  else
    r.type = "segmented"
    if what == "style" then r.values = stylesFor(thing)
    elseif what == "names" then r.values = { { "always", "Always" }, { "hover", "On hover" } }
    else r.values, r.swatches = colourValues(thing), true end
  end
  return r
end

function Look.Rows(thing)
  local t = Look.BY_ID[thing]
  local rows = {}
  for _, m in ipairs(t.maps) do
    for _, what in ipairs(Look.CONTROLS[thing][m] or {}) do rows[#rows + 1] = row(thing, t, m, what) end
  end
  return rows
end

-------------------------------------------------------------------------------
-- The standard of the new keys (the sizes and opacities already have theirs), and the keys a profile holds
-------------------------------------------------------------------------------
-- { key = standard value } of every spacing, style and colour
function Look.ExtraDefaults()
  local out = {}
  for _, t in ipairs(Look.THINGS) do
    for _, m in ipairs(t.maps) do
      for _, what in ipairs(Look.CONTROLS[t.id][m] or {}) do
        if what == "spacing" or what == "style" or what == "colour" or what == "names" then out[Look.Key(t.id, m, what)] = Look.Default(t.id, m, what) end
      end
    end
  end
  return out
end
function Look.ExtraKeys()
  local out = {}
  for k in pairs(Look.ExtraDefaults()) do out[#out + 1] = k end
  table.sort(out)
  return out
end
for k, v in pairs(Look.ExtraDefaults()) do
  if Panoply.defaults.account[k] == nil then Panoply.defaults.account[k] = v end
end

-- What draws a small sample of each thing for the live preview: fn(layer, where). The module that draws the thing on the real map
-- registers it, next to the code the sample shares with the map, so the preview cannot disagree with the map.
Look.Draw = {}
