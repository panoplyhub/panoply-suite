-- Panoply Suite profession data: shared helpers over the generated tables (World.lua + one file per
-- profession, built by tools/build_profdata.py from the VMaNGOS world database). The generated
-- tables ship in the separate data add-on PanoplySuite_QuestData (Professions/, Gathering/) and are
-- linked in below; without that add-on the profession and gathering features stay empty.
-- Everything is Classic 1.12 data and UNVERIFIED for WoW Forever; the addon corrects recipe colours
-- from the open profession window (PanoplySuiteDB.tradeObservations) as you play.
-- 0.8.4: on WoW Forever only, the recipe colours the Forever client table carries (the data add-on's
-- Professions/Forever.lua) are laid over the Classic values. Classic Era never sees that overlay.
local ADDON, Panoply = ...
Panoply.ProfData = Panoply.ProfData or {}
local PD = Panoply.ProfData

-- Link the data add-on's generated tables (it loads first through OptionalDeps).
local ext = rawget(_G, "PanoplySuiteQuestData")
if type(ext) == "table" then
  if type(ext.ProfData) == "table" then
    for k, v in pairs(ext.ProfData) do
      if PD[k] == nil then PD[k] = v end
    end
  end
  if Panoply.GatherData == nil and type(ext.GatherData) == "table" then Panoply.GatherData = ext.GatherData end
end

-- WoW Forever overlay. F = PanoplySuiteQuestData.ProfDataForever: profs[name] = { checked, same, changed,
-- missing = { spellId, ... }, foreverOnly, colours = { [spellId] = { yellow, green, grey [, learn, learnDerived] [, greyAtLearn] } } }.
-- yellow and grey are the Forever table's numbers. `learn` is our own rule (learnDerived, UNVERIFIED): the table has no learn
-- skill, so where the whole colour window moved down, learn moves with it. Trainer, fee and reagents stay the Classic ones.
-- A changed recipe keeps its Classic numbers in r.classic. A recipe the Forever table does not list is
-- flagged foreverMissing (plans leave it out unless you know it). prof.forever.learnDerived counts the recipes whose learn
-- skill is that estimate, so a plan can say so. Returns how many recipes changed. fp.names[spellId] = the Forever client's
-- spell name where it differs from 1.12 (kept in r.classicName); fp.moved[spellId] = profession the Forever client files the
-- recipe under (see below; prof.forever.movedIn counts the recipes that arrived).
function PD.ApplyForever(F)
  if PD.foreverApplied or type(F) ~= "table" or type(F.profs) ~= "table" then return 0 end
  local n = 0
  -- 0.9.3: recipes the Forever client lists under another profession's skill line move there first (fp.moved[spellId] =
  -- destination profession), so the colour and name rows below, which sit under the destination, find them. The moved
  -- recipe keeps r.classicSkillLine (its 1.12 profession). Ids are walked in order so the destination list is stable.
  local movedIn = {}
  for name, fp in pairs(F.profs) do
    local src = PD[name]
    if type(src) == "table" and type(src.recipes) == "table" and type(fp) == "table" and type(fp.moved) == "table" then
      local ids = {}
      for id in pairs(fp.moved) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local dst = PD[fp.moved[id]]
        if type(dst) == "table" and type(dst.recipes) == "table" then
          for i, r in ipairs(src.recipes) do
            if r.id == id then
              table.remove(src.recipes, i)
              r.classicSkillLine = name
              dst.recipes[#dst.recipes + 1] = r
              movedIn[fp.moved[id]] = (movedIn[fp.moved[id]] or 0) + 1
              break
            end
          end
        end
      end
    end
  end
  for name, fp in pairs(F.profs) do
    local prof = PD[name]
    if type(prof) == "table" and type(fp) == "table" then
      local missing = {}
      for _, id in ipairs(fp.missing or {}) do missing[id] = true end
      local colours, derived, fnames = fp.colours or {}, 0, fp.names or {}
      for _, list in ipairs({ prof.recipes or {}, prof.smelting or {} }) do
        for _, r in ipairs(list) do
          -- the Forever client's own spell name (the Era client keeps the 1.12 one); the old name stays in r.classicName
          local nm = r.id and fnames[r.id]
          if nm and nm ~= r.name then r.classicName, r.name = r.name, nm end
          local c = r.id and colours[r.id]
          if c then
            r.classic = { learn = r.learn, yellow = r.yellow, green = r.green, grey = r.grey }
            r.yellow, r.green, r.grey = c.yellow, c.green, c.grey
            if c.learn then r.learn, r.learnDerived, derived = c.learn, true, derived + 1 end
            r.greyAtLearn = c.greyAtLearn
            r.foreverColours = true
            n = n + 1
          elseif r.id and missing[r.id] then
            r.foreverMissing = true
          end
        end
      end
      prof.forever = { checked = fp.checked or 0, same = fp.same or 0, changed = fp.changed or 0, missing = #(fp.missing or {}),
                       foreverOnly = fp.foreverOnly or 0, learnDerived = derived, movedIn = movedIn[name] or 0 }
    end
  end
  PD.foreverApplied = n
  return n
end
if type(ext) == "table" and Panoply.Compat and Panoply.Compat.IsForever() then PD.ApplyForever(ext.ProfDataForever) end

-- Fallback rank ladder, used only when a profession file has no rank data.
PD.STANDARD_RANKS = {
  { name = "Apprentice", max = 75,  minSkill = 0,   minLevel = 1,  fee = 10 },
  { name = "Journeyman", max = 150, minSkill = 50,  minLevel = 10, fee = 500 },
  { name = "Expert",     max = 225, minSkill = 125, minLevel = 20, fee = 1000 },
  { name = "Artisan",    max = 300, minSkill = 200, minLevel = 35, fee = 5000 },
}

-- Skill-line ids (match the live skill list when names are localized).
PD.SKILL_LINES = {
  Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Herbalism = 182,
  Leatherworking = 165, Mining = 186, Skinning = 393, Tailoring = 197,
  Cooking = 185, ["First Aid"] = 129, Fishing = 356,
}

PD.ORDER = { "Mining", "Herbalism", "Skinning", "Tailoring", "Leatherworking", "Blacksmithing",
             "Engineering", "Alchemy", "Enchanting", "First Aid", "Cooking", "Fishing" }
PD.SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true }

-- Professions that feed each other (used by the partner/synergy panel and the material router).
PD.SYNERGY = {
  { from = "Mining", to = "Blacksmithing", text = "Your Mining supplies your Blacksmithing: ore becomes bars at a forge." },
  { from = "Mining", to = "Engineering", text = "Your Mining supplies Engineering with bars and stone." },
  { from = "Tailoring", to = "Enchanting", text = "Tailoring greens disenchant into Enchanting dust and essences." },
  { from = "Blacksmithing", to = "Enchanting", text = "Blacksmithing makes the Copper, Silver, Golden and Truesilver Rods that Enchanting needs." },
  { from = "Fishing", to = "Cooking", text = "Fish you catch are the main Cooking ingredients." },
  { from = "Tailoring", to = "First Aid", text = "Cloth you collect for Tailoring also feeds First Aid bandages (keep some aside)." },
}

local function world() return PD.WORLD or { items = {}, npcs = {}, focus = {}, disenchant = {}, auctioneers = {} } end
function PD.World() return world() end

function PD.Item(id) return world().items[id] end

function PD.ItemName(id)
  local it = world().items[id]
  if it and it.name then return it.name end
  local QD = Panoply.QuestData
  local n = QD and QD.ItemName and QD:ItemName(id)
  return n or "an item"
end

local nameIndex
function PD.ItemID(name)
  if type(name) == "number" then return name end
  if not nameIndex then
    nameIndex = {}
    for id, it in pairs(world().items) do if it.name then nameIndex[it.name] = id end end
  end
  return nameIndex[name]
end

-- Price in copper and where the number came from ("you", "vendor", "auction", "guess"). The lookup
-- itself is Panoply.Prices (Modules/Auctions/Prices.lua): the one price service. This keeps only the
-- order that matters for plans (what you typed, then the fixed vendor price, then what the auction
-- house scans say, then the built-in guess).
-- 0.9.6 phase P (Nov 17 2026): the vendor price of the player's own side. Items carry `sidePrice` ({ A = copper, H = copper }:
-- a side has it when a vendor of that side, or a neutral one, sells the item with unlimited stock); `price` / `priceSource` are the
-- Alliance-side values. Your side's vendor price is "vendor"; with none, the other side's vendor price is only an estimate for you
-- ("guess": you cannot buy it from a vendor). Data without `sidePrice`, or no side for the player: the old fields.
local function playerSide()
  local f = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
  return (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
end
PD.PlayerSide = playerSide
function PD.ItemPrice(id)
  local it = world().items[id]
  if not it then return nil end
  local sp, me = it.sidePrice, playerSide()
  if type(sp) == "table" and me then
    if sp[me] then return sp[me], "vendor" end
    local other = sp[me == "H" and "A" or "H"]
    if other then return other, "guess" end
  end
  if it.price then return it.price, it.priceSource or "guess" end
  return nil
end
-- is the item's vendor stock limited for you? With `sidePrice`, your side's vendor price exists only for an unlimited vendor
function PD.VendorLimited(id)
  local it = world().items[id]
  if not it then return false end
  local me = playerSide()
  if type(it.sidePrice) == "table" and me then return it.sidePrice[me] == nil end
  return it.limited and true or false
end
function PD.Price(id)
  local it = world().items[id]
  local P = Panoply.Prices
  if P then
    local u = P.Yours(id, it and it.name)
    if u then return u, "you" end
  end
  local p, src = PD.ItemPrice(id)
  if p and src == "vendor" then return p, "vendor" end
  local m = P and P.Market(id)
  if m then return m, "auction" end
  if p then return p, src end
  return 0, "unknown"
end

-- Best known position of an NPC: Panoply Suite Quest Data first (right ids for both clients), else embedded.
function PD.NpcSpot(id)
  local QD = Panoply.QuestData
  if QD and QD.Available and QD:Available() then
    local s = QD:NpcSpots(id)
    if s and s[1] then
      local w = world().npcs[id]
      return { map = s[1].map, x = s[1].x, y = s[1].y, name = (QD:NpcName(id)) or (w and w.name), title = w and w.title, npc = id }
    end
  end
  local w = world().npcs[id]
  if w and w.map then return { map = w.map, x = w.x, y = w.y, name = w.name, title = w.title, npc = id } end
  return nil
end

local function travel(pos, spot)
  if not (Panoply.Nav and spot) then return 1e9 end
  return Panoply.Nav.TravelSeconds(pos, spot) or 1e9
end
PD.Travel = travel

-- Nearest of a list of NPC ids to `pos` (player position). Returns spot (with .t seconds) or nil.
function PD.NearestNpc(ids, pos)
  local best
  for _, id in ipairs(ids or {}) do
    local s = PD.NpcSpot(id)
    if s then
      s.t = travel(pos, s)
      if not best or s.t < best.t then best = s end
    end
  end
  return best
end

-- Nearest crafting station ("anvil", "forge", "cooking").
function PD.NearestFocus(kind, pos)
  local best
  for _, p in ipairs(world().focus[kind] or {}) do
    local s = { map = p[1], x = p[2], y = p[3] }
    s.t = travel(pos, s)
    if not best or s.t < best.t then best = s end
  end
  return best
end

-- 0.9.6 phase P (Nov 17 2026): the nearest auctioneer of the player's own side or a neutral one (World `allAuctioneers`, both
-- sides; `auctioneers` is the old Alliance-side list), by phase L's lookup (Engine/ProfGuide.lua G:FriendlyNearest): this zone,
-- then your capitals, then anywhere. Never the other side's, never one whose side is unknown. Returns spot (with .t), where
-- ("zone" | "city" | "near"), or nil, "guard" when none is known (PD.AH_COPY: ask a city guard for the Auction House).
PD.AH_COPY = {
  short = "ask a city guard for the Auction House",   -- PLACEHOLDER COPY (Marketing)
  row = "Ask a city guard for the Auction House",   -- PLACEHOLDER COPY (Marketing)
  guard = "No Auction House of your side is known nearby. City guards mark it on your map.",   -- PLACEHOLDER COPY (Marketing)
}
function PD.NearestAuctioneer(pos)
  local W = world()
  local G = Panoply.ProfGuide
  if G and G.FriendlyNearest then return G:FriendlyNearest(W.allAuctioneers or W.auctioneers, pos) end
  return PD.NearestNpc(W.auctioneers, pos)
end

-- Disenchant ranges that yield an item, best chance first: { {minIlvl, maxIlvl, kind, chance} }
function PD.DisenchantSources(itemID)
  local out = {}
  for _, d in ipairs(world().disenchant or {}) do
    local m = d.mats and d.mats[itemID]
    if m and m.chance >= 15 then out[#out + 1] = { minIlvl = d.minIlvl, maxIlvl = d.maxIlvl, kind = d.kind, chance = m.chance } end
  end
  table.sort(out, function(a, b) if a.chance ~= b.chance then return a.chance > b.chance end return a.minIlvl < b.minIlvl end)
  return out
end

function PD.IsDisenchantMat(itemID)
  for _, d in ipairs(world().disenchant or {}) do if d.mats and d.mats[itemID] then return true end end
  return false
end
