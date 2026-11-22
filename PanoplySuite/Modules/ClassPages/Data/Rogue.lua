-- Panoply Suite 0.8.4 class pages: the Rogue. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Rogue article S11, the
-- launch notes S14, the class comparison C4, weapon trainers S22), read 8 Nov 2026 and NOT checked in the live game.
-- Corrections that must stay: Sap does not break Stealth; Venom is a passive set off by Shank, not a finisher you press.
-- The research found no clean record of Forever-only Rogue class quests, so none is named.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  strike = { "m", "Sinister Strike", "#showtooltip Sinister Strike\n/startattack\n/cast Sinister Strike", "Starts your attack and uses Sinister Strike. Pressing it again never stops your attack." },
  stealth = { "m", "Stealth that stays on", "#showtooltip Stealth\n/cast [nostealth] Stealth", "Goes into Stealth, and does nothing if you are already hidden, so a second press cannot reveal you." },
  gouge = { "m", "Gouge", "#showtooltip Gouge\n/stopattack\n/cast Gouge", "Stops your own attack first, so your next swing does not wake the enemy up." },
  kick = { "m", "Kick under the mouse", "#showtooltip Kick\n/cast [@mouseover,harm,nodead][] Kick", "Interrupts the enemy under your mouse without changing your target; otherwise your target." },
  sap = { "m", "Sap under the mouse", "#showtooltip Sap\n/cast [@mouseover,harm,nodead][] Sap", "Saps the enemy you point at, so your target stays on the one you mean to fight." },
  blind = { "m", "Blind under the mouse", "#showtooltip Blind\n/stopattack\n/cast [@mouseover,harm,nodead][] Blind", "Blinds the enemy you point at and stops your attack so you do not break it." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]\n/startattack", "Point at the tank (or target them) and press: you take their target and start attacking it." },
  flurry = { "m", "Blade Flurry with a trinket", "#showtooltip Blade Flurry\n/use 13\n/cast Blade Flurry", "Uses the trinket in your top trinket slot, then Blade Flurry (a Combat talent).", "e" },
  poison = { "m", "Poison the main hand", "#showtooltip\n/use Instant Poison\n/use 16", "Applies the poison to your main-hand weapon. Change the name to the rank you carry; 17 instead of 16 is the off hand.", "e" },
  focusKick = { "m", "Kick your focus", "#showtooltip Kick\n/cast [@focus,harm,nodead][] Kick", "Interrupts your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("ROGUE", {
  overview = {
    [1] = {
      { "h", "What a Rogue is" },
      { "p", "A Rogue fights up close with light weapons and can turn invisible to enemies with Stealth. Your attacks cost Energy, a yellow bar that refills by itself in a few seconds. Some attacks add combo points to the enemy; a finishing move spends them for a big effect." },
      { "p", "Rogues kill fast but wear leather and have no healing. You choose your fights, open from Stealth, and leave when it goes wrong." },
    },
    [2] = {
      { "h", "What a Rogue is" },
      { "p", "Energy sets the pace: you always have something to press, never everything. Builders make combo points, finishers spend them. Stealth gives you the opener and the choice of when a fight starts, and Gouge, Kick, Evasion and Sprint are how you survive it." },
    },
    [3] = {
      { "h", "Where a Rogue fits" },
      { "p", "Rogues deal melee damage in every tree. Combat is steady damage, Assassination is big finishers and poisons, Subtlety is Stealth and control. In groups you also Sap, interrupt, open locks and disarm traps." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "Combo points live on the enemy, not on you: change target and they are gone. Energy comes back in ticks, so pooling it matters. Poisons are items you buy or make and put on your weapons by hand. A dungeon has one difficulty: no heroic, no mythic." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Human, Dwarf, Night Elf, Gnome. Horde: Orc, Undead, Troll." },
      { "f", "Alliance: Human, Dwarf, Night Elf, Gnome and High Order Skyborne. Horde: Orc, Undead, Troll and Windshaper Skyborne." },
      { "f", "Skyborne Rogues of both factions start on Zephras Isle and leave it around level 12." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Walk up and use Sinister Strike until the enemy has a few combo points on it (the dots by its portrait), then use Eviscerate. Repeat." },
      { "p", "When you learn Stealth, start every fight from it. If a fight goes badly, Evasion makes most attacks miss you for a while. Eat after fights, and learn First Aid for bandages." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Combat with the best slow one-handed weapon you can find in your main hand; swords are the usual choice. Combat talents add hit chance and Energy, and both make every fight shorter." },
      { "p", "Open from Stealth, keep Slice and Dice running on longer fights, Gouge and bandage when you are hurt, and Kick every heal. Poisons and lockpicking are worth having as soon as your trainer offers them." },
    },
    [3] = {
      { "h", "Leveling another Rogue" },
      { "p", "Stealth lets you skip what other classes must fight: walk past guards to the quest target, pick pockets on the way, and open lockboxes for a little income. Two enemies at once is your limit unless Evasion is ready." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Misses hurt: a missed opener or a dodged builder is Energy gone. Leveling is fast when things go right and a corpse run when they do not, because you have no self-healing beyond food and bandages." },
    },
    all = {
      { "e", "Using Sap takes you out of Stealth unless you have the Improved Sap talent." },
      { "f", "Sap does not break Stealth, so you can Sap one enemy and still open on another from Stealth. Poised is trained at level 18 and Shank at 24." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Rogue trainer sells your abilities, usually every two levels. Talents & spells lists what to buy at each visit and what it costs." },
      { "p", "From level 10 you get talent points for three trees: Assassination, Combat and Subtlety." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy your builders, finishers, Kick, Gouge, Sprint and Evasion as they come. You can skip ranks of openers you never use. Combat is the usual leveling tree." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Combat: weapon talents and steady, sustained damage. Assassination: stronger finishers and poisons. Subtlety: better Stealth, openers and escapes." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "No Roll the Bones, no Shadow Dance loop. The damage rotation is a builder, Slice and Dice, and a finisher. The depth is in Energy timing and in the things only a Rogue can do for a group." },
    },
    all = {
      { "h", "Weapons, poisons and locks" },
      { "p", "Some attacks need a dagger, and Backstab also needs you to be behind the enemy. Poisons go on your weapons and wear off; carry spares. Lockpicking has its own skill number that you raise by opening locks." },
      { "e", "Rogues use daggers, swords, maces and fist weapons. A poison takes the place of any other temporary effect on that weapon, such as a sharpening stone." },
      { "f", "Rogues can also train one-handed axes at a weapon master. Poisons now sit alongside other temporary weapon effects and have charges." },
      { "f", "Shank comes at level 24, with another rank at 44. Venom is a passive that Shank sets off; it is not a finisher you press. Mutilate is the deep Assassination talent." },
      { "h", "Trainers" },
      { "p", "Any Rogue trainer teaches the same abilities. In the capitals: Osborne the Night Man in Stormwind's Old Town, Shenthul in Orgrimmar's Cleft of Shadow. Turn on Class trainers in the map's Places menu to see the ones near you." },
      { "f", "Skyborne on Zephras Isle: Akeri Duskblade and Miriaan Mistblade early on, Eltheen Nightbreeze in Valanaar." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Sinister Strike until the enemy has three or more combo points. 2. Eviscerate. 3. Start again." },
      { "p", "If the yellow bar is empty, wait a second. It refills by itself." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Open from Stealth: Cheap Shot or Garrote when you have them, Ambush if you carry a dagger. Build with Sinister Strike. On a fight that will last, spend the first combo points on Slice and Dice, then the rest on Eviscerate." },
      { "p", "Kick spell casts. When you are losing, Gouge and step back to bandage, or use Evasion and finish it." },
    },
    [3] = {
      { "h", "In dungeons" },
      { "p", "Sap the marked enemy before the pull. Stand behind the target: enemies cannot parry or block from behind, and Backstab needs it. Keep Slice and Dice up all the time, build, and spend the rest on Eviscerate." },
      { "p", "Use Feint before you need it, not after the enemy has turned to you. Kick is often worth more than your damage." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Slice and Dice never drops. Sinister Strike or Backstab to build; five-point Eviscerate with what is left. Feint on cooldown on fights where threat is tight." },
      { "e", "Use Blade Flurry and Adrenaline Rush together early, and again whenever they are ready. Vanish wipes your threat if you can afford the lost seconds." },
      { "e", "With limited debuff slots on a Classic boss, Rupture and Garrote are usually left off, and one Rogue may be asked to keep Expose Armor up instead of Eviscerate." },
      { "f", "Expose Armor no longer stops a Warrior's Sunder Armor from making threat, and Feint removes more threat than before." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.strike, M.stealth },
    [2] = { { "h", "For the road" }, M.strike, M.stealth, M.gouge, M.kick },
    [3] = { { "h", "For dungeons" }, M.stealth, M.sap, M.kick, M.gouge, M.blind, M.assist },
    [4] = { { "h", "A raid set" }, M.assist, M.kick, M.focusKick, M.sap, M.blind, M.gouge, M.flurry, M.poison },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Attack what the tank is attacking, from behind it. Do not run ahead in Stealth and start fights. If an enemy turns to you, stop attacking for a moment and let the tank take it back." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "Your jobs: damage, Sap on a humanoid before the pull when the group asks, and Kick on healers and casters. Tell the group you can open locked chests and doors." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Know which enemies can be sapped and which casts must be kicked in each dungeon. Carry poisons, bandages and a way to escape; a dead Rogue does no damage, and healers heal you last." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. Melee take real damage from boss abilities here and are healed after the tanks, so positioning, bandages and potions are part of your damage. Threat is the other ceiling: watch it." },
      { "e", "Classic raids are 20 and 40 players. Windfury Totem or a Warrior's Battle Shout in your party changes your damage more than most gear, so raid leaders group melee together." },
    },
  },
})
