-- Panoply Suite 0.8.4 class pages: what all nine classes share on a topic. "before" comes ahead of the class's own words,
-- "after" follows them. Written by Panoply Suite; the game facts are Blizzard's.
-- FOREVER facts here (talents from 10, a second specialization from the class trainer at 40, Legacy's Talented perk) are from
-- Blizzard's own articles as read on 8 Nov 2026 (logs/research/forever-class-pages-research.md, S2, S8, S13); not checked in game.
-- The macro commands are the ones Classic Era 1.15 has; none was tried on WoW Forever (the "f" paragraph under Macros says so).
-- Focus: Classic Era has no focus target, so every @focus macro in Data/<Class>.lua is WoW Forever only. That the Forever client
-- has one is read from its API list in tests/clientapi/api_forever.txt (FocusUnit, FocusFrame_OpenMenu); the [@focus] macro
-- condition itself was not tried in the game.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

CP.shared = {
  spells = {
    after = {
      all = {
        { "h", "Talent points" },
        { "e", "Talents start at level 10, one point a level, 51 points at level 60. You have one set of talents; changing it costs gold at your class trainer, more each time." },
        { "f", "Talents start at level 10. At level 40 your class trainer sells a second specialization, so one character can keep two sets of talents." },
        { "f", "Legacy's Talented perk hands out talent points up to five levels early. A build that is written level by level does not count those early points unless it says so, so with the perk you can be a few points ahead of it." },
      },
    },
  },
  macros = {
    before = {
      [1] = {
        { "h", "How to make a macro" },
        { "p", "A macro is a button you write yourself. Type /macro in chat, click New, give it a name and any icon, and type the lines shown below into the big box. Then drag the new button onto your action bar." },
        { "p", "One press of a macro casts one spell. A macro cannot play the game for you, and nothing here tries to." },
      },
      [2] = {
        { "h", "How to make a macro" },
        { "p", "Type /macro, click New, type the lines, and drag the button to a bar. One press casts one spell; small things that are not spells (starting your attack, an order to a pet) can ride along on the same press." },
      },
      [3] = {
        { "h", "Ground rules" },
        { "p", "One press, one spell on the global cooldown. Starting your attack, a pet order, a trinket or stopping your own cast can share the press. The words in square brackets pick the target: the unit under your mouse first, then your target." },
      },
      [4] = {
        { "h", "Ground rules" },
        { "p", "Same macro language you know, older rules: one press, one spell on the global cooldown, and no macro can chain a rotation. The set below covers mouseover casts, assist, interrupts and cooldowns." },
      },
    },
    after = {
      all = {
        { "e", "A macro holds 255 characters; each one shows its count." },
        { "f", "A macro holds 255 characters; each one shows its count. These use only the basic macro commands, plus a focus target for the raid sets. If a line does nothing, take the words in square brackets out of it." },
      },
    },
  },
}
