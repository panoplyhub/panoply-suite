-- Panoply Suite setup (Step 2, item A: "Welcome and setup", docs/step2/ABC-SPEC.md section A).
--
-- Two things live in this one window (PanoplySuiteWizard):
--   * the first page (mode "thanks"), in two kinds:
--       - the welcome page (0.9.6 item 5, Nov 16 2026: "a very short intro, Panoply Suite page and then into the setup ... a
--         splash page maybe? ... It should pickup whether they have alts or this is their very first character"): every character
--         that still has to be set up sees it once (PanoplySuiteCharDB.welcomeShown, 0.9.6 phase H), after a splash of
--         W.SPLASH_SECONDS (a click skips it). It counts as seen only once the welcome page itself was on screen, or "Set up" was
--         clicked; until then every way of opening setup shows the splash and the welcome first (W:Start), and the first run waits
--         for a cinematic to end and comes back after one closed it (a new character's intro: the game closes every window). What it says depends on W:AltState(): "alts" when Panoply Suite already knows other characters on this
--         account (it names them), "first" when it knows none. It shows what the suite does, "Set up <character>" (opens step 1)
--         and the off switch (UI/Minimap.lua). Nothing is asked on it.
--       - the thank-you page, once per account (PanoplySuiteDB.thanksSeen), for a character that already finished setup (an
--         account updated from 0.7.3.6 or earlier: our decision #19): the approved sentences and "Close".
--   * the setup: five short steps for the character being played (0.9.5 phase 4L, spec 06a section 1), each already answered:
--       1 settings (a profile: same as my other characters / a saved profile / start fresh). Left out when there is nothing to
--         choose (no other character on the account, or only one profile): then the counter reads "Step 1 of 4".
--       2 experience: how much have you played (the Class page's four levels; saved once, Core/Answers.lua)
--       3 class plan (the ready-made plans for the class, from Modules/SpecTrainer/Specs.lua; WizardPage.lua). Recommended goes on the
--         plan that suits the answer to step 2.
--       4 group quests (0.9.7: the levelling styles are gone; three cards, Ask me each time / Always include them / Leave them
--         out, saved as PanoplySuiteDB.groupQuests; UI/Settings.lua has the words)
--       5 solo or partner, the choices as labelled lines, and Start guiding
--     One "Skip setup" button is on every step; its tooltip says exactly what it applies. Nothing changes until Start guiding (or
--     Skip setup); the same steps run again from Help ("Run setup").
-- Automation (auto accept / hand in / fly) is not asked here any more: it stays in the Guide gear with its defaults.
-- Professions are not asked either: Panoply Suite reads them from your skills (Engine/ProfDetect.lua).
local ADDON, Panoply = ...
local W = { page = 1, pages = {}, built = {}, mode = nil }
Panoply.Wizard = W
local Skin, C = Panoply.Skin, Panoply.Compat
local SP = Skin.SP

W.ORDER = { "settings", "experience", "plan", "group", "partner" }
W.TITLES = { settings = "Settings", experience = "Experience", plan = "Class plan", group = "Group quests", partner = "Partner" }
-- the plan step is added by Modules/SpecTrainer/WizardPage.lua (W.builders.plan); without that module on it is left out
W.SIZE = { setup = { 720, 600 }, thanks = { 560, 480 }, welcome = { 620, 520 } }
W.SPLASH_SECONDS = 1.5          -- 0.9.6 item 5: how long the splash shows before the welcome page (a click skips it)
W.TIME = "About 30 seconds"     -- shown on the first step only (spec 06a 2.6)
W.SKIP_TEXT = "Skip setup"      -- the one skip button (spec 06a 2.6); what it applies is its tooltip
-- our decision #7 (2026-11-04): the three proposed sentences of the thank-you page
W.THANKS = {
  "Panoply Suite is free. It has no ads, and it never goes online.",
  "It plans your quest route and shows one clear step at a time. It only does what you click or press, as the game's rules ask.",
  "Next, a few quick questions about %s. They take about 30 seconds, and one button skips them.",
}
-- our decision #19 (2026-11-04), "Thank-you, no setup": the third sentence when no setup follows (wording is new: we may change it)
W.THANKS_CLOSE = "Nothing needs setting up: %s keeps the settings you already have. You can run the setup again any time from Help."
W.FINE = "From Ostrowski Holdings LLC. For WoW Forever."
-- 0.9.6 item 5: the splash and the welcome page.
-- PLACEHOLDER COPY (Marketing): everything in W.SPLASH and W.WELCOME (the wording comes from Panoply Marketing)
W.SPLASH = { title = "Panoply Suite", tagline = "Everything for your adventure, in one place." }
W.WELCOME = {
  head = { first = "Welcome to Panoply Suite", alts = "Welcome, %s" },
  lead = {
    first = "This looks like your first character with Panoply Suite. Here is what it does for you.",
    alts = "Panoply Suite already knows %s: %s. %s can share their settings, or start fresh.",
  },
  tiles = {
    -- each tile has the icon of the page it is about (the Kit's icon slots, as on Home; icon is the fallback)
    { icon = "Leveling", title = "Your route", text = "One clear step at a time, and an arrow to follow." },
    { slot = "icon.tile.upgrade", icon = "Character", title = "Your class", text = "Plans, talents, spells and gear upgrades." },
    { slot = "icon.tile.gold", icon = "Coin", title = "Your characters", text = "Gold, bags and progress for every character." },
    { slot = "icon.tile.prices", icon = "Auctions", title = "Auctions", text = "Prices and upgrades from the auction house." },
  },
  off = "Not for you right now? Turn Panoply Suite off",
  offTip = "Turns Panoply Suite off (the game reloads its interface). Nothing is lost, and the game's AddOns list turns it back on.",
}
-- 0.9.9.4 (the builds are shown the same way everywhere, setup included): the own path is "Plan by hand", as on the Class page
W.OWN_TEXT = "Plan by hand"
W.OWN_TIP = "The Class page opens on its Talents tab when setup ends: click talents in the order you want them."
-- the four answers to "How much have you played?": the Class page's own levels (Modules/ClassPages/Core.lua CP.LEVELS), one line each
W.EXPERIENCE_TEXT = {
  "Your first time playing World of Warcraft.",
  "You have played before, but never reached the top level.",
  "You reached the top level, but have not raided.",
  "You raid and play the endgame.",
}
-- 0.9.7 (Nov 18 2026): step 4, the three Group quests cards. The names and the cards' lines are UI/Settings.lua's (SUI.GROUP_QUESTS),
-- so setup and the Guide page's settings never disagree.
W.GROUP_HEAD = "What should the guide do with group quests?"
W.GROUP_INTRO = "Some quests need a group, such as elite and dungeon quests."
W.GROUP_NOTE = "You can change this any time in the Guide page's settings."
-- the choice inside a sentence (the Skip setup tooltip)
W.GROUP_PHRASE = { ask = "ask me about group quests", ["do"] = "always include group quests", skip = "leave group quests out" }
-- the partner step's line (0.9.7: what Level together does on WoW Forever)
W.PARTNER_INTRO = "You see each other's progress, wait for each other at turn-ins, and can sync to the same step."
local MAX_PICKS = 8
local BOOK_TOP, BOOK_BOTTOM = 64, 66     -- the card's gap above and below it inside the window (0.9.5: no skip line under it any more)

local function copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
local function has(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
local TH = function(fs, w) return Skin.TextHeight(fs, w) end

-------------------------------------------------------------------------------
-- Words and facts
-------------------------------------------------------------------------------
function W:CharName()
  local ok, info = pcall(C.PlayerInfo)
  local n = ok and type(info) == "table" and info.name
  return (type(n) == "string" and n ~= "") and n or "this character"
end

function W:PlanActive()
  local ST = Panoply.SpecTrainer
  return ST ~= nil and W.builders.plan ~= nil and Panoply.Modules:IsOn("spectrainer")
end

-- Is there anything to choose on step 1? Not on the account's first character, and not while only one profile exists (spec 06a 1).
function W:ProfileStepNeeded()
  local P = Panoply.Profiles
  if not P then return false end
  if P:Count() <= 1 then return false end
  return #self:OtherChars() > 0
end

-- the steps that run now (the plan step only when the Spec & Trainer module is on; the profile step only when it has a choice)
function W:Steps()
  local out = {}
  for _, n in ipairs(self.ORDER) do
    if (n ~= "plan" or self:PlanActive()) and (n ~= "settings" or self:ProfileStepNeeded()) and (n ~= "experience" or Panoply.Answers ~= nil) then
      out[#out + 1] = n
    end
  end
  return out
end

-- "Aldric, Brannoch, Tessa and Wren" (at most four names, then "and 2 more")
local function nameList(names)
  local n = #names
  if n == 0 then return "" end
  if n == 1 then return names[1] end
  local shown = {}
  for i = 1, math.min(n, 4) do shown[i] = names[i] end
  if n > 4 then return table.concat(shown, ", ") .. (" and %d more"):format(n - 4) end
  return table.concat(shown, ", ", 1, #shown - 1) .. " and " .. shown[#shown]
end

-- The other characters that use a profile.
function W:OthersOn(profile)
  local P = Panoply.Profiles
  local out = {}
  if not P then return out end
  for _, c in ipairs(P:UsedBy(profile)) do
    if not c.me then out[#out + 1] = c.name end
  end
  return out
end

-- The account's other characters (not the one being played): { realm, name }.
function W:OtherChars()
  local P = Panoply.Profiles
  local out = {}
  if not P then return out end
  local ok, list = pcall(P.Characters, P)
  for _, c in ipairs(ok and list or {}) do if not c.me then out[#out + 1] = c end end
  return out
end

-- 0.9.6 item 5: is this the account's first character, as far as Panoply Suite knows? -> "alts" or "first", and the other characters'
-- names. Panoply Suite can only know a character that has logged in with it: on a fresh install every character is "first" until
-- the others have logged in once.
function W:AltState()
  local names = {}
  for _, c in ipairs(self:OtherChars()) do if type(c.name) == "string" and c.name ~= "" then names[#names + 1] = c.name end end
  table.sort(names)
  return #names > 0 and "alts" or "first", names
end

-- The profile most of the account's other characters use (spec 06a 2.1), and every profile they use with its characters, most used
-- first: { { profile, names = { ... } }, ... }. A tie goes to the profile the last finished setup chose, then Default, then by name.
-- nil when there is no other character.
function W:MajorityProfile()
  local P = Panoply.Profiles
  local others = self:OtherChars()
  if not P or #others == 0 then return nil, {} end
  local by, groups = {}, {}
  for _, c in ipairs(others) do
    local pr = P:Of(c.realm, c.name)
    local g = by[pr]
    if not g then g = { profile = pr, names = {} } by[pr] = g groups[#groups + 1] = g end
    g.names[#g.names + 1] = c.name
  end
  local last = Panoply.db and type(Panoply.db.setupLast) == "table" and Panoply.db.setupLast.profile or nil
  table.sort(groups, function(a, b)
    if #a.names ~= #b.names then return #a.names > #b.names end
    if (a.profile == last) ~= (b.profile == last) then return a.profile == last end
    if (a.profile == P.DEFAULT) ~= (b.profile == P.DEFAULT) then return a.profile == P.DEFAULT end
    return a.profile < b.profile
  end)
  return groups[1].profile, groups
end

-- What the "Same as my other characters" card says: "Most of your characters use Default (Durgrim, Magni). Vaelor uses Forever."
function W:SameText()
  local top, groups = self:MajorityProfile()
  if not top then return nil end
  if #groups == 1 then
    local g = groups[1]
    if #g.names == 1 then return ("Your other character uses %s (%s)."):format(g.profile, g.names[1]) end
    return ("Your other characters use %s (%s)."):format(g.profile, nameList(g.names))
  end
  local out = { ("Most of your characters use %s (%s)."):format(groups[1].profile, nameList(groups[1].names)) }
  for i = 2, #groups do
    local g = groups[i]
    out[#out + 1] = ("%s use%s %s."):format(nameList(g.names), #g.names == 1 and "s" or "", g.profile)
  end
  return table.concat(out, " ")
end

-- Every profile except the one "Same as my other characters" means.
function W:OtherProfiles()
  local P = Panoply.Profiles
  local out = {}
  if not P then return out end
  -- with no other character there is no "Same as my other characters": every profile can be picked
  local usual = self:MajorityProfile() and (self.usual and self.usual.profile or P.DEFAULT) or nil
  for _, n in ipairs(P:Names()) do if n ~= usual then out[#out + 1] = n end end
  return out
end

-- The profile the character being played uses now (nil until the game says who it is).
function W:CurrentProfile()
  local P = Panoply.Profiles
  if not P then return nil end
  local mr, mn = P:Me()
  if not mr then return nil end
  return P:Of(mr, mn)
end

-- The name "Start fresh" will give the new profile: the character's name, or "<name> 2" and so on when taken.
function W:FreshName()
  local P = Panoply.Profiles
  local base = P.Clean(self:CharName()) or "New profile"
  local name, n = base, 2
  while not P:Valid(name) and n < 60 do name = ("%s %d"):format(base, n) n = n + 1 end
  return name
end
function W:CanStartFresh()
  local P = Panoply.Profiles
  return P ~= nil and P:Count() < P.MAX_PROFILES
end

-- The profile a set of choices ends up on (the name only; nothing is made or switched here).
function W:ProfileOf(ch)
  local P = Panoply.Profiles
  ch = ch or self.choices
  if not P then return "Default" end
  if ch.profile == "fresh" then return self:FreshName() end
  if ch.profile == "saved" and P:Exists(ch.profileName) then return ch.profileName end
  local u = self.usual and self.usual.profile or P.DEFAULT
  return P:Exists(u) and u or P.DEFAULT
end

function W:PlanName(key)
  local ST = Panoply.SpecTrainer
  if key == nil or key == ST.OWN_PICK then return W.OWN_TEXT end
  local p = ST:Find(key)
  return p and p.name or W.OWN_TEXT
end

-- Group quests: a valid choice ("ask" | "do" | "skip") or the saved one, and its words
function W:GroupKey(key)
  local G = Panoply.SettingsUI.GROUP_QUESTS
  return G.names[key] and key or Panoply.SettingsUI.GroupQuests()
end
function W:GroupName(key) return Panoply.SettingsUI.GROUP_QUESTS.names[self:GroupKey(key)] end

function W:PartnerPhrase(ch)
  if ch.solo then return "playing solo" end
  if (ch.partner or "") ~= "" then return "playing with " .. ch.partner end
  return "playing with anyone in my group"
end

-- The answers as words: { profile, plan?, group quests, partner }
function W:Parts(ch)
  local parts = { "profile " .. self:ProfileOf(ch) }
  if self:PlanActive() then parts[#parts + 1] = self:PlanName(ch.spec) end
  parts[#parts + 1] = W.GROUP_PHRASE[self:GroupKey(ch.group)]
  parts[#parts + 1] = self:PartnerPhrase(ch)
  return parts
end

-- the experience answer's words ("New to the game"), or nil without the Class page's levels
function W:ExperienceName(n)
  local L = Panoply.Answers and Panoply.Answers.Levels()
  return L and L[tonumber(n) or 1] or nil
end

-- the partner as the summary's last line says it: "none", "Nyxira" or "anyone in my group"
function W:PartnerShort(ch)
  if ch.solo then return "none" end
  if (ch.partner or "") ~= "" then return ch.partner end
  return "anyone in my group"
end

-- The summary on the last step, as labelled lines (spec 06a 2.5): { { "Profile", "Default" }, { "Experience", ... }, ... }
function W:SummaryRows(ch)
  ch = ch or self.choices
  local rows = { { "Profile", self:ProfileOf(ch) } }
  local ex = self:ExperienceName(ch.experience)
  if ex and has(self:Steps(), "experience") then rows[#rows + 1] = { "Experience", ex } end
  if self:PlanActive() then rows[#rows + 1] = { "Plan", self:PlanName(ch.spec) } end
  rows[#rows + 1] = { "Group quests", self:GroupName(ch.group) }
  rows[#rows + 1] = { "Partner", self:PartnerShort(ch) }
  return rows
end

-- The summary in one string: "Profile: Default · Experience: New to the game · Plan: Build my own later · Group quests: Ask me each time · Partner: none"
function W:SummaryText(ch)
  local out = {}
  for _, r in ipairs(self:SummaryRows(ch)) do out[#out + 1] = r[1] .. ": " .. r[2] end
  return table.concat(out, " \194\183 ")
end

-- The "Skip setup" button's tooltip: exactly what it applies.
function W:UsualChoices()
  local u = self.usual or self:Usual()
  return { profile = "same", spec = u.spec, group = u.group, solo = u.solo, partner = u.partner }
end
function W:SkipLine()
  if self.rerun then return ("Skip: keep what %s uses now."):format(self:CharName()) end
  return "Skip, use my usual means: " .. table.concat(self:Parts(self:UsualChoices()), ", ") .. "."
end

-------------------------------------------------------------------------------
-- "My usual" and the starting choices
-------------------------------------------------------------------------------
-- My usual = what the last character that finished setup chose (PanoplySuiteDB.setupLast); with none yet, the standard
-- choices of a fresh account (Default profile, the class's default plan, Ask me each time, solo). The plan is the class's
-- default plan when the class differs from that character's (SpecTrainer:WizardUsual).
function W:Usual()
  local db, P = Panoply.db, Panoply.Profiles
  local last = type(db.setupLast) == "table" and db.setupLast or nil
  local u = { profile = P and P.DEFAULT or "Default" }
  if last and P and type(last.profile) == "string" and P:Exists(last.profile) then u.profile = last.profile end
  -- 0.9.5 phase 4L (spec 06a 2.1): "Same as my other characters" is the profile most of them use; with no other character, the one
  -- this character has now (nothing changes)
  local major = self:MajorityProfile()
  if major and P and P:Exists(major) then u.profile = major
  elseif P and not major then u.profile = self:CurrentProfile() or u.profile end
  -- group quests: what the last setup chose (a setup from before 0.9.7 chose a style, not this: then the saved setting)
  u.group = self:GroupKey(last and last.group)
  if last then
    u.solo = last.solo ~= false
    u.partner = u.solo and "" or tostring(last.partner or "")
  else
    -- nobody finished setup yet on this account. A brand-new account (db.newAccount, set when the thank-you first showed
    -- on an empty account) gets the standard choices of decision #2: solo. An account that already had
    -- settings keeps its own: "no partner" with waiting on is "anyone in my group", not solo, so nothing is reset
    u.partner = db.syncPartner or ""
    u.solo = u.partner == "" and (db.newAccount == true or db.syncWaitForPartner == false)
  end
  if self:PlanActive() then u.spec = Panoply.SpecTrainer:WizardUsual(last) end
  return u
end

function W:InitChoices()
  local db = Panoply.db
  local u = self:Usual()
  self.usual = u
  local ch
  self.rerun = (Panoply.cdb and Panoply.cdb.setupDone) and true or false
  if self.rerun then
    -- running it again: the answers are what this character really has now, so Start guiding changes nothing by itself.
    -- Just me only when the player is really solo (no partner and not waiting for one); an empty partner name with waiting
    -- on is the default, "anyone in my group"
    ch = { profile = "same", group = self:GroupKey(), partner = db.syncPartner or "" }
    ch.solo = ch.partner == "" and db.syncWaitForPartner == false
    local cur = self:CurrentProfile()
    if cur and cur ~= u.profile then ch.profile, ch.profileName = "saved", cur end
    if self:PlanActive() then ch.spec = Panoply.SpecTrainer:WizardDefault() end
  else
    ch = { profile = "same", group = u.group, partner = u.partner, solo = u.solo, spec = u.spec }
  end
  ch.profileName = ch.profileName or self:OtherProfiles()[1]
  -- step 2: the saved answer when there is one, else the first level (New to the game). Saved only by Start guiding.
  ch.experience = Panoply.Answers and Panoply.Answers:Get("experience") or 1
  self.choices = ch
end

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
function W:Create()
  if self.frame then return self.frame end
  local sz = W.SIZE.setup
  local f = Skin.Window("PanoplySuiteWizard", sz[1], sz[2], "Set up", "")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  Panoply.Windows:OwnPlace(f)      -- 0.9.5: setup stays in the middle of the screen, above everything
  self.frame = f
  if f.HookScript then f:HookScript("OnHide", function() W:NoteHidden() end) end   -- 0.9.6 phase H: hidden by a cinematic (W:Resume)
  self.stepText = Skin.Ink(f, 12, Skin.colors.inkSoft)
  self.stepText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -18)
  if self.stepText.SetJustifyH then self.stepText:SetJustifyH("RIGHT") end
  local page = Skin.Card(f)
  page:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -BOOK_TOP)
  page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, BOOK_BOTTOM)
  self.book = page
  self.back = Skin.Button(f, "Back", 110, 34, function() W:Back() end, "Back", "Go to the previous step. Nothing is lost.")
  self.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
  -- one skip wording (spec 06a 2.6): "Skip setup" skips the whole setup, on any step; what it applies is its tooltip
  self.skip = Skin.Button(f, W.SKIP_TEXT, 150, 34, function() W:Skip() end, W.SKIP_TEXT, "")
  self.next = Skin.Button(f, "Next", 130, 34, function() W:Next() end, "Next", "Go to the next step.")
  self.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
  -- five dots: a bright one for this step, dim ones for the others
  self.pips = {}
  for k = 1, #self.ORDER do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(8, 8)
    self.pips[k] = t
  end
  return f
end

local function sizeTo(self, which, h)
  local f = self.frame
  local sz = W.SIZE[which]
  f:SetSize(sz[1], h or sz[2])
  if Panoply.Windows and Panoply.Windows.Apply then Panoply.Windows:Apply(f) end
end

-- the setup's own parts shown or hidden, for the thank-you page and the steps
local function setupParts(self, on)
  for _, o in ipairs({ self.book, self.back, self.skip, self.next, self.stepText }) do
    if on then o:Show() else o:Hide() end
  end
  for _, t in ipairs(self.pips) do if on then t:Show() else t:Hide() end end
  if self.thanks then if on then self.thanks:Hide() else self.thanks:Show() end end
  if on then self:EndSplash() end
end

-------------------------------------------------------------------------------
-- The thank-you page
-------------------------------------------------------------------------------
function W:BuildThanks()
  if self.thanks then return self.thanks end
  local f = self.frame
  local t = CreateFrame("Frame", nil, f)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  t.crest = t:CreateTexture(nil, "OVERLAY"); t.crest:SetSize(64, 64); Skin.Logo(t.crest)
  t.head = Skin.Ink(t, 22, Skin.colors.inkTitle); t.head:SetText("Thank you for using Panoply Suite")
  t.paras = {}
  for i = 1, #W.THANKS do t.paras[i] = Skin.Ink(t, 14) end
  t.go = Skin.Button(t, "Set up", 240, 40, function() if W.thanksClose then W.frame:Hide() else W:MarkWelcomeShown() W:Start() end end, "Set up",
    "Open the four short setup questions for this character.")
  t.fine = Skin.Ink(t, 11, Skin.colors.inkSoft); t.fine:SetText(W.FINE)
  -- 0.9.6 item 5: the welcome page's lead line and its four tiles (what the suite does)
  t.lead = Skin.Ink(t, 14)
  t.tiles = {}
  for i = 1, #W.WELCOME.tiles do
    local tile = CreateFrame("Frame", nil, t)
    tile.panoplyBox = true
    tile.bg = Skin.Box(tile, "S", { fill = Skin.colors.surface1 or Skin.colors.button, fillA = 1, line = Skin.colors.hairline, layer = "BACKGROUND", lineLayer = "BORDER" })
    tile.icon = tile:CreateTexture(nil, "ARTWORK"); tile.icon:SetSize(24, 24)
    tile.title = Skin.Text(tile, 13, Skin.colors.text, nil, "semi")
    tile.text = Skin.Ink(tile, 11, Skin.colors.inkSoft)
    for _, fs in ipairs({ tile.title, tile.text }) do if fs.SetJustifyH then fs:SetJustifyH("LEFT") end end
    t.tiles[i] = tile
  end
  -- 0.9.6 item 4: the off switch, on the first page every player sees (a quiet text button, not a second big button)
  local off = CreateFrame("Button", nil, t)
  off.label = Skin.Ink(off, 12, Skin.colors.inkSoft)
  off.label:SetPoint("CENTER", off, "CENTER", 0, 0)
  if off.label.SetJustifyH then off.label:SetJustifyH("CENTER") end
  off.label:SetText(W.WELCOME.off)
  Skin.Tooltip(off, "Turn Panoply Suite off", W.WELCOME.offTip)   -- PLACEHOLDER COPY (Marketing): the title (offTip is in W.WELCOME)
  off:SetScript("OnClick", function() if Panoply.Minimap and Panoply.Minimap.AskTurnOff then Panoply.Minimap:AskTurnOff() end end)
  off:SetScript("OnEnter", function(self)
    local c = Skin.colors.text or { 1, 1, 1 } self.label:SetTextColor(c[1], c[2], c[3], 1)
    if self.panoplyShowTip then self.panoplyShowTip() end
  end)
  off:SetScript("OnLeave", function(self)
    local c = Skin.colors.inkSoft or { 0.7, 0.7, 0.7 } self.label:SetTextColor(c[1], c[2], c[3], 1)
    if _G.GameTooltip then GameTooltip:Hide() end
  end)
  t.off = off
  for _, fs in ipairs({ t.head, t.fine, t.lead, unpack(t.paras) }) do if fs.SetJustifyH then fs:SetJustifyH("CENTER") end end
  self.thanks = t
  return t
end

local function center(t, fs, width, y)
  fs:ClearAllPoints(); fs:SetPoint("TOP", t, "TOP", 0, y); fs:SetWidth(width)
  local h = math.ceil(TH(fs, width)); fs:SetHeight(h)
  return y - h
end

-- the off switch line under the button
local function layoutOff(t, cw, y)
  local off = t.off
  local lw = math.min(cw, math.ceil(Skin.TextWidth(off.label)) + 8)
  off.label:SetWidth(lw)
  local lh = math.ceil(TH(off.label, lw)); off.label:SetHeight(lh)
  off:SetSize(lw, math.max(20, lh + 6))
  off:ClearAllPoints(); off:SetPoint("TOP", t, "TOP", 0, y)
  off:Show()
  return y - math.max(20, lh + 6)
end

-- The thank-you page (a character that finished setup; our decisions #7 and #19): the approved sentences and Close.
function W:LayoutThanks()
  local f, t = self.frame, self.thanks
  local w = W.SIZE.thanks[1]
  local cw = w - 100
  local name = self:CharName()
  t.lead:Hide()
  for _, tile in ipairs(t.tiles) do tile:Hide() end
  t.head:SetText("Thank you for using Panoply Suite")
  for i, fs in ipairs(t.paras) do fs:SetText(((self.thanksClose and i == #W.THANKS) and W.THANKS_CLOSE or W.THANKS[i]):format(name)) fs:Show() end
  t.go.label:SetText(self.thanksClose and "Close" or ("Set up " .. name))
  t.go.tip = self.thanksClose and "Close" or ("Set up " .. name)
  t.go.tipBody = self.thanksClose and "Close this window. Nothing was changed." or "Open the four short setup questions for this character."
  local y = -(f.panoplyHeaderBottom or 52) - 30
  t.crest:SetSize(64, 64)
  t.crest:ClearAllPoints(); t.crest:SetPoint("TOP", t, "TOP", 0, y); y = y - 64 - SP.xl
  y = center(t, t.head, w - 60, y) - SP.l
  for _, fs in ipairs(t.paras) do y = center(t, fs, cw, y) - SP.m end
  y = y - SP.xl
  local bw, bh = Skin.FitButton(t.go, 240, cw)
  t.go:ClearAllPoints(); t.go:SetPoint("TOP", t, "TOP", 0, y); y = y - bh - SP.s
  y = layoutOff(t, cw, y) - SP.s
  y = center(t, t.fine, cw, y) - SP.xl
  sizeTo(self, "thanks", math.max(-y, 400))
end

-- 0.9.6 item 5: the welcome page (a character still to be set up), for the first character or one with alts.
function W:LayoutWelcome()
  local f, t = self.frame, self.thanks
  local w = W.SIZE.welcome[1]
  local cw = w - 80
  local name = self:CharName()
  local kind, names = self:AltState()
  self.altState, self.altNames = kind, names
  local WL = W.WELCOME
  t.head:SetText(kind == "alts" and WL.head.alts:format(name) or WL.head.first)
  if kind == "alts" then
    local count = #names == 1 and "1 of your characters" or ("%d of your characters"):format(#names)
    t.lead:SetText(WL.lead.alts:format(count, nameList(names), name))
  else
    t.lead:SetText(WL.lead.first)
  end
  t.lead:Show()
  -- the approved third sentence (our decision #7) says what comes next; the first two are the thank-you page's
  for i, fs in ipairs(t.paras) do if i == #W.THANKS then fs:SetText(W.THANKS[i]:format(name)) fs:Show() else fs:Hide() end end
  t.go.label:SetText("Set up " .. name)
  t.go.tip = "Set up " .. name
  t.go.tipBody = "Open the short setup questions for this character."   -- PLACEHOLDER COPY (Marketing)
  local y = -(f.panoplyHeaderBottom or 52) - 18
  t.crest:SetSize(52, 52)
  t.crest:ClearAllPoints(); t.crest:SetPoint("TOP", t, "TOP", 0, y); y = y - 52 - SP.l
  y = center(t, t.head, w - 60, y) - SP.s
  y = center(t, t.lead, cw, y) - SP.l
  -- the tiles: two columns, one row height each
  local gap = SP.s
  local tw = math.floor((cw - gap) / 2)
  local inner = tw - 12 - 24 - SP.s - 10
  local rowH, left = 0, -cw / 2
  for i, tile in ipairs(t.tiles) do
    local d = WL.tiles[i]
    local K = Panoply.Kit
    if d.slot and K and K.ICONS and K.ICONS[d.slot] then K.Icon(tile.icon, d.slot, { size = 24 }) else Skin.SetIcon(tile.icon, d.icon) end
    tile.title:SetText(d.title); tile.text:SetText(d.text)
    tile.title:SetWidth(inner); tile.text:SetWidth(inner)
    local h1, h2 = math.ceil(TH(tile.title, inner)), math.ceil(TH(tile.text, inner))
    tile.title:SetHeight(h1); tile.text:SetHeight(h2)
    tile.icon:ClearAllPoints(); tile.icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 12, -10)
    tile.title:ClearAllPoints(); tile.title:SetPoint("TOPLEFT", tile, "TOPLEFT", 12 + 24 + SP.s, -9)
    tile.text:ClearAllPoints(); tile.text:SetPoint("TOPLEFT", tile.title, "BOTTOMLEFT", 0, -2)
    tile.panoplyH = math.max(24 + 20, 9 + h1 + 2 + h2 + 10)
    rowH = math.max(rowH, tile.panoplyH)
    local col = (i - 1) % 2
    tile:SetWidth(tw)
    tile:ClearAllPoints(); tile:SetPoint("TOPLEFT", t, "TOP", left + col * (tw + gap), y)
    tile:Show()
    if col == 1 or i == #t.tiles then
      for k = i - col, i do t.tiles[k]:SetHeight(rowH) end
      y = y - rowH - gap
      rowH = 0
    end
  end
  y = y - SP.m
  y = center(t, t.paras[#W.THANKS], cw, y) - SP.l
  local bw, bh = Skin.FitButton(t.go, 240, cw)
  t.go:ClearAllPoints(); t.go:SetPoint("TOP", t, "TOP", 0, y); y = y - bh - SP.s
  y = layoutOff(t, cw, y) - SP.s
  y = center(t, t.fine, cw, y) - SP.l
  sizeTo(self, "welcome", math.max(-y, 420))
end

-------------------------------------------------------------------------------
-- The splash (0.9.6 item 5): for W.SPLASH_SECONDS the window shows only the crest, the name and a line, then the welcome page takes
-- its place. A click anywhere on it skips it.
-------------------------------------------------------------------------------
function W:BuildSplash()
  if self.splash then return self.splash end
  local f = self.frame
  local s = CreateFrame("Frame", nil, f)
  s:EnableMouse(true)
  s.crest = s:CreateTexture(nil, "ARTWORK"); s.crest:SetSize(96, 96); Skin.Logo(s.crest)
  s.title = Skin.Heading(s, 28, W.SPLASH.title)
  s.tagline = Skin.Ink(s, 13, Skin.colors.inkSoft); s.tagline:SetText(W.SPLASH.tagline)
  for _, fs in ipairs({ s.title, s.tagline }) do if fs.SetJustifyH then fs:SetJustifyH("CENTER") end end
  s:SetScript("OnMouseUp", function() W:EndSplash() end)
  s:Hide()
  self.splash = s
  return s
end

function W:LayoutSplash()
  local s, f = self.splash, self.frame
  local top = (f.panoplyHeaderBottom or 52) + 4
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -top)
  s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  local w = ((f.GetWidth and f:GetWidth()) or W.SIZE.welcome[1]) - 32
  local h = ((f.GetHeight and f:GetHeight()) or W.SIZE.welcome[2]) - top - 16
  s:SetSize(w, h)
  local cw = w - 48
  s.title:SetWidth(cw); s.tagline:SetWidth(cw)
  local th, gh = math.ceil(TH(s.title, cw)), math.ceil(TH(s.tagline, cw))
  s.title:SetHeight(th); s.tagline:SetHeight(gh)
  local total = 96 + SP.l + th + SP.s + gh
  local y = -math.max(8, math.floor((h - total) / 2))
  s.crest:ClearAllPoints(); s.crest:SetPoint("TOP", s, "TOP", 0, y); y = y - 96 - SP.l
  s.title:ClearAllPoints(); s.title:SetPoint("TOP", s, "TOP", 0, y); y = y - th - SP.s
  s.tagline:ClearAllPoints(); s.tagline:SetPoint("TOP", s, "TOP", 0, y)
end

function W:ShowSplash()
  self:BuildSplash()
  self:LayoutSplash()
  if self.thanks then self.thanks:Hide() end
  self.splash:Show()
  self.splashing = true
  local token = {}
  self.splashToken = token
  C.After(W.SPLASH_SECONDS, function() if W.splashToken == token then W:EndSplash() end end)
  Panoply:Fire("WIZARD_PAGE", "splash")
end

function W:EndSplash()
  if not self.splashing then return end
  self.splashing, self.splashToken = nil, nil
  if self.splash then self.splash:Hide() end
  if self.mode == "thanks" and self.frame and self.frame:IsShown() then
    if self.thanks then self.thanks:Show() end
    self:NoteWelcomeOnScreen()
    Panoply:Fire("WIZARD_PAGE", "thanks")
  end
end

-------------------------------------------------------------------------------
-- 0.9.6 phase H (Nov 17 2026: a new character got setup with no splash and no welcome page). The welcome is due for a character
-- still to be set up until it was really seen: the welcome page on screen (not only the splash, not a window the game hid), or its
-- "Set up" clicked. NEW per-character key PanoplySuiteCharDB.welcomeShown; the 0.9.6 test builds' welcomeSeen was written when the
-- splash started, so it is not read for this any more (it is still written, with the same meaning as welcomeShown now).
-------------------------------------------------------------------------------
function W:WelcomeDue()
  local cdb = Panoply.cdb
  return (cdb and not cdb.setupDone and not cdb.welcomeShown) and true or false
end
function W:MarkWelcomeShown()
  local cdb = Panoply.cdb
  if cdb and not cdb.setupDone then cdb.welcomeShown = true cdb.welcomeSeen = true end
end
-- the welcome page is on screen: it counts as seen only when the player can see it (a movie hides the whole interface)
function W:NoteWelcomeOnScreen()
  local f = self.frame
  if self.mode == "thanks" and not self.thanksClose and f and f:IsShown() and (not f.IsVisible or f:IsVisible()) then self:MarkWelcomeShown() end
end

-- a cinematic is playing (a new character's intro, an in-game scene): no window opens over it
local function inCinematic()
  return (_G.InCinematic and InCinematic()) or (_G.IsInCinematicScene and IsInCinematicScene()) or false
end
W.InCinematic = inCinematic

-- The game closes every window when a cinematic starts (Blizzard's ShowUIPanel for the full-screen CinematicFrame runs CloseAllWindows,
-- which hides every adopted pop-out). When that hid the splash, the welcome or a setup step of a character still to be set
-- up, it comes back when the cinematic is over, on the same page (W:Resume).
function W:NoteHidden()
  if not (Panoply.cdb and not Panoply.cdb.setupDone) then self.hid = nil return end
  self.hid = { at = (C.GetTime and C.GetTime()) or 0, mode = self.mode, page = self.page }
  if inCinematic() then self.resume = self.hid end
end
function W:NoteCinematicStart()
  local h = self.hid
  local now = (C.GetTime and C.GetTime()) or 0
  if h and not (self.frame and self.frame:IsShown()) and now - (h.at or 0) <= 0.5 then self.resume = h end
end
function W:Resume()
  local r, auto = self.resume, self.pendingAuto
  if not (r or auto) then return false end
  if inCinematic() then return false end      -- another scene: wait for its end
  self.resume, self.pendingAuto = nil, nil
  if not (Panoply.cdb and not Panoply.cdb.setupDone) or (self.frame and self.frame:IsShown()) then return false end
  if C.InCombat and C.InCombat() then self.resume, self.pendingAuto = r, auto return false end
  if auto or not r or r.mode ~= "setup" or self:WelcomeDue() then
    if auto then return self:AutoStart() end
    return self:ShowThanks()
  end
  self:Start(r.page)
  return true
end
Panoply:On("CINEMATIC_START", function() W:NoteCinematicStart() end)
Panoply:On("CINEMATIC_STOP", function() C.After(1, function() W:Resume() end) end)
Panoply:On("PLAYER_REGEN_ENABLED", function() if W.resume or W.pendingAuto then W:Resume() end end)

-- The first page. The flags are set when it is shown, so it never comes back, even after a /reload.
-- our decision #19: on a character that already finished setup (an account from 0.7.3.6 or earlier) it is the thank-you with "Close"
-- and no setup opens; a character that still has to be set up gets the splash and the welcome page with "Set up <name>" (0.9.6).
function W:ShowThanks()
  if self:WaitForCombat("thanks") then return end
  self:Create()
  self:BuildThanks()
  self.thanksClose = (Panoply.cdb and Panoply.cdb.setupDone) and true or false
  if Panoply.db then
    if not Panoply.db.thanksSeen and not Panoply.existingAccount then Panoply.db.newAccount = true end
    Panoply.db.thanksSeen = true
  end
  self.mode, self.page = "thanks", 0
  setupParts(self, false)
  self.frame.panoplyTitle:SetText("Panoply Suite")
  if self.thanksClose then self:LayoutThanks() else self:LayoutWelcome() end
  self.frame:Show()
  if Panoply.Menu and Panoply.Menu.frame then Panoply.Menu.frame:Hide() end
  -- the splash only while the welcome is still due (a welcome page the game hid after it was seen comes back without it)
  if not self.thanksClose and self:WelcomeDue() and W.SPLASH_SECONDS and W.SPLASH_SECONDS > 0 then self:ShowSplash()
  else
    self:NoteWelcomeOnScreen()
    Panoply:Fire("WIZARD_PAGE", "thanks")
  end
end

-------------------------------------------------------------------------------
-- The steps
-------------------------------------------------------------------------------
-- Start (or run again) the setup. startAt may be a step number or name ("spec" is the old name of the plan step, "style" of the
-- Group quests step).
-- 0.9.6 phase H: setup never opens first. While this character's welcome is due, every way in (Home's next step, /panoply setup,
-- Help, the menu, the update card) shows the splash and the welcome page; its "Set up" opens step 1.
function W:Start(startAt)
  if self:WelcomeDue() then return self:ShowThanks() end
  if self:WaitForCombat("setup", startAt) then return end
  self:Create()
  self:InitChoices()
  self.mode = "setup"
  setupParts(self, true)
  self.frame.panoplyTitle:SetText("Set up " .. self:CharName())
  sizeTo(self, "setup")
  local steps = self:Steps()
  if startAt == "spec" then startAt = "plan" end
  if startAt == "style" then startAt = "group" end
  local idx = tonumber(startAt) or has(steps, startAt or "") or 1
  self.frame:Show()
  self:Go(idx)
  if Panoply.Menu and Panoply.Menu.frame then Panoply.Menu.frame:Hide() end
end

-- What a fresh login does: a character still to be set up gets the splash and the welcome page the first time (0.9.6 item 5), the
-- setup after that; an account that never saw the thank-you sees it once (a character that finished setup: Close).
function W:AutoStart()
  local db, cdb = Panoply.db, Panoply.cdb
  -- 0.9.6 phase H: a cinematic (a new character's intro) is playing: the first run waits for its end (W:Resume at CINEMATIC_STOP)
  if (cdb and not cdb.setupDone or db and not db.thanksSeen) and inCinematic() then self.pendingAuto = true return true end
  if self:WelcomeDue() then self:ShowThanks()
  elseif db and not db.thanksSeen then self:ShowThanks()
  elseif cdb and not cdb.setupDone then self:Start() end
  return true
end

-- The page of a step, made the first time it is asked for (hidden until W:Go shows it).
function W:Page(name)
  local p = self.pages[name]
  if p then return p end
  local sz = W.SIZE.setup
  local aw, ah = sz[1] - 32 - 16, sz[2] - BOOK_TOP - BOOK_BOTTOM - 16
  local area = Skin.ScrollArea(self.book)
  area:SetPoint("TOPLEFT", self.book, "TOPLEFT", 8, -8)
  area:SetPoint("BOTTOMRIGHT", self.book, "BOTTOMRIGHT", -8, 8)
  area:SetSize(aw, ah)
  p = area.content
  p:SetWidth(aw - 12)
  p.width = aw - 12
  p.panoplyArea = area
  self.pages[name] = p
  self.builders[name](p)
  return p
end

-------------------------------------------------------------------------------
-- 0.9.7: nothing of setup is made during a fight. The window, the first page, the splash and the steps this file builds (settings,
-- experience, group quests, partner) are made once at login, hidden (W:Prebuild); after a login in the middle of a fight, when the
-- fight ends. Until they are made, opening setup in a fight waits for the fight to end and says so once (W:WaitForCombat).
-- (The class plan step's cards are the Spec & Trainer module's, Modules/SpecTrainer/WizardPage.lua: it makes them when its step shows.)
-------------------------------------------------------------------------------
W.PREBUILT = { "settings", "experience", "group", "partner" }
W.COMBAT_WAIT = "Setup opens when the fight is over."
function W:Prebuild()
  if self.prebuilt then return true end
  if C.InCombat and C.InCombat() then return false end
  local had, hid = self.frame, self.hid
  self:Create()
  self:BuildThanks()
  self:BuildSplash()
  for _, n in ipairs(W.PREBUILT) do
    if self.builders[n] and not self.pages[n] then
      local p = self:Page(n)
      p:Hide(); p.panoplyArea:Hide()
    end
  end
  if not had then
    self.frame:Hide()
    self.hid = hid       -- hiding a window nobody saw is not "the game closed setup" (W:NoteHidden)
  end
  self.prebuilt = true
  return true
end
-- true when the open has to wait for the fight to end (it then happens by itself, once)
function W:WaitForCombat(mode, startAt)
  if self.prebuilt or not (C.InCombat and C.InCombat()) then return false end
  if not self.pendingOpen then Panoply:Print(W.COMBAT_WAIT) end
  self.pendingOpen = { mode = mode, startAt = startAt }
  return true
end
Panoply:On("PLAYER_LOGIN", function() W:Prebuild() end)
Panoply:On("PLAYER_REGEN_ENABLED", function()
  if not W.prebuilt then W:Prebuild() end
  local o = W.pendingOpen
  if not o then return end
  W.pendingOpen = nil
  if o.mode == "thanks" then W:ShowThanks() else W:Start(o.startAt) end
end)

function W:Name()
  if self.mode == "thanks" then return "thanks" end
  return self:Steps()[self.page]
end

function W:Go(i)
  if not self.choices then self:InitChoices() end
  local steps = self:Steps()
  i = math.max(1, math.min(#steps, i))
  self.page = i
  self.mode = "setup"
  local name = steps[i]
  for n, p in pairs(self.pages) do if n ~= name then p:Hide() p.panoplyArea:Hide() end end
  local p = self:Page(name)
  p.panoplyArea:Show()
  p:Show()
  self:RefreshBottom()
  if self.refreshers[name] then self.refreshers[name](p) end
  if p.Layout then self:FitPage(p, p:Layout()) end
  Panoply:Fire("WIZARD_PAGE", name)
end

-- 0.9.5 phase 4L (spec 06a 2.3): the window grows to show a step whole (four plan cards at Normal size) and scrolls only when the
-- step is taller than the screen allows. Never smaller than the standard size.
function W:FitPage(p, contentH)
  local f = self.frame
  local base = W.SIZE.setup[2]
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local scale = (f.GetScale and f:GetScale()) or 1
  if not scale or scale <= 0 then scale = 1 end
  local cap = math.max(base, math.floor(screenH / scale) - 40)
  local want = BOOK_TOP + 8 + (contentH or 0) + 8 + BOOK_BOTTOM + 2
  local h = math.max(base, math.min(cap, math.ceil(want)))
  if math.abs((f:GetHeight() or 0) - h) > 0.5 then sizeTo(self, "setup", h) end
  local ah = h - BOOK_TOP - BOOK_BOTTOM - 16
  p.panoplyArea:SetSize(W.SIZE.setup[1] - 32 - 16, ah)
  p.panoplyArea:SetContentHeight(contentH or 0)
end

-- the bottom row, the step counter, the dots and the Skip line (they depend on the step and on what is known)
function W:RefreshBottom()
  local steps, i = self:Steps(), self.page
  local n = #steps
  local last = i == n
  if i > 1 then self.back:Show() else self.back:Hide() end
  self.skip:ClearAllPoints()
  self.skip:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", i > 1 and (18 + 110 + 8) or 18, 16)
  Skin.FitButton(self.skip, 150, 260)
  self.next.label:SetText(last and "Start guiding" or "Next")
  self.next.tip = last and "Start guiding" or "Next"
  self.next.tipBody = last and "Save these choices, build your route and show the first step." or "Go to the next step."
  self.next.onLast = last
  -- the time estimate on the first step only (spec 06a 2.6)
  self.stepText:SetText(i == 1 and ("Step %d of %d \194\183 %s"):format(i, n, W.TIME) or ("Step %d of %d"):format(i, n))
  self.skip.tipBody = self:SkipLine()
  for k, t in ipairs(self.pips) do
    if k <= n then
      t:Show()
      t:ClearAllPoints(); t:SetPoint("BOTTOM", self.frame, "BOTTOM", (k - (n + 1) / 2) * 18, 29)
      t:SetTexture(Skin.TEX.CircleMask)
      if k == i then t:SetSize(10, 10); t:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], 1)
      else local c = Skin.colors.slotLine t:SetSize(8, 8); t:SetVertexColor(c[1], c[2], c[3], 1) end
    else t:Hide() end
  end
end

function W:Next()
  if self.mode ~= "setup" then return end
  if self.page < #self:Steps() then self:Go(self.page + 1) else self:Finish() end
end
function W:Back() if self.mode == "setup" and self.page > 1 then self:Go(self.page - 1) end end
function W:Refresh()
  if self.mode ~= "setup" then return end
  local n = self:Name()
  local p = self.pages[n]
  self:RefreshBottom()
  if self.refreshers[n] and p then self.refreshers[n](p) end
  if p and p.Layout then self:FitPage(p, p:Layout()) end
end

-- Choice setters (used by the buttons and by tests)
function W:SetProfileChoice(kind, name)
  if kind == "saved" and not (name or self.choices.profileName) then return end
  if kind == "fresh" and not self:CanStartFresh() then return end
  self.choices.profile = kind
  if name then self.choices.profileName = name end
  self:Refresh()
end
function W:SetPartner(name, solo)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  self.choices.partner = name
  self.choices.solo = solo and true or false
  if self.choices.chip and self.choices.chip ~= name then self.choices.chip = nil end
  self:Refresh()
end
-- a chip (someone in the group or an online friend) picked: the name is the partner, and the box goes back to its placeholder
function W:PickChip(name)
  self.choices.chip = name
  local p = self.pages.partner
  if p and p.box then
    if p.box.ClearFocus then p.box:ClearFocus() end
    p.box:SetText("")
    if p.box.placeholder then p.box.placeholder:Show() end
  end
  self:SetPartner(name, false)
end
-- the chips' selected look follows choices.chip
function W:MarkChips(p)
  local ch = self.choices
  for _, b in ipairs(p and p.picks or {}) do if b:IsShown() then b:SetSelected(not ch.solo and ch.chip ~= nil and ch.chip == b.pickName) end end
end
-- step 4: "ask", "do" or "skip" (anything else is refused)
function W:SetGroup(key)
  if not Panoply.SettingsUI.GROUP_QUESTS.names[key] then return end
  self.choices.group = key
  self:Refresh()
end
-- step 2: 1 to 4 (the Class page's levels)
function W:SetExperience(n)
  n = tonumber(n)
  if not n or n < 1 or n > 4 or n ~= math.floor(n) then return end
  self.choices.experience = n
  self:Refresh()
end

-------------------------------------------------------------------------------
-- Finishing
-------------------------------------------------------------------------------
-- Put the character on the profile its choices name. Returns the profile it is on afterwards.
function W:ApplyProfile(ch)
  local P = Panoply.Profiles
  if not self:CurrentProfile() then return nil end
  local want
  if ch.profile == "fresh" then
    local made, why = P:New(self:FreshName())
    if made then want = made else Panoply:Print("Setup could not make a new profile: " .. tostring(why)) end
  elseif ch.profile == "saved" and P:Exists(ch.profileName) then want = ch.profileName
  else want = self:ProfileOf({ profile = "same" }) end
  if want and want ~= self:CurrentProfile() then P:Switch(want) end
  return self:CurrentProfile()
end

-- 0.9.6.2 (PS-0011): setup leaves nothing of its own on screen when it ends: the window, its splash and any pop-up opened from it
-- (a profile list) are closed, so no frame of setup's is left over the world to take the next click (a quest giver's).
local function inside(f, root)
  while f do
    if f == root then return true end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end
function W:ClearScreen()
  self:EndSplash()
  local Pp, f = Skin.Popups, self.frame
  if f and Pp and Pp.stack then
    for i = #Pp.stack, 1, -1 do
      local p = Pp.stack[i]
      if p and p:IsShown() and inside(Pp:OwnerOf(p), f) then Pp:Close(p) end
    end
  end
  if f then f:Hide() end
end

-- Apply everything, build the route and show the first step.
function W:Finish()
  if not self.choices then self:InitChoices() end
  local ch, db = self.choices, Panoply.db
  local profile = self:ApplyProfile(ch)
  local partner = ch.solo and "" or (ch.partner or "")
  if (db.syncPartner or "") ~= partner then Panoply:SetPartner(partner) end
  if ch.solo then db.syncWaitForPartner = false end
  -- 0.9.7: the Group quests answer, through the one place that changes a setting, so the guide engine gets it right away. The old
  -- levellingStyle key is left in the saved file as it is: setup neither reads nor writes it any more.
  local group = self:GroupKey(ch.group)
  Panoply:SetOption("groupQuests", group)
  -- 0.9.5 phase 4L (spec 06a 2.2): the experience answer, saved once where the Class page's "Written for" reads it (asked only when
  -- the step ran: Skip setup leaves it for the Class page's first-run card)
  if Panoply.Answers and ch.experience and has(self:Steps(), "experience") then Panoply.Answers:Set("experience", ch.experience) end
  -- professions are never asked here: they come from your skills (and Settings overrides)
  if Panoply.ProfDetect then pcall(Panoply.ProfDetect.Detect, Panoply.ProfDetect, "setup") end
  -- what this setup chose is "my usual" for the next character
  local ST = Panoply.SpecTrainer
  -- (style: what a setup from before 0.9.7 remembered is carried along untouched; nothing reads it)
  local before = type(db.setupLast) == "table" and db.setupLast or nil
  db.setupLast = { profile = profile, spec = self:PlanActive() and ch.spec or nil, class = ST and ST:ClassFile() or nil,
                   style = before and before.style or nil, group = group, solo = ch.solo and true or false, partner = partner }
  if Panoply.Profiles then Panoply.Profiles:SaveCurrent() end   -- the profile's saved copy has the group quests choice and the rest right away
  Panoply.cdb.setupDone = true
  if Panoply.Answers then Panoply.Answers:MarkDone() end   -- 0.9.5 phase 4A4: finished, so the Class page does not ask again
  self:ClearScreen()
  local first
  Panoply:Replan("setup")
  Panoply.UI:Show()
  first = Panoply.Engine:Current()
  if Panoply.Toast then Panoply.Toast:Show("Your route is ready!", first and ("First: " .. Panoply.StepText.Headline(first)) or "Follow the guide window.") end
  Panoply:Fire("SETUP_DONE")
  return first
end

-- "Skip, use my usual": apply the line above the buttons and finish at once.
-- On a character that already finished setup (run again) it changes nothing and just closes.
function W:Skip()
  if not self.usual then self:InitChoices() end
  if self.rerun then self.frame:Hide() return end
  self.choices = self:UsualChoices()
  self.choices.profileName = self:OtherProfiles()[1]
  self.choices.experience = nil          -- skipped: not answered here, so the Class page may ask it
  local first = self:Finish()
  -- 0.9.5 phase 4A4 (spec 06 section 3.2): skipped, so the Class page's first-run card may ask what setup did not
  if Panoply.Answers then Panoply.Answers:MarkSkipped() end
  return first
end

-------------------------------------------------------------------------------
-- Building blocks shared by the steps (WizardPage.lua uses them for the plan step)
-------------------------------------------------------------------------------
W.builders, W.refreshers = {}, {}

local function at(p, obj, x, y, width)
  obj:ClearAllPoints(); obj:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
  if width then obj:SetWidth(width) end
end
local function heading(p, text)
  local h = Skin.Ink(p, 20, Skin.colors.inkTitle); h:SetText(text or "")
  h:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
  return h
end
local function para(p, text, size, color)
  local fs = Skin.Ink(p, size or 13, color); fs:SetText(text or "")
  return fs
end
-- stack a heading and paragraph from the top; returns the y below them
local function top(p, h, d)
  local w = p.width - 40
  at(p, h, 20, -18, w)
  h:SetHeight(TH(h, w))
  local y = -18 - TH(h, w) - SP.s
  if d then at(p, d, 20, y, w) d:SetHeight(TH(d, w)) y = y - TH(d, w) - SP.l end
  return y
end

-- A choice card: a round radio mark, a name, an optional "Recommended" pill, an optional note on the right (the role of a
-- plan), a line of words and an optional second line. It is a button: one click picks it. Selected = a brass outline.
local RADIO = 18
local function optionCard(parent, o)
  local b = Skin.Button(parent, "", 100, 56, o.onClick, o.tip, o.tipBody)
  b.label:SetText("")
  -- 0.9.5 phase 4L (spec 06a 2.6): the card shows its whole text, so it has no tooltip repeating it. A card whose tooltip adds
  -- something shows it beside the window, outside the cards (never over the card above or beside)
  -- (panoplyNoTip says so on purpose; the skin test accepts it only from a card whose title shows text)
  if not o.tip then b.tip, b.tipBody, b.panoplyNoTip = nil, nil, "card" end
  b.tipAnchor = W.TipBeside
  b.ringOut = b:CreateTexture(nil, "ARTWORK"); b.ringOut:SetTexture(Skin.TEX.CircleMask); b.ringOut:SetSize(RADIO, RADIO)
  b.ringIn = b:CreateTexture(nil, "OVERLAY"); b.ringIn:SetTexture(Skin.TEX.CircleMask); b.ringIn:SetSize(RADIO - 4, RADIO - 4)
  b.dot = b:CreateTexture(nil, "OVERLAY", nil, 1); b.dot:SetTexture(Skin.TEX.CircleMask); b.dot:SetSize(RADIO - 10, RADIO - 10)
  local c = Skin.colors.card; b.ringIn:SetVertexColor(c[1], c[2], c[3], 1)
  c = Skin.colors.accent; b.dot:SetVertexColor(c[1], c[2], c[3], 1)
  b.title = Skin.Name(b, 14, Skin.colors.text)
  b.side = Skin.Ink(b, 12, Skin.colors.inkSoft)
  if b.side.SetJustifyH then b.side:SetJustifyH("RIGHT") end
  b.body = Skin.Ink(b, 13, Skin.colors.inkSoft)
  b.extra = Skin.Ink(b, 13, Skin.colors.ink)
  -- the "Recommended" pill: a rounded outline in the accent colour
  b.pill = CreateFrame("Frame", nil, b)
  Skin.RoundBox(b.pill, 10, Skin.TEX.RFill, Skin.colors.accent, 0.14, Skin.TEX.RLine8, Skin.colors.accent, 1, "BACKGROUND")
  b.pillText = Skin.Name(b.pill, 11, Skin.colors.accent)
  b.pillText:SetText("Recommended"); b.pillText:SetPoint("CENTER", b.pill, "CENTER", 0, 0)
  if b.pillText.SetJustifyH then b.pillText:SetJustifyH("CENTER") end
  b.pill:Hide()
  function b:SetRecommended(on) self.recommended = on and true or nil if on then self.pill:Show() else self.pill:Hide() end end
  function b:SetSelected(on)
    self.selected = on and true or nil
    self:Paint(on and "sel" or "up")
    local a = on and Skin.colors.accent or Skin.colors.slotLine
    self.ringOut:SetVertexColor(a[1], a[2], a[3], 1)
    if on then self.dot:Show() else self.dot:Hide() end
    local t = on and Skin.colors.heading or Skin.colors.text
    self.title:SetTextColor(t[1], t[2], t[3], 1)
  end
  -- a card that cannot be picked now (no other profile yet): dimmed, clicks do nothing
  function b:SetUsable(on)
    self:SetEnabledLook(on)
    local k = on and 1 or 0.5
    for _, fs in ipairs({ self.title, self.side, self.body, self.extra }) do fs:SetAlpha(k) end
    self.ringOut:SetAlpha(k)
  end
  b:SetSelected(false)
  -- Lay the card out for `width`; returns its height. reserve = room kept free on the right (a drop-down).
  function b:Fit(width, reserve, minH)
    reserve = reserve or 0
    self:SetWidth(width)
    local x0 = 14 + RADIO + 12
    local right = width - 14 - reserve
    local y = -12
    local _, fsz = self.title:GetFont()
    local lineH = (fsz or 14) * 1.25 + 2
    local sideW = 0
    local hasSide = (self.side:GetText() or "") ~= ""
    if hasSide then
      sideW = math.min(math.ceil(Skin.TextWidth(self.side)) + 2, math.floor(width * 0.34))
      self.side:ClearAllPoints(); self.side:SetPoint("TOPRIGHT", self, "TOPRIGHT", -14 - reserve, y - 2)
      self.side:SetWidth(sideW); self.side:SetHeight(TH(self.side, sideW))
    end
    local pw, ph = 0, 0
    if self.recommended then
      pw, ph = math.ceil(Skin.TextWidth(self.pillText)) + 18, math.ceil(TH(self.pillText)) + 4
      self.pill:SetSize(pw, ph)
    end
    local avail = right - x0 - (hasSide and (sideW + 12) or 0) - (self.recommended and (pw + 8) or 0)
    local tw = math.max(60, math.min(math.ceil(Skin.TextWidth(self.title)) + 2, avail))
    self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", self, "TOPLEFT", x0, y); self.title:SetWidth(tw)
    local th = TH(self.title, tw); self.title:SetHeight(th)
    self.ringOut:ClearAllPoints(); self.ringOut:SetPoint("TOPLEFT", self, "TOPLEFT", 14, y - math.max(0, (lineH - RADIO) / 2))
    self.ringIn:ClearAllPoints(); self.ringIn:SetPoint("CENTER", self.ringOut, "CENTER", 0, 0)
    self.dot:ClearAllPoints(); self.dot:SetPoint("CENTER", self.ringOut, "CENTER", 0, 0)
    local rowH = th
    if self.recommended then
      local py = math.max(0, (lineH - ph) / 2)
      self.pill:ClearAllPoints(); self.pill:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + tw + 8, y - py)
      rowH = math.max(th, py + ph)
    end
    y = y - rowH
    local bw = right - x0
    for _, fs in ipairs({ self.body, self.extra }) do
      if (fs:GetText() or "") ~= "" then
        y = y - 3
        fs:Show(); fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", self, "TOPLEFT", x0, y); fs:SetWidth(bw)
        local h = TH(fs, bw); fs:SetHeight(h)
        y = y - h
      else fs:Hide() end
    end
    local h = math.max(minH or 46, math.ceil(-y + 12))
    self:SetHeight(h)
    return h
  end
  return b
end
W.OptionCard = optionCard

-- a setup tooltip: on the right of the window, level with the card (on the left when the window is near the screen's right edge)
function W.TipBeside(GT, owner)
  local f = W.frame
  if not f then GT:SetOwner(owner, "ANCHOR_TOP") return end
  GT:SetOwner(owner, "ANCHOR_NONE")
  GT:ClearAllPoints()
  local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024
  local right = f.GetRight and f:GetRight()
  local top = owner.GetTop and owner:GetTop()
  local fb = f.GetBottom and f:GetBottom()
  local y = (top and fb) and (top - fb) or 0
  if right and right + 260 > sw then GT:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", -8, y)
  else GT:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", 8, y) end
end
W.At, W.Heading, W.Para, W.Top = at, heading, para, top

-- Cards in a grid of `cols` columns from y; returns the y below. Cards in a row are made as tall as the tallest.
local function grid(p, cards, y, cols, gap)
  gap = gap or SP.s
  local w = p.width - 40
  local cw = math.floor((w - gap * (cols - 1)) / cols)
  local i = 1
  while i <= #cards do
    local row, h = {}, 0
    for k = 0, cols - 1 do
      local c = cards[i + k]
      if c then row[#row + 1] = c; h = math.max(h, c:Fit(cw)) end
    end
    for k, c in ipairs(row) do
      c:SetHeight(h)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", p, "TOPLEFT", 20 + (k - 1) * (cw + gap), y)
    end
    y = y - h - gap
    i = i + cols
  end
  return y
end
W.Grid = grid

-------------------------------------------------------------------------------
-- Step 1: which settings
-------------------------------------------------------------------------------
W.builders.settings = function(p)
  p.ttl = heading(p, "")
  p.intro = para(p, "Settings are your choices for windows, the arrow, automation and so on.")
  p.cards = {}
  local function card(key, title)
    local c = optionCard(p, { onClick = function() W:SetProfileChoice(key) end })
    c.title:SetText(title); c.pickKey = key
    p.cards[#p.cards + 1] = c; p[key] = c
    return c
  end
  card("same", "Same as my other characters")
  card("saved", "A saved profile")
  card("fresh", "Start fresh")
  p.same:SetRecommended(true)
  p.same:Hide()     -- shown by the step itself once it knows of another character (W.refreshers.settings)
  -- the drop-down on the "saved profile" card: a button that opens the list of profiles
  local dd = Skin.Button(p.saved, "", 160, 28, function(self) W:OpenProfileMenu(self) end, "Pick a profile", "Choose which saved profile this character uses.")
  dd.label:ClearAllPoints(); dd.label:SetPoint("LEFT", dd, "LEFT", 12, 0)
  if dd.label.SetJustifyH then dd.label:SetJustifyH("LEFT") end
  local k = Skin.colors.gold
  dd.chev = {}
  for i = 1, 2 do
    local ln = dd:CreateLine(nil, "OVERLAY")
    ln:SetColorTexture(k[1], k[2], k[3], 1); ln:SetThickness(2)
    dd.chev[i] = ln
  end
  dd.chev[1]:SetStartPoint("RIGHT", dd, -22, 2); dd.chev[1]:SetEndPoint("RIGHT", dd, -16, -3)
  dd.chev[2]:SetStartPoint("RIGHT", dd, -16, -3); dd.chev[2]:SetEndPoint("RIGHT", dd, -10, 2)
  p.dd = dd
  function p:Layout()
    local y = top(self, self.ttl, self.intro)
    local w = self.width - 40
    local reserve = 0
    if self.dd:IsShown() then
      local tw = math.ceil(Skin.TextWidth(self.dd.label))
      self.ddW = math.max(120, math.min(tw + 46, 260))
      self.dd:SetWidth(self.ddW)
      reserve = self.ddW + 12
    end
    for _, c in ipairs(self.cards) do
      if c:IsShown() then
      local h = c:Fit(w, c == self.saved and reserve or 0)
      at(self, c, 20, y)
      if c == self.saved and self.dd:IsShown() then
        self.dd:ClearAllPoints(); self.dd:SetPoint("RIGHT", c, "RIGHT", -14, 0)
      end
      y = y - h - SP.s
      end
    end
    return -y + SP.m
  end
end
W.refreshers.settings = function(p)
  local ch = W.choices
  local name = W:CharName()
  p.ttl:SetText(("Which settings should %s use?"):format(name))
  -- "Same as my other characters" is the profile most of them use, and says how they are split; with no other character it is hidden
  -- (spec 06a 2.1), and Recommended goes on it only when it is there
  local same = W:SameText()
  if same then p.same.body:SetText(same) p.same:Show() p.same:SetRecommended(true)
  else p.same:Hide() p.same:SetRecommended(false) if ch.profile == "same" then ch.profile = "saved" end end
  local list = W:OtherProfiles()
  local have = #list > 0
  p.saved.body:SetText(have and "Pick one of your other profiles." or "You have no other profile yet. Make one on the Profiles page.")
  p.saved:SetUsable(have)
  if have then
    local sel = ch.profileName
    if not has(list, sel or "") then sel = list[1]; ch.profileName = sel end
    p.dd.label:SetText(sel)
    p.dd:Show()
  else p.dd:Hide() end
  local fresh = W:CanStartFresh()
  p.fresh.body:SetText(("Panoply Suite's standard settings, kept in a new profile named after %s."):format(name))
  p.fresh:SetUsable(fresh)
  p.same:SetSelected(ch.profile == "same")
  p.saved:SetSelected(ch.profile == "saved" and have)
  p.fresh:SetSelected(ch.profile == "fresh" and fresh)
end

-- the list under the drop-down
function W:OpenProfileMenu(owner)
  local items = {}
  for _, n in ipairs(self:OtherProfiles()) do
    items[#items + 1] = { text = n, checked = function() return self.choices.profileName == n end,
      tip = "Use the profile " .. n .. ".", func = function() W:SetProfileChoice("saved", n) end }
  end
  if #items == 0 then return end
  -- above the setup window (both are on the top layer): the list never draws under the card's border (spec 06a 2.1)
  return Skin.Menu(owner, items, { strata = "TOOLTIP" })
end

-------------------------------------------------------------------------------
-- Step 2: how much have you played (0.9.5 phase 4L, spec 06a 2.2): the Class page's four levels, in the setup's choice cards.
-- Saved once (Core/Answers.lua) when setup finishes; the Class header's "Written for" reads it.
-------------------------------------------------------------------------------
W.builders.experience = function(p)
  p.ttl = heading(p, "How much have you played?")
  p.intro = para(p, "The Class page writes its advice for you. You can change this any time on the Class page.")
  p.pick, p.cards = {}, {}
  local levels = (Panoply.Answers and Panoply.Answers.Levels()) or { "New to the game", "Played before but never max level", "Max level but no raids", "Raids and endgame" }
  for i, name in ipairs(levels) do
    local c = optionCard(p, { onClick = function() W:SetExperience(i) end })
    c.title:SetText(name); c.body:SetText(W.EXPERIENCE_TEXT[i] or "")
    c.expLevel = i
    p.pick[i] = c; p.cards[#p.cards + 1] = c
  end
  function p:Layout()
    local y = top(self, self.ttl, self.intro)
    y = grid(self, self.cards, y, 2)
    return -y + SP.m
  end
end
W.refreshers.experience = function(p)
  local n = W.choices.experience or 1
  for i, c in pairs(p.pick) do c:SetSelected(i == n) end
end

-------------------------------------------------------------------------------
-- Step 4: group quests (0.9.7, Nov 18 2026: "the style step is replaced by the three Group quests cards"). Ask me each time /
-- Always include them / Leave them out; saved as PanoplySuiteDB.groupQuests by Start guiding. The words are UI/Settings.lua's.
-------------------------------------------------------------------------------
W.builders.group = function(p)
  local G = Panoply.SettingsUI.GROUP_QUESTS
  p.ttl = heading(p, W.GROUP_HEAD)
  p.intro = para(p, W.GROUP_INTRO)
  p.pick, p.cards = {}, {}
  for _, key in ipairs(G.values) do
    local c = optionCard(p, { onClick = function() W:SetGroup(key) end })
    c.title:SetText(G.names[key]); c.body:SetText(G.text[key])
    if key == G.default then c:SetRecommended(true) end
    c.groupKey = key
    p.pick[key] = c; p.cards[#p.cards + 1] = c
  end
  p.note = para(p, W.GROUP_NOTE, 12, Skin.colors.inkSoft)
  function p:Layout()
    local y = top(self, self.ttl, self.intro)
    local w = self.width - 40
    -- three cards, one under the other, each as wide as the page
    for _, c in ipairs(self.cards) do
      local h = c:Fit(w)
      at(self, c, 20, y)
      y = y - h - SP.s
    end
    y = y - SP.xs
    at(self, self.note, 20, y, w); self.note:SetHeight(TH(self.note, w)); y = y - TH(self.note, w) - SP.m
    return -y
  end
end
W.refreshers.group = function(p)
  local key = W:GroupKey(W.choices.group)
  for k, c in pairs(p.pick) do c:SetSelected(k == key) end
end

-------------------------------------------------------------------------------
-- Step 5: solo or partner, your choices, Start guiding
-------------------------------------------------------------------------------
W.builders.partner = function(p)
  p.ttl = heading(p, "Do you level with a partner?")
  p.intro = para(p, W.PARTNER_INTRO)
  p.solo = optionCard(p, { onClick = function() W:SetPartner("", true) end })
  p.solo.title:SetText("Just me"); p.solo.body:SetText("No partner. Panoply Suite never waits for anyone.")
  p.with = optionCard(p, { onClick = function() W:SetPartner(W.choices.partner or "", false) end })
  p.with.title:SetText("With a partner")
  p.with.body:SetText("Pick from your group or your friends who are online, or type a name.")
  p.picks = {}
  for i = 1, MAX_PICKS do
    local b = Skin.Button(p.with, "", 120, 30, function(self) W:PickChip(self.pickName) end, "Pick partner", "Level together with this player.")
    b.tipAnchor = W.TipBeside
    b:Hide()
    p.picks[i] = b
  end
  p.empty = Skin.Ink(p.with, 12, Skin.colors.inkSoft)
  local eb = Skin.Input(p.with, 220, 30, "or type a name")
  if eb.icon then eb.icon:Hide() end
  if eb.SetTextInsets then eb:SetTextInsets(8, 8, 0, 0) end
  if eb.placeholder then eb.placeholder:ClearAllPoints(); eb.placeholder:SetPoint("LEFT", eb, "LEFT", 8, 0) end
  -- spec 06a 2.5: a picked chip clears this box (its placeholder shows); typing a name deselects the chips
  eb:SetScript("OnTextChanged", function(b, user)
    if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end
    if user and (b:GetText() or "") ~= "" then W.choices.chip = nil W:MarkChips(p) end
  end)
  local function typed()
    local t = eb:GetText() or ""
    if t ~= "" then W:SetPartner(t, false)
    elseif not W.choices.solo and (W.choices.partner or "") ~= "" and not W.choices.chip then W:SetPartner("", false) end
  end
  eb:SetScript("OnEnterPressed", function() typed() eb:ClearFocus() end)
  eb:HookScript("OnEditFocusLost", typed)
  p.box = eb
  -- the choices in one line
  p.sum = Skin.Card(p); p.sum.panoplyGapOK = true
  p.sum.label = Skin.Label(p.sum, 11, Skin.colors.inkSoft)
  -- the choices as labelled lines (spec 06a 2.5): "Profile: Default", "Experience: New to the game", ...
  p.sum.keys, p.sum.vals = {}, {}
  for i = 1, 5 do
    p.sum.keys[i] = Skin.Ink(p.sum, 13, Skin.colors.inkSoft)
    p.sum.vals[i] = Skin.Name(p.sum, 13, Skin.colors.text)
  end
  p.sum.note = Skin.Ink(p.sum, 12, Skin.colors.inkSoft)
  function p:Layout()
    local y = top(self, self.ttl, self.intro)
    local w = self.width - 40
    local h = self.solo:Fit(w)
    at(self, self.solo, 20, y); y = y - h - SP.s
    -- "With a partner": its words, then the people who can be picked, then the box for a name
    local c = self.with
    local x0 = 14 + RADIO + 12
    local inner = w - x0 - 14
    local h0 = c:Fit(w)
    local cy = -(h0 - 6)
    local shown = {}
    for _, b in ipairs(self.picks) do if b:IsShown() then shown[#shown + 1] = b end end
    if #shown > 0 then
      local fh = Skin.FlowButtons(c, shown, x0, cy, inner, SP.s, 90)
      cy = cy - fh - SP.s
    end
    if (self.empty:GetText() or "") ~= "" then
      self.empty:Show(); self.empty:ClearAllPoints(); self.empty:SetPoint("TOPLEFT", c, "TOPLEFT", x0, cy); self.empty:SetWidth(inner)
      local eh = TH(self.empty, inner); self.empty:SetHeight(eh); cy = cy - eh - SP.s
    else self.empty:Hide() end
    self.box:ClearAllPoints(); self.box:SetPoint("TOPLEFT", c, "TOPLEFT", x0, cy)
    cy = cy - 30 - 12
    c:SetHeight(-cy)
    at(self, c, 20, y); y = y - (-cy) - SP.m
    -- the summary card
    local s = self.sum
    local sx, sw = 14, w - 28
    local sy = -12
    s.label:ClearAllPoints(); s.label:SetPoint("TOPLEFT", s, "TOPLEFT", sx, sy); s.label:SetWidth(sw)
    s.label:SetHeight(TH(s.label, sw)); sy = sy - TH(s.label, sw) - SP.xs
    local kw = 0
    for i, k in ipairs(s.keys) do if k:IsShown() then kw = math.max(kw, math.ceil(Skin.TextWidth(k)) + 2) end end
    kw = math.min(kw, math.floor(sw * 0.4))
    for i, k in ipairs(s.keys) do
      local v = s.vals[i]
      if k:IsShown() then
        local vw = sw - kw - SP.m
        k:ClearAllPoints(); k:SetPoint("TOPLEFT", s, "TOPLEFT", sx, sy); k:SetWidth(kw); k:SetHeight(TH(k, kw))
        v:ClearAllPoints(); v:SetPoint("TOPLEFT", s, "TOPLEFT", sx + kw + SP.m, sy); v:SetWidth(vw); v:SetHeight(TH(v, vw))
        sy = sy - math.max(TH(k, kw), TH(v, vw)) - 2
      end
    end
    sy = sy - SP.xs
    s.note:ClearAllPoints(); s.note:SetPoint("TOPLEFT", s, "TOPLEFT", sx, sy); s.note:SetWidth(sw)
    s.note:SetHeight(TH(s.note, sw)); sy = sy - TH(s.note, sw) - 12
    s:SetHeight(-sy)
    at(self, s, 20, y, w)
    y = y - (-sy) - SP.m
    return -y
  end
end
W.refreshers.partner = function(p)
  local cands = Panoply.Menu.PartnerCandidates()
  local ch = W.choices
  for i, b in ipairs(p.picks) do
    local c = cands[i]
    if c then
      b.pickName = c.name; b.label:SetText(c.name); b.tip = "Pick " .. c.name
      b.tipBody = (c.from == "group" and "In your group." or "Online friend.") .. " Level together with this player."
      b:Show()
    else b:Hide() end
  end
  p.empty:SetText(#cands == 0 and "Nobody in your group or online friends right now. Type a name, or leave it empty to pair with whoever you group with." or "")
  -- a chip's name is never typed in the box as well (spec 06a 2.5, run A): the box holds only a name typed there
  local typedName = (not ch.chip) and (ch.partner or "") or ""
  -- a partner saved before is shown as its chip when that player is in the list
  if not ch.chip and not ch.solo and typedName ~= "" then
    for _, c in ipairs(cands) do if c.name == typedName then ch.chip = c.name typedName = "" end end
  end
  if p.box.GetText and p.box:GetText() ~= typedName and not (p.box.HasFocus and p.box:HasFocus()) then
    p.box:SetText(typedName)
    if p.box.placeholder then if typedName == "" then p.box.placeholder:Show() else p.box.placeholder:Hide() end end
  end
  W:MarkChips(p)
  p.solo:SetSelected(ch.solo)
  p.with:SetSelected(not ch.solo)
  p.sum.label:SetText(("YOUR CHOICES FOR %s"):format(W:CharName():upper()))
  local rows = W:SummaryRows()
  for i, k in ipairs(p.sum.keys) do
    local r = rows[i]
    if r then k:SetText(r[1] .. ":") p.sum.vals[i]:SetText(r[2]) k:Show() p.sum.vals[i]:Show()
    else k:SetText("") p.sum.vals[i]:SetText("") k:Hide() p.sum.vals[i]:Hide() end
  end
  p.sum.note:SetText("Start guiding builds the route. Every choice can be changed later.")
end
