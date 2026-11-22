-- Panoply Suite 0.8.4: copy a report out as text. The report window (UI/Report.lua) and the list of noted problems each
-- have a "Copy as text" button; it opens this small window with the very lines that would be sent, already selected,
-- so the player can press Ctrl+C (Cmd+C on a Mac) and paste them wherever they like: an e-mail, a chat, a note.
-- Nothing is sent from here and nothing is saved: an add-on cannot reach the clipboard or the network, so the copy is the
-- player's own key press. Typing in the box changes nothing: the text is put back and selected again.
local ADDON, Panoply = ...
local Skin = Panoply.Skin
local SP, TH = Skin.SP, Skin.TextHeight
local RC = {}
Panoply.ReportCopy = RC

RC.WIDTH, RC.VIEW = 540, 300
RC.TITLE = "Copy this report"
RC.INTRO = "The text below is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it wherever you like. Nothing is sent from here."
RC.EMPTY = "There is nothing to copy."

function RC:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteReportCopy", RC.WIDTH, 420, RC.TITLE, "Select, copy, paste", "DIALOG", "Flag")
  self.frame = f
  f.intro = Skin.Text(f, 12)
  f.intro:SetText(RC.INTRO)
  f.view = Skin.ScrollArea(f)
  -- the same size and face as the box, to measure how tall the text is
  f.measure = Skin.Text(f.view.content, 10, Skin.colors.inkSoft)
  f.measure.panoplyLayoutSkip = true
  f.measure:Hide()
  local eb = CreateFrame("EditBox", nil, f.view.content)
  eb.panoplyLayoutSkip = true   -- selectable text, not laid out by us
  if eb.SetMultiLine then eb:SetMultiLine(true) end
  if eb.SetAutoFocus then eb:SetAutoFocus(false) end
  if eb.SetFont then pcall(eb.SetFont, eb, Skin.BODY, 10, "") end
  if eb.SetTextColor then local c = Skin.colors.text eb:SetTextColor(c[1], c[2], c[3], 1) end
  eb:SetPoint("TOPLEFT", f.view.content, "TOPLEFT", 0, 0)
  eb:SetScript("OnEscapePressed", function() RC:Close() end)
  -- the text is for copying, not for changing: what is typed is undone
  eb:SetScript("OnTextChanged", function(self, user)
    if user and RC.text and self:GetText() ~= RC.text then self:SetText(RC.text) RC:Select() end
  end)
  f.edit = eb
  f.again = Skin.Button(f, "Select it again", 140, 28, function() RC:Select() end, "Select it again", "Selects the whole text again, ready for Ctrl+C.")
  f.close = Skin.Button(f, "Close", 100, 28, function() RC:Close() end, "Close", "Close this window.")
  f.buttons = { f.again, f.close }
  f.panoplyClose:SetScript("OnClick", function() RC:Close() end)
  return f
end

function RC:Select()
  local eb = self.frame and self.frame.edit
  if not eb then return end
  if eb.SetFocus then eb:SetFocus() end
  if eb.HighlightText then eb:HighlightText() end
end

function RC:Layout()
  local f = self.frame
  local pad = 20
  local w = math.max(RC.WIDTH - 80, f:GetWidth() or RC.WIDTH) - 2 * pad        -- the window's own width (it resizes)
  local y = -((f.panoplyHeaderBottom or 50) + SP.m)
  f.intro:ClearAllPoints(); f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y); f.intro:SetWidth(w)
  y = y - TH(f.intro, w) - SP.m
  local view = f.view
  local tw = w - 14
  f.measure:SetWidth(tw); f.measure:SetText(self.text or "")
  local h = math.max(20, TH(f.measure, tw) + 8)
  -- never taller than the screen has room for
  local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
  local viewH = math.max(80, math.min(RC.VIEW, screenH - 40 - (-y) - (28 + SP.m + pad)))
  view:ClearAllPoints(); view:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y); view:SetSize(w, viewH)
  view.content:SetWidth(view:ContentWidth(h))
  f.edit:SetWidth(tw); f.edit:SetHeight(h)
  view:SetContentHeight(h)
  if view.SetVerticalScroll then view:SetVerticalScroll(0) end
  view:UpdateBar()
  y = y - viewH - SP.m
  local bh = Skin.FlowButtons(f, f.buttons, pad, y, w, SP.m, 90)
  y = y - bh - pad
  f:SetHeight(-y)
end

-- lines: the text to copy, a line each (Core/Reports.lua R:Lines or R:ErrorLines). Returns the window.
-- opts (0.9.5 phase 4G, map favorites' Share): { title, subtitle, intro } for a copy of something other than a report
function RC:Open(lines, opts)
  local f = self:Create()
  opts = opts or {}
  if f.panoplyTitle and f.panoplyTitle.SetText then f.panoplyTitle:SetText(opts.title or RC.TITLE) end
  if f.panoplySubtitle and f.panoplySubtitle.SetText then f.panoplySubtitle:SetText(opts.subtitle or "Select, copy, paste") end
  f.intro:SetText(opts.intro or RC.INTRO)
  if Panoply.ReportWindow and Panoply.ReportWindow.Resizable then Panoply.ReportWindow:Resizable(f, "reportCopy", RC.WIDTH - 80, function() RC:Layout() end) end
  local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines or "")
  if text == "" then text = RC.EMPTY end
  self.text = text
  f.edit:SetText(text)
  self:Layout()
  -- opened from the list of problems or the report window: it closes with the one it came from
  -- (the frames this module's own owners hold, not a lookup of a global by name: a name can still point at an older frame of the same
  -- name that is still shown, and the copy window would then be tied to a window that never closes)
  local from
  local RWm = Panoply.ReportWindow
  for _, w in ipairs({ RWm and RWm.Problems and RWm.Problems.frame or false, RWm and RWm.frame or false }) do
    if not from and w and w.IsShown and w:IsShown() then from = w end
  end
  if from then Skin.Popups:Child(f, from) else f.panoplyDialogParent = nil end
  f:Show()
  self:Select()
  return f
end

function RC:Close()
  if self.frame then
    if self.frame.edit.ClearFocus then self.frame.edit:ClearFocus() end
    self.frame:Hide()
  end
end
