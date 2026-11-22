# NOTICE - Panoply Suite Quest Data

This add-on is distributed under the GNU General Public License version 3 only (GPL-3.0-only, `LICENSE`), like the
rest of Panoply Suite. Until Nov 12 2026 it was labelled GPL-2.0-only; that "only" was our own wording (see source 1).

## Data sources
1. **VMaNGOS world database** - (c) the VMaNGOS contributors, https://github.com/vmangos/core,
   licensed under the GNU GPL "either version 2 of the License, or (at your option) any later version" (the notice
   at the top of its source files, e.g. `src/game/Objects/Player.cpp`; its repository LICENSE is the GPL version 2
   text and says no "only"; checked 2026-11-12). Panoply Suite takes the "later version" option and uses the data
   under the GNU GPL version 3. Official sqlite snapshot from the `db_latest` release, asset
   `db-sqlite-4641790.zip` (downloaded 2026-09-28). Content patch 1.12 (VMaNGOS patch index 10,
   client build 5875). Tables read: quest_template, creature_template, creature,
   creature_questrelation, creature_involvedrelation, gameobject_template, gameobject,
   gameobject_questrelation, gameobject_involvedrelation, areatrigger_involvedrelation, item_template,
   item_required_target, creature_loot_template, gameobject_loot_template, reference_loot_template,
   disenchant_loot_template, npc_vendor, npc_vendor_template, npc_trainer, npc_trainer_template,
   spell_template, spell_script_target, skill_line_ability, skill_fishing_base_level,
   creature_ai_events, creature_ai_scripts, game_event, game_event_quest, game_event_creature,
   game_event_gameobject, faction, faction_template, area_template, map_template,
   areatrigger_template, areatrigger_teleport, areatrigger_tavern, points_of_interest, gossip_menu_option, gossip_scripts.
   All files under `Data/`, `Professions/`, `Gathering/`, `Trainers/`, `Maps/`, `Loot/` and `Gear/` are derived from it and are distributed under
   the GPL-3.0 (see above).
   `Trainers/Classes.lua` (0.7.0, Spec & Trainer) holds class trainer spells with their required
   level and cost from npc_trainer / npc_trainer_template and spell_template; its icon ids come from
   the client's SpellMisc table (item 2).
   `Maps/Instances.lua` (0.8, the map feature in Panoply Suite's Modules/Map) holds, for every Classic dungeon
   and raid, its door positions and level requirement (areatrigger_teleport, areatrigger_template), group
   size (own table, checked against map_template), the creature and object spawn positions blocked into the
   floor-plan cells (creature, gameobject, creature_template levels), the boss positions (the boss names
   and their order are Panoply Suite's own list, looked up in creature_template), the spirit healer spots
   (creature, entry 6491) and the zone lists and level bands used by the jump menu. A boss the server
   summons by script has no spawn row and is listed without a marker. The client has no dungeon map art, so
   the plan is Panoply Suite's own sketch of these positions.
   `Loot/Loot.lua` (0.8.4, the At your level page in Panoply Suite's Modules/AtLevel) holds, in Panoply Suite's own
   record format: the gear each boss of that atlas drops (creature_template loot ids, creature_loot_template,
   reference_loot_template; green quality or better, at least 1%, at most ten droppers), the gear quests give
   (quest_template reward columns; no holiday, world-event or Darkmoon Faire quests), the quests open to one
   class only (quest_template RequiredClasses), and for each of those items its name, quality, slot, kind,
   required level, item level, class restriction, base stats, armour and weapon damage (item_template). A boss
   with no gear of its own in the data is listed as a gap. The dungeons only the WoW Forever client has are
   listed by the name in the client's Map table (item 2) with no loot: none is known in these sources.
   `Loot/Bosses.lua` (0.9.6, the dungeon and raid map window in Panoply Suite's Modules/Map: the boss tooltip and the
   treasure room) holds, for every boss of that atlas, in Panoply Suite's own record format: its creature entry and display id
   (creature_template, creature: the game shows its own model of the boss from that id) and what the boss itself drops, with the
   drop chance (creature_loot_template, reference_loot_template; items of green quality or better, quest items, and white items
   only the boss drops, at least 0.5%, dropped by at most ten creatures that are not bosses; a negative chance in the data is
   written as a quest-only drop), and for each of those items its name, quality, slot, kind and required level (item_template).
   Since 0.9.6 phase G the shared loot tables are followed to any depth with each pull counted, the data's conditions are read
   (conditions: a team condition gives a drop to one side only; event-only and Argent Dawn commission drops are left out; a
   "quest taken" drop is a quest-only drop; a patch condition follows patch 1.12), and the chest a boss leaves adds its loot,
   marked as the chest's (gameobject_template, gameobject, gameobject_loot_template: Majordomo Executus's Cache of the Firelord,
   King Gordok's Gordok Tribute). Since 0.9.6 phase J a boss with no drop of its own in the data (Oggleflint, Bazzalan,
   Hamhock) lists its random (world) drops instead, from the same tables by the same walk (same chances, sides and conditions):
   green quality or better only, no trade goods, junk or quest items, the most likely first, at most twelve, each with its real
   per-kill chance, and marked as a random drop. A boss that has drops of its own gets no random drops.
   Since phase J2 such a boss also carries one summary of its random gear (weapons and armor of green quality or better, by the
   same filter), computed from the same tables by the same walk: the chance per kill of at least one such piece, and how many
   different pieces its tables can give, and (since phase J3) the best quality among those pieces.
   No loot add-on's data or layout was used.
   `Gear/Gear.lua` (0.8.4, the Class Gear topic and Upgrade Hints in Panoply Suite's Modules/ClassGear) holds
   the wearable items the listed bosses drop (creature_template, creature_loot_template,
   reference_loot_template; a drop chance of 1% or more) and the quests give (quest_template), with the
   numbers the game prints on them (item_template; "Equip:" bonuses read from spell_template), plus the
   "Equip:" bonuses of other wearable items. It holds no item scores; the weights are Panoply Suite's own.
   `Maps/Extras.lua` (0.8.4, the map extras in Panoply Suite's Modules/Map) holds the open-world spawn positions of
   the rare creatures (creature_template rank 2 and 4, creature), of the cooking fires, anvils and forges
   (gameobject_template type 8 with spell focus 4, 1 and 3, gameobject), of the mailboxes (gameobject_template
   type 19) and of the guild masters (creature_template subname), with the side that can use a mailbox or a guild
   master (faction_template). Cooking fires within 45 yards of one already listed are the same camp and are listed
   once, at that first fire's own position. It also holds the named areas of every zone map (item 2).
   `Maps/Landmarks.lua` (0.9.6, the Go to window in Panoply Suite's Modules/Map) holds the named places a city guard
   marks for you (points_of_interest), each with the continent and side of the guards that offer it
   (gossip_menu_option, creature_template gossip_menu_id, creature, faction_template), and the inns by their own
   names at their rest areas (areatrigger_tavern, areatrigger_template; the side is the nearest innkeeper's). A
   guard's spot that is a person is left out (that NPC has its own spawn); a spot with an innkeeper within 15 yards
   is an inn. It also holds the towns the game's own world map labels (item 2: AreaPOI) and, for WoW Forever, the
   client's new named spots.
2. **World of Warcraft client tables** (UiMap, UiMapAssignment, ChrRaces, Lock, SpellMisc; AreaTable, UiMapXMapArt
   and WorldMapOverlay for the named areas of each zone map in `Maps/Extras.lua`: where the game lays an area's
   art once it is explored, and the area's name; AreaPOI for the town labels of the world map and WoW Forever's
   new named spots in `Maps/Landmarks.lua`; Map is fetched for cross-checks), as
   CSV exports from https://wago.tools for Classic Era build 1.15.9.70576 and WoW Forever build
   1.60.1.70707. Used only for map rectangles, area→map links, race bits and lock skill types (facts
   about the game client needed to place server coordinates on the in-game maps).
   World of Warcraft (c) Blizzard Entertainment.

The converter scripts (`tools/vmangos_world.py`, `tools/build_questdata.py`,
`tools/build_profdata.py`, `tools/build_gatherdata.py`, `tools/build_locnotes.py`,
`tools/build_spectrainer_data.py`, `tools/build_mapdata.py`, `tools/build_lootdata.py`, `tools/build_geardata.py`, `tools/build_mapextras.py`, `tools/build_landmarks.py`, `tools/build_bossloot.py` in the Panoply Suite
source) are our own work. `Data/Locations.lua` stores facts only (kind, building name as named in
the server data, floor); the note wording is composed by Panoply Suite at runtime.

**CMaNGOS was not used.** VMaNGOS models each 1.x content patch separately and its 1.12 rows match
Classic Era 1.15; CMaNGOS-Classic (also GPL) would be a valid alternative source, but mixing the two
would only add conflicts.

All game facts (quest names, NPC names, coordinates, item stats, and the like) belong to
Blizzard Entertainment. The sources above are the only ones. No code or written guide text from
any other add-on or website beyond the sources credited here was copied; where an
outside source was used, only game facts were taken and stored in Panoply Suite's own format.

## Changes
The VMaNGOS data was filtered (only content usable by a leveling route), converted from world
coordinates to per-map percent, and re-encoded into compact text records. `Forever.lua` is
hand-written. Generated 2026-10-31.
