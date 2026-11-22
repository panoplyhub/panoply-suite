-- Panoply Suite ProfDetect: finds the character's professions from the skill list by itself.
-- Never asks. Runs at login, when entering the world, and whenever skills or spells change;
-- learning or unlearning a profession adds or removes its plan at once, with a short toast.
-- Per character (PanoplySuiteCharDB), so a new alt is detected on its first login.
-- Manual override (Settings only): per profession "auto" (default), "always" or "never".
local ADDON, Panoply = ...
local D = {}
Panoply.ProfDetect = D
local C = Panoply.Compat
local function PD() return Panoply.ProfData end

D.OVERRIDES = { "auto", "always", "never" }
D.OVERRIDE_LABELS = { auto = "Automatic", always = "Always plan", never = "Never plan" }

local function store()
  local cdb = Panoply.cdb
  if not cdb then return nil end
  local pr = cdb.professions
  if type(pr) ~= "table" then pr = {}; cdb.professions = pr end
  pr.primary = pr.primary or {}
  pr.secondary = pr.secondary or {}
  pr.override = pr.override or {}
  return pr
end

-- Live scan: { [profName] = { rank, max } } for every profession the character knows.
-- C.GetSkills picks the API: C_SkillInfo / GetProfessions (Forever) or GetSkillLineInfo (Era).
function D:Scan()
  local pd = PD()
  local byLine = {}
  for name, line in pairs(pd.SKILL_LINES) do byLine[line] = name end
  local known, n = {}, 0
  local skills, how = C.GetSkills()
  for _, s in ipairs(skills or {}) do
    local name = (s.skillLineID and byLine[s.skillLineID]) or (pd.SKILL_LINES[s.name] and s.name) or nil
    if name and (s.max or 0) > 0 then
      known[name] = { rank = s.rank or 0, max = s.max or 0 }
      n = n + 1
    end
  end
  return known, n, how, skills and #skills or 0
end

-- The professions Panoply Suite plans: detected ones plus "always", minus "never".
function D:Effective(known)
  local pr = store() or { override = {} }
  local pd = PD()
  local prim, sec = {}, {}
  for _, name in ipairs(pd.ORDER) do
    local o = pr.override[name] or "auto"
    local on = (o == "always") or (o ~= "never" and known[name] ~= nil)
    if on then
      if pd.SECONDARY[name] then sec[#sec + 1] = name else prim[#prim + 1] = name end
    end
  end
  return prim, sec
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function joinNames(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- Re-scan and apply. Returns added, removed (lists of names).
function D:Detect(reason)
  local pr = store()
  if not pr then return {}, {} end
  local known, n, how, total = self:Scan()
  -- The skill list can be empty for a moment while the game loads; don't drop professions then.
  if total == 0 and pr.detected and next(pr.detected) then return {}, {} end
  local before = pr.detected
  local added, removed = {}, {}
  local pd = PD()
  for _, name in ipairs(pd.ORDER) do
    local had = before and before[name] ~= nil
    if known[name] and not had then added[#added + 1] = name end
    if had and not known[name] then removed[#removed + 1] = name end
  end
  local firstScan = before == nil
  pr.detected = known
  pr.detectedHow = how
  pr.detectedAt = C.GetTime and C.GetTime() or 0
  local prim, sec = self:Effective(known)
  local changed = not (same(prim, pr.primary) and same(sec, pr.secondary))
  pr.primary, pr.secondary = prim, sec
  if pr.mode == nil then pr.mode = "current" end
  -- the tracked profession follows: drop it if it is gone
  if Panoply.cdb.profTrack and not known[Panoply.cdb.profTrack] and (pr.override[Panoply.cdb.profTrack] or "auto") ~= "always" then Panoply.cdb.profTrack = nil end
  if Panoply.ProfUI and Panoply.ProfUI.selected and removed[1] then
    for _, r in ipairs(removed) do if Panoply.ProfUI.selected == r then Panoply.ProfUI.selected = nil end end
  end
  if #added > 0 or #removed > 0 or changed then
    Panoply:Debug("professions detected", reason or "", "via", tostring(how), "added", joinNames(added), "removed", joinNames(removed))
    if Panoply.ProfGuide then Panoply.ProfGuide:Invalidate(); Panoply.ProfGuide:Refresh("detect") end
    Panoply:Fire("PROFS_DETECTED", added, removed)
    Panoply:Fire("PROF_UPDATED")
    self:Announce(added, removed, firstScan)
  end
  return added, removed
end

function D:Announce(added, removed, firstScan)
  self.lastToast = nil
  local pd = PD()
  if #added > 0 then
    local planned, basic = {}, {}
    for _, a in ipairs(added) do if pd[a] and pd[a].ranks then planned[#planned + 1] = a else basic[#basic + 1] = a end end
    local head
    if #planned > 0 then head = "Panoply Suite: " .. joinNames(planned) .. " detected, plan" .. (#planned > 1 and "s" or "") .. " ready."
    else head = "Panoply Suite: " .. joinNames(basic) .. " detected." end
    local body = #basic > 0 and #planned > 0 and (joinNames(basic) .. ": trainers and basics only for now.")
      or (#basic > 0 and "Trainers and basics only for now.") or "See the Professions tab or follow the guide."
    self.lastToast = { head, body }
    if Panoply.Toast then Panoply.Toast:Show(head, body) end
    Panoply:Print(head)
  elseif #removed > 0 and not firstScan then
    local head = "Panoply Suite: " .. joinNames(removed) .. " unlearned, plan removed."
    self.lastToast = { head, "" }
    if Panoply.Toast then Panoply.Toast:Show(head, "") end
    Panoply:Print(head)
  end
end

-- Manual override from Settings: cycles Automatic -> Always plan -> Never plan.
function D:Override(name) local pr = store() return pr and pr.override[name] or "auto" end
function D:SetOverride(name, value)
  local pr = store()
  if not pr then return end
  pr.override[name] = (value ~= "auto") and value or nil
  self:Detect("override")
  Panoply:Fire("OPTION_CHANGED", "profOverride")
end
function D:CycleOverride(name)
  local cur = self:Override(name)
  local nxt = cur == "auto" and "always" or cur == "always" and "never" or "auto"
  self:SetOverride(name, nxt)
  return nxt
end

-- Debounced re-scan (skill events come in bursts).
local pending
function D:Schedule(reason)
  if pending then return end
  pending = true
  C.After(0.3, function() pending = false; if Panoply.db then local ok, err = pcall(D.Detect, D, reason) if not ok then Panoply:Debug("prof detect", err) end end end)
end

-- 0.6.1: LEARNED_SPELL_IN_SKILL_LINE (both clients); the old LEARNED_SPELL_IN_TAB is in neither API dump.
function D:Register()
  for _, ev in ipairs({ "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
    Panoply:On(ev, function() if Panoply.db then D:Schedule(ev) end end)
  end
end
D:Register()
