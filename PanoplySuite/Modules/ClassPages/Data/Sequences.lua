-- Panoply Suite 0.9.4 (next): the order of play behind the next ability display (the 0.9.4 Rotation sequencer) on the class pages. Panoply Suite's own words
-- and its own order, built from each class's own spell list in the game's client tables; no other add-on's or site's rotation was
-- read. DISPLAY ONLY: Modules/ClassPages/Sequencer.lua draws these as a strip; nothing here is ever pressed for the player.
--
-- A class has one or more sequences (the Hunter, the flagship, has three; the layout is the same for all nine):
--   { key = "solo", label = "Leveling: one enemy", steps = { step, ... } }
-- A step is { "Spell name", "one plain line on when", once = true, f = "name on WoW Forever", e = "name on Classic Era" }.
--   once = true: a buff, an opener or a damage-over-time you put on once per fight; the strip drops it after you cast it, and brings
--   it back when the fight ends or you pick another target. Without it the step stays: it is what you press again and again.
-- Every spell name is checked per game by tools/check_class_macros.lua (the name exists on that game, without a rank, and belongs to
-- the class); a step that fails on a game is not shown there (Data/Verified.lua).
-- The beta reads cooldowns, what is usable now and the spells you know. It does NOT read which buffs or enemy debuffs are up.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages

CP.sequences = {
  HUNTER = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Hunter's Mark", "Marks the enemy so it takes more ranged damage. Send your pet in first: that is an order, not a spell.", once = true },
      { "Serpent Sting", "A damage-over-time shot. Put it on once.", once = true },
      { "Arcane Shot", "Your quick shot. Press it whenever it is ready and Mana allows." },
      { "Concussive Shot", "Slows an enemy that is coming for you, so you can keep shooting." },
      { "Wing Clip", "When the enemy reaches you: slow it, then walk away." },
      { "Raptor Strike", "Your melee strike, for the moment the enemy is on top of you." },
    } },
    { key = "pair", label = "Leveling: two enemies", steps = {
      { "Freezing Trap", "Set it before the pull. It holds the extra enemy while you fight the first.", once = true },
      { "Hunter's Mark", "On the enemy you fight first.", once = true },
      { "Serpent Sting", "On the same enemy.", once = true },
      { "Multi-Shot", "Hits your target and the enemies next to it. Only when none of them is the trapped one." },
      { "Arcane Shot", "Your quick shot, on cooldown." },
      { "Mend Pet", "Heals your pet. Use it when its health bar drops.", },
    } },
    { key = "dungeon", label = "In a dungeon", steps = {
      { "Hunter's Mark", "On the enemy the group is killing. Wait a few seconds for the tank first.", once = true },
      { "Aimed Shot", "Your big shot, between automatic shots. Every Hunter has it on WoW Forever." },
      { "Multi-Shot", "When several enemies are being kept busy by the tank." },
      { "Arcane Shot", "Fills the gaps between the other two." },
      { "Feign Death", "Drops your threat when an enemy turns on you." },
    } },
  },

  WARRIOR = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Battle Shout", "More attack power for you. Before the pull.", once = true },
      { "Charge", "Opens the fight from a distance. Battle Stance, out of a fight.", once = true },
      { "Rend", "A bleed. Put it on once.", once = true },
      { "Heroic Strike", "Spend spare Rage on your next swing." },
      { "Thunder Clap", "When two or more enemies are on you." },
    } },
  },

  PALADIN = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Blessing of Might", "More attack power. Lasts several minutes.", once = true },
      { "Seal of Righteousness", "The Seal that fills your weapon hits. Put it on before the pull.", once = true },
      { "Judgement", "Spends the Seal for a strike. Use it whenever it is ready." },
      { "Consecration", "Ground fire. Worth its Mana when two or more enemies are on you." },
      { "Holy Light", "Heal yourself when your health is low." },
    } },
  },

  ROGUE = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Stealth", "Creep up on the enemy before the fight.", once = true },
      { "Cheap Shot", "Opens from Stealth and stuns the enemy.", once = true },
      { "Sinister Strike", "Your basic strike. Builds combo points." },
      { "Slice and Dice", "Faster attacks. Spend a few combo points on it once.", once = true },
      { "Eviscerate", "Spends your combo points for big damage." },
      { "Kick", "Stops an enemy spell. Only when it casts." },
    } },
  },

  PRIEST = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Power Word: Shield", "Soaks damage. Before the pull or as the enemy arrives.", once = true },
      { "Shadow Word: Pain", "A damage-over-time spell. Put it on once.", once = true },
      { "Mind Blast", "Your quick, strong spell. Use it on cooldown." },
      { "Smite", "Filler damage while the others recover." },
      { "Renew", "A heal over time. Use it on yourself when hurt." },
    } },
  },

  SHAMAN = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Lightning Shield", "Hurts enemies that hit you. Keep it on.", once = true },
      { "Lightning Bolt", "Opens the fight from range." },
      { "Flame Shock", "A damage-over-time shock. Put it on once.", once = true },
      { "Earth Shock", "Instant damage and it stops an enemy spell." },
      { "Healing Wave", "Heal yourself when your health is low." },
    } },
  },

  MAGE = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Frost Armor", "Protects you and slows what hits you. Keep it on.", once = true },
      { "Frostbolt", "Your main spell. It also slows the enemy." },
      { "Fire Blast", "A quick extra hit between Frostbolts." },
      { "Frost Nova", "When an enemy reaches you: freeze it, then walk away." },
      { "Evocation", "Gives Mana back when you are nearly out.", once = true },
    } },
  },

  WARLOCK = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Immolate", "Fire damage over time. Opens the fight.", once = true },
      { "Corruption", "Shadow damage over time.", once = true },
      { "Curse of Agony", "A curse that hurts a little each moment.", once = true },
      { "Shadow Bolt", "Your main spell while the others tick." },
      { "Life Tap", "Turns health into Mana. Only when your health is fine and Mana is low." },
    } },
  },

  DRUID = {
    { key = "solo", label = "Leveling: one enemy", steps = {
      { "Mark of the Wild", "More of every stat for you. Lasts a long time.", once = true },
      { "Moonfire", "Quick damage with a little more after it. Opens the fight.", once = true },
      { "Wrath", "Your main spell." },
      { "Rejuvenation", "A heal over time. Put it on yourself when hurt.", once = true },
      { "Healing Touch", "The slow, big heal. Use it when out of danger." },
    } },
  },
}

-- the spell name a step uses on this game
function CP:StepName(st, forever)
  if forever then return st.f or st[1] end
  return st.e or st[1]
end
