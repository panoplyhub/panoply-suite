-- Panoply Suite 0.9.5, phase 4A4: the shared setup answers (docs/specs/page-redesigns-06-help.md section 3.2; 06a section 2.2).
-- Original code for Panoply Suite.
--
-- Setup owns four questions about the character: how much the player has played (experience), the class plan, group quests and
-- the partner. Each answer is stored ONCE, in the saved value that already holds it, and every page reads it from there:
--   experience  PanoplySuiteCharDB.classExperience (1 to 4; the four levels of the Class page, CP.LEVELS). The Class page header's
--               "Written for" and the class write-ups read it; setup's new experience step (phase 4L) and the Class page's picker write it.
--   plan        the plan the character follows (Panoply.SpecTrainer:Tracked()); the Class header's "Plan" reads it.
--   style       0.9.7: the answer to "Group quests" (PanoplySuiteDB.groupQuests: "ask", "do" or "skip"; Engine/Difficulty.lua). The
--               answer keeps its old name "style" in A.KEYS so the pages that ask Answers:Missing() need no change; the levelling
--               styles themselves are gone and PanoplySuiteDB.levellingStyle is not read.
--   partner     PanoplySuiteDB.syncPartner and syncWaitForPartner.
-- One NEW per-character key: PanoplySuiteCharDB.setupSkipped = true when the player skipped setup on that character. The Class page's
-- first-run card (phase 4H) shows only then (or when setup has never run), and asks only Answers:Missing().
local ADDON, Panoply = ...
local A = {}
Panoply.Answers = A

A.KEYS = { "experience", "plan", "style", "partner" }
-- the four experience levels are the Class page's own (CP.LEVELS, Modules/ClassPages/Core.lua): one list, read when asked
A.LEVEL_COUNT = 4
function A.Levels() return Panoply.ClassPages and Panoply.ClassPages.LEVELS or nil end
local function validLevel(n) return n and n == math.floor(n) and n >= 1 and n <= A.LEVEL_COUNT end

local function cdb() return Panoply.cdb end

-- The saved answer, or nil when it was never given.
function A:Get(key)
  local c, db = cdb(), Panoply.db
  if key == "experience" then
    local n = c and tonumber(c.classExperience)
    return validLevel(n) and n or nil
  elseif key == "plan" then
    local ST = Panoply.SpecTrainer
    local ok, t = false, nil
    if ST and ST.Tracked then ok, t = pcall(ST.Tracked, ST) end
    return ok and type(t) == "table" and (t.key or t.name) or nil
  elseif key == "style" then
    return db and Panoply.Difficulty.GroupQuests() or nil
  elseif key == "partner" then
    if not db then return nil end
    if db.syncWaitForPartner == false and (db.syncPartner or "") == "" then return "" end
    return db.syncPartner
  end
  error("Answers:Get: unknown answer " .. tostring(key), 2)
end

-- The experience level the Class page writes for, 1 to 4: the saved answer, or 1 (New to the game) when none was given.
function A:Experience() return self:Get("experience") or 1 end

-- Save an answer (only experience is written here: the other three are saved by their own owners, setup's Finish and the pages).
-- Returns true when the value was valid and saved.
function A:Set(key, value)
  local c = cdb()
  if key == "experience" then
    local n = tonumber(value)
    if not validLevel(n) or not c then return false end
    local was = c.classExperience
    c.classExperience = n
    if was ~= n then Panoply:Fire("ANSWERS_CHANGED", "experience", n) end
    return true
  end
  error("Answers:Set: " .. tostring(key) .. " is saved by its own page", 2)
end

-- Setup on this character: "done" (finished), "skipped", or "never".
function A:SetupState()
  local c = cdb()
  if not c then return "never" end
  if c.setupSkipped then return "skipped" end
  if c.setupDone then return "done" end
  return "never"
end
function A:MarkSkipped()
  local c = cdb()
  if c then c.setupSkipped = true end
end
function A:MarkDone()
  local c = cdb()
  if c then c.setupSkipped = nil end
end

-- The questions setup did not answer on this character (for the Class page's first-run card): none when setup ran to the end.
-- Setup answers style and partner whenever it finishes; experience and plan only when given.
function A:Missing()
  local out = {}
  if self:SetupState() == "done" then
    if self:Get("experience") == nil then out[#out + 1] = "experience" end
    return out
  end
  for _, k in ipairs(A.KEYS) do
    if k == "style" or k == "partner" then out[#out + 1] = k
    elseif self:Get(k) == nil then out[#out + 1] = k end
  end
  return out
end

-- The Class page's first-run card shows only when setup was skipped or never run on this character, and something is missing.
function A:ClassCardWanted()
  local st = self:SetupState()
  if st == "done" then return false end
  local m = self:Missing()
  for _, k in ipairs(m) do if k == "experience" or k == "plan" then return true end end
  return false
end
