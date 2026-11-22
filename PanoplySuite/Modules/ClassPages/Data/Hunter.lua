-- Panoply Suite 0.8.4 class pages: the Hunter. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Hunter article S8, the
-- launch notes S14, the class comparison C3, the race table S1), read 8 Nov 2026 and NOT checked in the live game.
-- Corrections that must stay: the Hunter uses Mana and the pet uses Focus (no modern Hunter Focus rules); Aimed Shot is trained
-- at 20; all traps share one 30-second cooldown; Disengage lowers threat and is not a leap; Wyvern Sting is not in the tree.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
-- The pet has no write-up here: the Pet tab holds the pet panel (Modules/HunterPet/Panel.lua); the Overview links to it.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  mark = { "m", "Mark it and send the pet", "#showtooltip Hunter's Mark\n/petattack\n/cast Hunter's Mark", "Sends your pet at your target and casts Hunter's Mark. Sending the pet is an order, not a spell, so both happen on one press." },
  sting = { "m", "Sting and send the pet", "#showtooltip Serpent Sting\n/petattack\n/cast Serpent Sting", "For enemies not worth a Hunter's Mark: the pet goes in and Serpent Sting goes on." },
  back = { "m", "Pet, come back", "/petfollow", "Calls your pet off and back to your side." },
  pet = { "m", "Call, heal or revive the pet", "#showtooltip\n/cast [mod:shift][@pet,dead] Revive Pet; [nopet] Call Pet; Mend Pet", "No pet out: calls it. Pet out: heals it. Pet dead: revives it. If it died and vanished, hold Shift to revive." },
  clip = { "m", "Wing Clip", "#showtooltip Wing Clip\n/startattack\n/cast Wing Clip", "For when an enemy reaches you: starts your melee attack and slows it so you can walk away." },
  conc = { "m", "Concussive Shot under the mouse", "#showtooltip Concussive Shot\n/cast [@mouseover,harm,nodead][] Concussive Shot", "Slows the enemy under your mouse without changing your target; otherwise your target." },
  feign = { "m", "Feign Death", "#showtooltip Feign Death\n/stopattack\n/petfollow\n/cast Feign Death", "Stops your attack and calls the pet back first, so nothing you are doing breaks the trick." },
  off = { "m", "Pet off and passive", "/petpassive\n/petfollow", "For bosses where the pet must not touch anything. Set the pet back to Defensive on its bar afterwards." },
  assist = { "m", "Assist and send the pet", "/assist [@mouseover,help][help]\n/petattack", "Point at the tank (or target them) and press: you take their target and the pet goes in." },
  rapid = { "m", "Rapid Fire with a trinket", "#showtooltip Rapid Fire\n/use 13\n/cast Rapid Fire", "Uses the trinket in your top trinket slot, then Rapid Fire. The trinket is not a spell, so both go on one press." },
  tranq = { "m", "Tranquilizing Shot under the mouse", "#showtooltip Tranquilizing Shot\n/cast [@mouseover,harm,nodead][] Tranquilizing Shot", "Removes a boss's Frenzy without dropping your target.", "e" },
  aspect = { "m", "Hawk, or Monkey with Shift", "#showtooltip Aspect of the Hawk\n/cast [mod:shift] Aspect of the Monkey; Aspect of the Hawk", "A plain press puts on Aspect of the Hawk for damage. Hold Shift for Aspect of the Monkey, the dodge Aspect for when enemies reach you." },
  trap = { "m", "Freezing Trap", "#showtooltip Freezing Trap\n/cast Freezing Trap", "Sets the trap at your feet. Put it down a few steps from where the enemy will walk, then shoot the other enemy; the trapped one is held until the trap breaks." },
  multi = { "m", "Multi-Shot under the mouse", "#showtooltip Multi-Shot\n/cast [@mouseover,harm,nodead][] Multi-Shot", "Shoots the enemy under your mouse (and the ones beside it) without changing your target; otherwise your target. Keep it off a trapped enemy." },
  disengage = { "m", "Disengage", "#showtooltip Disengage\n/cast Disengage", "Lowers your threat on the enemy in melee with you. It is not a jump; press it when the tank has lost the enemy to you." },
  focusConc = { "m", "Slow your focus", "#showtooltip Concussive Shot\n/cast [@focus,harm,nodead][] Concussive Shot", "Slows your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("HUNTER", {
  overview = {
    [1] = {
      { "h", "What a Hunter is" },
      { "p", "A Hunter fights from a distance with a bow or gun, and has an animal companion that fights beside them. From level 10 you can tame a wild beast and keep it. The pet holds the enemy's attention while you shoot." },
      { "p", "Hunters are the easiest class to level alone, and a fine first character. Your shots cost Mana, the blue bar." },
    },
    [2] = {
      { "h", "What a Hunter is" },
      { "p", "Steady ranged damage, a pet that tanks for you, traps, and Aspects: stances you swap for more damage, more dodge or more speed. Your weak spot is an enemy standing on top of you, so most of your tools are about distance." },
    },
    [3] = {
      { "h", "Where a Hunter fits" },
      { "p", "Hunters are damage dealers in every tree. Beast Mastery leans on the pet, Marksmanship on your own shots, Survival on traps and utility. In groups you also pull, trap, and bring a pet that can hold a loose enemy." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "You use Mana. Focus belongs to the pet, and it pays for the pet's own abilities. Pets are not cosmetic: they have happiness, food they will and will not eat, and skills you teach them. A dungeon has one difficulty: no heroic, no mythic." },
      { "p", "Disengage lowers your threat on the enemy in melee with you. It is not a leap." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Dwarf and Night Elf. Horde: Orc, Tauren and Troll." },
      { "f", "Alliance: Human (new), Dwarf, Night Elf and High Order Skyborne. Horde: Orc, Tauren, Troll and Windshaper Skyborne." },
      { "f", "Skyborne Hunters start on Zephras Isle and have their own taming quests there. Players disagree about the order of the beasts those quests ask for, so follow your quest log rather than a guide." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Until level 10 you have no pet: shoot the enemy as it walks to you, then finish it up close with Raptor Strike. At level 10 your trainer gives you the taming quests. Do them at once; the class changes completely." },
      { "p", "With a pet: send it in, wait a moment so the enemy is looking at it, then shoot. Feed your pet when its face icon is not green. A happy pet does more damage." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Beast Mastery is the smooth leveling tree: a tougher pet that hits harder means you never stop to recover. Keep the pet's Growl on so enemies stay on it, and Mend Pet instead of bandaging yourself." },
      { "p", "Upgrade your ranged weapon before anything else. Teach your pet its skills with Beast Training; you learn most pet skills by taming a beast that already knows them." },
    },
    [3] = {
      { "h", "Leveling another Hunter" },
      { "p", "You can take quests a few levels above you and fight two enemies at once: the pet on one, a trap on the other. Hunters also solo many group quests by kiting, which means running while shooting an enemy that is slowed." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Pet upkeep is real: feed it, keep it loyal, and go and tame specific beasts to learn skill ranks. Shots are woven between automatic shots rather than cast back to back." },
      { "e", "You carry ammunition in a quiver or pouch, and you cannot shoot an enemy that is closer than a few yards." },
    },
    all = {
      { "f", "Aimed Shot is trained at level 20 by every Hunter, and traps can be put down in the middle of a fight. All traps share one 30-second cooldown." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Hunter trainer sells your shots, Aspects and traps, usually every two levels. Talents & spells lists what to buy at each visit and what it costs. A separate pet trainer teaches skills for your pet." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy every shot and Aspect. Beast Mastery is the usual leveling tree; Marksmanship is the choice if you want your own shots to do the work." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Beast Mastery: the strongest pet. Marksmanship: the strongest shots. Survival: traps and control." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "No Kill Command loop. Damage is automatic shots with a few special shots timed between them, and your Mana can run out." },
    },
    all = {
      { "h", "Shots, Aspects and traps" },
      { "p", "One Aspect at a time: Hawk for damage, Monkey for dodge when things reach you, Cheetah to travel. Hunter's Mark makes an enemy take more ranged damage." },
      { "e", "Aimed Shot is a Marksmanship talent. Traps can only be set outside combat, so you set one before the pull or after Feign Death. Wyvern Sting is the last Survival talent." },
      { "f", "Aimed Shot is trained at 20. Arcane Shot no longer shares its cooldown with it; Multi-Shot does. Traps work in combat on one shared 30-second cooldown. Wyvern Sting is not in the Survival tree." },
      { "f", "New in the trees: Summon Hawk and Focused Fire for Beast Mastery (the hawk is a short-lived helper, not another pet), Lone Wolf and Sniper Shot for Marksmanship, Strider Kick, Expose Prey and Lacerating Strikes for Survival." },
      { "h", "Trainers" },
      { "p", "Any Hunter trainer teaches the same spells. In the capitals: Jocaste in Darnassus's Cenarion Enclave, Ormak Grimshot in Orgrimmar's Valley of Honor. Turn on Class trainers and Pet trainers in the map's Places menu to see the ones near you." },
      { "f", "Skyborne on Zephras Isle: Tai'ree Farsight and Elayaa Easewind early on, Quel'ana Quickgale in Valanaar, and the pet trainer Quel'dora Quickgale there too." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Send your pet. 2. Count to two. 3. Shoot: your bow or gun keeps firing by itself. 4. Add Serpent Sting once, and Arcane Shot when it is ready." },
      { "p", "If the enemy turns and runs at you, stop shooting for a moment so your pet can take it back." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Hunter's Mark, pet in, Serpent Sting, then Arcane Shot on cooldown while your automatic shots do most of the work. Concussive Shot slows anything that comes for you. In melee, Wing Clip and walk away rather than standing and fighting." },
      { "p", "Watch your Mana: on long sessions, drop the Sting and the Arcane Shots before you run dry, and let the pet and automatic shots carry the fight." },
    },
    [3] = {
      { "h", "In dungeons" },
      { "p", "Give the tank a few seconds, then Hunter's Mark the kill target and shoot it. Multi-Shot only when nothing nearby is being kept out of the fight. Keep the pet's Growl off in groups so it does not fight the tank for the enemy." },
      { "p", "Feign Death drops your threat when an enemy turns on you. A Freezing Trap holds one enemy out of the fight." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Automatic shots are the core. Cast Aimed Shot and Multi-Shot in the gap right after an automatic shot fires, so you never delay the next one. Hunter's Mark on the boss, Aspect of the Hawk on, pet attacking from behind." },
      { "e", "Tranquilizing Shot on a boss's Frenzy is a Hunter's assigned job in several Classic raids. Feign Death, then set a trap, is how you trap in the middle of a fight." },
      { "f", "Arcane Shot is off Aimed Shot's cooldown, so it has a place between them when Mana allows. With every trap on one 30-second cooldown, choose the trap before the pull." },
    },
    all = {
      { "h", "Three orders, one for each kind of fight" },
      { "p", "The sequencer below has three Hunter orders: one enemy, two enemies (a trap on the second), and a dungeon. Each lists what you press from first to last. Your pet is sent in before the first spell; that is an order to the pet, not a spell, so it is not in the list." },
    },
  },

  macros = {
    [1] = { { "h", "Three to start with" }, M.mark, M.back, M.pet },
    [2] = { { "h", "For the road" }, M.mark, M.sting, M.back, M.pet, M.clip, M.aspect },
    [3] = { { "h", "For dungeons" }, M.mark, M.back, M.pet, M.conc, M.feign, M.assist, M.multi, M.trap, M.aspect },
    [4] = { { "h", "A raid set" }, M.assist, M.off, M.feign, M.conc, M.focusConc, M.tranq, M.rapid, M.pet, M.multi, M.trap, M.aspect, M.disengage },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Shoot what the tank is fighting and nothing else. Keep your pet close so it does not run off and bring more enemies; in tight places, put it on Passive." },
      { "p", "Turn off the pet's Growl in a group. Open your pet's spell book and right-click Growl so it stops using it by itself." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "Your jobs: steady damage, a trap on an extra enemy when asked, and pulling with a shot when the tank wants it. Dismiss the pet before a jump down a ledge: it will run the long way round and bring everything with it." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Learn to trap an enemy and keep it trapped for a whole fight, and learn the range of your shots so you stand at the edge of it. Bring food for the pet." },
      { "e", "Bring more ammunition than you think you need; running out ends your evening." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. A raid Hunter is judged on steady shot timing, staying alive, and doing the small jobs well: pulling, kiting and trapping." },
      { "e", "Classic raids are 20 and 40 players. Marksmanship's Trueshot Aura goes to your own party, so raid leaders put Hunters with melee." },
    },
  },
})
