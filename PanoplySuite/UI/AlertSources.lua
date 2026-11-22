-- Panoply Suite 0.9.5, phase 4A3: what the pages of today publish to the shared alerts registry (Core/Alerts.lua), and the one
-- on / off setting of each kind, in the publishing page's settings ("Alerts" section). Spec 05 section 2 lists the publishers:
--   Class        spells to buy, talent points waiting                     (Class & Spec's data; the Class page takes it over in 4H)
--   Legacy       unspent Legacy points on this character                  (WoW Forever only)
--   Muster       bags full or under 3 free slots, mail expiring within 3 days, COD mail, rested XP full (estimated)
--   Auctions     the saved scan is older than 3 days
--   Professions  a new rank is ready to learn ("Train now")
--   Guide        the next step needs a group
-- Blueprint dropped (Professions) came with phase 4B. Phase 4I (Muster, spec 02 2.3) adds auctions sold or expired waiting in the mail
-- and cooldowns ready, and makes the mail warning's days a setting of Muster's (hallMailDays, 3 by default).
-- Every number comes from the same place the owning page reads it from; nothing is worked out a second way here.
local ADDON, Panoply = ...
local A, Cat, C = Panoply.Alerts, Panoply.Catalog, Panoply.Compat

local DAY = 86400
A.BAGS_FREE_MIN = 3        -- Muster: "bags full or under 3 free slots"
A.MAIL_DAYS = 3            -- Muster: mail expiring within this many days (spec 02's default threshold)
A.SCAN_DAYS = 3            -- Auctions: "scan older than 3 days"

local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end
local function money(c)
  local ST = Panoply.SpecTrainer
  if ST and ST.Money then return ST.Money(c) end
  return Panoply.Home and Panoply.Home.Gold and Panoply.Home.Gold(c) or tostring(c)
end
local function now() return (_G.time and time()) or 0 end
local function pageHere(key) return Cat[key] ~= nil and Cat:PageExists(Cat[key]) end

-------------------------------------------------------------------------------
-- The kinds (and their settings)
-------------------------------------------------------------------------------
A:Kind("talentPoints", { page = "class", severity = "act", label = "Talent points waiting",
  tip = "Tell me when I have a talent point to spend.", words = "alert talent point waiting spend" })
A:Kind("spellsToBuy", { page = "class", severity = "act", label = "Spells to buy at the trainer",
  tip = "Tell me when my class trainer has spells for me.", words = "alert spells buy trainer waiting" })
A:Kind("legacyPoints", { page = "legacy", severity = "act", label = "Legacy points to spend",
  tip = "Tell me when this character has Legacy points it has not spent.", words = "alert legacy points perk unspent" })
A:Kind("bagsFull", { page = "hall", severity = "act", label = "Bags full",
  tip = "Tell me when a character's bags are full or have fewer than 3 free slots.", words = "alert bags full free slots space" })
A:Kind("mailExpiring", { page = "hall", severity = "act", label = "Mail about to expire",
  tip = "Tell me when a character has mail that runs out soon (3 days unless you change it below; as of its last mailbox visit).",
  words = "alert mail expire expiring mailbox letters days" })
A:Kind("mailCOD", { page = "hall", severity = "act", label = "Cash on delivery mail",
  tip = "Tell me when a character has mail waiting that has to be paid for (COD).", words = "alert mail cod cash on delivery pay" })
A:Kind("restedFull", { page = "hall", severity = "info", label = "Rested XP full",
  tip = "Tell me when another character's rested experience is full (estimated while it is offline).", words = "alert rested xp full experience" })
-- 0.9.5 phase 4I: the two kinds whose data Muster saves from this phase on
A:Kind("auctionMail", { page = "hall", severity = "act", label = "Auctions waiting in the mail",
  tip = "Tell me when a character has gold from a sale, or an item that did not sell, waiting in its mailbox.",
  words = "alert auction sold expired mail waiting collect" })
A:Kind("cooldownReady", { page = "hall", severity = "info", label = "Cooldowns ready",
  tip = "Tell me when a profession cooldown, a camp object or Dedicated Study is ready again on one of my characters.",
  words = "alert cooldown ready transmute camp dedicated study" })
A:Kind("auctionScan", { page = "auctions", severity = "act", label = "Old auction prices",
  tip = "Tell me when the saved auction scan is more than 3 days old.", words = "alert auction scan old prices stale" })
A:Kind("trainNow", { page = "professions", severity = "act", label = "Profession rank ready to learn",
  tip = "Tell me when a profession trainer can teach me the next rank.", words = "alert profession train rank journeyman expert artisan" })
-- 0.9.5 phase 4B: a Blueprint in the bags for a camp object this character has not learned yet (WoW Forever only: Classic has no camp)
if C.IsForever() then
  A:Kind("blueprintDropped", { page = "professions", severity = "act", label = "Blueprint to learn",
    tip = "Tell me when I carry a camp Blueprint for one of my professions that I have not learned yet.", words = "alert blueprint camp object learn drop" })
  -- its switch, on by default (a NEW key, WoW Forever only like the kind)
  if Panoply.defaults and Panoply.defaults.account and Panoply.defaults.account.alertBlueprintDropped == nil then Panoply.defaults.account.alertBlueprintDropped = true end
end
A:Kind("stepGroup", { page = "guide", severity = "act", label = "Next step needs a group",
  tip = "Tell me when the guide's next step is a quest for a group.", words = "alert group elite quest step party" })

-- the "Alerts" section in each publishing page's settings: one tick per kind, in the order above
do
  local items = Panoply.SettingsUI and Panoply.SettingsUI.items
  local pages, order = {}, {}
  for _, key in ipairs(A.kindOrder) do
    local k = A.kinds[key]
    if items then
      local have = false
      for _, it in ipairs(items) do if it[1] == k.setting then have = true end end
      if not have then items[#items + 1] = { k.setting, k.label, k.tip } end
    end
    if Cat.WORDS then Cat.WORDS[k.setting] = k.words end
    if not pages[k.page] then pages[k.page] = {} order[#order + 1] = k.page end
    table.insert(pages[k.page], { k.setting, k.label })
  end
  for _, pk in ipairs(order) do
    local page = Cat[pk]
    if page then
      page.sections = page.sections or {}
      local have = false
      for _, s in ipairs(page.sections) do if s.key == "alerts" then have = true end end
      if not have then
        page.sections[#page.sections + 1] = { key = "alerts", title = "Alerts",
          text = "What shows on Home under Needs you, and as a dot beside this page in the list. Switched off here, it is hidden everywhere.",
          rows = pages[pk] }
      end
    end
  end
  Cat.reg = nil
  local keys = {}
  for _, key in ipairs(A.kindOrder) do keys[#keys + 1] = A.kinds[key].setting end
  if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys(keys) end
end

-------------------------------------------------------------------------------
-- Openers: the pages whose target is a tab or a character
-------------------------------------------------------------------------------
-- 0.9.5 phase 4H: talent points and spells to buy open the Class page's Talents and Spells tabs (Class & Spec is part of it now)
A:Opener("class", function(t)
  local CP = Panoply.ClassPages
  if CP and CP.Open then CP:Open(nil, t.tab or "overview") else Panoply.Menu:Open("class") end
end)
A:Opener("legacy", function(t)
  local L = Panoply.Legacy
  if L and L.Open then L:Open(t.tab or "plan") else Panoply.Menu:Open("legacy") end
end)
A:Opener("professions", function(t)
  local PUI = Panoply.ProfUI
  if t.tab and PUI then PUI.page = t.tab end
  if PUI and PUI.Show and type(t.state) == "string" then PUI:Show(t.state) else Panoply.Menu:Open("professions") end
end)
A:Opener("hall", function(t)
  local Al, s = Panoply.Alts, t.state
  if Al and Al.active and type(s) == "table" and s.realm and s.name then Al:Open(s.realm, s.name, s.tab) else Panoply.Menu:Open("hall") end
end)
-- the mail warning's days: Muster's setting (spec 02 2.4), 1 to 7
function A.MailDays()
  local d = tonumber(Panoply.db and Panoply.db.hallMailDays) or A.MAIL_DAYS
  return math.max(1, math.min(7, math.floor(d)))
end

-------------------------------------------------------------------------------
-- Class: talent points and spells to buy (the numbers Home always showed, from Class & Spec)
-------------------------------------------------------------------------------
A:Source("class", function()
  local out = {}
  local ST = Panoply.SpecTrainer
  if not (ST and Panoply.Modules:IsOn("spectrainer") and pageHere("class")) then return out end
  local me = A:MyKey()
  local points = ST:UnspentPoints() or 0
  if points > 0 then
    local detail = "Open the Talents tab to see your next talent."
    local n = ST:Next()
    if n and n.tal then detail = ("Next: %s, rank %d of %d."):format(n.tal.name, n.rank, n.tal.ranks) end
    out[#out + 1] = { id = "talentPoints", severity = "act", icon = "Train", characterKey = me,
      text = points == 1 and "A talent point is waiting" or ("%d talent points are waiting"):format(points), detail = detail,
      target = { page = "class", tab = "talents" } }
  end
  local p = ST:Player()
  local w = ST:Waiting(p)
  if w and #w.list > 0 then
    out[#out + 1] = { id = "spellsToBuy", severity = "act", icon = "Train", characterKey = me,
      text = ("%d %s to buy at the trainer"):format(#w.list, plural(#w.list, "spell")),
      detail = ("%s of your %s."):format(money(w.cost), money(p.money)),
      target = { page = "class", tab = "spells" } }
  end
  return out
end)

-------------------------------------------------------------------------------
-- Legacy: points this character has not spent (the page's own meter)
-------------------------------------------------------------------------------
A:Source("legacy", function()
  local L = Panoply.Legacy
  if not (L and L.Here and L:Here() and pageHere("legacy")) then return {} end
  -- reading the meter makes Legacy's saved table when there is none (L:Store); an alert only reads, so it waits until Legacy has one
  local st = Panoply.db.foreverLegacy
  if type(st) ~= "table" or st.v == nil then return {} end
  for _, k in ipairs({ "earned", "done", "cosmetics", "chars" }) do if type(st[k]) ~= "table" then return {} end end
  local m = L:Meter()
  local left = math.min(m.points, m.cap) - m.spent
  if left <= 0 then return {} end
  return { { id = "legacyPoints", severity = "act", icon = "Star", characterKey = A:MyKey(),
    text = ("%d Legacy %s to spend"):format(left, plural(left, "point")),
    detail = ("%d of %d spent on this character."):format(m.spent, m.cap), target = { page = "legacy", tab = "plan" } } }
end)

-------------------------------------------------------------------------------
-- Muster: bags, mail and rested XP, for every saved character (Hearth Hall's saved data; this character's bags live)
-------------------------------------------------------------------------------
-- when the next letter still in the mailbox runs out: the earliest time after `t` (0.9.5 phase 17: after the first letter ran out the
-- warning went quiet even when another one ran out soon; mail saved before 0.9.5 has only the first letter's time)
function A.MailExpiry(rec, t)
  local m = type(rec) == "table" and type(rec.mail) == "table" and rec.mail
  if not m or (tonumber(m.n) or 0) <= 0 then return nil end
  local first = tonumber(m.expires)
  if not t then return first end
  local soon = first and first > t and first or nil
  for _, l in ipairs(type(m.letters) == "table" and m.letters or {}) do
    local e = type(l) == "table" and tonumber(l.expires)
    if e and e > t and (not soon or e < soon) then soon = e end
  end
  return soon
end

A:Source("muster", function()
  local out = {}
  local Al = Panoply.Alts
  if not (Al and Al.active and pageHere("hall")) then return out end
  local t = now()
  local guess = not (Panoply.db and Panoply.db.hallRestGuess == false)
  -- Alts:List makes Muster's saved table when there is none yet; an alert only reads, so before Muster has saved anything it looks
  -- at this character alone (its bags are read from the game)
  local list
  local a = Panoply.db.alts
  if type(a) == "table" and type(a.realms) == "table" and a.v ~= nil then list = Al:List()
  else
    local realm, name = Al:Me()
    list = realm and { { realm = realm, name = name, me = true } } or {}
  end
  for _, e in ipairs(list) do
    local key = A.CharKey(e.realm, e.name)
    local who = e.me and "your" or (e.name .. "'s")
    local function target(tab) return { page = "hall", state = { realm = e.realm, name = e.name, tab = tab } } end
    -- bags
    local used, total
    if e.me then
      local b = Panoply.Home and Panoply.Home.BagState and Panoply.Home.BagState()
      if b then used, total = b.used, b.total end
    else
      used, total = Al:SlotUse(e, "bags")
    end
    if total and total > 0 then
      local free = total - used
      if free < A.BAGS_FREE_MIN then
        out[#out + 1] = { id = "bagsFull:" .. key, severity = "act", icon = "Bags", characterKey = key, target = target("bags"),
          text = free <= 0 and ("Bags full: %s"):format(e.me and "this character" or e.name)
            or ("%d free bag %s: %s"):format(free, plural(free, "slot"), e.me and "this character" or e.name),
          detail = ("%d of %d slots used in %s bags."):format(used, total, who) }
      end
    end
    -- mail
    local exp = A.MailExpiry(e.rec, t)
    if exp and exp > t and exp - t < A.MailDays() * DAY then
      local d = math.floor((exp - t) / DAY)
      out[#out + 1] = { id = "mailExpiring:" .. key, severity = "act", icon = "Bank", characterKey = key, target = target("mail"),
        text = ("Mail expires %s: %s"):format(d < 1 and "within a day" or ("in %d %s"):format(d, plural(d, "day")), e.me and "this character" or e.name),
        detail = "Open the mailbox and take what you want to keep." }
    end
    local cod = e.rec and type(e.rec.mail) == "table" and tonumber(e.rec.mail.cod) or 0
    if cod > 0 then
      out[#out + 1] = { id = "mailCOD:" .. key, severity = "act", icon = "Bank", characterKey = key, target = target("mail"),
        text = ("%d cash on delivery %s: %s"):format(cod, plural(cod, "letter"), e.me and "this character" or e.name),
        detail = "Pay for it or send it back at a mailbox." }
    end
    -- rested XP, for the characters that are not being played
    if not e.me and e.rec then
      local pct, guessed = Al.RestedPercent(e.rec, t, guess)
      if pct and pct >= Al.RestCap(e.rec) then
        out[#out + 1] = { id = "restedFull:" .. key, severity = "info", icon = "Character", characterKey = key, target = target("overview"),
          text = ("Rested XP is full: %s"):format(e.name),
          detail = guessed and "Estimated from the time it has been offline." or "As it was when you last played it." }
      end
    end
    -- 0.9.5 phase 4I: auction house letters (as of the last mailbox visit)
    local m = e.rec and type(e.rec.mail) == "table" and e.rec.mail
    local sold, expired = m and tonumber(m.ahSold) or 0, m and tonumber(m.ahExpired) or 0
    if sold + expired > 0 then
      local bits = {}
      if sold > 0 then bits[#bits + 1] = ("%d sold"):format(sold) end
      if expired > 0 then bits[#bits + 1] = ("%d did not sell"):format(expired) end
      out[#out + 1] = { id = "auctionMail:" .. key, severity = "act", icon = "Auctions", characterKey = key, target = target("mail"),
        text = ("%d auction %s in the mail: %s"):format(sold + expired, plural(sold + expired, "letter"), e.me and "this character" or e.name),
        detail = table.concat(bits, ", ") .. ". As of the last mailbox visit." }
    end
    -- 0.9.5 phase 4I: cooldowns that are ready again (as the game showed them when the character was last played)
    for _, cd in ipairs(e.rec and type(e.rec.cds) == "table" and e.rec.cds or {}) do
      if type(cd) == "table" and tonumber(cd.ready) and cd.ready <= t then
        local tgt = target("overview")
        if e.me and cd.kind == "legacy" and pageHere("legacy") then tgt = { page = "legacy", tab = "plan" }
        elseif e.me and cd.kind == "camp" and cd.prof and pageHere("professions") then tgt = { page = "professions", tab = "Camp", state = cd.prof } end
        out[#out + 1] = { id = "cooldownReady:" .. key .. ":" .. tostring(cd.name), severity = "info", icon = "Professions", characterKey = key,
          target = tgt, text = ("%s is ready: %s"):format(tostring(cd.name), e.me and "this character" or e.name),
          detail = cd.prof and ("%s cooldown."):format(cd.prof) or "Legacy perk." }
      end
    end
  end
  return out
end)

-------------------------------------------------------------------------------
-- Auctions: the saved scan is old (the time the Auctions page and Home show)
-------------------------------------------------------------------------------
function A.ScanTime()
  local P = Panoply.Prices
  if not P then return 0 end
  local last = 0
  local adb = _G.PanoplySuiteAuctionDB
  local r = type(adb) == "table" and type(adb.realms) == "table" and adb.realms[P.Key()]
  if r then last = tonumber(r.lastScan) or 0 end
  local rec = Panoply.Auctions and Panoply.Auctions.Record
  if rec then last = rec.ScanTime(P.Key()) or last end
  return last
end

A:Source("auctions", function()
  if not pageHere("auctions") then return {} end
  local last = A.ScanTime()
  if last <= 0 then return {} end
  local age = now() - last
  if age <= A.SCAN_DAYS * DAY then return {} end
  local d = math.floor(age / DAY)
  return { { id = "auctionScan", severity = "act", icon = "Auctions",
    text = ("Auction prices are %d %s old"):format(d, plural(d, "day")),
    detail = "Scan at the auction house to bring them up to date.", target = { page = "auctions" } } }
end)

-------------------------------------------------------------------------------
-- Professions: the next rank can be learned now (the rule the Trainer Helper's profession panel uses)
-------------------------------------------------------------------------------
A:Source("professions", function()
  local out = {}
  local G, PR, PD = Panoply.ProfGuide, Panoply.Professions, Panoply.ProfData
  if not (G and PR and PD and pageHere("professions")) then return out end
  local level = (Panoply.State and Panoply.State.level) or (C.XP and C.XP()) or 0
  local PUI = Panoply.ProfUI
  for _, name in ipairs(G:Chosen()) do
    local skill, max = PR:CurrentSkill(name)
    if skill and max and max > 0 then
      local _, rk = PR:RankFor(PD[name], max)
      -- 0.9.5 phase 4B: the same rank gate the Professions page shows (on WoW Forever its own skill and level per rank)
      local g = PUI and PUI.Gate and PUI:Gate(name, skill, max)
      local ready
      if g then ready = g.skillOK and g.levelOK else ready = rk and skill >= (rk.minSkill or 0) and level >= (rk.minLevel or 0) end
      if rk and ready then
        out[#out + 1] = { id = "trainNow:" .. name, severity = "act", icon = "Professions", characterKey = A:MyKey(),
          text = ("Train now: %s %s"):format(rk.name, name),
          detail = rk.source == "book" and ("Up to skill %d. %s teaches it (%s)."):format(rk.max, rk.bookName or "A book", money((rk.fee or 0) * 100))
            or rk.source == "quest" and ("Up to skill %d. A quest teaches it: %s."):format(rk.max, rk.questTitle or "see the guide")
            or ("Up to skill %d, for %s, at a %s trainer."):format(rk.max, money((rk.fee or 0) * 100), name),
          target = { page = "professions", state = name } }
      end
    end
  end
  -- a camp Blueprint in the bags that this character has not learned (the bags first; the spellbook only when one is there)
  local PF, PC = Panoply.ProfForever, Panoply.ProfCamp
  if C.IsForever() and PF and PC then
    local items = PC:BagItems()
    local any = false
    for n in pairs(items) do if n:find("Blueprint", 1, true) then any = true break end end
    if any then
      local snap
      for _, name in ipairs(G:Chosen()) do
        local skill = PR:CurrentSkill(name)
        for _, o in ipairs(PF.CampOf(name) or {}) do
          if o.blueprint then
            local has = false
            for n, c in pairs(items) do if c > 0 and n:find("Blueprint", 1, true) and n:find(o.name, 1, true) then has = true end end
            if has then
              snap = snap or { spells = PC:Spells(), items = items }
              if not snap.spells[o.name] then
                out[#out + 1] = { id = "blueprintDropped:" .. name .. ":" .. o.name, severity = "act", icon = "Professions", characterKey = A:MyKey(),
                  text = ("Blueprint to learn: %s (%s)"):format(o.name, name),
                  detail = (skill or 0) >= (o.skill or 0) and "It is in your bags. Use it to learn the camp object."
                    or ("It is in your bags. %s %d learns it."):format(name, o.skill or 0),
                  target = { page = "professions", tab = "Camp", state = name } }
              end
            end
          end
        end
      end
    end
  end
  return out
end)

-------------------------------------------------------------------------------
-- Guide: the next step is a quest for a group, and you are not in one
-------------------------------------------------------------------------------
A:Source("guide", function()
  local E, D, ST = Panoply.Engine, Panoply.Difficulty, Panoply.StepText
  if not (E and D and ST) or Panoply:PlayAlong() then return {} end
  if C.InGroup and C.InGroup() then return {} end
  local cur = E.steps and E.steps[E.index]
  if not cur then return {} end
  local ids = {}
  if cur.questID then ids[#ids + 1] = cur.questID end
  for _, g in ipairs(cur.goals or {}) do
    if g.questID and (g.type == "complete" or g.type == "objective") then ids[#ids + 1] = g.questID end
  end
  for _, id in ipairs(ids) do
    if D.IsGroup(id) then
      local name
      for _, q in ipairs(ST.Quests(cur)) do if q.id == id then name = q.name end end
      return { { id = "stepGroup", severity = "act", icon = "Party", characterKey = A:MyKey(),
        text = "Your next step needs a group",
        detail = name and ("%s is a quest for a group."):format(name) or "It is a quest for a group.", target = { page = "guide" } } }
    end
  end
  return {}
end)
