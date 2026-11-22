-- Panoply Suite 0.9.7: the class-quest hold (the guide waits while a partner does a quest only their class can do) and the
-- help-your-partner step. Own code; it calls the engine's public calls, it does not copy them, and it draws nothing (the guide window
-- draws the card it is handed).
--   PartnerHold:Holding() -> true and the quest id while the guide is held, else false
--   PartnerHold:Card()    -> the hold card to show, or nil
--   PartnerHold:Release() -> lets the guide go on; true when a hold was released
-- Also here, for the card's buttons: PartnerHold:Help() (the arrow points at the partner), PartnerHold:StopHelp() (the arrow is back on
-- the guide) and PartnerHold:Update() (looks again; "PARTNER_HOLD_CHANGED" is fired when what the card says changed).
--
-- How it works (Nov 18 2026). The engine tells us each party member's step. A step that is no step of
-- its own for me, and is one for them (Engine.StepHiddenFor with their class, race and faction), is a quest only they can do. When my
-- own live step is the next step we both have, the guide holds: this card shows and Panoply's automatic accept and hand-in pause (they
-- ask Holding()). The engine's own wait does not cover a quest only one player has, so the hold is ours: nothing stops the player
-- doing the next step by hand, and the card then says they went ahead. The hold ends when the partner is on a step we both have
-- again, when they leave or go offline, or on "Go on without them". The arrow only points; nothing here moves the character.
local ADDON, Panoply = ...
local PartnerHold = {}
Panoply.PartnerHold = PartnerHold

local MAX_NEEDS = 3   -- lines of "what they still need" on the help card

-- the engine's own table, as the adapter finds it (Engine/PolestarEngine.lua PS.P; the engine is named in that file only)
local function P() local pe = Panoply.PolestarEngine return pe and pe.P and pe.P() or nil end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then Panoply:Debug("partner hold call", a) return nil end
  return a, b, c
end

-- the guide's own words go through Panoply's voice (never the engine's name in what the player reads)
local function voice(s)
  local V = Panoply.PolestarVoice
  if V and V.GuideText and type(s) == "string" then return V.GuideText(s) end
  return s
end

-- the hold under way: { key (the partner's party key), name, unit, index (their step in my guide), guide, classOnly, ahead,
-- helping, target (the arrow's point while helping) }, or nil
local state
-- partners the player went on without ("Go on without them"), by party key: no hold for them until they are on a shared step again
local released = {}
local listening   -- the engine table whose messages we listen to

-- Partner levelling is on and the engine is the one that runs the guide
local function enabled()
  local PE = Panoply.PolestarEngine
  if not (PE and PE.Active and PE:Active()) then return false end
  if Panoply.db and Panoply.db.partyShare == false then return false end
  local p = P()
  if not (p and p.Party and p.Engine and type(p.Engine.StepHiddenFor) == "function") then return false end
  if p.Get and call(p.Get, "party.show") == false then return false end
  return true
end

-- A member's step in my copy of the guide: by what the step holds (their step key), else by its number on the same guide version
local function theirIndex(p, m, g)
  local at = m.at
  if type(at) == "table" and at.guide == g.id then
    local i = call(p.Party.StepAt, g, at.key)
    if i then return i end
  end
  local pos = m.pos
  if type(pos) == "table" and type(pos.step) == "number" and pos.step > 0 and pos.guide == g.id then
    local mine = call(p.Party.MyPos)
    if mine and mine.packVersion == pos.packVersion then return pos.step end
  end
  return nil
end

-- How many steps we both have lie after their step `i` and before my live step: the steps I went on to while they were there. A step
-- that is not for one of us (Engine.StepHiddenFor), or that does not apply to me now (a step for a quest I do not have), is not one.
local FAR = 40   -- further apart than this is simply "ahead"; nobody is waiting at the next step
local function passed(p, g, i, live, who)
  local E = p.Engine
  if live - i > FAR then return live - i end
  local n = 0
  for s = i + 1, live - 1 do
    local step = g.steps[s]
    if step and call(E.StepHiddenFor, step) == false and call(E.StepHiddenFor, step, who) == false then
      local view = call(E.GetStepView, s)
      if not (type(view) == "table" and view.status == "na") then n = n + 1 end
    end
  end
  return n
end

-- Every party member who is on a step only they have: { key, name, unit, index, classOnly, ahead }, in the party's order of names.
-- `ahead`: how many steps we both have lie between their step and my live step (0: I am on the next one; nil: I am behind them).
local function scan(p)
  local E, Party = p.Engine, p.Party
  local g = call(E.GetGuide)
  local live = call(E.GetLiveStep)
  local out, seen = {}, {}
  if not (type(g) == "table" and type(g.steps) == "table" and type(live) == "number") then return out, seen end
  local rows = {}
  for _, row in ipairs(call(Party.Roster) or {}) do if row.name then rows[row.name] = row end end
  local myRace = select(2, UnitRace("player"))
  local myFaction = UnitFactionGroup("player")
  for _, m in ipairs(call(Party.Members) or {}) do
    local row = rows[m.name]
    local i = m.key and row and not row.offline and theirIndex(p, m, g)
    local step = i and g.steps[i]
    if step then
      seen[m.key] = true
      if call(E.StepHiddenFor, step) == true then
        local info = call(Party.UnitInfo, row.unit, m.key) or {}
        if info.class and call(E.StepHiddenFor, step, { class = info.class, race = info.race or myRace, faction = myFaction }) == false then
          -- theirs because of their class alone (my race, their class would have it), or for another reason (their race)
          local classOnly = call(E.StepHiddenFor, step, { class = info.class, race = myRace, faction = myFaction }) == false
          local ahead = nil
          if live > i then ahead = passed(p, g, i, live, { class = info.class, race = info.race or myRace, faction = myFaction }) end
          out[#out + 1] = { key = m.key, name = m.name, unit = row.unit, index = i, guide = g.id, classOnly = classOnly, ahead = ahead, member = m }
        else
          seen[m.key] = "shared"
        end
      else
        seen[m.key] = "shared"
      end
    end
  end
  return out, seen
end

-- The arrow back on the guide, when it is still on the partner we pointed it at
local function endHelp(p)
  if not (state and state.helping) then return end
  local target = state.target
  state.helping, state.target = nil, nil
  local Nav = p and p.Nav
  if not (Nav and target) then return end
  local trip = call(Nav.Trip)
  if trip and trip.target == target then call(Nav.EndTrip) end
end

-- The guide window back on my own live step (a look elsewhere changes no progress)
local function backToLive(p)
  local E = p and p.Engine
  if not E then return end
  local live = call(E.GetLiveStep)
  if live and E.GetStepIndex and call(E.GetStepIndex) ~= live then call(E.Goto, live) end
end

local function signature()
  if not state then return "" end
  return table.concat({ state.key, state.index, state.ahead or 0, state.helping and "help" or "hold" }, "|")
end

local function listen(p)
  if listening == p or type(p.On) ~= "function" then return end
  listening = p
  for _, msg in ipairs({ "PARTY_PROGRESS", "STEP_CHANGED", "GUIDE_CHANGED" }) do
    p.On(msg, function() PartnerHold:Update() end)
  end
end

-- Looks again at where the party is; starts, keeps or ends the hold. Returns the hold's state, or nil.
function PartnerHold:Update()
  local before = signature()
  local p = P()
  if not enabled() then
    if state then endHelp(p) state = nil end
    for k in pairs(released) do released[k] = nil end
  else
    listen(p)
    local found, seen = scan(p)
    -- a partner who is on a step we both have again, or is gone, can be waited for again later
    for key in pairs(released) do
      if seen[key] ~= true then released[key] = nil end
    end
    local keep, fresh
    for _, f in ipairs(found) do
      if not released[f.key] then
        if state and f.key == state.key and f.ahead then keep = f
        elseif f.ahead == 0 then fresh = fresh or f end
      end
    end
    local f = keep or fresh
    if f then
      if not (state and state.key == f.key) then
        if state then endHelp(p) end
        state = { key = f.key }
      end
      state.name, state.unit, state.index, state.guide = f.name, f.unit, f.index, f.guide
      state.classOnly, state.ahead, state.member = f.classOnly, f.ahead, f.member
      -- the arrow left the partner (they were reached, or the player picked another spot): the card is the hold card again
      if state.helping and state.target then
        local trip = p.Nav and call(p.Nav.Trip)
        if not (trip and trip.target == state.target) then state.helping, state.target = nil, nil end
      end
    elseif state then
      endHelp(p)
      state = nil
    end
  end
  if signature() ~= before then Panoply:Fire("PARTNER_HOLD_CHANGED", state ~= nil) end
  return state
end

-- The partner's step as we can show it: its title, the quest it is about, and what they still need of it
local function partnerStep(p, s)
  local E = p.Engine
  local view = call(E.GetStepView, s.index)
  local g = call(E.GetGuide)
  local raw = g and g.steps and g.steps[s.index]
  local quests = s.member and s.member.quests or {}
  local title, quest, needs, open = nil, nil, {}, {}
  if type(view) == "table" then
    if type(view.title) == "string" and view.title ~= "" then title = voice(view.title) end
    for _, gv in ipairs(view.goals or {}) do
      local q = type(gv.quest) == "number" and gv.quest or nil
      quest = quest or q
      local text = type(gv.text) == "string" and voice(gv.text) or ""
      if gv.t ~= "note" and text ~= "" then
        local counts = q and gv.oi and quests[q]
        local line = counts and (call(E.ObjectiveLine, gv) or gv.oi)
        local c = line and counts[line]
        if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" then
          if c[1] < c[2] then needs[#needs + 1] = ("%s: %d/%d"):format(voice(gv.subject) or text, c[1], c[2]) end
        else
          open[#open + 1] = text
        end
        title = title or text
      end
    end
  end
  if not quest and type(raw) == "table" then
    for _, goal in ipairs(raw.goals or {}) do
      if type(goal.quest) == "number" then quest = goal.quest break end
    end
  end
  -- nothing counted for them yet (they have not picked the quest up, or the step has nothing to count): the step's own lines
  if #needs == 0 then needs = open end
  while #needs > MAX_NEEDS do needs[#needs] = nil end
  return title, quest, needs
end

-- true and the partner's quest id while the guide is held (Panoply's automatic accept and hand-in pause), else false
function PartnerHold:Holding()
  local s = self:Update()
  if not s then return false, nil end
  local _, quest = partnerStep(P(), s)
  return true, quest
end

-- The card for the guide window, or nil: { kind = "hold" | "help" | "ahead", kicker, title, body, lines (what they still need, on the
-- help card), partner, questID, buttons = { a, b } } with a = { label, tip, fn, action } and b the same (also given as card.a and
-- card.b, the shape of the guide's own questions). action names the Engine/PolestarParty.lua call that does the same as fn:
-- "Help", "StopHelp", and "GoOn" for "Go on without them" (PolestarParty:GoOn calls PartnerHold:Release while a hold is on).
function PartnerHold:Card()
  local s = self:Update()
  if not s then return nil end
  local name = tostring(s.name or "Your partner")
  local stepTitle, quest, needs = partnerStep(P(), s)
  local what = s.classOnly and "their class quest" or "a quest only they can do"
  local card = { kicker = "Levelling together", partner = name, questID = quest, lines = {} }
  card.b = { label = "Go on without them", tip = ("Your guide goes on. %s can catch up later."):format(name), action = "GoOn", fn = function() PartnerHold:Release() end }
  if s.helping then
    card.kind = "help"
    card.title = ("Help %s"):format(name)
    card.body = stepTitle and ("%s is on: %s. The arrow points to %s."):format(name, stepTitle, name) or ("The arrow points to %s."):format(name)
    card.lines = needs
    card.a = { label = "Stop helping", tip = "The arrow goes back to your own guide. Your guide still waits.", action = "StopHelp", fn = function() PartnerHold:StopHelp() end }
  else
    if (s.ahead or 0) > 0 then
      card.kind = "ahead"
      card.title = ("You went ahead; %s is still on %s"):format(name, what)
      card.body = "Your own automatic pick-up and hand-in stay paused until you choose."
    else
      card.kind = "hold"
      card.title = ("Hold on: %s is doing %s"):format(name, what)
      card.body = "Your guide waits here, and nothing is picked up or handed in for you meanwhile."
    end
    card.a = { label = ("Help %s"):format(name), tip = ("Shows what %s still needs and points the arrow at them."):format(name), action = "Help", fn = function() PartnerHold:Help() end }
  end
  card.buttons = { card.a, card.b }
  return card
end

-- "Help <partner>": the arrow points at them (it never moves the character). True when the arrow has their place.
function PartnerHold:Help()
  local s = self:Update()
  if not s then return false end
  if s.helping then return true end
  local p = P()
  if not (s.unit and p.Party.PointAt and call(p.Party.PointAt, s.unit) == true) then
    Panoply:Print(("The game does not show where %s is right now, so the arrow stays on your guide."):format(tostring(s.name or "your partner")))
    s.helping, s.target = true, nil   -- the card still shows what they need
    Panoply:Fire("PARTNER_HOLD_CHANGED", true)
    return false
  end
  local trip = p.Nav and call(p.Nav.Trip)
  s.helping, s.target = true, trip and trip.target or nil
  Panoply:Fire("PARTNER_HOLD_CHANGED", true)
  return true
end

-- "Stop helping": the arrow is back on my own guide; the hold stays. True when helping ended.
function PartnerHold:StopHelp()
  if not (state and state.helping) then return false end
  local p = P()
  endHelp(p)
  backToLive(p)
  Panoply:Fire("PARTNER_HOLD_CHANGED", true)
  return true
end

-- "Go on without them": the hold ends and does not come back for this partner until they are on a step we both have again.
-- True when a hold was released.
function PartnerHold:Release()
  if not state then return false end
  local p = P()
  released[state.key] = true
  endHelp(p)
  state = nil
  backToLive(p)
  Panoply:Fire("PARTNER_HOLD_CHANGED", false)
  return true
end
