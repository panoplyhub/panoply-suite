-- Panoply Suite 0.8.4 class pages: the Warrior. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's class article S9, the launch
-- notes S14, the class comparison C1), read 8 Nov 2026 and NOT checked in the live game. The two quest names on Zephras Isle are
-- player reports (S16) and are worded as such. "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  strike = { "m", "Start the fight", "#showtooltip Heroic Strike\n/startattack\n/cast Heroic Strike", "Starts swinging and queues Heroic Strike on your next swing. Safe to press again and again: it never stops your attack." },
  charge = { "m", "Charge", "#showtooltip Charge\n/cast Charge\n/startattack", "Charges and starts your attack on arrival." },
  overpower = { "m", "Overpower from any stance", "#showtooltip Overpower\n/cast [stance:1] Overpower; Battle Stance", "In Battle Stance it uses Overpower. In another stance the first press goes to Battle Stance and the next press uses Overpower." },
  taunt = { "m", "Taunt under the mouse", "#showtooltip Taunt\n/cast [@mouseover,harm,nodead][] Taunt", "Taunts the enemy under your mouse without changing your target; with nothing under the mouse, your target." },
  interrupt = { "m", "Interrupt for your stance", "#showtooltip\n/cast [stance:3] Pummel; Shield Bash", "Pummel in Berserker Stance, Shield Bash in the other two (it needs a shield)." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]\n/startattack", "Point at the tank (or target them) and press: you take their target and start attacking it." },
  reck = { "m", "Recklessness with a trinket", "#showtooltip Recklessness\n/use 13\n/cast Recklessness", "Uses the trinket in your top trinket slot, then Recklessness. The trinket is not a spell, so both go on one press." },
  focusKick = { "m", "Interrupt your focus", "#showtooltip Pummel\n/cast [@focus,harm,nodead][] Pummel", "Pummels your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("WARRIOR", {
  overview = {
    [1] = {
      { "h", "What a Warrior is" },
      { "p", "A Warrior fights up close with weapons and heavy armor. You hit things, things hit you, and the hits fill a red bar called Rage. Rage is what your attacks cost. It starts empty and drains away when you stop fighting." },
      { "p", "Warriors are simple to start and strong with good gear, but they are the slowest class to level alone. You have no healing of your own, so you will eat between fights and carry bandages." },
    },
    [2] = {
      { "h", "What a Warrior is" },
      { "p", "Rage in, damage out. A Warrior has three stances, and each one allows different abilities: Battle for general fighting, Defensive for tanking, Berserker for damage. Most of the skill is knowing which stance holds the button you want." },
      { "p", "Your power follows your weapon more than any other class. A new weapon is a bigger jump than several levels." },
    },
    [3] = {
      { "h", "Where a Warrior fits" },
      { "p", "Protection Warriors are the standard dungeon and raid tanks. Arms and Fury deal damage, and at high gear levels they are among the best at it. A leveling Arms Warrior can tank most dungeons with a shield and Defensive Stance." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "Rage is earned, not handed out: an empty bar at the pull is normal, and tanks who take no damage have no Rage. Abilities are locked to stances and changing stance costs most of your Rage unless you have Tactical Mastery. There are no heroic or mythic dungeons here; a dungeon has one difficulty." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Human, Dwarf, Night Elf, Gnome. Horde: Orc, Undead, Tauren, Troll." },
      { "f", "Alliance: Human, Dwarf, Night Elf, Gnome and High Order Skyborne. Horde: Orc, Undead, Tauren, Troll and Windshaper Skyborne." },
      { "f", "Skyborne Warriors of both factions start on Zephras Isle and leave it around level 12. Players report class quests there called The Warrior's Path (about level 2) and The Skybreaker Bulwark (about level 10). Follow your quest log." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Fight one enemy at a time. Open with Charge when you have it, keep attacking, and press Heroic Strike when the Rage bar has plenty in it." },
      { "p", "After a fight, sit and eat if your health is under half. Learn First Aid from a trainer in any big town: bandages are a Warrior's healing." },
      { "p", "Every two levels, visit a Warrior trainer and buy what is new. Buy the best weapon you can afford before anything else." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Arms with a slow two-handed weapon. Slow weapons make each Rage ability hit harder, and Arms talents make the long road smoother." },
      { "p", "Pull carefully. Two enemies at your level is a hard fight and three is usually a death. Keep First Aid and a stack of food current, and replace your weapon every few levels through quests, dungeons or the auction house." },
      { "p", "Do your class quests: the one for Defensive Stance and the later one for Berserker Stance open half of your abilities." },
    },
    [3] = {
      { "h", "Leveling another Warrior" },
      { "p", "Dungeons are the fast lane: a Warrior who is willing to tank never waits long for a group, and dungeon weapons carry you for many levels. With a healer friend you can fight several enemies at once and level far faster than alone." },
      { "p", "Send your Warrior weapons and bandage cloth from your other characters. The class is gear-starved when poor and a different class when fed." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Leveling is the slow part of this game and Warrior is the slowest class at it. There is no self-healing worth the name, and misses and dodges starve you of Rage. Weapon skill matters: a weapon type you have not trained up misses constantly." },
    },
    all = {
      { "f", "The Rage you get from being hit is no longer cut by your armor or by absorb shields, so a well-armored Warrior is not starved. Victory Rush is trained at level 20." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "You do not get new abilities by leveling alone. A Warrior trainer sells them, usually every two levels. Talents & spells lists what to buy at each visit and what it costs." },
      { "p", "From level 10 you also get one talent point a level. Talents are small permanent bonuses in three trees: Arms, Fury and Protection." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy every damage ability and every stance ability as it comes. You can skip ranks of things you do not use while leveling, such as the shield abilities if you never tank." },
      { "p", "Arms is the usual leveling tree. Fury is for two weapons and good gear; Protection is for tanking and levels slowly alone." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Arms: one big weapon, Mortal Strike, strong in small fights. Fury: Bloodthirst, built for sustained damage. Protection: Shield Slam and the talents that hold threat and keep you alive." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "No Mastery stat and no talent rows to swap between pulls. A build is spent point by point, and changing it means a visit to your trainer." },
    },
    all = {
      { "h", "Stances" },
      { "p", "Battle Stance is where you start. Defensive Stance and Berserker Stance come from class quests your trainer gives you. Each stance has abilities that work only in it." },
      { "e", "Changing stance empties your Rage unless you have points in Tactical Mastery, an Arms talent. Recklessness, Retaliation and Shield Wall share one long cooldown: using one locks the other two." },
      { "f", "Tactical Mastery is trained at level 14 instead of being a talent. Recklessness, Retaliation and Shield Wall no longer share a cooldown. Thunder Clap works in Defensive Stance." },
      { "h", "Trainers" },
      { "p", "Any Warrior trainer teaches the same abilities. In the capitals: Ander Germaine in Stormwind's Old Town, Sorek in Orgrimmar's Valley of Honor. Turn on Class trainers in the map's Places menu to see the ones near you." },
      { "f", "Skyborne on Zephras Isle: Blademaster Ren and Corsan Earthrazer early on, Seena Skybreaker in Valanaar." },
      { "p", "Weapon masters are separate from class trainers: they teach you to use a kind of weapon, not abilities." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Charge in. 2. Keep attacking. 3. When the red bar is at least a quarter full, press Heroic Strike. 4. When the enemy is nearly dead and Execute lights up, press Execute." },
      { "p", "That is enough for a long time. If you have no Rage, just keep swinging: the bar fills as you hit and get hit." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Charge, then Rend on enemies that will live a while. Spend Rage on your main strike. Press Overpower every time the enemy dodges: it is cheap and cannot be dodged. Finish with Execute under a fifth of the enemy's health." },
      { "p", "Against casters, save Rage for your interrupt. Use Hamstring on enemies that run." },
    },
    [3] = {
      { "h", "Tanking a dungeon" },
      { "p", "Defensive Stance and a shield. Sunder Armor on the main target until the group's damage is settled, Revenge every time it lights up, Shield Block when the hits are heavy. Taunt takes one enemy back; Demoralizing Shout takes the edge off a pack." },
      { "e", "Thunder Clap needs Battle Stance, so tanks rarely use it." },
      { "f", "Thunder Clap works in Defensive Stance and is a normal part of holding a pack." },
      { "h", "Dealing damage" },
      { "p", "Arms: Mortal Strike whenever it is ready, Whirlwind next, Heroic Strike only with Rage to spare, Execute at the end. Fury: the same order with Bloodthirst in place of Mortal Strike." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Damage: Bloodthirst or Mortal Strike on cooldown, then Whirlwind, with Heroic Strike (Cleave on two targets) as the Rage dump once the bar is high. Under 20% it becomes Execute. Watch threat: you can out-threat the tank here, and there is no button that fixes it." },
      { "p", "Tank: Shield Slam, Revenge and Sunder Armor for threat, Shield Block against crushing blows, Heroic Strike with spare Rage. Threat from the first seconds decides how hard the raid can hit." },
      { "f", "The launch notes raise threat from Defensive Stance and Defiance, and Sunder Armor keeps making threat when a Rogue's stronger Expose Armor is on the target." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.strike, M.charge },
    [2] = { { "h", "For the road" }, M.strike, M.charge, M.overpower },
    [3] = { { "h", "For dungeons" }, M.charge, M.overpower, M.taunt, M.interrupt, M.assist },
    [4] = { { "h", "A raid set" }, M.taunt, M.interrupt, M.focusKick, M.assist, M.overpower, M.reck },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "If you are the tank, you go first and everyone else waits for you. If you are not the tank, attack what the tank is attacking and nothing else." },
      { "p", "Tell the group if you are new to a dungeon. People are patient with a player who says so." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "You will be asked to tank. Carry a one-handed weapon and a shield, go to Defensive Stance, and mark or call the target you want killed first. Give the healer time to drink before each pull." },
      { "p", "As damage, do not open before the tank has hit the enemy, and stand behind it so it cannot parry or block you." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Tanks: learn each pull, use line of sight to gather casters, and keep Battle Shout up for the melee. Damage Warriors: bring your own bandages and potions, and stop attacking when you are close to pulling the enemy off the tank." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "There is no heroic or mythic mode and no personal loot. Threat is a real limit on damage, buffs are short and cast by hand, and a tank's Rage depends on being hit." },
      { "e", "Classic raids are 20 and 40 players, enemies show only a limited number of debuffs, and your big cooldowns share one timer, so Shield Wall is a once-a-fight decision." },
    },
  },
})
