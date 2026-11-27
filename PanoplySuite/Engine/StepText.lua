-- Panoply Suite step text: turns the current step into plain English for the guide window.
-- Headline (verb + target + place), a "why it matters" line, live progress lines ("3/8 Kobold
-- Vermin"), distance, and friendly hints when idle, waiting or missing quest data. Never raw ids.
local ADDON, Panoply = ...
local ST = {}
Panoply.StepText = ST
local C = Panoply.Compat

local function q(name) return Panoply.Planner.Quoted(name or "this quest") end
local function list(names)
  if not names or #names == 0 then return nil end
  local out = {}
  for i, n in ipairs(names) do out[i] = q(n) end
  if #out == 1 then return out[1] end
  return table.concat(out, ", ", 1, #out - 1) .. " and " .. out[#out]
end

-- Remove anything that looks like an internal id from text we did not write ourselves.
function ST.Clean(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%s*%(%s*[Ii][Dd]%s*:?%s*%d+%s*%)", ""):gsub("%s*#%d+", "")
  return s
end

-- Detector used by tests and the self-test: raw ids or programmer jargon in player-facing text.
local JARGON = { "NPC %d", "[Nn]pc id", "[Oo]bject id", "[Ii]tem id", "[Qq]uest #", "#%d", "questID", "mapID", "nil", "%(generated%)" }
function ST.HasJargon(s)
  if type(s) ~= "string" then return false end
  for _, pat in ipairs(JARGON) do if s:find(pat) then return pat end end
  -- bare numbers of 4+ digits (ids) are jargon unless they are XP, gold or yards
  for num, after in s:gmatch("(%d%d%d%d+)(%s*%a*)") do
    if not after:find("XP") and not after:find("yd") and not after:find("[gsc]") then return "number " .. num end
  end
  return false
end

-- After 0.8.2: a goal's text, asking again for a quest name that was unknown when the guide step was built
-- ("quest 92840" until the client or our data learns the title). Goals of Engine/Guides.lua carry retext for this.
function ST.GoalText(g)
  -- Nov 11 zone audit: an item our data has no name for ("Collect the item for ..."), named by the client once it knows the item
  if type(g.itemRetext) == "function" then
    local ok, t = pcall(g.itemRetext)
    if ok and type(t) == "string" then g.text = t g.itemRetext, g.retext = nil, nil end
  end
  if type(g.retext) == "function" then
    local G = Panoply.Guides
    local n = G and G.QuestNameKnown and G.QuestNameKnown(g.retextQuest or g.questID)
    if n then
      local ok, t = pcall(g.retext, n)
      if ok and type(t) == "string" then g.text = t g.retext = nil end
    end
  end
  return g.text
end

-- The headline of a written-guide step with several goals follows the work: the first goal still open (and plain English),
-- not the title the step was written under, which still said "kill" after the kills were done. A profession step, a step with
-- one goal, and a step with nothing readable left keep their own title.
function ST.Headline(step)
  if not step then return "" end
  if step.fromGuide and not step.isProf and step.goals and #step.goals > 1 then
    for _, g in ipairs(step.goals) do
      if g.status ~= "done" and g.status ~= "hidden" and not g.hint and not g.optional then
        local t = ST.Clean(ST.GoalText(g))
        if t ~= "" and not ST.HasJargon(t) then return t end
      end
    end
  end
  return ST.Clean(step.title or "Next step")
end

-- Nov 13 2026 (approved): the goal to do now has no place in any of our data (our quest data, the written guide) and the game gives no waypoint for it either (Engine:Target finds nothing), so the arrow points nowhere. The step says so,
-- so an arrow that is gone is not taken for a fault. nil when the arrow has somewhere to point, or no open goal is at a place.
ST.NO_SPOT = "No map spot for this one."
local PLACED = { accept = true, turnin = true, objective = true, complete = true }
function ST.NoSpotNote(step)
  if not step or step.isDungeon or not step.goals or Panoply:PlayAlong() then return nil end
  local open = false
  for _, g in ipairs(step.goals) do
    -- an optional goal counts too (an optional pick-up from an item): the line shows only when the arrow points nowhere at all
    if PLACED[g.type] and not g.mapID and not g.hint and g.status ~= "done" and g.status ~= "hidden" then open = true break end
  end
  if not open then return nil end
  local E = Panoply.Engine
  if E and E.Target and E:Target(step) then return nil end
  return ST.NO_SPOT
end

-- Plain location note for the step's NPC / object ("Inside the Lion's Pride Inn, upstairs"), else the no-map-spot note, or nil.
function ST.LocationNote(step)
  local L = Panoply.Locations
  local s = L and step and L:NoteForStep(step)
  if type(s) ~= "string" or s == "" then return ST.NoSpotNote(step) end
  return ST.Clean(s)
end

function ST.Why(step)
  if not step then return "" end
  if step.why then return ST.Clean(step.why) end
  local k = step.kind
  if k == "talk" then
    local acc, tin = list(step.accepts), list(step.turnins)
    if tin and acc then return "Hand in " .. tin .. " for experience, then pick up " .. acc .. "." end
    if tin then return "Handing in " .. tin .. " gives experience and a reward." end
    if acc then return "Picks up " .. acc .. ", the next part of your route." end
    return "Next stop on your route."
  elseif k == "do" then
    return "Finishing " .. q(step.questName) .. " lets you hand it in for experience."
  elseif k == "grind" then
    return "A little extra experience unlocks the next quests on your route."
  elseif k == "train" then
    return "Training raises your skill cap so you can keep levelling this profession."
  elseif k == "skill" then
    return "Each recipe or node here still gives skill-ups at your level."
  end
  return ""
end

-- Live progress lines for the current step: { {text=, done=bool}, ... }
function ST.Progress(step)
  local out = {}
  if not step then return out end
  local S = Panoply.State
  for _, g in ipairs(step.goals or {}) do
    if g.status ~= "hidden" and not (g.hint and #step.goals > 1 and not (step.isProf and g.text)) then
      if g.ps and g.type ~= "complete" then
        -- PanoplyGuide's goal: its own words and its own state (a "complete" goal still lists the game's objective lines, below)
        out[#out + 1] = { text = ST.Clean(g.text), done = g.status == "done" }
      elseif g.type == "complete" and g.questID and S:InLog(g.questID) then
        local objs = S:Objectives(g.questID)
        local any = false
        for _, o in ipairs(objs) do
          if o.text and o.text ~= "" then
            any = true
            out[#out + 1] = { text = ST.Clean(o.text), done = o.finished and true or false }
          end
        end
        if not any then out[#out + 1] = { text = ST.Clean(ST.GoalText(g)), done = g.status == "done" } end
      elseif g.type == "objective" and g.questID and S:InLog(g.questID) then
        -- one goal stays one line: the game's own text for ITS objective, else the goal's text (never every objective of the quest)
        -- Nov 12 2026: a goal with no objective number (PanoplyGuide named its item or creature) shows the game's line that names
        -- it, ticked by its own state (Engine/Steps.lua), never objective 1's line
        local o
        if g.objIndex then o = S:Objectives(g.questID)[g.objIndex]
        else
          o = Panoply.Goals.ObjectiveNamed(S, g.questID, g.partName)
          if not o then local all = S:Objectives(g.questID) if #all == 1 then o = all[1] end end
        end
        local t = o and type(o.text) == "string" and ST.Clean(o.text) or ""
        if t == "" or ST.HasJargon(t) then t = ST.Clean(ST.GoalText(g)) end
        out[#out + 1] = { text = t, done = (g.objIndex and o and o.finished and true) or g.status == "done" }
      elseif g.type == "level" then
        local need = g.level or 0
        local lvl = S.level or 1
        local pct = (S.xpMax or 0) > 0 and math.floor((S.xp or 0) / S.xpMax * 100) or 0
        out[#out + 1] = { text = lvl >= need and ("Level " .. need .. " reached") or ("Level %d (%d%%) of %d"):format(lvl, pct, need), done = lvl >= need }
      else
        out[#out + 1] = { text = ST.Clean(ST.GoalText(g)), done = g.status == "done" }
      end
    end
  end
  return out
end

function ST.Distance(yards, otherZone)
  if otherZone then return "In " .. otherZone end
  if not yards then return "" end
  if yards < 10 then return "You are here" end
  return ("%d yd away"):format(math.floor(yards + 0.5))
end

function ST.Waiting(partner)
  return ("Waiting for %s to finish this step too. You'll move on together."):format(partner or "your partner")
end

function ST.Toast(nextStep)
  if not nextStep then return "Done! That's the end of this plan." end
  return "Done! Next: " .. ST.Headline(nextStep)
end

-- What to do when there is nothing to follow right now.
function ST.WhatNow()
  local QD = Panoply.QuestData
  local E = Panoply.Engine
  -- WoW Forever with PanoplyGuide's engine: no step means no guide here, or a finished guide
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return Panoply.PanoplyGuideEngine:IdleText() end
  -- 0.9.7 (Nov 18 2026): the guide engine cannot run and nothing takes its place: one plain line (Core/Init.lua)
  if Panoply.GuideUnavailable and Panoply:GuideUnavailable() then return Panoply.GUIDE_UNAVAILABLE_TITLE, Panoply.GUIDE_UNAVAILABLE_LINE end
  -- 0.7.4.1: an area without a guide (Engine/NoGuide.lua): say so, in the tracker line's words
  if Panoply.NoGuide and Panoply:NoGuideHere() and #E.steps == 0 then
    return Panoply.NoGuide:Text(), "Panoply Suite plans no route here and points nowhere. The quest tracker has the Record mode and Turn guide off here switches (or type /panoply noguide). The guide comes back by itself in the first zone it has quests for."
  end
  -- Nov 11 2026: no written guide has a step for this character here, and there is no planner to fill in (Engine/Guides.lua NoStep)
  if Panoply.Guides and Panoply.Guides.NoStepShown and Panoply.Guides:NoStepShown() then
    return Panoply.Guides.NOSTEP_TITLE, Panoply.Guides.NOSTEP_LINE
  end
  if not QD:Available() then
    return "What now?", "Turn on Panoply Suite Quest Data (it comes with Panoply Suite) so Panoply Suite can plan your route. Until then it follows the quests already in your log."
  end
  if Panoply.cdb and not Panoply.cdb.setupDone then
    return "What now?", "Run the quick setup so Panoply Suite knows how you like to play. Click Setup below."
  end
  if #E.steps == 0 then
    return "What now?", "Click Build my route and Panoply Suite will plan the next few levels from where you stand."
  end
  return "What now?", "Plan complete! Click Build my route to plan the next stretch of levels."
end

-- forever-data (Forever launch): a new Forever zone has no quests in our data yet. When you stand in one and the guide has no
-- step here (no step, or the current step is on another map), the step card says so instead of staying blank.
ST.NEW_ZONE_TEXT = "New Forever zone, guide coming soon"

local function stepMaps(step)
  local maps = {}
  for _, g in ipairs(step and step.goals or {}) do
    if g.mapID and g.status ~= "done" and g.status ~= "hidden" then maps[g.mapID] = true end
  end
  if step and step.mapID then maps[step.mapID] = true end
  return maps
end

-- 0.8.1: a step of a written guide (Engine/Guides.lua) covers the player's zone when the step's zone, or its guide's zone, is the zone
-- the player stands in, or the player's map is one of that guide's primary maps. Written steps carry no map of their own when the
-- quest is not in our data (Forever's 924xx quests), so stepMaps alone would call a guided Zephras Isle "guide coming soon".
local function stepCoversHere(step, pos, zone)
  if not step then return false end
  if zone and step.zone and step.zone == zone then return true end
  local G = Panoply.Guides
  local guide = G and step.guideID and G.guides and G.guides[step.guideID]
  if not guide then return false end
  if zone and guide.zone and guide.zone == zone then return true end
  return pos ~= nil and pos.map ~= nil and G:PrimaryMaps(guide)[pos.map] == true
end

function ST.NewZoneNote(step)
  if Panoply.PlayAlong and Panoply:PlayAlong() then return nil end        -- play-along mode: the guide is off, so is this
  if step and step.isDungeon then return nil end                 -- a dungeon step (Engine/Dungeon.lua) is the guide for where you are
  if Panoply.PanoplyGuideEngine and Panoply.PanoplyGuideEngine:Active() then return nil end   -- PanoplyGuide's guides decide where there is a guide
  local QD, S = Panoply.QuestData, Panoply.State
  if not (QD and QD.NewZone and S) then return nil end
  local pos = S.pos
  local z = QD:NewZone(pos and pos.map, S.zone)
  if not z or z.pvp then return nil end                          -- not a new zone (or a battleground: no guide will come)
  if step and stepMaps(step)[pos and pos.map or -1] then return nil end   -- the guide has a step here
  if stepCoversHere(step, pos, S.zone) then return nil end        -- 0.8.1: the written guide's own zone
  return ST.NEW_ZONE_TEXT
end

-- Friendly, exact instructions for turning on quest data (shown when none is found): our own
-- PanoplySuite_QuestData add-on, the only quest data Panoply Suite reads (0.6.0).
function ST.InstallQuestData()
  return {
    title = "Turn on quest data",
    intro = "Panoply Suite reads quest locations from its own Panoply Suite Quest Data add-on. Without it, it can only follow the quests already in your log.",
    steps = {
      "1. On the character screen click AddOns and tick Panoply Suite Quest Data.",
      "2. Not listed? Reinstall Panoply Suite; Panoply Suite Quest Data comes with it.",
      "3. Or unzip it by hand into your WoW Forever folder\\Interface\\AddOns.",
      "4. Restart the game (or type /reload), then click Build my route.",
    },
  }
end

-- Abandon hints for dungeon/group quests sitting in the quest log.
function ST.AbandonHints()
  local out = {}
  for _, s in ipairs((Panoply.Planner and Panoply.Planner.skippedLog) or {}) do
    local why = s.why == "raid" and "a raid" or s.why == "elite" and "an elite group quest" or "a dungeon"
    out[#out + 1] = q(s.title or "a quest in your log") .. " needs " .. why .. ". Panoply Suite skips it; you can abandon it in your quest log."
  end
  return out
end

-- What the old planner left out of its last plan, in one line (the levelling styles named it until 0.9.7; the Group quests
-- setting does now, Engine/Difficulty.lua).
function ST.FilterSummary()
  local f = Panoply.Planner and Panoply.Planner.filterStats
  local D = Panoply.Difficulty
  local lead = D.GROUP_QUESTS_LABEL .. ": " .. D.GroupQuestsName() .. ". "
  if D.Rules().dungeons then
    if not f or (f.total or 0) == 0 then return lead .. "Dungeon and group quests are included; raid quests are always left out." end
    return lead .. ("Dungeon and group quests are included; %d raid quests left out."):format(f.total)
  end
  if not f or (f.total or 0) == 0 then return lead .. "Dungeon and group quests are left out." end
  return lead .. ("%d dungeon, raid and elite group quests left out."):format(f.total)
end

-- 0.9.7 (Nov 18 2026): what /panoply style answers now. One line: the styles are gone, and where the setting that took
-- their place is (the settings search finds it by its name).
function ST.StyleGone()
  local D = Panoply.Difficulty
  return ("Levelling styles are gone. One setting took their place: %s (now: %s). Type /panoply settings group quests to change it.")
    :format(D.GROUP_QUESTS_LABEL, D.GroupQuestsName())
end

-------------------------------------------------------------------------------
-- 0.5.8: quest level + the game's difficulty colour on every quest step
-------------------------------------------------------------------------------
-- The quests a step is about: { {id=, name=, level=} } (in step order, no repeats).
function ST.Quests(step)
  local out, seen = {}, {}
  if not step or step.isProf then return out end
  local QD, Dif, S = Panoply.QuestData, Panoply.Difficulty, Panoply.State
  local function add(id, name)
    if type(id) ~= "number" or seen[id] then return end
    seen[id] = true
    local q = QD and QD.GetQuest and QD:GetQuest(id)
    local e = S and S.log and S.log[id]
    local lvl = Dif and Dif.QuestLevel(id, q) or (q and q.level) or (e and e.level)
    -- After 0.8.2: a quest of unknown level (newer than our data) stays in the list, with no level, instead of vanishing
    if lvl and lvl < 1 then lvl = nil end
    out[#out + 1] = { id = id, name = ST.Clean((q and q.name) or (e and e.title) or (Panoply.Guides and Panoply.Guides.QuestNameKnown and Panoply.Guides.QuestNameKnown(id)) or name or "Quest"), level = lvl }
  end
  if step.questID then add(step.questID, step.questName) end
  for _, g in ipairs(step.goals or {}) do
    if g.questID and (g.type == "accept" or g.type == "turnin" or g.type == "complete") then add(g.questID) end
  end
  return out
end

-- "[34] Quest Name" in its difficulty colour; up to max quests, then "+N more".
function ST.QuestLine(step, max)
  local list = ST.Quests(step)
  if #list == 0 then return "" end
  max = max or 3
  local parts = {}
  for i, q in ipairs(list) do
    if i <= max then parts[#parts + 1] = q.level and Panoply.Difficulty.Tag(q.level, q.name) or q.name end
  end
  local s = table.concat(parts, ", ")
  if #list > max then s = s .. (" +%d more"):format(#list - max) end
  return s
end

-- One row in a list (Up next, Leveling tab): the coloured quest tag(s), then the headline.
function ST.RowText(step, max)
  local tag = ST.QuestLine(step, max or 1)
  local head = ST.Headline(step)
  if tag == "" then return head end
  return tag .. "  |cffa3adb9" .. head .. "|r"
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4K (spec 06a section 3.2, spec 05 section 4.4, spec 05b section 2.2): the pieces every place that shows a step shares
-- (the Guide page, Home, the guide window, the tracker), so a step reads the same everywhere.
-------------------------------------------------------------------------------
-- The chapter's name, cleaned of level ranges and placeholders: "Westfall" from "Westfall (10-20)", nil when there is no readable one.
function ST.CleanChapter(s)
  if type(s) ~= "string" then return nil end
  s = ST.Clean(s)
  s = s:gsub("{[^}]*}", ""):gsub("%s*%(%s*%d+%s*%-%s*%d+%s*%)", ""):gsub("%s+%d+%s*%-%s*%d+%s*$", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

-- titles the engine gives a list of steps that are not a chapter of a guide
local NOT_A_CHAPTER = { ["Plan"] = true, ["No guide"] = true, ["Playing along"] = true }

-- The name of the guide chapter a step belongs to ("Westfall"), else the step's zone, else nil.
function ST.Chapter(step)
  if step and step.isDungeon then return step.dungeon or step.zone end
  local PS = Panoply.PanoplyGuideEngine
  if step and step.ps and PS then
    local z = PS.guideZone or ST.CleanChapter(PS.guideTitle)
    if z then return z end
  else
    local G = Panoply.Guides
    local guide = step and step.guideID and G and G.guides and G.guides[step.guideID]
    if guide then
      if type(guide.zone) == "string" and guide.zone ~= "" then return guide.zone end
      local t = ST.CleanChapter(guide.title)
      if t then return t end
    end
    local E = Panoply.Engine
    local t = E and E.title
    local nostep = G and G.NOSTEP_TITLE
    if type(t) == "string" and not NOT_A_CHAPTER[t] and t ~= nostep and not t:find("^Route to level")
        and not t:find("^Levels? %d") then   -- the planner's "Levels 12 to 15" names levels, not a place: the step's zone is the chapter

      local c = ST.CleanChapter(t)
      if c then return c end
    end
  end
  if step and type(step.zone) == "string" and step.zone ~= "" then return ST.Clean(step.zone) end
  return nil
end

-- Where a step sits in its guide chapter: n, total, chapter (n and total nil when not known). One meaning everywhere: the position in
-- the current guide chapter, never the length of the look-ahead list.
function ST.Number(step)
  local E = Panoply.Engine
  if not step or not E then return nil, nil, nil end
  if step.isDungeon then
    local DG = Panoply.Dungeon
    if DG and DG.StepNumber then local n, t = DG:StepNumber() return n, t, ST.Chapter(step) end
    return nil, nil, ST.Chapter(step)
  end
  local PS = Panoply.PanoplyGuideEngine
  if step.ps and PS and PS.Num then
    local n, t = PS:Num(step.psIndex)
    return n, t, ST.Chapter(step)
  end
  local steps = E.steps or {}
  local idx
  for i = 1, #steps do if steps[i] == step then idx = i break end end
  -- a step put in beside the guide (a "Fly to" step, a detour): it belongs to the guide step it leads to
  if not idx and #steps > 0 then idx = math.min(math.max(E.index or 1, 1), #steps) end
  return idx, (#steps > 0) and #steps or nil, ST.Chapter(step)
end

-- "Step 5 of 27 · Westfall" (spec 06a section 3.2). opts.chapter = false leaves the chapter off; inside a dungeon "Dungeon step 2 of 6".
-- PanoplyGuide showing a step other than the live one adds ", not your current step" (as before).
function ST.NumberText(step, opts)
  opts = opts or {}
  local n, total, chapter = ST.Number(step)
  local s
  if step and step.isDungeon then
    s = (n and total) and ("Dungeon step %d of %d"):format(n, total) or "Dungeon step"
  elseif n and total then s = ("Step %d of %d"):format(n, total)
  elseif n then s = ("Step %d"):format(n)
  else s = "" end
  if s ~= "" and opts.chapter ~= false and chapter and not (step and step.isDungeon) then s = s .. " · " .. chapter end
  if s ~= "" and step and step.psLooking then s = s .. ", not your current step" end
  return s
end

-- The eight step types (spec 05 section 4.4), one icon each: accept, turnin, kill, collect, use, travel, train, group.
ST.TYPES = { "accept", "turnin", "kill", "collect", "use", "travel", "train", "group" }
-- the skin's icon key for each type (UI/Skin.lua GAME_ICONS; the icon slot icon.step.<type> resolves the same key)
ST.TYPE_ICON = { accept = "Accept", turnin = "TurnIn", kill = "Kill", collect = "Collect", use = "Use", travel = "Travel",
                 train = "Train", group = "Group" }
-- what a goal or a step kind is, as a type
local GOAL_TYPE = { accept = "accept", turnin = "turnin", talk = "turnin", fly = "travel", hearth = "travel", ["goto"] = "travel",
                    learn = "train", train = "train", buy = "use", vendor = "use", repair = "use", use = "use", interact = "use",
                    gather = "collect", craft = "use", item = "collect", loot = "collect", collect = "collect", level = "kill", kill = "kill" }
local PROF_TYPE = { profgather = "collect", proffish = "collect", profrecipe = "train", proftrain = "train", profcraft = "use",
                    profbuy = "use", profah = "use", profbank = "use", profsmelt = "use", proffarm = "kill", profmail = "collect" }

-- a quest of the step (to finish, not to pick up) that needs a group (Engine/Difficulty.lua IsGroup)
local function groupQuest(step)
  local D = Panoply.Difficulty
  if not (D and D.IsGroup) then return false end
  local ids = {}
  if step.questID then ids[#ids + 1] = step.questID end
  for _, g in ipairs(step.goals or {}) do
    if g.questID and (g.type == "complete" or g.type == "objective" or g.type == "kill") and g.status ~= "done" then ids[#ids + 1] = g.questID end
  end
  for _, id in ipairs(ids) do
    local ok, yes = pcall(D.IsGroup, id)
    if ok and yes then return true end
  end
  return false
end

function ST.Type(step)
  if not step then return "travel" end
  if step.isDungeon or step.group then return "group" end
  if step.isProf then return PROF_TYPE[step.kind or ""] or (step.gather and "collect") or "use" end
  if step.isTravel then return step.kind == "learn" and "train" or "travel" end
  if step.kind == "train" or step.isTrainer then return "train" end
  if groupQuest(step) then return "group" end
  if step.kind == "kill" or step.kind == "grind" then return "kill" end
  if step.kind == "item" or step.kind == "object" then return "collect" end
  for _, g in ipairs(step.goals or {}) do
    if g.type == "complete" or g.type == "objective" then
      local t = step.title or ""
      return (step.kind == "kill" or t:find("^Kill") or t:find("^Slay") or t:find("^Defeat")) and "kill" or "collect"
    end
    if GOAL_TYPE[g.type] and not g.hint and g.status ~= "done" then return GOAL_TYPE[g.type] end
  end
  for _, g in ipairs(step.goals or {}) do if GOAL_TYPE[g.type] then return GOAL_TYPE[g.type] end end
  return "travel"
end
function ST.TypeIcon(step) return ST.TYPE_ICON[ST.Type(step)] end
function ST.TypeSlot(step) return "icon.step." .. ST.Type(step) end

-- Spec 05b section 2.2: a step the engine can't see done by itself (training, buying, a flight, a talk): it shows, but doesn't hold
-- the player up, and gets a Done tick. The same test the guide window's "I've done it" has always used.
function ST.Undetectable(step)
  if not step then return false end
  if step.ps then
    if step.psConfirm ~= nil then return true end
    -- a step further down the route: only a goal Done can really tick (open, manual, with its index; PS.ManualGoal)
    for _, g in ipairs(step.goals or {}) do if g.psManual and g.status == "todo" and g.psIndex then return true end end
    return false
  end
  if step.isTrainer then return true end
  if step.isProf then
    if step.kind == "profrecipe" or step.kind == "proftrain" then return true end
  end
  for _, g in ipairs(step.goals or {}) do
    -- a boss: the dungeon run often sees the kill, but not always; the player's own tick is one of its sources (Engine/Dungeon.lua)
    if (g.type == "confirm" or g.type == "talk" or g.type == "learn" or g.type == "fly" or g.type == "boss") and g.status ~= "done" then return true end
  end
  return false
end
ST.WONT_HOLD = "Won't hold you up"

-- The Done tick: the current step goes through the engine's own "I've done it" (Engine:ConfirmCurrent); a step further down the route
-- is ticked the same way its kind is ticked there. Returns true when something was ticked.
function ST.MarkDone(step)
  local E = Panoply.Engine
  if not (step and E) then return false end
  if step.onDone then local ok = pcall(step.onDone, step) return ok end   -- a step put in beside the guide (a trainer visit) says how
  if E.Current and E:Current() == step then E:ConfirmCurrent() return true end
  if step.ps and Panoply.PanoplyGuideEngine then
    -- not the current step: tick only the open manual goal; none, nothing is ticked (never the step's first open goal)
    local PS = Panoply.PanoplyGuideEngine
    local goal = step.psConfirm or (PS.ManualGoal and PS.ManualGoal(step))
    if not goal then return false end
    return PS:Confirm(step, goal)
  end
  if step.isProf and Panoply.ProfGuide then Panoply.ProfGuide:Confirm(step) return true end
  -- a dungeon boss further down the list: the player's own tick, as the current one gets (Dungeon:Confirm)
  if step.isDungeon and step.boss and Panoply.Dungeon and Panoply.Dungeon.SetBoss then return Panoply.Dungeon:SetBoss(step.boss, true, "player") and true or false end
  local any = false
  for _, g in ipairs(step.goals or {}) do
    if g.type == "confirm" or g.type == "talk" or g.type == "learn" or g.type == "fly" then g.confirmed = true any = true end
  end
  if any and E.Check then E:Check() end
  return any
end

-- "Level 16 in about 1 h 22 min at your pace" (the pace's own line, without the plan end); nil with no pace yet or the line turned off
function ST.PaceLine()
  local P = Panoply.Pace
  if not P or (Panoply.db and Panoply.db.paceShown == false) then return nil end
  return P:LevelLine(true)
end
