-- Panoply Suite 0.9.4 (next), step 18: the player's own rotations for the Rotation sequencer. DISPLAY ONLY.
--
-- A custom rotation is a named list of the player's own abilities, in the order the player wants them shown. The sequencer draws it
-- exactly as it draws the built-in order (the strip, and the highlight on the action bars of step 17). Nothing here casts, targets,
-- binds or presses anything, makes a secure frame or runs text: a rotation is plain saved data, and a shared string is read by a fixed
-- hand-written reader, never by loadstring or RunScript.
--
-- SAVED DATA, a NEW per-character saved variable (listed in the TOCs' ## SavedVariablesPerCharacter line); PanoplySuiteCharDB.rotation
-- (the old Rotation panel's key) is not read or written:
--   PanoplySuiteRotationsDB = { version = 1, nextId = n, specs = { [specKey] = { active = id | nil, list = { rotation, ... } } } }
--   rotation = { id, name, steps = { step, ... } }
--   step     = { name = "spell name" (or a macro's name), id = spell id | nil, hint = "words under the strip" | "",
--                cond = "condition text, step 19" | nil, macro = { name, index } | nil, once = true | nil }
-- specKey is "spec<n>" where the client has specialisations (GetSpecialization), else "all" (also the stable key for the moments a client
-- that has them answers nothing yet: what was filed there moves into the specialisation's list once the game names it). Created only when something is saved;
-- a table of another shape is repaired in place (its own keys only), unknown keys are kept.
-- Limits, kept on input and on import: 20 rotations per specialisation, 30 steps, names 30 characters, hints 80, conditions 160.
--
-- SHARE: "PSR1:" + body + ":" + check. The body is plain text made of letters, digits, + (a space), %XX (any other byte), "~" between
-- the name and the steps and "," between a step's fields; the check is eight hex digits of an Adler-32 style sum of the body. Import
-- treats the text as UNTRUSTED: a length cap, a fixed character set, the check, numbers for spell ids, every text stripped of the game's
-- escape codes ("|c", "|r", "|H", "|T", "|n", a lone "|") and control characters, every limit; a string that fails any of them changes
-- nothing and says why in plain words. A spell the character does not know is kept and marked "not in your spellbook"; the sequencer
-- skips it. An imported macro step keeps only the macro's NAME (the index is looked up on this computer).
-- Editing is refused in combat with a plain line; the display keeps working. Original code; no other add-on's format or code was used.
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local C = Panoply.Compat

local R = { MAX_ROT = 20, MAX_STEPS = 30, NAME_MAX = 30, HINT_MAX = 80, COND_MAX = 160, IMPORT_MAX = 32000, PREFIX = "PSR1:", VERSION = 1, rev = 0 }
CP.Rot = R

R.MSG = {
  combat = "Rotations can be changed when the fight ends. The sequencer keeps working.",
  tooMany = "You already have 20 rotations. Delete one first.",
  tooLong = "A rotation holds 30 steps at most.",
  noSpell = "That spell could not be added.",
  gone = "That rotation is not there any more.",
}

-------------------------------------------------------------------------------
-- Text: nothing the game could read as a code, no control characters, a length
-------------------------------------------------------------------------------
local function chars(s) return #(s:gsub("[\128-\191]", "")) end
R.Chars = chars

-- s with the game's escape codes and control characters taken out, spaces tidied, and cut to max characters.
-- Returns the text, and true when it had to be cut.
function R.Clean(s, max)
  s = type(s) == "string" and s or tostring(s or "")
  s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|[Hh].-|[hH]", ""):gsub("|[hH]", ""):gsub("|[Tt].-|[Tt]", ""):gsub("|[Aa].-|[Aa]", ""):gsub("|[nN]", " ")
  s = s:gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if max and chars(s) > max then
    local n, i = 0, 1
    while i <= #s do
      local b = s:byte(i)
      if b < 128 or b >= 192 then n = n + 1 if n > max then break end end
      i = i + 1
    end
    return (s:sub(1, i - 1):gsub(" $", "")), true
  end
  return s, false
end

-------------------------------------------------------------------------------
-- The saved data
-------------------------------------------------------------------------------
-- the specialisation the rotations belong to: "spec<n>" where the game has them, else "all". WHICH CLIENT ANSWERS IS UNVERIFIED.
-- Nov 14 2026 (17-22 review, backlog 5): a client that has specialisations may answer nothing for the first moments after login (or for a
-- character who has none yet). "all" is the stable key for those moments, and what was filed under it is MOVED into the specialisation's own
-- list the first time the game names one (R:Spec -> migrate): a rotation made in that window is never lost under a key that is not read again,
-- and is never filed under a specialisation that was only a guess.
function R:SpecKey()
  local ok, i = C.Call("GetSpecialization", "GetSpecialization")
  i = ok and C.Readable(i) or nil
  if type(i) == "number" and i > 0 then return "spec" .. i end
  return "all"
end

-- what was filed under "all" moves into the list of the specialisation now known: in order, after what is there, while the 20 allow;
-- the rest stays under "all" and is tried again at the next look. The active choice follows its rotation when the specialisation had none.
local function migrate(db, key)
  local from = db.specs.all
  if key == "all" or type(from) ~= "table" then return end
  local moving = type(from.list) == "table" and #from.list > 0
  if not moving then
    if next(from) == nil then db.specs.all = nil end
    return
  end
  local to = db.specs[key]
  if type(to) ~= "table" then to = {} db.specs[key] = to end
  if type(to.list) ~= "table" then to.list = {} end
  local keep, moved = {}, {}
  for _, rot in ipairs(from.list) do
    if type(rot) == "table" and #to.list < R.MAX_ROT then
      to.list[#to.list + 1] = rot
      moved[rot.id] = true
    else
      keep[#keep + 1] = rot
    end
  end
  if from.active ~= nil and moved[from.active] then
    if to.active == nil then to.active = from.active end
    from.active = nil
  end
  from.list = #keep > 0 and keep or nil
  if next(from) == nil then db.specs.all = nil end
  R.migrated = (R.migrated or 0) + 1
end

-- the saved table. Reading never makes it; a writer asks for it (create = true). One that exists in another shape is made whole in place.
function R:DB(create)
  local db = _G.PanoplySuiteRotationsDB
  if type(db) ~= "table" then
    if not create then return nil end
    db = {}
    _G.PanoplySuiteRotationsDB = db
  end
  if type(db.version) ~= "number" then db.version = R.VERSION end
  if type(db.nextId) ~= "number" then db.nextId = 1 end
  if type(db.specs) ~= "table" then db.specs = {} end
  return db
end

function R:Spec(create)
  local db = self:DB(create)
  if not db then return nil end
  local key = self:SpecKey()
  if key ~= "all" and db.specs.all ~= nil then migrate(db, key) end
  local sp = db.specs[key]
  if type(sp) ~= "table" then
    if not create then return nil end
    sp = {}
    db.specs[key] = sp
  end
  if type(sp.list) ~= "table" then
    if not create and next(sp) == nil then return nil end
    sp.list = {}
  end
  return sp
end

local NONE = {}
-- the rotations of this specialisation (never nil; do not change the table you get)
function R:List()
  local sp = self:Spec(false)
  return sp and sp.list or NONE
end

function R:Find(id)
  for i, r in ipairs(self:List()) do
    if type(r) == "table" and r.id == id then return r, i end
  end
  return nil
end

function R:ActiveId()
  local sp = self:Spec(false)
  local id = sp and sp.active
  if id and self:Find(id) then return id end
  return nil
end

function R:Active()
  local id = self:ActiveId()
  return id and self:Find(id) or nil
end

-- anything changed: the display and the editor draw again; the cached view is dropped
function R:Changed()
  self.rev = self.rev + 1
  if CP.Cond and CP.Cond.Forget then CP.Cond:Forget() end   -- the conditions read once are read again (Conditions.lua K:Evaluate)
  if CP.Seq then CP.Seq:UpdateAll() end
  if CP.Editor then CP.Editor:Changed() end
end

local function refuse(msg) return false, msg end

local function uniqueName(list, base)
  base = base ~= "" and base or "My rotation"
  local function taken(n) for _, r in ipairs(list) do if r.name == n then return true end end return false end
  if not taken(base) then return base end
  for n = 2, 99 do
    local suffix = " (" .. n .. ")"
    local cut = R.Clean(base, R.NAME_MAX - #suffix)
    local cand = cut .. suffix
    if not taken(cand) then return cand end
  end
  return (R.Clean(base, R.NAME_MAX - 4)) .. " (x)"
end

-------------------------------------------------------------------------------
-- Changes (refused in combat; every one returns true or false and a plain line)
-------------------------------------------------------------------------------
-- a rotation of this specialisation, made fresh in the saved data
local function add(self, name, steps)
  local sp = self:Spec(true)
  if #sp.list >= R.MAX_ROT then return nil, R.MSG.tooMany end
  local db = self:DB(true)
  local rot = { id = db.nextId, name = uniqueName(sp.list, (R.Clean(name or "", R.NAME_MAX))), steps = steps or {} }
  db.nextId = db.nextId + 1
  sp.list[#sp.list + 1] = rot
  return rot
end

function R:New(name)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local rot, msg = add(self, name)
  if not rot then return refuse(msg) end
  self:Changed()
  return rot.id
end

function R:Duplicate(id)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local src = self:Find(id)
  if not src then return refuse(R.MSG.gone) end
  local steps = {}
  for i, st in ipairs(src.steps) do
    local c = {}
    for k, v in pairs(st) do c[k] = type(v) == "table" and { name = v.name, index = v.index } or v end
    steps[i] = c
  end
  local rot, msg = add(self, (R.Clean(src.name .. " copy", R.NAME_MAX)), steps)
  if not rot then return refuse(msg) end
  self:Changed()
  return rot.id
end

function R:Delete(id)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local rot, i = self:Find(id)
  if not rot then return refuse(R.MSG.gone) end
  local sp = self:Spec(true)
  table.remove(sp.list, i)
  if sp.active == id then sp.active = nil end
  self:Changed()
  return true
end

function R:Rename(id, name)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local rot = self:Find(id)
  if not rot then return refuse(R.MSG.gone) end
  local clean = R.Clean(name or "", R.NAME_MAX)
  if clean == "" then return refuse("A rotation needs a name.") end
  if clean ~= rot.name then
    local others = {}
    for _, r in ipairs(self:List()) do if r ~= rot then others[#others + 1] = r end end
    rot.name = uniqueName(others, clean)
    self:Changed()
  end
  return true
end

-- which rotation shows: an id, or nil for the built-in order. Only data: allowed in a fight, so the strip can be switched at any time.
function R:SetActive(id)
  if id ~= nil and not self:Find(id) then return refuse(R.MSG.gone) end
  if id == nil and not self:ActiveId() then return true end
  local sp = self:Spec(true)
  sp.active = id
  self:Changed()
  return true
end

-- back to the built-in order; the rotations stay saved
function R:Reset() return self:SetActive(nil) end

local function stepList(self, id)
  local rot = self:Find(id)
  if not rot then return nil end
  if type(rot.steps) ~= "table" then rot.steps = {} end
  return rot.steps, rot
end

-- a spell from the spellbook: its id and name
function R:AddSpell(id, spellId, spellName)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local steps = stepList(self, id)
  if not steps then return refuse(R.MSG.gone) end
  if #steps >= R.MAX_STEPS then return refuse(R.MSG.tooLong) end
  local name = R.Clean(spellName or "", 60)
  if name == "" then return refuse(R.MSG.noSpell) end
  spellId = type(spellId) == "number" and spellId > 0 and spellId == math.floor(spellId) and spellId or nil
  steps[#steps + 1] = { name = name, id = spellId, hint = "" }
  self:Changed()
  return true, #steps
end

-- one of the player's own macros, by name (step 19; only its name and place are kept, never its text)
function R:AddMacro(id, macroName, index)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local steps = stepList(self, id)
  if not steps then return refuse(R.MSG.gone) end
  if #steps >= R.MAX_STEPS then return refuse(R.MSG.tooLong) end
  local name = R.Clean(macroName or "", 60)
  if name == "" then return refuse(R.MSG.noSpell) end
  steps[#steps + 1] = { name = name, hint = "", macro = { name = name, index = tonumber(index) } }
  self:Changed()
  return true, #steps
end

function R:RemoveStep(id, i)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local steps = stepList(self, id)
  if not steps or not steps[i] then return refuse(R.MSG.gone) end
  table.remove(steps, i)
  self:Changed()
  return true
end

-- dir -1 = up, +1 = down; returns true and the step's new place
function R:MoveStep(id, i, dir)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local steps = stepList(self, id)
  local j = i + (dir < 0 and -1 or 1)
  if not steps or not steps[i] then return refuse(R.MSG.gone) end
  if j < 1 or j > #steps then return refuse("It is already at the " .. (dir < 0 and "top." or "bottom.")) end
  steps[i], steps[j] = steps[j], steps[i]
  self:Changed()
  return true, j
end

local function stepOf(self, id, i)
  local steps = stepList(self, id)
  return steps and steps[i] or nil
end

function R:SetHint(id, i, text)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local st = stepOf(self, id, i)
  if not st then return refuse(R.MSG.gone) end
  st.hint = R.Clean(text or "", R.HINT_MAX)
  self:Changed()
  return true
end

function R:SetCond(id, i, text)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local st = stepOf(self, id, i)
  if not st then return refuse(R.MSG.gone) end
  local clean = R.Clean(text or "", R.COND_MAX)
  st.cond = clean ~= "" and clean or nil
  self:Changed()
  return true
end

function R:SetOnce(id, i, once)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local st = stepOf(self, id, i)
  if not st then return refuse(R.MSG.gone) end
  st.once = once and true or nil
  self:Changed()
  return true
end

-------------------------------------------------------------------------------
-- What the sequencer draws: the active rotation as an order
-------------------------------------------------------------------------------
-- { key, label, custom = true, rot, steps = { { name, id, note, once, cond, macro } } } for the active rotation, or nil.
-- (Every step is in it, including a spell not in the spellbook: the sequencer skips those like it skips an unlearned built-in step.)
function R:ActiveView()
  local rot = self:Active()
  if not rot or type(rot.steps) ~= "table" then return nil end
  local c = self.viewCache
  if c and c.rot == rot and c.rev == self.rev and c.n == #rot.steps then return c.view end
  local steps = {}
  for _, st in ipairs(rot.steps) do
    if type(st) == "table" and type(st.name) == "string" then
      steps[#steps + 1] = { name = st.name, id = st.id, note = st.hint or "", once = st.once and true or false, cond = st.cond, macro = st.macro, custom = true }
    end
  end
  local view = { key = "custom:" .. tostring(rot.id), label = rot.name, steps = steps, custom = true, rot = rot }
  self.viewCache = { rot = rot, rev = self.rev, n = #rot.steps, view = view }
  return view
end

-- the spells the character can cast, for the picker: { { name, icon, id } } in spellbook order (the Rotation module reads them)
function R:Spellbook()
  local K = Panoply.Rotation
  if type(K) ~= "table" or type(K.KnownSpells) ~= "function" then return {} end
  local ok, list = pcall(K.KnownSpells, K)
  return ok and type(list) == "table" and list or {}
end

-- is this step's spell in the spellbook? nil when the spellbook could not be read
function R:StepKnown(st)
  if st.macro then return true end
  local known = CP.Seq and CP.Seq.read.knownMap()
  if not known then return nil end
  return known[st.name] == true
end

-------------------------------------------------------------------------------
-- Share and import
-------------------------------------------------------------------------------
local function enc(s)
  return (s:gsub("[^A-Za-z0-9]", function(ch) if ch == " " then return "+" end return ("%%%02X"):format(ch:byte()) end))
end
local function dec(s)
  return (s:gsub("%+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function check(body)
  local a, b = 1, 0
  for i = 1, #body do a = (a + body:byte(i)) % 65521 b = (b + a) % 65521 end
  return ("%04X%04X"):format(b, a)
end
R.Checksum = check

function R:Export(id)
  local rot = self:Find(id)
  if not rot then return nil, R.MSG.gone end
  local parts = { enc(rot.name) }
  for _, st in ipairs(rot.steps) do
    local kind = st.macro and "M" or ("S" .. tostring(st.id or 0))
    parts[#parts + 1] = table.concat({ kind, enc(st.name or ""), enc(st.hint or ""), enc(st.cond or ""), st.once and "1" or "0" }, ",")
  end
  local body = table.concat(parts, "~")
  return R.PREFIX .. body .. ":" .. check(body)
end

local function bad(msg) return nil, msg end

-- Reads a shared string. Returns a table { name, steps } on success, or nil and a plain reason. Changes nothing.
function R:Read(text)
  if type(text) ~= "string" then return bad("Paste a shared rotation first.") end
  if #text > R.IMPORT_MAX * 2 then return bad("That text is far too long to be a rotation.") end
  text = text:gsub("%s+", "")
  if text == "" then return bad("Paste a shared rotation first.") end
  if #text > R.IMPORT_MAX then return bad("That text is too long to be a rotation.") end
  if text:sub(1, #R.PREFIX) ~= R.PREFIX then return bad("That is not a shared rotation: it should begin with " .. R.PREFIX) end
  local body, sum = text:match("^PSR1:([^:]*):(%x%x%x%x%x%x%x%x)$")
  if not body then return bad("That text is not complete: a shared rotation ends with a check number after a colon.") end
  if not body:match("^[A-Za-z0-9+%%~,]*$") then return bad("That text has characters a shared rotation never has.") end
  if check(body) ~= sum:upper() then return bad("The check number does not match: the text was changed or cut short when it was copied.") end
  local out = { steps = {} }
  local first = true
  for part in (body .. "~"):gmatch("(.-)~") do
    if first then
      first = false
      local raw = dec(part)
      local name, cut = R.Clean(raw, R.NAME_MAX)
      if cut then return bad("The rotation's name is longer than " .. R.NAME_MAX .. " characters.") end
      out.name = name
    else
      local f = {}
      for field in (part .. ","):gmatch("(.-),") do f[#f + 1] = field end
      if #f ~= 5 then return bad("A step in that text is not in the shape a shared rotation has.") end
      local st = {}
      local kind = f[1]
      if kind == "M" then
        st.macro = {}
      else
        local n = kind:match("^S(%d+)$")
        if not n or #n > 8 then return bad("A spell number in that text is not a number.") end
        n = tonumber(n)
        if n ~= math.floor(n) or n > 10000000 then return bad("A spell number in that text is out of range.") end
        st.id = n > 0 and n or nil
      end
      local name, cutName = R.Clean(dec(f[2]), 60)
      local hint, cutHint = R.Clean(dec(f[3]), R.HINT_MAX)
      local cond, cutCond = R.Clean(dec(f[4]), R.COND_MAX)
      if cutName then return bad("A spell name in that text is too long.") end
      if cutHint then return bad("A hint in that text is longer than " .. R.HINT_MAX .. " characters.") end
      if cutCond then return bad("A condition in that text is longer than " .. R.COND_MAX .. " characters.") end
      if name == "" then return bad("A step in that text has no name.") end
      if f[5] ~= "0" and f[5] ~= "1" then return bad("A step in that text has a damaged flag.") end
      st.name, st.hint, st.cond, st.once = name, hint, cond ~= "" and cond or nil, f[5] == "1" or nil
      if st.macro then st.macro = { name = name } end
      out.steps[#out.steps + 1] = st
      if #out.steps > R.MAX_STEPS then return bad("A rotation holds " .. R.MAX_STEPS .. " steps at most, and that one has more.") end
    end
  end
  return out
end

-- Adds the rotation in a shared string as a NEW one (never the active one). Returns its id, or nil and the reason; a refusal changes nothing.
function R:Import(text)
  if C.InCombat() then return refuse(R.MSG.combat) end
  local rot, why = self:Read(text)
  if not rot then return nil, why end
  local made, msg = add(self, rot.name ~= "" and rot.name or "Shared rotation", rot.steps)
  if not made then return nil, msg end
  self:Changed()
  return made.id
end
