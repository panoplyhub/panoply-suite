-- Panoply Suite 0.9.5, phase 4A4 (docs/specs/page-redesigns-06-help.md sections 2.2 and 2.3; 06b section 1): the help registry and the
-- slash-command registry, both on Panoply.Help (spec 06 calls it Panoply.Help; item 8 renames the namespace). Original code for Panoply Suite.
--
-- Help:Register(page, { subtitle = text or function, tips = { { key, title, body = text or function, lines = function, when = function } } })
--   A page (its Catalog key, or "everywhere" for the tips that belong to no one page) registers its one-line subtitle and its tips here.
--   The Help page shows what is registered, so a page and Help can never disagree. A page that registers nothing still has a row: its
--   Catalog subtitle (page.text) and its "?" text (page.help).
-- Help:Command({ key, usage, desc, group, aliases, module, when, note, chat, page, order })
--   Each slash command registers its usage line and what it does. The Help page's list and /panoply help are made from these.
--   usage may be a function (it returns nil to show no command, only the note).
--   chat is the line /panoply help prints (default "usage - desc"; false prints nothing). page = false keeps it out of the Help page's
--   list (commands for building Panoply Suite, and the finer forms of a command already listed). order sorts /panoply help.
local ADDON, Panoply = ...
local Help = Panoply.Help or {}
Panoply.Help = Help

Help.EVERYWHERE = "everywhere"
Help.pages = Help.pages or {}
Help.commands = Help.commands or {}
Help.cmdByKey = Help.cmdByKey or {}
Help.seq = Help.seq or 0

-- the groups of the commands list, in order (spec 06 section 2.3)
Help.GROUPS = {
  { key = "open", label = "Open things" },
  { key = "guide", label = "Guide and arrow" },
  { key = "waypoints", label = "Waypoints" },
  { key = "items", label = "Bags and items" },
  { key = "help", label = "Help and problems" },
}
Help.GROUP = {}
for i, g in ipairs(Help.GROUPS) do Help.GROUP[g.key] = i end

local function nextSeq() Help.seq = Help.seq + 1 return Help.seq end

-- a text that may be a function; a function that fails gives nil and is noted (never an error on the page)
local function resolve(v, what)
  if type(v) == "function" then
    local ok, r = pcall(v)
    if not ok then Panoply:Debug("help text", what or "?", r) return nil end
    return r
  end
  return v
end
Help.Resolve = resolve

-------------------------------------------------------------------------------
-- Tips by page
-------------------------------------------------------------------------------
function Help:Register(page, def)
  if type(page) ~= "string" or page == "" then error("Help:Register needs a page key", 2) end
  if type(def) ~= "table" then error("Help:Register needs a table", 2) end
  local e = self.pages[page]
  if not e then e = { key = page, tips = {}, byKey = {}, seq = nextSeq() } self.pages[page] = e end
  if def.subtitle ~= nil then e.subtitle = def.subtitle end
  for i, t in ipairs(def.tips or {}) do
    if type(t) ~= "table" or type(t.title) ~= "string" or (t.body == nil and t.lines == nil) then
      error(("Help:Register(%s): tip %d needs a title and a body"):format(page, i), 2)
    end
    local key = t.key or (t.title:lower())
    local old = e.byKey[key]
    local tip = { key = key, page = page, title = t.title, body = t.body, lines = t.lines, when = t.when, seq = old and old.seq or nextSeq() }
    if old then
      for j, o in ipairs(e.tips) do if o == old then e.tips[j] = tip end end
    else
      e.tips[#e.tips + 1] = tip
    end
    e.byKey[key] = tip
  end
  return e
end

-- one tip as { title, body } (body made from its lines when it has them), or nil while it does not apply
function Help.TipText(t)
  if t.when then
    local ok, yes = pcall(t.when)
    if not (ok and yes) then return nil end
  end
  local body
  if t.lines then
    local l = resolve(t.lines, t.key)
    body = type(l) == "table" and table.concat(l, " ") or nil
  else
    body = resolve(t.body, t.key)
  end
  return { t.title, tostring(body or ""), key = t.key, page = t.page }
end

local function catalogPage(key) local Cat = Panoply.Catalog return Cat and type(Cat[key]) == "table" and Cat[key].key == key and Cat[key] or nil end

-- What Help shows for one page: { key, label, icon, subtitle, tips = { { title, body }, ... } }. nil for a page that is not there.
function Help:Entry(page)
  local e = self.pages[page]
  if page == Help.EVERYWHERE then
    local tips = {}
    for _, t in ipairs(e and e.tips or {}) do tips[#tips + 1] = Help.TipText(t) end
    return { key = page, label = "Everywhere", icon = "Logo", subtitle = resolve(e and e.subtitle) or "What works on every page.", tips = tips }
  end
  local p = catalogPage(page)
  if not p and not e then return nil end
  local out = { key = page, label = p and p.label or page, icon = p and p.icon or nil, tips = {} }
  out.subtitle = resolve(e and e.subtitle, page) or (p and p.text) or ""
  -- the page's own "?" text comes first: it is what the page says about itself
  if p and type(p.help) == "string" and p.help ~= "" then out.tips[1] = { p.label, p.help, key = "page", page = page } end
  for _, t in ipairs(e and e.tips or {}) do out.tips[#out.tips + 1] = Help.TipText(t) end
  return out
end

-- Everywhere first, then every page of the left list in its order (the pages the player sees; Panoply.Menu:PageList).
function Help:Entries()
  local out = { self:Entry(Help.EVERYWHERE) }
  local list
  if Panoply.Menu and Panoply.Menu.PageList then
    local ok, l = pcall(Panoply.Menu.PageList, Panoply.Menu, false)
    if ok then list = l end
  end
  if not list then list = Panoply.Catalog and Panoply.Catalog.PAGES or {} end
  for _, pg in ipairs(list) do
    local en = self:Entry(pg.key)
    if en then out[#out + 1] = en end
  end
  return out
end

-- Every tip that applies, in the order they were registered, as { title, body } (what the Help page's Tips list shows).
function Help:AllTips()
  local all = {}
  for _, e in pairs(self.pages) do for _, t in ipairs(e.tips) do all[#all + 1] = t end end
  table.sort(all, function(a, b) return a.seq < b.seq end)
  local out = {}
  for _, t in ipairs(all) do out[#out + 1] = Help.TipText(t) end
  return out
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
function Help:Command(def)
  if type(def) ~= "table" or type(def.key) ~= "string" then error("Help:Command needs a key", 2) end
  if def.usage == nil and def.chat == nil then error("Help:Command(" .. def.key .. ") needs a usage line", 2) end
  if def.group ~= nil and not Help.GROUP[def.group] then error("Help:Command(" .. def.key .. "): unknown group " .. tostring(def.group), 2) end
  local c = self.cmdByKey[def.key]
  if not c then c = { seq = nextSeq() } self.cmdByKey[def.key] = c self.commands[#self.commands + 1] = c end
  for k, v in pairs(def) do c[k] = v end
  c.order = c.order or c.seq
  c.aliases = c.aliases or {}
  return c
end

local function cmdOn(c)
  -- a command whose module is off is left out, unless it has a note to show then
  if c.module and not (Panoply.Modules and Panoply.Modules:IsOn(c.module)) and not resolve(c.note, c.key) then return false end
  if c.when then
    local ok, yes = pcall(c.when)
    if not (ok and yes) then return false end
  end
  return true
end

-- One command as the Help page lists it: { usage (nil = no command shown), desc, aliases = { ... }, note, group, key, module }
function Help.CommandRow(c)
  return { usage = resolve(c.usage, c.key), desc = resolve(c.desc, c.key) or "", aliases = resolve(c.aliases, c.key) or {},
           note = resolve(c.note, c.key), group = c.group or "help", key = c.key, module = c.module }
end

-- The Help page's list: the commands that are on, grouped (in Help.GROUPS order), each group in the order the commands registered;
-- "/panoply help" is the last row. group (optional) gives only that group.
function Help:CommandList(group)
  local rows = {}
  for _, c in ipairs(self.commands) do
    if c.page ~= false and (group == nil or (c.group or "help") == group) and cmdOn(c) then rows[#rows + 1] = c end
  end
  table.sort(rows, function(a, b)
    if (a.key == "help") ~= (b.key == "help") then return b.key == "help" end
    local ga, gb = Help.GROUP[a.group or "help"], Help.GROUP[b.group or "help"]
    if ga ~= gb then return ga < gb end
    return a.order < b.order
  end)
  local out = {}
  for i, c in ipairs(rows) do out[i] = Help.CommandRow(c) end
  return out
end

-- "also /panoply hall, /hearthhall"
function Help.AliasText(row)
  local a = row.aliases or {}
  if #a == 0 then return nil end
  return "also " .. table.concat(a, ", ")
end

-- What /panoply help prints, in order: the chat line of each command (as in 0.9.4, whether or not its module is on).
function Help:ChatLines()
  local list = {}
  for _, c in ipairs(self.commands) do if c.chat ~= false then list[#list + 1] = c end end
  table.sort(list, function(a, b) return a.order < b.order end)
  local out = {}
  for _, c in ipairs(list) do
    local line = resolve(c.chat, c.key)
    if line == nil then
      local u = resolve(c.usage, c.key)
      if u then line = u .. " - " .. (resolve(c.desc, c.key) or "") else line = resolve(c.note, c.key) end
    end
    if line then out[#out + 1] = line end
  end
  return out
end

-- Click a command on the Help page: the command goes into the chat box, ready to send (nothing is sent; the player presses Enter).
-- Returns the text put there, or nil when there is no chat box.
function Help.PasteCommand(row)
  local text = type(row) == "table" and row.usage or row
  if type(text) ~= "string" or text == "" then return nil end
  text = text:gsub("%s%s+.*$", "")   -- "/panoply bags   /panoply bank": the first one
  local open = _G.ChatFrame_OpenChat
  if type(open) ~= "function" then return nil end
  local ok = pcall(open, text .. " ")
  return ok and text or nil
end
