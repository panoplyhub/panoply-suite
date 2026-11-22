-- Panoply Suite 0.9.5, phase 4B: what the Professions page reads from the game for WoW Forever's camp and trade camp, and the gather log
-- (docs/specs/page-redesigns-v1.md section 2.2: Camp tab, Trade camp entry, Scarce tab).
--   Camp objects: known = a spell of that name in the spellbook; owned = an item of that name in the bags; else missing. How the game
--     really shows them is probe question 5 (Core/Probe.lua "camp.spells" / "camp.items"); until someone runs it this is a best guess by name
--     and the page says "unverified". The cooldown is the spell's own cooldown when it is known.
--   Trade camp: Merchant's Favor from the currency list, the camp's reputation from the faction list, crates and writs in the bags, all
--     by the names in Data/ProfForever.lua. Anything the game does not answer is nil, and the page says it is not known.
--   Gather log: every item looted right after a gathering cast (Herbalism, Mining, Skinning) or from a fishing catch, counted per
--     profession in the NEW per-character key PanoplySuiteCharDB.gatherLog[profession][item name] = { n, q (quality), id }.
-- Every game call is guarded (pcall): a missing function or a secret value gives nil, never an error.
local ADDON, Panoply = ...
local PC = {}
Panoply.ProfCamp = PC
local C = Panoply.Compat

local function G(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return type(t) == "function" and t or nil
end
-- the game's answers passed straight through (a table and unpack would lose those after a nil in Lua 5.1: GetLootSlotInfo's
-- currencyID is nil for an item, before the quality)
local function tail(ok, ...) if not ok then return false end return true, ... end
local function ask(path, ...)
  local f = G(path)
  if not f then return false end
  return tail(pcall(f, ...))
end
local function str(v) return type(v) == "string" and v or nil end
local function num(v) return type(v) == "number" and v or nil end

-------------------------------------------------------------------------------
-- A snapshot of the game for one drawing of the page
-------------------------------------------------------------------------------
-- spell names in the spellbook (a set)
function PC:Spells()
  local out = {}
  if G("C_SpellBook.GetNumSpellBookSkillLines") and G("C_SpellBook.GetSpellBookSkillLineInfo") and G("C_SpellBook.GetSpellBookItemName") then
    local _, n = ask("C_SpellBook.GetNumSpellBookSkillLines")
    local bank = _G.Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for t = 1, math.min(num(n) or 0, 30) do
      local _, info = ask("C_SpellBook.GetSpellBookSkillLineInfo", t)
      if type(info) == "table" then
        local off, cnt = num(info.itemIndexOffset) or 0, num(info.numSpellBookItems) or 0
        for i = off + 1, off + math.min(cnt, 400) do
          local _, name = ask("C_SpellBook.GetSpellBookItemName", i, bank)
          if str(name) then out[name] = true end
        end
      end
    end
  elseif G("GetNumSpellTabs") and G("GetSpellTabInfo") and G("GetSpellBookItemName") then
    local _, n = ask("GetNumSpellTabs")
    for t = 1, math.min(num(n) or 0, 30) do
      local _, _, _, off, cnt = ask("GetSpellTabInfo", t)
      for i = (num(off) or 0) + 1, (num(off) or 0) + math.min(num(cnt) or 0, 400) do
        local _, name = ask("GetSpellBookItemName", i, "spell")
        if str(name) then out[name] = true end
      end
    end
  end
  return out
end

-- item names in the bags with their counts: { [name] = count }
function PC:BagItems()
  local out = {}
  for _, bag in ipairs(C.BagIDs()) do
    for slot = 1, math.min(C.NumSlots(bag) or 0, 40) do
      local s = C.SlotInfo(bag, slot)
      local name = s and str(s.link) and s.link:match("%[(.-)%]")
      if name then out[name] = (out[name] or 0) + (num(s.count) or 1) end
    end
  end
  return out
end

-- a currency's amount by name, or nil when the game does not list it
function PC:Currency(name)
  if G("C_CurrencyInfo.GetCurrencyListSize") and G("C_CurrencyInfo.GetCurrencyListInfo") then
    local _, n = ask("C_CurrencyInfo.GetCurrencyListSize")
    for i = 1, math.min(num(n) or 0, 300) do
      local _, info = ask("C_CurrencyInfo.GetCurrencyListInfo", i)
      if type(info) == "table" and info.name == name and not info.isHeader then return num(info.quantity) end
    end
  elseif G("GetCurrencyListSize") and G("GetCurrencyListInfo") then
    local _, n = ask("GetCurrencyListSize")
    for i = 1, math.min(num(n) or 0, 300) do
      local _, cname, isHeader, _, _, _, count = ask("GetCurrencyListInfo", i)
      if cname == name and not isHeader then return num(count) end
    end
  end
  return nil
end

PC.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
function PC.StandingName(id)
  id = num(id)
  if not id then return nil end
  return str(_G["FACTION_STANDING_LABEL" .. id]) or PC.STANDINGS[id]
end
function PC.StandingID(name)
  for i, n in ipairs(PC.STANDINGS) do if n == name then return i end end
  return nil
end

-- a faction's standing by name: { standing = "Neutral", standingID = 4, value, max } or nil
function PC:Reputation(name)
  if G("C_Reputation.GetNumFactions") and G("C_Reputation.GetFactionDataByIndex") then
    local _, n = ask("C_Reputation.GetNumFactions")
    for i = 1, math.min(num(n) or 0, 300) do
      local _, d = ask("C_Reputation.GetFactionDataByIndex", i)
      if type(d) == "table" and d.name == name then
        local sid = num(d.reaction)
        return { standing = PC.StandingName(sid), standingID = sid, value = (num(d.currentStanding) or 0) - (num(d.currentReactionThreshold) or 0),
          max = (num(d.nextReactionThreshold) or 0) - (num(d.currentReactionThreshold) or 0) }
      end
    end
  elseif G("GetNumFactions") and G("GetFactionInfo") then
    local _, n = ask("GetNumFactions")
    for i = 1, math.min(num(n) or 0, 300) do
      local _, fname, _, sid, lo, hi, v = ask("GetFactionInfo", i)
      if fname == name then
        return { standing = PC.StandingName(sid), standingID = num(sid), value = (num(v) or 0) - (num(lo) or 0), max = (num(hi) or 0) - (num(lo) or 0) }
      end
    end
  end
  return nil
end

-- seconds until a known spell is ready (0 = ready), or nil when the game does not say
function PC:Cooldown(spellName)
  local ok, a, b = ask("C_Spell.GetSpellCooldown", spellName)
  local start, dur
  if ok and type(a) == "table" then start, dur = num(a.startTime), num(a.duration)
  else
    ok, a, b = ask("GetSpellCooldown", spellName)
    if ok then start, dur = num(a), num(b) end
  end
  if not (start and dur) then return nil end
  if dur <= 1.5 or start <= 0 then return 0 end   -- the global cooldown is not a cooldown of its own
  local now = num(_G.GetTime and GetTime()) or 0
  return math.max(0, start + dur - now)
end

-- One snapshot per drawing: spellbook, bags, favor, the camp's reputation
function PC:Snapshot()
  local PF = Panoply.ProfForever
  local snap = { spells = self:Spells(), items = self:BagItems() }
  if C.IsForever() and PF then
    local info = C.PlayerInfo and C.PlayerInfo() or {}
    local fac = info.faction == "Horde" and "Horde" or "Alliance"
    local camp = PF.TRADE_CAMP[fac] or PF.TRADE_CAMP.Alliance
    snap.faction, snap.campName = fac, camp.name
    snap.favor = self:Currency(PF.TRADE_CAMP.currency)
    snap.rep = self:Reputation(camp.name)
    snap.crates = snap.items[PF.TRADE_CAMP.crate] or 0
    local writs = 0
    for n, c in pairs(snap.items) do if n:find(PF.TRADE_CAMP.writ, 1, true) then writs = writs + c end end
    snap.writs = writs
  end
  return snap
end

-- A camp object's state: "known" | "owned" | "missing" | "locked" (skill below the object's), and its cooldown when known
function PC:ObjectState(obj, skill, snap)
  snap = snap or self:Snapshot()
  if snap.spells[obj.name] then return "known", self:Cooldown(obj.name) end
  if (snap.items[obj.name] or 0) > 0 then return "owned" end
  for n, c in pairs(snap.items) do
    if c > 0 and n:find("Blueprint", 1, true) and n:find(obj.name, 1, true) then return "owned" end
  end
  if (skill or 0) < (obj.skill or 0) then return "locked" end
  return "missing"
end

-------------------------------------------------------------------------------
-- The gather log (NEW key PanoplySuiteCharDB.gatherLog)
-------------------------------------------------------------------------------
PC.GATHER_PROFS = { "Herbalism", "Mining", "Skinning", "Fishing" }
PC.WINDOW = 4   -- seconds between a gathering cast and the loot window that belongs to it
-- spell id -> profession, from the profession data's own rank spells (the gathering casts are those spells)
function PC:GatherSpells()
  if self.spellMap then return self.spellMap end
  local m, PD = {}, Panoply.ProfData
  for _, n in ipairs(self.GATHER_PROFS) do
    for _, rk in ipairs(PD and PD[n] and PD[n].ranks or {}) do if rk.spell then m[rk.spell] = n end end
  end
  self.spellMap = m
  return m
end
PC.GATHER_NAMES = { ["Herb Gathering"] = "Herbalism", Mining = "Mining", Skinning = "Skinning", Fishing = "Fishing" }

function PC:Log(make)
  local c = Panoply.cdb
  if not c then return nil end
  if type(c.gatherLog) ~= "table" then
    if not make then return nil end
    c.gatherLog = {}
  end
  return c.gatherLog
end

function PC:OnCast(unit, spellID)
  if unit ~= "player" then return end
  local prof = self:GatherSpells()[spellID or 0]
  if not prof and spellID then
    local n = C.SpellName and C.SpellName(spellID)
    prof = n and self.GATHER_NAMES[n]
  end
  if prof and prof ~= "Fishing" then self.pending = { prof = prof, at = num(_G.GetTime and GetTime()) or 0 } end
end

-- the loot window opened: what it holds is counted for the gathering cast just before it (or a fishing catch)
function PC:OnLoot()
  local prof
  if _G.IsFishingLoot and IsFishingLoot() then prof = "Fishing"
  else
    local p = self.pending
    local now = num(_G.GetTime and GetTime()) or 0
    if p and now - p.at <= self.WINDOW then prof = p.prof end
  end
  self.pending = nil
  if not prof then return 0 end
  local _, n = ask("GetNumLootItems")
  local added = 0
  for i = 1, math.min(num(n) or 0, 20) do
    local _, _, name, qty, _, quality = ask("GetLootSlotInfo", i)
    local _, link = ask("GetLootSlotLink", i)
    if str(name) and (num(qty) or 0) > 0 then
      local log = self:Log(true)
      if not log then return added end
      log[prof] = log[prof] or {}
      local e = log[prof][name] or { n = 0 }
      e.n = e.n + qty
      e.q = num(quality) or e.q
      e.id = (str(link) and tonumber(link:match("item:(%d+)"))) or e.id
      log[prof][name] = e
      added = added + qty
    end
  end
  return added
end

-- the scarce materials of a profession in the log: the names Data/ProfForever.lua flags, else uncommon (green) quality or better
function PC:Scarce(prof)
  local log = self:Log(false)
  local PF = Panoply.ProfForever
  local flagged = {}
  for _, n in ipairs(PF and PF.SCARCE or {}) do flagged[n] = true end
  local out = {}
  for name, e in pairs(log and log[prof] or {}) do
    if type(e) == "table" and (flagged[name] or (e.q or 0) >= 2) then out[#out + 1] = { name = name, n = e.n or 0, q = e.q, id = e.id } end
  end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return out
end
function PC:Logged(prof)
  local log = self:Log(false)
  local n = 0
  for _, e in pairs(log and log[prof] or {}) do if type(e) == "table" then n = n + (e.n or 0) end end
  return n
end

Panoply:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID) PC:OnCast(unit, spellID) end)
Panoply:On("LOOT_OPENED", function() PC:OnLoot() end)
