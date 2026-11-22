-- Panoply Suite gear engine, data 1 of 2: the stat weights (docs/specs/page-redesigns-04-gear-engine.md 2.2).
-- DATA ONLY: numbers and names, no code that runs in the game. Tune a number here and nothing else has to change; raise
-- `version` when you do, so what the engine worked out before is thrown away.
--
-- These are Panoply Suite's own weights (no other add-on's or site's item scores were read). They are the weights the Class
-- Guide's Gear topic used before 0.9.5, moved here unchanged as the starting values.
--
-- A weight says how much one point of a stat is worth to a plan, so two items can be compared with one number. This is a first
-- cut for levelling and early dungeons: plain and conservative, not a simulation.
--
-- Where each number comes from (marked on every line below):
--   [g] the game's own rules in the 1.12 world:
--         1 Strength = 2 attack power for warriors, paladins, shamans and druids (in Bear and Cat Form), 1 for
--           rogues and hunters;
--         1 Agility = 1 attack power for rogues, hunters and druids in Cat Form, and 2 ranged attack power for hunters;
--         14 attack power = 1 damage per second on every weapon swing or shot, so 1 weapon damage per second = 14;
--         an off-hand weapon hits for half;
--         a druid's forms do not use the weapon's damage.
--   [j] judgement: a modest value where the game gives no fixed exchange rate (critical strike and hit chance,
--         Stamina, Intellect, Spirit, armor, defence, mana every 5 seconds, a wand's damage). These are the
--         numbers to tune first; none of them is shown to the player as a fact.
-- Units: for specs that hit with weapons, 1.0 = one point of attack power. For casters, 1.0 = one point of spell
-- damage. For healers, 1.0 = one point of healing.
--
-- Stat keys (the same ones PanoplySuite_QuestData/Gear/Gear.lua uses):
--   str agi sta int spi   ap rap (attack power, ranged)   crit hit (percent)   sp (spell damage, all schools)
--   heal   spcrit sphit (percent)   spholy spfire spnature spfrost spshadow sparcane (one school)   mp5
--   def (Defense skill)   dodge parry block (percent)   armor
--   The weapon terms (a weapon's damage per second, by where it is held):
--   dps (main hand, or a two-hander)   odps (off hand; when a table leaves it out it is half of dps)
--   rdps (a bow, gun, crossbow or thrown weapon)   wand (a wand)
--
-- One table per talent tree of each class:
--   { spec = "arms",        our key, stable across versions
--     name = "Arms",        the talent tab's English name
--     role = "melee",       "melee" | "ranged" | "tank" | "caster" | "healer"
--     default = true,       the tree used when the character has no plan and no talent points (one per class)
--     stats = { str = 2 },  weight per point; a stat that is not listed weighs 0
--     bands = { [1] = { rdps = 16 }, [40] = { rdps = 14 } } }
--                           OPTIONAL. From the level of each key on, these weights replace the ones of the same name in
--                           `stats` (the band with the highest key that is not above the character's level wins). No table
--                           ships with bands yet: the starting values are the same at every level.
-- `plans` says which tree's table each ready-made plan of Class & Spec is weighed with. A plan the player made is weighed with
-- the table of the ready-made plan it was copied from; a plan started empty with the tree it has the most points in, and the
-- class default until a point is spent. `own` may give a plan a table of its own (same shape as a tree's table): none has one
-- yet, so every ready-made plan shares the table of its main tree (Panoply.Gear:WeightReport() lists them).
local ADDON, Panoply = ...

local W = { version = 1 }
Panoply.GearWeights = W

-- every stat key a table may use, in the order a breakdown lists equal contributions, with the words a tooltip shows
W.STATS = {
  { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" }, { "spi", "Spirit" },
  { "ap", "Attack Power" }, { "rap", "Ranged Attack Power" }, { "crit", "Critical Strike" }, { "hit", "Hit" },
  { "sp", "Spell Power" }, { "heal", "Healing" }, { "spcrit", "Spell Critical Strike" }, { "sphit", "Spell Hit" },
  { "spholy", "Holy Spell Power" }, { "spfire", "Fire Spell Power" }, { "spnature", "Nature Spell Power" },
  { "spfrost", "Frost Spell Power" }, { "spshadow", "Shadow Spell Power" }, { "sparcane", "Arcane Spell Power" },
  { "mp5", "Mana per 5 Seconds" }, { "def", "Defense" }, { "dodge", "Dodge" }, { "parry", "Parry" }, { "block", "Block" },
  { "armor", "Armor" }, { "dps", "Weapon Damage" }, { "odps", "Off-Hand Weapon Damage" }, { "rdps", "Ranged Weapon Damage" },
  { "wand", "Wand Damage" },
}

W.classes = {
  WARRIOR = {
    { spec = "arms", name = "Arms", role = "melee", default = true, stats = {
        str = 2,        -- [g]
        ap = 1,         -- the unit
        dps = 14,       -- [g]
        agi = 1.2, crit = 22, hit = 14, sta = 0.8, armor = 0.02 } },                                   -- [j]
    { spec = "fury", name = "Fury", role = "melee", stats = {
        str = 2, ap = 1, dps = 14,                                                                      -- [g]
        agi = 1.4, crit = 26, hit = 18, sta = 0.6, armor = 0.01 } },                                   -- [j]
    { spec = "protection", name = "Protection", role = "tank", stats = {
        str = 1.2, ap = 0.5, dps = 8,                                                                   -- [j] threat matters less than staying up
        sta = 2, agi = 1.2, armor = 0.15, def = 3, dodge = 25, parry = 25, block = 8, crit = 8, hit = 12 } },   -- [j]
  },
  PALADIN = {
    { spec = "holy", name = "Holy", role = "healer", stats = {
        heal = 1,       -- the unit
        sp = 0.3, int = 1, spi = 0.3, sta = 0.5, spcrit = 12, mp5 = 2.5, armor = 0.01 } },             -- [j]
    { spec = "protection", name = "Protection", role = "tank", stats = {
        sta = 2, str = 1, agi = 0.8, int = 0.5, armor = 0.15, def = 3, dodge = 25, parry = 25, block = 8,
        sp = 0.4, spholy = 0.4, ap = 0.4, hit = 10, dps = 6 } },                                         -- [j]
    { spec = "retribution", name = "Retribution", role = "melee", default = true, stats = {
        str = 2, ap = 1, dps = 14,                                                                      -- [g]
        agi = 1, crit = 22, hit = 14, sta = 0.8, int = 0.4, sp = 0.4, spholy = 0.4, armor = 0.02 } },  -- [j]
  },
  HUNTER = {
    { spec = "beastmastery", name = "Beast Mastery", role = "ranged", default = true, stats = {
        rap = 1,        -- the unit
        rdps = 14,      -- [g]
        agi = 2.4,      -- [g] 2 ranged attack power, [j] the rest for critical strikes
        crit = 24, hit = 18, sta = 0.7, int = 0.4, spi = 0.1, str = 0.2, dps = 2, armor = 0.02 } },    -- [j] a melee weapon mostly carries stats
    { spec = "marksmanship", name = "Marksmanship", role = "ranged", stats = {
        rap = 1, rdps = 14, agi = 2.4,
        crit = 26, hit = 18, sta = 0.6, int = 0.5, spi = 0.1, str = 0.2, dps = 2, armor = 0.02 } },    -- [j]
    { spec = "survival", name = "Survival", role = "ranged", stats = {
        rap = 1, rdps = 14, agi = 2.6,
        crit = 24, hit = 18, sta = 0.8, int = 0.4, spi = 0.1, str = 0.2, dps = 2, armor = 0.02 } },    -- [j]
  },
  ROGUE = {
    { spec = "assassination", name = "Assassination", role = "melee", stats = {
        agi = 1.8,      -- [g] 1 attack power, [j] the rest for critical strikes and dodge
        str = 1, ap = 1, dps = 14,                                                                      -- [g]
        crit = 26, hit = 20, sta = 0.7, armor = 0.02 } },                                              -- [j]
    { spec = "combat", name = "Combat", role = "melee", default = true, stats = {
        agi = 1.8, str = 1, ap = 1, dps = 14,
        crit = 24, hit = 22, sta = 0.7, armor = 0.02 } },                                              -- [j]
    { spec = "subtlety", name = "Subtlety", role = "melee", stats = {
        agi = 1.9, str = 1, ap = 1, dps = 14,
        crit = 24, hit = 18, sta = 0.8, armor = 0.02 } },                                              -- [j]
  },
  PRIEST = {
    { spec = "discipline", name = "Discipline", role = "healer", stats = {
        heal = 1,
        sp = 0.3, int = 0.9, spi = 0.7, sta = 0.5, spcrit = 8, mp5 = 2.5, wand = 1 } },                -- [j]
    { spec = "holy", name = "Holy", role = "healer", stats = {
        heal = 1,
        sp = 0.3, int = 0.9, spi = 0.8, sta = 0.5, spcrit = 8, mp5 = 2.5, wand = 1 } },                -- [j]
    { spec = "shadow", name = "Shadow", role = "caster", default = true, stats = {
        sp = 1, spshadow = 1,   -- the unit
        int = 0.6, spi = 0.6, sta = 0.6, sphit = 12, spcrit = 4, mp5 = 1.5, wand = 2 } },              -- [j]
  },
  SHAMAN = {
    { spec = "elemental", name = "Elemental", role = "caster", stats = {
        sp = 1, spnature = 1,
        int = 0.8, sta = 0.6, spi = 0.3, spcrit = 10, sphit = 10, mp5 = 2, armor = 0.02 } },           -- [j]
    { spec = "enhancement", name = "Enhancement", role = "melee", default = true, stats = {
        str = 2, ap = 1, dps = 14,                                                                      -- [g]
        agi = 1.2, crit = 22, hit = 14, sta = 0.8, int = 0.5, sp = 0.3, armor = 0.02 } },              -- [j]
    { spec = "restoration", name = "Restoration", role = "healer", stats = {
        heal = 1,
        sp = 0.3, int = 0.9, spi = 0.4, sta = 0.5, spcrit = 6, mp5 = 3, armor = 0.01 } },              -- [j]
  },
  MAGE = {
    { spec = "arcane", name = "Arcane", role = "caster", stats = {
        sp = 1, sparcane = 1,
        spfire = 0.5, spfrost = 0.5, int = 0.8, spi = 0.4, sta = 0.5, spcrit = 10, sphit = 12, mp5 = 1.5, wand = 2 } },   -- [j]
    { spec = "fire", name = "Fire", role = "caster", stats = {
        sp = 1, spfire = 1,
        int = 0.7, spi = 0.3, sta = 0.5, spcrit = 12, sphit = 12, mp5 = 1.5, wand = 2 } },             -- [j]
    { spec = "frost", name = "Frost", role = "caster", default = true, stats = {
        sp = 1, spfrost = 1,
        int = 0.7, spi = 0.4, sta = 0.5, spcrit = 9, sphit = 12, mp5 = 1.5, wand = 2 } },              -- [j]
  },
  WARLOCK = {
    { spec = "affliction", name = "Affliction", role = "caster", default = true, stats = {
        sp = 1, spshadow = 1,
        sta = 0.8,      -- [j] Life Tap turns health into mana
        int = 0.5, spi = 0.3, sphit = 12, spcrit = 5, mp5 = 1, wand = 2 } },                           -- [j]
    { spec = "demonology", name = "Demonology", role = "caster", stats = {
        sp = 1, spshadow = 1,
        spfire = 0.3, sta = 0.9, int = 0.5, spi = 0.3, sphit = 12, spcrit = 6, mp5 = 1, wand = 2 } },  -- [j]
    { spec = "destruction", name = "Destruction", role = "caster", stats = {
        sp = 1, spshadow = 1,
        spfire = 0.6, sta = 0.7, int = 0.5, spi = 0.2, sphit = 12, spcrit = 10, mp5 = 1, wand = 2 } }, -- [j]
  },
  DRUID = {
    { spec = "balance", name = "Balance", role = "caster", stats = {
        sp = 1, spnature = 1, sparcane = 1,
        int = 0.8, spi = 0.4, sta = 0.5, spcrit = 10, sphit = 10, mp5 = 1.5 } },                       -- [j]
    { spec = "feral", name = "Feral Combat", role = "melee", default = true, stats = {
        str = 2,        -- [g]
        ap = 1,
        dps = 0,        -- [g] the forms do not use the weapon's damage
        agi = 1.6,      -- [g] 1 attack power in Cat Form, [j] the rest for critical strikes and dodge
        crit = 22, hit = 12, sta = 1, int = 0.2, armor = 0.04 } },                                     -- [j] Bear Form multiplies armor
    { spec = "restoration", name = "Restoration", role = "healer", stats = {
        heal = 1,
        sp = 0.3, int = 0.9, spi = 0.8, sta = 0.5, spcrit = 4, mp5 = 2.5 } },                          -- [j]
  },
}

-- The class order the game uses (class ids 1..11; 6 and 10 are not in this game).
W.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- ready-made plan (Modules/SpecTrainer/Specs.lua) -> the tree whose table weighs it
W.plans = {
  ["warrior-arms"] = "arms", ["warrior-fury"] = "fury", ["warrior-prot"] = "protection", ["warrior-fury60"] = "fury",
  ["paladin-ret"] = "retribution", ["paladin-prot"] = "protection", ["paladin-holy60"] = "holy",
  ["hunter-bm"] = "beastmastery", ["hunter-mm"] = "marksmanship", ["hunter-surv"] = "survival", ["hunter-mm60"] = "marksmanship",
  ["rogue-combat"] = "combat", ["rogue-assa"] = "assassination", ["rogue-sub"] = "subtlety", ["rogue-combat60"] = "combat",
  ["priest-shadow"] = "shadow", ["priest-holy"] = "holy", ["priest-holy60"] = "holy",
  ["shaman-enh"] = "enhancement", ["shaman-ele"] = "elemental", ["shaman-resto60"] = "restoration",
  ["mage-frost"] = "frost", ["mage-fire"] = "fire", ["mage-aoe"] = "frost", ["mage-fire60"] = "fire",
  ["warlock-aff"] = "affliction", ["warlock-demo"] = "demonology", ["warlock-destro60"] = "destruction",
  ["druid-feral"] = "feral", ["druid-balance"] = "balance", ["druid-resto60"] = "restoration",
}

-- a ready-made plan with a table of its own: [plan key] = { stats = { ... }, bands = { ... } }. None yet.
W.own = {}
