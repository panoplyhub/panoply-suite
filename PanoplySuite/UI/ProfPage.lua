-- Panoply Suite 0.9.5, phase 4B: the Professions page (docs/specs/page-redesigns-v1.md section 2, queue item 2). The view model is
-- UI/Professions.lua; this file only draws it, with the shared visual system (UI/KitParts.lua): surfaces with no borders, gold only on
-- titles, explanations in tooltips, status chips, progress bars, icon cells, underlined text tabs.
--
--   Wide (over 820)    a list of ~240 px on the left (one card per profession: icon, name, skill bar to the rank cap, status chip;
--                      then the trade camp and Mage Research on WoW Forever, then what is not learned) and one profession's detail
--   Medium (560-820)   the list is a rail of ~64 px: each profession an icon with a skill ring and a status dot, its name in the tooltip
--   Narrow (under 560) one column: the professions are a wrapping row of chips on top (the trade camp is a chip too), then the detail,
--                      with its tabs as one dropdown
-- The detail, top to bottom: the header (name, plan dropdown, By hand, the button that opens the game's profession window), the skill
-- bar (on WoW Forever with the Legacy marks at 150 / 225 / 300 on crafting professions: a click opens the Legacy page), the Next card
-- (a fixed height, never scrolls; two lines at the window's least height), the tabs, and on Recipes the search row. All of that is
-- pinned; only the tab content scrolls (and the list, on its own, when it is longer than the page).
-- The header of the page (Size, On, the gear) is the window's own one line; the plan and the views live here, per profession.
-- Secure buttons: the "Open window" button and the trainer rows of Steps open the profession window (a spell, so secure code). The
-- page is therefore never redrawn in a fight; a change waits for the end of it (Kit.Holds below).
-- 0.9.6 phase K: a character with no profession gets the starter guide ("Start here": the professions to pick, the class's pairs, the
-- nearest trainer of your side with Take me there); the header's first control is the primary "Open <profession>" button, which opens
-- the profession here on the page (the crafting view: recipes, materials, quantity, Make, Make All) with the game's window kept hidden.
local ADDON, Panoply = ...
local PUI = Panoply.ProfUI
local Skin, Kit, C, PD = Panoply.Skin, Panoply.Kit, Panoply.Compat, Panoply.ProfData
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Page = {}
PUI.PageFrame = Page
Page.LIST_W, Page.RAIL_W, Page.GAP = 240, 64, 12
Page.CARD_H = 50
Page.NEXT_H, Page.NEXT_H_MIN = 116, 54   -- standard text; 1.3x text makes a card taller (it then keeps that height while drawn)
Page.SEARCH_WAIT = 0.3     -- seconds after the last key before the recipe list is drawn again
Page.GRIP = 22           -- room left under the tab content for the window's resize grip (16) and corner
Page.COMPACT_ROOM = 130   -- the Next card is two lines (action + blocker) when the full card would leave the tab content less than this

local function tContains_(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
local function plainText(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function accentOf(name)
  if PUI.IsSecondary(name) then return "secondary" end
  return PUI.Kind(name) == "crafting" and "crafting" or "gathering"
end
local function tint(fs, token) local c = Kit.Color(token) fs:SetTextColor(c[1], c[2], c[3], 1) end
local function inCombat() return C.InCombat() end

-------------------------------------------------------------------------------
-- What is selected, and the history step it makes
-------------------------------------------------------------------------------
-- the entries the list shows: { id, label, kind = "starter" | "prof" | "camp" | "research" | "notlearned" | "slot" }
-- 0.9.6 phase K: a character with no profession at all gets the starter guide first ("Start here"); its professions to pick and the
-- easy extras are in the guide, so the list has no "not learned" rows then (the trade camp and Mage Research stay, on WoW Forever).
PUI.START = "__start"
function PUI:Starter() return #self:Chosen() == 0 end
function PUI:Entries()
  local out = {}
  local starter = self:Starter()
  if starter then out[#out + 1] = { id = PUI.START, label = PUI.STARTER_COPY.entry, kind = "starter" } end
  for _, n in ipairs(self:Chosen()) do out[#out + 1] = { id = n, label = n, kind = "prof" } end
  if C.IsForever() then out[#out + 1] = { id = "Trade camp", label = "Trade camp", kind = "camp" } end
  if self:ShowResearch() then out[#out + 1] = { id = "Mage Research", label = "Mage Research", kind = "research" } end
  if not starter then
    local missing, slot = self:NotLearned()
    for _, n in ipairs(missing) do out[#out + 1] = { id = n, label = n, kind = "notlearned" } end
    if slot then out[#out + 1] = { id = "__slot", label = "Open primary slot", kind = "slot" } end
  end
  return out
end
function PUI:Selectable(id)
  for _, e in ipairs(self:Entries()) do if e.id == id and e.kind ~= "slot" then return true end end
  return false
end
-- pick what the detail shows: a new step of the window's history (Back comes back here)
function PUI:Select(id)
  if id == "__slot" then if Panoply.SettingsUI and Panoply.SettingsUI.OpenOverrides then Panoply.SettingsUI:OpenOverrides() end return false end
  if not self:Selectable(id) or self.selected == id then return false end
  if inCombat() and Kit.PageHolds and Kit.PageHolds("professions") then
    self.pendingSelect = id
    Kit.Defer("professions/select", function() local p = PUI.pendingSelect PUI.pendingSelect = nil if p then PUI:Select(p) end end)
    Panoply:Print("The Professions page shows " .. tostring(id) .. " when combat ends.")
    return false
  end
  self.selected = id
  self.pendingScroll = 0
  if Panoply.Menu then Panoply.Menu:RefreshCurrent() end
  if Panoply.History then Panoply.History:Note("profession") end
  return true
end
if Panoply.History then Panoply.History:State("professions", {
  get = function() return { prof = PUI.selected, scroll = Page.tabArea and Page.tabArea:GetVerticalScroll() or 0 } end,
  set = function(s) if type(s) == "table" then PUI.selected = s.prof PUI.pendingScroll = s.scroll or 0 end end,
  key = function(s) return type(s) == "table" and tostring(s.prof) or tostring(s) end,
}) end

-- the selected entry is always one that is there: the guide's profession, else the first
function PUI:FixSelected()
  local chosen = self:Chosen()
  if self.selected and self:Selectable(self.selected) then return self.selected end
  local t = Panoply.ProfGuide and Panoply.ProfGuide:Tracked()
  self.selected = (t and tContains_(chosen, t)) and t or chosen[1]
  if not self.selected and self:Starter() then self.selected = PUI.START end
  if not self.selected then
    -- nothing learned yet: a profession to start (a secondary not learned) before the trade camp
    local first
    for _, e in ipairs(self:Entries()) do
      if e.kind == "notlearned" or e.kind == "prof" then self.selected = e.id break end
      if not first and e.kind ~= "slot" then first = e.id end
    end
    self.selected = self.selected or first
  end
  return self.selected
end

-- the view of an entry (a profession, the trade camp, Mage Research)
function PUI:EntryView(id, snap, noRows)
  if id == PUI.START then return self:StarterView() end
  if id == "Trade camp" then return self:TradeCampView(snap) end
  if id == "Mage Research" then return self:ResearchView() end
  return self:View(id, { snap = snap, noRows = noRows })
end

-- the game snapshot of one drawing (spellbook, bags, Favor, reputation: WoW Forever only). Kept for a second while the same entry
-- shows, so a burst of refreshes (looting, a bag update) reads the game once.
function PUI:Snapshot()
  local PC = Panoply.ProfCamp
  if not (C.IsForever() and PC) then return nil end
  local now = (_G.GetTime and GetTime()) or 0
  local c = self.snapCache
  if c and c.sel == self.selected and now - c.at < 1 then return c.snap end
  local snap = PC:Snapshot()
  self.snapCache = { snap = snap, at = now, sel = self.selected }
  return snap
end

-------------------------------------------------------------------------------
-- 0.9.6 phase K: the starter guide (a character with no profession yet; Nov 17 2026: "yes, always show professions with a
-- starter guide"). A picker in the shape of the game's own: every profession with its icon, its name and one line, the pairs that
-- suit the character's class marked; a pick shows where to learn it (the nearest trainer of your side in this zone, else in one of
-- your capital cities, else "ask a guard") with Take me there (the arrow, through the map's Go To path) and Find a trainer (the
-- map's Go To search). Only the professions this add-on knows for both clients (PUI.PRIMARY, PUI.SECONDARY: Classic 1.15.x and WoW
-- Forever have no Jewelcrafting or Inscription).
-------------------------------------------------------------------------------
PUI.ICON_FILES[PUI.START] = "INV_Misc_Book_11"
PUI.STARTER_COPY = {
  entry = "Start here",   -- PLACEHOLDER COPY (Marketing)
  heading = "Start a profession",   -- PLACEHOLDER COPY (Marketing)
  intro = "Pick two main professions: a gathering one feeds a crafting one. Click one to see where to learn it.",   -- PLACEHOLDER COPY (Marketing)
  next = "Pick your first profession",   -- PLACEHOLDER COPY (Marketing)
  suggested = "SUGGESTED FOR YOUR %s",   -- PLACEHOLDER COPY (Marketing)
  main = "MAIN PROFESSIONS (PICK TWO)",   -- PLACEHOLDER COPY (Marketing)
  extras = "EASY EXTRAS ANYONE CAN LEARN",   -- PLACEHOLDER COPY (Marketing)
  picked = "Learn %s",   -- PLACEHOLDER COPY (Marketing)
  zone = "Nearest trainer: %s, %s.",   -- PLACEHOLDER COPY (Marketing)
  city = "No %s trainer in this zone. Nearest city trainer: %s, %s.",   -- PLACEHOLDER COPY (Marketing)
  -- 0.9.6 phase O: none in this zone or your capitals: the nearest trainer of your side anywhere
  near = "No %s trainer here or in your capitals. Nearest: %s, %s.",   -- PLACEHOLDER COPY (Marketing)
  -- (no trainer known: 0.9.6 phase M shows phase L's wording, PUI.GuardLine() in UI/Professions.lua; this line is no longer shown)
  guard = "No trainer known nearby. Ask a city guard: they mark the trainer on your map.",   -- PLACEHOLDER COPY (Marketing)
  go = "Take me there",   -- PLACEHOLDER COPY (Marketing)
  goTip = "Points the arrow at this trainer, through the map's Go to.",   -- PLACEHOLDER COPY (Marketing)
  find = "Find a trainer",   -- PLACEHOLDER COPY (Marketing)
  findTip = "Opens the map's Go to search for this profession's trainers.",   -- PLACEHOLDER COPY (Marketing)
  suggestedTip = "Suggested for your class.",   -- PLACEHOLDER COPY (Marketing)
  trainerTitle = "%s trainer",   -- PLACEHOLDER COPY (Marketing)
}
-- one line per profession (the picker's cells)
PUI.STARTER_LINES = {
  Mining = "Mine ore and stone. Feeds Blacksmithing and Engineering.",   -- PLACEHOLDER COPY (Marketing)
  Herbalism = "Pick herbs. Feeds Alchemy, and herbs sell well.",   -- PLACEHOLDER COPY (Marketing)
  Skinning = "Skin beasts for leather. Feeds Leatherworking.",   -- PLACEHOLDER COPY (Marketing)
  Tailoring = "Sew cloth from your loot into bags and cloth armor.",   -- PLACEHOLDER COPY (Marketing)
  Leatherworking = "Make leather and mail armor, and armor kits.",   -- PLACEHOLDER COPY (Marketing)
  Blacksmithing = "Forge plate, mail, weapons and sharpening stones.",   -- PLACEHOLDER COPY (Marketing)
  Engineering = "Build bombs, scopes, gadgets and goggles.",   -- PLACEHOLDER COPY (Marketing)
  Alchemy = "Brew healing and mana potions, and elixirs.",   -- PLACEHOLDER COPY (Marketing)
  Enchanting = "Enchant gear, and break unwanted gear into dust.",   -- PLACEHOLDER COPY (Marketing)
  Cooking = "Cook food that heals and buffs, from meat and fish.",   -- PLACEHOLDER COPY (Marketing)
  Fishing = "Fish in any water. Your catch feeds Cooking.",   -- PLACEHOLDER COPY (Marketing)
  ["First Aid"] = "Make bandages from looted cloth to heal between fights.",   -- PLACEHOLDER COPY (Marketing)
}
-- the gathering + crafting pairs that suit each class, best first (2 or 3 each); the class from the game (C.PlayerInfo().classFile)
local CLOTH = {
  { "Tailoring", "Enchanting", "Make your own cloth gear, then enchant it." },   -- PLACEHOLDER COPY (Marketing)
  { "Herbalism", "Alchemy", "Mana and healing potions for every fight." },   -- PLACEHOLDER COPY (Marketing)
  { "Herbalism", "Tailoring", "Herbs to sell; the cloth comes from your fights." },   -- PLACEHOLDER COPY (Marketing)
}
PUI.STARTER_PAIRS = {
  WARRIOR = {
    { "Mining", "Blacksmithing", "Make and upgrade your own plate and weapons." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Engineering", "Bombs, nets and scopes for tough fights." },   -- PLACEHOLDER COPY (Marketing)
    { "Skinning", "Leatherworking", "Armor kits and leather while you level." },   -- PLACEHOLDER COPY (Marketing)
  },
  PALADIN = {
    { "Mining", "Blacksmithing", "Make and upgrade your own plate and weapons." },   -- PLACEHOLDER COPY (Marketing)
    { "Herbalism", "Alchemy", "Potions for long fights and for healing." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Engineering", "Gadgets and bombs for tough fights." },   -- PLACEHOLDER COPY (Marketing)
  },
  ROGUE = {
    { "Skinning", "Leatherworking", "Make your own leather armor." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Engineering", "Bombs and gadgets for openers and escapes." },   -- PLACEHOLDER COPY (Marketing)
    { "Herbalism", "Alchemy", "Potions and elixirs for tough fights." },   -- PLACEHOLDER COPY (Marketing)
  },
  DRUID = {
    { "Skinning", "Leatherworking", "Make your own leather armor." },   -- PLACEHOLDER COPY (Marketing)
    { "Herbalism", "Alchemy", "Potions for every role you play." },   -- PLACEHOLDER COPY (Marketing)
  },
  HUNTER = {
    { "Skinning", "Leatherworking", "Make your own leather and, later, mail armor." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Engineering", "Make your own guns, scopes and ammunition." },   -- PLACEHOLDER COPY (Marketing)
    { "Herbalism", "Alchemy", "Potions for you and agility elixirs." },   -- PLACEHOLDER COPY (Marketing)
  },
  SHAMAN = {
    { "Skinning", "Leatherworking", "Make your own leather and, later, mail armor." },   -- PLACEHOLDER COPY (Marketing)
    { "Herbalism", "Alchemy", "Potions for healing and long fights." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Engineering", "Gadgets and bombs for tough fights." },   -- PLACEHOLDER COPY (Marketing)
  },
  MAGE = CLOTH, PRIEST = CLOTH, WARLOCK = CLOTH,
  [""] = {
    { "Herbalism", "Alchemy", "Potions anyone can use, and herbs sell well." },   -- PLACEHOLDER COPY (Marketing)
    { "Skinning", "Leatherworking", "Leather armor and armor kits." },   -- PLACEHOLDER COPY (Marketing)
    { "Mining", "Blacksmithing", "Plate, weapons and sharpening stones." },   -- PLACEHOLDER COPY (Marketing)
  },
}
-- the capital cities of each side (the fallback when this zone has no trainer)
PUI.CAPITALS = { Alliance = { [1453] = true, [1455] = true, [1457] = true }, Horde = { [1454] = true, [1456] = true, [1458] = true } }

local function known(name) return tContains_(PUI.PRIMARY, name) or tContains_(PUI.SECONDARY, name) end
local function playerInfo() return (C.PlayerInfo and C.PlayerInfo()) or {} end
-- the class's pairs, only professions this add-on knows (both clients)
function PUI:StarterPairs(classFile)
  classFile = classFile or playerInfo().classFile or ""
  local list = PUI.STARTER_PAIRS[classFile] or PUI.STARTER_PAIRS[""]
  local out = {}
  for _, pr in ipairs(list) do
    if known(pr[1]) and known(pr[2]) then out[#out + 1] = { a = pr[1], b = pr[2], why = pr[3] } end
  end
  return out
end
-- the picker's cells: { name, line, suggested, extra }
function PUI:StarterList(classFile)
  local sug = {}
  for _, pr in ipairs(self:StarterPairs(classFile)) do sug[pr.a] = true sug[pr.b] = true end
  local main, extras = {}, {}
  for _, n in ipairs(PUI.PRIMARY) do main[#main + 1] = { name = n, line = PUI.STARTER_LINES[n] or "", suggested = sug[n] or false } end
  for _, n in ipairs({ "Cooking", "Fishing", "First Aid" }) do
    if known(n) then extras[#extras + 1] = { name = n, line = PUI.STARTER_LINES[n] or "", extra = true } end
  end
  return main, extras
end

-- an NPC of the player's side: never an enemy one, nor one whose side is unknown. 0.9.6 phase M: phase L's own-side check
-- (Engine/ProfGuide.lua G.NpcFriendly: the NPC data's own faction, Engine/QuestData.lua, first; else the profession data's side)
local function friendlyNpc(id, rec)
  local G = Panoply.ProfGuide
  if G and G.NpcFriendly then
    local ok, f = pcall(G.NpcFriendly, id, rec)
    return ok and f == true
  end
  local QD = Panoply.QuestData
  if not (id and QD and QD.NpcFriendly) then return false end
  local ok, f = pcall(QD.NpcFriendly, QD, id)
  return ok and f == true
end
-- every trainer of a profession that the player's side may use: the profession data's apprentice trainers (0.9.6 phase M: both
-- sides' list, allNpcs, and on WoW Forever the trainers only Forever has), then the map's own profession trainer markers whose
-- title names this profession (Modules/Map/Places.lua). { npc, map, x, y, name }
function PUI:TrainerCandidates(prof)
  local out, seen = {}, {}
  local function add(id, map, x, y, name, rec)
    if not (id and map and x and y) then return end
    local k = tostring(id) .. ":" .. tostring(map)
    if seen[k] or not friendlyNpc(id, rec) then return end
    seen[k] = true
    out[#out + 1] = { npc = id, map = map, x = x, y = y, name = name or ("NPC " .. id) }
  end
  local pd = PD[prof or ""]
  local first = pd and pd.ranks and pd.ranks[1]
  for _, id in ipairs(first and (first.allNpcs or first.npcs) or {}) do
    local okS, s = pcall(PD.NpcSpot, id)
    if okS and s then add(id, s.map, s.x, s.y, s.name) end
  end
  local G = Panoply.ProfGuide
  local okF, ft = false, nil
  if G and G.ForeverTrainers then okF, ft = pcall(G.ForeverTrainers, G, prof) end
  for _, e in ipairs(okF and type(ft) == "table" and ft or {}) do
    if type(e) == "table" then add(e.npc, e.map, e.x, e.y, e.name, e) end
  end
  local P = Panoply.Map and Panoply.Map.Places
  local okI, idx = false, nil
  if P and P.Index then okI, idx = pcall(P.Index) end
  for _, e in ipairs(okI and idx and idx.byType and idx.byType.placeTrainProf or {}) do
    if PUI.TrainerTitle(prof, e.sub) then add(e.id, e.map, e.x, e.y, e.name) end
  end
  return out
end
-- does an NPC's title name a trainer of this profession? "Mining Trainer", or a crafter's rank and trade word ("Expert Leatherworker",
-- "Journeyman Tailor", "Blacksmith"); a specialty trainer ("Armorsmith", "Gnome Engineer") is not one to start with
PUI.TRAINER_WORDS = { Leatherworking = "leatherworker", Tailoring = "tailor", Blacksmithing = "blacksmith", Engineering = "engineer",
  Enchanting = "enchanter", Alchemy = "alchemist" }
local TRAINER_RANKS = { [""] = true, apprentice = true, journeyman = true, expert = true, artisan = true, master = true }
function PUI.TrainerTitle(prof, sub)
  if type(sub) ~= "string" or type(prof) ~= "string" then return false end
  local s = sub:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if s:find(prof:lower() .. " trainer", 1, true) then return true end
  local w = PUI.TRAINER_WORDS[prof]
  if not w then return false end
  local pre = s:match("^(%a*)%s*" .. w .. "$")
  return pre ~= nil and TRAINER_RANKS[pre] == true
end
-- where to learn a profession: { where = "zone" | "city" | "near" | "guard", spot = { npc, map, x, y, name }, text }
-- 0.9.6 phase O (Nov 17 2026): this zone, then your capitals, then (new) the nearest trainer of your side anywhere (by travel
-- time, as the guide and the window pick it), and only then ask a city guard. The same order as ProfGuide:FriendlyNearest.
function PUI:StarterTrainer(prof)
  local T = PUI.STARTER_COPY
  local cands = self:TrainerCandidates(prof)
  local caps = PUI.CAPITALS[playerInfo().faction or ""] or {}
  local pm, px, py = C.GetPlayerPos()
  local Nav = Panoply.Nav
  local function dist(c)
    if not (pm and Nav and Nav.Distance) then return nil end
    local ok, d = pcall(Nav.Distance, pm, px, py, c.map, c.x, c.y)
    return ok and d or nil
  end
  local pos = (pm and px and py) and { map = pm, x = px, y = py } or (Panoply.State and Panoply.State.pos)
  local function travel(c)
    if not PD.Travel then return 1e9 end
    local ok, t = pcall(PD.Travel, pos, c)
    return ok and tonumber(t) or 1e9
  end
  local bz, bzd, bc, bcd, bn, bnt
  for _, c in ipairs(cands) do
    local d = dist(c) or 1e9
    if pm and c.map == pm then if not bz or d < bzd then bz, bzd = c, d end end
    if caps[c.map] then if not bc or d < bcd then bc, bcd = c, d end end
    local t = travel(c)
    if not bn or t < bnt then bn, bnt = c, t end
  end
  local mapName = function(m) return (C.MapName and C.MapName(m)) or "?" end
  if bz then return { where = "zone", spot = bz, text = T.zone:format(bz.name, mapName(bz.map)) } end
  if bc then return { where = "city", spot = bc, text = T.city:format(prof, bc.name, mapName(bc.map)) } end
  if bn then return { where = "near", spot = bn, text = T.near:format(prof, bn.name, mapName(bn.map)) } end
  return { where = "guard", text = PUI.GuardLine() }   -- 0.9.6 phase M: phase L's "ask a city guard" wording
end
-- the profession the guide shows (picked by the player; else the best pair's first)
function PUI:StarterPick()
  if self.starterPick and known(self.starterPick) then return self.starterPick end
  local pairs_ = self:StarterPairs()
  return pairs_[1] and pairs_[1].a or PUI.PRIMARY[1]
end
function PUI:StarterSelect(name)
  if not known(name) or self.starterPick == name then return false end
  if inCombat() and Kit.PageHolds and Kit.PageHolds("professions") then return false end
  self.starterPick = name
  if Panoply.Menu then Panoply.Menu:RefreshCurrent() end
  return true
end
function PUI:StarterView()
  local info = playerInfo()
  local main, extras = self:StarterList(info.classFile)
  local pick = self:StarterPick()
  return { kind = "starter", name = PUI.STARTER_COPY.heading, class = info.class or info.classFile or "", classFile = info.classFile or "",
    pairs = self:StarterPairs(info.classFile), main = main, extras = extras, pick = pick, trainer = self:StarterTrainer(pick),
    next = { kind = "none", title = PUI.STARTER_COPY.next, line = PUI.STARTER_COPY.next } }
end
-- Take me there: the arrow at the trainer, through the map's Go to (a waypoint of the Professions group); without the map, the arrow
function PUI:StarterGo(prof)
  prof = prof or self:StarterPick()
  local t = self:StarterTrainer(prof)
  if not t.spot then Panoply:Print(PUI.GuardLine()) return false end
  local label = ("%s (%s)"):format(t.spot.name, PUI.STARTER_COPY.trainerTitle:format(prof))
  local N = Panoply.Map and Panoply.Map.Navigate
  if N and N.Go and Panoply.Modules and Panoply.Modules:IsOn("map") then
    return N:Go({ map = t.spot.map, x = t.spot.x, y = t.spot.y, name = label }, "prof") and true or false
  end
  self:PointAt({ map = t.spot.map, x = t.spot.x, y = t.spot.y, name = label }, label)
  return true
end
-- Find a trainer: the map's Go to search for this profession's trainers; with no map (or no trainer known) the chat says to ask a guard
function PUI:StarterFind(prof)
  prof = prof or self:StarterPick()
  local t = self:StarterTrainer(prof)
  if not t.spot then Panoply:Print(PUI.GuardLine()) end
  local N = Panoply.Map and Panoply.Map.Navigate
  if N and N.Create and Panoply.Modules and Panoply.Modules:IsOn("map") then
    local ok, f = pcall(N.Create, N)
    if ok and f then
      if f.input and f.input.SetText then f.input:SetText(PUI.STARTER_COPY.trainerTitle:format(prof)) end
      if not f:IsShown() then f:Show() end
      if N.Update then pcall(N.Update, N) end
      return true
    end
  end
  if t.spot then Panoply:Print(t.text) end
  return false
end

-------------------------------------------------------------------------------
-- 0.9.6 phase K: crafting on the page. The page's Open button (a secure spell button, the player's click) opens the profession; the
-- game's window is then kept tucked away (Modules/ProfWindow PW:HostedOpen: invisible, its mouse off, its session open) while this
-- page shows the recipes, the selected recipe's reagents (have / need), a quantity, Make and Make All, through the add-on's own trade
-- skill wrappers (Core/CompatModules.lua: TradeSkillDetails, SelectRecipe, RecipeRepeat, MakeRecipe, CloseProfession). Closing this view
-- ends the session (CloseTradeSkill); "Game window" hands the open session to the game's own window. A profession opened any other way
-- (spellbook, keybind) opens exactly as before.
-------------------------------------------------------------------------------
PUI.CRAFT_COPY = {
  close = "Close %s",   -- PLACEHOLDER COPY (Marketing)
  closeTip = "Closes this profession. The game's own window works as always from your spellbook.",   -- PLACEHOLDER COPY (Marketing)
  open = "Open %s",   -- PLACEHOLDER COPY (Marketing)
  openTip = "Opens %s here on this page: recipes, materials and Make.",   -- PLACEHOLDER COPY (Marketing)
  noWindow = "%s has no window to open: you gather out in the world.",   -- PLACEHOLDER COPY (Marketing)
  game = "Game window",   -- PLACEHOLDER COPY (Marketing)
  gameTip = "Shows the game's own profession window instead (linking, its filters and Create All work there as always).",   -- PLACEHOLDER COPY (Marketing)
  make = "Make",   -- PLACEHOLDER COPY (Marketing)
  makeTip = "Makes this recipe the number of times in the box.",   -- PLACEHOLDER COPY (Marketing)
  makeAll = "Make All",   -- PLACEHOLDER COPY (Marketing)
  makeAllTip = "Makes as many as your materials allow.",   -- PLACEHOLDER COPY (Marketing)
  canMake = "You can make %d.",   -- PLACEHOLDER COPY (Marketing)
  reagents = "MATERIALS",   -- PLACEHOLDER COPY (Marketing)
  none = "No recipe matches.",   -- PLACEHOLDER COPY (Marketing)
  pick = "Pick a recipe on the left.",   -- PLACEHOLDER COPY (Marketing)
  pickNarrow = "Pick a recipe above.",   -- PLACEHOLDER COPY (Marketing)
  failed = "The game did not start %s (%s). The game's own profession window still works.",   -- PLACEHOLDER COPY (Marketing)
  combat = "The profession window can't change during combat.",   -- PLACEHOLDER COPY (Marketing)
}
PUI.CRAFT_FILTERS = {
  { text = "All recipes", value = "all", tip = "Every recipe you know." },   -- PLACEHOLDER COPY (Marketing)
  { text = "Can make", value = "make", tip = "Only the recipes your bags have the materials for." },   -- PLACEHOLDER COPY (Marketing)
}
PUI.craftFilter, PUI.craftQuery, PUI.craftQty = "all", "", 1
PUI.CRAFT_WAIT = 10   -- seconds a click of Open may take before the game opens the profession (else the claim lapses)
local function PWm() return Panoply.ProfWindow end
local function now() return (_G.GetTime and GetTime()) or 0 end
local function sessionName()
  local W = PWm()
  local n = W and W.ProfName and W:ProfName()
  if n == "Smelting" then n = "Mining" end
  return n
end
-- is the page's crafting view in use for this profession (the selected one when none is named)?
function PUI:CraftShown(name)
  name = name or self.selected
  local W = PWm()
  if not (self.craft and name and self.craft.prof == name and W and W.hosted) then return false end
  local tf = W:GameFrame()
  return tf ~= nil and tf.IsShown ~= nil and tf:IsShown() and true or false
end
-- PW.host: the page claims a session that its own Open button started (Modules/ProfWindow PW:OnOpen)
PUI.Host = {}
function PUI.Host:Claims()
  local want = PUI.craftWant
  if not want then return false end
  if now() - (PUI.craftWantAt or 0) > PUI.CRAFT_WAIT then PUI.craftWant = nil return false end
  local M = Panoply.Menu
  if not (M and M.frame and M.frame:IsShown() and M.current == "professions") then PUI.craftWant = nil return false end
  local n = sessionName()
  if n and n ~= want and PD[n] then PUI.craftWant = nil return false end   -- the game opened another profession than the one clicked
  return true
end
function PUI.Host:Opened()
  local want = PUI.craftWant
  PUI.craftWant = nil
  local same = PUI.craft and PUI.craft.prof == want
  PUI.craft = { prof = want }
  if not same then PUI.craftSel, PUI.craftQty = nil, 1 end
  if Panoply.Menu then Panoply.Menu:RefreshCurrent() end
end
function PUI.Host:Closed()
  local was = PUI.craft
  PUI.craft = nil
  if was and Panoply.Menu and Panoply.Menu.current == "professions" then Panoply.Menu:RefreshCurrent() end
end
-- (Modules/ProfWindow loads after this file and takes PUI.Host as its PW.host)
-- the open session's recipes, filtered by the search and Can make; { rows, kind, all }
function PUI:CraftRows()
  local W = PWm()
  local okR, rows, kind = pcall(C.TradeSkillDetails, W and W.session == "craft", W and W:WantBlizzard())
  if not okR then rows, kind = {}, nil end
  rows = rows or {}
  self.craftKind = kind
  local q = (self.craftQuery or ""):lower()
  local out = {}
  for _, r in ipairs(rows) do
    if W and W.CanMake then pcall(W.CanMake, W, r) end
    for _, rg in ipairs(r.reagents or {}) do
      if rg.have == nil and rg.itemID and C.ItemCount then local okC, n = pcall(C.ItemCount, rg.itemID) rg.bags = okC and tonumber(n) or 0
      else rg.bags = tonumber(rg.have) or 0 end
    end
    local ok = true
    if q ~= "" and not (r.name or ""):lower():find(q, 1, true) then
      ok = false
      for _, rg in ipairs(r.reagents or {}) do if rg.name and rg.name:lower():find(q, 1, true) then ok = true end end
    end
    if ok and self.craftFilter == "make" and (W and W.Short and W.Short(r)) then ok = false end
    if ok then out[#out + 1] = r end
  end
  self.craftRowsAll = rows
  return out, kind
end
function PUI:CraftSelected()
  for _, r in ipairs(self.craftRowsList or {}) do if r.name == self.craftSel then return r end end
  return nil
end
function PUI:CraftSelect(name)
  if self.craftSel == name then return false end
  self.craftSel, self.craftQty = name, 1
  local r = self:CraftSelected()
  if r then pcall(C.SelectRecipe, r, self.craftKind) end
  if Panoply.Menu then Panoply.Menu:RefreshCurrent() end
  return true
end
function PUI:CraftQtyN() return max(1, min(999, floor(tonumber(self.craftQty) or 1))) end
-- Make (n = the box) and Make All (n = nil: as many as the materials allow, counted live; one where the game cannot repeat)
function PUI:CraftMake(n)
  local r = self:CraftSelected()
  if not r then return false end
  local kind = self.craftKind
  if not n then
    local okR, rep = pcall(C.RecipeRepeat, r, kind)
    rep = okR and rep or { canRepeat = false, max = 1 }
    n = rep.canRepeat and max(1, rep.max or 1) or 1
  end
  local ok, why, made = C.MakeRecipe(r, kind, n)
  if not ok then
    Panoply:Print(PUI.CRAFT_COPY.failed:format(r.name or "?", why or "?"))
    local R = Panoply.Reports
    if R and R.NoteError then R:NoteError("caught", ("Make %s failed: %s"):format(tostring(r.name), tostring(why)), "", "profession page Make") end
    return false
  end
  self.lastMake = { name = r.name, n = made or n }
  return true, made or n
end
-- closing the view ends the profession session (the game's window closes with it: TRADE_SKILL_CLOSE)
function PUI:CraftClose()
  local W = PWm()
  local hosted = W and W.hosted
  self.craft = nil
  if hosted then pcall(C.CloseProfession, (W.session == "craft") and "Craft" or self.craftKind) end
  if Panoply.Menu and Panoply.Menu.current == "professions" then Panoply.Menu:RefreshCurrent() end
  return hosted and true or false
end
-- "Game window": the open session goes on in the game's own window (shown again, as it is without Panoply's view)
function PUI:CraftToGame()
  local W = PWm()
  local tf = W and W:GameFrame()
  if not (W and tf) then return false end
  if inCombat() and tf.IsProtected and tf:IsProtected() then Panoply:Print(PUI.CRAFT_COPY.combat) return false end
  W.hosted, W.showBlizzard = nil, true
  W:Untuck(tf)
  self.craft = nil
  if Panoply.Menu then Panoply.Menu:RefreshCurrent() end
  return true
end
-- the list follows the game's (a skill-up, a new recipe, materials looted)
for _, ev in ipairs({ "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_UPDATE", "BAG_UPDATE" }) do
  Panoply:On(ev, function()
    local M = Panoply.Menu
    if PUI.craft and M and M.current == "professions" and M.frame and M.frame:IsShown() then M:RefreshCurrent() end
  end)
end

-------------------------------------------------------------------------------
-- Pieces
-------------------------------------------------------------------------------
-- a map button: shows the place on the map (a dungeon: the dungeon map; else the world map at that spot)
local function mapButton(parent, tip)
  local b = Skin.IconButton(parent, "", 20, function(self) PUI:ShowOnMap(self.spot, self.instance) end, tip or "Show on the map",
    "Shows this place on your map.")
  b:SetIcon("Map", 14)
  b.panoplyKitIcon = "icon.ui.map"
  return b
end
function PUI:ShowOnMap(spot, instance)
  local M = Panoply.Map
  if instance and M and M.Instances and M.Instances.All and Panoply.Modules and Panoply.Modules:IsOn("map") then
    local want = instance:lower():gsub("^the ", "")
    for _, i in ipairs(M.Instances:All()) do
      if type(i.name) == "string" and i.name:lower():gsub("^the ", "") == want then M.Instances:Open(i.id) return true end
    end
  end
  if spot and spot.map then
    if M and M.Navigate and M.Navigate.ShowOnMap then return M.Navigate:ShowOnMap({ map = spot.map, x = spot.x, y = spot.y, name = spot.name }) end
    self:PointAt(spot, spot.name)
    return true
  end
  if instance then Panoply:Print(instance .. ": the dungeon map is not available.") end
  return false
end

-- one row of a tab: its mark (or a camp icon cell), text, the right-hand words, a map or arrow button; returns its height
local function drawRow(p, cd, e, x, y, w)
  local r = {}
  r.hl = cd:CreateTexture(nil, "BACKGROUND"); Skin.Solid(r.hl, Kit.Color("surface.2"), 1); r.hl:Hide()
  r.text = Skin.Ink(cd, 12); r.right = Skin.Ink(cd, 11, Kit.Color("text.muted"))
  if r.right.SetJustifyH then r.right:SetJustifyH("RIGHT") end
  r.tipFrame = CreateFrame("Button", nil, cd)
  Skin.Tooltip(r.tipFrame, "", nil)
  r.tipFrame.panoplyLayoutSkip = true
  r.tipFrame:SetScript("OnEnter", function(self) if self.tip and self.panoplyShowTip then self.panoplyShowTip() end end)
  r.tipFrame:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  r.text:SetText(e.text or ""); r.right:SetText(e.right or "")
  if e.header then
    local gt = Kit.Color("gold.title")
    r.text:SetTextColor(gt[1], gt[2], gt[3], 1)
  elseif e.note or e.unknown or e.done then tint(r.text, "text.muted")
  else tint(r.text, "text.primary") end
  local hasBtn = (e.spot and e.spot.map) or e.instance
  local inner = w - (hasBtn and 26 or 0)
  local solo = (e.right or "") == ""
  local mark = (not e.header) and (not e.note)
  local tx = e.header and 0 or (e.camp and 32 or (mark and 18 or 0))
  local lw, rw = floor((inner - tx) * 0.55), floor((inner - tx) * 0.45)
  local tw = solo and (inner - tx) or (lw - SP.s)
  r.text:SetWidth(tw); r.right:SetWidth(rw)
  r.text:SetPoint("TOPLEFT", cd, "TOPLEFT", x + tx, y)
  r.right:SetPoint("TOPRIGHT", cd, "TOPLEFT", x + inner, y)
  local th = TH(r.text, tw); r.text:SetHeight(th)
  local rh = max(16, th, (not solo) and TH(r.right, rw) or 0) + 4
  if not solo then r.right:SetHeight(TH(r.right, rw)) end
  if e.camp then
    local cell = Kit.IconCell(cd, { size = 28, accent = "professions" })
    local spell = e.camp.obj.name
    local tex = e.camp.state == "known" and Panoply.Icons:Spell(spell) or nil
    cell:SetTexture(tex or PUI.IconFor(p.panoplySelected))
    local st = ({ known = "done", owned = "progress", missing = "todo", locked = "locked" })[e.camp.state] or "todo"
    cell:SetState(st, { progress = 0.5, tip = e.tip, tipBody = e.tipBody })
    cell:SetPoint("TOPLEFT", cd, "TOPLEFT", x, y + 2)
    r.cell = cell
    rh = max(rh, 32)
  elseif mark then
    r.check = cd:CreateTexture(nil, "OVERLAY"); r.check:SetSize(13, 13)
    Skin.SetMark(r.check, e.done and "Ready" or "Waiting")
    r.check:SetVertexColor(1, 1, 1, e.done and 1 or 0.6)
    r.check:SetPoint("TOPLEFT", cd, "TOPLEFT", x, y)
  end
  r.hl:SetPoint("TOPLEFT", cd, "TOPLEFT", x - 4, y + 3); r.hl:SetSize(w + 4, rh)
  if e.current then r.hl:Show() end
  if hasBtn then
    if e.mapButton or e.instance then
      r.map = mapButton(cd)
      r.map.spot, r.map.instance = e.spot, e.instance
      r.map:SetPoint("TOPLEFT", cd, "TOPLEFT", x + w - 20, y + 2)
    else
      r.arrow = PUI.ArrowButton(cd, function(self) PUI:PointAt(self.spot, self.label2) end)
      r.arrow.spot, r.arrow.label2 = e.spot, e.text
      r.arrow:SetPoint("TOPLEFT", cd, "TOPLEFT", x + w - 20, y + 2)
    end
  end
  r.tipFrame:SetPoint("TOPLEFT", cd, "TOPLEFT", x, y + 2); r.tipFrame:SetSize(inner, rh)
  if e.tip then r.tipFrame.tip = e.tip; r.tipFrame.tipBody = e.tipBody end
  -- 0.9.5 phase 4G: a row that is a link to another page (spec 01 section 8): the click opens it, the hover lights the row
  if e.onClick then
    r.tipFrame:SetScript("OnClick", function() e.onClick() end)
    r.tipFrame:SetScript("OnEnter", function(self) r.hl:Show() if self.tip and self.panoplyShowTip then self.panoplyShowTip() end end)
    r.tipFrame:SetScript("OnLeave", function() if not e.current then r.hl:Hide() end if _G.GameTooltip then GameTooltip:Hide() end end)
    r.link = e.onClick
  end
  -- a secure button only on a row that opens a profession (a trainer visit): a redraw makes no others
  if e.openProf then
    PUI:SetOpen(r, cd, e.openProf)
    PUI:PlaceOpen(r, cd, x, y + 2, inner, rh)
  end
  r.entry = e
  p.rows[#p.rows + 1] = r
  return rh
end
Page.DrawRow = drawRow

-- a status chip's words for an entry
local CHIP_KIND = { craft = "craft", gather = "gather", train = "train", blocked = "blocked", maxed = "maxed" }

-- the list card of one profession (Wide): three rows (the name never shares its row, so it is whole at 1.3x text)
--   icon  name [guide badge]
--         status chip            skill / cap
--         skill bar to the rank cap
-- the trade camp and Mage Research: icon, name, one line under it. Selected = surface.2 and the section's accent stripe.
local function listCard(p, holder, e, v, x, y, w)
  local sel = PUI.selected == e.id
  local card = Kit.Surface(holder, sel and 2 or 1)
  card:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
  card:SetSize(w, Page.CARD_H)
  card:SetAccent(sel and accentOf(e.id) or nil)
  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetSize(24, 24); icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
  if e.kind == "camp" then
    local fac = (C.PlayerInfo and C.PlayerInfo() or {}).faction == "Horde" and "horde" or "alliance"
    if Kit.Icon(icon, "icon.trade." .. fac) == "missing" then icon:SetTexture(PUI.IconFor("Trade camp")) icon:Show() end
  else
    icon:SetTexture(PUI.IconFor(e.id))
    if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  end
  card.icon = icon
  local tx = 10 + 24 + SP.s
  local inner = w - tx - 10
  -- row 1: the name, and the guide badge after it when the guide follows this profession
  local badgeW = v.tracked and 18 or 0
  local name = Skin.Text(card, 13, Kit.Color("text.primary"), nil, "semi")
  if name.SetWordWrap then name:SetWordWrap(false) end
  local nw = inner - badgeW
  name:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -9)
  name:SetWidth(nw)
  Skin.Ellipsize(name, e.label, nw)
  local nh = ceil(TH(name, nw))
  name:SetHeight(nh)
  card.name = name
  if v.tracked then
    local badge = card:CreateTexture(nil, "OVERLAY")
    badge:SetSize(14, 14)
    if Kit.Icon(badge, "icon.guide", { size = 14 }) ~= "missing" then
      badge:SetPoint("TOPLEFT", card, "TOPLEFT", tx + min(nw, ceil(TW(name)) + 2) + 4, -9 - max(0, floor((nh - 14) / 2)))
      card.guideBadge = badge
    end
  end
  local ry = -9 - nh - SP.xs
  -- row 2: the chip at the left, the skill at the right (the trade camp and Mage Research: one line)
  local subText
  if e.kind == "camp" or e.kind == "starter" then subText = v.next and v.next.line or ""
  else subText = v.rank and ("%d / %d"):format(v.rank, v.max or 0) or "Not learned yet" end
  local chip
  if v.status and CHIP_KIND[v.status] then
    chip = Kit.StatusChip(card, CHIP_KIND[v.status])
    chip:SetPoint("TOPLEFT", card, "TOPLEFT", tx, ry)
  end
  card.chip = chip
  local cw = chip and (ceil(chip:GetWidth()) + SP.s) or 0
  local sub = Skin.Ink(card, 11, Kit.Color("text.muted"))
  if sub.SetWordWrap then sub:SetWordWrap(false) end
  local sw = inner - cw
  sub:SetWidth(sw)
  if chip and sub.SetJustifyH then sub:SetJustifyH("RIGHT") end
  Skin.Ellipsize(sub, subText, sw)
  local sh = ceil(TH(sub, sw))
  sub:SetHeight(sh)
  local rowH = max(sh, chip and ceil(chip:GetHeight()) or 0)
  sub:SetPoint("TOPLEFT", card, "TOPLEFT", tx + cw, ry - max(0, floor((rowH - sh) / 2)))
  ry = ry - rowH
  -- row 3: the skill bar to the rank cap
  local bar
  if e.kind == "prof" and v.rank and (v.max or 0) > 0 then
    ry = ry - SP.xs
    bar = Kit.ProgressBar(card, { h = 6, accent = accentOf(e.id) })
    bar:SetPoint("TOPLEFT", card, "TOPLEFT", tx, ry)
    bar:SetBarWidth(inner)
    bar:SetValue(v.rank, v.max)
    ry = ry - 6
  end
  card.bar, card.sub = bar, sub
  local h = max(Page.CARD_H, -ry + 9)
  card:SetHeight(h)
  -- the click: an invisible button over the card
  local hit = CreateFrame("Button", nil, card)
  hit:SetAllPoints(card)
  hit.panoplyLayoutSkip = true
  hit.panoplyProf = e.id
  Skin.Tooltip(hit, e.label, (v.skill or subText) .. (v.tracked and ". The guide follows this one." or ""))
  hit:SetScript("OnEnter", function(self) if not sel then card:SetLevel(2) end if self.panoplyShowTip then self.panoplyShowTip() end end)
  hit:SetScript("OnLeave", function() if not sel then card:SetLevel(1) end if _G.GameTooltip then GameTooltip:Hide() end end)
  hit:SetScript("OnClick", function() PUI:Select(e.id) end)
  card.hit = hit
  card.panoplyEntry = e
  p.cards[e.id] = card
  return h
end

-- a muted list row (not learned, open primary slot)
local function mutedRow(p, holder, e, x, y, w)
  local b = CreateFrame("Button", nil, holder)
  b:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
  local fs = Skin.Ink(b, 12, Kit.Color("text.muted"))
  fs:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -4)
  fs:SetWidth(w - 20)
  local label = e.kind == "slot" and "Open primary slot: pick one" or (e.label .. ": not learned")
  fs:SetText(label)
  local th = ceil(TH(fs, w - 20)); fs:SetHeight(th)
  b:SetSize(w, th + 8)
  b.label = fs
  b.panoplyProf = e.id
  local sel = PUI.selected == e.id
  if sel then
    local hl = b:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(b); Skin.Solid(hl, Kit.Color("surface.2"), 1)
  end
  Skin.Tooltip(b, e.kind == "slot" and "Open primary slot" or e.label,
    e.kind == "slot" and "You know fewer than two primary professions. Click to plan one." or "A secondary profession you have not learned. Click to see how to start.")
  b:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() PUI:Select(e.id) end)
  p.cards[e.id] = b
  return th + 8
end

-- the rail (Medium): an icon cell per entry with a skill ring and a status dot; the name in the tooltip
local DOT = { craft = "state.good", gather = "state.good", train = "state.warn", blocked = "state.bad", maxed = "state.idle" }
local function railCell(p, holder, e, v, x, y, w)
  local s = 40
  local cell = Kit.IconCell(holder, { size = s, accent = e.kind == "prof" and accentOf(e.id) or "professions", onClick = function() PUI:Select(e.id) end })
  cell:SetPoint("TOPLEFT", holder, "TOPLEFT", x + floor((w - s) / 2), y)
  cell:SetTexture(PUI.IconFor(e.kind == "camp" and "Trade camp" or e.id))
  local state = (e.kind == "notlearned" or e.kind == "slot" or e.kind == "starter") and "todo" or ((v.status == "maxed") and "done" or "progress")
  local tipBody = e.kind == "slot" and "You know fewer than two primary professions. Click to plan one."
    or ((v.skill or (v.next and v.next.line) or "") .. (v.status and CHIP_KIND[v.status] and (". " .. Kit.CHIPS[CHIP_KIND[v.status]][1]) or ""))
  cell:SetState(state, { progress = (v.rank and (v.max or 0) > 0) and (v.rank / v.max) or 0, tip = e.label, tipBody = tipBody })
  if v.status and DOT[v.status] then
    local dot = cell:CreateTexture(nil, "OVERLAY", nil, 6)
    dot:SetSize(10, 10)
    Skin.Round(dot, 5, Skin.TEX.RFill)
    local c = Kit.Color(DOT[v.status])
    dot:SetVertexColor(c[1], c[2], c[3], 1)
    dot:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", -2, -2)
    cell.dot = dot
    cell.panoplyDot = v.status
  end
  if PUI.selected == e.id then
    local hl = holder:CreateTexture(nil, "BACKGROUND")
    hl:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y + 4); hl:SetSize(w, s + 8)
    Skin.Solid(hl, Kit.Color("surface.2"), 1)
  end
  cell.panoplyProf = e.id
  p.cards[e.id] = cell
  return s + SP.m
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
Panoply.Kit.TabVar("professions", { get = function() return PUI.page end, set = function(k) PUI.page = PUI.OLD_TABS[k] or k end, default = "Steps",
  valid = function(k) return PUI.PAGE_TIPS[k] ~= nil or PUI.OLD_TABS[k] ~= nil end })

Panoply.Kit.Holds("professions", function()
  local p = Panoply.Menu and Panoply.Menu.pages and Panoply.Menu.pages.Professions
  return p
end)

Panoply.Menu:RegisterTab("Professions", function(p)
  local K = Panoply.Kit
  p.cards, p.rows = {}, {}
  -- the list (Wide and Medium) scrolls on its own when it is longer than the page
  p.listArea = Skin.ScrollArea(p)
  -- the tabs: every tab any profession has; a profession shows those of its type
  local items = {}
  for _, k in ipairs(PUI.PAGES) do items[#items + 1] = { key = k, label = k, tip = k, tipBody = PUI.PAGE_TIPS[k] } end
  p.kitTabs = K.Tabs(p, { page = "professions", items = items, default = "Steps", minW = 70, style = "underline",
    get = function() return PUI.selected and PUI:TabFor(PUI.selected) or PUI.page end,
    onSelect = function(k) PUI.page = k Page.pendingTop = true end })
  p.pageTabs = p.kitTabs.buttons
  -- the plan of the selected profession
  local PP = Panoply.ProfPlans
  local choices = {}
  for _, c in ipairs(PP.CHOICES) do choices[#choices + 1] = { text = c.text, value = c.value, tip = c.tip } end
  -- In a fight the choice waits for the end of it, like every control of a page that holds secure buttons; it is made for the
  -- profession that was on screen when it was clicked (guard: noted then), even if another one is picked before the fight ends.
  p.planDD = K.Dropdown(p, { page = "professions", width = 170, height = 24, tip = "This profession's plan",
    guard = function() p.planDD.panoplyPending = p.planDD.panoplyFor return false end,
    tipBody = "How Panoply plans this profession: the cheapest or the fastest recipes, from your skill or from skill 1. Each profession has its own.",
    items = choices, get = function() local n = p.planDD and p.planDD.panoplyFor or PUI.selected return n and PP:Choice(n) end,
    -- the profession it was drawn for (a choice made in a fight is applied after it, when another may be selected)
    set = function(v)
      local n = p.planDD.panoplyPending or p.planDD.panoplyFor or PUI.selected
      p.planDD.panoplyPending = nil
      if n then PP:SetChoice(n, v) end
    end,
    onChange = function() Panoply.Menu:RefreshCurrent() end })
  p.byHand = Skin.Button(p, "By hand", 90, 24, function() Panoply.SettingsUI:OpenOverrides() end, "Change by hand",
    "Panoply reads your professions from your skills by itself. Click to plan one you have not learned yet, or to hide one.")
  p.byHand.panoplyEditIcon = p.byHand:CreateTexture(nil, "ARTWORK")
  if Kit.Icon(p.byHand.panoplyEditIcon, "icon.ui.edit", { size = 14 }) ~= "missing" then
    p.byHand.panoplyEditIcon:SetSize(14, 14)
    p.byHand.panoplyEditIcon:SetPoint("LEFT", p.byHand, "LEFT", 8, 0)
    p.byHand.label:ClearAllPoints(); p.byHand.label:SetPoint("CENTER", p.byHand, "CENTER", 9, 0)
    p.byHand.panoplyEditW = 18
  end
  -- the game's profession window (a spell: a secure button over this one)
  -- 0.9.6 phase K: the page's primary button, first in its header: taller, the profession's icon, the selected look (brass rim). Its
  -- click opens the profession here on the page (the crafting view); while that view shows, it closes it (a plain click).
  p.openWin = Skin.Button(p, "Open window", 140, 28, function() if PUI:CraftShown() then PUI:CraftClose() end end,
    "Open the profession window", "Opens this profession's window.")
  p.openWin.panoplyPrimary = true
  p.openWin:SetSelected(true)
  local oi = p.openWin:CreateTexture(nil, "ARTWORK")
  oi:SetSize(18, 18)
  if oi.SetTexCoord then oi:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  p.openWin.icon, p.openWin.panoplyIconPoint, p.openWin.panoplyIconX, p.openWin.panoplyLabelX = oi, "LEFT", 8, 11
  oi:SetPoint("LEFT", p.openWin, "LEFT", 8, 0)
  p.openWin.label:ClearAllPoints(); p.openWin.label:SetPoint("CENTER", p.openWin, "CENTER", 11, 0)
  p.openWinR = { tipFrame = p.openWin }
  -- 0.9.6 phase K: the crafting view's own pieces (kept, like the search, so a redraw does not lose them)
  p.craftDD = K.Dropdown(p, { page = "professions", width = 130, height = 24, tip = "Show", tipBody = "All your recipes, or only those you have the materials for.",
    items = PUI.CRAFT_FILTERS, get = function() return PUI.craftFilter end, set = function(v) PUI.craftFilter = v end,
    onChange = function() Panoply.Menu:RefreshCurrent() end })
  p.craftGame = Skin.Button(p, PUI.CRAFT_COPY.game, 110, 24, function() PUI:CraftToGame() end, PUI.CRAFT_COPY.game, PUI.CRAFT_COPY.gameTip)
  p.craftArea = Skin.ScrollArea(p)        -- the recipe list
  p.craftInfo = Skin.ScrollArea(p)        -- the selected recipe: name, count, materials
  p.craftMake = Skin.Button(p, PUI.CRAFT_COPY.make, 80, 24, function() PUI:CraftMake(PUI:CraftQtyN()) end, PUI.CRAFT_COPY.make, PUI.CRAFT_COPY.makeTip)
  p.craftMakeAll = Skin.Button(p, PUI.CRAFT_COPY.makeAll, 90, 24, function() PUI:CraftMake(nil) end, PUI.CRAFT_COPY.makeAll, PUI.CRAFT_COPY.makeAllTip)
  -- the quantity: - [n] +
  local q = CreateFrame("Frame", nil, p)
  q:SetSize(78, 24)
  q.minus = Skin.Button(q, "-", 20, 22, function() PUI.craftQty = max(1, PUI:CraftQtyN() - 1) q.input:SetText(tostring(PUI.craftQty)) end, "Fewer", "Make one less.")
  q.minus:SetPoint("LEFT", q, "LEFT", 0, 0)
  local box = CreateFrame("EditBox", nil, q)
  box:SetSize(34, 22)
  if box.SetAutoFocus then box:SetAutoFocus(false) end
  if box.SetNumeric then box:SetNumeric(true) end
  if box.SetMaxLetters then box:SetMaxLetters(3) end
  if box.SetFont then pcall(box.SetFont, box, Skin.BODY, 13, "") end
  if box.SetJustifyH then box:SetJustifyH("CENTER") end
  box:SetText("1")
  Skin.Box(box, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  box:SetPoint("LEFT", q.minus, "RIGHT", 2, 0)
  box:SetScript("OnTextChanged", function(self)
    local n = tonumber(self:GetText())
    if n and n >= 1 then PUI.craftQty = min(999, floor(n)) end
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() PUI:CraftMake(PUI:CraftQtyN()) end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  Skin.Tooltip(box, "How many to make", "Type a number, or use - and +. Make crafts this many; Enter does too.")
  q.input = box
  q.plus = Skin.Button(q, "+", 20, 22, function() PUI.craftQty = min(999, PUI:CraftQtyN() + 1) q.input:SetText(tostring(PUI.craftQty)) end, "More", "Make one more.")
  q.plus:SetPoint("LEFT", box, "RIGHT", 2, 0)
  p.craftQty = q
  -- leaving the page (another page, the window closed) ends the crafting view and its session
  if p.HookScript then
    p:HookScript("OnHide", function()
      C.After(0, function()
        local M = Panoply.Menu
        if PUI.craft and not (M and M.frame and M.frame:IsShown() and M.current == "professions") then PUI:CraftClose() end
      end)
    end)
  end
  -- Recipes: search and the learned filter (kept, so typing is not lost when the list draws again)
  p.search = Skin.Input(p, 180, 24, "Search recipes")
  -- the list is drawn again a moment after the typing stops, not on every key
  p.search:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if self.placeholder then if t == "" then self.placeholder:Show() else self.placeholder:Hide() end end
    -- 0.9.6 phase K: in the crafting view the same box searches the open profession's recipes (its own query)
    local key = PUI:CraftShown() and "craftQuery" or "recipeQuery"
    if t == (PUI[key] or "") then return end
    self.panoplyTyped = (self.panoplyTyped or 0) + 1
    local n = self.panoplyTyped
    C.After(Page.SEARCH_WAIT, function()
      if self.panoplyTyped ~= n then return end
      local now = self:GetText() or ""
      if now ~= (PUI[key] or "") then PUI[key] = now Panoply.Menu:RefreshCurrent() end
    end)
  end)
  p.filterDD = K.Dropdown(p, { page = "professions", width = 140, height = 24, tip = "Show", tipBody = "All recipes, only the learned ones, or only the ones still to learn.",
    items = PUI.RECIPE_FILTERS, get = function() return PUI.recipeFilter end, set = function(v) PUI.recipeFilter = v end,
    onChange = function() Panoply.Menu:RefreshCurrent() end })
  -- the tab content scrolls
  p.tabArea = Skin.ScrollArea(p)
  Page.tabArea = p.tabArea
  p.none = Skin.Ink(p, 12, Kit.Color("text.muted"))
end, function(p) PUI:Render(p) end)

-- the signature of what is drawn: when it is the same as last time, nothing is drawn again
local function signature(p, entries, views, W, H, band)
  local t = { tostring(PUI.selected), W, H, band, PUI.recipeFilter or "", PUI.recipeQuery or "" }
  for _, e in ipairs(entries) do
    local v = views[e.id] or {}
    local n = v.next or {}
    t[#t + 1] = table.concat({ e.id, e.kind, tostring(v.rank), tostring(v.max), tostring(v.status), tostring(v.tracked), n.kind or "", n.title or "", n.line or "",
      n.blocker or "", n.perkNote or "" }, "~")
  end
  local v = views[PUI.selected or ""]
  if v then
    t[#t + 1] = table.concat({ tostring(v.page), v.range or "", v.footer or "", v.skill or "" }, "~")
    for _, e in ipairs(v.rows or {}) do
      t[#t + 1] = table.concat({ e.text or "", e.right or "", tostring(e.header), tostring(e.done), tostring(e.current), e.tip or "", e.tipBody or "",
        e.openProf or "", e.spot and e.spot.map and (e.spot.map .. ":" .. tostring(e.spot.x) .. ":" .. tostring(e.spot.y)) or "", e.camp and e.camp.state or "", e.camp and e.camp.cooldown and tostring(math.ceil(e.camp.cooldown / 60)) or "" }, "~")
    end
    local PP = Panoply.ProfPlans
    if PP and PUI.selected then t[#t + 1] = PP:Choice(PUI.selected) end
    -- 0.9.6 phase K: the starter guide's pick and trainer; the crafting view's recipes, materials and pick
    if v.kind == "starter" then t[#t + 1] = table.concat({ tostring(v.pick), v.classFile or "", v.trainer and v.trainer.text or "" }, "~") end
  end
  t[#t + 1] = table.concat({ "craft", tostring(PUI.craft and PUI.craft.prof), tostring(PUI:CraftShown()), PUI.craftFilter or "", PUI.craftQuery or "",
    tostring(PUI.craftSel) }, "~")
  for _, r in ipairs(PUI.craftRowsList or {}) do
    local rg = {}
    for _, g in ipairs(r.reagents or {}) do rg[#rg + 1] = tostring(g.name) .. "=" .. tostring(g.bags) .. "/" .. tostring(g.need) end
    t[#t + 1] = table.concat({ r.name or "", tostring(r.numAvailable), tostring(r.difficulty), r.category or "", table.concat(rg, ",") }, "~")
  end
  return table.concat(t, "|")
end

function PUI:Render(p)
  local chosen = self:Chosen()
  if Panoply.ProfPlans then Panoply.ProfPlans:Migrate(chosen) end
  self:FixSelected()
  local entries = self:Entries()
  local snap = self:Snapshot()
  self.snap = snap
  local views = {}
  -- the list needs each profession's status and Next card; only the selected one builds its tab rows
  for _, e in ipairs(entries) do
    if e.kind ~= "slot" then
      if e.id == self.selected then views[e.id] = self:EntryView(e.id, snap)
      elseif e.kind == "prof" or e.kind == "camp" or e.kind == "research" or e.kind == "starter" then views[e.id] = self:EntryView(e.id, snap, true) end
    end
  end
  local sel = self.selected
  -- 0.9.6 phase K: the crafting view belongs to one profession: picking another one ends its session (never in a fight)
  if self.craft and self.craft.prof ~= sel and not inCombat() then
    local PWin = Panoply.ProfWindow
    self.craft = nil
    if PWin and PWin.hosted then pcall(C.CloseProfession, (PWin.session == "craft") and "Craft" or self.craftKind) end
  end
  self.craftRowsList = nil
  if self:CraftShown(sel) then
    self.craftRowsList = self:CraftRows()
    if not self:CraftSelected() then
      local first = self.craftRowsList[1]
      self.craftSel = first and first.name or nil
      if first then pcall(C.SelectRecipe, first, self.craftKind) end
    end
  end
  local v = sel and views[sel] or (sel and self:EntryView(sel, snap)) or self:View(nil)
  views[sel or ""] = v
  self.view, self.lastSummary, self.views = v, v, views
  local W, H = p.width or 600, p.height or 400
  local band = Kit.Band(W)
  local sig = signature(p, entries, views, W, H, band)
  if p.sig == sig and not (self.secureMissing and not inCombat()) then return end
  if inCombat() and p.drawn then self.pendingDraw = true Panoply.Kit.MarkDirty("professions") return end
  self.pendingDraw = nil
  self.secureMissing = nil
  p.sig = sig
  p.drawn = true
  Page:Draw(p, entries, views, v, W, H, band)
end

-- every piece placed for a width W and a height H in a band
function Page:Draw(p, entries, views, v, W, H, band)
  local sel = PUI.selected
  p.band = band
  p.panoplySelected = sel
  -- the frames of the last drawing go (the persistent pieces stay)
  if p.fixed then p.fixed:Hide() end
  if p.listHolder then p.listHolder:Hide() end
  if p.content then p.content:Hide() end
  p.cards, p.rows = {}, {}
  local fixed = CreateFrame("Frame", nil, p)
  fixed:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); fixed:SetSize(W, H)
  fixed.panoplyGapOK = true
  p.fixed = fixed
  if p.craftContent then p.craftContent:Hide() end
  if p.craftInfoContent then p.craftInfoContent:Hide() end
  -- (0.9.6 phase K: no bare "nothing learned" line any more: a character with no profession gets the starter guide)
  p.none:Hide()
  local y = 0
  local DX, DW
  -- the starter guide alone (Classic, nothing learned): the whole page, no list beside it
  local solo = #entries == 1 and entries[1].kind == "starter"
  -- the list: Wide a list of cards, Medium a rail, Narrow chips on top
  if solo then
    p.listArea:Hide()
    DX, DW = 0, W
  elseif band == "narrow" then
    p.listArea:Hide()
    local cy, cx, rowH = 0, 0, 0
    for _, e in ipairs(entries) do
      local ev = views[e.id] or {}
      local label = e.kind == "slot" and "Open slot" or e.label
      local b = Skin.Button(fixed, label, 80, 24, function() PUI:Select(e.id) end, e.label,
        (ev.skill or (ev.next and ev.next.line) or (e.kind == "notlearned" and "Not learned" or "")))
      Skin.FitButton(b, 60, W)
      if e.kind == "notlearned" or e.kind == "slot" then tint(b.label, "text.muted") end
      if e.id == sel then b:SetSelected(true) end
      local bw = b:GetWidth()
      if cx > 0 and cx + bw > W then cx = 0 cy = cy - rowH - SP.s rowH = 0 end
      b:SetPoint("TOPLEFT", fixed, "TOPLEFT", cx, cy)
      cx = cx + bw + SP.s
      rowH = max(rowH, b:GetHeight())
      b.panoplyProf = e.id
      p.cards[e.id] = b
    end
    y = cy - rowH - SP.m
    DX, DW = 0, W
  else
    local LW = band == "wide" and Page.LIST_W or Page.RAIL_W
    local area = p.listArea
    area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); area:SetSize(LW, H)
    area:Show()
    local holder = CreateFrame("Frame", nil, area.content)
    holder:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
    holder.panoplyGapOK = true
    p.listHolder = holder
    local cw = LW - 12
    local ly = 0
    local mutedLabel = false
    for _, e in ipairs(entries) do
      local ev = views[e.id] or {}
      if band == "wide" then
        if (e.kind == "notlearned" or e.kind == "slot") and not mutedLabel then
          mutedLabel = true
          local lab = Skin.Label(holder, 10); lab:SetText("NOT LEARNED")
          lab:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, ly - SP.xs); lab:SetWidth(cw - 10)
          local lh = ceil(TH(lab, cw - 10)); lab:SetHeight(lh)
          ly = ly - lh - SP.s
        end
        if e.kind == "notlearned" or e.kind == "slot" then ly = ly - mutedRow(p, holder, e, 0, ly, cw) - 2
        else ly = ly - listCard(p, holder, e, ev, 0, ly, cw) - SP.s end
      else
        ly = ly - railCell(p, holder, e, ev, 0, ly - 4, cw)
      end
    end
    holder:SetSize(cw, max(1, -ly))
    area:SetContentHeight(-ly + SP.s)
    DX, DW = LW + Page.GAP, W - LW - Page.GAP
  end
  self:DrawDetail(p, fixed, v, DX, y, DW, H)
end

-- the detail of the selected entry: header, bar, Next card, tabs, (search row), the scrolling tab content
function Page:DrawDetail(p, fixed, v, X, y, DW, H)
  local sel = PUI.selected
  local isProf = v and v.kind ~= "tradecamp" and v.kind ~= "research"
  local learned = isProf and v.rank ~= nil and (v.max or 0) > 0
  for _, f in ipairs({ p.craftDD, p.craftGame, p.craftArea, p.craftInfo, p.craftMake, p.craftMakeAll, p.craftQty }) do f:Hide() end
  p.craftRows, p.starter = nil, nil
  -- 0.9.6 phase K: the starter guide (no profession learned yet) has its own layout
  if v and v.kind == "starter" then return self:DrawStarter(p, fixed, v, X, y, DW, H) end
  -- 1. header. 0.9.6 phase K: the name and, first in the header at the right, the primary button that opens this profession here on
  -- the page (its icon, the brass rim); under them the plan and By hand. With no room beside the name, the button goes under it.
  local title = Skin.Heading(fixed, 17, v.name or sel or "")
  local gt = Kit.Color("gold.title")
  title:SetTextColor(gt[1], gt[2], gt[3], 1)
  if title.SetWordWrap then title:SetWordWrap(false) end
  title:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y)
  p.title = title
  local ctrls = {}
  if isProf and PD[sel or ""] and PD[sel].ranks then
    p.planDD.panoplyFor = sel
    p.planDD:Fit(140, 200)
    ctrls[#ctrls + 1] = p.planDD
    Skin.FitButton(p.byHand, 80, 130)
    if p.byHand.panoplyEditW then p.byHand:SetWidth(p.byHand:GetWidth() + p.byHand.panoplyEditW) end
    ctrls[#ctrls + 1] = p.byHand
  else p.planDD:Hide() p.byHand:Hide() end
  local CC = PUI.CRAFT_COPY
  local PWin = Panoply.ProfWindow
  local spell = learned and PWin and PWin:SpellFor(sel) or nil
  local craftOn = learned and PUI:CraftShown(sel)
  local primary = learned and true or false
  local canOpen = spell ~= nil and not craftOn
  local ob = p.openWin
  p.panoplyCraftOn = craftOn
  if primary then
    ob.icon:SetTexture(PUI.IconFor(sel)); ob.icon:Show()
    if craftOn then
      ob.label:SetText(CC.close:format(sel)); ob.tip, ob.tipBody = CC.close:format(sel), CC.closeTip
    else
      ob.label:SetText(CC.open:format(sel)); ob.tip = CC.open:format(sel)
      ob.tipBody = spell and CC.openTip:format(sel) or CC.noWindow:format(sel)
    end
    ob:SetEnabledLook(spell ~= nil)
    ob:SetSelected(spell ~= nil)
    ob.panoplyNoWindow = spell == nil or nil
    Skin.FitButton(ob, 120, max(120, min(260, DW)))
    if ob:GetHeight() < 28 then ob:SetHeight(28) end
  else
    if not inCombat() then ob:Hide() if p.openWinR.open then p.openWinR.open:Hide() end end
  end
  local th = 22
  local twNeed = ceil(TW(title)) + 2
  local placeCtrls = not (inCombat() and Kit.Protected and Kit.Protected(p.openWin))
  local function put(c, cx, cy)
    if placeCtrls or c ~= p.openWin then
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", p, "TOPLEFT", cx, cy)
      c:Show()
    end
  end
  local bw, bh = primary and ob:GetWidth() or 0, primary and max(28, ob:GetHeight()) or 0
  if primary and DW - bw - SP.m >= min(twNeed, 160) then
    local tw = DW - bw - SP.m
    title:SetWidth(tw); title:SetHeight(th)
    Skin.Ellipsize(title, v.name or sel or "", tw)
    put(ob, X + DW - bw, y)
    p.panoplyPrimaryRow = "beside"
    y = y - max(th, bh) - SP.s
  else
    title:SetWidth(DW); title:SetHeight(th)
    Skin.Ellipsize(title, v.name or sel or "", DW)
    if primary then
      y = y - th - SP.xs
      put(ob, X, y)
      p.panoplyPrimaryRow = "under"
      y = y - bh - SP.s
    else
      y = y - th - SP.s
    end
  end
  -- the plan and By hand: their own row under the header, left to right (a second row when they do not fit one)
  if #ctrls > 0 then
    local cy, cx, rowH = y, X, 0
    for _, c in ipairs(ctrls) do
      local cw = min(c:GetWidth(), DW)
      if cw < c:GetWidth() then c:SetWidth(cw) if c.Refresh then c:Refresh() end end
      if cx > X and cx + cw > X + DW then cx = X cy = cy - rowH - SP.xs rowH = 0 end
      put(c, cx, cy)
      cx = cx + cw + SP.s
      rowH = max(rowH, c:GetHeight() or 24)
    end
    y = cy - rowH - SP.s
  end
  -- the secure button lies over the visible one: a click is the player's own, and casts the profession's spell (Smelting for Mining).
  -- Its PreClick tells the page that this click asked for the page's crafting view (PW.host claims the session it opens).
  if canOpen then
    PUI:SetOpen(p.openWinR, p, sel)
    ob.tipBody = CC.openTip:format(sel)
    local o = p.openWinR.open
    if o and not inCombat() then
      o:ClearAllPoints(); o:SetAllPoints(ob)
      if not o.panoplyPage then
        o.panoplyPage = true
        o:SetScript("PreClick", function(self) PUI.craftWant, PUI.craftWantAt = self.panoplyProf, now() end)
        for _, k in ipairs({ "OnMouseDown", "OnMouseUp" }) do
          o:SetScript(k, function() local h = ob:GetScript(k) if h then h(ob) end end)
        end
      end
    end
  elseif p.openWinR.open and not inCombat() then
    p.openWinR.open:Hide()
  end
  if p.openWinR.open and p.openWinR.open.SetFrameLevel and not inCombat() then p.openWinR.open:SetFrameLevel((p.openWin:GetFrameLevel() or 1) + 2) end
  -- 2. the skill bar, the rank and (WoW Forever, crafting) the Legacy marks
  if learned then
    local lab = Skin.Ink(fixed, 11, Kit.Color("text.primary"))
    if lab.SetWordWrap then lab:SetWordWrap(false) end
    local rk = v.gate and v.gate.rank
    local rankName
    for _, r in ipairs(PD[sel] and Panoply.Professions:Ranks(PD[sel]) or {}) do if r.max == v.max then rankName = r.name end end
    local text = ("Skill %d / %d%s"):format(v.rank, v.max, rankName and (" · " .. rankName) or "")
    if rk then text = text .. ("  ·  next: %s at %d%s"):format(rk.name, v.gate.skill, (v.gate.level or 0) > 1 and (", level " .. v.gate.level) or "") end
    lab:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y); lab:SetWidth(DW)
    Skin.Ellipsize(lab, text, DW)
    local lh = ceil(TH(lab, DW)); lab:SetHeight(lh)
    y = y - lh - SP.xs
    local bar = Kit.ProgressBar(fixed, { h = 8, accent = accentOf(sel) })
    bar:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y - 2)
    bar:SetBarWidth(DW)
    bar:SetValue(v.rank, 300)
    local ticks = {}
    if C.IsForever() and v.kind == "crafting" then
      for _, at in ipairs({ 150, 225, 300 }) do
        ticks[#ticks + 1] = { value = at, reached = v.rank >= at, key = "legacy" .. at, tip = ("Legacy: %s %d"):format(sel, at),
          tipBody = "A Legacy challenge counts this skill. Click to open the Legacy page.",
          onClick = function() PUI:OpenLegacy(sel, at) end }
      end
    end
    bar:SetTicks(ticks)
    p.bar, p.barLabel = bar, lab
    y = y - 8 - SP.m - 4
  else
    p.bar, p.barLabel = nil, nil
  end
  -- 0.9.6 phase K: the crafting view takes the room of the Next card, the tabs and their content
  if craftOn then return self:DrawCraft(p, fixed, v, X, y, DW, H) end
  -- 3. the Next card: a fixed height; two lines at the least height
  local hasTabs = isProf and v.plan ~= nil
  local room = H + y - Page.NEXT_H - SP.m - (hasTabs and (Kit.TAB.h + SP.s) or 0) - ((hasTabs and v.page == "Recipes") and (24 + SP.s) or 0) - Page.GRIP
  local compact = room < Page.COMPACT_ROOM
  local nh = compact and Page.NEXT_H_MIN or Page.NEXT_H
  local card = Kit.Surface(fixed, 1)
  card:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y)
  card:SetSize(DW, nh)
  local n = v.next or { kind = "none", title = "", line = "" }
  local blocked = n.kind == "blueprint" or n.kind == "favor" or v.status == "blocked"
  card:SetAccent(blocked and Kit.Color("state.bad") or (isProf and accentOf(sel) or "professions"))
  card.panoplyNext = n
  self:DrawNext(p, card, n, v, DW, nh, compact)
  p.nextCard = card
  y = y - card:GetHeight() - SP.m
  -- 4. the tabs (Narrow: a dropdown); trade camp and Mage Research have none
  local tabs = p.kitTabs
  if hasTabs then
    local mine = {}
    for _, k in ipairs(PUI:TabsFor(sel)) do mine[k] = true end
    for _, k in ipairs(PUI.PAGES) do tabs:SetShown(k, mine[k] or false) end
    local th2 = tabs:Layout(X, y, DW, p.band == "narrow" and "dropdown" or nil)
    y = y - th2 - SP.s
  else
    tabs:HideAll(); if tabs.dd then tabs.dd:Hide() end
  end
  -- 5. Recipes: the search row
  if hasTabs and v.page == "Recipes" then
    local sw = min(220, DW - 150 - SP.s)
    p.search:SetSize(max(120, sw), 24)
    p.search:ClearAllPoints(); p.search:SetPoint("TOPLEFT", p, "TOPLEFT", X, y)
    if (p.search:GetText() or "") ~= (PUI.recipeQuery or "") then p.search:SetText(PUI.recipeQuery or "") end
    p.search:Show()
    p.filterDD:Fit(120, 160)
    p.filterDD:ClearAllPoints(); p.filterDD:SetPoint("TOPLEFT", p, "TOPLEFT", X + p.search:GetWidth() + SP.s, y)
    p.filterDD:Show()
    y = y - 24 - SP.s
  else
    p.search:Hide(); p.filterDD:Hide()
  end
  -- 6. the content: the only part that scrolls
  local area = p.tabArea
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", X, y)
  -- (it stops above the page's bottom: the window's rounded corner and its resize grip are there, and its scroll bar runs down the right)
  -- (never past the page's bottom, however short the window: the pinned part comes first)
  local ah = max(1, H + y - Page.GRIP)
  area:SetSize(DW, ah)
  area:Show()
  local content = CreateFrame("Frame", nil, area.content)
  content:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
  content.panoplyGapOK = true
  p.content = content
  local cw = DW - 14
  local cy = -2
  for _, e in ipairs(v.rows or {}) do cy = cy - drawRow(p, content, e, 4, cy, cw - 4) end
  if (v.footer or "") ~= "" then
    local ft = Skin.Ink(content, 11, Kit.Color("text.primary")); ft:SetText(v.footer)
    ft:SetPoint("TOPLEFT", content, "TOPLEFT", 4, cy - SP.s); ft:SetWidth(cw - 4)
    local fh = ceil(TH(ft, cw - 4)); ft:SetHeight(fh)
    cy = cy - SP.s - fh
    p.footer = ft
  end
  content:SetSize(cw, max(1, -cy))
  area:SetContentHeight(-cy + SP.s)
  if PUI.pendingScroll or Page.pendingTop then
    local s = Page.pendingTop and 0 or PUI.pendingScroll
    PUI.pendingScroll, Page.pendingTop = nil, nil
    if area.SetVerticalScroll then area:SetVerticalScroll(max(0, min(area:MaxScroll(), s or 0))) end
    area:UpdateBar()
  end
end

-- 0.9.6 phase K: the starter guide. Pinned: the heading, one line, and the pick's card (where to learn it: Take me there, Find a
-- trainer). Scrolling under it: the class's suggested pairs, the main professions as a grid of cells (icon, name, one line; the
-- suggested ones carry the accent stripe), and the easy extras. The grid has 3 columns where there is room, else 2, else 1.
function Page:DrawStarter(p, fixed, v, X, y, DW, H)
  local T = PUI.STARTER_COPY
  if not inCombat() then
    p.openWin:Hide()
    if p.openWinR.open then p.openWinR.open:Hide() end
  end
  for _, f in ipairs({ p.planDD, p.byHand, p.search, p.filterDD }) do f:Hide() end
  p.kitTabs:HideAll(); if p.kitTabs.dd then p.kitTabs.dd:Hide() end
  p.nextCard, p.bar, p.barLabel = nil, nil, nil
  local st = { cells = {}, pairRows = {}, extras = {} }
  p.starter = st
  -- the heading and the intro
  local title = Skin.Heading(fixed, 17, T.heading)
  local gt = Kit.Color("gold.title")
  title:SetTextColor(gt[1], gt[2], gt[3], 1)
  if title.SetWordWrap then title:SetWordWrap(false) end
  title:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y)
  title:SetWidth(DW); Skin.Ellipsize(title, T.heading, DW)
  local th = max(22, ceil(TH(title, DW))); title:SetHeight(th)
  p.title = title
  y = y - th - SP.xs
  local intro = Skin.Ink(fixed, 12, Kit.Color("text.muted"))
  intro:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y); intro:SetWidth(DW); intro:SetText(T.intro)
  local ih = ceil(TH(intro, DW)); intro:SetHeight(ih)
  st.intro = intro
  y = y - ih - SP.m
  -- the pick: where to learn it
  local pick, tr = v.pick, v.trainer or {}
  local card = Kit.Surface(fixed, 1)
  card:SetPoint("TOPLEFT", fixed, "TOPLEFT", X, y)
  card:SetAccent(accentOf(pick))
  local icon = card:CreateTexture(nil, "ARTWORK")
  icon:SetSize(28, 28); icon:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
  icon:SetTexture(PUI.IconFor(pick))
  if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  local go = Skin.Button(card, T.go, 110, 24, function() PUI:StarterGo(pick) end, T.go, T.goTip)
  local find = Skin.Button(card, T.find, 110, 24, function() PUI:StarterFind(pick) end, T.find, T.findTip)
  Skin.FitButton(go, 96, 170); Skin.FitButton(find, 96, 170)
  go:SetEnabledLook(tr.spot ~= nil)
  local tx = 12 + 28 + SP.s
  local bw = go:GetWidth() + SP.s + find:GetWidth()
  local side = DW - tx - 12 - bw - SP.m >= 200   -- the buttons beside the words, else under them
  local tw = side and (DW - tx - 12 - bw - SP.m) or (DW - tx - 12)
  local name = Skin.Text(card, 14, Kit.Color("text.primary"), nil, "semi")
  name:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -10); name:SetWidth(tw); name:SetText(T.picked:format(pick))
  local nh = ceil(TH(name, tw)); name:SetHeight(nh)
  local where = Skin.Ink(card, 11, Kit.Color("text.muted"))
  where:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -10 - nh - SP.xs); where:SetWidth(tw); where:SetText(tr.text or "")
  local wh = ceil(TH(where, tw)); where:SetHeight(wh)
  local textBottom = 10 + nh + SP.xs + wh
  local ch
  if side then
    go:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12 - find:GetWidth() - SP.s, -10)
    find:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -10)
    ch = max(textBottom, 10 + 28, 10 + 24) + 10
  else
    local by = -(max(textBottom, 38) + SP.s)
    go:SetPoint("TOPLEFT", card, "TOPLEFT", tx, by)
    if tx + bw <= DW - 12 then find:SetPoint("TOPLEFT", card, "TOPLEFT", tx + go:GetWidth() + SP.s, by)
    else by = by - 24 - SP.xs find:SetPoint("TOPLEFT", card, "TOPLEFT", tx, by) end
    ch = -by + 24 + 10
  end
  card:SetSize(DW, ch)
  card.icon, card.name, card.where, card.go, card.find = icon, name, where, go, find
  card.panoplyPick, card.panoplyWhere = pick, tr.where
  st.card = card
  y = y - ch - SP.m
  -- the rest scrolls
  local area = p.tabArea
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", X, y)
  area:SetSize(DW, max(1, H + y - Page.GRIP))
  area:Show()
  local content = CreateFrame("Frame", nil, area.content)
  content:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
  content.panoplyGapOK = true
  p.content = content
  local cw = DW - 14
  local cy = -2
  local function label(text)
    local lab = Skin.Label(content, 10); lab:SetText(text)
    lab:SetPoint("TOPLEFT", content, "TOPLEFT", 4, cy); lab:SetWidth(cw - 4)
    local lh = ceil(TH(lab, cw - 4)); lab:SetHeight(lh)
    cy = cy - lh - SP.s
    return lab
  end
  -- the class's pairs, best first
  st.suggestedLabel = label(T.suggested:format(tostring(v.class or ""):upper()))
  for _, pr in ipairs(v.pairs or {}) do
    local b = CreateFrame("Button", nil, content)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cy)
    local hl = b:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(b); Skin.Solid(hl, Kit.Color("surface.2"), 1); hl:Hide()
    local a = Skin.Text(b, 12, Kit.Color("text.primary"), nil, "semi")
    a:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -3); a:SetWidth(cw - 8); a:SetText(pr.a .. " + " .. pr.b)
    local ah = ceil(TH(a, cw - 8)); a:SetHeight(ah)
    local why = Skin.Ink(b, 11, Kit.Color("text.muted"))
    why:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -3 - ah - 1); why:SetWidth(cw - 8); why:SetText(pr.why or "")
    local wh2 = ceil(TH(why, cw - 8)); why:SetHeight(wh2)
    local rh = 3 + ah + 1 + wh2 + 4
    b:SetSize(cw, rh)
    Skin.Tooltip(b, pr.a .. " + " .. pr.b, pr.why)
    b:SetScript("OnEnter", function(self) hl:Show() if self.panoplyShowTip then self.panoplyShowTip() end end)
    b:SetScript("OnLeave", function() hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() PUI:StarterSelect(pr.a) end)
    b.title, b.why, b.panoplyPair = a, why, pr
    st.pairRows[#st.pairRows + 1] = b
    cy = cy - rh - SP.xs
  end
  cy = cy - SP.s
  -- a grid of profession cells
  local cols = (cw >= 600 and 3) or (cw >= 380 and 2) or 1
  local cellW = floor((cw - (cols - 1) * SP.s) / cols)
  local function grid(list)
    local i = 0
    while i < #list do
      local rowCells, rowH = {}, 0
      for c = 1, cols do
        local it = list[i + c]
        if it then
          local sel = it.name == pick
          local cell = Kit.Surface(content, sel and 2 or 1)
          cell:SetPoint("TOPLEFT", content, "TOPLEFT", (c - 1) * (cellW + SP.s), cy)
          if it.suggested then cell:SetAccent(accentOf(it.name)) end
          local ic = cell:CreateTexture(nil, "ARTWORK")
          ic:SetSize(28, 28); ic:SetPoint("TOPLEFT", cell, "TOPLEFT", 10, -8)
          ic:SetTexture(PUI.IconFor(it.name))
          if ic.SetTexCoord then ic:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
          local itx = 10 + 28 + SP.s
          local iw = cellW - itx - 8
          local nm = Skin.Text(cell, 13, Kit.Color("text.primary"), nil, "semi")
          nm:SetPoint("TOPLEFT", cell, "TOPLEFT", itx, -8); nm:SetWidth(iw); nm:SetText(it.name)
          local nmh = ceil(TH(nm, iw)); nm:SetHeight(nmh)
          local ln = Skin.Ink(cell, 11, Kit.Color("text.muted"))
          ln:SetPoint("TOPLEFT", cell, "TOPLEFT", itx, -8 - nmh - 1); ln:SetWidth(iw); ln:SetText(it.line or "")
          local lnh = ceil(TH(ln, iw)); ln:SetHeight(lnh)
          local h = max(44, 8 + nmh + 1 + lnh + 8)
          local hit = CreateFrame("Button", nil, cell)
          hit:SetAllPoints(cell)
          hit.panoplyLayoutSkip = true
          Skin.Tooltip(hit, it.name, (it.line or "") .. (it.suggested and ("\n" .. T.suggestedTip) or ""))
          hit:SetScript("OnEnter", function(self) if not sel then cell:SetLevel(2) end if self.panoplyShowTip then self.panoplyShowTip() end end)
          hit:SetScript("OnLeave", function() if not sel then cell:SetLevel(1) end if _G.GameTooltip then GameTooltip:Hide() end end)
          hit:SetScript("OnClick", function() PUI:StarterSelect(it.name) end)
          cell.icon, cell.name, cell.line, cell.hit = ic, nm, ln, hit
          cell.panoplyProf, cell.panoplySuggested, cell.panoplyPicked, cell.panoplyExtra = it.name, it.suggested and true or false, sel, it.extra and true or false
          st.cells[it.name] = cell
          if it.extra then st.extras[#st.extras + 1] = cell end
          rowCells[#rowCells + 1] = cell
          rowH = max(rowH, h)
        end
      end
      for _, cell in ipairs(rowCells) do cell:SetSize(cellW, rowH) end
      cy = cy - rowH - SP.s
      i = i + cols
    end
  end
  st.mainLabel = label(T.main)
  grid(v.main or {})
  cy = cy - SP.xs
  st.extrasLabel = label(T.extras)
  grid(v.extras or {})
  st.cols = cols
  content:SetSize(cw, max(1, -cy))
  area:SetContentHeight(-cy + SP.s)
  if PUI.pendingScroll or Page.pendingTop then
    local s = Page.pendingTop and 0 or PUI.pendingScroll
    PUI.pendingScroll, Page.pendingTop = nil, nil
    if area.SetVerticalScroll then area:SetVerticalScroll(max(0, min(area:MaxScroll(), s or 0))) end
    area:UpdateBar()
  end
end

-- 0.9.6 phase K: the crafting view of the open profession (the header's button opened it here). Pinned: the search row (the search,
-- All / Can make, Game window). Under it, Wide and Medium: the recipe list beside the selected recipe; Narrow: the list above it. The
-- recipe's name, its count and its materials (have / need) scroll on their own; the quantity, Make and Make All stay under them.
function Page:DrawCraft(p, fixed, v, X, y, DW, H)
  local CC = PUI.CRAFT_COPY
  local tabs = p.kitTabs
  tabs:HideAll(); if tabs.dd then tabs.dd:Hide() end
  p.tabArea:Hide(); p.filterDD:Hide()
  p.nextCard = nil
  -- the search row
  local gw = Skin.FitButton(p.craftGame, 90, 150)
  p.craftDD:Fit(110, 150)
  local ddw = p.craftDD:GetWidth()
  local oneRow = DW >= 140 + SP.s + ddw + SP.s + gw
  local sw = oneRow and min(240, DW - ddw - gw - 2 * SP.s) or max(100, DW - ddw - SP.s)
  p.search:SetSize(max(100, sw), 24)
  p.search:ClearAllPoints(); p.search:SetPoint("TOPLEFT", p, "TOPLEFT", X, y)
  if (p.search:GetText() or "") ~= (PUI.craftQuery or "") then p.search:SetText(PUI.craftQuery or "") end
  p.search:Show()
  p.craftDD:ClearAllPoints(); p.craftDD:SetPoint("TOPLEFT", p, "TOPLEFT", X + p.search:GetWidth() + SP.s, y)
  p.craftDD:Show()
  if oneRow then
    p.craftGame:ClearAllPoints(); p.craftGame:SetPoint("TOPLEFT", p, "TOPLEFT", X + DW - gw, y)
    y = y - 24 - SP.s
  else
    y = y - 24 - SP.xs
    p.craftGame:ClearAllPoints(); p.craftGame:SetPoint("TOPLEFT", p, "TOPLEFT", X, y)
    y = y - 24 - SP.s
  end
  p.craftGame:Show()
  -- the room under it
  local ah = max(80, H + y - Page.GRIP)
  local makeH = 24
  local two = DW >= 520
  local listW, listH, infoX, infoY, infoW, infoH
  if two then
    listW = floor((DW - SP.m) * 0.5); listH = ah
    infoX, infoY, infoW = X + listW + SP.m, y, DW - listW - SP.m
    infoH = max(30, ah - makeH - SP.s)
  else
    listW = DW
    listH = max(50, floor((ah - makeH - SP.s - SP.m) * 0.5))
    infoX, infoY, infoW = X, y - listH - SP.m, DW
    infoH = max(30, ah - listH - SP.m - makeH - SP.s)
  end
  local makeY = infoY - infoH - SP.s
  p.panoplyCraftLayout = two and "beside" or "above"
  -- the recipe list
  local area = p.craftArea
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", X, y); area:SetSize(listW, listH)
  area:Show()
  local content = CreateFrame("Frame", nil, area.content)
  content:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
  content.panoplyGapOK = true
  p.craftContent = content
  local cw = listW - 14
  local cy = -2
  local rows = PUI.craftRowsList or {}
  p.craftRows = {}
  local lastCat
  local DIFF = (Panoply.ProfWindow and Panoply.ProfWindow.DIFF_COLOR) or {}
  for _, r in ipairs(rows) do
    if r.category and r.category ~= lastCat then
      lastCat = r.category
      local lab = Skin.Label(content, 10); lab:SetText(tostring(r.category):upper())
      lab:SetPoint("TOPLEFT", content, "TOPLEFT", 4, cy - SP.xs); lab:SetWidth(cw - 4)
      local lh = ceil(TH(lab, cw - 4)); lab:SetHeight(lh)
      cy = cy - SP.xs - lh - SP.xs
    end
    local b = CreateFrame("Button", nil, content)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cy)
    local hl = b:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(b); Skin.Solid(hl, Kit.Color("surface.2"), 1)
    local sel = r.name == PUI.craftSel
    if not sel then hl:Hide() end
    local cnt = Skin.Ink(b, 11, Kit.Color("text.muted"))
    if cnt.SetWordWrap then cnt:SetWordWrap(false) end
    local n = tonumber(r.numAvailable) or 0
    cnt:SetText(n > 0 and ("[%d]"):format(n) or "")
    local rw = n > 0 and (ceil(TW(cnt)) + 2) or 0
    cnt:SetWidth(rw); cnt:SetHeight(ceil(TH(cnt, max(rw, 1))))
    local fs = Skin.Ink(b, 12)
    local c = DIFF[r.difficulty]
    if c then fs:SetTextColor(c[1], c[2], c[3], 1) else tint(fs, "text.primary") end
    local fw = cw - 8 - rw - (rw > 0 and SP.s or 0)
    fs:SetWidth(fw); fs:SetText(r.name or "")
    local fh = ceil(TH(fs, fw)); fs:SetHeight(fh)
    fs:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -2)
    cnt:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -2)
    local rh = max(18, fh + 4)
    b:SetSize(cw, rh)
    Skin.Tooltip(b, r.name or "", CC.canMake:format(n))
    b:SetScript("OnEnter", function(self) hl:Show() if self.panoplyShowTip then self.panoplyShowTip() end end)
    b:SetScript("OnLeave", function() if not sel then hl:Hide() end if _G.GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() PUI:CraftSelect(r.name) end)
    b.text, b.count, b.panoplyRecipe, b.panoplySelected = fs, cnt, r.name, sel
    p.craftRows[#p.craftRows + 1] = b
    cy = cy - rh
  end
  if #rows == 0 then
    local none = Skin.Ink(content, 12, Kit.Color("text.muted")); none:SetText(CC.none)
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 4, cy); none:SetWidth(cw - 4)
    local nh = ceil(TH(none, cw - 4)); none:SetHeight(nh)
    cy = cy - nh
    p.craftNone = none
  end
  content:SetSize(cw, max(1, -cy))
  area:SetContentHeight(-cy + SP.s)
  -- the selected recipe
  local info = p.craftInfo
  info:ClearAllPoints(); info:SetPoint("TOPLEFT", p, "TOPLEFT", infoX, infoY); info:SetSize(infoW, infoH)
  info:Show()
  local ic = CreateFrame("Frame", nil, info.content)
  ic:SetPoint("TOPLEFT", info.content, "TOPLEFT", 0, 0)
  ic.panoplyGapOK = true
  p.craftInfoContent = ic
  local iw = infoW - 14
  local iy = -2
  local r = PUI:CraftSelected()
  p.craftReagents = {}
  if not r then
    local t = Skin.Ink(ic, 12, Kit.Color("text.muted")); t:SetText(two and CC.pick or CC.pickNarrow)
    t:SetPoint("TOPLEFT", ic, "TOPLEFT", 4, iy); t:SetWidth(iw - 4)
    local h = ceil(TH(t, iw - 4)); t:SetHeight(h)
    iy = iy - h
  else
    local tex = ic:CreateTexture(nil, "ARTWORK")
    tex:SetSize(24, 24); tex:SetPoint("TOPLEFT", ic, "TOPLEFT", 4, iy)
    -- (0.9.7 hotfix: WoW Forever's recipe list can come without a picture; the made item's own is used then, and painted again
    -- when the game sends the item)
    if r.itemID and not r.craft then
      Panoply.Icons:Apply(tex, r.itemID, r.icon, PUI.IconFor(PUI.selected))
    else tex:SetTexture(r.icon or PUI.IconFor(PUI.selected)) end
    local nx = 4 + 24 + SP.s
    local nm = Skin.Text(ic, 14, Kit.Color("text.primary"), nil, "semi")
    nm:SetPoint("TOPLEFT", ic, "TOPLEFT", nx, iy); nm:SetWidth(iw - nx); nm:SetText(r.name or "")
    local nmh = ceil(TH(nm, iw - nx)); nm:SetHeight(nmh)
    iy = iy - max(24, nmh) - SP.xs
    local cnt = Skin.Ink(ic, 11, Kit.Color("text.muted")); cnt:SetText(CC.canMake:format(tonumber(r.numAvailable) or 0))
    cnt:SetPoint("TOPLEFT", ic, "TOPLEFT", 4, iy); cnt:SetWidth(iw - 4)
    local ch = ceil(TH(cnt, iw - 4)); cnt:SetHeight(ch)
    iy = iy - ch - SP.m
    local lab = Skin.Label(ic, 10); lab:SetText(CC.reagents)
    lab:SetPoint("TOPLEFT", ic, "TOPLEFT", 4, iy); lab:SetWidth(iw - 4)
    local lh = ceil(TH(lab, iw - 4)); lab:SetHeight(lh)
    iy = iy - lh - SP.xs
    for _, rg in ipairs(r.reagents or {}) do
      local have, need = tonumber(rg.bags) or 0, tonumber(rg.need) or 1
      local rt = ic:CreateTexture(nil, "ARTWORK"); rt:SetSize(16, 16); rt:SetPoint("TOPLEFT", ic, "TOPLEFT", 4, iy)
      -- (0.9.7 hotfix: WoW Forever lists a material by item id only, with no picture: it had none here at all)
      if rg.itemID then Panoply.Icons:Apply(rt, rg.itemID, rg.icon) elseif rg.icon then rt:SetTexture(rg.icon) end
      local right = Skin.Ink(ic, 12, Kit.Color(have >= need and "text.primary" or "state.bad"))
      if right.SetWordWrap then right:SetWordWrap(false) end
      if right.SetJustifyH then right:SetJustifyH("RIGHT") end
      right:SetText(("%d / %d"):format(have, need))
      local rw = ceil(TW(right)) + 2
      right:SetWidth(rw); right:SetHeight(ceil(TH(right, rw)))
      right:SetPoint("TOPRIGHT", ic, "TOPLEFT", iw, iy)
      local nw = iw - 24 - rw - SP.s
      local rn = Skin.Ink(ic, 12, Kit.Color("text.primary")); rn:SetText(rg.name or ("Item " .. tostring(rg.itemID or "?")))
      rn:SetPoint("TOPLEFT", ic, "TOPLEFT", 24, iy); rn:SetWidth(nw)
      local rnh = ceil(TH(rn, nw)); rn:SetHeight(rnh)
      p.craftReagents[#p.craftReagents + 1] = { name = rn, count = right, have = have, need = need }
      iy = iy - max(18, rnh + 2)
    end
  end
  ic:SetSize(iw, max(1, -iy))
  info:SetContentHeight(-iy + SP.s)
  -- the quantity, Make and Make All
  local q = p.craftQty
  q:ClearAllPoints(); q:SetPoint("TOPLEFT", p, "TOPLEFT", infoX, makeY); q:Show()
  if not (q.input.HasFocus and q.input:HasFocus()) then q.input:SetText(tostring(PUI:CraftQtyN())) end
  Skin.FitButton(p.craftMake, 64, 120); Skin.FitButton(p.craftMakeAll, 76, 130)
  p.craftMake:ClearAllPoints(); p.craftMake:SetPoint("TOPLEFT", p, "TOPLEFT", infoX + q:GetWidth() + SP.s, makeY)
  p.craftMakeAll:ClearAllPoints(); p.craftMakeAll:SetPoint("TOPLEFT", p, "TOPLEFT", infoX + q:GetWidth() + SP.s + p.craftMake:GetWidth() + SP.s, makeY)
  local short = not r or (Panoply.ProfWindow and Panoply.ProfWindow.Short and Panoply.ProfWindow.Short(r))
  p.craftMake:SetEnabledLook(not short); p.craftMakeAll:SetEnabledLook(not short)
  p.craftMake:Show(); p.craftMakeAll:Show()
end

-- the Next card's insides: the title, one line, the marks (train), the chip, and the card's buttons at the right
function Page:DrawNext(p, card, n, v, DW, nh, compact)
  local sel = PUI.selected
  local btns = {}
  -- buttons by kind
  if n.kind == "craft" or n.kind == "gather" or n.kind == "train" or n.kind == "learn" then
    local go = Skin.Button(card, "Guide me", 100, 24, function() PUI:GuideMe(sel) end, "Guide me now",
      "Shows this step in the guide window and points the arrow, even if you are not nearby.")
    btns[#btns + 1] = go
    card.go = go
    if not compact then
      local later = Skin.Button(card, "Later", 100, 22, function() if n.step then Panoply.ProfGuide:Snooze(n.step) Panoply.Menu:RefreshCurrent() end end,
        "Later", "Hide this profession step for 15 minutes.")
      btns[#btns + 1] = later
      card.later = later
    end
  end
  local bw = 0
  for _, b in ipairs(btns) do bw = max(bw, Skin.FitButton(b, 84, 130)) end
  for _, b in ipairs(btns) do b:SetWidth(bw) end
  local mapB
  if (n.spot and n.spot.map) or n.instance then
    mapB = mapButton(card, n.instance and ("Show " .. n.instance .. " on the map") or "Show on the map")
    mapB.spot, mapB.instance = n.spot, n.instance
    card.map = mapB
  end
  local right = (bw > 0 and (bw + SP.m) or 0) + (mapB and (20 + SP.s) or 0) + 10
  -- the chip
  local chip
  if v.status and CHIP_KIND[v.status] then chip = Kit.StatusChip(card, CHIP_KIND[v.status]) card.chip = chip end
  local tx = 14
  local tw = DW - tx - right
  local head = Skin.Label(card, 10)
  head:SetText("NEXT")
  head:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -8)
  head:SetWidth(40); head:SetHeight(ceil(TH(head, 40)))
  if chip then chip:SetPoint("LEFT", head, "LEFT", ceil(TW(head)) + SP.s, 0) end
  local cy = compact and -8 or (-8 - ceil(TH(head, 40)) - SP.xs)
  if compact then
    -- two lines: the action and its blocker, beside the label
    head:Hide(); if chip then chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -8) end
    local hx = tx + (chip and (chip:GetWidth() + SP.s) or 0)
    local t1 = Skin.Text(card, 13, Kit.Color("text.primary"), nil, "semi")
    if t1.SetWordWrap then t1:SetWordWrap(false) end
    t1:SetPoint("TOPLEFT", card, "TOPLEFT", hx, -8); t1:SetWidth(DW - hx - right)
    Skin.Ellipsize(t1, n.title or "", DW - hx - right); t1:SetHeight(ceil(TH(t1, DW - hx - right)))
    local h1 = max(ceil(TH(t1, DW - hx - right)), chip and ceil(chip:GetHeight()) or 0)
    local t2 = Skin.Ink(card, 11, Kit.Color("text.muted"))
    if t2.SetWordWrap then t2:SetWordWrap(false) end
    t2:SetPoint("TOPLEFT", card, "TOPLEFT", tx, -8 - h1 - SP.xs); t2:SetWidth(DW - tx - right)
    Skin.Ellipsize(t2, n.blocker or n.line or "", DW - tx - right)
    local h2 = ceil(TH(t2, DW - tx - right)); t2:SetHeight(h2)
    card.title, card.line = t1, t2
    card.panoplyLines = 2
    -- the two lines' own height, so 1.3x text still fits (the card is then a fixed height for this drawing)
    local need = 8 + h1 + SP.xs + h2 + 8
    if need > nh then card:SetHeight(need) card.panoplyGrew = need - nh end
  else
    -- the action: up to two lines; longer, one line cut short (the card's tooltip holds all of it)
    local t1 = Skin.Text(card, 14, Kit.Color("text.primary"), nil, "semi")
    t1:SetPoint("TOPLEFT", card, "TOPLEFT", tx, cy); t1:SetWidth(tw)
    t1:SetText(n.title or "")
    local one = ceil(TH(t1, 100000))
    local h1 = ceil(TH(t1, tw))
    local roomTwo = (#(n.facts or {}) == 0) and (nh - 8 - ceil(TH(head, 40)) - SP.xs - 2 * one - SP.xs - 14 - 6 >= 0)
    if h1 > one + 1 and not (roomTwo and h1 <= 2 * one + 1) then
      if t1.SetWordWrap then t1:SetWordWrap(false) end
      Skin.Ellipsize(t1, n.title or "", tw)
      h1 = ceil(TH(t1, tw))
    end
    t1:SetHeight(h1)
    cy = cy - h1 - SP.xs
    -- the marks (train): Skill 125 [ok], Level 20 [not yet]
    local fx = tx
    local facts = {}
    for _, f in ipairs(n.facts or {}) do
      if f then
        local m = card:CreateTexture(nil, "OVERLAY"); m:SetSize(12, 12)
        Skin.SetMark(m, f.ok and "Ready" or "Waiting")
        m:SetVertexColor(1, 1, 1, f.ok and 1 or 0.7)
        m:SetPoint("TOPLEFT", card, "TOPLEFT", fx, cy - 1)
        local ft = Skin.Ink(card, 11, Kit.Color(f.ok and "text.primary" or "state.bad"))
        if ft.SetWordWrap then ft:SetWordWrap(false) end
        ft:SetText(f.text or "")
        local w = ceil(TW(ft)) + 2
        ft:SetPoint("TOPLEFT", card, "TOPLEFT", fx + 15, cy); ft:SetWidth(w); ft:SetHeight(ceil(TH(ft, w)))
        facts[#facts + 1] = { mark = m, text = ft, ok = f.ok }
        fx = fx + 15 + w + SP.m
      end
    end
    card.facts = facts
    local fh = 0
    for _, f in ipairs(facts) do fh = max(fh, f.text:GetHeight() or 0, 12) end
    if #facts > 0 then cy = cy - fh - SP.xs end
    local t2 = Skin.Ink(card, 11, Kit.Color("text.muted"))
    if t2.SetWordWrap then t2:SetWordWrap(false) end
    t2:SetPoint("TOPLEFT", card, "TOPLEFT", tx, cy); t2:SetWidth(tw)
    Skin.Ellipsize(t2, n.line or "", tw)
    local h2 = ceil(TH(t2, tw)); t2:SetHeight(h2)
    cy = cy - h2 - SP.xs
    -- a blocker under the action (a rank that needs a level, while you craft on)
    local t3
    if n.blocker and n.blocker ~= n.line and (n.kind == "craft" or n.kind == "gather" or n.kind == "none") and -cy + 14 <= nh - 6 then
      t3 = Skin.Ink(card, 11, Kit.Color("text.muted"))
      if t3.SetWordWrap then t3:SetWordWrap(false) end
      t3:SetPoint("TOPLEFT", card, "TOPLEFT", tx, cy); t3:SetWidth(tw)
      Skin.Ellipsize(t3, n.blocker, tw); t3:SetHeight(ceil(TH(t3, tw)))
    end
    card.title, card.line, card.blockerLine = t1, t2, t3
    card.panoplyLines = 2 + (#facts > 0 and 1 or 0) + (t3 and 1 or 0)
    -- larger text (1.3x) needs more room than the standard height: the card grows to hold its lines (still one height for this drawing)
    local need = -cy + (t3 and ceil(t3:GetHeight() or 0) or 0) + 8
    if need > nh then card:SetHeight(need) card.panoplyGrew = need - nh end
  end
  -- the buttons, stacked at the right; the map button beside them
  local by = -8
  for i, b in ipairs(btns) do
    b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10 - (mapB and (20 + SP.s) or 0), by)
    if compact and i > 1 then b:Hide() end
    by = by - b:GetHeight() - SP.xs
  end
  if mapB then mapB:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10) end
  -- the whole action and its line in the card's tooltip (an invisible area under the buttons)
  local tipArea = CreateFrame("Frame", nil, card)
  tipArea:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0); tipArea:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -right, 0)
  tipArea.panoplyLayoutSkip = true
  if tipArea.EnableMouse then tipArea:EnableMouse(true) end
  Skin.Tooltip(tipArea, n.title or "", ((n.line or "") .. ((n.blocker and n.blocker ~= n.line) and ("\n" .. n.blocker) or "")
    .. (n.perkNote and ("\n" .. n.perkNote) or "")))
  card.perkNote = n.perkNote
  tipArea:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  tipArea:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  card.tipArea, card.panoplyFullTitle = tipArea, n.title
  -- the guide's own step (a train or learn card has one when the guide shows a trainer visit)
  local gstep = n.step or v.nextStep
  if card.go then card.go:SetEnabledLook(gstep ~= nil) end
  if card.later then card.later:SetEnabledLook(n.step ~= nil) end
end

-- the Legacy page, from a Legacy mark on the skill bar (WoW Forever): the Challenges tab; the Tradeskills row is named for the page
function PUI:OpenLegacy(name, at)
  local L = Panoply.Legacy
  if not (L and L.Open) then return false end
  L.focus = { section = "tradeskills", profession = name, skill = at }
  return L:Open("challenges")
end

-- open the page on a profession (Muster, the guide, the trainer and alerts link here)
-- Opening the page is one step of the window's history with the profession in it. In a fight (the page holds secure buttons) the pick
-- waits like a click in the list (PUI:Select), so what is on screen and what the page says it shows never differ.
function PUI:Show(name)
  local ok = name and self:Selectable(name) and self.selected ~= name
  if ok and not (inCombat() and Kit.PageHolds and Kit.PageHolds("professions")) then
    self.selected, self.pendingScroll, ok = name, 0, false
  end
  Panoply.Menu:Open("professions")
  if ok then self:Select(name) end
end
function PUI:Toggle()
  if Panoply.Menu.frame and Panoply.Menu.frame:IsShown() and Panoply.Menu.current == "professions" then Panoply.Menu:Hide() return end
  Panoply.Menu:Open("professions")
end

-- a page first drawn in a fight has no secure buttons on its trainer rows, and a change in a fight waits: drawn again when it ends
Panoply:On("PLAYER_REGEN_ENABLED", function()
  if (PUI.secureMissing or PUI.pendingDraw) and Panoply.Menu and Panoply.Menu.current == "professions" and Panoply.Menu.frame and Panoply.Menu.frame:IsShown() then
    Panoply.Menu:RefreshCurrent()
  end
end)
