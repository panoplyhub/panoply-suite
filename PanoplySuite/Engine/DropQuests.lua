-- Panoply Suite 0.5.7: after a Replan, offer to drop the quests in the log that the new route does
-- not use (SPEC 19.13). This file finds them and does the dropping; UI/DropDialog.lua asks first.
-- Safety rules:
--  * a quest is offered only when it is in the log and not in the new plan; while you are
--    partnered, quests your partner's current route still needs are never offered, and when
--    that route is not known nothing is offered at all;
--  * an item is listed (and destroyed) only when it is a quest item for that quest: the game's
--    GetContainerItemQuestInfo names the quest, or the item is that quest's objective / start /
--    provided item AND the game says it is a quest item (quest flag or item class Quest).
--    Never gear, never a non-quest item, never anything with a sell value unless it is a quest item;
--    an item another kept quest also uses is left alone;
--  * nothing happens until Confirm, and nothing at all in combat.
local ADDON, Panoply = ...
local C = Panoply.Compat
local D = { }
Panoply.DropQuests = D

D.QUEST_CLASS = 12   -- item class "Quest"
D.WHY = {
  dungeon = "Dungeon quest (dungeon quests are off)",
  raid = "Raid quest (dungeon quests are off)",
  elite = "Elite quest (elite quests are off)",
  leadIn = "Only leads to quests you are leaving out",
}

local function questRecord(id)
  local QD = Panoply.QuestData
  if not (QD and QD.Available and QD:Available()) then return nil end
  local ok, q = pcall(QD.GetQuest, QD, id)
  return ok and q or nil
end

-- Item IDs the quest database links to a quest: objective items, the item it starts from and
-- the item the quest giver hands you.
function D.LinkedItems(id)
  local out = {}
  local q = questRecord(id)
  if not q then return out end
  for _, e in ipairs((q.objectives and q.objectives.items) or {}) do if type(e[1]) == "number" then out[e[1]] = true end end
  for _, it in ipairs((q.starts and q.starts.item) or {}) do out[it] = true end
  if (q.sourceItem or 0) > 0 then out[q.sourceItem] = true end
  return out
end

-- The quests the partner's current route needs: a set, true (= nothing to protect: no
-- partner), or nil when we are partnered but don't know their route.
-- oldHash / oldSet: our plan before the replan (the partner was on it if their hash matched).
function D:PartnerNeeds(oldHash, oldSet)
  local S = Panoply.Sync
  if not (S and S.ActivePartner) then return true end
  local name, st = S:ActivePartner()
  if not name then return true end
  if not st.hash then return nil end
  if st.planSet and st.planHash == st.hash then return st.planSet end
  if oldHash and st.hash == oldHash and oldSet then return oldSet end
  if Panoply.Planner.hash and st.hash == Panoply.Planner.hash then return Panoply.Planner.planSet or {} end
  return nil
end

-- Bag scan: { [questID] = { {bag, slot, itemID, count, name, icon, link}, ... } } for the given
-- quests, plus itemUsers[itemID] = { questID = true } over every quest in the log.
function D.QuestItems(logIDs)
  local byQuest, users = {}, {}
  local linked = {}
  for id in pairs(logIDs) do linked[id] = D.LinkedItems(id) end
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, C.NumSlots(bag) do
      local s = C.SlotInfo(bag, slot)
      if s and s.itemID then
        local isQuest, questID = C.SlotQuest(bag, slot)
        local info = C.ItemInfo(s.itemID)
        local gear = info and info.equipLoc and info.equipLoc ~= "" and not info.equipLoc:find("NON_EQUIP", 1, true)
        local questItem = isQuest or (info and info.classID == D.QUEST_CLASS)
        if not gear then
          for id in pairs(logIDs) do
            local mine = (questID == id) or (questItem and linked[id][s.itemID] and (questID == nil or questID == id))
            if mine then
              users[s.itemID] = users[s.itemID] or {}
              users[s.itemID][id] = true
              byQuest[id] = byQuest[id] or {}
              byQuest[id][#byQuest[id] + 1] = { bag = bag, slot = slot, itemID = s.itemID, count = s.count or 1,
                name = (info and info.name) or (s.link and s.link:match("%[(.-)%]")) or ("Item " .. s.itemID),
                icon = s.icon or C.ItemIcon(s.itemID) or Panoply.Skin.UNKNOWN_ITEM, link = s.link }
            end
          end
        end
      end
    end
  end
  return byQuest, users
end

-- The quests to offer. Returns list (or nil, reason) where each entry is
-- { questID, title, why, class, ready, items = { ... }, keep = false }.
function D:Unneeded(oldHash, oldSet)
  local plan = Panoply.Planner.planSet or Panoply.Planner:PlanQuestSet()
  if not Panoply.Planner.hash or next(plan) == nil then return nil, "no plan" end
  local partner = self:PartnerNeeds(oldHash, oldSet)
  if partner == nil then return nil, "partner route unknown" end
  local skipped = {}
  for _, s in ipairs(Panoply.Planner.skippedLog or {}) do skipped[s.questID] = s.why end
  local log, all = {}, {}
  for _, q in ipairs(C.IterQuestLog()) do
    all[q.questID] = true
    -- 0.5.8: quests deferred by the difficulty guard are kept for later, never offered for dropping
    local deferred = Panoply.Planner.deferredSet and Panoply.Planner.deferredSet[q.questID]
    if not plan[q.questID] and not deferred and not (partner ~= true and partner[q.questID]) then log[#log + 1] = q end
  end
  local byQuest, users = D.QuestItems(all)
  local out = {}
  for _, q in ipairs(log) do
    local rec = questRecord(q.questID)
    local class = rec and (rec.classes or 0) ~= 0 or false
    local why = D.WHY[skipped[q.questID] or ""] or (class and "Class quest, not on your new route") or "Not on your new route"
    if q.isComplete then why = why .. ". Ready to hand in" end
    out[#out + 1] = { questID = q.questID, title = q.title or ("Quest " .. q.questID), why = why, class = class,
                      ready = q.isComplete and true or false, items = byQuest[q.questID] or {} }
  end
  table.sort(out, function(a, b) return tostring(a.title) < tostring(b.title) end)
  self.users = users
  return out
end

-- Run on Confirm (inside the click). Returns a report { dropped = n, items = n, manual = { names }, failed = { titles } }.
function D:Drop(list)
  if C.InCombat() then
    Panoply:Print("You are in combat. Quests can be dropped once the fight is over: press Replan again then.")
    return nil, "combat"
  end
  local dropping = {}
  for _, e in ipairs(list) do if not e.keep then dropping[e.questID] = true end end
  local report = { dropped = 0, items = 0, manual = {}, failed = {} }
  local canDelete = C.CanDeleteItems()
  for _, e in ipairs(list) do
    if not e.keep then
      for _, it in ipairs(e.items) do
        -- an item another quest that stays in the log also uses is kept
        local shared = false
        for qid in pairs((self.users or {})[it.itemID] or {}) do if not dropping[qid] then shared = true end end
        if not shared then
          local ok = canDelete and C.DeleteSlot(it.bag, it.slot, it.itemID)
          if ok then report.items = report.items + 1 else report.manual[#report.manual + 1] = it.name end
        end
      end
      if C.AbandonQuest(e.questID) then report.dropped = report.dropped + 1 else report.failed[#report.failed + 1] = e.title end
    end
  end
  local msg = ("Dropped %d quest%s"):format(report.dropped, report.dropped == 1 and "" or "s")
  if report.items > 0 then msg = msg .. (" and destroyed %d quest item%s"):format(report.items, report.items == 1 and "" or "s") end
  Panoply:Print(msg .. ".")
  if #report.manual > 0 then
    Panoply:Print("The game did not let Panoply Suite delete these quest items. Delete them by hand: " .. table.concat(report.manual, ", ") .. ".")
  end
  if #report.failed > 0 then Panoply:Print("Could not drop: " .. table.concat(report.failed, ", ") .. ". Abandon them from the quest log.") end
  Panoply:Fire("QUESTS_DROPPED", report)
  return report
end

-- Called after a successful Replan. Shows the dialog when there is something to drop.
D.SKIP_REASONS = { ["plan finished"] = true, ["level up"] = true, ["left the no-guide area"] = true }
function D:Offer(reason, oldHash, oldSet)
  if not Panoply.db or Panoply.db.dropOnReplan == false or self.SKIP_REASONS[reason or ""] then return nil end
  local list, why = self:Unneeded(oldHash, oldSet)
  if not list then
    if why == "partner route unknown" then Panoply:Debug("drop offer skipped: partner route unknown") end
    return nil, why
  end
  if #list == 0 then return nil, "none" end
  if Panoply.DropDialog then Panoply.DropDialog:Open(list) end
  return list
end
