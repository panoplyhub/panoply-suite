-- Panoply Suite /panoply selftest: checks every API wrapper and every module, prints PASS/WARN/MISSING.
local ADDON, Panoply = ...
local T = {}
Panoply.SelfTest = T
local C, U = Panoply.Compat, Panoply.Util

local COLORS = { PASS = "ff4cd964", WARN = "fff7b90a", MISSING = "ffff5050", SKIP = "ffaaaaaa", FAIL = "ffff5050" }

T.modules = {
  { "SavedVariables", function()
      if not Panoply.db or not Panoply.cdb then return "FAIL", "saved settings not loaded" end
      return "PASS", ("auto accept %s, turn-in %s, fly %s"):format(tostring(Panoply.db.autoAccept), tostring(Panoply.db.autoTurnIn), tostring(Panoply.db.autoFly))
    end },
  { "QuestDB", function()
      local QD = Panoply.QuestData
      if not QD:Available() then QD:Init() end
      if not QD:Available() then return "WARN", QD.status end
      local ids = QD:AllQuestIds()
      local q = QD:GetQuest(783)   -- an early Alliance quest; a sanity check that ids line up
      return (#ids > 0 and q) and "PASS" or "WARN", ("%s, %d quests%s"):format(QD.status or "", #ids, q and "" or ", sample quest 783 missing (data mismatch?)")
    end },
  { "Planner", function()
      local QD = Panoply.QuestData
      if not QD:Available() then return "SKIP", "needs Panoply Suite Quest Data" end
      local S = Panoply.Planner:StateFromGame()
      local actions, stats = Panoply.Planner:Generate(S, { goalLevel = math.min((S.level or 1) + 1, 60), maxActions = 30 })
      if not actions then return "FAIL", tostring(stats) end
      return "PASS", ("%d actions from %d candidate quests"):format(#actions, stats.candidates)
    end },
  { "StepEngine", function()
      local n = #Panoply.Engine.steps
      return "PASS", ("%d steps loaded, on step %d"):format(n, Panoply.Engine.index)
    end },
  { "SyncEncoding", function()
      local payload = { h = "abc", a = {} }
      for i = 1, 120 do payload.a[i] = { "a", 1000 + i, 1429, 4123, 5567, 197, 0 } end
      local msgs = Panoply.Sync.Encode("P", payload, "z")
      for _, m in ipairs(msgs) do if #m > 255 then return "FAIL", "chunk too long" end end
      local kind, back
      for _, m in ipairs(msgs) do kind, back = Panoply.Sync:Receive("SelfTest", m, 0) end
      if kind ~= "P" or not back or #back.a ~= 120 or back.a[120][2] ~= 1120 then return "FAIL", "roundtrip failed" end
      return "PASS", ("%d chunks roundtrip ok; %s"):format(#msgs, Panoply.Sync:StatusText())
    end },
  { "Professions", function()
      if not Panoply.ProfData.WORLD then return "SKIP", "needs PanoplySuite_QuestData (profession data)" end
      local parts = {}
      for _, n in ipairs({ "Mining", "Blacksmithing", "Enchanting", "Tailoring", "Cooking", "Fishing", "First Aid" }) do
        local plan = Panoply.Professions:Plan(n, { from = 1, to = 300, level = 60 })
        if not plan or plan.to ~= 300 then return "FAIL", n .. " plan did not reach 300" end
        parts[#parts + 1] = ("%s %d"):format(n, #plan.segments)
      end
      local G = Panoply.ProfGuide
      return "PASS", ("segments: %s; guide follows %s (%s)"):format(table.concat(parts, ", "), G:Tracked() or "none", G:Mode())
    end },
  { "DungeonFilter", function()
      local f = Panoply.Planner.filterStats
      if Panoply.Difficulty.Rules().dungeons then
        return "PASS", ("group and dungeon quests included (Group quests: %s); raid quests left out: %d"):format(Panoply.Difficulty.GroupQuestsName(), f and f.raid or 0)
      end
      if not f then return "SKIP", "no route planned yet" end
      return "PASS", ("left out %d quests: dungeon %d, raid %d, elite %d, lead-ins %d; %d in your log"):format(
        f.total, f.dungeon or 0, f.raid or 0, f.elite or 0, f.leadIn or 0, f.log or 0)
    end },
  { "Textures", function()
      local missing, unknown, n = {}, 0, 0
      for key, path in pairs(Panoply.Skin.BUILTIN) do
        n = n + 1
        local e = C.FileExists(path)
        if e == false then missing[#missing + 1] = key elseif e == nil then unknown = unknown + 1 end
      end
      table.sort(missing)
      if #missing > 0 then return "WARN", ("%d of %d game textures missing, own art used instead: %s"):format(#missing, n, table.concat(missing, ", ")) end
      if unknown == n then return "PASS", ("%d game textures (this client cannot check files; fallbacks ready)"):format(n) end
      return "PASS", ("%d game textures found"):format(n)
    end },
  -- 0.6.1: launch-day aid. The client's version and the events this client does not know (skipped by
  -- Panoply:On through C_EventUtils.IsEventValid). Expected on WoW Forever: the Era-only auction list,
  -- craft window and old trade skill events (Panoply Suite also listens to their Forever versions,
  -- e.g. TRADE_SKILL_LIST_UPDATE). Anything else is worth a look.
  { "Client", function()
      local gbi = _G.GetBuildInfo
      local ver, build, _, iface = "?", "?", nil, "?"
      if gbi then local okB, v, b, d, i = pcall(gbi); if okB then ver, build, iface = tostring(v), tostring(b), tostring(i) end end
      -- AUCTION_OWNED_LIST_UPDATE: the Auctions trading window's own-auctions list on Era (Forever uses C_AuctionHouse)
      -- 0.9.5: the bank's buy row listens to both games' events (Modules/Bags/Bags.lua): bank bag slots on Era
      -- (PLAYERBANKBAGSLOTS_CHANGED), bank tabs on Forever (BANK_TABS_CHANGED, BANK_TAB_SETTINGS_UPDATED)
      local expected = { AUCTION_ITEM_LIST_UPDATE = true, AUCTION_OWNED_LIST_UPDATE = true, CRAFT_SHOW = true, CRAFT_UPDATE = true, CRAFT_CLOSE = true, TRADE_SKILL_UPDATE = true,
        PLAYERBANKBAGSLOTS_CHANGED = true, BANK_TABS_CHANGED = true, BANK_TAB_SETTINGS_UPDATED = true }
      local skipped, odd = {}, {}
      for ev in pairs(Panoply.skippedEvents or {}) do
        skipped[#skipped + 1] = ev
        if not expected[ev] then odd[#odd + 1] = ev end
      end
      table.sort(skipped); table.sort(odd)
      local text = ("%s (%s), interface %s, %s; events this client does not have: %s"):format(ver, build, iface,
        Panoply.Compat.IsForever and Panoply.Compat.IsForever() and "WoW Forever" or "not WoW Forever",
        #skipped > 0 and table.concat(skipped, ", ") or "none")
      if #odd > 0 then return "WARN", text .. " (unexpected: " .. table.concat(odd, ", ") .. ")" end
      return "PASS", text
    end },
  { "UI", function()
      if not (Panoply.UI and Panoply.UI.frame) then return "WARN", "window not created yet" end
      local parts = {}
      if not (Panoply.Minimap and Panoply.Minimap.button) then parts[#parts + 1] = "minimap button" end
      if not Panoply.Toast.frame then parts[#parts + 1] = "toast" end
      if #parts > 0 then return "WARN", "not created: " .. table.concat(parts, ", ") end
      return "PASS", "guide, arrow, toast, minimap button; game options page: " .. tostring(Panoply.SettingsUI.registeredWith or "not registered")
    end },
}

function T:Run(quiet)
  local results = {}
  local counts = { PASS = 0, WARN = 0, MISSING = 0, SKIP = 0, FAIL = 0 }
  local function run(group, list)
    for _, p in ipairs(list) do
      local ok, st, detail = pcall(p[2])
      if not ok then st, detail = "FAIL", tostring(st) end
      st = st or "FAIL"
      counts[st] = (counts[st] or 0) + 1
      results[#results + 1] = { group = group, name = p[1], status = st, detail = detail }
    end
  end
  run("API", C.probes)
  run("Module", self.modules)
  self.last = { results = results, counts = counts, flavor = C.Flavor(), label = C.FlavorLabel() }
  if not quiet then
    local v, b, _, toc = C.BuildInfo()
    local F = C.Features()
    Panoply:Print(("Self-test %s - detected game: %s (client %s, build %s, Interface %s)"):format(Panoply.version, C.FlavorLabel(), tostring(v), tostring(b), tostring(toc)))
    Panoply:Print(("Paths: quest log %s, objectives %s, professions %s, flights %s; Midnight rules %s"):format(
      F.questLog, F.objectives, F.tradeSkill, F.taxi, F.restrictions and "ON (sync pauses in dungeons)" or "off (sync works everywhere)"))
    for _, r in ipairs(results) do
      Panoply:Print(("|c%s%s|r %s: %s%s"):format(COLORS[r.status] or "ffffffff", r.status, r.group, r.name, r.detail and (" - " .. r.detail) or ""))
    end
    Panoply:Print(("%d pass, %d warn, %d missing, %d fail, %d skipped"):format(counts.PASS, counts.WARN, counts.MISSING, counts.FAIL, counts.SKIP))
    if counts.MISSING + counts.FAIL > 0 then Panoply:Print("Something is missing: type /panoply debug apis and send the output with a problem report.") end
  end
  return self.last
end
