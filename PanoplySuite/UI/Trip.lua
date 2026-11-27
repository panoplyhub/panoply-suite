-- Panoply Suite trip times (0.6.0 M5, SPEC section 21.6; approved mockups step-fly and trip-time). Own code.
--   * Trip strip under the guide window: the current trip's total and its legs on one line, and the level
--     line under it ("Level 25 in about 47 min at your pace"). Click it for the trip panel.
--   * Trip panel: the total, the numbered legs with their times and notes, walking all the way for
--     comparison, travel left in the plan, and the time to the next level and to the plan's end.
--   * Each upcoming step in the guide gets a short travel estimate ("~4 min") from the step before it.
-- Display only. Colours, fonts and panels come from the skin.
local ADDON, Panoply = ...
local Skin, C = Panoply.Skin, Panoply.Compat
local Trip = {}
Panoply.Trip = Trip
local floor, max, min, ceil, sqrt = math.floor, math.max, math.min, math.ceil, math.sqrt

Trip.ROAD_FACTOR = 1.3      -- straight line to the walk along roads, for the upcoming-step estimates
Trip.PANEL_W = 380
Trip.NEXT_ROWS = 3          -- the next steps listed in the trip panel with their travel estimates

local function opt(key) local db = Panoply.db return not (db and db[key] == false) end
local function dur(s) return Panoply.Route.Duration(s) end
local function place(v) return Panoply.Travel and Panoply.Travel.Place(v) or (v and v.name) or "the next stop" end

Trip.ICON = { walk = "Travel", fly = "Fly", hearth = "Hearth", ship = "Travel", zeppelin = "Travel", tram = "Travel", portal = "Travel" }

-- Short words for one leg (the strip) and the longer line + note (the panel).
function Trip.Short(l)
  local k = l.kind
  if k == "walk" then
    local to = l.to
    if to.kind == "fp" then return ("walk %s to the flight master"):format(dur(l.seconds)) end
    if to.kind == "dock" then return ("walk %s to the %s"):format(dur(l.seconds), to.transport and to.transport[3] == "tram" and "tram" or "dock") end
    return ("walk %s"):format(dur(l.seconds))
  elseif k == "fly" then return ("flight at %s, %s to %s"):format(place(l.from), dur(l.seconds), place(l.to))
  elseif k == "hearth" then return ("hearth %s"):format(dur(l.seconds))
  elseif k == "ship" then return ("boat %s"):format(dur(l.seconds))
  else return ("%s %s"):format(k, dur(l.seconds)) end
end

function Trip.Long(l)
  local k = l.kind
  if l.ps and l.label then return l.label, nil end   -- a leg of PanoplyGuide's plan: in PanoplyGuide's own words
  if k == "walk" then
    local to = l.to
    local where = (to.kind == "fp" and ((to.npcName and to.npcName ~= "") and ("%s (flight master)"):format(to.npcName) or "the flight master"))
      or (to.kind == "dock" and ("the %s at %s"):format(to.transport and to.transport[3] == "tram" and "tram" or "dock", place(to)))
      or place(to)
    local note = l.how == "road" and l.via and #l.via > 0 and ("Along the road via " .. table.concat(l.via, ", ", 1, min(3, #l.via)) .. ".") or nil
    return "Walk to " .. where, note
  elseif k == "fly" then
    local note = l.measured and "Your own time on this flight." or (#(l.via or {}) > 0 and ("Passes " .. table.concat(l.via, ", ") .. ".") or nil)
    if l.overTarget then note = (note and note .. " " or "") .. "The flight passes over the target; you cannot get off on the way, so you walk back." end
    return ("Take the flight at %s to %s"):format(place(l.from), place(l.to)), note
  elseif k == "hearth" then return "Hearthstone to " .. place(l.to), "With the loading screen."
  elseif k == "portal" then return "Portal to " .. place(l.to), nil
  else
    local what = k == "ship" and "boat" or k
    return ("Take the %s to %s"):format(what, place(l.to)), ("Wait about %s (up to %s), ride about %s."):format(dur(l.wait or 0), dur(l.upTo or 0), dur(l.ride or 0))
  end
end

-- 0.9.6.2 launch fix (Nov 18 2026, Northshire to Stormwind City): PanoplyGuide splits one walk into pieces at the gates and passes
-- on the way, and a piece's end has no name of its own, so the route box read "Walk to Stormwind City" three times (1 min 51 s,
-- 3 s, 2 min 3 s). The rows a panel lists: walks in a row that read the same are one row with their times added, and a walk under
-- SHORT_WALK seconds is not listed (unless it is the only row). Display only: the route, its legs and its total are unchanged.
-- text(l) = the words the panel shows for leg l. -> { { leg = l, seconds = s } }
Trip.SHORT_WALK = 15
function Trip.ShownLegs(legs, text)
  local out = {}
  for _, l in ipairs(legs or {}) do
    local last = out[#out]
    if last and l.kind == "walk" and last.leg.kind == "walk" and text(l) == last.text then
      last.seconds = last.seconds + (l.seconds or 0)
    else
      out[#out + 1] = { leg = l, seconds = l.seconds or 0, text = text(l) }
    end
  end
  local kept = {}
  for _, row in ipairs(out) do
    if not (row.leg.kind == "walk" and row.seconds < Trip.SHORT_WALK) then kept[#kept + 1] = row end
  end
  if #kept == 0 and #out > 0 then kept[1] = out[1] end
  return kept
end

-------------------------------------------------------------------------------
-- Estimates for upcoming steps (straight line x road factor at your speed and pace)
-------------------------------------------------------------------------------
local function stepSpot(step)
  if not step then return nil end
  for _, g in ipairs(step.goals or {}) do
    if g.mapID and g.x then return g.mapID, g.x, g.y end
  end
  if step.mapID then return step.mapID, step.x, step.y end
  return nil
end
Trip.StepSpot = stepSpot

-- Seconds of travel from step i-1 to step i (nil when unknown or on another continent).
function Trip:StepEstimate(i)
  local E, R = Panoply.Engine, Panoply.Route
  if not (R and R:Available()) then return nil end
  local am, ax, ay = stepSpot(E.steps[i - 1])
  local bm, bx, by = stepSpot(E.steps[i])
  if not (am and bm) then return nil end
  local ca, wax, way = R:ToWorld(am, ax, ay)
  local cb, wbx, wby = R:ToWorld(bm, bx, by)
  if not (ca and cb) or ca ~= cb then return nil end
  local d = sqrt((wax - wbx) ^ 2 + (way - wby) ^ 2)
  local pace = Panoply.Pace and Panoply.Pace:TravelFactor() or 1
  return d * self.ROAD_FACTOR / (R:GroundSpeed() / pace)
end

-- "~4 min" for an upcoming row; nil when it is not worth a label (under 15 s or unknown).
function Trip:EstimateLabel(i)
  if not opt("tripShown") then return nil end
  local s = self:StepEstimate(i)
  if not s or s < 15 then return nil end
  if s < 60 then return "~" .. floor(s / 5 + 0.5) * 5 .. " s" end
  return "~" .. dur(floor(s / 60 + 0.5) * 60)
end

-- Travel left in the plan from the current step on (the route's own total for the current trip).
function Trip:PlanTravel()
  local E = Panoply.Engine
  local r = Panoply.Route and Panoply.Route.current
  if r and Panoply.Route.Valid and not Panoply.Route:Valid(r) then r = nil end
  local total, n = r and r.total or 0, 0
  for i = E.index + 1, #E.steps do
    local s = self:StepEstimate(i)
    if s then total = total + s n = n + 1 end
  end
  return total, n
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4K (spec 05b section 2.2, spec 06a section 3.3): the trip line. One icon per leg (walk, fly, boat, zeppelin, tram,
-- hearth) with its time, then the total, on ONE line; legs that do not fit fold into "+2". The Guide page's Next step card and the
-- guide window's Trip section both draw it. Same numbers as the strip (the trip to THIS step, never the whole plan).
-------------------------------------------------------------------------------
Trip.LEG_SLOT = { walk = "icon.leg.walk", fly = "icon.leg.fly", hearth = "icon.leg.hearth", ship = "icon.leg.boat", boat = "icon.leg.boat",
                  zeppelin = "icon.leg.zeppelin", tram = "icon.leg.tram", portal = "icon.step.travel" }
Trip.LEG_WORD = { walk = "Walk", fly = "Flight", hearth = "Hearthstone", ship = "Boat", boat = "Boat", zeppelin = "Zeppelin", tram = "Tram",
                  portal = "Portal" }

-- { legs = { { kind, slot, seconds, time, word } }, total = seconds to this step, totalText = "3 min", working = true while the router
-- works } or nil (no trip, or trip times turned off in Field Kit)
function Trip:Legs()
  if not opt("tripShown") then return nil end
  local R = Panoply.Route
  local r = R and R.current
  if r and R.Valid and not R:Valid(r) then r = nil end
  if not r then
    if R and R.working then return { legs = {}, working = true, totalText = Trip.WORKING } end
    return nil
  end
  if not (r.total and r.legs and #r.legs > 0) then return nil end
  local out = {}
  for _, l in ipairs(r.legs) do
    local k = l.kind or "walk"
    -- two walks in a row read as one walk
    local last = out[#out]
    if last and last.kind == "walk" and k == "walk" then
      last.seconds = last.seconds + (l.seconds or 0)
      last.time = dur(last.seconds)
    else
      out[#out + 1] = { kind = k, slot = Trip.LEG_SLOT[k] or "icon.step.travel", seconds = l.seconds or 0, time = dur(l.seconds or 0),
                        word = Trip.LEG_WORD[k] or "Travel", label = Trip.Short(l) }
    end
  end
  local eta = R.StepETA and R:StepETA() or r.total
  return { legs = out, total = eta, totalText = dur(eta) }
end

-- How many legs fit in `width` beside the total: shown, folded (the "+N" count). measure(i) = the width of leg i (icon, time, gap);
-- totalW = the total's width; plusW(n) = the width of "+n".
function Trip.Fit(n, width, measure, totalW, plusW)
  local used = totalW
  for i = 1, n do
    local need = used + measure(i)
    local rest = n - i
    local room = rest > 0 and (need + plusW(rest)) or need
    if room > width then
      -- leg i does not fit with the fold mark: show i-1 and fold the rest
      return i - 1, n - (i - 1)
    end
    used = need
  end
  return n, 0
end

-- The line as a widget: Trip.LineWidget(parent, { size = 14, font = 11 }) -> f; f:Fill(width) draws it and returns its height (0 when
-- there is no trip). f.shown, f.folded and f.text (the whole line in words, for its tooltip and for tests).
function Trip.LineWidget(parent, o)
  o = o or {}
  local Kit = Panoply.Kit
  local size, font = o.size or 14, o.font or 11
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(10, size + 2)
  f.panoplyGapOK = true
  f.icons, f.times = {}, {}
  f.plus = Skin.Text(f, font, Skin.colors.inkSoft)
  f.totalT = Skin.Text(f, font, Skin.colors.text, nil, true)
  f.working = Skin.Text(f, font, Skin.colors.inkSoft)
  if f.EnableMouse then f:EnableMouse(true) end
  f:SetScript("OnEnter", function(self)
    local GT = _G.GameTooltip
    if not (GT and self.text) then return end
    GT:SetOwner(self, "ANCHOR_BOTTOM")
    GT:AddLine("To this step", 1, 1, 1)
    GT:AddLine(self.text, nil, nil, nil, true)
    GT:Show()
  end)
  f:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  local function leg(i)
    if not f.icons[i] then
      local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(size, size)
      f.icons[i] = t
      f.times[i] = Skin.Text(f, font, Skin.colors.ink)
    end
    return f.icons[i], f.times[i]
  end
  function f:Fill(width)
    local data = Trip:Legs()
    for i = 1, #self.icons do self.icons[i]:Hide() self.times[i]:Hide() end
    self.plus:Hide() self.totalT:Hide() self.working:Hide()
    self.shown, self.folded, self.text, self.data = 0, 0, nil, data
    if not data then self:SetHeight(1) self:Hide() return 0 end
    self:Show()
    self:SetWidth(width)
    if data.working then
      self.working:SetText(Trip.WORKING); self.working:SetWidth(width)
      self.working:ClearAllPoints(); self.working:SetPoint("LEFT", self, "LEFT", 0, 0); self.working:Show()
      self.text = Trip.WORKING
      local h = math.max(size, ceil(Skin.TextHeight(self.working, width)))
      self:SetHeight(h)
      return h
    end
    local legs = data.legs
    local gap = Skin.SP.s
    local widths = {}
    for i, l in ipairs(legs) do
      local _, tf = leg(i)
      tf:SetText(l.time)
      widths[i] = size + 3 + ceil(Skin.TextWidth(tf)) + gap
    end
    self.totalT:SetText("Total " .. data.totalText)
    local totalW = ceil(Skin.TextWidth(self.totalT)) + 2
    local function plusW(n) self.plus:SetText("+" .. n) return ceil(Skin.TextWidth(self.plus)) + gap end
    local shown, folded = Trip.Fit(#legs, width, function(i) return widths[i] end, totalW, plusW)
    local x = 0
    local words = {}
    for i, l in ipairs(legs) do
      words[#words + 1] = l.word .. " " .. l.time
      if i <= shown then
        local ic, tf = leg(i)
        Kit.Icon(ic, l.slot, { size = size })
        ic:ClearAllPoints(); ic:SetPoint("LEFT", self, "LEFT", x, 0); ic:Show()
        local tw = ceil(Skin.TextWidth(tf)) + 1
        tf:SetWidth(tw); tf:ClearAllPoints(); tf:SetPoint("LEFT", self, "LEFT", x + size + 3, 0); tf:Show()
        x = x + widths[i]
      end
    end
    if folded > 0 then
      self.plus:SetText("+" .. folded)
      local pw = ceil(Skin.TextWidth(self.plus)) + 1
      self.plus:SetWidth(pw); self.plus:ClearAllPoints(); self.plus:SetPoint("LEFT", self, "LEFT", x, 0); self.plus:Show()
      x = x + pw + gap
    end
    self.totalT:SetWidth(totalW); self.totalT:ClearAllPoints(); self.totalT:SetPoint("LEFT", self, "LEFT", x, 0); self.totalT:Show()
    self.shown, self.folded = shown, folded
    self.text = table.concat(words, " · ") .. ". Total " .. data.totalText .. "."
    local h = math.max(size, ceil(Skin.TextHeight(self.totalT)))
    self:SetHeight(h)
    return h
  end
  return f
end

-- The trip in words: total, legs line, level line (any may be nil). 0.9.5 phase 4K: the strip that showed them is gone; they are the
-- words of the guide window's Trip section tooltip.
-- 0.6.1: the strip is the trip to THIS step's target only ("To this step"), never the old plan's or
-- another step's; the plan-end time stays on its own line. While the router works: a plain note.
Trip.WORKING = "Working out route..."
function Trip:StripTexts()
  local R = Panoply.Route
  local r = R and R.current
  if r and R.Valid and not R:Valid(r) then r = nil end
  local total, legs, level
  if opt("tripShown") and not r and R and R.working then
    total, legs = "To this step", Trip.WORKING
  elseif opt("tripShown") and r and r.total and r.legs and #r.legs > 0 then
    local eta = R.StepETA and R:StepETA() or r.total
    local walkOnly = true
    for _, l in ipairs(r.legs) do if l.kind ~= "walk" then walkOnly = false end end
    total = "To this step: " .. dur(eta) .. (walkOnly and " walk" or "")
    local parts = {}
    for _, l in ipairs(r.legs) do parts[#parts + 1] = Trip.Short(l) end
    legs = table.concat(parts, " · ")
    legs = legs:sub(1, 1):upper() .. legs:sub(2)
  end
  if opt("paceShown") and Panoply.Pace then level = Panoply.Pace:LevelLine() end
  return total, legs, level
end

-- 0.9.5 phase 4K (spec 06a section 3.3): the trip is a docked section of the guide window now (UI/MainFrame.lua draws Trip.LineWidget);
-- the strip under the window is gone. What is left here: the trip details panel follows the window and the step.
function Trip:Refresh()
  local UI = Panoply.UI
  if not (UI and UI.frame) then return end
  if UI.mode ~= "step" or not UI.frame:IsShown() then
    if self.panel then self.panel:Hide() end
    return
  end
  if self.panel and self.panel:IsShown() then self:FillPanel() end
end

-------------------------------------------------------------------------------
-- Trip panel
-------------------------------------------------------------------------------
function Trip:Panel()
  if self.panel then return self.panel end
  local f = CreateFrame("Frame", "PanoplySuiteTripPanel", UIParent)
  f:SetSize(self.PANEL_W, 200)
  if f.SetFrameStrata then f:SetFrameStrata("MEDIUM") end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  Skin.Panel(f, 0.96, true, "M")
  f.title = Skin.Heading(f, 14, "")
  f.sub = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.totalL = Skin.Text(f, 13, Skin.colors.ink, nil, true)
  f.totalV = Skin.Text(f, 18, Skin.colors.goldBright, nil, true)
  f.rule1 = f:CreateTexture(nil, "ARTWORK") f.rule1:SetTexture(Skin.WHITE)
  f.rule2 = f:CreateTexture(nil, "ARTWORK") f.rule2:SetTexture(Skin.WHITE)
  f.other = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.note = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.bar = Skin.Bar(f, 12)
  f.rows = {}
  local close = Skin.IconButton(f, "x", 18, function() f:Hide() end, "Close", "Close the trip details.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
  f.close = close
  f:Hide()
  self.panel = f
  return f
end

local function row(f, i)
  local r = f.rows[i]
  if r then return r end
  r = { icon = f:CreateTexture(nil, "ARTWORK"), left = Skin.Text(f, 12, Skin.colors.ink), right = Skin.Text(f, 12, Skin.colors.text),
        note = Skin.Text(f, 11, Skin.colors.inkSoft) }
  r.icon:SetSize(18, 18)
  if r.right.SetJustifyH then r.right:SetJustifyH("RIGHT") end
  f.rows[i] = r
  return r
end

local function placeRow(f, r, y, x, inner, icon, left, right, color, note)
  if icon then Skin.SetIcon(r.icon, icon) r.icon:ClearAllPoints() r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 1) r.icon:Show() else r.icon:Hide() end
  local rw = 0
  if right then
    r.right:SetText(right)
    local c = color or Skin.colors.text
    r.right:SetTextColor(c[1], c[2], c[3], 1)
    rw = ceil(Skin.TextWidth(r.right)) + 4
    r.right:SetWidth(rw) r.right:ClearAllPoints() r.right:SetPoint("TOPRIGHT", f, "TOPLEFT", x + inner, y) r.right:Show()
  else
    r.right:Hide()
  end
  local lx = x + (icon and 24 or 0)
  local lw = inner - (lx - x) - rw - (right and 10 or 0)
  r.left:SetText(left) r.left:SetWidth(lw)
  r.left:ClearAllPoints() r.left:SetPoint("TOPLEFT", f, "TOPLEFT", lx, y) r.left:Show()
  local h = max(18, Skin.TextHeight(r.left, lw), right and Skin.TextHeight(r.right) or 0)
  r.left:SetHeight(h)
  y = y - h - Skin.SP.xs
  if note then
    r.note:SetText(note) r.note:SetWidth(inner - 24)
    r.note:ClearAllPoints() r.note:SetPoint("TOPLEFT", f, "TOPLEFT", lx, y + 2)
    local nh = Skin.TextHeight(r.note, inner - 24)
    r.note:SetHeight(nh) r.note:Show()
    y = y - nh - Skin.SP.xs
  else
    r.note:Hide()
  end
  return y - Skin.SP.xs
end

function Trip:FillPanel()
  local f = self:Panel()
  local r = Panoply.Route and Panoply.Route.current
  if r and Panoply.Route.Valid and not Panoply.Route:Valid(r) then r = nil end
  local E = Panoply.Engine
  local step = E:Current()
  local SP = Skin.SP
  local x, inner = 16, self.PANEL_W - 32
  local headline = step and Panoply.StepText.Headline(step) or "your next step"
  local dest = step and step.isTravel and Panoply.StepText.Headline(E.steps[E.index] or step) or headline
  dest = tostring(dest or ""):gsub("^Go to ", ""):gsub("^Travel to ", ""):gsub("^Walk to ", "")
  f.title:SetText("Trip to " .. dest)
  f.title:SetWidth(inner - 26) f.title:ClearAllPoints() f.title:SetPoint("TOPLEFT", f, "TOPLEFT", x, -14)
  local y = -14 - Skin.TextHeight(f.title, inner - 26) - SP.xs
  f.sub:SetText(r and ("From %s, the fastest way at your pace."):format(place(r.from)) or (Panoply.Route and Panoply.Route.working and Trip.WORKING) or "No route yet.")
  f.sub:SetWidth(inner) f.sub:ClearAllPoints() f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  local sh = Skin.TextHeight(f.sub, inner) f.sub:SetHeight(sh)
  y = y - sh - SP.s
  local n = 0
  if r then
    f.totalV:SetText(dur(r.total)) if f.totalV.SetJustifyH then f.totalV:SetJustifyH("RIGHT") end
    local tvw = ceil(Skin.TextWidth(f.totalV)) + 4
    f.totalV:SetWidth(tvw) f.totalV:ClearAllPoints() f.totalV:SetPoint("TOPRIGHT", f, "TOPLEFT", x + inner, y + 3) f.totalV:Show()
    f.totalL:SetText("Total trip time") f.totalL:SetWidth(inner - tvw - 10)
    f.totalL:ClearAllPoints() f.totalL:SetPoint("TOPLEFT", f, "TOPLEFT", x, y) f.totalL:Show()
    y = y - max(Skin.TextHeight(f.totalL, inner - tvw - 10), Skin.TextHeight(f.totalV) - 3) - SP.s
    local br = Skin.colors.trailRide or Skin.colors.gold
    f.rule1:SetVertexColor(br[1], br[2], br[3], 0.55) f.rule1:ClearAllPoints() f.rule1:SetPoint("TOPLEFT", f, "TOPLEFT", x, y) f.rule1:SetSize(inner, 1) f.rule1:Show()
    y = y - SP.m
    for i, s in ipairs(Trip.ShownLegs(r.legs, function(l) return (Trip.Long(l)) end)) do
      n = n + 1
      local l = s.leg
      local left, note = Trip.Long(l)
      y = placeRow(f, row(f, n), y, x, inner, Trip.ICON[l.kind] or "Travel", i .. ".  " .. left, dur(s.seconds), nil, note)
    end
    -- the next few steps of the guide, with their estimated travel from the step before
    local first = true
    for i = E.index + 1, math.min(#E.steps, E.index + self.NEXT_ROWS) do
      local lbl = self:EstimateLabel(i)
      if lbl then
        if first then y = y - SP.xs first = false end
        n = n + 1
        y = placeRow(f, row(f, n), y, x, inner, Panoply.UI and Panoply.UI.StepIconName and Panoply.UI.StepIconName(E.steps[i]) or "Travel",
          ("Then step %d: %s"):format(i, Panoply.StepText.Headline(E.steps[i])), lbl, Skin.colors.inkSoft)
      end
    end
    local other = {}
    if r.walk and r.walk > r.total + 1 then other[#other + 1] = ("Walking all the way: about %s."):format(dur(r.walk)) end
    local pt, pn = self:PlanTravel()
    if pn > 0 then other[#other + 1] = ("Travel left in the plan: about %s over %d more step%s (estimate)."):format(dur(pt), pn, pn == 1 and "" or "s") end
    if #other > 0 then
      f.other:SetText(table.concat(other, " ")) f.other:SetWidth(inner)
      f.other:ClearAllPoints() f.other:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
      local oh = Skin.TextHeight(f.other, inner) f.other:SetHeight(oh) f.other:Show()
      y = y - oh - SP.s
    else f.other:Hide() end
  else
    f.totalV:Hide() f.totalL:Hide() f.rule1:Hide() f.other:Hide()
  end
  -- pace
  local P = Panoply.Pace
  local lvl, xp, mx = C.XP()
  local tNext = P and P:TimeToLevel()
  if tNext and opt("paceShown") then
    y = y - SP.xs
    local br = Skin.colors.trailRide or Skin.colors.gold
    f.rule2:SetVertexColor(br[1], br[2], br[3], 0.55) f.rule2:ClearAllPoints() f.rule2:SetPoint("TOPLEFT", f, "TOPLEFT", x, y) f.rule2:SetSize(inner, 1) f.rule2:Show()
    y = y - SP.m
    n = n + 1
    y = placeRow(f, row(f, n), y, x, inner, "Leveling", ("Level %d"):format(lvl + 1), dur(tNext), Skin.colors.goldBright)
    local st = Panoply.Planner and Panoply.Planner.lastStats
    if st and st.goalLevel and st.goalLevel > lvl + 1 then
      local te = P:TimeToLevel(st.goalLevel)
      if te then n = n + 1 y = placeRow(f, row(f, n), y, x, inner, "Leveling", ("Plan end (level %d)"):format(st.goalLevel), dur(te), Skin.colors.goldBright) end
    end
    f.bar:ClearAllPoints() f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 2) f.bar:SetWidth(inner) f.bar.panoplyWidth = inner
    f.bar:SetProgress((mx or 0) > 0 and (xp or 0) / mx or 0) f.bar:Show()
    y = y - 12 - SP.m
    local rate, src = P:XPH()
    f.note:SetText(src == "pace" and ("From your own pace: about %s experience an hour, rested bonus and AFK time left out."):format(Panoply.Pace.Number(rate))
      or "From the plan's estimate until Panoply Suite has seen about 20 minutes of your play.")
    f.note:SetWidth(inner) f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    local nh = Skin.TextHeight(f.note, inner) f.note:SetHeight(nh) f.note:Show()
    y = y - nh
  else
    f.rule2:Hide() f.bar:Hide() f.note:Hide()
  end
  for i = n + 1, #f.rows do local rr = f.rows[i] rr.icon:Hide() rr.left:Hide() rr.right:Hide() rr.note:Hide() end
  f:SetHeight(-y + SP.l)
  f:ClearAllPoints()
  local UI = Panoply.UI
  if UI and UI.frame and f.SetScale and UI.frame.GetScale then f:SetScale(UI.frame:GetScale() or 1) end   -- the details hang off the guide window: same scale
  if UI and UI.frame then
    local left = UI.frame.GetLeft and UI.frame:GetLeft()
    if left and left - 8 - self.PANEL_W < 0 then f:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 8, 0)
    else f:SetPoint("TOPRIGHT", UI.frame, "TOPLEFT", -8, 0) end
  else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

function Trip:TogglePanel(show)
  local f = self:Panel()
  if show == nil then show = not f:IsShown() end
  if show then self:FillPanel() f:Show() else f:Hide() end
end

function Trip:Register()
  local function refresh() if Panoply.UI and Panoply.UI.frame then Panoply.UI:Refresh() end end
  Panoply:Listen("ROUTE_UPDATED", refresh)
  Panoply:Listen("PACE_CHANGED", refresh)
  Panoply:On("PLAYER_XP_UPDATE", refresh)
end
for _, k in ipairs({ "tripShown", "paceShown", "paceSource" }) do
  Panoply.optionHooks[k] = function() if Panoply.UI and Panoply.UI.frame then Panoply.UI:Refresh() end end
end
