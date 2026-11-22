-- Panoply Suite: the one window. Left: the pages in the player's own order. Top: the "All settings"
-- box. Each page has a switch (its feature on or off) and a gear (its settings, UI/Gear.lua) in its
-- header. There is no Settings, Modules or Guide menu any more: docs/menus/MENUS-SPEC-v2.md.
-- This file is the window, the page header and the doors (open, select, jump); the left list and the
-- search results are UI/MenuNav.lua; the page bodies register themselves with Menu:RegisterTab.
local ADDON, Panoply = ...
local Menu = { defs = {}, pages = {}, rows = {}, current = nil }
Panoply.Menu = Menu
local Skin, C = Panoply.Skin, Panoply.Compat
local Cat = Panoply.Catalog
-- 0.9.7: the shared pop-out menu and its rows are built at load (UI/Skin.lua); here, with UI/Controls.lua loaded, each row gets its
-- On / Off switch too, so opening a menu never creates a frame
if Skin.BuildMenu then Skin.BuildMenu() end

_G.BINDING_NAME_HEARTHPATH_MENU = "Open Panoply Suite"
Menu.W, Menu.H = 900, 616          -- 616: the pages keep the room they had at 600 before the resize grip took a strip under them
Menu.NAV_X = 236             -- 0.9.5: where Back sits in the top bar (Forward is beside it), after the window's name
Menu.BOX_X = 236 + 24 + 4 + 24 + 8   -- and the All settings box after them
Menu.AREA_BOTTOM = 28        -- the page area ends this far above the window's bottom edge (the resize grip sits in the corner under it)
Menu.LIST_W = 200
-- names the older code and the slash commands still use
Menu.ALIAS = { Leveling = "guide", Professions = "professions", Partner = "partner", Help = "help", Hall = "hall",
  Settings = "guide", Modules = "guide", Guide = "guide", Bags = "hall", Profiles = "profiles", Auctions = "auctions", Map = "map", Home = "home",
  -- 0.9.5 phase 4A3: the names the pages have now (spec 05 section 1)
  Muster = "hall", Class = "class", Legacy = "legacy",
  -- 0.9.5 phase 4H (spec 03 section 2.1): Class & Spec ("Talents & spells") is part of the Class page now
  classspec = "class", ClassSpec = "class", ClassGuide = "class", ClassPages = "class" }
Menu.TIPS = {
  guide = "Your next step and the route. The gear holds the guide's settings.",
}

-- opts.scroll: the page sits in a scroll area and lays itself out with p:Layout()
function Menu:RegisterTab(name, build, refresh, opts)
  self.defs[name] = { build = build, refresh = refresh, scroll = opts and opts.scroll }
end

-------------------------------------------------------------------------------
-- Saved data: PanoplySuiteDB.menu = { order = { page keys }, hidden = { key = true }, last = "guide",
--   sections = { key = "play" | "character" | "account" | "setup" } }   (0.9.5 phase 4A3, a NEW key: only the pages the player moved
--   to another section than their own; Cat.NAV_SECTIONS)
-------------------------------------------------------------------------------
function Menu:Saved()
  local db = Panoply.db
  if not db then return { order = {}, hidden = {}, sections = {} } end
  db.menu = type(db.menu) == "table" and db.menu or {}
  if type(db.menu.order) ~= "table" then db.menu.order = {} end
  if type(db.menu.hidden) ~= "table" then db.menu.hidden = {} end
  if type(db.menu.sections) ~= "table" then db.menu.sections = {} end
  -- 0.9.5 phase 4A3, once (a NEW key, navV): an order saved before the sections had Class & Spec above the Class Guide; Character is
  -- Class, then Talents & spells (spec 05 section 1), so Class goes right above it. Nothing else in the saved order moves.
  if db.menu.navV == nil then
    db.menu.navV = 1
    local o = db.menu.order
    local ic, is
    for i, k in ipairs(o) do if k == "class" then ic = i elseif k == "classspec" then is = i end end
    if ic and is and is < ic then table.remove(o, ic) table.insert(o, is, "class") end
  end
  return db.menu
end

-- The section a page sits in: where the player moved it, else its own (spec 05 section 1). A section this build does not know is
-- read as the page's own.
function Menu:SectionIndex(key)
  for i, sec in ipairs(Cat.NAV_SECTIONS) do if sec.key == key then return i end end
  return nil
end
function Menu:SectionOf(key)
  local moved = self:Saved().sections[key]
  if moved and self:SectionIndex(moved) then return moved end
  local p = Cat[key]
  local own = p and p.nav
  if own and self:SectionIndex(own) then return own end
  return Cat.NAV_SECTIONS[#Cat.NAV_SECTIONS].key
end
function Menu:SetSection(key, sec)
  if not self:SectionIndex(sec) then return false end
  local p = Cat[key]
  if p and p.nav == sec then self:Saved().sections[key] = nil else self:Saved().sections[key] = sec end
  return true
end

-- The pages that exist in this build, in the player's order; hidden ones only with includeHidden. The list the player sees also
-- leaves out the pages that are not useful yet (Professions before one is learned, Level together outside a group; Cat:Useful),
-- except the page that is on screen. A page the saved order does not know yet (a new page, or a new feature) goes right after
-- the page that comes before it in Panoply Suite's own order, so Home is first and Level together sits where it belongs.
function Menu:PageList(includeHidden)
  local exist, by = Cat:Existing(), {}
  for _, p in ipairs(exist) do by[p.key] = p end
  local saved, out, seen = self:Saved(), {}, {}
  for _, k in ipairs(saved.order) do
    if by[k] and not seen[k] then out[#out + 1] = by[k]; seen[k] = true end
  end
  for i, p in ipairs(exist) do
    if not seen[p.key] then
      local at = 0
      for j = i - 1, 1, -1 do
        for n, q in ipairs(out) do if q.key == exist[j].key then at = n break end end
        if at > 0 then break end
      end
      table.insert(out, at + 1, p); seen[p.key] = true
    end
  end
  -- 0.9.5: the four sections, in their order; inside a section the player's order
  local buckets = {}
  for _, p in ipairs(out) do
    local i = self:SectionIndex(self:SectionOf(p.key))
    buckets[i] = buckets[i] or {}
    table.insert(buckets[i], p)
  end
  out = {}
  for i = 1, #Cat.NAV_SECTIONS do for _, p in ipairs(buckets[i] or {}) do out[#out + 1] = p end end
  if includeHidden then return out end
  local vis = {}
  for _, p in ipairs(out) do
    if not (saved.hidden[p.key] and not p.soon) and (Cat:Useful(p) or self.current == p.key) then vis[#vis + 1] = p end
  end
  return vis
end

function Menu:IsHidden(key) return self:Saved().hidden[key] and true or false end

-- the full order as saved: every page of the build, hidden ones too
function Menu:FullOrder()
  local out = {}
  for _, p in ipairs(self:PageList(true)) do out[#out + 1] = p.key end
  return out
end

-- Move a page by one (delta = -1 up, 1 down) or to a place in the full order (toIndex; the caller sets its section first, see
-- Menu:StopDrag). 0.9.5: a page keeps its section while it moves inside it; one more step past the first or last page of its section
-- takes it into the section before or after (to its end going up, to its start going down).
function Menu:MovePage(key, delta, toIndex)
  local order = self:FullOrder()
  local at
  for i, k in ipairs(order) do if k == key then at = i end end
  if not at then return false end
  if not toIndex and delta ~= 0 then
    local sec = self:SectionOf(key)
    -- the neighbour the player sees: the next page in the list on screen (a hidden page, or one not in use such as Level together
    -- when solo, is skipped); a page that is not in that list itself (a hidden one in Edit pages) moves in the full order
    local vis, vi = self:PageList(false), nil
    for i, p in ipairs(vis) do if p.key == key then vi = i end end
    local nb
    if vi then nb = vis[vi + delta] and vis[vi + delta].key else nb = order[at + delta] end
    if nb and self:SectionOf(nb) == sec then
      table.remove(order, at)
      local nj
      for i, k in ipairs(order) do if k == nb then nj = i end end
      table.insert(order, delta < 0 and nj or nj + 1, key)
      self:Saved().order = order
      self:LayoutList()
      return true
    end
    -- past the first or last page of its section: into the section before or after
    local si = self:SectionIndex(sec) + (delta < 0 and -1 or 1)
    local into = Cat.NAV_SECTIONS[si]
    if not into then return false end
    self:SetSection(key, into.key)
    table.remove(order, at)
    -- the place in the order: after the last page of that section going up, before its first going down
    local pos
    for i, k in ipairs(order) do
      if self:SectionOf(k) == into.key then
        if delta < 0 then pos = i + 1 elseif not pos then pos = i end
      end
    end
    table.insert(order, pos or (delta < 0 and #order + 1 or 1), key)
    self:Saved().order = order
    self:LayoutList()
    return true
  end
  local to = toIndex or (at + delta)
  to = math.max(1, math.min(#order, to))
  if to == at then return false end
  table.remove(order, at); table.insert(order, to, key)
  self:Saved().order = order
  self:LayoutList()
  return true
end

function Menu:SetHidden(key, hide)
  local p = Cat[key]
  if not p or p.soon then return false end
  self:Saved().hidden[key] = hide and true or nil
  self:LayoutList()
  return true
end

function Menu:ResetOrder()
  local s = self:Saved()
  s.order, s.hidden, s.sections = {}, {}, {}
  self:LayoutList()
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
function Menu:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteMenu", self.W, self.H, "Panoply Suite")
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- 900 x 600 fits 1024 x 668 with room to spare
  self.frame = f
  local hb = f.panoplyHeaderBottom or 50
  self.hb = hb
  -- All settings: one box, always there (results: UI/MenuNav.lua)
  -- 0.9.5 (spec 1.4): Back and Forward at the left of the top bar, before the search box (UI/History.lua draws and runs them)
  if Panoply.History then Panoply.History:BuildButtons(f, Menu.NAV_X, -math.floor((hb - 24) / 2)) end
  local box = Skin.Input(f, 400, 26, Menu.BOX_HINT)
  box:SetPoint("TOPLEFT", f, "TOPLEFT", Menu.BOX_X, -math.floor((hb - 26) / 2))
  Skin.Tooltip(box, "All settings", Cat.UI_HELP.search)
  box:SetScript("OnEnter", function() if box.panoplyShowTip then box.panoplyShowTip() end end)
  box:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  self.box = box
  self:BuildSearch(box)
  -- left list
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(hb + 6))
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 12)
  list:SetWidth(self.LIST_W)
  self.list = list
  self:BuildList(list)
  -- the page: a header (icon, name, line, switch, gear) and the body under it
  local bodyX = 10 + self.LIST_W + 10
  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", f, "TOPLEFT", bodyX, -(hb + 6))
  area:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, Menu.AREA_BOTTOM)     -- clear of the resize grip in the corner
  area:SetSize(self.W - bodyX - 12, self.H - hb - 6 - Menu.AREA_BOTTOM)
  self.area = area
  self.bodyW, self.areaH = self.W - bodyX - 12, self.H - hb - 6 - Menu.AREA_BOTTOM
  self:BuildHeader(area)
  local host = CreateFrame("Frame", nil, area)
  host:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
  host:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
  self.host = host
  -- Nov 2026: the window resizes in both directions and remembers its size; every page re-flows to the new width and scrolls
  -- when it is too short (Menu:Resized)
  Skin.Resizable(f, { key = "menu", minW = function() return Menu:MinWidthFor(Menu.pageDef) end, minH = Menu.MIN_H, w0 = self.W0, h0 = self.H0,
    onSize = function(w, h, done) Menu:Resized(w, h, done) end })
  -- 0.9.5 (item 3): a click on the main window brings it to the front again (the game does it for a top-level frame; the hook is for
  -- the windows above it that were lifted to its strata), and windows opened from it open in front of and beside it (Panoply.Windows:Child)
  if f.SetToplevel then f:SetToplevel(true) end
  f:HookScript("OnMouseDown", function(self) Panoply.Windows:Front(self) end)
  -- 0.9.5 (spec 1.4): the mouse's fourth and fifth buttons on the main window go back and forward. The game tells every button
  -- release anywhere (GLOBAL_MOUSE_UP); the window's own OnMouseUp would only hear the ones on its bare edges, because a row, a
  -- card or a scroll area under the pointer takes the click first. A window lying in front of this one keeps its own clicks.
  Panoply:On("GLOBAL_MOUSE_UP", function(_, button)
    if button ~= "Button4" and button ~= "Button5" then return end
    local H = Panoply.History
    if not (H and f:IsShown() and f.IsMouseOver and f:IsMouseOver()) then return end
    local front = Panoply.Windows.front
    if front and front ~= f and front.IsShown and front:IsShown() and front.IsMouseOver and front:IsMouseOver() then return end
    if button == "Button4" then H:Back() else H:Forward() end
  end)
  f:SetScript("OnHide", function()
    Panoply.Windows:MainHidden()
    Panoply:Fire("MENU_HIDDEN")
    if _G.GameTooltip then GameTooltip:Hide() end
    Menu:CloseResults(true)
    -- hidden while the live preview had it faded: it comes back whole the next time
    if Panoply.PageSettings and Panoply.PageSettings.ClearPreview then Panoply.PageSettings:ClearPreview() end
  end)
  for _, ev in ipairs({ "STEP_CHANGED", "STEPS_CHANGED", "SYNC_STATUS", "PLAN_ADOPTED", "OPTION_CHANGED", "PROF_UPDATED", "LEVEL_CHANGED", "MODULE_CHANGED", "PROFILES_CHANGED" }) do
    Panoply:Listen(ev, function() if Menu.frame and Menu.frame:IsShown() and not Menu.batching then Menu:RefreshCurrent() end end)
  end
  -- what Home shows changes with the bags, the characters' gold, an auction scan and the trainer: only Home follows those (Hearth
  -- Hall redraws itself, at most every third of a second)
  for _, ev in ipairs({ "ALTS_CHANGED", "INVENTORY_CHANGED", "AUCTION_SCAN_DONE", "SPEC_TRAINER_CHANGED" }) do
    Panoply:Listen(ev, function() if Menu.frame and Menu.frame:IsShown() and Menu.current == "home" then Menu:RefreshCurrent() end end)
  end
  -- 0.9.5 phase 4K: the Guide page's trainer steps (Engine/TrainerStep.lua) follow what waits at the trainer
  for _, ev in ipairs({ "SPEC_TRAINER_CHANGED", "TRAINER_STEPS_CHANGED" }) do
    Panoply:Listen(ev, function() if Menu.frame and Menu.frame:IsShown() and Menu.current == "guide" and not Menu.batching then Menu:RefreshCurrent() end end)
  end
  -- 0.9.5 phase 4A3: the nav dots follow the shared alerts (Core/Alerts.lua); Home redraws on the next frame (its own drawing works the
  -- alerts out again, which may say they changed: never inside that drawing)
  Panoply:Listen("ALERTS_CHANGED", function()
    if not (Menu.frame and Menu.frame:IsShown()) then return end
    Menu:LayoutList()
    if Menu.current == "home" and not Menu.alertRedraw then
      Menu.alertRedraw = true
      C.After(0, function() Menu.alertRedraw = false if Menu.frame and Menu.frame:IsShown() and Menu.current == "home" then Menu:RefreshCurrent() end end)
    end
  end)
  -- the list follows the character: a profession learned, a group joined or left
  local function listChanged() if Menu.frame and Menu.frame:IsShown() then Menu:RefreshCurrent() end end
  Panoply:On("GROUP_ROSTER_UPDATE", listChanged)
  Panoply:On("PLAYER_MONEY", function() if Menu.frame and Menu.frame:IsShown() and Menu.current == "home" then Menu:RefreshCurrent() end end)
  return f
end

-- The window took a new size (the resize grip, a remembered size put back, or Reset): the list, the header, the open page and every
-- page made so far take the new room. Pages are scrolling lists that lay themselves out for a width (p.width), so a narrower window
-- wraps their text and a shorter one scrolls them; nothing is cut off.
Menu.W0, Menu.H0 = Menu.W, Menu.H        -- the size it is made at
Menu.MIN_W, Menu.MIN_H = 860, 520        -- 860 wide: the Guide page's cards and the Map page's Look table keep their columns; 520 tall: every row of the left list fits
-- 0.9.5 (spec 1.3, the resize bands): how narrow the window goes depends on the page that is showing. A page says the least width it
-- can be laid out for (page.minWidth in UI/Catalog.lua, the width of its own area); a page that does not say keeps the 628 that the
-- 860 window always gave it. So a page rebuilt for the Narrow band lets the window be dragged narrower while it shows, and the window
-- widens again by itself for a page that needs the room (Menu:FitWindow). Beside the settings drawer a page that does not say is
-- laid out down to DRAWER_PAGE_MIN (every page but the Guide wraps and scrolls; the Guide says 628).
Menu.PAGE_MIN_W = Menu.MIN_W - (10 + Menu.LIST_W + 10) - 12
Menu.DRAWER_PAGE_MIN = 380
function Menu:PageMinWidth(page, drawer)
  local w = page and tonumber(page.minWidth)
  if w then return w end
  return drawer and Menu.DRAWER_PAGE_MIN or Menu.PAGE_MIN_W
end
-- the least width of the window while this page shows
function Menu:MinWidthFor(page)
  return (10 + Menu.LIST_W + 10) + 12 + self:PageMinWidth(page)
end
-- The window as wide as the page that is showing needs: the width the player gave it with the grip (when there is none: the
-- width it has), never under the page's least. Called when the page changes. Nothing is saved: the player's own size stays what
-- the grip set, so the window comes back to it on a page that allows it.
function Menu:FitWindow()
  local f = self.frame
  if not (f and self.pageDef) or f.panoplySizing then return false end
  local need = self:MinWidthFor(self.pageDef)
  local uw = f.panoplyUserSize and f:panoplyUserSize()
  local want = math.max(need, uw or f:GetWidth() or self.W0)
  local sw = Panoply.Windows:ScreenSize()
  local sc = f:GetScale() or 1
  if sw and sc > 0 then want = math.max(need, math.min(want, math.floor(sw / sc))) end
  local now = f:GetWidth() or want
  if math.abs(now - want) < 0.5 then return false end
  if Panoply.Kit.InCombat() and Panoply.Kit.Protected(f) then
    Panoply.Kit.Defer("menu/fit", function() Menu:FitWindow() end)
    return false
  end
  f:SetWidth(want)
  self:Resized(want, f:GetHeight() or self.H, true)
  return true
end
Menu.BOX_W = 400
function Menu:Resized(w, h, done)
  local f = self.frame
  if not f then return end
  -- review B1: the page area is a parent of protected frames while the page showing carries secure buttons (Professions' trainer rows):
  -- in a fight the room is not sized again; it is when the fight ends, for the size the window has then
  if Panoply.Kit.InCombat() and self.area and Panoply.Kit.Protected(self.area) then
    Panoply.Kit.Defer("menu/resized", function() Menu:Resized(f:GetWidth() or w, f:GetHeight() or h, true) end)
    return
  end
  self.W, self.H = w, h
  local bodyX = 10 + self.LIST_W + 10
  self.bodyW, self.areaH = w - bodyX - 12, h - (self.hb or 50) - 6 - Menu.AREA_BOTTOM
  self.area:SetSize(self.bodyW, self.areaH)
  -- the All settings box keeps clear of the close button
  self:FitBox(w)
  if not self.pageDef then return end
  -- 0.9.5: the settings panel first (a drawer beside a Wide page, the whole page area otherwise: UI/Gear.lua), because where it
  -- sits says how much room the page has
  -- (the header before it: the panel hangs under the header, whose help line may wrap to another height at the new width)
  self:LayoutHeader()
  if Panoply.PageSettings and Panoply.PageSettings.open and Panoply.PageSettings.Relayout then
    local ok, err = pcall(Panoply.PageSettings.Relayout, Panoply.PageSettings)
    if not ok then Panoply:Debug("gear relayout", err) end
  end
  self:LayoutHeader()
  self:SizePages()
  self:LayoutList()
  if self.results and self.results:IsShown() and self.ShowResults and self.lastQuery then pcall(self.ShowResults, self, self.lastQuery) end
  self:RefreshCurrent()
end

-- The All settings box keeps clear of the close button, and its hint is the long one only while the box is wide enough for it
-- (0.9.5: a page rebuilt for the Narrow band lets the window go narrower than the long hint)
Menu.BOX_HINT, Menu.BOX_HINT_SHORT = "All settings: type what you want to change", "All settings"
function Menu:FitBox(w)
  local box = self.box
  if not box then return end
  local bw = math.max(160, math.min(self.BOX_W, (w or self.W) - Menu.BOX_X - 56))
  box:SetWidth(bw)
  local ph = box.placeholder
  if ph then
    ph:SetText(Menu.BOX_HINT)
    if Skin.TextWidth(ph) > bw - 24 - 8 then ph:SetText(Menu.BOX_HINT_SHORT) end
  end
end

-- every page made so far takes the room the page area has now (the window was resized, or the settings drawer opened or closed)
function Menu:SizePages()
  for _, p in pairs(self.pages) do
    if p.panoplyArea then
      p.panoplyArea:SetSize(self.hostW, self.hostH)
      p.width, p.height = self.hostW - 12, self.hostH
      p:SetWidth(p.width)
      if p.panoplyArea.UpdateBar then p.panoplyArea:UpdateBar() end       -- its scroll bar is as long as the new height
    else
      p.width, p.height = self.hostW, self.hostH
    end
  end
end

-- 0.9.5 (spec 1.5): the settings panel as a drawer beside a Wide page. w = the room it takes at the right of the page area (its
-- width and the gap), or nil when it is closed or takes the whole page area. The page keeps the rest and is laid out for it.
-- Returns false when the page area may not be sized now (a fight, and the page carries secure buttons): it is sized when it ends.
function Menu:SetDrawer(w)
  w = (type(w) == "number" and w > 0) and w or nil
  if self.drawerW == w then return true end
  if self.host and Panoply.Kit.InCombat() and Panoply.Kit.Protected(self.host) then
    Panoply.Kit.Defer("menu/drawer", function() Menu:SetDrawer(w) Menu:RefreshCurrent() end)
    return false
  end
  self.drawerW = w
  self.hostKey = nil
  if self.pageDef then
    self:LayoutHeader()
    self:SizePages()
  end
  return true
end

-------------------------------------------------------------------------------
-- The page header
-------------------------------------------------------------------------------
Menu.headerExtra = {}   -- page key -> function() return "SMALL LABEL", "value" end (Hearth Hall: account gold)

-- Step 20 (0.9.4): the header is one of the kit's pieces (UI/Kit.lua, Kit.PageHeader), the same frame for every page; this file says
-- what goes in it (LayoutHeader) and what its buttons do.
-- Page key -> function() returning the extra controls (frames) that page puts in the header's right-hand slot (none today).
Menu.headerControls = {}
-- 0.9.5 phase 4H: page key -> function() returning { label, text, crest = { tex, cut } } for a page whose title is not its list name (the
-- Class page is titled with the character's class, "Hunter", under the class crest: docs/specs/page-redesigns-03-class.md section 2.1)
Menu.headerTitle = {}
function Menu:BuildHeader(area)
  local sizes = {}
  for _, pr in ipairs(Panoply.Look.PRESETS) do sizes[#sizes + 1] = { id = pr.id, name = pr.name, tipBody = Cat.UI_HELP[pr.id] } end
  self.header = Panoply.Kit.PageHeader(area, { onSwitch = function() Menu:ToggleSwitch() end, switchTip = Cat.UI_HELP.switch,
    onGear = function() Menu:ToggleGear() end, gearTip = Cat.UI_HELP.gear,
    sizes = sizes, onSize = function(id) Menu:ApplyPreset(id) end, sizeLabelTip = Cat.UI_HELP.sizeLabel,
    onReset = function() Menu:ResetView() end,
    resetTip = "Shows this page as it first opens: its first tab, and its sections open or closed as they start. It changes no setting." })
end

-- Reset view (the header's button, on every page): the page's remembered tab and sections are forgotten (Kit.ResetState)
function Menu:ResetView()
  local page = self.pageDef
  if not page then return false end
  local K = Panoply.Kit
  if not K.HasState(page.key) then
    Panoply:Print(("The %s page is already as it first opens."):format(page.label or "this"))
    return false
  end
  K.ResetState(page.key)
  Panoply:Print(("The %s page is back as it first opens."):format(page.label or "this"))
  return true
end

function Menu:PageDef(key) return Cat:Page(key) end

-- what the page's switch says: on or off
function Menu:SwitchState(page)
  if page.module and Panoply.Modules.byKey[page.module] then
    return Panoply.Modules:Wanted(page.module), Panoply.Modules:Status(page.module)
  end
  return nil
end

function Menu:ToggleSwitch()
  local page = self.pageDef
  if not page then return end
  if page.module and Panoply.Modules.byKey[page.module] then
    Panoply.Modules:Set(page.module, not Panoply.Modules:Wanted(page.module))
  end
  self:RefreshCurrent()
end

function Menu:HasGear(page)
  if not page then return false end
  if page.gear or page.front then return true end
  return #Cat:Sections(page) > 0
end

function Menu:LayoutHeader()
  local h, page = self.header, self.pageDef
  if not (h and page) then return end
  local SP = Skin.SP
  local W = self.bodyW
  local spec = { icon = page.icon, label = page.label, text = page.text, hasGear = self:HasGear(page),
    reset = { can = Panoply.Kit.HasState(page.key) } }
  local on, word = self:SwitchState(page)
  if on ~= nil then spec.switch = { on = on, word = word } end
  local ex = self.headerExtra[page.key]
  if ex then
    local label, value = ex()
    if label then spec.extra = { label = label, value = value } end
  end
  local fn = self.headerControls[page.key]
  if fn then spec.controls = fn() end
  local tf = self.headerTitle[page.key]
  if tf then
    local ok, t = pcall(tf)
    if ok and type(t) == "table" then
      spec.label, spec.text, spec.crest = t.label or spec.label, t.text or spec.text, t.crest
    end
  end
  -- 0.9.5 (spec 1.4): reached by a jump from another page: a small chip in the header that goes back there ("< Field Kit"). The
  -- header puts it beside the title when there is room, else on a line of its own under the help line (Kit.PageHeader).
  spec.chip = Panoply.History and Panoply.History:Chip(h) or nil
  if self.sizeShown ~= false and Panoply.Presets and Panoply.Presets:Has(page.key) then spec.size = { current = Panoply.Presets:Current(page.key) } end
  local total = h:Layout(spec, W)
  self.headerH = total
  -- the page's room: placed again only when it changed (a page may carry secure buttons, which makes this frame a parent of protected
  -- ones: it is not moved or sized in a fight, and is placed when the fight ends, review B1)
  local drawer = self.drawerW or 0
  local key = table.concat({ total, W, self.areaH or 0, drawer }, ":")
  if self.hostKey == key then return end
  if Panoply.Kit.InCombat() and Panoply.Kit.Protected(self.host) then
    Panoply.Kit.MarkDirty(self.current)
    return
  end
  self.hostKey = key
  self.host:ClearAllPoints()
  self.host:SetPoint("TOPLEFT", self.area, "TOPLEFT", 0, -(total + SP.s))
  self.host:SetPoint("BOTTOMRIGHT", self.area, "BOTTOMRIGHT", -drawer, 0)
  self.hostW, self.hostH = W - drawer, self.areaH - total - SP.s
  self.host:SetSize(self.hostW, self.hostH)
  -- every page takes the room it has now: beside a drawer the pages have less room than the window gives them, and a header that grew
  -- or shrank (another page's header, a jump's return chip) changes the height under it. (0.9.5 phase 4G: before, the pages were sized
  -- again only when the drawer changed, so a page drawn under a shorter header kept its old height and its scrolling part ran under the
  -- window's corner and resize grip: the layout checker's Professions, At Your Level and Legacy findings since phase 4B.)
  self.hostDrawer = drawer
  self:SizePages()
end

-- Small / Normal / Large on the page that is showing (UI/Presets.lua says what it sets)
function Menu:ApplyPreset(id)
  if not (Panoply.Presets and self.pageDef) then return end
  Panoply.Presets:Apply(self.pageDef.key, id)
  self:RefreshCurrent()
end

-- The live preview (UI/Gear.lua): while the mouse is on a setting that changes the screen behind the menu, the menu window fades to
-- a faint outline so the real screen shows; the gear itself stays whole.
function Menu:Preview(on)
  local f = self.frame
  if not f then return end
  self.preview = on and true or false
  Skin.FadeTo(f, on and Panoply.PageSettings.FADE or 1, 0.12)
end

-------------------------------------------------------------------------------
-- Page bodies
-------------------------------------------------------------------------------
function Menu:Page(name)
  local p = self.pages[name]
  if p then return p end
  local def = self.defs[name]
  local host = self.host
  local w, h = self.hostW or (self.W - 230), self.hostH or (self.H - 130)
  if def and def.scroll then
    local area = Skin.ScrollArea(host)
    area:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    area:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    area:SetSize(w, h)
    p = area.content
    p.width, p.height = w - 12, h
    p:SetWidth(p.width)
    p.panoplyArea = area
  else
    p = CreateFrame("Frame", nil, host)
    p:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    p.width, p.height = w, h
  end
  if def and def.build then def.build(p) end
  p:Hide()
  if p.panoplyArea then p.panoplyArea:Hide() end
  self.pages[name] = p
  return p
end

-- review B1: the room that holds the pages is a parent of protected frames while the page showing carries secure buttons (Professions'
-- trainer rows): in a fight it is not shown or hidden. ShowHost does nothing when it already is as asked and says false when it may not.
function Menu:HostLocked() return self.host and Panoply.Kit.InCombat() and Panoply.Kit.Protected(self.host) and true or false end
function Menu:ShowHost(on)
  local h = self.host
  if not h or (h:IsShown() and true or false) == (on and true or false) then return true end
  if self:HostLocked() then return false end
  if on then h:Show() else h:Hide() end
  return true
end

-- (a frame is only shown or hidden when it is not already: a page that carries secure buttons may not be, in a fight)
function Menu:ShowBody(name)
  for n, p in pairs(self.pages) do
    if n ~= name then
      if p:IsShown() then p:Hide() end
      if p.panoplyArea and p.panoplyArea:IsShown() then p.panoplyArea:Hide() end
    end
  end
  local p = self:Page(name)
  if p.panoplyArea and not p.panoplyArea:IsShown() then p.panoplyArea:Show() end
  if not p:IsShown() then p:Show() end
  return p
end

function Menu:RefreshCurrent()
  if not self.frame then return end
  local page = self.pageDef
  if not page then return end
  local body = page.body
  local def, p = self.defs[body], self.pages[body]
  self:LayoutHeader()
  if def and def.refresh and p then local ok, err = pcall(def.refresh, p) if not ok then Panoply:Debug("menu refresh", err) end end
  -- a page that carries secure buttons (Professions) is a parent of protected frames: in a fight its scroll area and content are not
  -- sized (review B1); the page is drawn again when the fight ends
  local held = p and Panoply.Kit.InCombat() and Panoply.Kit.Protected(p)
  if held then Panoply.Kit.MarkDirty(self.current) end
  if p and p.Layout and p.panoplyArea then
    local ok, h = pcall(p.Layout, p)
    if ok then
      if not held then p.panoplyArea:SetContentHeight(h) end
    else Panoply:Debug("menu layout", h) end
  end
  -- the page's room may have changed (a resized window, a taller header): its scroll bar is as long as the room it has now
  if p and p.panoplyArea and not held then
    if self.hostW and self.hostH then p.panoplyArea:SetSize(self.hostW, self.hostH); p.height = self.hostH end
    if p.panoplyArea.UpdateBar then p.panoplyArea:UpdateBar() end
  end
  self:RefreshList()
  if Panoply.PageSettings and Panoply.PageSettings.open then Panoply.PageSettings:RefreshRows() end
end

-------------------------------------------------------------------------------
-- Doors: open, select, jump
-------------------------------------------------------------------------------
-- Which page opens when none is named (the keybind, the minimap button, /panoply): Home the first time in a play session, after that the
-- page that was open last. A named page that this build does not have falls back to Home.
function Menu:Resolve(key)
  key = self.ALIAS[key or ""] or key
  if not key then
    key = self.openedThisSession and self:Saved().last or "home"
  end
  local def = Cat:Page(key)
  if not def or (def.sections and not Cat:PageExists(def)) then key = "home" end
  return key
end

function Menu:Select(key)
  self:Create()
  local H = Panoply.History
  if H then H:Begin() end
  local p = self:SelectPage(key)
  if H then H:End("page") end
  return p
end

function Menu:SelectPage(key)
  key = self:Resolve(key)
  local page = Cat:Page(key)
  -- review B1: the page showing carries secure buttons (Professions' trainer rows) and it is a fight: the page cannot be hidden, so
  -- the new one opens when the fight ends
  if Panoply.Kit.InCombat() and self.pageDef and page and page.body ~= self.pageDef.body then
    local cur = self.pages[self.pageDef.body]
    if cur and Panoply.Kit.Protected(cur) then
      Panoply.Kit.Defer("menu/select", function() Menu:Select(key) end)
      Panoply:Print(("The %s page opens when combat ends."):format(page.label or "next"))
      return cur
    end
  end
  if self.editing then self:EndEdit() end
  if Panoply.PageSettings and Panoply.PageSettings.open then Panoply.PageSettings:Close(true) end
  self:CloseResults(true)
  self.current, self.pageDef = key, page
  self.openedThisSession = true
  local s = self:Saved()
  s.last = page.parent or key
  if not self.defs[page.body] then
    -- a page whose body is not registered (a module that is not in this build): Home
    key, page = "home", Cat.home
    self.current, self.pageDef = key, page
  end
  self:LayoutHeader()
  local p = self:ShowBody(page.body)
  -- 0.9.5: the window is as wide as this page needs (it lays the page out itself when it changes the width)
  if not self:FitWindow() then self:RefreshCurrent() end
  return p
end

function Menu:Open(key)
  self:Create()
  if not self.frame:IsShown() then
    -- 0.9.5: the page the window is opened on was not reached by a jump from another page (no return chip in its header)
    if Panoply.History then Panoply.History:Via("open") end
    -- 0.9.5: the nav dots are worked out now, before the list is drawn (the alerts also follow the game's events, Core/Alerts.lua)
    if Panoply.Alerts and not C.InCombat() then Panoply.Alerts:Refresh() end
    self.frame:Show()
  end
  return self:Select(key)
end
-- the window holds the page showing: with secure buttons on it, it cannot be hidden in a fight (it closes when the fight ends)
function Menu:Hide()
  local f = self.frame
  if not f or not f:IsShown() then return end
  if Panoply.Kit.InCombat() and Panoply.Kit.Protected(f) then
    Panoply.Kit.Defer("menu/hide", function() Menu:Hide() end)
    Panoply:Print("The window closes when combat ends.")
    return
  end
  f:Hide()
end
function Menu:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide() else self:Open() end
end

-- the gear of a page, opened at a section and (when a search named it) a row
function Menu:OpenGear(pageKey, sectionKey, rowKey, advanced)
  self:Create()
  if not self.frame:IsShown() then
    if Panoply.History then Panoply.History:Via("open") end
    self.frame:Show()
  end
  pageKey = self.ALIAS[pageKey or ""] or pageKey
  -- one step of history for the whole jump: the page and its settings, opened at the section
  local H = Panoply.History
  if H then H:Begin() end
  if self.current ~= pageKey then self:Select(pageKey) end
  if self:HasGear(self.pageDef) then Panoply.PageSettings:Open(self.pageDef, sectionKey, rowKey, advanced) end
  if H then H:End("gear") end
end

function Menu:ToggleGear()
  if Panoply.PageSettings.open then Panoply.PageSettings:Close() else
    local page = self.pageDef
    if page and page.gear then Panoply.PageSettings:Open(Cat[page.gear[1]], page.gear[2]) else Panoply.PageSettings:Open(page) end
  end
end

-- the All settings box's text, with its hint shown only while it is empty (SetText also fires OnTextChanged in the game)
function Menu:SetBoxText(t)
  self.box:SetText(t)
  if self.box.placeholder then if t == "" then self.box.placeholder:Show() else self.box.placeholder:Hide() end end
end

-- /panoply settings [word]: the window, with the All settings box ready (and the word typed)
function Menu:Search(text)
  self:Open(self.current)
  self:SetBoxText(text or "")
  if self.box.SetFocus then self.box:SetFocus() end
  self:ShowResults(text or "")
end

-------------------------------------------------------------------------------
-- Guide page (0.9.5 phase 4K: docs/specs/page-redesigns-05-home-guide-map.md section 4, with spec 05b section 2 winning where they
-- differ, and spec 06a section 3.2's one step number "Step 5 of 27 · Westfall").
--   Top row     Guide ▾ (0.9.7: which written guide the character follows, Engine/GuidePicker.lua), Follows ▾ (Panoply.GuideParts.Follows, the control the
--               guide window's header has too), and ⋯ (Reset plan, which asks first; Report a problem).
--   Next step   the step type icon, the headline, "Step 5 of 27 · Westfall", the why line, live progress (pips or a count bar), the trip
--               line (one icon per leg with its time, then the total), Point the arrow, Skip step, Done (only on a step the engine
--               can't see done), Replan now (a small icon button). Progress: the level bar with the rested part shaded and the pace
--               mark, the "Level 16 in about 1 h 22 min at your pace" line, the route as pips up to 10 steps, and the session line
--               when Field Kit's switch is on. On your screen: Arrow, Trail, Quest tracker, Together (while levelling together):
--               each a toggle, each with a gear for its settings. Automation: Auto accept, Auto turn-in, Auto fly.
--   Your route  two-line rows that never cut a word: line 1 the type icon, the quest's level and name (or the headline), line 2 what
--               to do and where. A step with several quests opens in place. Steps done fold into "3 done" at the top; the current
--               one is highlighted; a step the engine can't see done has a dashed outline, "Won't hold you up" and a Done tick.
--               Trainer visits are steps of the route (Engine/TrainerStep.lua), put in beside the guide.
--   States      no guide here (Record mode), inside a dungeon (the Dungeon card).
--   Bands       Wide: two columns. Medium: Next step full width, the route under it. Narrow: the route shows the next 3 steps with
--               "Show route", and the toggles are icons only.
-------------------------------------------------------------------------------
local ROUTE_MAX = 24          -- rows made (the look-ahead setting goes to 20, plus the trainer steps)
local NARROW_ROWS = 3
local PIPS_UPTO = 10          -- the route bar is pips up to this many steps (spec 05 section 4.3)

Panoply.defaults.account.guideRouteSteps = 10
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "guideRouteSteps" }) end

local function planHeadline()
  local E, P, S = Panoply.Engine, Panoply.Planner, Panoply.State
  -- 0.9.7: the guide engine cannot run and nothing takes its place (Core/Init.lua): the same two lines as the guide card
  if Panoply.GuideUnavailable and Panoply:GuideUnavailable() then return Panoply.GUIDE_UNAVAILABLE_TITLE, Panoply.GUIDE_UNAVAILABLE_LINE end
  if not Panoply.QuestData:Available() then return "Following your quest log", "Turn on Panoply Suite Quest Data for a full route." end
  if Panoply.Guides and Panoply.Guides.NoStepShown and Panoply.Guides:NoStepShown() then return Panoply.Guides.NOSTEP_TITLE, Panoply.Guides.NOSTEP_LINE end   -- Nov 11 2026
  if #E.steps == 0 then return "No route yet", "Click Replan now to plan the next few levels." end
  local st = P.lastStats
  local head = st and ("Route to level %d"):format(st.goalLevel or (S.level or 1) + 1) or "Your route"
  local mins = st and st.seconds and math.floor(st.seconds / 60) or nil
  local parts = { ("Level %d"):format(S.level or 1) }
  if mins and mins > 0 then parts[#parts + 1] = ("about %d minutes of play"):format(mins) end
  if S.zone and S.zone ~= "" then parts[#parts + 1] = "you are in " .. S.zone end
  return head, table.concat(parts, ", ")
end
Menu.PlanHeadline = planHeadline

-- extra blocks a module can add to the Guide page, below the cards.
-- Each: { build = fn(p), layout = fn(p, y, W) -> y, refresh = fn(p) }. (Spec & Trainer's Trainer line and Field Kit's session strip
-- are two of them; 0.9.5 phase 4K draws the trainer as route steps and the session as one line under Progress, so the page leaves
-- those two blocks out of the area under the cards.)
Menu.levelingBlocks = Menu.levelingBlocks or {}

local Guide = {}
Menu.GuidePage = Guide

-- The look-ahead: the steps the route column lists, from the current one. Trainer steps are put in among them.
-- Returns { { step, index (E.steps index; nil for a trainer step), current } }
function Guide.RouteList(limit)
  local E = Panoply.Engine
  local out = {}
  local steps = E.steps or {}
  local first = E.index or 1
  for i = first, math.min(#steps, first + limit - 1) do out[#out + 1] = { step = steps[i], index = i, current = i == first } end
  local TS = Panoply.TrainerStep
  if TS and #out > 0 then
    local plain = {}
    for i, e in ipairs(out) do plain[i] = e.step end
    for _, s in ipairs(TS:Steps()) do
      local at = TS.Place(plain, s)
      table.insert(out, at, { step = s, trainer = true })
      table.insert(plain, at, s)
    end
  end
  return out
end

-- Line 1 of a route row: the quest's level and name in its colour (or the headline); line 2: what to do and where.
function Guide.RowLines(step)
  local ST = Panoply.StepText
  local quests = ST.Quests(step)
  local head = ST.Headline(step)
  local l1, more
  if step.isTrainer then
    l1 = step.title or head
  elseif #quests > 0 then
    local q = quests[1]
    l1 = q.level and Panoply.Difficulty.Tag(q.level, q.name) or q.name
    more = #quests - 1
  else
    l1 = head
  end
  local bits = {}
  if step.isTrainer then
    if step.detail then bits[#bits + 1] = step.detail end
  else
    if #quests > 0 and head ~= "" then bits[#bits + 1] = head end
    local zone = step.zone or (step.mapID and C.MapName and C.MapName(step.mapID)) or nil
    -- the zone, unless the headline already says it ("Talk to Marshal Dughan in Elwynn Forest")
    if zone and zone ~= "" and not (#quests > 0 and head:find(zone, 1, true)) then bits[#bits + 1] = zone end
    -- a travel step: what it saves, when the trip knows (spec 05b section 2.2)
    local saved = step.isTravel and step.trip and step.trip.saved
    if type(saved) == "number" and saved >= 60 then bits[#bits + 1] = ("Saves about %d min"):format(math.floor(saved / 60 + 0.5)) end
  end
  return l1, table.concat(bits, " · "), quests, more or 0
end

-- the "On your screen" and automation toggles: { key, label, slot, get, set, gear section, shown }
-- 0.9.7 (WoW Forever): levelling with a partner runs on the guide engine's party sync, reached only through Engine/PolestarParty.lua.
-- party() gives that module while it is the one in charge (the guide engine is running, or partner levelling is on); nil means
-- the older partner sync (Engine/Sync.lua) is the one this client runs.
local function party()
  local PP = Panoply.PolestarParty
  if not PP then return nil end
  local PE = Panoply.PolestarEngine
  if (PP.Enabled and PP:Enabled()) or (PE and PE.Active and PE:Active()) then return PP end
  return nil
end
function Menu.PartyMode() return party() ~= nil end
local function together()
  if party() then return (C.InGroup and C.InGroup()) and true or false end
  return (C.InGroup and C.InGroup()) or ((Panoply.db.syncPartner or "") ~= "")
end
Guide.TOGGLES = {
  { key = "arrow", label = "Arrow", slot = "icon.toggle.arrow", section = "arrow",
    get = function() return Panoply.db.arrowShown ~= false end, set = function(v) Panoply:SetOption("arrowShown", v) end },
  { key = "trail", label = "Trail on the maps", short = "Trail", slot = "icon.toggle.trail", section = "trail",
    get = function() return Panoply.db.trailWorldMap ~= false or Panoply.db.trailMinimap ~= false end,
    set = function(v) Panoply:SetOption("trailWorldMap", v) Panoply:SetOption("trailMinimap", v) end },
  { key = "tracker", label = "Quest tracker", short = "Tracker", slot = "icon.toggle.tracker", section = "tracker",
    shown = function() return Panoply.Modules.byKey.questTracker ~= nil end,
    get = function() return Panoply.Modules:IsOn("questTracker") end, set = function(v) Panoply.Modules:Set("questTracker", v) end },
  { key = "together", label = "Together", slot = "icon.toggle.together", section = "together", shown = together,
    get = function() if party() then return Panoply.db.partyShare ~= false end return Panoply.db.syncEnabled ~= false end,
    set = function(v) Panoply:SetOption(party() and "partyShare" or "syncEnabled", v) end },
}
Guide.AUTO = {
  { key = "autoAccept", label = "Auto accept", slot = "icon.step.accept", section = "givers" },
  { key = "autoTurnIn", label = "Auto turn-in", slot = "icon.step.turnin", section = "givers" },
  { key = "autoFly", label = "Auto fly", slot = "icon.leg.fly", section = "fastest" },
}
for _, a in ipairs(Guide.AUTO) do
  local k = a.key
  a.get = function() return Panoply.db[k] ~= false end
  a.set = function(v) Panoply:SetOption(k, v) end
end

local function toggle(parent, def, tip, body)
  local b = Skin.Button(parent, def.label, 120, 26, nil, tip, body)
  b.panoplyToggle = def.key
  b:SetIcon("Settings", 16)
  Panoply.Kit.Icon(b.icon, def.slot, { size = 16 })
  b:SetScript("OnClick", function() def.set(not def.get()) Menu:RefreshCurrent() end)
  b.gear = Skin.IconButton(parent, "Settings", 18, function() Menu:OpenGear("guide", def.section) end, def.label .. " settings",
    "Opens this in the Guide's settings.")
  b.gear.panoplyFixedW = true
  b.def = def
  return b
end

local function paintToggle(b, compact)
  local on = b.def.get() and true or false
  b.panoplyOn = on
  b:SetSelected(on)
  b:SetDimmed(not on)
  local label = compact and "" or (b.def.label .. (b.def.key == "together" and not party() and (Panoply.db.syncPartner or "") ~= "" and (" with " .. Panoply.db.syncPartner) or ""))
  b.label:SetText(label)
  b.panoplyLabel = b.def.label
  b.icon:ClearAllPoints()
  if label == "" then b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  else b.icon:SetPoint("LEFT", b, "LEFT", 8, 0); b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 10, 0) end
  b.tipBody = (b.panoplyTipBase or "") .. (on and " On now: click to turn it off." or " Off now: click to turn it on.")
end

-- a dashed outline around a row (a step the engine can't see done)
local function dashes(row, parent)
  row.dash = row.dash or {}
  for _, t in ipairs(row.dash) do t:Hide() end
  return function(x, y, w, h)
    local c = Panoply.Kit.Color("text.muted")
    local n = 0
    local function seg(px, py, sw, sh)
      n = n + 1
      local t = row.dash[n]
      if not t then t = parent:CreateTexture(nil, "ARTWORK"); row.dash[n] = t end
      t:SetColorTexture(c[1], c[2], c[3], 0.55)
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py); t:SetSize(sw, sh); t:Show()
    end
    local DASH, GAP = 6, 4
    for dx = 0, w - 1, DASH + GAP do local sw = math.min(DASH, w - dx) seg(x + dx, y, sw, 1) seg(x + dx, y - h + 1, sw, 1) end
    for dy = 0, h - 1, DASH + GAP do local sh = math.min(DASH, h - dy) seg(x, y - dy, 1, sh) seg(x + w - 1, y - dy, 1, sh) end
  end
end

-- 0.9.7: the guide picker's list, from Engine/GuidePicker.lua only: "Pick for me (recommended)" first, then the guides this
-- character can follow, the one in use ticked. No guides (the guide engine cannot run): the button says so and opens nothing.
Guide.PICK_FOR_ME = "panoply:pick-for-me"
Guide.PICKER_NONE = "not available"
Guide.PICKER_TIP = "Pick the guide this character follows. Your place in the guide you leave is kept, and a guide you come back to starts from what you have done."
function Guide.PickerItems()
  local GP = Panoply.GuidePicker
  local list = GP and GP.List and GP:List() or nil
  local out = {}
  if type(list) ~= "table" or #list == 0 then return out end
  out[1] = { value = Guide.PICK_FOR_ME, text = "Pick for me (recommended)", tip = "Panoply Suite picks the guide that fits this character best." }
  for _, g in ipairs(list) do
    local t = type(g) == "table" and g or { id = g }
    local id = t.id
    if id == nil then id = t.value end
    local text = t.text or t.title or t.name or (id ~= nil and tostring(id)) or nil
    if id ~= nil and text and text ~= "" then
      out[#out + 1] = { value = id, text = text .. ((t.finished or t.done) and "  (done)" or ""),
        tip = t.tip or "Follow this guide. Your place in the guide you leave is kept." }
    end
  end
  return out
end
function Guide.PickerCurrent()
  local GP = Panoply.GuidePicker
  return GP and GP.Current and GP:Current() or nil
end
function Guide.PickerSet(v)
  local GP = Panoply.GuidePicker
  if not GP then return false end
  if v == Guide.PICK_FOR_ME then return GP.PickForMe and GP:PickForMe() ~= nil or false end
  return GP.Pick and GP:Pick(v) and true or false
end
-- the name of the partner whose guide this character follows after a sync, when the picker engine can say (it is not part of the
-- agreed four calls, so it is asked for only when it is there)
function Guide.PickerFollowing()
  local GP = Panoply.GuidePicker
  local who = GP and GP.Following and GP:Following() or nil
  if type(who) == "string" and who ~= "" then return who end
  return nil
end
-- 0.9.7 hotfix (our in-game check: the picker cut long guide names short, "(lev..."): a guide's name is never cut and never ends
-- in "...". Words are broken at spaces into lines no wider than maxW, measured with the font string that draws them.
local function wrapLines(fs, text, maxW)
  -- the words, with a part in brackets kept together ("(levels 17 to 21)" is never split)
  local words, open = {}, nil
  for word in tostring(text or ""):gmatch("%S+") do
    if open then open = open .. " " .. word else open = word end
    local _, o = open:gsub("%(", "")
    local _, c = open:gsub("%)", "")
    if o <= c then words[#words + 1] = open open = nil end
  end
  if open then words[#words + 1] = open end
  local lines, cur = {}, nil
  for _, word in ipairs(words) do
    local try = cur and (cur .. " " .. word) or word
    fs:SetText(try)
    if cur and Skin.TextWidth(fs) > maxW then lines[#lines + 1] = cur cur = word else cur = try end
  end
  if cur then lines[#lines + 1] = cur end
  local out = table.concat(lines, "\n")
  fs:SetText(out)
  return out, #lines
end
Guide.WrapLines = wrapLines

-- the room the picker's list may take: the screen less a margin each side
Guide.PICKER_EDGE = 16
Guide.PICKER_GAP = 8          -- between two columns of the list
Guide.PICKER_COLS = 3         -- the most columns the list is split into
local function screenSize()
  local ui = _G.UIParent
  local w = ui and ui.GetWidth and ui:GetWidth()
  local h = ui and ui.GetHeight and ui:GetHeight()
  return (type(w) == "number" and w > 0) and w or 1024, (type(h) == "number" and h > 0) and h or 768
end
function Guide.PickerMaxW() local w = screenSize() return math.max(200, w - 2 * Guide.PICKER_EDGE) end
function Guide.PickerMaxH() local _, h = screenSize() return math.max(120, h - 2 * Guide.PICKER_EDGE) end

-- The picker's list, after the shared pop-out has drawn it: as wide as its longest guide name (each name on one line), up to the
-- screen's width; a name longer than that goes onto a second line (its row grows taller), so no name is ever cut short. A list
-- taller than the screen is split into two (or three) columns, read top to bottom and then the next column, so it stays in route
-- order. The list is then placed under the button (above it when there is no room below), inside the screen. Only the rows' words,
-- sizes and places change: the next pop-out opened (for any button) sets every one of them again.
function Guide.FitPickerMenu(m, owner)
  if not (m and m.rows and m:IsShown() and m.panoplyOwner == owner) then return m end
  -- never narrower than the shared pop-out drew it
  local capW, capH = math.max(Guide.PickerMaxW(), m:GetWidth() or 0), Guide.PickerMaxH()
  local GAP = Guide.PICKER_GAP
  local rows = {}
  for _, r in ipairs(m.rows) do
    if r:IsShown() then
      local words = r.panoplyRoom and r.text:IsShown() and r.item and type(r.item.text) == "string"
      rows[#rows + 1] = { r = r, words = words, h = r:GetHeight() or 22 }
    end
  end
  if #rows == 0 then return m end
  -- the width one column needs to show every name on one line
  local need = m:GetWidth() or 190
  for _, e in ipairs(rows) do
    if e.words then
      local r = e.r
      r.text.panoplyFullText, r.text.panoplyCut = nil, nil
      r.text:SetText(r.item.text)
      need = math.max(need, math.ceil(Skin.TextWidth(r.text)) + r.panoplyRoom)
    end
  end
  -- each row's words and height in a column colW wide (a name too long for it goes onto more lines)
  local function fill(colW)
    for _, e in ipairs(rows) do
      local r = e.r
      e.hh = e.h
      if e.words then
        local room = colW - r.panoplyRoom
        r.text:SetText(r.item.text)
        r.panoplyWrapped = nil
        if Skin.TextWidth(r.text) > room then
          wrapLines(r.text, r.item.text, room)
          r.panoplyWrapped = true
          e.hh = math.max(e.h, math.ceil(Skin.TextHeight(r.text, room)) + 8)
        end
      end
    end
  end
  -- rows split into cols columns, top to bottom (each column takes its share of the rows, in order): { first row of each column }
  local function split(cols)
    local per = math.ceil(#rows / cols)
    local starts, tallest = {}, 0
    for c = 1, cols do
      local a = (c - 1) * per + 1
      if a > #rows then break end
      starts[#starts + 1] = a
      local h = 0
      for i = a, math.min(#rows, a + per - 1) do h = h + rows[i].hh end
      tallest = math.max(tallest, h)
    end
    return starts, per, tallest + 20
  end
  local cols, colW, starts, per, mh
  for n = 1, Guide.PICKER_COLS do
    cols = n
    colW = math.min(need, math.floor((capW - (n - 1) * GAP) / n))
    fill(colW)
    starts, per, mh = split(n)
    if mh <= capH or colW < 200 then break end
  end
  cols = #starts
  local w = cols * colW + (cols - 1) * GAP
  for c, a in ipairs(starts) do
    local x, y = 6 + (c - 1) * (colW + GAP), -10
    for i = a, math.min(#rows, a + per - 1) do
      local e = rows[i]
      local r = e.r
      r:SetHeight(e.hh)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", m, "TOPLEFT", x, y)
      r:SetPoint("TOPRIGHT", m, "TOPLEFT", x + colW - 12, y)
      y = y - e.hh
    end
  end
  m:SetSize(w, mh)
  m.panoplyColumns = cols
  -- under the button, its left edges together, moved left as far as the screen needs; above the button when there is no room
  -- below; and never past the top or the bottom of the screen
  local ui = _G.UIParent
  local ol, ob, ot = owner.GetLeft and owner:GetLeft(), owner.GetBottom and owner:GetBottom(), owner.GetTop and owner:GetTop()
  if ui and type(ol) == "number" and type(ob) == "number" then
    local es = ((owner.GetEffectiveScale and owner:GetEffectiveScale()) or 1) / ((ui.GetEffectiveScale and ui:GetEffectiveScale()) or 1)
    local sw, sh = screenSize()
    local E = Guide.PICKER_EDGE
    local x = math.max(E, math.min(ol * es, sw - E - w))
    local top = ob * es - 4
    if top - mh < E and type(ot) == "number" and ot * es + 4 + mh <= sh - E then top = ot * es + 4 + mh end
    top = math.max(math.min(top, sh - E), math.min(sh - E, mh + E))
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", ui, "BOTTOMLEFT", x, top)
  end
  return m
end

-- The picker's button: the guide in use; "Following <name>'s guide" while synced to a partner; "not available" (and no list) when
-- there is no guide to pick. Its width is the slot's 200, more when the words in it need more, up to the row's width (maxW); words
-- longer than that wrap onto a second line and the button grows taller. Never cut short, never "...".
Guide.PICKER_W = 200
Guide.PICKER_H = 28
local function pickerSetup(dd)
  local opts = dd.panoplyDropdown
  local refresh = dd.Refresh
  local open = dd.Open
  local function room(self) return math.max(20, (self:GetWidth() or Guide.PICKER_W) - 20 - Panoply.Kit.SECTION.chevron - Skin.SP.s) end
  -- the words, whole: on one line when they fit the button, else on more lines with the button taller
  local function whole(self, text)
    local lbl, r = self.label, room(self)
    lbl.panoplyFullText, lbl.panoplyCut = nil, nil
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    lbl:SetWidth(r)
    lbl:SetText(text)
    local h = Guide.PICKER_H
    self.panoplyWrapped = nil
    if Skin.TextWidth(lbl) > r then
      if lbl.SetWordWrap then lbl:SetWordWrap(true) end
      wrapLines(lbl, text, r)
      self.panoplyWrapped = true
      h = math.max(h, math.ceil(Skin.TextHeight(lbl, r)) + 10)
    end
    self:SetHeight(h)
    self.panoplyText = text
  end
  function dd:Refresh()
    local none = #self:Items() == 0
    opts.empty = none and Guide.PICKER_NONE or "pick a guide"
    refresh(self)
    local who = (not none) and Guide.PickerFollowing() or nil
    self.panoplyFollowing = who
    whole(self, who and ("Following %s's guide"):format(who) or self.panoplyText or "")
    self:SetEnabledLook(not none)
    self.tipBody = none and "There is no guide to pick right now."
      or (who and (("You follow %s's guide. Picking another guide ends the sync.\n\n"):format(who)) or "") .. Guide.PICKER_TIP
  end
  dd.panoplyFit = function(self, minW, maxW)
    self:Refresh()
    local lbl = self.label
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    lbl:SetText(self.panoplyText or "")
    local w = math.max(Guide.PICKER_W, math.ceil(Skin.TextWidth(lbl)) + 20 + Panoply.Kit.SECTION.chevron + Skin.SP.s)
    if maxW and w > maxW then w = maxW end
    self:SetWidth(w)
    self:Refresh()
    return w
  end
  function dd:Open()
    return Guide.FitPickerMenu(open(self), self)
  end
  dd:Refresh()
end

Menu:RegisterTab("Guide", function(p)
  local K = Panoply.Kit
  local GP = Panoply.GuideParts
  p.expanded = {}
  -- the top row: Guide, Follows, ⋯
  -- 0.9.7: the guide picker, in the slot the Style menu had. Our own Kit.Dropdown and pop-out (no UIDropDownMenu); a pick made in a
  -- fight is made when the fight ends (guard), and the guide the player leaves keeps its place (Engine/GuidePicker.lua).
  p.guideDD = K.Dropdown(p, { page = "guide", label = "Guide: ", width = 200, height = 28, menuWidth = 280, tip = "Guide",
    tipBody = Guide.PICKER_TIP, empty = Guide.PICKER_NONE, guard = function() return true end,
    items = Guide.PickerItems, get = Guide.PickerCurrent, set = Guide.PickerSet,
    onChange = function() Menu:RefreshCurrent() end })
  pickerSetup(p.guideDD)
  p.followsDD = GP.Follows(p, { page = "guide", width = 240, height = 28, onChange = function() Menu:RefreshCurrent() end })
  p.moreBtn = Skin.Button(p, "...", 34, 28, function(b)
    Skin.Menu(b, {
      { text = "Reset plan...", tip = "Forget this route. It asks first.", func = function() p.confirmReset = true Menu:RefreshCurrent() end },
      { text = "Report a problem", tip = "The report window opens with this step filled in.", func = function() if Panoply.ReportWindow then Panoply.ReportWindow:Open() end end },
    }, { width = 200 })
  end, "More", "Reset plan, or report a problem with this step.")
  p.moreBtn.panoplyFixedW = true
  -- Reset plan asks first, on the page
  local cf = Skin.Card(p); p.confirm = cf; cf.panoplyGapOK = true
  cf.text = Skin.Ink(cf, 12)
  cf.text:SetText("Reset your route? Your plan and your place in it are forgotten. You can build a new one any time.")
  cf.yes = Skin.Button(cf, "Reset plan", 110, 26, function() p.confirmReset = nil Panoply:ResetPlan() Menu:RefreshCurrent() end, "Reset plan",
    "Forgets this route now.")
  cf.no = Skin.Button(cf, "Cancel", 80, 26, function() p.confirmReset = nil Menu:RefreshCurrent() end, "Cancel", "Keeps your route.")
  cf:Hide()

  -- NEXT STEP (a Kit.Section: open or closed is remembered; closed, its header says the step)
  local nsec
  nsec = K.Section(p, "guide", "next", { title = "Next step",
    summary = function() if nsec:IsOpen() then return "" end return nsec.stepText or "" end })
  local n = nsec.card; p.nextCard = n; n.panoplyGapOK = true
  n.sec, n.host = nsec, nsec.body
  local nh = n.host
  n.typeIcon = nh:CreateTexture(nil, "ARTWORK"); n.typeIcon:SetSize(22, 22)
  n.head = Skin.Heading(nh, 17)
  n.num = Skin.Ink(nh, 11, Skin.colors.inkSoft)
  n.why = Skin.Ink(nh, 12, Skin.colors.inkSoft)
  n.where = Skin.Ink(nh, 12, Skin.colors.inkSoft)
  n.lines, n.pips, n.counts = {}, {}, {}
  for i = 1, 3 do
    n.lines[i] = Skin.Ink(nh, 12)
    n.pips[i] = K.Pips(nh, { accent = "secondary" })
    n.counts[i] = K.ProgressBar(nh, { h = 6, accent = "secondary" })
  end
  n.trip = Panoply.Trip.LineWidget(nh, { size = 14, font = 11 })
  n.buttons = {}
  local function btn(parent, list, label, w, tip, body, fn)
    local b = Skin.Button(parent, label, w, 28, fn, tip, body)
    list[#list + 1] = b
    return b
  end
  n.pointBtn = btn(nh, n.buttons, "Point the arrow", 130, "Point the arrow", "Shows the arrow and points it at this step.", function() Guide.PointArrow() end)
  n.pointBtn:SetSelected(true)
  n.skipBtn = btn(nh, n.buttons, "Skip step", 100, "Skip step", "Move past the current step.", function() Panoply.Engine:Next() end)
  n.doneBtn = btn(nh, n.buttons, "Done", 80, "Done", "The game can't tell when this step is done. Tick it when you have done it.",
    function() local E = Panoply.Engine Panoply.StepText.MarkDone(E:Current()) Menu:RefreshCurrent() end)
  n.setupBtn = btn(nh, n.buttons, "Run setup", 110, "Run setup", "The short setup questions: settings, how much you have played, class plan, group quests, solo or partner. Nothing changes until you press Start guiding.", function() Panoply.Wizard:Start() end)
  n.tourBtn = btn(nh, n.buttons, "Take the tour", 120, "Take the tour", "A short walk through every part of Panoply Suite. /panoply tour replays it any time.", function() Panoply.Tour:Start() end)
  n.replanBtn = Skin.IconButton(nh, "Route", 26, function() Panoply:Replan("menu") end, "Replan now",
    "Plans the trip to this step again: the roads, flights, boats and hearthstone. The guide's own steps stay as they are.")
  n.replanBtn.panoplyFixedW = true
  n.buttons[#n.buttons + 1] = n.replanBtn
  -- progress
  n.progLabel = Skin.Label(nh, 10, Skin.colors.inkSoft); n.progLabel:SetText("PROGRESS")
  n.levelBar = Skin.Bar(nh, 8, true)
  n.rested = n.levelBar:CreateTexture(nil, "ARTWORK", nil, -1)
  Skin.Solid(n.rested, Skin.colors.progress or Skin.colors.accent, 0.35); n.rested:Hide()
  n.levelHit = CreateFrame("Frame", nil, nh); n.levelHit:SetAllPoints(n.levelBar)
  Skin.Tooltip(n.levelHit, "Level", "")
  if n.levelHit.EnableMouse then n.levelHit:EnableMouse(true) end
  n.levelHit:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  n.levelHit:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  n.pace = Skin.Ink(nh, 11, Skin.colors.inkSoft)
  -- this session, one muted line under Progress (Field Kit's "Show this session on the Guide page"; its words are Misc.StripText's)
  n.session = Skin.Ink(nh, 11, Skin.colors.inkSoft)
  n.routeBar = Skin.Bar(nh, 8)
  n.routePips = {}
  n.routeLabel = Skin.Ink(nh, 11, Skin.colors.inkSoft)
  -- no guide here (spec 05b section 2.2)
  n.ngText = Skin.Heading(nh, 15)
  n.ngRec = Skin.Button(nh, "Record mode", 130, 26, function()
    local NG = Panoply.NoGuide
    if NG then NG:SetRecording(not NG:Recording()) end
    Menu:RefreshCurrent()
  end, "Record mode", "Saves the quests you do here, so a guide for this area can be made later.")
  n.ngCount = Skin.Ink(nh, 11, Skin.colors.inkSoft)
  n.ngGo = Skin.Button(nh, "Find a place with a guide", 190, 26, function()
    if Panoply.Map and Panoply.Map.Navigate then Panoply.Map.Navigate:Toggle() else Menu:Open("map") end
  end, "Go to", "Opens the Map's Go to: search for a town or zone that has a guide, and the arrow takes you there.")
  -- dungeon mode (spec 05b section 2.2)
  n.dgName = Skin.Heading(nh, 15)
  n.dgBosses, n.dgQuests = {}, {}
  n.dgOpen = Skin.Button(nh, "Open the Dungeons window", 190, 26, function()
    if Panoply.Map and Panoply.Map.Instances then Panoply.Map.Instances:Toggle() end
  end, "Dungeons window", "The floor plan, the bosses in order and your quests for this dungeon.")

  -- ON YOUR SCREEN
  local ssec = K.Section(p, "guide", "screen", { title = "On your screen" })
  local s = ssec.card; p.screenCard = s; s.panoplyGapOK = true
  s.sec, s.host = ssec, ssec.body
  s.toggles, s.auto = {}, {}
  local TIPS = { arrow = "The arrow that points to your step.", trail = "The dotted trail to your step, on the world map and the minimap.",
    tracker = "Panoply Suite's quest tracker.", together = "Level together: you and your partner follow one route." }
  for _, d in ipairs(Guide.TOGGLES) do
    local b = toggle(s.host, d, d.label, TIPS[d.key])
    b.panoplyTipBase = TIPS[d.key]
    s.toggles[#s.toggles + 1] = b
  end
  s.autoLabel = Skin.Label(s.host, 10, Skin.colors.inkSoft); s.autoLabel:SetText("AUTOMATION")
  for _, d in ipairs(Guide.AUTO) do
    local b = toggle(s.host, d, d.label, "Hold Shift to skip.")
    b.panoplyTipBase = "Hold Shift to skip."
    s.auto[#s.auto + 1] = b
  end

  -- YOUR ROUTE
  local rsec = K.Section(p, "guide", "route", { title = "Your route" })
  local r = rsec.card; p.routeCard = r; r.panoplyGapOK = true
  r.sec, r.host = rsec, rsec.body
  r.head = Skin.Heading(r.host, 15)
  r.sub = Skin.Ink(r.host, 11, Skin.colors.inkSoft)
  r.doneLine = Skin.Ink(r.host, 11, Skin.colors.inkSoft)
  r.paused = Skin.Ink(r.host, 12, Skin.colors.inkSoft)
  r.rows = {}
  for i = 1, ROUTE_MAX do
    local hl = r.host:CreateTexture(nil, "BACKGROUND"); Skin.Solid(hl, Skin.colors.accent, 0.10); hl:Hide()
    local bar = r.host:CreateTexture(nil, "OVERLAY"); Skin.Solid(bar, Skin.colors.accent, 0.9)
    bar:SetPoint("TOPLEFT", hl, "TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", hl, "BOTTOMLEFT", 0, 0); bar:SetWidth(2); bar:Hide()
    hl.bar = bar
    local icon = r.host:CreateTexture(nil, "OVERLAY"); icon:SetSize(16, 16)
    local txt = Skin.Ink(r.host, 12)
    local line2 = Skin.Ink(r.host, 11, Skin.colors.inkSoft)
    local more = Skin.Button(r.host, "+1 more", 70, 18, nil, "This step's quests", "Click to list every quest of this step here.")
    local chip = K.StatusChip(r.host, "idle", Panoply.StepText.WONT_HOLD)
    local done = Skin.Button(r.host, "Done", 56, 20, nil, "Done", "The game can't tell when this step is done. Tick it when you have done it.")
    done:SetIcon("Check", 12)
    -- a trainer step's tooltip (the mount fund): a frame over the row, shown only when the step has one
    local tipHit = CreateFrame("Frame", nil, r.host)
    tipHit:SetAllPoints(hl)
    if tipHit.EnableMouse then tipHit:EnableMouse(true) end
    tipHit:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
    tipHit:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    tipHit:Hide()
    local row = { hl = hl, text = txt, line2 = line2, icon = icon, more = more, chip = chip, done = done, extra = {}, tipHit = tipHit }
    more:SetScript("OnClick", function() local k = row.panoplyKey if k then p.expanded[k] = not p.expanded[k] Menu:RefreshCurrent() end end)
    done:SetScript("OnClick", function() if row.step then Panoply.StepText.MarkDone(row.step) Menu:RefreshCurrent() end end)
    r.rows[i] = row
  end
  r.hint = Skin.Ink(r.host, 11, Skin.colors.warn)
  r.showAll = Skin.Button(r.host, "Show route", 110, 24, function() p.showAll = not p.showAll Menu:RefreshCurrent() end, "Show route",
    "Shows the whole look-ahead here, or only the next few steps.")

  for _, b in ipairs(Menu.levelingBlocks) do b.build(p) end

  local function put(o, parent, x, y, w)
    o:ClearAllPoints(); o:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if w then o:SetWidth(w) end
  end
  local function text(o, parent, x, y, w)
    if (o:GetText() or "") == "" then o:Hide() return y end
    o:Show(); put(o, parent, x, y, w)
    local h = math.ceil(Skin.TextHeight(o, w)); o:SetHeight(h)
    return y - h
  end

  function p:Layout()
    local SP, TH = Skin.SP, Skin.TextHeight
    local W = self.width
    local band = K.Band(W)
    self.band = band
    local gap = SP.m
    local v = self.view or {}
    local pad = 12
    local y = 0
    -- the top row
    self.followsDD:Fit(170, math.min(300, W - 60))
    local top = { self.guideDD, self.followsDD, self.moreBtn }
    for _, o in ipairs(top) do o:Show() end
    local th = Skin.FlowButtons(self, top, 2, 0, W - 4, SP.s, 60)
    y = th + SP.s
    if self.confirmReset then
      cf:Show(); cf:ClearAllPoints(); cf:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -y); cf:SetWidth(W - 4)
      local cy = -10
      cy = text(cf.text, cf, pad, cy, W - 4 - 2 * pad) - SP.s
      local bh = Skin.FlowButtons(cf, { cf.yes, cf.no }, pad, cy, W - 4 - 2 * pad, SP.s, 70)
      cf:SetHeight(-cy + bh + 10)
      y = y + cf:GetHeight() + SP.s
    else cf:Hide() end
    for _, c in ipairs({ self.nextCard, self.screenCard, self.routeCard }) do c:Show() end
    -- columns: Wide two, Medium and Narrow one
    local two = band == "wide"
    local lw = two and math.floor((W - 4 - gap) * 0.52) or (W - 4)
    local rw = two and (W - 4 - gap - lw) or (W - 4)
    local inner = lw - 2 * pad
    local compact = band == "narrow"
    -- NEXT STEP
    local _, nopen = n.sec:Begin(self, 2, -y, lw)
    local ny = -SP.xs
    -- the session line is placed under Progress only (Field Kit's strip block drew it under the cards before)
    if self.session then for _, o in pairs(self.session) do if o.Hide then o:Hide() end end end
    local hide = { n.typeIcon, n.head, n.num, n.why, n.where, n.trip, n.progLabel, n.levelBar, n.levelHit, n.pace, n.routeBar, n.routeLabel,
      n.ngText, n.ngRec, n.ngCount, n.ngGo, n.dgName, n.dgOpen }
    for _, o in ipairs(hide) do o:Hide() end
    n.session:Hide()
    for i = 1, 3 do n.lines[i]:Hide() n.pips[i]:Hide() n.counts[i]:Hide() end
    for _, pp in ipairs(n.routePips) do pp:Hide() end
    for _, o in ipairs(n.dgBosses) do o:Hide() end
    for _, o in ipairs(n.dgQuests) do o:Hide() end
    for _, b in ipairs(n.buttons) do b:Hide() end
    if nopen and v.mode == "noguide" then
      ny = text(n.ngText, nh, pad, ny, inner) - SP.s
      n.ngRec:Show(); n.ngGo:Show()
      local bh = Skin.FlowButtons(nh, { n.ngRec, n.ngGo }, pad, ny, inner, SP.s, 100)
      ny = ny - bh - SP.xs
      ny = text(n.ngCount, nh, pad, ny, inner) - SP.m
    elseif nopen and v.mode == "dungeon" then
      ny = text(n.dgName, nh, pad, ny, inner) - SP.s
      for _, o in ipairs(n.dgBosses) do if o.panoplyUsed then ny = text(o, nh, pad, ny, inner) - 2 end end
      ny = ny - SP.s
      for _, o in ipairs(n.dgQuests) do if o.panoplyUsed then ny = text(o, nh, pad, ny, inner) - 2 end end
      ny = ny - SP.s
      n.dgOpen:Show()
      ny = ny - Skin.FlowButtons(nh, { n.dgOpen }, pad, ny, inner, SP.s, 100) - SP.m
    elseif nopen then
      -- the step
      n.typeIcon:Show(); put(n.typeIcon, nh, pad, ny - 1)
      local hx = pad + 22 + SP.s
      local hy = text(n.head, nh, hx, ny, inner - 22 - SP.s)
      ny = math.min(hy, ny - 22) - SP.xs
      ny = text(n.num, nh, pad, ny, inner) - SP.xs
      ny = text(n.why, nh, pad, ny, inner)
      ny = text(n.where, nh, pad, ny - ((n.why:GetText() or "") ~= "" and SP.xs or 0), inner) - SP.s
      -- live progress: the words, then pips (6 or fewer) or a count bar
      for i = 1, 3 do
        local l = n.lines[i]
        if (l:GetText() or "") ~= "" then
          local g = l.panoplyCount
          local rightW = 0
          if g and K.UsePips(g.total) then
            rightW = n.pips[i]:Set(g.have, g.total) + SP.s
            n.pips[i]:Show()
          elseif g then
            rightW = math.min(120, math.floor(inner * 0.3)) + SP.s
            n.counts[i]:SetBarWidth(rightW - SP.s); n.counts[i]:SetValue(g.have, g.total); n.counts[i]:Show()
          end
          local ly = text(l, nh, pad, ny, inner - rightW)
          if g and K.UsePips(g.total) then put(n.pips[i], nh, pad + inner - rightW + SP.s, ny - 3)
          elseif g then put(n.counts[i], nh, pad + inner - rightW + SP.s, ny - 5) end
          ny = ly - SP.xs
        end
      end
      -- the trip line
      local tripH = n.trip:Fill(inner)
      if tripH > 0 then put(n.trip, nh, pad, ny - SP.xs); ny = ny - SP.xs - tripH - SP.s end
      -- the buttons (Point the arrow first; Done only on a step the engine can't see done)
      local list = {}
      for _, b in ipairs(n.buttons) do if not b.panoplyFlowSkip then list[#list + 1] = b; b:Show() end end
      local fh = Skin.FlowButtons(nh, list, pad, ny - SP.xs, inner, SP.s, 80)
      ny = ny - SP.xs - fh - SP.m
      -- progress
      n.progLabel:Show(); put(n.progLabel, nh, pad, ny); ny = ny - math.ceil(TH(n.progLabel, inner)) - SP.xs
      ny = ny - Skin.BarLabelSpace(n.levelBar)
      n.levelBar:Show(); n.levelHit:Show()
      n.levelBar:ClearAllPoints(); n.levelBar:SetPoint("TOPLEFT", nh, "TOPLEFT", pad, ny); n.levelBar:SetWidth(inner); n.levelBar.panoplyWidth = inner
      n.levelBar.text:SetWidth(inner)
      n.levelBar:SetProgress(n.levelBar.progress or 0, n.levelBar.text:GetText())
      -- the rested part, after the fill
      local rp = n.restFrac or 0
      local fp = n.levelBar.progress or 0
      if rp > 0 and fp < 1 then
        local fx = math.floor(inner * fp)
        local rwid = math.max(2, math.min(math.floor(inner * rp), inner - fx))
        n.rested:ClearAllPoints(); n.rested:SetPoint("TOPLEFT", n.levelBar, "TOPLEFT", fx, 0); n.rested:SetSize(rwid, 8); n.rested:Show()
      else n.rested:Hide() end
      ny = ny - 8 - SP.xs
      ny = text(n.pace, nh, pad, ny, inner) - SP.s
      -- the route: pips up to 10 steps, else the bar
      local tot = n.routeTotal or 0
      if tot > 0 and tot <= PIPS_UPTO then
        local px = pad
        for i = 1, tot do
          local pp = n.routePips[i]
          if not pp then pp = nh:CreateTexture(nil, "ARTWORK"); pp:SetTexture(Skin.TEX.CircleMask); n.routePips[i] = pp end
          pp:SetSize(9, 9)
          local c = i < (n.routeAt or 1) and Skin.colors.progress or (i == (n.routeAt or 1) and Skin.colors.accent or Skin.colors.dim)
          pp:SetVertexColor(c[1], c[2], c[3], 1)
          pp:ClearAllPoints(); pp:SetPoint("TOPLEFT", nh, "TOPLEFT", px, ny - 2); pp:Show()
          px = px + 9 + 4
        end
        put(n.routeLabel, nh, px + SP.xs, ny, inner - (px - pad) - SP.xs); n.routeLabel:Show()
        n.routeLabel:SetHeight(math.ceil(TH(n.routeLabel, inner - (px - pad) - SP.xs)))
        ny = ny - math.max(12, math.ceil(TH(n.routeLabel, inner - (px - pad) - SP.xs))) - SP.s
      elseif tot > 0 then
        ny = ny - Skin.BarLabelSpace(n.routeBar)
        n.routeBar:Show(); n.routeBar:ClearAllPoints(); n.routeBar:SetPoint("TOPLEFT", nh, "TOPLEFT", pad, ny); n.routeBar:SetWidth(inner)
        n.routeBar.panoplyWidth = inner; n.routeBar.text:SetWidth(inner)
        n.routeBar:SetProgress(n.routeBar.progress or 0, n.routeBar.text:GetText())
        ny = ny - 8 - SP.s
      end
      -- the session, one muted line (Field Kit's switch "Show this session on the Guide page")
      if self.sessionOn then ny = text(n.session, nh, pad, ny, inner) - SP.s else n.session:Hide() end
    end
    local leftBottom = n.sec:Done(nopen and (-ny) or 0)
    -- ON YOUR SCREEN
    local _, sopen = s.sec:Begin(self, 2, -(y + leftBottom + gap), lw)
    local sy = 0
    for _, b in ipairs(s.toggles) do b:Hide() b.gear:Hide() end
    for _, b in ipairs(s.auto) do b:Hide() b.gear:Hide() end
    s.autoLabel:Hide()
    if sopen then
      sy = -SP.xs
      -- each toggle and its gear are one unit: they wrap together, the gear just after its toggle, middle-aligned
      local function row(list)
        local cx, cy, rowH = 0, 0, 0
        for _, b in ipairs(list) do
          if not (b.def.shown and not b.def.shown()) then
            paintToggle(b, compact)
            local w
            if compact then w = 34 b:SetWidth(w) else w = Skin.FitButton(b, 60, math.max(60, inner - 22)) end
            local gw = b.gear:GetWidth() or 18
            local unit = w + 2 + gw
            if cx > 0 and cx + unit > inner then cx, cy, rowH = 0, cy + rowH + SP.s, 0 end
            b:Show(); b.gear:Show()
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", s.host, "TOPLEFT", pad + cx, sy - cy)
            b.gear:ClearAllPoints(); b.gear:SetPoint("LEFT", b, "RIGHT", 2, 0)
            cx = cx + unit + SP.s
            rowH = math.max(rowH, b:GetHeight() or 26)
          end
        end
        return cy + rowH
      end
      sy = sy - row(s.toggles) - SP.s
      s.autoLabel:Show(); put(s.autoLabel, s.host, pad, sy); sy = sy - math.ceil(TH(s.autoLabel, inner)) - SP.xs
      sy = sy - row(s.auto)
    end
    leftBottom = leftBottom + gap + s.sec:Done(-sy)
    -- YOUR ROUTE
    local rx, ry0 = 2, y
    if two then rx = 2 + lw + gap else ry0 = y + leftBottom + gap end
    local rin = rw - 2 * pad
    local _, ropen = r.sec:Begin(self, rx, -ry0, rw)
    local ry = 0
    for _, row in ipairs(r.rows) do
      row.hl:Hide(); row.hl.bar:Hide(); row.icon:Hide(); row.text:Hide(); row.line2:Hide(); row.more:Hide(); row.chip:Hide(); row.done:Hide()
      row.tipHit:Hide()
      for _, t in ipairs(row.dash or {}) do t:Hide() end
      for _, e in ipairs(row.extra) do e:Hide() end
    end
    r.doneLine:Hide(); r.paused:Hide(); r.hint:Hide(); r.showAll:Hide()
    if ropen then
      local rh0 = r.host
      ry = -SP.xs
      ry = text(r.head, rh0, pad, ry, rin) - SP.xs
      ry = text(r.sub, rh0, pad, ry, rin) - SP.s
      if v.mode == "dungeon" or v.mode == "noguide" then
        ry = text(r.paused, rh0, pad, ry, rin) - SP.s
      else
        ry = text(r.doneLine, rh0, pad, ry, rin) - SP.xs
        for _, row in ipairs(r.rows) do
          if row.panoplyUsed then
            local top = ry
            local x0 = pad + 24
            local rightW = 0
            if row.panoplyUndetect then
              local cw = row.chip:Set("idle", Panoply.StepText.WONT_HOLD)
              Skin.FitButton(row.done, 50, 90)
              rightW = math.max(cw, row.done:GetWidth()) + SP.s
            end
            local tw = rin - 24 - rightW
            row.icon:Show(); row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", rh0, "TOPLEFT", pad, ry - 3)
            local y1 = text(row.text, rh0, x0, ry - 3, tw)
            local y2 = text(row.line2, rh0, x0, y1 - 1, tw)
            local yy = y2
            if row.panoplyMore > 0 then
              Skin.FitButton(row.more, 60, 120)
              row.more:Show(); row.more:ClearAllPoints(); row.more:SetPoint("TOPLEFT", rh0, "TOPLEFT", x0, yy - 2)
              yy = yy - 2 - row.more:GetHeight()
              for _, e in ipairs(row.extra) do if e.panoplyUsed then yy = text(e, rh0, x0 + 8, yy - 1, tw - 8) end end
            end
            if row.panoplyUndetect then
              row.chip:Show(); row.chip:ClearAllPoints(); row.chip:SetPoint("TOPRIGHT", rh0, "TOPLEFT", pad + rin, ry - 3)
              row.done:Show(); row.done:ClearAllPoints(); row.done:SetPoint("TOPRIGHT", rh0, "TOPLEFT", pad + rin, ry - 3 - row.chip:GetHeight() - 2)
              yy = math.min(yy, ry - 3 - row.chip:GetHeight() - 2 - row.done:GetHeight())
            end
            local rh = math.max(20, top - yy + 4)
            row.hl:ClearAllPoints()
            row.hl:SetPoint("TOPLEFT", rh0, "TOPLEFT", 4, top); row.hl:SetPoint("TOPRIGHT", rh0, "TOPRIGHT", -4, top); row.hl:SetHeight(rh)
            if row.panoplyCurrent then row.hl:Show(); row.hl.bar:Show() end
            if row.tipHit.tipBody then
              local lv = (rh0:GetFrameLevel() or 1) + 1
              row.tipHit:SetFrameLevel(lv) row.tipHit:Show()
              row.done:SetFrameLevel(lv + 1) row.more:SetFrameLevel(lv + 1)
            end
            if row.panoplyUndetect then dashes(row, rh0)(4, top, rin + 2 * pad - 8, rh) end
            ry = top - rh - 2
          end
        end
        if v.moreRows then
          r.showAll.label:SetText(p.showAll and "Show less" or "Show route")
          r.showAll:Show(); Skin.FitButton(r.showAll, 90, 160)
          put(r.showAll, rh0, pad, ry - SP.xs); ry = ry - SP.xs - r.showAll:GetHeight()
        end
        ry = ry - SP.s
        ry = text(r.hint, rh0, pad, ry, rin) - SP.xs
      end
    end
    local routeH = r.sec:Done(-ry)
    if two then y = y + math.max(leftBottom, routeH) + gap else y = y + leftBottom + gap + routeH + gap end
    -- extra blocks (the pace mark on the level bar) go below, full width
    local yy = -y
    for _, b in ipairs(Menu.levelingBlocks) do if not Guide.Replaced(b) then yy = b.layout(self, yy, W) end end
    return -yy + SP.m
  end
end, function(p)
  local E, S, ST = Panoply.Engine, Panoply.State, Panoply.StepText
  local n, r = p.nextCard, p.routeCard
  local v = {}
  p.view = v
  p.guideDD:Refresh(); p.followsDD:Refresh()
  local function refreshBlocks()
    for _, b in ipairs(Menu.levelingBlocks) do b.refresh(p) end
    -- the Trainer line is route steps now: its block draws nothing on this page
    local tr = p.trainer
    if tr then for _, o in pairs(tr) do if o.Hide then o:Hide() end end end
    local se = p.session
    p.sessionOn = se and se.text:IsShown() and true or nil
    n.session:SetText(p.sessionOn and (se.text:GetText() or "") or "")
    if se then for _, o in pairs(se) do if o.Hide then o:Hide() end end end
  end
  local DG = Panoply.Dungeon
  if DG and DG.Inside and DG:Inside() and DG.run then v.mode = "dungeon"
  elseif Panoply:NoGuideHere() then v.mode = "noguide" end
  local cur = E:Current()
  local steps = E.steps
  local total = #steps
  -- the step
  if v.mode == "noguide" then
    n.sec.stepText = "No guide for this area yet."
    n.ngText:SetText("No guide for this area yet.")
    local NG = Panoply.NoGuide
    local rec = NG and NG:Recording()
    n.ngRec.label:SetText(rec and "Record mode: On" or "Record mode: Off")
    n.ngRec:SetSelected(rec)
    local FR = Panoply.QuestRecorder
    local okS, st = pcall(function() return FR and FR:Stats() end)
    local q = okS and st and st.quests or 0
    n.ngCount:SetText(("%d %s recorded so far."):format(q, q == 1 and "quest" or "quests"))
  elseif v.mode == "dungeon" then
    local run = DG.run
    n.sec.stepText = run.name or "Dungeon"
    n.dgName:SetText(run.name or "Dungeon")
    local nextB = DG:NextBoss()
    for i, b in ipairs(run.bosses or {}) do
      local o = n.dgBosses[i]
      if not o then o = Skin.Ink(n.host, 12) n.dgBosses[i] = o end
      local done = DG:BossDone(b.n)
      o:SetText(("%d. %s%s"):format(i, b.name or "?", done and "  (done)" or (b.n == nextB and "  - next" or "")))
      local c = b.n == nextB and Skin.colors.heading or (done and Skin.colors.done or Skin.colors.ink)
      o:SetTextColor(c[1], c[2], c[3], 1)
      o.panoplyUsed = true
    end
    for i = #(run.bosses or {}) + 1, #n.dgBosses do n.dgBosses[i].panoplyUsed = nil end
    local qs = DG:HeldQuests()
    for i, q in ipairs(qs) do
      local o = n.dgQuests[i]
      if not o then o = Skin.Ink(n.host, 12) n.dgQuests[i] = o end
      local ready = DG:QuestReady(q.id)
      o:SetText((ready and "Done: " or "") .. (q.name or "a quest") .. ((not ready and q.text) and (": " .. q.text) or ""))
      local c = ready and Skin.colors.done or Skin.colors.ink
      o:SetTextColor(c[1], c[2], c[3], 1)
      o.panoplyUsed = true
    end
    for i = #qs + 1, #n.dgQuests do n.dgQuests[i].panoplyUsed = nil end
  elseif cur then
    n.sec.stepText = ST.Headline(cur)
    n.head:SetText(ST.Headline(cur))
    Panoply.Kit.Icon(n.typeIcon, ST.TypeSlot(cur), { size = 22 })
    n.num:SetText(ST.NumberText(cur))
    n.why:SetText(ST.Why(cur))
    local loc = ST.LocationNote(cur)
    n.where:SetText(loc or "")
    local lines = ST.Progress(cur)
    for i, l in ipairs(n.lines) do
      local pl = lines[i]
      if pl then
        l:SetText((pl.done and "Done: " or "") .. pl.text)
        local c = pl.done and Skin.colors.done or Skin.colors.ink
        l:SetTextColor(c[1], c[2], c[3], 1)
        local have, need = tostring(pl.text):match("(%d+)%s*/%s*(%d+)")
        l.panoplyCount = have and { have = tonumber(have), total = tonumber(need) } or nil
        if l.panoplyCount and (l.panoplyCount.total or 0) <= 0 then l.panoplyCount = nil end
      else l:SetText("") l.panoplyCount = nil end
    end
  else
    local head, sub = ST.WhatNow()
    n.sec.stepText = head
    n.head:SetText(head)
    Skin.SetIcon(n.typeIcon, "Leveling")
    n.num:SetText("")
    n.why:SetText(sub or "")
    n.where:SetText("")
    for _, l in ipairs(n.lines) do l:SetText("") l.panoplyCount = nil end
  end
  -- Done only on a step the engine can't see done; never shown dimmed
  local undetect = cur and ST.Undetectable(cur) or false
  n.doneBtn.panoplyFlowSkip = not undetect
  local noPlan = total == 0
  for _, b in ipairs({ n.setupBtn, n.tourBtn }) do b.panoplyFlowSkip = not noPlan end
  n.pointBtn.panoplyFlowSkip = not cur or nil
  n.skipBtn.panoplyFlowSkip = not cur or nil
  -- progress: the level bar (rested shaded), the pace line and its tooltip
  local pct = (S.xpMax or 0) > 0 and (S.xp or 0) / S.xpMax or 0
  local goal = Panoply.Planner.lastStats and Panoply.Planner.lastStats.goalLevel
  if goal and goal <= (S.level or 1) then goal = nil end
  n.levelBar:SetProgress(pct, goal and ("Level %d (%d%%), heading for %d"):format(S.level or 1, math.floor(pct * 100), goal)
    or ("Level %d (%d%%)"):format(S.level or 1, math.floor(pct * 100)))
  local _, _, _, rested = C.XPKnown()
  n.restFrac = ((S.xpMax or 0) > 0 and (rested or 0) > 0) and math.min(1 - pct, rested / S.xpMax) or 0
  local paceLine = ST.PaceLine()
  n.pace:SetText(paceLine or "")
  local PM = Panoply.PaceMark
  local h = PM and PM.Horizon and PM:Horizon()
  n.levelHit.tip = ("Level %d: %d%%"):format(S.level or 1, math.floor(pct * 100))
  n.levelHit.tipBody = ((rested or 0) > 0 and ("Rested: %d XP more at double speed (the shaded part)."):format(rested) or "Not rested.")
    .. (h and h.minutes and ("\nAt your pace you'll be here in %d min (the gold mark)."):format(h.minutes) or "")
  -- the route bar or pips: the step's place in its chapter
  local num, numTotal = ST.Number(cur)
  if cur and not cur.isDungeon and num and numTotal then
    n.routeTotal, n.routeAt = numTotal, num
    n.routeBar:SetProgress((num - 1) / numTotal, ST.NumberText(cur))
    n.routeLabel:SetText(ST.NumberText(cur))
  else n.routeTotal, n.routeAt = 0, nil end
  -- the route
  local head, sub = planHeadline()
  r.head:SetText(head); r.sub:SetText(sub)
  r.paused:SetText(v.mode == "dungeon" and "Paused until you leave." or (v.mode == "noguide" and "No route planned here." or ""))
  local limit = math.max(1, math.min(20, tonumber(Panoply.db.guideRouteSteps) or 10))
  local list = Guide.RouteList(limit)
  local band = Panoply.Kit.Band(p.width or 600)
  v.moreRows = band == "narrow" and #list > NARROW_ROWS
  if band == "narrow" and not p.showAll then for i = #list, NARROW_ROWS + 1, -1 do list[i] = nil end end
  -- steps done fold into one line at the top
  local doneN = (num and num > 1 and not (cur and cur.isDungeon)) and (num - 1) or 0
  r.doneLine:SetText(doneN > 0 and ("%d done"):format(doneN) or "")
  for i, row in ipairs(r.rows) do
    local e = list[i]
    row.panoplyUsed, row.step, row.panoplyKey, row.panoplyIndex, row.panoplyCurrent, row.panoplyUndetect, row.panoplyMore = nil, nil, nil, nil, nil, nil, 0
    if e then
      local st = e.step
      local l1, l2, quests, more = Guide.RowLines(st)
      row.panoplyUsed, row.step, row.panoplyIndex, row.panoplyCurrent = true, st, e.index, e.current
      row.panoplyKey = st.key or tostring(e.index)
      row.panoplyUndetect = ST.Undetectable(st) and true or nil
      row.panoplyRowText = l1
      row.text:SetText(l1)
      row.line2:SetText(l2)
      Skin.SetIcon(row.icon, Panoply.UI.StepIconName(st))
      local c = e.current and Skin.colors.heading or Skin.colors.ink
      row.text:SetTextColor(c[1], c[2], c[3], 1)
      row.panoplyMore = more
      row.more.label:SetText(p.expanded[row.panoplyKey] and "Show less" or ("+%d more"):format(more))
      for j, ex in ipairs(row.extra) do ex.panoplyUsed = nil end
      if more > 0 and p.expanded[row.panoplyKey] then
        for j = 2, #quests do
          local ex = row.extra[j - 1]
          if not ex then ex = Skin.Ink(r.host, 11) row.extra[j - 1] = ex end
          local q = quests[j]
          ex:SetText(q.level and Panoply.Difficulty.Tag(q.level, q.name) or q.name)
          ex.panoplyUsed = true
        end
      end
      -- a trainer step's tooltip: the mount fund (it was on the Trainer line)
      if st.isTrainer and st.tip then Skin.Tooltip(row.tipHit, st.title or "Trainer", st.tip) else row.tipHit.tip, row.tipHit.tipBody = nil, nil end
    else
      row.text:SetText("")
      row.panoplyRowText = nil
      row.tipHit.tip, row.tipHit.tipBody = nil, nil
    end
  end
  if #list == 0 and v.mode == nil then
    local row = r.rows[1]
    row.panoplyUsed = true
    row.panoplyRowText = total == 0 and "Nothing planned yet." or "End of route."
    row.text:SetText(row.panoplyRowText); row.line2:SetText("")
    Skin.SetIcon(row.icon, "Leveling")
  end
  local hints = ST.AbandonHints()
  r.hint:SetText(hints[1] and (hints[1] .. (#hints > 1 and ("  (+%d more)"):format(#hints - 1) or "")) or "")
  -- the headers' summaries (closed)
  local nOn, nT = 0, 0
  for _, d in ipairs(Guide.TOGGLES) do
    if not (d.shown and not d.shown()) then nT = nT + 1 if d.get() then nOn = nOn + 1 end end
  end
  p.screenCard.sec:SetSummary(("%d of %d on"):format(nOn, nT))
  r.sec:SetSummary((cur and num) and ST.NumberText(cur) or "no route yet")
  refreshBlocks()
end, { scroll = true })

-- Blocks this page draws in its own way now (0.9.5 phase 4K): the Trainer line (route steps) and the session strip (one line).
function Guide.Replaced(b)
  local ST, Misc = Panoply.SpecTrainer, Panoply.Misc
  return (ST and b == ST.menuBlock) or (Misc and b == Misc.sessionBlock) or false
end

-- Point the arrow: shows it and points it at the step (a hand-picked spot, cleared when the step moves on, as the Professions
-- buttons do)
function Guide.PointArrow()
  local E = Panoply.Engine
  if Panoply.db.arrowShown == false then Panoply:SetOption("arrowShown", true) end
  local A = Panoply.Arrow
  if not A then return end
  local m, x, y, label = E:Target()
  if m then A:PointAt(m, x, y, label) else A:PointAt(nil) end
end

-------------------------------------------------------------------------------
-- Partner tab
-------------------------------------------------------------------------------
local MAX_PICKS = 8

function Menu.PartnerCandidates()
  local seen, out = {}, {}
  for _, n in ipairs(C.GroupMembers()) do local s = n:match("^[^-]+") or n if not seen[s] then seen[s] = true; out[#out + 1] = { name = s, from = "group" } end end
  for _, n in ipairs(C.FriendNames()) do local s = n:match("^[^-]+") or n if not seen[s] then seen[s] = true; out[#out + 1] = { name = s, from = "friend" } end end
  return out
end

function Panoply:SetPartner(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  Panoply.db.syncPartner = name
  Panoply:Fire("SYNC_STATUS")
  if Panoply.Sync then pcall(Panoply.Sync.SendHello, Panoply.Sync) end
end

-- the player's professions, the one being worked on first, then primary before secondary, then by rank
local function tracked1(list)
  local PD = Panoply.ProfData
  table.sort(list, function(a, b)
    if a.tracked ~= b.tracked then return a.tracked end
    local sa, sb = PD.SECONDARY[a.name] and 1 or 0, PD.SECONDARY[b.name] and 1 or 0
    if sa ~= sb then return sa < sb end
    return a.rank > b.rank
  end)
end

-- "You" on the Partner tab: name, level, zone, the step and the professions
local function partnerMe()
  local E, ST, PR, PD = Panoply.Engine, Panoply.StepText, Panoply.Professions, Panoply.ProfData
  local me = { name = (Panoply.Compat.PlayerInfo() or {}).name or "You", level = Panoply.State.level or 1, zone = Panoply.State.zone }
  local cur = E:LevelStep()
  me.step = cur and ST.Headline(cur) or "No route yet"
  local G = Panoply.ProfGuide
  me.profStep = G and G.current and ST.Headline(G.current) or nil
  me.profs = {}
  for _, n in ipairs(PD.ORDER) do
    local r, mx = PR:CurrentSkill(n)
    if r and (mx or 0) > 0 then me.profs[#me.profs + 1] = { name = n, rank = r, max = mx, tracked = G and G.tracked == n } end
  end
  tracked1(me.profs)
  return me
end

-- 0.9.7 (WoW Forever): the Partner tab on the guide engine's party sync. Everything comes from Engine/PolestarParty.lua's agreed
-- calls: Enabled (the Level together switch), PartnerLine (one line about the partner) and Card (the sync question, the class-quest
-- hold or the help-your-partner step, with its buttons). Nothing here reads the old shared-route number.
-- A card is read as { kind = "sync" | "wait" | "hold" | "help" | "ahead", title, body (or text), lines = { ... }, buttons =
-- { { label, tip, fn } or { label, tip, action = "Accept" | "Decline" | "GoOn" | "Help" | "StopHelp" | "RequestSync" } } } (the
-- shape Engine/PolestarParty.lua and Engine/PartnerHold.lua give, the same one the guide window draws); a card with no buttons of
-- its own gets the usual ones for its kind.
Menu.PARTY_BUTTONS = 3
Menu.PARTY_TEXT = {
  off = "Level together is off.",
  offSub = "Nothing is sent to your party and nothing about your party is shown. Turn it on in the Level together settings.",
  waiting = "Level together is on.",
  waitingSub = "Group up with your partner. It works when you both run Panoply Suite on WoW Forever, in a party (not a raid).",
  onSub = "Sync to my step asks your partner to come to your step. Nothing changes for them until they say yes.",
  partner = "Your partner",
  partnerNone = "Shows here once you are in a party and both run Panoply Suite.",
  partnerOff = "Level together is off.",
}
local function partyCardButtons(PP, card)
  local out = {}
  local function act(name) return function() if PP[name] then return PP[name](PP) end end end
  for _, b in ipairs(type(card.buttons) == "table" and card.buttons or {}) do
    if #out >= Menu.PARTY_BUTTONS then break end
    local text = b.text or b.label
    local own = b.fn or b.func or b.onClick
    local fn = own and function() return own(card) end or (b.action and PP[b.action] and act(b.action)) or nil
    if text and text ~= "" and fn then out[#out + 1] = { text = text, tip = b.tip, func = fn } end
  end
  if #out == 0 then
    if card.kind == "sync" then
      out[1] = { text = "Accept", tip = "Go to your partner's guide and step.", func = act("Accept") }
      out[2] = { text = "Decline", tip = "Stay on your own step.", func = act("Decline") }
    elseif card.kind == "hold" or card.kind == "help" or card.kind == "ahead" or card.kind == "wait" then
      out[1] = { text = "Go on without them", tip = "Carry on with your own guide. Your partner keeps their step.", func = act("GoOn") }
    end
  end
  return out
end
function Menu.PartyView(PP)
  local TX = Menu.PARTY_TEXT
  local on = PP:Enabled() and true or false
  local line, canAsk
  if on then line, canAsk = PP:PartnerLine() end
  if type(line) ~= "string" or line == "" then line = nil end
  local card = on and PP:Card() or nil
  if type(card) ~= "table" then card = nil end
  local v = { party = true, on = on, line = line }
  v.state = (not on) and "off" or (line or card) and "connected" or "waiting"
  v.connected = v.state == "connected"
  v.status = (not on) and TX.off or TX.waiting
  v.leader = (not on) and TX.offSub or v.connected and TX.onSub or TX.waitingSub
  v.me = partnerMe()
  v.partner = { name = (card and card.partner) or TX.partner, party = true, missing = true, profs = {},
    step = line or ((not on) and TX.partnerOff or TX.partnerNone) }
  if card then
    local parts = {}
    for _, s in ipairs({ card.text or card.body }) do if type(s) == "string" and s ~= "" then parts[#parts + 1] = s end end
    for _, s in ipairs(type(card.lines) == "table" and card.lines or {}) do if type(s) == "string" and s ~= "" then parts[#parts + 1] = s end end
    local text = table.concat(parts, "\n")
    v.card = { kind = card.kind, title = card.title or "", text = text or "", buttons = partyCardButtons(PP, card) }
  end
  v.canSync = on and line ~= nil and canAsk ~= false
  v.current = ""
  return v
end

-- Everything the Partner tab shows, as plain data (also dumped for the mockups).
function Menu.PartnerView()
  local PP = party()
  if PP then return Menu.PartyView(PP) end
  local Sy, E = Panoply.Sync, Panoply.Engine
  local v = { status = Sy:FriendlyStatus() }
  local name, st = Sy:ActivePartner()
  v.connected = name ~= nil
  local why = Sy:PausedReason()
  v.state = not Sy:Enabled() and "off" or why and "paused" or name and "connected" or "waiting"
  local leader, isMe, how = Sy:Leader()
  local _, pst = Sy:ActivePartner()
  local serves = Sy:Serves(pst)
  local awaited = (not leader) and Sy:AwaitedPartner() or nil   -- 0.7.3.2: the partner saved from last time, in the group, not heard yet
  if awaited then v.leader = "Route leader: decided as soon as " .. awaited .. "'s Panoply Suite answers."
  elseif not leader then v.leader = "Route leader: you (no partner connected yet)."
  elseif not serves and Sy:Shares() then v.leader = "No shared route right now: each of you plans your own."
  elseif how == "crown" then
    v.leader = isMe and "You are the party leader: your route is shared with your partner." or (leader .. " is the party leader: you follow their route.")
  else
    v.leader = isMe and "You lead: your route is shared with your partner." or (leader .. " leads: you follow the same route.")
  end
  -- You
  v.me = partnerMe()
  -- Partner
  if name then
    local pt = { name = name, level = st.level, zone = st.map and Panoply.Compat.MapName(st.map) or nil }
    local text, idx = Sy:PartnerStepText()
    pt.step = text and (text .. (idx and (" (step " .. idx .. ")") or "")) or "Unknown"
    pt.profStep = st.profStep
    pt.profs = {}
    for _, x in ipairs(st.profs or {}) do pt.profs[#pt.profs + 1] = { name = x.name, rank = x.rank, max = x.max, tracked = st.profTracked == x.name } end
    tracked1(pt.profs)
    pt.same = st.hash and st.hash == Panoply.Planner.hash or false
    pt.waiting = E.waiting and true or false
    v.partner = pt
  else
    v.partner = { name = awaited or (Panoply.db.syncPartner ~= "" and Panoply.db.syncPartner) or "Your partner", missing = true,
      step = awaited and "Waiting for their Panoply Suite to answer." or "Shows here once you are grouped and both run Panoply Suite.", profs = {} }
  end
  local c = Panoply.db.syncPartner or ""
  v.current = c ~= "" and ("Syncing with " .. c) or "Syncing with anyone in your group"
  return v
end

-- 0.9.5 phase 4J (spec 02 section 1, theme pass): a Kit.Surface card (one step lighter, no border), the name in text.primary, the
-- small labels and body in text.muted, and the profession bars are Kit.ProgressBar in the profession's own accent (gathering moss,
-- secondary steel, crafting bronze), each with its words in a muted line above it.
-- (the Professions page's own rule, UI/ProfPage.lua accentOf, so a profession has one colour everywhere)
local function profAccent(name)
  local PUI = Panoply.ProfUI
  if PUI and PUI.IsSecondary and PUI.IsSecondary(name) then return "secondary" end
  if PUI and PUI.Kind and PUI.Kind(name) ~= "crafting" then return "gathering" end
  return "crafting"
end
Menu.PartnerProfAccent = profAccent

local function playerCard(p, x, y, w)
  local K = Panoply.Kit
  local card = K.Surface(p, 1)
  card:SetPoint("TOPLEFT", p, "TOPLEFT", x, y); card:SetSize(w, 176)
  card.name = Skin.Name(card, 14, K.Color("text.primary")); card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
  card.sub = Skin.Ink(card, 10, K.Color("text.muted")); card.sub:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -26); card.sub:SetWidth(w - 20)
  local l1 = Skin.Label(card, 10, K.Color("text.muted")); l1:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -44); l1:SetText("ROUTE STEP")
  card.step = Skin.Ink(card, 12, K.Color("text.primary")); card.step:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -56); card.step:SetWidth(w - 20)
  local l2 = Skin.Label(card, 10, K.Color("text.muted")); l2:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -88); l2:SetText("PROFESSION STEP")
  card.prof = Skin.Ink(card, 12, K.Color("text.primary")); card.prof:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -100); card.prof:SetWidth(w - 20)
  card.l1, card.l2 = l1, l2
  card.bars = {}
  for i = 1, 3 do
    local b = K.ProgressBar(card, { h = 7 }); b:SetBarWidth(w - 20)
    b.text = Skin.Ink(card, 10, K.Color("text.muted"))
    if b.text.SetWordWrap then b.text:SetWordWrap(false) end
    local show, hide = b.Show, b.Hide
    b.Show = function(self) show(self) self.text:Show() end
    b.Hide = function(self) hide(self) self.text:Hide() end
    card.bars[i] = b
  end
  -- 0.5.5: measured; returns the card height
  function card:Layout()
    -- Step 20: the card takes the width the page gives it (panoplyW), so it follows a resized window
    local cw = self.panoplyW or w
    local SP, TH, iw = Skin.SP, Skin.TextHeight, cw - 20
    self:SetWidth(cw)
    for _, fs in ipairs({ self.sub, self.step, self.prof }) do fs:SetWidth(iw) end
    for _, b in ipairs(self.bars) do b:SetBarWidth(iw); b.text:SetWidth(iw) end   -- (the bar's words get the width too: they were cut at the first card's)
    local y = -8
    local function put(fs, gap)
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y); fs:SetWidth(iw)
      if (fs:GetText() or "") ~= "" then y = y - TH(fs, iw) - (gap or SP.xs) end
    end
    put(self.name, 2); put(self.sub, SP.m)
    put(self.l1, 2); put(self.step, SP.m)
    put(self.l2, 2); put(self.prof, SP.s)
    for _, b in ipairs(self.bars) do
      b:ClearAllPoints()
      b.text:ClearAllPoints()
      if b:IsShown() then
        b.text:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y); y = y - TH(b.text, iw) - 2
        b:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y); y = y - b.h - SP.s
      end
    end
    local h = -y + SP.s
    self:SetHeight(h)
    return h
  end
  function card:Fill(d)
    self.name:SetText(d.name or "")
    local sub = {}
    if d.level then sub[#sub + 1] = "Level " .. d.level end
    if d.zone and d.zone ~= "" then sub[#sub + 1] = d.zone end
    if d.same ~= nil then sub[#sub + 1] = d.same and "same route" or "different route" end
    self.sub:SetText(table.concat(sub, "  -  "))
    self.step:SetText(d.step or "")
    -- 0.9.7: the partner's card on the party sync has one line about them and no profession step of theirs to show
    self.l1:SetText(d.party and "RIGHT NOW" or "ROUTE STEP")
    self.l2:SetText(d.party and "" or "PROFESSION STEP")
    self.prof:SetText(d.profStep or (d.missing and "" or "No profession step right now"))
    for i, b in ipairs(self.bars) do
      local x = d.profs and d.profs[i]
      if x then
        b:Show(); b:SetAccent(profAccent(x.name)); b:SetProgress(x.rank / math.max(1, x.max))
        b.text:SetText(("%s %d / %d%s"):format(x.name, x.rank, x.max, x.tracked and "  (working on it)" or ""))
      else b:Hide() end
    end
  end
  return card
end

-- Step 20 (0.9.4): two Kit.Sections (a chevron in each header; open or closed remembered): You and your partner (the status, both
-- cards and the three buttons) and Who is your partner? (the name box, and a Kit.Dropdown that lists the people in your group and your
-- online friends where there used to be a row of buttons).
Menu:RegisterTab("Partner", function(p)
  local K = Panoply.Kit
  p.secLive = K.Section(p, "partner", "live", { title = "You and your partner" })
  p.secWho = K.Section(p, "partner", "who", { title = "Who is your partner?" })
  local lb, wb = p.secLive.body, p.secWho.body
  p.dot = lb:CreateTexture(nil, "OVERLAY"); p.dot:SetSize(12, 12); p.dot:SetTexture(Skin.TEX.CircleMask)
  p.status = Skin.Ink(lb, 12)
  p.leader = Skin.Ink(lb, 11, Skin.colors.inkSoft)
  p.meCard = playerCard(lb, 14, -78, 100)
  p.ptCard = playerCard(lb, 14, -78, 100)
  p.current = Skin.Ink(wb, 11, Skin.colors.inkSoft)
  local eb = CreateFrame("EditBox", nil, wb, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  eb:SetSize(200, 24); eb:SetAutoFocus(false)
  if eb.SetFontObject and _G.ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
  Skin.Font(eb, 12); if eb.SetTextInsets then eb:SetTextInsets(6, 6, 0, 0) end
  local ebg = eb:CreateTexture(nil, "BACKGROUND"); ebg:SetAllPoints(eb); Skin.Solid(ebg, Skin.colors.bgDeep, 0.92)
  Skin.Border(eb, true)
  eb:SetScript("OnEnterPressed", function() Panoply:SetPartner(eb:GetText()); eb:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function() Panoply:SetPartner(eb:GetText()) end)
  p.partnerBox = eb
  local set = Skin.Button(wb, "Use this name", 120, 24, function() Panoply:SetPartner(eb:GetText()) end, "Use this name",
    "Sync only with this player. Leave the box empty to sync with anyone in your group who runs Panoply Suite.")
  p.setBtn = set
  local anyone = Skin.Button(wb, "Anyone in my group", 150, 24, function() eb:SetText(""); Panoply:SetPartner("") end, "Anyone in my group",
    "Sync with whoever in your group runs Panoply Suite.")
  p.anyoneBtn = anyone
  p.pickLabel = Skin.Ink(wb, 11, Skin.colors.inkSoft)
  -- the people in your group and your online friends, one dropdown
  p.pick = K.Dropdown(wb, { page = "partner", width = 260, empty = "Pick someone...", tip = "Pick partner",
    tipBody = "Your group and your online friends. Sync with the one you pick.",
    items = function()
      local out = {}
      for i, c in ipairs(Menu.PartnerCandidates()) do
        if i > MAX_PICKS then break end
        out[#out + 1] = { text = c.name, value = c.name, tip = (c.from == "group" and "In your group. " or "Online friend. ") .. "Sync with this player." }
      end
      return out
    end,
    get = function() return Panoply.db and Panoply.db.syncPartner or "" end,
    set = function(v) eb:SetText(v or ""); Panoply:SetPartner(v) end })
  -- the three switches (Level together, Wait for my partner, Share one route) have one home: the gear
  p.settingsBtn = Skin.Button(lb, "Level together settings", 190, 26, function() Menu:OpenGear("guide", "together") end,
    "Level together settings", "Level together and Wait for my partner are in the Guide's gear.")
  local sync = Skin.Button(lb, "Sync now", 120, 26, function()
    -- 0.9.7: where the guide engine's party sync can run, "Sync now" is its "Sync to my step" (Engine/PolestarParty.lua)
    local PP = Panoply.PolestarParty
    if PP and PP.RequestSync and PP.CanRun and PP:CanRun() then
      if not PP:RequestSync() and not PP:Enabled() then Panoply:Print(PP:FriendlyStatus()) end
      Menu:RefreshCurrent()
      return
    end
    local did, leader = Panoply.Sync:SyncNow()
    if did == "asked" then Panoply:Print("Asked " .. leader .. " for the shared route and sent your progress.")
    else Panoply:Print("Sent your route and progress to your partner.") end
  end, "Sync now", "Send your progress to your partner straight away. The party leader sends the route; the other player asks for it.")
  p.syncBtn = sync
  local prof = Skin.Button(lb, "Professions together", 170, 26, function() Panoply.ProfUI.page = "Together"; Menu:Open("professions") end,
    "Professions together", "How your professions and your partner's help each other.")
  p.profBtn = prof
  -- 0.9.7 (WoW Forever, the party sync): "Sync to my step", and the card for a sync question, a class-quest hold or a
  -- help-your-partner step with its buttons. All of it is made here, with the page; showing a card creates nothing.
  p.syncStepBtn = Skin.Button(lb, "Sync to my step", 150, 26, function()
    local PP = Panoply.PolestarParty
    if PP and PP.RequestSync then PP:RequestSync() end
    Menu:RefreshCurrent()
  end, "Sync to my step", "Asks your partner to come to your guide and step. They see the question and choose; nothing moves by itself.")
  local pc = K.Surface(lb, 1); p.partyCard = pc; pc.panoplyGapOK = true
  pc.title = Skin.Name(pc, 14, K.Color("text.primary"))
  pc.text = Skin.Ink(pc, 12, K.Color("text.primary"))
  pc.buttons = {}
  for i = 1, Menu.PARTY_BUTTONS do
    local b
    b = Skin.Button(pc, "", 120, 26, function()
      local fn = b.panoplyAct
      if fn then fn() end
      Menu:RefreshCurrent()
    end)
    b:Hide()
    pc.buttons[i] = b
  end
  pc:Hide()
  function p:Layout()
    local SP, TH = Skin.SP, Skin.TextHeight
    local W = self.width - 4
    local pad = 12
    local inner = W - 2 * pad
    local y = 0
    local function at(o, parent, x, yy, w) o:ClearAllPoints(); o:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yy) if w then o:SetWidth(w) end end
    -- YOU AND YOUR PARTNER
    local _, open = self.secLive:Begin(self, 2, -y, W)
    local ly = 0
    if open then
      local b = self.secLive.body
      ly = -SP.xs
      at(self.dot, b, pad, ly - 2)
      at(self.status, b, pad + 18, ly, inner - 18); ly = ly - TH(self.status, inner - 18) - SP.xs
      at(self.leader, b, pad + 18, ly, inner - 18); ly = ly - TH(self.leader, inner - 18) - SP.m
      local cw = math.floor((inner - SP.l) / 2)
      self.meCard.panoplyW, self.ptCard.panoplyW = cw, cw
      at(self.meCard, b, pad, ly); at(self.ptCard, b, pad + cw + SP.l, ly)
      local ch = math.max(self.meCard:Layout(), self.ptCard:Layout())
      self.meCard:SetHeight(ch); self.ptCard:SetHeight(ch)
      ly = ly - ch - SP.m
      -- the party sync's card (0.9.7), as wide as the section
      local pc = self.partyCard
      if self.partyOn and pc.panoplyOn then
        local iw = inner - 20
        pc:Show(); at(pc, b, pad, ly, inner)
        local cy = -8
        for _, fs in ipairs({ pc.title, pc.text }) do
          fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", pc, "TOPLEFT", 10, cy); fs:SetWidth(iw)
          if (fs:GetText() or "") ~= "" then cy = cy - TH(fs, iw) - SP.s end
        end
        local used = {}
        for _, cb in ipairs(pc.buttons) do if cb.panoplyAct then cb:Show() used[#used + 1] = cb else cb:Hide() end end
        if #used > 0 then cy = cy - Skin.FlowButtons(pc, used, 10, cy, iw, SP.m, 80) - SP.s end
        pc:SetHeight(-cy + SP.xs)
        ly = ly - (-cy + SP.xs) - SP.m
      else pc:Hide() end
      local row
      if self.partyOn then
        self.syncBtn:Hide(); self.profBtn:Hide()
        row = { self.settingsBtn }
        if self.partySync then self.syncStepBtn:Show() table.insert(row, 1, self.syncStepBtn) else self.syncStepBtn:Hide() end
      else
        self.syncStepBtn:Hide(); self.syncBtn:Show(); self.profBtn:Show()
        row = { self.syncBtn, self.profBtn, self.settingsBtn }
      end
      local fh = Skin.FlowButtons(b, row, pad, ly, inner, SP.m, 100)
      ly = ly - fh
    end
    y = y + self.secLive:Done(-ly) + SP.m
    -- WHO IS YOUR PARTNER? (the older partner sync only: on the party sync your partner is whoever is in your party)
    if self.partyOn then
      self.secWho.card:Hide()
      return y
    end
    local _, wopen = self.secWho:Begin(self, 2, -y, W)
    local wy = 0
    if wopen then
      local b = self.secWho.body
      wy = -SP.xs
      at(self.current, b, pad, wy, inner); wy = wy - TH(self.current, inner) - SP.s
      at(self.partnerBox, b, pad, wy)
      local bh = Skin.FlowButtons(b, { self.setBtn, self.anyoneBtn }, pad + 200 + SP.m, wy, inner - 200 - SP.m, SP.m, 90)
      wy = wy - math.max(24, bh) - SP.m
      if self.hasPicks then
        self.pickLabel:Hide()
        self.pick:ClearAllPoints(); self.pick:SetPoint("TOPLEFT", b, "TOPLEFT", pad, wy)
        self.pick:SetWidth(math.min(260, inner)); self.pick:Refresh(); self.pick:Show()
        wy = wy - self.pick:GetHeight()
      else
        self.pick:Hide()
        at(self.pickLabel, b, pad, wy, inner); self.pickLabel:Show()
        wy = wy - TH(self.pickLabel, inner)
      end
    end
    y = y + self.secWho:Done(-wy)
    return y + SP.m
  end
end, function(p)
  local v = Menu.PartnerView()
  Menu.lastPartner = v
  -- 0.9.7: on the party sync the page has its own button and card, and no "Who is your partner?"
  p.partyOn = v.party and true or false
  p.partySync = v.canSync and true or false
  local pc = p.partyCard
  pc.panoplyOn = v.card ~= nil
  pc.title:SetText(v.card and v.card.title or "")
  pc.text:SetText(v.card and v.card.text or "")
  for i, b in ipairs(pc.buttons) do
    local d = v.card and v.card.buttons[i]
    b.panoplyAct = d and d.func or nil
    b.label:SetText(d and d.text or "")
    Skin.Tooltip(b, d and d.text or nil, d and d.tip or nil)
  end
  p.status:SetText(v.status)
  local col = v.state == "connected" and Skin.colors.done or v.state == "off" and Skin.colors.dim or Skin.colors.highlight
  p.dot:SetVertexColor(col[1], col[2], col[3], 1)
  p.leader:SetText(v.leader)
  p.meCard:Fill(v.me)
  p.ptCard:Fill(v.partner)
  p.current:SetText(v.current)
  p.partnerBox:SetText(Panoply.db.syncPartner or "")
  p.secLive:SetSummary(v.party and (v.state == "off" and "off" or v.state == "connected" and "with your partner" or "on")
    or v.state == "connected" and ("with " .. (v.partner.name or "your partner")) or v.state)
  p.secWho:SetSummary(Panoply.db.syncPartner ~= "" and Panoply.db.syncPartner or "anyone in your group")
  local cands = Menu.PartnerCandidates()
  p.hasPicks = #cands > 0
  p.pickLabel:SetText(p.hasPicks and "" or "Group up or log in friends to pick them here.")
  p.pick:Refresh()
end, { scroll = true })
