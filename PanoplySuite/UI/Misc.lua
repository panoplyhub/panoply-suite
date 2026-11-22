-- Panoply Suite 0.8.4: the Field Kit page (it was called Miscellaneous), and the small helpers that live on it. Rebuilt in 0.9.5
-- phase 4F (docs/specs/page-redesigns-v1.md section 5) with the shared visual system (UI/KitParts.lua): a grid of tiles, each with
-- its icon, its name, an On / Off switch in its header, one line of live status, at most one action and a gear that opens its own
-- section of this page's settings. No bordered boxes, gold only on titles, explanations in ? tooltips.
--
--   This session   (spans both columns, at the top) time played large; XP per hour, levels gained and dungeon runs as stat cells;
--                  the gold change with coin icons, green for a gain and red for a loss; where the pace takes you in 30 minutes;
--                  a small chart of the session's experience over time. Action: Start again.
--   At the vendor  repair, sell greys, restock (Modules/Merchant). Status "Last visit: ...", and "Restock: 2 items short" while
--                  restock is on. Action: Sell greys now. The switch is the vendor helper's own module switch.
--   Threat bar     a live preview of the bar with sample values (hidden at Narrow), and where it shows. The switch is the bar's own.
--   Death log      with no deaths, one line and nothing else; with deaths, the last 5 (level, place, when) with a Map button each,
--                  and All deaths to see the rest.
--   Small helpers  a plain list of switches with no status to show: Faster auto loot, Level-up card, Mark my pace on the XP bar,
--                  Show the session on Home, Show the session on the Guide.
-- Bands: Wide and Medium, two columns with This session across both; Narrow, one column, the session's cells two to a row.
--
-- Settings (spec 5.3): the threat bar's switch (it was on the Guide page) and the vendor settings (they were on Muster: repair, pay
-- from the guild bank, sell greys, sell soulbound gear you can't use) live here now, in "At the vendor" together with restock. Their
-- saved keys are the same ones (autoRepair, guildRepair, autoSellJunk, sellUnusable, threatBar, restock and the module switches), so
-- every player's values carry over as they are: a setting's home in the catalogue is only where it is shown. The Guide keeps one
-- link "Threat bar settings" and Muster one "Vendor settings", each opening this page's settings at that section. The bags card is
-- gone: bags belong to Muster, which owns every bag setting.
-- Also here, because they show the same numbers: the "This session" line on Home (Home.AddLine) and the strip on the Guide page
-- (Menu.levelingBlocks), and the chat commands /panoply kit | session | deaths | restock.
-- Other files reach the page with Panoply.Misc:Open() and a part of it with Panoply.Misc:OpenTopic("bags" | "merchant" | "threat").
local ADDON, Panoply = ...
local Menu, Skin, C, Cat, Kit = Panoply.Menu, Panoply.Skin, Panoply.Compat, Panoply.Catalog, Panoply.Kit
local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local Misc = {}
Panoply.Misc = Misc

Misc.PAGE = "misc"
Misc.LABEL = "Field Kit"
Misc.DEATHS_SHOWN = 5       -- deaths listed before "All deaths"
Misc.SPARK_BARS = 32        -- the bars of the session chart
Misc.ICON = 18              -- a tile's icon
Misc.BTN = 20               -- a tile's gear and a death's Map button

-------------------------------------------------------------------------------
-- Icon slots (spec section 9) and the page's accent
-------------------------------------------------------------------------------
local I = "Interface\\Icons\\"
-- the page's own menu drawing: no other page shares it
Kit.RegisterIcon("icon.page.fieldkit", { icon = "MenuMisc", own = true })
Kit.RegisterIcon("icon.kit.vendor", { icon = "Vendor" })
Kit.RegisterIcon("icon.kit.threat", { game = { I .. "Ability_Warrior_Challange", I .. "Ability_Warrior_PunishingBlow" } })
Kit.RegisterIcon("icon.kit.session", { game = { I .. "INV_Misc_PocketWatch_01", I .. "INV_Misc_PocketWatch_02" } })
Kit.RegisterIcon("icon.kit.deathlog", { game = { I .. "INV_Misc_Bone_HumanSkull_01", I .. "INV_Misc_Bone_ElfSkull_01" } })
Kit.RegisterIcon("icon.kit.helpers", { icon = "Modules" })
if not Kit.TOKENS["accent.fieldkit"] then Kit.TOKENS["accent.fieldkit"] = "accentMoss" end

-------------------------------------------------------------------------------
-- The catalogue: the page and its gear
-------------------------------------------------------------------------------
-- A new on / off setting: its row goes into the settings every gear can show (UI/Settings.lua SUI.items: key, label, tip),
-- so the catalogue's registry, the search and Reset know it like any other; the catalogue itself only says where it lives.
local function check(key, label, tip)
  local items = Panoply.SettingsUI.items
  local have = false
  for _, it in ipairs(items) do if it[1] == key then have = true end end
  if not have then items[#items + 1] = { key, label, tip } end
  return { key, label }
end
local function merchantHere() return Panoply.Modules ~= nil and Panoply.Modules.byKey.merchant ~= nil end

local page = { key = Misc.PAGE, nav = "setup", oldNames = "miscellaneous misc kit", label = Misc.LABEL, icon = "MenuMisc", body = "Misc",
  minWidth = 420,
  text = "The vendor helper, the threat bar, this session, your death log and small helpers.",
  help = "The vendor helper, the threat bar, this session's numbers, your death log and small helpers, each with its own switch.",
  front = { common = { "autoRepair", "autoSellJunk", "restock", "threatBar", "deathLog", "levelCard" } },
  sections = {
    -- 0.9.5 phase 4F (spec 5.3): repair and selling moved here from Muster, into one section with restock
    { key = "vendor", title = "At the vendor", module = "merchant",
      text = "Keep a number of something on you, such as water, arrows or reagents: at a vendor that sells it, Panoply Suite buys what is missing, never more than the number you asked for. Alt-click an item in a vendor's window to put it on the list or take it off.",
      rows = { { "autoRepair", "Repair for me" }, { "guildRepair", "Pay from the guild bank" }, { "autoSellJunk", "Sell grey items for me" },
        { "sellUnusable", "Also sell soulbound gear you can't use" },
        check("restock", "Restock at vendors", "At a vendor, buys what your restock list is short of. Off until you turn it on."),
        Cat.Readout("info:restock", function() return Panoply.Restock and table.concat(Panoply.Restock:Lines(), "\n") or "" end),
        { type = "button", id = "action:sellNow", label = "Sell grey items now", tip = "At a vendor: sells every grey item that is not protected. Alt-click an item in your bags to protect it.",
          func = function() if Panoply.Merchant then Panoply.Merchant:SellNow() end end } } },
    -- 0.9.5 phase 4F (spec 5.3): moved here from the Guide page (Modules/Threat/Threat.lua leaves a link there)
    -- 0.9.7 hotfix (Nov 18 2026): its size and its place, like the other bars (the rows are the module's own options)
    { key = "threat", title = "Threat bar", module = "threat",
      text = "Turn off Lock the threat bar to drag it where you want it: out of combat it shows with sample values until you lock it again.",
      rows = { { "threatBar", "Show the threat bar under my mana bar" }, { "threatLocked" }, { "threatScale" }, { "threatHeight" },
        { "threatMatchWidth" }, { "threatWidth" },
        { type = "button", id = "action:threatResetPos", label = "Move the threat bar back", tip = "Back under your mana bar, where it starts.",
          func = function() if Panoply.Threat then Panoply.Threat:ResetPosition() end end } } },
    { key = "session", title = "This session",
      text = "What this play session has brought: experience per hour, gold and dungeon runs. A /reload carries it on.",
      rows = { check("homeSession", "Show this session on Home", "A line on Home with this session's XP per hour, gold and dungeon runs."),
        check("sessionStrip", "Show this session on the Guide page", "A strip on the Guide page with this session's XP per hour, gold and dungeon runs."),
        check("paceMark", "Mark where my pace takes me on the XP bar", "A small mark on the experience bar: where you will be in 30 minutes at your pace."),
        { type = "button", id = "action:sessionReset", label = "Start the session again", tip = "Counts this session's experience, gold and dungeon runs from now.",
          func = function() if Panoply.Session then Panoply.Session:Reset() end end } } },
    { key = "levelup", title = "Level-up card",
      rows = { check("levelCard", "Show a card when I gain a level", "When you gain a level: new spells, your next talent, gear you can now wear, and dungeons."),
        { type = "button", id = "action:levelCardShow", label = "Show the card now", tip = "Shows the level-up card for the level you are now.",
          func = function() if Panoply.LevelCard then Panoply.LevelCard:Show(nil, true) end end } } },
    { key = "deaths", title = "Death log",
      text = "Where, when and at what level this character died. Kept on this computer only.",
      rows = { check("deathLog", "Record my deaths", "Notes where, when and at what level this character died. Kept on this computer only."),
        Cat.Readout("info:deaths", function()
          local DL = Panoply.DeathLog
          if not DL then return "" end
          local lines = DL:Lines(8)
          table.insert(lines, 1, DL:Headline() .. (#lines > 0 and ":" or "."))
          return table.concat(lines, "\n")
        end),
        Cat.ConfirmRow("Empty the death log", "Removes every death recorded for this character from this computer.",
          "This removes every death recorded for this character. It cannot be brought back.",
          function() if Panoply.DeathLog then Panoply.DeathLog:Clear() end end) } },
    { key = "loot", title = "Looting",
      rows = { check("fastLoot", "Faster auto loot", "With the game's auto loot on, picks everything up at once. Off until you turn it on.") } },
  } }
Misc.page = page
-- the old name of the restock section (0.8.4 to 0.9.4): it is part of At the vendor now
Misc.SECTION_ALIAS = { restock = "vendor", merchant = "vendor", session = "session", deathlog = "deaths" }

-- the page goes in before Unit frames, Profiles and Help (0.9.5: first of the Setup section; they stay last); it is added once
do
  local at = #Cat.PAGES + 1
  local have = false
  for i, p in ipairs(Cat.PAGES) do
    if p.key == page.key then have = true end
    if (p.key == "frames" or p.key == "profiles") and at > i then at = i end
  end
  if not have then
    table.insert(Cat.PAGES, at, page)
    Cat[page.key] = page
    Cat.reg = nil
  end
end

-- two more rows for Guide > At quest givers (Engine/Automation.lua; both off until turned on)
for _, sec in ipairs(Cat.guide and Cat.guide.sections or {}) do
  if sec.key == "givers" and not sec.panoplyQoL then
    sec.panoplyQoL = true
    sec.rows[#sec.rows + 1] = check("autoRepeatable", "Start repeatable quests too", "Also accepts repeatable quests at a quest giver. Off until you turn it on.")
    sec.rows[#sec.rows + 1] = check("autoAcceptShared", "Accept quests my group starts", "Says yes when the game asks you to join a quest a group member started. Off until you turn it on.")
    Cat.reg = nil
  end
end

for key, words in pairs({
  restock = "restock buy vendor water food arrows ammo reagents supplies keep stock",
  fastLoot = "loot fast faster quick auto corpse pick up",
  homeSession = "home session xp per hour gold dungeon runs line",
  sessionStrip = "guide session xp per hour gold dungeon runs strip",
  paceMark = "xp bar experience horizon mark pace speed minutes",
  levelCard = "level up ding card spells talent gear dungeons",
  deathLog = "death died deaths log where when corpse hardcore",
  sessionReset = "session start again reset xp gold",
  levelCardShow = "level up card show",
  autoRepeatable = "quest repeatable automatic accept",
  autoAcceptShared = "quest shared share escort group party automatic accept",
  threatBar = "threat aggro tank pull bar combat",
  threatLocked = "threat bar lock unlock move drag position",
  threatScale = "threat bar size scale bigger smaller",
  threatHeight = "threat bar height tall thin",
  threatMatchWidth = "threat bar width mana bar match",
  threatWidth = "threat bar width wide narrow",
  threatResetPos = "threat bar reset position move back mana bar",
  guildRepair = "guild bank repair gold pay",
}) do Cat.WORDS[key] = words end

if Panoply.Profiles and Panoply.Profiles.AddKeys then
  Panoply.Profiles:AddKeys({ "restock", "fastLoot", "homeSession", "sessionStrip", "paceMark", "levelCard", "deathLog", "autoRepeatable", "autoAcceptShared" })
end

-- names the slash commands and older code may use for the page
for _, name in ipairs({ "Misc", "Miscellaneous", "FieldKit", "Field Kit", "Kit" }) do if Menu.ALIAS[name] == nil then Menu.ALIAS[name] = Misc.PAGE end end

-------------------------------------------------------------------------------
-- Doors
-------------------------------------------------------------------------------
-- the parts other pages and the chat commands reach: what each one is, and what "open" means for it. Bags is not on this page any
-- more (it is Muster's), but /panoply kit bags still opens the bag window, as it did.
Misc.TOPICS = {
  bags = { label = "Bags", module = "bags", settings = { "hall", "bags" },
    open = function() if Panoply.Bags and Panoply.Bags.active then Panoply.Bags:Open("bags") return true end return false end },
  merchant = { label = "At the vendor", module = "merchant", settings = { Misc.PAGE, "vendor" } },
  threat = { label = "Threat bar", module = "threat", settings = { Misc.PAGE, "threat" } },
}
Misc.TOPIC_ORDER = { "merchant", "threat" }

function Misc:Open() return Menu:Open(Misc.PAGE) end

-- this page's settings at a section (an old section name is followed to where it is now); pushes one step of history
function Misc:OpenGear(sec)
  sec = Misc.SECTION_ALIAS[sec or ""] or sec
  return Menu:OpenGear(Misc.PAGE, sec)
end

-- A part: Bags opens the bag window (Muster's bag settings when the bag window is off); At the vendor and Threat bar open their
-- section of this page's settings. An unknown name, or a part this build does not have, opens the page. Returns what it opened.
function Misc:OpenTopic(key)
  local t = Misc.TOPICS[tostring(key or ""):lower()]
  if not (t and Panoply.Modules.byKey[t.module]) then self:Open() return "page" end
  if t.open and t.open() then return "window" end
  Menu:OpenGear(t.settings[1], t.settings[2])
  return "settings"
end

function Misc:OpenSettings(key)
  local t = Misc.TOPICS[tostring(key or ""):lower()]
  if not (t and Panoply.Modules.byKey[t.module]) then return false end
  Menu:OpenGear(t.settings[1], t.settings[2])
  return true
end

-------------------------------------------------------------------------------
-- What the tiles say (plain data: also read by the tests and the previews)
-------------------------------------------------------------------------------
local function status(module) return (Panoply.Modules:Status(module):gsub(":.*", "")) end

-- copper with the game's coin icons: "1g 20s 5c" drawn as coins
local COIN = { g = "Interface\\MoneyFrame\\UI-GoldIcon", s = "Interface\\MoneyFrame\\UI-SilverIcon", c = "Interface\\MoneyFrame\\UI-CopperIcon" }
function Misc.Coins(copper)
  copper = floor(math.abs(copper or 0) + 0.5)
  local CI = _G.C_CurrencyInfo
  local f = (CI and CI.GetCoinTextureString) or _G.GetCoinTextureString
  if f then
    local ok, s = pcall(f, copper)
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  local out = {}
  local function add(v, k) out[#out + 1] = v .. "|T" .. COIN[k] .. ":0:0:2:0|t" end
  if g > 0 then add(g, "g") end
  if s > 0 or (g > 0 and c > 0) then add(s, "s") end
  if c > 0 or #out == 0 then add(c, "c") end
  return table.concat(out, " ")
end

-- the restock list against the bags: how many of its items are short now
function Misc.RestockShort()
  local Re = Panoply.Restock
  if not Re then return 0, 0 end
  local short, n = 0, 0
  for _, r in ipairs(Re:Rows()) do
    n = n + 1
    if (r.have or 0) < (r.want or 0) then short = short + 1 end
  end
  return short, n
end

-- At the vendor: { on, word (the switch's words), status, restock, canSell }
function Misc.VendorTile()
  local Mer = Panoply.Merchant
  local on = Panoply.Modules:IsOn("merchant")
  local v = { on = on, word = on and "On" or status("merchant") }
  if on then
    local last = Mer and Mer.lastSummary
    v.status = last and ("Last visit: " .. last:gsub("^%u", string.lower)) or "No vendor visit yet this session."
    if Panoply.db and Panoply.db.restock == true then
      local short, n = Misc.RestockShort()
      if n == 0 then v.restock = "Restock: the list is empty"
      elseif short == 0 then v.restock = "Restock: nothing short"
      else v.restock = short == 1 and "Restock: 1 item short" or ("Restock: %d items short"):format(short) end
    end
  else
    v.status = "Off: nothing is repaired, sold or bought for you."
  end
  v.canSell = on
  return v
end

-- Threat bar: { on, word, status, preview = { left, who, whoPct, pct, level } }. The preview is sample values (out of combat there
-- is nothing to show), in the bar's own words and colours (Modules/Threat/Threat.lua Threat.Labels and Threat.LEVEL_COLOR).
Misc.THREAT_SAMPLE = { pct = 72, holder = "Your tank", holderPct = 100 }
function Misc.ThreatTile()
  local on = Panoply.Modules:IsOn("threat")
  local shown = on and Panoply.db ~= nil and Panoply.db.threatBar ~= false
  local v = { on = shown and true or false }
  v.word = shown and "On" or (on and "Off" or status("threat"))
  v.status = shown and "Shows in combat under your mana bar" or "Off: no bar in combat."
  local Th = Panoply.Threat
  -- 0.9.7 hotfix: where it is now that it can be moved
  local set = Th and Th.Settings and Th.Settings()
  if shown and set then
    if not set.locked then v.status = "Unlocked: drag the bar to move it, then lock it"
    elseif set.pos then v.status = "Shows in combat where you put it" end
  end
  local s = Misc.THREAT_SAMPLE
  local snap = { me = { pct = s.pct }, holder = { name = s.holder, pct = s.holderPct }, others = {} }
  local left, who, whoPct = ("%d%%"):format(s.pct), s.holder, (" %d%%"):format(s.holderPct)
  if Th and Th.Labels then left, who, whoPct = Th.Labels(snap) end
  local level = (Th and Th.Level) and Th.Level(snap.me) or "warn"
  v.preview = { left = left, who = who, whoPct = whoPct, pct = s.pct, level = level }
  return v
end

-- the session's chart: the experience gained by the end of each of n equal slices of the session (nil when there is nothing to draw)
function Misc.SessionBars(n)
  local S = Panoply.Session
  if not (S and S.Curve) then return nil end
  local curve, seconds = S:Curve()
  if not curve or seconds < 60 then return nil end
  local top = curve[#curve].xp
  if top <= 0 then return nil end
  local out, j = {}, 1
  for i = 1, n do
    local t = seconds * i / n
    while j < #curve and curve[j + 1].t <= t do j = j + 1 end
    out[i] = curve[j].t <= t and curve[j].xp / top or 0
  end
  return out
end

-- This session: { time, cells = { { value, label } x3 }, gold, goldText, gain (true | false | nil for no change), eta, bars }
function Misc.SessionTile()
  local S = Panoply.Session
  local s = S:Stats()
  local function number(n) return Panoply.Pace and Panoply.Pace.Number and Panoply.Pace.Number(n) or tostring(floor((n or 0) + 0.5)) end
  local v = { time = S.TimeText(s.seconds) }
  v.cells = {
    s.xph and { number(s.xph), "XP per hour" } or { number(s.xp), "XP so far" },
    { tostring(s.levels), s.levels == 1 and "Level gained" or "Levels gained" },
    { tostring(s.runs), s.runs == 1 and "Dungeon run" or "Dungeon runs" },
  }
  v.gold = s.gold
  if s.gold == 0 then v.goldText = "No change"
  else
    v.gain = s.gold > 0
    v.goldText = (s.gold > 0 and "+" or "-") .. Misc.Coins(s.gold)
  end
  v.eta = Misc.HorizonLine()
  v.bars = Misc.SessionBars(Misc.SPARK_BARS)
  return v
end

-- Death log: { on, count, head, rows = { { text, map, x, y, level } }, more } (rows only when there are deaths; all of them when
-- `all`, else the newest Misc.DEATHS_SHOWN)
function Misc.DeathTile(all)
  local DL = Panoply.DeathLog
  local v = { on = DL:On(), count = DL:Count(), rows = {} }
  v.head = DL:Headline()
  if v.count == 0 then return v end
  local now = (_G.time and _G.time()) or os.time()
  for i, rec in ipairs(DL:List()) do
    if not all and i > Misc.DEATHS_SHOWN then break end
    v.rows[#v.rows + 1] = { text = DL.Text(rec, now), map = rec.map, x = rec.x, y = rec.y, level = rec.level, zone = rec.zone }
  end
  v.more = v.count - #v.rows
  return v
end

-- the small helpers: switches with no status of their own
Misc.HELPERS = {
  { "fastLoot", "Faster auto loot" },
  { "levelCard", "Level-up card" },
  { "paceMark", "Mark my pace on the XP bar" },
  { "homeSession", "Show this session on Home" },
  { "sessionStrip", "Show this session on the Guide" },
}

-- "In 30 min: 72% of level 24 at your pace": only from the pace learned from your own play (the same rule as the mark)
function Misc.HorizonLine()
  local P = Panoply.Pace
  if not (P and P.HorizonLine) then return nil end
  local line, h = P:HorizonLine()
  if not (line and h and h.source == "pace") then return nil end
  return line
end

-- the tiles' explanations (in their ? tooltips, never in body copy)
Misc.HELP = {
  vendor = "When you talk to a vendor: repairs your gear, sells grey items and tops up your restock list, then says what it did in chat.",
  threat = "A thin bar under your mana bar in combat: how close you are to pulling your target, against your pet and your group. The preview here uses sample values.",
  session = "What this play session has brought. A /reload carries it on; Start again counts from now.",
  deaths = "Where, when and at what level this character died. Kept on this computer only.",
  helpers = "Small helpers with nothing to report: each switch turns one on or off.",
}

-------------------------------------------------------------------------------
-- Small parts
-------------------------------------------------------------------------------
local function setColor(fs, token) local c = Kit.Color(token) fs:SetTextColor(c[1], c[2], c[3], 1) end
local function redraw() if Menu.RefreshCurrent then Menu:RefreshCurrent() end end

-- a block of text at (x, y) of parent, w wide: returns its height
local function place(fs, parent, x, y, w)
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(max(10, w))
  local h = ceil(TH(fs, max(10, w)))
  fs:SetHeight(max(1, h))
  return h
end

local function iconButton(parent, glyph, slot, onClick, tip, body)
  local b = Skin.IconButton(parent, "", Misc.BTN, onClick, tip, body)
  b:SetIcon(glyph, floor(Misc.BTN * 0.7))
  if slot then b.panoplyKitIcon = slot end
  return b
end

-- One tile: a card with the header (icon, name, the switch, the gear) and the parts each kind adds. t.Layout(t, w) -> height.
local function newTile(p, key, slot, title, opts)
  opts = opts or {}
  local f = Kit.Surface(p, 1)
  f:SetAccent("fieldkit")
  local t = { key = key, frame = f, lines = {} }
  t.icon = f:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(Misc.ICON, Misc.ICON)
  Kit.Icon(t.icon, slot, { size = Misc.ICON })
  t.name = Skin.Name(f, 14, Kit.Color("text.primary"))
  t.name:SetText(title)
  if t.name.SetWordWrap then t.name:SetWordWrap(false) end
  t.title = title
  t.help = Kit.HelpIcon(f, title, Misc.HELP[key], 16)
  if opts.switch then
    t.switch = Skin.Switch(f, function() opts.switch() redraw() end, title, "Turns it on or off here; its settings are behind the gear.")
  end
  -- (the page header's settings picture: it follows the icon style, the theme's or the game's)
  t.gear = Skin.IconButton(f, "Settings", Misc.BTN, function() Misc:OpenGear(opts.gearSection or key) end, title .. " settings",
    "Opens this page's settings at " .. title .. ".")
  t.gear.panoplyKitIcon = "icon.ui.gear"
  return t
end

-- a font string of a tile's own, made once and kept in t.lines[name]
local function line(t, name, size, token, nameFont)
  local fs = t.lines[name]
  if not fs then
    fs = nameFont and Skin.Name(t.frame, size or 12, Kit.Color(token or "text.primary")) or Skin.Ink(t.frame, size or 12, Kit.Color(token or "text.muted"))
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    t.lines[name] = fs
  end
  return fs
end

-- the header: icon, name (with an optional status after it, for a tile that collapsed to one line), then at the right the switch
-- and the gear. Returns the height used.
local function layoutHead(t, w, pad, extra)
  local f = t.frame
  local right = w - pad
  t.gear:ClearAllPoints(); t.gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -pad + 1)
  right = right - Misc.BTN - SP.s
  if t.switch then
    t.switch:SetState(t.on, t.word, max(100, floor(w * 0.45)))
    t.switch:ClearAllPoints(); t.switch:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(w - right), -pad)
    right = right - t.switch:GetWidth() - SP.s
  end
  t.icon:ClearAllPoints(); t.icon:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad - 2)
  local x = pad + Misc.ICON + SP.s
  local helpW = (t.help and Misc.HELP[t.key]) and (16 + SP.s) or 0
  local room = max(40, right - x - helpW)
  -- a tile that collapsed to one line says its status after its name; when both do not fit, the status goes under the name
  local text = t.title .. (extra and ("  " .. Skin.Code(Kit.Color("text.muted")) .. extra .. "|r") or "")
  t.name:SetWidth(2000); t.name:SetText(text)
  local under = extra and ceil(TW(t.name)) + 2 > room
  if under then text = t.title end
  t.name:ClearAllPoints(); t.name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -pad - 3)
  t.name:SetWidth(room)
  Skin.Ellipsize(t.name, text, room)
  local nw = min(room, ceil(TW(t.name)) + 2)
  t.name:SetWidth(nw)
  local nh = ceil(TH(t.name, nw))
  t.name:SetHeight(nh)
  if helpW > 0 then
    t.help:ClearAllPoints(); t.help:SetPoint("TOPLEFT", f, "TOPLEFT", x + nw + SP.s, -pad - 3); t.help:Show()
  elseif t.help then t.help:Hide() end
  -- as tall as the tallest of the name (larger text at 1.3x), the icon, the switch and the gear, then a small gap
  local sw = t.switch and t.switch:GetHeight() or 0
  local h = pad + max(nh + 3, Misc.ICON + 2, sw, Misc.BTN) + SP.s
  local ex = t.lines.extra
  if under then
    ex = line(t, "extra", 12, "text.muted")
    ex:SetText(extra)
    ex:Show()
    h = h + place(ex, f, x, -h + SP.s, w - x - pad) + SP.s
  elseif ex then ex:Hide() end
  t.collapsedText = extra
  return h
end

-------------------------------------------------------------------------------
-- The tiles
-------------------------------------------------------------------------------
local Tiles = {}
Misc.Tiles = Tiles

-- This session
function Tiles.session(p)
  local t = newTile(p, "session", "icon.kit.session", "This session")
  t.big = line(t, "big", 20, "text.primary", true)
  t.cells = {}
  for i = 1, 3 do
    local c = Kit.Surface(t.frame, 2)
    c.value = Skin.Name(c, 15, Kit.Color("text.primary"))
    c.label = Skin.Ink(c, 11, Kit.Color("text.muted"))
    for _, fs in ipairs({ c.value, c.label }) do if fs.SetWordWrap then fs:SetWordWrap(false) end if fs.SetJustifyH then fs:SetJustifyH("LEFT") end end
    t.cells[i] = c
  end
  t.goldLabel = line(t, "goldLabel", 12, "text.muted")
  t.goldLabel:SetText("Gold")
  t.gold = line(t, "gold", 14, "text.primary", true)
  t.eta = line(t, "eta", 12, "text.muted")
  t.spark = CreateFrame("Frame", nil, t.frame)
  t.spark.panoplyGapOK = true
  t.spark.bars = {}
  Skin.Tooltip(t.spark, "Experience this session", "Each bar is a slice of the session: how much experience you had gained by its end.")
  if t.spark.EnableMouse then t.spark:EnableMouse(true) end
  t.spark:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  t.spark:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  t.action = Skin.Button(t.frame, "Start again", 110, 26, function() Panoply.Session:Reset() redraw() end, "Start the session again",
    "Counts this session's experience, gold and dungeon runs from now.")
  function t.Refresh(self)
    local v = Misc.SessionTile()
    self.v = v
    self.big:SetText(v.time .. " played")
    for i, c in ipairs(self.cells) do c.value:SetText(v.cells[i][1]); c.label:SetText(v.cells[i][2]) end
    self.gold:SetText(v.goldText)
    setColor(self.gold, v.gain == true and "state.good" or v.gain == false and "state.bad" or "text.primary")
    self.eta:SetText(v.eta and (v.eta .. ".") or "")
  end
  function t.Layout(self, w, band)
    local pad = SP.m
    local f = self.frame
    local y = layoutHead(self, w, pad)
    local inner = w - 2 * pad
    y = y + place(self.big, f, pad, -y, inner) + SP.s
    -- the cells: three in a row, or two to a row at Narrow
    local per = band == "narrow" and 2 or 3
    local cw = floor((inner - (per - 1) * SP.s) / per)
    local tw = cw - 2 * SP.s
    -- every cell is as tall as the tallest one
    local ch = 0
    for _, c in ipairs(self.cells) do
      c.value:ClearAllPoints(); c.value:SetPoint("TOPLEFT", c, "TOPLEFT", SP.s, -SP.s)
      c.value:SetWidth(tw); Skin.Ellipsize(c.value, c.value:GetText() or "", tw)
      local vh = ceil(TH(c.value, tw)); c.value:SetHeight(vh)
      c.label:ClearAllPoints(); c.label:SetPoint("TOPLEFT", c, "TOPLEFT", SP.s, -SP.s - vh - 2)
      c.label:SetWidth(tw); Skin.Ellipsize(c.label, c.label:GetText() or "", tw)
      local lh = ceil(TH(c.label, tw)); c.label:SetHeight(lh)
      ch = max(ch, SP.s + vh + 2 + lh + SP.s)
    end
    for i, c in ipairs(self.cells) do
      local col, row = (i - 1) % per, floor((i - 1) / per)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", pad + col * (cw + SP.s), -(y + row * (ch + SP.s)))
      c:SetSize(cw, ch)
    end
    local rows = ceil(#self.cells / per)
    y = y + rows * ch + (rows - 1) * SP.s + SP.m
    -- the gold change
    local lw = ceil(TW(self.goldLabel)) + 2
    self.goldLabel:ClearAllPoints(); self.goldLabel:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y - 2); self.goldLabel:SetWidth(lw)
    self.goldLabel:SetHeight(ceil(TH(self.goldLabel, lw)))
    local gh = place(self.gold, f, pad + lw + SP.m, -y, inner - lw - SP.m)
    y = y + max(gh, 16) + SP.s
    if (self.eta:GetText() or "") ~= "" then
      self.eta:Show()
      y = y + place(self.eta, f, pad, -y, inner) + SP.s
    else self.eta:Hide() end
    -- the chart and the action on one line (the chart only when there is something to draw)
    local bars = self.v and self.v.bars
    local bw = self.action:GetWidth()
    local sw = inner - bw - SP.m
    local sh = 28
    if bars and sw >= 60 then
      self.spark:Show()
      self.spark:ClearAllPoints(); self.spark:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
      self.spark:SetSize(sw, sh)
      local n = #bars
      local gap = 1
      local each = max(1, floor((sw - (n - 1) * gap) / n))
      local accent = Kit.Accent("fieldkit")
      for i = 1, n do
        local b = self.spark.bars[i]
        if not b then b = self.spark:CreateTexture(nil, "ARTWORK") self.spark.bars[i] = b end
        b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", self.spark, "BOTTOMLEFT", (i - 1) * (each + gap), 0)
        b:SetSize(each, max(1, floor(sh * bars[i] + 0.5)))
        Skin.Solid(b, accent, bars[i] > 0 and 0.85 or 0.25)
        b:Show()
      end
      for i = n + 1, #self.spark.bars do self.spark.bars[i]:Hide() end
    else self.spark:Hide() end
    self.action:ClearAllPoints(); self.action:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -y)
    y = y + max(bars and sh or 0, self.action:GetHeight()) + pad
    return y
  end
  return t
end

-- At the vendor
function Tiles.vendor(p)
  local t = newTile(p, "vendor", "icon.kit.vendor", "At the vendor", { switch = function()
    Panoply.Modules:Set("merchant", not Panoply.Modules:Wanted("merchant"))
  end })
  t.status = line(t, "status", 12, "text.muted")
  t.restock = line(t, "restock", 12, "text.muted")
  t.action = Skin.Button(t.frame, "Sell greys now", 130, 26, function()
    if Panoply.Merchant and Panoply.Merchant.active then Panoply.Merchant:SellNow() else Panoply:Print("The vendor helper is off.") end
  end, "Sell grey items now", "At a vendor: sells every grey item that is not protected. Alt-click an item in your bags to protect it.")
  Skin.FitButton(t.action, 110, 220)
  function t.Refresh(self)
    local v = Misc.VendorTile()
    self.v, self.on, self.word = v, v.on, v.word
    self.status:SetText(v.status)
    self.restock:SetText(v.restock or "")
    self.action:SetEnabledLook(v.canSell)
  end
  function t.Layout(self, w)
    local pad = SP.m
    local f = self.frame
    local y = layoutHead(self, w, pad)
    local inner = w - 2 * pad
    y = y + place(self.status, f, pad, -y, inner) + SP.xs
    if (self.restock:GetText() or "") ~= "" then
      self.restock:Show()
      y = y + place(self.restock, f, pad, -y, inner) + SP.xs
    else self.restock:Hide() end
    y = y + SP.s
    self.action:ClearAllPoints(); self.action:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
    return y + self.action:GetHeight() + pad
  end
  return t
end

-- Threat bar
function Tiles.threat(p)
  local t = newTile(p, "threat", "icon.kit.threat", "Threat bar", { switch = function()
    local M = Panoply.Modules
    local on = M:IsOn("threat") and Panoply.db.threatBar ~= false
    if on then Panoply:SetOption("threatBar", false)
    else
      if not M:Wanted("threat") then M:Set("threat", true) end
      Panoply:SetOption("threatBar", true)
    end
  end })
  t.status = line(t, "status", 12, "text.muted")
  -- the preview: the bar's own shape (a track, the fill to the percentage, the two words on it), with sample values
  local pv = CreateFrame("Frame", nil, t.frame)
  pv.panoplyGapOK = true
  pv.track = pv:CreateTexture(nil, "BACKGROUND"); pv.track:SetAllPoints(pv)
  Skin.Solid(pv.track, Skin.colors.slotBottom, 1)
  pv.fill = pv:CreateTexture(nil, "ARTWORK")
  pv.left = Skin.Text(pv, 11, Skin.colors.text, nil, "semi")
  pv.right = Skin.Text(pv, 11, Skin.colors.text, nil, "semi")
  for _, fs in ipairs({ pv.left, pv.right }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  Skin.Tooltip(pv, "Threat bar preview", "Sample values: what the bar looks like in combat.")
  if pv.EnableMouse then pv:EnableMouse(true) end
  pv:SetScript("OnEnter", function(self) if self.panoplyShowTip then self.panoplyShowTip() end end)
  pv:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  t.preview = pv
  function t.Refresh(self)
    local v = Misc.ThreatTile()
    self.v, self.on, self.word = v, v.on, v.word
    self.status:SetText(v.status)
  end
  function t.Layout(self, w, band)
    local pad = SP.m
    local f = self.frame
    local y = layoutHead(self, w, pad)
    local inner = w - 2 * pad
    local pv, v = self.preview, self.v
    local Th = Panoply.Threat
    if band ~= "narrow" and v and Th and Th.Settings and Th.FontSize then
      -- 0.9.7 hotfix (lane QLEFT): drawn like the live bar (Threat:ApplyLayout / Threat:Draw): the player's height as the bar draws
      -- it (never below Threat.HEIGHT_MIN), the words sized by Threat.FontSize and stepped down until they fit, my percentage dark
      -- on the fill or light with a shadow past its edge (never across it), and the one to watch on a line under the bar.
      pv:Show()
      local h = Th.Settings().height
      pv:ClearAllPoints(); pv:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
      pv:SetSize(inner, h)
      local cname = (Th.LEVEL_COLOR and Th.LEVEL_COLOR[v.preview.level]) or "highlight"
      local c = Skin.colors[cname] or Skin.colors.highlight
      local fw = max(1, floor(inner * v.preview.pct / 100))
      pv.fill:ClearAllPoints(); pv.fill:SetPoint("TOPLEFT", pv, "TOPLEFT", 0, 0)
      pv.fill:SetSize(fw, h)
      Skin.Solid(pv.fill, c, v.on and 0.9 or 0.4)
      local PAD, GAP = Th.PAD, Th.EDGE + 1
      -- a dimmed fill (the bar is off) is dark, so the words on it are light, as on the track
      local edge = v.preview.pct > 0 and fw or nil
      local function paint(fs, onFill)
        local tc = onFill and Skin.colors.bgDeep or Skin.colors.text
        fs:SetTextColor(tc[1], tc[2], tc[3], 1)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, onFill and 0 or 1) end
        if fs.SetShadowOffset then if onFill then fs:SetShadowOffset(0, 0) else fs:SetShadowOffset(1, -1) end end
      end
      pv.left:SetText(v.preview.left)
      local size, lw, lx, lOnFill = Th.FontSize(h)
      while true do
        for _, fs in ipairs({ pv.left, pv.right }) do Skin.Font(fs, size, Skin.colors.text, nil, "semi") end
        lw = TW(pv.left)
        lx, lOnFill = PAD, false
        if edge then
          if PAD + lw <= edge - GAP then lOnFill = v.on else lx = max(PAD, edge + GAP) end
        end
        if lx + lw <= inner - PAD or size <= Th.FONT_MIN then break end
        size = size - 1
      end
      pv.left:ClearAllPoints(); pv.left:SetPoint("LEFT", pv, "LEFT", lx, 0); pv.left:SetWidth(ceil(lw) + 2)
      if pv.left.SetJustifyH then pv.left:SetJustifyH("LEFT") end
      paint(pv.left, lOnFill)
      -- the one to watch: under the bar at its right end; the percentage is kept whole, the name gives way (3 letters or it goes)
      local name, pct = v.preview.who or "", v.preview.whoPct or ""
      local room, shown = inner - PAD * 2, ""
      if name ~= "" then
        local num = pct:gsub("^%s+", "")
        pv.right:SetText(pct)
        local nameRoom = room - (pct ~= "" and TW(pv.right) or 0)
        if nameRoom > 0 then
          local wasCut = Skin.Ellipsize(pv.right, name, nameRoom)
          local cut = pv.right:GetText() or ""
          if TW(pv.right) <= nameRoom and (not wasCut or #cut:gsub("[\128-\191]", "") > 3) then shown = cut .. pct end
        end
        if shown == "" and num ~= "" then
          pv.right:SetText(num)
          if TW(pv.right) <= room then shown = num end
        end
      end
      y = y + h
      if shown == "" then
        pv.right:SetText(""); pv.right:Hide()
      else
        pv.right:SetText(shown)
        pv.right:SetWidth(room)
        pv.right:ClearAllPoints(); pv.right:SetPoint("TOPRIGHT", pv, "BOTTOMRIGHT", -PAD, -2)
        if pv.right.SetJustifyH then pv.right:SetJustifyH("RIGHT") end
        paint(pv.right, false)
        pv.right:Show()
        y = y + 2 + ceil(TH(pv.right))
      end
      y = y + SP.s
    else pv:Hide() end
    y = y + place(self.status, f, pad, -y, inner)
    return y + pad
  end
  return t
end

-- Death log
function Tiles.deaths(p)
  local t = newTile(p, "deaths", "icon.kit.deathlog", "Death log", { switch = function()
    Panoply:SetOption("deathLog", not Panoply.DeathLog:On())
  end })
  t.rows = {}
  t.all = Skin.Button(t.frame, "All deaths", 110, 24, function() Misc:ShowAllDeaths(not Misc:AllDeaths()) end,
    "All deaths", "Every death recorded for this character, newest first.")
  function t.Refresh(self)
    local v = Misc.DeathTile(Misc:AllDeaths())
    self.v, self.on = v, v.on
    self.word = v.on and "On" or "Off"
    for i, r in ipairs(v.rows) do
      local row = self.rows[i]
      if not row then
        row = { text = Skin.Ink(self.frame, 12, Kit.Color("text.muted")) }
        if row.text.SetJustifyH then row.text:SetJustifyH("LEFT") end
        row.map = iconButton(self.frame, "Map", "icon.ui.map", function() Misc:ShowDeath(row.rec) end, "Show it on the map",
          "Points the arrow at the place and opens the Map page.")
        self.rows[i] = row
      end
      row.rec = r
      row.text:SetText(r.text)
    end
    for i = #v.rows + 1, #self.rows do self.rows[i].text:Hide(); self.rows[i].map:Hide() end
    if v.count > Misc.DEATHS_SHOWN then
      self.all.label:SetText(Misc:AllDeaths() and "Fewer" or ("All deaths (%d)"):format(v.count))
      Skin.FitButton(self.all, 90, 200)
    end
  end
  function t.Layout(self, w)
    local pad = SP.m
    local f = self.frame
    local v = self.v
    -- no deaths: the whole tile is one line
    if v.count == 0 then
      for _, row in ipairs(self.rows) do row.text:Hide(); row.map:Hide() end
      self.all:Hide()
      return layoutHead(self, w, pad, v.head) + pad - SP.s
    end
    local y = layoutHead(self, w, pad, v.head)
    local inner = w - 2 * pad
    for i, r in ipairs(v.rows) do
      local row = self.rows[i]
      local canMap = r.map and r.x and r.y and Panoply.Map ~= nil and Panoply.Map.PointAt ~= nil
      local tw = inner - (canMap and (Misc.BTN + SP.s) or 0)
      row.text:Show()
      local h = place(row.text, f, pad, -y - 2, tw)
      if canMap then
        row.map:ClearAllPoints(); row.map:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -y); row.map:Show()
      else row.map:Hide() end
      y = y + max(h + 4, canMap and (Misc.BTN + 2) or 0) + SP.xs
    end
    if v.count > Misc.DEATHS_SHOWN then
      self.all:Show()
      y = y + SP.xs
      self.all:ClearAllPoints(); self.all:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
      y = y + self.all:GetHeight()
    else self.all:Hide() end
    return y + pad
  end
  return t
end

-- Small helpers
function Tiles.helpers(p)
  local t = newTile(p, "helpers", "icon.kit.helpers", "Small helpers", { gearSection = "loot" })
  t.checks = {}
  for i, h in ipairs(Misc.HELPERS) do
    local key, label = h[1], h[2]
    local tip
    for _, it in ipairs(Panoply.SettingsUI.items) do if it[1] == key then tip = it[3] end end
    local b = Skin.Check(t.frame, label, { get = function() return Panoply.db and Panoply.db[key] ~= false and Panoply.db[key] ~= nil end,
      set = function(v) Panoply:SetOption(key, v and true or false) end }, function() redraw() end, tip, false)
    b.panoplyKey = key
    t.checks[i] = b
  end
  function t.Refresh(self) for _, b in ipairs(self.checks) do b:Refresh() end end
  function t.Layout(self, w)
    local pad = SP.m
    local f = self.frame
    local y = layoutHead(self, w, pad)
    local inner = w - 2 * pad
    for _, b in ipairs(self.checks) do
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
      local _, h = b:FitLabel(inner - 27)
      y = y + max(22, h + 6)
    end
    return y + pad - 2
  end
  return t
end

-- the death's Map button: the arrow points at the place (Map:PointAt, through the waypoints when they are on) and the Map page opens
-- (with waypoints off and the arrow off, nothing can be marked: it says so and stays here)
function Misc:ShowDeath(r)
  if not (r and r.map and r.x and r.y) then return false end
  local M = Panoply.Map
  local label = ("Where I died (level %d)"):format(r.level or 1)
  local ok = M and M.PointAt and M:PointAt(r.map, r.x, r.y, label)
  if not ok then
    Panoply:Print("Nothing was marked: waypoints and the arrow are off. Turn on waypoints on the Map page to mark where you died.")
    return false
  end
  Menu:Open("map")
  return true
end

-------------------------------------------------------------------------------
-- The page body
-------------------------------------------------------------------------------
Misc.TILE_ORDER = { "vendor", "threat", "deaths", "helpers" }

-- which tiles exist in this build (the vendor helper and the threat bar are modules)
function Misc.TileShown(key)
  if key == "vendor" then return merchantHere() end
  if key == "threat" then return Panoply.Modules ~= nil and Panoply.Modules.byKey.threat ~= nil end
  return true
end

Menu:RegisterTab("Misc", function(p)
  p.tiles = {}
  p.tiles.session = Tiles.session(p)
  for _, key in ipairs(Misc.TILE_ORDER) do p.tiles[key] = Tiles[key](p) end
  Misc.pageFrame = p
  function p:Layout() return Misc:Layout(self) end
end, function(p)
  for key, t in pairs(p.tiles) do
    if Misc.TileShown(key) then t.frame:Show() t:Refresh() else t.frame:Hide() end
  end
end, { scroll = true })

-- Wide and Medium: This session across the top, then two columns, each tile going to the shorter one. Narrow: one column.
function Misc:Layout(p)
  local W = (p.width or 600) - 4
  local band = Kit.Band(p.width or 600)
  p.band = band
  local gap = SP.m
  local x0 = 2
  local y = 0
  local s = p.tiles.session
  local sh = s:Layout(W, band)
  s.frame:ClearAllPoints(); s.frame:SetPoint("TOPLEFT", p, "TOPLEFT", x0, -y); s.frame:SetSize(W, sh)
  y = y + sh + gap
  local cols = band == "narrow" and 1 or 2
  local cw = cols == 1 and W or floor((W - gap) / 2)
  local colY = {}
  for i = 1, cols do colY[i] = y end
  p.columns = {}
  for _, key in ipairs(Misc.TILE_ORDER) do
    local t = p.tiles[key]
    if t.frame:IsShown() then
      local col = 1
      for i = 2, cols do if colY[i] < colY[col] then col = i end end
      local h = t:Layout(cw, band)
      t.frame:ClearAllPoints(); t.frame:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + (col - 1) * (cw + gap), -colY[col])
      t.frame:SetSize(cw, h)
      p.columns[key] = col
      colY[col] = colY[col] + h + gap
    end
  end
  local bottom = y
  for i = 1, cols do bottom = max(bottom, colY[i]) end
  return bottom - gap + SP.s
end

-- what the page remembers: whether All deaths is open. It is the page's own state (Kit page state, "deaths.all"), so it comes back
-- after a reload, Reset view in the header closes it, and Back and Forward put it back.
function Misc:AllDeaths() return Kit.GetOpen(Misc.PAGE, "deaths.all", false) and true or false end
function Misc:ShowAllDeaths(on)
  if on then Kit.SetOpen(Misc.PAGE, "deaths.all", true) else Kit.ForgetOpen(Misc.PAGE, "deaths.all") end
  if Panoply.History then Panoply.History:Note("deaths") end
  redraw()
end
if Panoply.History then Panoply.History:State(Misc.PAGE, {
  get = function() return Misc:AllDeaths() and "all" or "" end,
  set = function(s) if s == "all" then Kit.SetOpen(Misc.PAGE, "deaths.all", true) else Kit.ForgetOpen(Misc.PAGE, "deaths.all") end end,
}) end

-- the pages that show these numbers follow them while the window is open
local function follow(pages)
  return function()
    local M = Panoply.Menu
    if M and M.frame and M.frame:IsShown() and pages[M.current or ""] and not M.batching then M:RefreshCurrent() end
  end
end
Panoply:Listen("SESSION_CHANGED", follow({ misc = true, home = true, guide = true }))
Panoply:Listen("DEATH_LOGGED", follow({ misc = true }))
Panoply:Listen("RESTOCK_CHANGED", follow({ misc = true }))
Panoply:Listen("PACE_CHANGED", follow({ misc = true }))
Panoply:Listen("MODULE_CHANGED", follow({ misc = true }))

-------------------------------------------------------------------------------
-- Home: one line, once the session has something to tell
-------------------------------------------------------------------------------
function Misc.HomeLine()
  local S = Panoply.Session
  if not (S and Panoply.db and Panoply.db.homeSession ~= false) then return nil end
  local parts, s = S:Parts()
  if s.xp <= 0 and s.gold == 0 and s.runs == 0 and s.deaths == 0 then return nil end
  local first = table.remove(parts, 1)
  return { key = "session", group = "glance", icon = "Star", page = Misc.PAGE, pageLabel = Misc.LABEL,
    title = "This session: " .. first,
    sub = ("%s played. %s."):format(S.TimeText(s.seconds), table.concat(parts, ", ")),
    help = "Opens Field Kit: this session, your death log, the vendor helper and the threat bar." }
end
if Panoply.Home and Panoply.Home.AddLine then Panoply.Home.AddLine(Misc.HomeLine) end

-------------------------------------------------------------------------------
-- The Guide page: the session strip (through Menu.levelingBlocks, like the Trainer line)
-------------------------------------------------------------------------------
-- The strip's two lines, or nil when it is off or the session has nothing to tell yet.
function Misc.StripText()
  local S = Panoply.Session
  if not (S and Panoply.db and Panoply.db.sessionStrip ~= false) then return nil end
  local parts, s = S:Parts()
  if s.xp <= 0 and s.gold == 0 and s.runs == 0 and s.deaths == 0 then return nil end
  local sub = S.TimeText(s.seconds) .. " played."
  local h = Panoply.db.paceMark ~= false and Misc.HorizonLine()
  if h then sub = sub .. " " .. h .. "." end
  return table.concat(parts, ", ") .. ".", sub
end

local block = {}
function block.build(p)
  local icon = p:CreateTexture(nil, "OVERLAY"); icon:SetSize(18, 18); Skin.SetIcon(icon, "Star")
  local label = Skin.Label(p, 11, Skin.colors.goldBright); label:SetText("THIS SESSION")
  local t = Skin.Ink(p, 12)
  local s = Skin.Ink(p, 11, Skin.colors.inkSoft)
  p.session = { icon = icon, label = label, text = t, sub = s }
end
function block.refresh(p)
  local se = p.session
  if not se then return end
  local line1, sub = Misc.StripText()
  local on = line1 ~= nil and not Panoply:PlayAlong()
  for _, o in pairs(se) do if on then o:Show() else o:Hide() end end
  if not on then return end
  se.text:SetText(line1); se.sub:SetText(sub or "")
end
-- icon, THIS SESSION label, the numbers, a soft line under them
function block.layout(p, y, W)
  local se = p.session
  if not (se and se.text:IsShown()) then return y end
  y = y - SP.m
  se.icon:ClearAllPoints(); se.icon:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y)
  local lw = math.ceil(Skin.TextWidth(se.label)) + 2; se.label:SetWidth(lw)
  se.label:ClearAllPoints(); se.label:SetPoint("TOPLEFT", p, "TOPLEFT", 42, y - 3)
  local tx = 42 + lw + 8
  local tw = W - tx - 16
  se.text:ClearAllPoints(); se.text:SetPoint("TOPLEFT", p, "TOPLEFT", tx, y - 2); se.text:SetWidth(tw)
  local th = TH(se.text, tw); se.text:SetHeight(th)
  local y2 = y - math.max(th + 2, 18) - 2
  local sw = W - 42 - 16
  se.sub:ClearAllPoints(); se.sub:SetPoint("TOPLEFT", p, "TOPLEFT", 42, y2); se.sub:SetWidth(sw)
  local sh = (se.sub:GetText() or "") ~= "" and TH(se.sub, sw) or 0
  se.sub:SetHeight(math.max(1, sh))
  return y2 - sh
end
if Menu.levelingBlocks then table.insert(Menu.levelingBlocks, block) end
Misc.sessionBlock = block

-------------------------------------------------------------------------------
-- Chat commands (Core/Slash.lua loads after this file, so they are added once everything has loaded)
-------------------------------------------------------------------------------
Misc.CHAT = {
  "/panoply kit - open the Field Kit page (the vendor helper, the threat bar, this session, the death log); /panoply misc works too",
  "/panoply session - this session's experience per hour, gold and dungeon runs;  session reset - count from now",
  "/panoply deaths - where, when and at what level this character died;  deaths clear | on | off",
  "/panoply restock - your restock list;  restock on | off;  restock 40 [item link] - keep 40 of it (0 takes it off)",
  "/panoply levelup - show the level-up card for your level now",
}

function Misc:Slash(msg)
  local cmd, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "kit" or cmd == "fieldkit" or cmd == "misc" or cmd == "miscellaneous" then
    local topic = rest:lower()
    if Misc.TOPICS[topic] then self:OpenTopic(topic) else self:Open() end
  elseif cmd == "session" then
    if rest:lower() == "reset" then Panoply.Session:Reset() Panoply:Print("This session is counted from now.") end
    Panoply:Print((Panoply.Session:Line()))
    local h = Misc.HorizonLine()
    if h then Panoply:Print(h .. ".") end
  elseif cmd == "deaths" or cmd == "deathlog" then
    Panoply.DeathLog:Slash(Panoply.ParseSlashArgs and Panoply.ParseSlashArgs(msg) or { cmd, rest })
  elseif cmd == "restock" then
    local Re = Panoply.Restock
    if not (Re and Panoply.Merchant and Panoply.Merchant.active) then Panoply:Print("The vendor helper is off, so restock is too (switch it on in " .. Panoply:SettingsPath("autoSellJunk") .. ").") return true end
    Re:Slash(msg)
  elseif cmd == "levelup" or cmd == "levelcard" then
    if Panoply.LevelCard then Panoply.LevelCard:Show(nil, true) end
  elseif cmd == "help" then
    return false, true
  else
    return false
  end
  return true
end

function Misc.HookSlash()
  if Panoply.panoplyMiscSlash or type(Panoply.Slash) ~= "function" then return end
  Panoply.panoplyMiscSlash = true
  local slash = Panoply.Slash
  function Panoply:Slash(msg, ...)
    local done = Misc:Slash(msg)
    if done then return end
    -- /panoply help lists these too, after the others (0.9.5 phase 4A4: from the command registry, below)
    return slash(self, msg, ...)
  end
end
Panoply:On("ADDON_LOADED", function(_, name) if name == ADDON or name == "PanoplySuite" then Misc.HookSlash() end end)

-- 0.9.5 phase 4A4: the command registry (Core/HelpRegistry.lua). /panoply kit is on the Help page; Field Kit's chat lines print after
-- the others in /panoply help, as before.
if Panoply.Help and Panoply.Help.Command then
  Panoply.Help:Command({ key = "kit", usage = "/panoply kit", desc = "Open Field Kit: the vendor helper, the threat bar, this session and the death log.",
    group = "open", aliases = { "/panoply misc" }, chat = false, order = 150 })
  for i, l in ipairs(Misc.CHAT) do Panoply.Help:Command({ key = "misc:" .. i, page = false, chat = l, order = 900 + i }) end
end
