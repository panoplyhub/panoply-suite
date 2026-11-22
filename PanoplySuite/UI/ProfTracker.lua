-- Panoply Suite profession tracker: a small floating card next to the guide that always shows your
-- profession's next step (skill, bar to the trainer cap, what to do, where) with Go / Later buttons.
local ADDON, Panoply = ...
local T = {}
Panoply.ProfTracker = T
local Skin, C, PD = Panoply.Skin, Panoply.Compat, Panoply.ProfData
local WIDTH = 300
T.MIN_W, T.MAX_W = 260, 520

function T:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteProfTracker", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  self.frame = f
  f:SetSize(WIDTH, 112)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() if not Panoply.db.windowLocked then f:StartMoving() end end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    Panoply.cdb.trackerPos = Panoply.Windows:Place(f)      -- { p, rp, x, y, s }: s is the scale the offsets are in
  end)
  -- Window size (0.7.3.7): the tracker is one of the windows the setting reaches; a place it saved is saved again after a rescale.
  -- It is taken in before it is placed, so a saved place is put on at the scale the window has now (Windows:Offsets).
  Panoply.Windows:Register(f, { save = function(fr)
    local tp = Panoply.cdb and Panoply.cdb.trackerPos
    if type(tp) == "table" and tp.p then Panoply.cdb.trackerPos = Panoply.Windows:Place(fr) end
  end })
  local tp = Panoply.cdb and Panoply.cdb.trackerPos
  if tp and tp.p then
    local x, y = Panoply.Windows:Offsets(f, tp)
    f:SetPoint(tp.p, UIParent, tp.rp or tp.p, x, y)
  elseif Panoply.UI and Panoply.UI.frame then f:SetPoint("TOPRIGHT", Panoply.UI.frame, "BOTTOMRIGHT", 0, -8)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -470, -30) end  -- beside the guide window
  Skin.Panel(f, Panoply.db.windowAlpha, true)
  self.icon = f:CreateTexture(nil, "OVERLAY"); self.icon:SetSize(24, 24); Skin.SetIcon(self.icon, "Professions")
  self.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  self.title = Skin.Heading(f, 12, "Professions")
  self.title:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -9)
  if self.title.SetWordWrap then self.title:SetWordWrap(true) end
  local close = Skin.IconButton(f, "x", 16, function() Panoply:SetOption("profTracker", false) end, "Hide the profession tracker",
    "Turn it back on in " .. Panoply:SettingsPath("profTracker") .. ", or type /panoply prof tracker.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  self.switch = Skin.Button(f, "Switch", 52, 20, function() T:Cycle() end, "Switch profession",
    "Follow your other profession instead (for example Mining instead of Blacksmithing).")
  self.switch:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self.bar = Skin.Bar(f, 8); self.bar.panoplyWidth = WIDTH - 24
  self.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32); self.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -32)
  self.step = Skin.Text(f, 12, Skin.colors.text)
  self.step:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48); self.step:SetWidth(WIDTH - 24)
  self.sub = Skin.Text(f, 10, Skin.colors.dim)
  self.sub:SetWidth(WIDTH - 24)
  self.go = Skin.Button(f, "Show in guide", 104, 20, function() T:Go() end, "Show in guide",
    "Put this profession step in your guide window now, with the arrow.")
  self.later = Skin.Button(f, "Later", 60, 20, function() Panoply.ProfGuide:Snooze(Panoply.ProfGuide:First()) end, "Later",
    "Hide this step for 15 minutes and carry on levelling.")
  self.menuBtn = Skin.Button(f, "Plan", 52, 20, function() Panoply.Menu:Open("professions") end, "Open the profession plan",
    "Your full plan: shopping list, trainers, segments and where to gather.")
  for _, ev in ipairs({ "PROF_UPDATED", "STEP_CHANGED", "STEP_UPDATED", "OPTION_CHANGED" }) do Panoply:Listen(ev, function() T:Refresh() end) end
  -- Nov 2026: a resize grip. The tracker is as tall as what it says (Refresh sets the height), so the grip changes its width
  -- and the words wrap to it; the width is remembered.
  Skin.Resizable(f, { key = "profTracker", minW = T.MIN_W, maxW = T.MAX_W, minH = 60, onSize = function(_, _, done) if done then T:Refresh() end end })
  self:Refresh()
  return f
end

-- Go opens the guide window on the tracked profession (the arrow branch is for when the guide window is not used)
function T:Go()
  local G = Panoply.ProfGuide
  if Panoply:PlayAlong() then
    local st = G:First()
    if st and st.mapID and st.x and Panoply.Arrow then Panoply.Arrow:PointAt(st.mapID, st.x, st.y, Panoply.StepText.Headline(st)) end
    return
  end
  G:Force(); Panoply.UI:Show()
end

function T:Cycle()
  local G = Panoply.ProfGuide
  local list = G:Chosen()
  if #list < 2 then return end
  local cur = G:Tracked()
  local i = 1
  for k, n in ipairs(list) do if n == cur then i = k end end
  G:SetTracked(list[i % #list + 1])
end

-- 0.7.3.6 (profiles): where the saved place says; else beside the guide window, as when it is made
function T:ApplySavedPlace()
  local f = self.frame
  if not f then return end
  local tp = Panoply.cdb and Panoply.cdb.trackerPos
  f:ClearAllPoints()
  if tp and tp.p then
    local x, y = Panoply.Windows:Offsets(f, tp)
    f:SetPoint(tp.p, UIParent, tp.rp or tp.p, x, y)
  elseif Panoply.UI and Panoply.UI.frame then f:SetPoint("TOPRIGHT", Panoply.UI.frame, "BOTTOMRIGHT", 0, -8)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -470, -30) end
end

function T:Refresh()
  local f = self.frame
  if not f then return end
  local G = Panoply.ProfGuide
  local name = G and G:Tracked()
  if not (Panoply.db and Panoply.db.profTracker ~= false) or not name then f:Hide() return end
  -- 0.9.5 phase 4K (spec 06a section 3.3): while the guide window shows, the card is a docked section of it (UI/MainFrame.lua); this
  -- window is for when the guide window is hidden
  if Panoply.UI and Panoply.UI.DocksProfession and Panoply.UI:DocksProfession() then f:Hide() return end
  f:Show()
  -- the width the player gave it with the grip (300 until they do); everything below is measured for it
  local WIDTH = math.max(T.MIN_W, math.min(T.MAX_W, f:GetWidth() or WIDTH))
  self.bar.panoplyWidth = WIDTH - 24
  self.step:SetWidth(WIDTH - 24); self.sub:SetWidth(WIDTH - 24)
  local rank, max = Panoply.Professions:CurrentSkill(name)
  self.title:SetText(rank and ("%s  %d / %d"):format(name, rank, max or 0) or name)
  -- 0.5.5: measured layout; the title stays left of Switch and close, and every line below is
  -- placed from the height the text really takes.
  local SP = Skin.SP
  local multi = #G:Chosen() > 1
  if multi then self.switch:Show() else self.switch:Hide() end
  local sw = multi and (Skin.FitButton(self.switch, 52) + 6) or 0
  local titleW = WIDTH - 38 - 8 - 16 - 6 - sw - 6
  self.title:SetWidth(titleW)
  local top = math.max(32, 9 + Skin.TextHeight(self.title, titleW) + SP.s)

  local _, rk = Panoply.Professions:RankFor(PD[name] or {}, max)
  local lo = 0
  for _, r in ipairs(PD[name] and PD[name].ranks or {}) do if r.max == max then lo = r.minSkill or 0 end end
  if rank and max and max > 0 then
    self.bar:SetProgress((rank - lo) / math.max(1, max - lo), rank >= max and (rk and ("Capped: train " .. rk.name) or "Maxed!") or ("%d to the %d cap"):format(max - rank, max))
  else
    self.bar:SetProgress(0, "Not learned yet")
  end
  -- 0.6.0: the bar label sits above the bar, never on the fill
  top = top + Skin.BarLabelSpace(self.bar)
  self.bar:ClearAllPoints()
  self.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -top); self.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -top)
  local st = G:First()
  local inGuide = st and Panoply.Engine.detour == st
  self.step:SetText(st and Panoply.StepText.Headline(st) or (rank and rank >= 300 and "All done: 300!" or "Nothing to do right now."))
  local y = -(top + 10 + SP.s)
  self.step:ClearAllPoints(); self.step:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
  y = y - Skin.TextHeight(self.step, WIDTH - 24) - SP.xs
  local sub = ""
  local along = Panoply:PlayAlong()   -- 0.7.1: no guide window: Go points the arrow instead
  self.go.label:SetText(along and "Point arrow" or "Show in guide")
  if st then
    if along then sub = st.mapID and "Click Point arrow to head there." or ""
    elseif inGuide then sub = "In your guide now - follow the arrow."
    elseif st.gather then sub = "Do this as you pass by; it never takes over your route."
    elseif st.wait then sub = "Comes back by itself when you are ready."
    else sub = G:Mode() == "off" and "Click Show in guide to follow it." or "Shows in your guide when you are close by." end
  end
  self.sub:SetText(sub)
  self.sub:ClearAllPoints(); self.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
  if sub ~= "" then y = y - Skin.TextHeight(self.sub, WIDTH - 24) end
  y = y - SP.s
  local bh = Skin.FlowButtons(f, { self.go, self.later, self.menuBtn }, 12, y, WIDTH - 24 - 14, 6, 50)     -- 14: clear of the resize grip
  self.go:SetEnabledLook(st ~= nil and (along and st.mapID ~= nil or not along and not inGuide))
  self.later:SetEnabledLook(st ~= nil)
  f:SetHeight(-y + bh + SP.m)
end

Panoply.optionHooks.profTracker = function(v) T:Create(); T:Refresh() end
