-- Panoply Suite profession planner (own algorithm, SPEC section 9).
-- Dynamic programme over skill points using recipe colour thresholds from the generated open data
-- (VMaNGOS, via PanoplySuite_QuestData), corrected by what the live profession window shows.
-- Two strategies: "cheapest" (gold first, time as tie-breaker) and "fastest" (time first).
local ADDON, Panoply = ...
local PR = {}
Panoply.Professions = PR
local PD, C, U = Panoply.ProfData, Panoply.Compat, Panoply.Util

PR.MAX_SEGMENT = 60
PR.SECONDS_PER_NODE = 50        -- find + mine one node, including riding between them (estimate)
PR.SECONDS_PER_CRAFT = 3        -- cast time + clicking
PR.SECONDS_PER_CATCH = 12       -- cast, wait, loot
PR.COPPER_PER_SECOND = 2        -- how "cheapest" values your time (tie-breaker only)
PR.OWN_GATHER_WEIGHT = 0.15     -- "cheapest": your own mining time counts this much (it is free gold)
PR.RELIABILITY = 1.25           -- price multiplier for things you can't just buy from a vendor
-- Rare nodes spawn in place of common ones; they are a bonus, never a plan.
PR.RARE_NODES = { ["Silver Vein"] = true, ["Gold Vein"] = true, ["Truesilver Deposit"] = true, ["Incendicite Mineral Vein"] = true,
  ["Lesser Bloodstone Deposit"] = true, ["Dark Iron Deposit"] = true }
-- 0.8.4: words for the gathering professions that are not Mining (Mining keeps its own wording).
PR.GATHER_TEXT = {
  Herbalism = { verb = "Pick", where = "the fields", tip = "turn on Find Herbs so herbs show on your minimap." },
  Skinning = { verb = "Skin", where = "the wilds", tip = "kill and loot the beast first, then skin it." },
}

-------------------------------------------------------------------------------
-- Colour thresholds (data, corrected by live observations)
-------------------------------------------------------------------------------
function PR:Thresholds(profName, r)
  local obs = Panoply.db and Panoply.db.tradeObservations and Panoply.db.tradeObservations[profName]
  local o = obs and obs[r.name]
  local learn = math.max(r.learn or 1, 1)
  if not o then return learn, r.yellow, r.green, r.grey end
  return o.learn or learn, o.yellow or r.yellow, o.green or r.green, o.grey or r.grey
end

-- Chance that one craft/gather at `skill` gives a point.
function PR.Chance(skill, learn, yellow, green, grey)
  if skill < learn or skill >= grey then return 0 end
  if skill < yellow then return 1 end
  return (grey - skill) / (grey - yellow)
end

-- Expected crafts to go from skill a to b with one recipe (nil when it greys out first).
function PR:ExpectedCrafts(profName, r, a, b)
  local l, y, g, gr = self:Thresholds(profName, r)
  local n = 0
  for s = a, b - 1 do
    local p = PR.Chance(s, l, y, g, gr)
    if p <= 0 then return nil end
    n = n + 1 / p
  end
  return n
end

-- Record what the live trade-skill window shows, tightening thresholds; remembers known recipes.
-- difficulty: "optimal"(orange) "medium"(yellow) "easy"(green) "trivial"(grey)
function PR:Observe(profName, recipeName, difficulty, skill)
  if not (Panoply.db and profName and recipeName and skill) then return end
  if Panoply.cdb then
    Panoply.cdb.knownRecipes = Panoply.cdb.knownRecipes or {}
    Panoply.cdb.knownRecipes[profName] = Panoply.cdb.knownRecipes[profName] or {}
    Panoply.cdb.knownRecipes[profName][recipeName] = true
  end
  local prof = PD[profName]
  if not prof then return end
  local r
  for _, x in ipairs(prof.recipes or {}) do if x.name == recipeName then r = x end end
  for _, x in ipairs(prof.smelting or {}) do if x.name == recipeName then r = x end end
  if not r then return end
  Panoply.db.tradeObservations[profName] = Panoply.db.tradeObservations[profName] or {}
  local o = Panoply.db.tradeObservations[profName][recipeName] or {}
  local l, y, g, gr = self:Thresholds(profName, r)
  if difficulty == "optimal" and y <= skill then o.yellow = skill + 1 end
  if difficulty == "medium" and (y > skill) then o.yellow = skill end
  if difficulty == "medium" and g <= skill then o.green = skill + 1 end
  if difficulty == "easy" and g > skill then o.green = skill end
  if difficulty == "easy" and gr <= skill then o.grey = skill + 1 end
  if difficulty == "trivial" and gr > skill then o.grey = skill end
  Panoply.db.tradeObservations[profName][recipeName] = o
end

function PR:ObserveOpenWindow()
  local res = C.ReadOpenTradeSkill()
  if not res or not res.name or not res.rank then return 0 end
  local n = 0
  for _, r in ipairs(res.recipes) do self:Observe(res.name, r.name, r.difficulty, res.rank); n = n + 1 end
  Panoply:Fire("PROF_KNOWLEDGE", res.name)
  return n
end

function PR:KnowsRecipe(profName, r)
  if not r then return false end
  if r.source == "auto" then return true end
  local k = Panoply.cdb and Panoply.cdb.knownRecipes and Panoply.cdb.knownRecipes[profName]
  if k and k[r.name] then return true end
  if r.id and C.KnowsSpell(r.id) then return true end
  return false
end

function PR:MarkRecipeKnown(profName, name)
  if not (Panoply.cdb and profName and name) then return end
  Panoply.cdb.knownRecipes = Panoply.cdb.knownRecipes or {}
  Panoply.cdb.knownRecipes[profName] = Panoply.cdb.knownRecipes[profName] or {}
  Panoply.cdb.knownRecipes[profName][name] = true
end

-- "You have learned how to create a new item: Rough Bronze Boots." -> find the profession.
function PR:LearnedFromText(msg)
  if type(msg) ~= "string" then return nil end
  local name = msg:match("learned how to create a new item: (.-)%.?$") or msg:match("You have learned a new spell: (.-)%.?$")
    or msg:match("learned how to create (.-)%.?$")
  if not name then return nil end
  for _, pn in ipairs(PD.ORDER) do
    local prof = PD[pn]
    for _, r in ipairs(prof and prof.recipes or {}) do
      if r.name == name or (r.makes and PD.ItemName(r.makes) == name) then self:MarkRecipeKnown(pn, r.name) return pn, r.name end
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Items you have: bags + bank (+ mail seen at the mailbox)
-------------------------------------------------------------------------------
function PR:Have(id)
  local n = C.ItemCount(id, true) or 0
  local mail = Panoply.cdb and Panoply.cdb.mailItems and Panoply.cdb.mailItems[id] or 0
  return n + mail, n, mail
end

function PR:HaveInBags(id) return C.ItemCount(id, false) or 0 end

-------------------------------------------------------------------------------
-- Live skills
-------------------------------------------------------------------------------
function PR:CurrentSkill(profName)
  local line = PD.SKILL_LINES[profName]
  for _, s in ipairs(C.GetSkills()) do
    if s.name == profName or (line and s.skillLineID == line) then return s.rank or 0, s.max or 0 end
  end
  return nil
end

function PR:Ranks(prof) return prof.ranks or PD.STANDARD_RANKS end

function PR:RankFor(prof, max)
  for i, rk in ipairs(self:Ranks(prof)) do if (max or 0) < rk.max then return i, rk end end
  return nil
end

-------------------------------------------------------------------------------
-- Cost model
-------------------------------------------------------------------------------
local function makersIndex(prof)
  if prof._makers then return prof._makers end
  local m = {}
  for _, r in ipairs(prof.recipes or {}) do if r.makes and not m[r.makes] then m[r.makes] = r end end
  prof._makers = m
  return m
end

function PR:Maker(prof, itemID) return makersIndex(prof)[itemID] end

local smeltIndex
local function smelterOf(itemID)
  if not smeltIndex then
    smeltIndex = {}
    local M = PD.Mining
    for _, r in ipairs(M and M.smelting or {}) do if r.makes then smeltIndex[r.makes] = r end end
  end
  return smeltIndex[itemID]
end
PR.SmelterOf = smelterOf

local ORE = {}
local function isOre(id)
  if ORE[id] == nil then
    ORE[id] = false
    for _, n in ipairs(PD.Mining and PD.Mining.nodes or {}) do
      for _, o in ipairs(n.oreIds or {}) do if o == id then ORE[id] = true end end
    end
  end
  return ORE[id]
end
PR.IsOre = isOre

-- Money and seconds to obtain one unit of item `id`. ctx.mining = player can mine/smelt.
-- Making it yourself (bolts, bars) wins on "cheapest" whenever it costs no more gold.
local function better(money, ws, best, ctx)
  if ctx.strategy ~= "fastest" and money <= best.money then return true end
  return PR.Score(money, ws, ctx) < PR.Score(best.money, best.ws, ctx)
end

function PR:ReagentCost(prof, id, ctx, depth)
  depth = depth or 0
  local price, src = PD.Price(id)
  local it = PD.Item(id) or {}
  -- 0.9.6 phase P: the price is your side's vendor price (PD.Price), and "limited" is your side's vendors' stock
  local limited = PD.VendorLimited(id)
  local buyMoney, buySec
  if src == "vendor" and not limited then buyMoney, buySec = price, 2
  elseif src == "you" then buyMoney, buySec = price, 10
  else buyMoney, buySec = price * PR.RELIABILITY, (it.farm and it.farm[1]) and 25 or 12 end
  -- ws = seconds as the strategy weighs them (own gathering is cheap time when saving gold)
  local best = { money = buyMoney, sec = buySec, ws = buySec, how = (src == "vendor" and not limited) and "vendor" or "ah" }
  if depth < 3 then
    local m = makersIndex(prof)[id]
    if m then
      local mm, ms, mw = self:CraftCost(prof, m, ctx, depth + 1)
      local per = 1 / (m.count or 1)
      if better(mm * per, mw * per, best, ctx) then best = { money = mm * per, sec = ms * per, ws = mw * per, how = "craft", recipe = m } end
    end
    local sm = ctx.mining and smelterOf(id)
    if sm then
      local mm, ms, mw = 0, PR.SECONDS_PER_CRAFT, PR.SECONDS_PER_CRAFT
      for rid, n in pairs(sm.reagents or {}) do
        local c = self:ReagentCost(PD.Mining, rid, ctx, depth + 1)
        mm, ms, mw = mm + c.money * n, ms + c.sec * n, mw + c.ws * n
      end
      local per = 1 / (sm.count or 1)
      if better(mm * per, mw * per, best, ctx) then best = { money = mm * per, sec = ms * per, ws = mw * per, how = "smelt", recipe = sm } end
    end
    if ctx.mining and isOre(id) then
      local sec = PR.SECONDS_PER_NODE / 2
      local mine = { money = price * 0.3, sec = sec, ws = sec * ((ctx.strategy == "fastest") and 1 or PR.OWN_GATHER_WEIGHT), how = "mine" }
      if PR.Score(mine.money, mine.ws, ctx) < PR.Score(best.money, best.ws, ctx) then best = mine end
    end
  end
  return best
end

function PR.Score(money, sec, ctx)
  if ctx and ctx.strategy == "fastest" then return sec * 100 + money * 0.02 end
  return money + sec * PR.COPPER_PER_SECOND
end

-- money, real seconds, strategy-weighted seconds
function PR:CraftCost(prof, r, ctx, depth)
  local money, sec, ws = 0, PR.SECONDS_PER_CRAFT, PR.SECONDS_PER_CRAFT
  for id, n in pairs(r.reagents or {}) do
    local c = self:ReagentCost(prof, id, ctx, depth or 0)
    money, sec, ws = money + c.money * n, sec + c.sec * n, ws + c.ws * n
  end
  return money, sec, ws
end

-------------------------------------------------------------------------------
-- Which options a plan may use
-------------------------------------------------------------------------------
-- 0.9.6 phase P (Nov 17 2026): where YOU get a recipe, by your side. A recipe the data lists as a "drop" because no Alliance
-- vendor sells it, but which a vendor of your side (or a neutral one) sells (its `allNpcs`: phase N's 11, Horde vendors), is a
-- vendor recipe for you at that vendor's price (`vendorFee`). A "vendor" recipe that only the other side's vendors sell is a
-- drop for you (you cannot buy it). "Your side" is phase L's check (ProfGuide G.NpcFriendly: never an unknown side), and the
-- vendor must have a known spot, as ProfGuide:FriendlyNearest asks. Data without `allNpcs`, or no side for the player: as listed.
local function sideVendor(ids)
  local G = Panoply.ProfGuide
  if not (G and G.NpcFriendly) then return nil end
  for _, id in ipairs(ids or {}) do
    if G.NpcFriendly(id) then
      local s = PD.NpcSpot(id)
      if s and s.map then return true end
    end
  end
  return false
end
function PR:RecipeSource(r)
  if not (r and r.allNpcs and (r.source == "drop" or r.source == "vendor") and PD.PlayerSide and PD.PlayerSide()) then
    return r and r.source, r and r.fee
  end
  local mine = sideVendor(r.allNpcs)
  if mine == nil then return r.source, r.fee end
  if r.source == "drop" and mine then return "vendor", r.vendorFee or r.fee end
  if r.source == "vendor" and not mine then return "drop", r.fee end
  return r.source, r.fee
end
function PR:RecipeFee(r) return select(2, self:RecipeSource(r)) or 0 end

function PR:Usable(profName, prof, r, ctx)
  if self:KnowsRecipe(profName, r) then return true end
  if r.foreverMissing then return false, "forever" end   -- not in the WoW Forever recipe table
  if self:RecipeSource(r) == "drop" and not ctx.allowDrops then return false, "drop" end
  if r.rep then return false, "reputation" end
  if r.cooldown then return false, "cooldown" end
  if r.spec and r.spec ~= ctx.spec then return false, "spec" end
  if not (r.source == "trainer" or r.source == "auto" or r.source == "vendor" or r.source == "drop") then return false, "unknown" end
  return true
end

function PR:NodeUsable(node, level)
  if PR.RARE_NODES[node.name] or node.name:find("^Ooze Covered") then return false end
  for _, z in ipairs(node.zones or {}) do if (z.minLevel or 1) <= (level or 60) + 3 then return true end end
  return false
end

-------------------------------------------------------------------------------
-- Fishing model (own, UNVERIFIED): a zone is fine once skill >= zone skill + 70; catches per
-- skill point grow with skill.
-------------------------------------------------------------------------------
PR.FISH_MARGIN = 70
function PR.CatchesPerPoint(s)
  if s < 75 then return 1 elseif s < 150 then return 2 elseif s < 225 then return 3.5 else return 5 end
end

function PR:FishZones(skill, level)
  local out = {}
  for _, z in ipairs(PD.Fishing and PD.Fishing.zones or {}) do
    if (z.skill or 0) + PR.FISH_MARGIN <= math.max(skill, 1) + 70 and (z.minLevel or 1) <= (level or 60) + 2 then out[#out + 1] = z end
  end
  -- best: the highest zone skill you can handle (more fish, fewer junk casts), prefer Alliance-friendly low zones on ties
  table.sort(out, function(a, b)
    local ra, rb = (a.skill or 0) + PR.FISH_MARGIN <= skill, (b.skill or 0) + PR.FISH_MARGIN <= skill
    if ra ~= rb then return ra end
    if (a.minLevel or 1) ~= (b.minLevel or 1) then return (a.minLevel or 1) < (b.minLevel or 1) end
    return (a.skill or 0) < (b.skill or 0)
  end)
  return out
end

-------------------------------------------------------------------------------
-- Plan
-------------------------------------------------------------------------------
-- opts: from, to, level, maxKnown (current rank cap), strategy ("cheapest"|"fastest"),
--       spec, mining (bool), allowDrops
function PR:Context(profName, opts)
  opts = opts or {}
  local ctx = { level = opts.level or 60, strategy = opts.strategy or (Panoply.db and Panoply.db.profStrategy) or "cheapest",
    spec = opts.spec, allowDrops = opts.allowDrops }
  if ctx.spec == nil and Panoply.cdb and Panoply.cdb.profSpec then ctx.spec = Panoply.cdb.profSpec[profName] end
  if opts.mining ~= nil then ctx.mining = opts.mining
  else
    local r = self:CurrentSkill("Mining")
    ctx.mining = (r and r > 0) or self:Chosen("Mining")
  end
  return ctx
end

function PR:Chosen(name)
  local ch = Panoply.cdb and Panoply.cdb.professions
  if not ch then return false end
  for _, k in ipairs({ "primary", "secondary" }) do for _, n in ipairs(ch[k] or {}) do if n == name then return true end end end
  return false
end

function PR:Plan(profName, opts)
  opts = opts or {}
  local prof = PD[profName]
  if not prof or not prof.ranks then return nil, "No data for " .. tostring(profName) .. " yet (coming in a later version)." end
  local ctx = self:Context(profName, opts)
  local from = math.max(opts.from or 1, 1)
  local to = math.min(opts.to or 300, 300)
  local level = ctx.level
  local plan = { prof = profName, kind = prof.kind, from = from, to = to, segments = {}, training = {}, warnings = {},
                 shopping = {}, intermediates = {}, recipes = {}, tools = {}, totalCost = 0, totalSeconds = 0,
                 verified = prof.verified, strategy = ctx.strategy, spec = ctx.spec, ctx = ctx }
  if not prof.verified then
    -- 0.8.4: on WoW Forever the colours of the recipes the Forever client table lists come from that table
    -- (where the overlay also moved learn skills by our own rule, the note says they are an estimate)
    if prof.forever and prof.forever.checked > 0 and (prof.forever.learnDerived or 0) > 0 then
      plan.warnings[#plan.warnings + 1] = "Recipe colours are from the WoW Forever game files; learn skills are our estimate; the rest is Classic 1.12 (unverified)."
    elseif prof.forever and prof.forever.checked > 0 then
      plan.warnings[#plan.warnings + 1] = "Recipe colours are from the WoW Forever game files; trainers, fees and materials are Classic 1.12 values (unverified)."
    else
      plan.warnings[#plan.warnings + 1] = "Recipe colours are Classic 1.12 values (unverified for WoW Forever); they self-correct when you open the profession window."
    end
  end

  -- Rank boundaries and level gates.
  local ranks = self:Ranks(prof)
  local bounds = {}
  for _, rk in ipairs(ranks) do bounds[#bounds + 1] = rk.max end
  local cap = to
  for i, rk in ipairs(ranks) do
    local prevMax = i > 1 and ranks[i - 1].max or 0
    if to > prevMax and from < rk.max and (opts.maxKnown or 0) < rk.max then
      if level < (rk.minLevel or 0) then
        cap = math.max(from, math.min(cap, prevMax))
        plan.warnings[#plan.warnings + 1] = ("%s (up to %d) needs character level %d; plan stops at %d for now."):format(rk.name, rk.max, rk.minLevel, cap)
        plan.levelGate = { rank = rk.name, minLevel = rk.minLevel, at = cap }
        break
      end
      plan.training[#plan.training + 1] = { at = math.max(prevMax, from), rank = rk.name, max = rk.max, minLevel = rk.minLevel,
        minSkill = rk.minSkill, fee = rk.fee or 0, source = rk.source, npcs = rk.npcs, book = rk.book, bookName = rk.bookName, quest = rk.quest, questTitle = rk.questTitle, hint = rk.hint, spell = rk.spell, rankIndex = i }
    end
  end
  to = cap
  plan.to = to
  plan.trainers = self:Trainers(profName, plan.training, from)
  if to <= from then self:Finish(plan, prof) return plan end

  -- Options and unit cost.
  local options, unit = {}, {}
  -- 0.8.4: recipes left out only because their pattern is a drop. They are used for a stretch nothing else covers
  -- (WoW Forever's colours leave Tailoring with no trainer or vendor recipe above 280), never to make a plan cheaper.
  local found = {}
  if prof.kind == "gathering" then
    for _, n in ipairs(prof.nodes or {}) do
      if self:NodeUsable(n, level) then options[#options + 1] = n; unit[#options] = PR.Score(0, PR.SECONDS_PER_NODE, ctx) end
    end
  elseif prof.kind == "fishing" then
    -- one virtual option per skill: handled below
  else
    local dropCtx
    for _, r in ipairs(prof.recipes or {}) do
      local ok, why = self:Usable(profName, prof, r, ctx)
      if ok then
        local m, _, s = self:CraftCost(prof, r, ctx)
        options[#options + 1] = r
        unit[#options] = PR.Score(m, s, ctx) + 1
      elseif why == "drop" then
        dropCtx = dropCtx or setmetatable({ allowDrops = true }, { __index = ctx })
        if self:Usable(profName, prof, r, dropCtx) then found[#found + 1] = r end
      end
    end
  end

  local function nextBound(s)
    for _, b in ipairs(bounds) do if s < b then return b end end
    return 300
  end

  if prof.kind == "fishing" then
    self:PlanFishing(plan, prof, from, to, level, nextBound)
    self:Finish(plan, prof)
    return plan
  end

  local INF = math.huge
  local dp, prev = {}, {}
  for s = from, to do dp[s] = INF end
  dp[from] = 0
  local thr = {}
  for i, r in ipairs(options) do thr[i] = { self:Thresholds(profName, r) } end
  local function fill(first)
    for s = first, to - 1 do
      if dp[s] < INF then
        local limit = math.min(to, nextBound(s), s + PR.MAX_SEGMENT)
        for i, r in ipairs(options) do
          local t = thr[i]
          local l, y, g, gr = t[1], t[2], t[3], t[4]
          if s >= l and s < gr then
            local fee = (prof.kind == "crafting" and not self:KnowsRecipe(profName, r)) and self:RecipeFee(r) or 0
            if ctx.strategy == "fastest" then fee = fee * 0.02 end
            local acc, crafts = fee, 0
            for e = s + 1, limit do
              local p = PR.Chance(e - 1, l, y, g, gr)
              if p <= 0 then break end
              crafts = crafts + 1 / p
              acc = acc + unit[i] / p
              local v = dp[s] + acc
              if v < dp[e] then dp[e] = v; prev[e] = { s = s, i = i, crafts = crafts } end
            end
          end
        end
      end
    end
  end
  local function highest()
    local e = to
    while e > from and dp[e] == INF do e = e - 1 end
    return e
  end

  fill(from)
  local reached = highest()
  if reached < to and #found > 0 then
    local stuck = reached
    for _, r in ipairs(found) do
      local m, _, s = self:CraftCost(prof, r, ctx)
      options[#options + 1] = r
      unit[#options] = PR.Score(m, s, ctx) + 1
      thr[#options] = { self:Thresholds(profName, r) }
    end
    fill(stuck)
    reached = highest()
    if reached > stuck then
      plan.foundFrom = stuck
      plan.warnings[#plan.warnings + 1] = ("No trainer or vendor recipe covers %d-%d; those steps use recipes you have to find."):format(stuck, reached)
    end
  end
  if reached < to then plan.warnings[#plan.warnings + 1] = ("No known recipe covers %d-%d with your options."):format(reached, to) end
  plan.to = reached

  local segs = {}
  local e = reached
  while e > from and prev[e] do
    local p = prev[e]
    table.insert(segs, 1, { from = p.s, to = e, option = options[p.i], crafts = p.crafts })
    e = p.s
  end
  for _, sg in ipairs(segs) do
    local last = plan.segments[#plan.segments]
    if last and last.option == sg.option then last.to = sg.to; last.crafts = last.crafts + sg.crafts
    else plan.segments[#plan.segments + 1] = sg end
  end
  for _, sg in ipairs(plan.segments) do
    sg.count = math.ceil(sg.crafts - 0.05)
    sg.name = sg.option.name
    if prof.kind == "gathering" then
      sg.zones = self:NodeZones(sg.option, level)
      sg.yields = sg.option.ore
      sg.verb = "mine"
      sg.gather = PR.GATHER_TEXT[profName]
    else
      sg.verb = sg.option.target and "enchant" or "craft"
      sg.makes = sg.option.makes
      sg.focus = sg.option.focus
      sg.tools = sg.option.tools
    end
  end
  self:Finish(plan, prof)
  return plan
end

function PR:PlanFishing(plan, prof, from, to, level, nextBound)
  local s = from
  while s < to do
    local zs = self:FishZones(s, level)
    local z = zs[1]
    local e = math.min(to, nextBound(s))
    -- next zone change: when a better zone opens up
    for _, zz in ipairs(PD.Fishing.zones or {}) do
      local open = (zz.skill or 0) + PR.FISH_MARGIN
      if open > s and open < e and (zz.minLevel or 1) <= level + 2 then e = open end
    end
    local catches = 0
    for k = s, e - 1 do catches = catches + PR.CatchesPerPoint(k) end
    plan.segments[#plan.segments + 1] = { from = s, to = e, name = z and z.name or "any water", zone = z, zones = { z }, count = math.ceil(catches),
      crafts = catches, verb = "fish", option = { name = "Fishing" } }
    s = e
  end
  local merged = {}
  for _, sg in ipairs(plan.segments) do
    local last = merged[#merged]
    if last and last.zone == sg.zone then last.to = sg.to; last.count = last.count + sg.count else merged[#merged + 1] = sg end
  end
  plan.segments = merged
end

-- Totals: shopping list, intermediates, recipes to learn, tools, cost and time.
function PR:Finish(plan, prof)
  local ctx = plan.ctx
  local profName = plan.prof
  local seconds, money = 0, 0
  for _, t in ipairs(plan.training) do money = money + (t.fee or 0) end
  if prof.kind == "crafting" then
    local need, made = {}, {}
    for _, sg in ipairs(plan.segments) do
      sg.mats = {}
      for id, n in pairs(sg.option.reagents or {}) do sg.mats[id] = n * sg.count; need[id] = (need[id] or 0) + n * sg.count end
      if sg.makes then made[sg.makes] = (made[sg.makes] or 0) + sg.count * (sg.option.count or 1) end
      seconds = seconds + sg.count * PR.SECONDS_PER_CRAFT
    end
    -- Expand intermediates (same profession crafts, and smelting when you mine).
    plan.smelt = {}
    for _ = 1, 4 do
      local changed = false
      local ids = U.Keys(need)
      table.sort(ids)
      for _, id in ipairs(ids) do
        local n = need[id]
        local c = self:ReagentCost(prof, id, ctx)
        if c.how == "craft" or c.how == "smelt" then
          local m = c.recipe
          local extra = n - (made[id] or 0)
          plan.intermediates[id] = { need = n, recipe = m, how = c.how }
          need[id] = nil
          if extra > 0 then
            local crafts = math.ceil(extra / (m.count or 1))
            made[id] = (made[id] or 0) + crafts * (m.count or 1)
            for ri, rn in pairs(m.reagents or {}) do need[ri] = (need[ri] or 0) + rn * crafts end
            seconds = seconds + crafts * PR.SECONDS_PER_CRAFT
          end
          changed = true
        end
      end
      if not changed then break end
    end
    for id, n in pairs(need) do
      local have = self:Have(id)
      local c = self:ReagentCost(prof, id, ctx)
      local price, src = PD.Price(id)
      local buy = math.max(0, n - have)
      local it = PD.Item(id) or {}
      plan.shopping[id] = { id = id, name = PD.ItemName(id), need = n, have = have, buy = buy, price = price, priceSource = src,
        how = c.how, vendors = it.vendors, limited = it.limited, farm = it.farm, disenchant = PD.IsDisenchantMat(id) or nil }
      if c.how ~= "mine" then money = money + buy * price end
      seconds = seconds + buy * c.sec
    end
    -- Recipes to learn
    local seen = {}
    for _, sg in ipairs(plan.segments) do
      local r = sg.option
      if not seen[r] and not self:KnowsRecipe(profName, r) and r.source ~= "auto" then
        seen[r] = true
        -- 0.9.6 phase P: the source and fee for your side (a recipe a vendor of your side sells is bought there, at its price)
        -- (a vendor recipe only the other side sells, used only where nothing else covers, keeps "vendor": the guide and the window
        -- then say to ask a city guard, phase N's wording)
        local src, fee = self:RecipeSource(r)
        if src == "drop" and r.source == "vendor" then src = r.source end
        plan.recipes[#plan.recipes + 1] = { name = r.name, at = sg.from, source = src, fee = fee or 0, npcs = r.npcs,
          recipeItem = r.recipeItem, recipeName = r.recipeName, limited = r.limited, droppedBy = r.droppedBy, recipe = r }
        money = money + (fee or 0)
      end
    end
    -- Tools (hammer, rods)
    local tseen = {}
    for _, sg in ipairs(plan.segments) do
      for _, tid in ipairs(sg.option.tools or {}) do
        if not tseen[tid] then
          tseen[tid] = true
          local maker = makersIndex(prof)[tid]
          plan.tools[#plan.tools + 1] = { id = tid, name = PD.ItemName(tid), at = sg.from, maker = maker, have = self:Have(tid) > 0 }
        end
      end
    end
  elseif prof.kind == "gathering" then
    plan.totalNodes = 0
    for _, sg in ipairs(plan.segments) do plan.totalNodes = plan.totalNodes + sg.count end
    seconds = plan.totalNodes * PR.SECONDS_PER_NODE
    plan.tips = {}
    for _, sm in ipairs(prof.smelting or {}) do
      if math.max(sm.learn or 1, 1) < plan.to and sm.grey > plan.from then
        plan.tips[#plan.tips + 1] = ("%s gives points from %d to %d (orange until %d)."):format(sm.name, math.max(sm.learn or 1, 1), sm.grey, sm.yellow)
      end
    end
    for _, tid in ipairs(prof.tools or {}) do plan.tools[#plan.tools + 1] = { id = tid, name = PD.ItemName(tid), at = plan.from, have = self:Have(tid) > 0 } end
  else
    local n = 0
    for _, sg in ipairs(plan.segments) do n = n + sg.count end
    plan.totalCatches = n
    seconds = n * PR.SECONDS_PER_CATCH
    for _, tid in ipairs(prof.tools or {}) do plan.tools[#plan.tools + 1] = { id = tid, name = PD.ItemName(tid), at = plan.from, have = self:Have(tid) > 0 } end
  end
  for _, t in ipairs(plan.tools) do
    if not t.have and not t.maker then local p = PD.Price(t.id) money = money + p end
  end
  plan.totalCost, plan.totalSeconds = money, seconds
end

-- Zones for a gathering node, from the generated spawn tables (Panoply Suite Quest Data counts when present).
function PR:NodeZones(node, level)
  local out = {}
  local live = Panoply.QuestData and Panoply.QuestData.Available and Panoply.QuestData:Available() and Panoply.QuestData:NodeSpawnsByMap(node.name) or {}
  for _, z in ipairs(node.zones or {}) do
    out[#out + 1] = { map = z.map, name = z.name, count = live[z.map] or z.count, minLevel = z.minLevel, maxLevel = z.maxLevel, route = z.route }
  end
  for _, z in ipairs(out) do z.dangerous = z.minLevel and level and z.minLevel > level + 3 or false end
  local pos = Panoply.State and Panoply.State.pos
  table.sort(out, function(a, b)
    if a.dangerous ~= b.dangerous then return not a.dangerous end
    if pos and (a.map == pos.map) ~= (b.map == pos.map) then return a.map == pos.map end
    return (a.count or 0) > (b.count or 0)
  end)
  while #out > 4 do table.remove(out) end
  return out
end

-- Trainers near the player, for /panoply prof.
-- 0.9.6 phase O (Nov 17 2026): phase L's own-side lookup (Engine/ProfGuide.lua G:FriendlyNearest). For each rank the plan
-- trains from a trainer (else the rank you hold), the nearest trainer of your side who teaches THAT rank: this zone, then your
-- capitals, then anywhere; Apprentice also counts the trainers only WoW Forever has. Never the other side's, never one whose side
-- is unknown; a neutral one is fine. A trainer teaching several of those ranks is listed once. None of your side known: an entry
-- { rank, guard = true } (the chat says to ask a city guard), or the data's own hint (Annora in Uldaman).
-- { npc, name, title, spot, t, where, ranks = { "Apprentice", ... } } or { rank, fee, guard = true } or { rank, hint }
function PR:Trainers(profName, training, from)
  local prof = PD[profName]
  local G = Panoply.ProfGuide
  if not (prof and G and G.FriendlyNearest) then return {} end
  local pos = Panoply.State and Panoply.State.pos
  local ranks = self:Ranks(prof)
  local function trainerRank(rk) return rk and (rk.source == nil or rk.source == "trainer") end
  local want, seenRank = {}, {}
  for _, t in ipairs(training or {}) do
    local i = t.rankIndex
    if not (i and ranks[i] and ranks[i].name == t.rank) then
      i = nil
      for j, rk in ipairs(ranks) do if rk.name == t.rank then i = j end end
    end
    if i and not seenRank[i] and trainerRank(ranks[i]) then seenRank[i] = true; want[#want + 1] = i end
  end
  if #want == 0 then
    -- nothing to train: the trainers of the rank you hold (they teach its recipes)
    local hold
    for i, rk in ipairs(ranks) do if not hold and (from or 1) < rk.max then hold = i end end
    hold = hold or #ranks
    if ranks[hold] and trainerRank(ranks[hold]) then want[1] = hold end
  end
  local out, byNpc = {}, {}
  for _, i in ipairs(want) do
    local rk = ranks[i]
    local extra = (i == 1 and G.ForeverTrainers) and G:ForeverTrainers(profName) or nil
    local s, where = G:FriendlyNearest(rk.allNpcs or rk.npcs, pos, extra)
    if s then
      local key = s.npc or ((s.name or "?") .. ":" .. tostring(s.map))
      local e = byNpc[key]
      if e then e.ranks[#e.ranks + 1] = rk.name
      else
        e = { npc = s.npc, name = s.name, title = s.title, spot = s, t = s.t, where = where, ranks = { rk.name } }
        byNpc[key] = e
        out[#out + 1] = e
      end
    elseif rk.hint then
      out[#out + 1] = { rank = rk.name, hint = rk.hint }
    else
      out[#out + 1] = { rank = rk.name, fee = rk.fee or 0, guard = true }
    end
  end
  return out
end

-- Plan for the player's current state ("current" mode) or from scratch.
function PR:PlanForPlayer(profName, mode, target, opts)
  local lvl = select(1, C.XP())
  opts = opts or {}
  opts.level = opts.level or lvl
  opts.to = target or opts.to or 300
  if mode ~= "scratch" then
    local rank, max = self:CurrentSkill(profName)
    if rank then opts.from = math.max(rank, 1); opts.maxKnown = max end
  end
  return self:Plan(profName, opts)
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------
local function money(c) return U.FormatMoney(c or 0) end
PR.Money = money

function PR:SegmentText(plan, sg)
  if sg.verb == "mine" then
    local zs = {}
    for _, z in ipairs(sg.zones or {}) do zs[#zs + 1] = z.name .. (z.dangerous and " (high level!)" or "") end
    return ("%s about %d x %s (skill %d-%d) in %s"):format(sg.gather and sg.gather.verb or "Mine", sg.count, sg.name, sg.from, sg.to, table.concat(zs, ", "))
  elseif sg.verb == "fish" then
    return ("Fish about %d times in %s (skill %d-%d)"):format(sg.count, sg.name, sg.from, sg.to)
  end
  local made = sg.makes and PD.ItemName(sg.makes) or sg.name
  if sg.verb == "enchant" then return ("Make %d x %s (skill %d-%d)"):format(sg.count, sg.name, sg.from, sg.to) end
  return ("Make %d x %s (skill %d-%d)"):format(sg.count, made, sg.from, sg.to)
end

function PR:TrainingText(t)
  local where = ""
  if t.source == "quest" and t.quest then where = (" - quest %s"):format(Panoply.Planner.Quoted(t.questTitle or "the rank quest"))
  elseif t.source == "book" and t.book then where = (" - buy %s"):format(t.bookName or "the book")
  elseif t.hint then where = " - " .. t.hint.text end
  return ("At %d: learn %s (up to %d)%s, %s%s"):format(t.at, t.rank, t.max, t.minLevel and t.minLevel > 0 and (", needs level " .. t.minLevel) or "", money(t.fee), where)
end

-- Text lines describing a plan (used by /panoply prof and the self-test).
function PR:Describe(plan)
  local L = {}
  local function add(s) L[#L + 1] = s end
  add(("%s %d -> %d (%s)"):format(plan.prof, plan.from, plan.to, plan.strategy == "fastest" and "fastest" or "cheapest"))
  for _, t in ipairs(plan.training) do add("  " .. self:TrainingText(t)) end
  for _, sg in ipairs(plan.segments) do add("  " .. self:SegmentText(plan, sg)) end
  if plan.kind == "crafting" then
    add("  Shopping list (after your bags, bank and mail):")
    local ids = U.Keys(plan.shopping)
    table.sort(ids, function(a, b) return plan.shopping[a].name < plan.shopping[b].name end)
    for _, id in ipairs(ids) do
      local s = plan.shopping[id]
      add(("    %s: need %d, have %d, get %d (%s each, %s)"):format(s.name, s.need, s.have, s.buy, money(s.price), s.priceSource))
    end
    for _, r in ipairs(plan.recipes) do add(("  Recipe at %d: %s (%s, %s)"):format(r.at, r.name, r.source, money(r.fee))) end
  elseif plan.kind == "gathering" then
    add((plan.prof == "Skinning" and "  About %d skins in total." or "  About %d nodes in total."):format(plan.totalNodes or 0))
    for _, t in ipairs(plan.tips or {}) do add("  Tip: " .. t) end
  end
  for _, t in ipairs(plan.tools) do add("  Tool: " .. t.name .. (t.have and " (you have it)" or "")) end
  add("  Estimated cost: " .. money(plan.totalCost) .. (", about %d minutes"):format(math.floor((plan.totalSeconds or 0) / 60)))
  -- 0.9.6 phase O: trainers of your side only (PR:Trainers); none known: phase L's "ask a city guard" wording
  local G = Panoply.ProfGuide
  local TC = G and G.TRAINER_COPY
  local guard = false
  for _, t in ipairs(plan.trainers or {}) do
    if t.guard then
      guard = true
      add("  " .. (TC and TC.train or "Train %s %s (%s): ask a city guard for a trainer"):format(t.rank, plan.prof, money(t.fee)))
    elseif t.hint then
      add("  Trainer for " .. t.rank .. ": " .. (t.hint.text or t.hint.short or ""))
    else
      local zone = t.spot and t.spot.map and C.MapName and C.MapName(t.spot.map)
      add("  Trainer: " .. (t.name or "?") .. " <" .. (t.title or "") .. ">" .. (zone and (", " .. zone) or "")
        .. (t.ranks and #t.ranks > 0 and (" (" .. table.concat(t.ranks, ", ") .. ")") or ""))
    end
  end
  if guard and TC and TC.guard then add("  " .. TC.guard) end
  for _, w in ipairs(plan.warnings) do add("  Note: " .. w) end
  return L
end

-- Blacksmithing specialization note (shown at 200+, never forced).
function PR:SpecNote(profName, skill)
  if profName ~= "Blacksmithing" then return nil end
  return "At skill 200 and level 40 you can choose Armorsmith or Weaponsmith (Weaponsmiths later pick Axe, Hammer or Sword) through quests from the specialization trainers. Neither is needed to reach 300; Panoply Suite leaves specialization recipes out until you choose one in Settings."
end
