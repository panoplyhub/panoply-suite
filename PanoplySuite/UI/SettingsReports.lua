-- Panoply Suite reports and privacy settings (SPEC-REPORTS.md). Own code. The three switches live in
-- PanoplySuiteReportsDB.settings (not PanoplySuiteDB) so the desktop app outside the game can read the
-- "send" switch. Since the one-window menu these rows are Help > gear > Reports and privacy.
local ADDON, Panoply = ...
local Skin, R, SUI = Panoply.Skin, Panoply.Reports, Panoply.SettingsUI

local NAME = "Reports & privacy"
local Page = {}
Panoply.SettingsReports = Page
Page.NAME = NAME
-- 0.9.5 phase 4A4 (spec 06 section 4): where reports go is said by the sharing state line (Core/Sharing.lua), from the one setting
Page.INTRO = "When a step is wrong or Panoply Suite hits a problem, you can tell us. Reports and noted problems are saved on this computer."
function Page.StateLine() return Panoply.Sharing:Line() end
Page.WAITING = "A report shows as sent once Panoply Hub has sent it and the game has been closed once."
Page.NEVER ="Never kept: chat, whispers, your account name, Battle.net tag or email, and anything from other add-ons."

local function get(k) return function() return R:Setting(k) end end
local function set(k) return function(v) R:SetSetting(k, v and true or false) end end

local function clear()
  R:ClearAll()
  Panoply:Print("Saved reports and noted problems were cleared from this computer.")
end

Page.rows = {
  { type = "heading", label = "Sending" },
  { type = "check", key = "send", label = Panoply.Sharing.SETTING, get = get("send"), set = set("send"),
    tip = "Off (the standard): reports and noted problems stay on this computer." },
  { type = "heading", label = "Panoply Suite problems" },
  { type = "check", key = "captureErrors", label = "Note Panoply Suite errors", get = get("captureErrors"), set = set("captureErrors"),
    tip = "Only Panoply Suite's own errors, with what it was doing just before. Errors from other add-ons are passed on untouched and never kept." },
  { type = "check", key = "chatNotice", label = "Tell me once per session in chat", get = get("chatNotice"), set = set("chatNotice"), indent = true,
    tip = "One short line in chat the first time a problem is noted. No pop-ups." },
  { type = "heading", label = "Kept on this computer" },
  { type = "button", label = "Report a problem...", tip = "Open the report window.", func = function() Panoply.ReportWindow:Open({ general = true }) end },
  { type = "button", label = "Show noted problems", tip = "Panoply Suite's own errors, every line exactly as it would be sent.",
    func = function() Panoply.ReportWindow:OpenProblems() end },
  { type = "button", label = "Clear saved reports", tip = "Removes every saved report and noted problem from this computer.", func = clear },
}

-- The readout under the rows: counts, size, the latest few, and what is never kept.
function Page:Lines()
  if not R.db then return { "Nothing saved yet." } end
  local nr, ne = R:Counts()
  local sent, waiting, refused = R:SendCounts()
  local out = {}
  out[#out + 1] = ("%d report%s saved (%d sent, %d waiting to be sent), %d problem%s noted. %d KB of %d KB used."):format(
    nr, nr == 1 and "" or "s", sent, waiting, ne, ne == 1 and "" or "s", math.ceil((R.bytes or R.Size(R.db.reports)) / 1024), R.MAX_BYTES / 1024)
  out[#out + 1] = Page.StateLine()
  if R:Setting("send") and waiting > 0 then out[#out + 1] = Page.WAITING end
  if refused > 0 then out[#out + 1] = (refused == 1 and "1 report was" or (refused .. " reports were")) .. " not accepted by the report server and won't be sent again." end
  for i = #R.db.reports, math.max(1, #R.db.reports - 2), -1 do
    local r = R.db.reports[i]
    local what = r.step and r.step.title and ("step %s, %s"):format(r.step.index or "?", r.step.title) or (r.kind == "feedback" and "feedback" or "general")
    -- 0.9.4: once the companion app has recorded a ticket number for the report, it is shown after the state
    local state = r.sent == true and "sent" or (r.refused == true and "not accepted" or "waiting")
    if type(r.ticket) == "string" then state = state .. ", " .. r.ticket end
    out[#out + 1] = ("- %s: %s (%s, %s)"):format(r.reasonText or (r.kind == "feedback" and "Feedback / idea" or "Report"), what, r.id or "?", state)
  end
  local errs = {}
  for _, e in pairs(R.db.errors) do errs[#errs + 1] = e end
  table.sort(errs, function(a, b) return (a.last or 0) > (b.last or 0) end)
  for i = 1, math.min(3, #errs) do
    local e = errs[i]
    out[#out + 1] = ("- Problem x%d: %s"):format(e.count or 1, R.Cut(e.msg, 90))
  end
  out[#out + 1] = Page.NEVER
  return out
end
