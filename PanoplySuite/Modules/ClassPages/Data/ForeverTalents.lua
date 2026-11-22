-- Panoply Suite 0.9.5 phase 4H: the talents WoW Forever added to the class trees, as the class pages' own WoW Forever notes name them
-- ("New in the trees: ..." in Data/Hunter.lua, Mage.lua, Priest.lua and Warlock.lua, from Blizzard's class articles as read on 8 Nov
-- 2026: logs/research/forever-class-pages-research.md). The Talents tab badges these "New in Forever", with the note in the tooltip
-- (spec 03 section 4); the notes moved here from the How to play text.
-- UNVERIFIED: none of these names is in Modules/SpecTrainer/Data/TalentData.lua (the client's DB2 tables of Forever 1.60.1.70707), so
-- the badge shows when the game's own talent window names a talent this way (ST:LiveTalent), on the live client only.
-- true = no note of its own; a string = the note.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
CP.FOREVER_TALENTS = {
  HUNTER = { ["Summon Hawk"] = "a short-lived helper, not another pet.", ["Focused Fire"] = true, ["Lone Wolf"] = true, ["Sniper Shot"] = true,
    ["Strider Kick"] = true, ["Expose Prey"] = true, ["Lacerating Strikes"] = true },
  MAGE = { ["Arcane Blast"] = true, ["Missile Barrage"] = true, ["Heating Up"] = true,
    ["Ice Lance"] = "it shares an 8-second cooldown with Fire Blast, so you get one or the other.", ["Fingers of Frost"] = true },
  PRIEST = { ["Soul Warding"] = true, ["Penance"] = true, ["Divine Aegis"] = true, ["Prayer of Mending"] = true, ["Litany of Light"] = true,
    ["Devouring Contagion"] = true },
  WARLOCK = { ["Wrack"] = true, ["Pandemic"] = true, ["Demonic Brand"] = true, ["Demonic Knowledge"] = true, ["Demonic Pact"] = true,
    ["Bane of Havoc"] = true, ["Incinerate"] = true },
}
