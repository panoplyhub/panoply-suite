-- Panoply Suite 0.5.8 difficulty guard + quest difficulty colours.
-- One place decides whether a quest is safe to route right now, using the game's own quest
-- difficulty colours:
--   red    (quest level >= your level + 5)  never routed, whatever the settings say
--   orange (+3 / +4)                         normal quests only, never an elite one
--   elite / group quests need quest level <= your level + 2
-- In partner mode the LOWER level of the two players counts. Quests that are too hard now are
-- deferred (kept, not dropped) and come back when a level-up makes them safe.
local ADDON, Panoply = ...
local C = Panoply.Compat
local D = {}
Panoply.Difficulty = D

D.RED = 5            -- game: quest level >= level + 5 is red ("impossible")
D.ORANGE = 3         -- game: +3 / +4 is orange ("very difficult")
D.ELITE_MAX = 2      -- 0.5.8: elite quests at most level + 2 (yellow at worst)

-- The game's standard quest difficulty colours (the values the default UI uses for the quest log),
-- used only when the client does not hand them to us.
D.COLORS = {
  impossible    = { 1.00, 0.10, 0.10 },
  verydifficult = { 1.00, 0.50, 0.25 },
  difficult     = { 1.00, 0.82, 0.00 },
  standard      = { 0.25, 0.75, 0.25 },
  trivial       = { 0.50, 0.50, 0.50 },
}
D.KEY_NAMES = { impossible = "red", verydifficult = "orange", difficult = "yellow", standard = "green", trivial = "grey" }

-- Darkest panel colour text sits on (Skin bgDeep/bgMid); used for the readability lift.
D.PANEL = { 0x18 / 255, 0x20 / 255, 0x2b / 255 }
D.MIN_CONTRAST = 5      -- WCAG AA is 4.5; 5 keeps dimmed Up next rows (alpha 0.7) above 3

-------------------------------------------------------------------------------
-- Colour
-------------------------------------------------------------------------------
-- Difficulty key for a quest level seen from a player level (the game's thresholds, incl. the
-- green range from GetQuestGreenRange / C_QuestLog.GetTrivialRange via Compat).
function D.Key(questLevel, playerLevel)
  questLevel = tonumber(questLevel) or 1
  playerLevel = tonumber(playerLevel) or 1
  local diff = questLevel - playerLevel
  if diff >= D.RED then return "impossible"
  elseif diff >= D.ORANGE then return "verydifficult"
  elseif diff >= -2 then return "difficult"
  elseif -diff <= C.TrivialRange(playerLevel) then return "standard" end
  return "trivial"
end

local function lum(c)
  local function ch(v) v = math.max(0, math.min(1, v)) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
function D.Contrast(a, b)
  local la, lb = lum(a), lum(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

-- Keep the game's hue but lift it toward white until it reads on our dark panels.
function D.Readable(c, bg)
  bg = bg or D.PANEL
  local r, g, b = c[1], c[2], c[3]
  local n = 0
  while D.Contrast({ r, g, b }, bg) < D.MIN_CONTRAST and n < 20 do
    r, g, b = r + (1 - r) * 0.08, g + (1 - g) * 0.08, b + (1 - b) * 0.08
    n = n + 1
  end
  return { r, g, b }
end

-- Game colour for a key: the client's own QuestDifficultyColors table first, then
-- GetQuestDifficultyColor (only when it answers for the same level we ask about), then ours.
function D.GameColor(key, questLevel, playerLevel)
  local t = _G.QuestDifficultyColors
  local c = type(t) == "table" and t[key]
  if type(c) == "table" and tonumber(c.r) then return { c.r, c.g, c.b } end
  local f = _G.GetQuestDifficultyColor
  if f and questLevel and _G.UnitLevel and playerLevel == C.XP() then
    local ok, v = pcall(f, questLevel)
    if ok and type(v) == "table" and tonumber(v.r) then return { v.r, v.g, v.b } end
  end
  local d = D.COLORS[key] or D.COLORS.difficult
  return { d[1], d[2], d[3] }
end

-- Colour of a quest for the player (their own level: the colour the game's quest log shows).
-- Returns key, {r,g,b} (readable on our panels), hex "ffRRGGBB".
function D.Color(questLevel, playerLevel)
  playerLevel = playerLevel or (Panoply.State and Panoply.State.level) or C.XP()
  local key = D.Key(questLevel, playerLevel)
  local c = D.Readable(D.GameColor(key, questLevel, playerLevel))
  local hex = ("ff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  return key, c, hex
end

-- "[34] Quest Name" wrapped in its difficulty colour (|c...|r).
function D.Tag(questLevel, name, playerLevel)
  local _, _, hex = D.Color(questLevel, playerLevel)
  return ("|c%s[%d] %s|r"):format(hex, tonumber(questLevel) or 1, name or "Quest")
end

-------------------------------------------------------------------------------
-- Group quests (0.9.7, Nov 18 2026): the levelling styles are gone. ONE setting decides what the guide does at a quest
-- that is meant for a group: PanoplySuiteDB.groupQuests = "ask" | "do" | "skip".
--   ask   the guide asks at each group quest (the guide card's question; an answer given for a quest is kept for that quest)
--   do    group quests are always part of the guide
--   skip  group quests are always left out
-- Engine/PolestarEngine.lua hands the setting to the guide engine at login and whenever it changes. The words below are the
-- one copy every window uses (Settings, setup, the slash line).
-------------------------------------------------------------------------------
D.GROUP_QUESTS = { "ask", "do", "skip" }
D.DEFAULT_GROUP_QUESTS = "ask"
D.GROUP_QUESTS_LABEL = "Group quests"
D.GROUP_QUESTS_NAME = { ask = "Ask me each time", ["do"] = "Always include them", skip = "Leave them out" }
D.GROUP_QUESTS_TEXT = {
  ask = "At each quest meant for a group, your guide asks whether you want to do it.",
  ["do"] = "Quests meant for a group are always part of your guide.",
  skip = "Quests meant for a group are always left out of your guide.",
}

function D.GroupQuestsKey(key) return D.GROUP_QUESTS_NAME[key] and key or D.DEFAULT_GROUP_QUESTS end
-- The saved setting: Panoply.db.groupQuests, or the default when it is missing or not one of the three.
function D.GroupQuests() return D.GroupQuestsKey(Panoply.db and Panoply.db.groupQuests) end
function D.GroupQuestsName(key) return D.GROUP_QUESTS_NAME[D.GroupQuestsKey(key or D.GroupQuests())] end

-- What each old levelling style becomes (Nov 18 2026), used ONCE by Core/Init.lua, and only when groupQuests was never set:
-- Safe & steady -> Ask me each time; Safe -> Leave them out; Fastest and Ultimate -> Always include them.
D.GROUP_QUESTS_FROM_STYLE = { steady = "ask", safe = "skip", fastest = "do", ultimate = "do" }
function D.GroupQuestsFromStyle(style) return D.GROUP_QUESTS_FROM_STYLE[style] or D.DEFAULT_GROUP_QUESTS end

-- The rules the old planner plays by (Engine/Planner.lua; it builds no levelling route in the add-on). The four styles each had
-- their own; now there is one set, and only the group setting moves it:
--   maxAbove  highest quest level taken, relative to your level (+2 = yellow at worst)
--   mobAbove  highest enemy level a quest may send you to, relative to your level
--   elite     elite open-world quests are taken (still at most D.ELITE_MAX above you): only with "Always include them"
--   dungeons  dungeon and group quests are taken too: only with "Always include them". RAID quests never are.
function D.Rules()
  local all = D.GroupQuests() == "do"
  return { maxAbove = 2, mobAbove = 2, elite = all, dungeons = all }
end

-- Highest quest level worth considering for a plan that ends at goalLevel (the planner's candidate cut).
function D.MaxQuestLevel(rules, goalLevel)
  local top = goalLevel + rules.maxAbove
  if rules.ownLevelUntil then top = math.max(top, math.min(goalLevel, rules.ownLevelUntil)) end
  return top
end

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------
-- Level the rules use: yours, or the lower of you and your partner.
function D.EffectiveLevel(level, partnerLevel)
  level = tonumber(level) or 1
  partnerLevel = tonumber(partnerLevel)
  if partnerLevel and partnerLevel > 0 and partnerLevel < level then return partnerLevel end
  return level
end

-- Why a quest at questLevel can't be routed for a player at level (nil = fine).
--   "red": the game shows it red.  "elite": a group quest above level + 2 (orange or worse).
function D.Blocked(questLevel, level, isGroup)
  questLevel, level = tonumber(questLevel) or 1, tonumber(level) or 1
  if questLevel >= level + D.RED then return "red" end
  if isGroup and questLevel > level + D.ELITE_MAX then return "elite" end
  return nil
end

-- Lowest level at which the quest becomes OK.
function D.NeedLevel(questLevel, isGroup)
  questLevel = tonumber(questLevel) or 1
  return isGroup and (questLevel - D.ELITE_MAX) or (questLevel - D.RED + 1)
end

-- Quest level: the database's, or the game's own (from the quest log) when that is higher.
function D.QuestLevel(id, q)
  local QD = Panoply.QuestData
  q = q or (QD and QD.GetQuest and QD:GetQuest(id))
  local lvl = q and q.level or 0
  local e = Panoply.State and Panoply.State.log and Panoply.State.log[id]
  if e and tonumber(e.level) and e.level > lvl then lvl = e.level end
  return lvl > 0 and lvl or nil
end

-- Elite / group content (whatever the include settings say).
function D.IsGroup(id, q)
  local QD = Panoply.QuestData
  q = q or (QD and QD.GetQuest and QD:GetQuest(id))
  if q and QD.GroupContentReason then
    local ok, why = pcall(QD.GroupContentReason, QD, q)
    if ok and why then return true end
  end
  local e = Panoply.State and Panoply.State.log and Panoply.State.log[id]
  if e then
    if (e.suggestedGroup or 0) > 1 then return true end
    local okT, tag = pcall(C.QuestTag, id)
    if okT and (tag == "group" or tag == "elite" or tag == "dungeon" or tag == "raid") then return true end
  end
  return false
end

function D.PartnerLevel()
  local S = Panoply.Sync
  if not S or not S.PartnerLevel then return nil end
  local ok, v = pcall(S.PartnerLevel, S)
  return ok and v or nil
end

-- Runtime check for the step engine: returns nil when the quest is fine now, else
-- { why = "red"|"elite", level = questLevel, need = levelNeeded, eff = levelUsed }.
function D.Defer(id)
  if type(id) ~= "number" then return nil end
  local Sx = Panoply.State
  local e = Sx and Sx.log and Sx.log[id]
  if e and e.isComplete then return nil end               -- ready to hand in: always fine
  if Sx and Sx.completed and Sx.completed[id] then return nil end
  local qLevel = D.QuestLevel(id)
  if not qLevel then return nil end
  local eff = D.EffectiveLevel(Sx and Sx.level or C.XP(), D.PartnerLevel())
  local group = D.IsGroup(id)
  local why = D.Blocked(qLevel, eff, group)
  if not why then return nil end
  return { why = why, level = qLevel, need = D.NeedLevel(qLevel, group), eff = eff, group = group }
end

function D.Explain(id, name, info)
  local who = info.eff and (Panoply.State and Panoply.State.level and info.eff < Panoply.State.level) and " (your partner's level)" or ""
  local what = info.why == "red" and "too hard (red)" or "an elite quest above your level"
  return ("Later: %s is %s at level %d%s. It comes back at level %d."):format(D.Tag(info.level, name), what, info.eff or 0, who, info.need or 0)
end
