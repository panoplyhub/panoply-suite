-- Panoply Suite, Hunter class page, Pet topic: the facts (0.8.4). WRITTEN BY tools/build_hunterpet_data.py: do not edit by hand.
-- Abilities, ranks, pet levels, spell ids and which family can use what: Blizzard's own client tables (tools/cache), one
-- list per client because WoW Forever has abilities and a family Classic Era does not. Training-point costs, diets and
-- the wild beasts that know a rank: the research ledger of 9 Nov 2026 (logs/research/forever-pet-teachers.*), in our own
-- format. Beasts marked f = true were reported in WoW Forever and are offered there only; the others are the Classic
-- record and are offered on both clients. No coordinates are stored here: map markers come from Panoply Suite's own
-- NPC data and from where the player has met the beast (Modules/HunterPet/Core.lua).
local ADDON, Panoply = ...
local D = {}
Panoply.HunterPetData = D

D.FOODS = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" }
-- what each family eats (the family's name on Classic Era where it differs: eraName)
D.families = {
  ["Bat"] = { diet = { "Fungus", "Fruit" } },
  ["Bear"] = { diet = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" } },
  ["Bird of Prey"] = { diet = { "Meat" }, eraName = "Owl" },
  ["Boar"] = { diet = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" } },
  ["Carrion Bird"] = { diet = { "Meat", "Fish" } },
  ["Cat"] = { diet = { "Meat", "Fish" } },
  ["Crab"] = { diet = { "Fish", "Bread", "Fungus", "Fruit" } },
  ["Crocolisk"] = { diet = { "Meat", "Fish" } },
  ["Fox"] = { diet = { "Meat" } },
  ["Gorilla"] = { diet = { "Fungus", "Fruit" } },
  ["Hyena"] = { diet = { "Meat", "Fruit" } },
  ["Raptor"] = { diet = { "Meat" } },
  ["Scorpid"] = { diet = { "Meat" } },
  ["Spider"] = { diet = { "Meat" } },
  ["Tallstrider"] = { diet = { "Cheese", "Fungus", "Fruit" } },
  ["Turtle"] = { diet = { "Fish", "Fungus", "Fruit" } },
  ["Wind Serpent"] = { diet = { "Fish", "Cheese", "Bread" } },
  ["Wolf"] = { diet = { "Meat" } },
}

-- per client: the families, and each ability { kind = "wild" (learned by taming a beast that knows it) | "trainer" (bought from a
-- pet trainer), users = "all" | { families }, first = { family = lowest rank that family can use }, ranks = { { r = rank, lvl = pet
-- level, tp = training points (nil: not known), teach = the hunter's Beast Training spell, pet = the pet's own spell, auto = every
-- hunter starts with it } } }
D.clients = {
  forever = {
    families = { "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat", "Crab", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" },
    abilities = {
      ["Arcane Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24495, pet = 24493 },
        { r = 2, lvl = 30, tp = 15, teach = 24508, pet = 24497 },
        { r = 3, lvl = 40, tp = 45, teach = 24509, pet = 24500 },
        { r = 4, lvl = 50, tp = 90, teach = 24510, pet = 24501 },
      } },
      ["Bite"] = { kind = "wild", users = { "Bat", "Bear", "Boar", "Carrion Bird", "Cat", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 17254, pet = 17253 },
        { r = 2, lvl = 8, tp = 4, teach = 17262, pet = 17255 },
        { r = 3, lvl = 16, tp = 7, teach = 17263, pet = 17256 },
        { r = 4, lvl = 24, tp = 10, teach = 17264, pet = 17257 },
        { r = 5, lvl = 32, tp = 13, teach = 17265, pet = 17258 },
        { r = 6, lvl = 40, tp = 17, teach = 17266, pet = 17259 },
        { r = 7, lvl = 48, tp = 21, teach = 17267, pet = 17260 },
        { r = 8, lvl = 56, tp = 25, teach = 17268, pet = 17261 },
      } },
      ["Charge"] = { kind = "wild", users = { "Boar" }, ranks = {
        { r = 1, lvl = 1, tp = 5, teach = 7370, pet = 7371 },
        { r = 2, lvl = 12, tp = 9, teach = 26184, pet = 26177 },
        { r = 3, lvl = 24, tp = 13, teach = 26185, pet = 26178 },
        { r = 4, lvl = 36, tp = 17, teach = 26186, pet = 26179 },
        { r = 5, lvl = 48, tp = 21, teach = 26202, pet = 26201 },
        { r = 6, lvl = 60, tp = 25, teach = 28343, pet = 27685 },
      } },
      ["Claw"] = { kind = "wild", users = { "Bear", "Bird of Prey", "Carrion Bird", "Cat", "Crab", "Raptor", "Scorpid" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 2980, pet = 16827 },
        { r = 2, lvl = 8, tp = 4, teach = 2981, pet = 16828 },
        { r = 3, lvl = 16, tp = 7, teach = 2982, pet = 16829 },
        { r = 4, lvl = 24, tp = 10, teach = 3667, pet = 16830 },
        { r = 5, lvl = 32, tp = 13, teach = 2975, pet = 16831 },
        { r = 6, lvl = 40, tp = 17, teach = 2976, pet = 16832 },
        { r = 7, lvl = 48, tp = 21, teach = 2977, pet = 3010 },
        { r = 8, lvl = 56, tp = 25, teach = 3666, pet = 3009 },
      } },
      ["Cower"] = { kind = "wild", users = "all", ranks = {
        { r = 1, lvl = 5, tp = 8, teach = 1747, pet = 1742 },
        { r = 2, lvl = 15, tp = 10, teach = 1748, pet = 1753 },
        { r = 3, lvl = 25, tp = 12, teach = 1749, pet = 1754 },
        { r = 4, lvl = 35, tp = 14, teach = 1750, pet = 1755 },
        { r = 5, lvl = 45, tp = 16, teach = 1751, pet = 1756 },
        { r = 6, lvl = 55, tp = 18, teach = 16698, pet = 16697 },
      } },
      ["Dash"] = { kind = "wild", users = { "Bear", "Boar", "Cat", "Crab", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wolf" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 23100, pet = 23099 },
        { r = 2, lvl = 40, tp = 20, teach = 23111, pet = 23109 },
        { r = 3, lvl = 50, tp = 25, teach = 23112, pet = 23110 },
      } },
      ["Demoralizing Screech"] = { kind = "wild", users = { "Carrion Bird" }, ranks = {
        { r = 1, lvl = 8, tp = 10, teach = 24424, pet = 24423 },
        { r = 2, lvl = 24, tp = 15, teach = 24580, pet = 24577 },
        { r = 3, lvl = 48, tp = 20, teach = 24581, pet = 24578 },
        { r = 4, lvl = 56, tp = 25, teach = 24582, pet = 24579 },
      } },
      ["Dismember"] = { kind = "wild", users = { "Crocolisk" }, ranks = {
        { r = 1, lvl = 12, tp = 1, teach = 1264937, pet = 1264758 },
        { r = 2, lvl = 24, tp = 1, teach = 1264939, pet = 1264927 },
        { r = 3, lvl = 36, tp = 1, teach = 1264970, pet = 1264929 },
        { r = 4, lvl = 48, tp = 1, teach = 1264971, pet = 1264930 },
        { r = 5, lvl = 60, tp = 1, teach = 1264972, pet = 1264933 },
      } },
      ["Dive"] = { kind = "wild", users = { "Bat", "Bird of Prey", "Carrion Bird", "Wind Serpent" }, first = { ["Bat"] = 2 }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 23146, pet = 23145 },
        { r = 2, lvl = 40, tp = 20, teach = 23149, pet = 23147 },
        { r = 3, lvl = 50, tp = 25, teach = 23150, pet = 23148 },
      } },
      ["Dust Cloud"] = { kind = "wild", users = { "Tallstrider" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1265907, pet = 1265899 },
        { r = 2, lvl = 24, tp = 0, teach = 1265908, pet = 1265901 },
        { r = 3, lvl = 36, tp = 0, teach = 1265909, pet = 1265902 },
        { r = 4, lvl = 48, tp = 0, teach = 1265913, pet = 1265903 },
        { r = 5, lvl = 60, tp = 0, teach = 1265911, pet = 1265904 },
      } },
      ["Fire Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24440, pet = 23992 },
        { r = 2, lvl = 30, tp = 15, teach = 24441, pet = 24439 },
        { r = 3, lvl = 40, tp = 45, teach = 24463, pet = 24444 },
        { r = 4, lvl = 50, tp = 90, teach = 24464, pet = 24445 },
      } },
      ["Frost Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24475, pet = 24446 },
        { r = 2, lvl = 30, tp = 15, teach = 24476, pet = 24447 },
        { r = 3, lvl = 40, tp = 45, teach = 24477, pet = 24448 },
        { r = 4, lvl = 50, tp = 90, teach = 24478, pet = 24449 },
      } },
      ["Furious Howl"] = { kind = "wild", users = { "Wolf" }, ranks = {
        { r = 1, lvl = 10, tp = 10, teach = 24609, pet = 24604 },
        { r = 2, lvl = 24, tp = 15, teach = 24608, pet = 24605 },
        { r = 3, lvl = 40, tp = 20, teach = 24607, pet = 24603 },
        { r = 4, lvl = 56, tp = 25, teach = 24599, pet = 24597 },
      } },
      ["Great Stamina"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 5, teach = 4195, pet = 4187 },
        { r = 2, lvl = 12, tp = 10, teach = 4196, pet = 4188 },
        { r = 3, lvl = 18, tp = 15, teach = 4197, pet = 4189 },
        { r = 4, lvl = 24, tp = 25, teach = 4198, pet = 4190 },
        { r = 5, lvl = 30, tp = 50, teach = 4199, pet = 4191 },
        { r = 6, lvl = 36, tp = 75, teach = 4200, pet = 4192 },
        { r = 7, lvl = 42, tp = 100, teach = 4201, pet = 4193 },
        { r = 8, lvl = 48, tp = 125, teach = 4202, pet = 4194 },
        { r = 9, lvl = 54, tp = 150, teach = 5048, pet = 5041 },
        { r = 10, lvl = 60, tp = 185, teach = 5049, pet = 5042 },
      } },
      ["Growl"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 0, teach = 1853, pet = 2649, auto = true },
        { r = 2, lvl = 10, tp = 0, teach = 14922, pet = 14916, auto = true },
        { r = 3, lvl = 20, tp = 0, teach = 14923, pet = 14917 },
        { r = 4, lvl = 30, tp = 0, teach = 14924, pet = 14918 },
        { r = 5, lvl = 40, tp = 0, teach = 14925, pet = 14919 },
        { r = 6, lvl = 50, tp = 0, teach = 14926, pet = 14920 },
        { r = 7, lvl = 60, tp = 0, teach = 14927, pet = 14921 },
      } },
      ["Lightning Breath"] = { kind = "wild", users = { "Wind Serpent" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 24845, pet = 24844 },
        { r = 2, lvl = 12, tp = 5, teach = 25013, pet = 25008 },
        { r = 3, lvl = 24, tp = 10, teach = 25014, pet = 25009 },
        { r = 4, lvl = 36, tp = 15, teach = 25015, pet = 25010 },
        { r = 5, lvl = 48, tp = 20, teach = 25016, pet = 25011 },
        { r = 6, lvl = 60, tp = 25, teach = 25017, pet = 25012 },
      } },
      ["Mine!"] = { kind = "wild", users = { "Bird of Prey" }, ranks = {
        { r = 1, lvl = 10, tp = 0, teach = 1265059, pet = 1265054 },
        { r = 2, lvl = 20, tp = 0, teach = 1265060, pet = 1265055 },
        { r = 3, lvl = 30, tp = 0, teach = 1265061, pet = 1265056 },
        { r = 4, lvl = 40, tp = 0, teach = 1265062, pet = 1265057 },
        { r = 5, lvl = 50, tp = 0, teach = 1265064, pet = 1265058 },
      } },
      ["Natural Armor"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 24547, pet = 24545 },
        { r = 2, lvl = 12, tp = 5, teach = 24556, pet = 24549 },
        { r = 3, lvl = 18, tp = 10, teach = 24557, pet = 24550 },
        { r = 4, lvl = 24, tp = 15, teach = 24558, pet = 24551 },
        { r = 5, lvl = 30, tp = 25, teach = 24559, pet = 24552 },
        { r = 6, lvl = 36, tp = 50, teach = 24560, pet = 24553 },
        { r = 7, lvl = 42, tp = 75, teach = 24561, pet = 24554 },
        { r = 8, lvl = 48, tp = 100, teach = 24562, pet = 24555 },
        { r = 9, lvl = 54, tp = 125, teach = 24631, pet = 24629 },
        { r = 10, lvl = 60, tp = 150, teach = 24632, pet = 24630 },
      } },
      ["Nature Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24494, pet = 24492 },
        { r = 2, lvl = 30, tp = 15, teach = 24511, pet = 24502 },
        { r = 3, lvl = 40, tp = 45, teach = 24512, pet = 24503 },
        { r = 4, lvl = 50, tp = 90, teach = 24513, pet = 24504 },
      } },
      ["Pinch"] = { kind = "wild", users = { "Crab" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1264745, pet = 1264735 },
        { r = 2, lvl = 24, tp = 0, teach = 1264749, pet = 1264736 },
        { r = 3, lvl = 36, tp = 0, teach = 1264750, pet = 1264739 },
        { r = 4, lvl = 48, tp = 0, teach = 1264751, pet = 1264741 },
        { r = 5, lvl = 60, tp = 0, teach = 1264752, pet = 1264742 },
      } },
      ["Prowl"] = { kind = "wild", users = { "Cat" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 24451, pet = 24450 },
        { r = 2, lvl = 40, tp = 20, teach = 24454, pet = 24452 },
        { r = 3, lvl = 50, tp = 25, teach = 24455, pet = 24453 },
      } },
      ["Savage Rend"] = { kind = "wild", users = { "Raptor" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1265831, pet = 1265065 },
        { r = 2, lvl = 24, tp = 0, teach = 1265833, pet = 1265066 },
        { r = 3, lvl = 36, tp = 0, teach = 1265834, pet = 1265067 },
        { r = 4, lvl = 48, tp = 0, teach = 1265835, pet = 1265068 },
        { r = 5, lvl = 60, tp = 0, teach = 1265836, pet = 1265069 },
      } },
      ["Scorpid Poison"] = { kind = "wild", users = { "Scorpid" }, ranks = {
        { r = 1, lvl = 8, tp = 10, teach = 24641, pet = 24640 },
        { r = 2, lvl = 24, tp = 15, teach = 24584, pet = 24583 },
        { r = 3, lvl = 40, tp = 20, teach = 24588, pet = 24586 },
        { r = 4, lvl = 56, tp = 25, teach = 24589, pet = 24587 },
      } },
      ["Shadow Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24490, pet = 24488 },
        { r = 2, lvl = 30, tp = 15, teach = 24514, pet = 24505 },
        { r = 3, lvl = 40, tp = 45, teach = 24515, pet = 24506 },
        { r = 4, lvl = 40, tp = 90, teach = 24516, pet = 24507 },
      } },
      ["Shell Shield"] = { kind = "wild", users = { "Turtle" }, ranks = {
        { r = 1, lvl = 20, tp = 15, teach = 26065, pet = 26064 },
      } },
      ["Sonic Blast"] = { kind = "wild", users = { "Bat" }, ranks = {
        { r = 1, lvl = 12, pet = 1264478 },
        { r = 2, lvl = 24, pet = 1264479 },
        { r = 3, lvl = 36, pet = 1264480 },
        { r = 4, lvl = 48, pet = 1264481 },
        { r = 5, lvl = 60, pet = 1264482 },
      } },
      ["Swipe"] = { kind = "wild", users = { "Bear" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1264727, pet = 1264494 },
        { r = 2, lvl = 24, tp = 0, teach = 1264729, pet = 1264497 },
        { r = 3, lvl = 36, tp = 0, teach = 1264730, pet = 1264498 },
        { r = 4, lvl = 48, tp = 0, teach = 1264731, pet = 1264501 },
        { r = 5, lvl = 60, tp = 0, teach = 1264732, pet = 1264502 },
      } },
      ["Tendon Rip"] = { kind = "wild", users = { "Hyena" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1265043, pet = 1265038 },
        { r = 2, lvl = 24, tp = 0, teach = 1265045, pet = 1265039 },
        { r = 3, lvl = 36, tp = 0, teach = 1265046, pet = 1265040 },
        { r = 4, lvl = 48, tp = 0, teach = 1265047, pet = 1265041 },
        { r = 5, lvl = 60, tp = 0, teach = 1265048, pet = 1265042 },
      } },
      ["Thunderstomp"] = { kind = "wild", users = { "Gorilla" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 26094, pet = 26090 },
        { r = 2, lvl = 40, tp = 20, teach = 26189, pet = 26187 },
        { r = 3, lvl = 50, tp = 25, teach = 26190, pet = 26188 },
        { r = 4, lvl = 60, tp = 0, teach = 1264456, pet = 1264455 },
      } },
      ["Trickster's Dance"] = { kind = "wild", users = { "Fox" }, ranks = {
        { r = 1, lvl = 20, tp = 10, teach = 1310617, pet = 1310612 },
      } },
      ["Web"] = { kind = "wild", users = { "Spider" }, ranks = {
        { r = 1, lvl = 12, tp = 0, teach = 1265887, pet = 1265843 },
        { r = 2, lvl = 24, tp = 0, teach = 1265888, pet = 1265878 },
        { r = 3, lvl = 36, tp = 0, teach = 1265890, pet = 1265880 },
        { r = 4, lvl = 48, tp = 0, teach = 1265891, pet = 1265881 },
        { r = 5, lvl = 60, tp = 0, teach = 1265892, pet = 1265883 },
      } },
    },
  },
  era = {
    families = { "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat", "Crab", "Crocolisk", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" },
    abilities = {
      ["Arcane Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24495, pet = 24493 },
        { r = 2, lvl = 30, tp = 15, teach = 24508, pet = 24497 },
        { r = 3, lvl = 40, tp = 45, teach = 24509, pet = 24500 },
        { r = 4, lvl = 50, tp = 90, teach = 24510, pet = 24501 },
      } },
      ["Bite"] = { kind = "wild", users = { "Bat", "Bear", "Boar", "Carrion Bird", "Cat", "Crocolisk", "Gorilla", "Hyena", "Raptor", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 17254, pet = 17253 },
        { r = 2, lvl = 8, tp = 4, teach = 17262, pet = 17255 },
        { r = 3, lvl = 16, tp = 7, teach = 17263, pet = 17256 },
        { r = 4, lvl = 24, tp = 10, teach = 17264, pet = 17257 },
        { r = 5, lvl = 32, tp = 13, teach = 17265, pet = 17258 },
        { r = 6, lvl = 40, tp = 17, teach = 17266, pet = 17259 },
        { r = 7, lvl = 48, tp = 21, teach = 17267, pet = 17260 },
        { r = 8, lvl = 56, tp = 25, teach = 17268, pet = 17261 },
      } },
      ["Charge"] = { kind = "wild", users = { "Boar" }, ranks = {
        { r = 1, lvl = 1, tp = 5, teach = 7370, pet = 7371 },
        { r = 2, lvl = 12, tp = 9, teach = 26184, pet = 26177 },
        { r = 3, lvl = 24, tp = 13, teach = 26185, pet = 26178 },
        { r = 4, lvl = 36, tp = 17, teach = 26186, pet = 26179 },
        { r = 5, lvl = 48, tp = 21, teach = 26202, pet = 26201 },
        { r = 6, lvl = 60, tp = 25, teach = 28343, pet = 27685 },
      } },
      ["Claw"] = { kind = "wild", users = { "Bear", "Bird of Prey", "Carrion Bird", "Cat", "Crab", "Raptor", "Scorpid" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 2980, pet = 16827 },
        { r = 2, lvl = 8, tp = 4, teach = 2981, pet = 16828 },
        { r = 3, lvl = 16, tp = 7, teach = 2982, pet = 16829 },
        { r = 4, lvl = 24, tp = 10, teach = 3667, pet = 16830 },
        { r = 5, lvl = 32, tp = 13, teach = 2975, pet = 16831 },
        { r = 6, lvl = 40, tp = 17, teach = 2976, pet = 16832 },
        { r = 7, lvl = 48, tp = 21, teach = 2977, pet = 3010 },
        { r = 8, lvl = 56, tp = 25, teach = 3666, pet = 3009 },
      } },
      ["Cower"] = { kind = "wild", users = "all", ranks = {
        { r = 1, lvl = 5, tp = 8, teach = 1747, pet = 1742 },
        { r = 2, lvl = 15, tp = 10, teach = 1748, pet = 1753 },
        { r = 3, lvl = 25, tp = 12, teach = 1749, pet = 1754 },
        { r = 4, lvl = 35, tp = 14, teach = 1750, pet = 1755 },
        { r = 5, lvl = 45, tp = 16, teach = 1751, pet = 1756 },
        { r = 6, lvl = 55, tp = 18, teach = 16698, pet = 16697 },
      } },
      ["Dash"] = { kind = "wild", users = { "Boar", "Cat", "Hyena", "Tallstrider", "Wolf" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 23100, pet = 23099 },
        { r = 2, lvl = 40, tp = 20, teach = 23111, pet = 23109 },
        { r = 3, lvl = 50, tp = 25, teach = 23112, pet = 23110 },
      } },
      ["Dive"] = { kind = "wild", users = { "Bat", "Bird of Prey", "Carrion Bird", "Wind Serpent" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 23146, pet = 23145 },
        { r = 2, lvl = 40, tp = 20, teach = 23149, pet = 23147 },
        { r = 3, lvl = 50, tp = 25, teach = 23150, pet = 23148 },
      } },
      ["Fire Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24440, pet = 23992 },
        { r = 2, lvl = 30, tp = 15, teach = 24441, pet = 24439 },
        { r = 3, lvl = 40, tp = 45, teach = 24463, pet = 24444 },
        { r = 4, lvl = 50, tp = 90, teach = 24464, pet = 24445 },
      } },
      ["Frost Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24475, pet = 24446 },
        { r = 2, lvl = 30, tp = 15, teach = 24476, pet = 24447 },
        { r = 3, lvl = 40, tp = 45, teach = 24477, pet = 24448 },
        { r = 4, lvl = 50, tp = 90, teach = 24478, pet = 24449 },
      } },
      ["Furious Howl"] = { kind = "wild", users = { "Wolf" }, ranks = {
        { r = 1, lvl = 10, tp = 10, teach = 24609, pet = 24604 },
        { r = 2, lvl = 24, tp = 15, teach = 24608, pet = 24605 },
        { r = 3, lvl = 40, tp = 20, teach = 24607, pet = 24603 },
        { r = 4, lvl = 56, tp = 25, teach = 24599, pet = 24597 },
      } },
      ["Great Stamina"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 5, teach = 4195, pet = 4187 },
        { r = 2, lvl = 12, tp = 10, teach = 4196, pet = 4188 },
        { r = 3, lvl = 18, tp = 15, teach = 4197, pet = 4189 },
        { r = 4, lvl = 24, tp = 25, teach = 4198, pet = 4190 },
        { r = 5, lvl = 30, tp = 50, teach = 4199, pet = 4191 },
        { r = 6, lvl = 36, tp = 75, teach = 4200, pet = 4192 },
        { r = 7, lvl = 42, tp = 100, teach = 4201, pet = 4193 },
        { r = 8, lvl = 48, tp = 125, teach = 4202, pet = 4194 },
        { r = 9, lvl = 54, tp = 150, teach = 5048, pet = 5041 },
        { r = 10, lvl = 60, tp = 185, teach = 5049, pet = 5042 },
      } },
      ["Growl"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 0, teach = 1853, pet = 2649, auto = true },
        { r = 2, lvl = 10, tp = 0, teach = 14922, pet = 14916, auto = true },
        { r = 3, lvl = 20, tp = 0, teach = 14923, pet = 14917 },
        { r = 4, lvl = 30, tp = 0, teach = 14924, pet = 14918 },
        { r = 5, lvl = 40, tp = 0, teach = 14925, pet = 14919 },
        { r = 6, lvl = 50, tp = 0, teach = 14926, pet = 14920 },
        { r = 7, lvl = 60, tp = 0, teach = 14927, pet = 14921 },
      } },
      ["Lightning Breath"] = { kind = "wild", users = { "Wind Serpent" }, ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 24845, pet = 24844 },
        { r = 2, lvl = 12, tp = 5, teach = 25013, pet = 25008 },
        { r = 3, lvl = 24, tp = 10, teach = 25014, pet = 25009 },
        { r = 4, lvl = 36, tp = 15, teach = 25015, pet = 25010 },
        { r = 5, lvl = 48, tp = 20, teach = 25016, pet = 25011 },
        { r = 6, lvl = 60, tp = 25, teach = 25017, pet = 25012 },
      } },
      ["Natural Armor"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 1, tp = 1, teach = 24547, pet = 24545 },
        { r = 2, lvl = 12, tp = 5, teach = 24556, pet = 24549 },
        { r = 3, lvl = 18, tp = 10, teach = 24557, pet = 24550 },
        { r = 4, lvl = 24, tp = 15, teach = 24558, pet = 24551 },
        { r = 5, lvl = 30, tp = 25, teach = 24559, pet = 24552 },
        { r = 6, lvl = 36, tp = 50, teach = 24560, pet = 24553 },
        { r = 7, lvl = 42, tp = 75, teach = 24561, pet = 24554 },
        { r = 8, lvl = 48, tp = 100, teach = 24562, pet = 24555 },
        { r = 9, lvl = 54, tp = 125, teach = 24631, pet = 24629 },
        { r = 10, lvl = 60, tp = 150, teach = 24632, pet = 24630 },
      } },
      ["Nature Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24494, pet = 24492 },
        { r = 2, lvl = 30, tp = 15, teach = 24511, pet = 24502 },
        { r = 3, lvl = 40, tp = 45, teach = 24512, pet = 24503 },
        { r = 4, lvl = 50, tp = 90, teach = 24513, pet = 24504 },
      } },
      ["Prowl"] = { kind = "wild", users = { "Cat" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 24451, pet = 24450 },
        { r = 2, lvl = 40, tp = 20, teach = 24454, pet = 24452 },
        { r = 3, lvl = 50, tp = 25, teach = 24455, pet = 24453 },
      } },
      ["Scorpid Poison"] = { kind = "wild", users = { "Scorpid" }, ranks = {
        { r = 1, lvl = 8, tp = 10, teach = 24641, pet = 24640 },
        { r = 2, lvl = 24, tp = 15, teach = 24584, pet = 24583 },
        { r = 3, lvl = 40, tp = 20, teach = 24588, pet = 24586 },
        { r = 4, lvl = 56, tp = 25, teach = 24589, pet = 24587 },
      } },
      ["Screech"] = { kind = "wild", users = { "Bat", "Bird of Prey", "Carrion Bird" }, ranks = {
        { r = 1, lvl = 8, tp = 10, teach = 24424, pet = 24423 },
        { r = 2, lvl = 24, tp = 15, teach = 24580, pet = 24577 },
        { r = 3, lvl = 48, tp = 20, teach = 24581, pet = 24578 },
        { r = 4, lvl = 56, tp = 25, teach = 24582, pet = 24579 },
      } },
      ["Shadow Resistance"] = { kind = "trainer", users = "all", ranks = {
        { r = 1, lvl = 20, tp = 5, teach = 24490, pet = 24488 },
        { r = 2, lvl = 30, tp = 15, teach = 24514, pet = 24505 },
        { r = 3, lvl = 40, tp = 45, teach = 24515, pet = 24506 },
        { r = 4, lvl = 40, tp = 90, teach = 24516, pet = 24507 },
      } },
      ["Shell Shield"] = { kind = "wild", users = { "Turtle" }, ranks = {
        { r = 1, lvl = 20, tp = 15, teach = 26065, pet = 26064 },
      } },
      ["Thunderstomp"] = { kind = "wild", users = { "Gorilla" }, ranks = {
        { r = 1, lvl = 30, tp = 15, teach = 26094, pet = 26090 },
        { r = 2, lvl = 40, tp = 20, teach = 26189, pet = 26187 },
        { r = 3, lvl = 50, tp = 25, teach = 26190, pet = 26188 },
      } },
    },
  },
}

-- wild beasts reported to know a rank: [ability][rank] = { { n = name, lo, hi = its levels, z = zone, area = part of the zone,
-- inst = "dungeon" | "raid" (it lives inside one), rare, elite, f = reported in WoW Forever (offered there only) } }
D.teachers = {
  ["Bite"] = {
    [1] = {
      { n = "Ragged Scavenger", lo = 2, hi = 3, z = "Tirisfal Glades" },   -- ledger: ERA-ONLY
      { n = "Night Web Spider", lo = 3, hi = 4, z = "Tirisfal Glades" },   -- ledger: ERA-ONLY
      { n = "Forest Spider", lo = 5, hi = 6, z = "Elwynn Forest" },   -- ledger: ERA-ONLY
      { n = "Snow Tracker Wolf", lo = 6, hi = 7, z = "Dun Morogh" },   -- ledger: ERA-ONLY
      { n = "Juvenile Vuldren", lo = 1, hi = 1, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Vuldren", lo = 6, hi = 6, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
    },
    [2] = {
      { n = "Starving Winter Wolf", lo = 8, hi = 9, z = "Dun Morogh" },   -- ledger: ERA-ONLY
      { n = "Webwood Silkspinner", lo = 8, hi = 9, z = "Teldrassil" },   -- ledger: ERA-ONLY
      { n = "Prowler", lo = 9, hi = 10, z = "Elwynn Forest" },   -- ledger: ERA-ONLY
      { n = "Prairie Wolf Alpha", lo = 9, hi = 10, z = "Mulgore" },   -- ledger: ERA-ONLY
      { n = "Worg", lo = 10, hi = 11, z = "Silverpine Forest", area = "Tirisfal entrance", f = true },   -- ledger: FOREVER-REPORTED
    },
    [3] = {
      { n = "Bloodsnout Worg", lo = 16, hi = 17, z = "Silverpine Forest" },   -- ledger: ERA-ONLY
      { n = "Wood Lurker", lo = 17, hi = 18, z = "Loch Modan" },   -- ledger: ERA-ONLY
      { n = "Deepmoss Creeper", lo = 16, hi = 17, z = "Stonetalon Mountains" },   -- ledger: ERA-ONLY
    },
    [4] = {
      { n = "Black Ravager", lo = 24, hi = 25, z = "Duskwood" },   -- ledger: ERA-ONLY
      { n = "Giant Moss Creeper", lo = 24, hi = 25, z = "Hillsbrad Foothills" },   -- ledger: ERA-ONLY
      { n = "Leech Widow", lo = 24, hi = 24, z = "Wetlands", rare = true },   -- ledger: ERA-ONLY
    },
    [5] = {
      { n = "Plains Creeper", lo = 32, hi = 33, z = "Arathi Highlands" },   -- ledger: ERA-ONLY
      { n = "Sparkleshell Snapper", lo = 34, hi = 35, z = "Thousand Needles" },   -- ledger: ERA-ONLY
    },
    [6] = {
      { n = "Barnabus", lo = 38, hi = 38, z = "Badlands" },   -- ledger: ERA-ONLY
      { n = "Ripscale", lo = 39, hi = 39, z = "Dustwallow Marsh", rare = true },   -- ledger: ERA-ONLY
    },
    [7] = {
      { n = "Giant Surf Glider", lo = 48, hi = 50, z = "Tanaris" },   -- ledger: ERA-ONLY
      { n = "Rekk'tilac", lo = 48, hi = 48, z = "Searing Gorge", rare = true },   -- ledger: ERA-ONLY
    },
    [8] = {
      { n = "Bloodaxe Worg", lo = 56, hi = 57, z = "Blackrock Spire", inst = "dungeon" },   -- ledger: ERA-ONLY
    },
  },
  ["Charge"] = {
    [1] = {
      { n = "Mottled Boar", lo = 1, hi = 2, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Young Thistle Boar", lo = 1, hi = 2, z = "Teldrassil" },   -- ledger: ERA-ONLY
      { n = "Small Crag Boar", lo = 3, hi = 3, z = "Dun Morogh" },   -- ledger: ERA-ONLY
      { n = "Battleboar", lo = 3, hi = 4, z = "Mulgore" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Young Goretusk", lo = 12, hi = 13, z = "Westfall" },   -- ledger: ERA-ONLY
      { n = "Goretusk", lo = 14, hi = 15, z = "Westfall" },   -- ledger: ERA-ONLY
      { n = "Mangy Mountain Boar", lo = 14, hi = 15, z = "Loch Modan" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Bellygrub", lo = 24, hi = 24, z = "Redridge Mountains" },   -- ledger: ERA-ONLY
      { n = "Agam'ar", lo = 24, hi = 25, z = "Razorfen Kraul", inst = "dungeon" },   -- ledger: ERA-ONLY
    },
    [5] = {
      { n = "Ashmane Boar", lo = 48, hi = 49, z = "Blasted Lands" },   -- ledger: ERA-ONLY
      { n = "Grunter", lo = 50, hi = 50, z = "Blasted Lands", rare = true },   -- ledger: ERA-ONLY
    },
    [6] = {
      { n = "Plagued Swine", lo = 60, hi = 60, z = "Eastern Plaguelands" },   -- ledger: ERA-ONLY
    },
  },
  ["Claw"] = {
    [1] = {
      { n = "Scorpid Worker", lo = 3, hi = 3, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Strigid Owl", lo = 5, hi = 6, z = "Teldrassil" },   -- ledger: ERA-ONLY
      { n = "Ice Claw Bear", lo = 7, hi = 8, z = "Dun Morogh" },   -- ledger: ERA-ONLY
      { n = "Scrawny Ursera", lo = 3, hi = 4, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Ursera Scavenger", lo = 4, hi = 4, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Urs'anah", lo = 5, hi = 5, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
    },
    [2] = {
      { n = "Strigid Hunter", lo = 8, hi = 9, z = "Teldrassil" },   -- ledger: ERA-ONLY
      { n = "Young Forest Bear", lo = 8, hi = 9, z = "Elwynn Forest" },   -- ledger: ERA-ONLY
      { n = "Encrusted Surf Crawler", lo = 9, hi = 10, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Venomtail Scorpid", lo = 9, hi = 10, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Windsong Crawler", lo = 8, hi = 9, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
    },
    [3] = {
      { n = "Black Bear Patriarch", lo = 16, hi = 17, z = "Loch Modan" },   -- ledger: ERA-ONLY
      { n = "Shore Crawler", lo = 17, hi = 18, z = "Westfall" },   -- ledger: ERA-ONLY
      { n = "Clattering Crawler", lo = 19, hi = 20, z = "Ashenvale" },   -- ledger: ERA-ONLY
      { n = "Shadowgale Ursera", lo = 10, hi = 11, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
    },
    [4] = {
      { n = "Elder Ashenvale Bear", lo = 25, hi = 26, z = "Ashenvale" },   -- ledger: ERA-ONLY
      { n = "Scorpashi Snapper", lo = 30, hi = 31, z = "Desolace" },   -- ledger: ERA-ONLY
    },
    [5] = {
      { n = "Scorpashi Lasher", lo = 34, hi = 35, z = "Desolace" },   -- ledger: ERA-ONLY
      { n = "Vile Sting", lo = 35, hi = 35, z = "Thousand Needles", rare = true },   -- ledger: ERA-ONLY
    },
    [6] = {
      { n = "Scorpid Hunter", lo = 40, hi = 41, z = "Tanaris" },   -- ledger: ERA-ONLY
      { n = "Silt Crawler", lo = 40, hi = 41, z = "Swamp of Sorrows" },   -- ledger: ERA-ONLY
      { n = "Ironfur Bear", lo = 41, hi = 42, z = "Feralas" },   -- ledger: ERA-ONLY
    },
    [7] = {
      { n = "Ironfur Patriarch", lo = 48, hi = 49, z = "Feralas" },   -- ledger: ERA-ONLY
      { n = "Angerclaw Mauler", lo = 49, hi = 50, z = "Felwood" },   -- ledger: ERA-ONLY
    },
    [8] = {
      { n = "Elder Shardtooth", lo = 57, hi = 58, z = "Winterspring" },   -- ledger: ERA-ONLY
      { n = "Winterspring Screecher", lo = 57, hi = 59, z = "Winterspring" },   -- ledger: ERA-ONLY
    },
  },
  ["Cower"] = {
    [1] = {
      { n = "Juvenile Snow Leopard", lo = 5, hi = 6, z = "Dun Morogh" },   -- ledger: ERA-ONLY
      { n = "Greater Duskbat", lo = 6, hi = 7, z = "Tirisfal Glades" },   -- ledger: ERA-ONLY
      { n = "Nightsaber", lo = 5, hi = 6, z = "Teldrassil" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Giant Foreststrider", lo = 17, hi = 19, z = "Darkshore" },   -- ledger: ERA-ONLY
      { n = "Savannah Patriarch", lo = 15, hi = 16, z = "The Barrens" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Feral Mountain Lion", lo = 27, hi = 28, z = "Hillsbrad Foothills" },   -- ledger: ERA-ONLY
      { n = "Crag Stalker", lo = 25, hi = 26, z = "Thousand Needles" },   -- ledger: ERA-ONLY
    },
    [4] = {
      { n = "Ridge Stalker", lo = 36, hi = 37, z = "Badlands" },   -- ledger: ERA-ONLY
    },
    [5] = {
      { n = "Jaguero Stalker", lo = 50, hi = 50, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
    },
    [6] = {
      { n = "Frostsaber Cub", lo = 55, hi = 56, z = "Winterspring" },   -- ledger: ERA-ONLY
    },
  },
  ["Dash"] = {
    [1] = {
      { n = "Kurzen War Tiger", lo = 32, hi = 33, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Stranglethorn Tiger", lo = 32, hi = 33, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Bonepaw Hyena", lo = 33, hi = 35, z = "Desolace" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Bhag'thera", lo = 40, hi = 40, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Longtooth Runner", lo = 40, hi = 41, z = "Feralas" },   -- ledger: ERA-ONLY
      { n = "Ridge Stalker Patriarch", lo = 40, hi = 41, z = "Badlands" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Grunter", lo = 50, hi = 50, z = "Blasted Lands" },   -- ledger: ERA-ONLY
      { n = "Vilebranch Raiding Wolf", lo = 50, hi = 51, z = "The Hinterlands" },   -- ledger: ERA-ONLY
      { n = "Ravage", lo = 51, hi = 51, z = "Blasted Lands" },   -- ledger: ERA-ONLY
    },
  },
  ["Dive"] = {
    [1] = {
      { n = "Young Mesa Buzzard", lo = 31, hi = 32, z = "Arathi Highlands" },   -- ledger: ERA-ONLY
      { n = "Mesa Buzzard", lo = 34, hi = 35, z = "Arathi Highlands" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Roc", lo = 41, hi = 43, z = "Tanaris" },   -- ledger: ERA-ONLY
      { n = "Vale Screecher", lo = 41, hi = 43, z = "Feralas" },   -- ledger: ERA-ONLY
      { n = "Fire Roc", lo = 43, hi = 45, z = "Tanaris" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Carrion Vulture", lo = 50, hi = 52, z = "Western Plaguelands" },   -- ledger: ERA-ONLY
      { n = "Ironbeak Hunter", lo = 50, hi = 51, z = "Felwood" },   -- ledger: ERA-ONLY
      { n = "Spiteflayer", lo = 52, hi = 52, z = "Blasted Lands" },   -- ledger: ERA-ONLY
    },
  },
  ["Dust Cloud"] = {
    [1] = {
      { n = "Galestrider", lo = 5, hi = 6, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Ornery Galestrider", lo = 8, hi = 9, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Fleeting Plainstrider", lo = 12, hi = 13, z = "The Barrens", f = true },   -- ledger: FOREVER-REPORTED
    },
  },
  ["Furious Howl"] = {
    [1] = {
      { n = "Worg", lo = 10, hi = 11, z = "Silverpine Forest", area = "Tirisfal entrance", f = true },   -- ledger: FOREVER-REPORTED
      { n = "Coldrasp", lo = 12, hi = 12, z = "Tirisfal Glades", area = "Whispering Forest", rare = true, f = true },   -- ledger: FOREVER-REPORTED
      { n = "Coyote Packleader", lo = 11, hi = 12, z = "Westfall" },   -- ledger: ERA-ONLY
      { n = "Mist Howler", lo = 22, hi = 22, z = "Ashenvale", rare = true },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Black Ravager Mastiff", lo = 25, hi = 26, z = "Duskwood" },   -- ledger: ERA-ONLY
      { n = "Ghostpaw Alpha", lo = 27, hi = 28, z = "Ashenvale" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Longtooth Runner", lo = 40, hi = 41, z = "Feralas" },   -- ledger: ERA-ONLY
      { n = "Snarler", lo = 42, hi = 42, z = "Feralas" },   -- ledger: ERA-ONLY
    },
    [4] = {
      { n = "Bloodaxe Worg", lo = 56, hi = 57, z = "Blackrock Spire", inst = "dungeon" },   -- ledger: ERA-ONLY
    },
  },
  ["Lightning Breath"] = {
    [2] = {
      { n = "Deviate Coiler", lo = 15, hi = 16, z = "Wailing Caverns", inst = "dungeon" },   -- ledger: ERA-ONLY
      { n = "Deviate Stinglash", lo = 16, hi = 17, z = "Wailing Caverns", inst = "dungeon" },   -- ledger: ERA-ONLY
      { n = "Thunderhawk Hatchling", lo = 18, hi = 20, z = "The Barrens" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Cloud Serpent", lo = 25, hi = 26, z = "Thousand Needles" },   -- ledger: ERA-ONLY
      { n = "Washte Pawne", lo = 25, hi = 25, z = "The Barrens", rare = true },   -- ledger: ERA-ONLY
    },
    [4] = {
      { n = "Noxious Reaver", lo = 37, hi = 38, z = "Dustwallow Marsh" },   -- ledger: ERA-ONLY
      { n = "Vale Screecher", lo = 41, hi = 43, z = "Feralas" },   -- ledger: ERA-ONLY
    },
    [5] = {
      { n = "Arash-ethis", lo = 49, hi = 49, z = "Feralas", rare = true },   -- ledger: ERA-ONLY
    },
    [6] = {
      { n = "Son of Hakkar", lo = 60, hi = 60, z = "Zul'Gurub", inst = "raid" },   -- ledger: ERA-ONLY
    },
  },
  ["Prowl"] = {
    [1] = {
      { n = "Mountain Lion", lo = 32, hi = 33, z = "Alterac Mountains" },   -- ledger: ERA-ONLY
      { n = "Ridge Stalker", lo = 36, hi = 37, z = "Badlands" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Ridge Stalker Patriarch", lo = 40, hi = 41, z = "Badlands" },   -- ledger: ERA-ONLY
      { n = "Elder Shadowmaw Panther", lo = 42, hi = 43, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Jaguero Stalker", lo = 50, hi = 50, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Frostsaber Stalker", lo = 59, hi = 60, z = "Winterspring" },   -- ledger: ERA-ONLY
    },
  },
  ["Savage Rend"] = {
    [1] = {
      { n = "Mystmane", lo = 13, hi = 13, z = "Zephras Isle", area = "Shadowgale Forest", rare = true, f = true },   -- ledger: FOREVER-REPORTED
      { n = "Shadowgale Shriekling", lo = 10, hi = 11, z = "Zephras Isle", f = true },   -- ledger: FOREVER-REPORTED
    },
  },
  ["Scorpid Poison"] = {
    [1] = {
      { n = "Venomtail Scorpid", lo = 9, hi = 10, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Corrupted Scorpid", lo = 10, hi = 11, z = "Durotar" },   -- ledger: ERA-ONLY
      { n = "Death Flayer", lo = 11, hi = 11, z = "Durotar" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Scorpashi Snapper", lo = 30, hi = 31, z = "Desolace" },   -- ledger: ERA-ONLY
      { n = "Scorpid Reaver", lo = 31, hi = 32, z = "Thousand Needles" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Scorpid Hunter", lo = 40, hi = 41, z = "Tanaris" },   -- ledger: ERA-ONLY
      { n = "Scorpid Tail Lasher", lo = 43, hi = 44, z = "Tanaris" },   -- ledger: ERA-ONLY
    },
    [4] = {
      { n = "Firetail Scorpid", lo = 56, hi = 57, z = "Burning Steppes" },   -- ledger: ERA-ONLY
      { n = "Krellack", lo = 56, hi = 56, z = "Silithus" },   -- ledger: ERA-ONLY
      { n = "Stonelash Pincer", lo = 56, hi = 57, z = "Silithus" },   -- ledger: ERA-ONLY
    },
  },
  ["Shell Shield"] = {
    [1] = {
      { n = "Snapjaw", lo = 30, hi = 31, z = "Alterac Mountains / Hillsbrad Foothills" },   -- ledger: ERA-ONLY
      { n = "Cranky Benj", lo = 32, hi = 32, z = "Alterac Mountains", rare = true },   -- ledger: ERA-ONLY
      { n = "Kresh", lo = 20, hi = 20, z = "Wailing Caverns", inst = "dungeon", elite = true },   -- ledger: ERA-ONLY
      { n = "Aku'mai Fisher", lo = 23, hi = 24, z = "Blackfathom Deeps", inst = "dungeon" },   -- ledger: ERA-ONLY
    },
  },
  ["Swipe"] = {
    [1] = {
      { n = "Giant Grizzled Bear", lo = 12, hi = 13, z = "Silverpine Forest", f = true },   -- ledger: FOREVER-REPORTED
    },
  },
  ["Thunderstomp"] = {
    [1] = {
      { n = "Mistvale Gorilla", lo = 32, hi = 33, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Jungle Thunderer", lo = 37, hi = 38, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
    },
    [2] = {
      { n = "Elder Mistvale Gorilla", lo = 40, hi = 41, z = "Stranglethorn Vale" },   -- ledger: ERA-ONLY
      { n = "Groddoc Thunderer", lo = 49, hi = 50, z = "Feralas" },   -- ledger: ERA-ONLY
    },
    [3] = {
      { n = "Un'Goro Thunderer", lo = 52, hi = 53, z = "Un'Goro Crater" },   -- ledger: ERA-ONLY
      { n = "U'cha", lo = 55, hi = 55, z = "Un'Goro Crater", rare = true, elite = true },   -- ledger: ERA-ONLY
    },
  },
  ["Web"] = {
    [1] = {
      { n = "Moss Stalker", lo = 12, hi = 13, z = "Silverpine Forest", f = true },   -- ledger: FOREVER-REPORTED
    },
  },
}
-- Classic Era's name for an ability the list above files under its WoW Forever name
D.ERA_ALIAS = { ["Screech"] = "Demoralizing Screech" }
