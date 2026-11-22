-- Panoply Suite utilities: tables, hashing, big bitmasks, a safe serializer.
local ADDON, Panoply = ...
local U = {}
Panoply.Util = U

local floor, format, byte, sub, find = math.floor, string.format, string.byte, string.sub, string.find

function U.Copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = U.Copy(v) end
  return r
end

function U.Keys(t) local r = {} for k in pairs(t) do r[#r + 1] = k end return r end
function U.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function U.Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function U.Round(v, d) local m = 10 ^ (d or 0) return floor(v * m + 0.5) / m end

-- Bit test that works for masks above 2^32 (race masks use bits 32/33 for Skyborne).
-- `bitValue` is the power-of-two value for the bit (e.g. 1, 4, 4294967296).
function U.HasBitValue(mask, bitValue)
  if type(mask) ~= "number" or type(bitValue) ~= "number" or bitValue <= 0 then return false end
  return floor(mask / bitValue) % 2 == 1
end

-- 32-bit-safe-ish string hash (djb2), returns a hex string.
function U.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + byte(s, i)) % 4294967296 end
  return format("%08x", h)
end

function U.FormatMoney(copper)
  copper = floor((copper or 0) + 0.5)
  local g = floor(copper / 10000)
  local s = floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return format("%dg %ds %dc", g, s, c) end
  if s > 0 then return format("%ds %dc", s, c) end
  return format("%dc", c)
end

-------------------------------------------------------------------------------
-- Serializer: compact, printable, no code execution on decode.
-- Z=nil T=true F=false N<num>; S<len>:<bytes> { k v k v ... }
-------------------------------------------------------------------------------
local function ser(v, out, depth)
  if depth > 20 then error("serialize: too deep") end
  local t = type(v)
  if t == "nil" then out[#out + 1] = "Z"
  elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("serialize: bad number") end
    if v == floor(v) and v > -1e15 and v < 1e15 then out[#out + 1] = format("N%d;", v)
    else out[#out + 1] = "N" .. format("%.14g", v) .. ";" end
  elseif t == "string" then out[#out + 1] = "S" .. #v .. ":" .. v
  elseif t == "table" then
    out[#out + 1] = "{"
    -- deterministic order: array part first, then sorted other keys
    local n = #v
    for i = 1, n do ser(i, out, depth + 1); ser(v[i], out, depth + 1) end
    local other = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == floor(k)) then other[#other + 1] = k end
    end
    table.sort(other, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      if ta == "number" or ta == "string" then return a < b end
      return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(other) do ser(k, out, depth + 1); ser(v[k], out, depth + 1) end
    out[#out + 1] = "}"
  else
    error("serialize: unsupported type " .. t)
  end
end

function U.Serialize(v)
  local out = {}
  ser(v, out, 0)
  return table.concat(out)
end

local function de(s, pos, depth)
  if depth > 20 then error("deserialize: too deep") end
  local c = sub(s, pos, pos)
  if c == "Z" then return nil, pos + 1
  elseif c == "T" then return true, pos + 1
  elseif c == "F" then return false, pos + 1
  elseif c == "N" then
    local e = find(s, ";", pos + 1, true)
    if not e then error("deserialize: bad number") end
    local n = tonumber(sub(s, pos + 1, e - 1))
    if not n then error("deserialize: bad number") end
    return n, e + 1
  elseif c == "S" then
    local colon = find(s, ":", pos + 1, true)
    if not colon then error("deserialize: bad string") end
    local len = tonumber(sub(s, pos + 1, colon - 1))
    if not len or len < 0 or colon + len > #s then error("deserialize: bad string length") end
    return sub(s, colon + 1, colon + len), colon + len + 1
  elseif c == "{" then
    local t = {}
    pos = pos + 1
    local guard = 0
    while sub(s, pos, pos) ~= "}" do
      if pos > #s then error("deserialize: unterminated table") end
      local k, v
      k, pos = de(s, pos, depth + 1)
      v, pos = de(s, pos, depth + 1)
      if k == nil then error("deserialize: nil key") end
      t[k] = v
      guard = guard + 1
      if guard > 20000 then error("deserialize: table too large") end
    end
    return t, pos + 1
  end
  error("deserialize: unexpected '" .. c .. "' at " .. pos)
end

function U.Deserialize(s)
  if type(s) ~= "string" or s == "" then return false, "empty" end
  local ok, v, pos = pcall(de, s, 1, 0)
  if not ok then return false, v end
  if pos ~= #s + 1 then return false, "trailing data" end
  return true, v
end

-- Transport escaping: keep addon-channel payloads free of NUL and '|' (chat escape char).
function U.Escape(s)
  return (s:gsub("~", "~~"):gsub("|", "~p"):gsub("%z", "~0"))
end
function U.Unescape(s)
  return (s:gsub("~(.)", function(c)
    if c == "~" then return "~" elseif c == "p" then return "|" elseif c == "0" then return "\0" end
    return c
  end))
end
