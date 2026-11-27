-- Waypoints module (SPEC 19.7): /panoply way x y [zone] [note]
-- (also /way when no other add-on has that command), Ctrl-right-click on the world map, a waypoint list
-- with clear-all. The Panoply Suite arrow points at the first waypoint until you reach it.
local ADDON, Panoply = ...
local C, Skin, Nav = Panoply.Compat, Panoply.Skin, Panoply.Nav
local W = Panoply.Modules:Register({
  key = "waypoints", label = "Waypoints", icon = "Waypoints",
  desc = "Set your own waypoints with /way or Ctrl-right-click on the map; the arrow takes you there.",
  -- 0.7.3.7 ("Fix every size slider"): the size and opacity of the waypoint pins on the world map (Panoply.Look); there is no minimap pin
  defaults = { wayMapClick = true, waySlash = true, wayWmSize = 1, wayWmAlpha = 1 },
})
Panoply.Waypoints = W
W.ZONE_IDS = {}
for id = 1411, 1458 do W.ZONE_IDS[#W.ZONE_IDS + 1] = id end

function W:List()
  if not Panoply.cdb then return {} end
  Panoply.cdb.waypoints = Panoply.cdb.waypoints or {}
  return Panoply.cdb.waypoints
end
function W:Current() return self.active and self:List()[1] or nil end

-- Zone name -> uiMapID (case-insensitive; exact, then prefix, then substring).
function W:FindZone(text)
  if not text or text == "" then return nil end
  local q = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local exact, prefix, sub
  for _, id in ipairs(self.ZONE_IDS) do
    local n = C.MapName(id)
    if n then
      local l = n:lower()
      if l == q then exact = exact or id
      elseif l:sub(1, #q) == q then prefix = prefix or id
      elseif l:find(q, 1, true) then sub = sub or id end
    end
  end
  return exact or prefix or sub
end

-- Parse "x y", "x, y", "zone x y note", "x y zone note".
function W.Parse(msg)
  msg = msg or ""
  -- "45,2 61,8" (decimal commas) when both numbers have one; otherwise commas separate.
  if msg:find("%d+,%d+%s+%d+,%d+") then msg = msg:gsub("(%d),(%d)", "%1.%2") end
  msg = msg:gsub(",", " ")
  local toks = {}
  for t in msg:gmatch("%S+") do toks[#toks + 1] = t end
  for i = 1, #toks - 1 do
    local x, y = tonumber(toks[i]), tonumber(toks[i + 1])
    if x and y then
      local before = table.concat(toks, " ", 1, i - 1)
      local after = table.concat(toks, " ", i + 2)
      return x, y, before, after
    end
  end
  return nil
end

-- 0.9.5 phase 4K (spec 05 5.2, 05b 1.3; we 2026-11-14: one list, two views): every waypoint is in this one list. Its NEW field `src`
-- says where it came from: "trip" (a stop picked in Go to: the Map page's Trip shows these, in order), or a group of the Map page's
-- Waypoints section: "mine" (/way, Ctrl-right-click, a map icon, a death), "guide", "pet" (Class Pet's map markers), "prof"
-- (Professions) and "dungeon" (dungeon doors). A waypoint saved before 0.9.5 has none: a Go to stop (go = true) is on the trip, any
-- other is Mine (W.Group). Nothing old is renamed or rewritten.
W.GROUPS = {
  { id = "mine", label = "Mine" }, { id = "guide", label = "Guide route" }, { id = "pet", label = "Pet tames" },
  { id = "prof", label = "Professions" }, { id = "dungeon", label = "Dungeons" },
}
W.GROUP_BY = {}
for _, g in ipairs(W.GROUPS) do W.GROUP_BY[g.id] = g end
function W.Group(wp)
  if type(wp) ~= "table" then return "mine" end
  local s = wp.src
  if s == "trip" or W.GROUP_BY[s] then return s end
  return wp.go and "trip" or "mine"
end
function W.OnTrip(wp) return W.Group(wp) == "trip" end

function W:Add(m, x, y, note, quiet, src)
  if not (m and x and y) then return nil end
  if x > 1 or y > 1 then x, y = x / 100, y / 100 end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  local wp = { m = m, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000, note = note ~= "" and note or nil,
    src = (src == "trip" or W.GROUP_BY[src or ""]) and src or nil }
  local list = self:List()
  list[#list + 1] = wp
  self.fresh = self.fresh or setmetatable({}, { __mode = "k" })
  self.fresh[wp] = true   -- 0.8.1: set this session, so the player's own (Arrow:ForeignWaypoint ignores only leftovers)
  if not quiet then
    Panoply:Print(("Waypoint %d: %s %.1f, %.1f%s"):format(#list, C.MapName(m) or ("map " .. m), wp.x * 100, wp.y * 100, wp.note and (" - " .. wp.note) or ""))
  end
  Panoply:Fire("WAYPOINTS_CHANGED")
  return wp
end

function W:Remove(i)
  local list = self:List()
  if list[i] then table.remove(list, i) Panoply:Fire("WAYPOINTS_CHANGED") return true end
  return false
end
function W:RemoveCurrent() return self:Remove(1) end
-- Move a waypoint to another place in the list (the first one is the one the arrow follows). Nothing is lost: the list is only re-ordered.
function W:Move(from, to)
  local list = self:List()
  if not (list[from] and type(to) == "number") then return false end
  to = math.max(1, math.min(#list, to))
  if to == from then return false end
  local wp = table.remove(list, from)
  table.insert(list, to, wp)
  Panoply:Fire("WAYPOINTS_CHANGED")
  return true
end
function W:Reached(wp)
  local list = self:List()
  for i, v in ipairs(list) do
    if v == wp then
      table.remove(list, i)
      Panoply:Print(("Reached %s."):format(wp.note or "your waypoint") .. (list[1] and " Next waypoint set." or ""))
      Panoply:Fire("WAYPOINTS_CHANGED")
      return true
    end
  end
end
-- the waypoint's place in the list (or nil)
function W:IndexOf(wp)
  for i, v in ipairs(self:List()) do if v == wp then return i end end
  return nil
end
-- point the arrow at a waypoint: it becomes the first of the list (the one the arrow follows)
function W:Point(wp)
  local i = self:IndexOf(wp)
  if not i then return false end
  if i > 1 then self:Move(i, 1) end
  if Panoply.Arrow and Panoply.Arrow.Retarget and not Panoply:PlayAlong() then Panoply.Arrow:Retarget() end
  return true
end
-- "Add to trip": a dropped pin becomes a stop of the trip (after the stops already on it); the route plans to it like a Go to stop
function W:AddToTrip(wp)
  local i = self:IndexOf(wp)
  if not i or W.OnTrip(wp) then return false end
  wp.src, wp.go = "trip", true
  local list, last = self:List(), 0
  for k, v in ipairs(list) do if k ~= i and W.OnTrip(v) then last = k end end
  local to = last < i and last + 1 or last
  if to ~= i and to >= 1 then table.remove(list, i) table.insert(list, to, wp) end
  Panoply:Fire("WAYPOINTS_CHANGED")
  return true
end
-- the waypoints of one group ("trip" or a W.GROUPS id), in the list's order
function W:InGroup(id)
  local out = {}
  for _, wp in ipairs(self:List()) do if W.Group(wp) == id then out[#out + 1] = wp end end
  return out
end
-- "Clear group" / "Clear trip": only that group's waypoints go
function W:ClearGroup(id)
  local list, n = self:List(), 0
  for i = #list, 1, -1 do if W.Group(list[i]) == id then table.remove(list, i) n = n + 1 end end
  if n > 0 then Panoply:Fire("WAYPOINTS_CHANGED") end
  return n
end

-- Export: one "/way <zone> <x> <y> <note>" line a waypoint (what the add box and Import read back)
function W:ExportLines(id)
  local out = {}
  for _, wp in ipairs(self:List()) do
    if not id or W.Group(wp) == id then
      out[#out + 1] = ("/way %s %.1f %.1f%s"):format(C.MapName(wp.m) or ("Map " .. wp.m), wp.x * 100, wp.y * 100, wp.note and (" " .. wp.note) or "")
    end
  end
  return out
end
-- Import: lines like the export's (or the add box's), one after another; "/way", "/psway" and ";" separate them. Returns how many were
-- added and how many could not be read. They are the player's own: group Mine.
function W:Import(text, src)
  text = tostring(text or ""):gsub("\r", "\n")
  text = text:gsub("/[Pp]?[Ss]?[Hh]?[Pp]?[Ww][Aa][Yy]", "\n"):gsub(";", "\n")
  local added, bad = 0, 0
  for line in text:gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      if self:AddText(line, true, src or "mine") then added = added + 1 else bad = bad + 1 end
    end
  end
  if added > 0 then Panoply:Print(("Added %d waypoint%s."):format(added, added == 1 and "" or "s")) end
  return added, bad
end

-- one waypoint from typed words ("45.2 61.8", "Westfall 45 61 note", "45 61 Westfall note"): the waypoint, or nil and why
function W:AddText(msg, quiet, src)
  local x, y, before, after = W.Parse(msg)
  if not x then return nil, "Type the X and Y, like 45.2 61.8, with a zone before or after them if it is not this one." end
  local m
  local note = after
  if before ~= "" then m = self:FindZone(before) end
  if not m and after ~= "" then
    local words = {}
    for w in after:gmatch("%S+") do words[#words + 1] = w end
    for n = #words, 1, -1 do
      local id = self:FindZone(table.concat(words, " ", 1, n))
      if id then m = id note = table.concat(words, " ", n + 1) break end
    end
  end
  if before ~= "" and not m then return nil, "Unknown zone: " .. before end
  if not m then m = C.GetPlayerPos() end
  if not m then return nil, "Can't tell which map you are on here; add a zone name." end
  local wp = self:Add(m, x, y, note, quiet, src)
  if not wp then return nil, "X and Y must be between 0 and 100." end
  return wp
end

function W:Clear()
  local n = #self:List()
  if Panoply.cdb then Panoply.cdb.waypoints = {} end
  Panoply:Fire("WAYPOINTS_CHANGED")
  if n > 0 then Panoply:Print(("Cleared %d waypoint%s."):format(n, n == 1 and "" or "s")) end
  return n
end

function W:Slash(msg)
  msg = msg or ""
  local cmd = msg:lower():match("^%s*(%S*)")
  if cmd == "" or cmd == "list" then self:Toggle() return end
  if cmd == "clear" or cmd == "reset" then if self:Clear() == 0 then Panoply:Print("No waypoints to clear.") end return end
  local x = W.Parse(msg)
  if not x then Panoply:Print("Usage: /way 45.2 61.8 [zone] [note]  or  /way Elwynn Forest 45 61 [note]  -  /way list, /way clear") return end
  -- "x y zone note": AddText tries the longest leading run of words as a zone name
  local wp, why = self:AddText(msg, false, "mine")
  if not wp and why then Panoply:Print(why) end
  return wp
end

-- World map: Ctrl-right-click sets a waypoint where you clicked.
function W:OnMapClick(button)
  if not (self.active and Panoply.db.wayMapClick) then return end
  if button ~= "RightButton" or not C.CtrlDown() then return end
  local m = C.WorldMapID()
  local x, y = C.WorldMapCursor()
  if m and x and y then return self:Add(m, x, y, "Map pin", nil, "mine") end
end

-- Waypoint pins on the world map: 20 px at 100%; the first waypoint (the one the arrow follows) is solid, the rest a little fainter.
W.PIN_PX = 20
function W:PinAlpha(i) return (i == 1 and 1 or 0.7) * Panoply.Look.Alpha("way", "wm") end
-- Step 2 D (Look of the map): one waypoint pin is made once and styled every time it is shown, on the map and in the live preview, by
-- the same code: its size, its opacity and its colour (Waypoints > World map in the Map page's gear).
function W:BuildPin(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.tex = p:CreateTexture(nil, "OVERLAY"); p.tex:SetAllPoints(p); Skin.SetPin(p.tex, "Trail", "Waypoints")  -- skin v3: our trail pin (WoW style: the game icon)
  return p
end
function W:StylePin(p, i)
  local px = W.PIN_PX * Panoply.Look.Size("way", "wm")
  p:SetSize(px, px)
  p:SetAlpha(self:PinAlpha(i))
  Panoply.Look.Tint(p.tex, Panoply.Look.RGB("way", "wm"))
end
-- a small sample for the live preview: the first pin (solid) and a second (a little fainter), on the world map's true size
W.SAMPLE_AT = { { 38, 36 }, { 74, 26 } }
function W:DrawSample(layer, where)
  layer.pins = layer.pins or {}
  for i, at in ipairs(self.SAMPLE_AT) do
    local f = layer.pins[i]
    if not f then f = self:BuildPin(layer) f:EnableMouse(false) layer.pins[i] = f end
    if where == "wm" then
      self:StylePin(f, i)
      f:ClearAllPoints(); f:SetPoint("CENTER", layer, "TOPLEFT", at[1], -at[2])
      f:Show()
    else f:Hide() end
  end
end
Panoply.Look.Draw.way = function(layer, where) W:DrawSample(layer, where) end
function W:MapRefresh()
  local canvas, wm = C.WorldMapCanvas(), C.WorldMap()
  self.pins = self.pins or {}
  for _, p in ipairs(self.pins) do p:Hide() end
  if not (self.active and canvas and wm and wm:IsShown()) then return 0 end
  if not self.layer then self.layer = CreateFrame("Frame", nil, canvas); self.layer:SetAllPoints(canvas) end
  local lvl = C.LiftOnWorldMap(self.layer, "pins")     -- 0.6.1: above the explored map art (see Compat)
  local map = C.WorldMapID()
  local Wd, Ht = canvas:GetWidth() or 1000, canvas:GetHeight() or 667
  local n = 0
  for i, wp in ipairs(self:List()) do
    if wp.m == map then
      n = n + 1
      local p = self.pins[n]
      if not p then
        p = self:BuildPin(self.layer)
        self.pins[n] = p
      end
      if lvl and p.SetFrameLevel then p:SetFrameLevel(lvl + 2) end
      self:StylePin(p, i)
      p:ClearAllPoints(); p:SetPoint("CENTER", self.layer, "TOPLEFT", wp.x * Wd, -wp.y * Ht)
      p:Show()
    end
  end
  return n
end

-------------------------------------------------------------------------------
-- List window
-------------------------------------------------------------------------------
W.MIN_W, W.MIN_H = 340, 200
function W:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteWaypoints", 420, 300, "Waypoints", "The arrow takes you to the first one", nil, "Waypoints")
  self.frame = f
  -- 0.5.9.1: every waypoint is listed (0.5.9 showed the first 8 only); when they do not fit,
  -- the list scrolls inside the window instead of the window growing off the screen.
  f.area = Skin.ScrollArea(f)
  f.area:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -62)
  f.area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14 + 24 + Skin.SP.s)
  f.area:SetWidth(420 - 32)
  f.rows = {}
  f.empty = Skin.Text(f, 12, Panoply.Kit.Color("text.muted"))
  f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -66); f.empty:SetWidth(340)
  -- 4J: the empty state is one line; how to add one is in the ? beside it
  f.empty:SetText("No waypoints yet.")
  f.emptyHelp = Panoply.Kit.HelpIcon(f, "Add a waypoint", "Type /way 45 61 (and optionally a zone and a note), or Ctrl-right-click on the world map.", 14)
  f.emptyHelp:Hide()
  -- 0.9.5 phase 4J (spec 02 section 1, theme pass): Clear all is in the ⋯ menu and asks first (it was a button that cleared at once)
  f.more = Panoply.Kit.More(f, function()
    return { { text = "Clear all waypoints", tip = "Asks first, then removes every waypoint.",
      func = function() Panoply.Kit.Ask(f.more, "Remove every waypoint?", "Yes, clear them", function() W:Clear() end, "Keep them") end } }
  end, "Clear all waypoints (asks first).", 24)
  f.more:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16 - 12, 14)     -- 12: clear of the resize grip
  -- Nov 2026: resizable in both directions, the size remembered. Until the player drags it, the window is as tall as its
  -- list (as before); after that it keeps the height they chose and the list scrolls.
  Skin.Resizable(f, { key = "waypoints", minW = W.MIN_W, minH = W.MIN_H, onSize = function() W:Refresh() end })
  f:HookScript("OnShow", function() W:Refresh() end)   -- a hook: the open animation and Window size's fit check on open stay
  return f
end

local function makeRow(f, i)
  local r = CreateFrame("Frame", nil, f.area.content)
  r:SetHeight(26)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
  Skin.SetIcon(r.icon, "Waypoints")
  -- 0.5.5: place and distance on the first line, the note under it; both wrap and are measured
  r.text = Skin.Text(r, 12); r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -2)
  r.note = Skin.Text(r, 11, Skin.colors.inkSoft)
  r.del = Skin.IconButton(r, "x", 20, function() W:Remove(r.index) end, "Remove", "Remove this waypoint.")
  r.del:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -1)
  f.rows[i] = r
  return r
end
W.MakeRow = makeRow

function W:Refresh()
  local f = self.frame
  if not f then return end
  local list = self:List()
  local pm, px, py = C.GetPlayerPos()
  for i = 1, #list do if not f.rows[i] then makeRow(f, i) end end
  for i, r in ipairs(f.rows) do
    local wp = list[i]
    if wp then
      r.index = i
      local d = pm and Nav.Distance(pm, px, py, wp.m, wp.x, wp.y)
      r.text:SetText(("%s%s %.1f, %.1f%s"):format(i == 1 and (Skin.Code(Skin.colors.accent) .. ">|r ") or "", C.MapName(wp.m) or ("Map " .. wp.m), wp.x * 100, wp.y * 100,
        d and ("  (" .. Panoply.StepText.Distance(d) .. ")") or ""))
      r.note:SetText(wp.note or "")
      r.icon:SetAlpha(i == 1 and 1 or 0.6)
      r:Show()
    else
      r:Hide()
    end
  end
  -- measured rows; the window grows to fit them up to the screen, then the list scrolls
  local SP, TH = Skin.SP, Skin.TextHeight
  local function layout(width)
    f.area.content:SetWidth(width)
    local tw = width - 28 - 26
    local y = 0
    for _, r in ipairs(f.rows) do
      if r:IsShown() then
        r.text:SetWidth(tw); r.note:SetWidth(tw)
        local h = TH(r.text, tw) + 2
        r.note:ClearAllPoints(); r.note:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -2 - h)
        if (r.note:GetText() or "") ~= "" then h = h + TH(r.note, tw) end
        h = math.max(24, h + 4)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f.area.content, "TOPLEFT", 0, -y)
        r:SetSize(width, h)
        y = y + h + SP.xs
      end
    end
    return y
  end
  local chrome = 62 + SP.s + 24 + 14 + SP.s
  local sh = (UIParent.GetHeight and UIParent:GetHeight()) or 768
  if not sh or sh <= 0 then sh = 768 end
  local maxH = math.max(260, math.min(620, sh - 80))
  local fw = math.max(W.MIN_W, f:GetWidth() or 420)
  local full = fw - 32
  f.area:SetWidth(full)
  local contentH = layout(full)
  if #list == 0 then
    -- the line is as wide as its words, so the ? beside it never sits on it
    f.empty:Show(); f.empty:SetWidth(fw - 36 - 20)
    local ew = math.min(fw - 36 - 20, math.ceil(Skin.TextWidth(f.empty)) + 2)
    f.empty:SetWidth(ew); contentH = 4 + TH(f.empty, ew)
    f.emptyHelp:ClearAllPoints()
    f.emptyHelp:SetPoint("LEFT", f.empty, "RIGHT", SP.s, 0)
    f.emptyHelp:Show()
  else f.empty:Hide(); f.emptyHelp:Hide() end
  local h = math.max(200, math.min(maxH, contentH + chrome))
  -- a height the player chose (the grip) is kept; while the grip is being dragged the window is left as the mouse has it
  local _, userH = nil, nil
  if f.panoplyUserSize then _, userH = f:panoplyUserSize() end
  if f.panoplySizing then h = f:GetHeight() or h
  elseif userH then h = math.max(W.MIN_H, userH) end
  if not f.panoplySizing then f:SetHeight(h) end
  f.area:SetHeight(h - chrome + SP.s)
  if contentH > h - chrome + SP.s + 0.5 then contentH = layout(f.area:ContentWidth(contentH)) end
  f.area:SetContentHeight(#list == 0 and 0 or contentH)
  f.area.content:SetWidth(f.area:ContentWidth(contentH))
  f.more:SetEnabledLook(#list > 0)
end
function W:Toggle()
  self:Create()
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() self:Refresh() end
end

-- Whether any add-on other than this module has a slash command spelled /way (the globals SLASH_<NAME><n>).
-- The same technique as PanoplyGuide's own wayTaken (addon/PanoplyGuide/Nav/Journey.lua); PanoplyGuide's /way counts as taken too.
function W.WayTaken()
  for key, value in pairs(_G) do
    if type(key) == "string" and type(value) == "string" and key:find("^SLASH_") and not key:find("^SLASH_HEARTHPATHWAY%d")
      and value:lower() == "/way" then
      return true
    end
  end
  return false
end

function W:Enable()
  if not self.hooked then
    self.hooked = true
    local wm = C.WorldMap()
    local sc = wm and wm.ScrollContainer
    if sc and sc.HookScript then sc:HookScript("OnMouseUp", function(_, button) W:OnMapClick(button) end) end
    if wm and wm.HookScript then wm:HookScript("OnShow", function() W:MapRefresh() end) end
    if wm then C.Hook(wm, "OnMapChanged", function() W:MapRefresh() end) end
  end
  -- Nov 14 2026 (website claim: "/way (unless another add-on already provides that command)"): /psway and /hpway are ours and
  -- clash with nothing, so they are always registered; /way is added only when the setting is on AND no add-on has a slash
  -- command spelled /way (W.WayTaken scans every SLASH_* global). This runs from the module's Enable, which
  -- is called from Panoply:OnLogin (PLAYER_LOGIN), after every add-on's files have loaded, so a command registered at load is seen.
  if _G.SlashCmdList then
    local names = {}
    if Panoply.db.waySlash and not W.WayTaken() then names[#names + 1] = "/way" end
    names[#names + 1] = "/psway"   -- 0.8.0: the short form is ps; /hpway still works, unadvertised
    names[#names + 1] = "/hpway"
    -- the game reads SLASH_<NAME>1, 2, 3 ... until the first gap, so the numbers run on without one
    for i = 1, 3 do _G["SLASH_HEARTHPATHWAY" .. i] = names[i] end
    _G.SlashCmdList.HEARTHPATHWAY = function(msg) if W.active then W:Slash(msg) else Panoply:Print("Waypoints are off (switch them on in " .. Panoply:SettingsPath("waySlash") .. ").") end end
    self.slashRegistered = true
    self.wayClaimed = names[1] == "/way"
  end
  Panoply:Fire("WAYPOINTS_CHANGED")
end
function W:Disable()
  if self.frame then self.frame:Hide() end
  self:MapRefresh()
  Panoply:Fire("WAYPOINTS_CHANGED")
end
W:Listen("WAYPOINTS_CHANGED", function() W:Refresh() W:MapRefresh() end)
for _, what in ipairs({ "size", "alpha", "colour" }) do
  Panoply.optionHooks[Panoply.Look.Key("way", "wm", what)] = function() W:MapRefresh() end
end
-- a change of icon style puts the pin's picture back as it was: the colour is put on again
Panoply:Listen("ICON_STYLE_CHANGED", function() W:MapRefresh() end)

W.options = {
  { type = "check", key = "wayMapClick", label = "Ctrl-right-click on the world map sets a waypoint" },
  { type = "check", key = "waySlash", label = "Use /way (when no other add-on has it)", tip = "Takes effect after /reload." },
  { type = "button", label = "Open the waypoint list", func = function() W:Toggle() end },
}
-- 0.7.3.7: Waypoints have Size and Opacity for the world map (no minimap pin)
for _, r in ipairs(Panoply.Look.Rows("way")) do W.options[#W.options + 1] = r end
