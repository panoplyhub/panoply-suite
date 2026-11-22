-- Gathering module (SPEC 19.5): remembers every herb, ore vein, fishing pool and treasure chest
-- you gather (zone, x, y, type), shows them on the world map and minimap, shares them with your
-- partner, and on Classic Era starts with a database of known spawn points
-- (Data/Gathering/Nodes.lua). Profession "Mine X" steps point the arrow at the nearest node.
local ADDON, Panoply = ...
local C, Skin, Nav = Panoply.Compat, Panoply.Skin, Panoply.Nav
local Gat = Panoply.Modules:Register({
  key = "gathering", label = "Gathering", icon = "Gathering",
  desc = "Remembers herbs, ore, fishing pools and chests and shows them on your maps.",
  defaults = {
    gatherNodes = {}, gatherShow = { herb = true, ore = true, fish = true, chest = true },
    gatherWorldMap = true, gatherMinimap = true, gatherMinimapYards = 250, gatherEdgeFade = true,
    gatherSkillFilter = false, gatherShare = true, gatherDatabase = true,
    -- 0.7.3.7 ("Fix every size slider"): size and opacity of the spots on each map (Panoply.Look); 100% = 14 px on the world map, 8 px on the minimap
    gatherWmSize = 1, gatherWmAlpha = 1, gatherMmSize = 1, gatherMmAlpha = 1,
    gatherFadeNear = true, gatherFadeYards = 60,   -- 0.5.7: pins fade as you get close (the game's tracking dot shows)
    gatherRings = true,   -- 0.6.0: hollow rings on the minimap so the game's gold tracking dot shows
  },
})
Panoply.Gathering = Gat
Gat.TYPES = { "herb", "ore", "fish", "chest" }
Gat.ICON = { herb = "NodeHerb", ore = "NodeOre", fish = "NodeFish", chest = "NodeChest" }
Gat.LABEL = { herb = "Herbs", ore = "Ore veins", fish = "Fishing pools", chest = "Treasure chests" }
Gat.SKILL = { herb = "Herbalism", ore = "Mining" }
Gat.MERGE_YARDS = 15
Gat.VISIT_YARDS = 12
Gat.REVISIT_SECONDS = 300
Gat.visited = {}

-- Spells that gather (any rank). Names are the English fallback when the ID is not listed.
Gat.SPELLS = {
  [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
  [2575] = "ore", [2576] = "ore", [3564] = "ore", [10248] = "ore",
  [7620] = "fish", [7731] = "fish", [7732] = "fish", [18248] = "fish",
  [3365] = "chest", [6247] = "chest", [6249] = "chest", [6477] = "chest", [6478] = "chest", [21651] = "chest",
}
Gat.SPELL_NAMES = { ["Herb Gathering"] = "herb", ["Mining"] = "ore", ["Fishing"] = "fish", ["Opening"] = "chest" }
local CHEST_WORDS = { "Chest", "Trunk", "Strongbox", "Coffer", "Footlocker", "Cache" }
local POOL_WORDS = { "School", "Pool", "Wreckage", "Swarm", "Floating Debris", "Oil Spill" }

local function anyWord(name, words) for _, w in ipairs(words) do if name:find(w, 1, true) then return true end end return false end

-- Type of a named node: the database list first, then name patterns.
function Gat:TypeOf(name, spellType)
  if not name or name == "" then return nil end
  local D = Panoply.GatherData
  local t = D and D.types and D.types[name]
  if t then return t[1], t[2] end
  if spellType == "chest" then return anyWord(name, CHEST_WORDS) and "chest" or nil end
  if spellType == "fish" then return anyWord(name, POOL_WORDS) and "fish" or nil end
  if spellType == "herb" or spellType == "ore" then return spellType end
  return nil
end

-------------------------------------------------------------------------------
-- Node store: own and partner nodes (saved), plus the Era database (read-only, unpacked lazily)
-------------------------------------------------------------------------------
function Gat:MapNodes(map) Panoply.db.gatherNodes[map] = Panoply.db.gatherNodes[map] or {} return Panoply.db.gatherNodes[map] end

local dbCache = {}
function Gat:DatabaseNodes(map)
  local D = Panoply.GatherData
  if not (D and Panoply.db.gatherDatabase) then return {} end
  if D.flavor and D.flavor ~= C.Flavor() then return {} end
  if dbCache[map] then return dbCache[map] end
  local out = {}
  for name, packed in pairs(D.maps[map] or {}) do
    local t, skill = self:TypeOf(name)
    for i = 1, #packed - 5, 6 do
      local x = tonumber(packed:sub(i, i + 2), 16) / 4095
      local y = tonumber(packed:sub(i + 3, i + 5), 16) / 4095
      out[#out + 1] = { t, name, x, y, 0, 0, "db", skill = skill }
    end
  end
  dbCache[map] = out
  return out
end

function Gat:Record(map, x, y, ntype, name, src, quiet)
  if not (map and x and y and ntype) then return nil end
  local list = self:MapNodes(map)
  local w, h = C.MapSize(map)
  for _, n in ipairs(list) do
    if n[1] == ntype and n[2] == name then
      local d = w and math.sqrt(((n[3] - x) * w) ^ 2 + ((n[4] - y) * h) ^ 2) or (math.abs(n[3] - x) + math.abs(n[4] - y)) * 1000
      if d <= Gat.MERGE_YARDS then
        n[5] = (n[5] or 1) + 1; n[6] = time and time() or 0
        Panoply:Fire("GATHER_NODES_CHANGED", map)
        return n, false
      end
    end
  end
  local n = { ntype, name, math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000, 1, time and time() or 0, src or "me" }
  list[#list + 1] = n
  Panoply:Fire("GATHER_NODES_CHANGED", map)
  if (src or "me") == "me" and Panoply.db.gatherShare and Panoply.Sync and not quiet then
    Panoply.Sync:Queue("G", { m = map, x = n[3], y = n[4], t = ntype, n = name })
  end
  return n, true
end

function Gat:Remove(map, node)
  local list = self:MapNodes(map)
  for i, n in ipairs(list) do if n == node then table.remove(list, i) Panoply:Fire("GATHER_NODES_CHANGED", map) return true end end
  return false
end

function Gat:Shown(n)
  local show = Panoply.db.gatherShow or {}
  if not show[n[1]] then return false end
  if Panoply.db.gatherSkillFilter and n.skill and Gat.SKILL[n[1]] then
    local r = Panoply.Professions and Panoply.Professions:CurrentSkill(Gat.SKILL[n[1]]) or nil
    if not r or r < n.skill then return false end
  end
  return true
end

-- Everything to draw on a map: recorded nodes, then database spots not already recorded.
function Gat:Nodes(map)
  local out = {}
  for _, n in ipairs(self:MapNodes(map)) do if self:Shown(n) then out[#out + 1] = n end end
  for _, n in ipairs(self:DatabaseNodes(map)) do if self:Shown(n) then out[#out + 1] = n end end
  return out
end

-- Nearest node of a name (or type) to a position on the same map, skipping ones visited recently.
function Gat:Nearest(what, pos, map)
  if not self.active or not pos or not pos.map then return nil end
  map = map or pos.map
  if map ~= pos.map then return nil end
  local best, bestD
  local now = C.GetTime()
  local function consider(n)
    if n[2] ~= what and n[1] ~= what then return end
    local key = map .. ":" .. n[3] .. ":" .. n[4]
    if Gat.visited[key] and now - Gat.visited[key] < Gat.REVISIT_SECONDS then return end
    local d = Nav.Distance(pos.map, pos.x, pos.y, map, n[3], n[4])
    if d and d <= Gat.VISIT_YARDS then Gat.visited[key] = now return end
    if d and (not bestD or d < bestD) then best, bestD = n, d end
  end
  for _, n in ipairs(self:MapNodes(map)) do consider(n) end
  for _, n in ipairs(self:DatabaseNodes(map)) do consider(n) end
  return best, bestD
end

-------------------------------------------------------------------------------
-- Recording from the game: the cast names its target; success records it where you stand.
-------------------------------------------------------------------------------
function Gat:SpellType(spellID)
  local t = Gat.SPELLS[spellID]
  if t then return t end
  local n = spellID and C.SpellName(spellID)
  return n and Gat.SPELL_NAMES[n] or nil
end

function Gat:OnSent(unit, target, guid, spellID)
  if unit ~= "player" then return end
  local st = self:SpellType(spellID)
  if not st then self.pending = nil return end
  self.pending = { st = st, target = target, guid = guid, spell = spellID }
end

function Gat:OnSucceeded(unit, guid, spellID)
  if unit ~= "player" then return end
  local p = self.pending
  if not p or (guid and p.guid and guid ~= p.guid) then return end
  self.pending = nil
  if p.st == "fish" then return end   -- pools are recorded when the catch opens (LOOT_OPENED)
  local t = self:TypeOf(p.target, p.st)
  if not t then return end
  local m, x, y = C.GetPlayerPos()
  if m then return self:Record(m, x, y, t, p.target) end
end

function Gat:OnLoot()
  if not C.IsFishingLoot() then return end
  local name = C.TooltipTitle()
  local t = name and self:TypeOf(name, "fish")
  if t ~= "fish" then return end
  local m, x, y = C.GetPlayerPos()
  if m then return self:Record(m, x, y, "fish", name) end
end

Gat:On("UNIT_SPELLCAST_SENT", function(_, ...) Gat:OnSent(...) end)
Gat:On("UNIT_SPELLCAST_SUCCEEDED", function(_, ...) Gat:OnSucceeded(...) end)
Gat:On("LOOT_OPENED", function() Gat:OnLoot() end)

-- Partner nodes arrive over the Panoply Suite channel.
if Panoply.Sync then
  Panoply.Sync.handlers.G = function(who, p)
    if not Gat.active or not Panoply.db.gatherShare then return end
    if type(p.m) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then return end
    if p.x < 0 or p.x > 1 or p.y < 0 or p.y > 1 or not Gat.ICON[p.t] then return end
    Gat:Record(p.m, p.x, p.y, p.t, type(p.n) == "string" and p.n:sub(1, 40) or p.t, "partner")
  end
end

-------------------------------------------------------------------------------
-- Pins
-------------------------------------------------------------------------------
local function pinTip(pin)
  local n, GT = pin.node, _G.GameTooltip
  if not (n and GT) then return end
  GT:SetOwner(pin, "ANCHOR_RIGHT")
  GT:SetText(n[2] or Gat.LABEL[n[1]], 1, 0.82, 0.25)
  local src = n[7] == "db" and "Known spawn point (Classic database)" or n[7] == "partner" and "Shared by your partner"
    or ("Gathered here %d time%s"):format(n[5] or 1, (n[5] or 1) == 1 and "" or "s")
  GT:AddLine(src, 0.9, 0.9, 0.9)
  if n.skill and n.skill > 0 then GT:AddLine("Needs skill " .. n.skill, 0.7, 0.7, 0.7) end
  if pin.panoplyRing then GT:AddLine(Gat.RING_TIP, 0.9, 0.8, 0.55, true) end
  GT:AddLine("Right-click: point the arrow here", 0.5, 0.85, 1)
  GT:Show()
end

function Gat:NewPin(parent)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true  -- placed at the node's map position; two nearby nodes may touch
  p:SetSize(14, 14)
  local t = p:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(p)
  p.tex = t
  -- 0.6.2 (pins disappear into tan and brown terrain): a solid dark disc behind every node icon,
  -- 3 px wider, so the icon reads on any map colour (no glow: a flat disc)
  local back = p:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(Skin.TEX.CircleMask)
  back:SetPoint("TOPLEFT", p, "TOPLEFT", -1.5, 1.5); back:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 1.5, -1.5)
  local k = Skin.colors.trailInk or { 0.04, 0.05, 0.07 }
  back:SetVertexColor(k[1], k[2], k[3], 0.92)
  p.back = back
  if p.RegisterForClicks then p:RegisterForClicks("RightButtonUp") end
  p:SetScript("OnEnter", pinTip)
  p:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  p:SetScript("OnClick", function(self, button)
    local n = self.node
    if n and self.map and Panoply.Arrow then Panoply.Arrow:PointAt(self.map, n[3], n[4], n[2]) end
  end)
  return p
end

-- how solid a spot is on a map: the database spots are a little fainter, then the player's opacity setting
local function pinAlpha(n, where) return (n[7] == "db" and 0.8 or 1) * Panoply.Look.Alpha("gather", where) end
Gat.PinAlpha = pinAlpha

local function setPin(p, n, map, size, where)
  p.node, p.map = n, map
  if p.panoplyRing then
    p.panoplyRing = nil
    if p.tex.SetVertexColor then p.tex:SetVertexColor(1, 1, 1, 1) end
  end
  -- skin v3: our node pin in Panoply Suite icon style; the game's herb / ore / chest icon in WoW style
  Skin.SetPin(p.tex, "Node", Gat.ICON[n[1]] or "NodeHerb")
  -- Step 2 D: "Colour" of the gathering spots on this map: one colour for every spot (the art goes grey and takes it), or By type as before
  Panoply.Look.Tint(p.tex, Panoply.Look.RGB("gather", where or "wm"))
  if p.back then p.back:Show() end
  p:SetSize(size, size)
  p:SetAlpha(pinAlpha(n, where or "wm"))
end

-- 0.6.0: on the minimap a herb or ore node inside the visible radius is drawn as a thin hollow
-- brass ring when the matching game tracker is on (Find Herbs / Find Minerals), or always when
-- the tracker can't be read. The ring's clear centre (about 15 px at 18 px drawn) is wider than
-- the game's gold blip, so the dot shows inside it: ring with a dot = the node is up; empty
-- ring = not up right now. Rim pins and world map pins are unchanged; the fade applies too.
Gat.RING_PX = 18
Gat.RING_TYPES = { herb = true, ore = true }
Gat.RING_TIP = "Ring empty = not up right now (already gathered or not spawned yet)."
function Gat:WantsRing(ntype, tracking)
  if not (Panoply.db and Panoply.db.gatherRings ~= false) then return false end
  if not Gat.RING_TYPES[ntype] then return false end
  if tracking == nil then return true end   -- can't read the tracker: ring for every in-radius node
  return tracking[ntype] and true or false
end
local function setRing(p, n, map)
  p.node, p.map = n, map
  local t = p.tex
  t:SetTexture(Skin.TEX.GatherRing)
  if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
  if t.SetDesaturated then t:SetDesaturated(false) end
  local c = Panoply.Look.RGB("gather", "mm") or Skin.colors.gatherRing or Skin.colors.trim    -- Step 2 D: the ring takes the minimap colour too
  if t.SetVertexColor then t:SetVertexColor(c[1], c[2], c[3], 1) end
  t.panoplyLookTint = nil
  t.panoplyJ = true   -- a later Skin pin call resets the tint
  Skin.live[t] = nil
  p.panoplyRing = true
  if p.back then p.back:Hide() end   -- the ring keeps its clear middle (the game's tracking dot shows)
  p:SetSize(Gat.RING_PX, Gat.RING_PX)
end
Gat.SetRing = setRing

-- 0.5.7: pins fade as you walk up to the node, so the game's own gold Find Minerals / Find Herbs
-- dot under the pin can be read. Fully opaque from `far` yards (Settings > Gathering > Fade
-- distance, default 60), easing down to FADE_MIN at FADE_NEAR yards or closer.
Gat.FADE_NEAR, Gat.FADE_MIN = 15, 0.15
function Gat.FadeAlpha(d, far)
  if not d then return 1 end
  local near = Gat.FADE_NEAR
  far = math.max(near + 1, far or 60)
  if d >= far then return 1 end
  if d <= near then return Gat.FADE_MIN end
  local t = (d - near) / (far - near)
  t = t * t * (3 - 2 * t)                     -- smoothstep: no visible step at either end
  return Gat.FADE_MIN + (1 - Gat.FADE_MIN) * t
end
function Gat:FadeFor(d)
  if not (Panoply.db and Panoply.db.gatherFadeNear ~= false) then return 1 end
  return Gat.FadeAlpha(d, Panoply.db.gatherFadeYards)
end

-- World map: one overlay on the map canvas; redrawn when the map opens or changes.
function Gat:WorldMapRefresh()
  local canvas = C.WorldMapCanvas()
  local wm = C.WorldMap()
  self.wmPins = self.wmPins or {}
  for _, p in ipairs(self.wmPins) do p:Hide() end
  if not (self.active and Panoply.db.gatherWorldMap and canvas and wm and wm:IsShown()) then return 0 end
  if not self.wmLayer then
    self.wmLayer = CreateFrame("Frame", nil, canvas)
    self.wmLayer:SetAllPoints(canvas)
  end
  local lvl = C.LiftOnWorldMap(self.wmLayer, "pins")   -- 0.6.1: above the explored map art (see Compat)
  if C.FloorMapAlpha then C.FloorMapAlpha(self.wmLayer) C.HookMapAlpha() end   -- 0.6.2: never fade away
  local map = C.WorldMapID()
  if not map then return 0 end
  local W, H = canvas:GetWidth() or 1000, canvas:GetHeight() or 667
  local scale = (canvas.GetScale and canvas:GetScale()) or 1
  local size = Gat.WM_PIN_PX * Panoply.Look.Size("gather", "wm") / math.max(0.2, scale)
  local nodes = self:Nodes(map)
  for i, n in ipairs(nodes) do
    local p = self.wmPins[i]
    if not p then p = self:NewPin(self.wmLayer); self.wmPins[i] = p end
    setPin(p, n, map, size, "wm")
    if lvl and p.SetFrameLevel then p:SetFrameLevel(lvl + 1) end
    p:ClearAllPoints(); p:SetPoint("CENTER", self.wmLayer, "TOPLEFT", n[3] * W, -n[4] * H)
    p.panoplyBaseAlpha = p:GetAlpha()
    p:Show()
  end
  self.wmShown = #nodes
  self.wmMap, self.wmW, self.wmH, self.wmSize, self.wmScale = map, W, H, size, scale
  self:WorldMapFade()
  return #nodes
end

-- 0.5.7: on the world map only the pins that sit under the player arrow fade (so the arrow
-- and the game's dot stay readable); every other pin is left as it is. Cheap: runs on the
-- minimap tick while the map is open, over the pins already placed.
Gat.WM_ARROW_PX = 16   -- about half the player arrow on the map canvas, in canvas pixels at scale 1
function Gat:WorldMapFade()
  local pins, n = self.wmPins or {}, self.wmShown or 0
  if n == 0 or not self.wmMap then return 0 end
  local m, px, py = C.GetPlayerPos()
  local faded = 0
  local mw, mh = C.MapSize(self.wmMap)
  for i = 1, n do
    local p = pins[i]
    local node = p and p.node
    if node then
      local a = p.panoplyBaseAlpha or 1
      if m == self.wmMap and px then
        local dx, dy = (node[3] - px) * self.wmW, (node[4] - py) * self.wmH
        local reach = self.WM_ARROW_PX / math.max(0.2, self.wmScale or 1) + (self.wmSize or 14) / 2
        if dx * dx + dy * dy <= reach * reach then
          local yd = mw and math.sqrt(((node[3] - px) * mw) ^ 2 + ((node[4] - py) * mh) ^ 2) or 0
          a = a * self:FadeFor(yd)
          faded = faded + 1
        end
      end
      p:SetAlpha(a)
    end
  end
  self.wmFaded = faded
  return faded
end

-- Minimap: pins around the player; beyond the edge they sit on the rim (faded) up to the
-- chosen distance. Updated a few times a second only while the minimap is visible.
-- 0.6.1 (minimap icons too large): plain pins about 8 px (MM_PIN_PX x the minimap size setting, 0.7.3.7:
-- Gathering spots > Minimap > Size), at most MM_CAP pins (closest first), and pins within Panoply.MM_CENTER_PX
-- of the centre fade out. The 0.6.0 in-range ring keeps its size (never smaller), so its clear
-- centre still frames the game's gold Find Minerals / Find Herbs dot.
Gat.MM_PIN_PX = 8
Gat.WM_PIN_PX = 14            -- the world map pin at 100%
Gat.MM_CAP = 10
-- the size of a pin and of a ring on the minimap. The ring keeps its clear middle for the game's tracking dot, so it
-- never gets smaller than its standard size (only bigger).
function Gat:MinimapSizes()
  local sc = Panoply.Look.Size("gather", "mm")
  return Gat.MM_PIN_PX * sc, Gat.RING_PX * math.max(1, sc)
end
function Gat:MinimapRefresh()
  self.mmPins = self.mmPins or {}
  local mm = _G.Minimap
  local used, rings = 0, 0
  local m, px, py = C.GetPlayerPos()
  self.mmCapped, self.mmFaded = 0, 0
  if self.active and Panoply.db.gatherMinimap and mm and mm:IsShown() and m then
    local w, h = C.MapSize(m)
    if w then
      local radius = C.MinimapRadius()
      local maxY = math.max(radius, Panoply.db.gatherMinimapYards or 250)
      local half = (mm:GetWidth() or 140) / 2
      local rot = C.MinimapRotates()
      local f = rot and (C.Facing() or 0) or 0
      local cf, sf = math.cos(f), math.sin(f)
      local size, ringPx = self:MinimapSizes()
      local tracking = C.GatherTracking and C.GatherTracking() or nil
      self.mmTracking = tracking
      local cand = {}
      for _, n in ipairs(self:Nodes(m)) do
        local e, s = (n[3] - px) * w, (n[4] - py) * h
        if math.abs(e) <= maxY and math.abs(s) <= maxY then
          local north = -s
          local sx, sy = e * cf + north * sf, -e * sf + north * cf
          local d = math.sqrt(sx * sx + sy * sy)
          if d <= maxY then
            local alpha = pinAlpha(n, "mm")
            if d <= radius then alpha = alpha * Gat:FadeFor(d) end   -- 0.5.7: fade when close
            if d > radius then
              if not Panoply.db.gatherEdgeFade then alpha = 0 else
                sx, sy = sx / d * radius, sy / d * radius
                alpha = alpha * 0.45
              end
            end
            if alpha > 0 then cand[#cand + 1] = { n = n, sx = sx, sy = sy, d = d, alpha = alpha } end
          end
        end
      end
      table.sort(cand, function(a, b) return a.d < b.d end)
      for k, c in ipairs(cand) do
        if k > self.MM_CAP then self.mmCapped = self.mmCapped + 1 else
          local ox, oy = c.sx / radius * (half - 6), c.sy / radius * (half - 6)
          local ca = Panoply.MinimapCentreAlpha(ox, oy)
          if ca < 1 then self.mmFaded = self.mmFaded + 1 end
          if ca > 0 then
            used = used + 1
            local p = self.mmPins[used]
            if not p then p = self:NewPin(mm); self.mmPins[used] = p end
            if c.d <= radius and self:WantsRing(c.n[1], tracking) then
              setRing(p, c.n, m); p:SetSize(ringPx, ringPx); rings = rings + 1
            else
              setPin(p, c.n, m, size, "mm")
            end
            p:SetAlpha(c.alpha * ca)
            p.mmAlpha = ca
            p:ClearAllPoints(); p:SetPoint("CENTER", mm, "CENTER", ox, oy)
            p:Show()
          end
        end
      end
    end
  end
  for i = used + 1, #self.mmPins do self.mmPins[i]:Hide() end
  self.mmShown = used
  self.mmRings = rings
  return used
end

function Gat:Enable()
  if not self.driver then
    local d = CreateFrame("Frame", nil, _G.Minimap or UIParent)
    d.elapsed = 0
    d:SetScript("OnUpdate", function(self, dt)
      self.elapsed = self.elapsed + (dt or 0)
      if self.elapsed < 0.2 then return end
      self.elapsed = 0
      Gat.updates = (Gat.updates or 0) + 1
      Gat:MinimapRefresh()
      local wm = C.WorldMap()
      if wm and wm:IsShown() then Gat:WorldMapFade() end
    end)
    self.driver = d
    local wm = C.WorldMap()
    if wm then
      if wm.HookScript then wm:HookScript("OnShow", function() Gat:WorldMapRefresh() end) end
      C.Hook(wm, "OnMapChanged", function() Gat:WorldMapRefresh() end)
    end
  end
  if Panoply.db.gatherMinimap then self.driver:Show() else self.driver:Hide() end
  self:WorldMapRefresh()
end
function Gat:Disable()
  if self.driver then self.driver:Hide() end
  self:WorldMapRefresh(); self:MinimapRefresh()
end
Gat:Listen("GATHER_NODES_CHANGED", function() Gat:WorldMapRefresh() end)
Panoply.optionHooks.gatherMinimap = function(v) if Gat.driver then if v and Gat.active then Gat.driver:Show() else Gat.driver:Hide() end end Gat:MinimapRefresh() end
for _, k in ipairs({ "gatherWorldMap", "gatherSkillFilter", "gatherDatabase", "gatherFadeNear", "gatherFadeYards", "gatherRings" }) do
  Panoply.optionHooks[k] = function() dbCache = {} Gat:WorldMapRefresh() Gat:MinimapRefresh() end
end
-- 0.7.3.7: each map has its own size and opacity; a world map slider redraws the world map only, a minimap one the minimap only
for _, what in ipairs({ "size", "alpha", "colour" }) do
  Panoply.optionHooks[Panoply.Look.Key("gather", "wm", what)] = function() Gat:WorldMapRefresh() end
  Panoply.optionHooks[Panoply.Look.Key("gather", "mm", what)] = function() Gat:MinimapRefresh() end
end

-- A small sample for the live preview in the Look of the map: the same pins and rings, sizes, opacities and colours the maps draw (the
-- same functions), in a box of the map's true size. The minimap shows an herb and an ore as rings (or icons, by the Style) and a chest.
Gat.SAMPLE = {
  wm = { { { "herb", "Sample", 0, 0, 1, 0, "me" }, 34, 36 }, { { "ore", "Sample", 0, 0, 1, 0, "me" }, 76, 28 } },
  mm = { { { "herb", "Sample", 0, 0, 1, 0, "me" }, 18, 34 }, { { "ore", "Sample", 0, 0, 1, 0, "me" }, 38, 22 }, { { "chest", "Sample", 0, 0, 1, 0, "me" }, 30, 40 } },
}
function Gat:DrawSample(layer, where)
  layer.pins = layer.pins or {}
  local list = self.SAMPLE[where]
  local size, ringPx = self:MinimapSizes()
  for i, e in ipairs(list) do
    local p = layer.pins[i]
    if not p then p = self:NewPin(layer) p:EnableMouse(false) layer.pins[i] = p end
    local n = e[1]
    if where == "mm" then
      if self:WantsRing(n[1], nil) then setRing(p, n, 0) p:SetSize(ringPx, ringPx) else setPin(p, n, 0, size, "mm") end
    else
      setPin(p, n, 0, Gat.WM_PIN_PX * Panoply.Look.Size("gather", "wm"), "wm")
    end
    p:SetAlpha(pinAlpha(n, where))
    local x, y = e[2], e[3]
    if where == "mm" then
      -- as for the quest icons: a big pin or ring is pulled in by its own half size so the whole of it stays inside the circle
      local half = (layer:GetWidth() or 56) / 2
      local dx, dy = x - half, y - half
      local limit = math.max(0, half - ((p:GetWidth() or 8) / 2 + 1))
      local d = math.sqrt(dx * dx + dy * dy)
      if d > limit and d > 0 then x, y = half + dx * limit / d, half + dy * limit / d end
    end
    p:ClearAllPoints(); p:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
    p:Show()
  end
  for i = #list + 1, #layer.pins do layer.pins[i]:Hide() end
end
Panoply.Look.Draw.gather = function(layer, where) Gat:DrawSample(layer, where) end
-- a change of icon style puts every pin's picture back as it was (Skin re-applies the art, which takes the grey off): the colour is put on
-- again at once, on both maps, not at the next refresh
Panoply:Listen("ICON_STYLE_CHANGED", function() if Gat.active then Gat:WorldMapRefresh() Gat:MinimapRefresh() end end)

function Gat:SetShown(t, on)
  Panoply.db.gatherShow[t] = on and true or false
  self:WorldMapRefresh(); self:MinimapRefresh()
  Panoply:Fire("OPTION_CHANGED", "gatherShow", t)
end

function Gat:Counts()
  local mine, db = 0, 0
  for _, list in pairs(Panoply.db.gatherNodes or {}) do mine = mine + #list end
  local D = Panoply.GatherData
  if D and (not D.flavor or D.flavor == C.Flavor()) then db = D.count or 0 end
  return mine, db
end

Gat.options = {
  { type = "typechecks" },
  { type = "check", key = "gatherWorldMap", label = "Show on the world map", tip = "Gathering spots appear on the world map. Right-click one to point the arrow at it." },
  { type = "check", key = "gatherMinimap", label = "Show on the minimap", tip = "Nearby spots appear on the minimap; ones just outside sit faded on the edge. Their size and opacity: " .. Panoply:SettingsPath("gatherMmSize") .. "." },
  { type = "check", key = "gatherEdgeFade", label = "Faded icons on the minimap edge", tip = "Spots a little beyond the minimap are shown on its rim, faded, so you know where to head." },
  { type = "slider", key = "gatherMinimapYards", label = "Minimap icon distance", min = 100, max = 600, step = 25, fmt = "%d yards", tip = "How far away a spot can be and still show on the minimap edge." },
  { type = "check", key = "gatherFadeNear", label = "Fade pins when close", tip = "As you walk up to a node its pin fades, so the game's own gold tracking dot underneath (Find Minerals / Find Herbs) is easy to see." },
  { type = "slider", key = "gatherFadeYards", label = "Fade distance", min = 30, max = 120, step = 5, fmt = "%d yards", tip = "Pins start fading this close to you and are almost see-through within 15 yards.", parent = "gatherFadeNear" },
  { type = "check", key = "gatherSkillFilter", label = "Only spots I have the skill for", tip = "Hides herbs and veins your Herbalism or Mining is too low to gather." },
  -- 0.9.7 (WoW Forever only): the spawn list is for one game (Gat:DatabaseNodes); the row is drawn only where it does something. The saved key stays
  { type = "check", key = "gatherDatabase", label = "Use the known spawn spots", tip = "Start with every known herb, vein, pool and chest spawn point.",
    only = function() local D = Panoply.GatherData return not (D and D.flavor and D.flavor ~= C.Flavor()) end },
  { type = "check", key = "gatherShare", label = "Share finds with my partner", tip = "Nodes you gather are sent to your partner's Panoply Suite and theirs to you." },
}
-- 0.7.3.7: Gathering spots have Size and Opacity for the world map and the minimap. Step 2 D: and a Colour for each, and on the minimap a
-- Style: Icon or Ring (the old "Show hollow rings so the game's tracking dot shows" switch, same saved key gatherRings). With Find Minerals
-- or Find Herbs on, ore and herb spots inside the minimap are drawn as thin rings: a gold dot inside a ring means the node is there, an
-- empty ring means it is not up right now.
for _, r in ipairs(Panoply.Look.Rows("gather")) do Gat.options[#Gat.options + 1] = r end
