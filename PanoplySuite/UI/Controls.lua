-- Panoply Suite one-window menu: the small controls it needs on top of Skin.lua.
--   Skin.Switch    an On / Off pill with the state in words (colour is never the only cue)
--   Skin.Segmented every choice of a setting drawn as joined buttons (the chosen one is lit)
--   Skin.Grip      the six-dot drag handle of a page row in Edit pages
-- Skin v3 only: flat fills, hairlines, no glow.
local ADDON, Panoply = ...
local Skin = Panoply.Skin

-- A pill (46 x 22) and, to its right, the state in words. b:SetState(on, word) sets both; the button
-- is as wide as pill + word, so the word is part of the click target. onClick(b) flips the state.
function Skin.Switch(parent, onClick, tip, tipBody)
  local b = CreateFrame("Button", nil, parent)
  b.panoplyBox = true
  b:SetSize(46, 24)
  local track = b:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", b, "LEFT", 0, 0); track:SetSize(46, 22)
  Skin.Round(track, 11, Skin.TEX.RFill)
  local knob = b:CreateTexture(nil, "ARTWORK")
  knob:SetTexture(Skin.TEX.CircleMask); knob:SetSize(16, 16)
  local word = Skin.Name(b, 12, Skin.colors.text)
  word:SetPoint("LEFT", b, "LEFT", 54, 0)
  if word.SetWordWrap then word:SetWordWrap(false) end
  b.track, b.knob, b.word = track, knob, word
  Skin.Tooltip(b, tip or "Switch", tipBody)
  function b:Paint()
    local on = self.panoplyOn
    local c = on and Skin.colors.accentDark or Skin.colors.slotLine
    track:SetVertexColor(c[1], c[2], c[3], 1)
    local k = on and Skin.colors.goldBright or Skin.colors.inkSoft
    knob:SetVertexColor(k[1], k[2], k[3], 1)
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", b, "LEFT", on and 27 or 3, 0)
    local wc = on and Skin.colors.text or Skin.colors.inkSoft
    word:SetTextColor(wc[1], wc[2], wc[3], 1)
  end
  -- word: "On" / "Off" or a longer status
  function b:SetState(on, text, maxW)
    self.panoplyOn = on and true or false
    word:SetText(text or (on and "On" or "Off"))
    local ww = math.ceil(Skin.TextWidth(word)) + 2
    if maxW and ww > maxW - 54 then ww = math.max(20, maxW - 54) end
    word:SetWidth(ww)
    self:SetWidth(54 + ww)
    self:Paint()
  end
  function b:NeedWidth() return 54 + math.ceil(Skin.TextWidth(word)) + 2 end
  b:SetScript("OnEnter", function() if b.panoplyShowTip then b.panoplyShowTip() end end)
  b:SetScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(self) if onClick and not self.disabled then onClick(self) end end)
  b:SetState(false)
  Skin.buttons[#Skin.buttons + 1] = b
  return b
end

-- Every choice shown. opts = { values = { { value, name }... }, get = fn, set = fn(value), label, tip }.
-- Returns a frame with :Layout(maxW) -> height, :Refresh() and .buttons.
function Skin.Segmented(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.opts = opts
  f.label = opts.label and Skin.Text(f, 12, Skin.colors.text) or nil
  if f.label then f.label:SetText(opts.label) end
  f.buttons = {}
  for _, v in ipairs(opts.values) do
    local b = Skin.Button(f, v[2], 80, 26, function()
      opts.set(v[1])
      f:Refresh()
    end, opts.label or v[2], opts.tip)
    b.value = v[1]
    f.buttons[#f.buttons + 1] = b
  end
  function f:Refresh()
    local cur = opts.get()
    for _, b in ipairs(self.buttons) do
      b:SetSelected(b.value == cur)
      local c = b.value == cur and Skin.colors.heading or Skin.colors.text
      b.label:SetTextColor(c[1], c[2], c[3], 1)
    end
  end
  -- one label line above, the buttons wrapped under it; returns the height used
  function f:Layout(maxW)
    local y = 0
    if self.label then
      self.label:ClearAllPoints(); self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0); self.label:SetWidth(maxW)
      y = Skin.TextHeight(self.label, maxW) + Skin.SP.xs
    end
    local bh = Skin.FlowButtons(self, self.buttons, 0, -y, maxW, Skin.SP.xs, 70)
    self:SetSize(maxW, y + bh)
    return y + bh
  end
  f:Refresh()
  return f
end

-- Six dots in two columns: the handle of a page row in Edit pages.
function Skin.Grip(parent)
  local g = CreateFrame("Frame", nil, parent)
  g:SetSize(10, 16)
  g.dots = {}
  local c = Skin.colors.iconIdle
  for i = 0, 2 do
    for j = 0, 1 do
      local t = g:CreateTexture(nil, "ARTWORK")
      Skin.Solid(t, c, 0.9)
      t:SetSize(3, 3)
      t:SetPoint("TOPLEFT", g, "TOPLEFT", j * 6, -(i * 6))
      g.dots[#g.dots + 1] = t
    end
  end
  g.panoplyLayoutSkip = true
  return g
end
