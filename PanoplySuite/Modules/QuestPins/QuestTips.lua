-- Quest lines in mob, NPC, object and item tooltips (SPEC 22.4), part of the Quest icons module.
-- Matched on the NPC ID inside the unit's GUID (items: the item ID); lines cached per GUID / item
-- until the quest log, level, completed quests, settings or party progress change. Information only.
local ADDON, Panoply = ...
local C = Panoply.Compat
local QP = Panoply.QuestPins
local QT = { cache = {}, cacheN = 0, MAX_QUESTS = 6, MAX_CACHE = 300 }
Panoply.QuestTips = QT

local function QD() return Panoply.QuestData end
-- tooltip colours are skin v3 tokens (UI/Skin.lua qpTip*), looked up when a line is added
local YELLOW, GREY, GREEN, DONE = "qpTipLabel", "qpTipDim", "qpTipReady", "qpTipDone"
local function rgb(c) return Panoply.Skin.RGB(c) end

function QT:Clear() self.cache, self.cacheN = {}, 0 end

-- What the quests in your log want from each NPC / object (rebuilt per state generation).
function QT:LogIndex()
  if self.logIdx and self.logIdx.gen == QP.gen then return self.logIdx end
  local qd = QD()
  local idx = { gen = QP.gen, npc = {}, object = {}, objNames = {}, items = {} }
  local function rel(kind, id)
    local t = idx[kind][id]
    if not t then t = { kill = {}, drop = {}, use = {}, finish = {} } idx[kind][id] = t end
    return t
  end
  local function nameObj(id) local n = qd:ObjectName(id) if n then idx.objNames[n:lower()] = id end end
  if qd and qd:Available() then
    for qid in pairs(Panoply.State.log or {}) do
      local q = qd:GetQuest(qid)
      if q then
        local o, i = q.objectives, 0
        for _, c in ipairs(o.creatures or {}) do i = i + 1 local t = rel("npc", c[1]).kill t[#t + 1] = { qid, { kind = "kill", id = c[1] }, i } end
        for _, kc in ipairs(o.killCredit or {}) do
          i = i + 1
          for _, npc in ipairs(kc[1]) do local t = rel("npc", npc).kill t[#t + 1] = { qid, { kind = "kill", id = kc[2] }, i } end
        end
        for _, ob in ipairs(o.objects or {}) do i = i + 1 local t = rel("object", ob[1]).use t[#t + 1] = { qid, { kind = "object", id = ob[1] }, i } nameObj(ob[1]) end
        for _, it in ipairs(o.items or {}) do
          i = i + 1
          local il = idx.items[it[1]] if not il then il = {} idx.items[it[1]] = il end
          il[#il + 1] = { qid, { kind = "item", id = it[1] }, i }
          local npcs, objs = qd:ItemDroppers(it[1])
          for k, npc in ipairs(npcs) do if k > 60 then break end local t = rel("npc", npc).drop t[#t + 1] = { qid, { kind = "item", id = it[1] }, i } end
          for k, ob in ipairs(objs) do if k > 30 then break end local t = rel("object", ob).drop t[#t + 1] = { qid, { kind = "item", id = it[1] }, i } nameObj(ob) end
        end
        for _, npc in ipairs(q.ends.npc) do local t = rel("npc", npc).finish t[#t + 1] = qid end
        for _, ob in ipairs(q.ends.obj) do local t = rel("object", ob).finish t[#t + 1] = qid nameObj(ob) end
      end
    end
  end
  self.logIdx = idx
  return idx
end

-- NPC (or object) -> items it drops that start a quest you could do (setting, off by default).
function QT:DropStarts(id)
  local idx = QP.index
  if not idx then return {} end
  if not self.dropStart or self.dropStart.gen ~= QP.gen then
    local qd, ds = QD(), { gen = QP.gen, npc = {} }
    for item, quests in pairs(idx.itemStarts) do
      local npcs = qd:ItemDroppers(item)
      for k, npc in ipairs(npcs) do
        if k > 60 then break end
        local l = ds.npc[npc] if not l then l = {} ds.npc[npc] = l end
        l[#l + 1] = { item, quests }
      end
    end
    self.dropStart = ds
  end
  return self.dropStart.npc[id] or {}
end

local function name(qid) return (QP:QuestTitle(qid)) end

-- The tooltip lines for one NPC or object: { { text, r, g, b }, ... }
function QT:LinesFor(id, kind)
  local qd = QD()
  local out, quests = {}, 0
  if not (qd and qd:Available() and id) then return out end
  local Party = Panoply.QuestParty
  local function add(text, c) c = rgb(c) out[#out + 1] = { text, c[1], c[2], c[3] } end
  local function party(qid, j)
    if not Party then return end
    for k, l in ipairs(Party:Lines(qid, j)) do
      if k > 4 then break end
      out[#out + 1] = { "    " .. l[1], l[2], l[3], l[4] }
    end
  end
  local function quest(text, c, qid, j)
    add(text, c) party(qid, j)
  end
  local function room() quests = quests + 1 return quests <= self.MAX_QUESTS end
  local more = 0
  local li = self:LogIndex()
  local r = li[kind] and li[kind][id]
  if r then
    for _, e in ipairs(r.kill) do
      if room() then
        local o, j = QP:MatchObjective(e[1], e[2], e[3])
        local p = QP.Progress(o)
        quest(("Quest: %s%s"):format(name(e[1]), p and ("  " .. p) or ""), (o and o.finished) and DONE or YELLOW, e[1], j)
      else more = more + 1 end
    end
    for _, e in ipairs(r.use) do
      if room() then
        local o, j = QP:MatchObjective(e[1], e[2], e[3])
        local p = QP.Progress(o)
        quest(("Quest: %s%s"):format(name(e[1]), p and ("  " .. p) or ""), (o and o.finished) and DONE or YELLOW, e[1], j)
      else more = more + 1 end
    end
    for _, e in ipairs(r.drop) do
      if room() then
        local o, j = QP:MatchObjective(e[1], e[2], e[3])
        local p = QP.Progress(o)
        local item = qd:ItemName(e[2].id) or ("item " .. e[2].id)
        quest(("Drops: %s (%s)%s"):format(item, name(e[1]), p and ("  " .. p) or ""), (o and o.finished) and DONE or YELLOW, e[1], j)
      else more = more + 1 end
    end
    for _, qid in ipairs(r.finish) do
      if room() then
        local ready = Panoply.State.log[qid] and Panoply.State.log[qid].isComplete
        if ready then add(("? %s  - complete"):format(name(qid)), GREEN) else add(("? %s  (not finished)"):format(name(qid)), GREY) end
        party(qid, nil)
      else more = more + 1 end
    end
  end
  local idx = QP.index
  if idx then
    for _, qid in ipairs(idx.give[kind == "npc" and "npc" or "obj"][id] or {}) do
      local st = QP:GiverState(qid)
      if st then
        if room() then
          if st == "soon" then
            local q = qd:GetQuest(qid)
            add(("! %s  (level %d)"):format(name(qid), q and q.reqLevel or 0), GREY)
          else
            add("! " .. name(qid), st == "low" and GREY or YELLOW)
          end
        else more = more + 1 end
      end
    end
    if kind == "npc" and Panoply.db.qpDropStart then
      for _, d in ipairs(self:DropStarts(id)) do
        local ok = false
        for _, qid in ipairs(d[2]) do if QP:GiverStateItem(qid) then ok = true break end end
        if ok then
          if room() then add("Starts a quest: " .. (qd:ItemName(d[1]) or ("item " .. d[1])), YELLOW) else more = more + 1 end
        end
      end
    end
  end
  if more > 0 then add(("+%d more"):format(more), GREY) end
  return out
end

-- Item tooltips (0.5.10): "Quest: <name>  3/8" for an item a quest in your log needs, and
-- "Starts a quest: <name>" for an item that starts one (only quests your race/class can take).
local NOT_FOR_YOU = { unknown = true, race = true, class = true, hidden = true, child = true }
function QT:ItemLines(itemID)
  local qd = QD()
  local out = {}
  if not (qd and qd:Available() and type(itemID) == "number") then return out end
  local Party = Panoply.QuestParty
  local function add(text, c) c = rgb(c) out[#out + 1] = { text, c[1], c[2], c[3] } end
  local n, more = 0, 0
  for _, e in ipairs(self:LogIndex().items[itemID] or {}) do
    n = n + 1
    if n > self.MAX_QUESTS then more = more + 1 else
      local o, j = QP:MatchObjective(e[1], e[2], e[3])
      local p = QP.Progress(o)
      add(("Quest: %s%s"):format(name(e[1]), p and ("  " .. p) or ""), (o and o.finished) and DONE or YELLOW)
      if Party then
        for k, l in ipairs(Party:Lines(e[1], j)) do
          if k > 4 then break end
          out[#out + 1] = { "    " .. l[1], l[2], l[3], l[4] }
        end
      end
    end
  end
  -- item -> quests it starts comes from the quest index (built in slices after login)
  if not QP.index and QP.EnsureIndex then QP:EnsureIndex() end
  local starts = QP.index and QP.index.itemStarts[itemID]
  for _, qid in ipairs(starts or {}) do
    local st, why = QP:GiverState(qid)
    if not NOT_FOR_YOU[why or ""] then
      n = n + 1
      if n > self.MAX_QUESTS then more = more + 1
      elseif why == "done" then add(("Starts a quest: %s  (done)"):format(name(qid)), GREY)
      elseif why == "in log" then add(("Starts a quest: %s  (in your log)"):format(name(qid)), GREY)
      elseif st == "soon" or why == "level" then
        local q = qd:GetQuest(qid)
        add(("Starts a quest: %s  (level %d)"):format(name(qid), q and q.reqLevel or 0), GREY)
      else add("Starts a quest: " .. name(qid), st and YELLOW or GREY) end
    end
  end
  if more > 0 then add(("+%d more"):format(more), GREY) end
  return out
end

function QT:OnItem(tt, itemID)
  if not self:Enabled() or type(itemID) ~= "number" then return 0 end
  local key, ck = self:Key(), "item:" .. itemID
  local c = self.cache[ck]
  local lines
  if c and c.key == key then lines = c.lines self.hits = (self.hits or 0) + 1
  else
    local ok, l = pcall(self.ItemLines, self, itemID)
    if not ok then Panoply:Debug("quest item tips", l) return 0 end
    lines = l
    if not c then
      if self.cacheN >= self.MAX_CACHE then self:Clear() end
      self.cacheN = self.cacheN + 1
    end
    if QP.index then self.cache[ck] = { key = key, lines = lines } end   -- not cached until the index is ready
    self.builds = (self.builds or 0) + 1
  end
  return self:Apply(tt, lines)
end

-- Item-started quests: the giver rules without the "has a giver" part.
function QP:GiverStateItem(qid)
  local st = self:GiverState(qid)
  return st == "give" or st == "low"
end

function QT:Key()
  local P = Panoply.QuestParty
  return QP.gen .. ":" .. (P and P.version or 0)
end

function QT:CachedLines(guid)
  local id, kind = QD().NpcIdFromGUID(guid)
  if not id then return nil end
  local key = self:Key()
  local c = self.cache[guid]
  if c and c.key == key then self.hits = (self.hits or 0) + 1 return c.lines end
  if self.cacheN >= self.MAX_CACHE then self:Clear() end
  local lines = self:LinesFor(id, kind)
  if not c then self.cacheN = self.cacheN + 1 end
  self.cache[guid] = { key = key, lines = lines }
  self.builds = (self.builds or 0) + 1
  return lines
end

function QT:Enabled()
  if not QP.active then return false end
  return Panoply.db and Panoply.db.qpTooltips ~= false and QD() and QD():Available()
end

function QT:Apply(tt, lines)
  if not (tt and tt.AddLine and lines and #lines > 0) then return 0 end
  for _, l in ipairs(lines) do tt:AddLine(l[1], l[2], l[3], l[4]) end
  if tt.Show then tt:Show() end
  return #lines
end

function QT:OnGUID(tt, guid)
  if not self:Enabled() then return 0 end
  guid = C.Readable(guid)
  if type(guid) ~= "string" then return 0 end
  local ok, lines = pcall(self.CachedLines, self, guid)
  if not ok then Panoply:Debug("quest tips", lines) return 0 end
  return self:Apply(tt, lines)
end

-- Names of objects that start quests (wanted posters, books...), from the quest index.
function QT:GiverObjNames()
  local idx = QP.index
  if not idx then return {} end
  if self.giverNames and self.giverNames.idx == idx then return self.giverNames.map end
  local map, qd = {}, QD()
  for id in pairs(idx.give.obj) do
    local n = qd:ObjectName(id)
    if n then local l = map[n:lower()] if not l then l = {} map[n:lower()] = l end l[#l + 1] = id end
  end
  self.giverNames = { idx = idx, map = map }
  return map
end

-- Classic Era: objects have no GUID in the tooltip, so match the tooltip's first line against
-- the names of objects that matter to quests in your log (and nothing else).
function QT:OnShowEra(tt)
  if not self:Enabled() or tt ~= _G.GameTooltip then return 0 end
  if tt.GetUnit then local _, unit = tt:GetUnit() if unit then return 0 end end
  if tt.GetItem then local _, link = tt:GetItem() if link then return 0 end end
  local left = _G.GameTooltipTextLeft1
  local text = left and left.GetText and C.Readable(left:GetText())
  if type(text) ~= "string" or text == "" then return 0 end
  local low = text:lower()
  local id, givers = self:LogIndex().objNames[low], self:GiverObjNames()[low]
  if not id and not givers then return 0 end
  local mark = text .. "|" .. self:Key()
  if tt.panoplyQuestMark == mark then return 0 end
  tt.panoplyQuestMark = mark
  local key = "GameObject-name-" .. low
  local c = self.cache[key]
  local lines
  if c and c.key == self:Key() then lines = c.lines
  else
    -- every object with this name (several posters can share one), each line once
    local ids, seenId, seen = {}, {}, {}
    if id then ids[1] = id seenId[id] = true end
    for _, g in ipairs(givers or {}) do if not seenId[g] then ids[#ids + 1] = g seenId[g] = true end end
    lines = {}
    for _, oid in ipairs(ids) do
      for _, l in ipairs(self:LinesFor(oid, "object")) do
        if not seen[l[1]] then seen[l[1]] = true lines[#lines + 1] = l end
      end
    end
    self.cache[key] = { key = self:Key(), lines = lines }
  end
  return self:Apply(tt, lines)
end

function QT:Install()
  if not self.itemHow then
    self.itemHow = C.HookItemTooltip(function(tt, id) QT:OnItem(tt, id) end) or "none"
  end
  if self.how then return self.how end
  local TDP = _G.TooltipDataProcessor
  local types = C.G and C.G("Enum.TooltipDataType")
  if TDP and TDP.AddTooltipPostCall and type(types) == "table" and types.Unit ~= nil then
    pcall(TDP.AddTooltipPostCall, types.Unit, function(tt, data) QT:OnGUID(tt, data and data.guid) end)
    if types.Object ~= nil then
      pcall(TDP.AddTooltipPostCall, types.Object, function(tt, data) QT:OnGUID(tt, data and data.guid) end)
      self.objects = "guid"
    end
    self.how = "TooltipDataProcessor"
    return self.how
  end
  local GT = _G.GameTooltip
  if GT and GT.HookScript then
    pcall(GT.HookScript, GT, "OnTooltipSetUnit", function(tt)
      local _, unit = tt:GetUnit()
      local guid = unit and _G.UnitGUID and _G.UnitGUID(unit)
      QT:OnGUID(tt, guid)
    end)
    pcall(GT.HookScript, GT, "OnShow", function(tt) QT:OnShowEra(tt) end)
    pcall(GT.HookScript, GT, "OnTooltipCleared", function(tt) tt.panoplyQuestMark = nil end)
    self.objects = "name"
    self.how = "OnTooltipSetUnit"
    return self.how
  end
  self.how = "none"
  return self.how
end

Panoply:Listen("QUESTPINS_INVALIDATED", function() QT:Clear() QT.logIdx = nil end)
-- Hooks go in once, at login (they only add lines while the module and the setting are on).
Panoply:On("PLAYER_LOGIN", function() QT:Install() end)

