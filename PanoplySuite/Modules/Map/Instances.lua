-- Map module, the instance map window: every dungeon and raid in one place.
--   left   search (instance or boss names) and a filter, then the list of instances
--   right  the instance's name and facts, a floor plan with numbered bosses and the way in,
--          a legend you can search, and two buttons (point the arrow at the door; show it on the world map)
-- The game has no map art for the Classic dungeons (its map table lists none: the client tables UiMap of Classic Era 1.15.9 and of
-- WoW Forever 1.60.1 hold only the world, continents, zones and cities), so the plan is Panoply Suite's own: the instance's spawn
-- footprint (data: PanoplySuiteQuestData.MapData, built by tools/build_mapdata.py from the VMaNGOS world database), drawn as a
-- styled floor (0.9.6 phase E, "the grey blocky look ... looks childish"): the footprint's one-cell gaps closed, every outer
-- corner rounded and a thin brass edge round the whole floor. (A line joining the bosses in order was tried and left out: in
-- Blackrock Depths and the raids it crossed the plan in a tangle and drew paths through walls; the numbers give the order.)
-- A boss that a script summons has no fixed spot: it is in the legend without a marker.
-- 0.9.6 phase E, boss drops (data: PanoplySuiteQuestData.BossLoot, built by tools/build_bossloot.py from the VMaNGOS world
-- database): pointing at a boss (its name in the legend or its marker on the plan) lists its drops in the tooltip; clicking it opens
-- the treasure room in place of the plan: the boss (the game's own model of it), and every drop with the game's item icon, its
-- quality colour, what it is and how often it drops. The game's own item tooltip on each; Shift-click links it in chat and Ctrl-click
-- tries it on (the game's HandleModifiedItemClick, as on any item button).
-- Dungeon helper (Engine/Dungeon.lua): while the player is inside the instance shown, the next boss stands out, cleared bosses are
-- dimmed, a click on a boss's number in the legend (or a right-click on its name, or the button in its treasure room) ticks it
-- cleared or not, and the dungeon quests in the quest log are listed under YOUR
-- QUESTS: with a lettered marker beside the boss they need when that boss has a spot, else with no marker. An instance without a
-- floor plan (a WoW Forever dungeon, for one) is listed as "where you are": no plan, the quests all the same.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local pcallv = M.pc
local SP = Skin.SP

local Ins = {}
M.Instances = Ins

Ins.W, Ins.H = 900, 556
Ins.LEFT_W = 268                 -- left column
Ins.PLAN_W, Ins.PLAN_H = 336, 252
Ins.FILTERS = { { "all", "All" }, { "dungeon", "Dungeons" }, { "raid", "Raids" }, { "level", "Near my level" } }
Ins.MARK = 20                    -- boss marker size
Ins.DETECT_TRIES = 5              -- how often to look again when the game's instance facts are late
Ins.MARK_NEXT = 26               -- the next boss to clear, while you are inside
Ins.MARK_QUEST = 16              -- a quest's lettered marker, beside the boss it needs
Ins.QUEST_OFFSETS = { { 13, 13 }, { 13, -13 }, { -13, 13 }, { -13, -13 } }   -- where the letters sit round their boss
Ins.FOOTER = "Point at a boss to see what it drops; click it to open its treasure room. The plan is Panoply Suite's own, north up."
Ins.FOOTER_INSIDE = "You are inside. Click a boss's number to tick it cleared or not; click its name to see its drops."
Ins.FOOTER_ROOM = "Drops and chances come from a community copy of Classic's 1.12 loot tables."
Ins.FOOTER_ROOM_FOREVER = "Drops and chances come from a community copy of Classic's 1.12 loot tables; WoW Forever may differ."
-- only when the data gives a boss nothing worth listing, not even a random drop (0.9.6 phase J: no boss today)
Ins.NO_DROPS = "The game data lists no drops for this boss." -- PLACEHOLDER COPY (Marketing)
-- its drops are all the other side's (Baron Aquanis: only the Horde's Strange Water Globe)
Ins.NO_DROPS_SIDE = "The game data lists no drops of this boss for your side." -- PLACEHOLDER COPY (Marketing)
-- a drop that is in the chest the boss leaves (Cache of the Firelord, Gordok Tribute): the tooltip's tag, the room's note under the
-- chance, and the item tooltip's line
Ins.CHEST_TAG = " (chest)" -- PLACEHOLDER COPY (Marketing)
Ins.CHEST_NOTE = "in its chest" -- PLACEHOLDER COPY (Marketing)
Ins.CHEST_TIP = ", in the chest it leaves" -- PLACEHOLDER COPY (Marketing)
-- a random (world) drop (0.9.6 phase J): listed only for a boss with no drop of its own (Oggleflint, Bazzalan, Hamhock). The
-- tooltip's heading and tag, the room's heading and the note under the chance, and the item tooltip's line
Ins.RANDOM_HEAD = "Random drops (shared by many creatures)" -- PLACEHOLDER COPY (Marketing)
Ins.RANDOM_TAG = " (random drop)" -- PLACEHOLDER COPY (Marketing)
Ins.RANDOM_ROOM_HEAD = "RANDOM DROPS, SHARED BY MANY CREATURES (%d)" -- PLACEHOLDER COPY (Marketing)
Ins.RANDOM_NOTE = "random drop" -- PLACEHOLDER COPY (Marketing)
Ins.RANDOM_TIP = ", a random drop many creatures share" -- PLACEHOLDER COPY (Marketing)
-- (0.9.6 phase J2, our decision 1 b) beside a boss's random drops: the chance per kill of at least one random gear piece and how
-- many different pieces there are (the count stays in the data but is not shown since phase J4), both from the data (Loot/Bosses.lua, the row's fifth field); the hover and the room
Ins.RANDOM_GEAR = "Random green gear: about %s per kill" -- PLACEHOLDER COPY (Marketing)
-- (phase J3, J2 decision 1 a) the label by the best quality among the counted pieces (the field's third part): green only
-- keeps RANDOM_GEAR; a blue among them says "green or blue"; epic and legendary have never been counted (kept for truth's sake)
Ins.RANDOM_GEAR_BY_QUALITY = {
  [3] = "Random green or blue gear: about %s per kill", -- PLACEHOLDER COPY (Marketing)
  [4] = "Random green, blue or epic gear: about %s per kill", -- PLACEHOLDER COPY (Marketing)
  [5] = "Random green or better gear: about %s per kill", -- PLACEHOLDER COPY (Marketing)
}
Ins.NO_LOOT_DATA = "The boss drops need Panoply Suite Quest Data; it is not loaded."
Ins.TIP_MAX = 10                 -- drops listed in a boss's tooltip; the treasure room lists them all
Ins.ROOM_HERO_W = 150            -- the boss's alcove in the treasure room
Ins.DROP_H = 40                  -- one drop in the treasure room (icon, name, what it is, chance)
Ins.DROP_ICON = 32
Ins.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
-- the item kinds that are not gear (item class), and the slots (inventory type) for gear without a kind of its own
Ins.CLASS_WORDS = { [0] = "Consumable", [1] = "Bag", [5] = "Reagent", [6] = "Ammunition", [7] = "Trade goods", [9] = "Recipe",
  [11] = "Quiver", [12] = "Quest item", [13] = "Key", [15] = "Miscellaneous" }
Ins.SLOT_WORDS = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [13] = "One-hand", [14] = "Shield", [15] = "Ranged", [16] = "Back",
  [17] = "Two-hand", [18] = "Bag", [19] = "Tabard", [20] = "Chest", [21] = "Main hand", [22] = "Off hand", [23] = "Held in off hand",
  [25] = "Thrown", [26] = "Ranged", [28] = "Relic" }
Ins.NO_PLAN = "No floor plan for this instance yet."
Ins.NO_QUESTS = "None of the quests in your log is for this instance, as far as Panoply Suite's data knows."
local ROW_H = 52               -- an instance row in the list (name and a line of facts, at 1.3x text)

local function data() return M.Data() end

function Ins:All()
  local d = data()
  if not (d and d.instances) then return {} end
  if not self.byId then
    self.byId = {}
    for _, i in ipairs(d.instances) do self.byId[i.id] = i end
  end
  if not self.sorted then
    -- dungeons first, then raids, each by the level of their monsters
    local list = {}
    for _, id in ipairs(d.order or {}) do if self.byId[id] then list[#list + 1] = self.byId[id] end end
    local rank = function(i) return i.kind == "raid" and 1 or 0 end
    local pos = {}
    for n, i in ipairs(list) do pos[i] = n end
    table.sort(list, function(a, b)
      if rank(a) ~= rank(b) then return rank(a) < rank(b) end
      return pos[a] < pos[b]
    end)
    self.sorted = list
  end
  return self.sorted
end
function Ins:Count() return #self:All() end
function Ins:Get(id) self:All() return self.byId and self.byId[id] end

-- Boss list, in the usual clearing order: { n, name, level, u, v, wing, placed }
function Ins:Bosses(inst)
  inst.cache = inst.cache or {}
  if inst.cache.bosses then return inst.cache.bosses end
  local out = {}
  for n, b in ipairs(inst.bosses) do
    out[n] = { n = n, name = b[1], level = b[2], u = b[3], v = b[4], wing = b[5], placed = b[3] >= 0 }
  end
  inst.cache.bosses = out
  return out
end

-- The floor plan blocks: { { row, first, last }, ... }
function Ins:Runs(inst)
  inst.cache = inst.cache or {}
  if inst.cache.runs then return inst.cache.runs end
  local out = {}
  for r, a, b in inst.runs:gmatch("(%d+),(%d+),(%d+)") do out[#out + 1] = { tonumber(r), tonumber(a), tonumber(b) } end
  inst.cache.runs = out
  return out
end

-- The floor the plan draws: the blocks with their one-cell gaps and notches closed (grown by one cell, then shrunk by one: nothing
-- grows past the footprint's edge), as runs again { row, first, last }, plus the set of floor cells (rows of cells) for the corners.
function Ins:Floor(inst)
  inst.cache = inst.cache or {}
  if inst.cache.floor then return inst.cache.floor, inst.cache.floorSet end
  local cols, rows = inst.cols, inst.rows
  local set = {}
  for _, r in ipairs(self:Runs(inst)) do
    local row = set[r[1]] or {}
    set[r[1]] = row
    for c = r[2], r[3] do row[c] = true end
  end
  local function has(t, r, c) local row = t[r] return row ~= nil and row[c] == true end
  local grown = {}
  for r = -1, rows do
    for c = -1, cols do
      local on = false
      for dr = -1, 1 do for dc = -1, 1 do if not on and has(set, r + dr, c + dc) then on = true end end end
      if on then grown[r] = grown[r] or {} grown[r][c] = true end
    end
  end
  local closed, out = {}, {}
  for r = 0, rows - 1 do
    local first
    for c = 0, cols do
      local on = c < cols
      if on then
        for dr = -1, 1 do for dc = -1, 1 do if on and not has(grown, r + dr, c + dc) then on = false end end end
      end
      if on then
        closed[r] = closed[r] or {}
        closed[r][c] = true
        first = first or c
      elseif first then
        out[#out + 1] = { r, first, c - 1 }
        first = nil
      end
    end
  end
  inst.cache.floor, inst.cache.floorSet = out, closed
  return out, closed
end

-------------------------------------------------------------------------------
-- Boss drops (PanoplySuiteQuestData.BossLoot)
-------------------------------------------------------------------------------
function Ins:LootData()
  local qd = rawget(_G, "PanoplySuiteQuestData")
  return qd and type(qd.BossLoot) == "table" and qd.BossLoot or nil
end

-- what an item is, in words: the gear's kind and slot ("Two-hand sword", "Cloth  /  Hands"), else the kind of item ("Quest item")
function Ins:ItemKind(inv, kind)
  local cls = tonumber((kind or ""):match("^(%d+)%."))
  local AL = Panoply.AtLevel
  local words = AL and AL.TYPES and AL.TYPES[kind or ""]
  local slot = self.SLOT_WORDS[inv or 0]
  if cls == 2 then return (words and words ~= "") and words or slot or "Weapon" end
  if cls == 4 then
    if words and words ~= "" and slot and words ~= slot then return words .. "  /  " .. slot end
    return slot or words or "Armor"
  end
  return self.CLASS_WORDS[cls or -1] or slot or "Item"
end

-- A boss's record and drops: { entry, display, items = { { id, name, quality, kind, req, chance, quest, chest, side }, ... } } (best first), or nil
-- when the data is not loaded. The boss is found by its place in the instance's list, checked by name (the same lists, tools/build_*.py).
function Ins:Drops(inst, n)
  local L = self:LootData()
  if not (L and inst and type(L.bosses) == "table") then return nil end
  inst.cache = inst.cache or {}
  inst.cache.drops = inst.cache.drops or {}
  local got = inst.cache.drops[n]
  if got then return got end
  local b = inst.bosses[n]
  local list = L.bosses[inst.id]
  if not (b and type(list) == "table") then return nil end
  local rec = list[n]
  if not (type(rec) == "table" and rec[1] == b[1]) then
    rec = nil
    for _, r in ipairs(list) do if type(r) == "table" and r[1] == b[1] then rec = r end end
  end
  if not rec then return nil end
  got = { entry = tonumber(rec[2]) or 0, display = tonumber(rec[3]) or 0, items = {} }
  -- the marks after a chance (0.9.6 phase G): q = only on its quest, c = in the chest the boss leaves, A / H = only that side
  -- gets it from this boss; (phase J) r = a random (world) drop, listed for a boss with no drop of its own
  for iid, ch, marks in tostring(rec[4] or ""):gmatch("(%d+):([%d%.]+)(%a*)") do
    local id = tonumber(iid)
    local raw = type(L.items) == "table" and L.items[id]
    if type(raw) == "string" then
      local name, quality, inv, kind, req, side = raw:match("^(.-)|(%d+)|(%d+)|([%d%.]+)|(%d+)|?(%a?)")
      if name then
        got.items[#got.items + 1] = { id = id, name = name, quality = tonumber(quality) or 1, kind = self:ItemKind(tonumber(inv), kind),
          req = tonumber(req) or 0, chance = tonumber(ch) or 0, quest = marks:find("q", 1, true) ~= nil,
          chest = marks:find("c", 1, true) ~= nil, random = marks:find("r", 1, true) ~= nil,
          side = marks:match("[AH]") or (side ~= "" and side) or nil }
      end
    end
  end
  -- (phase J2) "chance:count" for a boss with random drops: the chance per kill of some random gear piece, and how many there are;
  -- (phase J3) ":quality" after them, the best quality counted (2 green ... 5 legendary); without it (phase J2's data), green
  local gf = tostring(rec[5] or "")
  local gch, gn, gq = gf:match("^([%d%.]+):(%d+):(%d)$")
  if not gch then gch, gn = gf:match("^([%d%.]+):(%d+)$") end
  gch, gn, gq = tonumber(gch), tonumber(gn), tonumber(gq) or 2
  if gch and gn and gch > 0 and gn > 0 then got.gear = { chance = gch, count = gn, quality = gq } end
  -- every drop listed is a random one (a boss with none of its own): the hover and the room say so in their heading
  got.random = #got.items > 0
  for _, it in ipairs(got.items) do if not it.random then got.random = false end end
  inst.cache.drops[n] = got
  return got
end

-- The player's side as the data writes it ("A", "H"), nil when the game does not say
function Ins:Side()
  local f = _G.UnitFactionGroup
  local ok, g = false, nil
  if f then ok, g = pcall(f, "player") end
  if not ok then g = nil elseif C.Readable then g = C.Readable(g) end
  return (g == "Alliance" and "A") or (g == "Horde" and "H") or nil
end

-- the drops this player can get: an item that is only the other side's (the other Head of Onyxia) is left out
function Ins:Shown(d)
  if not d then return {} end
  local side = self:Side()
  if not side then return d.items end
  d.shown = d.shown or {}
  if d.shown[side] then return d.shown[side] end
  local out = {}
  for _, it in ipairs(d.items) do if not it.side or it.side == side then out[#out + 1] = it end end
  d.shown[side] = out
  return out
end

-- the game's own name, link and icon for an item when it has them (the client's language), else ours
function Ins:ItemLook(it)
  local info = C.ItemInfo and C.ItemInfo(it.id)
  local name = info and info.name or it.name
  local q = info and tonumber(info.quality) or it.quality
  local link = info and info.link
  if type(link) ~= "string" then
    local hex = (Panoply.AtLevel and Panoply.AtLevel.QUALITY_COLOR and Panoply.AtLevel.QUALITY_COLOR[q]) or "ffffff"
    link = ("|cff%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(hex, it.id, it.name)
  end
  local icon = C.ItemIcon and C.ItemIcon(it.id) or nil
  return name, q, link, icon or self.QUESTION
end

function Ins:QualityColor(q)
  local K = Panoply.Kit
  if K and K.QualityColor then return K.QualityColor(q) end
  return C.QUALITY and C.QUALITY[q] or Skin.colors.text
end

function Ins:ChanceText(it)
  local s = ((it.chance >= 10) and ("%d%%"):format(math.floor(it.chance + 0.5))) or (("%.1f"):format(it.chance):gsub("%.0$", "") .. "%")
  -- a random drop is rarer than any boss drop (under 0.5%): the data's own figure, e.g. "0.16%" or "0.038%", not "0.2%" or "0%"
  if it.chance > 0 and it.chance < 0.5 then s = tostring(it.chance) .. "%" end
  return s
end

-- the random gear line (phase J2), or nil: "about 5%" (a whole percent from 1% up, one decimal below, never "0%")
function Ins:GearLine(d)
  local g = d and d.random and d.gear
  if not g then return nil end
  local pct = (g.chance >= 1 and ("%d%%"):format(math.floor(g.chance + 0.5)))
    or ((("%.1f"):format(g.chance)):gsub("%.0$", "") .. "%")
  if pct == "0%" then pct = tostring(g.chance) .. "%" end
  -- (phase J3) the label follows the best quality counted; above legendary (never in the data) the "or better" one
  local q = math.min(g.quality or 2, 5)
  -- (phase J4, Nov 17 2026: "if there is 486 items that can drop randomly do not show them") no item count in the line
  return (self.RANDOM_GEAR_BY_QUALITY[q] or self.RANDOM_GEAR):format(pct)
end

-- what follows the chance: on its quest, in its chest, or a random drop (the hover's tag, the room's note, the item tooltip's line)
function Ins:ChanceTag(it, quest, chest, random)
  if it.quest then return quest end
  if it.chest then return chest end
  if it.random then return random end
  return ""
end

-- The tooltip of a boss: its name and level, a line of state, then its drops (the best first, at most TIP_MAX), and what a click does
function Ins:BossTip(owner, inst, b, state)
  local tip = _G.GameTooltip
  if not (tip and inst and b) then return end
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  tip:SetText(("%d. %s"):format(b.n, b.name), 0.95, 0.84, 0.55, 1, true)
  local soft = Skin.colors.inkSoft
  tip:AddLine(("Level %d%s"):format(b.level, (b.wing or "") ~= "" and ("  /  " .. b.wing) or ""), soft[1], soft[2], soft[3])
  if state == "done" then tip:AddLine("Cleared.", soft[1], soft[2], soft[3]) elseif state == "next" then tip:AddLine("Next boss.", soft[1], soft[2], soft[3]) end
  local d = self:Drops(inst, b.n)
  local items = self:Shown(d)
  if not d then
    tip:AddLine(self.NO_LOOT_DATA, soft[1], soft[2], soft[3], true)
  elseif #items == 0 then
    tip:AddLine(#d.items > 0 and self.NO_DROPS_SIDE or self.NO_DROPS, soft[1], soft[2], soft[3], true)
  else
    tip:AddLine(" ")
    tip:AddLine(d.random and self.RANDOM_HEAD or "Drops", 0.95, 0.84, 0.55, true)
    for k = 1, math.min(#items, self.TIP_MAX) do
      local it = items[k]
      local name, q, _, icon = self:ItemLook(it)
      local c = self:QualityColor(q)
      local right = self:ChanceText(it) .. self:ChanceTag(it, " (quest)", self.CHEST_TAG, self.RANDOM_TAG)
      tip:AddDoubleLine(("|T%s:14:14:0:0|t %s"):format(tostring(icon), name), right, c[1], c[2], c[3], soft[1], soft[2], soft[3])
    end
    if #items > self.TIP_MAX then tip:AddLine(("and %d more"):format(#items - self.TIP_MAX), soft[1], soft[2], soft[3]) end
    local gear = self:GearLine(d)
    if gear then tip:AddLine(gear, soft[1], soft[2], soft[3], true) end
  end
  local acc = Skin.colors.accent
  tip:AddLine("Click to open its treasure room.", acc[1], acc[2], acc[3])
  tip:Show()
end

-- Where the way in is: the first door's zone, as "Westfall 38.0, 77.5".
function Ins:Where(inst)
  local d = inst.doors[1]
  if not d then return nil end
  local zone = C.MapName(d[4]) or "outside"
  if d[7] and d[7] > 0 then
    local outer = self:Get(d[7])
    return ("inside %s (%s %.1f, %.1f)"):format(outer and outer.name or "another instance", zone, d[5] * 100, d[6] * 100)
  end
  return ("%s %.1f, %.1f"):format(zone, d[5] * 100, d[6] * 100)
end

function Ins:Facts(inst)
  local parts = { inst.kind == "raid" and "Raid" or "Dungeon", ("%d players"):format(inst.size) }
  parts[#parts + 1] = ("Monsters level %d to %d"):format(inst.mobs[1], inst.mobs[2])
  if inst.enter and inst.enter > 0 then parts[#parts + 1] = ("Enter from level %d"):format(inst.enter) end
  local where = self:Where(inst)
  if where then parts[#parts + 1] = "Door: " .. where end
  return table.concat(parts, "  /  ")
end

function Ins:PlayerLevel()
  local level = C.XP and C.XP()
  return tonumber(level) or 1
end

-- Does the instance pass the current filter and search?
function Ins:Passes(inst)
  local f = Panoply.db.mapInstFilter or "all"
  if f == "dungeon" and inst.kind ~= "dungeon" then return false end
  if f == "raid" and inst.kind ~= "raid" then return false end
  if f == "level" then
    local lv = self:PlayerLevel()
    if not (lv >= (inst.enter or 0) and lv >= inst.mobs[1] - 4 and lv <= inst.mobs[2] + 6) then return false end
  end
  local q = (self.query or ""):lower()
  if q ~= "" then
    if inst.name:lower():find(q, 1, true) then return true end
    for _, b in ipairs(inst.bosses) do if b[1]:lower():find(q, 1, true) then return true end end
    return false
  end
  return true
end

function Ins:Visible()
  local out = {}
  for _, i in ipairs(self:All()) do if self:Passes(i) then out[#out + 1] = i end end
  return out
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function setBox(b, sel)
  local c = sel and Skin.colors.accentDark or Skin.colors.hairline
  b.rim:SetVertexColor(c[1], c[2], c[3], 1)
  local f = sel and Skin.colors.buttonHover or Skin.colors.button
  b.bg:SetVertexColor(f[1], f[2], f[3], 1)
end

function Ins:Row(i)
  local list = self.frame.list
  local b = list.rows[i]
  if b then return b end
  b = CreateFrame("Button", nil, list.area.content)
  b:SetHeight(ROW_H)
  b.bg, b.rim = Skin.Box(b, "S", { fill = Skin.colors.button, fillA = 1, line = Skin.colors.hairline })
  b.name = Skin.Name(b, 13)
  b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -8)
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  b.sub = Skin.Text(b, 11, Skin.colors.inkSoft)
  b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
  if b.sub.SetWordWrap then b.sub:SetWordWrap(false) end
  b:SetScript("OnClick", function(self) Ins:Select(self.instID) end)
  b:SetScript("OnEnter", function(self) if Ins.sel ~= self.instID then local c = Skin.colors.buttonHover self.bg:SetVertexColor(c[1], c[2], c[3], 1) end end)
  b:SetScript("OnLeave", function(self) setBox(self, Ins.sel == self.instID) end)
  list.rows[i] = b
  return b
end

function Ins:Heading(i)
  local list = self.frame.list
  local h = list.heads[i]
  if not h then
    h = Skin.Label(list.area.content, 11, Skin.colors.heading)
    list.heads[i] = h
  end
  return h
end

function Ins:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteInstances", self.W, self.H, "Dungeon and raid maps", "Every dungeon and raid: facts, floor plan and bosses", "DIALOG", "Kill")   -- 4J: its own header icon
  self.frame = f
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)      -- the window is tall: centred, so it fits a 1024x668 screen
  local top = (f.panoplyHeaderBottom or 52) + SP.m
  local LW = self.LEFT_W
  local RX = 16 + LW + SP.l                       -- right column starts here
  local RW = self.W - RX - 16

  -- left: search, filters, list
  f.search = Skin.Input(f, LW, 24, "Search dungeons or bosses")
  f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -top)
  -- typing refreshes the list; a SetText from our own code (userInput false) only fixes the hint text
  f.search:SetScript("OnTextChanged", function(box, userInput)
    box.placeholder:SetShown((box:GetText() or "") == "")
    if userInput == false then return end
    Ins.query = box:GetText() or ""
    Ins:RefreshList()
  end)
  f.filters = {}
  for _, fl in ipairs(self.FILTERS) do
    local b = Skin.Button(f, fl[2], 60, 24, function() Panoply:SetOption("mapInstFilter", fl[1]) Ins:RefreshList() end, fl[2])
    b.filterKey = fl[1]
    f.filters[#f.filters + 1] = b
  end
  local fh = Skin.FlowButtons(f, f.filters, 16, -(top + 24 + SP.s), LW, SP.xs, 48)
  self.listTop = top + 24 + SP.s + fh + SP.s
  f.list = { rows = {}, heads = {} }
  f.list.area = Skin.ScrollArea(f)
  f.list.area:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -self.listTop)
  f.list.area:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  f.list.area:SetWidth(LW)
  f.list.empty = Skin.Text(f, 12, Skin.colors.inkSoft)
  f.list.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -self.listTop - 4)
  f.list.empty:SetWidth(LW - 8)
  f.list.empty:SetText("Nothing matches. Clear the search or pick All.")

  -- right: title, facts, requirement
  f.title = Skin.Heading(f, 18)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", RX, -top)
  f.title:SetWidth(RW - 36)
  f.facts = Skin.Text(f, 12, Skin.colors.text)
  f.facts:SetWidth(RW)
  f.req = Skin.Text(f, 12, Skin.colors.warn)
  f.req:SetWidth(RW)
  self.RX, self.RW, self.top = RX, RW, top

  -- the plan
  local plan = Skin.Card(f)
  plan:SetSize(self.PLAN_W, self.PLAN_H)
  plan.panoplyLayoutSkip = true
  plan.cells, plan.rims, plan.marks = {}, {}, {}
  f.plan = plan
  f.noPlan = Skin.Text(f, 12, Skin.colors.inkSoft)
  f.noPlan:SetWidth(self.PLAN_W - 24)
  f.noPlan:SetText(self.NO_PLAN)
  self:CreateRoom(f)

  -- the legend
  local lw = RW - self.PLAN_W - SP.m
  f.lsearch = Skin.Input(f, lw, 24, "Search the legend")
  f.lsearch:SetScript("OnTextChanged", function(box, userInput)
    box.placeholder:SetShown((box:GetText() or "") == "")
    if userInput == false then return end
    Ins.lquery = box:GetText() or ""
    Ins:RefreshLegend()
  end)
  f.legend = { rows = {}, heads = {} }
  f.legend.area = Skin.ScrollArea(f)
  f.legend.area:SetWidth(lw)
  self.LW2 = lw

  -- buttons
  f.pointBtn = Skin.Button(f, "Point the arrow at the door", 200, 26, function() Ins:PointAtDoor() end, "Point the arrow at the door",
    "Sets a waypoint at the dungeon's door; the arrow takes you there.")
  f.worldBtn = Skin.Button(f, "Show on world map", 160, 26, function() Ins:ShowOnWorldMap() end, "Show on the world map", "Opens the world map at the zone with the door.")
  f.footer = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.footer:SetWidth(RW - 12)                   -- 12: clear of the resize grip
  f.footer:SetText(self.FOOTER)
  f.legend.none = Skin.Text(f.legend.area.content, 12, Skin.colors.inkSoft)
  f.legend.none:SetWidth(lw - 16)
  f.legend.none:SetText(self.NO_QUESTS)
  f.legend.none:Hide()
  f:SetScript("OnShow", function() Ins:RefreshList() end)
  -- Nov 2026: resizable (it grows from the size it is made at; that size is its smallest: the floor plan and its legend need
  -- it), the size remembered. More height is more of the list on the left; more width is a wider legend and wider words.
  Skin.Resizable(f, { key = "instances", minW = self.W, minH = self.H, onSize = function(w, h, done) Ins:Resized(w, h, done) end })
  return f
end

function Ins:Resized(w, h, done)
  local f = self.frame
  if not f then return end
  local RW = w - self.RX - 16
  local lw = RW - self.PLAN_W - SP.m
  self.RW, self.LW2 = RW, lw
  f.title:SetWidth(RW - 36)
  f.facts:SetWidth(RW); f.req:SetWidth(RW)
  f.footer:SetWidth(RW - 12)
  f.room:SetWidth(RW)
  f.lsearch:SetWidth(lw)
  f.legend.area:SetWidth(lw)
  f.legend.none:SetWidth(lw - 16)
  if f.list.area.UpdateBar then f.list.area:UpdateBar() end
  -- the right column is placed again for the new widths (the legend's search is kept while the grip is dragged)
  if self.sel and f:IsShown() then
    if done then self:Select(self.sel) else self:Redraw() end
  end
end

-------------------------------------------------------------------------------
-- List
-------------------------------------------------------------------------------
function Ins:RefreshList()
  local f = self.frame
  if not f then return end
  local list = f.list
  for _, fb in ipairs(f.filters) do fb:SetSelected(fb.filterKey == (Panoply.db.mapInstFilter or "all")) end
  local vis = self:Visible()
  local y, nRow, nHead, last = 0, 0, 0, nil
  local rowW = self.LEFT_W - 12
  local showHeads = (Panoply.db.mapInstFilter or "all") ~= "dungeon" and (Panoply.db.mapInstFilter or "all") ~= "raid"
  if self.here then
    -- the instance you are in has no floor plan: it is listed first, on its own
    nHead = nHead + 1
    local h = self:Heading(nHead)
    h:SetText("WHERE YOU ARE")
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", list.area.content, "TOPLEFT", 2, -y)
    h:Show()
    y = y + math.ceil(Skin.TextHeight(h, rowW)) + SP.xs
    nRow = nRow + 1
    local b = self:Row(nRow)
    b.instID = "here"
    b.name:SetWidth(rowW - 20); b.sub:SetWidth(rowW - 20)
    Skin.Ellipsize(b.name, self.here.name, rowW - 20)   -- the game's own name for it can be long; the title on the right has it whole
    b.sub:SetText("No floor plan yet")
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", list.area.content, "TOPLEFT", 0, -y)
    b:SetSize(rowW, ROW_H)
    setBox(b, self.sel == "here")
    b:Show()
    y = y + ROW_H + SP.xs
  end
  for _, i in ipairs(vis) do
    if showHeads and i.kind ~= last then
      last = i.kind
      nHead = nHead + 1
      local h = self:Heading(nHead)
      h:SetText(i.kind == "raid" and "RAIDS" or "DUNGEONS")
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", list.area.content, "TOPLEFT", 2, -y)
      h:Show()
      y = y + math.ceil(Skin.TextHeight(h, rowW)) + SP.xs
    end
    nRow = nRow + 1
    local b = self:Row(nRow)
    b.instID = i.id
    b.name:SetText(i.name)
    b.sub:SetText(("Levels %d to %d  /  %d players"):format(i.mobs[1], i.mobs[2], i.size))
    b.name:SetWidth(rowW - 20); b.sub:SetWidth(rowW - 20)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", list.area.content, "TOPLEFT", 0, -y)
    b:SetSize(rowW, ROW_H)
    setBox(b, self.sel == i.id)
    b:Show()
    y = y + ROW_H + SP.xs
  end
  for k = nRow + 1, #list.rows do list.rows[k]:Hide() end
  for k = nHead + 1, #list.heads do list.heads[k]:Hide() end
  list.area:SetContentHeight(y)
  list.area.content:SetWidth(list.area:ContentWidth(y))
  if #vis == 0 and not self.here then list.empty:Show() else list.empty:Hide() end
  self.visible = vis
  if self.sel == "here" then
    if self.here then return end
    self.sel = nil   -- you left the instance without a floor plan: back to the first of the list
  end
  -- the selected instance stays; if it was filtered out, show the first that remains
  if self.sel and not self:Passes(self:Get(self.sel)) and vis[1] then self:Select(vis[1].id) end
  if not self.sel and vis[1] then self:Select(vis[1].id) end
end

-------------------------------------------------------------------------------
-- Selection: facts, plan, legend
-------------------------------------------------------------------------------
-- The dungeon helper's view of the run, when the player is inside the instance the window shows (else nil)
function Ins:InsideView()
  local D = Panoply.Dungeon
  local v = D and D:View()
  if not v then return nil end
  if self.sel == "here" then return self.here and v.id == self.here.id and v or nil end
  return v.plan and v.id == self.sel and v or nil
end

function Ins:Select(id)
  local f = self.frame
  local here = id == "here" and self.here or nil
  local inst = not here and self:Get(id) or nil
  if not (f and (inst or here)) then return false end
  if self.sel ~= id then self.room = nil end   -- another instance: back to its plan
  self.sel = id
  self.lquery = ""
  f.lsearch:SetText("")
  if f.lsearch.placeholder then f.lsearch.placeholder:Show() end
  for _, b in ipairs(f.list.rows) do if b:IsShown() then setBox(b, b.instID == id) end end
  local req = inst and inst.req or ""
  f.title:SetText(inst and inst.name or here.name)
  f.facts:SetText(inst and self:Facts(inst) or (Panoply:PlayAlong() and "This instance has no floor plan yet."
    or "This instance has no floor plan yet. Your quests for it are listed here and in the guide window."))
  f.req:SetText(req ~= "" and ("Needs: " .. req) or "")

  -- vertical layout of the right column
  local x, y = self.RX, self.top
  local th = math.ceil(Skin.TextHeight(f.title, self.RW - 36))
  y = y + th + SP.s
  f.facts:ClearAllPoints(); f.facts:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
  y = y + math.ceil(Skin.TextHeight(f.facts, self.RW)) + SP.xs
  if req ~= "" then
    f.req:ClearAllPoints(); f.req:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    f.req:Show()
    y = y + math.ceil(Skin.TextHeight(f.req, self.RW)) + SP.xs
  else
    f.req:Hide()
  end
  y = y + SP.xs
  self.planY = y
  f.plan:ClearAllPoints(); f.plan:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
  f.lsearch:ClearAllPoints(); f.lsearch:SetPoint("TOPLEFT", f, "TOPLEFT", x + self.PLAN_W + SP.m, -y)
  f.legend.area:ClearAllPoints()
  f.legend.area:SetPoint("TOPLEFT", f, "TOPLEFT", x + self.PLAN_W + SP.m, -(y + 24 + SP.s))
  f.legend.area:SetHeight(self.PLAN_H - 24 - SP.s)
  y = y + self.PLAN_H + SP.m
  f.pointBtn:ClearAllPoints(); f.worldBtn:ClearAllPoints()
  local h = Skin.FlowButtons(f, { f.pointBtn, f.worldBtn }, x, -y, self.RW, SP.s, 90)
  y = y + h + SP.m
  f.footer:ClearAllPoints(); f.footer:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
  self.footerY = y
  -- the treasure room takes the plan's place and the buttons' row (it is about the boss, not the way to the door)
  f.room:ClearAllPoints(); f.room:SetPoint("TOPLEFT", f, "TOPLEFT", x, -self.planY)
  f.room:SetSize(self.RW, y - self.planY - SP.m)
  -- the two buttons are the way to the door outside; an instance without a floor plan has no door in our data
  f.pointBtn:SetEnabledLook(inst ~= nil); f.worldBtn:SetEnabledLook(inst ~= nil)
  self:Redraw()
  return true
end

-- The plan, the legend and the footer of the instance shown (again when the dungeon helper's run changes)
function Ins:Redraw()
  local f = self.frame
  if not (f and self.sel) then return end
  local inst = self.sel ~= "here" and self:Get(self.sel) or nil
  if not inst and not (self.sel == "here" and self.here) then return end
  if self.room and not (inst and inst.bosses[self.room]) then self.room = nil end
  if self.room then
    f.footer:SetText(C.IsForever() and self.FOOTER_ROOM_FOREVER or self.FOOTER_ROOM)
    for _, w in ipairs({ f.plan, f.noPlan, f.lsearch, f.legend.area, f.pointBtn, f.worldBtn }) do w:Hide() end
    self:DrawRoom(inst, self.room)
    return
  end
  f.room:Hide()
  for _, w in ipairs({ f.plan, f.lsearch, f.legend.area, f.pointBtn, f.worldBtn }) do w:Show() end
  f.footer:SetText(inst and (self:InsideView() and self.FOOTER_INSIDE or self.FOOTER) or "")
  self:DrawPlan(inst)
  self:RefreshLegend()
end

-- the plan: the styled floor and the markers, fitted into the plan card
Ins.RIM = 1.5                    -- the brass edge round the floor, in pixels
-- a quarter of a round disc (the CircleMask texture's corner) for each corner of a cell: top left, bottom left, top right, bottom right
local QUARTER = { tl = { 0, 0.5, 0, 0.5 }, bl = { 0, 0.5, 0.5, 1 }, tr = { 0.5, 1, 0, 0.5 }, br = { 0.5, 1, 0.5, 1 } }

-- One layer of the floor: every run as a bar whose outer corners are rounded (a corner is outer when no floor cell touches it from
-- the row above or below) and whose inner corners stay square, so neighbouring rows join without a notch. grow: how far this
-- layer reaches past the floor (the brass edge is the same floor, grown by RIM, drawn under it).
function Ins:DrawFloorLayer(plan, pool, runs, set, cs, ox, oy, colour, sub, grow)
  local n = 0
  local function piece(round, coords)
    n = n + 1
    local t = pool[n]
    if not t then t = plan:CreateTexture(nil, "ARTWORK", nil, sub) pool[n] = t end
    t:SetTexture(round and Skin.TEX.CircleMask or Skin.WHITE)
    if t.SetTexCoord then
      if round then t:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else t:SetTexCoord(0, 1, 0, 1) end
    end
    t:SetVertexColor(colour[1], colour[2], colour[3], 1)
    t:ClearAllPoints()
    t:Show()
    return t
  end
  local function has(r, c) local row = set[r] return row ~= nil and row[c] == true end
  local hr, g = cs / 2, grow
  for _, run in ipairs(runs) do
    local r, a, b = run[1], run[2], run[3]
    local x0, x1, y0 = ox + a * cs, ox + (b + 1) * cs, oy + r * cs
    -- a corner is rounded only when nothing touches it from above or below: not the cell next to it and not the one diagonally
    -- beyond it (a corner that only touches another row at its point stays square, so no dark speck opens between them)
    local tl = not has(r - 1, a) and not has(r - 1, a - 1)
    local bl = not has(r + 1, a) and not has(r + 1, a - 1)
    local tr = not has(r - 1, b) and not has(r - 1, b + 1)
    local br = not has(r + 1, b) and not has(r + 1, b + 1)
    local li = (tl or bl) and hr or 0
    local ri = (tr or br) and hr or 0
    -- the bar between the two ends (reaching past the floor by `grow` where its end is square)
    local left, right = x0 + li - (li == 0 and g or 0), x1 - ri + (ri == 0 and g or 0)
    if right - left > 0.01 then
      local t = piece(false)
      t:SetPoint("TOPLEFT", plan, "TOPLEFT", left, -(y0 - g))
      t:SetSize(right - left, cs + 2 * g)
    end
    -- the four corner pieces of the ends that have a rounded corner
    local s = hr + g
    if li > 0 then
      piece(tl, QUARTER.tl):SetPoint("TOPLEFT", plan, "TOPLEFT", x0 - g, -(y0 - g))
      pool[n]:SetSize(s, s)
      piece(bl, QUARTER.bl):SetPoint("TOPLEFT", plan, "TOPLEFT", x0 - g, -(y0 + hr))
      pool[n]:SetSize(s, s)
    end
    if ri > 0 then
      piece(tr, QUARTER.tr):SetPoint("TOPLEFT", plan, "TOPLEFT", x1 - hr, -(y0 - g))
      pool[n]:SetSize(s, s)
      piece(br, QUARTER.br):SetPoint("TOPLEFT", plan, "TOPLEFT", x1 - hr, -(y0 + hr))
      pool[n]:SetSize(s, s)
    end
  end
  for i = n + 1, #pool do pool[i]:Hide() end
  return n
end

function Ins:DrawPlan(inst)
  local plan = self.frame.plan
  local pad = 10
  if not inst then
    -- an instance without a floor plan: an empty card that says so
    for _, pool in ipairs({ plan.cells, plan.rims }) do for _, t in ipairs(pool) do t:Hide() end end
    for _, m in ipairs(plan.marks) do m:Hide() end
    self.planGeom = nil
    self.frame.noPlan:ClearAllPoints()
    self.frame.noPlan:SetPoint("TOPLEFT", plan, "TOPLEFT", 12, -12)
    self.frame.noPlan:Show()
    return 0
  end
  local view = self:InsideView()
  local cols, rows = inst.cols, inst.rows
  local cs = math.min((self.PLAN_W - 2 * pad) / cols, (self.PLAN_H - 2 * pad) / rows)
  local ox = (self.PLAN_W - cols * cs) / 2
  local oy = (self.PLAN_H - rows * cs) / 2
  self.planGeom = { cs = cs, ox = ox, oy = oy }
  local runs, set = self:Floor(inst)
  -- the brass edge first (the floor grown by RIM), the floor over it: where two rows meet, the floor covers the edge
  self:DrawFloorLayer(plan, plan.rims, runs, set, cs, ox, oy, Skin.colors.goldDark, 1, self.RIM)
  self.floorPieces = self:DrawFloorLayer(plan, plan.cells, runs, set, cs, ox, oy, Skin.colors.slotTop, 3, 0)
  local function at(u, v) return ox + u * cols * cs, -(oy + v * rows * cs) end
  local bosses = self:Bosses(inst)
  -- bosses, then the ways in
  local used = 0
  local function mark(u, v, label, kind, tip, state, dx, dy, boss)
    used = used + 1
    local m = plan.marks[used]
    if not m then
      m = CreateFrame("Button", nil, plan)
      m.ring = m:CreateTexture(nil, "BACKGROUND"); m.ring:SetTexture(Skin.TEX.CircleMask); m.ring:SetAllPoints(m)
      m.disc = m:CreateTexture(nil, "BORDER"); m.disc:SetTexture(Skin.TEX.CircleMask); m.disc:SetPoint("CENTER", m, "CENTER", 0, 0)
      m.num = Skin.Text(m, 11, Skin.colors.text, nil, "label")
      m.num:SetPoint("CENTER", m, "CENTER", 0, 0)
      if m.num.SetJustifyH then m.num:SetJustifyH("CENTER") end
      if m.num.SetWordWrap then m.num:SetWordWrap(false) end
      -- a boss: its drops in the tooltip, a click opens its treasure room; anything else: its words
      m:SetScript("OnEnter", function(self)
        if self.boss then Ins:BossTip(self, Ins:Get(Ins.sel), self.boss, self.state) return end
        if _G.GameTooltip and self.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(self.tip, 0.95, 0.84, 0.55, 1, true) GameTooltip:Show() end
      end)
      m:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      m:SetScript("OnClick", function(self) if self.boss then Ins:OpenRoom(self.boss.n) end end)
      plan.marks[used] = m
    end
    -- inside: the next boss is bigger with a light ring, a cleared one is dimmed; a quest's letter is small, beside its boss
    local size = (kind == "quest" and self.MARK_QUEST) or (state == "next" and self.MARK_NEXT) or self.MARK
    m:SetSize(size, size); m.disc:SetSize(size - 4, size - 4)
    local ring = (kind == "door" and Skin.colors.accent) or (kind == "quest" and (state == "ready" and Skin.colors.done or Skin.colors.warn))
      or (state == "done" and Skin.colors.dim) or (state == "next" and Skin.colors.gatherRing) or Skin.colors.goldBright
    m.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
    local dk = Skin.colors.trailInk
    m.disc:SetVertexColor(dk[1], dk[2], dk[3], 1)
    m.num:SetText(label)
    local ink = state == "done" and Skin.colors.dim or Skin.colors.text
    m.num:SetTextColor(ink[1], ink[2], ink[3], 1)
    m.tip = tip
    m.kind, m.state, m.label, m.boss = kind, state, label, boss
    m:ClearAllPoints()
    local x, y = at(u, v)
    m:SetPoint("CENTER", plan, "TOPLEFT", x + (dx or 0), y + (dy or 0))
    if m.SetFrameLevel then m:SetFrameLevel((plan:GetFrameLevel() or 1) + 2 + used % 30) end
    m.panoplyLayoutSkip = true
    m:Show()
  end
  for _, b in ipairs(bosses) do
    if b.placed then
      local state = view and ((view.done[b.n] and "done") or (view.next == b.n and "next")) or nil
      local tip = ("%d. %s (level %d)"):format(b.n, b.name, b.level)
      if state == "done" then tip = tip .. "\nCleared." elseif state == "next" then tip = tip .. "\nNext boss." end
      mark(b.u, b.v, tostring(b.n), "boss", tip, state, nil, nil, b)
    end
  end
  for _, a in ipairs(inst.arrive or {}) do mark(a[1], a[2], "E", "door", "Way in: " .. (a[3] or "Entrance")) end
  -- your quests for this dungeon: a letter beside the boss the quest needs (only a boss with a spot; nothing is placed by guess)
  if view then
    local at = {}
    for _, q in ipairs(view.quests) do
      local b = q.mark and bosses[q.mark]
      if b and b.placed then
        local k = at[q.mark] or 0
        at[q.mark] = k + 1
        local off = self.QUEST_OFFSETS[k % #self.QUEST_OFFSETS + 1]
        mark(b.u, b.v, q.letter, "quest", ("Quest %s: %s\nNeeds boss %d, %s.%s"):format(q.letter, q.name, b.n, b.name, q.ready and "\nReady to hand in." or ""),
          q.ready and "ready" or nil, off[1], off[2])
      end
    end
  end
  for i = used + 1, #plan.marks do plan.marks[i]:Hide() end
  self.frame.noPlan:ClearAllPoints()
  self.frame.noPlan:SetPoint("TOPLEFT", plan, "TOPLEFT", 12, -12)
  self.frame.noPlan:Hide()
  return used
end

-- legend: numbered bosses (with wing headings), the way in, and (inside) your quests for this dungeon; filtered by its own search
function Ins:RefreshLegend()
  local f = self.frame
  local here = self.sel == "here" and self.here or nil
  local inst = not here and self.sel and self:Get(self.sel) or nil
  if not (f and (inst or here)) then return end
  local view = self:InsideView()
  local L = f.legend
  local q = (self.lquery or ""):lower()
  local area = L.area
  local lw = self.LW2
  local y, nRow, nHead, lastWing = 0, 0, 0, nil
  local textW = lw - 12 - 28
  local function head(text)
    nHead = nHead + 1
    local h = L.heads[nHead]
    if not h then h = Skin.Label(area.content, 11, Skin.colors.heading) L.heads[nHead] = h end
    h:SetText(text)
    h:SetWidth(lw - 12)
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", area.content, "TOPLEFT", 2, -y)
    h:Show()
    y = y + math.ceil(Skin.TextHeight(h, lw - 12)) + SP.xs
  end
  -- one legend row: a round badge with a number or letter, then the words. A boss row is clicked to tick it (inside only).
  local function row(colour, label, text, gap, kind, bossN)
    nRow = nRow + 1
    local r = L.rows[nRow]
    if not r then
      r = CreateFrame("Button", nil, area.content)
      r.badge = r:CreateTexture(nil, "ARTWORK"); r.badge:SetTexture(Skin.TEX.CircleMask); r.badge:SetSize(22, 22)
      r.badge:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
      r.n = Skin.Text(r, 11, Skin.colors.trailInk, nil, "label")
      r.n:SetPoint("CENTER", r.badge, "CENTER", 0, 0)
      if r.n.SetJustifyH then r.n:SetJustifyH("CENTER") end
      if r.n.SetWordWrap then r.n:SetWordWrap(false) end
      r.name = Skin.Text(r, 12, Skin.colors.text)
      r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -3)
      -- the hovered row's surface (rounded, under the words)
      r.hl = r:CreateTexture(nil, "BACKGROUND")
      r.hl:SetAllPoints(r)
      Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
      local hc = Skin.colors.surface2
      r.hl:SetVertexColor(hc[1], hc[2], hc[3], 1)
      r.hl:Hide()
      -- the number: inside the instance, a click on it ticks the boss cleared or not
      r.tick = CreateFrame("Button", nil, r)
      r.tick:SetSize(22, 22)
      r.tick:SetPoint("CENTER", r.badge, "CENTER", 0, 0)
      r.tick.panoplyLayoutSkip = true   -- an invisible click target laid exactly over its own number: not a cover over the words
      r.tick:SetScript("OnClick", function(self) Ins:TickBoss(self:GetParent().bossN) end)
      r.tick:SetScript("OnEnter", function(self)
        local p = self:GetParent()
        if not (p.bossN and Ins:InsideView() and _G.GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to tick it cleared or not.", 0.95, 0.84, 0.55, 1, true)
        GameTooltip:Show()
      end)
      r.tick:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
      if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
      -- a boss: the click opens its treasure room (a right-click inside ticks it, as the number does)
      r:SetScript("OnClick", function(self, button)
        if not self.bossNo then return end
        if button == "RightButton" and Ins:InsideView() then Ins:TickBoss(self.bossNo) return end
        Ins:OpenRoom(self.bossNo)
      end)
      r:SetScript("OnEnter", function(self)
        if not self.bossNo then return end
        self.hl:Show()
        local inst = Ins:Get(Ins.sel)
        Ins:BossTip(self, inst, inst and Ins:Bosses(inst)[self.bossNo], self.state)
      end)
      r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
      L.rows[nRow] = r
    end
    r.kind, r.bossN = kind, bossN
    r.bossNo, r.state = nil, nil
    r.hl:Hide()
    if r.tick then if bossN then r.tick:Show() else r.tick:Hide() end end
    r.badge:SetVertexColor(colour[1], colour[2], colour[3], 1)
    r.n:SetText(label)
    r.n:SetWidth(22)
    r.name:SetWidth(textW)
    r.name:SetText(text)
    local rh = math.max(24, math.ceil(Skin.TextHeight(r.name, textW)) + 4)
    r:SetSize(lw - 12, rh)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, -y)
    r:Show()
    y = y + rh + gap
    return r
  end
  if inst then
    local multi = false
    for _, b in ipairs(inst.bosses) do if b[5] ~= "" then multi = true end end
    for _, b in ipairs(self:Bosses(inst)) do
      if q == "" or b.name:lower():find(q, 1, true) then
        if multi and b.wing ~= lastWing then
          lastWing = b.wing
          head((b.wing ~= "" and b.wing or "Other"):upper())
        end
        local state = view and ((view.done[b.n] and "done") or (view.next == b.n and "next")) or nil
        local gc = (state == "done" and Skin.colors.dim) or (state == "next" and Skin.colors.gatherRing)
          or (b.placed and Skin.colors.goldBright) or Skin.colors.dim
        local r = row(gc, tostring(b.n), ("%s  (%d)%s%s"):format(b.name, b.level, b.placed and "" or "  no marker",
          (state == "done" and "  cleared") or (state == "next" and "  next") or ""), 1, "boss", view and b.n or nil)
        r.bossNo, r.state = b.n, state
      end
    end
    -- the way in
    if q == "" or ("entrance"):find(q, 1, true) or ("door"):find(q, 1, true) then
      row(Skin.colors.accent, "E", "Way in: " .. (self:Where(inst) or "see the world map"), 2, "door")
    end
  end
  -- your quests for this dungeon (only while you are inside it)
  local nQuest = 0
  if view then
    local shown = {}
    for _, qu in ipairs(view.quests) do if q == "" or qu.name:lower():find(q, 1, true) then shown[#shown + 1] = qu end end
    if #shown > 0 then head("YOUR QUESTS") end
    for _, qu in ipairs(shown) do
      nQuest = nQuest + 1
      local where = qu.mark and ("  at boss %d"):format(qu.mark) or "  no marker"
      row(qu.ready and Skin.colors.done or Skin.colors.warn, qu.letter, qu.name .. where .. (qu.ready and "  ready to hand in" or ""), 1, "quest")
    end
  end
  -- an instance without a floor plan and without a quest of yours has nothing to list: say so
  if here and nQuest == 0 and q == "" then
    L.none:ClearAllPoints(); L.none:SetPoint("TOPLEFT", area.content, "TOPLEFT", 2, -y)
    L.none:Show()
    y = y + math.ceil(Skin.TextHeight(L.none, lw - 16)) + SP.xs
  else
    L.none:Hide()
  end
  for k = nRow + 1, #L.rows do L.rows[k]:Hide() end
  for k = nHead + 1, #L.heads do L.heads[k]:Hide() end
  area:SetContentHeight(y)
  area.content:SetWidth(area:ContentWidth(y))
  self.legendRows = nRow
end

-------------------------------------------------------------------------------
-- The treasure room: one boss and everything it drops, in place of the plan
-------------------------------------------------------------------------------
-- the room's frame and its fixed parts (made once with the window; filled by DrawRoom)
function Ins:CreateRoom(f)
  local room = Skin.Card(f)
  room:SetSize(self.RW or 400, self.PLAN_H)
  room:Hide()
  f.room = room
  room.back = Skin.Button(room, "Back to the map", 140, 24, function() Ins:CloseRoom() end, "Back to the map",
    "Shows the floor plan and the list of bosses again.")
  room.prev = Skin.Button(room, "Previous boss", 120, 24, function() Ins:StepRoom(-1) end, "Previous boss", "The boss before this one.")
  room.next = Skin.Button(room, "Next boss", 100, 24, function() Ins:StepRoom(1) end, "Next boss", "The boss after this one.")
  room.tick = Skin.Button(room, "Mark cleared", 120, 24, function() Ins:TickBoss(Ins.room) end, "Cleared or not",
    "Ticks this boss cleared, or takes the tick back, for the dungeon helper.")
  -- the boss's alcove: a dark case with a brass edge, the game's own model of the boss inside it
  local hero = CreateFrame("Frame", nil, room)
  hero.bg, hero.rim = Skin.Box(hero, "S", { fill = Skin.colors.bgDeep, fillA = 1, line = Skin.colors.goldDark })
  room.hero = hero
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, hero)
  if ok and model then
    model:SetPoint("TOPLEFT", hero, "TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -4, 4)
    model.panoplyLayoutSkip = true
    -- drag to turn the boss round (the player's own mouse; nothing moves by itself)
    if model.EnableMouse then model:EnableMouse(true) end
    model:SetScript("OnMouseDown", function(self)
      local gc = _G.GetCursorPosition
      if not gc then return end
      self.dragX = gc()
      self:SetScript("OnUpdate", function(m)
        local x = gc()
        if m.dragX and m.SetFacing then
          m.facing = (m.facing or 0) + (x - m.dragX) * 0.02
          pcall(m.SetFacing, m, m.facing)
        end
        m.dragX = x
      end)
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil self:SetScript("OnUpdate", nil) end)
    model:SetScript("OnHide", function(self) self.dragX = nil self:SetScript("OnUpdate", nil) end)
    room.model = model
  end
  -- without a model (no display id, or a client without model frames): the boss's number, large, as on the plan
  hero.ring = hero:CreateTexture(nil, "ARTWORK"); hero.ring:SetTexture(Skin.TEX.CircleMask); hero.ring:SetSize(56, 56)
  hero.ring:SetPoint("CENTER", hero, "CENTER", 0, 0)
  local gb = Skin.colors.goldBright
  hero.ring:SetVertexColor(gb[1], gb[2], gb[3], 1)
  hero.disc = hero:CreateTexture(nil, "ARTWORK", nil, 2); hero.disc:SetTexture(Skin.TEX.CircleMask); hero.disc:SetSize(50, 50)
  hero.disc:SetPoint("CENTER", hero, "CENTER", 0, 0)
  local dk = Skin.colors.trailInk
  hero.disc:SetVertexColor(dk[1], dk[2], dk[3], 1)
  hero.num = Skin.Heading(hero, 20)
  hero.num:SetPoint("CENTER", hero, "CENTER", 0, 0)
  if hero.num.SetJustifyH then hero.num:SetJustifyH("CENTER") end
  room.name = Skin.Heading(room, 16)
  room.sub = Skin.Text(room, 11, Skin.colors.inkSoft)
  room.dropsHead = Skin.Label(room, 11, Skin.colors.heading)
  room.gear = Skin.Text(room, 11, Skin.colors.inkSoft)
  room.list = Skin.ScrollArea(room)
  room.rows = {}
  room.none = Skin.Text(room, 12, Skin.colors.inkSoft)
  return room
end

function Ins:OpenRoom(n)
  local inst = self.sel and self.sel ~= "here" and self:Get(self.sel)
  if not (inst and inst.bosses[n] and self.frame) then return false end
  if _G.GameTooltip then GameTooltip:Hide() end
  self.room = n
  self:Redraw()
  return true
end

function Ins:CloseRoom()
  if not self.room then return false end
  self.room = nil
  self:Redraw()
  return true
end

function Ins:StepRoom(dir)
  local inst = self.room and self:Get(self.sel)
  local n = inst and self.room + dir
  if not (n and inst.bosses[n]) then return false end
  return self:OpenRoom(n)
end

-- the dungeon helper's tick (inside the instance shown only); the window follows through DUNGEON_CHANGED
function Ins:TickBoss(n)
  if not (n and self:InsideView() and Panoply.Dungeon) then return false end
  Panoply.Dungeon:ToggleBoss(n)
  return true
end

-- one drop of the list: the item's icon with its quality as a fine edge, its name in the quality colour, what it is, the chance
function Ins:DropRow(i)
  local room = self.frame.room
  local r = room.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, room.list.content)
  r:SetHeight(self.DROP_H)
  r.hl = r:CreateTexture(nil, "BACKGROUND")
  r.hl:SetAllPoints(r)
  Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
  local hc = Skin.colors.surface2
  r.hl:SetVertexColor(hc[1], hc[2], hc[3], 1)
  r.hl:Hide()
  local s = self.DROP_ICON
  r.edge = r:CreateTexture(nil, "BORDER")
  r.edge:SetTexture(Skin.WHITE)
  r.edge:SetSize(s, s)
  r.edge:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -math.floor((self.DROP_H - s) / 2))
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetPoint("TOPLEFT", r.edge, "TOPLEFT", 1, -1)
  r.icon:SetPoint("BOTTOMRIGHT", r.edge, "BOTTOMRIGHT", -1, 1)
  if r.icon.SetTexCoord then r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  r.name = Skin.Name(r, 12)
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", s + 12, -4)
  r.kind = Skin.Text(r, 11, Skin.colors.inkSoft)
  r.kind:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
  r.chance = Skin.Name(r, 13, Skin.colors.text)
  r.chance:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -4)
  r.note = Skin.Text(r, 10, Skin.colors.inkSoft)
  r.note:SetPoint("TOPRIGHT", r.chance, "BOTTOMRIGHT", 0, -2)
  for _, fs in ipairs({ r.name, r.kind, r.chance, r.note }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  for _, fs in ipairs({ r.chance, r.note }) do if fs.SetJustifyH then fs:SetJustifyH("RIGHT") end end
  -- the game's own item tooltip; Shift-click links it in chat and Ctrl-click tries it on (the game's own handler)
  r:SetScript("OnEnter", function(self)
    self.hl:Show()
    local tip, it = _G.GameTooltip, self.item
    if not (tip and it) then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    if tip.SetItemByID then pcall(tip.SetItemByID, tip, it.id) else pcall(tip.SetHyperlink, tip, "item:" .. it.id) end
    local soft = Skin.colors.inkSoft
    tip:AddLine(" ")
    tip:AddLine(("Drop chance: %s%s"):format(Ins:ChanceText(it), Ins:ChanceTag(it, ", for a player on its quest", Ins.CHEST_TIP, Ins.RANDOM_TIP)),
      0.95, 0.84, 0.55, true)
    tip:AddLine("Shift-click: link it in chat.  Ctrl-click: try it on.", soft[1], soft[2], soft[3], true)
    tip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  r:SetScript("OnClick", function(self)
    local h = _G.HandleModifiedItemClick
    if h and self.link then pcall(h, self.link) end
  end)
  room.rows[i] = r
  return r
end

-- The room of boss n of the instance: fills and places everything for the room's size
function Ins:DrawRoom(inst, n)
  local f = self.frame
  local room = f.room
  local bosses = self:Bosses(inst)
  local b = bosses[n]
  local view = self:InsideView()
  local state = view and ((view.done[n] and "done") or (view.next == n and "next")) or nil
  local RW = self.RW
  local RH = room:GetHeight() or self.PLAN_H
  local pad = SP.m
  room:SetWidth(RW)
  room:Show()
  -- top bar: back, previous, next and (inside) the tick
  room.prev:SetEnabledLook(n > 1)
  room.next:SetEnabledLook(n < #bosses)
  room.tick.label:SetText(state == "done" and "Mark not cleared" or "Mark cleared")
  local bar = { room.back, room.prev, room.next }
  if view then room.tick:Show() bar[#bar + 1] = room.tick else room.tick:Hide() end
  local barH = Skin.FlowButtons(room, bar, pad, -pad, RW - 2 * pad, SP.s, 60)
  local top = pad + barH + pad
  -- the alcove
  local heroH = math.max(80, RH - top - pad)
  local hw = self.ROOM_HERO_W
  local hero = room.hero
  hero:ClearAllPoints(); hero:SetPoint("TOPLEFT", room, "TOPLEFT", pad, -top)
  hero:SetSize(hw, heroH)
  local d = self:Drops(inst, n)
  local shown = false
  if room.model and d and d.display > 0 and room.model.SetDisplayInfo then
    if room.model.ClearModel then pcall(room.model.ClearModel, room.model) end
    shown = pcall(room.model.SetDisplayInfo, room.model, d.display)
    if shown then
      room.model.facing = 0.35
      if room.model.SetPortraitZoom then pcall(room.model.SetPortraitZoom, room.model, 0) end
      if room.model.SetFacing then pcall(room.model.SetFacing, room.model, room.model.facing) end
    end
  end
  room.modelShown = shown and d.display or nil
  if room.model then if shown then room.model:Show() else room.model:Hide() end end
  for _, t in ipairs({ hero.ring, hero.disc, hero.num }) do if shown then t:Hide() else t:Show() end end
  hero.num:SetText(tostring(n))
  -- the words beside it
  local x = pad + hw + SP.l
  local w = RW - x - pad
  room.name:ClearAllPoints(); room.name:SetPoint("TOPLEFT", room, "TOPLEFT", x, -top)
  room.name:SetWidth(w)
  room.name:SetText(b.name)
  local y = top + math.ceil(Skin.TextHeight(room.name, w)) + SP.xs
  local sub = { ("Boss %d of %d"):format(n, #bosses), ("level %d"):format(b.level) }
  if (b.wing or "") ~= "" then sub[#sub + 1] = b.wing end
  if state == "done" then sub[#sub + 1] = "cleared" elseif state == "next" then sub[#sub + 1] = "next" end
  room.sub:ClearAllPoints(); room.sub:SetPoint("TOPLEFT", room, "TOPLEFT", x, -y)
  room.sub:SetWidth(w)
  room.sub:SetText(table.concat(sub, "  /  "))
  y = y + math.ceil(Skin.TextHeight(room.sub, w)) + SP.m
  local items = self:Shown(d)
  room.dropsHead:ClearAllPoints(); room.dropsHead:SetPoint("TOPLEFT", room, "TOPLEFT", x, -y)
  room.dropsHead:SetWidth(w)
  room.dropsHead:SetText(#items > 0 and ((d.random and self.RANDOM_ROOM_HEAD or "POSSIBLE DROPS (%d)"):format(#items)) or "POSSIBLE DROPS")
  y = y + math.ceil(Skin.TextHeight(room.dropsHead, w)) + SP.xs
  -- (phase J2) under the random drops' heading: the random gear line
  local gear = #items > 0 and self:GearLine(d) or nil
  if gear then
    room.gear:ClearAllPoints(); room.gear:SetPoint("TOPLEFT", room, "TOPLEFT", x, -y)
    room.gear:SetWidth(w)
    room.gear:SetText(gear)
    room.gear:Show()
    y = y + math.ceil(Skin.TextHeight(room.gear, w)) + SP.xs
  else
    room.gear:SetText("")
    room.gear:Hide()
  end
  local list = room.list
  list:ClearAllPoints(); list:SetPoint("TOPLEFT", room, "TOPLEFT", x - 4, -y)
  list:SetSize(w + 4, math.max(self.DROP_H, RH - y - pad))
  local cw = list:ContentWidth(#items * (self.DROP_H + 2))
  local ly = 0
  for i, it in ipairs(items) do
    local r = self:DropRow(i)
    local name, q, link, icon = self:ItemLook(it)
    local c = self:QualityColor(q)
    r.item, r.link = it, link
    Panoply.Icons:Apply(r.icon, it.id, icon)   -- 0.9.7 hotfix: painted again when the game sends the item
    r.edge:SetVertexColor(c[1], c[2], c[3], 1)
    local nameW = cw - self.DROP_ICON - 12 - 96
    r.name:SetWidth(nameW); r.kind:SetWidth(nameW)
    Skin.Ellipsize(r.name, name, nameW)
    r.name:SetTextColor(c[1], c[2], c[3], 1)
    Skin.Ellipsize(r.kind, it.kind .. (it.req > 1 and ("  /  level %d"):format(it.req) or ""), nameW)
    r.chance:SetWidth(88); r.note:SetWidth(88)
    r.chance:SetText(self:ChanceText(it))
    r.note:SetText(self:ChanceTag(it, "on its quest", self.CHEST_NOTE, self.RANDOM_NOTE))
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -ly)
    r:SetSize(cw, self.DROP_H)
    r.hl:Hide()
    r:Show()
    ly = ly + self.DROP_H + 2
  end
  for i = #items + 1, #room.rows do room.rows[i]:Hide() end
  list:SetContentHeight(ly)
  list.content:SetWidth(cw)
  if list.UpdateBar then list:UpdateBar() end
  if #items == 0 then
    room.none:ClearAllPoints(); room.none:SetPoint("TOPLEFT", room, "TOPLEFT", x, -y)
    room.none:SetWidth(w)
    room.none:SetText(d and (#d.items > 0 and self.NO_DROPS_SIDE or self.NO_DROPS) or self.NO_LOOT_DATA)
    room.none:Show()
  else
    room.none:Hide()
  end
  self.roomRows = #items
  return #items
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
function Ins:PointAtDoor()
  local inst = self.sel and self:Get(self.sel)
  local d = inst and inst.doors[1]
  if not d then return false end
  return M:PointAt(d[4], d[5], d[6], inst.name .. " (door)", "dungeon")
end

function Ins:ShowOnWorldMap()
  local inst = self.sel and self:Get(self.sel)
  local d = inst and inst.doors[1]
  if not d or C.InCombat() then return false end
  local open = C.G("C_Map.OpenWorldMap")
  local wm = C.WorldMap()
  if open then pcallv(open, d[4]) elseif wm and wm.Show then wm:Show() end
  if wm and wm.SetMapID then wm:SetMapID(d[4]) end
  return true
end

-------------------------------------------------------------------------------
-- Opening, closing, being inside one
-------------------------------------------------------------------------------
function Ins:Open(id)
  local f = self:Create()
  if not f then return end
  if id == "here" then
    -- the instance you are in, which has no floor plan
    if not self.here then id = nil else
      f:Show()
      self:RefreshList()
      self:Select("here")
      return
    end
  end
  if id and self:Get(id) then self.sel = nil end
  f:Show()
  self:RefreshList()
  if id and self:Get(id) then
    -- make sure the pick is in the list the window shows
    if not self:Passes(self:Get(id)) then
      Panoply:SetOption("mapInstFilter", "all")
      self.query = ""
      f.search:SetText("")
      if f.search.placeholder then f.search.placeholder:Show() end
      self:RefreshList()
    end
    self:Select(id)
  end
end

function Ins:Toggle()
  if self.Count and self:Count() == 0 and not self.here then Panoply:Print("The instance maps need Panoply Suite Quest Data; it is not loaded.") return end
  local f = self:Create()
  if f:IsShown() then f:Hide() else self:Open((self.here and "here") or self.current or self.sel) end
end

-- The instance the player is in (the game's own number for the map, from GetInstanceInfo)
function Ins:CurrentID()
  local f = _G.GetInstanceInfo
  if not f then return nil end
  local ok, _, _, _, _, _, _, _, id = pcall(f)
  if ok then id = C.Readable(id) end   -- a secret instance id cannot be compared or used as a key
  if ok and type(id) == "number" then return id end
  return nil
end

-- light: a second look (a zone change, or the game's instance facts arriving late): the open window only follows a change
function Ins:OnZone(light)
  local was, wasHere = self.current, self.here and self.here.id
  local id = self:CurrentID()
  self.current = id and self:Get(id) and id or nil
  self:Detect(id)
  if light and self.current == was and (self.here and self.here.id) == wasHere then return end
  if self.frame and self.frame:IsShown() then
    if self.current then self:Open(self.current)
    elseif self.here then self:Open("here")
    else self:RefreshList() end
  end
end

-- Dungeon helper: tell Engine/Dungeon.lua whether the player is inside an instance, and which. Inside means the game says so
-- (C.InInstance: a dungeon, a raid or a scenario) and gives the instance's number. An instance with a floor plan hands over its
-- bosses; one without is remembered as self.here (no plan, the quests all the same).
function Ins:Detect(id)
  local D = Panoply.Dungeon
  if not D then return end
  local inside, kind = C.InInstance()
  local gameName, gameKind = C.InstanceInfo()
  if inside and D.KINDS[kind or ""] and (not id or (gameKind and not D.KINDS[gameKind])) then
    -- the game says "inside" but its instance facts still describe the world outside (they can arrive a moment after the
    -- loading screen): nothing is started on a guess; look again shortly, a few times
    self.detectTries = (self.detectTries or 0) + 1
    if self.detectTries <= self.DETECT_TRIES then C.After(1, function() if M.active then Ins:OnZone(true) end end) end
    return
  end
  self.detectTries = nil
  if inside and id and D.KINDS[kind or ""] then
    if not D.names then
      local names = {}
      for _, i in ipairs(self:All()) do names[D.Norm(i.name)] = i.id end
      if next(names) then D.names = names end
    end
    local inst = self:Get(id)
    self.here = not inst and { id = id, name = gameName or "This instance" } or nil
    D:Enter(id, inst and inst.name or gameName, inst and self:Bosses(inst) or nil, gameName)
  else
    self.here = nil
    D:Leave()
  end
end

function Ins:Enable()
  self:OnZone()
  if _G.SlashCmdList and not self.slash then
    self.slash = true
    _G.SLASH_HEARTHPATHMAP1 = "/psmap"   -- 0.8.0: the short form is ps; /hpmap still works, unadvertised
    _G.SLASH_HEARTHPATHMAP2 = "/hpmap"
    _G.SlashCmdList.HEARTHPATHMAP = function(msg)
      msg = (msg or ""):lower()
      if msg == "reset" and M.Window then M.Window:Reset() return end
      if M.active then Ins:Toggle() else Panoply:Print("The Map module is off (Map page, More settings, Map tools).") end
    end
  end
end

function Ins:Disable()
  if self.frame then self.frame:Hide() end
  self.here = nil
  if Panoply.Dungeon then Panoply.Dungeon:Leave() end   -- the helper is part of the Map module: off with it
end

-- the dungeon helper ticked a boss, or your quests for the dungeon changed: the window follows while it is open
Panoply:Listen("DUNGEON_CHANGED", function()
  if Ins.frame and Ins.frame:IsShown() and M.active then Ins:Redraw() end
end)
