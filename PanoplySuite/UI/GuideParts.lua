-- Panoply Suite 0.9.5 phase 4K: the Follows control (spec 05 section 4.2, spec 05b section 2.2, spec 06a section 3.3), the one control
-- the Guide page's header and the guide window's header both use for what the guide follows. It replaces the Leveling / Professions /
-- Both / <profession> switch there; it only sets what already exists:
--   "Leveling only"            -> Panoply.ProfGuide:SetActive("leveling")
--   "Leveling + Cooking"       -> Panoply.ProfGuide:SetActive("both", "Cooking")
--   "Cooking only"             -> Panoply.ProfGuide:SetActive("professions", "Cooking")
-- No new saved setting: activeGuide and profTrack are the settings these always were.
local ADDON, Panoply = ...
local GP = {}
Panoply.GuideParts = GP

GP.LEVELING = "leveling"

-- the profession a choice names ("both:Cooking" -> "both", "Cooking")
function GP.Split(value)
  if type(value) ~= "string" then return nil end
  local mode, prof = value:match("^(%a+):(.+)$")
  if mode then return mode, prof end
  return value, nil
end

-- What the guide follows now, as a choice value
function GP.Current()
  local G = Panoply.ProfGuide
  if not G then return GP.LEVELING end
  local a = G:Active()
  local prof = G:Tracked()
  if a == "leveling" or not prof then return GP.LEVELING end
  if a == "both" then return "both:" .. prof end
  return "only:" .. prof
end

-- The choices, in order: Leveling only; Leveling + each profession; each profession only.
function GP.Items()
  local G = Panoply.ProfGuide
  local profs = G and G:Chosen() or {}
  local out = { { value = GP.LEVELING, text = "Leveling only", tip = "Follow your levelling route. Your profession steps wait and keep their place." } }
  for _, p in ipairs(profs) do
    out[#out + 1] = { value = "both:" .. p, text = "Leveling + " .. p, tip = ("Your route, with %s steps added when the place is close by."):format(p) }
  end
  for _, p in ipairs(profs) do
    out[#out + 1] = { value = "only:" .. p, text = p .. " only", tip = ("Follow your %s plan step by step. Your route waits on its current step."):format(p) }
  end
  return out
end

-- The words for the current choice ("Leveling + Cooking")
function GP.Label(value)
  value = value or GP.Current()
  for _, it in ipairs(GP.Items()) do if it.value == value then return it.text end end
  return "Leveling only"
end

-- Make a choice. Returns true when it was one of the choices.
function GP.Set(value)
  local mode, prof = GP.Split(value)
  local G = Panoply.ProfGuide
  local guide = (mode == GP.LEVELING and "leveling") or (mode == "both" and "both") or (mode == "only" and "professions") or nil
  if not guide then return false end
  if G then G:SetActive(guide, prof) end
  return true
end

-- The dropdown: GP.Follows(parent, { page = "guide", width = 220 }) -> a Kit.Dropdown reading "Follows: Leveling + Cooking".
-- It redraws itself when the guide or the tracked profession change anywhere.
function GP.Follows(parent, o)
  o = o or {}
  local dd = Panoply.Kit.Dropdown(parent, { page = o.page, width = o.width or 220, height = o.height, label = o.noLabel and "" or "Follows: ",
    items = GP.Items, get = GP.Current, set = GP.Set, onChange = o.onChange, menuWidth = 220,
    tip = "What the guide follows", tipBody = "Your levelling route, a profession beside it, or a profession alone." })
  dd.panoplyFollows = true
  GP.live = GP.live or setmetatable({}, { __mode = "k" })
  GP.live[dd] = true
  return dd
end

function GP.RefreshAll()
  for dd in pairs(GP.live or {}) do pcall(dd.Refresh, dd) end
end
Panoply:Listen("GUIDE_SWITCHED", GP.RefreshAll)
Panoply:Listen("OPTION_CHANGED", function(key) if key == "activeGuide" or key == "profTrack" then GP.RefreshAll() end end)
