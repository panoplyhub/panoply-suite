-- Panoply Suite Planner: "jump in at any level" route generator (own algorithm, SPEC section 8).
-- Reads quests/NPCs from Panoply Suite Quest Data at runtime (Panoply.QuestData) and builds a greedy,
-- travel-aware plan: accept nearby quests, do objectives in nearest order, turn in, repeat,
-- simulating XP/levels, until the horizon (current level + N) is reached.
local ADDON, Panoply = ...
local P = {}
Panoply.Planner = P
local QD, Nav, U, C = Panoply.QuestData, Panoply.Nav, Panoply.Util, Panoply.Compat

P.WORK_SECONDS = { kill = 26, item = 26, object = 18, event = 30 }
P.DEFAULT_COUNT = { kill = 8, item = 6, object = 5, event = 1 }  -- only when the record has no count
-- 0.7 route fix (ROUTE-FIX-PLAN.md): level band, mob guard, zone stickiness, real counts and drops.
P.MAX_ABOVE = 2              -- quests up to yellow (your level + 2); hardcore: + 1
P.MOB_ABOVE = 2              -- never send you to fight mobs more than 2 levels above you
P.ACCEPT_MOB_ABOVE = 3       -- pick a quest up when its mobs are at most 3 above (done once you level)
P.DEFAULT_DROP = 35          -- percent, for a quest item without a known drop chance
P.MAX_KILLS_PER_ITEM = 8
P.ZONE_LEAVE_PENALTY = 900   -- scoring: leaving a zone that still has work for you
P.NEAR_SECONDS = 150          -- 0.7: "work close by" (about 1000 yd on foot)
P.FAR_SECONDS = 200           -- 0.7: a trip this long inside the zone counts as going to another area
P.FAR_PENALTY = 300           -- 0.7: scoring: going to another area of the zone while work is close by
P.DO_WORK_SHARE = 0.1         -- 0.7 (0.7.2: 0.25 -> 0.1, sim): scoring counts only this share of the fighting time (it is not travel)
P.LEVEL_AHEAD_PENALTY = 120  -- scoring: seconds per quest level above yours (easier quests first)
P.NOT_OFFERED_LEVELS = 2     -- a quest the game did not offer is skipped for this many levels
P.DRIFT_LEVELS = 2           -- re-plan when you are this many levels off the plan
P.GRIND_FOR_QUESTS = 2       -- grind a level in place when that opens this many quests here
P.MAX_LOCAL_GRIND = 2400     -- ... and takes at most this long (or less than leaving and coming back); 0.7.2: 1200 -> 2400 (routesim, see ZONE_HOP_SECONDS)
P.MAX_GRIND_STEPS = 10       -- per plan (0.7.2: 3 -> 10, see ZONE_HOP_SECONDS)
P.MOVED_SECONDS = 300        -- re-plan when you are this much further from the next step than expected
P.WEIGHT = { turnin = 1.6, accept = 1.25, ["do"] = 1.0 }
P.MAX_QUEST_SECONDS = 2700  -- 0.7: real kill counts and drop chances make quests look longer than the old guesses
P.ZONE_SWITCH_PENALTY = 420  -- scoring only: prefer finishing a zone before hopping to the next
P.MIN_RATE_VS_GRIND = 0.2    -- skip quests worth less than 20% of grinding XP/s (incl. travel)
P.MIN_RATE_HI = nil          -- planner-final: from level MIN_RATE_FROM the bar is this instead (nil = the same bar at every level)
P.MIN_RATE_FROM = 30
function P.MinRate(level) if P.MIN_RATE_HI and level >= P.MIN_RATE_FROM then return P.MIN_RATE_HI end return P.MIN_RATE_VS_GRIND end
P.CLUSTER_RADIUS = 0.05      -- map units for hotspot detection
-- 0.7.2 speed (SPEC 8, CALIBRATION.md): hand-ins wait while there is work close by, the hearthstone
-- takes you home to the hub, and the route sets your hearthstone at the inn of each new questing hub.
-- 0.7.2 zone batching ("go to a zone, do every green and yellow quest there, then a nearby zone of the
-- same levels, then back"): while the zone you are in still has work, only work here (or within NEAR_SECONDS)
-- is planned; hand-ins and quests elsewhere wait for the next visit there. When the zone is down to orange,
-- the next zone is the one with the most work per second of travel (its hand-ins included).
P.LA_STEP_GRIND = 0          -- exp/lookahead: grind one level at a time when nothing is available (1 = on)
P.ZONE_BATCH = 1              -- shipped: our zone rule (won the routesim A/B); 0 off, 2 XP-weighted variant
P.BATCH_NEAR = 150            -- s: work in another zone this close counts as "here" (a hub just over the zone line)
-- a capital and the zone around it count as one place for batching (the capital is the zone's town)
P.ZONE_GROUP = { [1453] = 1429, [1455] = 1426, [1457] = 1438, [1454] = 1411, [1456] = 1412, [1458] = 1420 }
P.MIN_BATCH = 3               -- a zone visit should have at least this many things to do
P.ZONE_HOP_SECONDS = 600      -- scoring only: the fixed cost of a zone change (finding your feet, the zone line)
-- 0.7.2 ("i hate travelling"): 90 -> 600, with MAX_GRIND_STEPS 3 -> 10 and MAX_LOCAL_GRIND 1200 -> 2400 the
-- route stays in a zone and fights a little for its next quests instead of hopping away and back. routesim:
-- 1-20 same time (16.3 h Era / 16.6 h Forever) with 12.3 / 12.8 quests per zone visit (was 10.2 / 11.2);
-- Alliance 20-40 71.2 -> 69.1 h, zone changes 79 -> 55, one-quest visits 22 -> 6 (tests/routesim/AB-RESULTS-0.7.2.md).
P.BATCH_CAP = 6               -- work counted per visit when comparing zones
P.SMALL_BATCH_FACTOR = 3      -- scoring only: a zone with fewer than MIN_BATCH things costs this much more
P.TURNIN_DEFER = 1.0         -- scoring: a hand-in further than "close by" costs this share more while work is near
P.HEARTH_SECONDS = 30        -- cast + loading screen
P.HEARTH_CD = 3600
P.HEARTH_GAIN = 60           -- use the hearthstone only when it saves at least this much
P.BIND_NEAR = 60             -- s: an inn this close to where you take or hand in quests is "the hub's inn"
P.BIND_FAR = 240             -- s: ... and binding there is worth it when your current inn is further than this
P.BIND_MIN_QUESTS = 3        -- quests still to take or hand in around that hub
P.FP_NEAR = 90               -- s: learn a flight path whose flight master is this close to a hub you visit
-- After 0.8.4 (Boneless, an Undead leaving Deathknell): what lies on the way is done on the way.
P.PATH_PICKUP = 30           -- s: a quest giver this little off the way to the next stop is visited first (Calvin Montague and
                             --    Deathguard Simmer stand on the road out of Deathknell; the route walked past both)
P.PATH_DETOUR = 30           -- s: a thing to gather this little off the way to its hand-in counts as "on the way"
P.PATH_MIN_NODES = 2         -- ... and there must be this many of them on the way per one needed (not every one is up), at least 3
-- Negative zoneOrSort values are quest categories. Only class categories are routed; holidays,
-- professions and other special categories are skipped.
P.ALLOWED_SORTS = { [-61] = true, [-81] = true, [-82] = true, [-141] = true, [-161] = true,
                    [-162] = true, [-261] = true, [-262] = true, [-263] = true }

-------------------------------------------------------------------------------
-- XP helpers
-------------------------------------------------------------------------------
function P.QuestXP(q, level)
  local base = q.xp
  if not base or base <= 0 then base = 40 + 18 * q.level + 4 * q.level * q.level end
  local diff = level - q.level
  local f = 1
  if diff >= 10 then f = 0.1 elseif diff >= 6 then f = 1 - (diff - 5) * 0.2 end
  return math.floor(base * f)
end

function P.MobXP(level) return 45 + 5 * level end

-- XP for one kill of a mob of level ml at player level pl (the classic rules: +5% per level above,
-- less for lower mobs, nothing for grey ones; elites give double).
local function zeroDiff(pl)
  if pl <= 7 then return 5 elseif pl <= 9 then return 6 elseif pl <= 11 then return 7 elseif pl <= 15 then return 8
  elseif pl <= 19 then return 9 elseif pl <= 29 then return 11 elseif pl <= 39 then return 12 elseif pl <= 44 then return 13
  elseif pl <= 49 then return 14 elseif pl <= 54 then return 15 elseif pl <= 59 then return 16 end
  return 17
end
local function greyLevel(pl)
  if pl <= 5 then return 0 elseif pl <= 39 then return pl - 5 - math.floor(pl / 10) elseif pl <= 59 then return pl - 1 - math.floor(pl / 5) end
  return pl - 9
end
function P.MobXPAt(pl, ml, elite)
  if not ml or ml <= 0 then ml = pl end
  local base = 45 + 5 * pl
  local xp
  if ml >= pl then xp = base * (1 + 0.05 * math.min(ml - pl, 4))
  elseif ml <= greyLevel(pl) then xp = 0
  else xp = base * (1 - (pl - ml) / zeroDiff(pl)) end
  if elite then xp = xp * 2 end
  return math.floor(xp)
end

function P.XPToLevel(level)
  return (Panoply.XPTable and Panoply.XPTable[level]) or (level * 1000)
end

local function addXP(sim, amount)
  sim.xp = sim.xp + amount
  while sim.level < (Panoply.MAX_LEVEL or 60) and sim.xp >= P.XPToLevel(sim.level) do
    sim.xp = sim.xp - P.XPToLevel(sim.level)
    sim.level = sim.level + 1
  end
end

-------------------------------------------------------------------------------
-- Geometry helpers
-------------------------------------------------------------------------------
-- Densest cluster of spots, preferring the reference map. Returns {map,x,y,n}.
function P.Hotspot(spots, ref)
  if not spots or #spots == 0 then return nil end
  local byMap, bestMap, bestN = {}, nil, 0
  for _, s in ipairs(spots) do
    local l = byMap[s.map]
    if not l then l = {}; byMap[s.map] = l end
    l[#l + 1] = s
    if #l > bestN then bestN, bestMap = #l, s.map end
  end
  -- 0.7: the quest giver's zone wins whenever it has a few spots (a common drop is everywhere; the
  -- densest zone was often a far one: Stocking Jetsteam sent Dun Morogh to another zone's bears)
  if ref and byMap[ref.map] and (#byMap[ref.map] >= 3 or #byMap[ref.map] * 3 >= bestN) then bestMap = ref.map end
  local list = byMap[bestMap]
  local sample = list
  if #list > 60 then
    sample = {}
    local step = #list / 60
    for i = 0, 59 do sample[#sample + 1] = list[math.floor(i * step) + 1] end
  end
  local r2 = P.CLUSTER_RADIUS * P.CLUSTER_RADIUS
  local best, bestCount = sample[1], -1
  for _, a in ipairs(sample) do
    local n = 0
    for _, b in ipairs(sample) do
      local dx, dy = a.x - b.x, a.y - b.y
      if dx * dx + dy * dy <= r2 then n = n + 1 end
    end
    if n > bestCount then best, bestCount = a, n end
  end
  local sx, sy, n = 0, 0, 0
  for _, b in ipairs(sample) do
    local dx, dy = best.x - b.x, best.y - b.y
    if dx * dx + dy * dy <= r2 then sx, sy, n = sx + b.x, sy + b.y, n + 1 end
  end
  return { map = bestMap, x = sx / n, y = sy / n, n = #list }
end

-- 0.7: travel time a -> b. Inside one zone: the straight walk. Between zones: the router (roads
-- through zone lines, known flights, boats, the tram, see Engine/Route.lua), cached on a coarse grid
-- for the length of one plan. The old straight line across zones sent Coldridge Valley dwarves to
-- Goldshire "7 minutes away" over the mountains.
P.travelCache, P.travelCacheN = {}, 0
P.STRAIGHT_TRAVEL = false

-- 0.7.2 (M2): automatic re-plans run time-sliced, a little every frame. P.Tick() yields the plan's
-- coroutine once the slice ran YIELD_MS; SLICE_MS is the cap the tests check. Never called inside
-- a pcall (Lua 5.1 cannot yield across it).
P.SLICE_MS = 5
P.YIELD_MS = 2
local pclock = _G.debugprofilestop or function() return os.clock() * 1000 end
P.clock = pclock
P.slice = nil
function P.Tick()
  local sl = P.slice
  if sl and coroutine.running() == sl.co and pclock() - sl.start >= P.YIELD_MS then
    coroutine.yield()
  end
end
local function cell(v) return math.floor((v or 0) * 25) end
function P.Travel(a, b)
  if not a or not b then return Nav.CROSS_ZONE_SECONDS end
  if not a.map or not b.map or a.map == b.map then return Nav.TravelSeconds(a, b) end
  local Route = Panoply.Route
  if P.STRAIGHT_TRAVEL or not (Route and Route.FindNow) then return Nav.TravelSeconds(a, b) end
  local k = a.map * 4096 * 4096 + cell(a.x) * 4096 * 64 + cell(a.y) * 4096 + b.map * 0.0001 + cell(b.x) * 64 + cell(b.y)
  local ck = tostring(k)
  local t = P.travelCache[ck]
  if t then return t end
  -- 0.7.2: the plan models the hearthstone itself (its cooldown), so plan trips never count on it
  local okR, r
  Route.noHearth = true
  if P.slice and coroutine.running() == P.slice.co then
    -- time-sliced plan (M2): the route search runs in its own slices and the plan yields between them
    local okJ, job = pcall(Route.NewJob, Route, { map = a.map, x = a.x, y = a.y }, { map = b.map, x = b.x, y = b.y })
    Route.noHearth = nil
    if okJ and job then
      while not Route:Resume(job) do P.Tick() end
      okR, r = true, job.result
    end
  else
    okR, r = pcall(Route.FindNow, Route, { map = a.map, x = a.x, y = a.y }, { map = b.map, x = b.x, y = b.y })
    Route.noHearth = nil
  end
  t = okR and r and r.total
  if not t or t ~= t or t == math.huge then t = Nav.TravelSeconds(a, b) * 1.5 end
  P.travelCacheN = P.travelCacheN + 1
  if P.travelCacheN > 20000 then P.travelCache, P.travelCacheN = {}, 0 end
  P.travelCache[ck] = t
  return t
end

local function nearest(spots, pos)
  if not spots or #spots == 0 then return nil, math.huge end
  if not pos then return spots[1], Nav.CROSS_ZONE_SECONDS end
  local best, bestT = nil, math.huge
  -- same-zone spots first (cheap); other zones only when none is in this zone
  for _, s in ipairs(spots) do
    if s.map == pos.map then
      local t = Nav.TravelSeconds(pos, s)
      if t < bestT then best, bestT = s, t end
    end
  end
  if best then return best, bestT end
  local seen = {}
  for _, s in ipairs(spots) do
    local k = (s.map or 0) .. ":" .. cell(s.x) .. ":" .. cell(s.y)
    if not seen[k] then
      seen[k] = true
      local t = P.Travel(pos, s)
      if t < bestT then best, bestT = s, t end
    end
  end
  return best, bestT
end
P.Nearest = nearest

-------------------------------------------------------------------------------
-- Player state input
-------------------------------------------------------------------------------
function P:StateFromGame()
  local S = Panoply.State
  S:RefreshPlayer()
  local info = C.PlayerInfo()
  local log = {}
  for id, q in pairs(S.log) do
    log[id] = { ready = q.isComplete and true or false, title = q.title, group = q.suggestedGroup or 0, tag = C.QuestTag(id) }
  end
  return {
    level = S.level or 1, xp = S.xp or 0,
    raceID = info.raceID, classID = info.classID, classFile = info.classFile,
    completed = S.completed, log = log, pos = S.pos,
    logSize = (Panoply.db and Panoply.db.plannerLogSize) or 20,
    horizon = (Panoply.db and Panoply.db.plannerHorizon) or 3,
    hardcore = C.IsHardcore(),
    partnerLevel = Panoply.Sync and Panoply.Sync:PartnerLevel() or nil,
    groupQuests = Panoply.Difficulty.GroupQuests(), -- 0.9.7: the Group quests setting (Difficulty.lua) replaces the levelling style
    notOffered = Panoply.cdb and Panoply.cdb.notOffered or nil,
    startItem = self:StartItemsInBags(),
  }
end

-- 0.7.2 (M1b): quests started by an item you carry: { [questID] = itemID }. The table of which
-- items start which quests is built once from the quest data.
function P:StartItemsInBags()
  if not QD:Available() then return nil end
  if not self.startItems then
    local map = {}
    for _, id in ipairs(QD:AllQuestIds()) do
      P.Tick()
      local okQ, q = pcall(QD.GetQuest, QD, id)
      if okQ and q and q.starts and q.starts.item then
        for _, it in ipairs(q.starts.item) do map[#map + 1] = { q = id, item = it } end
      end
    end
    self.startItems = map
  end
  local out, any = {}, false
  for _, e in ipairs(self.startItems) do
    if (C.ItemCount(e.item) or 0) > 0 then out[e.q] = e.item; any = true end
  end
  return any and out or nil
end

-------------------------------------------------------------------------------
-- Candidate quests (static filters, done once per plan)
-------------------------------------------------------------------------------
local function simEffLevelFwd(sim) return sim.level - (sim.lag or 0) end

local function questInfo(q, S, inLog)
  local info = { q = q, inLog = inLog }
  info.givers = inLog and {} or QD:GiverSpots(q)
  -- 0.7.2 (M1b): an item that starts a quest is "accepted" where you stand, once it is in your bags
  if not inLog and #info.givers == 0 and S.startItem and S.startItem[q.id] and S.pos then
    info.fromItem = S.startItem[q.id]
    info.givers = { { map = S.pos.map, x = S.pos.x, y = S.pos.y, item = info.fromItem } }
  end
  -- 0.7.2 (M1b): never route a hand-in to an NPC of the other side
  info.finishers = {}
  for _, f in ipairs(QD:FinisherSpots(q)) do
    if not (f.npc and QD:NpcFriendly(f.npc) == false) then info.finishers[#info.finishers + 1] = f end
  end
  info.areas = {}
  info.work = 0
  -- 0.5.8 difficulty guard inputs: the quest's level (the game's own when it is in the log and
  -- higher) and whether it is elite / group content
  local Dif = Panoply.Difficulty
  info.level = Dif and Dif.QuestLevel(q.id, q) or q.level
  info.group = Dif and Dif.IsGroup(q.id, q) or false
  local counts = P.ObjectiveCounts(q)
  info.kills, info.mobLevel = {}, 0
  -- After 0.8.4: an item the quest needs in your bags before its objective can be done (Data/Fixes.lua `need`: Samuel's Remains
  -- before Marla's Grave) is fetched first: its place goes in front of the objective areas and routeAreas keeps it there.
  for _, nd in ipairs(QD:QuestNeeds(q)) do
    local spot = P.Hotspot(nd.spots, info.givers[1] or S.pos)
    if spot and (C.ItemCount(nd.item) or 0) < nd.count then
      info.areas[#info.areas + 1] = { kind = "item", id = nd.item, spot = spot, count = nd.count, first = true }
      info.work = info.work + nd.count * P.WORK_SECONDS.kill
    end
  end
  info.handedWork = 0
  for i, a in ipairs(QD:ObjectiveAreas(q)) do
    local spot = P.Hotspot(a.spots, info.givers[1] or S.pos)
    local c = counts[i] or {}
    local count = c.count or P.DEFAULT_COUNT[a.kind] or 1
    local per = P.WORK_SECONDS[a.kind] or 20
    local n, ml, elite = P.KillsFor(a, c, count)
    local before = info.work
    if n > 0 then
      info.kills[#info.kills + 1] = { n = n, ml = ml, elite = elite }
      if ml and ml > info.mobLevel then info.mobLevel = ml end
      info.work = info.work + n * P.WORK_SECONDS.kill * (elite and 3 or 1)
    else
      info.work = info.work + count * per
    end
    local area = { kind = a.kind, id = a.id, spot = spot, count = count }
    -- things picked up off the ground or out of objects (never dropped by creatures): each place gives one, so the ones that lie
    -- on the way to the hand-in can be taken on the way (P.AlongWay)
    if spot and n == 0 and (a.kind == "object" or a.kind == "item") then area.gather, area.raw = true, a.spots end
    info.areas[#info.areas + 1] = area
    if not spot then
      info.work = info.work + 120  -- unknown location penalty
      -- 0.7.2 (M1b): an objective with no known place (not an item the quest hands you)
      local given = a.kind == "item" and (a.id == q.sourceItem or (function()
        local npcs, objs = QD:ItemDroppers(a.id)
        return #(npcs or {}) == 0 and #(objs or {}) == 0 end)())
      if not given then info.noPlace = true end
    end
    -- After 0.8.4: an item the quest itself hands you (a letter to deliver) is in your bags when you accept: the work counted for
    -- it above is not real. The plan's own sums keep it (so no route changes by it), but a giver you walk past is judged without it
    -- (the pickups on the way in P:Generate): that is what left Calvin Montague's letter (quest 8) out on the road past him.
    if a.kind == "item" and a.id == q.sourceItem and not spot then info.handedWork = info.handedWork + (info.work - before) end
  end
  return info
end

-- Objective counts in the order QD:ObjectiveAreas lists them: { {count=, npcs={...}}, ... }.
function P.ObjectiveCounts(q)
  local out, o = {}, q.objectives or {}
  local function n(v) return type(v) == "number" and v > 0 and v or nil end
  for _, c in ipairs(o.creatures or {}) do out[#out + 1] = { count = n(c[2]) or 1, npcs = { c[1] } } end
  for _, kc in ipairs(o.killCredit or {}) do out[#out + 1] = { count = n(kc[4]) or 1, npcs = type(kc[1]) == "table" and kc[1] or { kc[1] } } end
  for _, ob in ipairs(o.objects or {}) do out[#out + 1] = { count = n(ob[2]) or 1 } end
  for _, it in ipairs(o.items or {}) do out[#out + 1] = { count = n(it[2]) or 1, item = it[1] } end
  return out
end

-- Kills an objective takes: n kills of mobs at level ml (the lowest-level mob that counts or drops).
function P.KillsFor(a, c, count)
  local npcs, n = nil, 0
  if a.kind == "kill" then npcs, n = c.npcs, count
  elseif a.kind == "item" and c.item then
    local droppers = QD:ItemDroppers(c.item)
    if droppers and #droppers > 0 then
      npcs = droppers
      local F = QD:Fixes()
      local pct = (F and F.drop and F.drop[c.item]) or P.DEFAULT_DROP
      n = math.min(count * P.MAX_KILLS_PER_ITEM, math.ceil(count * 100 / math.max(1, pct)))
    end
  end
  if not npcs or n == 0 then return 0 end
  local ml, elite
  for i, id in ipairs(npcs) do
    if i > 40 then break end
    local lo = QD:NpcLevel(id)
    if lo and lo > 0 and (not ml or lo < ml) then ml, elite = lo, QD:NpcElite(id) end
  end
  return n, ml, elite
end

function P.KillXP(info, level)
  local xp = 0
  for _, k in ipairs(info.kills or {}) do xp = xp + k.n * P.MobXPAt(level, k.ml, k.elite) end
  return xp
end

-- Mobs a quest sends you to are at most MOB_ABOVE levels above you (above= override for picking up).
-- 0.7.3: the levelling style can lower both (Safe: never above your level).
function P.MobsOK(info, sim, above)
  local ml = info.mobLevel or 0
  return ml <= simEffLevelFwd(sim) + (above or sim.mobAbove or P.MOB_ABOVE)
end

-- The rules a planning state plays by (0.9.7: one set, moved only by the Group quests setting; see Difficulty.lua D.Rules).
-- One place, so every filter below reads the same four numbers/flags: maxAbove, mobAbove, elite, dungeons.
function P.Rules(S)
  return Panoply.Difficulty.Rules()
end

-- a couple levelling together may skip dungeons: unless Group quests is "Always include them", leave out quests
-- that happen inside instances, raid-flagged quests, quests whose targets are elites/bosses,
-- and pure lead-in quests (talk/deliver, breadcrumbs) whose follow-ups are all left out.
-- Ultimate (2026-11-02) still leaves out raid quests and the lead-ins that only lead into them.
-- Quests that follow a left-out quest can never become available, so whole chains stop there.
P.LOG_TAG_EXCLUDE = { dungeon = true, raid = true, group = true, elite = true }

function P:GroupExclusions(S, quests)
  local ex, stats = {}, { dungeon = 0, raid = 0, elite = 0, leadIn = 0, log = 0, total = 0 }
  self.skippedLog = {}
  self.filterStats = stats
  local R = P.Rules(S)
  local succ = {}
  local function link(from, to) if from and to and from ~= 0 then succ[from] = succ[from] or {}; succ[from][#succ[from] + 1] = to end end
  for id, q in pairs(quests) do
    P.Tick()
    for _, p in ipairs(q.preSingle or {}) do link(p, id) end
    for _, p in ipairs(q.preGroup or {}) do link(p, id) end
    if q.nextInChain ~= 0 then link(id, q.nextInChain) end
    if q.breadcrumbFor ~= 0 then link(id, q.breadcrumbFor) end
  end
  for id, q in pairs(quests) do
    P.Tick()
    local okW, why = pcall(QD.GroupContentReason, QD, q)
    if not okW then P.SkipQuest(id, "group check", why); why = nil end
    local e = S.log[id]
    if not why and e then
      if e.tag and P.LOG_TAG_EXCLUDE[e.tag] then why = e.tag == "group" and "elite" or e.tag
      elseif (e.group or 0) > 1 then why = "elite" end
    end
    -- Group quests "Always include them": elite, group and dungeon quests stay; raid quests never do
    if why == "elite" and R.elite then why = nil end
    if R.dungeons and why ~= "raid" then why = nil end
    if why then ex[id] = why; stats[why] = (stats[why] or 0) + 1 end
  end
  -- lead-ins that only lead into left-out quests (repeat for chains of lead-ins)
  for _ = 1, 6 do
    local changed = false
    for id, q in pairs(quests) do
      P.Tick()
      local okL, lead = pcall(QD.IsLeadIn, QD, q)
      if not ex[id] and succ[id] and okL and lead then
        local all = true
        for _, n in ipairs(succ[id]) do if not ex[n] then all = false break end end
        if all then ex[id] = "leadIn"; stats.leadIn = stats.leadIn + 1; changed = true end
      end
    end
    if not changed then break end
  end
  for id, why in pairs(ex) do
    stats.total = stats.total + 1
    if S.log[id] then
      stats.log = stats.log + 1
      self.skippedLog[#self.skippedLog + 1] = { questID = id, title = (quests[id] and quests[id].name) or S.log[id].title, why = why }
    end
  end
  table.sort(self.skippedLog, function(a, b) return tostring(a.title) < tostring(b.title) end)
  return ex, stats
end

-- In-log quests that the database doesn't know but the game tags as dungeon/group content.
local function logOnlyExclusion(S, id)
  local e = S.log[id]
  local R = P.Rules(S)
  if not e then return nil end
  local why
  if e.tag and P.LOG_TAG_EXCLUDE[e.tag] then why = e.tag == "group" and "elite" or e.tag
  elseif (e.group or 0) > 1 then why = "elite" end
  if why == "elite" and R.elite then return nil end
  if R.dungeons and why ~= "raid" then return nil end   -- "Always include them": only raid quests stay out
  return why
end

function P:Candidates(S, goalLevel)
  local list = {}
  local raceMask = QD:RaceMask(S.raceID)
  local classMask = QD:ClassMask(S.classID, S.classFile)
  local maxLevel = Panoply.Difficulty.MaxQuestLevel(P.Rules(S), goalLevel or (S.level + (S.horizon or 3)))   -- +2 (yellow at worst)
  local green = C.TrivialRange(S.level)
  local hidden = QD.hidden or {}
  local all = {}
  for _, id in ipairs(QD:AllQuestIds()) do
    P.Tick()
    local q = QD:GetQuest(id)
    if q then all[id] = q end
  end
  local excluded = self:GroupExclusions(S, all)
  local function consider(id)
    local inLog = S.log[id] ~= nil
    local q = (inLog or not S.completed[id]) and all[id] or nil
    local ok = q ~= nil and not excluded[id]
    if ok and not inLog then
      if hidden[id] then ok = false
      elseif q.races ~= 0 and raceMask and not U.HasBitValue(q.races, raceMask) then ok = false
      elseif QD:ForeignStart(q.zone, S.raceID) then ok = false      -- 0.7.4.1: another race's starting valley
      elseif q.classes ~= 0 and classMask and not U.HasBitValue(q.classes, classMask) then ok = false
      elseif q.specialFlags % 2 == 1 then ok = false                 -- repeatable
      elseif q.reqSkill or q.reqSpell ~= 0 or q.reqMinRep then ok = false
      elseif q.parentQuest ~= 0 then ok = false
      elseif q.zone < 0 and not P.ALLOWED_SORTS[q.zone] then ok = false
      elseif q.reqLevel > maxLevel or q.level > maxLevel + 1 then ok = false
      elseif q.level < S.level - green - 1 then ok = false
      elseif #q.starts.npc == 0 and #q.starts.obj == 0 and not (S.startItem and S.startItem[id]) then ok = false -- item-started: only once the item is in your bags
      else
        for _, npc in ipairs(q.starts.npc) do if QD:NpcFriendly(npc) == false then ok = false end end
      end
    end
    if ok then
      local info = questInfo(q, S, inLog)
      if info.noPlace and not inLog then
        -- 0.7.2 (M1b): we could not tell you where to go: leave it out
      elseif (inLog or #info.givers > 0) and #info.finishers > 0 then
        list[#list + 1] = info
      elseif inLog then
        info.noFinisher = true
        list[#list + 1] = info
      end
    end
  end
  for _, id in ipairs(QD:AllQuestIds()) do
    P.Tick()
    local okC, err = pcall(consider, id)
    if not okC then P.SkipQuest(id, "candidate", err); all[id] = nil end
  end
  -- log quests unknown to the database but tagged as group content by the game
  for id, e in pairs(S.log) do
    if not all[id] then
      local why = logOnlyExclusion(S, id)
      if why then self.skippedLog[#self.skippedLog + 1] = { questID = id, title = e.title, why = why } end
    end
  end
  return list
end

-------------------------------------------------------------------------------
-- Dynamic availability during simulation
-------------------------------------------------------------------------------
local function isDone(sim, id) return sim.baseDone[id] or sim.done[id] end

-- 0.5.8: the level the difficulty rules use during the simulation (the lower partner's level
-- when partnered: the gap between you is assumed to stay the same).
local function simEffLevel(sim) return sim.level - (sim.lag or 0) end
P.SimEffLevel = simEffLevel

-- Never route a red quest, never an elite above level + 2 (whatever the settings say).
function P.TooHard(info, sim)
  local Dif = Panoply.Difficulty
  if not Dif then return nil end
  return Dif.Blocked(info.level or info.q.level, simEffLevel(sim), info.group)
end

-- A quest gate from Data/Fixes.lua (VMaNGOS RequiredCondition) against the simulated state.
function P.EvalGate(g, sim, depth)
  depth = (depth or 0) + 1
  if type(g) ~= "table" or depth > 10 then return true end
  local k = g[1]
  if k == "and" then for i = 2, #g do if not P.EvalGate(g[i], sim, depth) then return false end end return true
  elseif k == "or" then for i = 2, #g do if P.EvalGate(g[i], sim, depth) then return true end end return false
  elseif k == "not" then return not P.EvalGate(g[2], sim, depth)
  elseif k == "done" then return isDone(sim, g[2]) and true or false
  elseif k == "taken" then return sim.log[g[2]] ~= nil
  elseif k == "ready" then return (sim.log[g[2]] and sim.log[g[2]].ready) and true or false
  elseif k == "none" then return not isDone(sim, g[2]) and not sim.log[g[2]]
  elseif k == "yes" then return true end
  return false -- aura, skill, ...: not modelled, never routed
end

P.notOffered = {}  -- questID -> level when the quest giver did not offer it (learned in game)
function P:NoteNotOffered(id, level)
  if not id then return end
  P.notOffered[id] = level or 1
  if Panoply.cdb then Panoply.cdb.notOffered = Panoply.cdb.notOffered or {}; Panoply.cdb.notOffered[id] = level or 1 end
end

function P.Available(info, sim)
  local q = info.q
  local id = q.id
  if isDone(sim, id) or sim.log[id] then return false end
  local lvl = sim.reqLevelFloor or sim.level
  if q.reqLevel > math.min(lvl, sim.level) then return false end
  local above = sim.maxAbove or P.MAX_ABOVE
  if sim.ownLevelUntil and sim.level <= sim.ownLevelUntil then above = math.max(above, 0) end
  if sim.hardcore then above = math.min(above, 1) end
  if q.level > sim.level + above then return false end
  if not P.MobsOK(info, sim, sim.acceptMobAbove or P.ACCEPT_MOB_ABOVE) then return false end
  local no = P.notOffered[id]
  if no and sim.level < no + P.NOT_OFFERED_LEVELS then return false end
  local F = QD:Fixes()
  if F then
    if F.pre and F.pre[id] then for _, p in ipairs(F.pre[id]) do if not isDone(sim, p) then return false end end end
    if F.cond and F.cond[id] and not P.EvalGate(F.cond[id], sim) then return false end
  end
  if q.reqMaxLevel > 0 and sim.level > q.reqMaxLevel then return false end
  if q.level < sim.level - C.TrivialRange(sim.level) then return false end
  if P.TooHard(info, sim) then return false end
  if q.preGroup then for _, p in ipairs(q.preGroup) do if not isDone(sim, p) then return false end end end
  if q.preSingle and #q.preSingle > 0 then
    local any = false
    for _, p in ipairs(q.preSingle) do if isDone(sim, p) then any = true break end end
    if not any then return false end
  end
  if q.exclusiveTo then for _, e in ipairs(q.exclusiveTo) do if isDone(sim, e) or sim.log[e] then return false end end end
  if q.nextInChain ~= 0 and (isDone(sim, q.nextInChain) or sim.log[q.nextInChain]) then return false end
  if q.breadcrumbFor ~= 0 and (isDone(sim, q.breadcrumbFor) or sim.log[q.breadcrumbFor]) then return false end
  return true
end

-- Order objective areas by nearest neighbour from pos. Returns ordered list, travel seconds, end spot.
local function routeAreas(info, pos)
  local left, order, t, cur = {}, {}, 0, pos
  local firsts = 0   -- areas that come before the rest (an item the objective needs: QD:QuestNeeds)
  for _, a in ipairs(info.areas) do if a.spot then left[#left + 1] = a if a.first then firsts = firsts + 1 end end end
  while #left > 0 do
    local bi, bt = nil, math.huge
    for i, a in ipairs(left) do
      if firsts == 0 or a.first then
        local tt = P.Travel(cur, a.spot)
        if not bi or tt < bt then bi, bt = i, tt end
      end
    end
    local a = table.remove(left, bi)
    if a.first then firsts = firsts - 1 end
    order[#order + 1] = a
    t = t + bt
    cur = a.spot
  end
  return order, t, cur
end
P.routeAreas = routeAreas

-- After 0.8.4 (Boneless: sent to farm Gloom Weed, away from Brill, with the weed growing all along the road into Brill): a quest
-- whose one located objective is gathered off the ground, with enough of it lying on the way from `pos` to the hand-in, is done on
-- the way. Returns { order = { area at the first such place }, t = seconds to it, endSpot = the last such place before the hand-in },
-- or nil (then the densest place is used, as before).
function P.AlongWay(info, pos)
  if not (pos and pos.map) then return nil end
  local area
  for _, a in ipairs(info.areas) do
    if a.spot then
      if area then return nil end
      area = a
    end
  end
  if not (area and area.gather and area.raw) then return nil end
  local fin
  for _, f in ipairs(info.finishers) do
    if f.map == pos.map and (not fin or Nav.TravelSeconds(pos, f) < Nav.TravelSeconds(pos, fin)) then fin = f end
  end
  if not fin then return nil end
  local direct = Nav.TravelSeconds(pos, fin)
  local n, first, ft, last, lt = 0, nil, nil, nil, nil
  for _, s in ipairs(area.raw) do
    if s.map == pos.map then
      local a, b = Nav.TravelSeconds(pos, s), Nav.TravelSeconds(s, fin)
      if a + b - direct <= P.PATH_DETOUR then
        n = n + 1
        if not ft or a < ft then first, ft = s, a end
        if not lt or b < lt then last, lt = s, b end
      end
    end
  end
  if n < math.max(3, (area.count or 1) * P.PATH_MIN_NODES) then return nil end
  return { order = { { kind = area.kind, id = area.id, count = area.count, spot = { map = first.map, x = first.x, y = first.y } } }, t = ft,
           endSpot = { map = last.map, x = last.x, y = last.y } }
end

-- 0.7.2: the closest friendly innkeeper on the same map within BIND_NEAR seconds on foot:
-- { name = bind location, npc, map, x, y } (Panoply Suite's own route data: RD.inns / RD.bind).
P.innsByMap = nil
function P.NearInn(pos, faction)
  local Route = Panoply.Route
  local RD = Route and Route.Data and Route:Data()
  if not (RD and RD.inns and RD.bind and pos and pos.map) then return nil end
  if not P.innsByMap then
    local byMap, names = {}, {}
    for name, id in pairs(RD.bind) do names[id] = name end
    for id, i in pairs(RD.inns) do
      if names[id] and i[5] then
        byMap[i[5]] = byMap[i[5]] or {}
        local l = byMap[i[5]]
        l[#l + 1] = { name = names[id], npc = id, map = i[5], x = i[6], y = i[7] }
      end
    end
    P.innsByMap = byMap
  end
  local best, bt
  for _, inn in ipairs(P.innsByMap[pos.map] or {}) do
    if QD:NpcFriendly(inn.npc) ~= false then
      local t = Nav.TravelSeconds(pos, inn)
      if t <= P.BIND_NEAR and (not bt or t < bt) then best, bt = inn, t end
    end
  end
  return best
end

-- 0.7.2: an unknown flight master of your side (or neutral) on the same map within FP_NEAR seconds.
function P.NearFlightMaster(pos, planned)
  local Route = Panoply.Route
  local RD = Route and Route.Data and Route:Data()
  if not (RD and RD.nodes and pos and pos.map) then return nil end
  local okF, fac = pcall(Route.Faction, Route)
  if not okF then return nil end
  local best, bt
  for _, n in pairs(RD.nodes) do
    if (n[2] == "N" or n[2] == fac) and n[6] == pos.map and not Route:Known(n[1]) and not (planned and planned[n[1]]) then
      local spot = { map = n[6], x = n[7], y = n[8] }
      local t = Nav.TravelSeconds(pos, spot)
      if t <= P.FP_NEAR and (not bt or t < bt) then best, bt = { name = n[1], map = n[6], x = n[7], y = n[8], npc = n[9] }, t end
    end
  end
  return best
end

-------------------------------------------------------------------------------
-- 0.7.2 zone visits (WORKLIST 2, "plan whole zone visits"): the plan is built one choice at a time,
-- so inside a zone it walks out for one quest, back to the hub to hand it in, out again past the
-- same place, back again. After the plan is made, each zone visit (a run of take / do / hand-in
-- actions on one map) is tidied: any take, do or hand-in may move to where it costs the least
-- walking, which mostly means hand-ins at a hub are done together on one trip back. What can't
-- change: a quest is taken, then done, then handed in; two quests that are linked in any way
-- (prerequisite, follow-up, breadcrumb, one rules out the other, a special condition) keep their
-- order exactly as planned; every take and do happens at no lower level than the plan checked it
-- at (XP recounted along the new order); the quest log never goes over its size; a quest started
-- by an item in your bags is a fixed point nothing moves across. Flight paths, hearthstone binds,
-- grind steps and zone changes are not touched. 0 = off.
-------------------------------------------------------------------------------
P.VISIT_TIDY = 1
P.VISIT_MIN_GAIN = 20     -- s: a move must save at least this much walking
P.VISIT_PASSES = 4

function P.TidyVisits(actions, meta, byId, logSize)
  local n = #actions
  local saved, moved = 0, 0
  local i = 1
  while i <= n do
    local a = actions[i]
    -- a visit: take / do / hand-in actions on one map, no item-started take inside
    if (a.t == "a" or a.t == "d" or a.t == "t") and a.m and not a.i then
      local j = i
      while j + 1 <= n do
        local b = actions[j + 1]
        if not ((b.t == "a" or b.t == "d" or b.t == "t") and b.m == a.m and not b.i) then break end
        j = j + 1
      end
      if j - i >= 2 and meta[i] then
        local g, m = P.TidyVisit(actions, meta, byId, i, j, logSize or 20)
        saved, moved = saved + g, moved + m
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return saved, moved
end

-- Where a step starts and ends: takes and hand-ins at their spot; a "do" from its first objective
-- area to its last (areas in nearest-first order from the first).
P.alongEnds = setmetatable({}, { __mode = "k" })   -- "do" actions gathered on the way (P.AlongWay): action -> where it ends
local function visitEnds(a, info)
  local spot = { map = a.m, x = a.x, y = a.y }
  if a.t ~= "d" or not info or #info.areas == 0 then return spot, spot, 0 end
  local along = P.alongEnds[a]
  if along then return spot, along, Nav.TravelSeconds(spot, along) end
  local order, t, last = P.routeAreas(info, spot)
  if not order or #order == 0 then return spot, spot, 0 end
  return order[1].spot, last or order[#order].spot, t
end

-- Two different quests whose take / hand-in order matters to the game.
local function linked(x, y)
  if not (x and y) then return false end
  local qx, qy = x.q, y.q
  local F = QD:Fixes()
  if F and F.cond and (F.cond[qx.id] or F.cond[qy.id]) then return true end
  local function refers(a, b)  -- does quest a name quest b?
    for _, p in ipairs(a.preGroup or {}) do if p == b.id then return true end end
    for _, p in ipairs(a.preSingle or {}) do if p == b.id then return true end end
    for _, p in ipairs(a.exclusiveTo or {}) do if p == b.id then return true end end
    if a.nextInChain == b.id or a.breadcrumbFor == b.id then return true end
    if F and F.pre and F.pre[a.id] then for _, p in ipairs(F.pre[a.id]) do if p == b.id then return true end end end
    return false
  end
  return refers(qx, qy) or refers(qy, qx)
end

function P.TidyVisit(actions, meta, byId, i, j, logSize)
  local seq = {}
  for k = i, j do seq[#seq + 1] = actions[k] end
  local ends = {}
  local function E(a)
    local e = ends[a]
    if not e then
      local info = a.q and byId[a.q]
      local s0, s1, inner = visitEnds(a, info)
      -- a "do" gathered on the way (P.AlongWay) belongs where the plan put it: between where you were and its hand-in
      e = { s0, s1, inner, movable = ((a.t ~= "d") or (info ~= nil and #info.areas > 0)) and not P.alongEnds[a] }
      ends[a] = e
    end
    return e
  end
  local before, after = actions[i - 1], actions[j + 1]
  local entry = before and before.m == actions[i].m and before.x and { map = before.m, x = before.x, y = before.y } or nil
  local exit = after and after.m == actions[j].m and after.x and { map = after.m, x = after.x, y = after.y } or nil
  local function L(x, y)
    local p = x and E(x)[2] or entry
    local q = y and E(y)[1] or exit
    if not p or not q then return 0 end
    return Nav.TravelSeconds(p, q)
  end
  local function total(list)
    local c = 0
    for k = 1, #list do c = c + L(list[k - 1], list[k]) + E(list[k])[3] end
    return c + L(list[#list], nil)
  end
  -- pairs that must keep their planned order: steps of one quest, and steps of linked quests
  local keep = {}
  for x = 1, #seq do
    P.Tick()
    for y = x + 1, #seq do
      local a, b = seq[x], seq[y]
      if a.q and b.q and (a.q == b.q or linked(byId[a.q], byId[b.q])) then keep[#keep + 1] = { a, b } end
    end
  end
  local function valid(list)
    local at = {}
    for k, a in ipairs(list) do at[a] = k end
    for _, p in ipairs(keep) do if at[p[1]] > at[p[2]] then return false end end
    local sim = { level = meta[i].level, xp = meta[i].xp }
    local inLog = meta[i].log or 0
    for _, a in ipairs(list) do
      local info = a.q and byId[a.q]
      if (a.t == "a" or a.t == "d") and a.lv and sim.level < a.lv then return false end
      if a.t == "a" then inLog = inLog + 1 if inLog > logSize then return false end
      elseif a.t == "d" and info then addXP(sim, P.KillXP(info, sim.level))
      elseif a.t == "t" then inLog = inLog - 1 if info then addXP(sim, P.QuestXP(info.q, sim.level)) end end
    end
    return true
  end
  local start = total(seq)
  local moved = 0
  for _ = 1, P.VISIT_PASSES do
    local improved = false
    for k = 1, #seq do
      local a = seq[k]
      if E(a).movable then
        local gain = L(seq[k - 1], a) + L(a, seq[k + 1]) - L(seq[k - 1], seq[k + 1])
        local rest = {}
        for x = 1, #seq do if x ~= k then rest[#rest + 1] = seq[x] end end
        local bestP, bestD
        for p = 1, #rest + 1 do
          if p ~= k then
            P.Tick()
            local u, v = rest[p - 1], rest[p]
            local d = L(u, a) + L(a, v) - L(u, v) - gain
            if d < -P.VISIT_MIN_GAIN and (not bestD or d < bestD) then
              table.insert(rest, p, a)
              if valid(rest) then bestP, bestD = p, d end
              table.remove(rest, p)
            end
          end
        end
        if bestP then
          table.insert(rest, bestP, a)
          seq, improved, moved = rest, true, moved + 1
        end
      end
    end
    if not improved then break end
  end
  if moved == 0 then return 0, 0 end
  -- each step records the level the new order expects there (the guide re-plans when you are
  -- DRIFT_LEVELS off the plan, so a stale level would trigger needless re-plans)
  local sim = { level = meta[i].level, xp = meta[i].xp }
  for k = i, j do
    local a = seq[k - i + 1]
    actions[k] = a
    if a.t == "d" then local e = E(a) a.m, a.x, a.y = e[1].map, e[1].x, e[1].y end
    if a.lv then a.lv = math.max(a.lv, sim.level) end
    local info = a.q and byId[a.q]
    if a.t == "d" and info then addXP(sim, P.KillXP(info, sim.level))
    elseif a.t == "t" and info then addXP(sim, P.QuestXP(info.q, sim.level)) end
  end
  return start - total(seq), moved
end

-------------------------------------------------------------------------------
-- exp/lookahead: the look-ahead zone chooser (prototype for LOOKAHEAD-PLAN.md; off unless P.LOOKAHEAD = 1)
-- When the route has to leave a zone, it no longer takes the zone with the most work per second of walking.
-- It plays out short visit sequences ("rollouts") over the quests that are in reach 2-3 levels ahead:
--   visit a zone -> do everything that is available there at that level (and what that opens) -> next zone ...
-- and scores each sequence by the seconds it takes to gain LA_LEVELS levels. A trip to another continent costs
-- the route's own time plus LA_CROSS; gaps are filled with grinding at the plan's own grind rate. The first
-- zone of the best sequence is the one the route goes to. No quest is taken or skipped by this code itself: the
-- usual greedy plan still builds the visit, so every rule of the planner (levels, prerequisites, friendly
-- hand-in NPCs, roads) holds as before.
-------------------------------------------------------------------------------
-- 0.7.3.4 (match the shape of a typical levelling route): ON from level 20, the settings measured in docs/route/PLANNER-FINAL-PLAN.md.
-- The kill switch is one line: P.LOOKAHEAD = 0 gives the planner of 0.7.3.3 (P.LA_CHAIN = 0 as well for the chain value).
P.LOOKAHEAD = 0             -- 0.7.3.4 ships OFF (Code Reviewer, Nov 3: un-sliced re-plans freeze 5-15 s with it on; partner wait too short). Off = the 0.7.3.3 planner.
P.LA_FROM_LEVEL = 20        -- the chooser runs from this level (our zone rule alone below it; at 1-19 it costs Safe 1-20 hours, measured)
P.LA_LEVELS = 4            -- levels to gain in a rollout
P.LA_DEPTH = 5             -- zone visits per sequence
P.LA_BRANCH = 2            -- zones tried per step after the first (best by a quick key)
P.LA_ROOTS = 8             -- zones tried as the first step, best by the greedy planner's score (0 = all)
P.LA_CROSS = 12000         -- s: extra cost of a trip to another continent, on top of the route time (above about 6,000 the number no longer matters)
P.LA_HOP = 60              -- s: arriving in another zone (finding your feet)
P.LA_QUEST_OVERHEAD = 220  -- s per quest in a rollout visit: accept, hand-in, short walks inside the zone
P.LA_VISIT_CAP = 14        -- quests per scan of a zone
P.LA_ROOT_GRIND = 0        -- 1 = grinding a level here first is also a choice when the route has to leave
P.LA_GRIND_MAX = 2         -- grinding steps (levels) in one sequence besides the final fill
P.LA_MIN_N = 0             -- planner-final: a zone with fewer things to do than this is not a choice while a bigger zone exists (0 = off)
P.LA_CROSS_MIN_N = 0       -- planner-final: ... and the same for a zone on another continent (0 = off)
P.LA_PACE = 1              -- 1 = use the player's own measured seconds per kill (S.killSeconds / S.grindSeconds) for rollouts
P.LA_STATS = { decisions = 0, rollouts = 0, visits = 0, cpu = 0 }

-- exp/lookahead: what a quest leads to. succ[id] = quests that need it done first (candidates only); chain XP and seconds
-- of everything downstream (each quest once, at most LA_CHAIN_MAX quests), valued at the level they open at.
P.LA_CHAIN = 0             -- 0.7.3.4 ships OFF with the look-ahead. 1 = a lead-in quest counts with the quests it unlocks (accept filter and rollouts); 0.7.3.4: on from LA_CHAIN_FROM
P.LA_CHAIN_MAX = 12
P.LA_CHAIN_FROM = 20       -- planner-final: chain value counts from this level (measured: below 20 it costs Safe 1-20 about 7%)
local function laBuildSucc(cands)
  local F = QD:Fixes()
  local succ = {}
  local function add(p, info) local l = succ[p] if not l then l = {} succ[p] = l end l[#l + 1] = info end
  for _, info in ipairs(cands) do
    local q = info.q
    if F and F.pre and F.pre[q.id] then for _, p in ipairs(F.pre[q.id]) do add(p, info) end end
    for _, p in ipairs(q.preGroup or {}) do add(p, info) end
    for _, p in ipairs(q.preSingle or {}) do add(p, info) end
  end
  return succ
end
function P.LA_ChainValue(info, succ, level)
  local cv = info.laCv   -- once per plan (the infos are rebuilt for every plan); valued at the level of the first use
  if cv then return cv[1], cv[2], cv[3] end
  local seen, n, xp, sec = { [info.q.id] = true }, 0, 0, 0
  local stack = { info.q.id }
  while #stack > 0 and n < P.LA_CHAIN_MAX do
    local id = table.remove(stack)
    for _, s in ipairs(succ[id] or {}) do
      local sid = s.q.id
      if not seen[sid] and n < P.LA_CHAIN_MAX then
        seen[sid] = true
        n = n + 1
        local lv = math.max(level, s.q.reqLevel or 1)
        xp = xp + P.QuestXP(s.q, lv) + P.KillXP(s, lv)
        sec = sec + s.work + 120
        stack[#stack + 1] = sid
      end
    end
  end
  info.laCv = { xp, sec, n }
  return xp, sec, n
end

-- the player's own pace (S.killSeconds / S.grindSeconds, measured from their kills); the plan's constants until it is known
P.laKillScale, P.laGrindSec = 1, nil
local function laGrindRate(level) return P.MobXPAt(level, level) / (P.laGrindSec or (P.WORK_SECONDS.kill * 1.5)) end
local function laWork(info)
  local kw = info.laKillWork
  if not kw then
    kw = 0
    for _, k in ipairs(info.kills or {}) do kw = kw + k.n * P.WORK_SECONDS.kill * (k.elite and 3 or 1) end
    info.laKillWork = kw
  end
  return info.work + kw * (P.laKillScale - 1) + P.LA_QUEST_OVERHEAD
end

local function laNewState(parent)
  local R = {}
  for k, v in pairs(parent) do R[k] = v end
  R.done = setmetatable({}, { __index = parent.done })
  local pend = {}
  for z, p in pairs(parent.pend) do pend[z] = { xp = p.xp, sec = p.sec } end
  R.pend = pend
  return R
end

local function laGain(R, xp)
  if xp and xp > 0 then addXP(R, xp) end
end

-- grind one level here
local function laGrind(R)
  local need = math.max(0, P.XPToLevel(R.level) - R.xp)
  R.t = R.t + need / math.max(laGrindRate(R.level), 0.1)
  addXP(R, need)
end

-- The static picture of this plan: quests by the zone they are given in, a hub per zone.
local function laSetup(S, sim, cands)
  local L = { idx = {}, hub = {}, cont = {}, zones = {}, finisherZone = {} }
  local contOf = QD.continentOf or {}
  for i, info in ipairs(cands) do
    if i % 40 == 0 then P.Tick() end
    if not info.inLog then
      local g = info.givers[1]
      local m = g and g.map
      if m then
        local l = L.idx[m]
        if not l then l = {} L.idx[m] = l L.zones[#L.zones + 1] = m end
        l[#l + 1] = info
      end
    end
  end
  for m, list in pairs(L.idx) do
    P.Tick()   -- planner-final: one zone's hub search per tick
    -- hub: the giver spot with the smallest summed walking to the other (up to 24) giver spots of the zone
    local spots = {}
    for i, info in ipairs(list) do if i <= 24 then spots[#spots + 1] = info.givers[1] end end
    local best, bestSum = spots[1], math.huge
    for _, a in ipairs(spots) do
      local sum = 0
      for _, b in ipairs(spots) do sum = sum + Nav.TravelSeconds(a, b) end
      if sum < bestSum then best, bestSum = a, sum end
    end
    L.hub[m] = best
    L.cont[m] = contOf[m]
  end
  P.Tick()
  L.succ = laBuildSucc(cands)
  P.Tick()
  -- hub-to-hub trip times are kept between plans; a new flight path or bind changes the roads, so the cache starts over then
  local epoch = Panoply.Route and Panoply.Route.epoch or 0
  if P.laPairEpoch ~= epoch then P.laPairCache, P.laPairEpoch = nil, epoch end
  L.pairT = P.laPairCache or {}
  P.laPairCache = L.pairT
  return L
end

local function laHubTime(L, a, b)
  local k = a * 100000 + b
  local t = L.pairT[k]
  if t then return t end
  local ha, hb = L.hub[a], L.hub[b]
  if not ha or not hb then t = Nav.CROSS_ZONE_SECONDS
  else t = P.Travel(ha, hb) end
  L.pairT[k] = t
  return t
end

local function laEntry(L, R, z, firstT)
  local t
  if R.zone == nil then t = firstT or Nav.CROSS_ZONE_SECONDS
  else t = laHubTime(L, R.zone, z) end
  local ca, cb = L.cont[R.zone or z], L.cont[z]
  if R.zone ~= nil and ca and cb and ca ~= cb then t = t + P.LA_CROSS end
  if R.zone ~= z then t = t + P.LA_HOP end
  return t
end

-- The zone where the hand-in of a quest given in zone z happens (z itself when a finisher is there).
local function laFinisherZone(info, z)
  local fz = info.laFz
  if fz == nil then
    fz = false
    local f = info.finishers
    if f and #f > 0 then
      fz = f[1].map
      for _, s in ipairs(f) do if s.map == z then fz = z break end end
    end
    info.laFz = fz
  end
  return fz or z
end

-- Do everything available in zone z at the current level of the rollout state.
local function laVisit(L, R, z)
  P.Tick()
  P.LA_STATS.visits = P.LA_STATS.visits + 1
  local pz = R.pend[z]
  if pz then
    R.t = R.t + pz.sec
    laGain(R, pz.xp)
    R.pend[z] = nil
  end
  local list = L.idx[z]
  if not list then R.zone = z return end
  for _ = 1, 4 do
    local n = 0
    for i, info in ipairs(list) do
      local id = info.q.id
      if i % 10 == 0 then P.Tick() end   -- planner-final: a scan of a big zone is cut into slices too
      if n >= P.LA_VISIT_CAP then break end
      if not R.done[id] and not R.baseDone[id] and P.Available(info, R) then
        local kxp = P.KillXP(info, R.level)
        local qxp = P.QuestXP(info.q, R.level)
        local w = laWork(info)
        local okRate = (kxp + qxp) / w >= P.MinRate(R.level) * laGrindRate(R.level)
        if not okRate and P.LA_CHAIN and P.LA_CHAIN ~= 0 and R.level >= P.LA_CHAIN_FROM and L.succ[id] then
          local cx, cs = P.LA_ChainValue(info, L.succ, R.level)
          okRate = cx > 0 and (kxp + qxp + cx) / (w + cs) >= P.MinRate(R.level) * laGrindRate(R.level)
        end
        if okRate then
          n = n + 1
          R.done[id] = true
          R.t = R.t + w
          laGain(R, kxp)
          local fz = laFinisherZone(info, z)
          if fz == z then laGain(R, qxp)
          else
            local p = R.pend[fz]
            if not p then p = { xp = 0, sec = 0 } R.pend[fz] = p end
            p.xp, p.sec = p.xp + qxp, p.sec + 45
          end
        end
      end
    end
    if n == 0 then break end
  end
  R.zone = z
end

-- Quick value of visiting zone z next: quest XP per second of what is available there now (no state change).
local function laQuickKey(L, R, z, entry)
  P.Tick()   -- planner-final: one zone's scan is the largest unit between two ticks
  local xp, sec = 0, 0
  local pz = R.pend[z]
  if pz then xp, sec = pz.xp, pz.sec end
  local list = L.idx[z]
  local n = 0
  if list then
    for i, info in ipairs(list) do
      if i % 10 == 0 then P.Tick() end
      if n >= P.LA_VISIT_CAP then break end
      if not R.done[info.q.id] and not R.baseDone[info.q.id] and P.Available(info, R) then
        n = n + 1
        xp = xp + P.QuestXP(info.q, R.level) + P.KillXP(info, R.level)
        sec = sec + laWork(info)
      end
    end
  end
  if xp <= 0 then return nil end
  return xp / (entry + sec + 1), n + (pz and 1 or 0)
end

-- Finish a sequence: grind whatever is missing to reach the target level; returns the seconds.
local function laFill(R, target)
  while R.level < target do laGrind(R) end
  return R.t
end

local function laSearch(L, R, target, depth, grinds)
  P.Tick()
  -- options: zones with something to do, best few by the quick key; or grind a level here
  local opts = {}
  for _, z in ipairs(L.zones) do
    if z ~= R.zone then
      local entry = laEntry(L, R, z)
      local key, n = laQuickKey(L, R, z, entry)
      if key then
        local cross = R.zone ~= nil and L.cont[R.zone] and L.cont[z] and L.cont[R.zone] ~= L.cont[z]
        opts[#opts + 1] = { z = z, key = key, n = n, cross = cross }
      end
    end
  end
  if P.LA_MIN_N > 0 or P.LA_CROSS_MIN_N > 0 then
    local keep = {}
    for _, o in ipairs(opts) do
      if o.n >= P.LA_MIN_N and (not o.cross or o.n >= P.LA_CROSS_MIN_N) then keep[#keep + 1] = o end
    end
    if #keep > 0 then opts = keep end
  end
  for z, p in pairs(R.pend) do
    if z ~= R.zone and not L.idx[z] and p.xp > 0 then opts[#opts + 1] = { z = z, key = p.xp / (laEntry(L, R, z) + p.sec + 1) } end
  end
  table.sort(opts, function(a, b) return a.key > b.key end)
  local best = nil
  for i = 1, math.min(P.LA_BRANCH, #opts) do
    local o = opts[i]
    local C2 = laNewState(R)
    C2.t = C2.t + laEntry(L, R, o.z)
    laVisit(L, C2, o.z)
    local score
    if C2.level >= target then score = C2.t
    elseif depth + 1 >= P.LA_DEPTH then score = laFill(C2, target)
    else score = laSearch(L, C2, target, depth + 1, grinds) end
    if not best or score < best then best = score end
  end
  if grinds < P.LA_GRIND_MAX then
    local C2 = laNewState(R)
    laGrind(C2)
    local score
    if C2.level >= target then score = C2.t
    elseif depth + 1 >= P.LA_DEPTH then score = laFill(C2, target)
    else score = laSearch(L, C2, target, depth + 1, grinds + 1) end
    if not best or score < best then best = score end
  end
  if not best then
    local C2 = laNewState(R)
    best = laFill(C2, target)
  end
  return best
end

-- Choose among the zones the greedy planner found work in (`zones`: map -> { t = trip seconds, n = things to do, ... }).
-- Returns the chosen zone table, or "grind" when grinding one level here first is cheaper, or nil to fall back.
function P.LA_Choose(S, sim, cands, zones, here, goalLevel)
  local t0 = os.clock()
  P.LA_STATS.decisions = P.LA_STATS.decisions + 1
  if P.LA_PACE ~= 0 and S.killSeconds then
    P.laKillScale = S.killSeconds / P.WORK_SECONDS.kill
    P.laGrindSec = S.grindSeconds
  else P.laKillScale, P.laGrindSec = 1, nil end
  P.Tick()
  local L = P.laSetupCache
  if not (L and L.cands == cands) then L = laSetup(S, sim, cands) L.cands = cands P.laSetupCache = L end
  local R0 = {
    level = sim.level, xp = sim.xp, t = 0, zone = nil, hardcore = sim.hardcore,
    baseDone = sim.baseDone, done = setmetatable({}, { __index = sim.done }), log = sim.log, pend = {},
    maxAbove = sim.maxAbove, mobAbove = sim.mobAbove, acceptMobAbove = sim.acceptMobAbove,
    reqLevelFloor = sim.reqLevelFloor, lag = sim.lag,
  }
  -- what is already in the quest log: hand-ins waiting somewhere, objectives still to do
  for id, e in pairs(sim.log) do
    local info = e.info
    local f = info.finishers[1]
    if e.ready then
      if f then
        local p = R0.pend[f.map] or { xp = 0, sec = 0 }
        R0.pend[f.map] = p
        p.xp, p.sec = p.xp + P.QuestXP(info.q, sim.level), p.sec + 45
      end
    else
      local a = info.areas[1]
      local m = (a and a.spot and a.spot.map) or (f and f.map)
      if m then
        local p = R0.pend[m] or { xp = 0, sec = 0 }
        R0.pend[m] = p
        p.xp, p.sec = p.xp + P.QuestXP(info.q, sim.level) + P.KillXP(info, sim.level), p.sec + laWork(info)
      end
    end
  end
  local target = math.min(Panoply.MAX_LEVEL or 60, sim.level + P.LA_LEVELS)
  local scored = {}
  local skipSmall = nil
  if P.LA_MIN_N > 0 or P.LA_CROSS_MIN_N > 0 then
    -- planner-final: leave out the small zones (and the small ones on the other continent) while a bigger one exists
    local keepZ, any = {}, false
    for m, z in pairs(zones) do
      local cross = L.cont[here] and L.cont[m] and L.cont[here] ~= L.cont[m]
      if z.n >= P.LA_MIN_N and (not cross or z.n >= P.LA_CROSS_MIN_N) then keepZ[m] = true any = true end
    end
    if any then skipSmall = keepZ end
  end
  -- planner-final: only the best LA_ROOTS zones by the greedy planner's own score are played out as a first step (0 = all)
  local rootOK = nil
  if P.LA_ROOTS and P.LA_ROOTS > 0 then
    local list = {}
    for m, z in pairs(zones) do
      local sc = (z.t + P.ZONE_HOP_SECONDS) / math.min(z.n, P.BATCH_CAP)
      if z.n < P.MIN_BATCH then sc = sc * P.SMALL_BATCH_FACTOR end
      list[#list + 1] = { m = m, sc = sc }
    end
    if #list > P.LA_ROOTS then
      table.sort(list, function(a, b) if a.sc ~= b.sc then return a.sc < b.sc end return a.m < b.m end)
      rootOK = {}
      for i = 1, P.LA_ROOTS do rootOK[list[i].m] = true end
    end
  end
  for m, z in pairs(zones) do
   if (not skipSmall or skipSmall[m]) and (not rootOK or rootOK[m]) then
    local C2 = laNewState(R0)
    C2.t = (z.t or 0) + P.LA_HOP
    -- the real trip time z.t is from where the player stands; a trip to another continent also pays LA_CROSS
    local ca, cb = L.cont[here], L.cont[m]
    if ca and cb and ca ~= cb then C2.t = C2.t + P.LA_CROSS end
    laVisit(L, C2, m)
    local score
    if C2.level >= target then score = C2.t
    elseif P.LA_DEPTH <= 1 then score = laFill(C2, target)
    else score = laSearch(L, C2, target, 1, 0) end
    scored[#scored + 1] = { z = z, m = m, score = score, n = z.n }
   end
  end
  table.sort(scored, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.m < b.m end)
  local grindScore
  if P.LA_ROOT_GRIND and P.LA_ROOT_GRIND ~= 0 and sim.level < target then
    local C2 = laNewState(R0)
    C2.zone = here
    laGrind(C2)
    if C2.level >= target then grindScore = C2.t
    elseif P.LA_DEPTH <= 1 then grindScore = laFill(C2, target)
    else grindScore = laSearch(L, C2, target, 1, 1) end
    P.LA_STATS.grindScore = grindScore
  end
  local dt = os.clock() - t0
  P.LA_STATS.cpu = P.LA_STATS.cpu + dt
  if dt > (P.LA_STATS.max or 0) then P.LA_STATS.max = dt end
  P.LA_STATS.rollouts = P.LA_STATS.rollouts + #scored
  if grindScore and (not scored[1] or grindScore < scored[1].score) then return "grind", scored end
  return scored[1] and scored[1].z, scored
end

-------------------------------------------------------------------------------
-- Generate
-------------------------------------------------------------------------------
local function hop(spot, pos)
  if spot and pos and spot.map and pos.map and spot.map ~= pos.map then return P.ZONE_SWITCH_PENALTY end
  return 0
end

function P:Generate(S, opts)
  opts = opts or {}
  if not QD:Available() then return nil, "no quest database" end
  local t0 = os and os.clock and os.clock() or 0
  P.travelCache, P.travelCacheN = {}, 0
  if S.notOffered then for id, l in pairs(S.notOffered) do P.notOffered[id] = l end end
  local goalLevel = math.min(opts.goalLevel or (S.level + (S.horizon or 3)), Panoply.MAX_LEVEL or 60)
  local cands = opts.candidates or self:Candidates(S, goalLevel)
  local byId = {}
  for _, info in ipairs(cands) do byId[info.q.id] = info end

  local sim = {
    level = S.level, xp = S.xp or 0, pos = S.pos, log = {}, logCount = 0,
    baseDone = S.completed or {}, done = {}, hardcore = S.hardcore, time = 0,
    reqLevelFloor = S.partnerLevel and math.min(S.level, S.partnerLevel) or nil,
    lag = S.partnerLevel and math.max(0, S.level - S.partnerLevel) or 0,
  }
  -- how far above you a quest and its enemies may be (Difficulty.lua D.Rules)
  local rules = P.Rules(S)
  sim.maxAbove, sim.mobAbove = rules.maxAbove, rules.mobAbove
  sim.ownLevelUntil = rules.ownLevelUntil   -- (nil since 0.9.7: only the old Safe style had it)
  -- picking a quest up allows enemies ACCEPT_MOB_ABOVE levels above you (done once you level); rules that keep enemies lower keep that too
  sim.acceptMobAbove = (rules.mobAbove < P.MOB_ABOVE) and rules.mobAbove or P.ACCEPT_MOB_ABOVE
  for id, e in pairs(S.log or {}) do
    local info = byId[id]
    if info then sim.log[id] = { info = info, ready = e.ready or #info.areas == 0 }; sim.logCount = sim.logCount + 1 end
  end
  -- 0.7.2: the hearthstone. Where it is bound and when it is ready (seconds on the plan clock).
  local Route = Panoply.Route
  if Route and Route.Data and Route:Data() and not opts.noHearth then
    local okB, b = pcall(Route.BindSpot, Route)
    local okC, cd = pcall(Route.HearthCooldown, Route)
    if okC and cd then
      sim.stone = true
      sim.bind = okB and b and b.map and { map = b.map, x = b.x, y = b.y, name = b.name } or nil
      sim.hearthReady = cd
    end
  end
  local maxActions = opts.maxActions or 260
  local actions = {}
  local meta = {}   -- 0.7.2: level and XP before each action (for P.TidyVisits)
  local wrapUp = false

  local function push(a) actions[#actions + 1] = a meta[#actions] = { level = sim.level, xp = sim.xp, log = sim.logCount } end

  while #actions < maxActions do
    P.Tick()
    if sim.level >= goalLevel then wrapUp = true end
    local stop = false
    repeat   -- exp/lookahead: "break" below leaves this one-pass block (skips the rest of the pass), `stop` leaves the plan
    -- 0.7: gather every possible next action with its trip time, then score them together so the
    -- route stays in a zone while that zone still has work for you.
    local opts = {}
    local here = sim.pos and sim.pos.map
    for id, e in pairs(sim.log) do
      if e.ready then
        local spot, t = nearest(e.info.finishers, sim.pos)
        if e.info.noFinisher then spot, t = nil, 60 end
        local viaHearth, walk
        if spot and sim.stone and sim.bind and sim.time >= (sim.hearthReady or 0) then
          local th = P.HEARTH_SECONDS + P.Travel(sim.bind, spot)
          if th + P.HEARTH_GAIN < t then walk, t, viaHearth = t, th, true end
        end
        if not wrapUp or t < 400 then opts[#opts + 1] = { kind = "turnin", obj = e, spot = spot, t = t, cost = t, hearth = viaHearth, walk = walk,
                                                          xp = P.QuestXP(e.info.q, sim.level), work = 5 } end
      elseif not P.TooHard(e.info, sim) and P.MobsOK(e.info, sim) then  -- too hard right now = deferred
        local order, t, endSpot = routeAreas(e.info, sim.pos)
        local along = P.AlongWay(e.info, sim.pos)   -- gathered on the way to its hand-in, when enough of it lies there
        if along then order, t, endSpot = along.order, along.t, along.endSpot end
        local first = order and order[1] and order[1].spot
        if not wrapUp or t < 300 then opts[#opts + 1] = { kind = "do", obj = e, spot = first, endSpot = endSpot, order = order, t = t, cost = t + e.info.work, along = along and true or nil,
                                                          xp = P.KillXP(e.info, sim.level), work = e.info.work } end
      end
    end
    local wayside = {}   -- quests not worth a trip of their own that may still be worth taking when you walk past their giver
    if not wrapUp and sim.logCount < (S.logSize or 20) then
      local grind = P.MobXPAt(sim.level, sim.level) / (P.WORK_SECONDS.kill * 1.5) -- incl. rest/drink time
      for _, info in ipairs(cands) do
        P.Tick()
        if not info.inLog and P.Available(info, sim) then
          local spot, t = nearest(info.givers, sim.pos)
          if spot then
            -- feasibility: rough whole-quest trip; worth it compared with grinding mobs?
            local _, tObj, endSpot = routeAreas(info, spot)
            local _, tFin = nearest(info.finishers, endSpot or spot)
            local total = tObj + tFin + info.work
            local xp = P.QuestXP(info.q, sim.level) + P.KillXP(info, sim.level)
            local rate = xp / (t + total + 1)
            if P.LA_CHAIN and P.LA_CHAIN ~= 0 and sim.level >= P.LA_CHAIN_FROM then
              sim.succ = sim.succ or laBuildSucc(cands)
              if sim.succ[info.q.id] then
                local cx, cs = P.LA_ChainValue(info, sim.succ, sim.level)
                if cx > 0 then rate = math.max(rate, (xp + cx) / (t + total + cs + 1)) end
              end
            end
            if total <= P.MAX_QUEST_SECONDS and rate >= P.MinRate(sim.level) * grind then
              opts[#opts + 1] = { kind = "accept", obj = info, spot = spot, t = t, cost = t, ahead = math.max(0, (info.level or info.q.level) - sim.level),
                                  xp = xp, work = total }
            elseif total <= P.MAX_QUEST_SECONDS and spot.map == here then
              wayside[#wayside + 1] = { kind = "accept", obj = info, spot = spot, t = t, cost = t, ahead = math.max(0, (info.level or info.q.level) - sim.level),
                                        xp = xp, work = total, need = P.MinRate(sim.level) * grind }
            end
          end
        end
      end
    end
    if #opts == 0 then
      -- exp/lookahead: nothing to do at this level anywhere. Grind ONE level, then look again (quests that open one
      -- level up are found at once); the old plan ground all the way to the goal level in one block.
      if P.LA_STEP_GRIND and P.LA_STEP_GRIND ~= 0 and not wrapUp and sim.level < goalLevel and (sim.grindSteps or 0) < 12 then
        sim.grindSteps = (sim.grindSteps or 0) + 1
        local need = math.max(0, P.XPToLevel(sim.level) - sim.xp)
        local rate = P.MobXPAt(sim.level, sim.level) / (P.WORK_SECONDS.kill * 1.5)
        local p = sim.pos or {}
        push({ t = "g", lvl = sim.level + 1, m = p.map, x = p.x, y = p.y, lv = sim.level })
        sim.time = sim.time + need / math.max(rate, 0.1)
        addXP(sim, need)
        break
      end
      stop = true
      break
    end
    local zoneHasWork = false
    for _, o in ipairs(opts) do if o.spot and o.spot.map == here then zoneHasWork = true break end end
    -- 0.7 area stickiness inside one zone (Coldridge vs Kharanos): while there is work close by,
    -- a far trip in the same zone costs extra, so the route finishes one area before the next.
    local nearWork = false
    for _, o in ipairs(opts) do if o.t <= P.NEAR_SECONDS then nearWork = true break end end
    local nearDo = false
    for _, o in ipairs(opts) do if o.kind ~= "turnin" and o.t <= P.NEAR_SECONDS then nearDo = true break end end
    -- After 0.8.4 (Boneless at Solliden Farmstead with the Scarlet Warriors of quest 427 next door, told to hearth to Brill): the
    -- hearthstone is a shortcut home once the work around you is done. While a quest in your log has its work close by, a hand-in
    -- counts the walk it really is (and waits, P.TURNIN_DEFER), so the stone is not spent carrying you away from that work.
    local nearLogWork = false
    for _, o in ipairs(opts) do if o.kind == "do" and o.t <= P.NEAR_SECONDS then nearLogWork = true break end end
    if nearLogWork then
      for _, o in ipairs(opts) do
        if o.hearth then o.t, o.cost, o.hearth, o.walk = o.walk, o.walk, nil, nil end
      end
      nearWork = false
      for _, o in ipairs(opts) do if o.t <= P.NEAR_SECONDS then nearWork = true break end end
    end
    local allOpts = opts   -- every choice, before the zone batching narrows it (for the pickups on the way, below)
    -- 0.7.2 zone batching: work here first; leave only for the zone with the best batch
    local leaving
    if P.ZONE_BATCH and P.ZONE_BATCH ~= 0 and here then
      local loc, zones = {}, {}
      local G = (P.ZONE_BATCH ~= 1 and P.ZONE_GROUP) or {}
      local hereG = G[here] or here
      for _, o in ipairs(opts) do
        local m = o.spot and o.spot.map
        m = m and (G[m] or m)
        if not m or m == hereG or o.t <= P.BATCH_NEAR then loc[#loc + 1] = o
        else
          local z = zones[m]
          if not z then z = { map = m, n = 0, t = math.huge, opts = {}, xp = 0, work = 0 } zones[m] = z end
          z.n = z.n + 1
          z.xp, z.work = z.xp + (o.xp or 0), z.work + (o.work or 0)
          z.opts[#z.opts + 1] = o
          if o.t < z.t then z.t = o.t end
        end
      end
      if #loc > 0 then opts = loc
      else
        local bz, bs
        local laGrindNow = false
        if P.LOOKAHEAD and P.LOOKAHEAD ~= 0 and sim.level >= P.LA_FROM_LEVEL then
          local pick = P.LA_Choose(S, sim, cands, zones, here, goalLevel)
          if pick == "grind" then laGrindNow = true
          elseif pick then bz = pick end
        end
        if laGrindNow then
          -- grinding a level here first is the cheaper way to reach the next quests
          local need = math.max(0, P.XPToLevel(sim.level) - sim.xp)
          local rate = P.MobXPAt(sim.level, sim.level) / (P.WORK_SECONDS.kill * 1.5)
          local p = sim.pos or {}
          push({ t = "g", lvl = sim.level + 1, m = p.map, x = p.x, y = p.y, lv = sim.level })
          sim.time = sim.time + need / math.max(rate, 0.1)
          addXP(sim, need)
          break
        end
        if not bz then
        for _, z in pairs(zones) do
          -- 1 = our zone batch as stated: the zone with the most things to do per second of travel
          -- 2 = combined: seconds per XP of the whole visit (the trip, the zone change and the work there)
          local sc
          if P.ZONE_BATCH == 1 then sc = (z.t + P.ZONE_HOP_SECONDS) / math.min(z.n, P.BATCH_CAP)
          else sc = (z.t + P.ZONE_HOP_SECONDS + z.work) / math.max(1, z.xp) end
          if z.n < P.MIN_BATCH then sc = sc * P.SMALL_BATCH_FACTOR end
          if not bs or sc < bs then bz, bs = z, sc end
        end
        end
        if bz then opts = bz.opts leaving = bz end
      end
      zoneHasWork = not leaving
    end
    local best, bestScore
    for _, o in ipairs(opts) do
      local hop = 0
      if o.spot and here and o.spot.map and o.spot.map ~= here then hop = zoneHasWork and P.ZONE_LEAVE_PENALTY or P.ZONE_SWITCH_PENALTY
      elseif nearWork and o.t > P.FAR_SECONDS then hop = math.max(P.FAR_PENALTY, 2 * o.t) end  -- you walk back for the work left here
      local score
      if o.kind == "turnin" then
        score = (o.t + (zoneHasWork and hop or hop * 0.5)) / P.WEIGHT.turnin
        if nearDo and o.t > P.NEAR_SECONDS and not o.hearth then score = score * (1 + P.TURNIN_DEFER) end
      elseif o.kind == "do" then score = (o.t + P.DO_WORK_SHARE * (o.cost - o.t) + hop) / P.WEIGHT["do"]  -- the work itself has to be done anyway
      else score = (o.t + 3 + hop + o.ahead * P.LEVEL_AHEAD_PENALTY) / P.WEIGHT.accept end
      if not bestScore or score < bestScore then best, bestScore = o, score end
    end
    -- 0.7 zone lookahead: about to leave a zone only because its next quests need one more level?
    -- Then fight a little here (a grind step) instead of walking away and coming back later.
    if not zoneHasWork and best.kind ~= "turnin" and here and best.spot and best.spot.map ~= here
        and sim.level < goalLevel and (sim.grindHere or 0) < P.MAX_GRIND_STEPS then
      sim.level = sim.level + 1
      local soon = 0
      for _, info in ipairs(cands) do
        local g = info.givers[1]
        if g and g.map == here and not info.inLog and P.Available(info, sim) then soon = soon + 1 end
      end
      sim.level = sim.level - 1
      local need = math.max(0, P.XPToLevel(sim.level) - sim.xp)
      local rate = P.MobXPAt(sim.level, sim.level) / (P.WORK_SECONDS.kill * 1.5)
      local secs = need / math.max(rate, 0.1)
      if soon >= P.GRIND_FOR_QUESTS and secs <= math.max(P.MAX_LOCAL_GRIND, 2 * best.t + P.ZONE_LEAVE_PENALTY) then
        sim.grindHere = (sim.grindHere or 0) + 1
        local p = sim.pos or {}
        push({ t = "g", lvl = sim.level + 1, m = p.map, x = p.x, y = p.y, lv = sim.level })
        sim.time = sim.time + secs
        addXP(sim, need)
        best = nil
      end
    end
    -- After 0.8.4: a quest giver on the way to the stop just chosen is visited first (P.PATH_PICKUP). The stop itself is chosen
    -- again on the next pass, from the giver, so several givers along one road are taken in the order you pass them.
    if best and best.spot and best.spot.map and sim.pos and sim.pos.map == best.spot.map and not best.hearth then
      local via
      local function onWay(o)
        if o.kind ~= "accept" or o == best or o.spot.map ~= best.spot.map or o.t >= best.t then return nil end
        local detour = o.t + Nav.TravelSeconds(o.spot, best.spot) - best.t
        return detour <= P.PATH_PICKUP and detour or nil
      end
      for _, o in ipairs(allOpts) do
        if onWay(o) and (not via or o.t < via.t) then via = o end
      end
      -- a quest that was not worth a trip of its own: worth it when the trip is only the few steps off your way, and an item it
      -- hands you is not counted as work
      for _, o in ipairs(wayside) do
        local detour = onWay(o)
        if detour and o.xp / (math.max(0, detour) + o.work - (o.obj.handedWork or 0) + 1) >= o.need and (not via or o.t < via.t) then via = o end
      end
      if via then best = via end
    end
    if not best then
      -- grind step pushed; plan the next action at the new level
    else
    sim.time = sim.time + best.cost
    local lv = sim.level

    if best.hearth then
      sim.hearthReady = sim.time + P.HEARTH_CD - best.cost
      sim.hearths = (sim.hearths or 0) + 1
    end
    if best.kind == "accept" then
      local info, bestSpot = best.obj, best.spot
      sim.log[info.q.id] = { info = info, ready = #info.areas == 0 }
      sim.logCount = sim.logCount + 1
      push({ t = "a", q = info.q.id, m = bestSpot.map, x = bestSpot.x, y = bestSpot.y, n = bestSpot.npc, o = bestSpot.obj, i = bestSpot.item, lv = lv })
      sim.pos = bestSpot
    elseif best.kind == "do" then
      local e = best.obj
      local last = best.order and best.order[#best.order]
      local spot = best.spot or sim.pos
      push({ t = "d", q = e.info.q.id, m = spot and spot.map, x = spot and spot.x, y = spot and spot.y, lv = lv })
      e.ready = true
      addXP(sim, P.KillXP(e.info, sim.level))
      if best.along and best.endSpot then
        P.alongEnds[actions[#actions]] = best.endSpot
        sim.pos = best.endSpot
      elseif last and last.spot then sim.pos = last.spot end
    else -- turnin
      local e, bestSpot = best.obj, best.spot
      local q = e.info.q
      push({ t = "t", q = q.id, m = bestSpot and bestSpot.map, x = bestSpot and bestSpot.x, y = bestSpot and bestSpot.y, n = bestSpot and bestSpot.npc, o = bestSpot and bestSpot.obj, lv = lv })
      addXP(sim, P.QuestXP(q, sim.level))
      sim.log[q.id] = nil
      sim.logCount = sim.logCount - 1
      sim.done[q.id] = true
      if bestSpot then sim.pos = bestSpot end
    end
    -- 0.7.2: an unknown flight master close to the hub: learn the flight path while you are here
    if (best.kind == "accept" or best.kind == "turnin") and sim.pos then
      local fm = P.NearFlightMaster(sim.pos, sim.taxi)
      if fm then
        sim.taxi = sim.taxi or {}
        sim.taxi[fm.name] = true
        push({ t = "f", node = fm.name, m = fm.map, x = fm.x, y = fm.y, n = fm.npc, lv = sim.level })
        sim.time = sim.time + 10 + 2 * Nav.TravelSeconds(sim.pos, fm)
      end
    end
    -- 0.7.2: a questing hub with an inn, far from where the hearthstone is bound: set it here
    if sim.stone and (best.kind == "accept" or best.kind == "turnin") and sim.pos then
      local inn = P.NearInn(sim.pos, S.faction)
      if inn and inn.name ~= (sim.bind and sim.bind.name) and (not sim.bind or P.Travel(sim.bind, sim.pos) > P.BIND_FAR) then
        local n = 0
        for _, info in ipairs(cands) do
          local g = info.givers[1]
          if g and g.map == sim.pos.map and not info.inLog and not isDone(sim, info.q.id) and not sim.log[info.q.id]
              and Nav.TravelSeconds(g, sim.pos) <= 2 * P.BIND_NEAR then n = n + 1 end
        end
        for _, e in pairs(sim.log) do
          local f = e.info.finishers[1]
          if f and f.map == sim.pos.map and Nav.TravelSeconds(f, sim.pos) <= 2 * P.BIND_NEAR then n = n + 1 end
        end
        if n >= P.BIND_MIN_QUESTS then
          push({ t = "b", bind = inn.name, m = inn.map, x = inn.x, y = inn.y, n = inn.npc, lv = sim.level })
          sim.bind = { map = inn.map, x = inn.x, y = inn.y, name = inn.name }
          sim.binds = (sim.binds or 0) + 1
          sim.time = sim.time + 10 + 2 * Nav.TravelSeconds(sim.pos, inn)
        end
      end
    end
    end
    until true
    if stop then break end
  end

  if sim.level < goalLevel then
    local p = sim.pos or {}
    push({ t = "g", lvl = goalLevel, m = p.map, x = p.x, y = p.y })
  end
  local tidySaved, tidyMoved = 0, 0
  if P.VISIT_TIDY and P.VISIT_TIDY ~= 0 then tidySaved, tidyMoved = P.TidyVisits(actions, meta, byId, S.logSize or 20) end

  -- 0.5.8: quests in the log the route had to leave for later (too hard even at the end level)
  local deferred, dset = {}, {}
  for id, e in pairs(sim.log) do
    local why = not e.ready and P.TooHard(e.info, sim)
    if why then
      local Dif = Panoply.Difficulty
      local lvl = e.info.level or e.info.q.level
      deferred[#deferred + 1] = { questID = id, title = e.info.q.name, level = lvl, why = why,
                                  need = Dif.NeedLevel(lvl, e.info.group) + (sim.lag or 0) }
      dset[id] = true
    end
  end
  table.sort(deferred, function(a, b) return a.questID < b.questID end)
  self.deferred, self.deferredSet = deferred, dset

  local stats = {
    hearths = sim.hearths or 0, binds = sim.binds or 0, tidySaved = tidySaved, tidyMoved = tidyMoved,
    deferred = #deferred,
    candidates = #cands, actions = #actions, endLevel = sim.level, endXP = sim.xp,
    seconds = sim.time, startLevel = S.level, goalLevel = goalLevel,
    cpu = (os and os.clock and os.clock() or 0) - t0,
  }
  return actions, stats
end

-------------------------------------------------------------------------------
-- Actions -> Steps
-------------------------------------------------------------------------------
local function close(a, m, x, y)
  return a.mapID == m and a.x and x and math.abs(a.x - x) < 0.006 and math.abs(a.y - y) < 0.006
end

-- Plain-English objective parts: { verb, target, count } (never raw ids).
local function objectiveParts(q)
  local parts = {}
  local o = q.objectives or {}
  -- QuestData normalizes every list to { id, count|nil, text|nil } and kill credit to
  -- { {npcIds}, rootNpcId|nil, text|nil }; still check types so a stray value can't crash.
  local function n(v) return type(v) == "number" and v or nil end
  local function s(v) return type(v) == "string" and v ~= "" and v or nil end
  for _, c in ipairs(o.creatures or {}) do
    parts[#parts + 1] = { "Kill", QD:NpcName(n(c[1])) or s(c[3]) or "the marked enemies", n(c[2]) }
  end
  for _, kc in ipairs(o.killCredit or {}) do
    local first = type(kc[1]) == "table" and n(kc[1][1]) or n(kc[1])
    parts[#parts + 1] = { "Defeat", s(kc[3]) or QD:NpcName(n(kc[2])) or QD:NpcName(first) or "the marked enemies" }
  end
  for _, ob in ipairs(o.objects or {}) do parts[#parts + 1] = { "Use", QD:ObjectName(n(ob[1])) or s(ob[3]) or "the marked object", n(ob[2]) } end
  for _, it in ipairs(o.items or {}) do parts[#parts + 1] = { "Collect", QD:ItemName(n(it[1])) or s(it[3]) or "the quest item", n(it[2]) } end
  if #parts == 0 and type(q.objectivesText) == "table" and s(q.objectivesText[1]) then parts[1] = { nil, q.objectivesText[1] } end
  return parts
end
P.ObjectiveParts = objectiveParts

local function objectiveText(q)
  local out = {}
  for _, pt in ipairs(objectiveParts(q)) do
    out[#out + 1] = (pt[1] and (pt[1] .. " ") or "") .. (type(pt[3]) == "number" and pt[3] > 1 and (pt[3] .. " ") or "") .. pt[2]
  end
  return table.concat(out, "; ")
end
P.ObjectiveText = objectiveText

local function zoneName(m)
  if not m then return nil end
  return C.MapName(m)
end
P.ZoneName = zoneName

local function inZone(m) local z = zoneName(m) return z and (" in " .. z) or "" end
local function quoted(name) return "\226\128\156" .. name .. "\226\128\157" end  -- curly quotes
P.Quoted = quoted

-- A quest that can't be read or turned into a step is skipped (and debug-logged), never fatal.
P.skipped = {}
function P.SkipQuest(id, where, err)
  P.skipped[#P.skipped + 1] = { questID = id, where = where, err = tostring(err) }
  if #P.skipped > 200 then table.remove(P.skipped, 1) end
  Panoply:Debug("skipped quest", tostring(id), where, tostring(err))
end

function P:StepsFromActions(actions)
  local steps = {}
  for _, a in ipairs(actions) do
    local before = #steps
    local okA, err = pcall(self.StepFromAction, self, a, steps)
    if not okA then
      for i = #steps, before + 1, -1 do steps[i] = nil end
      P.SkipQuest(type(a) == "table" and a.q, "step", err)
    end
  end
  return steps
end

function P:StepFromAction(a, steps)
  do
    local q = a.q and QD:GetQuest(a.q)
    local qname = (q and q.name) or "this quest"
    if a.t == "a" and a.i then
      -- 0.7.2 (M1b): the quest starts from an item in your bags
      local iname = QD:ItemName(a.i) or "the quest item"
      steps[#steps + 1] = { kind = "talk", title = "Read " .. iname .. " in your bags", item = a.i, mapID = a.m, x = a.x, y = a.y, zone = zoneName(a.m),
        goals = { { type = "accept", questID = a.q, text = "Open " .. iname .. " and accept " .. quoted(qname) } }, accepts = { qname }, turnins = {} }
    elseif a.t == "a" or a.t == "t" then
      local who = (a.n and QD:NpcName(a.n)) or (a.o and QD:ObjectName(a.o))
      local last = steps[#steps]
      local step
      if last and last.kind == "talk" and last.npc == a.n and last.obj == a.o and (a.m == nil or close(last, a.m, a.x, a.y)) then
        step = last
      else
        local verb = a.o and "Use" or "Talk to"
        step = { kind = "talk", npc = a.n, obj = a.o, mapID = a.m, x = a.x, y = a.y, who = who, zone = zoneName(a.m),
                 title = (who and (verb .. " " .. who) or (a.t == "a" and "Find the quest giver" or "Find the quest ender")) .. inZone(a.m),
                 goals = {}, accepts = {}, turnins = {} }
        if a.m then step.goals[1] = { type = "goto", hint = true, mapID = a.m, x = a.x, y = a.y, radius = 15, text = "Go to " .. (who or "the marked spot") } end
        steps[#steps + 1] = step
      end
      if a.t == "a" then
        step.goals[#step.goals + 1] = { type = "accept", questID = a.q, text = "Accept " .. quoted(qname) }
        step.accepts[#step.accepts + 1] = qname
      else
        step.goals[#step.goals + 1] = { type = "turnin", questID = a.q, text = "Hand in " .. quoted(qname) }
        step.turnins[#step.turnins + 1] = qname
      end
    elseif a.t == "d" then
      local parts = q and objectiveParts(q) or {}
      local head
      if parts[1] and parts[1][1] then head = parts[1][1] .. " " .. parts[1][2] .. (parts[2] and " and more" or "")
      else head = "Work on " .. quoted(qname) end
      -- After 0.8.4: an item the objective needs first (QD:QuestNeeds: Samuel's Remains before Marla's Grave) gets its own step in
      -- front, at the creature that drops it; the objective's own step then points at the objective, not at that creature.
      local m, x, y = a.m, a.x, a.y
      local needed = false
      for _, nd in ipairs(q and QD:QuestNeeds(q) or {}) do
        local spot = P.Hotspot(nd.spots, a.m and { map = a.m, x = a.x, y = a.y } or nil)
        if spot and (C.ItemCount(nd.item) or 0) < nd.count then
          needed = true
          local iname = nd.name or QD:ItemName(nd.item) or "the item this quest needs"
          local from = nd.npcs[1] and QD:NpcName(nd.npcs[1])
          local questID, item, count = a.q, nd.item, nd.count
          -- shown until you have it; gone for good once the quest itself is finished (the item is used up at the objective)
          local function stillOpen(s)
            if s:IsCompleted(questID) then return false end
            local e = s.log[questID]
            return not (e and e.isComplete)
          end
          steps[#steps + 1] = { kind = "do", title = "Collect " .. iname .. inZone(spot.map), mapID = spot.map, x = spot.x, y = spot.y, questID = a.q,
            questName = qname, zone = zoneName(spot.map),
            goals = { { type = "collect", itemID = item, count = count, onlyIf = stillOpen,
                        text = "Collect " .. (count > 1 and (count .. " ") or "") .. iname .. (from and (" from " .. from) or "") .. " (needed for " .. quoted(qname) .. ")" },
                      { type = "goto", hint = true, onlyIf = stillOpen, mapID = spot.map, x = spot.x, y = spot.y, radius = 40, text = "Head to " .. (from or "where it is found") } } }
        end
      end
      if needed then
        local area = QD:ObjectiveAreas(q)[1]
        local spot = area and P.Hotspot(area.spots, a.m and { map = a.m, x = a.x, y = a.y } or nil)
        if spot then m, x, y = spot.map, spot.x, spot.y end
      end
      a = { q = a.q, m = m, x = x, y = y }
      local step = { kind = "do", title = head .. inZone(a.m), mapID = a.m, x = a.x, y = a.y, questID = a.q,
                     questName = qname, zone = zoneName(a.m), goals = {} }
      step.goals[1] = { type = "complete", questID = a.q, text = (q and objectiveText(q) ~= "" and objectiveText(q)) or ("Finish " .. quoted(qname)) }
      if a.m then step.goals[2] = { type = "goto", hint = true, mapID = a.m, x = a.x, y = a.y, radius = 40, text = "Head to the objective area" } end
      steps[#steps + 1] = step
    elseif a.t == "f" then
      -- 0.7.2: learn the flight path here (later trips can fly)
      local who = a.n and QD:NpcName(a.n)
      steps[#steps + 1] = { kind = "talk", npc = a.n, mapID = a.m, x = a.x, y = a.y, who = who, zone = zoneName(a.m),
        title = "Learn the flight path at " .. (a.node or "the flight master") .. inZone(a.m), accepts = {}, turnins = {},
        goals = { { type = "goto", hint = true, mapID = a.m, x = a.x, y = a.y, radius = 15, text = "Go to " .. (who or "the flight master") },
                  { type = "fpath", node = a.node, text = "Talk to " .. (who or "the flight master") .. " to learn the flight path" } } }
    elseif a.t == "b" then
      -- 0.7.2: set the hearthstone at this hub's innkeeper
      local who = a.n and QD:NpcName(a.n)
      steps[#steps + 1] = { kind = "talk", npc = a.n, mapID = a.m, x = a.x, y = a.y, who = who, zone = zoneName(a.m),
        title = "Make " .. (a.bind or "this inn") .. " your home" .. inZone(a.m), accepts = {}, turnins = {},
        goals = { { type = "goto", hint = true, mapID = a.m, x = a.x, y = a.y, radius = 15, text = "Go to " .. (who or "the innkeeper") },
                  { type = "sethome", inn = a.bind, text = "Ask " .. (who or "the innkeeper") .. " to make this inn your home (for your hearthstone)" } } }
    elseif a.t == "g" then
      steps[#steps + 1] = { kind = "grind", title = "Gain experience to level " .. a.lvl .. inZone(a.m), mapID = a.m, x = a.x, y = a.y,
        zone = zoneName(a.m), level = a.lvl,
        goals = { { type = "level", level = a.lvl, xp = 0, text = "Reach level " .. a.lvl .. " by defeating enemies around here" } } }
    end
  end
end

-------------------------------------------------------------------------------
-- Log-driven fallback (no database): follow what is in the quest log.
-------------------------------------------------------------------------------
function P:LogDrivenSteps()
  local steps = {}
  local rules = Panoply.Difficulty.Rules()
  self.skippedLog = {}
  for _, q in ipairs(C.IterQuestLog()) do
    local tag = C.QuestTag(q.questID)
    local why = ((tag and P.LOG_TAG_EXCLUDE[tag]) and (tag == "group" and "elite" or tag) or ((q.suggestedGroup or 0) > 1 and "elite")) or nil
    if why == "elite" and rules.elite then why = nil end
    if rules.dungeons and why ~= "raid" then why = nil end   -- "Always include them": only raid quests stay out
    if why then
      self.skippedLog[#self.skippedLog + 1] = { questID = q.questID, title = q.title, why = tag == "group" and "elite" or tag or "elite" }
    else
    local m, x, y = C.QuestWaypoint(q.questID)
    local qname = quoted(q.title or "a quest in your log")
    local goal = q.isComplete and { type = "turnin", questID = q.questID, text = "Hand in " .. qname }
                              or { type = "complete", questID = q.questID, text = "Finish " .. qname }
    local step = { kind = q.isComplete and "talk" or "do", title = (q.isComplete and "Hand in " or "Work on ") .. qname, mapID = m, x = x, y = y,
                   questName = q.title, logOnly = true, goals = { goal } }
    steps[#steps + 1] = step
    if not q.isComplete then
      steps[#steps + 1] = { kind = "talk", title = "Hand in " .. qname, logOnly = true, turnins = { q.title }, goals = { { type = "turnin", questID = q.questID, text = "Hand in " .. qname } } }
    end
    end
  end
  return steps
end

-------------------------------------------------------------------------------
-- Plan lifecycle
-------------------------------------------------------------------------------
-- 0.7.3.2: the hash covers everything a partner's copy of the route is built from (it used to be only the
-- action type and quest), so two routes that differ in a place, an NPC, an item or an expected level no longer
-- look the same. Coordinates are counted as the sync wire carries them (to 1/10000).
function P.ActionsHash(actions)
  local parts = {}
  local function q(v) return v and math.floor(v * 10000 + 0.5) or "" end
  for i, a in ipairs(actions) do
    parts[i] = table.concat({ a.t or "", a.q or a.lvl or "", a.m or "", q(a.x), q(a.y), a.n or "", a.o or "", a.i or "",
      a.lv or "", a.node or a.bind or "" }, ":")
  end
  return U.Hash(table.concat(parts, ","))
end

function P:PlanQuestSet()
  local set = {}
  for _, a in ipairs(self.actions or {}) do if a.q then set[a.q] = true end end
  return set
end

-- Adopt an action list (from our generator, saved vars, or a partner) into the step engine.
function P:Adopt(actions, title, source, keepIndex)
  if Panoply:PlayAlong() then return end   -- 0.7.1: playing along: no route is taken on (not even a partner's)
  if Panoply:NoGuideHere() then return end   -- 0.7.4.1: an area without a guide takes on no route (not even a partner's)
  self.actions = actions
  self.hash = P.ActionsHash(actions)
  self.planSet = self:PlanQuestSet()
  if Panoply.cdb then Panoply.cdb.plan = { actions = actions, title = title, hash = self.hash, source = source, flavor = Panoply.Compat.Flavor(), db = QD.fingerprint } end
  Panoply.Engine:SetSteps(self:StepsFromActions(actions), title, keepIndex)
  Panoply:Fire("PLAN_ADOPTED", source)
end

-------------------------------------------------------------------------------
-- 0.7 re-planning: does what just happened need a new plan? (ROUTE-FIX-PLAN.md, "Re-planning")
-- ctx = { events = {...}, plan = actions, index = next action, level, pos, log, completed }
-- Returns a short reason or nil. Cheap: called on quest log, level, zone and gossip events.
-------------------------------------------------------------------------------
function P:ReplanReason(ctx)
  local plan, i = ctx.plan or self.actions, ctx.index
  if not plan or not i then return nil end
  local a = plan[i]
  for _, ev in ipairs(ctx.events or {}) do
    if ev == "stuck" or ev == "notoffered" then
      local b = plan[i]
      if b and b.t == "a" then self:NoteNotOffered(b.q, ctx.level) end
      return "a quest giver did not offer the next quest"
    end
  end
  if not a then return nil end
  local level = ctx.level or 1
  -- levelled faster or slower than the plan expected
  if a.lv and math.abs(level - a.lv) >= P.DRIFT_LEVELS then return "level " .. level .. " (plan expected " .. a.lv .. ")" end
  if a.t == "a" then
    local q = QD:GetQuest(a.q)
    if q and (q.reqLevel or 0) > level then return "too low for the next quest" end
  end
  -- a quest the plan still needs is gone from the log (abandoned)
  local acceptedLater = {}
  for j = i, #plan do local b = plan[j] if b.t == "a" then acceptedLater[b.q] = true end end
  for j = i, #plan do
    local b = plan[j]
    if (b.t == "d" or b.t == "t") and not acceptedLater[b.q] and ctx.log and not ctx.log[b.q]
        and not (ctx.completed and ctx.completed[b.q]) then
      return "a planned quest left the log"
    end
  end
  -- far from where the plan expects you (hearth, flight, walked off, died at a graveyard)
  if ctx.pos and a.m and i > 1 then
    local prev = plan[i - 1]
    if prev and prev.m then
      local now = P.Travel(ctx.pos, { map = a.m, x = a.x, y = a.y })
      local planned = P.Travel({ map = prev.m, x = prev.x, y = prev.y }, { map = a.m, x = a.x, y = a.y })
      if now > planned + P.MOVED_SECONDS then return "you are somewhere else" end
    end
  end
  return nil
end

-- In game: the plan's next action (first one not yet satisfied) and the context for ReplanReason.
function P:GameContext(events)
  local S = Panoply.State
  local plan = self.actions
  if not plan or #plan == 0 then return nil end
  local done, log = S.completed or {}, S.log or {}
  local idx
  for j, b in ipairs(plan) do
    local ok
    if b.t == "a" then ok = log[b.q] ~= nil or done[b.q]
    elseif b.t == "d" then ok = done[b.q] or (log[b.q] and log[b.q].isComplete)
    elseif b.t == "t" then ok = done[b.q]
    elseif b.t == "f" then ok = (Panoply.cdb and Panoply.cdb.knownTaxi and Panoply.cdb.knownTaxi[b.node]) and true or false
    elseif b.t == "b" then ok = (C.BindLocation and C.BindLocation() == b.bind) and true or false
    else ok = false end
    if not ok then idx = j break end
  end
  if not idx then return nil end
  return { events = events or {}, plan = plan, index = idx, level = S.level or 1, pos = S.pos, log = log, completed = done }
end

-- Called by Core/Bootstrap.lua on quest-log, level, zone and gossip events (throttled there).
function P:CheckReplan(event)
  if Panoply:NoGuideHere() then return nil end   -- 0.7.4.1
  if not QD:Available() or not self.actions or #self.actions == 0 then return nil end
  local ctx = self:GameContext(event and { event } or nil)
  if not ctx then return nil end
  return self:ReplanReason(ctx)
end

-- Nov 11 2026: "turn planner off. use panoplyguide. when a user reports an issue on a missing quest then we incorporate it." The
-- written leveling guides (Engine/Guides.lua) are the only leveling route, on WoW Forever and on Classic Era: this planner never builds
-- one, by itself, after a setting or after a slash command, and an old saved routeSource = "planner" changes nothing. Where no written
-- guide has a step for the character the guide says so (Guides:NoStep) and the player can report the missing quest (/panoply report).
-- The planner stays for what is not a leveling route of its own: a Panoply Hub plan and a route shared in a party are action lists it
-- puts in the step engine (P:Adopt). No saved key, setting or command reaches BuildsLevelingRoute; only tests/run.lua turns it back on,
-- for the suite's older tests of the planner itself.
P.levelingOff = true
function P:BuildsLevelingRoute() return not self.levelingOff end

function P:Replan(reason)
  if Panoply:PlayAlong() then return false, "playing along" end   -- 0.7.1: the planner does not run
  -- 0.9.7 (Nov 18 2026): the guide engine cannot run: no converted guide, no quest-log route and no planner take its place
  if Panoply:GuideUnavailable() then return Panoply:ShowGuideUnavailable() end
  -- 0.8.0: a written leveling guide takes this character now (Engine/Guides.lua); nil = none applies, plan as before
  if Panoply.Guides and Panoply.Guides:UseHere() then
    local okG, info = Panoply.Guides:Start(reason)
    if okG ~= nil then return okG, info end
  end
  if Panoply:NoGuideHere() then return false, "no guide for this area" end   -- 0.7.4.1
  Panoply.State:RefreshAll()
  if not QD:Available() then QD:Init() end
  if not QD:Available() then
    Panoply.Engine:SetSteps(self:LogDrivenSteps(), "Your quest log")
    self.actions, self.hash, self.planSet = {}, nil, {}
    return false, QD.status
  end
  if not self:BuildsLevelingRoute() then return Panoply.Guides:NoStep(reason) end   -- Nov 11 2026: no planner fallback
  local S = self:StateFromGame()
  local okG, actions, stats = pcall(self.Generate, self, S)
  return self:FinishReplan(S, okG, actions, stats, reason)
end

function P:FinishReplan(S, okG, actions, stats, reason)
  if not okG then
    Panoply:Debug("replan failed", actions)
    Panoply:Print("Could not plan a route right now (a quest record could not be read). Type /panoply debug log for details.")
    return false, tostring(actions)
  end
  if not actions then return false, stats end
  local title = ("Levels %d to %d"):format(S.level, stats.goalLevel)
  self.lastStats = stats
  self:Adopt(actions, title, "local")
  if Panoply.Sync then Panoply.Sync:SharePlan() end   -- 0.7.3.2: a following partner does not push their route over the leader's
  Panoply:Debug("replan", reason or "", "actions", stats.actions, "end level", stats.endLevel, "cpu", stats.cpu)
  return true, stats
end

-------------------------------------------------------------------------------
-- 0.7.2 (M2): the automatic re-plan, time-sliced. Same plan as P:Replan, built a few ms per frame
-- (P.SLICE_MS), paused while you are in combat, dropped when the play-along questing mode is turned on.
-- cb(ok, info) runs when the plan is adopted (or failed). One re-plan at a time.
-------------------------------------------------------------------------------
P.sliceStats = { slices = 0, max = 0, last = 0 }
function P:ReplanAsync(reason, cb)
  if Panoply:PlayAlong() then if cb then cb(false, "playing along") end return nil end
  if Panoply:GuideUnavailable() then   -- 0.9.7 (Nov 18 2026): nothing takes the guide engine's place (P:Replan says so)
    local ok, info = self:Replan(reason)
    if cb then cb(ok, info) end
    return nil
  end
  if Panoply.Guides and Panoply.Guides:UseHere() then   -- 0.8.0: the written guide (Engine/Guides.lua) needs no planning
    local okG, info = Panoply.Guides:Start(reason)
    if okG ~= nil then if cb then cb(okG, info) end return nil end
  end
  if Panoply:NoGuideHere() then if cb then cb(false, "no guide for this area") end return nil end   -- 0.7.4.1
  if self.job then self.job.reason = reason; return self.job end
  Panoply.State:RefreshAll()
  if not QD:Available() then QD:Init() end
  if not QD:Available() or not self:BuildsLevelingRoute() then   -- Nov 11 2026: no planner fallback (P:Replan says so)
    local ok, info = self:Replan(reason)
    if cb then cb(ok, info) end
    return nil
  end
  local S = self:StateFromGame()
  local job = { reason = reason, cb = cb, S = S, slices = 0, maxMs = 0 }
  job.co = coroutine.create(function() return self:Generate(S) end)
  self.job = job
  if not self.driver then
    local f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnUpdate", function() P:Step() end)
    self.driver = f
  end
  self.driver:Show()
  return job
end

-- One frame of the running re-plan. Returns true when it finished.
function P:Step()
  local job = self.job
  if not job then if self.driver then self.driver:Hide() end return true end
  if Panoply:PlayAlong() then
    self.job = nil
    if self.driver then self.driver:Hide() end
    if job.cb then pcall(job.cb, false, "playing along") end
    return true
  end
  if Panoply:NoGuideHere() then   -- 0.7.4.1: walked into an area without a guide while the plan was being built
    self.job = nil
    if self.driver then self.driver:Hide() end
    if job.cb then pcall(job.cb, false, "no guide for this area") end
    return true
  end
  if C.InCombat and C.InCombat() then return false end   -- never plan during a fight
  P.slice = { co = job.co, start = pclock() }
  local okR, a, b = coroutine.resume(job.co)
  local ms = pclock() - P.slice.start
  P.slice = nil
  job.slices, job.maxMs = job.slices + 1, math.max(job.maxMs, ms)
  P.sliceStats.slices, P.sliceStats.last = job.slices, ms
  if ms > P.sliceStats.max then P.sliceStats.max = ms end
  if okR and coroutine.status(job.co) ~= "dead" then return false end
  self.job = nil
  if self.driver then self.driver:Hide() end
  local ok, info = self:FinishReplan(job.S, okR, a, b, job.reason)
  if type(info) == "table" then info.slices, info.maxSliceMs = job.slices, job.maxMs end
  if job.cb then pcall(job.cb, ok, info) end
  return true
end
