-- Quest tracker (SPEC 23): every quest in the log, grouped by zone (current zone first), with
-- objectives, "Ready to turn in", timers, party progress and quest item buttons (ItemButtons.lua).
-- v3 look. Rebuilds at most twice a second; rows are pooled; the only timers are a 1 s countdown
-- while a timed quest shows and a 3 s refresh while a quest item exists.
-- Combat: while any secure item button is shown the layout is frozen (text still updates);
-- everything that would move a row waits for PLAYER_REGEN_ENABLED.
local ADDON, Panoply = ...
local C = Panoply.Compat

local QT = Panoply.Modules:Register({
  key = "questTracker", label = "Quest tracker", icon = "TurnIn",
  desc = "A movable list of every quest in your log, grouped by zone, with objectives, timers, party progress and a button for each usable quest item.",
  defaults = {
    trackerAutoTrack = true, trackerItems = true, trackerParty = true, trackerSort = "zone",
    trackerFontSize = 12, trackerOutline = false, trackerBgAlpha = 0.85, trackerLocked = false,
    trackerHideBG = true, trackerHideDungeon = false, trackerHideBlizzard = true, trackerShowAll = false,
  },
})
Panoply.QuestTracker = QT

QT.WIDTH = 280
QT.MIN_W, QT.MAX_W = 280, 480      -- Nov 2026: the grip sets the width too (remembered per character: trackerWidth)
QT.HEADER = 30
QT.CAP_CLEAR = 6      -- header and grip keep this far in from the edges (cap depth 3 + 2 px clear + 1)
QT.PAD = 10          -- inside the panel; the brass caps reach at most 3 px in from an edge
QT.MIN_H, QT.MAX_H, QT.DEFAULT_H = 120, 900, 340
QT.THROTTLE = 0.5
QT.ITEM = 24          -- item button size
QT.GUTTER = 30        -- room kept at the right of a quest for its item button
-- 0.6.0: the tracker shares the v3 skin's media (Media/V3, Media/Fonts, Media/Icons/J); its own copies
-- (needed only before the skin was merged) are gone.
QT.MEDIA = "Interface\\AddOns\\PanoplySuite\\Media\\V3\\"
QT.FONT_DIR = "Interface\\AddOns\\PanoplySuite\\Media\\Fonts\\"
QT.SORTS = { { "zone", "Zone" }, { "level", "Level" }, { "distance", "Distance" } }

-------------------------------------------------------------------------------
-- Look: the v3 Skin when it is merged (Skin.FONTS marks it), else our own copies and hex values.
-------------------------------------------------------------------------------
local function hex(h)
  h = h:gsub("#", "")
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
QT.COLORS = {
  heading = hex("#e9cf93"), text = hex("#e6e4de"), accent = hex("#5bbcd0"), panel = hex("#151d27"),
  trim = hex("#b8955a"), card = hex("#0e141c"), hairline = hex("#263140"), inkSoft = hex("#9aa5b2"),
  dim = hex("#6f7a87"), done = hex("#74c98f"), warn = hex("#e8875f"), icon = hex("#d6b878"), red = hex("#d9574f"),
  bgHigh = hex("#1e2834"),
}
-- quest difficulty in the v3 brand shades (same hues as the game's red/orange/yellow/green/grey)
QT.DIFF = { impossible = hex("#d9574f"), verydifficult = hex("#e48a4c"), difficult = hex("#e8c25a"),
            standard = hex("#73c47a"), trivial = hex("#9a9a9a") }
local OWN_FONTS = {
  head = QT.FONT_DIR .. "SpectralSC-SemiBold.ttf", body = QT.FONT_DIR .. "Lato-Medium.ttf",
  semi = QT.FONT_DIR .. "Lato-SemiBold.ttf", label = QT.FONT_DIR .. "Lato-Bold.ttf",
}
local GAME_FONTS = { head = "Fonts\\FRIZQT__.TTF", body = "Fonts\\ARIALN.TTF", semi = "Fonts\\ARIALN.TTF", label = "Fonts\\ARIALN.TTF" }

local function V3() local S = Panoply.Skin return S and S.FONTS and S.colors and S or nil end
function QT.Color(k)
  local S = V3()
  if S and S.colors[k] and k ~= "red" and k ~= "icon" then return S.colors[k] end
  return QT.COLORS[k] or QT.COLORS.text
end
function QT.FontPath(kind)
  local S = V3()
  return (S and S.FONTS[kind]) or OWN_FONTS[kind] or OWN_FONTS.body
end
function QT.Tex(name)
  local S = V3()
  if S and S.TEX and S.TEX[name] then return S.TEX[name] end
  return QT.MEDIA .. name
end
function QT.Icon(name)
  local S = V3()
  if S and S.JIcon then return S.JIcon(name, 20) end
  return "Interface\\AddOns\\PanoplySuite\\Media\\Icons\\J\\" .. name
end
-- Icons follow the player's Icon style (General settings): the game's own glyphs in "WoW icons",
-- our new brass J icons (or our glyphs where there is no J drawing) in "Panoply Suite icons".
-- Registered in Skin.live so a style switch redraws them without a reload.
QT.J = { Lock = true, Sort = true, Gear = true, Map = true, Close = true }
function QT.SetIcon(tex, name)
  local S = Panoply.Skin
  if not tex or not S then return tex end
  local j = name == "Unlock" and "Lock" or name    -- the open padlock is the same drawing, dimmed
  if S.WoW and S.WoW() or not QT.J[j] then
    S.SetGlyph(tex, name)
    if S.WoW and S.WoW() then tex:SetVertexColor(1, 1, 1, 1)
    else local c = QT.Color("icon") tex:SetVertexColor(c[1], c[2], c[3], 1) end
  else
    tex:SetTexture(QT.Icon(j))
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    local c = QT.Color("icon")
    tex:SetVertexColor(c[1], c[2], c[3], 1)
  end
  if S.live then S.live[tex] = { QT.SetIcon, name } end
  return tex
end

function QT.SetFont(fs, kind, size, color)
  local flags = (Panoply.db and Panoply.db.trackerOutline) and "OUTLINE" or ""
  local ok = pcall(fs.SetFont, fs, QT.FontPath(kind), size, flags)
  if not ok or not (fs.GetFont and fs:GetFont()) then pcall(fs.SetFont, fs, GAME_FONTS[kind] or GAME_FONTS.body, size, flags) end
  if color and fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], 1) end
  if fs.SetShadowOffset then
    if flags == "" then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
  end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.8) end
  return fs
end
local function newText(parent, kind, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  QT.SetFont(fs, kind, size, color)
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  fs.panoplyKind = kind
  return fs
end
QT.NewText = newText

-- 0.6.0: a row is as tall as the lines it really draws. The wrapped line count comes from
-- the font's own metrics, word by word (Skin.WrapMeasure); the Skin's generous estimate (which
-- assumes text 15-35% wider than it is) is only the fallback when a font cannot be measured.
local function wrapInfo(fs, width)
  local S = Panoply.Skin
  if S and S.WrapMeasure then
    local n, lh, lastW = S.WrapMeasure(fs, width)
    if n and lh and lh > 0 then return n, lh, lastW end
  end
end
QT.WrapInfo = wrapInfo
local function textH(fs, width)
  local n, lh = wrapInfo(fs, width)
  if n then return math.ceil(n * lh) end
  local S = Panoply.Skin
  local h = S and S.TextHeight and S.TextHeight(fs, width) or 14
  return math.ceil(h)
end

local function colorHex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
QT.Hex = colorHex

-- Rounded v3 box: fill + brass trim (Skin.Box when v3 is merged, else the same art from Media).
function QT.Box(f, size, fillColor, fillA, lineColor, lineA)
  local S = V3()
  if S and S.Box then
    local fill, line = S.Box(f, size, { fill = fillColor, fillA = fillA, line = lineColor or false, lineA = lineA })
    return fill, line
  end
  local corner = size == "L" and 16 or 8
  local function make(atlas, layer, col, a)
    local t = f:CreateTexture(nil, layer)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    Panoply.Skin.Round(t, corner, atlas)
    t:SetVertexColor(col[1], col[2], col[3], a or 1)
    return t
  end
  local fill = make(QT.MEDIA .. "Panel" .. (size == "L" and "L" or "S") .. "Fill", "BACKGROUND", fillColor, fillA)
  local line = lineColor and make(QT.MEDIA .. "Panel" .. (size == "L" and "L" or "S") .. "Line", "BORDER", lineColor, lineA) or nil
  return fill, line
end

-- Brass corner caps (same rule as the v3 Skin: by the shortest side; small panels get none here).
local CAP = { L = { size = 64, minSide = 110 }, M = { size = 32, minSide = 64 } }
local CORNERS = { TL = { "TOPLEFT", -1, 1 }, TR = { "TOPRIGHT", 1, 1 }, BL = { "BOTTOMLEFT", -1, -1 }, BR = { "BOTTOMRIGHT", 1, -1 } }
function QT.UpdateCaps(f)
  local S = V3()
  if S and S.UpdateCaps and f.panoplyCaps then return S.UpdateCaps(f) end
  local caps = f.qtCaps
  if not caps then return end
  local m = math.min(f:GetWidth() or 0, f:GetHeight() or 0)
  local size = (m >= CAP.L.minSide and "L") or (m >= CAP.M.minSide and "M") or nil
  for k, t in pairs(caps) do
    if size then
      t:SetTexture(QT.MEDIA .. "Cap" .. size .. k)
      t:SetSize(CAP[size].size, CAP[size].size)
      local c = CORNERS[k]
      t:ClearAllPoints(); t:SetPoint(c[1], f, c[1], c[2] * 2, c[3] * 2)
      t:Show()
    else t:Hide() end
  end
end
function QT.Caps(f)
  local S = V3()
  if S and S.Caps then return S.Caps(f) end
  f.qtCaps = {}
  for k in pairs(CORNERS) do f.qtCaps[k] = f:CreateTexture(nil, "OVERLAY", nil, 7) end
  QT.UpdateCaps(f)
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local function cdb()
  local d = Panoply.cdb or {}
  d.trackerUntracked = d.trackerUntracked or {}
  d.trackerHidden = d.trackerHidden or {}
  d.trackerZoneCollapsed = d.trackerZoneCollapsed or {}
  return d
end
QT.CharState = cdb
local function opt(k) return Panoply.db and Panoply.db[k] end

function QT:IsHidden(questID) return questID and cdb().trackerHidden[questID] and true or false end
function QT:IsTracked(questID) return not cdb().trackerUntracked[questID] end

function QT:Untrack(questID)
  cdb().trackerUntracked[questID] = true
  self:Refresh("untrack")
end
function QT:Track(questID)
  cdb().trackerUntracked[questID] = nil
  self:Refresh("track")
end

-- Hide from map and plan: off the tracker, the plan (Planner candidates) and the drop offer.
function QT:HideQuest(questID, title)
  cdb().trackerHidden[questID] = true
  Panoply:Print(("Hidden from the tracker, map and plan: %s. %s brings it back."):format(title or ("quest " .. questID), Panoply:SettingsPath("action:trackerUnhide") .. " > Unhide all"))
  Panoply:Fire("QUEST_HIDDEN_CHANGED", questID, true)
  self:Refresh("hide")
  if Panoply.Planner and Panoply.Planner.hash and Panoply.Replan then pcall(Panoply.Replan, Panoply, "hidden by you") end
end
function QT:UnhideAll()
  local n = 0
  for id in pairs(cdb().trackerHidden) do n = n + 1 cdb().trackerHidden[id] = nil end
  Panoply:Print(("%d hidden quest%s shown again."):format(n, n == 1 and "" or "s"))
  Panoply:Fire("QUEST_HIDDEN_CHANGED", nil, false)
  self:Refresh("unhide")
  if n > 0 and Panoply.Planner and Panoply.Planner.hash and Panoply.Replan then pcall(Panoply.Replan, Panoply, "hidden by you") end
  return n
end

-- Engine hooks (wrapped here so no shared file changes; see SPEC 23.9).
function QT.InstallPlanHooks()
  local P, D = Panoply.Planner, Panoply.DropQuests
  if P and P.Candidates and not P.qtWrapped then
    local orig = P.Candidates
    P.qtWrapped = true
    P.Candidates = function(self, ...)
      local list = orig(self, ...)
      if type(list) ~= "table" or not Panoply.cdb or not next(cdb().trackerHidden) then return list end
      local out = {}
      for _, info in ipairs(list) do
        if not (info.q and cdb().trackerHidden[info.q.id]) then out[#out + 1] = info end
      end
      return out
    end
  end
  if D and D.Unneeded and not D.qtWrapped then
    local orig = D.Unneeded
    D.qtWrapped = true
    D.Unneeded = function(self, ...)
      local list, why = orig(self, ...)
      if type(list) ~= "table" or not Panoply.cdb then return list, why end
      local out = {}
      for _, e in ipairs(list) do if not cdb().trackerHidden[e.questID] then out[#out + 1] = e end end
      return out, why
    end
  end
  if D and D.SKIP_REASONS then D.SKIP_REASONS["hidden by you"] = true end
end
QT.InstallPlanHooks()

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------
local function playerLevel() return (C.XP()) or 1 end

local function questRecord(id)
  local QD = Panoply.QuestData
  if not QD or not QD.GetQuest then return nil end
  local ok, q = pcall(QD.GetQuest, QD, id)
  return ok and q or nil
end

local function zoneFor(e)
  if e.zone and e.zone ~= "" then return e.zone end
  local q = questRecord(e.questID)
  local QD = Panoply.QuestData
  if q and q.zone and q.zone > 0 and QD.UiMapForArea then
    local ok, m = pcall(QD.UiMapForArea, QD, q.zone)
    local name = ok and m and C.MapName(m)
    if name then return name end
  end
  return "Other"
end

function QT.CurrentZone()
  local z = C.ZoneText and C.ZoneText()
  if z and z ~= "" then return z end
  local m = C.GetPlayerPos()
  return m and C.MapName(m) or nil
end

-- Places for a quest (turn-in when ready, else objective spots), cached per quest + readiness.
QT.spotCache = {}
function QT:Spots(questID, ready)
  local key = questID .. (ready and "r" or "o")
  local c = self.spotCache[key]
  if c then return c end
  local q = questRecord(questID)
  local QD = Panoply.QuestData
  local out = {}
  if q and QD then
    local ok = pcall(function()
      if ready then
        for _, s in ipairs(QD:FinisherSpots(q)) do out[#out + 1] = s end
      else
        for _, a in ipairs(QD:ObjectiveAreas(q)) do
          for i, s in ipairs(a.spots or {}) do if i <= 60 then out[#out + 1] = s end end
        end
        if #out == 0 then for _, s in ipairs(QD:FinisherSpots(q)) do out[#out + 1] = s end end
      end
    end)
    if not ok then out = {} end
  end
  self.spotCache[key] = out
  return out
end
-- Nearest spot: returns spot, distance (yards; nil when the player's position is unknown).
function QT:Nearest(questID, ready, pos)
  local spots = self:Spots(questID, ready)
  if #spots == 0 then return nil end
  local pm, px, py
  if pos then pm, px, py = pos[1], pos[2], pos[3] else pm, px, py = C.GetPlayerPos() end
  if not pm or not Panoply.Nav then return spots[1], nil end
  local best, bd
  for _, s in ipairs(spots) do
    local m, x, y = s.map or s.m, s.x, s.y
    if m and x and y then
      local d = Panoply.Nav.Distance(pm, px, py, m, x, y)
      if d and (not bd or d < bd) then best, bd = s, d end
    end
  end
  return best or spots[1], bd
end

local function tagsFor(e)
  local tags = {}
  local t = C.QuestTag(e.questID)
  if C.IsEliteQuest(e.questID) or t == "elite" then tags[#tags + 1] = "Elite" end
  if t == "dungeon" then tags[#tags + 1] = "Dungeon"
  elseif t == "raid" then tags[#tags + 1] = "Raid"
  elseif t == "pvp" then tags[#tags + 1] = "PvP"
  elseif t == "group" or (e.suggestedGroup or 0) > 1 then
    tags[#tags + 1] = (e.suggestedGroup or 0) > 1 and ("Group " .. e.suggestedGroup) or "Group"
  end
  return tags
end

-- Read the log: QT.entries (every quest), QT.view (groups to draw).
QT.known, QT.knownReady = {}, false
function QT:Collect()
  local log = C.TrackerLog()
  local st = cdb()
  local present = {}
  for _, e in ipairs(log) do present[e.questID] = true end
  -- new quests: auto-track (or leave untracked when the setting is off)
  if self.knownReady then
    for _, e in ipairs(log) do
      if not self.known[e.questID] then
        if opt("trackerAutoTrack") == false then st.trackerUntracked[e.questID] = true else st.trackerUntracked[e.questID] = nil end
        self.spotCache[e.questID .. "r"], self.spotCache[e.questID .. "o"] = nil, nil
      end
    end
    for id in pairs(self.known) do
      if not present[id] then st.trackerUntracked[id] = nil st.trackerHidden[id] = nil end
    end
  end
  if #log > 0 then self.knownReady = true end
  self.known = present
  local timers = C.QuestTimers(log)
  local now = _G.GetTime and GetTime() or 0
  local lvl = playerLevel()
  for _, e in ipairs(log) do
    e.zoneName = zoneFor(e)
    e.objectives = C.GetObjectives(e.questID) or {}
    e.tags = tagsFor(e)
    e.timerEnd = timers[e.questID] and (now + timers[e.questID]) or nil
    e.tracked = not st.trackerUntracked[e.questID]
    e.hidden = st.trackerHidden[e.questID] and true or false
    e.diffKey = Panoply.Difficulty and Panoply.Difficulty.Key(e.level, lvl) or "difficult"
    e.diff = QT.DIFF[e.diffKey] or QT.Color("text")
  end
  self.entries = log
  self.max = C.MaxQuests()
  return log
end

-- Group and sort (SPEC 23.3).
function QT:BuildView(entries)
  local mode = opt("trackerSort") or "zone"
  local cur = QT.CurrentZone()
  local showAll = opt("trackerShowAll")
  local groups, byName = {}, {}
  local pos
  if mode == "distance" then local m, x, y = C.GetPlayerPos() pos = m and { m, x, y } or false end
  for _, e in ipairs(entries) do
    if not e.hidden and (e.tracked or showAll) then
      if mode == "distance" then local _, d = self:Nearest(e.questID, e.isComplete, pos or nil) e.dist = d else e.dist = nil end
      local g = byName[e.zoneName]
      if not g then
        g = { name = e.zoneName, quests = {}, current = (cur ~= nil and e.zoneName == cur) }
        byName[e.zoneName] = g
        groups[#groups + 1] = g
      end
      g.quests[#g.quests + 1] = e
    end
  end
  local function qless(a, b)
    if mode == "level" and a.level ~= b.level then return (a.level or 0) < (b.level or 0) end
    if mode == "distance" and a.dist ~= b.dist then
      if a.dist and b.dist then return a.dist < b.dist end
      return a.dist ~= nil
    end
    return a.logIndex < b.logIndex
  end
  for _, g in ipairs(groups) do
    table.sort(g.quests, qless)
    g.minLevel, g.minDist = math.huge, nil
    for _, e in ipairs(g.quests) do
      g.minLevel = math.min(g.minLevel, e.level or 0)
      if e.dist and (not g.minDist or e.dist < g.minDist) then g.minDist = e.dist end
    end
  end
  table.sort(groups, function(a, b)
    if a.current ~= b.current then return a.current end
    if (a.name == "Other") ~= (b.name == "Other") then return b.name == "Other" end
    if mode == "level" and a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    if mode == "distance" and a.minDist ~= b.minDist then
      if a.minDist and b.minDist then return a.minDist < b.minDist end
      return a.minDist ~= nil
    end
    return a.name < b.name
  end)
  self.view = groups
  return groups
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function tip(owner, title, body)
  owner.qtTip, owner.qtTipBody = title, body
  owner:SetScript("OnEnter", function(self)
    local GT = _G.GameTooltip
    if not GT or not self.qtTip then return end
    GT:SetOwner(self, "ANCHOR_LEFT")
    GT:SetText(self.qtTip, 0.91, 0.81, 0.58, 1, true)
    if self.qtTipBody then GT:AddLine(self.qtTipBody, 0.9, 0.9, 0.87, true) end
    GT:Show()
  end)
  owner:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  owner.panoplyTip = title
end
QT.Tip = tip

local function iconButton(parent, icon, size, tipTitle, tipBody, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetPoint("CENTER", b, "CENTER", 0, 0); t:SetSize(size - 4, size - 4)
  QT.SetIcon(t, icon)
  b.icon = t
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", onClick)
  tip(b, tipTitle, tipBody)
  return b
end

function QT:SavePosition()
  local f = self.frame
  local l, t = f:GetLeft(), f:GetTop()
  if l and t then
    cdb().trackerPos = { "TOPLEFT", "BOTTOMLEFT", math.floor(l + 0.5), math.floor(t + 0.5) }
  end
end
function QT:ApplyPosition()
  local f = self.frame
  local p = cdb().trackerPos
  f:ClearAllPoints()
  if type(p) == "table" and p[3] and p[4] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -210) end
end
function QT:ResetPosition()
  if C.InCombat() then return self:Queue("position") end
  cdb().trackerPos = nil
  cdb().trackerHeight = nil
  if self.frame then self:ApplyPosition() self:Layout() end
end

-- Things that must wait for the end of combat.
QT.pending = {}
function QT:Queue(what)
  self.pending[what] = true
  return false
end
function QT:Locked()
  return C.InCombat() and self.Items and self.Items:AnyShown()
end

function QT:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteQuestTracker", UIParent)
  do
    local saved = tonumber(cdb().trackerWidth)
    if saved then self.WIDTH = math.floor(math.max(self.MIN_W, math.min(self.MAX_W, saved))) end
  end
  f:SetSize(self.WIDTH, self.DEFAULT_H)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  C.SetResizeBounds(f, self.MIN_W, self.MIN_H, self.MAX_W, self.MAX_H)
  f.panoplyBox = true
  f.panoplyQT = self
  self.frame = f
  self.bg, self.trim = QT.Box(f, "L", QT.Color("panel"), opt("trackerBgAlpha") or 0.85, QT.Color("trim"), 1)
  QT.Caps(f)
  f:SetScript("OnSizeChanged", function(fr) QT.UpdateCaps(fr) end)

  -- title bar: drag to move, right-click for the tracker menu
  local h = CreateFrame("Button", nil, f)
  -- 0.6.0: kept clear of the brass corner caps (cap depth + 2 px, the layout checker's rule)
  h:SetPoint("TOPLEFT", f, "TOPLEFT", QT.CAP_CLEAR, -QT.CAP_CLEAR); h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -QT.CAP_CLEAR, -QT.CAP_CLEAR)
  h:SetHeight(self.HEADER - QT.CAP_CLEAR)
  h:RegisterForClicks("RightButtonUp")
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function()
    if opt("trackerLocked") or C.InCombat() then return end
    f:StartMoving()
  end)
  h:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    QT:SavePosition()
    QT:ApplyPosition()
    if QT.Items then QT.Items:Place() end
  end)
  h:SetScript("OnClick", function(self, button) if button == "RightButton" then QT:OpenTrackerMenu(self) end end)
  tip(h, "Quests", "Drag to move. Right-click for sorting and options.")
  self.header = h
  local title = newText(h, "head", 15, QT.Color("heading"))
  title:SetPoint("LEFT", h, "LEFT", self.PAD + 4 - QT.CAP_CLEAR, 0)
  title:SetText("Quests")
  title:SetWordWrap(false)
  self.title = title
  local count = newText(h, "semi", 12, QT.Color("inkSoft"))
  count:SetPoint("LEFT", title, "RIGHT", 8, 0)
  count:SetWordWrap(false)
  self.count = count
  local collapse = iconButton(h, "Minus", 20, "Collapse", "Folds the tracker to this bar.", function() QT:ToggleCollapsed() end)
  collapse:SetPoint("RIGHT", h, "RIGHT", -(self.PAD - 2 - QT.CAP_CLEAR), 0)
  local lock = iconButton(h, "Lock", 20, "Lock", "Stops moving and resizing.", function()
    Panoply:SetOption("trackerLocked", not opt("trackerLocked"))
    QT:StyleButtons()
  end)
  lock:SetPoint("RIGHT", collapse, "LEFT", -2, 0)
  local sort = iconButton(h, "Sort", 20, "Sort", "", function() QT:CycleSort() end)
  sort:SetPoint("RIGHT", lock, "LEFT", -2, 0)
  self.collapseBtn, self.lockBtn, self.sortBtn = collapse, lock, sort

  -- the list
  local sf = Panoply.Skin.ScrollArea(f)
  sf:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD - 2, -self.HEADER)
  sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(self.PAD - 2), self.PAD + 4)
  local wheel = sf:GetScript("OnMouseWheel")
  sf:SetScript("OnMouseWheel", function(s, delta)
    if QT:Locked() then return end
    if wheel then wheel(s, delta) end
    if QT.Items then QT.Items:Place() end
  end)
  -- 0.9.0: the bar can be dragged and has arrows (Skin.ScrollBar); it obeys the same lock as the wheel, and the quest item buttons
  -- follow the list however it was moved
  sf.panoplyCanScroll = function() return not QT:Locked() end
  sf.panoplyOnScroll = function() if QT.Items then QT.Items:Place() end end
  self.scroll = sf

  local grip = Panoply.Skin.ResizeGrip(f, function(ww, hh)
    QT.sizing = nil
    cdb().trackerHeight = math.floor(math.max(QT.MIN_H, math.min(QT.MAX_H, hh or QT.DEFAULT_H)))
    -- Nov 2026: the width too; every row is measured for it again
    QT.WIDTH = math.floor(math.max(QT.MIN_W, math.min(QT.MAX_W, ww or QT.WIDTH)))
    cdb().trackerWidth = QT.WIDTH
    f:SetWidth(QT.WIDTH)
    QT:SavePosition() QT:ApplyPosition()
    QT:Layout()
  end)
  grip:ClearAllPoints()
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -QT.CAP_CLEAR, QT.CAP_CLEAR)
  grip:SetSize(12, 12)
  local down = grip:GetScript("OnMouseDown")
  grip:SetScript("OnMouseDown", function(...)
    if opt("trackerLocked") or C.InCombat() then return end
    QT.sizing = true
    -- size from the frame's current top-left so it grows downwards
    QT:SavePosition() QT:ApplyPosition()
    if down then down(...) end
  end)
  tip(grip, "Size", "Drag to set the tracker's width and the most height it uses.")
  self.grip = grip

  self.zoneRows, self.questRows = {}, {}
  self:ApplyPosition()
  self:StyleButtons()
  return f
end

-- 0.7.4.1 (Skyborne): the line at the top of the tracker where Panoply Suite has no guide (Engine/NoGuide.lua): what it says, a
-- "Record mode" switch and a "Turn guide off here" switch. Returns the height it takes (0 when there is no such area).
function QT:NoGuideStrip()
  local f = self.frame
  if not f then return 0 end
  local NG = Panoply.NoGuide
  local on = NG and not Panoply:PlayAlong() and NG:Active() and not cdb().trackerCollapsed
  local s = self.ngStrip
  if not on then if s then s:Hide() end return 0 end
  if not s then
    s = CreateFrame("Frame", nil, f)
    self.ngStrip = s
    s.text = newText(s, "semi", 12, QT.Color("heading"))
    s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
    local Skin = Panoply.Skin
    s.rec = Skin.Button(s, "Record mode", 100, 22, function() NG:SetRecording(not NG:Recording()) end, "Record mode",
      "Saves every quest you take or hand in here, with who gave it, who takes it, where they stand and where the objectives were done. Kept on this computer only (/panoply recorded shows it).")
    s.off = Skin.Button(s, "Turn guide off here", 130, 22, function() NG:SetGuideOff(not NG:GuideOff()) end, "Turn guide off here",
      "Keeps the guide off in this zone, even once Panoply Suite has quests for it. Remembered for this character. Click again to turn it back on.")
    s.line = s:CreateTexture(nil, "ARTWORK")
    s.line:SetColorTexture(QT.Color("hairline")[1], QT.Color("hairline")[2], QT.Color("hairline")[3], 1)
    s.line:SetHeight(1)
    s.line:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0); s.line:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
  end
  local w = self.WIDTH - 2 * (self.PAD - 2)
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD - 2, -self.HEADER)
  s:SetWidth(w)
  s.text:SetWidth(w - 4)
  s.text:SetText(NG:Text() or "")
  local th = textH(s.text, w - 4)
  local rec, off = NG:Recording(), NG:GuideOff()
  local function state(b, label, v)
    b.label:SetText(label .. ": " .. (v and "on" or "off"))
    b.selected = v and true or false
    b:Paint(v and "sel" or "up")
  end
  state(s.rec, NG.REC_LABEL, rec)
  state(s.off, NG.OFF_LABEL, off)
  s.rec:Show(); s.off:Show()
  local bh = Panoply.Skin.FlowButtons(s, { s.rec, s.off }, 0, -(th + 6), w, 4, 60)
  local h = th + 6 + bh + 6
  s:SetHeight(h)
  s:Show()
  return h
end

function QT:StyleButtons()
  if not self.frame then return end
  local locked = opt("trackerLocked")
  QT.SetIcon(self.lockBtn.icon, locked and "Lock" or "Unlock")
  self.lockBtn.icon:SetAlpha(locked and 1 or 0.5)
  self.lockBtn.qtTip = locked and "Unlock" or "Lock"
  self.lockBtn.qtTipBody = locked and "Lets you move and resize the tracker again." or "Stops moving and resizing."
  local mode = opt("trackerSort") or "zone"
  local name = "Zone"
  for _, s in ipairs(self.SORTS) do if s[1] == mode then name = s[2] end end
  self.sortBtn.qtTipBody = "Now: by " .. name:lower() .. ". Click for the next order (zone, level, distance)."
  local col = cdb().trackerCollapsed
  QT.SetIcon(self.collapseBtn.icon, col and "Plus" or "Minus")
  self.collapseBtn.qtTip = col and "Expand" or "Collapse"
  self.collapseBtn.qtTipBody = col and "Shows the quest list again." or "Folds the tracker to this bar."
  if self.grip then if locked then self.grip:Hide() else self.grip:Show() end end
  local a = opt("trackerBgAlpha") or 0.85
  if self.bg then self.bg:SetAlpha(a) end
end

function QT:CycleSort()
  if self:Locked() then Panoply:Print("Sorting changes after combat.") return self:Queue("layout") end
  local mode = opt("trackerSort") or "zone"
  local nxt = self.SORTS[1][1]
  for i, s in ipairs(self.SORTS) do if s[1] == mode then nxt = self.SORTS[i % #self.SORTS + 1][1] end end
  Panoply:SetOption("trackerSort", nxt)
  self:StyleButtons()
  self:Refresh("sort", true)
end

function QT:ToggleCollapsed()
  if self:Locked() then Panoply:Print("The tracker folds after combat.") self.pending.collapse = true return false end
  local st = cdb()
  st.trackerCollapsed = not st.trackerCollapsed
  self:StyleButtons()
  self:Layout()
  return true
end

function QT:ToggleZone(name)
  if self:Locked() then return self:Queue("layout") end
  local z = cdb().trackerZoneCollapsed
  z[name] = not z[name] or nil
  self:Layout()
end

-------------------------------------------------------------------------------
-- Rows (pooled)
-------------------------------------------------------------------------------
local function rowBase(parent)
  local r = CreateFrame("Button", nil, parent)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = r:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints(r)
  hl:SetTexture("Interface\\Buttons\\WHITE8X8")
  local a = QT.Color("accent")
  hl:SetVertexColor(a[1], a[2], a[3], 0.08)
  hl:Hide()
  r.hl = hl
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    local GT = _G.GameTooltip
    if GT and self.qtTip then
      GT:SetOwner(self, "ANCHOR_LEFT")
      GT:SetText(self.qtTip, 0.91, 0.81, 0.58, 1, true)
      if self.qtTipBody then GT:AddLine(self.qtTipBody, 0.9, 0.9, 0.87, true) end
      GT:Show()
    end
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  return r
end

function QT:ZoneRow(i)
  local r = self.zoneRows[i]
  if r then return r end
  r = rowBase(self.scroll.content)
  r.glyph = r:CreateTexture(nil, "ARTWORK")
  r.glyph:SetSize(12, 12)
  r.glyph:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -4)
  r.text = newText(r, "head", 13, QT.Color("heading"))
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 18, -2)
  r.count = newText(r, "semi", 11, QT.Color("inkSoft"))
  r.count:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -3)
  r.count:SetWordWrap(false)
  r.count:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self) QT:ToggleZone(self.zone) end)
  r.qtTipBody = "Click to fold or unfold this zone."
  self.zoneRows[i] = r
  return r
end

function QT:QuestRow(i)
  local r = self.questRows[i]
  if r then return r end
  r = rowBase(self.scroll.content)
  r.title = newText(r, "semi", 12, QT.Color("text"))
  r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
  r.lines = {}
  -- the item slot: reserves the place of the secure item button and is its look-alike in combat
  local s = CreateFrame("Button", nil, r)
  s:SetSize(self.ITEM, self.ITEM)
  s:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -2)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetAllPoints(s)
  s.icon:Hide()
  s:EnableMouse(false)
  s.panoplyTip = "Quest item"
  s:Hide()
  r.slot = s
  r:SetScript("OnClick", function(self, button) QT:OnQuestClick(self, button) end)
  self.questRows[i] = r
  return r
end

local function rowLine(r, j)
  local fs = r.lines[j]
  if not fs then fs = newText(r, "body", 11, QT.Color("text")) r.lines[j] = fs end
  return fs
end

local function fmtTime(s)
  s = math.max(0, math.floor(s or 0))
  if s >= 3600 then return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60) end
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
QT.FormatTime = fmtTime

-- The lines under a quest: { text, color, indent, kind }
function QT:LinesFor(e)
  local out = {}
  local fsz = opt("trackerFontSize") or 12
  local party = opt("trackerParty") ~= false and Panoply.QuestParty and Panoply.QuestParty.Lines and Panoply.QuestParty
  local function partyLines(j)
    if not party then return end
    local ok, ls = pcall(party.Lines, party, e.questID, j)
    if ok and type(ls) == "table" then
      for _, l in ipairs(ls) do
        if l[5] == "missing" then
          -- 0.7.1: "Name: doesn't have it" steps back: grey and a size smaller than the x/y lines
          out[#out + 1] = { text = tostring(l[1] or ""), color = QT.Color("dim"), indent = 20, kind = "party", missing = true, size = math.max(8, fsz - 3), alpha = 0.8 }
        else
          out[#out + 1] = { text = tostring(l[1] or ""), color = { l[2] or 0.8, l[3] or 0.8, l[4] or 0.8 }, indent = 20, kind = "party", size = fsz - 2 }
        end
      end
    end
  end
  if e.failed then
    out[#out + 1] = { text = "Failed", color = QT.Color("red"), indent = 10, kind = "failed" }
  elseif e.isComplete then
    out[#out + 1] = { text = "Ready to turn in", color = QT.Color("accent"), indent = 10, kind = "ready" }
    partyLines(nil)
  else
    for j, o in ipairs(e.objectives or {}) do
      local txt = o.text
      if not txt or txt == "" then txt = (o.numFulfilled or 0) .. "/" .. (o.numRequired or 1) end
      out[#out + 1] = { text = txt, color = o.finished and QT.Color("dim") or QT.Color("text"), indent = 10, kind = o.finished and "done" or "obj" }
      partyLines(j)
    end
  end
  if e.timerEnd then
    local left = e.timerEnd - (_G.GetTime and GetTime() or 0)
    out[#out + 1] = { text = "Time left " .. fmtTime(left), color = left < 60 and QT.Color("red") or QT.Color("warn"), indent = 10, kind = "timer" }
  end
  return out
end

function QT:TitleText(e)
  local diff = e.diff or QT.Color("text")
  local s = colorHex(diff) .. "[" .. tostring(e.level or "?") .. "]|r " .. tostring(e.title or ("Quest " .. e.questID))
  return s
end
-- 0.6.0: tags (Elite, Dungeon, Raid, PvP, Group N) are a small pill inline after the name,
-- never part of the wrapped title; the pill only drops to its own line when it truly does not fit.
function QT:TagText(e)
  return (e.tags and #e.tags > 0) and table.concat(e.tags, " · ") or nil
end
QT.PILL_PAD, QT.PILL_GAP = 4, 5
local function rowPill(r)
  if r.pill then return r.pill end
  local p = CreateFrame("Frame", nil, r)
  p.fill = QT.Box(p, "S", QT.Color("bgHigh"), 0.9, QT.Color("hairline"), 0.9)
  p.text = newText(p, "label", 9, QT.Color("inkSoft"))
  p.text:SetWordWrap(false)
  p.text:SetJustifyV("MIDDLE")
  p.text:SetPoint("LEFT", p, "LEFT", QT.PILL_PAD, 0)
  p.panoplyGapOK = true
  r.pill = p
  return p
end
QT.RowPill = rowPill

-- 0.7.1: shared quests at a glance: the game's party art and a count after the title (after
-- the tag pill) when one or more party members have the quest; the tooltip lists who and how far.
-- A child of the row (always above it), no highlight texture, no glow; clicks go on to the row.
function QT:PartyInfo(e)
  local P = opt("trackerParty") ~= false and Panoply.QuestParty
  if not (P and P.Who and e and e.questID) then return nil end
  local ok, who = pcall(P.Who, P, e.questID)
  if not ok or type(who) ~= "table" then return nil end
  local n = 0
  for _, w in ipairs(who) do if w.has then n = n + 1 end end
  if n == 0 then return nil end
  return { have = n, who = who }
end
function QT:ShowPartyTip(m)
  local GT, e = _G.GameTooltip, m.e
  if not (GT and e) then return end
  GT:SetOwner(m, "ANCHOR_LEFT")
  local info = self:PartyInfo(e)
  local n = info and info.have or 0
  GT:SetText(n == 1 and "1 party member has this quest" or (n .. " party members have this quest"), 0.91, 0.81, 0.58, 1, true)
  local P = Panoply.QuestParty
  local ok, ls = pcall(P.Lines, P, e.questID, nil)
  for _, l in ipairs(ok and ls or {}) do
    if l[5] == "missing" then local d = QT.Color("dim") GT:AddLine(l[1], d[1], d[2], d[3])
    else GT:AddLine(l[1], l[2], l[3], l[4]) end
  end
  GT:Show()
end
local function rowPartyMark(r)
  if r.partyMark then return r.partyMark end
  local m = CreateFrame("Frame", nil, r)
  m.icon = m:CreateTexture(nil, "ARTWORK")
  m.icon:SetPoint("LEFT", m, "LEFT", 0, 0)
  m.count = newText(m, "label", 9, QT.Color("inkSoft"))
  m.count:SetWordWrap(false)
  m.count:SetJustifyV("MIDDLE")
  m.count:SetPoint("LEFT", m.icon, "RIGHT", 1, 0)
  m:EnableMouse(true)
  m:SetScript("OnEnter", function(self) if r.hl then r.hl:Show() end QT:ShowPartyTip(self) end)
  m:SetScript("OnLeave", function() if r.hl then r.hl:Hide() end if _G.GameTooltip then GameTooltip:Hide() end end)
  m:SetScript("OnMouseUp", function(self, button) if r:GetScript("OnClick") then r:GetScript("OnClick")(r, button) end end)
  m.panoplyGapOK = true
  r.partyMark = m
  return m
end
QT.RowPartyMark = rowPartyMark

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
function QT:Visible()
  if not self:IsOn() then return false end
  local kind = C.InstanceKind()
  if kind == "pvp" and opt("trackerHideBG") ~= false then return false end
  if kind == "arena" and opt("trackerHideBG") ~= false then return false end
  if (kind == "party" or kind == "raid") and opt("trackerHideDungeon") then return false end
  if self.userHidden then return false end
  return true
end

local function fillRow(self, r, e, width, fsz)
  local hasItem = opt("trackerItems") ~= false and e.item ~= nil
  local textW = width - 4 - (hasItem and self.GUTTER or 4)
  QT.SetFont(r.title, "semi", fsz)
  r.title:SetWidth(textW)
  r.title:SetText(self:TitleText(e))
  local th = textH(r.title, textW)
  r.title:SetHeight(th)
  local y = 3 + th + 1
  -- badges after the title: the tag pill, then (0.7.1) the party mark; each goes inline on the
  -- title's last line when it fits there, else onto a line of its own under the title
  local badges = {}
  local tag = self:TagText(e)
  if tag then
    local p = rowPill(r)
    QT.SetFont(p.text, "label", math.max(8, fsz - 4), QT.Color("inkSoft"))
    p.text:SetText(tag)
    local tw = math.ceil((p.text.GetStringWidth and p.text:GetStringWidth()) or 0)
    local tl = math.ceil(textH(p.text))
    p.text:SetSize(tw + 1, tl)
    local pw, ph = tw + 1 + 2 * QT.PILL_PAD, tl + 2
    p:SetSize(pw, ph)
    badges[#badges + 1] = p
  elseif r.pill then r.pill:Hide() end
  local pinfo = self:PartyInfo(e)
  if pinfo then
    local m = rowPartyMark(r)
    local _, tlh = wrapInfo(r.title, textW)
    local s = math.max(10, math.min(fsz, math.floor(tlh or fsz)))   -- never taller than a title line
    local S = Panoply.Skin
    local art = S and S.Resolve and S.Resolve(S.GAME_GLYPHS, "Party")
    QT.SetFont(m.count, "label", math.max(8, fsz - 3), QT.Color("inkSoft"))
    if art then
      m.icon:SetSize(s, s)
      S.SetGlyph(m.icon, "Party")
      if m.icon.SetVertexColor then m.icon:SetVertexColor(1, 1, 1, 1) end
      m.icon:Show()
      m.count:ClearAllPoints()
      m.count:SetPoint("LEFT", m.icon, "RIGHT", 1, 0)
      m.count:SetText(tostring(pinfo.have))
    else
      -- no party art in this client: a plain text tag instead
      m.icon:Hide()
      m.count:ClearAllPoints()
      m.count:SetPoint("LEFT", m, "LEFT", 0, 0)
      m.count:SetText("Party " .. pinfo.have)
    end
    local cw = math.ceil((m.count.GetStringWidth and m.count:GetStringWidth()) or 0)
    m.count:SetSize(cw + 1, math.min(s, math.ceil(textH(m.count))))
    m:SetSize((art and (s + 1) or 0) + cw + 1, s)
    m.panoplyArt = art and (art.path or art.atlas) or nil
    m.e, m.questID, m.have = e, e.questID, pinfo.have
    badges[#badges + 1] = m
  elseif r.partyMark then r.partyMark:Hide() r.partyMark.e = nil end
  if #badges > 0 then
    local n, lh, lastW = wrapInfo(r.title, textW)
    -- with no item button beside the row, the badges may use the row's right margin too
    local room = hasItem and textW or (width - 4 - 1)
    local line = n and { x = math.ceil(lastW) + QT.PILL_GAP, top = 3 + (n - 1) * lh, h = lh, inline = true } or nil
    for _, b in ipairs(badges) do
      local bw, bh = b:GetWidth(), b:GetHeight()
      b:ClearAllPoints()
      if line and line.inline and line.x + bw <= room then
        b:SetPoint("TOPLEFT", r, "TOPLEFT", 4 + line.x, -(line.top + math.max(0, math.floor((line.h - bh) / 2))))
        line.x = line.x + bw + QT.PILL_GAP
      elseif line and not line.inline and line.x + bw <= room then
        -- a second badge on the badges' own line: grow that line if this one is taller
        if bh > line.h then y = y + (bh - line.h) line.h = bh end
        b:SetPoint("TOPLEFT", r, "TOPLEFT", 4 + line.x, -line.top)
        line.x = line.x + bw + QT.PILL_GAP
      else
        b:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -y)
        line = { x = bw + QT.PILL_GAP, top = y, h = bh }
        y = y + bh + 2
      end
      b:Show()
    end
  end
  local lines = self:LinesFor(e)
  r.lineData = lines
  for j, l in ipairs(lines) do
    local fs = rowLine(r, j)
    QT.SetFont(fs, "body", l.size or (fsz - 1), l.color)
    if fs.SetAlpha then fs:SetAlpha(l.alpha or 1) end
    local w = textW - l.indent
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", r, "TOPLEFT", 4 + l.indent, -y)
    fs:SetWidth(w)
    fs:SetText(l.text)
    local h = textH(fs, w)
    fs:SetHeight(h)
    fs.qtKind = l.kind
    fs:Show()
    y = y + h
  end
  for j = #lines + 1, #r.lines do r.lines[j]:SetText("") r.lines[j]:Hide() end
  if hasItem then y = math.max(y, self.ITEM + 4) end
  y = y + 4
  r.e, r.questID = e, e.questID
  r:SetAlpha(e.tracked and 1 or 0.5)
  r.qtTip = e.title
  r.qtTipBody = "Click: open in the quest log.\nShift-click: untrack.\nRight-click: more."
  r.slot.hasItem = hasItem
  if hasItem then r.slot:Show() else r.slot:Hide() end
  r.slot.itemID = hasItem and e.item.id or nil
  return y
end

-- Build every row; returns the content height for a given width.
function QT:LayoutRows(width)
  local fsz = opt("trackerFontSize") or 12
  local zc = cdb().trackerZoneCollapsed
  local zi, qi, y = 0, 0, 0
  self.shownRows = {}
  for _, g in ipairs(self.view or {}) do
    zi = zi + 1
    local z = self:ZoneRow(zi)
    z:ClearAllPoints()
    z:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
    z:SetWidth(width)
    z.zone = g.name
    local folded = zc[g.name] and true or false
    QT.SetIcon(z.glyph, folded and "Plus" or "Minus")
    QT.SetFont(z.text, "head", fsz + 1)
    z.count:SetText(folded and tostring(#g.quests) or "")
    QT.SetFont(z.count, "semi", fsz - 1)
    local cw = folded and (Panoply.Skin.TextWidth(z.count) + 6) or 0
    z.text:SetWidth(width - 20 - cw)
    z.text:SetText(g.name)
    local th = textH(z.text, width - 20 - cw)
    z.text:SetHeight(th)
    z.count:SetHeight(textH(z.count))
    z:SetHeight(th + 6)
    z.qtTip = g.name
    z:Show()
    y = y + th + 6
    if not folded then
      for _, e in ipairs(g.quests) do
        qi = qi + 1
        local r = self:QuestRow(qi)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
        r:SetWidth(width)
        local h = fillRow(self, r, e, width, fsz)
        r:SetHeight(h)
        r:Show()
        self.shownRows[#self.shownRows + 1] = r
        y = y + h
      end
    end
    y = y + 4
  end
  for i = zi + 1, #self.zoneRows do self.zoneRows[i]:Hide() end
  for i = qi + 1, #self.questRows do self.questRows[i]:Hide() self.questRows[i].e = nil self.questRows[i].slot:Hide() end
  return y
end

function QT:Layout()
  local f = self.frame
  if not f then return end
  if self:Locked() then self.pending.layout = true return self:UpdateTexts() end
  if not self:Visible() then
    f:Hide()
    if self.Items then self.Items:Place() end
    self:GameWatch()
    return
  end
  f:Show()
  self:StyleButtons()
  local st = cdb()
  local ngH = self:NoGuideStrip()   -- 0.7.4.1: the "no guide for this area" line sits between the title bar and the list
  self.ngH = ngH
  if self.scroll then
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", self.PAD - 2, -(self.HEADER + ngH))
    self.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(self.PAD - 2), self.PAD + 4)
  end
  local n = self.entries and #self.entries or 0
  self.count:SetText(("%d/%d quests"):format(n, self.max or 20))
  local maxH = st.trackerHeight or self.DEFAULT_H
  -- never taller than the room below the title bar (small screens, big UI scale)
  local top = f:GetTop()
  local screenH = UIParent and UIParent:GetHeight() or 768
  local room = (top and top > 0) and (top - 8) or (screenH - 40)
  maxH = math.max(self.MIN_H, math.min(maxH, room))
  local sf = self.scroll
  if st.trackerCollapsed then
    sf:Hide()
    for _, r in ipairs(self.questRows) do r:Hide() end
    self.shownRows = {}
    f:SetHeight(self.HEADER + QT.CAP_CLEAR)   -- the bar, clear of the bottom caps too
    if self.grip then self.grip:Hide() end
  else
    sf:Show()
    local full = self.WIDTH - 2 * (self.PAD - 2)
    local h = self:LayoutRows(full)
    local view = maxH - self.HEADER - ngH - self.PAD - 4
    if h > view + 0.5 then h = self:LayoutRows(full - 12) end
    if #(self.view or {}) == 0 then h = 0 end
    local frameH = math.max(self.MIN_H, math.min(maxH, self.HEADER + ngH + h + self.PAD + 4))
    if #(self.view or {}) == 0 then frameH = self.HEADER + ngH + 2 + 22 end
    f:SetHeight(frameH)
    -- 0.9.0: the list's own size, as its anchors make it (the bar shows only when the quests are taller than this)
    sf:SetSize(full, math.max(1, frameH - self.HEADER - ngH - self.PAD - 4))
    sf:SetContentHeight(h)
    self:EmptyNote(#(self.view or {}) == 0)
  end
  QT.UpdateCaps(f)
  self.laidOut = true
  if self.Items then self.Items:Place() end
  self:GameWatch()
  self:Timers()
end

function QT:EmptyNote(on)
  if not self.empty then
    self.empty = newText(self.frame, "body", 11, QT.Color("inkSoft"))
  end
  self.empty:SetWidth(self.WIDTH - 2 * (self.PAD + 4))      -- every time: the tracker's width can change (the grip)
  self.empty:ClearAllPoints()
  self.empty:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.PAD + 4, -(self.HEADER + (self.ngH or 0)))
  if on then
    local n = self.entries and #self.entries or 0
    self.empty:SetText(n == 0 and "No quests in your log." or "All quests are untracked or hidden.")
    self.empty:SetHeight(textH(self.empty, self.WIDTH - 2 * (self.PAD + 4)))
    self.empty:Show()
  else self.empty:Hide() end
end

-- In combat with item buttons shown: only text changes, rows stay where they are.
function QT:UpdateTexts()
  local byID = {}
  for _, e in ipairs(self.entries or {}) do byID[e.questID] = e end
  local n = self.entries and #self.entries or 0
  if self.count then self.count:SetText(("%d/%d quests"):format(n, self.max or 20)) end
  for _, r in ipairs(self.shownRows or {}) do
    local e = r.e and byID[r.questID]
    if not e then r:SetAlpha(0.4) self.pending.layout = true
    else
      local lines = self:LinesFor(e)
      if #lines ~= #(r.lineData or {}) then self.pending.layout = true end
      for j, l in ipairs(lines) do
        local fs = r.lines[j]
        if fs and r.lineData[j] then
          fs:SetText(l.text)
          fs:SetTextColor(l.color[1], l.color[2], l.color[3], 1)
        end
      end
    end
  end
end

-- Countdown: one 1 s timer while a timed quest is drawn (text only, safe in combat).
function QT:Timers()
  local any = false
  for _, r in ipairs(self.shownRows or {}) do if r.e and r.e.timerEnd then any = true end end
  if not any or self.timerOn then return end
  self.timerOn = true
  local function tick()
    if not QT.timerOn then return end
    local still = false
    local now = _G.GetTime and GetTime() or 0
    for _, r in ipairs(QT.shownRows or {}) do
      if r.e and r.e.timerEnd and r:IsShown() then
        still = true
        for j, l in ipairs(r.lineData or {}) do
          if l.kind == "timer" and r.lines[j] then
            local left = r.e.timerEnd - now
            r.lines[j]:SetText("Time left " .. fmtTime(left))
            local c = left < 60 and QT.Color("red") or QT.Color("warn")
            r.lines[j]:SetTextColor(c[1], c[2], c[3], 1)
          end
        end
      end
    end
    if still and QT.frame and QT.frame:IsShown() then C.After(1, tick) else QT.timerOn = false end
  end
  C.After(1, tick)
end

-- The game's own quest watch frame, hidden while ours shows (setting).
function QT:GameWatch()
  local w = C.GameQuestWatch()
  if not w then return end
  local want = self:IsOn() and opt("trackerHideBlizzard") ~= false and self.frame and self.frame:IsShown()
  if C.InCombat() then self.pending.watch = true return end
  if want then
    if not self.watchHooked and w.HookScript then
      self.watchHooked = true
      w:HookScript("OnShow", function(fr)
        if QT.hidingWatch and not C.InCombat() then fr:Hide() end
      end)
    end
    self.hidingWatch = true
    if w:IsShown() then w:Hide() end
  elseif self.hidingWatch then
    self.hidingWatch = false
    w:Show()
  end
end

-------------------------------------------------------------------------------
-- Refresh (throttled)
-------------------------------------------------------------------------------
function QT:Refresh(reason, now)
  if not self:IsOn() then return end
  if not now then
    if self.refreshQueued then return end
    self.refreshQueued = true
    C.After(self.THROTTLE, function() QT.refreshQueued = false QT:Refresh(reason, true) end)
    return
  end
  self.refreshes = (self.refreshes or 0) + 1
  self:Build()
  local entries = self:Collect()
  if self.Items then self.Items:Assign(entries) end
  self:BuildView(entries)
  self:Layout()
end

function QT:Flush()
  if C.InCombat() then return end
  local p = self.pending
  self.pending = {}
  if p.collapse then local st = cdb() st.trackerCollapsed = not st.trackerCollapsed end
  if p.position then cdb().trackerPos = nil if self.frame then self:ApplyPosition() end end
  self:Refresh("combat end", true)
end

-------------------------------------------------------------------------------
-- Clicks and menus
-------------------------------------------------------------------------------
function QT:OnQuestClick(row, button)
  local e = row.e
  if not e then return end
  if button == "RightButton" then return self:OpenQuestMenu(row, e) end
  if C.ShiftDown() then
    if e.tracked then self:Untrack(e.questID) else self:Track(e.questID) end
    return
  end
  C.OpenQuestLog(e.questID, e.logIndex)
end

function QT:ShowOnMap(e)
  local spot = self:Nearest(e.questID, e.isComplete)
  if not spot then Panoply:Print("No known place for " .. tostring(e.title) .. ".") return false end
  local m, x, y = spot.map or spot.m, spot.x, spot.y
  local label = (e.isComplete and "Turn in: " or "") .. tostring(e.title)
  local Way = Panoply.Waypoints
  if Way and Panoply.Modules:IsOn("waypoints") and Way.Add then Way:Add(m, x, y, label)
  elseif Panoply.Arrow and Panoply.Arrow.PointAt then Panoply.Arrow:PointAt(m, x, y, label) end
  self.lastMap = { map = m, x = x, y = y, label = label }
  return true
end

function QT:MenuItems(e)
  local items = {
    { label = "Show on map", func = function() QT:ShowOnMap(e) end, tip = "Sets a waypoint at the closest place for this quest." },
    e.tracked and { label = "Untrack", func = function() QT:Untrack(e.questID) end, tip = "Takes it off this list. It stays in your quest log." }
      or { label = "Track", func = function() QT:Track(e.questID) end },
  }
  if C.CanShareQuest(e.questID) then
    items[#items + 1] = { label = "Share with party", func = function() C.ShareQuest(e.questID) end }
  end
  items[#items + 1] = { label = "Abandon", func = function() C.ConfirmAbandon(e.questID, e.title) end, tip = "Asks the game's own \"Abandon quest?\" first." , warn = true }
  items[#items + 1] = { label = "Hide from map and plan", func = function() QT:HideQuest(e.questID, e.title) end, tip = "Stays in your quest log; " .. Panoply:SettingsPath("action:trackerUnhide") .. " > Unhide all brings it back." }
  return items
end

function QT:OpenQuestMenu(owner, e)
  return self.Menu:Open(owner, e.title, self:MenuItems(e))
end

function QT:OpenTrackerMenu(owner)
  local items = {}
  local mode = opt("trackerSort") or "zone"
  for _, s in ipairs(self.SORTS) do
    items[#items + 1] = { label = "Sort by " .. s[2]:lower(), checked = (mode == s[1]), func = function()
      if QT:Locked() then return QT:Queue("layout") end
      Panoply:SetOption("trackerSort", s[1]) QT:StyleButtons() QT:Refresh("sort", true) end }
  end
  items[#items + 1] = { label = "Show untracked quests", checked = opt("trackerShowAll") and true or false, func = function()
    Panoply:SetOption("trackerShowAll", not opt("trackerShowAll")) QT:Refresh("showAll", true) end }
  local hidden = 0
  for _ in pairs(cdb().trackerHidden) do hidden = hidden + 1 end
  if hidden > 0 then items[#items + 1] = { label = ("Unhide all hidden quests (%d)"):format(hidden), func = function() QT:UnhideAll() end } end
  items[#items + 1] = { label = "All settings...", tip = "Opens the Guide's settings, on the quest tracker.", func = function()
    if Panoply.Menu and Panoply.Menu.OpenGear then pcall(Panoply.Menu.OpenGear, Panoply.Menu, "guide", "tracker") end
  end }
  return self.Menu:Open(owner, "Quests", items)
end

-------------------------------------------------------------------------------
-- Module on/off and events
-------------------------------------------------------------------------------
function QT:Enable()
  self.userHidden = nil
  self:Build()
  self:Refresh("enable", true)
end
function QT:Disable()
  if self.frame then
    if C.InCombat() and self.Items and self.Items:AnyShown() then self.pending.disable = true
    else self.frame:Hide() end
  end
  if self.Items then self.Items:Place() end
  self:GameWatch()
end

for _, ev in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                      "QUEST_WATCH_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP",
                      "GROUP_ROSTER_UPDATE" }) do
  QT:On(ev, function(unit)
    if ev == "UNIT_QUEST_LOG_CHANGED" and unit and unit ~= "player" then return end
    if ev == "ZONE_CHANGED_NEW_AREA" or ev == "PLAYER_ENTERING_WORLD" then QT.spotCache = {} end
    QT:Refresh(ev)
  end)
end
QT:On("BAG_UPDATE_DELAYED", function() QT:Refresh("bags") end)
QT:Listen("NOGUIDE_CHANGED", function() QT:Refresh("noguide") end)
QT:On("PLAYER_REGEN_ENABLED", function()
  if QT.pending.disable then QT.pending.disable = nil if QT.frame then QT.frame:Hide() end end
  QT:Flush()
end)
QT:Listen("OPTION_CHANGED", function(key)
  if type(key) == "string" and key:find("^tracker") then
    if key == "trackerFontSize" or key == "trackerOutline" or key == "trackerSort" or key == "trackerItems"
      or key == "trackerShowAll" or key == "trackerParty" or key == "trackerHideBG" or key == "trackerHideDungeon" then
      QT:Refresh(key)
    else
      QT:StyleButtons()
      QT:GameWatch()
    end
  end
end)
-- the other module (Quest icons) can ask for a refresh of party lines
QT:Listen("QUEST_PARTY_CHANGED", function() QT:Refresh("party") end)

-------------------------------------------------------------------------------
-- Settings page rows
-------------------------------------------------------------------------------
QT.options = {
  { type = "check", key = "trackerAutoTrack", label = "Track new quests automatically", tip = "Off: new quests start untracked; right-click the title bar > Show untracked quests to see them." },
  { type = "check", key = "trackerItems", label = "Show quest item buttons", tip = "A button beside each quest with a usable quest item. One click uses it once." },
  { type = "check", key = "trackerParty", label = "Show party progress", tip = "Under each objective, when the Quest icons module shares progress with your group." },
  { type = "choice", key = "trackerSort", label = "Sort quests by", values = { { "zone", "Zone" }, { "level", "Level" }, { "distance", "Distance" } },
    tip = "Your current zone always comes first." },
  { type = "slider", key = "trackerFontSize", label = "Text size", min = 10, max = 16, step = 1, fmt = "%d" },
  { type = "check", key = "trackerOutline", label = "Outline text" },
  { type = "slider", key = "trackerBgAlpha", label = "Background opacity", min = 0.2, max = 1, step = 0.05,
    set = function(v) Panoply:SetOption("trackerBgAlpha", v) QT:StyleButtons() end },
  { type = "check", key = "trackerLocked", label = "Lock position and size" },
  { type = "check", key = "trackerHideBG", label = "Hide in battlegrounds" },
  { type = "check", key = "trackerHideDungeon", label = "Hide in dungeons and raids" },
  { type = "check", key = "trackerHideBlizzard", label = "Hide the game's quest tracker while this one is shown" },
  { type = "check", key = "trackerShowAll", label = "Show untracked quests (dimmed)" },
  { type = "button", label = "Unhide all hidden quests", tip = "Quests you hid from the map and plan come back.", func = function() QT:UnhideAll() end },
  { type = "button", label = "Reset position", func = function() QT:ResetPosition() end },
}
