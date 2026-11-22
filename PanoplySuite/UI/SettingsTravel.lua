-- Panoply Suite travel settings (0.6.0 M6, SPEC section 21.9): the rows for Fastest way there, Trail and
-- Trip times, and the calibration readout (what Panoply Suite has measured for this character) with the
-- road recorder's state. Since the one-window menu they live in Guide > gear (UI/Catalog.lua).
-- Advice and display only.
local ADDON, Panoply = ...
local Skin = Panoply.Skin
local C = Panoply.Compat
local SUI = Panoply.SettingsUI
local Calib = {}
Panoply.Calib = Calib
local floor = math.floor

local function forget()
  if Panoply.Pace then Panoply.Pace:Reset() end
  Panoply:Print("Your pace has been forgotten. Panoply Suite starts learning it again from now.")
  Panoply:Fire("PACE_CHANGED")
end
SUI.ForgetPace = forget

SUI.travelRows = {
  { type = "heading", label = "Fastest way there" },
  { type = "check", key = "routeFlights", label = "Use flight paths I know", tip = "Walks you to the flight master when flying is faster. You still talk to the flight master yourself." },
  { type = "check", key = "routeHearth", label = "Use my hearthstone", tip = "Counts your hearthstone when it is ready and goes to your inn." },
  { type = "check", key = "routeTransports", label = "Use boats, trams and zeppelins", tip = "Includes the waiting time at the dock or station." },
  { type = "check", key = "routeRoads", label = "Follow roads and passes", tip = "Off: straight lines, like before 0.6.0." },
  { type = "check", key = "routeSteps", label = "Add \"Fly to\" and \"Take the boat\" steps when faster", tip = "A short travel step before the guide's step when flying, a boat, tram or portal saves at least half a minute. Skip it any time." },
  { type = "check", key = "routeLearnFP", label = "Remind me to learn new flight paths", tip = "Adds a short stop at a flight master you pass but have not met yet." },
  { type = "heading", label = "Trail" },
  { type = "check", key = "trailWorldMap", label = "Show the trail on the world map" },
  { type = "check", key = "trailMinimap", label = "Show the trail on the minimap" },
  { type = "check", key = "trailAnimate", label = "Let the dots drift slowly along the route", indent = true, tip = "Off: the dots stand still." },
  { type = "heading", label = "Times" },
  { type = "check", key = "tripShown", label = "Show the trip time under the guide window" },
  { type = "check", key = "paceShown", label = "Show the time to my next level" },
  { type = "check", key = "paceLearn", label = "Learn my pace from my real travel times", tip = "Compares your real walks and flights with the estimate, within limits (0.7x to 1.6x). Off: the standard estimate." },
  { type = "choice", key = "paceSource", label = "Time to level from", values = { { "pace", "My own pace" }, { "plan", "The plan's estimate" } },
    tip = "My own pace: learned from your experience per hour while you play (rested time and AFK left out). The plan's estimate: from the route only." },
  { type = "button", label = "Forget my pace", tip = "Starts learning your pace again from now.", func = forget },
}

-- 0.7.3.7 ("Fix every size slider"): the dots have a size and an opacity on each map (Map page > Look of the map)
for _, r in ipairs(Panoply.Look.Rows("trail")) do SUI.travelRows[#SUI.travelRows + 1] = r end

-------------------------------------------------------------------------------
-- Calibration readout (also /panoply calib)
-------------------------------------------------------------------------------
local function yds(v) return ("%.1f yd/s"):format(v) end

function Calib:Lines()
  local out = {}
  local R = Panoply.Route
  if R then
    local g = R:GroundSpeed()
    if g > R.RUN_SPEED + 0.05 then
      out[#out + 1] = ("Speed: running %s; fastest seen %s (%d%% faster, mounted)."):format(yds(R.RUN_SPEED), yds(g), floor((g / R.RUN_SPEED - 1) * 100 + 0.5))
    else
      out[#out + 1] = ("Speed: running %s (no mount seen yet)."):format(yds(R.RUN_SPEED))
    end
  end
  if Panoply.Pace then for _, l in ipairs(Panoply.Pace:Summary()) do out[#out + 1] = l end end
  if C.MinimapRadius then
    local ok, r = pcall(C.MinimapRadius)
    if ok and r then
      local z = C.MinimapZoom and C.MinimapZoom() or 0
      out[#out + 1] = ("Minimap: about %d yd from the middle to the edge (zoom %d%s%s)."):format(floor(r + 0.5), z,
        (C.Indoors and C.Indoors()) and ", indoors" or "", (C.MinimapRotates and C.MinimapRotates()) and ", turning with you" or "")
    end
  end
  if R then
    local cd = R:HearthCooldown()
    local bind = C.BindLocation and C.BindLocation()
    if cd == nil then out[#out + 1] = "Hearthstone: not in your bags."
    else
      out[#out + 1] = ("Hearthstone: %s%s."):format(bind and ("set to " .. bind .. ", ") or "", cd <= 0 and "ready" or ("ready in " .. R.Duration(cd)))
    end
  end
  local Rec = Panoply.Recorder
  if Rec then
    local n = Panoply.db and type(Panoply.db.roadRecords) == "table" and #Panoply.db.roadRecords or 0
    if Rec:Active() then
      out[#out + 1] = ("Road recorder: recording \"%s\" (%d points). Type /panoply record stop to save it."):format(Rec.rec.name, #Rec.rec.points)
    else
      out[#out + 1] = ("Road recorder: off, %d recording%s saved. Type /panoply record to capture a road you walk."):format(n, n == 1 and "" or "s")
    end
  end
  return out
end
