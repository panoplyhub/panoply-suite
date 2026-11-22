-- Panoply Suite gear engine, data 2 of 2: what each class can wear and wield (docs/specs/page-redesigns-04-gear-engine.md 2.3).
-- DATA ONLY: numbers and names, no code that runs in the game. Raise `version` when a rule changes, so what the engine worked
-- out before is thrown away.
--
-- Every rule here is the Classic 1.12 rule, the one Classic Era 1.15 plays by. WoW Forever is TAKEN to be the same: no rule
-- below has been checked on the live Forever client yet (`verified.forever` says so, and Panoply.Gear:RuleReport() lists them).
-- /panoply probe records the weapon skills and the armor and shield training a Forever character really has ("gear.training").
--
-- Item numbers are the game's own: item class 2 = weapon, 4 = armor; the subclasses are listed beside each table.
local ADDON, Panoply = ...

local R = { version = 1 }
Panoply.GearRules = R

R.verified = {
  era = "The Classic 1.12 rules, which WoW Classic plays by.",
  forever = false,   -- not checked on the live WoW Forever client
}

-- Armor subclasses: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem (0 = jewellery, cloaks and
-- things held in the off hand: no training, any class).
R.ARMOR_NAME = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields", [7] = "Librams", [8] = "Idols", [9] = "Totems" }

-- Weapon subclasses, and the skill a character trains to use each: { the skill's English name, the game's skill line id }.
R.WEAPON_SKILL = {
  [0] = { "Axes", 44 }, [1] = { "Two-Handed Axes", 172 }, [2] = { "Bows", 45 }, [3] = { "Guns", 46 }, [4] = { "Maces", 54 },
  [5] = { "Two-Handed Maces", 160 }, [6] = { "Polearms", 229 }, [7] = { "Swords", 43 }, [8] = { "Two-Handed Swords", 55 },
  [10] = { "Staves", 136 }, [13] = { "Fist Weapons", 473 }, [15] = { "Daggers", 173 }, [16] = { "Thrown", 176 },
  [18] = { "Crossbows", 226 }, [19] = { "Wands", 228 },
}
R.WAND = 19
R.RANGED_WEAPON = { [2] = true, [3] = true, [16] = true, [18] = true }   -- bow, gun, thrown, crossbow (a wand has its own weight)

local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end

-- Per class:
--   armor      [armor subclass] = the level it can be worn from (a class moves up a kind of armor at 40 where it does)
--   weapons    the weapon subclasses the class can ever train
--   dualWield  the level from which a weapon can be held in the off hand (nil: never)
--   never      the slots the class never fills (keys of R.SLOTS). No class has one in this game: a paladin, a shaman and a
--              druid fill the ranged slot with a libram, a totem or an idol.
--   bit        the class's bit in an item's "Classes:" line;  id = the game's class id
R.classes = {
  WARRIOR = { id = 1, bit = 1, armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    weapons = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18), dualWield = 20, never = {} },
  PALADIN = { id = 2, bit = 2, armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    weapons = set(0, 1, 4, 5, 6, 7, 8), never = {} },
  HUNTER = { id = 3, bit = 4, armor = { [1] = 1, [2] = 1, [3] = 40 },
    weapons = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18), dualWield = 20, never = {} },
  ROGUE = { id = 4, bit = 8, armor = { [1] = 1, [2] = 1 },
    weapons = set(2, 3, 4, 7, 13, 15, 16, 18), dualWield = 10, never = {} },
  PRIEST = { id = 5, bit = 16, armor = { [1] = 1 },
    weapons = set(4, 10, 15, 19), never = {} },
  SHAMAN = { id = 7, bit = 64, armor = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
    weapons = set(0, 1, 4, 5, 10, 13, 15), never = {} },
  MAGE = { id = 8, bit = 128, armor = { [1] = 1 },
    weapons = set(7, 10, 15, 19), never = {} },
  WARLOCK = { id = 9, bit = 256, armor = { [1] = 1 },
    weapons = set(7, 10, 15, 19), never = {} },
  DRUID = { id = 11, bit = 1024, armor = { [1] = 1, [2] = 1, [8] = 1 },
    weapons = set(4, 5, 10, 13, 15), never = {} },
}

-- The game's inventory type numbers (an item's slot kind).
R.INV = { HEAD = 1, NECK = 2, SHOULDER = 3, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9, HANDS = 10, FINGER = 11,
  TRINKET = 12, ONE_HAND = 13, SHIELD = 14, BOW = 15, BACK = 16, TWO_HAND = 17, ROBE = 20, MAIN_HAND = 21, OFF_HAND = 22,
  HELD = 23, THROWN = 25, RANGED = 26, RELIC = 28 }

-- The slots as every page lists them: { key, label, the character's inventory slot ids }. Rings and trinkets are one slot
-- with two places: a candidate replaces the weaker of the two.
R.SLOTS = {
  { "head", "Head", { 1 } }, { "neck", "Neck", { 2 } }, { "shoulder", "Shoulders", { 3 } }, { "back", "Back", { 15 } },
  { "chest", "Chest", { 5 } }, { "wrist", "Wrists", { 9 } }, { "hands", "Hands", { 10 } }, { "waist", "Waist", { 6 } },
  { "legs", "Legs", { 7 } }, { "feet", "Feet", { 8 } }, { "finger", "Ring", { 11, 12 } }, { "trinket", "Trinket", { 13, 14 } },
  { "mainhand", "Main hand", { 16 } }, { "offhand", "Off hand", { 17 } }, { "ranged", "Ranged", { 18 } },
}

-- inventory type -> the slot (key of R.SLOTS) an item of that kind goes in. A one-hand weapon (13) goes in the main hand, and
-- in the off hand too for a class that can hold two weapons.
R.GOES_IN = {
  [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [20] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
  [9] = "wrist", [10] = "hands", [11] = "finger", [12] = "trinket", [16] = "back",
  [13] = "mainhand", [21] = "mainhand", [17] = "mainhand",
  [14] = "offhand", [22] = "offhand", [23] = "offhand",
  [15] = "ranged", [25] = "ranged", [26] = "ranged", [28] = "ranged",
}

-- the game's equip location token -> inventory type
R.EQUIP_LOC = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
  INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14,
  INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16, INVTYPE_2HWEAPON = 17, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21,
  INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26, INVTYPE_RELIC = 28,
}

-- The spells a character knows once it is trained in a kind of armor, a shield or holding two weapons (read by /panoply probe,
-- to check the levels above on WoW Forever; the engine itself goes by the levels).
R.TRAINING_SPELL = { [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116, dualWield = 674 }
