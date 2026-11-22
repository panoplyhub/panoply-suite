# Panoply Suite Plans

A small data add-on that ships with Panoply Suite. It holds three data files, `Plans.lua` (an empty
list), `Tickets.lua` (no tickets) and `Prices.lua` (no prices), and does nothing on its own. Keep it
installed next to the other Panoply Suite folders.

The game only ever reads these files. They may be updated from outside the game:

- `Prices.lua` holds free WoW Forever auction prices from Blizzard's game data API (nothing older
  than 30 days). Classic Era keeps the empty file.
- `Tickets.lua` can hold the ticket number and status of reports you sent.

## Licence
GNU General Public License, version 3 only (GPL-3.0-only, see `LICENSE`), like the rest of Panoply Suite.
