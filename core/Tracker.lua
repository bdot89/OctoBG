-- OctoBG :: enemy tracker
-- Collects enemy player GUIDs the way Spy's nampower module did (every
-- nampower *_GUID and *_OTHER event that names a unit, nameplate GUIDs), plus
-- what the group is targeting (raidNtarget GUIDs) and every enemy the
-- built-in cooldown tracker saw cast. Every 0.2 s each known enemy gets a
-- fresh position (SuperWoW), distance and line of sight (UnitXP_SP3), health
-- (nampower's GetUnitField: real values, and Feign Death does not read as 0),
-- PvP flag and the direction they are running (map / HUD arrows). Level,
-- race and guild are read for world PvP detection (Nearby.lua, People.lua).
--
-- Eviction: a unit missing from the object list for FORGET seconds is dropped,
-- at most MAX_UNITS are kept (oldest sighting goes first), and everything is
-- cleared on a zone change. Rejected GUIDs (NPCs, friends) are remembered for
-- 20 s, at most 500 before the list is wiped. Release Spirit marks: on death,
-- on coming back to life, after 10 minutes, at most 200 (wiped).

local B = OctoBG
local U = B.U
local T = { units = {}, count = 0, sorted = {}, byName = {}, released = {} }
B.Tracker = T

local MAX_UNITS = 80
local FORGET = 25

local rejected, nrej = {}, 0
local nreleased = 0

local function Reject(guid)
  if nrej >= 500 then
    rejected = {}
    nrej = 0
  end
  if not rejected[guid] then nrej = nrej + 1 end
  rejected[guid] = GetTime()
end

function T:Clear()
  self.units = {}
  self.count = 0
  self.sorted = {}
  self.byName = {}
  self.stealth = {}
  self.nstealth = 0
  self.released = {}
  nreleased = 0
  rejected = {}
  nrej = 0
end

-- nampower's GetUnitField, never raising (the field names are Spy's).
local function Field(guid, key)
  if not GetUnitField then return nil end
  local ok, v = pcall(GetUnitField, guid, key)
  if ok then return v end
  return nil
end
T.Field = Field

-- Health of a GUID: nampower's real values first (Feign Death keeps them
-- above 0), else the client's percentage.
function T.Health(guid)
  local hp, max = Field(guid, "health"), Field(guid, "maxHealth")
  if type(hp) == "number" and type(max) == "number" and max > 0 then return hp, max end
  return UnitHealth(guid), UnitHealthMax(guid)
end

-- A stealth aura on the unit (nampower aura slots), as Spy's scan found
-- enemies who walk into range already stealthed: spell id or nil.
local function StealthAura(guid)
  local auras = Field(guid, "aura")
  if type(auras) ~= "table" then return nil end
  for i = 1, 48 do
    local id = auras[i]
    if id and id ~= 0 and T.STEALTH[id] then return id end
  end
  return nil
end

-- Level (0 = "??"), race, guild and PvP flag, read again every few seconds.
function T:Details(u, now)
  local guid = u.guid
  local lvl = UnitLevel(guid)
  if type(lvl) == "number" then
    if lvl < 0 then lvl = 0 end
    if lvl > 0 or not u.level then u.level = lvl end
  end
  if not u.race then u.race, u.raceToken = UnitRace(guid) end
  local guild = GetGuildInfo(guid)
  if guild and guild ~= "" then u.guild = guild end
  u.detailsAt = now
end

function T:DropOldest()
  local oldG, oldT
  for g, u in pairs(self.units) do
    if not u.fake and (not oldT or u.seen < oldT) then oldG, oldT = g, u.seen end
  end
  if oldG then
    local u = self.units[oldG]
    if u.name and self.byName[u.name] == u then self.byName[u.name] = nil end
    self.units[oldG] = nil
    self.count = self.count - 1
  end
end

-- Add a GUID if it is an enemy player; returns the record or nil.
function T:Consider(guid)
  if not U.IsGuid(guid) or not B.env.safe then return nil end   -- sample IDs never reach Unit* calls
  local u = self.units[guid]
  if u then return u end
  local r = rejected[guid]
  if r and GetTime() - r < 20 then return nil end
  if not U.GuidExists(guid) then return nil end
  if not UnitIsPlayer(guid) then Reject(guid) return nil end
  -- Battlegrounds are cross-faction: the raid is our team, the scoreboard says
  -- everyone's side, and "can attack" decides the rest - never the faction.
  -- Elsewhere: hostile reaction first; arenas can match same-faction players,
  -- so there "can attack" counts too; the faction comparison is the last resort.
  local enemy
  if B:IsBG() then
    local side = B:SideOf(guid)
    if side then enemy = (side == "enemy") else enemy = UnitCanAttack("player", guid) and true or false end
  else
    enemy = UnitIsEnemy("player", guid)
    if not enemy and B.zone == "ARENA" then enemy = UnitCanAttack("player", guid) end
    if not enemy then
      local tf = UnitFactionGroup(guid)
      enemy = (tf ~= nil and B.faction ~= nil and tf ~= B.faction)
    end
  end
  if not enemy then Reject(guid) return nil end
  -- real players always have a class (Spy's pet check)
  local _, class = UnitClass(guid)
  if not class then Reject(guid) return nil end
  if self.count >= MAX_UNITS then self:DropOldest() end
  local now = GetTime()
  u = { guid = guid, name = UnitName(guid), class = class, seen = now, first = now,
        pvp = UnitIsPVP(guid) and true or false }
  self:Details(u, now)
  self.units[guid] = u
  self.count = self.count + 1
  if u.name then self.byName[u.name] = u end
  -- already stealthed when they came into range (rogue, druid, night elf)
  if class == "ROGUE" or class == "DRUID" or u.raceToken == "NightElf" then
    local id = StealthAura(guid)
    if id then u.stealthAura = id end
  end
  B:Fire("OBG_ENEMY", guid)
  if u.stealthAura then self:Stealthed(guid, u.stealthAura) end
  return u
end

-- A teammate's OctoBG sees this enemy (Sync.lua); hp is a percentage, 0 = dead.
-- What this client sees itself always wins: a unit in our own object list is
-- never overwritten, and a GUID we can look at goes through Consider instead.
T.TEAM_FRESH = 4   -- seconds a teammate's report counts as a current position
function T:Team(guid, name, class, x, y, z, hp, sender)
  local u = self.units[guid]
  if u and (u.visible or u.fake) then return end
  local now = GetTime()
  if not u then
    if U.GuidExists(guid) then
      self:Consider(guid)
      return
    end
    local r = rejected[guid]
    if r and now - r < 20 then return end
    if self.count >= MAX_UNITS then self:DropOldest() end
    u = { guid = guid, seen = now, first = now }
    self.units[guid] = u
    self.count = self.count + 1
    B:Fire("OBG_ENEMY", guid)
  end
  if name and not u.name then
    u.name = name
    self.byName[name] = u
  end
  if class and not u.class then u.class = class end
  self:Heading(u, x, y, now)
  u.x, u.y, u.z, u.posAt = x, y, z, now
  u.seen, u.teamAt, u.teamBy = now, now, sender
  if hp then
    u.hp, u.hpmax = hp, 100
    if hp > 0 then
      u.dead = nil
    elseif not u.dead then
      u.dead, u.diedAt = true, now
    end
  end
end

function T:FindByName(name)
  if not name then return nil end
  local u = self.byName[name]
  if u and self.units[u.guid] == u then return u end
  for _, v in pairs(self.units) do
    if v.name == name then
      self.byName[name] = v
      return v
    end
  end
  return nil
end

-- Which way an enemy is running, from their positions 0.4 s or more apart:
-- u.head = angle from north towards west (the map's and Map:Facing's
-- convention), u.headAt = when they last moved faster than 2.5 yd/s.
function T:Heading(u, x, y, now)
  if not x then return end
  if not u.hx0 or now - u.ht0 > 3 then
    u.hx0, u.hy0, u.ht0 = x, y, now
    return
  end
  local dt = now - u.ht0
  if dt < 0.4 then return end
  local dx, dy = x - u.hx0, y - u.hy0
  if dx * dx + dy * dy > 6.25 * dt * dt then
    u.head = math.atan2(dy, dx)
    u.headAt = now
  end
  u.hx0, u.hy0, u.ht0 = x, y, now
end

-- Running now (the arrow points their way) or standing (plain triangle).
function T.Moving(u, now)
  return u.head and u.headAt and now - u.headAt < 1.2
end

-- Living enemies with a known position within r yards of a world point,
-- position at most maxAge seconds old.
function T:CountNear(x, y, r, maxAge)
  local now, n = GetTime(), 0
  maxAge = maxAge or 3
  for _, u in pairs(self.units) do
    if u.x and not u.dead and now - (u.posAt or 0) <= maxAge then
      local dx, dy = u.x - x, u.y - y
      if dx * dx + dy * dy <= r * r then n = n + 1 end
    end
  end
  return n
end

-- INC counting for a base at world point x, y:
--   at     living enemies within r yards, position at most maxAge s old
--   coming living enemies further out (up to 3 x r, at most 150 yd) running
--          towards the point - their heading (T:Heading) within 45 degrees
--          of the line to it, measured in the last 1.2 s
function T:CountIncoming(x, y, r, maxAge)
  local now = GetTime()
  maxAge = maxAge or 3
  local far = math.min(r * 3, 150)
  local at, coming = 0, 0
  for _, u in pairs(self.units) do
    if u.x and not u.dead and now - (u.posAt or 0) <= maxAge then
      local dx, dy = x - u.x, y - u.y
      local dd = dx * dx + dy * dy
      if dd <= r * r then
        at = at + 1
      elseif dd <= far * far and T.Moving(u, now) then
        local diff = u.head - math.atan2(dy, dx)
        while diff > math.pi do diff = diff - 2 * math.pi end
        while diff < -math.pi do diff = diff + 2 * math.pi end
        if math.abs(diff) <= 0.785 then coming = coming + 1 end
      end
    end
  end
  return at, coming
end

-- Without positions: living, visible enemies within r yards of the player.
function T:CountAroundPlayer(r)
  local n = 0
  for _, u in pairs(self.units) do
    if u.visible and not u.dead and u.dist and u.dist <= r then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------- sources

-- nampower *_GUID events: arg1 = GUID, arg2 = 1 for players. An aura change
-- on a rogue, druid or night elf is checked for stealth (Spy did the same).
local function OnGuidEvent(ev, guid, isPlayer)
  if isPlayer ~= 1 then return end
  local u = T:Consider(guid)
  if u and ev == "UNIT_AURA_GUID" and not u.fake
     and (u.class == "ROGUE" or u.class == "DRUID" or u.raceToken == "NightElf") then
    local id = StealthAura(guid)
    if id and not u.stealthAura then T:Stealthed(guid, id) end
    u.stealthAura = id
  end
end

local GUID_EVENTS = {
  "UNIT_HEALTH_GUID", "UNIT_AURA_GUID", "UNIT_FLAGS_GUID", "UNIT_COMBAT_GUID",
  "UNIT_NAME_UPDATE_GUID", "UNIT_MANA_GUID", "UNIT_RAGE_GUID", "UNIT_ENERGY_GUID",
}
for i = 1, table.getn(GUID_EVENTS) do
  B:On(GUID_EVENTS[i], OnGuidEvent, true)
end

-- Release Spirit (8326): the player stays dead even though they leave a
-- corpse with a GUID (Spy's finding; ghosts fail every unit check).
local RELEASE = 8326
local function Released(guid)
  if nreleased >= 200 then
    T.released = {}
    nreleased = 0
  end
  if not T.released[guid] then nreleased = nreleased + 1 end
  T.released[guid] = GetTime()
end

-- nampower event layouts (Spy's SpyNampower.lua documents them):
--   SPELL_START/GO_OTHER        itemId, spellId, caster, target, ...
--   AUTO_ATTACK_OTHER           attacker, target, damage
--   SPELL_DAMAGE_EVENT_OTHER    target, caster, spellId, amount
--   SPELL_MISS_OTHER            caster, target, spellId, missInfo
--   SPELL_HEAL_BY_OTHER         target, caster, spellId, amount
--   SPELL_ENERGIZE_BY_OTHER     target, caster, spellId, power, amount
--   AURA_CAST_ON_OTHER          spellId, caster, target
--   BUFF/DEBUFF_ADDED/REMOVED_OTHER  unit, ?, spellId
--   DAMAGE_SHIELD_OTHER         shield owner, attacker, damage
--   SPELL_DISPEL_BY_OTHER       caster, target, spellId
--   ENVIRONMENTAL_DMG_OTHER     unit, type, damage
B:On("SPELL_START_OTHER", function(ev, item, spell, caster) T:Consider(caster) end, true)
B:On("SPELL_GO_OTHER", function(ev, item, spell, caster)
  if spell == RELEASE then
    if caster then Released(caster) end
    return
  end
  T:Consider(caster)
  if T.STEALTH[spell] then T:Stealthed(caster, spell) end
end, true)
B:On("AUTO_ATTACK_OTHER", function(ev, attacker) T:Consider(attacker) end, true)
B:On("SPELL_DAMAGE_EVENT_OTHER", function(ev, target, caster) T:Consider(caster) end, true)
B:On("SPELL_MISS_OTHER", function(ev, caster) T:Consider(caster) end, true)
B:On("SPELL_HEAL_BY_OTHER", function(ev, target, caster) T:Consider(caster) end, true)
B:On("SPELL_ENERGIZE_BY_OTHER", function(ev, target, caster) T:Consider(caster) end, true)
B:On("AURA_CAST_ON_OTHER", function(ev, spell, caster) T:Consider(caster) end, true)
B:On("DAMAGE_SHIELD_OTHER", function(ev, owner, attacker) T:Consider(attacker) end, true)
B:On("SPELL_DISPEL_BY_OTHER", function(ev, caster) T:Consider(caster) end, true)
B:On("ENVIRONMENTAL_DMG_OTHER", function(ev, guid) T:Consider(guid) end, true)
B:On("DEBUFF_ADDED_OTHER", function(ev, guid) T:Consider(guid) end, true)
B:On("BUFF_ADDED_OTHER", function(ev, guid, a2, spell)
  local u = T:Consider(guid)
  if T.STEALTH[spell] then
    if u then u.stealthAura = spell end
    T:Stealthed(guid, spell)
  end
end, true)
B:On("BUFF_REMOVED_OTHER", function(ev, guid, a2, spell)
  if T.STEALTH[spell] then
    local u = guid and T.units[guid]
    if u then u.stealthAura = nil end
    T:Unstealthed(guid, spell)
  end
end, true)

-- UNIT_DIED (nampower) is a real death, never Feign Death.
B:On("UNIT_DIED", function(ev, guid)
  if not guid then return end
  if T.released[guid] then
    T.released[guid] = nil
    nreleased = nreleased - 1
  end
  local u = T.units[guid]
  if u then
    u.dead = true
    u.diedAt = GetTime()
  end
  if T.stealth[guid] then T:DropStealth(guid) end
end, true)

-- Spy switched these nampower events on; OctoBG needs the same ones.
local NP_CVARS = { "NP_EnableSpellStartEvents", "NP_EnableSpellGoEvents", "NP_EnableAutoAttackEvents", "NP_EnableAuraCastEvents" }
local cvarsDone = false
B:On("PLAYER_ENTERING_WORLD", function()
  if cvarsDone or not GetNampowerVersion then return end
  cvarsDone = true
  for i = 1, table.getn(NP_CVARS) do
    local ok, v = pcall(GetCVar, NP_CVARS[i])
    if ok and v ~= nil and v ~= "1" then pcall(SetCVar, NP_CVARS[i], "1") end
  end
end)

-- ---------------------------------------------------------------- stealth

-- An enemy who stealths out of detection range stops existing for this
-- client (the server sends nothing more), so all OctoBG can show is where
-- they went into stealth and how far they could have moved since: a ring
-- growing at STEALTH_SPEED (rough stealth movement speed; Sprint beats it).
-- Spell ids as Spy's nampower module lists them.
T.STEALTH = {
  [1784] = "Stealth", [1785] = "Stealth", [1786] = "Stealth", [1787] = "Stealth",
  [5215] = "Prowl", [6783] = "Prowl", [9913] = "Prowl",
  [20580] = "Shadowmeld",
  [1856] = "Vanish", [1857] = "Vanish", [11327] = "Vanish", [11329] = "Vanish",
}
T.STEALTH_SPEED = 5
local STEALTH_KEEP, STEALTH_MAX = 20, 40

-- stealth[guid] = { name, class, kind, x, y, at, lastSeen, alertAt }
-- Eviction: 20 s after last seen, on death, on stealth ending, max 40, zone clears.
T.stealth = {}
T.nstealth = 0

function T:DropStealth(guid)
  if self.stealth[guid] then
    self.stealth[guid] = nil
    self.nstealth = self.nstealth - 1
  end
end

-- With marks off, alerts are throttled here (10 s per enemy; the table is
-- wiped at 100 entries and on a zone change).
local alertedAt, nalerted = {}, 0

function T:Stealthed(guid, spell)
  local u = self:Consider(guid)
  if not u then return end
  local now = GetTime()
  if not B.db.stealth.enabled then
    if now - (alertedAt[guid] or 0) > 10 and B.Nearby and B.Nearby:StealthAlert(u, self.STEALTH[spell], U.Distance(guid)) then
      if nalerted >= 100 then alertedAt, nalerted = {}, 0 end
      if not alertedAt[guid] then nalerted = nalerted + 1 end
      alertedAt[guid] = now
    end
    return
  end
  local m = self.stealth[guid]
  if not m then
    if self.nstealth >= STEALTH_MAX then
      local oldG, oldT
      for g, s in pairs(self.stealth) do
        if not oldT or s.lastSeen < oldT then oldG, oldT = g, s.lastSeen end
      end
      if oldG then self:DropStealth(oldG) end
    end
    m = {}
    self.stealth[guid] = m
    self.nstealth = self.nstealth + 1
  end
  local x, y = U.Position(guid)
  if not x then x, y = u.x, u.y end
  m.name, m.class, m.kind, m.x, m.y, m.at, m.lastSeen = u.name, u.class, self.STEALTH[spell], x, y, now, now
  m.teamBy = nil
  if B.Sync then B.Sync:Stealth(guid, m, spell) end
  -- one stealth alert for battlegrounds and world PvP (Nearby.lua decides)
  if now - (m.alertAt or 0) > 10 and B.Nearby and B.Nearby:StealthAlert(u, m.kind, U.Distance(guid)) then
    m.alertAt = now
  end
end

-- A stealth mark a teammate's OctoBG made (Sync.lua); our own fresher mark wins.
function T:TeamStealth(guid, x, y, spell, sender)
  if not B.db.stealth.enabled or not self.STEALTH[spell] then return end
  local now = GetTime()
  local m = self.stealth[guid]
  if m and not m.teamBy and now - m.lastSeen < 3 then return end
  if not m then
    if self.nstealth >= STEALTH_MAX then return end
    m = {}
    self.stealth[guid] = m
    self.nstealth = self.nstealth + 1
  end
  local u = self.units[guid]
  m.name, m.class, m.kind = u and u.name or m.name, u and u.class or m.class, self.STEALTH[spell]
  m.x, m.y, m.at, m.lastSeen, m.teamBy = x, y, now, now, sender
end

-- Vanish's own aura ends while its stealth goes on, so only the stealth
-- auras clear the mark.
function T:Unstealthed(guid, spell)
  if self.STEALTH[spell] ~= "Vanish" then self:DropStealth(guid) end
end

-- Yards the stealthed enemy may have moved since last seen.
function T:StealthRadius(m, now)
  return (now - m.lastSeen) * self.STEALTH_SPEED
end

-- ---------------------------------------------------------------- reach

-- How far away enemies are picked up here: the farthest UnitXP distance of
-- an enemy in the object list, and the distances at which living enemies
-- drop out of it (that is the server's visibility edge). Kept per zone in
-- db.reach[zone name] = { max, drop, n, day } (at most 60 zones).
T.reach, T.drops = 0, {}

function T:ReachSummary()
  local n = table.getn(self.drops)
  local drop
  if n > 0 then
    local c = {}
    for i = 1, n do c[i] = self.drops[i] end
    table.sort(c)
    drop = c[math.floor((n + 1) / 2)]
  end
  return self.reach, drop, n
end

function T:SaveReach()
  local zone = self.reachZone
  if not zone or self.reach <= 0 then return end
  local max, drop, n = self:ReachSummary()
  local db = B.db.reach
  local count = 0
  for _ in pairs(db) do count = count + 1 end
  if count >= 60 and not db[zone] then
    B.db.reach = {}
    db = B.db.reach
  end
  local old = db[zone]
  db[zone] = { max = math.max(max, old and old.max or 0), drop = drop or (old and old.drop), n = n, day = date("%d %b") }
  if self.reachIsBG or B.debug then
    B:Print(zone .. ": enemies picked up as far as " .. math.floor(max) .. " yd"
      .. (drop and (", they drop out at about " .. math.floor(drop) .. " yd (" .. n .. " seen leaving)") or ""))
  end
end

B:On("PLAYER_TARGET_CHANGED", function()
  T:Consider(U.GuidOf("target"))
end, true)

B:On("UPDATE_MOUSEOVER_UNIT", function()
  T:Consider(U.GuidOf("mouseover"))
end, true)

-- Open world: each zone gets its own reach figure (battlegrounds go through OBG_ZONE).
B:On("ZONE_CHANGED_NEW_AREA", function()
  local zone = GetRealZoneText()
  if B.zone or zone == T.reachZone then return end
  T:SaveReach()
  T.reachZone, T.reachIsBG, T.reach, T.drops = zone, false, 0, {}
end, true)

B:On("OBG_ZONE", function()
  T:SaveReach()
  T:Clear()
  alertedAt, nalerted = {}, 0
  T.reachZone, T.reachIsBG, T.reach, T.drops = B.zoneName, B:IsBG(), 0, {}
  if B.test then T:SetSamples(true) end
end)

-- Our side or the raid changed (cross-faction battlegrounds): teammates leave
-- the enemy list, and everyone rejected so far is looked at again.
B:On("OBG_TEAM", function()
  if not B:IsBG() then return end
  for guid, u in pairs(T.units) do
    if not u.fake and B:SideOf(guid, u.name) == "friend" then
      T.units[guid] = nil
      T.count = T.count - 1
      if u.name and T.byName[u.name] == u then T.byName[u.name] = nil end
    end
  end
  rejected, nrej = {}, 0
end)

-- Nameplates (nampower: frame:GetName(1) is the plate's GUID), the group's
-- targets, and the enemy tables of Spy and EnemyCooldowns.
function T:Harvest()
  if B.env.nampower then
    local kids = { WorldFrame:GetChildren() }
    for i = 1, table.getn(kids) do
      local ok, g = pcall(kids[i].GetName, kids[i], 1)
      if ok and type(g) == "string" and string.sub(g, 1, 2) == "0x" then self:Consider(g) end
    end
  end
  local nr = GetNumRaidMembers()
  if nr > 0 then
    for i = 1, nr do self:Consider(U.GuidOf("raid" .. i .. "target")) end
  else
    for i = 1, GetNumPartyMembers() do self:Consider(U.GuidOf("party" .. i .. "target")) end
  end
  self:Consider(U.GuidOf("target"))
  self:Consider(U.GuidOf("targettarget"))
  self:Consider(U.GuidOf("mouseover"))
  if SpySW and type(SpySW.enemyGuids) == "table" then
    for g in pairs(SpySW.enemyGuids) do self:Consider(g) end
  end
  if B.CD then
    for g in pairs(B.CD.cache) do self:Consider(g) end
  end
  -- the old EnemyCooldowns addon, while it is still switched on
  if ECD and type(ECD.cache) == "table" then
    for g in pairs(ECD.cache) do self:Consider(g) end
  end
end

-- ---------------------------------------------------------------- refresh

local function ByDist(a, b)
  if a.dist and b.dist then return a.dist < b.dist end
  if a.dist then return true end
  return false
end

local harvestAt = 0
function T:Scan()
  if not B.env.safe then return end
  local now = GetTime()
  if now - harvestAt > 1 then
    harvestAt = now
    self:Harvest()
  end
  local sorted, n = self.sorted, 0
  local px, py = B.Map:PlayerWorld()
  for guid, u in pairs(self.units) do
    if u.fake then
      n = n + 1
      sorted[n] = u
    elseif U.GuidExists(guid) then
      u.seen = now
      u.visible = true
      local x, y, z = U.Position(guid)
      if x then
        self:Heading(u, x, y, now)
        u.x, u.y, u.z, u.posAt = x, y, z, now
      end
      u.dist = U.Distance(guid)
      if u.dist then
        u.lastDist = u.dist
        if u.dist > self.reach then self.reach = u.dist end
      end
      local m = self.stealth[guid]
      if m then
        m.x, m.y, m.lastSeen = u.x or m.x, u.y or m.y, now
      end
      if not u.losAt or now - u.losAt > 0.5 then
        u.los = U.InSight(guid)
        u.losAt = now
      end
      u.pvp = UnitIsPVP(guid) and true or false
      if not u.detailsAt or now - u.detailsAt > 5 then self:Details(u, now) end
      u.hp, u.hpmax = T.Health(guid)
      local ghost = UnitIsGhost and UnitIsGhost(guid)
      if u.hp and u.hp > 0 and not ghost then
        u.dead = nil
        if self.released[guid] then   -- back to life after releasing
          self.released[guid] = nil
          nreleased = nreleased - 1
        end
      elseif ghost or self.released[guid] then
        u.dead = true
      elseif UnitIsDeadOrGhost(guid) then
        -- Feign Death can look dead; ClassicAPI's UnitIsFeignDeath tells them apart
        local fd = false
        if UnitIsFeignDeath then
          local ok, v = pcall(UnitIsFeignDeath, guid)
          fd = ok and v and true or false
        end
        u.dead = not fd
      end
      if u.dead and not u.diedAt then u.diedAt = now elseif not u.dead then u.diedAt = nil end
      if not u.name then
        u.name = UnitName(guid)
        if u.name then self.byName[u.name] = u end
      end
      n = n + 1
      sorted[n] = u
    else
      -- a living enemy leaving the object list far away marks the visibility edge
      if u.visible and not u.dead and u.lastDist and u.lastDist > 40 and not self.stealth[guid] then
        table.insert(self.drops, u.lastDist)
        if table.getn(self.drops) > 30 then table.remove(self.drops, 1) end
      end
      u.visible = nil
      u.dist = nil
      u.los = nil
      -- a teammate sees them: distance from their report (Sync.lua)
      if u.teamAt and now - u.teamAt < self.TEAM_FRESH and u.x and px then
        u.dist = B.Map.Dist(px, py, u.x, u.y)
        n = n + 1
        sorted[n] = u
      end
      if now - u.seen > FORGET then
        self.units[guid] = nil
        self.count = self.count - 1
        if u.name and self.byName[u.name] == u then self.byName[u.name] = nil end
      end
    end
  end
  for i = table.getn(sorted), n + 1, -1 do sorted[i] = nil end
  table.sort(sorted, ByDist)
  for guid, m in pairs(self.stealth) do
    if now - m.lastSeen > STEALTH_KEEP then self:DropStealth(guid) end
  end
  for guid, t in pairs(self.released) do
    if now - t > 600 then
      self.released[guid] = nil
      nreleased = nreleased - 1
    end
  end
end

B:Every(0.2, function() T:Scan() end, true)

-- ---------------------------------------------------------------- layout-mode samples

-- Sample enemies placed around the player so the HUD, list and map can be
-- arranged outside a battleground. They follow the player (relative offsets).
local SAMPLES = {
  { "Testrogue", "ROGUE", 12, 8, true },
  { "Testpriest", "PRIEST", -20, 25, true },
  { "Testwarrior", "WARRIOR", 30, -6, false },
  { "Testmage", "MAGE", -38, -30, true },
  { "Testhunter", "HUNTER", 52, 40, true },
}

function T:SetSamples(on)
  for g, u in pairs(self.units) do
    if u.fake then
      self.units[g] = nil
      self.count = self.count - 1
      if self.byName[u.name] == u then self.byName[u.name] = nil end
    end
  end
  self:DropStealth("sample")
  if not on then return end
  self.stealth.sample = { fake = true, name = "Testdruid", class = "DRUID", kind = "Prowl", lastSeen = GetTime() }
  self.nstealth = self.nstealth + 1
  for i = 1, table.getn(SAMPLES) do
    local s = SAMPLES[i]
    local g = "sample" .. i
    local u = { guid = g, fake = true, name = s[1], class = s[2], ox = s[3], oy = s[4],
                los = s[5], hp = 100 - i * 13, hpmax = 100, seen = GetTime(), visible = true,
                level = 58 + math.mod(i, 3), pvp = true, guild = (i == 2) and "Sample Guild" or nil }
    self.units[g] = u
    self.byName[u.name] = u
    self.count = self.count + 1
  end
end

-- Keep the samples around the player (world position if known, else 0,0).
B:Every(0.1, function()
  if not B.test then return end
  local px, py = B.Map:PlayerWorld()
  px, py = px or 0, py or 0
  local now = GetTime()
  for _, u in pairs(T.units) do
    if u.fake then
      local a = now * 0.15 + u.ox * 0.05
      local c, s = math.cos(a), math.sin(a)
      local x, y = px + u.ox * c - u.oy * s, py + u.ox * s + u.oy * c
      T:Heading(u, x, y, now)
      u.x, u.y = x, y
      u.posAt = now
      u.seen = now
      u.dist = math.sqrt(u.ox * u.ox + u.oy * u.oy)
    end
  end
  local m = T.stealth.sample
  if m then
    m.x, m.y = px - 15, py + 34
    m.lastSeen = now - math.mod(now, 15)   -- the ring grows for 15 s, then starts again
  end
end, true)

B:On("OBG_LAYOUT", function(ev, on)
  T:SetSamples(on)
end)
