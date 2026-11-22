-- Panoply Suite 0.9.4 (next), step 17: the highlight on the player's own action bars for the Rotation sequencer. DISPLAY ONLY.
--
-- When the sequencer shows an ability as the next one (Sequencer.lua, S:Next), the button that holds that ability on the game's own
-- action bars gets a thin coloured border. That is all it does. It never presses, casts, targets, binds or changes anything, and it
-- touches no action bar frame: it only READS them (visibility, rectangle, strata, the action slot a button shows).
--
-- DESIGN CHOSEN, and why. A frame of ours that is anchored to a protected frame (a secure action button) can itself be treated as
-- protected by the game ("implicitly protected": it may not be moved, shown or hidden by add-on code during combat lockdown) on some
-- client versions. So the highlight is NOT anchored to any action button. Out of combat, for each default action button that is on
-- screen, the button's screen rectangle is read (GetRect, scaled into UIParent's units) and ONE plain, non-secure Frame of ours is placed
-- there with SetPoint against UIParent (BOTTOMLEFT), with the button's size and frame strata. These frames are pooled (made once, out of
-- combat, and reused). In combat only Show and Hide are called on frames that are already placed: nothing is created, anchored, moved,
-- resized or re-parented. The frame's IsProtected() is read after it is placed; a frame that ever reported protected would be left alone in
-- combat (it keeps its last state). A bar that is moved or rebuilt out of combat is noticed by the rectangle check (about once a second
-- while the highlight is on) and by the bar events, and the pool is placed again then. In a fight the last map is kept.
--   * Which button holds the ability: for each default button (ActionButton1-12, MultiBarBottomLeftButton, MultiBarBottomRightButton,
--     MultiBarRightButton, MultiBarLeftButton and, only where the client has them, MultiBar5Button to MultiBar7Button) the action slot the
--     button shows is its own `action` field (what the game's bar code keeps there, so bar pages and stances are right), read at the moment
--     of use; without it, the documented slot rule of that bar. GetActionInfo(slot) says what is in the slot: a spell id (the name is
--     read with the spell-name API and compared by NAME, so a rank in the slot matches the spell) or, with step 19 on, a macro.
--   * Default buttons not on screen: then no highlight is drawn and the sequencer card says so once. Only the game's own action buttons are read.
--   * Settings, per character, saved only after a change, in the NEW key PanoplySuiteCharDB.classGlow = { on = true | false, style =
--     "subtle" | "strong" }. No `on` means "follow the sequencer switch": on while the sequencer is on, until the player changes it.
--   * Look (Skin v3 colours, no bloom, no glow texture): Subtle = a steady 2 px cerulean border; Strong = a 3 px gold border that pulses
--     (an alpha animation of our own frame). It is the highlight of an action button that we asked for; the skin's rule against glow
--     effects in the window chrome stands.
-- What of this only the real game can prove is listed in logs/094/step-17.md (UNVERIFIED).
-- Original code; no other add-on's code, layout or art was used.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local C, Skin = Panoply.Compat, Panoply.Skin
local SP = Skin.SP

local G = { entries = {}, pool = {}, count = 0, stale = true, dirty = true, checked = 0 }
CP.Glow = G

G.LABEL = "Highlight the button on my action bars"
G.TIP = "On: the button that holds the next ability gets a coloured border on your action bars. The next ability display never casts; it shows what to press next."
G.STYLES = { subtle = "Subtle", strong = "Strong" }
G.STYLE_ORDER = { "subtle", "strong" }
G.STYLE_TIP = { subtle = "A thin steady border.", strong = "A thicker border that pulses." }
G.POOL_MAX = 140          -- at most this many buttons are watched (the game's bars hold 120 slots; extra bars add a few more)
G.CHECK_EVERY = 1         -- seconds between two looks at whether a bar moved (out of combat only)
G.LEVEL_UP = 8            -- the highlight sits this many frame levels above its button
G.THICK = { subtle = 2, strong = 3 }

-- the default bars, by the global names of their buttons. Only the ones that exist on this client are used (feature-detected, never
-- assumed). first = the slot of the bar's first button by the documented rule, used only when a button has no `action` of its own.
G.BARS = {
  { "ActionButton", 12 },
  { "MultiBarBottomLeftButton", 12, 60 },
  { "MultiBarBottomRightButton", 12, 48 },
  { "MultiBarRightButton", 12, 24 },
  { "MultiBarLeftButton", 12, 36 },
  { "MultiBar5Button", 12 },
  { "MultiBar6Button", 12 },
  { "MultiBar7Button", 12 },
}

local function S() return CP.Seq end
local function ask(path, ...) return S().read.ask(path, ...) end

-------------------------------------------------------------------------------
-- The settings (plain saved data, new key only)
-------------------------------------------------------------------------------
local function saved() local d = Panoply.cdb and Panoply.cdb.classGlow return type(d) == "table" and d or nil end

-- on, as the player sees it: their own choice when they made one, else it follows the sequencer's switch
function G:IsOn()
  local d = saved()
  if d and type(d.on) == "boolean" then return d.on end
  return S():IsOn()
end

function G:Style()
  local d = saved()
  if d and G.STYLES[d.style] then return d.style end
  return "subtle"
end

-- true when the highlight should be drawn now: the sequencer is shown (as drawn: a switch flipped in a fight waits) and the player wants it
function G:Wanted()
  return S():Shown() and self:IsOn() and CP:PlayerClass() ~= nil
end

local function write(key, value)
  if not Panoply.cdb then return false end
  if type(Panoply.cdb.classGlow) ~= "table" then Panoply.cdb.classGlow = {} end
  Panoply.cdb.classGlow[key] = value
  return true
end

function G:SetOn(on)
  if not write("on", on and true or false) then return false end
  self:Refresh()
  return true
end

-- true when the style was applied at once, false when it waits for the end of the fight
function G:SetStyle(style)
  if not G.STYLES[style] then return false end
  if not write("style", style) then return false end
  if C.InCombat() then
    self.styleWait = true
    S().switchWait = true
    S():UpdateAll()
    return false
  end
  self:ApplyStyle()
  self:SyncControls()
  self:Refresh()
  return true
end

-------------------------------------------------------------------------------
-- Reading the bars (read only; nothing of the game's is written)
-------------------------------------------------------------------------------
-- the action slot a default button shows now: its own `action` (the game's bar code keeps it), else the documented rule
local function slotOf(btn, bar, i)
  local a = btn.action
  if type(a) == "number" and a > 0 then return a end
  if bar[3] then return bar[3] + i end
  local page = tonumber(ask("GetActionBarPage")) or 1
  local bonus = tonumber(ask("GetBonusBarOffset")) or 0
  if bonus > 0 and page == 1 then return (5 + bonus) * 12 + i end
  return (page - 1) * 12 + i
end

-- the button's rectangle in UIParent's units (nil when it is not on screen or the game did not say), and its strata and level
local function capture(btn)
  if not (btn.IsVisible and btn:IsVisible()) then return nil end
  local l, b, w, h = btn:GetRect()
  l, b, w, h = C.Readable(l), C.Readable(b), C.Readable(w), C.Readable(h)
  if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
  local es, us = btn:GetEffectiveScale(), _G.UIParent:GetEffectiveScale()
  es, us = C.Readable(es), C.Readable(us)
  if not es or not us or us == 0 then return nil end
  local k = es / us
  return l * k, b * k, w * k, h * k, btn:GetFrameStrata(), btn:GetFrameLevel()
end

-------------------------------------------------------------------------------
-- The pooled frames: plain, non-secure, parented to UIParent, never anchored to an action button
-------------------------------------------------------------------------------
local function makeFrame()
  local f = CreateFrame("Frame", nil, _G.UIParent)
  f:EnableMouse(false)
  f.edges = {}
  for i = 1, 4 do f.edges[i] = f:CreateTexture(nil, "OVERLAY") end
  -- the pulse of the strong style: an alpha animation of this frame (nothing else moves or changes size)
  if f.CreateAnimationGroup then
    local ag = f:CreateAnimationGroup()
    if ag then
      if ag.SetLooping then ag:SetLooping("BOUNCE") end
      local a = ag:CreateAnimation("Alpha")
      if a then
        if a.SetFromAlpha then a:SetFromAlpha(1) a:SetToAlpha(0.4) elseif a.SetChange then a:SetChange(-0.6) end
        if a.SetDuration then a:SetDuration(0.7) end
      end
      f.pulse = ag
    end
  end
  f:SetScript("OnShow", function(self) if self.panoplyStrong and self.pulse then self.pulse:Play() end end)
  f:SetScript("OnHide", function(self) if self.pulse then self.pulse:Stop() end end)
  f:Hide()
  return f
end

-- the border's look for the style (out of combat: it sets points and sizes of our own textures)
local function paint(f, style)
  local t = G.THICK[style] or 2
  local col = style == "strong" and Skin.colors.highlight or Skin.colors.accent
  local e = f.edges
  for i = 1, 4 do
    e[i]:ClearAllPoints()
    e[i]:SetColorTexture(col[1], col[2], col[3], 1)
  end
  e[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0);       e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0);       e[1]:SetHeight(t)
  e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); e[2]:SetHeight(t)
  e[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0);       e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0);   e[3]:SetWidth(t)
  e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0);     e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); e[4]:SetWidth(t)
  f.panoplyStrong = style == "strong"
  if not f.panoplyStrong and f.pulse then f.pulse:Stop() f:SetAlpha(1) end
  if f.panoplyStrong and f:IsShown() and f.pulse then f.pulse:Play() end
end

function G:ApplyStyle()
  self.styleWait = nil
  local style = self:Style()
  for _, f in ipairs(self.pool) do paint(f, style) end
  self.styleApplied = style
end

-------------------------------------------------------------------------------
-- The map of buttons: built out of combat; in a fight the last one is kept
-------------------------------------------------------------------------------
-- true when the card should say the game's own action buttons are not there to light
function G:BarsReplaced()
  return self.replaced == true and self:Wanted()
end

-- true while there is something to look at (the sequencer asks before it queues work for a closed window)
function G:Active()
  return self.count > 0 and self:Wanted()
end

function G:Scan()
  if C.InCombat() then self.dirty = true return false end
  -- the rectangles are read afresh: they can be trusted again (Nov 14 2026, 17-22 review backlog 2: see G:Rebuild)
  self.dirty, self.stale, self.untrusted = false, true, nil
  self.replaced = false
  local n = 0
  -- every default button frame the client has, on screen or not (the rectangle check looks at them all)
  local all = self.all
  if not all then all = {} self.all = all end
  local na = 0
  for _, bar in ipairs(G.BARS) do
    for i = 1, bar[2] do
      local b = _G[bar[1] .. i]
      if b then
        na = na + 1
        local a = all[na]
        if not a then a = {} all[na] = a end
        a.btn, a.bar, a.i = b, bar, i
      end
    end
  end
  for k = na + 1, #all do all[k].btn = nil end
  self.allCount = na
  do
    for k = 1, na do
      local a = all[k]
      if n < G.POOL_MAX then
        local x, y, w, h, strata, level = capture(a.btn)
        if x then
          n = n + 1
          local e = self.entries[n]
          if not e then e = {} self.entries[n] = e end
          local f = self.pool[n]
          local fresh = not f
          if fresh then f = makeFrame() self.pool[n] = f end
          e.btn, e.bar, e.i, e.glow = a.btn, a.bar, a.i, f
          e.x, e.y, e.w, e.h = x, y, w, h
          e.slot, e.kind, e.name, e.id, e.mid = nil, nil, nil, nil, nil
          f:ClearAllPoints()
          f:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", x, y)
          f:SetSize(w, h)
          if strata then f:SetFrameStrata(strata) end
          if level then f:SetFrameLevel(level + G.LEVEL_UP) end
          if fresh then paint(f, self:Style()) end
          -- placed against UIParent only, so it must not be protected; if the game ever says it is, it is left alone in combat
          f.panoplyNoCombat = f:IsProtected() and true or nil
        end
      end
    end
    -- no default button on screen: the bars are drawn by something else (or hidden). Where the client has no default bar frames at all
    -- there is nothing to say.
    if n == 0 and na > 0 then self.replaced = true end
  end
  for k = n + 1, #self.entries do
    local e = self.entries[k]
    e.btn, e.glow = nil, nil
  end
  for k = n + 1, #self.pool do
    local f = self.pool[k]
    if f:IsShown() then f:Hide() end
  end
  if self.styleApplied ~= self:Style() then self:ApplyStyle() end
  self.count = n
  self.checked = C.GetTime()
  return true
end

-- has any watched button moved or changed size since the map was made? (out of combat; numbers only, nothing is made)
function G:Moved()
  local all, j = self.all, 0
  for k = 1, self.allCount or 0 do
    local x, y, w, h = capture(all[k].btn)
    if x then
      j = j + 1
      local e = self.entries[j]
      if not e or e.btn ~= all[k].btn or math.abs(x - e.x) > 0.5 or math.abs(y - e.y) > 0.5 or math.abs(w - e.w) > 0.5 or math.abs(h - e.h) > 0.5 then return true end
    end
  end
  return j ~= self.count
end

-- the map made again soon (a burst of bar events becomes one scan); in a fight it waits for the end of it
-- Nov 14 2026 (17-22 review, backlog 2): a bar event (page, stance, bonus or override bar, screen size or scale) that fires IN A FIGHT may have
-- moved or replaced the buttons the rectangles were read from. The map cannot be made again in a fight (nothing of ours is moved there), so the
-- rectangles are marked as not to be trusted: the highlight is hidden (Refresh) rather than left on a place that may now be another button, and
-- comes back when the fight ends and the map is made again (Scan).
function G:Rebuild()
  self.stale = true
  if C.InCombat() then
    self.dirty, self.untrusted = true, true
    self:HideAll()          -- at once, whoever called (only Hide of frames already placed: allowed in a fight)
    return
  end
  if self.rebuildQueued then return end
  self.rebuildQueued = true
  C.After(0.2, function()
    G.rebuildQueued = nil
    G:Scan()
    G:Refresh()
  end)
end

-------------------------------------------------------------------------------
-- What each button holds, and which ones light up
-------------------------------------------------------------------------------
-- reads what the button's slot holds (data only, safe in a fight)
local function readEntry(e)
  local slot = slotOf(e.btn, e.bar, e.i)
  e.slot, e.kind, e.name, e.id, e.mid = slot, nil, nil, nil, nil
  if not slot then return end
  local has = ask("HasAction", slot)
  if has == false then return end
  local kind, id = ask("GetActionInfo", slot)
  if kind == "spell" and type(id) == "number" then
    e.kind, e.id, e.name = "spell", id, S().read.spellName(id)
  elseif kind == "macro" and type(id) == "number" then
    e.kind, e.mid = "macro", id
  end
end

-- does this button hold the wanted spell? A macro counts only with step 19's option ON (its spell is asked each time: it can change)
local function lights(e, want, adv)
  if e.kind == "spell" then
    if want.id and e.id == want.id then return true end
    return e.name ~= nil and e.name == want.name
  elseif e.kind == "macro" and adv then
    local sp = CP.Cond:MacroSpellAt(e.mid)
    return sp ~= nil and sp == want.name
  end
  return false
end

local function setShown(e, on)
  local f = e.glow
  if not f or f.panoplyNoCombat and C.InCombat() then return end
  local shown = f:IsShown()
  if on and not shown then f:Show() elseif not on and shown then f:Hide() end
end

function G:HideAll()
  for i = 1, self.count do setShown(self.entries[i], false) end
end

-- looks at the next step and the buttons and shows or hides the frames that already exist. Safe in combat: only reads, Show and Hide.
function G:Refresh()
  local combat = C.InCombat()
  if not combat then
    if self.dirty then self:Scan()
    elseif self:Wanted() and not self.replaced and C.GetTime() - self.checked >= G.CHECK_EVERY then
      self.checked = C.GetTime()
      if self:Moved() then self:Scan() end
    end
  end
  if self.count == 0 then return end
  if self.untrusted then self:HideAll() return end    -- the places may be wrong: nothing points at a button until they are read again
  local step = self:Wanted() and not self.replaced and S():Next() or nil
  if not step then self:HideAll() return end
  local stale = self.stale
  self.stale = false
  local adv = CP.Cond and CP.Cond.Enabled() or false
  for i = 1, self.count do
    local e = self.entries[i]
    if stale or e.slot ~= slotOf(e.btn, e.bar, e.i) then readEntry(e) end
    setShown(e, lights(e, step, adv))
  end
end

-------------------------------------------------------------------------------
-- The controls on the sequencer card (own class page only)
-------------------------------------------------------------------------------
function G:SyncControls()
  local h = self.controls
  if not h or C.InCombat() then return end
  local style = self:Style()
  for _, t in ipairs(h.tabs) do t:SetActive(t.panoplyStyle == style) end
end

-- c is the open card, holder the page's content frame, rec the card's record (Sequencer.lua Fill)
function G:FillControls(c, holder, rec)
  local PAD = 12
  local chk = Skin.Check(c, G.LABEL, { get = function() return G:IsOn() end, set = function(on) G:SetOn(on) end }, nil, G.TIP, true)
  chk:ClearAllPoints(); chk:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local _, ch = chk:FitLabel(c.inner - 27)
  c.y = c.y - ch - SP.m
  holder.glowSwitch = chk
  local lab = Skin.Label(c, 10, Skin.colors.inkSoft)
  lab:SetText("HIGHLIGHT STYLE")
  lab:SetWidth(c.inner)
  lab:ClearAllPoints(); lab:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - Skin.TextHeight(lab, c.inner) - SP.xs
  local tabs = {}
  for _, key in ipairs(G.STYLE_ORDER) do
    local t = Skin.Tab(c, G.STYLES[key], 90, function() G:SetStyle(key) end, G.STYLES[key], G.STYLE_TIP[key])
    t.panoplyPicker, t.panoplyStyle = true, key
    tabs[#tabs + 1] = t
  end
  local bh = Skin.FlowButtons(c, tabs, PAD, c.y, c.inner, SP.s, 90)
  c.y = c.y - bh - SP.m
  self.controls = { switch = chk, tabs = tabs, holder = holder }
  holder.glowTabs = tabs
  for _, t in ipairs(tabs) do t:SetActive(t.panoplyStyle == self:Style()) end
end

-------------------------------------------------------------------------------
-- Game events
-------------------------------------------------------------------------------
-- the bars changed: what a button holds is read again (data only); the map is made again soon, out of combat
local function slotsChanged() G.stale = true S():Queue() end
Panoply:On("ACTIONBAR_SLOT_CHANGED", slotsChanged)
Panoply:On("UPDATE_MACROS", slotsChanged)
local function pagesChanged() G:Rebuild() S():Queue() end
Panoply:On("UPDATE_BONUS_ACTIONBAR", pagesChanged)
Panoply:On("ACTIONBAR_PAGE_CHANGED", pagesChanged)
Panoply:On("UPDATE_SHAPESHIFT_FORM", pagesChanged)
Panoply:On("UPDATE_OVERRIDE_ACTIONBAR", pagesChanged)
Panoply:On("DISPLAY_SIZE_CHANGED", function() G:Rebuild() end)
Panoply:On("UI_SCALE_CHANGED", function() G:Rebuild() end)
Panoply:On("SPELLS_CHANGED", function() G.stale = true end)
Panoply:On("PLAYER_ENTERING_WORLD", function()
  G:Rebuild()
  -- the bars are laid out a moment after the world appears: look once more
  C.After(2, function() G:Rebuild() end)
end)
Panoply:On("PLAYER_REGEN_ENABLED", function()
  if G.dirty or G.styleWait then
    if G.styleWait then G:ApplyStyle() end
    G:Rebuild()
  end
  G:SyncControls()
end)

-------------------------------------------------------------------------------
-- All settings: the search finds these by name and opens the Rotation topic of the class page
-------------------------------------------------------------------------------
do
  local Cat = Panoply.Catalog
  if Cat and type(Cat.ACTIONS) == "table" then
    local function open() if CP.Open then CP:Open(nil, "rotation") end end
    table.insert(Cat.ACTIONS, { id = "action:seqglow", label = G.LABEL, words = "rotation sequencer highlight glow action bar button next ability class",
      page = "class", run = open })
    table.insert(Cat.ACTIONS, { id = "action:seqglowstyle", label = "Highlight style: Subtle or Strong", words = "rotation sequencer highlight glow action bar border pulse subtle strong class",
      page = "class", run = open })
  end
end
