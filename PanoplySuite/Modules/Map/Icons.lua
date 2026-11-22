-- Map module, what Panoply Suite adds to the world map: INFO ICONS (dungeon and raid entrances, graveyards) and CONNECTIONS (zone exits,
-- boats, zeppelins, the Deeprun Tram, portals, flight points known and not seen yet). Step 2 item E, from the design in
-- docs/step2/DEF-SPEC.md section E and mockups/step2/E-01 .. E-05. One layer, pooled button frames, drawn under the route trail and the
-- quest pins (M:IconLevel). Information only: a click points the arrow (a waypoint) at the spot; nothing is targeted, used or taken for you.
--
--   * Zone exits: on a zone map, a chip where one of the road graph's zone lines leaves the zone: an arrow the way you would walk, the
--     next zone's name and its level range. The range is shown only when the client in use has its own range for that zone in
--     Data/ZoneLevels.lua and somebody has checked it in the game (Classic Era and Forever each have their own);
--     the chip's edge says below you / in your range / above you (and the hover says it in words: colour is never the only cue).
--   * Boats, zeppelins, the tram, portals: a round badge at every end that has a ride, with where it goes ("Boat to Auberdine").
--     Two badges of one kind closer than 24 px on screen are one badge with a count.
--   * Flight points: today's approved flight pin. One Panoply Suite has seen on the player's list has a green check; the others are dimmed
--     with a "?" (the list only fills when a flight master's map is opened, so the words say "not seen yet", never "not learned").
--     Hovering one draws its flights along the real flight legs: solid to the points that can be flown to, dashed to the others.
--   * Look: Info icons and Connections are two things of the Map page's Look of the map (Core/Look.lua): size, opacity and colour on the
--     world map, and for Connections whether the names show always or only on hover. The minimap draws none of it.
--   * Words never overlap other words (I:SeparateLabels): when two marks' words would collide, the more important mark keeps its words (zone
--     exits first, then boats, zeppelins, the tram and portals, then flight points) and the other mark's words show on hover only.
-- Data: flight points, transports and zone exits from PanoplySuite_RouteData (the route planner's own data), entrances and graveyards from
-- PanoplySuiteQuestData.MapData (tools/build_mapdata.py), level ranges from Data/ZoneLevels.lua.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local Look = Panoply.Look
local pcallv = M.pc
local floor, max, min, sqrt, abs = math.floor, math.max, math.min, math.sqrt, math.abs

local I = {}
M.Icons = I
I.shown = 0
I.BASE = 16               -- a round badge's size in screen pixels at "Size 100%"
I.CONT_SCALE = 0.85       -- a little smaller on a continent map, which holds many more
I.MERGE_PX = 24           -- two badges of one kind this close on screen are one badge with a count
I.TAG_PT = 11             -- the words beside a badge, in points at Size 100%
I.CHIP_H = 22             -- a zone exit chip's height at Size 100%

-- kind -> which thing of the Look of the map it belongs to, its ring colour and glyph, its words and the setting that switches it
I.KINDS = {
  dungeon = { thing = "info", ring = "accent", glyph = "door", label = "Dungeon", setting = "mapEntrances" },
  raid = { thing = "info", ring = "goldBright", glyph = "door", label = "Raid", setting = "mapEntrances" },
  grave = { thing = "info", ring = "inkSoft", glyph = "cross", label = "Graveyard", setting = "mapGraves" },
  exit = { thing = "conn", label = "Zone exit", setting = "mapExits" },
  ship = { thing = "conn", ring = "trailShip", glyph = "boat", label = "Boat", plural = "boats", setting = "mapBoats" },
  zeppelin = { thing = "conn", ring = "trailZeppelin", glyph = "blimp", label = "Zeppelin", plural = "zeppelins", setting = "mapZeppelins" },
  tram = { thing = "conn", ring = "trailTram", glyph = "tram", label = "Deeprun Tram", plural = "trams", setting = "mapTram" },
  portal = { thing = "conn", ring = "accent", glyph = "portal", label = "Portal", plural = "portals", setting = "mapPortals" },
  flight = { thing = "conn", ring = "trailFly", art = "Flight", label = "Flight point" },   -- our approved flight pin (Media/Pins/Flight)
}
-- the kinds that can share a badge with a count
I.MERGES = { ship = true, zeppelin = true, tram = true, portal = true }
-- whose words win when two marks' words would overlap: lower first (exits, then docks and stops, then flight points); a tie goes to the mark
-- that comes first in the list
I.RANK = { exit = 1, ship = 2, zeppelin = 2, tram = 2, portal = 2, flight = 3 }
I.LABEL_GAP = 2           -- px of air kept between two marks' words
I.SETTING = {}
for k, d in pairs(I.KINDS) do I.SETTING[k] = d.setting end
I.SETTING.flight = "mapFlight"

-------------------------------------------------------------------------------
-- Where things are on the displayed map
-------------------------------------------------------------------------------
local function routeData()
  return Panoply.Route and Panoply.Route.Data and Panoply.Route:Data() or nil
end

-- The route planner's own map rectangle (the same rule the trail uses): { cont, top, bottom, left, right } in world yards.
local function rectOf(map)
  local Tr = Panoply.Trail
  return Tr and Tr.MapRect and Tr:MapRect(map)
end

-- Position (0..1) of a world spot on a map, even when it is off the map
local function frac(rc, wx, wy)
  return (rc[4] - wy) / (rc[4] - rc[5]), (rc[2] - wx) / (rc[2] - rc[3])
end

-- Position (0..1) of a world spot on a map, nil when it is not on that map.
local function onMap(map, cont, wx, wy)
  local rc = rectOf(map)
  if not (rc and rc[1] == cont and wx and wy) then return nil end
  local x, y = frac(rc, wx, wy)
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

local function isContinent(map)
  local Tr = Panoply.Trail
  return Tr and Tr.IsContinentMap and Tr:IsContinentMap(map) or false
end

-- The client's flight table also lists quest-only paths ("Quest Path 9574 ...") and a test row
-- ("Generic, World target"); a neutral node with no flight master in the data (the Eastern Plaguelands
-- towers) is not a place you can start a flight from. Those are left off the map.
local function realFlightPoint(n)
  local name = n[1] or ""
  if name:find("^Quest Path") or name:find("^Generic") then return false end
  return (n[9] or 0) > 0 or n[2] ~= "N"
end

local function myFaction()
  local f = Panoply.Route and Panoply.Route.Faction and Panoply.Route:Faction()
  return f or "A"
end

-- "Menethil Harbor, Wetlands" -> "Menethil Harbor"; "Stormwind City (Deeprun Tram)" -> "Stormwind City"
local function plain(name)
  return (tostring(name or ""):gsub(",.*$", ""):gsub(" %(.*%)$", ""))
end
I.Plain = plain

local function zoneName(map)
  local n = C.MapName and C.MapName(map)
  if n and n ~= "" then return n end
  local Z = Panoply.ZoneLevels
  local r = Z and Z.Row(map)
  return r and r.name or "the next zone"
end

local function dur(s)
  if Panoply.Route and Panoply.Route.Duration then return Panoply.Route.Duration(s) end
  return ("%d s"):format(floor(s + 0.5))
end

local function playerLevel()
  local ok, lv = pcall(C.XP)
  return ok and tonumber(lv) or nil
end

local FACTION = { A = "Alliance", H = "Horde", N = "Open to both sides" }

-- The list of marks for a map. Each: { kind, thing, x, y, map, title, ... }; the switches are read here, so a type that is off is never
-- built (and costs nothing).
function I:Collect(map)
  local out = {}
  if not map then return out end
  local cont = isContinent(map)
  local zoneOnly = not cont
  local d = M.Data()
  local RD = routeData()
  local fac = myFaction()
  local db = Panoply.db

  -- Info icons. Entrances: doors of one instance that stand together, and doors of different ones, share a pin
  if db.mapEntrances and d and d.instances then
    local pins = {}
    for _, inst in ipairs(d.instances) do
      for _, door in ipairs(inst.doors) do
        local x, y
        if zoneOnly then
          if door[4] == map then x, y = door[5], door[6] end
        else
          x, y = onMap(map, door[1], door[2], door[3])
        end
        if x then
          local pin
          for _, p in ipairs(pins) do
            if math.abs(p.x - x) < (cont and 0.012 or 0.02) and math.abs(p.y - y) < (cont and 0.016 or 0.03) then pin = p break end
          end
          if not pin then
            pin = { kind = "dungeon", thing = "info", x = x, y = y, map = map, instances = {}, seen = {} }
            pins[#pins + 1] = pin
          end
          if not pin.seen[inst.id] then
            pin.seen[inst.id] = true
            pin.instances[#pin.instances + 1] = { inst = inst, via = door[7], level = door[8] }
          end
        end
      end
    end
    for _, p in ipairs(pins) do
      table.sort(p.instances, function(a, b) return a.inst.mobs[1] < b.inst.mobs[1] end)
      local allRaid = true
      for _, e in ipairs(p.instances) do if e.inst.kind ~= "raid" then allRaid = false end end
      p.kind = allRaid and "raid" or "dungeon"
      p.title = #p.instances == 1 and p.instances[1].inst.name or (p.instances[1].inst.name .. " and " .. (#p.instances - 1) .. " more")
      out[#out + 1] = p
    end
  end
  if db.mapGraves and d and d.graveyards then
    for _, g in ipairs(d.graveyards) do
      local x, y
      if zoneOnly then if g[4] == map then x, y = g[5], g[6] end else x, y = onMap(map, g[1], g[2], g[3]) end
      if x then out[#out + 1] = { kind = "grave", thing = "info", x = x, y = y, map = g[4], title = "Graveyard" } end
    end
  end

  -- Connections. Zone exits: zone maps only (a continent would be a thicket of arrows)
  if db.mapExits and zoneOnly and RD and RD.exits then
    local list = RD.exits[map]
    for i = 1, #(list or {}), 3 do
      out[#out + 1] = { kind = "exit", thing = "conn", x = list[i], y = list[i + 1], map = map, to = list[i + 2], title = zoneName(list[i + 2]) }
    end
  end

  -- boats, zeppelins, the tram and portals: a badge at every stop that has a ride from it; your side's and the neutral ones
  if RD and RD.transports then
    for _, t in ipairs(RD.transports) do
      local kind = t[3]
      local want = I.SETTING[kind] and db[I.SETTING[kind]] and I.KINDS[kind] and I.KINDS[kind].thing == "conn"
      if want and (t[4] == "N" or t[4] == fac) then
        local stops, rides = t[6] or {}, t[7] or {}
        for i, e in ipairs(stops) do
          local x, y
          if zoneOnly then if e[5] == map then x, y = e[6], e[7] end else x, y = onMap(map, e[2], e[3], e[4]) end
          if x then
            local dests = {}
            for _, r in ipairs(rides) do
              if r[1] == i and stops[r[2]] then dests[#dests + 1] = { name = plain(stops[r[2]][1]), secs = r[3] } end
            end
            if #dests > 0 then
              local names = {}
              for _, dd in ipairs(dests) do names[#names + 1] = dd.name end
              out[#out + 1] = { kind = kind, thing = "conn", x = x, y = y, map = e[5], from = plain(e[1]), dests = dests, interval = t[5],
                faction = t[4], route = t[2], title = I.KINDS[kind].label .. " to " .. table.concat(names, " or ") }
            end
          end
        end
      end
    end
  end

  -- flight points (your side and the neutral ones): the ones on the player's list and the ones not seen there yet are two switches
  if RD and RD.nodes and (db.mapFlight or db.mapFlightUnseen) then
    local known = Panoply.cdb and Panoply.cdb.knownTaxi or {}
    local flights = {}
    for nid, n in pairs(RD.nodes) do
      if (n[2] == "N" or n[2] == fac) and realFlightPoint(n) then
        local isKnown = known[n[1]] and true or false
        if (isKnown and db.mapFlight) or (not isKnown and db.mapFlightUnseen) then
          local x, y
          if zoneOnly then if n[6] == map then x, y = n[7], n[8] end else x, y = onMap(map, n[3], n[4], n[5]) end
          if x then
            flights[#flights + 1] = { kind = "flight", thing = "conn", x = x, y = y, map = n[6], title = n[1], npc = n[10], known = isKnown, node = nid }
          end
        end
      end
    end
    table.sort(flights, function(a, b) return a.node < b.node end)
    for _, f in ipairs(flights) do out[#out + 1] = f end
  end
  return out
end

-- Badges of one kind that stand closer than MERGE_PX on the screen are one badge with a count; the hover lists each ride.
-- W, H: the canvas in its own pixels; cs: its scale on screen.
function I:Merge(pins, W, H, cs)
  local out, heads = {}, {}
  for _, p in ipairs(pins) do
    local head
    if I.MERGES[p.kind] then
      for _, q in ipairs(heads) do
        if q.kind == p.kind then
          local dx, dy = (q.x - p.x) * W, (q.y - p.y) * H
          if sqrt(dx * dx + dy * dy) * cs < I.MERGE_PX then head = q break end
        end
      end
    end
    if head then
      head.members[#head.members + 1] = p
    else
      if I.MERGES[p.kind] then p.members = { p } heads[#heads + 1] = p end
      out[#out + 1] = p
    end
  end
  for _, p in ipairs(out) do
    if p.members and #p.members > 1 then
      local k = I.KINDS[p.kind]
      p.count = #p.members
      p.title = ("%d %s at %s"):format(p.count, k.plural, p.from or "")
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- Pin frames (pooled): a dark disc in a coloured ring with a small flat glyph; the approved flight pin; a zone exit chip
-------------------------------------------------------------------------------
local GLYPHS = {
  -- each glyph: list of { x, y, w, h, round } in a 16 x 16 box, centre origin (+x right, +y up)
  door = { { 0, -1, 6, 9 }, { 0, -2, 3, 6, nil, "dark" } },
  boat = { { 0, -2.5, 10, 3 }, { 0, 2, 1.5, 7 }, { 1.8, 3, 3, 3 } },
  blimp = { { 0, 0, 11, 6, true }, { 0, -4, 3, 2 } },
  tram = { { 0, 0.5, 10, 7 }, { -2.5, 0.5, 3, 3, nil, "dark" }, { 2.5, 0.5, 3, 3, nil, "dark" }, { 0, -4, 8, 1.5 } },
  portal = { { 0, 0, 8, 10, true }, { 0, 0, 4, 6, true, "dark" } },
  cross = { { 0, 0, 3, 10 }, { 0, 1.5, 9, 3 } },
}

local function colour(name) return Skin.colors[name] or Skin.colors.text end
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

-- the width of a line of text in its own face, with room for the stub's and the game's small differences (as the toolbar measures)
local function textW(fs, str)
  fs:SetText(str)
  return math.ceil(Skin.TextWidth(fs) * 1.04) + 3
end

-- a font size change on a pooled FontString (only when it changed)
local function fontSize(fs, pt, color)
  pt = max(7, floor(pt * 2 + 0.5) / 2)
  if fs.panoplyPt ~= pt then fs.panoplyPt = pt Skin.Font(fs, pt, color) end
  if color and fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], 1) end
end

function I:NewPin(parent)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true          -- placed at a map position; neighbours may touch
  p:SetSize(self.BASE, self.BASE)
  p.ring = p:CreateTexture(nil, "BACKGROUND"); p.ring:SetTexture(Skin.TEX.CircleMask); p.ring:SetAllPoints(p)
  p.disc = p:CreateTexture(nil, "BORDER"); p.disc:SetTexture(Skin.TEX.CircleMask)
  p.disc:SetPoint("CENTER", p, "CENTER", 0, 0)
  local c = Skin.colors.trailInk
  p.disc:SetVertexColor(c[1], c[2], c[3], 0.95)
  p.art = p:CreateTexture(nil, "ARTWORK")        -- the approved flight pin (Skin.SetPin: the game's own icon in WoW style)
  Skin.SetPin(p.art, "Flight", "Fly")
  p.art:SetAllPoints(p)
  p.art:Hide()
  p.bits = {}
  for i = 1, 4 do
    local t = p:CreateTexture(nil, "ARTWORK")
    t:SetTexture(Skin.WHITE)
    p.bits[i] = t
  end
  -- the flight pin's status: a green check (on your list) or a dim "?" (not seen yet)
  p.badge = p:CreateTexture(nil, "OVERLAY"); p.badge:SetTexture(Skin.TEX.CircleMask); p.badge:Hide()
  p.check = p:CreateTexture(nil, "OVERLAY", nil, 1); p.check:SetTexture(Skin.TEX.Check); p.check:Hide()
  p.q = Skin.Text(p, 9, Skin.colors.text, "OVERLAY"); p.q:SetText("?"); p.q:Hide()
  if p.q.SetJustifyH then p.q:SetJustifyH("CENTER") end
  if p.q.SetWordWrap then p.q:SetWordWrap(false) end
  -- the words beside a round badge: a small dark chip
  local tag = CreateFrame("Frame", nil, p)
  tag:EnableMouse(false)
  tag.panoplyLayoutSkip = true
  tag.fill, tag.line = Skin.Box(tag, "S", { fill = Skin.colors.trailInk, fillA = 0.9, line = Skin.colors.hairline })
  tag.text = Skin.Text(tag, self.TAG_PT, Skin.colors.text)
  if tag.text.SetWordWrap then tag.text:SetWordWrap(false) end
  tag.text:SetPoint("CENTER", tag, "CENTER", 0, 0)
  tag:Hide()
  p.tag = tag
  -- a zone exit is one chip: an arrow, the next zone's name and its level range
  local chip = CreateFrame("Frame", nil, p)
  chip:EnableMouse(false)
  chip:SetAllPoints(p)
  chip.panoplyLayoutSkip = true
  chip.fill, chip.line = Skin.Box(chip, "S", { fill = Skin.colors.trailInk, fillA = 0.92, line = Skin.colors.inkSoft })
  chip.arrow = Skin.NavArrow(chip, "ARTWORK", 12)
  chip.name = Skin.Text(chip, self.TAG_PT, Skin.colors.text)
  chip.range = Skin.Text(chip, self.TAG_PT - 1, Skin.colors.inkSoft)
  for _, fs in ipairs({ chip.name, chip.range }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  chip:Hide()
  p.chip = chip
  if p.RegisterForClicks then p:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  p:SetScript("OnEnter", function(self) I:OnEnter(self) end)
  p:SetScript("OnLeave", function(self) I:OnLeave(self) end)
  p:SetScript("OnClick", function(self, button) I:OnClick(self, button) end)
  return p
end

-- where the arrow of a zone exit points: from the middle of the zone towards the exit, along the longer way (up, down, left, right)
local ANGLE = { up = 0, left = math.pi / 2, down = math.pi, right = -math.pi / 2 }
function I.Direction(x, y)
  local dx, dy = x - 0.5, y - 0.5
  if abs(dx) > abs(dy) then return dx > 0 and "right" or "left" end
  return dy > 0 and "down" or "up"
end

-- the edge colour of an exit chip: grey (below you), green (in your range), orange (above you); a city or an unchecked zone is plain
local function standingColour(standing)
  if standing == "below" then return Skin.colors.inkSoft end
  if standing == "in" then return Skin.colors.done end
  if standing == "above" then return Skin.colors.warn end
  return Skin.colors.hairline
end

-- How a mark is drawn. o = { px = the round badge's size, kk = the text scale, alpha, rgb (one colour for all, or nil: by kind), names }
function I:StylePin(p, pin, o)
  p.pin = pin
  local k = self.KINDS[pin.kind]
  local isExit = pin.kind == "exit"
  p:SetAlpha(o.alpha * ((pin.kind == "flight" and pin.known == false) and 0.6 or 1))
  p.tag:Hide()
  p.chip:Hide()
  p.badge:Hide(); p.check:Hide(); p.q:Hide()

  if isExit then
    -- the chip
    p.ring:Hide(); p.disc:Hide(); p.art:Hide()
    for _, bit in ipairs(p.bits) do bit:Hide() end
    local chip = p.chip
    local kk = o.kk
    local h = floor(self.CHIP_H * kk + 0.5)
    local Z = Panoply.ZoneLevels
    local range = Z and Z.Words(pin.to)
    local standing = Z and Z.Standing(pin.to, playerLevel())
    p.standing = standing
    fontSize(chip.name, self.TAG_PT * kk, Skin.colors.text)
    fontSize(chip.range, (self.TAG_PT - 1) * kk, Skin.colors.inkSoft)
    local pad, gap = floor(7 * kk + 0.5), floor(5 * kk + 0.5)
    local a = floor(12 * kk + 0.5)
    local w = pad + a
    chip.name:ClearAllPoints(); chip.range:ClearAllPoints(); chip.arrow:ClearAllPoints()
    chip.arrow:SetSize(a, a)
    chip.arrow:SetPoint("LEFT", chip, "LEFT", pad, 0)
    local rgb = o.rgb or Skin.colors.heading
    chip.arrow:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
    if Panoply.Arrow and Panoply.Arrow.SetRotation then Panoply.Arrow.SetRotation(chip.arrow, ANGLE[self.Direction(pin.x, pin.y)]) end
    chip.arrow:Show()
    if (o.names == "hover" or p.collapsed) and not p.hover then
      -- names on hover (the setting, or p.collapsed: another exit's name was in the way): the chip is only its arrow until the mouse is on it
      chip.name:Hide(); chip.range:Hide()
      w = w + pad
    else
      chip.name:SetText(pin.title)
      local nw = textW(chip.name, pin.title)
      chip.name:SetPoint("LEFT", chip, "LEFT", w + gap, 0)
      chip.name:Show()
      w = w + gap + nw
      if range then
        local rw = textW(chip.range, range)
        chip.range:SetText(range)
        chip.range:SetPoint("LEFT", chip, "LEFT", w + gap, 0)
        chip.range:Show()
        w = w + gap + rw
      else
        chip.range:Hide()
      end
      w = w + pad
    end
    p:SetSize(w, h)
    local edge = standingColour(standing)
    chip.line:SetVertexColor(edge[1], edge[2], edge[3], 1)
    chip:Show()
    return
  end

  -- a round badge
  local size = o.px
  p:SetSize(size, size)
  if k.art then
    -- an approved art pin: no ring, disc or glyph of ours
    p.ring:Hide(); p.disc:Hide()
    for _, bit in ipairs(p.bits) do bit:Hide() end
    p.art:Show()
    Look.Tint(p.art, o.rgb)
    -- on your list: a green check; not seen yet: dimmed (above) with a "?"
    local bs = max(6, floor(size * 0.5 + 0.5))
    p.badge:SetSize(bs, bs); p.badge:ClearAllPoints(); p.badge:SetPoint("CENTER", p, "BOTTOMRIGHT", -1, 2)
    p.q:SetText("?")
    if pin.known then
      local g = Skin.colors.done
      p.badge:SetVertexColor(g[1], g[2], g[3], 1)
      p.check:SetSize(max(4, bs - 3), max(4, bs - 3)); p.check:ClearAllPoints(); p.check:SetPoint("CENTER", p.badge, "CENTER", 0, 0)
      p.check:SetVertexColor(Skin.colors.trailInk[1], Skin.colors.trailInk[2], Skin.colors.trailInk[3], 1)
      p.badge:Show(); p.check:Show()
    else
      local g = Skin.colors.dim
      p.badge:SetVertexColor(g[1], g[2], g[3], 1)
      p.q:ClearAllPoints(); p.q:SetPoint("CENTER", p.badge, "CENTER", 0, 0); p.q:SetWidth(bs + 4)
      fontSize(p.q, max(7, bs * 0.9), Skin.colors.text)
      p.badge:Show(); p.q:Show()
    end
  else
    p.art:Hide(); p.ring:Show(); p.disc:Show()
    local r = o.rgb or colour(k.ring)
    p.ring:SetVertexColor(r[1], r[2], r[3], 1)
    local inner = size - 4
    p.disc:SetSize(inner, inner)
    local g = GLYPHS[k.glyph]
    local s = size / 16
    for i, bit in ipairs(p.bits) do
      local spec = g[i]
      if spec then
        bit:ClearAllPoints()
        bit:SetPoint("CENTER", p, "CENTER", spec[1] * s, spec[2] * s)
        bit:SetSize(spec[3] * s, spec[4] * s)
        if spec[6] == "dark" then
          local d = Skin.colors.trailInk
          bit:SetVertexColor(d[1], d[2], d[3], 1)
        else
          local lc = Skin.colors.text
          bit:SetVertexColor(lc[1], lc[2], lc[3], 1)
        end
        bit:Show()
      else
        bit:Hide()
      end
    end
  end

  -- the words beside the badge
  local words
  if pin.kind == "flight" then
    if o.cont and pin.known then words = plain(pin.title) end
  elseif pin.thing == "conn" then
    words = pin.count and (pin.count .. " " .. k.plural) or pin.title
  end
  p.hasWords = words ~= nil
  if words then
    local tag = p.tag
    local kk = o.kk
    fontSize(tag.text, self.TAG_PT * kk, Skin.colors.text)
    local tw = textW(tag.text, words)
    tag:SetSize(tw + floor(10 * kk + 0.5), floor(20 * kk + 0.5))
    tag:ClearAllPoints()
    if pin.x > 0.7 then tag:SetPoint("RIGHT", p, "LEFT", -3, 0) else tag:SetPoint("LEFT", p, "RIGHT", 3, 0) end
    if o.names ~= "hover" or p.hover then tag:Show() end
  end
  -- a merged badge carries its count in a small bubble at its corner
  if pin.count and k.glyph then
    local bs = max(8, floor(size * 0.55 + 0.5))
    local g = Skin.colors.trailInk
    p.badge:SetSize(bs, bs); p.badge:ClearAllPoints(); p.badge:SetPoint("CENTER", p, "TOPRIGHT", -1, -1)
    p.badge:SetVertexColor(g[1], g[2], g[3], 1)
    p.q:SetText(tostring(pin.count))
    p.q:ClearAllPoints(); p.q:SetPoint("CENTER", p.badge, "CENTER", 0, 0); p.q:SetWidth(bs + 4)
    fontSize(p.q, max(7, bs * 0.9), Skin.colors.text)
    p.badge:Show(); p.q:Show()
  end
end

-------------------------------------------------------------------------------
-- Tooltip and click
-------------------------------------------------------------------------------
local function line(GT, t, r, g, b) if GT.AddLine then GT:AddLine(t, r, g, b, true) end end

-- the words of one boat, zeppelin, tram or portal ride (one line for where from and to, one for the times)
local function rideLines(pin, lines, soft, headed)
  local k = I.KINDS[pin.kind]
  for _, d in ipairs(pin.dests or {}) do
    if headed then lines[#lines + 1] = { k.label .. " to " .. d.name, Skin.colors.heading } end
    if pin.kind == "portal" then
      lines[#lines + 1] = { ("%s to %s."):format(pin.from, d.name), soft }
      lines[#lines + 1] = { ("A portal: Panoply Suite's route counts %s for it."):format(dur(d.secs or 5)), Skin.colors.text }
    else
      local what = pin.kind == "ship" and "boat" or (pin.kind == "zeppelin" and "zeppelin" or "tram")
      local fw = FACTION[pin.faction] or ""
      lines[#lines + 1] = { ("%s to %s. %s%s."):format(pin.from, d.name, fw, fw ~= "" and (" " .. what) or what), soft }
      local t = {}
      if pin.interval and pin.interval > 4 then t[#t + 1] = ("Leaves about every %s."):format(dur(pin.interval)) end
      if d.secs then t[#t + 1] = ("The trip takes about %s."):format(dur(d.secs)) end
      if #t > 0 then lines[#lines + 1] = { table.concat(t, " "), Skin.colors.text } end
    end
  end
end

-- the legs that start at a flight point: { dest node id, leg, known } for the points of your side
function I:Flights(pin)
  local RD = routeData()
  local out = {}
  if not (RD and RD.legs and RD.nodes and pin.node) then return out end
  local known = Panoply.cdb and Panoply.cdb.knownTaxi or {}
  local fac = myFaction()
  for _, l in ipairs(RD.legs) do
    if l[2] == pin.node then
      local n = RD.nodes[l[3]]
      if n and (n[2] == "N" or n[2] == fac) and realFlightPoint(n) then
        out[#out + 1] = { node = l[3], leg = l, name = plain(n[1]), known = known[n[1]] and true or false }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function I:Describe(pin)
  local lines = {}
  local soft = Skin.colors.qpTipDim
  if pin.kind == "dungeon" or pin.kind == "raid" then
    for _, e in ipairs(pin.instances) do
      local i = e.inst
      local kind = i.kind == "raid" and "Raid" or "Dungeon"
      local text = ("%s: %d players, monsters level %d to %d"):format(kind, i.size, i.mobs[1], i.mobs[2])
      if e.via and e.via > 0 then text = text .. " (inside " .. self:InstName(e.via) .. ")" end
      lines[#lines + 1] = { i.name, Skin.colors.heading }
      lines[#lines + 1] = { text, soft }
      if i.enter and i.enter > 0 then lines[#lines + 1] = { ("Enter from level %d."):format(i.enter), soft } end
      if i.req and i.req ~= "" then lines[#lines + 1] = { i.req, soft } end
    end
    lines[#lines + 1] = { "Click: point the arrow here. Right-click: open the instance map.", Skin.colors.qpTipText }
  elseif pin.kind == "grave" then
    lines[#lines + 1] = { "A spirit healer stands here.", soft }
    lines[#lines + 1] = { "Click: point the arrow here.", Skin.colors.qpTipText }
  elseif pin.kind == "exit" then
    lines[#lines + 1] = { ("The way to %s."):format(pin.title), soft }
    local Z = Panoply.ZoneLevels
    if Z and Z.IsCity(pin.to) then
      lines[#lines + 1] = { "A city.", soft }
    else
      local range = Z and Z.Words(pin.to)
      if range then
        local st = Z.Standing(pin.to, playerLevel())
        if st == "in" then lines[#lines + 1] = { ("Levels %s. Your level is in its range."):format(range), Skin.colors.qpTipReady }
        elseif st == "below" then lines[#lines + 1] = { ("Levels %s. It is below your level."):format(range), soft }
        elseif st == "above" then lines[#lines + 1] = { ("Levels %s. It is above your level."):format(range), Skin.colors.warn }
        else lines[#lines + 1] = { ("Levels %s."):format(range), soft } end
      end
    end
    lines[#lines + 1] = { "Click: point the arrow here.", Skin.colors.qpTipText }
  elseif pin.kind == "flight" then
    lines[#lines + 1] = pin.known and { "You know this flight path.", Skin.colors.qpTipReady }
      or { "Not on your list yet. Panoply Suite only learns a flight path when you open a flight master's map.", soft }
    if pin.npc and pin.npc ~= "" then lines[#lines + 1] = { "Flight master: " .. pin.npc, soft } end
    local sure, maybe = {}, {}
    for _, f in ipairs(self:Flights(pin)) do
      if pin.known and f.known then sure[#sure + 1] = f.name else maybe[#maybe + 1] = f.name end
    end
    if #sure > 0 then lines[#lines + 1] = { "Flies to: " .. table.concat(sure, ", ") .. " (solid lines).", Skin.colors.text } end
    if #maybe > 0 then
      local why = pin.known and "Not seen at a flight master yet, so no flight there: " or "Flights from here once it is on your list: "
      lines[#lines + 1] = { why .. table.concat(maybe, ", ") .. " (dashed lines).", soft }
    end
    lines[#lines + 1] = { "Click: point the arrow here.", Skin.colors.qpTipText }
  else
    -- boats, zeppelins, the tram, portals: one ride, or the rides of a merged badge
    local members = pin.members or { pin }
    if #members > 1 then
      for _, m in ipairs(members) do rideLines(m, lines, soft, true) end
    else
      rideLines(pin, lines, soft, false)
    end
    lines[#lines + 1] = { "Click: point the arrow here.", Skin.colors.qpTipText }
  end
  return lines
end

function I:InstName(id)
  local d = M.Data()
  for _, i in ipairs(d and d.instances or {}) do if i.id == id then return i.name end end
  return "another instance"
end

function I:Title(pin)
  if pin.kind == "dungeon" or pin.kind == "raid" then return pin.title end
  if pin.kind == "flight" then return pin.title end
  if pin.kind == "grave" then return "Graveyard" end
  return pin.title or ""
end

function I:ShowTip(p)
  local GT = _G.GameTooltip
  local pin = p.pin
  if not (GT and pin) then return end
  GT:SetOwner(p, "ANCHOR_RIGHT")
  GT:SetText(self:Title(pin), 0.95, 0.84, 0.55, 1, true)
  for _, l in ipairs(self:Describe(pin)) do
    local c = l[2]
    line(GT, l[1], c[1], c[2], c[3])
  end
  GT:Show()
end

function I:OnEnter(p)
  p.hover = true
  self:ShowTip(p)
  local pin = p.pin
  if pin and pin.kind == "flight" then self:ShowFlights(pin) end
  -- names on hover (the setting, or words that were left out because they would have covered other words): the words of this one badge appear
  if pin and pin.thing == "conn" and (Look.Names("conn", "wm") == "hover" or p.collapsed or p.tagHidden) then
    if pin.kind == "exit" then self:StylePin(p, pin, self.lastOpts or { px = self.BASE, kk = 1, alpha = 1, names = "always" })
    elseif p.hasWords then p.tag:Show() end
  end
end

function I:OnLeave(p)
  p.hover = nil
  if _G.GameTooltip then GameTooltip:Hide() end
  self:HideFlights()
  local pin = p.pin
  if pin and pin.thing == "conn" and (Look.Names("conn", "wm") == "hover" or p.collapsed or p.tagHidden) then
    if pin.kind == "exit" and self.lastOpts then self:StylePin(p, pin, self.lastOpts)
    else p.tag:Hide() end
  end
end

function I:OnClick(p, button)
  local pin = p.pin
  if not pin then return end
  if button == "RightButton" and (pin.kind == "dungeon" or pin.kind == "raid") and M.Instances then
    M.Instances:Open(pin.instances[1].inst.id)
    return
  end
  if button ~= "LeftButton" and button ~= nil then return end
  local label = pin.kind == "exit" and ("Exit to " .. pin.title) or self:Title(pin)
  M:PointAt(pin.map, pin.x, pin.y, label)
  self.lastClick = { map = pin.map, x = pin.x, y = pin.y, label = label }
end

-------------------------------------------------------------------------------
-- Flight lines: only while a flight point is hovered (our decision 11), along the real flight legs: solid to the points that can be
-- flown to, dashed to the others
-------------------------------------------------------------------------------
I.LINE_MAX = 320
I.DASH, I.GAP, I.LINE_W = 9, 7, 3

local function polyline(pts)
  local xs, ys = {}, {}
  for _, q in ipairs(pts) do xs[#xs + 1] = q[1] ys[#ys + 1] = q[2] end
  return xs, ys
end

function I:FxPen(layer)
  local Tr = Panoply.Trail
  if not (Tr and Tr.NewPen) then return nil end
  if not self.fx then
    self.fx = CreateFrame("Frame", nil, layer)
    self.fx:SetAllPoints(layer)
    self.fx.panoplyLayoutSkip = true
    self.fxPen = Tr:NewPen(self.fx, 0, self.LINE_MAX, "wm")
  end
  if self.fx:GetParent() ~= layer and self.fx.SetParent then self.fx:SetParent(layer) self.fx:SetAllPoints(layer) end
  if self.fx.SetFrameLevel then self.fx:SetFrameLevel(layer:GetFrameLevel()) end
  self.fxPen.maxL = self.LINE_MAX
  return self.fxPen
end

-- one flight leg as a list of { x, y } in canvas pixels (TOPLEFT offsets), cut to the map
local function legPoints(RD, leg, map, W, H)
  local rc = rectOf(map)
  if not (rc and RD.Trail) then return nil end
  local pts = RD.Trail(leg)
  local Tr = Panoply.Trail
  local out, cur = {}, nil
  local cl = Tr.RectClip(0, 0, 1, 1)
  for i = 1, #pts - 1 do
    local x0, y0 = frac(rc, pts[i][1], pts[i][2])
    local x1, y1 = frac(rc, pts[i + 1][1], pts[i + 1][2])
    local a, b, c2, d = cl:seg(x0, y0, x1, y1)
    if a then
      if not cur or abs(cur[#cur][1] - a * W) > 0.5 or abs(cur[#cur][2] + b * H) > 0.5 then
        cur = { { a * W, -b * H } }
        out[#out + 1] = cur
      end
      cur[#cur + 1] = { c2 * W, -d * H }
    else
      cur = nil
    end
  end
  return out
end

-- a solid line, or one cut into dashes (the pattern runs on along the whole polyline)
local function stroke(pen, pts, th, c, a, dashed)
  local drawn, run = 0, 0
  local period = I.DASH + I.GAP
  for i = 1, #pts - 1 do
    local x0, y0, x1, y1 = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
    local dx, dy = x1 - x0, y1 - y0
    local L = sqrt(dx * dx + dy * dy)
    if L > 0 then
      if not dashed then
        if pen:Line(x0, y0, x1, y1, th, c, a, 1.5, "fly", 0, "core") then drawn = drawn + 1 end
      else
        local ux, uy = dx / L, dy / L
        local k = floor(run / period)
        while k * period < run + L do
          local s = max(k * period, run) - run
          local e = min(k * period + I.DASH, run + L) - run
          if e > s and pen:Line(x0 + ux * s, y0 + uy * s, x0 + ux * e, y0 + uy * e, th, c, a, 1.5, "fly", 0, "core") then drawn = drawn + 1 end
          k = k + 1
        end
      end
      run = run + L
    end
  end
  return drawn
end

function I:ShowFlights(pin)
  local layer = self.layer
  local RD = routeData()
  local Tr = Panoply.Trail
  if not (layer and RD and Tr and Tr.RectClip and pin and pin.node) then return 0 end
  local pen = self:FxPen(layer)
  if not pen then return 0 end
  -- the canvas size the marks were placed with (the same numbers, so a line ends exactly at the mark it leaves from)
  local W, H = self.canvasW or layer:GetWidth() or 1002, self.canvasH or layer:GetHeight() or 668
  local map = C.WorldMapID() or pin.map
  pen:Begin()
  local solid = Tr:Color("fly")
  local dashc = Skin.colors.text
  local n = 0
  for _, f in ipairs(self:Flights(pin)) do
    local sure = pin.known and f.known
    for _, run in ipairs(legPoints(RD, f.leg, map, W, H) or {}) do
      n = n + stroke(pen, run, I.LINE_W, sure and solid or dashc, sure and 1 or 0.9, not sure)
    end
  end
  pen:End()
  self.fx:Show()
  self.flightLines = n
  return n
end

function I:HideFlights()
  if self.fxPen then self.fxPen:Clear() end
  self.flightLines = 0
end

-------------------------------------------------------------------------------
-- Words never cover other words. Boats, zeppelins, the tram, portals and flight points carry their words in a small chip beside the badge,
-- a zone exit is a chip of its own; marks that stand close put their words on top of each other (Panoply Suite Studio's step 2 previews: the known
-- flight points, the tram and a "2 boats" badge on the continent map). After every mark is styled, the words are taken in order of
-- importance (I.RANK) and each one that would touch the words already kept (I.LABEL_GAP of air) is given up: a badge's chip is hidden
-- (p.tagHidden), an exit chip shrinks to its arrow (p.collapsed). The mark stays; its words show while the mouse is on it (OnEnter).
-------------------------------------------------------------------------------
-- the box of a mark's words in the layer's own pixels (y down): l, r, top, bottom; nil when the mark shows no words now
function I:LabelBox(p, W, H)
  local pin = p.pin
  if not pin then return nil end
  local cx, cy = pin.x * W, pin.y * H
  if pin.kind == "exit" then
    if not (p.chip:IsShown() and p.chip.name:IsShown()) then return nil end
    local w, h = p:GetWidth(), p:GetHeight()
    return cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
  end
  if not (p.hasWords and p.tag:IsShown()) then return nil end
  local tw, th = p.tag:GetWidth(), p.tag:GetHeight()
  local half = p:GetWidth() / 2
  local l = pin.x > 0.7 and (cx - half - 3 - tw) or (cx + half + 3)      -- the same sides StylePin anchors the chip to
  return l, l + tw, cy - th / 2, cy + th / 2
end

-- Give up the words that collide. used: how many of self.pins are in use; W, H: the canvas the marks were placed on. Returns how many marks lost
-- their words. Each such mark keeps the pin it lost to in p.lostTo.
function I:SeparateLabels(used, W, H)
  local items = {}
  for i = 1, used do
    local p = self.pins[i]
    local l, r, t, b = self:LabelBox(p, W, H)
    if l then items[#items + 1] = { p = p, l = l, r = r, t = t, b = b, rank = I.RANK[p.pin.kind] or 9, n = i } end
  end
  table.sort(items, function(a, c) if a.rank ~= c.rank then return a.rank < c.rank end return a.n < c.n end)
  local kept, lost, gap = {}, 0, I.LABEL_GAP
  for _, it in ipairs(items) do
    local hit
    for _, k in ipairs(kept) do
      if it.l < k.r + gap and it.r > k.l - gap and it.t < k.b + gap and it.b > k.t - gap then hit = k break end
    end
    if hit then
      lost = lost + 1
      it.p.lostTo = hit.p.pin
      if it.p.pin.kind == "exit" then
        it.p.collapsed = true
        self:StylePin(it.p, it.p.pin, self.lastOpts)
      else
        it.p.tagHidden = true
        it.p.tag:Hide()
      end
    else
      kept[#kept + 1] = it
    end
  end
  self.labelsLost = lost
  return lost
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
function I:Layer()
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

-- the size, text scale, opacity and colour of one thing on the world map, from its settings (the Look of the map)
function I:Options(thing, cont, cs)
  local f = Look.Size(thing, "wm") * (cont and self.CONT_SCALE or 1)
  return { px = self.BASE * f / max(0.2, cs), kk = clamp(f, 0.6, 1.8) / max(0.2, cs), alpha = Look.Alpha(thing, "wm"),
    rgb = Look.RGB(thing, "wm"), names = thing == "conn" and Look.Names("conn", "wm") or "always", cont = cont, thing = thing }
end

function I:Refresh(why)
  self.pins = self.pins or {}
  local used = 0
  local wm = C.WorldMap()
  local map = C.WorldMapID()
  if M:Wants("icons") and wm and wm.IsShown and wm:IsShown() and map then
    local layer, canvas = self:Layer()
    if layer then
      local lvl = M:IconLevel()
      if layer.SetFrameLevel and layer:GetFrameLevel() ~= lvl then layer:SetFrameLevel(lvl) end
      if C.FloorMapAlpha then C.FloorMapAlpha(layer) C.HookMapAlpha() end
      local markLevel = M:MarkLevel(layer:GetFrameLevel())
      local W, H = canvas:GetWidth() or 1002, canvas:GetHeight() or 668
      self.canvasW, self.canvasH = W, H
      local Tr = Panoply.Trail
      local cs = Tr and Tr.CanvasScale and Tr:CanvasScale(canvas) or 1
      local cont = isContinent(map)
      local opts = { info = self:Options("info", cont, cs), conn = self:Options("conn", cont, cs) }
      self.lastOpts = opts.conn
      local list = self:Merge(self:Collect(map), W, H, cs)
      for _, pin in ipairs(list) do
        used = used + 1
        local p = self.pins[used]
        if not p then p = self:NewPin(layer) self.pins[used] = p end
        p.hover, p.collapsed, p.tagHidden, p.lostTo = nil, nil, nil, nil
        self:StylePin(p, pin, opts[pin.thing])
        p:ClearAllPoints()
        p:SetPoint("CENTER", layer, "TOPLEFT", pin.x * W, -pin.y * H)
        if p.SetFrameLevel then p:SetFrameLevel(markLevel) end
        p.inUse, p.underCard = true, false
        p:Show()
      end
      self:SeparateLabels(used, W, H)
    end
  end
  for i = used + 1, #self.pins do local q = self.pins[i] q:Hide() q.inUse, q.underCard = false, false end
  if used == 0 then self:HideFlights() self.labelsLost = 0 end
  self.shown = used
  -- the route card draws over the corner of the map after the marks: keep the marks it would half cover out from under it
  if not self.cardHooked and Panoply.Trail and C.Hook(Panoply.Trail, "Card", function() I:AvoidCard() end) then self.cardHooked = true end
  self:AvoidCard()
  return used
end

-------------------------------------------------------------------------------
-- The route card sits in a corner of the map, over whatever is drawn there. A mark (or its words) that the card would half cover, with the
-- brass corner caps of the card on top of it, is not drawn while the card is there: it would show as a half-hidden button under a corner.
-- The layout checker's cap rule found these (a flight pin, the "Stormwind City" and "Westfall" exits, "Boat to the Forgotten Coast").
-- Only marks on the map canvas, only while the card is shown, and the mark comes back when the card moves or goes.
-------------------------------------------------------------------------------
I.CARD_MARGIN = 8       -- the card's corner caps reach 2 px outside it, and the checker keeps 2 px clear of them

-- the screen rectangle of a frame: left, right, bottom, top (nil when the game has not laid the frame out)
local function screenRect(f)
  if not (f and f.GetLeft and f.GetRight and f.GetBottom and f.GetTop) then return nil end
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  if not (l and r and b and t) then return nil end
  local s = tonumber(f.GetEffectiveScale and f:GetEffectiveScale()) or 1
  return l * s, r * s, b * s, t * s
end

-- a mark's box on the screen: the badge or chip and the words beside it when they are drawn
local function markBox(p)
  local l, r, b, t = screenRect(p)
  if not l then return nil end
  if p.tag and p.tag:IsShown() and not p.chip:IsShown() then
    local tl, tr, tb, tt = screenRect(p.tag)
    if tl then l, r, b, t = math.min(l, tl), math.max(r, tr), math.min(b, tb), math.max(t, tt) end
  end
  return l, r, b, t
end

function I:AvoidCard()
  local Tr = Panoply.Trail
  local card = Tr and Tr.card
  -- the card can be shown, moved or hidden without a call of ours (the trail hides it with no route): its own show and hide are the other cue
  if card and not card.panoplyAvoidHooked and card.HookScript then
    card.panoplyAvoidHooked = true
    card:HookScript("OnShow", function() I:AvoidCard() end)
    card:HookScript("OnHide", function() I:AvoidCard() end)
  end
  local cl, cr, cb, ct
  if card and card.IsShown and card:IsShown() then cl, cr, cb, ct = screenRect(card) end
  local m, n = self.CARD_MARGIN, 0
  for _, p in ipairs(self.pins or {}) do
    if p.inUse then
      local under = false
      if cl then
        local l, r, b, t = markBox(p)
        under = l ~= nil and l < cr + m and r > cl - m and b < ct + m and t > cb - m
      end
      if under ~= (p.underCard or false) then
        p.underCard = under
        if under then p:Hide() else p:Show() end
      end
      if under then n = n + 1 end
    end
  end
  self.underCard = n
  return n
end

function I:Disable()
  for _, p in ipairs(self.pins or {}) do p:Hide() p.inUse = false p.underCard = false end
  self:HideFlights()
  self.shown = 0
end

-------------------------------------------------------------------------------
-- The live preview of the Look of the map: a few sample marks on a true-size piece of the world map. Drawn by the same code as the
-- map (StylePin), from the same settings, so the preview cannot disagree with the map.
-------------------------------------------------------------------------------
I.SAMPLES = {
  info = {
    { kind = "dungeon", thing = "info", x = 26, y = 22, title = "Dungeon" },
    { kind = "raid", thing = "info", x = 62, y = 18, title = "Raid" },
    { kind = "grave", thing = "info", x = 84, y = 46, title = "Graveyard" },
  },
  conn = {
    { kind = "ship", thing = "conn", x = 14, y = 16, from = "Menethil Harbor", title = "Boat to Auberdine", dests = { { name = "Auberdine", secs = 96 } } },
    { kind = "flight", thing = "conn", x = 14, y = 42, title = "Menethil Harbor", known = true },
    { kind = "exit", thing = "conn", x = 70, y = 50, to = 1432, title = "Loch Modan" },
  },
}

function I:DrawSample(layer, thing, where)
  layer.pins = layer.pins or {}
  local samples = self.SAMPLES[thing] or {}
  local opts = self:Options(thing, false, 1)
  for i, s in ipairs(samples) do
    local p = layer.pins[i]
    if not p then p = self:NewPin(layer) p:EnableMouse(false) layer.pins[i] = p end
    if where == "wm" then
      p.hover = nil
      self:StylePin(p, s, opts)
      p:ClearAllPoints()
      p:SetPoint("CENTER", layer, "TOPLEFT", s.x, -s.y)
      p:Show()
    else
      p:Hide()
    end
  end
  for i = #samples + 1, #layer.pins do layer.pins[i]:Hide() end
end
Look.Draw.info = function(layer, where) I:DrawSample(layer, "info", where) end
Look.Draw.conn = function(layer, where) I:DrawSample(layer, "conn", where) end
