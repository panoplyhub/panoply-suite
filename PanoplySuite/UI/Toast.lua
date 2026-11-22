-- Panoply Suite toast: a gold-edged banner that slides in at the top ("Done! Next: ...").
local ADDON, Panoply = ...
local Toast = {}
Panoply.Toast = Toast
local Skin, C = Panoply.Skin, Panoply.Compat

local HOLD = 3.0

function Toast:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteToast", UIParent)
  self.frame = f
  f:SetSize(420, 104)
  f.panoplyBox = true   -- 0.5.9.1: the layout checker keeps the text inside the banner
  f:SetPoint("TOP", UIParent, "TOP", 0, -96)
  f:SetFrameStrata("HIGH")
  -- skin v3: slate panel, brass trim and caps; no glow behind the crest
  Skin.Panel(f, 1, nil, "M")
  local crest = f:CreateTexture(nil, "ARTWORK"); crest:SetSize(52, 52); Skin.Logo(crest)
  crest:SetPoint("CENTER", f, "LEFT", 46, 0)
  self.head = Skin.Heading(f, 16, "Step complete!")
  self.head:SetPoint("TOPLEFT", f, "TOPLEFT", 92, -28)
  -- 0.9.5 phase 4G: the heading wraps in the banner's text column like the body (a long one, "Panoply Suite: Mining, Blacksmithing and
  -- Cooking detected, plans ready.", ran out of the banner; Display already measured it at this width)
  self.head:SetWidth(300)
  if self.head.SetWordWrap then self.head:SetWordWrap(true) end
  self.body = Skin.Text(f, 12)
  self.body:SetPoint("TOPLEFT", self.head, "BOTTOMLEFT", 0, -4)
  self.body:SetWidth(300)
  f:EnableMouse(true)
  f:SetScript("OnMouseUp", function() Toast:Hide() end)
  Skin.Tooltip(f, "Step complete", "Click to dismiss.")
  -- fade/slide in, then fade out
  if f.CreateAnimationGroup then
    local ok, ag = pcall(f.CreateAnimationGroup, f)
    if ok and ag then
      local a = ag:CreateAnimation("Alpha"); if a and a.SetFromAlpha then a:SetFromAlpha(0); a:SetToAlpha(1) end; if a then a:SetDuration(0.25) end
      local t = ag:CreateAnimation("Translation"); if t then t:SetOffset(0, -16); t:SetDuration(0.25) end
      self.inAnim = ag
      local ok2, out = pcall(f.CreateAnimationGroup, f)
      if ok2 and out then
        local fa = out:CreateAnimation("Alpha"); if fa and fa.SetFromAlpha then fa:SetFromAlpha(1); fa:SetToAlpha(0) end
        if fa then fa:SetDuration(0.6) end
        out:SetScript("OnFinished", function() f:Hide() end)
        self.outAnim = out
      end
    end
  end
  f:Hide()
  return f
end

function Toast:Show(head, body)
  if Panoply.db and Panoply.db.toasts == false then return end
  return self:Display(head, body)
end

-- the banner itself, whatever "Step complete banners" says (0.9.5: Panoply.Kit.Toast has its own setting and shows through here)
function Toast:Display(head, body)
  self:Create()
  self.head:SetText(head or "Step complete!")
  self.body:SetText(body or "")
  -- 0.5.9.1: a long step (two or three lines) makes the banner taller instead of running out of it
  local th = Skin.TextHeight(self.head, 300)
  local bh = (body and body ~= "") and Skin.TextHeight(self.body, 300) or 0
  self.frame:SetHeight(math.max(104, math.ceil(28 + th + 4 + bh + 18)))
  self.shownAt = C.GetTime()
  self.frame:SetAlpha(1)
  self.frame:Show()
  if self.inAnim then self.inAnim:Stop(); self.inAnim:Play() end
  local token = {}
  self.token = token
  C.After(HOLD, function()
    if Toast.token ~= token then return end
    if Toast.outAnim then Toast.outAnim:Play() else Toast:Hide() end
  end)
end

function Toast:Hide() if self.frame then self.frame:Hide() end end

-- Show "Done! Next: ..." when the guide moves on by itself.
Panoply:Listen("STEP_CHANGED", function(_, reason)
  if reason ~= "auto" then return end
  local nextStep = Panoply.Engine:Current()
  Toast:Show("Step complete!", Panoply.StepText.Toast(nextStep))
end)
Panoply:Listen("PLAN_FINISHED", function()
  if Toast.finishedFor == Panoply.Engine.steps then return end
  Toast.finishedFor = Panoply.Engine.steps
  local auto = Panoply.db and Panoply.db.autoExtendPlan and Panoply.QuestData:Available()
  -- Nov 11 2026 ("turn planner off."): what comes next is the next written guide, not a plan
  if not (Panoply.Planner and Panoply.Planner:BuildsLevelingRoute()) then
    Toast:Show("Route complete!", auto and "Going on to the next written guide..." or "Click Build my route for the next written guide.")
    return
  end
  Toast:Show("Route complete!", auto and "Planning the next few levels for you..." or "Click Build my route to plan the next stretch.")
end)

-- Profession steps: "Done! Next: Buy 20 x Coarse Thread ..."
Panoply:Listen("STEP_DONE", function(kind, step)
  if kind ~= "prof" or not step then return end
  local G = Panoply.ProfGuide
  local nxt = G and G:First()
  Toast:Show((step.prof or "Profession") .. " step done!", nxt and ("Next: " .. Panoply.StepText.Headline(nxt)) or "Back to your route.")
end)

-------------------------------------------------------------------------------
-- 0.5.6: the welcome card after an update: "Panoply Suite updated" with Setup / Tour / Not now.
-- It stays until you pick one (no timer), and is shown once per account per version.
-------------------------------------------------------------------------------
function Toast:CreateWelcome()
  if self.welcome then return self.welcome end
  local SP = Skin.SP
  local f = CreateFrame("Frame", "PanoplySuiteWelcome", UIParent)
  self.welcome = f
  f:SetSize(420, 120)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Skin.Panel(f, 1, nil, "M")
  f.crest = f:CreateTexture(nil, "ARTWORK"); f.crest:SetSize(44, 44); Skin.Logo(f.crest)
  f.crest:SetPoint("CENTER", f, "TOPLEFT", 44, -46)
  f.head = Skin.Heading(f, 16, "Panoply Suite updated")
  f.body = Skin.Text(f, 12)
  f.body:SetText("Run setup again or take the tour.")
  local function close() f:Hide() end
  f.setup = Skin.Button(f, "Setup", 80, 26, function() close() Panoply.Wizard:Start() end, "Run setup",
    "Go through the short setup questions again: settings, how much you have played, class plan, group quests, solo or partner. Nothing changes until you press Start guiding.")
  f.tour = Skin.Button(f, "Tour", 80, 26, function() close() Panoply.Tour:Start() end, "Take the tour",
    "A short walk through every part of Panoply Suite. Replay it any time with /panoply tour.")
  f.later = Skin.Button(f, "Not now", 80, 26, close, "Not now", "Hide this. The Help tab in /panoply has both any time.")
  f.buttons = { f.setup, f.tour, f.later }
  function f:Layout()
    local W = self:GetWidth()
    local x, tw = 88, W - 88 - 18
    local y = -18
    self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", self, "TOPLEFT", x, y); self.head:SetWidth(tw)
    y = y - Skin.TextHeight(self.head, tw) - SP.xs
    self.body:ClearAllPoints(); self.body:SetPoint("TOPLEFT", self, "TOPLEFT", x, y); self.body:SetWidth(tw)
    y = y - Skin.TextHeight(self.body, tw) - SP.m
    local bh = Skin.FlowButtons(self, self.buttons, x, y, tw, SP.s, 64)
    y = y - bh - SP.l
    self:SetHeight(math.max(96, -y))
  end
  f:Hide()
  return f
end

function Toast:ShowWelcome()
  local f = self:CreateWelcome()
  f:Layout()
  f:Show()
  return f
end
