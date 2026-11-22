-- Panoply Suite 0.8.4 class pages: the Druid. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Druid article S8, the
-- launch notes S14, the 6 Nov hotfixes S15, the class comparison C9, the race table S1), read 8 Nov 2026 and NOT checked in the
-- live game. Corrections that must stay: there is no Berserk; Lacerate is a Feral talent, not trained at 42; Swiftmend needs your
-- own Regrowth or Rejuvenation on the target and does not use it up. The Cat Form quest in Moonglade and the Skyborne spirit
-- quests are player reports (S16) and are worded as such. Lotheluum Starbreeze's training is confirmed by the 5 Nov hotfix.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  heal = { "m", "Heal a friend, or me", "#showtooltip Healing Touch\n/cast [help,nodead][@player] Healing Touch", "Heals the friend you have targeted. With an enemy or nobody targeted, it heals you." },
  bear = { "m", "Bear Form that stays on", "#showtooltip Bear Form\n/cast [noform] Bear Form", "Changes into a bear, and does nothing if you are already in a form, so a second press cannot drop you out of it." },
  rejuv = { "m", "Leave form, then Rejuvenation", "#showtooltip Rejuvenation\n/cancelform [form]\n/cast [noform,help,nodead][noform,@player] Rejuvenation", "In an animal form the first press leaves the form; the next press casts. Out of form it casts at once." },
  touch = { "m", "Healing Touch under the mouse", "#showtooltip Healing Touch\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Touch", "Heals the friend under your mouse, then your friendly target, then you. Your target does not change." },
  rejuvMo = { "m", "Rejuvenation under the mouse", "#showtooltip Rejuvenation\n/cast [@mouseover,help,nodead][help,nodead][@player] Rejuvenation", "The heal over time, same order: mouse, target, you." },
  regrowth = { "m", "Regrowth under the mouse", "#showtooltip Regrowth\n/cast [@mouseover,help,nodead][help,nodead][@player] Regrowth", "The quick heal with a heal over time behind it, same order." },
  prowl = { "m", "Prowl that stays on", "#showtooltip Prowl\n/cast [nostealth] Prowl", "Goes into Prowl in Cat Form, and does nothing if you are already hidden." },
  growl = { "m", "Growl under the mouse", "#showtooltip Growl\n/cast [@mouseover,harm,nodead][] Growl", "Taunts the enemy under your mouse without changing your target; otherwise your target. Bear Form only." },
  decurse = { "m", "Remove Curse under the mouse", "#showtooltip Remove Curse\n/cast [@mouseover,help,nodead][help,nodead][@player] Remove Curse", "Write Abolish Poison instead for a second button." },
  rebirth = { "m", "Rebirth under the mouse", "#showtooltip Rebirth\n/cast [@mouseover,help,dead][help,dead] Rebirth", "Brings back the dead friend you point at during a fight. It does nothing unless that friend is dead." },
  innervate = { "m", "Innervate under the mouse", "#showtooltip Innervate\n/cast [@mouseover,help,nodead][help,nodead][@player] Innervate", "Innervate on the healer you point at; with nobody picked, on you." },
  swift = { "m", "Nature's Swiftness, then the big heal", "#showtooltip Healing Touch\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Touch", "Nature's Swiftness (a Restoration talent) is not on the global cooldown, so the instant heal goes out on the same press.", "e" },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]\n/startattack", "Point at the tank (or target them) and press: you take their target and start attacking it." },
  focusRoots = { "m", "Root your focus", "#showtooltip Entangling Roots\n/cast [@focus,harm,nodead][] Entangling Roots", "Roots your focus target again if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("DRUID", {
  overview = {
    [1] = {
      { "h", "What a Druid is" },
      { "p", "A Druid changes shape. As yourself you cast nature spells and heal. As a bear you take hits like a Warrior. As a cat you fight like a Rogue. You learn the shapes one by one as you level." },
      { "p", "It is the most flexible class in the game. The cost is that each shape has its own buttons, and you cannot cast spells while you are an animal." },
    },
    [2] = {
      { "h", "What a Druid is" },
      { "p", "Each form has its own resource: Mana as yourself, Rage as a bear, Energy as a cat. Changing form costs Mana. Most of playing a Druid well is choosing the right form for the next ten seconds." },
    },
    [3] = {
      { "h", "Where a Druid fits" },
      { "p", "Restoration heals with heal-over-time spells. Feral tanks as a bear or deals melee damage as a cat, often both in one dungeon. Balance casts. Every Druid brings Mark of the Wild, a resurrection that works during a fight, and Innervate." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "You cannot cast in animal forms, and changing form costs real Mana. There are no separate specializations for bear and cat: both are Feral, and one set of talents covers both. A dungeon has one difficulty: no heroic, no mythic." },
      { "f", "There is no Berserk. Lacerate is a Feral talent, not something every Druid trains." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Night Elf. Horde: Tauren." },
      { "f", "Alliance: Night Elf and High Order Skyborne. Horde: Tauren and Windshaper Skyborne." },
      { "f", "Skyborne Druids of both factions start on Zephras Isle. Players report spirit quests there for a Windborne Cat form and an Ursera form. Follow your quest log." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Until level 10 you are a caster: Wrath from far away, Moonfire, and Healing Touch or Rejuvenation on yourself when you are hurt. At level 10 your trainer sends you on a quest for Bear Form. Do it at once." },
      { "p", "As a bear, just attack and press Maul when you have Rage. If you are losing, change back, heal yourself, and change into a bear again." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Feral. Bear Form carries you until you get Cat Form, and from then on you fight as a cat and heal as yourself between fights. You will almost never need to eat or drink." },
      { "p", "Collect your forms as they come: the water form and the travel form save hours. Keep Mark of the Wild and Thorns on yourself." },
    },
    [3] = {
      { "h", "Leveling another Druid" },
      { "p", "A Feral Druid can tank a dungeon as a bear and heal it as yourself with the same talents, so you fill whichever place the group is missing. Out in the world, open from Prowl and use your travel form between enemies." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Gear made for Druids is rare. Expect to wear a mix of leather meant for Rogues and for casters." },
      { "e", "The weapon you hold adds nothing to your attacks in a form, and most items cannot be used while shapeshifted." },
    },
    all = {
      { "e", "Cat Form is trained at level 20, and a Druid has no way to bring back a dead player outside a fight: only Rebirth, on a long cooldown." },
      { "f", "Revive is trained at level 12 and brings back a dead player outside a fight. Nature's Grasp is trained at 10 and Omen of Clarity at 20. Attacks in a form use the damage of the weapon you have equipped." },
      { "f", "Players report that Cat Form now comes from a quest in Moonglade at level 20. Ask your trainer when you reach it." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Druid trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs. Some forms come from quests your trainer gives you." },
      { "p", "From level 10 you get talent points for three trees: Balance for casting, Feral Combat for bear and cat, Restoration for healing." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy the abilities of the forms you use and your heals. If you level as Feral you can skip most new ranks of Wrath and Starfire. Feral Combat is the usual leveling tree." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Restoration: stronger heals over time and Swiftmend. Feral Combat: bear and cat in one tree. Balance: spell damage from a distance." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "Healing is built on Rejuvenation, Regrowth and Healing Touch; Feral is Shred or Claw into Ferocious Bite as a cat, and Maul and Swipe as a bear. Do not expect the modern toolkit." },
    },
    all = {
      { "h", "Forms" },
      { "p", "Bear Form for taking hits, Cat Form for melee damage and stealth, a water form for swimming and a travel form for speed outdoors. In a form you can use only that form's abilities." },
      { "e", "Entangling Roots works outdoors only, and Faerie Fire has a separate Feral version from the talent tree. Nature's Grasp and Omen of Clarity are talents." },
      { "f", "More works while you are in a form: many consumables, object interactions, racial abilities and weapon effects. Not everything does; some Engineering items still do not. Entangling Roots works indoors, and Faerie Fire can be used in bear and cat form." },
      { "f", "Primal Bite and Shifting Power are separate deep Feral choices. Furor is now in the Feral tree and Heart of the Wild in Restoration. Balance has Eclipse, and Restoration has Bloom and Wild Growth." },
      { "h", "Swiftmend" },
      { "e", "Swiftmend, the deep Restoration talent, uses up your Rejuvenation or Regrowth on the target to heal at once." },
      { "f", "Swiftmend needs your own Regrowth or Rejuvenation on the target, and it does not use it up." },
      { "h", "Trainers" },
      { "p", "Any Druid trainer teaches the same spells. In the capitals: Mathrengyl Bearwalker in Darnassus, Turak Runetotem in Thunder Bluff. Turn on Class trainers in the map's Places menu to see the ones near you." },
      { "e", "Druids can also teleport to Moonglade, where a trainer teaches both factions." },
      { "f", "Skyborne on Zephras Isle: Xyton Silverwind and Naeluna Swiftmend early on, Lotheluum Starbreeze in Valanaar." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "As yourself: 1. Wrath from far away. 2. Moonfire once. 3. More Wrath. As a bear: 1. Attack. 2. Maul when the red bar has Rage in it." },
      { "p", "Hurt? Change back to yourself, cast Rejuvenation and Healing Touch, and change into a bear again." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Cat: open from Prowl when you can, build combo points with Claw (or Shred from behind), and spend them on Rip for a long fight or Ferocious Bite for a short one. Bear for anything that hits too hard: Maul, Swipe on groups, Bash to stop a cast." },
      { "p", "Between fights, change out, put Rejuvenation on yourself, and go again." },
    },
    [3] = {
      { "h", "Tanking a dungeon" },
      { "p", "Bear Form: Maul on the main target, Swipe to hold the others, Demoralizing Roar on a pack, Growl to take one enemy back. Bears hold several enemies less easily than they hold one, so ask the group to follow your target." },
      { "h", "Healing a dungeon" },
      { "p", "Rejuvenation on the tank at the pull, Regrowth when damage rises, Healing Touch for the big hits. Heal-over-time spells make little threat and let you move, so cast them early." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Healer: Rejuvenation on tanks and on anyone taking steady damage, Healing Touch at the rank the damage needs, Innervate on the healer who will run dry first, and Rebirth saved for a tank or healer." },
      { "p", "Cat: Shred from behind is your builder; keep Faerie Fire on the boss and spend on Ferocious Bite. Bear: Maul every swing you have Rage for, Swipe with the rest." },
      { "e", "Only one Druid's Rejuvenation and Regrowth fit on a target and debuff slots are limited, so Rip and Rake are often left off. Cats change out and back into form to refill Energy through Furor." },
      { "f", "Predatory Discipline changes what Ferocious Bite does with spare Energy, so check your talents before pooling for it. Wild Growth has a 3-second cast: start it before the damage lands." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.heal, M.bear },
    [2] = { { "h", "For the road" }, M.bear, M.rejuv, M.prowl },
    [3] = { { "h", "For dungeons" }, M.touch, M.rejuvMo, M.regrowth, M.decurse, M.growl, M.rebirth },
    [4] = { { "h", "A raid set" }, M.touch, M.rejuvMo, M.regrowth, M.decurse, M.rebirth, M.innervate, M.growl, M.focusRoots, M.swift, M.assist },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Tell the group which job you are doing: tank as a bear, healer as yourself, or damage as a cat. Cast Mark of the Wild on everyone at the start. If someone is about to die and you are not the healer, changing out to heal them is still the right call." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "You can tank or heal any leveling dungeon in Feral talents; carry a few pieces of Intellect gear for healing. As a bear, pull with Faerie Fire or Moonfire and change form as the enemies arrive. As a healer, never fight in a form: you cannot heal from it." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Groups value a Druid who can switch: tank one pull, heal the next after a death, bring someone back in the middle of a fight. Keep two sets of gear with you and learn each dungeon from the tank's and the healer's side." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. Raid Druids mostly heal, and bring what no one else can: a resurrection during a fight and Innervate. Feral and Balance work, with more effort and more unusual gear than the pure damage classes." },
      { "e", "Classic raids are 20 and 40 players. Each Druid's Mark of the Wild and Thorns are cast by hand, group by group." },
    },
  },
})
