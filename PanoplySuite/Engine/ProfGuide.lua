-- Panoply Suite ProfGuide: turns a profession plan into LIVE guide steps with the arrow.
-- It looks at your skill, cap, known recipes, bags/bank/mail and position every time something
-- changes, and produces the queue of what to do right now:
--   learn the profession -> train the next rank -> get tools -> learn the recipe ->
--   fetch / buy / mine / smelt / farm missing materials -> craft N x item (skill A->B).
-- Because the queue is rebuilt from live state, steps auto-advance on skill-ups, item counts and
-- training, and missing materials re-insert gather or buy steps on their own.
-- Modes: "interleave" (profession steps take over the guide when they are close by),
--        "only" (professions only) and "off" (floating tracker only).
local ADDON, Panoply = ...
local G = { queue = {}, snoozed = {}, plans = {} }
Panoply.ProfGuide = G
local PD, C, U = Panoply.ProfData, Panoply.Compat, Panoply.Util

G.NEAR_SECONDS = 90          -- interleave: take over when the step is this close (travel time)
G.ROUTE_RADIUS = 40          -- yards: hotspot reached, point the arrow at the next one
G.SNOOZE_SECONDS = 900
G.MODES = { "interleave", "only", "off" }
G.MODE_LABELS = { interleave = "Mixed with levelling", only = "Professions only", off = "Tracker only" }

local function PR() return Panoply.Professions end
local function now() return (_G.GetTime and GetTime()) or 0 end
local function money(c) return U.FormatMoney(c or 0) end
local function mapName(m) return (m and C.MapName(m)) or "the world" end
local function plural(n, word) return n == 1 and word or (word:gsub("y$", "ie") .. "s") end

-------------------------------------------------------------------------------
-- Which profession are we guiding?
-------------------------------------------------------------------------------
-- Which guide is active, per character: "leveling", "professions" or "both" (profession steps
-- woven into the route when close by). Each guide keeps its own place: the levelling route keeps
-- its step index, and the profession guide is rebuilt from your skill, bags and trainers, so
-- switching back resumes exactly where you were.
G.GUIDES = { "leveling", "professions", "both" }
G.GUIDE_LABELS = { leveling = "Leveling", professions = "Professions", both = "Both" }
G.GUIDE_TO_MODE = { leveling = "off", professions = "only", both = "interleave" }
G.MODE_TO_GUIDE = { off = "leveling", only = "professions", interleave = "both" }

function G:Active()
  local a = Panoply.cdb and Panoply.cdb.activeGuide
  if G.GUIDE_TO_MODE[a] then return a end
  return G.MODE_TO_GUIDE[(Panoply.db and Panoply.db.profGuide) or "interleave"] or "both"
end
function G:Mode() return G.GUIDE_TO_MODE[self:Active()] end

-- Switch the active guide (and optionally the profession it follows).
function G:SetActive(guide, prof)
  if not G.GUIDE_TO_MODE[guide] or not Panoply.cdb then return false end
  local before = self:Active()
  Panoply.cdb.activeGuide = guide
  if Panoply.db then Panoply.db.profGuide = G.GUIDE_TO_MODE[guide] end   -- default for characters without a choice yet
  if prof then Panoply.cdb.profTrack = prof; self.forced = nil end
  if guide == "leveling" then self.forced = nil end
  self:Refresh("switch")
  -- back on the route: catch up with anything already done, then carry on from the saved step
  if guide ~= "professions" and Panoply.Engine then Panoply.Engine:Check() end
  if Panoply.Arrow and Panoply.Arrow.Refresh then pcall(Panoply.Arrow.Refresh, Panoply.Arrow) end
  Panoply:Fire("GUIDE_SWITCHED", guide, before)
  Panoply:Fire("OPTION_CHANGED", "activeGuide")
  return true
end

-- Flip between the levelling and the profession guide ("Both" flips to Leveling).
function G:Switch()
  local a = self:Active()
  local nxt = a == "leveling" and "professions" or "leveling"
  self:SetActive(nxt)
  return nxt
end

-- Next detected profession that has a plan (the cycle button on the guide window).
function G:CycleProfession()
  local list = self:Chosen()
  if #list == 0 then return nil end
  local cur = self:Tracked()
  local i = 1
  for k, n in ipairs(list) do if n == cur then i = k end end
  local nxt = list[(i % #list) + 1]
  if Panoply.cdb then Panoply.cdb.profTrack = nxt end
  self.forced = nil
  self:Refresh("track")
  Panoply:Fire("OPTION_CHANGED", "profTrack")
  return nxt
end

function G:Chosen()
  local out = {}
  local ch = Panoply.cdb and Panoply.cdb.professions or {}
  for _, k in ipairs({ "primary", "secondary" }) do
    for _, n in ipairs(ch[k] or {}) do if PD[n] and PD[n].ranks then out[#out + 1] = n end end
  end
  return out
end

-- Crafting professions first (a crafting plan pulls its gathering partner along through materials).
function G:Tracked()
  local t = Panoply.cdb and Panoply.cdb.profTrack
  local chosen = self:Chosen()
  for _, n in ipairs(chosen) do if n == t then return n end end
  for _, n in ipairs(chosen) do if PD[n].kind == "crafting" and not PD.SECONDARY[n] then return n end end
  return chosen[1]
end

function G:SetTracked(name)
  if Panoply.cdb then Panoply.cdb.profTrack = name end
  self:Refresh("track")
end

-------------------------------------------------------------------------------
-- Plans (cached; recomputed when skill, cap, strategy or level change)
-------------------------------------------------------------------------------
function G:PlanFor(profName)
  local P = PR()
  local rank, max = P:CurrentSkill(profName)
  local S = Panoply.State
  -- 0.9.5 (phase 4B): each profession has its own plan (Engine/ProfPlans.lua); the old global choice is where it starts
  local strategy = (Panoply.ProfPlans and Panoply.ProfPlans:Strategy(profName)) or (Panoply.db and Panoply.db.profStrategy) or "cheapest"
  local spec = Panoply.cdb and Panoply.cdb.profSpec and Panoply.cdb.profSpec[profName] or ""
  local key = table.concat({ profName, rank or 0, max or 0, strategy, spec, S.level or 1, P:CurrentSkill("Mining") and 1 or 0 }, "|")
  local c = self.plans[profName]
  if c and c.key == key then return c.plan end
  local plan = P:PlanForPlayer(profName, "current", 300, { strategy = strategy })
  self.plans[profName] = { key = key, plan = plan }
  return plan
end

function G:Invalidate() self.plans = {} end

-------------------------------------------------------------------------------
-- Step helpers
-------------------------------------------------------------------------------
local function spotStep(step, spot)
  if spot then step.mapID, step.x, step.y = spot.map, spot.x, spot.y end
  return step
end

local function npcWhere(spot)
  if not spot then return "" end
  return (spot.name or "the trainer") .. " in " .. mapName(spot.map)
end

-------------------------------------------------------------------------------
-- 0.9.6 phase L (Nov 17 2026): trainers of the player's own side. The profession data's `npcs` lists hold only Alliance-side
-- NPCs (tools/build_profdata.py); its `allNpcs` lists (new) hold both sides, and every NPC record carries its side ("A", "H",
-- "AH"). Every trainer step picks the nearest trainer the player's side may use, in the order of the Professions page's starter
-- picker (UI/ProfPage.lua): this zone, then the player's own capital cities, then anywhere else; none known -> "ask a guard"
-- (no coordinates). An enemy trainer is never offered, and an NPC whose side is unknown counts as not friendly.
-------------------------------------------------------------------------------
-- the capital cities of each side (the same maps as UI/ProfPage.lua's PUI.CAPITALS)
G.CAPITALS = { Alliance = { [1453] = true, [1455] = true, [1457] = true }, Horde = { [1454] = true, [1456] = true, [1458] = true } }
G.TRAINER_COPY = {
  learn = "Learn %s (%s): ask a city guard for a trainer",   -- PLACEHOLDER COPY (Marketing)
  train = "Train %s %s (%s): ask a city guard for a trainer",   -- PLACEHOLDER COPY (Marketing)
  recipe = "Learn %s (%s): ask a city guard for a %s trainer",   -- PLACEHOLDER COPY (Marketing)
  guard = "No trainer of your side is known nearby. City guards mark the trainer on your map.",   -- PLACEHOLDER COPY (Marketing)
}
local function playerFaction() return _G.UnitFactionGroup and _G.UnitFactionGroup("player") or nil end
-- may the player use this NPC? The quest data's own side first (Engine/QuestData.lua, as the starter picker asks it), else the
-- profession data's side for it (rec, or its PD.WORLD record). Unknown side, or no side for the player: not friendly.
function G.NpcFriendly(id, rec)
  local f = playerFaction()
  local me = (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
  if not me then return false end
  local QD = Panoply.QuestData
  if type(id) == "number" and QD and QD.NpcFriendly then
    local ok, v = pcall(QD.NpcFriendly, QD, id)
    if ok and v ~= nil then return v == true end
  end
  local side = rec and rec.side
  if side == nil and type(id) == "number" then
    local w = PD.World().npcs[id]
    side = w and w.side
  end
  return type(side) == "string" and side:find(me, 1, true) ~= nil
end
-- the NPC ids a rank or recipe offers: both sides' list where the data has it, else the old list
local function npcIds(rec) return rec and (rec.allNpcs or rec.npcs) or {} end
-- WoW Forever only: profession trainers only Forever has, from a `trainers` table in the data add-on's Professions/Forever.lua.
-- No such table ships in this release, so this returns {}. A listed trainer's rank is not known: offered only to learn the profession.
function G:ForeverTrainers(profName)
  if not (C.IsForever and C.IsForever()) then return {} end
  local ext = rawget(_G, "PanoplySuiteQuestData")
  local F = type(ext) == "table" and ext.ProfDataForever
  local t = type(F) == "table" and type(F.trainers) == "table" and F.trainers[profName]
  return type(t) == "table" and t or {}
end
-- The nearest NPC of `ids` (and `extra` records { npc, name, map, x, y, side }) the player's side may use, by travel time:
-- in this zone first, then in the player's own capitals, then anywhere. Returns spot (with .t), where ("zone" | "city" |
-- "near"), or nil, "guard" when none is known.
function G:FriendlyNearest(ids, pos, extra)
  pos = pos or Panoply.State.pos
  local caps = G.CAPITALS[playerFaction() or ""] or {}
  local here = pos and pos.map
  local best = {}
  local function consider(s)
    s.t = PD.Travel(pos, s)
    local tier = (here and s.map == here and "zone") or (caps[s.map] and "city") or "near"
    if not best[tier] or s.t < best[tier].t then best[tier] = s end
  end
  for _, id in ipairs(ids or {}) do
    if G.NpcFriendly(id) then
      local s = PD.NpcSpot(id)
      if s and s.map then consider(s) end
    end
  end
  for _, e in ipairs(extra or {}) do
    if type(e) == "table" and e.map and G.NpcFriendly(e.npc, e) then
      consider({ map = e.map, x = e.x, y = e.y, name = e.name, npc = e.npc, side = e.side })
    end
  end
  for _, tier in ipairs({ "zone", "city", "near" }) do
    if best[tier] then return best[tier], tier end
  end
  return nil, "guard"
end

-------------------------------------------------------------------------------
-- 0.9.6 phase N (Nov 17 2026): vendors of the player's own side. Items' `vendors` and vendor recipes' `npcs` hold only
-- Alliance-side NPCs; the new `allVendors` (items) and `allNpcs` (recipes) hold both sides, with `limitedVendors` /
-- `limitedNpcs` naming the ones with limited stock. Every "Buy from a vendor" step (materials, tools, recipes) takes the nearest
-- vendor of your side by G:FriendlyNearest (this zone, your capitals, anywhere); none known -> "ask a city guard" (no spot).
-------------------------------------------------------------------------------
G.VENDOR_COPY = {
  material = "Buy %d x %s: ask a city guard for a trade goods vendor",   -- PLACEHOLDER COPY (Marketing)
  tool = "Buy a %s (%s): ask a city guard for a trade goods vendor",   -- PLACEHOLDER COPY (Marketing)
  recipe = "Buy %s (%s): ask a city guard for a %s supplies vendor",   -- PLACEHOLDER COPY (Marketing)
  guard = "No vendor of your side is known nearby. City guards mark vendors on your map; the Auction House may have it too.",   -- PLACEHOLDER COPY (Marketing)
}
-- does the chosen vendor have limited stock? The per-vendor list where the data has both sides' list, else the old flag
local function limitedAt(v, all, list, old)
  if not all then return old and true or false end
  if not v then return false end
  for _, id in ipairs(list or {}) do if id == v.npc then return true end end
  return false
end

local function haveGoal(id, count, where, label)
  return { type = "have", itemID = id, count = count, where = where or "all", label = label or PD.ItemName(id) }
end

local function profSkillGoal(profName, to, made)
  return { type = "profskill", prof = profName, skillLine = PD.SKILL_LINES[profName], skill = to, made = made }
end

function G:NewStep(profName, kind, key, title, why)
  return { kind = kind, isProf = true, prof = profName, key = profName .. ":" .. key, title = title, why = why, goals = {} }
end

-------------------------------------------------------------------------------
-- Goal types used by profession steps
-------------------------------------------------------------------------------
local Goals = Panoply.Goals
Goals.eval.have = function(g, s)
  local n
  if g.where == "bags" then n = PR():HaveInBags(g.itemID) else n = PR():Have(g.itemID) end
  g.current = n
  g.text = ("%s: %d/%d"):format(g.label or PD.ItemName(g.itemID), math.min(n, g.count), g.count)
  return n >= (g.count or 1) and Goals.DONE or Goals.TODO
end
Goals.eval.profskill = function(g, s)
  local r = s.skills[g.skillLine] or s.skills[g.prof] or 0
  local parts = { ("%s %d/%d"):format(g.prof, r, g.skill) }
  if g.made then
    local m = Panoply.cdb and Panoply.cdb.profMade and Panoply.cdb.profMade[g.made.key] or 0
    local base = g.made.base or 0
    local done = math.max(0, m - base)
    parts[#parts + 1] = ("%d of %d made"):format(math.min(done, g.made.total), g.made.total)
  end
  g.text = table.concat(parts, "  -  ")
  return r >= (g.skill or 1) and Goals.DONE or Goals.TODO
end
Goals.eval.skillmax = function(g, s)
  local m = s.skillMax and (s.skillMax[g.skillLine] or s.skillMax[g.prof]) or 0
  return m >= (g.max or 1) and Goals.DONE or Goals.TODO
end
Goals.eval.recipe = function(g, s)
  return (g.confirmed or PR():KnowsRecipe(g.prof, g.recipe)) and Goals.DONE or Goals.TODO
end
Goals.eval.hasprof = function(g, s)
  local r = s.skills[g.skillLine] or s.skills[g.prof]
  return (r and r > 0) and Goals.DONE or Goals.TODO
end
-- Moving hotspot: the arrow walks a loop of spawn clusters; never blocks the step.
Goals.eval.route = function(g, s)
  local pts = g.points or {}
  if #pts == 0 then return Goals.TODO end
  g.i = g.i or 1
  -- Gathering module: head for the nearest node of this kind you (or the database) know about.
  local Gat = Panoply.Gathering
  if g.node and Gat and Gat.active and s.pos and s.pos.map == g.map then
    local n, d = Gat:Nearest(g.node, s.pos)
    if n then
      g.mapID, g.x, g.y = g.map, n[3], n[4]
      g.nearest = n
      g.text = ("Nearest %s: %d yards"):format(n[2] or g.label or "node", math.floor((d or 0) + 0.5))
      return Goals.TODO
    end
  end
  g.nearest = nil
  local p = pts[g.i]
  if s.pos and p then
    local d = Panoply.Nav.Distance(s.pos.map, s.pos.x, s.pos.y, g.map, p[1], p[2])
    if d and d <= G.ROUTE_RADIUS then g.i = g.i % #pts + 1; p = pts[g.i] end
  end
  g.mapID, g.x, g.y = g.map, p[1], p[2]
  g.text = ("%s: spot %d of %d"):format(g.label or "Route", g.i, #pts)
  return Goals.TODO
end

-------------------------------------------------------------------------------
-- Materials: expand a need into buy / bank / mine / smelt / farm / craft steps
-------------------------------------------------------------------------------
local function nodeFor(oreID, miningRank)
  local best
  for _, n in ipairs(PD.Mining and PD.Mining.nodes or {}) do
    for _, o in ipairs(n.oreIds or {}) do
      if o == oreID and not PR().RARE_NODES[n.name] and not n.name:find("^Ooze") then
        if not best or (n.learn or 0) < (best.learn or 0) then best = n end
      end
    end
  end
  return best
end

local function bestZone(zones, level)
  local pos = Panoply.State.pos
  local best, bestScore
  for _, z in ipairs(zones or {}) do
    local danger = (z.minLevel or 1) > (level or 60) + 3
    local score = (danger and 1e6 or 0) + ((pos and z.map == pos.map) and 0 or 1000) - (z.count or 0)
    if not bestScore or score < bestScore then best, bestScore = z, score end
  end
  return best
end

local function routeGoal(zone, label, node)
  if not zone or not zone.route or #zone.route == 0 then return nil end
  return { type = "route", hint = true, map = zone.map, points = zone.route, label = label, node = node }
end

function G:AddMaterialSteps(out, profName, prof, need, ctx, depth)
  depth = depth or 0
  local P = PR()
  local pos = Panoply.State.pos
  local level = Panoply.State.level or 1
  local ids = U.Keys(need)
  table.sort(ids)
  local later = {}
  for _, id in ipairs(ids) do
    local n = need[id]
    local have, bags = P:Have(id), P:HaveInBags(id)
    local name = PD.ItemName(id)
    if have >= n then
      if bags < n then
        local st = self:NewStep(profName, "profbank", "bank:" .. id, ("Take %d x %s from your bank or mailbox"):format(n - bags, name),
          "You already own enough; it just needs to be in your bags to craft with.")
        st.goals[1] = haveGoal(id, n, "bags")
        out[#out + 1] = st
      end
    else
      local missing = n - have
      local c = P:ReagentCost(prof, id, ctx)
      local it = PD.Item(id) or {}
      -- You already hold what it is made from (cloth for bolts): make it rather than buy it.
      -- 0.9.6 phase N: the nearest vendor of your side (both sides' list where the data has it)
      local vids = it.allVendors or it.vendors
      local v, vwhere
      if vids and #vids > 0 then v, vwhere = self:FriendlyNearest(vids, pos) end
      local mk = P:Maker(prof, id)
      if mk and c.how ~= "craft" and P:Usable(profName, prof, mk, ctx) then
        local crafts, enough = math.ceil(missing / (mk.count or 1)), true
        for rid, rn in pairs(mk.reagents or {}) do if P:Have(rid) < rn * crafts then enough = false end end
        if enough then c = { how = "craft", recipe = mk } end
      end
      if c.how == "craft" and depth < 3 then
        local m = c.recipe
        local crafts = math.ceil(missing / (m.count or 1))
        local sub = {}
        for rid, rn in pairs(m.reagents or {}) do sub[rid] = (sub[rid] or 0) + rn * crafts end
        self:AddMaterialSteps(out, profName, prof, sub, ctx, depth + 1)
        local st = self:NewStep(profName, "profcraft", "mid:" .. id, ("Make %d x %s"):format(missing, name),
          ("You need %d %s for the next crafts; make them from the materials above."):format(n, name))
        st.goals[1] = haveGoal(id, n)
        self:AttachFocus(st, m.focus, pos)
        later[#later + 1] = st
      elseif c.how == "smelt" and depth < 3 then
        local m = c.recipe
        local crafts = math.ceil(missing / (m.count or 1))
        local sub = {}
        for rid, rn in pairs(m.reagents or {}) do sub[rid] = (sub[rid] or 0) + rn * crafts end
        self:AddMaterialSteps(out, profName, PD.Mining, sub, ctx, depth + 1)
        local st = self:NewStep(profName, "profsmelt", "smelt:" .. id, ("Smelt %d x %s at a forge"):format(missing, name),
          ("Open Mining (Smelting) at a forge. Smelting also gives Mining skill while it is not grey."))
        st.goals[1] = haveGoal(id, n)
        self:AttachFocus(st, "forge", pos)
        later[#later + 1] = st
      elseif c.how == "mine" and nodeFor(id) then
        local mr = P:CurrentSkill("Mining") or 0
        local node = nodeFor(id, mr)
        if node and mr >= math.max(node.learn or 1, 1) then
          self:ToolSteps(out, "Mining", PD.Mining, PD.Mining.tools or { 2901 }, pos)
          local z = bestZone(node.zones, level)
          local st = self:NewStep(profName, "profgather", "mine:" .. id,
            ("Mine %s in %s (%s: %d/%d)"):format(node.name:gsub("Vein$", "Veins"):gsub("Deposit$", "Deposits"), z and z.name or "the hills", name, math.min(have, n), n),
            ("Follow the arrow round the spawn spots. Every vein you mine also raises your Mining."))
          st.goals[1] = haveGoal(id, n)
          local rg = routeGoal(z, node.name .. " spots", node.name)
          if rg then st.goals[2] = rg; spotStep(st, { map = z.map, x = z.route[1][1], y = z.route[1][2] }) end
          st.gather = true
          st.zoneMap = z and z.map
          out[#out + 1] = st
        elseif mr == 0 then
          out[#out + 1] = self:LearnProfessionStep("Mining", PD.Mining, pos)
        else
          -- Mining too low for this ore: level Mining first (or buy it).
          local ah, ahWhere = PD.NearestAuctioneer(pos)   -- 0.9.6 phase P: an auctioneer of your side or a neutral one
          local st = self:NewStep(profName, "profgather", "minelvl:" .. id,
            ("Raise Mining to %d to mine %s (now %d), or buy %d x %s"):format(math.max(node.learn or 1, 1), node.name, mr, missing, name),
            "Your Mining is behind your crafting. The Mining plan below gets you there; the Auction House is the quick alternative." .. (ah and "" or (" " .. PD.AH_COPY.guard)))
          st.goals[1] = haveGoal(id, n)
          st.goals[2] = { type = "profskill", hint = true, prof = "Mining", skillLine = PD.SKILL_LINES.Mining, skill = math.max(node.learn or 1, 1) }
          spotStep(st, ah)
          st.auction, st.auctionWhere = ah, ah and ahWhere or "guard"
          st.gather = true
          out[#out + 1] = st
        end
      elseif v and (c.how == "vendor" or not it.farm) then
        local st = self:NewStep(profName, "profbuy", "buy:" .. id, ("Buy %d x %s from %s"):format(missing, name, npcWhere(v)),
          ("%s each%s."):format(money(PD.ItemPrice(id) or PD.Price(id)), limitedAt(v, it.allVendors, it.limitedVendors, it.limited) and " (limited stock: buy what they have, it restocks)" or ""))
        st.goals[1] = haveGoal(id, n)
        spotStep(st, v)
        st.vendor, st.vendorWhere = v, vwhere
        out[#out + 1] = st
      elseif vids and #vids > 0 and c.how == "vendor" then
        -- 0.9.6 phase N: a vendor item, but no vendor of your side is known: ask a guard (no spot, never the other side's vendor)
        local st = self:NewStep(profName, "profbuy", "buy:" .. id, G.VENDOR_COPY.material:format(missing, name),
          ("%s each. %s"):format(money(PD.ItemPrice(id) or PD.Price(id)), G.VENDOR_COPY.guard))
        st.goals[1] = haveGoal(id, n)
        st.vendorWhere = "guard"
        local ah, ahWhere = PD.NearestAuctioneer(pos)   -- 0.9.6 phase P: an auctioneer of your side or a neutral one (none: no alt)
        st.alt, st.auction, st.auctionWhere = ah, ah, ah and ahWhere or "guard"
        out[#out + 1] = st
      elseif PD.IsDisenchantMat(id) then
        local src = PD.DisenchantSources(id)[1]
        local ah, ahWhere = PD.NearestAuctioneer(pos)   -- 0.9.6 phase P: an auctioneer of your side or a neutral one
        local why = src and ("Disenchant green %s of item level %d-%d (about %d%% give %s)"):format(src.kind, src.minIlvl, src.maxIlvl, math.floor(src.chance), name) or "Disenchant green items"
        if profName == "Enchanting" and P:Chosen("Tailoring") then why = why .. ". Your own Tailoring greens are perfect for this" end
        local st = self:NewStep(profName, "profde", "de:" .. id, ("Get %d x %s: disenchant greens or buy at the Auction House"):format(missing, name),
          why .. "." .. (ah and "" or (" " .. PD.AH_COPY.guard)))
        st.goals[1] = haveGoal(id, n)
        spotStep(st, ah)
        st.alt, st.auction, st.auctionWhere = ah, ah, ah and ahWhere or "guard"
        out[#out + 1] = st
      else
        local farm = it.farm and it.farm[1]
        local ah, ahWhere = PD.NearestAuctioneer(pos)   -- 0.9.6 phase P: an auctioneer of your side or a neutral one
        local fz
        for _, f in ipairs(it.farm or {}) do if (f.minLevel or 1) <= level + 2 then fz = fz or f end end
        local st
        if fz and ((ctx.strategy ~= "fastest") or not ah) then
          st = self:NewStep(profName, "proffarm", "farm:" .. id, ("Collect %d x %s in %s"):format(missing, name, fz.name),
            ("Enemies there drop it (about %d%% per kill). Or buy it at the Auction House."):format(math.floor((fz.perKill or 0) * 100 + 0.5)) .. (ah and "" or (" " .. PD.AH_COPY.guard)))
          local rg = routeGoal(fz, "Hunting spots")
          st.goals[1] = haveGoal(id, n)
          if rg then st.goals[2] = rg; spotStep(st, { map = fz.map, x = fz.route[1][1], y = fz.route[1][2] }) end
          st.gather = true
        else
          -- 0.9.6 phase P: no auctioneer of your side or a neutral one known: ask a city guard for the Auction House (no spot)
          st = self:NewStep(profName, "profah", "ah:" .. id, ah and ("Buy %d x %s at the Auction House"):format(missing, name) or ("Buy %d x %s: %s"):format(missing, name, PD.AH_COPY.short),
            (fz and ("Or collect it yourself: enemies in %s drop it."):format(fz.name) or ("About %s each (a guess; set your own price with /panoply price)."):format(money(PD.ItemPrice(id) or 0)))
            .. (ah and "" or (" " .. PD.AH_COPY.guard)))
          st.goals[1] = haveGoal(id, n)
          spotStep(st, ah)
        end
        st.alt, st.auction, st.auctionWhere = ah, ah, ah and ahWhere or "guard"
        out[#out + 1] = st
      end
    end
  end
  for _, st in ipairs(later) do out[#out + 1] = st end
end

-- Tools you must carry. Crafted tools add their materials to `need` and their craft step to `crafts`.
function G:ToolSteps(out, profName, prof, toolIds, pos, need, crafts)
  local P = PR()
  for _, tid in ipairs(toolIds or {}) do
    if P:HaveInBags(tid) == 0 then
      local maker
      for _, r in ipairs(prof.recipes or {}) do if r.makes == tid then maker = r end end
      local it = PD.Item(tid) or {}
      local tname = PD.ItemName(tid)
      if maker and need then
        if not P:KnowsRecipe(profName, maker) then for _, st in ipairs(self:RecipeSteps(profName, maker, pos)) do out[#out + 1] = st end end
        for rid, rn in pairs(maker.reagents or {}) do need[rid] = (need[rid] or 0) + rn end
        local st = self:NewStep(profName, "profcraft", "tool:" .. tid, ("Make a %s"):format(tname), "Your next recipes need it in your bags.")
        st.goals[1] = haveGoal(tid, 1, "bags")
        self:AttachFocus(st, maker.focus, pos)
        crafts[#crafts + 1] = st
      else
        -- 0.9.6 phase N: the nearest vendor of your side; none known: ask a guard
        local vids = it.allVendors or it.vendors
        local v, vwhere
        if vids and #vids > 0 then v, vwhere = self:FriendlyNearest(vids, pos) end
        local price = money(PD.ItemPrice(tid) or PD.Price(tid))   -- 0.9.6 phase P: your side's vendor price
        local st = self:NewStep(profName, "proftool", "tool:" .. tid,
          v and ("Buy a %s from %s"):format(tname, npcWhere(v)) or G.VENDOR_COPY.tool:format(tname, price),
          v and ("%s. Keep it in your bags while you work."):format(price) or ("Keep it in your bags while you work. %s"):format(G.VENDOR_COPY.guard))
        st.goals[1] = haveGoal(tid, 1, "bags")
        spotStep(st, v)
        st.vendor, st.vendorWhere = v, v and vwhere or "guard"
        out[#out + 1] = st
      end
    end
  end
end

function G:AttachFocus(st, focus, pos)
  if not focus then return end
  local f = PD.NearestFocus(focus, pos or Panoply.State.pos)
  local label = focus == "anvil" and "an anvil" or focus == "forge" and "a forge" or focus == "cooking" and "a cooking fire" or focus
  st.focusLabel = label
  if f then
    spotStep(st, f)
    st.goals[#st.goals + 1] = { type = "goto", hint = true, mapID = f.map, x = f.x, y = f.y, radius = 8, text = "Go to " .. label .. " in " .. mapName(f.map) }
  end
end

-------------------------------------------------------------------------------
-- Training / learning
-------------------------------------------------------------------------------
function G:TrainStep(profName, prof, rk, idx, pos, rank, max)
  local line = PD.SKILL_LINES[profName]
  local level = Panoply.State.level or 1
  if level < (rk.minLevel or 0) then
    local st = self:NewStep(profName, "profwait", "level:" .. rk.name,
      ("Reach level %d to train %s %s"):format(rk.minLevel, rk.name, profName),
      ("Your %s is capped at %d. Keep levelling; Panoply Suite brings you back here at level %d."):format(profName, max, rk.minLevel))
    st.goals[1] = { type = "level", level = rk.minLevel - 1 }
    st.wait = true
    return { st }
  end
  local steps = {}
  local fee = money(rk.fee)
  if rk.source == "book" and rk.book then
    local v = self:FriendlyNearest(npcIds(rk), pos)   -- 0.9.6 phase L: a vendor of your side
    local st = self:NewStep(profName, "proftrain", "book:" .. rk.name, ("Buy %s from %s (%s)"):format(rk.bookName or "the book", v and npcWhere(v) or "the vendor", fee),
      ("Reading it teaches %s %s (up to %d)."):format(rk.name, profName, rk.max))
    st.goals[1] = haveGoal(rk.book, 1, "all", rk.bookName)
    st.goals[1].onlyIf = function(s) return not ((s.skillMax[line] or s.skillMax[profName] or 0) >= rk.max) end
    st.goals[2] = { type = "skillmax", hint = true, prof = profName, skillLine = line, max = rk.max, text = ("Then read it: %s cap %d"):format(profName, rk.max) }
    spotStep(st, v)
    steps[#steps + 1] = st
    local rd = self:NewStep(profName, "proftrain", "read:" .. rk.name, ("Read the %s in your bags"):format(rk.bookName or "book"),
      ("Right-click it to learn %s %s."):format(rk.name, profName))
    rd.goals[1] = { type = "skillmax", prof = profName, skillLine = line, max = rk.max, text = ("%s cap %d"):format(profName, rk.max) }
    steps[#steps + 1] = rd
    return steps
  elseif rk.source == "quest" and rk.quest then
    -- 0.9.6 phase L: each side may have its own rank quest (Triage: one doctor per side); take the one with a giver of your side
    local quest, title = rk.quest, rk.questTitle
    local giver = self:FriendlyNearest(rk.npcs, pos)
    for _, q in ipairs(rk.allQuests or {}) do
      local g = self:FriendlyNearest(q.npcs, pos)
      if g and (not giver or g.t < giver.t) then giver, quest, title = g, q.quest, q.questTitle or title end
    end
    local qn = Panoply.Planner.Quoted(title or "the rank quest")
    local st = self:NewStep(profName, "proftrain", "quest:" .. rk.name, ("Get %s from %s"):format(qn, giver and npcWhere(giver) or "its quest giver"),
      ("This quest unlocks %s %s (up to %d). It needs level %d and skill %d."):format(rk.name, profName, rk.max, rk.minLevel or 0, rk.minSkill or 0))
    st.goals[1] = { type = "accept", questID = quest, text = "Accept " .. qn }
    spotStep(st, giver)
    steps[#steps + 1] = st
    local fin = self:NewStep(profName, "proftrain", "questdone:" .. rk.name, ("Finish %s and hand it in"):format(qn),
      ("Your quest log shows what it needs. Handing it in raises your %s cap to %d."):format(profName, rk.max))
    fin.goals[1] = { type = "skillmax", prof = profName, skillLine = line, max = rk.max, text = ("%s cap %d"):format(profName, rk.max) }
    spotStep(fin, giver)
    steps[#steps + 1] = fin
    return steps
  end
  -- 0.9.6 phase L: a trainer of your side who teaches THIS rank (each rank's own list), nearest in this zone, a capital, anywhere
  local t, where = self:FriendlyNearest(npcIds(rk), pos)
  local title = ("Train %s %s with %s (%s)"):format(rk.name, profName, t and npcWhere(t) or "a trainer", fee)
  local why = ("Raises your %s cap from %d to %d so you can keep going."):format(profName, max or 0, rk.max)
  if not t and rk.hint then
    -- the data's own hint (Annora inside Uldaman: a neutral trainer, both sides)
    title = ("Train %s %s (%s)"):format(rk.name, profName, fee); why = rk.hint.text; t = { map = rk.hint.map, x = rk.hint.x, y = rk.hint.y }; where = "hint"
  elseif not t then
    title = G.TRAINER_COPY.train:format(rk.name, profName, fee); why = why .. " " .. G.TRAINER_COPY.guard
  end
  local st = self:NewStep(profName, "proftrain", "train:" .. rk.name, title, why)
  st.goals[1] = { type = "skillmax", prof = profName, skillLine = line, max = rk.max, text = ("%s cap %d"):format(profName, rk.max) }
  st.goals[2] = { type = "learn", hint = true, spellID = rk.spell, text = "Talk to the trainer and learn the rank" }
  spotStep(st, t)
  st.trainer = t
  st.trainerWhere = where
  steps[#steps + 1] = st
  return steps
end

function G:LearnProfessionStep(profName, prof, pos)
  local rk = prof.ranks[1]
  -- 0.9.6 phase L: an Apprentice trainer of your side (plus, on WoW Forever, the trainers only Forever has)
  local t, where = self:FriendlyNearest(npcIds(rk), pos, self:ForeverTrainers(profName))
  local title = t and ("Learn %s from %s (%s)"):format(profName, npcWhere(t), money(rk.fee)) or G.TRAINER_COPY.learn:format(profName, money(rk.fee))
  local why = ("Apprentice %s lets you start (up to %d)."):format(profName, rk.max)
  if not t then why = why .. " " .. G.TRAINER_COPY.guard end
  local st = self:NewStep(profName, "proftrain", "learn", title, why)
  st.goals[1] = { type = "hasprof", prof = profName, skillLine = PD.SKILL_LINES[profName], text = "Learn Apprentice " .. profName }
  spotStep(st, t)
  st.trainer = t
  st.trainerWhere = where
  return st
end

function G:RecipeSteps(profName, r, pos)
  local out = {}
  if r.source == "trainer" then
    -- 0.9.6 phase L: a trainer of your side who teaches this recipe
    local t, where = self:FriendlyNearest(npcIds(r), pos)
    local title = t and ("Learn %s from %s (%s)"):format(r.name, npcWhere(t), money(r.fee)) or G.TRAINER_COPY.recipe:format(r.name, money(r.fee), profName)
    local why = "Your trainer teaches it. Open the trainer window and pick it from the list."
    if not t then why = why .. " " .. G.TRAINER_COPY.guard end
    local st = self:NewStep(profName, "profrecipe", "recipe:" .. r.name, title, why)
    st.goals[1] = { type = "recipe", prof = profName, recipe = r, text = "Learn " .. r.name }
    spotStep(st, t)
    st.trainer = t
    st.trainerWhere = where
    out[1] = st
  elseif r.source == "vendor" or (r.source == "drop" and r.allNpcs and self:FriendlyNearest(r.allNpcs, pos)) then
    -- 0.9.6 phase N: the nearest vendor of your side (a recipe only the other side's vendors sell stays a drop for you); none: a guard
    local v, vwhere = self:FriendlyNearest(npcIds(r), pos)
    local rn = r.recipeName or ("the recipe for " .. r.name)
    local fee = money(r.source == "drop" and r.vendorFee or r.fee)
    if r.recipeItem and PR():Have(r.recipeItem) == 0 then
      local lim = limitedAt(v, r.allNpcs, r.limitedNpcs, r.limited)
      local why = lim and "Right-click it in your bags to learn it. Limited stock: if it is sold out, it comes back after a while." or "Then right-click it in your bags to learn it."
      if not v then why = why .. " " .. G.VENDOR_COPY.guard end
      local st = self:NewStep(profName, "profrecipe", "buyrecipe:" .. r.name,
        v and ("Buy %s from %s (%s)"):format(rn, npcWhere(v), fee) or G.VENDOR_COPY.recipe:format(rn, fee, profName), why)
      st.goals[1] = { type = "recipe", prof = profName, recipe = r, text = "Learn " .. r.name }
      st.goals[2] = haveGoal(r.recipeItem, 1, "all", rn)
      st.goals[2].hint = true
      spotStep(st, v)
      st.vendor, st.vendorWhere = v, v and vwhere or "guard"
      out[1] = st
    else
      local st = self:NewStep(profName, "profrecipe", "userecipe:" .. r.name, ("Right-click %s in your bags to learn it"):format(rn), "One click and it is in your profession window.")
      st.goals[1] = { type = "recipe", prof = profName, recipe = r, text = "Learn " .. r.name }
      out[1] = st
    end
  elseif r.source == "drop" then
    local ah, ahWhere = PD.NearestAuctioneer(pos)   -- 0.9.6 phase P: an auctioneer of your side or a neutral one
    local st = self:NewStep(profName, "profrecipe", "droprecipe:" .. r.name, ("Find the recipe for %s"):format(r.name),
      "It drops from enemies; check the Auction House too." .. (ah and "" or (" " .. PD.AH_COPY.guard)))
    st.goals[1] = { type = "recipe", prof = profName, recipe = r, text = "Learn " .. r.name }
    spotStep(st, ah)
    st.auction, st.auctionWhere = ah, ah and ahWhere or "guard"
    out[1] = st
  end
  return out
end

-------------------------------------------------------------------------------
-- Build the live queue for one profession
-------------------------------------------------------------------------------
function G:BuildFor(profName)
  local P = PR()
  local prof = PD[profName]
  if not (prof and prof.ranks) then return {} end
  local S = Panoply.State
  local pos = S.pos
  local out = {}
  local rank, max = P:CurrentSkill(profName)
  if not rank or (rank == 0 and (max or 0) == 0) then
    out[1] = self:LearnProfessionStep(profName, prof, pos)
    return out, nil
  end
  if rank >= 300 then return out, nil end
  local plan = self:PlanFor(profName)
  -- Training: when you can and you are near the cap, or you are capped.
  local idx, rk = P:RankFor(prof, max)
  if rk and rank >= (rk.minSkill or 0) and (rank >= max - 10 or rank >= max) then
    for _, st in ipairs(self:TrainStep(profName, prof, rk, idx, pos, rank, max)) do out[#out + 1] = st end
    if rank >= max then return out, plan end
  end
  if not plan or not plan.segments[1] then return out, plan end
  local sg
  for _, s in ipairs(plan.segments) do if s.to > rank then sg = s break end end
  if not sg then return out, plan end
  local ctx = plan.ctx
  local nextTo = math.min(sg.to, max)
  -- Tools: bought ones get their own step; crafted ones (Enchanting rods) share the material run.
  local toolIds = (prof.kind == "crafting") and (sg.option.tools or {}) or (prof.tools or {})
  local need, toolCrafts = {}, {}
  self:ToolSteps(out, profName, prof, toolIds, pos, need, toolCrafts)
  if prof.kind == "gathering" then
    local node = sg.option
    local z = bestZone(sg.zones or node.zones, S.level)
    local gt = P.GATHER_TEXT[profName]   -- 0.8.4: Herbalism and Skinning; nil for Mining
    local st
    if gt then
      st = self:NewStep(profName, "profgather", "seg:" .. node.name .. ":" .. sg.to,
        ("%s %s in %s (skill %d->%d)"):format(gt.verb, node.name, z and z.name or gt.where, rank, nextTo),
        ("Follow the arrow round the spawn spots; %s"):format(gt.tip))
    else
      st = self:NewStep(profName, "profgather", "seg:" .. node.name .. ":" .. sg.to,
        ("Mine %s in %s (skill %d->%d)"):format(node.name:gsub("Vein$", "Veins"):gsub("Deposit$", "Deposits"), z and z.name or "the hills", rank, nextTo),
        ("Follow the arrow round the spawn spots; turn on Find Minerals so veins show on your minimap. %s"):format(sg.yields and sg.yields[1] and ("Keep the " .. sg.yields[1] .. "; it smelts into bars.") or ""))
    end
    st.goals[1] = profSkillGoal(profName, nextTo)
    local rg = routeGoal(z, node.name .. " spots", node.name)
    if rg then st.goals[2] = rg; spotStep(st, { map = z.map, x = z.route[1][1], y = z.route[1][2] }) end
    st.gather = true
    st.zoneMap = z and z.map
    out[#out + 1] = st
    return out, plan, sg
  elseif prof.kind == "fishing" then
    local z = sg.zone
    local st = self:NewStep(profName, "proffish", "seg:" .. (z and z.name or "water") .. ":" .. sg.to,
      ("Fish in %s (skill %d->%d)"):format(z and z.name or "any lake or river", rank, nextTo),
      z and z.route and #z.route > 0 and "The arrow points at waters where fish pools spawn." or "Any lake, river or coast there works. Equip your pole and cast.")
    st.goals[1] = profSkillGoal(profName, nextTo)
    local rg = routeGoal(z, "Fishing waters", "fish")
    if rg then st.goals[2] = rg; spotStep(st, { map = z.map, x = z.route[1][1], y = z.route[1][2] }) end
    st.gather = true
    st.zoneMap = z and z.map
    out[#out + 1] = st
    return out, plan, sg
  end
  -- Crafting
  local r = sg.option
  if not P:KnowsRecipe(profName, r) then for _, st in ipairs(self:RecipeSteps(profName, r, pos)) do out[#out + 1] = st end end
  local crafts = math.max(1, math.ceil((P:ExpectedCrafts(profName, r, rank, nextTo) or sg.count) - 0.05))
  for id, n in pairs(r.reagents or {}) do need[id] = (need[id] or 0) + n * crafts end
  self:AddMaterialSteps(out, profName, prof, need, ctx)
  for _, st in ipairs(toolCrafts) do out[#out + 1] = st end
  local made = r.makes and PD.ItemName(r.makes) or r.name
  local verb = r.target and "Cast" or "Make"
  local title = ("%s %d x %s (skill %d->%d)"):format(verb, crafts, r.target and r.name or made, rank, nextTo)
  local where = r.focus and (" at " .. (r.focus == "anvil" and "an anvil" or r.focus == "forge" and "a forge" or "a cooking fire")) or ""
  local why = ("Open your %s window%s and %s %s %d times."):format(profName, where, r.target and "cast" or "craft", r.target and r.name or made, crafts)
  if r.target then why = why .. " Enchant your own " .. r.target:lower() .. " each time (it just replaces the old enchant)." end
  local st = self:NewStep(profName, "profcraft", "seg:" .. r.name .. ":" .. sg.to, title, why)
  Panoply.cdb.profMade = Panoply.cdb.profMade or {}
  local mkKey = r.makes
  local seg = Panoply.cdb.profSegment or {}
  if seg.key ~= st.key then seg = { key = st.key, base = mkKey and Panoply.cdb.profMade[mkKey] or 0, total = crafts }; Panoply.cdb.profSegment = seg end
  st.goals[1] = profSkillGoal(profName, nextTo, mkKey and { key = mkKey, base = seg.base, total = seg.total } or nil)
  st.crafts, st.fromSkill, st.toSkill = seg.total, rank, nextTo
  self:AttachFocus(st, r.focus, pos)
  st.recipe = r
  out[#out + 1] = st
  return out, plan, sg
end

-------------------------------------------------------------------------------
-- Queue, detour and modes
-------------------------------------------------------------------------------
function G:IsNear(step)
  if not step then return false end
  if step.wait then return false end
  local S = Panoply.State
  if not step.mapID then
    -- no place: crafting in your bags (sharpening stones, enchants, bandages) when resting
    return step.kind == "profcraft" and (_G.IsResting and IsResting()) and true or false
  end
  if step.gather then return false end   -- gathering never hijacks levelling; the tracker nudges
  local t = PD.Travel(S.pos, { map = step.mapID, x = step.x, y = step.y })
  return t <= G.NEAR_SECONDS
end

function G:Snooze(step)
  if not step then return end
  self.snoozed[step.key] = now() + G.SNOOZE_SECONDS
  self:Refresh("snooze")
end

function G:Snoozed(step)
  local t = step and self.snoozed[step.key]
  return t and t > now()
end

function G:Build()
  local queue, plan, sg = {}, nil, nil
  local name = self:Tracked()
  if name then
    local ok, q, p, s = pcall(self.BuildFor, self, name)
    if ok then queue, plan, sg = q or {}, p, s else Panoply:Debug("profguide", q) end
  end
  self.tracked, self.plan, self.segment = name, plan, sg
  -- Evaluate goals now so the queue starts at the first unfinished step.
  local live = {}
  for _, st in ipairs(queue) do
    if not Panoply.Goals.StepComplete(st, Panoply.State) then live[#live + 1] = st end
  end
  self.queue = live
  return live
end

-- Live steps for any chosen profession (the Professions tab), without touching the tracked
-- profession's craft counter.
function G:Preview(name)
  if name and name == self.tracked then return self.queue or {}, self.plan end
  if not (Panoply.cdb and name) then return {}, nil end
  local saved = Panoply.cdb.profSegment
  local ok, q, p = pcall(self.BuildFor, self, name)
  Panoply.cdb.profSegment = saved
  if not ok then Panoply:Debug("profguide preview", q) return {}, nil end
  local live = {}
  for _, st in ipairs(q or {}) do if not Panoply.Goals.StepComplete(st, Panoply.State) then live[#live + 1] = st end end
  return live, p
end

function G:First()
  for _, st in ipairs(self.queue) do if not self:Snoozed(st) then return st end end
  return nil
end

-- Rebuild the queue and decide whether the guide should show a profession step.
function G:Refresh(reason)
  if not (Panoply.db and Panoply.cdb) then return end
  self.refreshing = true
  local ok, err = pcall(self.Build, self)
  if not ok then Panoply:Debug("profguide build", err) end
  self.builtAt = now()
  self:Decide(reason)
  self.refreshing = false
end

function G:Decide(reason)
  local before = self.current and self.current.key
  local first = self:First()
  self.current = first
  local mode = self:Mode()
  local E = Panoply.Engine
  local detour
  if mode == "only" then detour = first
  elseif mode == "interleave" then
    if first and (self:IsNear(first) or self.forced == first.key or #E.steps == 0) and not first.wait then detour = first end
    if first and #E.steps == 0 and first.wait then detour = nil end
  end
  if self.forced and not (first and self.forced == first.key) then self.forced = nil end
  E:SetDetour(detour)
  if before and before ~= (first and first.key) and reason ~= "snooze" and reason ~= "track" then Panoply:Fire("PROF_STEP_DONE", before) end
  -- 0.9.5 phase 4A4 (spec 06 section 0.3): Tick decides again every second; PROF_UPDATED then goes out only when something the
  -- tracker, the guide switch, the menu or the partner's tab shows changed. Every other reason (a switch, a skill-up, a snooze) says it.
  if reason == "tick" then
    local ok, sig = pcall(self.UpdateSig, self)
    if not ok then Panoply:Debug("profession signature", sig) sig = nil end
    Panoply:FireChanged("PROF_UPDATED", sig)
  else
    Panoply:FireChanged("PROF_UPDATED", nil)
  end
end

-- Everything PROF_UPDATED's listeners show, as one string (see Engine:UpdateSig): the guide in use, the profession followed, the step in
-- front with its goals, the next steps in the queue, the skills and the bags.
function G:UpdateSig()
  local S, E = Panoply.State, Panoply.Engine
  local out = { tostring(self:Active()), tostring(Panoply.cdb and Panoply.cdb.profTrack), tostring(self.forced), tostring(#self.queue),
                tostring(E and E.detour and E.detour.key), tostring(S.skills), tostring(Panoply.bagRev), tostring(S.level) }
  for i = 1, math.min(#self.queue, 4) do
    local st = self.queue[i]
    out[#out + 1] = "|q" .. tostring(self:Snoozed(st))
    Panoply.Flat(st, out)
    for _, g in ipairs(type(st.goals) == "table" and st.goals or {}) do out[#out + 1] = "|g" Panoply.Flat(g, out) end
  end
  return table.concat(out, ";")
end

-- The "I've done it" button on a profession step.
function G:Confirm(step)
  if not step then return end
  for _, g in ipairs(step.goals or {}) do
    if g.type == "recipe" and g.recipe then PR():MarkRecipeKnown(step.prof, g.recipe.name) end
    g.confirmed = true
  end
  if not Panoply.Goals.StepComplete(step, Panoply.State) then self.snoozed[step.key] = now() + G.SNOOZE_SECONDS end
  self:Refresh("confirm")
end

function G:Tick()
  if not (Panoply.db and Panoply.cdb) then return end
  if not self.builtAt or now() - self.builtAt >= 10 then self:Refresh("tick") else self:Decide("tick") end
end

-- "Go" on the tracker: show this profession step in the guide now.
function G:Force()
  local first = self:First()
  if first then self.forced = first.key end
  Panoply.Engine:SetDetour(first)
end

local pending = false
function G:Schedule(reason)
  if pending then return end
  pending = true
  C.After(0.4, function() pending = false; G:Refresh(reason) end)
end

-- Mail: count items attached to open inbox letters (the mailbox only tells us while it is open).
function G:ScanMail()
  if not (_G.GetInboxNumItems and _G.GetInboxItem) then return end
  local items = {}
  local n = GetInboxNumItems() or 0
  for i = 1, n do
    for a = 1, (_G.ATTACHMENTS_MAX_RECEIVE or 12) do
      local ok, name, itemID, _, count = pcall(GetInboxItem, i, a)
      if ok and name then
        local id = itemID or PD.ItemID(name)
        if type(id) == "number" then items[id] = (items[id] or 0) + (count or 1) end
      end
    end
  end
  Panoply.cdb.mailItems = items
end

-- "You create: [Rough Sharpening Stone]x5." -> counters for the craft step.
function G:OnLoot(msg)
  if type(msg) ~= "string" or not msg:find("You create") then return end
  local id = tonumber(msg:match("item:(%d+)"))
  local name = msg:match("%[(.-)%]")
  if not id and name then id = PD.ItemID(name) end
  if not id then return end
  local n = tonumber(msg:match("x(%d+)") or "1") or 1
  Panoply.cdb.profMade = Panoply.cdb.profMade or {}
  Panoply.cdb.profMade[id] = (Panoply.cdb.profMade[id] or 0) + n
end

function G:Register()
  local function sched(r) return function() if Panoply.db then G:Schedule(r) end end end
  for _, ev in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_OPENED", "TRAINER_UPDATE", "TRAINER_CLOSED",
    "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SKILL" }) do
    Panoply:On(ev, sched(ev))
  end
  Panoply:On("SKILL_LINES_CHANGED", function() if Panoply.db then Panoply.State:RefreshSkills(); G:Schedule("skill") end end)
  Panoply:On("MAIL_INBOX_UPDATE", function() if Panoply.db then pcall(G.ScanMail, G); G:Schedule("mail") end end)
  Panoply:On("MAIL_CLOSED", sched("mail"))
  Panoply:On("CHAT_MSG_LOOT", function(_, msg) if Panoply.db then G:OnLoot(msg); G:Schedule("loot") end end)
  Panoply:On("CHAT_MSG_SYSTEM", function(_, msg)
    if Panoply.db and PR():LearnedFromText(msg) then G:Schedule("learned") end
  end)
  Panoply:Listen("PROF_KNOWLEDGE", function() G:Schedule("window") end)
  Panoply:Listen("PLAN_FINISHED", function() G:Schedule("plan") end)
  Panoply:Listen("STEPS_CHANGED", function() if Panoply.db and not G.refreshing then G:Schedule("steps") end end)
end

Panoply.optionHooks.profGuide = function()
  -- the Settings / slash "profession steps" choice is the same switch as the guide window's
  if Panoply.cdb then Panoply.cdb.activeGuide = G.MODE_TO_GUIDE[Panoply.db.profGuide] or "both" end
  G:Refresh("mode")
  if G:Active() ~= "professions" and Panoply.Engine then Panoply.Engine:Check() end
end
-- 0.9.5 (phase 4B): the global choice set any way (settings, slash, a profile) sets every profession's own plan too
Panoply.optionHooks.profStrategy = function(v) if Panoply.ProfPlans then Panoply.ProfPlans:ApplyStrategyToAll(v) end G:Invalidate(); G:Refresh("strategy") end
