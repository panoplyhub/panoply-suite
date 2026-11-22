-- Panoply Suite 0.9.5 phase 4H: the one plan of the Class page (docs/specs/page-redesigns-03-class.md sections 2.2, 2.3, 3.1 and 4).
--
-- One plan control, in the Class page's header, drives the talent tree, the spells to buy, the gear weights and the rotation text.
-- There is no save step:
--   * an edit to one of your own plans is saved as it is made;
--   * an edit to a ready-made plan (or to the copy that stands for it, ST:IsMirror) makes your own copy, "Beast Mastery leveling (mine)",
--     switches to it, and offers Undo (ST.undo; the page shows "Saved as your own copy. Undo"). Ready-made plans are never changed.
-- Plan management (the small ... beside the plan): New plan (empty), Duplicate, Rename, Delete (asks first; a ready-made plan cannot be
-- deleted; deleting the plan that is followed asks which to switch to).
-- WoW Forever, level 40 and up, once the second specialization is bought: Spec 1 | Spec 2, each with its own plan (Core.lua ST:PlanSlot).
--
-- Saved data: nothing is renamed. Plans stay in PanoplySuiteCharDB.specPlans and the followed plan in specTracked (spec 1). New keys:
-- specTrackedSpec2 (spec 2's plan) and specMineV (the one-time naming pass below). Reading only: Panoply Suite never spends or changes
-- talents in the game.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C = Panoply.Compat

ST.MINE = " (mine)"
ST.UNDO_TEXT = "Saved as your own copy."

local function copyPoints(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

-------------------------------------------------------------------------------
-- The second specialization (WoW Forever)
-------------------------------------------------------------------------------
ST.DUAL_SPEC_LEVEL = 40
-- true when this character has bought its second specialization: WoW Forever only, level 40 and up, and the game says it has two spec
-- groups (GetNumSpecGroups; on Classic Era there is no such call and the answer is always false)
function ST:DualSpec()
  if not (C.IsForever and C.IsForever()) then return false end
  if (self:Player().level or 1) < self.DUAL_SPEC_LEVEL then return false end
  local f = C.G("GetNumSpecGroups") or C.G("GetNumTalentGroups")
  if type(f) ~= "function" then return false end
  local ok, n = pcall(f)
  n = ok and tonumber(C.Readable and C.Readable(n) or n) or nil
  return (n or 0) >= 2
end

-- 1 or 2: the spec the game has active now (1 when it does not say)
function ST:ActiveSpec()
  local f = C.G("C_SpecializationInfo.GetActiveSpecGroup") or C.G("GetActiveSpecGroup") or C.G("GetActiveTalentGroup")
  if type(f) ~= "function" then return 1 end
  local ok, n = pcall(f)
  n = ok and tonumber(C.Readable and C.Readable(n) or n) or nil
  return n == 2 and 2 or 1
end

-- the page's Spec 1 | Spec 2 switch (it only shows what each spec's plan is; changing specs is done at the game's own talent window)
function ST:SetViewSpec(slot)
  if slot ~= 1 and slot ~= 2 then return false end
  self.viewSpec = slot
  self.edit, self.undo = nil, nil
  Panoply:Fire("SPEC_PLAN_CHANGED", self:CDB()[self:TrackKey(slot)])
  return true
end
Panoply:On("ACTIVE_TALENT_GROUP_CHANGED", function()
  ST.viewSpec, ST.edit, ST.undo = nil, nil, nil
  Panoply:Fire("SPEC_PLAN_CHANGED", nil)
end)

-------------------------------------------------------------------------------
-- One pass, once (specMineV): a copy that older versions edited in place under "my-<key>" with the ready-made plan's name is the player's
-- own plan now, so it is named "... (mine)". Its key, points and link to the ready-made plan are kept.
-------------------------------------------------------------------------------
function ST:NameMineOnce()
  local cdb = Panoply.cdb
  if not cdb or cdb.specMineV then return 0 end
  cdb.specMineV = 1
  local n = 0
  for key, p in pairs(self:CDB().specPlans) do
    if type(p) == "table" and p.from and p.source == "own" and not self:IsMirror(p) then
      local r = self:Find(p.from, p.class)
      if r and r.source ~= "own" and p.name == r.name then
        p.name = self:UniqueName(r.name .. self.MINE, p.class, key)
        n = n + 1
      end
    end
  end
  return n
end
-- (run the first time the plans are asked for on a character, when its saved data is there: ST:ActivePlan, ST:PlanItems)
local function mineOnce() if Panoply.cdb and not Panoply.cdb.specMineV then pcall(ST.NameMineOnce, ST) end end

-- a plan name nobody else of this class uses: "Name", else "Name 2", "Name 3" ... (except is a key whose own name does not count)
function ST:UniqueName(name, classFile, except)
  classFile = classFile or self:ClassFile()
  local taken = {}
  local own, ready = self:Plans(classFile)
  for _, p in ipairs(own) do if p.key ~= except then taken[p.name or ""] = true end end
  for _, p in ipairs(ready) do taken[p.name or ""] = true end
  if not taken[name] then return name end
  local i = 2
  while taken[name .. " " .. i] do i = i + 1 end
  return name .. " " .. i
end

-------------------------------------------------------------------------------
-- The plan dropdown
-------------------------------------------------------------------------------
-- The plan the page shows: the followed plan, else the class default (a ready-made plan; a first edit makes your own copy of it)
function ST:ActivePlan()
  mineOnce()
  return self:Tracked() or self:DefaultPlan()
end

-- the dropdown's choices: the ready-made plans, then your own (an untouched copy of a ready-made plan is that plan, not listed twice)
function ST:PlanItems()
  mineOnce()
  local own, ready = self:Plans()
  local out = {}
  for _, p in ipairs(ready) do
    out[#out + 1] = { text = p.name, value = p.key, tip = p.summary, ready = true }
  end
  for _, p in ipairs(own) do
    if not self:IsMirror(p) then
      out[#out + 1] = { text = p.name or p.key, value = p.key, tip = ("Your own plan: %s."):format(self:TreeSummary(p.class, p.points or {})) }
    end
  end
  return out
end

-- the value the dropdown shows (a ready-made key for an untouched copy), or nil when no plan is followed yet
function ST:PlanValue()
  local t = self:Tracked()
  if not t then return nil end
  if self:IsMirror(t) then return t.from end
  return t.key
end

-- the plan's name for the header ("Beast Mastery leveling"); "No plan yet" when none is followed
function ST:PlanName()
  local t = self:Tracked()
  return t and (t.name or t.key) or "No plan yet"
end

-- picking a plan in the dropdown: it is followed at once (talent hints, trainer, gear weights all follow it)
function ST:ChoosePlan(value)
  self.undo = nil
  local p = self:Track(value)
  self.edit = nil
  return p
end

-------------------------------------------------------------------------------
-- Editing without a save step
-------------------------------------------------------------------------------
-- The plan the talent tree edits: always the plan the page shows (a working copy of it, ST.edit, so a click that the talent rules refuse
-- changes nothing). Called by the Talents tab before it draws.
function ST:EditActive()
  local p = self:ActivePlan()
  local e = self.edit
  if not p then
    if not e then self:EditPlan(nil) end
    return self.edit
  end
  if not e or e.key ~= p.key or e.class ~= p.class then
    local keep = self.showLevel
    self:EditPlan(p.key)
    if keep and e and e.class == p.class then self.showLevel = keep end
  end
  return self.edit
end

-- After an edit to ST.edit (a talent added or taken back, Match my talents, Reset, Import): keep it. Returns "saved" (your own plan was
-- changed), "copied" (a ready-made plan was edited, so your own copy was made and followed; ST.undo can take it back) or nil.
function ST:Commit()
  local e = self.edit
  if not e then return nil end
  local cdb = self:CDB()
  local tk = self:TrackKey()
  local cur = self:Tracked()
  if cur and cur.key == e.key and cur.source == "own" and not self:IsMirror(cur) then
    cur.points = copyPoints(e.points)
    self:SavePlan(cur)
    e.dirty = nil
    -- a further edit to the copy Undo would remove: Undo is withdrawn, so it can never throw those edits away (the copy stays yours)
    if self.undo and self.undo.made == cur.key then self.undo = nil end
    return "saved"
  end
  -- a ready-made plan, the untouched copy that stands for one, or no plan yet (the class default): your own copy, followed
  local origin = cur or self:Find(e.key, e.class) or self:DefaultPlan(e.class)
  local readyKey = origin and (origin.source ~= "own" and origin.key or origin.from) or nil
  local base = origin and origin.name or e.name or "My plan"
  local plan = self:SavePlan({ name = self:UniqueName(base .. self.MINE, e.class), class = e.class, points = copyPoints(e.points),
    from = readyKey, source = "own" })
  local prev = cdb[tk]
  cdb[tk] = plan.key
  Panoply:Fire("SPEC_PLAN_CHANGED", plan.key)
  self.undo = { prev = prev, made = plan.key, slot = self:PlanSlot(), name = plan.name }
  local keep = self.showLevel
  self:EditPlan(plan.key)
  self.showLevel = keep or self.showLevel
  return "copied"
end

-- Undo of "Saved as your own copy": the copy is removed and the plan that was followed before is followed again
function ST:Undo()
  local u = self.undo
  if not u then return false end
  self.undo = nil
  local cdb = self:CDB()
  cdb.specPlans[u.made] = nil
  local tk = self:TrackKey(u.slot)
  if cdb[tk] == u.made then cdb[tk] = u.prev end
  Panoply:Fire("SPEC_PLAN_CHANGED", u.prev)
  self.edit = nil
  self:EditActive()
  self:Say("Your own copy was removed. Back to " .. (self:PlanName()) .. ".")
  return true
end

-- the talent tree's clicks: add the plan's next rank of a talent, or take its last one back, and keep the result
function ST:AddAndKeep(id)
  self:EditActive()
  local ok = self:AddPoint(id)
  if ok then return self:Commit() end
  return nil
end
function ST:RemoveAndKeep(id)
  self:EditActive()
  local ok = self:RemovePoint(id)
  if ok then return self:Commit() end
  return nil
end
function ST:MatchAndKeep()
  self:EditActive()
  local ok = self:MatchEdit()
  if ok and self.edit and self.edit.dirty then
    local msg = self.plannerMsg
    local r = self:Commit()
    -- (the planner's own words end with "Save to keep it"; there is no save step now: it is kept)
    if msg then self:Say((msg.text:gsub(" Save to keep it%.", "")), msg.bad) end
    return r
  end
  return nil
end
function ST:ResetAndKeep()
  self:EditActive()
  self:ResetEdit()
  local r = self:Commit()
  self:Say("Every point taken out. Click talents to start again.")
  return r
end
function ST:ImportAndKeep(text)
  local e = self:ImportEdit(text)
  if not e then return nil end
  -- an imported plan is always a new plan of your own, followed
  local plan = self:SavePlan({ name = self:UniqueName(e.name or "Imported plan", e.class), class = e.class, points = copyPoints(e.points),
    from = e.from, source = "own" })
  self:Track(plan.key)
  self.undo = nil
  self:EditPlan(plan.key)
  self:Say(("Imported \"%s\" (%d points) as a plan of your own, and following it."):format(plan.name, #plan.points))
  return plan
end

-------------------------------------------------------------------------------
-- Plan management (the ... beside the plan)
-------------------------------------------------------------------------------
-- New plan: an empty plan of your own, followed
function ST:NewEmptyPlan()
  local own = self:Plans()
  local plan = self:SavePlan({ name = self:UniqueName("My plan " .. (#own + 1)), class = self:ClassFile(), points = {}, source = "own" })
  self:Track(plan.key)
  self.undo = nil
  self:EditPlan(plan.key)
  self.showLevel = self.FIRST_LEVEL - 1
  self:Say("An empty plan. Click talents in the order you want them.")
  return plan
end

-- Duplicate: a copy of the plan the page shows, named "... copy", followed
function ST:DuplicatePlan()
  local p = self:ActivePlan()
  if not p then return nil end
  local readyKey = p.source ~= "own" and p.key or p.from
  local plan = self:SavePlan({ name = self:UniqueName((p.name or "My plan") .. " copy", p.class), class = p.class, points = copyPoints(p.points),
    from = readyKey, source = "own" })
  self:Track(plan.key)
  self.undo = nil
  self:EditPlan(plan.key)
  self:Say(("Made \"%s\" and following it."):format(plan.name))
  return plan
end

-- can this plan be renamed or deleted? (only your own; an untouched copy of a ready-made plan is that plan)
function ST:IsOwnPlan(p)
  return type(p) == "table" and p.source == "own" and not self:IsMirror(p)
end

-- Rename: returns the new name, or nil and the reason
function ST:RenamePlan(key, text)
  local p = self:CDB().specPlans[key or ""]
  if not self:IsOwnPlan(p) then return nil, "A ready-made plan keeps its name. Edit it to make your own copy." end
  local name = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "Type a name first." end
  if #name > 40 then return nil, "That name is longer than 40 letters." end
  if name:find("[%c|]") then return nil, "A plan name cannot have that character." end
  local unique = self:UniqueName(name, p.class, key)
  if unique ~= name then return nil, "Another plan already has that name." end
  p.name = name
  Panoply:Fire("SPEC_PLAN_CHANGED", key)
  if self.edit and self.edit.key == key then self.edit.name = name end
  return name
end

-- Delete: your own plans only. switchTo: the plan to follow instead when the deleted one was followed (a ready-made or own key, or nil to
-- follow none). Returns true, or nil and the reason.
function ST:DeleteOwnPlan(key, switchTo)
  local cdb = self:CDB()
  local p = cdb.specPlans[key or ""]
  if not p then return nil, "That plan is gone." end
  if not self:IsOwnPlan(p) then return nil, "A ready-made plan cannot be deleted." end
  local wasFollowed = {}
  for slot, k in ipairs(self.TRACK_KEYS) do if cdb[k] == key then wasFollowed[#wasFollowed + 1] = slot end end
  self:DeletePlan(key)
  if self.undo and self.undo.made == key then self.undo = nil end
  if switchTo and switchTo ~= key then
    for _, slot in ipairs(wasFollowed) do self:Track(switchTo, slot) end
  end
  self.edit = nil
  return true
end

-- the plans to switch to when the followed plan is deleted: every other choice of the dropdown
function ST:SwitchChoices(except)
  local out = {}
  for _, it in ipairs(self:PlanItems()) do if it.value ~= except then out[#out + 1] = it end end
  return out
end
