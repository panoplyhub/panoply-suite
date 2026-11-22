-- Panoply Suite automation (SPEC section 7): auto accept, auto turn-in, auto fly.
-- Hold Shift while talking to an NPC to suppress everything. Never sends chat.
local ADDON, Panoply = ...
local A = {}
Panoply.Automation = A
local C = Panoply.Compat

local function db() return Panoply.db or Panoply.defaults.account end

function A:Suppressed()
  return C.ShiftDown() or C.InCombat() or self:PartnerHeld()
end

-- 0.9.7 (partner leveling): while the guide holds for a partner's class quest (Engine/PartnerHold.lua), nothing is accepted,
-- handed in or flown for the player; the hold's card says why and "Go on without them" ends it.
function A:PartnerHeld()
  local H = Panoply.PartnerHold
  if not (H and H.Holding) then return false end
  local ok, held = pcall(H.Holding, H)
  if not ok then Panoply:Debug("automation", "partner hold", held) return false end
  return held == true
end

-- 0.9.7 (partner leveling, the automation-hold fix): the guide's party sync holds a quest's hand-in while a party member still needs
-- the quest; our auto turn-in did not ask and handed it in anyway. Now it asks (Engine/PolestarParty.lua, the engine's
-- Party.HoldsQuest) and leaves that quest alone, saying so once per quest for as long as the wait lasts. The player can still hand
-- it in by hand, or press "Go on without them".
A.waitSaid = {}
function A:PartnerWaits(questID, title)
  questID = tonumber(questID)
  local PP = Panoply.PolestarParty
  if not (questID and PP and PP.Waiting) then return false end
  local ok, waits, names = pcall(PP.Waiting, PP, questID)
  if not ok then Panoply:Debug("automation", "partner wait", waits) return false end
  if not waits then self.waitSaid[questID] = nil return false end
  if not self.waitSaid[questID] then
    self.waitSaid[questID] = true
    local who = type(names) == "table" and #names > 0 and PP.NameList(names) or "your partner"
    title = title or C.QuestTitle(questID)
    Panoply:Print(("Waiting for %s before handing in %s."):format(who, title and ("\"" .. title .. "\"") or "that quest"))
  end
  return true
end

-- Is the quest part of the route? (WoW Forever with Polestar's engine: Polestar's guide says so)
local function inPlan(questID)
  if questID == nil then return false end
  local PE = Panoply.PolestarEngine
  if PE and PE:Active() then return PE:WantsQuest(questID) end
  return Panoply.Planner.planSet ~= nil and Panoply.Planner.planSet[questID] == true
end

-- 0.9.6.1 (ticket PS-0011, Nov 17 2026: on WoW Forever a new Dwarf right-clicked Sten Stoutarm, the window "tried to pick it up
-- and then failed", and the first quest could not be taken). Quests whose automatic accept did not land this session: the next
-- window for one of them is left to the player (the game's own window, its own Accept button), so a click is never lost twice.
-- questID -> true; cleared when the quest reaches the log.
A.held = {}
A.CHECK_S = 5   -- seconds after the quest window closed for the accepted quest to reach the log
-- 0.9.6.2 (PS-0011 again, Nov 17 2026: after the setup finished, right-clicking Sten Stoutarm "did nothing or started then failed" for
-- minutes, with no line in chat). Picking a quest in the gossip list closes the list; when the game then opens no quest window for
-- it, nothing was said and the next right-click did the same. A pick waits this long for its quest window; without one, the quest is
-- held (the list is the player's from then on) and the player is told once.
A.PICK_S = 2

-- Should we touch this quest? (optionally only quests in the current plan)
function A:Wanted(questID, isTrivial, repeatable)
  if questID ~= nil and self.held[questID] then return false end
  local d = db()
  -- 0.8.4: repeatable quests are left alone unless the player asked for them too (off by default)
  if repeatable and d.autoRepeatable ~= true then return false end
  if d.autoOnlyPlanQuests then return inPlan(questID) end
  if isTrivial and d.autoSkipTrivial then return inPlan(questID) end
  return true
end

-- 0.9.6.2: an entry of the giver's list that is a quest to take: a real quest id, not in the log already, wanted, and not picked
-- already in this window (the game shows the list again after a quest window closes; a pick that led nowhere is not repeated).
function A:Pickable(q)
  local id = q and tonumber(C.Readable(q.questID))
  if not id or id <= 0 then return false end
  if C.LogIndexForQuest(id) then return false end
  local p = self.picked
  if p and p.questID == id then return false end
  return self:Wanted(id, q.isTrivial, q.repeatable)
end

-- A quest picked in the list: its quest window must follow (QUEST_DETAIL for it). When none does, the quest is held and the player
-- is told, in one line, to pick it in the list (A:CheckPicked).
function A:Picked(q)
  local p = { questID = tonumber(C.Readable(q.questID)), title = q.title }
  self.picked = p
  C.After(self.PICK_S, function() A:CheckPicked(p) end)
end

function A:CheckPicked(p)
  if not p or self.picked ~= p then return false end
  self.picked = nil
  if p.detail or C.LogIndexForQuest(p.questID) or self.held[p.questID] then return false end
  self.held[p.questID] = true
  local name = p.title and ("\"" .. p.title .. "\"") or "That quest"
  Panoply:Print(name .. " did not open. Right-click the quest giver again and pick it in the list: Panoply Suite leaves that window to you.")
  Panoply:Debug("automation", "pick led to no quest window", p.questID)
  return true
end

function A:GOSSIP_SHOW()
  if self:Suppressed() then return end
  local d = db()
  if d.autoTurnIn then
    for _, q in ipairs(C.GossipActive()) do
      if q.isComplete and not self:PartnerWaits(C.Readable(q.questID), q.title) then C.GossipSelectActive(q) return end
    end
  end
  if d.autoAccept then
    for _, q in ipairs(C.GossipAvailable()) do
      if self:Pickable(q) then
        if C.GossipSelectAvailable(q) then self:Picked(q) end
        return
      end
    end
  end
end

function A:QUEST_GREETING()
  if self:Suppressed() then return end
  local d = db()
  if d.autoTurnIn then
    for _, q in ipairs(C.GreetingActive()) do
      if q.isComplete and not self:PartnerWaits(C.Readable(q.questID), q.title) then C.GreetingSelectActive(q.index) return end
    end
  end
  if d.autoAccept then
    for _, q in ipairs(C.GreetingAvailable()) do
      if self:Pickable(q) then
        if C.GreetingSelectAvailable(q.index) then self:Picked(q) end
        return
      end
    end
  end
end

-- The quest window answered as the game's own Accept button answers it (0.9.6.1, PS-0011). A quest the game already gave as the
-- window opened (WoW Forever's auto-accept quests) is acknowledged, never accepted a second time (AcceptQuest there is the likely
-- "tried to pick it up and then failed"; not seen in the game). A quest offered by walking into a place gets the game's own pop-up;
-- one that turns PvP on gets the game's own question. Both are left to the player.
-- 0.9.6.2: the acknowledgement is checked as the accept is (the quest window closes, the quest must be in the log a moment later):
-- before, it returned at once, so one that did not give the quest was never noticed and the same click failed again and again.
function A:QUEST_DETAIL()
  local qid = C.DialogQuestID()
  local pk = self.picked
  if pk and qid and pk.questID == qid then pk.detail = true end   -- the pick's quest window came
  if self:Suppressed() or not db().autoAccept then return end
  if qid and not self:Wanted(qid, false, false) then return end
  if C.QuestAutoAccepted() then
    if C.QuestFromAreaTrigger() then return end
    if qid then self.pending = { questID = qid, title = C.DialogTitle() } end
    C.AcknowledgeAutoAccept()
    return
  end
  if C.QuestNeedsPvPConfirm() then return end
  if qid then self.pending = { questID = qid, title = C.DialogTitle() } end
  C.AcceptQuest()
end

-- The quest window closed after Panoply's accept: the quest must be in the log a moment later. When it is not, that quest is
-- held (its next window is the player's, untouched) and the player is told, in one line, to take it at the quest giver.
function A:QUEST_FINISHED()
  local p = self.pending
  if not p then return end
  self.pending = nil
  C.After(self.CHECK_S, function() A:CheckTaken(p) end)
end

function A:CheckTaken(p)
  if not p or C.LogIndexForQuest(p.questID) then return false end
  if self.held[p.questID] then return false end
  self.held[p.questID] = true
  local name = p.title and ("\"" .. p.title .. "\"") or "That quest"
  Panoply:Print(name .. " did not reach your quest log. Right-click the quest giver again and press Accept: Panoply Suite leaves that window to you.")
  Panoply:Debug("automation", "accept did not land", p.questID)
  return true
end

-- QUEST_ACCEPTED carries (questID) on WoW Forever and (questLogIndex, questID) on Classic (after the event's name, as Panoply:On
-- hands every handler).
function A:QUEST_ACCEPTED(_, a, b)
  local id = tonumber(C.Readable(b)) or tonumber(C.Readable(a))
  if not id then return end
  self.held[id] = nil
  if self.pending and self.pending.questID == id then self.pending = nil end
  if self.picked and self.picked.questID == id then self.picked = nil end
end

function A:QUEST_PROGRESS()
  if self:Suppressed() or not db().autoTurnIn then return end
  if self:PartnerWaits(C.DialogQuestID(), C.DialogTitle()) then return end   -- (a quest the player opened by hand: left to the player)
  if C.IsQuestCompletable() then C.CompleteQuest() end
end

function A:QUEST_COMPLETE()
  if self:Suppressed() or not db().autoTurnIn then return end
  if self:PartnerWaits(C.DialogQuestID(), C.DialogTitle()) then return end
  local n = C.NumQuestChoices()
  if n == 0 then C.GetQuestReward(0) return end
  if n == 1 and db().autoSelectSingleReward then C.GetQuestReward(1) return end
  -- More than one reward: the player chooses.
end

-- The flight destination wanted by the current step, if any.
function A:WantedFlight()
  local step = Panoply.Engine:Current()
  -- 0.6.0 travel steps ("Fly to X") are advice only: they never pick the flight for you
  if not step or step.isTravel then return nil end
  for _, g in ipairs(step.goals) do
    if g.type == "fly" and g.status ~= "done" then return g.node or g.zone end
  end
  return nil
end

function A:TAXIMAP_OPENED()
  local nodes = C.TaxiNodes()
  if Panoply.cdb then
    for _, n in ipairs(nodes) do
      if n.name and (n.state == "current" or n.state == "reachable") then Panoply.cdb.knownTaxi[n.name] = true end
    end
  end
  Panoply.Engine:Check()
  if self:Suppressed() or not db().autoFly then return end
  local want = self:WantedFlight()
  if not want then return end
  local needle = want:lower()
  for _, n in ipairs(nodes) do
    if n.state == "reachable" and n.name and n.name:lower():find(needle, 1, true) then
      Panoply:Print("Flying to " .. n.name .. " (hold Shift to stop this next time).")
      C.TakeTaxi(n.slotIndex)
      return
    end
  end
end

-- 0.8.4: a quest a group member shares or starts (an escort) asks "accept?" in a small box of its own. With "Accept quests
-- my group starts" on (off by default) the answer is yes, as it is for quests at a quest giver. Shift suppresses it.
function A:QUEST_ACCEPT_CONFIRM()
  local d = db()
  if self:Suppressed() or not (d.autoAccept and d.autoAcceptShared == true) then return end
  local f = _G.ConfirmAcceptQuest
  if type(f) ~= "function" then return end
  -- the game's own box is left as it is (hiding it from add-on code could taint the game's popups); it does no harm
  f()
end

Panoply.defaults.account.autoRepeatable = false     -- 0.8.4: also start repeatable quests
Panoply.defaults.account.autoAcceptShared = false   -- 0.8.4: say yes to a quest a group member shares or starts

function A:Register()
  for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "TAXIMAP_OPENED", "QUEST_ACCEPT_CONFIRM",
                          "QUEST_FINISHED", "QUEST_ACCEPTED" }) do
    Panoply:On(ev, function(...) local ok, err = pcall(A[ev], A, ...) if not ok then Panoply:Debug("automation", ev, err) end end)
  end
end
