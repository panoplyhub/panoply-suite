-- Threat bar module (a player request, Nov 2026): a thin bar under the player's mana bar (or under the class
-- power bar when one sits lower) that shows how close the player is to pulling the target off whoever has
-- it, and who that is: the player's pet, a party member or a raid member.
--
-- Reads only. It calls the game's threat reader (UnitDetailedThreatSituation) for "player", "pet" and the
-- party or raid units against "target", on the game's threat events. It never targets, attacks, taunts or
-- casts, uses no secure template, and draws nothing animated. It is idle (the bar is hidden) when it is
-- switched off, when the player is out of combat, with no attackable target, when the game gives no threat
-- reading for the player on that target, when the game hides the numbers (Forever "secret" values), or when the
-- player frame it hangs from is not on screen. A bar that cannot be read is never drawn from old numbers.
--
-- Where it hangs: Threat.FindAnchor() picks, in this order, the lowest visible of the class power bar and the
-- mana bar, else the health bar, else the player frame itself, and anchors the bar's top corners to its bottom
-- corners, so the bar always has the same width as the bar above it.
-- 0.9.7 hotfix (Nov 18 2026): its size (threatScale), height and width (or the bar above's width) are settings, and unlocked
-- (threatLocked off) it shows out of combat with sample values so it can be dragged; the spot is kept per character and Reset puts it
-- back under the mana bar. Size and place never change in combat: what is asked then is put in at PLAYER_REGEN_ENABLED.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Skin = Panoply.Skin

local Threat = Panoply.Modules:Register({
  key = "threat", label = "Threat bar", icon = "Character",
  desc = "A thin bar under your mana bar in combat: how close you are to pulling your target, against your pet and your group.",
  -- 0.9.7 hotfix (Nov 18 2026): the bar's size and place are the player's, like Panoply's other bars. NEW account keys (a profile
  -- holds them): threatLocked, threatScale, threatHeight, threatMatchWidth, threatWidth. The spot it was dragged to is per character
  -- (PanoplySuiteCharDB.threatPos), like the tracker's and the arrow's. With none of them touched the bar is what it was.
  defaults = { threatBar = true, threatLocked = true, threatScale = 1, threatHeight = 14, threatMatchWidth = true, threatWidth = 160 },
  options = {
    { type = "check", key = "threatBar", label = "Show the threat bar under my mana bar",
      tip = "A thin bar under your mana bar in combat: your threat on your target against your pet and group." },
    { type = "check", key = "threatLocked", label = "Lock the threat bar",
      tip = "Off: it shows out of combat with sample values so you can drag it. Lock it again when it is in place." },
    { type = "slider", key = "threatScale", label = "Threat bar size", min = 0.7, max = 2, step = 0.05,
      tip = "Makes the whole bar bigger or smaller, its words too." },
    -- shows the height the bar is drawn at (an old saved 14 shows as 20); showing it never saves it
    { type = "slider", key = "threatHeight", label = "Threat bar height", min = 20, max = 32, step = 1, fmt = "%d",
      get = function() return Panoply.Threat.Settings().height end,
      tip = "How tall the bar is. Its words grow with it." },
    { type = "check", key = "threatMatchWidth", label = "Same width as my mana bar",
      tip = "On: as wide as the bar it hangs under. Off, or once you have dragged it somewhere else: the width below." },
    { type = "slider", key = "threatWidth", label = "Threat bar width", min = 80, max = 400, step = 5, fmt = "%d",
      tip = "How wide the bar is when it does not match your mana bar." },
  },
})
Panoply.Threat = Threat

Threat.HEIGHT = 14          -- the saved standard height (threatHeight); it is drawn no lower than HEIGHT_MIN
Threat.SCALE_MIN, Threat.SCALE_MAX = 0.7, 2
-- 0.9.7 hotfix (lane QFIX): 20, not 14. At 14 the words (11 px, about 17 tall at 1.3x text) spilled out of the bar. A height saved
-- below 20 (the old standard 14 included) is kept as saved and drawn at 20.
Threat.HEIGHT_MIN, Threat.HEIGHT_MAX = 20, 32
Threat.FONT_MIN, Threat.FONT_MAX = 10, 17   -- the words grow with the bar: 10 at height 20, 17 at 32 (Threat.FontSize)
Threat.EDGE = 3             -- the words keep this far from the fill's edge, on whichever side of it they sit
Threat.WIDTH_MIN, Threat.WIDTH_MAX = 80, 400
Threat.WIDTH = 160          -- the standard width when it does not match the bar above
Threat.SAMPLE_PCT = 72      -- the sample shown while the bar is unlocked out of combat
Threat.SAMPLE_WORDS = "Drag to move"   -- shown under the sample bar
Threat.GAP = 2              -- between the bar above and this one
Threat.PAD = 5              -- inside the bar, each side of the text
Threat.WARN = 70            -- % of the pull point: the bar turns amber
Threat.DANGER = 90          -- % of the pull point (or the game says "higher than the tank"): the bar turns orange
Threat.MIN_INTERVAL = 0.1   -- seconds between two reads; events that come faster are folded into one
Threat.MAX_RAID = 40
Threat.TIP_ROWS = 8

-- fill colours by how safe the player is; the words on the bar say the same thing (colour is never the only cue)
Threat.LEVEL_COLOR = { safe = "done", warn = "highlight", danger = "warn", tanking = "loss" }

-------------------------------------------------------------------------------
-- Reading the game (every call guarded; a missing API is an idle bar, not an error)
-------------------------------------------------------------------------------
local function isSecret(v)
  local f = C.G("issecretvalue")
  if type(f) ~= "function" then return false end
  local ok, s = pcall(f, v)
  return (not ok) or (s and true or false)
end

-- first returned value of a guarded game call
local function ask(path, ...)
  local ok, v = C.Call(path, path, ...)
  if not ok then return nil end
  return v
end

local function exists(unit) return ask("UnitExists", unit) and true or false end

local function nameOf(unit)
  local n = ask("UnitName", unit)
  if n == nil or isSecret(n) or type(n) ~= "string" then return nil end
  return n
end

-- Threat of one unit on `mob`: { unit, pct, raw, value, tanking, status }, or nil and why:
--   "api" the game has no threat reader (or it errored), "none" the unit is not on the mob's threat list,
--   "secret" the game hides the numbers.
function Threat.ReadUnit(unit, mob)
  local ok, tanking, status, scaled, raw, value = C.Call("UnitDetailedThreatSituation", "UnitDetailedThreatSituation", unit, mob)
  if not ok then return nil, "api" end
  if scaled == nil and tanking == nil and status == nil then return nil, "none" end
  if isSecret(scaled) or isSecret(tanking) or isSecret(status) then return nil, "secret" end
  scaled = tonumber(scaled)
  if not scaled then return nil, "none" end
  local row = { unit = unit, pct = math.max(0, math.floor(scaled + 0.5)), tanking = tanking and true or false }
  row.status = (not isSecret(status)) and tonumber(status) or nil
  row.raw = (not isSecret(raw)) and tonumber(raw) or nil
  row.value = (not isSecret(value)) and tonumber(value) or nil
  return row
end

-- The units that can hold threat besides the player: the pet, then party or raid members.
function Threat.GroupUnits()
  local out = {}
  if exists("pet") then out[#out + 1] = { unit = "pet", kind = "pet" } end
  local count = tonumber(ask("GetNumGroupMembers")) or 0
  local raid = ask("IsInRaid") and true or false
  local prefix, last = "party", math.min(count, 4)
  if raid then prefix, last = "raid", math.min(count, Threat.MAX_RAID) end
  for i = 1, last do
    local u = prefix .. i
    if exists(u) and not ask("UnitIsUnit", u, "player") then out[#out + 1] = { unit = u, kind = raid and "raid" or "party" } end
  end
  return out
end

local function higher(a, b)
  if a.pct ~= b.pct then return a.pct > b.pct end
  if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
  return (a.name or "") < (b.name or "")
end

-- Why the bar is idle right now, or nil when a read is worth making.
function Threat:IdleReason()
  if not (self.active and Panoply.db and Panoply.db.threatBar ~= false) then return "off" end
  local fn = C.G("UnitAffectingCombat")
  local fighting = (type(fn) == "function" and ask("UnitAffectingCombat", "player")) or C.InCombat()
  if not fighting then return "combat" end
  if ask("UnitIsDeadOrGhost", "player") then return "dead" end
  if not exists("target") then return "target" end
  if ask("UnitIsDead", "target") then return "target" end
  if type(C.G("UnitCanAttack")) == "function" and not ask("UnitCanAttack", "player", "target") then return "target" end
  return nil
end

-- One read of everything: { state = "ok" | "idle", reason, me, others, holder, level }.
function Threat:Snapshot()
  local snap = { state = "idle", others = {} }
  local why = self:IdleReason()
  if why then snap.reason = why return snap end
  if type(C.G("UnitDetailedThreatSituation")) ~= "function" then snap.reason = "api" return snap end
  local me, whyNot = Threat.ReadUnit("player", "target")
  if not me then snap.reason = whyNot return snap end
  me.name, me.kind = "You", "me"
  for _, g in ipairs(Threat.GroupUnits()) do
    local row = Threat.ReadUnit(g.unit, "target")
    if row then
      row.kind, row.name = g.kind, nameOf(g.unit) or (g.kind == "pet" and "Pet" or "?")
      snap.others[#snap.others + 1] = row
    end
  end
  table.sort(snap.others, higher)
  -- who has the target now: the unit the game says is tanking, else the highest of the others
  snap.holder = me.tanking and me or nil
  for _, r in ipairs(snap.others) do if r.tanking then snap.holder = snap.holder or r break end end
  snap.holder = snap.holder or snap.others[1]
  snap.me = me
  snap.level = Threat.Level(me)
  snap.state = "ok"
  snap.targetName = nameOf("target")
  return snap
end

-- How safe the player is: "tanking" (has it), "danger", "warn" or "safe".
function Threat.Level(me)
  if me.tanking or (me.status and me.status >= 2) then return "tanking" end
  if me.pct >= Threat.DANGER or me.status == 1 then return "danger" end
  if me.pct >= Threat.WARN then return "warn" end
  return "safe"
end

-- The two words on the bar: the player's own percentage, and the unit to watch (its name and its percentage apart,
-- so a long name can be cut without losing the number).
function Threat.Labels(snap)
  local me = snap.me
  local left = ("%d%%"):format(me.pct)
  local who
  if me.tanking then
    who = snap.others[1]
    if not who then return left, "Holding", "" end
  else
    who = snap.holder
  end
  if not who then return left, "", "" end
  return left, who.name, (" %d%%"):format(who.pct)
end

-- Mouse-over lines: everyone on the target's threat list, highest first.
function Threat.TooltipLines(snap)
  local rows = { snap.me }
  for _, r in ipairs(snap.others) do rows[#rows + 1] = r end
  table.sort(rows, higher)
  local out = { "Threat on " .. (snap.targetName or "your target") }
  for i, r in ipairs(rows) do
    if i > Threat.TIP_ROWS then break end
    local tag = r.kind == "pet" and " (pet)" or ""
    out[#out + 1] = ("%s%s  %d%%%s"):format(r.name, tag, r.pct, r.tanking and "  has it" or "")
  end
  return out
end

-------------------------------------------------------------------------------
-- Where the bar hangs
-------------------------------------------------------------------------------
local function usable(f) return type(f) == "table" and f.SetPoint ~= nil and f.IsVisible ~= nil end
local function shown(f) return usable(f) and f:IsVisible() and true or false end

local function frameFrom(fnName, path)
  local f = ask(fnName)
  if usable(f) then return f end
  f = C.G(path)
  if usable(f) then return f end
  return nil
end

-- The frames the bar can hang from, tier by tier. The Era player frame has global bars; WoW Forever's
-- redrawn one hands them out through accessor functions and keeps them inside the frame.
function Threat.Candidates()
  local power, health
  local alt = frameFrom("PlayerFrame_GetAlternatePowerBar", "PlayerFrameAlternateManaBar")
  local mana = frameFrom("PlayerFrame_GetManaBar", "PlayerFrameManaBar")
  if not mana then
    mana = C.G("PlayerFrame.manabar") or C.G("PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar")
    if not usable(mana) then mana = nil end
  end
  power = {}
  if alt then power[#power + 1] = { frame = alt, how = "alt" } end
  if mana then power[#power + 1] = { frame = mana, how = "mana" } end
  health = frameFrom("PlayerFrame_GetHealthBar", "PlayerFrameHealthBar")
  if not health then
    health = C.G("PlayerFrame.healthbar")
    if not usable(health) then health = nil end
  end
  local pf = C.G("PlayerFrame")
  return power, health and { frame = health, how = "health" } or nil, usable(pf) and { frame = pf, how = "frame" } or nil
end

local function bottomOf(f)
  if type(f.GetBottom) ~= "function" then return nil end
  local ok, b = pcall(f.GetBottom, f)
  if ok and type(b) == "number" and not isSecret(b) then return b end
  return nil
end

-- The frame to hang under, and which kind it is ("alt", "mana", "health", "frame"); nil when none is on screen.
function Threat.FindAnchor()
  local power, health, frame = Threat.Candidates()
  local seen = {}
  for _, c in ipairs(power) do if shown(c.frame) then seen[#seen + 1] = c end end
  if #seen > 0 then
    local best = seen[1]
    local bb = bottomOf(best.frame)
    for i = 2, #seen do
      local b = bottomOf(seen[i].frame)
      -- the lowest one wins when the client can say where they are; otherwise the order above does
      if b and bb and b < bb then best, bb = seen[i], b end
    end
    return best.frame, best.how
  end
  if health and shown(health.frame) then return health.frame, health.how end
  if frame and shown(frame.frame) then return frame.frame, frame.how end
  return nil
end

-------------------------------------------------------------------------------
-- Size and place (0.9.7 hotfix): the saved values, held to their ranges
-------------------------------------------------------------------------------
local function clamp(v, lo, hi, d)
  v = tonumber(v)
  if not v or v ~= v then return d end
  return math.max(lo, math.min(hi, v))
end

-- { scale, height, width, match, locked, pos }: what the player set, or the standard values.
function Threat.Settings()
  local db, cdb = Panoply.db or {}, Panoply.cdb or {}
  local pos = cdb.threatPos
  if not (type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y)) then pos = nil end
  return {
    scale = clamp(db.threatScale, Threat.SCALE_MIN, Threat.SCALE_MAX, 1),
    height = math.floor(clamp(db.threatHeight, Threat.HEIGHT_MIN, Threat.HEIGHT_MAX, Threat.HEIGHT) + 0.5),
    width = math.floor(clamp(db.threatWidth, Threat.WIDTH_MIN, Threat.WIDTH_MAX, Threat.WIDTH) + 0.5),
    match = db.threatMatchWidth ~= false,
    locked = db.threatLocked ~= false,
    pos = pos,
  }
end

-- The words' size for a bar this tall: the line (size + 1 px, about 1.6 x that tall with the client's larger text) fits inside it.
function Threat.FontSize(height)
  local h = tonumber(height) or Threat.HEIGHT_MIN
  return math.max(Threat.FONT_MIN, math.min(Threat.FONT_MAX, math.floor((h - 2) / 1.6) - 1))
end

-- The bar can be dragged now: it is unlocked and there is no fight.
function Threat:CanMove()
  return not Threat.Settings().locked and not C.InCombat()
end

-------------------------------------------------------------------------------
-- The bar
-------------------------------------------------------------------------------
function Threat:Build()
  if self.bar then return self.bar end
  local bar = Skin.Bar(_G.UIParent, Threat.HEIGHT_MIN)
  if bar.text then bar.text:Hide() end
  if bar.SetFrameStrata then bar:SetFrameStrata("MEDIUM") end
  if bar.SetClampedToScreen then bar:SetClampedToScreen(true) end
  bar:Hide()
  -- one line each, never wrapped; Draw places them beside or on the fill, never across its edge
  bar.left = Skin.Text(bar, Threat.FONT_MIN, Skin.colors.text, "OVERLAY", "semi")
  bar.left:SetPoint("LEFT", bar, "LEFT", Threat.PAD, 0)
  bar.left:SetJustifyH("LEFT")
  bar.right = Skin.Text(bar, Threat.FONT_MIN, Skin.colors.text, "OVERLAY", "semi")
  bar.right:SetPoint("RIGHT", bar, "RIGHT", -Threat.PAD, 0)
  bar.right:SetJustifyH("RIGHT")
  for _, fs in ipairs({ bar.left, bar.right }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  if bar.EnableMouse then bar:EnableMouse(true) end
  bar:SetScript("OnEnter", function(b)
    local snap, tip = Threat.snap, _G.GameTooltip
    if not (snap and tip and tip.SetOwner) then return end
    if snap.state == "sample" then
      tip:SetOwner(b, "ANCHOR_BOTTOM")
      tip:SetText("Threat bar")
      tip:AddLine("Drag to move it. These are sample values: in combat it shows your real threat.", 0.9, 0.9, 0.9, true)
      tip:AddLine("Lock it again in Field Kit, Threat bar.", 0.9, 0.9, 0.9, true)
      tip:Show()
      return
    end
    if snap.state ~= "ok" then return end
    tip:SetOwner(b, "ANCHOR_BOTTOM")
    for i, line in ipairs(Threat.TooltipLines(snap)) do
      if i == 1 then tip:SetText(line) else tip:AddLine(line, 0.9, 0.9, 0.9) end
    end
    tip:Show()
  end)
  bar:SetScript("OnLeave", function() if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end end)
  -- 0.9.7 hotfix: drag to move while unlocked and out of combat; the spot is kept for this character
  if bar.SetMovable then bar:SetMovable(true) end
  if bar.RegisterForDrag then bar:RegisterForDrag("LeftButton") end
  bar:SetScript("OnDragStart", function(b)
    if not Threat:CanMove() then return end
    Threat.moving = true
    if b.StartMoving then b:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function(b)
    if not Threat.moving then return end
    Threat.moving = nil
    if b.StopMovingOrSizing then b:StopMovingOrSizing() end
    Threat:SavePosition()
  end)
  self.bar = bar
  self:ApplyLayout()
  return bar
end

-- Where the bar is now becomes its saved spot (top-left corner, in the bar's own scale, which is saved with it).
function Threat:SavePosition()
  local bar = self.bar
  if not bar then return false end
  if C.InCombat() then self.layoutPending = true return false end
  local l, t = bar:GetLeft(), bar:GetTop()
  if not (l and t) or not Panoply.cdb then return false end
  Panoply.cdb.threatPos = { p = "TOPLEFT", rp = "BOTTOMLEFT", x = math.floor(l + 0.5), y = math.floor(t + 0.5), s = bar:GetScale() or 1 }
  self.anchor, self.how = nil, nil
  self:Place()
  -- 0.9.7 hotfix (lane QFIX): drawn again at once, so the fill and the words follow the new width (the fill kept the old one)
  self:Refresh(true)
  return true
end

-- Back under the mana bar (the standard place). In combat it waits until the fight is over.
function Threat:ResetPosition()
  if C.InCombat() then
    self.resetPending, self.layoutPending = true, true
    return false
  end
  self.resetPending = nil
  if Panoply.cdb then Panoply.cdb.threatPos = nil end
  self.anchor, self.how = nil, nil
  if self.bar then self:Place() self:Refresh(true) end
  return true
end

-- Size, height, width and the spot, from the saved values. Never in combat: then it waits for the end of the fight.
function Threat:ApplyLayout()
  local bar = self.bar
  if not bar then return false end
  if C.InCombat() then self.layoutPending = true return false end
  self.layoutPending = nil
  if self.resetPending then
    self.resetPending = nil
    if Panoply.cdb then Panoply.cdb.threatPos = nil end
  end
  local s = Threat.Settings()
  if bar.SetScale then bar:SetScale(s.scale) end
  bar:SetHeight(s.height)
  bar.pill = s.height - 2
  if bar.bg and bar.bg.SetCorner then bar.bg:SetCorner(s.height / 2) end
  if bar.fill and bar.fill.SetCorner then bar.fill:SetCorner((s.height - 2) / 2) end
  -- the words grow with the bar, so they always fit inside it
  bar.fontBase = Threat.FontSize(s.height)
  self:SetFontSize(bar.fontBase)
  self.anchor, self.how = nil, nil
  self:Place()
  return true
end

-- The words' size on the bar (both labels); set only when it changes.
function Threat:SetFontSize(size)
  local bar = self.bar
  if not bar or bar.fontSize == size then return end
  bar.fontSize = size
  for _, fs in ipairs({ bar.left, bar.right, bar.text }) do if fs then Skin.Font(fs, size, Skin.colors.text, nil, "semi") end end
  -- the line under the bar stays on screen with it: the bar is held to the screen with that line included
  if bar.SetClampRectInsets then bar:SetClampRectInsets(0, 0, 0, -math.ceil(Skin.FontPx(size, "semi") * 1.6 + 2)) end
end

-- Put the bar where it belongs now: its saved spot, else under the bar FindAnchor picks (when one is on screen).
function Threat:Place()
  if Threat.Settings().pos then return self:Hang(_G.UIParent, "moved") end
  local anchor, how = Threat.FindAnchor()
  if anchor then self:Hang(anchor, how) end
end

-- Hang the bar under `anchor` (only when it is a different frame than last time). A bar dragged somewhere sits at its own spot.
function Threat:Hang(anchor, how)
  local bar = self:Build()
  local s = Threat.Settings()
  if s.pos then anchor, how = _G.UIParent, "moved" end
  if self.anchor == anchor and self.how == how then return end
  self.anchor, self.how = anchor, how
  local ok, err = pcall(function()
    bar:ClearAllPoints()
    if s.pos then
      -- the saved offsets are in the scale the bar had then; the same spot on screen is them times saved / now
      local k = (tonumber(s.pos.s) or 1) / s.scale
      bar:SetPoint(s.pos.p or "TOPLEFT", _G.UIParent, s.pos.rp or "BOTTOMLEFT", s.pos.x * k, s.pos.y * k)
      bar:SetWidth(s.width)
    elseif s.match then
      bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -Threat.GAP)
      bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -Threat.GAP)
    else
      bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -Threat.GAP)
      bar:SetWidth(s.width)
    end
  end)
  if not ok then
    self.anchor, self.how, self.error = nil, nil, err
    Panoply:Debug("threat bar anchor", err)
  end
end

-- The bar's width in its own units: the bar above it (seen through both scales) when it matches it, else the width setting.
function Threat:BarWidth()
  local s = Threat.Settings()
  local a = self.anchor
  if self.how ~= "moved" and s.match and a and a.GetWidth then
    local w = a:GetWidth()
    if type(w) == "number" and w > 0 then
      local ae = a.GetEffectiveScale and a:GetEffectiveScale() or 1
      local be = self.bar and self.bar.GetEffectiveScale and self.bar:GetEffectiveScale() or s.scale
      if type(ae) == "number" and type(be) == "number" and ae > 0 and be > 0 then w = w * ae / be end
      return w
    end
  end
  if self.how == "moved" or not s.match then return s.width end
  local bw = self.bar and self.bar.GetWidth and self.bar:GetWidth()
  if type(bw) == "number" and bw > 0 then return bw end
  return 120
end

-- While unlocked out of combat the bar shows sample values, so there is something to drag.
function Threat:SampleWanted(reason)
  if reason == "off" or not self.active then return false end
  if Threat.Settings().locked or C.InCombat() then return false end
  local fn = C.G("UnitAffectingCombat")
  if type(fn) == "function" and ask("UnitAffectingCombat", "player") then return false end
  return true
end

function Threat.SampleSnap()
  local me = { pct = Threat.SAMPLE_PCT, name = "You", kind = "me", tanking = false }
  return { state = "sample", sample = true, me = me, others = {}, level = Threat.Level(me) }
end

function Threat:Idle(reason)
  self.state, self.reason = "idle", reason
  Threat.snap = nil
  if self.bar then
    self.bar:Hide()
    if self.bar.fill then self.bar.fill:Hide() end
  end
end

function Threat:Draw(snap)
  local bar = self:Build()
  local c = Skin.colors[Threat.LEVEL_COLOR[snap.level]] or Skin.colors.text
  -- the bar is as wide as the frame it hangs from, or as wide as the player set it
  local w = self:BarWidth()
  if not w or w <= 0 then w = 120 end
  local p = math.max(0, math.min(1, snap.me.pct / 100))
  bar.panoplyValue, bar.progress = p, p
  bar.fill:SetVertexColor(c[1], c[2], c[3], 1)
  local fw = math.max(bar.pill or 1, (w - 2) * p)
  bar.fill:SetWidth(fw)
  local filled = snap.me.pct > 0
  if filled then bar.fill:Show() else bar.fill:Hide() end
  local left, name, pct
  -- the sample's instruction is a line of its own just under the bar, in full: in the bar beside the sample percentage it did not
  -- fit at the mana bar's width (it was cut to "Drag to m...")
  if snap.sample then left, name, pct = ("%d%%"):format(snap.me.pct), "", ""
  else left, name, pct = Threat.Labels(snap) end
  local cap = bar.text
  if cap then
    if snap.sample then
      cap:ClearAllPoints()
      cap:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", Threat.PAD, -2)
      if cap.SetWordWrap then cap:SetWordWrap(false) end
      cap:SetText(Threat.SAMPLE_WORDS)
      local tc = Skin.colors.text
      cap:SetTextColor(tc[1], tc[2], tc[3], 1)
      if cap.SetShadowColor then cap:SetShadowColor(0, 0, 0, 1) end
      cap:Show()
    else
      cap:SetText("")
      cap:Hide()
    end
  end
  -- 0.9.7 hotfix (lane QFIX): the words never cross the fill's edge. On the fill (bright) they are dark; on the empty track (dark)
  -- they are light with a shadow, so they read on both. edge: where the fill ends, in the bar's units (nil with no fill).
  local PAD, GAP = Threat.PAD, Threat.EDGE + 1
  local edge = filled and (1 + fw) or nil
  local function paint(fs, onFill)
    local tc = onFill and Skin.colors.bgDeep or Skin.colors.text
    fs:SetTextColor(tc[1], tc[2], tc[3], 1)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, onFill and 0 or 1) end
    if fs.SetShadowOffset then if onFill then fs:SetShadowOffset(0, 0) else fs:SetShadowOffset(1, -1) end end
  end
  -- my percentage: at the bar's left end on the fill when it fits there, else just past the fill's edge. On a short, tall bar the
  -- words step down in size (never below FONT_MIN) until they fit on one side.
  bar.left:SetText(left)
  local size = bar.fontBase or Threat.FontSize(Threat.Settings().height)
  local lw, lx, lOnFill
  while true do
    self:SetFontSize(size)
    lw = Skin.TextWidth(bar.left)
    lx, lOnFill = PAD, false
    if edge then
      if PAD + lw <= edge - GAP then lOnFill = true else lx = math.max(PAD, edge + GAP) end
    end
    if lx + lw <= w - PAD or size <= Threat.FONT_MIN then break end
    size = size - 1
  end
  bar.left:ClearAllPoints()
  bar.left:SetPoint("LEFT", bar, "LEFT", lx, 0)
  paint(bar.left, lOnFill)
  -- the one to watch (name and percentage) is a line just under the bar, at its right end: inside the bar beside my percentage it
  -- did not fit at the mana bar's width without crossing the fill's edge, and a line that moved in and out of the bar as the threat
  -- climbed would jump at the worst moment. The percentage is kept whole; the name gives way.
  local shown = ""
  if name ~= "" then
    local room = w - PAD * 2
    local num = pct:gsub("^%s+", "")
    bar.right:SetText(pct)
    local nameRoom = room - (pct ~= "" and Skin.TextWidth(bar.right) or 0)
    if nameRoom > 0 then
      -- a cut name keeps at least 3 letters before its "...", or it goes
      local wasCut = Skin.Ellipsize(bar.right, name, nameRoom)
      local cut = bar.right:GetText() or ""
      if Skin.TextWidth(bar.right) <= nameRoom and (not wasCut or #cut:gsub("[\128-\191]", "") > 3) then shown = cut .. pct end
    end
    if shown == "" and num ~= "" then
      bar.right:SetText(num)
      if Skin.TextWidth(bar.right) <= room then shown = num end
    end
  end
  if shown == "" then
    bar.right:SetText("")
    bar.right:Hide()
  else
    bar.right:SetText(shown)
    bar.right:ClearAllPoints()
    bar.right:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -PAD, -2)
    paint(bar.right, false)
    bar.right:Show()
  end
  bar:Show()
  if snap.sample then self.state, self.reason, Threat.snap = "sample", nil, snap
  else self.state, self.reason, Threat.snap = "ok", nil, snap end
end

-- Read and draw. Reads closer together than MIN_INTERVAL are folded into one that runs when the gap is over.
function Threat:Refresh(now)
  if not self.active then return end
  local t = C.GetTime()
  if not now and self.readAt and t - self.readAt < Threat.MIN_INTERVAL and t >= self.readAt then
    if not self.pending then
      self.pending = true
      C.After(Threat.MIN_INTERVAL, function() self.pending = false self:Refresh(true) end)
    end
    return
  end
  self.readAt = t
  local snap = self:Snapshot()
  if snap.state ~= "ok" then
    if not self:SampleWanted(snap.reason) then self:Idle(snap.reason) return end
    snap = Threat.SampleSnap()
  end
  -- a bar dragged to its own spot does not need the player frame; one under the mana bar does
  local anchor, how = _G.UIParent, "moved"
  if not Threat.Settings().pos then
    anchor, how = Threat.FindAnchor()
    if not anchor then self:Idle("anchor") return end
  end
  self:Hang(anchor, how)
  self:Draw(snap)
end

-- What the settings page and /panoply selftest can show.
function Threat:Report()
  return { active = self.active, state = self.state or "idle", reason = self.reason, anchor = self.how,
    shown = self.bar and self.bar:IsShown() or false }
end

function Threat:Enable()
  self:Build()
  self:Refresh(true)
end

function Threat:Disable()
  self:Idle("off")
  self.anchor, self.how = nil, nil
end

for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE",
  "UNIT_THREAT_SITUATION_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "UNIT_DISPLAYPOWER" }) do
  Threat:On(e, function()
    -- size and place changes made during the fight are put in now that it is over
    if e == "PLAYER_REGEN_ENABLED" and Threat.layoutPending and not C.InCombat() then Threat:ApplyLayout() end
    Threat:Refresh(e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_REGEN_DISABLED" or e == "PLAYER_TARGET_CHANGED")
  end)
end

Panoply.optionHooks.threatBar = function() Threat:Refresh(true) end
-- 0.9.7 hotfix: a new size, height, width or lock is put in at once out of combat, and after the fight in combat
local function relayout() if Threat.active then Threat:ApplyLayout() Threat:Refresh(true) end end
for _, k in ipairs({ "threatLocked", "threatScale", "threatHeight", "threatMatchWidth", "threatWidth" }) do Panoply.optionHooks[k] = relayout end
-- a profile brings its own values (Engine/Profiles.lua sets them without SetOption)
Threat:Listen("PROFILE_APPLIED", relayout)

-------------------------------------------------------------------------------
-- Settings: the switch lives on Field Kit (UI/Misc.lua, section "Threat bar"; 0.9.5 phase 4F, spec 01 5.3: it was a section of the
-- Guide page). The Guide keeps one link to it, beside the other things drawn on screen; a profile holds it like every other setting.
-------------------------------------------------------------------------------
local Cat = Panoply.Catalog
if Cat and Cat.guide and Cat.guide.sections then
  local have, at = false, #Cat.guide.sections + 1
  for i, s in ipairs(Cat.guide.sections) do
    if s.key == "threatlink" then have = true end
    if s.key == "tracker" then at = i + 1 end
  end
  if not have then
    table.insert(Cat.guide.sections, at, { key = "threatlink", title = "Threat bar",
      exists = function() return Panoply.Modules.byKey.threat ~= nil end,
      rows = { { type = "button", id = "action:threatSettings", label = "Threat bar settings: Field Kit",
        tip = "The threat bar's settings are on the Field Kit page. Opens them; Back returns here.",
        func = function() if Panoply.Menu then Panoply.Menu:OpenGear("misc", "threat") end end } } })
    Cat.reg = nil
  end
end
if Panoply.Profiles and Panoply.Profiles.AddKeys then
  Panoply.Profiles:AddKeys({ "threatBar", "threatLocked", "threatScale", "threatHeight", "threatMatchWidth", "threatWidth" })
end
