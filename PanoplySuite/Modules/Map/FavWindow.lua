-- Map module, the FAVORITES WINDOW (0.9.5 phase 4G, queue item 1): the list of every map favorite, the form that adds or edits one, the
-- icon picker, and the share and import windows. The engine and the pins are Favorites.lua; this file only draws and asks it.
--   List     opened from the Places menu on the world map's toolbar ("Favorites"), the pins' right-click menu, the Map page and
--            /panoply fav. This zone or All zones, By name or By distance, which types show (a tick each), Only mine (this
--            character). Each row: the icon, the name, its type, place and distance (the note in its tooltip), Show on map, Show me
--            the way, and a menu with Edit, Share and Delete. Under the list: Add where I stand, Add my target, Import, Share these.
--   Form     a name, a type (a trainer also gets its profession), a note, an icon (the type's own, or one picked), the zone and X, Y
--            (filled in from a click on the map, where you stand or your target; every field can be changed).
--   Icons    a search box and a grid of the game's own icons; picking one sets the form's icon.
--   Share    the text line, selected, to copy; Import reads a pasted line and says what it added.
-- Uses the suite's shared pieces (windows, dropdowns, ticks, buttons, the copy window); no Polestar name or art is shown.
local ADDON, Panoply = ...
local C, Skin, Kit, M = Panoply.Compat, Panoply.Skin, Panoply.Kit, Panoply.Map
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local FW = {}
M.FavWindow = FW
local function F() return M.Favorites end
FW.W, FW.H = 500, 520
FW.ROW_H = 40
FW.FORM_W = 420
FW.state = { zone = "all", sort = "name" }
FW.draft = { type = "custom" }   -- what the form holds now (its type, profession and picked icon)
FW.WORDS = {
  empty = "No favorites yet. Alt-right-click the world map, or use Add where I stand or Add my target.",
  emptyZone = "No favorite in this zone. Choose All zones to see the others.",
  hint = "Tip: Alt-right-click the world map to add the place you clicked.",
  shareIntro = "The line below is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it to a friend. Import reads it back.",
  importIntro = "Paste a shared favorites line (it begins with PSF1:) and click Import. Favorites you already have are skipped.",
}

local function plainBox(parent, w, placeholder, onEnter)
  local box = Skin.Input(parent, w, 24, placeholder)
  if box.icon then box.icon:Hide() end
  if box.SetTextInsets then box:SetTextInsets(8, 6, 0, 0) end
  if box.placeholder then box.placeholder:ClearAllPoints(); box.placeholder:SetPoint("LEFT", box, "LEFT", 8, 0) end
  box:SetScript("OnTextChanged", function(b)
    if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end
  end)
  if onEnter then box:SetScript("OnEnterPressed", onEnter) end
  return box
end
local function setBox(box, text)
  box:SetText(text or "")
  if box.placeholder then if (text or "") == "" then box.placeholder:Show() else box.placeholder:Hide() end end
end
local function label(parent, text)
  local t = Skin.Label(parent, 10, Skin.colors.inkSoft)
  t:SetText(text)
  return t
end
local function put(fs, parent, x, y, w)
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); fs:SetWidth(w)
  local h = ceil(TH(fs, w)); fs:SetHeight(h)
  return h
end

-------------------------------------------------------------------------------
-- The list window
-------------------------------------------------------------------------------
FW.ZONES = { { value = "here", text = "This zone" }, { value = "all", text = "All zones" } }
FW.SORTS = { { value = "name", text = "By name" }, { value = "distance", text = "By distance" } }

function FW:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteFavorites", FW.W, FW.H, "Map favorites", "Your own places, for every character", nil, "Star")   -- 4J: its own header icon
  self.frame = f
  f.zoneDD = Kit.Dropdown(f, { width = 140, height = 24, tip = "Which zone", tipBody = "Favorites in the zone you are in, or in every zone.",
    items = FW.ZONES, get = function() return FW.state.zone end, set = function(v) FW.state.zone = v end, onChange = function() FW:Layout() end })
  f.sortDD = Kit.Dropdown(f, { width = 140, height = 24, tip = "Order", tipBody = "By name, or the nearest first (favorites in other zones come after).",
    items = FW.SORTS, get = function() return FW.state.sort end, set = function(v) FW.state.sort = v end, onChange = function() FW:Layout() end })
  f.types = Skin.Button(f, "Types", 90, 24, function(b) FW:TypesMenu(b) end, "Types", "Which types of favorite show, on the maps and in this list.")
  f.mine = Skin.Check(f, "Only mine", { get = function() return F():OnlyMine() end, set = function(v) F():SetOnlyMine(v) end },
    nil, "Only mine", "This character shows only the favorites it saved itself. The others stay saved for your other characters.")
  f.count = Skin.Ink(f, 11, Kit.Color("text.muted"))
  if f.count.SetJustifyH then f.count:SetJustifyH("RIGHT") end
  f.area = Skin.ScrollArea(f)
  f.none = Skin.Ink(f.area.content, 12, Kit.Color("text.muted"))
  f.rows = {}
  f.here = Skin.Button(f, "Add where I stand", 140, 26, function() FW:OpenForm({ here = true }) end, "Add where I stand",
    "A new favorite at your character's position.")
  f.target = Skin.Button(f, "Add my target", 120, 26, function() FW:OpenForm({ target = true }) end, "Add my target",
    "A new favorite for your target: a vendor, a trainer or a creature. Its name, kind and place are filled in where Panoply Suite knows them.")
  f.import = Skin.Button(f, "Import", 90, 26, function() FW:OpenImport() end, "Import", "Add favorites from a shared line a friend sent you.")
  f.shareAll = Skin.Button(f, "Share these", 110, 26, function() FW:Share(FW:ShownIds()) end, "Share these",
    "A text line of every favorite listed here, to copy and paste to a friend.")
  f.buttons = { f.here, f.target, f.import, f.shareAll }
  f.hint = Skin.Ink(f, 11, Kit.Color("text.muted"))
  f.hint:SetText(FW.WORDS.hint)
  Skin.Resizable(f, { key = "favorites", minW = 400, minH = 360, onSize = function(_, _, done) if done and f:IsShown() then FW:Layout() end end })
  if f.HookScript then f:HookScript("OnShow", function() FW:Layout() end) end
  return f
end

function FW:Open()
  local f = self:Create()
  f:Show()
  self:Layout()
  return f
end
function FW:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() return end
  self:Open()
end
function FW:Hide()
  for _, w in ipairs({ self.frame, self.form, self.icons, self.importWin }) do if w then w:Hide() end end
end
function FW:Changed()
  if self.frame and self.frame:IsShown() then self:Layout() end
end

function FW:TypesMenu(owner)
  local items = {}
  for _, t in ipairs(F().TYPES) do
    -- a switch row: the menu stays open, so several types can be changed at once
    items[#items + 1] = { text = t.label, switch = function() return F():TypeShown(t.key) end,
      tip = "Show or hide every " .. t.label:lower() .. " favorite on the maps and in this list.",
      func = function() F():SetTypeShown(t.key, not F():TypeShown(t.key)) end }
  end
  local m = Skin.Menu(owner, items, { width = 240 })
  -- as wide as the longest type beside its switch (larger text needs more): measured on the menu's own rows
  local need = 0
  for _, r in ipairs(m and m.rows or {}) do
    if r:IsShown() and r.sw and r.sw:IsShown() then need = max(need, 6 + 8 + ceil(TW(r.text)) + SP.m + ceil(r.sw:GetWidth() or 0) + 6 + 6) end
  end
  if m and need > (m:GetWidth() or 0) then m:SetWidth(need) end
  return m
end

-- what the list shows now: { favorites }, and the zone it is filtered to
function FW:Rows()
  local zone
  if self.state.zone == "here" then zone = C.GetPlayerPos() end
  local list = F():List({ zone = zone, sort = self.state.sort, shown = true })
  return list, zone
end
function FW:ShownIds()
  local ids = {}
  for _, f in ipairs((self:Rows())) do ids[#ids + 1] = f.id end
  return ids
end

-- Delete asks first: "Delete <name>?" with Yes and Cancel (a delete cannot be undone)
function FW:ConfirmDelete(owner, fav, after)
  if not fav then return nil end
  return Skin.Menu(owner, {
    { header = ("Delete %s?"):format(fav.name) },
    { text = "Yes, delete it", tip = "Takes it off your favorites, for every character. This cannot be undone.",
      func = function() F():Remove(fav.id) if after then after() end end },
    { text = "Cancel", tip = "Keeps it.", func = function() end },
  }, { width = 230 })
end

local function rowMenu(owner, fav)
  return Skin.Menu(owner, {
    { text = "Edit...", tip = "Change its name, type, note, icon or place.", func = function() FW:OpenForm({ edit = fav.id }) end },
    { text = "Share...", tip = "A text line of this favorite to copy.", func = function() FW:Share({ fav.id }) end },
    { text = "Delete...", tip = "Asks first, then takes it off your favorites. This cannot be undone.", func = function() FW:ConfirmDelete(owner, fav) end },
  }, { width = 170 })
end

function FW:Row(i)
  local f = self.frame
  local r = f.rows[i]
  if r then return r end
  local cd = f.area.content
  r = CreateFrame("Button", nil, cd)
  r:SetHeight(FW.ROW_H)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); Skin.Solid(r.hl, Kit.Color("surface.2"), 1); r.hl:SetAllPoints(r); r.hl:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.name = Skin.Text(r, 12, Kit.Color("text.primary"), nil, "semi")
  r.line = Skin.Ink(r, 11, Kit.Color("text.muted"))
  for _, fs in ipairs({ r.name, r.line }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  r.map = Skin.IconButton(r, "Map", 22, function(b) if b.fav then F():Show(b.fav.id) end end, "Show on the map", "Opens the world map on it and rings the spot.")
  r.go = Skin.IconButton(r, "Arrow", 22, function(b) if b.fav then F():Go(b.fav.id) end end, "Show me the way", "Plans the trip there; the arrow follows it.")
  r.more = Skin.IconButton(r, "Gear", 22, function(b) if b.fav then rowMenu(b, b.fav) end end, "Edit, share or delete", "Edit, share or delete this favorite.")
  r.more.panoplyKitIcon = "icon.ui.more"
  r:SetScript("OnEnter", function(self) self.hl:Show() if self.fav then F():Tip(self, self.fav) end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  r:SetScript("OnClick", function(self, button)
    if not self.fav then return end
    if button == "RightButton" then rowMenu(self, self.fav) else F():Show(self.fav.id) end
  end)
  f.rows[i] = r
  return r
end

function FW:Layout()
  local f = self.frame
  if not f then return end
  local pad = 16
  local W = f:GetWidth() or FW.W
  local inner = W - 2 * pad
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  -- the filters: zone, order, types; then Only mine and the count
  local zw = f.zoneDD:Fit(110, 160)
  local sw = f.sortDD:Fit(110, 160)
  local tw = Skin.FitButton(f.types, 70, 140)
  f.zoneDD:ClearAllPoints(); f.zoneDD:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
  local x = pad + zw + SP.s
  if x + sw > pad + inner then y = y + 24 + SP.s x = pad end
  f.sortDD:ClearAllPoints(); f.sortDD:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
  x = x + sw + SP.s
  if x + tw > pad + inner then y = y + 24 + SP.s x = pad end
  f.types:ClearAllPoints(); f.types:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
  y = y + 24 + SP.s
  f.mine:ClearAllPoints(); f.mine:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y - 3)
  f.mine:Refresh()
  local mw = 18 + 9 + ceil(TW(f.mine.label)) + 4
  local list, zone = self:Rows()
  local total = F():Count()
  local words = (#list == total) and ("%d %s"):format(total, total == 1 and "favorite" or "favorites")
    or ("%d of %d shown"):format(#list, total)
  f.count:SetText(words)
  local cw = max(40, inner - mw - SP.m)
  f.count:ClearAllPoints(); f.count:SetPoint("TOPRIGHT", f, "TOPLEFT", pad + inner, -y - 3); f.count:SetWidth(cw)
  Skin.Ellipsize(f.count, words, cw); f.count:SetHeight(ceil(TH(f.count, cw)))
  y = y + 24 + SP.s
  -- the buttons and the tip at the bottom; the list takes what is left
  local bh = Skin.FlowButtons(f, f.buttons, pad, 0, inner, SP.s, 80, true)
  f.hint:SetWidth(inner)
  local hh = ceil(TH(f.hint, inner))
  local bottom = pad + bh + SP.s + hh + SP.s
  local H = f:GetHeight() or FW.H
  local viewH = max(80, H - y - bottom)
  local area = f.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); area:SetSize(inner, viewH)
  -- the rows' height decides whether the scroll bar shows: laid out once at the full width, and again beside the bar when they need it
  local cd = area.content
  local cw2, ry
  for pass = 1, 2 do
  cw2 = pass == 1 and area:ContentWidth(0) or area:ContentWidth(ry + viewH + 1)
  cd:SetWidth(cw2)
  ry = 0
  for i, fav in ipairs(list) do
    local r = self:Row(i)
    r.fav = fav
    r.map.fav, r.go.fav, r.more.fav = fav, fav, fav
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", cd, "TOPLEFT", 0, -ry); r:SetWidth(cw2)
    F().SetIcon(r.icon, fav)
    local bx = cw2 - 4 - 22
    r.more:ClearAllPoints(); r.more:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.go:ClearAllPoints(); r.go:SetPoint("RIGHT", r.more, "LEFT", -SP.xs, 0)
    r.map:ClearAllPoints(); r.map:SetPoint("RIGHT", r.go, "LEFT", -SP.xs, 0)
    bx = bx - 2 * (22 + SP.xs)
    local tx = 4 + 24 + SP.s
    local twid = max(40, bx - SP.s - tx)
    r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", r, "TOPLEFT", tx, -4); r.name:SetWidth(twid)
    Skin.Ellipsize(r.name, fav.name, twid); r.name:SetHeight(ceil(TH(r.name, twid)))
    local pos = zone and ("%.1f, %.1f"):format(fav.x * 100, fav.y * 100) or F():Where(fav)
    local dist = F():Distance(fav)
    local line = F():TypeLabel(fav) .. " · " .. pos .. (dist and (" · %d yards"):format(floor(dist + 0.5)) or "")
    r.line:ClearAllPoints(); r.line:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2); r.line:SetWidth(twid)
    Skin.Ellipsize(r.line, line, twid); r.line:SetHeight(ceil(TH(r.line, twid)))
    -- the row is as tall as its two lines (1.3x text needs more than the standard height)
    local rh = max(FW.ROW_H, 4 + ceil(r.name:GetHeight() or 0) + 2 + ceil(r.line:GetHeight() or 0) + 4)
    r:SetHeight(rh)
    ry = ry + rh
    r:Show()
  end
  if ry <= viewH or area:ContentWidth(ry) == cw2 then break end
  end
  for i = #list + 1, #f.rows do f.rows[i]:Hide() f.rows[i].fav = nil end
  if #list == 0 then
    local t = (total > 0 and zone) and FW.WORDS.emptyZone or (total > 0 and "Every favorite is hidden by the Types or Only mine choices." or FW.WORDS.empty)
    f.none:SetText(t)
    put(f.none, cd, 4, 4, cw2 - 8)
    f.none:Show()
    area:SetContentHeight(ceil(TH(f.none, cw2 - 8)) + 8)
  else
    f.none:Hide()
    area:SetContentHeight(ry)
  end
  area:UpdateBar()
  -- the buttons and the tip
  local by = (H - pad - bh)
  Skin.FlowButtons(f, f.buttons, pad, -by, inner, SP.s, 80)
  f.hint:ClearAllPoints(); f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(by - SP.s - hh)); f.hint:SetWidth(inner); f.hint:SetHeight(hh)
  if f.shareAll.SetEnabledLook then f.shareAll:SetEnabledLook(#list > 0) end
  self.list = list
end

-------------------------------------------------------------------------------
-- The form: a new favorite, or one to change
-------------------------------------------------------------------------------
FW.PROF_ITEMS = {}
for _, p in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring",
  "Cooking", "First Aid", "Fishing", "Class" }) do
  FW.PROF_ITEMS[#FW.PROF_ITEMS + 1] = { value = p, text = p == "Class" and "Class trainer" or p }
end
table.insert(FW.PROF_ITEMS, 1, { value = "", text = "Any profession" })

function FW:CreateForm()
  if self.form then return self.form end
  local f = Skin.Window("PanoplySuiteFavForm", FW.FORM_W, 460, "Add a favorite", "Kept for every character on this account", nil, "NodeChest")   -- 4J: its own header icon
  self.form = f
  local save = function() FW:FormSave() end
  f.lName, f.inName = label(f, "NAME"), plainBox(f, 200, "Brannock, cooking supplies", save)
  f.lType = label(f, "TYPE")
  f.typeDD = Kit.Dropdown(f, { width = 200, height = 24, tip = "Type", tipBody = "What kind of place this is. It sets the icon, unless you pick one.",
    items = function() local t = {} for _, x in ipairs(F().TYPES) do t[#t + 1] = { value = x.key, text = x.label } end return t end,
    get = function() return FW.draft.type end, set = function(v) FW.draft.type = v end, onChange = function() FW:LayoutForm() end })
  f.profDD = Kit.Dropdown(f, { width = 170, height = 24, tip = "Profession", tipBody = "The profession this trainer teaches; its icon is the profession's.",
    items = FW.PROF_ITEMS, get = function() return FW.draft.prof or "" end, set = function(v) FW.draft.prof = v ~= "" and v or nil end,
    onChange = function() FW:LayoutForm() end })
  f.lNote, f.inNote = label(f, "NOTE (SHOWN IN THE TOOLTIP)"), plainBox(f, 200, "Sells Simple Flour; restocks often", save)
  f.lIcon = label(f, "ICON")
  f.iconTex = f:CreateTexture(nil, "ARTWORK"); f.iconTex:SetSize(28, 28)
  f.iconPick = Skin.Button(f, "Choose an icon", 130, 24, function() FW:OpenIcons() end, "Choose an icon", "Pick any of the game's own icons.")
  f.iconReset = Skin.Button(f, "The type's icon", 130, 24, function() FW.draft.icon = nil FW:LayoutForm() end, "The type's icon",
    "Back to the icon of the type (a trainer: its profession).")
  f.lZone, f.inZone = label(f, "ZONE"), plainBox(f, 200, "Elwynn Forest", save)
  f.lX, f.inX = label(f, "X"), plainBox(f, 60, "45.2", save)
  f.lY, f.inY = label(f, "Y"), plainBox(f, 60, "61.8", save)
  f.here = Skin.Button(f, "Where I stand", 120, 24, function() FW:FormFill(F():Here()) end, "Where I stand",
    "Fills in the zone and the position your character stands at now.")
  f.tgt = Skin.Button(f, "My target", 100, 24, function() FW:FormFill(F():FromTarget()) end, "My target",
    "Fills in your target's name, kind and place.")
  f.save = Skin.Button(f, "Save", 80, 26, save, "Save", "Saves this favorite. It shows on the maps and in the Favorites window.")
  f.cancel = Skin.Button(f, "Cancel", 80, 26, function() f:Hide() end, "Cancel", "Closes this window without saving.")
  f.delete = Skin.Button(f, "Delete", 80, 26, function(b)
    local fav = FW.formEdit and F():Get(FW.formEdit)
    if fav then FW:ConfirmDelete(b, fav, function() f:Hide() end) else f:Hide() end
  end, "Delete", "Asks first, then takes this favorite off your list. This cannot be undone.")
  f.msg = Skin.Text(f, 11, Skin.colors.inkSoft)
  Skin.Resizable(f, { key = "favForm", minW = FW.FORM_W, minH = 200, onSize = function(_, _, done) if done and f:IsShown() then FW:LayoutForm() end end })
  return f
end

function FW:LayoutForm()
  local f = self.form
  if not f then return end
  local d = self.draft or {}
  local pad = 16
  local W = f:GetWidth() or FW.FORM_W
  local inner = W - 2 * pad
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  local function field(lab, box, x, w)
    local lh = put(lab, f, x, y, w)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + lh + 2)); box:SetWidth(w)
    return lh + 2 + 24
  end
  y = y + field(f.lName, f.inName, pad, inner) + SP.m
  -- the type, and the profession beside it for a trainer
  local lh = put(f.lType, f, pad, y, inner)
  local ty = y + lh + 2
  local tw = f.typeDD:Fit(150, min(inner, 230))
  f.typeDD:ClearAllPoints(); f.typeDD:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -ty)
  if d.type == "trainer" then
    local pw = f.profDD:Fit(130, min(inner, 200))
    f.profDD:ClearAllPoints()
    if tw + SP.s + pw <= inner then f.profDD:SetPoint("TOPLEFT", f, "TOPLEFT", pad + tw + SP.s, -ty)
    else ty = ty + 24 + SP.s f.profDD:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -ty) end
    f.profDD:Show()
  else f.profDD:Hide() end
  y = ty + 24 + SP.m
  y = y + field(f.lNote, f.inNote, pad, inner) + SP.m
  -- the icon: the picture, Choose an icon, and The type's icon when one was picked
  lh = put(f.lIcon, f, pad, y, inner)
  local iy = y + lh + 2
  F().SetIcon(f.iconTex, { type = d.type, prof = d.prof, icon = d.icon })
  f.iconTex:ClearAllPoints(); f.iconTex:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -iy)
  local cw = Skin.FitButton(f.iconPick, 100, inner - 28 - SP.s)
  f.iconPick:ClearAllPoints(); f.iconPick:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 28 + SP.s, -(iy + 2))
  local rw = Skin.FitButton(f.iconReset, 100, inner - 28 - SP.s)
  f.iconReset:ClearAllPoints()
  local rowH = 28
  if d.icon then
    if 28 + SP.s + cw + SP.s + rw <= inner then f.iconReset:SetPoint("TOPLEFT", f.iconPick, "TOPRIGHT", SP.s, 0)
    else f.iconReset:SetPoint("TOPLEFT", f.iconPick, "BOTTOMLEFT", 0, -SP.s) rowH = 2 + 24 + SP.s + 24 end
    f.iconReset:Show()
  else f.iconReset:Hide() end
  y = iy + rowH + SP.m
  y = y + field(f.lZone, f.inZone, pad, inner) + SP.m
  -- X and Y, then Where I stand and My target beside them when they fit
  local half = 70
  local xh = field(f.lX, f.inX, pad, half)
  field(f.lY, f.inY, pad + half + SP.m, half)
  local bw1 = Skin.FitButton(f.here, 90, inner)
  local bw2 = Skin.FitButton(f.tgt, 80, inner)
  local lx = ceil(TH(f.lX, half))
  local bx = pad + 2 * half + SP.m + SP.l
  f.here:ClearAllPoints(); f.tgt:ClearAllPoints()
  if bx + bw1 + SP.s + bw2 <= pad + inner then
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -(y + lx + 2))
    f.tgt:SetPoint("TOPLEFT", f.here, "TOPRIGHT", SP.s, 0)
    y = y + xh + SP.m
  else
    y = y + xh + SP.s
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
    if bw1 + SP.s + bw2 <= inner then f.tgt:SetPoint("TOPLEFT", f.here, "TOPRIGHT", SP.s, 0)
    else y = y + 24 + SP.s f.tgt:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y) end
    y = y + 24 + SP.m
  end
  -- the message, then Save / Cancel (/ Delete)
  local msg = self.formMsg
  f.msg:SetText(msg and msg.text or "")
  local c = msg and msg.bad and Skin.colors.warn or Skin.colors.inkSoft
  f.msg:SetTextColor(c[1], c[2], c[3], 1)
  if msg then y = y + put(f.msg, f, pad, y, inner) + SP.s f.msg:Show() else f.msg:Hide() end
  local btns = { f.save, f.cancel }
  if self.formEdit then btns[#btns + 1] = f.delete f.delete:Show() else f.delete:Hide() end
  local bh = Skin.FlowButtons(f, btns, pad, -y, inner, SP.s, 70)
  y = y + max(bh, 26) + pad
  f:SetHeight(y)
end

-- fill the form from a place (where I stand, my target): a table, or nil and why
function FW:FormFill(t, why)
  local f = self.form
  if not f then return end
  if not t then
    self.formMsg = { text = why or "Panoply Suite can't tell where that is.", bad = true }
  else
    self.formMsg = t.fromData == false and { text = "Your target is not in the map data here, so the place is where you stand." } or nil
    self:FormZone(t.map)
    setBox(f.inX, ("%.1f"):format(t.x * 100)); setBox(f.inY, ("%.1f"):format(t.y * 100))
    local cur = F().Clean(f.inName:GetText() or "")
    if (cur == "" or self.formFilledName == cur) and t.name and t.name ~= "" then
      setBox(f.inName, t.name) self.formFilledName = F().Clean(t.name)
    end
    if t.type and t.type ~= "custom" then self.draft.type = t.type self.draft.prof = t.prof end
  end
  f.typeDD:Refresh(); f.profDD:Refresh()
  self:LayoutForm()
end

-- Open the form. opts: { map, x, y } a place to start from (a click on the map); { here = true } where the character stands;
-- { target = true } the target; { edit = id } a favorite to change; nothing: empty, to type a zone, X and Y.
function FW:OpenForm(opts)
  opts = opts or {}
  local f = self:CreateForm()
  self.formMsg, self.formEdit, self.formFilledName = nil, nil, nil
  local fav = opts.edit and F():Get(opts.edit)
  if fav then
    self.formEdit = fav.id
    self.draft = { type = fav.type, prof = fav.prof, icon = fav.icon }
    setBox(f.inName, fav.name); setBox(f.inNote, fav.note or "")
    self:FormZone(fav.map); setBox(f.inX, ("%.1f"):format(fav.x * 100)); setBox(f.inY, ("%.1f"):format(fav.y * 100))
    if f.panoplyTitle and f.panoplyTitle.SetText then f.panoplyTitle:SetText("Edit a favorite") end
  else
    self.draft = { type = opts.type or "custom" }
    if f.panoplyTitle and f.panoplyTitle.SetText then f.panoplyTitle:SetText("Add a favorite") end
    setBox(f.inName, opts.name or ""); setBox(f.inNote, "")
    if opts.map and opts.x and opts.y then
      self:FormZone(opts.map); setBox(f.inX, ("%.1f"):format(opts.x * 100)); setBox(f.inY, ("%.1f"):format(opts.y * 100))
    else
      self:FormZone(nil); setBox(f.inX, ""); setBox(f.inY, "")
    end
  end
  f.typeDD:Refresh(); f.profDD:Refresh()
  f:Show()
  if opts.here and not fav then self:FormFill(F():Here()) end
  if opts.target and not fav then self:FormFill(F():FromTarget()) end
  self:LayoutForm()
  if f.inName.SetFocus then f.inName:SetFocus() end
  return f
end

-- the zone box, and the map it was filled with: a map the zone search does not list (a continent, a city map, an imported one) or one
-- that shares its name with another is kept as long as the player leaves the zone's name as it was
function FW:FormZone(map)
  local f = self.form
  local name = map and C.MapName(map) or ""
  setBox(f.inZone, name)
  self.formMap, self.formZoneText = map, name
end

function FW:FormSave()
  local f = self.form
  if not f then return nil end
  local Sp = M.Spots
  local zone = f.inZone:GetText() or ""
  local map
  if self.formMap and zone == self.formZoneText then map = self.formMap
  else map = Sp and Sp.FindZone and Sp:FindZone(zone) end
  if not map then
    self.formMsg = { text = ("No zone is called \"%s\". Type its name as the map shows it."):format(zone), bad = true }
    self:LayoutForm()
    return nil
  end
  local t = { name = f.inName:GetText() or "", type = self.draft.type, prof = self.draft.prof, note = f.inNote:GetText() or "",
    icon = self.draft.icon, map = map, x = tostring(f.inX:GetText() or ""):gsub(",", "."), y = tostring(f.inY:GetText() or ""):gsub(",", ".") }
  local fav, why
  if self.formEdit then
    if t.icon == nil then t.icon = false end
    if t.note == "" then t.note = false end
    if t.prof == nil then t.prof = false end
    fav, why = F():Update(self.formEdit, t)
  else
    fav, why = F():Add(t)
  end
  if not fav then
    self.formMsg = { text = why or "That favorite could not be saved.", bad = true }
    self:LayoutForm()
    return nil
  end
  Panoply:Print(self.formEdit and ("Favorite changed: %s."):format(fav.name)
    or (why and (why .. " (" .. fav.name .. ")") or ("Favorite saved: %s, %s."):format(fav.name, F():Where(fav))))
  f:Hide()
  if self.icons then self.icons:Hide() end
  return fav
end

-------------------------------------------------------------------------------
-- The icon picker: the game's own icons, searched by name
-------------------------------------------------------------------------------
FW.ICON_PX, FW.ICON_GAP, FW.ICON_MAX = 32, 4, 160
-- the named icons offered first (all ship with the game; the same names the rest of Panoply Suite already uses)
FW.ICON_NAMES = { "INV_Misc_Bag_10", "INV_Misc_Bag_07", "INV_Misc_Bag_08", "INV_Misc_Coin_01", "INV_Misc_Coin_02", "INV_Misc_Coin_03",
  "INV_Misc_Coin_05", "INV_Misc_Coin_17", "INV_Box_01", "INV_Box_02", "INV_Misc_Map_01", "INV_Misc_Map_02", "INV_Misc_Spyglass_02",
  "INV_Misc_Note_01", "INV_Misc_Note_02", "INV_Misc_Book_01", "INV_Misc_Book_07", "INV_Misc_Book_09", "INV_Misc_Book_11", "INV_Scroll_03",
  "INV_Misc_Key_03", "INV_Misc_Key_14", "INV_Misc_Gem_01", "INV_Misc_Gem_Emerald_02", "INV_Misc_Gem_Pearl_04", "INV_Misc_Gem_Sapphire_02",
  "INV_Misc_Rune_01", "INV_Misc_Eye_01", "INV_Misc_Gear_01", "INV_Gizmo_02", "INV_Misc_PocketWatch_01", "INV_Misc_PocketWatch_02",
  "INV_Misc_Bone_HumanSkull_01", "INV_Misc_Bone_ElfSkull_01", "INV_Misc_Head_Dragon_01", "INV_Misc_Head_Human_01", "INV_Misc_Fish_02",
  "INV_Misc_Flower_02", "INV_Misc_Food_15", "INV_Misc_Pelt_Wolf_01", "INV_Misc_ArmorKit_17", "INV_Ore_Copper_01", "INV_Sword_04",
  "INV_Musket_04", "INV_Chest_Chain_05", "INV_Chest_Cloth_17", "INV_Shirt_GuildTabard_01", "INV_BannerPVP_01", "INV_BannerPVP_02",
  "INV_Box_PetCarrier_01", "INV_Pet_Broom", "INV_ValentinesCard01", "INV_Misc_QuestionMark", "Ability_Mount_Gryphon_01",
  "Ability_Mount_Wyvern_01", "Ability_Hunter_Pathfinding", "Ability_Hunter_Pet_Bear", "Ability_EyeOfTheOwl", "Ability_Repair",
  "Ability_Rogue_Sprint", "Ability_Warrior_Challange", "Ability_Warrior_SavageBlow", "Spell_Fire_Fire", "Spell_Holy_Heal",
  "Spell_Holy_PrayerOfHealing02", "Spell_Holy_SealOfSacrifice", "Spell_Holy_Surgeoflight", "Spell_Shadow_DetectInvisibility",
  "Trade_Alchemy", "Trade_BlackSmithing", "Trade_Engineering", "Trade_Engraving", "Trade_Fishing", "Trade_Herbalism", "Trade_Mining",
  "Trade_Tailoring" }
-- every icon the picker can show: { tex, name (lower case, for the search) }. The named list, the types' and professions' own icons, then
-- the game's macro icon list (file numbers, found by "#" and their number) where the client has one.
function FW:IconList()
  if self.iconList then return self.iconList end
  local out, seen = {}, {}
  local function add(tex, name)
    if tex and not seen[tex] then seen[tex] = true out[#out + 1] = { tex = tex, name = name:lower() } end
  end
  for _, t in ipairs(F().TYPES) do add(t.icon, t.label .. " " .. tostring(t.icon):match("([^\\]+)$")) end
  for p, tex in pairs(F().PROF_ICON) do if p:sub(1, 1):match("%u") then add(tex, p .. " " .. tostring(tex):match("([^\\]+)$")) end end
  for _, n in ipairs(FW.ICON_NAMES) do add("Interface\\Icons\\" .. n, n:gsub("_", " ") .. " " .. n) end
  table.sort(out, function(a, b) return a.name < b.name end)
  for _, fnName in ipairs({ "GetMacroIcons", "GetMacroItemIcons" }) do
    local fn = _G[fnName]
    if type(fn) == "function" then
      local buf = {}
      local ok, res = pcall(fn, buf)
      local list = (ok and type(res) == "table") and res or buf
      for _, id in ipairs(list) do if type(id) == "number" then add(id, "#" .. id) end end
    end
  end
  self.iconList = out
  return out
end
function FW:IconMatches(q)
  q = tostring(q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local out = {}
  for _, e in ipairs(self:IconList()) do
    if q == "" then if type(e.tex) == "string" then out[#out + 1] = e end
    elseif e.name:find(q, 1, true) then out[#out + 1] = e end
  end
  return out
end

function FW:CreateIcons()
  if self.icons then return self.icons end
  local f = Skin.Window("PanoplySuiteFavIcons", 420, 440, "Choose an icon", "The game's own icons", nil, "Glow")   -- 4J: its own header icon
  self.icons = f
  f.search = Skin.Input(f, 240, 24, "Search: skull, coin, herb, #134400")
  f.search:SetScript("OnTextChanged", function(b, user)
    if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end
    FW:LayoutIcons()
  end)
  f.area = Skin.ScrollArea(f)
  f.cells = {}
  f.info = Skin.Ink(f, 11, Kit.Color("text.muted"))
  f.close2 = Skin.Button(f, "Close", 80, 26, function() f:Hide() end, "Close", "Closes the icon picker; the form keeps its icon.")
  Skin.Resizable(f, { key = "favIcons", minW = 320, minH = 300, onSize = function(_, _, done) if done and f:IsShown() then FW:LayoutIcons() end end })
  return f
end

function FW:LayoutIcons()
  local f = self.icons
  if not f then return end
  local pad = 16
  local W, H = f:GetWidth() or 420, f:GetHeight() or 440
  local inner = W - 2 * pad
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  f.search:ClearAllPoints(); f.search:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); f.search:SetWidth(inner)
  y = y + 24 + SP.s
  local all = self:IconMatches(f.search:GetText())
  local shown = min(#all, FW.ICON_MAX)
  local words = (#all == 0) and "No icon matches. Try a shorter word." or
    (shown < #all and ("The first %d of %d icons. Type more to narrow it."):format(shown, #all) or ("%d %s."):format(#all, #all == 1 and "icon" or "icons"))
  local ih = put(f.info, f, pad, y, inner)
  f.info:SetText(words); ih = put(f.info, f, pad, y, inner)
  y = y + ih + SP.s
  local bottom = pad + 26 + SP.s
  local viewH = max(80, H - y - bottom)
  local area = f.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); area:SetSize(inner, viewH)
  local step = FW.ICON_PX + FW.ICON_GAP
  local cols = max(1, floor((inner - 12 + FW.ICON_GAP) / step))
  local rows = ceil(shown / cols)
  local cw = area:ContentWidth(rows * step)
  cols = max(1, floor((cw + FW.ICON_GAP) / step))
  rows = ceil(shown / cols)
  area.content:SetWidth(cw)
  for i = 1, shown do
    local e = all[i]
    local b = f.cells[i]
    if not b then
      b = CreateFrame("Button", nil, area.content)
      b:SetSize(FW.ICON_PX, FW.ICON_PX)
      b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(b)
      b.sel = b:CreateTexture(nil, "OVERLAY"); Skin.Solid(b.sel, Kit.Color("surface.2"), 0.5); b.sel:SetAllPoints(b); b.sel:Hide()
      b:SetScript("OnClick", function(self) FW.draft.icon = self.entry.tex FW:LayoutForm() FW:LayoutIcons() end)
      b:SetScript("OnEnter", function(self)
        local GT = _G.GameTooltip
        if GT and self.entry then GT:SetOwner(self, "ANCHOR_RIGHT") GT:SetText(type(self.entry.tex) == "number" and ("Game icon " .. self.entry.name)
          or tostring(self.entry.tex):match("([^\\]+)$"), 1, 0.82, 0.25) GT:AddLine("Click: use this icon", 0.5, 0.85, 1) GT:Show() end
      end)
      b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      f.cells[i] = b
    end
    b.entry = e
    b.tex:SetTexture(e.tex)
    if FW.draft and FW.draft.icon == e.tex then b.sel:Show() else b.sel:Hide() end
    local c, r = (i - 1) % cols, floor((i - 1) / cols)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", area.content, "TOPLEFT", c * step, -r * step)
    b:Show()
  end
  for i = shown + 1, #f.cells do f.cells[i]:Hide() end
  area:SetContentHeight(max(1, rows * step))
  area:UpdateBar()
  f.close2:ClearAllPoints(); f.close2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pad, pad)   -- the resize grip has the right corner
  Skin.FitButton(f.close2, 70, inner)
end

function FW:OpenIcons()
  local f = self:CreateIcons()
  self.draft = self.draft or { type = "custom" }
  f:Show()
  if self.form and Skin.Popups and Skin.Popups.Child then Skin.Popups:Child(f, self.form) end
  self:LayoutIcons()
  return f
end

-------------------------------------------------------------------------------
-- Share and import
-------------------------------------------------------------------------------
function FW:Share(ids)
  local text, n = F():Export(ids)
  if not text then Panoply:Print(n or "There is no favorite to share.") return nil end
  local RC = Panoply.ReportCopy
  if not RC then return nil end
  self.lastShare = text
  return RC:Open(text, { title = ("Share %d %s"):format(n, n == 1 and "favorite" or "favorites"), intro = FW.WORDS.shareIntro,
    subtitle = "Select, copy, paste" })
end

function FW:CreateImport()
  if self.importWin then return self.importWin end
  local f = Skin.Window("PanoplySuiteFavImport", 440, 240, "Import favorites", "From a shared line", nil, "Tour")   -- 4J: its own header icon
  self.importWin = f
  f.intro = Skin.Text(f, 12)
  f.intro:SetText(FW.WORDS.importIntro)
  f.box = plainBox(f, 380, "PSF1:...", function() FW:DoImport() end)
  if f.box.SetMaxLetters then f.box:SetMaxLetters(F().TEXT_MAX) end
  f.msg = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.go = Skin.Button(f, "Import", 90, 26, function() FW:DoImport() end, "Import", "Adds the favorites in the line.")
  f.cancel = Skin.Button(f, "Close", 80, 26, function() f:Hide() end, "Close", "Closes this window.")
  return f
end
function FW:LayoutImport()
  local f = self.importWin
  local pad = 16
  local inner = (f:GetWidth() or 440) - 2 * pad
  local y = (f.panoplyHeaderBottom or 56) + SP.m
  y = y + put(f.intro, f, pad, y, inner) + SP.m
  f.box:ClearAllPoints(); f.box:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y); f.box:SetWidth(inner)
  y = y + 24 + SP.m
  local msg = self.importMsg
  if msg then
    f.msg:SetText(msg.text)
    local c = msg.bad and Skin.colors.warn or Skin.colors.inkSoft
    f.msg:SetTextColor(c[1], c[2], c[3], 1)
    y = y + put(f.msg, f, pad, y, inner) + SP.s
    f.msg:Show()
  else f.msg:Hide() end
  local bh = Skin.FlowButtons(f, { f.go, f.cancel }, pad, -y, inner, SP.s, 70)
  y = y + max(bh, 26) + pad
  f:SetHeight(y)
end
function FW:OpenImport()
  local f = self:CreateImport()
  self.importMsg = nil
  setBox(f.box, "")
  f:Show()
  self:LayoutImport()
  if f.box.SetFocus then f.box:SetFocus() end
  return f
end
function FW:DoImport()
  local f = self.importWin
  if not f then return nil end
  local added, skipped, unknown = F():Import(f.box:GetText() or "")
  if not added then
    self.importMsg = { text = skipped or "That line could not be read.", bad = true }
  else
    local parts = { ("Added %d %s."):format(added, added == 1 and "favorite" or "favorites") }
    if skipped > 0 then parts[#parts + 1] = ("%d you already had."):format(skipped) end
    if unknown > 0 then parts[#parts + 1] = ("%d in a zone this game does not have."):format(unknown) end
    self.importMsg = { text = table.concat(parts, " ") }
    Panoply:Print(table.concat(parts, " "))
    if added > 0 then setBox(f.box, "") end
  end
  self:LayoutImport()
  return added
end
