-- Spec & Trainer away from the trainer (SPEC 22.6.3): the level-up message and the Trainer line
-- on the Guide page. Nothing here buys anything; the only action is pointing the
-- Panoply Suite arrow at a trainer, and only when you click for it.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C, Skin = Panoply.Compat, Panoply.Skin
local U = ST.UI

local function names(list, n)
  local out = {}
  for i = 1, math.min(#list, n or 3) do
    local r = list[i]
    out[#out + 1] = r.name .. ((r.rank ~= "" and r.rank ~= "Passive") and (" (" .. r.rank .. ")") or "")
  end
  if #list > (n or 3) then out[#out + 1] = (#list - (n or 3)) .. " more" end
  if #out <= 1 then return out[1] or "" end
  return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
end
ST.SpellList = names

function ST.Away(seconds)
  if not seconds or seconds >= 1e8 then return nil end
  local m = math.max(1, math.floor(seconds / 60 + 0.5))
  return ("about %d min away"):format(m)
end

local function trainerWhere(t)
  if not t then return nil end
  local zone = t.spot and C.MapName and C.MapName(t.spot.map)
  local s = t.name .. (zone and (", " .. zone) or "")
  local away = ST.Away(t.seconds)
  return away and (s .. ", " .. away) or s
end

-------------------------------------------------------------------------------
-- The level-up message (our own small card: Panoply.Toast has no buttons)
-------------------------------------------------------------------------------
-- Text for the message after reaching `level`, or nil when nothing new is waiting.
function ST:ToastText(level)
  local p = self:Player()
  p.level = level or p.level
  local w = self:Waiting(p)
  if #w.list == 0 then return nil end
  local head = ("New spells at your trainer (%d) - %s"):format(#w.list, ST.Money(w.cost))
  local spend = self:Spendable(p.money)
  local t = self:NearestTrainer()
  local body
  if spend >= w.cost or not (Panoply.db and Panoply.db.trainerMoneyWarn ~= false) then
    body = ("Level %d: %s."):format(p.level, names(w.list))
    local where = trainerWhere(t)
    if where then body = body .. " Nearest trainer: " .. where .. "." end
  else
    -- what the money covers, cheapest Recommended first
    local plan = self:VerdictPlan()
    local first, sum = {}, 0
    local sorted = {}
    for _, r in ipairs(w.list) do if self:Verdict(r.name, plan) == "rec" then sorted[#sorted + 1] = r end end
    table.sort(sorted, function(a, b) return a.cost < b.cost end)
    for _, r in ipairs(sorted) do if sum + r.cost <= spend then first[#first + 1] = r; sum = sum + r.cost end end
    body = ("You have %s: %s short."):format(ST.Money(spend), ST.Money(w.cost - spend))
    if #first > 0 then body = body .. (" Learn %s first (%s)."):format(names(first), ST.Money(sum)) end
  end
  return head, body, t
end

function ST:ShowToast(level)
  if not (Panoply.db and Panoply.db.trainerToast ~= false) then return nil end
  if C.InCombat() then self.pendingToast = level or true return nil end
  local head, body, t = self:ToastText(level)
  if not head then return nil end
  local f = self.toast
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteTrainerToast", UIParent)
    f.panoplyBox = true
    f:SetFrameStrata("HIGH")
    Skin.Panel(f, 1, nil, "M")
    f:SetPoint("TOP", UIParent, "TOP", 0, -(ST.PAIR_TOP or 96))
    if f.EnableMouse then f:EnableMouse(true) end
    f:SetScript("OnUpdate", function(self, e)
      if self.IsMouseOver and self:IsMouseOver() then self.left = math.max(self.left or 0, 2) return end
      self.left = (self.left or 0) - (e or 0)
      if self.left <= 0 then self:Hide() end
    end)
    -- the next-talent card stacks under the toast; move it back up when the toast goes
    f:SetScript("OnHide", function() if ST.PlaceCard then ST:PlaceCard() end end)
    self.toast = f
  end
  local buttons = {}
  if t and Panoply.db.trainerArrowOffer ~= false then
    buttons[#buttons + 1] = { "Point the arrow there", "Sets the Panoply Suite arrow to " .. t.name .. ". Your route is not changed.",
      function() ST:PointToTrainer(); f:Hide() end }
  end
  buttons[#buttons + 1] = { "Not now", "Hides this message. The Trainer line in the main window keeps the reminder.", function() f:Hide() end }
  -- kept so the toast can narrow beside an open talent window (ST:PlaceCard, NextTalent.lua)
  f.panoplyContent, f.panoplyW, f.panoplyHeld = { head, body, buttons }, nil, nil
  if ST.SizeToast then ST:SizeToast(ST.TOAST_W or 460) else U.Toast(f, head, body, buttons, 460) end
  f.left = 10
  f:Show()
  if ST.PlaceCard then ST:PlaceCard() end
  return f
end

ST:On("PLAYER_LEVEL_UP", function(_, level)
  level = tonumber(level)
  -- the new level's spells and the talent hint; both wait for the end of a fight
  C.After(1, function()
    ST:ShowToast(level)
    if ST.LevelUpTalent then ST:LevelUpTalent(level) end
    ST:RefreshMenu()
  end)
end)
ST:On("PLAYER_REGEN_ENABLED", function()
  if ST.pendingToast then local l = ST.pendingToast ST.pendingToast = nil ST:ShowToast(l ~= true and l or nil) end
  if ST.pendingCard then ST.pendingCard = nil if ST.ShowNextCard then ST:ShowNextCard() end end
end)
ST:On("PLAYER_MONEY", function() ST:RefreshMenu() if ST.atTrainer then ST:Refresh() end end)
-- 0.7.0 on 0.6.2: LEARNED_SPELL_IN_SKILL_LINE (both clients); LEARNED_SPELL_IN_TAB is in neither API dump (0.6.1 audit)
ST:On("LEARNED_SPELL_IN_SKILL_LINE", function() ST:RefreshMenu() end)
ST:Listen("SPEC_PLAN_CHANGED", function() ST:RefreshMenu() end)
ST:Listen("SPEC_TRAINER_CHANGED", function() ST:RefreshMenu() end)

-------------------------------------------------------------------------------
-- The Trainer line in the main window (Guide page), through Menu.levelingBlocks
-------------------------------------------------------------------------------
function ST:MenuLine()
  local p = self:Player()
  local w = self:Waiting(p)
  local spend = self:Spendable(p.money)
  local line, sub
  local t = self:NearestTrainer()
  local where = trainerWhere(t)
  if #w.list > 0 then
    line = ("%d new spell%s waiting, %s. You have %s."):format(#w.list, #w.list == 1 and "" or "s", ST.Money(w.cost), ST.Money(p.money))
    local bits = {}
    if spend < w.cost then bits[#bits + 1] = ("%s short; learn the ticked ones first."):format(ST.Money(w.cost - spend)) end
    if where then bits[#bits + 1] = where .. "." end
    sub = table.concat(bits, " ")
  elseif w.nextLevel then
    line = ("Nothing new until level %d: %d spell%s, %s."):format(w.nextLevel, #w.nextList, #w.nextList == 1 and "" or "s", ST.Money(w.nextCost))
    if spend < w.nextCost then
      sub = ("You have %s: %s short. Selling the grey items in your bags helps."):format(ST.Money(spend), ST.Money(w.nextCost - spend))
    end
  else
    line = "Nothing left to learn from your class trainer."
  end
  -- the mount fund only when the next spells are covered: one money worry at a time
  local short = (#w.list > 0 and spend < w.cost) or (#w.list == 0 and w.nextLevel and spend < (w.nextCost or 0))
  local per = (not short) and self:MountSaving(p)
  if per and per > 0 then
    sub = ((sub and sub ~= "") and (sub .. " ") or "") .. ("Mount fund: put aside about %s a level for level 40."):format(ST.Money(per))
  end
  return line, sub or "", t
end

-- the pages that show the trainer's news (the Guide's Trainer line, the Class page) follow it
function ST:RefreshMenu()
  local M = Panoply.Menu
  if M and (M.current == "guide" or M.current == "class") and M.frame and M.frame:IsShown() then M:RefreshCurrent() end
end

local function menuOn() return Panoply.Modules:IsOn("spectrainer") and Panoply.db and Panoply.db.trainerMenuLine ~= false end

local block = {}
function block.build(p)
  local icon = p:CreateTexture(nil, "OVERLAY"); icon:SetSize(18, 18); Skin.SetIcon(icon, "Train")
  local label = Skin.Label(p, 11, Skin.colors.goldBright); label:SetText("TRAINER")
  local t = Skin.Ink(p, 12)
  local s = Skin.Ink(p, 11, Skin.colors.inkSoft)
  local b = Skin.Button(p, "Point the arrow", 90, 24, function() ST:PointToTrainer() end, "Point the arrow",
    "Sets the Panoply Suite arrow to your nearest class trainer. Your route is not changed.")
  Skin.FitButton(b, 90)
  p.trainer = { icon = icon, label = label, text = t, sub = s, btn = b }
end
function block.refresh(p)
  local tr = p.trainer
  if not tr then return end
  local on = menuOn()
  for _, o in pairs(tr) do if on then o:Show() else o:Hide() end end
  if not on then return end
  local line, sub, t = ST:MenuLine()
  tr.text:SetText(line); tr.sub:SetText(sub)
  if t then tr.btn:Show() else tr.btn:Hide() end
end
-- icon, TRAINER label, one line, a soft line, the arrow button on the right
function block.layout(p, y, W)
  local tr = p.trainer
  if not (tr and tr.text:IsShown()) then return y end
  local SP, TH = Skin.SP, Skin.TextHeight
  y = y - SP.m
  local tbw = tr.btn:IsShown() and tr.btn:GetWidth() or 0
  local gap = tbw > 0 and SP.m or 0
  tr.icon:ClearAllPoints(); tr.icon:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
  local lw = math.ceil(Skin.TextWidth(tr.label)) + 2; tr.label:SetWidth(lw)
  tr.label:ClearAllPoints(); tr.label:SetPoint("TOPLEFT", p, "TOPLEFT", 42, y - 3)
  local tx = 42 + lw + 8
  local tw = W - tx - 16 - tbw - gap
  tr.text:ClearAllPoints(); tr.text:SetPoint("TOPLEFT", p, "TOPLEFT", tx, y - 2); tr.text:SetWidth(tw)
  local th = TH(tr.text, tw); tr.text:SetHeight(th)
  tr.btn:ClearAllPoints(); tr.btn:SetPoint("TOPRIGHT", p, "TOPLEFT", W - 16, y + 1)
  local y2 = y - math.max(th + 2, 18) - 2
  local sw = W - 42 - 16 - tbw - gap
  tr.sub:ClearAllPoints(); tr.sub:SetPoint("TOPLEFT", p, "TOPLEFT", 42, y2); tr.sub:SetWidth(sw)
  local sh = (tr.sub:GetText() or "") ~= "" and TH(tr.sub, sw) or 0
  tr.sub:SetHeight(math.max(1, sh))
  return math.min(y2 - sh, y + 1 - (tbw > 0 and tr.btn:GetHeight() or 0))
end
if Panoply.Menu and Panoply.Menu.levelingBlocks then table.insert(Panoply.Menu.levelingBlocks, block) end
ST.menuBlock = block
