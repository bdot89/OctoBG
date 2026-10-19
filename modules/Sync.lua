-- OctoBG :: team sync
-- Every OctoBG in the battleground shares what its own client sees, over the
-- hidden addon channel (SendAddonMessage "BATTLEGROUND", the channel pfUI's
-- version check uses; RAID / PARTY for world PvP while detection runs). Nothing
-- is posted in chat. What the team gets:
--   * enemies a teammate sees, with health: on the map, HUD edge, enemy list
--     (distance in light blue), INC counts at bases, the enemy flag carrier's
--     health and level in Warsong Gulch while you are far away
--   * enemy cooldowns, immunities and diminishing returns a teammate saw
--   * stealth marks, and resurrection waves of graveyards too far to see
-- Only the OctoBG user nearest to an enemy reports it. The server never sends
-- anyone enemies beyond its range, so the team sees what its members see.
--
-- Wire format (prefix "OBG"), records ";"-separated, fields ","-separated,
-- player GUIDs as their low hex digits (0x00000000000000E5 -> E5), positions
-- as raw UnitPosition yards (each client applies its own axis calibration):
--   H ver,share                       hello (every 60 s, and to newcomers)
--   P low,x,y,z,hp[,name,class]       enemies (hp %, 0 = dead; name every 30 s)
--   C low,spellID,targetLow,enemy     a cast that changed cooldowns / DR / immunity
--   S low,x,y,spellID                 an enemy went into stealth here
--   G guid,tenths,x,y                 a spirit guide's next wave in tenths of seconds
-- Everything received is checked (format, ranges, lengths) and kept under the
-- tracker's own limits. Eviction: users 150 s after their last message, at
-- most 40; queued events after 4 s; name memory with the tracker unit; all on
-- a zone change.

local B = OctoBG
local U = B.U
local M = B.Map
local SY = { users = {}, nusers = 0, events = {}, named = {}, others = {}, nothers = 0,
             sent = 0, recv = 0, posNext = 1 }
B.Sync = SY

B.DEFAULTS.sync = { enabled = true, share = true }

local PREFIX = "OBG"
local MAX_LEN = 240              -- prefix + text must stay under 255
local OVERHEAD = 30              -- per message on the wire, roughly
local BYTES_PER_SEC, BURST = 500, 1200   -- ChatThrottleLib lets a whole UI use 800/s
local POS_EVERY, HELLO_EVERY, NAME_EVERY = 2, 60, 30
local USER_TIMEOUT, MAX_USERS = 150, 40

local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
                   SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9 }
local CLASS_TOKEN = {}
for k, v in pairs(CLASS_ID) do CLASS_TOKEN[v] = k end

-- ---------------------------------------------------------------- helpers

-- Player GUID <-> its low hex digits (players only: the high half is zero).
local function Low(guid)
  if type(guid) ~= "string" or string.len(guid) ~= 18 or string.sub(guid, 3, 10) ~= "00000000" then return nil end
  local s = string.gsub(string.upper(string.sub(guid, 11)), "^0+", "")
  if s == "" then return nil end
  return s
end

local function FromLow(s)
  if not s or not string.find(s, "^%x+$") or string.len(s) > 8 then return nil end
  s = string.upper(s)
  return "0x" .. string.rep("0", 16 - string.len(s)) .. s
end

-- This client's map axes <-> raw UnitPosition (a swap is its own inverse).
local function Raw(x, y)
  if B.db.swapXY then return y, x end
  return x, y
end

local function Round(v)
  return math.floor(v + 0.5)
end

local function Num(s, lo, hi)
  local v = tonumber(s)
  if not v or v < lo or v > hi then return nil end
  return v
end

-- Splits "a,b,,c" into out[1..n] (fields past n are cleared); returns n.
local function Split(s, out)
  local n = 0
  for f in string.gfind(s .. ",", "([^,]*),") do
    if n >= 8 then break end
    n = n + 1
    out[n] = f
  end
  for i = n + 1, 8 do out[i] = nil end
  return n
end

local function ValidName(s)
  return s and string.len(s) >= 2 and string.len(s) <= 24 and string.find(s, "^[%a\128-\255]+$") ~= nil
end

function SY:Me()
  if not self.me then self.me = UnitName("player") end
  return self.me
end

-- The channel to share on, or nil when there is no team to share with.
function SY:Channel()
  if B:IsBG() then return "BATTLEGROUND" end
  -- world PvP (detection or an open-world panel running): the group
  if B.zone == nil and B.active then
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
  end
  return nil
end

function SY:Receiving()
  return B.db.sync.enabled and self:Channel() ~= nil
end

function SY:Sharing()
  local db = B.db.sync
  return db.enabled and db.share and B.env.safe and self:Channel() ~= nil
end

-- Sightings go out in battlegrounds, and in a world group only once another
-- OctoBG user there has said hello (no traffic for a group without one).
function SY:Worth()
  return self:Sharing() and (B:IsBG() or self.nusers > 0)
end

-- ---------------------------------------------------------------- users

function SY:Touch(name, ver, share)
  local now = GetTime()
  local u = self.users[name]
  if not u then
    if self.nusers >= MAX_USERS then return nil end
    u = { share = true }
    self.users[name] = u
    self.nusers = self.nusers + 1
    -- a newcomer hears from us soon instead of within a minute
    if now - (self.helloAt or 0) > 10 then self.helloAt = 0 end
  end
  u.seen = now
  if ver then u.ver = ver end
  if share ~= nil then u.share = share end
  return u
end

function SY:PruneUsers(now)
  for name, u in pairs(self.users) do
    if now - u.seen > USER_TIMEOUT then
      self.users[name] = nil
      self.nusers = self.nusers - 1
    end
  end
end

-- Where the other sharing OctoBG users stand (raid / party map positions).
function SY:Others()
  local out, n = self.others, 0
  if self.nusers > 0 then
    local nr = GetNumRaidMembers()
    local prefix, count = "raid", nr
    if nr == 0 then prefix, count = "party", GetNumPartyMembers() end
    local me = self:Me()
    for i = 1, count do
      local unit = prefix .. i
      local name = UnitName(unit)
      local usr = name and name ~= me and self.users[name]
      if usr and usr.share then
        local x, y = M:UnitWorld(unit)
        if x then
          n = n + 1
          if not out[n] then out[n] = {} end
          out[n].x, out[n].y = x, y
        end
      end
    end
  end
  self.nothers = n
end

-- True when no other sharing user stands clearly nearer to this unit.
function SY:Best(u)
  if not u.x or not u.dist then return true end
  for i = 1, self.nothers do
    local o = self.others[i]
    if M.Dist(o.x, o.y, u.x, u.y) < u.dist - 10 then return false end
  end
  return true
end

-- ---------------------------------------------------------------- sending

function SY:Push(typ, rec)
  local n = table.getn(self.events)
  if n >= 60 then table.remove(self.events, 1) end
  table.insert(self.events, { typ, rec, GetTime() })
end

-- The oldest queued event plus the ones of the same type right behind it,
-- packed into one message; returns the message and how many it holds.
function SY:NextEvent(now)
  local ev = self.events
  while ev[1] and now - ev[1][3] > 4 do table.remove(ev, 1) end
  local first = ev[1]
  if not first then return nil end
  local typ, msg, k = first[1], first[1] .. first[2], 1
  while ev[k + 1] and ev[k + 1][1] == typ and string.len(msg) + 1 + string.len(ev[k + 1][2]) <= MAX_LEN do
    msg = msg .. ";" .. ev[k + 1][2]
    k = k + 1
  end
  return msg, k
end

function SY:Hello()
  self:Push("H", B.VERSION .. "," .. (B.db.sync.share and 1 or 0))
  self.helloAt = GetTime()
end

-- Enemies this client sees and is the nearest OctoBG user to.
function SY:Snapshot()
  local now = GetTime()
  self:Others()
  local recs, n = {}, 0
  local named = self.named
  for guid, u in pairs(B.Tracker.units) do
    if u.visible and not u.fake and u.x and now - (u.posAt or 0) < 1.5 and self:Best(u) then
      local low = Low(guid)
      if low then
        local x, y = Raw(u.x, u.y)
        local hp = ""
        if u.dead then
          hp = "0"
        elseif u.hp and u.hpmax and u.hpmax > 0 then
          hp = tostring(math.max(1, Round(u.hp / u.hpmax * 100)))   -- Feign Death is not dead
        end
        local rec = low .. "," .. Round(x) .. "," .. Round(y) .. "," .. (u.z and Round(u.z) or "") .. "," .. hp
        if u.name and (not named[guid] or now - named[guid] > NAME_EVERY) then
          rec = rec .. "," .. u.name .. "," .. (CLASS_ID[u.class or ""] or 0)
          named[guid] = now
        end
        n = n + 1
        recs[n] = rec
      end
    end
  end
  for g in pairs(named) do
    if not B.Tracker.units[g] then named[g] = nil end
  end
  -- pack; an unsent snapshot is simply replaced by this one
  local msgs, m, cur = {}, 0, nil
  for i = 1, n do
    if cur and string.len(cur) + 1 + string.len(recs[i]) <= MAX_LEN then
      cur = cur .. ";" .. recs[i]
    else
      if cur then
        m = m + 1
        msgs[m] = cur
      end
      cur = "P" .. recs[i]
    end
  end
  if cur then
    m = m + 1
    msgs[m] = cur
  end
  self.posMsgs, self.posNext = msgs, 1
end

-- Called by Cooldowns.lua for casts that changed cooldowns, immunity or DR.
function SY:Cast(caster, target, spellID, enemyCaster)
  if not self:Worth() then return end
  local low = Low(caster)
  local tl = target and Low(target) or ""
  if not low or (not enemyCaster and tl == "") then return end
  local T = B.Tracker
  local ref = (enemyCaster and T.units[caster]) or (target and T.units[target])
  if ref and ref.visible and not self:Best(ref) then return end
  self:Push("C", low .. "," .. spellID .. "," .. tl .. "," .. (enemyCaster and 1 or 0))
end

-- Called by Tracker.lua when an enemy goes into stealth in our sight.
function SY:Stealth(guid, m, spell)
  if not self:Worth() or not m.x then return end
  local low = Low(guid)
  if not low then return end
  local u = B.Tracker.units[guid]
  if u and u.visible and not self:Best(u) then return end
  local x, y = Raw(m.x, m.y)
  self:Push("S", low .. "," .. Round(x) .. "," .. Round(y) .. "," .. spell)
end

-- Called by Timers.lua when this client timed a spirit guide's wave.
function SY:Guide(g)
  if not self:Sharing() then return end
  local now = GetTime()
  if now - (g.sentAt or 0) < 20 then return end
  local rem = B.Timers.spirit:Remaining(g, now)
  local hex = type(g.guid) == "string" and string.upper(string.sub(g.guid, 3))
  if not rem or not hex or not string.find(hex, "^F13%x+$") or string.len(hex) ~= 16 then return end
  local wx, wy = U.Position(g.guid)
  wx, wy = wx or g.x, wy or g.y
  local pos = ","
  if wx then
    local x, y = Raw(wx, wy)
    pos = Round(x) .. "," .. Round(y)
  end
  g.sentAt = now
  self:Push("G", hex .. "," .. Round(rem * 10) .. "," .. pos)
end

local tokens, filled = BURST, 0

local function Send(msg, ch)
  SendAddonMessage(PREFIX, msg, ch)
  SY.sent = SY.sent + 1
  tokens = tokens - string.len(msg) - OVERHEAD
end

-- At most three messages per 0.2 s and BYTES_PER_SEC on average: events first,
-- then the position snapshot.
B:Every(0.2, function()
  if not SY:Sharing() then
    if SY.events[1] then SY.events = {} end
    SY.posMsgs = nil
    return
  end
  local now = GetTime()
  tokens = math.min(BURST, tokens + (now - filled) * BYTES_PER_SEC)
  filled = now
  local ch = SY:Channel()
  local sent = 0
  while sent < 3 do
    local msg, k = SY:NextEvent(now)
    if not msg or tokens < string.len(msg) + OVERHEAD then break end
    Send(msg, ch)
    for i = 1, k do table.remove(SY.events, 1) end
    sent = sent + 1
  end
  local pm = SY.posMsgs
  while sent < 3 and pm and pm[SY.posNext] do
    local msg = pm[SY.posNext]
    if tokens < string.len(msg) + OVERHEAD then break end
    Send(msg, ch)
    SY.posNext = SY.posNext + 1
    sent = sent + 1
  end
end, true)

B:Every(POS_EVERY, function()
  if SY:Worth() and B.env.position then SY:Snapshot() end
end, true)

B:Every(5, function()
  local now = GetTime()
  SY:PruneUsers(now)
  if SY:Sharing() and now - (SY.helloAt or 0) > HELLO_EVERY then SY:Hello() end
end, true)

-- ---------------------------------------------------------------- receiving

local F = {}   -- reused field table

local HANDLERS = {}

HANDLERS.H = function(body, sender)
  Split(body, F)
  SY:Touch(sender, string.sub(F[1] or "", 1, 12), F[2] ~= "0")
end

HANDLERS.P = function(body, sender)
  local T = B.Tracker
  for rec in string.gfind(body, "[^;]+") do
    local n = Split(rec, F)
    local guid = FromLow(F[1])
    local x, y = Num(F[2], -40000, 40000), Num(F[3], -40000, 40000)
    if guid and x and y and n >= 5 then
      local z = Num(F[4], -5000, 5000)
      local hp = Num(F[5], 0, 100)
      local name, class
      if n >= 7 and ValidName(F[6]) then
        name, class = F[6], CLASS_TOKEN[tonumber(F[7]) or 0]
      end
      x, y = Raw(x, y)
      T:Team(guid, name, class, x, y, z, hp, sender)
    end
  end
end

HANDLERS.C = function(body, sender)
  for rec in string.gfind(body, "[^;]+") do
    Split(rec, F)
    local caster, spell = FromLow(F[1]), Num(F[2], 1, 1000000)
    if caster and spell then
      B.CD:TeamCast(caster, FromLow(F[3]), spell, F[4] == "1")
    end
  end
end

HANDLERS.S = function(body, sender)
  for rec in string.gfind(body, "[^;]+") do
    Split(rec, F)
    local guid = FromLow(F[1])
    local x, y, spell = Num(F[2], -40000, 40000), Num(F[3], -40000, 40000), Num(F[4], 1, 1000000)
    if guid and x and y and spell then
      x, y = Raw(x, y)
      B.Tracker:TeamStealth(guid, x, y, spell, sender)
    end
  end
end

HANDLERS.G = function(body, sender)
  for rec in string.gfind(body, "[^;]+") do
    Split(rec, F)
    local hex, rem = F[1], Num(F[2], 0, 600)
    if hex and rem and string.len(hex) == 16 and string.find(hex, "^F13%x+$") then
      local x, y = Num(F[3], -40000, 40000), Num(F[4], -40000, 40000)
      if x and y then x, y = Raw(x, y) end
      B.Timers.spirit:Team("0x" .. string.upper(hex), rem / 10, x, y)
    end
  end
end

B:On("CHAT_MSG_ADDON", function(ev, prefix, msg, channel, sender)
  if prefix ~= PREFIX or not SY:Receiving() then return end
  if type(msg) ~= "string" or type(sender) ~= "string" or sender == SY:Me() then return end
  if string.len(msg) < 2 or string.len(msg) > 255 then return end
  local h = HANDLERS[string.sub(msg, 1, 1)]
  if not h then return end
  SY.recv = SY.recv + 1
  if string.sub(msg, 1, 1) ~= "H" and not SY:Touch(sender) then return end
  h(string.sub(msg, 2), sender)
end, true)

-- ---------------------------------------------------------------- status

-- Enemies on the map right now only because a teammate sees them.
function SY:TeamOnly()
  local n, now = 0, GetTime()
  for _, u in pairs(B.Tracker.units) do
    if not u.visible and u.teamAt and now - u.teamAt < B.Tracker.TEAM_FRESH then n = n + 1 end
  end
  return n
end

function SY:Status()
  local names = {}
  for name, u in pairs(self.users) do
    table.insert(names, name .. (u.share and "" or " (listening)"))
  end
  table.sort(names)
  return names
end

B:Command("sync", "team sync: who shares, what came in", function()
  local names = SY:Status()
  B:Print("team sync " .. (B.db.sync.enabled and "on" or "off") .. (B.db.sync.share and "" or " (not sharing)")
    .. " - channel " .. tostring(SY:Channel() or "none (not in a battleground or group)"))
  B:Print(table.getn(names) .. " other OctoBG user(s): " .. (table.getn(names) > 0 and table.concat(names, ", ") or "none yet"))
  B:Print("sent " .. SY.sent .. ", received " .. SY.recv .. " messages; " .. SY:TeamOnly() .. " enemies seen only by teammates now")
end)

B:On("OBG_ZONE", function()
  SY.users, SY.nusers, SY.events, SY.named, SY.nothers = {}, 0, {}, {}, 0
  SY.posMsgs, SY.posNext = nil, 1
  SY.helloAt = GetTime() - HELLO_EVERY + 5   -- say hello 5 s after arriving
end)
