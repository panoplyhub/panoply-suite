-- Panoply Suite modules (SPEC section 19): optional parts of the suite (merchant, bags, item glow,
-- gathering, profession window, waypoints). Each one lives in Modules/<Name>/, can be switched
-- off in Settings > Modules without errors.
local ADDON, Panoply = ...
local C = Panoply.Compat
local M = { list = {}, byKey = {} }
Panoply.Modules = M

-- def = { key, label, desc, icon, default = true,
--         defaults = { db keys }, options = { settings rows }, Enable = fn, Disable = fn }
function M:Register(def)
  assert(def.key and not self.byKey[def.key], "module key")
  def.active = false
  self.list[#self.list + 1] = def
  self.byKey[def.key] = def
  for k, v in pairs(def.defaults or {}) do Panoply.defaults.account[k] = v end
  -- Game events for a module only reach it while it is on.
  function def:On(event, fn) Panoply:On(event, function(...) if def.active then return fn(...) end end) end
  function def:Listen(name, fn) Panoply:Listen(name, function(...) if def.active then return fn(...) end end) end
  function def:IsOn() return self.active end
  return def
end

function M:Get(key) return self.byKey[key] end
function M:IsOn(key) local d = self.byKey[key] return d and d.active or false end

function M:Wanted(key)
  local d = self.byKey[key]
  local saved = Panoply.db and Panoply.db.modules and Panoply.db.modules[key]
  if saved == nil then return d and d.default ~= false end
  return saved and true or false
end

function M:Apply(d)
  local want = self:Wanted(d.key)
  local on = want and true or false
  if on == d.active then return on end
  d.active = on
  local fn = on and d.Enable or d.Disable
  if fn then
    local ok, err = pcall(fn, d)
    if not ok then d.error = err; Panoply:Debug("module", d.key, err) end
  end
  Panoply:Fire("MODULE_CHANGED", d.key, on)
  return on
end

function M:ApplyAll(login)
  Panoply.db.modules = Panoply.db.modules or {}
  for _, d in ipairs(self.list) do
    self:Apply(d)
  end
end

function M:Set(key, on)
  local d = self.byKey[key]
  if not d or not Panoply.db then return end
  Panoply.db.modules = Panoply.db.modules or {}
  Panoply.db.modules[key] = on and true or false
  self:Apply(d)
  Panoply:Fire("OPTION_CHANGED", "module:" .. key, on)
end

function M:Status(key)
  local d = self.byKey[key]
  if not d then return "Unknown" end
  if d.active then return "On" end
  return "Off"
end
