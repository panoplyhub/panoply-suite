-- Panoply Suite 0.8.4 class pages: the Paladin. Panoply Suite's own words; the game facts are Blizzard's.
-- "f" paragraphs are WoW Forever facts from logs/research/forever-class-pages-research.md (Blizzard's Paladin article S12, the
-- launch notes S14, the class comparison C2, the race table S1), read 8 Nov 2026 and NOT checked in the live game.
-- Corrections that must stay: Judgement does not use up the Seal; Consecration and Blessing of Kings are trained, not talents;
-- Salvation, Mass Salvation, Revoke, Blessing of Light and Twist of Light are gone (no Salvation macro, no seal-twisting advice);
-- a talent with "Holy Power" in its name is not the modern resource; Paladins are on both factions.
-- "e" paragraphs are Classic Era (1.12 rules). Trainer names: S21; no coordinates.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

local M = {
  judge = { "m", "Judgement", "#showtooltip Judgement\n/startattack\n/cast Judgement", "Starts your attack and judges your target. You need a Seal on yourself first." },
  healSelf = { "m", "Heal a friend, or me", "#showtooltip Holy Light\n/cast [help,nodead][@player] Holy Light", "Heals the friend you have targeted. With an enemy or nobody targeted, it heals you." },
  flash = { "m", "Flash of Light under the mouse", "#showtooltip Flash of Light\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash of Light", "Heals the friend under your mouse, then your friendly target, then you. Your target does not change." },
  light = { "m", "Holy Light under the mouse", "#showtooltip Holy Light\n/cast [@mouseover,help,nodead][help,nodead][@player] Holy Light", "The big heal, same order: mouse, target, you." },
  stun = { "m", "Hammer of Justice under the mouse", "#showtooltip Hammer of Justice\n/cast [@mouseover,harm,nodead][] Hammer of Justice", "Stuns the enemy under your mouse without changing your target; otherwise your target." },
  cleanse = { "m", "Cleanse under the mouse", "#showtooltip Cleanse\n/cast [@mouseover,help,nodead][help,nodead][@player] Cleanse", "Before you learn Cleanse, write Purify in both places." },
  bop = { "m", "Blessing of Protection under the mouse", "#showtooltip Blessing of Protection\n/cast [@mouseover,help,nodead][help,nodead] Blessing of Protection", "For the cloth wearer who pulled something. It never lands on you by accident: with nobody picked it does nothing." },
  loh = { "m", "Lay on Hands under the mouse", "#showtooltip Lay on Hands\n/cast [@mouseover,help,nodead][help,nodead] Lay on Hands", "The emergency heal, on purpose only: it needs a friend under the mouse or targeted." },
  assist = { "m", "Assist", "/assist [@mouseover,help][help]\n/startattack", "Point at the tank (or target them) and press: you take their target and start attacking it." },
  strike = { "m", "Holy Strike", "#showtooltip Holy Strike\n/startattack\n/cast Holy Strike", "Starts your attack and uses Holy Strike.", "f" },
  focusStun = { "m", "Stun your focus", "#showtooltip Hammer of Justice\n/cast [@focus,harm,nodead][] Hammer of Justice", "Stuns your focus target if you have one, otherwise your target. Set your focus first with /focus.", "f" },
}

CP:Register("PALADIN", {
  overview = {
    [1] = {
      { "h", "What a Paladin is" },
      { "p", "A Paladin wears heavy armor, fights with a weapon, and heals. You use Mana, the blue bar. You are very hard to kill: you can heal yourself, make yourself immune for a few seconds, and bring a friend back from the dead." },
      { "p", "The class is calm to play. Fights are slow and safe rather than fast, which makes it a good first character." },
    },
    [2] = {
      { "h", "What a Paladin is" },
      { "p", "Three tools define you. A Seal is a short buff on your weapon. Judgement throws the Seal's power at an enemy. Blessings and Auras strengthen your whole group. Around that you have heals, a stun and strong defensive buttons." },
    },
    [3] = {
      { "h", "Where a Paladin fits" },
      { "p", "Holy Paladins are efficient single-target healers and the usual choice for groups. Protection holds groups of enemies well. Retribution deals melee damage and brings the same Blessings and Auras as the other two." },
    },
    [4] = {
      { "h", "Coming from the modern game" },
      { "p", "There is no Holy Power bar and no builder-spender loop. Damage comes from your swing, your Seal and Judgement. Blessings are buffs you keep up by hand, one per Paladin on each player. A dungeon has one difficulty: no heroic, no mythic." },
      { "f", "A talent here has Holy Power in its name. It is a talent, not the modern resource." },
    },
    all = {
      { "h", "Who can be one" },
      { "e", "Alliance only: Human and Dwarf. The Horde has no Paladins." },
      { "f", "Alliance: Human and Dwarf. Horde: Undead, new. Paladins are no longer an Alliance-only class. Skyborne cannot be Paladins." },
    },
  },

  leveling = {
    [1] = {
      { "h", "Your first levels" },
      { "p", "Put a Seal on yourself, walk up to an enemy and attack. When you learn Judgement, use it during the fight. If your health gets low, step back and heal yourself with Holy Light." },
      { "p", "Keep a Blessing on yourself at all times; Blessing of Might makes you hit harder. Visit a Paladin trainer every two levels." },
    },
    [2] = {
      { "h", "Getting to the top" },
      { "p", "Level as Retribution with a slow two-handed weapon. You will rarely die and rarely need to eat, but each fight takes a while, so pick quests with enemies at or just under your level." },
      { "p", "Do the class quest for Redemption as soon as your trainer offers it. Keep an Aura on: Retribution Aura when alone, Devotion Aura when things hit hard." },
    },
    [3] = {
      { "h", "Leveling another Paladin" },
      { "p", "A Paladin can pull several enemies at once and outlast them with heals and defensive buttons. With a shield and Protection talents this becomes a real way to level. Dungeon groups always want a healer, and a leveling Paladin heals dungeons in any talents." },
    },
    [4] = {
      { "h", "What will surprise you" },
      { "p", "Most of your leveling damage is your plain weapon swing with the Seal riding on it. The reward for the slow pace is that almost nothing can kill you." },
      { "e", "There is no strike button to fill the time: long stretches are a Seal, Judgement and waiting." },
    },
    all = {
      { "e", "Judgement uses up your Seal, so the loop is Seal, Judgement, Seal again." },
      { "f", "Judgement does not use up your Seal: put one Seal up and judge whenever it is ready. Holy Strike is trained at level 6 and gives you a real attack button from the start." },
    },
  },

  spells = {
    [1] = {
      { "h", "Where spells come from" },
      { "p", "A Paladin trainer sells your spells, usually every two levels. Talents & spells lists what to buy at each visit and what it costs." },
      { "p", "From level 10 you get talent points for three trees: Holy for healing, Protection for tanking, Retribution for damage." },
    },
    [2] = {
      { "h", "What to buy and where to put points" },
      { "p", "Buy your Seals, Judgement, your heals and every Blessing and Aura. Retribution is the usual leveling tree. A few points in the other trees early are common; a ready-made plan in Talents & spells saves you the reading." },
    },
    [3] = {
      { "h", "Trees at the top level" },
      { "p", "Holy: cheaper and stronger heals, the dungeon and raid standard. Protection: shield talents and threat on many enemies. Retribution: damage with a two-handed weapon." },
    },
    [4] = {
      { "h", "What is different here" },
      { "p", "Healing is mostly two spells, Holy Light and Flash of Light, and knowing which one the moment needs. Do not expect the modern Holy toolkit." },
    },
    all = {
      { "h", "Seals, Blessings and Auras" },
      { "p", "One Seal on yourself, one Aura for the group, and Blessings on players. Each Paladin can keep one Blessing on a player, so two Paladins in a group agree on who casts which." },
      { "e", "Consecration and Blessing of Kings are talents. Blessing of Salvation lowers the threat of the player who has it and is the most asked-for Blessing in raids." },
      { "f", "Consecration (level 20) and Blessing of Kings are trained by every Paladin; they are no longer talents. Seal of Fury is trained at level 10 and its Judgement taunts. Righteous Fury is trained at level 10." },
      { "f", "Blessing of Salvation and Blessing of Light are not in WoW Forever. Guides that tell you to cast Salvation, or to swap Seals quickly for extra damage, were written for an older version." },
      { "h", "Trainers" },
      { "e", "Any Paladin trainer teaches the same spells. In Stormwind: Lord Grayson Shadowbreaker in the Cathedral. Turn on Class trainers in the map's Places menu to see the ones near you." },
      { "f", "Alliance: Lord Grayson Shadowbreaker in Stormwind's Cathedral. Horde: Aramis Hammerhand in Deathknell, Shari Stilwell in Brill, and Hilda the Breaker at Bandarion Keep in Tirisfal. Turn on Class trainers in the map's Places menu to see the ones near you." },
    },
  },

  rotation = {
    [1] = {
      { "h", "What to press" },
      { "p", "1. Put a Seal on yourself. 2. Attack. 3. Press Judgement when it is ready. 4. Heal yourself when your health is under half." },
      { "e", "After Judgement your Seal is gone: put it back on before you carry on." },
      { "f", "Your Seal stays on after Judgement. Use Holy Strike between Judgements." },
    },
    [2] = {
      { "h", "Leveling fights" },
      { "e", "Open with Seal of the Crusader and judge it: the enemy now takes more Holy damage. Then put up Seal of Righteousness, or Seal of Command if you have the talent, and fight under it. Judge the damage Seal only when the enemy is nearly dead." },
      { "f", "Keep your damage Seal up, judge on cooldown, and use Holy Strike whenever it is ready. From level 20, Consecration under two or more enemies." },
      { "p", "Hammer of Justice stops a caster or an enemy that runs." },
      { "e", "Against undead and demons, Exorcism is extra damage for little Mana." },
    },
    [3] = {
      { "h", "Healing a dungeon" },
      { "p", "Flash of Light for most damage, Holy Light when the tank drops fast. Keep a Blessing on everyone, and Cleanse poisons, diseases and magic as they appear. Stand still as little as possible before a pull so your Mana is full." },
      { "h", "Tanking a dungeon" },
      { "p", "Righteous Fury on, a shield, and a Seal that deals Holy damage. Consecration holds a pack; Judgement adds threat on one target." },
      { "e", "A Classic Paladin has no taunt. If an enemy leaves you, you win it back with damage, so pull to yourself and start early." },
      { "f", "Seal of Fury's Judgement is your taunt. Consecration matters most on the first four enemies it hits." },
    },
    [4] = {
      { "h", "Raid priorities" },
      { "p", "Healer: Flash of Light as the default, Holy Light when the tank is taking heavy damage. Mana over a long fight is the constraint, not throughput. Cleanse quickly; many raid fights are decided by dispels." },
      { "e", "Casting a lower rank of a heal to save Mana is normal practice: a low-rank Flash of Light is the bread and butter." },
      { "e", "Assign Blessings before the pull. Salvation on damage dealers is worth more raid damage than any button you press." },
      { "f", "There is no Salvation to assign, so threat is the tank's and the damage dealers' own job. Protection's Swift Judgement is its own action that unleashes the Seal; it does not reset a cooldown." },
    },
  },

  macros = {
    [1] = { { "h", "Two to start with" }, M.judge, M.healSelf },
    [2] = { { "h", "For the road" }, M.judge, M.strike, M.flash, M.stun },
    [3] = { { "h", "For dungeons" }, M.flash, M.light, M.cleanse, M.bop, M.stun },
    [4] = { { "h", "A raid set" }, M.flash, M.light, M.cleanse, M.bop, M.loh, M.focusStun, M.assist },
  },

  group = {
    [1] = {
      { "h", "In a group" },
      { "p", "Say which job you are doing: healing, tanking or damage. Whatever the job, put a Blessing on each player and keep your Aura on. If someone is about to die, heal them even if you are not the healer." },
    },
    [2] = {
      { "h", "Dungeons while leveling" },
      { "p", "You can heal any leveling dungeon in Retribution talents: carry a one-handed weapon and shield with Intellect on them and drink between pulls. Ask each player which Blessing they want; melee take Might, casters Wisdom." },
    },
    [3] = {
      { "h", "At the top level" },
      { "p", "Healers: watch the tank first and learn which enemy abilities must be cleansed. Blessing of Protection saves a caster who pulled an enemy, but it also stops that player's own melee attacks, so never put it on the tank." },
    },
    [4] = {
      { "h", "Raiding here" },
      { "p", "No heroic or mythic mode. Paladins raid mostly as healers; the job is efficient tank healing, cleansing and keeping Blessings up on a group that needs them recast by hand." },
      { "e", "Classic raids are 20 and 40 players. Blessings last five minutes, or fifteen for the Greater versions, and a raid with several Paladins splits them by class." },
    },
  },
})
