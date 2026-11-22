-- Panoply Suite gear engine, part 2: where gear comes from (docs/specs/page-redesigns-04-gear-engine.md section 4).
-- Each source hands the engine its candidates: an item, and one record that says where it comes from. A source is ON when its
-- data is there and OFF otherwise (the engine's results say which were off), so a source whose data arrives in a later version
-- needs no change here: it switches itself on.
--
--   kind      data it reads                                              on today?
--   quest     PanoplySuite_QuestData: Loot (rewards) + Gear + quest records     yes, with the data add-on
--   dungeon   PanoplySuite_QuestData: Loot (drop chances) + Gear + the instance atlas  yes, with the data add-on
--   raid      the same, for raids; hidden on WoW Forever until raids open        Classic: yes. Forever: from Src.FOREVER_RAIDS_OPEN
--   crafted   PanoplySuite_QuestData: profession recipes; material prices from the price service when it has them;
--             "who can craft" when another module provides it (Src.whoCanCraft)   yes, with the data add-on
--   auction   whatever the Auctions module hands over (Src.auctionData)           when a scan is loaded
--   vendor    PanoplySuiteQuestData.GearVendors                                   no: that table does not exist yet
--   favor     PanoplySuiteQuestData.GearFavor (WoW Forever trade camps)           no: that table does not exist yet
-- World drops are not a source: they only show when they are on the auction house.
--
-- A source record always has `kind`, and `fromLevel` when the source opens at a level (a quest's minimum level, the level a
-- dungeon comes into range): an item with no source open yet is listed as held back, "At level N". The rest by kind:
--   quest    id, name, level, reqLevel, zone (area id), zoneName, faction, chainStart = { id, name } or nil
--   dungeon  instance (map id), name, boss, chance (percent, nil when not known), levels = { low, high }, enter
--   raid     as dungeon
--   vendor   npc, name, zone, price (copper), reputation
--   auction  price (lowest buyout, copper), market, age (seconds since the scan), key (the Auctions module's own item key)
--   crafted  profession, skill, recipe, spell, cost (materials, copper, nil when no price is known), costKnown (every material
--            had a price), whoCanCraft = { "Name", ... } or nil
--   favor    favor (cost), standing, camp
-- Reads only: nothing here buys, travels or picks anything.
local ADDON, Panoply = ...
local C = Panoply.Compat

local Src = { list = {}, by = {} }
Panoply.GearSources = Src

Src.QUEST_AHEAD = 5        -- a quest more than this many levels above the character (or above its own minimum level) is too hard
Src.QUEST_BEHIND = 8       -- quests this many levels under the character are still listed
Src.DUNGEON_UNDER = 3      -- a dungeon counts from this many levels under its lowest monsters (and from its entry level)
Src.DUNGEON_OVER = 3       -- and up to this many levels over its highest
Src.RAID_LEVEL = 60
Src.CRAFT_OVER = 8         -- a recipe is looked at when its product's item level is at most this far over the window
Src.CRAFT_UNDER = 12       -- and at most this far under the character
-- the professions that make things to wear or wield (the others' products are never asked about)
Src.CRAFT_GEAR = { Blacksmithing = true, Leatherworking = true, Tailoring = true, Engineering = true, Enchanting = true }
-- Raids open on WoW Forever on this day (docs/specs/page-redesigns-04-gear-engine.md section 4). Classic Era: always open.
Src.FOREVER_RAIDS_OPEN = { year = 2026, month = 12, day = 9, hour = 0 }

-- Other modules plug their data in here when they have it:
Src.auctionData = nil      -- function() -> { age = seconds, items = { { ref = link or id, price = copper, market = copper, key = the caller's own }, ... } } or nil
Src.whoCanCraft = nil      -- function(profession name, recipe) -> { "Name", ... } or nil

-- def = { kind, label, available = function(ctx) -> bool, collect = function(ctx, filter, emit, tick) }
--   emit(item ref or item id, source record, price or nil);  tick() lets the engine spread the work over frames
function Src:Register(def)
  if not self.by[def.kind] then self.list[#self.list + 1] = def end
  self.by[def.kind] = def
  for i, d in ipairs(self.list) do if d.kind == def.kind then self.list[i] = def end end
  return def
end

local function own() return rawget(_G, "PanoplySuiteQuestData") end
local function lootData() local d = own() return d and type(d.LootData) == "table" and d.LootData or nil end
local function gearData() local d = own() return d and type(d.GearData) == "table" and type(d.GearData.items) == "table" and d.GearData or nil end
local function mapData() local d = own() return d and type(d.MapData) == "table" and d.MapData or nil end
Src.LootData, Src.GearData, Src.MapData = lootData, gearData, mapData

-- One table of the loot data ("bosses", "quests") and, on WoW Forever, the table of Forever's own records that go before it
local function lootTables(name)
  local loot = lootData()
  if not loot then return nil, nil end
  local over = C.IsForever() and type(loot.forever) == "table" and type(loot.forever[name]) == "table" and loot.forever[name] or nil
  return type(loot[name]) == "table" and loot[name] or nil, over
end

local floor = math.floor
local function hasBit(mask, bitValue) return floor(mask / bitValue) % 2 == 1 end
local function windowTop(ctx, filter) return filter.maxLevel or ctx.level end

-------------------------------------------------------------------------------
-- Quest rewards
-------------------------------------------------------------------------------
-- Is the quest for the character's side? The data has no side on a quest: it is the side of who gives it (or, for a quest an
-- item or an object starts, of who takes it back). A quest with nobody to ask is let through.
local function questSide(QD, q)
  for _, list in ipairs({ q.starts and q.starts.npc or {}, q.ends and q.ends.npc or {} }) do
    if #list > 0 then
      for _, npc in ipairs(list) do
        local ok, friendly = pcall(QD.NpcFriendly, QD, npc)
        if ok and friendly then return true end
      end
      return false
    end
  end
  return true
end

-- Is the quest one this character can do inside the window? The quest, or nil. Left out: done quests, hidden ones, the other
-- side's, another class's or race's, repeatable ones, and the ones that ask for a profession, a reputation or a spell.
function Src:QuestOpen(qid, ctx, filter)
  local QD = Panoply.QuestData
  if not (QD and QD.GetQuest) then return nil end
  local data = own()
  if data and data.IsHidden and data.IsHidden(qid) then return nil end
  if QD.hidden and QD.hidden[qid] then return nil end
  if ctx.done and ctx.done(qid) then return nil end
  local ok, q = pcall(QD.GetQuest, QD, qid)
  if not ok or not q then return nil end
  if (q.specialFlags or 0) % 2 == 1 or q.reqSkill or q.reqMinRep or (q.reqSpell or 0) ~= 0 or (q.parentQuest or 0) ~= 0 then return nil end
  if ctx.side ~= false and not questSide(QD, q) then return nil end
  if (q.classes or 0) ~= 0 and not (ctx.classID and hasBit(q.classes, 2 ^ (ctx.classID - 1))) then return nil end
  if (q.races or 0) ~= 0 and ctx.raceID then
    local rm = QD.RaceMask and QD:RaceMask(ctx.raceID)
    if not (rm and rm > 0 and hasBit(q.races, rm)) then return nil end
  end
  if ctx.raceID and QD.ForeignStart and QD:ForeignStart(q.zone, ctx.raceID) then return nil end   -- another race's starting valley
  if (q.reqMaxLevel or 0) > 0 and ctx.level > q.reqMaxLevel then return nil end
  -- the window decides how far ahead quests are looked at (by the level they open at); how hard a quest may be does not
  -- depend on the window, so every page agrees on what can be had now
  local top = windowTop(ctx, filter)
  local lvl, req = tonumber(q.level) or 0, tonumber(q.reqLevel) or 0
  if req > top then return nil end
  if lvl > math.max(ctx.level, req) + Src.QUEST_AHEAD then return nil end
  if lvl > 0 and lvl < ctx.level - Src.QUEST_BEHIND then return nil end
  return q
end

-- the first quest of the chain a quest is in: { id, name }, or nil when it stands alone
function Src:ChainStart(q)
  local QD = Panoply.QuestData
  local cur, hops = q, 0
  while cur and hops < 12 do
    local pre = (cur.preSingle and cur.preSingle[1]) or (cur.preGroup and cur.preGroup[1])
    if not pre then break end
    local ok, p = pcall(QD.GetQuest, QD, pre)
    if not (ok and p) then break end
    cur, hops = p, hops + 1
  end
  if cur and cur ~= q then return { id = cur.id, name = cur.name } end
  return nil
end

local function questItems(qid)
  local out, seen = {}, {}
  local base, over = lootTables("quests")
  local raw = (over and over[qid]) or (base and base[qid])
  if type(raw) == "string" then for id in raw:gmatch("%d+") do id = tonumber(id) if not seen[id] then seen[id] = true out[#out + 1] = id end end end
  local gd = gearData()
  raw = gd and gd.quests and gd.quests[qid]
  if type(raw) == "string" then for id in raw:gmatch("%d+") do id = tonumber(id) if not seen[id] then seen[id] = true out[#out + 1] = id end end end
  return out
end

Src:Register({ kind = "quest", label = "Quest rewards",
  available = function() return (lootData() ~= nil or gearData() ~= nil) and Panoply.QuestData ~= nil and Panoply.QuestData.GetQuest ~= nil end,
  collect = function(ctx, filter, emit, tick)
    local seen = {}
    local base, over = lootTables("quests")
    local gd = gearData()
    for _, set in ipairs({ over or {}, base or {}, gd and gd.quests or {} }) do
      for qid in pairs(set) do
        if not seen[qid] then
          seen[qid] = true
          tick()
          local q = Src:QuestOpen(qid, ctx, filter)
          if q then
            local src
            for _, id in ipairs(questItems(qid)) do
              src = src or { kind = "quest", id = qid, name = q.name, level = q.level, reqLevel = q.reqLevel, fromLevel = q.reqLevel, zone = q.zone,
                zoneName = (q.zone or 0) > 0 and C.AreaName and C.AreaName(q.zone) or nil, faction = ctx.faction, chainStart = Src:ChainStart(q) }
              emit(id, src)
            end
          end
        end
      end
    end
  end })

-------------------------------------------------------------------------------
-- Dungeon and raid drops
-------------------------------------------------------------------------------
function Src:RaidsOpen()
  if not C.IsForever() then return true end
  local now = _G.time and time() or 0
  if type(_G.time) ~= "function" then return false end
  local ok, at = pcall(_G.time, Src.FOREVER_RAIDS_OPEN)
  return ok and type(at) == "number" and now >= at
end

-- Can a character of this level, looking up to `top`, use what the instance drops? (a dungeon from its entry level and a few
-- levels under its monsters to a few over; a raid at the last level). Also returns the level it comes into range at.
function Src:InstanceInRange(inst, level, top)
  if type(inst) ~= "table" then return false end
  if inst.kind == "raid" then return top >= Src.RAID_LEVEL, Src.RAID_LEVEL end
  local lo = type(inst.mobs) == "table" and tonumber(inst.mobs[1]) or 1
  local hi = type(inst.mobs) == "table" and tonumber(inst.mobs[2]) or lo
  local from = math.max(inst.enter or 0, lo - Src.DUNGEON_UNDER)
  return top >= from and level <= hi + Src.DUNGEON_OVER, from
end

-- { { boss, item id, chance or nil }, ... } for one instance: the drop chances of the loot tables, and the items only the
-- Gear table lists
local function instanceDrops(id)
  local out, seen = {}, {}
  local base, over = lootTables("bosses")
  for _, r in ipairs((over and over[id]) or (base and base[id]) or {}) do
    for iid, ch in tostring(r[2] or ""):gmatch("(%d+):(%d+)") do
      iid = tonumber(iid)
      seen[r[1] .. "\1" .. iid] = true
      out[#out + 1] = { r[1], iid, tonumber(ch) }
    end
  end
  local gd = gearData()
  for _, r in ipairs(gd and gd.bosses and gd.bosses[id] or {}) do
    for iid in tostring(r[2] or ""):gmatch("%d+") do
      iid = tonumber(iid)
      if not seen[r[1] .. "\1" .. iid] then out[#out + 1] = { r[1], iid } end
    end
  end
  return out
end

local function instanceSource(kind)
  return function(ctx, filter, emit, tick)
    local md = mapData()
    local top = windowTop(ctx, filter)
    for _, inst in ipairs(md and md.instances or {}) do
      local isRaid = inst.kind == "raid"
      local inRange, from = Src:InstanceInRange(inst, ctx.level, top)
      if (kind == "raid") == isRaid and inRange then
        for _, d in ipairs(instanceDrops(inst.id)) do
          tick()
          emit(d[2], { kind = kind, instance = inst.id, name = inst.name, boss = d[1], chance = d[3], fromLevel = from,
            levels = type(inst.mobs) == "table" and { inst.mobs[1], inst.mobs[2] } or nil, enter = inst.enter })
        end
      end
    end
  end
end

local function haveDrops() return mapData() ~= nil and (lootData() ~= nil or gearData() ~= nil) end
Src:Register({ kind = "dungeon", label = "Dungeon drops", available = haveDrops, collect = instanceSource("dungeon") })
Src:Register({ kind = "raid", label = "Raid drops", available = function() return haveDrops() and Src:RaidsOpen() end,
  collect = instanceSource("raid") })

-------------------------------------------------------------------------------
-- Vendors (no data yet)
-------------------------------------------------------------------------------
-- PanoplySuiteQuestData.GearVendors = { [item id] = { { npc = id, name = "...", zone = "...", price = copper, reputation = "Honored" or nil,
--   side = "A" | "H" | nil }, ... } }
Src:Register({ kind = "vendor", label = "Vendors",
  available = function() local d = own() return d ~= nil and type(d.GearVendors) == "table" end,
  collect = function(ctx, filter, emit, tick)
    local side = ctx.faction == "Horde" and "H" or (ctx.faction == "Alliance" and "A" or nil)
    for id, rows in pairs(own().GearVendors) do
      tick()
      for _, v in ipairs(type(rows) == "table" and rows or {}) do
        if not (v.side and side and v.side ~= side) then
          emit(id, { kind = "vendor", npc = v.npc, name = v.name, zone = v.zone, price = v.price, reputation = v.reputation }, v.price)
        end
      end
    end
  end })

-------------------------------------------------------------------------------
-- The auction house (data from the Auctions module, when it has a scan)
-------------------------------------------------------------------------------
function Src:AuctionRows()
  if type(self.auctionData) ~= "function" then return nil end
  local ok, d = pcall(self.auctionData)
  if ok and type(d) == "table" and type(d.items) == "table" then return d end
  return nil
end

-- one row of the Auctions module's summary as the engine's source record (the same here and when rows come later: AddCandidates)
function Src.AuctionRecord(r, age)
  return { kind = "auction", price = r.price, market = r.market, age = age, key = r.key }
end

Src:Register({ kind = "auction", label = "Auction house",
  available = function() return Src:AuctionRows() ~= nil end,
  collect = function(ctx, filter, emit, tick)
    local d = Src:AuctionRows()
    for _, r in ipairs(d and d.items or {}) do
      tick()
      if r.ref and r.price then emit(r.ref, Src.AuctionRecord(r, d.age), r.price) end
    end
  end })

-------------------------------------------------------------------------------
-- Crafted gear
-------------------------------------------------------------------------------
local function materialsCost(recipe)
  local P = Panoply.Prices
  if not (P and P.Unit) then return nil, false end
  local total, known, any = 0, true, false
  for id, n in pairs(recipe.reagents or {}) do
    local ok, c = pcall(P.Unit, id)
    if ok and type(c) == "number" then total, any = total + c * n, true else known = false end
  end
  if not any then return nil, false end
  return total, known
end

Src:Register({ kind = "crafted", label = "Crafted",
  available = function() local d = own() return d ~= nil and type(d.ProfData) == "table" end,
  collect = function(ctx, filter, emit, tick)
    local top = windowTop(ctx, filter)
    for prof, pd in pairs(own().ProfData) do
      if type(pd) == "table" and pd.kind == "crafting" and type(pd.recipes) == "table" and Src.CRAFT_GEAR[pd.name or prof] then
        for _, r in ipairs(pd.recipes) do
          tick()
          local ilvl = tonumber(r.ilvl) or 0
          if r.makes and ilvl > 0 and ilvl <= top + Src.CRAFT_OVER and ilvl >= ctx.level - Src.CRAFT_UNDER then
            local cost, known = materialsCost(r)
            local who
            if type(Src.whoCanCraft) == "function" then
              local ok, list = pcall(Src.whoCanCraft, pd.name or prof, r)
              if ok and type(list) == "table" then who = list end
            end
            emit(r.makes, { kind = "crafted", profession = pd.name or prof, skill = r.learn or r.yellow, recipe = r.name, spell = r.id,
              cost = cost, costKnown = known, whoCanCraft = who }, cost)
          end
        end
      end
    end
  end })

-------------------------------------------------------------------------------
-- Merchant's Favor, the trade camps of WoW Forever (no data yet)
-------------------------------------------------------------------------------
-- PanoplySuiteQuestData.GearFavor = { [item id] = { favor = 120, standing = "Friendly", camp = "..." } }
Src:Register({ kind = "favor", label = "Merchant's Favor",
  available = function() local d = own() return C.IsForever() and d ~= nil and type(d.GearFavor) == "table" end,
  collect = function(ctx, filter, emit, tick)
    for id, f in pairs(own().GearFavor) do
      tick()
      if type(f) == "table" then emit(id, { kind = "favor", favor = f.favor, standing = f.standing, camp = f.camp }) end
    end
  end })

-------------------------------------------------------------------------------
-- The same words for a source on every page
-------------------------------------------------------------------------------
function Src.Text(src)
  if type(src) ~= "table" then return "" end
  local k = src.kind
  if k == "quest" then
    local lvl = tonumber(src.level) or 0
    return "Quest: " .. tostring(src.name or "?") .. (lvl > 0 and (" (level %d)"):format(lvl) or "")
  elseif k == "dungeon" or k == "raid" then
    local s = (src.name and (src.name .. ": ") or "") .. tostring(src.boss or "?")
    if src.chance then s = s .. (" (%d%%)"):format(src.chance) end
    return s
  elseif k == "vendor" then
    return "Vendor: " .. tostring(src.name or "?") .. (src.zone and (", " .. src.zone) or "")
  elseif k == "auction" then
    return "Auction house" .. (src.price and (": " .. C.FormatMoney(src.price)) or "")
  elseif k == "crafted" then
    return tostring(src.profession or "Crafted") .. (src.skill and (" (%d)"):format(src.skill) or "") .. ": " .. tostring(src.recipe or "?")
  elseif k == "favor" then
    return "Merchant's Favor" .. (src.favor and (": %d"):format(src.favor) or "")
  end
  return ""
end
