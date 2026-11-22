-- Upgrade Hints (the module "classgear"), part 1. A small green arrow in the corner of an item button (bags, bank, quest
-- reward choices) and one line in the item's tooltip, when the item beats what the character wears for its
-- plan. Skin v3: a flat arrow on a dark plate, no glow, nothing animated.
--
-- 0.9.5: nothing is scored here any more. Whether an item is an upgrade, and by how much, is the gear engine's answer
-- (Panoply.Gear:Score, Modules/Gear); this file only draws it. The weight tables and the class rules that used to sit beside
-- this file are data now (Data/GearWeights.lua, Data/GearRules.lua).
--
-- It only draws. It never picks a reward, equips, uses or moves an item. The arrow is our own texture on the
-- button (as the quality border of Modules/Glow is); nothing is written into the game's frames and nothing here
-- runs in the secure click path. Bag and bank buttons are reached through Modules/Glow (Glow:Apply hands the
-- button and its item over), so they follow the same redraws; quest rewards are read on the quest events.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Skin = Panoply.Skin

local CG = Panoply.Modules:Register({
  key = "classgear", label = "Upgrade Hints", icon = "Character",
  desc = "A small green arrow on gear in your bags and on quest rewards that beats what you wear, for your talents.",
  defaults = { gearHints = true, gearHintTips = true },
  options = {
    { type = "check", key = "gearHints", label = "Mark upgrades in my bags and on quest rewards",
      tip = "A small green arrow on gear that is better than what you wear, weighed for your talents." },
    { type = "check", key = "gearHintTips", label = "Say so in item tooltips",
      tip = "One line in an item's tooltip: how much better it is than what you wear, or that it is not an upgrade." },
  },
})
Panoply.ClassGear = CG

CG.MARK = 13                 -- the plate, in UI units
CG.MARK_INSET = 1            -- from the button's top-right corner
CG.MAX_REWARDS = 10          -- reward choice buttons looked at

-- button -> its arrow pieces. Weak keys: a button the game drops takes its pieces along.
CG.marks = setmetatable({}, { __mode = "k" })

local function solid(tex, c, a)
  tex:SetTexture(Skin.WHITE)
  tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

-- The arrow: a dark plate, a three-step head and a stem, all flat rectangles (crisp at any scale).
local function build(btn)
  local m = CG.marks[btn]
  if m then return m end
  if not (btn and btn.CreateTexture) then return nil end
  m = { parts = {} }
  local plate = btn:CreateTexture(nil, "OVERLAY", nil, 6)
  solid(plate, Skin.colors.trailInk, 0.85)
  plate:SetSize(CG.MARK, CG.MARK)
  plate:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -CG.MARK_INSET, -CG.MARK_INSET)
  m.plate = plate
  m.parts[1] = plate
  -- { width, height, distance of its top edge from the plate's top }
  for _, r in ipairs({ { 1, 1, 2 }, { 3, 1, 3 }, { 5, 1, 4 }, { 7, 1, 5 }, { 9, 1, 6 }, { 3, 4, 7 } }) do
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    solid(t, Skin.colors.done, 1)
    t:SetSize(r[1], r[2])
    t:SetPoint("TOP", plate, "TOP", 0, -r[3])
    m.parts[#m.parts + 1] = t
  end
  for _, t in ipairs(m.parts) do t:Hide() end
  CG.marks[btn] = m
  return m
end

local function setShown(m, on)
  if not m then return end
  for _, t in ipairs(m.parts) do if on then t:Show() else t:Hide() end end
  m.shown = on and true or false
end

function CG:HintsOn() return self.active and Panoply.db and Panoply.db.gearHints ~= false end

-- Show or hide the arrow on one item button. item: a link or an item id; nil hides it.
-- Returns true when the arrow is shown.
function CG:MarkButton(btn, item)
  if not btn then return false end
  local on = false
  if item ~= nil and self:HintsOn() then
    -- an upgrade the character can wear now (one held back for its level or for weapon training gets no arrow)
    local v = Panoply.Gear:Score(item)
    on = (v and v.upgrade and not v.locked and not v.pending) and true or false
  end
  if not on and not CG.marks[btn] then return false end
  local m = build(btn)
  setShown(m, on)
  if m then m.item = on and item or nil end
  return on
end

function CG:IsMarked(btn) local m = CG.marks[btn] return m and m.shown or false end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------
-- The line for an item's tooltip, or nil: text, r, g, b. The words are the engine's, the same on every page:
-- "+14 for Beast Mastery leveling", "+14 for Beast Mastery leveling (At level 17)", "Not an upgrade".
function CG:TipLine(item)
  if not (self.active and Panoply.db and Panoply.db.gearHintTips ~= false) then return nil end
  local text, kind = Panoply.Gear:TipLine(item)
  if not text then return nil end
  local c = kind == "upgrade" and Skin.colors.done or Skin.colors.inkSoft
  return text, c[1], c[2], c[3]
end

function CG:OnItemTooltip(tt, id)
  if not (tt and tt.AddLine) then return end
  -- the link, when the tooltip can give it (a random suffix's stats ride on the link)
  local link
  if tt.GetItem then local ok, _, l = pcall(tt.GetItem, tt) if ok then link = C.Readable(l) end end
  local text, r, g, b = self:TipLine(type(link) == "string" and link or id)
  if not text then return end
  tt:AddLine(text, r, g, b)
  if tt.Show then tt:Show() end   -- the game resizes a tooltip when it is shown
end

function CG:HookTooltips()
  if self.tipHook then return end
  self.tipHook = C.HookItemTooltip(function(tt, id) if CG.active then CG:OnItemTooltip(tt, id) end end) or false
end

-------------------------------------------------------------------------------
-- Quest rewards (the "choose your reward" buttons)
-------------------------------------------------------------------------------
-- The game's button for reward choice i, on either client's quest window; nil when there is none.
function CG.RewardButton(i)
  local qi = _G.QuestInfoFrame
  local rf = qi and qi.rewardsFrame
  if rf and type(_G.QuestInfo_GetRewardButton) == "function" then
    local ok, b = pcall(_G.QuestInfo_GetRewardButton, rf, i)
    if ok and type(b) == "table" and b.CreateTexture then return b end
  end
  for _, name in ipairs({ "QuestInfoRewardsFrameQuestInfoItem", "QuestInfoItem", "QuestRewardItem" }) do
    local b = _G[name .. i]
    if type(b) == "table" and b.CreateTexture then return b end
  end
  return nil
end

function CG:MarkRewards()
  local link = _G.GetQuestItemLink
  local n = tonumber(C.NumQuestChoices()) or 0
  local marked = 0
  for i = 1, CG.MAX_REWARDS do
    local b = CG.RewardButton(i)
    if b then
      local l
      if i <= n and type(link) == "function" then
        local ok, v = pcall(link, "choice", i)
        l = ok and C.Readable(v) or nil
      end
      if self:MarkButton(b, type(l) == "string" and l or nil) then marked = marked + 1 end
    end
  end
  self.rewardsMarked = marked
  return marked
end

function CG:ClearRewards()
  for i = 1, CG.MAX_REWARDS do
    local b = CG.RewardButton(i)
    if b and CG.marks[b] then setShown(CG.marks[b], false) end
  end
  self.rewardsMarked = 0
end

CG:On("QUEST_COMPLETE", function() CG:MarkRewards() end)
CG:On("QUEST_FINISHED", function() CG:ClearRewards() end)

-------------------------------------------------------------------------------
-- Redraws and settings
-------------------------------------------------------------------------------
-- gear, level or the plan changed: the bag windows redraw their buttons (Modules/Bags listens to GLOW_CHANGED)
function CG:Redraw()
  -- arrows already up are judged again here (quest reward buttons are not part of that redraw)
  for btn, m in pairs(CG.marks) do
    if m.shown then CG:MarkButton(btn, m.item) end
  end
  if not CG.redrawing then
    CG.redrawing = true
    Panoply:Fire("GLOW_CHANGED")
    CG.redrawing = false
  end
end
-- the engine says something changed for the character being played (not the progress of a long list)
Panoply:Listen("GEAR_CHANGED", function(ctxKey, what)
  if CG.active and what ~= "progress" and (ctxKey == nil or ctxKey == "player") then CG:Redraw() end
end)
Panoply.optionHooks.gearHints = function() CG:Redraw() end

function CG:Enable()
  self:HookTooltips()
  self:Redraw()
end
function CG:Disable() self:Redraw() end

-------------------------------------------------------------------------------
-- Settings: a small section beside the item quality borders, and a profile holds both switches.
-------------------------------------------------------------------------------
local Cat = Panoply.Catalog
if Cat and Cat.hall and Cat.hall.sections then
  local have, at = false, #Cat.hall.sections + 1
  for i, s in ipairs(Cat.hall.sections) do
    if s.key == "gearhints" then have = true end
    if s.key == "borders" then at = i + 1 end
  end
  if not have then
    table.insert(Cat.hall.sections, at, { key = "gearhints", title = "Upgrade Hints", module = "classgear",
      rows = { { "gearHints", "Mark upgrades in my bags and on quest rewards" }, { "gearHintTips", "Say so in item tooltips" } } })
    Cat.reg = nil
  end
end
if Panoply.Profiles and Panoply.Profiles.AddKeys then Panoply.Profiles:AddKeys({ "gearHints", "gearHintTips" }) end
