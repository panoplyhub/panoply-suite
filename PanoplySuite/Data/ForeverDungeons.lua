-- Panoply Suite 0.9.5 (phase 4D): the dungeons only WoW Forever has, for the pages that list dungeons by level (At Your Level first).
-- The instance atlas (PanoplySuite_QuestData MapData, the classic 1.12 world) has no record of them, so they live here, in one small
-- file that is easy to correct. COMMUNITY / BETA DATA, NOT VERIFIED IN THE GAME: every row is marked unverified.
--
-- The list is empty in this release: rows come back only from clean sources (the game client's own tables or in-game recordings).
-- A row is { name, enter, mobs = { lo, hi }, estimated, zone, side }: enter is the lowest level that can go in, mobs the level range
-- of the monsters inside, zone where the way in is (by zone name; nil = "Source unknown"), side the faction whose land the way in
-- lies in. No door coordinates are known, so no page offers "Point me there" for these rows.
-- No item, boss, drop or quest is known for these dungeons, so no gear comes from them (nothing is guessed).
-- Read only on WoW Forever (Classic Era never shows these rows). GNU GPL v3.
local ADDON, Panoply = ...

Panoply.ForeverDungeons = {
  version = 1,
  unverified = true,
  list = {},
}
