-- OctoBG :: timers
-- One panel of bars:
--   * spirit resurrection waves per graveyard (spirit guides cast Spirit Heal
--     every 30 s; nampower reports the channel start 22011 and the heal 22012,
--     both seen in this server's combat logs),
--   * Arathi Basin bases (60 s after an assault) and Alterac Valley
--     towers/graveyards (5 min), from the system messages and herald yells,
--   * the game start countdown,
--   * Arathi Basin: who reaches 2000 first, from the measured resource rate.
-- While dead in a battleground a big "Resurrection in N" sits mid-screen.
-- Clicking a row says it in /bg ("Stables: Horde takes it in 0:37"); posting
-- only ever happens on that click (U.SendBG: 1 per second, same text once per 4 s).

local B = OctoBG
local U = B.U
local M = B.Map
local TM = { rows = {}, pool = {} }
B.Timers = TM

local WAVE = 30
local SPIRIT_CHANNEL, SPIRIT_HEAL = 22011, 22012
local GUIDE_FACTION = { [13116] = "Alliance", [13117] = "Horde" }
local FAC = { alliance = "Alliance", horde = "Horde" }
local EVFAC = { CHAT_MSG_BG_SYSTEM_ALLIANCE = "Alliance", CHAT_MSG_BG_SYSTEM_HORDE = "Horde" }
local ICON_RES = "Interface\\Icons\\Spell_Holy_Resurrection"
local ICON_WATCH = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local POI = "Interface\\Minimap\\POIIcons"
local ROW_H, WIDTH, MAX_ROWS = 16, 214, 16
-- faction colours for text on the dark panel (the bar colours are too deep to read)
local TEXT = { Alliance = { 0.5, 0.75, 1 }, Horde = { 1, 0.45, 0.4 } }

-- "4 sec", "0:37", "6:03" for chat
local function Words(s)
  if not s then return "?" end
  if s < 60 then return math.ceil(s - 0.05) .. " sec" end
  return U.Time(s)
end

-- ---------------------------------------------------------------- spirit guides

-- guides[guid] = { faction, anchor = time of a wave, x, y, label, seen }
-- Eviction: a guide missing from the object list for 120 s is dropped
-- (captured AB/AV graveyards replace their guide); at most 24; zone clears.
local S = { guides = {}, n = 0 }
TM.spirit = S

local function Guide(guid)
  if type(guid) ~= "string" then return nil end
  local g = S.guides[guid]
  if not g then
    if S.n >= 24 then return nil end
    g = { guid = guid, faction = GUIDE_FACTION[U.CreatureEntry(guid) or 0] }
    S.guides[guid] = g
    S.n = S.n + 1
  end
  g.seen = GetTime()
  return g
end

-- nampower SPELL_START_OTHER: arg6 castTime, arg7 duration (ms). The channel
-- ends with the heal, so the next wave is start + duration.
B:On("SPELL_START_OTHER", function(ev, item, spell, caster, target, flags, castTime, duration)
  if spell ~= SPIRIT_CHANNEL then return end
  local g = Guide(caster)
  if not g then return end
  local ms = (duration and duration > 0 and duration) or (castTime and castTime > 0 and castTime) or WAVE * 1000
  g.anchor = GetTime() + ms / 1000
  g.localAt = GetTime()
  if B.Sync then B.Sync:Guide(g) end
end, true)

-- The resurrection clock. The wave is one timer for the whole battleground, not
-- one per graveyard: the heal (22012) is what raises the dead, and a user's log
-- of one guide (AV, 28 Sep 2026) has heals 60.06, 60.10, 120.16 and 150.19 s
-- apart: whole waves of 30.04 s (the server restarts a 30 s timer on the tick
-- after it runs out, vmangos BattleGround::Update m_LastResurrectTime). Guides'
-- channels (22011) run on their own phase when nobody is waiting, which is why
-- graveyards seemed to differ. That timer starts with the instance, as does
-- GetBattlefieldInstanceRunTime, so the wave is known with no graveyard in
-- sight ("clock"), and locks on when one is timed: a spirit healer's own timer
-- ("area"), a heal seen ("seen") or reported by a teammate ("team").
-- If two graveyards ever heal out of step, S.perGuide goes back to per-guide
-- timing. /obg reswave shows how far the clock was from the real heals.
local PERIOD = 30.04

function S:FromClock()
  if not B:IsBG() or not GetBattlefieldInstanceRunTime then return nil end
  local ms = GetBattlefieldInstanceRunTime()
  if not ms or ms <= 0 then return nil end
  return PERIOD - math.mod(ms / 1000, PERIOD)
end

-- A real wave at time t (src: "area", "seen", "team"; g: the guide that healed).
function S:Confirm(t, src, g)
  local now = GetTime()
  local c = self:FromClock()
  if c and src ~= "team" then
    -- how far the game clock's guess is from this real wave
    local e = math.mod(math.abs((now + c) - t), PERIOD)
    self.clockErr = math.min(e, PERIOD - e)
  end
  if g and self.waveGuide and g ~= self.waveGuide and self.waveAt then
    local e = math.mod(math.abs(t - self.waveAt), PERIOD)
    if math.min(e, PERIOD - e) > 2 then
      self.conflicts = (self.conflicts or 0) + 1
      if self.conflicts >= 3 then self.perGuide = true end
    end
  end
  self.waveAt, self.waveSrc = t, src
  if g then self.waveGuide = g end
end

-- Seconds to the next wave, or nil; S.perGuide: nil, each guide has its own.
function S:Global(now)
  if self.perGuide then return nil end
  if self.waveAt then
    local d = now - self.waveAt
    if d < 0 then return -d end
    return PERIOD - math.mod(d, PERIOD)
  end
  return self:FromClock()
end

B:On("SPELL_GO_OTHER", function(ev, item, spell, caster)
  if spell ~= SPIRIT_HEAL then return end
  local g = Guide(caster)
  if not g then return end
  local now = GetTime()
  g.anchor, g.localAt = now, now
  S:Confirm(now, "seen", g)
  if B.Sync then B.Sync:Guide(g) end
end, true)

-- A guide a teammate's OctoBG timed (Sync.lua): fills graveyards too far away
-- to see; a wave this client saw itself in the last 40 s is left alone.
function S:Team(guid, remaining, x, y)
  local g = Guide(guid)
  if not g then return end
  local now = GetTime()
  if g.localAt and now - g.localAt < 40 then return end
  g.anchor = now + remaining
  if x and not U.GuidExists(guid) then g.x, g.y = x, y end
  if self.waveSrc ~= "area" and self.waveSrc ~= "seen" then self:Confirm(now + remaining, "team") end
end

function S:Remaining(g, now)
  local r = self:Global(now)
  if r then return r end
  if not g.anchor then return nil end
  local d = now - g.anchor
  if d < 0 then return -d end
  return WAVE - math.mod(d, WAVE)
end

function S:Label(g, now)
  if g.label and now - (g.labelAt or 0) < 10 then return g.label end
  local x, y = U.Position(g.guid)
  if x then g.x, g.y = x, y end
  local label
  if B.zone == "WSG" and g.faction then
    label = g.faction .. " graveyard"
  elseif g.x then
    local m = M:NearestLandmark(g.x, g.y)
    if m then label = m.name end
  end
  if not label then label = g.faction and (g.faction .. " spirit guide") or "Spirit guide" end
  g.label, g.labelAt = label, now
  return label
end

-- The guide the player would rise at: the nearest one.
function S:Nearest()
  local best, bestD
  local px, py = M:PlayerWorld()
  for _, g in pairs(self.guides) do
    if g.anchor then
      local d = U.Distance(g.guid)
      if not d and g.x and px then d = M.Dist(px, py, g.x, g.y) end
      if d and (not bestD or d < bestD) then best, bestD = g, d end
    end
  end
  return best, bestD
end

function S:Prune(now)
  for guid, g in pairs(self.guides) do
    if U.GuidExists(guid) then
      g.seen = now
    elseif now - g.seen > 120 then
      self.guides[guid] = nil
      self.n = self.n - 1
    end
  end
end

-- The spirit healer dialog's own timer is exact; it also syncs the nearest guide.
B:On("AREA_SPIRIT_HEALER_IN_RANGE", function()
  local t = GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()
  if t and t > 0 then
    S.areaWave = GetTime() + t
    S:Confirm(S.areaWave, "area")
    local g = S:Nearest()
    if g then g.anchor = S.areaWave end
  end
end, true)

B:On("AREA_SPIRIT_HEALER_OUT_OF_RANGE", function() S.areaWave = nil end, true)

-- Seconds until the player's next resurrection wave, or nil.
function S:MyWave(now)
  if self.areaWave and self.areaWave > now then return self.areaWave - now end
  local r = self:Global(now)
  if r then return r end
  local g = self:Nearest()
  if g then return self:Remaining(g, now) end
  return nil
end

-- Seconds until the next wave at any of one faction's guides (the enemy list's
-- "dead - res N"; exact in WSG, the soonest graveyard elsewhere), or nil.
function S:NextWave(faction, now)
  now = now or GetTime()
  local r = self:Global(now)
  if r then return r end
  local best
  for _, g in pairs(self.guides) do
    if g.faction == faction then
      local r = self:Remaining(g, now)
      if r and (not best or r < best) then best = r end
    end
  end
  return best
end

-- ---------------------------------------------------------------- objectives

-- nodes[name] = { name, owner, by, ends, dur }
local O = { nodes = {}, order = {} }
TM.obj = O

local AB_NODES = { "Stables", "Gold Mine", "Blacksmith", "Lumber Mill", "Farm" }
local AB_KEYS = { { "stable", "Stables" }, { "farm", "Farm" }, { "smith", "Blacksmith" },
                  { "lumber", "Lumber Mill" }, { "mine", "Gold Mine" } }

local function ABNode(text)
  if not text then return nil end
  for i = 1, table.getn(AB_KEYS) do
    if string.find(text, AB_KEYS[i][1], 1, true) then return AB_KEYS[i][2] end
  end
  return nil
end

function O:Node(name)
  local n = self.nodes[name]
  if not n then
    n = { name = name }
    self.nodes[name] = n
  end
  return n
end

function O:Contest(name, by, dur)
  local n = self:Node(name)
  n.by, n.dur, n.ends = by, dur, GetTime() + dur
  if B.zone == "AB" then TM:Predict(GetTime()) end
end

function O:Own(name, owner)
  local n = self:Node(name)
  n.owner, n.by, n.ends = owner, nil, nil
  if B.zone == "AB" then TM:Predict(GetTime()) end
end

-- "begins in 1 minute" / "begins in 30 seconds" / AV: "1 minute until the battle..."
local function StartCountdown(low)
  local _, _, n, unit = string.find(low, "begins in (%d+) (%a+)")
  if not n then _, _, n, unit = string.find(low, "(%d+) (%a+) until the battle") end
  if n then
    local s = tonumber(n)
    if string.find(unit, "^min") then s = s * 60 end
    O.start = GetTime() + s
    return true
  end
  if string.find(low, "has begun", 1, true) then
    O.start, O.begunAt = nil, GetTime()
    return true
  end
  return false
end

-- Arathi Basin lines (BigWigs' AB module, enUS on this client):
--   "<name> has assaulted the <base>!"   "<name> claims the <base>! If left
--   unchallenged, the <faction> will control it in 1 minute!"
--   "<name> has defended the <base>!"    "The <faction> has taken the <base>!"
local function OnBGSystem(ev, msg)
  if not msg then return end
  local low = string.lower(msg)
  if StartCountdown(low) then return end
  if B.zone ~= "AB" then return end
  local fac = EVFAC[ev]
  local _, _, base = string.find(low, "has assaulted the ([^!]+)")
  if base and ABNode(base) and fac then
    O:Contest(ABNode(base), fac, 60)
    return
  end
  _, _, base = string.find(low, "claims the ([^!]+)")
  if base and ABNode(base) then
    local _, _, fw = string.find(low, "the (%a+) will control")
    local by = (fw and FAC[fw]) or fac
    if by then O:Contest(ABNode(base), by, 60) end
    return
  end
  _, _, base = string.find(low, "has defended the ([^!]+)")
  if base and ABNode(base) and fac then
    O:Own(ABNode(base), fac)
    return
  end
  local _, _, fw, tb = string.find(low, "the (%a+) has taken the ([^!]+)")
  if fw and FAC[fw] and ABNode(tb) then
    O:Own(ABNode(tb), FAC[fw])
  end
end

-- Alterac Valley herald yells (BigWigs' AV module): 5 minutes to capture a
-- graveyard or burn a tower.
local function OnYell(ev, msg)
  if not msg then return end
  local low = string.lower(msg)
  if StartCountdown(low) then return end
  if B.zone ~= "AV" then return end
  local _, _, p1, _, p2, fw = string.find(low, "^()(.-)() is under attack! if left unchecked, the (%a+) will")
  if fw and FAC[fw] then
    O:Contest(string.sub(msg, p1, p2 - 1), FAC[fw], 300)
    return
  end
  _, _, p1, _, p2, fw = string.find(low, "^()(.-)() was taken by the (%a+)")
  if fw and FAC[fw] then
    O:Own(string.sub(msg, p1, p2 - 1), FAC[fw])
    return
  end
  _, _, p1, _, p2, fw = string.find(low, "^()(.-)() was destroyed by the (%a+)")
  if fw and FAC[fw] then
    O.nodes[string.sub(msg, p1, p2 - 1)] = nil
  end
end

B:On("CHAT_MSG_BG_SYSTEM_ALLIANCE", OnBGSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_HORDE", OnBGSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", OnBGSystem, true)
B:On("CHAT_MSG_MONSTER_YELL", OnYell, true)

-- ---------------------------------------------------------------- AB prediction

-- The world state lines read like "Bases: 3  Resources: 1450/2000" (Warsong
-- Gulch: "2/3"; Alterac Valley: "Reinforcements: 412"). They are read the
-- moment the server changes them (UPDATE_WORLD_STATES), so scores are instant.
--
-- Who wins and when is worked out, not measured: the server adds points on a
-- fixed tick per number of bases (vmangos BG_AB_TickIntervals / TickPoints: 1
-- base 10 per 12 s, 2: 10 per 9 s, 3: 10 per 6 s, 4: 10 per 3 s, 5: 30 per 1 s).
-- TM:Predict plays the game forward from the last tick, with every base still
-- being captured flipping when its timer ends, and gives an exact moment
-- (pred.at), which the panels count down to every frame. If this server ticks
-- differently, two equal ticks in a row replace the table (db.abTicks).
local P = { Alliance = {}, Horde = {} }
TM.score = P
TM.extra = {}     -- world state lines that are not a score
TM.AB_TICKS = { { 10, 12 }, { 10, 9 }, { 10, 6 }, { 10, 3 }, { 30, 1 } }

function TM:Tick(bases)
  local learned = B.db.abTicks and B.db.abTicks[bases]
  return learned or self.AB_TICKS[bases]
end

-- Two ticks in a row with the same size and spacing, not what the table says: learn them.
local function Learn(p, bases, d, dt)
  if not bases or bases < 1 or bases > 5 or p.basesAt == nil then return end
  if p.lastD == d and p.lastDt and math.abs(p.lastDt - dt) < 0.6 and p.lastB == bases and dt >= 0.5 and dt <= 30 then
    local t = TM:Tick(bases)
    if t[1] ~= d or math.abs(t[2] - dt) > 0.75 then
      B.db.abTicks = B.db.abTicks or {}
      B.db.abTicks[bases] = { d, math.floor(dt * 10 + 0.5) / 10 }
    end
  end
  p.lastD, p.lastDt, p.lastB = d, dt, bases
end

function O:ScoreTick()
  if not B.zone or not GetNumWorldStateUI then return end
  local now = GetTime()
  local shown = 0
  local extra = {}
  for i = 1, GetNumWorldStateUI() do
    local state, text, icon = GetWorldStateUIInfo(i)
    if text and text ~= "" and (not state or state > 0) then
      shown = shown + 1
      local _, _, cur, max = string.find(text, "(%d+)/(%d+)")
      if not cur then _, _, cur = string.find(text, "[Rr]einforcements:?%s*(%d+)") end
      if cur then
        local li = string.lower(icon or "")
        local fac
        if string.find(li, "alliance", 1, true) then fac = "Alliance"
        elseif string.find(li, "horde", 1, true) then fac = "Horde"
        else fac = (shown == 1) and "Alliance" or "Horde" end
        local _, _, bases = string.find(text, "[Bb]ases:?%s*(%d+)")
        bases = tonumber(bases)
        local p = P[fac]
        cur, max = tonumber(cur), tonumber(max)
        if p.cur and cur < p.cur and max then p.tickAt, p.lastD, p.lastDt = nil, nil, nil end   -- a new game
        if p.cur and cur > p.cur and p.tickAt and bases == p.bases then
          Learn(p, bases, cur - p.cur, now - p.tickAt)
        elseif bases ~= p.bases then
          p.lastD, p.lastDt = nil, nil
        end
        if cur ~= p.cur or not p.tickAt then p.tickAt = now end
        if bases ~= p.bases then p.basesAt = now end
        p.cur, p.bases, p.max = cur, bases, max or p.max
      else
        table.insert(extra, text)
      end
    end
  end
  TM.extra = extra
  if B.zone == "AB" then TM:Predict(now) end
end

-- Plays Arathi Basin forward. pred = { winner, at (GetTime of the win), score
-- (the loser's points then), others = { [fac] = when that side reaches the
-- end } } or nil when nobody is scoring.
function TM:Predict(now)
  local A, H = P.Alliance, P.Horde
  self.pred = nil
  A.eta, H.eta = nil, nil
  if not A.cur or not H.cur then return end
  local max = A.max or H.max or 2000
  local sim = {}
  for fac, p in pairs(P) do
    sim[fac] = { cur = p.cur, bases = p.bases or 0, last = p.tickAt or now, fac = fac }
  end
  local caps = {}
  for _, n in pairs(O.nodes) do
    if n.ends and n.ends > now and n.by and sim[n.by] then table.insert(caps, { t = n.ends, by = n.by }) end
  end
  table.sort(caps, function(a, b) return a.t < b.t end)
  local nextCap = 1
  local t = now
  local pred
  for _ = 1, 2000 do
    -- the earliest thing to happen: a base flipping, or a side's next tick
    local at, who = nil, nil
    for fac, s in pairs(sim) do
      local k = (s.bases > 0) and self:Tick(math.min(s.bases, 5))
      if k and not s.done then
        local due = math.max(t, s.last + k[2])
        if not at or due < at then at, who = due, s end
      end
    end
    local cap = caps[nextCap]
    if cap and (not at or cap.t <= at) then
      t = cap.t
      local s = sim[cap.by]
      if s.bases == 0 then s.last = t end    -- a side with no base starts counting now
      s.bases = s.bases + 1
      nextCap = nextCap + 1
    elseif at then
      t = at
      local k = self:Tick(math.min(who.bases, 5))
      who.cur = who.cur + k[1]
      who.last = t
      if who.cur >= max then
        who.done = true
        P[who.fac].eta = t - now
        if not pred then
          local other = sim[(who.fac == "Alliance") and "Horde" or "Alliance"]
          pred = { winner = who.fac, at = t, score = other.cur, max = max }
        end
        local other = sim[(who.fac == "Alliance") and "Horde" or "Alliance"]
        if other.done or other.bases == 0 then break end
      end
    else
      break
    end
  end
  self.pred = pred
end

-- ---------------------------------------------------------------- rows

local function Entry(n)
  local e = TM.pool[n]
  if not e then
    e = {}
    TM.pool[n] = e
  end
  e.icon, e.coords, e.label, e.text, e.value, e.color, e.labelFac, e.say = nil, nil, nil, nil, nil, nil, nil, nil
  return e
end

-- POI icon of a landmark (cached on the landmark, which Map rebuilds every 2 s).
local function PoiCoords(name)
  local m = M:FindLandmark(name)
  if not m or not m.tex or not WorldMap_GetPOITextureCoords then return nil end
  if not m.coords then
    local l, r, t, b = WorldMap_GetPOITextureCoords(m.tex)
    m.coords = { l, r, t, b }
  end
  return m.coords
end

function TM:Collect(now)
  local n = 0
  local e
  if O.start and O.start > now then
    n = n + 1
    e = Entry(n)
    e.icon, e.label, e.text = ICON_WATCH, "Battle begins", U.Time(O.start - now)
    e.value, e.color = 1 - (O.start - now) / 120, { 0.8, 0.8, 0.8 }
    e.say = "Battle begins in " .. Words(O.start - now)
  end

  if B.zone == "AB" and B.BGScore and B.BGScore:Shows("nodes") then
    -- the score panel's base row has these
  elseif B.zone == "AB" then
    for i = 1, table.getn(AB_NODES) do
      local name = AB_NODES[i]
      local node = O.nodes[name]
      n = n + 1
      e = Entry(n)
      e.label = name
      local coords = PoiCoords(name)
      if coords then e.icon, e.coords = POI, coords end
      if node and node.ends and node.ends > now then
        e.text = U.Time(node.ends - now)
        e.value = 1 - (node.ends - now) / node.dur
        e.color = U.FACTION[node.by]
        e.say = name .. ": " .. (node.by or "?") .. " takes it in " .. Words(node.ends - now)
      elseif node and node.owner then
        e.say = name .. ": held by " .. node.owner
      else
        e.say = name .. ": nobody has it"
      end
      if node and node.owner then e.labelFac = node.owner end
    end
  else
    for name, node in pairs(O.nodes) do
      if node.ends and node.ends > now and n < MAX_ROWS - 4 then
        n = n + 1
        e = Entry(n)
        e.label, e.text = name, U.Time(node.ends - now)
        e.value, e.color = 1 - (node.ends - now) / node.dur, U.FACTION[node.by]
        e.say = name .. ": " .. (node.by or "?") .. " in " .. Words(node.ends - now)
        local coords = PoiCoords(name)
        if coords then e.icon, e.coords = POI, coords end
      end
    end
  end

  if B.db.timers.predict and B.zone == "AB" and not (B.BGScore and B.BGScore:Shows("predict")) then
    local pr = self.pred
    for _, fac in ipairs({ "Alliance", "Horde" }) do
      local p = P[fac]
      if p.cur then
        n = n + 1
        e = Entry(n)
        e.icon, e.label = U.FLAG[fac], p.cur .. "/" .. (p.max or "?")
        local wins = pr and pr.winner == fac
        e.text = wins and ("wins " .. U.Time(pr.at - now)) or ""
        e.value, e.color = p.cur / (p.max or 2000), U.FACTION[fac]
        if wins then
          e.say = fac .. " wins in " .. Words(pr.at - now) .. " (" .. pr.max .. " to " .. pr.score .. ")"
        else
          e.say = fac .. " " .. e.label
        end
      end
    end
  end

  -- one wave for the whole game: the score panel's row says it (per graveyard only if they differ)
  if B.db.timers.spirit and (S.perGuide or not (B.BGScore and B.BGScore:Shows("graveyard"))) then
    local list = {}
    for _, g in pairs(S.guides) do
      if g.anchor then table.insert(list, g) end
    end
    table.sort(list, function(a, b) return (a.faction or "") < (b.faction or "") end)
    for i = 1, math.min(table.getn(list), 6) do
      local g = list[i]
      local rem = S:Remaining(g, now)
      n = n + 1
      e = Entry(n)
      e.icon, e.label, e.text = ICON_RES, S:Label(g, now), U.Time(rem)
      e.value, e.color = 1 - rem / WAVE, U.FACTION[g.faction] or { 0.7, 0.7, 0.7 }
      e.say = e.label .. ": next res wave in " .. Words(rem)
    end
  end
  return n
end

-- Sample rows for layout mode.
function TM:Samples(now)
  local n = 0
  local e
  local data = {
    { ICON_WATCH, "Battle begins", 45, 120, { 0.8, 0.8, 0.8 } },
    { POI, "Stables", 37, 60, U.FACTION.Horde },
    { POI, "Blacksmith", 12, 60, U.FACTION.Alliance },
    { ICON_RES, "Alliance graveyard", 8, 30, U.FACTION.Alliance },
    { ICON_RES, "Horde graveyard", 21, 30, U.FACTION.Horde },
  }
  for i = 1, table.getn(data) do
    local d = data[i]
    local rem = d[4] - math.mod(now + d[3], d[4])
    n = n + 1
    e = Entry(n)
    e.icon, e.label, e.text = d[1], d[2], U.Time(rem)
    if d[1] == POI and WorldMap_GetPOITextureCoords then
      local l, r, t, b = WorldMap_GetPOITextureCoords(i == 2 and 38 or 27)
      e.coords = { l, r, t, b }
    end
    e.value, e.color = 1 - rem / d[4], d[5]
  end
  return n
end

-- ---------------------------------------------------------------- UI

function TM:Build()
  local f = U.Panel("OctoBGTimers", "timers", "Timers", WIDTH, ROW_H * 5 + 4, "RIGHT", -40, 120)
  U.Backdrop(f, 0.7)
  f:Hide()
  self.frame = f
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetWidth(WIDTH - 4)
    r:SetHeight(ROW_H - 1)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2 - (i - 1) * ROW_H)
    r.bar = U.Tex(r, U.WHITE, "BACKGROUND")
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", ROW_H, 0)
    r.bar:SetHeight(ROW_H - 1)
    r.icon = U.Tex(r, nil, "ARTWORK")
    r.icon:SetWidth(ROW_H - 2)
    r.icon:SetHeight(ROW_H - 2)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label = U.Text(r, 10, U.NARROW)
    r.label:SetPoint("LEFT", r, "LEFT", ROW_H + 3, 0)
    r.label:SetJustifyH("LEFT")
    r.text = U.Text(r, 11)
    r.text:SetPoint("RIGHT", r, "RIGHT", -3, 0)
    -- hover glow (the HIGHLIGHT layer shows while the mouse is on a button);
    -- click says the row in /bg
    r.hl = U.Tex(r, B.W.ART.glow, "HIGHLIGHT")
    r.hl:SetAllPoints(r)
    r.hl:SetBlendMode("ADD")
    r.hl:SetAlpha(0.5)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function()
      if this.say then U.SendBG(this.say) end
    end)
    r:SetScript("OnEnter", function()
      if not this.say then return end
      GameTooltip:SetOwner(this, "ANCHOR_LEFT")
      GameTooltip:AddLine("Click: say it in /bg", 1, 0.82, 0)
      GameTooltip:AddLine(this.say, 1, 1, 1, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    self.rows[i] = r
  end

  local big = U.Panel("OctoBGRes", "res", "Resurrection timer", 300, 40, "CENTER", 0, 140)
  big:Hide()
  big.text = U.Text(big, 24)
  big.text:SetPoint("CENTER", big, "CENTER", 0, 0)
  self.big = big
end

function TM:Paint(now)
  local f = self.frame
  if not f then return end
  local n = 0
  if B.db.timers.enabled then
    if B.test and not B.zone then n = self:Samples(now) else n = self:Collect(now) end
  end
  if n > MAX_ROWS then n = MAX_ROWS end
  if n == 0 then
    if f:IsShown() then f:Hide() end
  else
    f:SetHeight(n * ROW_H + 4)
    if not f:IsShown() then f:Show() end
  end
  local barW = WIDTH - 4 - ROW_H
  for i = 1, MAX_ROWS do
    local r = self.rows[i]
    local e = (i <= n) and self.pool[i]
    if e then
      if e.icon then
        r.icon:SetTexture(e.icon)
        if e.coords then
          r.icon:SetTexCoord(e.coords[1], e.coords[2], e.coords[3], e.coords[4])
        else
          r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        r.icon:Show()
      else
        r.icon:Hide()
      end
      r.label:SetText(e.label or "")
      r.text:SetText(e.text or "")
      local onBar = e.value and e.color
      if onBar then
        local v = math.max(0.01, math.min(1, e.value))
        r.bar:SetWidth(barW * v)
        r.bar:SetVertexColor(e.color[1], e.color[2], e.color[3], 0.55)
        r.bar:Show()
      else
        r.bar:Hide()
      end
      -- white on a bar (the bar already shows the side); a light faction
      -- colour on the dark panel for who holds a base
      local lc = (not onBar) and e.labelFac and TEXT[e.labelFac]
      if lc then r.label:SetTextColor(lc[1], lc[2], lc[3]) else r.label:SetTextColor(1, 1, 1) end
      r.say = e.say
      r:Show()
    else
      r:Hide()
    end
  end

  -- the big resurrection countdown
  local big = self.big
  local show, msg = false, nil
  if B.db.timers.big then
    if B.test then
      show, msg = true, "Resurrection in |cffffd100" .. U.Time(WAVE - math.mod(now, WAVE)) .. "|r"
    elseif B:IsBG() and UnitIsDeadOrGhost("player") then
      local t = S:MyWave(now)
      if t then
        show = true
        if UnitIsGhost("player") then
          msg = "Resurrection in |cffffd100" .. U.Time(t) .. "|r"
        else
          msg = "Release - next wave in |cffffd100" .. U.Time(t) .. "|r"
        end
      end
    end
  end
  if show then
    big.text:SetText(msg)
    if not big:IsShown() then big:Show() end
  elseif big:IsShown() then
    big:Hide()
  end
end

B:Every(0.1, function() TM:Paint(GetTime()) end, true)
B:Every(1, function()
  local now = GetTime()
  S:Prune(now)
  -- in a spirit healer's range the game's own timer is exact: keep to it
  if S.areaWave and GetAreaSpiritHealerTime then
    local t = GetAreaSpiritHealerTime()
    if t and t > 0 then
      S.areaWave = now + t
      S:Confirm(S.areaWave, "area")
      local g = S:Nearest()
      if g then g.anchor = S.areaWave end
    end
  end
  O:ScoreTick()
end, true)

B:On("OBG_INIT", function() TM:Build() end)

B:On("UPDATE_WORLD_STATES", function() O:ScoreTick() end, true)

-- How sure the wave is, and how good the game clock's guess was.
B:Command("reswave", "the battleground's resurrection wave: how it is known", function()
  local r = S:Global(GetTime())
  if S.perGuide then
    B:Print("res wave: graveyards here heal out of step - timed per graveyard")
  elseif not r then
    B:Print("res wave: only known inside a battleground")
  else
    B:Print(string.format("res wave: next in %.1f s, from %s", r,
      (S.waveSrc == "area" and "the spirit healer's timer") or (S.waveSrc == "seen" and "a heal you saw")
      or (S.waveSrc == "team" and "a teammate's OctoBG") or "the game's clock"))
    if S.clockErr then B:Print(string.format("the game's clock was %.2f s off the real wave", S.clockErr)) end
  end
end)

B:On("OBG_ZONE", function()
  S.guides, S.n, S.areaWave = {}, 0, nil
  S.waveAt, S.waveSrc, S.waveGuide, S.conflicts, S.perGuide, S.clockErr = nil, nil, nil, nil, nil, nil
  O.nodes, O.start, O.begunAt = {}, nil, nil
  P.Alliance, P.Horde = {}, {}
  TM.pred, TM.extra = nil, {}
  TM:Paint(GetTime())
end)

B:On("OBG_LAYOUT", function() TM:Paint(GetTime()) end)
