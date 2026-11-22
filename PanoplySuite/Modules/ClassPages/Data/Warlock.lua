-- Panoply Suite 0.8.4 class pages: the Warlock. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Warlock article S11, the
-- launch notes S14, the 6 Nov hotfixes S15, the class comparison C8, the race table S1), read 8 Nov 2026 and NOT checked in the
-- live game. Corrections that must stay: Banes (Agony, Doom) are a separate thing from Curses; Curse of Shadows is gone; nothing
-- here assumes the modern game's demons. Paragraphs for both games say "Agony", never "Curse of Agony" (a Bane on Forever). The level-20 incubus quest is a player report (S16) and is worded as such. The 10 Nov
-- tuning was only announced. "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  bolt = { "m", "Shadow Bolt and send the pet", "#showtooltip Shadow Bolt\n/petattack\n/cast Shadow Bolt", "Sends your demon at your target and casts Shadow Bolt. Sending the pet is an order, not a spell, so both happen on one press." },
  corr = { "m", "Corruption and send the pet", "#showtooltip Corruption\n/petattack\n/cast Corruption", "The demon goes in and Corruption goes on." },
  back = { "m", "Pet, come back", "/petfollow", "Calls your demon off and back to your side." },
  fear = { "m", "Fear under the mouse", "#showtooltip Fear\n/cast [@mouseover,harm,nodead][] Fear", "Fears the enemy you point at, so your target can stay on the one you are killing." },
  banish = { "m", "Banish under the mouse", "#showtooltip Banish\n/cast [@mouseover,harm,nodead][] Banish", "Banishes the demon or elemental you point at without changing your target." },
  lock = { "m", "Spell Lock under the mouse", "#showtooltip Spell Lock\n/cast [@mouseover,harm,nodead][] Spell Lock", "Your Felhunter interrupts the enemy under your mouse, or your target. It only works with the Felhunter out." },
  coil = { "m", "Death Coil, right now", "#showtooltip Death Coil\n/stopcasting\n/cast Death Coil", "Drops your own cast for the emergency button: the enemy runs for a moment and you get some health." },
  curse = { "m", "Two curses on one button", "#showtooltip\n/cast [mod:shift] Curse of Recklessness; Curse of the Elements", "A plain press casts Curse of the Elements; with Shift held, Curse of Recklessness. Write in the two you are assigned." },
  assist = { "m", "Assist and send the pet", "/assist [@mouseover,help][help]\n/petattack", "Point at the tank (or target them) and press: you take their target and the demon goes in." },
  off = { "m", "Pet off and passive", "/petpassive\n/petfollow", "For fights where the demon must not touch anything. Set it back to Defensive on its bar afterwards." },
  focusBanish = { "m", "Banish your focus", "#showtooltip Banish\n/cast [@focus,harm,nodead][] Banish", "Re-banishes your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("WARLOCK", {
  overview = {
    [1] = {
      { "h", "What a Warlock is" },
      { "p", "A Warlock casts shadow and fire spells and has a demon servant that fights for them. Many of your spells do their damage slowly over time: you put them on the enemy and let them work while your demon keeps it busy." },
      { "p", "You wear cloth and use Mana, the blue bar, but you can trade health for Mana and drain health back from enemies, so you rarely have to stop." },
    },
    [2] = {
      { "h", "What a Warlock is" },
      { "p", "Damage over time, a choice of demons for different jobs, and health as a second Mana bar through Life Tap. You also make Healthstones, bring dead players back with a Soulstone, and summon friends to you." },
    },
    [3] = {
      { "h", "Where a Warlock fits" },
      { "p", "Warlocks deal spell damage in all three trees. Affliction is damage over time and draining, Demonology is a stronger demon and a tougher Warlock, Destruction is big direct hits. In groups you also Banish, Fear, hand out Healthstones and summon latecomers." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "Leave the modern game's demon habits behind: read each demon's own spells here and pick it for the job. A dungeon has one difficulty: no heroic, no mythic." },
      { "e", "Soul Shards are items in your bags. You make one by killing an enemy with Drain Soul, and summoning a demon or making a stone uses one up." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Human and Gnome. Horde: Orc and Undead." },
      { "f", "Alliance: Human and Gnome. Horde: Orc, Undead and Troll (new). Skyborne cannot be Warlocks." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Your trainer gives you a quest for your first demon, the Imp, almost at once. Do it. Then: send the demon, cast Corruption and Agony on the enemy, and add Shadow Bolts until it dies." },
      { "p", "Around level 10 a second quest gives you the Voidwalker, a demon that holds the enemy's attention. It makes leveling safe." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Affliction with the Voidwalker. Put your damage-over-time spells on the enemy, then drain it or wand it. When Mana is low, Life Tap; when health is low, Drain Life. Played this way you almost never sit down." },
      { "p", "Do every demon quest your trainer offers. Keep a few Soul Shards on you for a Healthstone and for re-summoning your demon." },
    },
    [3] = {
      { "h", "Leveling another Warlock" },
      { "p", "Put your spells on one enemy and move straight to the next while they tick: two or three enemies dying at once is normal for Affliction. Fear one if it gets out of hand, in a place where it cannot run into more." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "The demon quests are real quests with travel, and each demon is a separate tool. Fear is strong and risky: feared enemies run and bring friends. Life Tap means your healer's Mana is partly yours to spend, so spend it politely." },
    },
    all = {
      { "f", "Players report a new quest at level 20 for an incubus, with a version for each faction. Ask your trainer." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Warlock trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs. Your demons learn their own spells from books called grimoires, sold by a demon trainer." },
      { "p", "From level 10 you get talent points for three trees: Affliction, Demonology and Destruction." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy Corruption, Agony, Shadow Bolt, Life Tap, Drain Life and Fear at every rank, and the grimoires for the demon you use. Affliction is the usual leveling tree." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Affliction: stronger damage over time and drains. Demonology: demon and Stamina talents, and Soul Link to share damage with your demon. Destruction: Shadow Bolt and fire spells that hit hard at once." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "No Soul Shard bar to build and spend during a fight, and no cooldown demons as a rotation." },
      { "e", "Raid damage is mostly Shadow Bolt with a curse you are assigned." },
    },
    all = {
      { "h", "Curses and demons" },
      { "p", "Imp: ranged damage and a Stamina buff. Voidwalker: holds enemies for you. Succubus: damage and a charm on humanoids. Felhunter: eats magic and interrupts casters." },
      { "e", "Agony is Curse of Agony here. One curse per Warlock on each enemy: Curse of Agony and Curse of Doom for damage, or a helping curse such as Elements, Shadow, Recklessness, Weakness or Tongues. You cannot have a damage curse and a helping curse up together." },
      { "f", "Agony and Doom are Banes now, a separate thing from Curses. One Bane per Warlock on each enemy, and a helping Curse can sit beside it. Curse of the Elements covers all magic, and Curse of Shadows is gone." },
      { "f", "Firestones and Spellstones are weapon enhancements that sit alongside other temporary weapon effects. Life Tap grows with your Spirit, and demons grow with your own gear." },
      { "f", "New in the trees: Wrack and Pandemic for Affliction, Demonic Brand, Demonic Knowledge and Demonic Pact for Demonology, Bane of Havoc and Incinerate for Destruction." },
      { "h", "Trainers" },
      { "p", "Any Warlock trainer teaches the same spells. In the capitals: Demisette Cloyce in Stormwind's Mage Quarter, Zevrost in Orgrimmar's Cleft of Shadow. Turn on Class trainers and Demon trainers in the map's Places menu to see the ones near you." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Send your demon. 2. Corruption. 3. Agony. 4. Shadow Bolt until the enemy is dead. Corruption and Agony only need casting once per enemy." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Demon in, Corruption, Agony, Immolate on tougher enemies, then Drain Life or your wand while they tick. Life Tap between fights instead of drinking, and Drain Life the next enemy to get the health back." },
      { "p", "Use Drain Soul for the killing blow when you need a Soul Shard." },
    },
    [3] = {
      { "h", "In dungeons" },
      { "p", "Give the tank a few seconds. Corruption and Agony on the kill target, then Shadow Bolt. Do not put damage over time on an enemy that is sheeped, sapped or otherwise set aside. Banish a demon or elemental when asked; Fear only when the group calls for it." },
      { "p", "Hand out Healthstones before the first pull and put a Soulstone on the healer." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Keep your assigned curse on the boss, then cast your main spell without gaps; for most builds that is Shadow Bolt. Life Tap early and often rather than running dry, and tell your healers you do it. Watch threat: Shadow Bolt critical hits pull bosses." },
      { "e", "With limited debuff slots on a Classic boss, Corruption and Immolate are usually left off unless you are told otherwise. Curse of Shadow, Curse of the Elements and Curse of Recklessness are split between the raid's Warlocks." },
      { "f", "A Bane and a Curse can both be yours on the same boss, so a damage Bane no longer costs the raid a helping Curse. Demonic Pact lets the sacrifice effect and a different summoned demon be up together." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.bolt, M.back },
    [2] = { { "h", "For the road" }, M.corr, M.bolt, M.back, M.fear },
    [3] = { { "h", "For dungeons" }, M.assist, M.back, M.fear, M.banish, M.lock, M.coil },
    [4] = { { "h", "A raid set" }, M.assist, M.off, M.curse, M.banish, M.focusBanish, M.lock, M.coil },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Cast at what the tank is fighting. Keep your demon close, and in tight places put it on Passive so it does not start a fight by itself. Use an Imp in groups: its buff gives everyone more health." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "Your jobs: damage, a Healthstone for each player, a Soulstone on the healer, and summoning players who are late. Turn off the Voidwalker's taunt, or do not bring it, so it does not fight the tank for enemies." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Learn which enemies you can Banish or enslave in each dungeon, and which pulls a Fear ruins. Arrive with a bag of Soul Shards. A Felhunter is worth more than the Imp where enemy casters decide the fight." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. A raid Warlock keeps a curse up, casts without gaps, manages threat and health, and does the utility: summons, Healthstones, Soulstones and Banish duty." },
      { "e", "Classic raids are 20 and 40 players. Bring a full Soul Shard bag; summons and stones for a raid use dozens." },
    },
  },
})
