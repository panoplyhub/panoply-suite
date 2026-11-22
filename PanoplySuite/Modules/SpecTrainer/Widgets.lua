-- Spec & Trainer: small measured layout helpers shared by its panels (skin v3, no glow).
-- Every helper places text at (x, y) from a parent's top-left and returns the y below it, so the
-- panels can be measured before they are shown (the 1.3x layout checker reads the same numbers).
local ADDON, Panoply = ...
local ST = Panoply.SpecTrainer
local Skin = Panoply.Skin
local U = {}
ST.UI = U

function U.Text(parent, size, color, role) return Skin.Text(parent, size, color or Skin.colors.ink, nil, role) end

-- A wrapped text block. Returns the y below it and the font string.
function U.Block(parent, x, y, w, size, color, s, role)
  local fs = U.Text(parent, size, color, role)
  fs:SetWidth(w); fs:SetText(s or ""); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = Skin.TextHeight(fs, w); fs:SetHeight(h)
  return y - h, fs
end

-- Label on the left, value on the right. Returns the y below.
function U.Pair(parent, x, y, w, left, right, lc, rc, size)
  local r = U.Text(parent, size or 12, rc or Skin.colors.goldBright, "semi")
  r:SetText(right); r:SetJustifyH("RIGHT")
  local rw = math.ceil(Skin.TextWidth(r)) + 4
  r:SetWidth(rw); r:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y)
  local l = U.Text(parent, size or 12, lc or Skin.colors.inkSoft)
  local lw = w - rw - 10
  l:SetWidth(lw); l:SetText(left); l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local h = math.max(Skin.TextHeight(l, lw), Skin.TextHeight(r)); l:SetHeight(h); r:SetHeight(h)
  return y - h - Skin.SP.xs, l, r
end

function U.Rule(parent, x, y, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8X8"); local c = Skin.colors.trim
  t:SetVertexColor(c[1], c[2], c[3], 0.45); t:SetHeight(1); t:SetWidth(w)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return t
end

-- Crest, title and one sub line. Returns the y below.
function U.Header(f, x, y, w, title, sub)
  local crest = f:CreateTexture(nil, "ARTWORK"); crest:SetSize(30, 30); Skin.Logo(crest)
  crest:SetPoint("TOPLEFT", f, "TOPLEFT", x, y + 1)
  local h = Skin.Heading(f, 16, title); local hw = w - 40
  h:SetWidth(hw); h:SetPoint("TOPLEFT", f, "TOPLEFT", x + 40, y)
  local hh = Skin.TextHeight(h, hw); h:SetHeight(hh)
  local sy = U.Block(f, x + 40, y - hh - 2, hw, 11, Skin.colors.inkSoft, sub)
  return math.min(sy, y - 32) - Skin.SP.m
end

-- A small box that says what the plan means for a spell (Step 2 C-03): "buy" is ticked (the plan says to buy it), "learned" is ticked
-- in green, "later" and "opt" are empty, "skip" has a dash. Returns the frame; it is TICK wide and tall.
U.TICK = 18
function U.Tick(parent, x, y, state)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(U.TICK, U.TICK)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local line = state == "buy" and Skin.colors.accent or state == "learned" and Skin.colors.done or Skin.colors.slotLine
  Skin.Box(t, "S", { fill = Skin.colors.slotBottom, fillA = 1, line = line })
  if state == "buy" or state == "learned" then
    local mark = t:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", t, "TOPLEFT", -2, 3); mark:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, -2)
    Skin.SetMark(mark, "Check")   -- the game's own check mark, as on the settings' check boxes; the box's line says which (accent / green)
    t.mark = mark
  elseif state == "skip" then
    local d = t:CreateTexture(nil, "ARTWORK")
    d:SetSize(8, 2); d:SetPoint("CENTER", t, "CENTER", 0, 0)
    Skin.Solid(d, Skin.colors.dim, 1)
    t.dash = d
  end
  t.state, t.panoplyTick = state, true
  return t
end

-- One row: icon, name + rank (and tag), the cost, the button, and a reason line.
-- r = { name, rank, cost, icon, reason, tag }. opts: spendable, dim, compact, button, onClick, tip,
-- tick ("buy" | "learned" | "later" | "opt": a tick box before the icon), learned (the row says "Learned" where the cost and the button
-- were), noButton (a price only: a spell for a later visit), noReason (one line: no reason line under the name).
function U.ServiceRow(f, x, y, w, r, opts)
  opts = opts or {}
  local dim, compact = opts.dim, opts.compact
  local IC = compact and 20 or 28
  if opts.tick then
    U.Tick(f, x, y - math.floor((IC - U.TICK) / 2) - 1, opts.tick)
    x, w = x + U.TICK + Skin.SP.s, w - U.TICK - Skin.SP.s
  end
  local ic = f:CreateTexture(nil, "ARTWORK"); ic:SetSize(IC, IC)
  if r[4] then ic:SetTexture(r[4]) else Skin.SetIcon(ic, "Train") end
  ic:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 1)
  local b, bw = nil, 0
  if not opts.learned and not opts.noButton then
    b = Skin.Button(f, opts.button or "Learn", 64, 22, opts.onClick, opts.tip or ("Learn " .. r[1]),
      opts.tipBody or "One click learns this one spell. Panoply Suite never buys anything by itself.")
    Skin.FitButton(b, 64)
    bw = b:GetWidth()
    b:SetPoint("TOPRIGHT", f, "TOPLEFT", x + w, y)
  end
  local afford = (opts.spendable or 0) >= (r[3] or 0)
  if b then b:SetEnabledLook(afford and not opts.disabled) end
  local ccolor
  if opts.learned then ccolor = Skin.colors.done
  elseif opts.noButton then ccolor = Skin.colors.inkSoft
  else ccolor = afford and Skin.colors.goldBright or Skin.colors.warn end
  local cost = U.Text(f, 12, ccolor, "semi")
  cost:SetText(opts.learned and "Learned" or ST.Money(r[3])); cost:SetJustifyH("RIGHT")
  local cw = math.ceil(Skin.TextWidth(cost)) + 4
  cost:SetWidth(cw); cost:SetPoint("TOPRIGHT", f, "TOPLEFT", x + w - bw - (bw > 0 and Skin.SP.m or 0), y - 2)
  local tx = x + IC + Skin.SP.m
  local tw = w - (tx - x) - bw - cw - (bw > 0 and 2 or 1) * Skin.SP.m
  local rank = r[2] ~= "" and r[2] or nil
  local soft = compact and r[6] and ((rank and (rank .. ", ") or "") .. r[6]) or rank
  local nm = Skin.Name(f, 12, dim and Skin.colors.inkSoft or Skin.colors.text)
  nm:SetWidth(tw); nm:SetText(r[1] .. (soft and ("  " .. Skin.Code(Skin.colors.inkSoft) .. soft .. "|r") or ""))
  nm:SetPoint("TOPLEFT", f, "TOPLEFT", tx, y - 1)
  local nh = Skin.TextHeight(nm, tw); nm:SetHeight(nh)
  local yy = math.min(y - 1 - nh, y - 24)
  if r[5] and not compact and not opts.noReason then yy = U.Block(f, tx, yy - 1, w - (tx - x), 11, Skin.colors.inkSoft, r[5]) end
  if dim then ic:SetAlpha(0.55) end
  return math.min(yy, y - IC - 2) - Skin.SP.s, b
end

-- A skipped spell: one dim line, "Fireball Rank 3: Frostbolt does it". No price, no button (the game's own trainer window still lists it).
function U.SkipRow(f, x, y, w, r)
  local rank = r[2] ~= "" and (" " .. r[2]) or ""
  local why = r[5] and r[5] ~= "" and (": " .. r[5]) or ""
  local _, fs = U.Block(f, x, y, w, 11, Skin.colors.inkSoft, r[1] .. rank .. why)
  local h = Skin.TextHeight(fs, w)
  return y - h - Skin.SP.xs, fs
end

-- n = nil: the heading alone (no count and cost on the right)
function U.GroupHead(f, x, y, w, title, n, cost, color, noun)
  noun = noun or "spell"
  local c, cw = nil, 0
  if n then
    c = U.Text(f, 11, Skin.colors.inkSoft, "semi")
    c:SetText(n .. " " .. noun .. (n == 1 and "" or "s") .. ", " .. ST.Money(cost)); c:SetJustifyH("RIGHT")
    cw = math.ceil(Skin.TextWidth(c)) + 4
    c:SetWidth(cw); c:SetPoint("TOPRIGHT", f, "TOPLEFT", x + w, y - 2)
  end
  local h = Skin.Heading(f, 13, title)
  if color then h:SetTextColor(color[1], color[2], color[3], 1) end
  local hw = w - cw - (c and 10 or 0)
  h:SetWidth(hw); h:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  local hh = math.max(Skin.TextHeight(h, hw), c and Skin.TextHeight(c) or 0); h:SetHeight(hh)
  y = y - hh - 3
  U.Rule(f, x, y, w)
  return y - Skin.SP.s
end

-- Fresh child frame for content that is rebuilt (the old one is hidden and dropped).
function U.Fresh(holder, key, parent)
  if holder[key] then holder[key]:Hide() end
  local c = CreateFrame("Frame", nil, parent)
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  c:SetSize(parent:GetWidth(), parent:GetHeight())
  holder[key] = c
  return c
end

-- A panel with a fixed top, a scrolling list and a footer pinned to the bottom, at most maxH tall.
-- top(f, x, w, y), list(c, x, w, y), foot(ft, x, w, y) each build and return the y below.
-- The frame is reused; its contents are rebuilt on every call.
function U.ListPanel(f, width, maxH, top, list, foot)
  f:SetSize(width, maxH)
  local x, w = 16, width - 32
  local body = U.Fresh(f, "panoplyBody", f)
  local y = top(body, x, w, -14)
  local ft = CreateFrame("Frame", nil, body)
  ft:SetSize(w, 100)
  local fh = -foot(ft, 0, w, 0)
  ft:SetHeight(math.max(1, fh))
  if not f.area then f.area = Skin.ScrollArea(f) end
  local area = f.area
  local c = U.Fresh(f, "panoplyList", area.content)
  area.content:SetWidth(w); c:SetWidth(w)
  local ch = -list(c, 0, w - 12, 0)
  c:SetHeight(math.max(1, ch))
  local viewMax = maxH + y - Skin.SP.s - fh - Skin.SP.l - Skin.SP.s
  local view = math.max(20, math.min(ch, viewMax))
  local H = -y + view + Skin.SP.s + fh + Skin.SP.l + Skin.SP.s
  f:SetHeight(H)
  area:ClearAllPoints(); area:SetPoint("TOPLEFT", f, "TOPLEFT", x, y); area:SetSize(w, view)
  area:SetContentHeight(ch); area:SetVerticalScroll(0)
  if area.UpdateBar then area:UpdateBar() end
  ft:ClearAllPoints(); ft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, Skin.SP.l)
  f.foot = ft
  return f
end

-- Our own message card with buttons (Panoply.Toast has none). Returns the frame; buttons = { {label, tip, fn}, ... }
function U.Toast(f, head, body, buttons, width)
  width = width or 460
  f:SetSize(width, 110)
  local c = U.Fresh(f, "panoplyBody", f)
  local crest = c:CreateTexture(nil, "ARTWORK"); crest:SetSize(52, 52); Skin.Logo(crest)
  crest:SetPoint("TOPLEFT", c, "TOPLEFT", 20, -22)
  local x = 92
  local w = width - x - 20
  local hd = Skin.Heading(c, 16, head); hd:SetWidth(w); hd:SetPoint("TOPLEFT", c, "TOPLEFT", x, -22)
  local hh = Skin.TextHeight(hd, w); hd:SetHeight(hh)
  local y = U.Block(c, x, -22 - hh - 4, w, 12, Skin.colors.ink, body)
  y = y - Skin.SP.m
  local list = {}
  for _, b in ipairs(buttons) do list[#list + 1] = Skin.Button(c, b[1], 90, 26, b[3], b[1], b[2]) end
  f.buttons = list
  local bh = Skin.FlowButtons(c, list, x, y, w, Skin.SP.s, 80)
  y = y - bh
  f:SetHeight(math.max(110, -y + 18))
  return f
end
