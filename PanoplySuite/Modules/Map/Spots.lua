-- Map module, SAVED SPOTS (Nov 2026): places the player saves for themselves, kept for every character on the account.
--   * Three ways to save one: Shift-right-click the world map (a plain right-click is the game's own "zoom out" and stays the game's;
--     Ctrl-right-click is a waypoint), "Where I stand" (the character's own position), or typing a zone, X, Y and a name. All three
--     end in the same small form (S:OpenForm), so a spot always gets a name the player chose.
--   * A saved spot has a Favorite star. Starred spots head the Go to window (FAVOURITES); the others follow (SAVED SPOTS). Every saved
--     spot is found by the Go to search next to the places of the data (Navigate.lua N:Destinations), by its name or its zone.
--   * Their own icons on the world map: a star (gold when it is a favourite), on the same dark disc as the other places. Click one to
--     point the arrow at it; right-click for Go there, the star, Rename and Remove. "Saved spots" in the map's Layers menu hides them.
--   * Kept in a saved variable of its own, PanoplySuiteSpotsDB (per account): { version = 1, nextId, spots = { { id, name, map, x, y,
--     fav, by, at } } }. No other saved variable is touched or renamed; a settings reset and a profile never change the spots.
-- No automatic movement: this file saves places and draws icons. The arrow shows the way and the player walks.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map

local S = {}
M.Spots = S
S.MAX = 200                 -- saved spots on one account
S.NAME_MAX = 40             -- letters in a name
S.WM_PX = 16                -- the icon on the world map, at 100%
S.rev = 0                   -- goes up with every change (the Go to search rebuilds its list when it has)

Panoply.defaults.account.mapSpots = true

-------------------------------------------------------------------------------
-- The saved list
-------------------------------------------------------------------------------
function S:DB()
  local db = _G.PanoplySuiteSpotsDB
  if type(db) ~= "table" then db = {} _G.PanoplySuiteSpotsDB = db end
  if type(db.spots) ~= "table" then db.spots = {} end
  db.version = tonumber(db.version) or 1
  db.nextId = tonumber(db.nextId) or 1
  -- a list edited by hand or cut short: only whole spots are kept in play (nothing is deleted from the file)
  for _, sp in ipairs(db.spots) do
    if type(sp) == "table" and type(sp.id) == "number" and sp.id >= db.nextId then db.nextId = sp.id + 1 end
  end
  return db
end

local function whole(sp)
  return type(sp) == "table" and type(sp.id) == "number" and type(sp.name) == "string" and type(sp.map) == "number"
    and type(sp.x) == "number" and type(sp.y) == "number" and sp.x >= 0 and sp.x <= 1 and sp.y >= 0 and sp.y <= 1
end

-- every whole spot, favourites first, then by name
function S:List()
  local out = {}
  for _, sp in ipairs(self:DB().spots) do if whole(sp) then out[#out + 1] = sp end end
  table.sort(out, function(a, b)
    if (a.fav and true or false) ~= (b.fav and true or false) then return a.fav and true or false end
    local an, bn = a.name:lower(), b.name:lower()
    if an ~= bn then return an < bn end
    return a.id < b.id
  end)
  return out
end

function S:Get(id)
  for _, sp in ipairs(self:DB().spots) do if whole(sp) and sp.id == id then return sp end end
  return nil
end

local function changed()
  S.rev = S.rev + 1
  Panoply:Fire("SPOTS_CHANGED")
end

-- a name as it is kept: no colour codes or links, single spaces, not longer than NAME_MAX
function S.CleanName(name)
  name = tostring(name or ""):gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #name > S.NAME_MAX then name = name:sub(1, S.NAME_MAX):gsub("%s+$", "") end
  return name
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- "Elwynn Forest 45.2, 61.8"
function S:Where(sp)
  return ("%s %.1f, %.1f"):format(C.MapName(sp.map) or ("Map " .. tostring(sp.map)), sp.x * 100, sp.y * 100)
end

-- Save a spot. x and y: 0..1, or 0..100 as the map shows them. Returns the spot, or nil and a plain reason.
function S:Add(map, x, y, name)
  map, x, y = tonumber(map), tonumber(x), tonumber(y)
  if not map or not C.MapName(map) then return nil, "Panoply Suite does not know that zone." end
  if not (x and y) then return nil, "X and Y must be numbers, like 45.2 and 61.8." end
  if x > 1 or y > 1 then x, y = x / 100, y / 100 end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "X and Y must be between 0 and 100." end
  name = S.CleanName(name)
  if name == "" then return nil, "Give the spot a name." end
  x, y = round4(x), round4(y)
  local db = self:DB()
  for _, sp in ipairs(db.spots) do
    if whole(sp) and sp.map == map and sp.name:lower() == name:lower() and math.abs(sp.x - x) < 0.002 and math.abs(sp.y - y) < 0.002 then
      return sp, "That spot is already saved."
    end
  end
  local n = 0
  for _, sp in ipairs(db.spots) do if whole(sp) then n = n + 1 end end
  if n >= S.MAX then return nil, ("You have %d saved spots, the most Panoply Suite keeps. Remove one first."):format(S.MAX) end
  local who = C.PlayerInfo() or {}
  local sp = { id = db.nextId, name = name, map = map, x = x, y = y,
               by = who.name and (who.name .. (who.realm and ("-" .. who.realm) or "")) or nil,
               at = (_G.time and time()) or nil }
  db.nextId = db.nextId + 1
  db.spots[#db.spots + 1] = sp
  changed()
  return sp
end

-- where the character stands: map, x, y, and the name of the place (the subzone, else the zone)
function S:Here()
  local m, x, y = C.GetPlayerPos()
  if not (m and x and y) then return nil end
  local sub = (_G.GetSubZoneText and GetSubZoneText()) or ""
  if type(sub) ~= "string" or sub == "" then sub = C.MapName(m) or "" end
  return m, x, y, sub
end

function S:AddHere(name)
  local m, x, y, place = self:Here()
  if not m then return nil, "Panoply Suite can't tell where you are here (inside a dungeon, or the map has no position)." end
  if S.CleanName(name) == "" then name = place ~= "" and place or "My spot" end
  return self:Add(m, x, y, name)
end

-- a zone by its name, as typed (exact, then the start of a name, then a part of one)
function S:FindZone(text)
  local q = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then return nil end
  local ids = (M.Navigate and M.Navigate.ZoneIds and M.Navigate:ZoneIds()) or (Panoply.Waypoints and Panoply.Waypoints.ZONE_IDS) or {}
  local exact, prefix, part
  for _, id in ipairs(ids) do
    local n = C.MapName(id)
    if n then
      local l = n:lower()
      if l == q then exact = exact or id
      elseif l:sub(1, #q) == q then prefix = prefix or id
      elseif l:find(q, 1, true) then part = part or id end
    end
  end
  return exact or prefix or part
end

function S:AddTyped(zone, x, y, name)
  local map = self:FindZone(zone)
  if not map then return nil, ("No zone is called \"%s\". Type its name as the map shows it."):format(tostring(zone or "")) end
  return self:Add(map, x, y, name)
end

function S:Remove(id)
  local list = self:DB().spots
  for i, sp in ipairs(list) do
    if type(sp) == "table" and sp.id == id then table.remove(list, i) changed() return true end
  end
  return false
end

function S:Rename(id, name)
  local sp = self:Get(id)
  name = S.CleanName(name)
  if not sp then return nil, "That spot is not saved any more." end
  if name == "" then return nil, "Give the spot a name." end
  sp.name = name
  changed()
  return sp
end

function S:SetFav(id, on)
  local sp = self:Get(id)
  if not sp then return false end
  sp.fav = on and true or nil
  changed()
  return true
end
function S:ToggleFav(id)
  local sp = self:Get(id)
  if not sp then return false end
  return self:SetFav(id, not sp.fav)
end

-- the saved spots as destinations of the Go to search (Navigate.lua): found by name, by "saved" / "spot" / "favourite" and by zone
function S:Dests()
  local out = {}
  for _, sp in ipairs(self:List()) do
    out[#out + 1] = { kind = "saved", spot = sp.id, name = sp.name, sub = "Saved spot - " .. self:Where(sp), map = sp.map, x = sp.x, y = sp.y,
      keys = { sp.name }, tw = "saved spot spots my place" .. (sp.fav and " favourite favorite star" or ""), ww = C.MapName(sp.map) or "" }
  end
  return out
end

function S:Go(id)
  local sp = self:Get(id)
  if not sp then return false end
  local N = M.Navigate
  if N and N.Go then return N:Go({ kind = "saved", spot = sp.id, name = sp.name, sub = "Saved spot - " .. self:Where(sp), map = sp.map, x = sp.x, y = sp.y }) end
  return M:PointAt(sp.map, sp.x, sp.y, sp.name)
end

-------------------------------------------------------------------------------
-- The form: one small window for all three ways in (a new spot, or renaming one)
-------------------------------------------------------------------------------
S.FORM_W = 380

local function field(f, label, w, placeholder)
  local t = Skin.Label(f, 10, Skin.colors.inkSoft)
  t:SetText(label)
  local box = Skin.Input(f, w, 24, placeholder)
  if box.icon then box.icon:Hide() end
  if box.SetTextInsets then box:SetTextInsets(8, 6, 0, 0) end
  if box.placeholder then box.placeholder:ClearAllPoints(); box.placeholder:SetPoint("LEFT", box, "LEFT", 8, 0) end
  box:SetScript("OnTextChanged", function(b)
    if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end
  end)
  box:SetScript("OnEnterPressed", function() S:FormSave() end)
  return { label = t, box = box }
end

function S:CreateForm()
  if self.form then return self.form end
  local f = Skin.Window("PanoplySuiteSpotForm", S.FORM_W, 300, "Save a spot", "Kept for every character on this account", nil, "Hearth")   -- 4J: its own header icon
  self.form = f
  f.inName = field(f, "NAME", 200, "A name for this spot")
  f.inZone = field(f, "ZONE", 200, "Elwynn Forest")
  f.inX = field(f, "X", 60, "45.2")
  f.inY = field(f, "Y", 60, "61.8")
  f.fields = { f.inName, f.inZone, f.inX, f.inY }
  f.here = Skin.Button(f, "Where I stand", 120, 24, function() S:FormHere() end, "Where I stand",
    "Fills in the zone and the position your character stands at now.")
  f.save = Skin.Button(f, "Save", 80, 26, function() S:FormSave() end, "Save", "Saves this spot. It shows on the world map and in the Go to search.")
  f.cancel = Skin.Button(f, "Cancel", 80, 26, function() f:Hide() end, "Cancel", "Closes this window without saving.")
  f.msg = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.hint = Skin.Text(f, 11, Skin.colors.dim)
  f.hint:SetText("Tip: Shift-right-click the world map to save the place you clicked.")
  function f:Layout() return S:LayoutForm() end
  -- a resize grip: the form is as tall as its fields (LayoutForm sets the height), so the grip changes the width
  Skin.Resizable(f, { key = "spotForm", minW = S.FORM_W, minH = 120, onSize = function(_, _, done) if done and f:IsShown() then S:LayoutForm() end end })
  if f.HookScript then f:HookScript("OnShow", function() S:LayoutForm() end) end
  return f
end

function S:LayoutForm()
  local f = self.form
  if not f then return end
  local SP = Skin.SP
  local W = f:GetWidth() or S.FORM_W
  local inner = W - 32
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  local function put(fld, x, w)
    local lh = math.ceil(Skin.TextHeight(fld.label, w))
    fld.label:SetWidth(w); fld.label:SetHeight(lh)
    fld.label:ClearAllPoints(); fld.label:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    fld.box:ClearAllPoints(); fld.box:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + lh + 2)); fld.box:SetWidth(w)
    return lh + 2 + 24
  end
  y = y + put(f.inName, 16, inner) + SP.m
  y = y + put(f.inZone, 16, inner) + SP.m
  -- X and Y side by side, "Where I stand" beside them when it fits, else under them
  local half = math.floor((math.min(inner, 220) - SP.m) / 2)
  local hx = put(f.inX, 16, half)
  put(f.inY, 16 + half + SP.m, half)
  local hw = Skin.FitButton(f.here, 100, inner)
  local lh = math.ceil(Skin.TextHeight(f.inX.label, half))
  f.here:ClearAllPoints()
  if 2 * half + SP.m + SP.l + hw <= inner then
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + inner - hw, -(y + lh + 2))
    y = y + hx + SP.m
  else
    y = y + hx + SP.s
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -y)
    y = y + 24 + SP.m
  end
  -- the message (why a spot could not be saved), then the tip
  local msg = self.formMsg
  f.msg:SetText(msg and msg.text or "")
  local c = msg and msg.bad and Skin.colors.warn or Skin.colors.inkSoft
  f.msg:SetTextColor(c[1], c[2], c[3], 1)
  f.msg:ClearAllPoints(); f.msg:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -y); f.msg:SetWidth(inner)
  if msg then
    local mh = math.ceil(Skin.TextHeight(f.msg, inner))
    f.msg:SetHeight(mh); f.msg:Show()
    y = y + mh + SP.s
  else f.msg:Hide() end
  f.hint:ClearAllPoints(); f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -y); f.hint:SetWidth(inner)
  if self.formEdit then f.hint:Hide() else
    local hh = math.ceil(Skin.TextHeight(f.hint, inner))
    f.hint:SetHeight(hh); f.hint:Show()
    y = y + hh + SP.m
  end
  f.save.label:SetText(self.formEdit and "Rename" or "Save")
  local bh = Skin.FlowButtons(f, { f.save, f.cancel }, 16, -y, inner, SP.s, 70)
  y = y + math.max(bh, 26) + SP.l
  f:SetHeight(y)
end

local function setBox(fld, text)
  fld.box:SetText(text or "")
  if fld.box.placeholder then if (text or "") == "" then fld.box.placeholder:Show() else fld.box.placeholder:Hide() end end
end
local function lock(fld, on)
  if fld.box.SetEnabled then fld.box:SetEnabled(not on) end
  fld.box:SetAlpha(on and 0.6 or 1)
end

-- Open the form. opts: { map, x, y } a place to start from (a click on the map); { here = true } the character's position;
-- { edit = id } rename a saved spot; nothing: empty, to type a zone, X and Y.
function S:OpenForm(opts)
  opts = opts or {}
  local f = self:CreateForm()
  self.formMsg, self.formEdit = nil, nil
  for _, fld in ipairs(f.fields) do lock(fld, false) end
  local sp = opts.edit and self:Get(opts.edit)
  if sp then
    self.formEdit = sp.id
    setBox(f.inName, sp.name); setBox(f.inZone, C.MapName(sp.map) or ""); setBox(f.inX, ("%.1f"):format(sp.x * 100)); setBox(f.inY, ("%.1f"):format(sp.y * 100))
    for _, fld in ipairs({ f.inZone, f.inX, f.inY }) do lock(fld, true) end
    f.here:Hide()
    if f.panoplyTitle and f.panoplyTitle.SetText then f.panoplyTitle:SetText("Rename a spot") end
  else
    f.here:Show()
    if f.panoplyTitle and f.panoplyTitle.SetText then f.panoplyTitle:SetText("Save a spot") end
    setBox(f.inName, opts.name or "")
    if opts.map and opts.x and opts.y then
      setBox(f.inZone, C.MapName(opts.map) or ""); setBox(f.inX, ("%.1f"):format(opts.x * 100)); setBox(f.inY, ("%.1f"):format(opts.y * 100))
    else
      setBox(f.inZone, ""); setBox(f.inX, ""); setBox(f.inY, "")
    end
  end
  f:Show()
  if opts.here and not sp then self:FormHere() end
  self:LayoutForm()
  if f.inName.box.SetFocus then f.inName.box:SetFocus() end
  return f
end

function S:FormHere()
  local f = self.form
  if not f then return end
  local m, x, y, place = self:Here()
  if not m then
    self.formMsg = { text = "Panoply Suite can't tell where you are here (inside a dungeon, or the map has no position).", bad = true }
  else
    self.formMsg = nil
    setBox(f.inZone, C.MapName(m) or ""); setBox(f.inX, ("%.1f"):format(x * 100)); setBox(f.inY, ("%.1f"):format(y * 100))
    if S.CleanName(f.inName.box:GetText()) == "" and place ~= "" then setBox(f.inName, S.CleanName(place)) end
  end
  self:LayoutForm()
end

function S:FormSave()
  local f = self.form
  if not f then return nil end
  local name = f.inName.box:GetText() or ""
  local sp, why
  if self.formEdit then
    sp, why = self:Rename(self.formEdit, name)
  else
    local x = tostring(f.inX.box:GetText() or ""):gsub(",", ".")
    local y = tostring(f.inY.box:GetText() or ""):gsub(",", ".")
    sp, why = self:AddTyped(f.inZone.box:GetText() or "", x, y, name)
  end
  if not sp then
    self.formMsg = { text = why or "That spot could not be saved.", bad = true }
    self:LayoutForm()
    return nil
  end
  Panoply:Print(self.formEdit and ("Renamed: %s."):format(sp.name) or (why and (why .. " (" .. sp.name .. ")") or ("Saved spot: %s, %s."):format(sp.name, self:Where(sp))))
  f:Hide()
  return sp
end

-------------------------------------------------------------------------------
-- The world map: a click to save, and the icons
-------------------------------------------------------------------------------
-- Shift-right-click on the map: the place under the pointer is read when the button goes down (the game's own right-click may change
-- the map before the button comes up), and the form opens with it when the button comes up.
function S:OnMapDown(button)
  self.press = nil
  if not (M.active and button == "RightButton" and _G.IsShiftKeyDown and IsShiftKeyDown()) then return end
  local m = C.WorldMapID()
  local x, y = C.WorldMapCursor()
  if m and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then self.press = { map = m, x = x, y = y } end
end
function S:OnMapUp(button)
  local p = self.press
  self.press = nil
  if not (p and button == "RightButton") then return end
  return self:OpenForm({ map = p.map, x = p.x, y = p.y })
end

function S:HookMap()
  if self.hooked then return end
  local wm = C.WorldMap()
  local sc = wm and wm.ScrollContainer
  if not (sc and sc.HookScript) then return end
  self.hooked = true
  sc:HookScript("OnMouseDown", function(_, button) S:OnMapDown(button) end)
  sc:HookScript("OnMouseUp", function(_, button) S:OnMapUp(button) end)
end

local function tipOf(p)
  local sp, GT = p.spot, _G.GameTooltip
  if not (sp and GT) then return end
  GT:SetOwner(p, "ANCHOR_RIGHT")
  GT:SetText(sp.name, 1, 0.82, 0.25)
  GT:AddLine(sp.fav and "Saved spot, a favourite" or "Saved spot", 0.9, 0.9, 0.9)
  GT:AddLine(S:Where(sp), 0.7, 0.7, 0.7)
  GT:AddLine("Click: point the arrow here", 0.5, 0.85, 1)
  GT:AddLine("Right-click: star, rename or remove", 0.5, 0.85, 1)
  GT:Show()
end

function S:PinMenu(owner, sp)
  if not (sp and Skin.Menu) then return end
  return Skin.Menu(owner, {
    { text = "Go there", tip = "Points the arrow at this spot.", func = function() S:Go(sp.id) end },
    { text = sp.fav and "Remove the star" or "Star as a favourite", tip = "Starred spots come first in the Go to window.", func = function() S:ToggleFav(sp.id) end },
    { text = "Rename...", tip = "Give this spot another name.", func = function() S:OpenForm({ edit = sp.id }) end },
    { text = "Remove this spot", tip = "Takes this spot off your saved list. This cannot be undone.", func = function() S:Remove(sp.id) end },
  }, { width = 200 })
end

function S:NewPin(parent)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true
  p:SetSize(S.WM_PX, S.WM_PX)
  local back = p:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(Skin.TEX.CircleMask)
  back:SetPoint("TOPLEFT", p, "TOPLEFT", -2, 2); back:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 2, -2)
  local k = Skin.colors.trailInk or { 0.04, 0.05, 0.07 }
  back:SetVertexColor(k[1], k[2], k[3], 0.92)
  p.back = back
  p.tex = p:CreateTexture(nil, "OVERLAY")
  p.tex:SetAllPoints(p)
  if p.RegisterForClicks then p:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  p:SetScript("OnEnter", tipOf)
  p:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  p:SetScript("OnClick", function(self, button)
    local sp = self.spot
    if not sp then return end
    if button == "RightButton" then S:PinMenu(self, sp) else S:Go(sp.id) end
  end)
  return p
end

function S:StylePin(p, sp, px)
  p.spot = sp
  p:SetSize(px, px)
  Skin.SetGlyph(p.tex, sp.fav and "Star" or "StarEmpty", { size = px })
  local c = sp.fav and Skin.colors.goldBright or Skin.colors.accent
  if p.tex.SetVertexColor then p.tex:SetVertexColor(c[1], c[2], c[3], 1) end
end

function S:Layer()
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

-- the saved spots of one zone map
function S:Collect(map)
  local out = {}
  if not map then return out end
  for _, sp in ipairs(self:List()) do if sp.map == map then out[#out + 1] = sp end end
  return out
end

function S:Refresh()
  self.pins = self.pins or {}
  self:HookMap()
  local used = 0
  local wm, map = C.WorldMap(), C.WorldMapID()
  if M.active and Panoply.db and Panoply.db.mapSpots ~= false and wm and wm.IsShown and wm:IsShown() and map then
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
      local px = S.WM_PX / math.max(0.2, cs)
      for _, sp in ipairs(list) do
        used = used + 1
        local p = self.pins[used]
        if not p then p = self:NewPin(layer) self.pins[used] = p end
        self:StylePin(p, sp, px)
        p:ClearAllPoints()
        p:SetPoint("CENTER", layer, "TOPLEFT", sp.x * W, -sp.y * H)
        if p.SetFrameLevel then p:SetFrameLevel(markLevel) end
        p:Show()
      end
    end
  end
  for i = used + 1, #self.pins do self.pins[i]:Hide() self.pins[i].spot = nil end
  self.shown = used
  return used
end

function S:Disable()
  for _, p in ipairs(self.pins or {}) do p:Hide() end
  self.shown = 0
  if self.form then self.form:Hide() end
end

Panoply:Listen("SPOTS_CHANGED", function()
  if M.active then S:Refresh() end
  local N = M.Navigate
  if N and N.frame and N.frame:IsShown() then N:Update() end
end)
Panoply.optionHooks.mapSpots = function() if M.active then S:Refresh() end end

-------------------------------------------------------------------------------
-- /panoply spot
-------------------------------------------------------------------------------
S.USAGE = "Usage: /panoply spot  (save where you stand)   /panoply spot <name>   /panoply spot <zone> <x> <y> <name>   /panoply spot list"

function S:Slash(rest)
  rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not Panoply.Modules:IsOn("map") then Panoply:Print("Saved spots are part of the Map page, which is switched off.") return false end
  if rest == "" then self:OpenForm({ here = true }) return true end
  local low = rest:lower()
  if low == "list" then if M.Navigate then M.Navigate:Toggle() end return true end
  if low == "help" then Panoply:Print(S.USAGE) return true end
  -- "<zone> <x> <y> <name>": the first two numbers that follow each other are X and Y; what is before them is the zone
  local toks = {}
  for t in rest:gsub(",", " "):gmatch("%S+") do toks[#toks + 1] = t end
  for i = 2, #toks - 1 do
    local x, y = tonumber(toks[i]), tonumber(toks[i + 1])
    if x and y then
      local zone = table.concat(toks, " ", 1, i - 1)
      local name = table.concat(toks, " ", i + 2)
      local sp, why = self:AddTyped(zone, x, y, name)
      if sp then Panoply:Print(why and (why .. " (" .. sp.name .. ")") or ("Saved spot: %s, %s."):format(sp.name, self:Where(sp))) return true end
      Panoply:Print(why .. " " .. S.USAGE)
      return false
    end
  end
  local sp, why = self:AddHere(rest)
  if sp then Panoply:Print(why and (why .. " (" .. sp.name .. ")") or ("Saved spot: %s, %s."):format(sp.name, self:Where(sp))) return true end
  Panoply:Print(why or "That spot could not be saved.")
  return false
end
