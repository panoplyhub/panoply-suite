-- Panoply Suite 0.9.5, phase 4A4: the one sharing rule (docs/specs/page-redesigns-06-help.md section 4, as settled by 06b sections 2 and 3).
-- Original code for Panoply Suite.
--
-- Reports and noted problems are always saved on this computer (PanoplySuiteReportsDB). They leave it only through Panoply Hub, and only
-- when "Send reports with Panoply Hub" is on. The add-on itself can't send anything. The setting starts OFF.
--
-- Saved data (all NEW keys; nothing is renamed):
--   PanoplySuiteReportsDB.settings.share  true / false: the setting. A file from before 0.9.5 gets false once (shareV = 1 marks that).
--   PanoplySuiteReportsDB.settings.send   kept, and kept equal to share: it is the key Panoply Hub 0.9.4 reads (it sends nothing from
--                                         an account whose send is false), so the new default holds with the Hub that is out today.
--   PanoplySuiteReportsDB.shareV          1 once the setting has been brought in.
--   report.sendOnce = true                "Send this one": the player agreed for this report only; the setting stays off.
--   report.keepLocal = true               "Keep it on this computer": never asked again for this report, never sent.
--   PanoplySuiteReportsDB.hub             written by Panoply Hub (queue item 11), never by the add-on: { installed = true, lastSent = <time> }.
-- Until Hub writes that marker, Hub counts as installed when it has marked a report or a noted problem sent (sent = true, sentAt).
local ADDON, Panoply = ...
local S = {}
Panoply.Sharing = S

-- The three state lines, verbatim (06b section 3). Every place in the game that says whether anything leaves the computer uses Line().
S.LINE_NO_HUB = "Reports stay on this computer."
S.LINE_OFF = "Reports stay on this computer. Panoply Hub asks before sending one."
S.LINE_ON = "Panoply Hub sends your reports. Last sent: %s."
S.LINE_ON_NONE = "Panoply Hub sends your reports. None sent yet."
-- Muster's "?" tooltip (phase 4I shows it): this first, then the line for the current state
S.MUSTER_TIP = "Your characters' bags, bank and mail are saved in your game's files on this computer."
-- the setting's name and the one-time question (06b section 2)
S.SETTING = "Send reports with Panoply Hub"
S.PROMPT_TITLE = "Send this report with Panoply Hub?"
S.PROMPT_ONE, S.PROMPT_ALWAYS, S.PROMPT_KEEP = "Send this one", "Always send", "Keep it on this computer"
S.SAVED_LOCAL = "Report saved on this computer."
S.SAVED_SENDING = "Panoply Hub will send it."

local function db() return Panoply.Reports and Panoply.Reports.db end
local function now() return (_G.time and _G.time()) or os.time() end

-- Called by Panoply.Reports:InitDB, after the settings have their defaults: a file from before 0.9.5 starts with sharing OFF (its old send
-- default was on, and nobody chose it), and send follows share from then on.
function S:Migrate(d)
  if type(d) ~= "table" or type(d.settings) ~= "table" then return false end
  local st = d.settings
  local first = false
  if type(st.share) ~= "boolean" then st.share = false first = true end
  if d.shareV == nil then d.shareV = 1 first = true end
  st.send = st.share
  return first
end

function S:On()
  local d = db()
  return d and type(d.settings) == "table" and d.settings.share == true or false
end

-- Turn the setting on or off (Help > Sharing, the settings row, "Always send"). Returns true when it changed.
function S:Set(on)
  local d = db()
  if not (d and type(d.settings) == "table") then return false end
  on = on and true or false
  local was = d.settings.share == true
  d.settings.share = on
  d.settings.send = on
  if was ~= on then
    Panoply:Fire("SHARING_CHANGED", on)
    Panoply:Fire("REPORTS_CHANGED", "setting")
  end
  return was ~= on
end

-- Has Panoply Hub ever run for this account: its marker, or a report or noted problem it marked sent.
function S:HubInstalled()
  local d = db()
  if not d then return false end
  if type(d.hub) == "table" and d.hub.installed == true then return true end
  for _, r in ipairs(type(d.reports) == "table" and d.reports or {}) do
    if type(r) == "table" and (r.sent == true or tonumber(r.sentAt)) then return true end
  end
  for _, e in pairs(type(d.errors) == "table" and d.errors or {}) do
    if type(e) == "table" and (e.sent == true or tonumber(e.sentAt)) then return true end
  end
  return false
end

-- When Panoply Hub last sent something (seconds since 1970), or nil.
function S:LastSent()
  local d = db()
  if not d then return nil end
  local last = type(d.hub) == "table" and tonumber(d.hub.lastSent) or nil
  for _, r in ipairs(type(d.reports) == "table" and d.reports or {}) do
    local t = type(r) == "table" and r.sent == true and tonumber(r.sentAt)
    if t and (not last or t > last) then last = t end
  end
  return last
end

-- "nohub", "off" or "on"
function S:State()
  if not self:HubInstalled() then return "nohub" end
  return self:On() and "on" or "off"
end

-- "today 14:02", "yesterday 09:15", or "Nov 3 14:02" (the year too when it is not this one)
S.MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function S.When(t, at)
  local date = _G.date or os.date
  at = at or now()
  local d, n = date("*t", t), date("*t", at)
  local hm = ("%02d:%02d"):format(d.hour, d.min)
  if d.year == n.year and d.yday == n.yday then return "today " .. hm end
  local y = date("*t", at - 86400)
  if d.year == y.year and d.yday == y.yday then return "yesterday " .. hm end
  local day = S.MONTHS[d.month] .. " " .. d.day
  if d.year ~= n.year then day = day .. ", " .. d.year end
  return day .. " " .. hm
end

-- The one line for the current state (06b section 3), exactly.
function S:Line(at)
  local st = self:State()
  if st == "nohub" then return S.LINE_NO_HUB end
  if st == "off" then return S.LINE_OFF end
  local last = self:LastSent()
  if not last then return S.LINE_ON_NONE end
  return S.LINE_ON:format(S.When(last, at))
end

-- Muster's tooltip text: its first line, then the state line.
function S:MusterTip() return S.MUSTER_TIP .. " " .. self:Line() end

-- Is this report one Panoply Hub may send: sharing on (and the player did not keep it), or agreed for this one.
function S:WillSend(rep)
  if type(rep) == "table" and rep.keepLocal then return false end
  -- "Send this one" needs a Panoply Hub that knows it (queue item 11; that Hub writes the marker): an older Hub sends nothing while send
  -- is off, so the report waits here, marked, and nothing claims it will be sent
  if type(rep) == "table" and rep.sendOnce then local d = db() return d and type(d.hub) == "table" and d.hub.installed == true or false end
  return self:State() == "on"
end

-- The one-time question comes before saving when Hub is installed, sharing is off and this report has no answer yet.
function S:NeedsPrompt(rep)
  if self:State() ~= "off" then return false end
  if type(rep) == "table" and (rep.keepLocal or rep.sendOnce) then return false end
  return true
end

-- Apply an answer to the question to a report about to be saved: "one", "always" or "keep". Returns the report.
S.ANSWERS = { one = true, always = true, keep = true }
function S:Answer(rep, choice)
  if not S.ANSWERS[choice] then error("Sharing:Answer: unknown choice " .. tostring(choice), 2) end
  if type(rep) ~= "table" then error("Sharing:Answer needs the report", 2) end
  if choice == "one" then rep.sendOnce, rep.keepLocal = true, nil
  elseif choice == "always" then self:Set(true) rep.sendOnce, rep.keepLocal = nil, nil
  else rep.keepLocal, rep.sendOnce = true, nil end
  return rep
end

-- What the toast after saving says: "Report saved on this computer." or "Report saved" with "Panoply Hub will send it."
function S:SavedWords(rep)
  if self:WillSend(rep) then return "Report saved", S.SAVED_SENDING end
  return "Report saved", S.SAVED_LOCAL
end
