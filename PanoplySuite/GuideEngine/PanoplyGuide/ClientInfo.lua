PanoplySuiteBundle.File("PanoplyGuide", "ClientInfo.lua", function(...) -- What PanoplyGuide Client knows of PanoplyGuide's releases (docs/RECORDING.md,
-- "Client info"). The Client rewrites this file after each check for addon
-- updates:
--   PanoplyGuideClientInfo = { latest = "<version>", released = <unix time>,
--     checked = <unix time>, releases = { "<newest>", ... } }
-- and Core/Update.lua reads it at login: the newest release, when it is
-- newer than this one, is told on the update card. The release ships it
-- empty (no Client: nothing known from here).
PanoplyGuideClientInfo = nil

end)
