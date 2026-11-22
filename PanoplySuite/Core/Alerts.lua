-- Panoply Suite 0.9.5, phase 4A3: the shared alerts registry (docs/specs/page-redesigns-05-home-guide-map.md section 2).
-- Home's "Needs you", the nav dots and (phase 4I) Muster's alerts chip all read this one list; nothing works an alert out twice.
--
--   Panoply.Alerts:Publish{ id, severity = "act"|"info", icon, text, detail, target = { page, tab, state }, characterKey, kind }
--   Panoply.Alerts:Clear(id)
--   Panoply.Alerts:List(filter)        -- filter: severity, characterKey, page, kind, mine (this character and the account-wide ones)
--   Panoply.Alerts:Subscribe(cb)       -- cb(list) after every change; returns a function that unsubscribes
--   Panoply.Alerts:Open(alert or id)   -- opens its target as one step of Back / Forward (UI/History.lua)
--
-- Each alert has a KIND (spells to buy, bags full...). A kind belongs to the page that publishes it and has one on / off setting,
-- in that page's settings (Panoply.Alerts:Kind); switched off, the kind is left out of every list, so it is gone everywhere at once.
-- Pages publish through a SOURCE (Panoply.Alerts:Source): a function that returns the alerts that hold now. A refresh runs every source
-- and clears what a source no longer returns. The sources of the pages that exist today are in UI/AlertSources.lua; pages built in
-- later phases add theirs as they land. The registry keeps nothing between sessions: every alert is worked out again from the
-- data its page already saves.
local ADDON, Panoply = ...

local A = { byId = {}, seq = 0, subs = {}, kinds = {}, kindOrder = {}, sources = {}, sourceOrder = {}, openers = {}, batch = 0 }
Panoply.Alerts = A

A.SEVERITIES = { act = 1, info = 2 }
A.REFRESH_DELAY = 0.5      -- seconds: a burst of game events (looting, a bag sort) is one refresh

-------------------------------------------------------------------------------
-- Kinds: one type of alert, and its one on / off setting
-------------------------------------------------------------------------------
-- spec = { page = owning page key, label = the setting's words, tip, severity = default severity, words = search words }
-- The setting is a NEW key of its own, "alert" + the kind ("alertSpellsToBuy"), on by default (Core/Init.lua defaults).
function A.SettingKey(kind) return "alert" .. kind:sub(1, 1):upper() .. kind:sub(2) end

function A:Kind(key, spec)
  assert(type(key) == "string" and key ~= "" and not key:find(":", 1, true), "Panoply.Alerts:Kind needs a key without ':'")
  assert(type(spec) == "table" and type(spec.page) == "string" and type(spec.label) == "string", "Panoply.Alerts:Kind needs a page and a label")
  spec.key, spec.setting = key, A.SettingKey(key)
  if not self.kinds[key] then self.kindOrder[#self.kindOrder + 1] = key end
  self.kinds[key] = spec
  return spec
end

function A:KindsOf(page)
  local out = {}
  for _, k in ipairs(self.kindOrder) do if self.kinds[k].page == page then out[#out + 1] = self.kinds[k] end end
  return out
end

-- a kind nobody registered is on: an alert is never hidden by a setting the player cannot see
function A:KindOn(kind)
  local k = kind and self.kinds[kind]
  if not k then return true end
  return not (Panoply.db and Panoply.db[k.setting] == false)
end

-------------------------------------------------------------------------------
-- Publish, clear, list
-------------------------------------------------------------------------------
local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local FIELDS = { "severity", "icon", "text", "detail", "target", "characterKey", "kind", "page", "source" }

function A:Changed()
  if self.batch > 0 then self.dirty = true return end
  self.dirty = false
  local list = self:List()
  for _, cb in ipairs(self.subs) do
    local ok, err = pcall(cb, list)
    if not ok then Panoply:Debug("alerts subscriber", err) end
  end
  if Panoply.Fire then Panoply:Fire("ALERTS_CHANGED") end
end

function A:Publish(t)
  assert(type(t) == "table" and type(t.id) == "string" and t.id ~= "", "Panoply.Alerts:Publish needs an id")
  assert(type(t.text) == "string" and t.text ~= "", "Panoply.Alerts:Publish needs text (" .. t.id .. ")")
  local kind = t.kind or t.id:match("^([^:]+)")
  local k = self.kinds[kind]
  local sev = t.severity or (k and k.severity) or "info"
  assert(A.SEVERITIES[sev], "Panoply.Alerts:Publish: severity is \"act\" or \"info\" (" .. t.id .. ")")
  local target = type(t.target) == "table" and t.target or {}
  local rec = { id = t.id, severity = sev, icon = t.icon, text = t.text, detail = t.detail, characterKey = t.characterKey,
    kind = kind, page = t.page or (k and k.page) or target.page, source = t.source,
    target = { page = target.page or t.page or (k and k.page), tab = target.tab, state = target.state } }
  local old = self.byId[t.id]
  if old then
    local diff = false
    for _, f in ipairs(FIELDS) do if not same(old[f], rec[f]) then diff = true break end end
    if not diff then return old end
    rec.seq = old.seq
  else
    self.seq = self.seq + 1
    rec.seq = self.seq
  end
  self.byId[t.id] = rec
  self:Changed()
  return rec
end

function A:Clear(id)
  if self.byId[id] == nil then return false end
  self.byId[id] = nil
  self:Changed()
  return true
end

-- "Realm-Name": the key alerts about one character carry (built from the same realm and name pair Alts and the bag store use)
function A.CharKey(realm, name)
  if not (realm and name) then return nil end
  return realm .. "-" .. name
end
function A:MyKey()
  local P = Panoply.Profiles
  local realm, name
  if P and P.Me then realm, name = P:Me() end
  return A.CharKey(realm, name)
end

-- What a filter keeps: severity, characterKey, page, kind; mine = this character's and the account-wide ones (no characterKey).
-- Kinds switched off are left out unless filter.all. Order: "act" before "info", this character before the others, account-wide
-- next, then other characters, then the order they were first published in.
function A:List(filter)
  filter = filter or {}
  local me = self:MyKey()
  local out = {}
  for _, a in pairs(self.byId) do
    local keep = filter.all or self:KindOn(a.kind)
    if keep and filter.severity and a.severity ~= filter.severity then keep = false end
    if keep and filter.page and a.page ~= filter.page then keep = false end
    if keep and filter.kind and a.kind ~= filter.kind then keep = false end
    if keep and filter.characterKey and a.characterKey ~= filter.characterKey then keep = false end
    if keep and filter.mine and a.characterKey ~= nil and a.characterKey ~= me then keep = false end
    if keep then out[#out + 1] = a end
  end
  local function rank(a)
    if a.characterKey == nil then return 2 end
    if a.characterKey == me then return 1 end
    return 3
  end
  table.sort(out, function(a, b)
    local sa, sb = A.SEVERITIES[a.severity], A.SEVERITIES[b.severity]
    if sa ~= sb then return sa < sb end
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    return a.seq < b.seq
  end)
  return out
end

function A:Count(filter) return #self:List(filter) end

-- the nav dot: the page has at least one "act" alert that is switched on
function A:PageHasAct(page)
  for _, a in pairs(self.byId) do
    if a.page == page and a.severity == "act" and self:KindOn(a.kind) then return true end
  end
  return false
end

function A:Subscribe(cb)
  assert(type(cb) == "function", "Panoply.Alerts:Subscribe needs a function")
  self.subs[#self.subs + 1] = cb
  return function()
    for i, f in ipairs(A.subs) do if f == cb then table.remove(A.subs, i) return true end end
    return false
  end
end

-------------------------------------------------------------------------------
-- Sources: what a page publishes, worked out again at every refresh
-------------------------------------------------------------------------------
-- fn() returns a list of Publish tables (or nil for none). An error in a source keeps that source's earlier alerts (an alert never
-- disappears because its page failed to look) and is noted with Panoply:Debug.
function A:Source(name, fn)
  assert(type(name) == "string" and type(fn) == "function", "Panoply.Alerts:Source needs a name and a function")
  if not self.sources[name] then self.sourceOrder[#self.sourceOrder + 1] = name end
  self.sources[name] = fn
end

function A:RunSource(name)
  local fn = self.sources[name]
  if not fn then return false end
  local ok, list = pcall(fn)
  if not ok then Panoply:Debug("alerts source " .. name, list) return false end
  local seen = {}
  for _, t in ipairs(type(list) == "table" and list or {}) do
    t.source = name
    local okP, err = pcall(self.Publish, self, t)
    if okP then seen[t.id] = true else Panoply:Debug("alerts publish " .. name, err) end
  end
  for id, a in pairs(self.byId) do
    if a.source == name and not seen[id] then self.byId[id] = nil self.dirty = true end
  end
  return true
end

function A:Refresh()
  self.batch = self.batch + 1
  for _, name in ipairs(self.sourceOrder) do self:RunSource(name) end
  self.batch = self.batch - 1
  self.lastRefresh = Panoply.Compat and Panoply.Compat.GetTime and Panoply.Compat.GetTime() or 0
  if self.dirty then self:Changed() end
end

-- soon, once: many events in a row are one refresh; in a fight it waits for the fight to end
function A:RefreshSoon()
  if self.pending then return end
  local C = Panoply.Compat
  if not (C and C.After) then return self:Refresh() end
  self.pending = true
  C.After(A.REFRESH_DELAY, function()
    A.pending = false
    if C.InCombat and C.InCombat() then A.afterCombat = true return end
    A:Refresh()
  end)
end

-------------------------------------------------------------------------------
-- Opening an alert's target
-------------------------------------------------------------------------------
-- a page that needs more than Menu:Open to show a tab or a state registers how (UI/AlertSources.lua)
function A:Opener(page, fn) self.openers[page] = fn end

function A:Open(a)
  if type(a) == "string" then a = self.byId[a] end
  if type(a) ~= "table" then return false end
  local t = a.target or {}
  local page = t.page or a.page
  if not page then return false end
  local H = Panoply.History
  if H then H:Begin() end
  local ok, err = pcall(function()
    local fn = A.openers[page]
    if fn then fn(t, a) else Panoply.Menu:Open(page) end
  end)
  if H then H:End("alert") end
  if not ok then Panoply:Debug("alerts open " .. tostring(a.id), err) end
  return ok
end

-------------------------------------------------------------------------------
-- When to look again
-------------------------------------------------------------------------------
A.EVENTS = { "ALTS_CHANGED", "INVENTORY_CHANGED", "AUCTION_SCAN_DONE", "SPEC_TRAINER_CHANGED", "LEVEL_CHANGED", "STEP_CHANGED",
  "STEPS_CHANGED", "LEGACY_CHANGED", "PROF_UPDATED", "MODULE_CHANGED", "PROFILES_CHANGED", "PLAN_ADOPTED" }
A.GAME_EVENTS = { "PLAYER_MONEY", "GROUP_ROSTER_UPDATE", "CHARACTER_POINTS_CHANGED", "SKILL_LINES_CHANGED" }

if Panoply.Listen then
  for _, ev in ipairs(A.EVENTS) do Panoply:Listen(ev, function() A:RefreshSoon() end) end
  -- an alert setting switched on or off shows or hides that kind at once (nothing to work out again)
  Panoply:Listen("OPTION_CHANGED", function(key)
    if type(key) == "string" and key:find("^alert") then A:Changed() else A:RefreshSoon() end
  end)
end
if Panoply.On then
  for _, ev in ipairs(A.GAME_EVENTS) do Panoply:On(ev, function() A:RefreshSoon() end) end
  Panoply:On("PLAYER_REGEN_ENABLED", function() if A.afterCombat then A.afterCombat = false A:RefreshSoon() end end)
  Panoply:On("PLAYER_ENTERING_WORLD", function() A:RefreshSoon() end)
end
