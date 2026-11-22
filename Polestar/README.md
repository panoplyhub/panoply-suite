# Panoply Suite (saved guide progress)

A stand-in add-on with no game code, published by Ostrowski Holdings LLC. Panoply Suite 0.9.0 to 0.9.4 put the guide
engine's own folders next to Panoply Suite's, and the game saved that engine's settings and every character's guide
progress under this folder's name. Panoply Suite 0.9.5 carries the engine inside its own folder, so this folder keeps
the old name and its TOC lists the old saved-data names: the game keeps loading the old files, and Panoply Suite takes
them over the first time each character logs in (Core/Bundle.lua). Panoply Suite never edits the old files; the game
writes them back at log out (the same tables), so going back to an earlier version finds them.

- Keep it installed and turned on while you have characters that have not logged in since the update.
- It runs no code (its one file, StandIn.lua, holds only comments).

## Licence
GNU General Public License, version 3 only (GPL-3.0-only, see `../PanoplySuite/LICENSE`), like the rest of Panoply Suite.
