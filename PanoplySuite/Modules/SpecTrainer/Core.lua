-- Class & Spec (the module key stays spectrainer; 0.7.0 called it Spec & Trainer, SPEC section 22): talent plans, the spell plan by
-- trainer visit (Visits.lua) and the Trainer Helper.
-- Core: the module, talent data access, the rules checker, plans (ready-made, your own, the
-- optional PanoplySuite_SpecPlans file), HP1 import/export, tracking (the next talent), trainer
-- verdicts, spells waiting away from the trainer, money planning and the nearest class trainer.
--
-- Blizzard policy (SPEC 22.1): Panoply Suite never spends talent points and never calls the talent
-- learning API. Trainer purchases happen only in TrainerPanel.lua, one service per player click.
-- Nothing here is protected or changes the game's own frames.
local ADDON, Panoply = ...
local C = Panoply.Compat

local ST = Panoply.Modules:Register({
  key = "spectrainer", label = "Talents & spells", icon = "Train", ownSettingsPage = true,
  desc = "Your talent plan, the next talent at each level, and what your trainers have for you and what it costs.",
  defaults = {
    trainerPanel = true, trainerLearnNext = true, trainerShowSkip = true, trainerProfPanel = true,
    trainerToast = true, trainerArrowOffer = true, trainerMenuLine = true,
    specNextCard = true, specOutline = true,
    trainerMoneyWarn = true, trainerMountFund = true, trainerReserve = 0,
  },
})
Panoply.SpecTrainer = ST
ST.FIRST_LEVEL, ST.LAST_LEVEL, ST.POINTS = 10, 60, 51
ST.MOUNT_LEVEL = 40
-- Apprentice Riding (90g) and a racial mount (10g) at level 40, before reputation discounts: the
-- costs since patch 1.12.1 (warcraft.wiki.gg "Riding"; before 1.12.1 it was 20g + 80g, the same
-- 100g in all). Paladins and warlocks get their mount from their class instead. Only the 100g total
-- is used. [VERIFY IN GAME] the exact trainer price on 1.15.x and Forever.
ST.RIDING_COST, ST.HORSE_COST = 900000, 100000
ST.CLASS_MOUNT = { PALADIN = true, WARLOCK = true }

local function hasBit(mask, bitNo) return math.floor(mask / 2 ^ (bitNo - 1)) % 2 == 1 end

-------------------------------------------------------------------------------
-- Money: "1g 10s", "40s", "9c"
-------------------------------------------------------------------------------
function ST.Money(c)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0
  if neg then c = -c end
  local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  -- two digits after a bigger coin, like "1g 05s" and "3s 07c"
  if s > 0 then out[#out + 1] = (g > 0 and ("%02d"):format(s) or s) .. "s" end
  if k > 0 or #out == 0 then out[#out + 1] = (#out > 0 and ("%02d"):format(k) or k) .. "c" end
  return (neg and "-" or "") .. table.concat(out, " ")
end

-------------------------------------------------------------------------------
-- Player
-------------------------------------------------------------------------------
function ST:Player()
  local p = C.PlayerInfo()
  local level = C.XP()
  p.level = level or 1
  p.money = _G.GetMoney and (GetMoney() or 0) or 0
  return p
end
function ST:ClassFile() return (C.PlayerInfo() or {}).classFile end
ST.CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
                  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

-- Per-character saved state (PanoplySuiteCharDB), created on first use.
function ST:CDB()
  local cdb = Panoply.cdb
  if not cdb then return {} end
  cdb.specPlans = cdb.specPlans or {}         -- [key] = { key, name, class, points = { talent ids } , from }
  cdb.trainerSeen = cdb.trainerSeen or {}     -- ["Name|Rank"] = { cost, level } seen at a real trainer
  return cdb
end

-------------------------------------------------------------------------------
-- Talent data (Data/TalentData.lua): tabs in the game's order, talents in row/column order
-------------------------------------------------------------------------------
ST.trees = {}
function ST:Trees(classFile)
  classFile = classFile or self:ClassFile()
  if self.trees[classFile] then return self.trees[classFile] end
  local raw = Panoply.TalentData and Panoply.TalentData.classes[classFile]
  if not raw then return nil end
  local forever = C.IsForever and C.IsForever()
  local T = { tabs = {}, byId = {}, byName = {} }
  for ti, tab in ipairs(raw) do
    local t = { index = ti, id = tab.id, name = tab.name, talents = {} }
    for li, r in ipairs(tab.talents) do
      local tal = { id = r[1], tier = r[2], col = r[3], key = r[4], name = (forever and r[10]) or r[4], ranks = r[5],
                    prereq = r[6] ~= 0 and r[6] or nil, prereqRank = r[7], spell = r[8], icon = r[9], tab = ti, letter = li }
      t.talents[li] = tal
      T.byId[tal.id] = tal
      T.byName[ti .. ":" .. r[4]] = tal
    end
    T.tabs[ti] = t
  end
  -- Forever names as a second way in, never over an Era name (Forever reuses some Era names)
  for ti, t in ipairs(T.tabs) do
    for li, tal in ipairs(t.talents) do
      local fn = raw[ti].talents[li][10]
      if fn and not T.byName[ti .. ":" .. fn] then T.byName[ti .. ":" .. fn] = tal end
    end
  end
  self.trees[classFile] = T
  return T
end

-- The game's own view of a talent (name, icon, rank) when the talent API is there; matched by tree,
-- row and column, so a renamed talent still lines up.
function ST:LiveTalent(tal)
  if not (_G.GetNumTalents and _G.GetTalentInfo) then return nil end
  local n = GetNumTalents(tal.tab) or 0
  for i = 1, n do
    local name, icon, tier, col, rank, maxRank = GetTalentInfo(tal.tab, i)
    if tier == tal.tier + 1 and col == tal.col + 1 then
      return { index = i, name = name, icon = icon, rank = rank or 0, ranks = maxRank }
    end
  end
  return nil
end

-- Current ranks from the game: { [talent id] = rank }, plus points per tree. nil without the API.
function ST:LiveRanks(classFile)
  local T = self:Trees(classFile)
  if not T or not (_G.GetNumTalentTabs and _G.GetTalentInfo) then return nil end
  local ranks, spent = {}, { 0, 0, 0 }
  for ti, tab in ipairs(T.tabs) do
    local pos = {}
    for _, tal in ipairs(tab.talents) do pos[tal.tier .. ":" .. tal.col] = tal end
    for i = 1, (GetNumTalents(ti) or 0) do
      local _, _, tier, col, rank = GetTalentInfo(ti, i)
      local tal = tier and pos[(tier - 1) .. ":" .. ((col or 1) - 1)]
      if tal and (rank or 0) > 0 then ranks[tal.id] = rank; spent[ti] = spent[ti] + rank end
    end
  end
  return ranks, spent
end

-- Does the game's talent data still match ours? (names may differ; rows, columns and ranks must not)
function ST:DataMatchesGame(classFile)
  local T = self:Trees(classFile)
  if not T or not (_G.GetNumTalentTabs and _G.GetTalentInfo) then return true end
  if (GetNumTalentTabs() or 0) ~= #T.tabs then return false end
  for ti, tab in ipairs(T.tabs) do
    if (GetNumTalents(ti) or 0) ~= #tab.talents then return false end
    for _, tal in ipairs(tab.talents) do
      local live = self:LiveTalent(tal)
      if not live or (live.ranks and live.ranks ~= tal.ranks) then return false end
    end
  end
  return true
end

-------------------------------------------------------------------------------
-- The rules checker (SPEC 22.3.2): row t (0-based) needs 5*t points in that tree first, the
-- prerequisite talent needs its points, and no talent goes past its ranks. 51 points at most.
-- points = { talent id, ... } one per level from 10. Returns true, or nil + a plain message
-- + the index of the first bad point.
-------------------------------------------------------------------------------
function ST:CanAdd(T, ranks, spent, tal)
  local tab = T.tabs[tal.tab]
  if (ranks[tal.id] or 0) >= tal.ranks then
    return nil, ("%s already has all %d points."):format(tal.name, tal.ranks)
  end
  if spent[tal.tab] < tal.tier * 5 then
    return nil, ("%s needs %d points in %s first."):format(tal.name, tal.tier * 5, tab.name)
  end
  if tal.prereq then
    local pre = T.byId[tal.prereq]
    if (ranks[tal.prereq] or 0) < tal.prereqRank then
      return nil, ("%s needs %s %d/%d first."):format(tal.name, pre and pre.name or "another talent", tal.prereqRank, pre and pre.ranks or tal.prereqRank)
    end
  end
  return true
end

function ST:Check(classFile, points)
  local T = self:Trees(classFile)
  if not T then return nil, "No talent data for this class.", 1 end
  if #points > self.POINTS then return nil, ("A plan has at most %d points (levels 10 to 60)."):format(self.POINTS), self.POINTS + 1 end
  local ranks, spent = {}, { 0, 0, 0 }
  for i, id in ipairs(points) do
    local tal = T.byId[id]
    if not tal then return nil, "A talent in this plan is not in the game's talent data.", i end
    local ok, err = self:CanAdd(T, ranks, spent, tal)
    if not ok then return nil, err, i end
    ranks[id] = (ranks[id] or 0) + 1
    spent[tal.tab] = spent[tal.tab] + 1
  end
  return true
end

-- Ranks and points per tree after the first n points of a plan.
function ST:RanksAt(classFile, points, n)
  local T = self:Trees(classFile)
  local ranks, spent = {}, { 0, 0, 0 }
  for i = 1, math.min(n or #points, #points) do
    local tal = T.byId[points[i]]
    if tal then ranks[tal.id] = (ranks[tal.id] or 0) + 1; spent[tal.tab] = spent[tal.tab] + 1 end
  end
  return ranks, spent
end

-- Ready-made steps { tree, talent name, n } to talent ids. The steps are a priority list: the
-- order is fitted to the rules by code (each level takes the first listed point that is legal
-- then), so a write-up never has to count row gates by hand. Returns points, or nil and why.
function ST:Expand(classFile, steps)
  local T = self:Trees(classFile)
  if not T then return nil, "No talent data for " .. tostring(classFile) end
  local want, total = {}, 0
  for _, s in ipairs(steps) do
    local tal = T.byName[s[1] .. ":" .. s[2]]
    if not tal then return nil, ("No talent %q in tree %d."):format(s[2], s[1]) end
    for _ = 1, s[3] do want[#want + 1] = tal end
    total = total + s[3]
  end
  if total ~= self.POINTS then return nil, ("%d points; a full plan has %d."):format(total, self.POINTS) end
  local count = {}
  for _, tal in ipairs(want) do
    count[tal.id] = (count[tal.id] or 0) + 1
    if count[tal.id] > tal.ranks then return nil, ("%s is listed for %d points; it has %d."):format(tal.name, count[tal.id], tal.ranks) end
  end
  local points, used, ranks, spent = {}, {}, {}, { 0, 0, 0 }
  for lv = 1, total do
    local pick, firstErr
    for i, tal in ipairs(want) do
      if not used[i] then
        local ok, err = self:CanAdd(T, ranks, spent, tal)
        if ok then pick = i break end
        firstErr = firstErr or err
      end
    end
    if not pick then return nil, ("level %d: %s"):format(self.FIRST_LEVEL + lv - 1, firstErr) end
    used[pick] = true
    local tal = want[pick]
    points[lv] = tal.id
    ranks[tal.id] = (ranks[tal.id] or 0) + 1
    spent[tal.tab] = spent[tal.tab] + 1
  end
  return points
end

-------------------------------------------------------------------------------
-- Plans
-------------------------------------------------------------------------------
-- Ready-made plans for a class: Panoply Suite basic (Specs.lua) plus the optional data file
-- PanoplySuite_SpecPlans (same shape, from the companion app later). Bad plans are left out with
-- one plain chat line.
function ST:ReadyMade(classFile)
  classFile = classFile or self:ClassFile()
  self.ready = self.ready or {}
  if self.ready[classFile] then return self.ready[classFile] end
  local out = {}
  local S = Panoply.SpecBasic
  for _, d in ipairs(S and S.classes[classFile] or {}) do
    local pts, err = self:Expand(classFile, d.steps)
    if pts then
      out[#out + 1] = { key = d.key, name = d.name, role = d.role, summary = d.summary, trees = d.trees, default = d.default,
                        at60 = d.at60, points = pts, spells = d.spells, why = S.why[classFile], classSpells = S.spells[classFile],
                        class = classFile, source = "basic" }
    else
      Panoply:Debug("spec", d.key, err)
    end
  end
  local file = _G.PanoplySuite_SpecPlans
  if type(file) == "table" and type(file.plans) == "table" and type(file.plans[classFile]) == "table" then
    if (tonumber(file.version) or 0) > 1 then
      self:Notice("PanoplySuite_SpecPlans is newer than this Panoply Suite; its plans are left out.")
    else
      local keys = {}
      for k in pairs(file.plans[classFile]) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do
        local d = file.plans[classFile][k]
        local pts, why, spells = {}, {}, { optional = {}, skip = {} }
        local bad = type(d) ~= "table" or type(d.talents) ~= "table"
        if not bad then
          for i, t in ipairs(d.talents) do
            if type(t) ~= "table" or t[1] ~= self.FIRST_LEVEL + i - 1 then bad = true break end
            pts[i] = t[2]
          end
        end
        if not bad and not self:Check(classFile, pts) then bad = true end
        if bad then
          self:Notice(("The plan %q in PanoplySuite_SpecPlans breaks the talent rules; it is left out."):format(tostring(k)))
        else
          local T = self:Trees(classFile)
          for id, s in pairs(d.why or {}) do local tal = T.byId[id] if tal then why[tal.key] = s end end
          for sid, v in pairs(d.spells or {}) do
            local name = self:SpellNameById(classFile, sid)
            if name and type(v) == "table" then
              if v[1] == "skip" then spells.skip[name] = v[2] or "" elseif v[1] == "optional" then spells.optional[name] = v[2] or "" end
            end
          end
          out[#out + 1] = { key = k, name = d.name or k, role = d.role, summary = d.summary, trees = self:TreeSummary(classFile, pts),
                            points = pts, spells = spells, why = why, classSpells = S and S.spells[classFile], class = classFile,
                            source = file.source or "PanoplySuite_SpecPlans" }
        end
      end
    end
  end
  self.ready[classFile] = out
  return out
end

function ST:Notice(msg)
  self.noticed = self.noticed or {}
  if self.noticed[msg] then return end
  self.noticed[msg] = true
  Panoply:Print(msg)
end

-- Class trainer table (VMaNGOS-derived, so it lives in the PanoplySuite_QuestData data add-on).
-- Without that add-on this is nil and the trainer lists come only from the game's trainer window.
function ST:TrainerTable()
  local qd = rawget(_G, "PanoplySuiteQuestData")
  local t = qd and qd.TrainerData
  return (type(t) == "table" and type(t.classes) == "table") and t or nil
end

function ST:SpellNameById(classFile, sid)
  local td = self:TrainerTable()
  for _, r in ipairs(td and td.classes[classFile] or {}) do if r[5] == sid then return r[2] end end
  return nil
end

function ST:DefaultPlan(classFile)
  local list = self:ReadyMade(classFile)
  for _, p in ipairs(list) do if p.default then return p end end
  return list[1]
end

-- "31 Arms, 20 Fury"
function ST:TreeSummary(classFile, points, n)
  local T = self:Trees(classFile)
  local _, spent = self:RanksAt(classFile, points, n)
  local order = {}
  for i = 1, #T.tabs do if spent[i] > 0 then order[#order + 1] = i end end
  table.sort(order, function(a, b) return spent[a] > spent[b] end)
  local parts = {}
  for _, i in ipairs(order) do parts[#parts + 1] = spent[i] .. " " .. T.tabs[i].name end
  return #parts > 0 and table.concat(parts, ", ") or "No points yet"
end

-- All plans this character can pick: its own (saved) plans first, then the ready-made ones.
function ST:Plans(classFile)
  classFile = classFile or self:ClassFile()
  local cdb = self:CDB()
  local own = {}
  for k, p in pairs(cdb.specPlans) do if p.class == classFile then own[#own + 1] = p end end
  table.sort(own, function(a, b) return (a.name or a.key) < (b.name or b.key) end)
  return own, self:ReadyMade(classFile)
end

function ST:Find(key, classFile)
  if not key then return nil end
  local cdb = self:CDB()
  if cdb.specPlans[key] then return cdb.specPlans[key] end
  for _, p in ipairs(self:ReadyMade(classFile)) do if p.key == key then return p end end
  return nil
end

-- 0.9.5 phase 4H (spec 03 section 3.1): on WoW Forever a character that bought its second specialization has a plan for each spec.
-- Spec 1 keeps the old key (PanoplySuiteCharDB.specTracked); spec 2's plan is a NEW key, specTrackedSpec2. ST:PlanSlot() is the spec
-- the Class page shows (its Spec 1 | Spec 2 switch), else the game's active one; everything that reads "the plan" reads that slot's.
ST.TRACK_KEYS = { "specTracked", "specTrackedSpec2" }
function ST:TrackKey(slot)
  slot = slot or self:PlanSlot()
  return self.TRACK_KEYS[slot] or self.TRACK_KEYS[1]
end
function ST:PlanSlot()
  if self.viewSpec and self:DualSpec() then return self.viewSpec end
  if self:DualSpec() then return self:ActiveSpec() end
  return 1
end

-- The tracked plan: the character's pick, else nil (then the tree with the most points decides).
function ST:Tracked(slot)
  local cdb = self:CDB()
  local p = self:Find(cdb[self:TrackKey(slot)])
  if p and p.class == self:ClassFile() then return p end
  return nil
end

-- 0.9.5 phase 4H (spec 03 section 2.3): a copy of a ready-made plan that is still exactly that plan (the same talents, in any order,
-- under the same name) stands for the ready-made plan; a copy that was edited is the player's own ("Beast Mastery leveling (mine)").
function ST:IsMirror(plan)
  if type(plan) ~= "table" or plan.source ~= "own" or not plan.from then return false end
  local r
  for _, rp in ipairs(self:ReadyMade(plan.class)) do if rp.key == plan.from then r = rp end end
  if not r or plan.name ~= r.name or #(plan.points or {}) ~= #(r.points or {}) then return false end
  local n = {}
  for _, id in ipairs(r.points) do n[id] = (n[id] or 0) + 1 end
  for _, id in ipairs(plan.points) do
    n[id] = (n[id] or 0) - 1
    if n[id] < 0 then return false end
  end
  return true
end

-- Track a plan. A ready-made plan is copied into the character's plans (the original stays as
-- shipped), keeping a link back to its verdicts and reasons.
-- 0.9.5 phase 4H: the copy that is tracked for a ready-made plan is one that is still that plan (ST:IsMirror); an edited copy under the
-- old key ("my-<key>", which older versions edited in place) stays the player's own and a fresh copy is made beside it.
function ST:Track(key, slot)
  local cdb = self:CDB()
  local p = self:Find(key)
  if not p then return nil end
  if p.source ~= "own" then
    local copyKey
    for k, op in pairs(cdb.specPlans) do
      if op.from == p.key and op.class == p.class and self:IsMirror(op) and (not copyKey or k < copyKey) then copyKey = k end
    end
    if not copyKey then
      copyKey = "my-" .. p.key
      local n = 1
      while cdb.specPlans[copyKey] do n = n + 1 copyKey = "my-" .. p.key .. "-" .. n end
      local pts = {}
      for i, v in ipairs(p.points) do pts[i] = v end
      cdb.specPlans[copyKey] = { key = copyKey, name = p.name, class = p.class, points = pts, from = p.key, source = "own" }
    end
    key = copyKey
  end
  cdb[self:TrackKey(slot)] = key
  Panoply:Fire("SPEC_PLAN_CHANGED", key)
  -- the plan you follow starts from the talents you have (SyncPlan, below); a plan that cannot is left for the page to say so
  pcall(self.SyncPlan, self, cdb.specPlans[key])
  return cdb.specPlans[key]
end

-- The ready-made plan a copy came from (for verdicts and reasons), or the plan itself.
function ST:Origin(plan)
  if not plan then return nil end
  if plan.from then return self:Find(plan.from, plan.class) or plan end
  return plan
end

function ST:SavePlan(plan)
  local cdb = self:CDB()
  plan.source = "own"
  if not plan.key then
    local n = 1
    while cdb.specPlans["own-" .. n] do n = n + 1 end
    plan.key = "own-" .. n
  end
  cdb.specPlans[plan.key] = plan
  Panoply:Fire("SPEC_PLAN_CHANGED", plan.key)
  return plan
end

function ST:NewPlan(name, copyFrom)
  local pts = {}
  for i, v in ipairs(copyFrom and copyFrom.points or {}) do pts[i] = v end
  return { name = name or "My plan", class = self:ClassFile(), points = pts, from = copyFrom and (copyFrom.from or (copyFrom.source ~= "own" and copyFrom.key)) or nil, source = "own" }
end

function ST:DeletePlan(key)
  local cdb = self:CDB()
  cdb.specPlans[key] = nil
  for _, k in ipairs(self.TRACK_KEYS) do if cdb[k] == key then cdb[k] = nil end end
  Panoply:Fire("SPEC_PLAN_CHANGED", nil)
end

-------------------------------------------------------------------------------
-- In step with the game (Nov 2026): a saved plan follows the talents the character really has.
-- Compare says how the two differ; FitToTalents re-orders a plan so it starts from the real talents;
-- SyncPlan does that on its own when nothing is lost (the same build, in the order the player took
-- the points) and only reports when the player has points the plan never takes (the player decides:
-- "Match my talents" in the planner). Reading only: Panoply Suite never spends or changes talents.
-------------------------------------------------------------------------------
local function talentOrder(a, b)
  if a.tal.tab ~= b.tal.tab then return a.tal.tab < b.tal.tab end
  if a.tal.tier ~= b.tal.tier then return a.tal.tier < b.tal.tier end
  return a.tal.col < b.tal.col
end

-- { total = points spent in the game, extra = { { tal, n } } points the plan never takes, extraN,
--   early = { { tal, n } } points the plan takes later, earlyN, inStep }. nil without a plan or the talent API.
function ST:Compare(plan, liveRanks)
  plan = plan or self:Tracked()
  if not (plan and plan.points) then return nil end
  local T = self:Trees(plan.class)
  if not T then return nil end
  if not liveRanks then
    if plan.class ~= self:ClassFile() then return nil end
    liveRanks = self:LiveRanks(plan.class)
  end
  if not liveRanks then return nil end
  local total = 0
  for id, r in pairs(liveRanks) do if T.byId[id] then total = total + r end end
  local final = self:RanksAt(plan.class, plan.points)
  local atN = self:RanksAt(plan.class, plan.points, total)
  local out = { total = total, extra = {}, extraN = 0, early = {}, earlyN = 0 }
  for id, r in pairs(liveRanks) do
    local tal = T.byId[id]
    if tal then
      local over = r - (final[id] or 0)
      if over > 0 then out.extra[#out.extra + 1] = { tal = tal, n = over }; out.extraN = out.extraN + over end
      local soon = math.min(r, final[id] or 0) - (atN[id] or 0)
      if soon > 0 then out.early[#out.early + 1] = { tal = tal, n = soon }; out.earlyN = out.earlyN + soon end
    end
  end
  table.sort(out.extra, talentOrder); table.sort(out.early, talentOrder)
  out.inStep = out.extraN == 0 and out.earlyN == 0
  return out
end

-- The plan's points again, starting from the real talents: the points the character has (in the plan's order where the
-- plan has them), then the rest of the plan in its order. Points that no longer fit in 51 are left off the end.
-- Returns points, how many plan points were dropped; nil when the real talents cannot be laid out by the rules.
function ST:FitToTalents(plan, liveRanks)
  local T = self:Trees(plan.class)
  if not T then return nil end
  liveRanks = liveRanks or self:LiveRanks(plan.class)
  if not liveRanks then return nil end
  local first, rest, used = {}, {}, {}
  for _, id in ipairs(plan.points) do
    used[id] = (used[id] or 0) + 1
    if used[id] <= (liveRanks[id] or 0) then first[#first + 1] = id else rest[#rest + 1] = id end
  end
  local extra = {}
  for id, r in pairs(liveRanks) do
    local tal = T.byId[id]
    if tal and r > (used[id] or 0) then extra[#extra + 1] = { tal = tal, n = r - (used[id] or 0) } end
  end
  table.sort(extra, talentOrder)
  for _, x in ipairs(extra) do for _ = 1, x.n do first[#first + 1] = x.tal.id end end
  local points, ranks, spent = {}, {}, { 0, 0, 0 }
  -- each turn takes the first waiting point the rules allow; returns how many could not be placed
  local function lay(list, cap)
    local done, left = {}, #list
    while left > 0 and #points < cap do
      local pick
      for i, id in ipairs(list) do
        if not done[i] and self:CanAdd(T, ranks, spent, T.byId[id]) then pick = i break end
      end
      if not pick then break end
      done[pick] = true; left = left - 1
      local tal = T.byId[list[pick]]
      points[#points + 1] = tal.id
      ranks[tal.id] = (ranks[tal.id] or 0) + 1
      spent[tal.tab] = spent[tal.tab] + 1
    end
    return left
  end
  if lay(first, #first) > 0 then return nil end
  local dropped = lay(rest, self.POINTS)
  return points, dropped
end

-- Keeps a saved plan in step with the real talents. Returns a state and the comparison:
--   "same"      nothing to do            "reordered"  the same build, now in the order the points were taken
--   "differs"   the player has points this plan never takes (left as it is, for the player to see)
--   "matched"   force = true: the plan now starts from the real talents (dropped = plan points left off the end)
-- nil when it cannot tell (no talent API, another class, a ready-made plan: those are never changed).
function ST:SyncPlan(plan, force)
  if not plan or plan.source ~= "own" then return nil end
  local cmp = self:Compare(plan)
  if not cmp then return nil end
  if cmp.inStep then return "same", cmp end
  if cmp.extraN > 0 and not force then return "differs", cmp end
  local pts, dropped = self:FitToTalents(plan)
  if not pts then return "differs", cmp end
  plan.points = pts
  Panoply:Fire("SPEC_PLAN_CHANGED", plan.key)
  return cmp.extraN > 0 and "matched" or "reordered", cmp, dropped
end

-- The plain line about a plan and the real talents: text, differs (true = show it as a warning). nil with nothing to say.
function ST:SyncLine(plan, cmp)
  cmp = cmp or self:Compare(plan)
  if not cmp or cmp.total == 0 then return nil end
  if cmp.extraN > 0 then
    local names = {}
    for i, x in ipairs(cmp.extra) do
      if i > 3 then names[#names + 1] = "and more" break end
      names[#names + 1] = ("%s %d"):format(x.tal.name, x.n)
    end
    return ("Your talents differ from this plan: %d %s not in it (%s)."):format(cmp.extraN,
      cmp.extraN == 1 and "point you have is" or "points you have are", table.concat(names, ", ")), true
  end
  if cmp.earlyN > 0 then
    return ("Your talents are in this plan, in another order (%d %s taken early)."):format(cmp.earlyN, cmp.earlyN == 1 and "point" or "points"), false
  end
  return ("Your talents match this plan so far (%d %s)."):format(cmp.total, cmp.total == 1 and "point" or "points"), false
end

-- The plan you follow is checked whenever the talents change, and once they are readable after login.
function ST:SyncTracked()
  local p = self:Tracked()
  if not p then return nil end
  local ok, state, cmp = pcall(self.SyncPlan, self, p)
  if not ok then Panoply:Debug("spec", "sync", state) return nil end
  if state == "reordered" and self.planner and self.planner:IsShown() and self.edit and self.edit.key == p.key and not self.edit.dirty then
    self:EditPlan(p.key); self:LayoutPlanner()
  end
  return state, cmp
end
ST:On("CHARACTER_POINTS_CHANGED", function() ST:SyncTracked() end)
ST:On("PLAYER_ENTERING_WORLD", function() ST:SyncTracked() end)

-------------------------------------------------------------------------------
-- HP1 text (SPEC 22.3.3): HP1:<CLASS>:<name>:<points>:<check>
-- points: two characters per level from 10, the tree (1-3) and the talent letter (a.. then A..,
-- in row then column order of that tree). check: 4 hex digits over everything before it.
-------------------------------------------------------------------------------
local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
function ST.Checksum(s)
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 65536 end
  return ("%04x"):format(h)
end

function ST:Export(plan)
  local T = self:Trees(plan.class)
  local parts = {}
  for _, id in ipairs(plan.points) do
    local tal = T.byId[id]
    parts[#parts + 1] = tal.tab .. LETTERS:sub(tal.letter, tal.letter)
  end
  local name = (plan.name or "Plan"):gsub("[:|\n]", " ")
  local body = ("HP1:%s:%s:%s"):format(plan.class, name, table.concat(parts))
  return body .. ":" .. ST.Checksum(body)
end

-- Returns a new (unsaved) plan, or nil and a plain message.
function ST:Import(text, classFile)
  classFile = classFile or self:ClassFile()
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cls, name, pts, check = text:match("^HP1:(%u+):([^:]*):([%w]*):(%x%x%x%x)$")
  if not cls then
    if text:match("^HP1:") then return nil, "This text was changed or cut short. Copy the whole line again." end
    if text:match("^HP%d+:") then return nil, "This text is from a newer Panoply Suite. Update Panoply Suite to import it." end
    return nil, "This is not a Panoply Suite plan. Plans start with HP1: (we do not read other build formats)."
  end
  if ST.Checksum(("HP1:%s:%s:%s"):format(cls, name, pts)) ~= check:lower() then
    return nil, "This text was changed or cut short (the check at the end does not match). Copy it again."
  end
  if cls ~= classFile then
    return nil, ("This plan is for a %s; you are a %s."):format(self.CLASS_NAME[cls] or cls, self.CLASS_NAME[classFile] or classFile)
  end
  local T = self:Trees(classFile)
  if not self:DataMatchesGame(classFile) then
    return nil, "Your game's talents differ from Panoply Suite's talent data, so this plan cannot be checked. Update Panoply Suite."
  end
  if #pts % 2 == 1 then return nil, "This text was cut short. Copy it again." end
  local points = {}
  for i = 1, #pts, 2 do
    local tree, letter = tonumber(pts:sub(i, i)), pts:sub(i + 1, i + 1)
    local li = LETTERS:find(letter, 1, true)
    local tab = tree and T.tabs[tree]
    local tal = tab and li and tab.talents[li]
    if not tal then return nil, "This plan names a talent that is not in your game's talent trees. It may be from another game version." end
    points[#points + 1] = tal.id
  end
  local ok, err, at = self:Check(classFile, points)
  if not ok then return nil, ("Level %d: %s The plan is refused."):format(self.FIRST_LEVEL + at - 1, err) end
  return { name = name ~= "" and name or "Imported plan", class = classFile, points = points, source = "own" }
end

-------------------------------------------------------------------------------
-- Tracking: the next talent (SPEC 22.5)
-------------------------------------------------------------------------------
-- Returns { tal, rank, level, index, why, offPlan = { names } } or nil when the plan is done or
-- nothing is learnable. Re-fits from the current talents: points already taken count, points
-- taken elsewhere are reported once and the plan carries on from where it can.
function ST:Next(plan, liveRanks, liveSpent)
  plan = plan or self:Tracked()
  if not plan then return nil end
  local T = self:Trees(plan.class)
  if not liveRanks then liveRanks, liveSpent = self:LiveRanks(plan.class) end
  liveRanks = liveRanks or {}
  if not liveSpent then
    liveSpent = { 0, 0, 0 }
    for id, r in pairs(liveRanks) do local tal = T.byId[id] if tal then liveSpent[tal.tab] = liveSpent[tal.tab] + r end end
  end
  local want, total = {}, 0
  for _, n in ipairs(liveSpent) do total = total + n end
  -- off plan: talents with more points than the plan has after the same number of points
  local planRanks = self:RanksAt(plan.class, plan.points, total)
  local off = {}
  for id, r in pairs(liveRanks) do
    if r > (planRanks[id] or 0) then local tal = T.byId[id] if tal then off[#off + 1] = tal.name end end
  end
  table.sort(off)
  local origin = self:Origin(plan)
  for i, id in ipairs(plan.points) do
    want[id] = (want[id] or 0) + 1
    if (liveRanks[id] or 0) < want[id] then
      local tal = T.byId[id]
      if self:CanAdd(T, liveRanks, liveSpent, tal) then
        return { tal = tal, rank = (liveRanks[id] or 0) + 1, planRank = want[id], level = self.FIRST_LEVEL + i - 1, index = i,
                 why = origin and origin.why and origin.why[tal.key] or nil, offPlan = off, tree = T.tabs[tal.tab].name }
      end
    end
  end
  return nil
end

function ST:UnspentPoints()
  if not _G.UnitCharacterPoints then return 0 end
  return UnitCharacterPoints("player") or 0
end

-- Spec when no plan is tracked: the tree with the most points (SPEC 22.5), else the wizard's pick.
function ST:MainTree()
  local T = self:Trees()
  local _, spent = self:LiveRanks()
  if T and spent then
    local best, bi = 0, nil
    for i, n in ipairs(spent) do if n > best then best, bi = n, i end end
    if bi then return T.tabs[bi].name, best end
  end
  return nil
end

-- The plan whose verdicts sort the trainer: the tracked plan, else the ready-made plan whose main
-- tree matches the tree with the most points, else the class default.
function ST:VerdictPlan()
  local p = self:Tracked()
  if p then return self:Origin(p), "plan" end
  local cls = self:ClassFile()
  local T = self:Trees(cls)
  local _, spent = self:LiveRanks(cls)
  if T and spent then
    local best, bi = 0, nil
    for i, n in ipairs(spent) do if n > best then best, bi = n, i end end
    if bi then
      for _, rp in ipairs(self:ReadyMade(cls)) do
        local _, ps = self:RanksAt(cls, rp.points)
        local top, ti = 0, nil
        for i, n in ipairs(ps) do if n > top then top, ti = n, i end end
        if ti == bi and not rp.at60 then return rp, "talents" end
      end
    end
  end
  return self:DefaultPlan(cls), "default"
end

-------------------------------------------------------------------------------
-- Trainer verdicts (SPEC 22.6.1): Skip only when the plan says so; anything unknown is Recommended.
-------------------------------------------------------------------------------
-- Returns "rec" | "opt" | "skip", and a tag or reason (may be nil).
function ST:Verdict(spellName, plan)
  plan = plan or (self:VerdictPlan())
  if not plan or not spellName then return "rec" end
  local own, cls = plan.spells or {}, plan.classSpells or {}
  if own.skip and own.skip[spellName] then return "skip", own.skip[spellName] end
  if own.optional and own.optional[spellName] then return "opt", own.optional[spellName] end
  if cls.skip and cls.skip[spellName] then return "skip", cls.skip[spellName] end
  if cls.optional and cls.optional[spellName] then return "opt", cls.optional[spellName] end
  return "rec"
end

-- A short line for a Recommended row.
function ST.RankLine(rank)
  local n = rank and tonumber(rank:match("(%d+)"))
  if n and n > 1 then return ("A stronger rank: replaces Rank %d."):format(n - 1) end
  return "New for you."
end

-------------------------------------------------------------------------------
-- Away from the trainer: spells waiting, the next visit, training cost to a level
-------------------------------------------------------------------------------
-- Names of talents that teach a spell (their higher ranks come from the trainer only once you
-- have the talent): every 1-rank talent.
function ST:TalentSpellNames(classFile)
  local T = self:Trees(classFile)
  local out = {}
  for _, tab in ipairs(T and T.tabs or {}) do
    for _, tal in ipairs(tab.talents) do if tal.ranks == 1 then out[tal.key] = tal end end
  end
  return out
end

-- Trainer table rows for this character: race-matched, talent-gated. opts.plan: count talent
-- spells the plan will have by then. Each: { level, name, rank, cost, spell, icon }.
function ST:ClassSpells(opts)
  opts = opts or {}
  local p = opts.player or self:Player()
  local cls = p.classFile
  local td = self:TrainerTable()
  local list = td and td.classes[cls]
  if not list then return {} end
  local gate = self:TalentSpellNames(cls)
  local live = opts.liveRanks or self:LiveRanks(cls) or {}
  local plan = opts.plan
  local seen = self:CDB().trainerSeen or {}
  local out = {}
  for _, r in ipairs(list) do
    local ok = true
    if r[6] ~= 0 and p.raceID then ok = hasBit(r[6], p.raceID) end
    local tal = gate[r[2]]
    if ok and tal then
      local have = (live[tal.id] or 0) > 0
      if not have and plan then
        for i = 1, math.min(#plan.points, math.max(0, r[1] - self.FIRST_LEVEL + 1)) do if plan.points[i] == tal.id then have = true break end end
      end
      ok = have
    end
    if ok then
      local key = r[2] .. "|" .. r[3]
      local s = seen[key]
      out[#out + 1] = { level = r[1], name = r[2], rank = r[3], cost = s and s.cost or r[4], spell = r[5], icon = r[7] }
    end
  end
  return out
end

-- Spells to buy now by your plan (the spells you could learn and do not know, minus the ranks and spells the plan skips or leaves
-- optional: Visits.lua), and the next trainer visit that has something to buy. Home's "spells to buy", the level-up message and the
-- Trainer line all read this, so they always agree with the Class & Spec page.
function ST:Waiting(p)
  p = p or self:Player()
  local sp = self:SpellPlan({ player = p })
  local out = { list = {}, cost = 0, nextLevel = nil, nextList = {}, nextCost = 0 }
  if sp.now then
    out.list, out.cost = ST.VisitRows(sp.now, "buy"), sp.now.buy.cost
  end
  if sp.next then
    out.nextLevel, out.nextList, out.nextCost = sp.next.level, ST.VisitRows(sp.next, "buy"), sp.next.buy.cost
  end
  return out
end

-- Training cost from just above your level up to `to` (inclusive): what the plan buys at the visits in between (Visits.lua), the same
-- numbers as the Class & Spec page. Spells the plan skips or leaves optional are not in it, so the mount saving does not ask for them.
function ST:TrainingCost(from, to, p)
  local sum = 0
  for _, v in ipairs(self:SpellPlan({ player = p, to = to }).visits) do
    if v.level > from and v.level <= to then sum = sum + v.buy.cost end
  end
  return sum
end

-------------------------------------------------------------------------------
-- Money planning (SPEC 22.6.4)
-------------------------------------------------------------------------------
function ST:Reserve() return math.floor((tonumber(Panoply.db and Panoply.db.trainerReserve) or 0) * 10000) end
-- Gold you may spend: your gold minus the reserve (never below 0).
function ST:Spendable(money)
  return math.max(0, (money or (_G.GetMoney and GetMoney()) or 0) - self:Reserve())
end

-- Per-level saving for riding and a mount at 40, or nil (40 or above, setting off, or covered).
function ST:MountSaving(p, spentNow)
  p = p or self:Player()
  if not (Panoply.db and Panoply.db.trainerMountFund) then return nil end
  if p.level >= self.MOUNT_LEVEL then return nil end
  local mount = self.CLASS_MOUNT[p.classFile] and 0 or (self.RIDING_COST + self.HORSE_COST)
  local training = self:TrainingCost(p.level, self.MOUNT_LEVEL, p)
  local have = math.max(0, self:Spendable(p.money) - (spentNow or 0))
  local need = mount + training - have
  if need <= 0 then return 0, mount, training end
  local per = math.ceil(need / (self.MOUNT_LEVEL - p.level) / 100) * 100
  return per, mount, training
end

-- "The ticked spells cost 1g 10s. You keep 35s." (or how much you are short). rec = what the ticked spells cost.
function ST:MoneyLine(rec, money)
  local left = self:Spendable(money) - rec
  if left >= 0 then
    return ("The ticked spells cost %s. You keep %s."):format(ST.Money(rec), ST.Money(left)), true
  end
  return ("The ticked spells cost %s. You are %s short: learn them in order, the rest waits."):format(ST.Money(rec), ST.Money(-left)), false
end

-------------------------------------------------------------------------------
-- Nearest class trainer (by travel time, with the 0.6.0 router), and the arrow
-------------------------------------------------------------------------------
function ST:NearestTrainer()
  local QD, PD = Panoply.QuestData, Panoply.ProfData
  local cls = self.CLASS_NAME[self:ClassFile() or ""]
  if not (cls and QD and QD.Available and QD:Available() and QD.FindTrainers) then return nil end
  local pos = Panoply.State and Panoply.State.pos
  local best, bt
  for _, t in ipairs(QD:FindTrainers(cls)) do
    local secs = PD and PD.Travel and PD.Travel(pos, t.spot) or 1e9
    if not bt or secs < bt then best, bt = t, secs end
  end
  if best then best.seconds = bt end
  return best
end

function ST:PointToTrainer()
  local t = self:NearestTrainer()
  if not (t and t.spot and Panoply.Arrow) then return nil end
  Panoply.Arrow:PointAt(t.spot.map, t.spot.x, t.spot.y, t.name)
  Panoply:Print("Arrow: " .. (t.name or "your trainer") .. ". Your route is not changed.")
  self.pointing = t
  return t
end

-- After the visit the arrow goes back to the route.
function ST:OnTrainerVisited()
  if self.pointing and Panoply.Arrow then
    self.pointing = nil
    Panoply.Arrow:PointAt(nil)
  end
end

-------------------------------------------------------------------------------
-- Module on/off
-------------------------------------------------------------------------------
function ST:Enable() Panoply:Fire("SPEC_TRAINER_CHANGED", true) end
function ST:Disable()
  -- 0.9.5 phase 16: self.panel is the Trainer Helper (classPanel and profPanel are older names that are never set); it closes too
  for _, f in ipairs({ self.panel, self.classPanel, self.profPanel, self.toast, self.card, self.ring }) do if f and f.Hide then f:Hide() end end
  Panoply:Fire("SPEC_TRAINER_CHANGED", false)
end
