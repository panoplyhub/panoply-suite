-- Panoply Suite 0.9.4 (next), steps 18 and 19: the editor for the player's own rotations (CustomRotations.lua), the card under the
-- Rotation sequencer on the class page of the character's own class. DISPLAY ONLY: it edits a saved list of the player's own abilities;
-- nothing in it casts, targets, binds, presses or runs anything, and its only buttons are plain Panoply Suite buttons.
--
-- Built like the sequencer's card: the frames are made once, out of combat, for one class, level, width, mode and "advanced" state, and
-- later only their text, their textures and which rows show change (never in combat: editing is refused in a fight with a plain line,
-- and the strip keeps working). The lists (steps, the spellbook picker) are a fixed number of rows with a pager, so no frame is made when a
-- step is added. The picker, the share box and the import box are three "modes" of the card (E.mode): the page is laid out again with
-- that mode's frames and kept, like every other variant of the page (Page.lua puts the mode into the page's signature).
local ADDON, Panoply = ...
local CP = Panoply.ClassPages
local C, Skin = Panoply.Compat, Panoply.Skin
local SP, TH = Skin.SP, Skin.TextHeight
local PAD = 12

local E = { live = setmetatable({}, { __mode = "k" }), mode = "", sel = nil, selStep = nil, stepPage = 1, pickPage = 1, filter = "", ROWS = 6 }
CP.Editor = E

E.TITLE = "My rotations"
E.INTRO = "Your own order of abilities. The next ability display and the highlight on your action bars follow it. The next ability display never casts; it shows what to press next."
E.NONE = "Built-in order"
E.EMPTY_LIST = "You have no rotations of your own yet. Press New rotation to start one."
E.SHARE_HELP = "Select all of the text, copy it (Ctrl+C) and send it to a friend. They paste it into Import."
E.IMPORT_HELP = "Paste a shared rotation here (Ctrl+V), then press Import. It is added as a new rotation; nothing else changes."
E.NOT_IN_BOOK = "not in your spellbook"

local function R() return CP.Rot end
local function S() return CP.Seq end

local function put(fs, parent, x, y, w, text)
  fs:SetWidth(w); fs:SetText(text or "")
  fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = TH(fs, w); fs:SetHeight(h)
  return y - h
end

-- a one-line text box in the add-on's look (like the partner box on the Level together page)
local function textBox(parent, w, h, maxLetters)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetSize(w, h)
  if eb.SetAutoFocus then eb:SetAutoFocus(false) end
  Skin.Font(eb, 12)
  if eb.SetTextInsets then eb:SetTextInsets(6, 6, 0, 0) end
  local bg, rim = Skin.Box(eb, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  eb.bg, eb.rim = bg, rim
  if maxLetters and eb.SetMaxLetters then eb:SetMaxLetters(maxLetters) end
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEditFocusGained", function(self) rim:SetVertexColor(Skin.colors.accentDark[1], Skin.colors.accentDark[2], Skin.colors.accentDark[3], 1) end)
  eb:SetScript("OnEditFocusLost", function(self) rim:SetVertexColor(Skin.colors.hairline[1], Skin.colors.hairline[2], Skin.colors.hairline[3], 1) end)
  return eb
end

-- a list row: an icon, a name and a short state, a plain button that picks the row
local function makeRow(c, x, y, w, onClick)
  local iconSize = 22
  local probe = Skin.Name(c, 12, Skin.colors.heading)
  probe:SetText("Wg")
  local nameH = TH(probe, w)
  probe:SetText("")
  local h = math.max(iconSize + 2 * SP.xs, nameH + 2 * SP.s)
  local b = CreateFrame("Button", nil, c)
  b.panoplyGapOK = true
  b:SetSize(w, h)
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", c, "TOPLEFT", x, y)
  local _, rim = Skin.Box(b, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = Skin.colors.slotLine })
  b.rim = rim
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(iconSize, iconSize)
  b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  local stateW = math.min(220, math.floor(w * 0.34))
  local nameW = w - 8 - iconSize - 8 - stateW - 8 - 6
  b.name = Skin.Name(b, 12, Skin.colors.heading)
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  b.name:SetSize(nameW, nameH)
  b.name:SetPoint("LEFT", b, "LEFT", 8 + iconSize + 8, 0)
  b.state = Skin.Ink(b, 11, Skin.colors.inkSoft)
  if b.state.SetWordWrap then b.state:SetWordWrap(false) end
  if b.state.SetJustifyH then b.state:SetJustifyH("RIGHT") end
  b.state:SetSize(stateW, nameH)
  b.state:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b.nameW, b.stateW = nameW, stateW
  b:SetScript("OnClick", onClick)
  b:Hide()
  return b, h
end

local function mark(row, on)
  local col = on and Skin.colors.accent or Skin.colors.slotLine
  row.rim:SetVertexColor(col[1], col[2], col[3], 1)
end

-------------------------------------------------------------------------------
-- What is selected, and the lines the editor says
-------------------------------------------------------------------------------
-- the rotation being edited: the one picked, else the active one, else the first
function E:Selected()
  local Rot = R()
  local r = self.sel and Rot:Find(self.sel)
  if not r then
    r = Rot:Active() or Rot:List()[1]
    self.sel = r and r.id or nil
  end
  return r
end

function E:SelStep()
  local rot = self:Selected()
  return rot and self.selStep and rot.steps[self.selStep] or nil, rot
end

function E:Say(text)
  self.said = text
  for holder, rec in pairs(self.live) do
    if rec.msg then rec.msg:SetText(text or "") end   -- (text only: allowed in a fight)
  end
end

-- true when an edit may go ahead; otherwise says why and returns false
function E:Allowed()
  if C.InCombat() then self:Say(R().MSG.combat) return false end
  return true
end

-------------------------------------------------------------------------------
-- Drawing the current state onto frames that already exist (out of combat)
-------------------------------------------------------------------------------
local function iconOf(name, id)
  local t = S().read.iconOf(id or name)
  if not t and id then t = S().read.iconOf(name) end
  return t or 134400
end

function E:StepState(st)
  if st.macro then
    local Cond = CP.Cond
    return Cond and Cond:MacroSpellText(st.macro) or "macro"
  end
  local known = R():StepKnown(st)
  if known == false then return E.NOT_IN_BOOK end
  local bits = {}
  if st.once then bits[#bits + 1] = "once" end
  if st.cond and CP.Cond and S().advDrawn then
    local ok = CP.Cond:Check(st.cond)
    bits[#bits + 1] = ok and "condition" or "can't read this condition"
    -- 0.9.5 phase 4H (spec 03a section 2): a condition that needs an input this game keeps secret in combat
    if ok and CP.Cond:SecretNote(st.cond) then bits[#bits + 1] = "skipped in a fight" end
  end
  return table.concat(bits, ", ")
end

function E:Pick()   -- the list the picker shows now: { { name, icon, id, state } }
  local out = {}
  local f = (self.filter or ""):lower()
  if self.mode == "macros" and CP.Cond then
    for _, m in ipairs(CP.Cond:Macros()) do
      if f == "" or m.name:lower():find(f, 1, true) then out[#out + 1] = m end
    end
  else
    for _, s in ipairs(R():Spellbook()) do
      if f == "" or s.name:lower():find(f, 1, true) then out[#out + 1] = { name = s.name, icon = s.icon, id = s.id } end
    end
  end
  return out
end

-- Nov 14 2026 (17-22 review, backlog 4): text typed into a box is never lost to a click on something else.
--   * E:Flush() runs first in every action below (a step clicked, a button pressed): a box that still has the typing focus loses it, which
--     commits what was typed (the box's OnEditFocusLost) to the step it belongs to, BEFORE the selection or the page changes. In the client a
--     click on a plain button does not take the focus from an edit box, so without this the typing was overwritten by the next Refresh.
--   * a box is filled with its text only when it is not being typed in (a redraw from outside, such as the spellbook changing, keeps the typing),
--     and a box remembers which rotation and step it was filled for, so its commit goes to that step, never to whichever is selected by then.
local BOXES = { "nameBox", "hintBox", "condBox" }
function E:Flush()
  for _, rec in pairs(self.live) do
    for _, key in ipairs(BOXES) do
      local b = rec[key]
      if b and b.HasFocus and b:HasFocus() then b:ClearFocus() end
    end
  end
end

-- fills a box for a rotation and step; a box with the typing focus is left as it is
local function fillBox(b, text, rotId, idx)
  if b.HasFocus and b:HasFocus() then return end
  b:SetText(text or "")
  b.panoplyRot, b.panoplyIdx = rotId, idx
end

function E:Refresh(rec)
  if not rec or C.InCombat() then self.dirty = true return end
  local Rot = R()
  local rot = self:Selected()
  local list = Rot:List()
  -- the strip's rotation
  local active = Rot:Active()
  rec.activeBtn.label:SetText(active and active.name or E.NONE)
  -- the editor
  fillBox(rec.nameBox, rot and rot.name or "", rot and rot.id, nil)
  local editable = rot ~= nil
  rec.state:SetText(rot and (active and active.id == rot.id and "Showing on the strip now" or "Not showing on the strip") or E.EMPTY_LIST)
  rec.useBtn:SetShown(rot ~= nil and not (active and active.id == rot.id))
  local steps = rot and rot.steps or {}
  local pages = math.max(1, math.ceil(#steps / E.ROWS))
  if self.stepPage > pages then self.stepPage = pages end
  if self.selStep and self.selStep > #steps then self.selStep = nil end
  for i, row in ipairs(rec.rows) do
    local idx = (self.stepPage - 1) * E.ROWS + i
    local st = steps[idx]
    if st then
      row.idx = idx
      row.icon:SetTexture(st.macro and 134400 or iconOf(st.name, st.id))
      Skin.Ellipsize(row.name, idx .. ". " .. st.name, row.nameW)
      row.state:SetText(E:StepState(st))
      mark(row, idx == self.selStep)
      row:Show()
    else
      row.idx = nil
      row:Hide()
    end
  end
  rec.pager:SetText(#steps == 0 and "No steps yet." or ("Steps %d to %d of %d"):format((self.stepPage - 1) * E.ROWS + 1, math.min(#steps, self.stepPage * E.ROWS), #steps))
  rec.prev:SetEnabledLook(self.stepPage > 1)
  rec.next:SetEnabledLook(self.stepPage < pages)
  -- the selected step
  local st = self.selStep and steps[self.selStep]
  rec.selLabel:SetText(st and ("Selected step: " .. st.name) or (rot and #steps > 0 and "Click a step to change it, move it or remove it." or ""))
  fillBox(rec.hintBox, st and st.hint or "", rot and rot.id, self.selStep)
  rec.hintBox:SetShown(st ~= nil)
  rec.hintLabel:SetShown(st ~= nil)
  rec.onceCheck:SetShown(st ~= nil)
  rec.onceCheck.label:SetShown(st ~= nil)
  if st then rec.onceCheck:Refresh() end
  for _, b in ipairs({ rec.up, rec.down, rec.remove }) do b:SetEnabledLook(st ~= nil) end
  for _, b in ipairs({ rec.dup, rec.del, rec.share }) do b:SetEnabledLook(rot ~= nil) end
  rec.addSpell:SetEnabledLook(rot ~= nil)
  if rec.addMacro then rec.addMacro:SetEnabledLook(rot ~= nil) end
  rec.reset:SetEnabledLook(active ~= nil)
  if rec.adv and self.FillAdvancedState then self:FillAdvancedState(rec, st) end
  -- the picker, the share box
  if rec.pickRows then
    local items = self:Pick()
    local ppages = math.max(1, math.ceil(#items / E.ROWS))
    if self.pickPage > ppages then self.pickPage = ppages end
    for i, row in ipairs(rec.pickRows) do
      local it = items[(self.pickPage - 1) * E.ROWS + i]
      if it then
        row.item = it
        row.icon:SetTexture(it.icon or 134400)
        Skin.Ellipsize(row.name, it.name, row.nameW)
        row.state:SetText(it.state or "")
        row:Show()
      else
        row.item = nil
        row:Hide()
      end
    end
    rec.pickPager:SetText(#items == 0 and "Nothing matches." or ("%d to %d of %d"):format((self.pickPage - 1) * E.ROWS + 1, math.min(#items, self.pickPage * E.ROWS), #items))
    rec.pickPrev:SetEnabledLook(self.pickPage > 1)
    rec.pickNext:SetEnabledLook(self.pickPage < ppages)
  end
  if rec.shareBox then
    local text = rot and Rot:Export(rot.id) or ""
    self.shareText = text
    rec.shareBox:SetText(text)
  end
  rec.msg:SetText(self.said or "")
  self.dirty = false
end

-- something changed (CustomRotations.lua calls this): every editor on screen draws again; in a fight it waits for the end of it
function E:Changed()
  if C.InCombat() then self.dirty = true return end
  for holder, rec in pairs(self.live) do
    if holder:IsVisible() then self:Refresh(rec) end
  end
end

function E:RefreshAll() self:Changed() end

-------------------------------------------------------------------------------
-- The actions (each refused in a fight with a plain line)
-------------------------------------------------------------------------------
local function say(msg) E:Say(msg) end

function E:SetMode(mode)
  self:Flush()
  if not self:Allowed() then return end
  self.mode, self.pickPage, self.filter = mode, 1, ""
  self.said = nil
  if S() then S():Redraw() end
  self:Changed()
end

function E:New()
  self:Flush()
  if not self:Allowed() then return end
  local id, msg = R():New("")
  if not id then say(msg) return end
  self.sel, self.selStep, self.stepPage = id, nil, 1
  say("Made a new rotation. Add spells with Add a spell.")
  self:Changed()
end

function E:Duplicate()
  self:Flush()
  if not self:Allowed() then return end
  local rot = self:Selected()
  if not rot then return end
  local id, msg = R():Duplicate(rot.id)
  if not id then say(msg) return end
  self.sel, self.selStep, self.stepPage = id, nil, 1
  say("Made a copy.")
  self:Changed()
end

function E:Delete()
  self:Flush()
  if not self:Allowed() then return end
  local rot = self:Selected()
  if not rot then return end
  local now = C.GetTime()
  if not (self.confirm and self.confirm.id == rot.id and now - self.confirm.at < 6) then
    self.confirm = { id = rot.id, at = now }
    say('Press Delete again within a few seconds to remove "' .. rot.name .. '". Its steps cannot be brought back.')
    return
  end
  self.confirm = nil
  local ok, msg = R():Delete(rot.id)
  if not ok then say(msg) return end
  self.sel, self.selStep, self.stepPage = nil, nil, 1
  say("Deleted.")
  self:Changed()
end

function E:UseSelected()
  self:Flush()
  local rot = self:Selected()
  if not rot then return end
  local ok, msg = R():SetActive(rot.id)
  if not ok then say(msg) return end
  say('"' .. rot.name .. '" is on the strip now.')
end

function E:Reset()
  self:Flush()
  local Rot = R()
  if not Rot:ActiveId() then return end
  Rot:Reset()
  say("The strip shows the built-in order again. Your rotations are still saved.")
end

-- the commit of a box goes to what the box was filled for (rotId, idx), else to what is selected now
function E:SetName(text, rotId)
  local rot = rotId and R():Find(rotId) or self:Selected()
  if not rot then return end
  if not self:Allowed() then self.nameBoxPending = true return end
  local ok, msg = R():Rename(rot.id, text)
  if not ok then say(msg) end
  self:Changed()
end

function E:SelectStep(idx)
  self:Flush()
  self.selStep = idx
  self:Changed()
end

function E:Move(dir)
  self:Flush()
  if not self:Allowed() then return end
  local st, rot = self:SelStep()
  if not st then return end
  local ok, j = R():MoveStep(rot.id, self.selStep, dir)
  if not ok then say(j) return end
  self.selStep = j
  self.stepPage = math.ceil(j / E.ROWS)
  say(nil)
  self:Changed()
end

function E:RemoveStep()
  self:Flush()
  if not self:Allowed() then return end
  local st, rot = self:SelStep()
  if not st then return end
  local ok, msg = R():RemoveStep(rot.id, self.selStep)
  if not ok then say(msg) return end
  self.selStep = nil
  say("Removed.")
  self:Changed()
end

-- the step a box commit is for: the rotation and place the box was filled for, else the selected step
local function target(self, rotId, idx)
  if rotId and idx then
    local rot = R():Find(rotId)
    local st = rot and type(rot.steps) == "table" and rot.steps[idx] or nil
    return st, rot, idx
  end
  local st, rot = self:SelStep()
  return st, rot, self.selStep
end

function E:SetHint(text, rotId, idx)
  local st, rot, at = target(self, rotId, idx)
  if not st then return end
  if not self:Allowed() then return end
  local ok, msg = R():SetHint(rot.id, at, text)
  if not ok then say(msg) end
  self:Changed()
end

function E:SetCond(text, rotId, idx)
  local st, rot, at = target(self, rotId, idx)
  if not st then return end
  if not self:Allowed() then return end
  local ok, msg = R():SetCond(rot.id, at, text)
  if not ok then say(msg) end
  self:Changed()
end

function E:SetOnce(on)
  self:Flush()
  local st, rot = self:SelStep()
  if not st then return end
  if not self:Allowed() then return end
  local ok, msg = R():SetOnce(rot.id, self.selStep, on)
  if not ok then say(msg) end
  self:Changed()
end

function E:AddFrom(it)
  self:Flush()
  if not self:Allowed() then return end
  local rot = self:Selected()
  if not rot then return end
  local ok, n
  if self.mode == "macros" then ok, n = R():AddMacro(rot.id, it.name, it.index)
  else ok, n = R():AddSpell(rot.id, it.id, it.name) end
  if not ok then say(n) return end
  self.selStep = n
  self.stepPage = math.ceil(n / E.ROWS)
  say(("Added %s as step %d."):format(it.name, n))
  self:Changed()
end

function E:Page(delta)
  self:Flush()
  local rot = self:Selected()
  local n = rot and #rot.steps or 0
  self.stepPage = math.max(1, math.min(math.max(1, math.ceil(n / E.ROWS)), self.stepPage + delta))
  self:Changed()
end

function E:PickPage(delta)
  self:Flush()
  self.pickPage = math.max(1, self.pickPage + delta)
  self:Changed()
end

function E:DoImport(text)
  self:Flush()
  if not self:Allowed() then return end
  local id, why = R():Import(text)
  if not id then
    say("Not imported: " .. tostring(why) .. " Nothing was changed.")
    self:Changed()
    return
  end
  self.sel, self.selStep, self.stepPage = id, nil, 1
  self.mode = ""
  say("Imported. It is the new rotation below; use Use this rotation to show it on the strip.")
  if S() then S():Redraw() end
end

function E:OpenActiveMenu(owner)
  self:Flush()
  if not self:Allowed() then return end
  local Rot = R()
  local items = { { text = E.NONE .. " (the default)", checked = Rot:ActiveId() == nil, func = function() self:Reset() end } }
  for _, r in ipairs(Rot:List()) do
    items[#items + 1] = { text = r.name, checked = Rot:ActiveId() == r.id,
      func = function() self.sel, self.selStep, self.stepPage = r.id, nil, 1 self:UseSelected() end }
  end
  return Skin.Menu(owner, items, { width = 300 })
end

-------------------------------------------------------------------------------
-- The card
-------------------------------------------------------------------------------
-- c is the open card (Page.lua), holder the page's content frame, v the page's view (own class, sequencer on)
function E:Fill(c, holder, v)
  local rec = { holder = holder, c = c, rows = {}, adv = S() and S().advDrawn or false, mode = self.mode }
  self.live[holder] = rec
  holder.panoplyEditor = rec
  -- a page variant that was built before is shown again with whatever the saved data says now
  local prevShow = holder:GetScript("OnShow")
  holder:SetScript("OnShow", function(...)
    if prevShow then prevShow(...) end
    if not C.InCombat() then E:Refresh(rec) end
  end)
  c:Para(E.INTRO)

  -- which rotation shows on the strip
  local lab = Skin.Label(c, 10, Skin.colors.inkSoft)
  lab:SetText("SHOWING ON THE STRIP")
  c.y = put(lab, c, PAD, c.y, c.inner, "SHOWING ON THE STRIP") - SP.xs
  rec.activeBtn = Skin.Button(c, E.NONE, math.min(c.inner, 360), 28, function(b) E:OpenActiveMenu(b) end, "Which rotation shows",
    "Pick the built-in order or one of your own rotations. The strip and the highlight follow it.")
  rec.activeBtn:ClearAllPoints(); rec.activeBtn:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - rec.activeBtn:GetHeight() - SP.m

  -- whole-rotation buttons
  local function btn(label, tip, fn) return Skin.Button(c, label, 100, 28, fn, label, tip) end
  rec.new = btn("New rotation", "Start an empty rotation of your own.", function() E:New() end)
  rec.dup = btn("Duplicate", "Make a copy of the rotation below to change.", function() E:Duplicate() end)
  rec.del = btn("Delete", "Remove the rotation below for good. You press it twice.", function() E:Delete() end)
  rec.reset = btn("Reset to default", "Show the built-in order again. Your rotations stay saved.", function() E:Reset() end)
  rec.share = btn("Share", "Make a text you can send to a friend.", function() E:SetMode(self.mode == "share" and "" or "share") end)
  rec.import = btn("Import", "Add a rotation a friend shared as text.", function() E:SetMode(self.mode == "import" and "" or "import") end)
  local list = { rec.new, rec.dup, rec.del, rec.reset, rec.share, rec.import }
  local bh = Skin.FlowButtons(c, list, PAD, c.y, c.inner, SP.s, 90)
  c.y = c.y - bh - SP.m

  -- the rotation being edited: its name, and whether it is the one on the strip
  local l2 = Skin.Label(c, 10, Skin.colors.inkSoft)
  c.y = put(l2, c, PAD, c.y, c.inner, "ROTATION TO CHANGE") - SP.xs
  local nameW = math.max(160, math.min(300, c.inner - 220))
  rec.nameBox = textBox(c, nameW, 26, R().NAME_MAX)
  rec.nameBox:ClearAllPoints(); rec.nameBox:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local function commitName(self) E:SetName(self:GetText(), self.panoplyRot) end
  rec.nameBox:SetScript("OnEnterPressed", function(self) commitName(self) self:ClearFocus() end)
  rec.nameBox:SetScript("OnEditFocusLost", function(self)
    rec.nameBox.rim:SetVertexColor(Skin.colors.hairline[1], Skin.colors.hairline[2], Skin.colors.hairline[3], 1)
    commitName(self)
  end)
  rec.useBtn = Skin.Button(c, "Use this rotation", 150, 26, function() E:UseSelected() end, "Use this rotation", "Show this rotation on the strip and on your action bars.")
  Skin.FitButton(rec.useBtn, 120, c.inner - nameW - SP.m)
  rec.useBtn:ClearAllPoints(); rec.useBtn:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + nameW + SP.m, c.y)
  c.y = c.y - 26 - SP.xs
  rec.state = Skin.Ink(c, 11, Skin.colors.inkSoft)
  local stateH = 0
  for _, s in ipairs({ E.EMPTY_LIST, "Showing on the strip now", "Not showing on the strip" }) do rec.state:SetText(s) stateH = math.max(stateH, TH(rec.state, c.inner)) end
  rec.state:SetWidth(c.inner); rec.state:SetHeight(stateH)
  rec.state:ClearAllPoints(); rec.state:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  rec.state:SetText("")
  c.y = c.y - stateH - SP.s

  -- the steps: a fixed number of rows and a pager
  local l3 = Skin.Label(c, 10, Skin.colors.inkSoft)
  c.y = put(l3, c, PAD, c.y, c.inner, "STEPS, IN ORDER") - SP.xs
  local rowGap = SP.xs
  for i = 1, E.ROWS do
    local row, h = makeRow(c, PAD, c.y, c.inner, function(b) if b.idx then E:SelectStep(b.idx) end end)
    rec.rows[i] = row
    c.y = c.y - h - rowGap
  end
  c.y = c.y - SP.xs + rowGap
  rec.prev = Skin.Button(c, "Earlier steps", 110, 26, function() E:Page(-1) end, "Earlier steps", "Show the steps before these.")
  rec.next = Skin.Button(c, "Later steps", 110, 26, function() E:Page(1) end, "Later steps", "Show the steps after these.")
  local pb = Skin.FlowButtons(c, { rec.prev, rec.next }, PAD, c.y, c.inner, SP.s, 90)
  rec.pager = Skin.Ink(c, 11, Skin.colors.inkSoft)
  local pw = math.max(120, c.inner - rec.prev:GetWidth() - rec.next:GetWidth() - 3 * SP.s)
  rec.pager:SetWidth(pw)
  rec.pager:SetText("Steps 88 to 88 of 888")
  local pagerH = TH(rec.pager, pw)
  rec.pager:SetHeight(pagerH)
  rec.pager:ClearAllPoints(); rec.pager:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + rec.prev:GetWidth() + rec.next:GetWidth() + 2 * SP.s + SP.m, c.y - math.max(0, (pb - pagerH) / 2))
  rec.pager:SetText("")
  c.y = c.y - math.max(pb, pagerH) - SP.m

  -- the selected step
  rec.selLabel = Skin.Name(c, 12, Skin.colors.heading)
  rec.selLabel:SetWordWrap(false)
  rec.selLabel:SetWidth(c.inner); rec.selLabel:SetHeight(TH(rec.selLabel, c.inner))
  rec.selLabel:SetText("Selected step: Wg")
  rec.selLabel:SetHeight(TH(rec.selLabel, c.inner))
  rec.selLabel:ClearAllPoints(); rec.selLabel:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - rec.selLabel:GetHeight() - SP.s
  rec.selLabel:SetText("")
  rec.up = btn("Move up", "Move the selected step one place earlier.", function() E:Move(-1) end)
  rec.down = btn("Move down", "Move the selected step one place later.", function() E:Move(1) end)
  rec.remove = btn("Remove step", "Take the selected step out of the rotation.", function() E:RemoveStep() end)
  local sb = Skin.FlowButtons(c, { rec.up, rec.down, rec.remove }, PAD, c.y, c.inner, SP.s, 90)
  c.y = c.y - sb - SP.s
  rec.hintLabel = Skin.Ink(c, 11, Skin.colors.inkSoft)
  c.y = put(rec.hintLabel, c, PAD, c.y, c.inner, "Hint shown under the strip while this step is next (up to " .. R().HINT_MAX .. " characters):") - SP.xs
  rec.hintBox = textBox(c, c.inner, 26, R().HINT_MAX)
  rec.hintBox:ClearAllPoints(); rec.hintBox:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  rec.hintBox:SetScript("OnEnterPressed", function(self) E:SetHint(self:GetText(), self.panoplyRot, self.panoplyIdx) self:ClearFocus() end)
  rec.hintBox:SetScript("OnEditFocusLost", function(self)
    self.rim:SetVertexColor(Skin.colors.hairline[1], Skin.colors.hairline[2], Skin.colors.hairline[3], 1)
    E:SetHint(self:GetText(), self.panoplyRot, self.panoplyIdx)
  end)
  c.y = c.y - 26 - SP.s
  rec.onceCheck = Skin.Check(c, "Take it off the strip after I cast it (an opener, a buff or a damage-over-time)",
    { get = function() local st = E:SelStep() return st and st.once end, set = function(on) E:SetOnce(on) end }, nil,
    "On: the step leaves the strip when your own cast of it succeeds, and comes back when the fight ends or you pick another target.", true)
  rec.onceCheck:ClearAllPoints(); rec.onceCheck:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  local _, och = rec.onceCheck:FitLabel(c.inner - 27)
  c.y = c.y - och - SP.m
  if rec.adv and self.FillAdvanced then self:FillAdvanced(c, rec) end

  -- adding steps
  rec.addSpell = btn("Add a spell", "Pick one of the spells in your spellbook to add as the last step.", function() E:SetMode(self.mode == "spells" and "" or "spells") end)
  local adders = { rec.addSpell }
  if rec.adv and CP.Cond then
    rec.addMacro = btn("Add one of my macros", "Pick one of your own macros. The strip shows the spell the macro would cast now. The macro itself is never changed or run.",
      function() E:SetMode(self.mode == "macros" and "" or "macros") end)
    adders[#adders + 1] = rec.addMacro
  end
  local ab = Skin.FlowButtons(c, adders, PAD, c.y, c.inner, SP.s, 90)
  c.y = c.y - ab - SP.m

  -- the mode's own part
  if rec.mode == "spells" or rec.mode == "macros" then
    local l4 = Skin.Label(c, 10, Skin.colors.inkSoft)
    c.y = put(l4, c, PAD, c.y, c.inner, rec.mode == "macros" and "YOUR MACROS: PICK ONE TO ADD" or "YOUR SPELLBOOK: PICK ONE TO ADD") - SP.xs
    rec.search = Skin.Input(c, math.min(c.inner, 320), 26, "Search")
    rec.search:ClearAllPoints(); rec.search:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
    rec.search:SetScript("OnTextChanged", function(self, user)
      local t = self:GetText() or ""
      if self.placeholder then self.placeholder:SetShown(t == "") end
      if E.filter ~= t then E.filter, E.pickPage = t, 1 E:Changed() end
    end)
    rec.search:SetText(E.filter or "")
    c.y = c.y - 26 - SP.s
    rec.pickRows = {}
    for i = 1, E.ROWS do
      local row, h = makeRow(c, PAD, c.y, c.inner, function(b) if b.item then E:AddFrom(b.item) end end)
      rec.pickRows[i] = row
      c.y = c.y - h - rowGap
    end
    c.y = c.y - SP.xs + rowGap
    rec.pickPrev = Skin.Button(c, "Earlier", 90, 26, function() E:PickPage(-1) end, "Earlier", "Show the entries before these.")
    rec.pickNext = Skin.Button(c, "Later", 90, 26, function() E:PickPage(1) end, "Later", "Show the entries after these.")
    rec.close = Skin.Button(c, "Close", 90, 26, function() E:SetMode("") end, "Close", "Close this list.")
    local pk = Skin.FlowButtons(c, { rec.pickPrev, rec.pickNext, rec.close }, PAD, c.y, c.inner, SP.s, 80)
    rec.pickPager = Skin.Ink(c, 11, Skin.colors.inkSoft)
    c.y = put(rec.pickPager, c, PAD, c.y - pk - SP.xs, c.inner, "888 to 888 of 888") - SP.s
    rec.pickPager:SetText("")
  elseif rec.mode == "share" then
    local l4 = Skin.Label(c, 10, Skin.colors.inkSoft)
    c.y = put(l4, c, PAD, c.y, c.inner, "SHARE THIS ROTATION") - SP.xs
    rec.shareBox = textBox(c, c.inner, 26, R().IMPORT_MAX)
    rec.shareBox:ClearAllPoints(); rec.shareBox:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
    rec.shareBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    rec.shareBox:SetScript("OnTextChanged", function(self, user) if user and self:GetText() ~= E.shareText then self:SetText(E.shareText or "") self:HighlightText() end end)
    c.y = c.y - 26 - SP.xs
    c:Para(E.SHARE_HELP, Skin.colors.inkSoft, 11)
    rec.close = Skin.Button(c, "Close", 90, 26, function() E:SetMode("") end, "Close", "Close the share box.")
    c.y = c.y - Skin.FlowButtons(c, { rec.close }, PAD, c.y, c.inner, SP.s, 80) - SP.s
  elseif rec.mode == "import" then
    local l4 = Skin.Label(c, 10, Skin.colors.inkSoft)
    c.y = put(l4, c, PAD, c.y, c.inner, "IMPORT A SHARED ROTATION") - SP.xs
    rec.importBox = textBox(c, c.inner, 26, R().IMPORT_MAX + 1)
    rec.importBox:ClearAllPoints(); rec.importBox:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
    rec.importBox:SetScript("OnEnterPressed", function(self) E:DoImport(self:GetText()) end)
    c.y = c.y - 26 - SP.xs
    c:Para(E.IMPORT_HELP, Skin.colors.inkSoft, 11)
    rec.doImport = Skin.Button(c, "Import", 100, 26, function() E:DoImport(rec.importBox:GetText()) end, "Import", "Add the pasted rotation as a new one. A text that is not a rotation changes nothing.")
    rec.close = Skin.Button(c, "Close", 90, 26, function() E:SetMode("") end, "Close", "Close the import box.")
    c.y = c.y - Skin.FlowButtons(c, { rec.doImport, rec.close }, PAD, c.y, c.inner, SP.s, 80) - SP.s
  end

  -- one line for what the editor says (room for the longest line it says)
  rec.msg = Skin.Ink(c, 11, Skin.colors.ink)
  local longest = ""
  for _, s in ipairs({ R().MSG.combat, 'Press Delete again within a few seconds to remove "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwww". Its steps cannot be brought back.',
    "Not imported: The check number does not match: the text was changed or cut short when it was copied. Nothing was changed.",
    "Imported. It is the new rotation below; use Use this rotation to show it on the strip." }) do
    if #s > #longest then longest = s end
  end
  local msgH = 0
  for _, s in ipairs({ R().MSG.combat, longest }) do rec.msg:SetText(s) msgH = math.max(msgH, TH(rec.msg, c.inner)) end
  rec.msg:SetWidth(c.inner); rec.msg:SetHeight(msgH)
  rec.msg:ClearAllPoints(); rec.msg:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  c.y = c.y - msgH - SP.s
  rec.msg:SetText("")
  self:Refresh(rec)
end

-------------------------------------------------------------------------------
-- Step 19: the condition field, drawn only while the advanced option is on (it is a different variant of the card when it is off)
-------------------------------------------------------------------------------
function E:FillAdvanced(c, rec)
  local Cond = CP.Cond
  rec.condLabel = Skin.Ink(c, 11, Skin.colors.inkSoft)
  c.y = put(rec.condLabel, c, PAD, c.y, c.inner, "Condition for this step, optional (up to " .. R().COND_MAX .. " characters). It only decides whether the step shows:") - SP.xs
  rec.condBox = textBox(c, c.inner, 26, R().COND_MAX)
  rec.condBox:ClearAllPoints(); rec.condBox:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  rec.condBox:SetScript("OnEnterPressed", function(self) E:SetCond(self:GetText(), self.panoplyRot, self.panoplyIdx) self:ClearFocus() end)
  rec.condBox:SetScript("OnEditFocusLost", function(self)
    self.rim:SetVertexColor(Skin.colors.hairline[1], Skin.colors.hairline[2], Skin.colors.hairline[3], 1)
    E:SetCond(self:GetText(), self.panoplyRot, self.panoplyIdx)
  end)
  c.y = c.y - 26 - SP.xs
  rec.condMsg = Skin.Ink(c, 11, Skin.colors.ink)
  local h = 0
  -- (the longest line it can show: the reasons, a macro step, and the secret-input note with every input named, then a macro step)
  local secretAll = ("%s (%s). In a fight that part is skipped and the step keeps its place in the order."):format(Cond.SECRET_TIP,
    "cooldowns, effects, health, macro conditions, power, spell highlights") .. " Macro step: casts Wwwwwwwwwwwwwwwwwwwwwwwwwwww now."
  for _, t in ipairs({ "Can't read this condition: " .. Cond.ENEMIES_WHY, "Macro step: casts Wwwwwwwwwwwwwwwwwwwwwwwwwwww now", secretAll }) do
    rec.condMsg:SetText(t) h = math.max(h, TH(rec.condMsg, c.inner))
  end
  rec.condMsg:SetWidth(c.inner); rec.condMsg:SetHeight(h)
  rec.condMsg:ClearAllPoints(); rec.condMsg:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, c.y)
  rec.condMsg:SetText("")
  c.y = c.y - h - SP.s
  for _, line in ipairs(Cond.HELP) do c:Para(line, Skin.colors.inkSoft, 11) end
end

function E:FillAdvancedState(rec, st)
  local Cond = CP.Cond
  local rot = self:Selected()
  fillBox(rec.condBox, st and st.cond or "", rot and rot.id, self.selStep)
  rec.condBox:SetShown(st ~= nil)
  rec.condLabel:SetShown(st ~= nil)
  local msg, secret = "", nil
  if st then
    if st.cond and st.cond ~= "" then
      local ok, why = Cond:Check(st.cond, st.macro ~= nil)
      msg = ok and "Condition read." or ("Can't read this condition: " .. (tostring(why):gsub("%.$", "")) .. ".")
      -- 0.9.5 phase 4H: greyed, with the reason, when it needs an input the game keeps secret in combat
      secret = ok and Cond:SecretNote(st.cond) or nil
      if secret then msg = secret end
    end
    if st.macro then msg = (msg ~= "" and (msg .. " ") or "") .. "Macro step: " .. Cond:MacroSpellText(st.macro) .. "." end
  end
  rec.condMsg:SetText(msg)
  local col = secret and Skin.colors.dim or Skin.colors.ink
  rec.condMsg:SetTextColor(col[1], col[2], col[3], 1)
  if rec.condBox.SetAlpha then rec.condBox:SetAlpha(secret and 0.6 or 1) end
  rec.condSecret = secret
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
Panoply:On("SPELLS_CHANGED", function() E:Changed() end)
Panoply:On("PLAYER_REGEN_ENABLED", function() if E.dirty then E:Changed() end end)
