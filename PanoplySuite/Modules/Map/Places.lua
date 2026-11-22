-- Map module, PLACES: trainers, services, vendors and crafting stations on the zone maps and on the minimap. Each kind of place is its own
-- switch (Map.lua M.PLACE_TYPES: the Places menu on the map toolbar and the Map page write the same setting), and its size, opacity and
-- colour are the Look of the map's "Places" (a World map and a Minimap column, like the other custom icons).
--
-- Where the places come from: PanoplySuite_QuestData's own NPC table (the VMaNGOS world database). An NPC's title (its "subName",
-- for instance "Priest Trainer" or "Innkeeper") and its service flags decide which kinds it is; its spots come from QuestData:NpcSpots like
-- every other NPC spot in Panoply Suite. NOTHING here is a coordinate somebody typed in. A kind with no records stays empty:
--   * Mailboxes, anvils, forges and camp sites (cooking fires) are game OBJECTS, and guild masters and rare creatures are not in the NPC
--     table's service flags: since 0.8.4 they come from PanoplySuite_QuestData/Maps/Extras.lua (the same world database, tools/
--     build_mapextras.py) through Extras.lua (X:AddPlaces). Without that data file the kinds stay empty, as before.
--   * Class trainers: your own class's, or every class's ("Show all classes"). The class names come from the game's own class list, so a
--     class Forever adds is found by its name with no change here.
-- Information only (hub rule 2 of CLAUDE.md): a click on a world map pin points the arrow at it (a waypoint). Nothing is targeted, cast, used
-- or walked for the player; there is no movement or automation code in this file.
local ADDON, Panoply = ...
local C, Skin, M = Panoply.Compat, Panoply.Skin, Panoply.Map
local Look = Panoply.Look
local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local P = {}
M.Places = P
P.WM_PX = 18            -- a world map pin at "Size 100%", in screen pixels
P.MM_PX = 12            -- a minimap pin at "Size 100%"
P.MM_CAP = 14           -- at most this many pins on the minimap (the closest)
P.MM_TICK = 0.5         -- seconds between minimap updates
P.shown, P.mmShown = 0, 0

-- Creature npc_flags of the 1.12 server (tools/vmangos_world.py keeps the same list for the data builder)
P.FLAG = { VENDOR = 4, FLIGHT = 8, TRAINER = 16, INNKEEPER = 128, BANKER = 256, AUCTION = 4096, STABLE = 8192, REPAIR = 16384 }
local function has(flags, bit) return flags % (bit * 2) >= bit end

-- not a switch of its own: the flight masters are kept so the Go to window can find them
P.INTERNAL = { flight = true }
-- kinds that live in game objects: their spots come from the map extras data (see the top of this file), and they have no name of their
-- own, so the Go to window lists the nearest one and not each of them
P.OBJECT_KINDS = { placeMail = true, placeAnvil = true, placeForge = true, placeCamp = true }

-------------------------------------------------------------------------------
-- Which kind of place an NPC is
-------------------------------------------------------------------------------
P.CLASS_WORDS = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }

-- every class name the game knows, in lower case (Era's nine, and any class the client lists on its own: WoW Forever's new ones)
function P.ClassWords()
  if P.classWords then return P.classWords end
  local words, seen = {}, {}
  local function add(n)
    if type(n) == "string" and n ~= "" then
      n = n:lower()
      if not seen[n] then seen[n] = true words[#words + 1] = n end
    end
  end
  for _, w in ipairs(P.CLASS_WORDS) do add(w) end
  local count, info = C.G("GetNumClasses"), C.G("GetClassInfo")
  local n = count and M.pc(count)
  if type(n) == "number" and info then
    for i = 1, min(n, 40) do add((M.pc(info, i))) end
  end
  P.classWords = words
  return words
end

local function classWordIn(s)
  for _, w in ipairs(P.ClassWords()) do if s:find(w, 1, true) then return w end end
  return nil
end

-- title + flags -> a list of { key, classWord }. Pure: nothing is read from the game, so the tests can feed it any title.
function P.Classify(sub, flags)
  local s = tostring(sub or ""):lower()
  flags = tonumber(flags) or 0
  local F, out = P.FLAG, {}
  local function add(key, cw) out[#out + 1] = { key = key, classWord = cw } end
  if s:find("demon trainer", 1, true) then
    add("placeTrainDemon")            -- the data gives the demon trainers no trainer flag: they teach through their gossip, so their title decides
  elseif has(flags, F.TRAINER) then
    if s:find("pet trainer", 1, true) then add("placeTrainPet")
    elseif s:find("portal trainer", 1, true) then add("placeTrainPortal")
    elseif s:find("weapon master", 1, true) then add("placeTrainWeapon")
    elseif s:find("riding", 1, true) or s:find("mechanostrider pilot", 1, true) then add("placeTrainRiding")
    else
      local cw = classWordIn(s)
      if cw then add("placeTrainClass", cw) else add("placeTrainProf") end   -- what is left of the trainers is a profession (Forever's extras too)
    end
  end
  if has(flags, F.INNKEEPER) then add("placeInn") end
  if has(flags, F.BANKER) then add("placeBank") end
  if has(flags, F.AUCTION) then add("placeAuction") end
  if has(flags, F.STABLE) then add("placeStable") end
  if has(flags, F.REPAIR) then add("placeRepair") end
  if s:find("guild master", 1, true) then add("placeGuild") end
  if has(flags, F.VENDOR) then
    if s:find("trade goods", 1, true) or s:find("trade supplies", 1, true) then add("placeVTrade")
    elseif s:find("reagent", 1, true) then add("placeVReagent")
    elseif s:find("ammunition", 1, true) or s:find("bowyer", 1, true) or s:find("gunsmith", 1, true) then add("placeVAmmo")
    elseif s:find("poison", 1, true) then add("placeVPoison")
    elseif s:find("food", 1, true) or s:find("baker", 1, true) or s:find("butcher", 1, true) or s:find("bartender", 1, true) then add("placeVFood")
    elseif s:find("supplies", 1, true) and not s:find("general", 1, true) then add("placeVProf") end
  end
  if has(flags, F.FLIGHT) then add("flight") end
  return out
end

-------------------------------------------------------------------------------
-- The index: every place of every kind, by kind and by map (built once, from the NPC table)
-------------------------------------------------------------------------------
-- { byType = { key = { entry ... } }, byMap = { uiMap = { entry ... } }, count = n }; an entry is
-- { type, id, name, sub, map, x, y, classWord, unverified } (an object kind's entry has station = true and no id)
function P.Index()
  local QD = Panoply.QuestData
  local own = QD and QD.own
  if P.index and P.indexOwn == own then return P.index end
  local idx = { byType = {}, byMap = {}, count = 0, otherSide = {} }
  P.index, P.indexOwn = idx, own
  if not (own and type(own.NpcIds) == "function" and type(own.Npc) == "function") then return idx end
  local ok, ids = pcall(own.NpcIds)
  if not (ok and type(ids) == "table") then return idx end
  for _, id in ipairs(ids) do
    if type(id) == "number" then
      local okr, rec = pcall(own.Npc, id)
      if okr and type(rec) == "table" then
        local kinds = P.Classify(rec.subName, rec.npcFlags)
        -- 0.9.6: a service NPC of the other side is remembered, so the Go to search does not offer it as a plain creature (Find.lua)
        if #kinds > 0 and QD:NpcFriendly(id) == false then idx.otherSide[id] = true end
        if #kinds > 0 and QD:NpcFriendly(id) ~= false then
          local okS, spots = pcall(QD.NpcSpots, QD, id)
          for _, s in ipairs(okS and type(spots) == "table" and spots or {}) do
            if s.map and s.x and s.y then
              for _, k in ipairs(kinds) do
                local e = { type = k.key, id = id, name = rec.name or ("NPC " .. id), sub = rec.subName, map = s.map, x = s.x, y = s.y,
                  classWord = k.classWord, unverified = s.unverified }
                local t = idx.byType[k.key] or {}
                idx.byType[k.key] = t
                t[#t + 1] = e
                local m = idx.byMap[s.map] or {}
                idx.byMap[s.map] = m
                m[#m + 1] = e
                idx.count = idx.count + 1
              end
            end
          end
        end
      end
    end
  end
  -- 0.8.4 map extras: mailboxes, anvils, forges, camp sites, guild masters and rare creatures (Extras.lua; nothing without its data file)
  local X = M.Extras
  if X and X.AddPlaces then
    X:AddPlaces(function(e)
      local t = idx.byType[e.type] or {}
      idx.byType[e.type] = t
      t[#t + 1] = e
      local m = idx.byMap[e.map] or {}
      idx.byMap[e.map] = m
      m[#m + 1] = e
      idx.count = idx.count + 1
    end)
  end
  return idx
end

-- the player's class name as the game spells it (lower case), and its file name
function P.MyClass()
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  local n = type(info.class) == "string" and info.class:lower() or nil
  local f = type(info.classFile) == "string" and info.classFile:lower() or nil
  return n, f
end

-- is this class trainer of the player's own class?
function P.IsMyClass(e)
  if e.type ~= "placeTrainClass" then return true end
  local n, f = P.MyClass()
  if not e.classWord then return false end
  return e.classWord == n or e.classWord == f or (n ~= nil and n:find(e.classWord, 1, true) ~= nil)
end

-- is this place drawn right now? (its switch is on; a class trainer is also of the player's class unless "Show all classes" is on)
function P.Shown(e)
  local db = Panoply.db
  if not (db and db[e.type]) then return false end
  if e.type == "placeTrainClass" and not db.placeClassAll then return P.IsMyClass(e) end
  return true
end

function P.AnyOn()
  local db = Panoply.db
  if not db then return false end
  for _, k in ipairs(M.PLACE_KEYS) do if k ~= "placeClassAll" and k ~= "placeMinimap" and db[k] and M.KindOK(k) then return true end end
  return false
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4K (spec 05b 1.4): the kinds other pages feed. Their places are not in the index (they change while playing): each kind
-- has a provider that lists them now, kept for a few seconds. Where each one's places come from:
--   placeBeastTame  the Hunter's pet plan (Modules/HunterPet: the To tame list of the main family, else the family the Pet tab shows),
--                   each beast at its place nearest the player (where this account met it, else the NPC data: the world database)
--   placeBlueprint  Panoply Suite's own Forever notes (Data/ProfForever.lua: which boss of which dungeon drops a camp Blueprint), drawn at
--                   the dungeon's door (the instance data of the Dungeons window)
--   placeTradeCamp  Panoply Suite's own Forever notes (PF.TRADE_CAMP). No checked position is known yet, so it lists nothing until one is
--                   written there (map, x, y on the faction's entry); nothing is guessed
--   placeDeath      the Field Kit's death log (Engine/DeathLog.lua), the newest P.DEATHS_MAX deaths that have a place outside a dungeon
-------------------------------------------------------------------------------
P.DYN_TTL = 3
P.DEATHS_MAX = 20
P.DYNAMIC = {}
P.DYNAMIC.placeBeastTame = function()
  local out = {}
  local Pet = Panoply.HunterPet
  if not (Pet and Pet.ToTame and Pet.NearestSpot and M.IsHunter()) then return out end
  local fam = (Pet.Main and Pet:Main()) or (Pet.View and Pet:View())
  if not fam then return out end
  local ok, tame = pcall(Pet.ToTame, Pet, fam)
  if not (ok and type(tame) == "table") then return out end
  for _, e in ipairs(tame.list or {}) do
    local spot = Pet:NearestSpot(e.n)
    if spot and spot.map and spot.x and spot.y then
      local teaches = e.teaches and #e.teaches > 0 and Pet.RanksText and Pet.RanksText(e.teaches) or nil
      out[#out + 1] = { type = "placeBeastTame", name = e.n, sub = teaches and ("Teaches " .. teaches) or "Beast to tame", map = spot.map, x = spot.x, y = spot.y,
        level = e.t and e.t.lo and (e.t.hi and e.t.hi ~= e.t.lo and ("Level %d to %d"):format(e.t.lo, e.t.hi) or ("Level %d"):format(e.t.lo)) or nil }
    end
  end
  return out
end
P.DYNAMIC.placeBlueprint = function()
  local out = {}
  local PF, Ins = Panoply.ProfForever, M.Instances
  if not (PF and C.IsForever() and Ins and Ins.All) then return out end
  local byInst, order = {}, {}
  local function add(prof, name, src)
    if not (src and src.instance) then return end
    local g = byInst[src.instance]
    if not g then g = {} byInst[src.instance] = g order[#order + 1] = src.instance end
    g[#g + 1] = ("%s%s"):format(name, src.boss and (" (" .. src.boss .. ")") or "")
  end
  local profs = {}
  for prof in pairs(PF.CAMP or {}) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    for _, o in ipairs(PF.CAMP[prof]) do if o.blueprint then add(prof, o.name, o.source) end end
  end
  for _, t in ipairs(PF.CAMPFIRE or {}) do if t.blueprint then add("Cooking", t.tier .. " campfire", t.source) end end
  for _, iname in ipairs(order) do
    for _, inst in ipairs(Ins:All()) do
      local d = inst.doors and inst.doors[1]
      if inst.name == iname and d and d[4] and d[5] and d[6] then
        out[#out + 1] = { type = "placeBlueprint", name = inst.name, sub = "Blueprints: " .. table.concat(byInst[iname], ", "), map = d[4], x = d[5], y = d[6] }
        break
      end
    end
  end
  return out
end
P.DYNAMIC.placeTradeCamp = function()
  local out = {}
  local PF = Panoply.ProfForever
  local tc = PF and C.IsForever() and PF.TRADE_CAMP
  if type(tc) ~= "table" then return out end
  for _, side in ipairs({ "Alliance", "Horde" }) do
    local e = tc[side]
    if type(e) == "table" and e.map and e.x and e.y then
      out[#out + 1] = { type = "placeTradeCamp", name = e.name or "Trade camp", sub = side .. " trade camp", map = e.map, x = e.x, y = e.y }
    end
  end
  return out
end
P.DYNAMIC.placeDeath = function()
  local out = {}
  local DL = Panoply.DeathLog
  if not (DL and DL.List) then return out end
  local ok, list = pcall(DL.List, DL)
  for _, r in ipairs(ok and type(list) == "table" and list or {}) do
    if #out >= P.DEATHS_MAX then break end
    if r.map and r.x and r.y and not r.inst then
      out[#out + 1] = { type = "placeDeath", name = ("Where I died (level %d)"):format(r.level or 1), sub = r.zone, map = r.map, x = r.x, y = r.y, t = r.t }
    end
  end
  return out
end

local function clock() return (_G.GetTime and GetTime()) or 0 end
-- the places of a fed kind now (a copy kept P.DYN_TTL seconds; P:Invalidate drops it)
function P:Dynamic(key)
  local fn = P.DYNAMIC[key]
  if not fn or not M.KindOK(key) then return {} end
  self.dyn = self.dyn or {}
  local c = self.dyn[key]
  local t = clock()
  if c and t - c.t < P.DYN_TTL and t >= c.t then return c.list end
  local ok, list = pcall(fn)
  if not ok then Panoply:Debug("places " .. key, list) list = {} end
  self.dyn[key] = { t = t, list = list }
  return list
end
function P:Invalidate() self.dyn = nil end
Panoply:Listen("DEATH_LOGGED", function() P:Invalidate() end)

-- every place of a map, the fed kinds included (only kinds that mean something here)
function P:OnMap(map)
  local out = {}
  for _, e in ipairs(P.Index().byMap[map] or {}) do if M.KindOK(e.type) then out[#out + 1] = e end end
  for key in pairs(P.DYNAMIC) do
    if Panoply.db and Panoply.db[key] then
      for _, e in ipairs(self:Dynamic(key)) do if e.map == map then out[#out + 1] = e end end
    end
  end
  return out
end

-- how many places of a kind a zone has (what the Map page's row says: a class trainer row counts what "Show all classes" would draw)
function P:ZoneCount(key, map)
  if not map then return 0 end
  local n = 0
  if P.DYNAMIC[key] then
    for _, e in ipairs(self:Dynamic(key)) do if e.map == map then n = n + 1 end end
    return n
  end
  local db = Panoply.db or {}
  for _, e in ipairs(P.Index().byMap[map] or {}) do
    if e.type == key and (key ~= "placeTrainClass" or db.placeClassAll or P.IsMyClass(e)) then n = n + 1 end
  end
  return n
end

-- how many places of a kind the data holds (0 for a kind that has no data: see the top of this file)
function P.Count(key)
  local list = P.Index().byType[key]
  return list and #list or 0
end

function P.TypeLabel(key)
  local t = M.PLACE_BY_KEY[key]
  if t then return t.dest end
  if key == "flight" then return "Flight master" end
  return key
end

-------------------------------------------------------------------------------
-- Drawing: one layer on the world map's canvas, one set of pins on the minimap
-------------------------------------------------------------------------------
local function isContinent(map)
  local Tr = Panoply.Trail
  return Tr and Tr.IsContinentMap and Tr:IsContinentMap(map) or false
end

local function iconPath(key)
  local t = M.PLACE_BY_KEY[key]
  if t and t.slot and Panoply.Kit and Panoply.Kit.ResolveIcon then
    local how, what = Panoply.Kit.ResolveIcon(t.slot)
    if how ~= "missing" and what then return what end
  end
  if t and t.tex then return t.tex end
  return "Interface\\Minimap\\Tracking\\" .. (t and t.icon or "Class")
end
P.IconPath = iconPath

local function tipOf(p)
  local e, GT = p.entry, _G.GameTooltip
  if not (e and GT) then return end
  GT:SetOwner(p, "ANCHOR_RIGHT")
  GT:SetText(e.name, 1, 0.82, 0.25)
  if e.sub and e.sub ~= "" then GT:AddLine(e.sub, 0.9, 0.9, 0.9) end
  if P.TypeLabel(e.type) ~= e.name then GT:AddLine(P.TypeLabel(e.type), 0.7, 0.7, 0.7) end   -- a mailbox is not "Mailbox" twice
  local X = M.Extras
  if X and X.TipLines then for _, l in ipairs(X:TipLines(e)) do GT:AddLine(l, 0.9, 0.9, 0.9, true) end end
  if e.unverified then GT:AddLine("Position not checked on WoW Forever", 0.9, 0.8, 0.55, true) end
  if not p.panoplyMinimap then GT:AddLine("Click: point the arrow here", 0.5, 0.85, 1) end
  GT:Show()
end

function P:NewPin(parent, minimap)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true
  p.panoplyMinimap = minimap and true or nil
  p:SetSize(14, 14)
  -- a flat dark disc behind the icon so it reads on any map colour (no glow)
  local back = p:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(Skin.TEX.CircleMask)
  back:SetPoint("TOPLEFT", p, "TOPLEFT", -1.5, 1.5); back:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 1.5, -1.5)
  local k = Skin.colors.trailInk or { 0.04, 0.05, 0.07 }
  back:SetVertexColor(k[1], k[2], k[3], 0.92)
  p.back = back
  p.tex = p:CreateTexture(nil, "OVERLAY")
  p.tex:SetAllPoints(p)
  if minimap then
    p:EnableMouse(false)                    -- the minimap's own clicks stay the minimap's
  else
    if p.RegisterForClicks then p:RegisterForClicks("LeftButtonUp") end
    p:SetScript("OnEnter", tipOf)
    p:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
    p:SetScript("OnClick", function(self)
      local e = self.entry
      if e then M:PointAt(e.map, e.x, e.y, e.name) end
    end)
  end
  return p
end

function P:StylePin(p, e, where, px)
  p.entry = e
  p:SetSize(px, px)
  p.tex:SetTexture(iconPath(e.type))
  Look.Tint(p.tex, Look.RGB("place", where))
  p:SetAlpha(Look.Alpha("place", where))
end

function P:Layer()
  local canvas = C.WorldMapCanvas()
  if not canvas then return nil end
  if not self.layer then
    self.layer = CreateFrame("Frame", nil, canvas)
    self.layer:SetAllPoints(canvas)
    self.layer.panoplyLayoutSkip = true
  end
  if self.layer:GetParent() ~= canvas and self.layer.SetParent then self.layer:SetParent(canvas) self.layer:SetAllPoints(canvas) end
  return self.layer, canvas
end

-- what the world map shows for a zone map: every place that is switched on
function P:Collect(map)
  local out = {}
  if not map or isContinent(map) then return out end
  for _, e in ipairs(self:OnMap(map)) do
    if not P.INTERNAL[e.type] and P.Shown(e) then out[#out + 1] = e end
  end
  return out
end

function P:Refresh(why)
  self.pins = self.pins or {}
  local used = 0
  local wm, map = C.WorldMap(), C.WorldMapID()
  if M.active and wm and wm.IsShown and wm:IsShown() and map and P.AnyOn() then
    local layer, canvas = self:Layer()
    if layer then
      local lvl = M:IconLevel()
      if layer.SetFrameLevel and layer:GetFrameLevel() ~= lvl then layer:SetFrameLevel(lvl) end
      if C.FloorMapAlpha then C.FloorMapAlpha(layer) C.HookMapAlpha() end
      local markLevel = M:MarkLevel(layer:GetFrameLevel())
      local W, H = canvas:GetWidth() or 1002, canvas:GetHeight() or 668
      local Tr = Panoply.Trail
      local cs = Tr and Tr.CanvasScale and Tr:CanvasScale(canvas) or 1
      local px = P.WM_PX * Look.Size("place", "wm") / max(0.2, cs)
      for _, e in ipairs(self:Collect(map)) do
        used = used + 1
        local p = self.pins[used]
        if not p then p = self:NewPin(layer) self.pins[used] = p end
        self:StylePin(p, e, "wm", px)
        p:ClearAllPoints()
        p:SetPoint("CENTER", layer, "TOPLEFT", e.x * W, -e.y * H)
        if p.SetFrameLevel then p:SetFrameLevel(markLevel) end
        p.inUse, p.underCard = true, false
        p:Show()
      end
    end
  end
  for i = used + 1, #self.pins do local q = self.pins[i] q:Hide() q.inUse, q.underCard = false, false end
  self.shown = used
  -- the route card draws over a corner of the map after the marks: the marks it would half cover are not drawn while it is there
  if not self.cardHooked and Panoply.Trail and C.Hook(Panoply.Trail, "Card", function() P:AvoidCard() end) then self.cardHooked = true end
  self:AvoidCard()
  self:MinimapRefresh()
  return used
end

-- the same rule as the Info icons and Connections (Icons.lua I:AvoidCard): a pin that the route card's corner would half cover, with the
-- brass caps of the card on top of it, is not drawn while the card is there; it comes back when the card moves or goes
P.CARD_MARGIN = 8
local function screenRect(f)
  if not (f and f.GetLeft and f.GetRight and f.GetBottom and f.GetTop) then return nil end
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  if not (l and r and b and t) then return nil end
  local s = tonumber(f.GetEffectiveScale and f:GetEffectiveScale()) or 1
  return l * s, r * s, b * s, t * s
end
function P:AvoidCard()
  local Tr = Panoply.Trail
  local card = Tr and Tr.card
  if card and not card.panoplyPlacesHooked and card.HookScript then
    card.panoplyPlacesHooked = true
    card:HookScript("OnShow", function() P:AvoidCard() end)
    card:HookScript("OnHide", function() P:AvoidCard() end)
  end
  local cl, cr, cb, ct
  if card and card.IsShown and card:IsShown() then cl, cr, cb, ct = screenRect(card) end
  local m, n = self.CARD_MARGIN, 0
  for _, p in ipairs(self.pins or {}) do
    if p.inUse then
      local under = false
      if cl then
        local l, r, b, t = screenRect(p)
        under = l ~= nil and l < cr + m and r > cl - m and b < ct + m and t > cb - m
      end
      if under ~= (p.underCard or false) then
        p.underCard = under
        if under then p:Hide() else p:Show() end
      end
      if under then n = n + 1 end
    end
  end
  self.underCard = n
  return n
end

-- Minimap: the closest places inside the minimap's radius (none on the rim: a place that far is a walk, not a glance)
function P:MinimapRefresh()
  self.mmPins = self.mmPins or {}
  local used = 0
  local mm = _G.Minimap
  local m, px, py = C.GetPlayerPos()
  if M.active and mm and mm:IsShown() and m and P.AnyOn() and not (Panoply.db and Panoply.db.placeMinimap == false) then
    local w, h = C.MapSize(m)
    if w then
      local radius = C.MinimapRadius()
      local half = (mm:GetWidth() or 140) / 2
      local rot = C.MinimapRotates()
      local f = rot and (C.Facing() or 0) or 0
      local cf, sf = math.cos(f), math.sin(f)
      local size = P.MM_PX * Look.Size("place", "mm")
      local cand = {}
      for _, e in ipairs(self:OnMap(m)) do
        if not P.INTERNAL[e.type] and P.Shown(e) then
          local dx, dy = (e.x - px) * w, (e.y - py) * h
          local north = -dy
          local sx, sy = dx * cf + north * sf, -dx * sf + north * cf
          local d = sqrt(sx * sx + sy * sy)
          if d <= radius then cand[#cand + 1] = { e = e, sx = sx, sy = sy, d = d } end
        end
      end
      table.sort(cand, function(a, b) return a.d < b.d end)
      for k = 1, min(#cand, P.MM_CAP) do
        local c = cand[k]
        local ox, oy = c.sx / radius * (half - 6), c.sy / radius * (half - 6)
        local ca = Panoply.MinimapCentreAlpha and Panoply.MinimapCentreAlpha(ox, oy) or 1
        if ca > 0 then
          used = used + 1
          local p = self.mmPins[used]
          if not p then p = self:NewPin(mm, true) self.mmPins[used] = p end
          self:StylePin(p, c.e, "mm", size)
          p:SetAlpha(Look.Alpha("place", "mm") * ca)
          p:ClearAllPoints()
          p:SetPoint("CENTER", mm, "CENTER", ox, oy)
          p:Show()
        end
      end
    end
  end
  for i = used + 1, #self.mmPins do self.mmPins[i]:Hide() end
  self.mmShown = used
  return used
end

function P:Enable()
  if not self.driver then
    local d = CreateFrame("Frame", nil, _G.Minimap or UIParent)
    d.elapsed = 0
    d:SetScript("OnUpdate", function(frame, dt)
      frame.elapsed = frame.elapsed + (dt or 0)
      if frame.elapsed < P.MM_TICK then return end
      frame.elapsed = 0
      P:MinimapRefresh()
    end)
    self.driver = d
  end
  self.driver:Show()
end

function P:Disable()
  if self.driver then self.driver:Hide() end
  for _, p in ipairs(self.pins or {}) do p:Hide() p.inUse, p.underCard = false, false end
  for _, p in ipairs(self.mmPins or {}) do p:Hide() end
  self.shown, self.mmShown = 0, 0
end

-------------------------------------------------------------------------------
-- The live preview of the Look of the map: a few sample places, drawn by the same code and the same settings as the maps
-------------------------------------------------------------------------------
P.SAMPLE = {
  wm = { { "placeTrainClass", 26, 30 }, { "placeInn", 62, 22 }, { "placeBank", 78, 44 }, { "placeAuction", 40, 46 } },
  mm = { { "placeTrainClass", 18, 30 }, { "placeInn", 36, 22 }, { "placeBank", 32, 42 } },
}
function P:DrawSample(layer, where)
  layer.pins = layer.pins or {}
  local list = self.SAMPLE[where] or {}
  local px = where == "mm" and P.MM_PX * Look.Size("place", "mm") or P.WM_PX * Look.Size("place", "wm")
  for i, s in ipairs(list) do
    local p = layer.pins[i]
    if not p then p = self:NewPin(layer, true) layer.pins[i] = p end
    self:StylePin(p, { type = s[1], name = "Sample", map = 0, x = 0, y = 0 }, where, px)
    local x, y = s[2], s[3]
    if where == "mm" then
      -- a big pin is pulled in by its own half size so the whole of it stays inside the circle
      local half = (layer:GetWidth() or 56) / 2
      local dx, dy = x - half, y - half
      local limit = max(0, half - (px / 2 + 1))
      local d = sqrt(dx * dx + dy * dy)
      if d > limit and d > 0 then x, y = half + dx * limit / d, half + dy * limit / d end
    end
    p:ClearAllPoints()
    p:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
    p:Show()
  end
  for i = #list + 1, #layer.pins do layer.pins[i]:Hide() end
end
Look.Draw.place = function(layer, where) P:DrawSample(layer, where) end
