-- Auctions: Cancelling tab (0.7.3). Your own auctions, and which of them somebody undercut.
--   * "Refresh" asks the game for your auctions (one request per click).
--   * "Check next" searches the auction house for the NEXT unchecked auction's item (one search per
--     click) and marks every auction of that item: lowest, undercut (by how much), or alone.
--   * "Only undercut" shows just the undercut ones: the cancel-undercut list.
--   * "Cancel" cancels that ONE auction (one click, one cancel). There is no "cancel all".
-- Cancelling gives up the deposit, so the button says so in its tooltip.
local ADDON, Panoply = ...
local C, Skin = Panoply.Compat, Panoply.Skin
local P = Panoply.Prices
local Auc = Panoply.Auctions
local T = Auc.Trade
local Panel = Auc.Panel
local Cn = { onlyUndercut = false }
Auc.Cancelling = Cn
Cn.W = 612
local function say(text, bad) Panel:Say(text, bad) end
local function money(c) return T.MoneyText(math.floor(c + 0.5)) end
Cn.WHY = {
  stale = "The list changed since you refreshed it. Click Refresh my auctions first.", busy = "A request is still on its way.",
  refused = "That click could not send the request.", ["cannot cancel"] = "The game says this auction cannot be cancelled now.",
  ["all checked"] = "Every auction has been checked.", ["not available"] = "This client cannot list your auctions.",
}

function Cn.Status(row)
  if row.cancelled then return "Cancelled", "done" end
  local c = row.check
  if not c then return "Not checked", "dim" end
  if c.state == "undercut" then return ("Undercut by %s"):format(money(c.by)), "warn" end
  if c.state == "lowest" then return "Lowest price", "done" end
  if c.state == "alone" then return "Only one listed", "done" end
  return "Bid only", "dim"
end
-- the rows to show: all, or only the undercut ones
function Cn.Rows()
  local out = {}
  for _, r in ipairs(T.owned and T.owned.rows or {}) do
    if not Cn.onlyUndercut or (r.check and r.check.state == "undercut" and not r.cancelled) then out[#out + 1] = r end
  end
  return out
end
function Cn.Counts()
  local n, u, c = 0, 0, 0
  for _, r in ipairs(T.owned and T.owned.rows or {}) do
    if not r.cancelled then n = n + 1 if r.check then c = c + 1 end if r.check and r.check.state == "undercut" then u = u + 1 end end
  end
  return n, c, u
end

function Cn.Refresh()
  local ok, why = T.Click(function() return T:RefreshOwned() end)
  if ok then say("Asking the game for your auctions...") else say(Cn.WHY[why] or Auc.Shopping.WHY[why] or tostring(why), true) end
  Panel:Refresh()
end
function Cn.CheckNext()
  local ok, why = T.Click(function() return T:CheckNext() end)
  if ok then say("Searching for the next auction's item...") else say(Cn.WHY[why] or Auc.Shopping.WHY[why] or tostring(why), true) end
  Panel:Refresh()
end
function Cn.Cancel(row)
  local ok, why = T.Click(function() return T:Cancel(row) end)
  if ok then say(("Cancelled %d x %s."):format(row.count, row.name)) else say(Cn.WHY[why] or tostring(why), true) end
  Panel:Refresh()
end

local COLOR = { warn = "warn", done = "done", dim = "dim" }
local function build(body)
  local ui = {}
  Cn.ui = ui
  ui.refresh = Skin.Button(body, "Refresh my auctions", 150, 24, function() Cn.Refresh() end, "Refresh my auctions", "Asks the game for your active auctions (one request per click).")
  ui.refresh:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  ui.check = Skin.Button(body, "Check next", 100, 24, function() Cn.CheckNext() end, "Check the next auction",
    "Searches the auction house for the next unchecked auction's item and marks whether somebody undercut you. One search per click.")
  ui.check:SetPoint("LEFT", ui.refresh, "RIGHT", 6, 0)
  ui.only = Skin.Check(body, "Only undercut", { get = function() return Cn.onlyUndercut end, set = function(v) Cn.onlyUndercut = v and true or false end },
    function() Panel:Refresh() end, "Shows only the auctions somebody undercut: your cancel list.")
  ui.only:SetPoint("LEFT", ui.check, "RIGHT", 14, 0)
  ui.info = Panel.Note(body, Cn.W, 11)
  ui.info:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -32)
  if ui.info.SetWordWrap then ui.info:SetWordWrap(false) end
  ui.list = Panel.List(body, Cn.W, 244, 26, function(parent)
    local r = Panel.Row(parent)
    r.name = Panel.Cell(r, 6, 150)
    r.qty = Panel.Cell(r, 160, 30, "RIGHT")
    r.each = Panel.Cell(r, 194, 96, "RIGHT")
    r.state = Panel.Cell(r, 298, 196)
    r.cancel = Skin.Button(r, "Cancel", 64, 20, function(self) Cn.Cancel(self:GetParent().item) end, "Cancel this auction",
      "Cancels ONE auction. You lose its deposit.")   
    r.cancel:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    return r
  end)
  ui.list.sf:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -54)
end

local function refresh(body)
  local ui = Cn.ui
  if not ui then return end
  local busy = T:Busy()
  local rows = Cn.Rows()
  local n, checked, under = Cn.Counts()
  ui.only:Refresh()
  ui.refresh:SetEnabledLook(not busy)
  ui.check:SetEnabledLook(not busy and T:NextToCheck() ~= nil)
  if not T.owned then ui.info:SetText("Click Refresh my auctions to load them.")
  elseif n == 0 then ui.info:SetText("You have no active auctions.")
  else ui.info:SetText(("%d auctions, %d checked, %d undercut. Check next searches for one item per click."):format(n, checked, under)) end
  ui.list:Set(rows, function(r, it)
    Panel.Put(r.name, it.name)
    Panel.Put(r.qty, tostring(it.count))
    Panel.Put(r.each, it.unit and money(it.unit) or "bid only")
    local text, tone = Cn.Status(it)
    Panel.Put(r.state, text)
    local col = tone == "warn" and Skin.colors.warn or tone == "done" and Skin.colors.done or Skin.colors.dim
    r.state:SetTextColor(col[1], col[2], col[3], 1)
    r.cancel:SetEnabledLook(not it.cancelled and not busy)
  end)
end

Panel:AddTab("cancelling", "Cancelling", "Your auctions, and which ones were undercut.", build, refresh)
