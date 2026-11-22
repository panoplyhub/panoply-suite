-- Panoply Suite: the Home page, the first page of the window and the one that opens first.
-- 0.9.5 phase 4K: redrawn to docs/specs/page-redesigns-05-home-guide-map.md section 3.
--   Next step    full width, from the Guide: the step type icon, the headline, where, how far, "Step 5 of 27 · Westfall" and a button
--                that points the arrow there. A click opens the Guide.
--   Needs you    the "act" alerts of the shared registry (Core/Alerts.lua), this character's first; each opens what it is about.
--                Nothing there: "Nothing needs you."
--   At a glance  a tile each: Gold (Muster's account total and its 7-day change), This session (Field Kit), Legacy (WoW Forever),
--                Prices (the age of the Auctions page's scan, in its freshness colour), Bags (free slots), Next upgrade (the Class
--                page's Gear tab). Which tiles show is set in Home's gear; the ? says so.
-- Every number comes from the page that owns it, with that page's own words (spec 05 section 3.1): Muster's coins and change,
-- the Auctions page's scan time and freshness, the Class page's gear grid. A tile whose source is not in this build is left out.
local ADDON, Panoply = ...
local Menu, Skin, C = Panoply.Menu, Panoply.Skin, Panoply.Compat
local Home = {}
Panoply.Home = Home
local SP, TH = Skin.SP, Skin.TextHeight

Panoply.defaults.account.homeLegacy = true
Panoply.defaults.account.homeUpgrade = true
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "homeLegacy", "homeUpgrade" }) end

-- the tiles' icon slots (spec 05 section 7): each reuses the icon of the page it opens; in WoW icons a game icon (Skin.GAME_ICONS key)
if Panoply.Kit and Panoply.Kit.RegisterIcon then
  local WOW = { ["icon.tile.gold"] = "Coin", ["icon.tile.session"] = "Modules", ["icon.tile.legacy"] = "Star",
    ["icon.tile.prices"] = "Auctions", ["icon.tile.bags"] = "Bags", ["icon.tile.upgrade"] = "Character" }
  for slot, icon in pairs({ ["icon.tile.gold"] = "MenuMuster", ["icon.tile.session"] = "MenuMisc", ["icon.tile.legacy"] = "MenuLegacy",
      ["icon.tile.prices"] = "MenuAuctions", ["icon.tile.bags"] = "MenuMuster", ["icon.tile.upgrade"] = "MenuClass" }) do
    Panoply.Kit.RegisterIcon(slot, { icon = icon, own = true, wow = WOW[slot] })
  end
end

-- 0.9.6 items 4 and 5. PLACEHOLDER COPY (Marketing): the setup line and the off switch at the foot of the page
Home.SETUP_TITLE = "Set up %s"
Home.SETUP_SUB = "A few quick questions, then your route is ready."
Home.SETUP_HELP = "Opens the short setup for this character."
Home.OFF_TEXT = "Turn Panoply Suite off"
Home.OFF_TIP = "Turns Panoply Suite off (the game reloads its interface). Nothing is lost, and the game's AddOns list turns it back on."

-- bags are "nearly full" when this few slots are free: a tenth of them, and never fewer than two
function Home.NearlyFull(free, total) return total > 0 and free <= math.max(2, math.ceil(total / 10)) end

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------
local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
-- "4g 85s", "85s 12c", "9c" (the copper is left off once there is gold)
function Home.Gold(copper)
  copper = math.max(0, math.floor(tonumber(copper) or 0))
  local g, s, k = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return commas(g) .. "g " .. s .. "s" end
  if s > 0 then return s .. "s " .. k .. "c" end
  return k .. "c"
end
local function money(c) local ST = Panoply.SpecTrainer return ST and ST.Money and ST.Money(c) or Home.Gold(c) end

-- "just now", "35 minutes ago", "2 hours ago", "3 days ago"
function Home.Ago(t, now)
  now = now or (_G.time and time() or 0)
  local s = now - (t or 0)
  if s < 90 then return "just now" end
  if s < 90 * 60 then return ("%d minutes ago"):format(math.floor(s / 60 + 0.5)) end
  if s < 36 * 3600 then local h = math.floor(s / 3600 + 0.5) return ("%d hour%s ago"):format(h, h == 1 and "" or "s") end
  local d = math.floor(s / 86400 + 0.5)
  return ("%d day%s ago"):format(d, d == 1 and "" or "s")
end

-------------------------------------------------------------------------------
-- The data (also read by the previews and the tests)
-------------------------------------------------------------------------------
-- slots in the bags: used, total, the grey items with what they would sell for
function Home.BagState()
  local used, total, junkN, junkCopper = 0, 0, 0, 0
  for _, bag in ipairs(C.BagIDs()) do
    local size = C.NumSlots(bag) or 0
    total = total + size
    for slot = 1, size do
      local i = C.SlotInfo(bag, slot)
      if i and i.itemID then
        used = used + 1
        if i.quality == 0 then
          local ii = C.ItemInfo(i.link or i.itemID)
          if ii and (ii.sellPrice or 0) > 0 then junkN = junkN + 1; junkCopper = junkCopper + ii.sellPrice * (i.count or 1) end
        end
      end
    end
  end
  return { used = used, total = total, free = total - used, junk = junkN, junkCopper = junkCopper }
end

-- the Guide's next step, as the Guide page shows it
local function nextLine()
  if Panoply:PlayAlong() then return nil end
  local E, S, ST = Panoply.Engine, Panoply.State, Panoply.StepText
  local cur = E:Current()
  local line = { key = "next", group = "next", icon = "Leveling", page = "guide", pageLabel = "Guide",
    help = "Opens the Guide: your next step, and the route to your goal." }
  if Panoply:NoGuideHere() then
    line.title, line.sub = "No guide for this area yet.", "The Guide page has Record mode and a way to a place with a guide."
    return line
  end
  if cur then
    line.step = cur
    line.slot = ST.TypeSlot(cur)
    line.title = ST.Headline(cur)
    local parts = {}
    local loc = ST.LocationNote(cur)
    local info = Panoply.Arrow and Panoply.Arrow.last
    local d = info and info.target and ST.Distance(info.yards, info.otherZone) or ""
    if loc and loc ~= "" then parts[#parts + 1] = loc elseif S.zone and S.zone ~= "" then parts[#parts + 1] = S.zone end
    if d ~= "" and d ~= "-" then parts[#parts + 1] = d end        -- "850 yd away", "You are here", "In Elwynn Forest"
    local num = ST.NumberText(cur)
    if num ~= "" then parts[#parts + 1] = num end
    line.sub = table.concat(parts, " · ")
  elseif Panoply.cdb and Panoply.cdb.setupDone == false and Panoply.Wizard then
    -- 0.9.6 item 5: a character that has not been set up yet (the welcome page was closed): Next step is the setup
    local name = Panoply.Wizard.CharName and Panoply.Wizard:CharName() or "this character"
    line.key, line.page, line.pageLabel = "setup", nil, "Setup"
    line.title, line.sub = (Home.SETUP_TITLE):format(name), Home.SETUP_SUB
    line.help = Home.SETUP_HELP
    line.open = function() Panoply.Wizard:Start() end
  else
    local head, sub = ST.WhatNow()
    line.title, line.sub = head, sub
  end
  return line
end

-- 0.9.5 phase 4A3: Needs you is the shared alerts registry (Core/Alerts.lua): its "act" alerts, this character's first, then the
-- account-wide ones and the other characters'. Home works nothing out itself; the pages publish (UI/AlertSources.lua).
function Home.NeedLines()
  local out = {}
  local A = Panoply.Alerts
  if not A then return out end
  -- worked out again now, except in a fight (Home redraws on every loot; the alerts then wait for the fight to end, Core/Alerts.lua)
  if not C.InCombat() then A:Refresh() end
  local Cat = Panoply.Catalog
  for _, a in ipairs(A:List({ severity = "act" })) do
    local pk = a.target and a.target.page or a.page
    local page = pk and Cat[pk]
    local label = page and page.label or ""
    out[#out + 1] = { key = a.id, group = "needs", icon = a.icon or (page and page.icon) or "Modules", page = pk, pageLabel = label,
      title = a.text, sub = a.detail or "", alert = a, open = function() A:Open(a) end,
      help = label ~= "" and ("Opens " .. label .. ".") or nil }
  end
  return out
end
local needLines = Home.NeedLines

-- open a page (with its tab) as one Back / Forward step (the alerts registry's opener does the history)
local function opener(target)
  return function()
    local A = Panoply.Alerts
    if A and A.Open then A:Open({ id = "home:" .. tostring(target.page), target = target }) else Panoply.Menu:Select(target.page) end
  end
end
local function pageHere(key) local Cat = Panoply.Catalog return Cat[key] ~= nil and Cat:PageExists(Cat[key]) end

-- the tiles: { key, group = "glance", icon, slot, title (the big value), sub (the muted line), label (what it is), page, pageLabel,
-- open, color (a token for the value) }
function Home.Tiles()
  local out = {}
  local db = Panoply.db or {}
  -- Gold: Muster's account total and its 7-day change, with Muster's coins
  if db.homeGold ~= false and pageHere("hall") then
    local Al = Panoply.Alts
    local H = Al and Al.Hall
    local total, change
    if Al and Al.active and Al.GoldChange then
      local ok, t, ch = pcall(Al.GoldChange, Al, 7)
      if ok then total, change = t, ch end
    end
    local t = { key = "gold", group = "glance", icon = "Coin", slot = "icon.tile.gold", label = "Gold", page = "hall", pageLabel = "Muster",
      help = "Every character's gold together, as Muster shows it. Opens Muster.", open = opener({ page = "hall" }) }
    if total and H then
      t.title = H.Coins(total, true)
      local ct = H.ChangeText(change)
      t.sub = ct and (ct .. " in 7 days") or "No change in 7 days"
      t.plain = Home.Gold(total)
    else
      local gold = C.Money and C.Money() or 0
      t.title = Home.Gold(gold)
      t.sub = "This character"
      t.plain = t.title
    end
    out[#out + 1] = t
  end
  -- This session: Field Kit's numbers (its switch is Field Kit's "Show this session on Home")
  local S = Panoply.Session
  if S and db.homeSession ~= false and pageHere("misc") then
    local ok, parts, s = pcall(S.Parts, S)
    if ok and s and (s.xp > 0 or s.gold ~= 0 or s.runs > 0 or s.deaths > 0) then
      out[#out + 1] = { key = "session", group = "glance", icon = "Star", slot = "icon.tile.session", label = "This session", page = "misc",
        pageLabel = "Field Kit", title = parts[1], sub = S.TimeText(s.seconds) .. " played · " .. parts[2],
        help = "This play session: experience per hour, time played and gold. Opens Field Kit.", open = opener({ page = "misc" }) }
    end
  end
  -- Legacy (WoW Forever): the account's points, and what this character has not spent (read only once Legacy has its saved table)
  local L = Panoply.Legacy
  if db.homeLegacy ~= false and L and L.Here and L:Here() and pageHere("legacy") then
    local st = db.foreverLegacy
    local okT = type(st) == "table" and st.v ~= nil
    if okT then for _, k in ipairs({ "earned", "done", "cosmetics", "chars" }) do if type(st[k]) ~= "table" then okT = false end end end
    if okT then
      local ok, m = pcall(L.Meter, L)
      if ok and m then
        out[#out + 1] = { key = "legacy", group = "glance", icon = "MenuLegacy", slot = "icon.tile.legacy", label = "Legacy", page = "legacy",
          pageLabel = "Legacy", title = ("%d %s"):format(m.points or 0, (m.points or 0) == 1 and "point" or "points"),
          sub = (m.unspent or 0) > 0 and ("%d unspent on this character"):format(m.unspent) or "All spent on this character",
          help = "Your account's Legacy points, and this character's unspent ones. Opens Legacy.", open = opener({ page = "legacy", tab = "plan" }) }
      end
    end
  end
  -- Prices: the age of the scan the Auctions page shows, in its freshness colour
  local Auc = Panoply.Auctions
  if db.homeAuction ~= false and pageHere("auctions") and Auc and Auc.Record then
    local R, V = Auc.Record, Auc.View
    local key = (V and V.Key and select(2, pcall(V.Key, V))) or (R.LatestKey and R.LatestKey())
    if type(key) ~= "string" then key = R.LatestKey and R.LatestKey() or nil end
    local snap = key and R.Snap(key)
    local t = (snap and tonumber(snap.t)) or (key and R.ScanTime(key)) or 0
    local tok, words = "state.idle", "No scan yet"
    if V and V.Freshness then tok, words = V.Freshness(t) end
    out[#out + 1] = { key = "auction", group = "glance", icon = "Auctions", slot = "icon.tile.prices", label = "Prices", page = "auctions",
      pageLabel = "Auctions", title = words, color = tok, scanAt = t,
      sub = t > 0 and "Auction prices" or "Scan at the auction house",
      help = "How old your auction prices are, as the Auctions page shows it. Opens Auctions.", open = opener({ page = "auctions" }) }
  end
  -- Bags: free slots on this character
  if db.homeBags ~= false then
    local b = Home.BagState()
    local near = Home.NearlyFull(b.free, b.total)
    out[#out + 1] = { key = "bags", group = "glance", icon = "Bags", slot = "icon.tile.bags", label = "Bags", page = "hall", pageLabel = "Muster",
      title = ("%d free"):format(b.free), color = near and "state.warn" or nil,
      sub = b.junk > 0 and ("of %d · %d grey worth %s"):format(b.total, b.junk, money(b.junkCopper)) or ("of %d slots"):format(b.total),
      help = "Free slots in this character's bags. Opens Muster at this character.",
      open = function()
        local A = Panoply.Alts
        local Hi = Panoply.History
        if Hi then Hi:Begin() end
        if A and A.active and Panoply.Profiles then
          local mr, mn = Panoply.Profiles:Me()
          if mr then A:Open(mr, mn, "bags") if Hi then Hi:End("home") end return end
        end
        Panoply.Menu:Select("hall")
        if Hi then Hi:End("home") end
      end }
  end
  -- Next upgrade: the Class page's gear grid (the same one its Gear tab and At your level draw)
  local CP = Panoply.ClassPages
  if db.homeUpgrade ~= false and Panoply.Gear and CP and CP.GearGrid and pageHere("class") then
    local ok, g = pcall(CP.GearGrid, CP)
    if ok and g and g.cells then
      local best
      for _, c in ipairs(g.cells) do if c.now and (not best or (c.now.delta or 0) > (best.delta or 0)) then best = c.now end end
      local t = { key = "upgrade", group = "glance", icon = "MenuClass", slot = "icon.tile.upgrade", label = "Next upgrade", page = "class",
        pageLabel = "Class", help = "The best upgrade the Class page's Gear tab shows. Opens it.", open = opener({ page = "class", tab = "gear" }) }
      if best then
        t.title = best.name or "An upgrade"
        t.sub = (g.now or 0) > 1 and ("%d slots have an upgrade"):format(g.now) or "1 slot has an upgrade"
        t.itemRef = best.link or best.itemID   -- the tile paints the picture through Panoply.Icons (late items too)
      elseif g.working then
        t.title, t.sub = "Looking...", "The gear engine is still weighing your gear"
      else
        t.title, t.sub = "None now", "Nothing beats what you wear"
      end
      out[#out + 1] = t
    end
  end
  return out
end

-- { { group, label, lines } } in the order they are shown; Needs you shows even when empty ("Nothing needs you.")
Home.GROUPS = { { id = "next", label = "NEXT STEP" }, { id = "needs", label = "NEEDS YOU" }, { id = "glance", label = "AT A GLANCE" } }
Home.providers = {}
function Home.AddLine(fn) Home.providers[#Home.providers + 1] = fn end
function Home.View()
  local db = Panoply.db or {}
  local by = { next = {}, needs = {}, glance = {} }
  if db.homeNext ~= false then local l = nextLine() if l then by.next[1] = l end end
  if db.homeNeeds ~= false then by.needs = needLines() end
  by.glance = Home.Tiles()
  -- lines another file adds (a provider returns a line, its group says where it goes, or nil). Field Kit's session line is a tile now.
  for _, fn in ipairs(Home.providers) do
    local ok, l = pcall(fn)
    if ok and type(l) == "table" and by[l.group or ""] and l.key ~= "session" then table.insert(by[l.group], l) end
  end
  local out = {}
  for _, g in ipairs(Home.GROUPS) do
    if #by[g.id] > 0 or (g.id == "needs" and db.homeNeeds ~= false) then
      local label = g.label
      if g.id == "needs" then label = ("NEEDS YOU (%d)"):format(#by.needs) end
      out[#out + 1] = { id = g.id, label = label, lines = by[g.id] }
    end
  end
  return out
end

-- one click opens its page, as one Back / Forward step
function Home.Open(line)
  if line.open then line.open() return end
  local Hi = Panoply.History
  if Hi then Hi:Begin() end
  Panoply.Menu:Select(line.page)
  if Hi then Hi:End("home") end
end

-------------------------------------------------------------------------------
-- The page
-------------------------------------------------------------------------------
local GROUP_TITLE = { next = "Next step", needs = "Needs you", glance = "At a glance" }
Home.HELP = "Click a tile or a line to open its page. The gear picks which tiles Home shows."

local function tileFrame(parent)
  local K = Panoply.Kit
  local t = CreateFrame("Button", nil, parent)
  t.panoplyBox = true
  t.bg = Skin.Box(t, "S", { fill = Skin.colors.surface1 or Skin.colors.button, fillA = 1, line = Skin.colors.hairline, layer = "BACKGROUND", lineLayer = "BORDER" })
  t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetSize(20, 20)
  t.value = Skin.Text(t, 15, Skin.colors.text, nil, "semi")
  t.sub = Skin.Ink(t, 11, Skin.colors.inkSoft)
  t.label = Skin.Label(t, 9, Skin.colors.inkSoft)
  t:SetScript("OnClick", function(self) if self.line then Home.Open(self.line) end end)
  t:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  t:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  return t
end

Menu:RegisterTab("Home", function(p)
  local K = Panoply.Kit
  p.secs = {}
  for _, g in ipairs(Home.GROUPS) do p.secs[g.id] = K.Section(p, "home", g.id, { title = GROUP_TITLE[g.id] or g.label }) end
  -- next step: one clickable card and its arrow button
  local nb = p.secs.next.body
  local nx = CreateFrame("Button", nil, nb); p.nextBtn = nx
  nx.icon = nx:CreateTexture(nil, "ARTWORK"); nx.icon:SetSize(22, 22)
  nx.title = Skin.Text(nx, 14, Skin.colors.text, nil, "semi")
  nx.sub = Skin.Ink(nx, 11, Skin.colors.inkSoft)
  nx.go = Skin.Ink(nx, 11, Skin.colors.inkSoft); nx.go:SetText("Guide >")
  nx:SetScript("OnClick", function(self) if self.line then Home.Open(self.line) end end)
  nx:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  nx:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  p.arrowBtn = Skin.IconButton(nb, "Arrow", 26, function()
    if Panoply.Menu.GuidePage and Panoply.Menu.GuidePage.PointArrow then Panoply.Menu.GuidePage.PointArrow() end
  end, "Point the arrow", "Shows the arrow and points it at your next step.")
  p.arrowBtn.panoplyFixedW = true
  -- needs you
  p.needList = K.List(p.secs.needs.body, { page = "home", big = true, icon = true, onClick = function(item) Home.Open(item.line) end })
  p.needEmpty = Skin.Ink(p.secs.needs.body, 12, Skin.colors.inkSoft); p.needEmpty:SetText("Nothing needs you.")
  -- at a glance
  p.tiles = {}
  p.help = K.HelpIcon(p.secs.glance.body, "At a glance", Home.HELP, 16)
  p.lines = {}
  -- 0.9.6 item 4: the off switch, a quiet text button at the foot of the page (UI/Minimap.lua asks first)
  local off = CreateFrame("Button", nil, p); p.offBtn = off
  off.label = Skin.Ink(off, 11, Skin.colors.inkSoft); off.label:SetPoint("RIGHT", off, "RIGHT", 0, 0)
  if off.label.SetJustifyH then off.label:SetJustifyH("RIGHT") end
  off.label:SetText(Home.OFF_TEXT)
  Skin.Tooltip(off, Home.OFF_TEXT, Home.OFF_TIP)
  off:SetScript("OnClick", function() if Panoply.Minimap and Panoply.Minimap.AskTurnOff then Panoply.Minimap:AskTurnOff() end end)
  off:SetScript("OnEnter", function(self)
    local c = Skin.colors.text or { 1, 1, 1 } self.label:SetTextColor(c[1], c[2], c[3], 1)
    if self.panoplyShowTip then self.panoplyShowTip() end
  end)
  off:SetScript("OnLeave", function(self)
    local c = Skin.colors.inkSoft or { 0.7, 0.7, 0.7 } self.label:SetTextColor(c[1], c[2], c[3], 1)
    if _G.GameTooltip then GameTooltip:Hide() end
  end)

  function p:Layout()
    local W = self.width - 4
    local band = K.Band(self.width)
    self.band = band
    local y = 0
    for _, s in pairs(self.secs) do s:Hide() end
    for i = #self.lines, 1, -1 do self.lines[i] = nil end
    nx:Hide(); self.arrowBtn:Hide(); self.needEmpty:Hide(); self.help:Hide()
    for _, t in ipairs(self.tiles) do t:Hide() end
    for _, g in ipairs(self.view or {}) do
      local sec = self.secs[g.id]
      sec:SetTitle(GROUP_TITLE[g.id] or g.label)
      sec:SetSummary(g.id == "needs" and ("%d %s"):format(#g.lines, #g.lines == 1 and "thing" or "things") or nil)
      local _, open = sec:Begin(self, 2, -y, W)
      local ch = 0
      if open and g.id == "next" then
        local l = g.lines[1]
        nx.line = l
        local pad = 10
        local aw = l.step and (26 + SP.m) or 0
        if l.step then self.arrowBtn:Show(); self.arrowBtn:ClearAllPoints(); self.arrowBtn:SetPoint("TOPRIGHT", sec.body, "TOPLEFT", W - pad, -SP.xs - 4) end
        if l.slot then K.Icon(nx.icon, l.slot, { size = 22 }) else Skin.SetIcon(nx.icon, l.icon or "Leveling") end
        nx.go:SetText((l.pageLabel or "Guide") .. " >")
        local gw = math.ceil(Skin.TextWidth(nx.go)) + 4
        local tx = 22 + SP.s
        local tw = W - 2 * pad - aw - tx - gw - SP.s
        nx.title:SetText(l.title or ""); nx.sub:SetText(l.sub or "")
        nx.title:SetWidth(tw); nx.sub:SetWidth(tw)
        local h1, h2 = math.ceil(TH(nx.title, tw)), (l.sub or "") ~= "" and math.ceil(TH(nx.sub, tw)) or 0
        nx.title:SetHeight(h1); nx.sub:SetHeight(math.max(1, h2))
        nx.icon:ClearAllPoints(); nx.icon:SetPoint("TOPLEFT", nx, "TOPLEFT", 0, -1)
        nx.title:ClearAllPoints(); nx.title:SetPoint("TOPLEFT", nx, "TOPLEFT", tx, 0)
        nx.sub:ClearAllPoints(); nx.sub:SetPoint("TOPLEFT", nx, "TOPLEFT", tx, -h1 - 2)
        nx.go:SetWidth(gw); nx.go:ClearAllPoints(); nx.go:SetPoint("TOPRIGHT", nx, "TOPRIGHT", 0, -2)
        local h = math.max(24, h1 + 2 + h2)
        nx:ClearAllPoints(); nx:SetPoint("TOPLEFT", sec.body, "TOPLEFT", pad, -SP.xs - 4); nx:SetSize(W - 2 * pad - aw, h)
        Skin.Tooltip(nx, l.title, l.help)
        nx:Show()
        nx.key = "next"
        self.lines[#self.lines + 1] = nx
        ch = SP.xs + 4 + h + SP.s
      elseif open and g.id == "needs" then
        if #g.lines == 0 then
          self.needEmpty:Show(); self.needEmpty:ClearAllPoints(); self.needEmpty:SetPoint("TOPLEFT", sec.body, "TOPLEFT", 10, -SP.xs - 2)
          self.needEmpty:SetWidth(W - 20)
          ch = SP.xs + 2 + math.ceil(TH(self.needEmpty, W - 20)) + SP.s
          self.needList:Set({})
        else
          local items = {}
          for i, line in ipairs(g.lines) do
            items[i] = { id = line.key, line = line, icon = line.icon, title = line.title, sub = line.sub, right = line.pageLabel, go = true,
              mark = true, tip = line.title, tipBody = line.help }
          end
          self.needList:Set(items)
          ch = self.needList:Layout(6, -SP.xs, W - 12) + SP.xs
          for _, r in ipairs(self.needList.rows) do
            if r:IsShown() then r.line, r.go = r.item and r.item.line, r.right; self.lines[#self.lines + 1] = r end
          end
        end
      elseif open and g.id == "glance" then
        local cols = band == "wide" and 3 or (band == "medium" and 2 or 1)
        local pad, gap = 6, SP.s
        self.help:Show(); self.help:ClearAllPoints(); self.help:SetPoint("TOPRIGHT", sec.body, "TOPLEFT", W - pad, -SP.xs)
        local top = SP.xs + 16 + SP.xs
        local cw = math.floor((W - 2 * pad - (cols - 1) * gap) / cols)
        local rowY, col, rowH = top, 0, 0
        for i, l in ipairs(g.lines) do
          local t = self.tiles[i]
          if not t then t = tileFrame(sec.body) self.tiles[i] = t end
          t.line, t.key = l, l.key
          if l.itemRef then Panoply.Icons:Apply(t.icon, l.itemRef) t.icon:Show()
          elseif l.slot and K.ICONS[l.slot] then K.Icon(t.icon, l.slot, { size = 20 })
          else Skin.SetIcon(t.icon, l.icon or "Modules") end
          t.label:SetText((l.label or ""):upper())
          t.value:SetText(l.title or "")
          local c = l.color and K.Color(l.color) or Skin.colors.text
          t.value:SetTextColor(c[1], c[2], c[3], 1)
          t.sub:SetText(l.sub or "")
          Skin.Tooltip(t, l.label, l.help)
          local inner = cw - 2 * 10 - 20 - SP.s
          local h
          for _, fs in ipairs({ t.value, t.sub, t.label }) do if fs.SetWordWrap then fs:SetWordWrap(cols > 1) end end
          t.icon:ClearAllPoints(); t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -10)
          if cols == 1 then
            -- narrow: one line each: icon, value, muted line
            t.label:Hide()
            local vw = math.min(math.ceil(Skin.TextWidth(t.value)) + 4, math.floor(inner * 0.5))
            t.value:SetWidth(vw); Skin.Ellipsize(t.value, l.title or "", vw)
            t.value:ClearAllPoints(); t.value:SetPoint("LEFT", t.icon, "RIGHT", SP.s, 0)
            local sw = inner - vw - SP.s
            t.sub:SetWidth(sw); Skin.Ellipsize(t.sub, l.sub or "", sw)
            t.sub:ClearAllPoints(); t.sub:SetPoint("LEFT", t.value, "RIGHT", SP.s, 0)
            t.value:SetHeight(math.ceil(TH(t.value, vw))); t.sub:SetHeight(math.ceil(TH(t.sub, sw)))
            h = math.max(20, math.ceil(TH(t.value, vw)), math.ceil(TH(t.sub, sw))) + 20
          else
            t.label:Show()
            local x = 10 + 20 + SP.s
            t.label:SetWidth(inner); t.label:ClearAllPoints(); t.label:SetPoint("TOPLEFT", t, "TOPLEFT", x, -8)
            local lh = math.ceil(TH(t.label, inner)); t.label:SetHeight(lh)
            t.value:SetWidth(inner); t.value:ClearAllPoints(); t.value:SetPoint("TOPLEFT", t, "TOPLEFT", x, -8 - lh - 2)
            local vh = math.ceil(TH(t.value, inner)); t.value:SetHeight(vh)
            t.sub:SetWidth(inner); t.sub:ClearAllPoints(); t.sub:SetPoint("TOPLEFT", t, "TOPLEFT", x, -8 - lh - 2 - vh - 2)
            local sh = (l.sub or "") ~= "" and math.ceil(TH(t.sub, inner)) or 0; t.sub:SetHeight(math.max(1, sh))
            h = 8 + lh + 2 + vh + 2 + sh + 10
          end
          t.panoplyH = h
          t:SetWidth(cw)
          t:ClearAllPoints(); t:SetPoint("TOPLEFT", sec.body, "TOPLEFT", pad + col * (cw + gap), -rowY)
          t:Show()
          rowH = math.max(rowH, h)
          self.lines[#self.lines + 1] = t
          col = col + 1
          if col >= cols or i == #g.lines then
            -- one row of tiles is one height
            for k = i - col + 1, i do self.tiles[k]:SetHeight(rowH) end
            rowY = rowY + rowH + gap
            col, rowH = 0, 0
          end
        end
        ch = rowY + SP.xs
      end
      y = y + sec:Done(ch) + SP.m
    end
    -- the off switch, right-aligned under the last section
    local ow = math.min(W - 4, math.ceil(Skin.TextWidth(off.label)) + 6)
    off.label:SetWidth(ow)
    local oh = math.max(18, math.ceil(TH(off.label, ow)) + 4)
    off.label:SetHeight(oh - 4)
    off:SetSize(ow, oh)
    off:ClearAllPoints(); off:SetPoint("TOPRIGHT", self, "TOPLEFT", 2 + W, -y)
    off:Show()
    y = y + oh
    return y + SP.m
  end
end, function(p)
  p.view = Home.View()
end, { scroll = true })
