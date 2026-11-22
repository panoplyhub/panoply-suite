-- Spec & Trainer: the plan step of the setup, "Pick a plan for your <class>" (Step 2 item A, SPEC 22.4.2; step 3 of 5 since 0.9.5).
-- The step is added from here (the wizard's own builders and refreshers); UI/Wizard.lua lists it in W.ORDER and runs
-- it only when this module is on. The pick is applied when setup finishes (SETUP_DONE).
-- The plans are the class's ready-made ones (Specs.lua), the safe one chosen and marked Recommended, plus
-- "Build my own later" (0.9.5 phase 4L, spec 06a 2.3), which leaves the plan empty and opens the Class page afterwards (Step 2 item C).
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

Wz.builders.plan = function(p)
  p.ttl = Wz.Heading(p, "")
  p.intro = Wz.Para(p, "A plan says which talents to take and which spells to buy. You can change it any time.")
  p.cards = {}
  p.builtFor = nil
  function p:Build()
    for _, c in ipairs(self.cards) do c:Hide() end
    self.cards = {}
    for _, s in ipairs(ST:WizardPlans()) do
      -- no tooltip: the card shows the plan's whole text (spec 06a 2.6)
      local c = Wz.OptionCard(self, { onClick = function() ST:WizardPick(s.key) end })
      c.title:SetText(s.name)
      c.side:SetText(s.role or "")
      c.body:SetText(s.summary or "")
      c.extra:SetText("Talents: " .. (s.trees or "") .. (s.at60 and " (from 60)" or ""))
      c.pickKey = s.key
      self.cards[#self.cards + 1] = c
    end
    -- the one tooltip that adds something (spec 06a 2.6), shown beside the window
    local own = Wz.OptionCard(self, { onClick = function() ST:WizardPick(ST.OWN_PICK) end, tip = Wz.OWN_TEXT, tipBody = Wz.OWN_TIP })
    own.title:SetText(Wz.OWN_TEXT)
    own.body:SetText("Leave the plan empty for now and start your own tree on the Class page.")
    own.pickKey = ST.OWN_PICK
    self.cards[#self.cards + 1] = own
    self.builtFor = ST:ClassFile()
    self.builtExp = Wz.choices and Wz.choices.experience
  end
  p:Build()
  function p:Layout()
    local y = Wz.Top(self, self.ttl, self.intro)
    y = Wz.Grid(self, self.cards, y, 1)
    return -y + SP.m
  end
end
Wz.refreshers.plan = function(p)
  local exp = Wz.choices and Wz.choices.experience
  if p.builtFor ~= ST:ClassFile() or p.builtExp ~= exp then p:Build() end
  local rec = ST:WizardRecommended(exp)
  for _, c in ipairs(p.cards) do c:SetRecommended(rec ~= nil and c.pickKey == rec.key) end
  local cls = ST.CLASS_NAME[ST:ClassFile() or ""]
  p.ttl:SetText(cls and ("Pick a plan for your %s"):format(cls) or "Pick a plan")
  local pick = Wz.choices and Wz.choices.spec or ST:WizardDefault()
  for _, c in ipairs(p.cards) do c:SetSelected(c.pickKey == pick) end
end

-- Start guiding: follow the picked plan. "Build my own later" leaves the plan empty (a plan of your own that is
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
