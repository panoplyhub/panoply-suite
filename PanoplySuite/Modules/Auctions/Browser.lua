-- Auctions: the pop-out window (Step 2 item F "View Auction House"; 0.9.5 phase 4E, docs/specs/page-redesigns-v1.md 7.3).
-- The Auctions page's tabs, Prices · Upgrades · History, in a window of their own, for players who want them beside the game. It
-- draws the same view as the page (View.lua) and shares what is chosen in it. It opens from the page's pop-out button, from Hearth
-- Hall (the scan of the chosen character's realm and faction) and from /panoply.
-- VIEW ONLY, like the page: there is no Buy, Post or Cancel in it, it never asks the auction house for anything and calls nothing
-- protected. It works anywhere (not only at the auction house) and stays open when the auction house closes.
-- The lists are drawn by a small pool of rows (10,000 items are never 10,000 frames): the rows move with the scroll bar.
local ADDON, Panoply = ...
local C, Skin, Kit = Panoply.Compat, Panoply.Skin, Panoply.Kit
local P = Panoply.Prices
local Auc = Panoply.Auctions
local R = Auc.Record
local V = Auc.View
local B = {}
Auc.Browser = B
B.W, B.H, B.PAD = 820, 560, 18
B.MIN_W, B.MIN_H, B.GRIP = 460, 420, 10      -- the smallest the window is dragged to (Narrow fits); the grip's corner
-- the shared helpers, under their old names
B.LinkOf, B.ItemInfo, B.NewList, B.DateText = V.LinkOf, V.ItemInfo, V.NewList, V.DateText

function B.KindText(s)
  if s.kind == "paged" then
    if s.full then return "page by page" .. (s.of and (", all %d pages"):format(s.of) or "") end
    return ("page by page, %d of %d pages"):format(s.pages or 0, s.of or s.pages or 0)
  elseif s.kind == "browse" then return "browse, the lowest price of each item"
  end
  return s.full and "full scan" or "partial scan"
end
function B.PlaceText(key)
  local realm, faction = R.RealmOfSnapKey(key), R.FactionOfSnapKey(key)
  return faction ~= "" and ("%s (%s)"):format(realm, faction) or realm
end

function B:Build()
  if self.frame then return self.frame end
  local f = Skin.Window("PanoplySuiteAuctionBrowser", B.W, B.H, "Auctions", "", "HIGH", "Auctions")
  self.frame = f
  f:HookScript("OnHide", function() B:Release() end)
  local body = CreateFrame("Frame", nil, f)
  body.panoplyGapOK = true
  f.body = body
  self.view = V.New(body, { kind = "popout" })
  -- the window resizes in both directions and remembers its size; the view takes the room
  Skin.Resizable(f, { key = "auctionBrowser", minW = B.MIN_W, minH = B.MIN_H, onSize = function(w, h)
    B.W, B.H = w, h
    if f:IsShown() then B:Refresh() end
  end })
  return f
end

-- opts: { realm, faction } (the scan and the history of that realm + faction; nothing = the latest scan of this realm),
-- tab = "prices" | "upgrades" | "history" (the old "scan" is Prices)
function B:Open(opts)
  opts = opts or {}
  local key
  if opts.realm and opts.realm ~= "" then key = R.SnapKey(opts.realm, opts.faction) end
  if key ~= V.state.snapKey then V.state.cat, V.state.char, V.state.open = nil, nil, nil end
  V.state.snapKey = key
  if opts.tab then V.state.tab = (opts.tab == "scan") and "prices" or opts.tab end
  local f = self:Build()
  f:Show()
  self:Refresh()
  return f
end
function B:Toggle(opts)
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Open(opts) end
end
function B:SetTab(tab)
  V.state.tab = (tab == "scan") and "prices" or tab
  V:RefreshAll()
end
-- the window is shut: what was decoded for it goes (a large scan is a few MB of Lua tables), and the page goes back to this realm
function B:Release()
  if V.state.snapKey then V.state.snapKey, V.state.cat, V.state.char, V.state.open = nil, nil, nil, nil end
  if not V:Visible() then V:Forget() end
  local v = self.view
  if v then
    if v.prices and v.prices.list then v.prices.list.data, v.prices.list.total = nil, 0 end
    if v.history and v.history.list then v.history.list.data, v.history.list.total = nil, 0 end
  end
  local M = Panoply.Menu
  if M and M.frame and M.frame:IsShown() and M.current == "auctions" and M.RefreshCurrent then M:RefreshCurrent() end
end

function B:Refresh()
  local f = self.frame
  if not (f and f:IsShown() and self.view) then return end
  local key = V:Key()
  if f.panoplySubtitle then f.panoplySubtitle:SetText(B.PlaceText(key)) end
  local pad = B.PAD
  local top = (f.panoplyHeaderBottom or 52) + Skin.SP.m
  local w, h = B.W - 2 * pad, B.H - top - pad
  f.body:ClearAllPoints(); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
  f.body:SetSize(w, h)
  self.view:Render(w, h, Kit.Band(w))
end
