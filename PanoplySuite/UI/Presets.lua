-- Panoply Suite, Step 2 item B: Small / Normal / Large on every page (docs/step2/ABC-SPEC.md B-01, B-03; our decision 1).
-- A page's header has "Size: Small, Normal, Large" (not Profiles and Help: nothing there resizes). The three choices are 80%, 100%
-- and 130% of the standard size. What each one sets is the page's own size settings, the same ones its gear shows as exact sliders:
--   * Guide:  the size of every Panoply Suite window (Window size, UI/Skin.lua Panoply.Windows: held to what fits the screen, never in combat)
--             and the size of the arrow;
--   * Map:    the size of every thing drawn on the maps, on the world map and the minimap (Panoply.Look, one setting for each);
--   * every other page: Window size. That one setting reaches the menu itself, the guide window, the bag windows, the auction
--             panels, the profession tracker and every other window of Panoply Suite's own (the windows that hang from the game's own
--             panels stay as they are).
-- Nothing new is saved for the presets: the choice that is lit is whichever one the page's settings add up to.
local ADDON, Panoply = ...
local Pre = {}
Panoply.Presets = Pre
local Look = Panoply.Look

-- the pages with no Size choice
-- (Profiles and Help; Hunter & Pet is a "coming soon" page and Unit frames has no body: a page with nothing to resize gets no Size choice)
Pre.NONE = { profiles = true, help = true, hunter = true, frames = true }

function Pre:Has(pageKey) return pageKey ~= nil and not Pre.NONE[pageKey] and Panoply.Catalog[pageKey] ~= nil end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- What a page's choice sets: { { key = saved key, value = function(factor) -> the value to save } }
function Pre:Targets(pageKey)
  if not self:Has(pageKey) then return {} end
  if pageKey == "map" then
    local out = {}
    for _, t in ipairs(Look.THINGS) do
      for _, m in ipairs(t.maps) do
        out[#out + 1] = { key = Look.Key(t.id, m, "size"), value = function(f) return clamp(f, Look.SIZE_MIN, Look.SIZE_MAX) end }
      end
    end
    return out
  end
  local out = { { key = "windowScale", value = function(f) return clamp(f, Look.WINDOW_MIN, Look.WINDOW_MAX) end } }
  if pageKey == "guide" then
    out[#out + 1] = { key = "arrowScale", value = function(f) return clamp(f, Look.ARROW_MIN, Look.ARROW_MAX) end }
  end
  return out
end

local function factorOf(id)
  for _, p in ipairs(Look.PRESETS) do if p.id == id then return p.factor end end
end

-- Which choice is lit: the one every size of the page equals, or nil (the sizes were set by hand in the gear)
function Pre:Current(pageKey)
  local targets = self:Targets(pageKey)
  if #targets == 0 or not Panoply.db then return nil end
  for _, p in ipairs(Look.PRESETS) do
    local all = true
    for _, t in ipairs(targets) do
      local v = tonumber(Panoply.db[t.key])
      if v == nil then v = 1 end
      if math.abs(v - t.value(p.factor)) > 0.005 then all = false break end
    end
    if all then return p.id end
  end
  return nil
end

-- Set every size of the page to the choice. Returns how many settings changed.
function Pre:Apply(pageKey, id)
  local f = factorOf(id)
  if not f then return 0 end
  local n = 0
  self.applying = true
  local Menu = Panoply.Menu
  if Menu then Menu.batching = true end
  for _, t in ipairs(self:Targets(pageKey)) do
    local want = t.value(f)
    if Panoply.db[t.key] ~= want then Panoply:SetOption(t.key, want) n = n + 1 end
  end
  self.applying = nil
  if Menu then Menu.batching = nil end
  return n
end

-- The words for a size, for tips and the What's new note
function Pre.Name(id)
  for _, p in ipairs(Look.PRESETS) do if p.id == id then return p.name end end
end
