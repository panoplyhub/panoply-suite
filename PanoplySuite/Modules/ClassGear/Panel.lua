-- Upgrade Hints (the module "classgear"), part 2: the Gear topic. Panoply.ClassGear:BuildPanel(parent) makes one panel for a class
-- page (or any frame): what the character wears, scored for its plan, beside the next upgrades. Skin v3 cards, measured text
-- (the 1.3x layout checker reads the same numbers), nothing animated.
--
-- 0.9.5: every number and every row here is the gear engine's (Panoply.Gear, Modules/Gear): the worn scores, and the upgrades of
-- the Class page's slice of the spec (docs/specs/page-redesigns-04-gear-engine.md section 6: up to five levels ahead, every
-- source). This file only lays them out. The Class page of phase 4H replaces this panel.
--
--   local panel = Panoply.ClassGear:BuildPanel(parent)
--   panel is anchored to the parent's top-left corner, is as wide as the parent (CG.PANEL_W when the parent has
--   no width yet) and as tall as its content: panel:GetHeight(), also panel.contentH. panel:Refresh() fills it
--   again (it does so itself when it is shown, when the parent changes size, and when gear, level or the plan
--   change). Calling BuildPanel twice for the same parent returns the same panel.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Skin = Panoply.Skin
local CG = Panoply.ClassGear
local SP = Skin.SP

CG.PANEL_W = 640           -- used when the parent has no width yet
CG.PANEL_MIN_W = 300
CG.TWO_COLUMNS_FROM = 620  -- narrower than this, the two cards stack
CG.AHEAD = 5               -- the Gear topic also lists what the character can wear within this many levels (spec section 6)
CG.MAX_ROWS = 10           -- upgrade rows in the Gear topic
CG.PER_SLOT = 2            -- at most this many upgrade rows for one slot
local PAD = SP.m

-- The worn slots, in the order the Gear topic lists them: { the game's inventory slot id, label }.
CG.SLOTS = {
  { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulders" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrists" }, { 10, "Hands" },
  { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" },
  { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}
CG.SLOT_LABEL = {}
for _, s in ipairs(CG.SLOTS) do CG.SLOT_LABEL[s[1]] = s[2] end
CG.CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
  MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

-- the filter of the Class page's Gear tab
function CG:Filter(ctx)
  return { maxLevel = (ctx and ctx.level or 1) + CG.AHEAD, includeLocked = true, limitPerSlot = CG.PER_SLOT }
end

-- The rows of the upgrades card: the engine's upgrades, best first, at most CG.MAX_ROWS. Returns the rows, the state
-- ("ok", "working", "nodata" = no source has its data, "noclass" = no weights for this class) and the engine's result.
function CG:Upgrades(ctx)
  ctx = ctx or Panoply.Gear:GetContext()
  if not (ctx and ctx.stats) then return {}, "noclass" end
  local list, best = Panoply.Gear:Upgrades(ctx, self:Filter(ctx))
  local rows = {}
  for i = 1, math.min(#list, CG.MAX_ROWS) do rows[i] = list[i] end
  local state = "ok"
  if best and best.working then state = "working"
  elseif not (best and best.sources and next(best.sources)) then state = "nodata" end
  return rows, state, best
end

local function TH(fs, w) return math.ceil(Skin.TextHeight(fs, w)) end
local function TW(fs) return math.ceil(Skin.TextWidth(fs)) end

-- a wrapped block at (x, y) from the parent's top-left; returns the y below it
local function block(fs, parent, x, y, w, text)
  fs:ClearAllPoints()
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end   -- the box is measured generously: keep the text at its top
  fs:SetWidth(w); fs:SetText(text or ""); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = TH(fs, w); fs:SetHeight(h)
  fs:Show()
  return y - h
end

-- one line cut to fit (the full text stays readable in the row's tooltip)
local function line(fs, parent, x, y, w, text)
  fs:ClearAllPoints()
  Skin.Ellipsize(fs, text or "", w)
  fs:SetWidth(w); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = TH(fs, w); fs:SetHeight(h)
  fs:Show()
  return h
end

-- a right-aligned value whose right edge is at x; returns its width and height
local function value(fs, parent, x, y, text)
  fs:ClearAllPoints()
  fs:SetText(text or "")
  if fs.SetJustifyH then fs:SetJustifyH("RIGHT") end
  local w = TW(fs) + 4
  fs:SetWidth(w); fs:SetPoint("TOPRIGHT", parent, "TOPLEFT", x, y)
  local h = TH(fs, w); fs:SetHeight(h)
  fs:Show()
  return w, h
end

-- what the line under the heading says after "Weighed for <plan>."
local FROM_TEXT = {
  own = "That is the plan you follow in Talents & spells.",
  plan = "That is the plan you follow in Talents & spells.",
  copied = "That is the plan you follow in Talents & spells.",
  tree = "That is the talent tree your plan has the most points in.",
  talents = "That is the talent tree you have put the most points in. Pick a plan in Talents & spells to weigh for it instead.",
  default = "That is the usual leveling spec of your class, until you pick a plan or spend talent points.",
}
CG.NOTE = "The scores are a guide. They weigh the stats your plan uses most and do not know enchants, set bonuses or special effects."
CG.EMPTY_TEXT = {
  nodata = "The dungeon and quest gear list needs the Panoply Suite Quest Data add-on. It is not loaded.",
  noclass = "Panoply Suite has no gear weights for this class yet.",
  none = "Nothing better than what you wear was found for your level.",
  working = "Looking through the gear for your level...",
}

local function qualityColor(q)
  if q == nil then return Skin.colors.text end
  return C.QualityColor(q)
end

local function showItemTip(owner)
  local GT = _G.GameTooltip
  if not (GT and GT.SetOwner and owner.panoplyItem) then return end
  GT:SetOwner(owner, "ANCHOR_RIGHT")
  local it = owner.panoplyItem
  local ok = GT.SetHyperlink and pcall(GT.SetHyperlink, GT, it.link or ("item:" .. it.id))
  if not ok and GT.SetText then GT:SetText(it.name or "") end
  if owner.panoplyTipLine and GT.AddLine then GT:AddLine(owner.panoplyTipLine, 0.9, 0.9, 0.88, true) end
  GT:Show()
end
local function hideTip() local GT = _G.GameTooltip if GT and GT.Hide then GT:Hide() end end

local function newRow(card)
  local r = CreateFrame("Frame", nil, card)
  if r.EnableMouse then r:EnableMouse(true) end
  r:SetScript("OnEnter", showItemTip)
  r:SetScript("OnLeave", hideTip)
  return r
end

local function build(p)
  p.title = Skin.Heading(p, 16)
  p.sub = Skin.Ink(p, 12, Skin.colors.inkSoft)
  p.plan = Skin.Button(p, "Open the talent planner", 190, 26, function()
    local st = Panoply.SpecTrainer
    if st and st.OpenPlanner then st:OpenPlanner() end
  end, "Open the talent planner", "See or change the plan your gear is weighed for. You click the talents in the game's talent window yourself.")

  -- worn
  local wc = Skin.Card(p)
  wc.label = Skin.Label(wc, 11); wc.label:SetText("WORN NOW")
  wc.rows = {}
  for i, s in ipairs(CG.SLOTS) do
    local r = newRow(wc)
    r.slotId = s[1]
    r.slot = Skin.Ink(r, 11, Skin.colors.inkSoft); r.slot:SetText(s[2])
    r.name = Skin.Name(r, 12)
    r.score = Skin.Text(r, 12, Skin.colors.goldBright, nil, "semi")
    wc.rows[i] = r
  end
  wc.totalLabel = Skin.Label(wc, 11); wc.totalLabel:SetText("TOTAL")
  wc.total = Skin.Text(wc, 13, Skin.colors.goldBright, nil, "semi")
  wc.rule = wc:CreateTexture(nil, "ARTWORK")
  wc.rule:SetTexture(Skin.WHITE)
  local hc = Skin.colors.hairline
  wc.rule:SetVertexColor(hc[1], hc[2], hc[3], 1)
  p.worn = wc

  -- upgrades
  local uc = Skin.Card(p)
  uc.label = Skin.Label(uc, 11); uc.label:SetText("NEXT UPGRADES")
  uc.rows = {}
  for i = 1, CG.MAX_ROWS do
    local r = newRow(uc)
    r.name = Skin.Name(r, 12)
    r.gain = Skin.Text(r, 12, Skin.colors.done, nil, "semi")
    r.from = Skin.Ink(r, 11, Skin.colors.inkSoft)
    uc.rows[i] = r
  end
  uc.empty = Skin.Ink(uc, 12, Skin.colors.inkSoft)
  p.ups = uc

  p.note = Skin.Ink(p, 11, Skin.colors.inkSoft)
  p.built = true
end

-- Fill the worn card for width cw; returns its height.
local function fillWorn(p, cw, who)
  local wc = p.worn
  local inner = cw - 2 * PAD
  local y = -PAD
  wc.label:ClearAllPoints(); wc.label:SetPoint("TOPLEFT", wc, "TOPLEFT", PAD, y)
  wc.label:SetWidth(inner); wc.label:SetHeight(TH(wc.label, inner))
  y = y - TH(wc.label, inner) - SP.s
  -- the slot column is as wide as its longest label
  local slotW = 0
  for _, r in ipairs(wc.rows) do slotW = math.max(slotW, TW(r.slot)) end
  slotW = math.min(slotW + SP.s, math.floor(inner * 0.4))
  local total = 0
  for _, r in ipairs(wc.rows) do
    local item, score = Panoply.Gear:Worn(who, r.slotId)
    total = total + score
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", wc, "TOPLEFT", PAD, y)
    local sw, sh = value(r.score, r, inner, 0, item and Panoply.Gear.Num(score) or "")
    local nameW = math.max(20, inner - slotW - sw - SP.s)
    local c = item and qualityColor(item.quality) or Skin.colors.dim
    r.name:SetTextColor(c[1], c[2], c[3], 1)
    local nh = line(r.name, r, slotW, 0, nameW, item and (item.name or ("Item " .. tostring(item.id))) or "Empty")
    local lh = line(r.slot, r, 0, 0, slotW - SP.xs, CG.SLOT_LABEL[r.slotId])
    local h = math.max(sh, nh, lh)
    r:SetSize(inner, h)
    r.panoplyItem = item
    r.panoplyTipLine = item and ("Worth " .. Panoply.Gear.Num(score) .. " to " .. (who.planName or "you") .. ".") or nil
    if item then
      -- why: the three stats that count most (the engine's breakdown)
      local v = Panoply.Gear:Score(item, who)
      local top = v and Panoply.Gear.BreakdownText(v, 3) or ""
      if top ~= "" then r.panoplyTipLine = r.panoplyTipLine .. " " .. top .. "." end
    end
    r:Show()
    y = y - h - 3
  end
  y = y - SP.xs
  wc.rule:ClearAllPoints(); wc.rule:SetPoint("TOPLEFT", wc, "TOPLEFT", PAD, y); wc.rule:SetSize(inner, 1)
  y = y - SP.s
  local tw, th = value(wc.total, wc, cw - PAD, y, Panoply.Gear.Num(total))
  wc.totalLabel:ClearAllPoints(); wc.totalLabel:SetPoint("TOPLEFT", wc, "TOPLEFT", PAD, y)
  local tlw = inner - tw - SP.s
  wc.totalLabel:SetWidth(tlw)
  local tlh = TH(wc.totalLabel, tlw); wc.totalLabel:SetHeight(tlh)
  y = y - math.max(th, tlh) - PAD
  p.wornTotal = total
  return -y
end

-- Fill the upgrades card for width cw; returns its height.
local function fillUps(p, cw, who)
  local uc = p.ups
  local list, state = CG:Upgrades(who)
  local inner = cw - 2 * PAD
  local y = -PAD
  uc.label:ClearAllPoints(); uc.label:SetPoint("TOPLEFT", uc, "TOPLEFT", PAD, y)
  uc.label:SetWidth(inner); uc.label:SetHeight(TH(uc.label, inner))
  y = y - TH(uc.label, inner) - SP.s
  for i, r in ipairs(uc.rows) do
    local row = list[i]
    if row then
      local it = row.item
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", uc, "TOPLEFT", PAD, y)
      local gw, gh = value(r.gain, r, inner, 0, Panoply.Gear.DeltaText(row.delta))
      local c = qualityColor(it.quality)
      r.name:SetTextColor(c[1], c[2], c[3], 1)
      local nh = line(r.name, r, 0, 0, math.max(20, inner - gw - SP.s), it.name)
      local h1 = math.max(gh, nh)
      local where = (CG.SLOT_LABEL[row.slotId] or "") .. "  /  " .. Panoply.Gear.SourceText(row.source)
      if row.locked and row.lockReason then where = where .. "  /  " .. row.lockReason end
      if row.hasEffect then where = where .. "  /  has an effect that is not scored" end
      local y2 = block(r.from, r, 0, -h1 - 1, inner, where)
      r:SetSize(inner, -y2)
      r.panoplyItem = it
      r.panoplyTipLine = row.pairedWith and ("With " .. (row.pairedWith.name or "an off-hand item") .. ", instead of your two-hand weapon.")
        or (row.replaces and ("Instead of " .. (row.replaces.name or "what you wear") .. ".")) or "That slot is empty now."
      local top = Panoply.Gear.BreakdownText(row, 3)
      if top ~= "" then r.panoplyTipLine = r.panoplyTipLine .. " " .. top .. "." end
      r:Show()
      y = y + y2 - SP.s
    else
      r:Hide()
      r.panoplyItem = nil
    end
  end
  if #list == 0 then
    y = block(uc.empty, uc, PAD, y, inner, CG.EMPTY_TEXT[state ~= "ok" and state or "none"]) - SP.s
  else
    uc.empty:Hide()
  end
  p.upgradeRows, p.upgradeState = #list, state
  return -y + PAD - SP.s
end

function CG:FillPanel(p)
  if not p.built then build(p) end
  local parent = p:GetParent()
  local W = parent and parent.GetWidth and parent:GetWidth() or 0
  if not W or W < CG.PANEL_MIN_W then W = (p.panoplyWidth and p.panoplyWidth >= CG.PANEL_MIN_W) and p.panoplyWidth or CG.PANEL_W end
  local who = Panoply.Gear:GetContext() or {}
  local y = 0
  -- the heading, the line under it and the planner button
  p.title:ClearAllPoints(); p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
  p.title:SetWidth(W); p.title:SetText(who.stats and ("Gear for your " .. (CG.CLASS_NAME[who.class] or "class")) or "Gear")
  local hh = TH(p.title, W); p.title:SetHeight(hh)
  y = y - hh - SP.xs
  y = block(p.sub, p, 0, y, W, who.stats and (who.weighedFor .. ". " .. (FROM_TEXT[who.from or "default"] or "")) or CG.EMPTY_TEXT.noclass) - SP.s
  local st = Panoply.SpecTrainer
  if st and st.OpenPlanner and who.stats then
    local _, bh = Skin.FitButton(p.plan, 120, W)
    p.plan:ClearAllPoints(); p.plan:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
    p.plan:Show()
    y = y - bh - SP.m
  else
    p.plan:Hide()
    y = y - SP.xs
  end
  -- the two cards: side by side when there is room
  local two = W >= CG.TWO_COLUMNS_FROM
  local cw = two and math.floor((W - SP.m) / 2) or W
  local hw = fillWorn(p, cw, who)
  local hu = fillUps(p, cw, who)
  p.worn:ClearAllPoints(); p.ups:ClearAllPoints()
  p.worn:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
  if two then
    local h = math.max(hw, hu)
    p.worn:SetSize(cw, h); p.ups:SetSize(cw, h)
    p.ups:SetPoint("TOPLEFT", p, "TOPLEFT", cw + SP.m, y)
    y = y - h - SP.m
  else
    p.worn:SetSize(cw, hw); p.ups:SetSize(cw, hu)
    p.ups:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y - hw - SP.m)
    y = y - hw - SP.m - hu - SP.m
  end
  p.worn:Show(); p.ups:Show()
  y = block(p.note, p, 0, y, W, CG.NOTE)
  p.contentH, p.panoplyWidth, p.columns = math.ceil(-y), W, two and 2 or 1
  p:SetSize(W, p.contentH)
  p.stamp = CG.stamp
  return p.contentH
end

CG.panels = setmetatable({}, { __mode = "k" })   -- parent -> its panel

function CG:BuildPanel(parent)
  if type(parent) ~= "table" or not parent.CreateTexture then return nil end
  local p = CG.panels[parent]
  if p then p:Refresh() return p end
  p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  p.panoplyClassGear = true
  function p:Refresh() return CG:FillPanel(self) end
  function p:GetContentHeight() return self.contentH or 0 end
  p:SetScript("OnShow", function(self) if self.stamp ~= CG.stamp then self:Refresh() end end)
  -- the parent got its width, or a new one: lay out again (not for our own SetSize)
  if parent.HookScript then
    pcall(parent.HookScript, parent, "OnSizeChanged", function()
      local w = parent.GetWidth and parent:GetWidth() or 0
      if w >= CG.PANEL_MIN_W and w ~= p.panoplyWidth then p:Refresh() end
    end)
  end
  CG.panels[parent] = p
  p:Refresh()
  return p
end

-- the engine has something new for the character (a long list finishing counts; its progress does not)
Panoply:Listen("GEAR_CHANGED", function(ctxKey, what)
  if what == "progress" or not (ctxKey == nil or ctxKey == "player") then return end
  CG.stamp = (CG.stamp or 0) + 1
  for _, p in pairs(CG.panels) do
    if p.IsVisible and p:IsVisible() then p:Refresh() end
  end
end)
