-- Panoply Suite group sync (SPEC section 10): two partners share one plan and wait for each other.
-- Addon messages only to the party, own chunking, throttled queue, pauses in dungeons/lockdown.
-- 0.7.3.2 (re-planning in a party made it hard for two partners to get back in step): the route
-- leader is the party leader (the crown); only the leader's route is adopted; a route mismatch repairs
-- itself (leader sends, follower asks, both throttled); a follower's re-plan is a request to the leader;
-- the partner and the shared route are remembered per character so a log-off and log-in rejoins it.
local ADDON, Panoply = ...
local S = { partners = {}, queue = {}, inbox = {}, msgId = 0, tokens = 10, paused = nil, handlers = {}, repair = {} }
Panoply.Sync = S
local C, U = Panoply.Compat, Panoply.Util

S.MAX_MSG = 255
S.HEADER_MAX = 16
S.BURST = 10
S.REFILL = 1          -- messages per second (client allows ~1/s after a 10 burst)
S.PARTNER_TIMEOUT = 90
S.REASSEMBLY_TIMEOUT = 30
-- 2 (0.7.3.2): flights/inns/item-started quests and expected levels travel with a plan; hello/state say whether the
-- sender shares routes (sh) and is playing along (pa); route requests (R) are answered (K).
S.VERSION = 2
S.MAX_RESENDS = 3          -- a leader sends the same route to the same partner on its own at most this many times
S.REPLAN_WAIT = 15         -- seconds a follower waits for an answer to "please re-plan" before planning for itself
S.REPLAN_ACKED_WAIT = 60   -- ... once the leader has said it is on it (the route then also takes a while to send)
S.REPAIR_GAP = 10          -- seconds between repeats of one repair message (send my route / ask for theirs) per partner
S.REPAIR_MAX = 120         -- the gap doubles while the partner's route stays different, up to this
S.REPLAN_ASK_GAP = 10      -- seconds: one "please re-plan" request, and one answered re-plan, per this long
S.LOGIN_GRACE = 15         -- seconds after login that a saved partner in the group is waited for before the first message

-------------------------------------------------------------------------------
-- Encoding: <type><id>:<seq>/<total>:<payload chunk>
-------------------------------------------------------------------------------
local function b36(n)
  local d = "0123456789abcdefghijklmnopqrstuvwxyz"
  local s = ""
  repeat local r = n % 36; s = d:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) until n == 0
  return s
end

function S.Encode(kind, payload, id)
  local body = U.Escape(U.Serialize(payload))
  local room = S.MAX_MSG - S.HEADER_MAX
  local total = math.max(1, math.ceil(#body / room))
  local out = {}
  for i = 1, total do
    out[i] = kind .. id .. ":" .. i .. "/" .. total .. ":" .. body:sub((i - 1) * room + 1, i * room)
  end
  return out
end

-- Feed one received message; returns kind, payload when a message is complete.
function S:Receive(sender, msg, now)
  local kind, id, seq, total, chunk = msg:match("^(%a)(%w+):(%d+)/(%d+):(.*)$")
  if not kind then return nil end
  seq, total = tonumber(seq), tonumber(total)
  if total > 200 or seq < 1 or seq > total then return nil end
  local key = sender .. "|" .. kind .. id
  local box = self.inbox[key]
  if not box then box = { parts = {}, n = 0, total = total, t = now or 0, kind = kind, who = (sender:match("^([^%-]+)") or sender) }; self.inbox[key] = box end
  box.t = now or box.t   -- 0.7.3.2: a long plan (dozens of chunks at 1 message a second) times out only when chunks stop coming
  if not box.parts[seq] then box.parts[seq] = chunk; box.n = box.n + 1 end
  if box.n < box.total then return nil end
  self.inbox[key] = nil
  local ok, value = U.Deserialize(U.Unescape(table.concat(box.parts)))
  if not ok then return nil end
  return kind, value
end

-------------------------------------------------------------------------------
-- Sending (queued + throttled)
-------------------------------------------------------------------------------
-- WoW Forever with Polestar's engine (Engine/PolestarEngine.lua): the steps are Polestar's and it moves the guide on itself, so our
-- step-by-step partner sync (shared route, waiting for each other) has nothing to hold on to. It is off there.
-- 0.9.7 (WoW Forever only): leveling with a partner is the engine's own party sync, drawn and switched by Engine/PolestarParty.lua.
-- This file's route sharing is no bridge to it and no second way to level together: with the engine's guide on it sends nothing,
-- and what it says about the partner (StatusText, FriendlyStatus) is PolestarParty's words. It only listens for a party member whose
-- add-on still speaks this old way, so the partner line can say why the two of you cannot share a step (S:OldClients).
-- "Share with my party" off (PanoplySuiteDB.partyShare) switches this file off as well: nothing is sent to the party at all.
local function polestar() local PE = Panoply.PolestarEngine return PE ~= nil and PE:Active() end
local function shareOff() return Panoply.db ~= nil and Panoply.db.partyShare == false end
function S:Enabled() return (not Panoply.db or Panoply.db.syncEnabled ~= false) and not shareOff() and not polestar() end

function S:PausedReason()
  if polestar() then return "polestar" end
  -- Midnight rules (Forever) block addon messages in instances. Classic Era has no such rule.
  local inInst, kind = C.InInstance()
  if C.Features().restrictions and inInst and (kind == "party" or kind == "raid" or kind == "scenario") then return "dungeon" end
  if self.paused and self.paused > C.GetTime() then return "lockdown" end
  return nil
end

function S:Queue(kind, payload)
  if not self:Enabled() then return false end
  local channel = C.GroupChannel()
  if not channel then return false end
  self.msgId = (self.msgId + 1) % 1296
  for _, m in ipairs(S.Encode(kind, payload, b36(self.msgId))) do
    self.queue[#self.queue + 1] = { msg = m, channel = channel }
  end
  self:Pump()
  return true
end

function S:Pump(dt)
  local now = C.GetTime()
  if self.lastPump then self.tokens = math.min(S.BURST, self.tokens + (now - self.lastPump) * S.REFILL) end
  self.lastPump = now
  if self:PausedReason() then return end
  -- keep two tokens spare for other addons
  while #self.queue > 0 and self.tokens >= 3 do
    local q = table.remove(self.queue, 1)
    local ok, why = C.Send(Panoply.prefix, q.msg, q.channel)
    if not ok and why == "lockdown" then
      self.paused = now + 30
      self.queue = {}
      Panoply:Fire("SYNC_STATUS")
      return
    elseif not ok and why == "throttled" then
      table.insert(self.queue, 1, q)
      self.tokens = 0
      return
    end
    self.tokens = self.tokens - 1
  end
end

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------
function S:MyState()
  local E = Panoply.Engine
  -- 0.5.7: "ready" is whether our current step is finished, not E.waiting. ClearToAdvance sends
  -- this state before the engine sets E.waiting, so the old check told the partner "not ready"
  -- and both players then waited on each other for good.
  local ready = E.waiting or (E.steps[E.index] and E:IsComplete(E.index))
  local st = { v = S.VERSION, lvl = Panoply.State.level, i = E.index, h = Panoply.Planner.hash, r = ready and E.index or nil,
           m = Panoply.State.pos and Panoply.State.pos.map, g = C.Flavor() }
  if Panoply:NoGuideHere() then st.h, st.r, st.ng = nil, nil, 1 end   -- 0.7.4.1: an area without a guide shares no route (the partner stops sending one)
  st.sh = self:Shares() and 1 or 0   -- 0.7.3.2: "Share one route" off: the partner must not wait for our routes
  -- Nov 11 2026: where we are on the route, for the partner who follows to see whether the two of you are in step: the quests of
  -- the step we stand on (gq), and on a written guide which guide and which of its steps (gd, gs; Engine/Guides.lua)
  if not st.pa and not st.ng then
    local cur = E.steps[E.index]
    if cur then
      local qs = {}
      for q in pairs(S.StepQuests(cur)) do if #qs < S.MAX_STEP_QUESTS then qs[#qs + 1] = q end end
      table.sort(qs)
      if #qs > 0 then st.gq = table.concat(qs, ",") end
      local saved = Panoply.cdb and Panoply.cdb.plan
      if cur.fromGuide and saved and saved.source == "guides" and cur.guideID == saved.guide then st.gd, st.gs = cur.guideID, cur.guideStep end
    end
  end

  -- Professions: "Mining=112/150;Blacksmithing=98/150" plus the profession step headline.
  local profs = {}
  local PD, PR = Panoply.ProfData, Panoply.Professions
  for _, n in ipairs(PD.ORDER) do
    local r, mx = PR:CurrentSkill(n)
    if r and (mx or 0) > 0 then profs[#profs + 1] = ("%s=%d/%d"):format(n, r, mx) end
  end
  st.pr = table.concat(profs, ";")
  local G = Panoply.ProfGuide
  local cur = G and G.current
  if cur then st.ps = Panoply.StepText.Headline(cur):sub(1, 100); st.pt = G.tracked end
  return st
end

function S.ParseProfs(s)
  local out = {}
  for name, r, mx in tostring(s or ""):gmatch("([^=;]+)=(%d+)/(%d+)") do out[#out + 1] = { name = name, rank = tonumber(r), max = tonumber(mx) } end
  return out
end

function S:SendHello() return self:Queue("H", self:MyState()) end
function S:SendState()
  local now = C.GetTime()
  if self.lastState and now - self.lastState < 2 then self.stateDirty = true return end
  self.lastState = now
  self.stateDirty = nil
  return self:Queue("S", self:MyState())
end
-- True while chunks of one of our plans are still waiting in the send queue.
function S:PlanQueued()
  for _, q in ipairs(self.queue) do if q.msg:sub(1, 1) == "P" then return true end end
  return false
end

function S:SendPlan()
  local P = Panoply.Planner
  if Panoply:PlayAlong() or not P.actions or #P.actions == 0 then return false end
  -- a newer route replaces plan chunks still waiting to go out
  for i = #self.queue, 1, -1 do if self.queue[i].msg:sub(1, 1) == "P" then table.remove(self.queue, i) end end
  local compact = {}
  for i, a in ipairs(P.actions) do
    -- every field the planner emits travels: t, q / lvl, m, x, y, n, o, node / bind, i (quest started by an item), lv (expected level)
    compact[i] = { a.t, a.q or a.lvl or 0, a.m or 0, a.x and math.floor(a.x * 10000 + 0.5) or 0, a.y and math.floor(a.y * 10000 + 0.5) or 0,
                   a.n or 0, a.o or 0, a.node or a.bind or 0, a.i or 0, a.lv or 0 }
  end
  -- k: what kind of route this is. Nov 11 2026: a partner takes on only a Panoply Hub plan this way ("hub"; a plan of ours from Panoply
  -- Hub, or one a leader shared with us); a planner route (an older Panoply Suite's) is not a leveling route any more
  local saved = Panoply.cdb and Panoply.cdb.plan
  local kind = saved and (saved.source == "hub" or saved.sharedKind == "hub") and "hub" or nil
  return self:Queue("P", { h = P.hash, title = Panoply.Engine.title, a = compact, g = C.Flavor(), k = kind })
end
function S:AskPlan() return self:Queue("A", { h = Panoply.Planner.hash }) end

function S.ExpandActions(compact)
  local out = {}
  for i, c in ipairs(compact or {}) do
    local a = { t = c[1] }
    -- 0.7.3.2: flight (f) and inn (b) actions carry no quest: 0 means "none", not quest 0. Reading it as quest 0
    -- gave the follower a different route hash ("f0" for "f"), so a route with a flight or an inn never matched
    -- and was adopted again and again. Their flight-master / inn name (c[8]) is carried too.
    if a.t == "g" then a.lvl = c[2] elseif c[2] ~= 0 then a.q = c[2] end
    if c[8] ~= nil and c[8] ~= 0 then if a.t == "f" then a.node = c[8] elseif a.t == "b" then a.bind = c[8] end end
    if c[3] ~= 0 then a.m = c[3]; a.x = c[4] / 10000; a.y = c[5] / 10000 end
    if c[6] ~= 0 then a.n = c[6] end
    if c[7] ~= 0 then a.o = c[7] end
    if c[9] ~= nil and c[9] ~= 0 then a.i = c[9] end    -- 0.7.3.2: the quest starts from an item ("Read <item>"), not from a giver
    if c[10] ~= nil and c[10] ~= 0 then a.lv = c[10] end -- the level the route expects here (drift check after a crown change)
    out[i] = a
  end
  return out
end

local function shortName(n) return n and (n:match("^([^%-]+)") or n) or n end

-- open = a message kind any party member may send (S.openKinds, e.g. "Q" quest progress), not
-- only the chosen sync partner. Your own messages are never accepted.
function S:Accepts(sender, open)
  local partner = Panoply.db and Panoply.db.syncPartner
  if not open and partner and partner ~= "" and shortName(partner):lower() ~= shortName(sender):lower() then return false end
  local me = C.PlayerInfo().name
  if me and shortName(sender) == me then return false end
  return true
end
S.openKinds = S.openKinds or {}

-- 0.9.7: a party member whose add-on speaks this file's old messages while the engine's guide is on here: their hello or state is
-- read for one thing only, who they are and which game they say they are on. Nothing is answered and nothing of theirs is taken on.
S.old = {}
function S:OnOldClient(msg, channel, sender)
  if channel ~= "PARTY" or shareOff() then return false end
  local me = C.PlayerInfo().name
  local who = sender:match("^([^%-%s]+)") or sender   -- (WoW Forever's names carry a surname: the first name is the one kept)
  if me and who == me then return false end
  local kind, p = self:Receive(sender, msg, C.GetTime())
  if not (kind == "H" or kind == "S") or type(p) ~= "table" then return false end
  local o = self.old[who]
  local game = type(p.g) == "string" and p.g or nil
  if not o or o.game ~= game then
    self.old[who] = { name = who, game = game, seen = C.GetTime() }
    Panoply:Fire("SYNC_STATUS")
  else
    o.seen = C.GetTime()
  end
  return true
end
-- The party members heard that way who are in the party now: { { name, game }, ... } by name.
function S:OldClients()
  local out, members = {}, {}
  for _, n in ipairs(C.GroupMembers()) do members[n:match("^([^%-%s]+)") or n] = true end
  for who, o in pairs(self.old) do
    if members[who] then out[#out + 1] = o else self.old[who] = nil end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function S:OnMessage(prefix, msg, channel, sender)
  if prefix == Panoply.prefix and sender and type(msg) == "string" and polestar() then return self:OnOldClient(msg, channel, sender) end
  if prefix ~= Panoply.prefix or not self:Enabled() or not sender or type(msg) ~= "string" then return end
  local open = self.openKinds[msg:sub(1, 1)] and true or false
  if not self:Accepts(sender, open) then return end
  local kind, p = self:Receive(sender, msg, C.GetTime())
  if not kind or type(p) ~= "table" then return end
  local who = shortName(sender)
  -- open kinds go straight to their module; they do not make the sender your sync partner
  if open then
    local h = self.handlers[kind]
    if h then local ok, err = pcall(h, who, p) if not ok then Panoply:Debug("sync handler", kind, err) end end
    return
  end
  local st = self.partners[who] or {}
  self.partners[who] = st
  st.seen = C.GetTime()
  if kind == "H" or kind == "S" then
    local oldLevel = st.level
    st.level, st.index, st.hash, st.ready, st.map, st.game, st.playAlong = p.lvl, p.i, p.h, p.r, p.m, p.g, p.pa and true or nil
    st.version, st.shares = tonumber(p.v) or 1, p.sh ~= 0
    st.guide, st.guideStep = type(p.gd) == "string" and p.gd or nil, tonumber(p.gs)   -- Nov 11 2026: the written guide they are on
    st.quests = S.ParseQuests(p.gq)
    st.noGuide = p.ng and true or nil   -- 0.7.4.1: the partner stands where there is no guide: no route is sent or wanted   -- 0.7.3.2: what the partner's Panoply Suite can do (older builds send no sh)
    -- 0.5.8: the lower partner's level decides what is too hard; their level-up can bring quests back
    if oldLevel and p.lvl and p.lvl > oldLevel and Panoply.ReviewDeferred then
      local okR, err = pcall(Panoply.ReviewDeferred, Panoply, "level up")
      if not okR then Panoply:Debug("review deferred", err) end
    end
    st.profs, st.profStep, st.profTracked = S.ParseProfs(p.pr), p.ps, p.pt
    if kind == "H" then self:SendState() end
    self:CheckRoute(who, st)
  elseif kind == "P" then
    st.hash = p.h
    if self.asked and self.asked.leader == who then self.asked = nil end   -- the leader answered the request for a new route
    -- 0.5.7: remember which quests the partner's route uses (Replan never drops those)
    st.planHash, st.planSet = p.h, {}
    for _, c in ipairs(p.a or {}) do if c[1] ~= "g" and type(c[2]) == "number" and c[2] > 0 then st.planSet[c[2]] = true end end
    -- Plans hold map coordinates, which differ between Era and Forever for some zones.
    if p.g and p.g ~= C.Flavor() then Panoply:Debug("ignored plan from other game", p.g) return end
    -- 0.7.3.2: only the route leader's route is taken on, unless we have no route at all
    local hasRoute = Panoply.Planner.hash ~= nil and Panoply.Planner.actions and #Panoply.Planner.actions > 0
    local leader = self:LeaderOf(who)
    -- Nov 11 2026 ("turn planner off."; "the second player in the level together should get the party leaders if they are in
    -- sync. if not they keep their own."): only a Panoply Hub plan is taken on this way (a written guide travels in the state message,
    -- S:FollowGuide), only from the party leader, and only while the two of you are in step (or this side has no route at all)
    local plannerOn = Panoply.Guides.PlannerOn()
    local takes = plannerOn or (p.k == "hub" and leader == who and (self:InSync(st) or #Panoply.Engine.steps == 0))
    if not plannerOn and not takes then
      if p.h ~= Panoply.Planner.hash then Panoply:Debug("ignored plan from", who, p.k == "hub" and "(not in step)" or "(not a route to share)") end
    elseif Panoply:NoGuideHere() then
      -- 0.7.4.1: no route is taken on here. Say nothing (it was "Using the plan shared by..." though nothing was adopted) and do not mark it
      -- bad: it is asked for again when we leave the area (NoGuide:Resume)
      Panoply:Debug("ignored plan from", who, "(no guide for this area)")
    elseif p.h ~= Panoply.Planner.hash and self:Shares() and not Panoply:PlayAlong() and (leader == who or not hasRoute) then
      -- the route we last shared with this partner: keep our own step in it (log-off, log-in, a lone re-plan in between)
      local saved = Panoply.cdb and Panoply.cdb.partner
      local keep = false
      if saved and saved.hash == p.h and saved.index then Panoply.Engine.index = saved.index; keep = true end
      Panoply.Planner:Adopt(S.ExpandActions(p.a), (p.title or "Shared plan") .. " (from " .. who .. ")", "partner", keep)
      if Panoply.Planner.hash ~= p.h then st.badHash = p.h end   -- never ask for this same route again
      if p.k == "hub" and Panoply.cdb and Panoply.cdb.plan and Panoply.cdb.plan.source == "partner" then Panoply.cdb.plan.sharedKind, Panoply.cdb.plan.sharedBy = "hub", who end
      Panoply:Print("Using the plan shared by " .. who .. ".")
      self:SendState()
    elseif p.h ~= Panoply.Planner.hash then
      Panoply:Debug("ignored plan from", who, "(not the route leader)")
    end
  elseif kind == "A" then
    self:SendPlanTo(who, false)
  elseif kind == "R" then
    self:OnReplanRequest(who)
  elseif kind == "K" then
    self:OnReplanAnswer(who, p)
  elseif self.handlers[kind] then
    -- Module messages (for example "G" = a gathered node from the Gathering module).
    local ok, err = pcall(self.handlers[kind], who, p)
    if not ok then Panoply:Debug("sync handler", kind, err) end
  end
  Panoply:Fire("SYNC_STATUS")
  if Panoply.Engine.waiting then Panoply.Engine:Check() end
end

-------------------------------------------------------------------------------
-- Partner queries
-------------------------------------------------------------------------------
function S:ActivePartner()
  local now = C.GetTime()
  local members = {}
  for _, n in ipairs(C.GroupMembers()) do members[shortName(n)] = true end
  for name, st in pairs(self.partners) do
    if members[name] and st.seen and now - st.seen < S.PARTNER_TIMEOUT then return name, st end
  end
  return nil
end

function S:PartnerLevel()
  local _, st = self:ActivePartner()
  return st and st.level or nil
end

-- Wait-for-partner gate used by the step engine.
function S:ClearToAdvance(index)
  if not Panoply.db or not Panoply.db.syncWaitForPartner or not self:Enabled() then return true end
  if self:PausedReason() then return true end
  local _, st = self:ActivePartner()
  if not st then
    -- 0.7.3.2: just logged in, and the partner we shared a route with is in the group: give their first message a moment
    local waited = self:AwaitedPartner()
    if waited and self.loginAt and C.GetTime() - self.loginAt < S.LOGIN_GRACE and Panoply.cdb.partner.hash == Panoply.Planner.hash then
      if self.lastReady ~= index then self.lastReady = index; self:SendState() end
      return false
    end
    return true
  end
  if not st.hash or st.hash ~= Panoply.Planner.hash then return true end
  if (st.index or 0) > index then return true end
  if st.ready and st.ready >= index then return true end
  -- Tell the partner we are ready on this step, then wait.
  if self.lastReady ~= index then self.lastReady = index; self:SendState() end
  return false
end

function S:StatusText()
  local why = self:PausedReason()
  if why == "polestar" then   -- 0.9.7: partner leveling is the engine's party sync (Engine/PolestarParty.lua)
    local PP = Panoply.PolestarParty
    return PP and PP.StatusText and PP:StatusText() or "Sync off"
  end
  if not self:Enabled() then return "Sync off" end
  if why == "dungeon" then return "Sync paused (dungeon)" end
  if why == "lockdown" then return "Sync paused" end
  local name, st = self:ActivePartner()
  if not name then
    local saved = self:AwaitedPartner()
    if saved then return "Waiting for " .. saved .. "'s Panoply Suite" end
    return C.InGroup() and "Waiting for partner's Panoply Suite" or "Solo"
  end
  local same = self:SameRoute(st)
  return ("%s L%s - step %s%s"):format(name, st.level or "?", st.index or "?", same and "" or " (different plan)")
end

S.READY_RESEND = 15   -- seconds: while waiting, repeat "I'm ready" so one lost message can't stall both of you

function S:Tick()
  self:Pump()
  local now = C.GetTime()
  if self.stateDirty then self:SendState()
  elseif Panoply.Engine and Panoply.Engine.waiting and self:ActivePartner() and now - (self.lastState or 0) >= S.READY_RESEND then self:SendState() end
  for k, box in pairs(self.inbox) do if now - (box.t or 0) > S.REASSEMBLY_TIMEOUT then self.inbox[k] = nil end end
  -- 0.7.3.2: a partner who left the group is forgotten (nothing of the old pair goes to a new party)
  if next(self.partners) then self:PruneLeft() end
  -- 0.7.3.2: a lost repair message must not leave two routes apart: look again (the spacing rules keep it quiet)
  if #self.queue == 0 then
    for who, st in pairs(self.partners) do
      if st.seen and now - st.seen < S.PARTNER_TIMEOUT and st.hash ~= Panoply.Planner.hash then self:CheckRoute(who, st) end
    end
  end
  self:CheckAsked()
end

-- Forget partners who are no longer in the group, and any route traffic still queued for them.
function S:PruneLeft()
  local members = {}
  for _, n in ipairs(C.GroupMembers()) do members[shortName(n)] = true end
  local left = false
  for who in pairs(self.partners) do
    if not members[who] then self.partners[who] = nil; self.repair[who] = nil; left = true end
  end
  for who in pairs(self.repair) do if not members[who] then self.repair[who] = nil end end
  if self.asked and not members[self.asked.leader] then self.asked = nil end
  if left then
    for i = #self.queue, 1, -1 do
      local k = self.queue[i].msg:sub(1, 1)
      if k == "P" or k == "A" or k == "R" or k == "K" then table.remove(self.queue, i) end
    end
    Panoply:Fire("SYNC_STATUS")
  end
  return left
end

-------------------------------------------------------------------------------
-- 0.7.3.2 route leader and self-repair
-------------------------------------------------------------------------------
-- "Share one route" on: one of you leads, the other follows. Off: nobody follows anybody.
function S:Shares() return not Panoply.db or Panoply.db.syncAdoptPartnerPlan ~= false end

-- The one place that decides who leads the shared route between me and the partner `who` (short name):
-- the party leader (the crown) when it is one of us two; otherwise (a third player has it, or the game
-- cannot say) the name that sorts first, as before 0.7.3.2. Returns name, isMe, how ("crown" or "name").
function S:LeaderOf(who)
  local me = (C.PlayerInfo() or {}).name or "You"
  if not self:Shares() then return me, true, "name" end
  local crown, crownIsMe = C.GroupLeader()
  if crownIsMe then return me, true, "crown" end
  if crown and shortName(crown) == who then return who, false, "crown" end
  if who < me then return who, false, "name" end
  return me, true, "name"
end

-- Who leads the shared plan right now (name, isMe, how); nil when no partner is connected.
function S:Leader()
  local name = self:ActivePartner()
  if not name then return nil end
  return self:LeaderOf(name)
end

-- Can this partner's Panoply Suite serve a shared route (answer "please re-plan", send its plan, be followed)?
-- No when it is an older build (0.7.3.1 and before: no route requests, a plan decoder that never matches),
-- when it is playing along, or when it has "Share one route" off. Returns true, or false and a short reason.
-- A partner whose messages carry no version at all (a hand-made table in a test) counts as current.
function S:Serves(st)
  if not st then return false, "unknown" end
  if st.playAlong then return false, "playalong" end
  if st.noGuide then return false, "noguide" end
  if st.shares == false then return false, "off" end
  if (st.version or S.VERSION) < 2 then return false, "older" end
  return true
end

-- True when a connected partner leads AND can serve, so this player follows their route. A crown holder who
-- cannot serve (older build, playing along, sharing off) leaves you planning for yourself: otherwise nobody
-- would ever re-plan.
function S:IsFollower()
  local name, st = self:ActivePartner()
  if not name or not self:Shares() then return false end
  local _, isMe = self:LeaderOf(name)
  if isMe then return false end
  return (self:Serves(st))
end

-- Allow one repair message of this kind to this partner now? Repeats are spaced S.REPAIR_GAP apart and the
-- gap doubles each time (up to S.REPAIR_MAX) while the routes stay different, so nothing can spam the channel.
function S:Allow(who, what)
  local now = C.GetTime()
  local r = self.repair[who]
  if not r then r = {}; self.repair[who] = r end
  local x = r[what]
  if not x then x = { at = -1000000, gap = S.REPAIR_GAP }; r[what] = x end
  if now - x.at < x.gap then return false end
  if x.at > -1000000 then x.gap = math.min(x.gap * 2, S.REPAIR_MAX) end
  x.at = now
  return true
end

-- proactive = our own repair (not an answer to the partner's ask): capped, and never to an older build
function S:SendPlanTo(who, proactive)
  if self:PlanQueued() then return false end
  local st = self.partners[who]
  if proactive and st then
    if not self:Serves(st) then return false end   -- an older build adopts every plan again and jumps to step 1
    local x = st.sent
    if not x or x.hash ~= Panoply.Planner.hash then x = { hash = Panoply.Planner.hash, n = 0 }; st.sent = x end
    if x.n >= S.MAX_RESENDS then return false end   -- three tries; a partner still on another route after that is not helped by a fourth
  end
  if not self:Allow(who, "send") then return false end
  if proactive and st then st.sent.n = st.sent.n + 1 end
  local before = #self.queue
  local ok = self:SendPlan()
  -- a long plan takes about a second a chunk to go out: count the spacing from when it has finished sending
  if ok then self.repair[who].send.at = C.GetTime() + math.max(0, #self.queue - before) end
  return ok
end

-- A route this player just made: share it, unless a connected partner leads (then theirs is the shared one).
function S:SharePlan()
  if self:IsFollower() then return false end
  return self:SendPlan()
end

function S:AskPlanFrom(who)
  if self:Receiving(who) or not self:Allow(who, "ask") then return false end
  return self:AskPlan()
end

-- Is a plan from this partner arriving right now (chunks still coming in)?
function S:Receiving(who)
  local now = C.GetTime()
  for _, box in pairs(self.inbox) do
    if box.kind == "P" and box.who == who and now - (box.t or 0) < S.REASSEMBLY_TIMEOUT then return true end
  end
  return false
end

-- A partner's hello or state shows which route they are on. Same route: remember it. Different: the leader
-- sends theirs and the follower asks for it (a partner with no route at all gets ours, whoever leads).
function S:CheckRoute(who, st)
  if Panoply:PlayAlong() or not self:Shares() then return end
  if not Panoply.Guides.PlannerOn() then return self:CheckShared(who, st) end   -- Nov 11 2026
  if Panoply:NoGuideHere() then return end   -- 0.7.4.1: we stand where there is no guide: no route is asked for or sent (NoGuide:Resume asks again on leaving)
  if st.game and st.game ~= C.Flavor() then return end   -- plans from the other game are never shared
  if st.playAlong or st.shares == false then return end   -- they are playing along / do not share: no route wanted
  if st.noGuide then return end   -- 0.7.4.1: they stand in an area without a guide: nothing is sent or asked until they leave it
  local mine = Panoply.Planner.hash
  if st.hash == mine then
    if mine then self:NoteShared(who) end
    local r = self.repair[who]
    if r then r.send, r.ask = nil, nil end   -- (the "Already asked" timer for a re-plan request stays)
    st.sent = nil
    return
  end
  if not mine then
    if st.hash and st.hash ~= st.badHash then self:AskPlanFrom(who) end
    return
  end
  if not st.hash then self:SendPlanTo(who, true) return end
  local _, isMe = self:LeaderOf(who)
  if isMe then self:SendPlanTo(who, true)
  elseif st.hash ~= st.badHash and self:Serves(st) then self:AskPlanFrom(who) end
end

-------------------------------------------------------------------------------
-- Nov 11 2026: "the second player in the level together should get the party leaders if they are in sync. if not they keep
-- their own." With the planner off (Engine/Planner.lua), the party leader's route is a written guide (or a Panoply Hub plan). The leader's
-- state message says which guide and which of its steps they stand on, and the quests of that step; the partner who follows decides:
--   in step   = the same step (the same guide, the same guide step), or the same quests (a quest of the leader's step is a quest of
--               ours: of the step we stand on, or in our quest log). Also: we have no route at all.
--   in step:  we follow the leader's guide (Guides:Start takes it, at the leader's step; once on it we keep our own place in it).
--   not:      we keep our own written guide, from our own quest log and handed-in quests. Nobody is ever put on the planner.
-- "Share one route" off on either side: nobody follows anybody, as before.
-------------------------------------------------------------------------------
S.MAX_STEP_QUESTS = 12
local QUEST_GOAL = { accept = true, turnin = true, complete = true, objective = true }
-- the quests a step is about (its accept, hand-in, complete and objective goals), as a set
function S.StepQuests(step)
  local out = {}
  for _, g in ipairs(step and step.goals or {}) do
    if g.questID and QUEST_GOAL[g.type] then out[g.questID] = true end
  end
  return out
end
function S.ParseQuests(text)
  local out, any = {}, false
  for n in tostring(text or ""):gmatch("%d+") do out[tonumber(n)] = true any = true end
  return any and out or nil
end
-- Are we in step with this partner's route (st: their last state)? See above.
function S:InSync(st)
  if not st then return false end
  local E = Panoply.Engine
  local mine = E.steps[E.index]
  if not mine then return Panoply.cdb ~= nil and Panoply.cdb.setupDone == true and #E.steps == 0 and not Panoply:NoGuideHere() end
  if st.guide and mine.fromGuide and mine.guideID == st.guide and st.guideStep and mine.guideStep == st.guideStep then return true end
  if st.quests then
    local log = Panoply.State and Panoply.State.log or {}
    local ours = S.StepQuests(mine)
    for q in pairs(st.quests) do if ours[q] or log[q] then return true end end
  end
  return false
end
-- The party leader's written guide, when we follow them and are in step: { guide = id, at = guide step, leader = name }; else nil.
function S:SharedGuide()
  if Panoply.Guides.PlannerOn() or not self:Enabled() or not self:Shares() or Panoply:PlayAlong() then return nil end
  local name, st = self:ActivePartner()
  if not (name and st and st.guide) then return nil end
  if st.game and st.game ~= C.Flavor() then return nil end
  local _, isMe = self:LeaderOf(name)
  if isMe or not self:Serves(st) then return nil end
  if not self:InSync(st) then return nil end
  return { guide = st.guide, at = st.guideStep, leader = name }
end
-- Are we following, on a Panoply Hub plan the party leader shared (not a written guide)?
function S:HoldsSharedRoute()
  local saved = Panoply.cdb and Panoply.cdb.plan
  return saved ~= nil and saved.sharedKind == "hub" and self:IsFollower() or false
end
-- Same route as this partner? A shared action list (the same hash), or the same written guide.
function S:SameRoute(st)
  if not st then return false end
  if st.hash and st.hash == Panoply.Planner.hash then return true end
  local saved = Panoply.cdb and Panoply.cdb.plan
  return st.guide ~= nil and saved ~= nil and saved.source == "guides" and saved.guide == st.guide
end

-- CheckRoute with the planner off. The leader sends a Panoply Hub plan when the follower is not on it; the follower follows the
-- leader's written guide or Hub plan while in step, and goes back to their own written guide when not.
function S:CheckShared(who, st)
  if Panoply:NoGuideHere() then return end
  if st.game and st.game ~= C.Flavor() then return end
  if st.playAlong or st.shares == false or st.noGuide then return end
  local _, isMe = self:LeaderOf(who)
  local saved = Panoply.cdb and Panoply.cdb.plan
  if isMe then
    local mine = Panoply.Planner.hash
    local hub = saved and (saved.source == "hub" or saved.sharedKind == "hub")
    if mine and hub and st.hash ~= mine then self:SendPlanTo(who, true) end
    if mine and st.hash == mine then self:NoteShared(who) end
    return
  end
  if not self:Serves(st) then return end
  if Panoply.Hub and Panoply.Hub:Holds() then return end   -- our own Panoply Hub plan is the route (a side trip, a replan we sent ourselves)
  local inStep = self:InSync(st)
  if st.guide then
    self:FollowGuide(who, st, inStep)
  elseif st.hash then
    if st.hash == Panoply.Planner.hash then
      if inStep or not self:HoldsSharedRoute() then self:NoteShared(who) else self:OwnRoute(who) end
      return
    end
    if inStep and st.hash ~= st.badHash then self:AskPlanFrom(who)
    elseif not inStep and self:HoldsSharedRoute() then self:OwnRoute(who) end
  elseif self:HoldsSharedRoute() then
    self:OwnRoute(who)   -- the leader shares no route any more
  end
end
-- Our own written guide again (out of step with the leader, or the leader shares nothing): from our own progress.
function S:OwnRoute(who)
  local saved = Panoply.cdb and Panoply.cdb.plan
  local G = Panoply.Guides
  if saved then saved.shared, saved.sharedKind, saved.sharedBy = nil, nil, nil end
  local ok, info = G:Start("partner")
  if not ok then G:NoStep("partner") end
  Panoply:Print(("You and %s are not on the same quests now, so you keep your own leveling guide%s."):format(who,
    ok and info and info.title and (": " .. info.title) or ""))
  self:SendState()
end
function S:FollowGuide(who, st, inStep)
  local saved = Panoply.cdb and Panoply.cdb.plan
  local G = Panoply.Guides
  local onIt = saved and saved.source == "guides" and saved.guide == st.guide
  if inStep then
    if onIt then
      if saved.shared ~= who then saved.shared = who end   -- already on the leader's guide: our own place in it is kept
      return
    end
    if not G:Guide(st.guide) or not G:InThisGame(G:Guide(st.guide)) then return end
    local ok, info = G:Start("partner")
    if ok and info and info.shared then
      Panoply:Print(("You and %s are on the same quests, so you follow %s's leveling guide: %s."):format(who, who, tostring(info.title)))
      self:SendState()
    end
    return
  end
  -- out of step: a guide we took from the leader gives way to our own (the same guide stays, at our own place in it)
  if saved and (saved.shared or saved.sharedKind == "hub") then
    local own = G:Pick(Panoply.State)
    if saved.sharedKind ~= "hub" and own and own.id == saved.guide then saved.shared = nil return end
    self:OwnRoute(who)
  end
end

-- We are on the same route as this partner: remember both for the next log-in.
function S:NoteShared(who)
  if not Panoply.cdb or not Panoply.Planner.hash then return end
  local x = Panoply.cdb.partner
  if not x or x.name ~= who or x.hash ~= Panoply.Planner.hash then
    x = { name = who, hash = Panoply.Planner.hash }
    Panoply.cdb.partner = x
  end
  x.index = Panoply.Engine.index
end
Panoply:Listen("STEP_CHANGED", function()
  local x = Panoply.cdb and Panoply.cdb.partner
  if x and Panoply.Planner.hash and x.hash == Panoply.Planner.hash then x.index = Panoply.Engine.index end
end)

-- The saved partner of this character, when they are in the group but have not been heard from yet.
function S:AwaitedPartner()
  local x = Panoply.cdb and Panoply.cdb.partner
  if not x or not x.name then return nil end
  local want = Panoply.db and Panoply.db.syncPartner
  if want and want ~= "" and shortName(want):lower() ~= x.name:lower() then return nil end
  for _, n in ipairs(C.GroupMembers()) do if shortName(n) == x.name then return x.name, x end end
  return nil
end

-- "Sync now": the leader sends hello and the route; a follower sends hello and asks the leader for theirs.
-- Returns what was done, for the chat line: "sent", "asked" (with the leader's name) or "hello".
function S:SyncNow()
  self:SendHello()
  local name = self:ActivePartner()
  if not name then return "hello" end
  local leader, isMe = self:LeaderOf(name)
  local r = self.repair[name]
  if r then r.send, r.ask = nil, nil end
  local st = self.partners[name]
  if st then st.sent = nil end
  if isMe or not self:Shares() or not self:Serves(st) then
    self:SendPlan()
    return "sent"
  end
  self:AskPlan()
  return "asked", leader
end

-- A follower's re-plan is a request: the leader re-plans and shares the result, so the two routes never cross.
-- If no answer comes (S.REPLAN_WAIT; longer once the leader said it is on it) the follower plans for herself.
function S:AskReplan(reason)
  if Panoply:PlayAlong() or not self:IsFollower() then return false end
  -- Nov 11 2026: the planner is off, so the leader re-plans nothing for a written guide: a Replan picks up your guide (the leader's, when
  -- you are in step) here. Only a Panoply Hub plan the leader shared is asked for again.
  if not Panoply.Guides.PlannerOn() and not self:HoldsSharedRoute() then return false end
  local name = self:ActivePartner()
  local leader = self:LeaderOf(name)
  if not self:Allow(leader, "replan") then
    Panoply:Print("Already asked " .. leader .. " for a new route. It arrives in a moment.")
    return true
  end
  self:Queue("R", { h = Panoply.Planner.hash })
  self.asked = { leader = leader, at = C.GetTime(), reason = reason or "partner did not answer" }
  Panoply:Print("Asked " .. leader .. " (the party leader) for a new route. It arrives in a moment.")
  return true
end

-- The leader's side of that request (one at a time, never more than every S.REPLAN_ASK_GAP). Always answered
-- with a K message: ok = the new route is coming (it is sent when it is built), or why not.
function S:OnReplanRequest(who)
  local function answer(ok, why) self:Queue("K", { ok = ok and 1 or 0, why = why }) end
  if Panoply:PlayAlong() then return answer(false, "playalong") end
  if Panoply:NoGuideHere() then return answer(false, "noguide") end   -- 0.7.4.1
  if not self:Shares() then return answer(false, "off") end
  local _, isMe = self:LeaderOf(who)
  if not isMe then return answer(false, "notleader") end
  local now = C.GetTime()
  if now - (self.lastReplanAsk or -1000000) < S.REPLAN_ASK_GAP then return answer(true) end   -- the one a moment ago covers it
  self.lastReplanAsk = now
  local ok, why = true, nil
  if Panoply.PartnerReplan then ok, why = Panoply:PartnerReplan(who) end
  return answer(ok, why)
end

local WHY = {
  playalong = "has the guide set to Off: quests on the map",
  noguide = "is in an area Panoply Suite has no guide for yet",
  off = "has Share one route turned off",
  notleader = "does not think she is the route leader",
  nodata = "has no quest data loaded",
  failed = "could not build a route",
}
-- The follower's side of the answer: ok = wait for the route; not ok = plan for yourself now, and say why.
function S:OnReplanAnswer(who, p)
  local a = self.asked
  if not a or a.leader ~= who then return end
  if p.ok == 1 then a.acked = C.GetTime() return end
  self:GiveUpAsk(WHY[p.why] and ("%s %s"):format(who, WHY[p.why]) or (who .. " could not re-plan right now"), p.why)
end

-- Called every tick: a request that nobody answered.
function S:CheckAsked()
  local a = self.asked
  if not a then return end
  if self:Receiving(a.leader) then return end   -- her route is arriving
  local limit = a.acked and S.REPLAN_ACKED_WAIT or S.REPLAN_WAIT
  if C.GetTime() - (a.acked or a.at) >= limit then self:GiveUpAsk(a.leader .. " did not answer", "silent") end
end

function S:GiveUpAsk(what, why)
  local a = self.asked
  self.asked = nil
  if not a then return end
  local keep = why == "playalong" or why == "off"
  Panoply:Print(what .. ", so Panoply Suite planned a route for you. " .. (keep and "You each keep your own route." or "Hers replaces it as soon as she can share one."))
  Panoply:Replan(a.reason, true)   -- true: plan here, do not ask the leader again
end

-- Plain description of what the partner is doing right now.
function S:PartnerStepText()
  local name, st = self:ActivePartner()
  if not name then return nil end
  if st.hash and st.hash == Panoply.Planner.hash and st.index then
    local step = Panoply.Engine.steps[st.index]
    if step then return Panoply.StepText.Headline(step), st.index end
  end
  -- Nov 11 2026: on the same written guide, the partner's step is found by the guide's own step number (each of you has your own list)
  if st.guide and st.guideStep and self:SameRoute(st) then
    for i, step in ipairs(Panoply.Engine.steps) do
      if step.guideStep == st.guideStep then return Panoply.StepText.Headline(step), i end
    end
  end
  return "Following a different plan", st.index
end

-- Friendly sync status (used by the Partner tab and step window).
function S:FriendlyStatus()
  local why = self:PausedReason()
  -- Nov 14 2026 (step 21): the engine is not named in what the player reads
  -- 0.9.7: partner leveling runs on the guide's own party sync; its words are Engine/PolestarParty.lua's
  if why == "polestar" then
    local PP = Panoply.PolestarParty
    return PP and PP.FriendlyStatus and PP:FriendlyStatus() or "Sync is off."
  end
  if not self:Enabled() then return "Sync is off. Turn it on in Settings to level together." end
  if why == "dungeon" then return "Sync pauses inside dungeons and resumes outside." end
  if why == "lockdown" then return "Sync is paused while the game limits addon messages." end
  local name, st = self:ActivePartner()
  if not name then
    local saved = self:AwaitedPartner()
    if saved then return "Waiting for " .. saved .. "'s Panoply Suite. You rejoin your shared route as soon as it answers." end
    if C.InGroup() then return "In a group, but your partner hasn't been seen with Panoply Suite yet." end
    local last = Panoply.cdb and Panoply.cdb.partner
    if last and last.name then return "Not grouped. Group up with " .. last.name .. " again and you pick up your shared route." end
    return "Not grouped. Invite your partner to level together."
  end
  local same = self:SameRoute(st)
  local serves, why = self:Serves(st)
  if not serves and not same and self:Shares() then
    local reason = why == "older" and "their Panoply Suite is older (update it to share a route)"
      or why == "playalong" and "they have the guide set to Off: quests on the map"
      or why == "off" and "they turned off Share one route" or nil
    if reason then return ("Connected to %s (level %s). Routes are not shared: %s."):format(name, tostring(st.level or "?"), reason) end
  end
  return ("Connected to %s (level %s)%s"):format(name, tostring(st.level or "?"), same and ", same route." or ", different route.")
end

-- Send our state again when our profession step changes (so the partner tab stays current).
Panoply:Listen("PROF_UPDATED", function()
  local G = Panoply.ProfGuide
  local key = G and G.current and G.current.key
  if key ~= S.lastProfKey then S.lastProfKey = key; if Panoply.db then S:SendState() end end
end)

function S:PartnerProfessions()
  local name, st = self:ActivePartner()
  if not name then return nil end
  return st.profs or {}, st.profStep, st.profTracked, name
end
