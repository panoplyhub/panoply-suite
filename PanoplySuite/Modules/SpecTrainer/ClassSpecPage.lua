-- Panoply Suite, Step 2 item C: the words of Class & Spec (docs/step2/ABC-SPEC.md C-01, C-02; "Spec & Trainer" renamed).
-- 0.9.5 phase 4H (docs/specs/page-redesigns-03-class.md): the Class & Spec page is gone. Its Plan tab is the Class page's header (the plan
-- dropdown) and Talents tab; its Spells to buy tab is the Class page's Spells tab (Modules/ClassPages/PageTabs.lua). What stays here are
-- the words other parts still say (Home's lines, the trainer card, the tests) and the old door, which now opens the Class page.
-- Nothing here buys anything or spends a talent point; buying is the Learn button at the trainer (TrainerPanel.lua).
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local C = Panoply.Compat

-- the old door: "plan" opens Talents, "spells" opens Spells (the Class page)
ST.CLASS_TAB = { plan = "talents", spells = "spells", talents = "talents" }
function ST:OpenClassSpec(tab)
  local CP = Panoply.ClassPages
  local t = self.CLASS_TAB[tab or ""] or "talents"
  if CP and CP.Open then return CP:Open(nil, t) end
  return Panoply.Menu:Open("class")
end

local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end

-------------------------------------------------------------------------------
-- The words (also read by the previews and the tests)
-------------------------------------------------------------------------------
-- "Mirabel: level 12 Mage"
function ST:WhoLine()
  local info = C.PlayerInfo() or {}
  local level = C.XP()
  local cls = ST.CLASS_NAME[info.classFile or ""] or info.class
  local name = info.name
  if not cls then return name or "" end
  return ("%s%d %s"):format(name and (name .. ": level ") or "Level ", level or 1, cls)
end

-- What the "YOU FOLLOW" card says: { big, lines = { ... } }
function ST:FollowText()
  local cls = self:ClassFile()
  local t = self:Tracked()
  if not t then
    return { big = "No plan yet", lines = { "Pick a plan at the top of the Class page, or start your own. Until you do, the trainer helper uses "
      .. ((self:VerdictPlan() or {}).name or "your class's plan") .. "." } }
  end
  local lines = { self:TreeSummary(cls, t.points) }
  local ok, n = pcall(self.Next, self, t)
  if ok and n and n.tal then
    lines[#lines + 1] = ("Next talent: %s, rank %d of %d."):format(n.tal.name, n.rank, n.tal.ranks)
    if n.why and n.why ~= "" then lines[#lines + 1] = n.why end
  else
    lines[#lines + 1] = "No talent to take right now."
  end
  -- Nov 2026: how the plan stands against the talents the character really has
  local okS, sync, differs = pcall(self.SyncLine, self, t)
  if okS and sync then
    lines[#lines + 1] = differs and (sync .. " On the Talents tab, Match my talents starts the plan from them.") or sync
  end
  return { big = t.name or t.key, lines = lines }
end

-- What the "SPELLS TO BUY" card says: { big, lines = { ... }, enabled }
function ST:BuyText(sp)
  sp = sp or self:SpellPlan()
  if not sp.table then
    return { big = "No trainer table", lines = { "Panoply Suite Quest Data is not installed, so spells are listed at the trainer only." } }
  end
  local big
  if sp.now and sp.now.buy.n > 0 then
    big = ("%d %s to buy now, %s"):format(sp.now.buy.n, plural(sp.now.buy.n, "spell"), ST.Money(sp.now.buy.cost))
  else
    big = "Nothing to buy now"
  end
  local lines = {}
  if sp.next then
    lines[1] = ("Next visit: level %d, %d %s, %s."):format(sp.next.level, sp.next.buy.n, plural(sp.next.buy.n, "spell"), ST.Money(sp.next.buy.cost))
  elseif not (sp.now and sp.now.buy.n > 0) then
    lines[1] = "Nothing left to buy from your class trainer."
  end
  return { big = big, lines = lines }
end

-- The whole-plan card: { label, big, lines = { ... } }
function ST:TotalText(sp)
  sp = sp or self:SpellPlan()
  local out = { label = ("THE WHOLE PLAN, LEVEL %d TO %d"):format(sp.from, sp.to), lines = {} }
  if not sp.table then
    out.big = "No trainer table"
    out.lines[1] = "Panoply Suite Quest Data is not installed, so there is no spell plan. The trainer panel still lists what the trainer teaches."
    return out
  end
  if sp.buy.n == 0 then
    out.big = "Nothing to buy"
    out.lines[1] = "Your plan has nothing left to buy from your class trainer."
  else
    out.big = ("%d %s to buy, %s in all"):format(sp.buy.n, plural(sp.buy.n, "spell"), ST.Money(sp.buy.cost))
  end
  local first = {}
  if sp.skip.n > 0 then first[#first + 1] = ("You skip %d %s and save %s."):format(sp.skip.n, plural(sp.skip.n, "spell"), ST.Money(sp.skip.cost)) end
  first[#first + 1] = ("You have %s now."):format(ST.Money(sp.money))
  out.lines[#out.lines + 1] = table.concat(first, " ")
  local soft = {}
  if sp.opt.n > 0 then soft[#soft + 1] = ("Not counted: %d optional %s (%s)."):format(sp.opt.n, plural(sp.opt.n, "spell"), ST.Money(sp.opt.cost)) end
  soft[#soft + 1] = "Prices are what the trainer charges; until you visit one they come from Panoply Suite's own table."
  out.lines[#out.lines + 1] = table.concat(soft, " ")
  return out
end

-- one line that says whose plan the spell plan follows
function ST:PlanIntro(sp)
  local name = sp.plan and sp.plan.name or "your class's plan"
  if sp.how == "plan" then return ("Following %s. Each trainer visit: what to buy, what it costs, and what is skipped."):format(name) end
  return ("No plan picked yet, so this uses %s. Pick one at the top of the page."):format(name)
end
