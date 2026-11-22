-- Panoply Suite 0.9.7: levelling with a partner (sync, the hold card and the help-your-partner step). Own code; it calls the engine's
-- public party calls, it does not copy them.
--
-- Nov 18 2026: "Partner levelling is REQUIRED for launch: sync, the class-quest hold card, and the help-your-partner step.
-- Polestar's party sync may share guide, step, level, XP %, class, race and version. Switch OFF Polestar's guild/whisper version hello
-- (update.probe false) and keep transit sharing off (nav.shareTransit false)."
--
-- The engine's own party sync does the talking (hidden add-on messages to the party only, never a raid, never chat). This file is
-- Panoply Suite's side of it:
--   * the switch: PanoplySuiteDB.partyShare (on unless turned off) sets the engine's party.share and party.show through the adapter's
--     PS:Manage, which keeps what each was and puts it back (PS:Unmanage). Off means nothing is sent and nothing is shown;
--   * party only: the engine's other senders are pinned off whatever the switch says: its whispered version question
--     (update.probe), its boat and zeppelin timings to guild, raid and party (nav.shareTransit), and its once-a-login version hello
--     to the guild. That hello has no setting of its own (it follows party.share), so the two times the engine reads before it
--     sends to the guild (Update.State: helloAt, replyAt) are held in the far future; what they were is kept in
--     PanoplySuiteDB.polestarQuiet and put back by PolestarParty:Unpin (with PS:Unmanage);
--   * the agreed interface the windows draw from:
--       PolestarParty:Enabled()     -> true when partner levelling is on and can run
--       PolestarParty:PartnerLine() -> one line about the partner for the guide window, or nil
--       PolestarParty:Card()        -> the card to show (sync, hold or help, with its buttons), or nil; asks PartnerHold:Card() first
--       PolestarParty:RequestSync() / :Accept() / :Decline() / :GoOn() -> the card's buttons; true when the action was taken
--       PolestarParty:Waiting(q)    -> true (and the names) when the partner still needs quest q
--       PolestarParty:Following()   -> the partner's name while this character follows their guide after a sync, else nil
--       PolestarParty:EndSync(why)  -> ends that (the guide picker calls it when another guide is picked); says nothing
--       PolestarParty:Help() / :StopHelp() -> the hold card's "Help <name>" and "Stop helping" (Engine/PartnerHold.lua does them)
--     a card is { kind = "sync" | "wait" (PartnerHold's own: "hold" | "help" | "ahead"), who, partner, title, lines = { text, ... },
--     buttons = { { label, tip, action (the PolestarParty function to call), primary }, ... } }.
--     "PARTNER_CHANGED" is fired (with "SYNC_STATUS") whenever the partner line, the card or a waiting answer may have changed.
-- Nothing here moves the character or acts for the player: a sync only moves the guide's own place, after the player says yes.
local ADDON, Panoply = ...
local PolestarParty = {}
Panoply.PolestarParty = PolestarParty
local PP = PolestarParty
local C = Panoply.Compat

-- the engine's own question for a sync request (the game's pop-up), by its name (kept in Engine/PolestarVoice.lua with the engine's other names)
PP.POPUP = Panoply.PolestarVoice and Panoply.PolestarVoice.SYNC_POPUP or nil
PP.PINS = { "update.probe", "nav.shareTransit" }    -- the engine's settings held off, whatever the switch says
PP.QUIET = { "helloAt", "replyAt" }                 -- the engine's two guild times (when it last said hello, when it last answered one)
PP.FAR = 4102444800                                 -- Jan 1 2100: "it said hello a moment ago", for good
-- what this file calls of the engine's party table; a release without one of them leaves partner levelling off
PP.NEEDS = { "Members", "MyPos", "StepAt", "SharedSteps", "UnitInfo", "StepWait", "HoldsQuest", "GoOn", "RequestSync", "AcceptSync",
             "DeclineSync", "SyncOffer" }

-- the engine's own table (Engine/PolestarVoice.lua knows it by name)
local function P()
  local V = Panoply.PolestarVoice
  return V and V.P and V.P() or nil
end

-- the engine's party table when it has everything this file calls, else nil and the name of the first part that is missing
local function party()
  local p = P()
  local t = type(p) == "table" and p.Party or nil
  if type(t) ~= "table" then return nil, "Party" end
  for _, name in ipairs(PP.NEEDS) do
    if type(t[name]) ~= "function" then return nil, "Party." .. name end
  end
  return t
end
function PP:Missing() local _, why = party() return why end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then Panoply:Debug("partner call", a) return nil end
  return a, b, c
end

-- the partner line, the card or a waiting answer may have changed: the windows that draw them are told
local function changed()
  Panoply:Fire("SYNC_STATUS")
  Panoply:Fire("PARTNER_CHANGED")
end

-------------------------------------------------------------------------------
-- The switch and the pins
-------------------------------------------------------------------------------
-- on unless the player turned it off (a stored false; the default is Core/Init.lua's)
function PP:Wanted()
  local db = Panoply.db
  return not (db and db.partyShare == false)
end

-- a party, not a raid (the engine shares with a party only)
function PP:InParty()
  return C.InGroup() and not (_G.IsInRaid and IsInRaid()) and true or false
end

-- partner levelling is on and the engine can do it (the guide may still be off: playing along)
function PP:CanRun()
  return self:Wanted() and C.Flavor() == "forever" and party() ~= nil
end

function PP:Enabled()
  local PE = Panoply.PolestarEngine
  return self:CanRun() and PE ~= nil and PE:Active() and true or false
end

-- The engine's guild times held in the far future, so its version hello and its answer to one never go to the guild.
function PP:Quiet()
  local p = P()
  local U = type(p) == "table" and p.Update or nil
  if not (type(U) == "table" and type(U.State) == "function" and Panoply.db) then return false end
  local s = call(U.State)
  if type(s) ~= "table" then return false end
  local kept = Panoply.db.polestarQuiet
  if type(kept) ~= "table" then kept = {} Panoply.db.polestarQuiet = kept end
  for _, k in ipairs(self.QUIET) do
    if s[k] ~= self.FAR then
      if kept[k] == nil then
        if s[k] == nil then kept[k] = false else kept[k] = s[k] end   -- (false: the engine had none)
      end
      s[k] = self.FAR
    end
  end
  return true
end

-- The guild times as the engine had them (the settings are put back by the adapter's PS:Unmanage, which calls this first).
function PP:Unpin()
  local kept = Panoply.db and Panoply.db.polestarQuiet
  if type(kept) ~= "table" then return false end
  local p = P()
  local U = type(p) == "table" and p.Update or nil
  local s = type(U) == "table" and call(U.State) or nil
  if type(s) ~= "table" then return false end
  for _, k in ipairs(self.QUIET) do
    if kept[k] ~= nil and s[k] == self.FAR then
      if kept[k] == false then s[k] = nil else s[k] = kept[k] end
    end
  end
  Panoply.db.polestarQuiet = nil
  return true
end

-- At every login and when the switch changes (Engine/PolestarVoice.lua's ApplyParty, which the adapter runs with its other
-- settings, also when it does not drive this engine: what goes to other players must not depend on the adapter starting).
function PP:Apply()
  local PE = Panoply.PolestarEngine
  if not (PE and PE.CanSet and PE:CanSet() and P()) then return false end
  local want = self:Wanted()
  PE:Manage("party.share", want)
  PE:Manage("party.show", want)
  for _, path in ipairs(self.PINS) do PE:Manage(path, false) end
  self:Quiet()
  self:Hook()
  if not want then self.request, self.acceptQueued, self.following = nil, nil, nil end
  changed()
  return true
end

Panoply:Listen("OPTION_CHANGED", function(key) if key == "partyShare" then PP:Apply() end end)

-- a profile must never switch what is shared with other players on or off
if Panoply.Profiles and type(Panoply.Profiles.NOT_COVERED) == "table" then
  Panoply.Profiles.NOT_COVERED.partyShare = "what you share with other players is the account's own choice; a profile must never switch it on"
end

-------------------------------------------------------------------------------
-- The engine's sync question, seen and answered
-------------------------------------------------------------------------------
-- The engine asks with the game's own pop-up and keeps the request to itself; the pop-up is watched (hooksecurefunc, nothing of the
-- game's is replaced) so the same question can sit in Panoply's guide card. Either one answers it; the other then goes away.
function PP:OnPopup(which, text, data)
  if which == nil or which ~= self.POPUP or type(data) ~= "table" then return end
  self.request = { req = data, name = type(data.name) == "string" and data.name or "Your partner", text = type(text) == "string" and text or nil }
  self.acceptQueued = nil
  changed()
end

-- the engine's pop-up put away once the question is answered in Panoply's card (after a fight when in one)
function PP:HidePopup()
  local hide = _G.StaticPopup_Hide
  if type(hide) ~= "function" or not self.POPUP then return false end
  if C.InCombat() then self.hideQueued = true return false end
  self.hideQueued = nil
  local ok, err = pcall(hide, self.POPUP)
  if not ok then Panoply:Debug("partner popup", err) end
  return ok
end

-- the request was answered (in the card or in the engine's pop-up)
function PP:Answered(req)
  local r = self.request
  if not r or (req ~= nil and req ~= r.req) then return end
  self.request, self.acceptQueued = nil, nil
  self:HidePopup()
  changed()
end

function PP:Hook()
  local t = party()
  local p = P()
  if not t or self.hooked == t or type(_G.hooksecurefunc) ~= "function" then return false end
  self.hooked = t
  hooksecurefunc(t, "AcceptSync", function(req)
    local r = PP.request
    PP:Answered(req)
    -- yes was said in the engine's own pop-up (PP:Accept knows the answer itself): the guide is now the partner's
    if not PP.accepting and r and (req == nil or req == r.req) and PP:OnTheirGuide(r.req) then PP:Follow(r.name) end
  end)
  hooksecurefunc(t, "DeclineSync", function(req) PP:Answered(req) end)
  if type(p.On) == "function" then
    for _, msg in ipairs({ "PARTY_PROGRESS", "PARTY_LIVE" }) do p.On(msg, function() PP:Changed() end) end
  end
  return true
end

if type(_G.hooksecurefunc) == "function" and type(_G.StaticPopup_Show) == "function" then
  hooksecurefunc("StaticPopup_Show", function(which, text, _, data) PP:OnPopup(which, text, data) end)
end

-- the party's progress or the party itself changed (the engine's message): the windows that show it are told
PP.told = {}   -- the party members whose other version was said in chat this session
function PP:Changed()
  if self.request and not self:InParty() then self.request, self.acceptQueued = nil, nil end
  self:CheckFollowing()
  -- a party member on another version: said once per member in chat (the partner line keeps saying it)
  for _, row in ipairs(self:Partners()) do
    if row.otherVersion and not self.told[row.name] then
      self.told[row.name] = true
      Panoply:Print(self.OTHER_VERSION:format(row.name))
    end
  end
  local QP = Panoply.QuestParty
  if QP and QP.EngineChanged then QP:EngineChanged() end
  changed()
end

Panoply:On("PLAYER_REGEN_ENABLED", function()
  if PP.hideQueued then PP:HidePopup() end
  if PP.acceptQueued then
    PP.acceptQueued = nil
    PP:Accept()
  end
end)
Panoply:On("GROUP_ROSTER_UPDATE", function()
  if (PP.request and not PP:InParty()) or PP.following then PP:Changed() end
end)
-- the class-quest hold started, changed or ended (Engine/PartnerHold.lua): the card is another one now. Not while this file is
-- asking for the card itself (PP:Card): the window that asked is drawing it already.
Panoply:Listen("PARTNER_HOLD_CHANGED", function() if not PP.inCard then changed() end end)

-------------------------------------------------------------------------------
-- The partner
-------------------------------------------------------------------------------
-- the party members whose progress the engine has, as it keeps them (name, quests = { [questID] = { { have, need }, ... } })
function PP:Members()
  local t = self:Enabled() and party()
  if not t then return {} end
  return call(t.Members) or {}
end

local function isRelease(v) return type(v) == "string" and v:match("^%d+[%.%d]*$") ~= nil end

-- One row per party member the engine has heard: { name, level, class, xp, relation ("same", "ahead", "behind", "otherGuide" or nil
-- when it cannot be said), steps (ahead: above 0, behind: below 0; only steps you both have count), otherVersion }.
function PP:Partners()
  local out = {}
  local t = self:Enabled() and party()
  if not t then return out end
  local p = P()
  local E = p.Engine
  local mine = call(t.MyPos)
  local g = mine and mine.step and type(E) == "table" and call(E.GetGuide) or nil
  local me = type(p.Compat) == "table" and call(p.Compat.GetPlayerInfo) or {}
  for _, m in ipairs(call(t.Members) or {}) do
    local info = call(t.UnitInfo, nil, m.key) or {}
    local row = { name = m.name, level = info.level, class = info.class, xp = info.xp }
    local v = (m.unit and m.unit.version) or (m.pos and m.pos.addon)
    if isRelease(v) and isRelease(p.version) and v ~= p.version then row.otherVersion = true end
    local at, pos = m.at, m.pos
    local theirs = (at and at.guide) or (pos and pos.guide)
    if theirs == "" then theirs = nil end
    if theirs and mine and theirs ~= mine.guide then
      row.relation = "otherGuide"
    elseif g and at and at.guide == g.id then
      local i = call(t.StepAt, g, at.key)
      if i then
        local who = { class = info.class or me.class, race = info.race or me.race, faction = me.faction }
        local d = tonumber(call(t.SharedSteps, g, mine.step, i, who)) or 0
        row.steps = d
        row.relation = d == 0 and "same" or (d > 0 and "ahead" or "behind")
      end
    end
    out[#out + 1] = row
  end
  return out
end

-- Party members whose add-on spoke the old way (Engine/Sync.lua hears it and keeps the name): they cannot share a guide step.
function PP:Others()
  local out = {}
  local S = Panoply.Sync
  if not (self:Enabled() and S and S.OldClients) then return out end
  for _, o in ipairs(S:OldClients()) do out[#out + 1] = o end
  return out
end

PP.OTHER_GUIDE = "%s is on a different guide."
PP.OTHER_VERSION = "%s's Panoply Suite is a different version: your guides can differ."
PP.OTHER_GAME = "%s is not on WoW Forever, so you cannot share a guide."
PP.NOBODY = "No one else in your party has been seen with Panoply Suite yet."
PP.OLDER = "%s's Panoply Suite cannot share its guide step: it is older, or its guide is off."

local function rowText(row)
  local n = row.name
  local s
  if row.relation == "same" then s = n .. " is on your step."
  elseif row.relation == "ahead" then s = row.steps == 1 and (n .. " is 1 step ahead of you.") or ("%s is %d steps ahead of you."):format(n, row.steps)
  elseif row.relation == "behind" then s = row.steps == -1 and (n .. " is 1 step behind you.") or ("%s is %d steps behind you."):format(n, -row.steps)
  elseif row.relation == "otherGuide" then s = PP.OTHER_GUIDE:format(n)
  elseif row.level then s = ("%s (level %d) is leveling with you."):format(n, row.level)
  else s = n .. " is leveling with you." end
  if row.otherVersion then s = s .. " " .. PP.OTHER_VERSION:format(n) end
  return s
end

-- The lines that say why you and a party member cannot be in step: another guide, another version, not on WoW Forever.
function PP:Mismatches()
  local out = {}
  for _, row in ipairs(self:Partners()) do
    if row.relation == "otherGuide" then out[#out + 1] = self.OTHER_GUIDE:format(row.name) end
    if row.otherVersion then out[#out + 1] = self.OTHER_VERSION:format(row.name) end
  end
  for _, o in ipairs(self:Others()) do
    out[#out + 1] = (o.game and o.game ~= "forever" and self.OTHER_GAME or self.OLDER):format(o.name)
  end
  return out
end

-- One line about the partner for the guide window, or nil (off, solo, a raid, nobody heard). Second: false when nobody in the
-- party can be asked to sync (only add-ons that cannot share a guide step were heard), so "Sync to my step" is left out.
function PP:PartnerLine()
  if not (self:Enabled() and self:InParty()) then return nil end
  local parts, heard = {}, {}
  local canSync = false
  for _, row in ipairs(self:Partners()) do
    parts[#parts + 1] = rowText(row)
    heard[row.name] = true
    canSync = true
  end
  for _, o in ipairs(self:Others()) do
    if not heard[o.name] then parts[#parts + 1] = (o.game and o.game ~= "forever" and self.OTHER_GAME or self.OLDER):format(o.name) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, " "), canSync
end

-------------------------------------------------------------------------------
-- Following a partner's guide
-------------------------------------------------------------------------------
-- The engine's sync is one move to the partner's guide and step; that this character then follows that partner's guide is kept
-- here, for this session: { name }. It ends when another guide is picked (the picker calls EndSync), when the partner is no
-- longer in the party or is on another guide, and when Level together is turned off.

-- after an accepted request `req`: is this character on the guide the request was for, at a step it has?
function PP:OnTheirGuide(req)
  local t = party()
  local at = type(req) == "table" and req.at or nil
  local mine = t and call(t.MyPos)
  local p = P()
  local g = type(p) == "table" and type(p.Engine) == "table" and call(p.Engine.GetGuide) or nil
  if not (type(at) == "table" and mine and g and at.guide ~= nil and at.guide == mine.guide) then return false end
  return call(t.StepAt, g, at.key) ~= nil
end

function PP:Follow(name)
  if type(name) ~= "string" or name == "" then return false end
  self.following = { name = name }
  changed()
  return true
end

-- the partner left the party, or is on another guide now: this character follows nobody. True when that ended here.
function PP:CheckFollowing()
  local f = self.following
  if not f then return false end
  local gone = not (self:Enabled() and self:InParty())
  if not gone then
    local t = party()
    local inParty = false
    for _, row in ipairs(call(t.Roster) or {}) do if row.name == f.name then inParty = true break end end
    gone = not inParty
  end
  if not gone then
    for _, row in ipairs(self:Partners()) do
      if row.name == f.name and row.relation == "otherGuide" then gone = true break end
    end
  end
  if gone then self.following = nil end
  return gone
end

function PP:Following()
  local f = self.following
  if not (f and self:Enabled() and self:InParty()) then return nil end
  return f.name
end

-- why: "guide" (another guide was picked). Says nothing: the caller has the words. True when a sync was ended.
function PP:EndSync(why)
  if not self.following then return false end
  self.following = nil
  Panoply:Debug("partner sync ended", why)
  changed()
  return true
end

-- Short and long words for where partner levelling stands (the Partner page, /panoply sync; Engine/Sync.lua hands them on).
function PP:StatusText()
  if not self:Wanted() then return "Level together is off" end
  if not self:Enabled() then return "Level together needs the guide" end
  if not C.InGroup() then return "Solo" end
  if not self:InParty() then return "Level together pauses in a raid" end
  return self:PartnerLine() or "Waiting for your partner's Panoply Suite"
end

function PP:FriendlyStatus()
  if not self:Wanted() then return "Level together is off. Turn it on in Settings to level with a partner." end
  if not self:Enabled() then return "Level together needs Panoply Suite's guide, and the guide is off right now." end
  if not C.InGroup() then return "Not grouped. Invite your partner to level together." end
  if not self:InParty() then return "Level together works in a party, not in a raid." end
  return self:PartnerLine() or "In a group, but your partner hasn't been seen with Panoply Suite yet."
end

-------------------------------------------------------------------------------
-- The card and its buttons
-------------------------------------------------------------------------------
local function nameList(names)
  if #names == 1 then return names[1] end
  if #names == 2 then return names[1] .. " and " .. names[2] end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

local function plain(s)
  local V = Panoply.PolestarVoice
  if V and V.GuideText then s = V.GuideText(s) end
  if V and V.Text then s = V.Text(s) end
  return s
end

-- The partner's question "sync to my step?": what saying yes would do, in the engine's own words for the player's language.
function PP:SyncCard()
  local r = self.request
  local t = party()
  if not (r and t) then return nil end
  local card = { kind = "sync", who = r.name, partner = r.name, title = ("%s asks you to sync to their guide."):format(r.name), lines = {},
                 buttons = { { label = "Accept", tip = "Your guide goes to their guide and step. Your character is not moved.", action = "Accept", primary = true },
                             { label = "Decline", tip = "Your guide stays where it is.", action = "Decline" } } }
  local offer = call(t.SyncOffer, r.req.at, r.req.who)
  local text = offer and type(t.SyncPrompt) == "function" and call(t.SyncPrompt, r.name, offer) or r.text
  if type(text) == "string" then
    local first = true
    for line in (text .. "\n\n"):gmatch("(.-)\n\n") do
      if not first and line ~= "" then card.lines[#card.lines + 1] = plain(line) end   -- (the first line is the title)
      first = false
    end
  end
  if self.acceptQueued then card.lines[#card.lines + 1] = "You sync when the fight ends." end
  return card
end

-- The step waits for a party member who still needs it.
function PP:WaitCard()
  local t = party()
  if not t then return nil end
  local names = call(t.StepWait)
  if type(names) ~= "table" or #names == 0 then return nil end
  local who = nameList(names)
  return { kind = "wait", who = who, partner = #names == 1 and names[1] or nil, title = "Waiting for " .. who,
           lines = { ("%s still %s this step. Hand-ins wait until you are both done."):format(who, #names == 1 and "needs" or "need") },
           buttons = { { label = "Go on without them", tip = "Your guide goes on. They can catch up later.", action = "GoOn" } } }
end

function PP:Card()
  local hold = Panoply.PartnerHold
  if hold and hold.Card then
    self.inCard = true
    local ok, card = pcall(hold.Card, hold)
    self.inCard = nil
    if not ok then Panoply:Debug("partner call", card) card = nil end
    if card then return card end
  end
  if not (self:Enabled() and self:InParty()) then return nil end
  return self:SyncCard() or self:WaitCard()
end

-- "Sync to my step": asks the party; each of them chooses. The engine says in chat what happened.
function PP:RequestSync()
  local t = self:Enabled() and party()
  if not t then return false end
  if call(t.RequestSync) == true then return true end
  -- nobody in the party has been heard (the engine's own line for that names the engine and is not said: Engine/PolestarVoice.lua)
  if self:InParty() and type(t.Roster) == "function" and #(call(t.Roster) or {}) == 0 then Panoply:Print(self.NOBODY) end
  return false
end

-- Yes to the partner's question. The guide's place moves (never the character); in a fight it waits until the fight ends.
function PP:Accept()
  local t = self:Enabled() and party()
  local r = self.request
  if not (t and r) then return false end
  if C.InCombat() then
    self.acceptQueued = true
    changed()
    return true
  end
  self.accepting = true
  local did = call(t.AcceptSync, r.req) == true
  self.accepting = nil
  if self.request == r then self:Answered(r.req) end   -- (the engine no longer held this request)
  if did then self:Follow(r.name) end
  return did
end

function PP:Decline()
  local t = self:Enabled() and party()
  local r = self.request
  if not (t and r) then return false end
  local did = call(t.DeclineSync, r.req) == true
  if self.request == r then self:Answered(r.req) end
  return did
end

-- "Go on without them": the class-quest hold when there is one (PartnerHold), else the step's wait for the party.
function PP:GoOn()
  local hold = Panoply.PartnerHold
  if hold and hold.Holding and hold:Holding() then return hold:Release() == true end
  local t = self:Enabled() and party()
  if not t then return false end
  local names = call(t.StepWait)
  if type(names) ~= "table" or #names == 0 then return false end
  local ok, err = pcall(t.GoOn)
  if not ok then Panoply:Debug("partner call", err) return false end
  changed()
  return true
end

-- The hold card's "Help <name>" (the arrow points at the partner; it never moves the character) and "Stop helping".
function PP:Help()
  local hold = Panoply.PartnerHold
  return hold ~= nil and hold.Help ~= nil and hold:Help() == true
end
function PP:StopHelp()
  local hold = Panoply.PartnerHold
  return hold ~= nil and hold.StopHelp ~= nil and hold:StopHelp() == true
end

-- Does a hand-in of quest q wait for the party? true and the names of who still needs it (Engine/Automation.lua asks).
function PP:Waiting(q)
  q = tonumber(q)
  local t = q and self:CanRun() and party()
  if not t then return false end
  if call(t.HoldsQuest, q) ~= true then return false end
  local names = {}
  for _, m in ipairs(call(t.Members) or {}) do
    local counts = type(m.quests) == "table" and m.quests[q]
    if type(counts) == "table" then
      for _, c in ipairs(counts) do
        if type(c) == "table" and (tonumber(c[1]) or 0) < (tonumber(c[2]) or 0) then names[#names + 1] = m.name break end
      end
    end
  end
  return true, names
end
PP.NameList = nameList
