-- Panoply Suite settings rows. There is no Settings window any more (one-window menu, SPEC section 28):
-- this file holds the settings every page's gear can show (SUI.items, SUI.choices, SUI.partyRows, SUI.guideRows),
-- the one row builder the gear sheets use (SUI:BuildRows), the professions override list, and the
-- page in the game's own Options > AddOns list, which is one button.
-- The catalogue that says which gear each row lives in is UI/Catalog.lua.
local ADDON, Panoply = ...
local SUI = {}
Panoply.SettingsUI = SUI
Panoply.Settings = SUI
local Skin = Panoply.Skin

-- { key, label, tooltip, needs = feature }
SUI.items = {
  { "autoAccept", "Auto accept quests", "Accepts the quests on your route as soon as you talk to the quest giver." },
  { "autoTurnIn", "Auto hand in quests", "Hands in finished quests when you talk to the quest ender. If there is a choice of reward, it waits for you." },
  { "autoFly", "Auto fly", "On the flight map, picks the flight point the next step needs." },
  -- 0.9.7: "Level together (sync)" (syncEnabled) and "Share one route" (syncAdoptPartnerPlan) are on no page any more: the Level
  -- together switch is partyShare (SUI.partyRows below). Their saved keys stay in the saved file as they are.
  { "syncWaitForPartner", "Wait for my partner", "Before moving to the next step, waits until your partner has finished it too." },
  { "arrowShown", "Show the arrow", "A floating arrow that points to where the step happens." },
  { "blizzWaypoint", "Also place the game's map pin", "Puts the game's own waypoint pin on the map for each step.", needs = "blizzWaypoint" },
  { "windowLocked", "Lock the guide window", "Stops the guide window from being dragged by accident." },
  { "minimapButton", "Minimap button", "The shield by the minimap: left-click the guide, right-click Panoply Suite, Ctrl-click quick switches." },
  { "toasts", "Step complete banners", "Shows a short banner with the next step when you finish one." },
  { "soundOnStep", "Sound when a step is done", "Plays the quest-complete sound when a step finishes." },
  -- Nov 11 2026 ("turn planner off."): the leveling route is the written guides, so Keep planning means going on to the next one
  { "autoExtendPlan", "Keep planning", "When a written guide ends, goes on to the next one by itself." },
  { "autoReplan", "Fix the route by itself", "Re-plans when the route no longer fits: you dropped a quest, out-levelled it, went somewhere else, or a quest giver did not offer the next quest." },
  { "dropOnReplan", "Offer to drop unneeded quests on Replan", "After Replan, lists the quests your new route doesn't use (with their quest items) and asks before dropping any. Nothing is dropped unless you confirm." },
  { "autoSkipTrivial", "Skip grey quests", "Does not auto-accept grey (too easy) quests unless they are on your route." },
  { "autoSelectSingleReward", "Take the only reward", "When a quest has a single reward, takes it automatically." },
  { "profTracker", "Profession tracker", "A small window under the guide with your next profession step, even while you level." },
  -- 0.7.5 (WoW Forever only; Help's gear shows them only on Forever): the quest recorder (Engine/QuestRecorder.lua)
  { "questRecorder", "Save quests in new zones as I play", "WoW Forever: quietly saves quests from the new zones and for the Skyborne (who gave them, who takes them in, where the objectives were done) on this computer only, so they can be added to Panoply Suite later. Nothing is sent anywhere. /panoply recorded shows what was saved." },
  { "questRecorderNotice", "Tell me once per session in chat", "Says in chat, once per session, that the quest recorder is saving quests." },
  -- 0.9.4 (step 21): WoW Forever, while in a party: a line in party chat when an objective is done or a quest is ready to hand in
  { "partyQuestChat", "Tell my party about my quest progress", "When you are in a party, says in party chat when you finish a quest objective, when a quest is ready to hand in, and when you loot an item that starts a quest. Everyone in the party reads it. Off by default." },
  -- Step 2 B: which lines the Home page shows (Home's gear)
  { "homeNext", "Show my next step", "Shows your next guide step on Home." },
  { "homeNeeds", "Show what needs me", "Shows a talent point or spells waiting for you on Home." },
  { "homeGold", "Gold tile", "A tile on Home: all your characters' gold and the last 7 days' change (Muster's numbers)." },
  { "homeBags", "Bags tile", "A tile on Home: the free slots in this character's bags." },
  { "homeAuction", "Prices tile", "A tile on Home: how old your auction prices are (the Auctions page's scan)." },
}

-- 0.9.7 (Nov 18 2026): the levelling styles are gone. One setting says what the guide does with group quests, saved as
-- PanoplySuiteDB.groupQuests ("ask" | "do" | "skip"; its default and the one-time move from the old style are Core/Init.lua's). The
-- old key levellingStyle stays in the saved file, and nothing here reads it. Setup's three cards (UI/Wizard.lua) use these words.
SUI.GROUP_QUESTS = {
  values = { "ask", "do", "skip" },
  default = "ask",
  names = { ask = "Ask me each time", ["do"] = "Always include them", skip = "Leave them out" },
  text = {
    ask = "The guide asks when it reaches a group quest, and you decide then.",
    ["do"] = "Group quests always stay in your guide.",
    skip = "The guide leaves group quests out.",
  },
}
-- the saved choice, or "Ask me each time" while nothing valid is saved
function SUI.GroupQuests()
  local v = Panoply.db and Panoply.db.groupQuests
  return SUI.GROUP_QUESTS.names[v] and v or SUI.GROUP_QUESTS.default
end

-- Choices (every option is drawn; the catalogue turns each into a segmented row).
SUI.choices = {
  groupQuests = { label = "Group quests", values = SUI.GROUP_QUESTS.values, names = SUI.GROUP_QUESTS.names,
    tip = "What the guide does with quests that need a group, such as elite and dungeon quests. Ask me each time (default): the guide asks when it reaches one. Always include them: they stay in your guide. Leave them out: the guide skips them. A quest you already answered keeps your answer.",
    get = function() return SUI.GroupQuests() end,
    set = function(v) if SUI.GROUP_QUESTS.names[v] then Panoply:SetOption("groupQuests", v) end end },
  -- Nov 11 2026 ("turn planner off."): this row is no longer on any page (UI/Catalog.lua): the written guides are the only route,
  -- and the planner choice below does nothing (Engine/Guides.lua SetMode refuses it). Kept for the suite's older planner tests.
  -- Nov 10 2026: which leveling route this character follows (Engine/Guides.lua). Saved per character as routeSource, as
  -- /panoply route saves it: the default ("auto", the written guides) is not saved at all. "guides" (only /panoply route guides sets
  -- it) is a written-guides choice too, so it shows as Written guides here and choosing Written guides leaves it as it is.
  routeSource = { label = "Leveling route", values = { "auto", "planner" },
    names = { auto = "Written guides", planner = "Planner (fallback)" },
    tip = "Written guides (default): your route is the written leveling guide for your race and faction, picked up from where this character is. Panoply Suite's planner fills in only where no written guide covers you. Planner (fallback): the planner plans everything and the written guides are off for this character. Changing this builds the route again right away.",
    get = function() return (Panoply.Guides and Panoply.Guides:Mode() == "planner") and "planner" or "auto" end,
    set = function(v)
      local G = Panoply.Guides
      if not (G and Panoply.cdb) then return end
      local was = G:Mode()
      if v == "auto" and was ~= "planner" then return end
      if v == was or not G:SetMode(v) then return end
      Panoply:Print(G:Status())
      if Panoply.NoGuide then Panoply.NoGuide:Update(true) end
      Panoply:Fire("OPTION_CHANGED", "routeSource", v)
      if Panoply.cdb.setupDone or #Panoply.Engine.steps > 0 then Panoply:Replan("settings") end
    end },
  -- Nov 2026 (step 7): WoW Forever with Polestar's engine: which guide it follows. The leveling guide, or a guide added to this
  -- computer from outside (a Polestar guide pack with the id PolestarEngine.ADDED_PACK; none ships yet). Each keeps its own place.
  guideSource = { label = "Guide source", values = { "leveling", "added" },
    names = { leveling = "Leveling guide", added = "Added guide" },
    tip = "Leveling guide (default): the leveling guide for your race and faction. Added guide: a guide that was added to this computer, when there is one. Each keeps its own step, so you can switch back to the leveling guide at any time and carry on where you were.",
    get = function() return Panoply.PolestarEngine and Panoply.PolestarEngine:Source() or "leveling" end,
    set = function(v)
      local PE = Panoply.PolestarEngine
      if not PE then return end
      if v == PE:Source() then return end
      local ok, why = PE:SetSource(v)
      if ok then Panoply:Print("Guide source: " .. PE.SOURCE_NAMES[PE:Source()] .. " (" .. tostring(Panoply.Engine.title) .. ").")
      else Panoply:Print(why) end
    end },
  iconStyle = { label = "Icon style", values = { "panoply", "wow" },
    names = { wow = "WoW icons", panoply = "Panoply Suite icons" },
    tip = "Panoply Suite icons (default): Panoply Suite's own brass icons on its tabs, buttons and map pins. WoW icons: the game's own built-in icons there instead. Item, ability, quest and bag pictures are always the game's own icons either way. Changes right away.",
    get = function() return Panoply.db.iconStyle == "wow" and "wow" or "panoply" end,
    set = function(v) Panoply:SetOption("iconStyle", v) end },
  -- 0.9.5 phase 4K (spec 06a section 3.4): the guide window's layout. By width (default): Compact below UI.COMPACT_W, Full above.
  guideWindowSize = { label = "Window layout", values = { "auto", "full", "compact" },
    names = { auto = "By width", full = "Full", compact = "Compact" },
    tip = "By width (default): the guide window shows every section, and only the step, the trip line and the buttons when you make it narrow. Full: every section at any width. Compact: the step, the trip line and the buttons, with Up next and Profession on one line each.",
    get = function() return Panoply.db.guideWindowSize or "auto" end,
    set = function(v) Panoply:SetOption("guideWindowSize", v) end },
  profGuide = { label = "Guide", values = { "off", "only", "interleave" },
    names = { interleave = "Both", only = "Professions", off = "Leveling" },
    tip = "The same switch as on the guide window. Leveling: your route. Professions: your profession plan step by step. Both: profession steps join your route when the place is close by. Each guide keeps its own step.",
    get = function() return Panoply.ProfGuide and Panoply.ProfGuide:Mode() or Panoply.db.profGuide or "interleave" end,
    set = function(v)
      if Panoply.ProfGuide and Panoply.cdb then Panoply.ProfGuide:SetActive(Panoply.ProfGuide.MODE_TO_GUIDE[v]) else Panoply:SetOption("profGuide", v) end
    end },
  profStrategy = { label = "Plans pick", values = { "cheapest", "fastest" },
    names = { cheapest = "Cheapest recipes", fastest = "Fastest recipes" },
    tip = "Cheapest: fewest gold, even if it takes more crafts. Fastest: fewest crafts and trips.",
    get = function() return Panoply.db.profStrategy or "cheapest" end,
    set = function(v) if Panoply.ProfPlans then Panoply.ProfPlans:SetAllStrategy(v) else Panoply:SetOption("profStrategy", v) end end },
  profSpec = { label = "Blacksmithing at 200+", values = { "", "Armorsmith", "Weaponsmith" },
    names = { [""] = "No specialisation yet", Armorsmith = "Armorsmith", Weaponsmith = "Weaponsmith" },
    tip = "Only matters from skill 200 (level 40 quest). Leave it unset to keep both paths open; you can pick later.",
    get = function() return (Panoply.cdb and Panoply.cdb.profSpec and Panoply.cdb.profSpec.Blacksmithing) or "" end,
    set = function(v)
      Panoply.cdb.profSpec = Panoply.cdb.profSpec or {}
      Panoply.cdb.profSpec.Blacksmithing = v ~= "" and v or nil
      if Panoply.ProfGuide then Panoply.ProfGuide:Invalidate(); Panoply.ProfGuide:Refresh("spec") end
      Panoply:Fire("OPTION_CHANGED", "profSpec", v)
    end },
}

-------------------------------------------------------------------------------
-- The page in the game's own Interface / Settings > AddOns list: one button, no settings.
-------------------------------------------------------------------------------
function SUI:RegisterBlizzard()
  local canvas = CreateFrame("Frame")
  canvas.name = "Panoply Suite"
  canvas:SetSize(640, 200)
  -- skin v3 panel (no caps: the game's settings frame clips anything outside the canvas)
  Skin.Panel(canvas, 0.95, nil, "L", true)
  local crest = canvas:CreateTexture(nil, "ARTWORK"); crest:SetSize(44, 44); Skin.Logo(crest)
  crest:SetPoint("TOPLEFT", canvas, "TOPLEFT", 10, -8)
  local t = Skin.Heading(canvas, 18, "Panoply Suite"); t:SetPoint("TOPLEFT", canvas, "TOPLEFT", 72, -18)
  local d = Skin.Text(canvas, 11, Skin.colors.inkSoft); d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
  d:SetText("Levelling and professions guide for two. Every setting is in the Panoply Suite window: type /panoply, or click the button.")
  local open = Skin.Button(canvas, "Open Panoply Suite", 200, 28, function() Panoply.Menu:Open() end,
    "Open Panoply Suite", "The one Panoply Suite window: guide, hall, bags and every setting behind each page's gear.")
  open:SetPoint("TOPLEFT", canvas, "TOPLEFT", 72, -92)
  t:SetWidth(640 - 72 - 16); d:SetWidth(640 - 72 - 16)
  self.canvas = canvas
  local S = _G.Settings
  if S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory then
    local ok, cat = pcall(S.RegisterCanvasLayoutCategory, canvas, "Panoply Suite")
    if ok and cat then pcall(S.RegisterAddOnCategory, cat); self.category = cat; self.registeredWith = "Settings" return true end
  end
  if _G.InterfaceOptions_AddCategory then pcall(InterfaceOptions_AddCategory, canvas); self.registeredWith = "InterfaceOptions" return true end
  return false
end

-------------------------------------------------------------------------------
-- Manual override for the auto-detected professions (Professions page > gear; nothing asks you).
-------------------------------------------------------------------------------
function SUI.FoundText()
  local pr = Panoply.cdb and Panoply.cdb.professions
  local list = {}
  for _, n in ipairs(pr and pr.primary or {}) do list[#list + 1] = n end
  for _, n in ipairs(pr and pr.secondary or {}) do list[#list + 1] = n end
  if #list == 0 then return "none yet" end
  local t = table.concat(list, ", ")
  if #t > 34 then t = list[1] .. (#list > 1 and (" + " .. (#list - 1) .. " more") or "") end
  return t
end

function SUI:OverrideLine(name)
  local D = Panoply.ProfDetect
  local det = Panoply.cdb and Panoply.cdb.professions and Panoply.cdb.professions.detected or {}
  local d = det[name]
  local found = d and ("found, " .. (d.rank or 0) .. "/" .. (d.max or 0)) or "not learned"
  return ("%s: %s (%s)"):format(name, D.OVERRIDE_LABELS[D:Override(name)], found)
end

function SUI:OpenOverrides()
  local PD, D = Panoply.ProfData, Panoply.ProfDetect
  if not self.overrideFrame then
    local f = Skin.Window("PanoplySuiteProfOverride", 360, 70 + #PD.ORDER * 26, "Professions", "Found by themselves - change by hand", nil, "Craft")   -- 4J: its own header icon
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if f.SetFrameStrata then f:SetFrameStrata("DIALOG") end
    local t = Skin.Text(f, 10, Skin.colors.textSoft or Skin.colors.text)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46); t:SetWidth(330)
    t:SetText("Click a profession to cycle: Automatic, Always plan, Never plan.")
    f.rows = {}
    for i, name in ipairs(PD.ORDER) do
      local b = Skin.Button(f, "", 328, 22, function(btn) D:CycleOverride(name); btn:Refresh() end, name,
        "Automatic: planned when you have learned it. Always plan: plan it even before you learned it. Never plan: hide it.")
      function b:Refresh() self.label:SetText(SUI:OverrideLine(name)) end
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -64 - (i - 1) * 26)
      b.prof = name
      f.rows[i] = b
    end
    self.overrideFrame = f
    -- Nov 2026: measured (the words under the title wrap and the rows start under them, at any text size), and a resize grip:
    -- the rows take the width; the box is as tall as its list of professions
    local function lay(w)
      local hb = (f.panoplyHeaderBottom or 50) + 6
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -hb); t:SetWidth(w - 32)
      local y = hb + math.ceil(Skin.TextHeight(t, w - 32)) + 8
      for _, b in ipairs(f.rows) do
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -y); b:SetWidth(w - 32)
        y = y + 26
      end
      f:SetHeight(y + 22)                          -- 22: the last row stays clear of the grip
    end
    lay(f:GetWidth())
    Skin.Resizable(f, { key = "profOverride", minW = 360, minH = 120, onSize = function(w, _, done) if done then lay(w) end end })
  end
  for _, b in ipairs(self.overrideFrame.rows) do b:Refresh() end
  -- opened from the Panoply Suite window: it closes with it
  local menu = Panoply.Menu and Panoply.Menu.frame
  if menu and menu:IsShown() then Skin.Popups:Child(self.overrideFrame, menu) else self.overrideFrame.panoplyDialogParent = nil end
  self.overrideFrame:Show()
  return self.overrideFrame
end

-------------------------------------------------------------------------------
-- The row builder every gear sheet uses. Rows come from a catalogue section or from a module's
-- options: check, slider, choice (every option drawn), segmented, button, heading, typechecks,
-- readout (text that refreshes) and custom (a build function). Returns the widgets made and the y
-- below them. Each widget carries panoplyKey (the setting it edits), panoplyRow (its row) and panoplyRowY (its
-- top inside the parent), so a search result can scroll to it.
-------------------------------------------------------------------------------
function SUI:BuildRows(parent, rows, x, y, width, ink)
  local SP = Skin.SP
  local made = {}
  local inner = width - 40
  for _, r in ipairs(rows or {}) do
    if not r.only or r.only() then
      local w
      local top = y
      if r.type == "check" then
        w = Skin.Check(parent, r.label, r.get and { get = r.get, set = r.set } or r.key, r.onChange, r.help or r.tip, ink)
        local ind = r.indent and 24 or 0   -- a sub-option sits indented under its parent
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2 + ind, y)
        local _, ch = w:FitLabel(inner - 30 - ind)
        y = y - math.max(24, ch + 6)
        w.panoplyParentKey = r.parent
      elseif r.type == "slider" then
        local key = r.key
        w = Skin.Slider(parent, r.label, r.min or 0, r.max or 1, r.step or 0.05,
          r.get or function() return Panoply.db[key] or r.min or 0 end,
          r.set or function(v) Panoply:SetOption(key, v) end, r.help or r.tip, r.fmt)
        w:SetWidth(math.min(260, inner))
        -- the label is one line as wide as the row: without a width the estimate wrapped a long label onto three lines and left a
        -- tall empty gap above the slider (seen under EXACT SIZES in the Guide gear)
        w.label:SetWidth(inner - 6)
        y = y - SP.xs - Skin.TextHeight(w.label, inner - 6) - 5
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 6, y)
        top = y + 5 + Skin.TextHeight(w.label)
        y = y - 16 - SP.m
      elseif r.type == "choice" or r.type == "segmented" then
        local key = r.key
        w = Skin.Segmented(parent, { label = r.label, tip = r.help or r.tip, values = r.values,
          get = r.get or function() return Panoply.db[key] end,
          set = r.set or function(v) Panoply:SetOption(key, v) end })
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
        local h = w:Layout(inner - 6)
        y = y - h - SP.m
      elseif r.type == "button" then
        w = Skin.Button(parent, r.label, math.min(240, inner), 24, r.func, r.label, r.help or r.tip)
        local _, bh = Skin.FitButton(w, 120, inner)
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
        y = y - bh - SP.s
      elseif r.type == "heading" then
        y = y - SP.s
        top = y
        w = Skin.Text(parent, 13, Skin.colors.heading, nil, true)
        w:SetWidth(inner)
        w:SetText(r.label)
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
        y = y - Skin.TextHeight(w, inner) - SP.s
      elseif r.type == "subheading" then
        -- 0.7.3.7: a small line under a heading ("World map", "Minimap") that names the group of rows below it
        w = Skin.Text(parent, 12, Skin.colors.inkSoft)
        w:SetWidth(inner)
        w:SetText(r.label)
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
        y = y - Skin.TextHeight(w, inner) - SP.xs
      elseif r.type == "readout" then
        w = Skin.Ink(parent, 11, Skin.colors.inkSoft)
        w:SetWidth(inner - 4)
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y)
        local textFn = r.text
        function w:Refresh()
          self:SetText(textFn())
          local h = Skin.TextHeight(self, inner - 4)
          self:SetHeight(h)
          self.panoplyHeight = h
        end
        w:Refresh()
        w.panoplyReadout = true
        y = y - w.panoplyHeight - SP.m
      elseif r.type == "custom" and r.build then
        w, y = r.build(parent, x, y, width, ink)
        y = y or top
      elseif r.type == "typechecks" and Panoply.Gathering then
        local G = Panoply.Gathering
        local half = math.floor(width / 2)
        local rowY = y
        local rowH = 0
        for i, t in ipairs(G.TYPES) do
          if i > 1 and (i - 1) % 2 == 0 then rowY = rowY - math.max(24, rowH + 6) rowH = 0 end
          local cb = Skin.Check(parent, G.LABEL[t], { get = function() return Panoply.db.gatherShow and Panoply.db.gatherShow[t] end,
            set = function(v) G:SetShown(t, v) end }, nil, "Show " .. G.LABEL[t]:lower() .. " on your maps.", ink)
          cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2 + ((i - 1) % 2) * half, rowY)
          local cw, ch = cb:FitLabel(half - 60)
          rowH = math.max(rowH, ch)
          local ic = parent:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18); Skin.SetIcon(ic, G.ICON[t])
          ic:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2 + ((i - 1) % 2) * half + cw + 6, rowY)
          cb.panoplyKey = "gatherShow:" .. t
          cb.panoplyRowY = -rowY
          cb.panoplyRow = r
          made[#made + 1] = cb
        end
        y = rowY - math.max(24, rowH + 6) - SP.xs
      end
      if w then
        w.panoplyKey = w.panoplyKey or r.key or r.id
        w.panoplyRow = r
        w.panoplyRowY = -top
        made[#made + 1] = w
      end
    end
  end
  return made, y
end

-- Page title, icon and explanation; returns the y below them (measured, so long text wraps).
function SUI.PageHead(parent, title, text, icon, x, y, width)
  local SP = Skin.SP
  local ic = parent:CreateTexture(nil, "ARTWORK"); ic:SetSize(30, 30); Skin.SetIcon(ic, icon or "Settings")
  ic:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local tw = width - x - 40 - 16
  local h = Skin.Heading(parent, 15, title); h:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 40, y - 2); h:SetWidth(tw)
  local hh = Skin.TextHeight(h, tw)
  local t = Skin.Ink(parent, 11, Skin.colors.inkSoft); t:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 40, y - 2 - hh - SP.xs); t:SetWidth(tw)
  t:SetText(text or "")
  local bottom = math.max(30, 2 + hh + SP.xs + Skin.TextHeight(t, tw))
  return h, t, y - bottom - SP.l
end

-- 0.9.7 (Nov 18 2026): Level together on WoW Forever. One switch, saved as PanoplySuiteDB.partyShare (on unless it was turned
-- off; the default is Core/Init.lua's). What it shares is our decision of Nov 18: the guide, step, level, XP, class, race and
-- version, with the party only.
SUI.partyRows = {
  { type = "check", key = "partyShare", label = "Level together", default = true,
    tip = "When you are in a party, shares your guide, step, level, XP, class, race and Panoply Suite version with your party, and shows theirs, so you can level together. Only your party gets it. Off: nothing is sent and nothing is shown.",
    get = function() return Panoply.db.partyShare ~= false end,
    set = function(v) Panoply:SetOption("partyShare", v and true or false) end },
}

-- The guide window's sliders and checks (moved to Guide > gear by the catalogue).
SUI.guideRows = {
  { type = "slider", key = "stepsShown", label = "Steps shown", min = 1, max = 5, step = 1, fmt = "%d",
    tip = "How many steps the guide window lists: the current one plus what comes next. Works in Leveling, Professions and Both." },
  { type = "slider", key = "windowAlpha", label = "Window background", min = 0, max = 1, step = 0.05,
    tip = "How see-through the guide window's background is. The text always stays readable." },
  { type = "slider", key = "arrowAlpha", label = "Arrow opacity", min = 0.1, max = 1, step = 0.05, tip = "How see-through the arrow is." },
  { type = "slider", key = "arrowScale", label = "Arrow size", min = Panoply.Look.ARROW_MIN, max = Panoply.Look.ARROW_MAX, step = 0.05, tip = "How big the arrow is." },
  { type = "slider", key = "windowScale", label = "Window size", min = Panoply.Look.WINDOW_MIN, max = Panoply.Look.WINDOW_MAX, step = 0.05,
    tip = "Makes every Panoply Suite window bigger or smaller: the guide, this menu, the profession tracker and the others. A window never grows past your screen." },
  { type = "check", key = "windowLocked", label = "Lock the guide window", tip = "Stops dragging and hides the resize corner." },
  -- 0.9.5 (spec 1.2, Shine + Toast): the banner for something Panoply Suite noticed completing by itself (Panoply.Kit.Toast). A NEW account
  -- key, kitToasts, on by default.
  { type = "check", key = "kitToasts", label = "Completion banners",
    tip = "A short banner when Panoply Suite notices something completed by itself, such as a Legacy challenge." },
  { type = "check", key = "arrowLocked", label = "Lock the arrow", tip = "The arrow can't be dragged and mouse clicks go straight through it." },
  { type = "check", key = "arrowShown", label = "Show the arrow" },
  { type = "check", key = "corpseArrow", label = "Corpse arrow when dead", tip = "While you are a ghost, a separate arrow with a skull points to your corpse and shows the yards left. The quest arrow waits until you are alive again." },
  { type = "check", key = "windowFade", label = "Fade the window when the mouse is away", tip = "The guide window fades out until you point at it." },
  { type = "slider", key = "windowFadeAlpha", label = "Faded opacity", min = 0.1, max = 0.9, step = 0.05, tip = "How faded the window gets while the mouse is away." },
  { type = "check", key = "hideInCombat", label = "Hide guide window in combat", tip = "The guide window and the profession tracker fade out when a fight starts and fade back in when it ends. The arrow has its own setting below." },
  { type = "check", key = "hideArrowInCombat", label = "Hide arrow in combat",
    tip = "Off: the arrow stays and keeps pointing during fights. On: it fades out in combat and comes back after the fight." },
  -- 0.9.5 phase 4K: the Guide page's route look-ahead and Home's two new tiles (NEW account keys; UI/Menu.lua and UI/Home.lua)
  { type = "slider", key = "guideRouteSteps", label = "Steps in the route list", min = 3, max = 20, step = 1, fmt = "%d",
    tip = "How many steps the Guide page's route lists, from the one you are on." },
  { type = "check", key = "homeLegacy", label = "Legacy tile", tip = "WoW Forever: your account's Legacy points and what this character has not spent." },
  { type = "check", key = "homeUpgrade", label = "Next upgrade tile", tip = "The best gear upgrade the Class page's Gear tab shows." },
}
