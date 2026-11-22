-- Fallback TOC only: keep the data file that matches the running client (the other file returns early).
local RD = PanoplySuiteRouteData
local v = select(4, GetBuildInfo and GetBuildInfo() or nil) or 0
RD.want = (v >= 16000) and "forever" or "era"
