-- Panoply Suite 0.9.5, phase 4A: back and forward in the main window (docs/specs/page-redesigns-v1.md 1.4). Pages jump to other
-- pages and to their settings; this is the way back, the same on every page, like a browser's.
--
--   A step of history is: the page, the tab it shows (every Kit.Tabs of the page), the page's own state (the selected profession,
--   an expanded slot, a Legacy section: a page registers it with History:State), whether the settings panel is open, on which page's
--   settings and with which sections open, and where the page and the panel are scrolled. Going to a step puts all of that back.
--
--   What makes a new step: a click on the left list, a link from one page to another, opening or closing the settings panel,
--   switching tabs, a page saying its own state changed (History:Note). NOT: scrolling, a tick box, resizing, opening or closing a
--   section of the settings panel (those only keep the step that is showing up to date).
--
--   The standard browser model: a new step after going back drops the steps that were ahead. At most 50 steps (the oldest goes).
--   For this play session only: nothing is saved.
--
--   The doors (Menu:Select, Menu:OpenGear, Gear:Open, Gear:Close, a Kit.Tabs click) wrap what they do in History:Begin() and
--   History:End(reason), so a jump that opens a page AND its settings at a section is one step. Back and Forward are two buttons at
--   the left of the top bar, the mouse's fourth and fifth buttons on the window, and two key bindings (unbound until the player binds
--   them). A page or panel reached by a jump from another page shows a small chip in its header that does the same as Back.
local ADDON, Panoply = ...
local Skin, Kit = Panoply.Skin, Panoply.Kit
local SP = Skin.SP

local Hist = { list = {}, index = 0, depth = 0, states = {}, MAX = 50 }
Panoply.History = Hist

_G.BINDING_NAME_PANOPLY_BACK = "Panoply: Back"
_G.BINDING_NAME_PANOPLY_FORWARD = "Panoply: Forward"

local function menu() return Panoply.Menu end
local function shown()
  local M = menu()
  return M and M.frame and M.frame:IsShown() and M.pageDef ~= nil
end

-------------------------------------------------------------------------------
-- A page's own state
-------------------------------------------------------------------------------
-- spec = { get = function() -> value, set = function(value), key = function(value) -> text }. get gives what the page shows now
-- (the selected profession, the expanded slot); set puts it back; key says which two values are the same step (default: tostring).
function Hist:State(pageKey, spec) self.states[pageKey] = spec end

-------------------------------------------------------------------------------
-- What is showing now
-------------------------------------------------------------------------------
local function tabsOf(page)
  local out = {}
  for _, t in ipairs(Kit.live or {}) do
    if getmetatable(t) == Kit.TabsClass and t.page == page and #t.items > 0 then out[#out + 1] = t end
  end
  return out
end

function Hist:Capture()
  if not shown() then return nil end
  local M, G = menu(), Panoply.PageSettings
  local page = M.current
  local e = { page = page, label = M.pageDef.label or page, tabs = {} }
  local id = { page }
  for _, t in ipairs(tabsOf(page)) do
    local ok, k = pcall(t.Current, t)
    if ok and k then e.tabs[#e.tabs + 1] = { t, k } id[#id + 1] = k end
  end
  local st = self.states[page]
  if st and st.get then
    local ok, v = pcall(st.get)
    if ok then
      e.state = v
      local okK, k = pcall(st.key or tostring, v)
      id[#id + 1] = "state:" .. tostring(okK and k or v)
    end
  end
  if G and G.open and G.page and G.sheet then
    local sc = G.sheet.scroll
    e.gear = { page = G.page.key, label = G.page.label, sections = G:OpenSections(), scroll = sc.GetVerticalScroll and sc:GetVerticalScroll() or 0 }
    id[#id + 1] = "gear:" .. G.page.key
  end
  local body = M.pages[M.pageDef.body]
  if body and body.panoplyArea and body.panoplyArea.GetVerticalScroll then e.scroll = body.panoplyArea:GetVerticalScroll() or 0 end
  e.id = table.concat(id, "|")
  return e
end

-- what a step is called in a tip: the page, and "settings" when its panel is open
function Hist:Label(e)
  if not e then return "" end
  if e.gear then return (e.gear.label or e.label) .. " settings" end
  return e.label
end

-- the parts of a step that change without making a new one (scroll, the panel's open sections, the page's own state while its key
-- stays the same): kept up to date so going back lands where the player was
local function freshen(cur, now)
  cur.scroll, cur.state, cur.tabs = now.scroll, now.state, now.tabs
  if cur.gear and now.gear then cur.gear.sections, cur.gear.scroll = now.gear.sections, now.gear.scroll end
end

-- the step that is showing takes what is on screen now (called before anything moves away from it)
function Hist:Leave()
  local cur = self.list[self.index]
  if not cur then return end
  local now = self:Capture()
  if now and now.id == cur.id then freshen(cur, now) end
end

-- a part of the step changed in place (a section of the settings panel opened or closed)
function Hist:Touch()
  if self.restoring or self.depth > 0 then return end
  self:Leave()
end

-------------------------------------------------------------------------------
-- The doors
-------------------------------------------------------------------------------
-- how the next step was reached, when the door knows better than "a link": "nav" = a click on the left list, "open" = the window
-- was closed and is opened on this page (the key, the minimap button, a slash command)
function Hist:Via(how) self.via = how end

function Hist:Begin()
  if self.depth == 0 then
    self.wasShown = shown() and true or false
    if not self.restoring then self:Leave() end
    -- every door is done within the frame it was opened in: one that an error left half open is shut on the next frame, so a
    -- failing page never stops Back, Forward and new steps for the rest of the session
    if not self.guard then
      self.guard = true
      Panoply.Compat.After(0, function()
        Hist.guard = nil
        if Hist.depth > 0 and not Hist.restoring then Hist.depth, Hist.via = 0, nil end
      end)
    end
  end
  self.depth = self.depth + 1
end

function Hist:End(reason)
  self.depth = math.max(0, self.depth - 1)
  if self.depth > 0 then return end
  local via = self.via
  self.via = nil
  if self.restoring then return end
  self:Record(reason, via)
end

-- a page says its own state changed (another profession was picked): a new step when its key changed
function Hist:Note(reason)
  if self.restoring or self.depth > 0 then return end
  self.wasShown = shown() and true or false
  self:Record(reason or "state")
end

function Hist:Record(reason, via)
  local e = self:Capture()
  if not e then return false end
  local cur = self.list[self.index]
  if cur and cur.id == e.id then
    freshen(cur, e)
    self:Update()
    return false
  end
  -- reached from another page by anything but the left list, with the window already open: a jump, with a way back in its header
  if cur and cur.page ~= e.page and via ~= "nav" and via ~= "open" and self.wasShown then
    e.via, e.from = "link", self:Label(cur)
  else
    e.via = via or reason
  end
  for i = #self.list, self.index + 1, -1 do self.list[i] = nil end
  self.list[#self.list + 1] = e
  while #self.list > self.MAX do table.remove(self.list, 1) end
  self.index = #self.list
  self:Update()
  return true
end

-------------------------------------------------------------------------------
-- Back and forward
-------------------------------------------------------------------------------
function Hist:CanBack() return self.index > 1 end
function Hist:CanForward() return self.index < #self.list end
function Hist:BackTo() return self.list[self.index - 1] end
function Hist:ForwardTo() return self.list[self.index + 1] end

-- everything a step holds, put back. Returns false when the page could not be shown now (a fight, and the page that is showing
-- carries secure buttons: the game does not let it be hidden; Menu says so in chat).
function Hist:Restore(e)
  local M, G, Cat = menu(), Panoply.PageSettings, Panoply.Catalog
  if not M.frame:IsShown() then M.frame:Show() end
  -- the page first: when it cannot be shown now, nothing of what is on screen is changed (the settings panel stays as it is)
  if M.current ~= e.page or not (G and G.open) then M:Select(e.page) end
  if M.current ~= e.page then return false end
  if G and G.open then G:Close(true) end
  local changed = false
  for _, t in ipairs(e.tabs or {}) do
    local obj, key = t[1], t[2]
    if obj:Has(key) and obj:Current() ~= key then obj:Select(key, true) changed = true end
  end
  local st = self.states[e.page]
  if st and st.set and e.state ~= nil then
    local ok, err = pcall(st.set, e.state)
    if not ok then Panoply:Debug("history state", e.page, err) end
    changed = true
  end
  if changed then M:RefreshCurrent() end
  if e.gear and G then
    local gp = Cat[e.gear.page]
    if gp and M:HasGear(gp) then
      G:Open(gp)
      if G.open then
        for _, k in ipairs(e.gear.sections or {}) do G:ToggleSection(k, true) end
        local sc = G.sheet.scroll
        if sc.SetVerticalScroll then sc:SetVerticalScroll(math.max(0, math.min(sc:MaxScroll(), e.gear.scroll or 0))) end
        sc:UpdateBar()
      end
    end
  end
  local body = M.pageDef and M.pages[M.pageDef.body]
  if body and body.panoplyArea and e.scroll then
    local a = body.panoplyArea
    if a.SetVerticalScroll then a:SetVerticalScroll(math.max(0, math.min(a:MaxScroll(), e.scroll))) end
    a:UpdateBar()
  end
  return true
end

function Hist:Go(delta)
  local to = self.index + delta
  local e = self.list[to]
  if not e or self.depth > 0 or self.restoring then return false end
  self:Leave()
  self.restoring = true
  local ok, res = pcall(self.Restore, self, e)
  self.restoring = false
  self.depth = 0
  if not ok then Panoply:Debug("history", res) return false end
  if res == false then return false end
  self.index = to
  self:Update()
  return true
end
function Hist:Back() return self:Go(-1) end
function Hist:Forward() return self:Go(1) end

-- a new play session of the window's history (the tests; nothing calls it in the game)
function Hist:Clear()
  self.list, self.index, self.depth, self.via, self.restoring = {}, 0, 0, nil, nil
  self:Update()
end

-------------------------------------------------------------------------------
-- The two buttons in the top bar, and the return chip
-------------------------------------------------------------------------------
local function navButton(parent, slot, onClick)
  local b = Skin.IconButton(parent, "", 24, onClick, "", nil)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetSize(12, 12)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.icon, b.panoplyIconPoint, b.panoplyIconX = t, "CENTER", 0
  b.panoplyIconHow = Kit.Icon(t, slot, { size = 12 })
  b.panoplySlot = slot
  return b
end

function Hist:BuildButtons(parent, x, y)
  if self.back then return self.back, self.fwd end
  self.back = navButton(parent, "icon.ui.back", function() Hist:Back() end)
  self.fwd = navButton(parent, "icon.ui.forward", function() Hist:Forward() end)
  self.back:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  self.fwd:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 24 + 4, y)
  self.back.panoplyKit, self.fwd.panoplyKit = "HistoryBack", "HistoryForward"
  self:Update()
  return self.back, self.fwd
end

local function setNav(b, can, tip, body)
  if not b then return end
  b:SetEnabledLook(can)             -- off: no hover, no click, the picture faded
  if b.icon and b.icon.SetDesaturated then b.icon:SetDesaturated(not can) end
  b.icon.panoplyDesat = not can
  b.tip, b.tipBody = tip, body
end

function Hist:Update()
  local back, fwd = self:BackTo(), self:ForwardTo()
  setNav(self.back, back ~= nil, back and ("Back to " .. self:Label(back)) or "Back", back and "Also the mouse's fourth button on this window." or "Nothing to go back to yet.")
  setNav(self.fwd, fwd ~= nil, fwd and ("Forward to " .. self:Label(fwd)) or "Forward", fwd and "Also the mouse's fifth button on this window." or "Nothing to go forward to.")
  -- the chip sits in the page header: laid out again when what it says may have changed
  local M = menu()
  local cur = self.list[self.index]
  local want = (cur and cur.via == "link" and self.index > 1) and (cur.from or "") or false
  if want ~= self.chipShown then
    self.chipShown = want
    -- the header may be a row taller or shorter with or without it, so the page is laid out again for the room it has
    if M and M.frame and M.frame:IsShown() and M.pageDef and not self.inChip then
      self.inChip = true
      pcall(M.RefreshCurrent, M)
      if Panoply.PageSettings and Panoply.PageSettings.open and Panoply.PageSettings.Relayout then pcall(Panoply.PageSettings.Relayout, Panoply.PageSettings) end
      self.inChip = nil
    end
  end
  -- the settings panel's own way back to its page follows the step that is showing
  if Panoply.PageSettings and Panoply.PageSettings.open and Panoply.PageSettings.LayoutHead and not self.inChip then pcall(Panoply.PageSettings.LayoutHead, Panoply.PageSettings) end
end

-- The chip for the page header when the step that is showing was reached by a jump: "< Field Kit". nil otherwise.
function Hist:Chip(header)
  local cur = self.list[self.index]
  local b = self.chip
  if not (cur and cur.via == "link" and self.index > 1) then
    if b then b:Hide() end
    return nil
  end
  if not b then
    b = Hist.MakeChip(header, function() Hist:Back() end)
    self.chip = b
  end
  if b:GetParent() ~= header then b:SetParent(header) end
  Hist.FitChip(b, cur.from or "Back", "Goes back to where you came from. The Back arrow at the top does the same.")
  return b
end

-- a chip: the back arrow and a name ("< Field Kit"). Hist.FitChip(b, name, tipBody) gives it its words and its width (b.panoplyControlW).
function Hist.MakeChip(parent, onClick)
  local b = Skin.Button(parent, "", 100, 24, onClick, "Back", nil)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetSize(10, 10)
  t:SetPoint("LEFT", b, "LEFT", 8, 0)
  Kit.Icon(t, "icon.ui.back", { size = 10 })
  b.icon, b.panoplyIconPoint, b.panoplyIconX, b.panoplyLabelX = t, "LEFT", 8, 7
  b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 7, 0)
  b.panoplyKit = "ReturnChip"
  return b
end
function Hist.FitChip(b, name, tipBody, maxW)
  maxW = maxW or 170
  b.panoplyFrom = name
  b.tip, b.tipBody = "Back to " .. name, tipBody
  -- one line always, as wide as its words: the width a longer name left on the label is taken off first; a name too long for the
  -- chip is cut with an ellipsis, never wrapped
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  b.label:SetWidth(0); b.label.hasW = nil
  b.panoplyWrapped = nil
  b.label:SetText(name)
  local pad = 2 * SP.m + 24
  local need = math.ceil(Skin.TextWidth(b.label)) + pad
  local w = math.max(70, math.min(maxW, need))
  if need > maxW then Skin.Ellipsize(b.label, name, maxW - pad) end
  b:SetSize(w, 24)
  b.panoplyControlW = w
  return w
end

-- true when the step that is showing was reached by a jump from another page (its header carries the return chip)
function Hist:Jumped()
  local cur = self.list[self.index]
  return cur ~= nil and cur.via == "link" and self.index > 1
end

-- the window closed: a door that was left half open by an error never blocks the next step
Panoply:Listen("MENU_HIDDEN", function() Hist.depth = 0 end)
