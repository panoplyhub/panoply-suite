-- Panoply Suite guide window: the one window you follow while playing.
-- Step card (headline, why it matters, live progress, arrow + distance), waiting banner, the partner line and partner card (0.9.7),
-- "What now?" and "Turn on quest data" states, up-next list, level bar and clear footer buttons.
local ADDON, Panoply = ...
local UI = {}
Panoply.UI = UI
local Skin, C = Panoply.Skin, Panoply.Compat

local WIDTH = 360                    -- default width; the window can be resized (MIN_W..MAX_W)
local MIN_W, MAX_W, MIN_H, MAX_H = 300, 560, 160, 900
local CARD_INSET = 12
local MAX_PROGRESS = 6
local MAX_UPCOMING = 4               -- "Steps shown" 1..5 = the current step + up to 4 upcoming
UI.MIN_W, UI.MAX_W, UI.MIN_H, UI.MAX_H = MIN_W, MAX_W, MIN_H, MAX_H
local SWITCH_H = 24                 -- the Leveling | Professions | Both row under the header
local CARD_TOP = -44 - SWITCH_H - 4

-- Segmented "Leveling | Professions | Both" switch plus a cycle button for the detected
-- professions. 0.9.5 phase 4K: the guide window uses the Follows control instead (UI/GuideParts.lua); this stays for the pages that
-- still draw it.
function UI.GuideSwitch(parent, compact)
  local G = Panoply.ProfGuide
  local sw = { tabs = {} }
  local widths = compact and { leveling = 74, professions = 90, both = 50 } or { leveling = 96, professions = 112, both = 70 }
  local tips = {
    leveling = "Follow your levelling route. Your profession steps wait in the tracker and keep their place.",
    professions = "Follow your profession plan step by step. Your route waits on its current step until you switch back.",
    both = "Your route, with profession steps added when the place is close by.",
  }
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(1, SWITCH_H)
  sw.frame = frame
  local x = 0
  for _, key in ipairs(G.GUIDES) do
    local t = Skin.Tab(frame, G.GUIDE_LABELS[key], widths[key], function()
      G:SetActive(key)
      if key == "professions" and #G:Chosen() == 0 then
        Panoply:Print("No profession with a plan found on this character yet. Learn one at a trainer and Panoply Suite picks it up by itself.")
      end
    end, G.GUIDE_LABELS[key] .. " guide", tips[key])
    t:SetHeight(SWITCH_H - 2)
    if t.label.SetFont then Skin.Font(t.label, compact and 11 or 12) end
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
    t.key = key
    x = x + widths[key] + 2
    sw.tabs[key] = t
  end
  sw.prof = Skin.Button(frame, "Profession", compact and 104 or 130, SWITCH_H - 4, function()
    if G:Active() == "leveling" then G:SetActive("professions") return end
    G:CycleProfession()
  end, "Which profession", "Click to switch to the next profession Panoply Suite found on this character. Each one keeps its own step.")
  sw.prof:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 6, -1)
  sw.width = x + 6 + (compact and 104 or 130)
  frame:SetWidth(sw.width)
  -- 0.5.5: tabs sized to their labels; the profession button drops to a second row when the
  -- three tabs and it do not fit in maxW. Returns the height the switch takes.
  function sw:Layout(maxW)
    local cx = 0
    for _, key in ipairs(G.GUIDES) do
      local t = self.tabs[key]
      local w = math.max(compact and 44 or 60, t:NeedWidth() - (compact and 8 or 0))
      t:SetWidth(w)
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", frame, "TOPLEFT", cx, 0)
      cx = cx + w + 3
    end
    local tabsW = cx - 3
    local h = SWITCH_H
    -- 0.6.0: with no profession on this character the button is hidden (no orphaned pill)
    if self.prof.panoplyNone then
      self.prof:Hide()
      self.width = tabsW
      frame:SetWidth(self.width); frame:SetHeight(h)
      self.height = h
      return h, self.width
    end
    self.prof:Show()
    local pw = Skin.FitButton(self.prof, compact and 90 or 110, maxW and math.max(90, maxW) or nil)
    self.prof:ClearAllPoints()
    if maxW and tabsW + 8 + pw > maxW then
      self.prof:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(SWITCH_H + 4))
      h = SWITCH_H + 4 + self.prof:GetHeight()
      self.width = math.max(tabsW, pw)
    else
      self.prof:SetPoint("TOPLEFT", frame, "TOPLEFT", tabsW + 8, -1)
      self.width = tabsW + 8 + pw
    end
    frame:SetWidth(self.width); frame:SetHeight(h)
    self.height = h
    return h, self.width
  end
  function sw:Refresh()
    local a = G:Active()
    for key, t in pairs(self.tabs) do t:SetActive(key == a) end
    local list = G:Chosen()
    local cur = G:Tracked()
    if #list == 0 then
      self.prof.panoplyNone = true
      self.prof.label:SetText("No professions")
      self.prof.tipBody = "Panoply Suite reads your professions from your skills. Learn one at a trainer and its plan appears here."
      self.prof:SetEnabledLook(false)
    else
      self.prof.panoplyNone = nil
      self.prof.label:SetText((cur or list[1]) .. (#list > 1 and "  >" or ""))
      self.prof.tipBody = #list > 1 and ("Click for the next one: " .. table.concat(list, ", ") .. ". Each keeps its own step.")
        or ("The profession guide follows " .. (cur or list[1]) .. ".")
      self.prof:SetEnabledLook(a ~= "leveling")
    end
    self.active, self.profName = a, (#list > 0 and (cur or list[1]) or nil)
    self:Layout(self.maxW)
  end
  for _, ev in ipairs({ "OPTION_CHANGED", "GUIDE_SWITCHED", "PROF_UPDATED", "PROFS_DETECTED" }) do
    Panoply:Listen(ev, function() sw:Refresh() end)
  end
  sw:Refresh()
  return sw
end

-- Icon for a step: 0.9.5 phase 4K (spec 05 section 4.4): one icon per step type, the same everywhere a step shows (the guide window,
-- the Guide page, Home, the tracker, the trip panel, the report window). The type is Panoply.StepText.Type (Engine/StepText.lua).
function UI.StepIconName(step)
  return Panoply.StepText.TypeIcon(step)
end

-------------------------------------------------------------------------------
-- 0.9.7 (WoW Forever only): levelling with a partner, in this window. Everything it draws comes from Engine/PanoplyGuideParty.lua
-- (PanoplyGuideParty:Enabled, :PartnerLine, :Card, :Waiting) and, through its card, Engine/PartnerHold.lua; nothing is worked out here.
--   the partner line   one line about the partner above the step card, with "Sync to my step" beside it
--   the partner card   the sync question, the class-quest hold or the help-your-partner step, with its buttons
--   the waiting line   "Waiting for <name> before handing in <quest>" under the step card
-- The card PanoplyGuideParty:Card() gives (a table; every field but title may be left out):
--   kind    = "sync" | "wait" | "hold" | "help" | "ahead"   (picks the small line over the title when kicker is left out)
--   kicker  = the small line over the title
--   title   = the card's headline                 ("Partner asks you to sync to their guide.")
--   body    = the words under it                  ("Their step: Kill 8 Kobold Vermin")
--   lines   = up to UI.PARTNER_LINES more lines   (what the partner still needs)
--   buttons = up to UI.PARTNER_BUTTONS of { label =, tip =, fn = function(card) end } or { label =, tip =, action = "Accept" }
--             (action: the name of a PanoplyGuideParty or PartnerHold call: Accept, Decline, GoOn, Help, StopHelp, RequestSync, Release)
-- Its rows are built with the window (UI:Create, at login), never when a card arrives. In a fight nothing of it appears or goes: what
-- changed is drawn when the fight ends.
-------------------------------------------------------------------------------
UI.PARTNER_LINES = 4
UI.PARTNER_BUTTONS = 3
UI.PARTNER_KICKER = { sync = "Sync", wait = "Waiting", hold = "Hold on", help = "Help your partner", ahead = "Hold on" }
UI.PARTNER_KICKER_OTHER = "Level together"
UI.PARTNER_SYNC = "Sync to my step"
UI.PARTNER_SYNC_TIP = "Asks your partner to come to the step you are on. They choose; nobody is moved."
UI.WAITING_HANDIN = "Waiting for %s before handing in %s."
-- the one line the window shows when the guide engine cannot run on WoW Forever (no backup guide runs there): Core/Init.lua's words
UI.NO_ENGINE = Panoply.GUIDE_UNAVAILABLE_TITLE or "Guide not available"

local function inFight()
  return (C.InCombat and C.InCombat()) or (_G.InCombatLockdown and InCombatLockdown()) or false
end

-- The partner line (and whether "Sync to my step" goes beside it) and the partner card to draw now, or nil for each.
function UI:PartnerParts()
  local PP = Panoply.PanoplyGuideParty
  local line, canSync, card
  if PP and PP.Enabled and PP:Enabled() and not Panoply:PlayAlong() then
    if PP.PartnerLine then line, canSync = PP:PartnerLine() end
    if PP.Card then card = PP:Card() end
  end
  if type(line) ~= "string" or line == "" then line = nil end
  if type(card) ~= "table" or type(card.title) ~= "string" or card.title == "" then card = nil end
  canSync = line ~= nil and canSync ~= false and PP ~= nil and type(PP.RequestSync) == "function"
  if inFight() then
    -- in a fight nothing new shows and nothing shown goes (PLAYER_REGEN_ENABLED draws what changed)
    local was = self.partnerDrawn or {}
    if (line ~= nil) ~= (was.line ~= nil) or (card ~= nil) ~= (was.card ~= nil) then self.partnerQueued = true end
    if was.line == nil then line = nil elseif line == nil then line, canSync = was.line, was.canSync end
    if was.card == nil then card = nil elseif card == nil then card = was.card end
  else
    self.partnerQueued = nil
  end
  self.partnerDrawn = { line = line, canSync = canSync, card = card }
  return line, canSync, card
end

-- the card's buttons, as a list (a card may also give them as a, b, c, like the guide's own questions)
local function partnerButtons(card)
  local list = type(card.buttons) == "table" and card.buttons or { card.a, card.b, card.c }
  local out = {}
  for _, b in ipairs(list) do
    if #out < UI.PARTNER_BUTTONS and type(b) == "table" and type(b.label) == "string" and b.label ~= "" then out[#out + 1] = b end
  end
  return out
end
UI.PartnerButtons = partnerButtons

-- A click on the card's button i: the card's own function, or the PanoplyGuideParty / PartnerHold call it names.
function UI:PartnerButton(i)
  local card = self.partnerDrawn and self.partnerDrawn.card
  local b = card and partnerButtons(card)[i]
  if not b then return false end
  local PP, PH = Panoply.PanoplyGuideParty, Panoply.PartnerHold
  if type(b.fn) == "function" then b.fn(card)
  elseif type(b.action) == "string" and PP and type(PP[b.action]) == "function" then PP[b.action](PP)
  elseif type(b.action) == "string" and PH and type(PH[b.action]) == "function" then PH[b.action](PH)
  else return false end
  self:Refresh()
  return true
end

-- "Sync to my step" beside the partner line
function UI:PartnerSync()
  local PP = Panoply.PanoplyGuideParty
  if not (PP and type(PP.RequestSync) == "function") then return false end
  local sent = PP:RequestSync()
  self:Refresh()
  return sent and true or false
end

-- The waiting line: a quest this step hands in that the partner still needs -> the words, or nil
function UI:PartnerWaiting(step)
  local PP = Panoply.PanoplyGuideParty
  if not (step and PP and PP.Enabled and PP.Waiting and PP:Enabled()) then return nil end
  for _, g in ipairs(step.goals or {}) do
    if g.type == "turnin" and type(g.questID) == "number" and g.status ~= "done" and g.status ~= "hidden" then
      local waits, who = PP:Waiting(g.questID)
      if waits then
        local name
        for _, q in ipairs(Panoply.StepText.Quests(step)) do if q.id == g.questID then name = q.name end end
        -- who: a name, or the list of names PanoplyGuideParty:Waiting gives
        if type(who) == "table" then who = #who > 0 and PP.NameList and PP.NameList(who) or nil end
        return UI.WAITING_HANDIN:format(type(who) == "string" and who ~= "" and who or "your partner", name and ("'" .. name .. "'") or "this quest")
      end
    end
  end
  return nil
end

-- True when the guide engine cannot run on WoW Forever. Engine/PanoplyGuideEngine.lua says so (PanoplyGuideEngine:Unavailable); without
-- that call: the engine is not there and nothing else builds a route.
function UI:NoEngine()
  if C.Flavor() ~= "forever" then return false end
  local PE = Panoply.PanoplyGuideEngine
  if PE and type(PE.Unavailable) == "function" then return PE:Unavailable() and true or false, true end
  if PE and PE:Present() then return false end
  local P = Panoply.Planner
  return not (P and P.BuildsLevelingRoute and P:BuildsLevelingRoute())
end

function UI:Width()
  local ws = Panoply.cdb and Panoply.cdb.windowSize
  local w = ws and tonumber(ws.w) or WIDTH
  return math.max(MIN_W, math.min(MAX_W, math.floor(w + 0.5)))
end
function UI:UserHeight()
  local ws = Panoply.cdb and Panoply.cdb.windowSize
  local h = ws and tonumber(ws.h)
  return h and math.max(MIN_H, math.min(MAX_H, h)) or nil
end
-- Size by hand (also used by the grip and tests): width reflows the text, height is a minimum.
function UI:SetUserSize(w, h)
  if not Panoply.cdb then return end
  Panoply.cdb.windowSize = { w = math.max(MIN_W, math.min(MAX_W, w or WIDTH)), h = h and math.max(MIN_H, math.min(MAX_H, h)) or nil }
  if self.frame then self.frame:SetWidth(Panoply.cdb.windowSize.w) end
  self:Refresh()
end
function UI:ResetSize() if Panoply.cdb then Panoply.cdb.windowSize = nil end self.scrollY = 0 self:Refresh() end

-- The parts of the window that scroll when it is shorter than what it shows (UI:Create puts them in the clipping frame)
UI.SCROLL_STEP = 36
UI.FIXED_LEVEL = 20          -- frame levels the header and footer buttons sit above the window (the scrolling body is under them)
UI.BODY_MIN = 56             -- at least this much of the scrolling body shows, however short the window is made
function UI:BodyParts()
  local out = { self.partnerRow, self.partnerCard, self.card, self.waitBanner, self.tripLine, self.paceText, self.profLine, self.profSub, self.profGo, self.profLater, self.profMore }
  for _, key in ipairs(UI.SECTIONS) do out[#out + 1] = self.heads and self.heads[key] end
  for _, o in ipairs(self.upRows or {}) do out[#out + 1] = o end
  return out
end

-- 0.9.5 phase 4K (spec 06a section 3.3): the docked sections, in their order, and what is open (NEW key Panoply.cdb.guideSections; open
-- until the player closes one)
UI.SECTIONS = { "trip", "upnext", "prof" }
UI.SECTION_TITLE = { trip = "Trip", upnext = "Up next", prof = "Profession" }
UI.SECTION_TIP = {
  trip = "How long the trip to this step takes at your pace, leg by leg, and when you reach the next level. Click the header to fold it; click the line for the details.",
  upnext = "The steps after this one. Click the header to fold it.",
  prof = "The next step of the profession you follow, or of the one the profession card shows. Click the header to fold it.",
}
function UI:SectionOpen(key)
  local s = Panoply.cdb and Panoply.cdb.guideSections
  return not (type(s) == "table" and s[key] == false)
end
function UI:ToggleSection(key)
  if not Panoply.cdb then return end
  if type(Panoply.cdb.guideSections) ~= "table" then Panoply.cdb.guideSections = {} end
  Panoply.cdb.guideSections[key] = not self:SectionOpen(key)
  self:Refresh()
end
-- spec 06a section 3.4: Compact (step card, trip line and actions; Up next and Profession one line each) below this width, Full above;
-- the NEW setting guideWindowSize forces either ("auto", "compact", "full")
UI.COMPACT_W = 340
Panoply.defaults.account.guideWindowSize = "auto"
function UI:IsCompact(w)
  local mode = Panoply.db and Panoply.db.guideWindowSize or "auto"
  if mode == "compact" then return true end
  if mode == "full" then return false end
  return (w or self:Width()) < UI.COMPACT_W
end

-- The Profession section: what it shows, or nil when it is not shown (playing along, no profession, or the card turned off while the
-- guide follows only the route)
function UI:ProfSection()
  local G = Panoply.ProfGuide
  if Panoply:PlayAlong() or not G then return nil end
  local name = G:Tracked()
  if not name then return nil end
  local follows = G:Active() ~= "leveling"
  if not follows and Panoply.db.profTracker == false then return nil end
  local rank, mx = Panoply.Professions:CurrentSkill(name)
  local st = G:First()
  local head = rank and ("%s %d / %d"):format(name, rank, mx or 0) or name
  local what = st and Panoply.StepText.Headline(st) or (rank and rank >= 300 and "All done: 300!" or "Nothing to do right now.")
  local inGuide = st and Panoply.Engine.detour == st
  local sub
  if st then
    if inGuide then sub = "In your guide now - follow the arrow."
    elseif st.gather then sub = "Do this as you pass by; it never takes over your route."
    elseif st.wait then sub = "Comes back by itself when you are ready."
    elseif G:Mode() == "off" then sub = "Click Follow in guide to follow it."
    else sub = "Shows in your guide when you are close by." end
  end
  return { name = name, line = head .. " \194\183 " .. what, sub = sub, step = st, inGuide = inGuide, multi = #G:Chosen() > 1 }
end
-- the profession card hides while this window shows it docked (and comes back when this window is hidden). 0.9.5 phase 4K review:
-- not while the window asks a question (its "ask" card draws no Profession section), so the profession shows in one of the two
function UI:DocksProfession()
  return self.frame ~= nil and self.frame:IsShown() and not Panoply:PlayAlong() and self.mode ~= "ask" and self:ProfSection() ~= nil
end
function UI:ProfFollow()
  local G = Panoply.ProfGuide
  if G then G:Force() end
  self:Show()
end
function UI:OpenProfMenu(owner)
  local s = self:ProfSection()
  local items = {}
  if s and s.multi then
    items[#items + 1] = { text = "Switch profession", tip = "Follow your other profession instead (for example Mining instead of Blacksmithing).",
      func = function() if Panoply.ProfTracker then Panoply.ProfTracker:Cycle() end end }
  end
  items[#items + 1] = { text = "Plan", tip = "Your full plan on the Professions page: shopping list, trainers, segments and where to gather.",
    func = function() if Panoply.Menu then Panoply.Menu:Open("professions") end end }
  return Skin.Menu(owner, items)
end
-- The actions menu (spec 06a section 3.3): Replan, Report a problem, Open the Guide page
function UI:ActionsMenuItems()
  local items = {
    { text = "Replan", tip = "Build a fresh route from where you are right now.", func = function() Panoply:Replan("button") end },
  }
  if Panoply.ReportWindow then
    items[#items + 1] = { text = "Report a problem", tip = "Something wrong with this step? Tell us. The report window opens with this step filled in.",
      func = function() Panoply.ReportWindow:Open() end }
  end
  items[#items + 1] = { text = "Open the Guide page", tip = "Your next step, the route and every guide setting.", func = function() if Panoply.Menu then Panoply.Menu:Open("guide") end end }
  return items
end
function UI:OpenActionsMenu(owner) return Skin.Menu(owner, self:ActionsMenuItems()) end
-- move the scrolled part by dy (down is positive); stops at both ends
function UI:Scroll(dy)
  if not (self.canScroll and self.frame) then return false end
  local was = self.scrollY or 0
  local to = math.max(0, math.min(self.maxScroll or 0, was + (dy or 0)))
  if to == was then return false end
  self.scrollY = to
  self:Refresh()
  return true
end
-- 0.7.3.6 (profiles): put the window where the saved place says (or the standard place) and at the saved size
function UI:ApplySavedPlace()
  local f = self.frame
  if not f then return end
  local w = Panoply.cdb and Panoply.cdb.window
  f:ClearAllPoints()
  if w and w.p then
    local x, y = Panoply.Windows:Offsets(f, w)
    f:SetPoint(w.p, UIParent, w.rp or w.p, x, y)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -90, -30) end
  f:SetWidth(self:Width())
  self:Refresh()
end

-- Opacity: the panel and card fills follow the background slider; the brass trim and caps fade less.
function UI:ApplyAlpha()
  local f = self.frame
  if not f then return end
  local a = Panoply.db.windowAlpha or 0.95
  if f.panoplyBg then f.panoplyBg:SetAlpha(a) end
  if f.panoplyTrim then f.panoplyTrim:SetAlpha(math.min(1, 0.25 + a)) end
  if self.card then
    if self.card.panoplyBg then self.card.panoplyBg:SetAlpha(Skin.ALPHA.card * a) end
    if self.card.panoplyTrim then self.card.panoplyTrim:SetAlpha(math.min(1, 0.2 + a)) end
  end
  if self.headerBar then self.headerBar:SetAlpha(a) end
  self.bgAlpha = a
end

-- Fade the whole window when the mouse is not over it (checked a few times a second, only
-- while the window is shown and the option is on).
function UI:FadeTarget()
  if self.inCombat and Panoply.db.hideInCombat then return 0 end
  if not Panoply.db.windowFade then return 1 end
  if self.frame and self.frame:IsMouseOver() then return 1 end
  return Panoply.db.windowFadeAlpha or 0.35
end
function UI:OnUpdate(dt)
  self.elapsed = (self.elapsed or 0) + (dt or 0)
  if self.elapsed < 0.15 then return end
  self.elapsed = 0
  self.updates = (self.updates or 0) + 1
  local want = self:FadeTarget()
  local f = self.frame
  local cur = f:GetAlpha() or 1
  if math.abs(cur - want) > 0.01 then Skin.FadeTo(f, want, 0.25) end
end
function UI:ApplyFade()
  local f = self.frame
  if not f then return end
  if Panoply.db.windowFade then
    f:SetScript("OnUpdate", function(_, dt) UI:OnUpdate(dt) end)
  else
    f:SetScript("OnUpdate", nil)
    f:SetAlpha(1)
  end
end

-- 0.5.6 "Hide in combat": the guide window and the profession tracker fade out when a fight
-- starts and fade back in when it ends. Alpha only (no Show/Hide), so nothing can be blocked by
-- combat lockdown; the mouse is switched off while faded so clicks reach the world.
UI.COMBAT_FADE = 0.3
function UI.CombatFrames()
  local out = {}
  if UI.frame then out[#out + 1] = UI.frame end
  if Panoply.ProfTracker and Panoply.ProfTracker.frame then out[#out + 1] = Panoply.ProfTracker.frame end
  return out
end
function UI:FadeForCombat(f, faded)
  if not f then return end
  if faded then
    if not f.panoplyCombatFaded then f.panoplyCombatFaded = true f.panoplyMouseWas = f.IsMouseEnabled and f:IsMouseEnabled() end
    Skin.FadeTo(f, 0, self.COMBAT_FADE)
    if f.EnableMouse then f:EnableMouse(false) end
  elseif f.panoplyCombatFaded then
    f.panoplyCombatFaded = nil
    local want = (f == self.frame) and self:FadeTarget() or 1
    Skin.FadeTo(f, want, self.COMBAT_FADE)
    if f.EnableMouse then f:EnableMouse(f.panoplyMouseWas ~= false) end
  end
end
function UI:OnCombat(inCombat)
  self.inCombat = inCombat and true or false
  local on = Panoply.db and Panoply.db.hideInCombat
  for _, f in ipairs(UI.CombatFrames()) do self:FadeForCombat(f, inCombat and on) end
  -- 0.5.7: the guide window's own drop-down menu closes too (our own plain frame, not secure,
  -- so Hide() is allowed in combat). The arrow is a separate frame with its own setting.
  local m = Skin.menu
  if inCombat and on and m and m:IsShown() and (m.panoplyOwner == self.menuBtn or m.panoplyOwner == self.frame) then m:Hide() end
end

local function savePos(f)
  if not Panoply.cdb then return end
  Panoply.cdb.window = Panoply.Windows:Place(f)      -- { p, rp, x, y, s }: s is the scale the offsets are in
end

-- Rough text height (FontString:GetStringHeight is not reliable before the first frame draw).
local function estLines(text, size, width)
  if not text or text == "" then return 0 end
  local lines = 0
  for para in (text .. "\n"):gmatch("(.-)\n") do
    lines = lines + math.max(1, math.ceil((#para * size * 0.52) / math.max(40, width)))
  end
  return lines
end
UI.EstLines = estLines

-- After 0.8.4: a step's tip that would push the guide window off the screen is cut to what fits (the written guides' longest tips are
-- five sentences; at 1.3x text the window was taller than a 1024x668 screen). The cut ends at a sentence when one ends in its
-- second half, else at a word with an ellipsis. The "Whole tip" button under it shows all of it.
UI.WHY_MIN = 120   -- characters of a tip that are always kept
local function clipTip(text, keep)
  if #text <= keep then return text end
  local cut = text:sub(1, keep)
  local stop
  for pos in cut:gmatch("()[%.!%?]%s") do stop = pos end
  if stop and stop > keep * 0.5 then return cut:sub(1, stop) end
  return (cut:match("^(.*%S)%s+%S*$") or cut) .. "\226\128\166"
end
UI.ClipTip = clipTip

function UI:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteFrame", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  self.frame = f
  f:SetSize(self:Width(), 260)
  f:SetResizable(true)
  C.SetResizeBounds(f, MIN_W, MIN_H, MAX_W, MAX_H)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() if not Panoply.db.windowLocked then f:StartMoving() end end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePos(f) end)
  -- Window size (0.7.3.7): the guide window is one of the windows the setting reaches; a place it saved is saved again after a rescale.
  -- It is taken in before it is placed, so a saved place is put on at the scale the window has now (Windows:Offsets), not at the one
  -- it will have once its real height is known (it may then shrink to fit the screen, keeping the same spot).
  Panoply.Windows:Register(f, { save = function(fr) if Panoply.cdb and Panoply.cdb.window then savePos(fr) end end })
  -- 0.9.5 (item 3): shown or clicked while the main window is open, it comes in front of it; its place stays its own (saved above)
  Panoply.Windows:OwnPlace(f)
  local w = Panoply.cdb and Panoply.cdb.window
  if w and w.p then
    local x, y = Panoply.Windows:Offsets(f, w)
    f:SetPoint(w.p, UIParent, w.rp or w.p, x, y)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -90, -30) end  -- clear of the minimap cluster
  Skin.Panel(f, Panoply.db.windowAlpha)

  -- Header: crest, name, where you are
  local crest = f:CreateTexture(nil, "OVERLAY"); crest:SetSize(26, 26); Skin.Logo(crest)
  crest:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
  -- skin v3: no header band, a hairline under the title bar instead (its top follows the header height)
  local bar = f:CreateTexture(nil, "ARTWORK"); Skin.Solid(bar, Skin.colors.hairline, 1)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -41); bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -41); bar:SetHeight(1)
  self.headerBar = bar
  -- 0.9.5 phase 4K (spec 06a section 3.3): the header line is where you are, "Level 15 · Sentinel Hill, Westfall" (the crest says whose
  -- window it is). self.where keeps the same words for what reads them (the mockup text dump) and is not drawn.
  self.title = Skin.Heading(f, 13, "")
  self.title:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -10)
  self.where = Skin.Text(f, 10, Skin.colors.inkSoft)
  self.where:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -1)
  self.where:Hide()
  local close = Skin.IconButton(f, "x", 20, function() UI:Hide() end, "Hide the guide", "Hide this window. Left-click the minimap button or type /panoply guide to bring it back.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -11)
  local menu = Skin.Button(f, "Menu", 56, 20, function() Panoply.Menu:Toggle() end, "Open Panoply Suite", "The one Panoply Suite window: the Guide, Muster, Class, professions and every setting.")
  menu:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self.menuBtn = menu
  -- Right-click the header: window options (lock, steps shown, opacity, fade, reset size).
  f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then UI:OpenWindowMenu() end end)

  -- 0.9.5 phase 4K (spec 06a section 3.3): what the guide follows is the Guide page's own Follows control (UI/GuideParts.lua), in place of
  -- the Leveling | Professions | Both tabs and the profession button
  self.follows = Panoply.GuideParts.Follows(f, { page = "guide", width = 220, height = 22 })
  self.follows:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, -44)
  self.closeBtn = close

  -- Step card (skin v3: inset slate card, hairline, no parchment)
  local card = Skin.Card(f)
  card:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, CARD_TOP)
  card:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_INSET, CARD_TOP)
  card:SetHeight(120)
  self.card = card
  -- Current step highlight: cerulean accent bar on the card's left edge and a step-type icon.
  local accent = card:CreateTexture(nil, "ARTWORK"); Skin.Solid(accent, Skin.colors.accent, 0.95)
  accent:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -8); accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 8); accent:SetWidth(3)
  self.cardAccent = accent
  self.stepIcon = card:CreateTexture(nil, "OVERLAY"); self.stepIcon:SetSize(20, 20)
  self.stepIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
  self.stepNum = Skin.Ink(card, 10, Skin.colors.inkSoft)
  self.stepNum:SetPoint("LEFT", self.stepIcon, "RIGHT", 6, 0)
  -- the headline: Lato SemiBold (quest titles are names, not headings)
  self.stepTitle = Skin.Name(card, 14, Skin.colors.heading)
  self.stepTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -34)
  self.stepTitle:SetWidth(WIDTH - CARD_INSET * 2 - 96)
  self.why = Skin.Ink(card, 11, Skin.colors.inkSoft)
  self.why:SetWidth(WIDTH - CARD_INSET * 2 - 96)
  -- 0.5.8: "[34] Quest Name" in the game's quest difficulty colour
  self.questLine = Skin.Text(card, 12, Skin.colors.text)
  self.questLine:SetWidth(WIDTH - CARD_INSET * 2 - 96)
  if self.questLine.SetJustifyH then self.questLine:SetJustifyH("LEFT") end
  -- location note under the headline ("Inside the Lion's Pride Inn, upstairs")
  self.locNote = Skin.Ink(card, 11, Skin.colors.accent)
  self.locNote:SetWidth(WIDTH - CARD_INSET * 2 - 96)
  if self.locNote.SetJustifyH then self.locNote:SetJustifyH("LEFT") end
  self.locNote:Hide()
  -- forever-data: "New Forever zone, guide coming soon" (Engine/StepText.lua NewZoneNote)
  self.zoneNote = Skin.Ink(card, 11, Skin.colors.accent)
  self.zoneNote:SetWidth(WIDTH - CARD_INSET * 2 - 96)
  if self.zoneNote.SetJustifyH then self.zoneNote:SetJustifyH("LEFT") end
  self.zoneNote:Hide()

  -- Arrow + distance on the card
  local arrowBox = card:CreateTexture(nil, "ARTWORK")
  arrowBox:SetSize(70, 70)   -- 0.6.0 (no glow anywhere): an empty anchor box now, no soft glow texture
  arrowBox:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
  self.arrowGlow = arrowBox
  self.arrow = Skin.NavArrow(card, "OVERLAY", 44)
  self.arrow:SetPoint("CENTER", arrowBox, "CENTER", 0, 0)
  self.dist = Skin.Ink(card, 10, Skin.colors.inkSoft)
  self.dist:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -70)
  if self.dist.SetJustifyH then self.dist:SetJustifyH("CENTER") end
  self.dist:SetWidth(78)

  self.progress = {}
  for i = 1, MAX_PROGRESS do
    local icon = card:CreateTexture(nil, "ARTWORK"); icon:SetSize(13, 13)
    local fs = Skin.Ink(card, 12)
    fs:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    fs:SetWidth(WIDTH - CARD_INSET * 2 - 50)
    -- 0.9.5 phase 4K (spec 06a section 3.3): an objective with a count ("3/8 Kobold Vermin") gets a thin count bar under its words
    local track = card:CreateTexture(nil, "ARTWORK"); Skin.Solid(track, Skin.colors.slotBottom or Skin.colors.hairline, 1); track:SetHeight(3)
    track.panoplyBarTrack = true
    local fill = card:CreateTexture(nil, "OVERLAY"); Skin.Solid(fill, Skin.colors.accent, 0.95); fill:SetHeight(3)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    track:Hide(); fill:Hide()
    self.progress[i] = { icon = icon, text = fs, track = track, fill = fill }
  end
  -- Action button inside the card (Build my route / Setup / I've done it)
  self.cardButton = Skin.Button(card, "Build my route", 150, 26, function() UI:CardAction() end, "Build my route",
    "Plan the next few levels from your level, zone and finished quests.")

  -- Second card button: point the arrow at the Auction House (buy instead of gather)
  self.altButton = Skin.Button(card, "Auction House instead", 150, 22, function() UI:AltAction() end, "Buy it instead",
    "Points the arrow at the nearest Auction House, if you would rather buy than gather.")
  self.altButton:Hide()
  -- After 0.8.4: under a tip that was cut to fit the screen: all of it on hover, and in the chat window on a click
  self.whyMore = Skin.Button(card, "Whole tip", 90, 20, function() UI:WholeTip() end, "The whole tip", "")
  self.whyMore:Hide()
  -- Profession badge on profession steps
  self.profBadge = Skin.Ink(card, 10, Skin.colors.inkTitle)
  self.profBadge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -92, -10)
  if self.profBadge.SetJustifyH then self.profBadge:SetJustifyH("RIGHT") end

  -- Waiting-for-partner banner
  local wait = CreateFrame("Frame", nil, f)
  wait:SetHeight(26)
  Skin.Box(wait, "S", { fill = Skin.colors.bgHigh, fillA = 1, line = Skin.colors.goldDark })
  self.waitText = Skin.Text(wait, 11, Skin.colors.heading)
  self.waitText:SetPoint("CENTER", wait, "CENTER", 0, 0)
  if self.waitText.SetJustifyH then self.waitText:SetJustifyH("CENTER") end
  self.waitBanner = wait
  wait:Hide()

  -- 0.9.7: levelling with a partner (see UI:PartnerParts above). Every row is made here, with the window, and only shown or hidden
  -- later: the partner line with "Sync to my step", and the partner card (small line, title, words, more lines, buttons).
  local prow = CreateFrame("Frame", nil, f)
  prow:SetHeight(18)
  self.partnerText = Skin.Ink(prow, 11, Skin.colors.inkSoft)
  self.partnerText:SetPoint("TOPLEFT", prow, "TOPLEFT", 2, -2)
  self.partnerSync = Skin.Button(prow, UI.PARTNER_SYNC, 110, 20, function() UI:PartnerSync() end, UI.PARTNER_SYNC, UI.PARTNER_SYNC_TIP)
  self.partnerRow = prow
  prow:Hide()
  local pcard = Skin.Card(f)
  pcard:SetHeight(60)
  local paccent = pcard:CreateTexture(nil, "ARTWORK"); Skin.Solid(paccent, Skin.colors.gold, 0.95)
  paccent:SetPoint("TOPLEFT", pcard, "TOPLEFT", 1, -8); paccent:SetPoint("BOTTOMLEFT", pcard, "BOTTOMLEFT", 1, 8); paccent:SetWidth(3)
  self.partnerKicker = Skin.Label(pcard, 10)
  self.partnerTitle = Skin.Name(pcard, 13, Skin.colors.heading)
  self.partnerBody = Skin.Ink(pcard, 11, Skin.colors.inkSoft)
  self.partnerLines, self.partnerBtns = {}, {}
  for i = 1, UI.PARTNER_LINES do
    self.partnerLines[i] = Skin.Ink(pcard, 11)
    self.partnerLines[i]:Hide()
  end
  for i = 1, UI.PARTNER_BUTTONS do
    local b = Skin.Button(pcard, "", 90, 22, function() UI:PartnerButton(i) end, "", "")
    b:Hide()
    self.partnerBtns[i] = b
  end
  self.partnerCard = pcard
  pcard:Hide()

  -- 0.9.5 phase 4K (spec 06a section 3.3): docked sections under the step card, each with a header that opens and closes it (what is
  -- open is remembered, Panoply.cdb.guideSections): Trip, Up next, Profession. The trip strip and the profession card were windows of their
  -- own under and beside this one.
  self.heads = {}
  for _, key in ipairs(UI.SECTIONS) do
    local h = CreateFrame("Button", nil, f)
    h:SetHeight(20)
    h.panoplyGapOK, h.key = true, key
    h.chev = h:CreateTexture(nil, "ARTWORK"); h.chev:SetSize(10, 10)
    h.chev:SetPoint("LEFT", h, "LEFT", 0, 0)
    local gc = Skin.colors.gold
    h.chev:SetVertexColor(gc[1], gc[2], gc[3], 1)
    h.label = Skin.Label(h, 11); h.label:SetText(UI.SECTION_TITLE[key])
    h.label:SetPoint("LEFT", h, "LEFT", 16, 0)
    h.summary = Skin.Ink(h, 11, Skin.colors.inkSoft)
    if h.summary.SetWordWrap then h.summary:SetWordWrap(false) end
    h.tip, h.tipBody = UI.SECTION_TITLE[key], UI.SECTION_TIP[key]
    h:SetScript("OnClick", function() if not UI.compact then UI:ToggleSection(key) end end)
    h:SetScript("OnEnter", function(self)
      local GT = _G.GameTooltip
      if not GT then return end
      GT:SetOwner(self, "ANCHOR_RIGHT")
      GT:AddLine(self.tip, 1, 1, 1)
      GT:AddLine(self.tipBody, nil, nil, nil, true)
      GT:Show()
    end)
    h:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    self.heads[key] = h
  end
  self.upHead = self.heads.upnext.label
  -- Trip: the leg icons with their times and the total on one line (UI/Trip.lua), then the pace line. A click opens the trip details.
  self.tripLine = Panoply.Trip.LineWidget(f, { size = 14, font = 11 })
  self.tripLine:SetScript("OnMouseUp", function() Panoply.Trip:TogglePanel() end)
  self.paceText = Skin.Ink(f, 11, Skin.colors.inkSoft)
  -- Up next: two lines a row (the step, then the quests and where), never cut short; a row that bundles several quests ("+6 more")
  -- lists them all on a click
  self.upLines, self.upIcons, self.upSubs, self.upRows = {}, {}, {}, {}
  self.upOpen = {}
  for i = 1, MAX_UPCOMING do
    local row = CreateFrame("Button", nil, f)
    row.panoplyGapOK, row.index = true, i
    local ic = row:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18)
    local fs = Skin.Text(row, 12, Skin.colors.text)
    fs:SetWidth(WIDTH - 60)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    local sub = Skin.Ink(row, 11, Skin.colors.inkSoft)
    if sub.SetJustifyH then sub:SetJustifyH("LEFT") end
    row.tip, row.tipBody = "Every quest of this step", "Click to list every quest this step bundles, and click again to fold them."
    row:SetScript("OnClick", function(self) if self.panoplyBundle then UI.upOpen[self.panoplyKey or i] = not UI.upOpen[self.panoplyKey or i] or nil UI:Refresh() end end)
    row:SetScript("OnEnter", function(self)
      local GT = _G.GameTooltip
      if not (GT and self.panoplyBundle) then return end
      GT:SetOwner(self, "ANCHOR_RIGHT")
      GT:AddLine(self.tip, 1, 1, 1)
      GT:AddLine(self.tipBody, nil, nil, nil, true)
      GT:Show()
    end)
    row:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    row:Hide()
    self.upLines[i], self.upIcons[i], self.upSubs[i], self.upRows[i] = fs, ic, sub, row
  end
  -- Profession: the profession followed or the one the card shows (Profession card setting), its skill and next step
  self.profLine = Skin.Text(f, 12, Skin.colors.text)
  if self.profLine.SetJustifyH then self.profLine:SetJustifyH("LEFT") end
  self.profSub = Skin.Ink(f, 11, Skin.colors.inkSoft)
  if self.profSub.SetJustifyH then self.profSub:SetJustifyH("LEFT") end
  self.profGo = Skin.Button(f, "Follow in guide", 110, 22, function() UI:ProfFollow() end, "Follow in guide",
    "Put this profession step in this window now, with the arrow.")
  self.profLater = Skin.Button(f, "Later", 60, 22, function() if Panoply.ProfGuide then Panoply.ProfGuide:Snooze(Panoply.ProfGuide:First()) end end, "Later",
    "Hide this step for 15 minutes and carry on levelling.")
  self.profMore = Skin.IconButton(f, "Settings", 22, function(b) UI:OpenProfMenu(b) end, "More", "Switch profession, or open the profession plan.")
  self.profMore.panoplyKitIcon = "icon.ui.more"

  -- Level bar, at the bottom edge of the window (never scrolls): the rested part shaded, and the pace mark (UI/PaceMark.lua)
  self.xpBar = Skin.Bar(f, 8)
  self.xpBar.panoplyWidth = WIDTH - 24
  local rest = self.xpBar:CreateTexture(nil, "BORDER")
  Skin.Solid(rest, Skin.colors.accent, 0.35)
  rest:SetPoint("TOPLEFT", self.xpBar, "TOPLEFT", 1, -1); rest:SetPoint("BOTTOMLEFT", self.xpBar, "BOTTOMLEFT", 1, 1)
  rest:Hide()
  self.xpRest = rest
  local pace = self.xpBar:CreateTexture(nil, "OVERLAY")
  Skin.Solid(pace, Skin.colors.goldBright or Skin.colors.gold, 1)
  pace:SetSize(2, 12)
  pace:Hide()
  self.xpPace = pace

  -- Actions: one row. Skip, Back, Done (only on a step the game can't see done), and a menu with the rest.
  self.buttons = {}
  local x = 12
  local function btn(label, w, tip, body, fn)
    local b = Skin.Button(f, label, w, 22, fn, tip, body)
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
    x = x + w + 6
    b.panoplyMinW = w
    self.buttons[#self.buttons + 1] = b
    return b
  end
  self.skipBtn = btn("Skip", 58, "Skip this step", "Move on without doing this step (for example if you already did it).", function() Panoply.Engine:Next() end)
  self.backBtn = btn("Back", 58, "Previous step", "Go back one step if you skipped too far.", function() Panoply.Engine:Prev() end)
  self.doneBtn = btn("Done", 64, "Mark as done", "The game can't tell when this step is done (training or buying, for example). Tick it off here.",
    function() Panoply.StepText.MarkDone(Panoply.Engine:Current()) end)
  self.moreBtn = Skin.IconButton(f, "Settings", 22, function(b) UI:OpenActionsMenu(b) end, "More", "Replan, Report a problem, or open the Guide page.")
  self.moreBtn.panoplyKitIcon = "icon.ui.more"

  -- Resize grip (bottom-right); size is saved per character.
  Skin.ResizeGrip(f, function(w, h) UI:SetUserSize(w, h) end, function()
    if f.panoplySizing then UI.sizingWidth = f:GetWidth(); UI:Refresh() end
  end)
  if Panoply.db.windowLocked and f.panoplyGrip then f.panoplyGrip:Hide() end
  -- Nov 2026 ("shrinking the guide vertically"): the window may be made shorter than what it shows. The part between the header
  -- and the buttons (the step card, Up next, the level bar) then scrolls: those parts are children of a frame that clips, so they
  -- are cut cleanly at its edges; the mouse wheel moves them, and a thin mark at the right shows where you are. The header, the
  -- guide switch and the buttons at the bottom never scroll.
  local clip = CreateFrame("Frame", nil, f)
  clip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -42); clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 40)
  if clip.SetClipsChildren then clip:SetClipsChildren(true); self.canScroll = true end
  self.clip = clip
  -- panoplyGapOK: the step card and the bars are parts of a window, not rows of a list (the layout checker's list-row rule is not for them)
  for _, part in ipairs(self:BodyParts()) do if part.SetParent then part:SetParent(clip); part.panoplyGapOK = true end end
  -- the parts that never scroll are above the scrolling body: a body part scrolled under them (clipped, so not seen) can never
  -- take a click or a drag meant for the header or the buttons
  local base = (f.GetFrameLevel and f:GetFrameLevel()) or 1
  if clip.SetFrameLevel then clip:SetFrameLevel(base + 1) end
  local fixed = { self.menuBtn, self.closeBtn, self.follows, f.panoplyGrip, self.xpBar, self.moreBtn }
  for _, b in ipairs(self.buttons) do fixed[#fixed + 1] = b end
  for i = 1, #self.buttons + 6 do
    local o = fixed[i]
    if o and o.SetFrameLevel then o:SetFrameLevel(base + UI.FIXED_LEVEL) end
  end
  local mark = f:CreateTexture(nil, "OVERLAY")
  Skin.Round(mark, 1.5, Skin.TEX.RFill)
  mark:SetVertexColor(Skin.colors.gold[1], Skin.colors.gold[2], Skin.colors.gold[3], 0.7)
  mark:SetWidth(3); mark:Hide()
  self.scrollMark = mark
  if f.EnableMouseWheel then f:EnableMouseWheel(true) end
  f:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(-(delta or 0) * UI.SCROLL_STEP) end)
  Panoply:Listen("STEP_CHANGED", function() UI.scrollY = 0 end)      -- a new step starts at its top
  -- the profession card is docked in this window while it shows: hidden, it comes back on its own (and goes again when this shows)
  f:SetScript("OnHide", function() f:SetAlpha(1) if Panoply.ProfTracker and Panoply.ProfTracker.frame then Panoply.ProfTracker:Refresh() end end)
  f:SetScript("OnShow", function()
    if Panoply.ProfTracker and Panoply.ProfTracker.frame then Panoply.ProfTracker:Refresh() end
    UI:SettleSoon()   -- 0.9.7: shown, it is laid out again once the game draws it (UI:Settle)
    -- Nov 18 2026: the one-time "Right-click the guide..." tip (UI/Report.lua); nothing is added to this window
    if Panoply.ReportWindow and Panoply.ReportWindow.GuideOpened then Panoply.ReportWindow:GuideOpened() end
  end)
  Panoply:Listen("PROF_UPDATED", function() UI:Refresh() end)
  self:ApplyAlpha()
  self:ApplyFade()
  Skin.Animate(f, -10)
  -- PARTNER_CHANGED (0.9.7): the partner line, the partner card or the waiting line has something new to say
  for _, ev in ipairs({ "STEP_CHANGED", "STEP_UPDATED", "STEPS_CHANGED", "SYNC_STATUS", "PLAN_FINISHED", "OPTION_CHANGED", "GUIDE_SWITCHED", "LEVEL_CHANGED", "NOGUIDE_CHANGED", "PARTNER_CHANGED" }) do
    Panoply:Listen(ev, function() UI:Refresh() end)
  end
  self:Refresh()
  return f
end

function UI:AltAction()
  local ask = self.psAsk
  if ask and ask.b then ask.b.fn(self.altButton) return end   -- the guide's question: the second answer
  local step = Panoply.Engine:Current()
  local a = step and step.alt
  if a and a.map then Panoply.Arrow:PointAt(a.map, a.x, a.y, a.name or "Auction House") end
end

function UI:CardAction()
  local a = self.cardActionKind
  if a == "ask" then if self.psAsk then self.psAsk.a.fn(self.cardButton) end
  elseif a == "setup" then Panoply.Wizard:Start()
  else Panoply:Replan("button") end
end

local function setIcon(icon, done)
  Skin.SetMark(icon, done and "Ready" or "Waiting")
  icon:SetVertexColor(1, 1, 1, (done or icon.panoplyGameIcon) and 1 or 0.8)
end

-- 0.9.5 phase 4K: the one test for a step the game can't see done (Engine/StepText.lua ST.Undetectable; spec 05b section 2.2)
local function needsConfirm(step) return Panoply.StepText.Undetectable(step) end

-- Arrow on the card follows the big arrow's numbers.
function UI:UpdateArrow()
  if not self.frame then return end
  local A = Panoply.Arrow
  local info = A and A.last
  -- 0.9.6 phase I: a question card (a route choice at the start of a guide has a target) uses the card's whole width: no card arrow
  if not info or not info.target or self.mode == "ask" then
    self.arrow:Hide(); self.arrowGlow:Hide(); self.dist:SetText("")
    return
  end
  self.arrowGlow:Show()
  if info.angle then
    self.arrow:Show()
    Panoply.Arrow.SetRotation(self.arrow, info.angle)
    local c = info.color or Skin.colors.arrowFar
    self.arrow:SetVertexColor(c[1], c[2], c[3], 1)
  else
    self.arrow:Hide()
  end
  -- 0.9.5 phase 4K (spec 06a section 3.2): the distance only; the trip time is the docked Trip section's (it was said twice)
  self.dist:SetText(Panoply.StepText.Distance(info.yards, info.otherZone))
end

-- 0.5.5: every height in the window comes from the measured text (Skin.TextHeight), so long
-- titles, reasons and objectives push what is below them down instead of running under it.
local TH = function(fs, w) return Skin.TextHeight(fs, w) end
-- The "Whole tip" button: the tip that was cut to fit the screen, in the chat window
function UI:WholeTip()
  if self.whyFull and self.whyFull ~= "" then Panoply:Print(self.whyFull) end
end

function UI:Refresh()
  local f = self.frame
  if not f then return end
  if Panoply:PlayAlong() then f:Hide() return end   -- 0.7.1: no guide window while playing along
  local E, S, ST, QD = Panoply.Engine, Panoply.State, Panoply.StepText, Panoply.QuestData
  local SP = Skin.SP
  local W = (f.panoplySizing and self.sizingWidth) or self:Width()
  self.W = W
  if not f.panoplySizing then f:SetWidth(W) end
  local cardW = W - CARD_INSET * 2
  for _, l in ipairs(self.progress) do l.text:SetWidth(cardW - 50) end
  local compact = self:IsCompact(W)
  self.compact = compact
  self.xpBar.panoplyWidth = W - 24 - 14
  local where = S.zone or ""
  if S.subzone and S.subzone ~= "" and S.subzone ~= where then where = S.subzone .. ", " .. where end
  -- "Level 15 · Sentinel Hill, Westfall"
  local whereText = ("Level %d%s"):format(S.level or 1, where ~= "" and (" \194\183 " .. where) or "")
  self.where:SetText(whereText)
  self.title:SetText(whereText)
  -- header: where you are sits left of the Menu and close buttons; what the guide follows on the row under it
  local headW = W - 46 - (Skin.FitButton(self.menuBtn, 56) + 20 + 6 + 10) - 8
  self.title:SetWidth(headW)
  local headH = math.max(36, 10 + TH(self.title, headW) + SP.s)
  self.follows:Fit(140, cardW)
  self.follows:ClearAllPoints(); self.follows:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, -(headH + 2))
  local fh = self.follows:GetHeight() or 22
  headH = headH + 2 + fh + SP.s
  self.headerBar:ClearAllPoints()
  self.headerBar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(headH - 1)); self.headerBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -(headH - 1))
  local bodyTop = headH + SP.s
  local sy = (self.canScroll and self.scrollY) or 0             -- how far the body is scrolled (0 = at its top)
  local cardTop = -bodyTop + sy
  self.bodyTop = bodyTop
  -- 0.9.7: levelling with a partner: the partner line, then the partner card, above the step card (they scroll with it)
  do
    local pLine, pSync, pCard = self:PartnerParts()
    local row = self.partnerRow
    if pLine then
      local pt, sb = self.partnerText, self.partnerSync
      pt:SetText(pLine)
      local bw, bh = 0, 0
      if pSync then bw, bh = Skin.FitButton(sb, 90, cardW) sb:Show() else sb:Hide() end
      -- the button sits beside a line short enough for it, else under the line
      local beside = pSync and Skin.TextWidth(pt) + SP.s + bw + 2 <= cardW
      local tw = beside and (cardW - bw - SP.s - 2) or (cardW - 2)
      pt:SetWidth(tw)
      local th = math.max(14, TH(pt, tw))
      local rh = th + 4
      sb:ClearAllPoints()
      if beside then
        rh = math.max(rh, bh)
        sb:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
      elseif pSync then
        sb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(th + 4 + SP.xs))
        rh = th + 4 + SP.xs + bh
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, cardTop); row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_INSET, cardTop)
      row:SetHeight(rh)
      row:Show()
      cardTop = cardTop - rh - SP.s
    else
      row:Hide()
    end
    local pc = self.partnerCard
    if pCard then
      local tw = cardW - 24
      local py = -8
      local function put(fs, text)
        fs:SetText(text)
        fs:SetWidth(tw)
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", pc, "TOPLEFT", 12, py)
        fs:Show()
        py = py - TH(fs, tw)
      end
      put(self.partnerKicker, type(pCard.kicker) == "string" and pCard.kicker ~= "" and pCard.kicker or UI.PARTNER_KICKER[pCard.kind] or UI.PARTNER_KICKER_OTHER)
      py = py - SP.xs
      put(self.partnerTitle, pCard.title)
      if type(pCard.body) == "string" and pCard.body ~= "" then
        py = py - SP.xs
        put(self.partnerBody, pCard.body)
      else self.partnerBody:SetText(""); self.partnerBody:Hide() end
      local shown = 0
      for _, l in ipairs(type(pCard.lines) == "table" and pCard.lines or {}) do
        if shown < UI.PARTNER_LINES and type(l) == "string" and l ~= "" then
          shown = shown + 1
          py = py - SP.xs
          put(self.partnerLines[shown], l)
        end
      end
      for i = shown + 1, UI.PARTNER_LINES do self.partnerLines[i]:SetText(""); self.partnerLines[i]:Hide() end
      local btns, flow = partnerButtons(pCard), {}
      for i, b in ipairs(self.partnerBtns) do
        local def = btns[i]
        b.panoplyFlowSkip = not def or nil
        if def then
          b.label:SetText(def.label)
          b.tip, b.tipBody = def.label, type(def.tip) == "string" and def.tip or nil
          b:Show()
          flow[#flow + 1] = b
        else b:Hide() end
      end
      if #flow > 0 then
        py = py - SP.s
        py = py - Skin.FlowButtons(pc, flow, 12, py, tw, 6, 60)
      end
      local ph = -py + 10
      pc:ClearAllPoints()
      pc:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, cardTop); pc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_INSET, cardTop)
      pc:SetHeight(ph)
      pc:Show()
      cardTop = cardTop - ph - SP.s
    else
      pc:Hide()
    end
  end
  self.card:ClearAllPoints()
  self.card:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, cardTop)
  self.card:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_INSET, cardTop)
  self.cardTop = cardTop

  local step = E:Current()
  local prof = step and step.isProf
  -- Dungeon helper: a dungeon step (Engine/Dungeon.lua) has its own list; the levelling route waits under it
  local DG = step and step.isDungeon and Panoply.Dungeon or nil
  local finished = step and not prof and not DG and not step.ps and E.index >= #E.steps and E:IsComplete(E.index)
  -- WoW Forever with PanoplyGuide's engine: a question the guide waits on (the next zone, a group quest, a quest that left the log)
  local PE = Panoply.PanoplyGuideEngine
  local psOn = PE and PE:Active()
  local ask = psOn and not prof and not DG and not (step and step.isTravel) and PE:Question() or nil
  self.psAsk = ask
  -- Without quest data we can still follow the quest log; the install help shows when there is nothing else.
  local install = not QD:Available() and QD.status ~= nil and (not step or finished)
  self.noGuide = false   -- 0.7.4.1: set below when the idle card is the "no guide for this area" card
  self.noEngine = false  -- 0.9.7: set below when the idle card is the one line "Guide not available"
  local y = -10
  Skin.SetIcon(self.stepIcon, UI.StepIconName(step))
  self.cardButton:Hide()
  self.altButton:Hide()
  self.whyMore:Hide()
  if not self.fitting then self.whyKeep, self.whyFull, self.progKeep, self.progressCount, self.fitFold = nil, nil, nil, nil, nil end
  self.locNote:SetText(""); self.locNote:Hide()
  self.zoneNote:SetText(""); self.zoneNote:Hide()
  self.profBadge:SetText("")
  self.questLine:SetText(""); self.questLine:Hide()
  for _, l in ipairs(self.progress) do l.icon:Hide(); l.text:Hide(); l.track:Hide(); l.fill:Hide() end
  self.cardActionKind = nil
  -- the step number row: icon, number and (on profession steps) the skill badge
  local function numRow(textW)
    self.stepNum:SetWidth(textW)
    return math.max(20, TH(self.stepNum, textW)) + 8 + SP.s
  end

  if ask or install or not step or finished then
    local t, body
    if ask then
      self.stepNum:SetText(ask.kicker or "Your guide asks")
      t, body = ask.title, ask.body
      self.mode = "ask"
      self.arrow:Hide(); self.arrowGlow:Hide(); self.dist:SetText("")
    elseif install then
      local info = ST.InstallQuestData()
      self.stepNum:SetText("No quest data found")
      t, body = info.title, info.intro .. "\n\n" .. table.concat(info.steps, "\n")
      self.mode = "install"
    else
      t, body = ST.WhatNow()
      self.noGuide = Panoply.NoGuide and Panoply:NoGuideHere() and #E.steps == 0 or false
      self.noStep = Panoply.Guides and Panoply.Guides.NoStepShown and Panoply.Guides:NoStepShown() or false   -- Nov 11 2026 (Engine/Guides.lua NoStep)
      self.stepNum:SetText(psOn and (PE.guideID and "Guide finished" or "No guide here yet") or self.noGuide and "No guide here" or self.noStep and "Nothing to follow here" or finished and "Plan complete" or "Nothing to follow yet")
      self.mode = "idle"
      -- 0.9.7: the guide engine cannot run on WoW Forever: one line, no button (a character still in setup keeps "Start setup").
      -- When the engine says so itself the line also takes the place of "No guide here"; else only of "Nothing to follow yet".
      local none, said = false, false
      if not step and not psOn and not (Panoply.cdb and not Panoply.cdb.setupDone) then none, said = self:NoEngine() end
      self.noEngine = none and (said or not (self.noGuide or self.noStep)) or false
      if self.noEngine then
        self.stepNum:SetText(UI.NO_ENGINE)
        t, body = "", ""
      end
    end
    y = -numRow(cardW - 50)
    self.stepTitle:SetWidth(cardW - 24)
    self.stepTitle:SetText(t)
    self.stepTitle:ClearAllPoints(); self.stepTitle:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
    if not self.noEngine then y = y - TH(self.stepTitle, cardW - 24) - SP.s end
    self.why:SetText(body)
    self.why:SetWidth(cardW - 24)
    self.why:ClearAllPoints(); self.why:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
    if not self.noEngine then y = y - TH(self.why, cardW - 24) - SP.m end
    local zn = self.mode == "idle" and not self.noEngine and ST.NewZoneNote(nil)
    if zn then
      self.zoneNote:SetText(zn)
      self.zoneNote:SetWidth(cardW - 24)
      self.zoneNote:ClearAllPoints(); self.zoneNote:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.zoneNote:Show()
      y = y - TH(self.zoneNote, cardW - 24) - SP.m
    end
    if ask then
      -- the answers: one button each, under the question
      self.cardActionKind = "ask"
      self.cardButton.label:SetText(ask.a.label)
      self.cardButton.tip, self.cardButton.tipBody = ask.a.label, ask.a.tip
      Skin.FitButton(self.cardButton, 150, cardW - 24)
      self.cardButton:ClearAllPoints(); self.cardButton:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.cardButton:Show()
      y = y - self.cardButton:GetHeight() - SP.s
      if ask.b then
        self.altButton.label:SetText(ask.b.label)
        self.altButton.tip, self.altButton.tipBody = ask.b.label, ask.b.tip
        Skin.FitButton(self.altButton, 150, cardW - 24)
        self.altButton:ClearAllPoints(); self.altButton:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
        self.altButton:Show()
        y = y - self.altButton:GetHeight() - SP.s
      end
    elseif self.mode == "idle" and not self.noEngine and not self.noGuide and not self.noStep and not (psOn and PE.guideID) then
      local setup = Panoply.cdb and not Panoply.cdb.setupDone
      self.cardActionKind = setup and "setup" or "replan"
      self.cardButton.label:SetText(setup and "Start setup" or "Build my route")
      self.cardButton.tip = setup and "Start setup" or "Build my route"
      Skin.FitButton(self.cardButton, 150, cardW - 24)
      self.cardButton:ClearAllPoints(); self.cardButton:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.cardButton:Show()
      y = y - self.cardButton:GetHeight() - SP.s
    end
  else
    self.mode = "step"
    local textW = cardW - 96   -- clear of the arrow on the right
    if prof then
      local r, mx = Panoply.Professions:CurrentSkill(step.prof)
      local G = Panoply.ProfGuide
      local q = G and G.queue or {}
      local n = 0
      for i, st in ipairs(q) do if st.key == step.key then n = i end end
      self.stepNum:SetText(("%s step%s"):format(step.prof, #q > 1 and n > 0 and (" %d of %d"):format(n, #q) or ""))
      self.profBadge:SetText(r and ("Skill %d / %d"):format(r, mx or 0) or "")
    elseif DG then
      self.stepNum:SetText(("Dungeon step %d of %d"):format(DG:StepNumber()))
    else
      -- 0.9.5 phase 4K (spec 06a section 3.2): one meaning everywhere, "Step 5 of 27 · Westfall" (Engine/StepText.lua)
      local num = ST.NumberText(step)
      self.stepNum:SetText(num ~= "" and num or step.numText or ("Step %d of %d"):format(E.index, #E.steps))
    end
    y = -numRow(textW - 26)
    -- the skill badge goes under the step number (never on top of it)
    self.profBadge:ClearAllPoints()
    if self.profBadge:GetText() ~= "" then
      self.profBadge:SetPoint("TOPLEFT", self.card, "TOPLEFT", 38, y + SP.xs)   -- 4K: clear of a step number that wraps at 1.3x text
      self.profBadge:SetWidth(textW - 26)
      if self.profBadge.SetJustifyH then self.profBadge:SetJustifyH("LEFT") end
      y = y - TH(self.profBadge, textW - 26) - SP.xs
    end
    local ql = ST.QuestLine(step, 3)
    if ql ~= "" then
      -- skin v3: one line; a long quest name is measured and cut with an ellipsis
      self.questLine:SetWidth(textW)
      Skin.Ellipsize(self.questLine, ql, textW)
      self.questLine:ClearAllPoints(); self.questLine:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.questLine:Show()
      y = y - TH(self.questLine, textW) - SP.xs
    end
    local head = ST.Headline(step)
    self.stepTitle:SetText(head)
    self.stepTitle:SetWidth(textW)
    self.stepTitle:ClearAllPoints(); self.stepTitle:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
    y = y - TH(self.stepTitle, textW) - SP.xs
    local zn = ST.NewZoneNote(step)
    if zn then
      self.zoneNote:SetText(zn)
      self.zoneNote:SetWidth(textW)
      self.zoneNote:ClearAllPoints(); self.zoneNote:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.zoneNote:Show()
      y = y - TH(self.zoneNote, textW) - SP.xs
    end
    local note = ST.LocationNote(step)
    if note then
      self.locNote:SetText(note)
      self.locNote:SetWidth(textW)
      self.locNote:ClearAllPoints(); self.locNote:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.locNote:Show()
      y = y - TH(self.locNote, textW) - SP.xs
    else
      self.locNote:SetText(""); self.locNote:Hide()
    end
    local why = ST.Why(step)
    self.whyFull, self.whyWidth = why, textW
    local cut = self.whyKeep and #why > self.whyKeep
    if cut then why = clipTip(why, self.whyKeep) end
    self.why:SetText(why)
    self.why:SetWidth(textW)
    self.why:ClearAllPoints(); self.why:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
    y = y - TH(self.why, textW) - (cut and SP.xs or SP.m)
    if cut then
      self.whyMore.tipBody = self.whyFull
      Skin.FitButton(self.whyMore, 90, textW)
      self.whyMore:ClearAllPoints(); self.whyMore:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y)
      self.whyMore:Show()
      y = y - self.whyMore:GetHeight() - SP.m
    end
    -- keep clear of the arrow and its distance line
    self:UpdateArrow()   -- 0.6.0: the distance line may carry the trip time on a second line
    local arrowBottom = -(70 + TH(self.dist, 78) + SP.s)
    y = math.min(y, arrowBottom)
    local shown = 0
    local lines = ST.Progress(step)
    self.progressCount = #lines
    -- fitting the screen (below): fewer lines than usual, what is still to do first
    local maxLines = self.progKeep or MAX_PROGRESS
    if self.progKeep and #lines > maxLines then
      local open, done = {}, {}
      for _, p in ipairs(lines) do if p.done then done[#done + 1] = p else open[#open + 1] = p end end
      lines = open
      for _, p in ipairs(done) do lines[#lines + 1] = p end
    end
    for _, p in ipairs(lines) do
      if shown < maxLines then
        shown = shown + 1
        local l = self.progress[shown]
        l.icon:ClearAllPoints(); l.icon:SetPoint("TOPLEFT", self.card, "TOPLEFT", 14, y - 2)
        setIcon(l.icon, p.done)
        l.icon:Show()
        l.text:SetText(p.text)
        l.text:ClearAllPoints(); l.text:SetPoint("TOPLEFT", self.card, "TOPLEFT", 32, y)
        local c = p.done and Skin.colors.inkSoft or Skin.colors.ink
        l.text:SetTextColor(c[1], c[2], c[3], 1)
        l.text:Show()
        y = y - math.max(16, TH(l.text, cardW - 50)) - 3
        -- the count bar under an objective that has one ("3/8 Kobold Vermin"), not under one that is done
        local have, need = tostring(p.text or ""):match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(have), tonumber(need)
        if have and need and need > 0 and not p.done then
          local bw = cardW - 50 - 6
          l.track:ClearAllPoints(); l.track:SetPoint("TOPLEFT", self.card, "TOPLEFT", 32, y); l.track:SetWidth(bw); l.track:Show()
          l.fill:SetWidth(math.max(1, math.floor(bw * math.min(1, have / need) + 0.5)))
          if have > 0 then l.fill:Show() end
          y = y - 3 - 4
        end
      end
    end
    if prof and step.alt and step.kind ~= "profah" then
      self.altButton.label:SetText("Auction House instead")
      self.altButton.tip, self.altButton.tipBody = "Buy it instead", "Points the arrow at the nearest Auction House, if you would rather buy than gather."
      Skin.FitButton(self.altButton, 150, cardW - 24)
      self.altButton:ClearAllPoints(); self.altButton:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y - 4)
      self.altButton:Show()
      y = y - 4 - self.altButton:GetHeight() - SP.xs
    end
  end
  local cardH = -y + 8
  self.card:SetHeight(cardH)
  local fy = self.cardTop - cardH - 8

  -- Waiting banner. 0.9.7: also the waiting line of levelling with a partner (a hand-in the partner still needs, UI:PartnerWaiting)
  local waitLine = self.mode == "step" and not E.waiting and not prof and not DG and self:PartnerWaiting(step) or nil
  self.partnerWaitLine = waitLine
  if (E.waiting or waitLine) and self.mode == "step" then
    local partner = Panoply.Sync and Panoply.Sync:ActivePartner()
    self.waitText:SetText(waitLine or ST.Waiting(partner))
    self.waitText:SetWidth(W - 16 - 20)
    local wh = math.max(26, TH(self.waitText, W - 36) + 10)
    self.waitBanner:SetHeight(wh)
    self.waitBanner:ClearAllPoints()
    self.waitBanner:SetPoint("TOPLEFT", f, "TOPLEFT", 8, fy); self.waitBanner:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, fy)
    self.waitBanner:Show()
    fy = fy - wh - SP.s
  else
    self.waitBanner:Hide()
  end

  -- 0.9.5 phase 4K (spec 06a section 3.3): the docked sections, each under a header that folds it (Compact: one line each, no fold)
  local inner = W - 2 * CARD_INSET
  local TW = Skin.TextWidth
  for _, h in pairs(self.heads) do h:Hide() end
  self.tripLine:Hide(); self.paceText:Hide()
  for _, r in ipairs(self.upRows) do r:Hide() end
  for _, o in ipairs({ self.profLine, self.profSub, self.profGo, self.profLater, self.profMore }) do o:Hide() end
  local function head(key, summary)
    local h = self.heads[key]
    -- one line (no fold) in Compact, or when the window would not fit the screen otherwise (the fitting below)
    local oneLine = compact or (self.fitFold and self.fitFold[key]) or false
    local open = (not oneLine) and self:SectionOpen(key)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, fy); h:SetWidth(inner)
    local lx = 0
    if oneLine then h.chev:Hide()
    else
      lx = 16
      h.chev:Show()
      if Skin.Sections and Skin.Sections.SetChevron then Skin.Sections.SetChevron(h.chev, open) end
    end
    local lw = math.ceil(TW(h.label)) + 2
    h.label:SetWidth(lw)
    h.label:ClearAllPoints(); h.label:SetPoint("TOPLEFT", h, "TOPLEFT", lx, -2)
    local sx = lx + lw + SP.s
    local sw = math.max(20, inner - sx)
    h.summary:ClearAllPoints(); h.summary:SetPoint("TOPLEFT", h, "TOPLEFT", sx, -2)
    h.summary:SetWidth(sw)
    if open or not summary or summary == "" then h.summary:SetText(""); h.summary:Hide()
    else Skin.Ellipsize(h.summary, summary, sw); h.summary:Show() end
    local hh = math.max(16, TH(h.label, lw), h.summary:IsShown() and TH(h.summary, sw) or 0) + 4
    h:SetHeight(hh)
    h.chev:ClearAllPoints(); h.chev:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -math.floor((hh - 10) / 2))
    h:Show()
    fy = fy - hh - SP.xs
    return open
  end

  -- Trip: to this step, leg by leg, then when you reach the next level
  if self.mode == "step" then
    local data = Panoply.Trip:Legs()
    local paceLine = ST.PaceLine()
    if data or paceLine then
      -- the header's tooltip says the trip in words ("To this step: 3 min. Walk 40 s · Flight to Sentinel Hill 2 min")
      local tTotal, tLegs = Panoply.Trip:StripTexts()
      local words = {}
      for _, w in ipairs({ tTotal, tLegs }) do if w and w ~= "" then words[#words + 1] = w end end
      self.heads.trip.tipBody = UI.SECTION_TIP.trip .. (#words > 0 and ("\n\n" .. table.concat(words, ". ")) or "")
      local open = compact or head("trip", data and data.totalText or paceLine)
      if open then
        if data then
          self.tripLine:ClearAllPoints(); self.tripLine:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET + 4, fy)
          local th = self.tripLine:Fill(inner - 4)
          if th > 0 then fy = fy - th - SP.xs end
        end
        if paceLine and not compact then
          self.paceText:SetText(paceLine); self.paceText:SetWidth(inner - 4)
          self.paceText:ClearAllPoints(); self.paceText:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET + 4, fy); self.paceText:Show()
          fy = fy - TH(self.paceText, inner - 4) - SP.xs
        end
      end
      fy = fy - SP.s
    end
  end

  -- Up next (the plan, or the quest log while Panoply Suite Quest Data is off). On a profession step: the
  -- next profession steps, then the levelling step you go back to.
  local upcoming = {}
  local nUp = math.max(0, math.min(MAX_UPCOMING, (Panoply.db.stepsShown or 3) - 1))
  if prof then
    local q = Panoply.ProfGuide.queue or {}
    local after = false
    for _, st in ipairs(q) do
      if after and #upcoming < math.max(0, nUp - 1) then upcoming[#upcoming + 1] = st end
      if st.key == step.key then after = true end
    end
    local lv = E.steps[E.index]
    if lv and Panoply.ProfGuide:Active() == "both" then upcoming[#upcoming + 1] = { title = "Back to your route: " .. ST.Headline(lv) }
    elseif lv then upcoming[#upcoming + 1] = { title = ("Route waits at step %d: %s"):format(E.index, ST.Headline(lv)) } end
  end
  if DG then
    -- the next dungeon steps, then the levelling step you go back to
    for _, st in ipairs(DG:Upcoming(math.max(0, nUp - 1))) do upcoming[#upcoming + 1] = st end
    local lv = E.steps[E.index]
    if lv then upcoming[#upcoming + 1] = { title = "Back to your route: " .. ST.Headline(lv) } end
  end
  local list = {}
  if self.mode ~= "idle" and self.mode ~= "ask" then
    for i = 1, nUp do
      local idx = (self.mode == "step" and E.index or 0) + i
      if self.mode == "install" or (step and step.isTravel) then idx = E.index + i - 1 end   -- travel: the guide's step comes next
      local s = E.steps[idx]
      if prof or DG then s = upcoming[i] end
      if s then list[#list + 1] = s end
    end
  end
  if #list > 0 then
    self.upHead:SetText(self.mode == "install" and "Meanwhile, from your quest log" or "Up next")
    local first = list[1]
    local oneUp = compact or (self.fitFold and self.fitFold.upnext)
    local summary = oneUp and ST.Headline(first) or (#list == 1 and "1 step" or (#list .. " steps"))
    if head("upnext", summary) then
      local textW = inner - 32
      for i, s in ipairs(list) do
        local row, l, ic, sub = self.upRows[i], self.upLines[i], self.upIcons[i], self.upSubs[i]
        local isStep = s.goals ~= nil
        local nq = isStep and #ST.Quests(s) or 0
        row.panoplyBundle, row.panoplyKey = nq > 1 or nil, s
        local open = row.panoplyBundle and self.upOpen[s]
        -- line 1: the quest tag(s) and the step; a bundle lists every quest when opened (two lines, never cut short)
        l:SetWidth(textW)
        l:SetText(isStep and ST.RowText(s, open and nq or 1) or ST.Headline(s))
        local where = isStep and (ST.LocationNote(s) or s.zone) or nil
        if row.panoplyBundle and not open then where = (where and (where .. " \194\183 ") or "") .. "click for every quest" end
        ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -1)
        Skin.SetIcon(ic, s.title and not s.goals and "Travel" or UI.StepIconName(s))
        l:ClearAllPoints(); l:SetPoint("TOPLEFT", row, "TOPLEFT", 32, 0)
        local rh = TH(l, textW)
        if where and where ~= "" then
          sub:SetText(where); sub:SetWidth(textW)
          sub:ClearAllPoints(); sub:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -(rh + 1))
          sub:Show()
          rh = rh + 1 + TH(sub, textW)
        else sub:SetText(""); sub:Hide() end
        rh = math.max(20, rh + 4)
        -- upcoming steps are dimmed, a little more each row
        -- (0.5.8: not below 0.7 so the quest difficulty colours stay readable)
        local dim = math.max(0.7, 0.86 - (i - 1) * 0.08)
        ic:SetAlpha(dim); l:SetAlpha(dim); sub:SetAlpha(dim)
        ic:Show(); l:Show()
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, fy); row:SetSize(inner, rh)
        if row.EnableMouse then row:EnableMouse(row.panoplyBundle and true or false) end
        row:Show()
        fy = fy - rh - 2
      end
    end
    fy = fy - SP.s
  end
  for i = #list + 1, MAX_UPCOMING do self.upLines[i]:Hide(); self.upIcons[i]:Hide(); self.upSubs[i]:Hide() end

  -- Profession: docked here in place of the profession card (shown while you follow a profession, or the card setting is on)
  local ps = self.mode ~= "ask" and self:ProfSection() or nil
  self.profShown = ps
  if ps then
    if head("prof", ps.line) then
      self.profLine:SetText(ps.line); self.profLine:SetWidth(inner - 4)
      self.profLine:ClearAllPoints(); self.profLine:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET + 4, fy); self.profLine:Show()
      fy = fy - TH(self.profLine, inner - 4) - SP.xs
      if ps.sub and ps.sub ~= "" then
        self.profSub:SetText(ps.sub); self.profSub:SetWidth(inner - 4)
        self.profSub:ClearAllPoints(); self.profSub:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET + 4, fy); self.profSub:Show()
        fy = fy - TH(self.profSub, inner - 4) - SP.s
      end
      -- no button that does nothing: Follow in guide only while the step is not in the guide, Later only when there is a step
      self.profGo.panoplyFlowSkip = not (ps.step and not ps.inGuide) or nil
      self.profLater.panoplyFlowSkip = not ps.step or nil
      local btns = {}
      for _, b in ipairs({ self.profGo, self.profLater }) do if not b.panoplyFlowSkip then b:Show(); btns[#btns + 1] = b end end
      local bh = #btns > 0 and Skin.FlowButtons(f, btns, CARD_INSET + 4, fy, inner - 4 - 22 - 6, 6, 50) or 22
      self.profMore:ClearAllPoints(); self.profMore:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_INSET, fy); self.profMore:Show()
      fy = fy - math.max(bh, 22) - SP.s
    end
  end

  -- Level bar, at the bottom edge (never scrolls): the rested part shaded and the pace mark
  local pct = (S.xpMax or 0) > 0 and (S.xp or 0) / S.xpMax or 0
  local barW = W - 24 - 14     -- clear of the resize grip
  self.xpBar.panoplyWidth = barW
  self.xpBar:SetWidth(barW)
  self.xpBar:SetProgress(pct, ("Level %d  -  %d%%"):format(S.level or 1, math.floor(pct * 100)))
  self.xpBar:ClearAllPoints(); self.xpBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  local _, _, _, rested = C.XPKnown()
  if type(rested) == "number" and rested > 0 and (S.xpMax or 0) > 0 then
    local frac = math.min(1, ((S.xp or 0) + rested) / S.xpMax)
    self.xpRest:SetWidth(math.max(1, math.floor((barW - 2) * frac + 0.5)))
    self.xpRest:Show()
  else self.xpRest:Hide() end
  local horizon = Panoply.PaceMark and Panoply.PaceMark:Horizon()
  if horizon and barW > 4 then
    local px = math.max(1, math.min(barW - 3, math.floor((barW - 2) * horizon.frac + 0.5)))
    self.xpPace:ClearAllPoints(); self.xpPace:SetPoint("TOPLEFT", self.xpBar, "TOPLEFT", px, 2)
    self.xpPace:Show()
  else self.xpPace:Hide() end
  local barTotal = 10 + 8 + Skin.BarLabelSpace(self.xpBar)

  -- Actions: Skip, Back, Done (only on a step the game can't see done), and the menu. A button that would do nothing is not shown.
  local stepMode = self.mode == "step"
  local canBack
  if DG then canBack = stepMode and DG:CanBack()
  elseif step and step.ps and not step.isTravel then canBack = stepMode and PE:CanBack()
  else canBack = stepMode and not prof and E.index > 1 end
  self.skipBtn.label:SetText(prof and "Later" or "Skip")
  self.skipBtn.tip = prof and "Later" or "Skip this step"
  self.skipBtn.tipBody = prof and "Hide this profession step for 15 minutes and carry on with your route." or "Move on without doing this step (for example if you already did it)."
  local showDone = stepMode and needsConfirm(step) and true or false
  for b, on in pairs({ [self.skipBtn] = stepMode, [self.backBtn] = canBack and true or false, [self.doneBtn] = showDone }) do
    b.panoplyFlowSkip = not on or nil
    if on then b:Show() else b:Hide() end
  end
  local btnY = barTotal + SP.s
  local anyBtn = stepMode or canBack
  local footH = anyBtn and Skin.FlowButtons(f, self.buttons, 12, btnY, W - 24 - 14 - 22 - 6, 6, 50, true) or 22
  self.moreBtn:ClearAllPoints(); self.moreBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12 - 14, btnY + footH - 22)
  local footTotal = btnY + footH
  self.footTotal = footTotal
  local need = -(fy - sy) + footTotal + SP.m
  self.contentHeight = need
  -- the smallest height that still holds the header, what the guide follows, the buttons, the level bar and a strip of the body (the
  -- buttons wrap onto more rows on a narrow window, so this follows the width)
  local minH = math.max(MIN_H, math.ceil(bodyTop + UI.BODY_MIN + footTotal + 3))
  -- and never taller than the screen
  local maxH = MAX_H
  do
    local _, sh = Panoply.Windows:ScreenSize()
    local sc = f.GetScale and f:GetScale() or 1
    if sh and type(sc) == "number" and sc > 0 then maxH = math.max(minH, math.min(MAX_H, math.floor(sh / sc))) end
  end
  if minH ~= self.minHeight or maxH ~= self.maxHeight then
    self.minHeight, self.maxHeight = minH, maxH
    C.SetResizeBounds(f, MIN_W, minH, MAX_W, maxH)
  end
  local userH = self:UserHeight()
  if userH then userH = math.max(minH, math.min(maxH, userH)) end
  if not f.panoplySizing then
    -- a height the player chose is kept, also when it is less than the content needs: the body scrolls then (no clipping frame on
    -- this client: the window grows to its content, as before)
    -- 0.9.7: with the partner line or a partner card up the window is never taller than the screen: the body scrolls instead
    local partnerUp = self.partnerDrawn and (self.partnerDrawn.line or self.partnerDrawn.card)
    if self.canScroll and userH then f:SetHeight(userH)
    elseif self.canScroll and partnerUp and need > maxH then f:SetHeight(maxH)
    else f:SetHeight(math.max(need, userH or 0)) end
  end
  if self.clip then
    local top, bottom = bodyTop - 3, footTotal + 3
    self.clip:ClearAllPoints()
    self.clip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top); self.clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, bottom)
    local have = (f:GetHeight() or need)
    local maxScroll = self.canScroll and math.max(0, math.ceil(need - have)) or 0
    self.maxScroll = maxScroll
    if sy > maxScroll and not self.reflow then
      -- the window grew or the content got shorter: the body comes back up
      self.scrollY = maxScroll
      self.reflow = true
      local ok, err = pcall(self.Refresh, self)
      self.reflow = nil
      if not ok then error(err, 0) end
      return
    end
    local viewH = have - top - bottom
    if maxScroll > 0 and viewH > 12 then
      local full = viewH + maxScroll
      local mh = math.max(10, math.floor(viewH * viewH / full))
      local my = math.floor((viewH - mh) * (sy / maxScroll) + 0.5)
      self.scrollMark:ClearAllPoints()
      self.scrollMark:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -(top + my))
      self.scrollMark:SetHeight(mh); self.scrollMark:Show()
    else self.scrollMark:Hide() end
  end
  -- After 0.8.4: taller than the screen because of a long tip: cut the tip until the window fits (never below UI.WHY_MIN)
  if self.mode == "step" and not self.fitting and not f.panoplySizing and self.whyFull and not (self.canScroll and userH) then
    local _, sh = Panoply.Windows:ScreenSize()
    local scale = f.GetScale and f:GetScale() or 1
    -- 0.9.5 phase 4K: measured at 100% at most. Over 100% Window size already holds the window to what fits (Panoply.Windows:ScaleFor);
    -- fitting by the scale the window has now would change its height, then its scale, then the fitting again, login after login
    -- (the docked Trip and Up next made the window tall enough for that to show)
    local room = sh and (sh / math.min(1, math.max(0.1, (type(scale) == "number" and scale > 0) and scale or 1)) - 8)
    if room and need > room then
      local _, size = self.why:GetFont()
      size = (type(size) == "number" and size > 0) and size or 11
      local lineH, perLine = size * 1.25 + 2, math.max(10, math.floor((self.whyWidth or 200) * 0.94 / (size * 0.5)))
      local keep = #self.whyFull
      self.fitting = true
      local function again()
        local ok, err = pcall(self.Refresh, self)
        if not ok then self.fitting = nil error(err, 0) end
      end
      for _ = 1, 12 do
        local over = (self.contentHeight or 0) - room
        if over <= 0 or keep <= UI.WHY_MIN then break end
        keep = math.max(UI.WHY_MIN, keep - (math.ceil(over / lineH) + 1) * perLine)
        self.whyKeep = keep
        again()
      end
      -- still too tall with the shortest tip: fewer goal lines (what is still to do stays first), never fewer than two
      local n = math.min(MAX_PROGRESS, self.progressCount or 0)
      while (self.contentHeight or 0) > room and n > 2 do
        n = n - 1
        self.progKeep = n
        again()
      end
      -- 0.9.5 phase 4K: still too tall (the trip and the profession are docked in the window now): Up next, then Profession, go to one
      -- line each, as in Compact
      for _, key in ipairs({ "upnext", "prof" }) do
        if (self.contentHeight or 0) <= room then break end
        self.fitFold = self.fitFold or {}
        self.fitFold[key] = true
        again()
      end
      self.fitting = nil
      return
    end
  end
  if f.panoplyGrip then if Panoply.db.windowLocked then f.panoplyGrip:Hide() else f.panoplyGrip:Show() end end
  self:ApplyAlpha()
  self:UpdateArrow()
  if Panoply.Trip then Panoply.Trip:Refresh() end
  if Panoply.ProfTracker and Panoply.ProfTracker.frame then Panoply.ProfTracker:Refresh() end
end

-- Right-click the header: a tiny quick menu. Every setting is in the Guide's gear; "All settings..." opens it.
function UI:OpenWindowMenu()
  local items = {
    { text = Panoply.db.windowLocked and "Unlock window" or "Lock window", checked = Panoply.db.windowLocked,
      tip = "A locked window can't be dragged or resized.", func = function() Panoply:SetOption("windowLocked", not Panoply.db.windowLocked) end },
    { text = "Hide guide window", tip = "Bring it back with a left-click on the minimap button or /panoply guide.", func = function() UI:Hide() end },
    { text = "Reset size", tip = "Back to the standard width.", func = function() UI:ResetSize() end },
    { text = "All settings...", tip = "Opens the Guide's settings, on the guide window.", func = function() Panoply.Menu:OpenGear("guide", "window") end },
  }
  -- [reports] merge: SPEC-REPORTS - report the current step from the window menu
  if Panoply.ReportWindow then table.insert(items, 1, { text = "Report a problem...", tip = "Something wrong with this step? Tell us.", func = function() Panoply.ReportWindow:Open() end }) end
  return Skin.Menu(self.menuBtn, items)
end

Panoply.optionHooks.windowAlpha = function() UI:ApplyAlpha() end
Panoply.optionHooks.windowFade = function() UI:ApplyFade() end
-- switching the option during a fight applies at once
Panoply.optionHooks.hideInCombat = function()
  UI:OnCombat(UI.inCombat)
end
Panoply.optionHooks.stepsShown = function() UI:Refresh() end
Panoply.optionHooks.guideWindowSize = function() UI:Refresh() end
Panoply.optionHooks.windowLocked = function() UI:Refresh() end
Panoply:On("PLAYER_REGEN_DISABLED", function() UI:OnCombat(true) if Panoply.Arrow and Panoply.Arrow.OnCombat then Panoply.Arrow:OnCombat(true) end end)
Panoply:On("PLAYER_REGEN_ENABLED", function() UI:OnCombat(false) if Panoply.Arrow and Panoply.Arrow.OnCombat then Panoply.Arrow:OnCombat(false) end end)
-- 0.9.7: a partner line or card that came or went during the fight is drawn now
Panoply:On("PLAYER_REGEN_ENABLED", function() if UI.partnerQueued and UI.frame then UI.partnerQueued = nil UI:Refresh() end end)

function UI:Show()
  -- 0.7.1: playing along there is no guide window; "show the guide" opens the main window instead
  -- (its Guide page says so) and the saved shown/hidden choice is kept for switching back
  if Panoply:PlayAlong() then if self.frame then self.frame:Hide() end if Panoply.Menu then Panoply.Menu:Open("guide") end return end
  self:Create(); self.frame:Show(); if Panoply.cdb then Panoply.cdb.hidden = nil end; self:Refresh()
  self:SettleSoon()   -- 0.9.6.2: also when OnShow does not run (already shown, e.g. the first show after SETUP_DONE)
  -- Nov 18 2026: the one-time tip (UI/Report.lua), also when OnShow does not run (a new frame is shown from the start)
  if Panoply.ReportWindow and Panoply.ReportWindow.GuideOpened then Panoply.ReportWindow:GuideOpened() end
end
-- 0.9.7 (Nov 17 2026, a new character's first login at Northshire, Classic and WoW Forever): the window showed no "Step 1 of 81 ·
-- Elwynn Forest" line, no headline and no "Level 1 - 0%" label, the quest name cut short and a gap in the card, until it was resized.
-- At login it is laid out while the loading screen is still up, before the game has measured or drawn its fonts, and every later
-- refresh sets the same words at the same widths, which the game does not lay out again. A resize changes every width, so the game
-- lays out and measures every line again. UI:Settle is that same pass with no resize: the layout at a width one point wider (as the
-- grip does while it drags), then at the window's own width. It runs once the game is drawing: the frame after the window shows, after
-- the loading screen goes, and once more a moment after login (Panoply.LOGIN_DELAY) on a client without that event.
function UI:Settle()
  self.settlePending = nil
  local f = self.frame
  if not (f and f:IsShown()) or f.panoplySizing or Panoply:PlayAlong() then return end
  f.panoplySizing, self.sizingWidth = true, self:Width() + 1
  local ok, err = pcall(self.Refresh, self)
  f.panoplySizing, self.sizingWidth = nil, nil
  if not ok then error(err, 0) end
  self:Refresh()
end
function UI:SettleSoon()
  if self.settlePending then return end
  self.settlePending = true
  C.After(0, function() UI:Settle() end)
end
Panoply:On("PLAYER_ENTERING_WORLD", function() UI:SettleSoon() end)
Panoply:On("LOADING_SCREEN_DISABLED", function() UI:SettleSoon() end)
Panoply:On("PLAYER_LOGIN", function() C.After(Panoply.LOGIN_DELAY or 2, function() UI:Settle() end) end)

function UI:Hide()
  if Panoply:PlayAlong() then if self.frame then self.frame:Hide() end if Panoply.Menu and Panoply.Menu.frame then Panoply.Menu.frame:Hide() end return end
  if self.frame then self.frame:Hide() end; if Panoply.cdb then Panoply.cdb.hidden = true end
end
function UI:Toggle()
  if Panoply:PlayAlong() then if Panoply.Menu then Panoply.Menu:Toggle() end return end
  if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end
function UI:ApplyScale() if self.frame then Panoply.Windows:Apply(self.frame) end self:AfterScale() end
-- what hangs off the guide window follows its scale (the trip strip and the trip details)
function UI:AfterScale() if self.frame and Panoply.Trip and Panoply.Trip.Refresh then Panoply.Trip:Refresh() end end
