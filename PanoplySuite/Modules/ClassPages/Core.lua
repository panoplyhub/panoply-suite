-- Panoply Suite 0.8.4: the class pages. 0.9.5 phase 4H: ONE Class page (Class & Spec and the Class Guide merged, spec 03); see CP.TOPICS.
-- Before that: one page for each of the nine classes, all with the same layout: a row that says how much
-- you have played (remembered for the character), a fixed list of topics, and under the topic that is picked the write-up for that
-- class at that experience level. This file is the data side: the classes, the experience levels, the topics, what a write-up is
-- made of, and Panoply.ClassPages:Open(class, topic). The window is Modules/ClassPages/Page.lua; the write-ups are Data/<Class>.lua.
--
-- 0.9.4 (our items 4 and 5): a macro shows on a game only when tools/check_class_macros.lua passed it there (Data/Verified.lua), and
-- the Rotation topic carries a display-only next ability display (the 0.9.4 Rotation sequencer) card (Modules/ClassPages/Sequencer.lua, Data/Sequences.lua).
-- 0.9.4: the old Rotation panel (a secure cast-sequence button; Modules/Rotation/Panel.lua) is removed, so the Rotation topic is the
-- written advice and the sequencer card, and holds no other module's panel. Gear holds another module's panel when that module is in
-- the build, and a short placeholder when it is not:
--   Gear                Panoply.ClassGear:BuildPanel(parent)
-- What the parent is, and what BuildPanel may return, is at CP:Mount in Page.lua.
-- 0.9.1 (11 Nov 2026: no third menu level; the left list plus ONE row of top tabs; "why a diff page for hunters? Should be in
-- the class page"): the topics are that one row of tabs, the same seven on every class, and on the Hunter page an eighth, Pet:
--   Pet                 Panoply.HunterPet:BuildPanel(parent)    (Hunter only, when the pet module is in the build)
-- Pet's four parts (Families, Planner, To tame, Training points) are collapsible sections inside that one tab, not tabs, so the row
-- stays one row of whole names at 1.3x text.
--
-- A write-up is a list of blocks:
--   { "h", "Heading" }                  starts a new card with this small heading
--   { "p", "Text" }                     a paragraph, on both games
--   { "f", "Text" }                     a paragraph shown on WoW Forever only (marked "WoW Forever")
--   { "e", "Text" }                     a paragraph shown on Classic only (marked "Classic")
--   { "m", "Name", "macro text", "what it does" [, "f" | "e"] }   a macro (one game only with the fifth field)
-- A topic is { [1] = blocks, [2] = blocks, [3] = blocks, [4] = blocks, all = blocks }: the blocks of the experience level that is
-- picked come first, then the ones every level shares. Data/Shared.lua adds what all nine classes share on a topic.
local ADDON, Panoply = ...
local C = Panoply.Compat
local CP = { data = {} }
Panoply.ClassPages = CP

CP.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
CP.CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
  MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

-- the four experience levels, in the words we chose
-- (0.9.5 phase 4A4: one list, shared with setup's experience question: Core/Answers.lua reads this one; tools/check_class_macros.lua
-- loads this file on its own, without the rest of the add-on)
CP.LEVELS = { "New to the game", "Played before but never max level", "Max level but no raids", "Raids and endgame" }
CP.LEVEL_TIP = {
  "Plain words, and only what you need first.",
  "You know the basics. This is about getting to the top level smoothly.",
  "You have been to the top level. This is about dungeons and getting ready for more.",
  "For players who raided, here or in the modern game. Mostly what is different here.",
}

-- 0.9.5 phase 4H (docs/specs/page-redesigns-03-class.md): Class & Spec and the Class Guide are ONE page, "Class", with at most six tabs:
-- Overview, Talents, Spells, How to play, Gear and Pet (Pet only for a class with a pet system that Panoply Suite has data for: the
-- Hunter today; a Warlock's demons wait for their own spec). The old topics live on as sections of How to play (CP.HOWTO) and as names
-- that still open the right tab (CP.TOPIC_ALIAS: a door, a slash command or a search that says "rotation" or "class & spec").
-- own = true: the tab is about the character playing (its plan, its spells, its gear, its pet); reading another class shows only the
-- text tabs and one line in place of the others (spec 03 section 2.7).
CP.TOPICS = {
  { key = "overview", label = "Overview", tip = "What to do next for your class, and what your class is." },
  { key = "talents", label = "Talents", own = true, module = "SpecTrainer", tip = "Your plan's talent trees, the next point and the level-by-level list." },
  -- 0.9.9.4 (the builds shown everywhere they are needed): every suggested build of the class, on the shared build card
  { key = "builds", label = "Builds", own = true, module = "SpecTrainer", tip = "Every suggested talent build for your class, from public guides, by spec. Follow one or show it on the tree." },
  { key = "spells", label = "Spells", own = true, module = "SpecTrainer", tip = "What to buy at each trainer visit, with its cost, and what your plan skips." },
  { key = "howto", label = "How to play", short = "Play", tip = "Leveling, what to press, shots and spells, macros and group play." },
  { key = "gear", label = "Gear", own = true, tip = "What you wear, scored for your plan, and the next upgrades for every slot." },
  { key = "pet", label = "Pet", own = true, class = "HUNTER", module = "HunterPet", tip = "Your pet, its abilities, where to learn each rank, and the pet families." },
}
CP.TOPIC = {}
for _, t in ipairs(CP.TOPICS) do CP.TOPIC[t.key] = t end

-- How to play: one section index instead of more tabs (spec 03 section 6). topic: the write-up it shows (Data/<Class>.lua's own keys).
CP.HOWTO = {
  { key = "leveling", label = "Leveling", topic = "leveling" },
  { key = "press", label = "What to press", topic = "rotation" },
  { key = "shots", label = "Shots, aspects and traps", short = "Spells and abilities", topic = "spells" },
  { key = "macros", label = "Macros", topic = "macros" },
  { key = "group", label = "Group play", topic = "group" },
}
CP.HOWTO_BY = {}
for _, h in ipairs(CP.HOWTO) do CP.HOWTO_BY[h.key] = h end
-- the shots section's words are the class's own for its kind of spells ("Shots, aspects and traps" is the Hunter's)
CP.HOWTO_LABEL = { shots = { HUNTER = "Shots, aspects and traps", WARRIOR = "Stances and shouts", PALADIN = "Seals, blessings and auras",
  ROGUE = "Poisons and finishers", PRIEST = "Heals and shields", SHAMAN = "Totems and shocks", MAGE = "Spells and frost",
  WARLOCK = "Curses and demons", DRUID = "Forms and spells" } }
function CP:HowtoLabel(key, classFile)
  local by = self.HOWTO_LABEL[key]
  return by and by[classFile or ""] or (self.HOWTO_BY[key] and self.HOWTO_BY[key].label) or key
end

-- older names of the topics: { tab, How to play section }
CP.TOPIC_ALIAS = {
  leveling = { "howto", "leveling" }, rotation = { "howto", "press" }, press = { "howto", "press" }, macros = { "howto", "macros" },
  group = { "howto", "group" }, ["group play"] = { "howto", "group" }, ["spells & talents"] = { "howto", "shots" }, shots = { "howto", "shots" },
  ["how to play"] = { "howto" }, play = { "howto" }, plan = { "talents" }, talent = { "talents" }, ["talent planner"] = { "talents" },
  ["spells to buy"] = { "spells" }, trainer = { "spells" }, ["class & spec"] = { "talents" }, ["class and spec"] = { "talents" },
  ["talents & spells"] = { "talents" }, ["class guide"] = { "overview" }, class = { "overview" }, build = { "builds" },
  ["talent builds"] = { "builds" }, ["talent build"] = { "builds" },
}

-- the longest text a macro can hold
CP.MACRO_MAX = 255

CP.topic = "overview"

-------------------------------------------------------------------------------
-- The write-ups register themselves (Data/<Class>.lua)
-------------------------------------------------------------------------------
function CP:Register(classFile, data) self.data[classFile] = data end

-------------------------------------------------------------------------------
-- Which class, which topic, which experience level
-------------------------------------------------------------------------------
-- "HUNTER", "Hunter" and "hunter" all name the Hunter page; anything else is nil
function CP:ClassKey(class)
  if type(class) ~= "string" then return nil end
  local up = class:upper()
  if self.CLASS_NAME[up] then return up end
  return nil
end

-- "gear", "Gear", "How to play" and the older names ("rotation", "Group Play", "class & spec") name tabs; anything else is nil. The second
-- answer is the How to play section an older name stands for ("rotation" is How to play, What to press).
function CP:TopicKey(topic)
  if type(topic) ~= "string" then return nil end
  local low = topic:lower()
  if self.TOPIC[low] then return low end
  for _, t in ipairs(self.TOPICS) do if t.label:lower() == low then return t.key end end
  local a = self.TOPIC_ALIAS[low]
  if a then return a[1], a[2] end
  for _, h in ipairs(self.HOWTO) do if h.label:lower() == low then return "howto", h.key end end
  return nil
end

function CP:PlayerClass()
  local ok, p = pcall(C.PlayerInfo)
  return ok and type(p) == "table" and self:ClassKey(p.classFile) or nil
end

-- the class whose page shows: the one that was picked, or the character's own
function CP:ViewClass()
  return self.viewClass or self:PlayerClass() or self.CLASSES[1]
end

-- a tab is on the class page: its class (when it has one), the module it needs (when it needs one) and, for a tab about the character
-- playing (own), that the page shows the character's own class (reading another class shows the text tabs only)
function CP:HasTopic(t, classFile)
  if not t then return false end
  classFile = classFile or self:ViewClass()
  if t.class and t.class ~= classFile then return false end
  if t.module and type(Panoply[t.module]) ~= "table" then return false end
  if t.own and classFile ~= self:PlayerClass() then return false end
  return true
end

-- the How to play section that shows (remembered for the play session: CP.howto)
function CP:HowtoSection()
  return self.HOWTO_BY[self.howto or ""] and self.howto or "leveling"
end
function CP:SetHowtoSection(key)
  if not self.HOWTO_BY[key or ""] then return false end
  self.howto = key
  return true
end

-- the topics of a class page, in menu order
function CP:Topics(classFile)
  local out = {}
  for _, t in ipairs(self.TOPICS) do
    if self:HasTopic(t, classFile) then out[#out + 1] = t end
  end
  return out
end

-- the topic that shows on this class page (a topic this class page does not have falls back to Overview)
function CP:ViewTopic(classFile)
  local t = self.TOPIC[self.topic or ""]
  if not t or not self:HasTopic(t, classFile or self:ViewClass()) then return "overview" end
  return t.key
end

-- 1 to 4; kept for the character as PanoplySuiteCharDB.classExperience. 0.9.5 phase 4A4: that is the shared setup answer (Core/Answers.lua),
-- so setup's experience question and this page's picker write the same value, and the page's "Written for" reads it.
function CP:Experience()
  if Panoply.Answers then return Panoply.Answers:Experience() end
  local n = Panoply.cdb and tonumber(Panoply.cdb.classExperience)
  return (n and self.LEVELS[n]) and n or 1
end

function CP:SetExperience(n)
  if Panoply.Answers then return Panoply.Answers:Set("experience", n) end
  return false
end

function CP:SetClass(class)
  local k = self:ClassKey(class)
  if not k then return false end
  self.viewClass = k
  return true
end

function CP:SetTopic(topic)
  local k, sec = self:TopicKey(topic)
  if not k then return false end
  self.topic = k
  if sec then self.howto = sec end
  return true
end

-------------------------------------------------------------------------------
-- The blocks of one topic of one class at one experience level, for the game that is running
-------------------------------------------------------------------------------
CP.GAME_TAG = { f = "WoW Forever", e = "Classic" }

function CP:Blocks(classFile, topicKey, level, forever)
  if forever == nil then forever = C.IsForever() and true or false end
  local out = {}
  local topic = (self.data[classFile] or {})[topicKey]
  if type(topic) ~= "table" then return out end   -- Gear and Pet have no write-up of their own: they hold a panel
  local function take(list)
    for _, b in ipairs(list or {}) do
      local kind = b[1]
      if kind == "h" then out[#out + 1] = { kind = "h", text = b[2] }
      elseif kind == "p" then out[#out + 1] = { kind = "p", text = b[2] }
      elseif kind == "f" or kind == "e" then
        if (kind == "f") == forever then out[#out + 1] = { kind = "p", text = b[2], tag = self.GAME_TAG[kind] } end
      elseif kind == "m" then
        local only = b[5]
        -- 0.9.4: a macro is shown only when the checker passed it on this game (Data/Verified.lua, written by
        -- tools/check_class_macros.lua); no list, or a macro not on it, means it is not shown
        if (only == nil or (only == "f") == forever) and self:MacroVerified(classFile, b[3], forever) then
          out[#out + 1] = { kind = "m", name = b[2], body = b[3], note = b[4] }
        end
      end
    end
  end
  level = level or self:Experience()
  -- what every class shares on this topic (Data/Shared.lua): some of it before the class's own words, some after
  local shared = self.shared and self.shared[topicKey] or {}
  local before, after = shared.before or {}, shared.after or {}
  take(before[level]); take(before.all)
  take(topic[level])
  take(topic.all)
  take(after[level]); take(after.all)
  return out
end

-- 0.9.4: did this macro pass tools/check_class_macros.lua on this game? (Data/Verified.lua)
function CP:MacroVerified(classFile, body, forever)
  local v = self.verified and self.verified[forever and "forever" or "era"]
  return v ~= nil and v.macros[classFile .. "|" .. body] == true
end

-- 0.9.4: the rotation sequences of a class for one game, with every step the checker did not pass on that game left out and
-- any sequence left with no step dropped: { { key, label, steps = { { name, note, once } } } } (Data/Sequences.lua)
function CP:Sequences(classFile, forever)
  if forever == nil then forever = C.IsForever() and true or false end
  local v = self.verified and self.verified[forever and "forever" or "era"]
  local out = {}
  for _, seq in ipairs(v and self.sequences and self.sequences[classFile] or {}) do
    local steps = {}
    for _, st in ipairs(seq.steps) do
      local name = self:StepName(st, forever)
      if v.steps[classFile .. "|" .. name] then steps[#steps + 1] = { name = name, note = st[2], once = st.once and true or false } end
    end
    if #steps > 0 then out[#out + 1] = { key = seq.key, label = seq.label, steps = steps } end
  end
  return out
end

-- every macro of a class, on either game: { { name, body, note, only, level, topic } } (the tests read this)
function CP:Macros(classFile)
  local out = {}
  for topicKey, topic in pairs(self.data[classFile] or {}) do
    for _, where in ipairs({ 1, 2, 3, 4, "all" }) do
      for _, b in ipairs(type(topic) == "table" and topic[where] or {}) do
        if b[1] == "m" then out[#out + 1] = { name = b[2], body = b[3], note = b[4], only = b[5], level = where, topic = topicKey } end
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- The door
-------------------------------------------------------------------------------
-- Panoply.ClassPages:Open(class, topic): the Class page of a class ("HUNTER" or "Hunter"; nil = the character's own class) on a tab
-- ("gear", "Talents", "How to play", or an older name: "rotation" opens How to play at What to press; nil = the tab that was showing).
-- A class or tab that does not exist changes nothing; a tab this class page does not have (Pet for a Mage, Talents while reading
-- another class) opens the Overview. Returns the page, or nil when the menu is not in this build.
function CP:Open(class, topic)
  if class == nil then self.viewClass = self:PlayerClass() or self.viewClass
  else self.viewClass = self:ClassKey(class) or self.viewClass end
  local k = self:TopicKey(topic)
  if k and not self:HasTopic(self.TOPIC[k], self:ViewClass()) then topic = "overview" end
  if topic ~= nil then self:SetTopic(topic) end
  if not (Panoply.Menu and Panoply.Menu.Open) then return nil end
  return Panoply.Menu:Open("class")
end
