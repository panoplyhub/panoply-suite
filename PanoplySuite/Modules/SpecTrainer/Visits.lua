-- Panoply Suite, Step 2 item C: the spell plan by trainer visit (docs/step2/ABC-SPEC.md C-02; our decision 4 in docs/step2/DECISIONS.md).
-- From the plan you follow, work out which spells and ranks to buy at each trainer visit, what each visit costs, and what the whole plan
-- costs. A trainer visit is a level where the class trainer has something new; everything you could already learn is one visit, "Now".
-- Nothing here buys anything: buying is ST:Learn (TrainerPanel.lua), one click for one spell.
--
-- Which ranks of a spell are skipped (Nov 4: "Plan's list only"): every rank is bought except what the FOLLOWED plan's own optional and
-- skip lists in Specs.lua (and the class's lists under them) say: a spell they name is Optional or Skipped at every rank, with their words.
-- That is the default, ST.RANK_RULE = "plan-only": no other rule skips a rank.
-- The other reading of decision 4 stays in the code behind the same switch, ST.RANK_RULE = "catchup", and is not the default: after the
-- lists, never skip a spell's first rank (Rank 1, or a spell that has no ranks), and skip a rank when the next rank arrives within
-- SKIP_WITHIN levels of the level you would buy it at (the level of the visit: the level the rank arrives at, or your own level when you
-- are behind). A skipped rank says why. The switch is read in ST:RankSkip and nowhere else; the page, the trainer panel, Home and the
-- level-up message all go through ST:RankSkip.
-- Spells whose rank you already have a stronger one of are left out (nothing to buy), under either setting.
--
-- Talent spells: a spell a talent teaches is counted only when the character has the talent now, or, for a later visit, when the plan
-- that is FOLLOWED (not the one the trainer helper falls back to) will have taken it by then.
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C = Panoply.Compat

ST.SKIP_WITHIN = 2
ST.RANK_RULE = "plan-only"    -- "plan-only" (the default: the plan's lists only) | "catchup" (see above)

-- "Rank 3" -> 3, whatever the wording ("Rang 3", "(Rank 3)", "Rank III"); no rank text (Blink, Slow Fall, "Passive") -> nil
local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10, XI = 11, XII = 12, XIII = 13, XIV = 14, XV = 15 }
function ST.RankNumber(rank)
  if type(rank) ~= "string" then return nil end
  local digits = rank:match("(%d+)")
  if digits then return tonumber(digits) end
  for word in rank:gmatch("%a+") do if ROMAN[word] then return ROMAN[word] end end
  return nil
end

-- The row of the class's trainer table (in list, one spell's rows) that a service of the game's trainer window is: by rank number, else by
-- the exact rank text, else by the level the service asks for when only one rank has it. nil when none (then no rank rule applies).
function ST.MatchRow(list, rank, level)
  if not list then return nil end
  local n = ST.RankNumber(rank)
  if n then for _, o in ipairs(list) do if o.n == n then return o end end end
  for _, o in ipairs(list) do if o.rank == (rank or "") then return o end end
  if level then
    local found
    for _, o in ipairs(list) do
      if o.level == level then
        if found then return nil end
        found = o
      end
    end
    return found
  end
  return nil
end

-- The class's trainer rows grouped by spell name, lowest rank first (the rows ST:ClassSpells gives; each gets .n, its rank number).
function ST:RankIndex(rows)
  local by = {}
  for _, r in ipairs(rows) do
    r.n = ST.RankNumber(r.rank)
    local list = by[r.name]
    if not list then list = {} by[r.name] = list end
    list[#list + 1] = r
  end
  for _, list in pairs(by) do table.sort(list, function(a, b) return (a.n or 0) < (b.n or 0) end) end
  return by
end

-- The next rank of the same spell, or nil
function ST.NextRank(list, r)
  if not (list and r.n) then return nil end
  for _, o in ipairs(list) do if o.n and o.n > r.n then return o end end
  return nil
end

-- A stronger rank of the same spell that you know already (then the lower ranks are nothing to buy), or nil
function ST.RankCovered(list, r, level, known)
  if not (list and r.n) then return nil end
  for _, o in ipairs(list) do
    if o.n and o.n > r.n and o.level <= level and known(o.spell) == true then return o end
  end
  return nil
end

-- nil, or the plain reason a rank is skipped by the rank rule; always nil unless ST.RANK_RULE is "catchup" (the one place it is read).
-- level = the player's level.
function ST:RankSkip(list, r, level)
  if ST.RANK_RULE ~= "catchup" then return nil end
  if not r.n or r.n <= 1 then return nil end
  local visitLevel = math.max(r.level, level)
  local nx = ST.NextRank(list, r)
  if nx and nx.level <= visitLevel + ST.SKIP_WITHIN then
    if nx.level <= visitLevel then return ("Rank %d is already there: learn that one."):format(nx.n), nx end
    return ("Rank %d comes at level %d."):format(nx.n, nx.level), nx
  end
  return nil
end

-- The plan by trainer visit.
-- opts: player (default ST:Player()), plan (the plan whose optional / skip lists decide; default ST:VerdictPlan()), gate (the plan whose
-- talents open the spells a talent teaches; default the plan you follow, and none when you follow none: then only the talents you have
-- count), to (last level, default 60), known (function(spellId) -> true / false / nil, default C.KnowsSpell).
-- Returns { level, money, plan, how, visits = { visit }, now, next, buy = { n, cost }, skip = { n, cost }, opt = { n, cost }, from, to, table }
-- where a visit is { level, now = true for the one you could do today, rows, buy = { n, cost }, skip = {..}, opt = {..} } and a row is
-- { level, name, rank, cost, spell, icon, n, kind = "buy" | "opt" | "skip", why }.
function ST:SpellPlan(opts)
  opts = opts or {}
  local p = opts.player or self:Player()
  local plan, how = opts.plan, opts.how
  if not plan then plan, how = self:VerdictPlan() end
  local gate = opts.gate or self:Tracked()
  local to = opts.to or self.LAST_LEVEL
  local known = opts.known or C.KnowsSpell
  local level = p.level or 1
  local rows = self:ClassSpells({ player = p, plan = gate })
  local index = self:RankIndex(rows)
  for i, r in ipairs(rows) do r.order = i end
  table.sort(rows, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.order < b.order end)
  local out = { level = level, money = p.money or 0, plan = plan, how = how, visits = {}, from = level, to = to,
                buy = { n = 0, cost = 0 }, skip = { n = 0, cost = 0 }, opt = { n = 0, cost = 0 }, table = self:TrainerTable() ~= nil }
  local byLevel = {}
  for _, r in ipairs(rows) do
    if r.level <= to then
      local here = r.level <= level
      -- what you could learn today and do not know; a stronger rank you know already covers the lower ones
      local wanted = true
      if here then
        wanted = known(r.spell) == false and not ST.RankCovered(index[r.name], r, level, known)
      end
      if wanted then
        local visitLevel = math.max(r.level, level)      -- the visit this spell is in
        local verdict, why = self:Verdict(r.name, plan)
        local kind, reason = "buy", nil
        if verdict == "skip" then kind, reason = "skip", why
        elseif verdict == "opt" then kind, reason = "opt", why
        else
          local why2 = self:RankSkip(index[r.name], r, level)
          if why2 then kind, reason = "skip", why2 end
        end
        local v = byLevel[visitLevel]
        if not v then
          v = { level = visitLevel, now = here or nil, rows = {}, buy = { n = 0, cost = 0 }, skip = { n = 0, cost = 0 }, opt = { n = 0, cost = 0 } }
          byLevel[visitLevel] = v
          out.visits[#out.visits + 1] = v
        end
        local row = { level = r.level, name = r.name, rank = r.rank, cost = r.cost, spell = r.spell, icon = r.icon, n = r.n, kind = kind, why = reason }
        v.rows[#v.rows + 1] = row
        v[kind].n, v[kind].cost = v[kind].n + 1, v[kind].cost + r.cost
        out[kind].n, out[kind].cost = out[kind].n + 1, out[kind].cost + r.cost
      end
    end
  end
  table.sort(out.visits, function(a, b) return a.level < b.level end)
  for _, v in ipairs(out.visits) do
    if v.now then out.now = v
    elseif not out.next and v.buy.n > 0 then out.next = v end
  end
  return out
end

-- The rows of one kind in a visit, in order
function ST.VisitRows(v, kind)
  local out = {}
  for _, r in ipairs(v and v.rows or {}) do if r.kind == kind then out[#out + 1] = r end end
  return out
end
