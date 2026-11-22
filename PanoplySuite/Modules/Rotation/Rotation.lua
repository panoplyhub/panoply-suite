-- Spell-name and spellbook helpers for the class pages' Rotation sequencer (Modules/ClassPages/Sequencer.lua), READ-ONLY.
--
-- 0.9.4 (next): the old Rotation panel is GONE (14 Nov 2026: "Remove it"). That was a secure button the player clicked or
-- keyed that fired a /castsequence line out of an order of their own spells, with its panel (Modules/Rotation/Panel.lua, deleted)
-- and the label "Beta - more rotations coming soon". Nothing here creates a secure button, sets a secure attribute, casts, targets,
-- binds a key or saves anything. tests/rotation_tests.lua scans every file of the add-on for a rotation secure button or a
-- castsequence / macrotext attribute and fails if one comes back.
--
-- What is kept, and why:
--   * R.CleanName(name)  a plain one-line spell name, or nil and why not
--   * R.SpellIcon(name)  the game's icon for a spell name (nil when it cannot be asked)
--   * R:KnownSpells()    the spells the character knows, in spellbook order: { { name, icon, id } } (id: the newest rank's spell id, when the
--                        game says it; step 18's spell picker stores it). The sequencer card calls it to
--                        leave out the steps the player has not learned. It is cleared on SPELLS_CHANGED (asked again next time).
-- They were written for the old panel; the sequencer is their one caller now, so they stay in this module (Panoply.Rotation) and no
-- caller changed.
--
-- The one thing that is not a helper: a player may still have a key bound to the old button (a CLICK binding on
-- "PanoplySuiteRotationButton"). 0.9.4 kept the binding in Bindings.xml for one release; 0.9.5 (phase 8, queue item 5a) takes it
-- out of Bindings.xml and Key Bindings. The frame name stays: a key bound before still lands on a PLAIN button (no secure
-- template, no attributes) whose click says once in chat that the button was removed. It casts nothing.
--
-- Saved data: the old panel wrote PanoplySuiteCharDB.rotation = { steps, reset, shown, pos }. Nothing reads or writes it any more;
-- it is left exactly as it is so an old account loads unchanged (tests/rotation_tests.lua).
-- Original code; no other add-on's code, layout or spell lists were used.
local ADDON, Panoply = ...
local C = Panoply.Compat

local R = {}
Panoply.Rotation = R

R.NAME_LIMIT = 60
R.BUTTON = "PanoplySuiteRotationButton"          -- only the name a saved key binding points at (see the bottom of this file)
R.BINDING = "CLICK " .. R.BUTTON .. ":LeftButton"
R.REMOVED = "The rotation button was removed, so this key does nothing now. You can give the key to something else in the game's Key Bindings."

-- A spell name the game's own APIs can be asked about, or nil and why not.
function R.CleanName(name)
  if type(name) ~= "string" then return nil, "That is not a spell name." end
  if name:find("%c") then return nil, "A spell name is one line of plain letters." end   -- checked before tidying: a line break never becomes a space
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if name == "" then return nil, "Type a spell's name first." end
  if #name > R.NAME_LIMIT then return nil, "That name is too long for a spell." end
  if name:find("[,;/|%[%]]") then return nil, "A spell name cannot have , ; / | [ or ] in it." end
  return name
end

-------------------------------------------------------------------------------
-- Reading the game (every call guarded; a missing API is an empty answer, not an error)
-------------------------------------------------------------------------------
local function ask(path, ...)
  local ok, a, b, c, d = C.Call(path, path, ...)
  if not ok then return nil end
  return C.Readable(a), C.Readable(b), C.Readable(c), C.Readable(d)
end

function R.SpellIcon(name) return Panoply.Icons:Spell(name) end   -- 0.9.7 hotfix: the one shared lookup (Core/CompatModules.lua)

-- WoW Forever's spellbook (C_SpellBook): skill lines, then the items of each.
local function bookForever(add)
  if type(C.G("C_SpellBook.GetNumSpellBookSkillLines")) ~= "function" or type(C.G("C_SpellBook.GetSpellBookSkillLineInfo")) ~= "function"
    or type(C.G("C_SpellBook.GetSpellBookItemInfo")) ~= "function" then return false end
  local bank = C.G("Enum.SpellBookSpellBank.Player") or 0
  local spellType = C.G("Enum.SpellBookItemType.Spell") or 1
  local lines = tonumber(ask("C_SpellBook.GetNumSpellBookSkillLines")) or 0
  for l = 1, lines do
    local line = ask("C_SpellBook.GetSpellBookSkillLineInfo", l)
    if type(line) == "table" and not line.shouldHide and not line.offSpecID then
      local first, count = tonumber(line.itemIndexOffset) or 0, tonumber(line.numSpellBookItems) or 0
      for slot = first + 1, first + count do
        local it = ask("C_SpellBook.GetSpellBookItemInfo", slot, bank)
        if type(it) == "table" and it.itemType == spellType and not it.isPassive and not it.isOffSpec then
          add(C.Readable(it.name), C.Readable(it.iconID), C.Readable(it.spellID))
        end
      end
    end
  end
  return true
end

-- Classic Era's spellbook: tabs, then slots.
local function bookEra(add)
  if type(C.G("GetNumSpellTabs")) ~= "function" or type(C.G("GetSpellTabInfo")) ~= "function"
    or type(C.G("GetSpellBookItemName")) ~= "function" then return false end
  local tabs = tonumber(ask("GetNumSpellTabs")) or 0
  for t = 1, tabs do
    local _, _, offset, count = ask("GetSpellTabInfo", t)
    offset, count = tonumber(offset) or 0, tonumber(count) or 0
    for slot = offset + 1, offset + count do
      local kind, sid = ask("GetSpellBookItemInfo", slot, "spell")
      local passive = ask("IsPassiveSpell", slot, "spell")
      if (kind == nil or kind == "SPELL") and not passive then
        local name = ask("GetSpellBookItemName", slot, "spell")
        local icon = ask("GetSpellBookItemTexture", slot, "spell")
        if not icon then icon = ask("GetSpellTexture", slot, "spell") end
        add(name, icon, type(sid) == "number" and sid or nil)
      end
    end
  end
  return true
end

-- The spells the character can cast, in spellbook order, one row per name: { { name, icon } }.
function R:KnownSpells()
  if self.known then return self.known end
  local out, at = {}, {}
  local function add(name, icon, id)
    name = R.CleanName(name)
    if not name then return end
    if at[name] then
      if icon then out[at[name]].icon = icon end   -- a later rank of the same spell: one row, the newest icon
      if id then out[at[name]].id = id end         -- and the newest rank's spell id
    else
      out[#out + 1] = { name = name, icon = icon, id = id }
      at[name] = #out
    end
  end
  local read = bookForever(add)
  if #out == 0 then read = bookEra(add) or read end
  self.bookRead = read and true or false
  self.known = out
  return out
end

Panoply:On("SPELLS_CHANGED", function() R.known = nil end)

-------------------------------------------------------------------------------
-- A key a player bound to the removed button
-------------------------------------------------------------------------------
-- A plain button with the old frame's name, so a saved key press has something harmless to land on. No secure template, no
-- attributes, no macro text: the click only writes one line in chat, once a session.
do
  local b = CreateFrame("Button", R.BUTTON, _G.UIParent)
  b:SetSize(1, 1)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetScript("OnClick", function()
    if R.toldRemoved then return end
    R.toldRemoved = true
    Panoply:Print(R.REMOVED)
  end)
  b:Hide()
  R.stub = b
end
