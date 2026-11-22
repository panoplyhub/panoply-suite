-- Panoply Suite 0.8.4 class pages: the Shaman. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Shaman article S10, the
-- launch notes S14, the class comparison C6, the race table S1), read 8 Nov 2026 and NOT checked in the live game.
-- Corrections that must stay: there is no Lava Burst (Call of Thunder replaces it); Totemic Call brings your totems
-- to you and is not a targeted move; Riptide is a heal over time only; Shamans are on both factions.
-- The Dwarf and Windshaper totem quest chains are player reports and are not named. The 10 Nov tuning was only announced.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  shock = { "m", "Shock", "#showtooltip Earth Shock\n/startattack\n/cast Earth Shock", "Starts your attack and shocks your target." },
  heal = { "m", "Heal a friend, or me", "#showtooltip Healing Wave\n/cast [help,nodead][@player] Healing Wave", "Heals the friend you have targeted. With an enemy or nobody targeted, it heals you." },
  wave = { "m", "Healing Wave under the mouse", "#showtooltip Healing Wave\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Wave", "Heals the friend under your mouse, then your friendly target, then you. Your target does not change." },
  lesser = { "m", "Lesser Healing Wave under the mouse", "#showtooltip Lesser Healing Wave\n/cast [@mouseover,help,nodead][help,nodead][@player] Lesser Healing Wave", "The quick heal, same order: mouse, target, you." },
  chain = { "m", "Chain Heal under the mouse", "#showtooltip Chain Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Chain Heal", "Starts the chain on the friend under your mouse. Pick someone standing in the middle of the hurt players." },
  interrupt = { "m", "Interrupt with a shock", "#showtooltip Earth Shock\n/stopcasting\n/cast [@mouseover,harm,nodead][] Earth Shock", "Drops your own cast and shocks the enemy under your mouse, or your target, to stop its spell." },
  purge = { "m", "Purge under the mouse", "#showtooltip Purge\n/cast [@mouseover,harm,nodead][] Purge", "Strips a buff from the enemy you point at without changing your target." },
  cure = { "m", "Cure Poison under the mouse", "#showtooltip Cure Poison\n/cast [@mouseover,help,nodead][help,nodead][@player] Cure Poison", "Write Cure Disease instead for a second button." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]\n/startattack", "Point at the tank (or target them) and press: you take their target and start attacking it." },
  swift = { "m", "Nature's Swiftness, then the big heal", "#showtooltip Healing Wave\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Wave", "Nature's Swiftness (a Restoration talent) is not on the global cooldown, so the instant heal goes out on the same press.", "e" },
  totems = { "m", "Recall your totems", "#showtooltip Totemic Recall\n/cast Totemic Recall", "Picks all your totems up in one press, so you can move on and leave none behind.", "f" },
  focusShock = { "m", "Interrupt your focus", "#showtooltip Earth Shock\n/stopcasting\n/cast [@focus,harm,nodead][] Earth Shock", "Shocks your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("SHAMAN", {
  overview = {
    [1] = {
      { "h", "What a Shaman is" },
      { "p", "A Shaman mixes three things: lightning and shock spells, healing, and fighting with a weapon you empower. You wear leather at first, carry a shield, and use Mana, the blue bar." },
      { "p", "Your special tool is totems: small objects you place on the ground that help everyone near them. They do not move, so you set them where the fight will be." },
    },
    [2] = {
      { "h", "What a Shaman is" },
      { "p", "A hybrid that can heal, cast or melee depending on talents. You can have one totem out for each element: Earth, Fire, Water and Air. Shocks are instant spells on a shared cooldown, and a weapon spell such as Rockbiter makes your swings hit harder." },
    },
    [3] = {
      { "h", "Where a Shaman fits" },
      { "p", "Restoration is a strong group healer built around Chain Heal. Enhancement is melee damage; Elemental is spell damage. Every Shaman brings totems, Purge, a shock that interrupts and a self-resurrection." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "No Maelstrom bar: everything runs on Mana. Totems are the class, not a side effect. They give lasting group buffs, they can be killed, and placing the right four is half your job. A dungeon has one difficulty: no heroic, no mythic." },
      { "f", "There is no Lava Burst. Call of Thunder replaces it." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Horde only: Orc, Tauren and Troll. The Alliance has no Shamans." },
      { "f", "Horde: Orc, Tauren, Troll and Windshaper Skyborne. Alliance: Dwarf, new. Shamans are no longer a Horde-only class." },
      { "f", "Windshaper Skyborne Shamans start on Zephras Isle. Dwarf Shamans begin with their own trainers in Coldridge and Kharanos." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Cast Lightning Bolt as the enemy walks to you, then fight it with your weapon. Keep a weapon spell such as Rockbiter on your weapon; it wears off, so cast it again when it does. Heal yourself with Healing Wave if you drop under half." },
      { "p", "Your trainer sends you on a quest for each kind of totem. Do them when they are offered: totems are a big part of your strength." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Enhancement. The fight is a Lightning Bolt on the way in, a shock, and melee with your weapon spell and Lightning Shield up." },
      { "e", "Enhancement talents let you use two-handed axes and maces. A slow two-handed weapon makes every hit and every Windfury attack bigger." },
      { "p", "Drop a totem or two for fights that matter, not for every enemy; they cost Mana. Ghost Wolf is your travel speed until you can ride." },
    },
    [3] = {
      { "h", "Leveling another Shaman" },
      { "p", "You can heal any leveling dungeon in Enhancement talents: carry a set of Intellect gear and swap before the run. Out in the world, save shocks for interrupts and runners and you will rarely need to drink." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Your Mana bar is the limit on everything, including melee. Shocks are expensive and share one cooldown, so each one is a choice. Totems cost Mana each time you place them." },
      { "e", "Each totem is placed one at a time, most last about two minutes, and you must carry the four totem items from your class quests." },
    },
    all = {
      { "f", "Buff totems last 5 minutes and weapon spells last 60 minutes. Call of the Elements at level 20, then Spirits at 30 and Ancestors at 40, each place a set of totems at once, and Totemic Recall is trained at 20." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Shaman trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs." },
      { "p", "From level 10 you get talent points for three trees: Elemental for spell damage, Enhancement for melee, Restoration for healing." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy your shocks, your heals, Lightning Shield and the weapon spell you use. You do not need every rank of every totem while leveling. Enhancement is the usual leveling tree." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Restoration: stronger and cheaper heals, the group standard. Enhancement: Stormstrike and melee. Elemental: Lightning Bolt and Chain Lightning with big critical hits." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "Restoration is Chain Heal, Healing Wave and Lesser Healing Wave, plus the right totems for your group. Do not expect the modern toolkit." },
    },
    all = {
      { "h", "Totems and weapon spells" },
      { "p", "One totem for each element at a time. A new Earth totem replaces your old Earth totem." },
      { "e", "Weapon spells are a buff on your own weapon: one at a time, recast when it fades. Totems reach your own party only. Windfury Weapon is a spell for your own weapon; Windfury Totem gives the effect to your party's melee." },
      { "f", "Totems have their own 1-second cooldown between them. Windfury and Flametongue are party buffs now, with some exclusions, rather than only your own weapon enchantment. Weapon spells sit alongside other temporary weapon effects." },
      { "f", "Totemic Call brings your totems to where you stand, on a 30-second cooldown. It does not send them somewhere else. Riptide is a heal over time only, with a 12-second cooldown." },
      { "h", "Trainers" },
      { "e", "Any Shaman trainer teaches the same spells. In Thunder Bluff: Beram Skychaser on Spirit Rise. Turn on Class trainers in the map's Places menu to see the ones near you." },
      { "f", "Horde: Beram Skychaser on Thunder Bluff's Spirit Rise. Alliance: Eldrun Stormbreaker in Ironforge's Forlorn Cavern, Teo Hammerstorm in Coldridge and Ingrid Dunwald in Kharanos. Skyborne on Zephras Isle: Windshaper Boro and Aarnor Galestrike early on, Sessaria Skystride in Valanaar." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Lightning Bolt while the enemy walks to you. 2. Earth Shock when it arrives. 3. Fight with your weapon. 4. Healing Wave on yourself under half health." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "p", "Lightning Bolt to pull, then melee with Lightning Shield up. Use a shock when it helps: Earth Shock stops a spell, Frost Shock slows a runner, Flame Shock adds damage on a long fight. One shock, then let the cooldown and your Mana recover." },
    },
    [3] = {
      { "h", "Healing a dungeon" },
      { "p", "Healing Wave on the tank for normal damage, Lesser Healing Wave when it is urgent, Chain Heal when three people are hurt and standing close. Put down a Mana totem for yourself and a melee totem for the tank's group at each real pull." },
      { "h", "Dealing damage" },
      { "p", "Enhancement: Stormstrike on cooldown, a shock when Mana allows, weapon spell and Lightning Shield always up. Elemental: Lightning Bolt, with Chain Lightning on cooldown. Earth Shock is saved for interrupts when the group needs one." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Restoration: Chain Heal is the default whenever more than one player is hurt; Healing Wave for a tank. Keep the right totems down for your party and replace them when the fight moves. Mana over the whole fight is the measure." },
      { "e", "Your totems reach only your party, so raids place a Shaman in each group: Windfury for melee groups, Mana Spring or Mana Tide for healers." },
      { "f", "Chain Lightning has a 2.5-second cast in the launch notes. Stormstrike is on a 6-second cooldown. Maelstrom Weapon is an Enhancement talent, not a resource bar." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.shock, M.heal },
    [2] = { { "h", "For the road" }, M.shock, M.wave, M.interrupt },
    [3] = { { "h", "For dungeons" }, M.wave, M.lesser, M.cure, M.interrupt, M.purge, M.totems },
    [4] = { { "h", "A raid set" }, M.chain, M.wave, M.lesser, M.cure, M.interrupt, M.focusShock, M.purge, M.totems, M.swift, M.assist },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Ask what the group needs: a healer or damage. Either way, put your totems down near where the tank fights, and heal anyone who is about to die." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "As healer, stay behind the group and keep the tank up. As damage, your totems still matter more than one more shock. Use Earth Shock to stop enemy heals." },
      { "e", "Carry an Ankh from level 30 so that Reincarnation can bring you back after a wipe." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Pick totems for the people in your group, not for yourself: Strength of Earth or Windfury for melee, Mana Spring for casters and healers, Tremor Totem against fears, Poison or Disease Cleansing where the dungeon calls for it." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. A raid Shaman is first a totem carrier for one party and a Chain Heal caster. Know each fight's movement so your totems are where your party ends up." },
      { "e", "Classic raids are 20 and 40 players, and only the Horde has Shamans." },
    },
  },
})
