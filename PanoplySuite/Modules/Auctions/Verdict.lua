-- Auctions: the verdict rule of the Sell tab (0.7.4, SPEC 19.9a, docs/auctions/AUCTIONS-REDESIGN-SPEC.md section 3).
-- Pure functions: no frames, no game calls, no requests. The sell list, the item card and "Post all worthwhile" all ask
-- Verdict.Compute with the same numbers, so a row and its card can never disagree.
--   price   copper each the item would be posted at (nil = unknown: "Scan first")
--   stack   items in one auction
--   vendor  copper each a vendor pays (0 when the item cannot be vendored)
--   cost    copper each of what posting gives up: the cost to make (crafted) or the vendor price (anything else)
--   cut     the auction house's share of a sale (0.05, or 0.15 at the neutral houses)
--   worth   the profit per post that is worth posting (setting "Worth posting from", default 5 silver)
-- First line that is true wins: Scan first / Vendor it / Post it / Keep it.
local ADDON, Panoply = ...
local C = Panoply.Compat
local Auc = Panoply.Auctions
local T = Auc.Trade
local V = {}
Auc.Verdict = V

V.POST, V.KEEP, V.VENDOR, V.SCAN = "post", "keep", "vendor", "scan"
V.NAME = { post = "Post it", keep = "Keep it", vendor = "Vendor it", scan = "Scan first" }
V.DEFAULT_WORTH = 500   -- 5 silver
-- Skin colour of each verdict. "loss" is the one colour token this feature adds (UI/Skin.lua).
V.COLOR = { post = "done", keep = "highlight", vendor = "loss", scan = "inkSoft" }

-- The profit per post that makes "Post it", in copper (the setting is a money text such as "5s").
function V.Worth()
  local c = T.ParseMoney(Panoply.db and Panoply.db.auctionWorth or "5s")
  return (c and c > 0) and c or V.DEFAULT_WORTH
end

local function round(x) return math.floor(x + 0.5) end

-- The numbers of one post and its verdict. Returns { verdict, price, stack, sale, cutAmount, net, costEach, cost, profit,
-- profitEach, vendorStack }; with no price only { verdict = "scan" }.
function V.Compute(inp)
  local price, stack = inp.price, math.max(1, math.floor(tonumber(inp.stack) or 1))
  if not price or price <= 0 then return { verdict = V.SCAN, stack = stack } end
  local cutRate = inp.cut or 0.05
  local vendor = inp.vendor or 0
  local costEach = inp.cost or vendor
  local r = { price = price, stack = stack, cutRate = cutRate, costEach = costEach, vendor = vendor }
  r.sale = price * stack
  r.net = round(r.sale * (1 - cutRate))
  r.cutAmount = r.sale - r.net
  r.cost = round(costEach * stack)
  r.profit = r.net - r.cost
  r.profitEach = round(price * (1 - cutRate)) - round(costEach)
  r.vendorStack = vendor * stack
  r.worth = inp.worth or V.DEFAULT_WORTH
  if vendor > 0 and r.net <= r.vendorStack then r.verdict = V.VENDOR
  elseif r.profit >= r.worth then r.verdict = V.POST
  else r.verdict = V.KEEP end
  return r
end

-- Sort key of the sell list: profit per post, best first; items with no price last, then by name.
function V.Before(a, b)
  local ap, bp = a.v.profit, b.v.profit
  if (ap == nil) ~= (bp == nil) then return ap ~= nil end
  if ap ~= bp and ap ~= nil then return ap > bp end
  return (a.name or "") < (b.name or "")
end

-- "+8g 74s 68c" / "-2s 10c": the sign is always shown, so colour is never the only cue.
function V.Signed(c)
  c = round(c or 0)
  if c < 0 then return "-" .. T.MoneyText(-c) end
  return "+" .. T.MoneyText(c)
end

-- How long ago, in plain words ("12 minutes ago"); short = the Vendor tab's form ("12 min ago", "2 h ago").
function V.Ago(sec, short)
  if not sec then return "never" end
  sec = math.max(0, sec)
  if sec < 60 then return "just now" end
  if sec < 3600 then
    local m = math.floor(sec / 60)
    return short and ("%d min ago"):format(m) or ("%d minute%s ago"):format(m, m == 1 and "" or "s")
  end
  if sec < 86400 then
    local h = math.floor(sec / 3600)
    return short and ("%d h ago"):format(h) or ("%d hour%s ago"):format(h, h == 1 and "" or "s")
  end
  local d = math.floor(sec / 86400)
  return d == 1 and "1 day ago" or ("%d days ago"):format(d)
end

-- The one or two sentences under the verdict word. `crafted`: the cost is the materials (else the vendor price).
function V.Sentence(r, crafted, worth)
  local m = T.MoneyText
  if r.verdict == V.SCAN then
    return "No price on file for this item. Scan the auction house, or click Check price now."
  end
  if r.verdict == V.VENDOR then
    return ("Vendor pays %s; the auction house leaves you %s. Posting needs two clicks."):format(m(r.vendorStack), m(r.net))
  end
  if r.verdict == V.POST then
    if crafted then
      return ("Materials cost %s. You keep %s after the cut: %s profit."):format(m(r.cost), m(r.net), m(r.profit))
    end
    return ("A vendor pays %s. You keep %s after the cut: %s more."):format(m(r.cost), m(r.net), m(r.profit))
  end
  if r.profit < 0 then
    return ("At this price posting loses %s. Keep it until the price rises."):format(m(-r.profit))
  elseif r.profit == 0 then
    return "At this price posting earns nothing. Keep it until the price rises."
  end
  return ("Posting earns only %s, under the %s minimum. Keep it for a better price."):format(m(r.profit), m(worth or V.DEFAULT_WORTH))
end
