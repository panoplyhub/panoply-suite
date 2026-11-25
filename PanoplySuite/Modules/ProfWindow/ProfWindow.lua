-- Profession window module (SPEC 19.6): a companion panel beside the game's profession window
-- with search, favourites (starred recipes first), filters (have materials, orange / yellow /
-- green, hide grey), "can make" counts from your bags AND bank (Bags module data), optional
-- auction material cost, Make / Make all, and "Guide me" into the Professions guide.
-- 0.5.9: only our window shows. The game's profession window (TradeSkillFrame, CraftFrame for
-- enchanting, ProfessionsFrame) stays open and working underneath - its session, its selection,
-- Esc - but it is invisible and cannot be clicked. Setting "Use Blizzard profession window too"
-- or the "Blizzard" button brings it back. Never changed while a protected frame is in combat.
-- 0.7.0 (tester report): a favourite reserves its materials for "reserve for N crafts" (per character).
-- Other recipes' Can make counts leave those materials alone; display only, nothing is blocked.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local PW = Panoply.Modules:Register({
  key = "profwindow", label = "Profession window", icon = "ProfWindow",
  desc = "One profession window with search, favourites, filters and Can make counts (the game's own stays hidden).",
  defaults = { profBlizzardToo = false, profFavs = {}, profFilters = { showAll = false, haveMats = false, optimal = true, medium = true, easy = true, trivial = false },
               profAuctionCost = true, profWindowLocked = false },
})
Panoply.ProfWindow = PW
PW.ROWS = 12
PW.ROW_H = 24
PW.DIFF_COLOR = { optimal = { 1, 0.55, 0.25 }, medium = { 1, 0.9, 0.2 }, easy = { 0.35, 0.85, 0.35 }, trivial = { 0.55, 0.55, 0.55 } }
PW.DIFF_ORDER = { optimal = 1, medium = 2, easy = 3, trivial = 4 }
PW.offset = 0

function PW:ProfName()
  local r = C.ReadOpenTradeSkill and C.ReadOpenTradeSkill()
  if r and r.name and r.name ~= "" then return r.name end
  if _G.GetCraftDisplaySkillLine then local n = C.pc(GetCraftDisplaySkillLine) if n then return n end end
  return Panoply.ProfGuide and Panoply.ProfGuide:Tracked() or "Profession"
end

local function favs(prof)
  Panoply.db.profFavs[prof] = Panoply.db.profFavs[prof] or {}
  return Panoply.db.profFavs[prof]
end
function PW:IsFav(prof, name) return favs(prof)[name] and true or false end
function PW:ToggleFav(prof, name)
  local f = favs(prof)
  f[name] = not f[name] or nil
  if not f[name] then PW:SetReserve(prof, name, nil) end   -- unfavourite: its reservation is released
  self:Refresh()
  return f[name] and true or false
end

-------------------------------------------------------------------------------
-- 0.7.0 (tester report): reserved materials for favourites. Saved per character in Panoply.cdb.profReserve
-- [profession][recipe] = crafts (no entry = 1). Favourites claim materials in the order the list
-- shows them (difficulty, then name); a favourite's own count uses the full stock.
-------------------------------------------------------------------------------
PW.RESERVE_MAX = 99
local function reserveStore(prof)
  Panoply.cdb.profReserve = Panoply.cdb.profReserve or {}
  Panoply.cdb.profReserve[prof] = Panoply.cdb.profReserve[prof] or {}
  return Panoply.cdb.profReserve[prof]
end
function PW:ReserveCount(prof, name)
  if not (prof and name and self:IsFav(prof, name)) then return 0 end
  local n = reserveStore(prof)[name]
  return n == nil and 1 or n
end
function PW:SetReserve(prof, name, n)
  if not (prof and name) then return 0 end
  if n ~= nil then n = math.max(0, math.min(PW.RESERVE_MAX, math.floor(tonumber(n) or 1))) end
  if n == 1 then n = nil end   -- 1 is the default: nothing stored
  reserveStore(prof)[name] = n
  if Panoply.cdb.profReserve[prof] and next(Panoply.cdb.profReserve[prof]) == nil then Panoply.cdb.profReserve[prof] = nil end
  return n == nil and 1 or n
end
-- -/+ in the detail card: changes the selected favourite's reservation and redraws
function PW:StepReserve(d)
  local row = self:SelectedRow()
  if not (row and row.fav) then return end
  self:SetReserve(self.prof, row.name, self:ReserveCount(self.prof, row.name) + (d or 0))
  self:Refresh()
end
local function matKey(rg) return rg.itemID or rg.name or "?" end
PW.favOrder = function(a, b)
  local da, db = PW.DIFF_ORDER[a.difficulty] or 3, PW.DIFF_ORDER[b.difficulty] or 3
  if da ~= db then return da < db end
  return (a.name or "") < (b.name or "")
end
-- rows: every recipe of the profession with r.canMake / rg.total already read (full stock).
-- Sets on each row: fav rows .reserveN / .reserveShort; other rows .canMake (what is left),
-- .canMakeFull, and rg.reserved on each material. Returns the shortfall list.
function PW:ApplyReserve(rows, prof)
  local fl = {}
  for _, r in ipairs(rows or {}) do
    r.reserveN, r.reserveShort, r.canMakeFull = nil, nil, r.canMake
    for _, rg in ipairs(r.reagents or {}) do rg.reserved = nil end
    if r.fav then fl[#fl + 1] = r end
  end
  table.sort(fl, PW.favOrder)
  local held, short = {}, {}
  for _, r in ipairs(fl) do
    local n = self:ReserveCount(prof, r.name)
    r.reserveN = n
    if n > 0 then
      for _, rg in ipairs(r.reagents or {}) do
        local k = matKey(rg)
        local want = n * math.max(1, rg.need or 1)
        local got = math.min(want, math.max(0, (rg.total or 0) - (held[k] or 0)))
        held[k] = (held[k] or 0) + got
        if got < want then
          r.reserveShort = true
          short[#short + 1] = { recipe = r.name, material = rg.name or ("item " .. tostring(rg.itemID)), missing = want - got }
        end
      end
    end
  end
  for _, r in ipairs(rows or {}) do
    if not r.fav and r.reagents and #r.reagents > 0 then
      local best, any
      for _, rg in ipairs(r.reagents) do
        local h = held[matKey(rg)] or 0
        if h > 0 then rg.reserved, any = h, true end
        local n = math.floor(math.max(0, (rg.total or 0) - h) / math.max(1, rg.need or 1))
        best = best and math.min(best, n) or n
      end
      if any then r.canMake = best or 0 end
    end
  end
  self.reserveShort = short
  return short
end
-- One plain warning line for the shortfall (nil when every reservation is covered).
function PW:ReserveWarning()
  local s = self.reserveShort
  if not (s and #s > 0) then return nil end
  local parts, seen = {}, {}
  for _, e in ipairs(s) do
    local k = e.material .. "|" .. e.recipe
    if not seen[k] then seen[k] = true parts[#parts + 1] = ("%d %s for %s"):format(e.missing, e.material, e.recipe) end
  end
  return "Not enough materials for all your reserved crafts. Short: " .. table.concat(parts, ", ") .. "."
end

-- How many you can make from bags + bank (Inventory store), or from the game's own count.
function PW:CanMake(row)
  local inv = Panoply.Inventory
  local best
  for _, rg in ipairs(row.reagents or {}) do
    if not rg.name and rg.itemID then local ii = C.ItemInfo(rg.itemID) rg.name = ii and ii.name end
    local have
    if rg.itemID and inv and inv:Enabled() then have = inv:Have(rg.itemID) else have = rg.have or 0 end
    rg.total = have
    local n = math.floor((have or 0) / math.max(1, rg.need or 1))
    best = best and math.min(best, n) or n
  end
  return best or (row.numAvailable or 0)
end

function PW:Rows()
  local rows, kind = C.TradeSkillDetails(self.session == "craft", self:WantBlizzard())   -- 0.7.1: the whole book (see C.WholeTradeList)
  self.kind = kind
  local prof = self:ProfName()
  self.prof = prof
  local q = self.search and self.search:lower() or ""
  local F = Panoply.db.profFilters
  local out = {}
  -- 0.6.0: categories in the game's order (its header rows; derived from the name for enchanting)
  local cats, seen, anyCat = {}, {}, false
  for _, r in ipairs(rows or {}) do
    if not r.category and r.craft then r.category = PW.CraftCategory(r.name) end
    if r.category then anyCat = true end
  end
  for _, r in ipairs(rows or {}) do
    if anyCat and not r.category then r.category = "Other" end
    local c = r.category
    if c and not seen[c] then seen[c] = true cats[#cats + 1] = c end
  end
  self.categories = cats
  local tab = self:Tab()
  if tab ~= "All" and not seen[tab] then tab = "All" self:SetTab("All", true) end
  for _, r in ipairs(rows or {}) do
    r.canMake = self:CanMake(r)
    r.fav = self:IsFav(prof, r.name or "")
    local d = r.difficulty or "easy"
    local ok = true
    if q ~= "" and not (r.name or ""):lower():find(q, 1, true) then
      ok = false
      for _, rg in ipairs(r.reagents or {}) do if rg.name and rg.name:lower():find(q, 1, true) then ok = true end end
    end
    if ok and tab ~= "All" and r.category ~= tab then ok = false end
    -- "Show all": every recipe, whatever the materials and the colour filters (tab and search still apply)
    if ok and not F.showAll and F.haveMats and r.canMake < 1 then ok = false end
    if ok and not F.showAll and F[d] == false then ok = false end
    if ok then out[#out + 1] = r end
  end
  -- 0.7.0: favourites hold back their materials (counted over every recipe, shown or filtered
  -- out); "Have mats" then also hides a recipe whose materials are all reserved
  self:ApplyReserve(rows or {}, prof)
  if not F.showAll and F.haveMats then
    local keep = {}
    for _, r in ipairs(out) do if r.canMake >= 1 then keep[#keep + 1] = r end end
    out = keep
  end
  table.sort(out, function(a, b)
    if a.fav ~= b.fav then return a.fav end
    local da, db = PW.DIFF_ORDER[a.difficulty] or 3, PW.DIFF_ORDER[b.difficulty] or 3
    if da ~= db then return da < db end
    return (a.name or "") < (b.name or "")
  end)
  self.rows = out
  return out
end

-- 0.6.0: enchanting (the craft window) has no category rows in Classic: "Enchant Bracer - Minor
-- Health" goes under Bracer, rods / oils / wands under their own, the rest under Other.
function PW.CraftCategory(name)
  name = name or ""
  local slot = name:match("^Enchant ([^%-]-)%s*%-")
  if slot and slot ~= "" then return slot end
  if name:find("Rod$") then return "Rods" end
  if name:find("Oil$") then return "Oils" end
  if name:find("Wand$") then return "Wands" end
  return nil
end

-- The category tab per profession ("All" = every category). Kept for this session only.
PW.tabByProf = {}
function PW:Tab() return self.tabByProf[self.prof or "?"] or "All" end
function PW:SetTab(name, quiet)
  self.tabByProf[self.prof or "?"] = name or "All"
  self.tabReveal = true
  if not quiet then self.offset = 0 self:Refresh() end
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------
local function filterButton(parent, key, label, tip)
  local b = Skin.Button(parent, label, 62, 20, function(self)
    local F = Panoply.db.profFilters
    if key ~= "showAll" and F.showAll then
      F.showAll = false            -- a filter pill while "Show all" is on: the filters apply again
    else
      F[key] = not F[key]
    end
    PW.offset = 0
    PW:Refresh()
  end, label, tip)
  b.filterKey = key
  return b
end

-------------------------------------------------------------------------------
-- 0.6.0: the window moves by its title bar, remembers its place per character, and by
-- default opens beside (not on top of) the character screen and other left-side game panels.
-- Only our own frame is moved; the game's panels and UIPanelWindows are never touched.
-------------------------------------------------------------------------------
PW.LEFT_PANELS = { "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame", "QuestLogFrame",
  "FriendsFrame", "GuildFrame", "CommunitiesFrame", "MailFrame", "MerchantFrame", "GossipFrame", "QuestFrame",
  "BankFrame", "ClassTrainerFrame", "AuctionFrame", "TaxiFrame", "InspectFrame", "DressUpFrame", "TradeFrame",
  "PetStableFrame", "MacroFrame", "HonorFrame", "PVPFrame", "LFGParentFrame", "ItemTextFrame", "TabardFrame",
  "LootFrame", "PetitionFrame", "GuildRegistrarFrame", "TradeSkillFrame", "CraftFrame", "ProfessionsFrame" }
PW.DEFAULT_TOP, PW.DEFAULT_LEFT, PW.PANEL_GAP = -104, 16, 8

local function uiScale() return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1 end
-- A frame's left/right edge in UIParent units (its own scale may differ).
local function edges(fr)
  local l, r = fr:GetLeft(), fr:GetRight()
  if not (l and r) then return nil end
  local k = (fr.GetEffectiveScale and fr:GetEffectiveScale() or 1) / uiScale()
  return l * k, r * k
end
-- Shown game panels on the left half of the screen (a tucked, invisible profession frame does not count).
function PW:OpenLeftPanels()
  local out, seen = {}, {}
  local sw = (UIParent and UIParent:GetWidth()) or 1024
  local function consider(fr)
    if not fr or seen[fr] or fr == self.frame or fr.panoplyTucked then return end
    seen[fr] = true
    if not (fr.IsShown and fr:IsShown()) then return end
    if fr.GetAlpha and (fr:GetAlpha() or 1) < 0.05 then return end
    local l, r = edges(fr)
    if l and r and r > l and l < sw / 2 then out[#out + 1] = { frame = fr, left = l, right = r } end
  end
  if _G.GetUIPanel then
    for _, slot in ipairs({ "left", "center", "doublewide", "right" }) do local ok, fr = pcall(_G.GetUIPanel, slot) if ok then consider(fr) end end
  end
  for _, n in ipairs(self.LEFT_PANELS) do consider(_G[n]) end
  return out
end
-- The open left-side panel that reaches furthest right (the game's profession window when it is the only one).
function PW:RightmostPanel()
  local best, br
  for _, p in ipairs(self:OpenLeftPanels()) do if not br or p.right > br then best, br = p.frame, p.right end end
  if not best then local tf = self:GameFrame() if tf and not tf.panoplyTucked and tf:IsShown() then return tf end end
  return best
end
-- Default spot: right of the open left-side panels (or the usual left spot when none are open).
function PW:DefaultSpot()
  local x = self.DEFAULT_LEFT
  for _, p in ipairs(self:OpenLeftPanels()) do x = math.max(x, math.ceil(p.right) + self.PANEL_GAP) end
  local w = self.frame and self.frame:GetWidth() or 380
  local sw = (UIParent and UIParent:GetWidth()) or 1024
  if x + w > sw - 4 then x = math.max(0, sw - 4 - w) end
  return x, self.DEFAULT_TOP
end
function PW:SavedSpot()
  local p = Panoply.cdb and Panoply.cdb.profWindowPos
  if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then return p[1], p[2] end
  return nil
end
function PW:SavePosition()
  local f = self.frame
  local l, t = f:GetLeft(), f:GetTop()
  if l and t and Panoply.cdb then Panoply.cdb.profWindowPos = { math.floor(l + 0.5), math.floor(t + 0.5) } end
end
function PW:ResetPosition()
  if Panoply.cdb then Panoply.cdb.profWindowPos = nil end
  if self.frame and self.frame:IsShown() then self:Anchor() end
  return true
end
function PW:Locked() return Panoply.db.profWindowLocked and true or false end
function PW:DragStart()
  local f = self.frame
  if not f or self:Locked() then return false end
  f:StartMoving()
  self.moving = true
  return true
end
function PW:DragStop()
  local f = self.frame
  if not (f and self.moving) then return false end
  self.moving = nil
  f:StopMovingOrSizing()
  self:SavePosition()
  self:Anchor()
  return true
end
-- The game re-arranges its panels after they show or hide: follow it on the next frame (only while
-- the window is in its default spot). hooksecurefunc / HookScript only, so nothing is tainted.
function PW:HookPanels()
  if self.panelsHooked then return end
  self.panelsHooked = true
  local function later() C.After(0, function() PW:FollowPanels() end) end
  if _G.UpdateUIPanelPositions and _G.hooksecurefunc then hooksecurefunc("UpdateUIPanelPositions", later) end
  for _, n in ipairs(self.LEFT_PANELS) do
    local fr = _G[n]
    if fr and fr.HookScript and not fr.panoplyPWPanelHook then
      fr.panoplyPWPanelHook = true
      fr:HookScript("OnShow", later); fr:HookScript("OnHide", later)
    end
  end
end
function PW:FollowPanels()
  if self.moving or self:SavedSpot() or not (self.frame and self.frame:IsShown()) then return end
  self:Anchor()
end

PW.LIST_X, PW.LIST_TOP, PW.LIST_GAP, PW.CARD_BOTTOM = 14, -128, 8, 54
PW.MIN_H = 380               -- the shortest the window is dragged to
PW.SKILL_BAR_Y, PW.SKILL_BAR_H = -54, 4   -- 0.6.0: the thin skill bar under the header rule (moves down with it)
PW.ROW_PITCH = PW.ROW_H + 2
local function makeRow(f, i)
  local area = f.listArea
  local r = CreateFrame("Button", nil, area)
  r:SetHeight(PW.ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); Skin.Solid(r.bg, Skin.colors.bgHigh, 0.35)
  r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(r); Skin.Solid(r.sel, Skin.colors.accent, 0.18); r.sel:Hide()
  r.star = CreateFrame("Button", nil, r); r.star:SetSize(18, 18); r.star:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.star.tex = r.star:CreateTexture(nil, "ARTWORK"); r.star.tex:SetAllPoints(r.star)
  r.star:SetScript("OnClick", function() if r.row then PW:ToggleFav(PW.prof, r.row.name) end end)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
  r.name = Skin.Text(r, 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -64, 0)
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.count = Skin.Text(r, 11, Skin.colors.inkSoft); r.count:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  if r.count.SetJustifyH then r.count:SetJustifyH("RIGHT") end
  -- 0.7.0: a small "reserved" note left of a reserving favourite's count
  r.resv = Skin.Text(r, 9, Skin.colors.accent); r.resv:SetPoint("RIGHT", r.count, "LEFT", -4, 0); r.resv:Hide()
  r:SetScript("OnClick", function() if r.row then PW:Select(r.row) end end)
  r:SetScript("OnEnter", function()
    r.bg:SetAlpha(0.7)
    if r.name.panoplyCut and GameTooltip then
      GameTooltip:SetOwner(r, "ANCHOR_RIGHT"); GameTooltip:SetText(r.name.panoplyFullText or ""); GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function() r.bg:SetAlpha(0.35); if r.name.panoplyCut and GameTooltip then GameTooltip:Hide() end end)
  f.list[i] = r
  return r
end
-- How many whole rows fit between the filters and the detail card (card height cy).
function PW:VisibleRows(cardH)
  local f = self.frame
  local h = (f and f:GetHeight() or 520) + PW.LIST_TOP - PW.CARD_BOTTOM - (cardH or 60) - PW.LIST_GAP
  return math.max(1, math.floor((h + 2) / PW.ROW_PITCH)), h
end
function PW:ClampOffset(o)
  local n = #(self.rows or {})
  return math.max(0, math.min(math.max(0, n - (self.visible or PW.ROWS)), o or 0))
end

-- 0.7.1: the drag handle ends 6 px left of the "Blizzard" button (measured, so a wider button at
-- large fonts still never sits under it), and the header buttons are two levels above it.
function PW:LayoutDragBar()
  local f = self.frame
  local drag, close, blizz = f and f.dragBar, f and f.closeBtn, f and f.blizz
  if not (drag and close and blizz) then return end
  local hb0 = drag.panoplyHb or 50
  local inset = 12 + (close:GetWidth() or 22) + 6 + (blizz:GetWidth() or 72) + 6
  drag:ClearAllPoints()
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
  drag:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -inset, -(hb0 - 2))
  local lv = (drag:GetFrameLevel() or 1) + 2
  close:SetFrameLevel(lv); blizz:SetFrameLevel(lv)
end

function PW:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteProfWindow", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  self.frame = f
  f:SetSize(380, 520)  -- 0.5.5: wider so recipe names fit at real font sizes
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  Panoply.Windows:OwnPlace(f)      -- 0.9.5 (item 3): in front of the main window when it opens over it; its place stays its own (PW:DragStop)
  Skin.Panel(f)
  Skin.Header(f, "Recipes", "", "ProfWindow")
  -- 0.6.0: the title area is the drag handle (Lock in Settings).
  -- 0.7.1 (X did not close, "Blizzard" did nothing): the handle used to span the whole
  -- header, and it is a sibling of the X and "Blizzard" buttons at the same frame level. WoW
  -- does not define which of two overlapping frames at one level gets the mouse, and in the
  -- client the mouse-enabled handle won: it swallowed both clicks. The handle now covers only
  -- the empty title area left of the buttons (PW:LayoutDragBar), and the buttons sit above it.
  local hb0 = math.max(50, f.panoplyHeaderBottom or 50)
  local drag = CreateFrame("Frame", nil, f)
  drag.panoplyHb = hb0
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() PW:DragStart() end)
  drag:SetScript("OnDragStop", function() PW:DragStop() end)
  drag:SetScript("OnEnter", function(self)
    if not _G.GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(PW:Locked() and "Position locked" or "Drag to move", 0.95, 0.84, 0.55, 1, true)
    GameTooltip:AddLine(PW:Locked() and ("Unlock it in " .. Panoply:SettingsPath("profWindowLocked") .. ".") or ("Your spot is kept for this character. " .. Panoply:SettingsPath("profWindowLocked") .. " has Lock and Reset position."), 0.9, 0.9, 0.88, true)
    GameTooltip:Show()
  end)
  drag:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  f.dragBar = drag
  local close = Skin.IconButton(f, "x", 22, function() PW:CloseButton() end, "Close", "Close the profession window.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -14)
  f.closeBtn = close
  f.blizz = Skin.Button(f, "Blizzard", 72, 22, function() PW:ToggleBlizzard() end, "Blizzard's window",
    "Show or hide the game's own profession window next to this one (this time only; Settings has the always-on switch).")
  f.blizz:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self:LayoutDragBar()
  -- 0.6.0: current skill / maximum as a thin flat bar under the header rule (accent fill on the
  -- dark track). Its numbers are in the subtitle above the rule, never on the bar or its fill.
  -- the header rule sits lower with large client fonts; the bar, search box and filters follow it
  local hb = math.max(50, f.panoplyHeaderBottom or 50)
  PW.SKILL_BAR_Y = -(hb + 4)
  -- 0.6.0: category tabs between the header and the search box
  local tabsY = -(hb + 14)
  PW.TAB_H = 22
  local strip = CreateFrame("Frame", nil, f)
  strip:SetPoint("TOPLEFT", f, "TOPLEFT", 16, tabsY); strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, tabsY)
  strip:SetHeight(PW.TAB_H)
  strip:EnableMouseWheel(true)
  strip:SetScript("OnMouseWheel", function(_, d) PW:ScrollTabs((d or 0) > 0 and -1 or 1) end)
  strip.tabs = {}
  strip.left = Skin.Button(strip, "<", 16, PW.TAB_H, function() PW:ScrollTabs(-1) end, "More categories", "Scroll the category tabs left (or use the mouse wheel).")
  strip.right = Skin.Button(strip, ">", 16, PW.TAB_H, function() PW:ScrollTabs(1) end, "More categories", "Scroll the category tabs right (or use the mouse wheel).")
  strip.left:SetPoint("LEFT", strip, "LEFT", 0, 0); strip.right:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
  strip.left:Hide(); strip.right:Hide()
  f.tabStrip = strip
  PW.tabFirst = 1
  local searchY = tabsY - PW.TAB_H - 6
  local sb = Skin.Bar(f, PW.SKILL_BAR_H)
  sb:SetPoint("TOPLEFT", f, "TOPLEFT", 16, PW.SKILL_BAR_Y); sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, PW.SKILL_BAR_Y)
  sb.panoplyWidth = 348
  sb:Hide()
  f.skillBar = sb
  local box = Skin.Input(f, (f:GetWidth() or 380) - 32, 24, "Search recipes or materials")
  box:SetPoint("TOPLEFT", f, "TOPLEFT", 16, searchY)
  box:SetScript("OnTextChanged", function(self)
    PW.search = self:GetText()
    if self.placeholder then if (PW.search or "") == "" then self.placeholder:Show() else self.placeholder:Hide() end end
    PW.offset = 0
    PW:Refresh()
  end)
  self.searchBox = box
  f.showAllBtn = filterButton(f, "showAll", "Show all", "Every recipe, whatever your materials and the colour filters (the category tab and search still apply). Click another filter to use the filters again.")
  f.filters = {
    filterButton(f, "haveMats", "Have mats", "Only recipes you have the materials for (bags and bank)."),
    filterButton(f, "optimal", "Orange", "Show orange recipes (always give a skill point)."),
    filterButton(f, "medium", "Yellow", "Show yellow recipes (usually give a point)."),
    filterButton(f, "easy", "Green", "Show green recipes (sometimes give a point)."),
  }
  f.greyBtn = filterButton(f, "trivial", "Grey", "Show grey recipes (no skill points). Off = hide grey.")
  -- 0.6.0: six pills sized to their measured labels; a second row only when they do not fit
  local all = { f.showAllBtn, f.filters[1], f.filters[2], f.filters[3], f.filters[4], f.greyBtn }
  f.pills = all
  local avail, x, y = (f:GetWidth() or 380) - 32, 16, searchY - 28
  local need = {}
  for i, b in ipairs(all) do need[i] = math.max(40, math.ceil(Skin.TextWidth(b.label)) + 14) end
  local total = -4
  for i = 1, #all do total = total + need[i] + 4 end
  if total < avail then   -- share the spare width so the row ends with the search box
    local extra = math.floor((avail - total) / #all)
    for i = 1, #all do need[i] = need[i] + extra end
  end
  for i, b in ipairs(all) do
    if x > 16 and x + need[i] > 16 + avail then x, y = 16, y - 24 end
    b:SetSize(need[i], 20); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    x = x + need[i] + 4
  end
  PW.LIST_TOP = y - 25
  -- 0.5.9.1: the recipe list is its own clipped area that ends above the detail card (our
  -- screenshot: rows 9-12 ran under "Pick a recipe"). Only as many rows as fit are shown; the
  -- rest scroll (mouse wheel), with a thin bar on the right. Rows are made when first needed.
  local area = CreateFrame("Frame", nil, f)
  area:SetClipsChildren(true)
  area.panoplyBox = true
  f.listArea = area
  -- 0.9.0: the suite's shared bar (Skin.ScrollBar): drag the thumb, click the track for a page, arrows for one row, the wheel as
  -- before. It sits in the 10 px the rows already leave free when the list scrolls, so the window's size, text and fonts are as
  -- they were.
  area.bar = Skin.ScrollBar(area, {
    width = 9,
    get = function() return PW.offset or 0 end,
    max = function() return math.max(0, #(PW.rows or {}) - (PW.visible or PW.ROWS)) end,
    set = function(v) PW.offset = PW:ClampOffset(math.floor(v + 0.5)) PW:Refresh(true) end,
    ratio = function() local n = #(PW.rows or {}) return n > 0 and (PW.visible or PW.ROWS) / n or 1 end,
    step = 1,
    page = function() return math.max(1, (PW.visible or PW.ROWS) - 1) end,
    length = function() return PW.barLength or 0 end,
  })
  area.bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -1)
  area.bar:Hide()
  area.track, area.thumb = area.bar.track, area.bar.thumb
  f.list = {}
  local function wheel(_, d)
    PW.offset = PW:ClampOffset((PW.offset or 0) - (d or 0) * 3)
    PW:Refresh(true)
  end
  area:EnableMouseWheel(true); area:SetScript("OnMouseWheel", wheel)
  f:EnableMouseWheel(true); f:SetScript("OnMouseWheel", wheel)
  -- Detail card
  local card = Skin.Card(f)
  card:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, PW.CARD_BOTTOM); card:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, PW.CARD_BOTTOM); card:SetHeight(86)
  f.card = card
  f.detailTitle = Skin.Name(card, 13, Skin.colors.heading); f.detailTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8); f.detailTitle:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  f.detail = Skin.Ink(card, 11, Skin.colors.ink); f.detail:SetPoint("TOPLEFT", f.detailTitle, "BOTTOMLEFT", 0, -4)
  f.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  -- 0.5.9.2: the made item (icon + quality-coloured name) and every material are hover rows:
  -- the game's own item tooltip, shift-click links it in chat, ctrl-click opens the dressing room
  local res = PW.HoverRow(card, nil)
  res.icon:SetSize(20, 20)
  -- skin v3: the item name in the skin's name font (as the detail title), the hint in its soft ink
  res.label = Skin.Name(res, 13, Skin.colors.heading); res.label:SetPoint("LEFT", res.icon, "RIGHT", 6, 0)
  if res.label.SetWordWrap then res.label:SetWordWrap(false) end
  res.hint = Skin.Ink(res, 10, Skin.colors.inkSoft); res.hint:SetText("Hover for details")
  res.hint:SetPoint("RIGHT", res, "RIGHT", -4, 0)
  if res.hint.SetJustifyH then res.hint:SetJustifyH("RIGHT") end
  res:Hide()
  f.result, f.mats = res, {}
  -- 0.7.0 (tester report): "Reserve for [-] N [+] crafts" on a favourite, its note, and the shortfall warning
  local rv = CreateFrame("Frame", nil, card)
  rv:SetHeight(20)
  rv.label = Skin.Ink(rv, 11, Skin.colors.ink); rv.label:SetPoint("LEFT", rv, "LEFT", 4, 0); rv.label:SetText("Reserve for")
  rv.minus = Skin.Button(rv, "-", 20, 18, function() PW:StepReserve(-1) end, "Reserve fewer", "Hold back materials for one craft less.")
  rv.num = Skin.Text(rv, 12, Skin.colors.heading)
  rv.plus = Skin.Button(rv, "+", 20, 18, function() PW:StepReserve(1) end, "Reserve more", "Hold back materials for one more craft.")
  rv.unit = Skin.Ink(rv, 11, Skin.colors.ink)
  if rv.num.SetJustifyH then rv.num:SetJustifyH("CENTER") end
  rv:Hide()
  f.reserve = rv
  f.resNote = Skin.Ink(card, 10, Skin.colors.inkSoft); f.resNote:Hide()
  f.resWarn = Skin.Ink(card, 10, Skin.colors.warn); f.resWarn:Hide()
  area:SetPoint("TOPLEFT", f, "TOPLEFT", PW.LIST_X, PW.LIST_TOP)
  area:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -2, PW.LIST_GAP)
  f.make = Skin.Button(f, "Make", 70, 24, function() PW:MakeQty() end, "Make", PW.MAKE_TIP)
  f.make:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 28)
  -- 0.8.1 ("no way to make a certain number"): [-] N [+] between Make and Make all, as the game's own window
  -- has beside Create. Make crafts N; Make all crafts as many as the materials allow. Both are hidden for a
  -- recipe the game cannot repeat (enchanting, cooldown recipes, one-shots) rather than left broken.
  f.qty = PW.QtyBox(f)
  f.qty:SetPoint("LEFT", f.make, "RIGHT", 6, 0)
  f.makeAll = Skin.Button(f, "Make all", 82, 24, function() PW:Make() end, "Make all", "Craft as many as your materials in your bags allow.")
  f.makeAll:SetPoint("LEFT", f.qty, "RIGHT", 6, 0)
  f.guide = Skin.Button(f, "Guide me", 100, 24, function() PW:GuideMe() end, "Guide me", "Open the Professions guide on this profession's next step.")
  f.guide:SetIcon("Arrow", 16)
  f.guide:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 28)
  -- 0.8.2 ("no report button in professions"): same report window as the guide, as a general report.
  -- 0.8.3: the Make row has no room left for it (Make, number box, Make all and Guide me fill the width), so it sits
  -- on its own footer row under them, bottom right.
  f.report = Skin.Button(f, "Report", 72, 20, function()
    if Panoply.ReportWindow then Panoply.ReportWindow:Open({ general = true }) end
  end, "Report a problem", "Something wrong with this profession window? Tell us.")
  f.report:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14 - 14, 6)      -- 14: clear of the resize grip in the corner
  -- Nov 2026: a resize grip for the height: a taller window lists more recipes, and the height is remembered. The width
  -- stays 380 (the filter pills, the tabs and the materials card are laid out for it). Not in combat (the side tabs are secure).
  Skin.Resizable(f, { key = "profWindow", combat = false, minW = 380, maxW = 380, minH = PW.MIN_H,
    onSize = function() if f:IsShown() then PW:Refresh() end end })
  Skin.Animate(f, 0)
  f:Hide()
  self:UpdateRail(true)
  return f
end

-------------------------------------------------------------------------------
-- 0.8.1: craft a number of one recipe. PW.qty is the number in the box (per recipe pick, 1 to start).
-------------------------------------------------------------------------------
PW.qty = 1
PW.QTY_MAX = 999
PW.MAKE_TIP = "Craft this recipe the number of times in the box beside it (1 unless you change it)."
function PW:Qty() return math.max(1, math.min(PW.QTY_MAX, math.floor(tonumber(self.qty) or 1))) end
function PW:SetQty(n, quiet)
  self.qty = math.max(1, math.min(PW.QTY_MAX, math.floor(tonumber(n) or 1)))
  local box = self.frame and self.frame.qty
  if box then
    local txt = tostring(self.qty)
    if box.input:GetText() ~= txt then box.input.panoplySet = true box.input:SetText(txt) box.input.panoplySet = nil end
  end
  return self.qty
end
function PW:StepQty(d) return self:SetQty(self:Qty() + (d or 0)) end
function PW:MakeQty() return self:Make(self:Qty()) end
function PW.QtyBox(parent)
  local q = CreateFrame("Frame", nil, parent)
  q:SetSize(78, 24)
  q.minus = Skin.Button(q, "-", 20, 22, function() PW:StepQty(-1) end, "Fewer", "Make one less.")
  q.minus:SetPoint("LEFT", q, "LEFT", 0, 0)
  local box = CreateFrame("EditBox", nil, q)
  box:SetSize(34, 22)
  if box.SetAutoFocus then box:SetAutoFocus(false) end
  if box.SetNumeric then box:SetNumeric(true) end
  if box.SetMaxLetters then box:SetMaxLetters(3) end
  if box.SetFont then pcall(box.SetFont, box, Skin.BODY, 13, "") end
  if box.SetJustifyH then box:SetJustifyH("CENTER") end
  box:SetText("1")
  Skin.Box(box, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  box:SetPoint("LEFT", q.minus, "RIGHT", 2, 0)
  box:SetScript("OnTextChanged", function(self)
    if self.panoplySet then return end
    local n = tonumber(self:GetText())
    if n and n >= 1 then PW.qty = math.min(PW.QTY_MAX, math.floor(n)) end
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() PW:SetQty(PW.qty) PW:MakeQty() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() PW:SetQty(PW.qty) end)
  box:SetScript("OnEditFocusLost", function() PW:SetQty(PW.qty) end)
  q.input = box
  q.plus = Skin.Button(q, "+", 20, 22, function() PW:StepQty(1) end, "More", "Make one more.")
  q.plus:SetPoint("LEFT", box, "RIGHT", 2, 0)
  Skin.Tooltip(box, "How many to make", "Type a number, or use - and +. Make crafts this many; Enter does too.")
  return q
end

function PW:Select(row)
  self.selected = row and row.name
  if row then C.SelectRecipe(row, self.kind) end
  self:Refresh(true)
end
function PW:SelectedRow()
  for _, r in ipairs(self.rows or {}) do if r.name == self.selected then return r end end
  return nil
end
-------------------------------------------------------------------------------
-- 0.5.9.2: item tooltips in the detail card. Nothing here is protected: GameTooltip,
-- ChatEdit_InsertLink and DressUpItemLink are plain UI calls, allowed in combat and taint-free.
-------------------------------------------------------------------------------
function PW.HoverRow(parent, reagent)
  local b = CreateFrame("Button", nil, parent)
  b.reagent = reagent
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(b); Skin.Solid(b.hl, Skin.colors.accent, 0.12); b.hl:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(14, 14); b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b:SetScript("OnEnter", function(self) self.hl:Show() PW:ShowTip(self, PW:SelectedRow(), self.reagent) end)
  b:SetScript("OnLeave", function(self) self.hl:Hide() PW:HideTip(self) end)
  b:SetScript("OnClick", function(self) PW:ItemClick(PW:SelectedRow(), self.reagent) end)
  return b
end

-- The game's own index for this row, only while its profession list is open and that index is
-- still the same recipe (the list can change under us: learning, filters, a different window).
function PW:LiveIndex(row)
  if not (row and row.index) then return nil end
  local tf = self:GameFrame()
  if not (tf and tf.IsShown and tf:IsShown()) then return nil end
  if row.craft then
    return (_G.GetCraftInfo and C.pc(GetCraftInfo, row.index) == row.name) and row.index or nil
  end
  if self.kind ~= "TradeSkill" or not _G.GetTradeSkillInfo then return nil end
  return C.pc(GetTradeSkillInfo, row.index) == row.name and row.index or nil
end

-- The item (or enchant) ID and the best link we have: the game's (only while the index is live),
-- then the one read with the list, then one made from the item ID ("item:123" works uncached).
function PW:ItemRef(row, j)
  if not row then return nil end
  local rg = j and row.reagents and row.reagents[j]
  if j and not rg then return nil end
  local live = self:LiveIndex(row)
  local link
  if live then
    if row.craft then
      link = j and C.pc(_G.GetCraftReagentItemLink, live, j) or (not j and C.pc(_G.GetCraftItemLink, live)) or nil
    else
      link = j and C.pc(_G.GetTradeSkillReagentItemLink, live, j) or (not j and C.pc(_G.GetTradeSkillItemLink, live)) or nil
    end
  elseif not j and self.kind == "C_TradeSkillUI" and row.recipeID then
    link = C.pc(C.G("C_TradeSkillUI.GetRecipeItemLink"), row.recipeID)
  end
  if type(link) ~= "string" or link == "" then link = nil end
  link = link or (j and rg.link or (not j and row.link)) or nil
  local id = (j and rg.itemID) or (not j and row.itemID) or C.ItemIDFromLink(link)
  local info = id and C.ItemInfo(id)
  if not link and info and info.link then link = info.link end
  if not link and id then link = "item:" .. id end
  return { id = id, link = link, info = info, live = live, craft = row.craft }
end

-- Item data not in the client's cache yet: ask again when GET_ITEM_INFO_RECEIVED brings it.
PW.waiting = {}
function PW:Wait(id) if id then self.waiting[id] = true end end

function PW:ShowTip(owner, row, j)
  local tip = _G.GameTooltip
  if not (tip and owner and row) then return false end
  local ref = self:ItemRef(row, j)
  if not ref then return false end
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  local done = false
  if ref.live then
    if row.craft then
      if j and tip.SetCraftItem then done = pcall(tip.SetCraftItem, tip, ref.live, j)
      elseif not j and tip.SetCraftSpell then done = pcall(tip.SetCraftSpell, tip, ref.live) end
    elseif tip.SetTradeSkillItem then
      if j then done = pcall(tip.SetTradeSkillItem, tip, ref.live, j) else done = pcall(tip.SetTradeSkillItem, tip, ref.live) end
    end
    -- a setter that quietly showed nothing (an empty tooltip): use the link instead
    if done and tip.NumLines and (C.pc(tip.NumLines, tip) or 0) == 0 then done = false end
  end
  if not done and ref.link and tip.SetHyperlink then done = pcall(tip.SetHyperlink, tip, ref.link) end
  if not done then   -- nothing the game can show: at least the name
    local rg = j and row.reagents[j]
    tip:SetText((rg and rg.name) or row.name or "?")
  end
  if ref.id and not ref.info and not ref.craft then self:Wait(ref.id) end
  self.tipOwner, self.tipRow, self.tipReagent = owner, row, j
  tip:Show()
  return true
end
function PW:HideTip(owner)
  if self.tipOwner == owner then self.tipOwner, self.tipRow, self.tipReagent = nil, nil, nil end
  if _G.GameTooltip_Hide then GameTooltip_Hide() elseif _G.GameTooltip then GameTooltip:Hide() end
end

-- Shift-click: the item's link in the chat box. Ctrl-click: try it on (items only).
function PW:ItemClick(row, j)
  local ref = self:ItemRef(row, j)
  if not ref then return false end
  local link = ref.link
  local full = link and link:find("|H", 1, true) and link or (ref.info and ref.info.link)
  if _G.IsShiftKeyDown and IsShiftKeyDown() then
    if not full then self:Wait(ref.id) return false end   -- not cached yet: nothing to link
    return Panoply.Compat.InsertChatLink(full)
  end
  if _G.IsControlKeyDown and IsControlKeyDown() then
    if ref.craft and not j then return false end           -- an enchant is not something to wear
    if not full then self:Wait(ref.id) return false end
    if _G.DressUpItemLink then return DressUpItemLink(full) and true or false end
  end
  return false
end

PW:On("GET_ITEM_INFO_RECEIVED", function(_, id, ok)
  id = tonumber(id)
  if not (id and PW.waiting[id]) then return end
  PW.waiting[id] = nil
  if not (PW.frame and PW.frame:IsShown()) then return end
  PW:Refresh(true)   -- the real name, colour and icon
  local tip, o = _G.GameTooltip, PW.tipOwner
  if ok ~= false and o and o:IsShown() and tip and (not tip.IsOwned or tip:IsOwned(o)) then PW:ShowTip(o, PW:SelectedRow(), PW.tipReagent) end
end)

-- 0.7.3.1: are the materials short for one craft? Enchanting (the craft window) decides as the game's own
-- enchanting window does: every material in the bags at least as often as needed, and not a "used" entry.
-- Trade skills use the game's own count (numAvailable), as before.
function PW.Short(row)
  if not row then return true end
  if row.craft then
    if row.difficulty == "used" then return true end
    for _, rg in ipairs(row.reagents or {}) do
      if (tonumber(rg.have) or 0) < (tonumber(rg.need) or 1) then return true end
    end
    return false
  end
  return (row.numAvailable or 0) < 1
end

function PW:Make(n)
  local r = self:SelectedRow()
  if not r then return false end
  -- 0.7.3.1: the game's list can move under us (a group opened or closed): find the recipe by name again
  if r.craft and _G.GetCraftInfo and C.pc(_G.GetCraftInfo, r.index) ~= r.name then
    for i = 1, C.pc(_G.GetNumCrafts) or 0 do
      if C.pc(_G.GetCraftInfo, i) == r.name then r.index = i break end
    end
  end
  -- 0.8.1 ("Make All does not work"): Make all is "as many as the materials allow", counted live from the
  -- game's own list (the number the row carried can be old); a recipe the game cannot repeat makes one.
  local rep = C.RecipeRepeat(r, self.kind)
  if not n then n = rep.canRepeat and math.max(1, rep.max) or 1 end
  self.lastMake = { name = r.name, n = n }
  -- 0.7.3.1 (tester: "nothing happens after she clicks make" on an enchant): never fail without a word.
  -- A refused or broken call is said in chat and kept in Panoply Suite's problem log (Settings > Reports &
  -- privacy, and every report). An enchant that neither waits for its item nor casts half a second later is
  -- kept in the log too (not said in chat: how quickly the game starts it is not checked in a real client).
  local ok, why, made = C.MakeRecipe(r, self.kind, n)
  if ok and made then self.lastMake.n = made end
  local R = Panoply.Reports
  if not ok then
    Panoply:Print(("The game did not start %s (%s). The game's own profession window still works; please send a report (/panoply report)."):format(r.name or "?", why or "?"))
    if R and R.NoteError then R:NoteError("caught", ("Make %s failed: %s"):format(tostring(r.name), tostring(why)), _G.debugstack and _G.debugstack(2, 8, 0) or "", "profession Make") end
    return false
  end
  if r.craft and C.After then
    local name = r.name
    C.After(0.5, function()
      local casting = _G.UnitCastingInfo and C.pc(_G.UnitCastingInfo, "player")
      if not C.SpellTargeting() and not casting and R and R.NoteError then
        R:NoteError("caught", ("Make %s: nothing started (no item target, no cast) 0.5 s after DoCraft(%s)"):format(tostring(name), tostring(r.index)), "", "profession Make")
      end
    end)
  end
  return true
end
function PW:GuideMe()
  local G = Panoply.ProfGuide
  if not G then return end
  local prof = self.prof or self:ProfName()
  G:SetActive("professions", prof)
  if Panoply.UI then Panoply.UI:Show() end
  Panoply:Print(("Professions guide: following %s."):format(prof))
end

-------------------------------------------------------------------------------
-- 0.5.9: the game's window stays loaded underneath, invisible and click-through
-------------------------------------------------------------------------------
function PW:GameFrame()
  if self.session == "craft" and _G.CraftFrame and _G.CraftFrame:IsShown() then return _G.CraftFrame, "CraftFrame" end
  return C.TradeSkillFrame()
end
function PW:WantBlizzard() return Panoply.db.profBlizzardToo or self.showBlizzard and true or false end
local function locked(tf) return C.InCombat() and tf.IsProtected and tf:IsProtected() and true or false end

-- Make the game's frame invisible without hiding it: Hide() would end the session
-- (its OnHide calls CloseTradeSkill / CloseCraft). Returns true when it is tucked away now.
-- 0.8.1 ("a stretched red bar along the bottom of the native window and across toward the bags; I could not use the native
-- profession UI or ours"): up to 0.8.0 the frame was also shrunk to scale 0.001. A part of the game's window anchored both to
-- it and to something outside it (the rank bar, a tab strip) then stretched across the screen, and showing the window again did
-- not always lay it out again. Now the frame keeps its size, scale and place: only its alpha goes to 0, and the mouse is turned
-- off on the frame and on every frame inside it (each one's own setting kept and given back), so nothing invisible catches a
-- click. Parts the game adds later (new recipe rows) are turned off by the next Tuck (TRADE_SKILL_UPDATE, Refresh).
local function eachDescendant(f, fn, depth)
  depth = depth or 0
  if depth > 12 or not (f and f.GetChildren) then return end
  local kids = { f:GetChildren() }
  for _, k in ipairs(kids) do fn(k) eachDescendant(k, fn, depth + 1) end
end
PW.EachDescendant = eachDescendant
function PW:Tuck(tf)
  if not tf then return false end
  if locked(tf) then self.pendingTuck = true return false end
  local t = tf.panoplyTucked
  if not t then
    t = { alpha = tf:GetAlpha() or 1, mouse = tf:IsMouseEnabled(), kids = {} }
    tf.panoplyTucked = t
    tf:SetAlpha(0); tf:EnableMouse(false)
  end
  eachDescendant(tf, function(k)
    if t.kids[k] == nil and k.IsMouseEnabled and k.EnableMouse and not (k.IsProtected and C.InCombat() and k:IsProtected()) then
      t.kids[k] = k:IsMouseEnabled() and true or false
      if t.kids[k] then k:EnableMouse(false) end
    end
  end)
  return true
end
function PW:Untuck(tf)
  if not (tf and tf.panoplyTucked) then return true end
  if locked(tf) then self.pendingUntuck = true return false end
  local o = tf.panoplyTucked
  tf.panoplyTucked = nil
  for k, was in pairs(o.kids or {}) do if was and k.EnableMouse then k:EnableMouse(true) end end
  tf:SetAlpha(o.alpha); tf:EnableMouse(o.mouse)
  -- an old 0.8.0 tuck may have left the scale at 0.001 (a /reload while tucked): give the window its size back
  if tf.GetScale and tf.SetScale and (tf:GetScale() or 1) < 0.1 then tf:SetScale(1) end
  return true
end
function PW:UntuckAll()
  for _, n in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[n]
    if f and f.panoplyTucked then self:Untuck(f) end
  end
end
-- Instant hide as soon as the game shows its frame (no flash before our window opens).
-- HookScript runs after the game's own OnShow and changes nothing it relies on.
function PW:HookGameFrames()
  for _, n in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[n]
    if f and f.HookScript and not f.panoplyHooked then
      f.panoplyHooked = true
      f:HookScript("OnShow", function(fr)
        if PW.active and not PW:WantBlizzard() then PW:Tuck(fr) end
        -- 0.8.1: Forever's profession overview cards and other paths show the game's window without the events below; ours
        -- opens with it whenever it shows (the session is the window that showed)
        if PW.active and not (PW.frame and PW.frame:IsShown()) then
          PW.session = (n == "CraftFrame") and "craft" or "trade"
          C.After(0.05, function() if PW.active and fr:IsShown() then PW:OnOpen() end end)
        end
      end)
    end
  end
end

-- 0.6.0: the saved spot (dragged by the title bar) wins; else right of the open left-side panels
-- (the character screen, spellbook, the game's own profession window when it shows too ...).
function PW:Anchor()
  local f = self.frame
  if not f then return nil end
  local tf = self:GameFrame()
  -- 0.8.1: the side rail's buttons are secure and anchored to this window, so it cannot be moved in combat
  if self.railSecure and C.InCombat() then self.pendingAnchor = true return tf end
  f:ClearAllPoints()
  local l, t = self:SavedSpot()
  if l then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
  elseif tf and not tf.panoplyTucked and tf.IsShown and tf:IsShown() and self:RightmostPanel() == tf then
    f:SetPoint("TOPLEFT", tf, "TOPRIGHT", 6, 0)   -- the game's window shows too: ours beside it
  else
    local x, y = self:DefaultSpot()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
  end
  return tf
end

-- Tuck or show the game's frame for the current settings, then place ours.
function PW:Apply()
  local tf = self:GameFrame()
  if not tf then return nil end
  self:HookGameFrames()
  self:HookPanels()
  if self:WantBlizzard() then self:Untuck(tf) else self:Tuck(tf) end
  self:Anchor()
  if self.frame and self.frame.blizz then self.frame.blizz:SetSelected(not tf.panoplyTucked) end
  return tf
end

function PW:ToggleBlizzard()
  local tf = self:GameFrame()
  if tf and locked(tf) then Panoply:Print("Can't change the profession window during combat.") return false end
  self.showBlizzard = not self:WantBlizzard()
  if Panoply.db.profBlizzardToo and not self.showBlizzard then Panoply.db.profBlizzardToo = false end
  self:Apply()
  return self.showBlizzard
end

-- Closing our window ends the profession session when it is the only window shown.
function PW:CloseButton()
  local tf = self:GameFrame()
  if tf and tf.panoplyTucked then
    self.closing = true
    C.CloseProfession(self.session == "craft" and "Craft" or self.kind)
    self.closing = nil
    self:OnClose()
  else
    if self.frame then self.frame:Hide() end
    self.userClosed = true
  end
end

-- 0.6.0: "Blacksmithing 142 / 225  -  17 recipes" (a temporary bonus as "142 (+10) / 225") and the
-- thin skill bar. Without a readable skill line: the old "Blacksmithing  -  17 recipes", no bar.
function PW:SkillText(prof, sk, n)
  local recipes = ("%d recipe%s"):format(n or 0, n == 1 and "" or "s")
  if not sk then return ("%s  -  %s"):format(prof or "", recipes) end
  local rank = tostring(sk.rank)
  if sk.mod and sk.mod ~= 0 then rank = ("%d (%s%d)"):format(sk.rank, sk.mod > 0 and "+" or "", sk.mod) end
  return ("%s %s / %d  -  %s"):format(prof or sk.name or "", rank, sk.max, recipes)
end
function PW:RefreshSkill(n)
  local f = self.frame
  if not f then return end
  local prof = self.prof or self:ProfName()
  local sk = C.ProfSkillLine and C.ProfSkillLine(prof, self.session == "craft") or nil
  self.skill = sk
  if n == nil then n = self.rows and #self.rows or 0 end
  f.panoplySubtitle:SetText(self:SkillText(prof, sk, n))
  local bar = f.skillBar
  if bar then
    if sk then
      bar:SetProgress(math.min(1, (sk.rank + math.max(0, sk.mod or 0)) / sk.max), "")
      bar:Show()
    else
      bar:Hide()
    end
  end
end

function PW:Refresh(keepRows)
  local f = self.frame
  if not (f and f:IsShown()) then return end
  self:LayoutDragBar()
  local rows = keepRows and self.rows or self:Rows()
  rows = rows or {}
  self:RefreshSkill(#rows)
  local F = Panoply.db.profFilters
  f.showAllBtn:SetSelected(F.showAll)
  for _, b in ipairs(f.filters) do b:SetSelected(F[b.filterKey]) end
  f.greyBtn:SetSelected(F.trivial)
  -- while "Show all" is on the other pills keep their state but are dimmed (they do not apply)
  for _, b in ipairs({ f.filters[1], f.filters[2], f.filters[3], f.filters[4], f.greyBtn }) do b:SetAlpha(F.showAll and 0.45 or 1) end
  self:LayoutTabs()
  self:UpdateRail()
  -- 0.5.9.1: the detail card first (its height sets how much room the list has), sized to
  -- its measured text so materials never run under the Make buttons.
  local sel = self:SelectedRow()
  local inner = (f:GetWidth() or 380) - 24 - 20
  local card, res = f.card, f.result
  for _, m in ipairs(f.mats) do m:Hide() end
  f.reserve:Hide(); f.resNote:Hide(); f.resWarn:Hide()
  local warn = self:ReserveWarning()
  -- a measured line of card text at y (from the card's top); returns the y below it
  local function cardLine(fs, text, y)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", card, "TOPLEFT", 10, y - 2); fs:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    fs:SetText(text); fs:SetWidth(inner); fs:Show()
    return y - 2 - math.ceil(Skin.TextHeight(fs, inner))
  end
  local cardH
  if sel then
    -- 0.5.9.2: the made item as a hover row, then one hover row per material, then the cost
    f.detailTitle:SetText(""); f.detailTitle:Hide()
    local ref = self:ItemRef(sel) or {}
    local info = ref.info
    if ref.id and not info and not sel.craft then self:Wait(ref.id) end
    local c = (info and info.quality) and C.QualityColor(info.quality) or Skin.colors.heading
    res.label.panoplyCut = nil
    res.label:SetText((info and info.name) or sel.name or "?"); res.label:SetTextColor(c[1], c[2], c[3], 1)
    -- (0.9.7 hotfix: through the shared helper, so the game's "?" is painted over when the game sends the item; an enchant has no
    -- item and keeps the recipe's own picture)
    if ref.id and not sel.craft then Panoply.Icons:Apply(res.icon, ref.link or ref.id, (info and info.icon) or sel.icon)
    else Panoply.Icons:Release(res.icon) res.icon:SetTexture((info and info.icon) or sel.icon or Skin.UNKNOWN_ITEM) end
    local nameW, hintW = Skin.TextWidth(res.label), Skin.TextWidth(res.hint)
    local room = inner + 8 - 2 - 20 - 6 - 4          -- the row is 8 wider than the text column
    local hint = nameW + 12 + hintW <= room            -- the hint only when it fits beside the name
    res.label:ClearAllPoints(); res.label:SetPoint("LEFT", res.icon, "RIGHT", 6, 0)
    -- skin v3: a name too long for the row is cut with an ellipsis (the tooltip shows it whole)
    if not hint and nameW > room and Skin.Ellipsize then Skin.Ellipsize(res.label, (info and info.name) or sel.name or "?", room); nameW = Skin.TextWidth(res.label) end
    res.label:SetWidth(math.max(20, math.min(nameW, hint and (room - hintW - 12) or room)))
    if hint then res.hint:Show() else res.hint:Hide() end
    local rowH = math.max(24, math.ceil(Skin.TextHeight(res.label, room)) + 4)
    res:ClearAllPoints()
    res:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -6); res:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
    res:SetHeight(rowH); res:Show()
    local y = -6 - rowH - 2
    local inv = Panoply.Inventory
    for j, rg in ipairs(sel.reagents or {}) do
      local m = f.mats[j]
      if not m then
        m = PW.HoverRow(card, j)
        m.text = Skin.Ink(m, 11, Skin.colors.ink); m.text:SetPoint("TOPLEFT", m, "TOPLEFT", 20, -2)
        f.mats[j] = m
      end
      local _, bags, bank = 0, rg.have or 0, 0
      if inv and inv:Enabled() and rg.itemID then _, bags, bank = inv:Have(rg.itemID) end
      local ii = rg.itemID and C.ItemInfo(rg.itemID)
      if rg.itemID and not ii then self:Wait(rg.itemID) end
      local line = ("%dx %s (%d in bags%s)"):format(rg.need or 1, rg.name or (ii and ii.name) or ("item " .. tostring(rg.itemID)), bags or 0, (bank or 0) > 0 and (", " .. bank .. " in bank") or "")
      -- 0.7.0: what your favourites hold back, in the reserved colour: "14 (4 reserved)"
      if not sel.fav and (rg.reserved or 0) > 0 then
        line = ("%s %s(%d reserved)|r"):format(line, Skin.Code(Skin.colors.accent), math.min(rg.reserved, rg.total or rg.reserved))
      end
      m.text:SetText(line)
      m.text:SetWidth(inner - 16)
      if rg.itemID then Panoply.Icons:Apply(m.icon, rg.itemID, rg.icon)
      else Panoply.Icons:Release(m.icon) m.icon:SetTexture(rg.icon or Skin.UNKNOWN_ITEM) end
      m.icon:ClearAllPoints(); m.icon:SetPoint("TOPLEFT", m, "TOPLEFT", 2, -2)
      local h = math.max(18, math.ceil(Skin.TextHeight(m.text, inner - 16)) + 3)
      m:ClearAllPoints()
      m:SetPoint("TOPLEFT", card, "TOPLEFT", 6, y); m:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, y)
      m:SetHeight(h); m:Show()
      y = y - h
    end
    -- 0.7.0 (tester report): a favourite's reservation (-/+), or what the reservations leave for this one
    if sel.fav then
      local rv, n = f.reserve, sel.reserveN or self:ReserveCount(self.prof, sel.name)
      rv.num:SetText(tostring(n)); rv.unit:SetText(n == 1 and "craft" or "crafts")
      rv.minus:ClearAllPoints(); rv.minus:SetPoint("LEFT", rv, "LEFT", 4 + math.ceil(Skin.TextWidth(rv.label)) + 6, 0)
      rv.num:SetWidth(math.max(20, math.ceil(Skin.TextWidth(rv.num)) + 6))
      rv.num:ClearAllPoints(); rv.num:SetPoint("LEFT", rv.minus, "RIGHT", 2, 0)
      rv.plus:ClearAllPoints(); rv.plus:SetPoint("LEFT", rv.num, "RIGHT", 2, 0)
      rv.unit:ClearAllPoints(); rv.unit:SetPoint("LEFT", rv.plus, "RIGHT", 6, 0)
      rv.minus:SetEnabledLook(n > 0); rv.plus:SetEnabledLook(n < PW.RESERVE_MAX)
      rv:SetHeight(math.max(20, math.ceil(Skin.TextHeight(rv.label, inner)) + 4))
      rv:ClearAllPoints(); rv:SetPoint("TOPLEFT", card, "TOPLEFT", 6, y - 2); rv:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, y - 2)
      rv:Show()
      y = y - 2 - rv:GetHeight()
      y = cardLine(f.resNote, n > 0 and ("Reserved: these materials are held back from your other recipes' Can make counts. Can make %d counts your whole stock."):format(sel.canMake or 0)
        or "Nothing reserved: set a number to hold its materials back from other recipes.", y)
    elseif (sel.canMakeFull or 0) ~= (sel.canMake or 0) then
      y = cardLine(f.resNote, ("Can make %d after what your favourites reserve (%d without)."):format(sel.canMake or 0, sel.canMakeFull or 0), y)
    end
    if warn and (sel.fav or (sel.canMakeFull or 0) ~= (sel.canMake or 0)) then y = cardLine(f.resWarn, warn, y) end
    f.detail:ClearAllPoints(); f.detail:SetPoint("TOPLEFT", card, "TOPLEFT", 10, y - 2); f.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    -- 0.7.3: materials and profit come from the one price service (Modules/Auctions/Prices.lua)
    f.detail:SetText(Panoply.Prices and Panoply.Prices.CraftLine(sel, Panoply.db.profAuctionCost ~= false) or "")
    f.detail:SetWidth(inner)
    local dh = Skin.TextHeight(f.detail, inner)
    cardH = math.max(60, math.ceil(-y + (dh > 0 and (2 + dh) or 0) + 8))
    -- 0.7.3.1 (tester: Make on an enchant, "nothing happens at all"): Make used to switch off (and swallow the
    -- click) whenever the game's numAvailable was 0; the game's own enchanting window never uses that number
    -- for its button. Now Make always answers a click once a recipe is picked (the game itself refuses a recipe
    -- it cannot make, with its own message); it only LOOKS dimmed when the materials fall short (PW.Short).
    f.make:SetEnabledLook(true); f.makeAll:SetEnabledLook(true)
    if PW.Short(sel) then
      local c = Skin.colors.dim
      f.make.label:SetTextColor(c[1], c[2], c[3], 1); f.makeAll.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    -- 0.8.1: the number box and Make all only for a recipe the game can repeat; the number is held to
    -- what the materials allow (never below 1)
    local rep = C.RecipeRepeat(sel, self.kind)
    self.repeatInfo = rep
    if sel.name ~= self.qtyFor then self.qtyFor = sel.name self:SetQty(1) end
    if rep.canRepeat then
      if rep.max >= 1 and self:Qty() > rep.max then self:SetQty(rep.max) end
      f.qty:Show(); f.makeAll:Show()
      f.make.tipBody = PW.MAKE_TIP
    else
      f.qty:Hide(); f.makeAll:Hide()
      f.make.tipBody = (rep.why or "One at a time.") .. " Click to craft it once."
    end
  else
    res:Hide()
    f.detailTitle:Show(); f.detailTitle:SetText("Pick a recipe")
    f.detail:ClearAllPoints(); f.detail:SetPoint("TOPLEFT", f.detailTitle, "BOTTOMLEFT", 0, -4); f.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    f.detail:SetText("Click a recipe for its materials. Click the star to keep it at the top.")
    f.make:SetEnabledLook(false); f.makeAll:SetEnabledLook(false)
    f.qty:Hide(); f.makeAll:Show()
    f.detail:SetWidth(inner)
    local th = Skin.TextHeight(f.detailTitle, inner)
    local dh = Skin.TextHeight(f.detail, inner)
    cardH = math.max(60, math.ceil(8 + th + 4 + dh + 10))
    if warn then   -- 0.7.0: the shortfall is said even with nothing picked
      local wy = cardLine(f.resWarn, warn, -math.ceil(8 + th + 4 + dh))
      cardH = math.max(cardH, math.ceil(-wy + 10))
    end
  end
  card:SetHeight(cardH)
  -- the list: as many whole rows as fit above the card, the rest scroll
  local vis = self:VisibleRows(cardH)
  self.visible = vis
  self.offset = self:ClampOffset(self.offset)
  local bar = #rows > vis
  for i = 1, vis do
    local r = f.list[i] or makeRow(f, i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f.listArea, "TOPLEFT", 0, -(i - 1) * PW.ROW_PITCH)
    r:SetPoint("TOPRIGHT", f.listArea, "TOPRIGHT", bar and -10 or 0, -(i - 1) * PW.ROW_PITCH)
  end
  for i, r in ipairs(f.list) do
    local row = i <= vis and rows[i + self.offset] or nil
    r.row = row
    if row then
      local c = PW.DIFF_COLOR[row.difficulty] or Skin.colors.text
      r.name:SetText(row.name or "?"); r.name:SetTextColor(c[1], c[2], c[3], 1)
      -- the game's own item/recipe icon, ? while unknown (painted again when the game sends the item)
      if row.itemID and not row.craft then Panoply.Icons:Apply(r.icon, row.itemID, row.icon)
      else Panoply.Icons:Release(r.icon) r.icon:SetTexture(row.icon or Skin.UNKNOWN_ITEM) end
      Skin.SetGlyph(r.star.tex, row.fav and "Star" or "StarEmpty"); r.star.tex:SetAlpha(row.fav and 1 or 0.45)
      r.count:SetText(row.canMake > 0 and ("Can make " .. row.canMake) or "")
      -- 0.7.0: a reserving favourite says so (in the warning colour when its stock falls short)
      if row.fav and (row.reserveN or 0) > 0 then
        r.resv:SetText("reserved"); r.resv:SetTextColor(unpack(row.reserveShort and Skin.colors.warn or Skin.colors.accent)); r.resv:Show()
      else
        r.resv:SetText(""); r.resv:Hide()
      end
      if row.name == self.selected then r.sel:Show() else r.sel:Hide() end
      r:Show()
    else
      r.resv:Hide()
      r:Hide()
    end
  end
  -- scroll bar: only when there are more recipes than rows
  local a = f.listArea
  if bar then
    local viewH = vis * PW.ROW_PITCH - 2
    self.barLength = viewH - 2
    a.bar:SetHeight(viewH - 2)
    a.bar:Update()
  else
    a.bar:Hide()
  end
  -- 0.5.5: the recipe name ends where the widest "Can make N" begins (measured, never under it)
  local cw, nw = 0, 0
  for _, r in ipairs(f.list) do
    if r:IsShown() and (r.count:GetText() or "") ~= "" then cw = math.max(cw, Skin.TextWidth(r.count)) end
    if r:IsShown() and r.resv:IsShown() then nw = math.max(nw, Skin.TextWidth(r.resv) + 4) end
  end
  -- the "reserved" note sits left of the count column; the names end before both
  for _, r in ipairs(f.list) do
    if cw > 0 then r.count:SetWidth(cw) end
    if r.resv:IsShown() then
      r.resv:ClearAllPoints()
      if (r.count:GetText() or "") ~= "" then r.resv:SetPoint("RIGHT", r.count, "LEFT", -4, 0) else r.resv:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
    end
  end
  cw = cw + nw
  for _, r in ipairs(f.list) do
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -(cw + 6 + Skin.SP.m), 0)
    -- skin v3: a long recipe name is measured and cut with an ellipsis (full name on hover)
    if r.row then
      local rowW = (f:GetWidth() or 380) - PW.LIST_X - 14 - (bar and 10 or 0)
      Skin.Ellipsize(r.name, r.row.name or "?", rowW - 52 - (cw + 6 + Skin.SP.m))
    end
  end
end

-- 0.6.0: the category tab row: "All", then each category. Only whole tabs are shown; when they
-- do not all fit, small < > buttons at the ends and the mouse wheel move it sideways.
function PW:TabList()
  local l = { "All" }
  for _, c in ipairs(self.categories or {}) do l[#l + 1] = c end
  return l
end
function PW:ScrollTabs(d)
  self.tabFirst = (self.tabFirst or 1) + (d or 0)
  self.tabReveal = nil
  self:LayoutTabs()
  return self.tabFirst
end
function PW:LayoutTabs()
  local f = self.frame
  local strip = f and f.tabStrip
  if not strip then return end
  local names = self:TabList()
  local active = self:Tab()
  local W = (f:GetWidth() or 380) - 32
  local need, total = {}, -4
  for i, n in ipairs(names) do
    local t = strip.tabs[i]
    if not t then
      t = Panoply.Kit.TextTab(strip, n, 60, function(b) PW:SetTab(b.panoplyCat) end)   -- 0.9.5 phase 4J (spec 02 section 1): underlined tabs
      -- the strip is 22 px, not the kit's 30: the words stay at the old 12 pt and the gold line sits on the bottom edge, under them
      Skin.Font(t.label, 12, nil, nil, "semi")
      t.underline:ClearAllPoints()
      t.underline:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", Skin.SP.s, 0); t.underline:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -Skin.SP.s, 0)
      t:SetHeight(self.TAB_H)
      strip.tabs[i] = t
    end
    t.panoplyCat = n
    t.label:SetText(n)
    t.tip = n == "All" and "All categories" or n
    t.tipBody = n == "All" and "Every recipe of this profession." or ("Only " .. n .. " recipes.")
    need[i] = math.max(36, t:NeedWidth() - 2 * Skin.SP.m + 16)
    total = total + need[i] + 4
  end
  for i = #names + 1, #strip.tabs do strip.tabs[i]:Hide() end
  local overflow = total > W
  local x0, room = 0, W
  if overflow then x0, room = 20, W - 40 end
  -- the first tab shown: kept in range, and moved so the active tab is visible after a pick
  local n = #names
  local function lastFrom(first)
    local x, last = 0, first - 1
    for i = first, n do if x + need[i] > room then break end x = x + need[i] + 4 last = i end
    return math.max(last, first)
  end
  local maxFirst = n
  while maxFirst > 1 and lastFrom(maxFirst - 1) == n do maxFirst = maxFirst - 1 end
  local first = overflow and math.max(1, math.min(self.tabFirst or 1, maxFirst)) or 1
  local ai
  for i, nm in ipairs(names) do if nm == active then ai = i end end
  if overflow and ai and self.tabReveal then
    if ai < first then first = ai end
    while lastFrom(first) < ai and first < maxFirst do first = first + 1 end
  end
  self.tabReveal = nil
  self.tabFirst = first
  local last = overflow and lastFrom(first) or n
  local x = x0
  for i, t in ipairs(strip.tabs) do
    if i <= n and i >= first and i <= last then
      t:ClearAllPoints(); t:SetWidth(need[i]); t:SetPoint("LEFT", strip, "LEFT", x, 0)
      t:SetActive(names[i] == active)
      t:Show()
      x = x + need[i] + 4
    else
      t:Hide()
    end
  end
  self.tabsShown = { first = first, last = last, n = n, overflow = overflow }
  if overflow then
    strip.left:Show(); strip.right:Show()
    strip.left:SetEnabledLook(first > 1); strip.right:SetEnabledLook(last < n)
  else
    strip.left:Hide(); strip.right:Hide()
  end
end

-- 0.5.9.1: a shorter window on short screens (the list just shows fewer rows)
function PW:FitHeight()
  local f = self.frame
  if not f then return end
  if self.railSecure and C.InCombat() then return end   -- 0.8.1: secure rail buttons hang on this frame
  local sh = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
  if not sh or sh <= 0 then sh = 768 end
  -- 0.6.0: +40 for the category tabs. 0.8.3: the window keeps its original height; the Report row under the Make row is
  -- paid for by the recipe list, which is 8 px shorter (PW.CARD_BOTTOM 54, was 46).
  -- a height the player chose with the grip is kept (never taller than the screen)
  local userH
  if f.panoplyUserSize then local _, uh = f:panoplyUserSize() userH = uh end
  if userH then f:SetHeight(math.max(PW.MIN_H, math.min(sh - 40, userH))) return end
  f:SetHeight(math.max(380, math.min(560, sh - 120)))   -- 16 px clear of the bottom at the -104 default top
end

-- 0.9.6 phase K: the Professions page (UI/ProfPage.lua) can show a session in its own crafting view. PW.host is the page: when the
-- player opened the profession from the page's Open button (host:Claims()), the game's window is kept tucked away (or beside, with
-- "Use Blizzard profession window too") and our separate window stays closed; a profession opened any other way (the spellbook, a
-- keybind, an action button) opens exactly as before.
PW.host = Panoply.ProfUI and Panoply.ProfUI.Host
function PW:HostedOpen()
  local tf = self:GameFrame()
  if not tf then return false end
  self:HookGameFrames()
  if self:WantBlizzard() then self:Untuck(tf) else self:Tuck(tf) end
  if self.frame and self.frame:IsShown() then self.frame:Hide() end
  return true
end
function PW:OnOpen()
  -- the game's window shows (its OnShow hook) and TRADE_SKILL_SHOW fires: both open ours. A session the page took stays the page's.
  if self.hosted then
    local tf = self:GameFrame()
    if tf and tf.IsShown and tf:IsShown() then self:HostedOpen() return end
  end
  if self.host and self.host.Claims and self.host:Claims() then
    self.pendingTuck = nil
    if self:HostedOpen() then
      self.hosted = true
      if self.host.Opened then self.host:Opened() end
      return
    end
  end
  self.hosted = nil
  self:Create()
  self.pendingTuck = nil
  if not self:Apply() then return end
  self.userClosed = nil
  self.offset = 0
  self:FitHeight()
  self.frame:Show()
  self:Refresh()
  self:Anchor()   -- 0.6.0: placed again once shown (the game has laid out its panels by now)
end
function PW:OnClose()
  self.showBlizzard = nil
  self:UntuckAll()
  if self.frame then self.frame:Hide() end
  local hosted = self.hosted
  self.hosted = nil
  if hosted and self.host and self.host.Closed then self.host:Closed() end
end
PW:On("TRADE_SKILL_SHOW", function() PW.session = "trade" PW:HookGameFrames() C.After(0.05, function() if PW.active then PW:OnOpen() end end) end)
PW:On("CRAFT_SHOW", function() PW.session = "craft" PW:HookGameFrames() C.After(0.05, function() if PW.active then PW:OnOpen() end end) end)
PW:On("PLAYER_REGEN_ENABLED", function()
  if PW.pendingAnchor then PW.pendingAnchor = nil if PW.frame and PW.frame:IsShown() then PW:Anchor() end end
  if PW.pendingRail then PW.pendingRail = nil PW:UpdateRail(true) end
  if PW.pendingUntuck then PW.pendingUntuck = nil PW:UntuckAll() end
  if PW.pendingTuck then PW.pendingTuck = nil if PW.active and PW.frame and PW.frame:IsShown() then PW:Apply() end end
end)
for _, ev in ipairs({ "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_UPDATE" }) do PW:On(ev, function()
  PW:Refresh()
  -- 0.8.1: rows the game added to its (tucked) window since: their mouse goes off too
  local tf = PW:GameFrame()
  if tf and tf.panoplyTucked and PW.active and not PW:WantBlizzard() then PW:Tuck(tf) end
end) end
-- 0.6.0: a skill-up (or a new maximum from the trainer) updates the subtitle and the skill bar
for _, ev in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
  PW:On(ev, function() if PW.frame and PW.frame:IsShown() then PW:RefreshSkill() end end)
end
for _, ev in ipairs({ "TRADE_SKILL_CLOSE", "CRAFT_CLOSE" }) do PW:On(ev, function() PW:OnClose() end) end
PW:Listen("INVENTORY_CHANGED", function() PW:Refresh() end)

-------------------------------------------------------------------------------
-- 0.8.1 ("Side tabs, like Blizzard"): a rail of icons on the window's right edge: Home (our Professions page:
-- every profession at a glance) and one icon per profession the character has learned. Opening a profession is a
-- spell cast, so each icon is a SecureActionButtonTemplate (type = spell): a click is one real key press for the
-- game, nothing is automated and nothing is tainted. Secure buttons cannot be changed in combat: the icons are
-- built and set out of combat only (PW.pendingRail catches up when combat ends). Our own drawing; no other
-- add-on's layout is used.
-------------------------------------------------------------------------------
PW.RAIL_SKIP = { Herbalism = true, Skinning = true, Fishing = true, Lockpicking = true, Riding = true }   -- no window to open
PW.RAIL_SPELL = { Mining = "Smelting" }   -- the spell that opens that profession's window
PW.RAIL_SIZE, PW.RAIL_GAP = 32, 6
function PW:SpellFor(prof) return prof and not PW.RAIL_SKIP[prof] and (PW.RAIL_SPELL[prof] or prof) or nil end
-- The character's professions that have a window, primary first (detected by Engine/ProfDetect).
function PW:RailProfessions()
  local out, seen = {}, {}
  local pr = Panoply.cdb and Panoply.cdb.professions or {}
  for _, list in ipairs({ pr.primary or {}, pr.secondary or {} }) do
    for _, n in ipairs(list) do
      if not seen[n] and self:SpellFor(n) then seen[n] = true out[#out + 1] = n end
    end
  end
  return out
end
local function spellIcon(spell) return Panoply.Icons:Spell(spell) end   -- 0.9.7 hotfix: the one shared lookup (Core/CompatModules.lua)
local function railButton(parent, secure)
  local b = CreateFrame("Button", nil, parent, secure and "SecureActionButtonTemplate" or nil)
  b:SetSize(PW.RAIL_SIZE, PW.RAIL_SIZE)
  if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
  -- 0.9.6 phase K: the game hands a secure button its click as a press when useOnKeyDown is not set (the ActionButtonUseKeyDown
  -- setting, on by default) and this one listens to the release only: it did nothing. It now acts on the release (as phase F's
  -- Turn off button and Polestar's Target button).
  if secure then b:SetAttribute("useOnKeyDown", false) end
  b.bg = Skin.Box(b, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4); b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.sel = b:CreateTexture(nil, "OVERLAY"); b.sel:SetAllPoints(b); Skin.Solid(b.sel, Skin.colors.accent, 0.28); b.sel:Hide()
  b:SetScript("OnEnter", function(self)
    if not _G.GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.panoplyTitle or "", 0.95, 0.84, 0.55, 1, true)
    if self.panoplyBody then GameTooltip:AddLine(self.panoplyBody, 0.9, 0.9, 0.88, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  return b
end
function PW:UpdateRail(force)
  local f = self.frame
  if not f then return end
  local list = self:RailProfessions()
  local sig = table.concat(list, "|") .. "#" .. tostring(self.prof or "")
  if not force and sig == self.railSig then return end
  if C.InCombat() then self.pendingRail = true return end
  self.railSig = sig
  f.rail = f.rail or { tabs = {} }
  local rail = f.rail
  if not rail.frame then
    -- its own frame beside the window (shown and hidden with it), so nothing of the window sticks out of it
    local rf = CreateFrame("Frame", "PanoplySuiteProfRail", UIParent)
    rf:SetSize(PW.RAIL_SIZE, PW.RAIL_SIZE)
    rf:SetFrameStrata("HIGH")
    rf:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, 0)
    rail.frame = rf
    if f.HookScript then
      f:HookScript("OnShow", function() rf:Show() end)
      f:HookScript("OnHide", function() rf:Hide() end)
    end
    if f:IsShown() then rf:Show() else rf:Hide() end
  end
  local rf = rail.frame
  if not rail.home then
    rail.home = railButton(rf, false)
    Skin.SetGlyph(rail.home.icon, "ProfWindow")
    rail.home.panoplyTitle = "All professions"
    rail.home.panoplyBody = "Back to the overview: every profession you have learned, its plan and what to do next."
    rail.home:SetScript("OnClick", function() if Panoply.Menu then Panoply.Menu:Open("professions") end end)
  end
  local y = -(math.max(50, f.panoplyHeaderBottom or 50) + 8)
  rail.home:ClearAllPoints(); rail.home:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, y)
  rail.home:Show()
  y = y - PW.RAIL_SIZE - PW.RAIL_GAP
  for i, prof in ipairs(list) do
    local b = rail.tabs[i]
    if not b then
      b = railButton(rf, true)
      rail.tabs[i] = b
      self.railSecure = true
    end
    local spell = self:SpellFor(prof)
    local active = prof == self.prof
    b.panoplyProf = prof
    b:SetAttribute("type", (not active) and "spell" or nil)   -- the open one needs no click
    b:SetAttribute("spell", spell)
    -- 0.9.9.4 hotfix: the profession's own Blizzard icon first (on WoW Forever the profession spell's picture came back as a gem
    -- in our screenshot, Nov 22); the spell lookup only for a profession Panoply has no icon for, never the game's "?"
    b.icon:SetTexture((Panoply.ProfUI and Panoply.ProfUI.IconFor(prof)) or spellIcon(spell) or Skin.UNKNOWN_ITEM)
    b.panoplyTitle = prof
    b.panoplyBody = active and "This is the profession shown now." or ("Open " .. prof .. ".")
    if active then b.sel:Show() else b.sel:Hide() end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, y)
    b:Show()
    y = y - PW.RAIL_SIZE - PW.RAIL_GAP
  end
  for i = #list + 1, #rail.tabs do rail.tabs[i]:Hide() end
  self.railShown = { home = true, n = #list }
end

function PW:Enable() end
function PW:Disable() self:OnClose() end   -- off: the game's own window is back as it was

PW.options = {
  { type = "check", key = "profBlizzardToo", label = "Use Blizzard profession window too",
    tip = "Off: only the Panoply Suite window shows (the game's stays open, hidden underneath). On: both, side by side.",
    onChange = function() if PW.frame and PW.frame:IsShown() then PW:Apply() end end },
  { type = "check", key = "profAuctionCost", label = "Use auction prices for material cost and profit", tip = "On: Panoply Suite's own scans, and the companion file, plus any price you set with /panoply price. Off: only the prices you set with /panoply price." },
  { type = "check", key = "profWindowLocked", label = "Lock the window position", tip = "Off: drag the window by its title bar; the spot is kept for this character." },
  { type = "button", label = "Reset position", tip = "Back to the default spot: beside the character screen and other open game panels.", func = function() PW:ResetPosition() end },
}
