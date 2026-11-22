-- Quest icons module (SPEC section 22): quest givers (!), turn-ins (?) and objective dots for
-- quests in your log, on the world map and the minimap, from Panoply Suite's own quest database.
-- Information only: a click sets a waypoint, nothing is accepted or turned in for you.
-- Original code for Panoply Suite. It needs no other add-on and looks for none.
local ADDON, Panoply = ...
local C, U, Skin = Panoply.Compat, Panoply.Util, Panoply.Skin

local QP = Panoply.Modules:Register({
  key = "questpins", label = "Quest icons", icon = "Accept",
  desc = "Quest givers, turn-ins and objectives on your world map and minimap, and quest lines in mob, object and item tooltips.",
  defaults = {
    qpWorldMap = true, qpMinimap = true, qpObjectives = true, qpLowLevel = false, qpLevelsAbove = 2,
    qpRepeatable = false, qpGroup = false,
    qpTooltips = true, qpDropStart = false, qpParty = true,
    -- 0.7.3.7 ("Fix every size slider"): quest givers, hand-ins and objectives each have a size and an opacity
    -- on the world map and on the minimap (Panoply.Look); 100% is how big and how solid they have always been drawn
    qpGiverWmSize = 1, qpGiverWmAlpha = 1, qpGiverMmSize = 1, qpGiverMmAlpha = 1,
    qpTurninWmSize = 1, qpTurninWmAlpha = 1, qpTurninMmSize = 1, qpTurninMmAlpha = 1,
    qpObjectiveWmSize = 1, qpObjectiveWmAlpha = 1, qpObjectiveMmSize = 1, qpObjectiveMmAlpha = 1,
  },
})
Panoply.QuestPins = QP

-- 0.6.2 pin art (tools/make_pins_v062.py): dark disc, dark outline ring, bright rim and glyph, no glow.
local PINS = "Interface\\AddOns\\PanoplySuite\\Media\\Pins\\"
QP.TEX = {
  give = PINS .. "QuestGiver", low = PINS .. "QuestGiver", soon = PINS .. "QuestGiverGrey",
  turnin = PINS .. "QuestTurnin", incomplete = PINS .. "QuestTurninGrey",
  obj = PINS .. "QuestObjective", highlight = PINS .. "QuestHighlight",
}
-- Base sizes in pixels at 100% (already a little above the usual 16 px map icons). Each kind of pin has its own size
-- and opacity per map (Panoply.Look): the number is the only thing that scales it, nothing is multiplied.
-- 0.7.3.7: the world map's base is what 0.7.3.6 drew at its default: 20 px x 1.15 = 23 px (givers, hand-ins), 14 x 1.15 = 16.1 px (objectives).
-- 0.6.1 (minimap icons too large): minimap givers/turn-ins 10 px, objective dots 6 px, drawn with the
-- light Mini* art (slim brass ring, see-through middle, small glyph); the world map keeps its 0.6.0 sizes.
-- 0.6.2 (tan '!' and '?' disappear into the terrain): the art is now a solid dark disc in a dark
-- outline ring with a bright rim and glyph; the minimap icons grow a little (12 / 8 px) so the glyph
-- reads, still well under 0.6.0's size. Low-level givers fade to 0.85 at most (0.6.1: 0.6).
QP.SIZE = { wm = { icon = 23, dot = 16.1 }, mm = { icon = 12, dot = 8 } }
QP.LOW_ALPHA = 0.85
QP.MM_CAP = 12                -- at most this many quest icons on the minimap (current-step targets first, then closest)
QP.MM_MERGE_PX = 12           -- objective dots closer than this on the minimap merge into one
QP.SCALE_MIN, QP.SCALE_MAX = Panoply.Look.SIZE_MIN, Panoply.Look.SIZE_MAX
-- which Look thing a pin kind belongs to
QP.KIND_THING = { give = "giver", low = "giver", soon = "giver", turnin = "turnin", incomplete = "turnin", obj = "objective" }
QP.RING_SCALE = 1.45         -- the current-step ring around a target pin
QP.TARGET_SCALE = 1.3
QP.BUDGET_MS = 0.6            -- work per frame for the sliced jobs (leaves room for one table resize under 1 ms)
QP.MINIMAP_INTERVAL = 0.1     -- 10 Hz
QP.MAX_DOTS = 12              -- per objective
QP.CELL = 0.035               -- spots closer than this (map fraction) merge into one dot
QP.MAX_SPOTS = 20             -- per quest giver / finisher

QP.TEX_MM = {
  give = PINS .. "MiniGiver", low = PINS .. "MiniGiver", soon = PINS .. "MiniGiverGrey",
  turnin = PINS .. "MiniTurnin", incomplete = PINS .. "MiniTurninGrey", obj = PINS .. "MiniObjective",
}

-- Step 2 D (Look of the map): "Blizzard default" draws a pin with the game's own quest icon (Skin.BUILTIN, probed: a client that does not
-- have the texture draws Panoply Suite's pin instead, and does not offer the choice for that thing). The game's icon is shown as it is, not
-- tinted; the grey states (a quest that opens soon, a low-level one) keep their greyness by greying the game's icon.
-- UNVERIFIED in the real game: which of these textures exist on Era 1.15 and on Forever, and that GetFileIDFromPath exists there to say so
-- (Skin.BuiltinProven: with no proof the game's icon is never drawn).
-- (no entry for an objective: there is no game texture known to fit, so Objectives are not offered "Blizzard default")
QP.GAME_KEY = { give = "questGiver", low = "questGiver", soon = "questGiver", turnin = "questTurnin", incomplete = "questIncomplete" }
QP.GAME_GREY = { low = true, soon = true }
Panoply.Look.AVAIL.blizzard = function(thing)
  local main = { giver = "give", turnin = "turnin", objective = "obj" }
  return main[thing] ~= nil and QP:GameArt(main[thing]) ~= nil
end

local QD = function() return Panoply.QuestData end
local function clock()
  local f = _G.debugprofilestop
  if f then local ok, v = pcall(f) if ok and type(v) == "number" then return v end end
  return C.GetTime() * 1000
end
QP.Clock = clock

-------------------------------------------------------------------------------
-- State generation: everything cached below is thrown away when it changes.
-------------------------------------------------------------------------------
QP.gen = 0
function QP:Invalidate(why)
  self.gen = self.gen + 1
  self.ctx = nil
  self.mapPins = {}
  self.logIdx = nil
  Panoply:Fire("QUESTPINS_INVALIDATED", why)
end
QP.mapPins = {}

-- Nothing hides the icons but their own switches (0.9.7 hotfix: no other add-on is looked for).
function QP:Suppressed() return false end

-- Player facts the eligibility rules need, read once per generation.
function QP:Ctx()
  if self.ctx then return self.ctx end
  local S, db = Panoply.State, Panoply.db or {}
  local info = C.PlayerInfo()
  local level = S.level or 1
  local qd = QD()
  self.ctx = {
    level = level, completed = S.completed or {}, log = S.log or {}, skills = S.skills or {},
    raceMask = qd and qd:RaceMask(info.raceID), classMask = qd and qd:ClassMask(info.classID, info.classFile),
    green = C.TrivialRange(level) or 5, above = math.max(0, tonumber(db.qpLevelsAbove) or 2),
    lowLevel = db.qpLowLevel and true or false, repeatable = db.qpRepeatable and true or false,
    group = db.qpGroup and true or false, state = {},
  }
  return self.ctx
end

-------------------------------------------------------------------------------
-- Eligibility (the route planner's rules, SPEC 22.2). Returns "give" | "low" | "soon" | nil, why.
-------------------------------------------------------------------------------
local function done(ctx, id) return ctx.completed[id] == true end

function QP:GiverState(id)
  local ctx = self:Ctx()
  local c = ctx.state[id]
  if c ~= nil then return c or nil, ctx.why and ctx.why[id] end
  local st, why = self:EvalGiver(id, ctx)
  ctx.state[id] = st or false
  ctx.why = ctx.why or {}
  ctx.why[id] = why
  return st, why
end

function QP:EvalGiver(id, ctx)
  local qd = QD()
  local q = qd and qd:GetQuest(id)
  if not q then return nil, "unknown" end
  if done(ctx, id) then return nil, "done" end
  if ctx.log[id] then return nil, "in log" end
  if qd.hidden and qd.hidden[id] then return nil, "hidden" end
  if q.races ~= 0 and ctx.raceMask and not U.HasBitValue(q.races, ctx.raceMask) then return nil, "race" end
  if q.classes ~= 0 and ctx.classMask and not U.HasBitValue(q.classes, ctx.classMask) then return nil, "class" end
  if (q.specialFlags or 0) % 2 == 1 and not ctx.repeatable then return nil, "repeatable" end
  if q.reqSkill then
    local have = ctx.skills[q.reqSkill[1]]
    if not have or have < (q.reqSkill[2] or 0) then return nil, "skill" end
  end
  if (q.reqSpell or 0) ~= 0 or q.reqMinRep then return nil, "requirement" end
  if (q.parentQuest or 0) ~= 0 then return nil, "child" end
  if (q.reqMaxLevel or 0) > 0 and ctx.level > q.reqMaxLevel then return nil, "too high" end
  for _, p in ipairs(q.preGroup or {}) do if not done(ctx, p) then return nil, "prerequisite" end end
  if q.preSingle and #q.preSingle > 0 then
    local any = false
    for _, p in ipairs(q.preSingle) do if done(ctx, p) then any = true break end end
    if not any then return nil, "prerequisite" end
  end
  for _, e in ipairs(q.exclusiveTo or {}) do if done(ctx, e) or ctx.log[e] then return nil, "exclusive" end end
  if (q.nextInChain or 0) ~= 0 and (done(ctx, q.nextInChain) or ctx.log[q.nextInChain]) then return nil, "chain" end
  if (q.breadcrumbFor or 0) ~= 0 and (done(ctx, q.breadcrumbFor) or ctx.log[q.breadcrumbFor]) then return nil, "breadcrumb" end
  if not ctx.group then
    local ok, g = pcall(qd.GroupContentReason, qd, q)
    if ok and g then return nil, g end
  end
  local qlevel = (q.level and q.level > 0) and q.level or q.reqLevel or 1
  local low = qlevel < ctx.level - ctx.green
  if low and not ctx.lowLevel then return nil, "trivial" end
  if (q.reqLevel or 1) > ctx.level then
    if q.reqLevel <= ctx.level + ctx.above then return "soon", "level" end
    return nil, "level"
  end
  return low and "low" or "give"
end

-------------------------------------------------------------------------------
-- Index: who gives / takes which quest, and where they stand (built once, in slices).
-------------------------------------------------------------------------------
local function slice(self)
  local job = self.job
  if job and clock() - job.t0 > self.BUDGET_MS then coroutine.yield() end
end
QP.Slice = slice

function QP:BuildIndex()
  local qd = QD()
  local idx = { give = { npc = {}, obj = {} }, finish = { npc = {}, obj = {} }, itemStarts = {}, giverSpots = {}, quests = 0, spots = 0 }
  if not (qd and qd:Available()) then return idx end   -- not stored: tried again later
  local function add(t, k, id) local l = t[k] if not l then l = {} t[k] = l end l[#l + 1] = id end
  for id in qd:EachQuestId() do
    local q = qd:GetQuest(id)
    if q then
      idx.quests = idx.quests + 1
      for _, n in ipairs(q.starts.npc) do add(idx.give.npc, n, id) end
      for _, o in ipairs(q.starts.obj) do add(idx.give.obj, o, id) end
      for _, it in ipairs(q.starts.item or {}) do add(idx.itemStarts, it, id) end
      for _, n in ipairs(q.ends.npc) do add(idx.finish.npc, n, id) end
      for _, o in ipairs(q.ends.obj) do add(idx.finish.obj, o, id) end
    end
    slice(self)
  end
  -- quest ids came in table order: sort each list so pins and tooltips list quests the same way every time
  local n = 0
  for _, group in ipairs({ idx.give.npc, idx.give.obj, idx.finish.npc, idx.finish.obj, idx.itemStarts }) do
    for _, l in pairs(group) do
      if #l > 1 then table.sort(l) end
      n = n + 1
      if n % 20 == 0 then slice(self) end
    end
  end
  -- giver spots by map
  n = 0
  for kind, list in pairs(idx.give) do
    for id in pairs(list) do
      local spots = kind == "npc" and qd:NpcSpots(id) or qd:ObjectSpots(id)
      local hostile = kind == "npc" and qd:NpcFriendly(id) == false
      if not hostile then
        for k, s in ipairs(spots) do
          if k > self.MAX_SPOTS then break end
          if s.map and s.x and s.y then
            local m = idx.giverSpots[s.map]
            if not m then m = {} idx.giverSpots[s.map] = m end
            m[#m + 1] = { kind, id, s.x, s.y, s.unverified or nil }
            idx.spots = idx.spots + 1
          end
        end
      end
      n = n + 1
      if n % 5 == 0 then slice(self) end
    end
  end
  self.index = idx
  if Panoply.QuestTips then Panoply.QuestTips:Clear() end   -- tooltip lines built before the index lacked givers
  return idx
end

-------------------------------------------------------------------------------
-- Jobs: coroutines resumed for BUDGET_MS per frame by one driver frame.
-------------------------------------------------------------------------------
QP.jobs = {}
QP.stats = { slices = 0, maxSliceMs = 0, indexMs = 0, computeMs = 0 }
function QP:Queue(key, fn)
  for _, j in ipairs(self.jobs) do if j.key == key then return j end end
  local j = { key = key, co = coroutine.create(function() fn(self) end) }
  self.jobs[#self.jobs + 1] = j
  if self.jobFrame then self.jobFrame:Show() end
  return j
end

function QP:Step()
  local j = self.jobs[1]
  if not j then if self.jobFrame then self.jobFrame:Hide() end return false end
  self.job = j
  j.t0 = clock()
  local ok, err = coroutine.resume(j.co)
  local ms = clock() - j.t0
  self.job = nil
  local st = self.stats
  st.slices = st.slices + 1
  if ms > st.maxSliceMs then st.maxSliceMs = ms end
  j.ms = (j.ms or 0) + ms
  if not ok then Panoply:Debug("questpins job", j.key, err) end
  if not ok or coroutine.status(j.co) == "dead" then
    table.remove(self.jobs, 1)
    if j.key == "index" then st.indexMs = j.ms else st.computeMs = j.ms end
    if j.after then pcall(j.after) end
  end
  return true
end

-- One frame's turn from the job frame. The 0.6.0 router has priority: while it is planning (or
-- already ran a slice this frame) the index waits, so the two never stack in one frame.
QP.waitedFrames = 0
function QP:FrameStep()
  local R = Panoply.Route
  if R and R.Busy and R:Busy() then self.waitedFrames = self.waitedFrames + 1 return false end
  return self:Step()
end

-- Run every queued job to the end now (tests).
function QP:Finish() local n = 0 while self:Step() and n < 100000 do n = n + 1 end end

function QP:EnsureIndex()
  if self.index then return true end
  self:Queue("index", self.BuildIndex)
  return false
end

-------------------------------------------------------------------------------
-- Objectives: which log objective an objective area belongs to.
-------------------------------------------------------------------------------
local function plain(s) return tostring(s or ""):lower() end
function QP:AreaName(a)
  local qd = QD()
  if a.kind == "kill" then return qd:NpcName(a.id) end
  if a.kind == "item" then return qd:ItemName(a.id) end
  if a.kind == "object" then return qd:ObjectName(a.id) end
  return a.text
end

-- Returns the log objective (table) and its index for objective area number i of quest qid.
function QP:MatchObjective(qid, a, i)
  local objs = Panoply.State:Objectives(qid) or {}
  local name = self:AreaName(a)
  if name and name ~= "" then
    local n = plain(name)
    for j, o in ipairs(objs) do if plain(o.text):find(n, 1, true) then return o, j end end
  end
  if objs[i] then return objs[i], i end
  return nil, i
end

local function progress(o)
  if not o then return nil end
  local need = tonumber(o.numRequired) or 0
  if need > 0 then return ("%d/%d"):format(tonumber(o.numFulfilled) or 0, need) end
  return o.finished and "done" or nil
end
QP.Progress = progress

-------------------------------------------------------------------------------
-- Pins for one map: { kind, x, y, quests = { ids }, npc / obj, idx, item, unverified }
-------------------------------------------------------------------------------
local function cluster(spots, cell, max)
  local cells, list = {}, {}
  for _, s in ipairs(spots) do
    local k = math.floor(s.x / cell) .. ":" .. math.floor(s.y / cell)
    local c = cells[k]
    if not c then c = { x = 0, y = 0, n = 0, unverified = s.unverified } cells[k] = c list[#list + 1] = c end
    c.x, c.y, c.n = c.x + s.x, c.y + s.y, c.n + 1
  end
  for _, c in ipairs(list) do c.x, c.y = c.x / c.n, c.y / c.n end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
  for i = #list, (max or 12) + 1, -1 do list[i] = nil end
  return list
end
QP.Cluster = cluster

function QP:ComputeMap(map)
  local qd = QD()
  local pins = {}
  local idx = self.index
  if not (qd and qd:Available() and idx and map) then return pins end
  local ctx = self:Ctx()
  -- givers
  local byKey = {}
  for i, e in ipairs(idx.giverSpots[map] or {}) do
    local kind, id = e[1], e[2]
    local best, quests, rk = nil, {}, {}
    local rank = { give = 3, low = 2, soon = 1 }
    for _, qid in ipairs(idx.give[kind][id] or {}) do
      local st = self:GiverState(qid)
      if st then
        quests[#quests + 1] = qid
        rk[qid] = rank[st]
        if not best or rank[st] > rank[best] then best = st end
      end
    end
    -- the tooltip lists what you can take now first, then grey, then later quests
    if #quests > 1 then table.sort(quests, function(a, b) if rk[a] ~= rk[b] then return rk[a] > rk[b] end return a < b end) end
    if best then
      local k = kind .. id .. ":" .. math.floor(e[3] * 200) .. ":" .. math.floor(e[4] * 200)
      if not byKey[k] then
        local p = { kind = best, x = e[3], y = e[4], quests = quests, map = map, unverified = e[5] }
        p[kind] = id
        byKey[k] = p
        pins[#pins + 1] = p
      end
    end
    if i % 10 == 0 then slice(self) end
  end
  -- turn-ins and objectives of quests in your log
  local showObj = Panoply.db.qpObjectives ~= false
  local n = 0
  for qid, e in pairs(ctx.log) do
    local q = qd:GetQuest(qid)
    if q then
      local ready = e.isComplete and true or false
      for k, s in ipairs(qd:FinisherSpots(q)) do
        if k > self.MAX_SPOTS then break end
        if s.map == map then
          pins[#pins + 1] = { kind = ready and "turnin" or "incomplete", x = s.x, y = s.y, quests = { qid }, npc = s.npc, obj = s.obj, map = map, unverified = s.unverified }
        end
      end
      if showObj and not ready then
        n = n + 1
        for i, a in ipairs(qd:ObjectiveAreas(q)) do
          local o, j = self:MatchObjective(qid, a, i)
          if not (o and o.finished) then
            local here = {}
            for _, s in ipairs(a.spots or {}) do if s.map == map and s.x and s.y then here[#here + 1] = s end end
            for _, c in ipairs(cluster(here, self.CELL, self.MAX_DOTS)) do
              pins[#pins + 1] = { kind = "obj", x = c.x, y = c.y, quests = { qid }, idx = j, area = a.kind, areaId = a.id,
                item = a.kind == "item" and a.id or nil, map = map, unverified = c.unverified, count = c.n }
            end
          end
          slice(self)
        end
      end
    end
  end
  -- draw order: objectives under turn-ins under givers
  local order = { obj = 1, incomplete = 2, turnin = 3, soon = 4, low = 5, give = 6 }
  table.sort(pins, function(a, b)
    if order[a.kind] ~= order[b.kind] then return order[a.kind] < order[b.kind] end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return pins
end

-- Pins for a map, from the cache; queues the work when it is not there yet. sync = finish now.
function QP:PinsFor(map, sync)
  if not map then return nil end
  local c = self.mapPins[map]
  if c and c.gen == self.gen then return c.pins end
  self:EnsureIndex()
  local gen = self.gen
  local j = self:Queue("map:" .. map, function()
    if not self.index then return end
    local pins = self:ComputeMap(map)
    if gen == self.gen then self.mapPins[map] = { gen = gen, pins = pins } end
  end)
  j.after = function() if self.gen == gen then self:Redraw() end end
  if sync then self:Finish() local c2 = self.mapPins[map] return c2 and c2.pins end
  return nil
end

-------------------------------------------------------------------------------
-- The current guide step's target (drawn larger)
-------------------------------------------------------------------------------
function QP:Targets()
  local t = {}
  local E = Panoply.Engine
  local step = E and E.Current and E:Current()
  for _, g in ipairs(step and step.goals or {}) do
    if g.questID then
      if g.type == "accept" then t[g.questID .. ":give"] = true
      elseif g.type == "turnin" then t[g.questID .. ":turnin"] = true
      elseif g.type == "objective" or g.type == "complete" then t[g.questID .. ":obj"] = true end
    end
  end
  return t
end
local ROLE = { give = "give", low = "give", soon = "give", turnin = "turnin", incomplete = "turnin", obj = "obj" }
function QP:IsTarget(p, targets)
  for _, qid in ipairs(p.quests) do if targets[qid .. ":" .. ROLE[p.kind]] then return true end end
  return false
end

-------------------------------------------------------------------------------
-- Pin frames (pooled)
-------------------------------------------------------------------------------
local function pinEnter(self) QP:ShowPinTip(self) end
local function pinLeave() local GT = _G.GameTooltip if GT then GT:Hide() end end
local function pinClick(self, button) QP:OnPinClick(self, button) end

-- a pin frame with its handlers; NewPin counts it (the pools of the maps), the preview in the Look of the map builds its own
function QP:BuildPin(parent)
  local p = CreateFrame("Button", nil, parent)
  p.panoplyLayoutSkip = true   -- placed at a map position; neighbours may touch
  local ring = p:CreateTexture(nil, "BACKGROUND")
  ring:SetTexture(self.TEX.highlight)
  ring:SetPoint("CENTER", p, "CENTER", 0, 0)
  ring:Hide()
  p.ring = ring
  local t = p:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(p); p.tex = t
  if p.RegisterForClicks then p:RegisterForClicks("LeftButtonUp") end
  p:SetScript("OnEnter", pinEnter)
  p:SetScript("OnLeave", pinLeave)
  p:SetScript("OnClick", pinClick)
  return p
end
function QP:NewPin(parent)
  local p = self:BuildPin(parent)
  self.created = (self.created or 0) + 1
  return p
end

function QP:Icon(kind, where)
  if where == "mm" then return self.TEX_MM[kind] or self.TEX_MM.give end
  return self.TEX[kind] or self.TEX.give
end

-- the game's own texture for a kind of pin, or nil when the game has not proven it has one (Skin.BuiltinProven asks once and keeps the answer)
function QP:GameArt(kind)
  local key = self.GAME_KEY[kind]
  return key and Skin.BuiltinProven(key) or nil
end

-- A pin that is not ready (a quest that opens soon, a hand-in that cannot be finished yet) must still look not ready under any Colour:
-- today it is told apart by its grey art, and with one colour for every pin that is gone, so these are drawn in the chosen colour at half
-- the brightness. The ready one (a ! to pick up, a ? to hand in) keeps the whole colour.
QP.NOT_READY = { soon = true, incomplete = true }
QP.NOT_READY_DIM = 0.5
local dimmed = {}                 -- the dimmed copy of a colour, made once (the pins are redrawn many times a second)
local function dimmedRGB(rgb)
  local e = dimmed[rgb]
  if not (e and e[1] == rgb[1] and e[2] == rgb[2] and e[3] == rgb[3]) then
    local k = QP.NOT_READY_DIM
    e = { rgb[1], rgb[2], rgb[3], d = { rgb[1] * k, rgb[2] * k, rgb[3] * k } }
    dimmed[rgb] = e
  end
  return e.d
end

-- How a pin is drawn on a map (Look of the map: Colour): the texture, whether it is greyed, and { r, g, b } when the pin takes one
-- colour (the art goes grey and the colour multiplies it: the light parts take the colour, the dark outline stays). Panoply Suite's pin is
-- today's art; Blizzard default is the game's own icon, not tinted. The map and the live preview both ask this.
function QP:PinArt(kind, where)
  local thing = self.KIND_THING[kind] or "giver"
  local Look = Panoply.Look
  if Look.Colour(thing, where) == "blizzard" then
    local path = self:GameArt(kind)
    if path then return path, self.GAME_GREY[kind] and true or false, nil end
    return self:Icon(kind, where), false, nil          -- this client has no icon for this kind: Panoply Suite's pin
  end
  local rgb = Look.RGB(thing, where)
  if rgb and self.NOT_READY[kind] then rgb = dimmedRGB(rgb) end
  return self:Icon(kind, where), rgb ~= nil, rgb
end

function QP:SetPin(f, p, size, where)
  f.pin = p
  local t = f.tex
  local path, grey, rgb = self:PinArt(p.kind, where or "wm")
  t:SetTexture(path)
  if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
  t:SetVertexColor(1, 1, 1, 1)
  if t.SetDesaturated then t:SetDesaturated(grey) end
  if rgb then t:SetVertexColor(rgb[1], rgb[2], rgb[3], 1) end
  t.panoplyGameIcon = nil
  f:SetSize(size, size)
  if p.target then f.ring:SetSize(size * self.RING_SCALE, size * self.RING_SCALE) f.ring:Show() else f.ring:Hide() end
  f:SetAlpha(self:PinAlpha(p, where or "wm"))
end

function QP:Thing(p) return self.KIND_THING[p.kind] or "giver" end

-- how solid a pin is: its opacity setting for this map (Look), times the fade of a low-level quest
function QP:PinAlpha(p, where)
  return (p.kind == "low" and self.LOW_ALPHA or 1) * Panoply.Look.Alpha(self:Thing(p), where)
end

function QP:PinSize(p, where, targets)
  local s = self.SIZE[where]
  local size = (p.kind == "obj" and s.dot or s.icon) * Panoply.Look.Size(self:Thing(p), where)
  if targets and self:IsTarget(p, targets) then size = size * self.TARGET_SCALE p.target = true else p.target = nil end
  return size
end

-------------------------------------------------------------------------------
-- World map
-------------------------------------------------------------------------------
function QP:WorldMapRefresh()
  local canvas, wm = C.WorldMapCanvas(), C.WorldMap()
  self.wmPins = self.wmPins or {}
  local used = 0
  if self.active and Panoply.db.qpWorldMap and not self:Suppressed() and canvas and wm and wm:IsShown() then
    local map = C.WorldMapID()
    local pins = map and self:PinsFor(map)
    if pins then
      if not self.wmLayer then
        self.wmLayer = CreateFrame("Frame", nil, canvas)
        self.wmLayer:SetAllPoints(canvas)
      end
      -- 0.6.1: above Blizzard's explored-area art (an absolute pin level of about 2001), not canvas + 25
      C.LiftOnWorldMap(self.wmLayer, "pins")
      if C.FloorMapAlpha then C.FloorMapAlpha(self.wmLayer) C.HookMapAlpha() end   -- 0.6.2: never fade away
      local W, H = canvas:GetWidth() or 1000, canvas:GetHeight() or 667
      local scale = math.max(0.2, (canvas.GetScale and canvas:GetScale()) or 1)
      local targets = self:Targets()
      for _, p in ipairs(pins) do
        used = used + 1
        local f = self.wmPins[used]
        if not f then f = self:NewPin(self.wmLayer) self.wmPins[used] = f end
        self:SetPin(f, p, self:PinSize(p, "wm", targets) / scale)
        f:ClearAllPoints(); f:SetPoint("CENTER", self.wmLayer, "TOPLEFT", p.x * W, -p.y * H)
        if f.SetFrameLevel then f:SetFrameLevel((self.wmLayer:GetFrameLevel() or 1) + used % 50 + (p.kind == "obj" and 0 or 50)) end
        f.where = "wm"
        f:Show()
      end
      self.wmMap = map
    end
  end
  for i = used + 1, #self.wmPins do self.wmPins[i]:Hide() end
  self.wmShown = used
  return used
end

-------------------------------------------------------------------------------
-- Minimap: icons inside the circle only, rotation and zoom aware (Gathering's projection).
-------------------------------------------------------------------------------
function QP:MinimapProject(px, py, x, y, w, h, radius, half, rot, facing)
  local e, s = (x - px) * w, (y - py) * h
  local north = -s
  local sx, sy = e, north
  if rot then
    local cf, sf = math.cos(facing), math.sin(facing)
    sx, sy = e * cf + north * sf, -e * sf + north * cf
  end
  local d = math.sqrt(sx * sx + sy * sy)
  if d > radius then return nil, nil, d end
  local r = half - 4
  return sx / radius * r, sy / radius * r, d
end

-- 0.6.1: lighter minimap. Small icons, objective dots merged within MM_MERGE_PX, at most MM_CAP
-- icons (current-step targets first, then the closest), and anything within Panoply.MM_CENTER_PX of the
-- centre fades out so the player arrow is never covered.
function QP:MinimapRefresh()
  self.mmPins = self.mmPins or {}
  local mm = _G.Minimap
  local used = 0
  local m, px, py = C.GetPlayerPos()
  self.mmMerged, self.mmCapped, self.mmFaded = 0, 0, 0
  if self.active and Panoply.db.qpMinimap and not self:Suppressed() and mm and mm:IsShown() and m then
    local w, h = C.MapSize(m)
    local pins = w and self:PinsFor(m)
    if pins then
      local radius = C.MinimapRadius()
      local half = (mm:GetWidth() or 140) / 2
      local rot = C.MinimapRotates()
      local facing = rot and (C.Facing() or 0) or 0
      local targets = self:Targets()
      local cand = {}
      for _, p in ipairs(pins) do
        local sx, sy, d = self:MinimapProject(px, py, p.x, p.y, w, h, radius, half, rot, facing)
        if sx then cand[#cand + 1] = { p = p, sx = sx, sy = sy, d = d, target = self:IsTarget(p, targets) and true or false } end
      end
      table.sort(cand, function(a, b)
        if a.target ~= b.target then return a.target end
        if a.d ~= b.d then return a.d < b.d end
        return (a.p.kind or "") < (b.p.kind or "")
      end)
      local keep, dots = {}, {}
      local merge2 = self.MM_MERGE_PX * self.MM_MERGE_PX
      for _, c in ipairs(cand) do
        local skip = false
        if c.p.kind == "obj" and not c.target then
          for _, o in ipairs(dots) do
            if (o.sx - c.sx) ^ 2 + (o.sy - c.sy) ^ 2 < merge2 then skip = true break end
          end
        end
        if skip then self.mmMerged = self.mmMerged + 1
        elseif #keep >= self.MM_CAP then self.mmCapped = self.mmCapped + 1
        else
          keep[#keep + 1] = c
          if c.p.kind == "obj" then dots[#dots + 1] = c end
        end
      end
      for _, c in ipairs(keep) do
        -- 0.7.3.7: a big icon (the size sliders go to 300%) is pulled in by its own half size (and its ring, for the current step's
        -- target) so the whole of it stays inside the round minimap; the trail does the same with its dots
        local size = self:PinSize(c.p, "mm", targets)
        c.size = size
        local reach = size / 2 * (c.p.target and self.RING_SCALE or 1) + 1
        local limit = math.max(0, half - reach)
        local dist = math.sqrt(c.sx * c.sx + c.sy * c.sy)
        if dist > limit and dist > 0 then c.sx, c.sy = c.sx * limit / dist, c.sy * limit / dist end
        local a = Panoply.MinimapCentreAlpha(c.sx, c.sy)
        if a <= 0 then self.mmFaded = self.mmFaded + 1
        else
          used = used + 1
          local f = self.mmPins[used]
          if not f then f = self:NewPin(mm) self.mmPins[used] = f end
          self:SetPin(f, c.p, c.size, "mm")
          f:SetAlpha(self:PinAlpha(c.p, "mm") * a)
          if a < 1 then self.mmFaded = self.mmFaded + 1 end
          f:ClearAllPoints(); f:SetPoint("CENTER", mm, "CENTER", c.sx, c.sy)
          f.where = "mm"
          f.mmAlpha = a
          f:Show()
        end
      end
    end
  end
  for i = used + 1, #self.mmPins do self.mmPins[i]:Hide() end
  self.mmShown = used
  self.mmUpdates = (self.mmUpdates or 0) + 1
  return used
end

function QP:Redraw()
  self:WorldMapRefresh()
  self:MinimapRefresh()
end

-- A small sample of one thing for the live preview in the Look of the map: the same pins, sizes, opacities and art the map draws (the
-- same functions), in a box of the map's true size. layer = a frame; where = "wm" or "mm".
QP.SAMPLE = {
  giver = { "give", "soon" }, turnin = { "turnin", "incomplete" }, objective = { "obj", "obj", "obj" },
}
QP.SAMPLE_AT = {   -- spots in a 108 x 64 box (the world map) and in a 56 x 56 circle (the minimap)
  wm = { giver = { { 34, 34 }, { 76, 28 } }, turnin = { { 34, 34 }, { 76, 28 } }, objective = { { 24, 40 }, { 56, 22 }, { 86, 38 } } },
  mm = { giver = { { 20, 32 }, { 38, 22 } }, turnin = { { 20, 32 }, { 38, 22 } }, objective = { { 16, 36 }, { 28, 18 }, { 40, 34 } } },
}
function QP:DrawSample(layer, thing, where)
  layer.pins = layer.pins or {}
  local kinds, at = self.SAMPLE[thing], self.SAMPLE_AT[where][thing]
  for i, kind in ipairs(kinds) do
    local f = layer.pins[i]
    if not f then
      f = self:BuildPin(layer)
      f:EnableMouse(false)
      layer.pins[i] = f
    end
    local p = { kind = kind }
    local size = self:PinSize(p, where, nil)
    self:SetPin(f, p, size, where)
    f:SetAlpha(self:PinAlpha(p, where))
    local x, y = at[i][1], at[i][2]
    if where == "mm" then
      -- as on the real minimap: a big icon is pulled in by its own half size so the whole of it stays inside the circle
      local half = (layer:GetWidth() or 56) / 2
      local dx, dy = x - half, y - half
      local limit = math.max(0, half - (size / 2 + 1))
      local d = math.sqrt(dx * dx + dy * dy)
      if d > limit and d > 0 then x, y = half + dx * limit / d, half + dy * limit / d end
    end
    f:ClearAllPoints(); f:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
    f:Show()
  end
  for i = #kinds + 1, #layer.pins do layer.pins[i]:Hide() end
end
for _, thing in ipairs({ "giver", "turnin", "objective" }) do
  Panoply.Look.Draw[thing] = function(layer, where) QP:DrawSample(layer, thing, where) end
end

-------------------------------------------------------------------------------
-- Pin tooltip and click
-------------------------------------------------------------------------------
function QP:QuestTitle(qid)
  local qd = QD()
  local q = qd and qd:GetQuest(qid)
  local e = Panoply.State.log[qid]
  local name = (q and q.name) or (e and e.title) or ("Quest " .. qid)
  local lvl = (e and e.level and e.level > 0 and e.level) or (q and q.level and q.level > 0 and q.level) or (q and q.reqLevel) or 1
  return name, lvl, q
end

local function tip(name, text) local c = Skin.RGB(name) return { text, c[1], c[2], c[3] } end
local function addLine(GT, text, r, g, b) if GT.AddLine then GT:AddLine(text, r, g, b) end end

function QP:ShowPinTip(f)
  local p, GT = f.pin, _G.GameTooltip
  if not (p and GT) then return end
  local qd = QD()
  GT:SetOwner(f, "ANCHOR_RIGHT")
  local who = (p.npc and qd:NpcName(p.npc)) or (p.obj and qd:ObjectName(p.obj))
  local lines = {}
  local shown = 0
  for i, qid in ipairs(p.quests) do
    if i > 6 then lines[#lines + 1] = tip("qpTipDim", ("+%d more"):format(#p.quests - 6)) break end
    local name, lvl, q = self:QuestTitle(qid)
    local _, col = Panoply.Difficulty.Color(lvl)
    if shown == 0 then GT:SetText(("[%d] %s"):format(lvl, name), col[1], col[2], col[3])
    else lines[#lines + 1] = { ("[%d] %s"):format(lvl, name), col[1], col[2], col[3] } end
    shown = shown + 1
    if p.kind == "soon" or (p.kind == "give" and self:GiverState(qid) == "soon") then
      lines[#lines + 1] = tip("qpTipDim", ("Available at level %d"):format(q and q.reqLevel or lvl))
    end
    if Panoply.State.log[qid] then
      for j, o in ipairs(Panoply.State:Objectives(qid) or {}) do
        if not p.idx or p.kind ~= "obj" or j == p.idx then
          local done = o.finished
          lines[#lines + 1] = tip(done and "qpTipDone" or "qpTipText", "  " .. tostring(o.text or ("Objective " .. j)))
        end
      end
      local QPty = Panoply.QuestParty
      if QPty then for _, l in ipairs(QPty:Lines(qid, p.kind == "obj" and p.idx or nil)) do lines[#lines + 1] = { "  " .. l[1], l[2], l[3], l[4] } end end
    end
  end
  if p.kind == "give" or p.kind == "low" or p.kind == "soon" then
    if who then lines[#lines + 1] = tip("qpTipLabel", "Quest giver: " .. who) end
  elseif p.kind == "turnin" then
    if who then lines[#lines + 1] = tip("qpTipLabel", "Turn in to: " .. who) end
    lines[#lines + 1] = tip("qpTipReady", "Ready to turn in")
  elseif p.kind == "incomplete" then
    if who then lines[#lines + 1] = tip("qpTipDim", "Turn in to: " .. who) end
    lines[#lines + 1] = tip("qpTipDim", "Not finished yet")
  elseif p.kind == "obj" then
    local an = self:AreaName({ kind = p.area, id = p.areaId })
    if an then lines[#lines + 1] = tip("qpTipLabel", (p.area == "kill" and "Kill: " or p.area == "item" and "Collect: " or "Use: ") .. an) end
  end
  if C.IsForever() and (p.unverified or (qd.RedrawnZone and qd:RedrawnZone(p.map))) then
    lines[#lines + 1] = { "WoW Forever redrew this zone: the position may be off.", 1, 0.6, 0.2 }
  end
  lines[#lines + 1] = { "Click: set a waypoint here", 0.5, 0.85, 1 }
  for _, l in ipairs(lines) do addLine(GT, l[1], l[2], l[3], l[4]) end
  self.lastTip = { owner = f, lines = lines }
  GT:Show()
end

function QP:QuestLink(qid)
  local f = _G.GetQuestLink
  if f then
    local ok, link = pcall(f, qid)
    if ok and type(link) == "string" and link ~= "" then return link end
    local idx = C.LogIndexForQuest(qid)
    if idx then ok, link = pcall(f, idx) if ok and type(link) == "string" and link:find("|Hquest:" .. qid, 1, true) then return link end end
  end
  return nil
end

function QP:OnPinClick(f, button)
  local p = f.pin
  if not p then return end
  local qid = p.quests[1]
  if C.ShiftDown() then
    local link = qid and self:QuestLink(qid)
    if link then C.InsertChatLink(link) end
    return
  end
  local name = qid and self:QuestTitle(qid) or "Quest"
  local label = (p.kind == "give" or p.kind == "low" or p.kind == "soon") and ("Pick up: " .. name)
    or (p.kind == "obj" and name) or ("Turn in: " .. name)
  -- Both ways end in Arrow:Retarget -> Arrow:HandTarget, the one arrow target path: the arrow points
  -- there and the route planner plans to it, so across zones the arrow follows the route's next
  -- waypoint (boat, flight, road) exactly as it does for a guide step.
  local Way = Panoply.Waypoints
  if Way and Panoply.Modules:IsOn("waypoints") and Way.Add then
    Way:Add(p.map, p.x, p.y, label)
  elseif Panoply.Arrow then
    Panoply.Arrow:PointAt(p.map, p.x, p.y, label)
  end
  if Panoply.Arrow and Panoply.Arrow.Retarget then Panoply.Arrow:Retarget() end
  self.lastClick = { map = p.map, x = p.x, y = p.y, label = label }
end

-------------------------------------------------------------------------------
-- Enable / disable, events
-------------------------------------------------------------------------------
function QP:Enable()
  if not self.driver then
    local d = CreateFrame("Frame", nil, _G.Minimap or UIParent)
    d.panoplyLayoutSkip = true
    d.elapsed = 0
    d:SetScript("OnUpdate", function(fr, dt)
      fr.elapsed = fr.elapsed + (dt or 0)
      if fr.elapsed < QP.MINIMAP_INTERVAL then return end
      fr.elapsed = 0
      QP:MinimapRefresh()
    end)
    self.driver = d
    local jf = CreateFrame("Frame", nil, UIParent)
    jf.panoplyLayoutSkip = true
    jf:SetScript("OnUpdate", function() QP:FrameStep() end)
    jf:Hide()
    self.jobFrame = jf
    local wm = C.WorldMap()
    if wm then
      if wm.HookScript then wm:HookScript("OnShow", function() if QP.active then QP:WorldMapRefresh() end end) end
      C.Hook(wm, "OnMapChanged", function() if QP.active then QP:WorldMapRefresh() end end)
    end
  end
  if #self.jobs > 0 then self.jobFrame:Show() end
  if Panoply.db.qpMinimap then self.driver:Show() else self.driver:Hide() end
  self:Invalidate("enable")
  self:EnsureIndex()
  self:WorldMapRefresh()
end

function QP:Disable()
  if self.driver then self.driver:Hide() end
  if self.jobFrame then self.jobFrame:Hide() end
  self:Redraw()
end

-- Quest log, level, completed quests: recompute (throttled), keeping the old pins until then.
function QP:Changed(why)
  if self.pending then return end
  self.pending = true
  C.After(0.5, function()
    self.pending = nil
    if not self.active then return end
    self:Invalidate(why)
    self:Redraw()
  end)
end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
  QP:On(ev, function() QP:Changed(ev) end)
end
QP:Listen("STEP_CHANGED", function() QP:Redraw() end)

local function optChanged() if QP.active then QP:Invalidate("option") QP:Redraw() end end
for _, k in ipairs({ "qpWorldMap", "qpObjectives", "qpLowLevel", "qpLevelsAbove", "qpRepeatable", "qpGroup" }) do
  Panoply.optionHooks[k] = optChanged
end
-- size and opacity sliders: only the frames change, nothing is recomputed. A world map slider redraws only the world
-- map, a minimap slider only the minimap.
for _, thing in ipairs({ "giver", "turnin", "objective" }) do
  for _, what in ipairs({ "size", "alpha", "colour" }) do
    Panoply.optionHooks[Panoply.Look.Key(thing, "wm", what)] = function() if QP.active then QP:WorldMapRefresh() end end
    Panoply.optionHooks[Panoply.Look.Key(thing, "mm", what)] = function() if QP.active then QP:MinimapRefresh() end end
  end
end
Panoply.optionHooks.qpMinimap = function(v)
  if QP.driver then if v and QP.active then QP.driver:Show() else QP.driver:Hide() end end
  QP:MinimapRefresh()
end
Panoply.optionHooks.qpTooltips = function() if Panoply.QuestTips then Panoply.QuestTips:Clear() end end
Panoply.optionHooks.qpDropStart = function() if Panoply.QuestTips then Panoply.QuestTips:Clear() end end
Panoply.optionHooks.qpParty = function() if Panoply.QuestTips then Panoply.QuestTips:Clear() end end

-- Memory and timing report (used by the tests and the build notes).
function QP:Report()
  local idx = self.index
  local pins = 0
  for _, c in pairs(self.mapPins) do pins = pins + #c.pins end
  return {
    quests = idx and idx.quests or 0, giverSpots = idx and idx.spots or 0, cachedPins = pins,
    frames = self.created or 0, indexMs = self.stats.indexMs, maxSliceMs = self.stats.maxSliceMs, slices = self.stats.slices,
  }
end

QP.options = {
  { type = "heading", label = "On your maps" },
  { type = "check", key = "qpWorldMap", label = "Show quest icons on the world map", tip = "Yellow ! where you can pick up a quest, ? where you hand one in. Click an icon to set a waypoint there." },
  { type = "check", key = "qpMinimap", label = "Show quest icons on the minimap", tip = "The same icons on your minimap, for things inside its circle." },
  { type = "check", key = "qpObjectives", label = "Show objectives", tip = "Target markers where the mobs, objects or items for quests in your log are. Hover one to see which objective it is." },
  { type = "check", key = "qpLowLevel", label = "Show low-level quests", tip = "Also show grey quests that are far below your level (they give little experience)." },
  { type = "slider", key = "qpLevelsAbove", label = "Show quests up to N levels above me", min = 0, max = 5, step = 1, fmt = "%d levels", tip = "A grey ! shows quests you can take after a few more levels. 0 turns them off." },
  { type = "check", key = "qpRepeatable", label = "Show repeatable quests", tip = "Quests you can do again and again." },
  { type = "check", key = "qpGroup", label = "Show dungeon, raid and elite group quests", tip = "Off: quests for groups (dungeons, raids, elite mobs) are left off the map." },
  { type = "heading", label = "Tooltips" },
  { type = "check", key = "qpTooltips", label = "Show quest info in tooltips", tip = "Hover a mob, NPC, object or item: which of your quests it counts for, what it drops for them, and quests it gives, takes or starts." },
  { type = "check", key = "qpDropStart", label = "Also show items that start quests", tip = "Mentions when a mob drops an item that starts a quest you can do.", parent = "qpTooltips", indent = true },
  { type = "check", key = "qpParty", label = "Show party progress", tip = "Shows how far your party members are on the same quest, when they use Panoply Suite too." },
}
-- 0.7.3.7: Quest givers, Hand-ins and Objectives each have Size and Opacity for the world map and the minimap
-- (the rows are the same on every thing: Panoply.Look.Rows; the Map page's gear shows them under "World map" / "Minimap")
for _, thing in ipairs({ "giver", "turnin", "objective" }) do
  for _, r in ipairs(Panoply.Look.Rows(thing)) do QP.options[#QP.options + 1] = r end
end

-- the settings of this module that a profile holds (Engine/Profiles.lua)
if Panoply.Profiles then
  Panoply.Profiles:AddKeys({ "qpDropStart", "qpGroup", "qpLevelsAbove", "qpLowLevel", "qpMinimap", "qpObjectives", "qpParty",
    "qpRepeatable", "qpTooltips", "qpWorldMap",
    "qpGiverWmSize", "qpGiverWmAlpha", "qpGiverMmSize", "qpGiverMmAlpha", "qpTurninWmSize", "qpTurninWmAlpha", "qpTurninMmSize", "qpTurninMmAlpha",
    "qpObjectiveWmSize", "qpObjectiveWmAlpha", "qpObjectiveMmSize", "qpObjectiveMmAlpha" })
end
