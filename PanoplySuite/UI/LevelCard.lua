-- Panoply Suite 0.8.4: the level-up card. When the character gains a level, one small card says what the new level
-- brings, each line from data the add-on already has (nothing is invented here; a line with nothing to say is left out):
--   SPELLS       the spells your plan buys at the trainer now, and what they cost      (Spec & Trainer: ST:Waiting)
--   NEXT TALENT  the talent your plan takes next                                        (Spec & Trainer: ST:Next)
--   WEAR NOW     gear in your bags that this level lets you put on                     (the game's own "requires level")
--   DUNGEONS     dungeons whose monsters are around your level                         (Map module: the dungeon list)
-- The buttons under the lines open the page each line is about. They go to the class pages (Panoply.ClassPages:Open(class,
-- topic)) and to "At your level" (Panoply.AtLevel:Open()) when those are in this build, and to the pages this build always
-- had when they are not (Class & Spec, the talent planner, the bag window, the dungeon maps). A button with nowhere to
-- go is not shown, and a page that fails to open never breaks the card.
-- The card waits for the end of a fight. It sits at the top middle of the screen when nothing else is there; when the
-- trainer message or the next-talent card (Spec & Trainer) are up it goes beside them, or under them, wherever it fits
-- without covering them or the game's talent window; on a screen with no room at all it waits until they are gone
-- (LC:Place). It can be dragged, and goes away on "Got it" or by itself after a while.
-- It never learns, buys, equips or travels: the player does that on the pages it opens.
local ADDON, Panoply = ...
local Skin, C = Panoply.Skin, Panoply.Compat
local SP, TH = Skin.SP, Skin.TextHeight
local LC = {}
Panoply.LevelCard = LC

LC.WIDTH = 296
LC.TOP = 96                   -- its top edge, this far below the top of the screen (the same line as the trainer message)
LC.SIDE_TOP = 250             -- ...and when it sits beside the trainer message: below the minimap's corner
LC.GAP, LC.EDGE = 10, 8       -- room kept to another card, and to the edge of the screen
LC.WAIT_S, LC.WAIT_TRIES = 1, 180   -- no room yet: look again this often, this many times, then let this level's card go
LC.STAY_S = 60                -- seconds it stays when the mouse is not on it
LC.MAX_NAMES = 3              -- names listed on a line before "and 2 more"

Panoply.defaults.account.levelCard = true

-- "A", "A and B", "A, B and C", "A, B, C and 2 more"
function LC.Names(list, max)
  max = max or LC.MAX_NAMES
  local out = {}
  for i = 1, math.min(#list, max) do out[#out + 1] = list[i] end
  if #list > max then out[#out + 1] = (#list - max) .. " more" end
  if #out <= 1 then return out[1] or "" end
  return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
end

-------------------------------------------------------------------------------
-- The data of each line
-------------------------------------------------------------------------------
local function stOn() return Panoply.SpecTrainer ~= nil and Panoply.Modules:IsOn("spectrainer") end

function LC.Spells(level)
  if not stOn() then return nil end
  local ST = Panoply.SpecTrainer
  local ok, p = pcall(ST.Player, ST)
  if not ok or type(p) ~= "table" then return nil end
  if level then p.level = level end
  local okW, w = pcall(ST.Waiting, ST, p)
  if not okW or type(w) ~= "table" or #w.list == 0 then return nil end
  local names = {}
  for _, r in ipairs(w.list) do names[#names + 1] = r.name end
  return { count = #w.list, cost = w.cost,
    text = ("%d to buy at your trainer, %s: %s."):format(#w.list, ST.Money(w.cost), LC.Names(names)) }
end

function LC.Talent()
  if not stOn() then return nil end
  local ST = Panoply.SpecTrainer
  local ok, n = pcall(ST.Next, ST)
  if not ok or type(n) ~= "table" or not n.tal then return nil end
  -- (0.9.9.4: and the build it comes from)
  local from = ST.BuildWords and ST:BuildWords() or nil
  return { name = n.tal.name, from = from, text = ("%s, rank %d of %d%s."):format(n.tal.name, n.rank, n.tal.ranks, from and (", from " .. from) or "") }
end

-- gear in the bags that needs exactly this level, and that this class can ever wear (the vendor helper's own table)
function LC.Wear(level)
  local classFile = (C.PlayerInfo() or {}).classFile
  local Mer = Panoply.Merchant
  local names, seen = {}, {}
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, C.NumSlots(bag) do
      local i = C.SlotInfo(bag, slot)
      if i and i.itemID and not seen[i.itemID] then
        local ii = C.ItemInfo(i.link or i.itemID)
        if ii and ii.name and (ii.equipLoc or "") ~= "" and ii.equipLoc ~= "INVTYPE_BAG" and tonumber(ii.minLevel) == level
            and not (Mer and Mer.Unusable and Mer.Unusable(ii, classFile)) then
          seen[i.itemID] = true
          names[#names + 1] = ii.name
        end
      end
    end
  end
  if #names == 0 then return nil end
  table.sort(names)
  return { names = names, text = ("In your bags: %s."):format(LC.Names(names)) }
end

-- dungeons around this level (the dungeon list's own "Near my level" rule); the ones that open at this level come first
function LC.Dungeons(level)
  local Ins = Panoply.Map and Panoply.Map.Instances
  if not (Ins and Ins.All and Panoply.Modules:IsOn("map")) then return nil end
  local ok, all = pcall(Ins.All, Ins)
  if not ok or type(all) ~= "table" then return nil end
  local fresh, rest = {}, {}
  for _, inst in ipairs(all) do
    local mobs = inst.mobs
    if inst.kind == "dungeon" and type(mobs) == "table" and mobs[1] and mobs[2] then
      local from = math.max(inst.enter or 0, mobs[1] - 4)
      if level >= from and level <= mobs[2] + 6 then
        local list = (from == level) and fresh or rest
        list[#list + 1] = inst.name
      end
    end
  end
  local names = {}
  for _, n in ipairs(fresh) do names[#names + 1] = n end
  for _, n in ipairs(rest) do names[#names + 1] = n end
  if #names == 0 then return nil end
  return { names = names, new = #fresh, text = (#fresh > 0 and "New at this level: %s." or "Around your level: %s."):format(LC.Names(names)) }
end

-- Everything the card says for `level` (the level you are when none is given).
function LC:Data(level)
  level = tonumber(level) or (C.XP())
  local d = { level = level, rows = {} }
  local function add(key, label, v) if v then d[key] = v d.rows[#d.rows + 1] = { key = key, label = label, text = v.text } end end
  add("spells", "SPELLS", LC.Spells(level))
  add("talent", "NEXT TALENT", LC.Talent())
  add("wear", "WEAR NOW", LC.Wear(level))
  add("dungeons", "DUNGEONS", LC.Dungeons(level))
  return d
end

-------------------------------------------------------------------------------
-- Where the buttons go
-------------------------------------------------------------------------------
-- A page another part of 0.8.4 brings, opened only when it is there; an error in it is noted and the card carries on.
local function try(obj, method, ...)
  local o = Panoply[obj]
  if type(o) ~= "table" or type(o[method]) ~= "function" then return false end
  local ok, err = pcall(o[method], o, ...)
  if not ok then Panoply:Debug("level card", obj, method, err) return false end
  return true
end

-- "At your level" (Panoply.AtLevel:Open()); without it, the dungeon maps. Returns what opened, or nil.
function LC:OpenAtLevel()
  if try("AtLevel", "Open") then return "atlevel" end
  local Ins = Panoply.Map and Panoply.Map.Instances
  if Ins and Panoply.Modules:IsOn("map") and type(Ins.Open) == "function" then
    local ok = pcall(Ins.Open, Ins)
    if ok then return "instances" end
  end
  return nil
end

-- The class page topic of a line ("spells", "talents", "gear"); without the class pages, the page this build has for
-- it. Returns what opened, or nil when there is nowhere to go.
function LC:OpenTopic(topic)
  local class = (C.PlayerInfo() or {}).classFile
  if try("ClassPages", "Open", class, topic) then return "classpages" end
  local ST = Panoply.SpecTrainer
  if topic == "spells" then
    if stOn() and type(ST.OpenClassSpec) == "function" and pcall(ST.OpenClassSpec, ST, "spells") then return "class" end
  elseif topic == "talents" then
    if stOn() and type(ST.OpenPlanner) == "function" and pcall(ST.OpenPlanner, ST) then return "planner" end
  elseif topic == "gear" then
    local B = Panoply.Bags
    if B and B.active and type(B.Open) == "function" and pcall(B.Open, B, "bags") then return "bags" end
  end
  return nil
end

-- Is there anywhere for a button to go? (asked before a button is shown; nothing is opened)
function LC:CanOpen(what)
  local function has(obj, method) return type(Panoply[obj]) == "table" and type(Panoply[obj][method]) == "function" end
  if what == "atlevel" then
    return has("AtLevel", "Open") or (Panoply.Map ~= nil and Panoply.Map.Instances ~= nil and Panoply.Modules:IsOn("map"))
  end
  if has("ClassPages", "Open") then return true end
  if what == "spells" or what == "talents" then return stOn() end
  if what == "gear" then return Panoply.Bags ~= nil and Panoply.Bags.active and true or false end
  return false
end

-- { key, label, tip body, what it opens } for the lines the card has
LC.BUTTONS = {
  { row = "spells", topic = "spells", label = "Spells", tip = "Opens the spells to buy at your trainer." },
  { row = "talent", topic = "talents", label = "Talents", tip = "Opens your talent plan." },
  { row = "wear", topic = "gear", label = "Gear", tip = "Opens your gear page, or your bags." },
  { row = "dungeons", atLevel = true, label = "At your level", tip = "Opens what there is to do at your level: dungeons and more." },
}

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------
function LC:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteLevelCard", UIParent)
  f.panoplyBox = true
  f:SetFrameStrata("HIGH")
  f:SetSize(LC.WIDTH, 120)
  f:SetPoint("TOP", UIParent, "TOP", 0, -LC.TOP)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  if f.SetMovable then
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  end
  Skin.Panel(f, 0.97, true, "M")
  f.crest = f:CreateTexture(nil, "ARTWORK"); f.crest:SetSize(30, 30); Skin.Logo(f.crest)
  f.head = Skin.Heading(f, 16)
  f.sub = Skin.Ink(f, 11, Skin.colors.inkSoft)
  f.rows = {}
  for i = 1, 4 do
    f.rows[i] = { label = Skin.Label(f, 10, Skin.colors.gold), text = Skin.Ink(f, 12) }
  end
  f.none = Skin.Ink(f, 12, Skin.colors.inkSoft)
  f.none:SetText("Nothing new to buy, wear or visit at this level.")
  f.buttons, f.byRow = {}, {}
  for _, def in ipairs(LC.BUTTONS) do
    local b = Skin.Button(f, def.label, 90, 26, function()
      local opened = def.atLevel and LC:OpenAtLevel() or (not def.atLevel and LC:OpenTopic(def.topic)) or nil
      if opened then f:Hide() end
    end, def.label, def.tip)
    b.panoplyDef = def
    f.buttons[#f.buttons + 1] = b
    f.byRow[def.row] = b
  end
  f.ok = Skin.Button(f, "Got it", 80, 26, function() f:Hide() end, "Got it", "Closes the card. It comes back at your next level.")
  f.buttons[#f.buttons + 1] = f.ok
  f:SetScript("OnUpdate", function(self, e)
    if self.IsMouseOver and self:IsMouseOver() then self.left = math.max(self.left or 0, 5) return end
    self.left = (self.left or 0) - (e or 0)
    if self.left <= 0 then self:Hide() end
  end)
  f:Hide()
  self.frame = f
  return f
end

function LC:Layout(d)
  local f = self.frame
  local pad = 16
  local w = LC.WIDTH - 2 * pad
  local y = -14
  f.crest:ClearAllPoints(); f.crest:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y + 1)
  f.head:SetText(("Level %d"):format(d.level))
  f.head:ClearAllPoints(); f.head:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 40, y); f.head:SetWidth(w - 40)
  local hy = y - TH(f.head, w - 40) - 2
  f.sub:SetText("What your new level brings")
  f.sub:ClearAllPoints(); f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 40, hy); f.sub:SetWidth(w - 40)
  y = math.min(hy - TH(f.sub, w - 40), y - 32) - SP.m
  for i, r in ipairs(f.rows) do
    local row = d.rows[i]
    if row then
      r.label:SetText(row.label); r.text:SetText(row.text)
      r.label:ClearAllPoints(); r.label:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y); r.label:SetWidth(w)
      y = y - TH(r.label, w) - 2
      r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y); r.text:SetWidth(w)
      local th = TH(r.text, w); r.text:SetHeight(th)
      y = y - th - SP.s
      r.label:Show(); r.text:Show()
    else r.label:Hide(); r.text:Hide() end
  end
  if #d.rows == 0 then
    f.none:ClearAllPoints(); f.none:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y); f.none:SetWidth(w)
    local nh = TH(f.none, w); f.none:SetHeight(nh)
    y = y - nh - SP.s
    f.none:Show()
  else f.none:Hide() end
  -- a button for each line that is there and has somewhere to go, then Got it
  for _, b in ipairs(f.buttons) do
    local def = b.panoplyDef
    if def then
      local on = d[def.row] ~= nil and LC:CanOpen(def.atLevel and "atlevel" or def.topic)
      b.panoplyFlowSkip = (not on) or nil
      if on then b:Show() else b:Hide() end
    end
  end
  y = y - SP.xs
  local bh = Skin.FlowButtons(f, f.buttons, pad, y, w, SP.s, 70)
  f:SetHeight(-(y - bh) + SP.l)
end

-------------------------------------------------------------------------------
-- Where the card goes
-------------------------------------------------------------------------------
local function num(v) return type(v) == "number" and v == v and v or nil end

-- A frame's box as { x, top, w, h } from the top-left of the screen, in UIParent units; nil when the game cannot say.
local function boxOf(f, sh)
  if not (f and f.GetLeft) then return nil end
  local ok, l, r, b, t = pcall(function() return f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop() end)
  l, r, b, t = ok and num(l), ok and num(r), ok and num(b), ok and num(t)
  if not (l and r and b and t) then return nil end
  local k = 1
  local okS, fs, us = pcall(function() return f:GetEffectiveScale(), UIParent:GetEffectiveScale() end)
  fs, us = okS and num(fs), okS and num(us)
  if fs and us and us > 0 then k = fs / us end
  return { l * k, sh - t * k, (r - l) * k, (t - b) * k }
end
local function hits(a, b)   -- two boxes share any pixel (touching edges is fine)
  return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

-- The boxes the card must not cover: the trainer message, the next-talent card and the game's talent window, each only
-- while it is on screen. A frame that is up but cannot say where it is counts as the whole middle column under the top
-- line (that is where Spec & Trainer puts its two).
function LC:Others(sw, sh)
  local out = {}
  local ST = Panoply.SpecTrainer
  if not ST then return out end
  local function add(f, middle)
    if not (f and f.IsShown and f:IsShown()) then return end
    local b = boxOf(f, sh)
    if not b and middle then
      local w, h = num(f.GetWidth and f:GetWidth()) or 460, num(f.GetHeight and f:GetHeight()) or 200
      b = { (sw - w) / 2, ST.PAIR_TOP or LC.TOP, w, sh }
    end
    if b then out[#out + 1] = b end
  end
  add(ST.toast, true); add(ST.card, true)
  if type(ST.TalentFrame) == "function" then
    local ok, tf = pcall(ST.TalentFrame, ST)
    if ok then add(tf, false) end
  end
  return out
end

-- Put the card (w wide, h tall) where it covers nothing of LC:Others and stays on screen: the top middle; else to the
-- right of the others, else to their left, else under them. Returns x, top (from the top-left of the screen), or nil
-- when there is no such place on this screen right now.
function LC:FindPlace(w, h, sw, sh, others)
  local E, G = LC.EDGE, LC.GAP
  local function free(x, top)
    if x < E or top < E or x + w > sw - E or top + h > sh - E then return false end
    local me = { x, top, w, h }
    for _, o in ipairs(others) do if hits(me, o) then return false end end
    return true
  end
  local mid = math.floor((sw - w) / 2)
  if free(mid, LC.TOP) then return mid, LC.TOP end
  local right, left, bottom = 0, sw, 0
  for _, o in ipairs(others) do
    right = math.max(right, o[1] + o[3]); left = math.min(left, o[1]); bottom = math.max(bottom, o[2] + o[4])
  end
  for _, top in ipairs({ LC.SIDE_TOP, LC.TOP }) do
    if free(right + G, top) then return right + G, top end
    if free(left - G - w, top) then return left - G - w, top end
  end
  if free(mid, bottom + G) then return mid, bottom + G end
  return nil
end

function LC:Place()
  local f = self.frame
  -- the size of the screen in UI units (a client that cannot say gets the smallest screen Panoply Suite is made for)
  local sw = num(UIParent.GetWidth and UIParent:GetWidth())
  local sh = num(UIParent.GetHeight and UIParent:GetHeight())
  if not (sw and sh) or sw < 300 or sh < 300 then sw, sh = 1024, 668 end
  local x, top = self:FindPlace(f:GetWidth() or LC.WIDTH, f:GetHeight() or 0, sw, sh, self:Others(sw, sh))
  if not x then return false end
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -top)
  return true
end

-- Show the card for `level` (the level you are when none is given). force: asked for by hand (the setting and "nothing
-- to tell" do not stop it). Returns the card and its data, or nil when it is not shown now (switched off, nothing to
-- tell, in a fight, or no room yet: the last two show it later by themselves).
function LC:Show(level, force, try)
  if not force and not (Panoply.db and Panoply.db.levelCard ~= false) then return nil end
  if C.InCombat() then self.pending = { level = level, force = force } return nil end
  local d = self:Data(level)
  if not force and #d.rows == 0 then return nil end
  local f = self:Create()
  self:Layout(d)
  f.data = d
  self.waiting = nil
  if not self:Place() then
    -- no room beside or under the other cards on this screen: look again in a moment
    f:Hide()
    try = (try or 0) + 1
    if try <= LC.WAIT_TRIES then
      local token = {}
      self.waiting = token
      C.After(LC.WAIT_S, function() if LC.waiting == token then LC:Show(level, force, try) end end)
    end
    return nil
  end
  f.left = LC.STAY_S
  f:Show()
  return f, d
end

function LC:Hide()
  self.waiting = nil
  if self.frame then self.frame:Hide() end
end

Panoply:On("PLAYER_LEVEL_UP", function(_, level)
  level = tonumber(level)
  -- a moment later: the new level's spells and talent point are known by then (the trainer message waits the same way)
  C.After(1.5, function() LC:Show(level) end)
end)
Panoply:On("PLAYER_REGEN_ENABLED", function()
  local p = LC.pending
  if p then LC.pending = nil LC:Show(p.level, p.force) end
end)
