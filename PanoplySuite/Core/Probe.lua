-- Panoply Suite 0.9.5, phase 4A: the probe. Nobody at Panoply can play the game, so the game is asked: /panoply probe runs every
-- check below on the character that types it and writes the answers into saved data; after a /reload the file can be read and turned
-- into docs/probes/<game>-api.md (tools/probe_report.lua). The later 0.9.5 pages are built on those answers.
--
-- What it asks (docs/specs/page-redesigns-v1.md section 0, and spec 03a for the next-ability display):
--   legacy.*       is Forever Legacy data readable: Legacy-named globals and C_ functions, achievements that award trait currency,
--                  the trait system behind the Legacy window (config, trees, node ranks), and which events fire (watched for the
--                  rest of the session after the command: spend a perk or finish a challenge, then /reload)
--   skills.*       the skill lines (professions with skill and cap, weapon skills, armour proficiencies), and whether the old global
--                  GetNumSkillLines is there
--   collect.*      toys, pets and mounts: the four Legacy rewards found BY NAME (no id is written into the add-on unverified)
--   explore.*      map exploration, and the PvP rank
--   camp.*         how camp objects and Blueprints show up: spells in the spellbook, items in the bags
--   advisor.*      every input the next-ability display reads (target health, the character's power, auras, cooldowns, usable,
--                  procs, macro conditions), each recorded as readable or secret, out of combat when the command runs and IN combat
--                  the next time the character is in a fight (nothing is forced; until then the in-combat answer says "pending")
--   icons.*        the game's own textures the icon slots fall back to (UI/KitParts.lua): does this game have each file
--
-- Saved in PanoplySuiteProbeDB, a NEW saved variable for the account (nothing else is touched):
--   { v = 1, last = <client key>, clients = { [<flavor> <version> (<build>)] = { flavor, version, build, toc, ran, addon, runs,
--     character = { name, realm, class, level, faction }, results = { [check id] = { status, value, list, note, at } },
--     events = { [EVENT] = { n, first, last, args } } } } }
-- One record per client build: a new build gets a new record, and on the first login on a new build the advisor checks (only those:
-- they are cheap) run by themselves, with ONE line in chat when an input changed between readable and secret. Nothing is sent
-- anywhere; a value the game marks secret is written as the word "secret", never the value.
--
-- Reads only. Nothing here casts, targets, buys, spends or changes a setting of the game. Every game call goes through
-- Compat (C.G / pcall), so a function that is not in this game is recorded as "missing" and nothing breaks.
local ADDON, Panoply = ...
local C = Panoply.Compat
local G = C.G

local Probe = { VERSION = 1, checks = {}, byId = {}, MAX_LIST = 80, MAX_TEXT = 300 }
Panoply.Probe = Probe

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------
function Probe:DB(create)
  local db = _G.PanoplySuiteProbeDB
  if type(db) ~= "table" then
    if not create then return nil end
    db = {}
    _G.PanoplySuiteProbeDB = db
  end
  if type(db.clients) ~= "table" then db.clients = {} end
  db.v = Probe.VERSION
  return db
end

-- "forever 1.60.1 (70291)": one record per build of each game
function Probe:ClientKey()
  local version, build = C.BuildInfo()
  return ("%s %s (%s)"):format(C.Flavor(), tostring(version or "?"), tostring(build or "?"))
end

function Probe:Record(create)
  local db = self:DB(create)
  if not db then return nil end
  local key = self:ClientKey()
  local rec = db.clients[key]
  if type(rec) ~= "table" then
    if not create then return nil end
    local version, build, _, toc = C.BuildInfo()
    rec = { flavor = C.Flavor(), version = tostring(version or "?"), build = tostring(build or "?"), toc = tonumber(toc), results = {}, events = {}, runs = 0 }
    db.clients[key] = rec
  end
  if type(rec.results) ~= "table" then rec.results = {} end
  if type(rec.events) ~= "table" then rec.events = {} end
  db.last = key
  return rec, key
end

-- the record of the build of this game that was probed before this one (to say what changed)
function Probe:Previous()
  local db = self:DB(false)
  if not db then return nil end
  local now, flavor = self:ClientKey(), C.Flavor()
  local best
  for key, rec in pairs(db.clients) do
    if key ~= now and type(rec) == "table" and rec.flavor == flavor and (not best or (rec.ran or 0) > (best.ran or 0)) then best = rec end
  end
  return best
end

-------------------------------------------------------------------------------
-- Values: plain words only (a secret value is never stored, compared or printed)
-------------------------------------------------------------------------------
local function isSecret(v)
  local f = _G.issecretvalue
  if not f then return false end
  local ok, s = pcall(f, v)
  return (not ok) or s and true or false
end
Probe.IsSecret = isSecret

local function cut(s)
  s = tostring(s)
  if #s > Probe.MAX_TEXT then s = s:sub(1, Probe.MAX_TEXT - 3) .. "..." end
  return s
end

-- a value as text: "secret" for a secret, key=value pairs for a table (one level, sorted), the value itself otherwise
local function plain(v, depth)
  if isSecret(v) then return "secret" end
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return cut(v) end
  if t == "table" then
    if (depth or 0) >= 2 then return "{...}" end
    local keys = {}
    for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for i, k in ipairs(keys) do
      if i > 24 then out[#out + 1] = "..." break end
      out[#out + 1] = tostring(k) .. "=" .. plain(v[k], (depth or 0) + 1)
    end
    return cut("{" .. table.concat(out, ", ") .. "}")
  end
  return t
end
Probe.Plain = plain

-- call a game function by its dotted name: ok ("missing" when it is not in this game, "error" when it threw), then what it returned
local function ask(path, ...)
  local f = G(path)
  if type(f) ~= "function" then return "missing" end
  local res = { pcall(f, ...) }
  if not res[1] then return "error", tostring(res[2]) end
  return "ok", unpack(res, 2, table.maxn(res))
end
Probe.Ask = ask

-- readable or secret, for a value the game returned
local function state(...)
  local n = select("#", ...)
  if n == 0 then return "readable" end
  for i = 1, n do if isSecret((select(i, ...))) then return "secret" end end
  return "readable"
end

local function has(path) return type(G(path)) == "function" end

local function capList(list)
  if #list > Probe.MAX_LIST then
    local more = #list - Probe.MAX_LIST
    for i = #list, Probe.MAX_LIST + 1, -1 do list[i] = nil end
    list[#list + 1] = ("... and %d more"):format(more)
  end
  return list
end

-------------------------------------------------------------------------------
-- The checks. Each is { id, group, title, run = function(inCombat) -> status, value, list, note }.
--   status: "ok" | "missing" | "error" | "readable" | "secret" | "none" (asked, and there was nothing to find)
--   combat = true: asked again in combat, kept under id .. ":combat"
--   forever = true: a WoW Forever question (not asked on Classic Era)
--   auto = true: one of the cheap checks that run by themselves on a new build
-------------------------------------------------------------------------------
local function add(def)
  Probe.checks[#Probe.checks + 1] = def
  Probe.byId[def.id] = def
end

-- 1. Legacy ------------------------------------------------------------------
add({ id = "legacy.globals", group = "legacy", forever = true, title = "Globals and C_ functions with Legacy in their name",
  run = function()
    local found = {}
    for k, v in pairs(_G) do
      if type(k) == "string" then
        if k:lower():find("legacy", 1, true) then found[#found + 1] = k .. " (" .. type(v) .. ")" end
        if k:find("^C_") and type(v) == "table" then
          for name, fn in pairs(v) do
            if type(name) == "string" and name:lower():find("legacy", 1, true) then found[#found + 1] = k .. "." .. name .. " (" .. type(fn) .. ")" end
          end
        end
      end
    end
    table.sort(found)
    if #found == 0 then return "none", "nothing named Legacy" end
    return "ok", #found .. " found", capList(found)
  end })

add({ id = "legacy.window", group = "legacy", forever = true, title = "The game's own Legacy window",
  run = function()
    local out = {}
    -- the names in the 1.60.1 function list (tests/clientapi/api_forever.txt), and the frame they make once the window was opened
    for _, n in ipairs({ "ToggleLegacySystemUI", "ToggleLegacyChallenges", "ShowLegacyChallenge", "LegacySystemFrame_LoadUI", "LegacyChallengeViewedUtil",
      "LegacySystemFrame", "LegacyChallengesFrame" }) do
      local v = G(n)
      if v ~= nil then out[#out + 1] = n .. " (" .. type(v) .. ")" end
    end
    if #out == 0 then return "missing", "no Legacy window function or frame found" end
    local loaded = type(G("LegacySystemFrame")) == "table"
    return "ok", cut(table.concat(out, ", ")), out, (not loaded) and "The game's Legacy window was not opened yet this session: open it once and run the probe again to see its parts." or nil
  end })

-- the trait systems the game has configs for: the Legacy tree is one of them when it is built on traits
add({ id = "legacy.traits", group = "legacy", forever = true, title = "Trait systems with a config (the Legacy perk tree, if it is one)",
  run = function()
    if not has("C_Traits.GetConfigIDBySystemID") then return "missing", "C_Traits.GetConfigIDBySystemID" end
    local out, secret, nodeLines = {}, false, {}
    for systemID = 1, 60 do
      local st, configID = ask("C_Traits.GetConfigIDBySystemID", systemID)
      if st == "ok" and configID ~= nil then
        if isSecret(configID) then secret = true out[#out + 1] = ("system %d: config secret"):format(systemID)
        else
          local line = ("system %d: config %s"):format(systemID, tostring(configID))
          local st2, info = ask("C_Traits.GetConfigInfo", configID)
          if st2 == "ok" and type(info) == "table" and not isSecret(info) then
            line = line .. ", name " .. plain(info.name) .. ", type " .. plain(info.type)
            local trees = {}
            for _, treeID in ipairs(type(info.treeIDs) == "table" and info.treeIDs or {}) do
              local st3, nodes = ask("C_Traits.GetTreeNodes", treeID)
              local n = (st3 == "ok" and type(nodes) == "table") and #nodes or 0
              local ranked = 0
              if st3 == "ok" and type(nodes) == "table" then
                for i = 1, math.min(#nodes, 120) do
                  local st4, node = ask("C_Traits.GetNodeInfo", configID, nodes[i])
                  if st4 == "ok" and type(node) == "table" then
                    if isSecret(node.currentRank) then secret = true
                    elseif type(node.currentRank) == "number" and node.currentRank > 0 then ranked = ranked + 1 end
                    -- each node with its rank and what it is called (the perk plan needs the node ids): the first 40 of a tree
                    if i <= 40 then
                      local entryID = type(node.activeEntry) == "table" and node.activeEntry.entryID or (type(node.entryIDs) == "table" and node.entryIDs[1]) or nil
                      local name, spellID
                      if entryID ~= nil and not isSecret(entryID) then
                        local _, entry = ask("C_Traits.GetEntryInfo", configID, entryID)
                        local defID = type(entry) == "table" and entry.definitionID or nil
                        if defID ~= nil and not isSecret(defID) then
                          local _, def = ask("C_Traits.GetDefinitionInfo", defID)
                          if type(def) == "table" then
                            spellID = def.spellID
                            name = def.overrideName
                            if (name == nil or name == "") and spellID ~= nil and not isSecret(spellID) then
                              local _, sn = ask("C_Spell.GetSpellName", spellID)
                              name = sn
                            end
                          end
                        end
                      end
                      nodeLines[#nodeLines + 1] = cut(("tree %s node %s: rank %s/%s%s%s"):format(tostring(treeID), plain(nodes[i]), plain(node.currentRank), plain(node.maxRanks),
                        name and (", " .. plain(name)) or "", spellID and (" (spell " .. plain(spellID) .. ")") or ""))
                    end
                  end
                end
              end
              trees[#trees + 1] = ("tree %s: %d nodes, %d with ranks"):format(tostring(treeID), n, ranked)
            end
            if #trees > 0 then line = line .. "; " .. table.concat(trees, "; ") end
          elseif st2 == "ok" and isSecret(info) then secret = true line = line .. ", info secret" end
          out[#out + 1] = cut(line)
        end
      end
    end
    if #out == 0 then return "none", "no trait system has a config on this character" end
    local systems = #out
    for _, l in ipairs(nodeLines) do out[#out + 1] = l end
    return secret and "secret" or "readable", systems .. " trait systems", capList(out), secret and "some values are secret" or nil
  end })

-- achievements: the categories, and every achievement that awards trait currency (a Legacy challenge, if that is how points come)
add({ id = "legacy.achievements", group = "legacy", forever = true, title = "Achievements that award trait currency (Legacy challenges?)",
  run = function()
    if not has("GetCategoryList") then return "missing", "GetCategoryList" end
    if not has("GetAchievementInfo") then return "missing", "GetAchievementInfo" end
    local st, cats = ask("GetCategoryList")
    if st ~= "ok" or type(cats) ~= "table" then return "error", plain(cats) end
    local out, legacyCats, secret, seen = {}, {}, false, 0
    local currency = has("C_Traits.GetTraitCurrencyForAchievement")
    for _, cat in ipairs(cats) do
      local _, title = ask("GetCategoryInfo", cat)
      local named = type(title) == "string" and not isSecret(title) and title:lower():find("legacy", 1, true)
      if named then legacyCats[#legacyCats + 1] = ("category %s: %s"):format(tostring(cat), title) end
      local _, n = ask("GetCategoryNumAchievements", cat, true)
      n = (type(n) == "number" and not isSecret(n)) and n or 0
      for i = 1, math.min(n, 400) do
        local st2, id, name, _, completed = ask("GetAchievementInfo", cat, i)
        if st2 == "ok" and (isSecret(id) or id ~= nil) then
          seen = seen + 1
          if isSecret(id) or isSecret(completed) then secret = true
          else
            local cur
            if currency then
              local st3, c = ask("C_Traits.GetTraitCurrencyForAchievement", id)
              if st3 == "ok" and not isSecret(c) and c ~= nil and c ~= 0 then cur = c end
            end
            if cur or named then
              out[#out + 1] = ("%s %s: %s%s%s"):format(tostring(id), plain(name), completed and "done" or "not done",
                cur and (", trait currency " .. tostring(cur)) or "", named and ", in a Legacy category" or "")
            end
          end
        end
      end
    end
    local list = {}
    for _, l in ipairs(legacyCats) do list[#list + 1] = l end
    for _, l in ipairs(out) do list[#list + 1] = l end
    local value = ("%d categories, %d achievements looked at, %d Legacy categories, %d award trait currency or sit in one%s"):format(#cats, seen, #legacyCats, #out,
      currency and "" or " (C_Traits.GetTraitCurrencyForAchievement is not in this game)")
    if #list == 0 then return secret and "secret" or "none", value end
    return secret and "secret" or "readable", value, capList(list)
  end })

-- 2. Skill lines -------------------------------------------------------------
add({ id = "skills.lines", group = "skills", title = "Skill lines (professions, weapon skills, armour): C_SkillInfo, or the old global calls",
  run = function()
    local out, secret, how = {}, false, nil
    if has("C_SkillInfo.GetNumSkillLines") and has("C_SkillInfo.GetSkillLineInfo") then
      how = "C_SkillInfo"
      local st, n = ask("C_SkillInfo.GetNumSkillLines")
      if st ~= "ok" then return "error", plain(n) end
      if isSecret(n) then return "secret", "the number of skill lines is secret" end
      for i = 1, math.min(tonumber(n) or 0, 120) do
        local res = { ask("C_SkillInfo.GetSkillLineInfo", i) }
        if res[1] == "ok" then
          local parts = {}
          for j = 2, table.maxn(res) do
            if isSecret(res[j]) then secret = true end
            parts[#parts + 1] = plain(res[j])
          end
          out[#out + 1] = cut(i .. ": " .. table.concat(parts, " | "))
        end
      end
    elseif has("GetNumSkillLines") and has("GetSkillLineInfo") then
      how = "GetNumSkillLines"
      local st, n = ask("GetNumSkillLines")
      if st ~= "ok" then return "error", plain(n) end
      for i = 1, math.min(tonumber(n) or 0, 120) do
        local st2, name, isHeader, _, rank, _, _, maxRank = ask("GetSkillLineInfo", i)
        if st2 == "ok" then
          if isSecret(name) or isSecret(rank) then secret = true end
          out[#out + 1] = cut(("%d: %s%s"):format(i, plain(name), (not isSecret(isHeader) and isHeader) and " (header)" or (" " .. plain(rank) .. "/" .. plain(maxRank))))
        end
      end
    else
      return "missing", "neither C_SkillInfo.GetNumSkillLines nor GetNumSkillLines"
    end
    return secret and "secret" or "readable", ("%s: %d lines"):format(how, #out), capList(out)
  end })

add({ id = "skills.global", group = "skills", title = "Is the old global GetNumSkillLines there",
  run = function()
    local parts = {}
    for _, n in ipairs({ "GetNumSkillLines", "GetSkillLineInfo", "C_SkillInfo.GetNumSkillLines", "C_SkillInfo.GetSkillLineInfo", "C_SkillInfo.GetSkillLineInfoByID" }) do
      parts[#parts + 1] = n .. ": " .. (has(n) and "yes" or "no")
    end
    return "ok", table.concat(parts, ", "), parts
  end })

-- 0.9.5 phase 4A2: what the gear engine's class rules (Data/GearRules.lua) need checked on the live game. Every rule there is
-- the Classic rule; this records what THIS character really has, so a Forever difference shows in the report.
add({ id = "skills.gear", group = "skills", title = "Gear training: the weapon skills trained, armor and shield training, holding two weapons",
  run = function()
    local R, Gear = Panoply.GearRules, Panoply.Gear
    if not (R and Gear and Gear.Trained) then return "missing", "the gear engine is not loaded" end
    local out = {}
    local who = Panoply.Compat.PlayerInfo() or {}
    out[#out + 1] = "class: " .. tostring(who.classFile) .. ", level: " .. plain((Panoply.Compat.XP()))
    local okT, trained = pcall(Gear.Trained, Gear)
    if not okT then return "error", plain(trained) end
    if trained == nil then
      out[#out + 1] = "weapon skills: none listed (this game may have no trainable weapon skills, or hides the skill list)"
    else
      local names = {}
      for sub in pairs(trained) do names[#names + 1] = R.WEAPON_SKILL[sub] and R.WEAPON_SKILL[sub][1] or tostring(sub) end
      table.sort(names)
      out[#out + 1] = "weapon skills trained: " .. table.concat(names, ", ")
    end
    local known = G("IsPlayerSpell") or G("IsSpellKnown")
    local secret = false
    for _, key in ipairs({ 2, 3, 4, 6, "dualWield" }) do
      local id = R.TRAINING_SPELL[key]
      local label = type(key) == "number" and (R.ARMOR_NAME[key] or tostring(key)) or "Dual Wield"
      local rule = who.classFile and R.classes[who.classFile]
      local from
      if rule then
        if type(key) == "number" then from = rule.armor[key] else from = rule.dualWield end
      end
      local ruleText = from and ("our rule: from level " .. from) or "our rule: never"
      if type(known) ~= "function" then
        out[#out + 1] = ("%s (spell %d): cannot be asked (no IsPlayerSpell or IsSpellKnown); %s"):format(label, id, ruleText)
      else
        local okK, v = pcall(known, id)
        if isSecret(v) then secret = true end
        out[#out + 1] = ("%s (spell %d): %s; %s"):format(label, id, okK and plain(v) or "error", ruleText)
      end
    end
    return secret and "secret" or "readable", ("%d lines"):format(#out), capList(out)
  end })

-- 3. Collections: the four Legacy rewards, found by name ----------------------
Probe.REWARDS = { toy = "Replica Ironforge Air Rifle", pet = "Spectral Bear Cub", tabard = "Spectral Bear Tabard", mount = "Reins of the Spectral Bear" }

add({ id = "collect.toy", group = "collect", forever = true, title = "Toys: PlayerHasToy and the toy box; the Legacy toy by name",
  run = function()
    if not has("PlayerHasToy") then return "missing", "PlayerHasToy" end
    if not (has("C_ToyBox.GetNumToys") and has("C_ToyBox.GetToyFromIndex")) then return "ok", "PlayerHasToy is there; the toy box cannot be listed (no C_ToyBox.GetNumToys)" end
    local st, n = ask("C_ToyBox.GetNumToys")
    if st ~= "ok" or isSecret(n) then return isSecret(n) and "secret" or "error", plain(n) end
    local want = Probe.REWARDS.toy:lower()
    for i = 1, math.min(tonumber(n) or 0, 3000) do
      local _, itemID = ask("C_ToyBox.GetToyFromIndex", i)
      if type(itemID) == "number" and not isSecret(itemID) and itemID > 0 then
        local _, _, name = ask("C_ToyBox.GetToyInfo", itemID)
        if type(name) == "string" and not isSecret(name) and name:lower() == want then
          local _, owned = ask("PlayerHasToy", itemID)
          return state(owned), ("%s: item %d, owned %s"):format(name, itemID, plain(owned)), { ("item %d"):format(itemID) }
        end
      end
    end
    return "none", ("%d toys listed; '%s' is not among them"):format(tonumber(n) or 0, Probe.REWARDS.toy)
  end })

add({ id = "collect.pet", group = "collect", forever = true, title = "Pets: C_PetJournal; the Legacy pet by name",
  run = function()
    if not has("C_PetJournal.FindPetIDByName") then
      if has("C_PetJournal.GetNumPets") then return "ok", "C_PetJournal is there, FindPetIDByName is not" end
      return "missing", "C_PetJournal"
    end
    local st, speciesID, petGUID = ask("C_PetJournal.FindPetIDByName", Probe.REWARDS.pet)
    if st ~= "ok" then return "error", plain(speciesID) end
    if speciesID == nil then return "none", ("'%s' is not in the pet journal"):format(Probe.REWARDS.pet) end
    return state(speciesID, petGUID), ("%s: species %s, owned %s"):format(Probe.REWARDS.pet, plain(speciesID), petGUID ~= nil and "yes" or "no")
  end })

add({ id = "collect.mount", group = "collect", forever = true, title = "Mounts: C_MountJournal; the Legacy mount by name",
  run = function()
    if not (has("C_MountJournal.GetMountIDs") and has("C_MountJournal.GetMountInfoByID")) then return "missing", "C_MountJournal" end
    local st, ids = ask("C_MountJournal.GetMountIDs")
    if st ~= "ok" or type(ids) ~= "table" then return "error", plain(ids) end
    -- "Reins of the Spectral Bear" teaches the mount "Spectral Bear": either name counts
    local a, b = Probe.REWARDS.mount:lower(), Probe.REWARDS.mount:lower():gsub("^reins of the ", "")
    for _, id in ipairs(ids) do
      local res = { ask("C_MountJournal.GetMountInfoByID", id) }
      local name = res[2]
      if type(name) == "string" and not isSecret(name) and (name:lower() == a or name:lower() == b) then
        local collected = res[12]
        return state(collected), ("%s: mount %s, spell %s, collected %s"):format(name, plain(id), plain(res[3]), plain(collected))
      end
    end
    return "none", ("%d mounts listed; '%s' is not among them"):format(#ids, Probe.REWARDS.mount)
  end })

add({ id = "collect.tabard", group = "collect", forever = true, title = "The Legacy tabard: an item, found by name when the game has seen it",
  run = function()
    local path = has("C_Item.GetItemInfo") and "C_Item.GetItemInfo" or (has("GetItemInfo") and "GetItemInfo" or nil)
    if not path then return "missing", "GetItemInfo" end
    local st, name, link = ask(path, Probe.REWARDS.tabard)
    if st ~= "ok" then return "error", plain(name) end
    if name == nil then return "none", ("'%s' is not known to this session (an item is only found by name once the game has shown it)"):format(Probe.REWARDS.tabard) end
    local id = type(link) == "string" and not isSecret(link) and link:match("item:(%d+)") or nil
    return state(name, link), ("%s: item %s"):format(plain(name), tostring(id or "?"))
  end })

-- 4. Exploration and PvP -----------------------------------------------------
add({ id = "explore.map", group = "explore", title = "Map exploration: C_MapExplorationInfo on the map the character is on",
  run = function()
    if not has("C_MapExplorationInfo.GetExploredMapTextures") then return "missing", "C_MapExplorationInfo.GetExploredMapTextures" end
    local st, mapID = ask("C_Map.GetBestMapForUnit", "player")
    if st ~= "ok" or mapID == nil then return "none", "no map for the character right now (" .. plain(mapID) .. ")" end
    if isSecret(mapID) then return "secret", "the character's map is secret" end
    local st2, tex = ask("C_MapExplorationInfo.GetExploredMapTextures", mapID)
    if st2 ~= "ok" then return "error", plain(tex) end
    if isSecret(tex) then return "secret", "the explored areas are secret" end
    return "readable", ("map %s: %d explored areas"):format(tostring(mapID), type(tex) == "table" and #tex or 0)
  end })

add({ id = "explore.pvprank", group = "explore", title = "The PvP rank: UnitPVPRank, or what this game has instead",
  run = function()
    if has("UnitPVPRank") then
      local st, rank = ask("UnitPVPRank", "player")
      if st ~= "ok" then return "error", plain(rank) end
      local name
      if not isSecret(rank) and has("GetPVPRankInfo") then local _, n = ask("GetPVPRankInfo", rank) name = n end
      return state(rank), ("UnitPVPRank: %s%s"):format(plain(rank), name and (" (" .. plain(name) .. ")") or "")
    end
    -- not there: list what C_PvP and the globals offer with Rank or Honor in the name
    local out = {}
    local pvp = G("C_PvP")
    if type(pvp) == "table" then
      for name, fn in pairs(pvp) do
        if type(name) == "string" and type(fn) == "function" and (name:find("Rank", 1, true) or name:find("Honor", 1, true)) then out[#out + 1] = "C_PvP." .. name end
      end
    end
    for _, n in ipairs({ "GetPVPLifetimeStats", "GetPVPRankProgress", "GetHonorCurrency", "UnitHonorLevel", "UnitHonor" }) do if has(n) then out[#out + 1] = n end end
    table.sort(out)
    if #out == 0 then return "missing", "no UnitPVPRank, and nothing with Rank or Honor in C_PvP" end
    return "missing", "no UnitPVPRank; this game has: " .. cut(table.concat(out, ", ")), capList(out)
  end })

-- 5. Camp objects and Blueprints ---------------------------------------------
-- the names come from the spec's table (community data from around launch, unverified): they are only searched for, never relied on
Probe.CAMP_NAMES = { "Mana Well", "Fermenter", "Alchemy Laboratory", "Sharpening Wheel", "Anvil", "Master Forge", "Enchanted Lute", "Arcane Salvager",
  "Arcane Forge", "Reagent Bot", "Repair Bot", "Anarchist's Workbench", "Camp Tent", "Tanning Rack", "Sewing Machine", "Faction Banner", "Spinning Wheel",
  "Loom", "Basic Campfire Kit", "Cookie's Feast", "Iron Oven", "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory", "Incense Candle", "Greenhouse",
  "Seed Hybridizer", "Lodestone", "Rock Garden", "Molten Foundry", "Camp Chair", "Field Guide", "Trapper's Workbench", "Fish Bowl", "Fishing Rack", "Fishing Hut" }
local function campWord(name)
  if type(name) ~= "string" or isSecret(name) then return false end
  local low = name:lower()
  if low:find("blueprint", 1, true) or low:find("campfire", 1, true) or low:find("camp ", 1, true) then return true end
  for _, n in ipairs(Probe.CAMP_NAMES) do if low == n:lower() then return true end end
  return false
end

add({ id = "camp.spells", group = "camp", forever = true, title = "Camp objects and Blueprints as spells in the spellbook",
  run = function()
    local out, tabs, total = {}, {}, 0
    if has("C_SpellBook.GetNumSpellBookSkillLines") and has("C_SpellBook.GetSpellBookSkillLineInfo") and has("C_SpellBook.GetSpellBookItemName") then
      local bank = G("Enum.SpellBookSpellBank.Player") or 0
      local _, n = ask("C_SpellBook.GetNumSpellBookSkillLines")
      for t = 1, math.min(tonumber(n) or 0, 20) do
        local _, info = ask("C_SpellBook.GetSpellBookSkillLineInfo", t)
        if type(info) == "table" and not isSecret(info) then
          tabs[#tabs + 1] = plain(info.name)
          local first, count = tonumber(info.itemIndexOffset) or 0, tonumber(info.numSpellBookItems) or 0
          for i = first + 1, first + math.min(count, 400) do
            local _, name = ask("C_SpellBook.GetSpellBookItemName", i, bank)
            total = total + 1
            if campWord(name) then out[#out + 1] = ("%s (tab %s)"):format(name, plain(info.name)) end
          end
        end
      end
    elseif has("GetNumSpellTabs") and has("GetSpellTabInfo") and has("GetSpellBookItemName") then
      local _, n = ask("GetNumSpellTabs")
      for t = 1, math.min(tonumber(n) or 0, 20) do
        local _, tabName, _, offset, count = ask("GetSpellTabInfo", t)
        tabs[#tabs + 1] = plain(tabName)
        for i = (tonumber(offset) or 0) + 1, (tonumber(offset) or 0) + math.min(tonumber(count) or 0, 400) do
          local _, name = ask("GetSpellBookItemName", i, "spell")
          total = total + 1
          if campWord(name) then out[#out + 1] = ("%s (tab %s)"):format(name, plain(tabName)) end
        end
      end
    else
      return "missing", "no spellbook functions"
    end
    local value = ("%d spells in %d tabs (%s); %d look like camp objects or Blueprints"):format(total, #tabs, cut(table.concat(tabs, ", ")), #out)
    if #out == 0 then return "none", value end
    return "readable", value, capList(out)
  end })

add({ id = "camp.items", group = "camp", forever = true, title = "Camp objects and Blueprints as items in the bags",
  run = function()
    if not (has("C_Container.GetContainerNumSlots") and has("C_Container.GetContainerItemLink")) then return "missing", "C_Container" end
    local out, slots = {}, 0
    for bag = 0, 4 do
      local _, n = ask("C_Container.GetContainerNumSlots", bag)
      for slot = 1, math.min(tonumber(n) or 0, 40) do
        slots = slots + 1
        local _, link = ask("C_Container.GetContainerItemLink", bag, slot)
        if type(link) == "string" and not isSecret(link) then
          local name = link:match("%[(.-)%]")
          if campWord(name) then out[#out + 1] = ("%s (item %s)"):format(name, link:match("item:(%d+)") or "?") end
        end
      end
    end
    local value = ("%d bag slots looked at; %d items look like camp objects or Blueprints"):format(slots, #out)
    if #out == 0 then return "none", value end
    return "readable", value, capList(out)
  end })

-- 6. The next-ability display's inputs (spec 03a): readable or secret, out of combat and in combat -------------------------------
local function firstSpell()
  -- a spell of the character to ask about: the first of the spellbook that has a name
  if has("C_SpellBook.GetSpellBookItemName") then
    local bank = G("Enum.SpellBookSpellBank.Player") or 0
    for i = 1, 12 do
      local st, name = ask("C_SpellBook.GetSpellBookItemName", i, bank)
      if st == "ok" and type(name) == "string" and not isSecret(name) and name ~= "" then return name end
    end
  elseif has("GetSpellBookItemName") then
    for i = 1, 12 do
      local st, name = ask("GetSpellBookItemName", i, "spell")
      if st == "ok" and type(name) == "string" and not isSecret(name) and name ~= "" then return name end
    end
  end
  return nil
end

add({ id = "advisor.targetHealth", group = "advisor", combat = true, auto = true, title = "Target health (UnitHealth, UnitHealthMax of the target)",
  run = function()
    if not has("UnitHealth") then return "missing", "UnitHealth" end
    local _, exists = ask("UnitExists", "target")
    local unit = (not isSecret(exists) and exists) and "target" or "player"
    local st, cur = ask("UnitHealth", unit)
    local st2, max = ask("UnitHealthMax", unit)
    if st ~= "ok" or st2 ~= "ok" then return "error", plain(cur) end
    return state(cur, max), ("asked of the %s: %s / %s"):format(unit, plain(cur), plain(max)), nil, unit == "player" and "no target: asked of the character instead" or nil
  end })

add({ id = "advisor.power", group = "advisor", combat = true, auto = true, title = "The character's own power (UnitPower, UnitPowerMax)",
  run = function()
    if not has("UnitPower") then return "missing", "UnitPower" end
    local st, cur = ask("UnitPower", "player")
    local st2, max = ask("UnitPowerMax", "player")
    if st ~= "ok" or st2 ~= "ok" then return "error", plain(cur) end
    return state(cur, max), ("%s / %s"):format(plain(cur), plain(max))
  end })

add({ id = "advisor.auras", group = "advisor", combat = true, auto = true, title = "Auras (C_UnitAuras.GetAuraDataByIndex, or UnitAura)",
  run = function()
    if has("C_UnitAuras.GetAuraDataByIndex") then
      local st, d = ask("C_UnitAuras.GetAuraDataByIndex", "player", 1, "HELPFUL")
      if st ~= "ok" then return "error", plain(d) end
      if d == nil then return "readable", "C_UnitAuras: the character has no aura to read right now", nil, "nothing to read: a secret aura would still be returned" end
      if isSecret(d) then return "secret", "C_UnitAuras: the aura itself is secret" end
      local st3 = state(d.name, d.expirationTime, d.duration, d.applications)
      return st3, ("C_UnitAuras: name %s, expires %s, duration %s"):format(isSecret(d.name) and "secret" or "readable", isSecret(d.expirationTime) and "secret" or "readable",
        isSecret(d.duration) and "secret" or "readable")
    elseif has("UnitAura") then
      local st, name, _, _, _, duration, expires = ask("UnitAura", "player", 1, "HELPFUL")
      if st ~= "ok" then return "error", plain(name) end
      if name == nil then return "readable", "UnitAura: the character has no aura to read right now" end
      return state(name, duration, expires), ("UnitAura: name %s, expires %s"):format(isSecret(name) and "secret" or "readable", isSecret(expires) and "secret" or "readable")
    end
    return "missing", "neither C_UnitAuras.GetAuraDataByIndex nor UnitAura"
  end })

add({ id = "advisor.cooldown", group = "advisor", combat = true, auto = true, title = "Cooldowns (C_Spell.GetSpellCooldown, or GetSpellCooldown)",
  run = function()
    local spell = firstSpell()
    if not spell then return "none", "no spell in the spellbook to ask about" end
    if has("C_Spell.GetSpellCooldown") then
      local st, info = ask("C_Spell.GetSpellCooldown", spell)
      if st ~= "ok" then return "error", plain(info) end
      if info == nil then return "none", "C_Spell.GetSpellCooldown answered nothing for " .. spell end
      if isSecret(info) then return "secret", "C_Spell.GetSpellCooldown: the answer is secret (" .. spell .. ")" end
      return state(info.startTime, info.duration), ("C_Spell.GetSpellCooldown(%s): start %s, duration %s"):format(spell, isSecret(info.startTime) and "secret" or "readable",
        isSecret(info.duration) and "secret" or "readable")
    elseif has("GetSpellCooldown") then
      local st, start, duration = ask("GetSpellCooldown", spell)
      if st ~= "ok" then return "error", plain(start) end
      return state(start, duration), ("GetSpellCooldown(%s): start %s, duration %s"):format(spell, isSecret(start) and "secret" or "readable", isSecret(duration) and "secret" or "readable")
    end
    return "missing", "neither C_Spell.GetSpellCooldown nor GetSpellCooldown"
  end })

add({ id = "advisor.usable", group = "advisor", combat = true, auto = true, title = "Usable and out of power (C_Spell.IsSpellUsable, or IsUsableSpell)",
  run = function()
    local spell = firstSpell()
    if not spell then return "none", "no spell in the spellbook to ask about" end
    local path = has("C_Spell.IsSpellUsable") and "C_Spell.IsSpellUsable" or (has("IsUsableSpell") and "IsUsableSpell" or nil)
    if not path then return "missing", "neither C_Spell.IsSpellUsable nor IsUsableSpell" end
    local st, usable, noPower = ask(path, spell)
    if st ~= "ok" then return "error", plain(usable) end
    return state(usable, noPower), ("%s(%s): usable %s, out of power %s"):format(path, spell, isSecret(usable) and "secret" or "readable", isSecret(noPower) and "secret" or "readable")
  end })

add({ id = "advisor.proc", group = "advisor", combat = true, auto = true, title = "Procs (the game's own spell alert: IsSpellOverlayed)",
  run = function()
    local path = has("C_SpellActivationOverlay.IsSpellOverlayed") and "C_SpellActivationOverlay.IsSpellOverlayed" or (has("IsSpellOverlayed") and "IsSpellOverlayed" or nil)
    if not path then return "missing", "neither C_SpellActivationOverlay.IsSpellOverlayed nor IsSpellOverlayed" end
    local st, v = ask(path, 1)
    if st ~= "ok" then return "error", plain(v) end
    return state(v), path .. ": " .. (isSecret(v) and "secret" or "readable")
  end })

add({ id = "advisor.macro", group = "advisor", combat = true, auto = true, title = "Macro conditions (SecureCmdOptionParse called from an add-on)",
  run = function(inCombat)
    if not has("SecureCmdOptionParse") then return "missing", "SecureCmdOptionParse" end
    local st, v = ask("SecureCmdOptionParse", "[combat] in; out")
    if st ~= "ok" then return "error", plain(v) end
    if isSecret(v) then return "secret", "the answer is secret" end
    local want = inCombat and "in" or "out"
    return "readable", ("answered '%s'%s"):format(plain(v), v == want and "" or (" (expected '" .. want .. "')"))
  end })

-- 7. The icon slots' fallbacks: does this game have each file -------------------------------------------------------------------
add({ id = "icons.fallbacks", group = "icons", title = "The game's own textures the icon slots fall back to",
  run = function()
    local K = Panoply.Kit
    if not (K and K.ICONS) then return "none", "the icon slots are not loaded" end
    if C.FileExists("Interface\\Icons\\INV_Misc_QuestionMark") == nil then return "missing", "this game cannot say whether a file exists (GetFileIDFromPath)" end
    local names, out, miss = {}, {}, 0
    for slot in pairs(K.ICONS) do names[#names + 1] = slot end
    table.sort(names)
    for _, slot in ipairs(names) do
      for _, path in ipairs(K.ICONS[slot].game or {}) do
        local there = C.FileExists(path) == true
        if not there then miss = miss + 1 end
        out[#out + 1] = ("%s: %s: %s"):format(slot, path, there and "yes" or "NO")
      end
    end
    return "ok", ("%d fallback files asked about, %d not in this game"):format(#out, miss), capList(out)
  end })

-- 7b. 0.9.5 phase 4G: the map favorites' icons (Modules/Map/Favorites.lua types and professions, the picker's named list) -----------
add({ id = "icons.favorites", group = "icons", title = "The game's own textures the map favorites use",
  run = function()
    local Fv, FW = Panoply.Map and Panoply.Map.Favorites, Panoply.Map and Panoply.Map.FavWindow
    if not (Fv and FW) then return "none", "map favorites are not loaded" end
    if C.FileExists("Interface\\Icons\\INV_Misc_QuestionMark") == nil then return "missing", "this game cannot say whether a file exists (GetFileIDFromPath)" end
    local out, miss, seen = {}, 0, {}
    local function ask(what, path)
      if type(path) ~= "string" or seen[path] then return end
      seen[path] = true
      local there = C.FileExists(path) == true
      if not there then miss = miss + 1 end
      out[#out + 1] = ("%s: %s: %s"):format(what, path, there and "yes" or "NO")
    end
    for _, t in ipairs(Fv.TYPES) do ask("type " .. t.key, t.icon) end
    ask("type flight (Horde)", "Interface\\Icons\\Ability_Mount_Wyvern_01")
    for _, p in ipairs(Fv.PROFS) do ask("trainer " .. p, Fv.PROF_ICON[p]) end
    for _, n in ipairs(FW.ICON_NAMES) do ask("picker", "Interface\\Icons\\" .. n) end
    return "ok", ("%d files asked about, %d not in this game"):format(#out, miss), capList(out)
  end })

-------------------------------------------------------------------------------
-- Running
-------------------------------------------------------------------------------
local function character()
  local p = C.PlayerInfo() or {}
  local level = C.XPKnown and C.XPKnown() or nil
  return { name = p.name, realm = p.realm, class = p.classFile, faction = p.faction, level = tonumber(level) }
end

function Probe:RunCheck(def, inCombat)
  local ok, status, value, list, note = pcall(def.run, inCombat)
  if not ok then return { status = "error", value = cut(status) } end
  local r = { status = status or "error", value = value ~= nil and cut(value) or nil, note = note }
  if type(list) == "table" and #list > 0 then
    r.list = {}
    for i, l in ipairs(list) do r.list[i] = cut(l) end
  end
  local t = G("time")
  r.at = type(t) == "function" and t() or nil
  return r
end

local function applies(def, forever)
  return not def.forever or forever
end

-- Run the checks. opts.auto: only the cheap ones that run by themselves (the next-ability display's inputs). Returns the record
-- and how many checks ran.
function Probe:Run(opts)
  opts = opts or {}
  local rec = self:Record(true)
  local forever = C.IsForever()
  local inCombat = C.InCombat()
  local before = {}
  for id, r in pairs(rec.results) do before[id] = r.status end
  local n = 0
  for _, def in ipairs(self.checks) do
    if applies(def, forever) and (not opts.auto or def.auto) then
      n = n + 1
      if def.combat then
        -- the answer out of combat now, the answer in combat when there is a fight (or now, if this IS a fight)
        if inCombat then
          rec.results[def.id .. ":combat"] = self:RunCheck(def, true)
          if rec.results[def.id] == nil then rec.results[def.id] = { status = "pending", note = "Asked the next time the command runs out of combat." } end
        else
          rec.results[def.id] = self:RunCheck(def, false)
          if rec.results[def.id .. ":combat"] == nil then
            rec.results[def.id .. ":combat"] = { status = "pending", note = "Recorded the next time this character is in combat." }
          end
        end
      else
        rec.results[def.id] = self:RunCheck(def, inCombat)
      end
    end
  end
  local t = G("time")
  rec.ran = type(t) == "function" and t() or nil
  rec.runs = (tonumber(rec.runs) or 0) + 1
  rec.addon = Panoply.version
  rec.character = character()
  if not opts.auto then rec.full = rec.ran end
  self.changed = {}
  for id, was in pairs(before) do
    local now = rec.results[id] and rec.results[id].status
    if (was == "readable" or was == "secret") and (now == "readable" or now == "secret") and was ~= now then self.changed[#self.changed + 1] = id end
  end
  table.sort(self.changed)
  Panoply:Fire("PROBE_DONE", rec)
  return rec, n
end

-- the in-combat answers, the first time there is a fight after a run left them pending
function Probe:RunCombat()
  local rec = self:Record(false)
  if not rec or not C.InCombat() then return 0 end
  local forever = C.IsForever()
  local n = 0
  for _, def in ipairs(self.checks) do
    local id = def.id .. ":combat"
    if def.combat and applies(def, forever) and rec.results[id] and rec.results[id].status == "pending" then
      rec.results[id] = self:RunCheck(def, true)
      n = n + 1
    end
  end
  if n > 0 then Panoply:Fire("PROBE_DONE", rec) end
  return n
end

function Probe:HasPending()
  local rec = self:Record(false)
  if not rec then return false end
  for id, r in pairs(rec.results) do if id:find(":combat$") and r.status == "pending" then return true end end
  return false
end

-- What the game shares of one input of the next-ability display on this build: "readable", "secret", or "unknown" (not asked yet,
-- or the game has no such call). when = "combat" (the default: that is when the display needs it) or "out".
function Probe:Input(name, when)
  local rec = self:Record(false)
  if not rec then return "unknown" end
  local id = "advisor." .. name .. ((when or "combat") == "combat" and ":combat" or "")
  local r = rec.results[id]
  if r and (r.status == "readable" or r.status == "secret") then return r.status end
  return "unknown"
end

-- "3 of 7 inputs readable on this client" (in combat), or nil when nothing was asked in combat yet
function Probe:InputSummary()
  local total, readable, known = 0, 0, 0
  for _, def in ipairs(self.checks) do
    if def.group == "advisor" then
      total = total + 1
      local st = self:Input(def.id:match("^advisor%.(.+)$"), "combat")
      if st ~= "unknown" then known = known + 1 end
      if st == "readable" then readable = readable + 1 end
    end
  end
  if known == 0 then return nil, 0, total end
  return ("%d of %d inputs readable on this client"):format(readable, known), readable, known
end

-------------------------------------------------------------------------------
-- Watching events (which fire when a challenge completes or a perk is spent): only after /panoply probe, only for that session
-------------------------------------------------------------------------------
Probe.WATCH = { "ACHIEVEMENT_EARNED", "CRITERIA_EARNED", "CRITERIA_COMPLETE", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED",
  "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "SKILL_LINES_CHANGED", "NEW_TOY_ADDED", "NEW_MOUNT_ADDED", "NEW_PET_ADDED" }
function Probe:Watch()
  if self.watching then return 0 end
  self.watching = true
  local n = 0
  for _, ev in ipairs(self.WATCH) do
    Panoply:On(ev, function(event, ...)
      local rec = Probe:Record(false)
      if not rec then return end
      local e = rec.events[event]
      local t = G("time")
      local now = type(t) == "function" and t() or nil
      if not e then e = { n = 0, first = now } rec.events[event] = e end
      e.n = e.n + 1
      e.last = now
      if e.n <= 3 then
        local parts = {}
        for i = 1, math.min(select("#", ...), 6) do parts[i] = plain((select(i, ...))) end
        e.args = cut(table.concat(parts, ", "))
      end
    end)
    if not (Panoply.skippedEvents and Panoply.skippedEvents[ev]) then n = n + 1 end
  end
  self.watched = n
  return n
end

-------------------------------------------------------------------------------
-- The command: /panoply probe [show | clear]
-------------------------------------------------------------------------------
local ORDER = { "readable", "secret", "ok", "none", "missing", "error", "pending" }
function Probe:Counts(rec)
  local c = {}
  for _, r in pairs(rec and rec.results or {}) do c[r.status] = (c[r.status] or 0) + 1 end
  local parts = {}
  for _, k in ipairs(ORDER) do if c[k] then parts[#parts + 1] = c[k] .. " " .. k end end
  return table.concat(parts, ", "), c
end

function Probe:Lines(rec)
  local out = {}
  if not rec then return { "Nothing has been probed on this game version yet. Type /panoply probe." } end
  for _, def in ipairs(self.checks) do
    for _, id in ipairs(def.combat and { def.id, def.id .. ":combat" } or { def.id }) do
      local r = rec.results[id]
      if r then out[#out + 1] = ("%s: %s%s"):format(id, r.status, r.value and (" - " .. r.value) or (r.note and (" - " .. r.note) or "")) end
    end
  end
  return out
end

function Probe:Slash(arg)
  arg = tostring(arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "show" or arg == "list" then
    local rec, key = self:Record(false)
    if rec then Panoply:Print("Probe of " .. tostring(key) .. ":") end
    for _, l in ipairs(self:Lines(rec)) do Panoply:Print(l) end
    return
  elseif arg == "clear" or arg == "forget" then
    _G.PanoplySuiteProbeDB = nil
    Panoply:Print("The probe's saved answers are forgotten.")
    return
  elseif arg ~= "" then
    Panoply:Print("Usage: /panoply probe - ask this game what it shares with add-ons;  probe show - what was found;  probe clear - forget it")
    return
  end
  local rec, n = self:Run()
  local _, key = self:Record(false)
  local watched = self:Watch()
  Panoply:Print(("Probe of %s: %d checks, %s."):format(tostring(key), n, self:Counts(rec)))
  if self:HasPending() then Panoply:Print("The in-combat answers are recorded the next time this character is in a fight. Nothing is forced.") end
  if (watched or self.watched or 0) > 0 then
    Panoply:Print("Watching what the game says for the rest of this session: finish a challenge or spend a Legacy point if you can, then type /reload so the answers are saved.")
  else
    Panoply:Print("Type /reload so the answers are saved. /panoply probe show lists them.")
  end
end

-------------------------------------------------------------------------------
-- By itself: the cheap checks on a new build, and the in-combat answers when there is a fight
-------------------------------------------------------------------------------
Probe.AUTO_DELAY = 8
Panoply:On("PLAYER_LOGIN", function()
  C.After(Probe.AUTO_DELAY, function()
    if Probe:Record(false) then return end        -- this build was asked before
    local prev = Probe:Previous()
    local ok, err = pcall(Probe.Run, Probe, { auto = true })
    if not ok then Panoply:Debug("probe", err) return end
    -- one line, only when an input the next-ability display reads changed between readable and secret since the last build
    if prev then
      local rec = Probe:Record(false)
      local changed = {}
      for id, r in pairs(rec.results) do
        local was = prev.results and prev.results[id] and prev.results[id].status
        if (was == "readable" or was == "secret") and (r.status == "readable" or r.status == "secret") and was ~= r.status then changed[#changed + 1] = id end
      end
      if #changed > 0 then
        Panoply:Print(("This game version shares different things with add-ons than the last one (%d changed). /panoply probe show lists them."):format(#changed))
      end
    end
  end)
end)

Panoply:On("PLAYER_REGEN_DISABLED", function()
  if not Probe:HasPending() then return end
  -- a moment into the fight, so the game is fully in combat when it is asked
  C.After(2, function()
    if C.InCombat() then
      local ok, err = pcall(Probe.RunCombat, Probe)
      if not ok then Panoply:Debug("probe combat", err) end
    end
  end)
end)
