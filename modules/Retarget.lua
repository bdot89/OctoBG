-- OctoBG :: keep your target through Feign Death, Vanish and stealth
-- Feign Death clears every enemy's target on the hunter. When you lose your
-- target within WINDOW seconds of that enemy feigning, OctoBG targets them
-- again (SuperWoW GUID, else the exact name). Feign Death is spell 5384 on
-- this server (EnemyCooldowns' harvested data); the combat logs show its cast
-- (SPELL_GO), the aura going on (BUFF_ADD) and coming off when they stand up.
--
-- Rogues (and druids): Vanish or Stealth drops your target too, but they are
-- gone from the client, so OctoBG waits. If they show again within
-- db.retarget.rogueTime seconds (they open on someone, stealth breaks, you
-- detect them, a flare), they are your target again - or your focus, as set.
--
-- Hunter's Mark (ranks 1-4: 1130, 14323, 14324, 14325, two minutes; Cursive's
-- spell data): an enemy rogue or druid with the mark is picked up when the
-- mark goes on, when they come into view with it, when they come back after
-- stealth, and when they stealth while you still see them (the hunter who
-- marked them sees through stealth).
--
-- It never fights you: OctoBG only targets while you have no target, so
-- clearing it yourself and then picking someone else is left alone. Focus
-- does not touch your target, so it is set either way.

local B = OctoBG
local U = B.U
local R = {
  feigned = {},     -- guid -> GetTime() Feign Death started (cleared when they stand up)
  stealthed = {},   -- guid -> { at, kind } Vanish / Stealth / Prowl seen
  marked = {},      -- guid -> { at, name, gone, stealthAt } enemy rogues / druids with Hunter's Mark
  nmarked = 0,
  acted = {},       -- guid -> GetTime() last targeted / focused here
}
B.Retarget = R

B.DEFAULTS.retarget = { enabled = true, notify = true, rogue = true, rogueTime = 20, mark = true, rogueDo = "target" }

local FEIGN_DEATH = 5384
local WINDOW = 1.5
local HUNTERS_MARK = { [1130] = true, [14323] = true, [14324] = true, [14325] = true }
local MARK_TIME, MARK_MAX = 120, 40
local STEALTHERS = { ROGUE = true, DRUID = true }
R.HUNTERS_MARK = HUNTERS_MARK

R.DO = { { key = "target", label = "Target them" }, { key = "focus", label = "Make them my focus" },
         { key = "both", label = "Target and focus" } }

local function DB() return B.db and B.db.retarget end
local function Marking() return DB() and DB().mark end

local function Say(text)
  if DB().notify then UIErrorsFrame:AddMessage(text, 0.67, 0.83, 0.45) end
end

-- Hunter's Mark among the unit's auras (nampower's aura field): true or
-- false, nil when the client cannot tell.
function R.HasMark(guid)
  local auras = B.Tracker.Field(guid, "aura")
  if type(auras) ~= "table" then return nil end
  for i = 1, 48 do
    if auras[i] and HUNTERS_MARK[auras[i]] then return true end
  end
  return false
end

-- Target and / or focus an enemy who showed again.
function R:Act(guid, name, why)
  local now = GetTime()
  if self.acted[guid] and now - self.acted[guid] < 2 then return end
  if not U.GuidExists(guid) or U.GuidOf("target") == guid then return end
  self.acted[guid] = now
  name = name or UnitName(guid) or "?"
  local db = DB()
  local focused
  if db.rogueDo ~= "target" and B.Focus and B.Focus:Get() ~= guid then
    B.Focus:Set(guid, name)   -- says "Focus: Name" itself
    focused = true
  end
  if db.rogueDo ~= "focus" and not UnitExists("target") and U.TargetGuidOrName(guid, name) then
    Say("Target: " .. name .. " (" .. why .. ")")
    return
  end
  if not focused then Say(name .. " is back (" .. why .. ")") end
end

-- ---------------------------------------------------------------- lost target

function R:Try()
  local lost = self.lost
  if not lost then return end
  if GetTime() - lost.at > WINDOW or UnitExists("target") then   -- too late, or you picked something
    self.lost = nil
    return
  end
  local db = DB()
  local t = self.feigned[lost.guid]
  if db.enabled and t and math.abs(t - lost.at) <= WINDOW then
    self.lost = nil
    if U.TargetGuidOrName(lost.guid, lost.name) then Say("Target kept: " .. lost.name .. " (Feign Death)") end
    return
  end
  if not db.rogue then return end
  -- Vanish / Stealth: the stealth event, or a rogue who just left the object
  -- list (the event can be missed; a dead rogue stays as a corpse)
  local s = self.stealthed[lost.guid]
  local fresh = s and math.abs(s.at - lost.at) <= WINDOW
  if fresh or (lost.class == "ROGUE" and not U.GuidExists(lost.guid)) then
    self.lost = nil
    self:Hunt(lost.guid, lost.name, fresh and s.kind or "stealth")   -- a late stealth event names it (Stealthed)
  end
  -- else: not a Feign Death or stealth (yet) - Try runs again in 0.1 s
end

-- Wait for a stealthed enemy to show again.
function R:Hunt(guid, name, kind)
  local now = GetTime()
  self.hunt = { guid = guid, name = name, kind = kind or "stealth", at = now, due = now + DB().rogueTime,
                gone = not U.GuidExists(guid) }
end

function R:Watch()
  local h = self.hunt
  local now = GetTime()
  if now > h.due then
    self.hunt = nil
  elseif not U.GuidExists(h.guid) then
    h.gone = true
  elseif h.gone or now - h.at > 0.6 then
    -- back in view; or never gone after 0.6 s: you can see them in stealth
    -- (detection range, Hunter's Mark)
    self.hunt = nil
    self:Act(h.guid, h.name, "back from " .. h.kind)
  end
end

B:On("PLAYER_TARGET_CHANGED", function()
  local db = DB()
  if not db or not (db.enabled or db.rogue) then return end
  local g = U.GuidOf("target")
  if g and UnitExists("target") then
    if UnitIsPlayer("target") and UnitCanAttack("player", "target") then
      local _, class = UnitClass("target")
      R.cur = { guid = g, name = UnitName("target"), class = class }
    else
      R.cur = nil
    end
    return
  end
  if R.cur then
    R.lost = { guid = R.cur.guid, name = R.cur.name, class = R.cur.class, at = GetTime() }
    R.cur = nil
    R:Try()
  end
end)

-- ---------------------------------------------------------------- Hunter's Mark

local function Unmark(guid)
  if R.marked[guid] then
    R.marked[guid] = nil
    R.nmarked = R.nmarked - 1
  end
end

local function Mark(guid)
  if not U.IsGuid(guid) or not U.GuidExists(guid) or not UnitIsPlayer(guid) then return end
  if not UnitCanAttack("player", guid) then return end
  local _, class = UnitClass(guid)
  if not STEALTHERS[class] then return end
  local m = R.marked[guid]
  local fresh = not m
  if fresh then
    if R.nmarked >= MARK_MAX then return end
    m = {}
    R.marked[guid] = m
    R.nmarked = R.nmarked + 1
  end
  m.at, m.name, m.gone = GetTime(), UnitName(guid), false
  if fresh then R:Act(guid, m.name, "Hunter's Mark") end
end

function R:WatchMarks()
  local now = GetTime()
  for guid, m in pairs(self.marked) do
    if now - m.at > MARK_TIME then
      Unmark(guid)
    elseif not U.GuidExists(guid) then
      m.gone = true
    elseif m.gone then
      m.gone = false
      if R.HasMark(guid) == false then Unmark(guid) else self:Act(guid, m.name, "Hunter's Mark") end
    elseif m.stealthAt and now - m.stealthAt > 0.6 then
      m.stealthAt = nil
      self:Act(guid, m.name, "Hunter's Mark, in stealth")
    end
  end
end

-- ---------------------------------------------------------------- events

local function Feigned(guid)
  if not guid or not DB() or not DB().enabled then return end
  -- the cast, the aura and SuperWoW's event arrive together: keep the first;
  -- an older mark (its stand-up was missed) is replaced
  local t = R.feigned[guid]
  if not t or GetTime() - t > 3 then R.feigned[guid] = GetTime() end
  R:Try()
end

local function Stealthed(guid, spell)
  local db = DB()
  if not guid or not db or not (db.rogue or db.mark) then return end
  local now = GetTime()
  -- Vanish puts a Stealth aura on as well: the first name counts
  local s = R.stealthed[guid]
  if not s or now - s.at > 3 then
    s = { at = now, kind = B.Tracker.STEALTH[spell] }
    R.stealthed[guid] = s
  end
  local h = R.hunt
  if h and h.guid == guid and now - h.at <= WINDOW then h.kind = s.kind end
  local m = R.marked[guid]
  if m and not m.stealthAt then m.stealthAt = now end
  R:Try()
end

-- nampower: SPELL_GO_OTHER item, spell, caster, target; BUFF / DEBUFF_ADDED /
-- REMOVED_OTHER unit, slot, spell
B:On("SPELL_GO_OTHER", function(ev, item, spell, caster, target)
  if spell == FEIGN_DEATH then
    Feigned(caster)
  elseif B.Tracker.STEALTH[spell] then
    Stealthed(caster, spell)
  elseif HUNTERS_MARK[spell] and Marking() then
    Mark(target)
  end
end)
B:On("BUFF_ADDED_OTHER", function(ev, guid, a2, spell)
  if spell == FEIGN_DEATH then
    Feigned(guid)
  elseif B.Tracker.STEALTH[spell] then
    Stealthed(guid, spell)
  end
end)
B:On("BUFF_REMOVED_OTHER", function(ev, guid, a2, spell)
  if spell == FEIGN_DEATH and guid then R.feigned[guid] = nil end
end)
B:On("DEBUFF_ADDED_OTHER", function(ev, guid, a2, spell)
  if HUNTERS_MARK[spell] and Marking() then Mark(guid) end
end)
B:On("DEBUFF_REMOVED_OTHER", function(ev, guid, a2, spell)
  -- a unit leaving view may report its auras gone: only one still in view lost the mark
  if HUNTERS_MARK[spell] and guid and U.GuidExists(guid) then Unmark(guid) end
end)
-- SuperWoW sees the casts too (also without nampower's events)
B:On("UNIT_CASTEVENT", function(ev, caster, target, kind, spell)
  if kind ~= "CAST" then return end
  if spell == FEIGN_DEATH then
    Feigned(caster)
  elseif B.Tracker.STEALTH[spell] then
    Stealthed(caster, spell)
  elseif HUNTERS_MARK[spell] and Marking() then
    Mark(target)
  end
end)
-- an enemy rogue or druid walking into view already marked (the tracker's
-- new-enemy message; it runs where OctoBG is active)
B:On("OBG_ENEMY", function(ev, guid)
  local u = B.Tracker.units[guid]
  if u and not u.fake and STEALTHERS[u.class] and Marking() and R.HasMark(guid) then Mark(guid) end
end)
B:On("UNIT_DIED", function(ev, guid)
  if guid then
    Unmark(guid)
    if R.hunt and R.hunt.guid == guid then R.hunt = nil end
  end
end)

-- The target can drop just before the cast event arrives: look again shortly.
B:Every(0.1, function()
  if R.lost then R:Try() end
  if R.hunt then R:Watch() end
end)
B:Every(0.2, function()
  if R.nmarked > 0 then R:WatchMarks() end
end)
-- Eviction: Feign Death and stealth marks older than a minute go, acted after
-- 10 s; Hunter's Marks after two minutes (WatchMarks), at most 40, death.
B:Every(10, function()
  local now = GetTime()
  for g, t in pairs(R.feigned) do
    if now - t > 60 then R.feigned[g] = nil end
  end
  for g, s in pairs(R.stealthed) do
    if now - s.at > 60 then R.stealthed[g] = nil end
  end
  for g, t in pairs(R.acted) do
    if now - t > 10 then R.acted[g] = nil end
  end
end)

B:On("OBG_ZONE", function()
  R.feigned, R.stealthed, R.marked, R.nmarked, R.acted = {}, {}, {}, 0, {}
  R.lost, R.cur, R.hunt = nil, nil, nil
end)
