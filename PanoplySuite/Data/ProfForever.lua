-- Panoply Suite 0.9.5, phase 4B: WoW Forever profession facts for the Professions page (docs/specs/page-redesigns-v1.md section 2.4).
-- ONE file, easy to update. Every value here is community / beta data from around the Nov 2026 launch, may change with hotfixes and is
-- UNVERIFIED until it is checked live (the /panoply probe 's own characters). Where a source is not confirmed it is nil, and the
-- page says "Source unknown". No item, spell, species or mount ID is written here: only names, which the page matches in the game.
-- Classic Era never reads this file's tables (the page hides every Forever-only part there).
local ADDON, Panoply = ...
local PF = {}
Panoply.ProfForever = PF

PF.verified = false
PF.SOURCE = "Community notes around the WoW Forever launch (Nov 2026); unverified"

-- Rank gates: the skill needed to train the rank and the character level it needs (crafting and gathering differ on Forever).
-- gather = 0: no level needed.
PF.RANK_GATES = {
  Journeyman = { cap = 150, skill = 50, craft = 10, gather = 0 },
  Expert = { cap = 225, skill = 125, craft = 20, gather = 10 },
  Artisan = { cap = 300, skill = 200, craft = 35, gather = 25 },
}

-- Camp objects: three per profession, at skill 20, 140 and 300 (Cooking's first at 1, Leatherworking's Tanning Rack at 125 since Nov 6).
-- blueprint = true: learned from a Blueprint. station = true: the skill-300 object, a required station for the most advanced recipes.
-- source = { boss, instance }: where the Blueprint drops, when it is known; nil = "Source unknown".
local function obj(skill, name, t) t = t or {} t.skill, t.name = skill, name return t end
PF.CAMP = {
  Alchemy = { obj(20, "Mana Well"), obj(140, "Fermenter", { blueprint = true }), obj(300, "Alchemy Laboratory", { blueprint = true, station = true }) },
  Blacksmithing = { obj(20, "Sharpening Wheel"), obj(140, "Anvil", { blueprint = true, source = { boss = "Gilnid", instance = "The Deadmines" } }),
    obj(300, "Master Forge", { blueprint = true, station = true }) },
  Enchanting = { obj(20, "Enchanted Lute"), obj(140, "Arcane Salvager", { blueprint = true }), obj(300, "Arcane Forge", { blueprint = true, station = true }) },
  Engineering = { obj(20, "Reagent Bot"), obj(140, "Repair Bot", { blueprint = true, source = { boss = "Sneed", instance = "The Deadmines" } }),
    obj(300, "Anarchist's Workbench", { blueprint = true, station = true }) },
  Leatherworking = { obj(20, "Camp Tent"),
    obj(125, "Tanning Rack", { blueprint = true, note = "Needs Leatherworking 125 since Nov 6.", source = { boss = "Razorclaw the Butcher", instance = "Shadowfang Keep" } }),
    obj(300, "Sewing Machine", { blueprint = true, station = true }) },
  Tailoring = { obj(20, "Faction Banner"), obj(140, "Spinning Wheel", { blueprint = true }), obj(300, "Loom", { blueprint = true, station = true }) },
  Cooking = { obj(1, "Basic Campfire Kit"), obj(140, "Cookie's Feast", { blueprint = true }), obj(300, "Iron Oven", { blueprint = true, station = true }) },
  ["First Aid"] = { obj(20, "First Aid Kit"), obj(140, "Toxin Study", { blueprint = true }), obj(300, "Plague Doctor's Laboratory", { blueprint = true, station = true }) },
  Herbalism = { obj(20, "Incense Candle"), obj(140, "Greenhouse", { blueprint = true }), obj(300, "Seed Hybridizer", { blueprint = true, station = true }) },
  Mining = { obj(20, "Lodestone"), obj(140, "Rock Garden", { blueprint = true }), obj(300, "Molten Foundry", { blueprint = true, station = true }) },
  Skinning = { obj(20, "Camp Chair"), obj(140, "Field Guide", { blueprint = true }), obj(300, "Trapper's Workbench", { blueprint = true, station = true }) },
  Fishing = { obj(20, "Fish Bowl"), obj(140, "Fishing Rack", { blueprint = true }), obj(300, "Fishing Hut", { blueprint = true, station = true }) },
}

-- Cooking's campfire: the tier sets how many camp objects fit around it.
PF.CAMPFIRE = {
  { tier = "Basic", slots = 3, skill = 1 },
  { tier = "Journeyman", slots = 5, skill = 90, blueprint = true, note = "Cooking 90 since Nov 10.", source = { boss = "Lord Serpentis", instance = "Wailing Caverns" } },
  { tier = "Expert", slots = 10, skill = 200, blueprint = true },
}

-- The trade camps. Merchant's Favor is per character, earned from Waylaid Crates; reputation comes from Craftsman's Writs (once a day each).
PF.TRADE_CAMP = {
  Alliance = { name = "Azeroth Commerce Authority" },
  Horde = { name = "Durotar Supply and Logistics" },
  currency = "Merchant's Favor",
  crate = "Waylaid Crate",
  writ = "Craftsman's Writ",
}

-- Patterns sold at the trade camps: [profession] = { { name, favor, standing, skill } }. None confirmed yet, so the Next card's
-- "Reputation or Favor needed" only shows once this list has entries (a test fills it).
PF.PATTERNS = {}

-- Recipes that need a camp station: [profession] = { [recipe name] = camp object name }. None confirmed yet; the Next card's "Blueprint
-- needed" shows when the plan's next recipe is listed here and the object is missing.
PF.RECIPE_STATIONS = {}

-- Scarce gathering materials by name (WoW Forever's "scarce materials"). None confirmed yet; until then the Scarce tab counts what the
-- gather log saw of uncommon (green) quality or better.
PF.SCARCE = {}

-- Mage Research (mages only): the skill line's name as the game shows it. Unconfirmed: any skill line whose name has "Research" in it.
PF.MAGE_RESEARCH_MATCH = "Research"

-- the camp objects of a profession (nil when it has none)
function PF.CampOf(name) return PF.CAMP[name or ""] end
-- the rank gate on Forever for a rank and profession kind ("gathering" uses the gathering level column)
function PF.Gate(rankName, kind)
  local g = PF.RANK_GATES[rankName or ""]
  if not g then return nil end
  return { skill = g.skill, level = (kind == "gathering" or kind == "fishing") and g.gather or g.craft, cap = g.cap }
end
