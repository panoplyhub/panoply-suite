-- The Map page of the one Panoply Suite window. 0.9.5 phase 4K, from docs/specs/page-redesigns-05b-guide-map-current.md section 1 (it
-- wins over spec 05 section 5): the page shows and controls what the map already does; nothing here is a second copy of a setting.
--
--   Go to (full width, every band)   the same search as the map toolbar's Go to (Navigate.lua N:Search); a result is gone to (N:Go: the
--                                    trip is planned and the arrow points there). Under it the chips Home, Favourites (this
--                                    character's Go to favourites), Recents.
--   What the map shows (left)        Places: one row a kind (icon, name, how many in this zone, On/Off, + for its look); Info and
--                                    connections; Display (fog, route trail with its line legend, toolbar, places on the minimap, and
--                                    the layers of other parts: quest icons, gathering spots, saved spots, map favorites); Rares.
--   Where you're going (right)       Trip (the Go to stops in order, the legs to the first), Waypoints (dropped pins NOT on the trip,
--                                    by where they came from), Saved spots, Dungeons.
-- our terms (05b 1.2), each defined in its section's ?: a Saved spot is a place you keep, a Waypoint a temporary target for the arrow,
-- a Trip an ordered set of stops the router plans and talks you through. One list, two views (2026-11-14): Trip and Waypoints are
-- the one waypoint list (Modules/Waypoints), split by each waypoint's group (W.Group). Saved spots (PanoplySuiteSpotsDB), the Go to
-- favourites (Panoply.cdb.placesFav) and the map favorites (PanoplySuiteFavoritesDB) keep their own stores and are labelled apart.
-- Every switch on this page writes the setting the map toolbar's Places and Layers menus write (Panoply:SetOption on the same key).
-- Nothing here moves, targets or casts: the arrow points and the player walks.
local ADDON, Panoply = ...
local C, Skin, Kit = Panoply.Compat, Panoply.Skin, Panoply.Kit
local M, Menu = Panoply.Map, Panoply.Menu
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local MP = { query = "", open = {} }
M.Page = MP

MP.ROW_H, MP.WROW_H = 26, 36
MP.MAX_RESULTS, MP.MAX_CHIPS, MP.MAX_RARES = 6, 6, 8

MP.WORDS = {
  searchPH = "A town, a trainer, a dungeon, an NPC...",
  addPH = "/way 45.2 61.8 or zone x y",
  goTo = "Search every town, zone, dungeon, NPC, flight master, quest, monster, item, boss and node, in plain words (\"paladin trainer goldshire\"). Pick one: the trip is planned and the arrow points there.",
  favTip = "Go to favourites: places you starred in Go to, kept for this character. Starred saved spots are under Saved spots; your map favorites have their own window.",
  shows = "What Panoply Suite draws on the world map and the minimap. The map toolbar's Places and Layers menus switch the same things.",
  places = "Trainers, services, vendors, stations and the places other pages know, on the zone maps and the minimap. The number is how many are in the zone you are in.",
  looks = "Size, opacity and colour are the same for every kind of place.",
  info = "Entrances, graveyards and how the zones join.",
  display = "How the map looks, and the layers of other parts of Panoply Suite.",
  toolbar = "The strip along the bottom of the world map: zone menu, coordinates, Go to, Places, Layers and Dungeons",
  rares = "Rare creatures of the zone you are in, and when you last saw each one.",
  going = "Your trip, your waypoints and your saved spots.",
  trip = "Trip: an ordered set of stops the router plans and talks you through. Stops come from Go to, or from \"Add to trip\" on a waypoint.",
  way = "Waypoint: a temporary target for the arrow. Type one in the box, Ctrl-right-click the world map, or use a Map button on another page. They are grouped by where they came from.",
  spots = "Saved spot: a place you keep (named, starred, account-wide). Shift-right-click the world map to save one there.",
  dungeons = "Every dungeon and raid: facts, floor plan and numbered bosses.",
  noTrip = "No trip. Pick a place in Go to.",
  noWay = "No waypoints.",
  noSpots = "No saved spots.",
  wayOff = "Waypoints are off.",
  mapOff = "The map tools are off: nothing below is drawn until they are on.",
}
-- the kinds of the Info and connections section, and the Display rows (keys the toolbar's Layers menu and the gear also write)
MP.INFO = { { "mapEntrances", "Dungeon and raid entrances" }, { "mapGraves", "Graveyards" }, { "mapExits", "Zone exits" },
  { "mapBoats", "Boats" }, { "mapZeppelins", "Zeppelins" }, { "mapTram", "Trams" }, { "mapPortals", "Portals" },
  { "mapFlight", "Flight points you know" }, { "mapFlightUnseen", "Flight points not seen yet" } }
MP.DISPLAY = {
  { "mapFog", "Mark unexplored areas" },
  { "trailWorldMap", "Route trail on the world map", legend = true },
  { "trailMinimap", "Route trail on the minimap" },
  { "mapBar", "Map toolbar", help = "toolbar" },
  { "placeMinimap", "Places on the minimap" },
  { "qpWorldMap", "Quest icons", module = "questpins" },
  { "gatherWorldMap", "Gathering spots", module = "gathering" },
  { "mapSpots", "Saved spots" },
  { "mapFavWM", "Map favorites (your own places, with a type and a note)", favs = true },
}
MP.LEGEND_WORD = { ants = "dots", solid = "line", dash = "dashes", dashdot = "dash and dot", rail = "rails" }

local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function db() return Panoply.db or {} end
local function W() return Panoply.Waypoints end
local function distance(map, x, y)
  local pm, px, py = C.GetPlayerPos()
  local d = pm and Panoply.Nav and Panoply.Nav.Distance and Panoply.Nav.Distance(pm, px, py, map, x, y)
  return d and Panoply.StepText and Panoply.StepText.Distance(d) or nil
end
local function where(map, x, y) return ("%s %.1f, %.1f"):format(C.MapName(map) or ("Map " .. tostring(map)), (x or 0) * 100, (y or 0) * 100) end

-------------------------------------------------------------------------------
-- A canvas: pooled pieces on the page, all hidden at the start of each layout and taken again in drawing order
-------------------------------------------------------------------------------
local Canvas = {}
Canvas.__index = Canvas
local function canvas(frame) return setmetatable({ frame = frame, pools = {} }, Canvas) end
function Canvas:Begin() for _, pl in pairs(self.pools) do for i = 1, pl.n do pl[i]:Hide() end pl.n = 0 end end
function Canvas:Get(kind, make)
  local pl = self.pools[kind]
  if not pl then pl = { n = 0 } self.pools[kind] = pl end
  pl.n = pl.n + 1
  local o = pl[pl.n]
  if not o then o = make(self.frame) pl[pl.n] = o end
  if o.ClearAllPoints then o:ClearAllPoints() end
  o:Show()
  return o
end
-- words at (x, y) in w: one line cut short, or wrapped (opts.wrap); returns the height
function Canvas:Text(x, y, w, size, color, words, opts)
  opts = opts or {}
  local kind = (opts.name and "N" or "I") .. size
  local fs = self:Get(kind, function(f)
    local s = opts.name and Skin.Name(f, size, Kit.Color("text.primary")) or Skin.Ink(f, size, Kit.Color("text.muted"))
    if s.SetJustifyH then s:SetJustifyH("LEFT") end
    return s
  end)
  setColor(fs, type(color) == "table" and color or Kit.Color(color or "text.muted"))
  fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  w = max(10, w)
  fs:SetWidth(w)
  if opts.wrap then
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    fs:SetText(words or "")
  else
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    Skin.Ellipsize(fs, words or "", w)
  end
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  if opts.fit then fs:SetWidth(min(w, ceil(TW(fs)) + 2)) end
  return h, fs
end
function Canvas:Label(x, y, w, words)
  local fs = self:Get("L", function(f) local s = Skin.Label(f, 10, Kit.Color("text.muted")) if s.SetWordWrap then s:SetWordWrap(false) end return s end)
  fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  fs:SetWidth(max(10, w))
  Skin.Ellipsize(fs, words or "", max(10, w))
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  return h
end
function Canvas:Tex(x, y, w, h)
  local t = self:Get("T", function(f) return f:CreateTexture(nil, "ARTWORK") end)
  t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  t:SetSize(w, h)
  t:SetAlpha(1)
  if t.SetTexCoord then t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 1) end
  return t
end
function Canvas:Head(x, y, w, title, help)
  local h = self:Get("SH", function(f) local s = Kit.SectionHeader(f, { size = 15 }) return s end)
  h:SetTitle(title)
  h:SetHelp(help)
  return h:Layout(x, -y, w)
end
function Canvas:Button(x, y, label, onClick, tip, body, minW, maxW, hh)
  local b = self:Get("B" .. (hh or 22), function(f)
    local bb = Skin.Button(f, "", 80, hh or 22, function(self, btn) if self.panoplyOnClick then self.panoplyOnClick(self, btn) end end)
    bb.panoplyGapOK = true
    return bb
  end)
  b.label:SetText(label or "")
  local w = Skin.FitButton(b, minW or 50, maxW or 260)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  b.panoplyOnClick, b.tip, b.tipBody = onClick, tip or label, body
  b:SetEnabledLook(true)
  return b, b:GetWidth() or w
end
-- the width a button with these words takes (drawn once off-page, then given back to the pool)
function Canvas:ButtonWidth(label, minW, maxW, hh)
  local b = self:Get("B" .. (hh or 22), function(f)
    local bb = Skin.Button(f, "", 80, hh or 22, function(self, btn) if self.panoplyOnClick then self.panoplyOnClick(self, btn) end end)
    bb.panoplyGapOK = true
    return bb
  end)
  b.label:SetText(label or "")
  local w = Skin.FitButton(b, minW or 50, maxW or 260)
  b:Hide()
  local pl = self.pools["B" .. (hh or 22)]
  pl.n = pl.n - 1
  return b:GetWidth() or w
end
function Canvas:Icon(x, y, glyph, size, onClick, tip, body)
  local b = self:Get("IB" .. glyph .. size, function(f)
    local bb = Skin.IconButton(f, glyph, size, function(self) if self.panoplyOnClick then self.panoplyOnClick(self) end end, tip, body)
    bb.panoplyGapOK = true
    if glyph == "Settings" then bb.panoplyKitIcon = "icon.ui.more" end
    return bb
  end)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  b.panoplyOnClick, b.tip, b.tipBody = onClick, tip, body
  return b
end
function Canvas:More(x, y, items, tip)
  return self:Icon(x, y, "Settings", 20, function(self) Skin.Menu(self, items(), { width = 210 }) end, "More", tip)
end
function Canvas:Switch(x, y, on, onClick, tip, body, word)
  local s = self:Get("SW", function(f)
    local ss = Skin.Switch(f, function(self) if self.panoplyToggle then self.panoplyToggle(self) end end, "Switch")
    ss.panoplyGapOK = true
    return ss
  end)
  s:SetState(on, word)
  s:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  s.panoplyToggle, s.tip, s.tipBody = onClick, tip, body
  return s, s:NeedWidth()
end
function Canvas:SwitchWidth(on, word)
  local s, w = self:Switch(-2000, 0, on, nil, nil, nil, word)
  s:Hide()
  self.pools.SW.n = self.pools.SW.n - 1
  return w
end
function Canvas:Help(x, y, title, body)
  local b = self:Get("HP", function(f) local hh = Kit.HelpIcon(f, title, body, 16) hh.panoplyGapOK = true return hh end)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  b.tip, b.tipBody = title, body
  return b
end
-- a sub-section title with its ? at the right (the words stop before it); returns the height
function Canvas:Sub(x, y, w, title, help, rightW)
  rightW = rightW or 0
  local h = self:Text(x, y, w - 22 - rightW, 13, "text.primary", title, { name = true })
  if help then self:Help(x + w - 16 - rightW, y + max(0, floor((h - 16) / 2)), title, help) end
  return max(h, 18)
end
local function hotSpot(f)
  local b = CreateFrame("Button", nil, f)
  b.panoplyGapOK, b.panoplyLayoutSkip = true, true
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetAllPoints(b)
  Skin.Solid(b.hl, Kit.Color("surface.2"), 1)
  b.hl:Hide()
  b:SetScript("OnEnter", function(self)
    self.hl:Show()
    local GT = _G.GameTooltip
    if GT and self.tip then
      GT:SetOwner(self, "ANCHOR_RIGHT")
      GT:SetText(self.tip, 0.95, 0.84, 0.55, 1, true)
      if self.tipBody then GT:AddLine(self.tipBody, 0.9, 0.9, 0.88, true) end
      GT:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self, btn) if self.panoplyOnClick then self.panoplyOnClick(self, btn) end end)
  return b
end
function Canvas:Hot(x, y, w, h, onClick, tip, body)
  local b = self:Get("hot", hotSpot)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
  b:SetSize(max(1, w), max(1, h))
  b.panoplyOnClick, b.tip, b.tipBody = onClick, tip, body
  b.hl:Hide()
  return b
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
local function redraw() if Menu.frame and Menu.frame:IsShown() and Menu.current == "map" then Menu:RefreshCurrent() end end
MP.Redraw = redraw
local function toggle(key) return function() Panoply:SetOption(key, not db()[key]) redraw() end end

-- is a section or group open? (remembered for the page; d = the default for this band)
function MP:IsOpen(id, d) return Kit.GetOpen("map", id, d) end
function MP:Toggle(id, d) Kit.SetOpen("map", id, not self:IsOpen(id, d)) redraw() end

-- a layer's own page settings, as one Back / Forward step (spec 05 section 6)
MP.OWNER_SECTION = { misc = "deaths" }
function MP:OpenOwner(owner)
  local page = owner == "misc" and (Panoply.Misc and Panoply.Misc.PAGE or "misc") or owner
  Menu:OpenGear(page, MP.OWNER_SECTION[owner])
end

function MP:Search(text)
  local N = M.Navigate
  if not (N and N.Search) then return {} end
  local ok, list = pcall(N.Search, N, text, MP.MAX_RESULTS)
  return ok and type(list) == "table" and list or {}
end
function MP:Go(d)
  local N = M.Navigate
  if N and N.Go and N:Go(d, "trip") then redraw() return true end
  return false
end
function MP:AddFromBox(text)
  local Wy = W()
  if not (Wy and Wy.active) then return false end
  text = tostring(text or ""):gsub("^%s*/[%a]*way%s*", "")
  local wp, why = Wy:AddText(text, false, "mine")
  self.addMsg = not wp and why or nil
  if wp and self.page and self.page.addBox then self.page.addBox:SetText("") if self.page.addBox.placeholder then self.page.addBox.placeholder:Show() end end
  redraw()
  return wp
end

-- Import / Export (the Waypoints list's ⋯): the copy window, and a small window with a box for the lines
function MP:Export()
  local Wy = W()
  if not (Wy and Panoply.ReportCopy) then return false end
  Panoply.ReportCopy:Open(Wy:ExportLines(), { title = "Export waypoints", subtitle = "Select, copy, paste",
    intro = "Every waypoint as a /way line. Paste them into Import on another character or computer." })
  return true
end
function MP:CreateImport()
  if self.importWin then return self.importWin end
  local f = Skin.Window("PanoplySuiteWayImport", 440, 220, "Import waypoints", "/way lines", nil, "TurnIn")   -- 4J: its own header icon
  self.importWin = f
  f.intro = Skin.Text(f, 12)
  f.intro:SetText("Paste /way lines, one after another (zone, X, Y and a note). They are added to Mine.")
  f.box = Skin.Input(f, 380, 24, "/way Westfall 45.2 61.8 Sentinel Hill")
  if f.box.icon then f.box.icon:Hide() end
  if f.box.SetTextInsets then f.box:SetTextInsets(6, 6, 0, 0) end
  if f.box.placeholder then f.box.placeholder:ClearAllPoints() f.box.placeholder:SetPoint("LEFT", f.box, "LEFT", 6, 0) end
  f.box:SetScript("OnTextChanged", function(b) if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end end)
  f.box:SetScript("OnEnterPressed", function() MP:DoImport() end)
  f.msg = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.go = Skin.Button(f, "Import", 90, 26, function() MP:DoImport() end, "Import", "Adds the waypoints in the box.")
  f.close = Skin.Button(f, "Close", 80, 26, function() f:Hide() end, "Close", "Closes this window.")
  return f
end
function MP:LayoutImport()
  local f = self.importWin
  local pad = 16
  local inner = (f:GetWidth() or 440) - 2 * pad
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  f.intro:ClearAllPoints(); f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); f.intro:SetWidth(inner)
  y = y + TH(f.intro, inner) + SP.m
  f.box:ClearAllPoints(); f.box:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); f.box:SetWidth(inner)
  y = y + 24 + SP.m
  if self.importMsg then
    f.msg:SetText(self.importMsg)
    f.msg:ClearAllPoints(); f.msg:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); f.msg:SetWidth(inner)
    y = y + TH(f.msg, inner) + SP.s
    f.msg:Show()
  else f.msg:Hide() end
  local bh = Skin.FlowButtons(f, { f.go, f.close }, pad, -y, inner, SP.s, 70)
  f:SetHeight(y + max(bh, 26) + pad)
end
function MP:OpenImport()
  local f = self:CreateImport()
  self.importMsg = nil
  f.box:SetText("")
  if f.box.placeholder then f.box.placeholder:Show() end
  f:Show()
  self:LayoutImport()
  return f
end
function MP:DoImport()
  local f, Wy = self.importWin, W()
  if not (f and Wy) then return 0 end
  local added, bad = Wy:Import(f.box:GetText() or "", "mine")
  local parts = { ("Added %d waypoint%s."):format(added, added == 1 and "" or "s") }
  if bad > 0 then parts[#parts + 1] = ("%d line%s could not be read."):format(bad, bad == 1 and "" or "s") end
  self.importMsg = table.concat(parts, " ")
  if added > 0 then f.box:SetText("") end
  self:LayoutImport()
  redraw()
  return added, bad
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
Menu:RegisterTab("Map", function(p)
  MP.page = p
  p.cv = canvas(p)
  p.search = Skin.Input(p, 300, 26, MP.WORDS.searchPH)
  p.search.panoplyGapOK = true
  p.search:SetScript("OnTextChanged", function(b)
    local t = b:GetText() or ""
    if b.placeholder then if t == "" then b.placeholder:Show() else b.placeholder:Hide() end end
    if t ~= MP.query then MP.query = t redraw() end
  end)
  p.search:SetScript("OnEnterPressed", function(b)
    b:ClearFocus()
    local first = MP:Search(b:GetText() or "")[1]
    if first then MP:Go(first) end
  end)
  p.search:SetScript("OnEscapePressed", function(b) if (b:GetText() or "") ~= "" then b:SetText("") end b:ClearFocus() end)
  p.addBox = Skin.Input(p, 240, 24, MP.WORDS.addPH)
  p.addBox.panoplyGapOK = true
  if p.addBox.icon then p.addBox.icon:Hide() end
  if p.addBox.SetTextInsets then p.addBox:SetTextInsets(6, 6, 0, 0) end
  if p.addBox.placeholder then p.addBox.placeholder:ClearAllPoints() p.addBox.placeholder:SetPoint("LEFT", p.addBox, "LEFT", 6, 0) end
  p.addBox:SetScript("OnTextChanged", function(b) if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end end)
  p.addBox:SetScript("OnEnterPressed", function(b) b:ClearFocus() MP:AddFromBox(b:GetText() or "") end)
  p.addBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  -- the waypoint list's pop-out (the waypoint window keeps working)
  local pb = CreateFrame("Button", nil, p)
  pb:SetSize(20, 20)
  pb.panoplyKit, pb.panoplyGapOK = "IconButton", true
  pb.icon = pb:CreateTexture(nil, "ARTWORK"); pb.icon:SetAllPoints(pb)
  pb.panoplyIconHow = Kit.Icon(pb.icon, "icon.ui.popout", { size = 20 })
  Skin.Tooltip(pb, "Pop out", "The waypoint list in a window of its own.")
  pb:SetScript("OnEnter", function(f) if f.panoplyShowTip then f.panoplyShowTip() end end)
  pb:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  pb:SetScript("OnClick", function() local Wy = W() if Wy and Wy.active then Wy:Toggle() end end)
  p.popout = pb
  if Panoply.Trip and Panoply.Trip.LineWidget then p.tripLine = Panoply.Trip.LineWidget(p, { size = 14, font = 11 }) end
  function p:Layout() return MP:Draw(self) end
end, function(p) end, { scroll = true })

function MP:Draw(p)
  local cv = p.cv
  cv:Begin()
  local Wd = p.width or 600
  local band = Kit.Band(Wd)
  self.band = band
  local y = self:DrawGoTo(p, 2, 0, Wd - 4)
  y = y + SP.l
  if band == "wide" then
    local gap = SP.l
    local lw = floor((Wd - 4 - gap) * 0.4)
    local rw = Wd - 4 - gap - lw
    local yl = self:DrawShows(p, 2, y, lw)
    local yr = self:DrawGoing(p, 2 + lw + gap, y, rw)
    return max(yl, yr) + SP.m
  end
  y = self:DrawShows(p, 2, y, Wd - 4)
  y = self:DrawGoing(p, 2, y + SP.l, Wd - 4)
  return y + SP.m
end

-- Go to: the search box, its results, and the chips Home, Favourites, Recents
function MP:DrawGoTo(p, x, y, w)
  local cv = p.cv
  y = y + cv:Head(x, y, w, "Go to", self.WORDS.goTo) + SP.s
  p.search:ClearAllPoints(); p.search:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y); p.search:SetWidth(w); p.search:Show()
  if (p.search:GetText() or "") ~= self.query then p.search:SetText(self.query) end
  y = y + 26 + SP.s
  local q = self.query:gsub("^%s+", ""):gsub("%s+$", "")
  if q ~= "" then
    local list = self:Search(q)
    if #list == 0 then
      y = y + cv:Text(x, y, w, 12, "text.muted", ("Nothing matches \"%s\"."):format(q)) + SP.s
    end
    for _, d in ipairs(list) do
      local bw = 22
      local dist = d.map and distance(d.map, d.x, d.y)
      local h1 = cv:Text(x + 4, y + 3, w - bw - 12, 12, "text.primary", d.name or "?", { name = true })
      local h2 = cv:Text(x + 4, y + 3 + h1, w - bw - 12, 11, "text.muted", (d.sub or "") .. (dist and ((d.sub and d.sub ~= "" and " · " or "") .. dist) or ""))
      local rh = max(MP.WROW_H, h1 + h2 + 6)
      cv:Hot(x, y, w - bw - 8, rh, function() MP:Go(d) end, "Go there", "Plans the trip and points the arrow.")
      cv:Icon(x + w - bw, y + floor((rh - 20) / 2), "+", 20, function() local N = M.Navigate if N and N:AddStop(d, "trip") then redraw() end end,
        "Add as a stop", "Adds it at the end of your trip.")
      y = y + rh + 2
    end
    y = y + SP.s
  end
  local N = M.Navigate
  if not N then return y end
  local rows = {}
  local home = N.Home and N:Home()
  rows[#rows + 1] = { "HOME", home and { home } or {}, "Right-click a place in Go to and choose Set as Home; until then it is your hearthstone's inn." }
  local favs = {}
  for _, f in ipairs(N:Favs()) do if not f.spot and #favs < MP.MAX_CHIPS then favs[#favs + 1] = f end end
  rows[#rows + 1] = { "FAVOURITES", favs, self.WORDS.favTip }
  local rec = {}
  for _, r in ipairs(N:Recents()) do if not r.spot and #rec < MP.MAX_CHIPS then rec[#rec + 1] = r end end
  rows[#rows + 1] = { "RECENTS", rec, "The places you went to last." }
  for _, r in ipairs(rows) do
    local lh = cv:Label(x, y + 4, 110, r[1])
    cv:Help(x + 112, y + 2, r[1]:sub(1, 1) .. r[1]:sub(2):lower(), r[3])
    local cx, cy, rowH, rowLine = x + 136, y, 22, 22
    if #r[2] == 0 then
      cv:Text(cx, y + 4, w - (cx - x), 11, "text.muted", r[1] == "HOME" and "Not set" or "None yet")
    end
    for _, d in ipairs(r[2]) do
      local bw = cv:ButtonWidth(d.name or "?", 40, 200)
      bw = min(bw, w - 136)
      if cx + bw > x + w and cx > x + 136 then cx = x + 136 cy = cy + rowLine + SP.xs end
      local bb = cv:Button(cx, cy, d.name or "?", function() MP:Go(d) end, d.name, (d.sub and (d.sub .. ". ") or "") .. "Go there.", 40, min(200, w - 136))
      local bh = ceil(bb:GetHeight() or 22)
      rowLine = max(rowLine, bh)
      rowH = max(rowH, cy - y + bh)
      cx = cx + bw + SP.s
    end
    y = y + max(rowH, lh + 8) + SP.xs
  end
  return y
end

-- one On/Off row: label (and an icon), the switch at the right; returns the height
function MP:SwitchRow(cv, x, y, w, label, on, onClick, tip, iconPath, extra)
  local sww = cv:SwitchWidth(on)
  local right = sww + (extra or 0)
  local tx = x
  if iconPath then
    local t = cv:Tex(x, y + 5, 16, 16)
    t:SetTexture(iconPath)
    tx = x + 22
  end
  local h = cv:Text(tx, y + 6, w - (tx - x) - right - SP.s, 12, "text.primary", label, { name = true })
  cv:Switch(x + w - sww, y + 1, on, onClick, label, tip)
  return max(MP.ROW_H, h + 10)
end

-- Left: what the map shows
function MP:DrawShows(p, x, y, w)
  local cv = p.cv
  local d = db()
  y = y + cv:Head(x, y, w, "What the map shows", self.WORDS.shows) + SP.s
  if not (Panoply.Modules and Panoply.Modules:IsOn("map")) then
    y = y + cv:Text(x, y, w, 12, "state.warn", self.WORDS.mapOff, { wrap = true }) + SP.xs
    if Panoply.Modules and Panoply.Modules.byKey.map then
      cv:Button(x, y, "Turn the map tools on", function() Panoply.Modules:Set("map", true) redraw() end, "Map tools", "Switches the Map module on.")
      y = y + 22 + SP.s
    end
  end
  -- Places
  local zone = C.GetPlayerPos()
  y = y + cv:Sub(x, y, w, "Places", self.WORDS.places) + SP.xs
  local Pl = M.Places
  for _, g in ipairs(M.PLACE_GROUPS) do
    local kinds = {}
    for _, t in ipairs(M.PLACE_TYPES) do if t.group == g.id and M.KindOK(t) then kinds[#kinds + 1] = t end end
    if #kinds > 0 then
      y = y + cv:Label(x, y + 2, w, g.head) + SP.xs + 2
      for _, t in ipairs(kinds) do y = self:DrawKind(cv, x, y, w, t, zone, Pl) end
    end
  end
  y = y + SP.s
  -- Info and connections
  y = y + cv:Sub(x, y, w, "Info and connections", self.WORDS.info) + SP.xs
  for _, r in ipairs(self.INFO) do
    y = y + self:SwitchRow(cv, x, y, w, r[2], d[r[1]] and true or false, toggle(r[1]), nil)
  end
  y = y + SP.s
  -- Display
  y = y + cv:Sub(x, y, w, "Display", self.WORDS.display) + SP.xs
  for _, r in ipairs(self.DISPLAY) do
    if not r.module or (Panoply.Modules and Panoply.Modules.byKey[r.module]) then
      local extra = r.help and 22 or 0
      local rh = self:SwitchRow(cv, x, y, w, r[2], d[r[1]] and true or false, toggle(r[1]), nil, nil, extra)
      if r.help then
        local sww = cv:SwitchWidth(d[r[1]] and true or false)
        cv:Help(x + w - sww - 20, y + 5, r[2], self.WORDS[r.help])
      end
      y = y + rh
      if r.legend then
        local Tr = Panoply.Trail
        local parts = {}
        for _, k in ipairs({ "walk", "fly", "ship", "zeppelin", "tram" }) do
          local s = Tr and Tr.STYLE and Tr.STYLE[k]
          if s then parts[#parts + 1] = ("%s: %s"):format(s.label:sub(1, 1):upper() .. s.label:sub(2), self.LEGEND_WORD[s.draw] or s.draw) end
        end
        if #parts > 0 then y = y + cv:Text(x + 12, y, w - 12, 11, "text.muted", table.concat(parts, " · "), { wrap = true }) + SP.xs end
      end
      if r.favs and M.FavWindow then
        cv:Button(x + 12, y, "Open Map favorites", function() M.FavWindow:Open() end, "Map favorites",
          "Your own places with a type, a note and an icon, for every character: this zone or all, by name or distance.")
        y = y + 22 + SP.s
      end
    end
  end
  y = y + SP.s
  -- Rares
  y = self:DrawRares(cv, x, y, w, zone)
  return y
end

-- one kind of place: icon, name, count here, (trainers: my class / all), On/Off, + for its look, (a fed kind: its page's settings)
function MP:DrawKind(cv, x, y, w, t, zone, Pl)
  local d = db()
  local on = d[t.key] and true or false
  local sww = cv:SwitchWidth(on)
  local right = sww + 24
  local ownerW = t.owner and 24 or 0
  local classW = 0
  if t.key == "placeTrainClass" then classW = cv:ButtonWidth(d.placeClassAll and "All classes" or "My class", 40, 120) + SP.s end
  local t0 = cv:Tex(x, y + 5, 16, 16)
  t0:SetTexture(Pl and Pl.IconPath and Pl.IconPath(t.key) or nil)
  local n = Pl and Pl.ZoneCount and Pl:ZoneCount(t.key, zone) or 0
  local nameW = w - 22 - right - ownerW - classW - SP.s
  local countText = zone and (n .. " here") or ""
  local cw = countText ~= "" and 60 or 0
  local h = cv:Text(x + 22, y + 6, nameW - cw, 12, "text.primary", t.label, { name = true })
  if countText ~= "" then cv:Text(x + 22 + nameW - cw + 4, y + 7, cw - 4, 11, "text.muted", countText) end
  local rx = x + w - sww - 24
  if t.key == "placeTrainClass" then
    cv:Button(rx - classW - ownerW, y + 2, d.placeClassAll and "All classes" or "My class", toggle("placeClassAll"), "Trainers",
      "My class: only your own class's trainers. All classes: every class's.", 40, 120)
  end
  if t.owner then
    cv:Icon(rx - 24, y + 3, "Settings", 20, function() MP:OpenOwner(t.owner) end, t.label .. " settings",
      "Opens the settings of the page these places come from.")
  end
  cv:Switch(rx, y + 1, on, toggle(t.key), t.label, t.tip)
  local id = "kind:" .. t.key
  local open = self:IsOpen(id, false)
  cv:Icon(x + w - 20, y + 3, open and "-" or "+", 20, function() MP:Toggle(id, false) end, open and "Hide the look" or "Show the look",
    "Size, opacity and colour of the places on the world map and the minimap.")
  y = y + max(MP.ROW_H, h + 10)
  if open then
    local L = Panoply.Look
    local function pct(v) return floor((v or 1) * 100 + 0.5) .. "%" end
    local line = ("World map: size %s, opacity %s. Minimap: size %s, opacity %s. %s"):format(pct(L.Size("place", "wm")), pct(L.Alpha("place", "wm")),
      pct(L.Size("place", "mm")), pct(L.Alpha("place", "mm")), self.WORDS.looks)
    if t.key == "placeTradeCamp" and #(Pl:Dynamic("placeTradeCamp")) == 0 then line = line .. " No checked position of the trade camps is known yet, so none is drawn." end
    y = y + cv:Text(x + 22, y, w - 22, 11, "text.muted", line, { wrap = true }) + SP.xs
    cv:Button(x + 22, y, "Change the look", function() Menu:OpenGear("map", "look") end, "Change the look", "Opens Look of the map, at Places.")
    y = y + 22 + SP.s
  end
  return y
end

function MP:DrawRares(cv, x, y, w, zone)
  local R, Pl = M.Rares, M.Places
  if not (R and Pl and M.KindOK("placeRare")) then return y end
  y = y + cv:Sub(x, y, w, "Rares", self.WORDS.rares) + SP.xs
  local d = db()
  y = y + self:SwitchRow(cv, x, y, w, "Tell me when one is near", d.rareAlert and true or false, toggle("rareAlert"),
    "A short notice when the game shows you a rare creature. Nothing is targeted or searched for you.")
  local list = zone and R:ZoneList(zone) or {}
  if #list == 0 then
    return y + cv:Text(x, y, w, 11, "text.muted", zone and ("No rare creatures are known in " .. (C.MapName(zone) or "this zone") .. ".") or "Your zone is not known here.") + SP.s
  end
  local spot = {}
  for _, e in ipairs(Pl.Index().byMap[zone] or {}) do if e.type == "placeRare" and e.id and not spot[e.id] then spot[e.id] = e end end
  local now = (_G.time and time()) or 0
  for i, r in ipairs(list) do
    if i > MP.MAX_RARES then break end
    local e = spot[r.id]
    local seen = r.seen and r.seen.t and ("last seen " .. R.Ago(now - r.seen.t)) or "not seen yet"
    local h1 = cv:Text(x, y + 3, w - 28, 12, "text.primary", r.name, { name = true })
    local h2 = cv:Text(x, y + 3 + h1, w - 28, 11, "text.muted", (r.level and (r.level .. " · ") or "") .. seen)
    if e then cv:Icon(x + w - 20, y + 6, "Arrow", 20, function() M:PointAt(e.map, e.x, e.y, r.name, "mine") redraw() end, "Point the arrow", "Points the arrow where it can appear.") end
    y = y + max(MP.WROW_H, h1 + h2 + 6)
  end
  return y + SP.s
end

-- Right: where you're going
function MP:DrawGoing(p, x, y, w)
  local cv = p.cv
  self.goingY = y      -- where the section starts on the page (the previews and the tests scroll to it)
  y = y + cv:Head(x, y, w, "Where you're going", self.WORDS.going) + SP.s
  y = self:DrawTrip(p, x, y, w)
  y = self:DrawWaypoints(p, x, y + SP.s, w)
  y = self:DrawSpots(p, x, y + SP.s, w)
  y = self:DrawDungeons(p, x, y + SP.s, w)
  return y
end

-- a waypoint row: name, where and how far, then its buttons at the right
function MP:WayRow(cv, x, y, w, wp, buttons)
  local bx = x + w
  local placed = {}
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    local bw = b.label and cv:ButtonWidth(b.label, 40, 110, 20) or 20
    bx = bx - bw
    placed[i] = { b, bx }
    bx = bx - SP.xs
  end
  local tw = bx - x - SP.s
  local dist = distance(wp.m, wp.x, wp.y)
  local h1 = cv:Text(x, y + 3, tw, 12, "text.primary", wp.note or ("Waypoint " .. where(wp.m, wp.x, wp.y)), { name = true })
  local h2 = cv:Text(x, y + 3 + h1, tw, 11, "text.muted", where(wp.m, wp.x, wp.y) .. (dist and (" · " .. dist) or ""))
  local rh = max(MP.WROW_H, h1 + h2 + 6)
  for _, pb in ipairs(placed) do
    local b, at = pb[1], pb[2]
    if b.label then cv:Button(at, y + floor((rh - 20) / 2), b.label, b.fn, b.tip, b.body, 40, 110, 20)
    elseif b.more then cv:More(at, y + floor((rh - 20) / 2), b.more, b.tip)
    else cv:Icon(at, y + floor((rh - 20) / 2), b.glyph, 20, b.fn, b.tip, b.body) end
  end
  return rh
end

function MP:DrawTrip(p, x, y, w)
  local cv, Wy = p.cv, W()
  local stops = Wy and Wy:InGroup("trip") or {}
  local hy = y
  y = y + cv:Sub(x, y, w, "Trip", self.WORDS.trip, 26)
  cv:More(x + w - 20, hy, function()
    return { { text = "Clear trip", tip = "Takes every stop off the trip. Your other waypoints stay.", func = function() if Wy then Wy:ClearGroup("trip") redraw() end end } }
  end, "Clear trip")
  y = y + SP.xs
  if p.tripLine then p.tripLine:Hide() end
  if #stops == 0 then
    return y + cv:Text(x, y, w, 11, "text.muted", self.WORDS.noTrip) + SP.s
  end
  local first = Wy:List()[1]
  for i, wp in ipairs(stops) do
    local idx = Wy:IndexOf(wp)
    local rh = self:WayRow(cv, x, y, w, wp, {
      { glyph = "Arrow", fn = function() Wy:Point(wp) redraw() end, tip = "Point the arrow", body = "The arrow takes you to this stop first." },
      { more = function()
          return {
            { text = "Move up", func = function() local k = Wy:IndexOf(wp) local prev for j = k - 1, 1, -1 do if Wy.OnTrip(Wy:List()[j]) then prev = j break end end
              if prev then Wy:Move(k, prev) redraw() end end },
            { text = "Move down", func = function() local k = Wy:IndexOf(wp) local nxt local L = Wy:List() for j = k + 1, #L do if Wy.OnTrip(L[j]) then nxt = j break end end
              if nxt then Wy:Move(k, nxt) redraw() end end },
            { text = "Remove", func = function() local k = Wy:IndexOf(wp) if k then Wy:Remove(k) redraw() end end },
          }
        end, tip = "Move or remove this stop" } })
    -- the stop the arrow follows: its legs and the total, on one line
    if wp == first and idx == 1 and p.tripLine then
      p.tripLine:ClearAllPoints(); p.tripLine:SetPoint("TOPLEFT", p, "TOPLEFT", x + 12, -(y + rh))
      local lh = p.tripLine:Fill(w - 12)
      if lh > 0 then rh = rh + lh + SP.xs end
    end
    y = y + rh + 2
    if i == #stops then y = y + SP.xs end
  end
  return y
end

function MP:DrawWaypoints(p, x, y, w)
  local cv, Wy = p.cv, W()
  local hy = y
  y = y + cv:Sub(x, y, w, "Waypoints", self.WORDS.way, 50)
  p.popout:ClearAllPoints(); p.popout:SetPoint("TOPLEFT", p, "TOPLEFT", x + w - 46, -hy); p.popout:Show()
  cv:More(x + w - 20, hy, function()
    return { { text = "Import...", tip = "Paste /way lines.", func = function() MP:OpenImport() end },
      { text = "Export...", tip = "Every waypoint as a /way line to copy.", func = function() MP:Export() end } }
  end, "Import or export")
  y = y + SP.xs
  if not (Wy and Wy.active) then
    p.addBox:Hide(); p.popout:Hide()
    y = y + cv:Text(x, y, w, 12, "text.muted", self.WORDS.wayOff) + SP.xs
    if Panoply.Modules and Panoply.Modules.byKey.waypoints then
      cv:Button(x, y, "Turn waypoints on", function() Panoply.Modules:Set("waypoints", true) redraw() end, "Waypoints", "Switches the Waypoints module on.")
      y = y + 22 + SP.s
    end
    return y
  end
  p.addBox:ClearAllPoints(); p.addBox:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y); p.addBox:SetWidth(w); p.addBox:Show()
  y = y + 24 + SP.xs
  if self.addMsg then y = y + cv:Text(x, y, w, 11, "state.warn", self.addMsg, { wrap = true }) + SP.xs end
  local any = false
  local narrow = self.band ~= "wide"
  for _, g in ipairs(Wy.GROUPS) do
    local list = Wy:InGroup(g.id)
    if #list > 0 then
      any = true
      -- sorted by distance within the group (the nearest first)
      local pm, px, py = C.GetPlayerPos()
      local dist = {}
      for _, wp in ipairs(list) do dist[wp] = pm and Panoply.Nav and Panoply.Nav.Distance and Panoply.Nav.Distance(pm, px, py, wp.m, wp.x, wp.y) or math.huge end
      table.sort(list, function(a, b) return dist[a] < dist[b] end)
      local id = "wg:" .. g.id
      local def = (not narrow) or g.id == "mine"
      local open = self:IsOpen(id, def)
      cv:Icon(x, y + 1, open and "-" or "+", 18, function() MP:Toggle(id, def) end, open and "Collapse" or "Expand", g.label)
      local hh = cv:Text(x + 24, y + 2, w - 24 - 24, 12, "text.primary", ("%s (%d)"):format(g.label, #list), { name = true })
      cv:More(x + w - 20, y, function()
        return { { text = "Clear group", tip = "Takes every waypoint of " .. g.label .. " off the list.", func = function() Wy:ClearGroup(g.id) redraw() end } }
      end, "Clear group")
      y = y + max(22, hh + 6)
      if open then
        for _, wp in ipairs(list) do
          y = y + self:WayRow(cv, x + 12, y, w - 12, wp, {
            { label = "Add to trip", fn = function() Wy:AddToTrip(wp) redraw() end, tip = "Add to trip", body = "Makes it a stop of your trip." },
            { glyph = "Arrow", fn = function() Wy:Point(wp) redraw() end, tip = "Point the arrow", body = "The arrow takes you here first." },
            { glyph = "x", fn = function() local k = Wy:IndexOf(wp) if k then Wy:Remove(k) redraw() end end, tip = "Remove", body = "Takes this waypoint off the list." } }) + 2
        end
      end
    end
  end
  if not any then y = y + cv:Text(x, y, w, 11, "text.muted", self.WORDS.noWay) + SP.xs end
  return y + SP.xs
end

function MP:DrawSpots(p, x, y, w)
  local cv, S = p.cv, M.Spots
  if not S then return y end
  y = y + cv:Sub(x, y, w, "Saved spots", self.WORDS.spots)
  y = y + SP.xs
  local list = S:List()
  for _, sp in ipairs(list) do
    local tw = w - 22 - 20 - 20 - SP.s * 2
    local star = cv:Tex(x, y + 6, 14, 14)
    if star.SetTexCoord then star:SetTexCoord(0, 1, 0, 1) end
    Skin.SetGlyph(star, sp.fav and "Star" or "StarEmpty")
    local dist = distance(sp.map, sp.x, sp.y)
    local h1 = cv:Text(x + 20, y + 3, tw, 12, "text.primary", sp.name, { name = true })
    local h2 = cv:Text(x + 20, y + 3 + h1, tw, 11, "text.muted", S:Where(sp) .. (dist and (" · " .. dist) or "") .. " · every character")
    local rh = max(MP.WROW_H, h1 + h2 + 6)
    cv:Icon(x + w - 44, y + floor((rh - 20) / 2), "Arrow", 20, function() S:Go(sp.id) redraw() end, "Point the arrow", "Goes there: the arrow points at it.")
    cv:More(x + w - 20, y + floor((rh - 20) / 2), function()
      return {
        { text = sp.fav and "Remove the star" or "Star it", func = function() S:ToggleFav(sp.id) redraw() end },
        { text = "Rename...", func = function() S:OpenForm({ edit = sp.id }) end },
        { text = "Delete", tip = "Takes this spot off your saved list. This cannot be undone.", func = function() S:Remove(sp.id) redraw() end },
      }
    end, "Star, rename or delete")
    y = y + rh + 2
  end
  if #list == 0 then y = y + cv:Text(x, y, w, 11, "text.muted", self.WORDS.noSpots) + SP.xs end
  cv:Button(x, y, "Add where I stand", function() S:OpenForm({ here = true }) end, "Add where I stand", "Saves the place where your character stands, with a name you choose.")
  return y + 22 + SP.s
end

-- "In Wailing Caverns: next boss Lord Cobrahn" while inside (Engine/Dungeon.lua's run), and the Dungeons window
function MP.InsideLine()
  local D = Panoply.Dungeon
  local run = D and D.run
  if not run then return nil end
  local n = D.NextBoss and D:NextBoss()
  local name
  for _, b in ipairs(run.bosses or {}) do if b.n == n then name = b.name end end
  if name then return ("In %s: next boss %s"):format(run.name, name) end
  return ("In %s"):format(run.name)
end
function MP:DrawDungeons(p, x, y, w)
  local cv, Ins = p.cv, M.Instances
  if not Ins then return y end
  y = y + cv:Sub(x, y, w, "Dungeons", self.WORDS.dungeons)
  y = y + SP.xs
  local line = MP.InsideLine()
  if line then
    local h = cv:Text(x, y + 3, w, 12, "text.primary", line)
    cv:Hot(x, y, w, h + 6, function() Ins:Open(Ins:CurrentID()) end, line, "Opens the Dungeons window at this dungeon.")
    y = y + h + 6 + SP.xs
  end
  cv:Button(x, y, "Open the Dungeons window", function() Ins:Toggle() end, "Dungeons window", self.WORDS.dungeons)
  return y + 22 + SP.s
end

-- a waypoint change, a setting or a death redraws the page while it shows
for _, ev in ipairs({ "WAYPOINTS_CHANGED", "DEATH_LOGGED" }) do Panoply:Listen(ev, function() redraw() end) end
-- and so does the zone: the game's own events (the "N here" counts, the Rares list and the distances), once per burst of them
MP.zonePending = false
local function zoneRedraw()
  if MP.zonePending then return end
  MP.zonePending = true
  Panoply.Compat.After(0.5, function() MP.zonePending = false redraw() end)
end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do Panoply:On(ev, zoneRedraw) end
