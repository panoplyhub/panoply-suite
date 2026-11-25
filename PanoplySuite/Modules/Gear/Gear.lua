-- Panoply Suite gear engine, part 3: Panoply.Gear, the one engine every page asks (docs/specs/page-redesigns-04-gear-engine.md).
-- Pages call only these (section 5 of the spec):
--   Panoply.Gear:GetContext(characterKey)   -> ctx    who is asking: class, level, plan, weights, what is worn, training, gold
--   Panoply.Gear:Score(itemRef, ctx)        -> { score, breakdown, hasEffect, pending, delta, upgrade, slot, replaces, locked, ... }
--   Panoply.Gear:BestPerSlot(ctx, filter)   -> { [slot] = { worn, candidates = { ...ranked } } }
--   Panoply.Gear:Upgrades(ctx, filter)      -> a flat list, the biggest gain first, across slots
--   Panoply.Gear:Subscribe(callback)        -> callback(ctxKey, what) when results change ("changed", "progress", "done")
-- and, so every page says the same words: Panoply.Gear.DeltaText(n) ("+14"), Panoply.Gear:WeighedFor(ctx) ("Weighed for Beast Mastery
-- leveling"), Panoply.Gear.SourceText(source), Panoply.Gear:TipLine(itemRef). The lock words come with each candidate (lockReason).
--
-- characterKey: nil = the character being played. "Name-Realm" or { realm, name } = a saved character (the Muster cache;
-- its worn gear shows once that cache holds it). { class = "MAGE", level = 30 } = a what-if with nothing worn (At Your Level
-- looking at another level).
-- filter (all optional): minLevel, maxLevel (an item's required level), sources = { quest = true, ... }, maxPrice,
-- affordableOnly, includeLocked (keep what cannot be worn yet, marked "At level 17"), slots = { head = true, ... },
-- limitPerSlot (default 5).
-- Each candidate: itemID, link, name, quality, slot, slotId, score, delta, breakdown, hasEffect, requiredLevel, locked,
-- lockReason, source, secondarySources, price, replaces, upgrade.
--
-- When it works (spec section 7):
--   * A big list is worked out a slice at a time (a coroutine, about BUDGET_MS of engine work per frame). A call that cannot
--     finish in its first slice returns what it has, marked working = true with progress = 0..1, and tells its subscribers
--     when it is done; asking again then gives the finished result at once.
--   * Nothing is worked out in combat: what was worked out before stays as it is, and the rest waits for the fight to end.
--   * What changed decides what is worked out again: new gear in a slot ranks that slot again, nothing else.
--   * 0.9.6 ("the engine is constantly running over and over"): a result is worked out again only when something it reads has
--     changed. An event that says "maybe something changed" (a loading screen, the trainer, a talent window) rebuilds the
--     character, and a result whose inputs are the same as before (level, plan, talents, training, what is worn, quests handed in)
--     is kept. An item the game names late is filled into the results that were waiting for it, and only the slots it goes in are
--     ranked again: nothing starts over. An item the game says does not exist, or does not name after a few requests, is left out.
-- Reads only. It never equips, buys, picks or uses anything, and touches nothing protected.
local ADDON, Panoply = ...
local C = Panoply.Compat
local S, R, W, Src = Panoply.GearScore, Panoply.GearRules, Panoply.GearWeights, Panoply.GearSources

-- UI/Gear.lua (the settings panel every page shares) used this name until 0.9.5; it is Panoply.PageSettings now.
local Gear = { results = {}, verdicts = {}, items = {}, byId = {}, pendingItems = {}, tries = {}, asks = {}, gone = {}, subs = {}, jobs = {}, stamp = 0,
  uses = 0, questsDone = 0 }
Panoply.Gear = Gear

Gear.BUDGET_MS = 5          -- engine work per frame, about
Gear.TICKS_PER_SLICE = 250  -- used instead where the game has no fine clock
Gear.MAX_RESULTS = 12       -- results kept (the least recently asked for goes first)
Gear.ITEM_TRIES = 3         -- how often an item the game has no numbers for yet is asked again before it is taken as it is
Gear.ITEM_WAIT = 0.5        -- seconds after the game names an item before it is filled in (they come in bursts)
Gear.ITEM_ASKS = 3          -- how often the game is asked for an item it has not named before that item is left out

Gear.DeltaText, Gear.Num, Gear.SourceText = S.DeltaText, S.Num, Src.Text
Gear.SLOT_ORDER, Gear.SLOTS = S.SLOT_ORDER, S.SLOTS

-------------------------------------------------------------------------------
-- Reading an item (a link, an "item:..." string, an id, or an item table already read)
-------------------------------------------------------------------------------
local PRIMARY = { str = true, agi = true, sta = true, int = true, spi = true }
-- the keys of the game's own item stat table (GetItemStats) -> ours
Gear.GAME_STAT = {
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
}

local function split(s, sep)
  local out, pos = {}, 1
  while true do
    local a = s:find(sep, pos, true)
    if not a then out[#out + 1] = s:sub(pos) return out end
    out[#out + 1] = s:sub(pos, a - 1)
    pos = a + 1
  end
end

-- One record of the data add-on as an item, or nil. Decoded once per session.
-- The Gear table (PanoplySuite_QuestData/Gear/Gear.lua) has the fuller numbers; the loot tables (Loot/Loot.lua) know a few
-- items it does not, and on WoW Forever their `forever.items` records win.
Gear.decoded = setmetatable({}, { __mode = "v" })
local function fromLoot(id, raw)
  local f = split(raw, "|")
  local class, sub = tostring(f[4] or ""):match("^(%d+)%.(%d+)$")
  local it = { id = id, name = f[1], quality = tonumber(f[2]) or 1, slot = tonumber(f[3]) or 0, class = tonumber(class), sub = tonumber(sub),
    req = tonumber(f[5]) or 0, ilvl = tonumber(f[6]) or 0, mask = tonumber(f[7]), stats = {}, known = true, random = f[9] == "r" }
  for k, v in tostring(f[8] or ""):gmatch("(%a+):([%d%.]+)") do it.stats[k] = tonumber(v) end
  it.speed = it.stats.speed and it.stats.speed * 1000 or nil
  -- "block" there is a shield's block value, not the block chance the weights mean
  it.stats.speed, it.stats.block = nil, nil
  if it.mask == 0 then it.mask = nil end
  return it
end
local function fromGear(id, raw)
  local f = split(raw, "|")
  local it = { id = id, name = f[1], slot = tonumber(f[2]), class = tonumber(f[3]), sub = tonumber(f[4]), quality = tonumber(f[5]),
    req = tonumber(f[6]) or 0, ilvl = tonumber(f[7]) or 0, mask = tonumber(f[12]), stats = {}, known = true }
  if tonumber(f[8]) then it.stats.armor = tonumber(f[8]) end
  if tonumber(f[9]) then it.stats.dps = tonumber(f[9]) / 10 end
  it.speed = tonumber(f[10])
  for k, v in tostring(f[11] or ""):gmatch("(%a+):(%-?%d+)") do it.stats[k] = tonumber(v) end
  local flags = f[13] or ""
  -- an effect that is not in the stats, or a set bonus: scored on its plain stats and flagged
  if flags:find("e", 1, true) or flags:find("s", 1, true) then it.effect = true end
  if flags:find("u", 1, true) then it.unique = true end
  it.bind = tonumber(f[14])
  return it
end

function Gear:DataItem(id)
  if not id then return nil end
  local hit = Gear.decoded[id]
  if hit then return hit end
  local it
  local loot = Src.LootData()
  if loot and C.IsForever() and type(loot.forever) == "table" and type(loot.forever.items) == "table" and type(loot.forever.items[id]) == "string" then
    it = fromLoot(id, loot.forever.items[id])
  end
  local gd = Src.GearData()
  if not it and gd and type(gd.items[id]) == "string" then it = fromGear(id, gd.items[id]) end
  if not it and loot and type(loot.items) == "table" and type(loot.items[id]) == "string" then it = fromLoot(id, loot.items[id]) end
  if it and not R.GOES_IN[it.slot or 0] then it = nil end
  if it then Gear.decoded[id] = it end
  return it
end

local function statsFn() return C.G("C_Item.GetItemStats") or _G.GetItemStats end
function Gear.GameStats(item)
  local f = statsFn()
  if type(f) ~= "function" or item == nil then return nil end
  if type(item) == "number" then item = "item:" .. item end
  local ok, t = pcall(f, item)
  if not ok or type(t) ~= "table" then return nil end
  local out, any = {}, false
  for k, key in pairs(Gear.GAME_STAT) do
    local v = tonumber(C.Readable(t[k]))
    if v and v ~= 0 then out[key] = v any = true end
  end
  return any and out or nil
end

-- A link with a random suffix ("of the Bear") carries stats the base item does not.
local function suffixOf(link)
  if type(link) ~= "string" then return nil end
  local s = link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)")
  s = tonumber(s)
  return s and s ~= 0 and s or nil
end

-- ask the game to send an item's numbers (it answers with GET_ITEM_INFO_RECEIVED). Asked once while an answer is awaited, and at
-- most ITEM_ASKS times in all (the game answers a request for an item it already has, and an item it never names would otherwise
-- be asked for again on every answer). Returns false when the item is not asked for any more.
function Gear:RequestItem(id)
  if not id then return false end
  if self.pendingItems[id] then return true end
  local n = (self.asks[id] or 0) + 1
  if n > Gear.ITEM_ASKS then return false end
  self.asks[id] = n
  self.pendingItems[id] = true
  local f = C.G("C_Item.RequestLoadItemDataByID")
  if type(f) == "function" then pcall(f, id) end
  return true
end

Gear.MAX_ITEMS = 8000      -- items kept read (an auction scan reads thousands); past this the store starts over
-- (0.9.6: only a new item counts, and starting over forgets what was read, never how often an item was asked for: before, an
-- evening's reading passed the limit again and again, and every time the items that had been waited for were asked for again)
local function remember(ref, id, it)
  if Gear.items[ref] == nil then
    Gear.itemCount = (Gear.itemCount or 0) + 1
    if Gear.itemCount > Gear.MAX_ITEMS then Gear.items, Gear.byId, Gear.itemCount = {}, {}, 1 end
  end
  Gear.items[ref] = it
  local list = Gear.byId[id]
  if not list then list = {} Gear.byId[id] = list end
  list[ref] = true
end

-- The item, nil when it is not gear, or { id, pending = true } while the game has not sent its numbers: an item is never
-- scored on part of its numbers.
function Gear:Item(ref)
  if ref == nil then return nil end
  if type(ref) == "table" then return ref end
  local hit = Gear.items[ref]
  if hit ~= nil then return hit or nil end
  local id = C.ItemIDFromLink(ref)
  if not id then return nil end
  local base = self:DataItem(id)
  local info = C.ItemInfo(ref)
  local it
  if base then
    it = { stats = {} }
    for k, v in pairs(base) do if k ~= "stats" then it[k] = v end end
    for k, v in pairs(base.stats) do it.stats[k] = v end
  elseif info then
    local slot = R.EQUIP_LOC[info.equipLoc or ""]
    if not slot then remember(ref, id, false) return nil end
    it = { id = id, slot = slot, class = tonumber(info.classID), sub = tonumber(info.subclassID), quality = tonumber(info.quality),
      req = tonumber(info.minLevel) or 0, ilvl = tonumber(info.ilvl) or 0, stats = {} }
  else
    -- not in our data and not cached by the game yet: ask for it, and say so. One the game says does not exist, or has not named
    -- after ITEM_ASKS requests, is left out (it is not remembered: if the game names it later after all, it is read then).
    if self.gone[id] or not self:RequestItem(id) then return nil end
    return { id = id, pending = true }
  end
  if info then
    it.name = info.name or it.name
    it.link = info.link or (type(ref) == "string" and ref:find("|H", 1, true) and ref) or nil
    it.quality = tonumber(info.quality) or it.quality
    it.bind = tonumber(info.bindType) or it.bind
    if tonumber(info.setID) and tonumber(info.setID) ~= 0 then it.effect = true end
  end
  it.suffix = suffixOf(type(ref) == "string" and ref or nil)
  -- the game's own numbers: they win for armor and weapon damage, and a random suffix's stats come only from them
  local game = Gear.GameStats(type(ref) == "string" and ref or id)
  if game then
    for k, v in pairs(game) do
      if PRIMARY[k] then it.stats[k] = math.max(it.stats[k] or 0, v)
      elseif it.stats[k] == nil or k == "armor" or k == "dps" then it.stats[k] = v end
    end
  elseif (not base or it.suffix) and type(statsFn()) == "function" and (it.class == 2 or (it.class == 4 and (it.sub or 0) >= 1) or it.suffix) then
    -- the game knows the item but has not said its numbers yet (every weapon and piece of armor has some): wait for them,
    -- a few times at most
    local n = (self.tries[ref] or 0) + 1
    self.tries[ref] = n
    if n <= Gear.ITEM_TRIES then
      if not self.pendingItems[id] then self:RequestItem(id) end
      -- and look again a moment later in case the game sends no event for it
      if not self.retryWait then
        self.retryWait = true
        C.After(Gear.ITEM_WAIT * 4, function() self.retryWait = false self:OnItemInfo(nil, true) end)
      end
      return { id = id, pending = true, name = it.name }
    end
  end
  if not base and it.effect == nil then
    -- an item our data does not know: a "Use:" effect shows as the item's spell
    local gis = C.G("C_Item.GetItemSpell") or _G.GetItemSpell
    if type(gis) == "function" then
      local ok, spell = pcall(gis, type(ref) == "string" and ref or id)
      if ok and C.Readable(spell) ~= nil then it.effect = true end
    end
  end
  remember(ref, id, it)
  return it
end

-- forget what was read of one item (the game has just named it), or of every item. How often an item was waited for is kept
-- (0.9.6: forgetting it here let an item whose numbers never come be waited for again on every answer, without end).
function Gear:ForgetItem(id)
  if id == nil then
    Gear.items, Gear.byId, Gear.itemCount = {}, {}, 0
    return
  end
  for ref in pairs(Gear.byId[id] or {}) do Gear.items[ref] = nil end
  Gear.byId[id] = nil
end

-------------------------------------------------------------------------------
-- The character (ctx)
-------------------------------------------------------------------------------
local WORN_IDS = {}
for _, s in ipairs(R.SLOTS) do for _, id in ipairs(s[3]) do WORN_IDS[#WORN_IDS + 1] = id end end

-- the keys of a set, sorted, as one string ("*" for no set)
local function setSig(t)
  if type(t) ~= "table" then return "*" end
  local keys = {}
  for k, v in pairs(t) do if v then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  return table.concat(keys, ",")
end

local function wornLinks()
  local out = {}
  local f = _G.GetInventoryItemLink
  if type(f) == "function" then
    for _, sid in ipairs(WORN_IDS) do
      local ok, link = pcall(f, "player", sid)
      link = ok and C.Readable(link) or nil
      if type(link) == "string" then out[sid] = link end
    end
  end
  return out
end

-- the weapon skills the character has trained: { [weapon subclass] = true }, or nil when the game lists no weapon skill at
-- all (then nothing is held back for training)
function Gear:Trained()
  local ok, skills = pcall(C.GetSkills)
  if not ok or type(skills) ~= "table" then return nil end
  local byLine, byName = {}, {}
  for sub, ws in pairs(R.WEAPON_SKILL) do byLine[ws[2]] = sub byName[ws[1]] = sub end
  local out, any = {}, false
  for _, s in ipairs(skills) do
    local sub = (s.skillLineID and byLine[s.skillLineID]) or (type(s.name) == "string" and byName[s.name]) or nil
    if sub then out[sub] = true any = true end
  end
  return any and out or nil
end

-- the plan the character follows in Class & Spec, as the weights need it: { key, from, name, topTree } or nil
local function trackedPlan(class)
  local ST = Panoply.SpecTrainer
  if not (ST and ST.Tracked) then return nil end
  local ok, plan = pcall(ST.Tracked, ST)
  if not ok or type(plan) ~= "table" then return nil end
  local top
  if type(plan.points) == "table" and ST.RanksAt then
    local ok2, _, spent = pcall(ST.RanksAt, ST, class, plan.points)
    if ok2 and type(spent) == "table" then
      local best = 0
      for i, n in ipairs(spent) do if n > best then best, top = n, i end end
    end
  end
  return { key = plan.key, from = plan.from, name = plan.name, topTree = top }
end

-- the talent tree the character has the most points in, when it has spent any
local function liveTree(class)
  local ST = Panoply.SpecTrainer
  if not (ST and ST.LiveRanks) then return nil end
  local ok, _, spent = pcall(ST.LiveRanks, ST, class)
  if not ok or type(spent) ~= "table" then return nil end
  local best, top = 0, nil
  for i, n in ipairs(spent) do if n > best then best, top = n, i end end
  return top
end

-- The weights for a class: its plan when it has one (spec 2.1), else the tree its talent points are in, else the class
-- default. Sets ctx.plan, ctx.table, ctx.stats, ctx.planName and ctx.from ("own" | "plan" | "copied" | "tree" | "talents" |
-- "default").
local function weigh(ctx, plan, tree)
  local tbl, how
  if plan then
    tbl, how = S.ForPlan(ctx.class, plan)
    ctx.plan = plan
    if how == "default" then ctx.planName = tbl and (tbl.name .. " (default)") else ctx.planName = plan.name or (tbl and tbl.name) end
  elseif tree and S.Table(ctx.class, tree) then
    tbl, how = S.Table(ctx.class, tree), "talents"
    ctx.planName = tbl.name
  else
    tbl, how = S.ForPlan(ctx.class, nil)
    ctx.planName = tbl and (tbl.name .. " (default)") or nil
  end
  ctx.table, ctx.from = tbl, how
  ctx.stats = tbl and S.Weights(tbl, ctx.level) or nil
  ctx.weighedFor = ctx.planName and ("Weighed for " .. ctx.planName) or nil
end

local function versionStamp() return tostring(W.version) .. "." .. tostring(R.version) end

-- ctx.scores[inventory slot id] = what the worn piece is worth to the plan (spec 2.1: item, link and score per slot)
local function scoreWorn(ctx)
  ctx.scores = {}
  for sid, it in pairs(ctx.equipped or {}) do ctx.scores[sid] = ctx.stats and S.Score(it, ctx.stats, sid == 17) or 0 end
end

function Gear:LiveContext()
  if self.live then return self.live end
  local info = C.PlayerInfo() or {}
  local ctx = { key = "player", me = true, class = info.classFile, classID = info.classID, race = info.raceFile, raceID = info.raceID,
    faction = info.faction, name = info.name, realm = info.realm, level = tonumber((C.XP())) or 1 }
  if self.levelUp then
    if self.levelUp > ctx.level then ctx.level = self.levelUp else self.levelUp = nil end
  end
  weigh(ctx, trackedPlan(ctx.class), liveTree(ctx.class))
  ctx.links = wornLinks()
  ctx.equipped = {}
  for sid, link in pairs(ctx.links) do
    local it = self:Item(link)
    if it and not it.pending then ctx.equipped[sid] = it elseif it then ctx.wornPending = true end
  end
  scoreWorn(ctx)
  ctx.trained = self:Trained()
  ctx.proficiencies = { rules = R.classes[ctx.class or ""], trained = ctx.trained, dualWield = S.DualWield(ctx.class, ctx.level) }
  ctx.gold = C.Money()
  ctx.done = function(qid)
    local St = Panoply.State
    if St and type(St.completed) == "table" and St.completed[qid] then return true end
    return C.IsQuestCompleted(qid) and true or false
  end
  self.stamp = self.stamp + 1
  ctx.stamp = self.stamp .. "/" .. versionStamp()
  ctx.inputSig = self:InputSig(ctx)
  self.live = ctx
  return ctx
end

-- Everything about the character a result depends on, as one string (0.9.6): when a rebuilt character has the same, the results
-- worked out for the old one still hold. Gold is not in it (only "Only what I can afford" reads gold: OnMoney), nor a source's
-- rows (SourceChanged, AddCandidates); which sources are on is (raids open on a date on WoW Forever, a data table appears).
function Gear:InputSig(ctx)
  local plan = ctx.plan
  local on = {}
  for _, def in ipairs(Src.list) do
    local ok, yes = pcall(def.available, ctx)
    on[#on + 1] = (ok and yes) and "1" or "0"
  end
  local parts = { versionStamp(), tostring(ctx.class), tostring(ctx.level), tostring(ctx.planName), tostring(ctx.from),
    tostring(plan and plan.key), tostring(plan and plan.topTree), setSig(ctx.trained), tostring(self.questsDone), tostring(ctx.wornPending),
    table.concat(on) }
  for _, sid in ipairs(WORN_IDS) do parts[#parts + 1] = tostring(ctx.links and ctx.links[sid] or "") end
  return table.concat(parts, "|")
end

-- a saved character (the Muster cache, Modules/Alts): its class, level and gold; its worn gear and plan once the cache
-- holds them (rec.gear = { [inventory slot id] = link or item id }, rec.plan = { key, from, name, topTree })
local function savedContext(self, realm, name)
  local A = Panoply.Alts
  local rec = A and A.Rec and A:Rec(realm, name)
  if type(rec) ~= "table" or not rec.classFile then return nil end
  local rules = R.classes[rec.classFile]
  local ctx = { key = "saved:" .. realm .. "\1" .. name, saved = true, class = rec.classFile, classID = rules and rules.id, race = rec.raceFile,
    faction = rec.faction, name = name, realm = realm, level = tonumber(rec.level) or 1, gold = tonumber(rec.money) or 0, side = false }
  weigh(ctx, type(rec.plan) == "table" and rec.plan or nil, nil)
  ctx.equipped = {}
  if type(rec.gear) == "table" then
    for sid, ref in pairs(rec.gear) do
      local it = self:Item(ref)
      if it and not it.pending then ctx.equipped[sid] = it elseif it then ctx.wornPending = true end
    end
  else
    ctx.noGear = true     -- the cache does not hold this character's worn gear (yet)
  end
  scoreWorn(ctx)
  ctx.proficiencies = { rules = rules, dualWield = S.DualWield(ctx.class, ctx.level) }
  ctx.done = function() return false end
  ctx.stamp = "s" .. tostring(rec.t or 0) .. "/" .. versionStamp()
  return ctx
end

function Gear:GetContext(characterKey)
  local me = C.PlayerInfo() or {}
  if characterKey == nil or characterKey == "player" then return self:LiveContext() end
  if type(characterKey) == "string" then
    local name, realm = characterKey:match("^([^%-]+)%-(.+)$")
    if not name then name, realm = characterKey, me.realm end
    characterKey = { realm = realm, name = name }
  end
  if type(characterKey) ~= "table" then return nil end
  if characterKey.name then
    if characterKey.name == me.name and (characterKey.realm == nil or characterKey.realm == me.realm) then return self:LiveContext() end
    return savedContext(self, characterKey.realm or me.realm, characterKey.name)
  end
  -- a what-if: a class at a level, nothing worn. The player's own class is weighed with the player's own plan.
  local class = characterKey.class and tostring(characterKey.class):upper()
  local rules = class and R.classes[class]
  if not rules then return nil end
  local level = tonumber(characterKey.level) or 1
  local ctx = { key = "view:" .. class .. ":" .. level .. ":" .. tostring(characterKey.raceID or ""), view = true, class = class, classID = rules.id,
    raceID = characterKey.raceID, faction = characterKey.faction or me.faction, level = level, equipped = {}, gold = 0,
    scores = {}, done = characterKey.done or function() return false end }
  if class == me.classFile then weigh(ctx, trackedPlan(class), liveTree(class)) else weigh(ctx, nil, nil) end
  ctx.proficiencies = { rules = rules, dualWield = S.DualWield(class, level) }
  -- (0.9.6: the stamp no longer counts every rebuild of the player's own character: a what-if has nothing worn, so only its plan,
  -- the quests handed in and the data can change what it is worth)
  ctx.stamp = "v" .. versionStamp() .. tostring(ctx.planName) .. "/" .. tostring(self.questsDone) .. (characterKey.done and tostring(characterKey.done) or "")
  return ctx
end

-- What is worn in one inventory slot and what it is worth to the plan: item, score (nil, 0 for an empty slot).
function Gear:Worn(ctx, slotId)
  ctx = ctx or self:GetContext()
  local it = ctx and ctx.equipped and ctx.equipped[slotId]
  if not it then return nil, 0 end
  return it, (ctx.stats and S.Score(it, ctx.stats, slotId == 17)) or 0
end

-- Throw away everything worked out and everything read (the tests; a data add-on that loaded late).
function Gear:Reset()
  self:ForgetItem(nil)
  Gear.decoded = setmetatable({}, { __mode = "v" })
  self.pendingItems, self.tries, self.asks, self.gone = {}, {}, {}, {}
  self.results, self.jobs = {}, {}
  self.afterCombat, self.dirtyAll, self.dirtyWorn = nil, nil, nil
  self.live, self.verdicts = nil, {}
  self:Notify("player", "changed")
end

-- The Class page's Talents tab is where the plan is picked (the "Weighed for" line links there). Until that page exists
-- (phase 4H) this opens Class & Spec on its plan.
function Gear:OpenPlan()
  local ST = Panoply.SpecTrainer
  -- 0.9.5 phase 4H: the plan lives on the Class page; its Talents tab shows it (spec 03 section 7: the plan name links to Talents)
  local CP = Panoply.ClassPages
  if CP and CP.Open then return CP:Open(nil, "talents") end
  if ST and ST.OpenClassSpec then return ST:OpenClassSpec("plan") end
  if Panoply.Menu and Panoply.Menu.Open then return Panoply.Menu:Open("class") end
end

-- "Strength 12 · Stamina 4 · Armor 3": the biggest parts of a score, for a tooltip (spec section 3: the top three)
function Gear.BreakdownText(result, n)
  local parts = {}
  for i, b in ipairs(result and result.breakdown or {}) do
    if i > (n or 3) then break end
    parts[#parts + 1] = (b.label or b.stat) .. " " .. S.Num(b.contribution)
  end
  return table.concat(parts, " \194\183 ")
end

-- "Weighed for Beast Mastery leveling" (the header line every gear page shows; it links to the Class page's Talents tab)
function Gear:WeighedFor(ctx)
  ctx = ctx or self:GetContext()
  return ctx and ctx.weighedFor or nil
end

-------------------------------------------------------------------------------
-- Subscribers
-------------------------------------------------------------------------------
function Gear:Subscribe(callback)
  if type(callback) ~= "function" then return nil end
  self.subs[#self.subs + 1] = callback
  return function()
    for i, f in ipairs(self.subs) do if f == callback then table.remove(self.subs, i) break end end
  end
end

function Gear:Notify(ctxKey, what, result)
  for _, f in ipairs({ unpack(self.subs) }) do
    local ok, err = pcall(f, ctxKey, what, result)
    if not ok then Panoply:Debug("gear subscriber:", err) end
  end
  Panoply:Fire("GEAR_CHANGED", ctxKey, what)
end

-------------------------------------------------------------------------------
-- One item (tooltips, bag marks)
-------------------------------------------------------------------------------
-- nil for what is not gear (or for a class with no weights). In combat only what was worked out before is given; the rest
-- is nil until the fight ends.
function Gear:Score(itemRef, ctx)
  ctx = ctx or self:GetContext()
  if not (ctx and ctx.stats) or itemRef == nil then return nil end
  local cache = self.verdicts[ctx.key]
  if not cache or cache.stamp ~= ctx.stamp then cache = { stamp = ctx.stamp, by = {} } self.verdicts[ctx.key] = cache end
  local key = type(itemRef) == "table" and (itemRef.link or itemRef.id) or itemRef
  local hit
  if key ~= nil then hit = cache.by[key] end
  if hit ~= nil then return hit or nil end
  if C.InCombat() then self.afterCombat = true return nil end
  local item = self:Item(itemRef)
  if not item then if key ~= nil then cache.by[key] = false end return nil end
  if item.pending then return { pending = true, score = 0, breakdown = {}, hasEffect = false } end
  local cmp = S.Compare(item, ctx)
  if not cmp then if key ~= nil then cache.by[key] = false end return nil end
  local score, bd = S.Score(item, ctx.stats, cmp.slotId == 17, true)
  cmp.score = cmp.score or score
  cmp.breakdown, cmp.item, cmp.pending = bd, item, false
  cmp.hasEffect = item.effect and true or false
  if key ~= nil then cache.by[key] = cmp end
  return cmp
end

-- The line an item's tooltip gets (spec section 6): "+14 for Beast Mastery leveling", "Not an upgrade", or nil for what the
-- character cannot use, already wears, or that is not gear. Returns the text and "upgrade" | "locked" | "not".
function Gear:TipLine(itemRef, ctx)
  ctx = ctx or self:GetContext()
  local v = self:Score(itemRef, ctx)
  if not v or v.pending or v.never or v.same or v.delta == nil then return nil end
  if v.upgrade then
    local text = S.DeltaText(v.delta) .. " for " .. (ctx.planName or "you")
    if v.locked and v.lockReason then return text .. " (" .. v.lockReason .. ")", "locked" end
    return text, "upgrade"
  end
  return "Not an upgrade", "not"
end

-------------------------------------------------------------------------------
-- Results: best per slot, upgrades
-------------------------------------------------------------------------------
local FILTER_KEYS = { "minLevel", "maxLevel", "maxPrice", "affordableOnly", "includeLocked", "limitPerSlot" }
function Gear.FilterKey(filter)
  filter = filter or {}
  local parts = {}
  for _, k in ipairs(FILTER_KEYS) do parts[#parts + 1] = tostring(filter[k]) end
  parts[#parts + 1] = setSig(filter.sources)
  parts[#parts + 1] = setSig(filter.slots)
  return table.concat(parts, "|")
end

local function copyFilter(filter)
  local out = {}
  for k, v in pairs(filter or {}) do
    if type(v) == "table" then local t = {} for a, b in pairs(v) do t[a] = b end out[k] = t else out[k] = v end
  end
  return out
end

function Gear.Clock()
  local f = _G.debugprofilestop
  if type(f) == "function" then return f() end
  return nil
end

-- the sources a filter lets through, split into the ones that have their data and the ones that do not
function Gear:SourcesFor(ctx, filter)
  local on, off = {}, {}
  for _, def in ipairs(Src.list) do
    if not filter.sources or filter.sources[def.kind] then
      local ok, yes = pcall(def.available, ctx)
      if ok and yes then on[#on + 1] = def else off[#off + 1] = def.kind end
    end
  end
  return on, off
end

-- the whole job, run inside a coroutine: every source, then the ranking. Yields when its slice of the frame is used up.
local function compute(self, e)
  local ctx, filter = e.ctx, e.filter
  local function tick()
    self.sliceTicks = self.sliceTicks + 1
    local now = Gear.Clock()
    local over
    if now and self.sliceStart then over = (now - self.sliceStart) >= Gear.BUDGET_MS
    else over = self.sliceTicks >= Gear.TICKS_PER_SLICE end
    if over and Gear.BUDGET_MS ~= math.huge then coroutine.yield() end
  end
  local raw, waiting = {}, {}
  local on, off = self:SourcesFor(ctx, filter)
  local used = {}
  e.collected = {}
  for i, def in ipairs(on) do
    used[def.kind] = true
    def.collect(ctx, filter, function(ref, source, price)
      local item = self:Item(ref)
      if item then
        raw[#raw + 1] = { item = item, source = source, price = price }
        -- an item the game has not named yet: kept, so it is filled in when it is named (nothing starts over for it)
        if item.pending then waiting[#waiting + 1] = { ref = ref, source = source, price = price, id = item.id } end
      end
    end, tick)
    e.collected[def.kind] = true
    e.progress = i / (#on + 1)
    tick()
  end
  local result = S.BestPerSlot(raw, ctx, filter, tick)
  result.waiting = waiting
  result.sources, result.sourcesOff = used, off
  result.weighedFor, result.ctxKey, result.stamp = ctx.weighedFor, ctx.key, ctx.stamp
  result.working, result.progress = false, 1
  return result
end

local function skeleton(ctx, filter)
  local r = S.BestPerSlot({}, ctx, filter)
  r.weighedFor, r.ctxKey, r.stamp, r.sources, r.sourcesOff = ctx.weighedFor, ctx.key, ctx.stamp, {}, {}
  return r
end

-- run one slice of a job. Returns true when the job is finished.
function Gear:Slice(e)
  self.sliceStart, self.sliceTicks = Gear.Clock(), 0
  local ok, res = coroutine.resume(e.co)
  if not ok then
    -- never loop on a broken job: say so in the debug log and give an empty result
    Panoply:Debug("gear engine:", res)
    e.error = tostring(res)
    res = skeleton(e.ctx, e.filter)
    res.error = e.error
  end
  if not ok or coroutine.status(e.co) == "dead" then
    res.working, res.progress = false, 1
    -- (a change that came while it ran keeps its dirty mark: the next ask starts over)
    e.result, e.co, e.progress = res, nil, 1
    for i, j in ipairs(self.jobs) do if j == e then table.remove(self.jobs, i) break end end
    -- rows a source handed over after this job had read it (AddCandidates), and items named while it ran
    if ok and e.later then
      local later = e.later
      e.later = nil
      local _, waiting = self:Fill(e, later)
      res.waiting = res.waiting or {}
      for _, w in ipairs(waiting) do res.waiting[#res.waiting + 1] = w end
      res.pending = (res.pending or 0) + #waiting
    end
    if ok and res.waiting and #res.waiting > 0 then self:ScheduleFill() end
    return true
  end
  return false
end

-- keep the jobs going, one slice a frame, never in combat
function Gear:Pump()
  if self.pumping or #self.jobs == 0 then return end
  if C.InCombat() then self.afterCombat = true return end
  self.pumping = true
  C.After(0, function()
    self.pumping = false
    local e = self.jobs[1]
    if not e then return end
    if C.InCombat() then self.afterCombat = true return end
    if self:Slice(e) then
      self:Notify(e.ctx.key, "done", e.result)
    else
      if e.shown then e.shown.progress = e.progress or 0 end
      self:Notify(e.ctx.key, "progress", e.shown)
    end
    self:Pump()
  end)
end

function Gear:BestPerSlot(ctx, filter)
  ctx = ctx or self:GetContext()
  if not ctx then return nil end
  filter = filter or {}
  if not ctx.stats then
    local r = skeleton(ctx, filter)
    r.noWeights = true
    return r
  end
  local key = ctx.key .. "#" .. Gear.FilterKey(filter)
  local e = self.results[key]
  self.uses = self.uses + 1
  if e then e.at = self.uses end
  -- 0.9.6: the character was rebuilt (an event said something might have changed) but nothing this result reads did: it still holds
  if e and e.stamp ~= ctx.stamp and not e.dirty and e.inputSig and e.inputSig == ctx.inputSig then
    e.ctx, e.stamp = ctx, ctx.stamp
    if e.result then e.result.stamp = ctx.stamp end
  end
  if e and e.stamp == ctx.stamp and not e.dirty then
    if e.result and not e.co then return e.result end
  else
    -- nothing yet, or what there is no longer holds: a new job (one already running for an older state is dropped)
    if e and e.co then for i, j in ipairs(self.jobs) do if j == e then table.remove(self.jobs, i) break end end end
    local old = e and e.result
    e = { key = key, ctx = ctx, filter = copyFilter(filter), stamp = ctx.stamp, inputSig = ctx.inputSig, at = self.uses, progress = 0, last = old }
    e.co = coroutine.create(function() return compute(self, e) end)
    self.results[key] = e
    self.jobs[#self.jobs + 1] = e
    -- keep the store small
    local n, oldest = 0, nil
    for _, x in pairs(self.results) do
      n = n + 1
      if not x.co and (not oldest or x.at < oldest.at) then oldest = x end
    end
    if n > Gear.MAX_RESULTS and oldest then self.results[oldest.key] = nil end
    if not C.InCombat() then
      -- the first slice now: a small job is finished before this call returns
      if self:Slice(e) then return e.result end
    end
  end
  -- still working (or waiting for a fight to end): what there was before, or the empty slots, marked
  local shown = e.last or e.shown or skeleton(ctx, filter)
  shown.working, shown.progress = true, e.progress or 0
  shown.queued = C.InCombat() or nil
  e.shown = shown
  if C.InCombat() then self.afterCombat = true else self:Pump() end
  return shown
end

-- Every upgrade as one flat list, the biggest gain first. Also returns the BestPerSlot result it came from (for `working`).
function Gear:Upgrades(ctx, filter)
  local best = self:BestPerSlot(ctx, filter)
  if not best then return {}, nil end
  return S.Upgrades(best), best
end

-- Finish every job now (the tests, and a page that must not show a half list). Never in combat.
function Gear:Finish()
  local guard = 0
  while #self.jobs > 0 and not C.InCombat() and guard < 100000 do
    guard = guard + 1
    local e = self.jobs[1]
    local budget = Gear.BUDGET_MS
    Gear.BUDGET_MS = math.huge
    local done = self:Slice(e)
    Gear.BUDGET_MS = budget
    if done then self:Notify(e.ctx.key, "done", e.result) end
  end
end

-------------------------------------------------------------------------------
-- When to work it out again (spec section 7)
-------------------------------------------------------------------------------
-- Everything about the character may have changed (level, plan, talents, training, a quest handed in): a new ctx. A result is
-- worked out again when it is next asked for only when what it reads is not the same any more (0.9.6: BestPerSlot compares the
-- inputs; before, every loading screen and every trainer or talent event threw every result away). Nobody is told unless the
-- character really changed.
function Gear:Invalidate(why)
  if C.InCombat() then self.afterCombat, self.dirtyAll = true, true return end
  local old = self.live
  self.live = nil
  if not old then self.verdicts = {} self:Notify("player", "changed") return end
  local ctx = self:LiveContext()
  if ctx.inputSig == old.inputSig then
    -- the same character: the item verdicts and the results carry over
    self.verdicts[ctx.key] = self.verdicts[old.key]
    if self.verdicts[ctx.key] then self.verdicts[ctx.key].stamp = ctx.stamp end
    for _, e in pairs(self.results) do
      if e.ctx == old then
        e.ctx, e.stamp = ctx, ctx.stamp
        if e.result then e.result.stamp = ctx.stamp end
      end
    end
    return
  end
  self.verdicts = {}
  for _, e in pairs(self.results) do
    if e.co and e.ctx == old then
      for i, j in ipairs(self.jobs) do if j == e then table.remove(self.jobs, i) break end end
      e.co = nil
      e.dirty = true
    end
  end
  self:Notify("player", "changed")
end

-- A source's data changed (an auction scan was read): only the results that used it are worked out again.
-- quiet: nobody is told (the source went away with the window that fed it).
function Gear:SourceChanged(kind, quiet)
  local any = false
  for _, e in pairs(self.results) do
    local r = e.result
    local uses = (r and r.sources and r.sources[kind]) or ((r or e.co) and (not e.filter.sources or e.filter.sources[kind]))
    if uses then e.dirty = true any = true end
  end
  if any and not quiet then self:Notify(nil, "changed") end
end

-- What is worn changed: the slots that changed are ranked again in every result of the character, nothing else.
-- pendingToo (0.9.6): also read again the slots whose piece the game had not sent the numbers of (they were named since); when
-- one of them is still waiting, nothing is ranked for it yet.
function Gear:OnEquipment(pendingToo)
  local ctx = self.live
  if not ctx then return end
  if C.InCombat() then self.afterCombat, self.dirtyWorn = true, true return end
  local links = wornLinks()
  local pools, any, wasPending = {}, false, ctx.wornPending
  if pendingToo then ctx.wornPending = nil end
  for _, sid in ipairs(WORN_IDS) do
    local changed = links[sid] ~= ctx.links[sid]
    local waited = pendingToo and links[sid] and not ctx.equipped[sid]
    if changed or waited then
      local it = links[sid] and self:Item(links[sid]) or nil
      if it and it.pending then ctx.wornPending = true end
      local now = (it and not it.pending) and it or nil
      if changed or now then
        any = true
        pools[S.PoolOf(S.SLOT_OF_ID[sid])] = true
        ctx.equipped[sid] = now
      end
    end
  end
  if not any then
    if pendingToo and wasPending ~= ctx.wornPending then
      ctx.inputSig = self:InputSig(ctx)
      for _, e in pairs(self.results) do if e.ctx == ctx then e.inputSig = ctx.inputSig end end
    end
    return
  end
  ctx.links = links
  scoreWorn(ctx)
  self.verdicts[ctx.key] = nil
  local oldSig = ctx.inputSig
  ctx.inputSig = self:InputSig(ctx)
  for _, e in pairs(self.results) do
    if e.ctx == ctx and e.stamp == ctx.stamp then
      if e.co or not e.result then
        e.dirty = true
      else
        for pool in pairs(pools) do S.Rerank(e.result, pool, ctx, e.filter) end
        if e.inputSig == oldSig then e.inputSig = ctx.inputSig end
      end
    elseif e.ctx ~= ctx and e.ctx and e.ctx.view then
      e.dirty = true
    end
  end
  self:Notify(ctx.key, "changed")
end

-------------------------------------------------------------------------------
-- Filling in (0.9.6): items the game names late, and rows a source hands over later, go into the results already worked out
-------------------------------------------------------------------------------
-- rows = { { ref, source, price }, ... } into one finished result: what is ready is merged into its slots and only those slots
-- are ranked again. Returns whether the result changed, and the rows still waiting (the caller keeps them for the next time).
function Gear:Fill(e, rows)
  local r = e.result
  if not (r and r.pools) then return false, rows end
  local ready, waiting = {}, {}
  for _, row in ipairs(rows) do
    local item = self:Item(row.ref)
    if item then
      if item.pending then waiting[#waiting + 1] = { ref = row.ref, source = row.source, price = row.price, id = item.id }
      else ready[#ready + 1] = { item = item, source = row.source, price = row.price } end
    end
  end
  local changed = false
  if #ready > 0 then changed = S.AddRaw(r, ready, e.ctx, e.filter) end
  return changed, waiting
end

-- Every finished result that was waiting for items: those the game has named since are filled in. Results being worked out pick
-- them up when they finish (Slice). Nobody is told when nothing changed.
function Gear:FillWaiting()
  for _, e in pairs(self.results) do
    local r = e.result
    if r and not e.co and r.waiting and #r.waiting > 0 then
      local changed, waiting = self:Fill(e, r.waiting)
      local was = r.pending or 0
      r.waiting = waiting
      local seen, n = {}, 0
      for _, w in ipairs(waiting) do if not seen[w.id or w.ref] then seen[w.id or w.ref] = true n = n + 1 end end
      r.pending = n
      if changed or n ~= was then
        self.fills = (self.fills or 0) + 1
        self:Notify(e.ctx.key, "done", r)
      end
    end
  end
end

-- one filling-in pass a moment from now (the game names items in bursts)
function Gear:ScheduleFill()
  if self.itemWait then return end
  self.itemWait = true
  C.After(Gear.ITEM_WAIT, function()
    self.itemWait = false
    if C.InCombat() then self.afterCombat, self.fillAfterCombat = true, true return end
    if self.live and self.live.wornPending then self:OnEquipment(true) end
    self:FillWaiting()
  end)
end

-- A source has new rows (an item of an auction scan the game has just named): they are added to every result that reads the
-- source, without working anything out again. rows = { { ref, source, price }, ... } as the source would have handed them over.
function Gear:AddCandidates(kind, rows)
  if type(rows) ~= "table" or #rows == 0 then return end
  for _, e in pairs(self.results) do
    local f = e.filter or {}
    if not f.sources or f.sources[kind] then
      if e.co then
        -- being worked out: a source it has read already gets the rows when it is done (one it has not read yet reads them itself)
        if e.collected and e.collected[kind] then
          e.later = e.later or {}
          for _, row in ipairs(rows) do e.later[#e.later + 1] = row end
        end
      elseif e.result and e.result.pools then
        local changed, waiting = self:Fill(e, rows)
        local r = e.result
        r.sources = r.sources or {}
        r.sources[kind] = true
        for i = #(r.sourcesOff or {}), 1, -1 do if r.sourcesOff[i] == kind then table.remove(r.sourcesOff, i) end end
        if #waiting > 0 then
          r.waiting = r.waiting or {}
          for _, w in ipairs(waiting) do r.waiting[#r.waiting + 1] = w end
          r.pending = (r.pending or 0) + #waiting
        end
        if changed then
          self.fills = (self.fills or 0) + 1
          self:Notify(e.ctx.key, "done", r)
        end
      end
    end
  end
end

-- The game has just named an item it did not know (success = false: it has no such item).
-- retry: a timed second look for items the game had not sent (nothing is forgotten but what is still waiting)
-- 0.9.6: an item nobody here waited for (chat links, tooltips, other add-ons) does nothing; one that was waited for is filled into
-- the results that wanted it, and the worn piece that waited is read again. Nothing is worked out again from the start.
function Gear:OnItemInfo(id, retry, success)
  id = tonumber(id)
  if id then
    local waited = self.pendingItems[id]
    self.pendingItems[id] = nil
    self:ForgetItem(id)
    if not waited then return end
    if success == false then self.gone[id] = true end
  elseif not retry then
    self:ForgetItem(nil)
  end
  self:ScheduleFill()
end

function Gear:OnMoney()
  local ctx = self.live
  if not ctx then return end
  local gold = C.Money()
  if gold == ctx.gold then return end
  ctx.gold = gold
  local any = false
  for _, e in pairs(self.results) do
    if e.ctx == ctx and e.filter.affordableOnly then e.dirty = true any = true end
  end
  if any then self:Notify(ctx.key, "changed") end
end

-- a weapon skill was learned (the only skill change that matters here)
function Gear:OnSkills()
  local ctx = self.live
  if not ctx then return end
  local now = self:Trained()
  local a, b = setSig(now), setSig(ctx.trained)
  if a ~= b then self:Invalidate("skills") end
end

function Gear:AfterCombat()
  if not self.afterCombat then return end
  self.afterCombat = false
  local all, worn, fill = self.dirtyAll, self.dirtyWorn, self.fillAfterCombat
  self.dirtyAll, self.dirtyWorn, self.fillAfterCombat = nil, nil, nil
  if all then self:Invalidate("combat")
  elseif worn then self:OnEquipment()
  else self:Notify("player", "changed") end
  if fill then self:ScheduleFill() end
  self:Pump()
end

-- (0.9.9.4 review: WoW Forever's trait tree events too, so a talent point spent there re-weighs the gear like Classic's event did)
for _, e in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
  Panoply:On(e, function() Gear:Invalidate(e) end)
end
-- a quest handed in: the quest rewards it offered are gone from what can be had (part of the inputs: InputSig)
Panoply:On("QUEST_TURNED_IN", function() Gear.questsDone = Gear.questsDone + 1 Gear:Invalidate("QUEST_TURNED_IN") end)
-- the game may still answer the old level while PLAYER_LEVEL_UP is being handled: the event's own level is used until it agrees
Panoply:On("PLAYER_LEVEL_UP", function(_, level) Gear.levelUp = tonumber(level) Gear:Invalidate("PLAYER_LEVEL_UP") end)
Panoply:On("PLAYER_EQUIPMENT_CHANGED", function() Gear:OnEquipment() end)
Panoply:On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == nil or unit == "player" then Gear:OnEquipment() end end)
Panoply:On("GET_ITEM_INFO_RECEIVED", function(_, id, success) Gear:OnItemInfo(id, nil, success) end)
Panoply:On("PLAYER_MONEY", function() Gear:OnMoney() end)
Panoply:On("SKILL_LINES_CHANGED", function() Gear:OnSkills() end)
Panoply:On("PLAYER_REGEN_ENABLED", function() Gear:AfterCombat() end)
Panoply:Listen("SPEC_TRAINER_CHANGED", function() Gear:Invalidate("spec") end)
Panoply:Listen("SPEC_PLAN_CHANGED", function() Gear:Invalidate("plan") end)

-------------------------------------------------------------------------------
-- Reports (spec 2.2 and 2.3: which plans have no weights of their own, which class rules are not checked on WoW Forever)
-------------------------------------------------------------------------------
-- { { class, plan, name, weighedWith = "Beast Mastery", own = bool, how }, ... } for every ready-made plan, and the classes
-- with no weights at all.
function Gear:WeightReport()
  local rows, missing = {}, {}
  local SB = Panoply.SpecBasic
  local ST = Panoply.SpecTrainer
  -- WoW Forever (0.9.9.4 hotfix): the ready-made plans there are Class & Spec's (ReadyMade: the public builds, none until they ship), not
  -- Specs.lua's; one that Data/GearWeights.lua does not name is weighed with its main tree
  local forever = C.IsForever and C.IsForever() and ST and ST.ReadyMade
  for _, class in ipairs(W.CLASSES) do
    if not S.Specs(class) then missing[#missing + 1] = class end
    for _, d in ipairs(forever and ST:ReadyMade(class) or (SB and SB.classes and SB.classes[class]) or {}) do
      local top
      if forever and d.points then
        local _, spent = ST:RanksAt(class, d.points)
        local best = 0
        for i, n in ipairs(spent or {}) do if n > best then best, top = n, i end end
      end
      local tbl, how = S.ForPlan(class, { key = d.key, topTree = top })
      rows[#rows + 1] = { class = class, plan = d.key, name = d.name, weighedWith = tbl and tbl.name or nil, own = how == "own", how = how,
        bands = tbl and tbl.bands ~= nil or false }
    end
  end
  return rows, missing
end

-- { { class, rule = "armor" | "weapons" | "dualWield", text, verified = false }, ... } on WoW Forever; verified = the Classic
-- note on Classic Era.
function Gear:RuleReport()
  local out = {}
  local how = R.verified.era
  if C.IsForever() then how = R.verified.forever end
  for _, class in ipairs(W.CLASSES) do
    local r = R.classes[class]
    local armor, weapons = {}, {}
    for sub, from in pairs(r.armor) do armor[#armor + 1] = (R.ARMOR_NAME[sub] or tostring(sub)) .. (from > 1 and (" from level " .. from) or "") end
    for sub in pairs(r.weapons) do weapons[#weapons + 1] = R.WEAPON_SKILL[sub] and R.WEAPON_SKILL[sub][1] or tostring(sub) end
    table.sort(armor) table.sort(weapons)
    out[#out + 1] = { class = class, rule = "armor", text = table.concat(armor, ", "), verified = how }
    out[#out + 1] = { class = class, rule = "weapons", text = table.concat(weapons, ", "), verified = how }
    out[#out + 1] = { class = class, rule = "dualWield", text = r.dualWield and ("from level " .. r.dualWield) or "never", verified = how }
  end
  return out
end
