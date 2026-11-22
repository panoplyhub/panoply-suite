-- Panoply Suite skin. Skin v3 (SPEC 19.13, our approved "final v3" look): slate panels with a 1 px
-- brass trim and small brass corner caps, Spectral SC headings, Lato body text, a cerulean accent,
-- flat brass line icons (J set) for Panoply Suite's own controls, no glow, no sheen, no parchment.
-- Every colour, font and texture the add-on draws with lives here.
-- Art: our final-v3 pack converted by tools/make_skin3.py (Media/V3, Media/Icons/J, Media/Pins,
-- Media/Fonts) plus older own textures (tools/make_art.py). A few built-in client paths are probed
-- with a fallback (Skin.Builtin). No Blizzard art is copied.
local ADDON, Panoply = ...
local Skin = {}
Panoply.Skin = Skin
local C = Panoply.Compat

local function hex(h)
  return tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255
end
Skin.hex = hex
-- Skin v3 palette (final-v3 README). Older keys keep their names so every caller follows along.
Skin.colors = {
  bgDeep = { hex("#0b1017") }, bgMid = { hex("#151d27") }, bgHigh = { hex("#1e2834") },
  gold = { hex("#b8955a") }, goldBright = { hex("#d9bd82") }, goldDark = { hex("#8f703f") },
  heading = { hex("#e9cf93") }, text = { hex("#e6e4de") },
  button = { hex("#1e2834") }, buttonHover = { hex("#263241") }, buttonDown = { hex("#141b24") },
  accent = { hex("#5bbcd0") }, accentDark = { hex("#3a93a8") }, highlight = { hex("#dcb766") },
  -- "ink" colours are the text on content cards (they were dark ink on parchment before 0.5.0).
  ink = { hex("#e6e4de") }, inkSoft = { hex("#9aa5b2") }, inkTitle = { hex("#e9cf93") },
  arrowFar = { hex("#5bbcd0") }, arrowNear = { hex("#dcb766") }, arrowHere = { hex("#74c98f") },
  dim = { hex("#6f7a87") }, done = { hex("#74c98f") }, warn = { hex("#e8875f") },
  -- 0.7.4: a loss and "Vendor it" on the auction Sell tab (about 5.9:1 on the card colour; colour is never the only cue)
  loss = { hex("#ec6a5e") },
  danger = { hex("#4a2620") }, dangerHover = { hex("#5c2f27") },
  -- v3 surfaces
  panel = { hex("#151d27") }, trim = { hex("#b8955a") }, cap = { hex("#c9a86a") },
  card = { hex("#0e141c") }, hairline = { hex("#263140") }, slotLine = { hex("#384453") },
  slotTop = { hex("#2a3441") }, slotBottom = { hex("#1b222c") },
  progress = { hex("#dcb766") }, progressDark = { hex("#b38f4a") },
  tabFillIdle = { hex("#141b24") }, tabFillHover = { hex("#1a2330") }, tabFillSel = { hex("#1e2834") },
  -- J icons are white masks tinted here: brass, idle and active
  icon = { hex("#d6b878") }, iconIdle = { hex("#a8925f") }, iconActive = { hex("#e3c88a") },
  -- route trail (SPEC 21; 0.6.2: one bright colour per travel style over a dark outline, see
  -- UI/Trail.lua; trailRide stays brass for the card rule and the trip window). No glow.
  trailWalk = { hex("#4de4ff") }, trailRide = { hex("#b8955a") }, trailOff = { hex("#f5f5f5") },
  -- 0.6.2: one bright colour per travel style, always over the ink outline (UI/Trail.lua)
  trailFly = { hex("#ff9cef") }, trailShip = { hex("#fff04a") }, trailZeppelin = { hex("#ff9440") }, trailTram = { hex("#a8ff5c") },
  trailInk = { hex("#0a0d12") },
  -- the minimap gathering ring, clear centre (0.6.2: a white band between dark edges, was thin brass)
  gatherRing = { hex("#f4f4f4") },
  -- 0.6.0: quest icon tooltips (labels in brass, "can do / done" in the done green, the rest soft)
  qpTipLabel = { hex("#e9cf93") }, qpTipText = { hex("#e6e4de") }, qpTipDim = { hex("#9aa5b2") },
  qpTipReady = { hex("#74c98f") }, qpTipDone = { hex("#8fb89a") },
  -- 0.9.5 (docs/specs/page-redesigns-v1.md 1.1): the shared visual system's surfaces and section accents (UI/KitParts.lua names them
  -- by token: surface.1, accent.professions, ...). surface1 is one step lighter than the window, for anything that reads as a card
  -- (no border); surface2 is a hovered or selected row. One accent per section: bronze, moss green, steel blue.
  surface1 = { hex("#1e2834") }, surface2 = { hex("#263241") },
  accentBronze = { hex("#c08a4e") }, accentMoss = { hex("#7fa65a") }, accentSteel = { hex("#6f9fc8") },
}
-- {r,g,b} for a skin colour, read when used so a re-skin applies to the next tooltip
function Skin.RGB(name)
  local c = Skin.colors[name] or Skin.colors.text
  return { c[1], c[2], c[3] }
end
-- Alphas that belong with the colours above.
Skin.ALPHA = { panel = 0.97, card = 0.70, rowHighlight = 0.10 }

-- Fonts (SPEC 19.13.3). Shipped in Media/Fonts under the SIL Open Font License (see NOTICE.md).
-- Spectral SC SemiBold: headings (numbers inside a heading are set in Lato SemiBold).
-- Lato Medium: body. Lato SemiBold: tabs, names, values, quest titles. Lato Bold: small labels.
Skin.MEDIA = "Interface\\AddOns\\PanoplySuite\\Media\\"
Skin.FONTS = {
  head = Skin.MEDIA .. "Fonts\\SpectralSC-SemiBold.ttf",
  body = Skin.MEDIA .. "Fonts\\Lato-Medium.ttf",
  semi = Skin.MEDIA .. "Fonts\\Lato-SemiBold.ttf",
  label = Skin.MEDIA .. "Fonts\\Lato-Bold.ttf",
}
-- the client's own fonts, used only if one of ours fails to load
Skin.GAME_FONTS = { head = "Fonts\\FRIZQT__.TTF", body = "Fonts\\ARIALN.TTF" }
Skin.FONT = Skin.FONTS.head           -- headings (kept name)
Skin.BODY = Skin.FONTS.body           -- body text (kept name)
Skin.NUMBER_SCALE = 0.92              -- Lato numbers inside a Spectral SC heading
Skin.WHITE = "Interface\\Buttons\\WHITE8X8"
Skin.PAD = 12                            -- padding grid unit
-- 0.5.5: one spacing scale for every layout (xs 4, s 6, m 10, l 14, xl 20)
Skin.SP = { xs = 4, s = 6, m = 10, l = 14, xl = 20 }
Skin.colors.tabIdle = { hex("#9aa5b2") }
Skin.colors.tabHover = { hex("#e6e4de") }
Skin.colors.tabSel = { hex("#e9cf93") }
Skin.TEX = {}
-- v3: no Glow, Sheen, ButtonGlow, Parchment, HeaderBar or SlotGlow any more (SPEC 19.13.6).
-- Nov 2026: the logo is the Panoply shield (Shield 128 px, ShieldMinimap 64 px; tools/make_shield.py). The old crest's two
-- files stay in the Media folder but nothing names them any more (tests/shield_tests.lua checks that).
for _, n in ipairs({ "Divider", "Shield", "ShieldMinimap", "Check", "Arrow", "BadgeQuest", "BadgeJunk", "ResizeGrip" }) do
  Skin.TEX[n] = Skin.MEDIA .. n
end
-- v3 frames from our pack: white fill and trim masks per panel size, brass corner caps, the
-- slate icon-button backing.
for _, n in ipairs({ "PanelLFill", "PanelLLine", "PanelMFill", "PanelMLine", "PanelSFill", "PanelSLine", "IconButton",
                     "CapLTL", "CapLTR", "CapLBL", "CapLBR", "CapMTL", "CapMTR", "CapMBL", "CapMBR",
                     "CapSTL", "CapSTR", "CapSBL", "CapSBR" }) do
  Skin.TEX[n] = Skin.MEDIA .. "V3\\" .. n
end
-- 0.6.0 arrow fix: the navigation arrow is two own drawings (tools/make_arrow.py, 256 px, anti-aliased, colour
-- bled into the clear texels): Arrow (white body, tinted per state) and ArrowTrim (brass trim and a
-- faint soft contact shadow, never tinted). No glow.
Skin.TEX.ArrowTrim = Skin.MEDIA .. "ArrowTrim"
-- One arrow: the body texture (callers tint and rotate it as before) with its trim riding along:
-- Show / Hide / SetRotation on the body move the trim too (Arrow.SetRotation rotates both).
function Skin.NavArrow(parent, layer, size)
  local body = parent:CreateTexture(nil, layer or "ARTWORK", nil, 1)
  body:SetTexture(Skin.TEX.Arrow)
  body:SetSize(size, size)
  local trim = parent:CreateTexture(nil, layer or "ARTWORK", nil, 2)
  trim:SetTexture(Skin.TEX.ArrowTrim)
  trim:SetAllPoints(body)
  trim.panoplyPieceOf = body
  body.trim = trim
  local show, hide = body.Show, body.Hide
  body.Show = function(self) show(self) trim:Show() end
  body.Hide = function(self) hide(self) trim:Hide() end
  return body
end
Skin.TEX.TrailDot = Skin.TEX.CircleMask   -- the trail's dot: a plain round disc, no halo
-- 0.6.0: the hollow gathering ring on the minimap (our own 64 px drawing, white, tinted brass;
-- the centre is fully clear so the game's gold tracking dot shows through)
Skin.TEX.GatherRing = Skin.MEDIA .. "GatherRing"
Skin.GATHER_RING_HOLE = 53 / 64   -- clear diameter as a share of the drawn size
-- the seven approved map pins
Skin.PINS = { "Flight", "Giver", "Node", "Objective", "Trail", "Trainer", "Turnin" }
for _, n in ipairs(Skin.PINS) do Skin.TEX["Pin" .. n] = Skin.MEDIA .. "Pins\\" .. n end
-- Icon set: tile (64 px), large tile (128 px) and bare glyph (64 px).
-- 0.5.4: keys with no drawing of their own in the Panoply Suite set borrow a close one
Skin.ICON_ALIAS = { Auctions = "Coin", Help = "Train", Tour = "Map",
  -- 0.9.5 phase 4K: the step types, trip legs and Guide toggles with no drawing of their own in the set borrow the closest one
  Use = "Settings", Group = "Partner", Walk = "Travel", Boat = "Travel", Zeppelin = "Fly", Tram = "Travel", Trail = "Travel", Tracker = "Leveling" }
function Skin.ICON(name, large) name = Skin.ICON_ALIAS[name or ""] or name return Skin.MEDIA .. "Icons\\" .. (large and "Large\\" or "") .. (name or "Modules") end
function Skin.GLYPH(name) return Skin.MEDIA .. "Icons\\Glyph\\" .. (name or "Modules") end
Skin.STEP_ICON = {
  accept = "Accept", turnin = "TurnIn", kill = "Kill", collect = "Collect", loot = "Collect", travel = "Travel",
  go = "Travel", fly = "Fly", taxi = "Fly", hearth = "Hearth", train = "Train", learn = "Train", craft = "Craft",
  gather = "Gather", profgather = "Gather", proffish = "NodeFish", vendor = "Vendor", buy = "Vendor", sell = "Vendor",
  repair = "Repair", bank = "Bank", use = "Collect", explore = "Map",
}
function Skin.StepIcon(stepType) return Skin.ICON(Skin.STEP_ICON[stepType or ""] or "Travel") end

-- Built-in client textures used for extra polish, always with a fallback.
Skin.BUILTIN = {
  dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  minimapBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
  minimapHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
  rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  readyIcon = "Interface\\RaidFrame\\ReadyCheck-Ready",
  waitIcon = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  -- Step 2 D: the game's own quest icons, for "Blizzard default" in the Map page's Look of the map (Modules/QuestPins). Drawn only when the
  -- game says the file exists (Skin.BuiltinProven below): where it cannot say, or says no, Panoply Suite's own pin is drawn instead. The first
  -- two are the paths GAME_ICONS has used since 0.5.x, the third is their sibling in the same folder. There is no path here for the objective
  -- marker: nothing in the game is known to fit, so Objectives have no "Blizzard default" until a real one is confirmed in the game.
  questGiver = "Interface\\GossipFrame\\AvailableQuestIcon",
  questTurnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  questIncomplete = "Interface\\GossipFrame\\IncompleteQuestIcon",
}
Skin.builtinMissing = {}
function Skin.Builtin(key)
  local path = Skin.BUILTIN[key]
  if not path then return nil end
  if C.FileExists(path) == false then Skin.builtinMissing[key] = true return nil end
  return path
end
-- Step 2 D: like Builtin, but the path comes back ONLY when the game has said the file exists. A client that cannot say (no GetFileIDFromPath)
-- or says it is not there gets nil, so an unproven texture is never drawn (it would be an invisible pin). The answer is kept: a file does
-- not come and go in a session, so it is asked once, not on every redraw (Skin.ForgetProofs starts again: the tests).
Skin.proven = {}
function Skin.BuiltinProven(key)
  local c = Skin.proven[key]
  if c ~= nil then return c or nil end
  local path = Skin.BUILTIN[key]
  local ok = path ~= nil and C.FileExists(path) == true
  Skin.proven[key] = ok and path or false
  return ok and path or nil
end
function Skin.ForgetProofs() Skin.proven = {} end

Skin.buttons = {}

-------------------------------------------------------------------------------
-- 0.5.3 rounded look. Skin.Round turns an anchored texture into a nine-slice of one of the
-- rounded atlases (Media/*R.tga, 64x64 with the whole corner curve in the outer 16px), so a
-- corner keeps its real radius however the box is stretched. The original texture stays as the
-- invisible anchor and forwards SetTexture / colour / alpha / show-hide to its nine pieces, so
-- callers keep using it like a texture. Straight edges are plain stretched texels: crisp.
-------------------------------------------------------------------------------
for _, n in ipairs({ "RFill", "RLine8",
                     "RoundMask", "RoundMaskSmall", "CircleMask", "SlotRing2", "SlotRing3" }) do
  Skin.TEX[n] = Skin.MEDIA .. n
end
-- v3 radii: large windows 12, cards 8, controls 6 (rows and pills are drawn with RFill).
Skin.RADIUS = { window = 12, card = 8, button = 6, tab = 6, input = 6, toast = 12, row = 6 }
-- The three v3 frame atlases (our panel-large/mid/small): fill + trim masks and the corner size
-- in UI px of each nine-slice corner piece (a quarter of the texture's UI size).
Skin.BOX = {
  L = { fill = Skin.TEX.PanelLFill, line = Skin.TEX.PanelLLine, corner = 16, radius = 12 },
  M = { fill = Skin.TEX.PanelMFill, line = Skin.TEX.PanelMLine, corner = 8, radius = 8 },
  S = { fill = Skin.TEX.PanelSFill, line = Skin.TEX.PanelSLine, corner = 8, radius = 6 },
}
-- Corner caps (SPEC 19.13.2): texture size in UI px, and the visible bracket measured from our
-- art: each arm runs `arm` px along the edge from the corner and reaches `depth` px inside it.
-- The texture's top-left sits 2 UI px outside the panel corner (final-v3 README).
Skin.CAP = {
  L = { size = 64, arm = 37, depth = 3, minSide = 110 },
  M = { size = 32, arm = 22, depth = 3, minSide = 64 },
  S = { size = 16, arm = 13, depth = 2, minSide = 32 },   -- below 32 px: no caps at all
}
Skin.CAP_OUT = 2
local SLICE_C = 0.25
local COORDS = {
  { 0, SLICE_C, 0, SLICE_C }, { SLICE_C, 1 - SLICE_C, 0, SLICE_C }, { 1 - SLICE_C, 1, 0, SLICE_C },
  { 0, SLICE_C, SLICE_C, 1 - SLICE_C }, { SLICE_C, 1 - SLICE_C, SLICE_C, 1 - SLICE_C }, { 1 - SLICE_C, 1, SLICE_C, 1 - SLICE_C },
  { 0, SLICE_C, 1 - SLICE_C, 1 }, { SLICE_C, 1 - SLICE_C, 1 - SLICE_C, 1 }, { 1 - SLICE_C, 1, 1 - SLICE_C, 1 },
}
function Skin.Round(t, corner, atlas)
  if not t or t.panoplyPieces then if t and atlas then t:SetTexture(atlas) end return t end
  local parent = t.GetParent and t:GetParent()
  if not parent or not parent.CreateTexture then return t end
  local layer, sub = "ARTWORK", 0
  if t.GetDrawLayer then local l, s2 = t:GetDrawLayer() layer, sub = l or layer, s2 or 0 end
  local mt = getmetatable(t)
  local idx = mt and mt.__index
  local function method(name) return (type(idx) == "table" and idx[name]) or (type(idx) == "function" and idx(t, name)) or t[name] end
  local P = {}
  for i = 1, 9 do
    local x = parent:CreateTexture(nil, layer, nil, sub)
    if x.SetTexCoord then x:SetTexCoord(COORDS[i][1], COORDS[i][2], COORDS[i][3], COORDS[i][4]) end
    P[i] = x
  end
  t.panoplyPieces, t.panoplyCorner = P, corner or 8
  local M = {}
  for _, n in ipairs({ "SetTexture", "SetVertexColor", "SetAlpha", "SetDesaturated", "Show", "Hide", "SetBlendMode" }) do M[n] = method(n) end
  t.panoplyBase = M
  M.SetTexture(t, nil)
  local function layout(self)
    local c = self.panoplyCorner
    local w, h = self.GetWidth and self:GetWidth() or 0, self.GetHeight and self:GetHeight() or 0
    if w and w > 0 then c = math.min(c, w / 2) end
    if h and h > 0 then c = math.min(c, h / 2) end
    local p = self.panoplyPieces
    for _, x in ipairs(p) do x:ClearAllPoints() end
    p[1]:SetSize(c, c); p[1]:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    p[3]:SetSize(c, c); p[3]:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    p[7]:SetSize(c, c); p[7]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
    p[9]:SetSize(c, c); p[9]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT"); p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
    p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT"); p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
  end
  t.panoplyLayout = layout
  function t:SetCorner(c) self.panoplyCorner = c layout(self) end
  t.SetTexture = function(self, path) self.panoplyAtlas = path for _, x in ipairs(self.panoplyPieces) do x:SetTexture(path) end end
  t.SetVertexColor = function(self, ...) self.color = { ... } for _, x in ipairs(self.panoplyPieces) do x:SetVertexColor(...) end end
  t.SetAlpha = function(self, a) M.SetAlpha(self, a) for _, x in ipairs(self.panoplyPieces) do x:SetAlpha(a) end end
  t.SetDesaturated = function(self, d) for _, x in ipairs(self.panoplyPieces) do if x.SetDesaturated then x:SetDesaturated(d) end end end
  t.SetBlendMode = function(self, m) for _, x in ipairs(self.panoplyPieces) do if x.SetBlendMode then x:SetBlendMode(m) end end end
  t.Show = function(self) M.Show(self) for _, x in ipairs(self.panoplyPieces) do x:Show() end end
  t.Hide = function(self) M.Hide(self) for _, x in ipairs(self.panoplyPieces) do x:Hide() end end
  t.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
  -- gradients: the atlases carry their own shading, so a gradient call becomes a plain tint
  t.SetGradient = function(self) end
  t.SetGradientAlpha = function(self) end
  layout(t)
  if atlas then t:SetTexture(atlas) end
  if t.IsShown and not t:IsShown() then for _, x in ipairs(P) do x:Hide() end end
  return t
end
-- A rounded box: fill + optional hairline ring, anchored to region f with an inset.
function Skin.RoundBox(f, corner, fill, fillColor, fillAlpha, line, lineColor, lineAlpha, layer, inset)
  inset = inset or 0
  local function make(atlas, col, a, lay)
    local t = f:CreateTexture(nil, lay)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    Skin.Round(t, corner, atlas)
    if col then t:SetVertexColor(col[1], col[2], col[3], a or 1) elseif a then t:SetAlpha(a) end
    return t
  end
  local bg = fill and make(fill, fillColor, fillAlpha, layer or "BACKGROUND")
  local rim = line and make(line, lineColor, lineAlpha, "BORDER")
  return bg, rim
end

-- MaskTexture support (Classic Era 1.15 and Forever both have it; feature-detected anyway).
function Skin.CanMask(parent, tex)
  return parent and parent.CreateMaskTexture ~= nil and tex and tex.AddMaskTexture ~= nil
end
-- Rounded (or round) mask on a texture; returns true when a real mask was applied. Without masks
-- the icon stays square but cropped, which is the graceful fallback.
function Skin.Mask(tex, file, parent)
  parent = parent or (tex.GetParent and tex:GetParent())
  if not Skin.CanMask(parent, tex) then tex.panoplyMaskFallback = true return false end
  local m = tex.panoplyMask
  if not m then
    local ok, mm = pcall(parent.CreateMaskTexture, parent)
    if not ok or not mm then tex.panoplyMaskFallback = true return false end
    m = mm
    m:SetAllPoints(tex)
    pcall(tex.AddMaskTexture, tex, m)
    tex.panoplyMask = m
  end
  if not pcall(m.SetTexture, m, file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then m:SetTexture(file) end
  tex.panoplyMaskFile = file
  return true
end

-------------------------------------------------------------------------------
-- 0.5.3 icons: the game's own icon textures, chosen at runtime by path with an existence check
-- per client (first candidate that exists wins), cropped 0.07-0.93 and rounded with a mask.
-- Our own icon tiles are only the fallback when none of the candidates exist.
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
Skin.GAME_ICONS = {
  Leveling = { I .. "INV_Scroll_03", I .. "INV_Misc_Note_01" },
  Professions = { I .. "Trade_BlackSmithing" },
  Partner = { I .. "INV_ValentinesCard01", I .. "Spell_Holy_PrayerOfHealing02", I .. "Spell_Holy_Heal" },
  Modules = { I .. "INV_Gizmo_02", I .. "INV_Misc_Gear_01" },
  Settings = { I .. "Trade_Engineering", I .. "INV_Misc_Gear_01" },
  GuideWindow = { I .. "INV_Misc_Book_09", I .. "INV_Misc_Book_01" },
  Bags = { I .. "INV_Misc_Bag_08" },
  Bank = { I .. "INV_Box_02" },
  Vendor = { I .. "INV_Misc_Coin_01" },
  Glow = { I .. "INV_Misc_Gem_Sapphire_02", I .. "INV_Misc_Gem_Emerald_02", I .. "INV_Misc_Gem_01" },
  Gathering = { I .. "Trade_Herbalism", I .. "INV_Misc_Flower_02" },
  ProfWindow = { I .. "INV_Misc_Book_11", I .. "INV_Misc_Book_09" },
  Waypoints = { I .. "INV_Misc_Spyglass_02", I .. "INV_Misc_Map_01" },
  Auctions = { I .. "INV_Misc_Coin_02", I .. "INV_Misc_Coin_01" },
  Accept = { "Interface\\GossipFrame\\AvailableQuestIcon", raw = true },  -- the yellow !
  TurnIn = { "Interface\\GossipFrame\\ActiveQuestIcon", raw = true },     -- the yellow ?
  Kill = { I .. "INV_Sword_04", I .. "Ability_Warrior_SavageBlow" },
  Collect = { I .. "INV_Misc_Bag_07" },
  Travel = { I .. "Ability_Rogue_Sprint", I .. "INV_Misc_Map_02" },
  Fly = { I .. "Ability_Mount_Gryphon_01", I .. "Ability_Mount_Wyvern_01", I .. "INV_Misc_Map_02" },
  Hearth = { I .. "INV_Misc_Rune_01" },
  Train = { I .. "INV_Misc_Book_07" },
  Craft = { I .. "Trade_Tailoring", I .. "Trade_BlackSmithing" },
  Gather = { I .. "Trade_Mining" },
  NodeHerb = { I .. "INV_Misc_Flower_02" },
  NodeOre = { I .. "INV_Ore_Copper_01" },
  NodeFish = { I .. "INV_Misc_Fish_02", I .. "Trade_Fishing" },
  NodeChest = { I .. "INV_Box_01" },
  Repair = { I .. "Ability_Repair", I .. "Trade_BlackSmithing" },
  Map = { I .. "INV_Misc_Map_01" },
  Character = { I .. "INV_Misc_Head_Human_01" },
  Coin = { I .. "INV_Misc_Coin_01" },
  Star = { I .. "INV_Misc_Gem_Pearl_04", I .. "Spell_Holy_Surgeoflight" },
  Help = { I .. "INV_Misc_QuestionMark", I .. "INV_Misc_Book_07" },        -- 0.5.6 Help tab
  Tour = { I .. "INV_Misc_Map_02", I .. "INV_Misc_Spyglass_02" },          -- 0.5.6 the tour
  -- 0.9.5 phase 4K (spec 05 section 4.4 and 7, spec 06a section 4): the step types without an icon above, the trip legs and the Guide
  -- page's On your screen toggles. The game's own files, first one the game has; the last of each list is one every client has.
  Use = { I .. "INV_Misc_Gear_01", I .. "Trade_Engineering" },                          -- a cog: use an item, interact
  Group = { I .. "Spell_Holy_PrayerOfHealing02", I .. "INV_Misc_Head_Human_01" },      -- a group: dungeon or group step
  Walk = { I .. "Ability_Tracking", I .. "Ability_Rogue_Sprint" },                     -- footprints
  Boat = { I .. "INV_Misc_Anchor", I .. "Spell_Frost_SummonWaterElemental", I .. "INV_Misc_Map_02" },
  Zeppelin = { I .. "INV_Gizmo_RocketBoot_01", I .. "Ability_Mount_Wyvern_01", I .. "INV_Misc_Map_02" },
  Tram = { I .. "INV_Gizmo_02", I .. "INV_Misc_Map_02" },
  Trail = { I .. "Ability_Tracking", I .. "Ability_Rogue_Sprint" },                    -- footprints: the trail on the maps
  Tracker = { I .. "INV_Misc_Note_01", I .. "INV_Scroll_03" },                         -- a list: the quest tracker
}
-- 0.5.4: icons for Panoply Suite's own buttons and controls (game UI textures first; raw = no crop).
local B = "Interface\\Buttons\\"
Skin.GAME_GLYPHS = {
  Close = { B .. "UI-StopButton", raw = true },
  Plus = { B .. "UI-PlusButton-Up", raw = true },
  Minus = { B .. "UI-MinusButton-Up", raw = true },
  Search = { "Interface\\Common\\UI-Searchbox-Icon", raw = true },
  Sort = { { atlas = "bags-button-autosort-up" }, I .. "INV_Pet_Broom" },
  Bags = { B .. "Button-Backpack-Up", I .. "INV_Misc_Bag_08" },
  Bank = { I .. "INV_Misc_Bag_10_Blue", I .. "INV_Misc_Bag_10", I .. "INV_Box_02" },
  Arrow = { I .. "Ability_Hunter_Pathfinding", I .. "INV_Misc_Map_01" },
  Route = { I .. "INV_Misc_Map_02", I .. "INV_Misc_Map_01" },   -- 0.9.5 phase 4K: the Guide page's Replan now (a route drawn on a map)
  Lock = { B .. "LockButton-Locked-Up", raw = true },
  Unlock = { B .. "LockButton-Unlocked-Up", raw = true },
  Eye = { I .. "INV_Misc_Eye_01", I .. "Spell_Shadow_DetectInvisibility", I .. "Ability_EyeOfTheOwl" },
  Star = { { atlas = "auctionhouse-icon-favorite" }, "Interface\\Common\\FavoritesIcon" },
  StarEmpty = { { atlas = "auctionhouse-icon-favorite-off" }, { atlas = "auctionhouse-icon-favorite", desat = true }, "Interface\\Common\\FavoritesIcon", desat = true },
  Check = { B .. "UI-CheckBox-Check", raw = true },
  Ready = { "Interface\\RaidFrame\\ReadyCheck-Ready", raw = true },
  Waiting = { "Interface\\RaidFrame\\ReadyCheck-Waiting", raw = true },
  -- 0.7.1 tracker "party has this quest" mark: the game's own group / party art (first that
  -- exists in this client), flat, never a glow or highlight texture.
  Party = { { atlas = "socialqueuing-icon-group" }, { atlas = "groupfinder-icon-friend" },
            "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", raw = true },
}
-- The game's own bag-slot quest marks (what the default bag UI shows) and a junk coin.
Skin.GAME_MARKS = {
  QuestBang = { "Interface\\ContainerFrame\\UI-Icon-QuestBang", raw = true },     -- item starts a quest
  QuestBorder = { "Interface\\ContainerFrame\\UI-Icon-QuestBorder", raw = true }, -- quest item
  Junk = { { atlas = "bags-junkcoin" }, B .. "UI-GroupLoot-Coin-Up", raw = true },
}
Skin.UNKNOWN_ITEM = 134400   -- the game's question-mark icon (INV_Misc_QuestionMark)

-- v3 J icons: our flat brass line icons, shipped white (Media/Icons/J, 64 px, and J/Small, his
-- 32 px drawing) and tinted brass here. ONLY for Panoply Suite's own UI glyphs: tabs, the title-bar
-- settings and close buttons, route and map buttons, panel headers (SPEC 19.13.4). Item, ability,
-- quest and bag pictures are never J icons (SPEC 19.10).
Skin.J_ICONS = { Leveling = "Leveling", Professions = "Professions", Partner = "Partner", Modules = "Modules",
                 Settings = "Settings", Help = "Help", Map = "Map", Route = "Route", Tour = "Map" }
Skin.J_GLYPHS = { Close = "Close", Settings = "Gear", Gear = "Gear", Lock = "Lock", Unlock = "Lock", Map = "Map",
                  Route = "Route", Arrow = "Route", Sort = "Sort", ChatSettings = "ChatSettings" }
Skin.J_DIM = { Unlock = true }          -- the unlocked padlock is the same drawing, dimmed
-- 0.9.4: the main menu's pages, one line icon each, the same in both icon styles (SetIcon with opts.own). key = the page's `icon`
-- in UI/Catalog.lua (or Misc.lua) -> the file in Media/Icons/J. The first six are our drawings; the rest are drawn by
-- tools/make_menu_icons.py (our own, same stroke, size, colour and alignment). tests/menuicons_tests.lua checks every page has one.
Skin.J_MENU = { Leveling = "Leveling", Map = "Map", Partner = "Partner", Professions = "Professions", Modules = "Modules", Help = "Help",
                MenuHome = "Home", MenuTalents = "Talents", MenuClass = "ClassGuide", MenuAtLevel = "AtLevel", MenuAuctions = "Auctions",
                MenuFrames = "Frames", MenuTogether = "Together", MenuLegacy = "Legacy", MenuMisc = "Misc", MenuMuster = "Muster" }
function Skin.JIcon(name, size)
  -- our 32 px drawing up to 24 UI px (most controls), the 64 px one above that
  return Skin.MEDIA .. "Icons\\J\\" .. ((not size or size <= 24) and "Small\\" or "") .. name
end

-- Icon style: "panoply" (v3 default: J icons on Panoply Suite's own controls, the game's icons
-- everywhere else) or "wow" (the game's own textures for everything). Before 0.9.5 the first was saved as "hearthpath";
-- anything but "wow" reads as "panoply", and Skin.PanoplyValues rewrites the old word once at login.
function Skin.Style()
  return (Panoply.db and Panoply.db.iconStyle == "wow") and "wow" or "panoply"
end
function Skin.WoW() return Skin.Style() == "wow" end

local function atlasExists(name)
  local CT = _G.C_Texture
  if not (CT and CT.GetAtlasInfo) then return false end
  local ok, info = pcall(CT.GetAtlasInfo, name)
  return ok and info ~= nil and info ~= false
end
-- First candidate in a list that exists in this client: returns { path | atlas, raw, desat } or nil.
Skin.iconCache = {}
local function resolve(tbl, key)
  local ck = tostring(tbl) .. ":" .. key
  local c = Skin.iconCache[ck]
  if c ~= nil then return c or nil end
  local list = tbl[key]
  local found = false
  for _, p in ipairs(list or {}) do
    if type(p) == "table" and p.atlas then
      if atlasExists(p.atlas) then found = { atlas = p.atlas, raw = true, desat = p.desat or list.desat } break end
    elseif type(p) == "string" and C.FileExists(p) ~= false then
      found = { path = p, raw = list.raw, desat = list.desat } break
    end
  end
  Skin.iconCache[ck] = found
  return found or nil
end
Skin.Resolve = resolve
function Skin.GameIcon(key)
  local r = resolve(Skin.GAME_ICONS, key)
  if not r then return nil end
  return r.path or r.atlas, r.raw, r.atlas and true or nil
end

-- Live switching: every icon texture we set is remembered (weakly) with how it was set, so a
-- change of icon style re-applies it in place.
Skin.live = setmetatable({}, { __mode = "k" })
Skin.styleListeners = {}
function Skin.OnStyle(fn) Skin.styleListeners[#Skin.styleListeners + 1] = fn end
function Skin.RefreshIcons()
  Skin.iconCache = {}
  local n = 0
  for tex, r in pairs(Skin.live) do
    local ok = pcall(r[1], tex, r[2], r[3], true)
    if ok then n = n + 1 end
  end
  for _, fn in ipairs(Skin.styleListeners) do pcall(fn, Skin.Style()) end
  Panoply:Fire("ICON_STYLE_CHANGED", Skin.Style())
  return n
end

local function unmask(tex)
  if tex.panoplyMask and tex.RemoveMaskTexture and tex.panoplyMaskOn then pcall(tex.RemoveMaskTexture, tex, tex.panoplyMask) end
  tex.panoplyMaskOn = false
end
local function remask(tex, file, parent)
  if tex.panoplyMask and not tex.panoplyMaskOn and tex.AddMaskTexture then pcall(tex.AddMaskTexture, tex, tex.panoplyMask) end
  if Skin.Mask(tex, file, parent) then tex.panoplyMaskOn = true end
end
-- Apply a resolved game texture to tex.
local function applyGame(tex, r, opts, mask)
  if r.atlas and tex.SetAtlas then
    tex:SetAtlas(r.atlas)
  else
    tex:SetTexture(r.path or r.atlas)
  end
  if tex.SetDesaturated then tex:SetDesaturated(r.desat and true or false) end
  if r.raw or r.atlas then
    if not r.atlas and tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    unmask(tex)
  else
    if tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    if mask ~= false then
      remask(tex, opts.circle and Skin.TEX.CircleMask or (opts.small and Skin.TEX.RoundMaskSmall or Skin.TEX.RoundMask), opts.parent)
    end
  end
end
local function applyOwn(tex, file)
  tex:SetTexture(file)
  if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
  if tex.SetDesaturated then tex:SetDesaturated(false) end
  unmask(tex)
  if tex.panoplyJ then tex.panoplyJ = nil if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end end
end
-- A J icon: white drawing, tinted brass (or the tint the control asked for).
local function applyJ(tex, name, opts, dim)
  local w = tex.GetWidth and tex:GetWidth() or 0
  tex:SetTexture(Skin.JIcon(name, opts.size or (w > 0 and w or nil)))
  if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
  if tex.SetDesaturated then tex:SetDesaturated(false) end
  unmask(tex)
  local c = opts.tint or tex.panoplyTint or Skin.colors.icon
  tex.panoplyJ = name
  if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], dim and 0.55 or 1) end
end
-- Re-tint a J icon (tabs: idle / active); a game icon keeps its own colours.
function Skin.TintIcon(tex, c)
  if not tex then return end
  tex.panoplyTint = c
  if tex.panoplyJ and tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3], 1) end
end

local function resetJ(tex)
  if tex.panoplyJ then tex.panoplyJ = nil if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end end
end
-- Put the icon for `key` on texture tex. Panoply Suite style: a J icon when `key` is one of
-- Panoply Suite's own UI glyphs (Skin.J_ICONS); otherwise, and always in WoW style, the game's own
-- icon (rounded). Our older icon tiles are only the fallback when no game candidate exists.
-- opts.item: an item / ability / quest picture, never a J icon (also enforced by tests).
function Skin.SetIcon(tex, key, opts)
  if not tex then return end
  if key == "Logo" then return Skin.Logo(tex, opts) end   -- the tour's minimap step names the logo as an icon: the shield
  opts = opts or {}
  Skin.live[tex] = { Skin.SetIcon, key, opts }
  -- 0.9.4 (review K9): no key means no icon (a menu page without one must not break its header): the texture is emptied
  if key == nil then
    applyOwn(tex, nil)
    tex.panoplyGameIcon, tex.panoplyIconKey, tex.panoplyStyle = nil, nil, Skin.Style()
    return tex
  end
  -- 0.9.4: opts.own = a page of the main menu (its list row and its header): Panoply Suite's own line icon in BOTH icon styles
  local j = not opts.item and ((opts.own and Skin.J_MENU[key or ""]) or (not Skin.WoW() and Skin.J_ICONS[key or ""]))
  local r = not j and resolve(Skin.GAME_ICONS, key)
  if j then
    applyJ(tex, j, opts)
    tex.panoplyGameIcon, tex.panoplyIconKey = nil, key
  elseif r then
    resetJ(tex)
    applyGame(tex, r, opts)
    tex.panoplyGameIcon, tex.panoplyIconKey = r.path or r.atlas, key
  else
    applyOwn(tex, Skin.ICON(key, opts.large))
    tex.panoplyGameIcon, tex.panoplyIconKey = nil, key
  end
  tex.panoplyStyle = Skin.Style()
  return tex
end
-- A small control glyph (close, gear, sort, lock, plus, minus, search, star...): a J icon in
-- Panoply Suite style when there is one, else the game's UI texture.
function Skin.SetGlyph(tex, name, opts)
  if not tex then return end
  opts = opts or {}
  Skin.live[tex] = { Skin.SetGlyph, name, opts }
  local j = not Skin.WoW() and Skin.J_GLYPHS[name or ""]
  local r = not j and (resolve(Skin.GAME_GLYPHS, name) or resolve(Skin.GAME_ICONS, name))
  if j then
    applyJ(tex, j, opts, Skin.J_DIM[name])
    tex.panoplyGameIcon, tex.panoplyIconKey = nil, name
  elseif r then
    resetJ(tex)
    applyGame(tex, r, opts, false)
    tex.panoplyGameIcon, tex.panoplyIconKey = r.path or r.atlas, name
  else
    applyOwn(tex, Skin.GLYPH(name))
    tex.panoplyGameIcon, tex.panoplyIconKey = nil, name
  end
  tex.panoplyStyle = Skin.Style()
  return tex
end
-- Check / waiting marks: the game's ready-check marks in both styles (v3 has no own marks; our
-- Check.tga is the fallback only).
function Skin.SetMark(tex, name)
  if not tex then return end
  Skin.live[tex] = { Skin.SetMark, name }
  local r = resolve(Skin.GAME_GLYPHS, name)
  if r then applyGame(tex, r, {}, false) tex.panoplyGameIcon = r.path or r.atlas
  else applyOwn(tex, Skin.TEX.Check) tex.panoplyGameIcon = nil end
  tex.panoplyIconKey, tex.panoplyStyle = name, Skin.Style()
  return tex
end
-- A map pin (SPEC 19.13.5): one of our seven pins in Panoply Suite style, the game's icon for
-- `gameKey` in WoW style.
function Skin.SetPin(tex, pin, gameKey)
  if not tex then return end
  Skin.live[tex] = { Skin.SetPin, pin, gameKey }
  if not Skin.WoW() and Skin.TEX["Pin" .. (pin or "")] then
    applyOwn(tex, Skin.TEX["Pin" .. pin])
    tex.panoplyGameIcon, tex.panoplyIconKey, tex.panoplyPin = nil, gameKey, pin
  else
    Skin.SetIcon(tex, gameKey, { circle = true })
    Skin.live[tex] = { Skin.SetPin, pin, gameKey }
    tex.panoplyPin = nil
  end
  tex.panoplyStyle = Skin.Style()
  return tex
end
-- The Panoply Suite logo: the Panoply shield (Shield, 128 px), in both icon styles. The old "Show the crest" choice and the
-- Hearthstone-icon logo are gone; that choice's saved value is still read (Core/Init.lua) and kept as it is, and means nothing.
function Skin.Logo(tex, opts)
  Skin.live[tex] = { Skin.Logo, opts }
  applyOwn(tex, Skin.TEX.Shield)
  tex.panoplyGameIcon, tex.panoplyIconKey, tex.panoplyStyle = nil, "Logo", Skin.Style()
  return tex
end

local function solid(tex, c, a)
  tex:SetTexture(Skin.WHITE)
  tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end
Skin.Solid = solid

-------------------------------------------------------------------------------
-- Tweens: one shared driver, shown only while something is animating (no idle OnUpdate).
-------------------------------------------------------------------------------
Skin.tweens = {}
local driver
local function ensureDriver()
  if driver then return driver end
  driver = CreateFrame("Frame")
  driver:Hide()
  driver:SetScript("OnUpdate", function(self, dt)
    local any = false
    for obj, tw in pairs(Skin.tweens) do
      tw.t = tw.t + (dt or 0.016)
      local p = math.min(1, tw.t / tw.dur)
      local e = 1 - (1 - p) * (1 - p)  -- ease out
      tw.apply(obj, tw.from + (tw.to - tw.from) * e)
      if p >= 1 then Skin.tweens[obj] = nil if tw.done then tw.done(obj) end else any = true end
    end
    if not any then self:Hide() end
  end)
  Skin.driver = driver
  return driver
end
function Skin.Tween(obj, from, to, dur, apply, done)
  if not obj then return end
  if (dur or 0) <= 0 then apply(obj, to) if done then done(obj) end return end
  Skin.tweens[obj] = { t = 0, from = from, to = to, dur = dur, apply = apply, done = done }
  ensureDriver():Show()
end
function Skin.FadeTo(obj, to, dur)
  local from = obj.GetAlpha and obj:GetAlpha() or 0
  Skin.Tween(obj, from, to, dur or 0.15, function(o, v) o:SetAlpha(v) end)
end

-------------------------------------------------------------------------------
-- Type
-------------------------------------------------------------------------------
-- role: "head" (or true, the old `head` flag), "body" (default), "semi" or "label".
-- Body and semi get +1 px over the size asked for, as the body font always has (12 -> 13 px).
local ROLES = { head = true, body = true, semi = true, label = true }
function Skin.Role(role)
  if role == true then return "head" end
  return ROLES[role or ""] and role or "body"
end
function Skin.FontPx(size, role)
  role = Skin.Role(role)
  return (size or 12) + ((role == "body" or role == "semi") and 1 or 0)
end
local function setFont(fs, role, px, flags)
  if not fs.SetFont then return end
  local ok, res = pcall(fs.SetFont, fs, Skin.FONTS[role], px, flags or "")
  if not ok or res == false then
    -- our file did not load: the client's own font, so text never disappears
    fs.panoplyFontFallback = true
    pcall(fs.SetFont, fs, role == "head" and Skin.GAME_FONTS.head or Skin.GAME_FONTS.body, px, flags or "")
  end
end
Skin.SetFontFile = setFont
function Skin.Font(fs, size, color, flags, role)
  role = Skin.Role(role)
  local px = Skin.FontPx(size, role)
  fs.panoplyRole, fs.panoplyPx, fs.panoplyFlags = role, px, flags
  setFont(fs, role, px, flags)
  local c = color or Skin.colors.text
  if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], 1) end
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.75) end
  if fs.SetSpacing then fs:SetSpacing(2) end
  if fs.panoplyRich ~= nil then Skin.LayoutHeading(fs) end
  return fs
end

-------------------------------------------------------------------------------
-- v3 headings: numbers inside a Spectral SC heading are set in Lato SemiBold (Spectral's small
-- caps make "1" read as "I"). A FontString cannot mix fonts, so a heading whose text has digits
-- keeps its full text (invisible: measured, wrapped and anchored as usual) and draws the runs on
-- top with one FontString each, laid out on one line. A heading that would not fit on one line
-- stays plain Spectral SC. The run FontStrings are decorative (panoplyLayoutSkip); the layout checker
-- measures the heading itself.
-------------------------------------------------------------------------------
local function baseMethod(t, name)
  local mt = getmetatable(t)
  local idx = mt and mt.__index
  return (type(idx) == "table" and idx[name]) or (type(idx) == "function" and idx(t, name)) or t[name]
end
-- "Your route: level 1 to 4" -> { "Your route: level ", false }, { "1", true }, { " to ", false }, ...
function Skin.NumberRuns(t)
  local out, i = {}, 1
  t = tostring(t or "")
  while true do
    local s, e = t:find("%d[%d,%.:/]*", i)
    if not s then break end
    while e > s and not t:sub(e, e):match("%d") do e = e - 1 end
    if t:sub(e + 1, e + 1) == "%" then e = e + 1 end
    if s > i then out[#out + 1] = { t:sub(i, s - 1), false } end
    out[#out + 1] = { t:sub(s, e), true }
    i = e + 1
  end
  if i <= #t then out[#out + 1] = { t:sub(i), false } end
  return out
end
local function richOff(fs)
  if not fs.panoplyRich then return end
  fs.panoplyRich = false
  local M, c = fs.panoplyRichM, fs.panoplyColor or Skin.colors.heading
  M.SetTextColor(fs, c[1], c[2], c[3], c[4] or 1)
  if fs.SetShadowColor then M.SetShadowColor(fs, 0, 0, 0, fs.panoplyShadowA or 0.75) end
  for _, s in ipairs(fs.panoplySegs) do s:Hide() end
end
-- A heading's runs are split into words (a number stays glued to the text around it unless a
-- space separates them) and wrapped greedily inside the heading's width, so a long heading keeps
-- its Lato numbers on two or more lines too. If our wrap needs more lines than the heading itself
-- (measured by the client), or a wrapped heading is centred or right-aligned, it stays plain.
local function headingTokens(runs)
  local tk = {}
  for _, r in ipairs(runs) do
    if r[2] then tk[#tk + 1] = { r[1], true }
    else
      local lead = r[1]:match("^ +")
      if lead then tk[#tk + 1] = { lead, false } end
      for w in r[1]:gmatch("[^ ]+ *") do tk[#tk + 1] = { w, false } end
    end
  end
  return tk
end
function Skin.LayoutHeading(fs)
  if fs.panoplyRich == nil then return end
  local t = fs.panoplyFull
  local runs = fs.panoplyRole == "head" and type(t) == "string" and t:find("%d") and not t:find("|", 1, true)
    and not t:find("\n", 1, true) and Skin.NumberRuns(t)
  if not runs or #runs < 1 then richOff(fs) return end
  local parent = fs:GetParent()
  local layer = fs.GetDrawLayer and fs:GetDrawLayer() or "OVERLAY"
  local px, c = fs.panoplyPx or 16, fs.panoplyColor or Skin.colors.heading
  local fw = fs.panoplyWidthSet or 0
  local function seg(i, text, num)
    local s = fs.panoplySegs[i]
    if not s then
      s = parent:CreateFontString(nil, layer)
      s.panoplyLayoutSkip, s.panoplyHeadingRun = true, fs
      if s.SetWordWrap then s:SetWordWrap(false) end
      if s.SetJustifyH then s:SetJustifyH("LEFT") end
      fs.panoplySegs[i] = s
    end
    local role = num and "semi" or "head"
    setFont(s, role, num and math.floor(px * Skin.NUMBER_SCALE + 0.5) or px, fs.panoplyFlags)
    s.panoplyRole = role
    s:SetText(text)
    if s.SetShadowOffset then s:SetShadowOffset(1, -1.5) end
    if s.SetShadowColor then s:SetShadowColor(0, 0, 0, fs.panoplyShadowA or 0.75) end
    s.panoplyW = s:GetStringWidth() or 0
    s.panoplyH = s.GetStringHeight and s:GetStringHeight() or px
    return s
  end
  local total = 0
  for i, r in ipairs(runs) do total = total + seg(i, r[1], r[2]).panoplyW end
  local n, place = #runs, {}
  if fw > 0 and total > fw + 0.5 then
    -- wrap: words of tokens, greedy, left-aligned
    if (fs.panoplyJustify or "LEFT") ~= "LEFT" then richOff(fs) for i = 1, #fs.panoplySegs do fs.panoplySegs[i]:Hide() end return end
    local tk = headingTokens(runs)
    n = #tk
    local lineH, words, cur = 0, {}, nil
    for i, x in ipairs(tk) do
      local s = seg(i, x[1], x[2])
      if s.panoplyH and s.panoplyH > lineH and not x[2] then lineH = s.panoplyH end
      if not cur then cur = { w = 0, trail = 0, segs = {} } words[#words + 1] = cur end
      cur.segs[#cur.segs + 1] = s
      cur.w = cur.w + s.panoplyW
      if not x[2] and x[1]:find(" $") then
        local bare = x[1]:gsub(" +$", "")
        s:SetText(bare); cur.trail = s.panoplyW - (s:GetStringWidth() or s.panoplyW); s:SetText(x[1])
        cur = nil
      end
    end
    if lineH <= 0 then lineH = px end
    lineH = lineH + 2   -- the heading's line spacing (Skin.Font sets SetSpacing(2))
    local x, line = 0, 0
    for _, w in ipairs(words) do
      if x > 0 and x + w.w - w.trail > fw + 0.5 then x, line = 0, line + 1 end
      for _, s in ipairs(w.segs) do place[#place + 1] = { s, x, line } x = x + s.panoplyW end
    end
    local lines = line + 1
    local room = Skin.TextHeight(fs, fw)
    if lines * lineH > room + lineH * 0.5 then richOff(fs) for i = 1, #fs.panoplySegs do fs.panoplySegs[i]:Hide() end return end
    for _, p in ipairs(place) do p[4] = -(p[3] * lineH + (lineH - 2) / 2) end
  else
    local j = fs.panoplyJustify or "LEFT"
    local x = (fw > 0 and j == "CENTER") and (fw - total) / 2 or ((fw > 0 and j == "RIGHT") and (fw - total) or 0)
    for i = 1, n do place[i] = { fs.panoplySegs[i], x, nil } x = x + fs.panoplySegs[i].panoplyW end
  end
  for i = n + 1, #fs.panoplySegs do fs.panoplySegs[i]:Hide() end
  for _, p in ipairs(place) do
    local s = p[1]
    s:ClearAllPoints()
    if p[4] then s:SetPoint("LEFT", fs, "TOPLEFT", p[2], p[4]) else s:SetPoint("LEFT", fs, "LEFT", p[2], 0) end
    s:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    s:SetAlpha(fs.panoplyAlpha or 1)
    if fs:IsShown() then s:Show() else s:Hide() end
  end
  fs.panoplyRich = true
  local M = fs.panoplyRichM
  M.SetTextColor(fs, c[1], c[2], c[3], 0)
  if fs.SetShadowColor then M.SetShadowColor(fs, 0, 0, 0, 0) end
end
function Skin.NumberHeading(fs)
  if not fs or fs.panoplyRich ~= nil then return fs end
  local M = {}
  for _, n in ipairs({ "SetText", "SetTextColor", "SetShadowColor", "SetAlpha", "Show", "Hide", "SetWidth", "SetJustifyH" }) do M[n] = baseMethod(fs, n) end
  fs.panoplyRichM, fs.panoplySegs, fs.panoplyRich = M, {}, false
  fs.SetText = function(self, t) M.SetText(self, t) self.panoplyFull = t Skin.LayoutHeading(self) end
  fs.SetFormattedText = function(self, f, ...) self:SetText(f:format(...)) end
  fs.SetTextColor = function(self, r, g, b, a)
    self.panoplyColor = { r, g, b, a or 1 }
    if self.panoplyRich then M.SetTextColor(self, r, g, b, 0) for _, s in ipairs(self.panoplySegs) do s:SetTextColor(r, g, b, a or 1) end
    else M.SetTextColor(self, r, g, b, a) end
  end
  fs.SetShadowColor = function(self, r, g, b, a)
    self.panoplyShadowA = a
    M.SetShadowColor(self, r, g, b, self.panoplyRich and 0 or a)
    for _, s in ipairs(self.panoplySegs) do if s.SetShadowColor then s:SetShadowColor(r, g, b, a) end end
  end
  fs.SetAlpha = function(self, a) M.SetAlpha(self, a) self.panoplyAlpha = a for _, s in ipairs(self.panoplySegs) do s:SetAlpha(a) end end
  fs.Show = function(self) M.Show(self) if self.panoplyRich then Skin.LayoutHeading(self) end end
  fs.Hide = function(self) M.Hide(self) for _, s in ipairs(self.panoplySegs) do s:Hide() end end
  fs.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
  fs.SetWidth = function(self, w) M.SetWidth(self, w) self.panoplyWidthSet = w Skin.LayoutHeading(self) end
  fs.SetJustifyH = function(self, j) M.SetJustifyH(self, j) self.panoplyJustify = j Skin.LayoutHeading(self) end
  fs.GetText = function(self) return self.panoplyFull end
  return fs
end

-- v3: Lato is wider than Arial Narrow, so a single-line name that may be long (quest names) is
-- measured and cut with an ellipsis to fit maxW. Colour codes are kept and closed. Returns true
-- when the text was cut. The full text stays on fs.panoplyFullText (tooltips can show it).
local ELLIPSIS = "\226\128\166"   -- U+2026
local function tokens(t)
  local out, i = {}, 1
  while i <= #t do
    local esc = t:match("^|c%x%x%x%x%x%x%x%x", i) or t:match("^|r", i) or t:match("^|T.-|t", i)
    if esc then out[#out + 1] = { esc, true } i = i + #esc
    else
      local ch = t:match("^[%z\1-\127\194-\244][\128-\191]*", i) or t:sub(i, i)
      out[#out + 1] = { ch, false } i = i + #ch
    end
  end
  return out
end
function Skin.Ellipsize(fs, text, maxW)
  text = tostring(text or "")
  fs.panoplyFullText = text
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(text)
  if not maxW or maxW <= 0 or Skin.TextWidth(fs) <= maxW then fs.panoplyCut = nil return false end
  local tk = tokens(text)
  local chars = {}
  for i, x in ipairs(tk) do if not x[2] then chars[#chars + 1] = i end end
  local function build(n)
    local parts, seen, open = {}, 0, false
    for _, x in ipairs(tk) do
      if seen >= n then break end
      parts[#parts + 1] = x[1]
      if x[2] then
        if x[1]:sub(1, 2) == "|c" then open = true elseif x[1] == "|r" then open = false end
      else seen = seen + 1 end
    end
    local s = table.concat(parts):gsub("%s+$", "")
    return s .. ELLIPSIS .. (open and "|r" or "")
  end
  local lo, hi = 0, #chars
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    fs:SetText(build(mid))
    if Skin.TextWidth(fs) <= maxW then lo = mid else hi = mid - 1 end
  end
  fs:SetText(build(lo))
  fs.panoplyCut = true
  return true
end

-- 0.5.5 measured layout. The real client's fonts are larger than any estimate, and
-- GetStringHeight can lag before the first draw, so we take the larger of the client's own
-- measurement and a generous estimate. Never assume one line.
local function plainText(t)
  t = tostring(t or "")
  return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW"):gsub("|H.-|h(.-)|h", "%1"))
end
-- characters, not bytes (an ellipsis or an accented name is one character)
local function ulen(t) return #(t:gsub("[\128-\191]", "")) end
local function fontSize(fs)
  local size
  if fs.GetFont then local _, s = fs:GetFont() size = s end
  return (type(size) == "number" and size > 0) and size or 12
end
function Skin.TextWidth(fs)
  local t = fs.GetText and fs:GetText()
  if not t or t == "" then return 0 end
  local w = fs.GetStringWidth and fs:GetStringWidth() or 0
  local longest = 0
  for para in (plainText(t) .. "\n"):gmatch("(.-)\n") do longest = math.max(longest, ulen(para)) end
  return math.max(w or 0, longest * fontSize(fs) * 0.5)
end
function Skin.TextHeight(fs, width)
  local t = fs.GetText and fs:GetText()
  if not t or t == "" then return 0 end
  local size = fontSize(fs)
  local own = width == nil
  width = width or (fs.GetWidth and fs:GetWidth()) or 0
  local plain = plainText(t)
  local longest = 1
  for para in (plain .. "\n"):gmatch("(.-)\n") do longest = math.max(longest, ulen(para)) end
  local natural = Skin.TextWidth(fs)
  local charW = math.max(size * 0.5, natural / longest)
  -- text that already fits its width (or has no width of its own) is one line per paragraph
  local sw = fs.GetStringWidth and fs:GetStringWidth() or 0
  local fits = natural <= width + 0.5 or (own and sw > 0 and sw <= width + 0.5)
  local lines = 0
  for para in (plain .. "\n"):gmatch("(.-)\n") do
    lines = lines + ((width > 0 and not fits and fs.panoplyNoWrap ~= true) and math.max(1, math.ceil(ulen(para) * charW / (width * 0.94))) or 1)
  end
  local h = fs.GetStringHeight and fs:GetStringHeight() or 0
  return math.max(h or 0, lines * (size * 1.25 + 2))
end
-- 0.6.0 (tracker): the real wrapped line count. Each word is measured with the font's own
-- metrics (a hidden one-line FontString's GetStringWidth: the client's real advances, the calibrated
-- ones in the tests) and words are laid greedily the way the client wraps, so a row is exactly as
-- tall as the lines it draws. Returns lines, one line's height and the last line's width; nil when
-- the font cannot be measured (callers then fall back to Skin.TextHeight).
local measurer
local function measureFS()
  if measurer then return measurer end
  if not _G.CreateFrame then return nil end
  local f = CreateFrame("Frame")
  f:Hide()
  measurer = f:CreateFontString(nil, "OVERLAY")
  if measurer.SetWordWrap then measurer:SetWordWrap(false) end
  return measurer
end
function Skin.WrapMeasure(fs, width, text)
  local t = text or (fs.GetText and fs:GetText())
  if not t or t == "" then return 0, 0, 0 end
  local m = measureFS()
  if not m or not fs.GetFont then return nil end
  local path, size, flags = fs:GetFont()
  if not path or not size then return nil end
  if not pcall(m.SetFont, m, path, size, flags or "") then return nil end
  local function w(str) m:SetText(str) return (m:GetStringWidth() or 0) end
  local space = w("a a") - w("aa")
  m:SetText("Hg")
  local lineH = m:GetStringHeight() or 0
  if lineH <= 0 or w("Hg") <= 0 then return nil end
  width = (width or 0) - 1                 -- 1 px tolerance: never promise a fit the client would wrap
  local lines, lastW = 0, 0
  for para in (plainText(t) .. "\n"):gmatch("(.-)\n") do
    lines = lines + 1
    local cur = 0
    for word in para:gmatch("%S+") do
      local ww = w(word)
      if cur == 0 then cur = ww
      elseif width > 0 and cur + space + ww > width then lines = lines + 1 cur = ww
      else cur = cur + space + ww end
      -- a single word wider than the line breaks inside itself
      while width > 0 and cur > width + 1 do lines = lines + 1 cur = cur - width end
    end
    lastW = cur
  end
  m:SetText("")
  return lines, lineH, lastW
end
-- Set width + text and return the measured height.
function Skin.FitText(fs, width, text)
  if width then fs:SetWidth(width) end
  if text then fs:SetText(text) end
  local h = Skin.TextHeight(fs, width)
  return h
end
-- Button width that fits its label (and icon) with padding.
-- A label too long for maxW wraps onto two lines and the button grows taller instead.
function Skin.FitButton(b, minW, maxW)
  -- Step 20: a Kit.Dropdown has a chevron to leave room for; it fits itself (Kit.lua, b:Fit)
  if b.panoplyFit then local w = b:panoplyFit(minW, maxW) return w, b:GetHeight() end
  local pad = 2 * Skin.SP.m + (b.icon and b.icon:IsShown() and 24 or 0)
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  if b.panoplyWrapped then b.label:SetWidth(0) b.label.hasW = nil b.panoplyWrapped = nil b:SetHeight(b.panoplyBaseH or b:GetHeight()) end
  b.panoplyBaseH = b.panoplyBaseH or b:GetHeight()
  local w = math.max(minW or 60, math.ceil(Skin.TextWidth(b.label) + pad))
  if maxW and w > maxW then
    w = maxW
    local lw = maxW - pad
    if b.label.SetWordWrap then b.label:SetWordWrap(true) end
    b.label:SetWidth(lw)
    b.panoplyWrapped = true
    b:SetHeight(math.max(b.panoplyBaseH, math.ceil(Skin.TextHeight(b.label, lw) + 10)))
  end
  if b.panoplyFixedH and b:GetHeight() < b.panoplyFixedH then b:SetHeight(b.panoplyFixedH) end
  b:SetWidth(w)
  return w, b:GetHeight()
end
-- Lay buttons left to right from (x, y) under parent's TOPLEFT, wrapping to a new row when the
-- next one would pass maxW. Each button is sized to its label. Returns the height used.
-- fromBottom: y is the gap above parent's bottom edge and the rows are pinned there instead.
function Skin.FlowButtons(parent, list, x, y, maxW, gap, minW, fromBottom)
  gap = gap or Skin.SP.s
  local cx, cy, rowH = 0, 0, 0
  local pos = {}
  for _, b in ipairs(list) do
    if (b:IsShown() or not fromBottom) and not b.panoplyFlowSkip then
      local w = Skin.FitButton(b, minW, maxW)
      local h = b:GetHeight() or 22
      if cx > 0 and cx + w > maxW then cx, cy = 0, cy + rowH + gap; rowH = 0 end
      pos[#pos + 1] = { b, cx, cy, h }
      cx = cx + w + gap
      rowH = math.max(rowH, h)
    end
  end
  local total = cy + rowH
  for _, p in ipairs(pos) do
    local b = p[1]
    b:ClearAllPoints()
    if fromBottom then b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + p[2], y + total - p[3] - p[4])
    else b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + p[2], y - p[3]) end
  end
  return total
end

-- 0.9.0 ("none of our windows have it enabled"): the scroll bar every list in the suite uses. Still the thin gold line on a
-- dim track, but now a real control on all clients (Classic Era 1.15 and WoW Forever, plain Frames and Buttons only):
--   * the thumb can be clicked and dragged up and down,
--   * a click on the track above or below the thumb moves one page that way (held down, it keeps paging),
--   * a small arrow button at each end moves one step (held down, it keeps stepping),
--   * the mouse wheel is the list's own (Skin.ScrollArea and the lists that keep their own bar wire it to the same moves).
-- opts: get() -> where the list is now; max() -> the furthest it goes (0 or less: no bar); set(v) moves the list (v is clamped
-- here first); ratio() -> how much of the list shows, 0 to 1 (the thumb's share of the track); step (one arrow click, default 40);
-- page() -> one track click (default 0.9 of step x 10); length() -> the bar's height (default its own GetHeight); width (default 10).
-- The caller anchors the bar and calls bar:Update() when the list, its size or its place changes.
Skin.TEX.ScrollArrow = Skin.MEDIA .. "ScrollArrow"   -- our own chevron (tools/make_scroll_arrow.py), white, tinted here
Skin.SCROLL = { width = 10, arrow = 10, minThumb = 16, wait = 0.4, every = 0.06 }

local function cursorY(region)
  local _, y = GetCursorPosition()
  if type(y) ~= "number" then return nil end
  local es = (region.GetEffectiveScale and region:GetEffectiveScale()) or 1
  if type(es) ~= "number" or es <= 0 then es = 1 end
  return y / es
end

-- run fn now, and again while the button stays held (a short wait first, then quickly), as a scroll bar does
local function repeatWhileHeld(b, fn)
  b:SetScript("OnMouseDown", function(self, button)
    if button and button ~= "LeftButton" then return end
    fn(self)
    self.panoplyHeld, self.panoplyHeldWait = true, Skin.SCROLL.wait
    self:SetScript("OnUpdate", function(s, dt)
      if not s.panoplyHeld then s:SetScript("OnUpdate", nil) return end
      s.panoplyHeldWait = s.panoplyHeldWait - (dt or 0)
      if s.panoplyHeldWait <= 0 then s.panoplyHeldWait = Skin.SCROLL.every fn(s) end
    end)
  end)
  local function stop(self) self.panoplyHeld = nil self:SetScript("OnUpdate", nil) end
  b:SetScript("OnMouseUp", stop)
  b:SetScript("OnHide", stop)
end

function Skin.ScrollBar(parent, opts)
  opts = opts or {}
  local S = Skin.SCROLL
  local W = opts.width or S.width
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(W)
  bar.opts = opts
  bar.panoplyScrollBar = true
  local gold, dim = Skin.colors.gold, Skin.colors.dim
  local function arrow(dir)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(W, S.arrow)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetTexture(Skin.TEX.ScrollArrow)
    t:SetSize(W, W); t:SetPoint("CENTER", b, "CENTER", 0, 0)
    if dir > 0 then t:SetTexCoord(0, 1, 1, 0) end   -- the down button: the same chevron, flipped
    t:SetVertexColor(gold[1], gold[2], gold[3], 1); t:SetAlpha(0.7)
    b.tex, b.panoplyDir = t, dir
    b:SetScript("OnEnter", function() t:SetAlpha(1) end)
    b:SetScript("OnLeave", function() t:SetAlpha(0.7) end)
    repeatWhileHeld(b, function() bar:Step(dir) end)
    return b
  end
  bar.up, bar.down = arrow(-1), arrow(1)
  bar.up:SetPoint("TOP", bar, "TOP", 0, 0)
  bar.down:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
  -- the track: a Button so a click on it can page; the line drawn in it is the old 4 px dim line
  local tb = CreateFrame("Button", nil, bar)
  bar.trackButton = tb
  local line = tb:CreateTexture(nil, "ARTWORK")
  line:SetWidth(4); line:SetPoint("TOP", tb, "TOP", 0, 0); line:SetPoint("BOTTOM", tb, "BOTTOM", 0, 0)
  Skin.Solid(line, dim, 0.18)
  bar.track = line
  -- the thumb: a Button in the track, the old 4 px gold line drawn in it; its hit area is the bar's whole width
  local thumb = CreateFrame("Button", nil, tb)
  thumb:SetWidth(W)
  local tt = thumb:CreateTexture(nil, "OVERLAY")
  tt:SetWidth(4); tt:SetPoint("TOP", thumb, "TOP", 0, 0); tt:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  Skin.Solid(tt, gold, 0.75)
  thumb.tex = tt
  bar.thumb = thumb
  thumb:SetScript("OnEnter", function() tt:SetAlpha(1) end)
  thumb:SetScript("OnLeave", function() if not bar.drag then tt:SetAlpha(0.75) end end)

  local function get() return (opts.get and opts.get()) or 0 end
  local function maxv() return math.max(0, (opts.max and opts.max()) or 0) end
  function bar:Set(v)
    local m = maxv()
    v = math.max(0, math.min(m, v or 0))
    if opts.set then opts.set(v) end
    self:Update()
    return v
  end
  function bar:Step(dir) return self:Set(get() + (dir or 0) * (opts.step or 40)) end
  function bar:PageSize() return (opts.page and opts.page()) or (opts.step or 40) * 9 end
  function bar:Page(dir) return self:Set(get() + (dir or 0) * self:PageSize()) end
  function bar:Length()
    local L = opts.length and opts.length() or self:GetHeight()
    return type(L) == "number" and L or 0
  end
  -- where the parts go; hides the bar when the list fits
  function bar:Update()
    local m = maxv()
    if m <= 0.5 then self:Hide() self.shown = false return end
    self:Show()
    self.shown = true
    local L = self:Length()
    local a = L >= 3 * S.arrow + S.minThumb and S.arrow or 0     -- a very short bar has no room for arrows
    if a > 0 then self.up:Show() self.down:Show() else self.up:Hide() self.down:Hide() end
    tb:ClearAllPoints()
    tb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(a > 0 and a + 1 or 0))
    tb:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, a > 0 and a + 1 or 0)
    local trackL = math.max(1, L - (a > 0 and 2 * (a + 1) or 0))
    tb:SetHeight(trackL)
    local r = (opts.ratio and opts.ratio()) or 0.5
    local th = math.min(trackL, math.max(S.minThumb, trackL * math.max(0, math.min(1, r))))
    local pos = (trackL - th) * math.max(0, math.min(1, get() / m))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", tb, "TOP", 0, -pos)
    self.trackL, self.thumbH, self.thumbPos = trackL, th, pos
  end
  -- a click on the track, off pixels below its top: one page towards it (on the thumb itself: nothing)
  function bar:ClickTrack(off)
    if not (off and self.thumbPos) then return end
    if off < self.thumbPos then return self:Page(-1) end
    if off > self.thumbPos + (self.thumbH or 0) then return self:Page(1) end
  end
  -- dragging: dy pixels down from where the thumb was picked up moves the list in proportion
  function bar:BeginDrag(y)
    self.drag = { y = y or 0, v = get() }
    tt:SetAlpha(1)
  end
  function bar:DragTo(y)
    local d = self.drag
    if not (d and y) then return end
    local span = (self.trackL or 0) - (self.thumbH or 0)
    if span <= 0 then return end
    return self:Set(d.v + (d.y - y) * maxv() / span)
  end
  function bar:EndDrag()
    self.drag = nil
    thumb:SetScript("OnUpdate", nil)
    tt:SetAlpha(thumb:IsMouseOver() and 1 or 0.75)
  end
  thumb:SetScript("OnMouseDown", function(self, button)
    if button and button ~= "LeftButton" then return end
    bar:BeginDrag(cursorY(self))
    self:SetScript("OnUpdate", function(s) bar:DragTo(cursorY(s)) end)
  end)
  thumb:SetScript("OnMouseUp", function() bar:EndDrag() end)
  thumb:SetScript("OnHide", function() if bar.drag then bar:EndDrag() end end)
  repeatWhileHeld(tb, function(self)
    local top, y = self:GetTop(), cursorY(self)
    if top and y then bar:ClickTrack(top - y) end
  end)
  return bar
end

-- 0.5.5: a scrolling area for pages that can grow past the window (real fonts, many modules).
-- area.content is the frame to build into; call area:SetContentHeight(h) after laying out.
-- The thin bar on the right only shows when the content is taller than the view (0.9.0: Skin.ScrollBar, so it drags too).
-- area:ScrollTo(v) moves the view (clamped); area:Step(dir) one step. A page can change how it moves: area.panoplyScrollTo(area, v)
-- (a list that only stops on whole rows), area.panoplyStep(area, dir), area.panoplyCanScroll() (false: the bar and the wheel do nothing),
-- area.panoplyOnScroll(area, v) (after every move).
function Skin.ScrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf.panoplyScroll = true
  local child = CreateFrame("Frame", nil, sf)
  child:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
  child:SetSize(10, 10)
  if sf.SetScrollChild then sf:SetScrollChild(child) end
  sf.content = child
  sf.contentH = 0
  local function cur() return (sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0 end
  local bar = Skin.ScrollBar(sf, {
    get = cur,
    max = function() return sf:MaxScroll() end,
    set = function(v) sf:ScrollTo(v, true) end,
    ratio = function() return sf.contentH > 0 and sf:ViewH() / sf.contentH or 1 end,
    step = 40,
    page = function() return math.max(40, sf:ViewH() - 40) end,
    length = function() return sf:ViewH() - 4 end,
  })
  bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -1, -2); bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 2)
  bar:Hide()
  sf.bar = bar
  sf.track, sf.thumb = bar.track, bar.thumb
  function sf:ViewH() return self:GetHeight() or 0 end
  function sf:MaxScroll() return math.max(0, self.contentH - self:ViewH()) end
  function sf:UpdateBar()
    local need = self:MaxScroll() > 0.5
    child:SetWidth(math.max(10, (self:GetWidth() or 10) - (need and 12 or 0)))
    if not need then
      if self.SetVerticalScroll then self:SetVerticalScroll(0) end
      bar:Hide() bar.shown = false
      return
    end
    bar:Update()
  end
  -- move the view to v (clamped to the content); fromBar: the bar asked, so it is not asked back
  function sf:ScrollTo(v, fromBar)
    if self.panoplyCanScroll and not self.panoplyCanScroll() then return cur() end
    if self.panoplyScrollTo and not self.panoplyScrolling then
      self.panoplyScrolling = true
      local ok, err = pcall(self.panoplyScrollTo, self, v)
      self.panoplyScrolling = nil
      if not ok then error(err) end
    else
      v = math.max(0, math.min(self:MaxScroll(), v or 0))
      if self.SetVerticalScroll then self:SetVerticalScroll(v) end
    end
    if not fromBar then self:UpdateBar() end
    if self.panoplyOnScroll then self.panoplyOnScroll(self, cur()) end
    return cur()
  end
  function sf:Step(dir)
    if self.panoplyStep then return self.panoplyStep(self, dir) end
    return self:ScrollTo(cur() + (dir or 0) * 40)
  end
  bar.Step = function(_, dir) local v = sf:Step(dir) bar:Update() return v end
  function sf:SetContentHeight(h)
    self.contentH = h or 0
    child:SetHeight(math.max(10, self.contentH))
    if cur() > self:MaxScroll() and self.SetVerticalScroll then self:SetVerticalScroll(self:MaxScroll()) end
    self:UpdateBar()
  end
  -- the width available to content (the bar takes 12 when it shows)
  function sf:ContentWidth(h)
    return (self:GetWidth() or 10) - (((h or self.contentH) > self:ViewH() + 0.5) and 12 or 0)
  end
  if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
  sf:SetScript("OnMouseWheel", function(self, delta)
    self:ScrollTo(cur() - (delta or 0) * 40)
  end)
  sf:SetScript("OnSizeChanged", function(self) self:UpdateBar() end)
  -- a page that sets the scroll itself (SetVerticalScroll) still gets the thumb in the right place
  sf:SetScript("OnVerticalScroll", function(self) if bar.shown then bar:Update() end end)
  return sf
end

-- role: nil (body), true / "head", "semi" or "label" (see Skin.Font).
function Skin.Text(parent, size, color, layer, role)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  Skin.Font(fs, size, color, nil, role)
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.panoplyRole == "head" then Skin.NumberHeading(fs) end
  return fs
end
-- Text on content cards (light, softer shadow).
-- "|cffrrggbb" chat/text colour code for a Skin.colors entry (so inline colours follow the skin).
function Skin.Code(c)
  c = c or Skin.colors.text
  return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Body text on a card. Skin v3: an inkTitle line of 12 px or more is a section heading, so it
-- takes the heading face (Spectral SC, numbers in Lato) like Skin.Heading.
function Skin.Ink(parent, size, color)
  local head = color == Skin.colors.inkTitle and (size or 12) >= 12
  local fs = Skin.Text(parent, size, color or Skin.colors.ink, nil, head and "head" or nil)
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.5) end
  return fs
end
-- Spectral SC heading in heading gold (numbers in Lato SemiBold, see Skin.NumberHeading).
function Skin.Heading(parent, size, text)
  local fs = Skin.Text(parent, size or 16, Skin.colors.heading, nil, "head")
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1.5) end
  if fs.SetSpacing then fs:SetSpacing(1) end
  Skin.NumberHeading(fs)
  if text then fs:SetText(text) end
  return fs
end
-- Names, values, quest titles: Lato SemiBold.
function Skin.Name(parent, size, color)
  return Skin.Text(parent, size or 13, color or Skin.colors.text, nil, "semi")
end
-- Small capital labels (ROUTE, LEVEL 4): Lato Bold.
function Skin.Label(parent, size, color)
  local fs = Skin.Text(parent, size or 11, color or Skin.colors.inkSoft, nil, "label")
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.5) end
  return fs
end

function Skin.Gradient(tex, top, bottom, alpha)
  tex:SetTexture(Skin.WHITE)
  local ok = false
  if _G.CreateColor and tex.SetGradient then
    ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], alpha or 1), CreateColor(top[1], top[2], top[3], alpha or 1))
  end
  if not ok and tex.SetGradientAlpha then
    ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], alpha or 1, top[1], top[2], top[3], alpha or 1)
  end
  if not ok then tex:SetVertexColor(top[1], top[2], top[3], alpha or 1) end
end

-- Hairline gold divider with a small centre diamond.
function Skin.Divider(parent, y, inset, width)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(Skin.TEX.Divider)
  t:SetHeight(12)
  if width then
    t:SetWidth(width); t:SetPoint("TOP", parent, "TOP", 0, y)
  else
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", inset or 10, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 10), y)
  end
  return t
end
function Skin.Rule(parent, y, inset)
  local t = parent:CreateTexture(nil, "ARTWORK")
  solid(t, Skin.colors.gold, 0.35)
  t:SetHeight(1)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", inset or 8, y)
  t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset or 8), y)
  return t
end

-------------------------------------------------------------------------------
-- Frames: 9-slice trims, shadows, panels, cards
-------------------------------------------------------------------------------
-- Eight textures from one atlas (corners keep their size, edges stretch). No centre piece.
function Skin.NineSlice(f, tex, corner, outset, layer, c)
  c = c or 0.25
  outset = outset or 0
  layer = layer or "BORDER"
  local P = {}
  local function piece(l, r, t, b) local x = f:CreateTexture(nil, layer); x:SetTexture(tex); x:SetTexCoord(l, r, t, b); P[#P + 1] = x return x end
  local tl = piece(0, c, 0, c); tl:SetSize(corner, corner); tl:SetPoint("TOPLEFT", f, "TOPLEFT", -outset, outset)
  local tr = piece(1 - c, 1, 0, c); tr:SetSize(corner, corner); tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", outset, outset)
  local bl = piece(0, c, 1 - c, 1); bl:SetSize(corner, corner); bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -outset, -outset)
  local br = piece(1 - c, 1, 1 - c, 1); br:SetSize(corner, corner); br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", outset, -outset)
  local t = piece(c, 1 - c, 0, c); t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local b = piece(c, 1 - c, 1 - c, 1); b:SetPoint("TOPLEFT", bl, "TOPRIGHT"); b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local l = piece(0, c, c, 1 - c); l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local r = piece(1 - c, 1, c, 1 - c); r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  function P:SetColor(rr, g, bb, a) for _, x in ipairs(self) do x:SetVertexColor(rr, g, bb, a or 1) end end
  function P:SetAlpha(a) for _, x in ipairs(self) do x:SetAlpha(a) end end
  return P
end

-- v3 has no soft drop shadow (no glow anywhere): kept as an empty piece list for older callers.
local NO_PIECES = { SetColor = function() end, SetAlpha = function() end }
function Skin.Shadow(f) f.panoplyShadow = NO_PIECES return f.panoplyShadow end

-- v3 rounded box from one of our frame atlases (Skin.BOX L / M / S): a fill mask and a trim
-- mask, each tinted from Skin.colors, so opacity can fade the fill and keep the trim.
-- opts: fill / fillA / line / lineA (colours and alphas, line = false for none), inset, layer.
function Skin.Box(f, size, opts)
  opts = opts or {}
  local B = Skin.BOX[size or "M"] or Skin.BOX.M
  local inset = opts.inset or 0
  local function make(atlas, layer, col, a)
    local t = f:CreateTexture(nil, layer)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    Skin.Round(t, B.corner, atlas)
    t:SetVertexColor(col[1], col[2], col[3], a or 1)
    return t
  end
  local fill = make(B.fill, opts.layer or "BACKGROUND", opts.fill or Skin.colors.panel, opts.fillA or Skin.ALPHA.panel)
  local line = opts.line ~= false and make(B.line, opts.lineLayer or "BORDER", opts.line or Skin.colors.trim, opts.lineA or 1) or nil
  return fill, line
end

-- Corner caps (SPEC 19.13.2): our brass caps, 2 UI px outside each corner. Size follows the
-- panel: shortest side >= 110 large caps on all four corners, 64-109 mid caps on all four, smaller
-- frames small caps on top-left and bottom-right only. Re-picked whenever the frame changes size.
-- Inner cards, tabs, buttons and rows never get caps.
local CORNERS = { TL = { "TOPLEFT", -1, 1 }, TR = { "TOPRIGHT", 1, 1 }, BL = { "BOTTOMLEFT", -1, -1 }, BR = { "BOTTOMRIGHT", 1, -1 } }
function Skin.CapSize(w, h)
  local m = math.min(w or 0, h or 0)
  if m >= Skin.CAP.L.minSide then return "L" elseif m >= Skin.CAP.M.minSide then return "M"
  elseif m >= Skin.CAP.S.minSide then return "S" end
  return "none"
end
function Skin.UpdateCaps(f)
  local caps = f.panoplyCaps
  if not caps then return end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  local size = caps.force or Skin.CapSize(w, h)
  local C = Skin.CAP[size] or Skin.CAP.S
  caps.size = size
  for k, t in pairs(caps.tex) do
    local on = size ~= "none" and (size ~= "S" or k == "TL" or k == "BR")
    t:SetTexture(on and Skin.TEX["Cap" .. size .. k] or nil)
    t:SetSize(C.size, C.size)
    local c = CORNERS[k]
    t:ClearAllPoints(); t:SetPoint(c[1], f, c[1], c[2] * Skin.CAP_OUT, c[3] * Skin.CAP_OUT)
    t.panoplyCapOn = on
    if on and f.panoplyCapsShown ~= false then t:Show() else t:Hide() end
  end
end
function Skin.Caps(f, force)
  if f.panoplyCaps then f.panoplyCaps.force = force Skin.UpdateCaps(f) return f.panoplyCaps end
  local caps = { tex = {}, force = force }
  for k in pairs(CORNERS) do
    local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
    t.panoplyCap, t.panoplyCapCorner, t.panoplyCapOwner = true, k, f
    caps.tex[k] = t
  end
  f.panoplyCaps = caps
  Skin.UpdateCaps(f)
  if f.HookScript then
    f:HookScript("OnSizeChanged", function(self) Skin.UpdateCaps(self) end)
    f:HookScript("OnShow", function(self) Skin.UpdateCaps(self) end)
  end
  return caps
end
function Skin.CapsAlpha(f, a)
  if not f.panoplyCaps then return end
  for _, t in pairs(f.panoplyCaps.tex) do t:SetAlpha(a) end
end
-- The rectangles (in the frame's own coordinates: x right from its left edge, y down from its top)
-- the visible cap brackets cover; the layout checker keeps text and controls 2 px clear of them.
function Skin.CapRects(f)
  local caps = f.panoplyCaps
  if not caps then return {} end
  local C = Skin.CAP[caps.size or "S"]
  if not C then return {} end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  local o, out = Skin.CAP_OUT, {}
  for k, t in pairs(caps.tex) do
    if t.panoplyCapOn then
      local sx, sy = (k == "TL" or k == "BL") and 1 or -1, (k == "TL" or k == "TR") and 1 or -1
      local x0, y0 = sx > 0 and 0 or w, sy > 0 and 0 or h
      local function rect(ax, ay, bx, by)
        out[#out + 1] = { math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by), corner = k }
      end
      rect(x0 - sx * o, y0 - sy * o, x0 + sx * C.arm, y0 + sy * C.depth)   -- along the top / bottom edge
      rect(x0 - sx * o, y0 - sy * o, x0 + sx * C.depth, y0 + sy * C.arm)   -- along the left / right edge
    end
  end
  return out
end

-- The 1 px brass trim alone (older callers; Skin.Panel and Skin.Card draw their own).
function Skin.Border(f, thin, corner)
  local _, line = Skin.Box(f, thin and "M" or "L", { fill = Skin.colors.panel, fillA = 0, line = thin and Skin.colors.hairline or Skin.colors.trim })
  f.panoplyTrim = line
  f.panoplyBorder = thin and "trimThin" or "trim"
  return f.panoplyTrim
end

-- Kept for older callers: no filigree corners.
function Skin.Corners(f) f.panoplyCorners = {} end

-- v3 panel: slate fill, 1 px brass trim, brass corner caps. size "L" (windows, default), "M"
-- (dialogs, toasts) or "S" (small frames and pills). noCaps for frames that sit inside another.
function Skin.Panel(f, alpha, noShadow, size, noCaps)
  local fill, line = Skin.Box(f, size or "L", { fillA = Skin.ALPHA.panel })
  fill:SetAlpha(alpha or 1)
  f.panoplyBg, f.panoplyTrimTex = fill, line
  f.panoplyTrim = { SetAlpha = function(_, a) line:SetAlpha(a) Skin.CapsAlpha(f, a) end, SetColor = function(_, r, g, b, a) line:SetVertexColor(r, g, b, a or 1) end }
  f.panoplyBox = true
  f.panoplyBorder = "trim"
  f.panoplyPanel = size or "L"
  f.panoplyShadow = NO_PIECES
  if not noCaps then Skin.Caps(f) end
  return f
end

-- Content card: the inset card colour (#0e141c at 70%) with a hairline, radius 8, no caps.
function Skin.Card(parent)
  local p = CreateFrame("Frame", nil, parent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  local fill, line = Skin.Box(p, "M", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  fill:SetAlpha(Skin.ALPHA.card)
  p.panoplyBg, p.panoplyTrimTex = fill, line
  p.panoplyTrim = { SetAlpha = function(_, a) line:SetAlpha(a) end, SetColor = function(_, r, g, b, a) line:SetVertexColor(r, g, b, a or 1) end }
  p.panoplyBox = true
  return p
end
-- 0.5.0 name for a content card (there is no parchment in v3).
Skin.Parchment = Skin.Card

-- Header: crest, Spectral SC title and subtitle, a hairline under the title bar (v3 has no
-- header band texture).
function Skin.Header(f, title, subtitle, icon)
  local rule = f:CreateTexture(nil, "ARTWORK")
  solid(rule, Skin.colors.hairline, 1)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -50)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -50)
  rule:SetHeight(1)
  local crest = f:CreateTexture(nil, "OVERLAY")
  crest:SetSize(30, 30)
  if icon then crest:SetSize(26, 26) Skin.SetIcon(crest, icon, { size = 26 }) else Skin.Logo(crest) end
  crest:SetPoint("TOPLEFT", f, "TOPLEFT", 14, icon and -12 or -10)
  local h = Skin.Heading(f, 16, title)
  h:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -11)
  local sub = Skin.Text(f, 10, Skin.colors.inkSoft)
  sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
  -- measure one line of each (the subtitle is often filled in later), then set the real text
  h:SetText("Ag"); sub:SetText("Ag")
  local th, sh = h:GetStringHeight() or 0, sub:GetStringHeight() or 0
  h:SetText(title or ""); sub:SetText(subtitle or "")
  -- 0.6.0: the hairline sits under the subtitle, never through it (large client fonts push the
  -- subtitle down past the old fixed -50).
  local need = 11 + th + 2 + sh + 2
  local y = -math.max(50, math.ceil(need))
  rule:ClearAllPoints()
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, y)
  f.panoplyHeader, f.panoplyCrest, f.panoplyTitle, f.panoplySubtitle = rule, crest, h, sub
  f.panoplyHeaderBottom = -y
  return h, sub
end

function Skin.Tooltip(owner, title, body)
  owner.tip, owner.tipBody = title, body
  local function show()
    local GT = _G.GameTooltip
    if not GT or not owner.tip then return end
    -- 0.9.5 phase 4L (spec 06a 2.6): an owner may place its tooltip itself (setup puts it beside its window, outside the cards)
    if type(owner.tipAnchor) == "function" then owner.tipAnchor(GT, owner) else GT:SetOwner(owner, "ANCHOR_TOP") end
    GT:SetText(owner.tip, 0.95, 0.84, 0.55, 1, true)
    if owner.tipBody then GT:AddLine(owner.tipBody, 0.9, 0.9, 0.88, true) end
    GT:Show()
  end
  owner.panoplyShowTip = show
  return show
end

-- Fade + short slide in when shown.
function Skin.Animate(f, dy)
  if not f.CreateAnimationGroup then return end
  local ok, ag = pcall(f.CreateAnimationGroup, f)
  if not ok or not ag then return end
  local a = ag:CreateAnimation("Alpha")
  if a then
    if a.SetFromAlpha then a:SetFromAlpha(0) a:SetToAlpha(1) end
    a:SetDuration(0.18)
    if a.SetSmoothing then a:SetSmoothing("OUT") end
  end
  if dy and dy ~= 0 then
    local t = ag:CreateAnimation("Translation")
    if t then t:SetOffset(0, dy * 0.6) t:SetDuration(0.18) if t.SetSmoothing then t:SetSmoothing("OUT") end end
  end
  f.panoplyIntro = ag
  local prev = f:GetScript("OnShow")
  f:SetScript("OnShow", function(self, ...)
    if self.panoplyIntro then self.panoplyIntro:Stop(); self.panoplyIntro:Play() end
    if prev then prev(self, ...) end
  end)
end

-------------------------------------------------------------------------------
-- Controls
-------------------------------------------------------------------------------
local GLYPH_FOR = { x = "Close", ["+"] = "Plus", ["-"] = "Minus" }

-- v3 control states: fill + hairline per state (Skin.colors), no glow.
Skin.BUTTON_STATE = {
  up = { fill = "button", line = "hairline" },
  over = { fill = "buttonHover", line = "goldDark" },
  down = { fill = "buttonDown", line = "goldDark" },
  sel = { fill = "buttonHover", line = "trim" },
  -- a destructive action (Confirm in "Drop unneeded quests?")
  danger_up = { fill = "danger", line = "warn" },
  danger_over = { fill = "dangerHover", line = "warn" },
  danger_down = { fill = "buttonDown", line = "warn" },
  danger_sel = { fill = "dangerHover", line = "warn" },
}
local function paintBox(bg, rim, st)
  local S = Skin.BUTTON_STATE[st] or Skin.BUTTON_STATE.up
  local f, l = Skin.colors[S.fill], Skin.colors[S.line]
  bg:SetVertexColor(f[1], f[2], f[3], 1)
  if rim then rim:SetVertexColor(l[1], l[2], l[3], 1) end
end
Skin.PaintBox = paintBox

-- Slate button with a hairline; hover brightens the fill and warms the line to brass, pressed
-- darkens it and sinks the label 1 px. Label: Lato SemiBold.
function Skin.Button(parent, label, w, h, onClick, tip, tipBody)
  local b = CreateFrame("Button", nil, parent)
  w, h = w or 96, h or 26
  b:SetSize(w, h)
  b.panoplyBox = true
  local bg, rim = Skin.Box(b, "S", { fill = Skin.colors.button, fillA = 1, line = Skin.colors.hairline, layer = "BORDER", lineLayer = "BORDER" })
  b.bg, b.rim = bg, rim
  local function paint(st) b.panoplyState = st paintBox(bg, rim, b.panoplyDanger and ("danger_" .. st) or st) end
  b.Paint = function(_, st) paint(st) end
  paint("up")
  local fs = Skin.Text(b, h >= 30 and 13 or 12, nil, nil, "semi")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(label or "")
  b.label = fs
  Skin.Tooltip(b, tip or label, tipBody)
  b:SetScript("OnEnter", function()
    if b.disabled then return end
    paint(b.selected and "sel" or "over")
    if b.icon and b.icon.panoplyJ then Skin.TintIcon(b.icon, Skin.colors.iconActive) end
    if b.panoplyShowTip then b.panoplyShowTip() end
  end)
  b:SetScript("OnLeave", function()
    paint(b.selected and "sel" or "up")
    if b.icon and b.icon.panoplyJ then Skin.TintIcon(b.icon, b.panoplyIconTint or Skin.colors.icon) end
    if _G.GameTooltip then GameTooltip:Hide() end
  end)
  b:SetScript("OnMouseDown", function()
    if b.disabled then return end
    paint("down")
    fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", b.panoplyLabelX or 0, -1)
    if b.icon then b.icon:ClearAllPoints(); b.icon:SetPoint(b.panoplyIconPoint or "CENTER", b, b.panoplyIconPoint or "CENTER", b.panoplyIconX or 0, -1) end
    b.pressed = true
  end)
  b:SetScript("OnMouseUp", function()
    paint(b.selected and "sel" or (b:IsMouseOver() and "over" or "up"))
    fs:ClearAllPoints(); fs:SetPoint("CENTER", b, "CENTER", b.panoplyLabelX or 0, 0)
    if b.icon then b.icon:ClearAllPoints(); b.icon:SetPoint(b.panoplyIconPoint or "CENTER", b, b.panoplyIconPoint or "CENTER", b.panoplyIconX or 0, 0) end
    b.pressed = nil
  end)
  if onClick then b:SetScript("OnClick", function(self, button) if not self.disabled then onClick(self, button) end end) end
  function b:SetEnabledLook(on)
    self.disabled = not on
    local c = on and Skin.colors.text or Skin.colors.dim
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    self.bg:SetAlpha(on and 1 or 0.6)
    if self.rim then self.rim:SetAlpha(on and 1 or 0.6) end
    if self.icon then self.icon:SetAlpha(on and 1 or 0.45) end
  end
  -- 0.6.1: a toggle's "off" look (a hidden bag, a hidden list). Dimmed with a slash across the icon
  -- but STILL CLICKABLE: SetEnabledLook(false) is for actions that cannot run now and ignores
  -- clicks, so a toggle that used it switched itself off for good (our bags: "0 of 0 slots free").
  function b:SetDimmed(on)
    self.dimmed = on and true or nil
    if self.disabled then self:SetEnabledLook(true) end   -- a toggle is never disabled by its own state
    local c = on and Skin.colors.dim or Skin.colors.text
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    self.bg:SetAlpha(on and 0.75 or 1)
    if self.icon then self.icon:SetAlpha(on and 0.4 or 1) end
    if on and not self.panoplySlash and self.CreateLine then
      local ln = self:CreateLine(nil, "OVERLAY")
      local k = Skin.colors.gold or Skin.colors.accent or { 0.8, 0.65, 0.35 }
      ln:SetColorTexture(k[1], k[2], k[3], 0.95)
      local w, hh = self:GetWidth() or 28, self:GetHeight() or 28
      ln:SetStartPoint("TOPRIGHT", self, -math.floor(w * 0.22), -math.floor(hh * 0.22))
      ln:SetEndPoint("BOTTOMLEFT", self, math.floor(w * 0.22), math.floor(hh * 0.22))
      ln:SetThickness(2)
      self.panoplySlash = ln
    end
    if self.panoplySlash then if on then self.panoplySlash:Show() else self.panoplySlash:Hide() end end
  end
  function b:SetSelected(on)
    self.selected = on and true or nil
    paint(on and "sel" or "up")
  end
  -- Optional glyph left of the label (or centred when there is no label).
  function b:SetIcon(name, size)
    if not name then if self.icon then self.icon:Hide() end return end
    if not self.icon then self.icon = self:CreateTexture(nil, "ARTWORK") end
    local s = size or math.min(h - 6, 22)
    self.icon:SetSize(s, s)
    Skin.SetGlyph(self.icon, name, { size = s }); self.icon:Show()
    self.iconName = name
    self.icon:ClearAllPoints()
    if (self.label:GetText() or "") == "" then
      self.panoplyIconPoint, self.panoplyIconX, self.panoplyLabelX = "CENTER", 0, 0
      self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
    else
      self.panoplyIconPoint, self.panoplyIconX, self.panoplyLabelX = "LEFT", 8, s / 2 + 2
      self.icon:SetPoint("LEFT", self, "LEFT", 8, 0)
      self.label:ClearAllPoints(); self.label:SetPoint("CENTER", self, "CENTER", s / 2 + 2, 0)
    end
  end
  Skin.buttons[#Skin.buttons + 1] = b
  return b
end

-- Square icon button on our slate icon-button backing. label "x" / "+" / "-" or a glyph name.
function Skin.IconButton(parent, label, size, onClick, tip, tipBody)
  size = size or 22
  local glyph = GLYPH_FOR[label or ""] or (label and label ~= "" and #label > 1 and label) or nil
  local b = Skin.Button(parent, glyph and "" or label, size, size, onClick, tip, tipBody)
  -- the backing drawing is 24 of its 32 UI px: scale the texture so the drawn square is the button
  b.bg:Hide(); if b.rim then b.rim:Hide() end
  local back = b:CreateTexture(nil, "BORDER")
  back:SetTexture(Skin.TEX.IconButton)
  back:SetSize(size * 32 / 23, size * 32 / 23); back:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.back = back
  b.Paint = function(self, st)
    self.panoplyState = st
    back:SetAlpha(st == "down" and 0.75 or 1)
    if back.SetVertexColor then local k = st == "over" and 1 or (st == "down" and 0.85 or 0.92) back:SetVertexColor(k, k, k, 1) end
  end
  b:Paint("up")
  local pe, pl, pd, pu = b:GetScript("OnEnter"), b:GetScript("OnLeave"), b:GetScript("OnMouseDown"), b:GetScript("OnMouseUp")
  b:SetScript("OnEnter", function(self) if pe then pe(self) end if not self.disabled then self:Paint("over") end end)
  b:SetScript("OnLeave", function(self) if pl then pl(self) end self:Paint("up") end)
  b:SetScript("OnMouseDown", function(self) if pd then pd(self) end if not self.disabled then self:Paint("down") end end)
  b:SetScript("OnMouseUp", function(self) if pu then pu(self) end self:Paint(self:IsMouseOver() and "over" or "up") end)
  if glyph then b:SetIcon(glyph, math.floor(size * 0.66)) end
  return b
end

-- Tab: three clear states, each with a fill and a full hairline rim. Idle: dark fill, muted
-- text, idle-brass icon. Hover: lighter. Selected: the raised fill, brass line, a cerulean bar
-- inside the bottom edge, heading-gold text and active-brass icon. Label: Lato SemiBold.
Skin.TAB_STATE = {
  idle = { fill = "tabFillIdle", line = "hairline", text = "tabIdle", icon = "iconIdle" },
  hover = { fill = "tabFillHover", line = "slotLine", text = "tabHover", icon = "icon" },
  sel = { fill = "tabFillSel", line = "goldDark", text = "tabSel", icon = "iconActive" },
}
function Skin.Tab(parent, label, w, onClick, tip, tipBody, icon, own)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 110, 30)
  b.panoplyBox = true
  local bg, rim = Skin.Box(b, "S", { fill = Skin.colors.tabFillIdle, fillA = 1, line = Skin.colors.hairline })
  b.bg, b.rim = bg, rim
  -- kept for older callers (always clear)
  local hl = b:CreateTexture(nil, "BORDER"); hl:SetAllPoints(b); solid(hl, Skin.colors.tabFillHover, 0); hl:SetAlpha(0)
  b.hl = hl
  local bar = b:CreateTexture(nil, "ARTWORK")
  Skin.Round(bar, 1, Skin.TEX.RFill)
  bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 2); bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 2); bar:SetHeight(2)
  bar:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], 1)
  b.accent = bar
  local fs = Skin.Text(b, 12, Skin.colors.tabIdle, nil, "semi")
  fs:SetPoint("CENTER", b, "CENTER", icon and 10 or 0, 0)
  if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(label)
  b.label = fs
  if icon then
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 16); Skin.SetIcon(t, icon, { size = 16, own = own and true or nil })
    t:SetPoint("RIGHT", fs, "LEFT", -6, 0)
    b.icon = t
  end
  Skin.Tooltip(b, tip or label, tipBody)
  function b:Paint()
    local st = self.active and "sel" or (self.hover and "hover" or "idle")
    self.state = st
    local S = Skin.TAB_STATE[st]
    local f, l, c = Skin.colors[S.fill], Skin.colors[S.line], Skin.colors[S.text]
    self.bg:SetVertexColor(f[1], f[2], f[3], 1)
    self.rim:SetVertexColor(l[1], l[2], l[3], 1)
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    if st == "sel" then self.accent:Show() else self.accent:Hide() end
    if self.icon then
      Skin.TintIcon(self.icon, Skin.colors[S.icon])
      -- a game icon (WoW style) shows its own colours, dimmed when idle
      self.icon:SetAlpha(self.icon.panoplyJ and 1 or (st == "sel" and 1 or (st == "hover" and 0.9 or 0.7)))
    end
    self.hl:SetAlpha(0)
  end
  function b:SetActive(on) self.active = on and true or false self:Paint() end
  -- the width that fits the icon + label with padding
  function b:NeedWidth() return math.ceil(Skin.TextWidth(self.label) + (self.icon and 22 or 0) + 2 * Skin.SP.l) end
  b:SetScript("OnEnter", function() b.hover = true b:Paint() if b.panoplyShowTip then b.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() b.hover = false b:Paint() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function() if onClick then onClick(b) end end)
  b:SetActive(false)
  -- (an icon style switch keeps the tint: applyJ re-reads tex.panoplyTint)
  Skin.buttons[#Skin.buttons + 1] = b
  return b
end

-- Checkbox bound to Panoply.db[key] (or a getter/setter pair), with tooltip.
function Skin.Check(parent, label, key, onChange, tip, ink)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  -- v3: an inset slate square with a slot-coloured line (Skin.colors.slotBottom / slotLine)
  local box, rim = Skin.Box(b, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine })
  b.box, b.rim = box, rim
  local mark = b:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 3)
  mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
  Skin.SetMark(mark, "Check")
  b.mark = mark
  local fs = ink and Skin.Ink(parent, 12) or Skin.Text(parent, 12)
  fs:SetPoint("LEFT", b, "RIGHT", 9, 0)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetText(label)
  b.label = fs
  -- 0.5.5: the label is part of the click target
  -- Returns the width and height the box + label take. A label wider than maxW wraps.
  function b:FitLabel(maxW)
    local w, h = Skin.TextWidth(fs), 18
    if maxW and w > maxW then
      if fs.SetWordWrap then fs:SetWordWrap(true) end
      fs:SetWidth(maxW) w = maxW
      h = math.max(18, Skin.TextHeight(fs, maxW))
      -- a wrapped label hangs from the top of the box instead of centring on it
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", b, "TOPRIGHT", 9, 0)
      if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    end
    if b.SetHitRectInsets then b:SetHitRectInsets(0, -(w + 9), 0, 0) end
    return 18 + 9 + w, h
  end
  b:FitLabel()
  Skin.Tooltip(b, label, tip)
  local get = type(key) == "table" and key.get or function() return Panoply.db and Panoply.db[key] end
  local set = type(key) == "table" and key.set or function(v) Panoply:SetOption(key, v) end
  function b:Refresh()
    if get() then mark:Show() else mark:Hide() end
    -- 0.5.6: a sub-option is dimmed while the option it belongs to is off
    if self.panoplyParentKey and Panoply.db then
      local a = Panoply.db[self.panoplyParentKey] and 1 or 0.45
      self:SetAlpha(a) fs:SetAlpha(a)
    end
  end
  local function line(c) rim:SetVertexColor(c[1], c[2], c[3], 1) end
  b:SetScript("OnEnter", function() line(Skin.colors.goldDark) if b.panoplyShowTip then b.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() line(Skin.colors.slotLine) if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function()
    set(not get())
    b:Refresh()
    if get() and mark.SetAlpha then mark:SetAlpha(0); Skin.FadeTo(mark, 1, 0.12) end
    if onChange then onChange(get()) end
  end)
  b:Refresh()
  Skin.buttons[#Skin.buttons + 1] = b
  return b
end

-- Progress bar (v3): a flat slate track and a flat pill fill, cerulean for the route and warm
-- gold for experience. No sheen, no glow.
-- 0.6.0: the label is never drawn on the bar (it used to sit centred on the track and crossed the
-- fill's edge). It sits ABOVE the bar, left-aligned, in plain text colour; a caller keeps
-- Skin.BarLabelSpace(bar) free above the bar (0 when the bar has no label).
Skin.BAR_LABEL_GAP = 3
Skin.BAR_LABEL_SIZE = 10
local function tint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end
function Skin.Bar(parent, h, gold)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(h or 8)
  h = h or 8
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(bar); Skin.Round(bg, h / 2, Skin.TEX.RFill)
  tint(bg, Skin.colors.slotBottom)
  bg.panoplyBarTrack = true
  local fill = bar:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
  fill:SetWidth(h - 2)
  Skin.Round(fill, (h - 2) / 2, Skin.TEX.RFill)
  tint(fill, gold and Skin.colors.progress or Skin.colors.accentDark)
  fill.panoplyBarFill = true
  bg.panoplyBarFillTex = fill
  bar.pill = h - 2
  local text = Skin.Text(bar, Skin.BAR_LABEL_SIZE, Skin.colors.text, nil, "semi")
  text:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, Skin.BAR_LABEL_GAP)
  if text.SetJustifyH then text:SetJustifyH("LEFT") end
  bar.bg, bar.fill, bar.text = bg, fill, text
  bar.panoplyValue = 0
  local function width(self) local w = self:GetWidth() or 0 if w <= 0 then w = self.panoplyWidth or 200 end return w - 2 end
  local function place(self, p)
    self.panoplyValue = p
    -- a pill never gets narrower than its own height; nothing at all at 0%
    local w = math.max(self.pill or 1, width(self) * p)
    self.fill:SetWidth(w)
    if p <= 0 then self.fill:Hide() else self.fill:Show() end
  end
  function bar:SetProgress(p, label)
    p = math.max(0, math.min(1, p or 0))
    local from = self.panoplyValue or 0
    self.progress = p
    self.text:SetText(label or "")
    if (label or "") == "" then self.text:Hide() else self.text:Show() end
    -- 0.5.5: the label is held to the bar's width (one line), so a long one can be caught and fixed
    local bw = self.panoplyWidth or (self.GetWidth and self:GetWidth()) or 0
    if bw > 20 then self.text:SetWidth(bw); if self.text.SetWordWrap then self.text:SetWordWrap(false) end end
    if self:IsVisible() and math.abs(p - from) > 0.001 and from > 0 then
      Skin.Tween(self, from, p, 0.35, place)
    else
      place(self, p)
    end
  end
  return bar
end
-- Height to keep free above a bar for its label (0 with no label).
function Skin.BarLabelSpace(bar)
  if not bar or (bar.text:GetText() or "") == "" then return 0 end
  return Skin.TextHeight(bar.text) + Skin.BAR_LABEL_GAP
end

-- Slider: slate track, cerulean fill, brass knob. fmt: "%d%%" (0..1 values) or a format.
function Skin.Slider(parent, label, minV, maxV, step, get, set, tip, fmt)
  local s = CreateFrame("Slider", nil, parent)
  s:SetSize(200, 16)
  s:EnableMouse(true)     -- 0.7.3.7: said out loud, so the track can be clicked and the knob dragged on every client
  if s.SetOrientation then s:SetOrientation("HORIZONTAL") end
  if s.SetMinMaxValues then s:SetMinMaxValues(minV, maxV) end
  if s.SetValueStep then s:SetValueStep(step) end
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", s, "LEFT", 0, 0); track:SetPoint("RIGHT", s, "RIGHT", 0, 0); track:SetHeight(6)
  Skin.Round(track, 3, Skin.TEX.RFill); tint(track, Skin.colors.slotBottom)
  local fill = s:CreateTexture(nil, "BORDER")
  fill:SetPoint("LEFT", s, "LEFT", 1, 0); fill:SetHeight(4); fill:SetWidth(4); Skin.Round(fill, 2, Skin.TEX.RFill)
  tint(fill, Skin.colors.accentDark)
  s.fill = fill
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture(Skin.TEX.CircleMask); thumb:SetSize(14, 14); tint(thumb, Skin.colors.goldBright)
  if s.SetThumbTexture then s:SetThumbTexture(thumb) end
  s.thumb = thumb
  local fs = Skin.Text(parent, 12); fs:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 5)
  s.label = fs
  local function refreshLabel(v)
    if fmt then fs:SetText(("%s: " .. fmt):format(label, v)) else fs:SetText(("%s: %d%%"):format(label, math.floor(v * 100 + 0.5))) end
    local w = s:GetWidth() or 200
    fill:SetWidth(math.max(4, w * (v - minV) / math.max(0.0001, maxV - minV)))
  end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    refreshLabel(v)
    if s.ready and not s.refreshing then set(v) end
  end)
  -- showing the saved value must not save it again: the game rounds the knob to the step, and a value that sits between
  -- two steps (carried over from the old sliders) would otherwise change just because its page was opened
  function s:Refresh()
    local v = get()
    s.refreshing = true
    if self.SetValue then self:SetValue(v) end
    s.refreshing = nil
    refreshLabel(v)
  end
  Skin.Tooltip(s, label, tip)
  s:SetScript("OnEnter", function() tint(thumb, Skin.colors.heading) if s.panoplyShowTip then s.panoplyShowTip() end end)
  s:SetScript("OnLeave", function() tint(thumb, Skin.colors.goldBright) if _G.GameTooltip then GameTooltip:Hide() end end)
  s:Refresh()
  s.ready = true
  s.Set = function(_, v) set(v); s:Refresh() end
  return s
end

-- Text input: the inset card colour with a hairline that turns cerulean while typing.
function Skin.Input(parent, w, h, placeholder)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(w or 160, h or 22)
  if box.SetAutoFocus then box:SetAutoFocus(false) end
  if box.SetFont then pcall(box.SetFont, box, Skin.BODY, 13, "") end
  if box.SetTextInsets then box:SetTextInsets(24, 6, 0, 0) end
  local bg, rim = Skin.Box(box, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  box.bg, box.rim = bg, rim
  local icon = box:CreateTexture(nil, "ARTWORK"); Skin.SetGlyph(icon, "Search"); icon:SetSize(14, 14)
  icon:SetPoint("LEFT", box, "LEFT", 6, 0); icon:SetAlpha(0.8)
  local ph = Skin.Text(box, 12, Skin.colors.dim); ph:SetPoint("LEFT", box, "LEFT", 24, 0); ph:SetText(placeholder or "Search")
  box.placeholder, box.icon = ph, icon
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function() icon:SetAlpha(1) tint(rim, Skin.colors.accentDark) end)
  box:SetScript("OnEditFocusLost", function() icon:SetAlpha(0.8) tint(rim, Skin.colors.hairline) end)
  return box
end

-------------------------------------------------------------------------------
-- Pop-ups (Nov 2026, "none may get stuck open"). Every menu, pop-out and list that opens over something else is taken
-- in here (Popups:Adopt) and then closes the same way everywhere:
--   a click outside it        (GLOBAL_MOUSE_DOWN; on a client without that event the mouse button is watched instead)
--   picking an item           (the pop-up's own rows; rows that are switches or ticks stay open on purpose)
--   its parent closing        (the button it was opened from is no longer on screen: its window closed)
--   Esc, one level at a time  (a pop-up opened from a pop-up closes first, then the one under it, then the window)
-- Opening a pop-up closes any other that it was not opened from, so two unrelated ones are never open together.
--
-- Esc: outside combat the manager takes the Esc key itself while a pop-up is open and closes only the top one. In combat an
-- add-on may not hold keys, so there the game's own Esc is used: the game closes every frame named in UISpecialFrames at once,
-- so only the top-most Panoply Suite frame is kept in that list (the top pop-up, else the window shown last) and the next one
-- is put back a moment after it closes. Windows (Skin.Window) close one at a time the same way, newest first.
-- Nothing here is protected: frames are only shown and hidden; the Esc key is never held in combat.
-------------------------------------------------------------------------------
local Popups = { stack = {}, windows = {}, special = {} }
Skin.Popups = Popups
local function popCombat() return Panoply.Compat and Panoply.Compat.InCombat and Panoply.Compat.InCombat() end
local function isUnder(f, root)
  local n = 0
  while f and n < 60 do
    if f == root then return true end
    f = f.GetParent and f:GetParent() or nil
    n = n + 1
  end
  return false
end
local function later(fn)
  if _G.C_Timer and C_Timer.After then C_Timer.After(0, fn) else fn() end
end

function Popups:Top() return self.stack[#self.stack] end
function Popups:IsOpen(f)
  for _, p in ipairs(self.stack) do if p == f then return true end end
  return false
end
local function dropFrom(list, f)
  for i = #list, 1, -1 do if list[i] == f then table.remove(list, i) end end
end

-- the frame that makes the manager tick while a pop-up is open (parent gone, mouse watch) and holds Esc outside combat
function Popups:Frame()
  local k = self.frame
  if k then return k end
  k = CreateFrame("Frame", "PanoplySuitePopupKeys", UIParent)
  k:SetSize(1, 1); k:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
  k.panoplyLayoutSkip = true
  k:Hide()
  k:SetScript("OnUpdate", function() Popups:Tick() end)
  k:SetScript("OnKeyDown", function(self, key)
    if popCombat() or not self.SetPropagateKeyboardInput then return end
    local top = Popups:Top()
    if key == "ESCAPE" and top then
      -- this key press stays ours: nothing about the keyboard is changed until the handler is over (Popups:Idle waits)
      self:SetPropagateKeyboardInput(false)
      Popups.inKey = true
      local ok, err = pcall(Popups.Close, Popups, top)
      Popups.inKey = nil
      if not ok then Panoply:Debug("popup close", err) end
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  self.frame = k
  return k
end

-- nothing is open any more: the keyboard goes back and the manager stops ticking
function Popups:Idle()
  if #self.stack > 0 or not self.frame then return end
  self:Keys(false)
  self.frame:Hide()
end

-- hold Esc (on) or give the keyboard back (off); never touched in combat
function Popups:Keys(on)
  local k = self:Frame()
  if popCombat() then return end
  if on then
    if k.SetPropagateKeyboardInput then k:SetPropagateKeyboardInput(true) end
    if k.EnableKeyboard then k:EnableKeyboard(true) end
    self.keysOn = true
  elseif self.keysOn then
    if k.SetPropagateKeyboardInput then k:SetPropagateKeyboardInput(true) end
    if k.EnableKeyboard then k:EnableKeyboard(false) end
    self.keysOn = nil
  end
end
-- combat is about to start: the keyboard goes back to the game while that is still allowed
Panoply:On("PLAYER_REGEN_DISABLED", function()
  local k = Popups.frame
  if not (k and Popups.keysOn) then return end
  if k.SetPropagateKeyboardInput then pcall(k.SetPropagateKeyboardInput, k, true) end
  if k.EnableKeyboard then pcall(k.EnableKeyboard, k, false) end
  Popups.keysOn = nil
end)
Panoply:On("PLAYER_REGEN_ENABLED", function() if #Popups.stack > 0 then Popups:Keys(true) end end)

function Popups:Close(f)
  local info = f.panoplyPopup
  if info and info.close then info.close(f) else f:Hide() end
  if f:IsShown() then f:Hide() end
  dropFrom(self.stack, f)
end

function Popups:OwnerOf(f)
  local o = f.panoplyPopup and f.panoplyPopup.owner
  if type(o) == "function" then o = o(f) end
  return o or f.panoplyOwner or f.owner
end

-- Take a frame in as a pop-up. opts.close(f): how it closes (default f:Hide()); opts.owner: the frame it opens from, or a
-- function giving it (default f.panoplyOwner, else f.owner, read each time it opens).
function Popups:Adopt(f, opts)
  if f.panoplyPopup then return f end
  f.panoplyPopup = opts or {}
  if f.HookScript then
    f:HookScript("OnShow", function() Popups:Opened(f) end)
    f:HookScript("OnHide", function() Popups:Closed(f) end)
  end
  local name = f.GetName and f:GetName()
  if name then self.special[name] = "popup" end
  self:SyncSpecials()
  if f:IsShown() then self:Opened(f) end
  return f
end

function Popups:Opened(f)
  local owner = self:OwnerOf(f)
  f.panoplyPopupOwner = owner
  dropFrom(self.stack, f)
  -- every open pop-up this one was not opened from closes
  while #self.stack > 0 do
    local p = self.stack[#self.stack]
    if owner and isUnder(owner, p) then break end
    self:Close(p)
  end
  self.stack[#self.stack + 1] = f
  self.downWas = nil
  self:Frame():Show()
  self:Keys(true)
  self:SyncSpecials()
end

function Popups:Closed(f)
  local at
  for i, p in ipairs(self.stack) do if p == f then at = i end end
  if at then
    -- what was opened from it goes with it
    for i = #self.stack, at + 1, -1 do
      local p = self.stack[i]
      table.remove(self.stack, i)
      if p and p:IsShown() then self:Close(p) end
    end
    dropFrom(self.stack, f)
  end
  if #self.stack == 0 and self.frame then
    if self.inKey then later(function() Popups:Idle() end) else self:Idle() end
  end
  -- the game may be in the middle of closing its Esc list: that list is changed a moment later
  later(function() Popups:SyncSpecials() end)
end

-- a click somewhere: from the top down, every pop-up the pointer is not over closes; the first one it is over stays
function Popups:MouseDown()
  self.clicked = nil
  while #self.stack > 0 do
    local p = self.stack[#self.stack]
    if p.IsMouseOver and p:IsMouseOver() then break end
    local owner = p.panoplyPopupOwner
    if owner and owner.IsMouseOver and (not owner.IsVisible or owner:IsVisible()) and owner:IsMouseOver() then
      -- the click is on the button that opened it: that click must close it, not open it again (Popups:Reopening)
      self.clicked = { f = p, owner = owner, t = (_G.GetTime and GetTime()) or 0 }
    end
    self:Close(p)
  end
end
-- true when this pop-up was just closed by the press of the very click that now asks to open it from the same button
function Popups:Reopening(f, owner)
  local c = self.clicked
  if not c then return false end
  self.clicked = nil
  local now = (_G.GetTime and GetTime()) or 0
  return c.f == f and c.owner == owner and (now - c.t) < 1.5
end
Panoply:On("GLOBAL_MOUSE_DOWN", function() Popups:MouseDown() end)

function Popups:Tick()
  -- the parent closed: the button a pop-up was opened from is not on screen any more
  for i = #self.stack, 1, -1 do
    local p = self.stack[i]
    local owner = p and p.panoplyPopupOwner
    if p and owner and owner.IsVisible and not owner:IsVisible() then self:Close(p) end
  end
  -- a client without the mouse event: watch the buttons
  if Panoply.skippedEvents and Panoply.skippedEvents.GLOBAL_MOUSE_DOWN and _G.IsMouseButtonDown then
    local down = (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and true or false
    if down and self.downWas == false then self:MouseDown() end
    self.downWas = down
  end
end

-- A Panoply Suite frame that Esc closes (in place of adding its name to UISpecialFrames by hand). Windows are remembered in
-- the order they were shown so Esc closes the newest first.
-- first = true: an overlay that always closes before the windows under it (the tour), whenever it was shown.
function Popups:Special(name, first)
  if not name or self.special[name] then return end
  self.special[name] = "window"
  local f = _G[name]
  if f and first then f.panoplyEscFirst = true end
  if f and f.HookScript then
    f:HookScript("OnShow", function() dropFrom(Popups.windows, f); Popups.windows[#Popups.windows + 1] = f; Popups:SyncSpecials() end)
    f:HookScript("OnHide", function() dropFrom(Popups.windows, f); later(function() Popups:SyncSpecials() end) end)
    if f:IsShown() then self.windows[#self.windows + 1] = f end
  end
  self:SyncSpecials()
end

-- UISpecialFrames holds, of our frames, only the one Esc should close next (all of them while none is shown)
function Popups:SyncSpecials()
  local list = _G.UISpecialFrames
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do if self.special[list[i]] then table.remove(list, i) end end
  local top = self:Top()
  for i = #self.windows, 1, -1 do if not self.windows[i]:IsShown() then table.remove(self.windows, i) end end
  local win = self.windows[#self.windows]
  for i = #self.windows, 1, -1 do if self.windows[i].panoplyEscFirst then win = self.windows[i] break end end
  local only = (top and top.GetName and top:GetName()) or (win and win.GetName and win:GetName())
  if top and not only then return end        -- an unnamed pop-up is on top: Esc is the manager's own key
  if only then list[#list + 1] = only return end
  local names = {}
  for name in pairs(self.special) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do list[#list + 1] = name end
end

-- A window opened from another window (a dialog): it closes when that window closes.
function Popups:Child(child, parent)
  if not (child and parent) then return end
  child.panoplyDialogParent = parent
  parent.panoplyDialogKids = parent.panoplyDialogKids or {}
  parent.panoplyDialogKids[child] = true
  if not parent.panoplyDialogHooked and parent.HookScript then
    parent.panoplyDialogHooked = true
    parent:HookScript("OnHide", function(self)
      for kid in pairs(self.panoplyDialogKids) do
        if kid.panoplyDialogParent == self and kid:IsShown() then kid:Hide() end
      end
    end)
  end
end

-- Small popup menu (right-click menus): items { text, func, checked=fn|bool, tip }. Step 2 B adds three more kinds of row:
--   { header = "QUICK SWITCHES" }                              a small heading that cannot be clicked
--   { text, switch = fn() -> bool, func, tip }                  an On / Off switch drawn at the right; a click runs func and the
--                                                               menu STAYS OPEN with the switch redrawn (each one acts at once)
--   { divider = true }                                          a hairline
-- opts.width: the menu's width (default 190). 0.9.7: a row whose words need more room widens the menu (to MENU_MAX_W at most; past
-- that the words end in an ellipsis), so a long name is never drawn over the menu's edge or under a switch.
-- 0.9.7: the frame and its first MENU_ROWS rows (each with its On / Off switch) are built when this file loads, so opening a menu
-- creates nothing, in a fight or out of one. A longer menu makes its extra rows only out of combat; in a fight it shows the rows
-- it has.
local MENU_ROWS = 24
Skin.MENU_ROWS = MENU_ROWS
local MENU_MAX_W = 440
Skin.MENU_MAX_W = MENU_MAX_W
-- (Skin.Switch is UI/Controls.lua's, loaded after this file: the rows built here get their switch when UI/Menu.lua, loaded after
-- both, calls Skin.BuildMenu() again)
local function menuSwitch(r)
  if r.sw or not Skin.Switch then return r.sw end
  r.sw = Skin.Switch(r, nil)
  r.sw:EnableMouse(false)       -- the whole row is the click target
  r.sw:Hide()
  return r.sw
end
local function menuRow(m, i)
  local r = CreateFrame("Button", nil, m)
  r:SetHeight(22)
  r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(r); Skin.Round(r.hl, Skin.RADIUS.row, Skin.TEX.RFill)
  r.hl:SetVertexColor(Skin.colors.accent[1], Skin.colors.accent[2], Skin.colors.accent[3], Skin.ALPHA.rowHighlight); r.hl:Hide()
  r.mark = r:CreateTexture(nil, "ARTWORK"); Skin.SetMark(r.mark, "Check"); r.mark:SetSize(14, 14); r.mark:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.text = Skin.Text(r, 12); r.text:SetPoint("LEFT", r, "LEFT", 26, 0)
  r.head = Skin.Label(r, 10, Skin.colors.inkSoft); r.head:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.rule = r:CreateTexture(nil, "ARTWORK"); Skin.Solid(r.rule, Skin.colors.hairline, 1); r.rule:SetHeight(1)
  r.rule:SetPoint("LEFT", r, "LEFT", 6, 0); r.rule:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  menuSwitch(r)
  r:SetScript("OnEnter", function(self) if not (self.item and (self.item.header or self.item.divider)) then self.hl:Show() end if self.panoplyShowTip then self.panoplyShowTip() end end)
  r:SetScript("OnLeave", function(self) self.hl:Hide() if _G.GameTooltip then GameTooltip:Hide() end end)
  r:Hide()
  m.rows[i] = r
  return r
end
local function menuFrame()
  local m = Skin.menu
  if m then
    if not m.panoplySwitches and Skin.Switch then
      for _, r in ipairs(m.rows) do menuSwitch(r) end
      m.panoplySwitches = true
    end
    return m
  end
  m = CreateFrame("Frame", "PanoplySuitePopupMenu", UIParent)
  m:SetFrameStrata("FULLSCREEN_DIALOG")
  Skin.Panel(m, 1, nil, "M")
  m.rows = {}
  m:EnableMouse(true)
  m:Hide()
  Skin.menu = m
  Popups:Adopt(m)
  Popups:Frame()        -- the pop-up manager's own key frame: made now too, not when the first pop-up opens
  for i = 1, MENU_ROWS do menuRow(m, i) end
  m.panoplySwitches = Skin.Switch and true or nil
  return m
end
Skin.BuildMenu = menuFrame
menuFrame()

function Skin.Menu(owner, items, opts)
  local m = menuFrame()
  -- the press of this very click already closed this menu (it was open from the same button): leave it closed
  if Popups:Reopening(m, owner) then return m end
  -- open for another button: it closes there first, so it is taken in again for the new one
  if m:IsShown() then m:Hide() end
  -- 0.9.5 phase 4L (spec 06a 2.1): a menu opened from a window on the same layer (setup) draws above it, never under its border
  m:SetFrameStrata((opts and opts.strata) or "FULLSCREEN_DIALOG")
  for _, r in ipairs(m.rows) do r:Hide() end
  local y, w = -10, (opts and opts.width) or 190
  local need = 0
  local fight = _G.InCombatLockdown and InCombatLockdown() and true or false
  for i, it in ipairs(items) do
    local r = m.rows[i]
    if not r then
      if fight then break end
      r = menuRow(m, i)
    end
    r.item = it
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", m, "TOPLEFT", 6, y); r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -6, y)
    r.mark:Hide(); r.text:Hide(); r.head:Hide(); r.rule:Hide()
    if r.sw then r.sw:Hide() end
    r.panoplyRoom = nil
    local h = 22
    if it.header then
      h = 20
      r.head:SetText(it.header); r.head:Show()
      need = math.max(need, Skin.TextWidth(r.head) + 24)
      r.tip, r.tipBody, r.panoplyShowTip = nil, nil, nil     -- a row used as a text row before must not show its old tooltip
      r:SetScript("OnClick", nil)
    elseif it.divider then
      h = 10
      r.rule:ClearAllPoints(); r.rule:SetPoint("LEFT", r, "LEFT", 6, 0); r.rule:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.rule:Show()
      r.tip, r.tipBody, r.panoplyShowTip = nil, nil, nil
      r:SetScript("OnClick", nil)
    else
      r.text.panoplyFullText, r.text.panoplyCut = nil, nil
      r.text:SetText(it.text); r.text:Show()
      -- what the row takes beside its words: the menu's inset each side (6 + 6), the tick's column (26) or the switch, the right edge
      r.panoplyRoom = 12 + 26 + 6
      local checked = it.checked
      if type(checked) == "function" then checked = checked() end
      if it.switch then
        h = 28
        r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
        if not fight then menuSwitch(r) end
        if r.sw then
          r.sw:ClearAllPoints(); r.sw:SetPoint("RIGHT", r, "RIGHT", -6, 0)
          r.sw:SetState(it.switch() and true or false)
          r.sw:Show()
        end
        r.panoplyRoom = 12 + 8 + Skin.SP.m + ((r.sw and r.sw:GetWidth()) or 40) + 6
        r.mark:Hide()
      else
        r.text:ClearAllPoints(); r.text:SetPoint("LEFT", r, "LEFT", 26, 0)
        if checked then r.mark:Show() else r.mark:Hide() end
      end
      need = math.max(need, math.ceil(Skin.TextWidth(r.text)) + r.panoplyRoom)
      Skin.Tooltip(r, it.text, it.tip)
      r:SetScript("OnClick", function(self)
        local item = self.item
        if item.switch then
          if item.func then item.func() end
          if self.sw then self.sw:SetState(item.switch() and true or false) end
          return
        end
        m:Hide()
        if item.func then item.func() end
      end)
    end
    r:SetHeight(h)
    r:Show()
    y = y - h
  end
  if need > w then
    w = math.min(need, math.max(w, MENU_MAX_W))
    for _, r in ipairs(m.rows) do
      if r:IsShown() and r.panoplyRoom and r.text:IsShown() then Skin.Ellipsize(r.text, r.item.text, w - r.panoplyRoom) end
    end
  end
  m:SetSize(w, -y + 10)
  m:ClearAllPoints()
  if m.SetClampedToScreen then m:SetClampedToScreen(true) end
  if owner then
    -- under the owner, its left edges together; when that would run off the screen (the minimap button is near the right edge) the
    -- menu hangs from the owner's right edge instead, and above it when there is no room below
    local flipX, flipY
    local ui = _G.UIParent
    if owner.GetLeft and ui and ui.GetWidth then
      local ol, ob = owner:GetLeft(), owner:GetBottom()
      local es = ((owner.GetEffectiveScale and owner:GetEffectiveScale()) or 1) / ((ui.GetEffectiveScale and ui:GetEffectiveScale()) or 1)
      local sw = ui:GetWidth()
      if ol and type(sw) == "number" and sw > 0 and ol * es + w > sw then flipX = true end
      if ob and ob * es - 4 - (-y + 10) < 0 then flipY = true end
    end
    m:SetPoint((flipY and "BOTTOM" or "TOP") .. (flipX and "RIGHT" or "LEFT"), owner, (flipY and "TOP" or "BOTTOM") .. (flipX and "RIGHT" or "LEFT"), 0, flipY and 4 or -4)
  else m:SetPoint("CENTER", UIParent, "CENTER") end
  m.items = items
  m.panoplyOwner = owner
  m:Show()
  return m
end

-- Resize grip in a frame's bottom-right corner. onDone(w, h) after a drag.
function Skin.ResizeGrip(f, onDone, onSizing)
  local g = CreateFrame("Button", nil, f)
  g:SetSize(16, 16)
  g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)   -- v3: clear of the brass corner cap
  local t = g:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(g); t:SetTexture(Skin.TEX.ResizeGrip); t:SetAlpha(0.7)
  g.tex = t
  if f.SetResizable then f:SetResizable(true) end
  g:SetScript("OnEnter", function() t:SetAlpha(1) end)
  g:SetScript("OnLeave", function() t:SetAlpha(0.7) end)
  g:SetScript("OnMouseDown", function() if f.StartSizing then f.panoplySizing = true f:StartSizing("BOTTOMRIGHT") end end)
  g:SetScript("OnMouseUp", function()
    if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    f.panoplySizing = nil
    if onDone then onDone(f:GetWidth(), f:GetHeight()) end
  end)
  if onSizing and f.HookScript then f:HookScript("OnSizeChanged", function(_, w, h) onSizing(w, h) end) end
  f.panoplyGrip = g
  return g
end

-------------------------------------------------------------------------------
-- Resizable windows (Nov 2026, "every Panoply window resizes freely in both directions ... keeps a working resize grip and
-- remembers its size"). Skin.Resizable(f, opts) gives a window the grip in its bottom-right corner, its limits and a remembered
-- size, and tells the window's own layout the new size while the grip is dragged and when it is let go:
--   opts.key            the name the size is remembered under (Panoply.db.winSize[key] = { w, h }, for the account)
--   opts.minW, minH     the smallest it goes (a sensible minimum: below it the window's content scrolls, it does not clip)
--                       (minW may be a function giving it now: a window whose least width depends on what it shows)
--   opts.maxW, maxH     the largest (default: the screen)
--   opts.onSize(w, h, done)   lay the content out for this size; done = true when the grip was let go (and on restore / reset)
--   opts.combat = false  a window that holds protected buttons (bags): not resized in combat
-- f:panoplyRestoreSize() puts the remembered size on (called by itself the first time the window shows), f:panoplyResetSize() forgets it.
-- A locked window (opts.locked() -> true) hides the grip.
-------------------------------------------------------------------------------
Skin.RESIZE_TICK = 0.03      -- seconds between two layouts while the grip is dragged
function Skin.Resizable(f, opts)
  if f.panoplyResize then return f.panoplyGrip end
  opts = opts or {}
  f.panoplyResize = opts
  local C = Panoply.Compat
  -- opts.minW may be a function (0.9.5: the main window's least width follows the page that is showing)
  local minW0, minH = opts.minW or 200, opts.minH or 120
  local minW = type(minW0) == "function" and (minW0() or 200) or minW0
  local function limits()
    if type(minW0) == "function" then minW = minW0() or 200 end
    local maxW, maxH = opts.maxW, opts.maxH
    local sw, sh
    if Panoply.Windows then sw, sh = Panoply.Windows:ScreenSize() end
    local sc = (f.GetScale and f:GetScale()) or 1
    if type(sc) ~= "number" or sc <= 0 then sc = 1 end
    if sw then
      maxW = math.min(maxW or 1e6, math.floor(sw / sc))
      maxH = math.min(maxH or 1e6, math.floor(sh / sc))
    end
    maxW, maxH = math.max(minW, maxW or 4000), math.max(minH, maxH or 3000)
    return maxW, maxH
  end
  local function clamp(w, h)
    local maxW, maxH = limits()
    return math.max(minW, math.min(maxW, math.floor((w or minW) + 0.5))), math.max(minH, math.min(maxH, math.floor((h or minH) + 0.5)))
  end
  local function saved()
    local t = Panoply.db and opts.key and Panoply.db.winSize and Panoply.db.winSize[opts.key]
    if type(t) == "table" and type(t.w) == "number" and type(t.h) == "number" then return t.w, t.h end
    return nil
  end
  local function tell(done)
    if not opts.onSize then return end
    local w, h = clamp(f:GetWidth(), f:GetHeight())
    local ok, err = pcall(opts.onSize, w, h, done and true or false)
    if not ok then Panoply:Debug("resize " .. tostring(opts.key), err) end
  end
  local function setBounds()
    local maxW, maxH = limits()
    if C and C.SetResizeBounds then C.SetResizeBounds(f, minW, minH, maxW, maxH) end
  end
  setBounds()
  local last = 0
  local grip = Skin.ResizeGrip(f, function(w, h)
    w, h = clamp(w, h)
    if f:GetWidth() ~= w or f:GetHeight() ~= h then f:SetSize(w, h) end
    if Panoply.db and opts.key then
      Panoply.db.winSize = Panoply.db.winSize or {}
      Panoply.db.winSize[opts.key] = { w = w, h = h }
    end
    tell(true)
  end, function()
    if not f.panoplySizing then return end
    local now = (_G.GetTime and GetTime()) or 0
    if now - last < Skin.RESIZE_TICK then return end
    last = now
    tell(false)
  end)
  -- the grip does nothing in combat on a window that holds protected buttons
  if opts.combat == false then
    local down = grip:GetScript("OnMouseDown")
    grip:SetScript("OnMouseDown", function(...)
      if C and C.InCombat and C.InCombat() then return end
      setBounds()
      return down(...)
    end)
  else
    local down = grip:GetScript("OnMouseDown")
    grip:SetScript("OnMouseDown", function(...) setBounds() return down(...) end)
  end
  Skin.Tooltip(grip, "Resize", "Drag to make this window bigger or smaller. Its size is remembered.")
  local ge, gl = grip:GetScript("OnEnter"), grip:GetScript("OnLeave")
  grip:SetScript("OnEnter", function(self) if ge then ge(self) end if self.panoplyShowTip then self.panoplyShowTip() end end)
  grip:SetScript("OnLeave", function(self) if gl then gl(self) end if _G.GameTooltip then GameTooltip:Hide() end end)
  f.panoplyNaturalW, f.panoplyNaturalH = opts.w0 or f:GetWidth(), opts.h0 or f:GetHeight()
  function f:panoplyRestoreSize()
    local w, h = saved()
    if not w then return false end
    if opts.combat == false and C and C.InCombat and C.InCombat() then return false end
    w, h = clamp(w, h)
    self:SetSize(w, h)
    tell(true)
    return true
  end
  function f:panoplyResetSize()
    if Panoply.db and opts.key and Panoply.db.winSize then Panoply.db.winSize[opts.key] = nil end
    if opts.combat == false and C and C.InCombat and C.InCombat() then return false end
    self:SetSize(self.panoplyNaturalW, self.panoplyNaturalH)
    tell(true)
    return true
  end
  function f:panoplyUserSize() return saved() end
  local restored = false
  local function onShow()
    if opts.locked then if opts.locked() then grip:Hide() else grip:Show() end end
    if restored then return end
    restored = true
    f:panoplyRestoreSize()
  end
  if f.HookScript then f:HookScript("OnShow", onShow) end
  if f:IsShown() then onShow() end
  return grip
end

-------------------------------------------------------------------------------
-- 0.7.3.7 ("Fix every size slider"): "Window size" (40% to 200%) reaches every Panoply Suite window that is a window of its
-- own, live: the guide window, the one-window menu, the profession tracker and every window made by Skin.Window. Windows
-- that sit beside or inside the game's own panels (the profession window, the auction host, the trainer panel and the
-- talent hints) and the quest tracker (it has its own text size and places its item buttons in screen pixels) are left alone.
-- A window is never made bigger than the screen: the scale it gets is the setting, held to the largest that fits. A window
-- is kept on screen (SetClampedToScreen); when it is rescaled the corner it hangs from stays where it was.
-------------------------------------------------------------------------------
local Windows = { list = {} }
Panoply.Windows = Windows
-- The size of the screen in UI units, or nil when the game cannot say (no cap then).
function Windows:ScreenSize()
  local ui = _G.UIParent
  local w, h = ui and ui.GetWidth and ui:GetWidth(), ui and ui.GetHeight and ui:GetHeight()
  if type(w) ~= "number" or type(h) ~= "number" or w < 300 or h < 300 then return nil end
  return w, h
end
-- The scale a window gets now: the setting, but over 100% never more than what lets the whole window show.
function Windows:ScaleFor(f)
  local want = Panoply.Look.WindowScale()
  if want <= 1 then return want end
  local sw, sh = self:ScreenSize()
  local w, h = f:GetWidth(), f:GetHeight()
  if sw and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
    want = math.max(1, math.min(want, sw / w, sh / h))
  end
  return want
end
-- Scale one window. Returns true when it changed. `save` (kept on the window) is called after a change so a place the window
-- saved in the old scale is saved again in the new one. shrinkOnly: the window grew while it was open; it may get smaller to
-- keep fitting the screen but never bigger again until it is opened or the setting is touched (a window whose text grows and
-- shrinks must not breathe).
-- In combat nothing is scaled, moved or clamped (the bag and bank windows hold item buttons the game may treat as protected):
-- the change waits and is made when combat ends (PLAYER_REGEN_ENABLED, below).
local function inCombat() return Panoply.Compat and Panoply.Compat.InCombat and Panoply.Compat.InCombat() end
function Windows:Apply(f, shrinkOnly)
  local info = f.panoplyWindow
  if not info or info.skip then return false end
  if inCombat() then self.waiting = true return false end
  local s = self:ScaleFor(f)
  local old = f:GetScale() or 1
  if math.abs(old - s) < 0.0001 or (shrinkOnly and s > old) then return false end
  if f.GetNumPoints and f:GetNumPoints() == 1 and f.GetPoint then
    local p, rel, rp, x, y = f:GetPoint(1)
    if p and (rel == nil or rel == _G.UIParent) then
      f:SetScale(s)
      f:ClearAllPoints()
      f:SetPoint(p, rel or _G.UIParent, rp or p, (x or 0) * old / s, (y or 0) * old / s)
    else f:SetScale(s) end
  else f:SetScale(s) end
  if info.save then local ok, err = pcall(info.save, f) if not ok then Panoply:Debug("window save", err) end end
  return true
end
function Windows:ApplyAll()
  local n = 0
  for _, f in ipairs(self.list) do if self:Apply(f) then n = n + 1 end end
  return n
end
-- A place a window saved ({ p, rp, x, y, s }): offsets are in the scale the window had when it was saved (s). Where the window is
-- now (maybe at another scale, or not yet at its final one), the same spot on screen is the offsets times s / now.
function Windows:Place(f)
  local p, _, rp, x, y = f:GetPoint(1)
  return { p = p, rp = rp, x = x, y = y, s = f:GetScale() or 1 }
end
function Windows:Offsets(f, place)
  local k = (place.s or (f:GetScale() or 1)) / (f:GetScale() or 1)
  return (place.x or 0) * k, (place.y or 0) * k
end
-- Take a window into the family. opts.save: called after the window was rescaled.
function Windows:Register(f, opts)
  if f.panoplyWindow then return f end
  f.panoplyWindow = opts or {}
  self.list[#self.list + 1] = f
  if f.HookScript then
    f:HookScript("OnSizeChanged", function() Windows:Apply(f, true) end)
    f:HookScript("OnShow", function() Windows:Apply(f) end)
  end
  if inCombat() then self.waiting = true else
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:SetScale(self:ScaleFor(f))       -- no re-anchoring here: a saved place is put on with Windows:Offsets, at whatever scale the window has then
  end
  return f
end
-- A window that stays out of it (it hangs from the game's own panels).
function Windows:Leave(f)
  f.panoplyWindow = { skip = true }
  if f.SetScale and not inCombat() then f:SetScale(1) end
end
-------------------------------------------------------------------------------
-- 0.9.5 (item 3: "windows opened from the main menu must not be buried behind it"). One helper for every window that opens
-- from a page of the main window (the talent planner, Go to, the dungeon maps, the auction windows, What's new, the report
-- windows, ...). Windows:Child(f, opts) takes a window in; every Skin.Window is taken in by itself. A child window then:
--   * opens IN FRONT of the main window: it is raised when it shows and when it is clicked, and while the main window is on screen a
--     child in a lower strata is lifted to the main window's (it goes back to its own when it or the main window closes);
--   * opens BESIDE the main window: to its right when there is room, else to its left, else cascaded down and right from the main
--     window's top left; a spot another child already has is cascaded from; always held on the screen;
--   * a dialog opened from another child (Skin.Popups:Child) is cascaded from that window instead;
--   * remembers where the player dragged it: PanoplySuiteDB.winPlace[key] = { x, y } (a NEW account key, made the first time a
--     window is moved; the top left corner in screen units, so it holds at any Window size) and reopens there.
-- opts.key: the name the place is remembered under (default: the frame's name). opts.place = false: a window that has a place of
-- its own (the bag windows, the guide window, the profession window): it is only brought to the front.
-- Windows:PlaceChild(f) -> true when it put the window somewhere (a remembered place, or beside the main window); a window's own
-- "open centred" code asks it first and centres only on false. With no main window on screen and no remembered place nothing is
-- moved, so a window opened by a slash command or a key opens where it always did.
-- Nothing here moves, raises or re-stratas a protected frame in combat (a window that holds secure buttons is left alone until the
-- next time it opens out of combat).
-------------------------------------------------------------------------------
Windows.CHILD_GAP = 8        -- between the main window and a child beside it
Windows.CASCADE = 28         -- one step down and right
Windows.kids = {}
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function childBlocked(f)
  if not inCombat() then return false end
  -- the kit's check also looks at the frames inside (a window that holds secure buttons); the frame's own word before the kit loads
  local K = Panoply.Kit
  if K and K.Protected then return K.Protected(f) and true or false end
  return f.IsProtected and f:IsProtected() and true or false
end
-- where a point sits on a w x h box whose bottom left is 0, 0
local function pointOn(w, h, point)
  point = point or "CENTER"
  local x = (point:find("LEFT") and 0) or (point:find("RIGHT") and w) or w / 2
  local y = (point:find("TOP") and h) or (point:find("BOTTOM") and 0) or h / 2
  return x, y
end
-- A window's place on the screen: left, top, width, height in screen (UIParent) units, or nil when it cannot be told. A window hung
-- from the screen by one point (every Skin.Window, and any window the player dragged) is worked out from that point, so the answer
-- is there before the game has drawn the window for the first time.
function Windows:Rect(f)
  local sw, sh = self:ScreenSize()
  if not sw or not f then return nil end
  local s = (f.GetScale and f:GetScale()) or 1
  if type(s) ~= "number" or s <= 0 then s = 1 end
  local w, h = (f:GetWidth() or 0) * s, (f:GetHeight() or 0) * s
  if f.GetNumPoints and f:GetNumPoints() == 1 and f.GetPoint then
    local p, rel, rp, x, y = f:GetPoint(1)
    if type(p) == "string" and (rel == nil or rel == _G.UIParent) then
      local ax, ay = pointOn(sw, sh, rp or p)
      local ox, oy = pointOn(w, h, p)
      return ax + (x or 0) * s - ox, ay + (y or 0) * s - oy + h, w, h
    end
  end
  local l, t = f.GetLeft and f:GetLeft(), f.GetTop and f:GetTop()
  local ui = _G.UIParent
  if type(l) == "number" and type(t) == "number" and f.GetEffectiveScale and ui and ui.GetEffectiveScale then
    local k = (f:GetEffectiveScale() or 1) / (ui:GetEffectiveScale() or 1)
    return l * k, t * k, w, h
  end
  return nil
end
-- The window's top left corner at (left, top) in screen units, held on the screen. Returns where it went.
function Windows:PutAt(f, left, top)
  local sw, sh = self:ScreenSize()
  if not sw then return nil end
  local s = (f.GetScale and f:GetScale()) or 1
  if type(s) ~= "number" or s <= 0 then s = 1 end
  local w, h = (f:GetWidth() or 0) * s, (f:GetHeight() or 0) * s
  left = math.max(0, math.min(left, sw - w))
  top = math.min(sh, math.max(top, h))
  left, top = math.floor(left + 0.5), math.floor(top + 0.5)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", left / s, top / s)
  return left, top
end
function Windows:ChildKey(f)
  local info = f and f.panoplyChild
  return info and (info.key or (f.GetName and f:GetName())) or nil
end
-- the place the player dragged a window to, or nil
function Windows:SavedPlace(f)
  local key = self:ChildKey(f)
  local t = key and Panoply.db and type(Panoply.db.winPlace) == "table" and Panoply.db.winPlace[key]
  if type(t) == "table" and type(t.x) == "number" and type(t.y) == "number" then return t.x, t.y end
  return nil
end
function Windows:SavePlace(f)
  local key = self:ChildKey(f)
  if not (key and Panoply.db) then return false end
  local l, t = self:Rect(f)
  if not l then return false end
  if type(Panoply.db.winPlace) ~= "table" then Panoply.db.winPlace = {} end
  Panoply.db.winPlace[key] = { x = math.floor(l + 0.5), y = math.floor(t + 0.5) }
  return true
end
function Windows:ForgetPlace(f)
  local key = self:ChildKey(f)
  if key and Panoply.db and type(Panoply.db.winPlace) == "table" then Panoply.db.winPlace[key] = nil end
end
-- the main window, when it is on screen
function Windows:Main()
  local m = Panoply.Menu and Panoply.Menu.frame
  if m and m:IsShown() then return m end
  return nil
end
-- Put a child window where it belongs (see above). Returns true when it was placed.
function Windows:PlaceChild(f)
  local info = f and f.panoplyChild
  if not info or info.place == false or not self:ChildKey(f) then return false end
  local sw, sh = self:ScreenSize()
  if not sw or childBlocked(f) then return false end
  local sx, sy = self:SavedPlace(f)
  if sx then self:PutAt(f, sx, sy) info.placed = "saved" return true end
  local main = self:Main()
  local ref, dialog = main, false
  local dp = f.panoplyDialogParent
  if dp and dp ~= f and dp ~= main and dp.IsShown and dp:IsShown() then ref, dialog = dp, true end
  if not ref or ref == f then return false end
  local l, t, w, h = self:Rect(ref)
  if not l then return false end
  local s = (f.GetScale and f:GetScale()) or 1
  if type(s) ~= "number" or s <= 0 then s = 1 end
  local cw = (f:GetWidth() or 0) * s
  local gap, step = self.CHILD_GAP, self.CASCADE
  local x, y, how
  if dialog then x, y, how = l + step, t - step, "dialog"
  elseif l + w + gap + cw <= sw then x, y, how = l + w + gap, t, "right"
  elseif l - gap - cw >= 0 then x, y, how = l - gap - cw, t, "left"
  else x, y, how = l + step, t - step, "cascade" end
  -- a spot another child window already has: one step down and right from it
  for _ = 1, 8 do
    local taken = false
    for _, k in ipairs(self.kids) do
      if k ~= f and k ~= ref and k:IsShown() and k.panoplyChild and k.panoplyChild.place ~= false then
        local kl, kt = self:Rect(k)
        if kl and math.abs(kl - x) < 4 and math.abs(kt - y) < 4 then taken = true break end
      end
    end
    if not taken then break end
    x, y = x + step, y - step
  end
  self:PutAt(f, x, y)
  info.placed = how
  return true
end
-- Bring a window in front of the main window (and of every other child). Returns false when it may not be touched now.
function Windows:Front(f)
  if not f or childBlocked(f) then return false end
  local main = self:Main()
  if main and main ~= f and f.GetFrameStrata and f.SetFrameStrata then
    local ms, fs = main:GetFrameStrata(), f:GetFrameStrata()
    if (STRATA_ORDER[fs] or 3) < (STRATA_ORDER[ms] or 5) then
      f.panoplyStrata0 = f.panoplyStrata0 or fs
      f:SetFrameStrata(ms)
    end
  end
  if f.Raise then f:Raise() end
  self.front = f
  return true
end
-- a lifted window goes back to the strata it was made in
function Windows:Unlift(f)
  if not (f and f.panoplyStrata0) or childBlocked(f) then return end
  f:SetFrameStrata(f.panoplyStrata0)
  f.panoplyStrata0 = nil
end
-- the main window closed: nothing needs to stay lifted above it
function Windows:MainHidden()
  for _, k in ipairs(self.kids) do self:Unlift(k) end
  if self.front == (Panoply.Menu and Panoply.Menu.frame) then self.front = nil end
end
function Windows:Child(f, opts)
  if not f or f.panoplyChild then return f end
  f.panoplyChild = opts or {}
  self.kids[#self.kids + 1] = f
  if f.SetToplevel and not childBlocked(f) then f:SetToplevel(true) end      -- the game raises it on a click by itself
  if f.HookScript then
    f:HookScript("OnShow", function(self)
      Windows:PlaceChild(self)
      Windows:Front(self)
    end)
    f:HookScript("OnHide", function(self)
      Windows:Unlift(self)
      if Windows.front == self then Windows.front = nil end
    end)
    f:HookScript("OnMouseDown", function(self) Windows:Front(self) end)
    f:HookScript("OnDragStop", function(self) if self.panoplyChild.place ~= false then Windows:SavePlace(self) end end)
  end
  return f
end
-- A window with a place of its own (the bag windows in their corners, the auction window beside the game's): it is brought to the
-- front like every child window, and never moved or remembered by this helper.
function Windows:OwnPlace(f)
  if not f then return end
  if not f.panoplyChild then self:Child(f, { place = false }) else f.panoplyChild.place = false end
end

Panoply.optionHooks = Panoply.optionHooks or {}
Panoply.optionHooks.windowScale = function() Windows:ApplyAll() if Panoply.UI and Panoply.UI.AfterScale then Panoply.UI:AfterScale() end end
Panoply:On("UI_SCALE_CHANGED", function() Windows:ApplyAll() end)
Panoply:On("DISPLAY_SIZE_CHANGED", function() Windows:ApplyAll() end)
-- what waited for the end of combat
Panoply:On("PLAYER_REGEN_ENABLED", function()
  if not Windows.waiting then return end
  Windows.waiting = nil
  Windows:ApplyAll()
  if Panoply.UI and Panoply.UI.AfterScale then Panoply.UI:AfterScale() end
end)

-- Standard window: v3 panel with brass caps, header with crest, close button, drag, fade/slide in.
function Skin.Window(name, w, h, title, subtitle, strata, icon)
  local f = CreateFrame("Frame", name, UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(w, h)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata(strata or "DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  Skin.Panel(f)
  Skin.Header(f, title, subtitle, icon)
  local close = Skin.IconButton(f, "x", 24, function() f:Hide() end, "Close", "Close this window. Type /panoply to open it again.")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -13)
  f.panoplyClose = close
  if name then Skin.Popups:Special(name) end
  Skin.Animate(f, -12)
  f:Hide()
  Windows:Register(f)
  -- 0.9.5 (item 3): every window but the main one is a child window: it opens in front of and beside the main window
  if name ~= "PanoplySuiteMenu" then Windows:Child(f, { key = name }) end
  return f
end

-- 0.5.4: switching the icon style re-applies every icon in place (no /reload).
Panoply.optionHooks = Panoply.optionHooks or {}
Panoply.optionHooks.iconStyle = function()
  -- a choice made in Settings is kept by the skin v3 migration below
  if Panoply.db then Panoply.db.iconStyleTouched = true end
  Skin.RefreshIcons() Panoply:Fire("GLOW_CHANGED")
end

-- Skin v3 (SPEC 19.13.4): Panoply Suite icons are the default icon style. An account saved by an
-- older version holds the old default ("wow") without anyone having chosen it, so it moves to
-- Panoply Suite icons once; a style picked in Settings since then is left alone.
if Panoply.InitDB and not Panoply.panoplySkin3InitDB then
  local initDB = Panoply.InitDB
  Panoply.panoplySkin3InitDB = true
  function Panoply:InitDB(...)
    local r = initDB(self, ...)
    local db = self.db
    if db and not db.skin3Migrated then
      if db.iconStyle == "wow" and not db.iconStyleTouched then db.iconStyle = "panoply" end
      db.skin3Migrated = true
    end
    if db then
      Skin.PanoplyValues(db)
      local prof = type(db.profiles) == "table" and type(db.profiles.list) == "table" and db.profiles.list
      for _, rec in pairs(prof or {}) do
        local set = type(rec) == "table" and type(rec.settings) == "table" and rec.settings.set
        if type(set) == "table" then Skin.PanoplyValues(set) end
      end
    end
    return r
  end
end

-- 0.9.5 (phase 8, queue item 8): a stored setting VALUE that said "hearthpath" says "panoply" now: the icon style and the
-- "Panoply Suite" swatch of the quest icons' Colour (Core/Look.lua). Run at every login on the settings and on each saved
-- profile's snapshot; it only rewrites that one word, so running it again changes nothing. The keys are never renamed, and
-- the readers (Skin.Style, Look.Colour, the Settings row) still take the old word.
function Skin.PanoplyValues(set)
  if type(set) ~= "table" then return 0 end
  local n = 0
  if set.iconStyle == "hearthpath" then set.iconStyle = "panoply" n = n + 1 end
  local Look = Panoply.Look
  for k, v in pairs(set) do
    if v == "hearthpath" and type(k) == "string" and Look and Look.KeyInfo then
      local info = Look.KeyInfo(k)
      if info and info.what == "colour" then set[k] = "panoply" n = n + 1 end
    end
  end
  return n
end
