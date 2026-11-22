-- Panoply Suite 0.8.4 class pages: the Mage. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Mage article S10, the
-- launch notes S14, the 6 Nov hotfixes S15, the class comparison C7, the race table S1), read 8 Nov 2026 and NOT checked in the
-- live game. Corrections that must stay: after the quest only Study remains (there is no Research to press); Ice Lance shares an
-- 8-second cooldown with Fire Blast. The level-20 study quest givers (Garion Wendell, Owen Thadd) are player reports (S16) and are
-- worded as such. "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  nova = { "m", "Frost Nova, right now", "#showtooltip Frost Nova\n/stopcasting\n/cast Frost Nova", "Drops whatever you were casting and freezes the enemies next to you in place. Then walk away from them." },
  intellect = { "m", "Buff a friend, or me", "#showtooltip Arcane Intellect\n/cast [help,nodead][@player] Arcane Intellect", "Arcane Intellect on the friend you have targeted; otherwise on you." },
  sheep = { "m", "Polymorph under the mouse", "#showtooltip Polymorph\n/cast [@mouseover,harm,nodead][] Polymorph", "Sheeps the enemy you point at, so your target can stay on the one you are killing." },
  counter = { "m", "Counterspell, right now", "#showtooltip Counterspell\n/stopcasting\n/cast [@mouseover,harm,nodead][] Counterspell", "Drops your own cast and interrupts the enemy under your mouse, or your target. Stopping your cast is on purpose: the interrupt cannot wait." },
  decurse = { "m", "Remove a curse under the mouse", "#showtooltip Remove Lesser Curse\n/cast [@mouseover,help,nodead][help,nodead][@player] Remove Lesser Curse", "Removes a curse from the friend under your mouse, then your friendly target, then you." },
  blink = { "m", "Blink, right now", "#showtooltip Blink\n/stopcasting\n/cast Blink", "Drops your cast and Blinks. For the moment something is about to land on you." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]", "Point at the tank (or target them) and press: you take their target." },
  power = { "m", "Arcane Power with a trinket", "#showtooltip Arcane Power\n/use 13\n/cast Arcane Power", "Uses the trinket in your top trinket slot, then Arcane Power (an Arcane talent). The trinket is not a spell, so both go on one press.", "e" },
  focusCounter = { "m", "Counterspell your focus", "#showtooltip Counterspell\n/stopcasting\n/cast [@focus,harm,nodead][] Counterspell", "Interrupts your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
  focusSheep = { "m", "Polymorph your focus", "#showtooltip Polymorph\n/cast [@focus,harm,nodead][] Polymorph", "Re-sheeps your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("MAGE", {
  overview = {
    [1] = {
      { "h", "What a Mage is" },
      { "p", "A Mage stands back and casts spells of fire, frost and arcane. You wear cloth and die quickly if enemies reach you, so you stop them: freeze them in place, slow them, or turn one into a sheep." },
      { "p", "You use Mana, the blue bar, and you make your own food and water, so you never pay to refill it." },
    },
    [2] = {
      { "h", "What a Mage is" },
      { "p", "High damage, strong control and the best travel in the game: Blink now, teleports and portals to the capitals later. The price is being fragile and tied to your Mana bar. Frost Nova, Polymorph and Counterspell are as important as your damage spells." },
    },
    [3] = {
      { "h", "Where a Mage fits" },
      { "p", "Mages deal spell damage in all three trees and are the best class at damaging many enemies at once. In groups you also Polymorph, remove curses, hand out water and food, and open portals when the run is over." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "Mana is the real limit on your damage. Spell ranks exist: you train higher ranks as you level. Bosses can be immune to a whole school of magic. A dungeon has one difficulty: no heroic, no mythic." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Human and Gnome. Horde: Undead and Troll." },
      { "f", "Alliance: Human, Gnome and High Order Skyborne. Horde: Orc (new), Undead and Troll. Only High Order Skyborne can be Mages; Windshapers cannot." },
      { "f", "High Order Skyborne Mages start on Zephras Isle and leave it around level 12." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Cast Fireball at an enemy from as far away as you can. Keep casting as it walks to you. If it reaches you with health left, Frost Nova freezes it in place: step back and finish it." },
      { "p", "Sit and drink after every fight or two. Make your own water and food with Conjure Water and Conjure Food. Keep Frost Armor and Arcane Intellect on yourself." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Frost. Frostbolt slows the enemy, so most die before they touch you, and the Frost tree adds survival that the other trees lack. Polymorph a second enemy rather than fighting two." },
      { "p", "Buy every rank of your main spell and of Conjure Water. Wands finish off low enemies for free." },
    },
    [3] = {
      { "h", "Leveling another Mage" },
      { "p", "With Frost talents a Mage can gather a group of enemies that fight in melee, freeze them, and kill them all together with Blizzard and Arcane Explosion. It is the fastest way any class levels, and it takes practice and the right spots." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Drinking is part of the class: your Mana does not last and does not come back while you cast. Enemies resist spells, some fully. You have no pet and no healing, so a bad pull is a death." },
    },
    all = {
      { "f", "Frostfire Bolt is trained at level 40 and works with both the Fire and the Frost trees." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Mage trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs. Teleports and portals come from a separate portal trainer in each capital." },
      { "p", "From level 10 you get talent points for three trees: Arcane, Fire and Frost." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy your main damage spell, Frost Nova, Polymorph, Counterspell, Blink and the Conjure spells. If you level as Frost you can skip most new ranks of Fireball. Frost is the usual leveling tree." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Frost: control, survival and steady damage. Fire: the highest damage where enemies are not immune to fire. Arcane: Mana and burst, and good supporting talents for either." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "You pick the school for the dungeon and build your talents around it. Changing your mind means a visit to your trainer." },
      { "e", "Nothing lights up to decide your next cast: you choose one main spell and cast it well." },
    },
    all = {
      { "h", "Worth knowing" },
      { "p", "Polymorph breaks on damage and heals the sheep, so use it on an enemy nobody will touch. Counterspell locks the school it interrupts for several seconds. Fire Blast is your instant spell for finishing or for casting while you move." },
      { "e", "Ignite is one shared debuff on the enemy: several Fire Mages feed the same one." },
      { "f", "Ignite belongs to each caster. New in the trees: Arcane Blast and Missile Barrage for Arcane, Heating Up for Fire, Ice Lance and Fingers of Frost for Frost. Ice Lance shares an 8-second cooldown with Fire Blast, so you get one or the other." },
      { "f", "Comprehension is a small Mage-only trade skill with Comprehend Scroll. After its quest the action you keep is called Study. Older guides that tell you to use Research are out of date; there is no such button now." },
      { "f", "Players report that the level-20 quest for it starts with Garion Wendell in Stormwind or Owen Thadd in the Undercity. Ask your trainer when you reach 20." },
      { "h", "Trainers" },
      { "p", "Any Mage trainer teaches the same spells. In the capitals: Jennea Cannon in Stormwind's Mage Quarter, Anastasia Hartwell in the Undercity's Magic Quarter. Turn on Class trainers and Portal trainers in the map's Places menu to see the ones near you." },
      { "f", "High Order Skyborne on Zephras Isle: Dorii Brightwhisper and Shenaan Spellwind early on, Anathamaas Aetherwind in Valanaar." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Fireball from far away, again and again. 2. If the enemy reaches you: Frost Nova, then step back. 3. Fire Blast to finish it. 4. Drink." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Frostbolt from maximum range and keep casting; the slow does the work. Frost Nova when it arrives, step back two paces, and carry on. Fire Blast or a wand to finish. Polymorph the second enemy before you start on the first." },
    },
    [3] = {
      { "h", "In dungeons" },
      { "p", "Let the tank have the enemies for a few seconds, then cast your main spell at the kill target. Area spells only when the tank has the whole pack and nothing is sheeped nearby. Counterspell healers and dangerous casts." },
      { "p", "If an enemy comes for you, do not run away from the group: Frost Nova and walk to the tank." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Cast your main spell without gaps and never stand still for nothing: every second not casting is the loss. Use your trinkets and talent cooldowns together and early. Evocation and Mana gems are planned, not saved. Watch threat after big critical hits." },
      { "e", "Many early Classic raid bosses are immune or resistant to fire, so raids start as Frost; Fire takes over where it is allowed. With limited debuff slots, your Mage group agrees who applies what." },
      { "f", "Arcane Blast builds a stacking bonus to your spell damage and a rising Mana cost for 18 seconds, so Arcane is played in bursts. Fire Blast and Ice Lance compete for the same 8-second cooldown." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.nova, M.intellect },
    [2] = { { "h", "For the road" }, M.nova, M.sheep, M.counter },
    [3] = { { "h", "For dungeons" }, M.sheep, M.counter, M.decurse, M.nova, M.blink },
    [4] = { { "h", "A raid set" }, M.assist, M.counter, M.focusCounter, M.sheep, M.focusSheep, M.decurse, M.blink, M.power },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Wait until the tank has hit the enemy, then cast at the same enemy. If asked to sheep something, Polymorph it before the fight and do not damage it. Hand out water to anyone with a Mana bar." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "Your jobs: damage, Polymorph on a marked enemy, and re-sheeping it when it breaks. Frost Nova near the tank holds a pack in place, but a frozen enemy that is not on the tank will hit whoever is closest when it thaws." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Know which enemies can be sheeped (humanoids and beasts) and which pulls are safe for area damage. Remove curses without being asked. Bring the reagents for portals and for group buffs." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. A raid Mage casts one spell for minutes, keeps threat under the tank's, removes curses, and makes water for the whole raid before the first pull." },
      { "e", "Classic raids are 20 and 40 players." },
    },
  },
})
