-- Panoply Suite 0.9.5 phase 4H: the Class page's Pet tab for Hunters (docs/specs/page-redesigns-03-class.md section 8). One pet view
-- instead of the four sections of 0.9.1 (Families, Planner, To tame, Training points); the facts and the plan are Modules/HunterPet/Core.lua
-- as before, and nothing saved is renamed (PanoplySuiteCharDB.hunterPet, PanoplySuiteDB.hunterPetBeasts).
--
--   Pet strip        the pet's name, its family's icon and name, level, loyalty, happiness (the game's face, in its colour), training
--                    points "70 total · 7 spent · 63 free"; Families, Feed (what this family eats), Point me to the stable master.
--   Abilities        (left, Wide) one row per ability the family can learn: its icon, name, rank pips (filled = learned or on the pet,
--                    gold outline = in the plan, grey = not planned, lock = needs a higher pet level), the training points of the planned
--                    rank, and - / + for the planned rank. A budget bar on top: what the plan uses against what the pet will have, for
--                    the pet now or at level 60 with loyalty 6 (this replaces the Pet level and Loyalty level steppers). A click on a pip
--                    selects that rank; a right-click ticks it learned by hand (the recorder ticks it when the game says so).
--   Where to learn   (right, Wide) the next beasts to tame for the plan, lowest level first: name, level range, zone, what it teaches, a
--                    state chip (Can tame now / At level 16), and Point me there, Map and Learned. With a rank selected: only the beasts
--                    that teach it. "Mark them all on my map", "Waypoint list", "Only ones I can tame now".
--   Families         a panel over the right column: the families as icon tiles with their diet and special abilities; Main pet, Out now,
--                    Plan saved. A click shows that family's plan (a plan is kept per family); hovering compares it with the current one.
-- Medium and Narrow: Abilities above Where to learn. Nothing here tames, feeds, trains or targets anything: buttons change the plan,
-- what shows, or add a waypoint.
local ADDON, Panoply = ...
local P = Panoply.HunterPet
local CP = Panoply.ClassPages
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local U = CP.UI
local D = Panoply.HunterPetData

P.PIP = 10                     -- a rank pip
P.TILE_W = 132                 -- a family tile in the Families panel
P.sel = nil                    -- the selected rank: { key, rank }
P.budgetMode = "max"           -- "now" (the pet out now) | "max" (level 60, loyalty 6)
P.onlyNow = false
P.familiesOpen = false

-------------------------------------------------------------------------------
-- Icon slots (spec 03 section 11)
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
P.FAMILY_ICON = { Bat = "Ability_Hunter_Pet_Bat", Bear = "Ability_Hunter_Pet_Bear", ["Bird of Prey"] = "Ability_Hunter_Pet_Owl",
  Boar = "Ability_Hunter_Pet_Boar", ["Carrion Bird"] = "Ability_Hunter_Pet_Vulture", Cat = "Ability_Hunter_Pet_Cat", Crab = "Ability_Hunter_Pet_Crab",
  Crocolisk = "Ability_Hunter_Pet_Crocolisk", Fox = "Ability_Hunter_Pet_Fox", Gorilla = "Ability_Hunter_Pet_Gorilla", Hyena = "Ability_Hunter_Pet_Hyena",
  Raptor = "Ability_Hunter_Pet_Raptor", Scorpid = "Ability_Hunter_Pet_Scorpid", Spider = "Ability_Hunter_Pet_Spider",
  Tallstrider = "Ability_Hunter_Pet_TallStrider", Turtle = "Ability_Hunter_Pet_Turtle", ["Wind Serpent"] = "Ability_Hunter_Pet_WindSerpent",
  Wolf = "Ability_Hunter_Pet_Wolf" }
-- the family's own icon; the signature ability's (Bite) where the game has no family picture
for fam, file in pairs(P.FAMILY_ICON) do
  Kit.RegisterIcon("icon.pet.family." .. fam:lower():gsub(" ", ""), { game = { I .. file, I .. "Ability_Hunter_BeastTaming" } })
end
P.DIET_ICON = { Meat = "INV_Misc_Food_14", Fish = "INV_Misc_Fish_22", Cheese = "INV_Misc_Food_03", Bread = "INV_Misc_Food_11",
  Fungus = "INV_Mushroom_02", Fruit = "INV_Misc_Food_19" }
for food, file in pairs(P.DIET_ICON) do Kit.RegisterIcon("icon.diet." .. food:lower(), { game = { I .. file, I .. "INV_Misc_Food_01" } }) end
Kit.RegisterIcon("icon.pet.happiness", { game = { "Interface\\PetPaperDollFrame\\UI-PetHappiness" }, raw = true })
-- the face of each happiness state on the game's texture (1 unhappy, 2 content, 3 happy), and its colour
P.HAPPY_CUT = { { 0.375, 0.5625, 0, 0.359375 }, { 0.1875, 0.375, 0, 0.359375 }, { 0, 0.1875, 0, 0.359375 } }
P.HAPPY_WORD = { "Unhappy", "Content", "Happy" }
P.HAPPY_TOKEN = { "state.bad", "state.warn", "state.good" }

function P:FamilySlot(fam) return "icon.pet.family." .. tostring(fam or ""):lower():gsub(" ", "") end
function P:FamilyIcon(fam)
  local how, what = Kit.ResolveIcon(self:FamilySlot(fam))
  return how ~= "missing" and what or nil
end

-------------------------------------------------------------------------------
-- The pet that is out, as the strip shows it (read only, through Compat)
-------------------------------------------------------------------------------
local function ask(name)
  local f = C.G(name)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f)
  if not ok then return nil end
  local R = C.Readable or function(v) return v end
  return R(a), R(b), R(c)
end

-- { name, family, familyName, level, loyalty, happy (1-3), points, spent, free } or nil when no pet is out
function P:Strip()
  local pet = self.pet
  if not pet then return nil end
  local out = { name = pet.name, family = pet.family, familyName = pet.familyName or (pet.family and self:FamilyName(pet.family)), level = pet.level }
  local loyalty = ask("GetPetLoyalty")
  out.loyalty = type(loyalty) == "number" and loyalty or (type(loyalty) == "string" and tonumber(loyalty:match("(%d+)")) or nil)
  local happy = ask("GetPetHappiness")
  out.happy = (type(happy) == "number" and happy >= 1 and happy <= 3) and happy or nil
  if type(pet.points) == "number" then
    out.points, out.spent = pet.points, type(pet.spent) == "number" and pet.spent or 0
    out.free = max(0, out.points - out.spent)
  end
  return out
end

function P:StripLine(st)
  local parts = {}
  parts[#parts + 1] = st.familyName or "family not known"
  if st.level then parts[#parts + 1] = ("level %d"):format(st.level) end
  if st.loyalty then parts[#parts + 1] = ("loyalty %d"):format(st.loyalty) end
  return table.concat(parts, " \194\183 ")
end

function P:PointsLine(st)
  if not (st and st.points) then return nil end
  return ("%d total \194\183 %d spent \194\183 %d free"):format(st.points, st.spent or 0, st.free or 0)
end

-------------------------------------------------------------------------------
-- The budget: for the pet now, or at level 60 with loyalty 6
-------------------------------------------------------------------------------
function P:SetBudgetMode(mode, fam)
  if mode ~= "now" and mode ~= "max" then return false end
  self.budgetMode = mode
  fam = fam or self:View()
  local st = self:Strip()
  if mode == "now" and st and st.family == fam and st.level then
    self:SetPlanLevel(fam, st.level)
    self:SetPlanLoyalty(fam, st.loyalty or 1)
  else
    self:SetPlanLevel(fam, P.MAX_LEVEL)
    self:SetPlanLoyalty(fam, P.MAX_LOYALTY)
  end
  return true
end

-- a pip's state: "have" (on the pet or learned), "plan" (in the plan), "off" (not planned), "locked" (needs a higher pet level)
function P:PipState(fam, a, r)
  local st = self:RankState(fam, a.key, r.r)
  if st == "pet" or st == "learned" then return "have" end
  if (r.lvl or 0) > self:PlanLevel(fam) then return "locked" end
  if r.r <= self:Want(fam, a.key) then return "plan" end
  return "off"
end

-- the beasts the right column lists: { { n, t, teaches = { { key, rank } }, now = can tame now, entry } }
function P:LearnRows(fam)
  local level = P.HunterLevel()
  local out = {}
  if self.sel then
    for _, t in ipairs(self:Teachers(self.sel.key, self.sel.rank)) do
      out[#out + 1] = { n = t.n, t = t, teaches = { { key = self.sel.key, rank = self.sel.rank } }, now = (t.lo or 0) <= level,
        entry = { n = t.n, t = t, teaches = { { key = self.sel.key, rank = self.sel.rank } }, first = { key = self.sel.key, rank = self.sel.rank, all = {} }, others = 0 } }
    end
    table.sort(out, function(a, b) if (a.t.lo or 0) ~= (b.t.lo or 0) then return (a.t.lo or 0) < (b.t.lo or 0) end return a.n < b.n end)
  else
    local tame = self:ToTame(fam)
    for _, e in ipairs(tame.list) do out[#out + 1] = { n = e.n, t = e.t, teaches = e.teaches, now = (e.t.lo or 0) <= level, entry = e } end
  end
  if self.onlyNow then
    local keep = {}
    for _, r in ipairs(out) do if r.now then keep[#keep + 1] = r end end
    out = keep
  end
  return out
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
local function spellIcon(id)
  local Seq = CP.Seq
  local t = Seq and Seq.read and Seq.read.iconOf and Seq.read.iconOf(id) or nil
  return t or 134400
end

local function pip(parent, x, y, state, onClick, tip, body)
  local b = CreateFrame("Button", nil, parent)
  b.panoplyGapOK = true
  b:SetSize(P.PIP, P.PIP)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  local fill = b:CreateTexture(nil, "ARTWORK"); fill:SetAllPoints(b)
  Skin.Round(fill, 3, Skin.TEX.RFill)
  local ring = b:CreateTexture(nil, "BORDER"); ring:SetAllPoints(b)
  Skin.Round(ring, 3, Skin.TEX.RLine8 or Skin.TEX.RFill)
  local gold, grey, good = Skin.colors.gold, Skin.colors.slotLine, Kit.Color("state.good")
  if state == "have" then fill:SetVertexColor(good[1], good[2], good[3], 1) ring:SetVertexColor(good[1], good[2], good[3], 1)
  elseif state == "plan" then fill:SetVertexColor(gold[1], gold[2], gold[3], 0.15) ring:SetVertexColor(gold[1], gold[2], gold[3], 1)
  else fill:SetVertexColor(grey[1], grey[2], grey[3], state == "locked" and 0.25 or 0.5) ring:SetVertexColor(grey[1], grey[2], grey[3], 1) end
  if state == "locked" then
    local l = b:CreateTexture(nil, "OVERLAY")
    l:SetPoint("CENTER", b, "CENTER", 0, 0); l:SetSize(P.PIP + 2, P.PIP + 2)
    Kit.Icon(l, "icon.state.locked", { size = P.PIP + 2 })
    b.lock = l
  end
  b.state = state
  Skin.Tooltip(b, tip, body)
  b:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self, button) if onClick then onClick(button) end end)
  return b
end

-- the strip at the top; returns its height
local function drawStrip(p, holder, w, fam)
  local st = P:Strip()
  local y = 0
  local ix = 0
  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32); icon:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  Kit.Icon(icon, P:FamilySlot(st and st.family or fam), { size = 32 })
  p.petIcon = icon
  ix = 32 + SP.s
  -- buttons at the right: Families, Feed, stable master
  local btns = {}
  local function button(label, fn, tip, body)
    local b = Skin.Button(holder, label, 80, 24, fn, tip or label, body)
    Skin.FitButton(b, 60, 140)
    btns[#btns + 1] = b
    return b
  end
  p.familiesBtn = button(P.familiesOpen and "Close families" or "Families", function() P.familiesOpen = not P.familiesOpen Menu:RefreshCurrent() end,
    "Families", "Every pet family: what it eats and its special abilities. Click one to plan for it.")
  p.feedBtn = button("Feed", function(b) P:OpenFeedMenu(b, st and st.family or fam) end, "Feed",
    "What this family eats. You feed your pet yourself, with the game's Feed Pet.")
  local stable = U.IconButton(holder, "Arrow", nil, 24, function() P:GoToStable() end, "Point me to the stable master",
    "Adds the nearest stable master your map knows to your waypoints.")
  btns[#btns + 1] = stable
  p.stableBtn = stable
  local bx = w
  for i = #btns, 1, -1 do
    local b = btns[i]
    bx = bx - b:GetWidth()
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, 0)
    bx = bx - SP.s
  end
  local tw = max(80, bx - ix - SP.s)
  local name = st and st.name or "No pet out"
  local nh = U.Text(holder, ix, 0, tw, 14, "text.primary", name, false, true)
  local sub = st and P:StripLine(st) or ("Planning for: %s"):format(P:FamilyName(fam))
  local sh, sfs = U.Text(holder, ix, -nh - 1, tw, 11, "text.muted", sub, false)
  local line2 = -nh - 1 - sh - 2
  local x2 = ix
  if st and st.happy then
    local face = holder:CreateTexture(nil, "ARTWORK")
    face:SetSize(16, 16); face:SetPoint("TOPLEFT", holder, "TOPLEFT", x2, line2)
    local how = Kit.Icon(face, "icon.pet.happiness", { size = 16 })
    if how ~= "missing" and face.SetTexCoord then local c = P.HAPPY_CUT[st.happy] face:SetTexCoord(c[1], c[2], c[3], c[4]) end
    p.happyFace = face
    local hw = U.Word(holder, x2 + 18, line2 - 1, 11, P.HAPPY_TOKEN[st.happy], P.HAPPY_WORD[st.happy], 100)
    x2 = x2 + 18 + hw + SP.m
  end
  local pts = P:PointsLine(st)
  if pts then U.Word(holder, x2, line2 - 1, 11, "text.muted", "Training points: " .. pts, max(60, w - x2)) end
  p.petStrip = { name = name, sub = sub, points = pts, happy = st and st.happy }
  return max(32, -line2 + 16) + SP.m
end

-- the budget bar and the two choices; returns the height
local function drawBudget(p, holder, x, y, w, fam)
  local st = P:Strip()
  local b = P:Budget(fam)
  local y0 = y
  local nowLabel = (st and st.family == fam and st.level) and ("For %s now (level %d, loyalty %d)"):format(st.name, st.level, st.loyalty or 1) or nil
  local tabs = {}
  if nowLabel then
    local t1 = Skin.Tab(holder, nowLabel, 160, function() P:SetBudgetMode("now", fam) Menu:RefreshCurrent() end, "For the pet now", "Counts the training points your pet has today.")
    t1.panoplyPicker = true
    t1:SetActive(P.budgetMode == "now")
    tabs[#tabs + 1] = t1
  end
  local t2 = Skin.Tab(holder, ("At level %d, loyalty %d"):format(P.MAX_LEVEL, P.MAX_LOYALTY), 140, function() P:SetBudgetMode("max", fam) Menu:RefreshCurrent() end,
    "At the top level", "Counts the training points a pet of the top level and loyalty has.")
  t2.panoplyPicker = true
  t2:SetActive(P.budgetMode ~= "now" or not nowLabel)
  tabs[#tabs + 1] = t2
  local bh = Skin.FlowButtons(holder, tabs, x, y, w, SP.s, 100)
  y = y - bh - SP.s
  p.budgetTabs = tabs
  local bar = Kit.ProgressBar(holder, { h = 7, accent = Kit.ClassColor("HUNTER") })
  bar:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
  if bar.SetBarWidth then bar:SetBarWidth(w) end
  bar:SetValue(min(b.spent, max(1, b.budget)), max(1, b.budget))
  y = y - 7 - SP.xs
  local words = ("The plan uses %d of %d training points"):format(b.spent, b.budget) .. (b.left < 0 and (", %d too many."):format(-b.left) or ".")
    .. (b.unknown > 0 and (" %d %s no known cost."):format(b.unknown, b.unknown == 1 and "rank has" or "ranks have") or "")
  local h = U.Text(holder, x, y, w, 11, b.left < 0 and "state.warn" or "text.muted", words, true)
  y = y - h - SP.m
  p.budget = { bar = bar, words = words, data = b }
  return y0 - y
end

-- the Abilities list; returns the height
local function drawAbilities(p, holder, x, y, w, fam)
  local y0 = y
  local hdr = Kit.SectionHeader(holder, { title = "Abilities", help = "Filled: your pet has it or you have learned it. Gold outline: in your plan. Grey: not planned. A lock: needs a higher pet level. Click a rank to see where to learn it. The ranks tick themselves when the game says your pet learned one; right-click a rank to tick or untick it by hand. Use - and + to change the rank you plan." })
  y = y - hdr:Layout(x, y, w) - SP.s
  y = y - drawBudget(p, holder, x, y, w, fam)
  p.abilityRows = {}
  local level = P:PlanLevel(fam)
  for _, a in ipairs(P:Abilities(fam)) do
    local want = P:Want(fam, a.key)
    local rowY = y
    local first = a.ranks[1]
    U.Icon(holder, x, y, 22, spellIcon(first and (first.pet or first.teach)))
    local nx = x + 22 + SP.s
    -- right side: points, - and +
    local plus = Skin.IconButton(holder, "+", 18, function() P:StepWant(fam, a.key, 1) Menu:RefreshCurrent() end, "One rank more", "Plans the next rank of " .. a.key .. ".")
    plus:SetPoint("TOPLEFT", holder, "TOPLEFT", x + w - 18, y - 2)
    local minus = Skin.IconButton(holder, "-", 18, function() P:StepWant(fam, a.key, -1) Menu:RefreshCurrent() end, "One rank less", "Plans one rank less of " .. a.key .. ".")
    minus:SetPoint("TOPLEFT", holder, "TOPLEFT", x + w - 18 - 2 - 18, y - 2)
    local rank = min(want, P.MaxRankAt(a, level))
    local rd = rank >= a.first and P:RankDef(a.key, rank) or nil
    local cost = rd and (rd.tp and ("%d TP"):format(rd.tp) or "? TP") or "out"
    local cw, _ch, cfs = U.Word(holder, 0, y - 3, 11, "text.muted", cost, 60)
    cfs:ClearAllPoints(); cfs:SetPoint("TOPRIGHT", holder, "TOPLEFT", x + w - 40 - SP.s, y - 3)
    local room = max(60, w - (nx - x) - 40 - SP.s - cw - SP.s)
    local nameW = min(room, 120)
    U.Text(holder, nx, y - 3, nameW, 12, "text.primary", a.key, false, true)
    -- the pips
    local px = nx + nameW + SP.s
    local pips = {}
    for _, r in ipairs(a.ranks) do
      if px + P.PIP > nx + room then break end
      local state = P:PipState(fam, a, r)
      local sel = P.sel and P.sel.key == a.key and P.sel.rank == r.r
      local tip = ("%s rank %d"):format(a.key, r.r)
      local body = ({ have = "Your pet has it, or you have learned it.", plan = "In your plan.", off = "Not in your plan.",
        locked = ("Needs pet level %d."):format(r.lvl or 0) })[state] .. (r.tp and (" Costs %d training points."):format(r.tp) or "")
        .. (a.kind == "trainer" and " Bought from a pet trainer." or " Learned by taming a beast that knows it.")
        .. "\n\nClick: where to learn it. Right-click: tick it learned, or untick it."
      local b = pip(holder, px, y - 6, state, function(button)
        if button == "RightButton" then
          P:SetLearned(a.key, r.r, not P:Learned(a.key, r.r))
        elseif sel then P.sel = nil
        else P.sel = { key = a.key, rank = r.r } end
        Menu:RefreshCurrent()
      end, tip, body)
      b.panoplyRank, b.panoplyKey, b.panoplySelected = r.r, a.key, sel or nil
      if sel then
        local mark = holder:CreateTexture(nil, "OVERLAY")
        Skin.Solid(mark, Kit.Color("gold.title"), 1)
        mark:SetSize(P.PIP, 2); mark:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
      end
      pips[#pips + 1] = b
      px = px + P.PIP + 3
    end
    p.abilityRows[#p.abilityRows + 1] = { a = a, want = want, pips = pips, cost = cost, plus = plus, minus = minus }
    y = rowY - 24 - SP.xs
  end
  return y0 - y
end

-- the Where to learn list; returns the height
local function drawLearn(p, holder, x, y, w, fam)
  local y0 = y
  local title = P.sel and ("Where to learn %s rank %d"):format(P.sel.key, P.sel.rank) or "Where to learn"
  local help = "The next beasts to tame for your plan, lowest level first, each with what it teaches. Click a rank on the left to see only the beasts that teach it."
  if C.IsForever() then help = help .. "\n\nWoW Forever: Skyborne hunters start on Zephras Isle with their own taming quests; follow the quest log for those." end
  local hdr = Kit.SectionHeader(holder, { title = title, help = help })
  y = y - hdr:Layout(x, y, w) - SP.s
  -- the actions
  local acts = {}
  local markAll = Skin.Button(holder, "Mark them all on my map", 180, 24, function() P:MarkAll(fam) end, "Mark them all on my map",
    "Adds every beast of the list that has a known place to your waypoints, in the list's order.")
  Skin.FitButton(markAll, 120, 220)
  acts[#acts + 1] = markAll
  local wl = Skin.Button(holder, "Waypoint list", 110, 24, function() P:OpenWaypoints() end, "Waypoint list", "Opens the list of your waypoints on the Map page.")
  Skin.FitButton(wl, 90, 160)
  acts[#acts + 1] = wl
  if P.sel then
    local all = Skin.Button(holder, "All ranks", 90, 24, function() P.sel = nil Menu:RefreshCurrent() end, "All ranks", "Lists the next beasts for your whole plan again.")
    Skin.FitButton(all, 70, 140)
    acts[#acts + 1] = all
  end
  local bh = Skin.FlowButtons(holder, acts, x, y, w, SP.s, 80)
  y = y - bh - SP.s
  local only = Skin.Check(holder, "Only ones I can tame now", { get = function() return P.onlyNow end, set = function(on) P.onlyNow = on and true or false Menu:RefreshCurrent() end },
    nil, "Hides the beasts above your level.", true)
  only:ClearAllPoints(); only:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
  local _, oh = only:FitLabel(w - 27)
  y = y - oh - SP.s
  p.learnActions, p.onlyNow = acts, only
  local rows = P:LearnRows(fam)
  p.learnRows = {}
  if #rows == 0 then
    local words = P.sel and "No beast is known to teach this rank yet. A pet trainer may sell it, or it may be learned elsewhere."
      or "Nothing to tame for your plan: every rank it wants is on your pet or learned."
    y = y - U.Text(holder, x, y, w, 12, "text.muted", words, true) - SP.s
  end
  local level = P.HunterLevel()
  for _, r in ipairs(rows) do
    local rowY = y
    local chip = Kit.StatusChip(holder, r.now and "now" or "soon", r.now and "Can tame now" or ("At level %d"):format(r.t.lo or 0))
    local btnW = 3 * 20 + 2 * SP.xs
    local room = max(60, w - btnW - SP.s - chip:GetWidth() - SP.s)
    local nw, nh = U.Word(holder, x, y, 12, "text.primary", r.n, room, true)
    chip:SetPoint("TOPLEFT", holder, "TOPLEFT", x + nw + SP.s, y)
    local bx = x + w - btnW
    local go = U.IconButton(holder, "Arrow", nil, 20, function() P:Mark(r.entry) end, "Point me there", "Adds this beast to your waypoints; the arrow follows it.")
    go:SetPoint("TOPLEFT", holder, "TOPLEFT", bx, y)
    local map = U.IconButton(holder, "Map", nil, 20, function() P:OpenMapFor(r.entry) end, "Map", "Opens the Map page, where this beast's waypoint shows.")
    map:SetPoint("TOPLEFT", holder, "TOPLEFT", bx + 20 + SP.xs, y)
    local learned = U.IconButton(holder, nil, "icon.state.done", 20, function() P:MarkLearned(r.entry) Menu:RefreshCurrent() end, "Learned",
      "Ticks what this beast teaches as learned, so it leaves the list.")
    learned:SetPoint("TOPLEFT", holder, "TOPLEFT", bx + 2 * (20 + SP.xs), y)
    local teach = {}
    for _, t in ipairs(r.teaches or {}) do teach[#teach + 1] = ("%s %d"):format(t.key, t.rank) end
    local line = P:WhereText(r.t, true) .. (#teach > 0 and (" \194\183 teaches " .. table.concat(teach, ", ")) or "")
    local sh = U.Text(holder, x, y - max(20, nh + 2), w - btnW - SP.s, 11, "text.muted", line, true)
    p.learnRows[#p.learnRows + 1] = { row = r, chip = chip, go = go, map = map, learned = learned, line = line }
    y = rowY - max(20, nh + 2) - sh - SP.s
  end
  -- the tames this account has recorded (PetLog.lua): the switch, how many, and the newest few (kept from the 0.9.1 To tame section)
  local PL = P.PetLog
  if PL and not P.sel then
    y = y - SP.s
    local on = PL:IsOn()
    local sw = Skin.Check(holder, "Record my tames", { get = function() return PL:IsOn() end, set = function(v) PL:SetOn(v) Menu:RefreshCurrent() end },
      nil, "Writes down each tame and each new ability rank your pet shows, with what the game itself reports, in a file of its own on this computer. It only watches.", true)
    sw:ClearAllPoints(); sw:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
    local _, swh = sw:FitLabel(w - 27)
    y = y - swh - SP.xs
    p.petLogSwitch = sw
    local tames, ranks = PL:Counts()
    local words = on and "Recording is on: it only watches." or "Recording is off: nothing new is written down. What is recorded stays."
    if tames == 0 then words = words .. " No tame is recorded yet."
    else words = words .. (" %d %s recorded%s."):format(tames, tames == 1 and "tame" or "tames", ranks > 0 and (" and %d new %s seen on a pet"):format(ranks, ranks == 1 and "rank" or "ranks") or "") end
    y = y - U.Text(holder, x, y, w, 11, "text.muted", words, true) - SP.xs
    p.petLogRows = {}
    for _, e in ipairs(PL:Recent(PL.SHOW)) do
      local h, fs = U.Text(holder, x, y, w, 11, "text.primary", PL.Words(e), true)
      p.petLogRows[#p.petLogRows + 1] = fs
      y = y - h - 2
    end
  end
  return y0 - y
end

-- the families panel (over the right column); returns the height
local function drawFamilies(p, holder, x, y, w, fam)
  local y0 = y
  local hdr = Kit.SectionHeader(holder, { title = "Families", help = "Every pet family this game has: what it eats and its special abilities. Growl and the resistances are left off: every family learns them. Click one to plan for it; a plan is kept for each family." })
  y = y - hdr:Layout(x, y, w) - SP.s
  local cols = max(1, floor((w + SP.s) / (P.TILE_W + SP.s)))
  local tw = floor((w - (cols - 1) * SP.s) / cols)
  local main, out = P:Main(), P.pet and P.pet.family
  local saved = {}
  for _, f in ipairs(P:SavedPlans()) do saved[f] = true end
  p.familyTiles = {}
  local cur = {}
  for _, a in ipairs(P:Abilities(fam)) do cur[a.key] = true end
  local i, rowH = 0, 0
  local ty = y
  for _, f in ipairs(P:Families()) do
    local col = i % cols
    if col == 0 and i > 0 then ty = ty - rowH - SP.s rowH = 0 end
    local tile = CreateFrame("Button", nil, holder)
    tile.panoplyGapOK = true
    tile:SetPoint("TOPLEFT", holder, "TOPLEFT", x + col * (tw + SP.s), ty)
    -- (everything on the tile is drawn on its surface, so the words sit inside the card they belong to)
    local surf = Kit.Surface(tile, f == fam and 2 or 1)
    surf:SetAllPoints(tile)
    local ic = surf:CreateTexture(nil, "ARTWORK")
    ic:SetSize(24, 24); ic:SetPoint("TOPLEFT", surf, "TOPLEFT", 6, -6)
    Kit.Icon(ic, P:FamilySlot(f), { size = 24 })
    local nh = U.Text(surf, 36, -6, tw - 42, 12, "text.primary", P:FamilyName(f), false, true)
    -- the diet, as small food icons
    local dx = 36
    for _, food in ipairs((D.families[f] or {}).diet or {}) do
      local t = surf:CreateTexture(nil, "ARTWORK")
      t:SetSize(12, 12); t:SetPoint("TOPLEFT", surf, "TOPLEFT", dx, -6 - nh - 2)
      Kit.Icon(t, "icon.diet." .. food:lower(), { size = 12 })
      dx = dx + 13
    end
    -- its special abilities: the ones few families share
    local sx, sy = 6, -6 - max(24, nh + 2 + 12) - 4
    local special = {}
    for _, a in ipairs(P:Abilities(f)) do
      local users = a.def.users
      if users ~= "all" and type(users) == "table" and #users <= 4 then
        local r1 = a.ranks[1]
        local t = surf:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16); t:SetPoint("TOPLEFT", surf, "TOPLEFT", sx, sy)
        t:SetTexture(spellIcon(r1 and (r1.pet or r1.teach)))
        if t.SetTexCoord then t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        special[#special + 1] = a.key
        sx = sx + 18
      end
    end
    local by = sy - 18
    -- badges
    local badges = {}
    if f == main then badges[#badges + 1] = "Main pet" end
    if f == out then badges[#badges + 1] = "Out now" end
    if saved[f] then badges[#badges + 1] = "Plan saved" end
    local bx = 6
    for _, word in ipairs(badges) do
      local chip = Kit.StatusChip(surf, "state.idle", word)
      local cw, ch = chip:Set("state.idle", word)
      if bx + cw > tw - 6 and bx > 6 then bx = 6 by = by - ch - 2 end
      chip:SetPoint("TOPLEFT", surf, "TOPLEFT", bx, by)
      bx = bx + cw + 3
      if bx > tw then bx = 6 end
    end
    local th = -by + (#badges > 0 and 20 or 4)
    tile:SetSize(tw, th)
    rowH = max(rowH, th)
    -- hover: compared with the family shown now
    local more, less = {}, {}
    local theirs = {}
    for _, a in ipairs(P:Abilities(f)) do theirs[a.key] = true if not cur[a.key] then more[#more + 1] = a.key end end
    for k in pairs(cur) do if not theirs[k] then less[#less + 1] = k end end
    table.sort(more) table.sort(less)
    local body = ("Eats: %s."):format(P:DietText(f))
    if #special > 0 then body = body .. "\nIts own: " .. table.concat(special, ", ") .. "." end
    if f ~= fam then
      if #more > 0 then body = body .. ("\nCompared with %s, it can also learn: %s."):format(P:FamilyName(fam), table.concat(more, ", ")) end
      if #less > 0 then body = body .. ("\nIt cannot learn: %s."):format(table.concat(less, ", ")) end
    end
    body = body .. "\n\nClick to plan for this family."
    Skin.Tooltip(tile, P:FamilyName(f), body)
    tile:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
    tile:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    tile:SetScript("OnClick", function() P:SetView(f) P.sel = nil P.familiesOpen = false Menu:RefreshCurrent() end)
    tile.panoplyFamily, tile.panoplyBadges = f, badges
    p.familyTiles[#p.familyTiles + 1] = tile
    i = i + 1
  end
  y = ty - rowH - SP.s
  return y0 - y
end

function P:OpenFeedMenu(owner, fam)
  local items = { { header = ("%s eats"):format(self:FamilyName(fam or self:View())) } }
  for _, food in ipairs((D.families[fam or self:View()] or {}).diet or {}) do
    items[#items + 1] = { text = food, tip = "Feed your pet with the game's Feed Pet: cast it, then click a food in your bags.", func = function() end }
  end
  items[#items + 1] = { divider = true }
  items[#items + 1] = { text = "Food your pet likes keeps it happy and loyal.", disabled = true, func = function() end }
  return Skin.Menu(owner, items, { width = 220 })
end

function P:GoToStable()
  local N = Panoply.Map and Panoply.Map.Navigate
  if not (N and N.Go) then Panoply:Print("The Map feature is not in this build, so there is no stable master to point at.") return false end
  return N:Go({ kind = "type", name = "Stable master", type = "placeStable" })
end

function P:OpenWaypoints()
  if Panoply.Menu and Panoply.Menu.Open then
    if Panoply.History then Panoply.History:Via("link") end
    return Panoply.Menu:Open("map")
  end
end

-- Map: the beast's waypoint is set (as Point me there), then the Map page opens (spec 03 section 10)
function P:OpenMapFor(entry)
  self:Mark(entry, false)
  return self:OpenWaypoints()
end

-- opens the Class page on the Pet tab (the Hunter's)
function P:OpenPage()
  if CP and CP.Open then return CP:Open("HUNTER", "pet") end
end

CP.TABS.pet = {
  Sig = function(v, w)
    local st = P:Strip()
    return table.concat({ P.rev or 0, tostring(P.PetLog and P.PetLog:IsOn()), tostring(P.PetLog and select(1, P.PetLog:Counts())), tostring(P:View()), tostring(P.sel and (P.sel.key .. P.sel.rank)), P.budgetMode, tostring(P.onlyNow),
      tostring(P.familiesOpen), v.band, P.HunterLevel(), tostring(Panoply.SpecTrainer and Panoply.SpecTrainer:PlanValue()), st and (tostring(st.name) .. tostring(st.level) .. tostring(st.happy) .. tostring(st.loyalty) .. tostring(st.points) .. tostring(st.spent)) or "-" }, "|")
  end,
  Draw = function(p, holder, w, viewH, v)
    if holder.drawn then return holder.panoplyH end
    holder.drawn = true
    local fam = P:View()
    if P.sel and not P:Ability(fam, P.sel.key) then P.sel = nil end
    local y = -drawStrip(p, holder, w, fam)
    -- 0.9.9.4: the talent build this Hunter follows and its spec, on the shared build card (Modules/SpecTrainer/BuildCard.lua)
    p.petBuildCard = nil
    local ST = Panoply.SpecTrainer
    local build = ST and Panoply.Modules:IsOn("spectrainer") and ST:FollowedBuild() or nil
    if build and build.source == "public" then
      local facts = ST:BuildFacts(build)
      local card = ST:BuildCard(holder, { mode = "line", actions = { "change" } })
      card:Set(facts, { mark = facts.specName and (facts.specName .. " spec") or nil })
      local ch = card:Fit(min(w, 640))
      card:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
      p.petBuildCard = card
      y = y - ch - SP.m
    end
    local wide = v.band == "wide"
    if wide then
      local gap = SP.l + SP.s
      local lw = floor((w - gap) * 0.55)
      local rw = w - gap - lw
      local lh = drawAbilities(p, holder, 0, y, lw, fam)
      local rh = P.familiesOpen and drawFamilies(p, holder, lw + gap, y, rw, fam) or drawLearn(p, holder, lw + gap, y, rw, fam)
      y = y - max(lh, rh)
    else
      if P.familiesOpen then y = y - drawFamilies(p, holder, 0, y, w, fam) - SP.m end
      y = y - drawAbilities(p, holder, 0, y, w, fam) - SP.m
      if not P.familiesOpen then y = y - drawLearn(p, holder, 0, y, w, fam) end
    end
    holder.panoplyH = -y + SP.s
    return holder.panoplyH
  end,
}

-- the pet, a tame, a rank learned: the Pet tab follows it
Panoply:Listen("HUNTERPET_CHANGED", function()
  if Menu.current == "class" and CP.topic == "pet" and Menu.frame and Menu.frame:IsShown() and not C.InCombat() then Menu:RefreshCurrent() end
end)
