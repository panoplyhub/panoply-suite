-- Item quality marker module (SPEC 19.4): a crisp quality-coloured border plus a faint inner corner
-- glow on item buttons, so green / blue / purple / orange gear stands out and nothing else does. Used by Panoply Suite's bag and bank
-- windows and, optionally, on the game's own bags, bank, character sheet and vendor window.
-- Adds a "!" badge on quest items and a coin on junk.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Skin = Panoply.Skin
local Glow = Panoply.Modules:Register({
  key = "glow", label = "Item quality glow", icon = "Glow",
  desc = "A crisp quality-colour border on uncommon and better items only.",
  defaults = { glowStrength = "subtle", glowPoor = false, glowDefaultFrames = true, glowBadges = true },
})
Panoply.Glow = Glow

-- 0.5.2 look (after testing in the real Era client): only Uncommon, Rare, Epic, Legendary,
-- Artifact and Heirloom get a marker. Poor (unless asked), Common, empty slots and unknown /
-- not-yet-cached quality get nothing, and every texture is hidden explicitly on every update.
-- The marker is a crisp, solid border in the game's own quality colour, drawn as four solid
-- edges snapped to whole screen pixels. 0.6.0 (no glow anywhere): the faint inner-corner glow
-- is gone; the border is flat. No halo, no additive blending. Strength nudges thickness and brightness.
Glow.STRENGTH = {
  subtle = { px = 2, bright = 0.90 },
  normal = { px = 2, bright = 1.00 },
  strong = { px = 3, bright = 1.00 },
}
Glow.DEFAULT = "subtle"
Glow.MARKED = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true }
Glow.applied = 0

-- Quality as a usable integer, or nil (nil, -1, strings, unknown values from an uncached item).
function Glow.Q(q)
  q = tonumber(q)
  if not q or q < 0 or q ~= math.floor(q) then return nil end
  return q
end

function Glow:Wants(quality)
  local q = Glow.Q(quality)
  if not q then return false end
  if q == 0 then return Panoply.db and Panoply.db.glowPoor and true or false end
  return Glow.MARKED[q] or false
end

-- Border thickness in UI units for `px` screen pixels at 1080p, snapped to whole physical pixels.
function Glow.Thickness(btn, px)
  local ph = _G.GetPhysicalScreenSize and select(2, C.pc(GetPhysicalScreenSize))
  local scale = btn.GetEffectiveScale and C.pc(btn.GetEffectiveScale, btn) or 1
  if not ph or ph <= 0 or not scale or scale <= 0 then return px end
  local phys = math.max(px, math.floor(px * ph / 1080 + 0.5))
  return phys * 768 / ph / scale
end

local EDGES = { "top", "bottom", "left", "right" }
local CORNERS = { "tl", "tr", "bl", "br" }
local CORNER_TC = { { 0, 0.25, 0, 0.25 }, { 0.75, 1, 0, 0.25 }, { 0, 0.25, 0.75, 1 }, { 0.75, 1, 0.75, 1 } }
-- corner radius for a given border thickness: the ring atlases have stroke = 1/3 (SlotRing2) or
-- 1/2 (SlotRing3) of the radius, so the curve's stroke always equals the straight edge exactly.
function Glow.CornerFor(th, px)
  if (px or 2) >= 3 then return th * 2, Skin.TEX.SlotRing3 end
  return th * 3, Skin.TEX.SlotRing2
end

local function ensure(btn)
  if btn.panoplyGlow then return btn.panoplyGlow end
  local g = {}
  g.edges = {}
  for _, k in ipairs(EDGES) do
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Skin.WHITE)
    if t.SetBlendMode then t:SetBlendMode("BLEND") end
    t:Hide()
    g.edges[k] = t
  end
  g.border = g.edges.top   -- kept for callers that check "is the border shown"
  -- 0.5.3: rounded corners. Four quarter-ring pieces carry the curve; the straight runs between
  -- them are solid texels of the snapped thickness, so the border stays crisp and follows the
  -- rounded slot (slot radius ~6 units).
  g.rcorners = {}
  for i, k in ipairs(CORNERS) do
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Skin.TEX.SlotRing2)
    if t.SetTexCoord then local q = CORNER_TC[i] t:SetTexCoord(q[1], q[2], q[3], q[4]) end
    t:Hide()
    g.rcorners[k] = t
  end
  -- skin v3 (no glow anywhere): the soft inner glow is gone; the crisp quality border stays.
  -- g.corner is kept (never shown, no texture) for callers that look at it.
  g.corner = btn:CreateTexture(nil, "OVERLAY")
  g.corner:Hide()
  g.quest = btn:CreateTexture(nil, "OVERLAY")
  g.quest:Hide()
  g.junk = btn:CreateTexture(nil, "OVERLAY")
  g.junk:Hide()
  btn.panoplyGlow = g
  return g
end

-- Quest and junk marks. Panoply Suite style: our small ! and coin badges. WoW style: the game's own
-- bag marks - the quest "bang" over the whole slot for an item that starts a quest, the gold quest
-- border for other quest items, and the game's coin for junk. Shown only when the game's own API
-- said so (see Apply); never from our data.
function Glow.MarkStyle(g, btn, questStart)
  local wow = Skin.WoW()
  local key = (wow and "w" or "h") .. (questStart and "s" or "q")
  if g.markKey == key then return end
  g.markKey = key
  local q, j = g.quest, g.junk
  q:ClearAllPoints(); j:ClearAllPoints()
  local qr = wow and Skin.Resolve(Skin.GAME_MARKS, questStart and "QuestBang" or "QuestBorder")
  if qr then
    q:SetTexture(qr.path); if q.SetTexCoord then q:SetTexCoord(0, 1, 0, 1) end
    q:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1); q:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
  else
    q:SetTexture(Skin.TEX.BadgeQuest); q:SetSize(16, 16); q:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
  end
  q.panoplyGameIcon = qr and qr.path or nil
  local jr = wow and Skin.Resolve(Skin.GAME_MARKS, "Junk")
  if jr and jr.atlas and j.SetAtlas then j:SetAtlas(jr.atlas) else j:SetTexture(jr and jr.path or Skin.TEX.BadgeJunk) end
  j:SetSize(14, 14); j:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
  j.panoplyGameIcon = jr and (jr.path or jr.atlas) or nil
end

local function layout(g, btn, th, px)
  if g.th == th and g.px == px then return end
  g.th, g.px = th, px
  local R, ring = Glow.CornerFor(th, px)
  g.radius = R
  local e, c = g.edges, g.rcorners
  e.top:ClearAllPoints(); e.top:SetPoint("TOPLEFT", btn, "TOPLEFT", R, 0); e.top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -R, 0); e.top:SetHeight(th)
  e.bottom:ClearAllPoints(); e.bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", R, 0); e.bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -R, 0); e.bottom:SetHeight(th)
  e.left:ClearAllPoints(); e.left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -R); e.left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, R); e.left:SetWidth(th)
  e.right:ClearAllPoints(); e.right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -R); e.right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, R); e.right:SetWidth(th)
  local pts = { tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }
  for k, t in pairs(c) do t:ClearAllPoints(); t:SetTexture(ring); t:SetSize(R, R); t:SetPoint(pts[k], btn, pts[k], 0, 0) end
  g.corner:ClearAllPoints()
  g.corner:SetPoint("TOPLEFT", btn, "TOPLEFT", th, -th); g.corner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -th, th)
end

local function hideAll(g)
  for _, t in pairs(g.edges) do t:Hide() end
  for _, t in pairs(g.rcorners) do t:Hide() end
  g.corner:Hide()
end

-- quality: item quality (nil = empty slot / unknown). opts: { quest = bool, junk = bool, item = link or id }
-- 0.8.4: opts.item is handed to Class Gear's Upgrade Hints (Modules/ClassGear), which draws its own small arrow.
function Glow:Apply(btn, quality, opts)
  if not btn or not btn.CreateTexture then return end
  opts = opts or {}
  local g = ensure(btn)
  local q = Glow.Q(quality)
  local on = self.active and self:Wants(q) or false
  local st = Glow.STRENGTH[Panoply.db and Panoply.db.glowStrength or Glow.DEFAULT] or Glow.STRENGTH[Glow.DEFAULT]
  if on then
    local c = C.QualityColor(q)
    layout(g, btn, Glow.Thickness(btn, st.px), st.px)
    for _, t in pairs(g.edges) do t:SetVertexColor(c[1], c[2], c[3], st.bright); t:Show() end
    for _, t in pairs(g.rcorners) do t:SetVertexColor(c[1], c[2], c[3], st.bright); t:Show() end
    g.corner:Hide()
    Glow.applied = Glow.applied + 1
  else
    hideAll(g)
  end
  g.quality, g.on = q, on
  local badges = self.active and Panoply.db and Panoply.db.glowBadges
  Glow.MarkStyle(g, btn, opts.questStart)
  if badges and opts.quest then g.quest:Show() else g.quest:Hide() end
  if badges and opts.junk and not opts.quest then g.junk:Show() else g.junk:Hide() end
  g.isQuest, g.isJunk = badges and opts.quest or false, badges and opts.junk and not opts.quest or false
  local CG = Panoply.ClassGear
  if CG and CG.MarkButton then CG:MarkButton(btn, opts.item) end
end

function Glow:Clear(btn)
  if btn and btn.panoplyGlow then local g = btn.panoplyGlow hideAll(g) g.quest:Hide() g.junk:Hide() g.on = false end
  local CG = Panoply.ClassGear
  if btn and CG and CG.MarkButton then CG:MarkButton(btn, nil) end
end

-- Default game frames --------------------------------------------------------------------------
local function slotOf(btn)
  local bag = btn.GetBagID and C.pc(btn.GetBagID, btn)
  if bag == nil and btn.GetParent and btn:GetParent() and btn:GetParent().GetID then bag = btn:GetParent():GetID() end
  return bag, btn.GetID and btn:GetID()
end
Glow.SlotOf = slotOf

function Glow:ApplySlot(btn, bag, slot)
  local info = bag and slot and C.SlotInfo(bag, slot)
  if not info then self:Apply(btn, nil) return end
  local quest, _, start = C.SlotQuest(bag, slot)
  -- the game's own bag frames already draw the game's quest marks; only add ours in Panoply Suite style
  if Skin.WoW() then quest = false end
  local ii = C.ItemInfo(info.link or info.itemID)
  self:Apply(btn, info.quality or (ii and ii.quality), { quest = quest, questStart = start, junk = (info.quality == 0) and ii and (ii.sellPrice or 0) > 0,
    item = info.link or info.itemID })
end

function Glow:Defaults() return self.active and Panoply.db and Panoply.db.glowDefaultFrames end

local hooked = false
function Glow:HookDefaultFrames()
  if hooked then return end
  hooked = true
  local got = {}
  -- One shared helper both clients use to colour item button borders.
  if C.Hook("SetItemButtonQuality", function(btn, quality, link)
    if not Glow:Defaults() or not btn or btn.panoplyOwn then return end
    local ii = link and C.ItemInfo(link)
    Glow:Apply(btn, quality, { junk = quality == 0 and ii and (ii.sellPrice or 0) > 0, item = link })
  end) then got[#got + 1] = "SetItemButtonQuality" end
  -- Era bag frames.
  if C.Hook("ContainerFrame_Update", function(frame)
    if not Glow:Defaults() or not frame or not frame.GetName then return end
    local name, bag = frame:GetName(), frame:GetID()
    for i = 1, frame.size or 0 do
      local btn = _G[name .. "Item" .. i]
      if btn then Glow:ApplySlot(btn, bag, btn:GetID()) end
    end
  end) then got[#got + 1] = "ContainerFrame_Update" end
  if C.Hook("BankFrameItemButton_Update", function(btn)
    if not Glow:Defaults() or not btn then return end
    local bag, slot = slotOf(btn)
    if bag then Glow:ApplySlot(btn, bag, slot) end
  end) then got[#got + 1] = "BankFrameItemButton_Update" end
  if C.Hook("PaperDollItemSlotButton_Update", function(btn)
    if not Glow:Defaults() or not btn then return end
    local q = _G.GetInventoryItemQuality and C.pc(GetInventoryItemQuality, "player", btn:GetID())
    Glow:Apply(btn, q)
  end) then got[#got + 1] = "PaperDollItemSlotButton_Update" end
  if C.Hook("MerchantFrame_UpdateMerchantInfo", function()
    if not Glow:Defaults() then return end
    for i = 1, _G.MERCHANT_ITEMS_PER_PAGE or 10 do
      local btn = _G["MerchantItem" .. i .. "ItemButton"]
      local link = btn and _G.GetMerchantItemLink and C.pc(GetMerchantItemLink, btn:GetID())
      local ii = link and C.ItemInfo(link)
      if btn then Glow:Apply(btn, ii and ii.quality) end
    end
  end) then got[#got + 1] = "MerchantFrame_UpdateMerchantInfo" end
  self.hooks = got
end

-- 0.5.1 migration: Strong was the 0.5.0 default  found it too bright. A saved "strong"
-- (account-wide, or a per-character copy if one exists) becomes the new default once.
function Glow:Migrate()
  local db, cdb = Panoply.db, Panoply.cdb
  if db and not db.glowMigrated051 then
    if db.glowStrength == "strong" then db.glowStrength = Glow.DEFAULT end
    db.glowMigrated051 = true
  end
  if cdb and not cdb.glowMigrated051 then
    if cdb.glowStrength == "strong" then cdb.glowStrength = Glow.DEFAULT end
    cdb.glowMigrated051 = true
  end
end

function Glow:Enable()
  self:HookDefaultFrames()
  Panoply:Fire("GLOW_CHANGED")
end
function Glow:Disable() Panoply:Fire("GLOW_CHANGED") end

Glow.options = {
  { type = "choice", key = "glowStrength", label = "Glow strength", values = { { "subtle", "Subtle" }, { "normal", "Normal" }, { "strong", "Strong" } },
    tip = "Slightly changes how thick and bright the coloured border is. Subtle is the default." },
  { type = "check", key = "glowPoor", label = "Mark grey (poor) items too", tip = "Off by default. Common white items are never marked." },
  { type = "check", key = "glowDefaultFrames", label = "Also in the game's own windows", tip = "Also on the default bags, bank, character sheet and vendor window." },
  { type = "check", key = "glowBadges", label = "Quest '!' and junk coin badges", tip = "A small ! on quest items and a coin on items that only sell." },
}
for _, k in ipairs({ "glowStrength", "glowPoor", "glowBadges" }) do
  Panoply.optionHooks[k] = function() Panoply:Fire("GLOW_CHANGED") end
end
