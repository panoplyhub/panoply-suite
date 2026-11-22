-- Panoply Suite 0.5.7: "Drop unneeded quests?" - the confirmation after a Replan (SPEC 19.13).
-- A ticked list of the quests the new route doesn't use, each with the quest items that would be
-- destroyed beneath it. Nothing is dropped until Confirm; Keep all (or the close button) does nothing.
local ADDON, Panoply = ...
local Skin, C = Panoply.Skin, Panoply.Compat
local DD = { rows = {}, itemRows = {} }
Panoply.DropDialog = DD

DD.TITLE = "Drop unneeded quests?"
DD.TEXT = "These quests aren't in your new plan. They will be abandoned, and their quest items will be destroyed. Check the list before confirming."
DD.WIDTH, DD.MAX_H = 470, 560

local function dangerLook(b)
  b.panoplyDanger = true
  -- skin v3: a dark red fill with a warm line (Skin.BUTTON_STATE.danger_*), no glow
  if b.Paint then b:Paint("up") end
  b.label:SetTextColor(1, 0.86, 0.8, 1)
end

function DD:Create()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteDropQuests", DD.WIDTH, 420, DD.TITLE, "Replan clean-up", "DIALOG", "Accept")
  self.frame = f
  f.panoplyClose:SetScript("OnClick", function() DD:KeepAll() end)
  f.body = Skin.Text(f, 12)
  f.body:SetText(DD.TEXT)
  f.scroll = Skin.ScrollArea(f)
  f.list = f.scroll.content
  f.empty = Skin.Text(f, 12, Skin.colors.inkSoft)
  f.confirm = Skin.Button(f, "Confirm", 110, 28, function() DD:Confirm() end, "Drop the ticked quests",
    "Abandons every ticked quest and destroys the quest items listed under it. Untick a quest to keep it.")
  dangerLook(f.confirm)
  f.keep = Skin.Button(f, "Keep all", 100, 28, function() DD:KeepAll() end, "Keep all", "Close this and keep every quest and item.")
  f.buttons = { f.confirm, f.keep }
  f.note = Skin.Text(f, 11, Skin.colors.warn)
  return f
end

local function questRow(i)
  local r = DD.rows[i]
  if r then return r end
  local p = DD.frame.list
  r = {}
  r.icon = p:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18)
  r.check = Skin.Check(p, "", { get = function() return r.entry and not r.entry.keep end,
                                  set = function(v) if r.entry then r.entry.keep = not v end end },
    nil, "Ticked: this quest is dropped. Untick it to keep the quest and its items.")
  r.why = Skin.Text(p, 11, Skin.colors.inkSoft)
  DD.rows[i] = r
  return r
end

local function itemRow(i)
  local r = DD.itemRows[i]
  if r then return r end
  local p = DD.frame.list
  r = { icon = p:CreateTexture(nil, "ARTWORK"), text = Skin.Text(p, 11) }
  r.icon:SetSize(16, 16)
  DD.itemRows[i] = r
  return r
end

function DD:Fill(list)
  local f = self.frame
  self.list = list
  local n = 0
  for i, e in ipairs(list) do
    local r = questRow(i)
    r.entry = e
    Skin.SetIcon(r.icon, e.ready and "TurnIn" or "Accept")
    r.check.label:SetText(e.title)
    r.why:SetText(e.why)
    r.check:Refresh()
    r.icon:Show(); r.check:Show(); r.check.label:Show(); r.why:Show()
    r.items = {}
    for _, it in ipairs(e.items) do
      n = n + 1
      local ir = itemRow(n)
      -- the item picture is always the game's own icon; an item the game has not loaded yet is painted when it is sent (0.9.7 icons)
      if it.itemID then Panoply.Icons:Apply(ir.icon, it.link or it.itemID, it.icon)
      else Panoply.Icons:Release(ir.icon) ir.icon:SetTexture(it.icon or Skin.UNKNOWN_ITEM) end
      ir.text:SetText((it.count or 1) > 1 and ("%s x%d"):format(it.name, it.count) or it.name)
      ir.icon:Show(); ir.text:Show()
      r.items[#r.items + 1] = ir
    end
  end
  for i = #list + 1, #self.rows do local r = self.rows[i] r.entry = nil r.icon:Hide() r.check:Hide() r.check.label:Hide() r.why:Hide() end
  for i = n + 1, #self.itemRows do local r = self.itemRows[i] r.icon:Hide() r.text:Hide() end
  f.note:SetText("")
end

function DD:Layout()
  local f, SP, TH = self.frame, Skin.SP, Skin.TextHeight
  local W = f:GetWidth()
  local x, tw = 18, W - 36
  local y = -66
  f.body:ClearAllPoints(); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.body:SetWidth(tw)
  y = y - TH(f.body, tw) - SP.m
  -- list content (measured), inside the scroll area
  local function lay(cw)
    local ly = -SP.xs
    for _, r in ipairs(self.rows) do
      if r.entry then
        r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", f.list, "TOPLEFT", 2, ly)
        r.check:ClearAllPoints(); r.check:SetPoint("TOPLEFT", f.list, "TOPLEFT", 26, ly)
        local _, lh = r.check:FitLabel(cw - 26 - 27 - 4)
        ly = ly - math.max(18, lh) - 2
        local iw = cw - 53 - 4
        r.why:ClearAllPoints(); r.why:SetPoint("TOPLEFT", f.list, "TOPLEFT", 53, ly); r.why:SetWidth(iw)
        ly = ly - TH(r.why, iw) - SP.xs
        for _, ir in ipairs(r.items) do
          ir.icon:ClearAllPoints(); ir.icon:SetPoint("TOPLEFT", f.list, "TOPLEFT", 53, ly)
          local tx = 53 + 16 + SP.s
          ir.text:ClearAllPoints(); ir.text:SetPoint("TOPLEFT", f.list, "TOPLEFT", tx, ly); ir.text:SetWidth(cw - tx - 4)
          ly = ly - math.max(16, TH(ir.text, cw - tx - 4)) - 2
        end
        ly = ly - SP.m
      end
    end
    return -ly
  end
  local contentH = lay(tw)
  -- the buttons sit at the bottom; the list takes what is left up to MAX_H
  local bw = tw
  local bh = 0
  for _, b in ipairs(f.buttons) do Skin.FitButton(b, 90) bh = math.max(bh, b:GetHeight()) end
  local noteH = (f.note:GetText() or "") ~= "" and (TH(f.note, tw) + SP.s) or 0
  local fixed = -y + SP.m + noteH + bh + SP.l
  local viewH = math.max(80, math.min(contentH, DD.MAX_H - fixed))
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  f.scroll:SetSize(tw, viewH)
  if contentH > viewH + 0.5 then contentH = lay(tw - 12) end
  f.list:SetWidth(f.scroll:ContentWidth(contentH))
  f.scroll:SetContentHeight(contentH)
  y = y - viewH - SP.m
  if noteH > 0 then
    f.note:ClearAllPoints(); f.note:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); f.note:SetWidth(tw)
    y = y - noteH
  end
  Skin.FlowButtons(f, f.buttons, x, y, bw, SP.m, 90)
  y = y - bh - SP.l
  f:SetHeight(-y)
end

function DD:Open(list)
  local f = self:Create()
  -- Nov 2026: a resize grip. The box is as tall as its list (its layout sets the height), so the grip changes the width.
  if not f.panoplyResize then
    Skin.Resizable(f, { key = "dropQuests", minW = DD.WIDTH - 60, minH = 120, onSize = function(_, _, done) if done and f:IsShown() then DD:Layout() end end })
  end
  self:Fill(list)
  self:Layout()
  f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:Show()
  return f
end

function DD:KeepAll()
  self.list = nil
  if self.frame then self.frame:Hide() end
  Panoply:Fire("QUESTS_KEPT")
end

-- Everything happens inside this click: out of combat, one quest at a time.
function DD:Confirm()
  if not self.list then return end
  if C.InCombat() then
    self.frame.note:SetText("You are in combat. Confirm again when the fight is over.")
    self:Layout()
    Panoply:Print("You are in combat. Nothing was dropped; confirm again after the fight.")
    return nil, "combat"
  end
  local list = self.list
  self.list = nil
  self.frame:Hide()
  return Panoply.DropQuests:Drop(list)
end
