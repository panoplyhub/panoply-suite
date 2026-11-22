-- Panoply Suite "Report a problem" window (SPEC-REPORTS.md).
-- Original code for Panoply Suite. No third-party code.
--
-- Ways in: the flag button beside "Step N of M" on the guide window, right-click on a step row
-- (guide window "Up next" and the Leveling tab), the guide window's right-click menu, the Help
-- tab, and /panoply report. The add-on itself sends nothing. 0.9.4 (ticket pipeline, step 11): Send opens a consent notice
-- (what is included, what is not, that the companion app must be running, what "Send and reload" does) and nothing is saved
-- until the player picks "Send and reload" (save, then ReloadUI outside combat; in combat after it), "Send later" (save,
-- no reload) or "Cancel" (nothing saved). The report is saved in PanoplySuiteReportsDB, and the desktop app on this computer
-- sends it automatically (if sending is on), then marks it sent while the game is closed. "Feedback / idea" is a second
-- report type on the same window and path (kind "feedback", note required). "Credit me as" is an optional box, empty each time.
local ADDON, Panoply = ...
local Skin, R = Panoply.Skin, Panoply.Reports
local RW = { chips = {} }
Panoply.ReportWindow = RW

RW.WIDTH, RW.PREVIEW_H, RW.NOTE_H, RW.MIN_PREVIEW_H, RW.NOTE_H_SHORT = 520, 220, 66, 70, 46
RW.TITLE_STEP, RW.TITLE_GENERAL, RW.TITLE_FEEDBACK = "Something's wrong with this step", "Report a problem", "Feedback / idea"
RW.NOTE_HEAD, RW.NOTE_HEAD_FEEDBACK = "Anything else? (optional)", "Your feedback or idea"
RW.PLACEHOLDER, RW.PLACEHOLDER_FEEDBACK = "For example: the quest giver isn't at this spot.", "For example: it would help to see how far the next step is."
RW.CREDIT_LABEL, RW.CREDIT_PLACEHOLDER = "Credit me as (optional)", "Anonymous if empty"
RW.CREDIT_HINT = "Leave this empty to stay anonymous. If you type a name, we may thank you by it in the release notes once this is fixed."
-- 0.9.5 phase 4A4 (spec 06 section 4, 06b): what the window says about where a report goes is the sharing state line (Core/Sharing.lua),
-- generated from the one setting; nothing here says it on its own any more.
RW.SAVED = "Thanks. Your report is saved. " .. Panoply.Sharing.SAVED_SENDING
RW.SAVED_OFF = "Thanks. Your report is saved on this computer."
function RW.HowLine() return Panoply.Sharing:Line() end
-- Will Panoply Hub send the report being written: sharing on, or "Send this one" for it.
function RW:WillSend() return Panoply.Sharing:WillSend(self.shareFlags) end

-- The flag: our own drawing (Media/Icons/J/Flag.tga) in Panoply Suite icons, the game's note icons in
-- WoW icons.
Skin.J_GLYPHS.Flag = Skin.J_GLYPHS.Flag or "Flag"
Skin.J_ICONS.Flag = Skin.J_ICONS.Flag or "Flag"
Skin.GAME_GLYPHS.Flag = Skin.GAME_GLYPHS.Flag or { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", raw = true }
Skin.GAME_ICONS.Flag = Skin.GAME_ICONS.Flag or { "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\INV_Misc_Note_01" }

-- Height of a long block of text in a scroll panel: the larger of the quick estimate and the real
-- wrapped line count (Skin.WrapMeasure), so the last lines can always be scrolled to.
local function blockH(fs, w)
  local h = Skin.TextHeight(fs, w)
  local n, lh = Skin.WrapMeasure(fs, w)
  -- the client may add a little leading between lines: allow 10% per line and one spare line,
  -- so the last line is never hidden under the bottom edge (at worst a little room is left at the end)
  if n and lh and lh > 0 then h = math.max(h, (n + 1) * lh * 1.1 + 4) end
  return h
end
RW.BlockHeight = blockH

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
function RW:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteReport", RW.WIDTH, 520, RW.TITLE_STEP, "Report a problem")
  self.frame = f
  -- what kind of report: a problem, or feedback / an idea (the same window and path)
  f.typeProblem = Skin.Button(f, "A problem", 110, 26, function() RW:SetType("problem") end, "A problem", "Something isn't working.")
  f.typeFeedback = Skin.Button(f, "Feedback / idea", 130, 26, function() RW:SetType("feedback") end, "Feedback / idea",
    "Tell us what would make Panoply Suite better. No reason is needed, only a note.")
  f.typeButtons = { f.typeProblem, f.typeFeedback }
  -- the step being reported
  f.card = Skin.Card(f)
  f.stepIcon = f.card:CreateTexture(nil, "ARTWORK"); f.stepIcon:SetSize(18, 18)
  f.stepNum = Skin.Ink(f.card, 10, Skin.colors.inkSoft)
  f.stepTitle = Skin.Name(f.card, 13)
  f.stepQuest = Skin.Ink(f.card, 11, Skin.colors.inkTitle)
  if f.stepQuest.SetWordWrap then f.stepQuest:SetWordWrap(false) end
  f.card:Hide()
  -- 0.9.5 phase 4L (spec 06 section 5): what the report is about, at the top in muted text (it replaces the step card)
  f.about = Skin.Ink(f, 12, Skin.colors.inkSoft)
  -- reasons
  f.reasonHead = Skin.Heading(f, 13); f.reasonHead:SetText("What's wrong?")
  for i, r in ipairs(R.REASONS) do
    local b = Skin.Button(f, r.label, 100, 26, function() RW:SetReason(r.key) end, r.label, "Pick the one that fits best. Send stays off until you pick one.")
    b.panoplyReason = r.key
    self.chips[i] = b
  end
  -- note
  f.noteHead = Skin.Heading(f, 13); f.noteHead:SetText("Anything else? (optional)")
  f.count = Skin.Ink(f, 10, Skin.colors.inkSoft)
  if f.count.SetJustifyH then f.count:SetJustifyH("RIGHT") end
  f.noteBox = CreateFrame("Frame", nil, f)
  f.noteBox.panoplyBox = true
  Skin.Box(f.noteBox, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  local eb = CreateFrame("EditBox", nil, f.noteBox)
  eb.panoplyLayoutSkip = true   -- typed text, not laid out by us
  if eb.SetMultiLine then eb:SetMultiLine(true) end
  if eb.SetAutoFocus then eb:SetAutoFocus(false) end
  if eb.SetMaxLetters then eb:SetMaxLetters(R.MAX_NOTE) end
  if eb.SetFont then pcall(eb.SetFont, eb, Skin.BODY, 12, "") end
  if eb.SetTextColor then local c = Skin.colors.text eb:SetTextColor(c[1], c[2], c[3], 1) end
  eb:SetPoint("TOPLEFT", f.noteBox, "TOPLEFT", 8, -6)
  eb:SetPoint("BOTTOMRIGHT", f.noteBox, "BOTTOMRIGHT", -8, 6)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function() RW:NoteChanged() end)
  f.noteBox:EnableMouse(true)
  f.noteBox:SetScript("OnMouseDown", function() if eb.SetFocus then eb:SetFocus() end end)
  f.note = eb
  f.placeholder = Skin.Text(f.noteBox, 12, Skin.colors.dim)
  f.placeholder:SetPoint("TOPLEFT", f.noteBox, "TOPLEFT", 8, -7)
  f.placeholder:SetText("For example: the quest giver isn't at this spot.")
  -- "Credit me as": optional, empty every time the window opens, never filled in for the player
  f.creditLabel = Skin.Text(f, 12)
  f.creditLabel:SetText(RW.CREDIT_LABEL)
  f.creditBox = CreateFrame("Frame", nil, f)
  f.creditBox.panoplyBox = true
  Skin.Box(f.creditBox, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  local ce = CreateFrame("EditBox", nil, f.creditBox)
  ce.panoplyLayoutSkip = true
  if ce.SetMultiLine then ce:SetMultiLine(false) end
  if ce.SetAutoFocus then ce:SetAutoFocus(false) end
  if ce.SetMaxLetters then ce:SetMaxLetters(R.MAX_CREDIT) end
  if ce.SetFont then pcall(ce.SetFont, ce, Skin.BODY, 12, "") end
  if ce.SetTextColor then local c = Skin.colors.text ce:SetTextColor(c[1], c[2], c[3], 1) end
  ce:SetPoint("TOPLEFT", f.creditBox, "TOPLEFT", 8, -4)
  ce:SetPoint("BOTTOMRIGHT", f.creditBox, "BOTTOMRIGHT", -8, 4)
  ce:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ce:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  ce:SetScript("OnTextChanged", function() RW:CreditChanged() end)
  f.creditBox:EnableMouse(true)
  f.creditBox:SetScript("OnMouseDown", function() if ce.SetFocus then ce:SetFocus() end end)
  Skin.Tooltip(f.creditBox, RW.CREDIT_LABEL, RW.CREDIT_HINT)
  f.credit = ce
  f.creditPlaceholder = Skin.Text(f.creditBox, 12, Skin.colors.dim)
  f.creditPlaceholder:SetPoint("LEFT", f.creditBox, "LEFT", 8, 0)
  f.creditPlaceholder:SetText(RW.CREDIT_PLACEHOLDER)
  -- what we'll send
  f.previewBtn = Skin.Button(f, "Show what we'll send", 180, 26, function() RW:TogglePreview() end, "What we'll send",
    "Every field of this report, exactly as it will be sent.")
  f.previewBtn:SetIcon("Plus", 14)
  f.preview = Skin.ScrollArea(f)
  f.previewText = Skin.Text(f.preview.content, 10, Skin.colors.inkSoft)
  if f.previewText.SetJustifyH then f.previewText:SetJustifyH("LEFT") end
  if f.previewText.SetJustifyV then f.previewText:SetJustifyV("TOP") end
  -- how it travels
  f.how = Skin.Text(f, 11, Skin.colors.inkSoft)
  -- buttons
  f.send = Skin.Button(f, "Send", 110, 28, function() RW:Send() end, "Send the report",
    "Shows what is included and asks you to confirm. Nothing is saved until you do.")
  f.cancel = Skin.Button(f, "Cancel", 100, 28, function() RW:Close() end, "Cancel", "Close without saving anything.")
  -- 0.8.4: the report as text the player can select and copy (UI/ReportCopy.lua); nothing is saved or sent by it
  f.copy = Skin.Button(f, "Copy as text", 130, 28, function() RW:CopyOut() end, "Copy as text",
    "Shows this report as text you can select and copy, to paste somewhere yourself. Nothing is sent.")
  f.buttons = { f.send, f.cancel, f.copy }
  f.panoplyClose:SetScript("OnClick", function() RW:Close() end)
  return f
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

-- The report as it stands right now (the snapshot taken when the window opened, plus your choices).
-- 0.9.4: never the character's name or realm (the note is scrubbed of them); "Feedback / idea" makes it kind "feedback" with no
-- reason and no step; the credit is what is typed in "Credit me as" (trimmed, at most 40 characters), absent when empty.
function RW:Current()
  local base = self.base
  if not base then return nil end
  local rep = copy(base)
  local feedback = self.type == "feedback"
  if feedback then
    rep.kind, rep.reason, rep.reasonText, rep.step = "feedback", nil, nil, nil
  else
    rep.reason = self.reason
    rep.reasonText = R.REASON_LABEL[self.reason or ""]
  end
  local note = self.frame and self.frame.note:GetText() or ""
  note = note:gsub("^%s+", ""):gsub("%s+$", "")
  if note ~= "" then rep.note = R:Scrub(R.CutNote(note), false) end
  rep.credit = R.CleanCredit(self.frame and self.frame.credit:GetText() or "")
  return rep
end

function RW:SetReason(key)
  self.reason = key
  for _, b in ipairs(self.chips) do b:SetSelected(b.panoplyReason == key) end
  self:Update()
end

-- "problem" or "feedback": the same window, the same path.
function RW:SetType(kind)
  self.type = kind == "feedback" and "feedback" or "problem"
  self:Update()
end

function RW:CreditChanged()
  local f = self.frame
  local t = f.credit:GetText() or ""
  if t == "" then f.creditPlaceholder:Show() else f.creditPlaceholder:Hide() end
  self:Update()
end

function RW:NoteChanged()
  local f = self.frame
  local t = f.note:GetText() or ""
  if #t > R.MAX_NOTE then f.note:SetText(R.CutNote(t)) t = f.note:GetText() or "" end
  if t == "" then f.placeholder:Show() else f.placeholder:Hide() end
  self:Update()
end

function RW:TogglePreview()
  self.showPreview = not self.showPreview
  self:Update()
  -- opening the panel makes the window taller: bring it back on screen when it now sticks out
  local f = self.frame
  local top, bottom = f.GetTop and f:GetTop(), f.GetBottom and f:GetBottom()
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  if top and bottom and (top > screenH or bottom < 0) then self:Place() end
end

-- Centred a little above the middle, never past the top or bottom of the screen.
function RW:Place()
  local f = self.frame
  -- 0.9.5: where the player dragged it, or beside the main window when that is open (Panoply.Windows:PlaceChild); else centred as before
  if Panoply.Windows and Panoply.Windows:PlaceChild(f) then return end
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local room = (screenH - (f:GetHeight() or 0)) / 2 - 10
  local up = math.max(0, math.min(40, room))
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, up)
end

-- "About: Goretusk Snouts, step 5 of 27 · Westfall, Westfall 52.3, 47.1" (spec 06 section 5): the step (its words and number, when the report
-- is about one) and where the player stands. nil when nothing is known.
function RW:AboutText()
  local base = self.base
  if not base then return nil end
  local parts = {}
  local st = (self.type ~= "feedback") and base.step or nil
  if st then
    if st.title and st.title ~= "" then parts[#parts + 1] = st.title end
    local num
    if self.stepRef and Panoply.StepText and Panoply.StepText.NumberText then
      local ok, t = pcall(Panoply.StepText.NumberText, self.stepRef)
      if ok and type(t) == "string" and t ~= "" then num = t end
    end
    if not num and st.index then num = ("Step %d"):format(st.index) .. (base.plan and base.plan.steps and (" of %d"):format(base.plan.steps) or "") end
    if num then parts[#parts + 1] = num:sub(1, 1):lower() .. num:sub(2) end
  end
  local w = base.where
  if w and w.zone then
    local at = w.zone
    if tonumber(w.x) and tonumber(w.y) then at = ("%s %.1f, %.1f"):format(w.zone, w.x * 100, w.y * 100) end
    parts[#parts + 1] = at
  end
  if #parts == 0 then return nil end
  return "About: " .. table.concat(parts, ", ")
end

-- Can Send be pressed: a problem needs a category (spec 06 section 5); feedback needs a note.
function RW:CanSend()
  local f = self.frame
  if self.type == "feedback" then return f and (f.note:GetText() or ""):find("%S") ~= nil or false end
  return self.reason ~= nil
end
RW.SEND_NEED_REASON = "Pick what's wrong first. Send stays off until one is picked."
RW.SEND_NEED_NOTE = "Write your idea first. Send stays off until there is a note."

-- Text, then layout (measured, top to bottom).
function RW:Update()
  local f = self.frame
  if not f or not self.base then return end
  local feedback = self.type == "feedback"
  local general = self.base.kind == "general" or feedback
  f.panoplyTitle:SetText(feedback and RW.TITLE_FEEDBACK or (general and RW.TITLE_GENERAL or RW.TITLE_STEP))
  f.panoplySubtitle:SetText(feedback and "Tell us what would make it better" or (general and "Tell us what isn't working" or "Report a problem"))
  f.typeProblem:SetSelected(not feedback)
  f.typeFeedback:SetSelected(feedback)
  f.noteHead:SetText(feedback and RW.NOTE_HEAD_FEEDBACK or RW.NOTE_HEAD)
  f.placeholder:SetText(feedback and RW.PLACEHOLDER_FEEDBACK or RW.PLACEHOLDER)
  local n = #(f.note:GetText() or "")
  f.count:SetText(("%d / %d"):format(n, R.MAX_NOTE))
  f.previewBtn.label:SetText(self.showPreview and "Hide what we'll send" or "Show what we'll send")
  f.previewBtn:SetIcon(self.showPreview and "Minus" or "Plus", 14)
  f.how:SetText(RW.HowLine())
  local c = Skin.colors.inkSoft
  f.how:SetTextColor(c[1], c[2], c[3], 1)
  -- no Panoply Hub on this computer: the report can only be saved here
  f.send.label:SetText(Panoply.Sharing:State() == "nohub" and "Save" or "Send")
  -- 0.9.5 phase 4L (spec 06 section 5): a problem needs one of the categories; feedback needs a note (0.9.4 review K2: a note of only
  -- spaces is no note). The button's tooltip says what is missing.
  local can = self:CanSend()
  f.send:SetEnabledLook(can)
  if can then f.send.tipBody = "Shows what is included and asks you to confirm. Nothing is saved until you do."
  else f.send.tipBody = feedback and RW.SEND_NEED_NOTE or RW.SEND_NEED_REASON end
  f.about:SetText(self:AboutText() or "")
  self.report = self:Current()
  if self.showPreview then f.previewText:SetText(table.concat(R:Lines(self.report), "\n")) end
  self:Layout()
end

-- The window always fits the screen: the "What we'll send" panel gives up height first.
-- Nov 2026: the report windows resize. Each is as tall as what it says (its layout sets the height), so the grip changes the
-- width and the words wrap to it; the width is remembered.
function RW:Resizable(f, key, minW, layout)
  if f.panoplyResize then return end
  Skin.Resizable(f, { key = key, minW = minW, minH = 120, onSize = function(_, _, done) if done and f:IsShown() then layout() end end })
end

function RW:Layout()
  -- then, on a short screen, the "how it travels" text (shown again when the panel closes),
  -- then the note box gets one line shorter
  self.previewCap, self.compact, self.noteH = RW.PREVIEW_H, false, RW.NOTE_H
  local h = self:LayoutOnce()
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local maxH = screenH - 40
  if h > maxH and self.showPreview then
    self.previewCap = math.max(RW.MIN_PREVIEW_H, RW.PREVIEW_H - (h - maxH))
    h = self:LayoutOnce()
    if h > maxH then
      self.compact = true
      h = self:LayoutOnce()
    end
    if h > maxH then
      self.noteH = RW.NOTE_H_SHORT
      h = self:LayoutOnce()
    end
    if h < maxH and self.previewCap < RW.PREVIEW_H then  -- give back what compacting freed
      self.previewCap = math.min(RW.PREVIEW_H, self.previewCap + (maxH - h))
      h = self:LayoutOnce()
    end
  end
  return h
end

function RW:LayoutOnce()
  local f, SP, TH = self.frame, Skin.SP, Skin.TextHeight
  local W = f:GetWidth()
  local x, tw = 18, W - 36
  local y = -66
  local feedback = self.type == "feedback"
  -- what kind of report
  for _, b in ipairs(f.typeButtons) do Skin.FitButton(b, 60, tw) end
  local th = Skin.FlowButtons(f, f.typeButtons, x, y, tw, SP.s, 60)
  y = y - th - SP.l
  -- what it is about (muted, spec 06 section 5)
  if (f.about:GetText() or "") ~= "" then
    f.about:Show()
    f.about:ClearAllPoints(); f.about:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.about:SetWidth(tw)
    y = y - TH(f.about, tw) - SP.m
  else f.about:Hide() end
  f.card:Hide()   -- 0.9.5: the step card is replaced by the About line above
  -- reasons (a problem only: feedback needs no reason)
  if feedback then
    f.reasonHead:Hide()
    for _, b in ipairs(self.chips) do b:Hide() end
  else
    f.reasonHead:Show()
    for _, b in ipairs(self.chips) do b:Show() end
    f.reasonHead:ClearAllPoints(); f.reasonHead:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    y = y - TH(f.reasonHead) - SP.s
    for _, b in ipairs(self.chips) do Skin.FitButton(b, 60, tw) end
    local ch = Skin.FlowButtons(f, self.chips, x, y, tw, SP.s, 60)
    y = y - ch - SP.l
  end
  -- note
  f.noteHead:ClearAllPoints(); f.noteHead:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  local cw = Skin.TextWidth(f.count) + 4
  f.count:ClearAllPoints(); f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -x, y - 2); f.count:SetWidth(cw)
  f.noteHead:SetWidth(tw - cw - SP.m)
  y = y - TH(f.noteHead, tw - cw - SP.m) - SP.s
  f.noteBox:ClearAllPoints(); f.noteBox:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.noteBox:SetSize(tw, self.noteH or RW.NOTE_H)
  f.placeholder:SetWidth(tw - 16)
  y = y - (self.noteH or RW.NOTE_H) - SP.m
  -- credit: the label, then the box beside it on the same row
  local lw = math.ceil(Skin.TextWidth(f.creditLabel)) + 2
  lw = math.min(lw, math.floor(tw * 0.6))
  f.creditLabel:ClearAllPoints(); f.creditLabel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 6); f.creditLabel:SetWidth(lw)
  f.creditBox:ClearAllPoints(); f.creditBox:SetPoint("TOPLEFT", f, "TOPLEFT", x + lw + SP.s, y); f.creditBox:SetSize(tw - lw - SP.s, 26)
  Skin.Ellipsize(f.creditPlaceholder, RW.CREDIT_PLACEHOLDER, tw - lw - SP.s - 16)
  y = y - math.max(26, TH(f.creditLabel, lw) + 6) - SP.m
  -- preview
  Skin.FitButton(f.previewBtn, 160, tw)
  f.previewBtn:ClearAllPoints(); f.previewBtn:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  y = y - f.previewBtn:GetHeight() - SP.s
  if self.showPreview then
    local function lay(w)
      f.previewText:ClearAllPoints(); f.previewText:SetPoint("TOPLEFT", f.preview.content, "TOPLEFT", 6, -6)
      f.previewText:SetWidth(w - 12)
      return blockH(f.previewText, w - 12) + 12
    end
    local h = lay(tw)
    local viewH = math.min(self.previewCap or RW.PREVIEW_H, h)
    if h > viewH + 0.5 then h = lay(tw - 12) end
    f.preview:ClearAllPoints(); f.preview:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.preview:SetSize(tw, viewH)
    f.preview.content:SetWidth(f.preview:ContentWidth(h))
    f.preview:SetContentHeight(h)
    f.preview:Show(); f.previewText:Show()
    y = y - viewH - SP.m
  else
    f.preview:Hide()
  end
  -- how it travels
  if self.compact then
    f.how:Hide()
  else
    f.how:Show()
    f.how:ClearAllPoints(); f.how:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.how:SetWidth(tw)
    y = y - TH(f.how, tw) - SP.m
  end
  local bh = 0
  for _, b in ipairs(f.buttons) do Skin.FitButton(b, 90) bh = math.max(bh, b:GetHeight()) end
  bh = Skin.FlowButtons(f, f.buttons, x, y, tw, SP.m, 90)
  y = y - bh - SP.l
  f:SetHeight(-y)
  return -y
end

-- opts: { step =, index = } for a step, { general = true } for a general report, { feedback = true } for "Feedback / idea"; note =
-- words to start the note with (the player can change them: "Report a missing place" in the Go to window).
function RW:Open(opts)
  opts = opts or {}
  if not R.db then R:InitDB() end
  local f = self:Create()
  self:Resizable(f, "report", RW.WIDTH - 80, function() RW:Layout() end)
  local E = Panoply.Engine
  local step, index = opts.step, opts.index
  local general = opts.general or opts.feedback
  if not general and not step and E and E.Current then step, index = E:Current(), E.index end
  if not step then general = true end
  self.base = R:Build({ kind = general and "general" or "step", step = step, index = index })
  self.stepRef = (not general) and step or nil
  if not general then
    local ST = Panoply.StepText
    Skin.SetIcon(f.stepIcon, Panoply.UI and Panoply.UI.StepIconName and Panoply.UI.StepIconName(step) or "Accept")
    -- the title the player saw (a travel step's own wording)
    if ST and self.base.step then self.base.step.title = self.base.step.title or ST.Headline(step) end
  end
  local pi = Panoply.Compat and Panoply.Compat.PlayerInfo and Panoply.Compat.PlayerInfo() or {}
  self.identity = { name = pi.name, realm = pi.realm }
  self.reason, self.showPreview = nil, false
  self.type = opts.feedback and "feedback" or "problem"
  RW.Consent:Close()
  for _, b in ipairs(self.chips) do b:SetSelected(false) end
  f.note:SetText("")
  f.placeholder:Show()
  -- "Credit me as" starts empty every time: never filled from the character name, an earlier report or anywhere else
  f.credit:SetText("")
  f.creditPlaceholder:Show()
  if type(opts.note) == "string" and opts.note ~= "" then
    f.note:SetText(R.CutNote(opts.note))
    f.placeholder:Hide()
  end
  R:Crumb("REPORT_OPEN", general and "general" or "step")
  self:Update()
  self:Place()
  f:Show()
  return f
end

function RW:Close()
  self.base, self.report, self.shareFlags = nil, nil, nil
  RW.Consent:Close()
  if RW.Share then RW.Share:Close() end
  if self.frame then
    if self.frame.note.ClearFocus then self.frame.note:ClearFocus() end
    if self.frame.credit then
      if self.frame.credit.ClearFocus then self.frame.credit:ClearFocus() end
      self.frame.credit:SetText("")
    end
    self.frame:Hide()
  end
end

-- 0.8.4: every line of the report as it stands now, in a window where it can be selected and copied. Returns that window.
function RW:CopyOut()
  if not (self.base and Panoply.ReportCopy) then return nil end
  return Panoply.ReportCopy:Open(R:Lines(self:Current()))
end

-- The window's Send button: nothing is saved yet. It opens the consent notice (what is included, what is not, what "Send and
-- reload" does); the three buttons there decide. Returns the notice window.
-- 0.9.5 phase 4A4 (06b section 2): with Panoply Hub installed and sharing off, the one question comes first ("Send this report with
-- Panoply Hub?"); its answer is kept for this report (RW.shareFlags) and the notice follows, except for "Keep it on this computer",
-- which saves at once.
function RW:Send()
  if not self.base or self.frame.send.disabled then return nil end
  if Panoply.Sharing:NeedsPrompt(self.shareFlags) then return RW.Share:Open() end
  return RW.Consent:Open()
end

-- Save the report now (the player pressed "Send and reload" or "Send later"). reload = true also reloads the interface: at once
-- outside combat, after combat otherwise (the saved report is safe either way). Returns the stored report, and what the reload
-- did: "now", "after_combat", "unavailable" or nil (no reload asked for).
function RW:Commit(reload)
  if not self.base then return nil end
  local cur = self:Current()
  for k, v in pairs(self.shareFlags or {}) do cur[k] = v end   -- the answer to the sharing question, for this report only
  local rep, why
  if cur.keepLocal then rep, why = R:SubmitLocal(cur) else rep, why = R:Submit(cur) end
  if not rep then
    -- 0.9.4 (review K2): a refused save never leaves the player with a hidden window: the notice closes and the report window
    -- (its note, reason and credit kept) comes back, with the reason in chat
    RW.Consent:Close()
    if self.frame then self.frame:Show() self:Update() end
    Panoply:Print("Not saved: " .. tostring(why) .. ".")
    return nil
  end
  local on = Panoply.Sharing:WillSend(rep)
  local state
  if reload then state = R:ReloadNow() end
  self:Close()
  Panoply:Print(on and RW.SAVED or RW.SAVED_OFF)
  if Panoply.Toast and Panoply.Toast.Show then pcall(Panoply.Toast.Show, Panoply.Toast, Panoply.Sharing:SavedWords(rep)) end
  if state == "after_combat" then
    Panoply:Print(RW.COMBAT)
    RW.Consent:ShowCombat()
  elseif state == "unavailable" then
    Panoply:Print(RW.NO_RELOAD)
  end
  return rep, state
end
function RW:SendAndReload() return self:Commit(true) end
function RW:SendLater() return self:Commit(false) end
RW.COMBAT = "Your report is saved. You are in combat, so the game will reload as soon as combat ends. Nothing else to do."
RW.NO_RELOAD = "This game version can't reload from here. Type /reload to send your report now."

-------------------------------------------------------------------------------
-- The consent notice (0.9.4): shown after Send, before anything is saved.
-------------------------------------------------------------------------------
local RC = {}
RW.Consent = RC
RC.WIDTH = 480
RC.TITLE, RC.TITLE_SAVED = "Before you send", "Report saved"
RC.INTRO = "This report includes:"
RC.INCLUDED = {
  "the zone you are in and the guide step",
  "the Panoply Suite add-on version and the game version",
  "the note you wrote",
  "the text of recent Panoply Suite errors",
}
-- 0.9.4 (review K6): the list above is our; a report also saves a few more things (level, faction, map position, quest IDs, route,
-- settings), so this one true sentence follows it and points at the full list
RC.ALSO = "It also includes your level, faction and where you are on the route; \"Show what we'll send\" lists everything."
RC.NOT = "It does not include your character name, realm, race or class."
RC.NEEDS = "To send it, the companion app must be running on this computer."
RC.CHOICES = "\"Send and reload\" reloads the game's interface (the UI) now, so your report is saved and can be sent. \"Send later\" saves it without reloading; it goes out after your next reload or logout. \"Cancel\" saves nothing."
RC.CREDIT_NONE, RC.CREDIT_NAMED = "No credit name: you stay anonymous.", "Credit name: %s"

-- The notice text for the report as it stands (the credit line echoes what was typed).
function RC:Text()
  local lines = { RC.INTRO }
  for _, l in ipairs(RC.INCLUDED) do lines[#lines + 1] = "- " .. l end
  lines[#lines + 1] = " "
  lines[#lines + 1] = RC.ALSO
  lines[#lines + 1] = " "
  lines[#lines + 1] = RC.NOT
  lines[#lines + 1] = " "
  lines[#lines + 1] = RC.NEEDS
  -- sending off: the buttons say save, so the sentence that names them does too
  lines[#lines + 1] = RW:WillSend() and RC.CHOICES or (RC.CHOICES:gsub("Send and reload", "Save and reload"):gsub("Send later", "Save for later"))
  local rep = RW.base and RW:Current()
  lines[#lines + 1] = " "
  lines[#lines + 1] = rep and rep.credit and RC.CREDIT_NAMED:format(rep.credit) or RC.CREDIT_NONE
  return table.concat(lines, "\n")
end

function RC:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteReportConsent", RC.WIDTH, 360, RC.TITLE, "Your report", "DIALOG", "Flag")
  self.frame = f
  f.body = Skin.Text(f, 12)
  if f.body.SetJustifyH then f.body:SetJustifyH("LEFT") end
  f.state = Skin.Text(f, 11, Skin.colors.warn)
  f.sendReload = Skin.Button(f, "Send and reload", 140, 28, function() RW:SendAndReload() end, "Send and reload",
    "Saves your report and reloads the game's interface now. The companion app then sends it.")
  f.sendLater = Skin.Button(f, "Send later", 110, 28, function() RW:SendLater() end, "Send later",
    "Saves your report without reloading. It is sent after your next reload or logout.")
  f.cancel = Skin.Button(f, "Cancel", 100, 28, function() RW:Close() end, "Cancel", "Closes this. Nothing is saved.")
  f.ok = Skin.Button(f, "OK", 100, 28, function() RC:Close() end, "OK", "Close this.")
  f.panoplyClose:SetScript("OnClick", function() if RC.mode == "consent" then RW:Close() else RC:Close() end end)
  return f
end

function RC:Layout()
  local f, SP, TH = self.frame, Skin.SP, Skin.TextHeight
  local x, tw = 18, f:GetWidth() - 36
  local y = -66
  f.body:ClearAllPoints(); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.body:SetWidth(tw)
  y = y - blockH(f.body, tw) - SP.m
  local sendOn = RW:WillSend()
  if self.mode == "consent" and not sendOn then
    f.state:SetText(RW.HowLine())
    f.state:ClearAllPoints(); f.state:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.state:SetWidth(tw); f.state:Show()
    y = y - TH(f.state, tw) - SP.m
  else
    f.state:Hide()
  end
  local list
  if self.mode == "consent" then
    -- sending off: nothing leaves, so the buttons say "save" (the reload still writes the file)
    f.sendReload.label:SetText(sendOn and "Send and reload" or "Save and reload")
    f.sendLater.label:SetText(sendOn and "Send later" or "Save for later")
    list = { f.sendReload, f.sendLater, f.cancel }
    f.ok:Hide()
  else
    list = { f.ok }
    f.sendReload:Hide(); f.sendLater:Hide(); f.cancel:Hide()
  end
  for _, b in ipairs(list) do b:Show() Skin.FitButton(b, 90) end
  local bh = Skin.FlowButtons(f, list, x, y, tw, SP.m, 90)
  y = y - bh - SP.l
  f:SetHeight(-y)
  return -y
end

function RC:Place()
  local f = self.frame
  if Panoply.Windows and Panoply.Windows:PlaceChild(f) then return end
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local up = math.max(0, math.min(40, (screenH - (f:GetHeight() or 0)) / 2 - 10))
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, up)
end

-- mode "consent" (before saving) or "saved" (the in-combat message after saving)
function RC:Show(mode)
  local f = self:Create()
  self.mode = mode
  RW:Resizable(f, "reportConsent", RC.WIDTH - 80, function() if RC.frame:IsShown() then RC:Relayout() end end)
  self:Relayout()
  self:Place()
  f:Show()
  return f
end

function RC:Relayout()
  local f = self.frame
  if self.mode == "consent" then
    f.panoplyTitle:SetText(RC.TITLE)
    f.panoplySubtitle:SetText("Your report")
    f.body:SetText(RC:Text())
  else
    f.panoplyTitle:SetText(RC.TITLE_SAVED)
    f.panoplySubtitle:SetText("Your report")
    f.body:SetText(RW.COMBAT)
  end
  return self:Layout()
end

-- The notice takes the report window's place (the window is only hidden: its note, reason and credit are kept until a button
-- here decides). Cancel, the window's X and RW:Close end it all and save nothing.
function RC:Open()
  local f = self:Show("consent")
  if RW.frame and RW.frame:IsShown() then RW.frame:Hide() end
  return f
end

-- After "Send and reload" in combat: the report is saved, the reload waits for the end of combat.
function RC:ShowCombat()
  return self:Show("saved")
end

function RC:Close()
  if self.frame then self.frame:Hide() end
end

-------------------------------------------------------------------------------
-- 0.9.5 phase 4A4 (06b section 2): the sharing question. Shown on Send while Panoply Hub is installed and "Send reports with Panoply Hub"
-- is off, before the notice. Its answer is for this report: "Send this one" (Hub sends this one; the setting stays off), "Always send"
-- (turns the setting on), "Keep it on this computer" (saved here at once, and this report is never asked about again). The X goes back
-- to the report window; nothing is saved.
-------------------------------------------------------------------------------
local RS = {}
RW.Share = RS
RS.WIDTH = 460
-- 0.9.5 phase 4L (06b section 3): the state line, word for word, then where the setting is (no other words about what leaves the computer)
function RS.Body() return Panoply.Sharing:Line() .. " You can change this any time in " .. Panoply:SettingsPath("send") .. "." end

function RS:Create()
  if self.frame then return self.frame end
  local S = Panoply.Sharing
  local f = Skin.Window("PanoplySuiteReportShare", RS.WIDTH, 200, S.PROMPT_TITLE, "Your report", "DIALOG", "Flag")
  self.frame = f
  f.body = Skin.Text(f, 12)
  if f.body.SetJustifyH then f.body:SetJustifyH("LEFT") end
  f.one = Skin.Button(f, S.PROMPT_ONE, 130, 28, function() RS:Choose("one") end, S.PROMPT_ONE,
    "Panoply Hub sends this report. The setting stays off, so you are asked again next time.")
  f.always = Skin.Button(f, S.PROMPT_ALWAYS, 120, 28, function() RS:Choose("always") end, S.PROMPT_ALWAYS,
    "Turns on " .. S.SETTING .. ". Panoply Hub sends this report and the ones after it.")
  f.keep = Skin.Button(f, S.PROMPT_KEEP, 180, 28, function() RS:Choose("keep") end, S.PROMPT_KEEP,
    "Saves this report on this computer only. It is not sent, and you are not asked about it again.")
  f.panoplyClose:SetScript("OnClick", function() RS:Back() end)
  return f
end

function RS:Layout()
  local f, SP, TH = self.frame, Skin.SP, Skin.TextHeight
  -- wide enough for the whole question beside the icon and the close button, at any text size
  local need = math.ceil(Skin.TextWidth(f.panoplyTitle) or 0) + 150
  f:SetWidth(math.max(RS.WIDTH, need))
  local x, tw = 18, f:GetWidth() - 36
  local y = -66
  f.body:SetText(RS.Body())
  f.body:ClearAllPoints(); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.body:SetWidth(tw)
  y = y - TH(f.body, tw) - SP.m
  local list = { f.one, f.always, f.keep }
  for _, b in ipairs(list) do b:Show() Skin.FitButton(b, 90) end
  local bh = Skin.FlowButtons(f, list, x, y, tw, SP.m, 90)
  y = y - bh - SP.l
  f:SetHeight(-y)
  return -y
end

function RS:Open()
  local f = self:Create()
  self:Layout()
  RC.Place(self)
  f:Show()
  if RW.frame and RW.frame:IsShown() then RW.frame:Hide() end
  return f
end

function RS:Close() if self.frame then self.frame:Hide() end end

-- the X: back to the report window as it was
function RS:Back()
  self:Close()
  if RW.base and RW.frame then RW.frame:Show() RW:Update() end
end

-- One of the three answers. Returns what came next: the notice window, or the saved report ("keep").
function RS:Choose(choice)
  if not RW.base then self:Close() return nil end
  local flags = {}
  Panoply.Sharing:Answer(flags, choice)
  RW.shareFlags = flags
  self:Close()
  if choice == "keep" then return RW:Commit(false) end
  return RC:Open()
end

-------------------------------------------------------------------------------
-- "Noted problems": Panoply Suite's own errors, every line exactly as it is sent
-- (R:ErrorLines), so the player can read what error capture keeps before anything goes out.
-------------------------------------------------------------------------------
local PV = {}
RW.Problems = PV
PV.WIDTH, PV.MAX_VIEW = 560, 420
PV.TITLE = "Noted Panoply Suite problems"
-- 0.9.5 phase 4L (spec 06 section 6): a readable list. The header line is kept word for word.
PV.INTRO = "Only Panoply Suite's own errors are noted. Errors from the game or other add-ons are passed on untouched and never kept."
PV.EMPTY = "No problems noted. Panoply Suite hasn't hit an error on this computer (or the list was cleared)."
function PV.ShareLine() return Panoply.Sharing:Line() end   -- 0.9.5 phase 4A4: the sharing state line, at the bottom of the list
PV.OFF_CAPTURE = "Noting errors is off: new problems are not kept."
PV.REPEATING = 50          -- more than this many times: the Repeating chip
PV.CLEAR_ASK = "Clear every noted problem from this computer?"

-- Every noted problem, newest first, as it is sent.
function PV:Lines()
  local db = R.db
  local list = {}
  for _, e in pairs(db and db.errors or {}) do if type(e) == "table" then list[#list + 1] = e end end
  table.sort(list, function(a, b)
    if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
    return tostring(a.sig) < tostring(b.sig)
  end)
  local out = {}
  for i, e in ipairs(list) do
    if i > 1 then out[#out + 1] = " " end
    for _, l in ipairs(R:ErrorLines(e)) do out[#out + 1] = l end
  end
  return out, #list
end

-- One problem's short title: the first line of the error without its file and line ("attempt to compare ...").
function PV.Title(e)
  local m = tostring(e and e.msg or ""):match("^[^\n]*") or ""
  m = m:gsub("^.-%.lua:%d+:%s*", "")
  if m == "" then m = "An error with no message" end
  if #m > 90 then m = m:sub(1, 87) .. "..." end
  return m:sub(1, 1):upper() .. m:sub(2)
end
-- The Panoply Suite part it came from: the file inside the add-on ("Engine/Route.lua"), or what it was doing when it was caught.
function PV.Module(e)
  local hay = tostring(e and e.msg or "") .. "\n" .. table.concat(type(e and e.stack) == "table" and e.stack or {}, "\n")
  local f = hay:match("PanoplySuite[_%w]*[/\\](.-%.lua)")
  if f then return (f:gsub("\\", "/")) end
  f = hay:match("([%w_/\\]+%.lua):%d+")
  if f then return (f:gsub("\\", "/"):gsub("^.*AddOns/", "")) end
  return e and e.where or "Panoply Suite"
end

-- The rows: every noted problem, most counted first (spec 06 section 6).
function PV:Rows()
  local db = R.db
  local list = {}
  for _, e in pairs(db and db.errors or {}) do if type(e) == "table" then list[#list + 1] = e end end
  table.sort(list, function(a, b)
    if (a.count or 1) ~= (b.count or 1) then return (a.count or 1) > (b.count or 1) end
    if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
    return tostring(a.sig) < tostring(b.sig)
  end)
  local out = {}
  for i, e in ipairs(list) do
    out[i] = { e = e, sig = e.sig, title = PV.Title(e), module = PV.Module(e), count = e.count or 1,
      first = e.first, last = e.last, version = e.version, fixedIn = e.fixedIn, repeating = (e.count or 1) > PV.REPEATING }
  end
  return out
end

-- one row's facts in a line: "Engine/Route.lua · 695 times · first Nov 3 14:02 · last today 09:15 · Panoply Suite 0.8.2"
function PV.FactsLine(r)
  local S = Panoply.Sharing
  local t = { r.module, ("%d time%s"):format(r.count, r.count == 1 and "" or "s") }
  if tonumber(r.first) then t[#t + 1] = "first " .. S.When(r.first) end
  if tonumber(r.last) then t[#t + 1] = "last " .. S.When(r.last) end
  if r.version then t[#t + 1] = "Panoply Suite " .. tostring(r.version) end
  return table.concat(t, " \194\183 ")
end

-- The text of one problem (the expanded box and Copy as text): every line as it is sent.
function PV.Detail(e) return table.concat(R:ErrorLines(e), "\n") end

function PV:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteReportProblems", PV.WIDTH, 420, PV.TITLE, "Noted problems", "DIALOG", "Flag")
  self.frame = f
  self.open = {}
  f.intro = Skin.Text(f, 12)
  f.intro:SetText(PV.INTRO)
  f.state = Skin.Text(f, 11, Skin.colors.inkSoft)
  f.view = Skin.ScrollArea(f)
  f.rows = {}
  f.empty = Skin.Text(f.view.content, 12, Skin.colors.inkSoft)
  f.empty:SetText(PV.EMPTY)
  -- Copy as text (all), Clear (asks first), Close
  f.copy = Skin.Button(f, "Copy all as text", 140, 28, function() if Panoply.ReportCopy then Panoply.ReportCopy:Open((PV:Lines())) end end, "Copy all as text",
    "Shows every noted problem as text you can select and copy, to paste somewhere yourself. Nothing is sent.")
  f.clear = Skin.Button(f, "Clear", 90, 28, function() PV.asking = true PV:Layout() end, "Clear", "Removes every noted problem from this computer. It asks first.")
  f.close = Skin.Button(f, "Close", 100, 28, function() PV:Close() end, "Close", "Close this list.")
  f.buttons = { f.copy, f.clear, f.close }
  f.ask = Skin.Text(f, 12, Skin.colors.warn)
  f.ask:SetText(PV.CLEAR_ASK)
  f.yes = Skin.Button(f, "Clear them", 110, 28, function() PV.asking = nil R:ClearErrors() PV:Layout() end, "Clear them", "Removes every noted problem now.")
  f.keep = Skin.Button(f, "Keep", 80, 28, function() PV.asking = nil PV:Layout() end, "Keep", "Keeps them.")
  f.panoplyClose:SetScript("OnClick", function() PV:Close() end)
  return f
end

local function pvRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, f.view.content)
  r.panoplyGapOK = true
  r.head = Skin.Button(r, "", 100, 44, function(self) local k = self.sig PV.open[k] = not PV.open[k] or nil PV:Layout() end, nil, nil)
  r.head.label:SetText("")
  r.head.tip = nil
  r.title = Skin.Name(r.head, 13, Skin.colors.text)
  r.facts = Skin.Ink(r.head, 11, Skin.colors.inkSoft)
  r.chev = r.head:CreateTexture(nil, "ARTWORK")      -- the kit's chevron (the same as every section's)
  r.chev:SetSize(Panoply.Kit.SECTION.chevron, Panoply.Kit.SECTION.chevron)
  local gc = Skin.colors.gold
  r.chev:SetVertexColor(gc[1], gc[2], gc[3], 1)
  r.chip = Panoply.Kit.StatusChip(r.head, "state.warn", "Repeating")
  r.fixed = Panoply.Kit.StatusChip(r.head, "state.good", "Fixed")
  r.box = CreateFrame("Frame", nil, r)
  r.box.panoplyBox = true
  Skin.Box(r.box, "S", { fill = Skin.colors.card, fillA = 1, line = Skin.colors.hairline })
  r.text = Skin.Text(r.box, 10, Skin.colors.inkSoft)
  if r.text.SetJustifyH then r.text:SetJustifyH("LEFT") end
  if r.text.SetJustifyV then r.text:SetJustifyV("TOP") end
  if Skin.MONO and r.text.SetFont then pcall(r.text.SetFont, r.text, Skin.MONO, 10, "") end
  r.copy = Skin.Button(r, "Copy as text", 120, 24, function(self) if Panoply.ReportCopy and self.e then Panoply.ReportCopy:Open(R:ErrorLines(self.e)) end end,
    "Copy as text", "Shows this problem as text you can select and copy. Nothing is sent.")
  f.rows[i] = r
  return r
end

function PV:Layout()
  local f, SP, TH = self.frame, Skin.SP, Skin.TextHeight
  local x, tw = 18, f:GetWidth() - 36
  local y = -66
  f.intro:ClearAllPoints(); f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.intro:SetWidth(tw)
  y = y - TH(f.intro, tw) - SP.m
  local rows = self:Rows()
  self.shown = rows
  -- the list, in a scroll area
  local function lay(w)
    local ly = 0
    for i, r in ipairs(rows) do
      local row = pvRow(f, i)
      row:Show()
      local open = self.open[r.sig] and true or false
      local h = row.head
      h.sig = r.sig
      row.title:SetText(r.title)
      row.facts:SetText(PV.FactsLine(r))
      if Skin.Sections and Skin.Sections.SetChevron then Skin.Sections.SetChevron(row.chev, open) end
      -- chips on the right: Repeating (over 50), and Fixed in <version> for a problem a later version fixed (phase 4A4's fixedIn)
      local cx = w - 30
      local chipsW = 0
      if r.repeating then row.chip:Set("state.warn", "Repeating") row.chip:Show() else row.chip:Hide() end
      if r.fixedIn then row.fixed:Set("state.good", "Fixed in " .. tostring(r.fixedIn)) row.fixed:Show() else row.fixed:Hide() end
      for _, c in ipairs({ row.chip, row.fixed }) do
        if c:IsShown() then
          local cw = c:GetWidth() or 60
          cx = cx - cw
          c:ClearAllPoints(); c:SetPoint("TOPLEFT", h, "TOPLEFT", cx, -8)
          cx = cx - SP.s
          chipsW = chipsW + cw + SP.s
        end
      end
      local textW = w - 12 - 30 - chipsW - SP.s
      row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", h, "TOPLEFT", 12, -8); row.title:SetWidth(textW)
      local th = TH(row.title, textW); row.title:SetHeight(th)
      row.facts:ClearAllPoints(); row.facts:SetPoint("TOPLEFT", h, "TOPLEFT", 12, -8 - th - 2); row.facts:SetWidth(w - 12 - 30)
      local fh = TH(row.facts, w - 12 - 30); row.facts:SetHeight(fh)
      local hh = math.max(40, 8 + th + 2 + fh + 8)
      row.chev:ClearAllPoints(); row.chev:SetPoint("RIGHT", h, "RIGHT", -12, 0)
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); h:SetSize(w, hh)
      local rh = hh
      if open then
        -- the error, its stack and the recent events, exactly as they are kept and sent
        row.text:SetText(PV.Detail(r.e))
        row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", row.box, "TOPLEFT", 8, -6); row.text:SetWidth(w - 16)
        local bh = blockH(row.text, w - 16) + 12
        row.box:ClearAllPoints(); row.box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(rh + SP.xs)); row.box:SetSize(w, bh)
        row.box:Show(); row.text:Show()
        rh = rh + SP.xs + bh + SP.xs
        row.copy.e = r.e
        Skin.FitButton(row.copy, 100, w)
        row.copy:ClearAllPoints(); row.copy:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -rh)
        row.copy:Show()
        rh = rh + row.copy:GetHeight() + SP.xs
      else
        row.box:Hide(); row.text:Hide(); row.copy:Hide()
      end
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", f.view.content, "TOPLEFT", 0, -ly); row:SetSize(w, rh)
      ly = ly + rh + SP.s
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    if #rows == 0 then
      f.empty:Show()
      f.empty:ClearAllPoints(); f.empty:SetPoint("TOPLEFT", f.view.content, "TOPLEFT", 6, -6); f.empty:SetWidth(w - 12)
      ly = TH(f.empty, w - 12) + 12
    else f.empty:Hide() end
    return ly
  end
  -- the foot: the sharing state line (06b section 3), and a word when noting is off
  local foot = { PV.ShareLine() }
  if not R:Setting("captureErrors") then foot[#foot + 1] = PV.OFF_CAPTURE end
  f.state:SetText(table.concat(foot, " "))
  f.state:SetWidth(tw)
  local stateH = TH(f.state, tw)
  local list = PV.asking and { f.yes, f.keep } or f.buttons
  for _, b in ipairs({ f.copy, f.clear, f.close, f.yes, f.keep }) do b:Hide() end
  local bh = 0
  for _, b in ipairs(list) do b:Show() Skin.FitButton(b, 80) bh = math.max(bh, b:GetHeight()) end
  f.clear:SetEnabledLook(#rows > 0)     -- (Copy stays on: with nothing noted it says so, as before)
  local askH = PV.asking and (TH(f.ask, tw) + SP.s) or 0
  -- the list gets what is left of the screen after everything else (never past the top or bottom)
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local rest = -y + SP.m + stateH + SP.m + askH + bh + SP.l
  local cap = math.max(80, math.min(PV.MAX_VIEW, screenH - 40 - rest))
  local h = lay(tw)
  local viewH = math.min(cap, h)
  if h > viewH + 0.5 then h = lay(tw - 12) end
  f.view:ClearAllPoints(); f.view:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.view:SetSize(tw, viewH)
  f.view.content:SetWidth(f.view:ContentWidth(h))
  f.view:SetContentHeight(h)
  y = y - viewH - SP.m
  f.state:ClearAllPoints(); f.state:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  y = y - stateH - SP.m
  if PV.asking then
    f.ask:Show(); f.ask:ClearAllPoints(); f.ask:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.ask:SetWidth(tw)
    y = y - TH(f.ask, tw) - SP.s
  else f.ask:Hide() end
  bh = Skin.FlowButtons(f, list, x, y, tw, SP.m, 80)
  y = y - bh - SP.l
  f:SetHeight(-y)
  return -y, #rows
end

function PV:Open()
  if not R.db then R:InitDB() end
  local f = self:Create()
  PV.asking = nil
  RW:Resizable(f, "reportProblems", PV.WIDTH - 80, function() PV:Layout() end)
  self:Layout()
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local up = math.max(0, math.min(40, (screenH - (f:GetHeight() or 0)) / 2 - 10))
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, up)
  -- opened from the report window: it closes with it
  if RW.frame and RW.frame:IsShown() then Skin.Popups:Child(f, RW.frame) else f.panoplyDialogParent = nil end
  f:Show()
  return f
end
function RW:OpenProblems() return PV:Open() end

function PV:Close() if self.frame then self.frame:Hide() end end

Panoply:Listen("REPORTS_CHANGED", function()
  if PV.frame and PV.frame:IsShown() then PV:Layout() end
end)

-------------------------------------------------------------------------------
-- Notices about your reports (0.9.4): "Report queued" after a reload, "Report PS-0042 received" when the companion app has
-- recorded a ticket number, "PS-0042 was fixed in 0.9.5. Thank you." when it is fixed. Each is shown once (Core/Reports.lua
-- R:TakeNotices decides and remembers), all together in ONE small card at the next load, never a pile of windows.
-------------------------------------------------------------------------------
local NT = {}
RW.Notices = NT
NT.WIDTH, NT.DELAY = 420, 4
NT.TITLE = "Your reports"

function NT:Create()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "PanoplySuiteReportNotice", UIParent)
  self.frame = f
  f:SetSize(NT.WIDTH, 120)
  f:SetPoint("TOP", UIParent, "TOP", 0, -300)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  Skin.Panel(f, 1, nil, "M")
  f.crest = f:CreateTexture(nil, "ARTWORK"); f.crest:SetSize(44, 44); Skin.Logo(f.crest)
  f.crest:SetPoint("CENTER", f, "TOPLEFT", 44, -46)
  f.head = Skin.Heading(f, 16, NT.TITLE)
  f.body = Skin.Text(f, 12)
  if f.body.SetJustifyH then f.body:SetJustifyH("LEFT") end
  f.ok = Skin.Button(f, "OK", 80, 26, function() NT:Hide() end, "OK", "Close this.")
  f.buttons = { f.ok }
  f:Hide()
  return f
end

function NT:Layout()
  local f, SP = self.frame, Skin.SP
  local W = f:GetWidth()
  local x, tw = 88, W - 88 - 18
  local y = -18
  f.head:ClearAllPoints(); f.head:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.head:SetWidth(tw)
  y = y - Skin.TextHeight(f.head, tw) - SP.xs
  f.body:ClearAllPoints(); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.body:SetWidth(tw)
  y = y - blockH(f.body, tw) - SP.m
  local bh = Skin.FlowButtons(f, f.buttons, x, y, tw, SP.s, 64)
  y = y - bh - SP.l
  f:SetHeight(math.max(96, -y))
end

-- Show the lines in the one card.
function NT:Show(lines)
  if not lines or #lines == 0 then return nil end
  local f = self:Create()
  f.body:SetText(table.concat(lines, "\n"))
  self:Layout()
  f:Show()
  return f
end
function NT:Hide() if self.frame then self.frame:Hide() end end

-- Take what is owed (once) and show it.
-- 0.9.4 (review K10): what was shown is marked as shown only AFTER the card has been drawn; an error in drawing leaves it owed.
function NT:Run()
  if not R.db then return nil end
  local lines, commit = R:OwedNotices()
  local f = self:Show(lines)
  commit()
  return f
end

-- a few seconds after login or /reload, so it does not land on the loading screen
Panoply:On("PLAYER_LOGIN", function()
  local C = Panoply.Compat
  local run = function() NT:Run() end
  if C and C.After then C.After(NT.DELAY, run) else run() end
end)

-------------------------------------------------------------------------------
-- Ways in
-------------------------------------------------------------------------------
local function stepAt(idx)
  local E = Panoply.Engine
  return E and E.steps and E.steps[idx], idx
end

-- A small right-click menu for a step row.
function RW:RowMenu(owner, idx)
  local s = stepAt(idx)
  if not s then return end
  return Skin.Menu(owner, {
    { text = "Report a problem...", tip = ("Tell us what's wrong with step %d."):format(idx),
      func = function() RW:Open({ step = s, index = idx }) end },
  })
end

-- parent: the frame the hit area belongs to (and is clipped by); win: the window a left-drag on it moves (default: the parent)
local function rowHit(parent, win)
  win = win or parent
  local h = CreateFrame("Button", nil, parent)
  h.panoplyLayoutSkip = true
  if h.RegisterForClicks then h:RegisterForClicks("RightButtonUp") end
  h:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.panoplyIndex then return RW:RowMenu(self, self.panoplyIndex) end
  end)
  -- left-drag still moves the window underneath
  if h.RegisterForDrag then h:RegisterForDrag("LeftButton") end
  h:SetScript("OnDragStart", function() local fn = win.GetScript and win:GetScript("OnDragStart") if fn then fn(win) end end)
  h:SetScript("OnDragStop", function() local fn = win.GetScript and win:GetScript("OnDragStop") if fn then fn(win) end end)
  h:Hide()
  return h
end

-- Guide window: the report button (hidden since 0.9.5 phase 4K; the actions menu opens it), and right-click on the Up next rows.
local UI = Panoply.UI
if UI and not UI.panoplyReportHooked then
  UI.panoplyReportHooked = true
  local create, refresh = UI.Create, UI.Refresh
  function UI:Create(...)
    local had = self.frame
    local r = create(self, ...)
    if not had and self.frame and self.card then
      local b = Skin.IconButton(self.card, "Flag", 18, function() RW:Open() end, "Report a problem",
        "Something wrong with this step? Tell us. Your report is saved on this computer first.")
      b:Hide()
      self.reportBtn = b
      self.upHits = {}
      for i, l in ipairs(self.upLines or {}) do
        -- Nov 2026: the Up next rows scroll with the guide's body, so their click areas live in the same clipping frame (a row
        -- scrolled out of view must not take a click meant for the buttons under it)
        local h = rowHit(self.clip or self.frame, self.frame)
        -- 0.7.1: no vertical padding: with 2 px above and below, neighbouring rows' click areas
        -- overlapped at the same frame level (the client then picks either one for a right-click)
        h:SetPoint("TOPLEFT", self.upIcons[i], "TOPLEFT", -2, 0)
        h:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, 0)
        self.upHits[i] = h
        -- 0.9.5 r095: since phase 4K a row that bundles several quests is a button itself (a click lists every quest). Over it
        -- the click area above would take that click, so on such a row the row's own button takes the right-click and the drag too
        local row = self.upRows and self.upRows[i]
        if row and not row.panoplyReportClicks then
          row.panoplyReportClicks = true
          if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
          local click = row:GetScript("OnClick")
          row:SetScript("OnClick", function(s, button, ...)
            if button == "RightButton" then
              if s.panoplyIndex then return RW:RowMenu(s, s.panoplyIndex) end
              return
            end
            if click then return click(s, button, ...) end
          end)
          local win = self.frame
          if row.RegisterForDrag then row:RegisterForDrag("LeftButton") end
          row:SetScript("OnDragStart", function() local fn = win.GetScript and win:GetScript("OnDragStart") if fn then fn(win) end end)
          row:SetScript("OnDragStop", function() local fn = win.GetScript and win:GetScript("OnDragStop") if fn then fn(win) end end)
        end
      end
    end
    return r
  end
  function UI:Refresh(...)
    local r = refresh(self, ...)
    local b = self.reportBtn
    if b and self.frame then
      -- 0.9.5 phase 4K (spec 06a section 3.3): no flag beside the step number any more; Report a problem is in the actions row's
      -- menu (UI:ActionsMenuItems). The button stays, hidden, as the one way that menu entry and old key paths open the report.
      b:Hide()
      local E = Panoply.Engine
      local step = E and E.Current and E:Current()
      local prof = step and step.isProf
      for i, h in ipairs(self.upHits or {}) do
        local l = self.upLines[i]
        local idx = (self.mode == "step" and E.index or 0) + i
        if self.mode == "install" or (step and step.isTravel) then idx = E.index + i - 1 end
        -- 0.9.5 r095: the row (phase 4K) is hidden on every refresh and shown again only while it is drawn, but its line keeps its
        -- own shown flag; the click area follows the row, so a folded Up next leaves no click area over what is drawn there now
        local row = self.upRows and self.upRows[i]
        local drawn = l:IsShown() and (not row or row:IsShown())
        if drawn and not prof and self.mode ~= "idle" and E.steps[idx] then
          h.panoplyIndex = idx
          if row then row.panoplyIndex = idx end
          if row and row.panoplyBundle then h:Hide() else h:Show() end   -- a bundle's row takes the right-click itself (UI:Create above)
        else
          h.panoplyIndex = nil h:Hide()
          if row then row.panoplyIndex = nil end
        end
      end
    end
    return r
  end
end

-- Guide page: right-click a step row of the route.
local Menu = Panoply.Menu
local def = Menu and Menu.defs and Menu.defs.Guide
if def and not def.panoplyReportHooked then
  def.panoplyReportHooked = true
  local build, refresh = def.build, def.refresh
  def.build = function(p, ...)
    build(p, ...)
    p.reportHits = {}
    for i, row in ipairs(p.routeCard and p.routeCard.rows or {}) do
      local h = rowHit(p)
      h:SetAllPoints(row.hl)
      p.reportHits[i] = h
    end
  end
  def.refresh = function(p, ...)
    refresh(p, ...)
    local E = Panoply.Engine
    -- 0.9.5 phase 4K: a route row says which guide step it is (a trainer step put in beside the guide is none)
    local rows = p.routeCard and p.routeCard.rows or {}
    for i, h in ipairs(p.reportHits or {}) do
      local row = rows[i]
      local idx = row and row.panoplyUsed and row.panoplyIndex
      if idx and E.steps[idx] then h.panoplyIndex = idx h:Show() else h.panoplyIndex = nil h:Hide() end
    end
  end
end

-- Help page: the command in the list (the Report a problem button is on the page itself).
-- 0.9.5 phase 4A4: registered with the other commands in Core/Slash.lua (key "report")

-- /panoply report [general]  (Core/Slash.lua loads after this file, so the command is added once
-- everything has loaded)
-- Nov 18 2026 (easier report access): /panoply idea opens the window already set to Feedback / idea
function RW.HookSlash()
  if Panoply.panoplyReportSlash or type(Panoply.Slash) ~= "function" then return end
  Panoply.panoplyReportSlash = true
  local slash = Panoply.Slash
  function Panoply:Slash(msg, ...)
    local cmd, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd and cmd:lower()
    if cmd == "report" then
      rest = rest:lower()
      RW:Open({ general = rest == "general" or rest == "problem", feedback = rest == "feedback" or rest == "idea" })
      return
    elseif cmd == "idea" then
      RW:Open({ feedback = true })
      return
    end
    return slash(self, msg, ...)
  end
end

-------------------------------------------------------------------------------
-- Nov 18 2026 (easier report access): a one-time tip the first time the guide window opens. It is a tip, not a control: the
-- game's chat gets the line, and the banner at the top of the screen (UI/Toast.lua) shows it for a few seconds. Nothing is added to
-- the guide window. Never in combat (it waits for the fight to end), never over setup or the tour (it waits for them to finish),
-- never while playing along (there is no guide window then).
-- New saved key (nothing renamed): PanoplySuiteDB.reportTipShown, true once the tip was on screen; it never shows again after that.
-------------------------------------------------------------------------------
RW.GUIDE_TIP_HEAD = "Tip"
RW.GUIDE_TIP = "Right-click the guide to report a problem or share an idea."
RW.GUIDE_TIP_DELAY = 2   -- seconds after the window opens: past the loading screen, and after the tour that follows setup has started

-- -> nil when the tip may show now, or why not
local function tipBlocked()
  local C = Panoply.Compat
  if (C and C.InCombat and C.InCombat()) or (_G.InCombatLockdown and InCombatLockdown()) then return "combat" end
  if Panoply.PlayAlong and Panoply:PlayAlong() then return "along" end
  local f = Panoply.UI and Panoply.UI.frame
  if not (f and f:IsShown()) then return "hidden" end
  local Wz = Panoply.Wizard
  if Wz and Wz.frame and Wz.frame:IsShown() then return "setup" end
  if Panoply.Tour and Panoply.Tour.active then return "tour" end
  return nil
end
RW.TipBlocked = tipBlocked

-- The guide window was opened (its OnShow, UI/MainFrame.lua): the tip is owed until it has been shown once.
function RW:GuideOpened()
  local db = Panoply.db
  if not db or db.reportTipShown then return end
  self.tipPending = true
  if self.tipTimer then return end
  self.tipTimer = true
  Panoply.Compat.After(RW.GUIDE_TIP_DELAY, function() RW.tipTimer = nil RW:ShowGuideTip() end)
end

-- -> true when the tip was shown now; false and why not
function RW:ShowGuideTip()
  local db = Panoply.db
  if not (db and self.tipPending) or db.reportTipShown then self.tipPending = nil return false, "done" end
  local why = tipBlocked()
  if why then
    -- the window closed again, or playing along: the next time the guide opens asks again. Combat, setup and the tour: it waits.
    if why == "hidden" or why == "along" then self.tipPending = nil end
    return false, why
  end
  self.tipPending = nil
  db.reportTipShown = true
  if Panoply.Toast and Panoply.Toast.Display then Panoply.Toast:Display(RW.GUIDE_TIP_HEAD, RW.GUIDE_TIP) self.tipToast = true end
  Panoply:Print(RW.GUIDE_TIP)
  return true
end

-- the tip waited for a fight, setup or the tour: asked again once it is over
local function again() if RW.tipPending then RW:GuideOpened() end end
Panoply:On("PLAYER_REGEN_ENABLED", again)
Panoply:Listen("SETUP_DONE", again)
Panoply:Listen("TOUR_DONE", again)
-- a fight starts while the tip's banner is up: it goes at once
Panoply:On("PLAYER_REGEN_DISABLED", function()
  local T = Panoply.Toast
  if RW.tipToast and T and T.frame and T.frame:IsShown() and T.body and T.body.GetText and T.body:GetText() == RW.GUIDE_TIP then T:Hide() end
  RW.tipToast = nil
end)
Panoply:On("ADDON_LOADED", function(_, name) if name == ADDON or name == "PanoplySuite" then RW.HookSlash() end end)
