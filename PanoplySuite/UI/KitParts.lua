-- Panoply Suite 0.9.5, phase 4A: the shared visual system (docs/specs/page-redesigns-v1.md section 1). It is defined once here, on
-- top of UI/Kit.lua, and every redesigned page reads from it; no page hand-styles a colour, a border or a bar.
--
--   Tokens (1.1)       Kit.Color("surface.1") / Kit.Accent("gathering") / Kit.ClassColor("MAGE") / Kit.Space(1..4)
--   Icon slots (9)     Kit.Icon(tex, "icon.ui.help") resolves a semantic slot against the theme first, then the game's own art, and
--                      Kit.IconReport() lists how every slot resolved (theme, game or missing) for the final report
--   Components (1.2)   Kit.Surface (a card: one step lighter, no border, an optional 2 px accent stripe)
--                      Kit.SectionHeader (serif gold title, one thin gold rule, an optional ? that holds the explanation)
--                      Kit.TextTab (underlined text tabs: Kit.Tabs with style = "underline"; a dropdown on a narrow page)
--                      Kit.Pips (totals of 6 or less), Kit.ProgressBar (6 to 8 px, accent fill, marker ticks)
--                      Kit.IconCell (done / in progress / not done / locked), Kit.TalentNode + Kit.TalentArrow
--                      Kit.StatusChip, Kit.Shine + Kit.Toast
--   Bands (1.3)        Kit.Band(width): "wide" (over 820), "medium" (560 to 820), "narrow" (under 560)
--
-- No glow anywhere (CLAUDE.md rule 3 and the skin): the spec's "small glow at the fill end" is a flat bright tip, and its "shine" is a
-- flat highlight that fades in and out. Nothing here is a protected frame, and nothing here creates one.
local ADDON, Panoply = ...
local Skin, Kit, C = Panoply.Skin, Panoply.Kit, Panoply.Compat
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-------------------------------------------------------------------------------
-- Tokens
-------------------------------------------------------------------------------
-- token -> the key of the colour in Skin.colors (every colour the add-on draws with lives in UI/Skin.lua)
Kit.TOKENS = {
  ["surface.0"] = "panel",          -- the window background
  ["surface.1"] = "surface1",       -- anything that reads as a card (no border)
  ["surface.2"] = "surface2",       -- hovered and selected rows
  ["text.primary"] = "text",        -- numbers and names
  ["text.muted"] = "inkSoft",       -- body copy and captions
  ["gold.title"] = "heading",       -- page titles and section headings only
  ["rule"] = "gold",                -- the one thin rule under a section heading
  ["accent.professions"] = "accentBronze", ["accent.crafting"] = "accentBronze",
  ["accent.gathering"] = "accentMoss", ["accent.secondary"] = "accentSteel",
  ["accent.legacy.professions"] = "accentBronze", ["accent.legacy.adventure"] = "accentMoss",
  ["accent.legacy.resourcefulness"] = "accentSteel",
  -- what a state means (always with a word or a mark beside it: colour is never the only cue)
  ["state.good"] = "done", ["state.warn"] = "highlight", ["state.bad"] = "loss", ["state.idle"] = "dim",
}
Kit.unknownTokens = {}
-- the colour of a token: { r, g, b } (the same table Skin.colors holds, so a re-skin reaches it)
function Kit.Color(token)
  local key = Kit.TOKENS[token or ""]
  if key and Skin.colors[key] then return Skin.colors[key] end
  if type(token) == "string" then
    local cls = token:match("^accent%.class%.(%u+)$")
    if cls then return Kit.ClassColor(cls) end
    Kit.unknownTokens[token] = true
  end
  return Skin.colors.text
end
-- the accent of a section: "professions", "gathering", "legacy.adventure", "class.MAGE"
function Kit.Accent(section)
  if type(section) == "table" then return section end
  return Kit.Color("accent." .. tostring(section or "professions"))
end
-- the game's class colours when it has them, else the standard ones
Kit.CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1, 0.96, 0.41 },
  PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}
function Kit.ClassColor(classFile)
  local t = _G.RAID_CLASS_COLORS
  local c = type(t) == "table" and t[classFile]
  if type(c) ~= "table" and _G.C_ClassColor and C_ClassColor.GetClassColor then
    local ok, v = pcall(C_ClassColor.GetClassColor, classFile)
    if ok then c = v end
  end
  if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
  return Kit.CLASS_COLORS[classFile or ""] or Skin.colors.text
end
-- space.1 to space.4: 4 / 8 / 12 / 16. A window is drawn at the Size setting as a whole (Panoply.Windows scales the frame), so these are
-- in the window's own units and need no factor of their own.
Kit.SPACE4 = { 4, 8, 12, 16 }
function Kit.Space(n) return Kit.SPACE4[max(1, min(4, floor(n or 1)))] end
function Kit.SizeScale() return Panoply.Look.WindowScale() end

local function tint(tex, c, a) tex:SetVertexColor(c[1], c[2], c[3], a or 1) end
local function lighter(c, k)
  k = k or 0.35
  return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end
Kit.Lighter = lighter

-------------------------------------------------------------------------------
-- Resize bands (1.3)
-------------------------------------------------------------------------------
-- The bands are measured in the page's own units: the width a page lays itself out for (p.width). That IS "content pane width
-- divided by the Size setting": a window drawn at Large is 1.3 times as wide on the screen, so on the screen Large changes band
-- 1.3 times sooner, exactly as the spec asks, while a page always changes at the same width of its own. Kit.EffectiveWidth turns a
-- width measured on the screen into the page's units for a caller that only has that.
Kit.BAND = { wide = 820, medium = 560 }
function Kit.EffectiveWidth(screenWidth, scale)
  scale = scale or Kit.SizeScale()
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  return (screenWidth or 0) / scale
end
function Kit.Band(width)
  width = width or 0
  if width > Kit.BAND.wide then return "wide" end
  if width >= Kit.BAND.medium then return "medium" end
  return "narrow"
end
-- the band of a main-window page (its body frame carries the width it is laid out for)
function Kit.PageBand(p) return Kit.Band(p and p.width or (Panoply.Menu and Panoply.Menu.hostW) or 0) end

-------------------------------------------------------------------------------
-- Icon slots (spec section 9). A slot resolves against the theme first; the game's own art is the fallback, and only a file the
-- game says it has is ever drawn (an unknown file would be a green square). Kit.IconReport() says how each slot resolved.
--   theme sources:  icon = a page / control icon of the skin (Skin.SetIcon), glyph = a control glyph (Skin.SetGlyph),
--                   file = one of Panoply's own textures in Media (with optional coords to flip it), mark = a check mark (Skin.SetMark)
--   game fallback:  game = { paths }, the first the game has
-- A page registers its own slots with Kit.RegisterIcon(slot, def).
-------------------------------------------------------------------------------
local I, B = "Interface\\Icons\\", "Interface\\Buttons\\"
Kit.ICONS = {
  -- (0.9.5 phase 4C: not `own`: in the WoW icon style the ? is the game's own question mark, like every icon outside the menu's list)
  ["icon.ui.help"] = { icon = "Help" },
  ["icon.ui.gear"] = { glyph = "Gear" },
  ["icon.ui.map"] = { glyph = "Map" },
  ["icon.ui.arrow"] = { glyph = "Arrow" },   -- 0.9.5 phase 4K: the same Route drawing (J_GLYPHS.Arrow), with the game's Pathfinding in WoW icons
  ["icon.ui.back"] = { file = "ScrollArrowRight", coords = { 1, 0, 0, 1 } },      -- the skin's own arrow, mirrored
  ["icon.ui.forward"] = { file = "ScrollArrowRight" },
  ["icon.trend.up"] = { file = "ScrollArrow" },
  ["icon.trend.down"] = { file = "ScrollArrow", coords = { 0, 1, 1, 0 } },
  ["icon.state.done"] = { mark = "Check" },
  ["icon.state.locked"] = { glyph = "Lock" },
  ["icon.guide"] = { icon = "Leveling", own = true },
  ["icon.ui.edit"] = { game = { B .. "UI-GuildButton-PublicNote-Up", I .. "INV_Misc_Note_01" } },
  ["icon.ui.popout"] = { game = { B .. "UI-Panel-ExpandButton-Up", I .. "INV_Misc_Spyglass_02" } },
  -- (0.9.5 phase 4F: a cog, which the spec allows for the row menus: the same picture as the page header's settings button, the
  -- theme's in Panoply icons and the game's in WoW icons. The theme has no three-dot drawing, and the game file UI-OptionsButton is not
  -- certain on either game.)
  ["icon.ui.more"] = { icon = "Settings" },
  ["icon.coin.gold"] = { game = { "Interface\\MoneyFrame\\UI-GoldIcon", I .. "INV_Misc_Coin_01" }, raw = true },
  ["icon.coin.silver"] = { game = { "Interface\\MoneyFrame\\UI-SilverIcon", I .. "INV_Misc_Coin_03" }, raw = true },
  ["icon.coin.copper"] = { game = { "Interface\\MoneyFrame\\UI-CopperIcon", I .. "INV_Misc_Coin_05" }, raw = true },
}
-- 0.9.5 phase 4K (spec 05 sections 4.4 and 7, spec 06a section 4): the step types (Panoply.StepText.TYPES; the same skin keys
-- Panoply.UI.StepIconName gives, so a slot and a step's icon never differ), the trip legs and the Guide page's On your screen toggles
for _, t in ipairs({ "accept", "turnin", "kill", "collect", "use", "travel", "train", "group" }) do
  local key = ({ accept = "Accept", turnin = "TurnIn", kill = "Kill", collect = "Collect", use = "Use", travel = "Travel", train = "Train", group = "Group" })[t]
  Kit.ICONS["icon.step." .. t] = { icon = key }
end
Kit.ICONS["icon.leg.walk"] = { icon = "Walk" }
Kit.ICONS["icon.leg.fly"] = { icon = "Fly" }
Kit.ICONS["icon.leg.boat"] = { icon = "Boat" }
Kit.ICONS["icon.leg.zeppelin"] = { icon = "Zeppelin" }
Kit.ICONS["icon.leg.tram"] = { icon = "Tram" }
Kit.ICONS["icon.leg.hearth"] = { icon = "Hearth" }
Kit.ICONS["icon.toggle.arrow"] = { glyph = "Arrow" }   -- our Route drawing (J_GLYPHS.Arrow); in WoW icons the game's Pathfinding (GAME_GLYPHS.Arrow)
Kit.ICONS["icon.toggle.trail"] = { icon = "Trail" }
Kit.ICONS["icon.toggle.tracker"] = { icon = "Tracker" }
Kit.ICONS["icon.toggle.together"] = { icon = "Partner" }
function Kit.RegisterIcon(slot, def) Kit.ICONS[slot] = def end

-- how a slot resolves now: "theme" | "game" | "missing", and what it resolves to
-- 0.9.5 phase 4K: a slot drawn with our own art in both styles (own = true) may name `wow`, the game icon (a Skin.GAME_ICONS key)
-- it shows in WoW icons, so "in WoW icons every icon is the game's" holds for it too (Home's tiles)
local function slotDef(slot)
  local d = Kit.ICONS[slot or ""]
  if d and d.wow and Skin.WoW() then return { icon = d.wow } end
  return d
end
function Kit.ResolveIcon(slot)
  local d = slotDef(slot)
  if not d then return "missing", nil end
  if d.file then return "theme", Skin.MEDIA .. d.file end
  if d.icon then
    if d.own and Skin.J_MENU[d.icon] then return "theme", Skin.JIcon(Skin.J_MENU[d.icon]) end
    if not Skin.WoW() and Skin.J_ICONS[d.icon] then return "theme", Skin.JIcon(Skin.J_ICONS[d.icon]) end
    local r = Skin.Resolve(Skin.GAME_ICONS, d.icon)
    if r then return "game", r.path or r.atlas end
    return "theme", Skin.ICON(d.icon)
  end
  if d.glyph then
    if not Skin.WoW() and Skin.J_GLYPHS[d.glyph] then return "theme", Skin.JIcon(Skin.J_GLYPHS[d.glyph]) end
    local r = Skin.Resolve(Skin.GAME_GLYPHS, d.glyph) or Skin.Resolve(Skin.GAME_ICONS, d.glyph)
    if r then return "game", r.path or r.atlas end
    return "theme", Skin.GLYPH(d.glyph)
  end
  if d.mark then
    local r = Skin.Resolve(Skin.GAME_GLYPHS, d.mark)
    if r then return "game", r.path or r.atlas end
    return "theme", Skin.TEX.Check
  end
  for _, p in ipairs(d.game or {}) do
    if C.FileExists(p) == true then return "game", p end
  end
  return "missing", nil
end

-- Put a slot's picture on a texture. Returns how it resolved. A missing slot hides the texture.
function Kit.Icon(tex, slot, opts)
  if not tex then return "missing" end
  opts = opts or {}
  local d = slotDef(slot)
  local how, what = Kit.ResolveIcon(slot)
  tex.panoplySlot, tex.panoplySlotHow = slot, how
  if how == "missing" or not d then tex:Hide() return "missing" end
  if d.file then
    Skin.live[tex] = nil
    tex:SetTexture(what)
    local co = d.coords
    if tex.SetTexCoord then if co then tex:SetTexCoord(co[1], co[2], co[3], co[4]) else tex:SetTexCoord(0, 1, 0, 1) end end
    tint(tex, opts.tint or Skin.colors.icon)
  elseif d.icon then Skin.SetIcon(tex, d.icon, { size = opts.size, own = d.own })
  elseif d.glyph then Skin.SetGlyph(tex, d.glyph, { size = opts.size, tint = opts.tint })
  elseif d.mark then Skin.SetMark(tex, d.mark)
  else
    Skin.live[tex] = nil
    tex:SetTexture(what)
    if tex.SetTexCoord then if d.raw then tex:SetTexCoord(0, 1, 0, 1) else tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end end
    if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
  end
  tex:Show()
  return how
end

-- every slot, in name order: { slot, how, source }
function Kit.IconReport()
  local names = {}
  for slot in pairs(Kit.ICONS) do names[#names + 1] = slot end
  table.sort(names)
  local out = {}
  for _, slot in ipairs(names) do
    local how, what = Kit.ResolveIcon(slot)
    out[#out + 1] = { slot = slot, how = how, source = what, candidates = Kit.ICONS[slot].game }
  end
  return out
end

-------------------------------------------------------------------------------
-- Surface: a card. One step lighter than what it sits on, rounded, NO border. An accent is a 2 px stripe down its left edge.
-------------------------------------------------------------------------------
function Kit.Surface(parent, level)
  local f = CreateFrame("Frame", nil, parent)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  Skin.Round(fill, Skin.RADIUS.card, Skin.TEX.RFill)
  tint(fill, Kit.Color("surface." .. (level or 1)))
  f.panoplyBg, f.panoplyBox, f.panoplyGapOK, f.panoplyKit = fill, true, true, "Surface"
  f.panoplyLevel = level or 1
  function f:SetLevel(l)
    self.panoplyLevel = l
    tint(self.panoplyBg, Kit.Color("surface." .. l))
  end
  function f:SetAccent(accent)
    if not accent then if self.stripe then self.stripe:Hide() end self.panoplyAccent = nil return end
    local c = Kit.Accent(accent)
    if not self.stripe then
      local s = self:CreateTexture(nil, "BORDER")
      s:SetWidth(2)
      s:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -Skin.RADIUS.card)
      s:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, Skin.RADIUS.card)
      self.stripe = s
    end
    Skin.Solid(self.stripe, c, 1)
    self.stripe:Show()
    self.panoplyAccent = c
  end
  return f
end

-------------------------------------------------------------------------------
-- The ? that holds an explanation (explanations live in tooltips, never in body copy)
-------------------------------------------------------------------------------
function Kit.HelpIcon(parent, title, body, size)
  size = size or 16
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.panoplyKit = "HelpIcon"
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(b)
  b.icon = t
  b.panoplyIconHow = Kit.Icon(t, "icon.ui.help", { size = size })
  Skin.Tooltip(b, title, body)
  b:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  return b
end

-------------------------------------------------------------------------------
-- SectionHeader: serif title in gold, one thin gold rule under it, an optional ? at the right
-------------------------------------------------------------------------------
-- opts.title, opts.help (the explanation, shown in the ?'s tooltip), opts.size (15)
-- h:Layout(x, y, w) places it at (x, y) of its parent and returns its height.
function Kit.SectionHeader(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f.panoplyGapOK, f.panoplyKit = true, "SectionTitle"
  f.title = Skin.Heading(f, opts.size or 15, opts.title or "")
  local gt = Kit.Color("gold.title")
  f.title:SetTextColor(gt[1], gt[2], gt[3], 1)
  f.rule = f:CreateTexture(nil, "ARTWORK")
  Skin.Solid(f.rule, Kit.Color("rule"), 0.55)
  f.rule:SetHeight(1)
  f.rule.panoplyRule = true
  f.panoplyTitle, f.panoplyHelp = opts.title or "", opts.help
  function f:SetTitle(t) self.panoplyTitle = t or "" self.title:SetText(self.panoplyTitle) end
  function f:SetHelp(body)
    self.panoplyHelp = body
    if body and not self.help then self.help = Kit.HelpIcon(self, self.panoplyTitle, body) end
    if self.help then self.help.tip, self.help.tipBody = self.panoplyTitle, body end
  end
  function f:Layout(x, y, w)
    self:ClearAllPoints(); self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", x or 0, y or 0)
    local hw = (self.panoplyHelp and self.help) and (16 + SP.s) or 0
    local tw = max(40, w - hw)
    self.title:ClearAllPoints(); self.title:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.title:SetWidth(tw)
    local th = ceil(TH(self.title, tw))
    self.title:SetHeight(th)
    if self.help then
      if self.panoplyHelp then
        self.help:ClearAllPoints(); self.help:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -max(0, floor((th - 16) / 2)))
        self.help:Show()
      else self.help:Hide() end
    end
    local h = max(th, hw > 0 and 16 or 0) + Kit.Space(1) + 1
    self.rule:ClearAllPoints()
    self.rule:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0); self.rule:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    self:SetSize(w, h)
    self:Show()
    return h
  end
  f:SetHelp(opts.help)
  return f
end

-------------------------------------------------------------------------------
-- TextTab: a tab that is its words, underlined in gold when it is the one showing (Kit.Tabs with opts.style = "underline")
-------------------------------------------------------------------------------
function Kit.TextTab(parent, label, w, onClick, tip, tipBody)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 100, Kit.TAB.h)
  b.panoplyBox, b.panoplyKit = true, "TextTab"
  local fs = Skin.Text(b, 13, Kit.Color("text.muted"), nil, "semi")
  fs:SetPoint("CENTER", b, "CENTER", 0, 1)
  if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(label or "")
  b.label = fs
  local line = b:CreateTexture(nil, "ARTWORK")
  Skin.Solid(line, Kit.Color("gold.title"), 1)
  line:SetHeight(2)
  line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", SP.s, 2); line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -SP.s, 2)
  b.underline = line
  Skin.Tooltip(b, tip or label, tipBody)
  function b:Paint()
    local st = self.active and "sel" or (self.hover and "hover" or "idle")
    self.state = st
    local c = Kit.Color(st == "sel" and "gold.title" or (st == "hover" and "text.primary" or "text.muted"))
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    if st == "sel" then self.underline:Show() else self.underline:Hide() end
  end
  function b:SetActive(on) self.active = on and true or false self:Paint() end
  function b:NeedWidth() return ceil(TW(self.label) + 2 * SP.m) end
  b:SetScript("OnEnter", function() b.hover = true b:Paint() if b.panoplyShowTip then b.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() b.hover = false b:Paint() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() if onClick then onClick(b) end end)
  b:SetActive(false)
  return b
end

-------------------------------------------------------------------------------
-- Pips: a total of 6 or less (3 dungeons, 5 ranks). An empty pip is an outline in the accent at 40%; a filled one is solid.
-------------------------------------------------------------------------------
Kit.PIPS_MAX = 6
-- true when a total is small enough for pips (else it is a ProgressBar: never an empty bar for a small total)
function Kit.UsePips(total) return (total or 0) >= 1 and total <= Kit.PIPS_MAX end
-- opts.accent, opts.size (9), opts.gap (4). p:Set(done, total[, accent]) returns its width.
function Kit.Pips(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f.panoplyKit, f.panoplyGapOK = "Pips", true
  f.pips = {}
  f.size, f.gap = opts.size or 9, opts.gap or 4
  f.accent = Kit.Accent(opts.accent or "professions")
  function f:Set(done, total, accent)
    if accent then self.accent = Kit.Accent(accent) end
    total = max(0, floor(total or 0))
    self.over = total > Kit.PIPS_MAX      -- a caller's mistake: more than six is a bar's job; the first six are drawn
    total = min(total, Kit.PIPS_MAX)
    done = max(0, min(total, floor(done or 0)))
    local s, g, c = self.size, self.gap, self.accent
    for i = 1, total do
      local p = self.pips[i]
      if not p then
        p = { ring = self:CreateTexture(nil, "ARTWORK"), dot = self:CreateTexture(nil, "ARTWORK") }
        p.ring:SetTexture(Skin.TEX.GatherRing)
        p.dot:SetTexture(Skin.TEX.CircleMask)
        self.pips[i] = p
      end
      for _, t in ipairs({ p.ring, p.dot }) do
        t:SetSize(s, s)
        t:ClearAllPoints(); t:SetPoint("LEFT", self, "LEFT", (i - 1) * (s + g), 0)
      end
      tint(p.ring, c, 0.4); tint(p.dot, c, 1)
      p.filled = i <= done
      if p.filled then p.dot:Show() p.ring:Hide() else p.dot:Hide() p.ring:Show() end
    end
    for i = total + 1, #self.pips do self.pips[i].dot:Hide() self.pips[i].ring:Hide() self.pips[i].filled = nil end
    self.done, self.total = done, total
    local w = total > 0 and (total * s + (total - 1) * g) or 1
    self:SetSize(w, s)
    return w
  end
  f:Set(0, 0)
  return f
end

-------------------------------------------------------------------------------
-- ProgressBar: 6 to 8 px tall, accent fill, a 1 px lighter line along the fill's top edge and a flat bright tip at its end
-- (no glow), optional marker ticks (the Legacy marks at 150 / 225 / 300 on a skill bar, reward thresholds).
-------------------------------------------------------------------------------
-- opts.h (7), opts.accent. bar:SetBarWidth(w), bar:SetProgress(0..1), bar:SetValue(cur, max),
-- bar:SetTicks({ { at = 0..1 | value = n, reached = bool, tip, tipBody, onClick, key } }), bar:SetAccent(accent)
function Kit.ProgressBar(parent, opts)
  opts = opts or {}
  local h = max(6, min(8, opts.h or 7))
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(h)
  bar.panoplyKit, bar.panoplyGapOK = "ProgressBar", true
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  Skin.Round(bg, h / 2, Skin.TEX.RFill)
  tint(bg, Skin.colors.slotBottom)
  bg.panoplyBarTrack = true
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0); fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  fill:SetWidth(h)
  Skin.Round(fill, h / 2, Skin.TEX.RFill)
  fill.panoplyBarFill = true
  bg.panoplyBarFillTex = fill
  local hi = bar:CreateTexture(nil, "OVERLAY")
  hi:SetHeight(1)
  hi:SetPoint("TOPLEFT", fill, "TOPLEFT", h / 2, 0); hi:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -h / 2, 0)
  local tip = bar:CreateTexture(nil, "OVERLAY")
  tip:SetSize(2, max(2, h - 4))
  tip:SetPoint("RIGHT", fill, "RIGHT", -max(2, floor(h / 2)), 0)
  bar.bg, bar.fill, bar.highlight, bar.tipMark = bg, fill, hi, tip
  bar.ticks, bar.tickList = {}, {}
  bar.progress, bar.h = 0, h
  function bar:SetAccent(accent)
    local c = Kit.Accent(accent or "professions")
    self.accent = c
    tint(self.fill, c)
    Skin.Solid(self.highlight, lighter(c, 0.45), 0.9)
    Skin.Solid(self.tipMark, lighter(c, 0.7), 1)
  end
  local function width(self)
    local w = self.panoplyWidth or self:GetWidth() or 0
    if w <= 0 then w = 200 end
    return w
  end
  function bar:Place()
    local w, p = width(self), self.progress
    if p <= 0 then self.fill:Hide() self.highlight:Hide() self.tipMark:Hide()
    else
      local fw = max(self.h, w * p)
      self.fill:SetWidth(fw)
      self.fill:Show()
      -- the line and the tip only where the fill is long enough to carry them
      if fw > self.h + 4 then self.highlight:Show() self.tipMark:Show() else self.highlight:Hide() self.tipMark:Hide() end
    end
    for i, tk in ipairs(self.tickList) do
      local b = self.ticks[i]
      local at = tk.at
      if not at and tk.value and (self.maxValue or 0) > 0 then at = tk.value / self.maxValue end
      at = max(0, min(1, at or 0))
      b.panoplyAt = at
      b:ClearAllPoints(); b:SetPoint("CENTER", self, "LEFT", floor(w * at + 0.5), 0)
      local reached = tk.reached
      if reached == nil then reached = p >= at end
      b.panoplyReached = reached and true or false
      Skin.Solid(b.line, Kit.Color(reached and "gold.title" or "text.muted"), reached and 1 or 0.8)
      b:Show()
    end
    for i = #self.tickList + 1, #self.ticks do self.ticks[i]:Hide() end
  end
  function bar:SetBarWidth(w) self.panoplyWidth = w self:SetWidth(w) self:Place() end
  function bar:SetProgress(p)
    self.progress = max(0, min(1, p or 0))
    self:Place()
  end
  function bar:SetValue(cur, maxV)
    self.value, self.maxValue = cur or 0, maxV or 0
    self:SetProgress((maxV or 0) > 0 and (cur or 0) / maxV or 0)
  end
  function bar:SetTicks(list)
    self.tickList = list or {}
    for i, tk in ipairs(self.tickList) do
      local b = self.ticks[i]
      if not b then
        b = CreateFrame("Button", nil, self)
        b:SetSize(9, self.h + 4)
        b.panoplyKit, b.panoplyLayoutSkip = "BarTick", true
        b.line = b:CreateTexture(nil, "OVERLAY")
        b.line:SetSize(1, self.h + 4)
        b.line:SetPoint("CENTER", b, "CENTER", 0, 0)
        Skin.Tooltip(b, "", nil)
        b:SetScript("OnEnter", function(s) if s.tip and s.tip ~= "" and s.panoplyShowTip then s.panoplyShowTip() end end)
        b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
        b:SetScript("OnClick", function(s) if s.panoplyTick and s.panoplyTick.onClick then s.panoplyTick.onClick(s.panoplyTick) end end)
        self.ticks[i] = b
      end
      b.panoplyTick = tk
      b.tip, b.tipBody = tk.tip or "", tk.tipBody
    end
    self:Place()
  end
  bar:SetAccent(opts.accent)
  bar:SetTicks(opts.ticks)
  return bar
end

-------------------------------------------------------------------------------
-- Shine: a short flat highlight on a frame (an auto-detected completion). No glow: a flat wash that fades in and out.
-------------------------------------------------------------------------------
Kit.SHINE_TIME, Kit.SHINE_ALPHA = 0.5, 0.35
function Kit.Shine(frame, color)
  if not (frame and frame.CreateTexture) then return false end
  local t = frame.panoplyShine
  if not t then
    t = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetAllPoints(frame)
    Skin.Solid(t, color or Kit.Color("gold.title"), 1)
    t:SetAlpha(0)
    frame.panoplyShine = t
  end
  frame.panoplyShines = (frame.panoplyShines or 0) + 1
  t:Show()
  -- up in the first third, down in the rest
  Skin.Tween(t, 0, 1, Kit.SHINE_TIME, function(o, v)
    local k = v < 0.33 and v / 0.33 or (1 - v) / 0.67
    o:SetAlpha(Kit.SHINE_ALPHA * max(0, k))
  end, function(o) o:SetAlpha(0) o:Hide() end)
  return true
end

-- a reward that unlocked pulses its icon once: the same short flat highlight
function Kit.Pulse(frame, color) return Kit.Shine(frame, color) end

-- A banner for something that completed by itself ("Legacy: Druid 25 - 13/65"). opts.title (the banner's heading), opts.cell (a
-- frame that shines with it). The shine is drawn whether or not banners are on; the banner respects the setting (kitToasts: a NEW
-- account key, on unless turned off: Help > gear > Look). Returns true when the banner was shown.
function Kit.ToastsOn() return not (Panoply.db and Panoply.db.kitToasts == false) end
-- a profile holds the choice (Engine/Profiles.lua: every setting with a row in a gear)
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "kitToasts" }) end
function Kit.Toast(text, opts)
  opts = opts or {}
  if opts.cell then Kit.Shine(opts.cell) end
  if not Kit.ToastsOn() then return false end
  local T = Panoply.Toast
  if not (T and T.Display) then return false end
  T:Display(opts.title or "Done", text or "")
  Kit.lastToast = { title = opts.title or "Done", text = text or "" }
  return true
end

-------------------------------------------------------------------------------
-- IconCell: a square icon with four states
--   done      full colour, a small check badge            progress   full colour, a partial accent ring (how far along)
--   todo      desaturated, 60%                            locked     desaturated, a lock badge, the date or reason in the tooltip
-------------------------------------------------------------------------------
Kit.CELL_STATES = { done = true, progress = true, todo = true, locked = true }
-- opts.size (36), opts.accent, opts.onClick(cell, button)
-- cell:SetTexture(path | fileID), cell:SetSlot("icon.x"), cell:SetState(state, { progress = 0..1, accent, tip, tipBody })
function Kit.IconCell(parent, opts)
  opts = opts or {}
  local s = opts.size or 36
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(s, s)
  c.panoplyKit, c.panoplyGapOK = "IconCell", true
  c.size = s
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 2, -2); c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -2, 2)
  if c.icon.SetTexCoord then c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  -- the ring: four sides, drawn clockwise from the top left for as much of the way round as the progress
  c.ring = {}
  for i = 1, 4 do c.ring[i] = c:CreateTexture(nil, "OVERLAY") end
  c.badge = c:CreateTexture(nil, "OVERLAY", nil, 5)
  c.badge:SetSize(max(12, floor(s * 0.4)), max(12, floor(s * 0.4)))
  c.badge:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -3)
  c.badge:Hide()
  c.accent = Kit.Accent(opts.accent or "professions")
  Skin.Tooltip(c, "", nil)
  c:SetScript("OnEnter", function(self) if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
  c:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  c:SetScript("OnClick", function(self, button) if opts.onClick then opts.onClick(self, button) end end)
  function c:SetTexture(tex)
    self.panoplyTexture = tex
    self.icon:SetTexture(tex)
    if self.icon.SetTexCoord then self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    self.icon:Show()
  end
  function c:SetSlot(slot)
    self.panoplySlot = slot
    return Kit.Icon(self.icon, slot, { size = self.size })
  end
  function c:SetRing(p, accent)
    local col = accent and Kit.Accent(accent) or self.accent
    local n = self.size
    p = max(0, min(1, p or 0))
    self.panoplyRing = p
    for i = 1, 4 do
      local t = self.ring[i]
      local frac = max(0, min(1, p * 4 - (i - 1)))
      if frac <= 0 then t:Hide() else
        local len = max(2, floor(n * frac + 0.5))
        Skin.Solid(t, col, 1)
        t:ClearAllPoints()
        if i == 1 then t:SetSize(len, 2) t:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        elseif i == 2 then t:SetSize(2, len) t:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        elseif i == 3 then t:SetSize(len, 2) t:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        else t:SetSize(2, len) t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0) end
        t:Show()
      end
    end
  end
  function c:SetState(state, o)
    o = o or {}
    if not Kit.CELL_STATES[state] then state = "todo" end
    self.state = state
    if o.accent then self.accent = Kit.Accent(o.accent) end
    local grey = state == "todo" or state == "locked"
    if self.icon.SetDesaturated then self.icon:SetDesaturated(grey) end
    self.icon.panoplyDesat = grey
    self.icon:SetAlpha(grey and 0.6 or 1)
    self:SetRing(state == "progress" and (o.progress or 0) or 0)
    if state == "done" then self.panoplyBadge = "icon.state.done" Kit.Icon(self.badge, "icon.state.done", { size = 14 })
    elseif state == "locked" then self.panoplyBadge = "icon.state.locked" Kit.Icon(self.badge, "icon.state.locked", { size = 14 })
    else self.panoplyBadge = nil self.badge:Hide() end
    if o.tip ~= nil then self.tip = o.tip end
    if o.tipBody ~= nil or o.tip ~= nil then self.tipBody = o.tipBody end
    return state
  end
  function c:Shine() return Kit.Shine(self) end
  c:SetState("todo")
  return c
end

-------------------------------------------------------------------------------
-- TalentNode: a square icon with a rank badge at the bottom right ("2/5"). Border grey when it cannot be taken, green when it has
-- ranks, gold when it is full. A locked tier's nodes are desaturated. Kit.TalentArrow draws the prerequisite arrow between two.
-------------------------------------------------------------------------------
Kit.NODE_BORDER = { none = "slotLine", some = "done", full = "heading" }
-- opts.size (40), opts.onClick(node, button)
-- node:Set({ icon = path | fileID, slot = "icon.x", rank, max, available (default true), locked, tip, tipBody })
function Kit.TalentNode(parent, opts)
  opts = opts or {}
  local s = opts.size or 40
  local n = CreateFrame("Button", nil, parent)
  n:SetSize(s, s)
  n.panoplyBox, n.panoplyKit, n.panoplyGapOK = true, "TalentNode", true
  n.size = s
  local bg, rim = Skin.Box(n, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.slotLine })
  n.bg, n.rim = bg, rim
  n.icon = n:CreateTexture(nil, "ARTWORK")
  n.icon:SetPoint("TOPLEFT", n, "TOPLEFT", 3, -3); n.icon:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", -3, 3)
  if n.icon.SetTexCoord then n.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  -- the rank: its own small plate so the numbers read on any icon
  -- (in the ARTWORK layer above the icon, so the numbers, which are in OVERLAY, are always drawn over it)
  local plate = n:CreateTexture(nil, "ARTWORK", nil, 6)
  Skin.Round(plate, 4, Skin.TEX.RFill)
  tint(plate, Skin.colors.bgDeep, 0.92)
  n.plate = plate
  n.rankText = Skin.Text(n, 10, Skin.colors.text, nil, "label")
  if n.rankText.SetWordWrap then n.rankText:SetWordWrap(false) end
  if n.rankText.SetJustifyH then n.rankText:SetJustifyH("RIGHT") end
  Skin.Tooltip(n, "", nil)
  n:SetScript("OnEnter", function(self) if self.tip and self.tip ~= "" and self.panoplyShowTip then self.panoplyShowTip() end end)
  n:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  if n.RegisterForClicks then n:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  n:SetScript("OnClick", function(self, button) if opts.onClick then opts.onClick(self, button) end end)
  function n:Set(o)
    o = o or {}
    local rank, maxR = o.rank or 0, o.max or 1
    self.rank, self.max = rank, maxR
    self.locked = o.locked and true or false
    self.available = (o.available ~= false) and not self.locked
    if o.slot then Kit.Icon(self.icon, o.slot, { size = self.size }) elseif o.icon ~= nil then
      self.icon:SetTexture(o.icon)
      if self.icon.SetTexCoord then self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
      self.icon:Show()
    end
    -- grey when it cannot be taken, green with ranks, gold when full
    local st = (rank >= maxR and rank > 0) and "full" or ((rank > 0) and "some" or "none")
    self.state = st
    local c = Skin.colors[Kit.NODE_BORDER[st]]
    self.rim:SetVertexColor(c[1], c[2], c[3], 1)
    local grey = self.locked or (st == "none" and not self.available)
    if self.icon.SetDesaturated then self.icon:SetDesaturated(grey) end
    self.icon.panoplyDesat = grey
    self.icon:SetAlpha(grey and 0.55 or 1)
    self.rankText:SetText(("%d/%d"):format(rank, maxR))
    local rc = st == "full" and Skin.colors.heading or (st == "some" and Skin.colors.done or Skin.colors.inkSoft)
    self.rankText:SetTextColor(rc[1], rc[2], rc[3], 1)
    local tw = ceil(TW(self.rankText)) + 2
    local th = ceil(TH(self.rankText))
    self.rankText:SetWidth(tw); self.rankText:SetHeight(th)
    self.rankText:ClearAllPoints(); self.rankText:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 2)
    self.plate:ClearAllPoints()
    self.plate:SetPoint("TOPLEFT", self.rankText, "TOPLEFT", -3, 1); self.plate:SetPoint("BOTTOMRIGHT", self.rankText, "BOTTOMRIGHT", 2, -1)
    if o.tip ~= nil then self.tip, self.tipBody = o.tip, o.tipBody end
    return st
  end
  n:Set({})
  return n
end

-- The prerequisite arrow from one node to another (side by side, or one above the other): a 2 px line from the edge of the first
-- to the edge of the second with a small head on the second. a:SetMet(true) draws it in gold (the prerequisite is full), else grey.
function Kit.TalentArrow(parent, from, to)
  local a = CreateFrame("Frame", nil, parent)
  a.panoplyKit, a.panoplyLayoutSkip = "TalentArrow", true
  a.from, a.to = from, to
  a.line = a:CreateTexture(nil, "ARTWORK")
  a.head = a:CreateTexture(nil, "ARTWORK")
  a.head:SetTexture(Skin.TEX.ScrollArrowRight or (Skin.MEDIA .. "ScrollArrowRight"))
  a.head:SetSize(8, 8)
  function a:SetMet(met)
    self.met = met and true or false
    local c = met and Skin.colors.heading or Skin.colors.slotLine
    Skin.Solid(self.line, c, 1)
    tint(self.head, c, 1)
  end
  -- across = true: the second node is to the right of the first (a prerequisite "to its left"); false: it is below it
  function a:Layout(across)
    self.across = across ~= false
    self:ClearAllPoints()
    self.line:ClearAllPoints(); self.head:ClearAllPoints()
    if self.across then
      self:SetPoint("TOPLEFT", self.from, "TOPRIGHT", 0, 0); self:SetPoint("BOTTOMRIGHT", self.to, "BOTTOMLEFT", 0, 0)
      self.line:SetHeight(2)
      self.line:SetPoint("LEFT", self, "LEFT", 1, 0); self.line:SetPoint("RIGHT", self, "RIGHT", -6, 0)
      self.head:SetPoint("RIGHT", self, "RIGHT", -1, 0)
      if self.head.SetRotation then self.head:SetRotation(0) end
    else
      self:SetPoint("TOPLEFT", self.from, "BOTTOMLEFT", 0, 0); self:SetPoint("BOTTOMRIGHT", self.to, "TOPRIGHT", 0, 0)
      self.line:SetWidth(2)
      self.line:SetPoint("TOP", self, "TOP", 0, -1); self.line:SetPoint("BOTTOM", self, "BOTTOM", 0, 6)
      self.head:SetPoint("BOTTOM", self, "BOTTOM", 0, 1)
      if self.head.SetRotation then self.head:SetRotation(-math.pi / 2) end
    end
    self:Show()
  end
  a:SetMet(false)
  return a
end

-------------------------------------------------------------------------------
-- StatusChip: a small rounded label. The word says the state; the colour only repeats it.
-------------------------------------------------------------------------------
Kit.CHIPS = {
  craft = { "Craft", "state.good" }, gather = { "Gather", "state.good" }, now = { "Now", "state.good" },
  train = { "Train now", "state.warn" }, soon = { "Soon", "state.warn" },
  blocked = { "Blocked", "state.bad" },
  done = { "Done", "state.idle" }, maxed = { "Maxed", "state.idle" },
}
-- chip:Set(kind[, text]) returns its width and height. kind is a key of Kit.CHIPS, or a state token with its own words.
function Kit.StatusChip(parent, kind, text)
  local f = CreateFrame("Frame", nil, parent)
  f.panoplyBox, f.panoplyKit, f.panoplyGapOK = true, "StatusChip", true
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  Skin.Round(fill, 9, Skin.TEX.RFill)
  f.fill = fill
  f.label = Skin.Text(f, 11, Skin.colors.text, nil, "semi")
  f.label:SetPoint("CENTER", f, "CENTER", 0, 0)
  if f.label.SetJustifyH then f.label:SetJustifyH("CENTER") end
  if f.label.SetWordWrap then f.label:SetWordWrap(false) end
  function f:Set(k, words)
    local def = Kit.CHIPS[k or ""]
    local token = def and def[2] or ((type(k) == "string" and Kit.TOKENS[k]) and k or "state.idle")
    local c = Kit.Color(token)
    self.kind, self.token = k, token
    self.text = words or (def and def[1]) or ""
    self.label:SetText(self.text)
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    tint(self.fill, c, 0.16)
    -- (0.9.5 phase 4E: the height is measured at the new width; measured first, a chip whose words grew read as wrapped)
    local tw = ceil(TW(self.label)) + 2
    self.label:SetWidth(tw)
    local th = ceil(TH(self.label, tw))
    self.label:SetHeight(th)
    local w, h = tw + 2 * Kit.Space(2), th + Kit.Space(1)
    self:SetSize(w, h)
    return w, h
  end
  f:Set(kind or "done", text)
  return f
end

-------------------------------------------------------------------------------
-- Coins: money drawn with the game's coin icons (spec 02 section 1, theme pass: "money shown with coin icons")
-------------------------------------------------------------------------------
-- Kit.Coins(copper, short): "1,204[g] 3[s] 5[c]" as inline textures; short = gold only (rounded down) once there is a gold.
-- Muster (Modules/Alts/Hall.lua H.Coins) and Field Kit (UI/Misc.lua Misc.Coins) keep their own copies from 4F/4I; the pop-outs of
-- the theme pass (phase 4J) use this one.
Kit.COIN = { g = "Interface\\MoneyFrame\\UI-GoldIcon", s = "Interface\\MoneyFrame\\UI-SilverIcon", c = "Interface\\MoneyFrame\\UI-CopperIcon" }
local function commas(n)
  local s = tostring(n)
  local k
  repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end
function Kit.Coins(copper, short)
  copper = floor(math.abs(tonumber(copper) or 0) + 0.5)
  local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  local out = {}
  local function add(v, k) out[#out + 1] = (k == "g" and commas(v) or tostring(v)) .. "|T" .. Kit.COIN[k] .. ":0:0:2:0|t" end
  if short and g > 0 then add(g, "g") return table.concat(out, " ") end
  if g > 0 then add(g, "g") end
  if s > 0 or (g > 0 and c > 0) then add(s, "s") end
  if c > 0 or #out == 0 then add(c, "c") end
  return table.concat(out, " ")
end

-------------------------------------------------------------------------------
-- More (⋯) and Ask: destructive actions live in a ⋯ menu and ask first (spec 02 section 1, theme pass)
-------------------------------------------------------------------------------
-- Kit.More(parent, items, tipBody, size): the ⋯ button (slot icon.ui.more, as Muster's). items: a list or a function giving one,
-- in Skin.Menu's form (a row's tip is the explanation under its name). Kit.Ask(owner, question, yes, fn, keep): the same menu, now a question: the question as its heading, a red
-- "yes" row that runs fn, and a "keep" row that does nothing. A destructive row of a ⋯ menu calls Kit.Ask instead of acting.
function Kit.More(parent, items, tipBody, size)
  local b = Skin.IconButton(parent, "", size or 22, function(self)
    local list = type(self.panoplyItems) == "function" and self.panoplyItems() or self.panoplyItems
    if list then Skin.Menu(self, list, { width = 230 }) end
  end, "More", tipBody)
  b:SetIcon("Settings", math.floor((size or 22) * 0.66))   -- (the size Muster's ⋯ draws it at)
  b.panoplyKitIcon, b.panoplyGapOK, b.panoplyItems = "icon.ui.more", true, items
  -- dimmed means the backing too, not only the glyph (an IconButton's backing is b.back)
  local look = b.SetEnabledLook
  function b:SetEnabledLook(on) look(self, on) if self.back then self.back:SetAlpha(on and 1 or 0.45) end end
  return b
end
function Kit.AskItems(question, yes, fn, keep)
  return {
    { header = question },
    { text = Skin.Code(Skin.colors.loss) .. (yes or "Yes") .. "|r", tip = "Do it now. This cannot be undone.", func = fn },
    { text = keep or "Keep them", tip = "Close this and change nothing." },
  }
end
function Kit.Ask(owner, question, yes, fn, keep)
  local items = Kit.AskItems(question, yes, fn, keep)
  Kit.lastAsk = items   -- (the tests answer the question through this)
  -- opened from a row of the ⋯ menu: that menu is still closing on this click, so the question opens on the next frame
  local T = _G.C_Timer
  local function open() Skin.Menu(owner, items, { width = 260 }) end
  if T and T.After then T.After(0, open) else open() end
  return items
end
