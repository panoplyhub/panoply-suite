-- Panoply Suite trail (0.6.0 M4, SPEC 21.1 and 21.5; restyled in 0.6.2): the route drawn on the world map
-- and on the minimap. Own code and own art (the round CircleMask disc and Line widgets), no glow.
-- 0.6.2: every travel type has its own line, each in a strong colour over a dark ink outline so it
-- reads on any map colour (0.6.1's brass dots matched the ochre Classic map art and could not be seen):
--   * walking   moving "ant trail" dots (the only animated style)
--   * flight    one solid line along the flight path (gryphon, wyvern, bat)
--   * boat      long dashes
--   * zeppelin  dash-dot
--   * tram      a double rail with ties (Deeprun Tram)
--   portals and the hearthstone have no line (they jump); a boat or zeppelin to another continent is a
--   loading screen, so it has no line either (the route card still lists it).
-- The same styles on zone maps, continent maps and the minimap. World map: every leg that crosses the
-- map on screen is drawn, explored or not (the map's explored-area art never hides or masks frames;
-- see C.WorldMapLevel), clipped to the canvas; the layer sits at an explicit pin frame level read from
-- Blizzard's own level manager. Minimap: 10 updates a second, clipped to the circle, rotation and zoom
-- aware, hidden in instances. Off the trail: a short pale dotted line back to it, and a line on the card.
-- Drawing only: nothing here is protected, clicks anything or acts for the player. Textures and lines
-- are created only when a pool grows; per update the code only moves, colours and shows/hides them.
-- Colours are skin tokens (Skin.colors.trail*) so a skin can restyle them.
-- Step 2 D (the Look of the map, Map page > gear): on each map the walking part has its own Size, Spacing, Opacity, Style (dots, dashes or
-- a line) and Colour (by travel type, or one colour for the whole trail; the dark outline stays). Flights, boats, zeppelins and trams keep
-- their own shapes. Trail:WalkSetup builds the walking geometry for the world map, the minimap and the live preview alike.
local ADDON, Panoply = ...
local Trail = {}
Panoply.Trail = Trail
local Skin, C = Panoply.Skin, Panoply.Compat
local sqrt, floor, ceil, max, min, cos, sin, abs = math.sqrt, math.floor, math.ceil, math.max, math.min, math.cos, math.sin, math.abs

-- Skin tokens (a skin that defines them wins; these are the v3 palette values). Every core colour is
-- bright (relative luminance about 0.5 or more): it reads on dark map art by itself and on bright map
-- art through the ink outline.
Skin.colors.trailWalk = Skin.colors.trailWalk or { Skin.hex("#4de4ff") }   -- bright cyan: on foot
Skin.colors.trailFly = Skin.colors.trailFly or { Skin.hex("#ff9cef") }     -- pink: flights
Skin.colors.trailShip = Skin.colors.trailShip or { Skin.hex("#fff04a") }   -- yellow: boats
Skin.colors.trailZeppelin = Skin.colors.trailZeppelin or { Skin.hex("#ff9440") }   -- orange: zeppelins
Skin.colors.trailTram = Skin.colors.trailTram or { Skin.hex("#a8ff5c") }   -- lime: the tram
Skin.colors.trailRide = Skin.colors.trailRide or { Skin.hex("#b8955a") }   -- brass: the card rule, the trip window
Skin.colors.trailOff = Skin.colors.trailOff or { Skin.hex("#f5f5f5") }     -- white: back to the trail
Skin.colors.trailInk = Skin.colors.trailInk or { Skin.hex("#0a0d12") }     -- the dark outline under every mark
Skin.TEX.TrailDot = Skin.TEX.TrailDot or Skin.TEX.CircleMask               -- a plain round disc, no halo

-- The five line styles, in legend order.
Trail.KINDS = { "walk", "fly", "ship", "zeppelin", "tram" }
Trail.STYLE = {
  walk = { token = "trailWalk", draw = "ants", label = "on foot" },
  fly = { token = "trailFly", draw = "solid", label = "flight" },
  ship = { token = "trailShip", draw = "dash", label = "boat" },
  zeppelin = { token = "trailZeppelin", draw = "dashdot", label = "zeppelin" },
  tram = { token = "trailTram", draw = "rail", label = "tram" },
}

Trail.MAP_MAX = 200            -- world map walking dots (SPEC 21.5)
Trail.LINE_MAX = 480           -- world map line pieces (flight, boat, zeppelin, tram cores)
Trail.MINI_MAX = 40            -- minimap dots, the off-trail cue included
Trail.MINI_LINE_MAX = 90       -- minimap line pieces
Trail.MINI_HZ = 10             -- minimap updates a second
Trail.MAP_ANT_HZ = 12          -- world map ant-trail steps a second while the map is open
Trail.MAP_WATCH = 0.2          -- s between cheap "did the map change or zoom?" checks while the map is open
-- world map geometry in screen (UI) pixels; divided by the canvas scale so it keeps its size when zoomed
Trail.MAP_WALK_PX, Trail.MAP_WALK_DOT = 15, 8      -- ant dots: spacing and size
Trail.MAP = { ink = 2, line = 3.6, dash = 16, gap = 9, zdash = 14, zgap = 6, zdot = 6, rail = 2.6, railSep = 6.4, tie = 9, tieW = 1.8, step = 4 }
-- minimap geometry (minimap pixels)
Trail.MINI_WALK_STEPS = 15     -- ant dots across the minimap's diameter
Trail.MINI_WALK_DOT, Trail.MINI_OFF_DOT = 6, 5
Trail.MINI = { ink = 1.5, line = 2.6, dash = 11, gap = 6, zdash = 10, zgap = 4.5, zdot = 5, rail = 2.5, railSep = 5, tie = 7, tieW = 1.4, step = 3 }
Trail.DRIFT = 0.35             -- ant speed in dot gaps per second (option "Let the dots drift slowly")
Trail.CUE_MAX = 8              -- dots in the off-trail cue
Trail.MARK_PX = 16             -- the next-stop marker (screen px)
Trail.WALK_PIECES = { wm = 200, mm = 90 }   -- dashes / line pieces of the walking part: never more (the dots' caps are MAP_MAX and MINI_MAX)
Trail.WALK_DRAW = { dots = "ants", dashes = "wdash", line = "solid" }
Trail.DASH_K = 2.6             -- a walking dash is this many line thicknesses long (a boat's long dash is 16 px; a walking one about 9)
-- Nov 14 2026 (0.9.4 step 22): only the way AHEAD of the player is drawn. The player is followed along the walk: each update looks at the
-- stretch just ahead of where he last was (TRIM_AHEAD_YD of walk, and TRIM_BACK_YD behind it for a stutter), never back across a loop; a
-- full search of the route is made only for a new route, another continent, a long jump, or after being off the walk (further than
-- Route.OFF_TRAIL_YD from it). The dots and dashes behind the spot he is at are not drawn.
Trail.TRIM_AHEAD_YD = 160
Trail.TRIM_BACK_YD = 8
-- Nov 14 2026 (17-22 review, backlog 8): a player who walks back along the walk (8 to 60 yd) is followed: the spot the trail starts at moves
-- back to where he is, so no gap opens between him and the first dot. A step back smaller than STUTTER_BACK_YD is a stutter of the position
-- and is ignored (the dots do not flicker). The nearest point is looked for only in the window (TRIM_BACK_YD behind the spot, TRIM_AHEAD_YD
-- ahead), so a loop that comes back near its start never brings the dots far behind him back; further than Route.OFF_TRAIL_YD from the walk
-- the whole route is searched, as before.
Trail.STUTTER_BACK_YD = 1.5
Trail.BACK_LOOKS = 12          -- at most this many looks in one update while he walks back (each reaches TRIM_BACK_YD further)

local function opt(key) local db = Panoply.db return not (db and db[key] == false) end
-- 0.7.3.7 ("Fix every size slider"): the dots have their own size and opacity on each map
-- (Trail dots in the Map page's gear): `where` is "wm" for the world map, "mm" for the minimap. The walking
-- dots and the pale way-back dots are sized (25% to 300% of their normal size; the spacing grows with them so big dots
-- never touch); the whole trail follows the opacity (10% to 100%).
local function alpha(where) return Panoply.Look.Alpha("trail", where or "wm") end
Trail.Alpha = alpha
Trail.SIZE_MIN, Trail.SIZE_MAX = Panoply.Look.SIZE_MIN, Panoply.Look.SIZE_MAX
local function size(where) return Panoply.Look.Size("trail", where or "wm") end
Trail.Size = size
Trail.GAP_MIN = 0.6            -- the spacing of the dots stops shrinking here (their size goes on to 25%): a small dot keeps its gaps and the dot cap is never hit
local function tok(name) local c = Skin.colors[name] or Skin.colors.trailWalk return c end
-- `where` ("wm" / "mm") says which map's Colour setting applies: one colour for the whole trail, or By travel type (the standard).
-- The dark outline, the white way-back dots and the white markers do not change.
function Trail:Color(kind, where)
  if kind == "off" then return tok("trailOff") end
  if kind == "ink" then return tok("trailInk") end
  local s = self.STYLE[kind]
  if where and s then
    local one = Panoply.Look.RGB("trail", where)
    if one then return one end
  end
  return tok(s and s.token or "trailOff")
end
local function col(kind, where) local c = Trail:Color(kind, where) return c[1], c[2], c[3] end

-------------------------------------------------------------------------------
-- Route -> world polylines (built once per route, never per frame)
-------------------------------------------------------------------------------
-- { cont, kind = walk|fly|ship|zeppelin|tram, leg = index, x = {...}, y = {...}, cum = {...}, len, minX, maxX, minY, maxY }
local function newSeg(cont, kind, leg) return { cont = cont, kind = kind, leg = leg, x = {}, y = {}, cum = {}, len = 0 } end
local function addPt(s, x, y)
  local n = #s.x
  if n > 0 then
    local dx, dy = x - s.x[n], y - s.y[n]
    local d = sqrt(dx * dx + dy * dy)
    if d < 0.5 then return end
    s.len = s.len + d
  end
  s.x[n + 1], s.y[n + 1], s.cum[n + 1] = x, y, s.len
  s.minX, s.maxX = min(s.minX or x, x), max(s.maxX or x, x)
  s.minY, s.maxY = min(s.minY or y, y), max(s.maxY or y, y)
end

-- Why a leg has no line (for /panoply mapdebug and the card).
Trail.NO_LINE = {
  portal = "portal: a jump, no line", hearth = "hearthstone: a jump, no line",
  cross = "to another continent: a loading screen, no line", short = "too short to draw",
}
function Trail:Build(r)
  local segs, none = {}, {}
  self.noLine = none
  if not r then return segs end
  local RD = Panoply.Route and Panoply.Route:Data()
  for i, l in ipairs(r.legs or {}) do
    local k = l.kind
    local same = l.from and l.to and l.from.cont ~= nil and l.from.cont == l.to.cont
    if k == "walk" and same then
      local s = newSeg(l.from.cont, "walk", i)
      for _, p in ipairs(l.points or { { l.from.wx, l.from.wy }, { l.to.wx, l.to.wy } }) do addPt(s, p[1], p[2]) end
      segs[#segs + 1] = s
    elseif k == "fly" then
      local s = newSeg(l.from.cont, "fly", i)
      -- a flight that brings its own line (PanoplyGuide's plan lists every flight point it passes)
      if l.points then for _, p in ipairs(l.points) do addPt(s, p[1], p[2]) end end
      for _, row in ipairs(l.paths or {}) do
        local pts = RD and RD.Trail and row[5] and RD.Trail(row)
        if pts and #pts >= 2 then for _, p in ipairs(pts) do addPt(s, p[1], p[2]) end end
      end
      if #s.x < 2 then addPt(s, l.from.wx, l.from.wy) addPt(s, l.to.wx, l.to.wy) end
      segs[#segs + 1] = s
    elseif (k == "ship" or k == "zeppelin" or k == "tram") and same then
      local s = newSeg(l.from.cont, k, i)
      addPt(s, l.from.wx, l.from.wy) addPt(s, l.to.wx, l.to.wy)
      segs[#segs + 1] = s
    else
      none[#none + 1] = { leg = i, kind = k, why = (k == "portal" and self.NO_LINE.portal) or (k == "hearth" and self.NO_LINE.hearth)
        or ((k == "ship" or k == "zeppelin" or k == "tram" or k == "walk") and self.NO_LINE.cross) or ("no line for " .. tostring(k)) }
    end
  end
  for i = #segs, 1, -1 do
    if #segs[i].x < 2 then
      none[#none + 1] = { leg = segs[i].leg, kind = segs[i].kind, why = self.NO_LINE.short }
      table.remove(segs, i)
    end
  end
  table.sort(none, function(a, b) return a.leg < b.leg end)
  return segs
end

-- The styles this route uses, in legend order.
function Trail:KindsInUse(segs)
  local seen, out = {}, {}
  for _, s in ipairs(segs or self.segs or {}) do seen[s.kind] = true end
  for _, k in ipairs(self.KINDS) do if seen[k] then out[#out + 1] = k end end
  return out
end

function Trail:SetRoute(r)
  if Panoply:PlayAlong() or Panoply:NoGuideHere() then r = nil end   -- 0.7.1: no trail while playing along (0.7.4.1: or in an area without a guide)
  self.route = r
  self.segs = self:Build(r)
  self.mapSig = nil
  self:UpdateDrivers()
  self:DrawMap()
end

-------------------------------------------------------------------------------
-- Pens: pooled dots (an ink disc under a coloured disc) and pooled lines (an ink line under a
-- coloured line). Every colour sits above every outline, so overlapping pieces read as one stroke.
-------------------------------------------------------------------------------
local function hideFrom(pool, n) for i = n + 1, #pool do local t = pool[i] if t.panoplyOn ~= false then t:Hide() t.panoplyOn = false end end end
local function put(t, layer, x, y, size, r, g, b, a)
  t:ClearAllPoints()
  t:SetPoint("CENTER", layer, "TOPLEFT", x, y)
  t:SetSize(size, size)
  t:SetVertexColor(r, g, b, a)
  if t.panoplyOn ~= true then t:Show() t.panoplyOn = true end
end
local function newDot(layer, draw, sub)
  local t = layer:CreateTexture(nil, draw, nil, sub)
  t:SetTexture(Skin.TEX.TrailDot)
  t.panoplyLayoutSkip = true                 -- map art, not a control (the layout checker skips it)
  Trail.created = (Trail.created or 0) + 1
  return t
end
local function newLine(layer, draw, sub)
  if not layer.CreateLine then return nil end
  local l = layer:CreateLine(nil, draw, nil, sub)
  if not l then return nil end
  l.panoplyLayoutSkip = true
  Trail.created = (Trail.created or 0) + 1
  return l
end
local function setLine(l, layer, x1, y1, x2, y2, th, r, g, b, a)
  l:ClearAllPoints()
  l:SetStartPoint("TOPLEFT", layer, x1, y1)
  l:SetEndPoint("TOPLEFT", layer, x2, y2)
  l:SetThickness(th)
  l:SetColorTexture(r, g, b, a)
  if l.panoplyOn ~= true then l:Show() l.panoplyOn = true end
end

local Pen = {}
Pen.__index = Pen
Trail.Pen = Pen
-- `where` ("wm" / "mm"): the map this pen draws on, so the colour of that map's setting is used (nil: the standard colours)
function Trail:NewPen(layer, maxDots, maxLines, where)
  return setmetatable({ layer = layer, dots = {}, inks = {}, lines = {}, inkLines = {}, nd = 0, nl = 0, ni = 0,
    maxD = maxDots or 0, maxL = maxLines or 0, where = where }, Pen)
end
function Pen:Begin() self.nd, self.nl, self.ni, self.full = 0, 0, 0, nil end
function Pen:End()
  hideFrom(self.dots, self.nd) hideFrom(self.inks, self.nd)
  hideFrom(self.lines, self.nl) hideFrom(self.inkLines, self.ni)
end
function Pen:Clear() self:Begin() self:End() end
-- a dot of `size` with an ink rim `ink` wide; x, y are TOPLEFT offsets of the layer (y negative)
function Pen:Dot(x, y, size, c, a, ink, kind)
  if self.nd >= self.maxD then self.full = true return nil end
  local i = self.nd + 1
  self.nd = i
  local t = self.dots[i]
  if not t then t = newDot(self.layer, "OVERLAY", 2) self.dots[i] = t end
  if ink and ink > 0 then
    local o = self.inks[i]
    if not o then o = newDot(self.layer, "ARTWORK", 2) self.inks[i] = o end
    local k = Trail:Color("ink")
    put(o, self.layer, x, y, size + 2 * ink, k[1], k[2], k[3], a)
    t.ink = o
  else
    if self.inks[i] and self.inks[i].panoplyOn then self.inks[i]:Hide() self.inks[i].panoplyOn = false end
    t.ink = nil
  end
  put(t, self.layer, x, y, size, c[1], c[2], c[3], a)
  t.panoplyKind = kind
  if self.onPut then self.onPut(x, y) end
  return t
end
-- an ink line only (the base of the rails)
function Pen:Ink(x1, y1, x2, y2, th, a)
  if self.ni >= self.maxL * 2 then self.full = true return nil end
  local i = self.ni + 1
  local o = self.inkLines[i]
  if not o then o = newLine(self.layer, "ARTWORK", 0) if not o then return nil end self.inkLines[i] = o end
  self.ni = i
  local k = Trail:Color("ink")
  setLine(o, self.layer, x1, y1, x2, y2, th, k[1], k[2], k[3], a)
  return o
end
-- a coloured line `th` thick, `ext` longer at each end, over an ink line `ink` wider on every side
function Pen:Line(x1, y1, x2, y2, th, c, a, ink, kind, ext, role)
  if self.nl >= self.maxL then self.full = true return nil end
  local dx, dy = x2 - x1, y2 - y1
  local L = sqrt(dx * dx + dy * dy)
  if L <= 0 then return nil end
  local ux, uy = dx / L, dy / L
  local o
  if ink and ink > 0 then
    local e = (ext or 0) + ink
    o = self:Ink(x1 - ux * e, y1 - uy * e, x2 + ux * e, y2 + uy * e, th + 2 * ink, a)
    if not o then return nil end
  end
  local i = self.nl + 1
  local l = self.lines[i]
  if not l then l = newLine(self.layer, "OVERLAY", 1) if not l then return nil end self.lines[i] = l end
  self.nl = i
  local e = ext or 0
  setLine(l, self.layer, x1 - ux * e, y1 - uy * e, x2 + ux * e, y2 + uy * e, th, c[1], c[2], c[3], a)
  l.panoplyKind, l.panoplyRole, l.ink = kind, role or "core", o
  if self.onPut then self.onPut((x1 + x2) / 2, (y1 + y2) / 2) end
  return l
end

-------------------------------------------------------------------------------
-- Clipping (pieces are cut to the canvas or the minimap circle, so a leg that crosses the map is
-- drawn up to the edge, never past it)
-------------------------------------------------------------------------------
-- Liang-Barsky. No table is made per call (a clipped walking dash is cut like this 12 times a second, up to 200 of them at once: two
-- small tables each were about 5,000 a second of garbage); the four edges are taken one at a time with plain numbers.
local function clipRect(cl, x0, y0, x1, y1)
  local t0, t1 = 0, 1
  local dx, dy = x1 - x0, y1 - y0
  for i = 1, 4 do
    local p, q
    if i == 1 then p, q = -dx, x0 - cl.x0
    elseif i == 2 then p, q = dx, cl.x1 - x0
    elseif i == 3 then p, q = -dy, y0 - cl.y0
    else p, q = dy, cl.y1 - y0 end
    if p == 0 then
      if q < 0 then return nil end
    else
      local r = q / p
      if p < 0 then if r > t1 then return nil elseif r > t0 then t0 = r end
      else if r < t0 then return nil elseif r < t1 then t1 = r end end
    end
  end
  return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end
local function clipCircle(cl, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local fx, fy = x0 - cl.cx, y0 - cl.cy
  local a = dx * dx + dy * dy
  if a <= 0 then return nil end
  local b = 2 * (fx * dx + fy * dy)
  local c = fx * fx + fy * fy - cl.r * cl.r
  local disc = b * b - 4 * a * c
  if disc <= 0 then return nil end
  local s = sqrt(disc)
  local t0, t1 = max(0, (-b - s) / (2 * a)), min(1, (-b + s) / (2 * a))
  if t0 >= t1 then return nil end
  return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end
function Trail.RectClip(x0, y0, x1, y1)
  return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, seg = clipRect,
    pt = function(cl, x, y, m) m = m or 0 return x >= cl.x0 + m and x <= cl.x1 - m and y >= cl.y0 + m and y <= cl.y1 - m end }
end
local function ptCircle(cl, x, y, m) local dx, dy = x - cl.cx, y - cl.cy local rr = cl.r - (m or 0) return rr > 0 and dx * dx + dy * dy <= rr * rr end
function Trail.CircleClip(cx, cy, r) return { cx = cx, cy = cy, r = r, seg = clipCircle, pt = ptCircle } end
-- the same circle again with another centre and radius (the minimap keeps two and sets them each update: nothing is made)
function Trail.SetCircle(cl, cx, cy, r) cl.cx, cl.cy, cl.r = cx, cy, r return cl end

-------------------------------------------------------------------------------
-- The stroker: one polyline in layer coordinates (xs, ys, with cum = distance along it in the same
-- units) drawn in the style of `kind`. G = geometry (already in layer units), phase = ant offset.
-- Returns the number of dots and pieces drawn; `rec` (optional) collects the pieces for mapdebug.
-------------------------------------------------------------------------------
local function at(xs, ys, cum, i, d)
  local n = #xs
  while i < n - 1 and cum[i + 1] < d do i = i + 1 end
  local L = cum[i + 1] - cum[i]
  local t = L > 0 and (d - cum[i]) / L or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return xs[i] + (xs[i + 1] - xs[i]) * t, ys[i] + (ys[i + 1] - ys[i]) * t, i
end
-- draw the part of the polyline between distances d0 and d1 as pieces
local function span(pen, xs, ys, cum, i, d0, d1, piece)
  local n = #xs
  while i < n - 1 and cum[i + 1] <= d0 do i = i + 1 end
  local ax, ay = at(xs, ys, cum, i, d0)
  local j = i
  while j < n and cum[j + 1] < d1 do
    piece(ax, ay, xs[j + 1], ys[j + 1])
    ax, ay = xs[j + 1], ys[j + 1]
    j = j + 1
  end
  local bx, by = at(xs, ys, cum, min(j, n - 1), d1)
  piece(ax, ay, bx, by)
  return i
end

-- Nov 14 2026 (step 22): the stroker's state is in these upvalues and its three helpers are made once, so a Stroke call makes no closure and
-- no table (the minimap strokes ten times a second). `from` (optional) is the distance along cum where drawing starts: the part of the
-- walk behind the player is not drawn. Dots and dashes keep their place on the ground (their phase is along the whole walk).
local sPen, sClip, sA, sC, sKind, sG, sTh0, sRec, sPieces, sDots
local function note(x1, y1, x2, y2)
  local rec = sRec
  if rec and #rec < (rec.max or 400) then rec[#rec + 1] = x2 and { x1, y1, x2, y2 } or { x1, y1 } elseif rec then rec.more = (rec.more or 0) + 1 end
end
local function piece(x1, y1, x2, y2, th, ext, ink)
  local cx1, cy1, cx2, cy2 = x1, y1, x2, y2
  if sClip then cx1, cy1, cx2, cy2 = sClip:seg(x1, y1, x2, y2) if not cx1 then return end end
  if (cx2 - cx1) ^ 2 + (cy2 - cy1) ^ 2 < 0.01 then return end
  if sPen:Line(cx1, cy1, cx2, cy2, th or sTh0, sC, sA, ink or sG.ink, sKind, ext) then sPieces = sPieces + 1 note(cx1, cy1, cx2, cy2) end
end
local function dot(x, y, size)
  if sClip and not sClip:pt(x, y, size / 2 + sG.ink) then return end
  if sPen:Dot(x, y, size, sC, sA, sG.ink, sKind) then sDots = sDots + 1 note(x, y) end
end

function Trail:Stroke(pen, xs, ys, cum, kind, G, clip, a, phase, rec, from)
  local n = #xs
  if n < 2 then return 0, 0 end
  -- Step 2 D: the walking part is drawn as the Style of its map says (G.walk: ants = dots, wdash = dashes, solid = a line); every other
  -- kind keeps its own shape. Walking pieces are as thick as the dots are big (G.wline).
  local style = (kind == "walk" and G.walk) or (self.STYLE[kind] or self.STYLE.fly).draw
  sPen, sClip, sA, sKind, sG, sRec = pen, clip, a, kind, G, rec
  sC = self:Color(kind, pen.where)
  sTh0 = (kind == "walk" and G.wline) or G.line
  sPieces, sDots = 0, 0
  local th0 = sTh0
  local total = cum[n]
  local lo = cum[1]
  if from and from > lo then lo = from end
  if style == "ants" then
    local gap = G.gap
    if not gap or gap <= 0 then return 0, 0 end
    -- the dots sit at a fixed rhythm along the whole walk; the first one drawn is the first of them at or after `lo`
    local d = (phase or 0.5 * gap) % gap
    if lo > d then d = d + ceil((lo - d) / gap) * gap end
    local i = 1
    while d <= total and not pen.full do
      local x, y
      x, y, i = at(xs, ys, cum, i, d)
      dot(x, y, G.dot)
      d = d + gap
    end
  elseif style == "solid" then
    local k0, sx, sy = 1, nil, nil
    if lo > cum[1] then
      while k0 < n - 1 and cum[k0 + 1] <= lo do k0 = k0 + 1 end
      local L = cum[k0 + 1] - cum[k0]
      local t = L > 0 and (lo - cum[k0]) / L or 0
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      sx, sy = xs[k0] + (xs[k0 + 1] - xs[k0]) * t, ys[k0] + (ys[k0 + 1] - ys[k0]) * t
    end
    for k = k0, n - 1 do
      local ax, ay = xs[k], ys[k]
      if k == k0 and sx then ax, ay = sx, sy end
      piece(ax, ay, xs[k + 1], ys[k + 1], th0, th0 / 2)
      if pen.full then break end
    end
  elseif style == "wdash" then
    -- walking dashes: short dashes (the boat's long ones stay the boat's), the gap is the Spacing; they drift like the dots do. A walking
    -- dash is ONE piece from where it starts to where it ends (a road has a point every pixel or so: following each of them would use a
    -- dozen pieces for a dash and the cap would run out after a few), so the pieces the pen may draw are the dashes it may draw.
    local period = G.wdash + G.wgap
    if period <= 0 then return 0, 0 end
    local d, i = ((phase or 0) % period) - period, 1
    if lo > d + G.wdash then d = d + floor((lo - d - G.wdash) / period) * period end
    while d < total and not pen.full do
      local d0, d1 = max(lo, d, 0), min(total, d + G.wdash)
      if d1 > d0 then
        local ax, ay, j = at(xs, ys, cum, i, d0)
        local bx, by = at(xs, ys, cum, j, d1)
        i = j
        piece(ax, ay, bx, by)
      end
      d = d + period
    end
  elseif style == "dash" or style == "dashdot" then
    local dash, gap = (style == "dash" and G.dash or G.zdash), (style == "dash" and G.gap or G.zgap)
    local period = style == "dash" and (dash + gap) or (dash + gap + G.zdot + gap)
    local d, i = 0, 1
    while d < total and not pen.full do
      local d1 = min(total, d + dash)
      if d1 > d then i = span(pen, xs, ys, cum, i, d, d1, piece) end
      if style == "dashdot" then
        local dd = d + dash + gap + G.zdot / 2
        if dd < total then local x, y = at(xs, ys, cum, i, dd) dot(x, y, G.zdot) end
      end
      d = d + period
    end
  elseif style == "rail" then
    local base = G.railSep + G.rail + 2 * G.ink
    for k = 1, n - 1 do
      local x1, y1, x2, y2 = xs[k], ys[k], xs[k + 1], ys[k + 1]
      if clip then x1, y1, x2, y2 = clip:seg(x1, y1, x2, y2) end
      if x1 then
        local dx, dy = x2 - x1, y2 - y1
        local L = sqrt(dx * dx + dy * dy)
        if L > 0.1 then
          local nx, ny = -dy / L * G.railSep / 2, dx / L * G.railSep / 2
          local ux, uy = dx / L * G.ink, dy / L * G.ink
          local bed = pen:Ink(x1 - ux, y1 - uy, x2 + ux, y2 + uy, base, a)
          if bed then
            local r1 = pen:Line(x1 + nx, y1 + ny, x2 + nx, y2 + ny, G.rail, sC, a, 0, kind, G.rail / 2)
            if r1 then r1.ink = bed sPieces = sPieces + 1 note(x1, y1, x2, y2) end
            local r2 = pen:Line(x1 - nx, y1 - ny, x2 - nx, y2 - ny, G.rail, sC, a, 0, kind, G.rail / 2)
            if r2 then r2.ink = bed end
          end
        end
      end
      if pen.full then break end
    end
    -- ties across the rails
    local d, i = G.tie / 2, 1
    while d < total and not pen.full do
      local x, y, j = at(xs, ys, cum, i, d)
      i = j
      local dx, dy = xs[j + 1] - xs[j], ys[j + 1] - ys[j]
      local L = sqrt(dx * dx + dy * dy)
      if L > 0 and (not clip or clip:pt(x, y, G.railSep)) then
        local hx, hy = -dy / L * (G.railSep / 2 + G.rail * 0.5), dx / L * (G.railSep / 2 + G.rail * 0.5)
        pen:Line(x - hx, y - hy, x + hx, y + hy, G.tieW, sC, a, 0, kind, 0, "tie")
      end
      d = d + G.tie
    end
  end
  return sDots, sPieces
end

-- geometry table scaled from screen pixels to layer units
-- (Nov 14 2026, step 22: scaledInto fills a table the caller keeps, so the minimap's update makes no table of its own)
local function scaledInto(g, src, u, extra)
  for k, v in pairs(src) do g[k] = v * u end
  if extra then for k, v in pairs(extra) do g[k] = v end end
  return g
end
local function scaled(src, u, extra) return scaledInto({}, src, u, extra) end
Trail.Scaled = scaled

-- The walking part on one map (Look of the map): its geometry, from the map's Size, Spacing and Style. ONE function builds it for the
-- world map, the minimap and the live preview, so the preview draws what the maps draw.
--   where    "wm" | "mm"            src      Trail.MAP | Trail.MINI     u   layer units per screen pixel (1 on the minimap)
--   baseGap  the gap between dots at Size 100% and Spacing 100% (layer units)     baseDot  the dot's size in screen pixels
--   len      the length of the walking part to draw (layer units)               cap   the most pieces the pen may draw
--   grow     the world map has always spread its dots when the cap would be hit; the minimap cut them off, and keeps doing so at
--            Spacing 100% (nothing changes for a player who never opens the Look of the map)
-- Returns the geometry: G.walk (ants | wdash | solid), G.gap and G.period (dots and dashes), G.dot, G.wline (the thickness of a dash
-- or a line), G.wdash and G.wgap (dashes), G.lstep (the line is drawn between points this far apart). Spacing never makes more
-- pieces than the cap: a small Spacing stops at the gap that just fills it.
-- (`into`, optional: a table the caller keeps and gets filled again, so an update that runs ten times a second makes no table)
function Trail:WalkSetup(where, src, u, baseGap, baseDot, len, cap, grow, into)
  local Look = Panoply.Look
  local ds = size(where)
  local sp = Look.Spacing("trail", where)
  local style = Look.Style("trail", where)
  local gap1 = baseGap * max(ds, Trail.GAP_MIN)           -- tiny dots keep a readable gap (their size goes on to 25%)
  local G = into and scaledInto(into, src, u) or scaled(src, u)
  G.lstep, G.wdash, G.wgap, G.period = nil, nil, nil, nil
  G.style, G.walk, G.ds = style, self.WALK_DRAW[style], ds
  G.wline = G.line * ds
  G.dot = baseDot * u * ds
  local fill = cap > 0 and len / cap or 0                  -- the gap that just fills the cap
  if style == "line" then
    G.lstep = max(G.step, fill)
    G.gap, G.period = gap1, nil
  elseif style == "dashes" then
    G.wdash = self.DASH_K * G.wline
    G.wgap = max(2 * u, 0.5 * gap1 * sp, fill - G.wdash)
    G.gap, G.period = G.wgap, G.wdash + G.wgap
  else
    G.gap = max(gap1 * sp, grow and fill or min(gap1, fill))
    G.period = G.gap
  end
  return G
end

-- Thin a polyline to points about `step` apart (the line style draws one piece between two points, and the pen may only draw so many).
-- The first and the last point stay. Writes into ox, oy, oc and returns them.
local function thin(xs, ys, cum, n, step, ox, oy, oc)
  local k = 1
  ox[1], oy[1], oc[1] = xs[1], ys[1], cum[1]
  local last = cum[1]
  for i = 2, n - 1 do
    if cum[i] - last >= step then k = k + 1 ox[k], oy[k], oc[k] = xs[i], ys[i], cum[i] last = cum[i] end
  end
  k = k + 1
  ox[k], oy[k], oc[k] = xs[n], ys[n], cum[n]
  for j = #ox, k + 1, -1 do ox[j], oy[j], oc[j] = nil, nil, nil end
  return ox, oy, oc
end
Trail.Thin = thin

-------------------------------------------------------------------------------
-- World map
-------------------------------------------------------------------------------
-- Map rectangle in world yards: { cont, top (max x), bottom, left (max y), right }.
Trail.rects = {}
function Trail:MapRect(map)
  if not map then return nil end
  local c = self.rects[map]
  if c ~= nil then return c or nil end
  local RD = Panoply.Route and Panoply.Route:Data()
  local r = RD and RD.rects and RD.rects[map]
  if r then
    c = { r[1], r[4], r[2], r[5], r[3] }
  elseif C.WorldPos then
    local c0, x0, y0 = C.WorldPos(map, 0, 0)
    local c1, x1, y1 = C.WorldPos(map, 1, 1)
    if c0 and c0 == c1 and x0 ~= x1 and y0 ~= y1 then c = { c0, x0, x1, y0, y1 } end
  end
  self.rects[map] = c or false
  return c
end

-- The canvas's scale on screen relative to the UI (zoom, the small or maximized window, any parent
-- scale): sizes are given in UI pixels and divided by this.
function Trail:CanvasScale(canvas)
  local ui = _G.UIParent
  local ce = canvas and canvas.GetEffectiveScale and tonumber(canvas:GetEffectiveScale())
  local ue = ui and ui.GetEffectiveScale and tonumber(ui:GetEffectiveScale())
  local s
  if ce and ue and ce > 0 and ue > 0 then s = ce / ue end
  if not s or s ~= s or s <= 0 then s = (canvas and canvas.GetScale and canvas:GetScale()) or 1 end
  if not s or s <= 0 then s = 1 end
  return s
end

-- The layer: a plain frame on the map canvas (the scroll child, so it pans and zooms with the map art),
-- at an explicit frame level from the map's own pin level manager (C.WorldMapLevel "trail": above the
-- explored-area art, the fog and the highlights, and above Blizzard's town, flight and quest pins,
-- under our own pins, the group members and the player arrow). Set again on every redraw.
function Trail:MapLayer(canvas)
  if not self.mapLayer then
    self.mapLayer = CreateFrame("Frame", nil, canvas)
    self.mapLayer:SetAllPoints(canvas)
    self.mapLayer.panoplyLayoutSkip = true
    self.mapPen = self:NewPen(self.mapLayer, 0, self.LINE_MAX, "wm")
    self.mapPen.maxD = 60                       -- zeppelin dots
    self.antPen = self:NewPen(self.mapLayer, self.MAP_MAX, 0, "wm")
    self.mapPool, self.linePool = self.antPen.dots, self.mapPen.lines
  end
  if self.mapLayer.GetParent and self.mapLayer:GetParent() ~= canvas and self.mapLayer.SetParent then
    self.mapLayer:SetParent(canvas) self.mapLayer:ClearAllPoints() self.mapLayer:SetAllPoints(canvas)
  end
  self.antPen.maxD = self.MAP_MAX
  self.antPen.maxL = self.WALK_PIECES.wm        -- Step 2 D: dashes and the line are pieces of their own, never more than this
  self.mapLevel = C.LiftOnWorldMap(self.mapLayer, "trail")
  -- 0.6.2: follow the map's fade only down to C.MAP_ALPHA_FLOOR (small Era map fading)
  if C.FloorMapAlpha then C.FloorMapAlpha(self.mapLayer) C.HookMapAlpha() end
  if not self.mapLayer:IsShown() then self.mapLayer:Show() end
  return self.mapLayer
end

-- Is the map on screen a continent? (Only the debug snapshot and the tests care; every map gets the
-- same styles since 0.6.2.)
function Trail:IsContinentMap(map)
  local t = C.MapType and C.MapType(map)
  local want = (_G.Enum and Enum.UIMapType and tonumber(Enum.UIMapType.Continent)) or C.MAP_TYPE_CONTINENT
  return t ~= nil and t == want
end

-- The next stop: where the leg you are on ends (the route is re-planned from where you stand).
function Trail:NextStop()
  local r = self.route
  local l = r and r.legs and r.legs[1]
  local to = l and l.to
  if not (to and to.cont and to.wx and to.wy) then return nil end
  return to.cont, to.wx, to.wy, to, l.kind
end

function Trail:Marker(layer)
  local m = self.mark
  if m then return m end
  m = {}
  for i, key in ipairs({ "ink", "ring", "gap", "core" }) do
    local t = layer:CreateTexture(nil, "OVERLAY", nil, 3 + i)
    t:SetTexture(Skin.TEX.TrailDot)
    t.panoplyLayoutSkip = true
    m[key] = t
  end
  self.mark = m
  return m
end
function Trail:HideMarker()
  local m = self.mark
  if m then for _, t in pairs(m) do if t.panoplyOn ~= false then t:Hide() t.panoplyOn = false end end end
  self.markShown = false
end
-- ink rim, a ring in the colour of the leg you are on, an ink gap, a white core
function Trail:DrawMarker(layer, x, y, u, kind)
  local m = self:Marker(layer)
  local s = self.MARK_PX * u
  local ink = self:Color("ink")
  local rc = self:Color(self.STYLE[kind or ""] and kind or "walk", "wm")
  local wc = self:Color("off")
  put(m.ink, layer, x, y, s + 4 * u, ink[1], ink[2], ink[3], 1)
  put(m.ring, layer, x, y, s, rc[1], rc[2], rc[3], 1)
  put(m.gap, layer, x, y, s * 0.6, ink[1], ink[2], ink[3], 1)
  put(m.core, layer, x, y, s * 0.34, wc[1], wc[2], wc[3], 1)
  self.markShown = true
end

-- 0.7.2 (M3): the route's start (a white ring) and finish (a gold bullseye), so both ends read on the map.
Trail.END_PX = 13
function Trail:EndMarks(layer)
  local e = self.ends
  if e and e.layer == layer then return e end
  e = { layer = layer, start = {}, finish = {} }
  for i, key in ipairs({ "ink", "disc", "core" }) do
    local t = layer:CreateTexture(nil, "OVERLAY", nil, 1 + i) t:SetTexture(Skin.TEX.TrailDot) t.panoplyLayoutSkip = true e.start[key] = t
  end
  for i, key in ipairs({ "ink", "disc", "gap", "core" }) do
    local t = layer:CreateTexture(nil, "OVERLAY", nil, 1 + i) t:SetTexture(Skin.TEX.TrailDot) t.panoplyLayoutSkip = true e.finish[key] = t
  end
  self.ends = e
  return e
end
function Trail:HideEnds()
  local e = self.ends
  if not e then return end
  for _, set in ipairs({ e.start, e.finish }) do for _, t in pairs(set) do if t.panoplyOn ~= false then t:Hide() t.panoplyOn = false end end end
  self.endsShown = nil
end
function Trail:EndColors()
  local g = Skin.colors.goldBright or { 1, 0.82, 0.3 }
  return self:Color("ink"), self:Color("off"), g
end
-- which: "start" or "finish"; x, y are TOPLEFT offsets of the layer (y negative)
function Trail:DrawEnd(layer, which, x, y, u)
  local e = self:EndMarks(layer)
  local s = self.END_PX * u
  local ink, white, gold = self:EndColors()
  if which == "start" then
    put(e.start.ink, layer, x, y, s + 4 * u, ink[1], ink[2], ink[3], 1)
    put(e.start.disc, layer, x, y, s, white[1], white[2], white[3], 1)
    put(e.start.core, layer, x, y, s * 0.45, ink[1], ink[2], ink[3], 1)
  else
    put(e.finish.ink, layer, x, y, s + 4 * u, ink[1], ink[2], ink[3], 1)
    put(e.finish.disc, layer, x, y, s, gold[1], gold[2], gold[3], 1)
    put(e.finish.gap, layer, x, y, s * 0.62, ink[1], ink[2], ink[3], 1)
    put(e.finish.core, layer, x, y, s * 0.34, gold[1], gold[2], gold[3], 1)
  end
  self.endsShown = self.endsShown or {}
  self.endsShown[which] = { x = x, y = y }
end

-- (Nov 14 2026, step 22: `wc` is the distance along the walk in yards at each projected point, so the spot the player has reached along
-- the walk is found on the projected line)
local function project(s, rc, kx, ky, step)
  local top, left = rc[2], rc[4]
  local xs, ys, cum, wc = {}, {}, {}, {}
  local n, len = 0, 0
  local sx, sy, sc = s.x, s.y, s.cum
  local np = #sx
  for i = 1, np do
    local x, y = (left - sy[i]) * kx, -(top - sx[i]) * ky
    if n == 0 then
      n = 1 xs[1], ys[1], cum[1], wc[1] = x, y, 0, sc[i]
    else
      local dx, dy = x - xs[n], y - ys[n]
      local d = sqrt(dx * dx + dy * dy)
      if d >= step or i == np then
        if d > 0 then n = n + 1 len = len + d xs[n], ys[n], cum[n], wc[n] = x, y, len, sc[i] end
      end
    end
  end
  return xs, ys, cum, len, wc
end

-- Redraw the world map trail and the route card. Returns the number of walking dots shown.
function Trail:DrawMap()
  local wm, canvas = C.WorldMap(), C.WorldMapCanvas()
  self.keyA, self.keyB = self:MapKey()
  local shown = wm and wm.IsShown and wm:IsShown()
  if not (canvas and shown and self.route and opt("trailWorldMap") and opt("routeEnabled")) then
    if self.mapPen then self.mapPen:Clear() self.antPen:Clear() end
    self:HideMarker()
    self:HideEnds()
    if self.card then self.card:Hide() end
    self.mapDots, self.mapLines, self.mapWalk = 0, 0, nil
    self.dbg = { why = not canvas and "no map canvas" or not shown and "map closed" or not self.route and "no route"
      or not opt("trailWorldMap") and "world map trail is off" or "route planner is off" }
    return 0
  end
  local layer = self:MapLayer(canvas)
  local map = C.WorldMapID()
  local rc = self:MapRect(map)
  local W, H = canvas:GetWidth() or 1000, canvas:GetHeight() or 667
  local sc = self:CanvasScale(canvas)
  local u = 1 / sc                                   -- layer units per screen pixel
  local CZW, CZH = (self.CARD_W + 24) * u, 230 * u   -- the card corners, in layer units
  local bl, brc = 0, 0
  local pen, ants = self.mapPen, self.antPen
  pen:Begin()
  local dbg = { map = map, W = W, H = H, scale = sc, legs = {}, skipped = {}, pieces = {} }
  dbg.pieces.max = 300
  self.dbg = dbg
  for _, x in ipairs(self.noLine or {}) do dbg.skipped[#dbg.skipped + 1] = { leg = x.leg, kind = x.kind, why = x.why } end
  self.mapMode = rc and (self:IsContinentMap(map) and "continent" or "zone") or nil
  self:HideMarker()
  local walks = {}
  if not rc then
    dbg.why = "no map rectangle for map " .. tostring(map)
    for _, s in ipairs(self.segs or {}) do dbg.skipped[#dbg.skipped + 1] = { leg = s.leg, kind = s.kind, why = "this map has no coordinates" } end
  else
    local cont, top, bottom, left, right = rc[1], rc[2], rc[3], rc[4], rc[5]
    local kx, ky = W / (left - right), H / (top - bottom)
    local clip = self.RectClip(0, -H, W, 0)
    local a = alpha("wm")
    local G = scaled(self.MAP, u)
    pen.onPut = function(x, y)
      if -y > H - CZH then if x < CZW then bl = bl + 1 elseif x > W - CZW then brc = brc + 1 end end
    end
    self:Track()                                      -- where the player is on the walk: what is behind him is not drawn (step 22)
    -- the player's own spot counts heavily: the card should not hide where you stand
    local pm, ppx, ppy = C.GetPlayerPos()
    if pm then
      local pc, wx, wy = Panoply.Route:ToWorld(pm, ppx, ppy)
      if pc == cont then pen.onPut((left - wy) * kx, -(top - wx) * ky) for _ = 1, 19 do pen.onPut((left - wy) * kx, -(top - wx) * ky) end end
    end
    for si, s in ipairs(self.segs or {}) do
      local why
      if s.cont ~= cont then why = "on another continent"
      elseif not (s.maxX >= bottom and s.minX <= top and s.maxY >= right and s.minY <= left) then why = "does not cross this map" end
      if why then
        dbg.skipped[#dbg.skipped + 1] = { leg = s.leg, kind = s.kind, why = why }
      else
        local xs, ys, cum, len, wc = project(s, rc, kx, ky, (s.kind == "walk" and 1.2 or G.step))
        local info = { leg = s.leg, kind = s.kind, style = self.STYLE[s.kind].draw, points = #xs, lengthPx = floor(len * sc + 0.5),
          from = { floor(xs[1] * 10 + 0.5) / 10, floor(-ys[1] * 10 + 0.5) / 10 }, to = { floor(xs[#xs] * 10 + 0.5) / 10, floor(-ys[#ys] * 10 + 0.5) / 10 } }
        dbg.legs[#dbg.legs + 1] = info
        if s.kind == "walk" then
          walks[#walks + 1] = { xs = xs, ys = ys, cum = cum, len = len, info = info, wc = wc, si = si, cont = s.cont }
          for k = 1, #xs, 4 do if clip:pt(xs[k], ys[k]) then pen.onPut(xs[k], ys[k]) end end
        else
          local d0, p0 = self:Stroke(pen, xs, ys, cum, s.kind, G, clip, a, nil, dbg.pieces)
          info.dots, info.pieces = d0, p0
          if d0 + p0 == 0 then info.note = "outside the visible part of the map" end
        end
      end
    end
    pen.onPut = nil
    -- the walking part (Look of the map: Size, Spacing, Style): dots widen their spacing when the cap would be hit (0.7.3.7: tiny dots keep
    -- a readable spacing instead of crowding into a line), dashes and the line never draw more pieces than their cap
    local wlen = 0
    for _, w in ipairs(walks) do wlen = wlen + w.len end
    local cap = Panoply.Look.Style("trail", "wm") == "dots" and self.MAP_MAX or self.WALK_PIECES.wm
    self.antG = self:WalkSetup("wm", self.MAP, u, self.MAP_WALK_PX * u, self.MAP_WALK_DOT, wlen, cap, true)
    if self.antG.walk == "solid" then
      for _, w in ipairs(walks) do w.lx, w.ly, w.lcum = thin(w.xs, w.ys, w.cum, #w.xs, self.antG.lstep, {}, {}, {}) end
    end
    self.antClip, self.antAlpha = clip, a
  end
  pen:End()
  self.mapWalk = walks
  self.mapLines = pen.nl
  self:DrawMapAnts(0)
  dbg.dots, dbg.lines, dbg.full = self.mapDots, self.mapLines, (pen.full or ants.full) and true or nil
  -- 0.7.2 (M3): start and finish of the route, on whichever map shows them
  self:HideEnds()
  if rc then
    local r = self.route
    local first = r.legs and r.legs[1]
    local ends = { { "start", first and first.from or r.from }, { "finish", r.to } }
    for _, e in ipairs(ends) do
      local v = e[2]
      if v and v.cont == rc[1] and v.wx and v.wy then
        local x, y = (rc[4] - v.wy) * W / (rc[4] - rc[5]), (rc[2] - v.wx) * H / (rc[2] - rc[3])
        if x >= 0 and x <= W and y >= 0 and y <= H then self:DrawEnd(layer, e[1], x, -y, u) end
      end
    end
    dbg.ends = self.endsShown
  end
  -- the next stop, on whichever map shows it
  if rc then
    local c, wx, wy, _, kind = self:NextStop()
    if c == rc[1] then
      local x, y = (rc[4] - wy) * W / (rc[4] - rc[5]), (rc[2] - wx) * H / (rc[2] - rc[3])
      if x >= 0 and x <= W and y >= 0 and y <= H then self:DrawMarker(layer, x, -y, u, kind) end
    end
  end
  -- the card sits bottom-left unless the trail or the player is there and the right corner is clearer
  self.cardCorner = (bl > brc) and "BOTTOMRIGHT" or "BOTTOMLEFT"
  self:Card(wm)
  return self.mapDots
end

-- The walking dots only (the ant trail moves, so these are re-placed a few times a second while the
-- map is open; nothing else is redrawn and nothing is created).
function Trail:DrawMapAnts(dt)
  local ants = self.antPen
  if not ants then return 0 end
  ants:Begin()
  local P = self.prog
  self.mapSi, self.mapS0 = P and P.si, P and P.s0       -- the spot on the walk this drawing starts at (Trail:Track compares with it)
  local G = self.antG
  if G and self.mapWalk and #self.mapWalk > 0 then
    if opt("trailAnimate") then self.mapDrift = ((self.mapDrift or 0) + (dt or 0) * self.DRIFT) % 1 else self.mapDrift = 0 end
    local phase = (G.period or G.gap) * (0.5 + self.mapDrift)
    for _, w in ipairs(self.mapWalk) do
      local from, past = self:WalkFrom(w)             -- step 22: where on this walk the player is; a walk he has finished is not drawn
      if past then
        w.info.dots, w.info.pieces = 0, 0
      else
        local xs, ys, cum = w.xs, w.ys, w.cum
        if G.walk == "solid" and w.lx then xs, ys, cum = w.lx, w.ly, w.lcum end
        local d, pcs = self:Stroke(ants, xs, ys, cum, "walk", G, self.antClip, self.antAlpha or alpha("wm"), phase, nil, from)
        w.info.dots = d
        if pcs > 0 then w.info.pieces = pcs end
        if d + pcs == 0 and not w.info.note then w.info.note = "outside the visible part of the map" end
      end
    end
  end
  ants:End()
  self.mapDots = ants.nd
  self.mapWalkPieces = ants.nl
  if self.dbg then self.dbg.dots = ants.nd end
  return ants.nd
end

-- Cheap watcher while the map is open: redraw only when the map, its size or its zoom changed; step
-- the ant trail.
function Trail:MapSig()
  local canvas = C.WorldMapCanvas()
  if not canvas then return "" end
  local wm = C.WorldMap()
  local maxi = wm and wm.IsMaximized and wm:IsMaximized()
  return table.concat({ tostring(C.WorldMapID()), floor((canvas:GetWidth() or 0) + 0.5), floor((canvas:GetHeight() or 0) + 0.5),
    floor(self:CanvasScale(canvas) * 1000 + 0.5), tostring(maxi), self.offYd and floor(self.offYd / 10) or -1 }, ":")
end
-- The same thing as two numbers, for the watcher that asks five times a second: nothing is made (the string above is made only when the
-- map did change). Map, width and height in the first; zoom, maximized and the off-trail tens of yards in the second.
function Trail:MapKey()
  local canvas = C.WorldMapCanvas()
  if not canvas then return 0, 0 end
  local wm = C.WorldMap()
  local maxi = (wm and wm.IsMaximized and wm:IsMaximized()) and 1 or 0
  local a = ((tonumber(C.WorldMapID()) or 0) * 4096 + floor((canvas:GetWidth() or 0) + 0.5)) * 4096 + floor((canvas:GetHeight() or 0) + 0.5)
  local b = (floor(self:CanvasScale(canvas) * 1000 + 0.5) * 2 + maxi) * 4096 + (self.offYd and floor(self.offYd / 10) or 4095)
  return a, b
end
function Trail:WatchMap(elapsed)
  self.mapClock = (self.mapClock or 0) + (elapsed or 0)
  self.antClock = (self.antClock or 0) + (elapsed or 0)
  if self.mapClock >= self.MAP_WATCH then
    self.mapClock = 0
    local ka, kb = self:MapKey()
    if C.FloorAllMapAlpha then C.FloorAllMapAlpha() end   -- a fade that did not go through SetAlpha hooks
    if self.mapSig == nil or ka ~= self.keyA or kb ~= self.keyB then
      self.mapSig = self:MapSig()
      self:DrawMap() self:DrawRoadsDebug() self.antClock = 0 return
    end
    -- step 22: the player walked on: the part of the walk behind him goes (the dots are placed again, nothing is made)
    if self:Track() and self.mapWalk and #self.mapWalk > 0 then self:DrawMapAnts(0) end
  end
  if self.antClock >= 1 / self.MAP_ANT_HZ then
    local dt = self.antClock
    self.antClock = 0
    if opt("trailAnimate") and self.mapWalk and #self.mapWalk > 0 and not (self.antG and self.antG.walk == "solid") then self:DrawMapAnts(dt) end
  end
end

-------------------------------------------------------------------------------
-- Route card on the world map (corner): the legs, the total, the legend, the off-trail line
-------------------------------------------------------------------------------
local function dur(s) return Panoply.Route.Duration(s or 0) end
-- a stop's name as the card writes it: the town without its zone; nil when it has none. Never "?" (0.9.4): the route box says
-- "Your route" for an end with no name, and a leg line says "the next stop".
local function placeOrNil(v)
  local n = v and v.name
  if type(n) ~= "string" or not n:find("%S") then return nil end
  return (n:gsub(",.*$", ""):gsub(" %(.*%)$", ""))
end
local function place(v) return placeOrNil(v) or "the next stop" end
-- the row text and the style key of its marker (portals and the hearthstone: "jump", a white dot)
function Trail:LegLine(l)
  if l.kind == "walk" then
    local to = l.backFrom and "the target" or place(l.to)
    return "walk", ("Walk %sto %s%s"):format(l.backFrom and "back " or "", to, l.how == "road" and " by the road" or "")
  elseif l.kind == "fly" then
    -- 0.7.2 (M3): say where you board; a flight over the target says why you walk back
    return "fly", ("Take the flight at %s to %s%s"):format(place(l.from), place(l.to),
      l.overTarget and " (the flight passes over the target; you walk back)" or "")
  elseif l.kind == "ship" or l.kind == "zeppelin" then
    return l.kind, ("Take the %s to %s (wait about %s)"):format(l.kind == "ship" and "boat" or "zeppelin", place(l.to), dur(l.wait))
  elseif l.kind == "tram" then
    return "tram", "Deeprun Tram to " .. place(l.to)
  elseif l.kind == "portal" then
    return "jump", "Portal to " .. place(l.to)
  elseif l.kind == "hearth" then
    return "jump", "Hearthstone to " .. place(l.to)
  end
  return "jump", place(l.to)
end

Trail.STRAIGHT_NOTE = "Walking in straight lines: Follow roads is off (" .. Panoply:SettingsPath("routeRoads") .. ")."
Trail.CARD_W = 300
Trail.CARD_LEGS = 6
Trail.SWATCH_W = 30
Trail.CARD_G = { ink = 1.5, line = 3, dash = 9, gap = 5, zdash = 8, zgap = 3.5, zdot = 4, rail = 1.8, railSep = 4.4, tie = 6, tieW = 1.3, step = 1,
  gap_ants = 10, dot = 5.5 }
function Trail:CardFrame(parent)
  local f = self.card
  if f then return f end
  f = CreateFrame("Frame", "PanoplySuiteRouteCard", parent)
  f:SetSize(self.CARD_W, 120)
  -- 0.6.1: no strata of its own; the map's strata and a frame level above every map pin.
  Skin.Panel(f, 0.94, true, "S")
  f.title = Skin.Heading(f, 14, "")
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetTexture(Skin.WHITE)
  f.rows = {}
  f.total = Skin.Text(f, 12, Skin.colors.goldBright, nil, true)
  f.totalV = Skin.Text(f, 12, Skin.colors.goldBright, nil, true)
  f.off = Skin.Text(f, 11, Skin.colors.trailOff)
  f.note = Skin.Text(f, 11, Skin.colors.inkSoft)   -- 0.7.4: "straight line because Follow roads is off"
  f.legend = {}
  f.swatch = self:NewPen(f, 40, 60, "wm")  -- the legend's samples, drawn by the same stroker as the map (and in the world map's colours)
  self.card = f
  return f
end

local function cardRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = { ring = f:CreateTexture(nil, "ARTWORK"), dot = f:CreateTexture(nil, "OVERLAY"), text = Skin.Text(f, 12, Skin.colors.ink), time = Skin.Text(f, 12, Skin.colors.text) }
  r.dot:SetTexture(Skin.TEX.TrailDot) r.dot.panoplyLayoutSkip = true
  r.ring:SetTexture(Skin.TEX.TrailDot) r.ring.panoplyLayoutSkip = true
  r.time:SetJustifyH("RIGHT")
  f.rows[i] = r
  return r
end
local function legendItem(f, i)
  local L = f.legend[i]
  if L then return L end
  L = { text = Skin.Text(f, 11, Skin.colors.inkSoft) }
  f.legend[i] = L
  return L
end

-- A sample of one style, SWATCH_W wide, centred on y (TOPLEFT offsets of the card).
function Trail:Swatch(pen, kind, x, y)
  local G = {}
  for k, v in pairs(self.CARD_G) do G[k] = v end
  G.gap = kind == "walk" and G.gap_ants or G.gap
  if kind == "walk" then
    -- the sample of walking is drawn in the Style the world map uses (standard size)
    G.walk = self.WALK_DRAW[Panoply.Look.Style("trail", "wm")]
    G.wline, G.wdash, G.wgap = G.line, self.DASH_K * G.line, 3.5
  end
  local w = self.SWATCH_W
  local xs, ys, cum = { x, x + w }, { y, y }, { 0, w }
  return self:Stroke(pen, xs, ys, cum, kind, G, nil, 1, kind == "walk" and 3 or nil)
end

function Trail:Card(wm)
  local r = self.route
  local sc = wm and wm.ScrollContainer
  if not (r and sc) then if self.card then self.card:Hide() end return end
  local f = self:CardFrame(sc)
  local SP = Skin.SP
  local x, inner = 14, self.CARD_W - 28
  local dest = placeOrNil(r.to)
  f.title:SetText(dest and ("Route to " .. dest) or "Your route")
  f.title:SetWidth(inner)
  f.title:ClearAllPoints() f.title:SetPoint("TOPLEFT", f, "TOPLEFT", x, -12)
  local th = Skin.TextHeight(f.title, inner)
  f.title:SetHeight(th)
  local y = -12 - th - SP.xs
  local br = Skin.colors.trailRide
  f.rule:SetVertexColor(br[1], br[2], br[3], 0.55)
  f.rule:ClearAllPoints() f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", x, y) f.rule:SetSize(inner, 1)
  y = y - SP.s
  local legs, n = r.legs or {}, 0
  local ink = self:Color("ink")
  -- 0.9.6.2 launch fix: walks in a row that read the same are one row, a walk under 15 s is not listed (Trip.ShownLegs)
  local shown = Panoply.Trip.ShownLegs(legs, function(l) return select(2, self:LegLine(l)) end)
  for _, s in ipairs(shown) do
    if n >= self.CARD_LEGS then break end
    n = n + 1
    local row = cardRow(f, n)
    local kind, text = self:LegLine(s.leg)
    if n == self.CARD_LEGS and #shown > n then kind, text = "jump", ("%d more steps"):format(#shown - n + 1) end
    row.kind = kind
    row.time:SetText(dur(s.seconds))
    local tw = ceil(Skin.TextWidth(row.time)) + 4
    row.time:SetWidth(tw)
    row.time:ClearAllPoints() row.time:SetPoint("TOPRIGHT", f, "TOPLEFT", x + inner, y)
    local lw = inner - 16 - tw - 8
    row.text:SetText(text) row.text:SetWidth(lw)
    row.text:ClearAllPoints() row.text:SetPoint("TOPLEFT", f, "TOPLEFT", x + 16, y)
    local h = max(Skin.TextHeight(row.text, lw), Skin.TextHeight(row.time))
    row.text:SetHeight(h)
    local cr, cg, cb = col(kind == "jump" and "off" or kind, "wm")
    row.ring:SetVertexColor(ink[1], ink[2], ink[3], 1) row.ring:SetSize(10, 10)
    row.ring:ClearAllPoints() row.ring:SetPoint("CENTER", f, "TOPLEFT", x + 4, y - 8)
    row.dot:SetVertexColor(cr, cg, cb, 1) row.dot:SetSize(7, 7)
    row.dot:ClearAllPoints() row.dot:SetPoint("CENTER", f, "TOPLEFT", x + 4, y - 8)
    row.text:Show() row.time:Show() row.dot:Show() row.ring:Show()
    y = y - h - SP.xs
  end
  for i = n + 1, #f.rows do local row = f.rows[i] row.text:Hide() row.time:Hide() row.dot:Hide() row.ring:Hide() end
  -- total
  f.totalV:SetText(dur(r.total)) f.totalV:SetJustifyH("RIGHT")
  local vw = ceil(Skin.TextWidth(f.totalV)) + 4
  f.totalV:SetWidth(vw)
  f.totalV:ClearAllPoints() f.totalV:SetPoint("TOPRIGHT", f, "TOPLEFT", x + inner, y - 2)
  f.total:SetText("Total trip time") f.total:SetWidth(inner - vw - 8)
  f.total:ClearAllPoints() f.total:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 2)
  y = y - 2 - max(Skin.TextHeight(f.total, inner - vw - 8), Skin.TextHeight(f.totalV)) - SP.s
  -- off the trail
  if self.offYd then
    f.off:SetText(("You are about %d yd off the trail. Head for the white dots; the route updates after %d s."):format(
      floor(self.offYd / 10 + 0.5) * 10, Panoply.Route.OFF_TRAIL_SECONDS))
    f.off:SetWidth(inner)
    f.off:ClearAllPoints() f.off:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    local oh = Skin.TextHeight(f.off, inner)
    f.off:SetHeight(oh) f.off:Show()
    y = y - oh - SP.s
  else
    f.off:Hide()
  end
  -- 0.7.4: with "Follow roads and passes" off every walk is a straight line; say so once, so a trail across open
  -- hills is not mistaken for a wrong road
  local hasWalk = false
  for _, l in ipairs(legs) do if l.kind == "walk" then hasWalk = true break end end
  if hasWalk and not opt("routeRoads") then
    f.note:SetText(self.STRAIGHT_NOTE)
    f.note:SetWidth(inner)
    f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    local nh = Skin.TextHeight(f.note, inner)
    f.note:SetHeight(nh) f.note:Show()
    y = y - nh - SP.s
  else
    f.note:Hide()
  end
  -- legend: one sample per style this route uses, wrapped to the card's width
  local kinds = self:KindsInUse()
  f.legendKinds = kinds
  local pen = f.swatch
  pen:Begin()
  local lx, rowH = x, 18
  local used = 0
  for i, kind in ipairs(kinds) do
    local L = legendItem(f, i)
    L.kind, L.mark = kind, nil
    L.text:SetText(self.STYLE[kind].label)
    local w = ceil(Skin.TextWidth(L.text)) + 2
    L.text:SetWidth(w)
    local need = self.SWATCH_W + 6 + w
    if lx > x and lx + need > x + inner then lx = x y = y - rowH end
    L.d, L.p = self:Swatch(pen, kind, lx + 1, y - 8)
    L.x, L.y = lx, y
    L.text:ClearAllPoints() L.text:SetPoint("TOPLEFT", f, "TOPLEFT", lx + self.SWATCH_W + 6, y - 1)
    L.text:Show()
    lx = lx + need + 14
    used = i
  end
  -- 0.7.2 (M3): the two end marks
  local ink, white, gold = self:EndColors()
  for _, which in ipairs({ "start", "finish" }) do
    used = used + 1
    local L = legendItem(f, used)
    L.kind, L.mark = nil, which   -- not a line style: kept apart from L.kind (one item per style)
    L.text:SetText(which)
    local w = ceil(Skin.TextWidth(L.text)) + 2
    L.text:SetWidth(w)
    local need = 14 + 6 + w
    if lx > x and lx + need > x + inner then lx = x y = y - rowH end
    if which == "start" then
      pen:Dot(lx + 7, y - 8, 9, white, 1, 1.5) pen:Dot(lx + 7, y - 8, 4, ink, 1, 0)
    else
      pen:Dot(lx + 7, y - 8, 9, gold, 1, 1.5) pen:Dot(lx + 7, y - 8, 5.5, ink, 1, 0) pen:Dot(lx + 7, y - 8, 3, gold, 1, 0)
    end
    L.x, L.y = lx, y
    L.text:ClearAllPoints() L.text:SetPoint("TOPLEFT", f, "TOPLEFT", lx + 14 + 6, y - 1)
    L.text:Show()
    lx = lx + need + 14
  end
  for i = used + 1, #f.legend do f.legend[i].text:Hide() f.legend[i].kind, f.legend[i].mark = nil, nil end
  pen:End()
  if used > 0 then y = y - rowH end
  f:SetHeight(-y + SP.m)
  f:ClearAllPoints()
  local corner = self.cardCorner or "BOTTOMLEFT"
  f:SetPoint(corner, sc, corner, corner == "BOTTOMLEFT" and 12 or -12, 12)
  C.LiftOnWorldMap(f, "card")
  f:Show()
end

-------------------------------------------------------------------------------
-- Minimap
-------------------------------------------------------------------------------
function Trail:MiniLayer()
  if not self.miniLayer then
    local mm = _G.Minimap
    if not mm then return nil end
    self.miniLayer = CreateFrame("Frame", nil, mm)
    self.miniLayer:SetAllPoints(mm)
    self.miniLayer.panoplyLayoutSkip = true
    if self.miniLayer.SetFrameLevel and mm.GetFrameLevel then self.miniLayer:SetFrameLevel((mm:GetFrameLevel() or 1) + 4) end
    self.miniAnts = self:NewPen(self.miniLayer, self.MINI_MAX, 0, "mm")
    self.miniPen = self:NewPen(self.miniLayer, 12, self.MINI_LINE_MAX, "mm")
    self.miniPool, self.miniLinePool = self.miniAnts.dots, self.miniPen.lines
  end
  return self.miniLayer
end

Trail.BEND_STEP_YD = 20        -- 0.7.3.1: road pieces near the player are cut this short so the bend is smooth

-- The player against the walking lines on this continent: distance to the nearest one (yd), that walk
-- segment, the nearest point on it and how far along the walk it lies (yd). Nil without a walk here.
-- (The whole route is searched. DrawMinimap uses Trail:Locate below, which looks only just ahead of the player's last spot.)
function Trail:Anchor(cont, px, py)
  local best, bs, bx, by, bc
  for _, s in ipairs(self.segs or {}) do
    if s.kind == "walk" and s.cont == cont then
      local xs, ys, cs = s.x, s.y, s.cum
      for i = 1, #xs - 1 do
        local ax, ay = xs[i], ys[i]
        local dx, dy = xs[i + 1] - ax, ys[i + 1] - ay
        local L = dx * dx + dy * dy
        local t = L > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L)) or 0
        local qx, qy = ax + t * dx, ay + t * dy
        local d = (px - qx) * (px - qx) + (py - qy) * (py - qy)
        if not best or d < best then best, bs, bx, by, bc = d, s, qx, qy, cs[i] + t * (cs[i + 1] - cs[i]) end
      end
    end
  end
  if not best then return nil end
  return sqrt(best), bs, bx, by, bc
end

-------------------------------------------------------------------------------
-- Where the player is on the walk (Nov 14 2026, 0.9.4 step 22: "Dots behind the player must disappear as they pass them")
-------------------------------------------------------------------------------
-- Why they stayed: the route is made once from where the player stood, and the trail drew all of it until the next plan. Our own planner
-- plans again only for a new step or after being off the walk for five seconds; the walk PanoplyGuide gives is the whole path from where its
-- search began and changes only when it searches again (more than 25 yd off). Nothing ever cut the part already walked.
-- Now each update finds the player's place on the walk and the trail starts there: self.prog = { segs, cont, si (which of the trail's pieces),
-- s0 (yards along it: only grows while he follows it), e (the edge of the piece s0 is on), d, seg, nx, ny, along (the nearest point of the
-- walk, as found now), valid }. A new route (a new self.segs) or another continent starts the search again from nothing.
local function edgeD2(xs, ys, i, px, py)
  local ax, ay = xs[i], ys[i]
  local dx, dy = xs[i + 1] - ax, ys[i + 1] - ay
  local L = dx * dx + dy * dy
  local t = 0
  if L > 0 then
    t = ((px - ax) * dx + (py - ay) * dy) / L
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local qx, qy = ax + t * dx, ay + t * dy
  return (px - qx) * (px - qx) + (py - qy) * (py - qy), t
end

local function nextWalk(segs, si, cont)
  for j = si + 1, #segs do
    local s = segs[j]
    if s.kind == "walk" and s.cont == cont then return j end
  end
  return nil
end

-- Nearest edge to (px, py) in segment si from edge e0 until the walk is `limit` yd along; the best so far is passed in and comes back.
local bd2, bsi, be, bt
local scanned, fullSearches = 0, 0      -- how many edges were looked at, and how many searches of the whole route were made (the tests read them)
function Trail.Scanned() return scanned, fullSearches end
local function scanWalk(segs, si, e0, limit, px, py)
  local s = segs[si]
  local xs, ys, cs = s.x, s.y, s.cum
  local n = #xs
  local i = e0
  while i <= n - 1 and cs[i] <= limit do
    local d2, t = edgeD2(xs, ys, i, px, py)
    scanned = scanned + 1
    if not bd2 or d2 < bd2 - 1e-9 then bd2, bsi, be, bt = d2, si, i, t end
    i = i + 1
  end
  return i > n - 1
end

-- cont, px, py: where the player is in world yards. Returns what Anchor returned (d, seg, nx, ny, along): the distance to the walk, the piece,
-- the nearest point on it and its distance along it. d is the distance to the walk just ahead of where he was while he is on it; once he is
-- further from it than Route.OFF_TRAIL_YD, the whole route is searched, so the way back to it is shown (the off-trail cue).
function Trail:Locate(cont, px, py)
  local segs = self.segs
  local P = self.prog
  if not P then P = {} self.prog = P end
  if P.segs ~= segs or P.cont ~= cont then
    P.segs, P.cont, P.si, P.e, P.s0, P.valid, P.on = segs, cont, nil, nil, nil, false, false
  end
  if not segs or #segs == 0 then return nil end
  if P.valid and P.px == px and P.py == py then return P.d, P.seg, P.nx, P.ny, P.along end
  P.px, P.py = px, py
  local R = Panoply.Route
  local lock = (R and R.OFF_TRAIL_YD) or 60
  local lock2 = lock * lock
  local found = false
  -- 1. just ahead of the last known spot: this walk from a little behind it, and the next walk when this one ends inside the window.
  -- Walking back (17-22 review, backlog 8): when the nearest point in the window is behind the spot by more than a stutter, the spot moves
  -- there and the window is looked at again from it, so each look reaches TRIM_BACK_YD further back: he is followed to where he stands in
  -- this one call, and a player who stands still does not leave a gap (Locate answers from its cache until he moves). BACK_LOOKS bounds it.
  local looks = 0
  while true do
    found = false
    bd2, bsi, be, bt = nil, nil, nil, nil
    if P.si and segs[P.si] then
      local si, s0 = P.si, P.s0
      local cs = segs[si].cum
      local e = P.e
      local from = s0 - self.TRIM_BACK_YD
      while e > 1 and cs[e] > from do e = e - 1 end
      if scanWalk(segs, si, e, s0 + self.TRIM_AHEAD_YD, px, py) then
        local sj = nextWalk(segs, si, cont)
        if sj then scanWalk(segs, sj, 1, self.TRIM_AHEAD_YD, px, py) end
      end
      if bd2 and bd2 <= lock2 then found = true end
    end
    if not (found and bsi == P.si and looks < self.BACK_LOOKS) then break end
    local sb = segs[bsi].cum
    local back = sb[be] + bt * (sb[be + 1] - sb[be])
    if P.s0 - back <= self.STUTTER_BACK_YD then break end
    P.s0, P.e = back, be
    looks = looks + 1
  end
  -- 2. not there: the whole route (a new route, a long jump, a way back to a part he had left behind, or off the walk altogether)
  local viaWindow = found
  if not found then
    fullSearches = fullSearches + 1
    bd2, bsi, be, bt = nil, nil, nil, nil
    for si = 1, #segs do
      local s = segs[si]
      if s.kind == "walk" and s.cont == cont then scanWalk(segs, si, 1, 1e12, px, py) end
    end
    if bd2 and bd2 <= lock2 then found = true end
  end
  if not bd2 then P.valid, P.on = false, false return nil end
  local s = segs[bsi]
  local cs = s.cum
  local along = cs[be] + bt * (cs[be + 1] - cs[be])
  P.d, P.seg, P.along = sqrt(bd2), s, along
  P.nx = s.x[be] + (s.x[be + 1] - s.x[be]) * bt
  P.ny = s.y[be] + (s.y[be + 1] - s.y[be]) * bt
  P.on, P.valid = found, true
  if found then
    if viaWindow and bsi == P.si and along < P.s0 then
      -- behind the last spot: a stutter changes nothing; a real step back along the walk moves the start back with him. The nearest point is
      -- only looked for in the window (TRIM_BACK_YD behind the spot), so what lies further back, across a loop, is never taken.
      if P.s0 - along > self.STUTTER_BACK_YD then P.s0, P.e = along, be end
    else
      P.si, P.s0, P.e = bsi, along, be
    end
  end
  return P.d, P.seg, P.nx, P.ny, P.along
end

-- The world position of the player in the world yards of the route: the map's own corners (cached, nothing is asked of the game that makes
-- a table), else the route's own conversion. cont, wx, wy, or nil.
function Trail:PlayerWorld()
  local pm, ppx, ppy = C.GetPlayerPos()
  if not pm then return nil end
  local rc = self:MapRect(pm)
  if rc then return rc[1], rc[2] - ppy * (rc[2] - rc[3]), rc[4] - ppx * (rc[4] - rc[5]) end
  return Panoply.Route:ToWorld(pm, ppx, ppy)
end

-- Follow the player along the walk (for the world map, which has no update of its own): true when the spot the trail starts at moved.
function Trail:Track()
  if not self.route or C.OnTaxi() then return false end
  local cont, px, py = self:PlayerWorld()
  if not cont then return false end
  self:Locate(cont, px, py)
  local P = self.prog
  -- moved since the world map last drew the walk (the minimap's update may have followed him first)
  return P.si ~= self.mapSi or math.abs((P.s0 or 0) - (self.mapS0 or 0)) > 0.25
end

-- Where on a projected walk of the world map (a self.mapWalk entry) the trail starts: the distance along the projected line, or nil for all
-- of it; past = the player has finished this walk (a later one of the route is the one he is on).
function Trail:WalkFrom(w)
  local P = self.prog
  if not (P and P.valid and P.si and P.cont == w.cont and P.segs == self.segs) then return nil, false end
  if w.si < P.si then return nil, true end
  if w.si > P.si then return nil, false end
  local wc, cum = w.wc, w.cum
  local n = #cum
  if n < 2 then return nil, false end
  local s0 = P.s0
  local k = w.k or 1
  if k > n - 1 or wc[k] > s0 then k = 1 end
  while k < n - 1 and wc[k + 1] <= s0 do k = k + 1 end
  w.k = k
  local L = wc[k + 1] - wc[k]
  local t = L > 0 and (s0 - wc[k]) / L or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return cum[k] + (cum[k + 1] - cum[k]) * t, false
end

-- 0.7.3.1: walk segment s bent through the player (Route.NudgeWeight): a copy whose points near the player
-- move by the player's offset (ox, oy) from the nearest point, which sits s0 yd along and is a point of its
-- own, so the line runs through the player. cum keeps the distance along the unbent walk, so the dots stay
-- put on the ground. Nil when nothing moves.
-- (Step 22: the copy is one table the trail keeps and fills again, and its points go in order without a list to sort: nothing is made.)
local bW, bD, bS0, bLen, bOx, bOy, bB, bN
local function bendPut(x, y, c)
  local w = bW(bD, c, bS0, bLen)
  x, y = x + w * bOx, y + w * bOy
  bN = bN + 1
  bB.x[bN], bB.y[bN], bB.cum[bN] = x, y, c
  bB.minX, bB.maxX = min(bB.minX or x, x), max(bB.maxX or x, x)
  bB.minY, bB.maxY = min(bB.minY or y, y), max(bB.maxY or y, y)
end
function Trail:Bend(s, d, s0, ox, oy)
  local R = Panoply.Route
  local len, reach, step = s.len, R.NUDGE_REACH_YD, self.BEND_STEP_YD
  if R.NudgeWeight(d, s0, s0, len) <= 0 then return nil end
  local b = self.bendSeg
  if not b then b = { x = {}, y = {}, cum = {} } self.bendSeg = b end
  b.src, b.cont, b.kind, b.leg, b.len = s, s.cont, s.kind, s.leg, len
  b.minX, b.maxX, b.minY, b.maxY = nil, nil, nil, nil
  bW, bD, bS0, bLen, bOx, bOy, bB, bN = R.NudgeWeight, d, s0, len, ox, oy, b, 0
  local xs, ys, cs = s.x, s.y, s.cum
  local np = #xs
  for i = 1, np do
    bendPut(xs[i], ys[i], cs[i])
    if i < np then
      local c0, c1 = cs[i], cs[i + 1]
      local L = c1 - c0
      if L > 0 and c1 > s0 - reach and c0 < s0 + reach then
        local k = max(1, ceil(L / step))
        local sPending = s0 > c0 and s0 < c1
        local last = c0
        for j = 1, k - 1 do
          local c = c0 + L * j / k
          if sPending and s0 <= c then
            if s0 - last > 0.01 then
              local t = (s0 - c0) / L
              bendPut(xs[i] + (xs[i + 1] - xs[i]) * t, ys[i] + (ys[i + 1] - ys[i]) * t, s0)
              last = s0
            end
            sPending = false
          end
          if c - last > 0.01 then
            local t = (c - c0) / L
            bendPut(xs[i] + (xs[i + 1] - xs[i]) * t, ys[i] + (ys[i + 1] - ys[i]) * t, c)
            last = c
          end
        end
        if sPending and s0 - last > 0.01 then
          local t = (s0 - c0) / L
          bendPut(xs[i] + (xs[i + 1] - xs[i]) * t, ys[i] + (ys[i + 1] - ys[i]) * t, s0)
        end
      end
    end
  end
  local bx, by, bc = b.x, b.y, b.cum
  for j = #bx, bN + 1, -1 do bx[j], by[j], bc[j] = nil, nil, nil end
  return b
end

-- One minimap update (called 10 times a second by the driver). Returns the number of dots shown.
-- Step 2 D: the walking part has its own Style, Size, Spacing and Colour on the minimap. The route is first cut into runs inside the
-- minimap's square (pass 1), so the walking length is known and Spacing can never ask for more dots or pieces than the caps allow
-- (pass 2 strokes them). The runs are pooled: nothing is allocated once they have grown to the size the route needs.
-- Step 22 (Nov 14 2026): the walk starts where the player is on it (Trail:Locate): the walks he has finished and the part of this one behind
-- him are not cut into runs, so they are not drawn. Nothing in this update makes a table or a closure: the scratch lists, the geometry tables and
-- the two clips are kept and filled again (tests/routedots_tests.lua counts the memory of 400 updates).
local mPx, mPy, mCa, mSa, mK, mRpx = 0, 0, 1, 0, 1, 70
local mXs, mYs, mCum = {}, {}, {}
local mRuns, mNr, mWalkLen
local function toLayerX(wx, wy)
  local ex, ny = (mPy - wy), (wx - mPx)
  return mRpx + (ex * mCa + ny * mSa) * mK
end
local function toLayerY(wx, wy)
  local ex, ny = (mPy - wy), (wx - mPx)
  return -(mRpx - (-ex * mSa + ny * mCa) * mK)
end
local function keepRun(kind, n)
  mNr = mNr + 1
  local r = mRuns[mNr]
  if not r then r = { xs = {}, ys = {}, cum = {}, lx = {}, ly = {}, lc = {} } mRuns[mNr] = r end
  local rx, ry, rc = r.xs, r.ys, r.cum
  for j = 1, n do rx[j], ry[j], rc[j] = mXs[j], mYs[j], mCum[j] end
  for j = #rx, n + 1, -1 do rx[j], ry[j], rc[j] = nil, nil, nil end
  r.kind, r.n = kind, n
  if kind == "walk" then mWalkLen = mWalkLen + (mCum[n] - mCum[1]) end
end

function Trail:DrawMinimap(dt)
  local layer = self:MiniLayer()
  if not layer then return 0 end
  local ants, pen = self.miniAnts, self.miniPen
  if not (self.route and opt("trailMinimap") and opt("routeEnabled")) or (C.InInstance and C.InInstance()) then
    ants:Clear() pen:Clear() self.miniDots, self.miniLines = 0, 0 self.offYd = nil
    return 0
  end
  local Route = Panoply.Route
  local cont, px, py = self:PlayerWorld()
  if not cont then ants:Clear() pen:Clear() self.miniDots, self.miniLines = 0, 0 return 0 end
  local R = C.MinimapRadius()
  local mm = _G.Minimap
  local rpx = ((mm.GetWidth and mm:GetWidth()) or 140) / 2
  local k = rpx / R
  local ca, sa = 1, 0
  if C.MinimapRotates() then
    local f = C.Facing() or 0
    ca, sa = cos(f), sin(f)
  end
  mPx, mPy, mCa, mSa, mK, mRpx = px, py, ca, sa, k, rpx
  if opt("trailAnimate") then self.drift = ((self.drift or 0) + (dt or 0) * self.DRIFT) % 1 else self.drift = 0 end
  local a = alpha("mm")
  ants:Begin() pen:Begin()
  -- where the player stands against the walk (every update, so the bend keeps up with the player): far
  -- off it, the off-trail cue; near it, the walk bends through the player (0.7.3.1, Route.NudgeWeight)
  local d, ns, nx, ny, s0 = self:Locate(cont, px, py)
  local taxi = C.OnTaxi()
  if d and d > Route.OFF_TRAIL_YD and not taxi then self.offYd, self.offX, self.offY = d, nx, ny else self.offYd = nil end
  self.bend = (d and not taxi and d > 0.01) and self:Bend(ns, d, s0, px - nx, py - ny) or nil
  local bend = self.bend
  local P = self.prog
  local tsi = (P and P.valid and P.si and P.segs == self.segs and P.cont == cont) and P.si or nil
  local cueN = self.offYd and self.CUE_MAX or 0
  ants.maxD = self.MINI_MAX - cueN
  local ds = size("mm")
  local style = Panoply.Look.Style("trail", "mm")
  ants.maxL = style == "dots" and 0 or self.WALK_PIECES.mm
  local baseGap = 2 * rpx / self.MINI_WALK_STEPS
  -- the legs that are not walking keep the geometry they have always had (their dashes use this gap too)
  local G = scaledInto(self.gMini or {}, self.MINI, 1)
  self.gMini = G
  G.gap, G.dot = baseGap * max(ds, Trail.GAP_MIN), self.MINI_WALK_DOT * ds
  -- pass 1: runs of consecutive pieces whose box meets the minimap square; cum keeps the world distance (times k) so dashes and dots
  -- stay put on the ground as you move
  local runs = self.runs
  if not runs then runs = {} self.runs = runs end
  mRuns, mNr, mWalkLen = runs, 0, 0
  local xs, ys, cum = mXs, mYs, mCum
  local segs = self.segs
  for si = 1, segs and #segs or 0 do
    local s = segs[si]
    local passed, trimmed = false, false
    if tsi and s.kind == "walk" and s.cont == cont then
      if si < tsi then passed = true elseif si == tsi then trimmed = true end
    end
    if not passed then
      if bend and bend.src == s then s = bend end
      if s.cont == cont and s.maxX >= px - R and s.minX <= px + R and s.maxY >= py - R and s.minY <= py + R then
        local sx, sy, sc = s.x, s.y, s.cum
        local np = #sx
        local n = 0
        local i = 1
        local ax0, ay0, ac0
        if trimmed then
          -- the walk starts at the spot the player has reached on it, which lies on the edge i
          local st = P.s0
          while i < np - 1 and sc[i + 1] <= st do i = i + 1 end
          local L = sc[i + 1] - sc[i]
          local t = L > 0 and (st - sc[i]) / L or 0
          if t < 0 then t = 0 elseif t > 1 then t = 1 end
          ax0, ay0, ac0 = sx[i] + (sx[i + 1] - sx[i]) * t, sy[i] + (sy[i + 1] - sy[i]) * t, st
        end
        local first = i
        while i <= np - 1 do
          local ax, ay, bx, by, ac = sx[i], sy[i], sx[i + 1], sy[i + 1], sc[i]
          if trimmed and i == first then ax, ay, ac = ax0, ay0, ac0 end
          local hit = max(ax, bx) >= px - R and min(ax, bx) <= px + R and max(ay, by) >= py - R and min(ay, by) <= py + R
          if hit then
            if n == 0 then
              n = 1
              xs[1], ys[1] = toLayerX(ax, ay), toLayerY(ax, ay) cum[1] = ac * k
            end
            n = n + 1
            xs[n], ys[n] = toLayerX(bx, by), toLayerY(bx, by) cum[n] = sc[i + 1] * k
          end
          if (not hit or i == np - 1) and n >= 2 then keepRun(s.kind, n) n = 0
          elseif not hit then n = 0 end
          i = i + 1
        end
      end
    end
  end
  local nr, walkLen = mNr, mWalkLen
  -- the walking part: its geometry, from the minimap's Size, Spacing and Style
  local W = self:WalkSetup("mm", self.MINI, 1, baseGap, self.MINI_WALK_DOT, walkLen, style == "dots" and ants.maxD or self.WALK_PIECES.mm, false, self.wMini or {})
  self.wMini = W
  local phase = (W.period or W.gap) * (0.5 + self.drift)
  -- line pieces are cut short enough that their dark outline (and the tram's rail bed) stays inside
  -- the minimap circle: the minimap does not clip what add-ons draw on it
  -- (cut point + the cap extension + half the outlined width, for the widest style: the rail bed)
  local clip = self.SetCircle(self.clipMini or self.CircleClip(0, 0, 1), rpx, -rpx, rpx - max(G.line + 2 * G.ink, (G.railSep + G.rail) / 2 + 2 * G.ink) - 0.5)
  self.clipMini = clip
  local walkClip = self.SetCircle(self.clipMiniWalk or self.CircleClip(0, 0, 1), rpx, -rpx, style == "dots" and rpx or (rpx - (W.wline + 2 * W.ink) - 0.5))
  self.clipMiniWalk = walkClip
  -- pass 2
  for i = 1, nr do
    local r = runs[i]
    if r.kind == "walk" then
      if W.walk == "solid" then
        local lx, ly, lc = thin(r.xs, r.ys, r.cum, r.n, W.lstep, r.lx, r.ly, r.lc)
        self:Stroke(ants, lx, ly, lc, "walk", W, walkClip, a, phase)
      else
        self:Stroke(ants, r.xs, r.ys, r.cum, "walk", W, walkClip, a, phase)
      end
    else
      self:Stroke(pen, r.xs, r.ys, r.cum, r.kind, G, clip, a)
    end
  end
  -- the off-trail cue: white dots from the player towards the nearest point of the trail
  ants.maxD = self.MINI_MAX
  if self.offYd and self.offX then
    local ex, ny = (py - self.offY), (self.offX - px)
    local dist = sqrt(ex * ex + ny * ny)
    if dist > 0 then
      local ux, uy = ex / dist, ny / dist
      local reach = min(dist, R)
      local gap = reach / (self.CUE_MAX + 1)
      local c = self:Color("off")
      local od = self.MINI_OFF_DOT * ds
      local lim = rpx - od / 2 - 2
      for j = 1, self.CUE_MAX do
        local dd = gap * j
        local qx, qy = ux * dd, uy * dd
        local sx, sy = (qx * ca + qy * sa) * k, (-qx * sa + qy * ca) * k
        if sx * sx + sy * sy <= lim * lim then
          ants:Dot(rpx + sx, -(rpx - sy), od, c, a * 0.95, self.MINI.ink, "off")
        end
      end
    end
  end
  ants:End() pen:End()
  self.miniDots, self.miniLines = ants.nd, pen.nl
  self.miniWalkPieces = ants.nl
  return ants.nd + pen.nl
end

-------------------------------------------------------------------------------
-- Drivers: one hidden frame, shown only while there is something to draw
-------------------------------------------------------------------------------
function Trail:Driver()
  if self.driver then return self.driver end
  local f = CreateFrame("Frame")
  f:Hide()
  f:SetScript("OnUpdate", function(_, elapsed) Trail:OnUpdate(elapsed) end)
  self.driver = f
  return f
end

Trail.slices = {}
function Trail:OnUpdate(elapsed)
  local clock = Panoply.Route.clock
  self.miniClock = (self.miniClock or 0) + (elapsed or 0)
  if self.miniClock >= 1 / self.MINI_HZ then
    local t0 = clock()
    local dt = self.miniClock
    self.miniClock = 0
    self:DrawMinimap(dt)
    local ms = clock() - t0
    self.lastMs = ms
    if ms > (self.worstMs or 0) then self.worstMs = ms end
  end
  local wm = C.WorldMap()
  if wm and wm.IsShown and wm:IsShown() then self:WatchMap(elapsed) end
end

function Trail:UpdateDrivers()
  local want = (self.route and opt("routeEnabled") and (opt("trailMinimap") or opt("trailWorldMap"))) or self.roadsDebug
  local d = self:Driver()
  if want then d:Show() else
    d:Hide()
    if self.miniAnts then self.miniAnts:Clear() self.miniPen:Clear() end
    self.miniDots, self.miniLines, self.offYd = 0, 0, nil
  end
end

-------------------------------------------------------------------------------
-- 0.7.4 (roads): the road overlay of /panoply mapdebug. Draws OUR road points and links over the open world map
-- (skin v3, no glow) with their ids, so a screenshot can be held against the real roads in the map art.
-- Drawing only: the router does not read it, nothing is saved, /panoply mapdebug off (or a reload) removes it.
-------------------------------------------------------------------------------
Trail.ROADS_DEBUG = { maxDots = 900, maxLines = 900, maxLabels = 160, dot = 6, line = 2.4, ink = 1.4, font = 11 }
local function hexc(h) return { Skin.hex(h) } end
Trail.ROAD_COLORS = { road = hexc("#ffb000"), bridge = hexc("#f5f5f5"), other = hexc("#c9a7ff"), zone = hexc("#ff9cef"),
  nogo = hexc("#8aa0b8"), here = hexc("#f5f5f5"), away = hexc("#a87a1a") }

function Trail:RoadsLayer(canvas)
  local L = self.roadLayer
  if not L then
    L = CreateFrame("Frame", nil, canvas)
    L:SetAllPoints(canvas)
    L.panoplyLayoutSkip = true
    self.roadLayer = L
    local D = self.ROADS_DEBUG
    self.roadPen = self:NewPen(L, D.maxDots, D.maxLines)
    self.roadLabels = {}
  end
  if L.GetParent and L:GetParent() ~= canvas and L.SetParent then L:SetParent(canvas) L:ClearAllPoints() L:SetAllPoints(canvas) end
  local lvl = C.LiftOnWorldMap(L, "trail")
  if lvl and L.SetFrameLevel then pcall(L.SetFrameLevel, L, lvl + 1) end   -- just above the trail, under our pins
  if not L:IsShown() then L:Show() end
  return L
end

function Trail:HideRoadsDebug()
  if self.roadPen then self.roadPen:Clear() end
  for _, fs in ipairs(self.roadLabels or {}) do fs:Hide() end
  if self.roadLayer then self.roadLayer:Hide() end
end

local function pointsOnWorld(rc, W, H)
  local top, bottom, left, right = rc[2], rc[3], rc[4], rc[5]
  return function(wx, wy) return (left - wy) * W / (left - right), -((top - wx) * H / (top - bottom)) end
end

-- Returns a summary table (also kept in self.roadsInfo for the chat line and the tests).
function Trail:DrawRoadsDebug()
  local wm, canvas = C.WorldMap(), C.WorldMapCanvas()
  local shown = wm and wm.IsShown and wm:IsShown()
  self.roadsInfo = nil
  if not (self.roadsDebug and canvas and shown) then self:HideRoadsDebug() return nil end
  local map = C.WorldMapID()
  local rc = self:MapRect(map)
  local Rd = Panoply.Roads
  local data = Rd and Rd.Data and Rd:Data()
  local layer = self:RoadsLayer(canvas)
  local pen, D, K = self.roadPen, self.ROADS_DEBUG, self.ROAD_COLORS
  local info = { map = map, nodes = 0, links = 0, nogo = 0, labels = 0 }
  self.roadsInfo = info
  pen:Begin()
  local nl = 0
  local function finish()
    pen:End()
    for i = nl + 1, #self.roadLabels do self.roadLabels[i]:Hide() end
    info.labels = nl
    info.capped = pen.full and true or nil
    return info
  end
  if not rc then info.why = "no map rectangle for map " .. tostring(map) return finish() end
  if not data then info.why = "no road data (PanoplySuite_RouteData not loaded)" return finish() end
  local c = data[rc[1]]
  if not c then info.why = "no road points on this continent" return finish() end
  local W, H = canvas:GetWidth() or 1000, canvas:GetHeight() or 667
  local u = 1 / self:CanvasScale(canvas)
  local at = pointsOnWorld(rc, W, H)
  local want = Rd:Layer(map)                          -- Undercity has its own layer; everywhere else nil
  local pos = {}
  for i = 1, c.n do
    if c.layer[i] == want then
      local x, y = at(c.X[i], c.Y[i])
      if x >= 0 and x <= W and -y >= 0 and -y <= H then pos[i] = { x, y } end
    end
  end
  -- no-go areas: thin outlines
  for _, P in ipairs(c.polys) do
    if P.layer == want and #P.xs >= 3 then
      local any = false
      for k = 1, #P.xs do local x, y = at(P.xs[k], P.ys[k]) if x >= 0 and x <= W and -y >= 0 and -y <= H then any = true break end end
      if any then
        info.nogo = info.nogo + 1
        for k = 1, #P.xs do
          local k2 = k % #P.xs + 1
          local x1, y1 = at(P.xs[k], P.ys[k])
          local x2, y2 = at(P.xs[k2], P.ys[k2])
          if self.RectClip(0, -H, W, 0):pt(x1, y1) or self.RectClip(0, -H, W, 0):pt(x2, y2) then pen:Line(x1, y1, x2, y2, 1.2 * u, K.nogo, 0.8, 0, "nogo") end
        end
      end
    end
  end
  -- links (both ends on this map), then points
  local zoneNode = {}
  for i, p in pairs(pos) do
    local adj = c.adj[i]
    for j = 1, #adj - 2, 3 do
      local b, kind = adj[j], adj[j + 2]
      if kind == 8 then zoneNode[i] = true zoneNode[b] = true end
      local q = pos[b]
      if q and b > i then
        local col = (kind == 1) and K.road or ((kind == 3) and K.bridge or ((kind == 8) and K.zone or K.other))
        if pen:Line(p[1], p[2], q[1], q[2], D.line * u, col, 0.95, D.ink * u, "road") then info.links = info.links + 1 end
      end
    end
  end
  local prefix = tostring(map) .. ":"
  local order = {}
  for i in pairs(pos) do order[#order + 1] = i end
  table.sort(order)
  for _, i in ipairs(order) do
    local p = pos[i]
    local id = c.id[i] or "?"
    local here = id:sub(1, #prefix) == prefix
    local col = zoneNode[i] and K.zone or (here and K.here or K.away)
    if pen:Dot(p[1], p[2], D.dot * u, col, 1, D.ink * u, "roadpoint") then info.nodes = info.nodes + 1 end
    if nl < D.maxLabels then
      nl = nl + 1
      local fs = self.roadLabels[nl]
      if not fs then fs = Skin.Text(layer, D.font, Skin.colors.text) fs:SetJustifyH("LEFT") if fs.SetWordWrap then fs:SetWordWrap(false) end fs.panoplyLayoutSkip = true self.roadLabels[nl] = fs end
      Skin.Font(fs, D.font * u, here and Skin.colors.text or Skin.colors.inkSoft)
      fs:SetText(here and id:sub(#prefix + 1) or id)
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", layer, "TOPLEFT", p[1] + (D.dot * 0.5 + 3) * u, p[2])
      fs:Show()
    end
  end
  return finish()
end

function Trail:SetRoadsDebug(on)
  self.roadsDebug = on and true or false
  self:UpdateDrivers()
  return self:DrawRoadsDebug()
end

function Trail:RoadsDebugLine(info)
  if not self.roadsDebug then return "mapdebug roads: off." end
  if not info then return "mapdebug roads: on. Open the world map (M) to see our road points." end
  if info.why then return "mapdebug roads: " .. info.why .. "." end
  return ("mapdebug roads: map %s, %d road points, %d links, %d no-go outlines drawn%s. Amber = roads, white = this zone's points, pink = zone lines, grey-blue = no-go areas. /panoply mapdebug off removes it."):format(
    tostring(info.map), info.nodes, info.links, info.nogo, info.capped and " (capped)" or "")
end

-------------------------------------------------------------------------------
-- /panoply mapdebug: a snapshot of what the trail drew on the open world map, saved in PanoplySuiteDB
-- (SavedVariables, written at /reload or logout) and summed up in one chat line.
-------------------------------------------------------------------------------
local function num(v, p) v = tonumber(v) if not v then return nil end local m = 10 ^ (p or 1) return floor(v * m + 0.5) / m end
local function safe(o, m, ...) if not (o and o[m]) then return nil end local ok, a, b = pcall(o[m], o, ...) if ok then return a, b end return nil end
local function effAlpha(f)
  if f and f.GetEffectiveAlpha then return num(safe(f, "GetEffectiveAlpha"), 2) end
  local a = 1
  while f do a = a * (tonumber(safe(f, "GetAlpha")) or 1) f = safe(f, "GetParent") end
  return num(a, 2)
end
function Trail:MapDebug()
  local wm, canvas = C.WorldMap(), C.WorldMapCanvas()
  local open = wm and safe(wm, "IsShown") and true or false
  if open then self.mapSig = nil self:DrawMap() end
  local map = C.WorldMapID()
  local info = map and C.MapInfo and C.MapInfo(map)
  local snap = {
    version = Panoply.version, time = _G.date and date("%Y-%m-%d %H:%M:%S") or nil,
    build = _G.GetBuildInfo and select(4, GetBuildInfo()) or nil,
    open = open, map = map, mapName = info and info.name or (C.MapName and C.MapName(map)) or nil,
    mapType = C.MapType and C.MapType(map) or nil, mode = self.mapMode,
    maximized = wm and safe(wm, "IsMaximized") and true or false,
    options = { trailWorldMap = opt("trailWorldMap"), trailMinimap = opt("trailMinimap"), trailAnimate = opt("trailAnimate"),
      routeEnabled = opt("routeEnabled"),
      trailWmSize = size("wm"), trailWmAlpha = alpha("wm"), trailMmSize = size("mm"), trailMmAlpha = alpha("mm"),
      trailWmSpacing = Panoply.Look.Spacing("trail", "wm"), trailMmSpacing = Panoply.Look.Spacing("trail", "mm"),
      trailWmStyle = Panoply.Look.Style("trail", "wm"), trailMmStyle = Panoply.Look.Style("trail", "mm"),
      trailWmColour = Panoply.Look.Colour("trail", "wm"), trailMmColour = Panoply.Look.Colour("trail", "mm") },
  }
  if canvas then
    local sc = wm and wm.ScrollContainer
    snap.canvas = { w = num(safe(canvas, "GetWidth")), h = num(safe(canvas, "GetHeight")), scale = num(safe(canvas, "GetScale"), 3),
      effScale = num(self:CanvasScale(canvas), 3), container = sc and { w = num(safe(sc, "GetWidth")), h = num(safe(sc, "GetHeight")), alpha = num(safe(sc, "GetAlpha"), 2) } or nil,
      mapAlpha = wm and num(safe(wm, "GetAlpha"), 2) or nil }
  end
  local L = self.mapLayer
  if L then
    snap.layer = { level = safe(L, "GetFrameLevel"), strata = safe(L, "GetFrameStrata"), shown = safe(L, "IsShown") and true or false,
      visible = safe(L, "IsVisible") and true or false, onCanvas = safe(L, "GetParent") == canvas, alpha = effAlpha(L),
      w = num(safe(L, "GetWidth")), h = num(safe(L, "GetHeight")), floored = L.panoplyFloored and true or false }
  end
  snap.mapStrata = wm and safe(wm, "GetFrameStrata") or nil
  snap.mapScale = wm and num(safe(wm, "GetScale"), 3) or nil
  local mgr = wm and safe(wm, "GetPinFrameLevelsManager")
  if type(mgr) == "table" and mgr.GetValidFrameLevel then
    snap.levels = {}
    for _, t in ipairs({ "PIN_FRAME_LEVEL_MAP_EXPLORATION", "PIN_FRAME_LEVEL_FOG_OF_WAR", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_AREA_POI",
      "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "PIN_FRAME_LEVEL_GROUP_MEMBER", "PIN_FRAME_LEVEL_TOPMOST" }) do
      snap.levels[(t:gsub("PIN_FRAME_LEVEL_", ""))] = safe(mgr, "GetValidFrameLevel", t)
    end
  end
  snap.levels = snap.levels or {}
  snap.levels.trail, snap.levels.pins, snap.levels.card = C.WorldMapLevel("trail"), C.WorldMapLevel("pins"), C.WorldMapLevel("card")
  local ex = _G.C_MapExplorationInfo
  if map and ex and ex.GetExploredMapTextures then
    local ok, t = pcall(ex.GetExploredMapTextures, map)
    snap.exploredTextures = ok and type(t) == "table" and #t or nil
  end
  local d = self.dbg or {}
  snap.why = d.why
  snap.dots, snap.lines, snap.capped = self.mapDots or 0, self.mapLines or 0, d.full
  snap.legs = d.legs or {}
  snap.skipped = d.skipped or {}
  local pcs = d.pieces or {}
  snap.coords = {}
  for i, p in ipairs(pcs) do
    snap.coords[i] = #p == 4 and ("%.1f,%.1f>%.1f,%.1f"):format(p[1], -p[2], p[3], -p[4]) or ("%.1f,%.1f"):format(p[1], -p[2])
  end
  snap.coordsMore = pcs.more
  snap.dotCoords = {}
  for i, t in ipairs(self.mapPool or {}) do
    if i > 60 or not t.panoplyOn then break end
    local _, _, _, x, y = safe(t, "GetPoint", 1)
    snap.dotCoords[i] = ("%.1f,%.1f"):format(tonumber(x) or 0, -(tonumber(y) or 0))
  end
  local sample = self.mapPool and self.mapPool[1] and self.mapPool[1].panoplyOn and self.mapPool[1] or (self.linePool and self.linePool[1] and self.linePool[1].panoplyOn and self.linePool[1])
  if sample then
    snap.sample = { kind = sample.panoplyKind, visible = safe(sample, "IsVisible") and true or false, alpha = effAlpha(sample),
      layer = safe(sample, "GetDrawLayer"), w = num(safe(sample, "GetWidth")), thickness = num(safe(sample, "GetThickness"), 2) }
  end
  snap.kinds = self:KindsInUse()
  snap.card = self.card and { shown = safe(self.card, "IsShown") and true or false, level = safe(self.card, "GetFrameLevel"), corner = self.cardCorner,
    legend = table.concat(self.card.legendKinds or {}, ",") } or nil
  return snap
end
function Trail:MapDebugLine(s)
  if not s.open then return "mapdebug: open the world map first (M), then run /panoply mapdebug again. Saved what I have; /reload writes it to SavedVariables." end
  local skipped = {}
  for _, x in ipairs(s.skipped or {}) do skipped[#skipped + 1] = ("%d %s"):format(x.leg or 0, x.why) end
  local L = s.layer or {}
  return ("mapdebug: map %s (%s, %s) canvas %sx%s x%s, trail level %s %s %s, %d dots + %d pieces from %d legs%s. Saved; /reload writes it to SavedVariables."):format(
    tostring(s.map), tostring(s.mapName or "?"), s.maximized and "maximized" or "small",
    tostring(s.canvas and s.canvas.w), tostring(s.canvas and s.canvas.h), tostring(s.canvas and s.canvas.effScale),
    tostring(L.level), tostring(L.strata), L.visible and "visible" or "NOT visible",
    s.dots or 0, s.lines or 0, #(s.legs or {}),
    #skipped > 0 and (", skipped: " .. table.concat(skipped, "; ")) or (s.why and (", " .. s.why) or ""))
end
function Trail:MapDebugCommand(sub)
  sub = sub and sub:lower() or ""
  if sub == "off" then
    self:SetRoadsDebug(false)
    local line = self:RoadsDebugLine(nil)
    Panoply:Print(line)
    return nil, line
  elseif sub == "roads" then                      -- toggle the road overlay only
    local info = self:SetRoadsDebug(not self.roadsDebug)
    local line = self:RoadsDebugLine(info)
    Panoply:Print(line)
    return info, line
  end
  local snap = self:MapDebug()
  if Panoply.db then Panoply.db.mapDebug = snap end
  local line = self:MapDebugLine(snap)
  Panoply:Print(line)
  -- 0.7.4: the plain command also lays our road points over the map (drawing only; /panoply mapdebug off removes it)
  local info = self:SetRoadsDebug(true)
  if snap.open then Panoply:Print(self:RoadsDebugLine(info)) end
  return snap, line
end

-- Step 2 D: a small sample for the live preview in the Look of the map. The walking part (the dots, dashes or line the map's Style says)
-- and a flight leg after it, drawn by the SAME stroker, from the SAME geometry (Trail:WalkSetup) and the same size, spacing, opacity and
-- colour the maps read, in a box of the map's true size (108 x 64 for the world map, a 56 px piece of the minimap).
Trail.SAMPLE = {
  wm = { walk = { { 8, 54 }, { 30, 50 }, { 52, 38 }, { 70, 32 } }, fly = { { 70, 32 }, { 88, 22 }, { 102, 10 } } },
  mm = { walk = { { 2, 48 }, { 16, 42 }, { 28, 32 }, { 36, 27 } }, fly = { { 36, 27 }, { 46, 17 }, { 54, 7 } } },
}
local function polyline(pts)
  local xs, ys, cum = {}, {}, {}
  local len = 0
  for i, p in ipairs(pts) do
    xs[i], ys[i] = p[1], -p[2]
    if i > 1 then len = len + sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2) end
    cum[i] = len
  end
  return xs, ys, cum, len
end
function Trail:DrawSample(layer, where)
  local pen = layer.panoplyPen
  if not pen then
    pen = self:NewPen(layer, 80, 160, where)
    layer.panoplyPen = pen
  end
  local S = self.SAMPLE[where]
  local wxs, wys, wcum, wlen = polyline(S.walk)
  local src, baseGap, baseDot, grow
  if where == "wm" then src, baseGap, baseDot, grow = self.MAP, self.MAP_WALK_PX, self.MAP_WALK_DOT, true
  else
    local mm = _G.Minimap
    local rpx = ((mm and mm.GetWidth and mm:GetWidth()) or 140) / 2       -- the real minimap's size: the sample is a true-size piece of it
    src, baseGap, baseDot, grow = self.MINI, 2 * rpx / self.MINI_WALK_STEPS, self.MINI_WALK_DOT, false
  end
  local style = Panoply.Look.Style("trail", where)
  local W = self:WalkSetup(where, src, 1, baseGap, baseDot, wlen, 60, grow)
  -- the other legs keep the geometry they have on the real map (on the minimap their gap follows the dots' size)
  local G = scaled(src, 1, where == "mm" and { gap = baseGap * max(size("mm"), Trail.GAP_MIN), dot = baseDot * size("mm") } or nil)
  local a = alpha(where)
  -- clipped like the real map: the world map's piece is cut to its box, the minimap's to its circle, with line pieces cut short enough that
  -- their dark outline stays inside (the box and the circle of the live preview clip what is drawn on them, but a mark must never be asked to
  -- reach past them: the real minimap does not clip what add-ons draw on it)
  local walkClip, flyClip
  if where == "wm" then
    local w, h = layer:GetWidth() or 108, layer:GetHeight() or 64
    walkClip = self.RectClip(0, -h, w, 0)
    flyClip = walkClip
  else
    local half = (layer:GetWidth() or 56) / 2
    if W.walk == "ants" then walkClip = self.CircleClip(half, -half, half)
    else walkClip = self.CircleClip(half, -half, half - (W.wline + 2 * W.ink) - 0.5) end
    flyClip = self.CircleClip(half, -half, half - max(G.line + 2 * G.ink, (G.railSep + G.rail) / 2 + 2 * G.ink) - 0.5)
  end
  pen:Begin()
  if W.walk == "solid" then
    local lx, ly, lc = thin(wxs, wys, wcum, #wxs, W.lstep, {}, {}, {})
    self:Stroke(pen, lx, ly, lc, "walk", W, walkClip, a, nil)
  else
    self:Stroke(pen, wxs, wys, wcum, "walk", W, walkClip, a, (W.period or W.gap) * 0.5)
  end
  local fxs, fys, fcum = polyline(S.fly)
  self:Stroke(pen, fxs, fys, fcum, "fly", G, flyClip, a, nil)
  pen:End()
  layer.panoplyStyle = style
end
Panoply.Look.Draw.trail = function(layer, where) Trail:DrawSample(layer, where) end

local TRAIL_KEYS = { trailWorldMap = true, trailMinimap = true, trailAnimate = true, routeEnabled = true }
for _, k in ipairs(Panoply.Look.AllKeys()) do if k:find("^trail") then TRAIL_KEYS[k] = true end end
local function redraw() Trail.mapSig = nil Trail:DrawMap() Trail:DrawRoadsDebug() end
Trail.HOOKS = { "OnMapChanged", "OnCanvasScaleChanged", "OnCanvasSizeChanged", "Maximize", "Minimize", "SynchronizeDisplayState" }
function Trail:Register()
  Panoply:Listen("ROUTE_UPDATED", function() Trail:SetRoute(Panoply.Route.current) end)
  Panoply:Listen("OPTION_CHANGED", function(key)
    if TRAIL_KEYS[key] then Trail.mapSig = nil Trail:UpdateDrivers() Trail:DrawMap() Trail:DrawMinimap(0) end
  end)
  local wm = C.WorldMap()
  if wm and wm.HookScript then
    wm:HookScript("OnShow", redraw)
    wm:HookScript("OnHide", function() if Trail.card then Trail.card:Hide() end end)
  end
  -- hooksecurefunc on the map's own methods (no data provider, nothing added to Blizzard's tables)
  self.hooked = {}
  if wm then for _, m in ipairs(self.HOOKS) do if C.Hook(wm, m, redraw) then self.hooked[#self.hooked + 1] = m end end end
end
