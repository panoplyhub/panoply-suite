-- Panoply Suite: the voice of the bundled Polestar engine (WoW Forever only). Own code; it calls Polestar, it does not copy it.
--
-- Nov 14 2026 (0.9.4 step 21): "Polestar branding leaks to the player ... Everything the player sees must be Panoply-themed: no
-- "Polestar" prefix, no Polestar option paths. Polestar's files must stay UNEDITED, so do it from Panoply's side."
-- Polestar's files are bundled unedited except what Polestar/PANOPLY-CHANGES.md lists (tools/update_polestar_engine.py checks every byte). This file runs after them (the TOC lists
-- Polestar as an optional dependency, so it loads first) and changes what Polestar says AT RUNTIME, in Polestar's own tables:
--   * Polestar.Print (its one chat print function, every "Polestar: ..." line) prints with Panoply Suite's own chat prefix, with the
--     brand word reworded and no pointer to a Polestar-only setting or command (such a line is dropped);
--   * Polestar.L (its locale table: every text it shows, in all nine languages) is rewritten at key level: the texts that need a true
--     Panoply sentence are keyed below (V.KEYS), every other text that holds the brand word is reworded, and a text added later (a
--     language folder that loads late) is reworded as it arrives;
--   * the party quest-progress announcements ("{rt1} Polestar: [Quest] 5/5") are OFF unless the player turned on Panoply Suite's own
--     setting "Tell my party about my quest progress" (PanoplySuiteDB.partyQuestChat, applied at every login through the adapter's
--     Polestar.Set, as its own options window would); when on, the line sent to the party says "Panoply";
--   * 0.9.7: the hidden party sync (party.share, party.show) follows Panoply Suite's switch PanoplySuiteDB.partyShare, and what would
--     reach beyond the party is held off (Engine/PolestarParty.lua, applied with the line above);
--   * tooltips (Polestar.Widgets.Tooltip, Polestar.Hooks.AddLine), the key binding names, the chat filter's icon, the add-on
--     compartment entry, the entry in the game's Settings list and the slash commands answer as Panoply.
-- Every wrapped entry point is looked up first; a Polestar release without one is skipped without an error and V:Report() lists it
-- (tests/polevoice_tests.lua is the drift guard). Nothing here is used on Classic, where Polestar is not loaded.
-- Credits stay in About (UI/Help.lua), NOTICE.md and Licenses/: those are not touched.
local ADDON, Panoply = ...
local V = {}
Panoply.PolestarVoice = V

local DROP = "\1"          -- a text that is dropped rather than shown (see V.KEYS); never visible: Print drops the whole line
V.DROP = DROP
V.BRAND = "Panoply Suite"  -- what the brand word becomes in running text
V.MARKER = "{rt1} Panoply: "   -- the line a party member reads before a quest line
V.SYNC_POPUP = "POLESTAR_PARTY_SYNC"   -- 0.9.7: the name of Polestar's own pop-up for a sync request (Engine/PolestarParty.lua watches for it)

-------------------------------------------------------------------------------
-- Rewording
-------------------------------------------------------------------------------
local function hasBrand(s) return s:find("[Pp][Oo][Ll][Ee][Ss][Tt][Aa][Rr]") ~= nil end
V.HasBrand = function(s) return type(s) == "string" and hasBrand(s) end

-- What Polestar's own texts say that has no Panoply twin: its settings pages, its slash commands, its folders and its other
-- products. A line that holds one of these AND names the brand is not said (a pointer to a thing Panoply Suite does not have is not
-- a true Panoply sentence). A settings path is "A > B > C" in every language, so it is found by its arrows, not by its words.
local FOREIGN = { "/polestar", "/pole ", "/psrec", "%(Options,", "Options,%s*Integrations", "Polestar_", "Polestar Client", "CurseForge",
  "Discord", "GitHub", "AddOns list", "Community guides", "Shortest Path Forever", "Polestar's settings", "Polestar settings", "Polestar's options",
  "Polestar options", "Polestar package", "Polestar zip", "Polestar folder", "Polestar's Gamepad", "Polestar's source" }
local PATH = "[^%s>]%s>%s[^%s>]"
local function anyArrow(s) return s:find(PATH) ~= nil end
-- Nov 14 2026 (17-22 review, backlog 7): an arrow between two words is NOT always a settings path: an engine line such as "Stormwind > Ironforge"
-- or "Level 12 > 10" is harmless and is said. A settings path of Polestar's starts with its page word "Options" ("Options > Discovery >
-- Dungeons"), in the player's language as Polestar's own locale table says it (L["Options"]: Optionen, Opciones, 설정, ...). So:
--   * a text that names the brand: any arrow is a pointer to a Polestar-only thing (as before);
--   * a text that does not: only an arrow that follows the word for Options.
local function optionWords()
  local words = { "Options" }
  local p = rawget(_G, "Polestar")
  local L = type(p) == "table" and p.L or nil
  if type(L) == "table" then
    local ok, w = pcall(function() return L["Options"] end)
    if ok and type(w) == "string" and w ~= "" and w ~= "Options" then words[2] = w end
  end
  return words
end
local function optionPath(s)
  if not anyArrow(s) then return false end
  local l = s:lower()
  for _, w in ipairs(optionWords()) do
    if l:find(w:lower() .. " > ", 1, true) then return true end
  end
  return false
end
local function hasPath(s)
  if hasBrand(s) then return anyArrow(s) end
  return optionPath(s)
end
V.HasPath = function(s) return type(s) == "string" and hasPath(s) end
-- the pointer in brackets is cut out: "(Options > Questing > Quests > Group to change this)"
local function pathFree(s)
  local branded = hasBrand(s)
  return (s:gsub("%s*(%b())", function(par)
    if optionPath(par) or (branded and anyArrow(par)) then return "" end
  end))
end
local function foreign(s)
  if hasPath(s) then return true end
  local l = s:lower()
  for _, p in ipairs(FOREIGN) do if l:find(p:lower()) then return true end end
  return false
end

-- Generic rewording of any text: option paths out, the slash command to ours, the brand word to Panoply Suite.
function V.Text(s)
  if type(s) ~= "string" then return s end
  if not hasBrand(s) and not hasPath(s) then return s end
  s = pathFree(s)
  s = s:gsub("[^%s>]+%s>%s[^%.%)\"]*", "Panoply Suite's settings")
  s = s:gsub("/[Pp]olestar", "/panoply")
  s = s:gsub("[Pp][Oo][Ll][Ee][Ss][Tt][Aa][Rr]'s", V.BRAND .. "'s")
  s = s:gsub("[Pp][Oo][Ll][Ee][Ss][Tt][Aa][Rr]", V.BRAND)
  return s
end

-- A text of Polestar's locale table (a key, or a translation of it) as the table holds it from now on: reworded, or marked as not to be
-- said (V.DROP) when it points at a Polestar-only setting, command or folder. Only a text that names the brand is touched.
local function localeText(text, key)
  if not hasBrand(text) then
    -- a translation that has lost the brand word of its English key is still dropped when the English text points at a Polestar-only thing
    if type(key) == "string" and hasBrand(key) and foreign(pathFree(key)) then return DROP .. text end
    return text
  end
  local c = pathFree(text)
  -- the pointers are found in the English key too: a translation says "settings" and "AddOns list" in its own words
  if foreign(c) or (type(key) == "string" and hasBrand(key) and foreign(pathFree(key))) then return DROP .. V.Text(c) end
  return V.Text(c)
end
V.LocaleText = localeText

-- Guide text that Polestar's guides carry ("Follow the Polestar guide ...", "Polestar cannot read your rank yet"): said as the guide
-- speaks, never naming it. A sentence that sends the player to one of Polestar's other guides is left out: Panoply Suite's windows
-- do not open them.
function V.GuideText(s)
  if type(s) ~= "string" or not hasBrand(s) then return s end
  s = s:gsub("%s*Follow the Polestar[^%.]*%.", "")
  local function cap(str, pos, word)
    if pos == 1 or str:sub(1, pos - 1):find("[%.!?:]%s*$") then return word:sub(1, 1):upper() .. word:sub(2) end
    return word
  end
  local out, i = {}, 1
  while true do
    local a, b, poss = s:find("[Pp][Oo][Ll][Ee][Ss][Tt][Aa][Rr]('?s?)", i)
    if not a then out[#out + 1] = s:sub(i) break end
    out[#out + 1] = s:sub(i, a - 1)
    out[#out + 1] = cap(s, a, poss == "'s" and "the guide's" or "the guide")
    i = b + 1
  end
  s = table.concat(out)
  s = s:gsub("^%s+", "")
  return s
end

-------------------------------------------------------------------------------
-- Key-level texts: Polestar's own keys (the English text is the key; every language folder fills the same keys)
-------------------------------------------------------------------------------
-- value: a string (a true Panoply sentence), a function returning one (read when the text is asked for), or DROP (said to nobody).
local function partyChatPath()
  local path = Panoply.SettingsPath and Panoply:SettingsPath("partyQuestChat") or "Guide > Party chat"
  return path
end
V.KEYS = {
  -- the party quest-progress announcements (Quests/PartyChat.lua): the line the party reads, and the one-time local confirmation
  ["{rt1} Polestar: "] = V.MARKER,
  ["Polestar told your party about your quest progress in chat (Options > Questing > Quests > Group to change this)."] = function()
    return "Told your party about your quest progress in chat. Change it in Panoply Suite's settings: " .. partyChatPath() .. "."
  end,
  -- other players' Polestar versions and packs (Quests/Party.lua): about their add-on, not ours
  -- (0.9.7, partner leveling: Engine/PolestarParty.lua says the two that matter in Panoply's own words, a party member on another
  -- version and nobody heard yet; Polestar's own lines for them stay unsaid, so neither is said twice)
  ["%s is on Polestar %s: your guides can differ. A newer version is out."] = DROP,
  ["%s is on Polestar %s: your guides can differ."] = DROP,
  ["%s has a newer %s guide pack (%s; yours is %s)."] = DROP,
  ["No one else in your party has been heard running Polestar yet."] = DROP,
  ["Party sync is on: you and your party see each other's quest progress. Turn it off in Options."] =
    "Party sync is on: you and your party see each other's quest progress.",
  -- the arrow and its hiding (Nav/Nav.lua): Polestar-only buttons and settings
  ["Shortest Path Forever is guiding a journey of its own. Polestar's arrow comes back when it ends."] =
    "Shortest Path Forever is guiding a journey of its own.",
  ["Shortest Path Forever is guiding. Turn off \"Hand guiding to Shortest Path Forever\" (Options, Integrations) to use Polestar's arrow."] = DROP,
  ["Polestar is hidden, the arrow with it: \"Keep the arrow when hidden\" in the minimap button's menu keeps it."] = DROP,
  ["The guide is hidden and \"Hide the arrow with the guide\" is on, so the arrow is hidden too: /polestar show brings them back."] = DROP,
  -- the one popup Polestar puts up by itself (UI/Packs.lua, at login): its guide files unticked in the AddOns list
  ["Polestar Guides is turned off in the AddOns list, so Polestar has no guides to show. Turn it on for all your characters and reload?"] =
    "The guide files are turned off in the AddOns list, so the guide has nothing to show. Turn them on for all your characters and reload?",
  -- a broken install (Core/Data.lua)
  ["Polestar no longer uses the old folders Polestar_Guides_<language> and Polestar_Names_<language> (%s): Polestar_<language> holds both now. Close the game and delete them from Interface/AddOns."] = DROP,
  ["Your install is mixed or incomplete (%s). Close the game, delete every Polestar folder in Interface/AddOns and install Polestar again: with the Polestar Client, the CurseForge app, or the latest zip from GitHub Releases (not \"Source code\")."] =
    -- (no "%s": what Polestar fills in there is the list of its own folder names, which are not said)
    "The guide files are mixed or incomplete. Close the game and install Panoply Suite again.",
}

-------------------------------------------------------------------------------
-- Wrapping, with a record of what was and was not found (the drift guard reads it)
-------------------------------------------------------------------------------
V.wrapped, V.skipped = {}, {}
local mine = setmetatable({}, { __mode = "k" })      -- the functions this file made: never wrapped twice

-- every entry point this file changes, by name: tests/polevoice_tests.lua fails when one of these is not wrapped with the bundled Polestar
V.EXPECT = { "Print", "L", "Widgets.Tooltip", "Hooks.AddLine", "PartyChat.MarkerToken", "PartyChat.ICON", "SlashCmdList.POLESTAR",
  "SlashCmdList.POLESTARREC", "Polestar_OnAddonCompartmentClick", "Polestar_OnAddonCompartmentEnter", "Polestar_OnAddonCompartmentLeave",
  "BINDING_NAME_POLESTAR_HIDE", "BINDING_NAME_POLESTAR_OPTIONS", "UI.settingsCategory" }   -- 0.9.9: no BINDING_TAG_POLESTAR (Polestar 0.4.2 removed it)

local function note(name, ok, why)
  if ok then V.wrapped[name], V.skipped[name] = true, nil else V.wrapped[name], V.skipped[name] = nil, why or "missing" end
end

local function P() return rawget(_G, "Polestar") end
V.P = P

-- A function of a Polestar table replaced by wrap(original). Missing, or already ours: noted and left.
local function wrapFn(name, tbl, key, wrap)
  local orig = type(tbl) == "table" and tbl[key] or nil
  if type(orig) ~= "function" then note(name, false, "missing") return false end
  if mine[orig] then note(name, true) return true end
  local f = wrap(orig)
  mine[f] = true
  tbl[key] = f
  note(name, true)
  return true
end

-------------------------------------------------------------------------------
-- Chat: Polestar.Print
-------------------------------------------------------------------------------
-- Print's text comes in as Polestar built it ("%s" already filled in). A text that carries the DROP mark (a key above) or a pointer to
-- something Panoply Suite has not got is not said; every other is said once, in Panoply Suite's prefix, reworded.
function V.Say(...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  local body = table.concat(parts, " ")
  if body:find(DROP, 1, true) then V.dropped = (V.dropped or 0) + 1 return false end
  -- (a sentence that says Panoply Suite is Panoply's own, with its own path in it: "Guide > Party chat")
  if hasBrand(body) or (hasPath(body) and not body:find("Panoply", 1, true)) then
    -- "(Options > Questing > Quests > Group to change this)" is cut out of the sentence; any other path or command is a reason to say nothing
    body = pathFree(body)
    if foreign(body) then V.dropped = (V.dropped or 0) + 1 return false end
    body = V.Text(body)
  end
  V.said = (V.said or 0) + 1
  Panoply:Print(body)
  return true
end

-------------------------------------------------------------------------------
-- Locale: Polestar.L
-------------------------------------------------------------------------------
-- The text for a key: Panoply's own where V.KEYS has one, else Polestar's (in the player's language) reworded.
local function keyText(key)
  local k = V.KEYS[key]
  if type(k) == "function" then return k() end
  if k ~= nil then return k end
  return nil
end

-- What becomes of one of Polestar's English texts (the key): class, and the text a player of an English client would read in chat (the report
-- logs/094/step-21-strings.md is written from this). Classes: keyed (a Panoply sentence), dropped (keyed to say nothing), dropped (it points at a
-- Polestar-only thing), reworded, reworded + settings path cut, path cut (no brand), unchanged.
function V.Describe(key)
  local k = V.KEYS[key]
  if k == DROP then return "dropped (keyed)", "" end
  if k ~= nil then return "keyed", type(k) == "function" and k() or k end
  local branded, pathy = hasBrand(key), hasPath(key)
  if not branded and not pathy then return "unchanged", key end
  local c = pathFree(key)
  if foreign(c) then return "dropped (points at a Polestar-only thing)", "" end
  if branded then return (c ~= key) and "reworded, settings path cut" or "reworded", V.Text(c) end
  return "settings path cut", c
end

function V.PatchLocale(L)
  local mt = getmetatable(L)
  if type(mt) ~= "table" or type(mt.__index) ~= "function" then return false, "no locale metatable" end
  if mt.psvoice then return true end
  mt.psvoice = true
  local list = {}
  for k, v in pairs(L) do list[#list + 1] = k end
  local n = 0
  for _, k in ipairs(list) do
    local v = rawget(L, k)
    if type(k) == "string" and V.KEYS[k] ~= nil then
      rawset(L, k, nil)                    -- the key is answered by __index from now on (a function is read when asked)
      n = n + 1
    elseif type(v) == "string" and (hasBrand(v) or (type(k) == "string" and hasBrand(k))) then
      rawset(L, k, localeText(v, k))
      n = n + 1
    end
  end
  V.reworded = (V.reworded or 0) + n
  -- the English text is the key: a key that is not in the table answers with itself, reworded when it holds the brand word
  mt.__index = function(_, key)
    if type(key) ~= "string" then return key end
    local k = V.KEYS[key]
    if k ~= nil then
      if type(k) == "function" then return k() end
      return k
    end
    if hasBrand(key) then return localeText(key) end
    return key
  end
  -- a language folder that fills the table later (Polestar's Core/Locale.lua says it may): its texts arrive reworded
  mt.__newindex = function(t, key, value)
    if type(key) == "string" and V.KEYS[key] ~= nil then return end
    if type(value) == "string" and (hasBrand(value) or (type(key) == "string" and hasBrand(key))) then value = localeText(value, key) end
    rawset(t, key, value)
  end
  return true
end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------
local function lineHasBrand(l)
  if type(l) == "string" then return hasBrand(l) end
  if type(l) == "table" then
    for _, x in ipairs({ l.left, l.right, l[1] }) do if type(x) == "string" and hasBrand(x) then return true end end
  end
  return false
end

local function wrapTooltip(orig)
  return function(owner, anchor, title, lines)
    local dirty = type(title) == "string" and hasBrand(title)
    if not dirty and type(lines) == "table" then
      for i = 1, #lines do if lineHasBrand(lines[i]) then dirty = true break end end
    end
    if not dirty then return orig(owner, anchor, title, lines) end
    local out = {}
    for i = 1, type(lines) == "table" and #lines or 0 do
      local l = lines[i]
      if type(l) == "string" then out[i] = V.Text(l)
      elseif type(l) == "table" then
        local c = {}
        for k, v in pairs(l) do c[k] = type(v) == "string" and V.Text(v) or v end
        out[i] = c
      else out[i] = l end
    end
    return orig(owner, anchor, V.Text(title), type(lines) == "table" and out or lines)
  end
end

-------------------------------------------------------------------------------
-- The add-on compartment, the game's Settings list, key bindings
-------------------------------------------------------------------------------
local function compartment(p)
  -- the compartment's row is made from Polestar's TOC (Title: Polestar); where the client lets an add-on take a row away, Polestar's goes
  local f = rawget(_G, "AddonCompartmentFrame")
  local removed = 0
  if type(f) == "table" and type(f.UnregisterAddon) == "function" and type(f.registeredAddons) == "table" then
    local list = {}
    for _, e in ipairs(f.registeredAddons) do if type(e) == "table" and type(e.text) == "string" and e.text == "Polestar" then list[#list + 1] = e end end
    for _, e in ipairs(list) do if pcall(f.UnregisterAddon, f, e) then removed = removed + 1 end end
  end
  V.compartmentRemoved = removed
end

local function settingsCategory(p)
  local UI = p.UI
  local cat = type(UI) == "table" and UI.settingsCategory or nil
  if type(cat) ~= "table" then return false end
  if type(cat.name) == "string" then cat.name = V.BRAND .. " guide engine" end
  -- the canvas Polestar drew (its wordmark, "Open Polestar settings"), when the client lets an add-on reach it
  local ok, layout = pcall(function() return cat.GetLayout and cat:GetLayout() or nil end)
  local frame = ok and type(layout) == "table" and layout.frame or nil
  if type(frame) == "table" and frame.GetRegions then
    for _, r in ipairs({ frame:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText and r.SetText then r:SetText(V.Text(r:GetText())) end
      if r.GetObjectType and r:GetObjectType() == "Texture" and r.Hide then r:Hide() end
    end
    if frame.GetChildren then
      for _, c in ipairs({ frame:GetChildren() }) do
        if c.GetText and c.SetText then c:SetText(V.Text(c:GetText())) end
      end
    end
  end
  return true
end

local BINDINGS = { "BINDING_NAME_POLESTAR_TOGGLE", "BINDING_NAME_POLESTAR_HIDE", "BINDING_NAME_POLESTAR_NEXT",
  "BINDING_NAME_POLESTAR_PREV", "BINDING_NAME_POLESTAR_FOCUS", "BINDING_NAME_POLESTAR_MENU", "BINDING_NAME_POLESTAR_OPTIONS",
  "BINDING_NAME_POLESTAR_REPORT", "BINDING_NAME_POLESTAR_NEXT_WAYPOINT", "BINDING_NAME_POLESTAR_PREV_WAYPOINT", "BINDING_NAME_POLESTAR_REOPEN_TAB",
  "BINDING_NAME_POLESTAR_RECORDER_TRAIL", "BINDING_NAME_POLESTAR_RECORDER_WINDOW" }
local function bindings()
  for _, g in ipairs(BINDINGS) do
    local v = rawget(_G, g)
    if type(v) == "string" and hasBrand(v) then _G[g] = V.Text(v) end
  end
end

-------------------------------------------------------------------------------
-- Install (at load, and again at login: it does each part once per Polestar)
-------------------------------------------------------------------------------
function V:Install()
  local p = P()
  if type(p) ~= "table" then return false, "Polestar is not loaded" end
  -- chat
  wrapFn("Print", p, "Print", function() return function(...) return V.Say(...) end end)
  -- locale
  local ok, why = false, "no locale"
  if type(p.L) == "table" then ok, why = V.PatchLocale(p.L) end
  note("L", ok, why)
  -- tooltips
  wrapFn("Widgets.Tooltip", p.Widgets, "Tooltip", wrapTooltip)
  wrapFn("Hooks.AddLine", p.Hooks, "AddLine", function(orig)
    return function(tooltip, left, right, ...)
      if type(left) == "string" and hasBrand(left) then left = V.Text(left) end
      if type(right) == "string" and hasBrand(right) then right = V.Text(right) end
      return orig(tooltip, left, right, ...)
    end
  end)
  -- the chat filter's star: the line carries "Panoply", and the picture in its place is ours
  local PC = p.PartyChat
  wrapFn("PartyChat.MarkerToken", PC, "MarkerToken", function(orig)
    return function(msg)
      local n = orig(msg)
      if n then return n end
      if type(msg) ~= "string" then return nil end
      local C = p.Compat
      if C and C.IsSecret and C.IsSecret(msg) then return nil end
      for _, t in ipairs({ "{rt1}", "{\208\183\208\178\208\181\208\183\208\180\208\176}" }) do
        if msg:sub(1, #t) == t and msg:find("^ Panoply ?: ", #t + 1) then return #t end
      end
      return nil
    end
  end)
  if type(PC) == "table" and type(PC.ICON) == "string" then
    PC.ICON = "|TInterface\\AddOns\\" .. ADDON .. "\\Media\\Shield:0|t"
    note("PartyChat.ICON", true)
  else note("PartyChat.ICON", false, "missing") end
  -- slash commands: /polestar and /pole are Panoply Suite's own command now; the recorder's /psrec says it is not part of it
  local S = rawget(_G, "SlashCmdList")
  if type(S) == "table" and type(S.POLESTAR) == "function" then
    if not mine[S.POLESTAR] then
      local f = function(msg) Panoply:Slash(msg or "") end
      mine[f] = true
      S.POLESTAR = f
    end
    note("SlashCmdList.POLESTAR", true)
  else note("SlashCmdList.POLESTAR", false, "missing") end
  if type(S) == "table" and type(S.POLESTARREC) == "function" then
    if not mine[S.POLESTARREC] then
      local f = function() Panoply:Print("The recorder is not part of Panoply Suite. Type /panoply help to see what is.") end
      mine[f] = true
      S.POLESTARREC = f
    end
    note("SlashCmdList.POLESTARREC", true)
  else note("SlashCmdList.POLESTARREC", false, "missing") end
  -- the add-on compartment: its row goes where the client allows it; a click or a hover on it is ours
  for _, name in ipairs({ "Polestar_OnAddonCompartmentClick", "Polestar_OnAddonCompartmentEnter", "Polestar_OnAddonCompartmentLeave" }) do
    local orig = rawget(_G, name)
    if type(orig) == "function" then
      if not mine[orig] then
        local f
        if name:find("Click$") then f = function() if Panoply.Menu and Panoply.Menu.Toggle then Panoply.Menu:Toggle() end end
        elseif name:find("Enter$") then
          f = function(_, row)
            local tip = rawget(_G, "GameTooltip")
            if tip and row and tip.SetOwner then
              tip:SetOwner(row, "ANCHOR_LEFT")
              tip:SetText(V.BRAND, 1, 1, 1)
              tip:AddLine("Click: open the menu", 0.7, 0.7, 0.7)
              tip:Show()
            end
          end
        else f = function() local tip = rawget(_G, "GameTooltip") if tip and tip.Hide then tip:Hide() end end end
        mine[f] = true
        _G[name] = f
      end
      note(name, true)
    else note(name, false, "missing") end
  end
  pcall(compartment, p)
  -- the entry in the game's Settings list
  local sok = pcall(settingsCategory, p)
  note("UI.settingsCategory", sok and type(p.UI) == "table" and type(p.UI.settingsCategory) == "table", "missing")
  -- key bindings: the labels Polestar set at load
  bindings()
  for _, g in ipairs({ "BINDING_NAME_POLESTAR_HIDE", "BINDING_NAME_POLESTAR_OPTIONS" }) do
    note(g, type(rawget(_G, g)) == "string", "missing")
  end
  V.installedFor = p
  return true
end

-- What was changed and what was not found (a Polestar release without one of the entry points): { wrapped = { names }, skipped = { name = why } }
function V:Report()
  local w, s = {}, {}
  for name in pairs(self.wrapped) do w[#w + 1] = name end
  table.sort(w)
  for name, why in pairs(self.skipped) do s[name] = why end
  return { wrapped = w, skipped = s }
end

-------------------------------------------------------------------------------
-- The party quest-progress announcements: off unless the player turns them on
-------------------------------------------------------------------------------
-- Polestar's settings party.chat (objectives and ready quests) and party.chatLoot (a looted item that starts a quest) both come on in
-- Polestar. Panoply Suite's setting is the master: applied at every login and when it changes, through the adapter's Polestar.Set
-- (the value each had before is kept, as for the adapter's other settings). Polestar's saved keys are not renamed or removed.
function V:ApplyParty()
  local PE = Panoply.PolestarEngine
  -- Nov 14 2026 (17-22 review, backlog 6): needs Polestar's settings (Get / Set), not the adapter's start: a Polestar release that lacks
  -- another function the adapter wants must still not tell the party on its own
  if not (PE and PE.CanSet and PE:CanSet() and P()) then return false end
  local want = Panoply.db.partyQuestChat == true
  PE:Manage("party.chat", want)
  PE:Manage("party.chatLoot", want)
  -- 0.9.7: what Polestar does for the party that is not chat (hidden add-on messages: party.share, party.show) follows Panoply
  -- Suite's own switch, and its senders that reach beyond the party (update.probe, nav.shareTransit, the guild hello) are held off:
  -- Engine/PolestarParty.lua
  local PP = Panoply.PolestarParty
  if PP and PP.Apply then PP:Apply() end
  return true
end

Panoply:Listen("OPTION_CHANGED", function(key) if key == "partyQuestChat" then V:ApplyParty() end end)

-- a profile must never switch what is told to other players on or off
if Panoply.Profiles and type(Panoply.Profiles.NOT_COVERED) == "table" then
  Panoply.Profiles.NOT_COVERED.partyQuestChat = "what you tell other players is the account's own choice; a profile must never switch it on"
end

-- 0.9.5: the bundled Polestar (Core/Bundle.lua) starts at Panoply Suite's ADDON_LOADED, after this file has loaded; what Install
-- changes (the Settings list entry above all) is there only then. A Polestar of the player's own was up before this file, as before.
local bundle = rawget(_G, "PanoplySuiteBundle")
if type(bundle) == "table" and bundle.OnStart then bundle.OnStart(function() V:Install() end) else V:Install() end
