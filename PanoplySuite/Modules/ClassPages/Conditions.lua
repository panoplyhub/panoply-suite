-- Panoply Suite 0.9.4 (next), step 19: macro-style conditions for the Rotation sequencer. An OPTION, OFF by default. DISPLAY ONLY.
--
-- With "Advanced macro conditions" OFF nothing in this file is read or evaluated: the sequencer works exactly as in steps 17 and 18
-- (Sequencer.lua S:Steps takes its plain path), and a condition saved earlier stays in the saved data, ignored. With it ON a step of a
-- rotation (built-in steps carry none) may carry a condition text, and a rotation may hold steps that are the player's own macros.
--   condition text = zero or more {helper conditions}, then optionally ONE macro line
--       {target.hp<20} {mana>30, !buff:Aspect of the Hawk} [@target,harm,nodead] Serpent Sting; [mod:shift] Multi-Shot
--   * The macro line is evaluated by the game's own macro rules with SecureCmdOptionParse, READ ONLY: it returns the text of the first
--     clause whose [conditions] hold; it casts nothing. A nil or empty answer, a call that errors or that does not exist means "skip this
--     step". The answer is resolved to a spell with the spell-info call and that spell is what the strip shows and the highlight lights.
--     This is the only file that names that call.
--   * The helpers are a small grammar of our own, read by the hand-written parser below (never loadstring, never a macro): all of them must
--     be true for the step to show. A helper the parser cannot read, or one this game cannot answer, makes the step count as false and the
--     editor marks it "can't read this condition".
--       target.hp<20  player.hp>=50        health in percent                  (UnitHealth, UnitHealthMax)
--       mana>30  rage<20  energy>=40  focus>10   the character's own power in percent   (UnitPower, UnitPowerMax)
--       buff:Name  debuff:Name  [!]         present on you / on your target (your own debuffs only); with <, >, <=, >=, = and seconds:
--                                           a missing effect counts as 0 seconds left; target.buff:Name and self.debuff:Name read the other unit
--       ready:Name                          the spell is known and off cooldown
--       proc:Name                           the game's spell highlight for it is lit; where the client does not say, the spell is usable
--       !                                   in front of buff, debuff, ready, proc: "is not"
--     "Number of nearby enemies" is NOT offered (see Cond.ENEMIES_WHY): the game has no call that counts enemies, and counting name plates is
--     the only way and is unreliable. {enemies>=3} reads as an unavailable condition.
--   * A macro step holds only the macro's NAME and place (CustomRotations.lua); the strip shows the spell GetMacroSpell reports for it now. The
--     macro's text is never read into anything, edited or run.
-- Reads only: SecureCmdOptionParse, GetMacroInfo, GetNumMacros, GetMacroSpell, the unit, aura, power, cooldown and spell calls, each through
-- Panoply.Compat's C.Call (pcall-guarded; a missing call is a "false", not an error). WHICH OF THEM EXIST AND ANSWER AS READ HERE ON EACH GAME, AND
-- WHETHER SecureCmdOptionParse MAY BE CALLED FROM ADD-ON CODE IN COMBAT, IS UNVERIFIED in the real game.
-- Original code; no other add-on's code or grammar was used.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local C = Panoply.Compat

local K = { procs = {}, MAX_ITEMS = 12 }
CP.Cond = K

K.LABEL = "Advanced macro conditions"
K.TIP = "On: a step of your own rotation can carry conditions (health, power, effects, cooldowns, the game's own macro conditions) and a rotation can hold your own macros. They only decide what the strip shows; nothing is cast or pressed for you. Off: steps are plain."
K.ENEMIES_WHY = "The number of nearby enemies is not offered: the game has no call that counts them, and counting name plates misses enemies whose plates are off."
K.HELP = {
  "Put conditions in curly brackets before the rest, and every one must be true: {target.hp<20} {mana>30}. Several can share one pair, separated by commas.",
  "Health: target.hp or player.hp, then < > <= >= or = and a percent. Your own power: mana, rage, energy or focus the same way.",
  "Effects: buff:Name is on you, debuff:Name is on your target and yours. Add seconds: debuff:Serpent Sting<3 is true when it is missing or has under 3 seconds left. ! in front means is not there: !buff:Name.",
  "Spells: ready:Name is known and off cooldown. proc:Name is lit by the game's spell highlight where the game says so, else usable.",
  "After the brackets you may add a macro line in the game's own macro rules: [@target,harm,nodead] Serpent Sting; [mod:shift] Multi-Shot. The first part that matches decides the spell shown.",
  K.ENEMIES_WHY,
}

local function S() return CP.Seq end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-------------------------------------------------------------------------------
-- The option (a new saved key, only written after a change)
-------------------------------------------------------------------------------
function K.Enabled()
  local d = Panoply.cdb and Panoply.cdb.classAdvanced
  return type(d) == "table" and d.on == true
end

-- true when applied at once; false when the drawing waits for the end of the fight (the evaluation itself changes at once)
function K:SetEnabled(on)
  if not Panoply.cdb then return false end
  if type(Panoply.cdb.classAdvanced) ~= "table" then Panoply.cdb.classAdvanced = {} end
  Panoply.cdb.classAdvanced.on = on and true or false
  local seq = S()
  if C.InCombat() then
    seq.dirty, seq.switchWait = true, true
    seq:UpdateAll()
    return false
  end
  seq:Redraw()
  seq:UpdateAll()
  if CP.Editor then CP.Editor:Changed() end
  return true
end

-------------------------------------------------------------------------------
-- Reading the game (read only)
-------------------------------------------------------------------------------
local function unitExists(unit)
  local ok, v = C.Call("UnitExists", "UnitExists", unit)
  return ok and v and true or false
end

-- a percent 0 to 100 from two game calls, or nil when the game did not say
local function percent(cur, max)
  cur, max = C.Readable(cur), C.Readable(max)
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
  return cur / max * 100
end

local function health(unit)
  if not unitExists(unit) then return nil end
  local ok1, cur = C.Call("UnitHealth", "UnitHealth", unit)
  local ok2, max = C.Call("UnitHealthMax", "UnitHealthMax", unit)
  if not (ok1 and ok2) then return nil end
  return percent(cur, max)
end

local POWER = { mana = 0, rage = 1, focus = 2, energy = 3 }
local function power(name)
  local id = C.G("Enum.PowerType." .. name:sub(1, 1):upper() .. name:sub(2)) or POWER[name]
  local ok1, cur = C.Call("UnitPower", "UnitPower", "player", id)
  local ok2, max = C.Call("UnitPowerMax", "UnitPowerMax", "player", id)
  if not (ok1 and ok2) then return nil end
  return percent(cur, max)
end

-- seconds left on an effect of this name (math.huge when it has no end), nil when it is not there. Debuffs on the target are the
-- player's own only; buffs and a debuff on yourself are anyone's.
local function auraLeft(unit, name, harmful)
  local filter = harmful and (unit == "target" and "HARMFUL|PLAYER" or "HARMFUL") or "HELPFUL"
  local byIndex = C.G("C_UnitAuras.GetAuraDataByIndex")
  local now = C.GetTime()
  for i = 1, 60 do
    local n, exp
    if type(byIndex) == "function" then
      local ok, d = C.Call("GetAuraDataByIndex", "C_UnitAuras.GetAuraDataByIndex", unit, i, filter)
      if not ok or type(d) ~= "table" then break end
      n, exp = C.Readable(d.name), C.Readable(d.expirationTime)
    else
      local ok, nm, _, _, _, _, ex = C.Call("UnitAura", "UnitAura", unit, i, filter)
      if not ok or nm == nil then break end
      n, exp = C.Readable(nm), C.Readable(ex)
    end
    if n == name and type(exp) == "number" then
      if exp == 0 then return math.huge end
      local left = exp - now
      return left > 0 and left or 0
    end
  end
  return nil
end

local function spellId(name)
  local ok, info = C.Call("GetSpellInfo", "C_Spell.GetSpellInfo", name)
  if ok and type(info) == "table" then return C.Readable(info.spellID) end
  local ok2, _, _, _, _, _, _, id = C.Call("GetSpellInfo", "GetSpellInfo", name)
  if ok2 then return C.Readable(id) end
  return nil
end

-- how "proc" is answered on this client: the game's overlay call, else its overlay events, else the spell being usable
function K:ProcSource()
  if type(C.G("C_SpellActivationOverlay.IsSpellOverlayed")) == "function" or type(C.G("IsSpellOverlayed")) == "function" then return "api" end
  local skipped = Panoply.skippedEvents
  if not (skipped and (skipped.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW or skipped.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE)) then return "events" end
  return "usable"
end

local function procActive(name)
  local id = spellId(name)
  local src = K:ProcSource()
  if src == "api" and id then
    local ok, v = C.Call("IsSpellOverlayed", "C_SpellActivationOverlay.IsSpellOverlayed", id)
    if not ok then ok, v = C.Call("IsSpellOverlayed", "IsSpellOverlayed", id) end
    if ok then return v and true or false end
  elseif src == "events" and id then
    return K.procs[id] and true or false
  end
  local usable = S().read.usable(name)
  return usable == true
end

-- what this game can answer, for the editor's help and the log
function K:Availability()
  return { enemies = false, enemiesWhy = K.ENEMIES_WHY, proc = self:ProcSource(), secureParse = type(C.G("SecureCmdOptionParse")) == "function",
    auraApi = type(C.G("C_UnitAuras.GetAuraDataByIndex")) == "function" and "C_UnitAuras" or (type(C.G("UnitAura")) == "function" and "UnitAura" or "none") }
end

-------------------------------------------------------------------------------
-- The helper grammar (fixed; a hand-written reader)
-------------------------------------------------------------------------------
local OPS = {
  ["<"] = function(a, b) return a < b end, [">"] = function(a, b) return a > b end,
  ["<="] = function(a, b) return a <= b end, [">="] = function(a, b) return a >= b end,
  ["="] = function(a, b) return a == b end,
}

local function goodName(n)
  n = trim(n)
  if n == "" or #n > 60 then return nil end
  if n:find("[%c{}%[%]<>=!;|,]") then return nil end
  return n
end

-- one helper, as a table, or nil and a plain reason
local function parseItem(raw)
  local s = trim(raw)
  if s == "" then return nil, "a condition between the brackets is empty" end
  local neg = false
  if s:sub(1, 1) == "!" then neg, s = true, trim(s:sub(2)) end
  local left, op, num = s:match("^(.-)%s*([<>=][=]?)%s*(%-?%d[%d%.]*)$")
  if op then
    if not OPS[op] then return nil, "'" .. op .. "' is not a comparison it knows" end
    num = tonumber(num)
    if not num then return nil, "that is not a number" end
    if neg then return nil, "! cannot go with a comparison" end
    local unit = left:match("^(target)%.hp$") or left:match("^(player)%.hp$")
    if unit then return { kind = "hp", unit = unit, op = op, num = num } end
    if POWER[left] then return { kind = "power", power = left, op = op, num = num } end
    if left == "enemies" then return { kind = "enemies", op = op, num = num } end
    local u, k, name = left:match("^(%a+)%.(%a+):(.+)$")
    if not u then k, name = left:match("^(%a+):(.+)$") end
    if k == "buff" or k == "debuff" then
      if u and u ~= "self" and u ~= "target" then return nil, "'" .. u .. "' is not a unit it knows (self or target)" end
      name = goodName(name)
      if not name then return nil, "an effect name is missing or has a character it cannot have" end
      return { kind = "aura", harmful = k == "debuff", unit = u == "self" and "player" or u or (k == "debuff" and "target" or "player"), name = name, op = op, num = num }
    end
    return nil, "'" .. left .. "' is not a condition it knows"
  end
  local u, k, name = s:match("^(%a+)%.(%a+):(.+)$")
  if not u then k, name = s:match("^(%a+):(.+)$") end
  if k == "buff" or k == "debuff" then
    if u and u ~= "self" and u ~= "target" then return nil, "'" .. u .. "' is not a unit it knows (self or target)" end
    name = goodName(name)
    if not name then return nil, "an effect name is missing or has a character it cannot have" end
    return { kind = "aura", harmful = k == "debuff", unit = u == "self" and "player" or u or (k == "debuff" and "target" or "player"), name = name, neg = neg }
  elseif (k == "ready" or k == "proc") and not u then
    name = goodName(name)
    if not name then return nil, "a spell name is missing or has a character it cannot have" end
    return { kind = k, name = name, neg = neg }
  end
  return nil, "'" .. s .. "' is not a condition it knows"
end

-- text -> { helpers = { item, ... }, macro = "line" | nil }, or nil and a plain reason
function K.Parse(text)
  text = trim(text)
  local helpers = {}
  while true do
    text = text:gsub("^%s+", "")
    if text:sub(1, 1) ~= "{" then break end
    local close = text:find("}", 2, true)
    if not close then return nil, "a { has no closing }" end
    for piece in (text:sub(2, close - 1) .. ","):gmatch("([^,]*),") do
      local item, err = parseItem(piece)
      if not item then return nil, err end
      helpers[#helpers + 1] = item
      if #helpers > K.MAX_ITEMS then return nil, "there are more than " .. K.MAX_ITEMS .. " conditions" end
    end
    text = text:sub(close + 1)
  end
  local macro = trim(text)
  if macro:find("[{}]") then return nil, "a bracket { or } is in the wrong place" end
  local opens = select(2, macro:gsub("%[", ""))
  local closes = select(2, macro:gsub("%]", ""))
  if opens ~= closes then return nil, "a [ bracket has no matching ]" end
  return { helpers = helpers, macro = macro ~= "" and macro or nil }
end

-- is this item true now? (false when the game did not say)
function K:Test(item)
  local k = item.kind
  if k == "hp" then
    local v = health(item.unit)
    return v ~= nil and OPS[item.op](v, item.num)
  elseif k == "power" then
    local v = power(item.power)
    return v ~= nil and OPS[item.op](v, item.num)
  elseif k == "aura" then
    local left = auraLeft(item.unit, item.name, item.harmful)
    if item.op then return OPS[item.op](left or 0, item.num) end
    local present = left ~= nil
    if item.neg then return not present end
    return present
  elseif k == "ready" then
    local R = S().read
    local known = R.knownMap()
    if known and not known[item.name] then return item.neg and true or false end
    local left = R.cooldownLeft(item.name)
    local ready = left == 0
    if item.neg then return not ready end
    return ready
  elseif k == "proc" then
    local on = procActive(item.name)
    if item.neg then return not on end
    return on
  end
  return false     -- "enemies": not offered on any game
end

-- can this text be read by this game? Returns true, or false and the reason (the editor marks it). isMacroStep: a macro step takes helpers only.
function K:Check(text, isMacroStep)
  local p, err = K.Parse(text)
  if not p then return false, err end
  for _, item in ipairs(p.helpers) do
    if item.kind == "enemies" then return false, K.ENEMIES_WHY end
  end
  if p.macro and isMacroStep then return false, "a macro step takes conditions in curly brackets only" end
  if p.macro and type(C.G("SecureCmdOptionParse")) ~= "function" then return false, "this game cannot read macro conditions here" end
  return true
end

-------------------------------------------------------------------------------
-- Macros: the player's own, by name and place; never their text
-------------------------------------------------------------------------------
local function macroCount()
  local ok, acc, chr = C.Call("GetNumMacros", "GetNumMacros")
  if not ok then return 0, 0 end
  return tonumber(C.Readable(acc)) or 0, tonumber(C.Readable(chr)) or 0
end

local function macroName(i)
  local ok, name = C.Call("GetMacroInfo", "GetMacroInfo", i)     -- (the macro's text is the third answer and is dropped here)
  name = ok and C.Readable(name) or nil
  return type(name) == "string" and name or nil
end

-- the index of the macro a step points at: by its name first (indexes move), else its saved place when the name still matches
function K:MacroIndex(ref)
  if type(ref) ~= "table" or type(ref.name) ~= "string" then return nil end
  local acc, chr = macroCount()
  for i = 1, acc do if macroName(i) == ref.name then return i end end
  for i = 121, 120 + chr do if macroName(i) == ref.name then return i end end
  if ref.index and macroName(ref.index) == ref.name then return ref.index end
  return nil
end

-- the spell name the game says the macro at this place would cast now, or nil (Classic answers a name, WoW Forever an id: both are read)
function K:MacroSpellAt(idx)
  if type(idx) ~= "number" then return nil end
  local ok, a, _, c3 = C.Call("GetMacroSpell", "GetMacroSpell", idx)
  if not ok then return nil end
  a, c3 = C.Readable(a), C.Readable(c3)
  if type(a) == "string" and a ~= "" then return a end
  local id = type(a) == "number" and a or (type(c3) == "number" and c3) or nil
  return id and S().read.spellName(id) or nil
end

-- the same for a step's macro reference (found by name)
function K:MacroSpell(ref)
  return self:MacroSpellAt(self:MacroIndex(ref))
end

function K:MacroSpellText(ref)
  if not self:MacroIndex(ref) then return "macro not found" end
  local sp = self:MacroSpell(ref)
  return sp and ("casts " .. sp .. " now") or "no spell now"
end

-- the macros to pick from: { { name, icon, index, state } }, the account's then the character's; names and icons only
function K:Macros()
  local out = {}
  local acc, chr = macroCount()
  local function add(i)
    local ok, name, icon = C.Call("GetMacroInfo", "GetMacroInfo", i)
    name = ok and C.Readable(name) or nil
    if type(name) == "string" then
      local ref = { name = name, index = i }
      out[#out + 1] = { name = name, icon = C.Readable(icon), index = i, state = self:MacroSpellText(ref) }
    end
  end
  for i = 1, acc do add(i) end
  for i = 121, 120 + chr do add(i) end
  return out
end

-------------------------------------------------------------------------------
-- The one answer the sequencer asks for a step (only with the option ON)
-------------------------------------------------------------------------------
-- Which spell does this step show now? A spell name, or nil: skip the step.
-- Nov 14 2026 (17-22 review, backlog 1): a step's condition text is read once, not on every look (up to ten a second in a fight). The read
-- form is kept for the step table (weak keys: a step that is gone takes its entry with it) and used while the text is the same; an edit
-- changes the text, and a change to the rotation drops every entry (R:Changed -> K:Forget).
local parsedCache = setmetatable({}, { __mode = "k" })
function K:Forget() parsedCache = setmetatable({}, { __mode = "k" }) end
local function parsedOf(st, text)
  local e = parsedCache[st]
  if e and e.text == text then return e.p end
  local p = K.Parse(text)
  K.parsedCount = (K.parsedCount or 0) + 1
  parsedCache[st] = { text = text, p = p or false }
  return p
end

-------------------------------------------------------------------------------
-- Secret values (0.9.5 phase 4H, spec 03a section 2): WoW Forever may keep some combat information secret from add-ons. The probe
-- (Core/Probe.lua, /panoply probe; it reruns by itself on a new game build) records each input this file reads as readable or secret,
-- in combat, for this client. A helper whose input is secret is greyed in the editor ("The game doesn't share this in combat") and
-- skipped in a fight: the step is then shown in its fixed place in the order, as if the helper were not there. A macro line whose
-- SecureCmdOptionParse answer is secret falls back to the step's own spell. Nothing fails silently: the editor says which input.
-------------------------------------------------------------------------------
K.SECRET_TIP = "The game doesn't share this in combat"
K.INPUT = { hp = "targetHealth", power = "power", aura = "auras", ready = "cooldown", proc = "proc" }
K.INPUT_WORDS = { targetHealth = "health", power = "power", auras = "effects", cooldown = "cooldowns", proc = "spell highlights",
  macro = "macro conditions" }

-- is this input secret in combat on this client? (unknown = not asked yet: treated as readable)
function K:InputSecret(name)
  local P = Panoply.Probe
  return name ~= nil and P ~= nil and P.Input ~= nil and P:Input(name, "combat") == "secret"
end

-- the inputs a read condition needs that this client keeps secret in combat: a list of probe names, in a fixed order
function K:SecretInputs(p)
  local out, seen = {}, {}
  local function add(n) if n and not seen[n] and self:InputSecret(n) then seen[n] = true out[#out + 1] = n end end
  for _, item in ipairs(p and p.helpers or {}) do add(K.INPUT[item.kind]) end
  if p and p.macro then add("macro") end
  table.sort(out)
  return out
end

-- the editor's line for a condition text that needs a secret input, or nil
function K:SecretNote(text)
  local p = text and text ~= "" and K.Parse(text) or nil
  if not p then return nil end
  local list = self:SecretInputs(p)
  if #list == 0 then return nil end
  local words = {}
  for i, n in ipairs(list) do words[i] = K.INPUT_WORDS[n] or n end
  return ("%s (%s). In a fight that part is skipped and the step keeps its place in the order."):format(K.SECRET_TIP, table.concat(words, ", "))
end

function K:Evaluate(st)
  local text = st.cond
  local p
  local fight = C.InCombat()
  if text and text ~= "" then
    p = parsedOf(st, text)
    if not p then return nil end
    for _, item in ipairs(p.helpers) do
      -- a helper this client keeps secret in combat is skipped there: the step keeps its fixed place (spec 03a section 2)
      if not (fight and self:InputSecret(K.INPUT[item.kind])) and not self:Test(item) then return nil end
    end
  end
  if st.macro then
    if p and p.macro then return nil end
    return self:MacroSpell(st.macro)
  end
  if p and p.macro and fight and self:InputSecret("macro") then return st.name end
  if p and p.macro then
    local ok, action = C.Call("SecureCmdOptionParse", "SecureCmdOptionParse", p.macro)
    action = ok and C.Readable(action) or nil
    if type(action) ~= "string" then return nil end
    action = trim(action):gsub("^!", "")
    if action == "" then return nil end
    return S().read.spellName(action)
  end
  return st.name
end

-------------------------------------------------------------------------------
-- The switch on the sequencer card (own class page)
-------------------------------------------------------------------------------
function K:FillControls(c, holder, rec)
  local PAD = 12
  local Skin = Panoply.Skin
  local chk = Skin.Check(c, K.LABEL, { get = function() return K.Enabled() end, set = function(on) K:SetEnabled(on) end }, nil, K.TIP, true)
  -- in a fight the choice is saved and takes effect at once, but the card (which fields are drawn) changes when the fight ends
  local draw = chk:GetScript("OnClick")
  chk:SetScript("OnClick", function(b, ...)
    if C.InCombat() then K:SetEnabled(not K.Enabled()) return end
    if draw then draw(b, ...) end
  end)
  chk:ClearAllPoints(); chk:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local _, ch = chk:FitLabel(c.inner - 27)
  c.y = c.y - ch - Skin.SP.m
  holder.advSwitch = chk
end

-------------------------------------------------------------------------------
-- Game events and the settings search
-------------------------------------------------------------------------------
Panoply:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, id) id = C.Readable(id) if type(id) == "number" then K.procs[id] = true if S() then S():Queue() end end end)
Panoply:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, id) id = C.Readable(id) if type(id) == "number" then K.procs[id] = nil if S() then S():Queue() end end end)
Panoply:On("UPDATE_MACROS", function() if K.Enabled() and S() then S():Queue() end end)
Panoply:On("PLAYER_TARGET_CHANGED", function() if K.Enabled() and S() then S():Queue() end end)
Panoply:On("UNIT_AURA", function(_, unit) unit = C.Readable(unit) if K.Enabled() and (unit == "player" or unit == "target") and S() then S():Queue() end end)
Panoply:On("MODIFIER_STATE_CHANGED", function() if K.Enabled() and S() then S():Queue() end end)
Panoply:On("PLAYER_REGEN_DISABLED", function() if K.Enabled() and S() then S():Queue() end end)

do
  local Cat = Panoply.Catalog
  if Cat and type(Cat.ACTIONS) == "table" then
    table.insert(Cat.ACTIONS, { id = "action:seqadvanced", label = K.LABEL, words = "rotation sequencer macro conditions conditional steps health mana buff debuff cooldown class",
      page = "class", run = function() if CP.Open then CP:Open(nil, "rotation") end end })
  end
end
