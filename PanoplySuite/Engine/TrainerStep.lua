-- Panoply Suite 0.9.5 phase 4K: trainer visits as steps of the route (spec 05 section 4.3, spec 05b section 2.2).
-- Own code.
--
-- When the Class page has spells to buy now (Spec & Trainer's waiting list) or the Professions page says a rank can be learned now
-- ("Train now", the same gate the Professions page and its alert use), the route shows a step "Train at <trainer>, <zone> · 2 spells,
-- 24s". It is put in BESIDE the guide, the way Engine/Travel.lua puts in its "Fly to" steps: the guide's own steps and data are
-- never edited, and the step lives only on the screens that show the route (the Guide page; Panoply.TrainerStep:Steps() for any other).
-- The game gives no event for "these spells were bought", so the step is one the engine can't see done (isTrainer: it shows the
-- "Won't hold you up" chip and a Done tick, spec 05b section 2.2). Done hides it until what waits changes (a new spell, a new rank).
-- Done is saved per character in the NEW key PanoplySuiteCharDB.trainerStepDone ({ [step key] = true }), made only the first time
-- Done is pressed; a key that no longer matches what waits is dropped (TS:Prune), so it never grows.
-- The old Trainer line under the Guide page's cards is replaced by this; its switch (trainerMenuLine) now turns these steps on or off.
local ADDON, Panoply = ...
local C = Panoply.Compat
local TS = { done = {} }   -- the fallback before the character's saved data exists (tests, a load error)
Panoply.TrainerStep = TS

-- the ticked keys: this character's saved table when there is one (read only: it is made by finish)
function TS:Done() return (Panoply.cdb and Panoply.cdb.trainerStepDone) or self.done end
local function isDone(key) return TS:Done()[key] == true end
-- a ticked step whose key no longer matches what waits ("class:" or one profession's) is forgotten
function TS:Prune(prefix, current)
  local d = self:Done()
  for k in pairs(d) do if k:sub(1, #prefix) == prefix and k ~= current then d[k] = nil end end
end
local function warn(what, err) Panoply:Debug("trainer step: " .. what .. " failed", tostring(err)) end

local function money(c)
  local ST = Panoply.SpecTrainer
  if ST and ST.Money then return ST.Money(c) end
  return C.FormatMoney and C.FormatMoney(c or 0) or tostring(c or 0)
end
local function plural(n, one) return n == 1 and one or (one .. "s") end

function TS:On() return not (Panoply.db and Panoply.db.trainerMenuLine == false) end

local function finish(step)
  if Panoply.cdb then Panoply.cdb.trainerStepDone = Panoply.cdb.trainerStepDone or {} end
  TS:Done()[step.key] = true
  Panoply:Fire("TRAINER_STEPS_CHANGED")   -- the Guide page redraws on it (UI/Menu.lua)
end

-- the class trainer: { step } or nil
function TS:ClassStep()
  local ST = Panoply.SpecTrainer
  if not (ST and Panoply.Modules and Panoply.Modules:IsOn("spectrainer") and ST.Waiting and ST.Player) then return nil end
  local okP, p = pcall(ST.Player, ST)
  if not okP then warn("the class", p) end
  if not okP or not p then return nil end
  local okW, w = pcall(ST.Waiting, ST, p)
  if not okW then warn("the spells waiting", w) end
  if not (okW and w and w.list and #w.list > 0) then self:Prune("class:", nil) return nil end
  local okT, t = pcall(ST.NearestTrainer, ST)
  if not okT then warn("the nearest trainer", t) end
  t = okT and t or nil
  local zone = t and t.spot and C.MapName and C.MapName(t.spot.map) or nil
  local key = ("class:%d:%d"):format(#w.list, w.cost or 0)
  self:Prune("class:", key)
  if isDone(key) then return nil end
  local who = t and t.name or "your class trainer"
  local s = { isTrainer = true, kind = "train", trainer = "class", key = key, zone = zone, spot = t and t.spot or nil, goals = {},
    title = ("Train at %s%s"):format(who, zone and (", " .. zone) or ""),
    detail = ("%d %s, %s"):format(#w.list, plural(#w.list, "spell"), money(w.cost or 0)),
    target = { page = "class", tab = "spells" }, onDone = finish }
  s.why = ("%d new %s waiting at your class trainer."):format(#w.list, plural(#w.list, "spell"))
  -- the mount fund (it was on the Trainer line): only in this step's tooltip
  local okM, per = pcall(ST.MountSaving, ST, p)
  if not okM then warn("the mount fund", per) end
  if okM and per and per > 0 then s.tip = ("Mount fund: put aside about %s a level for level 40."):format(money(per)) end
  return s
end

-- the profession ranks that can be learned now: { step, ... }
function TS:ProfSteps()
  local out = {}
  local G, PR, PD, PUI = Panoply.ProfGuide, Panoply.Professions, Panoply.ProfData, Panoply.ProfUI
  if not (G and PR and PD) then return out end
  local level = (Panoply.State and Panoply.State.level) or 0
  for _, name in ipairs(G:Chosen() or {}) do
    local skill, max = PR:CurrentSkill(name)
    if skill and max and max > 0 then
      local _, rk = PR:RankFor(PD[name], max)
      local g = PUI and PUI.Gate and PUI:Gate(name, skill, max)
      local ready
      if g then ready = g.skillOK and g.levelOK else ready = rk and skill >= (rk.minSkill or 0) and level >= (rk.minLevel or 0) end
      -- a rank a book or a quest teaches is not a trainer visit
      if rk and ready and rk.source ~= "book" and rk.source ~= "quest" then
        local key = ("prof:%s:%s"):format(name, tostring(rk.name))
        self:Prune("prof:" .. name .. ":", key)
        if not isDone(key) then
          local tr = PUI and PUI.Trainer and select(2, pcall(PUI.Trainer, PUI, rk)) or nil
          if type(tr) ~= "table" then tr = nil end
          local zone = tr and tr.spot and C.MapName and C.MapName(tr.spot.map) or nil
          out[#out + 1] = { isTrainer = true, kind = "train", trainer = "profession", profession = name, key = key, zone = zone,
            spot = tr and tr.spot or nil, goals = {},
            title = ("Train %s %s%s"):format(rk.name, name, zone and (", " .. zone) or ""),
            detail = ("Up to skill %d, %s"):format(rk.max or 0, money((rk.fee or 0) * 100)),
            why = ("Your %s can go up to %d once you learn %s."):format(name, rk.max or 0, rk.name),
            target = { page = "professions", state = name }, onDone = finish }
        end
      end
    end
  end
  return out
end

-- Every trainer step that applies now, class first.
function TS:Steps()
  if not self:On() or Panoply:PlayAlong() then return {} end
  local out = {}
  local ok, cs = pcall(self.ClassStep, self)
  if not ok then warn("the class trainer step", cs) end
  if ok and cs then out[#out + 1] = cs end
  local okP, ps = pcall(self.ProfSteps, self)
  if not okP then warn("the profession trainer steps", ps) end
  if okP and ps then for _, s in ipairs(ps) do out[#out + 1] = s end end
  return out
end

-- Where in a list of route steps a trainer step goes: before the first step in the trainer's zone, else right after the current
-- step (position 2). `steps` is the look-ahead list, current step first.
function TS.Place(steps, s)
  if s.zone then
    for i = 2, #steps do
      local z = steps[i] and steps[i].zone
      if z and z == s.zone then return i end
    end
  end
  return math.min(2, #steps + 1)
end

-- (A new waiting list or rank brings the step back by itself: its key names the count and cost, or the rank.)
