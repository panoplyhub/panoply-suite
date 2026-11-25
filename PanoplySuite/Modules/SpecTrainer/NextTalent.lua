-- Spec & Trainer: the next talent (SPEC 22.5). A small card says which talent your plan takes
-- next and why, and a thin outline marks it in the game's talent window.
--
-- Panoply Suite NEVER learns a talent: the talent learning API is not called anywhere in Panoply Suite.
-- You click the talent in the game's window yourself. The game's talent window is only looked at:
-- we hook its update function with hooksecurefunc (an after-hook that cannot taint it) and
-- anchor our own frames to its buttons; none of its functions or frames are replaced.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C, Skin = Panoply.Compat, Panoply.Skin
local U = ST.UI

-- The game's talent window: frame and button names per client (checked in Blizzard's Classic Era
-- Blizzard_TalentUI source; [VERIFY IN GAME] on a live Forever client). Era 1.15 and
-- Forever use Blizzard_TalentUI with PlayerTalentFrame, PlayerTalentFrameTalent<n> (n = the
-- talent's index in the shown tree) and PlayerTalentFrameTab<1-3>; older clients used TalentFrame.
ST.TALENT_FRAMES = { "PlayerTalentFrame", "TalentFrame" }

function ST:TalentFrame()
  for _, n in ipairs(self.TALENT_FRAMES) do
    local f = _G[n]
    if f then return f, n end
  end
  return nil
end

function ST:TalentTabShown(f, name)
  local sel
  if _G.PanelTemplates_GetSelectedTab then sel = PanelTemplates_GetSelectedTab(f) end
  return tonumber(sel or f.selectedTab or f.talentTab or (_G.PlayerTalentFrame_GetTalentTab and nil)) or 1
end

-- The button for a talent in the shown tree (by its index in that tree), or nil.
-- 0.9.9.4 review: on WoW Forever the game's talent buttons are trait nodes, and which PlayerTalentFrameTalent<n> shows which node is
-- not known (our row and column order is not the game's index), so without the game's own index for the talent no button is named and
-- no outline is drawn: no outline rather than one on the wrong talent. Classic Era: the game's index, else the talent's place in our list.
function ST:TalentButton(tal)
  local f, name = self:TalentFrame()
  if not (f and f.IsShown and f:IsShown()) then return nil end
  if self:TalentTabShown(f, name) ~= tal.tab then return nil, "other tab" end
  local live = self:LiveTalent(tal)
  local idx = live and live.index
  if not idx then
    if C.IsForever and C.IsForever() then return nil, "no index" end
    idx = tal.letter
  end
  local b = _G[name .. "Talent" .. idx]
  if b and b.IsShown and b:IsShown() then return b end
  return nil
end

function ST:Ring()
  if self.ring then return self.ring end
  -- our own frame on top of the game's button: a thin cerulean outline, no glow, no mouse
  local r = CreateFrame("Frame", "PanoplySuiteTalentHint", UIParent)
  r:SetSize(48, 48)
  r:SetFrameStrata("HIGH")
  if r.EnableMouse then r:EnableMouse(false) end
  Skin.Box(r, "S", { fill = Skin.colors.accent, fillA = 0.12, line = Skin.colors.accent, lineA = 1 })
  r:Hide()
  self.ring = r
  local d = CreateFrame("Frame", "PanoplySuiteTalentTabDot", UIParent)
  d:SetSize(10, 10); d:SetFrameStrata("HIGH")
  local t = d:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(d); t:SetTexture(Skin.TEX.CircleMask)
  local c = Skin.colors.accent
  t:SetVertexColor(c[1], c[2], c[3], 1)
  d:Hide()
  self.tabDot = d
  return r
end

-- After the game's talent window updates: put the outline on the next talent, or a dot on the
-- tab that holds it.
function ST:UpdateOutline()
  local ring = self:Ring()
  ring:Hide(); self.tabDot:Hide()
  if not (Panoply.Modules:IsOn("spectrainer") and Panoply.db and Panoply.db.specOutline ~= false) then return end
  if self:UnspentPoints() <= 0 then return end
  local n = self:Next()
  if not n then return end
  local b, why = self:TalentButton(n.tal)
  if b then
    ring:ClearAllPoints(); ring:SetPoint("CENTER", b, "CENTER", 0, 0)
    local w = (b.GetWidth and b:GetWidth() or 37) + 10
    ring:SetSize(w, w)
    ring:Show()
  elseif why == "other tab" then
    local f, name = self:TalentFrame()
    local tab = _G[name .. "Tab" .. n.tal.tab]
    if tab then self.tabDot:ClearAllPoints(); self.tabDot:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -6, -6); self.tabDot:Show() end
  end
  return n
end

-- Hook the game's talent window once it is loaded (Blizzard_TalentUI loads on demand).
function ST:HookTalentUI()
  if self.talentHooked then return true end
  local f = self:TalentFrame()
  if not f then return false end
  self.talentHooked = true
  for _, fn in ipairs({ "PlayerTalentFrame_Update", "TalentFrame_Update" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function() ST:UpdateOutline() ST:PlaceCard() end) end
  end
  if f.HookScript then
    f:HookScript("OnShow", function() ST:UpdateOutline() ST:PlaceCard() end)
    f:HookScript("OnHide", function() if ST.ring then ST.ring:Hide() ST.tabDot:Hide() end ST:PlaceCard() end)
  end
  return true
end

ST:On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_TalentUI" then ST:HookTalentUI() end
end)
ST:On("PLAYER_LOGIN", function() ST:HookTalentUI() end)
for _, ev in ipairs(ST.TALENT_EVENTS) do
  ST:On(ev, function()
    ST:UpdateOutline()
    if ST.card and (ST.card:IsShown() or ST.card.panoplyHeld) then ST:ShowNextCard(true) end
  end)
end

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------
function ST:CardText(n, plan)
  local T = self:Trees(plan.class)
  local lines = {
    head = "Next talent",
    -- (0.9.9.4: "Level 12, from your Survival leveling build (Icy Veins)")
    sub = ("Level %d, from %s"):format(n.level, self:BuildWords() or ("your plan \"" .. (plan.name or "your plan") .. "\"")),
    name = n.tal.name,
    rank = ("Point %d of %d, %s, row %d"):format(n.rank, n.tal.ranks, T.tabs[n.tal.tab].name, n.tal.tier + 1),
    why = n.why or "This is the next point in your plan.",
    note = "Outlined in your talent window. Click it there to learn it: Panoply Suite never spends points for you.",
  }
  if n.offPlan and #n.offPlan > 0 then
    lines.off = ("You took %s instead; the plan moves on from your current talents."):format(ST.SpellList({ { name = n.offPlan[1], rank = "" } }))
  end
  return lines
end

-- Places the level-up toast and the next-talent card (SPEC 22.5: one stacked pair).
-- Talent window closed: the toast is at the top, the card right under it; when the two do not fit
-- above the bottom of the screen (big text, small window) they sit side by side.
-- Talent window open (0.7.0 fix, "the level-up message may overlap the talent window on small
-- screens"): neither ever covers it. Both go into the free column beside the window (the wider side),
-- toast on top and card under it, or side by side when that fits better; the toast narrows to the
-- column (down to TOAST_MIN_W). When there is still no room the toast waits, hidden, and comes back
-- with its time left as soon as the talent window closes. The card has priority: it is about talents.
ST.PAIR_TOP, ST.PAIR_GAP = 96, 10
ST.TOAST_W, ST.TOAST_MIN_W, ST.EDGE = 460, 300, 8

-- A frame's box in UIParent units (left, right, bottom, top), or nil when the client cannot say.
local function num(v) return type(v) == "number" and v == v and v end
function ST.BoxOf(f)
  if not (f and f.GetLeft) then return nil end
  local ok, l, r, b, t = pcall(function() return f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop() end)
  l, r, b, t = ok and num(l), ok and num(r), ok and num(b), ok and num(t)
  if not (l and r and b and t) then return nil end
  local k = 1
  local okS, fs, us = pcall(function() return f:GetEffectiveScale(), UIParent:GetEffectiveScale() end)
  fs, us = okS and num(fs), okS and num(us)
  if fs and us and us > 0 then k = fs / us end
  return l * k, r * k, b * k, t * k
end

-- Re-lays the toast's text for a new width (U.Toast keeps the content we gave it).
function ST:SizeToast(w)
  local t = self.toast
  if not (t and t.panoplyContent) then return end
  w = math.floor(w)
  if t.panoplyW == w then return end
  t.panoplyW = w
  local c = t.panoplyContent
  U.Toast(t, c[1], c[2], c[3], w)
end

-- Our frames are placed by their top-left corner, in UIParent units measured from the top-left of the
-- screen; `boxes` keeps each placed box (x, top, w, h) for the final no-overlap check.
local function at(f, x, top, boxes)
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -top)
  if boxes then boxes[f] = { x, top, f:GetWidth() or 0, f:GetHeight() or 0 } end
end
local function hits(a, b)   -- two boxes { x, top, w, h } share any pixel (touching edges is fine)
  return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end
ST.BoxesHit = hits

function ST:PlaceCard()
  if self.placing then return end
  self.placing = true
  local ok, err = pcall(self.PlaceCardNow, self)
  self.placing = false
  if not ok then error(err, 0) end
end

-- hide one of our two frames while the talent window needs the room; it comes back when it closes
local function hold(f) if f and f:IsShown() then f.panoplyHeld = true; f:Hide() end end
local function unhold(f) if f and f.panoplyHeld then f.panoplyHeld = nil; f:Show() return true end end

function ST:PlaceCardNow()
  local f, toast = self.card, self.toast
  local cardOn = f and (f:IsShown() or f.panoplyHeld)
  local toastOn = toast and ((toast.IsShown and toast:IsShown()) or toast.panoplyHeld)
  local sw = UIParent.GetWidth and UIParent:GetWidth() or 1024
  local sh = UIParent.GetHeight and UIParent:GetHeight() or 768
  local G, E = self.PAIR_GAP, self.EDGE
  local tf = self:TalentFrame()
  local tl, tr, tb, tt
  if tf and tf.IsShown and tf:IsShown() then tl, tr, tb, tt = ST.BoxOf(tf) end

  if not tl then
    -- talent window closed: the stacked pair in the middle (anything held comes back now)
    if unhold(toast) then toast.left = math.max(toast.left or 0, 6) end
    unhold(f)
    if toastOn then self:SizeToast(self.TOAST_W); toast:ClearAllPoints(); toast:SetPoint("TOP", UIParent, "TOP", 0, -self.PAIR_TOP) end
    if not cardOn then return end
    f:ClearAllPoints()
    if toastOn then
      local need = self.PAIR_TOP + (toast:GetHeight() or 0) + G + (f:GetHeight() or 0) + E
      if need <= sh then
        f:SetPoint("TOP", toast, "BOTTOM", 0, -G)
      else
        toast:ClearAllPoints(); toast:SetPoint("TOPRIGHT", UIParent, "TOP", -G / 2, -self.PAIR_TOP)
        f:SetPoint("TOPLEFT", toast, "TOPRIGHT", G, 0)
      end
    else f:SetPoint("TOP", UIParent, "TOP", 0, -self.PAIR_TOP) end
    return
  end

  -- talent window open: nothing of ours may cover it
  local win = { tl, sh - tt, tr - tl, tt - tb }          -- the talent window as { x, top, w, h }
  local boxes = {}
  local leftW, rightW = tl - G - E, sw - tr - G - E
  local x0, colW
  if rightW >= leftW then x0, colW = tr + G, rightW else x0, colW = E, leftW end
  local top = math.max(E, math.min(self.PAIR_TOP, win[2]))
  if toastOn then unhold(toast) end
  if cardOn then unhold(f) end
  local cw, ch = 0, 0
  if cardOn then cw, ch = f:GetWidth() or 0, f:GetHeight() or 0 end

  -- 1. the card: in the column beside the window; else under or over it; else it waits
  local cardInColumn = false
  if cardOn then
    local cx = math.max(E, math.min(tl, sw - cw - E))
    if cw <= colW and math.max(E, win[2]) + ch + E <= sh then
      cardInColumn = true
    elseif cw <= sw - 2 * E and win[2] + win[4] + G + ch + E <= sh then
      at(f, cx, win[2] + win[4] + G, boxes)
    elseif cw <= sw - 2 * E and win[2] - G - ch >= E then
      at(f, cx, win[2] - G - ch, boxes)
    else
      hold(f); cardOn = false; cw, ch = 0, 0
    end
  end

  -- 2. the toast: in the same column, full width or narrowed, stacked with the card or beside it
  local placed = false
  if toastOn then
    local tw = math.min(self.TOAST_W, colW)
    if tw >= self.TOAST_MIN_W then
      self:SizeToast(tw)
      local th = toast:GetHeight() or 0
      if cardInColumn then
        if top + th + G + ch + E <= sh then
          at(toast, x0, top, boxes); at(f, x0, top + th + G, boxes); placed = true
        else
          local sideW = math.min(self.TOAST_W, colW - G - cw)
          if sideW >= self.TOAST_MIN_W then
            self:SizeToast(sideW); th = toast:GetHeight() or 0
            if top + math.max(th, ch) + E <= sh then
              at(f, x0, top, boxes); at(toast, x0 + cw + G, top, boxes); placed = true
            end
          end
        end
      elseif top + th + E <= sh then
        at(toast, x0, top, boxes); placed = true
      end
    end
  end
  if cardInColumn and not boxes[f] then at(f, x0, math.max(E, math.min(win[2], sh - ch - E)), boxes) end

  -- 3. the final check: the toast never covers the talent window or the card and stays on screen;
  -- if it would, it waits (hidden, with its time left) until the talent window closes
  if toastOn then
    local b = boxes[toast]
    local bad = not placed or not b or hits(b, win) or (boxes[f] and hits(b, boxes[f]))
      or b[1] < 0 or b[2] < 0 or b[1] + b[3] > sw or b[2] + b[4] > sh
    if bad then self:SizeToast(self.TOAST_W); hold(toast) end
  end
  if cardOn and boxes[f] and hits(boxes[f], win) then hold(f) end
end

-- Show the card (on level up, or when asked). quiet: only refresh an open card.
function ST:ShowNextCard(quiet)
  if not (Panoply.db and Panoply.db.specNextCard ~= false) then return nil end
  if C.InCombat() then self.pendingCard = true return nil end
  local plan = self:Tracked()
  local n = plan and self:Next(plan)
  if not n or self:UnspentPoints() <= 0 then if self.card then self.card.panoplyHeld = nil; self.card:Hide() end return nil end
  local L = self:CardText(n, plan)
  if L.off then
    local k = table.concat(n.offPlan, ",")
    if self.offNoticed ~= k then self.offNoticed = k; Panoply:Print(L.off) end
  end
  local f = self.card
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteTalentNext", UIParent)
    f.panoplyBox = true
    f:SetFrameStrata("HIGH")
    Skin.Panel(f, 0.97, true, "M")
    -- the toast moves back to the middle when the card goes
    f:SetScript("OnHide", function() ST:PlaceCard() end)
    self.card = f
  end
  local width = 380
  f:SetSize(width, 100)
  local c = U.Fresh(f, "panoplyBody", f)
  local x, w = 16, width - 32
  local crest = c:CreateTexture(nil, "ARTWORK"); crest:SetSize(30, 30); Skin.Logo(crest); crest:SetPoint("TOPLEFT", c, "TOPLEFT", x, -13)
  local h = Skin.Heading(c, 15, L.head); h:SetWidth(w - 40); h:SetPoint("TOPLEFT", c, "TOPLEFT", x + 40, -14)
  local y = -14 - Skin.TextHeight(h, w - 40) - 2
  local s = Skin.Ink(c, 11, Skin.colors.inkSoft); s:SetText(L.sub); s:SetWidth(w - 40); s:SetPoint("TOPLEFT", c, "TOPLEFT", x + 40, y)
  y = math.min(y - Skin.TextHeight(s, w - 40), -46) - Skin.SP.m
  local live = self:LiveTalent(n.tal)
  local ic = c:CreateTexture(nil, "ARTWORK"); ic:SetSize(36, 36); ic:SetTexture((live and live.icon) or n.tal.icon); ic:SetPoint("TOPLEFT", c, "TOPLEFT", x, y)
  local nm = Skin.Name(c, 14, Skin.colors.text); nm:SetText((live and live.name) or L.name); nm:SetWidth(w - 48); nm:SetPoint("TOPLEFT", c, "TOPLEFT", x + 48, y)
  local yy = y - Skin.TextHeight(nm, w - 48) - 2
  local rk = Skin.Ink(c, 11, Skin.colors.goldBright); rk:SetText(L.rank); rk:SetWidth(w - 48)
  rk:SetPoint("TOPLEFT", c, "TOPLEFT", x + 48, yy)
  yy = yy - Skin.TextHeight(rk, w - 48)
  y = math.min(yy, y - 36) - Skin.SP.s
  y = U.Block(c, x, y, w, 12, Skin.colors.ink, L.why) - Skin.SP.s
  if L.off then y = U.Block(c, x, y, w, 11, Skin.colors.warn, L.off) - Skin.SP.s end
  y = U.Block(c, x, y, w, 11, Skin.colors.inkSoft, L.note) - Skin.SP.m
  local list = { Skin.Button(c, "Open Talents", 90, 26, function() ST:OpenPlanner() end, "Open Talents", "The Class page's Talents tab: the whole plan, to see or change."),
                 Skin.Button(c, "Not now", 90, 26, function() f:Hide() end, "Not now", "Hides the hint until your next level.") }
  f.buttons = list
  local bh = Skin.FlowButtons(c, list, x, y, w, Skin.SP.s, 80)
  f:SetHeight(-(y - bh) + Skin.SP.l)
  f.next = n
  f.panoplyHeld = nil
  f:Show()
  self:PlaceCard()
  self:UpdateOutline()
  return f, n
end

function ST:LevelUpTalent(level)
  if (level or 0) < self.FIRST_LEVEL then return end
  self:ShowNextCard()
end
