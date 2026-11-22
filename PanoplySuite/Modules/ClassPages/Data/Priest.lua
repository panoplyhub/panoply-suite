-- Panoply Suite 0.8.4 class pages: the Priest. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Priest article S9, the
-- launch notes S14, the class comparison C5, the race table S1), read 8 Nov 2026 and NOT checked in the live game.
-- Corrections that must stay: Fear Ward and Devouring Plague are for every Priest at 20; Binding Heal was replaced by Holy
-- Binding; the racial Priest spells stay tied to a race. Exact ranks of the racial spells still need the game.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  heal = { "m", "Heal a friend, or me", "#showtooltip Lesser Heal\n/cast [help,nodead][@player] Lesser Heal", "Heals the friend you have targeted. With an enemy or nobody targeted, it heals you. Change the name when you learn a bigger heal." },
  shield = { "m", "Shield a friend, or me", "#showtooltip Power Word: Shield\n/cast [help,nodead][@player] Power Word: Shield", "Shields your friendly target; otherwise you. You can keep fighting an enemy and still shield yourself." },
  renew = { "m", "Renew under the mouse", "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead][@player] Renew", "Renew on the friend under your mouse, then your friendly target, then you. Your target does not change." },
  flash = { "m", "Flash Heal under the mouse", "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash Heal", "The quick heal, same order: mouse, target, you." },
  greater = { "m", "Greater Heal under the mouse", "#showtooltip Greater Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Greater Heal", "The big heal, same order: mouse, target, you." },
  pws = { "m", "Shield under the mouse", "#showtooltip Power Word: Shield\n/cast [@mouseover,help,nodead][help,nodead][@player] Power Word: Shield", "Shield on the friend under your mouse, then your friendly target, then you." },
  scream = { "m", "Scream, right now", "#showtooltip Psychic Scream\n/stopcasting\n/cast Psychic Scream", "Drops whatever you were casting and fears the enemies next to you." },
  dispel = { "m", "Dispel Magic under the mouse", "#showtooltip Dispel Magic\n/cast [@mouseover,exists,nodead][] Dispel Magic", "Works both ways: it cleans a friend and strips an enemy, whoever is under your mouse; otherwise your target." },
  shackle = { "m", "Shackle under the mouse", "#showtooltip Shackle Undead\n/cast [@mouseover,harm,nodead][] Shackle Undead", "Shackles the undead you point at, so your target can stay on the tank." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]", "Point at the tank (or target them) and press: you take their target, for a Shackle, a dispel or damage." },
  stop = { "m", "Stop my cast", "/stopcasting", "Cancels the heal you are casting. Start a heal early on the tank and cancel it if it is not needed: you spend no Mana." },
  focusShackle = { "m", "Shackle your focus", "#showtooltip Shackle Undead\n/cast [@focus,harm,nodead][] Shackle Undead", "Re-shackles your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
  innerFocus = { "m", "Inner Focus, then the big heal", "#showtooltip Greater Heal\n/cast Inner Focus\n/cast [@mouseover,help,nodead][help,nodead][@player] Greater Heal", "Inner Focus (a Discipline talent) is not on the global cooldown, so the free heal starts on the same press.", "e" },
}

CP:Register("PRIEST", {
  overview = {
    [1] = {
      { "h", "What a Priest is" },
      { "p", "A Priest is a healer first. You wear cloth, cast spells with Mana, the blue bar, and keep other people alive. Alone you fight with Holy and Shadow spells, a shield that soaks damage, and a wand." },
      { "p", "Groups are always looking for a healer, so a Priest never waits long for company." },
    },
    [2] = {
      { "h", "What a Priest is" },
      { "p", "The widest healing toolkit in the game: a small, a fast and a big heal, a heal over time, a shield, a group heal, and a resurrection. Shadow turns the same character into a damage dealer who leaves damage-over-time spells on enemies." },
    },
    [3] = {
      { "h", "Where a Priest fits" },
      { "p", "Holy and Discipline heal; Shadow deals damage. Priests also bring Power Word: Fortitude, Dispel Magic, Shackle Undead and Mind Control." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "Healing is slow casts and Mana, not cooldown rotations. Discipline is a healing tree, not a healer who heals by dealing damage. Running out of Mana is the normal way to lose a fight. A dungeon has one difficulty: no heroic, no mythic." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance: Human, Dwarf, Night Elf. Horde: Undead, Troll." },
      { "f", "Alliance: Human, Dwarf, Night Elf and Gnome (new). Horde: Undead and Troll. Skyborne cannot be Priests." },
      { "h", "Spells that come with your race" },
      { "e", "Each race gets its own Priest spells: Dwarves get Fear Ward and Desperate Prayer, Humans Desperate Prayer and Feedback, Night Elves Starshards and Elune's Grace, Undead Touch of Weakness and Devouring Plague, Trolls Hex of Weakness and Shadowguard." },
      { "f", "Fear Ward and Devouring Plague are trained by every Priest at level 20. The other racial spells stay with their race: Gnomes get Confounding Flash and Contingency Plan, Humans Divine Grace and Feedback, Dwarves Desperate Prayer and Chastise, Night Elves Starshards and Elune's Grace, Trolls Hex of Weakness and Shadowguard, Undead Touch of Weakness and Dark Sacrifice." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Cast Smite at the enemy as it comes, add Shadow Word: Pain when you learn it, and put Power Word: Shield on yourself before it reaches you. Heal yourself if your health drops under half." },
      { "p", "Buy a wand as soon as you can use one. Finishing enemies with the wand costs no Mana, and that is the secret to leveling a Priest. Drink between fights." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level with Shadow talents. The usual fight is Shield, a damage-over-time spell, one or two Mind Blasts, then the wand while your Mana comes back. Shadow talents that speed your Mana back after each kill make this nearly endless." },
      { "p", "You can still heal every leveling dungeon in Shadow talents. Upgrade your wand whenever you can: for many levels it is most of your damage." },
    },
    [3] = {
      { "h", "Leveling another Priest" },
      { "p", "Healing dungeons from the mid-teens on is the fastest route, and no class finds groups more easily. Out in the world, Mind Flay and Shadowform make the last twenty levels much quicker than the first forty." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "You will wand things to death, and it is correct. Mana does not come back while you are casting, so stopping to wand is how you keep going. Fear is risky: a feared enemy runs into its friends." },
    },
    all = {
      { "f", "Shadow Word: Death is trained at level 32. If its target survives, you take a heavy hit yourself (the launch notes say 30% of your maximum health), so use it to finish, not to open." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Priest trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs." },
      { "p", "From level 10 you get talent points for three trees: Discipline, Holy and Shadow." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy every heal, Power Word: Shield and Fortitude at every rank. If you level as Shadow you can skip new ranks of Smite and Holy Fire. Start in Shadow; a few early Discipline points for the wand are common." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Holy: the strongest group and tank heals. Discipline: Mana, shields and buffs. Shadow: Mind Flay, Shadowform and steady damage." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "Your core heals are Lesser Heal, Heal, Greater Heal, Flash Heal, Renew and Prayer of Healing, and the craft is picking the right one for the damage coming in." },
    },
    all = {
      { "h", "Worth knowing" },
      { "p", "Power Word: Shield leaves Weakened Soul on its target, so the same player cannot be shielded again for a short time. Prayer of Healing heals one party, not the whole raid." },
      { "e", "Divine Spirit is a Discipline talent. Prayer of Healing always heals your own party. Only one Priest's Renew can be on a player at a time." },
      { "f", "Divine Spirit is trained at level 30. Prayer of Healing is aimed through a party member and also heals that party's pets. Several Priests can each keep their own Renew on the same player." },
      { "f", "New in the trees: Soul Warding, Penance and Divine Aegis for Discipline, Prayer of Mending and Litany of Light for Holy, Devouring Contagion for Shadow. Holy Binding heals you whenever your Flash Heal heals someone else." },
      { "h", "Trainers" },
      { "p", "Any Priest trainer teaches the same spells. In the capitals: High Priestess Laurena in Stormwind's Cathedral, Aelthalyste in the Undercity's War Quarter. Turn on Class trainers in the map's Places menu to see the ones near you." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "Alone: 1. Shield yourself. 2. Shadow Word: Pain on the enemy. 3. Smite until it is nearly dead. 4. Finish with your wand." },
      { "p", "Healing a friend: target them and cast your heal when they are missing about a third of their health. Do not heal a scratch; it wastes Mana." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Shield, Shadow Word: Pain, Mind Blast, then wand. Against a tough enemy add Renew on yourself instead of a big heal. Psychic Scream is your panic button when two or more are on you, away from other enemies." },
    },
    [3] = {
      { "h", "Healing a dungeon" },
      { "p", "Renew on the tank at the pull, then the mid-sized Heal for normal damage and Flash Heal when it gets urgent. Shield a damage dealer who has taken an enemy off the tank. Dispel Magic the debuffs that matter and keep Fortitude on everyone." },
      { "p", "Start drinking the moment a fight ends. Your Mana bar is the group's pace." },
      { "h", "Shadow damage" },
      { "p", "Shadow Word: Pain up at all times, Mind Blast when ready, Mind Flay in between. Shadow makes a lot of threat: hold back for the first few seconds." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Healer: pick the cheapest heal that covers the damage, start it early on the tank, and cancel it if it would be wasted. Renew on tanks, Prayer of Healing for a party after area damage, dispels on call." },
      { "e", "Five seconds without spending Mana starts your Spirit regeneration again; plan pauses around that. Casting lower ranks to save Mana is standard, and only one Priest's Renew fits on a target, so healers agree who covers whom." },
      { "f", "Fear Ward is yours whatever your race, so it can be assigned to any Priest. Flash Heal on others also heals you through Holy Binding, which covers light raid damage on yourself." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.heal, M.shield },
    [2] = { { "h", "For the road" }, M.shield, M.renew, M.scream },
    [3] = { { "h", "For dungeons" }, M.renew, M.flash, M.pws, M.dispel, M.shackle, M.scream },
    [4] = { { "h", "A raid set" }, M.greater, M.flash, M.renew, M.pws, M.dispel, M.stop, M.assist, M.focusShackle, M.innerFocus },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "You will usually be the healer. Stand back, watch the health bars of your group, and heal the tank first. Tell the group when your Mana is low so they wait for you to drink." },
      { "p", "Cast Power Word: Fortitude on everyone at the start. It is the buff people expect from a Priest." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "Heal the tank, then whoever is in danger. Do not heal before the tank has the enemies' attention or they will come for you; if one does, run to the tank, not away. Bring more water than you think you need." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Learn what each dungeon asks of a Priest: which undead to Shackle, which debuffs to Dispel, where a Mind Control wins the pull. Healing gear with Spirit and Mana regeneration lasts longer than gear with only healing power." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. Raid healing is assignment-based: you are given tanks or groups and you stay on them. Mana across a long fight, not peak output, is how healers are measured." },
      { "e", "Classic raids are 20 and 40 players. Fortitude and Spirit are cast per group, and a Dwarf's Fear Ward is asked for by name on fights with a fear." },
    },
  },
})
