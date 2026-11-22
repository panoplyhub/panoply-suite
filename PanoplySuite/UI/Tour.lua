-- Panoply Suite 0.5.6: "How to use Panoply Suite", a first-time guided tour (coach marks).
-- The screen is dimmed except for the real frame being explained (a spotlight with a gold ring);
-- a rounded callout card sits next to it with a title, 1-3 plain sentences, Back / Next /
-- Skip tour and "Step X of N" dots. The card is placed on whichever side has room: it never
-- covers the highlighted frame and always stays on screen. Steps for modules that are off are
-- skipped. Shown once after the first setup; /panoply tour or the menu buttons replay it.
local ADDON, Panoply = ...
local Tour = { index = 0, list = {} }
Panoply.Tour = Tour
local Skin, C = Panoply.Skin, Panoply.Compat
local SP = Skin.SP

Tour.CARD_W, Tour.CARD_MIN_W = 330, 250
Tour.GAP, Tour.HOLE_PAD, Tour.EDGE = 16, 6, 12

local function on(key) return Panoply.Modules and Panoply.Modules:IsOn(key) end
local function shown(f) return f and f.IsVisible and f:IsVisible() and true or false end

-- the window is parked on the left while the tour explains it, so the card fits beside it
local function menu(page, section, rowKey)
  Panoply.Menu:Open(page)
  if section then Panoply.Menu:OpenGear(page, section, rowKey) end
  Tour:Park(Panoply.Menu.frame, "LEFT", 24, 30)
  return Panoply.Menu.frame
end
local function noMenu() Panoply.Menu:Hide() end
local function noBags() if Panoply.Bags and Panoply.Bags.Close then pcall(Panoply.Bags.Close, Panoply.Bags, "bags") end end
local function noWay() if Panoply.Waypoints and Panoply.Waypoints.frame then Panoply.Waypoints.frame:Hide() end end
local function clear() noMenu() noBags() noWay() if Tour.rowFrame then Tour.rowFrame:Hide() end if Tour.regionFrame then Tour.regionFrame:Hide() end end
-- a page's own header (its icon, name, switch and gear)
local function pageHeader() return Panoply.Menu.header or Panoply.Menu.frame end

-- 0.9.5 phase 4L (spec 06 section 8): the tour is seven short steps for the new window, each pointing at one part of it with the
-- rest dimmed (spotlight, bordered card, step dots, Back / Next / Skip the tour). Before 0.9.5 it was six (Step 2 B-06).
-- It offers itself once per character after the update that ships the new window ("A lot has moved."), and after the first setup of a
-- new account; Help replays it.
-- Each step: key, icon, title, body (1-3 sentences), when() = shown at all, prepare() = open what is explained, target() = the frame
-- to light up.
local function homeNeeds()
  local p = Panoply.Menu.pages.Home
  local s = p and p.secs and p.secs.needs
  local card = s and s.card
  if card and card:IsShown() then return card end
  return Panoply.Menu.list
end
Tour.STEPS = {
  { key = "pages", icon = "Leveling", title = "Your pages, in four sections",
    body = "Play, Character, Account and Setup. Click a page to open it; the list keeps the same order on every character.",
    prepare = function() menu("home") end, target = function() return Panoply.Menu.list end },
  { key = "history", icon = "Route", title = "Back and forward",
    body = "The two arrows at the top go back and forward through the pages you opened, like a web browser. Your mouse's fourth and fifth buttons do the same.",
    prepare = function() menu("home") end,
    target = function()
      local H = Panoply.History
      if H and H.back and H.fwd then return Tour.Region({ H.back, H.fwd }) or H.back end
      return Panoply.Menu.frame
    end },
  { key = "search", icon = "Search", title = "Search everything",
    body = "Type a word in the All settings box, like arrow or junk, and jump straight to the setting.",
    prepare = function() menu("home") end, target = function() return Panoply.Menu.box end },
  { key = "home", icon = "Hearth", title = "Home: what needs you",
    body = "Your next step, a talent point or spells waiting, your gold and your bags. Click any line to open the page it belongs to.",
    -- the first line (the whole page leaves no room for the card on a small screen)
    prepare = function() menu("home") end,
    target = function()
      local p = Panoply.Menu.pages.Home
      local l = p and p.lines and p.lines[1]
      return (l and l:IsShown()) and l or Panoply.Menu.host
    end },
  { key = "alerts", icon = "MenuHome", title = "Alerts: the dots and Needs you",
    body = "A dot beside a page in the list means something there needs you. Home's Needs you lists every one, and a click goes there.",
    prepare = function() menu("home") end, target = homeNeeds },
  { key = "gear", icon = "Settings", title = "Each page's gear opens its settings",
    body = "The settings open beside the page. The ones most players change come first; the rest are in the sections under them.",
    prepare = function() menu("guide") Panoply.Menu:OpenGear("guide") Tour:Park(Panoply.Menu.frame, "LEFT", 24, 30) end,
    -- 0.9.5: the settings take the whole page area on a Medium page, which leaves the card no room beside them on a small screen:
    -- there the first common settings at their top are lit; the drawer beside a Wide page is lit whole
    target = function()
      local G = Panoply.PageSettings
      local P = G.P
      if G.sheet and (G.sheet:GetWidth() or 0) > 600 and P and #(P.commonMade or {}) > 0 then
        local list = {}
        for i = 1, math.min(4, #P.commonMade) do
          local w = P.commonMade[i]
          list[#list + 1] = w
          if w.label then list[#list + 1] = w.label end
        end
        return Tour.Region(list) or G.sheet
      end
      return G.sheet
    end },
  { key = "help", icon = "Help", title = "Help: tips, commands and problems",
    body = "Tips for every page, every command, and where to report a problem. Help has this tour again.",
    prepare = function() menu("help") end,
    target = function()
      local p = Panoply.Menu.pages.Help
      if p and p.search and p.search:IsShown() then
        local list = { p.search }
        for _, b in ipairs(p.index or {}) do if b:IsShown() then list[#list + 1] = b end end
        if p.pick and p.pick:IsShown() then list[#list + 1] = p.pick end
        return Tour.Region(list) or p.search
      end
      return Panoply.Menu.host
    end },
}

-- Step 2 B: what the older fourteen-step tour explained is not lost: Help's Tips list shows it (UI/Help.lua).
Tour.TIPS = {
  { key = "window", title = "Your guide window",
    body = "The top card is what to do right now. It ticks itself off when you finish it and moves on by itself. "
      .. "Drag the header to move it, pull the corner to resize, and right-click the header to lock it or hide it." },
  -- 0.9.5 phase 4K (spec 05 4.2, 06a 3.3): the Leveling / Professions / Both switch is the Follows menu now (UI/GuideParts.lua)
  { key = "switch", title = "What the guide follows",
    body = "The Follows menu at the top of the Guide page and of the guide window picks what the guide follows: leveling only, leveling and a profession, or one profession.",
    when = function() return Panoply.GuideParts ~= nil and Panoply.GuideParts.Follows ~= nil end },
  { key = "combat", title = "In a fight",
    body = function()
      local w = Panoply.db.hideInCombat and "The guide window fades out when a fight starts and comes back when it ends."
        or "The guide window stays during fights."
      local a = Panoply.db.hideArrowInCombat and " The arrow fades too." or " The arrow stays and keeps pointing."
      return w .. a .. " Change this with Hide the guide window in combat (" .. Panoply:SettingsPath("hideInCombat") .. ") and Hide the arrow in combat (" .. Panoply:SettingsPath("hideArrowInCombat") .. ")."
    end },
  { key = "arrow", title = "Follow the arrow",
    body = "The arrow points to your next goal and shows how far away it is. Right-click it to lock it in place; clicks then go straight through it.",
    when = function() return Panoply.db.arrowShown ~= false end },
  { key = "minimap", title = "Open Panoply Suite",
    body = "Type /panoply, or use the crest by the minimap: left-click shows or hides the guide, right-click opens Panoply Suite on the page you used last, Ctrl-click opens the quick switches. You can drag the crest around the minimap." },
  -- 0.9.5 phase 4L (spec 06 section 2.2): "The pages" (one paragraph about every page) is gone: each page has its own row in Help's
  -- Tips by page, from its own subtitle and "?" text. "Things it does for you" is a list in the Everywhere row, each action with its
  -- switch's state and the page that owns it (UI/Help.lua Help.Automation).
  { key = "bags", title = "Your bags",
    body = function()
      return "Press B to open all your bags in one window." .. (on("glow") and " Coloured borders show item quality;" or "")
        .. " search and sort are at the top. Your bank is saved, so /panoply bank shows it anywhere."
    end,
    when = function() return on("bags") end },
  { key = "tooltips", title = "Prices in tooltips",
    body = "Point at any item: its tooltip shows what a vendor pays and its Auction House price. At the Auction House, click Scan at the top right to update the prices.",
    when = function() return on("auctions") end },
  { key = "gathering", title = "Gathering pins",
    body = "Herbs, ore, fishing pools and chests you find show up as pins on your world map and minimap, so you can find them again.",
    when = function() return on("gathering") end },
  { key = "profwindow", title = "The profession window",
    body = "Open a profession and a panel next to it adds search, favourites, filters and how many of each recipe you can make.",
    when = function() return on("profwindow") end },
  { key = "waypoints", title = "Waypoints",
    body = "Type /way 45.2 61.8 to set your own waypoint and the arrow takes you there. /way list shows them all.",
    when = function() return on("waypoints") end },
  { key = "partner", title = "Playing together",
    body = "Group up and both run Panoply Suite: the Level together page shows where your partner is and keeps you both on the same route." },
}

-- 0.9.5 phase 4A4: these tips go into the help registry (Core/HelpRegistry.lua) under the page each is about, or Everywhere; Help's
-- Tips by page reads the registry, in this order.
Tour.TIP_PAGE = { bags = "hall", tooltips = "auctions", gathering = "map", profwindow = "professions", waypoints = "map", partner = "partner",
  switch = "guide" }
if Panoply.Help and Panoply.Help.Register then
  for _, t in ipairs(Tour.TIPS) do Panoply.Help:Register(Tour.TIP_PAGE[t.key] or Panoply.Help.EVERYWHERE, { tips = { t } }) end
end

-- the Size choice in a page's header (Small, Normal, Large with its word)
function Tour.SizeControl()
  local h = Panoply.Menu.header
  if not (h and h.sizeBtns and h.sizeBtns[1]:IsShown()) then return h end
  local list = { h.sizeLabel }
  for _, b in ipairs(h.sizeBtns) do list[#list + 1] = b end
  return Tour.Region(list) or h
end

-- scroll the nearest scroll area so frame f is in view (near the top third)
function Tour.ScrollTo(f)
  local sc = f.GetParent and f:GetParent()
  local n = 0
  while sc and not sc.panoplyScroll and n < 30 do sc, n = sc.GetParent and sc:GetParent(), n + 1 end
  if not (sc and sc.content and sc.SetVerticalScroll and f.GetTop and sc.content.GetTop) then return end
  local ct, top = f:GetTop(), sc.content:GetTop()
  local cur = sc.GetVerticalScroll and sc:GetVerticalScroll() or 0
  if not (ct and top) then return end
  -- content top moves with the scroll: offset of f inside the content
  local off = (top - ct)
  local want = math.max(0, math.min(sc:MaxScroll(), off - (sc:ViewH() or 0) * 0.3))
  if math.abs(want - cur) > 0.5 then pcall(sc.SetVerticalScroll, sc, want) end
end

-- A highlight box around several frames (part of a page), so the card fits beside it even on
-- small screens where the whole window leaves no room.
function Tour.Region(frames)
  local u
  for _, f in ipairs(frames) do
    local r = Tour.RectOf(f)
    if r then
      if not u then u = { r[1], r[2], r[3], r[4] }
      else u[1], u[2], u[3], u[4] = math.min(u[1], r[1]), math.max(u[2], r[2]), math.min(u[3], r[3]), math.max(u[4], r[4]) end
    end
  end
  if not u then return nil end
  Tour.regionFrame = Tour.regionFrame or CreateFrame("Frame", nil, UIParent)
  local f = Tour.regionFrame
  f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", u[1] - 4, u[3] - 4); f:SetSize(u[2] - u[1] + 8, u[4] - u[3] + 8)
  f:Show()
  return f
end

-- several rows of the open gear section lit up together (scrolled into view); no keys = the section's checks
function Tour.SettingRows(keys)
  local G = Panoply.PageSettings
  local h = G and G.open and G.cur
  if not h then return nil end
  local want = {}
  for _, k in ipairs(keys or {}) do want[k] = true end
  local list = {}
  for _, w in ipairs(h.made or {}) do
    if (keys and want[w.panoplyKey]) or (not keys and w.panoplyRow and w.panoplyRow.type == "check") then
      if w:IsVisible() then
        if #list == 0 then Tour.ScrollTo(w) end
        list[#list + 1] = w
        if w.label then list[#list + 1] = w.label end
      end
    end
  end
  if #list == 0 then return nil end
  return Tour.Region(list)
end
function Tour.GearRows() return Tour.SettingRows(nil) end

function Tour.PartnerTop()
  local p = Panoply.Menu.pages.Partner
  if not p then return nil end
  return Tour.Region({ p.head, p.status, p.meCard, p.ptCard })
end

function Tour:Steps()
  local out = {}
  for _, s in ipairs(self.STEPS) do
    local ok, yes = true, true
    if s.when then ok, yes = pcall(s.when) end
    if ok and yes then out[#out + 1] = s end
  end
  return out
end

-------------------------------------------------------------------------------
-- Geometry
-------------------------------------------------------------------------------
local function screen()
  local w = UIParent.GetWidth and UIParent:GetWidth() or nil
  local h = UIParent.GetHeight and UIParent:GetHeight() or nil
  return (w and w > 0) and w or 1280, (h and h > 0) and h or 800
end
Tour.Screen = screen

-- { left, right, bottom, top } in UIParent units, or nil when the frame is not on screen
function Tour.RectOf(f)
  if not shown(f) or not f.GetLeft then return nil end
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  if not (l and r and b and t) or r - l < 1 or t - b < 1 then return nil end
  local s = 1
  if f.GetEffectiveScale and UIParent.GetEffectiveScale then
    local a, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if a and u and u > 0 then s = a / u end
  end
  local sw, sh = screen()
  l, r, b, t = math.max(0, l * s), math.min(sw, r * s), math.max(0, b * s), math.min(sh, t * s)
  -- inside a scroll area only the visible part counts
  local p, n = f.GetParent and f:GetParent(), 0
  while p and n < 30 do
    if p.panoplyScroll and p.GetLeft and p ~= f then
      local pl, pr, pb, pt = p:GetLeft(), p:GetRight(), p:GetBottom(), p:GetTop()
      if pl and pr and pb and pt then
        l, r, b, t = math.max(l, pl * s), math.min(r, pr * s), math.max(b, pb * s), math.min(t, pt * s)
      end
    end
    p, n = p.GetParent and p:GetParent(), n + 1
  end
  if r - l < 1 or t - b < 1 then return nil end
  return { l, r, b, t }
end

local function overlaps(a, b) return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] end

-- Where a cw x ch card goes next to hole (screen sw x sh): x, y (bottom-left) and the side.
-- Tries the side with the most room first, then the others, then the screen corners.
function Tour.Place(cw, ch, hole, sw, sh)
  local E, G, P = Tour.EDGE, Tour.GAP, Tour.HOLE_PAD
  if not hole then return math.floor((sw - cw) / 2), math.floor((sh - ch) / 2), "center" end
  local l, r, b, t = hole[1] - P, hole[2] + P, hole[3] - P, hole[4] + P
  local cx, cy = (l + r) / 2, (b + t) / 2
  local function clamp(v, lo, hi) if hi < lo then return lo end return math.max(lo, math.min(hi, v)) end
  local cands = {
    { "right", r + G, clamp(cy - ch / 2, E, sh - E - ch), sw - r },
    { "left", l - G - cw, clamp(cy - ch / 2, E, sh - E - ch), l },
    { "below", clamp(cx - cw / 2, E, sw - E - cw), b - G - ch, b },
    { "above", clamp(cx - cw / 2, E, sw - E - cw), t + G, sh - t },
  }
  table.sort(cands, function(x, y) return x[4] > y[4] end)
  cands[#cands + 1] = { "corner", E, E, 0 }
  cands[#cands + 1] = { "corner", sw - E - cw, E, 0 }
  cands[#cands + 1] = { "corner", E, sh - E - ch, 0 }
  cands[#cands + 1] = { "corner", sw - E - cw, sh - E - ch, 0 }
  local padded = { l - G / 2, r + G / 2, b - G / 2, t + G / 2 }
  for _, c in ipairs(cands) do
    local x, y = math.floor(c[2] + 0.5), math.floor(c[3] + 0.5)
    local box = { x, x + cw, y, y + ch }
    if x >= E - 0.5 and x + cw <= sw - E + 0.5 and y >= E - 0.5 and y + ch <= sh - E + 0.5 and not overlaps(box, padded) then
      return x, y, c[1]
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------
function Tour:Park(f, point, x, y)
  if not f then return end
  if not self.parked then self.parked = {} end
  if not self.parked[f] then
    local saved
    if f.GetNumPoints and f.GetPoint and (f:GetNumPoints() or 0) > 0 then
      saved = {}
      for i = 1, f:GetNumPoints() do saved[i] = { f:GetPoint(i) } end
    end
    self.parked[f] = saved or false
  end
  f:ClearAllPoints(); f:SetPoint(point, UIParent, point, x, y)
end

function Tour:Unpark()
  for f, saved in pairs(self.parked or {}) do
    f:ClearAllPoints()
    if saved and #saved > 0 then for _, p in ipairs(saved) do f:SetPoint(unpack(p)) end
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
  end
  self.parked = nil
end

local function solid(parent, layer, col, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetAllPoints(parent)
  if t.SetColorTexture then t:SetColorTexture(col[1], col[2], col[3], a) else t:SetTexture(Skin.TEX.RFill) t:SetVertexColor(col[1], col[2], col[3], a) end
  return t
end

function Tour:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteTour", UIParent)
  self.frame = f
  f:SetAllPoints(UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f.panoplyLayoutSkip = nil
  -- four dim panes around the hole: the highlighted frame stays bright, the rest is dimmed
  -- and can't be clicked by accident
  f.dim = {}
  for i = 1, 4 do
    local d = CreateFrame("Frame", nil, f)
    d:EnableMouse(true)
    solid(d, "BACKGROUND", { 0, 0, 0 }, 0.62)
    d.panoplyLayoutSkip = true
    f.dim[i] = d
  end
  -- the gold ring around the spotlight
  local ring = CreateFrame("Frame", nil, f)
  ring.panoplyLayoutSkip = true
  -- skin v3: a plain brass line, no glow around it
  Skin.RoundBox(ring, Skin.RADIUS.window, nil, nil, nil, Skin.TEX.RLine8, Skin.colors.gold, 1, "BORDER")
  f.ring = ring
  -- the callout card
  local card = CreateFrame("Frame", "PanoplySuiteTourCard", f)
  card:SetFrameLevel((f.GetFrameLevel and f:GetFrameLevel() or 1) + 20)
  card:EnableMouse(true)
  Skin.Panel(card, 0.98)
  -- skin v3: the brass trim and corner caps mark the card (the cerulean top bar would run into the caps)
  card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(34, 34)
  card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
  card.title = Skin.Heading(card, 15, "")
  card.count = Skin.Text(card, 10, Skin.colors.inkSoft)
  card.body = Skin.Text(card, 12)
  card.dots = {}
  card.back = Skin.Button(card, "Back", 70, 26, function() Tour:Go(Tour.index - 1) end, "Back", "The step before.")
  card.next = Skin.Button(card, "Next", 70, 26, function() Tour:Go(Tour.index + 1) end, "Next", "The next step.")
  card.skip = Skin.Button(card, "Skip the tour", 110, 26, function() Tour:Stop() end, "Skip the tour", "Close the tour. Help has it again any time, and so does /panoply tour.")
  card.buttons = { card.back, card.next, card.skip }
  f.card = card
  f:SetScript("OnHide", function() if Tour.active then Tour:Stop() end end)
  Skin.Popups:Special("PanoplySuiteTour", true)
  f:Hide()
  return f
end

local function dot(card, i)
  local d = card.dots[i]
  if d then return d end
  d = card:CreateTexture(nil, "ARTWORK")
  Skin.Round(d, 4, Skin.TEX.RFill)
  card.dots[i] = d
  return d
end

-- Fill the card for step s and size it for width cw; returns its height.
function Tour:LayoutCard(s, cw)
  local card = self.frame.card
  local n = #self.list
  card:SetWidth(cw)
  local x0, tx = 16, 16 + 34 + 10
  local tw = cw - tx - 16
  local y = -16
  card.title:ClearAllPoints(); card.title:SetPoint("TOPLEFT", card, "TOPLEFT", tx, y); card.title:SetWidth(tw)
  y = y - Skin.TextHeight(card.title, tw) - 2
  card.count:ClearAllPoints(); card.count:SetPoint("TOPLEFT", card, "TOPLEFT", tx, y); card.count:SetWidth(tw)
  y = y - Skin.TextHeight(card.count, tw)
  y = math.min(y, -(16 + 34)) - SP.m
  local bw = cw - 2 * x0
  card.body:ClearAllPoints(); card.body:SetPoint("TOPLEFT", card, "TOPLEFT", x0, y); card.body:SetWidth(bw)
  local bh = Skin.TextHeight(card.body, bw)
  card.body:SetHeight(bh)
  y = y - bh - SP.l
  -- "Step X of N" dots: the current one is a gold pill
  local dx = x0
  for i = 1, math.max(n, #card.dots) do
    local d = dot(card, i)
    if i <= n then
      local cur = i == self.index
      d:SetSize(cur and 16 or 7, 7)
      d:ClearAllPoints(); d:SetPoint("TOPLEFT", card, "TOPLEFT", dx, y)
      local c = cur and Skin.colors.gold or (i < self.index and Skin.colors.accent or Skin.colors.dim)
      d:SetVertexColor(c[1], c[2], c[3], cur and 1 or 0.8)
      d:Show()
      dx = dx + (cur and 16 or 7) + 5
    else d:Hide() end
  end
  y = y - 7 - SP.l
  local fh = Skin.FlowButtons(card, card.buttons, x0, y, bw, SP.s, 64)
  y = y - fh - 16
  card:SetHeight(-y)
  return -y
end

function Tour:Place_(s)
  local f, card = self.frame, self.frame.card
  local sw, sh = screen()
  local target
  local okT, tgt = pcall(s.target)
  if okT then target = tgt end
  local hole = Tour.RectOf(target)
  -- a target larger than the screen leaves no room: show the card alone
  if hole and (hole[2] - hole[1]) * (hole[4] - hole[3]) > sw * sh * 0.85 then hole = nil end
  local x, y, side, cw, ch
  for _, w in ipairs({ self.CARD_W, self.CARD_MIN_W }) do
    ch = self:LayoutCard(s, w)
    x, y, side = Tour.Place(w, ch, hole, sw, sh)
    cw = w
    if x then break end
  end
  if not x then hole = nil; x, y, side = Tour.Place(cw, ch, nil, sw, sh) end
  card:ClearAllPoints(); card:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
  -- dim around the hole (or the whole screen)
  local d = f.dim
  for _, p in ipairs(d) do p:ClearAllPoints() end
  if hole then
    local P = self.HOLE_PAD
    local l, r, b, t = hole[1] - P, hole[2] + P, hole[3] - P, hole[4] + P
    d[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, t); d[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    d[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); d[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, b)
    d[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, b); d[3]:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", l, t)
    d[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", r, b); d[4]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, t)
    for i = 2, 4 do d[i]:Show() end
    f.ring:ClearAllPoints(); f.ring:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", l, b); f.ring:SetSize(r - l, t - b); f.ring:Show()
  else
    d[1]:SetAllPoints(f)
    for i = 2, 4 do d[i]:Hide() end
    f.ring:Hide()
  end
  d[1]:Show()
  self.last = { key = s.key, hole = hole, card = { x, x + cw, y, y + ch }, side = side, screen = { sw, sh } }
  return self.last
end

-------------------------------------------------------------------------------
-- Flow
-------------------------------------------------------------------------------
function Tour:Go(i)
  if not self.active then return end
  if i < 1 then i = 1 end
  if i > #self.list then return self:Stop(true) end
  self.index = i
  local s = self.list[i]
  if s.prepare then local ok, err = pcall(s.prepare) if not ok then Panoply:Debug("tour prepare", s.key, err) end end
  local card = self.frame.card
  Skin.SetIcon(card.icon, s.icon, { large = true })
  card.title:SetText(s.title)
  card.count:SetText(("Step %d of %d"):format(i, #self.list))
  local body = s.body
  if s.lines then body = table.concat(s.lines(), "\n") elseif type(body) == "function" then body = body() end
  card.body:SetText(body or "")
  card.back:SetEnabledLook(i > 1)
  card.back.disabled = i <= 1
  card.next.label:SetText(i == #self.list and "Finish" or "Next")
  local ok, err = pcall(self.Place_, self, s)
  if not ok then Panoply:Debug("tour place", err) end
  -- the client settles new anchors after a frame: place once more then
  if C.After then
    local token = {}
    self.token = token
    C.After(0.05, function() if Tour.active and Tour.token == token then pcall(Tour.Place_, Tour, s) end end)
  end
  Panoply:Fire("TOUR_STEP", s.key, i)
  return s
end

function Tour:Start()
  if C.InCombat and C.InCombat() then
    Panoply:Print("The tour starts after combat.")
    self.pending = true
    return false
  end
  self:Create()
  self.list = self:Steps()
  if #self.list == 0 then return false end
  self.wasMenu = Panoply.Menu.frame and Panoply.Menu.frame:IsShown()
  self.active = true
  if Panoply.db then Panoply.db.tourSeen = true end
  if Panoply.cdb then Panoply.cdb.tourOffered = true end   -- 0.9.5 phase 4L: a character that has taken the new tour is not offered it
  self:CloseOffer()
  self.frame:Show()
  self:Go(1)
  return true
end

function Tour:Stop(finished)
  if not self.active then return end
  self.active = false
  self.token = nil
  clear()
  self:Unpark()
  if self.frame then self.frame:Hide() end
  if Panoply.UI and Panoply.UI.Show and Panoply.cdb and not Panoply.cdb.hidden then pcall(Panoply.UI.Show, Panoply.UI) end
  if finished then Panoply:Print("That's the tour. Type /panoply tour to see it again, or /panoply help for every command.") end
  -- the tour that followed the first setup gives the window back on the page the setup opened (Class & Spec after "I will build my own
  -- later"): it moved the menu around and closed it
  local back = self.returnTo
  self.returnTo = nil
  if back and not (C.InCombat and C.InCombat()) then pcall(Panoply.Menu.Open, Panoply.Menu, back) end
  Panoply:Fire("TOUR_DONE", finished and true or false)
end

-- First setup finished: the tour follows once per account.
-- One window at a time: when the What's new note is on screen the tour waits for it to close (UI/WhatsNew.lua starts it then).
function Tour.AutoStart()
  if not (Panoply.db and not Panoply.db.tourSeen) or Tour.active then return end
  local WN = Panoply.WhatsNew
  if WN and WN.frame and WN.frame:IsShown() then Tour.queuedAuto = true return end
  -- a window the setup left open is the page to come back to when the tour is over
  local M = Panoply.Menu
  Tour.returnTo = (M and M.frame and M.frame:IsShown() and M.current) or nil
  if not Tour:Start() then Tour.returnTo = nil end
end
Panoply:Listen("SETUP_DONE", function()
  if Panoply.db and not Panoply.db.tourSeen then C.After(1.5, Tour.AutoStart) end
end)
Panoply:On("PLAYER_REGEN_ENABLED", function() if Tour.pending then Tour.pending = nil Tour:Start() end end)
Panoply:On("PLAYER_REGEN_DISABLED", function() if Tour.active then Tour:Stop() Panoply:Print("Tour paused for combat. /panoply tour starts it again.") end end)

-------------------------------------------------------------------------------
-- 0.9.5 phase 4L (spec 06 section 8): offered once, the first time a character opens Panoply Suite after the update that ships the new
-- window: "A lot has moved. Take the 1-minute tour?" with Skip. New saved keys (nothing renamed):
--   PanoplySuiteDB.tourOfferOwed   true once this account updated from a version before Tour.OFFER_SINCE (noted at login)
--   PanoplySuiteCharDB.tourOffered true once this character was offered it (or took the tour)
-- A brand-new account gets the tour after its first setup instead (Tour.AutoStart), so it is never offered twice.
-------------------------------------------------------------------------------
Tour.OFFER_SINCE = "0.9.5"
Tour.OFFER_HEAD = "A lot has moved."
Tour.OFFER_BODY = "Take the 1-minute tour?"

local function cmp(a, b)
  local WN = Panoply.WhatsNew
  if WN and WN.Cmp then return WN.Cmp(a, b) end
  return a == b and 0 or (tostring(a) < tostring(b) and -1 or 1)
end

-- At login, before the running version is written as the account's last one (Core/Bootstrap.lua Panoply:AfterLogin).
function Tour:NoteLogin()
  local db = Panoply.db
  if not db then return false end
  local last = db.lastVersion
  if last and cmp(last, Tour.OFFER_SINCE) < 0 and cmp(Panoply.version, Tour.OFFER_SINCE) >= 0 then db.tourOfferOwed = true end
  return db.tourOfferOwed == true
end

-- Is the offer due for this character now?
function Tour:OfferDue()
  local db, cdb = Panoply.db, Panoply.cdb
  if not (db and cdb) then return false end
  if not db.tourOfferOwed or cdb.tourOffered or not cdb.setupDone then return false end
  -- only in the version that ships the new window (0.9.5.x): a character made in a later version is not told "A lot has moved"
  if (tostring(Panoply.version):match("^%d+%.%d+%.%d+") or "") ~= Tour.OFFER_SINCE then return false end
  if self.active or (C.InCombat and C.InCombat()) then return false end
  local Z, WN = Panoply.Wizard, Panoply.WhatsNew
  if Z and Z.frame and Z.frame:IsShown() then return false end
  if WN and WN.frame and WN.frame:IsShown() then return false end
  return true
end

function Tour:CreateOffer()
  if self.offer then return self.offer end
  local f = CreateFrame("Frame", "PanoplySuiteTourOffer", UIParent)
  self.offer = f
  f:SetSize(400, 110)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  -- above the main window (DIALOG), which has just opened: the offer must be seen to count as made
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Skin.Panel(f, 1, nil, "M")
  f.crest = f:CreateTexture(nil, "ARTWORK"); f.crest:SetSize(44, 44); Skin.Logo(f.crest)
  f.crest:SetPoint("CENTER", f, "TOPLEFT", 44, -46)
  f.head = Skin.Heading(f, 16, Tour.OFFER_HEAD)
  f.body = Skin.Text(f, 12)
  f.body:SetText(Tour.OFFER_BODY)
  f.go = Skin.Button(f, "Take the tour", 120, 26, function() Tour:CloseOffer() Tour:Start() end, "Take the tour",
    "Seven short steps through the window. Help has it again any time.")
  f.go.panoplyAccent = true
  f.skip = Skin.Button(f, "Skip", 80, 26, function() Tour:CloseOffer() end, "Skip", "Close this. Help has the tour any time.")
  f.buttons = { f.go, f.skip }
  function f:Layout()
    local W = self:GetWidth()
    local x, tw = 88, W - 88 - 18
    local y = -18
    self.head:ClearAllPoints(); self.head:SetPoint("TOPLEFT", self, "TOPLEFT", x, y); self.head:SetWidth(tw)
    y = y - Skin.TextHeight(self.head, tw) - SP.xs
    self.body:ClearAllPoints(); self.body:SetPoint("TOPLEFT", self, "TOPLEFT", x, y); self.body:SetWidth(tw)
    y = y - Skin.TextHeight(self.body, tw) - SP.m
    local bh = Skin.FlowButtons(self, self.buttons, x, y, tw, SP.s, 64)
    y = y - bh - SP.l
    self:SetHeight(math.max(96, -y))
  end
  f:Hide()
  return f
end

-- Show the offer when it is due (the main window just opened). Returns the card, or nil.
function Tour:MaybeOffer()
  if not self:OfferDue() then return nil end
  Panoply.cdb.tourOffered = true
  local f = self:CreateOffer()
  f:Layout()
  f:Show()
  return f
end
function Tour:CloseOffer() if self.offer then self.offer:Hide() end end

-- the main window opening is "a character opens Panoply Suite"
do
  local M = Panoply.Menu
  local open = M.Open
  function M:Open(key)
    local r = open(self, key)
    if Tour:OfferDue() then C.After(0.3, function() Tour:MaybeOffer() end) end
    return r
  end
end
