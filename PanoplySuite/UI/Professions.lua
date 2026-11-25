-- Panoply Suite Professions page: the view model (pure data; UI/ProfPage.lua draws it, the tests and the previews read it).
-- 0.9.5 phase 4B (docs/specs/page-redesigns-v1.md section 2, queue item 2): a list of your professions beside one profession's detail.
-- Each profession has a status chip (Craft / Gather, Train now, Blocked, Maxed), a Next card with exactly one action (the most urgent
-- blocker wins: Train, then Blueprint needed, then Reputation or Favor needed, then Craft or gather), and the tabs its type has:
--   crafting (with Cooking and First Aid)  Steps · Shopping · Recipes · Camp · Together
--   gathering (Herbalism, Mining, Skinning) Where · Scarce · Camp · Together
--   Fishing                                 Where · Camp
-- Camp, the trade camp, Blueprints, Favor and the Legacy marks are WoW Forever only; on Classic Era they are not shown.
-- Plans are per profession (Engine/ProfPlans.lua).
local ADDON, Panoply = ...
local PUI = { target = 300, page = "Steps" }
Panoply.ProfUI = PUI
local Skin, PD, U, C = Panoply.Skin, Panoply.ProfData, Panoply.Util, Panoply.Compat

PUI.PRIMARY = { "Mining", "Herbalism", "Skinning", "Tailoring", "Leatherworking", "Blacksmithing", "Engineering", "Alchemy", "Enchanting" }
PUI.SECONDARY = { "First Aid", "Cooking", "Fishing" }
local isSecondary = {}
for _, n in ipairs(PUI.SECONDARY) do isSecondary[n] = true end
PUI.IsSecondary = function(n) return isSecondary[n] or false end
-- every tab any profession can have, in the order a crafting profession shows them (a profession shows those of its type: PUI:TabsFor)
PUI.PAGES = { "Steps", "Shopping", "Recipes", "Where", "Scarce", "Camp", "Together" }
PUI.PAGE_TIPS = {
  Steps = "Every stage of the plan from your skill to 300, with trainer visits. Ticked when done.",
  Shopping = "What you still need for the whole plan (counting bags, bank and mail) and where to buy or gather it.",
  Recipes = "Every recipe of this profession, learned or not, and where each one comes from. Tools and specialization too.",
  Where = "Where to gather for your skill range. The map button shows the place on your map.",
  Scarce = "Scarce materials you gathered: what the gather log counted since 0.9.5.",
  Camp = "Your camp objects for this profession: known, owned or missing, where the Blueprint comes from, and the cooldown.",
  Together = "How your professions and your partner's help each other.",
}
-- tabs saved by 0.9.4 and older that are called something else now
PUI.OLD_TABS = { ["Trainers & recipes"] = "Recipes" }
PUI.GATHERING = { Herbalism = true, Mining = true, Skinning = true }

-- 0.9.1: no paging any more (an open profession lists all its rows; the page scrolls)
local function money(c) return U.FormatMoney(c or 0) end
local function mapName(m) return (m and C.MapName(m)) or "?" end
local function at(spot) return spot and ((spot.name and (spot.name .. ", ") or "") .. mapName(spot.map)) or "" end
local function tContains_(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
local function PR() return Panoply.Professions end

-------------------------------------------------------------------------------
-- 0.9.6 phase M (Nov 17 2026): every trainer this page shows or points to (the Steps tab's trainer visits, the trainer rows,
-- the Next card's line and its spot) comes from phase L's own-side lookup (Engine/ProfGuide.lua G:FriendlyNearest): the nearest
-- trainer of your side who teaches that rank or recipe, in this zone, then your capitals, then anywhere. Never the other side's,
-- never one whose side is unknown; a neutral one is fine. None known: ask a city guard (phase L's wording), with no spot.
-------------------------------------------------------------------------------
PUI.TRAINER_GUARD = "Ask a city guard for a trainer"   -- PLACEHOLDER COPY (Marketing)
local function PG() return Panoply.ProfGuide end
-- phase L's longer line: "No trainer of your side is known nearby. City guards mark the trainer on your map."
function PUI.GuardLine()
  local G = PG()
  return G and G.TRAINER_COPY and G.TRAINER_COPY.guard or PUI.TRAINER_GUARD
end
local function trainerSource(src) return src == nil or src == "trainer" end
-- the profession's own rank record for a plan's training entry (the entry is a copy without the both-sides lists)
local function rankOf(name, t)
  local ranks = PD[name or ""] and PR():Ranks(PD[name]) or {}
  if t.rankIndex and ranks[t.rankIndex] and ranks[t.rankIndex].name == t.rank then return ranks[t.rankIndex] end
  for _, rk in ipairs(ranks) do if rk.name == t.rank then return rk end end
  return t
end
-- where a rank is trained, for this character: spot (nil when none of your side is known), where ("zone" | "city" | "near" |
-- "guard"), and the rank quest's title (each side may have its own quest; the same choice as ProfGuide:TrainStep)
function PUI:RankSpot(name, rk, pos)
  local G = PG()
  if not (rk and G and G.FriendlyNearest) then return nil, "guard" end
  pos = pos or (Panoply.State and Panoply.State.pos)
  if rk.source == "quest" and rk.quest then
    local giver, where = G:FriendlyNearest(rk.npcs, pos)
    local title = rk.questTitle
    for _, q in ipairs(rk.allQuests or {}) do
      local g, w = G:FriendlyNearest(q.npcs, pos)
      if g and (not giver or g.t < giver.t) then giver, where, title = g, w, q.questTitle or title end
    end
    return giver, giver and where or "guard", title
  end
  -- the Apprentice rank: on WoW Forever also the trainers only Forever has (they teach only the first rank)
  local ranks = PD[name or ""] and PR():Ranks(PD[name]) or {}
  local extra = (ranks[1] == rk and trainerSource(rk.source) and G.ForeverTrainers) and G:ForeverTrainers(name) or nil
  return G:FriendlyNearest(rk.allNpcs or rk.npcs, pos, extra)
end
-- a recipe taught by a trainer: the nearest trainer of your side who teaches it (nil, "guard" when none is known)
function PUI:RecipeTrainer(r, pos)
  local G = PG()
  if not (r and G and G.FriendlyNearest) then return nil, "guard" end
  return G:FriendlyNearest(r.allNpcs or r.npcs, pos or (Panoply.State and Panoply.State.pos))
end

-------------------------------------------------------------------------------
-- 0.9.6 phase O (Nov 17 2026): every vendor this page shows or points to (the Shopping tab's vendor rows and its "Where to buy"
-- rows, the trainer rows' vendor recipes, the Recipes tab's "Vendor:" source) comes from phase N's own-side vendor data (items'
-- allVendors, vendor recipes' allNpcs) through phase L's G:FriendlyNearest: this zone, then your capitals, then anywhere. Never the
-- other side's, never one whose side is unknown; a neutral one is fine. None known: ask a city guard (phase N's G.VENDOR_COPY
-- wording), with no spot. "Limited stock" is the chosen vendor's own. A recipe only the other side's vendors sell stays a drop for
-- you (the guide's rule, ProfGuide:RecipeSteps).
-------------------------------------------------------------------------------
PUI.VENDOR_GUARD = "Ask a city guard for a trade goods vendor"   -- PLACEHOLDER COPY (Marketing) (phase N's wording)
PUI.RECIPE_VENDOR_GUARD = "Ask a city guard for a %s supplies vendor"   -- PLACEHOLDER COPY (Marketing) (phase N's wording)
-- phase N's longer line: "No vendor of your side is known nearby. City guards mark vendors on your map; ..."
function PUI.VendorGuardLine()
  local G = PG()
  return G and G.VENDOR_COPY and G.VENDOR_COPY.guard or PUI.VENDOR_GUARD
end
local function lowerFirst(text) return (text:gsub("^%u", string.lower)) end
-- does the chosen vendor have limited stock? (the same rule as ProfGuide's limitedAt)
local function limitedAt(v, all, list, old)
  if not all then return old and true or false end
  if not v then return false end
  for _, id in ipairs(list or {}) do if id == v.npc then return true end end
  return false
end
-- an item's nearest vendor of your side: spot, where ("zone" | "city" | "near" | "guard"; "none" when no vendor sells it), limited
function PUI:ItemVendor(id, pos)
  local it = PD.Item(id) or {}
  local ids = it.allVendors or it.vendors
  if not (ids and #ids > 0) then return nil, "none", false end
  local G = PG()
  if not (G and G.FriendlyNearest) then return nil, "guard", false end
  local v, where = G:FriendlyNearest(ids, pos or (Panoply.State and Panoply.State.pos))
  return v, where, limitedAt(v, it.allVendors, it.limitedVendors, it.limited)
end
-- a recipe's nearest vendor of your side (or, for other sources, its NPC of your side): spot, where, limited
function PUI:RecipeVendor(r, pos)
  local ids = r and (r.allNpcs or r.npcs)
  if not (ids and #ids > 0) then return nil, "none", false end
  local G = PG()
  if not (G and G.FriendlyNearest) then return nil, "guard", false end
  local v, where = G:FriendlyNearest(ids, pos or (Panoply.State and Panoply.State.pos))
  return v, where, limitedAt(v, r.allNpcs, r.limitedNpcs, r.limited)
end
-- is this recipe bought from a vendor, for you? Vendor recipes; and a "drop" recipe a vendor of your side sells
function PUI:BoughtFromVendor(r, pos)
  if not r then return false end
  if r.source == "vendor" then return true end
  return r.source == "drop" and r.allNpcs ~= nil and (self:RecipeVendor(r, pos)) ~= nil
end

function PUI:Chosen()
  local pr = Panoply.cdb and Panoply.cdb.professions or {}
  local out = {}
  for _, n in ipairs(pr.primary or {}) do out[#out + 1] = n end
  for _, n in ipairs(pr.secondary or {}) do out[#out + 1] = n end
  return out
end
-- 0.9.5: a profession's own plan (Engine/ProfPlans.lua); with no name, the old global choice (where a profession's plan starts)
function PUI:Mode(name)
  local PP = Panoply.ProfPlans
  if name and PP then return PP:From(name) end
  return (Panoply.cdb and Panoply.cdb.professions and Panoply.cdb.professions.mode) or (Panoply.db and Panoply.db.profPlanFrom) or "current"
end
function PUI:Strategy(name)
  local PP = Panoply.ProfPlans
  if name and PP then return PP:Strategy(name) end
  return (Panoply.db and Panoply.db.profStrategy) or "cheapest"
end

-- Plan for the tab: the guide's cached plan ("from my skill") or a fresh one from 1 ("from scratch").
function PUI:PlanFor(name)
  if not PD[name] or not PD[name].ranks then return nil, "Detailed plan for " .. name .. " is coming in a later version." end
  local strategy = self:Strategy(name)
  if self:Mode(name) == "scratch" then
    local key = name .. "|" .. strategy .. "|" .. (Panoply.State.level or 1)
    self.scratch = self.scratch or {}
    local c = self.scratch[key]
    if not c then c = { PR():PlanForPlayer(name, "scratch", self.target, { strategy = strategy }) }; self.scratch[key] = c end
    return c[1], c[2]
  end
  local G = Panoply.ProfGuide
  local plan = G and G:PlanFor(name)
  if plan then return plan end
  return PR():PlanForPlayer(name, "current", self.target, { strategy = strategy })
end

-- Next cap and the rank that raises it.
local function nextCap(prof, rank, max)
  for _, rk in ipairs(PR():Ranks(prof)) do
    if (max or 0) < rk.max then return rk end
  end
  return nil
end

-------------------------------------------------------------------------------
-- View model (pure data; the frames below only draw it; the mockups dump it)
-------------------------------------------------------------------------------
local function row(t) return t end
local function head(text) return { text = text, header = true } end

function PUI:ShoppingRows(name, plan, v)
  local rows = {}
  local pos = Panoply.State.pos
  -- 0.9.5 phase 4G (spec 01 section 8): the costs read the Auctions page's scan and say how old it is; each line opens that item there
  local AV = Panoply.Auctions and Panoply.Auctions.View
  local aucOn = AV and AV.OpenItem and Panoply.Modules and Panoply.Modules:IsOn("auctions")
  local scanAge = aucOn and AV.ScanAge and AV.ScanAge() or nil
  local R_ = Panoply.Auctions and Panoply.Auctions.Record
  local function ago(sec) return R_ and R_.Ago and R_.Ago(sec) or (math.floor(sec / 3600) .. " hours ago") end
  if plan.kind == "crafting" then
    local h = head("Materials for the whole plan (bags + bank + mail)")
    if aucOn then h.right = scanAge and ("Auction prices: scanned " .. ago(scanAge)) or "No auction scan yet" end
    rows[#rows + 1] = h
    local ids = U.Keys(plan.shopping)
    table.sort(ids, function(a, b) return (plan.shopping[a].need or 0) > (plan.shopping[b].need or 0) end)
    local total = 0
    for _, id in ipairs(ids) do
      local s = plan.shopping[id]
      local have, bagBank, mail = PR():Have(id)
      local bags = PR():HaveInBags(id)
      local get = math.max(0, s.need - have)
      local how, spot, vguard, ahGuard
      if get == 0 then how = "you have enough"
      elseif s.how == "mine" then
        how = "mine it"; local z = s.farm and s.farm[1]
      elseif s.how == "vendor" then
        -- 0.9.6 phase O: a vendor of your side (none known: ask a city guard, no spot)
        local vs = self:ItemVendor(s.id or id, pos); spot = vs
        vguard = not vs
        how = vs and ("vendor: " .. at(vs)) or lowerFirst(PUI.VENDOR_GUARD)
      -- 0.9.6 phase P: an auctioneer of your side or a neutral one (PD.NearestAuctioneer); none known: ask a city guard (no spot)
      elseif s.disenchant then spot = PD.NearestAuctioneer(pos); how = spot and "disenchant greens or Auction House" or ("disenchant greens or " .. PD.AH_COPY.short); ahGuard = not spot
      elseif s.farm and s.farm[1] and self:Strategy(name) ~= "fastest" then
        local f = s.farm[1]; how = "drops in " .. (f.name or mapName(f.map)); if f.route and f.route[1] then spot = { map = f.map, x = f.route[1][1], y = f.route[1][2], name = f.name } end
      else spot = PD.NearestAuctioneer(pos); how = spot and "Auction House" or PD.AH_COPY.short; ahGuard = not spot end
      if s.how ~= "mine" then total = total + get * (s.price or 0) end
      local split = {}
      if bags > 0 then split[#split + 1] = bags .. " bags" end
      if (bagBank or 0) - bags > 0 then split[#split + 1] = ((bagBank or 0) - bags) .. " bank" end
      if (mail or 0) > 0 then split[#split + 1] = mail .. " mail" end
      local srcWords
      if s.priceSource == "vendor" then srcWords = "vendor price"
      elseif s.priceSource == "you" then srcWords = "your price"
      elseif s.priceSource == "auction" then
        local pr = aucOn and AV.PriceOf and AV.PriceOf(id)
        srcWords = pr and ("auction house, scanned " .. ago(pr.age)) or "auction house"
      else srcWords = "a guess; set yours with /panoply price" end
      local onClick
      if aucOn then
        local nm, key = s.name, id
        onClick = function() AV:OpenItem(nm, key) end
      end
      rows[#rows + 1] = row({ text = ("%s  %d / %d"):format(s.name, math.min(have, s.need), s.need), done = get == 0,
        right = get > 0 and ("get %d: %s"):format(get, how) or how, spot = spot, item = id, onClick = onClick,
        tip = s.name, tipBody = ("Have %d%s, need %d for the plan. About %s each (%s)."):format(have, #split > 0 and (" (" .. table.concat(split, ", ") .. ")") or "",
          s.need, money(s.price), srcWords) .. (vguard and (" " .. PUI.VendorGuardLine()) or "") .. (ahGuard and (" " .. PD.AH_COPY.guard) or "") .. (onClick and " Click: see it on the Auctions page." or "") })
    end
    v.toBuy = total
    -- Made along the way (bolts, bars)
    local mids = U.Keys(plan.intermediates or {})
    if #mids > 0 then
      table.sort(mids)
      rows[#rows + 1] = head("You make these along the way")
      for _, id in ipairs(mids) do
        local m = plan.intermediates[id]
        local have, _, mail = PR():Have(id)
        rows[#rows + 1] = row({ text = ("%s  %d / %d"):format(PD.ItemName(id), math.min(have, m.need), m.need), item = id,
          right = m.how == "smelt" and "smelt at a forge" or ("craft: " .. (m.recipe and m.recipe.name or "")),
          spot = m.how == "smelt" and PD.NearestFocus("forge", pos) or nil, done = have >= m.need,
          tip = PD.ItemName(id), tipBody = ("Have %d%s. You make the rest from the materials above."):format(have, (mail or 0) > 0 and (" (" .. mail .. " in mail)") or "") })
      end
    end
  end
  -- Where to buy and gather
  rows[#rows + 1] = head("Where to buy and gather")
  local seen = {}
  local function where(text, right, spot, tipBody)
    local k = text .. (spot and (spot.map or 0) or "")
    if seen[k] then return end
    seen[k] = true
    rows[#rows + 1] = row({ text = text, right = right, spot = spot, tip = text, tipBody = tipBody })
  end
  if plan.kind == "gathering" then
    for _, sg in ipairs(plan.segments) do
      for i, z in ipairs(sg.zones or {}) do
        if i <= 2 then
          local spot = z.route and z.route[1] and { map = z.map, x = z.route[1][1], y = z.route[1][2], name = z.name } or nil
          where(("%s: %s"):format(sg.name, z.name or mapName(z.map)), ("skill %d-%d%s"):format(sg.from, sg.to, z.dangerous and ", high level!" or ""), spot,
            "The arrow walks you round the spawn spots there.")
        end
      end
    end
  elseif plan.kind == "fishing" then
    for _, sg in ipairs(plan.segments) do
      local z = sg.zone
      if z then where("Fish in " .. (z.name or mapName(z.map)), ("skill %d-%d"):format(sg.from, sg.to), z.route and z.route[1] and { map = z.map, x = z.route[1][1], y = z.route[1][2], name = z.name } or nil) end
    end
  else
    for _, id in ipairs(U.Keys(plan.shopping)) do
      local s = plan.shopping[id]
      if s.how == "vendor" then
        -- 0.9.6 phase O: a vendor of your side, its own limited stock; none known: ask a city guard (no spot)
        local vs, _, lim = self:ItemVendor(s.id or id, pos)
        if vs then where(("%s: %s"):format(s.name, vs.name or "vendor"), mapName(vs.map) .. (lim and " (limited stock)" or ""), vs, "Sells " .. s.name .. ".")
        else where(("%s: vendor"):format(s.name), PUI.VENDOR_GUARD, nil, PUI.VendorGuardLine()) end
      elseif s.how == "mine" then
        local node
        for _, n in ipairs(PD.Mining and PD.Mining.nodes or {}) do
          for _, o in ipairs(n.oreIds or {}) do
            if o == id and not PR().RARE_NODES[n.name] and not n.name:find("^Ooze") and (not node or (n.learn or 0) < (node.learn or 0)) then node = n end
          end
        end
        local z, zt
        for _, zz in ipairs(node and PR():NodeZones(node, Panoply.State.level) or {}) do
          local t = PD.Travel(pos, zz.route and zz.route[1] and { map = zz.map, x = zz.route[1][1], y = zz.route[1][2] } or { map = zz.map, x = 0.5, y = 0.5 })
          if zz.dangerous then t = t + 1e7 end
          if not zt or t < zt then z, zt = zz, t end
        end
        if z then where(("%s: %s"):format(node.name, z.name or mapName(z.map)), "mine it", z.route and z.route[1] and { map = z.map, x = z.route[1][1], y = z.route[1][2], name = z.name } or nil) end
      end
    end
    -- 0.9.6 phase P: an auctioneer of your side or a neutral one; none known: ask a city guard (no spot)
    local ah = PD.NearestAuctioneer(pos)
    if ah then where("Auction House: " .. (ah.name or "auctioneer"), mapName(ah.map), ah, "Buy what you cannot make or gather.")
    else where("Auction House", PD.AH_COPY.row, nil, PD.AH_COPY.guard) end
    local f = plan.segments[1] and plan.segments[1].focus
    -- 0.8.4: the cooking fire's row says where the rest of them are (the Camp sites of the map's Places menu)
    if f then local s = PD.NearestFocus(f, pos) if s then where("Nearest " .. (f == "cooking" and "cooking fire" or f), mapName(s.map), s,
      f == "cooking" and "Every camp site is on your maps: Places menu on the world map, Camp sites." or nil) end end
  end
  -- Enchanting: what to disenchant
  if name == "Enchanting" then
    for _, r in ipairs(self:DisenchantRows(plan)) do rows[#rows + 1] = r end
  end
  return rows
end

-- Disenchanting guidance: which greens give the dust and essences this plan needs, and which of
-- your (or your partner's) Tailoring crafts are such greens.
function PUI:DisenchantRows(plan)
  local rows = { head("Disenchanting: greens to break down") }
  local tailoring = PD.Tailoring
  local tailor = PR():Chosen("Tailoring")
  local pprofs = Panoply.Sync and select(1, Panoply.Sync:PartnerProfessions())
  local partnerTailor = false
  for _, x in ipairs(pprofs or {}) do if x.name == "Tailoring" then partnerTailor = true end end
  local any = false
  for _, id in ipairs(U.Keys(plan.shopping or {})) do
    local s = plan.shopping[id]
    if s.disenchant then
      any = true
      local src = PD.DisenchantSources(id)[1]
      if src then
        rows[#rows + 1] = row({ text = ("%s: green %s, item level %d-%d"):format(s.name, src.kind, src.minIlvl, src.maxIlvl),
          right = ("about %d%% each"):format(math.floor(src.chance)), done = PR():Have(id) >= s.need,
          tip = s.name, tipBody = "Disenchant (the Enchanting spell) any green item in this item level range. Uncommon (green) armor and weapons both work." })
        local best
        for _, r in ipairs(tailoring and tailoring.recipes or {}) do
          if r.quality == 2 and r.ilvl and r.ilvl >= src.minIlvl and r.ilvl <= src.maxIlvl and not r.spec and r.source ~= "drop" then
            if not best or (r.learn or 0) < (best.learn or 0) then best = r end
          end
        end
        if best and (tailor or partnerTailor) then
          rows[#rows + 1] = row({ text = ("  Tailored: %s (item level %d)"):format(best.name, best.ilvl),
            right = (tailor and "you make it" or "your partner makes it") .. (" at skill %d+"):format(best.learn or 1),
            tip = best.name, tipBody = "A green Tailoring item in the right range: tailor it for skill, then disenchant it for this material." })
        end
      end
    end
  end
  if not any then rows[#rows + 1] = row({ text = "This stage needs no dust or essences.", right = "" }) end
  if tailor or partnerTailor then
    rows[#rows + 1] = row({ text = "Tip: disenchant every green your Tailoring makes on the way up.", right = "" })
  end
  return rows
end

function PUI:StepRows(name, plan, rank)
  local rows = {}
  local cur = rank or 0
  local events = {}
  for _, t in ipairs(plan.training or {}) do events[#events + 1] = { at = t.at, train = t } end
  for _, sg in ipairs(plan.segments or {}) do events[#events + 1] = { at = sg.from + 0.5, seg = sg } end
  table.sort(events, function(a, b) return a.at < b.at end)
  local markedCurrent = false
  local _, mx = PR():CurrentSkill(name)
  for _, e in ipairs(events) do
    if e.train then
      local t = e.train
      -- 0.9.6 phase M: a trainer of your side who teaches this rank (else the data's hint, else ask a city guard)
      local tr = self:RankSpot(name, rankOf(name, t), Panoply.State.pos)
      local guard = not tr and not t.hint and trainerSource(t.source)
      local done = (mx or 0) >= t.max
      rows[#rows + 1] = row({ text = ("Train %s (up to %d), %s"):format(t.rank, t.max, money(t.fee)), right = tr and at(tr) or (t.hint and t.hint.text) or (guard and PUI.TRAINER_GUARD) or "",
        spot = tr, done = done, train = true, openProf = rank and name or nil, tip = "Trainer visit",
        tipBody = PR():TrainingText(t) .. (guard and (". " .. PUI.GuardLine()) or "") })
    else
      local sg = e.seg
      local done = cur >= sg.to
      local current = not done and not markedCurrent
      if current then markedCurrent = true end
      local mats = {}
      for id, n in pairs(sg.mats or {}) do mats[#mats + 1] = n .. " " .. PD.ItemName(id) end
      table.sort(mats)
      rows[#rows + 1] = row({ text = PR():SegmentText(plan, sg):gsub(" in .*$", ""), right = table.concat(mats, ", "), done = done, current = current,
        tip = sg.name, tipBody = #mats > 0 and ("Materials: " .. table.concat(mats, ", ") .. ".") or nil })
      if name == "Blacksmithing" and sg.from < 200 and sg.to >= 200 then
        rows[#rows + 1] = row({ text = "At 200: Armorsmith or Weaponsmith (optional)", right = "see Trainers & recipes", tip = "Specialization", tipBody = PR():SpecNote(name) })
      end
    end
  end
  if plan.levelGate then
    rows[#rows + 1] = row({ text = ("Stops at %d until level %d (%s)"):format(plan.levelGate.at, plan.levelGate.minLevel, plan.levelGate.rank), right = "keep levelling" })
  end
  return rows
end

function PUI:TrainerRows(name, plan)
  local rows = { head("Trainer visits") }
  local pos = Panoply.State.pos
  local _, mx = PR():CurrentSkill(name)
  local prof = PD[name]
  for _, rk in ipairs(PR():Ranks(prof)) do
    -- 0.9.6 phase M: a trainer (or book vendor, or quest giver) of your side for this rank
    local tr, _, qTitle = self:RankSpot(name, rk, pos)
    local guard = not tr and not rk.hint and trainerSource(rk.source)
    local how = rk.source == "book" and ("buy " .. (rk.bookName or "the book")) or rk.source == "quest" and ("quest " .. Panoply.Planner.Quoted(qTitle or rk.questTitle or "")) or "trainer"
    rows[#rows + 1] = row({ text = ("%s (up to %d): %s%s"):format(rk.name, rk.max, money(rk.fee), (rk.minLevel or 0) > 1 and (", level " .. rk.minLevel) or ""),
      right = (tr and at(tr) or (rk.hint and (rk.hint.short or rk.hint.text)) or (guard and PUI.TRAINER_GUARD) or "") .. (how ~= "trainer" and (" - " .. how) or ""), spot = tr or (rk.hint and { map = rk.hint.map, x = rk.hint.x, y = rk.hint.y }),
      done = (mx or 0) >= rk.max, openProf = mx and name or nil, tip = rk.name .. " " .. name, tipBody = ("Needs skill %d%s. Costs %s.%s%s"):format(rk.minSkill or 0, (rk.minLevel or 0) > 1 and (" and level " .. rk.minLevel) or "", money(rk.fee), rk.hint and rk.hint.text and (" " .. rk.hint.text) or "", guard and (" " .. PUI.GuardLine()) or "") })
  end
  if #(plan.recipes or {}) > 0 then
    rows[#rows + 1] = head("Recipes to learn")
    for _, r in ipairs(plan.recipes) do
      -- 0.9.6 phase M: a recipe from a trainer: a trainer of your side who teaches it (vendors and drops: as before)
      -- 0.9.6 phase O: a recipe from a vendor (or any other NPC): one of your side, its own limited stock; none: ask a city guard
      local rec = r.recipe or r
      local spot, lim, vguard = nil, false, false
      local bought = r.source ~= "trainer" and self:BoughtFromVendor(rec, pos)
      if r.source == "trainer" then spot = self:RecipeTrainer(rec, pos)
      else spot, _, lim = self:RecipeVendor(rec, pos); vguard = bought and not spot end
      local src = r.source == "trainer" and "trainer" or bought and ("buy " .. (r.recipeName or "the recipe")) or r.source == "drop" and "drops; check the Auction House" or r.source
      if r.source == "drop" and not bought then spot = nil end
      local guard = r.source == "trainer" and not spot
      if guard then src = PUI.TRAINER_GUARD end
      if vguard then src = PUI.RECIPE_VENDOR_GUARD:format(name) end
      rows[#rows + 1] = row({ text = ("At %d: %s (%s)"):format(r.at, r.name, money(r.fee)), right = src .. (spot and (" - " .. at(spot)) or "") .. (lim and " (limited)" or ""),
        spot = spot, done = PR():KnowsRecipe(name, r.recipe), tip = r.name,
        tipBody = lim and "Limited stock: if sold out it comes back after a while." or (guard and PUI.GuardLine()) or (vguard and PUI.VendorGuardLine()) or nil })
    end
  end
  if #(plan.tools or {}) > 0 then
    rows[#rows + 1] = head("Tools")
    for _, t in ipairs(plan.tools) do
      rows[#rows + 1] = row({ text = t.name, right = t.have and "you have it" or (t.maker and ("make it: " .. t.maker.name) or "buy from a trade supplier"), done = t.have })
    end
  end
  if name == "Blacksmithing" then
    rows[#rows + 1] = head("Specialization (optional)")
    local spec = Panoply.cdb and Panoply.cdb.profSpec and Panoply.cdb.profSpec.Blacksmithing or ""
    rows[#rows + 1] = row({ text = spec ~= "" and ("Chosen: " .. spec) or "Not chosen: the plan uses no specialization recipes", right = "change in Settings",
      tip = "Armorsmith or Weaponsmith", tipBody = PR():SpecNote(name) })
  end
  for _, w in ipairs(plan.warnings or {}) do rows[#rows + 1] = row({ text = "Note: " .. w, note = true }) end
  return rows
end

-- Partner synergy rules: { mine, theirs, text }. "you"/"they" are filled in.
-- { giver, receiver, you help them, they help you, you help yourself }
PUI.SYNERGY = {
  { "Mining", "Blacksmithing", "Your Mining feeds %s's Blacksmithing: mail spare ore, bars and stone.",
    "%s's Mining feeds your Blacksmithing: ask for spare ore, bars and stone.",
    "Your Mining feeds your Blacksmithing: keep your ore and stone instead of selling them." },
  { "Blacksmithing", "Enchanting", "You can make the Silver, Golden and Truesilver Rods that %s's Enchanting needs.",
    "%s can make the Silver, Golden and Truesilver Rods your Enchanting needs.",
    "You can make your own Silver, Golden and Truesilver enchanting Rods." },
  { "Tailoring", "Enchanting", "Mail your Tailoring greens to %s to disenchant into dust and essences, instead of selling them.",
    "%s's Tailoring greens disenchant into the dust and essences your Enchanting needs. Ask for them.",
    "Disenchant your own Tailoring greens: they give the dust and essences your Enchanting needs." },
  { "Enchanting", "Blacksmithing", "You can enchant the weapons and armour %s smiths (cheap skill-ups for you).",
    "%s can enchant the weapons and armour you smith.",
    "Enchant the weapons and armour you smith (cheap skill-ups)." },
  { "Enchanting", "Tailoring", "You can enchant the cloaks, bracers and gloves %s tailors.",
    "%s can enchant the cloaks, bracers and gloves you tailor.",
    "Enchant the cloaks, bracers and gloves you tailor (cheap skill-ups)." },
  { "Fishing", "Cooking", "Your catches are %s's cooking ingredients.",
    "%s's catches are your cooking ingredients.",
    "Cook what you catch." },
  { "Tailoring", "First Aid", "Both use cloth: you turn it into bolts, %s into bandages. Agree who gets Wool, Silk and Mageweave.",
    "Both use cloth: %s turns it into bolts, you into bandages. Agree who gets Wool, Silk and Mageweave.",
    "Both use cloth: split your Wool, Silk and Mageweave between bolts and bandages." },
}

function PUI:TogetherRows(name)
  local rows = {}
  local Sy = Panoply.Sync
  local pprofs, pstep, ptracked, pname = nil, nil, nil, nil
  if Sy then pprofs, pstep, ptracked, pname = Sy:PartnerProfessions() end
  local mine = {}
  for _, n in ipairs(self:Chosen()) do mine[n] = true end
  local theirs = {}
  for _, x in ipairs(pprofs or {}) do theirs[x.name] = x end
  rows[#rows + 1] = head(pname and ("%s's professions"):format(pname) or "Your partner's professions")
  if pname then
    if #pprofs == 0 then rows[#rows + 1] = row({ text = "No professions shared yet.", right = "" }) end
    for _, x in ipairs(pprofs) do rows[#rows + 1] = row({ text = ("%s %d / %d"):format(x.name, x.rank, x.max), right = x.name == ptracked and "working on it now" or "" }) end
    if pstep then rows[#rows + 1] = row({ text = "Their next profession step: " .. pstep, right = "" }) end
  else
    rows[#rows + 1] = row({ text = "Shows here once you are grouped with sync on.", right = "Partner tab", tip = "Partner", tipBody = "Group up with your partner; both of you need Panoply Suite." })
  end
  rows[#rows + 1] = head("How you help each other")
  local any = false
  local them = pname or "your partner"
  for _, s in ipairs(self.SYNERGY) do
    if mine[s[1]] and theirs[s[2]] then rows[#rows + 1] = row({ text = s[3]:format(them), right = "you help " .. them, tip = s[1] .. " to " .. s[2], tipBody = s[3]:format(them) }); any = true end
    if theirs[s[1]] and mine[s[2]] then rows[#rows + 1] = row({ text = s[4]:format(them), right = them .. " helps you", tip = s[1] .. " to " .. s[2], tipBody = s[4]:format(them) }); any = true end
    if mine[s[1]] and mine[s[2]] then rows[#rows + 1] = row({ text = s[5], right = "both yours", tip = s[1] .. " to " .. s[2], tipBody = s[5] }); any = true end
  end
  if not any then rows[#rows + 1] = row({ text = "No direct links between your professions and your partner's yet.", right = "" }) end
  return rows
end

-- opts.snap: the one game snapshot of this drawing (Engine/ProfCamp.lua); opts.noRows: only what the list needs (status, Next card),
-- no tab rows (the professions that are not selected)
function PUI:View(name, opts)
  opts = opts or {}
  local v = { name = name, rows = {} }
  if not name then v.title = "Professions"; v.skill = "Pick professions to see what to do next, what to buy and where to train."; return v end
  local prof = PD[name]
  local rank, max = PR():CurrentSkill(name)
  v.rank, v.max = rank, max
  v.secondary = PD.SECONDARY[name] or false
  if rank then
    v.skill = ("Skill %d / %d"):format(rank, max or 0)
  else
    v.skill = "Not learned yet"
  end
  local rk = prof and nextCap(prof, rank, max)
  if rank and (max or 0) > 0 then
    v.barP = rank / math.max(1, max)
    v.bar = rk and ("%d / %d  -  then %s (up to %d) from skill %d%s"):format(rank, max, rk.name, rk.max, rk.minSkill or 0, (rk.minLevel or 0) > 1 and (", level " .. rk.minLevel) or "")
      or ("%d / %d"):format(rank, max)
  else
    v.barP = 0
    v.bar = prof and ("Learn Apprentice %s to start (%s)"):format(name, money(prof.ranks[1].fee)) or ""
  end
  v.kind = PUI.Kind(name)
  v.gate = self:Gate(name, rank, max)
  local plan, err = self:PlanFor(name)
  v.plan = plan
  if not plan then
    v.note = err
    v.next = self:NextCard(name, v, opts.snap)
    v.status = self:Status(name, v)
    return v
  end
  local mins = math.floor((plan.totalSeconds or 0) / 60 + 0.5)
  v.total = money(plan.totalCost) .. (", about %s of play"):format(mins >= 90 and (("%.1f hours"):format(mins / 60)) or (mins .. " minutes"))
  v.range = ("Plan: %d to %d, %s, %s"):format(plan.from, plan.to, self:Strategy(name) == "fastest" and "fastest" or "cheapest", self:Mode(name) == "scratch" and "from scratch" or "from your skill")
  -- Your next step: the same live step the guide uses.
  local G = Panoply.ProfGuide
  local q = G and G:Preview(name) or {}
  local st = q[1]
  v.nextStep = st
  if st then
    v.next = { title = Panoply.StepText.Headline(st), why = Panoply.StepText.Why(st), spot = st.mapID and { map = st.mapID, x = st.x, y = st.y, name = st.title } or nil, kind = st.kind, count = #q }
    local pg = Panoply.StepText.Progress(st)
    v.next.progress = pg[1] and pg[1].text or nil
  elseif rank and rank >= 300 then
    v.next = { title = name .. " is maxed. Well done!", why = "Nothing left to train." }
  else
    v.next = { title = "Nothing to do right now", why = plan.levelGate and ("Keep levelling: %s needs level %d."):format(plan.levelGate.rank, plan.levelGate.minLevel) or "" }
  end
  v.tracked = G and G:Tracked() == name
  -- 0.9.5: the guide's step is the Craft or gather action; a train, Blueprint or Favor blocker comes first (PUI:NextCard)
  v.next = self:NextCard(name, v, opts.snap)
  v.status = self:Status(name, v)
  local page = self:TabFor(name)
  v.page = page
  if opts.noRows then v.rows = {} return v end
  v.rows = self:RowsFor(name, page, plan, v, opts.snap)
  if page == "Shopping" and v.toBuy then v.footer = ("Still to buy: about %s.  Whole plan: %s."):format(money(v.toBuy), v.total)
  elseif page == "Steps" or page == "Shopping" or page == "Where" then v.footer = "Whole plan: " .. v.total .. "."
  else v.footer = nil end
  return v
end

-- the rows of one tab (Shopping keeps working out what is still to buy into v.toBuy)
function PUI:RowsFor(name, page, plan, v, snap)
  if page == "Shopping" then return self:ShoppingRows(name, plan, v)
  elseif page == "Steps" then return self:StepRows(name, plan, v.rank)
  elseif page == "Recipes" then return self:RecipeRows(name, plan)
  elseif page == "Where" then return self:WhereRows(name, plan, v.rank)
  elseif page == "Scarce" then return self:ScarceRows(name)
  elseif page == "Camp" then return self:CampRows(name, v.rank, snap)
  elseif page == "Trainers & recipes" then return self:TrainerRows(name, plan) end
  return self:TogetherRows(name)
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4B: types, tabs, rank gates, status chips and the Next card
-------------------------------------------------------------------------------
function PUI.Kind(name)
  local p = PD[name or ""]
  if p and (p.kind == "gathering" or p.kind == "fishing" or p.kind == "crafting") then return p.kind end
  if name == "Fishing" then return "fishing" end
  if PUI.GATHERING[name or ""] then return "gathering" end
  return "crafting"
end

-- the tabs a profession shows, in order (a tab that does not apply is not there; Camp is WoW Forever only)
function PUI:TabsFor(name)
  local k, fv = PUI.Kind(name), C.IsForever()
  local t
  if k == "gathering" then t = { "Where", "Scarce" } if fv then t[#t + 1] = "Camp" end t[#t + 1] = "Together"
  elseif k == "fishing" then t = { "Where" } if fv then t[#t + 1] = "Camp" end
  else t = { "Steps", "Shopping", "Recipes" } if fv then t[#t + 1] = "Camp" end t[#t + 1] = "Together" end
  return t
end
-- the tab that shows for a profession: the one picked last when this profession has it, else its first
function PUI:TabFor(name)
  local want = PUI.OLD_TABS[self.page or ""] or self.page
  for _, k in ipairs(self:TabsFor(name)) do if k == want then return k end end
  return self:TabsFor(name)[1]
end

local function level() return (Panoply.State and Panoply.State.level) or select(1, C.XP()) or 1 end

-- The next rank and what it needs: the profession data's skill and level, or on WoW Forever the rank gates of Data/ProfForever.lua
-- (gathering needs a lower level there). The "Train now" alert reads the same (UI/AlertSources.lua).
-- { rank = rk, skill, level, skillOK, levelOK, capped (skill at the cap: nothing more until you train), learned, yourLevel }
function PUI:Gate(name, rank, max)
  local prof = PD[name or ""]
  if not (prof and prof.ranks) then return nil end
  local learned = rank ~= nil and (max or 0) > 0
  local _, rk = PR():RankFor(prof, learned and max or 0)
  if not rk then return nil end
  local needSkill, needLevel = rk.minSkill or 0, rk.minLevel or 0
  local PF = Panoply.ProfForever
  if C.IsForever() and PF then
    local g = PF.Gate(rk.name, prof.kind)
    if g then needSkill, needLevel = g.skill, g.level end
  end
  local lv, sk = level(), rank or 0
  return { rank = rk, skill = needSkill, level = needLevel, skillOK = sk >= needSkill, levelOK = lv >= needLevel,
    capped = learned and sk >= (max or 0), learned = learned, yourLevel = lv }
end

-- Status chip: "maxed" | "train" | "blocked" | "craft" | "gather" (nil when the profession is not learned)
function PUI:Status(name, v)
  if not v.rank or (v.max or 0) == 0 then return nil end
  local g = v.gate
  if not g and v.rank >= (v.max or 0) then return "maxed" end
  if v.rank >= 300 then return "maxed" end
  local n = v.next
  if n and (n.kind == "blueprint" or n.kind == "favor") then return "blocked" end
  if g and g.skillOK and g.levelOK then return "train" end
  if g and g.capped then return "blocked" end
  return (v.kind or PUI.Kind(name)) == "crafting" and "craft" or "gather"
end

-- the recipe the plan does next (its current segment's recipe)
local function nextRecipe(plan, rank)
  for _, sg in ipairs(plan and plan.segments or {}) do
    if sg.to > (rank or 0) then return sg.option, sg end
  end
  return nil
end

-- the camp object of a profession with that name
function PUI:CampObject(name, objName)
  local PF = Panoply.ProfForever
  for _, o in ipairs(PF and PF.CampOf(name) or {}) do if o.name == objName then return o end end
  return nil
end

-- "Gilnid, The Deadmines" or "Source unknown"
function PUI.SourceText(src)
  if type(src) ~= "table" or not src.boss then return "Source unknown" end
  return src.boss .. (src.instance and (", " .. src.instance) or "")
end

-- what the trainer of a rank is: { text = "Trainer: Name, Zone", spot, cost, where }
-- 0.9.6 phase M: a trainer of your side who teaches the rank (PUI:RankSpot); none known: ask a city guard, no spot
function PUI:Trainer(rk, name)
  local spot, where, qTitle = self:RankSpot(name, rk)
  local how
  if rk.source == "book" then how = "Book: " .. (rk.bookName or "the book")
  elseif rk.source == "quest" then how = "Quest: " .. (qTitle or rk.questTitle or "see the guide")
  else how = spot and ("Trainer: " .. at(spot)) or (rk.hint and (rk.hint.short or rk.hint.text)) or PUI.TRAINER_GUARD end
  if not spot and rk.hint and rk.hint.map then spot = { map = rk.hint.map, x = rk.hint.x, y = rk.hint.y, name = rk.hint.short }; where = "hint" end
  return { text = how, spot = spot, cost = money(rk.fee), where = spot and where or "guard" }
end

-- The Next card: exactly one action, the most urgent blocker first.
--   1 train      the next rank (skill and level marks, trainer, place, cost)
--   2 blueprint  the next recipe needs a camp station you do not have (WoW Forever)
--   3 favor      the next recipe is a trade-camp pattern you cannot buy yet (WoW Forever)
--   4 craft / gather   the guide's own next step (recipe x count, have the materials or what to buy)
--   learn / maxed / none: not learned yet, at 300, or nothing to do now
-- { kind, title, line, facts = { { ok, text } }, spot, instance, blocker (a short second line), step (the guide step) }
function PUI:NextCard(name, v, snap)
  local n = self:NextCardRaw(name, v, snap)
  -- 0.9.5 phase 4G (spec 01 section 8): the Legacy perks that change the camp or your skill, in the card's tooltip
  local L = Panoply.Legacy
  if n and C.IsForever() and L and L.CampPerks then
    local lines = {}
    for _, e in ipairs(L:CampPerks()) do lines[#lines + 1] = "Legacy: " .. L.CampPerkLine(e) end
    if #lines > 0 then n.perkNote = table.concat(lines, "\n") end
  end
  return n
end
function PUI:NextCardRaw(name, v, snap)
  local g = v.gate
  local rank, plan = v.rank, v.plan
  if not rank or (v.max or 0) == 0 then
    local prof = PD[name or ""]
    local rk = prof and prof.ranks and prof.ranks[1]
    if not rk then return { kind = "none", title = "No plan for " .. tostring(name) .. " yet", line = v.note or "" } end
    local tr = self:Trainer(rk, name)
    return { kind = "learn", title = ("Learn Apprentice %s"):format(name), line = tr.text .. " · " .. tr.cost, spot = tr.spot,
      blocker = tr.text, facts = {} }
  end
  if rank >= 300 or (not g and rank >= (v.max or 0)) then
    return { kind = "maxed", title = name .. " is maxed. Well done!", line = "Nothing left to train.", facts = {} }
  end
  -- 1. train
  if g and ((g.skillOK and g.levelOK) or g.capped) then
    local rk = g.rank
    local tr = self:Trainer(rk, name)
    local facts = { { ok = g.skillOK, text = ("Skill %d"):format(g.skill) } }
    if (g.level or 0) > 1 then
      facts[#facts + 1] = { ok = g.levelOK, text = g.levelOK and ("Level %d"):format(g.level) or ("Level %d (you are %d)"):format(g.level, g.yourLevel) }
    end
    return { kind = "train", title = ("Train %s %s (up to %d)"):format(rk.name, name, rk.max), line = tr.text .. " · " .. tr.cost,
      facts = facts, spot = tr.spot, train = rk,
      blocker = (not g.levelOK) and ("Needs level %d; you are %d."):format(g.level, g.yourLevel) or (tr.text .. " · " .. tr.cost) }
  end
  local PF = Panoply.ProfForever
  local r = nextRecipe(plan, rank)
  if C.IsForever() and PF and r then
    -- 2. a camp station the next recipe needs
    local st = PF.RECIPE_STATIONS[name] and PF.RECIPE_STATIONS[name][r.name]
    local obj = st and self:CampObject(name, st)
    if obj then
      local PC = Panoply.ProfCamp
      local state = PC and PC:ObjectState(obj, rank, snap) or "missing"
      if state ~= "known" and state ~= "owned" then
        local src = obj.source
        return { kind = "blueprint", title = "Blueprint needed: " .. obj.name, line = (src and ("Drops from " .. PUI.SourceText(src)) or "Source unknown") ..
          (" · %s needs it"):format(r.name), facts = {}, instance = src and src.instance, object = obj,
          blocker = ("%s needs the %s."):format(r.name, obj.name) }
      end
    end
    -- 3. a trade-camp pattern: Favor and standing
    for _, pt in ipairs(PF.PATTERNS[name] or {}) do
      if pt.name == r.name and not PR():KnowsRecipe(name, r) then
        local PC = Panoply.ProfCamp
        snap = snap or (PC and PC:Snapshot()) or {}
        local favor, rep = snap.favor, snap.rep
        local needID = PC and PC.StandingID(pt.standing)
        local favorOK = favor ~= nil and favor >= (pt.favor or 0)
        local repOK = (not needID) or (rep and rep.standingID and rep.standingID >= needID) or false
        if not (favorOK and repOK) then
          local have = {}
          have[#have + 1] = favor and ("you have %d"):format(favor) or "your Favor is not known yet"
          if pt.standing then have[#have + 1] = rep and rep.standing or "standing not known" end
          return { kind = "favor", title = ("Plans: %s needs %s%d Favor"):format(pt.name, pt.standing and (pt.standing .. ", ") or "", pt.favor or 0),
            line = (table.concat(have, ", "):gsub("^%l", string.upper)) .. ".", facts = { { ok = favorOK, text = ("%d Favor"):format(pt.favor or 0) },
              pt.standing and { ok = repOK, text = pt.standing } or nil }, pattern = pt,
            blocker = ("%s needs %s%d Favor."):format(pt.name, pt.standing and (pt.standing .. " and ") or "", pt.favor or 0) }
        end
      end
    end
  end
  -- 4. craft or gather: the guide's own next step
  local st = v.nextStep
  local kind = (v.kind or PUI.Kind(name)) == "crafting" and "craft" or "gather"
  local blocker
  if g and g.skillOK == false and not g.levelOK then blocker = ("Next: %s at skill %d and level %d."):format(g.rank.name, g.skill, g.level)
  elseif g and not g.levelOK then blocker = ("Next: %s needs level %d; you are %d."):format(g.rank.name, g.level, g.yourLevel)
  elseif g then blocker = ("Next: %s at skill %d."):format(g.rank.name, g.skill) end
  if not st then
    return { kind = "none", title = "Nothing to do right now", line = plan and plan.levelGate and ("Keep levelling: %s needs level %d."):format(plan.levelGate.rank, plan.levelGate.minLevel) or (v.note or ""),
      facts = {}, blocker = blocker }
  end
  local line = Panoply.StepText.Why(st)
  local pg = Panoply.StepText.Progress(st)
  local progress = pg[1] and pg[1].text or nil
  if progress and progress:find("%d+/%d+") then line = progress .. "  -  " .. (line or "") end
  local mats = kind == "craft" and self:MatsLine(r, plan, rank) or nil
  return { kind = kind, title = Panoply.StepText.Headline(st), line = mats or line, why = line, mats = mats, facts = {}, step = st,
    spot = st.mapID and { map = st.mapID, x = st.x, y = st.y, name = st.title } or nil, blocker = blocker, progress = progress }
end

-- "You have the materials." or "Buy: 4 Linen Cloth, 2 Coarse Thread" for the current segment
function PUI:MatsLine(r, plan, rank)
  local sg
  for _, s in ipairs(plan and plan.segments or {}) do if s.to > (rank or 0) then sg = s break end end
  if not (sg and sg.mats) then return nil end
  local need = {}
  for id, n in pairs(sg.mats) do
    local have = PR():Have(id)
    if have < n then need[#need + 1] = { n = n - have, name = PD.ItemName(id) } end
  end
  if #need == 0 then return "You have the materials." end
  table.sort(need, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  local parts = {}
  for i = 1, math.min(3, #need) do parts[i] = need[i].n .. " " .. need[i].name end
  return "Buy or gather: " .. table.concat(parts, ", ") .. (#need > 3 and (", and %d more"):format(#need - 3) or "") .. "."
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4B: the new tabs' rows
-------------------------------------------------------------------------------
PUI.RECIPE_FILTERS = { { value = "all", text = "All recipes" }, { value = "learned", text = "Learned" }, { value = "todo", text = "Not learned" } }
PUI.recipeFilter, PUI.recipeQuery = "all", ""
PUI.RECIPE_MAX = 80   -- the most recipe rows one draw shows; the search finds the rest

-- where a recipe comes from, in words ("Source unknown" when no source is confirmed)
function PUI:RecipeSource(name, r)
  local PF = C.IsForever() and Panoply.ProfForever or nil
  local parts = {}
  local pt
  for _, p in ipairs(PF and PF.PATTERNS[name] or {}) do if p.name == r.name then pt = p end end
  if pt then parts[#parts + 1] = ("Merchant's Favor %d%s"):format(pt.favor or 0, pt.standing and (", " .. pt.standing) or "")
  elseif r.foreverMissing or r.foreverOnly then parts[#parts + 1] = "Source unknown"
  elseif r.source == "auto" then parts[#parts + 1] = "Learned with the profession"
  elseif r.source == "trainer" then parts[#parts + 1] = "Trainer" .. ((r.fee or 0) > 0 and (", " .. money(r.fee)) or "")
  elseif self:BoughtFromVendor(r) then
    -- 0.9.6 phase O: a vendor of your side, its own limited stock; none known: ask a city guard
    local spot, _, lim = self:RecipeVendor(r)
    parts[#parts + 1] = "Vendor: " .. (spot and at(spot) or lowerFirst(PUI.RECIPE_VENDOR_GUARD:format(name))) .. (lim and " (limited)" or "")
  elseif r.source == "drop" then parts[#parts + 1] = "Drop"
  elseif r.source == "quest" then parts[#parts + 1] = "Quest"
  elseif r.source == "item" then parts[#parts + 1] = "Recipe item"
  else parts[#parts + 1] = "Source unknown" end
  local st = PF and PF.RECIPE_STATIONS[name] and PF.RECIPE_STATIONS[name][r.name]
  if st then parts[#parts + 1] = "needs the " .. st .. " (Blueprint)" end
  return table.concat(parts, " · ")
end

function PUI:RecipeRows(name, plan)
  local rows = {}
  local prof = PD[name]
  -- tools and the specialization (what the old Trainers & recipes tab had beside the trainer visits, which are in Steps)
  if #(plan and plan.tools or {}) > 0 then
    rows[#rows + 1] = head("Tools")
    for _, t in ipairs(plan.tools) do
      rows[#rows + 1] = row({ text = t.name, right = t.have and "you have it" or (t.maker and ("make it: " .. t.maker.name) or "buy from a trade supplier"), done = t.have })
    end
  end
  if name == "Blacksmithing" then
    rows[#rows + 1] = head("Specialization (optional)")
    local spec = Panoply.cdb and Panoply.cdb.profSpec and Panoply.cdb.profSpec.Blacksmithing or ""
    rows[#rows + 1] = row({ text = spec ~= "" and ("Chosen: " .. spec) or "Not chosen: the plan uses no specialization recipes", right = "change in Settings",
      tip = "Armorsmith or Weaponsmith", tipBody = PR():SpecNote(name) })
  end
  local list = {}
  for _, r in ipairs(prof and prof.recipes or {}) do list[#list + 1] = r end
  table.sort(list, function(a, b) if (a.learn or 0) ~= (b.learn or 0) then return (a.learn or 0) < (b.learn or 0) end return (a.name or "") < (b.name or "") end)
  local f, q = self.recipeFilter or "all", (self.recipeQuery or ""):lower()
  local shown, matched, learned = 0, 0, 0
  local out = {}
  for _, r in ipairs(list) do
    local known = PR():KnowsRecipe(name, r)
    if known then learned = learned + 1 end
    local keep = (f == "all") or (f == "learned" and known) or (f == "todo" and not known)
    if keep and q ~= "" then keep = (r.name or ""):lower():find(q, 1, true) ~= nil end
    if keep then
      matched = matched + 1
      if shown < self.RECIPE_MAX then
        shown = shown + 1
        local src = self:RecipeSource(name, r)
        out[#out + 1] = row({ text = ("%d  %s"):format(r.learn or 1, r.name or "?"), right = known and "learned" or src, done = known,
          unknown = (not known) and src:find("^Source unknown") ~= nil,
          tip = r.name, tipBody = ("Learn at skill %d. %s."):format(r.learn or 1, src) })
      end
    end
  end
  rows[#rows + 1] = head(("Recipes: %d learned of %d"):format(learned, #list))
  for _, e in ipairs(out) do rows[#rows + 1] = e end
  if matched == 0 then rows[#rows + 1] = row({ text = q ~= "" and ("No recipe matches '%s'."):format(self.recipeQuery) or "No recipes here.", right = "" }) end
  if matched > shown then rows[#rows + 1] = row({ text = ("Showing %d of %d. Type in Search to find the rest."):format(shown, matched), right = "", note = true }) end
  return rows
end

-- Where (gathering and fishing): the places for each stage of the plan, the current one first marked; each with a map button
function PUI:WhereRows(name, plan, rank)
  local rows = {}
  local cur = rank or 0
  local marked = false
  if not plan then return { row({ text = "No plan yet.", right = "" }) } end
  rows[#rows + 1] = head("Where to gather, by skill")
  for _, sg in ipairs(plan.segments or {}) do
    local done = cur >= sg.to
    local current = not done and not marked
    if current then marked = true end
    local zones = sg.zones or (sg.zone and { sg.zone }) or {}
    local label = sg.name or (plan.kind == "fishing" and "Fishing") or name
    if #zones == 0 then
      rows[#rows + 1] = row({ text = ("%d-%d  %s"):format(sg.from, sg.to, label), right = "any water", done = done, current = current })
    end
    for i, z in ipairs(zones) do
      if i <= 3 then
        local spot = z.route and z.route[1] and { map = z.map, x = z.route[1][1], y = z.route[1][2], name = z.name } or (z.map and { map = z.map, x = 0.5, y = 0.5, name = z.name }) or nil
        rows[#rows + 1] = row({ text = ("%d-%d  %s"):format(sg.from, sg.to, label), right = (z.name or mapName(z.map)) .. (z.dangerous and ", high level!" or ""),
          spot = spot, mapButton = true, done = done, current = current and i == 1,
          tip = z.name or mapName(z.map), tipBody = "The map button shows this place on your map. The arrow walks you round the spots there." })
      end
    end
  end
  if #rows == 1 then rows[#rows + 1] = row({ text = "No places in the data for this skill range.", right = "" }) end
  return rows
end

-- Scarce (gathering): scarce materials the gather log counted
function PUI:ScarceRows(name)
  local PC = Panoply.ProfCamp
  local rows = { head("Scarce materials you gathered") }
  local list = PC and PC:Scarce(name) or {}
  for _, e in ipairs(list) do
    rows[#rows + 1] = row({ text = e.name, right = ("x %d"):format(e.n), done = true, item = e.id, tip = e.name,
      tipBody = "Counted by Panoply's gather log on this character." })
  end
  if #list == 0 then
    rows[#rows + 1] = row({ text = "Nothing scarce logged yet. The gather log counts what you gather from now on.", right = "" })
  end
  local total = PC and PC:Logged(name) or 0
  rows[#rows + 1] = row({ text = ("Gathered so far on this character: %d items."):format(total), right = "", note = true })
  return rows
end

-- Camp (WoW Forever): the profession's three camp objects (and on Cooking the campfire tier). Entries carry .camp for the icon cells.
PUI.CAMP_WORDS = { known = "Known", owned = "Owned: use it to learn it", missing = "Missing", locked = "Needs skill %d" }
function PUI:CampRows(name, rank, snap)
  local PF, PC = Panoply.ProfForever, Panoply.ProfCamp
  local rows = {}
  if not (C.IsForever() and PF) then return { row({ text = "Camp objects are a WoW Forever feature.", right = "" }) } end
  snap = snap or (PC and PC:Snapshot()) or { spells = {}, items = {} }
  rows[#rows + 1] = head("Camp objects (unverified data)")
  for _, o in ipairs(PF.CampOf(name) or {}) do
    local state, cd = "missing", nil
    if PC then state, cd = PC:ObjectState(o, rank, snap) end
    local words = PUI.CAMP_WORDS[state]:format(o.skill or 0)
    if state == "known" and cd then words = words .. (cd > 0 and (", ready in %s"):format(SecondsToTime and SecondsToTime(cd) or (math.ceil(cd / 60) .. " min")) or ", ready") end
    local src = o.blueprint and ("Blueprint: " .. PUI.SourceText(o.source)) or "Learned at the trainer"
    rows[#rows + 1] = row({ text = ("%d  %s"):format(o.skill or 0, o.name), right = words, done = state == "known", camp = { obj = o, state = state, cooldown = cd },
      instance = o.source and o.source.instance, tip = o.name,
      tipBody = src .. "." .. (o.station and " A station the most advanced recipes need." or "") .. (o.note and (" " .. o.note) or "") })
  end
  if name == "Cooking" then
    rows[#rows + 1] = head("Campfire")
    local best
    for _, t in ipairs(PF.CAMPFIRE) do if (rank or 0) >= (t.skill or 0) then best = t end end
    for _, t in ipairs(PF.CAMPFIRE) do
      local reached = (rank or 0) >= (t.skill or 0)
      rows[#rows + 1] = row({ text = ("%s campfire: %d objects"):format(t.tier, t.slots), right = (t == best and "yours" or (reached and "skill reached" or ("at Cooking %d"):format(t.skill))) ..
        (t.blueprint and (" · Blueprint: " .. PUI.SourceText(t.source)) or ""), done = reached, current = t == best,
        instance = t.source and t.source.instance, tip = t.tier .. " campfire", tipBody = ("Holds %d camp objects. Cooking %d.%s"):format(t.slots, t.skill, t.note and (" " .. t.note) or "") })
    end
  end
  -- 0.9.5 phase 4G (spec 01 section 8): the Legacy perks that change the camp, when this character has or plans them; each opens the plan
  local L = Panoply.Legacy
  local perks = L and L.CampPerks and L:CampPerks() or {}
  if #perks > 0 then
    rows[#rows + 1] = head("Legacy perks that change your camp")
    for _, e in ipairs(perks) do
      rows[#rows + 1] = row({ text = L.CampPerkLine(e), right = "", done = e.state == "owned", tip = e.name,
        tipBody = L:PerkText(e.perk) .. (e.state == "planned" and " In your perk plan, not spent yet." or "") .. " Click: the Legacy page, Perk plan.",
        onClick = function() if L.Open then L:Open("plan") end end })
    end
  end
  rows[#rows + 1] = row({ text = "Known: a spell of that name. Owned: its Blueprint or item in your bags. Unverified until the probe has run.", right = "", note = true })
  return rows
end

-------------------------------------------------------------------------------
-- The trade camp and Mage Research (WoW Forever), and what is not learned
-------------------------------------------------------------------------------
function PUI:TradeCampView(snap)
  local PF, PC = Panoply.ProfForever, Panoply.ProfCamp
  snap = snap or (PC and PC:Snapshot()) or {}
  local v = { kind = "tradecamp", name = snap.campName or "Trade camp", rows = {} }
  local rows = v.rows
  rows[#rows + 1] = head(snap.campName or "Trade camp")
  rows[#rows + 1] = row({ text = "Merchant's Favor", right = snap.favor and tostring(snap.favor) or "not known yet", done = snap.favor ~= nil,
    tip = "Merchant's Favor", tipBody = "Per character. Earned by handing Waylaid Crates to your faction's trade camp." })
  rows[#rows + 1] = row({ text = "Reputation", right = snap.rep and (snap.rep.standing or "?") .. ((snap.rep.max or 0) > 0 and (" %d / %d"):format(snap.rep.value or 0, snap.rep.max) or "") or "not known yet",
    done = snap.rep ~= nil, tip = "Reputation", tipBody = "Craftsman's Writs raise it, once a day each." })
  rows[#rows + 1] = row({ text = "Waylaid Crates in your bags", right = tostring(snap.crates or 0), done = (snap.crates or 0) > 0 })
  rows[#rows + 1] = row({ text = "Craftsman's Writs you carry", right = tostring(snap.writs or 0), done = (snap.writs or 0) > 0 })
  rows[#rows + 1] = row({ text = "Today's writs", right = "not tracked yet", tip = "Today's writs",
    tipBody = "How the game reports a writ handed in today is not known yet (the probe will tell)." })
  -- the next pattern: the first one you can afford, else the first and what it needs
  local best, need
  for prof, list in pairs(PF and PF.PATTERNS or {}) do
    for _, pt in ipairs(list) do
      local needID = PC and PC.StandingID(pt.standing)
      local ok = (snap.favor or -1) >= (pt.favor or 0) and ((not needID) or (snap.rep and (snap.rep.standingID or 0) >= needID))
      if ok and not best then best = { prof = prof, pt = pt } elseif not ok and not need then need = { prof = prof, pt = pt } end
    end
  end
  rows[#rows + 1] = head("Next pattern")
  if best then rows[#rows + 1] = row({ text = ("%s (%s)"):format(best.pt.name, best.prof), right = ("you can buy it: %d Favor"):format(best.pt.favor or 0), done = true })
  elseif need then rows[#rows + 1] = row({ text = ("%s (%s)"):format(need.pt.name, need.prof), right = ("needs %s%d Favor"):format(need.pt.standing and (need.pt.standing .. ", ") or "", need.pt.favor or 0) })
  else rows[#rows + 1] = row({ text = "Source unknown: no trade-camp patterns are confirmed yet.", right = "", unknown = true }) end
  v.next = { kind = (snap.crates or 0) > 0 and "camp" or "none",
    title = (snap.crates or 0) > 0 and ("Hand in %d Waylaid Crate%s for Merchant's Favor"):format(snap.crates, snap.crates == 1 and "" or "s") or "No crates to hand in",
    line = ("Favor: %s · %s"):format(snap.favor and tostring(snap.favor) or "not known yet", snap.rep and (snap.rep.standing or "?") or "standing not known yet"), facts = {} }
  v.next.blocker = v.next.line
  return v
end

-- Mage Research (mages on WoW Forever): its skill line, when the game lists one (the name is unconfirmed: any "Research" line)
function PUI:ResearchSkill()
  local PF = Panoply.ProfForever
  local match = PF and PF.MAGE_RESEARCH_MATCH or "Research"
  for _, s in ipairs(C.GetSkills()) do
    if type(s.name) == "string" and s.name:find(match, 1, true) then return s end
  end
  return nil
end
function PUI:ResearchView()
  local s = self:ResearchSkill()
  local v = { kind = "research", name = "Mage Research", rows = {}, rank = s and s.rank, max = s and s.max }
  v.rows[#v.rows + 1] = head("Mage Research")
  v.rows[#v.rows + 1] = row({ text = s and ("Skill %d / %d"):format(s.rank or 0, s.max or 0) or "Not learned yet", right = "", done = s ~= nil })
  v.rows[#v.rows + 1] = row({ text = "Panoply has no plan for Mage Research yet (unverified data).", right = "", note = true })
  v.next = { kind = "none", title = s and ("Mage Research %d / %d"):format(s.rank or 0, s.max or 0) or "Mage Research not learned yet",
    line = "No plan yet: what raises it is not confirmed.", facts = {} }
  v.next.blocker = v.next.line
  return v
end
function PUI:ShowResearch()
  local info = C.PlayerInfo and C.PlayerInfo() or {}
  return C.IsForever() and info.classFile == "MAGE"
end

-- the secondaries not picked up, and whether a primary slot is open
function PUI:NotLearned()
  local mine = {}
  for _, n in ipairs(self:Chosen()) do mine[n] = true end
  local out = {}
  for _, n in ipairs(PUI.SECONDARY) do if not mine[n] then out[#out + 1] = n end end
  local prim = 0
  for _, n in ipairs(Panoply.cdb and Panoply.cdb.professions and Panoply.cdb.professions.primary or {}) do
    local r = PR():CurrentSkill(n)
    if r then prim = prim + 1 end
  end
  return out, prim < 2
end

-- the profession's icon: the game's texture of its first rank spell, else the standard icon file
PUI.ICON_FILES = {
  Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving", Engineering = "Trade_Engineering",
  Leatherworking = "INV_Misc_ArmorKit_17", Tailoring = "Trade_Tailoring", Cooking = "INV_Misc_Food_15", ["First Aid"] = "Spell_Holy_SealOfSacrifice",
  Herbalism = "Trade_Herbalism", Mining = "Trade_Mining", Skinning = "INV_Misc_Pelt_Wolf_01", Fishing = "Trade_Fishing",
  ["Mage Research"] = "INV_Misc_Book_09", ["Trade camp"] = "INV_Misc_Bag_10",
}
for n, f in pairs(PUI.ICON_FILES) do
  Panoply.Kit.RegisterIcon("icon.profession." .. n:lower():gsub("[^%w]", ""), { game = { "Interface\\Icons\\" .. f } })
end
Panoply.Kit.RegisterIcon("icon.trade.alliance", { game = { "Interface\\Icons\\INV_BannerPVP_02" } })
Panoply.Kit.RegisterIcon("icon.trade.horde", { game = { "Interface\\Icons\\INV_BannerPVP_01" } })
Panoply.Kit.RegisterIcon("icon.currency.favor", { game = { "Interface\\Icons\\INV_Misc_Coin_17" } })
-- 0.9.9.4 hotfix ("our profession window has icons that look like jewelcrafting. how about we use the correct icon for the
-- profession"): the profession's own Blizzard icon (ICON_FILES) comes first. Asking WoW Forever for the profession spell's
-- picture gave gem pictures (our screenshot, Nov 22), so the spell lookup is only for a profession without one here.
function PUI.IconFor(name)
  local file = PUI.ICON_FILES[name or ""]
  if file then return "Interface\\Icons\\" .. file end
  local prof = PD[name or ""]
  local spell = prof and prof.ranks and prof.ranks[1] and prof.ranks[1].spell
  local t = spell and Panoply.Icons:Spell(spell)   -- 0.9.7 hotfix: the one shared lookup; the game's "?" is not an answer
  return t or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Kept for /panoply and older callers: a short plain summary.
function PUI:Summary(name)
  local v = self:View(name)
  return { name = name, skill = v.skill, milestone = v.next and v.next.title, train = v.bar, cost = v.total, note = v.note, plan = v.plan }
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Shared pieces the page (UI/ProfPage.lua) draws with
-------------------------------------------------------------------------------
-- The page itself is UI/ProfPage.lua (0.9.5 phase 4B: the list of professions beside one profession's detail). The profession window
-- (Modules/ProfWindow) is a separate window and is not changed by this page.
local function arrowButton(parent, fn)
  local b = Skin.IconButton(parent, "", 20, fn, "Point the arrow here", "The arrow (and the guide window's compass) points at this place until you get there.")
  -- skin v3: the route glyph (a J icon in Panoply Suite style)
  b:SetIcon("Arrow", 14)
  return b
end
PUI.ArrowButton = arrowButton

function PUI:PointAt(spot, label)
  if not spot or not spot.map then return end
  -- 0.9.5 phase 4K (spec 05 6): the place also goes in the Map page's Professions group of waypoints (once), unless Waypoints is off
  local Way = Panoply.Waypoints
  if Way and Way.Add and Panoply.Modules:IsOn("waypoints") then
    local have = false
    local x, y = spot.x, spot.y
    if x and y and (x > 1 or y > 1) then x, y = x / 100, y / 100 end
    for _, wp in ipairs(Way:List()) do
      if wp.m == spot.map and x and y and math.abs(wp.x - x) < 0.0002 and math.abs(wp.y - y) < 0.0002 then have = true break end
    end
    if not have then Way:Add(spot.map, spot.x, spot.y, label or spot.name, true, "prof") end
  end
  Panoply.Arrow:PointAt(spot.map, spot.x, spot.y, label or spot.name)
  Panoply:Print("Arrow: " .. (label or spot.name or "there") .. " in " .. mapName(spot.map) .. ".")
end

-- 0.8.1: a "visit a trainer" row of a profession you know opens our profession window for it. Opening a
-- profession is a spell cast, which only secure code may do, so each row has a SecureActionButtonTemplate
-- laid over its text (the arrow button stays clear of it). The game's window that the cast opens is hidden
-- by the Profession window module, which shows ours. Secure buttons cannot be made or changed in combat: a
-- row drawn in combat simply has none (its text and arrow still work), and the page is drawn again when
-- combat ends so it gets one.
function PUI:OpenButton(r, parent)
  if r.open then return r.open end
  if C.InCombat() then return nil end
  local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
  if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
  -- 0.9.6 phase K ("Open Leatherworking" did nothing): with useOnKeyDown unset the game acts on the press (its
  -- ActionButtonUseKeyDown setting, on by default), and this button is handed the release only, so no click ever cast the spell.
  -- It acts on the release now, whatever that setting says (the same fix as phase F's Turn off button).
  b:SetAttribute("useOnKeyDown", false)
  b:SetFrameLevel((r.tipFrame:GetFrameLevel() or 1) + 2)
  b:SetScript("OnEnter", function(self)
    if r.tipFrame.panoplyShowTip and r.tipFrame.tip then r.tipFrame.panoplyShowTip() end
  end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b.panoplyLayoutSkip = true
  b:Hide()
  r.open = b
  return b
end
function PUI:SetOpen(r, parent, prof)
  local b = self:OpenButton(r, parent)
  if prof and not b then self.secureMissing = true end
  if not b or C.InCombat() then return end
  r.openProf = prof
  local spell = prof and Panoply.ProfWindow and Panoply.ProfWindow:SpellFor(prof) or nil
  b:SetAttribute("type", spell and "spell" or nil)
  b:SetAttribute("spell", spell)
  b.panoplyProf = prof
  if spell then b:Show() else b:Hide() end
  if spell and r.tipFrame.tip then
    r.tipFrame.tipBody = ((r.tipFrame.tipBody and (r.tipFrame.tipBody .. " ") or "") .. "Click to open your " .. prof .. " window.")
  end
end
function PUI:PlaceOpen(r, parent, x, y, w, h)
  local b = r.open
  if not b or C.InCombat() then return end
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); b:SetSize(w, h)
end

-- Guide me: this profession's next step in the guide window (name: the profession; nil = the one the page last showed)
function PUI:GuideMe(name)
  name = name or self.selected
  if not name then return end
  local G = Panoply.ProfGuide
  if G:Tracked() ~= name then G:SetTracked(name) end
  if G:Active() == "leveling" then G:SetActive("professions", name) end
  G:Force()
  Panoply.UI:Show()
end


