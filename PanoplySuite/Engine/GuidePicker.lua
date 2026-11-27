-- Panoply Suite 0.9.7: the guide picker (which written guide the character follows). Own code; it calls the engine, it does not copy it.
-- The engine's public calls only: Guides.List / Guides.GuideMatches / Guides.Suggest / Guides.Get, Engine.GetTabs / Engine.GetGuide /
-- Engine.GetGuideState / Engine.SetGuide, Compat.GetPlayerInfo. The windows draw from this file; nothing here makes a frame.
--   GuidePicker:Available()  -> true when the guide engine runs and a guide can be picked (else GuidePicker.NOT_AVAILABLE is the one line to show)
--   GuidePicker:List()       -> the levelling guides this character can follow, in route order:
--                               { { id, title, text, minLevel, maxLevel, current, pending, suggested, state ("new" | "started" | "done"), finished }, ... }
--                               (text is the menu line, "<title> (levels a to b)"; an empty list when no guide can be picked)
--   GuidePicker:Pick(id)     -> true when the guide was chosen. In combat nothing is switched: the pick waits until combat ends and
--                               the answer is true, "after_combat". A guide that cannot be picked answers false and why, in plain words.
--   GuidePicker:PickForMe()  -> the id of the guide chosen for the character (the engine's own choice), or nil; in combat it waits too
--   GuidePicker:Current()    -> the id of the guide in use, or nil
--   GuidePicker:Pending()    -> the id of the guide a pick made in combat is waiting to open, or nil
--   GuidePicker:Title(id)    -> a guide's name as the player reads it (never the engine's name)
--   GuidePicker:Following()  -> the partner's name while this character is synced to a partner's guide, or nil
-- Progress: the engine keeps each guide's place, ticks and skips itself; going back to a guide opens it where it was left.
-- Partner (Engine/PanoplyGuideParty.lua): PanoplyGuideParty:Following() -> the partner's name while synced, or nil;
--   PanoplyGuideParty:EndSync(why) -> ends the sync, says nothing (the one line is printed here).
local ADDON, Panoply = ...
local C = Panoply.Compat
local GuidePicker = {}
Panoply.GuidePicker = GuidePicker

GuidePicker.NOT_AVAILABLE = "Guide not available."

local function PE() return Panoply.PanoplyGuideEngine end
-- the engine's own table, as the adapter finds it (Engine/PanoplyGuideEngine.lua PS.P)
local function P() local pe = PE() return pe and pe.P and pe.P() or nil end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then Panoply:Debug("guide picker call", a) return nil end
  return a, b, c
end

-- The engine, when it runs for this character and has every call the picker makes; else nil
local function engine()
  local pe, p = PE(), P()
  if not (pe and pe.Active and pe:Active() and type(p) == "table") then return nil end
  local G, E = p.Guides, p.Engine
  if not (type(G) == "table" and type(E) == "table") then return nil end
  if type(G.List) ~= "function" or type(G.GuideMatches) ~= "function" or type(G.Get) ~= "function" then return nil end
  if type(E.SetGuide) ~= "function" or type(E.GetGuide) ~= "function" then return nil end
  if not (p.Compat and type(p.Compat.GetPlayerInfo) == "function") then return nil end
  return p, G, E
end

function GuidePicker:Available()
  return engine() ~= nil
end

-- A guide's name in Panoply's voice: the engine is never named in what the player reads
local function voice(s)
  local V = Panoply.PanoplyGuideVoice
  if type(s) ~= "string" then return nil end
  if V and V.GuideText then s = V.GuideText(s) end
  if V and V.Text then s = V.Text(s) end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

local function titleOf(h)
  return voice(h.title) or voice(h.zoneName) or "Guide"
end

local function levelsOf(h)
  local lo = tonumber(h.minLevel) or 1
  local hi = tonumber(h.maxLevel) or lo
  if hi < lo then hi = lo end
  return lo, hi
end

local function lineOf(h)
  local lo, hi = levelsOf(h)
  if lo == hi then return ("%s (level %d)"):format(titleOf(h), lo) end
  return ("%s (levels %d to %d)"):format(titleOf(h), lo, hi)
end

-- Is this one of the engine's own levelling guides, and one this character can follow? (the engine's own fit check)
local function fits(G, h, player, pack)
  if type(h) ~= "table" or type(h.id) ~= "string" then return false end
  if h.pack ~= pack then return false end
  if h.category ~= nil and h.category ~= "Leveling" then return false end
  return call(G.GuideMatches, h, player) == true
end

-- The engine's headers of the guides this character can pick, in route order (the order the engine lists them in)
local function fitting()
  local p, G, E = engine()
  if not p then return {} end
  local player = call(p.Compat.GetPlayerInfo)
  if type(player) ~= "table" then return {}, p, G, E end
  local pack = PE().LEVELING_PACK
  local out, at = {}, {}
  for i, h in ipairs(call(G.List) or {}) do
    if fits(G, h, player, pack) then out[#out + 1] = h at[h] = i end
  end
  -- route order: by the levels a guide is for (the race's own first guide is listed by the engine after the shared ones)
  table.sort(out, function(a, b)
    local alo, ahi = levelsOf(a)
    local blo, bhi = levelsOf(b)
    if alo ~= blo then return alo < blo end
    if ahi ~= bhi then return ahi < bhi end
    return at[a] < at[b]
  end)
  return out, p, G, E
end

local function currentId(E)
  if type(E.GetTabs) == "function" then
    local tabs, active = call(E.GetTabs)
    local t = type(tabs) == "table" and tabs[active or 0] or nil
    if type(t) == "table" and t.guideId then return t.guideId end
  end
  local g = call(E.GetGuide)
  return type(g) == "table" and g.id or nil
end

function GuidePicker:Current()
  local p, G, E = engine()
  if not p then return nil end
  return currentId(E)
end

function GuidePicker:Pending()
  return self.pending
end

function GuidePicker:Title(id)
  local p, G = engine()
  local g = p and id and call(G.Get, id)
  if type(g) ~= "table" then return nil end
  return titleOf(g)
end

function GuidePicker:List()
  local heads, p, G, E = fitting()
  local out = {}
  if #heads == 0 then return out end
  local cur = currentId(E)
  local best = type(G.Suggest) == "function" and call(G.Suggest) or nil
  for _, h in ipairs(heads) do
    local lo, hi = levelsOf(h)
    local state = type(E.GetGuideState) == "function" and call(E.GetGuideState, h.id) or nil
    if state ~= "started" and state ~= "done" then state = "new" end
    out[#out + 1] = {
      id = h.id, title = titleOf(h), text = lineOf(h), minLevel = lo, maxLevel = hi,
      current = h.id == cur, pending = h.id == self.pending, suggested = h.id == best,
      state = state, finished = state == "done",
    }
  end
  return out
end

-- The partner this character is synced to (Engine/PanoplyGuideParty.lua keeps it)
function GuidePicker:Following()
  local PP = Panoply.PanoplyGuideParty
  if not (PP and type(PP.Following) == "function") then return nil end
  local name = PP:Following()
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Picking another guide while synced to a partner ends the sync, with one line saying so. `name`: who was followed before the
-- guide was switched (once it is, the partner is on another guide and PanoplyGuideParty no longer names them).
local function endSync(name)
  if not name then return end
  local PP = Panoply.PanoplyGuideParty
  if PP and type(PP.EndSync) == "function" then PP:EndSync("guide") end
  Panoply:Print(("You picked another guide, so you no longer follow %s's guide."):format(name))
end

-- The switch itself. Never in combat (Pick and the end of combat are the only callers).
local function switch(self, id)
  local heads, p, G, E = fitting()
  if not p then return false, self.NOT_AVAILABLE end
  local head
  for _, h in ipairs(heads) do if h.id == id then head = h break end end
  if not head then return false, "That guide is not one this character can follow." end
  if currentId(E) == id then return true end
  local followed = self:Following()
  if call(E.SetGuide, id) ~= true or currentId(E) ~= id then return false, "That guide could not be opened." end
  -- "Leveling guide" in the guide source switch comes back to the guide picked here (Engine/PanoplyGuideEngine.lua PS:SetSource)
  if Panoply.cdb then Panoply.cdb.psLevelingGuide = id end
  endSync(followed)
  local pe = PE()
  pe.stale = true
  pe:Sync("guide")
  pe:SyncRoute("replan")
  Panoply:Fire("OPTION_CHANGED", "guidePick", id)
  return true
end

function GuidePicker:Pick(id)
  if type(id) ~= "string" then return false, "That guide is not one this character can follow." end
  if not self:Available() then return false, self.NOT_AVAILABLE end
  if C.InCombat() then
    local title = self:Title(id)
    local ok
    for _, h in ipairs(fitting()) do if h.id == id then ok = true break end end
    if not (title and ok) then return false, "That guide is not one this character can follow." end
    if self:Current() == id then
      -- back to the guide in use: the pick that was waiting is taken back
      self.pending = nil
      return true
    end
    if self.pending ~= id then
      self.pending = id
      Panoply:Print(("The guide '%s' is opened when combat ends."):format(title))
    end
    return true, "after_combat"
  end
  self.pending = nil
  return switch(self, id)
end

function GuidePicker:PickForMe()
  local p, G = engine()
  if not (p and type(G.Suggest) == "function") then return nil end
  local id = call(G.Suggest)
  if type(id) ~= "string" then return nil end
  if self:Pick(id) then return id end
  return nil
end

-- A pick made in combat is made now
Panoply:On("PLAYER_REGEN_ENABLED", function()
  local id = GuidePicker.pending
  if not id then return end
  if C.InCombat() then return end
  GuidePicker.pending = nil
  local ok, why = switch(GuidePicker, id)
  if ok then Panoply:Print(("Your guide is now %s."):format(GuidePicker:Title(id) or "the one you picked"))
  else Panoply:Print(why or "That guide could not be opened.") end
end)
