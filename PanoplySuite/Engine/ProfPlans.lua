-- Panoply Suite 0.9.5, phase 4B: a plan per profession (docs/specs/page-redesigns-v1.md section 2.2, queue item 2). Until 0.9.4 one
-- plan choice applied to every profession at once: Cheapest / Fastest (PanoplySuiteDB.profStrategy, account-wide) and From my skill /
-- From scratch (PanoplySuiteCharDB.professions.mode, or the older PanoplySuiteDB.profPlanFrom). Now each profession has its own, in the
-- NEW per-character key PanoplySuiteCharDB.profPlans[profession] = { strategy = "cheapest" | "fastest", from = "current" | "scratch" }.
-- Migration: the first time a profession's plan is asked for, it starts as the old global choice. The old keys are kept and still
-- read (they are the starting point for a profession learned later), never renamed or deleted.
-- The settings panel's "Recipe plans", "/panoply prof cheapest | fastest" and anything else that sets the old global (a profile)
-- still set every profession at once (the option's hook in Engine/ProfGuide.lua), and a profession learned later starts the same.
local ADDON, Panoply = ...
local PP = {}
Panoply.ProfPlans = PP

PP.STRATEGIES = { cheapest = true, fastest = true }
PP.FROMS = { current = true, scratch = true }
-- the choices of a profession's plan dropdown, in order
PP.CHOICES = {
  { value = "cheapest", strategy = "cheapest", from = "current", text = "Cheapest",
    tip = "From your skill, the fewest gold: make bolts and bars yourself and gather what you can." },
  { value = "fastest", strategy = "fastest", from = "current", text = "Fastest",
    tip = "From your skill, the fewest crafts and trips: buy more at the Auction House." },
  { value = "cheapest-scratch", strategy = "cheapest", from = "scratch", text = "Cheapest, from scratch",
    tip = "The whole cheapest plan from skill 1, to see what all of it costs." },
  { value = "fastest-scratch", strategy = "fastest", from = "scratch", text = "Fastest, from scratch",
    tip = "The whole fastest plan from skill 1, to see what all of it costs." },
}

-- the old global choice: where a profession's own plan starts
function PP:GlobalStrategy()
  local s = Panoply.db and Panoply.db.profStrategy
  return PP.STRATEGIES[s or ""] and s or "cheapest"
end
function PP:GlobalFrom()
  local m = (Panoply.cdb and Panoply.cdb.professions and Panoply.cdb.professions.mode) or (Panoply.db and Panoply.db.profPlanFrom)
  return PP.FROMS[m or ""] and m or "current"
end

-- the saved plans of this character (made on the first ask; nil before the character's saved data exists)
function PP:Store(make)
  local c = Panoply.cdb
  if not c then return nil end
  if type(c.profPlans) ~= "table" then
    if not make then return nil end
    c.profPlans = {}
  end
  return c.profPlans
end

-- a profession's plan: { strategy, from }. A profession with no plan of its own yet gets the old global choice, saved (the migration).
function PP:Get(name)
  local t = name and self:Store(true)
  if not t then return { strategy = self:GlobalStrategy(), from = self:GlobalFrom() } end
  local e = t[name]
  if type(e) ~= "table" then
    e = { strategy = self:GlobalStrategy(), from = self:GlobalFrom() }
    t[name] = e
  end
  if not PP.STRATEGIES[e.strategy or ""] then e.strategy = self:GlobalStrategy() end
  if not PP.FROMS[e.from or ""] then e.from = self:GlobalFrom() end
  return e
end
function PP:Strategy(name) return self:Get(name).strategy end
function PP:From(name) return self:Get(name).from end

-- every profession this character plans gets its plan now (run once when the page first draws, so a later change of the old global
-- choice does not move them)
function PP:Migrate(names)
  local n = 0
  local t = self:Store(true)
  if not t then return 0 end
  for _, name in ipairs(names or {}) do
    if type(t[name]) ~= "table" then self:Get(name) n = n + 1 end
  end
  return n
end

-- the dropdown's value for a profession
function PP:Choice(name)
  local e = self:Get(name)
  for _, c in ipairs(PP.CHOICES) do if c.strategy == e.strategy and c.from == e.from then return c.value end end
  return PP.CHOICES[1].value
end

local function changed()
  local G = Panoply.ProfGuide
  if G and G.Invalidate then G:Invalidate() G:Refresh("strategy") end
  local PUI = Panoply.ProfUI
  if PUI then PUI.scratch = nil end
end

-- set one profession's plan from a dropdown value
function PP:SetChoice(name, value)
  for _, c in ipairs(PP.CHOICES) do
    if c.value == value then
      local e = self:Get(name)
      if e.strategy == c.strategy and e.from == c.from then return false end
      e.strategy, e.from = c.strategy, c.from
      changed()
      return true
    end
  end
  return false
end

-- every profession's strategy at once (the old global choice was set: the settings panel's "Recipe plans", /panoply prof cheapest |
-- fastest, a profile being applied; Engine/ProfGuide.lua's option hook calls this, so every way of setting it reaches every profession)
function PP:ApplyStrategyToAll(v)
  if not PP.STRATEGIES[v or ""] then return false end
  local t = self:Store(false)
  if t then for _, e in pairs(t) do if type(e) == "table" then e.strategy = v end end end
  local PUI = Panoply.ProfUI
  if PUI then PUI.scratch = nil end
  return true
end
-- the settings panel's "Recipe plans" and the slash command: every profession at once (and the old global, for later ones)
function PP:SetAllStrategy(v)
  if not PP.STRATEGIES[v or ""] then return false end
  self:ApplyStrategyToAll(v)
  if Panoply.db and Panoply.db.profStrategy ~= v then Panoply:SetOption("profStrategy", v) else changed() end
  return true
end
