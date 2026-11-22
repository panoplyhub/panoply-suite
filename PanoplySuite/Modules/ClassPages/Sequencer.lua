-- Panoply Suite 0.9.4 (next): the next ability display (the 0.9.4 Rotation sequencer) card on the class pages' Rotation topic. DISPLAY ONLY.
--
-- It draws a short strip: the next few abilities of the class's leveling order (Data/Sequences.lua), in order, each with what the
-- game says about it right now (ready, seconds left, not enough Mana). That is all it does.
--   * It never casts, targets, uses an item, changes an action bar, sets a key binding, makes a secure or clickable action button,
--     or calls a protected function. Its only buttons are plain Panoply Suite buttons that change what the strip SHOWS (which order,
--     on or off). tests/classpages_tests.lua scans this file and Page.lua for a deny-list of such calls.
--   * Combat: the card is built only out of combat (CP.Seq:ViewState). In combat the frames it already has only get new text and
--     new textures (SetText, SetTexture, SetTextColor, SetVertexColor); nothing is created, shown, hidden, moved or resized. A switch
--     flipped in combat is saved at once but drawn when the fight ends (PLAYER_REGEN_ENABLED).
--   * Switch: "Show the rotation sequencer", ON by default (like the Rotation panel's button, which is shown unless the player
--     turns it off). Saved for the character under PanoplySuiteCharDB.classSequencer = { shown = false } only after a change.
--
-- What it reads from the game, all read-only, every call through Panoply.Compat (C.Call, pcall-guarded; a missing API is a blank, not an
-- error). WHICH OF THESE EXIST AND ANSWER AS EXPECTED ON EACH CLIENT IS UNVERIFIED in the real game:
--   spell icon          C_Spell.GetSpellTexture(name)   (WoW Forever)      GetSpellTexture(name)   (Classic Era)
--   cooldown            C_Spell.GetSpellCooldown(name)  (table, Forever)   GetSpellCooldown(name)  (start, duration, enabled)
--   usable, Mana        C_Spell.IsSpellUsable(name)     (Forever)          IsUsableSpell(name)     (Era)
--   name of a cast      C_Spell.GetSpellName(id)        (Forever)          GetSpellInfo(id)        (Era)
--   the spells you know Panoply.Rotation:KnownSpells(), the Rotation module's spellbook reader (C_SpellBook on Forever, the old spellbook
--                       calls on Era); without it every step is shown and the card says so
-- It does not read buffs or enemy debuffs: a "once" step (a buff, an opener, a damage-over-time) is dropped from the strip after the
-- player's own cast of it succeeds (UNIT_SPELLCAST_SUCCEEDED) and comes back when the fight ends or the target changes.
--
-- 0.9.4 (next), step 17: the next ability can also be highlighted on the player's own action bars (Modules/ClassPages/ActionGlow.lua).
-- S:Next() is the one place that says which step is next, for the strip and for the highlight; S.read hands the read-only game
-- readers below to the other files of this feature. Nothing here changes: still display only.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local C, Skin = Panoply.Compat, Panoply.Skin
local SP, TH = Skin.SP, Skin.TextHeight

local S = { live = setmetatable({}, { __mode = "k" }), pick = {}, done = {}, seqCache = {} }
CP.Seq = S

S.CHIPS = 4            -- how many next abilities the strip shows
S.GCD = 1.6            -- a cooldown this short is the global cooldown, not the spell's own
-- 0.9.5 phase 4H (specs 03a section 3 and 05a section 1): the feature is called the next ability display; its words say what it does and
-- scope "never casts" to it alone (profession craft buttons and quest-item buttons elsewhere in the suite do cast when clicked). The Beta
-- line lives in the section's ? tooltip (S.HelpText), with the probe's summary of what this client shares in combat.
S.TITLE = "Next ability display"
S.INTRO = "Shows your next ability and lights up its button on your action bar. You press your own buttons; this display never casts."
S.BETA = "Beta: more rotations are coming."
S.SCOPE = "The next ability display never casts; it shows what to press next."
S.LIMIT = "It reads your spellbook, cooldowns and Mana. It does not yet know which buffs or damage-over-time effects are already on, so an opener you have cast stays off the strip until the fight ends."
S.OFF = "The next ability display is off. Turn it on above to see the order of play for this class."
S.NO_ORDER = "There is no order of play for this class on this game yet."
S.OTHER = "You are reading another class's page, so this shows the order only."
S.NO_BOOK = "Your spellbook could not be read here, so every step is shown."
S.EMPTY = "Every step is done for now. It starts again when the fight ends."
S.WAIT = "Saved. The next ability display changes when the fight ends."
S.NOSTEPS = "This rotation has no steps yet. Add some below."
S.NONE_KNOWN = "None of this rotation's spells are in your spellbook yet."
S.BARS_OTHER = "The game's own action buttons are not shown, so the button highlight is off."
local PAD = 12

local function put(fs, parent, x, y, w, text)
  fs:SetWidth(w); fs:SetText(text or "")
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = TH(fs, w); fs:SetHeight(h)
  return y - h
end

-------------------------------------------------------------------------------
-- The switch (plain saved data)
-------------------------------------------------------------------------------
function S:IsOn()
  local d = Panoply.cdb and Panoply.cdb.classSequencer
  return not (type(d) == "table" and d.shown == false)
end

-- "on", "off" or "wait" for the card the page would draw now. Out of combat it follows the saved switch; in combat it keeps what was
-- last drawn (so nothing changes in a fight), and "wait" means the card has never been drawn and is left out until the fight ends.
function S:ViewState()
  if C.InCombat() then
    if not self.applied then self.dirty = true end
    return self.applied or "wait"
  end
  self.applied = self:IsOn() and "on" or "off"
  self.advDrawn = CP.Cond and CP.Cond.Enabled() or false   -- (step 19: which fields the editor draws; in a fight they stay as drawn)
  return self.applied
end

-- The section's ? tooltip (How to play > What to press): the Beta line, and what the probe found this client shares in combat
-- ("3 of 5 inputs readable on this client"; Core/Probe.lua), or that it was not asked yet.
function S:HelpText()
  local lines = { S.BETA, S.SCOPE }
  local P = Panoply.Probe
  local summary = P and P.InputSummary and P:InputSummary() or nil
  if summary then
    lines[#lines + 1] = summary .. " in combat. A condition that needs one the game keeps secret is greyed in the editor and skipped in a fight; that step keeps its place in the order."
  else
    lines[#lines + 1] = "What this game shares in combat is checked the first time you fight with Panoply Suite on (or type /panoply probe)."
  end
  return table.concat(lines, "\n\n")
end

-- what the switch shows: in a fight, what was last drawn (the saved change waits)
function S:Shown()
  if C.InCombat() and self.applied then return self.applied == "on" end
  return self:IsOn()
end

-- true when it was applied at once, false when it waits for the end of the fight
function S:SetOn(on)
  if not Panoply.cdb then return false end
  if type(Panoply.cdb.classSequencer) ~= "table" then Panoply.cdb.classSequencer = {} end
  Panoply.cdb.classSequencer.shown = on and true or false
  if C.InCombat() then
    self.dirty, self.switchWait = true, true
    self:UpdateAll()
    return false
  end
  self:Redraw()
  if CP.Glow then CP.Glow:Refresh() end
  return true
end

-- the class page, drawn again (out of combat only; a plain page refresh)
function S:Redraw()
  local M = Panoply.Menu
  if M and M.frame and M.pageDef and M.pageDef.body == "ClassPages" and M.RefreshCurrent then M:RefreshCurrent() end
end

-------------------------------------------------------------------------------
-- Reading the game (read-only, guarded)
-------------------------------------------------------------------------------
local function ask(path, ...)
  local ok, a, b, c3 = C.Call(path, path, ...)
  if not ok then return nil end
  return C.Readable(a), C.Readable(b), C.Readable(c3)
end

local function iconOf(name) return Panoply.Icons:Spell(name) end   -- 0.9.7 hotfix: the one shared lookup (Core/CompatModules.lua)

-- seconds left on the spell's own cooldown (0 = ready, nil = could not be asked)
local function cooldownLeft(name)
  local a, b = ask("C_Spell.GetSpellCooldown", name)
  local start, dur
  if type(a) == "table" then start, dur = a.startTime, a.duration
  else
    start, dur = ask("GetSpellCooldown", name)
  end
  start, dur = tonumber(start), tonumber(dur)
  if not start or not dur then return nil end
  if start == 0 or dur <= S.GCD then return 0 end
  local left = start + dur - C.GetTime()
  return left > 0 and left or 0
end

-- usable now, and whether Mana (or Rage, Energy) is what is short; nil when it could not be asked
local function usable(name)
  local ok, short = ask("C_Spell.IsSpellUsable", name)
  if ok == nil then ok, short = ask("IsUsableSpell", name) end
  if ok == nil then return nil end
  return ok and true or false, short and true or false
end

-- Nov 14 2026 (17-22 review, backlog 1): the map of the spellbook is made once, not on every look (up to ten a second in a fight). It is
-- kept for as long as the Rotation module hands back the same list; that module drops its list on SPELLS_CHANGED, and the events below
-- drop it too when a spell is learned or a talent changes, so the next look reads the book again.
local kmCache = {}
local function knownMap()
  local R = Panoply.Rotation
  if type(R) ~= "table" or type(R.KnownSpells) ~= "function" then return nil end
  local ok, list = pcall(R.KnownSpells, R)
  if not ok or type(list) ~= "table" or #list == 0 then return nil end
  if kmCache.list == list and kmCache.n == #list then return kmCache.map end
  local m = {}
  for _, s in ipairs(list) do m[s.name] = true end
  kmCache.list, kmCache.n, kmCache.map = list, #list, m
  S.mapsMade = (S.mapsMade or 0) + 1
  return m
end

local function spellName(id)
  local n = ask("C_Spell.GetSpellName", id)
  if not n then n = ask("GetSpellInfo", id) end
  return type(n) == "string" and n or nil
end

-- the read-only readers, for the other files of this feature (ActionGlow.lua, and the later steps' files)
S.read = { ask = ask, iconOf = iconOf, cooldownLeft = cooldownLeft, usable = usable, knownMap = knownMap, spellName = spellName }

-------------------------------------------------------------------------------
-- What the strip shows now: text and textures on frames that already exist
-------------------------------------------------------------------------------
local function chosen(rec)
  local key = S.pick[rec.class]
  for i, q in ipairs(rec.seqs) do if q.key == key then return i end end
  return 1
end

-- Nov 14 2026 (17-22 review, backlog 1): the step list and the rows that stand for a step shown under another name are kept and
-- filled again on every look, not made again (a look runs up to ten times a second in a fight). So the list S:Steps returns is valid
-- until the next call of S:Steps; the callers (Update, Next) use it at once and keep nothing.
local BUF, ROWS, bufN = {}, {}, 0

-- the steps the strip shows, in order: a "once" step the player already cast and a spell the player has not learned are left out.
-- known is nil when the spellbook could not be read (every step is shown).
function S:Steps(seq, own)
  local known = own and knownMap() or nil
  local list, n = BUF, 0
  local Cond = CP.Cond
  if not (own and Cond and Cond.Enabled()) then
    -- steps 17 and 18, as they were: a condition a step carries is kept in the saved data and ignored, and a step that is a macro of the
    -- player's does not show (it needs the advanced option)
    for _, st in ipairs(seq.steps) do
      if not st.macro then
        local skip = (st.once and self.done[st.name]) or (known and not known[st.name])
        if not skip then n = n + 1 list[n] = st end
      end
    end
  else
    -- step 19, the option ON: a step may carry conditions and a macro line, and may be one of the player's macros; each says which spell it shows now
    local r = 0
    for _, st in ipairs(seq.steps) do
      if not (st.once and self.done[st.name]) then
        local name = st.name
        if st.cond or st.macro then name = Cond:Evaluate(st) end
        if name and not (known and not known[name]) then
          n = n + 1
          if name == st.name and not st.macro then list[n] = st
          else
            r = r + 1
            local row = ROWS[r]
            if not row then row = {} ROWS[r] = row end
            row.name, row.note, row.once, row.id, row.macro, row.st = name, st.note, st.once, (name == st.name) and st.id or nil, st.macro, st
            list[n] = row
          end
        end
      end
    end
  end
  for i = n + 1, bufN do list[i] = nil end
  bufN = n
  return list, known
end

-- the built-in order the player picked for a class on this game (the first one until a tab is clicked); nil when it has none
function S:Order(class)
  local forever = C.IsForever() and true or false
  local key = class .. (forever and "|forever" or "|era")
  local seqs = self.seqCache[key]
  if not seqs then seqs = CP:Sequences(class, forever) self.seqCache[key] = seqs end
  local want = self.pick[class]
  for _, q in ipairs(seqs) do if q.key == want then return q end end
  return seqs[1]
end

-- what the strip and the highlight follow for the character who is playing: the active rotation of their own (step 18), else the
-- built-in order they picked
function S:Active(class)
  local R = CP.Rot
  local v = R and R:ActiveView()
  if v then return v end
  return self:Order(class)
end

-- the step that is next for the character who is playing: the one place that answers it, for the highlight on the action bars
function S:Next()
  local class = CP:PlayerClass()
  if not class then return nil end
  local seq = self:Active(class)
  if not seq then return nil end
  local list = self:Steps(seq, true)
  return list[1]
end

-- does any step of this order name a spell in the spellbook?
function S:AnyKnown(seq, known)
  for _, st in ipairs(seq.steps) do if known[st.name] then return true end end
  return false
end

function S:Update(rec)
  if not rec then return end
  if not rec.chips then
    rec.status:SetText(self.switchWait and S.WAIT or "")
    return
  end
  -- an own rotation (step 18) shows instead of the built-in order that was picked, so no built-in tab is the picked one then
  local cv = rec.own and CP.Rot and CP.Rot:ActiveView() or nil
  local idx = (not cv) and chosen(rec) or nil
  local seq = cv or rec.seqs[idx or 1]
  -- a tab's look is drawn out of combat only (it shows and hides a mark); the title and the strip follow at once
  if not C.InCombat() then for i, tab in ipairs(rec.tabs or {}) do tab:SetActive(i == idx) end end
  if not seq then seq = { label = "", steps = {} } end
  rec.title:SetText(seq.label)
  local list, known = self:Steps(seq, rec.own)
  for i, chip in ipairs(rec.chips) do
    local st = list[i]
    if st then
      chip.icon:SetTexture(iconOf(st.name) or 134400)
      Skin.Ellipsize(chip.name, (i == 1 and "Next: " or (i .. ". ")) .. st.name, chip.textW)
      local text, col = "", Skin.colors.inkSoft
      if rec.own then
        local left = cooldownLeft(st.name)
        local ok, short = usable(st.name)
        if left and left > 0 then text, col = ("%d seconds left"):format(math.ceil(left)), Skin.colors.warn
        elseif ok == false then text, col = short and "Not enough Mana or energy" or "Not usable now", Skin.colors.warn
        elseif left == 0 or ok then text, col = "Ready", Skin.colors.ink end
      end
      chip.state:SetText(text)
      chip.state:SetTextColor(col[1], col[2], col[3], 1)
      chip.hasStep = true
    else
      chip.icon:SetTexture(nil)
      chip.name:SetText("")
      chip.state:SetText("")
      chip.hasStep = false
    end
  end
  -- the first step's words, in a box that already has room for the longest of them
  local first = list[1]
  local note = first and first.note
  if not note then
    if #seq.steps == 0 then note = seq.custom and S.NOSTEPS or (rec.own and S.NO_ORDER) or ""
    elseif seq.custom and known and not self:AnyKnown(seq, known) then note = S.NONE_KNOWN
    else note = S.EMPTY end
  end
  rec.note:SetText(note)
  local status = ""
  if self.switchWait then status = S.WAIT elseif not rec.own then status = S.OTHER elseif not known then status = S.NO_BOOK
  elseif CP.Glow and CP.Glow:BarsReplaced() then status = S.BARS_OTHER end
  rec.status:SetText(status)
end

-- every card on screen, and the highlight on the action bars (which needs no card: it works with the window closed)
function S:UpdateAll()
  for holder, rec in pairs(self.live) do
    if holder:IsVisible() then self:Update(rec) end
  end
  if CP.Glow then CP.Glow:Refresh() end
end

-- a burst of game events becomes one look a moment later (one function for all of them: nothing is made per call)
local function flush() S.queued = nil S:UpdateAll() end
function S:Queue()
  if self.queued then return end
  local any = false
  for holder in pairs(self.live) do if holder:IsVisible() then any = true break end end
  if not any and not (CP.Glow and CP.Glow:Active()) then return end
  self.queued = true
  C.After(0.1, flush)
end

function S:Pick(class, key)
  self.pick[class] = key
  -- a built-in tab clicked while an own rotation shows: the own rotation steps aside (it stays saved)
  if CP.Rot and class == CP:PlayerClass() and CP.Rot:ActiveId() then CP.Rot:SetActive(nil) end
  self:UpdateAll()
end

-------------------------------------------------------------------------------
-- The card: built once for a class, topic, level and width, and only out of combat (the page asks ViewState first)
-------------------------------------------------------------------------------
-- c is an open card of the class page (Page.lua: c:Para, c.y, c.inner); holder is the page's content frame; v the page's view
function S:Fill(c, holder, v)
  c:Para(S.INTRO)
  local sw = Skin.Check(c, "Show the next ability display", { get = function() return S:Shown() end, set = function(on) S:SetOn(on) end },
    nil, "On: the strip below shows what to press next. Off: it is hidden. " .. S.SCOPE, true)
  -- in a fight the switch only saves what the player chose (the box is drawn again when the fight ends): nothing is shown or hidden
  local drawBox = sw:GetScript("OnClick")
  sw:SetScript("OnClick", function(b, ...)
    if C.InCombat() then S:SetOn(not S:IsOn()) return end
    if drawBox then drawBox(b, ...) end
  end)
  sw:ClearAllPoints(); sw:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local _, ch = sw:FitLabel(c.inner - 27)
  c.y = c.y - ch - SP.m
  holder.seqSwitch = sw
  -- one line that a later SetText can fill (a switch flipped in a fight, another class's page, no spellbook): room for the longest
  local rec = { class = v.class, own = v.own and true or false, holder = holder }
  rec.status = Skin.Ink(c, 11, Skin.colors.inkSoft)
  local statusH = 0
  for _, s in ipairs({ S.OTHER, S.NO_BOOK, S.WAIT, S.BARS_OTHER }) do rec.status:SetText(s) statusH = math.max(statusH, TH(rec.status, c.inner)) end
  rec.status:SetWidth(c.inner); rec.status:SetHeight(statusH)
  rec.status:ClearAllPoints(); rec.status:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - statusH - SP.s
  rec.status:SetText("")
  self.live[holder] = rec
  holder.panoplySeq = rec
  -- a kept page that is shown again reads the game again (text and textures only: allowed in a fight)
  holder:SetScript("OnShow", function() S:Update(rec) end)
  if v.seqState ~= "on" then
    c:Para(S.OFF, Skin.colors.inkSoft)
    return
  end
  local seqs = CP:Sequences(v.class, v.forever)
  if #seqs == 0 and not v.own then
    c:Para(S.NO_ORDER, Skin.colors.inkSoft)
    return
  end
  rec.seqs, rec.chips, rec.tabs = seqs, {}, {}
  -- 0.9.4 step 17: the highlight on the player's own action bars (the character's own page only: it is for the class being played)
  if rec.own and CP.Glow then CP.Glow:FillControls(c, holder, rec) end
  -- step 19: the advanced macro conditions option (off by default)
  if rec.own and CP.Cond then CP.Cond:FillControls(c, holder, rec) end
  -- which order: only when the class has more than one
  if #seqs > 1 then
    for i, q in ipairs(seqs) do
      local tab = Skin.Tab(c, q.label, 120, function() S:Pick(v.class, q.key) end, q.label, "Show this order.")
      tab.panoplyPicker = true
      rec.tabs[i] = tab
    end
    local bh = Skin.FlowButtons(c, rec.tabs, PAD, c.y, c.inner, SP.s, 90)
    c.y = c.y - bh - SP.s
  end
  rec.title = Skin.Name(c, 13, Skin.colors.heading)
  c.y = put(rec.title, c, PAD, c.y, c.inner, seqs[1] and seqs[1].label or "") - SP.xs
  -- the strip: S.CHIPS boxes, two across (four when the card is wide), made once; later only their text and icon change
  local cols = c.inner >= 760 and S.CHIPS or 2
  local gap = SP.s
  local cw = math.floor((c.inner - (cols - 1) * gap) / cols)
  local probe = Skin.Name(c, 12, Skin.colors.heading)
  local probe2 = Skin.Ink(c, 11, Skin.colors.inkSoft)
  local iconSize = 28
  local textW = cw - 8 - iconSize - 8 - 6
  probe:SetText("Wg"); probe2:SetText("Wg")
  local nameH, stateH = TH(probe, textW), TH(probe2, textW)
  probe:SetText(""); probe2:SetText("")
  local chipH = math.max(iconSize + 2 * SP.s, nameH + stateH + 2 * SP.s + 2)
  for i = 1, S.CHIPS do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local f = CreateFrame("Frame", nil, c)
    f.panoplyGapOK = true
    f:SetSize(cw, chipH)
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + col * (cw + gap), c.y - row * (chipH + gap))
    Skin.Box(f, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine })
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(iconSize, iconSize)
    f.icon:SetPoint("LEFT", f, "LEFT", 8, 0)
    if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.name = Skin.Name(f, 12, Skin.colors.heading)
    if f.name.SetWordWrap then f.name:SetWordWrap(false) end
    f.name:SetSize(textW, nameH)
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + iconSize + 8, -SP.s)
    f.state = Skin.Ink(f, 11, Skin.colors.inkSoft)
    if f.state.SetWordWrap then f.state:SetWordWrap(false) end
    f.state:SetSize(textW, stateH)
    f.state:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + iconSize + 8, -SP.s - nameH - 2)
    f.textW = textW
    rec.chips[i] = f
  end
  local rows = math.ceil(S.CHIPS / cols)
  c.y = c.y - rows * chipH - (rows - 1) * gap - SP.s
  -- the words for the first step, and the one-line status: both with room for the longest text they will ever hold, so a later
  -- SetText never changes a size
  rec.note = Skin.Ink(c, 12, Skin.colors.ink)
  rec.note:SetWidth(c.inner)   -- 0.9.4: the width is set BEFORE measuring, so the wrapped height is read (without it a two-line note got 4 px too little)
  local noteH = 0
  for _, q in ipairs(seqs) do
    for _, st in ipairs(q.steps) do rec.note:SetText(st.note or "") noteH = math.max(noteH, TH(rec.note, c.inner)) end
  end
  for _, w in ipairs({ S.EMPTY, S.NOSTEPS, S.NONE_KNOWN, S.NO_ORDER }) do rec.note:SetText(w) noteH = math.max(noteH, TH(rec.note, c.inner)) end
  rec.note:SetWidth(c.inner); rec.note:SetHeight(noteH)
  rec.note:ClearAllPoints(); rec.note:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - noteH - SP.s
  c:Para(S.LIMIT, Skin.colors.inkSoft, 11)
  self:Update(rec)
end

-------------------------------------------------------------------------------
-- Game events: look again; a "once" step is done when the player's own cast of it succeeded
-------------------------------------------------------------------------------
Panoply:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if C.Readable(unit) ~= "player" then return end
  local id = C.Readable(spellID)
  local name = id and spellName(id)
  if name then S.done[name] = true end
  S:Queue()
end)
local function forget() S.done = {} S:Queue() end
Panoply:On("PLAYER_TARGET_CHANGED", forget)
Panoply:On("PLAYER_DEAD", forget)
Panoply:On("SPELL_UPDATE_COOLDOWN", function() S:Queue() end)
Panoply:On("SPELL_UPDATE_USABLE", function() S:Queue() end)
Panoply:On("UNIT_POWER_UPDATE", function(_, unit) if C.Readable(unit) == "player" then S:Queue() end end)
Panoply:On("SPELLS_CHANGED", function() kmCache.list = nil S:Queue() end)
-- a talent changed: the Rotation module's list of the spellbook is read again (its own handler drops it on SPELLS_CHANGED only), and so is
-- the map made from it. A spell learned is SPELLS_CHANGED (above): LEARNED_SPELL_IN_TAB is in neither client's event list
-- (tests/clientapi/events_era.txt and events_forever.txt; the 0.6.1 audit said the same), PLAYER_TALENT_UPDATE and
-- ACTIVE_TALENT_GROUP_CHANGED are in both. Panoply:On asks C_EventUtils.IsEventValid first and skips an event the client lacks.
local function bookChanged()
  kmCache.list = nil
  if type(Panoply.Rotation) == "table" then Panoply.Rotation.known = nil end
  S:Queue()
end
Panoply:On("PLAYER_TALENT_UPDATE", bookChanged)
Panoply:On("ACTIVE_TALENT_GROUP_CHANGED", bookChanged)
Panoply:On("PLAYER_REGEN_ENABLED", function()
  S.done = {}
  S.switchWait = nil
  if S.dirty then
    S.dirty = nil
    S:Redraw()      -- the card that waited for the end of the fight, or a switch flipped in it
  end
  S:Queue()
end)
