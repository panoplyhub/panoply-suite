-- Panoply Suite one-window menu: the page bodies that are short cards (Auctions, Map).
-- Each body shows today's information and the actions you use while playing; every setting is behind
-- the page's gear (UI/Gear.lua). The Guide, Partner, Professions, Hearth Hall and Help bodies are
-- in UI/Menu.lua, UI/Professions.lua, Modules/Alts/Hall.lua and UI/Help.lua.
local ADDON, Panoply = ...
local Menu = Panoply.Menu
local Skin, C = Panoply.Skin, Panoply.Compat
local SP = Skin.SP

-------------------------------------------------------------------------------
-- A small card: a brass label, a big line, some lines, an optional bar, buttons
-------------------------------------------------------------------------------
-- Step 20 (0.9.4): a card made with opts = { page, id, title, summary, open, guard } is a Kit.Section: its header has the chevron
-- (UI/Kit.lua), its content sits in the section's body, and open or closed is remembered for the page. A card made with no opts is
-- the plain card it always was.
local function newCard(parent, opts)
  local sec
  local c
  if opts and opts.page then
    sec = Panoply.Kit.Section(parent, opts.page, opts.id, { title = opts.title, summary = opts.summary, open = opts.open, guard = opts.guard })
    c = sec.card
    c.sec = sec
  else
    c = Skin.Card(parent)
  end
  c.panoplyGapOK = true
  local host = sec and sec.body or c
  c.host = host
  c.label = Skin.Label(c, 10, Skin.colors.gold)
  if sec then c.label:Hide() end
  c.big = Skin.Heading(host, 17)
  c.bar = Skin.Bar(host, 8, true)
  c.lines = {}
  c.buttons = {}
  function c:Line(i)
    local l = self.lines[i]
    if not l then l = Skin.Ink(self.host, 12, i == 1 and Skin.colors.ink or Skin.colors.inkSoft) self.lines[i] = l end
    return l
  end
  function c:Button(label, w, tip, body, fn)
    local b = Skin.Button(self.host, label, w, 28, fn, tip or label, body)
    self.buttons[#self.buttons + 1] = b
    return b
  end
  -- places everything for width w; returns the height
  function c:Layout(w)
    local pad = 12
    local inner = w - 2 * pad
    local sec = self.sec
    local anchor, y
    if sec then
      local _, open = sec:Head(w)
      if not open then
        if self.corner then self.corner:Hide() end
        return sec:Done(0)
      end
      anchor, y = sec.body, -SP.xs
    else
      self:SetWidth(w)
      anchor, y = self, -12
      self.label:ClearAllPoints(); self.label:SetPoint("TOPLEFT", self, "TOPLEFT", pad, y); self.label:SetWidth(inner)
      y = y - Skin.TextHeight(self.label, inner) - SP.xs
    end
    if (self.big:GetText() or "") ~= "" then
      -- a button at the right of the big line (Step 2 F: View Auction House beside the age of the last scan)
      local bigW, cornerH = inner, 0
      if self.corner then
        local cw = Skin.FitButton(self.corner, 120, math.floor(inner * 0.5))
        bigW = inner - cw - SP.m
        self.corner:ClearAllPoints(); self.corner:SetPoint("TOPRIGHT", anchor, "TOPLEFT", pad + inner, y)
        self.corner:Show()
        cornerH = self.corner:GetHeight()
      end
      self.big:ClearAllPoints(); self.big:SetPoint("TOPLEFT", anchor, "TOPLEFT", pad, y); self.big:SetWidth(bigW)
      y = y - math.max(Skin.TextHeight(self.big, bigW), cornerH) - SP.xs
      self.big:Show()
    else
      self.big:Hide()
      if self.corner then self.corner:Hide() end
    end
    if self.hasBar then
      y = y - Skin.BarLabelSpace(self.bar)
      self.bar:ClearAllPoints(); self.bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", pad, y); self.bar:SetWidth(inner); self.bar.panoplyWidth = inner
      self.bar.text:SetWidth(inner)
      y = y - 8 - SP.s
      self.bar:Show()
    else self.bar:Hide() end
    for _, l in ipairs(self.lines) do
      if (l:GetText() or "") ~= "" then
        l:ClearAllPoints(); l:SetPoint("TOPLEFT", anchor, "TOPLEFT", pad, y); l:SetWidth(inner)
        y = y - Skin.TextHeight(l, inner) - SP.xs
        l:Show()
      else l:Hide() end
    end
    y = y - SP.xs
    local bh = Skin.FlowButtons(anchor, self.buttons, pad, y, inner, SP.s, 90)
    if bh > 0 then y = y - bh - SP.m else y = y - SP.xs end
    if sec then return sec:Done(math.max(0, -y - SP.xs)) end
    self:SetHeight(-y)
    return -y
  end
  return c
end
Menu.NewCard = newCard

-- cards of one row get the height of the taller one (a card that is closed keeps its own height: only its header)
local function layoutCards(p, cards)
  local W = p.width
  local gap = SP.m
  local cw = math.floor((W - 4 - gap) / 2)
  local y = 0
  local i = 1
  while i <= #cards do
    local c = cards[i]
    if not c:IsShown() then i = i + 1
    elseif c.full then
      local h = c:Layout(W - 4)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -y)
      y = y + h + gap
      i = i + 1
    else
      local pair = { c }
      local j = i + 1
      while j <= #cards and not cards[j]:IsShown() do j = j + 1 end
      if j <= #cards and not cards[j].full then pair[2] = cards[j] end
      local rowH = 0
      local hs = {}
      for k, d in ipairs(pair) do
        hs[k] = d:Layout(cw)
        if not (d.sec and not d.sec:IsOpen()) then rowH = math.max(rowH, hs[k]) end
      end
      local tall = 0
      for k, d in ipairs(pair) do
        local h = (d.sec and not d.sec:IsOpen()) and hs[k] or rowH
        d:SetHeight(h)
        tall = math.max(tall, h)
        d:ClearAllPoints(); d:SetPoint("TOPLEFT", p, "TOPLEFT", 2 + (k - 1) * (cw + gap), -y)
      end
      y = y + tall + gap
      i = pair[2] and (j + 1) or (i + 1)
    end
  end
  return y
end
Menu.LayoutCards = layoutCards

local function setLines(card, lines)
  for i = 1, math.max(#lines, #card.lines) do card:Line(i):SetText(lines[i] or "") end
end

local function money(c) return Panoply.Alts and Panoply.Alts.MoneyFull and Panoply.Alts.MoneyFull(c) or C.FormatMoney(c) end

-------------------------------------------------------------------------------
-- Auctions (0.9.5 phase 4E, docs/specs/page-redesigns-v1.md section 7): the page IS the data. The strip, the tabs Prices · Upgrades ·
-- History and everything in them are drawn by the Auctions view (Modules/Auctions/View.lua), which the pop-out window draws too.
-------------------------------------------------------------------------------
Menu:RegisterTab("Auctions", function(p)
  local V = Panoply.Auctions and Panoply.Auctions.View
  if V then p.view = V.New(p, { kind = "page" }) end
  p.msg = Skin.Ink(p, 13, Skin.colors.inkSoft)
end, function(p)
  if not p.view then
    p.msg:ClearAllPoints(); p.msg:SetPoint("TOPLEFT", p, "TOPLEFT", 4, 0)
    p.msg:SetWidth((p.width or 600) - 8)
    p.msg:SetText("Turn Auctions on (the On switch above) to see prices here.")
    p.msg:Show()
    return
  end
  p.msg:Hide()
  local W, H = p.width or 600, p.height or 400
  p.view:Render(W, H, Panoply.Kit.Band(W))
end)

-------------------------------------------------------------------------------
-- Map: 0.9.5 phase 4K moved the Map page to Modules/Map/Page.lua (spec 05b section 1)
-------------------------------------------------------------------------------
