-- Panoply Suite, the hunter's pet (0.8.4): the panel. Panoply.HunterPet:BuildPanel(parent) builds it into a frame and fills it.
-- 0.9.1 (11 Nov 2026: "Flatten professions yes but why a diff page for hunters? Should be in the class page"; no third menu
-- level, only the left list plus ONE row of top tabs): the panel is the Pet tab of the Hunter's Class Guide (Modules/ClassPages,
-- CP:Mount), one tab on that page's one row. It has no tabs of its own: its four parts are collapsible sections of ONE list, so the
-- Class Guide row stays one row of short names and nothing sits under it but sections. There is no window, page or slash command
-- of its own; Panoply.HunterPet:OpenPage() opens the Hunter Class Guide on the Pet tab.
-- The four sections, in this order, all closed at first (the closed header says the gist), several open at once, never nested:
--   Families         every pet family as a flat list: what it eats, what it can learn, and Open (its plan in Planner).
--   Planner          the family's card (main pet, save or remove the plan, other families), the saved plans, then each ability as a
--                    flat block: one small button per rank (on your pet / learned / still to learn, also said in words), and under
--                    each missing rank the beasts that know it, their level and zone, and whether you can tame them yet. Last, what a
--                    pet trainer sells.
--   To tame          the plan's missing ranks as an ordered list of beasts, grouped by zone (a zone line, then its beasts; beasts our
--                    data has no zone for under "No place known yet"), each with a map marker button (the Waypoints list).
--   Training points  the plan's ranks against the points a pet of a level and loyalty has (a short list).
-- The bar pinned over the list (search, "N of M", the clear X, Expand all / Collapse all, Jump to) and the saved open state are the
-- suite's shared ones (UI/Sections.lua; saved per character as sectionState["hunterpet/pet"]). The search looks inside closed
-- sections too: a family, an ability, a rank, a beast or a zone; an open section then lists only what matched.
-- Skin v3 (UI/Skin.lua): slate cards, hairlines, no glow. Every text is measured before it is placed (Skin.TextHeight), so the layout
-- checker's 1.3x text and the 1024x668 screen hold. Nothing here acts in the game: buttons change the plan or add a waypoint.
local ADDON, Panoply = ...
local P = Panoply.HunterPet
local Skin, C = Panoply.Skin, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- the sections of the Pet tab, in order: { id, title, what it is (the tooltip of its Jump to line and the tests' words) }
P.SECTIONS = {
  { "families", "Families", "Every pet family: what it eats and what it can learn." },
  { "planner", "Planner", "The ranks your pet has, the ranks you have learned, and where to learn the rest." },
  { "tame", "To tame", "The beasts to tame for the missing ranks, by zone, with map markers." },
  { "points", "Training points", "What the plan costs in training points." },
}
P.SECTION_KEY = "hunterpet/pet"      -- where the open sections are saved (sectionState; the 0.9.0 lists per tab sit unused)
P.SCROLL_KEY = "hunterpet/pet"       -- where the list was scrolled, for this play session (Skin.KeepScroll)
P.DEFAULT_W, P.DEFAULT_H = 640, 440
P.PAD = 12

-------------------------------------------------------------------------------
-- Small measured pieces (each returns the y below what it placed)
-------------------------------------------------------------------------------
local function fit(fs, w)
  fs:SetWidth(w)
  local h = ceil(TH(fs, w))
  fs:SetHeight(h)
  return h
end

-- a wrapped text at (x, y) from the parent's top left
local function block(parent, x, y, w, size, color, s, role)
  local fs = Skin.Text(parent, size, color or Skin.colors.ink, nil, role)
  fs:SetText(s or "")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = fit(fs, w)
  return y - h, fs
end

local function label(parent, x, y, w, s)
  local fs = Skin.Label(parent, 10, Skin.colors.inkSoft)
  fs:SetText(s)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = fit(fs, w)
  return y - h - SP.xs, fs
end

local function heading(parent, x, y, w, s, size)
  local fs = Skin.Heading(parent, size or 15, s)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = fit(fs, w)
  return y - h - SP.xs, fs
end

-- buttons left to right from (x, y), wrapping at w; returns the y below them (y itself when there are none)
local function flow(parent, list, x, y, w, minW)
  if #list == 0 then return y end
  local h = Skin.FlowButtons(parent, list, x, y, w, SP.s, minW or 60)
  return y - h
end

local function button(parent, text, fn, tip, body)
  return Skin.Button(parent, text, 80, 24, fn, tip or text, body)
end

-------------------------------------------------------------------------------
-- The words (read by the tests too)
-------------------------------------------------------------------------------
P.STATE_WORD = { pet = "On your pet", learned = "Learned", missing = "Still to learn" }

-- "On your pet: up to rank 3. Learned: 4. Still to learn: 5, 6." for an ability of a family
function P:RankSummary(fam, a)
  local onPet, learned, missing = 0, {}, {}
  local want = self:Want(fam, a.key)
  for _, r in ipairs(a.ranks) do
    local st = self:RankState(fam, a.key, r.r)
    if st == "pet" then onPet = r.r
    elseif st == "learned" then learned[#learned + 1] = r.r
    elseif r.r <= want then missing[#missing + 1] = r.r end
  end
  local parts = {}
  if onPet > 0 then parts[#parts + 1] = ("On your pet: up to rank %d."):format(onPet) end
  if #learned > 0 then parts[#parts + 1] = "Learned: " .. table.concat(learned, ", ") .. "." end
  if #missing > 0 then parts[#parts + 1] = "Still to learn: " .. table.concat(missing, ", ") .. "." end
  if want == 0 then parts[#parts + 1] = "Left out of this plan." end
  if #parts == 0 then parts[1] = "Nothing to learn here." end
  return table.concat(parts, " ")
end

-- "Whiskers, level 23" for the family's pet: the one that is out, or the last one seen
function P:PetLine(fam)
  local pet, live = self:PetOf(fam)
  if not pet then return nil end
  local who = ("%s%s"):format(pet.name or "Your pet", pet.level and (", level " .. pet.level) or "")
  return live and ("Out now: " .. who .. ".") or ("Last seen: " .. who .. ".")
end

function P:CostText(tp)
  if tp == nil then return "cost not known" end
  if tp == 0 then return "free" end
  return tp == 1 and "1 point" or (tp .. " points")
end


-------------------------------------------------------------------------------
-- 0.9.1: the Pet tab is ONE list of collapsible sections under a fixed bar (UI/Sections.lua). Every section starts closed; what the
-- player opens is kept in PanoplySuiteDB.pageState.class.open["pet/..."] (0.9.4; before, per character in sectionState). An open section is a flat list: it never
-- holds another section (no nested accordions).
-------------------------------------------------------------------------------
local function sectionsChanged()
  for _, f in ipairs(P.panels) do
    if f:IsVisible() then f:Refresh() end
  end
end
-- Step 20 fix round: a Kit.SectionList on the Class Guide page ("class"): the kit's chevron header, open or closed remembered in
-- PanoplySuiteDB.pageState.class.open["pet/<section>"] (the per-character sectionState above is read as the default until a section is changed).
P.list = Panoply.Kit.SectionList({ key = P.SECTION_KEY, page = "class", prefix = "pet/", onChange = sectionsChanged, placeholder = "Search families, abilities, beasts and zones" })

-- a hairline between two entries of an open section; returns the y below it
local function rule(parent, x, y, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  Skin.Solid(t, Skin.colors.hairline, 1)
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - SP.s)
  t:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y - SP.s)
  return y - 2 * SP.s - 1
end

-- an entry of an open section: a frame at (x, y) of the section's card that build(row, w) fills from its top and returns the y
-- below what it placed. Returns the y under the entry and the entry's frame.
local function entry(cd, x, y, w, build)
  local row = CreateFrame("Frame", nil, cd)
  row.panoplyGapOK = true
  row:SetPoint("TOPLEFT", cd, "TOPLEFT", x, y)
  row:SetSize(w, 20)
  local yy = build(row, w)
  row:SetHeight(max(1, -yy))
  return y + yy, row
end

local function plural(n, one, many) return n == 1 and one or many end

-------------------------------------------------------------------------------
-- Families
-------------------------------------------------------------------------------
-- the tags under a family's name: main pet, out now, plan saved
local function familyTags(fam)
  local tags = {}
  if fam == P:Main() then tags[#tags + 1] = "Main pet" end
  if P.pet and P.pet.family == fam then tags[#tags + 1] = "Out now" end
  if P:HasPlan(fam) then tags[#tags + 1] = "Plan saved" end
  return tags
end

local function abilityNames(fam)
  local names = {}
  for _, a in ipairs(P:Abilities(fam)) do names[#names + 1] = a.key end
  return names
end

-- the closed header's words: "18 families. Main pet: Cat."
function P:FamiliesSummary()
  local n, main = #self:Families(), self:Main()
  local s = ("%d %s."):format(n, plural(n, "family", "families"))
  if main then return s .. " Main pet: " .. self:FamilyName(main) .. "." end
  return s .. " Pick one to plan its abilities."
end

local function familiesSection(f)
  local fams = P:Families()
  local items = {}
  for i, fam in ipairs(fams) do
    items[i] = table.concat({ P:FamilyName(fam), P:DietText(fam), table.concat(abilityNames(fam), " "), table.concat(familyTags(fam), " ") }, " ")
  end
  return {
    id = "families", title = "Families", summary = P:FamiliesSummary(), items = items,
    body = function(cd, x, y, w, match)
      y = block(cd, x, y, w, 12, Skin.colors.inkSoft,
        "Pick a family to see what it can learn and to plan its abilities. A plan is kept for every family you save one for.")
      local view = P:View()
      local first = true
      for i, fam in ipairs(fams) do
        if not match or match[i] then
          y = first and (y - SP.s) or rule(cd, x, y, w)
          first = false
          local row
          y, row = entry(cd, x, y, w, function(r, rw)
            local yy = 0
            local _, nm = block(r, 0, yy, rw, 13, fam == view and Skin.colors.heading or Skin.colors.text, P:FamilyName(fam), "semi")
            yy = yy - ceil(TH(nm, rw)) - 2
            local tags = familyTags(fam)
            if #tags > 0 then yy = block(r, 0, yy, rw, 11, Skin.colors.accent, table.concat(tags, " - "), "semi") end
            yy = block(r, 0, yy, rw, 12, Skin.colors.ink, "Eats " .. P:DietText(fam) .. ".")
            local names = abilityNames(fam)
            if #names > 0 then yy = block(r, 0, yy, rw, 11, Skin.colors.inkSoft, "Can learn: " .. table.concat(names, ", ") .. ".") end
            local b = button(r, "Open", function() P:SetView(fam) P.list:JumpTo("planner") end, P:FamilyName(fam),
              "Open this family's plan in Planner.")
            b.panoplyFamily = fam
            r.open = b
            return flow(r, { b }, 0, yy - SP.s, rw)
          end)
          row.panoplyFamily = fam
          f.familyRows[fam] = row
        end
      end
      return y
    end,
  }
end

-------------------------------------------------------------------------------
-- Planner
-------------------------------------------------------------------------------
-- one small button per rank; a click ticks or unticks "I have learned this" (the recorder ticks them by itself when the game says so)
local function rankChips(f, parent, fam, a, x, y, w)
  local list = {}
  local want = P:Want(fam, a.key)
  for _, r in ipairs(a.ranks) do
    local st = P:RankState(fam, a.key, r.r)
    local tip = ("%s rank %d"):format(a.key, r.r)
    local body = ("%s. Pet level %d, %s.%s"):format(P.STATE_WORD[st], r.lvl or 0, P:CostText(r.tp),
      st == "pet" and "" or " Click to tick or untick it as learned.")
    local b = Skin.Button(parent, tostring(r.r), 26, 22, function()
      if P:RankState(fam, a.key, r.r) == "pet" then return end
      P:SetLearned(a.key, r.r, not P:Learned(a.key, r.r))
    end, tip, body)
    b.panoplyRank, b.panoplyAbility, b.panoplyRankState = r.r, a.key, st
    local col = st == "pet" and Skin.colors.done or st == "learned" and Skin.colors.accent or (r.r <= want and Skin.colors.text or Skin.colors.dim)
    b.label:SetTextColor(col[1], col[2], col[3], 1)
    if st ~= "missing" then b:SetSelected(true) end
    list[#list + 1] = b
    f.chips[#f.chips + 1] = b
  end
  return flow(parent, list, x, y, w, 26)
end

-- the searchable words of an ability: its name, each rank ("Bite rank 4") and the beasts and zones that teach them
function P:AbilityWords(a)
  local words = { a.key }
  for _, r in ipairs(a.ranks) do
    words[#words + 1] = ("%s rank %d"):format(a.key, r.r)
    for _, t in ipairs(self:Teachers(a.key, r.r)) do words[#words + 1] = t.n .. " " .. self:WhereText(t) end
  end
  return table.concat(words, " ")
end

-- the closed header's words: "Cat. 5 ranks still to learn, in 2 abilities."
function P:PlannerSummary(fam, level)
  local abil, ranks = 0, 0
  for _, a in ipairs(self:Abilities(fam)) do
    local n = #self:NeededRanks(fam, a, level)
    if n > 0 then abil = abil + 1 ranks = ranks + n end
  end
  local s = self:FamilyName(fam) .. ". "
  if ranks == 0 then return s .. "Nothing to learn." end
  return s .. ("%d %s still to learn, in %d %s."):format(ranks, plural(ranks, "rank", "ranks"), abil, plural(abil, "ability", "abilities"))
end

-- one ability as a flat block of the open Planner at (x, y): its name, the rank buttons, the words for them, and (for an ability
-- learned by taming) under each rank still to learn the beasts that teach it. Returns the y below it; the block is f.abilityRows[key].
function P:AbilityBlock(f, cd, fam, a, level, x, y, w)
  local row
  y, row = entry(cd, x, y, w, function(r, rw)
    local yy = 0
    local _, nm = block(r, 0, yy, rw, 13, Skin.colors.text, a.key, "semi")
    yy = yy - ceil(TH(nm, rw)) - 2
    yy = rankChips(f, r, fam, a, 0, yy, rw) - SP.xs
    yy = block(r, 0, yy, rw, 11, Skin.colors.inkSoft, P:RankSummary(fam, a))
    if a.kind == "trainer" then return yy end
    for _, rk in ipairs(P:NeededRanks(fam, a, level)) do
      yy = yy - SP.s
      yy = block(r, 0, yy, rw, 12, Skin.colors.goldBright, ("Rank %d, for a pet of level %d"):format(rk.r, rk.lvl or 0), "semi")
      local teachers = P:Teachers(a.key, rk.r)
      if #teachers == 0 then
        yy = block(r, SP.m, yy - 1, rw - SP.m, 11, Skin.colors.inkSoft,
          "No beast is known to teach this yet. When you tame one that knows it, it is listed here.")
      end
      for i, t in ipairs(teachers) do
        if i > P.TEACHERS_SHOWN then
          yy = block(r, SP.m, yy - 1, rw - SP.m, 11, Skin.colors.inkSoft, ("And %d more under To tame."):format(#teachers - P.TEACHERS_SHOWN))
          break
        end
        local tame, can = P:TameText(t, level)
        yy = block(r, SP.m, yy - 1, rw - SP.m, 12, Skin.colors.ink, ("%s: %s."):format(t.n, P:WhereText(t)))
        yy = block(r, SP.m, yy, rw - SP.m, 11, can and Skin.colors.done or Skin.colors.warn, tame)
        yy = block(r, SP.m, yy, rw - SP.m, 10, Skin.colors.inkSoft, P:SourceText(t))
      end
    end
    return yy
  end)
  row.panoplyAbility = a.key
  f.abilityRows[a.key] = row
  return y
end

local function plannerSection(f, fam, level)
  -- the abilities learned by taming first, then the ones a pet trainer sells; one search item each
  local wild, trainer, items = {}, {}, {}
  for _, a in ipairs(P:Abilities(fam)) do
    if a.kind == "trainer" then trainer[#trainer + 1] = a else wild[#wild + 1] = a end
  end
  local order = {}
  for _, a in ipairs(wild) do order[#order + 1] = a end
  for _, a in ipairs(trainer) do order[#order + 1] = a end
  for i, a in ipairs(order) do items[i] = P:AbilityWords(a) end
  return {
    id = "planner", title = "Planner", summary = P:PlannerSummary(fam, level), items = items,
    body = function(cd, x, y, w, match)
      local main = P:Main()
      -- the family
      y = heading(cd, x, y, w, P:FamilyName(fam), 16)
      local lines = { "Eats " .. P:DietText(fam) .. "." }
      local petLine = P:PetLine(fam)
      if petLine then lines[#lines + 1] = petLine end
      if fam == main then lines[#lines + 1] = "This is your main pet family." end
      y = block(cd, x, y, w, 12, Skin.colors.ink, table.concat(lines, " "))
      local list = {}
      if fam ~= main then
        list[#list + 1] = button(cd, "Make this my main pet", function() P:SetMain(fam) end, "Make this my main pet",
          "The page opens on this family, and its plan is saved.")
      end
      if P:HasPlan(fam) then
        list[#list + 1] = button(cd, "Remove this plan", function() P:RemovePlan(fam) end, "Remove this plan",
          "Forgets the ranks you chose for this family. What you have learned is kept.")
      else
        list[#list + 1] = button(cd, "Save this plan", function() P:SavePlan(fam) end, "Save this plan",
          "Keeps a plan for this family beside your other plans.")
      end
      list[#list + 1] = button(cd, "Other families", function() P.list:JumpTo("families") end, "Other families",
        "Opens Families, the list of every family.")
      f.planButtons = list
      y = flow(cd, list, x, y - SP.s, w)
      -- saved plans (the other families)
      local saved = P:SavedPlans()
      f.savedButtons = {}
      if #saved > 1 or (#saved == 1 and saved[1] ~= fam) then
        y = label(cd, x, y - SP.s, w, "SAVED PLANS")
        local sl = {}
        for _, sf in ipairs(saved) do
          local b = button(cd, P:FamilyName(sf) .. (sf == main and " (main)" or ""), function() P:SetView(sf) end, P:FamilyName(sf), "Open this plan.")
          b.panoplyFamily = sf
          if sf == fam then b:SetSelected(true) end
          sl[#sl + 1] = b
          f.savedButtons[#f.savedButtons + 1] = b
        end
        y = flow(cd, sl, x, y, w)
      end
      y = block(cd, x, y - SP.s, w, 11, Skin.colors.inkSoft, P.IsHunter()
        and "The recorder ticks a rank when the game says you learned it. You can also click a rank to tick it yourself."
        or "Log in on a hunter to record what you learn. You can click a rank to tick it yourself.")
      -- the abilities learned by taming, each a flat block (a search lists only the ones it matched)
      for i, a in ipairs(wild) do
        if not match or match[i] then
          y = rule(cd, x, y, w)
          y = P:AbilityBlock(f, cd, fam, a, level, x, y, w)
        end
      end
      -- the ones a pet trainer sells, together
      local shownTrainer = {}
      for k, a in ipairs(trainer) do
        if not match or match[#wild + k] then shownTrainer[#shownTrainer + 1] = a end
      end
      if #shownTrainer > 0 then
        y = rule(cd, x, y, w)
        y = label(cd, x, y, w, "FROM A PET TRAINER")
        for k, a in ipairs(shownTrainer) do
          if k > 1 then y = y - SP.s end
          y = P:AbilityBlock(f, cd, fam, a, level, x, y, w)
        end
        if P:KnowsPetTrainers() then
          local b = button(cd, "Go to the nearest pet trainer", function() P:GoToPetTrainer() end, "Go to the nearest pet trainer",
            "Adds the nearest pet trainer on your map as your next waypoint.")
          f.trainerButton = b
          y = flow(cd, { b }, x, y - SP.s, w)
        end
      end
      return y
    end,
  }
end

-------------------------------------------------------------------------------
-- To tame
-------------------------------------------------------------------------------
P.NO_ZONE = "No place known yet"   -- the group of beasts our data has no zone for (never a made-up zone)

-- one beast of the To tame list at (x, y): its number in the whole list, where, what it teaches, whether you can tame it yet, and
-- its buttons. Returns the y below it; the row is f.tameRows[i] (row.mark / .here / .other / .done).
function P:TameRow(f, cd, fam, e, i, level, x, y, w)
  local row
  y, row = entry(cd, x, y, w, function(r, rw)
    local yy = 0
    local _, nm = block(r, 0, yy, rw, 13, Skin.colors.text, ("%d. %s"):format(i, e.n), "semi")
    yy = yy - ceil(TH(nm, rw)) - 2
    yy = block(r, 0, yy, rw, 12, Skin.colors.ink, P:WhereText(e.t, true) .. ". Teaches " .. P.RanksText(e.teaches) .. ".")
    local text, can = P:TameText(e.t, level)
    yy = block(r, 0, yy, rw, 11, can and Skin.colors.done or Skin.colors.warn, text)
    yy = block(r, 0, yy, rw, 10, Skin.colors.inkSoft, P:SourceText(e.t))
    local list = {}
    local spot, count = P:NearestSpot(e.n)
    if spot then
      r.mark = button(r, "Map marker", function() P:Mark(e) end, "Map marker",
        ("Adds a waypoint where %s is found (%d known %s) and points the arrow at it."):format(e.n, count, count == 1 and "place" or "places"))
      list[#list + 1] = r.mark
    else
      r.here = button(r, "Mark where I stand", function() P:MarkHere(e) end, "Mark where I stand",
        "Panoply Suite has no place for this beast yet. When you have found it, this keeps the spot so a map marker can bring you back.")
      list[#list + 1] = r.here
    end
    if e.others > 0 then
      r.other = button(r, "Other beast", function() P:NextChoice(fam, e) end, "Other beast",
        ("%d more %s this rank. Click to plan with the next one."):format(e.others, e.others == 1 and "beast teaches" or "beasts teach"))
      list[#list + 1] = r.other
    end
    r.done = button(r, "Learned it", function() P:MarkLearned(e) end, "Learned it", "Ticks these ranks as learned and takes the beast off the list.")
    list[#list + 1] = r.done
    return flow(r, list, 0, yy - SP.s, rw)
  end)
  row.panoplyEntry = e
  f.tameRows[i] = row
  return y
end

-- the beasts of a To tame list by zone, zones in the order of their lowest beast: { { zone, entries = { { i, e } } } }
function P:TameGroups(tame)
  local groups, byZone = {}, {}
  for i, e in ipairs(tame.list) do
    local z = (e.t and e.t.z and e.t.z ~= "") and e.t.z or self.NO_ZONE
    local g = byZone[z]
    if not g then g = { zone = z, entries = {} } byZone[z] = g groups[#groups + 1] = g end
    g.entries[#g.entries + 1] = { i = i, e = e }
  end
  return groups
end

-- "4 to tame, level 32-40" for a group of beasts
local function groupWords(entries)
  local lo, hi
  for _, it in ipairs(entries) do
    local t = it.e.t
    if t and t.lo and t.lo > 0 then lo = min(lo or t.lo, t.lo) hi = max(hi or 0, t.hi or t.lo) end
  end
  return ("%d to tame"):format(#entries) .. (lo and (lo == hi and (", level " .. lo) or (", level " .. lo .. "-" .. hi)) or "")
end

-- the closed header's words: "6 beasts to tame in 3 zones, level 10-30."
function P:TameSummary(tame, groups)
  local n = #tame.list
  if n == 0 then
    if #tame.unknown > 0 then return "No beast known yet for the ranks this plan still needs." end
    return "Nothing to tame."
  end
  local zones = 0
  for _, g in ipairs(groups) do if g.zone ~= self.NO_ZONE then zones = zones + 1 end end
  local all = {}
  for _, g in ipairs(groups) do for _, it in ipairs(g.entries) do all[#all + 1] = it end end
  local s = ("%d %s to tame"):format(n, plural(n, "beast", "beasts"))
  if zones > 0 then s = s .. (" in %d %s"):format(zones, plural(zones, "zone", "zones")) end
  local lv = groupWords(all):match(", level .*$")
  return s .. (lv or "") .. "."
end

local function tameSection(f, fam, level)
  local tame = P:ToTame(fam)
  local groups = P:TameGroups(tame)
  local items = {}
  for i, e in ipairs(tame.list) do items[i] = table.concat({ e.n, P:WhereText(e.t), P.RanksText(e.teaches) }, " ") end
  return {
    id = "tame", title = "To tame", summary = P:TameSummary(tame, groups), items = items,
    body = function(cd, x, y, w, match)
      y = heading(cd, x, y, w, "To tame for a " .. P:FamilyName(fam), 15)
      local n = #tame.list
      local line
      if n == 0 and #tame.unknown == 0 then
        line = "Nothing to tame: every rank this plan wants is learned or on your pet."
      elseif n == 0 then
        line = "No beast is known yet for the ranks this plan still needs."
      else
        line = ("%d %s to tame, by zone, lowest level first. Stable your own pet first: a hunter can only have one pet out."):format(n, plural(n, "beast", "beasts"))
      end
      y = block(cd, x, y, w, 12, Skin.colors.ink, line)
      local list = {}
      if n > 0 then
        list[#list + 1] = button(cd, "Mark them all on my map", function() P:MarkAll(fam) end, "Mark them all on my map",
          "Adds a waypoint for every beast below that has a known place, in this order. The arrow follows the first.")
      end
      if Panoply.Waypoints and Panoply.Waypoints.active then
        list[#list + 1] = button(cd, "Open the waypoint list", function() Panoply.Waypoints:Toggle() end, "Open the waypoint list", "Your waypoints; the arrow follows the first.")
      end
      f.tameButtons = list
      if #list > 0 then y = flow(cd, list, x, y - SP.s, w) end
      -- the beasts, grouped by zone: the zone's line (its name, how many and their levels), then its beasts, each numbered in the
      -- whole list's order. A plain line, not a section: an open section holds no other section.
      for _, g in ipairs(groups) do
        local shownE = {}
        for _, it in ipairs(g.entries) do if not match or match[it.i] then shownE[#shownE + 1] = it end end
        if #shownE > 0 then
          y = rule(cd, x, y, w) - SP.xs
          local zy, zt = block(cd, x, y, w, 13, Skin.colors.heading, g.zone, "semi")
          local zy2, zs = block(cd, x, zy, w, 11, Skin.colors.inkSoft, groupWords(g.entries))
          f.tameZones[g.zone] = { title = zt, summary = zs }
          y = zy2
          for k, it in ipairs(shownE) do
            y = y - (k == 1 and SP.s or 2 * SP.s)
            y = P:TameRow(f, cd, fam, it.e, it.i, level, x + SP.m, y, w - SP.m)
          end
        end
      end
      if #tame.unknown > 0 and not match then
        y = rule(cd, x, y, w)
        y = label(cd, x, y, w, "NO BEAST KNOWN YET")
        y = block(cd, x, y, w, 12, Skin.colors.ink, P.RanksText(tame.unknown) .. ".")
        y = block(cd, x, y - 2, w, 11, Skin.colors.inkSoft, "When you tame a beast that knows one of these, the recorder lists it here.")
      end
      if #tame.trainer > 0 and not match then
        y = rule(cd, x, y, w)
        y = label(cd, x, y, w, "FROM A PET TRAINER")
        y = block(cd, x, y, w, 12, Skin.colors.ink, P.RanksText(tame.trainer) .. ".")
        if P:KnowsPetTrainers() then
          local b = button(cd, "Go to the nearest pet trainer", function() P:GoToPetTrainer() end, "Go to the nearest pet trainer",
            "Adds the nearest pet trainer on your map as your next waypoint.")
          f.trainerButton = b
          y = flow(cd, { b }, x, y - SP.s, w)
        end
      end
      -- the tames this account has recorded (PetLog.lua): the switch, how many, and the newest few
      if not match and P.PetLog then
        local PL = P.PetLog
        local on = PL:IsOn()
        y = rule(cd, x, y, w)
        y = label(cd, x, y, w, "RECORDED TAMES")
        local sw = button(cd, on and "Recording tames: on" or "Recording tames: off", function() PL:SetOn(not PL:IsOn()) end, "Recording tames",
          "Writes down each tame and each new ability rank your pet shows, with what the game itself reports, in a file of its own on this computer. It only watches.")
        sw:SetSelected(on)
        f.petLogSwitch = sw
        y = flow(cd, { sw }, x, y, w)
        local tames, ranks = PL:Counts()
        local words = on and "Recording is on: it only watches, and nothing is sent anywhere."
          or "Recording is off: nothing new is written down. What is recorded stays."
        if tames == 0 then
          words = words .. " No tame is recorded yet; when you tame a beast it is written down here."
        else
          words = words .. (" %d %s recorded%s (the newest %d entries are kept)."):format(tames, plural(tames, "tame", "tames"),
            ranks > 0 and (" and %d new %s seen on a pet"):format(ranks, plural(ranks, "rank", "ranks")) or "", PL.CAP)
        end
        y = block(cd, x, y - SP.s, w, 11, Skin.colors.inkSoft, words)
        for _, e in ipairs(PL:Recent(PL.SHOW)) do
          local ry, fs = block(cd, x, y - 2, w, 11, Skin.colors.ink, PL.Words(e))
          f.petLogRows[#f.petLogRows + 1] = fs
          y = ry
        end
      end
      return y
    end,
  }
end

-------------------------------------------------------------------------------
-- Training points
-------------------------------------------------------------------------------
-- "[-] value [+]" at (x, y); returns the y below and the width used
local function stepper(parent, x, y, text, onDown, onUp, canDown, canUp, tipDown, tipUp, valueW)
  local S = 20
  local dn = Skin.IconButton(parent, "-", S, onDown, tipDown)
  dn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  dn:SetEnabledLook(canDown and true or false)
  local v = Skin.Text(parent, 12, Skin.colors.text, nil, "semi")
  v:SetText(text)
  if v.SetJustifyH then v:SetJustifyH("CENTER") end
  local vw = max(valueW or 0, ceil(TW(v)) + 4)
  v:SetWidth(vw)
  local vh = ceil(TH(v, vw))
  v:SetHeight(vh)
  v:SetPoint("TOPLEFT", parent, "TOPLEFT", x + S + SP.s, y - max(0, floor((S - vh) / 2)))
  local up = Skin.IconButton(parent, "+", S, onUp, tipUp)
  up:SetPoint("TOPLEFT", parent, "TOPLEFT", x + S + SP.s + vw + SP.s, y)
  up:SetEnabledLook(canUp and true or false)
  return y - max(S, vh), 2 * S + 2 * SP.s + vw, dn, up, v
end

-- the closed header's words: "84 of 150 points used, 66 left."
function P:PointsSummary(B)
  if B.left < 0 then return ("%d of %d points used: over by %d."):format(B.spent, B.budget, -B.left) end
  return ("%d of %d points used, %d left."):format(B.spent, B.budget, B.left)
end

local function pointsSection(f, fam)
  local B = P:Budget(fam)
  local items = {}
  for i, row in ipairs(B.rows) do items[i] = row.a.key end
  return {
    id = "points", title = "Training points", summary = P:PointsSummary(B), items = items,
    body = function(cd, x, y, w, match)
      -- the pet the plan is for
      y = heading(cd, x, y, w, "Training points for a " .. P:FamilyName(fam), 15)
      local half = floor((w - SP.m) / 2)
      local ly = label(cd, x, y, half, "PET LEVEL")
      local ry = label(cd, x + half + SP.m, y, half, "LOYALTY LEVEL")
      y = min(ly, ry)
      local y1, _, ldn, lup = stepper(cd, x, y, tostring(B.level), function() P:SetPlanLevel(fam, B.level - 1) end,
        function() P:SetPlanLevel(fam, B.level + 1) end, B.level > 1, B.level < P.MAX_LEVEL, "One level lower", "One level higher", 30)
      local y2, _, ydn, yup = stepper(cd, x + half + SP.m, y, tostring(B.loyalty), function() P:SetPlanLoyalty(fam, B.loyalty - 1) end,
        function() P:SetPlanLoyalty(fam, B.loyalty + 1) end, B.loyalty > 1, B.loyalty < P.MAX_LOYALTY, "One loyalty level lower", "One loyalty level higher", 30)
      f.levelDown, f.levelUp, f.loyaltyDown, f.loyaltyUp = ldn, lup, ydn, yup
      y = min(y1, y2) - SP.s
      local over = B.left < 0
      local _, big = block(cd, x, y, w, 13, over and Skin.colors.warn or Skin.colors.goldBright,
        over and ("%d of %d points used: over by %d. Lower a rank."):format(B.spent, B.budget, -B.left)
          or ("%d of %d points used, %d left."):format(B.spent, B.budget, B.left), "semi")
      f.pointsTotal = big
      y = y - ceil(TH(big, w)) - 2
      local notes = { ("A pet of level %d at loyalty level %d has %d points."):format(B.level, B.loyalty, B.budget) }
      local pet, live = P:PetOf(fam)
      if live and pet.points and pet.spent then
        notes[#notes + 1] = ("%s has %d points and has spent %d."):format(pet.name, pet.points, pet.spent)
      end
      if B.unknown > 0 then notes[#notes + 1] = ("%d %s no known cost and %s not counted."):format(B.unknown, B.unknown == 1 and "rank has" or "ranks have", B.unknown == 1 and "is" or "are") end
      y = block(cd, x, y, w, 11, Skin.colors.inkSoft, table.concat(notes, " "))
      -- one line per ability
      y = rule(cd, x, y, w)
      local stepW = 2 * 20 + 2 * SP.s + 96
      local nameW = max(80, w - stepW - SP.m)
      for i, row in ipairs(B.rows) do
        if not match or match[i] then
          local a = row.a
          local cap = P.MaxRankAt(a, B.level)
          local value = row.rank == 0 and "Left out" or ("Rank %d of %d"):format(row.rank, a.max)
          local words = row.rank == 0 and (cap < a.first and ("Rank %d needs a pet of level %d."):format(a.first, a.ranks[1].lvl or 0) or "Not in this plan.")
            or (P:CostText(row.tp):gsub("^%l", string.upper) .. (row.capped and (". Rank %d needs a higher pet level."):format(row.rank + 1) or "."))
          local _, nm = block(cd, x, y, nameW, 12, row.rank == 0 and Skin.colors.inkSoft or Skin.colors.text, a.key, "semi")
          local nh = ceil(TH(nm, nameW))
          local _, sub = block(cd, x, y - nh, nameW, 11, Skin.colors.inkSoft, words)
          local sh = ceil(TH(sub, nameW))
          local sy, _, dn, up, val = stepper(cd, x + nameW + SP.m, y, value, function() P:StepWant(fam, a.key, -1) end,
            function() P:StepWant(fam, a.key, 1) end, row.rank > 0, (row.rank == 0 and a.first or row.rank + 1) <= cap and row.rank < a.max,
            "One rank lower", "One rank higher", 96)
          f.pointRows[a.key] = { down = dn, up = up, value = val, name = nm, sub = sub, row = row }
          y = min(y - nh - sh, sy) - SP.s
        end
      end
      -- WoW Forever pet talents: said only when the game hands a tree over (see Core.lua)
      local tree = P:PetTalentTree()
      if tree and not match then
        y = rule(cd, x, y, w)
        y = label(cd, x, y, w, "PET TALENTS")
        local done = false
        if type(P.TalentBuilder) == "function" then
          local ok, ny = pcall(P.TalentBuilder, cd, tree, x, y, w)
          if ok and type(ny) == "number" then y = ny done = true end
        end
        if not done then
          y = block(cd, x, y, w, 12, Skin.colors.ink, "This game also gives your pet a talent tree. Panoply Suite does not plan it yet; the points above are the classic training points.")
        end
      end
      return y
    end,
  }
end

-- the four sections of the Pet tab for the family that shows
function P:SectionList(f)
  local fam = self:View()
  local level = self.HunterLevel()
  return { familiesSection(f), plannerSection(f, fam, level), tameSection(f, fam, level), pointsSection(f, fam) }
end

-------------------------------------------------------------------------------
-- The panel
-------------------------------------------------------------------------------
-- the size the panel has to fill: what the caller gave, else the parent's own (the class page's host carries width and height),
-- else a default
local function sizeOf(f)
  local p = f.host
  local w = f.givenW or (type(p.width) == "number" and p.width) or nil
  local h = f.givenH or (type(p.height) == "number" and p.height) or nil
  if not w then local pw = p.GetWidth and p:GetWidth() or 0 w = pw >= 200 and pw or P.DEFAULT_W end
  if not h then local ph = p.GetHeight and p:GetHeight() or 0 h = ph >= 160 and ph or P.DEFAULT_H end
  return w, h
end

function P:LayoutPanel(f)
  local W, H = sizeOf(f)
  f:SetSize(W, H)
  local area = f.area
  local S = P.list
  -- the list is built again only when something it shows changed (a section opened or closed, a search, the plan, the pet)
  local sig = table.concat({ W, H, P.rev, P:View() or "", P.HunterLevel(), P.Client(), S.version }, "|")
  local built = false
  if f.sig ~= sig then
    local keep = area.GetVerticalScroll and area:GetVerticalScroll() or 0
    f.sig = sig
    if f.content then f.content:Hide() end
    local c = CreateFrame("Frame", nil, area.content)
    local CW = W - 14
    c:SetPoint("TOPLEFT", area.content, "TOPLEFT", 0, 0)
    c:SetSize(CW, 10)
    f.content = c
    f.chips, f.familyRows, f.abilityRows, f.tameRows, f.tameZones, f.pointRows = {}, {}, {}, {}, {}, {}
    f.planButtons, f.savedButtons, f.tameButtons, f.trainerButton, f.pointsTotal = {}, {}, {}, nil, nil
    f.petLogSwitch, f.petLogRows = nil, {}
    S:SetList(P:SectionList(f))
    local h = -S:Render(c, 0, 0, CW)
    f.sections = S.cards
    c:SetHeight(max(10, h))
    f.contentH = h
    f.keep = keep
    built = true
  end
  -- the bar pinned at the top; the list scrolls under it and the bar stays
  local bar = f.bar
  if not bar then bar = Skin.FindBar(f, S) f.bar = bar end
  bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  local top = bar:Layout(W - 14) + SP.s
  bar:Show()
  local viewH = max(60, H - top)
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
  area:SetSize(W, viewH)
  if built then
    area:SetContentHeight(f.contentH)
    local jumpY = S:TakeJump()
    if jumpY then
      area:ScrollTo(-jumpY)                                 -- Jump to (and Open, Other families): the section's header at the top
    elseif S:TakeReset() then
      area:ScrollTo(0)                                      -- a new search: its results from the top
    else
      area:ScrollTo(min(f.keep or 0, area:MaxScroll()))     -- the same list built again: where it was
    end
  end
  area:UpdateBar()
  return top + (f.contentH or 0)
end

-- The one door. parent: the frame to fill. w, h (optional): the size to lay out for, when the parent's own is not known yet.
-- Returns the panel: panel:Refresh() lays it out again, panel:Layout(w, h) does so for a new size and returns the height its
-- content needs, panel:ShowSection(key) opens one of "families", "planner", "tame", "points" and scrolls to it. One panel per parent.
function P:BuildPanel(parent, w, h)
  if type(parent) ~= "table" then return nil end
  if parent.panoplyHunterPet then
    local f = parent.panoplyHunterPet
    if w or h then f.givenW, f.givenH = w or f.givenW, h or f.givenH end
    f:Show()
    f:Refresh()
    return f
  end
  local f = CreateFrame("Frame", nil, parent)
  f.host, f.givenW, f.givenH = parent, w, h
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  f.area = Skin.ScrollArea(f)
  f.panoplyFitsView = true          -- the class page gives this panel the height that shows (ClassPages/Page.lua)
  function f:Refresh() return P:LayoutPanel(self) end
  function f:Layout(nw, nh)
    if nw or nh then self.givenW, self.givenH = nw or self.givenW, nh or self.givenH end
    return P:LayoutPanel(self)
  end
  function f:ShowSection(key)
    self:Refresh()
    if P.list.byId[key] then P.list:JumpTo(key) end
    return self:Refresh()
  end
  -- where the list was scrolled is kept while the Class Guide shows another tab, and put back when the Pet tab shows again
  f:SetScript("OnHide", function(self) Skin.KeepScroll(P.SCROLL_KEY, self.area) end)
  f:SetScript("OnShow", function(self)
    self:Refresh()
    if Skin.scrollMemo[P.SCROLL_KEY] then Skin.RecallScroll(P.SCROLL_KEY, self.area) self.area:UpdateBar() end
  end)
  parent.panoplyHunterPet = f
  P.panels[#P.panels + 1] = f
  f:Refresh()
  return f
end

-- a change of the plan, the pet or what is learned: every panel on screen lays itself out again
Panoply:Listen("HUNTERPET_CHANGED", function()
  for _, f in ipairs(P.panels) do
    if f:IsVisible() then f:Refresh() end
  end
end)

-------------------------------------------------------------------------------
-- 0.9.1: the door. The pet is the Pet tab of the Hunter's Class Guide (Modules/ClassPages); this opens the menu there, for anyone
-- (a Mage can read the Hunter page too). Returns the class page, or nil when the menu or the class pages are not in this build.
-------------------------------------------------------------------------------
function P:OpenPage()
  local CP = Panoply.ClassPages
  if not (CP and CP.Open) then return nil end
  return CP:Open("HUNTER", "pet")
end
