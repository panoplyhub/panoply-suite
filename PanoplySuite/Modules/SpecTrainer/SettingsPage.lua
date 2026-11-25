-- Talents and trainer settings: the rows of the Class page's gear (UI/Catalog.lua, page "class"; Class & Spec's until 0.9.5), built with
-- the gear's own row builder. All options are account settings (module defaults in Panoply.db); the plan
-- you follow is per character (Panoply.cdb.specTracked).
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local Skin = Panoply.Skin
local SUI = Panoply.SettingsUI

ST.SETTINGS_NAME = "Talents & spells"
ST.SETTINGS_ROWS = {
  { type = "check", key = "specNextCard", label = "Show the next talent when I level up", tip = "A small card with the talent and why. You click the talent yourself; Panoply Suite never spends points." },
  { type = "check", key = "specOutline", label = "Outline it in the talent window", indent = true, tip = "A thin outline on the talent in the game's talent window, or a dot on its tab." },
  { type = "heading", label = "At the trainer" },
  { type = "check", key = "trainerPanel", label = "Show the Trainer Helper beside the trainer window", tip = "Lists what your plan says to buy now with a tick and a Learn button, what is optional, what waits for the next visit and what is skipped." },
  { type = "check", key = "trainerLearnNext", label = "Show the \"Learn next\" button", indent = true, tip = "One click learns one spell. Panoply Suite never buys anything on its own." },
  { type = "check", key = "trainerShowSkip", label = "Show the Skip group", indent = true, tip = "Off: spells your plan skips are hidden from the list. The game's own trainer window still shows them." },
  { type = "check", key = "trainerProfPanel", label = "Show recipes at profession trainers", tip = "Recipes for your skill, their cost, and which ones your profession plan uses." },
  { type = "heading", label = "Away from the trainer" },
  { type = "check", key = "trainerToast", label = "Tell me when new spells are waiting", tip = "A short message when you level up and your trainer has something new. Never during a fight." },
  { type = "check", key = "trainerArrowOffer", label = "Offer to point the arrow to my trainer", indent = true, tip = "The nearest class trainer for your faction, by travel time. Your route is not changed." },
  { type = "check", key = "trainerMenuLine", label = "Trainer visits in my route", tip = "When spells or a profession rank wait for you, the Guide page's route has a step for the trainer." },
  { type = "heading", label = "Money" },
  { type = "check", key = "trainerMoneyWarn", label = "Warn me when I will be short for training" },
  { type = "check", key = "trainerMountFund", label = "Save for riding and a horse at level 40", tip = "Shows how much to put aside each level. Prices are the trainer's and vendor's, before any reputation discount." },
  { type = "slider", key = "trainerReserve", label = "Keep this much gold untouched (gold)", min = 0, max = 20, step = 1, fmt = "%dg",
    tip = "\"What you can afford\" leaves this amount alone, for repairs and food." },
}

-- The plan choices for this character: the ready-made plans, then your own (not copies).
-- 0.9.5 phase 4H: an edited copy of a ready-made plan ("... (mine)") is one of your own and is listed as one; a copy that is still the
-- ready-made plan stands for it (ST:IsMirror)
function ST:PlanChoices()
  local own, ready = self:Plans()
  local out = {}
  for _, p in ipairs(ready) do out[#out + 1] = { p.key, p.name } end
  for _, p in ipairs(own) do if not self:IsMirror(p) then out[#out + 1] = { p.key, p.name or p.key } end end
  out[#out + 1] = { "none", "No plan" }
  return out
end
function ST:PlanChoice()
  local t = self:Tracked()
  if not t then return "none" end
  if self:IsMirror(t) then return t.from end
  return t.key
end
function ST:SetPlanChoice(key)
  if key == "none" then
    self:CDB()[self:TrackKey()] = nil
    Panoply:Fire("SPEC_PLAN_CHANGED", nil)
  else
    self:Track(key)
  end
end

-- the "Plan I follow" button: cycles through the choices (a custom row of the gear sheet)
local function planButton(sp, x, y, width)
  local bw = 120
  local w = Skin.Button(sp, "", bw, 24, function(self)
    local list, cur = ST:PlanChoices(), ST:PlanChoice()
    local nxt = list[1][1]
    for i, v in ipairs(list) do if v[1] == cur then nxt = list[i % #list + 1][1] end end
    ST:SetPlanChoice(nxt)
    self:Refresh()
    if Panoply.PageSettings then Panoply.PageSettings:RefreshRows() end
  end, "Plan I follow", "Your talent hints and the trainer groups follow this plan. The Class page's plan control at the top changes it too.")
  function w:Refresh()
    local cur, label = ST:PlanChoice(), nil
    for _, v in ipairs(ST:PlanChoices()) do if v[1] == cur then label = v[2] end end
    self.label:SetText("Plan I follow: " .. (label or cur))
    Skin.FitButton(self, bw, bw)
  end
  local longest = ""
  for _, v in ipairs(ST:PlanChoices()) do if #v[2] > #longest then longest = v[2] end end
  -- one steady width (the longest choice, on one line when it fits), so cycling does not jump
  w.label:SetText("Plan I follow: " .. longest)
  Skin.FitButton(w, 120, width - 40)
  bw = math.ceil(w:GetWidth())
  local _, bh = Skin.FitButton(w, bw, bw)
  w.panoplyFixedH = bh
  w:Refresh()
  w:SetPoint("TOPLEFT", sp, "TOPLEFT", x + 2, y)
  return w, y - bh - Skin.SP.s
end

function ST:SettingsSourceText()
  local t = self:Tracked()
  local o = t and self:Origin(t)
  local lines = {}
  if t then
    local from = (o and o.source == "basic") and "from the Panoply Suite basic set (free, built in)"
      or (o and o.source == "public") and ("a public build: %s, %s"):format(o.sourceLine or "a public site", o.link or "")
      or (o and o.source ~= "own") and "from your PanoplySuite_SpecPlans file" or "your own plan"
    lines[1] = ("Plan: %s, %s. Without a plan: the tree with the most points."):format(t.name or t.key, from)
  else
    lines[1] = "Plan: none picked, so the tree with the most points decides."
  end
  local seen = self:CDB().trainerSeenAt
  lines[2] = "Prices: read from the trainer when you visit; until then from Panoply Suite's own table."
    .. (seen and (" Last trainer seen: " .. seen .. ".") or "")
  return table.concat(lines, "\n")
end

-- custom rows for the gear sheet: build(parent, x, y, width) -> widget, y below it
-- 0.9.9.4 (builds shown everywhere they are needed): "Plan I follow" is the shared build card (BuildCard.lua), as on the Talents tab:
-- the build followed, its kind and source (the web address in its tooltip), and Change build (the Class page's Builds tab). The cycling
-- button of older versions (planButton above) is no longer drawn; ST:PlanChoices / ST:SetPlanChoice stay.
ST.PlanRow = function(parent, x, y, width)
  local card = ST:BuildCard(parent, { mode = "line",
    onFollow = function(facts) ST:FollowBuild(facts.key) end,
    onBack = function() ST:EndPreview() if Panoply.PageSettings then Panoply.PageSettings:RefreshRows() end end })
  local w = math.max(ST.CARD.minW, width - 8)
  local function fill()
    local f, o = ST:TalentsCard()
    if not f then f, o = { none = true, title = "No build to follow yet", sub = ST:NoBuildLine() or ST.BUILD_WORDS.noneSub }, { actions = {} } end
    card:Set(f, o)
    return card:Fit(w)
  end
  local h0 = fill()
  card.panoplyFixedH = h0
  function card:Refresh()
    local h = fill()
    if h < h0 then self:SetHeight(h0) end
  end
  card:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  return card, y - h0 - Skin.SP.s
end
ST.planButtonRow = planButton
ST.PlannerRow = function(parent, x, y, width)
  local open = Skin.Button(parent, "Open the Talents tab", 200, 24, function() ST:OpenPlanner() end, "Open the Talents tab",
    "See your plan level by level, change it, or make, share and import your own.")
  local _, oh = Skin.FitButton(open, 120, width - 40)
  open:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
  return open, y - oh - Skin.SP.s
end
ST:Listen("SPEC_PLAN_CHANGED", function() if Panoply.PageSettings and Panoply.PageSettings.RefreshRows then Panoply.PageSettings:RefreshRows() end end)
