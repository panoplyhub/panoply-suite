-- Map module, the toolbar on the world map (bottom edge of the map window).
--   [grip] [zone name v] [Levels 30 to 45] [You 30.4, 72.6] [Cursor 54.2, 17.6]     [search] [Places v] [Layers v] [Dungeons]
-- The zone name opens the jump menu (continent tabs and a grid of zones). Layers switches the icon
-- groups and the other Panoply Suite layers. Places switches the trainers, services, vendors and stations. Go to opens the search window
-- (Navigate.lua: the magnifier). Dungeons opens the instance map window. Every width is measured, so nothing overlaps at
-- 1.3x text or in the small map window; what does not fit is dropped (level range first, then your
-- coordinates, then the cursor's).
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local pcallv = M.pc
local SP = Skin.SP

-- The world map's frame strata, MEDIUM when the game will not say (Forever can answer with a secret value, which SetFrameStrata rejects).
local function worldMapStrata(wm)
  local ok, s = pcall(function() return wm.GetFrameStrata and wm:GetFrameStrata() end)
  s = ok and C.Readable(s)
  return type(s) == "string" and s or "MEDIUM"
end

local B = {}
M.Bar = B
B.HEIGHT = 34
B.EDGE = 8                 -- room inside the bar's ends
B.GAP = 8                  -- between parts
B.RAISE = 10               -- the bar's distance from the window's bottom edge
B.CARD_GAP = 8             -- the route card sits this far above the bar

-- The jump menu's continents: { map, label }.
B.CONTINENTS = { { 947, "Azeroth" }, { 1414, "Kalimdor" }, { 1415, "Eastern Kingdoms" } }

local function data() local qd = _G.PanoplySuiteQuestData return qd and qd.MapData or nil end
M.Data = data

-------------------------------------------------------------------------------
-- Zones for the jump menu: our own list (from the client's map table), kept to the maps this client has
-------------------------------------------------------------------------------
function M:ZonesOf(cont)
  local d = data()
  local list = d and d.zones and d.zones[cont]
  local out = {}
  if list then
    for _, id in ipairs(list) do
      local name = C.MapName(id)
      if name then out[#out + 1] = { id = id, name = name } end
    end
  else
    -- no data add-on: ask the game for the continent's zones
    local f = C.G("C_Map.GetMapChildrenInfo")
    local kids = f and pcallv(f, cont, 3)
    for _, k in ipairs(type(kids) == "table" and kids or {}) do
      if k.mapID and k.name then out[#out + 1] = { id = k.mapID, name = k.name } end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- the continent a map belongs to (947 stays itself)
function M:ContinentOf(map)
  if not map then return nil end
  if map == 947 then return 947 end
  local d = data()
  if d and d.zones then
    for cont, list in pairs(d.zones) do
      if cont == map then return cont end
      for _, id in ipairs(list) do if id == map then return cont end end
    end
  end
  return nil
end

-- The zone's CHECKED level range for the client in use (Data/ZoneLevels.lua: a range nobody has checked in the game gives none, and a client
-- never reads the other client's range; our decisions 9 and 26). The list that came with the map data (MapData.zoneLevels) is not read: it
-- is a tie-breaker for the data builder, not a range anyone has checked.
function M:ZoneLevels(map)
  local Z = Panoply.ZoneLevels
  if Z then return Z.Range(map) end
  return nil
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------
local function text(parent, size, color)
  local fs = Skin.Text(parent, size or 12, color or Skin.colors.text)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

function B:Create()
  if self.frame then return self.frame end
  local wm = C.WorldMap()
  local sc = wm and wm.ScrollContainer
  if not sc then return nil end
  local f = CreateFrame("Frame", "PanoplySuiteMapBar", sc)
  self.frame = f
  f:SetHeight(self.HEIGHT)
  f:EnableMouse(true)                       -- clicks on the bar are not clicks on the map
  Skin.Panel(f, 0.94, true, "M", true)
  f:SetFrameStrata(worldMapStrata(wm))
  f:Hide()

  -- grip: six dots; drag to move the map window
  local g = CreateFrame("Button", nil, f)
  g:SetSize(18, 26)
  g.dots = {}
  for i = 0, 5 do
    local t = g:CreateTexture(nil, "ARTWORK")
    t:SetTexture(Skin.TEX.CircleMask); t:SetSize(3, 3)
    t:SetPoint("CENTER", g, "CENTER", ((i % 2) - 0.5) * 6, (1 - math.floor(i / 2)) * 6)
    local c = Skin.colors.iconIdle
    t:SetVertexColor(c[1], c[2], c[3], 1)
    g.dots[#g.dots + 1] = t
  end
  g:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" and M.Window then M.Window:StartMove() end end)
  g:SetScript("OnMouseUp", function() if M.Window then M.Window:StopMove() end end)
  Skin.Tooltip(g, "Move the map", "Hold and drag to move the map window. Map settings > Reset map position and size puts it back.")
  g:SetScript("OnEnter", function() if g.panoplyShowTip then g.panoplyShowTip() end end)
  g:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  f.grip = g

  f.zone = Skin.Button(f, "Zone", 150, 26, function() B:ToggleJump() end, "Jump to a zone", "Open a menu of every continent and zone. Click one to show its map.")
  f.zone.label:SetJustifyH("CENTER")
  f.chip = text(f, 12, Skin.colors.inkSoft)
  f.you = text(f, 12)
  f.cur = text(f, 12)
  f.layers = Skin.Button(f, "Layers", 80, 26, function(self) B:OpenLayers(self) end, "Layers", "Choose which icons Panoply Suite adds to the map.")
  f.places = Skin.Button(f, "Places", 80, 26, function(self) B:OpenPlaces(self) end, "Places", "Choose which trainers, services, vendors and crafting stations show on the map and the minimap.")
  f.go = Skin.IconButton(f, "Search", 26, function() if M.Navigate then M.Navigate:Toggle() end end, "Go to a place",
    "Type a place and the arrow takes you there: towns, dungeons, trainers, the auction house, flight masters. Save favourites, set a Home, add stops.")
  f.dungeons = Skin.Button(f, "Dungeons", 90, 26, function() if M.Instances then M.Instances:Toggle() end end, "Dungeon and raid maps",
    "Open the map of every dungeon and raid: facts, floor plan and numbered bosses.")
  -- fixed-width measuring strings (so the numbers changing never move the layout)
  f.measure = text(f, 12)
  f.measure:Hide()
  f.measure.panoplyLayoutSkip = true

  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.1 then return end
    acc = 0
    B:UpdateCoords()
  end)
  return f
end

-- The stub and the game measure a line a little differently (about 1 to 2 %: seen in the preview
-- renders), so every measured line gets 4 % and 3 px of room.
local function width(fs, str)
  fs:SetText(str)
  return math.ceil(Skin.TextWidth(fs) * 1.04) + 3
end

-- measured width of a string in the bar's text face
function B:Measure(str)
  local f = self.frame
  return width(f.measure, str)
end

-------------------------------------------------------------------------------
-- What the bar shows
-------------------------------------------------------------------------------
local function coord(x, y) return ("%.1f, %.1f"):format(x * 100, y * 100) end

function B:UpdateCoords()
  local f = self.frame
  if not (f and f:IsShown()) then return end
  if f.you:IsShown() then
    local pm, px, py = C.GetPlayerPos()
    if pm and pm == C.WorldMapID() then f.you:SetText("You  " .. coord(px, py)) else f.you:SetText("You  --") end
  end
  if f.cur:IsShown() then
    local cx, cy = C.WorldMapCursor()
    if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then f.cur:SetText("Cursor  " .. coord(cx, cy)) else f.cur:SetText("Cursor  --") end
  end
end

function B:Hide()
  if self.frame then self.frame:Hide() end
  if self.jump then self.jump:Hide() end
  if self.layersMenu then self.layersMenu:Hide() end
  if self.placesMenu then self.placesMenu:Hide() end
  self.lifted = false
  self:LiftCard()
end

-- Make room for the route card: it keeps its corner and rises above the bar.
-- Trail re-anchors the card on every redraw (and the dots drift): a hook on Trail:Card puts it back.
function B:LiftCard()
  local Tr = Panoply.Trail
  local card = Tr and Tr.card
  local wm = C.WorldMap()
  local sc = wm and wm.ScrollContainer
  if not (card and sc and card.IsShown and card:IsShown()) then return end
  local corner = Tr.cardCorner or "BOTTOMLEFT"
  local lift = self.lifted and (self.RAISE + self.HEIGHT + self.CARD_GAP) or 12
  card:ClearAllPoints()
  card:SetPoint(corner, sc, corner, corner == "BOTTOMLEFT" and 12 or -12, lift)
  -- the card has its final place now: the marks it would cover step aside (Icons.lua)
  if M.Icons and M.Icons.AvoidCard then M.Icons:AvoidCard() end
  if M.Places and M.Places.AvoidCard then M.Places:AvoidCard() end
end

function B:Refresh(why)
  local wm = C.WorldMap()
  local sc = wm and wm.ScrollContainer
  local bar = Panoply.db and Panoply.db.mapBar
  local wantBar = M.active and wm and wm.IsShown and wm:IsShown() and sc
  local hasData = data() and M.Instances and M.Instances:Count() > 0
  local showMain = wantBar and bar
  local showDungeons = wantBar and bar and hasData
  if not (showMain or showDungeons) then self:Hide() return end
  local f = self:Create()
  if not f then return end
  local lvl = C.WorldMapLevel("card")
  f:SetFrameLevel(lvl)
  f:SetFrameStrata(worldMapStrata(wm))
  self:Layout(f, sc, showMain and true or false, showDungeons and true or false)
  f:Show()
  self.lifted = true
  if not self.cardHooked and Panoply.Trail and C.Hook(Panoply.Trail, "Card", function() B:LiftCard() end) then self.cardHooked = true end
  self:LiftCard()
  self:UpdateCoords()
end

-- Place the parts left to right inside the available width.
function B:Layout(f, sc, main, dungeons)
  local W = tonumber(sc.w) or (sc.GetWidth and sc:GetWidth()) or 1002
  local avail = math.max(120, W - 24)
  local E, G = self.EDGE, self.GAP
  local y = 0
  local map = C.WorldMapID()
  local wantJump, wantCoords = main and M:Wants("jump"), main and M:Wants("coords") and Panoply.db.mapCoords
  local wantLayers = main
  local wantPlaces, wantGo = main, main
  local wantMove = main and M:Wants("move")
  local wantLevel = main and M:Wants("level")

  -- fixed things on the right
  local rightW = 0
  local dw, lw, pw, nw = 0, 0, 0, 0
  if dungeons then f.dungeons.label:SetText("Dungeons") dw = Skin.FitButton(f.dungeons, 80, 140) rightW = rightW + dw end
  if wantLayers then f.layers.label:SetText("Layers") lw = Skin.FitButton(f.layers, 70, 120) rightW = rightW + lw + (dw > 0 and G or 0) end
  if wantPlaces then f.places.label:SetText("Places") pw = Skin.FitButton(f.places, 70, 120) rightW = rightW + pw + (rightW > 0 and G or 0) end
  if wantGo then nw = 26 rightW = rightW + nw + (rightW > 0 and G or 0) end      -- a search icon: the narrowest way to keep it on the compact bar
  -- the zone name
  local zname = map and C.MapName(map) or "Map"
  local gw = wantMove and 18 or 0
  local zoneW = 0
  if wantJump then
    f.zone.label:SetText(zname)
    zoneW = math.min(190, math.max(110, math.ceil(Skin.TextWidth(f.zone.label) + 2 * SP.m + 14)))
  end
  -- the optional text parts, widest the numbers can get
  local lo, hi = M:ZoneLevels(map)
  local chipStr
  if wantLevel and lo then chipStr = lo == hi and ("Level %d"):format(lo) or ("Levels %d to %d"):format(lo, hi)
  elseif wantLevel and Panoply.ZoneLevels and Panoply.ZoneLevels.IsCity(map) then chipStr = "City" end
  local chipW = chipStr and (self:Measure(chipStr)) or 0
  local youW = wantCoords and self:Measure("You  99.9, 99.9") or 0
  local curW = wantCoords and self:Measure("Cursor  99.9, 99.9") or 0

  local function need(useChip, useYou, useCur, zw)
    local n = 2 * E + gw + (gw > 0 and G or 0) + zw + (zw > 0 and G or 0)
    if useChip and chipW > 0 then n = n + chipW + G end
    if useYou and youW > 0 then n = n + youW + G end
    if useCur and curW > 0 then n = n + curW + G end
    return n + rightW
  end
  local useChip, useYou, useCur = chipW > 0, youW > 0, curW > 0
  if need(useChip, useYou, useCur, zoneW) > avail then useChip = false end
  if need(useChip, useYou, useCur, zoneW) > avail then useYou = false end
  if need(useChip, useYou, useCur, zoneW) > avail then useCur = false end
  local zw = zoneW
  if need(useChip, useYou, useCur, zw) > avail and zw > 0 then zw = math.max(90, zoneW - (need(useChip, useYou, useCur, zw) - avail)) end

  -- bar size: full width when the main parts are drawn, snug around the Dungeons button otherwise
  local total = need(useChip, useYou, useCur, zw)
  local full = wantJump or wantCoords or wantMove
  local barW = full and avail or (E * 2 + rightW)
  f:SetWidth(barW)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", sc, "BOTTOM", 0, self.RAISE)
  f:SetHeight(self.HEIGHT)

  local x = E
  local function put(w, region, text)
    region:ClearAllPoints()
    region:SetPoint("LEFT", f, "LEFT", x, y)
    if region.SetWidth and text then region:SetWidth(w) end
    region:Show()
    x = x + w + G
  end
  if gw > 0 then f.grip:ClearAllPoints() f.grip:SetPoint("LEFT", f, "LEFT", x, y) f.grip:Show() x = x + gw + G else f.grip:Hide() end
  if zw > 0 then
    f.zone:SetWidth(zw)
    f.zone:ClearAllPoints(); f.zone:SetPoint("LEFT", f, "LEFT", x, y); f.zone:Show(); x = x + zw + G
  else f.zone:Hide() end
  if useChip and chipW > 0 then f.chip:SetText(chipStr) put(chipW, f.chip, true) else f.chip:Hide() end
  if useYou and youW > 0 then put(youW, f.you, true) else f.you:Hide() end
  if useCur and curW > 0 then put(curW, f.cur, true) else f.cur:Hide() end
  -- the right end
  local xr = -E
  if dungeons then f.dungeons:ClearAllPoints(); f.dungeons:SetPoint("RIGHT", f, "RIGHT", xr, y); f.dungeons:Show(); xr = xr - dw - G else f.dungeons:Hide() end
  if wantLayers then f.layers:ClearAllPoints(); f.layers:SetPoint("RIGHT", f, "RIGHT", xr, y); f.layers:Show(); xr = xr - lw - G else f.layers:Hide() end
  if wantPlaces then f.places:ClearAllPoints(); f.places:SetPoint("RIGHT", f, "RIGHT", xr, y); f.places:Show(); xr = xr - pw - G else f.places:Hide() end
  if wantGo then f.go:ClearAllPoints(); f.go:SetPoint("RIGHT", f, "RIGHT", xr, y); f.go:Show() else f.go:Hide() end
  self.shown = { chip = useChip, you = useYou, cur = useCur, zone = zw > 0, width = barW, need = total }
end

-------------------------------------------------------------------------------
-- Layers menu
-------------------------------------------------------------------------------
-- The groups of the Layers menu (E-05): CONNECTIONS, INFO ICONS, then the layers of other parts of Panoply Suite. Each tick is one setting, the
-- same setting the Map page's gear shows (one setting, two doors, so they cannot disagree).
B.LAYERS = {
  { head = "CONNECTIONS", rows = {
    { "mapExits", "Zone exits" },
    { "mapBoats", "Boats" },
    { "mapZeppelins", "Zeppelins" },
    { "mapTram", "Trams" },
    { "mapPortals", "Portals" },
    { "mapFlight", "Flight points you know" },
    { "mapFlightUnseen", "Flights not seen yet" },
  } },
  { head = "INFO ICONS", rows = {
    { "mapEntrances", "Dungeon and raid entrances" },
    { "mapGraves", "Graveyards" },
  } },
}
-- The layers of other parts of Panoply Suite on the world map. The menu writes the same options their own
-- settings pages write (one switch for one thing), and shows only what is running.
B.OTHER_LAYERS = {
  { key = "trailWorldMap", label = "Route trail and card" },
  { key = "qpWorldMap", label = "Quest icons", module = "questpins" },
  { key = "gatherWorldMap", label = "Gathering spots", module = "gathering" },
}
function B:LayerRows()
  local rows = {}
  if M:Wants("icons") then
    for _, g in ipairs(self.LAYERS) do
      rows[#rows + 1] = { head = g.head }
      for _, l in ipairs(g.rows) do rows[#rows + 1] = { key = l[1], label = l[2] } end
    end
  end
  local other = {}
  for _, l in ipairs(self.OTHER_LAYERS) do
    local on = not l.module or Panoply.Modules:IsOn(l.module)
    if on then
      other[#other + 1] = { key = l.key, label = l.label }
      -- 0.8.4: under "Gathering spots", one tick for each kind (herbs, ore veins, fishing pools, treasure chests)
      if l.key == "gatherWorldMap" then for _, r in ipairs(self:GatherRows()) do other[#other + 1] = r end end
    end
  end
  other[#other + 1] = { key = "mapSpots", label = "Saved spots" }      -- Nov 2026: the player's own saved spots (Spots.lua)
  other[#other + 1] = { key = "mapFavWM", label = "Map favorites" }    -- 0.9.5 phase 4G: the player's map favorites (Favorites.lua)
  if M:Wants("follow") then other[#other + 1] = { key = "mapFollow", label = "Follow my zone" } end
  if #other > 0 then
    rows[#rows + 1] = { head = "OTHER LAYERS" }
    for _, r in ipairs(other) do rows[#rows + 1] = r end
  end
  return rows
end

-- The kinds of gathering spot as ticks of the Layers menu: the same switches as the Map page's "Gathering spots" (Panoply.db.gatherShow, written
-- through Gathering:SetShown), so herbs, ore veins, fishing pools and treasure chests can be filtered without leaving the map.
function B:GatherRows()
  local G = Panoply.Gathering
  local rows = {}
  if not (G and G.TYPES and G.SetShown) then return rows end
  self.gatherChecks = self.gatherChecks or {}
  for _, t in ipairs(G.TYPES) do
    local spec = self.gatherChecks[t]
    if not spec then
      spec = { get = function() return Panoply.db and Panoply.db.gatherShow and Panoply.db.gatherShow[t] and true or false end,
        set = function(v) G:SetShown(t, v) end }
      self.gatherChecks[t] = spec
    end
    rows[#rows + 1] = { key = "gatherShow:" .. t, label = G.LABEL[t] or t, check = spec, sub = true }
  end
  return rows
end

-- The Layers popup: ticks (the same options the settings pages write) and two buttons. Its width is
-- measured from its longest line, so nothing runs out of the panel.
function B:OpenLayers(owner)
  local f = self.layersMenu
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteMapLayers", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    Skin.Panel(f, 1, nil, "M")
    f.checks = {}
    f.reset = Skin.Button(f, "Reset map position and size", 200, 24, function() f:Hide() if M.Window then M.Window:Reset() end end,
      "Reset map position and size", "Puts the map window back where the game puts it and turns the dimmer off.")
    f.settings = Skin.Button(f, "Map settings", 120, 24, function()
      f:Hide()
      if Panoply.Menu and Panoply.Menu.OpenGear then Panoply.Menu:OpenGear("map") end
    end, "Map settings", "Open the Map page's settings.")
    f:Hide()
    Skin.Popups:Adopt(f)
    self.layersMenu = f
  end
  -- a second click on the button closes it (the press may already have: Popups:Reopening)
  if Skin.Popups:Reopening(f, owner) then return f end
  if f:IsShown() then f:Hide() return f end
  f.panoplyOwner = owner
  local pad, gap = 12, 6
  local rows = self:LayerRows()
  local y, wmax = pad, 0
  local want = {}
  f.heads = f.heads or {}
  local nh = 0
  -- 0.9.5 phase 4K: the menu opens upward from the bar at the bottom of the screen; when its rows run taller than the screen leaves room
  -- for (a 1024x668 screen, since the Map favorites row), the rest of the groups go into a second column, at a group's heading
  local room = math.floor((UIParent:GetHeight() or 768) - 60 - (2 * 24 + 2 * gap + pad))
  local colX, colW, maxY = pad, 0, pad
  local function rowH(r) return r.head and (14 + 7) or 24 end
  local function groupH(i)
    local h = rowH(rows[i])
    for j = i + 1, #rows do if rows[j].head then break end h = h + rowH(rows[j]) end
    return h
  end
  for i, r in ipairs(rows) do
    if r.head and y > pad and y + groupH(i) > room then
      -- a new column at this group
      colX = colX + colW + 2 * pad
      maxY = math.max(maxY, y)
      y, colW = pad, 0
    end
    if r.head then
      -- a small heading over a group of ticks (CONNECTIONS, INFO ICONS, OTHER LAYERS)
      nh = nh + 1
      local h = f.heads[nh]
      if not h then h = Skin.Label(f, 10, Skin.colors.gold) f.heads[nh] = h end
      h:SetText(r.head)
      local lift = (y > pad) and 4 or 0
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", colX, -(y + lift))
      if h.SetWordWrap then h:SetWordWrap(false) end
      h:SetWidth(math.ceil(Skin.TextWidth(h) * 1.04) + 3)
      h:Show()
      colW = math.max(colW, h:GetWidth())
      y = y + lift + Skin.TextHeight(h) + 3
    else
      want[r.key] = true
      local cb = f.checks[r.key]       -- one check per option: it reads and writes that option
      if not cb then
        cb = Skin.Check(f, r.label, r.check or r.key)
        f.checks[r.key] = cb
      end
      local ind = r.sub and 18 or 0       -- a kind of gathering spot sits under "Gathering spots"
      local w = ind + 18 + 9 + math.ceil(Skin.TextWidth(cb.label) * 1.04) + 3
      colW = math.max(colW, w)
      cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", f, "TOPLEFT", colX + ind, -y)
      cb:Refresh()
      cb:Show()
      y = y + 22 + 2
    end
  end
  for i = nh + 1, #f.heads do f.heads[i]:Hide() end
  for key, cb in pairs(f.checks) do if not want[key] then cb:Hide() end end
  y = math.max(maxY, y)
  wmax = colX - pad + colW
  y = y + gap
  local rw = Skin.FitButton(f.reset, 120, 300)
  local sw = Skin.FitButton(f.settings, 90, 300)
  wmax = math.max(wmax, rw, sw)
  f.reset:ClearAllPoints(); f.reset:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
  y = y + 24 + gap
  f.settings:ClearAllPoints(); f.settings:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
  y = y + 24 + pad
  f:SetSize(wmax + 2 * pad, y)
  f:ClearAllPoints()
  f:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 6)    -- the bar is at the bottom of the screen: open upward
  f:Show()
  return f
end

-------------------------------------------------------------------------------
-- Places menu: the same switches the Map page's Places section shows (one setting, two doors), grouped, in a scrolling list
-------------------------------------------------------------------------------
function B:PlaceRows()
  local rows = {}
  for _, g in ipairs(M.PLACE_GROUPS) do
    local head = { head = g.head }
    local n = 0
    for _, t in ipairs(M.PLACE_TYPES) do
      -- 0.9.5 phase 4K: a kind that means nothing here (Beasts to tame on a character that is not a Hunter, the Forever kinds on
      -- Classic Era) is left out, and a group with none left has no heading
      if t.group == g.id and M.KindOK(t) then
        if n == 0 then rows[#rows + 1] = head end
        n = n + 1
        rows[#rows + 1] = { key = t.key, label = t.label }
        if t.key == "placeTrainClass" then rows[#rows + 1] = { key = "placeClassAll", label = "Show all classes", sub = true } end
      end
    end
  end
  rows[#rows + 1] = { head = "DISPLAY" }
  rows[#rows + 1] = { key = "placeMinimap", label = "Places on the minimap" }
  return rows
end

B.PLACES_MAX_H = 520       -- the menu's tallest height; what does not fit scrolls

function B:OpenPlaces(owner)
  local f = self.placesMenu
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteMapPlaces", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    Skin.Panel(f, 1, nil, "M")
    f.area = Skin.ScrollArea(f)
    f.checks, f.heads = {}, {}
    f.settings = Skin.Button(f, "Map settings", 120, 24, function()
      f:Hide()
      if Panoply.Menu and Panoply.Menu.OpenGear then Panoply.Menu:OpenGear("map") end
    end, "Map settings", "Open the Map page's settings: the size, colour and opacity of the places are there.")
    -- 0.9.5 phase 4G (queue item 1): the player's own map favorites, listed in their window (Modules/Map/FavWindow.lua)
    f.favs = Skin.Button(f, "Favorites", 120, 24, function()
      f:Hide()
      if M.FavWindow then M.FavWindow:Open() end
    end, "Favorites", "Every map favorite you saved: this zone or all zones, by name or by distance. Click one to see it on the map or to go there.")
    f:Hide()
    Skin.Popups:Adopt(f)
    self.placesMenu = f
  end
  -- a second click on the button closes it (the press may already have: Popups:Reopening)
  if Skin.Popups:Reopening(f, owner) then return f end
  if f:IsShown() then f:Hide() return f end
  f.panoplyOwner = owner
  local pad, gap = 12, 6
  local content = f.area.content
  local y, wmax, nh = 0, 0, 0
  -- the Favorites entry heads the menu (the count of those this character shows)
  local FV = M.Favorites
  local favTop = 0
  if FV and M.FavWindow then
    local n = #FV:List({ shown = true })
    f.favs.label:SetText(("Favorites (%d)"):format(n))
    wmax = math.max(wmax, Skin.FitButton(f.favs, 90, 300))
    f.favs:ClearAllPoints(); f.favs:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
    f.favs:Show()
    favTop = 24 + gap
  else f.favs:Hide() end
  local want = {}
  for _, r in ipairs(self:PlaceRows()) do
    if r.head then
      nh = nh + 1
      local h = f.heads[nh]
      if not h then h = Skin.Label(content, 10, Skin.colors.gold) f.heads[nh] = h end
      h:SetText(r.head)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + (nh > 1 and 4 or 0)))
      if h.SetWordWrap then h:SetWordWrap(false) end
      h:SetWidth(math.ceil(Skin.TextWidth(h) * 1.04) + 3)
      h:Show()
      wmax = math.max(wmax, h:GetWidth())
      y = y + (nh > 1 and 4 or 0) + Skin.TextHeight(h) + 3
    else
      want[r.key] = true
      local cb = f.checks[r.key]
      if not cb then cb = Skin.Check(content, r.label, r.key) f.checks[r.key] = cb end
      local ind = r.sub and 18 or 0
      wmax = math.max(wmax, ind + 18 + 9 + math.ceil(Skin.TextWidth(cb.label) * 1.04) + 3)
      cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", content, "TOPLEFT", ind, -y)
      cb:Refresh()
      cb:Show()
      y = y + 22 + 2
    end
  end
  for i = nh + 1, #f.heads do f.heads[i]:Hide() end
  for key, cb in pairs(f.checks) do if not want[key] then cb:Hide() end end
  local contentH = y
  local sw = Skin.FitButton(f.settings, 90, 300)
  wmax = math.max(wmax, sw)
  local sh = (_G.UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  if not sh or sh <= 0 then sh = 768 end
  local below = gap + 24 + pad                       -- the button under the list and the bottom margin
  local tall = math.max(180, math.min(self.PLACES_MAX_H, sh - 150))
  local viewH = math.min(contentH, tall - pad - below - favTop)
  local scrolls = contentH > viewH + 0.5
  local areaW = wmax + (scrolls and 12 or 0)
  f.area:ClearAllPoints(); f.area:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(pad + favTop))
  f.area:SetSize(areaW, viewH)
  f.area:SetContentHeight(contentH)
  content:SetWidth(f.area:ContentWidth(contentH))
  f.settings:ClearAllPoints(); f.settings:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(pad + favTop + viewH + gap))
  f:SetSize(areaW + 2 * pad, pad + favTop + viewH + below)
  f:ClearAllPoints()
  f:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 6)    -- the bar is at the bottom of the screen: open upward
  f:Show()
  return f
end

-------------------------------------------------------------------------------
-- Zone jump menu: continent tabs and a grid of zone buttons
-------------------------------------------------------------------------------
B.JUMP_COLS, B.JUMP_BTN_W, B.JUMP_BTN_H = 3, 160, 24

function B:CreateJump()
  if self.jump then return self.jump end
  local f = CreateFrame("Frame", "PanoplySuiteMapJump", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true)
  Skin.Panel(f, 1, nil, "M")
  f:Hide()
  f.tabs, f.btns = {}, {}
  for i, c in ipairs(self.CONTINENTS) do
    local t = Skin.Tab(f, c[2], 120, function() B:SelectContinent(c[1]) end, c[2])
    f.tabs[i] = t
  end
  Skin.Popups:Adopt(f)
  self.jump = f
  return f
end

function B:SelectContinent(cont)
  local f = self:CreateJump()
  self.jumpCont = cont
  local pad, gap = 12, 6
  local x = pad
  for i, c in ipairs(self.CONTINENTS) do
    local t = f.tabs[i]
    t:SetActive(c[1] == cont)
    local w = math.max(70, t:NeedWidth())
    t:SetWidth(w)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -pad)
    t:Show()
    x = x + w + gap
  end
  local top = pad + 26 + SP.m
  local zones = {}
  if cont == 947 then
    for _, c in ipairs(self.CONTINENTS) do if c[1] ~= 947 then zones[#zones + 1] = { id = c[1], name = c[2] } end end
  else
    zones = M:ZonesOf(cont)
    table.insert(zones, 1, { id = cont, name = "All of " .. (C.MapName(cont) or "this continent") })
  end
  -- widest label decides the button width, capped
  local longest = 0
  for _, z in ipairs(zones) do longest = math.max(longest, self:Measure(z.name)) end
  local bw = math.min(220, math.max(110, longest + 2 * SP.m + 4))
  local cols = self.JUMP_COLS
  for i, z in ipairs(zones) do
    local b = f.btns[i]
    if not b then
      b = Skin.Button(f, "", bw, self.JUMP_BTN_H, function(btn) B:Jump(btn.zoneID) end)
      f.btns[i] = b
    end
    b.zoneID = z.id
    b.label:SetText(z.name)
    b:SetSize(bw, self.JUMP_BTN_H)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", pad + col * (bw + gap), -(top + row * (self.JUMP_BTN_H + gap)))
    b:SetSelected(C.WorldMapID() == z.id)
    b:Show()
  end
  for i = #zones + 1, #f.btns do f.btns[i]:Hide() end
  local rows = math.ceil(#zones / cols)
  local w = math.max(x - gap + pad, pad * 2 + math.min(cols, #zones) * bw + (math.min(cols, #zones) - 1) * gap)
  f:SetSize(w, top + rows * (self.JUMP_BTN_H + gap) - gap + pad)
  return f
end

function B:ToggleJump()
  local f = self:CreateJump()
  local owner = self.frame and self.frame.zone
  -- a second click on the zone button closes it (the press may already have: Popups:Reopening)
  if Skin.Popups:Reopening(f, owner) then return end
  if f:IsShown() then f:Hide() return end
  f.panoplyOwner = owner
  local cont = M:ContinentOf(C.WorldMapID()) or 947
  self:SelectContinent(cont)
  f:ClearAllPoints()
  if owner then f:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 6) else f:SetPoint("CENTER", UIParent, "CENTER") end
  f:Show()
end

function B:Jump(map)
  local wm = C.WorldMap()
  if self.jump then self.jump:Hide() end
  if not (wm and wm.SetMapID and map) then return false end
  if C.InCombat() then return false end
  wm:SetMapID(map)
  return true
end
