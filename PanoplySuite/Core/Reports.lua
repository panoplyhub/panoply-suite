-- Panoply Suite reports (SPEC-REPORTS.md): what a report holds and how it is saved.
-- Original code for Panoply Suite. No third-party code.
--
-- R:Build(opts) gathers the context for one report: Panoply Suite and game versions, the character's
-- level / race / class / faction, where you stand, the plan and the step, the quest IDs in your
-- log, the route legs, a few settings, the breadcrumb and recent Panoply Suite problems.
-- R:Lines(report) turns it into the plain lines the "What we'll send" panel shows, so the player
-- reads exactly what is kept. R:Submit(report) stores it for Panoply Hub, which sends it when it runs.
-- 0.9.4 (ticket pipeline, step 11): a saved report never carries the character's name, realm, race or class (R:Build scrubs
-- every string in it); "feedback" is a third kind; R:ReloadNow reloads the UI outside combat only; the companion app's ticket
-- file (PanoplySuite_Plans/Tickets.lua, global PanoplySuiteTickets) is read as untrusted data and turned into one-time notices.
local ADDON, Panoply = ...
local R = Panoply.Reports or {}
Panoply.Reports = R

-- Reason chips, in the order the window shows them.
R.REASONS = {
  { key = "quest_unavailable", label = "Quest not available" },
  { key = "npc_missing", label = "NPC or object not there" },
  { key = "wrong_location", label = "Wrong location" },
  { key = "wont_complete", label = "Step won't complete" },
  { key = "odd_route", label = "Route is odd" },
  { key = "other", label = "Other" },
}
R.REASON_LABEL = {}
for _, r in ipairs(R.REASONS) do R.REASON_LABEL[r.key] = r.label end

-- Settings a report carries (Panoply Suite's own options only; plain values).
R.SETTING_KEYS = { "autoAccept", "autoTurnIn", "autoFly", "autoOnlyPlanQuests", "autoSkipTrivial", "groupQuests", "partyShare",
  "autoExtendPlan", "routeEnabled", "routeFlights", "routeHearth", "routeTransports", "routeRoads",
  "routeSteps", "syncEnabled", "profGuide", "profStrategy", "iconStyle", "stepsShown", "plannerHorizon" }
R.MAX_LOG_IDS, R.MAX_GOALS, R.MAX_LEGS, R.MAX_REPORT_ERRORS = 35, 10, 8, 5

local function now() return (_G.time and _G.time()) or os.time() end
local function round(v, n) if type(v) ~= "number" then return nil end local m = 10 ^ (n or 3) return math.floor(v * m + 0.5) / m end
local function plain(s, n)
  if s == nil then return nil end
  s = tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
  return R.Cut(s, n or 120)
end
local function try(fn, ...) local ok, a, b, c, d = pcall(fn, ...) if ok then return a, b, c, d end end

-- A stable key for a step (levelling steps have none of their own): kind + the goals' quest IDs.
function R.StepKey(step)
  if not step then return nil end
  if step.key then return tostring(step.key) end
  local parts = { step.kind or "step" }
  local short = { accept = "a", turnin = "t", complete = "c", objective = "o", kill = "k", collect = "l", ["goto"] = "g", level = "v" }
  for _, g in ipairs(step.goals or {}) do
    if g.questID then parts[#parts + 1] = (short[g.type] or "x") .. g.questID
    elseif g.type == "level" and g.level then parts[#parts + 1] = "v" .. g.level end
  end
  if #parts == 1 and step.questID then parts[2] = "q" .. step.questID end
  return table.concat(parts, ":")
end

local function stepInfo(step, index)
  if not step then return nil end
  local ST = Panoply.StepText
  local out = { index = index, key = R.StepKey(step), kind = step.kind, title = plain(ST and ST.Headline(step) or step.title) }
  if step.isTravel then out.travel = true end
  if step.isProf then out.profession = plain(step.prof, 40) end
  local quests = ST and ST.Quests and try(ST.Quests, step) or {}
  local q = quests[1]
  out.questID = step.questID or (q and q.id)
  out.questName = plain(step.questName or (q and q.name), 80)
  if #quests > 1 then
    out.otherQuests = {}
    for i = 2, math.min(#quests, 4) do out.otherQuests[#out.otherQuests + 1] = quests[i].id end
  end
  out.goals = {}
  for i, g in ipairs(step.goals or {}) do
    if i > R.MAX_GOALS then break end
    out.goals[#out.goals + 1] = { type = g.type, questID = g.questID, text = plain(g.text, 100), hint = g.hint or nil,
      state = g.status ~= nil and tostring(g.status) or nil, deferred = g.deferred and true or nil,
      mapID = g.mapID, x = round(g.x, 3), y = round(g.y, 3) }
  end
  out.mapID, out.x, out.y = step.mapID, round(step.x, 3), round(step.y, 3)
  return out
end

local function routeInfo()
  local r = Panoply.Route and Panoply.Route.current
  if type(r) ~= "table" then return nil end
  local function place(n) return type(n) == "table" and plain(n.name or n.label, 40) or nil end
  local out = { total = round(r.total, 0), legs = {} }
  for i, l in ipairs(r.legs or {}) do
    if i > R.MAX_LEGS then break end
    out.legs[#out.legs + 1] = { kind = l.kind, from = place(l.from), to = place(l.to), seconds = round(l.seconds, 0), yards = round(l.yards, 0) }
  end
  return out
end

-- Everything a report carries. opts: { kind = "step" | "general" | "feedback", step =, index =, reason =, note = }
-- (0.9.4: opts.includeName is ignored: a report never carries the character's name or realm)
function R:Build(opts)
  opts = opts or {}
  local C, S, E, P = Panoply.Compat, Panoply.State or {}, Panoply.Engine, Panoply.Planner
  local rep = { schema = R.SCHEMA, kind = opts.kind or "step", sent = false, created = now() }
  rep.installId = self.db and self.db.installId or nil
  rep.reason = opts.reason
  rep.reasonText = R.REASON_LABEL[opts.reason or ""]
  local note = opts.note and tostring(opts.note):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if note ~= "" then rep.note = self:Scrub(R.CutNote(note), false) end
  -- versions
  local qd = Panoply.QuestData
  rep.addon = { version = Panoply.version, questData = qd and qd.Available and try(qd.Available, qd) and (qd.fingerprint or "on") or "off" }
  local v, b, toc
  if C and C.BuildInfo then
    local _
    v, b, _, toc = C.BuildInfo()
  end
  rep.game = { flavor = C and C.Flavor and C.Flavor() or nil, version = v, build = b and tostring(b), toc = toc,
               locale = _G.GetLocale and try(_G.GetLocale) or nil }
  -- the character: level and faction only. 0.9.4: never the name, realm, race or class (the consent notice says so)
  local pi = C and C.PlayerInfo and try(C.PlayerInfo) or {}
  rep.player = { level = S.level or (_G.UnitLevel and try(_G.UnitLevel, "player")), faction = pi.faction }
  -- where
  local m, x, y = nil, nil, nil
  if C and C.GetPlayerPos then m, x, y = try(C.GetPlayerPos) end
  rep.where = { zone = plain(S.zone, 60), subzone = plain(S.subzone, 60), mapID = m, x = round(x, 3), y = round(y, 3) }
  -- the plan and the step
  if E then
    rep.plan = { title = plain(E.title, 60), id = P and P.hash and tostring(P.hash) or nil, steps = #(E.steps or {}), index = E.index,
                 guide = Panoply.ProfGuide and Panoply.ProfGuide.Active and try(Panoply.ProfGuide.Active, Panoply.ProfGuide) or nil }
    local step, index = opts.step, opts.index
    if not step and rep.kind == "step" then step, index = E:Current(), E.index end
    rep.step = stepInfo(step, index)
  end
  -- 0.7.4: the player's own level times against the simulator (Engine/LevelStats.lua: whole minutes per band of
  -- levels, no zone names). It sits inside "plan" because Panoply Hub and the report server keep only the
  -- fields they list, and "plan" is kept whole; a field of its own needs both to be updated first.
  local ls = Panoply.LevelStats and Panoply.LevelStats.ReportSummary and try(Panoply.LevelStats.ReportSummary, Panoply.LevelStats)
  if ls then
    rep.plan = rep.plan or {}
    rep.plan.levelStats = ls
  end
  -- 0.7.5: how much the Forever quest recorder has saved (Engine/QuestRecorder.lua): counts only, no names or positions.
  -- Inside "plan" for the same reason as levelStats above.
  local qr = Panoply.QuestRecorder and Panoply.QuestRecorder.ReportSummary and try(Panoply.QuestRecorder.ReportSummary, Panoply.QuestRecorder)
  if qr then
    rep.plan = rep.plan or {}
    rep.plan.questRecorder = qr
  end
  -- quest IDs in the log (IDs only: no titles, no objectives text)
  rep.questLog = {}
  for id in pairs(S.log or {}) do if type(id) == "number" then rep.questLog[#rep.questLog + 1] = id end end
  table.sort(rep.questLog)
  while #rep.questLog > R.MAX_LOG_IDS do table.remove(rep.questLog) end
  rep.route = routeInfo()
  -- settings
  rep.settings = {}
  local db = Panoply.db or {}
  for _, k in ipairs(R.SETTING_KEYS) do
    local val = db[k]
    if type(val) == "boolean" or type(val) == "number" or (type(val) == "string" and #val <= 24) then rep.settings[k] = val end
  end
  if Panoply.Modules and Panoply.Modules.list then
    local on = {}
    for _, d in ipairs(Panoply.Modules.list) do if d.active then on[#on + 1] = d.key end end
    table.sort(on)
    rep.settings.modules = table.concat(on, ",")
  end
  rep.breadcrumb = self:Breadcrumb()
  -- recent Panoply Suite problems (signature, count, message)
  rep.errors = {}
  if self.db then
    local list = {}
    for _, e in pairs(self.db.errors) do list[#list + 1] = e end
    table.sort(list, function(a, c) return (a.last or 0) > (c.last or 0) end)
    for i = 1, math.min(#list, R.MAX_REPORT_ERRORS) do
      rep.errors[i] = { sig = list[i].sig, kind = list[i].kind, count = list[i].count, msg = R.Cut(list[i].msg, 160) }
    end
  end
  -- 0.9.4: every string in the report (and every key) is scrubbed of the character's name and realm, emails and BattleTags:
  -- a plan title, a zone, a quest or objective text, a route place, an error message or anything else that could carry one
  return self:ScrubAll(rep)
end

-- Strings that come from Panoply Suite's OWN data (plan, step and quest titles, goal wording, route place names). A character name
-- or a realm cannot be in them; a realm that is also a game word (Whitemane, Mankrik, Herod, Arugal...) can, and replacing it
-- there would turn "Whitemane's Embrace" into "<character>'s Embrace" (0.9.4 review K4). Choice: these fields skip ONLY the name
-- and realm step; emails, BattleTags and other add-ons' paths are still removed from them. Everything else (the note, error text,
-- breadcrumb, zone and subzone, settings text, any key) is free text and is scrubbed whole-word, in any capitalisation.
-- Paths name string keys only ("step.goals.text": list positions are skipped).
R.OWN_DATA_FIELDS = { ["plan.title"] = true, ["step.title"] = true, ["step.questName"] = true, ["step.profession"] = true,
                      ["step.goals.text"] = true, ["step.goals.hint"] = true, ["route.legs.from"] = true, ["route.legs.to"] = true }

-- A copy of value v with every string (and string key) scrubbed (R:Scrub, name and realm removed except in R.OWN_DATA_FIELDS).
function R:ScrubAll(v, depth, path)
  depth = depth or 0
  path = path or ""
  if type(v) == "string" then return (self:Scrub(v, R.OWN_DATA_FIELDS[path] == true)) end
  if type(v) ~= "table" or depth > 8 then return v end
  local out = {}
  for k, x in pairs(v) do
    local sub = path
    if type(k) == "string" then
      sub = path == "" and k or (path .. "." .. k)
      k = self:Scrub(k, false)
    end
    out[k] = self:ScrubAll(x, depth + 1, sub)
  end
  return out
end

-- The note: at most MAX_NOTE characters (UTF-8 safe: never cuts a character in half).
function R.CutNote(s)
  s = tostring(s or "")
  if #s <= R.MAX_NOTE then return s end
  s = s:sub(1, R.MAX_NOTE)
  -- drop a trailing partial UTF-8 sequence
  local i = #s
  while i > 0 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end
  if i > 0 and s:byte(i) >= 192 then s = s:sub(1, i - 1) end
  return s
end

-- "Credit me as": what the player typed, without control characters, trimmed, at most MAX_CREDIT characters (UTF-8 safe);
-- nil when nothing is left. Never scrubbed: it is a name the player chose to give.
R.MAX_CREDIT = 40
function R.CleanCredit(s)
  if type(s) ~= "string" then return nil end
  -- 0.9.4 (review K7): the game's escape codes go first (colour |cAARRGGBB ... |r, textures |T...|t, links |H...|h...|h, |n), then
  -- any lone "|", then control characters; only then trim and cut. What is typed can never draw or link anything.
  s = s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|[hrRnN]", ""):gsub("|", "")
  s = s:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local n, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    local len = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
    if n >= R.MAX_CREDIT then s = s:sub(1, i - 1) break end
    n, i = n + 1, i + len
  end
  s = s:gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

-- Store a confirmed report (the player pressed a button on the consent notice) for Panoply Hub. Returns the stored report (with
-- its id), or nil and a reason when it may not be saved (a feedback report needs a note). "sent" stays false here; only Panoply
-- Hub sets it to true, through its write journal with the game closed, after the report server took it.
function R:Submit(rep)
  if not self.db then self:InitDB() end
  if rep.kind == "feedback" and not (type(rep.note) == "string" and rep.note:find("%S")) then return nil, "a feedback report needs a note" end
  local general = rep.kind == "general" or rep.kind == "feedback"
  rep.id = self:NextId(general and "g" or "r")
  rep.sent = false
  rep.credit = R.CleanCredit(rep.credit)
  rep.bytes = nil
  rep.bytes = R.Size(rep)
  local list = self.db.reports
  list[#list + 1] = rep
  self.db.queuedNotice = true   -- 0.9.4: "Report queued" is shown once at the next load (UI/Report.lua)
  self:Enforce()
  self:Crumb("REPORT_SAVED", rep.kind)
  if Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "report") end
  return rep
end

-- 0.9.5 phase 4A4 (06b section 2, "Keep it on this computer"): a kept report goes into its own NEW list, PanoplySuiteReportsDB.localReports,
-- not db.reports, so no Panoply Hub (today's reads only db.reports) can ever send it, even after sharing is turned on later.
function R:SubmitLocal(rep)
  if not self.db then self:InitDB() end
  if rep.kind == "feedback" and not (type(rep.note) == "string" and rep.note:find("%S")) then return nil, "a feedback report needs a note" end
  local general = rep.kind == "general" or rep.kind == "feedback"
  rep.id = self:NextId(general and "g" or "r")
  rep.keepLocal, rep.sendOnce, rep.sent = true, nil, false
  rep.credit = R.CleanCredit(rep.credit)
  rep.bytes = nil
  rep.bytes = R.Size(rep)
  if type(self.db.localReports) ~= "table" then self.db.localReports = {} end
  local list = self.db.localReports
  list[#list + 1] = rep
  self:Enforce()
  self:Crumb("REPORT_SAVED", rep.kind)
  if Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "report") end
  return rep
end

-- Reload the interface so the saved report reaches the file the companion app reads. Never in combat: in combat it waits for
-- PLAYER_REGEN_ENABLED and reloads once then. Returns "now", "after_combat" or "unavailable" (no ReloadUI on this client).
local function inCombat()
  local C = Panoply.Compat
  if C and C.InCombat then return C.InCombat() end
  local f = _G.InCombatLockdown
  return f and f() and true or false
end
function R:ReloadNow()
  if type(_G.ReloadUI) ~= "function" then return "unavailable" end
  if inCombat() then
    self.reloadAfterCombat = true
    return "after_combat"
  end
  self.reloadAfterCombat = nil
  _G.ReloadUI()
  return "now"
end
if Panoply.On then
  -- the character is known by login even if it was not when the saved variables loaded (R:ScrubStored does nothing twice)
  Panoply:On("PLAYER_LOGIN", function() if R.db then R:ScrubStored() end end)
  Panoply:On("PLAYER_REGEN_ENABLED", function()
    if not R.reloadAfterCombat or inCombat() then return end
    R.reloadAfterCombat = nil   -- once
    if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
  end)
end

-------------------------------------------------------------------------------
-- Tickets (0.9.4): the companion app cannot write saved variables while the game runs, so it writes
-- Interface/AddOns/PanoplySuite_Plans/Tickets.lua, which sets ONE global when it loads:
--   PanoplySuiteTickets = { format = 1, stamp = "...", tickets = { ["<report id>"] = { ticket = "PS-0042", n = 42,
--                           status = "new", fixedIn = "0.9.5" }, ... } }
-- It is untrusted data: anything that does not fit is ignored silently (never an error, never shown). The global may be absent.
-------------------------------------------------------------------------------
R.TICKET_STATUS = { new = true, triaged = true, in_fix = true, fix_ready = true, fixed = true, wont_fix = true, duplicate = true }
R.MAX_TICKETS, R.MAX_TICKET_ID, R.MAX_TICKET_TEXT, R.MAX_FIXED_IN = 500, 120, 16, 20

-- The valid entries of the file for the reports of THIS account only: { [report id] = { ticket, n, status, fixedIn } }.
function R:ReadTickets()
  local out = {}
  local ok = pcall(function()
    local g = _G.PanoplySuiteTickets
    if type(g) ~= "table" or g.format ~= 1 or type(g.tickets) ~= "table" then return end
    -- more than MAX_TICKETS entries: the whole file is ignored (a partial read would depend on table order)
    local count = 0
    for _ in pairs(g.tickets) do
      count = count + 1
      if count > R.MAX_TICKETS then return end
    end
    local own = {}
    for _, r in ipairs(self.db and self.db.reports or {}) do if type(r) == "table" and type(r.id) == "string" then own[r.id] = true end end
    for id, e in pairs(g.tickets) do
      if type(id) == "string" and #id <= R.MAX_TICKET_ID and own[id] and type(e) == "table" then
        -- one entry at a time: a broken entry costs only itself
        pcall(function()
          local t, n, st, fx = e.ticket, e.n, e.status, e.fixedIn
          local good = type(t) == "string" and #t <= R.MAX_TICKET_TEXT and t:find("^PS%-%d%d%d%d+$") ~= nil
            and type(n) == "number" and n == math.floor(n) and n >= 1 and n < 2 ^ 53
            and type(st) == "string" and R.TICKET_STATUS[st] == true
          if good and fx ~= nil then
            good = type(fx) == "string" and #fx >= 1 and #fx <= R.MAX_FIXED_IN and fx:find("^[%d%.]+$") ~= nil
          end
          if good then out[id] = { ticket = t, n = n, status = st, fixedIn = fx } end
        end)
      end
    end
  end)
  if not ok then return {} end
  return out
end

-- Notice lines owed right now, each shown once: "Report queued" (a report was saved), "Report PS-0042 received" (the first time a
-- ticket number is known for a report), "PS-0042 was fixed in 0.9.5. Thank you." (the first time its status is fixed and the
-- version is known). What was shown is remembered on the report (ticket, ticketN, ticketStatus, fixedIn, toldReceived, toldFixed)
-- and as db.queuedNotice (removed when shown). Calling it again returns nothing new.
-- 0.9.4 (review K10): R:OwedNotices() changes nothing; it returns the lines and a commit function. The card calls commit only after it
-- has been drawn, so an error while drawing does not lose a notice for good. R:TakeNotices() is the two together.
function R:OwedNotices()
  local db = self.db
  if not db then return {}, function() end end
  local lines = {}
  local clearQueued = false
  if db.queuedNotice then
    lines[#lines + 1] = R.NOTICE_QUEUED
    clearQueued = true
  end
  local found = self:ReadTickets()
  local fixed, marks = {}, {}
  for _, r in ipairs(db.reports) do
    local t = type(r) == "table" and found[r.id]
    if t then
      local mark = { r = r, t = t }
      if not r.toldReceived then
        mark.received = true
        lines[#lines + 1] = R.NOTICE_RECEIVED:format(t.ticket)
      end
      if t.status == "fixed" and t.fixedIn and not r.toldFixed then
        mark.fixed = true
        fixed[#fixed + 1] = R.NOTICE_FIXED:format(t.ticket, t.fixedIn)
      end
      marks[#marks + 1] = mark
    end
  end
  for _, l in ipairs(fixed) do lines[#lines + 1] = l end
  local done = false
  local function commit()
    if done then return end
    done = true
    if clearQueued then db.queuedNotice = nil end
    for _, m in ipairs(marks) do
      local r, t = m.r, m.t
      r.ticket, r.ticketN, r.ticketStatus, r.fixedIn = t.ticket, t.n, t.status, t.fixedIn
      if m.received then r.toldReceived = true end
      if m.fixed then r.toldFixed = true end
    end
    if #lines > 0 and Panoply.Fire then Panoply:Fire("REPORTS_CHANGED", "notices") end
  end
  return lines, commit
end
function R:TakeNotices()
  local lines, commit = self:OwedNotices()
  commit()
  return lines
end
R.NOTICE_QUEUED = "Report queued"
R.NOTICE_RECEIVED = "Report %s received"
R.NOTICE_FIXED = "%s was fixed in %s. Thank you."

-------------------------------------------------------------------------------
-- "What we'll send": the report as plain lines, in a fixed order, every field shown.
-------------------------------------------------------------------------------
local ORDER = { "id", "kind", "reason", "reasonText", "note", "credit", "installId", "created", "addon", "game", "player", "where", "plan", "step",
                "questLog", "route", "settings", "errors", "breadcrumb", "schema", "sent" }
local LABEL = { id = "Report id", kind = "Type", reason = "Reason key", reasonText = "Reason", note = "Your note",
  credit = "Credit me as (only because you typed it)",
  installId = "Install number (random, not your account)", created = "Created (time stamp)", addon = "Panoply Suite", game = "Game",
  player = "Character", where = "Where you are", plan = "Plan", step = "Step", questLog = "Quest IDs in your log",
  route = "Route", settings = "Settings", errors = "Recent Panoply Suite problems", breadcrumb = "Recent Panoply Suite events",
  schema = "Format", sent = "Sent" }

local function scalar(v)
  if type(v) == "string" then return v end
  if type(v) == "number" then return (v == math.floor(v)) and tostring(v) or tostring(round(v, 4)) end
  return tostring(v)
end
local function isList(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n == #t end
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end
-- lists shown one entry per line (event trails and stack lines read badly as one long line)
local ONE_PER_LINE = { [LABEL.breadcrumb] = true, events = true, stack = true }
local function emit(out, indent, label, v)
  local pad = ("  "):rep(indent)
  if type(v) ~= "table" then out[#out + 1] = pad .. label .. ": " .. scalar(v) return end
  if isList(v) then
    local simple = true
    for _, x in ipairs(v) do if type(x) == "table" then simple = false break end end
    if #v == 0 then out[#out + 1] = pad .. label .. ": (none)" return end
    if simple and not ONE_PER_LINE[label] then
      local parts = {}
      for _, x in ipairs(v) do parts[#parts + 1] = scalar(x) end
      out[#out + 1] = pad .. label .. ": " .. table.concat(parts, ", ")
      return
    end
    out[#out + 1] = pad .. label .. ":"
    for i, x in ipairs(v) do
      if type(x) == "table" then emit(out, indent + 1, tostring(i), x) else out[#out + 1] = pad .. "  " .. scalar(x) end
    end
    return
  end
  out[#out + 1] = pad .. label .. ":"
  for _, k in ipairs(sortedKeys(v)) do emit(out, indent + 1, tostring(k), v[k]) end
end
function R:Lines(rep)
  local out, seen = {}, {}
  for _, k in ipairs(ORDER) do
    if rep[k] ~= nil then emit(out, 0, LABEL[k] or k, rep[k]) end
    seen[k] = true
  end
  for _, k in ipairs(sortedKeys(rep)) do if not seen[k] and k ~= "bytes" then emit(out, 0, tostring(k), rep[k]) end end
  return out
end
-- An error record as Panoply Hub sends it (the same fields, in the same plain form; "install" is the
-- random install number Hub adds, "events" the breadcrumb kept with it).
function R:ErrorLines(e)
  local out = {}
  local install = self.db and self.db.installId or nil
  emit(out, 0, "Problem " .. tostring(e.sig), { install = install, kind = e.kind, count = e.count, first = e.first, last = e.last, message = e.msg,
    where = e.where, version = e.version, game = e.game, flavor = e.flavor, stack = e.stack, events = e.crumbs })
  return out
end
