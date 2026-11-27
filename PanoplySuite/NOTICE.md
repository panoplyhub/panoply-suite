# Panoply Suite - third-party notices

## Fonts (Media/Fonts/)
Panoply Suite bundles these fonts. Each is licensed under the SIL Open Font License, Version 1.1;
the full licence text ships next to the font files. The Lato files are unmodified. Spectral SC
SemiBold is a modified version (as OFL 1.1 allows; Spectral has no Reserved Font Name): its
character map points each letter straight at the font's own small-cap glyph, because the game does
not apply the OpenType feature that normally does this. No glyph was changed or added
(`tools/make_skin3.py`, bake_small_caps). The modified font stays under the SIL OFL 1.1.

| File | Font | Copyright | Licence |
| --- | --- | --- | --- |
| SpectralSC-SemiBold.ttf | Spectral SC SemiBold | Copyright 2017 The Spectral Project Authors (https://github.com/productiontype/Spectral) | SIL OFL 1.1, `Media/Fonts/SpectralSC-OFL.txt` |
| Lato-Medium.ttf, Lato-SemiBold.ttf, Lato-Bold.ttf | Lato Medium / SemiBold / Bold | Copyright (c) 2010-2014 by tyPoland Lukasz Dziedzic (team@latofonts.com), Reserved Font Name "Lato" | SIL OFL 1.1, `Media/Fonts/Lato-OFL.txt` |

The fonts are used only for drawing Panoply Suite's own interface text. They are not sold on their own.

## Artwork (Media/)
The panels, brass trim and corner caps (Media/V3), the J line icons (Media/Icons/J), the map pins
(Media/Pins), the crest and minimap button (Media/Crest.tga, Media/MinimapIcon.tga) are our own
Panoply Suite v3 artwork (hearthpath-brand final-v3), converted to TGA by `tools/make_skin3.py`.
Everything else in Media/ was drawn for Panoply Suite. Item, ability, quest and bag pictures are always
the game's own built-in textures, read from the client at runtime; none are shipped.

## Spec & Trainer data (0.7.0, Modules/SpecTrainer/)
- `Data/TalentData.lua` (talent trees: talent names, positions, ranks, requirements, icons) is generated
  by Panoply Suite's own `tools/build_spectrainer_data.py` from World of Warcraft client tables (Talent,
  TalentTab, SpellName, Spell, SpellMisc), CSV exports from https://wago.tools for Classic Era
  1.15.9.70576 and WoW Forever 1.60.1.70707. World of Warcraft (c) Blizzard Entertainment.
- `Specs.lua` (the ready-made specs and their reasons) is Panoply Suite's own write-up. No talent build,
  wording or data from any other add-on or website was used.
- Class trainer costs and levels come from the VMaNGOS world database and ship in the data add-on
  PanoplySuite_QuestData (`Trainers/Classes.lua`, see its NOTICE.md), not here.

## Licence (0.8.0; whole suite since Nov 12 2026)
The whole of Panoply Suite is distributed under the GNU General Public License version 3 only (GPL-3.0-only): this
folder, the data add-ons `PanoplySuite_QuestData` and `PanoplySuite_RouteData`, the `PanoplySuite_Plans` add-on and
the `Hearthpath` stand-in. Each folder carries the licence in its own `LICENSE`. Panoply Suite's own code, text and
artwork are Copyright (C) 2026 Ostrowski Holdings LLC. The fonts keep the SIL Open Font License 1.1 (above).
The whole suite has to be version 3 because the leveling guides (below) are Polestar's GPL-3.0-only text.
- **VMaNGOS** (the data add-ons are derived from its world database): (c) the VMaNGOS contributors,
  https://github.com/vmangos/core. Its source files say it is licensed under the GNU GPL "either version 2 of the
  License, or (at your option) any later version", and its repository's LICENSE is the GPL version 2 text, which
  says no "only". Panoply Suite takes the "later version" option and uses that data under version 3. Checked
  2026-11-12 against the repository (`LICENSE`, `src/game/Objects/Player.cpp`, `src/mangosd/Main.cpp`); the world
  database files themselves carry no notice of their own. Until Nov 12 2026 the data add-ons were labelled
  GPL-2.0-only; that "only" was our own wording, not VMaNGOS's.

## The guide engine: Polestar, bundled as a modified version (WoW Forever only; Nov 2026)
On WoW Forever the leveling guide, the walking routes, the arrow's target and the travel plan come from **Polestar** by
Fitz and the Polestar authors (https://github.com/fitzforge/polestar, GPL-3.0), which ships inside the Panoply Suite
package as a modified version. Thank you, Fitz. In the game and in Panoply Suite's folders it carries Panoply's names,
not Polestar's (see "Renamed" below); this file, the licence files and `GuideEngine/PANOPLY-CHANGES.md` are where its
authors are credited.
- **What:** Polestar release **v0.4.2.1**, revision `4e1cd841c94d41348635d7c67a7280c8ad9960c5` (https://github.com/fitzforge/polestar/releases/tag/v0.4.2.1),
  Copyright (c) 2026 The Polestar authors. Every folder of that release's `addon/` directory except the ones listed
  below, 803 files in 28 folders. In Polestar's release they are called `Polestar`, `Polestar_Options` (the settings),
  `Polestar_Nav`, `Polestar_Nav_EK`, `Polestar_Nav_Kalimdor` (the walking-map regions are files inside these three
  folders), `Polestar_Guides`, `Polestar_Guides_Alliance`, `Polestar_Guides_Horde`, the nine race guide folders
  (`Polestar_Guides_Human` ... `Polestar_Guides_Troll`, each with `Legs.lua`), the nine language folders
  (`Polestar_deDE` ... `Polestar_zhTW`), `Polestar_ItemDB` and `Polestar_Recorder`.
- **Left out (0.9.9):** `Polestar_Arcade`, `Polestar_Experimental`, `Polestar_Looks`, `Polestar_SkinAPI` and the ten
  `Polestar_Skin_*` folders of that release are not part of Panoply Suite. Polestar's own code looks for them when it needs
  them and runs without them; no file of Polestar's code was edited to leave them out.
- **Where (0.9.5):** the game's AddOns list showed Polestar's folders (27 then) as one row each, so they ship inside Panoply
  Suite's own folders, each folder whole: `PanoplySuite/GuideEngine/<folder>/` for all but the languages,
  `PanoplySuite_Languages/<folder>/` (a load-on-demand add-on) for the nine language folders.
- **Renamed (0.9.9.5, 25 November 2026):** in this copy every name of Polestar's own is replaced by a name of Panoply
  Suite's: `Polestar` becomes `PanoplyGuide` (and `polestar`, `POLESTAR` likewise) in every folder name, file name, TOC
  field, saved-data name, global name, frame name, slash command, key-binding name, hidden-message prefix and text of the
  `.lua`, `.toc`, `.xml` and `.json` files, and three web addresses of Polestar's project are replaced by Panoply Suite's.
  So the folders above are `PanoplyGuide`, `PanoplyGuide_Options`, `PanoplyGuide_Nav` ... `PanoplyGuide_zhTW` here. This
  was done so that this copy shares no folder, saved-data name or global with the Polestar add-on (both can be installed;
  neither overwrites the other) and so that the game shows no name but the add-on's own. Copyright comment lines and
  every licence, credit and data-source file are left exactly as Polestar's authors wrote them.
  `GuideEngine/PANOPLY-CHANGES.md` has the full table and is the notice of modification that section 5(a) of the GPL-3.0
  asks for. There is no folder called `Polestar` in Panoply Suite any more (0.9.5 to 0.9.9.4 shipped a small saved-data
  stand-in under that name).
- **Packaging, and the files `GuideEngine/PANOPLY-CHANGES.md` lists:** apart from the renames, those listed changes and
  two fixed, mechanical packaging rules, no file's content is changed, and no file of an included folder is added or left
  out. Every Lua file a Polestar TOC loads gets one wrapper on its first and
  last line (`PanoplySuiteBundle.File("<folder>", "<path>", function(...)` ... `end)`) so it runs under its own folder's
  name, at the moment the game would have run it (`Core/Bundle.lua`, Panoply Suite's own loader); and in those files the
  folder name in a picture, font or sound path (`"Interface\\AddOns\\" .. NAME .. ...`) is looked up through
  `PanoplySuiteBundle.Dir(NAME)`, because the folder moved. Pictures, sounds, fonts, licences and credits are byte for
  byte Polestar's. The XML files only list Lua files; Panoply Suite's WoW Forever TOCs
  list the same files in the same order. In Panoply Suite's source, `tools/polestar_engine_manifest.json` lists the sha256
  of every file of Polestar's release, and `python3 tools/update_polestar_engine.py --check` (run by the test suite and by
  the release build) undoes the renames and the two rules and compares every file with it, and with the download when
  there is one. Polestar's key bindings file (`Bindings.xml`, which the game reads only from an add-on's top folder) is
  shipped but not active.
- **Licences, as Polestar's own files state them** (folders by their names in Polestar's release):
  - `Polestar`, the guide folders, the language folders, `Polestar_ItemDB`, `Polestar_Recorder`: **GPL-3.0-only**
    (each TOC's `X-License`). Polestar's main folder carries no licence file of its own, so Polestar's `LICENSE`
    (the GNU GPL version 3), `LICENSE-EXCEPTION.md` and `THIRD_PARTY.md` are copied, unchanged, into
    `Licenses/GuideEngine/` of this folder.
  - `Polestar_Nav`, `Polestar_Nav_EK`, `Polestar_Nav_Kalimdor`: **GPL-3.0-or-later** (`GuideEngine/PanoplyGuide_Nav/LICENSE`,
    `GuideEngine/PanoplyGuide_Nav/CREDITS.md`). The walking router: "Polestar's walking router started from Shortest Path Forever
    v1.16.0 by Cillian Berragan, with thanks; Polestar maintains it since 2026-10-16" (that CREDITS.md);
    Shortest Path Forever, https://github.com/cjber/shortest-path-forever, GPL-3.0-or-later, Copyright (C) 2026
    Cillian Berragan. His copyright notices stay, unchanged, in the files that carry them (the router's `Routing/` folder,
    and the files of the main folder that CREDITS.md lists as adapted from his work).
  - **Leffe's navigation maps:** the walking maps in the three Nav folders
    (maps format 5) are, in Polestar's words, "Leffe's navigation maps, condensed for the game ... with his permission",
    and the walks baked into the race guide folders (`Legs.lua`) were drawn on Leffe's navigation maps and are
    published by Polestar "with his permission and the credit 'Leffe's navigation maps'" (Polestar's THIRD_PARTY.md).
    Credit: **Leffe's navigation maps**. Leffe's permission was given to Polestar's author; Panoply Suite ships these
    files only as part of Polestar's release (repackaged and renamed as above), under the licence Polestar
    publishes them under.
  - Data notices (`LICENSE-DATA.txt` in the guide, language and item folders and in the main folder's `Gear/`, `CREDITS.md`
    in the language folders) and the font licences in the main folder's `Media/Fonts/` ship where Polestar put them,
    inside the folders above, unchanged.
- **How Panoply Suite uses it:** `Core/Bundle.lua` (Panoply Suite's own code, GPL-3.0-only) runs the engine's files: each
  folder under a name and private table of its own, at the moments the game used (the main folder as Panoply Suite
  loads, its guides and Recorder right after it starts, the load-on-demand folders when the engine asks for them), and it
  answers the engine's own questions about its add-on folders from their TOCs. `Engine/PanoplyGuideEngine.lua` (Panoply
  Suite's own code) calls the engine's functions; neither copies any of Polestar's code. It keeps the engine's own windows,
  arrow and buttons hidden through the engine's own switch and draws its step, arrow target and route in Panoply
  Suite's windows. It sets four of the engine's settings (its minimap button, its game menu button, automatic quest
  accept and hand-in) and keeps what each was. The engine's saved data is saved with Panoply Suite's, under the names
  `PanoplyGuideDB`, `PanoplyGuideCharDB`, `PanoplyGuideRecorderDB` and `PanoplyGuideRecorderCharDB` (0.9.5 to 0.9.9.4
  saved the same tables there as `PolestarDB`, `PolestarCharDB`, `PolestarRecorderDB` and `PolestarRecorderCharDB`;
  `Core/Bundle.lua` moves each to its new name once, the first time a character logs in after the update).
- **With the Polestar add-on installed too:** since 0.9.9.5 the two share no folder, saved-data name, global or
  hidden-message prefix, so both load and run side by side and neither touches the other's files or saved data.
  Panoply Suite's installers never change a Polestar folder that is not Panoply Suite's own old stand-in.
- **Classic Era:** the engine does not load there.
- **To update (Panoply Suite's source):** `docs/polestar-update.md`; the tools apply the renames by themselves and
  refuse a build in which Polestar's name would reach a shipped folder, file, TOC field, saved-data name or text.

## Leveling guides converted from Polestar's guide text (0.8.0, Data/Guides/; Classic Era, and WoW Forever without Polestar)
- **Source:** Polestar, https://github.com/fitzforge/polestar, Copyright (c) 2026 The Polestar authors, licensed under
  the GNU General Public License version 3 (Polestar's `package.json`: `GPL-3.0-only`). Only Polestar's own WoW Forever
  leveling guide text was used: `guides/forever/alliance/**.guide` and `guides/forever/horde/**.guide` and the both-faction guides directly in `guides/forever/40-50` and `50-60` (each written once per faction), 71 guides (every
  race's start, then the shared Alliance and Horde guides; what each race's guides cover is listed guide by guide in
  `docs/launch/GUIDE-COVERAGE.md` of the Panoply Suite repository), Polestar release **v0.4.2.1**, revision
  `4e1cd841c94d41348635d7c67a7280c8ad9960c5`. The exact release and revision are also written in the header of
  every generated file and in `Data/Guides/Index.lua` (`source.release`, `source.revision`).
- **Not used in the converted guides:** Polestar's add-on code, compiled guide packs, UI, arrow, navigation, engine,
  frames, art, data folders and tools (those ship unedited in Polestar's own folders, section above, and are not part of
  this conversion). Polestar's `LICENSE-EXCEPTION.md`
  (the additional permission for guide packs made by its compiler) does not cover guide text copied from Polestar's own
  guides, and is not relied on: the guide text is used under the GPL-3.0 itself, which is Panoply Suite's licence too.
- **Changes made (a modified version, GPL section 5):** the `.guide` text was parsed by Panoply Suite's own converter,
  `tools/convert_polestar_guides.py`, into Lua tables: zone names given map ids from Panoply Suite's own client table
  (`tools/cache/forever_UiMap.csv`), coordinates written as 0-1 fractions, race names written as the client's race file
  names. Steps, goals, quest/NPC/object/item ids, coordinates, `only` and `when` conditions, tips and notes are kept.
  Panoply Suite's own step engine (`Engine/Guides.lua`) follows them; where it cannot act on a construct, the data still
  carries it and `docs/guides/POLESTAR-CONVERSION-REPORT.txt` counts it.
- **To convert again** (e.g. a newer Polestar revision): clone Polestar outside the add-on folders, then
  `python3 tools/convert_polestar_guides.py --src <checkout> --report docs/guides/POLESTAR-CONVERSION-REPORT.txt`.
  The converter refuses a checkout whose LICENSE is no longer the GPL version 3. Polestar's add-on folders are copied into
  `addon/` only by `tools/update_polestar_engine.py` (section above), never by hand.
- **Facts Polestar's guides rest on:** Polestar's own THIRD_PARTY.md (Licenses/Polestar/) names the sources of its quest,
  NPC, object and item facts. Panoply Suite's converter copies none of those data files:
  the converted guides carry only what is written in the guide text (ids, coordinates, quoted names, tips and notes).
  In the game, quest, NPC and item names and quest-giver / objective positions are looked up in Panoply Suite's own
  quest data first; a name or coordinate written in the guide text is used where the guide gives one or our data has none.

## WoW Forever talent trees (0.9.9.4 hotfix, Modules/SpecTrainer/Data/ForeverTalentData.lua and the game itself)
- **In the game, the player's own class:** the talents, ranks and names are read from the game's own talent tree (Blizzard's trait API)
  and laid on the tree below: a talent it has keeps that tree's row, column, gates and arrows; a talent new to the game is placed on
  the same grid by the same fixed rules.
- **Other classes, and before the game's tree can be read:** the nine classes' trees (talents, ranks, spells, icons, rows and columns,
  arrows, gates) from World of Warcraft's own client tables of WoW Forever build 1.60.1.71037 (TraitTree, TraitNode,
  TraitNodeXTraitNodeEntry, TraitNodeEntry, TraitDefinition, TraitEdge, TraitCond, TraitNodeGroup, TraitNodeGroupXTraitNode,
  TraitNodeGroupXTraitCond, SkillLineXTraitTree, SpellName, SpellMisc), CSV exports from https://wago.tools, kept in
  `tools/cache/forever-traits-71037/`. World of Warcraft (c) Blizzard Entertainment. Panoply Suite's own tool
  `tools/build_forever_talents.py` turns them into `ForeverTalentData.lua`; the few positions the tables give off the grid are settled by
  fixed rules that the file's header lists. Nothing of Polestar's is used for the trees any more (Nov 22 2026: "i really only wanted
  their levleling guide").

## WoW Forever suggested talent builds (0.9.9.4 hotfix, Modules/SpecTrainer/Data/ForeverBuilds.lua)
- **Source:** TimeSaver's free WoW Forever talent calculator, `https://timesaver.gg/tools/wow-forever/talent-calculator/<class>/<spec>`,
  read on 22 November 2026 (docs/research/forever-meta-builds.md says how). TimeSaver relays each build from the guide it names, and each
  build is shown in the add-on as "TimeSaver (from <guide>)" with its page's address: **Maxroll**, **Wowhead**,
  **Method** and **Icy Veins**. Thank you to all of them. we lifted the clean-room rule for
  public site data (Nov 22 2026). No other add-on's code was read for the builds.
- **What is used:** the order of points (levels 10 to 60) or, where the site gives only that, the level-60 layout; the talent names the
  site gives; the build's name, the guide it is credited to and the page's address. Built by `tools/build_forever_builds.py`. Each point
  is a talent name and rank; its spell id is Blizzard's (the talent of that name in the class's tree in the client tables of build
  1.60.1.71037 above). The add-on offers only the builds that fit Blizzard's talent rules on the tree it uses, one a spec ("One per
  spec, extra only if different"), and each card keeps its guide's credit.
- **What Polestar's data was used for, and what is left of it:** while the builds were being read (22 November 2026) the research wrote
  each talent name as the node id of the talent with exactly that name in the pre-launch talent tree data Panoply Suite then took from
  Polestar, and replayed the ordered builds through Polestar's own talent rules as a check
  (docs/research/forever-meta-builds.md). That check's results are not used. docs/research/forever-meta-builds-names.json turns those
  research ids back into the names they were matched from (names only). No spell id, rank, position, gate or rule of Polestar's is in
  the shipped builds or used to make them (0.9.9.4 review, 23 November 2026).

## Hunter pet facts (0.8.4, Modules/HunterPet/)
- Abilities, ranks, pet levels, spell ids and which family can use what come from World of Warcraft
  client tables (SkillLineAbility, SpellName, Spell, SpellLevels), CSV exports from
  https://wago.tools. World of Warcraft (c) Blizzard Entertainment.
- Training-point costs, family diets and the wild beasts reported to know a rank come from Panoply
  Suite's research ledger (9 Nov 2026). That ledger drew on ForeverChanges
  (https://foreverchanges.pro/hunter-pets), official Blizzard forums, Mmonster, WoWFDB and 60.tools,
  and on player teacher reports from community forums collected by ForeverChanges. No coordinates are
  stored in this data.

## Game facts
All game facts belong to Blizzard Entertainment. We credit every outside source we used. This tree
contains no code, guide text or data from any other add-on or website beyond the sources credited
here. The Polestar leveling guides
(above) are the exception already described: that guide text is used under the GNU GPL version 3.
