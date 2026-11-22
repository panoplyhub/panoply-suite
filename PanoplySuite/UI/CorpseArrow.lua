-- Panoply Suite 0.5.7: the corpse-run arrow. While you are a ghost a second, clearly different arrow
-- (lavender, with the game's skull raid icon and "Your corpse") points to your body with the
-- yards left; the quest arrow is paused meanwhile and comes back when you are alive again
-- (corpse, spirit healer, or a resurrection by another player). Settings > Guide window >
-- "Corpse arrow when dead".
local ADDON, Panoply = ...
local Skin, C, Nav = Panoply.Skin, Panoply.Compat, Panoply.Nav
local CA = {}
Panoply.CorpseArrow = CA

CA.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
CA.COLOR_FAR = { 0.74, 0.65, 1.0 }    -- lavender: never the quest arrow's teal/gold/green
CA.COLOR_NEAR = { 0.93, 0.89, 1.0 }
CA.HERE_YARDS = 10
CA.NEAR_YARDS = 40                     -- about where the game offers "Resurrect now"

function CA:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteCorpseArrow", UIParent)
  self.frame = f
  f:SetSize(110, 118)
  local ap = Panoply.cdb and Panoply.cdb.arrowPos
  -- the quest arrow's saved place is in the scale that arrow had (s, 100% for an older save): the same spot on screen
  if ap and ap.p then local k = ap.s or 1 f:SetPoint(ap.p, UIParent, ap.rp or ap.p, (ap.x or 0) * k, (ap.y or 0) * k) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
  if f.EnableMouse then f:EnableMouse(false) end   -- clicks go through; it is only up while you are a ghost
  -- 0.6.0 (SPEC 21.12, no glow anywhere): no soft glow behind the corpse arrow; shape and behaviour unchanged.
  local skull = f:CreateTexture(nil, "OVERLAY")
  skull:SetSize(20, 20); skull:SetPoint("TOP", f, "TOP", 0, 0)
  skull:SetTexture(CA.SKULL)
  self.skull = skull
  local tex = Skin.NavArrow(f, "ARTWORK", 52)   -- 0.6.0 arrow fix: the same redrawn arrow as the quest arrow
  tex:SetPoint("TOP", skull, "BOTTOM", 0, -2)
  self.tex = tex
  local pill = CreateFrame("Frame", nil, f)
  pill:SetSize(110, 36); pill:SetPoint("TOP", tex, "BOTTOM", 0, -2)
  local pbg = Skin.Box(pill, "S", { fill = Skin.colors.card, fillA = 0.85, line = Skin.colors.hairline })
  self.pill = pill
  self.title = Skin.Name(pill, 11, Skin.colors.heading)
  self.title:SetTextColor(CA.COLOR_FAR[1], CA.COLOR_FAR[2], CA.COLOR_FAR[3], 1)
  self.title:SetText("Your corpse")
  self.dist = Skin.Text(pill, 11)
  if self.title.SetJustifyH then self.title:SetJustifyH("CENTER") self.dist:SetJustifyH("CENTER") end
  self.elapsed = 0
  f:SetScript("OnUpdate", function(_, dt) CA:OnUpdate(dt) end)
  f:Hide()
  return f
end

-- Measured: the pill grows to fit the two lines at any font scale.
function CA:Layout()
  local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
  local w = math.max(96, math.min(220, math.max(TW(self.title), TW(self.dist)) + 2 * SP.m))
  self.title:ClearAllPoints(); self.title:SetPoint("TOP", self.pill, "TOP", 0, -SP.xs); self.title:SetWidth(w - 2 * SP.s)
  local th = TH(self.title, w - 2 * SP.s)
  self.dist:ClearAllPoints(); self.dist:SetPoint("TOP", self.title, "BOTTOM", 0, -2); self.dist:SetWidth(w - 2 * SP.s)
  local dh = TH(self.dist, w - 2 * SP.s)
  local ph = SP.xs + th + 2 + dh + SP.xs
  self.pill:SetSize(w, ph)
  self.frame:SetSize(math.max(w, 96), 20 + 2 + 52 + 2 + ph)
end

function CA:Enabled() return Panoply.db and Panoply.db.corpseArrow ~= false end
function CA:Active() return self.active and true or false end

-- PLAYER_DEAD: remember where we fell (the body is there; also survives a /reload as a ghost).
function CA:OnDeath()
  local m, x, y = C.GetPlayerPos()
  if Panoply.cdb and m then Panoply.cdb.corpse = { m = m, x = x, y = y } end
  self:Check()
end

function CA:Check()
  local ghost = C.IsGhost()
  if ghost and self:Enabled() then
    if not self.active then
      self.active = true
      self:Create()
      self.frame:Show()
      if Panoply.Arrow then Panoply.Arrow.pausedForCorpse = true; if Panoply.Arrow.frame then Panoply.Arrow:Update() end end
      Panoply:Fire("CORPSE_RUN", true)
    end
    self:Update()
  else
    if not C.IsDead() and Panoply.cdb then Panoply.cdb.corpse = nil end   -- alive again (any way)
    if self.active then
      self.active = nil
      if self.frame then self.frame:Hide() end
      if Panoply.Arrow then Panoply.Arrow.pausedForCorpse = nil; if Panoply.Arrow.frame then Panoply.Arrow:Refresh() end end
      Panoply:Fire("CORPSE_RUN", false)
    end
  end
end

-- The corpse spot: the game's answer first, then where we died.
function CA:CorpseSpot()
  local pm = C.GetPlayerPos()
  local saved = Panoply.cdb and Panoply.cdb.corpse
  local m, x, y = C.CorpsePos({ pm, saved and saved.m })
  if m then return m, x, y end
  if saved then return saved.m, saved.x, saved.y end
  return nil
end

function CA:Update()
  if not (self.active and self.frame) then return end
  local last = {}
  self.last = last
  local cm, cx, cy = self:CorpseSpot()
  local pm, px, py = C.GetPlayerPos()
  local col = CA.COLOR_FAR
  if not cm then
    self.tex:Hide()
    self.dist:SetText("Corpse location unknown")
  elseif not pm then
    self.tex:Hide()
    self.dist:SetText("Corpse in " .. (C.MapName(cm) or "another zone"))
  else
    local bearing, d = Nav.Bearing(pm, px, py, cm, cx, cy)
    last.corpse = { m = cm, x = cx, y = cy }
    if not bearing then
      -- another continent or an instance: name the zone
      self.tex:Hide()
      last.otherZone = C.MapName(cm) or "another zone"
      self.dist:SetText("Corpse in " .. last.otherZone)
    else
      if d <= CA.NEAR_YARDS then col = CA.COLOR_NEAR end
      local facing = C.Facing()
      if facing then
        Panoply.Arrow.SetRotation(self.tex, Nav.ArrowAngle(bearing, facing))
        last.angle = Nav.ArrowAngle(bearing, facing)
        self.tex:Show()
      else
        self.tex:Hide()
      end
      last.yards = d
      local zone = cm ~= pm and C.MapName(cm)
      if d <= CA.HERE_YARDS then self.dist:SetText("At your corpse")
      else self.dist:SetText(Panoply.StepText.Distance(d) .. (zone and (" - " .. zone) or "")) end
    end
  end
  self.tex:SetVertexColor(col[1], col[2], col[3], 1)
  last.color = col
  self.frame:SetAlpha(Panoply.db and Panoply.db.arrowAlpha or 1)
  self:Layout()
end

function CA:OnUpdate(dt)
  self.elapsed = (self.elapsed or 0) + (dt or 0)
  if self.elapsed < 0.1 then return end
  self.elapsed = 0
  self.updates = (self.updates or 0) + 1
  self:Update()
end

Panoply:On("PLAYER_DEAD", function() CA:OnDeath() end)
Panoply:On("PLAYER_ALIVE", function() CA:Check() end)     -- released (now a ghost) or resurrected before release
Panoply:On("PLAYER_UNGHOST", function() CA:Check() end)   -- back in the body: corpse, spirit healer
Panoply:On("PLAYER_ENTERING_WORLD", function() CA:Check() end)
Panoply:On("ZONE_CHANGED_NEW_AREA", function() if CA.active then CA:Update() end end)
Panoply.optionHooks.corpseArrow = function() CA:Check() end
