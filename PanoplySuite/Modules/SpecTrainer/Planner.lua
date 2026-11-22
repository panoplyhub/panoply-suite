-- Spec & Trainer: the talent planner (SPEC 22.4). It plans, checks and shares talent orders. It never learns a talent; you click
-- talents in the game's talent window yourself. 0.9.5 phase 4H (docs/specs/page-redesigns-03-class.md section 4): it is the Class
-- page's Talents tab, the only talent UI. The window, the plan tabs, "Use this plan", Save and the "*" are gone: the plan is chosen
-- in the page's header and every edit is kept as it is made (Modules/SpecTrainer/PlanModel.lua).
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C, Skin = Panoply.Compat, Panoply.Skin
local U = ST.UI
local MAX_W, MAX_H = 1000, 600
ST.PLANNER_MIN_W, ST.PLANNER_MIN_H = 860, 520      -- the smallest the window is dragged to: the three trees and the list still fit

local function copyPlan(p)
  local pts = {}
  for i, v in ipairs(p.points or {}) do pts[i] = v end
  return { key = p.key, name = p.name, class = p.class, points = pts, from = p.from, source = p.source,
           ready = p.source ~= "own" or nil }
end

-------------------------------------------------------------------------------
-- Editing (no frames needed: the tests drive these directly)
-------------------------------------------------------------------------------
-- Select a plan to show and edit: an own plan, a ready-made plan (edited as a copy) or nil (the
-- tracked plan, else the class default).
function ST:EditPlan(key)
  local p = key and self:Find(key) or self:Tracked() or self:DefaultPlan()
  if not p then p = self:NewPlan("My plan") end
  self.edit = copyPlan(p)
  self.showLevel = math.max(self.FIRST_LEVEL - 1, math.min(self.LAST_LEVEL, (self:Player().level or 1)))
  if self.showLevel < self.FIRST_LEVEL then self.showLevel = self.FIRST_LEVEL - 1 + #self.edit.points end
  self.plannerMsg = nil
  return self.edit
end

function ST:Say(msg, bad)
  self.plannerMsg = msg and { text = msg, bad = bad } or nil
end

-- Left-click: add the next point to this talent (at the end of the plan).
function ST:AddPoint(id)
  local e = self.edit
  if not e then return nil end
  local T = self:Trees(e.class)
  local tal = T.byId[id]
  if #e.points >= self.POINTS then self:Say("The plan is full: 51 points, levels 10 to 60.", true) return nil end
  local ranks, spent = self:RanksAt(e.class, e.points)
  local ok, err = self:CanAdd(T, ranks, spent, tal)
  if not ok then self:Say(err, true) return nil end
  e.points[#e.points + 1] = id
  e.dirty = true
  self.showLevel = self.FIRST_LEVEL - 1 + #e.points
  self:Say(("Level %d: %s %d/%d."):format(self.showLevel, tal.name, ranks[id] and ranks[id] + 1 or 1, tal.ranks))
  return true
end

-- Right-click: take this talent's last point back, if nothing later needs it.
function ST:RemovePoint(id)
  local e = self.edit
  if not e then return nil end
  local T = self:Trees(e.class)
  local at
  for i = #e.points, 1, -1 do if e.points[i] == id then at = i break end end
  if not at then self:Say(T.byId[id].name .. " has no points in this plan.", true) return nil end
  local test = {}
  for i, v in ipairs(e.points) do if i ~= at then test[#test + 1] = v end end
  local ok, err = self:Check(e.class, test)
  if not ok then
    self:Say(("Other points need this one (%s) Take those back first."):format(err), true)
    return nil
  end
  e.points = test
  e.dirty = true
  self.showLevel = math.min(self.showLevel or 60, self.FIRST_LEVEL - 1 + #e.points)
  self:Say(T.byId[id].name .. ": one point taken back.")
  return true
end

-- An empty plan to fill in. 0.9.5 phase 4H: there is no save step, so it is a plan of your own at once, followed (ST:NewEmptyPlan,
-- PlanModel.lua; the Class page's plan ... menu, New plan).
function ST:StartNewPlan()
  self:NewEmptyPlan()
  if self.planner and self.planner:IsShown() then self:LayoutPlanner() end
  return self.edit
end

function ST:ResetEdit()
  if not self.edit then return end
  self.edit.points = {}
  self.edit.dirty = true
  self.showLevel = self.FIRST_LEVEL - 1
  self:Say("Every point taken out. Click talents to start again.")
end

-- Save: a ready-made plan is saved as your own copy; the ready-made one stays as shipped.
function ST:SaveEdit()
  local e = self.edit
  if not e then return nil end
  local plan
  if e.ready or not e.key then
    plan = { name = e.name, class = e.class, points = e.points, from = e.ready and e.key or e.from, source = "own" }
    if e.ready then plan.key = "my-" .. e.key end
  else
    plan = { key = e.key, name = e.name, class = e.class, points = e.points, from = e.from, source = "own" }
  end
  local pts = {}
  for i, v in ipairs(e.points) do pts[i] = v end
  plan.points = pts
  plan = self:SavePlan(plan)
  -- Nov 2026: a saved plan is brought in step with the talents the character really has
  local state, cmp = self:SyncPlan(plan)
  self.edit = copyPlan(plan)
  local said = ("Saved \"%s\" for this character (%d of 51 points)."):format(plan.name, #plan.points)
  if state == "reordered" then
    said = said .. " Its order now starts from the talents you have."
  elseif state == "differs" then
    said = said .. " " .. (self:SyncLine(plan, cmp)) .. " Press Match my talents to start the plan from them."
  end
  self:Say(said, state == "differs")
  return plan
end

-- "Match my talents": the plan in the window now starts from the talents the character really has (Save keeps it).
function ST:MatchEdit()
  local e = self.edit
  if not e then return nil end
  self.plannerLive = nil
  local cmp = self:Compare(e)
  if not cmp then self:Say("Panoply Suite cannot read your talents right now.", true) return nil end
  if cmp.inStep then self:Say("This plan already starts from the talents you have.") return true end
  local pts, dropped = self:FitToTalents(e)
  if not pts then self:Say("Your talents do not fit Panoply Suite's talent data, so the plan is left as it is.", true) return nil end
  e.points = pts
  e.dirty = true
  self.showLevel = math.max(self.FIRST_LEVEL - 1, math.min(self.FIRST_LEVEL - 1 + #pts, self.FIRST_LEVEL - 1 + cmp.total))
  self:Say(("The plan now starts from your %d talent %s.%s Save to keep it."):format(cmp.total, cmp.total == 1 and "point" or "points",
    (dropped or 0) > 0 and (" The last %d %s of the plan no longer fit and were left off."):format(dropped, dropped == 1 and "point" or "points") or ""))
  return true
end

function ST:UseEdit()
  local e = self.edit
  if not e then return nil end
  local key
  if e.ready and not e.dirty then key = e.key
  else key = self:SaveEdit().key end
  local p = self:Track(key)
  self.edit = copyPlan(p)
  self:Say(("Following \"%s\": talent hints and the trainer groups use it."):format(p.name))
  return p
end

-------------------------------------------------------------------------------
-- The Talents tab (0.7.4.1 layout, our approved mockup A, kept): the level slider on top, the "Next point" card, three 4x7 tree
-- grids, the "Level by level" timeline and the footer. The widgets are made once; LayoutPlanner measures the text, sizes the talent
-- tiles to the room there is and refreshes them.
-------------------------------------------------------------------------------
local PAD, TL_W, COL_GAP, SEC_GAP = 14, 250, 6, 8
local Kit = Panoply.Kit
local TILE_MAX, TILE_MIN = 36, 24
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local DOT, EN_DASH = "\194\183", "\226\128\147"
-- how an unpicked talent looks: brightness and saturation of its icon (about 80% and 60%); one that
-- cannot be taken yet at the shown level is a little further back
local LOOK_PICKED, LOOK_OPEN, LOCKED = { 1, 1 }, { 0.80, 0.60 }, { 0.68, 0.40 }
ST.TALENT_LOOK = { picked = LOOK_PICKED, open = LOOK_OPEN, locked = LOCKED }

local function tint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end
local function colorText(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end
local function put(obj, parent, x, dn, w, h)
  obj:ClearAllPoints(); obj:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -dn)
  if w then obj:SetWidth(w) end
  if h then obj:SetHeight(h) end
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- the game's icon for a talent: the game's own talent API for the player's class, else the icon id in
-- Data/TalentData.lua, else the game's question mark (never a blank)
-- the icon a tile already holds (one lookup per talent when a class is bound, not one per refresh)
function ST:HeldIcon(tal, class)
  local b = self.cells and self.cells[tal.id]
  return (b and b.panoplyIconFile) or self:TalentIcon(tal, class)
end

function ST:TalentIcon(tal, class)
  local live = (class == nil or class == self:ClassFile()) and self:LiveTalent(tal) or nil
  -- (0.9.7 hotfix: the game's own "?" for a talent is not an answer; our data's picture is used then)
  local I = Panoply.Icons
  local ic = live and live.icon
  if I.IsUnknown(ic) then ic = tal.icon end
  if I.IsUnknown(ic) then ic = ICON_UNKNOWN end
  return ic
end

-- A rounded icon tile on any frame: a dark fill, a two-pixel rounded border and the icon. SetBorder colours the
-- border, SetLook sets the icon's brightness and saturation.
local function tileArt(f)
  local fill, line = Skin.Box(f, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine })
  local ring = f:CreateTexture(nil, "BORDER")
  ring:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  Skin.Round(ring, 5, Skin.BOX.S.line)
  tint(ring, Skin.colors.slotLine)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.panoplyFill, f.panoplyLine, f.panoplyRing, f.panoplyIcon = fill, line, ring, icon
  function f:SetBorder(c) tint(line, c); tint(ring, c); self.border = c end
  function f:SetLook(bright, sat)
    icon:SetVertexColor(bright, bright, bright, 1)
    -- Texture:SetDesaturation takes any amount; where a client lacks it the brightness alone dims the icon
    if icon.SetDesaturation then icon:SetDesaturation(1 - sat) else icon:SetVertexColor(bright * 0.9, bright * 0.9, bright * 0.9, 1) end
    self.bright, self.sat = bright, sat
  end
  f:SetLook(1, 1)
  return f
end

local function makeTile(P, t)
  local b = CreateFrame("Button", nil, t.card)
  b:SetSize(TILE_MAX, TILE_MAX)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  tileArt(b)
  local pill = CreateFrame("Frame", nil, b)
  local bg = pill:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(pill)
  Skin.Round(bg, 5, Skin.TEX.RFill); bg:SetVertexColor(10 / 255, 14 / 255, 20 / 255, 0.92)
  local fs = U.Text(pill, 9, Skin.colors.done, "semi")
  fs:SetPoint("CENTER", pill, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
  pill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.panoplyPill, b.panoplyPillText = pill, fs
  b:SetScript("OnClick", function(self, button)
    local tal = self.panoplyTalent
    if not tal then return end
    -- 0.9.5 phase 4H: no save step: the edit is kept at once (a ready-made plan becomes your own copy, with Undo)
    if button == "RightButton" then ST:RemoveAndKeep(tal.id) else ST:AddAndKeep(tal.id) end
    ST:AfterEdit()
  end)
  b:SetScript("OnEnter", function(self) ST:ShowTalentTip(self) end)
  b:SetScript("OnLeave", function() ST:HideTalentTip() end)
  return b
end

-- an empty slot of the grid: a faint fill and a dashed outline
local function makeGhost(t)
  local g = CreateFrame("Frame", nil, t.card)
  g:SetSize(TILE_MAX, TILE_MAX)
  local fill = g:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(g)
  Skin.Round(fill, 5, Skin.TEX.RFill); fill:SetVertexColor(14 / 255, 20 / 255, 28 / 255, 0.45)
  g.dashes = {}
  return g
end
local function layoutGhost(g, size)
  local n = clamp(math.floor((size + 3) / 7), 3, 5)
  local k, L = 0, 4
  local function dash(x, y, w, h)
    k = k + 1
    local d = g.dashes[k]
    if not d then d = g:CreateTexture(nil, "BORDER"); Skin.Solid(d, Skin.colors.hairline, 1); g.dashes[k] = d end
    d:ClearAllPoints(); d:SetPoint("TOPLEFT", g, "TOPLEFT", x, -y); d:SetSize(w, h); d:Show()
  end
  for i = 0, n - 1 do
    local p = math.floor(i * (size - L) / (n - 1) + 0.5)
    dash(p, 0, L, 1); dash(p, size - 1, L, 1); dash(0, p, 1, L); dash(size - 1, p, 1, L)
  end
  for i = k + 1, #g.dashes do g.dashes[i]:Hide() end
end

-- A prerequisite arrow: up to two lines and a four-strip arrowhead, plain rectangles (no glow).
local function makeArrow(t)
  local a = { parts = {} }
  for i = 1, 6 do
    local x = t.card:CreateTexture(nil, "ARTWORK")
    Skin.Solid(x, Skin.colors.slotLine, 1); x:Hide()
    a.parts[i] = x
  end
  return a
end
local function arrowRects(a, G, tree)
  local pre, tal = a.from, a.to
  local function box(t) return G.gx + t.col * G.px, G.gy + t.tier * G.py end
  local px0, py0 = box(pre)
  local tx0, ty0 = box(tal)
  local S = G.tile
  local out = {}
  local right = tal.col >= pre.col
  local function down(x, y)   -- an arrowhead pointing down, its tip at (x, y)
    for j = 0, 3 do local w = 8 - 2 * j; out[#out + 1] = { x - w / 2, y - 4 + j, w, 1 } end
  end
  local function across(x, y)   -- an arrowhead pointing right (or left, for a talent on the left), its tip at (x, y)
    for j = 0, 3 do
      local w = 8 - 2 * j
      out[#out + 1] = { right and (x - 4 + j) or (x + 3 - j), y - w / 2, 1, w }
    end
  end
  -- a horizontal run from the edge of one tile to the edge of the other, at height cy
  local function run(fromX, toX, cy) -- fromX: the start (next to a tile), toX: the far end where the head begins
    local l, r = math.min(fromX, toX), math.max(fromX, toX)
    return { l, cy - 1, r - l, 2 }
  end
  if tal.col == pre.col then
    local cx = px0 + S / 2
    out[1] = { cx - 1, py0 + S + 1, 2, math.max(0, ty0 - 5 - (py0 + S + 1)) }
    down(cx, ty0 - 1)
  elseif tal.tier == pre.tier then
    local cy = py0 + S / 2
    if right then out[1] = run(px0 + S + 1, tx0 - 5, cy); across(tx0 - 1, cy)
    else out[1] = run(px0 - 1, tx0 + S + 5, cy); across(tx0 + S + 1, cy) end
  else
    local sideFree = not tree.pos[pre.tier * 4 + tal.col + 1]       -- the slot beside the prerequisite, in the target's column, is empty
    if sideFree then
      local cyP, cxT = py0 + S / 2, tx0 + S / 2
      if right then out[1] = run(px0 + S + 1, cxT + 1, cyP) else out[1] = run(px0 - 1, cxT - 1, cyP) end
      out[2] = { cxT - 1, cyP, 2, math.max(0, ty0 - 5 - cyP) }
      down(cxT, ty0 - 1)
    else
      local cxP, cyT = px0 + S / 2, ty0 + S / 2
      out[1] = { cxP - 1, py0 + S + 1, 2, cyT - (py0 + S + 1) + 1 }
      if right then out[2] = run(cxP, tx0 - 5, cyT); across(tx0 - 1, cyT)
      else out[2] = run(cxP, tx0 + S + 5, cyT); across(tx0 + S + 1, cyT) end
    end
  end
  return out
end
ST.ArrowRects = arrowRects

local function placeGeometry(t, G)
  t.G = G
  for k = 1, 28 do
    local c = t.cells[k]
    if c then
      local tier, col = math.floor((k - 1) / 4), (k - 1) % 4
      local x, y = G.gx + col * G.px, G.gy + tier * G.py
      local o = c.btn or c.ghost
      if o then
        o:ClearAllPoints(); o:SetPoint("TOPLEFT", t.card, "TOPLEFT", x, -y); o:SetSize(G.tile, G.tile)
        if c.ghost then layoutGhost(c.ghost, G.tile) end
      end
    end
  end
  for i = 1, t.arrowN do
    local a = t.arrows[i]
    local rects = arrowRects(a, G, t)
    for j, x in ipairs(a.parts) do
      local r = rects[j]
      if r and r[3] > 0 and r[4] > 0 then
        x:ClearAllPoints(); x:SetPoint("TOPLEFT", t.card, "TOPLEFT", r[1], -r[2]); x:SetSize(r[3], r[4]); x:Show()
      else x:Hide() end
    end
  end
end

-- the three tree columns' widgets for a class: tiles for talents, ghosts for empty slots, arrows
local function bindClass(P, T, class)
  if P.class == class then return end
  P.class = class
  ST.cells = {}
  for ti = 1, 3 do
    local t, tab = P.trees[ti], T.tabs[ti]
    for _, c in pairs(t.cells) do
      if c.btn then c.btn:Hide(); c.btn.panoplyTalent = nil end
      if c.ghost then c.ghost:Hide() end
      c.tal = nil
    end
    t.pos = {}
    for _, tal in ipairs(tab and tab.talents or {}) do t.pos[tal.tier * 4 + tal.col + 1] = tal end
    for k = 1, 28 do
      local tal = t.pos[k]
      local c = t.cells[k]
      if not c then c = {}; t.cells[k] = c end
      if tal then
        c.tal = tal
        c.btn = c.btn or makeTile(P, t)
        c.btn.panoplyTalent = tal
        c.btn.panoplyIconFile = ST:TalentIcon(tal, class)
        c.btn.panoplyIcon:SetTexture(c.btn.panoplyIconFile)
        c.btn:Show()
        ST.cells[tal.id] = c.btn
      else
        c.ghost = c.ghost or makeGhost(t)
        c.ghost:Show()
      end
    end
    for i = 1, #t.arrows do for _, x in ipairs(t.arrows[i].parts) do x:Hide() end end
    t.arrowN = 0
    for _, tal in ipairs(tab and tab.talents or {}) do
      local pre = tal.prereq and T.byId[tal.prereq]
      if pre and pre.tab == tal.tab then
        t.arrowN = t.arrowN + 1
        local a = t.arrows[t.arrowN] or makeArrow(t)
        t.arrows[t.arrowN] = a
        a.from, a.to = pre, tal
      end
    end
    t.geomKey = nil
  end
end

local function buildSkeleton(f)
  local P = { f = f, chips = {}, trees = {}, tl = { rows = {}, heads = {} } }
  P.lv = U.Text(f, 12, Skin.colors.ink, "semi"); P.lv:SetJustifyH("RIGHT")
  P.slider = Skin.Slider(f, "Show level", ST.FIRST_LEVEL, 60, 1, function() return math.max(ST.FIRST_LEVEL, ST.showLevel or ST.FIRST_LEVEL) end,
    function(v) if not ST.sliderQuiet and v ~= ST.showLevel then ST.showLevel = v; ST:LayoutPlanner() end end,
    "Move it to see your plan at an earlier level.", "%d")
  P.slider.label:Hide()
  -- the Next point card
  local nx = { card = Skin.Card(f) }
  nx.label = Skin.Heading(nx.card, 10, "Next point"); colorText(nx.label, Skin.colors.accent)
  nx.icon = CreateFrame("Frame", nil, nx.card); nx.icon:SetSize(34, 34); tileArt(nx.icon)
  nx.name = U.Text(nx.card, 13, Skin.colors.text, "semi")
  nx.why = U.Text(nx.card, 11, Skin.colors.inkSoft)
  nx.due = U.Text(nx.card, 12, Skin.colors.heading, "semi"); nx.due:SetJustifyH("RIGHT")
  P.next = nx
  -- "2 points don't match your plan" (spec 03 section 4) and Match my talents beside it
  P.mismatch = U.Text(f, 12, Skin.colors.warn, "semi")
  P.mismatch:Hide()
  P.match = Skin.Button(f, "Match my talents", 120, 24, function() ST:MatchAndKeep(); ST:AfterEdit() end, "Match my talents",
    "Changes this plan so it starts from the talents your character has now. Points that no longer fit in 51 are left off the end. Nothing is spent or changed in the game.")
  P.match:Hide()
  -- Narrow: one tree at a time, with a switcher that says the points in each
  P.treeTabs = {}
  for i = 1, 3 do
    local b = Skin.Tab(f, "", 100, function() ST.treeShown = i; ST:LayoutPlanner() end, "Tree", "Shows this tree.")
    b.panoplyPicker, b.panoplyTree = true, i
    b:Hide()
    P.treeTabs[i] = b
  end
  -- the three trees
  for i = 1, 3 do
    local t = { card = Skin.Card(f), cells = {}, arrows = {}, arrowN = 0 }
    t.name = Skin.Heading(t.card, 11, "")
    t.pts = U.Text(t.card, 11, Skin.colors.inkSoft, "semi"); t.pts:SetJustifyH("RIGHT")
    t.goal = U.Text(t.card, 10, Skin.colors.inkSoft)
    t.track = t.card:CreateTexture(nil, "ARTWORK"); Skin.Round(t.track, 2, Skin.TEX.RFill); tint(t.track, Skin.colors.hairline)
    t.fill = t.card:CreateTexture(nil, "OVERLAY"); Skin.Round(t.fill, 2, Skin.TEX.RFill); tint(t.fill, Skin.colors.progress)
    P.trees[i] = t
  end
  -- the timeline
  local tl = P.tl
  tl.card = Skin.Card(f)
  tl.head = Skin.Heading(tl.card, 11, "Level by level")
  tl.area = Skin.ScrollArea(tl.card)
  -- the list moves by whole rows: three rows a notch, and it never shows half a row
  tl.area:SetScript("OnMouseWheel", function(_, delta)
    if not tl.tops then return end
    local i = 1
    for k, t in ipairs(tl.tops or { 0 }) do if t <= (tl.scroll or 0) + 0.5 then i = k end end
    i = math.max(1, math.min(#tl.tops, i - (delta or 0) * 3))
    ST:TimelineView(tl.tops[i])
  end)
  -- 0.9.0: the shared bar (drag, track, arrows) moves it by whole rows too: a drag or a page stops on a row's top, an arrow is one row
  tl.area.panoplyScrollTo = function(_, v) if tl.tops then ST:TimelineView(v) end end
  tl.area.panoplyStep = function(_, dir)
    if not tl.tops then return end
    local i = 1
    for k, t in ipairs(tl.tops) do if t <= (tl.scroll or 0) + 0.5 then i = k end end
    i = math.max(1, math.min(#tl.tops, i + (dir or 0)))
    ST:TimelineView(tl.tops[i])
    return tl.scroll
  end
  tl.hl = CreateFrame("Frame", nil, tl.area.content)
  Skin.Box(tl.hl, "S", { fill = Skin.colors.accent, fillA = 0.14, line = Skin.colors.accent })
  tl.hl:Hide()
  tl.note = U.Text(tl.area.content, 11, Skin.colors.inkSoft)
  tl.sample = U.Text(tl.card, 11, Skin.colors.ink); tl.sample:Hide()
  -- the help on the timeline's heading: the Legacy Talented note lives here (spec 03 section 3.2: it moved to the Talents tab)
  tl.help = Kit.HelpIcon(tl.card, "Level by level", ST:TimelineHelp())
  -- the footer: ... (Export, Import, Reset), the status line and the note
  P.rule = f:CreateTexture(nil, "ARTWORK"); Skin.Solid(P.rule, Skin.colors.hairline, 1); P.rule:SetHeight(1)
  P.menu = Skin.Button(f, "...", 34, 28, function(b) ST:OpenPlannerMenu(b) end, "More", "Export as text, Import text, or Reset this plan.")
  P.menu.panoplyFixedW = true
  P.msg = U.Text(f, 11, Skin.colors.inkSoft); P.msg:SetJustifyH("RIGHT")
  P.note = U.Text(f, 11, Skin.colors.dim); P.note:SetJustifyH("RIGHT")
  P.sync = U.Text(f, 11, Skin.colors.inkSoft); P.sync:SetJustifyH("RIGHT"); P.sync:Hide()
  P.note:SetText("Panoply Suite never spends your points.")
  -- the export / import box (it takes the buttons' row while it is open)
  P.io = Skin.Input(f, 200, 24, "Paste a plan (HP1:...)")
  if P.io.icon then P.io.icon:Hide() end
  if P.io.SetTextInsets then P.io:SetTextInsets(8, 6, 0, 0) end
  if P.io.placeholder then P.io.placeholder:ClearAllPoints(); P.io.placeholder:SetPoint("LEFT", P.io, "LEFT", 8, 0) end
  P.io:SetScript("OnTextChanged", function(b)
    ST.ioText = b:GetText() or ""; P.ioLast = ST.ioText
    if b.placeholder then if ST.ioText ~= "" then b.placeholder:Hide() else b.placeholder:Show() end end
  end)
  P.io:SetScript("OnEnterPressed", function(b) if ST.ioMode == "import" then ST:ImportAndKeep(b:GetText()) end ST:AfterEdit() end)
  P.io:Hide()
  P.ioDone = Skin.Button(f, "Done", 90, 24, function()
    if ST.ioMode == "import" then ST:ImportAndKeep(P.io:GetText()) else ST.ioMode = nil end
    ST:AfterEdit()
  end, "Done", "Closes the box.")
  P.ioCancel = Skin.Button(f, "Cancel", 90, 24, function() ST.ioMode = nil; ST.plannerMsg = nil; ST:LayoutPlanner() end, "Cancel", "Closes the box without importing.")
  P.ioDone:Hide(); P.ioCancel:Hide()
  ST.slider, ST.levelText, ST.statusText, ST.noteText = P.slider, P.lv, P.msg, P.note
  ST.plannerButtons = { P.match, P.menu }
  return P
end

-- 0.9.5 phase 4H (spec 03 section 4): the talent planner is the Class page's Talents tab, the only talent UI; its window is gone. The
-- host is one frame, made once and handed to the tab (ST:PlannerHost); LayoutPlanner lays it out for the size and band it is given.
function ST:PlannerHost(parent)
  local f = self.planner
  if not f then
    f = CreateFrame("Frame", "PanoplySuiteTalentPlanner", parent)
    f.panoplyGapOK = true
    f.panoplyHeaderBottom = 0
    f:SetSize(600, 480)
    self.planner = f
    self.pl = buildSkeleton(f)
    if f.HookScript then f:HookScript("OnHide", function() ST:HideTalentTip(); if Skin.menu and Skin.menu.panoplyOwner == ST.pl.menu then Skin.menu:Hide() end end) end
  elseif parent and f:GetParent() ~= parent then
    f:SetParent(parent)
  end
  return f
end
function ST:PlannerFrame() return self:PlannerHost(Panoply.ClassPages and Panoply.ClassPages.pageFrame or UIParent) end

-- after an edit made on the tab: the page is drawn again (the plan's name, Undo, the Overview's next talent follow it)
function ST:AfterEdit()
  if Panoply.Menu and Panoply.Menu.current == "class" and Panoply.Menu.frame and Panoply.Menu.frame:IsShown() then Panoply.Menu:RefreshCurrent()
  else self:LayoutPlanner() end
end

-- The real talents as the planner last read them: read on opening the tab and whenever the game says they changed.
function ST:LiveForPlanner()
  if self.plannerLive == nil then self.plannerLive = self:LiveRanks(self:ClassFile()) or false end
  return self.plannerLive or nil
end
ST:On("CHARACTER_POINTS_CHANGED", function()
  ST.plannerLive = nil
  if ST.planner and ST.planner:IsShown() then ST:LayoutPlanner() end
end)

-- The talent planner: the Class page's Talents tab (the old window's door: the trainer card, the gear, the next-talent card).
-- key: ignored since 0.9.5 (the plan is chosen in the page's header only).
function ST:OpenPlanner(key)
  self.plannerLive = nil
  local CP = Panoply.ClassPages
  if CP and CP.Open then return CP:Open(nil, "talents") end
  if Panoply.Menu and Panoply.Menu.Open then return Panoply.Menu:Open("class") end
  return nil
end

-- the "..." menu: Export as text, Import text, Reset
function ST:PlannerMenuItems()
  return {
    { text = "Export as text", tip = "A short line of text you can paste to a friend or into another character.", func = function()
        ST.ioMode = "export"; ST.ioText = ST:Export(ST.edit); ST:Say("Copy this line (Ctrl+C). It starts with HP1:."); ST:LayoutPlanner() end },
    { text = "Import text", tip = "Paste a plan someone shared. Panoply Suite checks it against the game's talent rules first, and keeps it as a plan of your own.", func = function()
        ST.ioMode = "import"; ST.ioText = ""; ST:Say("Paste the HP1: line and press Enter."); ST:LayoutPlanner() end },
    { text = "Reset", tip = "Takes every point out of this plan. A ready-made plan is never changed: your own empty copy is made.", func = function() ST:ResetAndKeep(); ST:AfterEdit() end },
  }
end

function ST:OpenPlannerMenu(owner)
  return Skin.Menu(owner or (self.pl and self.pl.menu), self:PlannerMenuItems(), { width = 170 })
end

-------------------------------------------------------------------------------
-- Legacy's Talented perk (WoW Forever): talent points start earlier than level 10 (spec 03 section 4, Level by level)
-------------------------------------------------------------------------------
ST.TALENTED_PERK = 1225474
-- the level of the first talent point with the perk the character owns, or nil (no perk, Classic Era, Legacy not read)
function ST:TalentedFirst()
  local L = Panoply.Legacy
  if not (L and L.Here and L.Actual and L.Perk) then return nil end
  local okH, here = pcall(L.Here, L)
  if not (okH and here) then return nil end
  local ok, actual = pcall(L.Actual, L)
  if not ok or type(actual) ~= "table" then return nil end
  local r = math.floor(tonumber(actual[self.TALENTED_PERK]) or 0)
  if r <= 0 then return nil end
  local p = L:Perk(self.TALENTED_PERK)
  local list = p and p.per and p.per.list
  local first = type(list) == "table" and list[math.min(r, #list)] or nil
  return type(first) == "number" and first < self.FIRST_LEVEL and first or nil
end
-- the level the plan's point number i comes at for this character
function ST:PointLevel(i)
  return (self:TalentedFirst() or self.FIRST_LEVEL) + i - 1
end
function ST:TimelineHelp()
  return "Your plan, point by point, with the level each point comes at. The shown level is marked; move the slider to look at an earlier one."
    .. "\n\nWoW Forever: Legacy's Talented perk hands out talent points up to five levels early. With the perk, the early points are marked \"Legacy Talented\" and the list moves to match. The most you can have is still 51."
end

-------------------------------------------------------------------------------
-- WoW Forever's new talents (spec 03 section 4): a "New in Forever" badge and the note the Class Guide had, in the talent's tooltip
-------------------------------------------------------------------------------
-- a talent WoW Forever added in place of an Era one: its Forever name is in the class's list (Modules/ClassPages/Data/ForeverTalents.lua)
function ST:ForeverNew(tal, class)
  if not (C.IsForever and C.IsForever()) then return nil end
  local CP = Panoply.ClassPages
  local list = CP and CP.FOREVER_TALENTS and CP.FOREVER_TALENTS[class or self:ClassFile() or ""]
  if not list then return nil end
  local e = list[tal.name]
  if e == nil then
    -- the game's own name for the talent (its talent window), for the character's own class
    if (class or self:ClassFile()) == self:ClassFile() then
      self.liveNames = self.liveNames or {}
      local n = self.liveNames[tal.id]
      if n == nil then
        local live = self:LiveTalent(tal)
        n = live and live.name or false
        self.liveNames[tal.id] = n
      end
      if n then e = list[n] end
    end
  end
  if e == nil then return nil end
  return e == true and "" or e
end

function ST:PlannerView()
  local e = self.edit
  if not e then return nil end
  local show = clamp(self.showLevel or 60, self.FIRST_LEVEL - 1, self.FIRST_LEVEL - 1 + #e.points)
  local nShown = show - self.FIRST_LEVEL + 1
  local ranks, spent = self:RanksAt(e.class, e.points, nShown)
  return { show = show, nShown = nShown, ranks = ranks, spent = spent, nextId = e.points[nShown + 1], T = self:Trees(e.class) }
end

-- the plain line on why a talent is in the plan
function ST:WhyLine(tal)
  local e = self.edit
  -- a ready-made plan is edited as a copy: the reasons live on the plan it came from
  local origin = e.from and self:Find(e.from, e.class) or (e.ready and e.key and self:Find(e.key, e.class)) or e
  local w = origin and origin.why and origin.why[tal.key]
  if w then return w end
  local T = self:Trees(self.edit.class)
  return ("A %s talent, row %d."):format(T.tabs[tal.tab].name, tal.tier + 1)
end

-- the level a plan takes the next point of a talent, after the shown level
function ST:DueLevel(id, nShown)
  for i, v in ipairs(self.edit.points) do
    if v == id and i > nShown then return self:PointLevel(i) end
  end
end

-- "Level 45: 36 of 51 points (31 / 5 / 0)" (spec 03 section 4)
function ST:LevelLine(v)
  -- the first point comes at level 10, so an empty plan reads level 10 too
  return ("Level %d: %s%d of %d points|r (%d / %d / %d)"):format(math.max(v.show, self.FIRST_LEVEL), Skin.Code(Skin.colors.goldBright), v.nShown, self.POINTS,
    v.spent[1], v.spent[2], v.spent[3])
end

-- the tree's goal: the deepest talent the whole plan buys in it, and how many points the plan puts there
function ST:TreeGoal(class, points)
  local T = self:Trees(class)
  local planned, goal, at = { 0, 0, 0 }, {}, {}
  for i, id in ipairs(points) do
    local tal = T.byId[id]
    if tal then
      planned[tal.tab] = planned[tal.tab] + 1
      if not goal[tal.tab] or tal.tier >= goal[tal.tab].tier then goal[tal.tab] = tal end
    end
  end
  return planned, goal
end

-- tooltip text for a talent (a plain table, so tests can read it)
function ST:TalentTipText(tal)
  local e, v = self.edit, self:PlannerView()
  local T = v.T
  local r = v.ranks[tal.id] or 0
  local due = self:DueLevel(tal.id, v.nShown)
  local rank = ("Rank %d/%d"):format(r, tal.ranks) .. (due and (" " .. DOT .. " due at level " .. due) or "")
  local meta = {}
  if tal.tier > 0 then meta[#meta + 1] = ("Requires %d points in %s."):format(tal.tier * 5, T.tabs[tal.tab].name) end
  if tal.prereq and T.byId[tal.prereq] then
    local pre = T.byId[tal.prereq]
    meta[#meta + 1] = ("Requires %s %d/%d."):format(pre.name, tal.prereqRank, pre.ranks)
  end
  if tal.id == v.nextId then meta[#meta + 1] = ("Next in your %s plan."):format(e.name or "talent") end
  -- 0.9.5 phase 4H: points your character has here that the plan never takes, and WoW Forever's own talents with their note
  if self.offPlan and self.offPlan[tal.id] then meta[#meta + 1] = "You have more points here than your plan: Match my talents starts the plan from your talents." end
  local new = self:ForeverNew(tal, e.class)
  local forever
  if new ~= nil then forever = "New in Forever" .. (new ~= "" and (": " .. new) or ".") end
  return { name = tal.name, rank = rank, why = self:WhyLine(tal), meta = table.concat(meta, "\n"), forever = forever,
           action = "Left-click adds this point " .. DOT .. " right-click takes one back" }
end

-------------------------------------------------------------------------------
-- The hover tooltip (tooltip.jpg): the icon, the name, the rank and due level, why, what it needs, what a click does
-------------------------------------------------------------------------------
local TIP_W = 268
function ST:TalentTip()
  local m = self.talentTip
  if m then return m end
  m = CreateFrame("Frame", "PanoplySuiteTalentTip", UIParent)
  m:SetFrameStrata("TOOLTIP"); m:SetSize(TIP_W, 120)
  if m.EnableMouse then m:EnableMouse(false) end
  m.panoplyBox = true
  Skin.Box(m, "M", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.gold })
  m.art = CreateFrame("Frame", nil, m); m.art:SetSize(40, 40); tileArt(m.art); m.art:SetBorder(Skin.colors.gold)
  m.title = Skin.Heading(m, 14, "")
  m.rank = U.Text(m, 12, Skin.colors.goldBright)
  m.why = U.Text(m, 12, Skin.colors.ink)
  m.meta = U.Text(m, 11, Skin.colors.inkSoft)
  m.forever = U.Text(m, 11, Skin.colors.accent)
  m.action = U.Text(m, 11, Skin.colors.accent)
  m:Hide()
  self.talentTip = m
  return m
end

function ST:ShowTalentTip(owner)
  local tal = owner and owner.panoplyTalent
  if not (tal and self.edit) then return end
  local m = self:TalentTip()
  local L = self:TalentTipText(tal)
  self.tipOwner = owner
  m.art.panoplyIcon:SetTexture(owner.panoplyIconFile)
  local px, py = 12, 12
  local textX = px + 40 + 10
  local tw = TIP_W - textX - px
  m.title:SetText(L.name); put(m.title, m, textX, py, tw)
  local th = Skin.TextHeight(m.title, tw); m.title:SetHeight(th)
  m.rank:SetText(L.rank); put(m.rank, m, textX, py + th + 2, tw)
  local rh = Skin.TextHeight(m.rank, tw); m.rank:SetHeight(rh)
  local headH = math.max(40, th + 2 + rh)
  put(m.art, m, px, py + math.floor((headH - 40) / 2))
  local fw = TIP_W - 2 * px
  local y = py + headH + 10
  local function block(fs, text, gap)
    fs:SetText(text or "")
    if (text or "") == "" then fs:Hide() return end
    fs:Show(); put(fs, m, px, y, fw)
    local h = Skin.TextHeight(fs, fw); fs:SetHeight(h)
    y = y + h + gap
  end
  block(m.why, L.why, 8)
  block(m.forever, L.forever, 8)
  block(m.meta, L.meta, 8)
  block(m.action, L.action, 0)
  m:SetHeight(y + py)
  m.text = L
  m:ClearAllPoints()
  -- right of the tile, or left of it when the screen ends there
  local ui = _G.UIParent
  local sw = ui and ui.GetWidth and ui:GetWidth() or 1024
  local l, r = ST.BoxOf(owner)
  if l and r and r + TIP_W + 14 > sw then m:SetPoint("RIGHT", owner, "LEFT", -10, 0) else m:SetPoint("LEFT", owner, "RIGHT", 10, 0) end
  if m.SetClampedToScreen then m:SetClampedToScreen(true) end
  m:Show()
end

function ST:HideTalentTip()
  self.tipOwner = nil
  if self.talentTip then self.talentTip:Hide() end
end

-------------------------------------------------------------------------------
-- Layout: measure, size the tiles to the room, refresh every widget
-------------------------------------------------------------------------------
-- Layout: measure, size the tiles to the room, refresh every widget (0.9.5 phase 4H: inside the Talents tab, in three bands)
--   Wide     the three trees and the Level by level list side by side, filling the tab's height
--   Medium   the three trees across the whole width, the Level by level list below them
--   Narrow   one tree at a time (a switcher that says the points in each), Next point at the top, the list below
-------------------------------------------------------------------------------
local function layoutNext(self, P, v, e, x0, dn, cw)
  local nx = P.next
  local card = nx.card
  local tal = v.nextId and v.T.byId[v.nextId]
  local labelW = math.ceil(Skin.TextWidth(nx.label)) + 4
  nx.label:SetWidth(labelW)
  local lh = Skin.TextHeight(nx.label, labelW); nx.label:SetHeight(lh)
  local iconX = 12 + labelW + 12
  local metaX = iconX + 34 + 10
  local due = tal and ("Level " .. self:PointLevel(v.nShown + 1)) or ""
  nx.due:SetText(due)
  local dueW = tal and (math.ceil(Skin.TextWidth(nx.due)) + 4) or 0
  nx.due:SetWidth(math.max(1, dueW))
  local mw = cw - 12 - dueW - 12 - metaX
  local name, why
  if tal then
    local r = (v.ranks[tal.id] or 0) + 1
    name = tal.name .. "  " .. Skin.Code(Skin.colors.goldBright) .. r .. "/" .. tal.ranks .. "|r"
    why = self:WhyLine(tal)
    nx.icon.panoplyIcon:SetTexture(self:HeldIcon(tal, e.class))
    nx.icon:SetBorder(Skin.colors.gold); nx.icon:SetLook(1, 1); nx.icon:Show()
  else
    nx.icon:Hide()
    if #e.points == 0 then
      name, why = "No points yet", "Click a talent in the first row of a tree to start the plan."
    elseif v.nShown >= #e.points and #e.points >= self.POINTS then
      name, why = "Every point is placed", ("All %d points are in this plan."):format(self.POINTS)
    else
      name, why = "Nothing planned after this level", "Click a talent to add the next point."
    end
    metaX = iconX
    mw = cw - 12 - metaX - 12
  end
  nx.name:SetText(name); nx.why:SetText(why or "")
  local nh, wh = Skin.TextHeight(nx.name, mw), Skin.TextHeight(nx.why, mw)
  local metaH = nh + 2 + wh
  local cardH = 2 * 7 + math.max(34, metaH)
  card:ClearAllPoints(); card:SetPoint("TOPLEFT", P.f, "TOPLEFT", x0, -dn); card:SetSize(cw, cardH)
  put(nx.label, card, 12, math.floor((cardH - lh) / 2))
  put(nx.icon, card, iconX, math.floor((cardH - 34) / 2))
  local my = math.floor((cardH - metaH) / 2)
  put(nx.name, card, metaX, my, mw, nh)
  put(nx.why, card, metaX, my + nh + 2, mw, wh)
  if tal then
    local dh = Skin.TextHeight(nx.due, dueW); nx.due:SetHeight(dh)
    nx.due:ClearAllPoints(); nx.due:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -math.floor((cardH - dh) / 2))
    nx.due:Show()
  else nx.due:Hide() end
  return cardH
end

-- the badge on a talent WoW Forever added (made on first use, on the tile)
local function badgeOf(b)
  local t = b.panoplyBadge
  if not t then
    t = b:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 3)
    b.panoplyBadge = t
  end
  return t
end

local function styleTile(b, tal, v, t, T, nextId, off, class)
  local r = v.ranks[tal.id] or 0
  local picked, isNext = r > 0, tal.id == nextId
  local legal = picked or (ST:CanAdd(T, v.ranks, v.spent, tal)) and true or false
  local look = picked and LOOK_PICKED or (legal and LOOK_OPEN or LOCKED)
  b:SetLook(look[1], look[2])
  -- a talent your character has more points in than the plan: outlined in amber (spec 03 section 4, Live vs plan)
  local border = (off and off[tal.id]) and Skin.colors.warn or (isNext and Skin.colors.accent or (picked and Skin.colors.gold or Skin.colors.slotLine))
  b:SetBorder(border)
  b.tileState, b.tileNext, b.tileRank, b.tileOff = picked and "picked" or (legal and "open" or "locked"), isNext, r, (off and off[tal.id]) and true or nil
  local fs, pill = b.panoplyPillText, b.panoplyPill
  fs:SetText(r .. "/" .. tal.ranks)
  colorText(fs, isNext and Skin.colors.accent or (picked and Skin.colors.done or Skin.colors.inkSoft))
  local pw, ph = math.ceil(Skin.TextWidth(fs)) + 8, math.ceil(Skin.TextHeight(fs)) + 2
  pill:SetSize(pw, ph)
  -- "New in Forever"
  local note = ST:ForeverNew(tal, class)
  b.tileNew = note ~= nil
  if note ~= nil then
    local bd = badgeOf(b)
    local s = math.max(10, math.floor((ST.tileSize or 30) * 0.38))
    bd:SetSize(s, s)
    Kit.Icon(bd, "icon.badge.new", { size = s })
    bd:Show()
  elseif b.panoplyBadge then b.panoplyBadge:Hide() end
end

-- the tile size and gaps for a tree card tw wide; avail: the height there is for the seven rows (nil: as the width allows)
local function treeGeometry(tw, headBlock, avail)
  local byW = math.floor((tw - 12 - 3 * 6) / 4)
  local tile
  if avail then tile = clamp(math.min(byW, math.floor((avail - 6 * 8) / 7)), TILE_MIN, TILE_MAX)
  else tile = clamp(byW, TILE_MIN, TILE_MAX) end
  local gapY = avail and clamp(math.floor((avail - 7 * tile) / 6), 4, 12) or 8
  local gapX = clamp(math.floor((tw - 12 - 4 * tile) / 3), 6, 22)
  local gridW = 4 * tile + 3 * gapX
  return { tile = tile, px = tile + gapX, py = tile + gapY, gx = math.floor((tw - gridW) / 2), gy = headBlock,
    h = headBlock + 7 * tile + 6 * gapY + 8 }
end

-- the tree headers' text (names, points, goals): returns the tallest header block
local function treeHeads(P, v, e, T, tw, planned, goal)
  local headBlock = 0
  for i, t in ipairs(P.trees) do
    local tab = T.tabs[i]
    t.pts:SetText(v.spent[i] .. " pts")
    local pw = math.ceil(Skin.TextWidth(t.pts)) + 4
    t.pts:SetWidth(pw)
    local nw = tw - 12 - pw - 6
    Skin.Ellipsize(t.name, tab.name, nw - 2); t.name:SetWidth(nw)
    local hh = math.max(Skin.TextHeight(t.name, nw), Skin.TextHeight(t.pts))
    local gtxt
    if planned[i] > 0 and goal[i] then gtxt = "Goal: " .. Skin.Code(Skin.colors.goldBright) .. goal[i].name .. "|r" else gtxt = "No points in this plan" end
    t.goal:SetWidth(tw - 16)
    Skin.Ellipsize(t.goal, gtxt, tw - 18)
    local gh = Skin.TextHeight(t.goal, tw - 16)
    t.hh, t.gh = hh, gh
    headBlock = math.max(headBlock, 6 + hh + 2 + gh + 4 + 4 + 8)
  end
  return headBlock
end

local function layoutTree(P, i, v, e, T, x, dn, tw, cardH, G, planned, nextId, off)
  local t = P.trees[i]
  local card = t.card
  card:ClearAllPoints(); card:SetPoint("TOPLEFT", P.f, "TOPLEFT", x, -dn); card:SetSize(tw, cardH)
  card:Show()
  t.pts:ClearAllPoints(); t.pts:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
  t.pts:SetHeight(Skin.TextHeight(t.pts))
  put(t.name, card, 6, 6, nil, Skin.TextHeight(t.name, t.name:GetWidth()))
  put(t.goal, card, 8, 6 + t.hh + 2, nil, t.gh)
  local by = 6 + t.hh + 2 + t.gh + 4
  local bw = tw - 16
  put(t.track, card, 8, by, bw, 4)
  local frac = planned[i] > 0 and math.min(1, v.spent[i] / planned[i]) or 0
  t.frac = frac
  if frac > 0 then put(t.fill, card, 8, by, math.max(4, math.floor(bw * frac + 0.5)), 4); t.fill:Show() else t.fill:Hide() end
  local key = table.concat({ G.tile, G.px, G.py, G.gx, G.gy, tw, e.class }, ",")
  if t.geomKey ~= key then t.geomKey = key; placeGeometry(t, G) end
  for k = 1, 28 do
    local c = t.cells[k]
    if c and c.tal and c.btn then styleTile(c.btn, c.tal, v, t, T, nextId, off, e.class) end
  end
  for j = 1, t.arrowN do
    local a = t.arrows[j]
    local met = (v.ranks[a.from.id] or 0) >= (a.to.prereqRank or 1)
    for _, x2 in ipairs(a.parts) do tint(x2, met and Skin.colors.gold or Skin.colors.slotLine) end
    a.met = met
  end
end

-- Lays the tab out for the size of its host (ST.planner) and the band ST.plannerBand. Returns the height it used.
function ST:LayoutPlanner()
  local f, P = self.planner, self.pl
  if not (f and P) then return 0 end
  local e = self:EditActive()
  if not e then return 0 end
  local T = self:Trees(e.class)
  if not T then return 0 end
  bindClass(P, T, e.class)
  local W, H = math.max(300, f:GetWidth() or 600), math.max(200, f:GetHeight() or 480)
  local band = self.plannerBand or Panoply.Kit.Band(W)
  local x0, inner = 0, W
  local v = self:PlannerView()
  self.showLevel = v.show
  local nextId = v.nextId
  self.cells = self.cells or {}
  local dn = 0
  -- level text and slider
  local lv = P.lv
  lv:SetText(self:LevelLine(v))
  local lvw = math.min(math.ceil(Skin.TextWidth(lv)) + 4, inner)
  lv:SetWidth(lvw)
  local lvh = Skin.TextHeight(lv, lvw); lv:SetHeight(lvh)
  lv:ClearAllPoints(); lv:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + inner, -dn)
  local sl = P.slider
  if #e.points > 0 and inner - lvw - Skin.SP.l >= 120 then
    local maxLv = math.max(self.FIRST_LEVEL, self.FIRST_LEVEL - 1 + #e.points)
    self.sliderQuiet = true
    if sl.SetMinMaxValues then sl:SetMinMaxValues(self.FIRST_LEVEL, maxLv) end
    sl:ClearAllPoints(); sl:SetWidth(math.max(120, inner - lvw - Skin.SP.l))
    sl:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -(dn + math.max(0, math.floor((lvh - 16) / 2)) + 1)); sl:Refresh()
    self.sliderQuiet = nil
    sl:Show(); sl.label:Hide()
  else sl:Hide(); sl.label:Hide() end
  dn = dn + math.max(16, lvh) + SEC_GAP
  -- the Next point card
  dn = dn + layoutNext(self, P, v, e, x0, dn, inner) + SEC_GAP
  -- live vs plan: "2 points don't match your plan", the nodes outlined in amber, and Match my talents
  local off, syncText, syncBad = nil, nil, nil
  do
    local ok, cmp = pcall(self.Compare, self, e, e.class == self:ClassFile() and self:LiveForPlanner() or nil)
    if ok and cmp then
      syncText, syncBad = self:SyncLine(e, cmp)
      if cmp.extraN > 0 then
        off = {}
        for _, x in ipairs(cmp.extra) do off[x.tal.id] = true end
      end
      self.syncShown = syncText and { text = syncText, differs = syncBad or false, inStep = cmp.inStep, extraN = cmp.extraN } or nil
    else self.syncShown = nil end
    self.offPlan = off
    if off then
      local n = self.syncShown.extraN
      P.mismatch:SetText(("%d %s match your plan"):format(n, n == 1 and "point doesn't" or "points don't"))
      Skin.FitButton(P.match, 100, 160)
      local mw = math.min(math.ceil(Skin.TextWidth(P.mismatch)) + 4, inner - P.match:GetWidth() - Skin.SP.m)
      P.mismatch:SetWidth(mw)
      local mh = Skin.TextHeight(P.mismatch, mw); P.mismatch:SetHeight(mh)
      local rowH = math.max(mh, P.match:GetHeight())
      put(P.mismatch, f, x0, dn + math.floor((rowH - mh) / 2))
      P.mismatch:Show()
      P.match:ClearAllPoints(); P.match:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + mw + Skin.SP.m, -dn); P.match:Show()
      self.mismatchText = P.mismatch:GetText()
      dn = dn + rowH + SEC_GAP
    else
      P.mismatch:Hide(); P.match:Hide()
      self.mismatchText = nil
    end
  end
  -- footer (measured first in the Wide band: the trees take what is left)
  local GRIP = 0
  local io = self.ioMode
  P.menu:SetWidth(34)
  local sideW = inner - 34 - Skin.SP.l
  local blockW = io and inner or sideW
  local msg = self.plannerMsg
  P.msg:SetText(msg and msg.text or ""); colorText(P.msg, msg and msg.bad and Skin.colors.warn or Skin.colors.inkSoft)
  local mh = msg and Skin.TextHeight(P.msg, blockW) or 0
  P.msg:SetWidth(blockW); P.msg:SetHeight(math.max(1, mh))
  P.note:SetWidth(blockW)
  local nh = Skin.TextHeight(P.note, blockW); P.note:SetHeight(nh)
  local showSync = syncText and not off
  P.sync:SetText(showSync and syncText or ""); colorText(P.sync, syncBad and Skin.colors.warn or Skin.colors.inkSoft)
  local sh = showSync and Skin.TextHeight(P.sync, blockW) or 0
  P.sync:SetWidth(blockW); P.sync:SetHeight(math.max(1, sh))
  local blockH = mh + (mh > 0 and 2 or 0) + sh + (sh > 0 and 2 or 0) + nh
  local rowH = io and 24 or math.max(28, blockH)
  local footH = io and (24 + Skin.SP.s + blockH) or rowH
  -- the body: the trees and the timeline
  local planned, goal = self:TreeGoal(e.class, e.points)
  local gap = COL_GAP
  local bodyTop = dn
  local bottom
  for _, b in ipairs(P.treeTabs) do b:Hide() end
  if band == "wide" then
    local footTop = math.max(H - footH - 4, bodyTop + 300)
    local bodyH = footTop - 13 - bodyTop
    local treesW = inner - TL_W - SEC_GAP
    local tw = math.floor((treesW - 2 * gap) / 3)
    local headBlock = treeHeads(P, v, e, T, tw, planned, goal)
    local G = treeGeometry(tw, headBlock, bodyH - headBlock - 8)
    self.tileSize = G.tile
    for i = 1, 3 do layoutTree(P, i, v, e, T, x0 + (i - 1) * (tw + gap), bodyTop, tw, bodyH, G, planned, nextId, off) end
    self:LayoutTimeline(P, v, e, T, x0 + treesW + SEC_GAP, bodyTop, bodyH, TL_W)
    bottom = footTop
  elseif band == "medium" then
    local tw = math.floor((inner - 2 * gap) / 3)
    local headBlock = treeHeads(P, v, e, T, tw, planned, goal)
    local G = treeGeometry(tw, headBlock, nil)
    self.tileSize = G.tile
    for i = 1, 3 do layoutTree(P, i, v, e, T, x0 + (i - 1) * (tw + gap), bodyTop, tw, G.h, G, planned, nextId, off) end
    local tlTop = bodyTop + G.h + SEC_GAP
    local tlH = 230
    self:LayoutTimeline(P, v, e, T, x0, tlTop, tlH, inner)
    bottom = tlTop + tlH + SEC_GAP + 5
  else
    -- one tree at a time: the switcher says the points in each
    local shown = self.treeShown
    if not (shown and T.tabs[shown]) then
      shown = 1
      local best = -1
      for i = 1, 3 do if (planned[i] or 0) > best then best, shown = planned[i] or 0, i end end
      self.treeShown = shown
    end
    local tabs = {}
    for i, b in ipairs(P.treeTabs) do
      b.label:SetText(("%s %d"):format(T.tabs[i].name, v.spent[i]))
      b:SetActive(i == shown)
      Skin.FitButton(b, 60, inner)
      tabs[#tabs + 1] = b
    end
    local bh = Skin.FlowButtons(f, tabs, x0, -bodyTop, inner, Skin.SP.s, 60)
    for _, b in ipairs(tabs) do b:Show() end
    local treeTop = bodyTop + bh + SEC_GAP
    local tw = inner
    local headBlock = treeHeads(P, v, e, T, tw, planned, goal)
    local G = treeGeometry(tw, headBlock, nil)
    self.tileSize = G.tile
    for i = 1, 3 do
      if i == shown then layoutTree(P, i, v, e, T, x0, treeTop, tw, G.h, G, planned, nextId, off)
      else P.trees[i].card:Hide() end
    end
    local tlTop = treeTop + G.h + SEC_GAP
    local tlH = 220
    self:LayoutTimeline(P, v, e, T, x0, tlTop, tlH, inner)
    bottom = tlTop + tlH + SEC_GAP + 5
  end
  if band ~= "narrow" then for i = 1, 3 do P.trees[i].card:Show() end end
  self.nextCell = nextId and self.cells[nextId] or nil
  -- footer widgets
  local footTop = bottom
  P.rule:ClearAllPoints(); P.rule:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -(footTop - 7)); P.rule:SetWidth(inner)
  local fy = footTop
  if io then
    P.menu:Hide()
    local imp = io == "import"
    P.io:ClearAllPoints(); P.io:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -fy); P.io:SetSize(inner - (imp and 200 or 100), 24)
    if P.ioShown ~= io or P.ioLast ~= (self.ioText or "") then
      P.ioShown = io; P.ioLast = self.ioText or ""
      P.io:SetText(P.ioLast)
      if P.io.placeholder then if P.ioLast ~= "" then P.io.placeholder:Hide() else P.io.placeholder:Show() end end
      if io == "export" and P.io.HighlightText then P.io:SetFocus(); P.io:HighlightText() end
    end
    if P.io.placeholder then P.io.placeholder:SetText(imp and "Paste a plan (HP1:...)" or "") end
    P.io:Show()
    P.ioDone.label:SetText(imp and "Import" or "Done")
    P.ioDone.tip, P.ioDone.tipBody = imp and "Import" or "Done", imp and "Checks the text against the game's talent rules, then keeps it as a plan of your own." or "Closes the box."
    P.ioDone:ClearAllPoints(); P.ioDone:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + inner - (imp and 190 or 90), -fy); P.ioDone:Show()
    if imp then P.ioCancel:ClearAllPoints(); P.ioCancel:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + inner - 90, -fy); P.ioCancel:Show() else P.ioCancel:Hide() end
    self.ioBox, self.ioCancel = P.io, imp and P.ioCancel or nil
    fy = fy + 24 + Skin.SP.s
  else
    P.ioShown = nil
    P.io:Hide(); P.ioDone:Hide(); P.ioCancel:Hide(); self.ioBox, self.ioCancel = nil, nil
    P.menu:ClearAllPoints(); P.menu:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -(fy + math.floor((rowH - 28) / 2))); P.menu:Show()
  end
  -- the status line and the note, right-aligned beside the ... (or under the box)
  local by = io and fy or (fy + math.floor((rowH - blockH) / 2))
  P.msg:ClearAllPoints(); P.note:ClearAllPoints(); P.sync:ClearAllPoints()
  if mh > 0 then P.msg:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + inner - GRIP, -by); P.msg:Show() else P.msg:Hide() end
  local sy = by + (mh > 0 and mh + 2 or 0)
  if sh > 0 then P.sync:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + inner - GRIP, -sy); P.sync:Show() else P.sync:Hide() end
  P.note:SetPoint("TOPRIGHT", f, "TOPLEFT", x0 + inner - GRIP, -(sy + (sh > 0 and sh + 2 or 0)))
  self.footTop = footTop
  local used = fy + (io and blockH or rowH) + 4
  self.plannerUsed = used
  if self.tipOwner and self.talentTip and self.talentTip:IsShown() then self:ShowTalentTip(self.tipOwner) end
  return used
end


-- Show the list from the row whose top is `want` (or the nearest row top before it). The view ends on a whole row too:
-- the area is only as tall as the whole rows that fit, so half a row is never drawn; the last page ends at the last row.
function ST:TimelineView(want)
  local tl = self.pl.tl
  local area, maxH = tl.area, tl.viewMax
  local last = tl.tops[#tl.tops]
  for _, t in ipairs(tl.tops) do if tl.contentH - t <= maxH + 0.5 then last = t break end end
  local top = math.max(0, math.min(want or 0, last))
  local s = 0
  for _, t in ipairs(tl.tops) do if t <= top + 0.5 then s = t end end
  local eff = 0
  if tl.contentH - s <= maxH + 0.5 then eff = tl.contentH - s
  else
    for i, t in ipairs(tl.tops) do
      local h = tl.bottoms[i] - s
      if t >= s - 0.5 and h <= maxH + 0.5 and h > eff then eff = h end
    end
    if eff <= 0 then eff = maxH end
  end
  area:SetHeight(eff)
  area:SetContentHeight(tl.contentH)
  area:SetVerticalScroll(s)
  area:UpdateBar()
  tl.scroll = s
end

-- the Level by level list: groups of ten levels, small icons, the shown level highlighted, scrolling by whole rows.
-- A name that is longer than its room wraps onto a second line and its row grows: no name is ever cut short.
function ST:LayoutTimeline(P, v, e, T, x, dn, cardH, cardW)
  local tl = P.tl
  local card = tl.card
  local CWd = cardW or TL_W
  card:ClearAllPoints(); card:SetPoint("TOPLEFT", P.f, "TOPLEFT", x, -dn); card:SetSize(CWd, cardH)
  local hh = Skin.TextHeight(tl.head, CWd - 20 - 22)
  put(tl.head, card, 10, 6, CWd - 20 - 22, hh)
  if tl.help then tl.help:ClearAllPoints(); tl.help:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -6); tl.help:Show() end
  local areaY = 6 + math.max(hh, 16) + 4
  local viewH = cardH - areaY - 6
  local areaW = CWd - 12
  local first = self:TalentedFirst()
  local area = tl.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -areaY); area:SetWidth(areaW)
  tl.viewMax = viewH
  tl.sample:SetText("Ag")
  local lineH = math.ceil(Skin.TextHeight(tl.sample))
  local headH = lineH + 6
  -- what goes in the list
  local items, count = {}, {}
  local lastLo
  for i, id in ipairs(e.points) do
    local tal = T.byId[id]
    -- Legacy Talented: the points start earlier, and the early ones are marked
    local lvN = (first or self.FIRST_LEVEL) + i - 1
    count[id] = (count[id] or 0) + 1
    local lo = math.floor(lvN / 10) * 10
    if lo ~= lastLo then
      items[#items + 1] = { head = lo >= self.LAST_LEVEL and tostring(lo) or (lo .. EN_DASH .. (lo + 9)) }
      lastLo = lo
    end
    items[#items + 1] = { i = i, lv = lvN, tal = tal, rank = count[id], talented = lvN < self.FIRST_LEVEL }
  end
  local rowW = areaW - 12                       -- room for the scroll bar is always kept, so wrapping never depends on it
  local content = area.content
  content:SetWidth(rowW)
  tl.sample:SetText("60"); local lvW = math.ceil(Skin.TextWidth(tl.sample)) + 6
  tl.sample:SetText("5/5"); local rkW = math.ceil(Skin.TextWidth(tl.sample)) + 4
  local icon = 15
  local nameX = 4 + lvW + 2 + icon + 5
  local nameW = rowW - nameX - rkW - 8
  local y, curY = 0, nil
  local nr, nh = 0, 0
  tl.hl:Hide()
  tl.rowOf = {}
  tl.tops, tl.bottoms = {}, {}
  tl.wrapped = 0
  for _, it in ipairs(items) do
    if it.head then
      nh = nh + 1
      local fs = tl.heads[nh]
      if not fs then fs = Skin.Label(content, 10, Skin.colors.accent); tl.heads[nh] = fs end
      fs:SetText(it.head); fs:SetWidth(rowW - 8); fs:SetHeight(lineH); put(fs, content, 4, y + 3); fs:Show()
      tl.tops[#tl.tops + 1] = y
      y = y + headH
      tl.bottoms[#tl.tops] = y
    else
      nr = nr + 1
      local r = tl.rows[nr]
      if not r then
        r = CreateFrame("Frame", nil, content)
        r.panoplyGapOK = true
        r.lv = U.Text(r, 10, Skin.colors.dim, "semi")
        r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = U.Text(r, 11, Skin.colors.ink)
        r.rk = U.Text(r, 10, Skin.colors.goldBright, "semi"); r.rk:SetJustifyH("RIGHT")
        tl.rows[nr] = r
      end
      local future = it.i > v.nShown
      local current = it.lv == v.show
      if r.name.SetWordWrap then r.name:SetWordWrap(true) end
      r.name.panoplyCut = nil
      r.name:SetText(it.talented and (it.tal.name .. " (Legacy Talented)") or it.tal.name); r.name:SetWidth(nameW)
      r.talented = it.talented or nil
      if it.talented then
        Skin.Tooltip(r, ("Level %d: %s"):format(it.lv, it.tal.name), "An early point from Legacy's Talented perk: talent points start before level 10 with it. The most you can have is still 51.")
        if r.EnableMouse then r:EnableMouse(true) end
        r:SetScript("OnEnter", function(self) if self.panoplyShowTip and self.talented then self.panoplyShowTip() end end)
        r:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      end
      local th = Skin.TextHeight(r.name, nameW)
      r.name:SetHeight(th)
      if th > lineH * 1.5 then tl.wrapped = tl.wrapped + 1 end
      local rowH = math.max(lineH, th) + 4
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); r:SetSize(rowW, rowH); r:Show()
      r.lv:SetText(it.lv); r.lv:SetWidth(lvW); r.lv:SetHeight(lineH); put(r.lv, r, 4, 2)
      colorText(r.lv, current and Skin.colors.accent or Skin.colors.dim)
      r.ic:ClearAllPoints(); r.ic:SetPoint("TOPLEFT", r, "TOPLEFT", 4 + lvW + 2, -(2 + math.floor((lineH - icon) / 2))); r.ic:SetSize(icon, icon)
      r.ic:SetTexture(self:HeldIcon(it.tal, e.class))
      put(r.name, r, nameX, 2)
      colorText(r.name, future and Skin.colors.inkSoft or Skin.colors.ink)
      r.rk:SetText(it.rank .. "/" .. it.tal.ranks); r.rk:SetWidth(rkW); r.rk:SetHeight(lineH)
      r.rk:ClearAllPoints(); r.rk:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -2)
      r.level, r.tal = it.lv, it.tal
      tl.rowOf[it.lv] = r
      if current then
        curY = y
        tl.hl:ClearAllPoints(); tl.hl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); tl.hl:SetSize(rowW, rowH); tl.hl:Show()
        tl.current = r
      end
      tl.tops[#tl.tops + 1] = y
      y = y + rowH
      tl.bottoms[#tl.tops] = y
    end
  end
  if #e.points == 0 then
    tl.note:SetText("No points yet. Click a talent in the first row of a tree.")
    put(tl.note, content, 4, 4, rowW - 8)
    local h = Skin.TextHeight(tl.note, rowW - 8); tl.note:SetHeight(h); tl.note:Show()
    y = h + 8
    tl.tops, tl.bottoms = { 0 }, { y }
  else tl.note:Hide() end
  if not curY then tl.current = nil end
  for i = nr + 1, #tl.rows do tl.rows[i]:Hide(); tl.rows[i].level = nil end
  for i = nh + 1, #tl.heads do tl.heads[i]:Hide() end
  tl.viewH, tl.lineH, tl.contentH = viewH, lineH, y
  self:TimelineView(curY and (curY - viewH / 2) or 0)
end

function ST:ImportEdit(text)
  local p, err = self:Import(text)
  if not p then self:Say(err, true) return nil end
  self.ioMode = nil
  self.edit = copyPlan(p); self.edit.key = nil; self.edit.dirty = true
  self.showLevel = self.FIRST_LEVEL - 1 + #p.points
  self:Say(("Imported \"%s\" (%d points). Save to keep it."):format(p.name, #p.points))
  return self.edit
end
