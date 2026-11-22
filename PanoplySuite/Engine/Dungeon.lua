-- Panoply Suite dungeon helper: what the guide does while the player is inside a dungeon or raid. Own code.
--
-- The Dungeons window (Modules/Map/Instances.lua) tells this file when the player walks into an instance and when they leave
-- (its OnZone, on the loading screen every way in and out has). While inside:
--   * the bosses of the instance, in the usual clearing order of our own floor plan data (PanoplySuiteQuestData.MapData), and the
--     dungeon quests in the player's quest log become a short step list of its own,
--   * the guide window shows that list in front of the levelling route (Engine/Steps.lua: Engine.dungeon). The levelling route is
--     NOT replaced: it stays in the engine at its step, with its saved place untouched, and is the guide again the moment the
--     dungeon steps are done or the player leaves. Nothing is saved to come back to because nothing was taken away.
--   * nothing here has a spot the arrow could point at. The game gives no player position inside an instance, so the arrow is off
--     in there (UI/Arrow.lua) and no dungeon step carries a map point. The Dungeons window's "Point the arrow at the door" is the
--     way TO the entrance, as before.
-- An instance our floor plan data does not have (a WoW Forever dungeon, for one) has no bosses to list: the player's quests for it
-- are still listed, and the window says there is no floor plan yet.
--
-- When a boss counts as done (any one of these; none of them alone is relied on):
--   log        the combat log says it died (Classic Era)
--   xp         the "<boss> dies, you gain experience" chat line
--   unit       the player's target, or what they point at, is that boss, dead (also checked when a fight ends and at looting)
--   encounter  ENCOUNTER_END / BOSS_KILL (sent in raids; 5-player dungeons may never send them, so they are only one more signal)
--   quest      a quest in the log that needed that boss moved on during this run
--   player     the player ticked it (I've done it in the guide window, or a click on the boss in the Dungeons window)
-- Where none of them comes, the step waits for the player's tick; Skip moves on without one.
--
-- Which quests are "for this dungeon" (our own data only; Engine/QuestData.lua):
--   1. WoW Forever: the quest is in the dungeon's quest group (a quest-group table in PanoplySuite_QuestData, when one is loaded; none ships in this release),
--   2. an objective creature or object, a creature or object that drops an objective item, or who takes the quest, stands in this
--      instance (the data keeps such spawns as the instance's map number, with no spot),
--   3. the quest is filed under an instance area and that area is this instance: by the area's name as the game gives it, else by
--      which instance the other quests of that area lead into.
-- A quest gets a marker on the floor plan only where a boss we have a spot for is what it needs; every other quest is listed with
-- no marker, like a summoned boss. No coordinate is made up.
--
-- Saved per character: PanoplySuiteCharDB.dungeonRun = { inst =, done = { [boss number] = how }, skipped = { [step key] = true },
-- entered =, seen =, left = } so a /reload or a corpse run keeps the ticks. Coming back more than half an hour after leaving is a new run.
local ADDON, Panoply = ...
local C = Panoply.Compat

local D = {}
Panoply.Dungeon = D

D.SAME_RUN_S = 30 * 60     -- back inside within this long after leaving (or after the last tick of the clock inside) is the same run
D.KINDS = { party = true, raid = true, scenario = true }
D.MAX_DROPPERS = 30
D.MAX_ALONG = 3            -- quests with no boss of their own shown under each boss step
D.SOURCES = { log = true, xp = true, unit = true, encounter = true, quest = true, player = true }

local function wall() return (_G.time and _G.time()) or os.time() end
local function qd() return Panoply.QuestData end
local function quoted(name) return Panoply.Planner.Quoted(name) end

-- "The Deadmines" and "Deadmines" are one name; so are names that differ in case or punctuation
local function norm(s)
  s = tostring(s or ""):lower():gsub("^the%s+", "")
  return (s:gsub("[^%w]", ""))
end
D.Norm = norm

-------------------------------------------------------------------------------
-- Which instance a quest belongs to (our own data)
-------------------------------------------------------------------------------
local function addSpawns(set, rec)
  local spawns = rec and rec.spawns
  if type(spawns) ~= "table" then return end
  for k in pairs(spawns) do if type(k) == "number" and k < 0 then set[-k] = true end end
end

-- The creature ids a quest needs dead or looted: { [npcId] = "kill" | "item" }, and for an item whether every creature that drops it is listed
local function questNpcs(q)
  local QD = qd()
  local out, order = {}, {}
  local function add(id, how) if type(id) == "number" and not out[id] then out[id] = how order[#order + 1] = id end end
  local o = q.objectives or {}
  for _, c in ipairs(o.creatures or {}) do add(c[1], "kill") end
  for _, kc in ipairs(o.killCredit or {}) do for _, id in ipairs(kc[1] or {}) do add(id, "kill") end end
  local items = {}
  for _, it in ipairs(o.items or {}) do
    local npcs, objs = QD:ItemDroppers(it[1])
    local list = {}
    for i, id in ipairs(npcs or {}) do if i > D.MAX_DROPPERS then break end add(id, "item") list[#list + 1] = id end
    items[#items + 1] = { npcs = list, objects = objs or {} }
  end
  return out, order, items
end

-- The instances a quest's creatures and objects stand in: a set of instance map numbers. Cached per quest.
function D:QuestInstances(q)
  self.instCache = self.instCache or {}
  local c = self.instCache[q.id]
  if c then return c end
  local QD = qd()
  local own = QD and QD.own
  local set = {}
  if own and own.Npc and own.Object then
    local _, order, items = questNpcs(q)
    for _, id in ipairs(order) do addSpawns(set, own.Npc(id)) end
    local o = q.objectives or {}
    for _, ob in ipairs(o.objects or {}) do addSpawns(set, own.Object(ob[1])) end
    for _, it in ipairs(items) do
      for i, id in ipairs(it.objects) do if i > D.MAX_DROPPERS then break end addSpawns(set, own.Object(id)) end
    end
    for _, id in ipairs(q.ends and q.ends.npc or {}) do addSpawns(set, own.Npc(id)) end
    for _, id in ipairs(q.ends and q.ends.obj or {}) do addSpawns(set, own.Object(id)) end
    if next(set) == nil then
      for _, id in ipairs(q.starts and q.starts.npc or {}) do addSpawns(set, own.Npc(id)) end
      for _, id in ipairs(q.starts and q.starts.obj or {}) do addSpawns(set, own.Object(id)) end
    end
  end
  self.instCache[q.id] = set
  return set
end

-- The instance an instance area is: the one that most of that area's quests lead into (only quests that lead into exactly one
-- instance vote, and the winner needs more than half of those votes). Nil when the data cannot say. Cached; the scan runs once.
function D:AreaInstance(area)
  local QD = qd()
  if not (QD and QD.Available and QD:Available() and QD.own and QD.EachQuestId) then return nil end
  if not self.areaInst or self.areaInstFor ~= QD.own then
    local votes = {}
    local raw = QD.own.Quest
    for id in QD:EachQuestId() do
      -- the raw record says the area; only a quest of an instance area is built, and what this scan built is not kept
      local r = raw and raw(id)
      local area = r and tonumber(r.zoneOrSort) or 0
      if area > 0 and QD:IsInstanceArea(area) then
        local had = QD.cache[id] ~= nil
        local q = QD:GetQuest(id)
        if q then
          local set = self:QuestInstances(q)
          local one = next(set)
          if one and next(set, one) == nil then
            votes[area] = votes[area] or {}
            votes[area][one] = (votes[area][one] or 0) + 1
          end
        end
        if not had then QD.cache[id] = nil end
      end
    end
    local map = {}
    for a, v in pairs(votes) do
      local total, best, bestN = 0, nil, 0
      for inst, n in pairs(v) do
        total = total + n
        if n > bestN or (n == bestN and best and inst < best) then best, bestN = inst, n end
      end
      if best and bestN * 2 > total then map[a] = best end
    end
    self.areaInst, self.areaInstFor = map, QD.own
  end
  return self.areaInst[area]
end

-- the quests of this instance's quest groups, as a set (empty when no quest-group table is loaded, which is every release now)
local function groupSet(id)
  local set = {}
  local QD = qd()
  local F = QD and QD.own and QD.own.Facts
  if not (F and F.Dungeons and F.QuestGroup) then return set end
  local ok, list = pcall(F.Dungeons)
  if not ok or type(list) ~= "table" then return set end
  for _, d in ipairs(list) do
    if d.instanceId == id and d.questGroup then
      local okG, g = pcall(F.QuestGroup, d.questGroup)
      if okG and type(g) == "table" then
        for _, side in pairs(g) do
          for _, key in ipairs({ "accept", "turnin" }) do
            for _, q in ipairs(type(side) == "table" and side[key] or {}) do set[q] = true end
          end
        end
      end
    end
  end
  return set
end

-- Is this quest for the instance of this run?
function D:Belongs(questID, run)
  run = run or self.run
  if not run or type(questID) ~= "number" then return false end
  local c = run.belongs[questID]
  if c ~= nil then return c end
  local QD = qd()
  local yes = false
  if not run.groups then run.groups = groupSet(run.id) end
  if run.groups[questID] then
    yes = true
  elseif QD and QD.Available and QD:Available() then
    local q = QD:GetQuest(questID)
    if q then
      local set = self:QuestInstances(q)
      if next(set) ~= nil then
        yes = set[run.id] == true
      elseif (q.zone or 0) > 0 and QD:IsInstanceArea(q.zone) then
        -- the area's own name first; a name that is another floor plan's says no; else what the area's other quests lead into
        local an = C.AreaName(q.zone)
        local other = an and self.names and self.names[norm(an)]
        if an and (norm(an) == norm(run.name) or (run.gameName and norm(an) == norm(run.gameName))) then yes = true
        elseif other then yes = other == run.id
        else yes = self:AreaInstance(q.zone) == run.id end
      end
    end
  else
    return false   -- the quest data is not loaded yet: ask again later, remember nothing
  end
  run.belongs[questID] = yes
  return yes
end

-------------------------------------------------------------------------------
-- The run
-------------------------------------------------------------------------------
local function savedRun(id, fresh)
  local cdb = Panoply.cdb
  if not cdb then return { inst = id, done = {}, skipped = {} }, true end
  local s = cdb.dungeonRun
  local now = wall()
  local same = type(s) == "table" and s.inst == id and type(s.done) == "table" and not fresh
    and (now - (tonumber(s.left) or tonumber(s.seen) or 0)) < D.SAME_RUN_S
  if not same then
    s = { inst = id, done = {}, skipped = {}, entered = now }
    cdb.dungeonRun = s
  end
  if type(s.skipped) ~= "table" then s.skipped = {} end
  s.left, s.seen = nil, now
  return s, not same
end

-- D.names (set by the Dungeons window): { [norm(floor plan name)] = instance number }, so an area named like another floor plan
-- is never taken for this one.
-- Called by the Dungeons window when the player is inside an instance. `bosses` is the floor plan's boss list
-- ({ n, name, level, placed, wing }, in clearing order) or nil when our data has no floor plan for this instance.
function D:Enter(id, name, bosses, gameName)
  if type(id) ~= "number" then return false end
  local run = self.run
  if run and run.id == id then
    if bosses and not run.plan then run.plan, run.bosses = true, bosses self:IndexBosses(run) self:Refresh(true) end
    return true
  end
  if run then self:Leave() end
  local saved, new = savedRun(id)
  run = { id = id, name = name or gameName or "This instance", gameName = gameName, plan = bosses ~= nil, bosses = bosses or {},
          saved = saved, belongs = {}, ties = {}, quests = {}, steps = {}, index = 1 }
  self:IndexBosses(run)
  self.run = run
  C.WatchDeaths(function(n, guid, source) D:OnDeath(n, guid, source) end)
  if new then
    if run.plan then
      Panoply:Print(Panoply:PlayAlong() and ("%s: the floor plan and the boss order are in the Dungeons window (/psmap)."):format(run.name)
        or ("%s: the floor plan and the boss order are in the Dungeons window (/psmap). The guide window lists the bosses and your quests for this dungeon."):format(run.name))
    else
      Panoply:Print(Panoply:PlayAlong() and ("%s has no floor plan yet."):format(run.name)
        or ("%s has no floor plan yet. The guide window still lists your quests for it."):format(run.name))
    end
  end
  self:Refresh(true)
  self:Settle("enter")
  Panoply:Fire("DUNGEON_CHANGED")
  return true
end

function D:IndexBosses(run)
  run.bossByName = {}
  for _, b in ipairs(run.bosses) do
    local k = norm(b.name)
    if k ~= "" and not run.bossByName[k] then run.bossByName[k] = b.n end
  end
end

-- Called by the Dungeons window when the player is not inside an instance (any more).
function D:Leave()
  local run = self.run
  if not run then return false end
  run.saved.left = wall()
  C.WatchDeaths(nil)
  self.run = nil
  local E = Panoply.Engine
  if E.dungeon then
    E.dungeon = nil
    if E.steps[E.index] and not Panoply:PlayAlong() then
      Panoply:Print(("You left %s. Your leveling guide is back where you left it."):format(run.name))
    end
    Panoply:Fire("STEP_CHANGED", E.index, "dungeon")
    E:Check()   -- the route catches up with anything finished meanwhile
  end
  Panoply:Fire("DUNGEON_CHANGED")
  return true
end

function D:Inside() return self.run ~= nil end

-------------------------------------------------------------------------------
-- Bosses
-------------------------------------------------------------------------------
function D:BossDone(n)
  local run = self.run
  return run ~= nil and n ~= nil and run.saved.done[n] ~= nil
end

-- Tick a boss cleared or not. `source` is one of D.SOURCES.
function D:SetBoss(n, done, source)
  local run = self.run
  if not (run and run.plan and run.bosses[n]) then return false end
  local was = run.saved.done[n] ~= nil
  if done then
    if not was then run.saved.done[n] = D.SOURCES[source] and source or "player" end
  else
    run.saved.done[n] = nil
    run.saved.skipped["b" .. n] = nil
  end
  if was ~= (done and true or false) then
    Panoply:Debug("dungeon boss", run.bosses[n].name, done and (source or "player") or "unticked")
    Panoply:Fire("DUNGEON_CHANGED")
    if not self.ticking then Panoply.Engine:Check() end
  end
  return true
end

function D:ToggleBoss(n) return self:SetBoss(n, not self:BossDone(n), "player") end

-- The boss to go for now: the guide's current boss step, else the first one not ticked. Nil when all are.
function D:NextBoss()
  local run = self.run
  if not (run and run.plan) then return nil end
  local cur = Panoply.Engine.dungeon
  if cur and cur.boss and not self:BossDone(cur.boss) then return cur.boss end
  for _, b in ipairs(run.bosses) do if not run.saved.done[b.n] then return b.n end end
  return nil
end

-- A creature died (Core/Compat.lua WatchDeaths): a boss of this floor plan, by its name or by its creature number.
function D:OnDeath(name, guid, source)
  local run = self.run
  if not (run and run.plan) then return false end
  local n = name and run.bossByName[norm(name)]
  if not n and guid then
    local QD = qd()
    local id = QD and QD.NpcIdFromGUID and QD.NpcIdFromGUID(guid)
    local known = id and QD.NpcName and QD:NpcName(id)
    n = known and run.bossByName[norm(known)] or nil
  end
  if not n or run.saved.done[n] then return false end
  return self:SetBoss(n, true, source)
end

-- A quest that needed a boss moved on during this run (the quest became ready, or its line for that boss was ticked by the game):
-- that boss is done. What was already so when the run started says nothing about this run and is not counted.
function D:QuestEvidence()
  local run = self.run
  if not (run and run.plan) then return end
  local S = Panoply.State
  for _, tie in ipairs(run.ties) do
    local e = S.log[tie.quest]
    local ok = false
    if S.completed[tie.quest] or (e and e.isComplete) then
      ok = true
    elseif e then
      local want = (run.bosses[tie.boss].name or ""):lower()
      for _, o in ipairs(S:Objectives(tie.quest)) do
        if o.finished and type(o.text) == "string" and want ~= "" and o.text:lower():find(want, 1, true) then ok = true break end
      end
    end
    local key = tie.quest .. ":" .. tie.boss
    run.tieSeen = run.tieSeen or {}
    if run.tieSeen[key] == nil then
      run.tieSeen[key] = ok
    elseif ok and not run.tieSeen[key] then
      run.tieSeen[key] = true
      if not run.saved.done[tie.boss] then self:SetBoss(tie.boss, true, "quest") end
    end
  end
end

-------------------------------------------------------------------------------
-- The player's quests for this instance
-------------------------------------------------------------------------------
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- The bosses of this floor plan a quest needs: a kill objective on the boss, or an item that only bosses of this floor plan drop.
local function questBosses(run, q)
  local QD = qd()
  local list, seen = {}, {}
  local function boss(id)
    local name = QD:NpcName(id)
    return name and run.bossByName[norm(name)] or nil
  end
  local how, order, items = questNpcs(q)
  for _, id in ipairs(order) do
    if how[id] == "kill" then
      local n = boss(id)
      if n and not seen[n] then seen[n] = true list[#list + 1] = n end
    end
  end
  for _, it in ipairs(items) do
    if #it.npcs > 0 and #it.objects == 0 then
      local all, found = true, {}
      for _, id in ipairs(it.npcs) do
        local n = boss(id)
        if n then found[#found + 1] = n else all = false end
      end
      if all then for _, n in ipairs(found) do if not seen[n] then seen[n] = true list[#list + 1] = n end end end
    end
  end
  table.sort(list)
  return list
end

-- Who takes the quest, when they only stand inside this instance: their name, else nil.
local function finisherInside(run, q)
  local QD = qd()
  local own = QD.own
  if not (own and own.Npc and q.ends) then return nil end
  for _, id in ipairs(q.ends.npc or {}) do
    local set = {}
    addSpawns(set, own.Npc(id))
    if set[run.id] and QD:NpcOnlyInInstance(id) then return QD:NpcName(id) or "the quest's taker" end
  end
  for _, id in ipairs(q.ends.obj or {}) do
    local set = {}
    addSpawns(set, own.Object(id))
    if set[run.id] and QD:ObjectOnlyInInstance(id) then return QD:ObjectName(id) or "the quest's taker" end
  end
  return nil
end

-- The quests in the log that are for this instance, in a steady order: { id, name, letter, bosses = {n...}, mark = n or nil,
-- inside = finisher's name or nil, known = our data has the quest }.
function D:HeldQuests()
  local run = self.run
  local out = {}
  if not run or Panoply:PlayAlong() then return out end   -- playing along: no quest marks and no quest lines of ours
  local S, QD = Panoply.State, qd()
  local ids = {}
  for id in pairs(S.log or {}) do if type(id) == "number" then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    if self:Belongs(id, run) then
      local q = QD and QD.Available and QD:Available() and QD:GetQuest(id) or nil
      local e = S.log[id]
      local rec = { id = id, name = (q and q.name) or (e and e.title) or "a quest in your log", bosses = {}, known = q ~= nil }
      if q then
        local okB, list = pcall(questBosses, run, q)
        if okB then rec.bosses = list end
        local okF, who = pcall(finisherInside, run, q)
        if okF then rec.inside = who end
        local text = Panoply.Planner.ObjectiveText and Panoply.Planner.ObjectiveText(q)
        if type(text) == "string" and text ~= "" then rec.text = text end
      end
      for _, n in ipairs(rec.bosses) do if run.bosses[n] and run.bosses[n].placed then rec.mark = n break end end
      rec.letter = LETTERS:sub(#out + 1, #out + 1)
      if rec.letter == "" then rec.letter = "+" end
      out[#out + 1] = rec
    end
  end
  return out
end

-- Is a held quest ready to hand in (or handed in)?
function D:QuestReady(id)
  local S = Panoply.State
  local e = S.log[id]
  return S.completed[id] == true or (e ~= nil and e.isComplete and true or false)
end

-------------------------------------------------------------------------------
-- The step list
-------------------------------------------------------------------------------
local function questGoal(rec, optional)
  return { type = "complete", questID = rec.id, forceRoute = true, optional = optional or nil,
           text = rec.text or ("Finish " .. quoted(rec.name)) }
end

function D:Build()
  local run = self.run
  local steps, ties = {}, {}
  local quests = run.quests
  local byBoss, along = {}, {}
  for _, rec in ipairs(quests) do
    if #rec.bosses == 0 then
      along[#along + 1] = rec
    else
      for _, n in ipairs(rec.bosses) do
        byBoss[n] = byBoss[n] or {}
        byBoss[n][#byBoss[n] + 1] = rec
        ties[#ties + 1] = { quest = rec.id, boss = n }
      end
    end
  end
  local total = #run.bosses
  for _, b in ipairs(run.bosses) do
    local why
    if b.placed then why = ("Boss %d of %d. Number %d on the floor plan in the Dungeons window."):format(b.n, total, b.n)
    else why = ("Boss %d of %d. This boss is summoned, so it has no marker on the floor plan."):format(b.n, total) end
    if b.wing and b.wing ~= "" then why = why .. " Wing: " .. b.wing .. "." end
    local step = { isDungeon = true, key = "b" .. b.n, kind = "kill", boss = b.n, title = "Defeat " .. b.name, why = why, zone = run.name,
                   goals = { { type = "boss", boss = b.n, text = ("Defeat %s (level %d)"):format(b.name, b.level) } } }
    for _, rec in ipairs(byBoss[b.n] or {}) do step.goals[#step.goals + 1] = questGoal(rec, true) end
    for i, rec in ipairs(along) do
      if i > D.MAX_ALONG then break end
      step.goals[#step.goals + 1] = questGoal(rec, true)
    end
    steps[#steps + 1] = step
  end
  for _, rec in ipairs(quests) do
    local where
    if not run.plan then where = "This quest is for this dungeon, which has no floor plan yet."
    elseif rec.mark then where = ("This quest is for this dungeon. It is marked %s at boss %d on the floor plan."):format(rec.letter, rec.mark)
    else where = "This quest is for this dungeon. It is listed in the Dungeons window with no marker." end
    steps[#steps + 1] = { isDungeon = true, key = "q" .. rec.id, kind = "do", questID = rec.id, questName = rec.name, zone = run.name,
                          title = "Finish " .. quoted(rec.name), why = where, goals = { questGoal(rec) } }
  end
  for _, rec in ipairs(quests) do
    if rec.inside then
      steps[#steps + 1] = { isDungeon = true, key = "t" .. rec.id, kind = "talk", zone = run.name, who = rec.inside,
                            title = ("Hand in %s to %s, inside the dungeon"):format(quoted(rec.name), rec.inside),
                            accepts = {}, turnins = { rec.name },
                            goals = { { type = "turnin", questID = rec.id, forceRoute = true, text = "Hand in " .. quoted(rec.name) } } }
    end
  end
  run.steps, run.ties = steps, ties
end

-- Look at the quest log again; rebuild the steps when the quests for this instance changed. Returns whether it rebuilt.
function D:Refresh(force)
  local run = self.run
  if not run then return false end
  local QD = qd()
  local quests = self:HeldQuests()
  local parts = { (QD and QD.Available and QD:Available()) and "d" or "-", Panoply:PlayAlong() and "p" or "-", run.plan and "f" or "-" }
  for _, rec in ipairs(quests) do parts[#parts + 1] = rec.id .. (rec.known and "k" or "") end
  local sig = table.concat(parts, ",")
  local ready = {}
  for _, rec in ipairs(quests) do ready[#ready + 1] = self:QuestReady(rec.id) and "1" or "0" end
  local rsig = table.concat(ready)
  if sig == run.sig and not force then
    if rsig ~= run.rsig then run.rsig = rsig Panoply:Fire("DUNGEON_CHANGED") end
    return false
  end
  run.sig, run.rsig, run.quests = sig, rsig, quests
  self:Build()
  if not force then Panoply:Fire("DUNGEON_CHANGED") end
  return true
end

local function passable(run, i)
  local step = run.steps[i]
  if not step then return true, false end
  local done = Panoply.Goals.StepComplete(step, Panoply.State)
  return done or run.saved.skipped[step.key] == true, done
end

-- Put the first step that is still open in front of the guide; none left (or playing along): the levelling route is the guide again.
function D:Settle(how)
  local run, E = self.run, Panoply.Engine
  if not run then return end
  local was = E.dungeon
  local wasDone = false
  if was then wasDone = Panoply.Goals.StepComplete(was, Panoply.State) end
  local at
  if not Panoply:PlayAlong() then
    for i = 1, #run.steps do if not passable(run, i) then at = i break end end
  end
  if at then
    run.index = at
    local step = run.steps[at]
    if was and was ~= step and was.key == step.key then
      E.dungeon = step   -- the same step, built again
      E:Updated()   -- 0.9.5 phase 4A4: built again on every check; told only when it reads differently
    elseif was ~= step then
      E.dungeon = step
      run.shown = true
      if was and wasDone and how == "auto" then
        Panoply:Fire("STEP_DONE", "dungeon", was)
        if Panoply.db and Panoply.db.soundOnStep and _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
          pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
        end
        if Panoply.Toast and Panoply.StepText then pcall(Panoply.Toast.Show, Panoply.Toast, "Step complete!", Panoply.StepText.Toast(step)) end
      end
      Panoply:Fire("STEP_CHANGED", E.index, "dungeon")
    else
      E:Updated()
    end
  elseif was then
    E.dungeon = nil
    if run.shown then
      run.shown = false
      if wasDone and how == "auto" then Panoply:Fire("STEP_DONE", "dungeon", was) end
      if not Panoply:PlayAlong() then
        Panoply:Print(E.steps[E.index] and ("The dungeon steps for %s are done. Your leveling guide is back where you left it."):format(run.name)
          or ("The dungeon steps for %s are done."):format(run.name))
      end
    end
    Panoply:Fire("STEP_CHANGED", E.index, "dungeon")
  end
end

-- Called by the engine's check (events and the 1 s ticker). Returns true while a dungeon step is the guide's step,
-- so the levelling route waits where it is.
function D:Tick()
  local run = self.run
  if not run then return false end
  run.saved.seen = wall()
  self.ticking = true
  local ok, err = pcall(function()
    self:QuestEvidence()
    self:Refresh()
    self:Settle("auto")
  end)
  self.ticking = nil
  if not ok then Panoply:Debug("dungeon tick", err) end
  return Panoply.Engine.dungeon ~= nil
end

-- The guide window's buttons on a dungeon step
function D:Skip()
  local run, step = self.run, Panoply.Engine.dungeon
  if not (run and step) then return false end
  run.saved.skipped[step.key] = true
  self:Settle("manual")
  Panoply:Fire("DUNGEON_CHANGED")
  return true
end

function D:CanBack()
  local run = self.run
  return run ~= nil and Panoply.Engine.dungeon ~= nil and (run.index or 1) > 1
end

-- Back: the step before comes up again. A skipped step is no longer skipped; a ticked boss is unticked (how a wrong tick is taken back).
function D:Back()
  local run = self.run
  if not self:CanBack() then return false end
  local step = run.steps[run.index - 1]
  run.saved.skipped[step.key] = nil
  if step.boss and run.saved.done[step.boss] then run.saved.done[step.boss] = nil end
  self:Settle("manual")
  Panoply:Fire("DUNGEON_CHANGED")
  return true
end

-- I've done it: the player's own tick for a boss
function D:Confirm(step)
  if not (self.run and step and step.boss) then return false end
  return self:SetBoss(step.boss, true, "player")
end

function D:StepNumber()
  local run = self.run
  if not run then return 0, 0 end
  return run.index or 1, #run.steps
end

-- The next open steps after the current one (for the guide window's Up next)
function D:Upcoming(n)
  local run, out = self.run, {}
  if not run then return out end
  for i = (run.index or 1) + 1, #run.steps do
    if #out >= n then break end
    if not passable(run, i) then out[#out + 1] = run.steps[i] end
  end
  return out
end

-- What the Dungeons window draws (plain data; the tests read it too): nil when not inside.
function D:View()
  local run = self.run
  if not run then return nil end
  local v = { id = run.id, name = run.name, plan = run.plan, next = self:NextBoss(), done = {}, quests = {}, steps = #run.steps,
              guiding = Panoply.Engine.dungeon ~= nil }
  for n, how in pairs(run.saved.done) do v.done[n] = how end
  for _, rec in ipairs(run.quests) do
    v.quests[#v.quests + 1] = { id = rec.id, name = rec.name, letter = rec.letter, mark = rec.mark, bosses = rec.bosses,
                                ready = self:QuestReady(rec.id), inside = rec.inside }
  end
  return v
end
