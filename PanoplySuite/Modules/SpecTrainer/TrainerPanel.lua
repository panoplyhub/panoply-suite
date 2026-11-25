-- Spec & Trainer: the Trainer Helper panel beside the game's trainer window (SPEC 22.6).
--
-- Blizzard policy: learning a spell is the player's action. The ONLY call to BuyTrainerService in
-- Panoply Suite is ST:Learn below, reached only from a Learn / "Learn next" button's OnClick: one
-- click, one service. Never from an event, a timer or a loop, and never in combat. The panel only
-- reads the trainer (GetTrainerService*); it never changes the trainer window's filters.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C, Skin = Panoply.Compat, Panoply.Skin
local U = ST.UI
local PANEL_W, PANEL_MAX_H = 420, 556

-------------------------------------------------------------------------------
-- Reading the trainer
-------------------------------------------------------------------------------
-- Services you can learn now: { index, name, rank, cost, icon, level }. Second result: what you learned from this panel during this visit
-- ({ name, rank, cost, icon }, in the order you clicked) that the trainer no longer offers, so the panel can say Learned. The game lists a
-- learned spell as "used" or, when its list is filtered, not at all; either way it is no longer available.
function ST:ReadTrainer()
  local out, learned = {}, {}
  if not (_G.GetNumTrainerServices and _G.GetTrainerServiceInfo) then return out, learned end
  local seen = self:CDB().trainerSeen
  local offered = {}
  for i = 1, (GetNumTrainerServices() or 0) do
    local name, rank, kind = GetTrainerServiceInfo(i)
    if name and kind == "available" then
      local cost = _G.GetTrainerServiceCost and (GetTrainerServiceCost(i)) or 0
      local lvl = _G.GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
      out[#out + 1] = { index = i, name = name, rank = rank or "", cost = cost or 0,
                        icon = _G.GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil, level = lvl }
      offered[name .. "|" .. (rank or "")] = true
      -- the real price for "away from the trainer" sums (SPEC 22.6.3)
      if seen then seen[name .. "|" .. (rank or "")] = { cost = cost or 0, level = lvl } end
    end
  end
  for key, row in pairs(self.learnedHere or {}) do
    if not offered[key] then learned[#learned + 1] = row end
  end
  table.sort(learned, function(a, b) return a.order < b.order end)
  return out, learned
end

function ST:IsProfessionTrainer()
  return _G.IsTradeskillTrainer and IsTradeskillTrainer() and true or false
end

-- Index of a service by name and rank, read again at click time (the list can change between the
-- panel being drawn and the click).
function ST:FindService(name, rank)
  if not (_G.GetNumTrainerServices and _G.GetTrainerServiceInfo) then return nil end
  for i = 1, (GetNumTrainerServices() or 0) do
    local n, r, kind = GetTrainerServiceInfo(i)
    if n == name and (r or "") == (rank or "") then return i, kind end
  end
  return nil
end

-- The player's click on Learn: one service, once. Returns true when the purchase was asked for.
function ST:Learn(name, rank)
  if C.InCombat() then
    Panoply:Print("Not during a fight. Learn it when the fight is over.")
    return false
  end
  local i, kind = self:FindService(name, rank)
  if not i or kind ~= "available" then
    Panoply:Print((name or "That spell") .. " is not available at this trainer now.")
    return false
  end
  local cost, isProfession = 0, false
  if _G.GetTrainerServiceCost then cost, isProfession = GetTrainerServiceCost(i) end
  cost = cost or 0
  -- Learning a whole new profession: the game's own Train button asks the player to confirm
  -- (it counts against the two primary professions), so Panoply Suite never buys that one itself.
  if isProfession then
    Panoply:Print("To learn " .. (name or "a new profession") .. ", use the trainer's own Train button so the game can ask you to confirm.")
    return false
  end
  if _G.GetMoney and (GetMoney() or 0) < (cost or 0) then
    Panoply:Print("Not enough money for " .. name .. " (" .. ST.Money(cost) .. ").")
    return false
  end
  if not _G.BuyTrainerService then return false end
  BuyTrainerService(i)
  -- the panel says Learned for it once the trainer stops offering it (ST:ReadTrainer)
  self.learnedHere = self.learnedHere or {}
  self.learnedCount = (self.learnedCount or 0) + 1
  self.learnedHere[(name or "") .. "|" .. (rank or "")] = { name = name, rank = rank or "", cost = cost,
    icon = _G.GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil, order = self.learnedCount }
  return true
end

-------------------------------------------------------------------------------
-- Class trainer: Buy now (rec) / Optional / Skipped by your plan
-------------------------------------------------------------------------------
-- p = the player: then the rank rule of Visits.lua applies too (a rank the plan has no use for goes to skip with its reason). Without
-- p only the plan's own optional / skip lists decide.
function ST:ClassGroups(services, plan, p)
  local groups = { rec = {}, opt = {}, skip = {} }
  local sums = { rec = 0, opt = 0, skip = 0 }
  local index
  if p then index = self:RankIndex(self:ClassSpells({ player = p, plan = self:Tracked() })) end
  for _, s in ipairs(services) do
    local v, why = self:Verdict(s.name, plan)
    if v == "rec" and index then
      local list = index[s.name]
      local row = ST.MatchRow(list, s.rank, s.level)
      if row then
        local covered = ST.RankCovered(list, row, p.level, C.KnowsSpell)
        if covered then v, why = "skip", ("You already know Rank %d."):format(covered.n)
        else
          local r2 = self:RankSkip(list, row, p.level)
          if r2 then v, why = "skip", r2 end
        end
      end
    end
    local reason = v == "rec" and ST.RankLine(s.rank) or (v == "skip" and why or nil)
    local tag = v == "opt" and why or (v == "skip" and "skip" or nil)
    local row = { s.name, s.rank, s.cost, s.icon, reason, tag, s = s }
    table.insert(groups[v], row)
    sums[v] = sums[v] + s.cost
  end
  return groups, sums
end

function ST.TrainerTitle()
  local n = _G.UnitName and UnitName("npc") or nil
  local zone = C.ZoneText()
  if n and zone ~= "" then return n .. ", " .. zone end
  return n or zone
end

function ST:PanelAnchor(f)
  local tf = _G.ClassTrainerFrame
  f:ClearAllPoints()
  if tf and tf.IsShown and tf:IsShown() then f:SetPoint("TOPLEFT", tf, "TOPRIGHT", 8, 0)
  else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 392, -104) end
end

-- 0.9.5 phase 16 (our bug, 2026-11-15: it would not close until /reload). The panel closes with its own close button, with Esc and
-- when the trainer window closes (TRAINER_CLOSED, the game's trainer frame hiding, or the interaction manager saying the trainer
-- is gone). Once the player has closed it, nothing opens it again during that visit: only the next TRAINER_SHOW does.
function ST:PanelFrame()
  if self.panel then return self.panel end
  local f = CreateFrame("Frame", "PanoplySuiteTrainerPanel", UIParent)
  f.panoplyBox = true
  f:SetFrameStrata("HIGH")
  Skin.Panel(f, 0.97, true, "M")
  f:EnableMouse(true)
  local close = Skin.IconButton(f, "x", 24, function() ST:ClosePanel() end, "Close",
    "Close the Trainer Helper. It opens again the next time you talk to a trainer.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
  close:SetFrameLevel(f:GetFrameLevel() + 10)
  f.panoplyClose = close
  f:Hide()
  -- Esc (the game hides it through its Esc list, joined by Skin.Popups:Special below): a hide the panel did not ask for itself counts as the player closing it
  f:HookScript("OnHide", function() if not ST.panelHiding then ST.panelDismissed = true end end)
  self.panel = f
  if Skin.Popups and Skin.Popups.Special then Skin.Popups:Special("PanoplySuiteTrainerPanel") end
  return f
end

-- Hides the panel without counting it as the player closing it (a setting switched off, a redraw).
function ST:HidePanel()
  if not (self.panel and self.panel:IsShown()) then return end
  self.panelHiding = true
  self.panel:Hide()
  self.panelHiding = nil
end

-- The player closed it: it stays closed until the next trainer visit.
function ST:ClosePanel()
  self.panelDismissed = true
  if self.panel then self.panel:Hide() end
end

-- The trainer is gone (however the game said so): the panel closes and nothing reopens it until the next TRAINER_SHOW.
function ST:TrainerGone()
  local was = self.atTrainer
  self.atTrainer = nil
  self:HidePanel()
  if was and self:IsOn() then Panoply:Fire("SPEC_TRAINER_CHANGED", true) end
end

-- The game's trainer window (Blizzard_TrainerUI, loaded on first use): when it hides, the trainer is closed.
function ST:HookTrainerFrame()
  local tf = _G.ClassTrainerFrame
  if not (tf and tf.HookScript) or tf.panoplyTrainerHooked then return end
  tf.panoplyTrainerHooked = true
  -- looked at a frame later, so a hide and show in one go (the game swapping one trainer for the next) does not count
  tf:HookScript("OnHide", function()
    C.After(0, function() if ST.atTrainer and not tf:IsShown() then ST:TrainerGone() end end)
  end)
end

-- Builds the class panel from the live trainer (docs/step2/ABC-SPEC.md C-03). Returns the frame.
--   Buy now           what your plan says to buy now: a tick, the icon, the name and rank, the price and a Learn button (one click, one
--                     spell). After a click the row says Learned.
--   Optional          spells your plan leaves to you (a Learn button too)
--   Next visit        the next trainer visit that has something to buy, grey, with the prices so you can save up
--   Skipped           what your plan skips, with the reason
function ST:ShowClassPanel()
  local db = Panoply.db or {}
  local p = self:Player()
  local plan, from = self:VerdictPlan()
  local services, learned = self:ReadTrainer()
  local groups, sums = self:ClassGroups(services, plan, p)
  -- what was learned here stays in its own group: an optional spell under Optional, the rest under Buy now
  local learnedBuy, learnedOpt = {}, {}
  for _, s in ipairs(learned) do
    local list = self:Verdict(s.name, plan) == "opt" and learnedOpt or learnedBuy
    list[#list + 1] = s
  end
  local upcoming = self:SpellPlan({ player = p, plan = plan, how = from }).next
  local spend = self:Spendable(p.money)
  local f = self:PanelFrame()
  self.panelKind = "class"
  local planName = plan and plan.name or "none"
  if from == "talents" then planName = planName .. " (from your talents)" end
  -- 0.9.9.4: the spells named for the build they come from ("Spells for your Survival leveling build (Icy Veins)"), and its card
  local buildWords, build = self:BuildWords()
  local noun = (build and build.source == "public") and "build" or "plan"
  local headSub = (build and build.source == "public") and ("Spells for " .. buildWords .. ".") or ("Plan: " .. planName .. ".")
  local function top(c, x, w, y)
    y = U.Header(c, x, y, w - 24, "Trainer Helper", (ST.TrainerTitle() or "Your trainer") .. ". " .. headSub)
    if build and build.source == "public" then
      local card = ST:BuildCard(c, { mode = "line" })
      card:Set(ST:BuildFacts(build))
      local ch = card:Fit(w)
      card:SetPoint("TOPLEFT", c, "TOPLEFT", x, y)
      self.panelBuildCard = card
      y = y - ch - Skin.SP.s
    else self.panelBuildCard = nil end
    y = U.Pair(c, x, y, w, "Your gold", ST.Money(p.money), nil, Skin.colors.text)
    if self:Reserve() > 0 then y = U.Pair(c, x, y, w, "Kept aside", ST.Money(self:Reserve()), nil, Skin.colors.inkSoft, 11) end
    if #services == 0 and #learned == 0 then
      return U.Block(c, x, y - 2, w, 11, Skin.colors.ink, "Nothing new to learn here right now.") - Skin.SP.m
    end
    local line, color
    if #groups.rec > 0 then
      local s, ok = self:MoneyLine(sums.rec, p.money)
      if db.trainerMoneyWarn == false and not ok then s = "Learn the ticked spells in order." end
      line, color = s, ok and Skin.colors.done or Skin.colors.warn
    elseif #learnedBuy > 0 then
      line, color = ("Everything your %s says to buy here is learned."):format(noun), Skin.colors.done
    else
      line, color = ("Your %s has nothing to buy here right now."):format(noun), Skin.colors.ink
    end
    return U.Block(c, x, y - 2, w, 11, Skin.colors.ink, Skin.Code(color) .. line .. "|r") - Skin.SP.m
  end
  local function list(c, x, w, y)
    self.learnButtons = {}
    local function learnRow(r, opts)
      local b
      opts.spendable, opts.onClick = spend, function() ST:Learn(r[1], r[2]) end
      y, b = U.ServiceRow(c, x, y, w, r, opts)
      b.panoplyService = r
      self.learnButtons[#self.learnButtons + 1] = b
    end
    if #groups.rec > 0 or #learnedBuy > 0 then
      y = U.GroupHead(c, x, y, w, "Buy now", #groups.rec > 0 and #groups.rec or nil, sums.rec, Skin.colors.heading)
      for _, s in ipairs(learnedBuy) do
        y = U.ServiceRow(c, x, y, w, { s.name, s.rank, s.cost, s.icon }, { tick = "learned", learned = true, noReason = true })
      end
      for _, r in ipairs(groups.rec) do learnRow(r, { tick = "buy", noReason = true }) end
      y = y - Skin.SP.xs
    end
    if #groups.opt > 0 or #learnedOpt > 0 then
      y = U.GroupHead(c, x, y, w, "Optional", #groups.opt > 0 and #groups.opt or nil, sums.opt, Skin.colors.goldBright)
      for _, s in ipairs(learnedOpt) do
        y = U.ServiceRow(c, x, y, w, { s.name, s.rank, s.cost, s.icon }, { tick = "learned", learned = true, compact = true })
      end
      for _, r in ipairs(groups.opt) do learnRow(r, { tick = "opt", compact = true }) end
      y = y - Skin.SP.xs
    end
    if upcoming then
      y = U.GroupHead(c, x, y, w, ("Next visit: level %d"):format(upcoming.level), upcoming.buy.n, upcoming.buy.cost, Skin.colors.inkSoft)
      for _, r in ipairs(ST.VisitRows(upcoming, "buy")) do
        y = U.ServiceRow(c, x, y, w, { r.name, r.rank or "", r.cost, r.icon }, { tick = "later", noButton = true, compact = true, dim = true })
      end
      y = y - Skin.SP.xs
    end
    if #groups.skip > 0 and db.trainerShowSkip ~= false then
      y = U.GroupHead(c, x, y, w, "Skipped by your " .. noun, nil, nil, Skin.colors.inkSoft)
      for _, r in ipairs(groups.skip) do y = U.SkipRow(c, x, y, w, r) end
    end
    if #services == 0 and #learned == 0 then
      y = U.Block(c, x, y, w, 11, Skin.colors.inkSoft, "Come back when you level up; the line below says when.") - Skin.SP.s
    end
    return y
  end
  local function foot(ft, x, w, y)
    U.Rule(ft, x, y, w); y = y - Skin.SP.s
    local first = groups.rec[1]
    self.learnNext = nil
    if first and db.trainerLearnNext ~= false then
      local label = "Learn next: " .. first[1] .. ((first[2] ~= "" and (" (" .. first[2] .. ")")) or "") .. ", " .. ST.Money(first[3])
      local nb = Skin.Button(ft, label, 200, 28, function() ST:Learn(first[1], first[2]) end, "Learn next",
        "Learns the first ticked spell you do not have yet. One click, one spell; click again for the next one. Panoply Suite never buys on its own.")
      Skin.FitButton(nb, 200, w)
      nb:SetEnabledLook(spend >= first[3])
      nb:SetPoint("TOPLEFT", ft, "TOPLEFT", x, y)
      nb.panoplyService = first
      self.learnNext = nb
      y = y - nb:GetHeight() - Skin.SP.s
    end
    if upcoming then
      y = U.Pair(ft, x, y, w, ("Next visit: level %d, %d spell%s"):format(upcoming.level, upcoming.buy.n, upcoming.buy.n == 1 and "" or "s"), ST.Money(upcoming.buy.cost), Skin.colors.ink)
    end
    local per = self:MountSaving(p, sums.rec)
    if per and per > 0 then
      y = U.Pair(ft, x, y, w, "Mount at 40: put aside each level", ST.Money(per), Skin.colors.ink)
    end
    return y
  end
  U.ListPanel(f, PANEL_W, self:PanelMaxH(), top, list, foot)
  self:PanelAnchor(f)
  f:Show()
  return f
end

function ST:PanelMaxH()
  local tf = _G.ClassTrainerFrame
  local sh = _G.UIParent and UIParent:GetHeight() or 668
  local topY = (tf and tf.GetTop and tf:IsShown() and tf:GetTop()) or (sh - 104)
  return math.max(300, math.min(PANEL_MAX_H, (topY or sh) - 8))
end

-------------------------------------------------------------------------------
-- Profession trainer: your plan's recipes first (SPEC 22.6.2)
-------------------------------------------------------------------------------
function ST:WhichProfession(services)
  local PD = Panoply.ProfData
  if not PD or not PD.SKILL_LINES then return nil end
  local best, bn = nil, 0
  for prof in pairs(PD.SKILL_LINES) do
    local d = PD[prof]
    if d and d.recipes then
      local names = {}
      for _, r in ipairs(d.recipes) do names[r.name] = true end
      local n = 0
      for _, s in ipairs(services) do if names[s.name] or s.name:find(prof, 1, true) then n = n + 1 end end
      if n > bn then best, bn = prof, n end
    end
  end
  return best
end

function ST:ProfessionGroups(profName, services, skill, max, level)
  local PD, PR = Panoply.ProfData, Panoply.Professions
  local prof = PD[profName] or {}
  local byName = {}
  for _, r in ipairs(prof.recipes or {}) do byName[r.name] = r end
  local uses = {}
  local plan = PR and PR.Plan and PR:Plan(profName, { from = math.max(1, skill or 1), to = math.min(300, (max or 75) + 75), level = level, maxKnown = max })
  for _, sg in ipairs(plan and plan.segments or {}) do if sg.name and not uses[sg.name] then uses[sg.name] = sg end end
  local rows = { uses = {}, opt = {}, skip = {}, ranks = {} }
  for _, s in ipairs(services) do
    local r = byName[s.name]
    local ent = { s.name, "", s.cost, s.icon, nil, nil, s = s }
    if not r then
      ent[5] = "A new rank: you can raise your skill further."
      rows.ranks[#rows.ranks + 1] = ent
    elseif uses[s.name] then
      local sg = uses[s.name]
      ent[5] = ("Plan: make about %d (skill %d to %d)."):format(sg.count or 0, sg.from or skill, sg.to or skill)
      rows.uses[#rows.uses + 1] = ent
    elseif (r.yellow or 0) > (skill or 0) then
      ent[6] = ("points to %d"):format(r.grey or 0)
      rows.opt[#rows.opt + 1] = ent
    else
      ent[6] = (r.grey or 0) <= (skill or 0) and "grey now" or ("grey at %d"):format(r.grey or 0)
      rows.skip[#rows.skip + 1] = ent
    end
  end
  table.sort(rows.opt, function(a, b) return a[3] < b[3] end)
  rows.more = math.max(0, #rows.opt - 3)
  rows.allOpt = {}
  for i, v in ipairs(rows.opt) do rows.allOpt[i] = v end
  if not self.showAllOptional then for i = #rows.opt, 4, -1 do table.remove(rows.opt, i) end else rows.more = 0 end
  -- a new rank goes first in "Your plan uses": nothing else gives points past the cap
  for i = #rows.ranks, 1, -1 do table.insert(rows.uses, 1, rows.ranks[i]) end
  return rows, plan
end

function ST:ShowProfessionPanel()
  local p = self:Player()
  local services = self:ReadTrainer()
  local profName = self:WhichProfession(services)
  local PR, PD = Panoply.Professions, Panoply.ProfData
  local skill, max = 0, 0
  if profName and PR then skill, max = PR:CurrentSkill(profName) end
  skill, max = skill or 0, max or 0
  local rows = self:ProfessionGroups(profName or "", services, skill, max, p.level)
  local spend = self:Spendable(p.money)
  local planCost = 0
  for _, s in ipairs(rows.uses) do planCost = planCost + s[3] end
  local f = self:PanelFrame()
  self.panelKind = "profession"
  local function top(c, x, w, y)
    local sub = (ST.TrainerTitle() or "Your trainer") .. "." .. (profName and (" " .. profName .. " " .. skill .. " / " .. max .. ".") or "")
    y = U.Header(c, x, y, w - 24, "Trainer Helper", sub)
    if max > 0 then
      local bar = Skin.Bar(c, 6)
      bar:SetPoint("TOPLEFT", c, "TOPLEFT", x, y + 2); bar:SetWidth(w); bar.panoplyWidth = w
      bar:SetProgress(skill / max)
      y = y - 6 - Skin.SP.m
    end
    y = U.Pair(c, x, y, w, "Your gold", ST.Money(p.money), nil, Skin.colors.text)
    local left = spend - planCost
    local line = left >= 0 and (Skin.Code(Skin.colors.done) .. "Your plan's recipes: " .. ST.Money(planCost) .. ", you keep " .. ST.Money(left) .. ".|r")
      or (Skin.Code(Skin.colors.warn) .. ST.Money(-left) .. " short for your plan's recipes.|r Learn them in order.")
    return U.Block(c, x, y - 2, w, 11, Skin.colors.ink, line) - Skin.SP.m
  end
  local function list(c, x, w, y)
    local groups = { { "Your plan uses", rows.uses, Skin.colors.heading }, { "Optional", rows.opt, Skin.colors.goldBright, rows.more },
                     { "Skip (no skill points soon)", rows.skip, Skin.colors.inkSoft } }
    self.learnButtons = {}
    for gi, g in ipairs(groups) do
      if #g[2] > 0 and not (gi == 3 and Panoply.db and Panoply.db.trainerShowSkip == false) then
        local gc = 0
        for _, s in ipairs(g[2]) do gc = gc + s[3] end
        y = U.GroupHead(c, x, y, w, g[1], #g[2], gc, g[3], "recipe")
        for _, r in ipairs(g[2]) do
          local b
          y, b = U.ServiceRow(c, x, y, w, r, { spendable = spend, dim = gi == 3, compact = gi ~= 1, onClick = function() ST:Learn(r[1], r[2]) end,
            tipBody = "One click learns this one recipe. Panoply Suite never buys anything by itself." })
          b.panoplyService = r
          self.learnButtons[#self.learnButtons + 1] = b
        end
        if g[4] and g[4] > 0 then
          local more = Skin.Button(c, ("And %d more that still give points"):format(g[4]), 200, 22, function() ST.showAllOptional = true; ST:Refresh() end,
            "Show all", "Lists every Optional recipe here. The game's own window lists them too.")
          Skin.FitButton(more, 120, w - 30)
          more:SetPoint("TOPLEFT", c, "TOPLEFT", x + 30, y)
          y = y - more:GetHeight() - Skin.SP.s
        end
        y = y - Skin.SP.xs
      end
    end
    if #services == 0 then y = U.Block(c, x, y, w, 11, Skin.colors.inkSoft, "Nothing new to learn here right now.") - Skin.SP.s end
    return y
  end
  local function foot(ft, x, w, y)
    U.Rule(ft, x, y, w); y = y - Skin.SP.s
    local note
    local prof = profName and PD[profName]
    if prof and PR then
      local _, rk = PR:RankFor(prof, max)
      if rk then
        local fee = (rk.fee or 0) * 100
        if skill >= (rk.minSkill or 0) and p.level >= (rk.minLevel or 0) then
          note = ("%s %s (up to %d): you can learn it now, %s."):format(rk.name, profName, rk.max, ST.Money(fee))
        else
          local bits = {}
          if skill < (rk.minSkill or 0) then bits[#bits + 1] = ("at skill %d"):format(rk.minSkill) end
          if p.level < (rk.minLevel or 0) then bits[#bits + 1] = ("at level %d"):format(rk.minLevel) end
          note = ("%s %s (up to %d): %s, %s."):format(rk.name, profName, rk.max, table.concat(bits, " and "), ST.Money(fee))
          if skill < (rk.minSkill or 0) then
            local n = rk.minSkill - skill
            note = note .. (" Come back in %d point%s."):format(n, n == 1 and "" or "s")
          end
        end
      end
    end
    if note then y = U.Block(ft, x, y, w, 11, Skin.colors.ink, note) - Skin.SP.xs end
    return U.Block(ft, x, y, w, 10, Skin.colors.dim, "From your profession plan (cheapest). One click learns one recipe.")
  end
  U.ListPanel(f, PANEL_W, self:PanelMaxH(), top, list, foot)
  self:PanelAnchor(f)
  f:Show()
  return f
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
function ST:Refresh()
  if not self.atTrainer or not Panoply.Modules:IsOn("spectrainer") then return end
  -- closed by the player during this visit: a TRAINER_UPDATE (a purchase, a level, a money change) never brings it back
  if self.panelDismissed then return end
  local db = Panoply.db or {}
  if self:IsProfessionTrainer() then
    if db.trainerProfPanel ~= false then return self:ShowProfessionPanel() end
  elseif db.trainerPanel ~= false then
    return self:ShowClassPanel()
  end
  self:HidePanel()
end

ST:On("TRAINER_SHOW", function()
  ST.atTrainer, ST.showAllOptional, ST.learnedHere, ST.learnedCount = true, nil, {}, 0
  ST.panelDismissed = nil
  -- the game's trainer window is created by the same event: lay out on the next frame
  ST:HookTrainerFrame()
  ST:Refresh()
  C.After(0, function() if ST.atTrainer then ST:HookTrainerFrame(); ST:Refresh() end end)
  if not ST:IsProfessionTrainer() then
    ST:CDB().trainerSeenAt = ST.TrainerTitle()
    ST:OnTrainerVisited()
  end
end)
ST:On("TRAINER_UPDATE", function() if ST.atTrainer then ST:Refresh() end end)
-- The close paths are not gated on the module being on (Panoply:On, not ST:On): a trainer closed while Talents & spells was switched
-- off must still clear the visit, or the next TRAINER_UPDATE after switching it back on would show a panel for a trainer that is gone.
Panoply:On("TRAINER_CLOSED", function()
  ST.atTrainer = nil
  ST:HidePanel()
  if ST:IsOn() then Panoply:Fire("SPEC_TRAINER_CHANGED", true) end
end)
-- Newer clients also report the trainer closing through the interaction manager (the type is read from Enum by name; an
-- older client has neither and this is skipped).
Panoply:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  local E = _G.Enum and _G.Enum.PlayerInteractionType
  if E and E.Trainer and kind == E.Trainer and ST.atTrainer then ST:TrainerGone() end
end)
