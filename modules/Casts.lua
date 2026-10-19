-- OctoBG :: enemy casts
-- What each enemy is casting right now, from SuperWoW's UNIT_CASTEVENT
-- (caster, target, "START" / "CAST" / "CHANNEL" / "FAIL", spell id, cast time
-- in ms - the same event and units pfUI's castbars use). Only data: the
-- enemy list and the focus strip draw it; pfUI already draws target, focus
-- and nameplate castbars, so OctoBG does not draw those again.

local B = OctoBG
local U = B.U
local CS = { db = {} }   -- guid -> { spell, icon, id, start, dur, channel }
B.Casts = CS

B:On("UNIT_CASTEVENT", function(ev, caster, target, kind, spellID, ms)
  if not caster or not B.db then return end
  if kind == "START" or kind == "CHANNEL" then
    if not ms or ms <= 0 or not UnitCanAttack("player", caster) then return end
    local name, icon
    if SpellInfo then
      local n, _, t = SpellInfo(spellID)
      name, icon = n, t
    end
    local c = CS.db[caster]
    if not c then
      c = {}
      CS.db[caster] = c
    end
    c.spell, c.icon, c.id = name or "?", icon, spellID
    c.start, c.dur, c.channel = GetTime(), ms / 1000, (kind == "CHANNEL")
  elseif kind == "CAST" then
    -- a finished cast; instant procs during a cast (other ids) leave it alone
    local c = CS.db[caster]
    if c and not c.channel and c.id == spellID then CS.db[caster] = nil end
  elseif kind == "FAIL" then
    CS.db[caster] = nil
  end
end)

-- spell, icon, progress 0..1, seconds left, channel - or nil
function CS:Get(guid)
  local c = guid and self.db[guid]
  if not c then return nil end
  local el = GetTime() - c.start
  if c.loop then el = math.mod(el, c.dur) end
  if el >= c.dur then
    self.db[guid] = nil
    return nil
  end
  return c.spell, c.icon, el / c.dur, c.dur - el, c.channel
end

-- Eviction: finished casts go on read and in this sweep; a zone change clears all.
B:Every(5, function()
  local now = GetTime()
  for g, c in pairs(CS.db) do
    if not c.loop and now - c.start > c.dur then CS.db[g] = nil end
  end
end)

B:On("OBG_ZONE", function() CS.db = {} end)

-- Sample casts for layout mode (the tracker's sample enemies)
B:On("OBG_LAYOUT", function(ev, on)
  if on then
    CS.db.sample2 = { spell = "Greater Heal", icon = "Interface\\Icons\\Spell_Holy_GreaterHeal", id = 0,
                      start = GetTime(), dur = 2.5, channel = false, loop = true }
  else
    CS.db.sample2 = nil
  end
end)
