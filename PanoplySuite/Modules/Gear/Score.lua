-- Panoply Suite gear engine, part 1: the pure scoring (docs/specs/page-redesigns-04-gear-engine.md sections 3, 5 and 8).
-- NO game calls in this file: it works on plain tables, so tests/gear_pure_tests.lua runs it under a bare Lua 5.1 with made-up
-- items. Everything that asks the game something (what is worn, what an item is, where it comes from) is in Gear.lua and
-- Sources.lua, which hand their answers to the functions here.
--
-- An item, as this file sees it:
--   { id, name, link, slot (the game's inventory type number), class (2 weapon, 4 armor), sub (subclass), quality,
--     req (required level), ilvl, mask (class bits; nil or 0 = any class), stats = { str = 5, armor = 120, dps = 31.4 },
--     suffix (a random suffix's number), effect = true (it has an effect that is not in its stats), unique = true,
--     pending = true (the game has not sent its numbers yet: never scored) }
-- A character, as this file sees it (ctx; Gear.lua builds the full one):
--   { class, level, stats = the plan's weights for that level (S.Weights), equipped = { [inventory slot id] = item },
--     trained = { [weapon subclass] = true } or nil when the game does not say which weapon skills are trained, gold }
local ADDON, Panoply = ...

local S = {}
Panoply.GearScore = S
local W, R = Panoply.GearWeights, Panoply.GearRules
local INV = R.INV

S.MIN_DELTA = 0.05        -- a candidate this much better than what is worn is an upgrade (anything less would read "+0.0")
S.DEFAULT_LIMIT = 5       -- candidates kept per slot when the filter gives no limitPerSlot
local MAIN, OFF = 16, 17

-- the order equal contributions are listed in, and each stat's words
S.STAT_ORDER, S.STAT_LABEL = {}, {}
for i, s in ipairs(W.STATS) do S.STAT_ORDER[s[1]] = i S.STAT_LABEL[s[1]] = s[2] end

-- each tree's table knows its class and its place among the talent tabs
for class, list in pairs(W.classes) do
  for i, t in ipairs(list) do t.class, t.tree = class, i end
end

S.SLOTS, S.SLOT_ORDER = {}, {}
for i, s in ipairs(R.SLOTS) do
  S.SLOTS[s[1]] = { key = s[1], label = s[2], ids = s[3], order = i }
  S.SLOT_ORDER[i] = s[1]
end
-- inventory slot id -> the slot's key
S.SLOT_OF_ID = {}
for _, s in ipairs(R.SLOTS) do for _, id in ipairs(s[3]) do S.SLOT_OF_ID[id] = s[1] end end
-- rings and trinkets share one list of candidates; so do the two hands (a one-hand weapon can go in either)
local function poolOf(slotKey) return (slotKey == "mainhand" or slotKey == "offhand") and "weapon" or slotKey end
S.PoolOf = poolOf

-------------------------------------------------------------------------------
-- Weights
-------------------------------------------------------------------------------
local function norm(s) return (tostring(s):lower():gsub("[^%a]", "")) end

function S.Specs(class)
  if type(class) ~= "string" then return nil end
  return W.classes[class:upper()]
end

-- The table of one talent tree. spec: our key, the tab's name or its number; nil gives the class default.
function S.Table(class, spec)
  local list = S.Specs(class)
  if not list then return nil end
  if spec == nil then
    for _, t in ipairs(list) do if t.default then return t end end
    return list[1]
  end
  if type(spec) == "number" then return list[spec] end
  local want = norm(spec)
  for _, t in ipairs(list) do
    if t.spec == want or norm(t.name) == want then return t end
  end
  return nil
end

-- The table a plan is weighed with, and how it was found. plan = { key, from = the ready-made plan it was copied from,
-- topTree = the number of the tree it has the most points in } (any of them may be missing; nil = no plan).
--   "own"      the plan (or the one it was copied from) has a table of its own in Data/GearWeights.lua
--   "plan"     the table of the ready-made plan's main tree
--   "copied"   the table of the ready-made plan this one was copied from
--   "tree"     the tree the plan has the most points in
--   "default"  the class default (no plan, or a plan with no point spent)
function S.ForPlan(class, plan)
  if not S.Specs(class) then return nil end
  plan = plan or {}
  for _, k in ipairs({ plan.key or false, plan.from or false }) do
    local own = k and W.own[k]
    if type(own) == "table" and type(own.stats) == "table" then
      local base = S.Table(class, own.spec or W.plans[k])
      return { class = class:upper(), spec = own.spec or (base and base.spec) or k, name = own.name or (base and base.name) or k,
        role = own.role or (base and base.role), tree = base and base.tree, stats = own.stats, bands = own.bands, plan = k }, "own"
    end
  end
  if plan.key and W.plans[plan.key] then return S.Table(class, W.plans[plan.key]), "plan" end
  if plan.from and W.plans[plan.from] then return S.Table(class, W.plans[plan.from]), "copied" end
  if plan.topTree and S.Table(class, plan.topTree) then return S.Table(class, plan.topTree), "tree" end
  return S.Table(class), "default"
end

-- The weights of a table at a level: `stats`, with the band for that level laid over them and the off-hand weapon weight
-- filled in (half the main hand's, the game's own rule) when the table leaves it out. The same table is given back for the
-- same band, so it can be used as a key.
local resolved = setmetatable({}, { __mode = "k" })
function S.Weights(tbl, level)
  if type(tbl) ~= "table" or type(tbl.stats) ~= "table" then return nil end
  local band = 0
  if type(tbl.bands) == "table" then
    for from in pairs(tbl.bands) do
      if type(from) == "number" and from <= (level or 1) and from > band then band = from end
    end
  end
  local per = resolved[tbl]
  if not per then per = {} resolved[tbl] = per end
  local out = per[band]
  if out then return out, band end
  out = {}
  for k, v in pairs(tbl.stats) do out[k] = v end
  if band > 0 then for k, v in pairs(tbl.bands[band]) do out[k] = v end end
  if out.odps == nil then out.odps = (out.dps or 0) * 0.5 end
  per[band] = out
  return out, band
end

-------------------------------------------------------------------------------
-- What a class can use
-------------------------------------------------------------------------------
-- Returns usable (true when it can be worn right now) and a table that says why not:
--   { never = true, why = "class" | "armor" | "weapon" | "slot" }    this class can never use it: it is never listed
--   { level = 17 }                                                   wearable from that level
--   { skill = "Axes" }                                               the weapon skill is not trained yet
-- (level and skill can both be set). trained: { [weapon subclass] = true }, or nil when it is not known (then no item is held
-- back for it).
function S.CanUse(class, item, level, trained)
  local rules = type(class) == "string" and R.classes[class:upper()]
  if not (rules and type(item) == "table") then return false, { never = true, why = "class" } end
  level = level or 60
  local mask = item.mask
  if mask and mask > 0 and (mask % (rules.bit * 2)) < rules.bit then return false, { never = true, why = "class" } end
  local slotKey = R.GOES_IN[item.slot or 0]
  if not slotKey or rules.never[slotKey] then return false, { never = true, why = "slot" } end
  local need, skill = item.req or 0, nil
  if item.class == 4 then
    -- cloaks, rings, necks, trinkets and things held in the off hand have no armor training
    if item.slot ~= INV.BACK and item.sub and item.sub >= 1 then
      local from = rules.armor[item.sub]
      if not from then return false, { never = true, why = "armor" } end
      if from > need then need = from end
    end
  elseif item.class == 2 then
    if not rules.weapons[item.sub or -1] then return false, { never = true, why = "weapon" } end
    if item.slot == INV.OFF_HAND then
      if not rules.dualWield then return false, { never = true, why = "weapon" } end
      if rules.dualWield > need then need = rules.dualWield end
    end
    if trained and not trained[item.sub] then
      local ws = R.WEAPON_SKILL[item.sub]
      skill = ws and ws[1] or "this weapon"
    end
  else
    return false, { never = true, why = "class" }
  end
  if need > level or skill then
    return false, { level = need > level and need or nil, skill = skill }
  end
  return true, nil
end

-- The same words on every page (spec section 6).
function S.LockText(lock)
  if type(lock) ~= "table" or lock.never then return nil end
  if lock.skill then return "Needs weapon training: " .. lock.skill end
  if lock.level then return ("At level %d"):format(lock.level) end
  return nil
end

-- Can the class hold a weapon in the off hand at this level?
function S.DualWield(class, level)
  local rules = type(class) == "string" and R.classes[class:upper()]
  return rules ~= nil and rules.dualWield ~= nil and (level or 60) >= rules.dualWield
end

-------------------------------------------------------------------------------
-- Scoring one item
-------------------------------------------------------------------------------
local function isTwoHand(item) return item ~= nil and item.slot == INV.TWO_HAND end
S.IsTwoHand = isTwoHand

-- which weight a weapon's damage per second is multiplied by
local function weaponKey(item, offHand)
  if item.sub == R.WAND then return "wand" end
  if R.RANGED_WEAPON[item.sub or -1] or item.slot == INV.BOW or item.slot == INV.THROWN or item.slot == INV.RANGED then return "rdps" end
  if offHand or item.slot == INV.OFF_HAND then return "odps" end
  return "dps"
end

-- score = the sum of stat value x weight, plus the weapon term (weapons only): damage per second x the plan's weight for the
-- place the weapon is held. offHand: the weapon would sit in the off hand.
-- wantBreakdown: also return the list { { stat, value, weight, contribution, label }, ... }, biggest contribution first.
function S.Score(item, weights, offHand, wantBreakdown)
  if not (type(item) == "table" and type(weights) == "table" and type(item.stats) == "table") then return 0, wantBreakdown and {} or nil end
  local total = 0
  local list = wantBreakdown and {} or nil
  for k, v in pairs(item.stats) do
    local key = k
    if k == "dps" then key = item.class == 2 and weaponKey(item, offHand) or nil end
    local w = key and weights[key] or 0
    if w ~= 0 and v ~= 0 then
      total = total + v * w
      if list then list[#list + 1] = { stat = key, value = v, weight = w, contribution = v * w, label = S.STAT_LABEL[key] or key } end
    end
  end
  if list then
    table.sort(list, function(a, b)
      if a.contribution ~= b.contribution then return a.contribution > b.contribution end
      return (S.STAT_ORDER[a.stat] or 99) < (S.STAT_ORDER[b.stat] or 99)
    end)
  end
  return total, list
end

-- A score as the player reads it: whole numbers from 10, one decimal under 10.
function S.Num(n)
  n = tonumber(n) or 0
  if math.abs(n) < 9.95 then return ("%.1f"):format(n) end
  return ("%d"):format(math.floor(math.abs(n) + 0.5) * (n < 0 and -1 or 1))
end
-- "+14", "+3.5"
function S.DeltaText(n)
  n = tonumber(n) or 0
  return (n >= 0 and "+" or "") .. S.Num(n)
end

local function sameItem(a, b) return a ~= nil and b ~= nil and a.id == b.id and (a.suffix or 0) == (b.suffix or 0) end

-------------------------------------------------------------------------------
-- One item against what is worn
-------------------------------------------------------------------------------
-- Returns
--   { pending = true }                                  the item's numbers are not here yet: no score
--   { never = true, why }                               this class can never use it
--   { usable = bool, locked = bool, lock, lockReason,   usable now, or held back and why ("At level 17")
--     score, hasEffect,
--     slot = "legs", slotId = 7,                        where it would go
--     worn = the score of what it would replace (0 for an empty slot), replaces = that item or nil,
--     pair = true                                       (a two-hander: worn is the main hand and the off hand together)
--     delta = score - worn (nil: no verdict, see below), upgrade = bool (delta of S.MIN_DELTA or more, and not `same`),
--     same = true                                       the very item is already worn
--     vsTwoHand = true                                  a one-hand weapon weighed against a worn two-hander alone
--     noVerdict = "twohand"                             an off-hand item while a two-hander is worn: nothing to compare with }
-- Rules (spec section 3): a ring or a trinket replaces the weaker of the two worn; an empty slot gives the full score; a
-- two-hander is weighed against the main hand and the off hand together; a one-hand weapon goes where the gain is bigger for a
-- class that can hold two.
function S.Compare(item, ctx)
  if type(item) ~= "table" then return nil end
  if item.pending then return { pending = true } end
  local weights = ctx.stats
  if not (weights and item.slot and R.GOES_IN[item.slot]) then return nil end
  local usable, lock = S.CanUse(ctx.class, item, ctx.level, ctx.trained)
  if lock and lock.never then return { never = true, why = lock.why, usable = false } end
  local res = { usable = usable, locked = not usable, lock = lock, lockReason = S.LockText(lock), hasEffect = item.effect and true or false,
    upgrade = false }
  local worn = ctx.equipped or {}
  local slotKey = R.GOES_IN[item.slot]
  local function wornScore(sid) return worn[sid] and S.Score(worn[sid], weights, sid == OFF) or 0 end
  for _, wi in pairs(worn) do
    if sameItem(wi, item) then res.same = true break end
  end

  local best
  local function option(sid, score, had, extra)
    local o = { slotId = sid, score = score, worn = had, delta = had and (score - had) or nil, replaces = worn[sid] }
    for k, v in pairs(extra or {}) do o[k] = v end
    if not best or (o.delta or -math.huge) > (best.delta or -math.huge) then best = o end
  end

  if slotKey == "mainhand" then
    local score = S.Score(item, weights, false)
    if isTwoHand(item) then
      option(MAIN, score, wornScore(MAIN) + wornScore(OFF), { pair = worn[OFF] ~= nil or nil })
    else
      option(MAIN, score, wornScore(MAIN), { vsTwoHand = isTwoHand(worn[MAIN]) or nil })
      -- a plain one-hand weapon can also go in the off hand of a class that holds two (at the level the item can be worn)
      local at = math.max(ctx.level or 1, lock and lock.level or 0)
      if item.slot == INV.ONE_HAND and S.DualWield(ctx.class, at) and not isTwoHand(worn[MAIN]) then
        option(OFF, S.Score(item, weights, true), wornScore(OFF))
      end
    end
  elseif slotKey == "offhand" then
    local score = S.Score(item, weights, true)
    if isTwoHand(worn[MAIN]) then
      best = { slotId = OFF, score = score, noVerdict = "twohand" }
    else
      option(OFF, score, wornScore(OFF))
    end
  else
    local score = S.Score(item, weights, false)
    local ids = S.SLOTS[slotKey].ids
    -- the weaker of the places it can go: an empty place first
    local sid, had
    for _, id in ipairs(ids) do
      local ws = wornScore(id)
      if worn[id] == nil then ws = -1 end
      if had == nil or ws < had then sid, had = id, ws end
    end
    option(sid, score, math.max(had, 0))
  end

  for k, v in pairs(best) do res[k] = v end
  res.slot = S.SLOT_OF_ID[res.slotId]
  if res.same then res.delta = 0 end
  res.upgrade = (not res.same) and res.delta ~= nil and res.delta >= S.MIN_DELTA
  return res
end

-------------------------------------------------------------------------------
-- Filters and ranking
-------------------------------------------------------------------------------
-- The order sources are preferred in when one item comes from several: a sure thing before a drop, a drop before a price.
S.SOURCE_ORDER = { quest = 1, vendor = 2, favor = 3, crafted = 4, dungeon = 5, raid = 6, auction = 7 }

local function sourceBefore(a, b)
  local oa, ob = S.SOURCE_ORDER[a.kind] or 99, S.SOURCE_ORDER[b.kind] or 99
  if oa ~= ob then return oa < ob end
  if (a.chance or 0) ~= (b.chance or 0) then return (a.chance or 0) > (b.chance or 0) end
  if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
  return tostring(a.id or a.name or "") < tostring(b.id or b.name or "")
end
S.SourceBefore = sourceBefore

-- Does the filter let this item's static facts through? (level window, slot, source kind, price). ctx gives the gold.
-- Returns true, or false and which rule said no.
function S.Passes(item, source, price, ctx, filter)
  filter = filter or {}
  local req = item.req or 0
  if filter.minLevel and req < filter.minLevel then return false, "minLevel" end
  if filter.maxLevel and req > filter.maxLevel then return false, "maxLevel" end
  if filter.sources and not (source and filter.sources[source.kind]) then return false, "sources" end
  if filter.slots then
    local key = R.GOES_IN[item.slot or 0]
    if not (key and (filter.slots[key] or (key == "mainhand" and item.slot == INV.ONE_HAND and filter.slots.offhand))) then return false, "slots" end
  end
  if price then
    if filter.maxPrice and price > filter.maxPrice then return false, "maxPrice" end
    if filter.affordableOnly and price > (ctx.gold or 0) then return false, "affordableOnly" end
  end
  return true
end

-- A source record may say `fromLevel`: the level its quest opens at or its dungeon comes into range. An item whose every source
-- opens later than the character's level is listed as held back ("At level 20") even when the item itself could be worn now,
-- so "the best piece now" means the same on every page however far ahead that page looks.
-- raw candidates { item, source, price } -> one entry per item { item, source (the primary one), secondary = { ... }, price
-- (the lowest), pending }, with the static filters applied.
function S.Merge(raw, ctx, filter, tick)
  local out, by = {}, {}
  local pending = 0
  for _, c in ipairs(raw) do
    if tick then tick() end
    local item = c.item
    if type(item) == "table" then
      if item.pending then
        if not by[item] then by[item] = true pending = pending + 1 end
      elseif S.Passes(item, c.source, c.price, ctx, filter) then
        local key = tostring(item.id) .. ":" .. tostring(item.suffix or 0)
        local e = by[key]
        if not e then
          e = { item = item, sources = {} }
          by[key] = e
          out[#out + 1] = e
        end
        if c.source then
          local s = c.source
          if c.price and s.price == nil then s.price = c.price end
          e.sources[#e.sources + 1] = s
        end
        if c.price and (e.price == nil or c.price < e.price) then e.price = c.price end
      end
    end
  end
  local level = ctx.level or 0
  for _, e in ipairs(out) do
    -- a source the character can go to now before one that opens later (a quest for a higher level, a dungeon not yet in
    -- range); the item can be had from the level its earliest source opens at
    local at
    for _, s in ipairs(e.sources) do
      local from = s.fromLevel or 0
      if at == nil or from < at then at = from end
    end
    e.availableAt = at or 0
    table.sort(e.sources, function(a, b)
      local la, lb = (a.fromLevel or 0) > level, (b.fromLevel or 0) > level
      if la ~= lb then return not la end
      return sourceBefore(a, b)
    end)
    e.source = e.sources[1]
    e.secondary = {}
    for i = 2, #e.sources do e.secondary[#e.secondary + 1] = e.sources[i] end
    e.sources = nil
  end
  return out, pending
end

-- unlocked before locked; the bigger gain first; then the bigger score; then the lower item id (so the order never jumps and
-- every page names the same best item)
local function candidateBefore(a, b)
  if a.locked ~= b.locked then return not a.locked end
  local da, db = a.delta or -math.huge, b.delta or -math.huge
  if da ~= db then return da > db end
  if a.score ~= b.score then return a.score > b.score end
  if a.itemID ~= b.itemID then return a.itemID < b.itemID end
  return (a.suffix or 0) < (b.suffix or 0)
end
S.CandidateBefore = candidateBefore

local function candidate(e, cmp)
  local it = e.item
  return { itemID = it.id, link = it.link or ("item:" .. tostring(it.id)), name = it.name, quality = it.quality, item = it, suffix = it.suffix,
    slot = cmp.slot, slotId = cmp.slotId, score = cmp.score, delta = cmp.delta, worn = cmp.worn, replaces = cmp.replaces,
    upgrade = cmp.upgrade, hasEffect = cmp.hasEffect, requiredLevel = it.req or 0, locked = cmp.locked, lockReason = cmp.lockReason,
    lock = cmp.lock, sourceLocked = cmp.sourceLocked, pair = cmp.pair, vsTwoHand = cmp.vsTwoHand, noVerdict = cmp.noVerdict,
    source = e.source, secondarySources = e.secondary, price = e.price }
end

-- Rank one pool (merged entries that go in the same slot or pair of hands) against what is worn.
-- Returns { [slot key] = { candidates, ranked } } for the slots of that pool.
local function rankPool(entries, ctx, filter, tick)
  local bySlot = {}
  for _, e in ipairs(entries) do
    if tick then tick() end
    local cmp = S.Compare(e.item, ctx)
    if cmp and not cmp.never and not cmp.pending and not cmp.same then
      -- wearable now, but nowhere to get it yet: held back until its first source opens, with the same words
      if (e.availableAt or 0) > (ctx.level or 0) then
        local lock = cmp.lock or {}
        lock.level = math.max(lock.level or 0, e.availableAt)
        cmp.lock, cmp.locked, cmp.usable, cmp.sourceLocked = lock, true, false, true
        cmp.lockReason = S.LockText(lock)
      end
      local keep = true
      if cmp.locked then
        if not filter.includeLocked then keep = false end
        -- wearable only after the window the page asked for: not a candidate at all
        if keep and filter.maxLevel and cmp.lock and cmp.lock.level and cmp.lock.level > filter.maxLevel then keep = false end
      end
      if keep and cmp.slot and (not filter.slots or filter.slots[cmp.slot]) then
        local list = bySlot[cmp.slot]
        if not list then list = {} bySlot[cmp.slot] = list end
        list[#list + 1] = candidate(e, cmp)
      end
    end
  end
  -- A two-hander is worn: a one-hand weapon and an off-hand item are weighed as the best pair on offer against it
  -- ("the best one-hand + off-hand pair available").
  local main = ctx.equipped and ctx.equipped[MAIN]
  if isTwoHand(main) and (bySlot.mainhand or bySlot.offhand) then
    local had = S.Score(main, ctx.stats, false)
    local function top(list, want)
      local best
      for _, c in ipairs(list or {}) do
        if not c.locked and want(c) and (not best or c.score > best.score or (c.score == best.score and c.itemID < best.itemID)) then best = c end
      end
      return best
    end
    local bestOff = top(bySlot.offhand, function() return true end)
    local bestOne = top(bySlot.mainhand, function(c) return c.vsTwoHand end)
    for _, c in ipairs(bySlot.mainhand or {}) do
      if c.vsTwoHand and bestOff then
        c.delta, c.worn, c.pairedWith = c.score + bestOff.score - had, had, bestOff.item
        c.upgrade = c.delta >= S.MIN_DELTA
      end
    end
    for _, c in ipairs(bySlot.offhand or {}) do
      if c.noVerdict and bestOne then
        c.delta, c.worn, c.pairedWith, c.replaces = c.score + bestOne.score - had, had, bestOne.item, main
        c.upgrade = c.delta >= S.MIN_DELTA
      end
    end
  end
  local limit = filter.limitPerSlot or S.DEFAULT_LIMIT
  for _, list in pairs(bySlot) do
    table.sort(list, candidateBefore)
    for i = #list, limit + 1, -1 do list[i] = nil end
    for _, c in ipairs(list) do
      local _, bd = S.Score(c.item, ctx.stats, c.slotId == OFF, true)
      c.breakdown = bd
    end
  end
  return bySlot
end

-- what is worn in a slot, as a page shows it: the item a candidate would replace (the weaker ring or trinket), its score,
-- and every item worn in the slot's places
local function wornOf(slotKey, ctx)
  local worn = ctx.equipped or {}
  local out = { items = {} }
  local weakest, any, empty = nil, false, false
  for _, id in ipairs(S.SLOTS[slotKey].ids) do
    local it = worn[id]
    if it then
      any = true
      local sc = S.Score(it, ctx.stats, id == OFF)
      out.items[#out.items + 1] = { slotId = id, item = it, score = sc }
      if not weakest or sc < weakest.score then weakest = { item = it, score = sc, slotId = id } end
    else
      empty = true
    end
  end
  if any and not empty then out.item, out.score, out.slotId = weakest.item, weakest.score, weakest.slotId end
  out.empty = empty
  return out
end
S.WornOf = wornOf

-- The best candidates per slot. raw: { { item, source, price }, ... } from the sources. tick (optional) is called once per
-- item looked at, so the caller can spread a big list over several frames; it is the only thing here that is not a plain sum.
-- Returns { [slot key] = { slot, label, slotIds, worn = the item a candidate would replace (nil: a place is empty),
--   wornScore, wornItems = { { slotId, item, score }, ... }, candidates = { ...ranked } }, ... }
-- plus two fields beside the slots: `pending` (items whose numbers the game has not sent yet) and `pools` (kept so one slot
-- can be ranked again when what is worn there changes: S.Rerank).
function S.BestPerSlot(raw, ctx, filter, tick)
  filter = filter or {}
  local merged, pending = S.Merge(raw, ctx, filter, tick)
  local pools = {}
  for _, e in ipairs(merged) do
    local key = R.GOES_IN[e.item.slot or 0]
    if key then
      local p = poolOf(key)
      local list = pools[p]
      if not list then list = {} pools[p] = list end
      list[#list + 1] = e
    end
  end
  local out = { pending = pending, pools = pools }
  for _, key in ipairs(S.SLOT_ORDER) do
    if not filter.slots or filter.slots[key] then
      local s = S.SLOTS[key]
      out[key] = { slot = key, label = s.label, slotIds = s.ids, candidates = {} }
    end
  end
  local done = {}
  for _, key in ipairs(S.SLOT_ORDER) do
    local p = poolOf(key)
    if not done[p] then
      done[p] = true
      S.Rerank(out, p, ctx, filter, tick)
    end
  end
  return out
end

-- Rank one pool of a result again (what is worn in its slots changed): only those slots are touched.
function S.Rerank(result, pool, ctx, filter, tick)
  filter = filter or {}
  local ranked = rankPool(result.pools[pool] or {}, ctx, filter, tick)
  for _, key in ipairs(S.SLOT_ORDER) do
    if poolOf(key) == pool and result[key] then
      local w = wornOf(key, ctx)
      local e = result[key]
      e.worn, e.wornScore, e.wornItems, e.empty = w.item, w.score, w.items, w.empty
      e.candidates = ranked[key] or {}
    end
  end
  return result
end

-- 0.9.6: more candidates for a result already worked out (items the game named late, rows a source handed over later): they are
-- merged into its pools like the first ones (an item already there gets the new source beside its own) and only the pools they go
-- in are ranked again. raw as for BestPerSlot. Returns true when a pool changed.
function S.AddRaw(result, raw, ctx, filter, tick)
  filter = filter or {}
  local merged = S.Merge(raw, ctx, filter, tick)
  if #merged == 0 then return false end
  result.pools = result.pools or {}
  local touched = {}
  for _, e in ipairs(merged) do
    local key = R.GOES_IN[e.item.slot or 0]
    if key then
      local p = poolOf(key)
      local list = result.pools[p]
      if not list then list = {} result.pools[p] = list end
      local same
      for _, x in ipairs(list) do
        if x.item.id == e.item.id and (x.item.suffix or 0) == (e.item.suffix or 0) then same = x break end
      end
      if same then
        same.secondary = same.secondary or {}
        if e.source then same.secondary[#same.secondary + 1] = e.source end
        for _, s in ipairs(e.secondary or {}) do same.secondary[#same.secondary + 1] = s end
        if e.price and (same.price == nil or e.price < same.price) then same.price = e.price end
        if (e.availableAt or 0) < (same.availableAt or 0) then same.availableAt = e.availableAt end
      else
        list[#list + 1] = e
      end
      touched[p] = true
    end
  end
  local any = false
  for p in pairs(touched) do S.Rerank(result, p, ctx, filter, tick) any = true end
  return any
end

-- Every upgrade of a BestPerSlot result as one flat list, the biggest gain first (what can be worn now before what is held
-- back).
function S.Upgrades(best)
  local out = {}
  for _, key in ipairs(S.SLOT_ORDER) do
    for _, c in ipairs(best[key] and best[key].candidates or {}) do
      if c.upgrade then out[#out + 1] = c end
    end
  end
  table.sort(out, candidateBefore)
  return out
end
