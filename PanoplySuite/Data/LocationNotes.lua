-- Panoply Suite curated location notes: OUR OWN hand-written table (Panoply Suite project, same licence as
-- the rest of this add-on). Not taken from any guide, add-on or website. Entries here win over the
-- generated facts in PanoplySuite_QuestData.
--
-- [npcId] (or objects[objectId]) = {
--   kind     = "inside" | "near",
--   name     = building or place, as it should read after "Inside" / "Near",
--   room     = optional room or part of the building ("throne room"),
--   floor    = optional 1 (upstairs) / -1 (downstairs),
--   entrance = optional { map = uiMapID, x = 0..1, y = 0..1 } - the arrow points here first while
--              you are outside. Only fill it in after standing in the doorway in game.
--   forever  = true when the entry was also checked on WoW Forever (re-drawn zones skip the rest),
--   checked  = how the entry was checked.
-- }
-- The examples below were checked against the NPC's spawn position in the VMaNGOS data (the leader
-- stands in the building's main hall); in-game checks are still pending, so none has an entrance yet.
local ADDON, Panoply = ...
Panoply.LocationNotesCurated = {
  source = "Panoply Suite (own)",
  npcs = {
    [1748]  = { kind = "inside", name = "Stormwind Keep", room = "throne room", checked = "spawn position" },    -- Highlord Bolvar Fordragon
    [2784]  = { kind = "inside", name = "the High Seat", checked = "spawn position" },                           -- King Magni Bronzebeard (Ironforge)
    [4949]  = { kind = "inside", name = "Grommash Hold", checked = "spawn position" },                           -- Thrall (Orgrimmar)
    [7999]  = { kind = "inside", name = "the Temple of the Moon", checked = "spawn position" },                  -- Tyrande Whisperwind (Darnassus)
    [10181] = { kind = "inside", name = "the Royal Quarter", checked = "spawn position" },                       -- Lady Sylvanas Windrunner (Undercity)
  },
  objects = {},
}
