PanoplySuiteBundle.File("PanoplyGuide_Recorder", "Ack.lua", function(...) -- The uploader's acknowledgement (docs/RECORDING.md, "Ack file"). PanoplyGuide
-- Client rewrites this file with the highest chunk it has sent for each
-- install (one per WoW account; the accounts share this folder):
--   PanoplyGuideRecorderAck = { ["<install id>"] = <seq>, ... }
-- and at the next login Recorder.lua deletes those chunks. It also writes
--   PanoplyGuideRecorderShare = true|false
-- (sharing on in the client and not paused): true turns recording on at
-- login unless the player typed /psrec off, false turns it off; and
--   PanoplyGuideRecorderExplore = true|false
-- (its explorer mode toggle): false keeps explorer mode off, as /psrec
-- explore off does.
-- The release ships it empty; a lost ack only means a chunk is uploaded twice.
PanoplyGuideRecorderAck = nil

end)
