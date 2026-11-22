-- Panoply Suite: Forever Legacy, the facts. WoW Forever only (the Legacy system is not in Classic Era).
-- 0.8.4 shipped the categories, the perk names (from the Forever client's own spell table) and the 16-point cap. 0.9.5 phase 4C
-- (docs/specs/page-redesigns-v1.md section 3) adds what that spec gives: the perk trees with ranks, gates and prerequisites, the
-- named account rewards with their thresholds, and the 65 challenges as rows.
--
-- THIS IS THE ONE FILE TO UPDATE when Blizzard changes Legacy (the spec: "Blizzard plans more challenges, perks and trees").
-- Everything the spec marks as community or beta data is tagged here with unverified = true, and anything nobody has confirmed says
-- "Source unknown". No item, species or mount id is written here: the rewards are found by NAME in the game's collections
-- (Legacy.lua, L:Reward), and the probe (/panoply probe, Core/Probe.lua) records the ids it finds.
-- Where each fact comes from:
--   * categories and counts (65), one point each, account-wide off Hardcore, three trees, the 16-point cap: Blizzard's public
--     description at launch (0.8.4);
--   * perk names and spell ids: the Forever client's spell table, build 1.60.1 (tools/cache/forever_SpellName.csv);
--   * trees, ranks, gates, prerequisites, per-rank values, the reward names and thresholds, the PvP ranks, the Field of Honor weeks,
--     the Spelunker level bands and their notes, the raid boss counts and their date: the spec (community data around the Nov 2026
--     launch, UNVERIFIED);
--   * which dungeons make up each Spelunker band and their final bosses: our own reading of the instance atlas
--     (PanoplySuite_QuestData/Maps/Instances.lua, the last boss of each wing), UNVERIFIED;
--   * the Lord Valthalak questline: the Classic 1.12 quest data (PanoplySuite_QuestData/Data/Quests.lua), UNVERIFIED on Forever.
local ADDON, Panoply = ...
local L = {}
Panoply.Legacy = L

L.CAP = 16                     -- perk points one character can spend at launch
L.POINTS_PER_CHALLENGE = 1
L.TOTAL = 65                   -- challenges (and so account points) at launch; the page reads this, never a literal

-- The challenge categories at launch, in the game's order. count = how many challenges the category has.
L.CATEGORIES = {
  { key = "classes", name = "Classes", count = 27 },
  { key = "tradeskills", name = "Tradeskills", count = 18 },
  { key = "pvp", name = "PvP", count = 12 },
  { key = "adventure", name = "Adventure", count = 2 },
  { key = "dungeons", name = "Dungeons", count = 3 },
  { key = "raids", name = "Raids", count = 3 },
}

-- Named challenges from a live source (Legacy.lua, L:SetSource). Shape: { id, category, name, text, class, map, x, y, done }.
-- The rows below (L.ROWS, built by Legacy.lua from the tables of this file) are the page's own list; this stays for a source.
L.CHALLENGES = {}

-------------------------------------------------------------------------------
-- The perk trees
-------------------------------------------------------------------------------
L.TREES = {
  { key = "professions", name = "Professions" },
  { key = "adventure", name = "Adventure" },
  { key = "resourcefulness", name = "Resourcefulness" },
}
L.TIERS = { 0, 5, 10 }          -- a tier row opens at this many points spent in that tree, in the rows above it
L.TREE_COLS = 4                 -- columns of a tree (a perk's col)
L.FUTURE_SLOTS = 2              -- empty future slots in each tree, drawn as locked placeholders
L.TREE_UNVERIFIED = true        -- the trees below are the spec's community data

-- The perks. id = the spell in the Forever client; name = its name there; text = what it does, in our words.
-- tree, ranks, gate (points in that tree needed, in the tiers above), prereq (id of a perk that must be full first), col (1..4,
-- its column in the tree; a prerequisite sits straight above), per = what each rank gives:
--   { step = n, fmt = "..%d.." } -> rank r gives r * step;  { list = { ... }, fmt } -> rank r gives list[r];  { text = "..." } -> one text
-- A perk without a tree is in the client's table but not in the launch trees: it is kept and not shown.
L.PERKS = {
  -- Professions
  { id = 1225451, name = "Working Overtime", tree = "professions", ranks = 5, gate = 0, col = 2, per = { step = 4, fmt = "+%d%% skill-up chance" },
    text = "A better chance of a skill point each time you use any tradeskill." },
  { id = 1225435, name = "Bountiful Harvest", tree = "professions", ranks = 5, gate = 0, col = 1, per = { step = 20, fmt = "+%d%% Scarce materials" },
    text = "Scarce materials turn up more often when you mine, pick herbs or skin." },
  { id = 1225457, name = "Master Chef", tree = "professions", ranks = 5, gate = 5, col = 2, per = { step = 10, fmt = "%d%% chance of an extra cooking result" },
    text = "Your cooking has a chance to make an extra portion." },
  { id = 1225459, name = "Bartering", tree = "professions", ranks = 2, gate = 5, col = 3, per = { step = 5, fmt = "%d%% lower vendor prices" },
    text = "Every vendor charges you less gold." },
  { id = 1225456, name = "Performance Bonus", tree = "professions", ranks = 3, gate = 5, col = 1, prereq = 1225435, per = { step = 5, fmt = "%d%% chance of double Merchant's Favor" },
    text = "A chance of double Merchant's Favor when you hand in a crate to your faction's tradeskill traders." },
  { id = 1225455, name = "Luremaster", tree = "professions", ranks = 2, gate = 5, col = 4, per = { step = 25, fmt = "%d%% chance of an extra fish with a lure" },
    text = "While a lure is on your fishing pole, a chance to catch an extra fish." },
  { id = 1225469, name = "Dedicated Study", tree = "professions", ranks = 1, gate = 10, col = 3, prereq = 1225459,
    per = { text = "Raises your lowest tradeskill by one point, every 23 hours. With every tradeskill at 300 it gives Elemental Essences instead." },
    text = "Raises your lowest tradeskill by one point. With every tradeskill at 300 it gives Elemental Essence instead.",
    affects = "camp" },
  -- Adventure
  { id = 1225478, name = "Well Rested", tree = "adventure", ranks = 5, gate = 0, col = 1, per = { step = 4, fmt = "+%d%% rested rate and cap" },
    text = "Rested experience builds up faster, and you can hold more of it." },
  { id = 1225472, name = "Thrill of Adventure", tree = "adventure", ranks = 5, gate = 0, col = 2, per = { step = 1, fmt = "%d%% health and mana per killing blow, outdoors" },
    text = "A killing blow gives back some health and mana. Not in dungeons, raids or battlegrounds." },
  { id = 1225477, name = "High Alert", tree = "adventure", ranks = 2, gate = 5, col = 2, per = { step = 1, fmt = "Spot stealth as if %d level(s) higher" },
    text = "You notice stealthed enemies as if you were a few levels higher. Not in battlegrounds." },
  { id = 1225474, name = "Talented", tree = "adventure", ranks = 5, gate = 5, col = 1, prereq = 1225478, per = { list = { 9, 8, 7, 6, 5 }, fmt = "First talent point at level %d" },
    text = "Talent points start earlier than level 10. The most you can have is still 51." },
  { id = 1225479, name = "Field Guide", tree = "adventure", ranks = 3, gate = 5, col = 3, per = { list = { 8, 17, 25 }, fmt = "%d%% shorter camp cooldown" },
    text = "You can add features to your camp more often.", affects = "camp" },
  { id = 1225475, name = "Field Medicine", tree = "adventure", ranks = 2, gate = 5, col = 4, per = { step = 5, fmt = "Recently Bandaged %d seconds shorter" },
    text = "You can bandage again sooner. Not in dungeons, raids or battlegrounds." },
  { id = 1225490, name = "Frequent Flier", tree = "adventure", ranks = 1, gate = 10, col = 3, prereq = 1225479, per = { text = "Flights cost 50% less and are 20% faster." },
    text = "Flight paths cost less, and the flight is faster." },
  -- Resourcefulness
  { id = 1225499, name = "Gourmand", tree = "resourcefulness", ranks = 3, gate = 0, col = 1, per = { step = 33, fmt = "Food buffs last %d%% longer" },
    text = "Food buffs last longer." },
  { id = 1225500, name = "The Quick and the Dead", tree = "resourcefulness", ranks = 2, gate = 0, col = 2, per = { step = 5, fmt = "%d%% faster while dead, and free buffs after you are brought back" },
    text = "You move faster while dead, and your helpful spells are free for a short while after you are brought back." },
  { id = 1225497, name = "Reinforce", tree = "resourcefulness", ranks = 5, gate = 0, col = 3, per = { step = 8, fmt = "%d%% less durability lost on death" },
    text = "Your gear loses less durability when you die." },
  { id = 1225502, name = "Permanence", tree = "resourcefulness", ranks = 2, gate = 5, col = 1, prereq = 1225499, per = { step = 50, fmt = "Long buffs and camp rest last %d%% longer" },
    text = "Your long group buffs last longer, and so does the benefit of resting at a camp." },
  { id = 1225485, name = "Diplomat", tree = "resourcefulness", ranks = 5, gate = 5, col = 3, per = { step = 2, fmt = "+%d%% reputation" },
    text = "You gain reputation faster." },
  { id = 1225501, name = "For Great Honor", tree = "resourcefulness", ranks = 5, gate = 5, col = 4, per = { step = 2, fmt = "+%d%% Honor" },
    text = "You gain more Honor Points." },
  { id = 1225503, name = "Reagent Economy", tree = "resourcefulness", ranks = 1, gate = 10, col = 2, prereq = 1225500,
    per = { text = "No vendor-bought class reagents, and the first tier of camp objects is free." },
    text = "Your class abilities no longer need reagents that vendors sell.", affects = "camp" },
  -- In the client's spell table, not in the launch trees (kept, not shown)
  { id = 1225468, name = "Master Forager", text = "Extra skill in Skinning, Mining, Herbalism and Fishing." },
  { id = 1225465, name = "Meticulous", text = "A chance of extra results from First Aid, and from Alchemy elixirs, potions, draughts and flasks." },
  { id = 1225470, name = "Essence of Innovation", text = "Make an Essence of Innovation and research a new recipe for a crafting tradeskill you have at 300." },
  { id = 1225505, name = "Fast Recovery", text = "You get health and mana back faster while out of combat." },
  { id = 1225487, name = "Iron Stomach", text = "You can drink potions more often. Not in dungeons, raids or battlegrounds." },
  { id = 1225492, name = "Play Dead", text = "A chance to be able to bring yourself back with some health and mana when you die. Not in dungeons, raids or battlegrounds." },
  { id = 1225498, name = "Mount Up", text = "You ride faster. Not in battlegrounds, and it does not add to other riding speed bonuses." },
  { id = 1225491, name = "Master Swimmer", text = "You hold your breath longer and swim faster." },
  { id = 1225494, name = "Second Home", text = "A second place to return to, set at any rest area. It shares its cooldown with your hearthstone." },
  { id = 1225493, name = "Personal Banking", text = "Every innkeeper can open your bank, once per cooldown." },
  { id = 1225504, name = "Better Living Through Chemistry", text = "Elixirs and flasks last longer." },
  { id = 1225506, name = "Conquering Hero", text = "The effects you get from celebrating a boss kill last longer." },
  { id = 1225508, name = "Second Chance", text = "The effects from celebrating a boss kill stay on you the first time you die." },
  { id = 1225509, name = "Adaptability", text = "Resets the talent points you have spent." },
}

-- Our own presets: each a complete 16-point build that the planner accepts (tests/legacy_tests.lua checks every one).
-- ranks = { [perk id] = rank }. A preset only fills the plan on this page, on a click; nothing spends a point.
L.PRESETS = {
  { key = "level", name = "Level fast", tip = "For a character that wants to reach the level cap: more rested experience, talents sooner, cheaper and faster flights, more camp.",
    ranks = { [1225478] = 5, [1225474] = 5, [1225479] = 3, [1225490] = 1, [1225472] = 2 } },
  { key = "gold", name = "Gold and professions", tip = "For a character that lives off its tradeskills: faster skill points, more Scarce materials, cheaper vendors and a free skill point every day.",
    ranks = { [1225451] = 5, [1225435] = 5, [1225459] = 2, [1225469] = 1, [1225456] = 3 } },
  { key = "pvp", name = "PvP", tip = "For battlegrounds: less durability lost, more Honor, a quicker way back after a death and no reagents to buy.",
    ranks = { [1225497] = 5, [1225500] = 2, [1225499] = 3, [1225501] = 5, [1225503] = 1 } },
}

L.RESET_NOTE = "The first reset costs 10g at a class trainer. Taking points out of Talented may need a talent reset first."

-------------------------------------------------------------------------------
-- The account rewards (the reward track)
-------------------------------------------------------------------------------
-- points = the account points it unlocks at. find = how the game's collections are searched, by name: "toy" (the toy box), "pet"
-- (the pet journal), "mount" (the mount journal; "Reins of the X" teaches the mount "X"), "item" (an item the game has seen).
-- fallback = a game icon shown until the item's own icon is found (a stand-in: say so in the report). unverified = community data.
L.COSMETICS = {
  { key = "toy", kind = "Toy", name = "Replica Ironforge Air Rifle", points = 15, find = "toy", fallback = "INV_Musket_04", unverified = true },
  { key = "pet", kind = "Pet", name = "Spectral Bear Cub", points = 25, find = "pet", fallback = "INV_Box_PetCarrier_01", unverified = true },
  { key = "tabard", kind = "Tabard", name = "Spectral Bear Tabard", points = 40, find = "item", fallback = "INV_Shirt_GuildTabard_01", unverified = true },
  { key = "mount", kind = "Mount", name = "Reins of the Spectral Bear", points = 55, find = "mount", fallback = "Ability_Hunter_Pet_Bear", unverified = true },
}

-------------------------------------------------------------------------------
-- The challenges, as rows (Legacy.lua builds L.ROWS from these)
-------------------------------------------------------------------------------
L.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
L.CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
  MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
L.CLASS_LEVELS = { 25, 45, 60 }

L.TRADESKILLS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" }
L.TRADESKILL_LEVELS = { 150, 225, 300 }

L.PVP_RANKS = { 3, 7, 10, 13, 14 }
-- exalted with a battleground: the faction names of each side, searched in the reputation list; none known = ticked by hand
L.PVP_EXALTED = {
  { key = "av", name = "Alterac Valley", factions = { "Stormpike Guard", "Frostwolf Clan" } },
  { key = "ab", name = "Arathi Basin", factions = { "The League of Arathor", "The Defilers" } },
  { key = "wsg", name = "Warsong Gulch", factions = { "Silverwing Sentinels", "Warsong Outriders" } },
  { key = "di", name = "Darkspear Islands", factions = {}, note = "Source unknown: the faction's name is not confirmed, so tick it by hand." },
}
L.EXALTED_STANDING = 8
-- Field of Honor: weeks of battleground play. week1 = the first day of the first week it counts (y, m, d), community data.
L.FIELD_OF_HONOR = { weeks = { 4, 7, 10 }, week1 = { 2026, 11, 3 }, unverified = true }

-- Spelunker: every final boss of the dungeons of a level band. dungeons = atlas names (PanoplySuite_QuestData MapData); a name the
-- atlas does not have is a dungeon only WoW Forever has: it is a row with a box to tick (its bosses are not in our data).
L.SPELUNKER = {
  { key = "novice", name = "Novice Spelunker", from = 15, to = 25, unverified = true,
    dungeons = { "Ragefire Chasm", "The Deadmines", "Wailing Caverns", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade" } },
  { key = "experienced", name = "Experienced Spelunker", from = 26, to = 45, unverified = true,
    dungeons = { "Razorfen Kraul", "Gnomeregan", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "The Drowned City" },
    notes = { ["The Drowned City"] = "Reported not to count for Experienced yet." } },
  { key = "master", name = "Master Spelunker", from = 46, to = 60, unverified = true,
    dungeons = { "The Temple of Atal'Hakkar", "Blackrock Depths", "Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance" },
    notes = { ["Stratholme"] = "Balnazzar counts since Nov 13." } },
}

-- Raids: all bosses of each. bosses = how many; instance = the name the game gives inside (GetInstanceInfo). opens = the date (y, m, d).
L.RAIDS = {
  { key = "onyxia", name = "Onyxia", instance = "Onyxia's Lair", bosses = 1, opens = { 2026, 12, 9 }, unverified = true },
  { key = "barrow", name = "Barrow Deeps", instance = "Barrow Deeps", bosses = 8, opens = { 2026, 12, 9 }, unverified = true },
  { key = "hyjal", name = "Hyjal Summit", instance = "Hyjal Summit", bosses = 13, opens = { 2026, 12, 9 }, unverified = true },
}

-- Adventure
L.EXPLORE = { key = "explore", name = "Explore the world map", text = "Every area of every zone, on one character." }
-- the Lord Valthalak questline, step by step: a step is done when any quest of it is (the class variants share a step)
L.VALTHALAK = { key = "valthalak", name = "Lord Valthalak", unverified = true, steps = {
  { 8960 }, { 8961 }, { 8962, 8963, 8964, 8965 }, { 8966, 8967, 8968, 8969 }, { 8970 },
  { 8985, 8986, 8987, 8988 }, { 8989, 8990, 8991, 8992 }, { 8994 }, { 8995 }, { 8996 } } }
