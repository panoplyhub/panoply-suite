# Panoply Suite

Panoply Suite is a leveling route, arrow, professions, bags, merchant, gathering and waypoints
add-on for World of Warcraft. It is free and open source (GNU General Public License, version 3
only — see `LICENSE`). It is free now and free forever.

It is for **WoW Forever** now. Classic support is coming later.

## Install

The release zip (`PanoplySuite-0.9.9.6.zip`) holds six folders, and all six go into the game's AddOns
folder: `PanoplySuite` (the add-on), `PanoplySuite_QuestData`, `PanoplySuite_RouteData`,
`PanoplySuite_Plans`, `PanoplySuite_Languages` (the guide's texts in nine more languages) and
`Hearthpath` (a small stand-in with no code that keeps settings saved under the add-on's old name
loading).

**Windows**

1. Quit World of Warcraft.
2. Right-click the zip, choose "Extract All...", then "Extract".
3. Open `World of Warcraft\_forever_\Interface\AddOns` (create `Interface` and `AddOns` if they are
   missing).
4. If you are updating, delete the old copies of the six folders there first.
5. Copy the six folders from the download into `AddOns`.
6. Start WoW Forever, open AddOns on the character screen, and make sure Panoply Suite is ticked.
   In the game, type `/panoply`.

**Mac**

1. Quit World of Warcraft.
2. Double-click the zip.
3. In Finder open `/Applications/World of Warcraft/_forever_/Interface/AddOns` (create `Interface`
   and `AddOns` if they are missing).
4. If you are updating, move the old copies of the six folders there to the Trash first.
5. Drag the six folders from the download into `AddOns`.
6. Start WoW Forever, open AddOns on the character screen, and make sure Panoply Suite is ticked.
   In the game, type `/panoply`.

Your settings and progress are kept (they live in the game's `WTF` folder, which you do not touch).

Updating from an earlier version: versions 0.9.5 to 0.9.9.4 also put one more small stand-in folder
into AddOns, besides `Hearthpath` (always keep `Hearthpath`). Panoply Suite no longer uses or ships it.
You can tell it by two things: its .toc file has the line `## X-Panoply-StandIn: 1`, and it has no
`Core`, `UI` or `Engine` folder inside. You may delete that folder. **Leave every other folder alone,
including any add-on you installed yourself.**

## Credits

The guide engine, its guides, travel planner, walking router and walking maps are **Polestar** by
Fitz and the Polestar authors (GNU GPL version 3, https://github.com/fitzforge/polestar), carried
inside Panoply Suite as a modified version under Panoply's own names. Thank you. Every credit and
licence is in `PanoplySuite/NOTICE.md` and `PanoplySuite/Licenses/`; what Panoply Suite changed is
listed in `PanoplySuite/GuideEngine/PANOPLY-CHANGES.md`.

## Licence and affiliation

Copyright (C) 2026 Ostrowski Holdings LLC. See `LICENSE` and the `NOTICE.md` files in the add-on
folders for third-party notices.

Panoply Suite is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and
Warcraft are trademarks or registered trademarks of Blizzard Entertainment, Inc., in the U.S. and/or
other countries.
