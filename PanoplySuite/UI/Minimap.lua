-- Panoply Suite minimap button: the Panoply shield (ShieldMinimap, 64 px) in both icon styles. Left-click: show or hide the guide window. Right-click: open Panoply Suite. Ctrl-click: quick switches.
-- Shift-click: turn Panoply Suite off (0.9.6 item 4). Drag to move it around the minimap (angle is saved).
-- 0.9.6 item 3 (Nov 16 2026: "the icon on the minimap should be easy to use and have instructions when you hover over it"): the
-- tooltip is one line per click, key on the left and what it does on the right, beside the button (towards the middle of the screen,
-- never over the minimap); it is shown again if something else hid it while the mouse is still on the button; the face answers the
-- mouse (a touch larger and brighter, no glow); the button sits a fixed number of layers above the minimap, whatever layer the
-- minimap is on in this client, so nothing on the minimap covers it.
local ADDON, Panoply = ...
local MM = {}
Panoply.Minimap = MM
local Skin, C = Panoply.Skin, Panoply.Compat

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

function MM:Position()
  local b = self.button
  if not b then return end
  local a = math.rad(Panoply.db.minimapAngle or 215)
  local mm = _G.Minimap
  local r = ((mm and mm.GetWidth and mm:GetWidth()) or 140) / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", mm or UIParent, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Angle (degrees) of the cursor around the minimap centre.
function MM:CursorAngle()
  local mm = _G.Minimap
  if not (mm and mm.GetCenter and _G.GetCursorPosition) then return nil end
  local mx, my = mm:GetCenter()
  local px, py = GetCursorPosition()
  local s = (mm.GetEffectiveScale and mm:GetEffectiveScale()) or 1
  if not (mx and px) then return nil end
  return math.deg(atan2(py / s - my, px / s - mx)) % 360
end

-- Right-click opens the one Panoply Suite window on the page that was open last (Home the first time in a play session: Menu:Resolve).
-- Ctrl-click is a small menu of quick switches (Step 2 B-07): each one turns something on or off at once, with no window. It ends
-- in "All settings...". Left-click on this button shows or hides the guide window (also a button in the Guide's gear; /ps guide).
-- "Hide this button" is the Minimap button setting in Help's gear (/panoply minimap brings the button back).
-- MM.SWITCHES is the list of switches; each is { id, text, tip, only = fn, get = fn -> bool, set = fn(bool) }.
-- "Connections" (Step 2 item E, the Map module) turns the zone connections on the
-- world map on and off: exits, boats, zeppelins, trams, portals and flight points; a switch with nothing behind it is never shown.
MM.SWITCHES = {
  { id = "trail", text = "Route trail", tip = "Shows or hides the dotted route trail on the world map and the minimap.",
    only = function() return true end,
    get = function() return Panoply.db.trailWorldMap ~= false or Panoply.db.trailMinimap ~= false end,
    set = function(on) Panoply:SetOption("trailWorldMap", on) Panoply:SetOption("trailMinimap", on) end },
  { id = "icons", text = "Quest icons", tip = "Shows or hides the quest icons on the world map and the minimap.",
    only = function() return Panoply.Modules and Panoply.Modules.byKey.questpins ~= nil end,
    get = function() return Panoply.db.qpWorldMap ~= false or Panoply.db.qpMinimap ~= false end,
    set = function(on) Panoply:SetOption("qpWorldMap", on) Panoply:SetOption("qpMinimap", on) end },
  { id = "connections", text = "Connections", tip = "Shows or hides the zone exits, boats, zeppelins, trams, portals and flight points on the world map.",
    only = function() return Panoply.Modules and Panoply.Modules.byKey.map ~= nil and Panoply.Modules:Wanted("map") end,
    get = function() for _, k in ipairs(Panoply.Map.CONNECTION_KEYS) do if Panoply.db[k] ~= false then return true end end return false end,
    set = function(on) for _, k in ipairs(Panoply.Map.CONNECTION_KEYS) do Panoply:SetOption(k, on) end end },
}

-- the switches that exist in this build
function MM:Switches()
  local out = {}
  for _, sw in ipairs(self.SWITCHES) do
    if not sw.only or sw.only() then out[#out + 1] = sw end
  end
  return out
end

function MM:QuickMenu()
  local items = { { header = "QUICK SWITCHES" } }
  local list = self:Switches()
  for _, sw in ipairs(list) do
    items[#items + 1] = { text = sw.text, tip = sw.tip, switch = sw.get, func = function() sw.set(not sw.get()) end }
  end
  items[#items + 1] = { divider = true }
  -- Nov 18 2026 (easier report access): the report window, where a problem or an idea can be sent
  if Panoply.ReportWindow then
    items[#items + 1] = { text = "Report a problem / Feedback", tip = "Opens the report window: tell us what is wrong, or share an idea.",
      func = function() Panoply.ReportWindow:Open({ general = true }) end }
  end
  items[#items + 1] = { text = "All settings...", tip = "Opens Panoply Suite with the All settings box ready: type what you want to change.",
    func = function() Panoply.Menu:Search() end }
  -- Nov 18 2026: 270 wide (was 230) so "Report a problem / Feedback" fits at 1.3x text
  return Skin.Menu(self.button, items, { width = 270 })
end

function MM:OnClick(button)
  -- Nov 12 2026: Left-click shows or hides the guide window; Right-click opens the main Panoply Suite window;
  -- Ctrl-click opens the quick-switches menu. Ctrl is checked first so a Mac Control-click (which the client may
  -- report as a right-click) still opens the quick switches. 0.9.6 item 4: Shift-click asks to turn Panoply Suite off.
  if IsControlKeyDown() then return self:QuickMenu() end
  if _G.IsShiftKeyDown and IsShiftKeyDown() then return self:AskTurnOff() end
  if button == "RightButton" then Panoply.Menu:Toggle() else if Panoply.UI then Panoply.UI:Toggle() end end
  -- the tooltip under the mouse stays (a click must not leave the button without its instructions)
  if self.hovered then self:ShowTip() end
end

-------------------------------------------------------------------------------
-- The tooltip (0.9.6 item 3)
-------------------------------------------------------------------------------
-- PLACEHOLDER COPY (Marketing): the title and every line below
MM.TIP_TITLE = "Panoply Suite"
MM.TIP_LINES = {
  { "Left-click", "Show or hide the guide" },
  { "Right-click", "Open the Panoply Suite menu" },
  { "Ctrl-click", "Quick switches" },
  { "Shift-click", "Turn Panoply Suite off" },
  { "Drag", "Move this button" },
}

-- The tooltip's lines: { key, what it does }.
function MM:TipLines()
  local out = {}
  for _, l in ipairs(MM.TIP_LINES) do out[#out + 1] = l end
  return out
end

-- The same as one string (tipBody, for the tests' tooltip checks and for anything that reads a button's tooltip text).
function MM:TipBody()
  local parts = {}
  for _, l in ipairs(self:TipLines()) do parts[#parts + 1] = l[2] and (l[1] .. ": " .. l[2] .. ".") or l[1] end
  return table.concat(parts, "\n")
end

-- Which side of the button the tooltip goes: towards the middle of the screen, so it never sits over the minimap (the minimap is in
-- a corner) and never runs off the edge.
function MM:TipAnchor()
  local b = self.button
  if not (b and b.GetCenter) then return "ANCHOR_LEFT" end
  local x, y = b:GetCenter()        -- (not "b and b:GetCenter()": an "and" keeps only the first of the two values)
  local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024
  local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  if not (x and y) then return "ANCHOR_LEFT" end
  local s = (b.GetEffectiveScale and b:GetEffectiveScale()) or 1
  local us = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if us and us > 0 then x, y = x * s / us, y * s / us end
  if x > sw / 2 then return y > sh / 2 and "ANCHOR_BOTTOMLEFT" or "ANCHOR_LEFT" end
  return y > sh / 2 and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_RIGHT"
end

function MM:ShowTip()
  local b, GT = self.button, _G.GameTooltip
  if not (b and GT) then return end
  b.tipBody = self:TipBody()
  self.tipAnchorUsed = self:TipAnchor()
  GT:SetOwner(b, self.tipAnchorUsed)
  GT:SetText(MM.TIP_TITLE, 0.95, 0.84, 0.55, 1, true)
  local key, act = Skin.colors.heading or { 0.95, 0.84, 0.55 }, { 0.9, 0.9, 0.88 }
  for _, l in ipairs(self:TipLines()) do
    if l[2] and GT.AddDoubleLine then GT:AddDoubleLine(l[1], l[2], key[1], key[2], key[3], act[1], act[2], act[3])
    elseif l[2] then GT:AddLine(l[1] .. ": " .. l[2], act[1], act[2], act[3])
    else GT:AddLine(l[1], 0.55, 0.78, 0.9) end
  end
  GT:Show()
end

-- while the mouse is on the button: the tooltip comes back if something else hid it (checked 5 times a second)
function MM:HoverTick(elapsed)
  self.tipWait = (self.tipWait or 0) + (elapsed or 0)
  if self.tipWait < 0.2 then return end
  self.tipWait = 0
  local b, GT = self.button, _G.GameTooltip
  -- the mouse really left (the game sends no OnLeave in a few cases, e.g. a loading screen): stop, never bring the tooltip back
  if b and (not b:IsShown() or (b.IsMouseOver and not b:IsMouseOver())) then return self:Hover(false) end
  if self.hovered and GT and not (GT.IsShown and GT:IsShown()) then self:ShowTip() self.tipRestored = (self.tipRestored or 0) + 1 end
end

function MM:Hover(on)
  local b, icon = self.button, self.icon
  self.hovered = on and true or nil
  if on then
    self:ShowTip()
    -- the face answers the mouse: 2 px larger and full brightness (resting it is a touch dimmer); no glow, no ring
    if icon then icon:SetSize(34, 34) if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end end
    self.tipWait = 0
    if not self.dragging then b:SetScript("OnUpdate", function(_, e) MM:HoverTick(e) end) end
  else
    if icon then icon:SetSize(32, 32) if icon.SetVertexColor then icon:SetVertexColor(0.88, 0.88, 0.88, 1) end end
    if not self.dragging then b:SetScript("OnUpdate", nil) end
    local GT = _G.GameTooltip
    if GT then GT:Hide() end
  end
end

-------------------------------------------------------------------------------
-- The off switch (0.9.6 item 4; Nov 16 2026: "an easy to see off switch. Giving them the ability to turn the addon off if
-- it's a bit much")
-------------------------------------------------------------------------------
-- Off means off: Panoply Suite is switched off in the game's own AddOns list (for every character) and the interface reloads. With
-- it not loaded at all, every Blizzard window works exactly as it does without Panoply Suite, nothing of it runs, and the game
-- neither reads nor writes its saved files, so every setting, character record and recording stays on disk as it was. It comes back
-- on from the game's AddOns list (Esc > AddOns, or the AddOns button on the character screen); the next login says it is back.
-- New saved key (nothing renamed): PanoplySuiteDB.suiteOffAt, the time it was turned off (read and cleared at the next login).
-- Reached from: Shift-click on this button (its tooltip says so), the first-run welcome page, and the foot of the Home page.
-- PLACEHOLDER COPY (Marketing): the title, the text and both buttons
MM.OFF_TITLE = "Turn Panoply Suite off?"
MM.OFF_TEXT = "The game reloads its interface (a few seconds) and then plays exactly as it does without Panoply Suite. Your settings, characters and recordings stay saved."
MM.OFF_BACK = "To turn it back on: press Esc, click AddOns, tick Panoply Suite, then click Reload UI."
MM.OFF_GO = "Turn off and reload"
MM.OFF_KEEP = "Keep it on"
MM.OFF_FAIL = "Panoply Suite could not turn itself off here. Turn it off in the game's AddOns list (Esc > AddOns)."
-- 0.9.6 phase F: the /reload fallback (the window says it, and the chat says it once the add-on is switched off)
MM.OFF_RELOAD = "If the game does not reload by itself, type /reload and press Enter."   -- PLACEHOLDER COPY (Marketing)
MM.OFF_DONE = "Panoply Suite is switched off. If the game did not reload, type /reload and press Enter."   -- PLACEHOLDER COPY (Marketing)
MM.OFF_COMBAT = "Panoply Suite can't be turned off during combat. Try again when the fight is over."   -- PLACEHOLDER COPY (Marketing)

-- 0.9.6 phase F (Nov 17 2026: "Turn off and reload" printed "Interface action failed because of an AddOn" and did nothing).
-- The reload is a restricted game action (C_UI.Reload / ReloadUI: hardware event only, restricted), and the client refused it from
-- Panoply Suite's own code, so the old button (a plain button calling ReloadUI) could not reload. Now the click is a secure button
-- over the "Turn off and reload" face: its PreClick (one player click, in the same call) switches Panoply Suite off in the AddOns
-- list and saves the list, then the game's own secure code runs "/reload", exactly as a /reload macro on an action bar does. Nothing
-- in between: no timer, no event, no deferral. A window holding a secure button cannot be shown or moved in combat, so it never
-- opens in combat and closes when a fight starts. The plain button stays underneath for a client without secure buttons.
local function reloadCommand()
  for i = 1, 9 do if _G["SLASH_RELOAD" .. i] == "/reload" then return "/reload" end end
  return _G.SLASH_RELOAD1 or "/reload"
end
local function inCombat() return (C and C.InCombat and C.InCombat()) or (_G.InCombatLockdown and InCombatLockdown()) or false end

function MM:BuildOff()
  if self.off then return self.off end
  local f = Skin.Window("PanoplySuiteTurnOff", 460, 260, MM.OFF_TITLE, "", "FULLSCREEN_DIALOG", "Modules")   -- 0.9.6: own header icon (GAME_ICONS; Close is a glyph only)
  f.text = Skin.Ink(f, 13)
  f.back = Skin.Ink(f, 12, Skin.colors.inkSoft)
  f.reload = Skin.Ink(f, 12, Skin.colors.inkSoft)
  for _, fs in ipairs({ f.text, f.back, f.reload }) do if fs.SetJustifyH then fs:SetJustifyH("LEFT") end end
  -- PLACEHOLDER COPY (Marketing): the two buttons' tooltips
  f.go = Skin.Button(f, MM.OFF_GO, 190, 34, function() MM:TurnOff() end, MM.OFF_GO, "Switches Panoply Suite off in the game's AddOns list and reloads the interface.")
  f.keep = Skin.Button(f, MM.OFF_KEEP, 150, 34, function() f:Hide() end, MM.OFF_KEEP, "Close this and change nothing.")
  self:BuildSecureGo(f)
  self.off = f
  return f
end

-- The secure click over the "Turn off and reload" face (made out of combat only; AskTurnOff never runs in combat).
function MM:BuildSecureGo(f)
  if f.goSecure or inCombat() then return f.goSecure end
  local ok, s = pcall(CreateFrame, "Button", "PanoplySuiteTurnOffGo", f.go, "SecureActionButtonTemplate")
  if not ok or not s then return nil end
  s:SetAllPoints(f.go)
  s.panoplyLayoutSkip = true   -- an invisible click area exactly over the face; the face itself is what the layout checker reads
  s:SetFrameLevel((f.go:GetFrameLevel() or 1) + 2)
  if s.RegisterForClicks then s:RegisterForClicks("AnyUp") end
  s:SetAttribute("useOnKeyDown", false)
  s:SetAttribute("type", "macro")
  s:SetAttribute("macrotext", reloadCommand())
  -- the face under it still answers the mouse (hover, press, tooltip)
  for _, k in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
    s:SetScript(k, function() local h = f.go:GetScript(k) if h then h(f.go) end end)
  end
  s:SetScript("PreClick", function() MM:SwitchOff() end)
  s:SetScript("PostClick", function()
    -- when the reload goes ahead this line is never seen; when the game refused it, the player is told what to type
    if MM.switchedOff then Panoply:Print(MM.OFF_DONE) end
    if f:IsShown() and not inCombat() then f:Hide() end
  end)
  f.goSecure = s
  return s
end

-- Switch Panoply Suite off in the game's AddOns list, for every character, and save the list. -> true when it was switched off
-- C_AddOns.DisableAddOn(name [, character]): no character = every character (Blizzard's AddonList passes nil for "All"; the
-- default for an omitted character has been all characters since 10.2.0). The global DisableAddOn is the older clients' name.
-- C_AddOns.SaveAddOns() writes the list now, as the AddonList's own Okay does, so the add-on stays off even if the reload fails.
-- The data add-ons stay on (phase C): they hold tables only and run nothing without Panoply Suite.
function MM:SwitchOff()
  local AO = _G.C_AddOns
  local disable = (AO and AO.DisableAddOn) or _G.DisableAddOn
  local ok = disable and pcall(disable, ADDON)
  if not ok then
    self.switchedOff = nil
    Panoply:Print(MM.OFF_FAIL)
    return false
  end
  local save = (AO and AO.SaveAddOns) or _G.SaveAddOns
  if save then pcall(save) end
  if Panoply.db then Panoply.db.suiteOffAt = (_G.time and time()) or true end
  self.switchedOff = true
  return true
end

function MM:LayoutOff()
  local f = self.off
  local w = 460
  local cw = w - 48
  f.text:SetText(MM.OFF_TEXT); f.back:SetText(MM.OFF_BACK); f.reload:SetText(MM.OFF_RELOAD)
  local y = -(f.panoplyHeaderBottom or 52) - 16
  for _, fs in ipairs({ f.text, f.back, f.reload }) do
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", 24, y); fs:SetWidth(cw)
    local h = math.ceil(Skin.TextHeight(fs, cw)); fs:SetHeight(h)
    y = y - h - 12
  end
  y = y - 6
  local gw, gh = Skin.FitButton(f.go, 190, cw)
  local kw = Skin.FitButton(f.keep, 150, cw)
  gh = gh or 34
  if gw + 12 + kw <= cw then
    f.go:ClearAllPoints(); f.go:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, y)
    f.keep:ClearAllPoints(); f.keep:SetPoint("TOPRIGHT", f.go, "TOPLEFT", -12, 0)
    y = y - gh
  else
    f.go:ClearAllPoints(); f.go:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, y); y = y - gh - 10
    f.keep:ClearAllPoints(); f.keep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, y); y = y - gh
  end
  f:SetSize(w, math.ceil(-y + 20))
  if Panoply.Windows and Panoply.Windows.Apply then Panoply.Windows:Apply(f) end
end

-- Ask first (one click more, so a stray Shift-click never reloads anything).
-- Not in combat: the window holds a secure button, and the game forbids showing or moving such a window in combat. -> the window, or nil
function MM:AskTurnOff()
  local GT = _G.GameTooltip
  if GT then GT:Hide() end
  if inCombat() then
    Panoply:Print(MM.OFF_COMBAT)
    return nil
  end
  self:BuildOff()
  self:LayoutOff()
  self.off:Show()
  if self.off.Raise then self.off:Raise() end
  Panoply:Fire("SUITE_OFF_ASKED")
  return self.off
end

-- The plain button's click (a client without secure buttons; the secure button covers it everywhere else): switch off, then ask the
-- game to reload in the same call. -> true when the reload was asked for
function MM:TurnOff()
  if inCombat() then
    Panoply:Print(MM.OFF_COMBAT)
    return false
  end
  if not self:SwitchOff() then return false end
  Panoply:Print(MM.OFF_DONE)
  local reload = (_G.C_UI and _G.C_UI.Reload) or _G.ReloadUI
  if reload then reload() end
  if self.off then self.off:Hide() end   -- after the reload call: nothing else runs between the click and the reload
  return true
end

-- A fight starts while the question is open: it closes (PLAYER_REGEN_DISABLED comes just before the combat lock, so this is allowed).
if Panoply.On then
  Panoply:On("PLAYER_REGEN_DISABLED", function() if MM.off and MM.off:IsShown() then MM.off:Hide() end end)
end

-- At login: Panoply Suite was turned off and is back on. -> the line said, or nil
-- PLACEHOLDER COPY (Marketing)
MM.BACK_ON = "Panoply Suite is back on. Everything you had is still here."
function MM:NoteBackOn()
  local db = Panoply.db
  if not (db and db.suiteOffAt) then return nil end
  db.suiteOffAt = nil
  Panoply:Print(MM.BACK_ON)
  return MM.BACK_ON
end

-- Nov 2026: the Panoply shield is the whole face of the button in both icon styles (ShieldMinimap: dark disc, brass
-- ring, the shield; 64 px for a 32 px button). The game's Hearthstone icon, the game's tracking ring and the old crest are gone.
function MM:ApplyIcon()
  local icon = self.icon
  if not icon then return end
  icon:SetTexture(Skin.TEX.ShieldMinimap); if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
  if icon.panoplyMask and icon.RemoveMaskTexture and icon.panoplyMaskOn then pcall(icon.RemoveMaskTexture, icon, icon.panoplyMask) icon.panoplyMaskOn = false end
  Skin.live[icon] = nil
  icon.panoplyGameIcon = nil
  icon:SetSize(32, 32)
end

function MM:Create()
  if self.button then return self.button end
  local parent = _G.Minimap or UIParent
  local b = CreateFrame("Button", "PanoplySuiteMinimapButton", parent)
  self.button = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  -- 0.9.6 item 3: a fixed number of layers above the minimap (it was layer 8 whatever layer the minimap is on: where the minimap and
  -- what sits on it are higher than that, they covered the button and the mouse never reached it, so no tooltip)
  self:Raise()
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  -- the shield is the whole face (art with its own disc and ring); no game ring, no extra disc, no highlight texture (no glow
  -- anywhere); 0.9.6: a hover makes the face a touch larger and brighter (MM:Hover), and the tooltip lists what each click does
  local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(32, 32); icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  self.icon = icon
  self.highlight = nil
  self:ApplyIcon()
  if icon.SetVertexColor then icon:SetVertexColor(0.88, 0.88, 0.88, 1) end
  -- Skin.Tooltip keeps the shared tooltip fields (tip, tipBody, panoplyShowTip) that the tests and the tooltip check read; the
  -- button draws its own (MM:ShowTip: one line per click)
  Skin.Tooltip(b, MM.TIP_TITLE, self:TipBody())
  b.panoplyShowTip = function() MM:ShowTip() end
  b:SetScript("OnEnter", function() MM:Hover(true) end)
  b:SetScript("OnLeave", function() MM:Hover(false) end)
  b:SetScript("OnClick", function(_, button) return MM:OnClick(button) end)
  b:SetScript("OnDragStart", function()
    MM.dragging = true
    if _G.GameTooltip then GameTooltip:Hide() end
    b:SetScript("OnUpdate", function()
      local a = MM:CursorAngle()
      if a then Panoply.db.minimapAngle = a; MM:Position() end
    end)
  end)
  b:SetScript("OnDragStop", function()
    MM.dragging = nil
    b:SetScript("OnUpdate", MM.hovered and function(_, e) MM:HoverTick(e) end or nil)
    if MM.hovered then MM:ShowTip() end
  end)
  Skin.buttons[#Skin.buttons + 1] = b
  self:Position()
  self:Refresh()
  return b
end

-- the button's layer: MEDIUM strata (above the minimap's LOW) and 8 layers above the minimap itself
function MM:Raise()
  local b, mm = self.button, _G.Minimap
  if not (b and b.SetFrameLevel) then return end
  local base = (mm and mm.GetFrameLevel and mm:GetFrameLevel()) or 0
  b:SetFrameLevel(math.min(10000, (tonumber(base) or 0) + 8))
end

function MM:Refresh()
  if not self.button then return end
  self:Raise()
  if Panoply.db.minimapButton == false then self.button:Hide() else self.button:Show() end
end
