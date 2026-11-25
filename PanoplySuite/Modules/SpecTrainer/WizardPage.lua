-- Spec & Trainer: the plan step of the setup, "Pick a plan for your <class>" (Step 2 item A, SPEC 22.4.2; step 3 of 5 since 0.9.5).
-- The step is added from here (the wizard's own builders and refreshers); UI/Wizard.lua lists it in W.ORDER and runs
-- it only when this module is on. The pick is applied when setup finishes (SETUP_DONE).
-- The plans are the class's ready-made ones (on WoW Forever the public builds, Data/ForeverBuilds.lua), the default one chosen (0.9.9.4:
-- no longer marked Recommended, our decision), plus "Plan by hand" (0.9.5 phase 4L "Build my own later", spec 06a 2.3; renamed 0.9.9.4), which leaves the plan empty and
-- opens the Class page afterwards (Step 2 item C).
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local Skin = Panoply.Skin
local Wz = Panoply.Wizard
if not Wz then return end
local SP = Skin.SP

ST.OWN_PICK = "own"

-- The current pick (a ready-made key, or "own").
function ST:WizardPick(key)
  if key then
    Wz.choices = Wz.choices or {}
    Wz.choices.spec = key
    Wz:Refresh()
  end
  return Wz.choices and Wz.choices.spec
end

-- What this character follows now (setup run again), else the class's default plan.
function ST:WizardDefault()
  local t = self:Tracked()
  if t then return t.from or (t.source == "own" and self.OWN_PICK) or t.key end
  local d = self:DefaultPlan()
  return d and d.key or self.OWN_PICK
end

-- "My usual" for this class: the plan the last character that finished setup chose when it had the same class (a class
-- plan cannot carry over to another class), else this class's default plan.
function ST:WizardUsual(last)
  local cls = self:ClassFile()
  if type(last) == "table" and last.class == cls and last.spec then
    if last.spec == self.OWN_PICK or self:Find(last.spec, cls) then return last.spec end
  end
  local d = self:DefaultPlan()
  return d and d.key or self.OWN_PICK
end

-- 0.9.5 phase 4L (spec 06a section 1): the plan that suits the answer to "How much have you played?". Every leveling plan is
-- written for any player, so the class's default leveling plan is Recommended, except for a character already at level 60 whose
-- player knows max level (answers 3 and 4): the class's level 60 plan then. Returns the plan, or nil.
function ST:WizardRecommended(experience)
  local d = self:DefaultPlan()
  local level = (self:Player() or {}).level or 1
  if (tonumber(experience) or 1) >= 3 and level >= 60 then
    for _, s in ipairs(self:ReadyMade()) do if s.at60 then return s end end
  end
  return d
end

-- The plans listed for this character: the leveling plans of its class (a level 60 plan is not a leveling plan; it
-- stays on the Class page), the plan it follows now even when that is one of those, and the Recommended one.
function ST:WizardPlans()
  local out, keep = {}, Wz.choices and Wz.choices.spec
  local t = self:Tracked()
  local now = t and (t.from or t.key)
  local rec = self:WizardRecommended(Wz.choices and Wz.choices.experience)
  for _, s in ipairs(self:ReadyMade()) do
    if not s.at60 or s.key == keep or s.key == now or (rec and s.key == rec.key) then out[#out + 1] = s end
  end
  return out
end

-- 0.9.9.4 ("this is also part of the setup and also part of the new user setup"): "How do you want to level?", the class's builds
-- grouped by spec on the shared build card (BuildCard.lua, pick mode: a click picks it; Follow this build picks it too; Show on tree
-- shows it on the Class page's Talents tab), a "No suggested build for this spec yet" line for a spec no build fits, then Plan by hand.
-- p.cards: the cards that can be picked, in order (the builds, then Plan by hand); p.groups: the spec headings and their cards.
ST.WIZARD_TITLE = "How do you want to level?"
ST.WIZARD_INTRO = "Each build is from a public guide. Change it any time on the Class page."
ST.WIZARD_NONE = "No suggested build for your class yet. Plan by hand: click talents on the Class page in the order you want them."
Wz.builders.plan = function(p)
  p.ttl = Wz.Heading(p, "")
  p.intro = Wz.Para(p, ST.WIZARD_INTRO)
  p.cards, p.groups, p.made, p.loose = {}, {}, {}, {}
  p.builtFor = nil
  function p:Build()
    for _, f in ipairs(self.made) do f:Hide() end
    self.cards, self.groups, self.made, self.loose = {}, {}, {}, {}
    local listed = {}
    for _, s in ipairs(ST:WizardPlans()) do listed[s.key] = true end
    local bySpec = ST:BuildsBySpec(ST:ClassFile())
    local pick = function(key) ST:WizardPick(key) end
    for _, g in ipairs(bySpec) do
      local grp = { head = ST:SpecHeading(self, g.name, 0), cards = {} }
      self.made[#self.made + 1] = grp.head
      local n = 0
      for _, f in ipairs(g.builds) do
        if listed[f.key] then
          local c = ST:BuildCard(self, { mode = "pick", onPick = function(card) pick(card.pickKey) end,
            onFollow = function(facts) pick(facts.key) end, onShow = function(facts) ST:ShowOnTree(facts.key) end })
          c:Set(f)
          grp.cards[#grp.cards + 1] = c
          self.cards[#self.cards + 1] = c
          self.made[#self.made + 1] = c
          n = n + 1
        end
      end
      if n == 0 then
        local c = ST:BuildCard(self, { mode = "line" })
        c:Set({ none = true, specName = g.name })
        grp.none = c
        self.made[#self.made + 1] = c
      end
      grp.head:SetText(n > 0 and ("%s \194\183 %d %s"):format(g.name, n, n == 1 and "build" or "builds") or g.name)
      self.groups[#self.groups + 1] = grp
    end
    -- the plans of the class this step lists that are not in a spec's group (none today; kept so nothing listed is ever lost)
    for _, s in ipairs(ST:WizardPlans()) do
      local found = false
      for _, c in ipairs(self.cards) do if c.pickKey == s.key then found = true end end
      if not found then
        local c = ST:BuildCard(self, { mode = "pick", onPick = function(card) pick(card.pickKey) end, onFollow = function(facts) pick(facts.key) end })
        c:Set(ST:BuildFacts(s))
        self.cards[#self.cards + 1] = c
        self.loose[#self.loose + 1] = c
        self.made[#self.made + 1] = c
      end
    end
    -- Plan by hand (the one card whose tooltip adds something: shown beside the window)
    local own = ST:BuildCard(self, { mode = "pick", onPick = function() pick(ST.OWN_PICK) end })
    own:Set({ byHand = true, tip = Wz.OWN_TIP, sub = "Leave the plan empty for now and start your own tree on the Class page." }, { pickKey = ST.OWN_PICK })
    own.tip, own.tipBody = Wz.OWN_TEXT, Wz.OWN_TIP
    self.own = own
    self.cards[#self.cards + 1] = own
    self.made[#self.made + 1] = own
    self.builtFor = ST:ClassFile()
    self.builtExp = Wz.choices and Wz.choices.experience
    self.builtTree = ST.trees and ST.trees[ST:ClassFile() or ""]
  end
  p:Build()
  function p:Layout()
    local y = Wz.Top(self, self.ttl, self.intro)
    local w = self.width - 40
    for _, g in ipairs(self.groups) do
      local hh = math.ceil(Skin.TextHeight(g.head, w))
      g.head:SetWidth(w); g.head:SetHeight(hh)
      Wz.At(self, g.head, 20, y)
      y = y - hh - SP.xs
      for _, c in ipairs(g.cards) do
        local h = c:Fit(w)
        Wz.At(self, c, 20, y)
        y = y - h - SP.s
      end
      if g.none then
        local h = g.none:Fit(w)
        Wz.At(self, g.none, 20, y)
        y = y - h - SP.s
      end
      y = y - SP.xs
    end
    for _, c in ipairs(self.loose) do local h = c:Fit(w) Wz.At(self, c, 20, y) y = y - h - SP.s end
    local h = self.own:Fit(w)
    Wz.At(self, self.own, 20, y)
    y = y - h - SP.s
    return -y + SP.m
  end
end
Wz.refreshers.plan = function(p)
  local exp = Wz.choices and Wz.choices.experience
  local tree = ST.trees and ST.trees[ST:ClassFile() or ""]
  if p.builtFor ~= ST:ClassFile() or p.builtExp ~= exp or p.builtTree ~= tree then p:Build() end
  -- (0.9.9.4, no build is marked "Recommended": the card shows only the guide's own words; the default stays chosen until a click)
  local pick = Wz.choices and Wz.choices.spec or ST:WizardDefault()
  for _, c in ipairs(p.cards) do c:SetSelected(c.pickKey == pick) end
  p.ttl:SetText(ST.WIZARD_TITLE)
  p.intro:SetText(#ST:ReadyMade() == 0 and ST.WIZARD_NONE or ST.WIZARD_INTRO)
end

-- Start guiding: follow the picked plan. "Plan by hand" leaves the plan empty (a plan of your own that is
-- already followed stays) and opens the Class page on its Plan tab, where "Build my own talent tree" opens the planner.
Panoply:Listen("SETUP_DONE", function()
  if not Panoply.Modules:IsOn("spectrainer") then return end
  local pick = Wz.choices and Wz.choices.spec
  if not pick then return end
  if pick == ST.OWN_PICK then
    local t = ST:Tracked()
    if not (t and t.source == "own" and not t.from) then
      local cdb = ST:CDB()
      local tk = ST:TrackKey()
      if cdb[tk] then cdb[tk] = nil Panoply:Fire("SPEC_PLAN_CHANGED", nil) end
    end
    ST:OpenClassSpec("plan")
  else
    ST:Track(pick)
  end
end)
