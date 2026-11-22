-- Quest tracker (SPEC 23): the game calls the tracker and its item buttons need, added to
-- Panoply.Compat. Kept inside the module so it merges on its own. Same rules as Core/Compat.lua:
-- every API is picked by checking it exists at call time, every read goes through Readable().
local ADDON, Panoply = ...
local C = Panoply.Compat
local G, R = C.G, C.Readable

local function pc(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  return unpack(r, 2, table.maxn(r))
end

-- Every quest in the log, in log order, with the zone header it sits under.
-- { questID, title, level, isComplete, failed, logIndex, suggestedGroup, zone }
function C.TrackerLog()
  local out = {}
  local num, info = G("C_QuestLog.GetNumQuestLogEntries"), G("C_QuestLog.GetInfo")
  if num and info then
    local zone
    for i = 1, R(pc(num)) or 0 do
      local q = pc(info, i)
      if type(q) == "table" then
        if q.isHeader then zone = R(q.title)
        elseif q.questID and q.questID ~= 0 and not q.isHidden then
          local id = q.questID
          local failed = false
          local isFailed = G("C_QuestLog.IsFailed")
          if isFailed then failed = R(pc(isFailed, id)) and true or false end
          out[#out + 1] = { questID = id, title = R(q.title), level = R(q.level), isComplete = C.IsReadyForTurnIn(id),
                            failed = failed, logIndex = i, suggestedGroup = tonumber(R(q.suggestedGroup)) or 0, zone = zone }
        end
      end
    end
    return out
  end
  local num2, title = _G.GetNumQuestLogEntries, _G.GetQuestLogTitle
  if num2 and title then
    local zone
    for i = 1, R(pc(num2)) or 0 do
      local t, level, group, isHeader, _, isComplete, _, questID = pc(title, i)
      if t and isHeader then zone = R(t)
      elseif t and questID and questID ~= 0 then
        local ready = (isComplete == 1)
        if isComplete == nil and _G.GetNumQuestLeaderBoards then
          if pc(GetNumQuestLeaderBoards, i) == 0 then ready = true end   -- "talk to" quests
        end
        out[#out + 1] = { questID = questID, title = R(t), level = R(level), isComplete = ready, failed = (isComplete == -1),
                          logIndex = i, suggestedGroup = tonumber(R(group)) or 0, zone = zone }
      end
    end
  end
  return out
end

-- Most quests the log can hold (Classic: 20).
function C.MaxQuests()
  local f = G("C_QuestLog.GetMaxNumQuestsCanAccept") or G("C_QuestLog.GetMaxNumQuests")
  local n = f and tonumber(R(pc(f)))
  if n and n > 0 then return n end
  return tonumber(_G.MAX_QUESTLOG_QUESTS) or 20
end

-- Seconds left on timed quests: { [questID] = seconds }. Forever: C_QuestLog.GetTimeAllowed;
-- Era: GetQuestTimers() + GetQuestIndexForTimer(i) -> log index.
function C.QuestTimers(entries)
  local out = {}
  local allowed = G("C_QuestLog.GetTimeAllowed")
  if allowed then
    for _, e in ipairs(entries or {}) do
      local total, elapsed = pc(allowed, e.questID)
      total, elapsed = tonumber(R(total)), tonumber(R(elapsed))
      if total and total > 0 and elapsed then out[e.questID] = math.max(0, total - elapsed) end
    end
    return out
  end
  local timers, index = _G.GetQuestTimers, _G.GetQuestIndexForTimer
  if timers and index then
    local list = { pc(timers) }
    local byIndex = {}
    for _, e in ipairs(entries or {}) do byIndex[e.logIndex] = e.questID end
    for i, secs in ipairs(list) do
      secs = tonumber(R(secs))
      local li = tonumber(R(pc(index, i)))
      if secs and li and byIndex[li] then out[byIndex[li]] = math.max(0, secs) end
    end
  end
  return out
end

-- The game's own quest item for a log entry (clients that have it). Returns itemID, icon, charges.
function C.QuestSpecialItem(logIndex)
  local f = _G.GetQuestLogSpecialItemInfo
  if not f or not logIndex then return nil end
  local link, icon, charges = pc(f, logIndex)
  link = R(link)
  local id = link and C.ItemIDFromLink(link)
  if not id then return nil end
  return id, R(icon), tonumber(R(charges))
end

-- Has the item a "Use:" effect (according to the game)?
function C.ItemUsable(itemID)
  local f = G("C_Item.GetItemSpell") or _G.GetItemSpell
  if not f or not itemID then return false end
  return R(pc(f, itemID)) ~= nil
end

-- start, duration (0, 0 when ready)
function C.ItemCooldown(itemID)
  local f = G("C_Container.GetItemCooldown") or _G.GetItemCooldown or G("C_Item.GetItemCooldown")
  if not f or not itemID then return 0, 0 end
  local s, d = pc(f, itemID)
  return tonumber(R(s)) or 0, tonumber(R(d)) or 0
end

-- Every usable bag item and the quest the game ties it to: list of { itemID, bag, slot, questID }.
function C.BagQuestItems()
  local out = {}
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, C.NumSlots(bag) do
      local s = C.SlotInfo(bag, slot)
      if s and s.itemID then
        local _, qid = C.SlotQuest(bag, slot)
        out[#out + 1] = { itemID = s.itemID, bag = bag, slot = slot, questID = qid, icon = s.icon, count = s.count }
      end
    end
  end
  return out
end

-- Open the game's quest log at a quest.
function C.OpenQuestLog(questID, logIndex)
  local details = _G.QuestMapFrame_OpenToQuestDetails
  if details and questID and pc(function() details(questID) return true end) then return "map" end
  local open = _G.QuestLog_OpenToQuest
  if open and logIndex and pc(function() open(logIndex) return true end) then return "open" end
  local frame = _G.QuestLogFrame
  if frame and logIndex then
    if _G.SelectQuestLogEntry then pc(SelectQuestLogEntry, logIndex) end
    if _G.ShowUIPanel then pc(ShowUIPanel, frame) elseif frame.Show then frame:Show() end
    if _G.QuestLog_Update then pc(QuestLog_Update) end
    return "frame"
  end
  local toggle = _G.ToggleQuestLog
  if toggle then pc(toggle) return "toggle" end
  return nil
end

local function selectQuest(questID)
  local sel = G("C_QuestLog.SetSelectedQuest")
  if sel then return pc(function() sel(questID) return true end) and true or false end
  local idx = C.LogIndexForQuest(questID)
  if idx and _G.SelectQuestLogEntry then return pc(function() SelectQuestLogEntry(idx) return true end) and true or false end
  return false
end

function C.CanShareQuest(questID)
  if not C.InGroup() or not _G.QuestLogPushQuest then return false end
  local pushable = G("C_QuestLog.IsPushableQuest")
  if pushable then return R(pc(pushable, questID)) and true or false end
  if _G.GetQuestLogPushable and selectQuest(questID) then return R(pc(GetQuestLogPushable)) and true or false end
  return true
end
function C.ShareQuest(questID)
  if not C.CanShareQuest(questID) or not selectQuest(questID) then return false end
  return pc(function() QuestLogPushQuest() return true end) and true or false
end

-- Abandon: only ever the game's own confirmation (StaticPopup "ABANDON_QUEST"); the player
-- clicks Accept there and the game abandons. Panoply Suite never calls AbandonQuest from here.
function C.ConfirmAbandon(questID, title)
  local setA = G("C_QuestLog.SetAbandonQuest") or _G.SetAbandonQuest
  local show = _G.StaticPopup_Show
  if not (setA and show) or not selectQuest(questID) then return false end
  if not pc(function() setA() return true end) then return false end
  local name = (_G.GetAbandonQuestName and R(pc(GetAbandonQuestName))) or title
  return pc(function() show("ABANDON_QUEST", name) return true end) and true or false
end

-- The game's own quest watch / objective tracker frame.
function C.GameQuestWatch()
  return _G.ObjectiveTrackerFrame or _G.QuestWatchFrame or _G.WatchFrame
end

function C.InstanceKind()
  local _, kind = C.InInstance()
  return kind or "none"
end
