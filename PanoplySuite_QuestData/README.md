# Panoply Suite Quest Data

Quest, NPC, object, item, profession and gathering data for the **Panoply Suite** leveling guide,
for WoW Classic Era (1.15.x) and WoW Forever. Panoply Suite reads it through its own adapter; this
add-on has no code of its own beyond a small decoder (`Core.lua`) and the Forever overlay
(`Forever.lua`). It does nothing on its own.

Install: copy the `PanoplySuite_QuestData` folder into `Interface/AddOns/` next to `PanoplySuite`
and tick **Panoply Suite Quest Data** in the AddOns list.

## Licence
GNU General Public License, version 3 only (GPL-3.0-only, see `LICENSE`), like the rest of Panoply Suite.
The data is derived from the VMaNGOS world database, which is licensed under the GPL version 2 "or (at your
option) any later version"; Panoply Suite uses it under version 3. See `NOTICE.md` for attribution and exact sources.

## What is inside
| File | Content |
| --- | --- |
| `Core.lua` | decoder, getters (`PanoplySuiteQuestData.Quest/Npc/Object/Item`), id lists, reprojection |
| `Data/Zones.lua` | zone → uiMapID table, per-uiMap world rectangles (Era and Forever), instance areas, hidden quests |
| `Data/Quests.lua` | 4433 quests (201 hidden: disabled, event-only or placeholder): levels, min/max level, race/class masks, pre-quests, chains, exclusive groups, starters/finishers, objectives (creatures, kill credit, items, objects), zone, quest type (elite/dungeon/raid), suggested players, XP |
| `Data/Npcs.lua` | 5987 NPCs: name, levels, rank, faction side, NPC flags, spawns in map percent per uiMap |
| `Data/Objects.lua` | 825 objects: name, type, spawns |
| `Data/Items.lua` | 2637 items: NPC drops, object drops, vendors |
| `Data/Locations.lua` | location facts for 56 NPCs and 1 object: inside / near a named inn or building, floor (upstairs / downstairs); Panoply Suite writes the note text |
| `Forever.lua` | WoW Forever overlay (Forever/Camelot TOC and fallback TOC only) |
| `Professions/*.lua` | recipes, trainers, vendors, nodes, disenchanting (Classic 1.12 values) |
| `Gathering/Nodes.lua` | herb, ore, chest and fishing-pool spawn points (Classic Era) |

Only quests, NPCs, objects and items that the route can use are included (quest givers, finishers,
objective targets, item sources, trainers, vendors, flight masters, innkeepers).

## Encoding and loading
Each record is one plain `|`-separated text line (spawn coordinates are 3 hex digits per axis,
0..4095 = 0..100 %). Nothing is compressed or obfuscated; every file is readable Lua. Records are
decoded the first time they are read and held in weak caches, so the game can drop records nobody
uses. About 5 MB of Lua memory after loading; the full Panoply Suite route plan with its own caches
uses about 19 MB together with the main add-on (measured with Lua 5.1 `collectgarbage("count")`).

## WoW Forever
Forever runs the classic world, but its client re-drew four zone maps (Stormwind City, Redridge
Mountains, Mulgore, Eastern Plaguelands), added the Skyborne races (race bits 32 and 33) and new
zones. `Data/Zones.lua` carries both rectangle sets; spawns in re-drawn zones are re-projected
and flagged **unverified**. `Forever.lua` holds verified corrections (empty until checked in game)
and Panoply Suite learns NPC positions when you talk to an NPC, and the giver of quests this database
does not know. Forever-only quests, Skyborne starting areas and NPCs in the new zones are **not**
in this database.

## Location facts
`tools/build_locnotes.py` records a fact only when the server data supports it and every spawn of
the NPC agrees: inside an inn (the inn's rest area from `areatrigger_tavern` / `areatrigger_template`,
a box, or a sphere confirmed by standing next to the innkeeper), upstairs / downstairs (height
against the innkeeper's), or near a named building (the guards' points of interest, kept only when
one is clearly the closest). Holiday decorations named "Interior" / "Exterior" were checked and
rejected (the "Exterior" ones also stand inside throne rooms). Known gaps: the server data has no
per-spawn sub-area, no building models and no doors, so most NPCs get no fact, there are no
generated entrances (Panoply Suite learns them in game or takes them from its curated table) and
rooms ("throne room") only come from the curated table. On Forever, facts in the four re-drawn
zones are hidden until checked there.

## Rebuilding
`tools/fetch_sources.sh` downloads the sources; `tools/build_questdata.py`,
`tools/build_profdata.py`, `tools/build_gatherdata.py` and `tools/build_locnotes.py` regenerate the files (Python 3, sqlite3).
