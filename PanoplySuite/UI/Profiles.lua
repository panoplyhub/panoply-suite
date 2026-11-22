-- Panoply Suite: the Profiles page of the one window (SPEC section 29, our order of Nov 3 2026). Rebuilt in 0.9.5 phase 4F
-- (docs/specs/page-redesigns-v1.md section 6) with the shared visual system (UI/KitParts.lua). The list and the choices are
-- Engine/Profiles.lua's; what a profile covers and how it is saved and applied: Engine/Profiles.lua and SPEC 29.1 to 29.3.
--
--   The top strip (pinned)  the class crest, the character's name in its class colour, the realm, "uses" and a profile dropdown.
--                           Changing it applies at once, shows a banner "Talon now uses Forever." and an Undo button beside it.
--   Profiles                "New profile" (a small form: the name, and Standard settings or a copy of a profile to start from),
--                           then one row per profile: its name, "In use here", the characters using it as class-coloured names,
--                           and a ... menu on the row: Rename, Duplicate, Reset to defaults, Delete. Each acts on that row only:
--                           there is no selection. Delete is red only in the menu and in its question; the question names every
--                           character using the profile and makes the player pick the profile they move to. Default can't be
--                           deleted. The row of the profile in use holds "Window scale: 100%" with the slider in an expander.
--   Characters              one row per character Panoply Suite knows (Muster's list): a tick box (unticked to start), the crest,
--                           the name in class colour, level and realm, and a profile dropdown: changing it is the whole operation.
--                           Other characters' rows say "Takes effect next login". With any ticked, a bar appears: "Set 2
--                           characters to [profile] · Apply". There is no "copy into another profile": Duplicate makes a new one.
-- Bands: Wide, Profiles (about 40%) beside Characters; Medium and Narrow, one column, Profiles first. Only the part under the strip
-- scrolls. No popups: every form and question opens on the page, under the row it is about.
local ADDON, Panoply = ...
local Menu, Skin, Kit, C = Panoply.Menu, Panoply.Skin, Panoply.Kit, Panoply.Compat
local P = Panoply.Profiles
local Cat = Panoply.Catalog
local Prof = {}
Panoply.ProfilesUI = Prof

local SP, TH, TW = Skin.SP, Skin.TextHeight, Skin.TextWidth
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local function setColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

Prof.GRIP = 22         -- room left under the scrolling part for the window's resize grip
Prof.DD_W = 170        -- a character row's profile dropdown (narrower when the column is)
Prof.CREST = 20

-- what the page is doing: mode = "rename" | "duplicate" | "reset" | "delete" on the row of profile `target`; newOpen = the New
-- profile form is open (newFrom: nil for the standard settings, else the profile to copy); moveTo = the profile Delete moves the
-- characters to; ticks = the ticked characters; bulkTo = the profile the bar sets; undo = the profile this character used before
-- the last switch; note / err = what the last action did / why it could not
Prof.state = { ticks = {} }

local function plural(n, one, many) return n == 1 and ("1 " .. one) or (n .. " " .. (many or (one .. "s"))) end

local function classCode(c)
  local A = Panoply.Alts
  if A and A.ClassColor and A.ColorCode and c.classFile then return A.ColorCode(A.ClassColor(c.classFile)) end
  return ""
end

-- "Alice, Bob (Whitemane), Partner": class colours when Muster knows the class; the realm when it is not yours
local function whoText(list, plain)
  local mr = P:Me()
  local parts = {}
  for _, c in ipairs(list) do
    local nm = c.name .. ((mr and c.realm ~= mr) and (" (" .. c.realm .. ")") or "")
    local code = plain and "" or classCode(c)
    parts[#parts + 1] = code ~= "" and (code .. nm .. "|r") or nm
  end
  return table.concat(parts, ", ")
end
Prof.WhoText = whoText

-- the class crest: the game's class circles, cut to the class
local CREST = "Interface\\TargetingFrame\\UI-Classes-Circles"
local CREST_CUT = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }
local function crest(tex, cls)
  local t = cls and (type(_G.CLASS_ICON_TCOORDS) == "table" and _G.CLASS_ICON_TCOORDS[cls] or CREST_CUT[cls])
  if not t then tex:Hide() return end
  tex:SetTexture(CREST)
  if tex.SetTexCoord then tex:SetTexCoord(t[1], t[2], t[3], t[4]) end
  tex.panoplySlot = "icon.class." .. tostring(cls):lower()
  tex:Show()
end
local function classColor(cls)
  local A = Panoply.Alts
  return (cls and A and A.ClassColor and A.ClassColor(cls)) or Kit.Color("text.primary")
end

-- the ? of the Profiles heading (spec 6.2: "What's in a profile" as a short list, and what isn't)
Prof.WHATS_IN = "In a profile:\n- the order of the pages\n- each page's settings\n- window positions and sizes\n- tracker, map and trail options\n- window scale\n\nNot in a profile: quest progress, Muster items, recordings."
Prof.CHARS_HELP = "Each character uses one profile. Change a character's dropdown to switch it; tick several to set them all at once. Characters you are not playing pick up the change the next time they log in."


-------------------------------------------------------------------------------
-- Small parts
-------------------------------------------------------------------------------
local function redraw() if Menu.RefreshCurrent then Menu:RefreshCurrent() end end

local function place(fs, parent, x, y, w)
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(max(10, w))
  local h = ceil(TH(fs, max(10, w)))
  fs:SetHeight(max(1, h))
  return h
end

-- a name box (not a search box: no magnifier)
local function nameBox(parent, placeholder, onEnter, onEscape)
  local box = Skin.Input(parent, 220, 26, placeholder)
  if box.icon then box.icon:Hide() end
  if box.SetTextInsets then box:SetTextInsets(8, 6, 0, 0) end
  if box.placeholder then box.placeholder:ClearAllPoints(); box.placeholder:SetPoint("LEFT", box, "LEFT", 8, 0) end
  box:SetScript("OnTextChanged", function(b)
    if b.placeholder then if (b:GetText() or "") == "" then b.placeholder:Show() else b.placeholder:Hide() end end
  end)
  box:SetScript("OnEnterPressed", function(b) b:ClearFocus() onEnter() end)
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() onEscape() end)
  return box
end
local function setBox(box, text, placeholder)
  box:SetText(text or "")
  if box.placeholder then
    if placeholder then box.placeholder:SetText(placeholder) end
    if (text or "") == "" then box.placeholder:Show() else box.placeholder:Hide() end
  end
end

-- Every character that uses a profile: the ones Muster knows (with class and level), and any other character the profile store still
-- points at it (Muster may have forgotten one; Delete moves those too, so the question names them). Default is everyone else.
function Prof.UsersOf(profile)
  local out = P:UsedBy(profile)
  if profile == P.DEFAULT then return out end
  local seen = {}
  for _, c in ipairs(out) do seen[P.Key(c.realm, c.name)] = true end
  local d = P:Data()
  local extra = {}
  for k, v in pairs(d and d.use or {}) do
    if v == profile and not seen[k] then
      local realm, name = tostring(k):match("^(.-)\1(.*)$")
      if realm and name and name ~= "" then extra[#extra + 1] = { realm = realm, name = name } end
    end
  end
  table.sort(extra, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.realm < b.realm end)
  for _, c in ipairs(extra) do out[#out + 1] = c end
  return out
end
local usersOf = Prof.UsersOf

-- the profiles as dropdown items; `except` is left out
local function profileItems(except)
  local out = {}
  for _, n in ipairs(P:Names()) do if n ~= except then out[#out + 1] = { text = n, value = n } end end
  return out
end

-------------------------------------------------------------------------------
-- Building the page (once)
-------------------------------------------------------------------------------
Menu:RegisterTab("Profiles", function(p)
  Prof.page = p
  -- the top strip
  local st = Kit.Surface(p, 1)
  st.crest = st:CreateTexture(nil, "ARTWORK"); st.crest:SetSize(24, 24)
  st.name = Skin.Name(st, 15, Kit.Color("text.primary"))
  st.realm = Skin.Ink(st, 12, Kit.Color("text.muted"))
  st.uses = Skin.Ink(st, 12, Kit.Color("text.muted")); st.uses:SetText("uses")
  for _, fs in ipairs({ st.name, st.realm, st.uses }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  st.dd = Kit.Dropdown(st, { page = "profiles", width = 170, items = function() return profileItems() end,
    get = function() local mr, mn = P:Me() return mr and P:Of(mr, mn) or P.DEFAULT end,
    set = function(v) Prof:UseHere(v) end, tip = "The profile this character uses", tipBody = "Pick another one: it applies at once." })
  st.undo = Skin.Button(st, "Undo", 70, 24, function() Prof:Undo() end, "Undo", "Back to the profile this character used before.")
  st.note = Skin.Ink(st, 12, Kit.Color("text.muted"))
  p.strip = st
  -- the scrolling part
  p.area = Skin.ScrollArea(p)
  local ct = p.area.content
  p.content = ct
  -- Profiles
  p.profHead = Kit.SectionHeader(ct, { title = "Profiles", help = Prof.WHATS_IN })
  p.newBtn = Skin.Button(ct, "New profile", 120, 26, function() Prof:OpenNew() end, "New profile",
    "A new profile: give it a name, and start from the standard settings or from a copy of another profile.")
  Skin.FitButton(p.newBtn, 110, 200)
  local nf = Kit.Surface(ct, 2)
  nf.label = Skin.Ink(nf, 12, Kit.Color("text.muted")); nf.label:SetText("Name")
  nf.box = nameBox(nf, "Name of the new profile", function() Prof:SubmitNew() end, function() Prof:Cancel() end)
  nf.fromLabel = Skin.Ink(nf, 12, Kit.Color("text.muted")); nf.fromLabel:SetText("Start from")
  nf.from = Kit.Dropdown(nf, { page = "profiles", width = 200,
    items = function()
      local out = { { text = "Standard settings", value = "" } }
      for _, n in ipairs(P:Names()) do out[#out + 1] = { text = "A copy of " .. n, value = n } end
      return out
    end,
    get = function() return Prof.state.newFrom or "" end,
    set = function(v) Prof.state.newFrom = v ~= "" and v or nil end,
    tip = "Start from", tipBody = "The standard settings, or a copy of one of your profiles." })
  nf.ok = Skin.Button(nf, "Create", 90, 26, function() Prof:SubmitNew() end, "Create", "Make the profile.")
  nf.cancel = Skin.Button(nf, "Cancel", 90, 26, function() Prof:Cancel() end, "Cancel", "Close this without changing anything.")
  nf.err = Skin.Ink(nf, 11, Skin.colors.warn)
  nf:Hide()
  p.newForm = nf
  p.prows = {}
  -- the form and the question that open under a row (one of each: only one row is being changed at a time)
  local rf = Kit.Surface(ct, 2)
  rf.label = Skin.Ink(rf, 12, Kit.Color("text.muted"))
  rf.box = nameBox(rf, "New name", function() Prof:SubmitRow() end, function() Prof:Cancel() end)
  rf.ok = Skin.Button(rf, "Rename", 90, 26, function() Prof:SubmitRow() end, "Save", "Save the name.")
  rf.cancel = Skin.Button(rf, "Cancel", 90, 26, function() Prof:Cancel() end, "Cancel", "Close this without changing anything.")
  rf.err = Skin.Ink(rf, 11, Skin.colors.warn)
  rf:Hide()
  p.rowForm = rf
  local ra = Kit.Surface(ct, 2)
  ra.text = Skin.Ink(ra, 12, Skin.colors.warn)
  ra.moveLabel = Skin.Ink(ra, 12, Kit.Color("text.muted")); ra.moveLabel:SetText("Move them to")
  ra.move = Kit.Dropdown(ra, { page = "profiles", width = 180, empty = "Pick a profile",
    items = function() return profileItems(Prof.state.target) end,
    get = function() return Prof.state.moveTo end,
    set = function(v) Prof.state.moveTo = v redraw() end,
    tip = "Move them to", tipBody = "The profile the characters using this one use from now on." })
  ra.yes = Skin.Button(ra, "Delete", 100, 26, function() Prof:Confirm() end, "Yes", "Do it.")
  ra.yes.panoplyDanger = true; ra.yes:Paint("up")
  ra.no = Skin.Button(ra, "Keep it", 90, 26, function() Prof:Cancel() end, "Keep it", "Do nothing.")
  ra:Hide()
  p.rowAsk = ra
  -- the window scale slider (spec 1.5 / 6.2: on the row of the profile in use, in an expander)
  local sc = CreateFrame("Frame", nil, ct)
  sc.panoplyGapOK = true
  sc:Hide()
  p.scaleBox = sc
  -- Characters
  p.charHead = Kit.SectionHeader(ct, { title = "Characters", help = Prof.CHARS_HELP })
  local bar = Kit.Surface(ct, 2)
  bar.text = Skin.Name(bar, 12, Kit.Color("text.primary"))
  if bar.text.SetWordWrap then bar.text:SetWordWrap(false) end
  bar.dd = Kit.Dropdown(bar, { page = "profiles", width = 160, empty = "Pick a profile", items = function() return profileItems() end,
    get = function() return Prof.state.bulkTo end, set = function(v) Prof.state.bulkTo = v redraw() end,
    tip = "Set the ticked characters to", tipBody = "The profile the ticked characters use." })
  bar.apply = Skin.Button(bar, "Apply", 80, 26, function() Prof:ApplyBulk() end, "Apply", "Switch every ticked character to this profile.")
  bar.apply.panoplyAccent = true
  bar.clear = Skin.Button(bar, "Clear", 70, 26, function() Prof:ClearTicks() end, "Clear", "Untick every character.")
  bar:Hide()
  p.bulk = bar
  p.crows = {}
  if Panoply.History then Panoply.History:State("profiles", {
    get = function() return { scroll = p.area and p.area.GetVerticalScroll and p.area:GetVerticalScroll() or 0 } end,
    set = function(s) if type(s) == "table" then Prof.pendingScroll = s.scroll end end,
    key = function() return "profiles" end,
  }) end
end, function(p) Prof:Refresh() Prof:Layout(p) end)

-------------------------------------------------------------------------------
-- State changes
-------------------------------------------------------------------------------
local function clear(st) st.mode, st.target, st.newOpen, st.err, st.moveTo = nil, nil, nil, nil, nil end

function Prof:Cancel()
  local st = self.state
  clear(st)
  local p = self.page
  if p then p.newForm.box:ClearFocus(); p.rowForm.box:ClearFocus() end
  redraw()
end

function Prof:OpenNew()
  local st = self.state
  if P:Count() >= P.MAX_PROFILES then st.note = ("You can have at most %d profiles."):format(P.MAX_PROFILES) redraw() return end
  clear(st)
  st.newOpen, st.newFrom, st.note = true, nil, nil
  local p = self.page
  if p then setBox(p.newForm.box, "", "Name of the new profile") end
  redraw()
  if p and p.newForm.box.SetFocus then p.newForm.box:SetFocus() end
end

function Prof:SubmitNew()
  local st = self.state
  local p = self.page
  if not (p and st.newOpen) then return end
  local text = p.newForm.box:GetText() or ""
  local from = st.newFrom
  local name, why
  if from then name, why = P:Copy(from, text) else name, why = P:New(text) end
  if not name then st.err = why redraw() return end
  st.note = from and ("Made %s as a copy of %s."):format(name, from) or ("Made the profile %s."):format(name)
  clear(st)
  st.newFrom = nil
  p.newForm.box:ClearFocus()
  redraw()
end

-- the ... menu of a row: Rename, Duplicate, Reset to defaults, Delete (Default has no Rename and no Delete)
function Prof:MenuItems(name)
  local items = {}
  if name ~= P.DEFAULT then items[#items + 1] = { text = "Rename", tip = "Give this profile another name.", func = function() Prof:Begin("rename", name) end } end
  items[#items + 1] = { text = "Duplicate", tip = "A new profile that starts as a copy of this one.", func = function() Prof:Begin("duplicate", name) end }
  items[#items + 1] = { text = "Reset to defaults", tip = "Put this profile back to Panoply Suite's standard settings.", func = function() Prof:Begin("reset", name) end }
  if name ~= P.DEFAULT then
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = Skin.Code(Skin.colors.loss) .. "Delete|r", tip = "Delete this profile. You pick the profile its characters move to.",
      func = function() Prof:Begin("delete", name) end }
  end
  return items
end

function Prof:Begin(mode, name)
  local st = self.state
  if not P:Exists(name) then return end
  if (mode == "rename" or mode == "delete") and name == P.DEFAULT then return end
  if mode == "duplicate" and P:Count() >= P.MAX_PROFILES then st.note = ("You can have at most %d profiles."):format(P.MAX_PROFILES) redraw() return end
  clear(st)
  st.mode, st.target, st.note = mode, name, nil
  -- Delete with nobody on it needs no choice; with somebody, the player picks (nothing is picked for them)
  local p = self.page
  if p and (mode == "rename" or mode == "duplicate") then
    setBox(p.rowForm.box, mode == "rename" and name or "", mode == "rename" and "New name" or "Name of the copy")
  end
  redraw()
  if p and (mode == "rename" or mode == "duplicate") and p.rowForm.box.SetFocus then p.rowForm.box:SetFocus() end
end

function Prof:SubmitRow()
  local st = self.state
  local p = self.page
  if not (p and (st.mode == "rename" or st.mode == "duplicate")) then return end
  local text = p.rowForm.box:GetText() or ""
  -- (taken before the store changes: its PROFILES_CHANGED redraws the page, which lets go of a row whose profile is gone)
  local mode, target = st.mode, st.target
  local name, why
  if mode == "rename" then name, why = P:Rename(target, text) else name, why = P:Copy(target, text) end
  if not name then st.mode, st.target, st.err = mode, target, why redraw() return end
  st.note = mode == "rename" and ("Renamed %s to %s."):format(target, name) or ("Made %s as a copy of %s."):format(name, target)
  clear(st)
  p.rowForm.box:ClearFocus()
  redraw()
end

-- the characters a delete would move: the ones using it
function Prof:DeleteNeedsChoice(name) return #usersOf(name) > 0 end

function Prof:Confirm()
  local st = self.state
  local name, mode = st.target, st.mode
  if mode == "delete" then
    local users = usersOf(name)
    if #users > 0 and not (st.moveTo and P:Exists(st.moveTo) and st.moveTo ~= name) then
      st.err = "Pick the profile they move to first." redraw() return
    end
    local to = st.moveTo or P.DEFAULT
    local n, why = P:Delete(name, to)
    if n == nil then st.note = why else
      if n == 0 or #users == 0 then st.note = n == 0 and ("Deleted %s."):format(name) or ("Deleted %s. %s now use %s."):format(name, plural(n, "character"), to)
      else st.note = ("Deleted %s. %s now use%s %s."):format(name, whoText(users, true), #users == 1 and "s" or "", to) end
      if st.undo == name then st.undo = nil end
    end
  elseif mode == "reset" then
    local ok, why = P:ResetToDefaults(name)
    local mr, mn = P:Me()
    local mine = mr and P:Of(mr, mn) == name
    st.note = ok and ("%s is back to Panoply Suite's standard settings.%s"):format(name, mine and " This character uses it, so they are applied now." or "") or why
  end
  clear(st)
  redraw()
end

-- this character switches to `name` now; the banner says so and Undo goes back
function Prof:UseHere(name, isUndo)
  local mr, mn = P:Me()
  if not mr then return end
  local was = P:Of(mr, mn)
  local ok, changed = P:Switch(name)
  if not ok then return end
  local st = self.state
  clear(st)
  if was ~= name then
    st.undo = (not isUndo) and was or nil
    Kit.Toast(("%s now uses %s."):format(mn, name), { title = "Profiles" })
  end
  local note = ("%s now uses %s. %s"):format(mn, name, (changed or 0) == 0 and "Its settings were already the same."
    or (plural(changed, "setting") .. " changed, applied now."))
  if P.placePending then note = note .. " The windows move when combat ends." end
  st.note = note
  redraw()
end

function Prof:Undo()
  local to = self.state.undo
  if not (to and P:Exists(to)) then self.state.undo = nil redraw() return end
  self:UseHere(to, true)
end

-- a character's dropdown: this character switches now, another one from its next login
function Prof:SetCharacter(c, name)
  if c.me then return self:UseHere(name) end
  if not P:Exists(name) then return end
  local was = P:Of(c.realm, c.name)
  if not P:Use(c.realm, c.name, name) then return end
  local st = self.state
  clear(st)
  st.note = was == name and ("%s already uses %s."):format(c.name, name) or ("%s uses %s from its next login."):format(c.name, name)
  redraw()
end

-- the tick boxes start unticked; ticking any shows the bar
local function ckey(c) return P.Key(c.realm, c.name) end
function Prof:Ticked(c) return self.state.ticks[ckey(c)] == true end
function Prof:SetTicked(c, v)
  self.state.ticks[ckey(c)] = v and true or nil
  redraw()
end
function Prof:TickedList()
  local out = {}
  for _, c in ipairs(P:Characters()) do if self:Ticked(c) then out[#out + 1] = c end end
  return out
end
function Prof:ClearTicks()
  self.state.ticks, self.state.bulkTo = {}, nil
  redraw()
end

-- "Set 2 characters to [profile] · Apply": every ticked character uses that profile (this character at once, the others from their
-- next login); then the ticks are cleared
function Prof:ApplyBulk()
  local st = self.state
  local to = st.bulkTo
  local list = self:TickedList()
  if #list == 0 then return end
  if not (to and P:Exists(to)) then st.note = "Pick the profile first." redraw() return end
  local moved, already, me = 0, 0, nil
  for _, c in ipairs(list) do
    if P:Of(c.realm, c.name) == to then already = already + 1
    elseif c.me then me = c
    elseif P:Use(c.realm, c.name, to) then moved = moved + 1 end
  end
  st.ticks, st.bulkTo = {}, nil
  if me then
    self:UseHere(to)
    moved = moved + 1
  end
  st.note = ("Set %s to %s.%s"):format(plural(#list, "character"), to,
    already > 0 and (" %d already used it."):format(already) or "") .. ((moved - (me and 1 or 0)) > 0 and " The others pick it up at their next login." or "")
    .. ((me and P.placePending) and " The windows move when combat ends." or "")
  redraw()
end

-- the window scale expander is the page's own state (Kit page state, "scale"): it comes back after a reload and Reset view closes it
function Prof:ScaleOpen() return Kit.GetOpen("profiles", "scale", false) and true or false end
function Prof:ToggleScale()
  if self:ScaleOpen() then Kit.ForgetOpen("profiles", "scale") else Kit.SetOpen("profiles", "scale", true) end
  redraw()
end

-------------------------------------------------------------------------------
-- Refresh: the words; Layout: where everything goes
-------------------------------------------------------------------------------
-- a profile row: built once per index and kept
local function profileRow(p, i)
  local r = p.prows[i]
  if r then return r end
  local ct = p.content
  r = { frame = Kit.Surface(ct, 1) }
  local f = r.frame
  r.name = Skin.Name(f, 14, Kit.Color("text.primary"))
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.badge = Kit.StatusChip(f, "state.good", "In use here")
  r.who = Skin.Ink(f, 12, Kit.Color("text.muted"))
  -- (icon.ui.more: the header's settings picture, which follows the icon style)
  r.more = Skin.IconButton(f, "Settings", 22, function(self) if r.profile then Skin.Menu(self, Prof:MenuItems(r.profile), { width = 190 }) end end,
    "More", "Rename, Duplicate, Reset to defaults, Delete.")
  r.more.panoplyKitIcon = "icon.ui.more"
  r.scaleBtn = Skin.Button(f, "Window scale: 100%", 160, 24, function() Prof:ToggleScale() end, "Window scale",
    "Makes every Panoply Suite window bigger or smaller. Click to show the slider.")
  p.prows[i] = r
  return r
end

-- a character row
local function charRow(p, i)
  local r = p.crows[i]
  if r then return r end
  local ct = p.content
  r = { frame = CreateFrame("Frame", nil, ct) }
  local f = r.frame
  f.panoplyGapOK = true
  r.check = Skin.Check(f, "", { get = function() return r.c and Prof:Ticked(r.c) end, set = function(v) if r.c then Prof:SetTicked(r.c, v) end end },
    nil, "Tick to set several characters at once.", false)
  r.check.panoplySelectTick = true     -- it picks characters; it is no setting
  -- the box has no label of its own, so its tooltip gets a title (an empty one drew a blank first line)
  Skin.Tooltip(r.check, "Select", "Tick to set several characters at once.")
  r.crest = f:CreateTexture(nil, "ARTWORK"); r.crest:SetSize(Prof.CREST, Prof.CREST)
  r.name = Skin.Name(f, 13, Kit.Color("text.primary"))
  r.info = Skin.Ink(f, 11, Kit.Color("text.muted"))
  r.note = Skin.Ink(f, 11, Kit.Color("text.muted"))
  for _, fs in ipairs({ r.name, r.info, r.note }) do if fs.SetWordWrap then fs:SetWordWrap(false) end if fs.SetJustifyH then fs:SetJustifyH("LEFT") end end
  r.dd = Kit.Dropdown(f, { page = "profiles", width = Prof.DD_W, items = function() return profileItems() end,
    get = function() return r.c and P:Of(r.c.realm, r.c.name) end,
    set = function(v) if r.c then Prof:SetCharacter(r.c, v) end end,
    tip = "The profile this character uses", tipBody = "Pick another one to switch it." })
  p.crows[i] = r
  return r
end

function Prof:Refresh()
  local p = self.page
  if not p then return end
  local st = self.state
  local names = P:Names()
  if st.target and not P:Exists(st.target) then clear(st) end
  if st.undo and not P:Exists(st.undo) then st.undo = nil end
  local mr, mn, mi = P:Me()
  local cur = mr and P:Of(mr, mn) or P.DEFAULT
  -- the strip
  local s = p.strip
  if mr then
    s:Show()
    crest(s.crest, mi and mi.classFile)
    s.name:SetText(mn); setColor(s.name, classColor(mi and mi.classFile))
    s.realm:SetText(mr)
    s.dd:Refresh()
  else s:Hide() end
  s.note:SetText(st.note or "")
  -- the profile rows
  for i = 1, max(#names, #p.prows) do
    local n = names[i]
    if n then
      local r = profileRow(p, i)
      r.profile = n
      r.here = n == cur and mr ~= nil
      r.name:SetText(n)
      local users = usersOf(n)
      if #users == 0 then r.who:SetText("No character uses it."); setColor(r.who, Skin.colors.dim)
      else r.who:SetText(whoText(users)); setColor(r.who, Kit.Color("text.muted")) end
      if r.here then
        local v = (Panoply.db and Panoply.db.windowScale) or (Panoply.Look and Panoply.Look.WindowScale and Panoply.Look.WindowScale()) or 1
        r.scaleBtn.label:SetText(("Window scale: %d%%"):format(floor(v * 100 + 0.5)))
        Skin.FitButton(r.scaleBtn, 140, 220)
      end
      r.frame:Show()
    elseif p.prows[i] then p.prows[i].frame:Hide() end
  end
  local full = P:Count() >= P.MAX_PROFILES
  p.newBtn:SetEnabledLook(not full)
  -- the new profile form
  local nf = p.newForm
  if st.newOpen then
    nf:Show(); nf.from:Refresh()
    nf.err:SetText(st.err or "")
  else nf:Hide() end
  -- the row's form and question
  local rf, ra = p.rowForm, p.rowAsk
  if st.mode == "rename" or st.mode == "duplicate" then
    rf:Show()
    rf.label:SetText(st.mode == "rename" and ("Rename %s. Characters that use it keep using it under the new name."):format(st.target)
      or ("A new profile that starts as a copy of %s."):format(st.target))
    rf.ok.label:SetText(st.mode == "rename" and "Rename" or "Create copy")
    Skin.FitButton(rf.ok, 90, 160)
    rf.err:SetText(st.err or "")
  else rf:Hide() end
  if st.mode == "delete" or st.mode == "reset" then
    ra:Show()
    local users = usersOf(st.target)
    if st.mode == "delete" then
      local who = #users > 0 and (" %s %s it: %s."):format(plural(#users, "character"), #users == 1 and "uses" or "use", whoText(users, true)) or " No character uses it."
      ra.text:SetText(("Delete %s?%s Quest progress, Muster items and recordings are not touched."):format(st.target, who) .. (st.err and (" " .. st.err) or ""))
      ra.yes.label:SetText("Delete")
      ra.yes.panoplyDanger = true
      ra.yes:SetEnabledLook(#users == 0 or (st.moveTo ~= nil and P:Exists(st.moveTo)))
      ra.move:Refresh()
    else
      ra.text:SetText(("Reset %s to Panoply Suite's standard settings? %s"):format(st.target,
        #users > 0 and ("Characters affected: %s."):format(whoText(users, true)) or "No character uses it."))
      ra.yes.label:SetText("Reset it")
      ra.yes:SetEnabledLook(true)
    end
    ra.yes:Paint("up")
    Skin.FitButton(ra.yes, 90, 160)
  else ra:Hide() end
  -- the characters
  local chars = P:Characters()
  self.chars = chars
  for i = 1, max(#chars, #p.crows) do
    local c = chars[i]
    if c then
      local r = charRow(p, i)
      r.c = c
      crest(r.crest, c.classFile)
      r.name:SetText(c.name); setColor(r.name, classColor(c.classFile))
      -- (the character being played: its level from the game when Muster has not saved it yet)
      local lvl = c.level
      if not lvl and c.me and C.XP then local ok, l = pcall(C.XP) if ok and type(l) == "number" then lvl = l end end
      r.info:SetText(((lvl and ("Level %d · "):format(lvl)) or "") .. (c.realm or ""))
      r.note:SetText(c.me and "Playing now: applies at once" or "Takes effect next login")
      r.check:Refresh()
      r.dd:Refresh()
      r.frame:Show()
    elseif p.crows[i] then p.crows[i].frame:Hide() end
  end
  -- the bar for the ticked ones
  local ticked = #self:TickedList()
  local bar = p.bulk
  if ticked > 0 then
    bar:Show()
    bar.text:SetText(("Set %s to"):format(plural(ticked, "character")))
    bar.dd:Refresh()
    bar.apply:SetEnabledLook(st.bulkTo ~= nil and P:Exists(st.bulkTo))
  else bar:Hide(); st.bulkTo = nil end
end

-- the strip: line 1 the crest, the name, the realm, "uses", the dropdown and Undo; line 2 what the last action did
function Prof:LayoutStrip(p, W)
  local s = p.strip
  if not s:IsShown() then return 0 end
  local pad = SP.m
  local inner = W - 2 * pad
  s:ClearAllPoints(); s:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  s.crest:ClearAllPoints(); s.crest:SetPoint("TOPLEFT", s, "TOPLEFT", pad, -pad)
  local x = pad + 24 + SP.s
  local undoW = self.state.undo and (s.undo:GetWidth() + SP.s) or 0
  local ddW = min(200, max(120, floor(inner * 0.35)))
  s.dd:SetWidth(ddW); s.dd:Fit(120, ddW)
  ddW = s.dd:GetWidth()
  local usesW = ceil(TW(s.uses)) + 2
  local room = inner - 24 - SP.s - ddW - usesW - undoW - 3 * SP.s
  local nmW = min(max(40, floor(room * 0.6)), ceil(TW(s.name)) + 2)
  s.name:SetWidth(nmW); Skin.Ellipsize(s.name, s.name:GetText() or "", nmW)
  local nh = ceil(TH(s.name, nmW)); s.name:SetHeight(nh)
  s.name:ClearAllPoints(); s.name:SetPoint("TOPLEFT", s, "TOPLEFT", x, -pad - 3)
  local rmW = max(10, min(room - nmW - SP.s, ceil(TW(s.realm)) + 2))
  s.realm:SetWidth(rmW); Skin.Ellipsize(s.realm, s.realm:GetText() or "", rmW)
  s.realm:SetHeight(ceil(TH(s.realm, rmW)))
  s.realm:ClearAllPoints(); s.realm:SetPoint("TOPLEFT", s, "TOPLEFT", x + nmW + SP.s, -pad - 5)
  local ux = x + nmW + SP.s + rmW + SP.s
  s.uses:SetWidth(usesW); s.uses:SetHeight(ceil(TH(s.uses, usesW)))
  s.uses:ClearAllPoints(); s.uses:SetPoint("TOPLEFT", s, "TOPLEFT", ux, -pad - 5)
  s.dd:ClearAllPoints(); s.dd:SetPoint("TOPLEFT", s, "TOPLEFT", ux + usesW + SP.s, -pad)
  if self.state.undo then
    s.undo:Show(); s.undo:ClearAllPoints(); s.undo:SetPoint("TOPLEFT", s, "TOPLEFT", ux + usesW + SP.s + ddW + SP.s, -pad + 1)
  else s.undo:Hide() end
  local y = pad + max(26, nh + 6, 24)
  if (s.note:GetText() or "") ~= "" then
    s.note:Show()
    y = y + SP.xs + place(s.note, s, pad, -y - SP.xs, inner)
  else s.note:Hide() end
  y = y + pad
  s:SetSize(W, y)
  return y
end

-- one profile row (and the form or question under it); returns the height it took
local function layoutProfileRow(self, p, r, x, y, w)
  local st = self.state
  local pad = SP.m
  local f = r.frame
  local inner = w - 2 * pad
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -y)
  r.more:ClearAllPoints(); r.more:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -pad + 2)
  local bw = 0
  if r.here then
    local cw, ch = r.badge:Set("state.good", "In use here")
    bw = cw + SP.s
    r.badge:ClearAllPoints(); r.badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad - 22 - SP.s, -pad)
    r.badge:Show()
  else r.badge:Hide() end
  local nw = max(40, inner - 22 - SP.s - bw)
  r.name:SetWidth(nw); Skin.Ellipsize(r.name, r.profile, nw)
  local nh = ceil(TH(r.name, nw)); r.name:SetHeight(nh)
  r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
  local cy = pad + max(nh, 22) + SP.xs
  if r.who.SetWordWrap then r.who:SetWordWrap(true) end
  cy = cy + place(r.who, f, pad, -cy, inner)
  if r.here then
    cy = cy + SP.s
    r.scaleBtn:Show(); r.scaleBtn:ClearAllPoints(); r.scaleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -cy)
    cy = cy + r.scaleBtn:GetHeight()
    local sc = p.scaleBox
    if self:ScaleOpen() then
      -- built once, the first time it is opened (the settings' own slider row: the same one the gear shows)
      if not sc.built then
        local row = Cat:Row("windowScale")
        sc.made, sc.h = {}, 0
        if row then
          local made, ny = Panoply.SettingsUI:BuildRows(sc, { row }, 0, 0, max(200, inner), true)
          sc.made, sc.h = made or {}, -(ny or 0)
          if Panoply.PageSettings and Panoply.PageSettings.PreviewHook then for _, wd in ipairs(sc.made) do Panoply.PageSettings.PreviewHook(wd) end end
        end
        sc.built = true
      end
      for _, wd in ipairs(sc.made) do if wd.Refresh then wd:Refresh() end end
      local sh = max(sc.h, 24)
      cy = cy + SP.s
      sc:ClearAllPoints(); sc:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -cy)
      sc:SetSize(inner, sh); sc:SetParent(f); sc:Show()
      cy = cy + sh
    else sc:Hide() end
  else r.scaleBtn:Hide() end
  cy = cy + pad
  f:SetSize(w, cy)
  local h = cy
  -- the form or question of this row, under it
  if st.target == r.profile then
    local box
    if st.mode == "rename" or st.mode == "duplicate" then box = p.rowForm elseif st.mode == "delete" or st.mode == "reset" then box = p.rowAsk end
    if box then
      local by = 0
      local bi = w - 2 * pad
      if box == p.rowForm then
        by = pad + place(box.label, box, pad, -pad, bi) + SP.s
        local fw = min(220, bi)
        box.box:SetWidth(fw); box.box:ClearAllPoints(); box.box:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -by)
        local bh
        if bi - fw - SP.m >= 170 then
          bh = Skin.FlowButtons(box, { box.ok, box.cancel }, pad + fw + SP.m, -by, bi - fw - SP.m, SP.s, 80)
          by = by + max(26, bh)
        else
          by = by + 26 + SP.s
          bh = Skin.FlowButtons(box, { box.ok, box.cancel }, pad, -by, bi, SP.s, 80)
          by = by + bh
        end
        if (box.err:GetText() or "") ~= "" then box.err:Show(); by = by + SP.xs + place(box.err, box, pad, -by - SP.xs, bi) else box.err:Hide() end
      else
        by = pad + place(box.text, box, pad, -pad, bi) + SP.s
        if st.mode == "delete" and #usersOf(st.target) > 0 then
          local lw = ceil(TW(box.moveLabel)) + 2
          box.moveLabel:SetWidth(lw); box.moveLabel:SetHeight(ceil(TH(box.moveLabel, lw)))
          box.moveLabel:ClearAllPoints(); box.moveLabel:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -by - 5); box.moveLabel:Show()
          local dw = min(200, max(110, bi - lw - SP.s))
          box.move:SetWidth(dw); box.move:Refresh()
          box.move:ClearAllPoints(); box.move:SetPoint("TOPLEFT", box, "TOPLEFT", pad + lw + SP.s, -by); box.move:Show()
          by = by + 26 + SP.s
        else box.moveLabel:Hide(); box.move:Hide() end
        by = by + Skin.FlowButtons(box, { box.yes, box.no }, pad, -by, bi, SP.s, 80)
      end
      by = by + pad
      box:ClearAllPoints(); box:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -(y + h + SP.xs))
      box:SetSize(w, by)
      h = h + SP.xs + by
    end
  end
  return h
end

function Prof:LayoutProfiles(p, x, y, w)
  local st = self.state
  local y0 = y
  y = y + p.profHead:Layout(x, -y, w) + SP.s
  p.newBtn:ClearAllPoints(); p.newBtn:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -y)
  y = y + p.newBtn:GetHeight() + SP.s
  local nf = p.newForm
  if nf:IsShown() then
    local pad = SP.m
    local bi = w - 2 * pad
    local lw = max(ceil(TW(nf.label)), ceil(TW(nf.fromLabel))) + 2
    local cw = bi - lw - SP.s
    local by = pad
    nf.label:SetWidth(lw); nf.label:SetHeight(ceil(TH(nf.label, lw)))
    nf.label:ClearAllPoints(); nf.label:SetPoint("TOPLEFT", nf, "TOPLEFT", pad, -by - 5)
    nf.box:SetWidth(min(220, cw)); nf.box:ClearAllPoints(); nf.box:SetPoint("TOPLEFT", nf, "TOPLEFT", pad + lw + SP.s, -by)
    by = by + 26 + SP.s
    nf.fromLabel:SetWidth(lw); nf.fromLabel:SetHeight(ceil(TH(nf.fromLabel, lw)))
    nf.fromLabel:ClearAllPoints(); nf.fromLabel:SetPoint("TOPLEFT", nf, "TOPLEFT", pad, -by - 5)
    nf.from:SetWidth(min(220, cw)); nf.from:Refresh()
    nf.from:ClearAllPoints(); nf.from:SetPoint("TOPLEFT", nf, "TOPLEFT", pad + lw + SP.s, -by)
    by = by + 26 + SP.s
    by = by + Skin.FlowButtons(nf, { nf.ok, nf.cancel }, pad, -by, bi, SP.s, 80)
    if (nf.err:GetText() or "") ~= "" then nf.err:Show(); by = by + SP.xs + place(nf.err, nf, pad, -by - SP.xs, bi) else nf.err:Hide() end
    by = by + pad
    nf:ClearAllPoints(); nf:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -y)
    nf:SetSize(w, by)
    y = y + by + SP.s
  end
  for _, r in ipairs(p.prows) do
    if r.frame:IsShown() then y = y + layoutProfileRow(self, p, r, x, y, w) + SP.s end
  end
  if not (st.mode and P:Exists(st.target or "")) then p.rowForm:Hide(); p.rowAsk:Hide() end
  -- the slider is hidden when no row shows it
  local any = false
  for _, r in ipairs(p.prows) do if r.frame:IsShown() and r.here then any = true end end
  if not (any and self:ScaleOpen()) then p.scaleBox:Hide() end
  return y - y0
end

function Prof:LayoutCharacters(p, x, y, w)
  local y0 = y
  y = y + p.charHead:Layout(x, -y, w) + SP.s
  local pad = SP.s
  -- the bar for the ticked ones
  local bar = p.bulk
  if bar:IsShown() then
    local bp = SP.m
    local bi = w - 2 * bp
    local tw = min(bi, ceil(TW(bar.text)) + 2)
    bar.text:SetWidth(tw); bar.text:SetHeight(ceil(TH(bar.text, tw)))
    local ddW = min(180, max(110, bi - tw - SP.s))
    bar.dd:SetWidth(ddW); bar.dd:Refresh()
    local by = bp
    if tw + SP.s + ddW <= bi then
      bar.text:ClearAllPoints(); bar.text:SetPoint("TOPLEFT", bar, "TOPLEFT", bp, -by - 6)
      bar.dd:ClearAllPoints(); bar.dd:SetPoint("TOPLEFT", bar, "TOPLEFT", bp + tw + SP.s, -by)
      by = by + 26 + SP.s
    else
      bar.text:ClearAllPoints(); bar.text:SetPoint("TOPLEFT", bar, "TOPLEFT", bp, -by)
      by = by + ceil(TH(bar.text, tw)) + SP.xs
      bar.dd:ClearAllPoints(); bar.dd:SetPoint("TOPLEFT", bar, "TOPLEFT", bp, -by)
      by = by + 26 + SP.s
    end
    by = by + Skin.FlowButtons(bar, { bar.apply, bar.clear }, bp, -by, bi, SP.s, 70) + bp
    bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -y)
    bar:SetSize(w, by)
    y = y + by + SP.s
  end
  local ddW = min(Prof.DD_W, max(110, floor(w * 0.38)))
  for _, r in ipairs(p.crows) do
    if r.frame:IsShown() then
      local f = r.frame
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", p.content, "TOPLEFT", x, -y)
      r.check:ClearAllPoints(); r.check:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad - 2)
      r.check:FitLabel(0)
      if r.check.SetHitRectInsets then r.check:SetHitRectInsets(0, 0, 0, 0) end
      r.crest:ClearAllPoints(); r.crest:SetPoint("TOPLEFT", f, "TOPLEFT", pad + 18 + SP.s, -pad)
      local tx = pad + 18 + SP.s + Prof.CREST + SP.s
      r.dd:SetWidth(ddW); r.dd:Refresh()
      r.dd:ClearAllPoints(); r.dd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -pad)
      local tw = max(40, w - tx - ddW - 2 * pad - SP.s)
      r.name:SetWidth(tw); Skin.Ellipsize(r.name, r.c.name, tw)
      local nh = ceil(TH(r.name, tw)); r.name:SetHeight(nh)
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -pad)
      r.info:SetWidth(tw); Skin.Ellipsize(r.info, r.info:GetText() or "", tw)
      local ih = ceil(TH(r.info, tw)); r.info:SetHeight(ih)
      r.info:ClearAllPoints(); r.info:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -pad - nh - 1)
      r.note:SetWidth(tw); Skin.Ellipsize(r.note, r.note:GetText() or "", tw)
      local mh = ceil(TH(r.note, tw)); r.note:SetHeight(mh)
      r.note:ClearAllPoints(); r.note:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -pad - nh - 1 - ih - 1)
      local h = pad + max(nh + 1 + ih + 1 + mh, 26, Prof.CREST) + pad
      f:SetSize(w, h)
      y = y + h + SP.xs
    end
  end
  return y - y0
end

function Prof:Layout(p)
  local W, H = p.width or 600, p.height or 400
  local band = Kit.Band(W)
  p.band = band
  local sh = self:LayoutStrip(p, W)
  local top = sh > 0 and (sh + SP.m) or 0
  local area = p.area
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -top)
  area:SetSize(W, max(1, H - top - Prof.GRIP))
  area:Show()
  local cw = W - 14
  local ch
  if band == "wide" then
    local gap = SP.l + SP.s
    local lw = floor((cw - gap) * 0.4)
    local rw = cw - gap - lw
    local lh = self:LayoutProfiles(p, 0, 0, lw)
    local rh = self:LayoutCharacters(p, lw + gap, 0, rw)
    ch = max(lh, rh)
  else
    local lh = self:LayoutProfiles(p, 0, 0, cw)
    local rh = self:LayoutCharacters(p, 0, lh + SP.l, cw)
    ch = lh + SP.l + rh
  end
  p.content:SetSize(cw, max(1, ch))
  area:SetContentHeight(ch + SP.s)
  if self.pendingScroll and area.SetVerticalScroll then
    area:SetVerticalScroll(max(0, min(area:MaxScroll(), self.pendingScroll)))
    self.pendingScroll = nil
  end
  if area.UpdateBar then area:UpdateBar() end
  return ch
end

Panoply:Listen("PROFILES_CHANGED", function(kind, name, old)
  -- a renamed profile: every choice the page holds follows the new name (Undo, the form's start, the bar's profile, Delete's target)
  if kind == "rename" and old and name then
    local st = Prof.state
    for _, k in ipairs({ "undo", "newFrom", "bulkTo", "moveTo", "target" }) do if st[k] == old then st[k] = name end end
  end
  local M = Panoply.Menu
  if M and M.frame and M.frame:IsShown() and M.current == "profiles" and not M.batching then M:RefreshCurrent() end
end)
